// ═══════════════════════════════════════════════════════════════════════════
//  B5c — R-DR-01 — VÉRIFICATION 4 : LE VRAI CHEMIN DE PRODUCTION
//
//  OBJET : exercer réellement
//      DataRefreshService.refresh()  (→ _doRefresh, public l.565)
//        → ZoneTurfService.chargerProgramme()   [réseau intercepté]
//        → DataRefreshService._sauvegarderCacheLocal()  (l.531, .ignore())
//        → prefs.setString(cle, …) + prefs.setInt('${cle}_ts', …)  (l.329-330)
//
//  MÉTHODE D'INJECTION : `http.runWithClient` + `MockClient` de
//  `package:http/testing.dart`. Patron DÉJÀ VALIDÉ dans ce projet
//  (test/v10_a6s_production_path_test.dart l.174-189). Aucune modification
//  de production.
//
//  ⚠️ CHOIX DÉLIBÉRÉ : la réunion de fixture contient UNE COURSE SANS
//  AUCUN PARTANT. Conséquences vérifiées dans le code de production :
//    • `_appliquerScoresIA` (zone_turf l.807) → `if (partants.isNotEmpty)`
//      FAUX → aucun calcul IA exécuté ;
//    • `_enregistrerPronosticsBatchIsolate` (data_refresh l.664)
//      `if (course.partants.isEmpty) continue` → `reunionsFiltrees` vide →
//      `return` → AUCUN pronostic créé, aucune écriture IA ;
//    • `_recupererResultatsBatch` (l.868) → `pronosticsEnAttente` vide →
//      `return` → aucune arrivée enregistrée, aucun apprentissage.
//  ⇒ Le chemin d'écriture du CACHE est exercé, la mémoire IA n'est pas
//    touchée. C'est la seule façon de tester l'un sans l'autre.
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

import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';
import 'package:pronostic_hippique/models/zt_models.dart';

// ── Store contrôlable ───────────────────────────────────────────────────────
class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  Completer<void>? _verrouSet;
  Completer<void>? _entreeSet;
  String? _cleSuspendue;

  Completer<void>? _verrouRemove;
  Completer<void>? _entreeRemove;
  String? _cleRemoveSuspendue;

  /// Politique d'échec : si non nul, `setValue` sur cette clé renvoie false.
  String? cleEnEchec;

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
    if (_cleRemoveSuspendue != null && key == _cleRemoveSuspendue) {
      final entree = _entreeRemove;
      _entreeRemove = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      await _verrouRemove!.future;
    }
    // SharedPreferences retourne `true` même si la clé est absente :
    // `remove` réussit (idempotent). Retourner `false` ferait échouer
    // `BackupService` pour toutes les clés vides, ce qui n'a rien à voir
    // avec le défaut étudié.
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET $key');
    if (cleEnEchec != null && key == 'flutter.$cleEnEchec') return false;
    final verrou = (_cleSuspendue != null && key == _cleSuspendue) ? _verrouSet : null;
    if (verrou != null) {
      final entree = _entreeSet;
      _entreeSet = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      await verrou.future;
    }
    _valeurs[key] = value;
    return true;
  }

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

  Completer<void> armerSuspensionRemove(String cle) {
    final entree = Completer<void>();
    _entreeRemove = entree;
    _verrouRemove = Completer<void>();
    _cleRemoveSuspendue = 'flutter.$cle';
    return entree;
  }

  void libererRemove() {
    final v = _verrouRemove;
    _verrouRemove = null;
    _cleRemoveSuspendue = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  List<String> clesCacheReunions() => _valeurs.keys
      .where((k) => k.startsWith('flutter.cache_reunions_'))
      .map((k) => k.replaceFirst('flutter.', ''))
      .toList()
    ..sort();

  List<String> depuis(int i) => journal.sublist(i);
}

// ignore: library_private_types_in_public_api
late _Store store;

