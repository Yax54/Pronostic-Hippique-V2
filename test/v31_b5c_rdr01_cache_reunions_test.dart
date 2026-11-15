// ═══════════════════════════════════════════════════════════════════════════
//  B5c — ÉTAPE 7 — R-DR-01 — CACHE DES RÉUNIONS (PHASE 1 : DIAGNOSTIC)
//
//  OBJET : mesurer si le cache disque `cache_reunions_<ddmmyyyy>` (+ `_ts`)
//  survit à `BackupService.reinitialiserComplet()` et si le cache RAM
//  `DataRefreshService._reunions` est invalidé.
//
//  AUCUNE MODIFICATION DE PRODUCTION DANS CETTE PHASE.
//  Les tests n'utilisent que des API publiques et le store de test.
//
//  ⚠️ LIMITE DÉCLARÉE HONNÊTEMENT :
//  `_sauvegarderCacheLocal()` est PRIVÉE et n'est appelée que depuis
//  `_doRefresh()` (l.531), elle-même déclenchée par `refresh()`/`init()`.
//  En environnement de test, `HttpClient` renvoie 400 → `chargerProgramme()`
//  renvoie `[]` → `if (reunions.isNotEmpty)` (l.530) est FAUX → la production
//  ne sauvegarde JAMAIS le cache. Il est donc IMPOSSIBLE de déclencher une
//  écriture réelle de `_sauvegarderCacheLocal` sans hook de test.
//
//  Pour les scénarios C, D, E, j'exécute donc les DEUX appels EXACTS du corps
//  de `_sauvegarderCacheLocal` (l.329-331) :
//      await prefs.setString(cle, jsonEncode(...));
//      await prefs.setInt('${cle}_ts', ...);
//  C'est une SIMULATION DU CHEMIN D'ÉCRITURE, pas l'appel réel de la méthode.
//  Je le déclare : cela prouve que les clés sont réécrites sans être protégées,
//  cela ne prouve pas le moment exact où la production les écrit.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';

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

  /// Suspend le premier `setValue` sur `cle` (clé SANS préfixe).
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

  /// Suspend le `remove` sur `cle` (clé SANS préfixe).
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

  /// Simule l'effacement total d'un reset (utilisé dans les closures de reset).
  void effacerDirect(String cle) {
    journal.add('REM flutter.$cle');
    _valeurs.remove('flutter.$cle');
  }
}

// ignore: library_private_types_in_public_api
late _Store store;

