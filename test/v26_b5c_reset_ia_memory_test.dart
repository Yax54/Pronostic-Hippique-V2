// ═══════════════════════════════════════════════════════════════════════════
//  B5c — P3 : tests ciblés du reset complet de IaMemoryService
//
//  V26-1 : aucune ancienne donnée IA ne reste en RAM après un reset réussi,
//          et les 11 clés IA du disque sont effacées — l'archive E3/E4 survit.
//  V26-2 : poids, seuils et registre de calibration reviennent aux valeurs
//          d'usine.
//  V26-3 : le garde `_load()` interdit TOUT accès disque pendant le reset.
//
//  Chaque test porte un TÉMOIN de non-vacuité : l'assertion doit être
//  démontrablement fausse sur un chemin sans reset, ou sur un chemin où le
//  garde est retiré.
//
//  ⚠️ Ces tests prouvent des observations ciblées, PAS le bon fonctionnement
//     global de l'application.
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
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Store en mémoire : compte les appels `getAll` (= un accès disque réel)
//  pour que la sonde du garde `_load()` soit mesurable.
// ───────────────────────────────────────────────────────────────────────────
class StoreEspion extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];
  int getAllAppels = 0;

  // ── Politique de panne (C2) ──────────────────────────────────────────────
  /// Clés dont l'écriture/suppression doit ÉCHOUER.
  final Set<String> clesEnPanne = <String>{};

  /// `true`  → panne par EXCEPTION (canal rompu)
  /// `false` → panne par retour `false` (échec silencieux du store)
  bool panneParException = true;

  /// Journal des pannes réellement déclenchées (pour vérifier la non-vacuité).
  final List<String> pannes = <String>[];

  bool _doitEchouer(String cle) {
    // Le store reçoit les clés PRÉFIXÉES ('flutter.xxx').
    final nue = cle.startsWith('flutter.') ? cle.substring(8) : cle;
    return clesEnPanne.contains(cle) || clesEnPanne.contains(nue);
  }

  void _declencherPanne(String op, String cle) {
    pannes.add('$op $cle');
    if (panneParException) {
      throw StateError('PANNE SIMULÉE ($op) sur $cle');
    }
  }

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
    getAllAppels++;
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    if (_doitEchouer(key)) {
      _declencherPanne('REM', key);
      return false; // panne « silencieuse »
    }
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET $key');
    if (_doitEchouer(key)) {
      _declencherPanne('SET', key);
      return false; // panne « silencieuse »
    }
    _valeurs[key] = value;
    return true;
  }

  // ── Helpers de test (préfixe « flutter. » comme le vrai store) ───────────
  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;

  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');

  List<String> get clesArchive => _valeurs.keys
      .where((k) => k.startsWith('flutter.ia_archive_v1_'))
      .toList()
    ..sort();
}

late StoreEspion store;