Future<void> _laisserProgresser([int tours = 40]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<bool> _attendreQue(bool Function() c, [int max = 2000]) async {
  for (var i = 0; i < max; i++) {
    if (c()) return true;
    await Future<void>.delayed(Duration.zero);
  }
  return c();
}

// ── Fixture PMU : champs LUS PAR LE PARSEUR, rien de plus ──────────────────
//
//  Références dans zone_turf_service.dart :
//    l.76  progData['programme']['reunions']          → List
//    l.87  r['hippodrome']['libelleLong']             → String (filtre pays)
//    l.93  hippo['libelleCourt'] ?? hippo['libelle']  → lieu
//    l.94  r['numOfficiel']                           → int
//    l.95  r['courses']                               → List
//    l.99  coursesJson.first['discipline']            → String
//    l.114 c['numOrdre']                              → int
//    l.115 c['libelle'] ?? c['libelleCourt']          → nom
//    l.116 c['distance']                              → int
//    l.117 c['montantPrix']                           → int
//    l.118 c['discipline']                            → String
//    l.121 c['paris'][].typePari                      → List
//    l.146 c['heureDepart']                           → int (millisecondes)
//    l.154 _chargerPartants → data['participants']    → List
//
//  Aucun autre champ n'est lu. On n'en invente aucun.
String get _dateDuJour {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

String get kCleCache => 'cache_reunions_$_dateDuJour';
String get kCleTs => '${kCleCache}_ts';

/// Un programme d'UNE réunion, UNE course, ZÉRO partant.
String _programmePmu({required String lieu, int numOfficiel = 1}) {
  final depart = DateTime.now()
      .add(const Duration(hours: 3))
      .millisecondsSinceEpoch;
  return jsonEncode({
    'programme': {
      'reunions': [
        {
          'numOfficiel': numOfficiel,
          'hippodrome': {
            'libelleLong': '$lieu (FRANCE)',
            'libelleCourt': lieu,
          },
          'courses': [
            {
              'numOrdre': 1,
              'libelle': 'PRIX DE LA FIXTURE R-DR-01',
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

const String _participantsVides = '{"participants": []}';

/// Exécute [action] avec le réseau PMU simulé.
Future<T> _avecPmuSimule<T>(
  Future<T> Function() action, {
  String? lieu,
  List<Uri>? urlsVues,
}) {
  final client = MockClient((request) async {
    urlsVues?.add(request.url);
    final path = request.url.path;
    if (path.contains('participants')) {
      return http.Response(_participantsVides, 200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response(_programmePmu(lieu: lieu ?? 'VINCENNES'), 200,
        headers: {'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
  });

  tearDown(() {
    store.libererSet();
    store.libererRemove();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R01-I — PREUVE : le vrai chemin atteint les DEUX setValue
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-I — refresh() exerce _sauvegarderCacheLocal et écrit les DEUX clés',
      () async {
    final urls = <Uri>[];
    final marque = store.journal.length;

    await _avecPmuSimule(
      () => DataRefreshService.instance.refresh(),
      lieu: 'VINCENNES',
      urlsVues: urls,
    );
    await _attendreQue(() => store.contient(kCleTs));
    await _laisserProgresser();

    final journal = store.depuis(marque);
    final cles = store.clesCacheReunions();

    debugPrint('R01-I URLs vues : ${urls.map((u) => u.path).toList()}');
    debugPrint('R01-I journal  : $journal');
    debugPrint('R01-I cles     : $cles');
    debugPrint('R01-I RAM      : ${DataRefreshService.instance.reunions.length} '
        'réunion(s)');

    // ── 1. Le réseau a RÉELLEMENT été appelé (deux endpoints PMU) ────────
    expect(urls.any((u) => u.path.contains('/programme/')), isTrue,
        reason: 'PREUVE : chargerProgramme() a bien émis la requête programme '
            'via http.get() intercepté par runWithClient');
    expect(urls.any((u) => u.path.contains('participants')), isTrue,
        reason: 'PREUVE : _chargerPartants() a bien émis la requête '
            'participants — c\'est le parseur réel qui a tourné');

    // ── 2. La réunion a été construite et retenue en RAM ────────────────
    expect(DataRefreshService.instance.reunions.length, 1,
        reason: 'PREUVE : la fixture a traversé le parseur réel '
            '(_estHippodromeFrancais, _pmuDisciplineToZt, ZtReunion…) et '
            '`_reunions = reunions` (data_refresh l.520) a eu lieu');

    // ── 3. Les DEUX setValue de _sauvegarderCacheLocal ont été atteints ──
    expect(journal, contains('SET flutter.$kCleCache'),
        reason: 'PREUVE n°1 : `prefs.setString(cle, json)` (l.329) est '
            'réellement atteint par le chemin de production — sans aucune '
            'reconstruction du corps de la méthode dans le test');
    expect(journal, contains('SET flutter.$kCleTs'),
        reason: 'PREUVE n°2 : `prefs.setInt(\'\${cle}_ts\', …)` (l.330) est '
            'réellement atteint');

    // ── 4. Les deux clés EXISTENT, avec le bon contenu ──────────────────
    expect(cles, containsAll(<String>[kCleCache, kCleTs]),
        reason: 'PREUVE : les deux clés « cache_reunions_* » sont écrites');
    expect(store.contient(kCleCache), isTrue);
    expect(store.contient(kCleTs), isTrue);

    final jsonCache = store.lire(kCleCache) as String;
    final decode = jsonDecode(jsonCache) as List<dynamic>;
    expect(decode.length, 1,
        reason: 'PREUVE : le contenu est bien le JSON des réunions sérialisées '
            'par `jsonEncode(reunions.map((r) => r.toJson()).toList())`');
    expect((decode.first as Map<String, dynamic>)['code'], 'R1',
        reason: 'PREUVE : la réunion sérialisée porte le code issu du '
            '`numOfficiel` de la fixture');
    expect((decode.first as Map<String, dynamic>)['lieu'], 'VINCENNES');

    expect(store.lire(kCleTs), isA<int>(),
        reason: 'PREUVE : la clé _ts contient bien un int (epoch ms)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R01-J — CONCURRENCE : reset pendant setString du CACHE
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-J — reset pendant l\'écriture du cache : aucune clé ne réapparaît',
      () async {
    store.armerSuspensionSet(kCleCache);
    final marque = store.journal.length;

    // `_sauvegarderCacheLocal(...).ignore()` : on n'attend pas refresh().
    final refresh = _avecPmuSimule(
        () => DataRefreshService.instance.refresh(),
        lieu: 'DEAUVILLE');

    final suspendu = await _attendreQue(
        () => store.journal.contains('SET flutter.$kCleCache'));
    expect(suspendu, isTrue,
        reason: 'GARDE DE PRÉCONDITION : setString est retenu — l\'écriture '
            'est ENGAGÉE');

    //  ⚠️ R-DR-01-c a changé la nature de ce scénario : l'écriture du cache
    //  est désormais ENREGISTRÉE au registre de DataRefreshService et DRAINÉE
    //  par le reset. Attendre le reset ici produirait un interblocage du TEST
    //  (la production, elle, se comporte correctement : elle attend).
    //  On lance donc le reset SANS l'attendre, on vérifie que la barrière est
    //  engagée, puis on libère.
    final reset = BackupService.instance.reinitialiserComplet();
    await _laisserProgresser(120);

    final pendant = store.depuis(marque);
    debugPrint('R01-J pendant reset : cles=${store.clesCacheReunions()}');

    // Libération : le drain peut conclure, puis le reset se termine.
    store.libererSet();
    await refresh;
    await reset;
    await _laisserProgresser(150);

    debugPrint('R01-J après : cles=${store.clesCacheReunions()}');
    debugPrint('R01-J journal SET : '
        '${pendant.where((e) => e.startsWith("SET flutter.cache_reunions")).toList()}');

    //  ★ INVERSÉE en R-DR-01-c. Elle démontrait le défaut : une écriture
    //  engagée avant le reset et terminée pendant réinscrivait les clés.
    //  Aujourd'hui `_sauvegarderCacheLocal` passe par `_ecrireProtegeCache`,
    //  dont les DEUX contrôles refusent l'écriture, et le reset DRAINE le
    //  registre : la clé ne peut plus réapparaître.
    expect(store.contient(kCleCache), isFalse,
        reason: 'CORRECTION R01-c : une écriture engagée avant le reset et '
            'terminée pendant ne réinscrit PAS la clé JSON');
    expect(store.contient(kCleTs), isFalse,
        reason: 'CORRECTION R01-c : et pas davantage la clé d\'horodatage — '
            'aucune paire n\'est reconstituée après un reset terminé');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R01-K — ATOMICITÉ LOGIQUE DE LA PAIRE DE CACHE
  //
  //  CONTRAT DE PRODUCTION APRÈS R-DR-01-c :
  //    • ordre d'écriture INVERSÉ : `_ts` d'abord, JSON ensuite ;
  //    • un `_ts` orphelin (JSON absent) est INOFFENSIF, car
  //      `_chargerCacheLocal` lit le JSON en premier et sort s'il est null
  //      (l.296) ;
  //    • un échec comme une interruption laissent le disque SANS clé orpheline
  //      après la clôture du reset.
  //
  //  SCÉNARIO : on suspend le JSON. L'état intermédiaire observable est donc
  //  « `_ts` posé, JSON absent ». On vérifie cet état AU BON INSTANT, puis on
  //  laisse le reset drainer et refuser l'écriture restée en vol.
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-K — état intermédiaire `_ts` posé / JSON absent, puis disque propre',
      () async {
    //  On suspend le JSON, PAS le `_ts` : les deux écritures sont
    //  SÉQUENTIELLES, donc suspendre le `_ts` empêcherait le JSON d'être
    //  jamais tenté et le témoin attendrait indéfiniment.
    store.armerSuspensionSet(kCleCache);
    final marque = store.journal.length;

    final refresh = _avecPmuSimule(
        () => DataRefreshService.instance.refresh(),
        lieu: 'ENGHIEN');

    final suspendu = await _attendreQue(() =>
        store.journal.sublist(marque).contains('SET flutter.$kCleCache'));
    expect(suspendu, isTrue,
        reason: 'GARDE DE PRÉCONDITION : l\'écriture du JSON est retenue');

    // ── ÉTAT INTERMÉDIAIRE, mesuré À LA SUSPENSION ────────────────────────
    debugPrint('R01-K à la suspension : ts=${store.contient(kCleTs)} '
        'cache=${store.contient(kCleCache)}');
    expect(store.contient(kCleTs), isTrue,
        reason: 'FAIT : `_ts` est écrit en PREMIER (ordre inversé) et a abouti '
            'avant la suspension du JSON');
    expect(store.contient(kCleCache), isFalse,
        reason: 'FAIT : le JSON est retenu — l\'état est bien '
            '« horodatage présent, JSON absent »');

    // ── Reset lancé SANS être attendu : il draine cette écriture ──────────
    final reset = BackupService.instance.reinitialiserComplet();
    await _laisserProgresser(120);

    // ── Libération, puis clôture du reset ────────────────────────────────
    store.libererSet();
    await refresh;
    await reset;
    await _laisserProgresser(150);

    final finales = store.clesCacheReunions();
    debugPrint('R01-K final : cles=$finales');

    // ── NON-RÉGRESSION : aucune clé orpheline après la clôture ───────────
    expect(finales, isEmpty,
        reason: 'NON-RÉGRESSION R01-c : après la clôture du reset, le disque '
            'ne contient AUCUNE clé de cache — ni le JSON, ni le `_ts` qui '
            'avait pourtant abouti avant le reset');
    expect(store.contient(kCleTs), isFalse,
        reason: 'NON-RÉGRESSION R01-c : le `_ts` posé avant le reset n\'est '
            'pas réintroduit');
    expect(store.contient(kCleCache), isFalse,
        reason: 'NON-RÉGRESSION R01-c : et le JSON refusé ne l\'est pas non '
            'plus');
  });


  // ═══════════════════════════════════════════════════════════════════════
  //  R01-L — ÉCHEC de setString : comportement du cache
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-L — échec de setString : le cache reste absent, sans exception',
      () async {
    store.cleEnEchec = kCleCache;

    await _avecPmuSimule(
        () => DataRefreshService.instance.refresh(),
        lieu: 'VIRE');
    await _attendreQue(() => store.contient(kCleTs));
    await _laisserProgresser();

    debugPrint('R01-L : cache=${store.contient(kCleCache)} '
        'ts=${store.contient(kCleTs)}');

    expect(store.contient(kCleCache), isFalse,
        reason: 'FAIT : setString en échec (retour false) → la clé n\'est pas '
            'écrite. `_sauvegarderCacheLocal` ne teste PAS le retour de '
            'setString : l\'échec est SILENCIEUX');
    //  ★ INVERSÉE en R-DR-01-c : le `_ts` est désormais RETIRÉ quand
    //  `setString` échoue, et l'erreur est rendue observable.
    expect(store.contient(kCleTs), isFalse,
        reason: 'CORRECTION R01-c : quand setString échoue, la clé '
            'd\'horodatage déjà posée est RETIRÉE — plus de clé orpheline');
    expect(DataRefreshService.instance.derniereErreurCache, isNotNull,
        reason: 'CORRECTION R01-c : l\'échec n\'est plus silencieux — il est '
            'exposé par `derniereErreurCache`');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R01-M — ZONETURFSERVICE : le cache statique ignore-t-il forceRefresh ?
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-M — le cache statique de ZoneTurf court-circuite un 2e refresh()',
      () async {
    final urls = <Uri>[];

    // 1er refresh : réseau sollicité, cache statique peuplé.
    await _avecPmuSimule(
        () => DataRefreshService.instance.refresh(),
        lieu: 'CAGNES', urlsVues: urls);
    await _attendreQue(() => store.contient(kCleTs));
    final appelsApres1 = urls.length;
    debugPrint('R01-M 1er refresh : $appelsApres1 appel(s) réseau');

    // 2e refresh, MÊME DateStr : `refresh()` passe forceRefresh: true.
    await _avecPmuSimule(
        () => DataRefreshService.instance.refresh(),
        lieu: 'CAGNES', urlsVues: urls);
    await _laisserProgresser();
    final appelsApres2 = urls.length;
    debugPrint('R01-M 2e refresh : ${appelsApres2 - appelsApres1} appel(s) '
        'supplémentaire(s) — total $appelsApres2');

    expect(appelsApres2 - appelsApres1, greaterThan(0),
        reason: 'FAIT : `refresh()` → `_doRefresh(force: true)` → '
            '`chargerProgramme(forceRefresh: true)` (zone_turf l.52) : le '
            'cache statique est bien CONTOURNÉ. Le risque théorique '
            '« forceRefresh ignoré » est DONC RÉFUTÉ sur ce chemin');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R01-N — le cache statique réinjecte-t-il des données antérieures ?
  //
  //  ÉTAT AVANT R-DR-01-b : ce test affirmait le DÉFAUT — le cache statique
  //  `_cache[dateStr]` de ZoneTurfService servait encore les réunions
  //  d'AVANT le reset (`reunions=1 appelsRéseau=0`). R-DR-01-b ajoute la
  //  purge : l'assertion est donc INVERSÉE, pas supprimée.
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-N — le cache statique de ZoneTurf est purgé par le reset', () async {
    await _avecPmuSimule(
        () => DataRefreshService.instance.refresh(),
        lieu: 'MARSEILLE');
    await _attendreQue(() => store.contient(kCleTs));

    // TÉMOIN DE PRÉPARATION : sans purge, un appel SANS forceRefresh est servi
    // par le cache statique chaud, sans aucun appel réseau. On le vérifie
    // AVANT le reset, sinon l'assertion d'après ne prouverait rien.
    final urlsAvant = <Uri>[];
    final avantReset = await _avecPmuSimule(
        () => _chargerSansForce(), lieu: 'MARSEILLE', urlsVues: urlsAvant);
    debugPrint('R01-N témoin avant reset : reunions=${avantReset.length} '
        'appelsRéseau=${urlsAvant.length}');
    expect(urlsAvant, isEmpty,
        reason: 'TÉMOIN DE PRÉPARATION : le cache statique est bien CHAUD avant '
            'le reset — un `chargerProgramme()` sans forceRefresh est servi '
            'depuis `_cache[dateStr]` (zone_turf_service l.52-58)');
    expect(avantReset.length, 1,
        reason: 'TÉMOIN DE PRÉPARATION : il sert effectivement une réunion');

    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    // Appel SANS forceRefresh : c'est le chemin des écrans
    // (best_bet_screen l.182, conseils_screen l.184, races_screen l.67).
    final urls = <Uri>[];
    final reunions = await _avecPmuSimule(
        () => _chargerSansForce(),
        lieu: 'MARSEILLE', urlsVues: urls);
    await _laisserProgresser();

    debugPrint('R01-N après reset : reunions=${reunions.length} '
        'appelsRéseau=${urls.length}');

    expect(urls, isNotEmpty,
        reason: 'CORRECTION R-DR-01-b : sans `forceRefresh`, le chemin des '
            'écrans repart désormais AU RÉSEAU — `_cache` a été purgé. Avant '
            'la correction, aucun appel n\'était émis et les réunions '
            'd\'avant le reset étaient resservies');
    expect(reunions.length, 1,
        reason: 'CORRECTION R-DR-01-b : le chargement aboutit sur des données '
            'FRAÎCHES (la fixture réseau), et non plus sur l\'état antérieur '
            'au reset. Le service reste pleinement fonctionnel');
  });
}

/// Chemin des écrans : `chargerProgramme()` SANS forceRefresh.
/// `forceRefresh` a pour défaut `false` (zone_turf_service.dart l.43).
Future<List<ZtReunion>> _chargerSansForce() =>
    ZoneTurfService.chargerProgramme();
