// ═══════════════════════════════════════════════════════════════════════════
//  B5c — R-DR-03 — RÉCUPÉRATION DES RÉSULTATS OFFICIELS ET RESET
//
//  OBJET : garantir qu'une récupération de résultats officiels commencée
//  avant un reset ne puisse, après celui-ci, réintroduire des données
//  obsolètes ni déclencher un apprentissage IA non autorisé.
//
//  DÉFAUT AUDITÉ (avant correction) : `_recupererResultatsBatch` attend
//  `_fetchArriveeOfficielle(...)`, un appel RÉSEAU. Cette suspension n'est
//  enregistrée dans AUCUN registre de drainage — contrairement à `_save()`
//  qui, lui, est drainé par toutes les barrières. Un reset complet peut donc
//  s'exécuter ENTIÈREMENT pendant l'attente réseau. Au retour :
//    • `_pronostics[idx]` était réécrit (RAM repeuplée après vidage) ;
//    • `_save()` réécrivait les clés effacées ;
//    • `_apprendreParGradient()` MODIFIAIT `_poids` et `_seuils` sur un état
//      disparu → apprentissage obsolète non autorisé.
//
//  PÉRIMÈTRE : R-DR-03 uniquement. Aucun calcul IA, aucune formule, aucun
//  poids, aucun seuil, aucun critère, aucun TOP3 modifié.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ── Store contrôlable : suspensions ciblées sur les écritures ──────────────
class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  String? _cleSuspendue;
  Completer<void>? _entreeSet;
  Completer<void>? _verrouSet;

  @override
  Future<bool> clear() async {
    journal.add('CLEAR');
    _valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    journal.add('GETALL');
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET $key');
    if (_cleSuspendue != null && key == _cleSuspendue) {
      final entree = _entreeSet;
      _entreeSet = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      await _verrouSet!.future;
    }
    _valeurs[key] = value;
    return true;
  }

  /// Suspend le prochain `setValue` sur [cle] (nom SANS préfixe `flutter.`).
  Completer<void> armerSuspensionSet(String cle) {
    final entree = Completer<void>();
    _entreeSet = entree;
    _verrouSet = Completer<void>();
    _cleSuspendue = 'flutter.$cle';
    return entree;
  }

  void libererSet() {
    final v = _verrouSet;
    _verrouSet = null;
    _cleSuspendue = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  List<String> clesCache() => _valeurs.keys
      .where((k) => k.startsWith('flutter.cache_reunions_'))
      .map((k) => k.replaceFirst('flutter.', ''))
      .toList()
    ..sort();

  /// Clés qui ne devraient JAMAIS survivre à un reset.
  List<String> clesDonneesIa() => _valeurs.keys
      .where((k) => k.startsWith('flutter.ia_') ||
          k.startsWith('flutter.ia_pronostics_v2'))
      .map((k) => k.replaceFirst('flutter.', ''))
      .toList()
    ..sort();
}

// ignore: library_private_types_in_public_api
late _Store store;