void installerStore() {
  store = StoreEspion();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

// ───────────────────────────────────────────────────────────────────────────
//  ★ A-3 — Date de référence CALCULÉE au moment du test, jamais figée.
//
//  Jusqu'à A-3, `enregistrerPronostic()` datait le pronostic de
//  `DateTime.now()` : une date de fixture figée (2026-01-05) ne pouvait donc
//  jamais devenir « ancienne ». Depuis A-3, la date vient de la COURSE
//  (`courseKey` / `dateStr`). Une date figée finirait par dépasser
//  `_maxPronosticsAge` (90 jours) et `_purgerVieuxPronostics()` supprimerait
//  le pronostic NON RÉSOLU de `amorcer()` : les témoins de non-vacuité
//  tomberaient, alors que le reset qu'ils éprouvent est intact.
//
//  La date est donc calculée à chaque exécution. `courseKey` (format ISO) et
//  `course.dateStr` (format ddMMyyyy) désignent le MÊME jour : ils concordent,
//  ce qui est la condition d'acceptation posée par A-3.
// ───────────────────────────────────────────────────────────────────────────
DateTime get dateRefA3 {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Date de référence au format `ddMMyyyy` (celui de `ZtCourse.dateStr`).
String get dateRefDdMmYyyy =>
    '${dateRefA3.day.toString().padLeft(2, '0')}'
    '${dateRefA3.month.toString().padLeft(2, '0')}'
    '${dateRefA3.year}';

/// Date de référence au format ISO `YYYY-MM-DD` (celui des `courseKey` de ce
/// fichier, et celui que `dateDepuisCourseKey()` sait relire).
String get dateRefIso =>
    '${dateRefA3.year.toString().padLeft(4, '0')}-'
    '${dateRefA3.month.toString().padLeft(2, '0')}-'
    '${dateRefA3.day.toString().padLeft(2, '0')}';

ZtCourse courseTest(int numCourse, String nom) => ZtCourse(
      numCourse: numCourse,
      anchor: 'c$numCourse',
      nom: nom,
      dateStr: dateRefDdMmYyyy, // ★ A-3 : date réelle, concordante avec la clé
      heure: '14:00',
      distance: '2700',
      prix: '50000',
      type: 'Attelé',
      piste: 'Grande piste',
      categorie: 'Course D',
      isQuinte: false,
      pronosticZt: const <int>[],
      partants: <ZtPartant>[],
    );

/// Alimente la mémoire IA par des voies PUBLIQUES uniquement.
/// Chaque appel écrit réellement sur le disque (via `_save()` ou une unité
/// protégée P2), ce qui rend les assertions « clé effacée » non vacues.
Future<void> amorcer(IaMemoryService mem) async {
  await mem.enregistrerPronostic(
    courseKey: 'R1C1_$dateRefIso', // ★ A-3 : date réelle du jour
    course: courseTest(1, 'Prix Amorçage'),
    partantsClasses: const <ZtPartant>[],
    confiancePredite: 72.0,
  );
  await mem.enregistrerParisPremiumDuJour(<String>['R1C1_$dateRefIso']);
  await mem.enregistrerPronosticsPremiumDuJour(<PremiumPronosticDuJour>[
    PremiumPronosticDuJour(
      courseKey: 'R1C1_$dateRefIso', // ★ A-3 : date réelle du jour
      typePari: 'Quinté+',
      numeros: <String>['1', '2', '3', '4', '5'],
      sourceWidget: 'conseilJour',
    ),
  ]);
  await mem.sauvegarderSelectionWidgetPremiumDuJour(
    SelectionWidgetPremiumDuJour(
      dateKey: dateRefIso, // ★ A-3 : date réelle du jour
      sourceWidget: 'conseilJour',
      courseKey: 'R1C1_$dateRefIso',
      typePari: 'Quinté+',
      numeros: const <String>['1', '2', '3', '4', '5'],
      createdAt: dateRefA3,
    ),
  );
  // Alimente `_journal` par une voie PUBLIQUE. Le gradient n'est PAS lancé :
  // `annulerJourneeAtypique` ne l'appelle que s'il existe des pronostics
  // RÉSOLUS pour la date, et `enregistrerPronostic` n'a créé aucun résultat.
  // Aucun mécanisme d'apprentissage n'est donc sollicité ici.
  await mem.annulerJourneeAtypique(dateRefA3);
}

const List<String> kClesIASurDisque = <String>[
  'ia_pronostics_v2',
  'ia_pronostics_v2_gz',
  'ia_poids_v3',
  'ia_journal_v2',
  'ia_seuils_v1',
  'ia_stats_types_v1',
  'ia_stats_labels_v1',
  'ia_precision_v2',
  'ia_premium_du_jour_v1',
  'ia_premium_historique_v1',
  'premium_widgets_selection_jour_v1',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installerStore);

  // ══════════════════════════════════════════════════════════════════════════
  //  V26-1 — le reset complet vide la RAM et efface les clés IA
  // ══════════════════════════════════════════════════════════════════════════
  test('V26-1 — le reset complet vide la RAM et efface les clés IA', () async {
    // Archive E3/E4 semée AVANT le reset : elle doit survivre intacte.
    store
      ..semer('ia_archive_v1_manifest', '{"mois":["2026-01"]}')
      ..semer('ia_archive_v1_2026-01', '[]');

    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    await amorcer(mem);

    // `ia_pronostics_v2_gz` n'est écrite que si > 20 pronostics (compression).
    // On la sème APRÈS l'amorçage pour que l'assertion d'effacement couvre
    // aussi la branche compressée, sans fausser le chargement.
    store.semer('ia_pronostics_v2_gz', 'FAUX_BLOB_GZ');

    // ── TÉMOIN 1a : RAM peuplée avant le reset ────────────────────────────
    debugPrint('V26-1 témoin RAM pronostics=${mem.pronostics.length} '
        'journal=${mem.journal.length}');
    expect(mem.pronostics, isNotEmpty,
        reason: 'TÉMOIN : sans données initiales, le test ne prouverait rien');
    expect(mem.journal, isNotEmpty, reason: 'TÉMOIN : journal alimenté');

    // ── TÉMOIN 1b : les clés IA existent bien sur le disque AVANT ─────────
    //    `get()` (non typé) et non `getString()` : certaines clés portent des
    //    `List<String>`, sur lesquelles `getString` lèverait un TypeError.
    final presentesAvant =
        kClesIASurDisque.where((k) => store.contient(k)).toList();
    debugPrint('V26-1 témoin clés présentes avant reset : $presentesAvant');
    expect(presentesAvant, isNotEmpty,
        reason: 'TÉMOIN : aucune clé à effacer → assertion finale vide de sens');
    expect(presentesAvant, hasLength(kClesIASurDisque.length),
        reason: 'TÉMOIN : les 11 clés IA doivent exister avant le reset');
    expect(store.clesArchive, hasLength(2),
        reason: 'TÉMOIN : archive semée sur le disque');

    await BackupService.instance.reinitialiserComplet();

    // ── ASSERTIONS RAM ────────────────────────────────────────────────────
    debugPrint('V26-1 après RAM pronostics=${mem.pronostics.length} '
        'journal=${mem.journal.length} '
        'rapports=${mem.rapports.length} '
        'bilansSemaine=${mem.bilansSemaine.length} '
        'ecrituresEnCours=${mem.nbEcrituresEnCours}');
    expect(mem.pronostics, isEmpty, reason: '_pronostics vidé');
    expect(mem.journal, isEmpty, reason: '_journal vidé');
    expect(mem.rapports, isEmpty, reason: '_rapports vidé');
    expect(mem.bilansSemaine, isEmpty, reason: '_bilansSemaine vidé');
    expect(mem.nbEcrituresEnCours, 0, reason: 'aucun Future orphelin');
    expect(mem.nbEcrituresRefuseesParReset, 0,
        reason: 'le reset lui-même n\'effectue aucune écriture protégée');

    // ── ASSERTIONS DISQUE : aucune clé IA ne survit ───────────────────────
    //    Lecture via le store (non typée) : `prefs.getString` lèverait un
    //    TypeError sur les clés qui portent des `List<String>`.
    final survivantes =
        kClesIASurDisque.where((k) => store.contient(k)).toList();
    debugPrint('V26-1 clés IA survivantes après reset : $survivantes');
    expect(survivantes, isEmpty,
        reason: 'aucune des 11 clés IA ne doit survivre au reset complet');

    // ── ASSERTION E3/E4 : l'archive n'est pas touchée ─────────────────────
    debugPrint('V26-1 archive après reset : ${store.clesArchive}');
    expect(store.clesArchive, hasLength(2),
        reason: 'les clés ia_archive_v1_* ne font pas partie des 107 clés');
    expect(store.contient('ia_archive_v1_2026-01'), isTrue,
        reason: 'shard mensuel d\'archive préservé');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  V26-2 — poids, seuils et registre reviennent aux valeurs d'usine
  // ══════════════════════════════════════════════════════════════════════════
  test('V26-2 — poids, seuils et calibration reviennent aux valeurs d\'usine',
      () async {
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    await amorcer(mem);

    // Altération par le getter exposé : c'est l'état observable en production.
    mem.poids.forme = 0.99;
    mem.poids.cote = 0.77;
    mem.poids.calibrationScore = 88.0;
    IaCalibrationRegistry.update(88.0);

    // ── TÉMOIN 2 : avant reset, les valeurs sont ALTÉRÉES ─────────────────
    debugPrint('V26-2 témoin forme=${mem.poids.forme} '
        'cote=${mem.poids.cote} '
        'seuilSG=${mem.seuilsConfiance.seuilSimpleGagnant} '
        'calibration=${IaCalibrationRegistry.value}');
    final attendu = IaPoidsAdaptatifs.defaut();
    expect(mem.poids.forme, isNot(attendu.forme),
        reason: 'TÉMOIN : la valeur altérée diffère de la valeur d\'usine');
    expect(IaCalibrationRegistry.value, 88.0,
        reason: 'TÉMOIN : registre altéré');

    // ⚠️ On altère aussi les seuils, sinon l'assertion serait vraie même
    //    sans reset (les seuils n'ont pas bougé depuis le chargement).
    mem.seuilsConfiance.seuilSimpleGagnant = 12.0;
    mem.seuilsConfiance.seuilQuinte = 99.0;

    await BackupService.instance.reinitialiserComplet();

    // ── ASSERTIONS ────────────────────────────────────────────────────────
    final seuilsAttendus = SeuilsConfianceAdaptatifs();
    debugPrint('V26-2 après forme=${mem.poids.forme} '
        'cote=${mem.poids.cote} '
        'calibrationScore=${mem.poids.calibrationScore} '
        'seuilSG=${mem.seuilsConfiance.seuilSimpleGagnant} '
        'registre=${IaCalibrationRegistry.value}');

    expect(mem.poids.toJson(), attendu.toJson(),
        reason: 'TOUS les poids remis aux valeurs d\'usine');
    expect(mem.seuilsConfiance.toJson(), seuilsAttendus.toJson(),
        reason: 'seuils remis aux constantes de classe');
    expect(IaCalibrationRegistry.value, 50.0,
        reason: 'registre resynchronisé sur le poids d\'usine (50.0)');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  V26-3 — le garde `_load()` interdit tout accès disque pendant le reset
  //
  //  Le garde n'agit QUE lorsque `_loaded == false` et `_loadCompleter == null`
  //  (sinon `_load()` sort par ses deux autres sorties, garde ou pas). La
  //  sonde force donc cet état avec `recharger()`, qui est le SEUL chemin
  //  public capable de le produire (`_loaded = false` + `_loadCompleter = null`
  //  + RAM vidée + poids d'usine, puis `_load()`).
  //
  //  Deux observables, tous deux PUBLICS :
  //    • `store.getAllAppels`  → un `getAll` = un accès disque réel ;
  //    • `mem.seuilsConfiance` → `_load()` écrase les seuils avec le contenu
  //      du disque ; une valeur piégée semée sur le disque prouve que le
  //      chargement a eu lieu.
  //
  //  A/B sans mutation du code : le MÊME appel `recharger()`, une fois hors
  //  reset (témoin) et une fois pendant le reset (sonde).
  // ══════════════════════════════════════════════════════════════════════════
  test('V26-3 — le garde _load() interdit tout accès disque pendant le reset',
      () async {
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;

    // Seuils piégés sur le disque : valeur qu'AUCUN chemin d'usine ne produit.
    final pieges = SeuilsConfianceAdaptatifs()
      ..seuilSimpleGagnant = 12.0
      ..seuilQuinte = 99.0;
    store.semer('ia_seuils_v1', jsonEncode(pieges.toJson()));

    // ── TÉMOIN 3 : HORS reset, `recharger()` va bien jusqu'au disque ──────
    SharedPreferences.resetStatic();
    final baseTemoin = store.getAllAppels;
    await mem.recharger();
    final deltaTemoin = store.getAllAppels - baseTemoin;
    debugPrint('V26-3 TÉMOIN hors reset : delta getAll=$deltaTemoin '
        'seuilSG=${mem.seuilsConfiance.seuilSimpleGagnant}');
    expect(deltaTemoin, 1,
        reason: 'TÉMOIN : recharger() hors reset lit bien le disque');
    expect(mem.seuilsConfiance.seuilSimpleGagnant, 12.0,
        reason: 'TÉMOIN : hors reset, les seuils piégés sont chargés — '
            'donc l\'observable métier est fiable');

    // ── SONDE PENDANT LE RESET ────────────────────────────────────────────
    //    `executerResetComplet` a déjà vidé la RAM et remis les seuils
    //    d'usine (étape 5) puis posé `_loaded = true` (étape 7) quand le
    //    callback démarre. `recharger()` force `_loaded = false` : c'est
    //    exactement la fenêtre où le garde doit agir.
    int? deltaDansReset;
    double? seuilPendantReset;
    await mem.executerResetComplet(() async {
      // Uniquement dans le test : force une nouvelle instance prefs pour
      // rendre observable tout accès disque. En production, personne
      // n'appelle `resetStatic()` ici.
      SharedPreferences.resetStatic();
      final avant = store.getAllAppels;
      await mem.recharger(); // ← chemin métier de (re)chargement
      deltaDansReset = store.getAllAppels - avant;
      seuilPendantReset = mem.seuilsConfiance.seuilSimpleGagnant;
      store.journal.add('EFFACEMENT');
    });

    debugPrint('V26-3 getAll pendant le reset = $deltaDansReset (attendu 0) '
        'seuilSG pendant reset = $seuilPendantReset (attendu 80.0)');
    expect(deltaDansReset, 0,
        reason: 'le garde _load() doit sortir SANS toucher au disque : sinon '
            'un chargement repeuplerait la RAM pendant l\'effacement');
    expect(seuilPendantReset, 80.0,
        reason: 'aucune donnée périmée du disque ne doit être réinjectée '
            'dans un état métier pendant le reset');
    expect(store.journal, contains('EFFACEMENT'),
        reason: 'le callback d\'effacement a bien été exécuté');

    // ── État final cohérent ───────────────────────────────────────────────
    debugPrint('V26-3 après : poids.forme=${mem.poids.forme} '
        'registre=${IaCalibrationRegistry.value} '
        'pronostics=${mem.pronostics.length} '
        'ecrituresEnCours=${mem.nbEcrituresEnCours}');
    expect(mem.poids.forme, IaPoidsAdaptatifs.defaut().forme,
        reason: 'RAM aux valeurs d\'usine');
    expect(IaCalibrationRegistry.value, 50.0, reason: 'registre resynchronisé');
    expect(mem.nbEcrituresEnCours, 0, reason: 'aucun Future orphelin');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B5c-C2 — restored propagation of REAL exceptions
  //
  //  Avant P2, les 7 sites ci-dessous laissaient remonter l'exception d'un
  //  `prefs.setString/setBool/remove` en échec. P2 l'avait avalée partout.
  //  C2 la rétablit, tout en gardant la distinction stricte :
  //    • REFUS pendant un reset  → refuseeParReset, JAMAIS d'exception ;
  //    • ERREUR disque réelle    → exception (sur les 7 sites) ;
  //    • `_save()`               → absorbe et journalise, comme historiquement.
  //
  //  Chaque test porte un TÉMOIN : la panne est déclenchée (store.pannes non
  //  vide) ET le chemin nominal réussit quand la panne est retirée.
  // ══════════════════════════════════════════════════════════════════════════

  group('V26-C2 — propagation des erreurs réelles', () {
    test('V26-4 — les 4 méthodes premium sans catch laissent remonter',
        () async {
      await IaMemoryService.init();
      final mem = IaMemoryService.instance;
      await amorcer(mem);

      // ── 1. enregistrerParisPremiumDuJour (setString) ────────────────────
      store.clesEnPanne.add(_kPremiumDuJour);
      var panneTemoin = store.pannes.length;
      await expectLater(
        mem.enregistrerParisPremiumDuJour(<String>['R9C9_2026-01-05']),
        throwsA(isA<StateError>()),
        reason: 'avant P2, setString en échec remontait à l\'appelant',
      );
      expect(store.pannes.length, greaterThan(panneTemoin),
          reason: 'TÉMOIN : la panne a bien été déclenchée');
      store.clesEnPanne.clear();

      // ── 2. _sauvegarderPremiumHistorique (via enregistrerPronostics...) ─
      store.clesEnPanne.add(_kPremiumHistorique);
      await expectLater(
        mem.enregistrerPronosticsPremiumDuJour(const <PremiumPronosticDuJour>[
          PremiumPronosticDuJour(
            courseKey: 'R9C9_2026-01-05',
            typePari: 'Tiercé',
            numeros: <String>['1', '2', '3'],
            sourceWidget: 'meilleurPari',
          ),
        ]),
        throwsA(isA<StateError>()),
        reason: 'avant P2, setString en échec remontait depuis '
            '_sauvegarderPremiumHistorique',
      );
      store.clesEnPanne.clear();

      // ── 3. resetPremiumPourDate ─────────────────────────────────────────
      //   ⚠️ CORRECTION D'AUDIT : le `setString` de l'historique est DANS un
      //   `try { … } catch (_)` LOCAL (parsing JSON), y compris avant P2 : il
      //   n'a JAMAIS propagé. Seul le `remove(_premiumDuJourKey)` de l'étape 2
      //   — non entouré — propageait. On cible donc ce `remove`, avec la date
      //   du jour pour que la branche soit atteinte.
      store.clesEnPanne.add(_kPremiumDuJour);
      final aujourdhui = DateTime.now();
      await expectLater(
        mem.resetPremiumPourDate(aujourdhui),
        throwsA(isA<StateError>()),
        reason: 'avant P2, le remove(_premiumDuJourKey) de l\'étape 2 '
            'remontait à l\'appelant (le setString de l\'historique, lui, '
            'était déjà avalé par le catch local)',
      );
      store.clesEnPanne.clear();

      // ── 4. resetToutesEtoilesPremium (remove ×2) ────────────────────────
      store.clesEnPanne.add(_kPremiumHistorique);
      await expectLater(
        mem.resetToutesEtoilesPremium(),
        throwsA(isA<StateError>()),
        reason: 'avant P2, remove en échec remontait à l\'appelant',
      );
      store.clesEnPanne.clear();

      // ── TÉMOIN FINAL : sans panne, tout réussit ─────────────────────────
      await mem.resetToutesEtoilesPremium();
      debugPrint('V26-4 pannes déclenchées : ${store.pannes.length}');
      expect(store.pannes.length, greaterThanOrEqualTo(4),
          reason: 'TÉMOIN : 4 pannes distinctes ont été provoquées');
    });

    test('V26-5 — sauvegarderSelectionWidget conserve son catch ET son log',
        () async {
      await IaMemoryService.init();
      final mem = IaMemoryService.instance;
      final selection = SelectionWidgetPremiumDuJour(
        dateKey: dateRefIso, // ★ A-3 : date réelle du jour
        sourceWidget: 'meilleurPari',
        courseKey: 'R2C2_$dateRefIso',
        typePari: 'Tiercé',
        numeros: const <String>['4', '5', '6'],
        createdAt: dateRefA3.add(const Duration(hours: 10)),
      );

      // ── TÉMOIN « la méthode n'écrit pas quand rien ne change » écarté :
      //    la clé n'existe pas encore, donc setString sera bien appelé.
      store.clesEnPanne.add(_kPremiumWidgetsSelection);
      final pannesAvant = store.pannes.length;

      // Ne lève PAS : le `catch (e)` englobant historique avale.
      await mem.sauvegarderSelectionWidgetPremiumDuJour(selection);

      debugPrint('V26-5 pannes=${store.pannes.length} '
          '(avant=$pannesAvant) — la méthode a bien tenté l\'écriture');
      expect(store.pannes.length, greaterThan(pannesAvant),
          reason: 'TÉMOIN : setString a réellement été tenté et a échoué');
      expect(store.contient(_kPremiumWidgetsSelection), isFalse,
          reason: 'la panne a empêché l\'écriture sur le disque');

      // Contrôle : sans panne, la sélection est bien écrite. On vise une
      // AUTRE date, car « déjà figé » est idempotent et n'écrirait pas.
      // ★ A-3 : la date de `amorcer()` est celle d'AUJOURD'HUI ; il faut donc
      //   une date distincte. On prend DEMAIN — toujours différente de la date
      //   du jour, et jamais figée.
      final demainRef = dateRefA3.add(const Duration(days: 1));
      final demainIso = '${demainRef.year.toString().padLeft(4, '0')}-'
          '${demainRef.month.toString().padLeft(2, '0')}-'
          '${demainRef.day.toString().padLeft(2, '0')}';
      store.clesEnPanne.clear();
      await mem.sauvegarderSelectionWidgetPremiumDuJour(
        SelectionWidgetPremiumDuJour(
          dateKey: demainIso,
          sourceWidget: 'meilleurPari',
          courseKey: 'R3C3_$demainIso',
          typePari: 'Tiercé',
          numeros: const <String>['7', '8', '9'],
          createdAt: demainRef.add(const Duration(hours: 10)),
        ),
      );
      expect(store.contient(_kPremiumWidgetsSelection), isTrue,
          reason: 'chemin nominal restauré');
    });

    test('V26-6 — _load() signale la panne à l\'appelant suspendu', () async {
      await IaMemoryService.init();
      final mem = IaMemoryService.instance;

      // Semer un pronostic RÉSOLU : sans lui, la branche de migration n'est
      // jamais atteinte (`_pronostics.any((p) => p.resultatsReels)`).
      final date = DateTime(2026, 1, 5, 12);
      final pronosticResolu = IaPronostic(
        courseKey: 'R1C1_2026-01-05',
        nomCourse: 'Prix Test',
        hippodrome: 'Vincennes',
        discipline: 'Trot Attelé',
        datePronostic: date,
        scoresIA: const <String, double>{'1': 80.0, '2': 70.0, '3': 60.0},
        scoresCriteres: const <String, ScoresCriteres>{},
        resultatsReels: true,
        arriveeReelle: const <int>[1, 2, 3],
      );
      store.semer('ia_pronostics_v2', <String>[jsonEncode(pronosticResolu.toJson())]);
      // Flag de migration ABSENT → la branche s'exécute et tente setBool.
      store.clesEnPanne.add('ia_precision_migrated_v3');

      // ⚠️ `IaMemoryService` est un SINGLETON : `_loaded` vaut encore `true`
      //   depuis le test précédent, donc `init()` sortirait immédiatement.
      //   `recharger()` est le seul chemin public qui remet `_loaded = false`
      //   puis appelle `_load()` (il n'est pas modifié : simple appelant).
      //
      // ⚠️ CORRECTION D'AUDIT : `_load()` ne REJETTE jamais sa future — son
      //   catch terminal appelle `_loadCompleter?.completeError(e)` SANS
      //   `rethrow`, et le `Completer` n'a AUCUN auditeur sur un chargement
      //   unique. L'erreur est donc livrée à la ZONE en erreur asynchrone non
      //   gérée. C'est le comportement HISTORIQUE (pré-P2) que C2 restaure ;
      //   on l'observe donc via `runZonedGuarded`, qui est le seul canal réel.
      Object? erreurZone;
      final fini = Completer<void>();
      SharedPreferences.resetStatic();
      runZonedGuarded(() async {
        await mem.recharger(); // ne rejette pas : l'erreur part dans la zone
        if (!fini.isCompleted) fini.complete();
      }, (e, st) {
        erreurZone = e;
        if (!fini.isCompleted) fini.complete();
      });
      await fini.future;

      debugPrint('V26-6 pannes=${store.pannes} '
          'erreurZone=$erreurZone '
          'derniereErreur=${mem.derniereErreurEcriture}');

      expect(store.pannes.any((p) => p.contains('ia_precision_migrated_v3')),
          isTrue,
          reason: 'TÉMOIN : la panne a bien frappé le flag de migration, donc '
              'l\'exception a traversé `_ecrireProtege` jusqu\'au catch de '
              '`_load()` (avant P2 : identique ; en P2 : branche jamais atteinte)');
      expect(erreurZone, isA<StateError>(),
          reason: 'le catch de `_load()` a bien appelé `completeError` : '
              'l\'erreur réelle est signalée, pas convertie en refus');
      expect(mem.derniereErreurEcriture, isA<StateError>(),
          reason: 'l\'erreur réelle est mémorisée, pas convertie en refus');

      // Remise en état sain pour les tests suivants (singleton partagé).
      store.clesEnPanne.clear();
      SharedPreferences.resetStatic();
      await mem.recharger();
    });

    test('V26-7 — _save() absorbe et journalise, sans propager', () async {
      await IaMemoryService.init();
      final mem = IaMemoryService.instance;

      // `_save()` écrit _poidsKey ; on le met en panne.
      store.clesEnPanne.add('ia_poids_v3');
      final pannesAvant = store.pannes.length;

      // Ne doit PAS lever : comportement historique de _save().
      await mem.enregistrerPronostic(
        courseKey: 'R3C3_$dateRefIso', // ★ A-3 : date réelle du jour
        course: courseTest(3, 'Prix Sans Propagation'),
        partantsClasses: const <ZtPartant>[],
        confiancePredite: 55.0,
      );

      debugPrint('V26-7 pannes=${store.pannes.length} '
          '(avant=$pannesAvant) derniereErreur=${mem.derniereErreurEcriture}');
      expect(store.pannes.length, greaterThan(pannesAvant),
          reason: 'TÉMOIN : l\'écriture de ia_poids_v3 a bien échoué');
      // L'échec est MÉMORISÉ mais pas propagé.
      expect(mem.derniereErreurEcriture, isA<StateError>(),
          reason: '_save() doit absorber ET journaliser l\'erreur réelle');
      // Aucun future orphelin : le registre s\'est vidé.
      expect(mem.nbEcrituresEnCours, 0,
          reason: 'le rejet de la future n\'a pas fui hors du registre');
    });

    test('V26-8 — un REFUS pendant le reset ne lève jamais, même en panne',
        () async {
      await IaMemoryService.init();
      final mem = IaMemoryService.instance;
      await amorcer(mem);

      // Panne armée : si la barrière ne refusait pas AVANT d'écrire, le
      // setString lèverait et le test échouerait.
      store.clesEnPanne.add(_kPremiumDuJour);
      final pannesAvant = store.pannes.length;

      var refuseesAvant = mem.nbEcrituresRefuseesParReset;
      await mem.executerResetComplet(() async {
        // Pendant le reset, `_ecrireProtege` sort au contrôle 1 :
        // aucun accès disque, donc aucune panne ne peut être déclenchée.
        await mem.enregistrerParisPremiumDuJour(<String>['R8C8_2026-01-08']);
        await mem.resetToutesEtoilesPremium();
      });

      debugPrint('V26-8 refusees=${mem.nbEcrituresRefuseesParReset} '
          '(avant=$refuseesAvant) pannes=${store.pannes.length} '
          '(avant=$pannesAvant)');

      // ── ASSERTION DISCRIMINANTE : un refus n'est pas une erreur ─────────
      expect(mem.nbEcrituresRefuseesParReset, refuseesAvant + 2,
          reason: 'les 2 écritures doivent être REFUSÉES, pas rejetées');
      expect(store.pannes.length, pannesAvant,
          reason: 'un refus sort AVANT tout accès disque : aucune panne '
              'ne doit être déclenchée');

      store.clesEnPanne.clear();
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  C1 — ÉCHEC D'EFFACEMENT : CONTRÔLE, ÉTAT DE CHARGEMENT, CACHE
  //
  //  ⚠️ Un reset partiellement effectué n'est PAS une transaction annulée.
  //     Les tests ci-dessous ne prétendent jamais que les données résiduelles
  //     constituent une restauration de l'état initial : ils vérifient
  //     seulement ce qui est RÉELLEMENT encore récupérable, et que l'échec
  //     est visible (exception) au lieu d'être silencieusement ignoré.
  // ══════════════════════════════════════════════════════════════════════════
  group('C1 — échec de suppression SharedPreferences', () {
    /// Arme une panne par RETOUR `false` (échec silencieux du store).
    void panneSilencieuse(String cle) {
      store.clesEnPanne.add(cle);
      store.panneParException = false;
    }

    // ────────────────────────────────────────────────────────────────────────
    //  V26-9 — remove() retourne false, service DÉJÀ CHARGÉ avant le reset
    //
    //  Couvre les points 1, 3, 4, 7, 6 des tests obligatoires.
    //
    //  TÉMOIN de non-vacuité : le store enregistre explicitement la panne ET
    //  la clé visée survit sur le disque (vérifié par `store.contient`).
    //  Si C1-a était retiré (`if (!ok) echecs.add(key)` supprimé), la future
    //  se terminerait normalement : `reinitialiserComplet()` n'échouerait pas
    //  et l'assertion `throwsA` serait fausse.
    // ────────────────────────────────────────────────────────────────────────
    test('V26-9 — remove() == false : le reset ÉCHOUE et ne s\'annonce pas',
        () async {
      // Clé de production réelle (présente dans les 107), à ne PAS réécrire.
      const cible = 'ia_seuils_v1';

      // Donnée résiduelle : semée APRÈS l'amorçage (voir plus bas), car
      // `amorcer()` réécrit `ia_seuils_v1` via `_save()`.
      final residuel = SeuilsConfianceAdaptatifs()..seuilQuinte = 99.0;

      await IaMemoryService.init();
      final mem = IaMemoryService.instance;
      final alertes = AlertService.instance;
      await amorcer(mem);

      // ⚠️ `amorcer()` écrit via `_save()`, qui réécrit `ia_seuils_v1` avec les
      //    seuils COURANTS (d'usine). La donnée résiduelle doit donc être
      //    semée APRÈS l'amorçage, sinon elle est écrasée avant le reset.
      store.semer(cible, jsonEncode(residuel.toJson()));
      expect(store.contient(cible), isTrue,
          reason: 'TÉMOIN : la donnée résiduelle est bien présente avant le reset');

      // ── Point 3 : le service est DÉJÀ CHARGÉ avant le reset ──────────────
      //    Sans ce témoin, un `_loaded` resté `false` rendrait l'assertion 4
      //    vraie sans que la correction soit nécessaire.
      expect(mem.pronostics, isNotEmpty,
          reason: 'TÉMOIN : `_load()` a bien été exécuté, le service est '
              'chargé et peuplé avant le reset');

      // ── Panne armée sur UNE clé : `remove()` retourne false ──────────────
      panneSilencieuse(cible);

      // On capture l'instance SINGLETON de `SharedPreferences` AVANT le reset :
      // c'est cet objet qui verra son cache muté par les `remove()`.
      final prefsCache = await SharedPreferences.getInstance();
      expect(prefsCache.containsKey(cible), isTrue,
          reason: 'TÉMOIN : le cache contient la clé avant le reset');

      Object? erreur;
      StackTrace? pile;
      try {
        await BackupService.instance.reinitialiserComplet();
      } catch (e, st) {
        erreur = e;
        pile = st;
      } finally {
        store.clesEnPanne.clear();
      }

      debugPrint('V26-9 pannes=${store.pannes} erreur=$erreur '
          'contientCible=${store.contient(cible)}');

      // ── Point 1 : un `false` est un ÉCHEC, l'exception le dit ────────────
      expect(store.pannes, contains('REM flutter.$cible'),
          reason: 'TÉMOIN : le store a bien refusé CETTE suppression');
      expect(erreur, isA<StateError>(),
          reason: 'C1-a : un retour false doit lever, pas être ignoré');
      expect('$erreur', contains(cible),
          reason: 'le message doit nommer la clé survivante pour être '
              'exploitable (diagnostic complet, pas un simple « échec »)');
      expect(pile, isNotNull, reason: 'la pile d\'origine est conservée');

      // ── Le reset ne s'est PAS annoncé réussi ─────────────────────────────
      //    Aucune assertion directe sur le debugPrint (non observable), mais
      //    `notifyListeners()` est APRÈS le try/finally : en cas d'exception
      //    il n'est jamais atteint. Conséquence observable : la RAM reste
      //    dans son état d'échec, cohérente avec un disque partiellement vidé.
      expect(mem.poids.toJson(), IaPoidsAdaptatifs.defaut().toJson(),
          reason: 'les étapes RAM internes au reset ont bien eu lieu — '
              'l\'échec est disque, pas RAM');

      // ── Point 6 : données résiduelles RÉELLEMENT présentes ───────────────
      expect(store.contient(cible), isTrue,
          reason: 'la clé refusée SURVIT sur le disque : c\'est un reset '
              'partiel, pas une annulation');

      // ── C1-c : preuve DIRECTE que le cache a été resynchronisé ───────────
      //    `prefsCache` est l'INSTANCE SINGLETON de `SharedPreferences` :
      //    c'est exactement l'objet dont `remove()` a vidé `_preferenceCache`
      //    pendant le reset, et c'est celui que `_load()` réutilise via
      //    `getInstance()`. Aucun `resetStatic()` ici, donc aucune relecture
      //    fortuite du disque : on lit la mémoire vive de cet objet.
      //
      //    Contrat de `remove()` (shared_preferences_legacy.dart:173-177) :
      //    `_preferenceCache.remove(key)` AVANT `_store.remove(prefixedKey)`.
      //    Sur la clé refusée, le cache est donc vide alors que le disque la
      //    garde. Sans le `reload()` de C1-c, cette assertion serait fausse.
      debugPrint('V26-9 cache après échec : contientCible='
          '${prefsCache.containsKey(cible)}');
      expect(store.contient(cible), isTrue,
          reason: 'la clé refusée est bien présente sur le DISQUE');
      expect(prefsCache.containsKey(cible), isTrue,
          reason: 'C1-c : le cache doit avoir été resynchronisé sur le disque '
              'par `reload()` sur le chemin d\'échec. Sans lui, il mentirait '
              '(clé absente du cache alors qu\'elle existe sur le store)');

      // ── Point 4 : état de chargement après échec → tue M6 et M10 ─────────
      //    Sonde menée AVANT tout `recharger()` : celui-ci repose
      //    `_loaded = false` et masquerait une régression.
      //
      //    ⚠️ Sonde choisie avec précaution. Une première version utilisait
      //       `annulerJourneeAtypique()`, qui appelle `_load()` MAIS termine
      //       par `_save()` ; après `resetStatic()`, ce `_save()` fait un
      //       `getInstance()` qui déclenche lui-même un `getAll`. Le compteur
      //       bougeait donc MÊME avec `_loaded == true` : la sonde mesurait
      //       l'écriture, pas le chargement, et était VACUAIRE (elle passait
      //       sous M6 et sous M10).
      //
      //    `relancerRecuperationPMU()` appelle `_load()` puis, la mémoire
      //    venant d'être vidée par le reset, sort IMMÉDIATEMENT sur
      //    `if (aRelancer.isEmpty) return …` : aucun autre accès disque,
      //    aucune écriture. Le `getAll` mesuré ne peut donc venir que de
      //    `_load()`, c'est-à-dire de l'état de `_loaded`.
      //
      //    Avec C1-b : `_loaded == false` après l'échec ⇒ `_load()` lit le
      //    disque ⇒ delta == 1.
      //    Avec M6 (`_loaded = true` avant l'effacement) ou M10 (`false`
      //    retiré, donc `_loaded` encore `true` depuis `amorcer()`) :
      //    `_load()` sort immédiatement ⇒ delta == 0.
      SharedPreferences.resetStatic();
      final getAllAvantSonde = store.getAllAppels;
      final rapport = await mem.relancerRecuperationPMU();
      final deltaSonde = store.getAllAppels - getAllAvantSonde;
      debugPrint('V26-9 sonde _loaded : delta getAll=$deltaSonde '
          'rapport=${rapport['message']}');
      expect(rapport['total'], 0,
          reason: 'TÉMOIN : la sonde est bien sortie par la branche vide, '
              'donc aucun accès disque parasite (PMU) n\'a eu lieu');
      expect(deltaSonde, 1,
          reason: 'après un échec, `_loaded` doit être FAUX : `_load()` doit '
              'donc relire le disque, soit exactement 1 `getAll`. Avec M6 '
              '(_loaded = true avant l\'effacement) ou M10 (`_loaded = false` '
              'retiré), `_load()` sortirait immédiatement et delta vaudrait 0');

      // ── Point 6 : donnée résiduelle RÉELLEMENT récupérable ───────────────
      //    `recharger()` remet `_loaded = false` puis `_load()` relit le
      //    disque : la valeur piégée, qui a survécu sur le stockage, est
      //    retrouvée. Sans le `reload()` de C1-c, le cache désynchronisé
      //    aurait rendu `getString(...)` == null et le seuil serait resté à
      //    sa valeur d'usine (0.0).
      //
      //    ⚠️ Cela ne restaure PAS l'état initial : les 106 autres clés ont
      //       bien été supprimées, et seule cette clé refusée subsiste.
      await mem.recharger();
      debugPrint('V26-9 seuilQuinte après rechargement (via disque)='
          '${mem.seuilsConfiance.seuilQuinte}');
      expect(mem.seuilsConfiance.seuilQuinte, 99.0,
          reason: 'C1-c : la donnée résiduelle survit sur le disque ET '
              'redevient lisible par le chargement métier');

      // ── Point 7 : libération des barrières ──────────────────────────────
      expect(mem.nbEcrituresEnCours, 0,
          reason: 'le drain a vidé le registre : aucun Future orphelin');
      // La barrière IaMemory est libérée : une écriture doit pouvoir NAÎTRE.
      // Preuve : `nbEcrituresRefuseesParReset` ne bouge plus après un appel
      // d'écriture hors reset (sinon la barrière serait restée fermée).
      final refuseesAvant = mem.nbEcrituresRefuseesParReset;
      await mem.enregistrerParisPremiumDuJour(<String>['R9BIS_2026-01-09']);
      debugPrint('V26-9 refusees: avant=$refuseesAvant '
          'apres=${mem.nbEcrituresRefuseesParReset}');
      expect(mem.nbEcrituresRefuseesParReset, refuseesAvant,
          reason: 'C1-b : la barrière doit être libérée MÊME en échec, '
              'sinon le service resterait muet jusqu\'au redémarrage');

      // La barrière AlertService est libérée elle aussi : son vidage RAM a eu
      // lieu, et son registre d'écritures est vide.
      expect(alertes.nbEcrituresEnCours, 0,
          reason: 'barrière externe également drainée et libérée');
    });

    // ────────────────────────────────────────────────────────────────────────
    //  V26-10 — remove() lève une exception : l'exception réelle est préservée
    //
    //  Couvre le point 2. Différence essentielle avec V26-9 (échec silencieux) :
    //  ici le store n'a JAMAIS atteint le disque, donc la clé est intacte ET le
    //  cache de `SharedPreferences` n'a pas été vidé pour cette clé.
    // ────────────────────────────────────────────────────────────────────────
    test('V26-10 — remove() lève : l\'exception réelle est préservée', () async {
      const cible = 'ia_journal_v2';

      await IaMemoryService.init();
      final mem = IaMemoryService.instance;
      await amorcer(mem);
      final cleAvant = store.contient(cible);
      expect(cleAvant, isTrue, reason: 'TÉMOIN : la clé existe avant');

      // Panne par EXCEPTION (comportement par défaut du store espion).
      store.clesEnPanne.add(cible);
      Object? erreur;
      try {
        await BackupService.instance.reinitialiserComplet();
      } catch (e) {
        erreur = e;
      } finally {
        store.clesEnPanne.clear();
      }

      debugPrint('V26-10 pannes=${store.pannes} erreur=$erreur');

      expect(store.pannes, contains('REM flutter.$cible'),
          reason: 'TÉMOIN : la panne a bien frappé cette suppression');
      // L'exception INITIALE remonte telle quelle : ce n'est PAS la StateError
      // de C1-a (qui ne concerne que le retour false).
      expect(erreur, isA<StateError>());
      expect('$erreur', contains('PANNE SIMULÉE'),
          reason: 'l\'exception du store est préservée, pas remplacée par '
              'une erreur générique du reset');
      expect('$erreur', isNot(contains('Reset complet INCOMPLET')),
          reason: 'C1-c : un échec secondaire ne doit pas masquer l\'erreur '
              'initiale — et ici il n\'y a même pas de reload nécessaire');
      // Aucune donnée perdue pour cette clé : le store n\'a pas été atteint.
      expect(store.contient(cible), isTrue,
          reason: 'exception ⇒ aucune suppression effective sur le disque');

      // L'état RAM est quand même réinitialisé en interne (étapes 4-6).
      expect(mem.poids.toJson(), IaPoidsAdaptatifs.defaut().toJson(),
          reason: 'l\'échec est disque, pas RAM');
      // Barrières libérées.
      final refuseesAvant = mem.nbEcrituresRefuseesParReset;
      await mem.enregistrerParisPremiumDuJour(<String>['R10C10_2026-01-10']);
      expect(mem.nbEcrituresRefuseesParReset, refuseesAvant,
          reason: 'barrière libérée malgré l\'exception');
    });

    // ────────────────────────────────────────────────────────────────────────
    //  V26-11 — cache avant/après reload() : ce qui est réellement récupérable
    //
    //  Couvre les points 5 et 6. On documente le comportement SANS prétendre
    //  qu'il restaure quoi que ce soit.
    // ────────────────────────────────────────────────────────────────────────
    test('V26-11 — échec silencieux : cache désynchronisé puis resynchronisé',
        () async {
      const cible = 'ia_seuils_v1';

      // Donnée leurre : valeur qu'AUCUN chemin d'usine ne produit (0.0).
      final leurre = SeuilsConfianceAdaptatifs()..seuilQuinte = 99.0;

      await IaMemoryService.init();
      final mem = IaMemoryService.instance;
      await amorcer(mem);

      // ⚠️ Semé APRÈS l'amorçage : `amorcer()` écrit via `_save()`, qui
      //    réécrit `ia_seuils_v1` avec les seuils courants (d'usine).
      store.semer(cible, jsonEncode(leurre.toJson()));

      // Le cache singleton : c'est LUI que les `remove()` du reset vident.
      SharedPreferences.resetStatic();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(cible), isTrue,
          reason: 'TÉMOIN : le cache contient la clé avant l\'opération');
      expect(prefs.getString(cible), contains('99'),
          reason: 'TÉMOIN : la valeur lue est bien le leurre');

      // ── Panne sur `cible` : `remove()` rend false (échec SILENCIEUX) ────
      panneSilencieuse(cible);
      var leve = false;
      try {
        await BackupService.instance.reinitialiserComplet();
      } catch (_) {
        leve = true;
      }
      store.clesEnPanne.clear();

      debugPrint('V26-11 après reset en échec : leve=$leve '
          'cacheContient=${prefs.containsKey(cible)} '
          'disqueContient=${store.contient(cible)}');

      // ── Point 1 : l'échec est SIGNALÉ, pas silencieux ────────────────────
      expect(leve, isTrue,
          reason: 'C1-a : un retour false doit produire une exception visible');

      // ── Point 6 : la donnée résiduelle existe TOUJOURS sur le disque ─────
      expect(store.contient(cible), isTrue,
          reason: 'la clé refusée survit : reset partiel, pas annulation');

      // ── Point 5 : le cache a été RESYNCHRONISÉ par `reload()` ────────────
      //    Sans le `reload()` de C1-c, `prefs._preferenceCache` aurait perdu
      //    la clé au moment du `remove()` (contrat : cache d'abord, store
      //    ensuite) alors que le disque la garde : `containsKey` serait faux.
      expect(prefs.containsKey(cible), isTrue,
          reason: 'C1-c : `reload()` remet le cache en accord avec le '
              'stockage réellement restant. Il ne RESTAURE pas les 106 clés '
              'supprimées avec succès — il n\'efface pas non plus la perte');
      expect(prefs.getString(cible), contains('99'),
          reason: 'la valeur résiduelle est de nouveau lisible, pas seulement '
              'la présence de la clé');

      // ── Point 6bis : la valeur résiduelle est réellement EXPLOITABLE ─────
      //    Le chargement métier la retrouve ; sans `reload()`, le cache
      //    désynchronisé aurait rendu `null` et le seuil serait resté à 0.0.
      await mem.recharger();
      debugPrint('V26-11 seuilQuinte après rechargement='
          '${mem.seuilsConfiance.seuilQuinte}');
      expect(mem.seuilsConfiance.seuilQuinte, 99.0,
          reason: 'la donnée résiduelle partircipe bien au rechargement — '
              'sans prétendre restaurer l\'état initial');

      // ── Contraste : une clé supprimée AVEC SUCCÈS reste supprimée ────────
      //    C'est la démonstration que `reload()` ne « restaure » rien.
      const temoinEfface = 'ia_premium_historique_v1';
      debugPrint('V26-11 contraste $temoinEfface : '
          'disque=${store.contient(temoinEfface)} '
          'cache=${prefs.containsKey(temoinEfface)}');
      expect(store.contient(temoinEfface), isFalse,
          reason: 'la clé effacée avec succès ne réapparaît PAS sur le disque');
      expect(prefs.containsKey(temoinEfface), isFalse,
          reason: 'et le `reload()` ne la fait pas réapparaître dans le cache : '
              'il reflète le stockage, il ne le réécrit pas');
    });

    // ────────────────────────────────────────────────────────────────────────
    //  V26-12 — nouvelle tentative APRÈS un échec : elle réussit
    //
    //  Couvre le point 8 et démontre que l'échec ne laisse pas le service
    //  définitivement bloqué (pas de barrière collée, pas de `_loaded` figé).
    // ────────────────────────────────────────────────────────────────────────
    test('V26-12 — une nouvelle tentative après échec réussit et vide le disque',
        () async {
      const cible = 'ia_seuils_v1';
      store.semer(cible, jsonEncode({'seuilQuinte': 99.0}));

      await IaMemoryService.init();
      final mem = IaMemoryService.instance;
      await amorcer(mem);

      // ── 1er essai : ÉCHEC ────────────────────────────────────────────────
      panneSilencieuse(cible);
      var premierEchec = false;
      try {
        await BackupService.instance.reinitialiserComplet();
      } catch (_) {
        premierEchec = true;
      }
      store.clesEnPanne.clear();

      debugPrint('V26-12 échec1=$premierEchec contientAprèsÉchec=${store.contient(cible)}');
      expect(store.pannes.any((p) => p.contains(cible)), isTrue,
          reason: 'TÉMOIN : le premier essai a bien échoué sur cette clé');
      expect(premierEchec, isTrue, reason: 'TÉMOIN : un échec a bien eu lieu');
      expect(store.contient(cible), isTrue,
          reason: 'TÉMOIN : la donnée résiduelle est encore là');

      // ── 2e essai : SUCCÈS complet ────────────────────────────────────────
      final pannesAvant2 = store.pannes.length;
      await BackupService.instance.reinitialiserComplet();

      debugPrint('V26-12 pannes2=${store.pannes.length - pannesAvant2} '
          'contientAprèsSuccès=${store.contient(cible)}');
      expect(store.pannes.length, pannesAvant2,
          reason: 'aucune nouvelle panne : la seconde tentative ne rencontre '
              'plus la clé défaillante');
      expect(store.contient(cible), isFalse,
          reason: 'le second reset efface réellement la clé résiduelle');
      // Et l'état de chargement est de nouveau cohérent APRÈS succès :
      // le disque vidé ne doit plus rien rendre. On lit par le CACHE réel
      // (sans `resetStatic()`), donc sans possibilité de relecture fortuite.
      await mem.recharger();
      debugPrint('V26-12 après succès : pronostics=${mem.pronostics.length} '
          'seuilQuinte=${mem.seuilsConfiance.seuilQuinte}');
      expect(mem.pronostics, isEmpty,
          reason: 'après succès, plus aucun pronostic ne revient du disque');
      // Seuil laissé à sa valeur d'usine : la clé piégée a bien été effacée,
      // donc le rechargement ne la retrouve pas (contraste avec V26-9).
      expect(mem.seuilsConfiance.seuilQuinte,
          SeuilsConfianceAdaptatifs().seuilQuinte,
          reason: 'après succès, la donnée résiduelle de V26-9 n\'existe plus : '
              'c\'est bien la preuve que le second reset a réellement écrit');
    });
  });
}

// ── Clés de production utilisées par les tests C2 ───────────────────────────
const String _kPremiumDuJour = 'ia_premium_du_jour_v1';
const String _kPremiumHistorique = 'ia_premium_historique_v1';
const String _kPremiumWidgetsSelection = 'premium_widgets_selection_jour_v1';
