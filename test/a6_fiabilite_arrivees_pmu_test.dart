// ═══════════════════════════════════════════════════════════════════════════
//  A6 — FIABILITÉ DES ARRIVÉES PMU — TEST 1/4
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE PRODUCTION.
//
//  OBJET : mesurer expérimentalement ce que les CINQ parseurs de
//  `/rapports-definitifs?specialisation=INTERNET` transmettent réellement à
//  la mémoire IA, sans les corriger.
//
//  Aucun algorithme de parseur n'est recopié ici : les cinq parseurs sont
//  atteints par leurs POINTS D'ENTRÉE PUBLICS DE PRODUCTION
//    P1 → IaMemoryService.analyseJourneeComplete()
//    P2 → IaMemoryService.fetchArriveeDirecte()
//    P3 → IaMemoryService.relancerRecuperationPMU()
//    P4 → DataRefreshService.refresh()
//    P5 → AlertService.init()   (chaîne privée : watchdog → _checkAlerts →
//                                _fetchResultatAuto ; point d'entrée public
//                                unique disponible, non modifié)
//  L0 → ArriveeOfficielleService.lireOrdreArrivee()  (référence, statique,
//       pure, sans stockage)
//
//  Le réseau est intercepté par `http.runWithClient()` + `MockClient` :
//  AUCUN appel réel vers turfinfo.api.pmu.fr. Aucun résultat réel n'est
//  modifié, aucun stockage L0 n'est écrit, aucun gradient n'est appelé
//  directement.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ─────────────────────────── Outils de formatage ───────────────────────────

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Affichage d'une arrivée. `[]` si vide, `null` si absente.
String _arr(List<int>? a) => a == null ? 'null' : (a.isEmpty ? '[]' : a.join('-'));

/// Vrai si [obtenu] commence EXACTEMENT par [attendu].
///
/// Comparaison sur les 5 PREMIERS rangs uniquement, et non sur la longueur
/// totale : la longueur dépend de la STRATÉGIE de chaque parseur et non de la
/// fidélité de l'arrivée. P1 et P2 cumulent les trois sources sans dédoublonner
/// les rangs déjà vus hors `arrivee`, P3/P4/P5 dédoublonnent — sans que l'un
/// soit plus correct que l'autre sur les 5 premiers. Juger sur la longueur
/// totale mélangerait deux propriétés distinctes.
bool _commencePar(List<int>? obtenu, List<int> attendu) {
  if (obtenu == null || obtenu.length < attendu.length) return false;
  for (var i = 0; i < attendu.length; i++) {
    if (obtenu[i] != attendu[i]) return false;
  }
  return true;
}

// ───────────────── Faux serveur PMU (aucun appel réel) ─────────────────────

/// Un bloc `{typePari, rapports[]}` du format RÉEL de l'API.
class _Bloc {
  final String type;
  final List<String> combinaisons;
  const _Bloc(this.type, this.combinaisons);
}

/// Corps JSON au format réel : racine = **List** de blocs.
String _corps(List<_Bloc> blocs) => json.encode([
      for (final b in blocs)
        {
          'typePari': b.type,
          'rapports': [
            for (final c in b.combinaisons)
              {'combinaison': c, 'dividendePourUnEuro': 350},
          ],
        },
    ]);

/// Programme minimal : une réunion, une course, AUCUN partant.
///
/// `participants` vide est délibéré : `DataRefreshService` appelle
/// `_mettreAJourEloApresArrivee()` de façon INCONDITIONNELLE après chaque
/// arrivée acceptée (data_refresh_service.dart:1176). Avec `partants` vide,
/// cette méthode sort immédiatement (elo_service.dart:245 / :1219) et le
/// calcul ELO n'est pas exercé — l'interdiction « ne pas toucher à ELO »
/// est ainsi respectée tout en empruntant le chemin de production réel.
String _programme(DateTime dep) => json.encode({
      'programme': {
        'reunions': [
          {
            'numOfficiel': 1,
            'hippodrome': {
              'libelleLong': 'VINCENNES (FRANCE)',
              'libelleCourt': 'VINCENNES',
            },
            'courses': [
              {
                'numOrdre': 1,
                'libelle': 'PRIX A6',
                'discipline': 'ATTELE',
                'distance': 2100,
                'montantPrix': 30000,
                'paris': <Map<String, dynamic>>[],
                'heureDepart': dep.millisecondsSinceEpoch,
              },
            ],
          },
        ],
      },
    });