Future<void> _laisserProgresser([int tours = 80]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<bool> _attendreQue(bool Function() c, [int max = 3000]) async {
  for (var i = 0; i < max; i++) {
    if (c()) return true;
    await Future<void>.delayed(Duration.zero);
  }
  return c();
}

// ── Fixture : un programme d'une réunion, une course ───────────────────────
class _Scenario {
  String lieu;
  List<int> nums;
  String dateStr;

  /// Ancienneté du départ, en minutes. 20 min place la course dans la fenêtre
  /// de récupération de production : `courseDiff >= 10 min` et `<= 24 h`.
  /// Constante, comme `numR`/`numC` : tous les scénarios visent la MÊME
  /// fenêtre temporelle, sinon ils ne testeraient plus le même chemin.
  int get minutesDepuisDepart => 20;

  /// Suspension optionnelle de la récupération des RÉSULTATS (réseau).
  Completer<void>? verrouResultats;
  Completer<void>? entreeResultats;

  // `numR`/`numC` sont FIXES : le parseur de `_recupererResultatsBatch`
  // (RegExp `^R(\d+)C(\d+)_...`) et la fixture réseau ne sont cohérents que
  // sur R1C1. En faire des paramètres créerait une fausse modularité : un
  // appelant pourrait les changer sans que la fixture suive.
  int get numR => 1;
  int get numC => 1;

  _Scenario({this.lieu = 'VINCENNES', required this.nums,
      required this.dateStr});
}

String _programme(_Scenario s) {
  final depart = DateTime.now()
      .subtract(Duration(minutes: s.minutesDepuisDepart))
      .millisecondsSinceEpoch;
  return jsonEncode({
    'programme': {
      'reunions': [
        {
          'numOfficiel': s.numR,
          'hippodrome': {'libelleLong': '${s.lieu} (FRANCE)', 'libelleCourt': s.lieu},
          'courses': [
            {
              'numOrdre': s.numC,
              'libelle': 'PRIX RDR03',
              'discipline': 'ATTELE',
              'distance': 2100,
              'montantPrix': 30000,
              'paris': <Map<String, dynamic>>[],
              'heureDepart': depart,
            },
          ],
        },
      ],
    },
  });
}

String _participants(List<int> nums) => jsonEncode({
      'participants': [
        for (final n in nums)
          {
            'numPmu': n,
            'nom': 'CHEVAL_$n',
            'statut': 'PARTANT',
            'age': 5,
            'sexe': 'M',
          },
      ],
    });

/// Arrivée officielle : ordre [3, 1, 2].
///
/// ⚠️ FORMAT RÉEL de l'API PMU et de `_fetchArriveeOfficielle`
/// (data_refresh_service.dart:1228) : la racine est une **List** d'objets
/// `{typePari, rapports:[{combinaison, rapport}]}`. Une racine objet
/// provoquerait une erreur de cast (une Map n'est pas une List).
///
/// ⚠️ ADAPTATION DE FIXTURE — FINALISATION A6 (P4).
/// ANCIENNE FIXTURE : `E_SIMPLE_GAGNANT` (3) puis `E_SIMPLE_PLACE` (1, 2),
/// sans aucun rapport ORDONNÉ. `_fetchArriveeOfficielle` empilait alors le
/// gagnant puis l'ordre fourni par les PLACÉ, et rendait `[3, 1, 2]`.
/// Ce `[3, 1, 2]` n'était donc pas un ordre officiel : c'était l'ordre
/// d'énumération des rapports PLACÉ, pris à tort pour un classement.
/// Depuis A6, une telle arrivée est REFUSÉE (aucun rapport ordonné), donc
/// aucun résultat n'était plus enregistré et les témoins R-DR-03 de ce
/// fichier ne pouvaient plus s'armer — mesuré : R03-B et R03-E échouaient
/// sur leur TÉMOIN, pas sur leur assertion de fond.
/// NOUVELLE FIXTURE : un rapport `E_QUINTE_ORDRE` officiel publie l'ordre
/// `3-1-2` attendu par les trois assertions de ce fichier. Le scénario
/// (barrières R-DR-03) et ses témoins sont intégralement conservés ; seule
/// la source de l'arrivée devient conforme à ce que la production exige.
String _rapportsDefinitifs() => jsonEncode([
      {
        'typePari': 'E_SIMPLE_GAGNANT',
        'rapports': [
          {'combinaison': '3', 'rapport': 12.5},
        ],
      },
      {
        'typePari': 'E_SIMPLE_PLACE',
        'rapports': [
          {'combinaison': '1', 'rapport': 3.2},
          {'combinaison': '2', 'rapport': 4.8},
        ],
      },
      // ★ A6 : rapport ORDONNÉ officiel — seule source d'arrivée admise.
      {
        'typePari': 'E_QUINTE_ORDRE',
        'rapports': [
          {'combinaison': '3-1-2', 'rapport': 250.0},
        ],
      },
    ]);

/// Exécute [action] avec un réseau PMU simulé.
///
/// [urls] reçoit chaque URL réellement demandée.
Future<T> _avecScenario<T>(
  Future<T> Function() action,
  _Scenario s, {
  List<Uri>? urls,
  bool suspendreResultats = false,
}) {
  final client = MockClient((request) async {
    urls?.add(request.url);
    final p = request.url.path;

    if (p.contains('participants')) {
      return http.Response(_participants(s.nums), 200,
          headers: {'content-type': 'application/json'});
    }
    if (p.contains('rapports-definitifs')) {
      if (suspendreResultats) {
        final v = s.verrouResultats;
        if (v != null) {
          final e = s.entreeResultats;
          s.entreeResultats = null;
          s.verrouResultats = null;
          if (e != null && !e.isCompleted) e.complete();
          await v.future;
        }
      }
      return http.Response(_rapportsDefinitifs(), 200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response(_programme(s), 200,
        headers: {'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

/// Construit une clé de course au format attendu par le parseur.
String _cleCourse(_Scenario s) {
  final d = DateTime.now().subtract(Duration(minutes: s.minutesDepuisDepart));
  final dj = d.day.toString().padLeft(2, '0');
  final dm = d.month.toString().padLeft(2, '0');
  return 'R${s.numR}C${s.numC}_$dj$dm${d.year}';
}

/// Prépare l'état par le VRAI chemin de PRODUCTION : le pronostic est écrit
/// sur le disque au format exact que `_save()` utilise, puis le SERVICE le
/// charge par `_load()` — c'est-à-dire le chemin de démarrage réel de
/// l'application. Aucune injection dans l'état interne du service.
///
/// POURQUOI PAS un rafraîchissement ? `_enregistrerPronosticsAuto` calcule
/// les pronostics dans un ISOLATE (`compute`) : sur cette fixture minimale il
/// n'en produit aucun (mesuré : REUNIONS=1, PRONOS=0), ce qui rendrait la
/// précondition non déterministe. Le semis disque + chargement est, lui,
/// entièrement déterministe.
///
/// POURQUOI PAS `init()` SEUL ? `init()` appelle `_load()`, qui SORT
/// IMMÉDIATEMENT sur `if (_loaded) return;` (ia_memory_service.dart:1679).
/// `IaMemoryService` est un singleton : après le premier test du fichier
/// `_loaded` vaut `true`, et `SharedPreferences.resetStatic()` ne réinitialise
/// QUE le cache de `SharedPreferences`, jamais `_loaded`. Mesuré : avec
/// `init()` seul, les tests 2 à 5 lisaient 0 pronostic.
///
/// Le mécanisme OFFICIEL et DÉJÀ UTILISÉ par le projet pour forcer une
/// relecture disque est `recharger()` (V26-6, V27-3, V28 `setUp`) : c'est le
/// seul chemin PUBLIC qui repose `_loaded = false`, vide les collections RAM
/// puis rappelle `_load()`. Il n'est pas modifié ici : simple appelant.
Future<void> _preparerPronosticEnAttente(_Scenario s) async {
  final cle = _cleCourse(s);

  // Le disque doit être VIDE de tout autre état IA : `_load()` donne la
  // PRIORITÉ à `ia_pronostics_v2_gz` sur `ia_pronostics_v2` (l.1692-1726).
  // Un blob compressé résiduel masquerait le pronostic semé.
  expect(store.contient('ia_pronostics_v2_gz'), isFalse,
      reason: 'PRÉCONDITION : aucun blob compressé ne doit masquer le semis');

  final p = IaPronostic(
    courseKey: cle,
    nomCourse: 'PRIX RDR03',
    hippodrome: s.lieu,
    discipline: 'ATTELE',
    datePronostic: DateTime.now().subtract(const Duration(minutes: 20)),
    scoresIA: const {'1': 80.0, '2': 70.0, '3': 60.0},
    scoresCriteres: const {},
    confiancePredite: 70.0,
    resultatsReels: false,
    arriveeReelle: null,
  );

  // TÉMOIN 1 — le pronostic survit à l'aller-retour JSON que `_load()` fera.
  // `fromJson` est appelé dans un `try { } catch (_) { }` : une entrée
  // malformée serait silencieusement JETÉE. On prouve donc ici qu'elle ne
  // l'est pas, avant d'accuser le chargement.
  final relu = IaPronostic.fromJson(
      json.decode(jsonEncode(p.toJson())) as Map<String, dynamic>);
  expect(relu.courseKey, cle,
      reason: 'TÉMOIN 1 : `toJson`/`fromJson` préservent `courseKey`');
  expect(relu.resultatsReels, isFalse,
      reason: 'TÉMOIN 1 : le pronostic relu est bien en ATTENTE de résultat');

  // Format `_save()` : une List<String> de JSON, sous `ia_pronostics_v2`.
  store.semer('ia_pronostics_v2', <String>[jsonEncode(p.toJson())]);

  // `resetStatic()` invalide le cache de `SharedPreferences` ; `recharger()`
  // repose `_loaded = false` et relit réellement le disque.
  SharedPreferences.resetStatic();
  final getAllAvant = store.journal.where((e) => e == 'GETALL').length;
  await IaMemoryService.instance.recharger();

  // TÉMOIN 2 — le chargement a bien eu lieu.
  expect(store.journal.where((e) => e == 'GETALL').length,
      greaterThan(getAllAvant),
      reason: 'TÉMOIN 2 : le service a réellement relu le disque');

  // TÉMOIN 3 — et il a produit ce qu'on attend.
  expect(IaMemoryService.instance.pronostics.length, 1,
      reason: 'PRÉCONDITION : le service a chargé le pronostic semé sur le '
          'disque — c\'est le chemin de démarrage réel de l\'application');

  final charge = IaMemoryService.instance.pronostics.first;
  expect(charge.courseKey, cle,
      reason: 'PRÉCONDITION : le pronostic chargé est IDENTIFIABLE');
  expect(charge.resultatsReels, isFalse,
      reason: 'PRÉCONDITION : ce pronostic est en ATTENTE de résultat');
  expect(charge.arriveeReelle, isNull,
      reason: 'PRÉCONDITION : aucune arrivée officielle n\'est déjà connue');

  debugPrint('PRÉCONDITION OK : cle=$cle '
      'generationIa=${IaMemoryService.instance.generationCache} '
      'generationDr=${DataRefreshService.instance.generationCache} '
      'nbApprentissage=${IaMemoryService.instance.poids.nbMisesAJour}');
}

/// Photographie des poids, pour prouver qu'aucun apprentissage n'a eu lieu.
List<double> _poidsInstantane() {
  final p = IaMemoryService.instance;
  return <double>[
    p.poids.forme, p.poids.gains, p.poids.record, p.poids.cote,
    p.poids.constance, p.poids.victoires, p.poids.discipline,
    p.poids.distSpec, p.poids.jockey, p.poids.repos, p.poids.hippo,
    p.poids.entraineur, p.poids.elo, p.poids.terrain,
    p.poids.divergence, p.poids.poidsRel, p.poids.progression,
    p.poids.mouvCote, p.poids.placeDepart,
  ];
}

int _nbApprentissage() => IaMemoryService.instance.poids.nbMisesAJour;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    ZoneTurfService.viderCachePourResetComplet();
    DataRefreshService.instance.viderMemoirePourResetComplet();
  });

  tearDown(() {
    store.libererSet();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A — RESET PENDANT LA RÉCUPÉRATION RÉSEAU
  //
  //  C'est le défaut central : le réseau n'est dans aucun registre de
  //  drainage, donc le reset peut se terminer ENTIÈREMENT pendant l'attente.
  //  Au retour, rien ne doit être réintroduit.
  // ═══════════════════════════════════════════════════════════════════════
  test('R03-A — reset pendant la récupération réseau : aucun résultat réinjecté',
      () async {
    final s = _Scenario(nums: [1, 2, 3], dateStr: '01012026');
    final verrouResultats = Completer<void>();
    s.verrouResultats = verrouResultats;
    s.entreeResultats = Completer<void>();

    // L'état d'avant : un pronostic en attente de résultat, créé par le
    // chemin de production.
    await _preparerPronosticEnAttente(s);
    final poidsAvant = _poidsInstantane();
    final apprentissagesAvant = _nbApprentissage();

    final urls = <Uri>[];
    final refresh = _avecScenario(
      () => DataRefreshService.instance.refresh(),
      s,
      urls: urls,
      suspendreResultats: true,
    );

    // TÉMOIN : la requête de résultats est bien partie et reste suspendue.
    final suspendu = await _attendreQue(
        () => urls.any((u) => u.path.contains('rapports-definitifs')));
    expect(suspendu, isTrue,
        reason: 'TÉMOIN 1 : la récupération des résultats a interrogé le réseau '
            'et reste SUSPENDUE dessus');

    // ── Reset complet PENDANT cette suspension réseau ────────────────────
    //  Aucun registre ne voit ce `await` : le reset doit se terminer ici,
    //  sans être retenu. C'est ce qui rend la fenêtre exploitable.
    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser(120);

    final generationApresReset = DataRefreshService.instance.generationCache;
    expect(DataRefreshService.instance.reunions, isEmpty,
        reason: 'ÉTAT APRÈS RESET : la RAM des réunions est vidée');
    expect(DataRefreshService.instance.resetEnCours, isFalse,
        reason: 'PRÉCONDITION : le reset est TERMINÉ pendant que le réseau '
            'est encore suspendu — c\'est la fenêtre du défaut');

    // ── Libération du réseau : la reprise doit être refusée ──────────────
    verrouResultats.complete();
    await refresh;
    await _laisserProgresser(200);

    debugPrint('R03-A après reprise : '
        'pronostics=${IaMemoryService.instance.pronostics.length} '
        'apprentissages=${_nbApprentissage()} (avant=$apprentissagesAvant) '
        'generation=$generationApresReset');

    expect(IaMemoryService.instance.pronostics, isEmpty,
        reason: 'CORRECTION R-DR-03 — DISCRIMINANT : aucun pronostic n\'est '
            'réinjecté par la reprise. Sans la garde, `_pronostics[idx]` est '
            'réécrit APRÈS le vidage du reset');
    expect(_nbApprentissage(), apprentissagesAvant,
        reason: 'CORRECTION R-DR-03 — DISCRIMINANT : AUCUN apprentissage. Sans '
            'la garde, `_apprendreParGradient()` s\'exécute sur un état '
            'disparu et incrémente `nbMisesAJour`');
    expect(_poidsInstantane(), poidsAvant,
        reason: 'CORRECTION R-DR-03 : les poids sont INTACTS — aucun gradient '
            'obsolete n\'a été appliqué');
    expect(store.clesDonneesIa(), isEmpty,
        reason: 'CORRECTION R-DR-03 : aucune clé IA n\'est recréée sur le '
            'disque par la reprise obsolète');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B — RESET PENDANT LA SAUVEGARDE (après le réseau)
  //
  //  Ici le réseau a répondu, la mutation RAM a eu lieu AVANT le reset :
  //  c'est légitime. On vérifie que la SAUVEGARDE et l'APPRENTISSAGE qui
  //  suivent ne s'exécutent pas après le vidage.
  // ═══════════════════════════════════════════════════════════════════════
  test('R03-B — reset pendant la sauvegarde : ni disque ni apprentissage',
      () async {
    final s = _Scenario(nums: [1, 2, 3], dateStr: '01012026');
    await _preparerPronosticEnAttente(s);
    final apprentissagesAvant = _nbApprentissage();

    // On suspend la PREMIÈRE écriture de `_save()` (les poids), qui est
    // enregistrée au registre d'IaMemoryService.
    store.armerSuspensionSet('ia_poids_v3');
    final marque = store.journal.length;

    final refresh = _avecScenario(
        () => DataRefreshService.instance.refresh(), s);

    final ecritureSuspendue = await _attendreQue(() => store.journal
        .sublist(marque)
        .contains('SET flutter.ia_poids_v3'));
    expect(ecritureSuspendue, isTrue,
        reason: 'TÉMOIN : `_save()` a engagé son écriture et reste suspendu '
            'dessus — le réseau a donc déjà répondu');

    // Reset pendant cette suspension. Il DRAINE cette écriture : on ne
    // l'attend pas ici, sinon le test s'interbloquerait (la production,
    // elle, attend correctement).
    final reset = BackupService.instance.reinitialiserComplet();
    await _laisserProgresser(120);

    store.libererSet();
    await refresh;
    await reset;
    await _laisserProgresser(200);

    debugPrint('R03-B final : pronostics=${IaMemoryService.instance.pronostics.length} '
        'apprentissages=${_nbApprentissage()} (avant=$apprentissagesAvant) '
        'cles=${store.clesDonneesIa()}');

    expect(IaMemoryService.instance.pronostics, isEmpty,
        reason: 'INVARIANT R-DR-03 : le reset laisse une RAM vide');
    expect(store.clesDonneesIa(), isEmpty,
        reason: 'INVARIANT R-DR-03 : et un disque sans clé IA');
    expect(_nbApprentissage(), apprentissagesAvant,
        reason: 'CORRECTION R-DR-03 : l\'apprentissage qui suit la sauvegarde '
            'n\'est pas exécuté après le vidage');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  C — REPRISE D'UNE ANCIENNE OPÉRATION : génération transmise
  //
  //  On vérifie ici le contrat de `enregistrerResultat(generationAppelante:)`
  //  directement : une génération périmée est refusée SANS toucher la RAM,
  //  le disque ni les poids.
  // ═══════════════════════════════════════════════════════════════════════
  test('R03-C — enregistrerResultat refuse une génération périmée', () async {
    final s = _Scenario(nums: [1, 2, 3], dateStr: '01012026');
    await _preparerPronosticEnAttente(s);

    final generationObsolete =
        IaMemoryService.instance.generationCache - 1; // périmée par construction
    final poidsAvant = _poidsInstantane();
    final apprentissagesAvant = _nbApprentissage();
    final cle = _cleCourse(s);

    await IaMemoryService.instance.enregistrerResultat(
      courseKey: cle,
      arriveeReelle: const [3, 1, 2],
      generationAppelante: generationObsolete,
    );
    await _laisserProgresser(100);

    expect(IaMemoryService.instance.pronostics.length, 1,
        reason: 'CONTRAT R-DR-03 : le pronostic semé n\'est PAS modifié');
    expect(IaMemoryService.instance.pronostics.first.resultatsReels, isFalse,
        reason: 'CORRECTION R-DR-03 : le résultat n\'est pas enregistré — la '
            'génération périmée est refusée avant toute mutation');
    expect(_nbApprentissage(), apprentissagesAvant,
        reason: 'CORRECTION R-DR-03 : aucun apprentissage déclenché');
    expect(_poidsInstantane(), poidsAvant,
        reason: 'CORRECTION R-DR-03 : poids intacts');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D — ABSENCE D'APPRENTISSAGE OBSOLÈTE : génération courante acceptée
  //
  //  Non-régression indispensable : avec la génération COURANTE, le résultat
  //  doit être enregistré normalement et l'apprentissage exécuté. Sans ce
  //  test, une garde trop stricte passerait inaperçue.
  // ═══════════════════════════════════════════════════════════════════════
  test('R03-D — génération courante : le résultat est enregistré normalement',
      () async {
    final s = _Scenario(nums: [1, 2, 3], dateStr: '01012026');
    await _preparerPronosticEnAttente(s);
    final cle = _cleCourse(s);
    final apprentissagesAvant = _nbApprentissage();

    await IaMemoryService.instance.enregistrerResultat(
      courseKey: cle,
      arriveeReelle: const [3, 1, 2],
      generationAppelante: IaMemoryService.instance.generationCache,
    );
    await _laisserProgresser(200);

    final p = IaMemoryService.instance.pronostics.first;
    debugPrint('R03-D : resultatsReels=${p.resultatsReels} '
        'arrivee=${p.arriveeReelle} apprentissages=${_nbApprentissage()} '
        '(avant=$apprentissagesAvant)');

    expect(p.resultatsReels, isTrue,
        reason: 'NON-RÉGRESSION : le résultat est bien enregistré quand la '
            'génération est valide');
    expect(p.arriveeReelle, isNotNull,
        reason: 'NON-RÉGRESSION : l\'arrivée officielle est conservée');
    expect(store.clesDonneesIa(), isNotEmpty,
        reason: 'NON-RÉGRESSION : `_save()` a bien écrit sur le disque');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G — NON-RÉGRESSION DES APPELANTS SANS GÉNÉRATION TRANSMISE
  //
  //  Les TROIS appelants de production qui n'ont pas de capture propre
  //  gardent leur comportement, par construction :
  //    • lib/services/alert_service.dart:2654  (`_fetchResultatAuto`)
  //    • ia_memory_service.dart:1266           (rattrapage des résultats)
  //    • ia_memory_service.dart:1451           (`fetchArriveeDirecte`)
  //  Ils n'ont pas de génération à transmettre : la garde se calcule alors
  //  sur `_generationCache` COURANTE (`generationAppelante ?? …`). Elle est
  //  donc vraie et l'enregistrement a lieu. Ce test le prouve ; sans lui, une
  //  garde qui refuserait le cas « paramètre absent » gèlerait la récupération
  //  de résultats dans TOUTE l'application, et les cinq autres tests ne le
  //  verraient pas (ils passent tous le paramètre explicitement).
  // ═══════════════════════════════════════════════════════════════════════
  test('R03-G — appelant SANS génération transmise : enregistrement nominal',
      () async {
    final s = _Scenario(lieu: 'SANSG', nums: [1, 2, 3], dateStr: '01012026');
    await _preparerPronosticEnAttente(s);
    final cle = _cleCourse(s);

    // Exactement l'appel des trois appelants de production : rien de plus.
    await IaMemoryService.instance.enregistrerResultat(
      courseKey: cle,
      arriveeReelle: const [3, 1, 2],
    );
    await _laisserProgresser(200);

    final p = IaMemoryService.instance.pronostics
        .where((x) => x.courseKey == cle)
        .toList();
    debugPrint('R03-G : pronostics=${p.length} '
        'resultatsReels=${p.isNotEmpty && p.first.resultatsReels} '
        'arrivee=${p.isNotEmpty ? p.first.arriveeReelle : null}');

    expect(p, isNotEmpty, reason: 'NON-RÉGRESSION : le pronostic est présent');
    expect(p.first.resultatsReels, isTrue,
        reason: 'NON-RÉGRESSION ESSENTIELLE : sans paramètre, la garde se '
            'calcule sur la génération courante et laisse passer — sinon la '
            'récupération de résultats serait gelée dans toute l\'application');
    expect(p.first.arriveeReelle, isNotNull,
        reason: 'NON-RÉGRESSION : l\'arrivée officielle est bien enregistrée');
    expect(store.clesDonneesIa(), isNotEmpty,
        reason: 'NON-RÉGRESSION : `_save()` a écrit sur le disque');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  E — FONCTIONNEMENT NORMAL APRÈS RESET
  //
  //  La barrière doit être ROUVERTE : un rafraîchissement postérieur au reset
  //  doit fonctionner, et une récupération de résultats légitime aussi.
  // ═══════════════════════════════════════════════════════════════════════
  test('R03-E — après le reset, une récupération légitime fonctionne',
      () async {
    final s = _Scenario(lieu: 'APRES', nums: [1, 2, 3], dateStr: '01012026');

    // 1. Un premier cycle, puis un reset.
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _attendreQue(() => DataRefreshService.instance.reunions.isNotEmpty);
    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser(120);

    expect(DataRefreshService.instance.reunions, isEmpty, reason: 'TÉMOIN reset');
    expect(DataRefreshService.instance.resetEnCours, isFalse,
        reason: 'TÉMOIN : barrière rouverte');

    // 2. Un pronostic en attente APRÈS le reset, par le chemin de production.
    await _preparerPronosticEnAttente(s);
    final cle = _cleCourse(s);
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _laisserProgresser(300);

    final p = IaMemoryService.instance.pronostics
        .where((x) => x.courseKey == cle)
        .toList();
    debugPrint('R03-E : pronostics=${IaMemoryService.instance.pronostics.length} '
        'resultatsReels=${p.isNotEmpty && p.first.resultatsReels}');

    expect(p, isNotEmpty,
        reason: 'NON-RÉGRESSION : le pronostic post-reset est présent');
    expect(p.first.resultatsReels, isTrue,
        reason: 'NON-RÉGRESSION ESSENTIELLE : après le reset, la récupération '
            'des résultats fonctionne normalement — la garde ne gèle pas le '
            'service');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  F — DISCRIMINANT DÉCISIF : la MÊME course en attente après le reset
  //
  //  POURQUOI CE TEST EXISTE (mesuré, pas supposé) : dans le scénario A, la
  //  reprise obsolète est inerte pour une raison ACCIDENTELLE — le reset a vidé
  //  `_pronostics`, donc `indexWhere` rend `-1` et `enregistrerResultat` sort
  //  avant toute écriture. Cette inertie ne prouve aucune garantie : elle
  //  dépend de l'ordre des opérations, pas d'un contrôle.
  //
  //  Banc de mutations : M49 (contrôle DataRefresh APRÈS le réseau neutralisé
  //  ET génération non transmise) SURVIVAIT aux cinq autres tests. Ce test la
  //  tue.
  //
  //  Scénario RÉALISTE : reset, puis le pronostic est RESTAURÉ depuis le disque
  //  (chemin de démarrage de l'application — la course est toujours en attente,
  //  elle n'a pas de résultat), puis la récupération réseau de l'ANCIEN cycle
  //  reprend. Sans la garde, l'arrivée obsolète est écrite dans le pronostic
  //  restauré, `_save()` réécrit le disque et `_apprendreParGradient()`
  //  s'exécute : exactement le défaut R-DR-03.
  // ═══════════════════════════════════════════════════════════════════════
  test('R03-F — reprise obsolète sur une MÊME course restaurée : refusée',
      () async {
    final s = _Scenario(lieu: 'MEME', nums: [1, 2, 3], dateStr: '01012026');
    final verrouResultats = Completer<void>();
    s.verrouResultats = verrouResultats;
    s.entreeResultats = Completer<void>();
    final cle = _cleCourse(s);

    // 1. Cycle n°1 : pronostic en attente, génération d'IaMemoryService = N.
    await _preparerPronosticEnAttente(s);
    final generationAvantReset = IaMemoryService.instance.generationCache;

    // 2. Le cycle de récupération s'engage et se suspend sur le RÉSEAU.
    final urls = <Uri>[];
    final refreshAncien = _avecScenario(
      () => DataRefreshService.instance.refresh(),
      s,
      urls: urls,
      suspendreResultats: true,
    );
    final suspendu = await _attendreQue(
        () => urls.any((u) => u.path.contains('rapports-definitifs')));
    expect(suspendu, isTrue,
        reason: 'TÉMOIN 1 : l\'ancien cycle attend le réseau');

    // 3. Reset complet PENDANT cette attente.
    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser(120);
    expect(IaMemoryService.instance.generationCache,
        isNot(generationAvantReset),
        reason: 'TÉMOIN 2 : le reset a bien incrémenté la génération IA');

    // 4. La MÊME course est de nouveau EN ATTENTE après le reset : c'est le
    //    chemin de démarrage réel (le disque est relu au lancement).
    await _preparerPronosticEnAttente(s);
    expect(IaMemoryService.instance.pronostics.first.courseKey, cle);
    expect(IaMemoryService.instance.pronostics.first.resultatsReels, isFalse,
        reason: 'TÉMOIN 3 : la course est toujours en attente — le disque a été '
            'relu après le reset');

    final poidsAvant = _poidsInstantane();
    final apprentissagesAvant = _nbApprentissage();
    // ⚠️ `ia_pronostics_v2` est PRÉSENT ici, et c'est LÉGITIME : c'est l'état
    //    restauré à l'étape 4. On ne peut donc pas asserter « disque vide ».
    //    Ce qui est fautif est une RÉÉCRITURE par la reprise obsolète. On
    //    capture donc le contenu exact avant libération.
    final disqueAvantReprise = store.lire('ia_pronostics_v2');
    final pannesAvant = store.journal.length;

    // 5. Libération : l'ANCIEN cycle reprend sur un état qui a changé de
    //    génération. C'est ici que la garde doit refuser.
    verrouResultats.complete();
    await refreshAncien;
    await _laisserProgresser(240);

    final apres = IaMemoryService.instance.pronostics
        .where((x) => x.courseKey == cle)
        .toList();

    debugPrint('R03-F après reprise : pronostics=${apres.length} '
        'resultatsReels=${apres.isNotEmpty && apres.first.resultatsReels} '
        'apprentissages=${_nbApprentissage()} (avant=$apprentissagesAvant) '
        'ecritures=${store.journal.length - pannesAvant}');

    expect(apres, isNotEmpty,
        reason: 'TÉMOIN 4 : le pronostic restauré est toujours là — sinon '
            '« pas de résultat » ne prouverait rien');
    expect(apres.first.resultatsReels, isFalse,
        reason: 'CORRECTION R-DR-03 — DISCRIMINANT DÉCISIF : l\'arrivée de '
            'l\'ancien cycle n\'est PAS écrite dans le pronostic restauré. '
            'Sans la transmission de génération NI le contrôle après réseau, '
            '`indexWhere` retrouve cette course et l\'écriture a lieu');
    expect(apres.first.arriveeReelle, isNull,
        reason: 'CORRECTION R-DR-03 : aucune arrivée obsolète n\'est attachée');
    expect(_nbApprentissage(), apprentissagesAvant,
        reason: 'CORRECTION R-DR-03 : AUCUN apprentissage IA non autorisé');
    expect(_poidsInstantane(), poidsAvant,
        reason: 'CORRECTION R-DR-03 : poids INTACTS — aucun gradient obsolète');
    // Aucune écriture IA supplémentaire : `_save()` n'a pas été appelée.
    expect(store.lire('ia_pronostics_v2'), disqueAvantReprise,
        reason: 'CORRECTION R-DR-03 : la reprise obsolète n\'a RIEN écrit sur '
            'le disque — ni `_poidsKey` ni `_pronosticsKey` réécrits');
    expect(
        store.journal.skip(pannesAvant).where((e) =>
            e.startsWith('SET flutter.ia_') || e.startsWith('REM flutter.ia_')),
        isEmpty,
        reason: 'CORRECTION R-DR-03 : aucune opération IA sur le disque après '
            'la reprise');
  });
}