Future<void> _laisserProgresser([int tours = 24]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<bool> _attendreQue(bool Function() condition, [int maxTours = 1200]) async {
  for (var i = 0; i < maxTours; i++) {
    if (condition()) return true;
    await Future<void>.delayed(Duration.zero);
  }
  return condition();
}

// ── Fixtures ────────────────────────────────────────────────────────────────
const String kPrefix = 'cache_reunions_';

String _dateDuJour() {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

String get kCleCache => '$kPrefix${_dateDuJour()}';
String get kCleTs => '${kCleCache}_ts';

/// Réunion minimale : aucune course, ce qui suffit pour le cache local
/// (`_initialiserEtatPartants` itère sur une liste vide).
List<ZtReunion> _reunions([String lieu = 'VINCENNES']) => <ZtReunion>[
      ZtReunion(
        code: 'R1',
        lieu: lieu,
        discipline: 'Trot',
        dateStr: _dateDuJour(),
        courses: const <ZtCourse>[],
      ),
    ];

String _jsonDes(List<ZtReunion> r) =>
    jsonEncode(r.map((x) => x.toJson()).toList());

/// Reproduit EXACTEMENT les deux écritures de `_sauvegarderCacheLocal`
/// (data_refresh_service.dart l.329-331), sans `_nettoyerAnciensCache`.
Future<void> _ecrireCacheCommeLaProduction(
    List<ZtReunion> reunions, String dateStr) async {
  final prefs = await SharedPreferences.getInstance();
  final cle = '$kPrefix$dateStr';
  await prefs.setString(cle, _jsonDes(reunions));
  await prefs.setInt('${cle}_ts', DateTime.now().millisecondsSinceEpoch);
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

  // `DataRefreshService.instance` est un `static final` : un `dispose()`
  // le rend DÉFINITIVEMENT inutilisable pour tout le processus de test
  // (`notifyListeners()` lève « used after being disposed »). On ne le
  // coupe donc qu'UNE fois, à la toute fin du fichier, pour satisfaire
  // flutter_test qui refuse un `Timer.periodic` encore actif.
  tearDownAll(() {
    DataRefreshService.instance.dispose();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A — CACHE PRÉSENT AVANT RESET (témoin)
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-A — le cache disque est présent et exploitable AVANT le reset',
      () async {
    store.semer(kCleCache, _jsonDes(_reunions()));
    store.semer(kCleTs, DateTime.now().millisecondsSinceEpoch);

    final cles = store.clesCacheReunions();
    debugPrint('R01-A avant : cles=$cles cache=${store.contient(kCleCache)} '
        'ts=${store.contient(kCleTs)}');

    expect(store.contient(kCleCache), isTrue,
        reason: 'TÉMOIN : la clé de cache existe sur le disque simulé');
    expect(store.contient(kCleTs), isTrue,
        reason: 'TÉMOIN : la clé d\'horodatage existe aussi — ce sont DEUX '
            'clés distinctes, et un correctif qui n\'en supprime qu\'une '
            'laisserait un cache orphelin');
    expect(cles.length, 2,
        reason: 'TÉMOIN : deux clés préfixées « cache_reunions_ » sont présentes');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B — CACHE TOUJOURS PRÉSENT APRÈS RESET  ← DÉFAUT PRINCIPAL
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-B — le cache disque est SUPPRIMÉ par reinitialiserComplet() [CORRIGÉ R01-a]',
      () async {
    store.semer(kCleCache, _jsonDes(_reunions()));
    store.semer(kCleTs, DateTime.now().millisecondsSinceEpoch);

    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    final apres = store.clesCacheReunions();
    debugPrint('R01-B : apres=$apres '
        'cache=${store.contient(kCleCache)} ts=${store.contient(kCleTs)}');
    debugPrint('R01-B : RAM reunions=${DataRefreshService.instance.reunions.length}');

    // ── CORRECTION R-DR-01-a (appliquée) ─────────────────────────────────
    //
    //  AVANT R01-a, les deux clés SURVIVAIENT : `cache_reunions_*` n'était
    //  dans aucune des 107 clés fixes, et une clé datée ne peut pas y être
    //  nommée. Le balayage dynamique de `reinitialiserComplet()` nomme
    //  désormais les clés réellement présentes.
    //
    //  Ce test documentait le DÉFAUT ; il documente maintenant la CORRECTION.
    //  La preuve positive (y compris `_ts` orpheline, clés étrangères
    //  préservées, échec enregistré) est dans
    //  `v32_b5c_rdr01a_suppression_test.dart`.
    expect(store.contient(kCleCache), isFalse,
        reason: 'CORRECTION R-DR-01-a : la clé « cache_reunions_<date> » est '
            'désormais SUPPRIMÉE par le reset complet');
    expect(store.contient(kCleTs), isFalse,
        reason: 'CORRECTION R-DR-01-a : la clé « cache_reunions_<date>_ts » '
            'l\'est aussi — elle commence par le même préfixe');
    expect(apres, isEmpty,
        reason: 'CORRECTION R-DR-01-a : plus aucune clé de cache ne subsiste '
            'après le reset (avant : les deux survivaient)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  C — ÉCRITURE ENGAGÉE AVANT LE RESET, TERMINÉE PENDANT
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-C — écriture engagée avant le reset, terminée pendant', () async {
    // Aucun cache au départ.
    expect(store.clesCacheReunions(), isEmpty, reason: 'TÉMOIN initial');

    final entree = store.armerSuspensionSet(kCleCache);
    final ecriture =
        _ecrireCacheCommeLaProduction(_reunions('DEAUVILLE'), _dateDuJour());

    final suspendu = await _attendreQue(() => store.journal.contains(
        'SET flutter.$kCleCache'));
    expect(suspendu, isTrue,
        reason: 'GARDE DE PRÉCONDITION : l\'écriture est bien retenue AVANT '
            'd\'atteindre le store');
    expect(entree.isCompleted, isTrue);

    // Le reset s'exécute pendant que l'écriture est suspendue.
    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    debugPrint('R01-C pendant : cles=${store.clesCacheReunions()}');

    // Libération : l'écriture aboutit APRÈS le reset.
    store.libererSet();
    await ecriture;
    await _laisserProgresser();

    final cles = store.clesCacheReunions();
    debugPrint('R01-C après : cles=$cles');

    // ── FAIT : le cache est RÉÉCRIT alors que le reset vient de passer ───
    expect(store.contient(kCleCache), isTrue,
        reason: 'DÉFAUT R-DR-01 : une écriture née AVANT le reset et terminée '
            'PENDANT réinscrit le cache. Aucune barrière ne la refuse : '
            '`_sauvegarderCacheLocal` ne consulte ni `_resetEnCours` ni aucune '
            'génération — contrairement à `_ecrireProtege` (IaMemory) ou '
            '`_sauvegarder` (EloService)');
    expect(cles.length, 2,
        reason: 'DÉFAUT : les deux clés (cache + _ts) sont réapparues');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D — ÉCRITURE TERMINÉE APRÈS LE RESET
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-D — écriture terminée APRÈS le reset : le cache revit', () async {
    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();
    expect(store.clesCacheReunions(), isEmpty,
        reason: 'TÉMOIN : aucun cache avant l\'écriture');

    // Écriture née APRÈS la fin du reset.
    await _ecrireCacheCommeLaProduction(_reunions('CAGNES'), _dateDuJour());
    await _laisserProgresser();

    final cles = store.clesCacheReunions();
    debugPrint('R01-D après écriture post-reset : cles=$cles');

    expect(store.contient(kCleCache), isTrue,
        reason: 'FAIT DOCUMENTÉ : une écriture née APRÈS le reset écrit '
            'légitimement. Ce comportement est SAIN et ne doit PAS être '
            'interdit par un futur correctif — la barrière doit couvrir la '
            'fenêtre du reset, pas geler le service indéfiniment');
    expect(cles.length, 2, reason: 'FAIT : deux clés écrites');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  E — ÉCRITURE DÉCLENCHÉE PENDANT L'EFFACEMENT
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-E — écriture déclenchée PENDANT l\'effacement', () async {
    const kCleTardive = 'alert_config_v2';
    store.semer(kCleTardive, 'sentinelle');
    store.armerSuspensionRemove(kCleTardive);

    final reset = BackupService.instance.reinitialiserComplet();

    final suspendu = await _attendreQue(() =>
        store.journal.contains('REM flutter.$kCleTardive'));
    expect(suspendu, isTrue,
        reason: 'GARDE DE PRÉCONDITION : la boucle de suppression est retenue '
            'sur la clé tardive — le reset est EN COURS');

    // Écriture du cache pendant l'effacement.
    await _ecrireCacheCommeLaProduction(_reunions('ENGHIEN'), _dateDuJour());
    await _laisserProgresser(4);

    debugPrint('R01-E pendant : cles=${store.clesCacheReunions()}');

    store.libererRemove();
    await reset;
    await _laisserProgresser();

    final cles = store.clesCacheReunions();
    debugPrint('R01-E après : cles=$cles');

    // ── CORRECTION R-DR-01-a (appliquée) ─────────────────────────────────
    //
    //  AVANT R01-a : l'écriture née pendant l'effacement n'était vue par
    //  aucune liste fixe → les deux clés subsistaient (`avant=[cache,_ts]`
    //  mesuré, `apres=[cache,_ts]`).
    //
    //  APRÈS R01-a : le balayage lit les clés RÉELLEMENT présentes, donc il
    //  voit celle écrite pendant la boucle fixe et la supprime. Mesure :
    //  `pendant=[cache,_ts]` puis `apres=[]`.
    //
    //  ⚠️ PORTÉE : cela ne prouve RIEN sur R01-c. Ici l'écriture est
    //  TERMINÉE avant que le balayage ne lise le stockage. Une écriture
    //  encore EN VOL au moment du balayage reste non couverte — c'est
    //  exactement ce que continuent de démontrer R01-J (v31b) et R01-K.
    expect(store.contient(kCleCache), isFalse,
        reason: 'CORRECTION R-DR-01-a : une écriture TERMINÉE pendant '
            'l\'effacement est désormais vue et supprimée par le balayage '
            'dynamique, qui lit les clés réellement présentes');
    expect(cles, isEmpty,
        reason: 'CORRECTION R-DR-01-a : plus aucune clé de cache après le reset');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  F — RECHARGEMENT DES RÉUNIONS APRÈS RESET
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-F — plus de réinjection : le cache est vide après le reset',
      () async {
    store.semer(kCleCache, _jsonDes(_reunions('PARIS-LONGCHAMP')));
    store.semer(kCleTs, DateTime.now().millisecondsSinceEpoch);

    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    // `init()` appelle `_chargerCacheLocal()` puis démarre le timer.
    await DataRefreshService.init();
    await _laisserProgresser();

    final reunions = DataRefreshService.instance.reunions;
    debugPrint('R01-F : reunions rechargees=${reunions.length} '
        'lieu=${reunions.isNotEmpty ? reunions.first.lieu : "-"}');

    // ── CORRECTION R-DR-01-a (appliquée) ─────────────────────────────────
    //
    //  AVANT R01-a : `_chargerCacheLocal()` (l.290) relisait la clé que le
    //  reset n'avait pas supprimée et repeuplait `_reunions` avec les données
    //  ANTÉRIEURES au reset (mesuré : `reunions rechargees=1
    //  lieu=PARIS-LONGCHAMP`).
    //
    //  APRÈS R01-a : la clé n'existe plus, `_chargerCacheLocal()` sort sur
    //  `if (jsonStr == null || jsonStr.isEmpty) return;` (l.296) et
    //  `_reunions` n'est pas repeuplé DEPUIS LE DISQUE.
    //
    //  ⚠️ PORTÉE STRICTE : ce test ne dit rien du cache RAM déjà en mémoire
    //  (`_reunions` non vidé = R01-b, mesuré par R01-H) ni du cache statique
    //  de `ZoneTurfService` (R01-d, mesuré par R01-N). Il ne mesure que le
    //  chemin DISQUE → RAM au démarrage.
    expect(reunions, isEmpty,
        reason: 'CORRECTION R-DR-01-a : plus aucune donnée antérieure au reset '
            'n\'est réinjectée depuis le disque au démarrage');
    expect(store.clesCacheReunions(), isEmpty,
        reason: 'CORRECTION R-DR-01-a : le disque ne contient plus de cache');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  H — CACHE RAM : les réunions sont VIDÉES du reset
  //
  //  ÉTAT AVANT R-DR-01-b : ce test affirmait le DÉFAUT — `_reunions`
  //  survivait au reset (`lieu=RAM-SURVIT`) parce que
  //  `BackupService.reinitialiserComplet()` ne mentionnait jamais
  //  `DataRefreshService`. R-DR-01-b a corrigé ce défaut : l'assertion est
  //  donc INVERSÉE, pas supprimée — elle mesure désormais la correction.
  //
  //  Elle n'est PAS affaiblie : le témoin de préparation (RAM peuplée avec
  //  `RAM-SURVIT`), la vérification du CONTENU disparu et la vérification
  //  finale de non-régression de R01-G restent en place.
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-H — la RAM `_reunions` est vidée par le reset', () async {
    store.semer(kCleCache, _jsonDes(_reunions('RAM-SURVIT')));
    store.semer(kCleTs, DateTime.now().millisecondsSinceEpoch);

    // Peuplement de la RAM par le chemin NORMAL (cache local au démarrage).
    await DataRefreshService.init();
    await _laisserProgresser();

    final ramAvant = DataRefreshService.instance.reunions;
    debugPrint('R01-H avant reset : RAM=${ramAvant.length} '
        'lieu=${ramAvant.isNotEmpty ? ramAvant.first.lieu : "-"}');
    expect(ramAvant.length, 1,
        reason: 'TÉMOIN DE PRÉPARATION : la RAM est peuplée AVANT le reset');
    expect(ramAvant.first.lieu, 'RAM-SURVIT',
        reason: 'TÉMOIN DE PRÉPARATION : la donnée présente est bien celle du '
            'cache local, et elle porte le marqueur « RAM-SURVIT »');

    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    final ramApres = DataRefreshService.instance.reunions;
    debugPrint('R01-H après reset : RAM=${ramApres.length} '
        'lieu=${ramApres.isNotEmpty ? ramApres.first.lieu : "-"}');

    expect(ramApres, isEmpty,
        reason: 'CORRECTION R-DR-01-b : `reinitialiserComplet()` vide désormais '
            '`DataRefreshService._reunions` via '
            '`viderMemoirePourResetComplet()`, comme les 5 autres services '
            'B5/B5c. Avant la correction, la réunion d\'avant le reset restait '
            'servie à l\'UI (`home_screen.dart:46`)');
    expect(ramApres.any((r) => r.lieu == 'RAM-SURVIT'), isFalse,
        reason: 'CORRECTION R-DR-01-b : la donnée antérieure au reset n\'est '
            'plus servie, sous aucune forme');
    expect(DataRefreshService.instance.lastRefresh, isNull,
        reason: 'CORRECTION R-DR-01-b : `_lastRefresh` est également remis à '
            'null — `lastRefreshLabel` ne peut plus afficher un état aboli');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G — NOUVELLE RÉCUPÉRATION LÉGITIME APRÈS RESET (non-régression)
  // ═══════════════════════════════════════════════════════════════════════
  test('R01-G — après reset, le service reste opérationnel (non-régression)',
      () async {
    // Aucun cache.
    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser(4);

    // `refresh()` en environnement de test : HttpClient renvoie 400 →
    // `chargerProgramme()` renvoie [] → réponse vide, sans exception.
    await DataRefreshService.instance.refresh();
    await _laisserProgresser(4);
    final svc = DataRefreshService.instance;
    debugPrint('R01-G : reunions=${svc.reunions.length} '
        'loading=${svc.loading} erreur=${svc.lastError}');

    expect(svc.loading, isFalse,
        reason: 'NON-RÉGRESSION : le service ne reste pas bloqué en chargement');

    // ── NOTE D'ORDRE — LEVÉE PAR R-DR-01-b ────────────────────────────────
    //  Avant R01-b, on n'assertait PAS `reunions.isEmpty` ici : `_reunions`
    //  survivait au reset ET d'un test à l'autre, donc une assertion « vide »
    //  aurait mesuré l'ordre d'exécution, pas `refresh()`.
    //  Depuis R01-b, `reinitialiserComplet()` — appelé à la ligne 509 de CE
    //  test — vide `_reunions` de façon inconditionnelle. L'assertion est donc
    //  désormais STABLE et significative : elle ne dépend plus de l'ordre.
    expect(svc.reunions, isEmpty,
        reason: 'CORRECTION R-DR-01-b : le reset en tête de ce test vide la '
            'RAM ; un `refresh()` dont l\'API est injoignable ne fabrique '
            'AUCUNE réunion. La RAM reste donc vide — le service ne réinvente '
            'rien à partir de rien');
    expect(svc.lastError, isNull,
        reason: 'NON-RÉGRESSION : `refresh()` se termine sans erreur remontée'
            ' (API injoignable → liste vide, pas d\'exception)');

    // Un cache légitime peut ensuite être écrit normalement.
    await _ecrireCacheCommeLaProduction(_reunions('VIRE'), _dateDuJour());
    await _laisserProgresser();

    expect(store.contient(kCleCache), isTrue,
        reason: 'NON-RÉGRESSION : après le reset, une écriture légitime '
            'fonctionne — un futur correctif ne doit pas geler le cache');
    debugPrint('R01-G après écriture : cles=${store.clesCacheReunions()}');
  });
}