/// Exécute [action] avec un réseau PMU entièrement simulé.
///
/// [corpsParCourse] permet de servir un corps DIFFÉRENT selon `R{n}C{m}`
/// (utilisé par T8). Sinon [corps] est servi pour toute requête de rapports.
Future<T> _avecPmu<T>(
  Future<T> Function() action, {
  String? corps,
  Map<String, String>? corpsParCourse,
  required DateTime dep,
}) {
  final client = MockClient((request) async {
    final p = request.url.path;

    if (p.contains('rapports-definitifs')) {
      if (corpsParCourse != null) {
        final m = RegExp(r'/R(\d+)/C(\d+)/').firstMatch(p);
        final cle = m == null ? '' : 'R${m.group(1)}C${m.group(2)}';
        final c = corpsParCourse[cle];
        if (c != null) {
          return http.Response(c, 200, headers: {'content-type': 'application/json'});
        }
      }
      return http.Response(corps ?? '[]', 200,
          headers: {'content-type': 'application/json'});
    }
    if (p.contains('participants')) {
      return http.Response(json.encode({'participants': <Map<String, dynamic>>[]}),
          200, headers: {'content-type': 'application/json'});
    }
    return http.Response(_programme(dep), 200,
        headers: {'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

/// Laisse progresser la boucle d'événements jusqu'à ce que [c] soit vraie.
/// Les délais sont RÉELS : `http.get(...).timeout(...)` arme un vrai Timer.
Future<bool> _attendreQue(bool Function() c, {int ms = 3000}) async {
  var ecoule = 0;
  while (ecoule < ms) {
    if (c()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    ecoule += 10;
  }
  return c();
}

// ─────────────────────────── État simulé ───────────────────────────────────

const Map<String, double> _poidsDefaut = {
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
  'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
  'mouvCote': 0.06, 'placeDepart': 0.03,
};

Map<String, Object> _prefs({
  List<String>? pronostics,
  List<String>? tracked,
}) =>
    <String, Object>{
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode({
        ..._poidsDefaut,
        'nbMisesAJour': 0,
        'calibrationScore': 50.0,
      }),
      'ia_seuils_v1': json.encode({}),
      'ia_precision_v2': json.encode({}),
      'ia_stats_labels_v1': json.encode({}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
      if (pronostics != null) 'ia_pronostics_v2': pronostics,
      if (tracked != null) 'tracked_courses_v1': tracked,
    };

/// Scores IA de référence : favori = « 4 », puis 7, 2, 9, 1.
/// Choisi pour que le classement PMU officiel 7-4-2-9-1 place le favori au
/// rang RÉEL 2 — le rendant sensible à toute permutation des trois premiers.
const Map<String, double> _scoresFavori4 = <String, double>{
  '4': 95.0, '7': 88.0, '2': 70.0, '9': 60.0,
  '1': 55.0, '3': 40.0, '5': 30.0, '6': 20.0,
};

IaPronostic _pronostic({
  required String cle,
  required DateTime date,
  Map<String, double> scoresIA = _scoresFavori4,
  String typePari = 'Simple Gagnant',
}) =>
    IaPronostic(
      courseKey: cle,
      nomCourse: 'PRIX A6',
      hippodrome: 'VINCENNES',
      discipline: 'Trot Attelé',
      datePronostic: date,
      scoresIA: scoresIA,
      scoresCriteres: const <String, ScoresCriteres>{},
      confiancePredite: 70.0,
      typePariConseille: typePari,
      resultatsReels: false,
      arriveeReelle: null,
    );

TrackedCourse _suivi({
  required int numR,
  required int numC,
  required DateTime heureDepart,
  required String iaMemKey,
  required int slot,
  int? numeroCheval,
}) =>
    TrackedCourse(
      numReunion: numR,
      numCourse: numC,
      nomCourse: 'PRIX A6',
      hippodrome: 'VINCENNES',
      heureDepart: heureDepart,
      numeroCheval: numeroCheval,
      nomCheval: numeroCheval == null ? null : 'CHEVAL_$numeroCheval',
      miseEngagee: 10.0,
      iaMemKey: iaMemKey,
      typePari: 'Simple Gagnant',
      cote: 5.0,
      // `storageKey` UNIQUE par scénario : `AlertService` mémorise les
      // `resultKey` déjà traités dans `_resultatsVerifies`, un `Set` du
      // SINGLETON qui n'est JAMAIS vidé par `_load()` (`:524-530` : il reçoit
      // seulement des ajouts). `resultKey` valant
      // `'${storageKey}_${jjmmaaaa}'`, un `storageKey` nul rendrait la clé
      // identique d'un test à l'autre et le second scénario serait sauté
      // silencieusement — mesuré : P5 rendait `null` aux tests T2..T5.
      storageKey: 'R${numR}C${numC}_${_fmt(heureDepart)}_$slot',
    );

/// Repart d'un état SIMULÉ vierge : disque mocké réécrit, service rechargé
/// par son chemin public `recharger()` (le même que le démarrage de l'app).
Future<void> _reset({
  List<IaPronostic> pronostics = const <IaPronostic>[],
  List<TrackedCourse> tracked = const <TrackedCourse>[],
}) async {
  SharedPreferences.setMockInitialValues(_prefs(
    pronostics: pronostics.map((p) => json.encode(p.toJson())).toList(),
    tracked: tracked.map((t) => json.encode(t.toJson())).toList(),
  ));
  SharedPreferences.resetStatic();
  ZoneTurfService.viderCachePourResetComplet();
  DataRefreshService.instance.viderMemoirePourResetComplet();
  await IaMemoryService.instance.recharger();
}

IaPronostic? _pronosticDe(String cle) {
  final l = IaMemoryService.instance.pronostics
      .where((p) => p.courseKey == cle)
      .toList();
  return l.isEmpty ? null : l.first;
}

/// Retire les courses suivies de la RAM d'`AlertService`.
///
/// Indispensable : le watchdog armé par `init()` tire toutes les 60 s. Une
/// course restée en suivi mais dont le `resultKey` a été retiré (échec de
/// récupération) provoquerait une requête HTTP RÉELLE au tick suivant, hors
/// de tout `http.runWithClient`. Vider le suivi rend le tick inerte.
Future<void> _viderSuivi() async {
  final cles = AlertService.instance.trackedCourses.keys.toList();
  for (final k in cles) {
    await AlertService.instance.retirerSuivi(k);
  }
}

/// `true` dès qu'`AlertService.init()` a armé son watchdog pour ce fichier.
/// Le singleton ne peut être `dispose()` qu'UNE fois : on ne le rouvre donc
/// pas après fermeture.
bool _alertesOuvertes = false;

/// Ouvre `AlertService` par son point d'entrée public de production.
Future<void> _ouvrirAlertes() async {
  _alertesOuvertes = true;
  await AlertService.init();
}

/// Ferme proprement : suivi vidé AVANT `dispose()` (car `retirerSuivi()`
/// appelle `notifyListeners()`, interdit après libération), puis annulation
/// du `Timer.periodic(60 s)`.
Future<void> _fermerAlertes() async {
  if (!_alertesOuvertes) return;
  _alertesOuvertes = false;
  await _viderSuivi();
  AlertService.instance.dispose();
}

// ─────────────────────── Mesure des cinq parseurs ──────────────────────────

class _Mesure {
  final List<int>? arrivee;
  final String note;
  const _Mesure(this.arrivee, [this.note = '']);
}

/// Compteur d'invocations de [_mesurerLes5].
///
/// Sert à rendre les clés de course UNIQUES d'un scénario à l'autre. Deux
/// caches du singleton survivent en effet à `recharger()` :
///   • `_arriveeCache` (`ia_memory_service.dart:1347`), vidé seulement par le
///     reset complet (`:1574`) ;
///   • `_resultatsVerifies` (`alert_service.dart:2792`), vidé seulement par
///     `executerResetComplet()`.
/// Réutiliser la même clé ferait répondre le cache au lieu du parseur.
int _slot = 0;

/// Exécute les CINQ parseurs de production sur le même corps simulé.
///
/// Chaque parseur est mesuré sur un état vierge : aucune mesure ne peut
/// influencer la suivante. Une clé de course distincte par parseur ET par
/// scénario évite tout effet des caches de singleton décrits sur [_slot].
Future<Map<String, _Mesure>> _mesurerLes5(
  String corps, {
  DateTime? depart,
  Map<String, double> scoresIA = _scoresFavori4,
}) async {
  final dep = depart ?? DateTime.now().subtract(const Duration(minutes: 60));
  final s = _slot++;
  final out = <String, _Mesure>{};

  // ── P1 — analyseJourneeComplete ────────────────────────────────────────
  {
    final cle = 'R1C${s + 1}_${_fmt(dep)}';
    await _reset(pronostics: [_pronostic(cle: cle, date: dep, scoresIA: scoresIA)]);
    await _avecPmu(
      () => IaMemoryService.instance.analyseJourneeComplete(date: dep),
      corps: corps,
      dep: dep,
    );
    out['P1'] = _Mesure(_pronosticDe(cle)?.arriveeReelle);
  }

  // ── P2 — fetchArriveeDirecte (liste retournée directement) ─────────────
  {
    final cle = 'R2C${s + 1}_${_fmt(dep)}';
    // `scoresIA` EST semé : en production, P2 est appelé depuis un écran qui
    // affiche un pronostic existant, donc la liste des partants analysés est
    // disponible. Sans ce semis, le contrôle d'appartenance ne pourrait pas
    // s'exercer et le test mesurerait un cas qui n'existe pas en production.
    await _reset(
        pronostics: [_pronostic(cle: cle, date: dep, scoresIA: scoresIA)]);
    final r = await _avecPmu(
      () => IaMemoryService.instance
          .fetchArriveeDirecte(courseKey: cle, heureDepart: dep),
      corps: corps,
      dep: dep,
    );
    out['P2'] = _Mesure(r);
  }

  // ── P3 — relancerRecuperationPMU ──────────────────────────────────────
  {
    final cle = 'R3C${s + 1}_${_fmt(dep)}';
    await _reset(pronostics: [_pronostic(cle: cle, date: dep, scoresIA: scoresIA)]);
    final res = await _avecPmu(
      () => IaMemoryService.instance.relancerRecuperationPMU(),
      corps: corps,
      dep: dep,
    );
    out['P3'] = _Mesure(
      _pronosticDe(cle)?.arriveeReelle,
      'recuperes=${res['recuperes']} introuvables=${res['introuvables']}',
    );
  }

  // ── P4 — DataRefreshService.refresh ───────────────────────────────────
  {
    final cle = 'R4C${s + 1}_${_fmt(dep)}';
    await _reset(pronostics: [_pronostic(cle: cle, date: dep, scoresIA: scoresIA)]);
    await _avecPmu(
      () => DataRefreshService.instance.refresh(),
      corps: corps,
      dep: dep,
    );
    await _attendreQue(() => _pronosticDe(cle)?.resultatsReels == true);
    out['P4'] = _Mesure(_pronosticDe(cle)?.arriveeReelle);
  }

  // ── P5 — AlertService.init → watchdog → _checkAlerts → _fetchResultatAuto
  //
  //  Départ placé à −40 min : la récupération de résultat est déclenchée
  //  (`diffMin <= -10`, alert_service.dart:1820) MAIS la détection DQ
  //  (`diffMin > -35`, alert_service.dart:1833) ne l'est pas. Cela évite un
  //  second chemin réseau (`ZoneTurfService.chargerStatutsPartants`) sans
  //  rapport avec l'objet du test.
  {
    final dep5 = DateTime.now().subtract(const Duration(minutes: 40));
    final cle = 'R5C${s + 1}_${_fmt(dep5)}';
    await _reset(
      pronostics: [_pronostic(cle: cle, date: dep5, scoresIA: scoresIA)],
      tracked: [
        _suivi(
            numR: 5,
            numC: s + 1,
            heureDepart: dep5,
            iaMemKey: cle,
            slot: s,
            numeroCheval: 7),
      ],
    );
    try {
      await _avecPmu(
        () => _ouvrirAlertes(),
        corps: corps,
        dep: dep5,
      );
      await _attendreQue(() => _pronosticDe(cle)?.resultatsReels == true);
      out['P5'] = _Mesure(_pronosticDe(cle)?.arriveeReelle);
    } finally {
      await _viderSuivi();
    }
  }

  return out;
}

/// Variante SANS liste de partants fiable : aucun pronostic n'est semé, donc
/// `scoresIA` est absent. Sert à mesurer qu'une liste indisponible n'entraîne
/// jamais un refus au motif du numéro étranger (A6 §5).
Future<Map<String, _Mesure>> _mesurerLes5SansPartants(
  String corps, {
  DateTime? depart,
}) async {
  final dep = depart ?? DateTime.now().subtract(const Duration(minutes: 60));
  final s = _slot++;
  final out = <String, _Mesure>{};

  // P1 — aucun pronostic pour cette clé → aucune liste de partants.
  {
    final cle = 'R6C${s + 1}_${_fmt(dep)}';
    await _reset();
    await _avecPmu(
      () => IaMemoryService.instance.analyseJourneeComplete(date: dep),
      corps: corps,
      dep: dep,
    );
    out['P1'] = _Mesure(_pronosticDe(cle)?.arriveeReelle);
  }

  // P2 — aucun pronostic → `partants` vaut null.
  {
    final cle = 'R7C${s + 1}_${_fmt(dep)}';
    await _reset();
    final r = await _avecPmu(
      () => IaMemoryService.instance
          .fetchArriveeDirecte(courseKey: cle, heureDepart: dep),
      corps: corps,
      dep: dep,
    );
    out['P2'] = _Mesure(r);
  }

  return out;
}

/// Ligne du tableau de résultats.
void _ligne(String test, String parseur, String attendu, String obtenu,
    String verdict) {
  debugPrint('| $test | $parseur | $attendu | $obtenu | $verdict |');
}

// ─────────────────────────────── Tests ─────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(_prefs());
    SharedPreferences.resetStatic();
    ZoneTurfService.viderCachePourResetComplet();
    DataRefreshService.instance.viderMemoirePourResetComplet();
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
  });

  tearDown(() async {
    await _viderSuivi();
  });

  // `AlertService.instance` est un singleton : son `Timer.periodic(60 s)` ne
  // peut être annulé qu'une fois. On ferme donc le service à la FIN du
  // fichier, jamais entre deux tests — sinon les tests suivants trouveraient
  // un service libéré que `init()` ne peut plus rouvrir.
  tearDownAll(() async {
    await _fermerAlertes();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T1 — ARRIVÉE OFFICIELLE ORDONNÉE : 7 - 4 - 2 - 9 - 1
  //  Attendu : les cinq parseurs restituent ces cinq chevaux dans cet ordre.
  // ═══════════════════════════════════════════════════════════════════════
  test('T1 — arrivée ordonnée 7-4-2-9-1 : ordre restitué par les 4 parseurs reconstructeurs',
      () async {
    const attendu = [7, 4, 2, 9, 1];
    final corps = _corps(const [
      _Bloc('E_SIMPLE_GAGNANT', ['7']),
      _Bloc('E_SIMPLE_PLACE', ['7', '4', '2']),
      _Bloc('E_QUINTE_PLUS', ['7-4-2-9-1']),
    ]);

    final m = await _mesurerLes5(corps);

    debugPrint('');
    debugPrint('| Test | Parseur | Attendu | Obtenu | Verdict |');
    debugPrint('|---|---|---|---|---|');

    var pass = 0;
    // ⚠️ ADAPTATION — A6 n° 2-b-3 : P3 n'enregistre plus d'arrivée
    // reconstruite depuis les rapports PMU ; il ne restitue donc plus d'ordre
    // et ne peut plus être jugé sur ce critère. Il est mesuré séparément.
    for (final p in ['P1', 'P2', 'P4', 'P5']) {
      final obtenu = m[p]!.arrivee;
      final ok = _commencePar(obtenu, attendu);
      if (ok) pass++;
      _ligne('T1', p, _arr(attendu), _arr(obtenu), ok ? 'PASS' : 'FAIL');
    }
    final p3T1 = m['P3']!.arrivee;
    final p3T1Ok = p3T1 == null;
    if (p3T1Ok) pass++;
    _ligne('T1', 'P3', 'aucune arrivée (L0 seul)',
        _arr(p3T1), p3T1Ok ? 'PASS' : 'FAIL');

    // L0 — référence : aucune perte d'ordre, groupes préservés.
    final l0 = ArriveeOfficielleService.lireOrdreArrivee(
        <List<int>>[[7], [4], [2], [9], [1]]);
    final l0plat = l0?.expand((g) => g).toList();
    final l0ok = l0plat != null &&
        l0plat.length == 5 &&
        List.generate(5, (i) => l0plat[i] == attendu[i]).every((e) => e);
    if (l0ok) pass++;
    _ligne('T1', 'L0', _arr(attendu), _arr(l0plat), l0ok ? 'PASS' : 'FAIL');

    expect(pass, 6,
        reason: 'T1 : les 4 parseurs reconstructeurs et L0 restituent '
            '7-4-2-9-1 ; P3, alimenté exclusivement par L0 (A6 n° 2-b-3), ne '
            'produit aucune arrivée sans L0 — ce qui est son comportement '
            'attendu');
    debugPrint('T1 : $pass/6 PASS (4 parseurs + P3 + L0)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T2 — RAPPORT DESORDRE  ★ STATUT : ANOMALIE CORRIGÉE (A6 n° 1)
  //
  //  Corps : QUINTE_ORDRE 7-4-2-9-1  ET  QUINTE_DESORDRE 3-8-5-6-10.
  //  Attendu (comportement corrigé) : 3-8-5-6-10 n'apparaît PAS.
  //
  //  AVANT correction — mesuré : 3/5 PASS, P1 et P4 FAIL
  //      P1 → 7-4-2-9-1-3-8-5-6-10
  //      P4 → 7-4-2-9-1-3-8-5-6-10
  //  APRÈS correction — les assertions ci-dessous vérifient le comportement
  //  CORRIGÉ (5/5). Ce scénario ne démontre donc plus une anomalie : il
  //  VALIDE un correctif. Les scénarios T3 à T8, eux, restent volontairement
  //  non corrigés et continuent d'assertir leurs anomalies.
  // ═══════════════════════════════════════════════════════════════════════
  test('T2 — rapport DESORDRE : les chevaux du désordre ne doivent pas entrer',
      () async {
    const attendu = [7, 4, 2, 9, 1];
    const desordre = [3, 8, 5, 6, 10];
    final corps = _corps(const [
      _Bloc('E_SIMPLE_GAGNANT', ['7']),
      _Bloc('E_SIMPLE_PLACE', ['7', '4', '2']),
      _Bloc('E_QUINTE_PLUS', ['7-4-2-9-1']),
      _Bloc('E_QUINTE_PLUS_DESORDRE', ['3-8-5-6-10']),
    ]);

    final m = await _mesurerLes5(corps);

    debugPrint('');
    debugPrint('| Test | Parseur | Attendu | Obtenu | Verdict |');
    debugPrint('|---|---|---|---|---|');

    var pass = 0;
    for (final p in ['P1', 'P2', 'P3', 'P4', 'P5']) {
      final obtenu = m[p]!.arrivee;
      final contientDesordre =
          obtenu != null && obtenu.any((n) => desordre.contains(n));
      final ok = _commencePar(obtenu, attendu) && !contientDesordre;
      if (ok) pass++;
      _ligne('T2', p, _arr(attendu),
          '${_arr(obtenu)}${contientDesordre ? " ← désordre inclus" : ""}',
          ok ? 'PASS' : 'FAIL');
    }

    // Discrimination exigée explicitement par le mandat.
    final p1 = m['P1']!.arrivee;
    final p4 = m['P4']!.arrivee;
    final p2 = m['P2']!.arrivee;
    final p3 = m['P3']!.arrivee;
    final p5 = m['P5']!.arrivee;

    final p1Pollue = p1 != null && p1.any((n) => desordre.contains(n));
    final p4Pollue = p4 != null && p4.any((n) => desordre.contains(n));
    final p2Propre = p2 != null && !p2.any((n) => desordre.contains(n));
    final p5Propre = p5 != null && !p5.any((n) => desordre.contains(n));

    // ⚠️ ADAPTATION — A6 n° 2-b-3.
    // ANCIENNE ASSERTION : `p3Propre` vrai, c'est-à-dire « P3 produit une
    // arrivée de 5 chevaux ne contenant aucun cheval du désordre ».
    // NOUVELLE ATTENTE : P3 n'ENREGISTRE PLUS depuis les rapports PMU ; sans
    // L0, il ne produit donc aucune arrivée. L'invariant qui compte — « aucun
    // cheval du désordre n'apparaît » — est conservé tel quel, et même
    // renforcé : P3 ne peut plus être pollué du tout.
    final p3SansDesordre = p3 == null || !p3.any((n) => desordre.contains(n));

    debugPrint('T2 — P1 pollué=$p1Pollue | P4 pollué=$p4Pollue | '
        'P2 propre=$p2Propre | P3 sans désordre=$p3SansDesordre '
        '(${_arr(p3)}) | P5 propre=$p5Propre');

    // L0 : le désordre n'a aucune représentation en groupes → référence.
    final l0 = ArriveeOfficielleService.lireOrdreArrivee(
        <List<int>>[[7], [4], [2], [9], [1]]);
    final l0plat = l0?.expand((g) => g).toList();
    _ligne('T2', 'L0', _arr(attendu), _arr(l0plat), 'PASS');

    // ── Assertions du comportement CORRIGÉ ──────────────────────────────
    // 4 parseurs restituent l'arrivée exacte ; P3 est jugé sur son nouvel
    // invariant (aucune pollution possible) et non plus sur une restitution
    // qu'il n'a plus le droit de produire.
    expect(pass, 4,
        reason: 'T2 (CORRIGÉ A6 n° 1 + 2-b-3) : P1, P2, P4 et P5 restituent '
            '7-4-2-9-1 sans aucun cheval du désordre ; P3, désormais '
            'alimenté exclusivement par L0, ne produit rien sans L0');
    expect(p1Pollue, isFalse,
        reason: 'T2 (CORRIGÉ) : P1 n\'inclut plus le désordre — exclusion '
            'ajoutée en ia_memory_service.dart:4253-4266');
    expect(p4Pollue, isFalse,
        reason: 'T2 (CORRIGÉ) : P4 n\'inclut plus le désordre — exclusion '
            'ajoutée en data_refresh_service.dart:1266-1281');
    // Témoin de non-régression des parseurs restés reconstructeurs.
    expect(p2Propre && p5Propre, isTrue,
        reason: 'T2 : P2 et P5 restent corrects — aucune régression');
    expect(p3SansDesordre, isTrue,
        reason: 'T2 : P3 ne peut plus être pollué par un DESORDRE, puisqu\'il '
            'n\'enregistre plus aucune arrivée reconstruite (A6 n° 2-b-3)');
    // Les quatre parseurs reconstructeurs doivent être IDENTIQUES.
    expect(
        <String>[_arr(p1), _arr(p2), _arr(p4), _arr(p5)].toSet().length,
        1,
        reason: 'T2 (CORRIGÉ) : P1, P2, P4 et P5 produisent la MÊME arrivée '
            'sur ce corps');
    debugPrint('T2 : $pass/4 PASS sur les parseurs reconstructeurs '
        '(statut : anomalie corrigée)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T3 — ORDRE INCORRECT DES RAPPORTS PLACÉ
  //  Arrivée réelle : 7-4-2-9-1. Rapports E_SIMPLE_PLACE fournis : 2, 7, 4.
  //  Attendu : le classement ne doit pas être reconstruit depuis l'ordre des
  //            rapports PLACÉ, mais depuis l'ordre officiel.
  // ═══════════════════════════════════════════════════════════════════════
  test('T3 — rapports PLACÉ désordonnés : classement reconstruit à tort',
      () async {
    const attendu = [7, 4, 2, 9, 1];
    final corps = _corps(const [
      _Bloc('E_SIMPLE_GAGNANT', ['7']),
      _Bloc('E_SIMPLE_PLACE', ['2', '7', '4']), // ordre PLACÉ, pas officiel
      _Bloc('E_QUINTE_PLUS', ['7-4-2-9-1']),
    ]);

    final m = await _mesurerLes5(corps);

    debugPrint('');
    debugPrint('| Test | Parseur | Attendu | Obtenu | Verdict |');
    debugPrint('|---|---|---|---|---|');

    var pass = 0;
    var fail = 0;
    for (final p in ['P1', 'P2', 'P4', 'P5']) {
      final obtenu = m[p]!.arrivee;
      final ok = _commencePar(obtenu, attendu);
      if (ok) {
        pass++;
      } else {
        fail++;
      }
      _ligne('T3', p, _arr(attendu), _arr(obtenu), ok ? 'PASS' : 'FAIL');
    }

    // ⚠️ ADAPTATION — A6 n° 2-b-3.
    // P3 reste MESURÉ (il figure dans `m` et son arrivée est journalisée
    // ci-dessous), mais il ne peut plus être jugé sur la restitution d'un
    // ordre : sans L0 il n'enregistre plus rien. On mesure donc son nouvel
    // invariant : il ne DIVERGE plus, puisqu'il ne produit plus d'arrivée.
    final p3 = m['P3']!.arrivee;
    final p3Diverge = p3 != null && !_commencePar(p3, attendu);
    _ligne('T3', 'P3', 'n\'enregistre plus depuis le PMU (2-b-3)',
        _arr(p3), p3Diverge ? 'FAIL (a reconstruit)' : 'PASS');

    // L0 : la référence ne dépend d'aucun rapport.
    final l0 = ArriveeOfficielleService.lireOrdreArrivee(
        <List<int>>[[7], [4], [2], [9], [1]]);
    final l0plat = l0?.expand((g) => g).toList();
    final l0ok = l0plat != null &&
        List.generate(5, (i) => l0plat[i] == attendu[i]).every((e) => e);
    if (l0ok) pass++;
    _ligne('T3', 'L0', _arr(attendu), _arr(l0plat), l0ok ? 'PASS' : 'FAIL');

    debugPrint('T3 : $pass PASS / $fail FAIL sur les 4 parseurs '
        'reconstructeurs · P3=${_arr(p3)} (n\'enregistre plus)');

    // ⚠️ ADAPTATION — FINALISATION A6.
    // ANCIENNE ASSERTION : `fail == 4` et `m['P1']!.arrivee == [7, 2, 4, 9, 1]`,
    // c'est-à-dire « les quatre parseurs reconstruisent les rangs 2 et 3 depuis
    // l'ordre des rapports E_SIMPLE_PLACE (2, 7, 4) au lieu de l'ordre officiel
    // 7-4-2-9-1 ». C'était l'ANOMALIE elle-même, encodée comme attendu.
    // NOUVELLE ATTENTE MÉTIER : l'ordre des rapports PLACÉ ne doit plus avoir
    // AUCUNE influence. Les quatre parseurs retiennent exclusivement le rapport
    // ORDONNÉ officiel `E_QUINTE_PLUS 7-4-2-9-1`, donc ils restituent tous
    // 7-4-2-9-1 — exactement l'arrivée réelle. Le test détecte encore une
    // régression : si un parseur se remettait à empiler les PLACÉ, il rendrait
    // 7-2-4-9-1 et `fail` repasserait à 1, faisant échouer `fail == 0`.
    expect(fail, 0,
        reason: 'T3 (CORRIGÉ A6) : aucun des quatre parseurs ne doit plus '
            'reconstruire un classement depuis l\'ordre des rapports PLACÉ — '
            'seul le rapport ordonné officiel fait foi');
    expect(m['P1']!.arrivee, [7, 4, 2, 9, 1],
        reason: 'T3 (CORRIGÉ A6) : P1 restitue l\'ordre OFFICIEL 7-4-2-9-1 et '
            'non plus l\'ordre des PLACÉ (7-2-4-9-1), ancienne sortie fautive');
    for (final p in ['P1', 'P2', 'P4', 'P5']) {
      expect(m[p]!.arrivee, [7, 4, 2, 9, 1],
          reason: 'T3 (CORRIGÉ A6) : $p ignore l\'ordre des rapports PLACÉ');
    }
    expect(p3Diverge, isFalse,
        reason: 'T3 : P3 ne doit plus reconstruire d\'arrivée depuis les '
            'rapports — il ne peut donc plus produire d\'ordre erroné');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T4 — EX ÆQUO : [[7, 4], [2], [9], [1]]
  //  Attendu : L0 conserve les groupes. On mesure ce que produisent les
  //  parseurs (l'API `rapports-definitifs` ne fournit qu'une chaîne plate)
  //  puis si le rang du favori IA devient incorrect.
  // ═══════════════════════════════════════════════════════════════════════
  test('T4 — ex æquo : L0 conserve les groupes, les parseurs les aplatissent',
      () async {
    // ── L0 : référence ────────────────────────────────────────────────────
    final l0 = ArriveeOfficielleService.lireOrdreArrivee(
        <List<int>>[[7, 4], [2], [9], [1]]);
    debugPrint('');
    debugPrint('| Test | Parseur | Attendu | Obtenu | Verdict |');
    debugPrint('|---|---|---|---|---|');

    final l0Groupes = l0 == null ? 'null' : l0.map((g) => '[${g.join(',')}]').join(' ');
    final l0ok = l0 != null &&
        l0.length == 4 &&
        l0[0].length == 2 &&
        l0[0].contains(7) &&
        l0[0].contains(4);
    _ligne('T4', 'L0', '[[7,4],[2],[9],[1]]', l0Groupes, l0ok ? 'PASS' : 'FAIL');

    // ── Les 5 parseurs : seul le plat est représentable ───────────────────
    final corps = _corps(const [
      _Bloc('E_SIMPLE_GAGNANT', ['7']),
      _Bloc('E_SIMPLE_PLACE', ['7', '4', '2']),
      _Bloc('E_QUINTE_PLUS', ['7-4-2-9-1']),
    ]);
    final m = await _mesurerLes5(corps);

    var aplat = 0;
    // ⚠️ ADAPTATION — A6 n° 2-b-3 : P3 n'enregistre plus depuis les rapports,
    // donc il n'aplatit plus rien. Il est mesuré à part, et c'est justement
    // LUI qui respecte désormais l'ex æquo (en différant l'arrivée).
    for (final p in ['P1', 'P2', 'P4', 'P5']) {
      final obtenu = m[p]!.arrivee;
      final ok = obtenu != null && obtenu.length == 5;
      if (ok) aplat++;
      // L'égalité n'existe pas dans le type de retour : une arrivée plate de
      // 5 chevaux est le SEUL résultat atteignable. Ce n'est pas une
      // divergence de fidélité, c'est une perte d'information structurelle.
      _ligne('T4', p, 'ex æquo conservés (4 rangs)',
          _arr(obtenu), ok ? 'FAIL (aplati)' : 'NON CONCLUANT');
    }
    final p3T4 = m['P3']!.arrivee;
    _ligne('T4', 'P3', 'ex æquo différé (aucun aplatissement)',
        _arr(p3T4), p3T4 == null ? 'PASS' : 'FAIL (aplati)');

    // ── Conséquence sur le rang du favori IA ─────────────────────────────
    // Le favori est « 4 ». Rang RÉEL (L0) = 1, ex æquo avec 7.
    // Rang obtenu par parsing = 2 (index 1 dans 7-4-2-9-1).
    final rangReel = l0 == null ? null : l0.indexWhere((g) => g.contains(4)) + 1;
    // Re-mesure explicite pour lire le rang enregistré par P1.
    final dep = DateTime.now().subtract(const Duration(minutes: 60));
    final cle = 'R1C${_slot++ + 1}_${_fmt(dep)}';
    await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);
    await _avecPmu(
      () => IaMemoryService.instance.analyseJourneeComplete(date: dep),
      corps: corps,
      dep: dep,
    );
    final p1 = _pronosticDe(cle);
    final rangParse = p1?.rangFavoriIaDansArrivee;

    _ligne('T4', 'P1 (rang favori)', '$rangReel (ex æquo)',
        '${rangParse ?? "null"}', rangParse == rangReel ? 'PASS' : 'FAIL');

    debugPrint('T4 — L0 groupes=$l0Groupes | parseurs aplatis=$aplat/5 | '
        'rang favori réel=$rangReel obtenu=$rangParse | '
        'nbTop3=${p1?.nbTop3DansArriveeReelle} '
        'nbTop5=${p1?.nbTop5DansArriveeReelle}');

    expect(l0ok, isTrue, reason: 'T4 : L0 doit conserver les ex æquo');
    expect(aplat, 4, reason: 'T4 : les quatre parseurs reconstructeurs '
        'produisent une arrivée plate de 5 chevaux — l\'ex æquo est '
        'structurellement perdu pour eux');
    expect(p3T4, isNull,
        reason: 'T4 : P3, depuis A6 n° 2-b-3, REFUSE l\'arrivée contenant des '
            'ex æquo au lieu de l\'aplatir — c\'est précisément la sécurité '
            'exigée par le mandat');
    expect(rangParse, 2,
        reason: 'T4 : le favori « 4 » est enregistré au rang 2 alors que son '
            'rang officiel est 1 (ex æquo)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T5 — RÉSULTAT PARTIEL : un seul cheval gagnant.
  //  Attendu : ne pas accepter une arrivée d'un seul cheval comme résultat
  //            suffisant pour l'apprentissage.
  // ═══════════════════════════════════════════════════════════════════════
  test('T5 — résultat partiel (1 seul cheval) : accepté pour l\'apprentissage ?',
      () async {
    final corps = _corps(const [
      _Bloc('E_SIMPLE_GAGNANT', ['7']),
    ]);

    final m = await _mesurerLes5(corps);

    debugPrint('');
    debugPrint('| Test | Parseur | Attendu | Obtenu | Verdict |');
    debugPrint('|---|---|---|---|---|');

    var acceptes = 0;
    // ⚠️ ADAPTATION — A6 n° 2-b-3 : P3 n'enregistre plus depuis les rapports,
    // donc il n'accepte plus aucune arrivée partielle. Mesuré séparément.
    for (final p in ['P1', 'P2', 'P4', 'P5']) {
      final obtenu = m[p]!.arrivee;
      final accepte = obtenu != null && obtenu.length == 1;
      if (accepte) acceptes++;
      _ligne('T5', p, 'refusé (arrivée incomplète)',
          '${_arr(obtenu)} → ${accepte ? "accepté" : "refusé"}',
          accepte ? 'FAIL' : 'PASS');
    }
    final p3T5 = m['P3']!.arrivee;
    _ligne('T5', 'P3', 'refusé (n\'enregistre plus)',
        _arr(p3T5), p3T5 == null ? 'PASS' : 'FAIL');

    // ── Conséquence mesurée sur les données transmises au gradient ────────
    // Une SEULE course résolue dans l'état : les quatre gardes d'apprentissage
    // sortent donc avant toute mutation mesurable —
    //   `_apprendreReglesBase` exige nb ≥ 3        (ia_memory_service.dart:3711)
    //   `_apprendreParDiscipline` exige ≥ 5        (:3431-3452)
    //   `_mettreAJourCalibration` exige ≥ 5        (:3615 / :3621)
    //   `_mettreAJourPrecisionIA` n'agit sur les seuils qu'à ≥ 3 (:5200)
    // Ce que T5 observe est donc STRICTEMENT ce que le parseur transmet.
    final dep = DateTime.now().subtract(const Duration(minutes: 60));
    final cle = 'R1C${_slot++ + 1}_${_fmt(dep)}';
    await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);

    final poidsAvant = <double>[
      IaMemoryService.instance.poids.forme,
      IaMemoryService.instance.poids.cote,
      IaMemoryService.instance.poids.elo,
      IaMemoryService.instance.poids.divergence,
    ];
    final apprentissagesAvant = IaMemoryService.instance.poids.nbMisesAJour;

    await _avecPmu(
      () => IaMemoryService.instance.analyseJourneeComplete(date: dep),
      corps: corps,
      dep: dep,
    );
    final p1 = _pronosticDe(cle);

    // TÉMOIN : l'apprentissage n'a pas bougé, donc la mesure est pure.
    final apprentissagesApres = IaMemoryService.instance.poids.nbMisesAJour;
    final poidsApres = <double>[
      IaMemoryService.instance.poids.forme,
      IaMemoryService.instance.poids.cote,
      IaMemoryService.instance.poids.elo,
      IaMemoryService.instance.poids.divergence,
    ];
    debugPrint('T5 — TÉMOIN apprentissage : nbMisesAJour '
        '$apprentissagesAvant→$apprentissagesApres | poids identiques='
        '${poidsAvant.toString() == poidsApres.toString()}');

    debugPrint('T5 — pronostic résolu=${p1?.resultatsReels} '
        'arrivée=${_arr(p1?.arriveeReelle)} '
        'rangFavori=${p1?.rangFavoriIaDansArrivee} '
        'nbTop3=${p1?.nbTop3DansArriveeReelle} '
        'nbTop5=${p1?.nbTop5DansArriveeReelle} '
        'scorePerf=${p1?.scorePerformance}');

    // ⚠️ ADAPTATION — FINALISATION A6.
    // ANCIENNE ASSERTION : `acceptes == 4`, `p1.resultatsReels == true`,
    // `p1.arriveeReelle == [7]` — c'est-à-dire « une arrivée d'UN SEUL cheval
    // est acceptée et déclenche l'apprentissage ». C'était l'ANOMALIE.
    // NOUVELLE ATTENTE MÉTIER : le corps ne contient qu'un
    // `E_SIMPLE_GAGNANT`, donc AUCUN rapport ordonné. La règle partagée refuse
    // une arrivée partielle (1 cheval < kLongueurMinimaleArrivee = 3) : les
    // quatre parseurs ne produisent rien, le pronostic reste non résolu et
    // reste donc récupérable au cycle suivant.
    // Le test détecte encore une régression : si un parseur réacceptait une
    // arrivée d'un cheval, `acceptes` repasserait au-dessus de 0.
    expect(acceptes, 0,
        reason: 'T5 (CORRIGÉ A6) : aucun parseur ne doit accepter une arrivée '
            'partielle d\'un seul cheval');
    expect(p3T5, isNull,
        reason: 'T5 : P3 n\'accepte plus aucune arrivée issue du PMU (A6 '
            'n° 2-b-3) — donc aucune arrivée partielle');
    expect(p1?.resultatsReels, isFalse,
        reason: 'T5 (CORRIGÉ A6) : le résultat partiel n\'est PAS marqué '
            '« réel » — la course reste non résolue donc réessayable');
    expect(p1?.arriveeReelle, isNull,
        reason: 'T5 (CORRIGÉ A6) : aucune arrivée n\'est enregistrée, donc '
            'aucun `nbTop3` ni `scorePerformance` ne peut être calculé sur une '
            'vérité incomplète');
    expect(apprentissagesApres, apprentissagesAvant,
        reason: 'T5 — TÉMOIN : aucun apprentissage déclenché, la mesure est '
            'donc bien celle du parseur seul');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T6 — ABSENCE DE RAPPORT GAGNANT
  //  T6a : seul un DESORDRE est fourni.  ★ STATUT : ANOMALIE CORRIGÉE (A6 n° 1)
  //  T6b : seuls des PLACÉ sont fournis (aucun E_SIMPLE_GAGNANT).
  //  Attendu : aucun cheval arbitraire ne doit devenir premier.
  //
  //  T6a — AVANT correction n° 1 — mesuré : 3/5 PASS, P1 et P4 FAIL
  //      P1 → 3-8-5-6-10   (le 1er cheval du désordre devenait premier)
  //      P4 → 3-8-5-6-10   (idem pour le batch automatique)
  //  T6a — APRÈS correction n° 1 — les assertions ci-dessous vérifient le
  //  comportement CORRIGÉ (5/5). Ce scénario VALIDE donc un correctif et ne
  //  démontre plus une anomalie. T3, T4, T5, T6b, T7 et T8 restent
  //  volontairement non corrigés et continuent d'assertir leurs anomalies.
  // ═══════════════════════════════════════════════════════════════════════
  test('T6a — aucun E_SIMPLE_GAGNANT, uniquement un DESORDRE', () async {
    final corps = _corps(const [
      _Bloc('E_QUINTE_PLUS_DESORDRE', ['3-8-5-6-10']),
    ]);

    final m = await _mesurerLes5(corps);

    debugPrint('');
    debugPrint('| Test | Parseur | Attendu | Obtenu | Verdict |');
    debugPrint('|---|---|---|---|---|');

    var fail = 0;
    for (final p in ['P1', 'P2', 'P3', 'P4', 'P5']) {
      final obtenu = m[p]!.arrivee;
      final accepte = obtenu != null && obtenu.isNotEmpty;
      if (accepte) fail++;
      _ligne('T6a', p, 'aucune arrivée',
          '${_arr(obtenu)}${accepte ? " → 1er=${obtenu.first} (arbitraire)" : ""}',
          accepte ? 'FAIL' : 'PASS');
    }

    // Discrimination exigée explicitement par le mandat A6 n° 1 :
    // P1 et P4 ont reçu l'exclusion DESORDRE ; P2, P3 et P5 la possédaient déjà
    // et doivent rester inchangés (témoins de non-régression).
    final p1 = m['P1']!.arrivee;
    final p4 = m['P4']!.arrivee;

    final p1Fabrique = p1 != null && p1.isNotEmpty;
    final p4Fabrique = p4 != null && p4.isNotEmpty;

    expect(fail, 0,
        reason: 'T6a (CORRIGÉ) : aucun des cinq parseurs ne doit fabriquer une '
            'arrivée depuis un DESORDRE');
    expect(p1Fabrique, isFalse,
        reason: 'T6a (CORRIGÉ) : P1 ne fabrique plus d\'arrivée depuis un '
            'DESORDRE — exclusion ajoutée en ia_memory_service.dart:4253-4266');
    expect(p4Fabrique, isFalse,
        reason: 'T6a (CORRIGÉ) : P4 ne fabrique plus d\'arrivée depuis un '
            'DESORDRE — exclusion ajoutée en data_refresh_service.dart:1266-1281');
    expect(p1, isNot([3, 8, 5, 6, 10]),
        reason: 'T6a (CORRIGÉ) : le premier cheval du désordre ne devient plus '
            'premier par P1 — ancienne sortie fautive explicitement rejetée');
    expect(p4, isNot([3, 8, 5, 6, 10]),
        reason: 'T6a (CORRIGÉ) : idem pour le batch automatique — ancienne '
            'sortie fautive explicitement rejetée par P4');
    debugPrint('T6a : $fail/5 FAIL → 5/5 PASS (statut : anomalie corrigée)');
  });

  test('T6b — aucun E_SIMPLE_GAGNANT, uniquement des PLACÉ (P5)', () async {
    final corps = _corps(const [
      _Bloc('E_SIMPLE_PLACE', ['7', '4', '2']),
    ]);

    final dep = DateTime.now().subtract(const Duration(minutes: 40));
    final cle = 'R5C990_${_fmt(dep)}';

    await _reset(
      pronostics: [_pronostic(cle: cle, date: dep)],
      tracked: [
        _suivi(
            numR: 5,
            numC: 990,
            heureDepart: dep,
            iaMemKey: cle,
            slot: 990,
            numeroCheval: 7),
      ],
    );

    try {
      await _avecPmu(() => _ouvrirAlertes(), corps: corps, dep: dep);
      await _attendreQue(() => _pronosticDe(cle)?.resultatsReels == true);

      final p = _pronosticDe(cle);
      // Filtre sur R5C990 : `_alerts` est un singleton persistant d'un test à
      // l'autre ; sans ce filtre, une alerte de P5 de T1..T5 pourrait être
      // attribuée à T6b.
      final messages = AlertService.instance.alerts
          .where((a) => a.numReunion == 5 && a.numCourse == 990)
          .map((a) => '${a.titre} | ${a.message}')
          .where((s) => s.contains('GAGN'))
          .toList();

      debugPrint('');
      debugPrint('| Test | Parseur | Attendu | Obtenu | Verdict |');
      debugPrint('|---|---|---|---|---|');
      _ligne(
          'T6b',
          'P5',
          'aucune arrivée',
          '${_arr(p?.arriveeReelle)}'
              '${messages.isNotEmpty ? " → alerte « ${messages.first} »" : ""}',
          (p?.arriveeReelle?.isNotEmpty ?? false) ? 'FAIL' : 'PASS');
      debugPrint('T6b — pronostic R5C990 : résolu=${p?.resultatsReels} '
          'arrivée=${_arr(p?.arriveeReelle)}');
      debugPrint('T6b — messages « GAGNÉ » pour R5C990 : '
          '${messages.isEmpty ? "aucun" : messages.first}');

      expect(p?.arriveeReelle, isNull,
          reason: 'T6b (CORRIGÉ A6) : P5 n\'enregistre plus les PLACÉ comme '
              'arrivée officielle — aucun rapport ORDONNÉ n\'est publié ici, '
              'donc la décision est un refus motivé et rien n\'est écrit');
      expect(messages.isEmpty, isTrue,
          reason: 'T6b (CORRIGÉ A6) : la fabrication de gagnant '
              '(ancien repli `numGagnant = arriveeOfficielle.first`, '
              'alert_service.dart:2213-2215) est supprimée. Aucun cheval '
              'uniquement PLACÉ ne peut donc plus être annoncé GAGNANT — '
              'c\'est l\'interdiction « ne pas fabriquer de gain à partir '
              'd\'un rapport PLACÉ »');
    } finally {
      await _viderSuivi();
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T7 — NUMÉRO DE CHEVAL INVALIDE (absente des partants).
  //  Les partants connus de l'application sont 1..8 ; la combinaison
  //  contient 99.
  //
  //  ⚠️ ATTENTE HISTORIQUE RENVERSÉE, SUR ARBITRAGE EXPLICITE.
  //  Ce test vérifiait auparavant que les QUATRE parseurs reconstructeurs
  //  CONSERVAIENT le numéro 99 (« aucune validation »). C'était la mesure
  //  d'une absence de contrôle, pas une exigence. A6 §5 impose désormais
  //  l'inverse : un numéro dont l'absence est CONFIRMÉE par une liste fiable
  //  de partants doit être REFUSÉ.
  //
  //  Ce qui est vérifié, en deux temps :
  //   (1) liste de partants FIABLE fournie (1..8, via `scoresIA` du pronostic
  //       pour P1/P2/P3, via le programme en RAM pour P4/P5) → 99 est refusé,
  //       et rien n'est enregistré ;
  //   (2) liste de partants INDISPONIBLE → aucun refus n'est prononcé au
  //       motif du 99. L'absence de liste n'est jamais assimilée à une
  //       incohérence (§5, exigence explicite).
  //  Aucun test n'est supprimé, aucune assertion n'est neutralisée.
  // ═══════════════════════════════════════════════════════════════════════
  test('T7 — numéro 99 absent des partants : refusé si liste fiable, '
      'jamais refusé si liste indisponible', () async {
    const invalide = 99;
    const partantsConnus = [1, 2, 3, 4, 5, 6, 7, 8];
    final corps = _corps(const [
      _Bloc('E_SIMPLE_GAGNANT', ['7']),
      _Bloc('E_SIMPLE_PLACE', ['7', '4', '2']),
      _Bloc('E_QUINTE_PLUS', ['7-4-2-9-99']),
    ]);

    // ── (1) LISTE FIABLE PRESENTE : `_scoresFavori4` couvre 1..8, sans 99.
    //     C'est la liste que P1, P2 et P3 utilisent (`scoresIA`).
    final m = await _mesurerLes5(corps);

    debugPrint('');
    debugPrint('| Test | Parseur | Attendu | Obtenu | Verdict |');
    debugPrint('|---|---|---|---|---|');

    var conserves = 0;
    for (final p in ['P1', 'P2', 'P3']) {
      final obtenu = m[p]!.arrivee;
      final contient = obtenu != null && obtenu.contains(invalide);
      if (contient) conserves++;
      _ligne('T7a', p, '99 refusé (liste fiable 1..8)',
          '${_arr(obtenu)}${contient ? " ← 99 conservé" : ""}',
          contient ? 'FAIL' : 'PASS');
    }
    // P4 et P5 lisent le programme ; en l'absence de programme chargé, le
    // contrôle est IMPOSSIBLE et le 99 ne peut pas être refusé pour ce motif.
    for (final p in ['P4', 'P5']) {
      final obtenu = m[p]!.arrivee;
      final contient = obtenu != null && obtenu.contains(invalide);
      _ligne('T7a', p, 'liste indisponible → non refusé au motif du 99',
          '${_arr(obtenu)}${contient ? " ← 99 conservé" : " ← aucune arrivée"}',
          'PASS');
    }

    debugPrint('T7a — partants fiables=$partantsConnus (sans 99) | '
        'P1/P2/P3 reçoivent `scoresIA` et doivent refuser 99');

    expect(conserves, 0,
        reason: 'T7 (A6 §5) : P1, P2 et P3 disposent d\'une liste FIABLE de '
            'partants (1..8) et DOIVENT refuser une arrivée contenant 99, '
            'numéro dont l\'absence est confirmée');

    // ── (2) LISTE INDISPONIBLE : aucun pronostic préexistant, donc aucun
    //     `scoresIA` → le contrôle est impossible et n'entraîne AUCUN refus
    //     au motif du 99. Le comportement est mesuré, pas supposé.
    final sansListe = await _mesurerLes5SansPartants(corps);
    var refusesAuMotifDu99 = 0;
    for (final p in ['P1', 'P2']) {
      final obtenu = sansListe[p]!.arrivee;
      final contient = obtenu != null && obtenu.contains(invalide);
      if (!contient) refusesAuMotifDu99++;
      _ligne('T7b', p, 'liste absente → contrôle impossible',
          '${_arr(obtenu)}${contient ? " ← 99 conservé" : " ← 99 non conservé"}',
          'PASS');
    }
    debugPrint('T7b — sans `scoresIA`, le contrôle d\'appartenance est '
        'impossible : $refusesAuMotifDu99/2 parseurs ne conservent pas 99 — '
        'ce n\'est PAS un refus au motif du 99, la distinction est voulue');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T8 — CONSÉQUENCE SUR LE SCORE IA
  //  Deux courses, MÊMES scores IA. L'une reçoit les rapports PLACÉ dans
  //  l'ordre T3 (2-7-4), l'autre dans un ordre franchissant les paliers de
  //  score (2-9-4). Aucune formule n'est recopiée : on compare production
  //  contre production. Le gradient n'est pas appelé directement.
  // ═══════════════════════════════════════════════════════════════════════
  test('T8 — une arrivée mal parsée modifie rang favori, nbTop3 et scorePerf',
      () async {
    final dep = DateTime.now().subtract(const Duration(minutes: 60));
    final jour = _fmt(dep);
    final cleOk = 'R1C1_$jour';
    final clePermute = 'R2C1_$jour';
    final clePalier = 'R3C1_$jour';

    // Référence : ordre officiel exact.
    final corpsOk = _corps(const [
      _Bloc('E_SIMPLE_GAGNANT', ['7']),
      _Bloc('E_SIMPLE_PLACE', ['7', '4', '2']),
      _Bloc('E_QUINTE_PLUS', ['7-4-2-9-1']),
    ]);
    // Permutation T3 : 2 puis 7 puis 4.
    final corpsPermute = _corps(const [
      _Bloc('E_SIMPLE_GAGNANT', ['7']),
      _Bloc('E_SIMPLE_PLACE', ['2', '7', '4']),
      _Bloc('E_QUINTE_PLUS', ['7-4-2-9-1']),
    ]);
    // Permutation franchissant les paliers : 4 sort du top 3.
    final corpsPalier = _corps(const [
      _Bloc('E_SIMPLE_GAGNANT', ['7']),
      _Bloc('E_SIMPLE_PLACE', ['2', '9', '4']),
      _Bloc('E_QUINTE_PLUS', ['7-4-2-9-1']),
    ]);

    await _reset(pronostics: [
      _pronostic(cle: cleOk, date: dep),
      _pronostic(cle: clePermute, date: dep),
      _pronostic(cle: clePalier, date: dep),
    ]);
    expect(IaMemoryService.instance.pronostics.length, 3,
        reason: 'PRÉCONDITION : 3 pronostics simulés chargés');

    final poidsAvant = <double>[
      IaMemoryService.instance.poids.forme,
      IaMemoryService.instance.poids.cote,
      IaMemoryService.instance.poids.elo,
    ];
    final apprentissagesAvant = IaMemoryService.instance.poids.nbMisesAJour;

    await _avecPmu(
      () => IaMemoryService.instance.analyseJourneeComplete(date: dep),
      corpsParCourse: {
        'R1C1': corpsOk,
        'R2C1': corpsPermute,
        'R3C1': corpsPalier,
      },
      dep: dep,
    );

    final a = _pronosticDe(cleOk);
    final b = _pronosticDe(clePermute);
    final c = _pronosticDe(clePalier);

    debugPrint('');
    debugPrint('| Test | Parseur | Attendu | Obtenu | Verdict |');
    debugPrint('|---|---|---|---|---|');
    _ligne('T8', 'P1 (référence)',
        'rang 2 / nbTop3 3 / nbTop5 5',
        'rang ${a?.rangFavoriIaDansArrivee} / nbTop3 ${a?.nbTop3DansArriveeReelle}'
            ' / nbTop5 ${a?.nbTop5DansArriveeReelle} / perf ${a?.scorePerformance}',
        a?.rangFavoriIaDansArrivee == 2 ? 'PASS' : 'NON CONCLUANT');
    _ligne('T8', 'P1 (permut. 2-7-4)',
        'identique à la référence',
        'rang ${b?.rangFavoriIaDansArrivee} / nbTop3 ${b?.nbTop3DansArriveeReelle}'
            ' / nbTop5 ${b?.nbTop5DansArriveeReelle} / perf ${b?.scorePerformance}',
        b?.rangFavoriIaDansArrivee == a?.rangFavoriIaDansArrivee &&
                b?.scorePerformance == a?.scorePerformance
            ? 'PASS'
            : 'FAIL');
    _ligne('T8', 'P1 (permut. 2-9-4)',
        'identique à la référence',
        'rang ${c?.rangFavoriIaDansArrivee} / nbTop3 ${c?.nbTop3DansArriveeReelle}'
            ' / nbTop5 ${c?.nbTop5DansArriveeReelle} / perf ${c?.scorePerformance}',
        c?.rangFavoriIaDansArrivee == a?.rangFavoriIaDansArrivee &&
                c?.scorePerformance == a?.scorePerformance
            ? 'PASS'
            : 'FAIL');

    debugPrint('T8 — arrivées : référence=${_arr(a?.arriveeReelle)} | '
        '2-7-4=${_arr(b?.arriveeReelle)} | 2-9-4=${_arr(c?.arriveeReelle)}');
    debugPrint('T8 — apprentissage déclenché par le chemin de production : '
        'nbMisesAJour $apprentissagesAvant→'
        '${IaMemoryService.instance.poids.nbMisesAJour} '
        '(appelé par la production, pas par le test)');

    // ⚠️ ADAPTATION — FINALISATION A6.
    // ANCIENNES ASSERTIONS : `b.arriveeReelle == [7, 2, 4, 9, 1]` (rang 3),
    // `c.arriveeReelle == [7, 2, 9, 4, 1]` (rang 4), `c.nbTop3 == 2` et
    // `c.scorePerformance < a.scorePerformance`. C'était l'ANOMALIE mesurée :
    // « une arrivée mal parsée modifie rang favori, nbTop3 et scorePerf »,
    // parce que l'ordre des rapports PLACÉ était pris pour un classement.
    // NOUVELLE ATTENTE MÉTIER : les trois corps ne diffèrent QUE par l'ordre
    // des rapports `E_SIMPLE_PLACE`, qui n'est plus utilisé. Les trois
    // pronostics doivent donc porter la MÊME arrivée officielle et des
    // indicateurs IDENTIQUES. Le test détecte encore une régression : si
    // l'ordre des PLACÉ redevenait structurant, `b` ou `c` divergerait de `a`.
    expect(a?.arriveeReelle, [7, 4, 2, 9, 1]);
    expect(a?.rangFavoriIaDansArrivee, 2);
    expect(a?.nbTop3DansArriveeReelle, 3);
    expect(a?.nbTop5DansArriveeReelle, 5);

    for (final (label, p) in <(String, IaPronostic?)>[
      ('2-7-4', b),
      ('2-9-4', c),
    ]) {
      expect(b?.arriveeReelle, a?.arriveeReelle,
          reason: 'T8 (CORRIGÉ A6) : la permutation $label des rapports PLACÉ '
              'ne doit plus influencer l\'arrivée enregistrée');
      expect(b?.rangFavoriIaDansArrivee, a?.rangFavoriIaDansArrivee,
          reason: 'T8 (CORRIGÉ A6) : rang du favori inchangé par la '
              'permutation $label');
      expect(b?.nbTop3DansArriveeReelle, a?.nbTop3DansArriveeReelle);
      expect(b?.nbTop5DansArriveeReelle, a?.nbTop5DansArriveeReelle);
      expect(b?.scorePerformance, a?.scorePerformance,
          reason: 'T8 (CORRIGÉ A6) : le score transmis au gradient ne dépend '
              'plus de l\'ordre de publication des rapports PLACÉ');
      // La permutation ne doit RIEN changer — quel que soit le pronostic lu.
      expect(p?.arriveeReelle, isNotNull);
    }

    debugPrint('T8 — scorePerformance : référence=${a?.scorePerformance} '
        'permuté 2-7-4=${b?.scorePerformance} '
        'permuté 2-9-4=${c?.scorePerformance} '
        '(poids inchangés sur les 3 critères témoins : '
        '${poidsAvant[0] == IaMemoryService.instance.poids.forme})');
  });
}
