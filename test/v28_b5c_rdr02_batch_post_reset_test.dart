// ═══════════════════════════════════════════════════════════════════════════
//  B5c — ÉTAPE 7 / R-DR-02 : recréation de pronostics après un reset complet
//
//  OBJET DE CES TESTS : ÉTABLIR LES FAITS, PAS PROPOSER UN CORRECTIF.
//
//  Le point d'entrée observé est `IaMemoryService.enregistrerPronosticsBatch`.
//  C'est la fin EXACTE de `DataRefreshService._enregistrerPronosticsBatchIsolate`
//  (data_refresh_service.dart:738) et de son fallback (:814) : une fois
//  `compute()` rendu, tout le travail restant passe par cette méthode.
//
//  ⚠️ PORTÉE EXPLICITE : ces tests prouvent des observations ciblées sur
//     `enregistrerPronosticsBatch`. Ils ne prouvent PAS que
//     `DataRefreshService` atteint cet état en production — cela dépend du
//     calendrier réseau, de la durée réelle du calcul dans l'isolate et du
//     moment où l'utilisateur appuie sur « Réinitialiser ».
//
//  ★ ÉTAT DES TESTS DEPUIS R-DR-02 :
//     V28-B et V28-B-bis décrivaient le DÉFAUT (le lot recréait le pronostic
//     après le reset). Le correctif étant appliqué, ils décrivent désormais
//     la CORRECTION : le lot périmé est rejeté, et un lot frais reste accepté.
//     Le dispositif de mesure (journal du store, frontière de reset) est
//     inchangé : seule l'issue attendue est inversée.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Store instrumenté minimal : verrou par clé, journal, lecture directe.
// ───────────────────────────────────────────────────────────────────────────
class _StoreControle extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  Completer<void>? _verrouSet;
  String? _cleSuspendue;
  Completer<void>? _entreeSet;

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
    journal.add('SET-ENTREE $key');
    if (_cleSuspendue != null && key.contains(_cleSuspendue!)) {
      final verrou = _verrouSet;
      if (verrou != null) {
        final entree = _entreeSet;
        _entreeSet = null;
        if (entree != null && !entree.isCompleted) entree.complete();
        await verrou.future;
      }
    }
    _valeurs[key] = value;
    journal.add('SET-OK $key');
    return true;
  }

  Completer<void> armerSuspensionSet(String cle) {
    final entree = Completer<void>();
    _entreeSet = entree;
    _cleSuspendue = cle;
    _verrouSet = Completer<void>();
    return entree;
  }

  void libererSet() {
    final v = _verrouSet;
    _verrouSet = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void desarmer() {
    _cleSuspendue = null;
    _verrouSet = null;
    _entreeSet = null;
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');

  int get nbRem => journal.where((e) => e.startsWith('REM ')).length;
  int get nbSetOk => journal.where((e) => e.startsWith('SET-OK')).length;
}

// ignore: library_private_types_in_public_api
late _StoreControle store;

void _installerStore() {
  store = _StoreControle();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

/// Vidage BORNÉ de la boucle d'événements. Aucune assertion ne repose sur
/// une durée : les observables sont le journal et l'état du disque.
Future<void> _laisserProgresser([int tours = 16]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Attend un signal d'entrée OU la fin de l'opération : ne fige jamais.
Future<bool> _attendreEntreeOuFin(
    Completer<void> entree, Future<void> operation) async {
  var fini = false;
  final fin = Completer<void>();
  operation.whenComplete(() {
    fini = true;
    if (!fin.isCompleted) fin.complete();
  }).ignore();
  await Future.any<void>([entree.future, fin.future]);
  return !fini;
}

// ── Constructeurs ZT ───────────────────────────────────────────────────────

ZtPartant _partant(int num) => ZtPartant(
      numero: '$num',
      nom: 'CHEVAL_$num',
      driver: 'DRIVER_$num',
      entraineur: 'ENTR_$num',
      proprietaire: 'PROP_$num',
      gains: '${num * 10000}',
      record: '1\'1${num % 10}"0',
      musique: '1a2a3a4a5a',
      cote: '4.0',
      ageSexe: '${4 + num % 6} M',
      poids: 57.0 + num,
      placeDepartInt: num,
      joursRepos: 10 + num,
      hippodromeActuel: 'VINCENNES',
      statsJockeyCsv: 'JOCKEY_$num|15|40|12',
      statsHippodromeCsv: 'VINCENNES|20|45|15',
      statsEntraineurCsv: 'ENTR_$num|12|33|8',
      eloRating: 1500.0 + num * 10,
      eloNbCourses: 20,
      eloVariationMois: 5.0,
      statsTerrainCsv: 'bon|6|2|4',
      gainsDernierAn: num * 5000,
    );

/// Course du JOUR (dateStr = aujourd'hui) : c'est le cas normal d'un refresh,
/// et celui qui rend le pronostic visible dans l'application.
ZtCourse _courseDuJour({int numCourse = 1, int nbPartants = 8}) {
  final now = DateTime.now();
  final ds = '${now.day.toString().padLeft(2, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.year}';
  return ZtCourse(
    numCourse: numCourse,
    anchor: 'R1C$numCourse',
    nom: 'PRIX_RDR02_$numCourse',
    heure: '23:50',
    distance: '2700',
    prix: '50000',
    type: 'Trot Attelé',
    piste: 'Sable',
    categorie: 'Course D',
    isQuinte: true,
    pronosticZt: const <int>[1, 2, 3, 4, 5],
    partants: List.generate(nbPartants, (i) => _partant(i + 1)),
    dateStr: ds,
  );
}

/// Item de batch construit par le chemin RÉEL :
/// `IaPronosticEngine.analyserCourseAvecCriteres`.
Map<String, dynamic> _itemBatch(ZtCourse course, String courseKey) {
  final (partants, criteres) =
      IaPronosticEngine.analyserCourseAvecCriteres(course);
  return <String, dynamic>{
    'courseKey': courseKey,
    'course': course,
    'partantsClasses': partants,
    'scoresCriteres': criteres,
    'confiance': 71.0,
    'typePariConseille': 'Tiercé',
  };
}

const String kPoids = 'ia_poids_v3';
const String kPronostics = 'ia_pronostics_v2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _installerStore();
    IaMemoryService.instance.hookApresGetInstancePourTest = null;
    // Base saine : le singleton persiste entre les tests d'un même fichier.
    // `recharger()` vide les 13 collections RAM (dont `_pronostics`) et
    // repose `_loaded`. Sans lui, un test hériterait des pronostics du
    // précédent et l'anti-doublon fausserait toutes les mesures.
    await IaMemoryService.instance.recharger();
  });

  tearDown(() {
    IaMemoryService.instance.hookApresGetInstancePourTest = null;
    store.desarmer();
    store.libererSet();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V28-0 — TÉMOIN ABSOLU
  //
  //  Sans lui, « la clé est absente » ne prouverait rien : elle pourrait
  //  manquer simplement parce que le batch n'écrit jamais.
  // ═══════════════════════════════════════════════════════════════════════
  test('V28-0 — TÉMOIN : le batch nominal écrit en RAM et sur le disque',
      () async {
    final mem = IaMemoryService.instance;
    final course = _courseDuJour();
    final key = 'R1C1_${course.dateStr}';

    await mem.enregistrerPronosticsBatch([_itemBatch(course, key)]);

    debugPrint('V28-0 → RAM=${mem.pronostics.length} '
        'getPronostic!=null=${mem.getPronostic(key) != null} '
        'disque=${store.contient(kPronostics)}');

    expect(mem.getPronostic(key), isNotNull,
        reason: 'TÉMOIN : le batch crée le pronostic en RAM');
    expect(store.contient(kPronostics), isTrue,
        reason: 'TÉMOIN : le batch persiste ia_pronostics_v2 — sinon une clé '
            'absente après reset ne prouverait rien');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  SCÉNARIO A — le batch se termine PENDANT le reset
  //
  //    A1. le batch est engagé ; `_load()` rend la main ; il INSÈRE en RAM ;
  //    A2. `_save()` se suspend sur la première écriture (clé des poids) ;
  //    A3. le reset démarre : barrière fermée, génération +1 ;
  //    A4. le drain attend l'écriture engagée ;
  //    A5. libération → `_save()` reprend, son `_ecrireProtege` est REFUSÉ ;
  //    A6. le reset poursuit : vidage RAM puis effacement disque.
  //
  //  Attendu (invariant B5c) : RAM vide, disque vide.
  // ═══════════════════════════════════════════════════════════════════════
  test('V28-A — batch terminé PENDANT le reset : rien ne doit survivre',
      () async {
    final mem = IaMemoryService.instance;
    final course = _courseDuJour();
    final key = 'R1C1_${course.dateStr}';

    final entree = store.armerSuspensionSet(kPoids);
    final batch = mem.enregistrerPronosticsBatch([_itemBatch(course, key)]);

    final suspendu = await _attendreEntreeOuFin(entree, batch);
    expect(suspendu, isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : le batch doit être suspendu dans '
            '`_save()`, donc APRÈS avoir inséré en RAM');

    final refusAvant = mem.nbEcrituresRefuseesParReset;
    debugPrint('V28-A avant reset : RAM=${mem.pronostics.length} '
        'enCours=${mem.nbEcrituresEnCours} '
        'getPronostic!=null=${mem.getPronostic(key) != null}');

    expect(mem.getPronostic(key), isNotNull,
        reason: 'TÉMOIN : le pronostic est déjà en RAM avant le reset — '
            'c\'est cette insertion que le reset doit effacer');
    expect(mem.nbEcrituresEnCours, 1,
        reason: 'TÉMOIN : l\'écriture est au registre, le drain la verra');

    // ── A3/A4 : reset lancé pendant la suspension ────────────────────────
    //    Frontière du journal : tout ce qui précède vient de la préparation.
    final indexDebutReset = store.journal.length;
    final reset = BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    // ── A5 : libération → `_save()` reprend et écrit réellement ──────────
    store.libererSet();
    await batch;
    await reset;

    final refusDelta = mem.nbEcrituresRefuseesParReset - refusAvant;
    debugPrint('V28-A après : RAM=${mem.pronostics.length} '
        'disque=${store.contient(kPronostics)} refusDelta=$refusDelta '
        'enCours=${mem.nbEcrituresEnCours}');

    // ── ASSERTION 1 — le pronostic inséré avant le reset ne survit pas ───
    expect(mem.pronostics, isEmpty,
        reason: 'SCÉNARIO A : le pronostic inséré en RAM avant le reset ne '
            'doit pas réapparaître — le vidage a lieu APRÈS le drain');
    expect(store.contient(kPronostics), isFalse,
        reason: 'SCÉNARIO A : la clé effacée ne doit pas survivre, même si '
            'l\'écriture en vol a pu s\'exécuter');
    expect(mem.nbEcrituresEnCours, 0, reason: 'registre drainé');

    // ── ASSERTION 2 — MÉCANISME RÉEL : ce n'est PAS un refus ─────────────
    //    FAIT MESURÉ : `refusDelta == 0`. L'écriture était DÉJÀ dans son
    //    action, donc au-delà des contrôles 1 et 2 : elle n'est pas refusée,
    //    elle s'exécute. Ce qui protège, c'est l'ORDRE du reset —
    //    drain (2) → vidage RAM (4) → effacement disque (8).
    expect(refusDelta, 0,
        reason: 'FAIT MESURÉ : une écriture déjà engagée dans son action '
            'n\'est jamais refusée — les deux contrôles sont en amont. La '
            'protection du scénario A vient de l\'ORDRE des étapes du reset, '
            'pas de la barrière');

    // ── ASSERTION 3 — preuve de l'ordre par le journal du disque ─────────
    //    Le SET de `_save()` doit précéder le PREMIER `REM` du reset.
    final journalReset = store.journal.skip(indexDebutReset).toList();
    final iPremierRem =
        journalReset.indexWhere((e) => e.startsWith('REM '));
    final iPremierSetOk =
        journalReset.indexWhere((e) => e.startsWith('SET-OK'));
    debugPrint('V28-A ordre : iPremierSetOk=$iPremierSetOk '
        'iPremierRem=$iPremierRem '
        'nbRemDuReset=${journalReset.where((e) => e.startsWith('REM ')).length}');

    expect(iPremierSetOk, greaterThanOrEqualTo(0),
        reason: 'TÉMOIN : l\'écriture en vol a bien fini par écrire');
    expect(iPremierRem, greaterThanOrEqualTo(0),
        reason: 'TÉMOIN : le reset a bien effacé');
    expect(iPremierSetOk, lessThan(iPremierRem),
        reason: 'PREUVE DE L\'ORDRE : le drain a laissé l\'écriture se '
            'terminer AVANT la première suppression — c\'est cela qui rend '
            'le scénario A sûr');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  SCÉNARIO B — le batch se termine APRÈS la fin complète du reset
  //
  //  C'est le scénario qu'un garde `_resetEnCours` NE PEUT PAS couvrir.
  //
  //  Modélisation fidèle de `compute()` : la génération est CAPTURÉE avant le
  //  reset (comme `_enregistrerPronosticsBatchIsolate` la lit avant
  //  `compute()`), les scores sont calculés avec les poids d'AVANT (comme
  //  l'isolate qui a reçu `poidsJson` en payload), puis le lot est ENREGISTRÉ
  //  après la fin du reset — exactement ce que fait data_refresh_service.dart
  //  au retour de l'isolate. Aucune instrumentation n'est nécessaire : la
  //  latence de `compute()` est le point de suspension réel.
  // ═══════════════════════════════════════════════════════════════════════
  test('V28-B — batch préparé AVANT, enregistré APRÈS le reset : REJETÉ',
      () async {
    final mem = IaMemoryService.instance;
    final course = _courseDuJour();
    final key = 'R1C1_${course.dateStr}';

    // B1. Le « calcul dans l'isolate » : génération capturée et item prêt,
    //     rien encore enregistré.
    final generationAvantCalcul = mem.generationCache;
    final item = _itemBatch(course, key);
    expect(mem.pronostics, isEmpty, reason: 'TÉMOIN : rien en RAM');
    expect(store.contient(kPronostics), isFalse,
        reason: 'TÉMOIN : rien sur le disque');

    // B2. Reset complet, jusqu'au bout.
    await BackupService.instance.reinitialiserComplet();

    // B3. Le reset est TERMINÉ. On le prouve avant de continuer.
    //     POINT DE VIGILANCE 1 (a) : le reset vide la RAM.
    //     POINT DE VIGILANCE 1 (b) : le reset vide le disque.
    debugPrint('V28-B reset terminal : RAM=${mem.pronostics.length} '
        'disquePronostics=${store.contient(kPronostics)} '
        'enCours=${mem.nbEcrituresEnCours} '
        'generation $generationAvantCalcul→${mem.generationCache}');
    expect(mem.pronostics, isEmpty, reason: 'TÉMOIN : reset effectif en RAM');
    expect(store.contient(kPronostics), isFalse,
        reason: 'TÉMOIN : reset effectif sur le disque');
    expect(mem.nbEcrituresEnCours, 0, reason: 'TÉMOIN : registre vide');
    expect(mem.generationCache, isNot(generationAvantCalcul),
        reason: 'TÉMOIN : le reset a bien incrémenté la génération — sans cela '
            'le rejet ne prouverait rien');

    // B4. Retour de l'isolate : enregistrement APRÈS le reset, avec la
    //     génération capturée AVANT le calcul.
    final refusAvant = mem.nbEcrituresRefuseesParReset;
    final indexDebutBatch = store.journal.length;
    await mem.enregistrerPronosticsBatch([item],
        generationAuDemarrage: generationAvantCalcul);

    final ram = mem.pronostics.length;
    final disque = store.contient(kPronostics);
    final refusDelta = mem.nbEcrituresRefuseesParReset - refusAvant;
    // Journal postérieur à la frontière : aucune entrée d'écriture ne doit
    // y apparaître pour la clé des pronostics.
    final journalDepuisBatch = store.journal.skip(indexDebutBatch).toList();
    final ecrituresPronostics = journalDepuisBatch
        .where((e) =>
            (e.startsWith('SET-ENTREE ') || e.startsWith('SET-OK ')) &&
            e.contains(kPronostics))
        .toList();
    debugPrint('V28-B après enregistrement : RAM=$ram disque=$disque '
        'refusDelta=$refusDelta getPronostic!=null='
        '${mem.getPronostic(key) != null} '
        'ecrituresPronostics=$ecrituresPronostics');

    // ── POINT DE VIGILANCE 1 (c) : aucun pronostic ne réapparaît ─────────
    expect(mem.getPronostic(key), isNull,
        reason: 'CORRECTION : le lot est écarté, le pronostic effacé par le '
            'reset ne doit pas réapparaître en RAM');
    expect(mem.pronostics, isEmpty,
        reason: 'CORRECTION : la mémoire vidée par le reset reste vide');
    expect(disque, isFalse,
        reason: 'CORRECTION : la clé ia_pronostics_v2 effacée par le reset '
            'reste absente du disque');

    // ── POINT DE VIGILANCE 1 (d) : aucun enregistrement n'est effectué ───
    expect(ecrituresPronostics, isEmpty,
        reason: 'CORRECTION : aucune écriture n\'est même tentée sur la clé '
            'des pronostics — le rejet a lieu avant insertion et avant _save()');

    // ── Le rejet est un rejet de LOT, pas un refus de barrière ───────────
    //    `refusDelta` reste 0 : le lot n'atteint jamais `_ecrireProtege`,
    //    donc le compteur de refus n'est pas sollicité. C'est bien la
    //    comparaison de génération qui agit, à un autre niveau.
    expect(refusDelta, 0,
        reason: 'le rejet se produit APRÈS `_load()` et AVANT toute insertion : '
            'aucune écriture n\'est engagée, donc aucun refus de barrière');

    // ── POINT DE VIGILANCE 1 (e) : un batch frais reste ACCEPTÉ ──────────
    //    Sans cette assertion, un correctif trop large (qui rejetterait tout
    //    batch après n'importe quel reset) passerait pour correct.
    final generationApresReset = mem.generationCache;
    await mem.enregistrerPronosticsBatch([_itemBatch(course, key)],
        generationAuDemarrage: generationApresReset);

    debugPrint('V28-B batch frais : RAM=${mem.pronostics.length} '
        'disque=${store.contient(kPronostics)} '
        'getPronostic!=null=${mem.getPronostic(key) != null}');

    expect(mem.getPronostic(key), isNotNull,
        reason: 'CONTRÔLE NÉGATIF : un batch dont la génération est celle du '
            'reset est ACCEPTÉ — le correctif ne bloque pas tout');
    expect(store.contient(kPronostics), isTrue,
        reason: 'CONTRÔLE NÉGATIF : et il persiste normalement');
    expect(mem.pronostics.length, 1,
        reason: 'CONTRÔLE NÉGATIF : exactement un pronostic, celui du lot frais');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V28-B-bis — conséquence DURABLE : le rejet tient au-delà du processus
  //
  //  Avant correctif, le batch réécrivait la clé et le pronostic ressuscité
  //  traversait un `recharger()` : il n'était plus distinguable d'une donnée
  //  légitime. Après correctif, le lot est écarté AVANT toute écriture, donc
  //  le disque reste vierge : `recharger()` relit un disque vide et la
  //  réinitialisation tient durablement.
  // ═══════════════════════════════════════════════════════════════════════
  test('V28-B-bis — le lot rejeté ne ressuscite pas après rechargement',
      () async {
    final mem = IaMemoryService.instance;
    final course = _courseDuJour();
    final key = 'R1C1_${course.dateStr}';

    final generationAvantCalcul = mem.generationCache;
    final item = _itemBatch(course, key);
    await BackupService.instance.reinitialiserComplet();
    expect(mem.pronostics, isEmpty, reason: 'TÉMOIN : reset effectif');

    await mem.enregistrerPronosticsBatch([item],
        generationAuDemarrage: generationAvantCalcul);
    final ramApresBatch = mem.pronostics.length;
    final disqueApresBatch = store.contient(kPronostics);

    await mem.recharger();

    debugPrint('V28-B-bis → avantReload RAM=$ramApresBatch '
        'disque=$disqueApresBatch | aprèsReload RAM=${mem.pronostics.length} '
        'getPronostic!=null=${mem.getPronostic(key) != null}');

    // Le lot a été écarté : rien n'est écrit, donc `recharger()` relit un
    // disque vide. La réinitialisation n'est pas seulement valable en RAM,
    // elle est durable.
    expect(disqueApresBatch, isFalse,
        reason: 'CORRECTION : le lot rejeté n\'écrit rien sur le disque — '
            'c\'est la condition pour que le rechargement ne le ramène pas');
    expect(ramApresBatch, 0,
        reason: 'CORRECTION : et rien en RAM avant rechargement');
    expect(mem.pronostics, isEmpty,
        reason: 'CORRECTION : après rechargement depuis un disque vierge, la '
            'RAM reste vide — la réinitialisation tient au-delà du processus');
    expect(mem.getPronostic(key), isNull,
        reason: 'CORRECTION : le pronostic ne ressuscite pas, ni en RAM ni '
            'via le disque : il n\'y a plus de donnée indistingable d\'une '
            'donnée légitime');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V28-C — PORTÉE RÉELLE DE `_generationCache`
  //
  //  Le compteur est incrémenté à l'ÉTAPE 1 d'`executerResetComplet`, donc
  //  AVANT le drain et AVANT le vidage RAM. Un compteur capturé avant le
  //  reset est donc bien invalidé.
  //
  //  MAIS `_generationCache` est comparé DANS `_ecrireProtege`, c'est-à-dire
  //  au niveau d'UNE écriture, pas d'une transaction métier. Sa portée est
  //  donc locale : elle ne peut pas invalider un batch qui n'a pas encore
  //  commencé à écrire. C'est exactement ce que V28-B démontre.
  //
  //  Ce test fige la portée : deux écritures successives du MÊME batch, la
  //  première pendant le reset (refusée), la seconde après (acceptée).
  // ═══════════════════════════════════════════════════════════════════════
  test('V28-C — la génération protège une ÉCRITURE, pas une transaction',
      () async {
    final mem = IaMemoryService.instance;
    final course = _courseDuJour();
    final key = 'R1C1_${course.dateStr}';
    final item = _itemBatch(course, key);

    // Écriture n°1 : pendant le reset → refusée.
    final refusAvant = mem.nbEcrituresRefuseesParReset;
    final pendant = mem.enregistrerPronosticsBatch([item]);
    // Le reset est lancé sans attendre : `_resetEnCours` est posé
    // synchroniquement par `executerResetComplet` avant tout `await`.
    final reset = BackupService.instance.reinitialiserComplet();
    await Future.wait<void>([pendant, reset]);
    final refusApres1 = mem.nbEcrituresRefuseesParReset;

    debugPrint('V28-C écriture pendant reset : '
        'refus ${refusApres1 - refusAvant} '
        'RAM=${mem.pronostics.length} disque=${store.contient(kPronostics)}');

    // Écriture n°2 : après le reset → acceptée.
    await mem.enregistrerPronosticsBatch([item]);
    debugPrint('V28-C écriture après reset : '
        'RAM=${mem.pronostics.length} disque=${store.contient(kPronostics)}');

    // ── Ce qui est établi ────────────────────────────────────────────────
    expect(mem.pronostics, isNotEmpty,
        reason: 'la même transaction, rejouée APRÈS le reset, est acceptée : '
            'la génération ne « retient » pas le batch, elle ne juge que '
            'chaque appel d\'écriture');
    expect(store.contient(kPronostics), isTrue,
        reason: 'et elle réécrit le disque effacé par le reset');
  });
}
