// ═══════════════════════════════════════════════════════════════════════════
//  B5c — ÉTAPE 7 / R-DR-04 — DIAGNOSTIC EN LECTURE SEULE
//
//  OBJET : ÉTABLIR LES FAITS sur le risque de RECRÉATION DE PRONOSTICS après
//  un reset complet, via `IaMemoryService.invaliderEtRecalculer()`.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION N'EST APPORTÉE PAR CE FICHIER.
//
//  ── AUDIT STATIQUE (points 1 à 3 et 5 de la demande) ──────────────────────
//
//  1. UN SEUL chemin d'appel depuis DataRefreshService :
//       data_refresh_service.dart:610  (dans `reAnalyserCourse`)
//     lui-même appelé par :
//       • data_refresh_service.dart:486  ← `_detecterNonPartants()`, détection
//         AUTOMATIQUE des non-partants pendant `_doRefresh` (fenêtre -30/+240
//         min autour du départ) ;
//       • alert_service.dart:2005        ← recalcul après DQ/retrait saisi.
//
//  2. Chaîne de `invaliderEtRecalculer()` (ia_memory_service.dart:2445) :
//       await _load();                          ← l.2453  PORTE 1 (garde P3)
//       <lecture idx + calculs PURS>
//       _pronostics[idx] = nouveau
//         OU _pronostics.insert(0, nouveau)     ← l.2534-2539  MUTATION RAM
//       await _save();                          ← l.2542  PORTE 2 (_ecrireProtege)
//       notifyListeners();                      ← l.2543
//
//  3. `_load()` sort par `if (_resetEnCours) return;` (l.1678) et
//     `if (_loaded) return;` (l.1679).
//     `_save()` est intégralement protégé par `_ecrireProtege` (l.2082-2106) :
//     contrôle 1, contrôle 2 (génération), registre + drain.
//
//  ⇒ ASYMÉTRIE MESURÉE ICI : la MUTATION RAM (l.2534-2539) est SYNCHRONE et
//    n'est soumise à AUCUN contrôle, alors que l'écriture disque l'est.
//    C'est exactement la distinction demandée au point 5.
//
//  ⚠️ PORTÉE : observations ciblées sur IaMemoryService et l'ordre du reset.
//     Ne prouve pas que l'appairage réseau réel produit cet entrelacement.
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
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Store instrumenté : verrou set, verrou remove, journal.
// ───────────────────────────────────────────────────────────────────────────
class _StoreControle extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  Completer<void>? _verrouSet;
  String? _cleSetSuspendue;
  Completer<void>? _entreeSet;

  Completer<void>? _verrouRemove;
  String? _cleRemoveSuspendue;
  Completer<void>? _entreeRemove;

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
    if (_cleRemoveSuspendue != null && key.contains(_cleRemoveSuspendue!)) {
      final verrou = _verrouRemove;
      if (verrou != null) {
        final entree = _entreeRemove;
        _entreeRemove = null;
        if (entree != null && !entree.isCompleted) entree.complete();
        await verrou.future;
      }
    }
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET-ENTREE $key');
    if (_cleSetSuspendue != null && key.contains(_cleSetSuspendue!)) {
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
    _cleSetSuspendue = cle;
    _verrouSet = Completer<void>();
    return entree;
  }

  void libererSet() {
    final v = _verrouSet;
    _verrouSet = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  Completer<void> armerSuspensionRemove(String cle) {
    final entree = Completer<void>();
    _entreeRemove = entree;
    _cleRemoveSuspendue = cle;
    _verrouRemove = Completer<void>();
    return entree;
  }

  void libererRemove() {
    final v = _verrouRemove;
    _verrouRemove = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void desarmer() {
    _cleSetSuspendue = null;
    _verrouSet = null;
    _entreeSet = null;
    _cleRemoveSuspendue = null;
    _verrouRemove = null;
    _entreeRemove = null;
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  /// Effacement direct, utilisé par la clôture des resets pilotés par le test.
  void effacerDirect(String cle) {
    journal.add('REM flutter.$cle');
    _valeurs.remove('flutter.$cle');
  }
}

// ignore: library_private_types_in_public_api
late _StoreControle store;

void _installerStore() {
  store = _StoreControle();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

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

/// Cherche dans le journal APRÈS l'index [depuis] uniquement.
/// Indispensable : le journal est cumulatif sur toute la durée du test, donc
/// une recherche globale trouverait les traces d'une opération ANTÉRIEURE.
bool _journalDepuis(int depuis, bool Function(String) predicat) =>
    store.journal.skip(depuis).any(predicat);

// ── Constructeurs ──────────────────────────────────────────────────────────

const String kCourseKey = 'R1C1_01012026';
const String kPronosticsKey = 'ia_pronostics_v2';
const String kPoidsKey = 'ia_poids_v3';
const String kCleTardive = 'alert_config_v2'; // index 86 sur 107

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
      ageSexe: '5 M',
      poids: 57.0 + num,
      placeDepartInt: num,
      joursRepos: 10 + num,
      hippodromeActuel: 'VINCENNES',
      statsJockeyCsv: 'JOCKEY_$num|15|40|12',
      statsHippodromeCsv: 'VINCENNES|20|45|15',
      statsEntraineurCsv: 'ENTR_$num|12|33|8',
      eloRating: 1500.0,
      eloNbCourses: 20,
      eloVariationMois: 5.0,
      statsTerrainCsv: 'bon|6|2|4',
      gainsDernierAn: num * 5000,
      scoreIA: 70.0 - num,
    );

/// Date du jour au format `ddmmyyyy`. SANS elle, `heureDateTime` retombe sur
/// 2000-01-01 et `_purgerVieuxPronostics()` supprime le pronostic AVANT même
/// qu'on puisse l'observer : le témoin serait muet.
String _dateDuJour() {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

ZtCourse _course(List<ZtPartant> partants) => ZtCourse(
      numCourse: 1,
      anchor: 'R1C1',
      nom: 'PRIX DE TEST',
      heure: '13:45',
      distance: '2100',
      prix: '50000',
      type: 'Trot Attelé',
      piste: 'Cendrée',
      categorie: 'Course D',
      isQuinte: false,
      pronosticZt: const <int>[],
      partants: partants,
    )..dateStr = _dateDuJour();

final List<ZtPartant> kPartants = List.generate(6, (i) => _partant(i + 1));

ScoresCriteres _criteres() => const ScoresCriteres(
      forme: 71, gains: 62, record: 55, cote: 48,
      constance: 60, victoires: 66, discipline: 58,
    );

Future<void> _invalider({
  String courseKey = kCourseKey,
  List<ZtPartant>? partants,
  String raison = 'test R-DR-04',
}) {
  final p = partants ?? kPartants;
  return IaMemoryService.instance.invaliderEtRecalculer(
    courseKey: courseKey,
    course: _course(p),
    partantsClasses: p,
    scoresCriteres: <String, ScoresCriteres>{
      for (final q in p) q.numero: _criteres()
    },
    confiance: 66.0,
    raisonInvalidation: raison,
  );
}

int _nbPronostics() => IaMemoryService.instance.pronostics.length;

List<String> _blobDisque() {
  final v = store.lire(kPronosticsKey);
  if (v is List) return v.cast<String>();
  return const <String>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _installerStore();
  });

  tearDown(() {
    store.desarmer();
    store.libererSet();
    store.libererRemove();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  TÉMOIN — sans lui, « 0 pronostic après reset » ne prouverait rien.
  // ═══════════════════════════════════════════════════════════════════════
  test('R04-0 TÉMOIN — un recalcul HORS reset crée le pronostic (RAM + disque)',
      () async {
    final mem = IaMemoryService.instance;

    await _invalider();
    debugPrint('R04-0 → RAM=${_nbPronostics()} '
        'getPronostic=${mem.getPronostic(kCourseKey) != null} '
        'disque=${store.contient(kPronosticsKey)} nbBlob=${_blobDisque().length}');

    expect(mem.getPronostic(kCourseKey), isNotNull,
        reason: 'TÉMOIN : le pronostic est créé en RAM');
    expect(store.contient(kPronosticsKey), isTrue,
        reason: 'TÉMOIN : `_save()` a écrit le blob — sinon une absence après '
            'reset ne prouverait rien');
    expect(_blobDisque(), isNotEmpty, reason: 'TÉMOIN : blob non vide');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A — RECALCUL COMMENCÉ AVANT LE RESET, TERMINÉ PENDANT CELUI-CI
  //
  //  `_save()` est suspendue DANS le store sur `ia_poids_v3` (première
  //  écriture de l'unité protégée). À cet instant :
  //    • la MUTATION RAM a déjà eu lieu ;
  //    • l'écriture est ENGAGÉE et au registre.
  //  Le reset la DRAINE avant d'effacer, puis vide la RAM.
  // ═══════════════════════════════════════════════════════════════════════
  test('R04-A — recalcul terminé PENDANT le reset (écriture drainée)', () async {
    final mem = IaMemoryService.instance;

    await _invalider(raison: 'état initial');
    expect(mem.getPronostic(kCourseKey), isNotNull, reason: 'TÉMOIN initial');

    final marque = store.journal.length;
    store.armerSuspensionSet(kPoidsKey);
    final recalcul = _invalider(raison: 'recalcul suspendu');

    final suspendu = await _attendreQue(
        () => _journalDepuis(marque, (e) => e.startsWith('SET-ENTREE')));
    expect(suspendu, isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : `_save()` suspendue dans le store, '
            'donc mutation RAM déjà faite');
    await _laisserProgresser(4);

    debugPrint('R04-A avant reset : RAM=${_nbPronostics()} '
        'enCours=${mem.nbEcrituresEnCours} '
        'disque=${store.contient(kPronosticsKey)}');

    expect(mem.nbEcrituresEnCours, 1,
        reason: 'TÉMOIN : l\'écriture est au registre — le drain la verra');

    // ── Reset lancé sans être attendu ────────────────────────────────────
    final marqueReset = store.journal.length;
    final reset = BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    final effacementCommence =
        _journalDepuis(marqueReset, (e) => e.startsWith('REM '));
    debugPrint('R04-A reset bloqué : effacementCommence=$effacementCommence '
        'enCours=${mem.nbEcrituresEnCours}');
    expect(effacementCommence, isFalse,
        reason: 'PREUVE DU DRAIN : le reset attend l\'écriture engagée du '
            'recalcul avant de commencer à effacer');

    store.libererSet();
    await recalcul;
    await reset;

    debugPrint('R04-A après : RAM=${_nbPronostics()} '
        'getPronostic=${mem.getPronostic(kCourseKey) != null} '
        'disque=${store.contient(kPronosticsKey)} '
        'nbBlob=${_blobDisque().length}');

    expect(store.contient(kPronosticsKey), isFalse,
        reason: 'FAIT : le blob pronostics est ABSENT du disque après le reset '
            '— les ÉCRITURES sont bien protégées');
    expect(_nbPronostics(), 0,
        reason: 'FAIT : le vidage `_pronostics.clear()` a lieu APRÈS le drain, '
            'donc il efface la mutation RAM du recalcul. Scénario SAIN PAR '
            'ORDRE, pas par une protection dédiée');
    expect(mem.getPronostic(kCourseKey), isNull,
        reason: 'FAIT : RAM et disque cohérents sur ce scénario');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B — ÉCRITURE NÉE AVANT LE RESET, ATTEIGNANT LE DISQUE APRÈS
  //
  //  Le drain ne peut rien pour elle : au moment du reset, elle n'est PAS au
  //  registre. Le seul point situé entre la capture de la génération et le
  //  contrôle 2 est le hook P4 (`hookApresGetInstancePourTest`, l.2093),
  //  documenté comme NUL en production et @visibleForTesting. Il est utilisé
  //  ici exactement pour ce pourquoi il a été créé.
  //
  //  Le reset est piloté DIRECTEMENT (clôture fournie par le test) : il n'a
  //  donc pas besoin de `getInstance()` et peut aboutir pendant la
  //  suspension. Patron identique à V29-G (R-DR-05).
  //
  //  ⚠️ CONSTAT PRÉALABLE, mesuré lors de la première tentative : suspendre
  //     `getInstance()` par un verrou de store ne permet PAS d'atteindre la
  //     porte 2 — la suspension tombe dans `await _load()` (l.2453), donc
  //     AVANT la mutation. C'est cohérent avec la production, où `_loaded`
  //     vaut `true` et où `_load()` ne suspend donc jamais. Ce point est
  //     documenté comme risque résiduel (R-DR-04-note-1).
  // ═══════════════════════════════════════════════════════════════════════
  test('R04-B — écriture née AVANT le reset, refusée par la GÉNÉRATION', () async {
    final mem = IaMemoryService.instance;

    await _invalider(raison: 'état initial');
    expect(mem.getPronostic(kCourseKey), isNotNull, reason: 'TÉMOIN initial');

    final genAvant = mem.generationCache;
    var resets = 0;

    // Hook P4 : s'exécute APRÈS la capture de génération, AVANT le contrôle 2.
    mem.hookApresGetInstancePourTest = () async {
      if (resets == 0) {
        resets++;
        await mem.executerResetComplet(() async {
          store.effacerDirect(kPronosticsKey);
          store.effacerDirect(kPoidsKey);
          await Future<void>.delayed(Duration.zero);
        });
      }
    };
    addTearDown(() => mem.hookApresGetInstancePourTest = null);

    final refusAvant = mem.nbEcrituresRefuseesParReset;
    await _invalider(raison: 'écriture née avant le reset');
    await _laisserProgresser();

    final deltaRefus = mem.nbEcrituresRefuseesParReset - refusAvant;
    debugPrint('R04-B : resets=$resets gen=$genAvant→${mem.generationCache} '
        'deltaRefus=$deltaRefus disque=${store.contient(kPronosticsKey)} '
        'RAM=${_nbPronostics()}');

    expect(resets, 1,
        reason: 'TÉMOIN DE PRÉPARATION : un reset complet a bien été exécuté '
            'ENTRE la capture de génération et le contrôle 2');
    expect(mem.generationCache, genAvant + 1,
        reason: 'TÉMOIN : la génération a été incrémentée');

    // ── FAIT : l'écriture disque est REFUSÉE par le contrôle 2 ───────────
    expect(deltaRefus, greaterThanOrEqualTo(1),
        reason: 'FAIT : l\'écriture est refusée — sa génération capturée est '
            'devenue périmée. La protection disque fonctionne');
    expect(store.contient(kPronosticsKey), isFalse,
        reason: 'FAIT : le blob n\'est PAS recréé après l\'effacement');

    // ── FAIT : la mutation RAM PRÉCÈDE le reset, donc elle est effacée ───
    //
    //  Le hook P4 est situé DANS `_save()` (l.2093), donc APRÈS la mutation
    //  RAM (l.2534-2539). Quand le reset s'exécute à cet endroit, son vidage
    //  `_pronostics.clear()` a lieu APRÈS la mutation : elle est donc effacée.
    expect(_nbPronostics(), 0,
        reason: 'FAIT : la mutation RAM a précédé le vidage du reset, donc '
            'elle est effacée. CE SCÉNARIO EST SAIN — le pronostic n\'existe '
            'plus ni en RAM ni sur le disque');
    expect(mem.getPronostic(kCourseKey), isNull,
        reason: 'FAIT : aucun pronostic consultable — RAM et disque cohérents');
    expect(store.contient(kPronosticsKey), isFalse,
        reason: 'FAIT : disque vide — cohérence confirmée');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  C — RECALCUL DÉCLENCHÉ PENDANT L'EFFACEMENT (vidage RAM pas encore fait)
  //
  //  Reset suspendu sur la clé tardive (index 86). À cet instant le vidage
  //  `_pronostics.clear()` (l.1553, étape 4) N'A PAS ENCORE EU LIEU : il
  //  précède l'étape 8 (effacement). La mutation RAM profite donc du vidage
  //  qui vient APRÈS elle → elle est effacée.
  // ═══════════════════════════════════════════════════════════════════════
  test('R04-C — recalcul PENDANT l\'effacement, AVANT le vidage RAM', () async {
    final mem = IaMemoryService.instance;

    await _invalider(raison: 'état initial');
    expect(mem.getPronostic(kCourseKey), isNotNull, reason: 'TÉMOIN initial');

    final marque = store.journal.length;
    store.semer(kCleTardive, 'sentinelle');
    store.armerSuspensionRemove(kCleTardive);
    final reset = BackupService.instance.reinitialiserComplet();

    final suspendu = await _attendreQue(
        () => _journalDepuis(marque, (e) => e == 'REM flutter.$kCleTardive'));
    expect(suspendu, isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : boucle suspendue sur la clé tardive — '
            'donc le vidage RAM (étape 4) a DÉJÀ eu lieu, et l\'effacement '
            '(étape 8) est en cours');

    final ramApresVidage = _nbPronostics();
    debugPrint('R04-C état à la suspension : RAM=$ramApresVidage');
    expect(ramApresVidage, 0,
        reason: 'TÉMOIN CAPITAL : le vidage RAM a déjà eu lieu à cet instant. '
            'Toute mutation à partir d\'ICI ne sera PLUS effacée par le reset');

    final marqueEcriture = store.journal.length;
    final refusAvant = mem.nbEcrituresRefuseesParReset;

    await _invalider(raison: 'recalcul dans la fenêtre');
    await _laisserProgresser(4);

    final deltaRefus = mem.nbEcrituresRefuseesParReset - refusAvant;
    final ecrit = _journalDepuis(
        marqueEcriture, (e) => e.contains(kPronosticsKey));
    debugPrint('R04-C dans la fenêtre : RAM=${_nbPronostics()} '
        'deltaRefus=$deltaRefus disque=${store.contient(kPronosticsKey)} '
        'journal=$ecrit');

    // ── CORRECTION R-DR-04 : la mutation RAM est REFUSÉE ─────────────────
    expect(_nbPronostics(), 0,
        reason: 'CORRECTION R-DR-04 : la garde de génération refuse la MUTATION '
            'RAM. Avant correctif, le pronostic réapparaissait en RAM alors que '
            'le reset avait déjà vidé `_pronostics` (défaut mesuré)');
    // ── CORRECTION R-DR-04 : le refus a lieu AVANT `_save()` ─────────────
    //
    //  AVANT correctif, la mutation RAM passait, puis `_save()` atteignait le
    //  contrôle 1 de `_ecrireProtege` → `nbEcrituresRefuseesParReset`
    //  s'incrémentait (mesuré : deltaRefus=1).
    //
    //  APRÈS correctif, la garde de génération sort de `invaliderEtRecalculer`
    //  AVANT `_save()` : le contrôle 1 n'est JAMAIS atteint, donc le compteur
    //  disque reste à 0. C'est la preuve mesurable que la garde RAM précède
    //  bien la porte disque.
    expect(deltaRefus, 0,
        reason: 'CORRECTION R-DR-04 : le compteur d\'écritures refusées par '
            'reset reste à 0 — `_save()` n\'est même plus atteint, la garde '
            'RAM a coupé court AVANT. Avant correctif : deltaRefus=1 (le '
            'contrôle 1 de `_ecrireProtege` était atteint)');
    expect(ecrit, isFalse,
        reason: 'FAIT : aucune écriture disque tentée pour le blob');

    store.libererRemove();
    await reset;
    await _laisserProgresser();

    final ramFinale = _nbPronostics();
    final disqueFinal = store.contient(kPronosticsKey);
    debugPrint('R04-C après fin du reset : RAM=$ramFinale disque=$disqueFinal');

    expect(disqueFinal, isFalse, reason: 'FAIT : disque vide');
    expect(ramFinale, 0,
        reason: 'CORRECTION R-DR-04 : la RAM reste VIDE — RAM et disque sont '
            'COHÉRENTS. Avant correctif, la RAM conservait un pronostic absent '
            'du disque (divergence mesurée)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D — PERSISTANCE : le pronostic fantôme est réécrit sur le disque par le
  //      prochain `_save()` LÉGITIME, une fois la barrière rouverte.
  //
  //  C'est la conséquence DURABLE du scénario C : plus rien ne distingue le
  //  pronostic muté dans la fenêtre d'un pronostic légitime. Le premier
  //  `_save()` suivant le persiste → la réinitialisation est ANNULÉE.
  // ═══════════════════════════════════════════════════════════════════════
  test('R04-D — PERSISTANCE : un `_save()` ultérieur réécrit le fantôme', () async {
    final mem = IaMemoryService.instance;

    await _invalider(raison: 'état initial');
    final marque = store.journal.length;
    store.semer(kCleTardive, 'sentinelle');
    store.armerSuspensionRemove(kCleTardive);
    final reset = BackupService.instance.reinitialiserComplet();
    await _attendreQue(
        () => _journalDepuis(marque, (e) => e == 'REM flutter.$kCleTardive'));

    await _invalider(raison: 'fantôme');
    await _laisserProgresser(4);
    expect(_nbPronostics(), 0,
        reason: 'CORRECTION R-DR-04 : plus aucun fantôme en RAM — la mutation '
            'est refusée. Avant correctif, elle créait un pronostic fantôme');

    store.libererRemove();
    await reset;
    await _laisserProgresser();

    debugPrint('R04-D après reset : RAM=${_nbPronostics()} '
        'disque=${store.contient(kPronosticsKey)}');
    expect(store.contient(kPronosticsKey), isFalse,
        reason: 'TÉMOIN : le disque est encore vierge à cet instant');

    // ── Opération LÉGITIME qui déclenche un `_save()` ────────────────────
    //    Aucune formule IA n'est touchée : `resetPoids()` remet les poids par
    //    défaut puis appelle `_save()`. On ne mesure que la PERSISTANCE.
    await mem.resetPoids();
    await _laisserProgresser();

    final clesFinales = _blobDisque()
        .map((s) => (jsonDecode(s) as Map<String, dynamic>)['courseKey'])
        .toList();
    debugPrint('R04-D après _save() légitime : RAM=${_nbPronostics()} '
        'disque=${store.contient(kPronosticsKey)} '
        'nbBlob=${_blobDisque().length} cles=$clesFinales');

    // ── CORRECTION : aucune résurrection sur le disque ───────────────────
    //
    //  Deux protections se cumulent ici, et c'est voulu :
    //    • la garde R-DR-04 empêche la mutation RAM → il n'y a plus rien à
    //      persister (cause racine traitée) ;
    //    • `_save()` reste de toute façon protégé par `_ecrireProtege` si un
    //      pronostic légitime existait déjà (protection en profondeur).
    expect(clesFinales, isNot(contains(kCourseKey)),
        reason: 'CORRECTION R-DR-04 : le pronostic fabriqué dans la fenêtre '
            'n\'est PLUS persisté. Avant correctif, le blob était réécrit et '
            'la réinitialisation définitivement annulée');
    expect(_nbPronostics(), 0,
        reason: 'CORRECTION : la RAM non plus ne ressuscite pas');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  E — NON-RÉGRESSION : un recalcul APRÈS un reset réussi fonctionne.
  // ═══════════════════════════════════════════════════════════════════════
  test('R04-E — un recalcul APRÈS un reset réussi fonctionne normalement',
      () async {
    final mem = IaMemoryService.instance;

    await _invalider(raison: 'avant reset');
    expect(mem.getPronostic(kCourseKey), isNotNull, reason: 'TÉMOIN');

    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    debugPrint('R04-E après reset : RAM=${_nbPronostics()} '
        'disque=${store.contient(kPronosticsKey)}');
    expect(_nbPronostics(), 0, reason: 'FAIT : reset réussi');
    expect(store.contient(kPronosticsKey), isFalse, reason: 'FAIT : disque vide');

    await _invalider(raison: 'après reset');
    await _laisserProgresser();

    debugPrint('R04-E après recalcul : RAM=${_nbPronostics()} '
        'disque=${store.contient(kPronosticsKey)} '
        'nbBlob=${_blobDisque().length}');

    expect(mem.getPronostic(kCourseKey), isNotNull,
        reason: 'NON-RÉGRESSION : service opérationnel après reset réussi');
    expect(store.contient(kPronosticsKey), isTrue,
        reason: 'NON-RÉGRESSION : et il persiste normalement');
  });
  // ═══════════════════════════════════════════════════════════════════════
  //  F — VÉRIFICATION 1 : ÉVICTION ET ARCHIVAGE DANS LA FENÊTRE
  //
  //  QUESTION : une éviction (`_evincerAuDelaDeLaLimite`, l.2528) ou une
  //  écriture dans `IaArchiveService` peut-elle intervenir AVANT la garde ?
  //
  //  ORDRE RÉEL (l.2521-2533) :
  //    2521  if (idx >= 0) {
  //    2522    _pronostics[idx] = nouveauPronostic;   ← MUTATION
  //    2525  } else {
  //    2526    _pronostics.insert(0, nouveauPronostic); ← MUTATION
  //    2528    _evincerAuDelaDeLaLimite();             ← ÉVICTION (après)
  //    2530  }
  //    2532  await _save();                          ← PORTE 2
  //    2533  notifyListeners();
  //
  //  `_evincerAuDelaDeLaLimite()` est donc TOUJOURS APRÈS la mutation, et
  //  uniquement dans la branche `else`. Deux raisons structurelles font
  //  qu'elle ne peut pas être polluée par un reset :
  //    (a) aucun `await` ne sépare la mutation de l'éviction (vérifié : les
  //        seuls `await` postérieurs à `_load()` sont 2532 et 2541) → le
  //        reset ne peut pas s'intercaler ENTRE les deux ;
  //    (b) si le reset s'intercale AVANT la mutation, il a déjà vidé
  //        `_pronostics` (l.1553) → `length == 0 <= 600` → l'éviction sort
  //        immédiatement (`if (_pronostics.length <= _maxPronostics) return`).
  // ═══════════════════════════════════════════════════════════════════════
  test('R04-F — aucune éviction ni archivage déclenché dans la fenêtre', () async {
    final archive = IaArchiveService.instance;

    await _invalider(raison: 'état initial');

    final evictionsAvant = archive.nbEvictionsNonArchivees;
    final versionsAvant = archive.nbVersionsArchivees;

    final marque = store.journal.length;
    store.semer(kCleTardive, 'sentinelle');
    store.armerSuspensionRemove(kCleTardive);
    final reset = BackupService.instance.reinitialiserComplet();
    await _attendreQue(
        () => _journalDepuis(marque, (e) => e == 'REM flutter.$kCleTardive'));

    expect(_nbPronostics(), 0, reason: 'TÉMOIN : vidage RAM déjà effectué');

    // Recalcul dans la fenêtre (branche else : idx == -1 car RAM vide).
    await _invalider(raison: 'recalcul dans la fenêtre');
    await _laisserProgresser(4);

    final evictionsPendant = archive.nbEvictionsNonArchivees;
    final versionsPendant = archive.nbVersionsArchivees;
    debugPrint('R04-F archive : evictions $evictionsAvant→$evictionsPendant '
        'versions $versionsAvant→$versionsPendant '
        'RAM=${_nbPronostics()}');

    expect(evictionsPendant, evictionsAvant,
        reason: 'RISQUE R-DR-04-c ÉCARTÉ : aucune éviction en attente '
            'd\'archivage n\'a été créée. `_pronostics` était vide au moment '
            'de l\'éviction, donc `length <= 600` a fait sortir la méthode '
            'immédiatement');
    expect(versionsPendant, versionsAvant,
        reason: 'RISQUE R-DR-04-c ÉCARTÉ : aucune écriture d\'archive n\'a eu '
            'lieu — `enregistrerEviction` n\'a même pas été appelée');
    expect(_nbPronostics(), 0,
        reason: 'CORRECTION R-DR-04 : le recalcul de la fenêtre est REFUSÉ, '
            'donc `_pronostics` reste vide. Avant correctif, il contenait 1 '
            'pronostic fantôme — et si `_evincerAuDelaDeLaLimite()` avait été '
            'atteinte avec un tableau plein, elle aurait créé une éviction à '
            'archiver. La garde étant placée AVANT la mutation ET avant '
            'l\'éviction (l.2528), ce chemin est structurellement inatteignable');

    store.libererRemove();
    await reset;
    await _laisserProgresser();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G — VÉRIFICATION 2 : LE FAUX SIGNALEMENT DE RECALCUL
  //
  //  QUESTION : un recalcul annulé peut-il être annoncé comme réussi ?
  //
  //  DEUX canaux distincts :
  //    • IaMemoryService : `notifyListeners()` (l.2533). La garde étant placée
  //      AVANT la mutation, elle sort par `return` et n'atteint PAS 2532-2533.
  //      ⇒ aucun signal IA émis pour un recalcul refusé.
  //    • DataRefreshService : APRÈS l'appel (l.621-636), il met à jour
  //      `_reunions`, journalise « ✅ Pronostic recalculé » et appelle
  //      `notifyListeners()` SANS AUCUN RETOUR D'INFORMATION : la méthode
  //      retourne `Future<void>`.
  //      ⇒ FAUX SIGNALEMENT, indépendant de la garde (déjà vrai quand la
  //        barrière refusait `_save()`), mais rendu plus fréquent par elle.
  //  Ce test mesure le canal DataRefreshService.
  // ═══════════════════════════════════════════════════════════════════════
  test('R04-G — DataRefreshService annonce un recalcul malgré le refus', () async {
    final mem = IaMemoryService.instance;
    final refresh = DataRefreshService.instance;

    var notifs = 0;
    void compteur() => notifs++;
    refresh.addListener(compteur);
    addTearDown(() => refresh.removeListener(compteur));

    var resets = 0;
    mem.hookApresGetInstancePourTest = () async {
      if (resets == 0) {
        resets++;
        await mem.executerResetComplet(() async {
          store.effacerDirect(kPronosticsKey);
          store.effacerDirect(kPoidsKey);
          await Future<void>.delayed(Duration.zero);
        });
      }
    };
    addTearDown(() => mem.hookApresGetInstancePourTest = null);

    final notifsAvant = notifs;
    await refresh.reAnalyserCourse(
      courseKey: kCourseKey,
      course: _course(kPartants),
      retraits: const <int>[6],
    );
    await _laisserProgresser(4);

    final pronostic = mem.getPronostic(kCourseKey);
    final deltaNotifs = notifs - notifsAvant;
    debugPrint('R04-G : resets=$resets RAM=${_nbPronostics()} '
        'getPronostic=${pronostic != null} '
        'disque=${store.contient(kPronosticsKey)} '
        'notifsDataRefresh=$deltaNotifs');

    // ── FAIT 1 : le recalcul a bien été REFUSÉ par la barrière ───────────
    expect(store.contient(kPronosticsKey), isFalse,
        reason: 'FAIT : l\'écriture disque a été refusée par la génération');

    // ── FAIT 2 : et pourtant DataRefreshService NOTIFIE ──────────────────
    expect(deltaNotifs, greaterThanOrEqualTo(1),
        reason: 'FAUX SIGNALEMENT MESURÉ : `reAnalyserCourse` appelle '
            '`notifyListeners()` (l.635) et journalise « ✅ Pronostic '
            'recalculé » (l.634) SANS savoir que le recalcul a été refusé — '
            '`invaliderEtRecalculer` retourne `Future<void>`, aucun canal de '
            'retour n\'existe');

    // ── FAIT 3 : la garde R-DR-04 a bien empêché la mutation RAM ─────────
    expect(pronostic, isNull,
        reason: 'CORRECTION R-DR-04 : la mutation RAM est refusée — il n\'y a '
            'plus de pronostic fantôme');
    expect(_nbPronostics(), 0,
        reason: 'CORRECTION R-DR-04 : `_pronostics` reste vide');

    // ── FAIT 4 : LE FAUX SIGNALEMENT SUBSISTE, ET C'EST DOCUMENTÉ ────────
    //
    //  DÉCISION : il n'est PAS corrigé dans cette intervention.
    //  Cause : `invaliderEtRecalculer()` retourne `Future<void>` — aucun
    //  canal de retour n'indique à `reAnalyserCourse` que le recalcul a été
    //  refusé. Corriger exige soit un changement de signature (interdit ici),
    //  soit un compteur public dédié (correctif séparé).
    //  Ce test FIXE le comportement actuel pour qu'il ne passe pas inaperçu :
    //  le jour où le signalement sera corrigé, cette assertion devra être
    //  inversée, ce qui rendra la correction visible dans le diff.
    debugPrint('R04-G RAM après refus : ${_nbPronostics()} '
        'pronostic=${pronostic != null} — faux signalement CONSERVÉ (documenté)');
  });
}
