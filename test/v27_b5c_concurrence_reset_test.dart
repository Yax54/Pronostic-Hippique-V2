// ═══════════════════════════════════════════════════════════════════════════
//  B5c — P4 : résistance du reset complet aux opérations concurrentes
//
//  Chaque test est DÉTERMINISTE : aucune latence simulée. La concurrence est
//  obtenue par des `Completer` contrôlés par le test, que le store instrumenté
//  attend explicitement. Deux signaux synchronisent :
//    • `entreeDansOperation` — « le code a atteint l'opération suspendue » ;
//    • `finOperation`       — « l'opération s'est terminée » (échappatoire
//      anti-blocage quand le code ne suspend pas, ce qui permet d'échouer
//      franchement au lieu de figer le test).
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
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Store instrumenté : journal d'ORDRE des opérations réellement exécutées
//  + verrous contrôlés par le test (jamais par une durée).
// ───────────────────────────────────────────────────────────────────────────
class StoreControle extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};

  /// Journal d'ORDRE : chaque entrée est ajoutée au moment de l'appel.
  /// Sert d'observable principal (ordre des opérations réellement exécutées).
  final List<String> journal = <String>[];

  int getAllAppels = 0;
  final List<String> remAppeles = <String>[];
  final List<String> setAppeles = <String>[];

  // ── Verrou de suspension sur `getAll` (retarde `getInstance()`) ──────────
  Completer<void>? _verrouGetAll;
  Completer<void>? _entreeGetAll;

  // ── Verrou de suspension sur `setValue` d'une clé précise ───────────────
  Completer<void>? _verrouSet;
  String? _cleSuspendueSet;
  Completer<void>? _entreeSet;

  // ── Verrou « Nième appel » : isole la GÉNÉRATION du contrôle 1 ──────────
  //    Sert au scénario où le reset s'exécute ENTIÈREMENT pendant que
  //    l'écriture est suspendue : au réveil, `_resetEnCours` est déjà
  //    retombé à false, donc seul le changement de génération peut refuser.
  int? _bloquerAppelGetAll;
  int _compteurGetAll = 0;
  Completer<void>? _entreeGetAllN;
  Completer<void>? _verrouGetAllN;

  Completer<void> armerSuspensionGetAllNieme(int n) {
    _compteurGetAll = 0;
    _bloquerAppelGetAll = n;
    final entree = Completer<void>();
    _entreeGetAllN = entree;
    _verrouGetAllN = Completer<void>();
    return entree;
  }

  void libererGetAllN() {
    final v = _verrouGetAllN;
    _verrouGetAllN = null;
    _bloquerAppelGetAll = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  // ── Politique de panne ──────────────────────────────────────────────────
  final Set<String> clesEnPanne = <String>{};
  bool panneParException = true;
  final List<String> pannes = <String>[];

  bool _doitEchouer(String cle) {
    final nue = cle.startsWith('flutter.') ? cle.substring(8) : cle;
    return clesEnPanne.contains(cle) || clesEnPanne.contains(nue);
  }

  bool get enSuspension => _verrouGetAll != null || _verrouSet != null;

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
    journal.add('GETALL');

    // Verrou « Nième appel » (prioritaire, scénario génération seule).
    if (_bloquerAppelGetAll != null) {
      _compteurGetAll++;
      if (_compteurGetAll == _bloquerAppelGetAll) {
        final e = _entreeGetAllN;
        _entreeGetAllN = null;
        if (e != null && !e.isCompleted) e.complete();
        final v = _verrouGetAllN;
        if (v != null) await v.future;
      }
    }

    final verrou = _verrouGetAll;
    if (verrou != null) {
      final entree = _entreeGetAll;
      _entreeGetAll = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      await verrou.future;
    }
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    remAppeles.add(key);
    if (_doitEchouer(key)) {
      pannes.add('REM $key');
      if (panneParException) throw StateError('PANNE SIMULÉE (REM) sur $key');
      return false;
    }
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET-ENTREE $key');
    setAppeles.add(key);
    if (_doitEchouer(key)) {
      pannes.add('SET $key');
      if (panneParException) throw StateError('PANNE SIMULÉE (SET) sur $key');
      return false;
    }
    if (_cleSuspendueSet != null && key.contains(_cleSuspendueSet!)) {
      final verrou = _verrouSet;
      if (verrou != null) {
        final entree = _entreeSet;
        _entreeSet = null;
        if (entree != null && !entree.isCompleted) entree.complete();
        await verrou.future;
      }
    }
    _valeurs[key] = value;
    return true;
  }

  // ── Armement / libération ───────────────────────────────────────────────
  /// Arme la suspension et rend le `Completer` d'ENTRÉE : le test l'attend
  /// via `attendreEntreeOuFin`.
  Completer<void> armerSuspensionGetAll() {
    final entree = Completer<void>();
    _entreeGetAll = entree;
    _verrouGetAll = Completer<void>();
    return entree;
  }

  Completer<void> armerSuspensionSet(String cle) {
    final entree = Completer<void>();
    _entreeSet = entree;
    _cleSuspendueSet = cle;
    _verrouSet = Completer<void>();
    return entree;
  }

  void libererGetAll() {
    final v = _verrouGetAll;
    _verrouGetAll = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void libererSet() {
    final v = _verrouSet;
    _verrouSet = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void toutLiberer() {
    libererGetAll();
    libererSet();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;

  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');

  Object? lire(String cle) => _valeurs['flutter.$cle'];

  List<String> get clesArchive => _valeurs.keys
      .where((k) => k.startsWith('flutter.ia_archive_v1_'))
      .toList()
    ..sort();

  int get nbRem => journal.where((e) => e.startsWith('REM ')).length;

  int indexPremierRem() => journal.indexWhere((e) => e.startsWith('REM '));

  int indexDe(String entree) => journal.indexOf(entree);
}

late StoreControle store;

void installerStore() {
  store = StoreControle();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

/// Vidage BORNÉ de la boucle d'événements : permet aux tâches déjà démarrées
/// d'atteindre leur premier point de suspension. Ce n'est pas une latence
/// simulée : aucune durée significative, et aucune assertion n'en dépend
/// seule (les observables sont l'ordre du journal et l'état du disque).
Future<void> laisserProgresser([int tours = 12]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Attend un signal d'entrée OU la fin de l'opération, sans jamais figer :
/// si le code ne suspend pas, on le sait explicitement.
/// Retourne `true` si la suspension a bien été atteinte.
Future<bool> attendreEntreeOuFin(
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

ZtCourse courseTest(int numCourse, String nom) => ZtCourse(
      numCourse: numCourse,
      anchor: 'c$numCourse',
      nom: nom,
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

/// Alimente la mémoire par des voies PUBLIQUES uniquement.
Future<void> amorcer(IaMemoryService mem) async {
  await mem.enregistrerPronostic(
    courseKey: 'R1C1_2026-03-02',
    course: courseTest(1, 'Prix Concurrence'),
    partantsClasses: const <ZtPartant>[],
    confiancePredite: 70.0,
  );
  await mem.enregistrerParisPremiumDuJour(<String>['R1C1_2026-03-02']);
  await mem.enregistrerPronosticsPremiumDuJour(const <PremiumPronosticDuJour>[
    PremiumPronosticDuJour(
      courseKey: 'R1C1_2026-03-02',
      typePari: 'Quinté+',
      numeros: <String>['1', '2', '3', '4', '5'],
      sourceWidget: 'conseilJour',
    ),
  ]);
  await mem.sauvegarderSelectionWidgetPremiumDuJour(
    SelectionWidgetPremiumDuJour(
      dateKey: '2026-03-02',
      sourceWidget: 'conseilJour',
      courseKey: 'R1C1_2026-03-02',
      typePari: 'Quinté+',
      numeros: const <String>['1', '2', '3', '4', '5'],
      createdAt: DateTime(2026, 3, 2, 12),
    ),
  );
}

const String kPremiumDuJour = 'ia_premium_du_jour_v1';
const String kPremiumHistorique = 'ia_premium_historique_v1';
const String kWidgetsSelection = 'premium_widgets_selection_jour_v1';
const String kPoids = 'ia_poids_v3';
const String kPronostics = 'ia_pronostics_v2';
const String kArchiveManifest = 'ia_archive_v1_manifest';
const String kArchiveShard = 'ia_archive_v1_2026-03';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installerStore);
  tearDown(() {
    // Le hook de test B5c-P4 ne doit JAMAIS survivre à un test : un hook
    // laissé armé suspendrait toutes les écritures des fichiers de test
    // suivants (le service est un singleton de processus).
    IaMemoryService.instance.hookApresGetInstancePourTest = null;
    // Aucun test ne doit laisser une suspension armée derrière lui.
    store.toutLiberer();
    store.libererGetAllN();
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  V27-1 — scénario 2 : écriture DÉJÀ ENGAGÉE, suspendue DANS son action
  //
  //  Interleaving : l'écriture franchit les deux gardes, est enregistrée dans
  //  le registre, puis se suspend dans `prefs.setString()`. Le reset démarre.
  //
  //  Invariant : le drain attend cette écriture, donc AUCUNE suppression ne
  //  commence avant qu'elle soit terminée, donc sa clé ne peut pas survivre.
  //
  //  Observables DISCRIMINANTS (deux, indépendants) :
  //    1. ORDRE dans le journal : `SET-OK` doit précéder le premier `REM`.
  //    2. Clé réellement persistée : `premium_widgets_selection_jour_v1`
  //       absente du disque à la fin.
  //
  //  Tue la mutation qui retire l'enregistrement au registre (M14) : le drain
  //  ne voit plus l'écriture, efface d'abord, la clé réapparaît ensuite.
  // ══════════════════════════════════════════════════════════════════════════
  test('V27-1 — écriture engagée puis suspendue : drainée avant l\'effacement',
      () async {
    // La clé réellement écrite par l'opération choisie.
    const cleEcriture = kWidgetsSelection;

    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    await amorcer(mem);

    final entree = store.armerSuspensionSet(cleEcriture);

    final ecriture = mem.sauvegarderSelectionWidgetPremiumDuJour(
      SelectionWidgetPremiumDuJour(
        dateKey: '2026-03-09',
        sourceWidget: 'conseilJour',
        courseKey: 'R9C9_2026-03-09',
        typePari: 'Quinté+',
        numeros: const <String>['3', '7', '9'],
        createdAt: DateTime(2026, 3, 9, 12),
      ),
    );

    // ── TÉMOIN : l'écriture est réellement suspendue dans son action ──────
    final suspendue = await attendreEntreeOuFin(entree, ecriture);
    expect(suspendue, isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : l\'écriture doit être suspendue DANS '
            'setValue, donc déjà enregistrée dans le registre. Sinon le test '
            'ne prouve rien sur le drain');
    expect(mem.nbEcrituresEnCours, 1,
        reason: 'TÉMOIN : l\'écriture est bien dans le registre');

    // ── Le reset démarre pendant que l'écriture est suspendue ─────────────
    //    ⚠️ Frontière du journal : `_save()` de `amorcer()` effectue lui-même
    //       un `prefs.remove('ia_pronostics_v2_gz')` (branche compression).
    //       Sans frontière, on compterait CE remove comme un effacement du
    //       reset : l'assertion mesurerait la préparation, pas le drain.
    final indexDebutReset = store.journal.length;
    final reset = BackupService.instance.reinitialiserComplet();
    await laisserProgresser();

    // Invariant : tant que l'écriture n'est pas finie, rien n'est effacé.
    final remPendantSuspension = store.journal
        .skip(indexDebutReset)
        .where((e) => e.startsWith('REM '))
        .toList();
    debugPrint('V27-1 pendant suspension : remDuReset=$remPendantSuspension '
        'ecrituresEnCours=${mem.nbEcrituresEnCours}');
    expect(remPendantSuspension, isEmpty,
        reason: 'Le drain doit bloquer le reset AVANT toute suppression : '
            'aucune suppression DU RESET ne doit avoir eu lieu tant que '
            'l\'écriture est suspendue. (Mutation M14 : le drain ne voit rien '
            'et efface)');

    // ── Libération : l'écriture se termine, le reset peut effacer ─────────
    store.libererSet();
    await ecriture;
    await reset;

    // ── ASSERTION 1 : ordre réel des opérations sur le disque ─────────────
    // ⚠️ Le store reçoit la clé PRÉFIXÉE ('flutter.…') : on cherche donc par
    //    `startsWith` + `contains`, jamais par égalité sur la clé nue.
    final iSetOk = store.journal.asMap().entries
        .where((e) =>
            e.value.startsWith('SET-ENTREE') && e.value.contains(cleEcriture))
        .map((e) => e.key)
        .fold<int>(-1, (a, b) => a == -1 ? b : a);
    // Premier REM *postérieur au début du reset* (frontière identique).
    final iPremierRem = store.journal
        .asMap()
        .entries
        .where((e) => e.key >= indexDebutReset && e.value.startsWith('REM '))
        .map((e) => e.key)
        .fold<int>(-1, (a, b) => a == -1 ? b : a);
    debugPrint('V27-1 ordre : iSet=$iSetOk iPremierRemDuReset=$iPremierRem '
        'indexDebutReset=$indexDebutReset');
    expect(iSetOk, greaterThanOrEqualTo(0), reason: 'TÉMOIN : SET a eu lieu');
    expect(iPremierRem, greaterThanOrEqualTo(0),
        reason: 'TÉMOIN : l\'effacement a bien eu lieu');
    expect(iSetOk, lessThan(iPremierRem),
        reason: 'L\'écriture engagée doit être TRAITÉE AVANT le premier '
            'effacement : le drain l\'attend. Sinon la clé serait réécrite '
            'après l\'effacement et le reset serait annulé');

    // ── ASSERTION 2 : la clé ne survit pas sur le disque ──────────────────
    debugPrint('V27-1 disque : $cleEcriture présent=${store.contient(cleEcriture)}');
    expect(store.contient(cleEcriture), isFalse,
        reason: 'aucune écriture ancienne ne survit après un reset réussi');

    // ── ASSERTION 3 : registre revenu à zéro, barrière libérée ────────────
    expect(mem.nbEcrituresEnCours, 0, reason: 'aucun Future orphelin');
    final refuseesAvant = mem.nbEcrituresRefuseesParReset;
    await mem.enregistrerParisPremiumDuJour(<String>['R1C1_2026-03-10']);
    expect(mem.nbEcrituresRefuseesParReset, refuseesAvant,
        reason: 'barrière libérée après succès : une écriture peut renaître');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  V27-2 — scénario 3 : écriture suspendue DANS `getInstance()`
  //
  //  Interleaving : `enregistrerParisPremiumDuJour` franchit le contrôle 1
  //  PUIS se suspend sur `SharedPreferences.getInstance()`. Le reset démarre
  //  et incrémente la génération. L'écriture reprend et doit être REFUSÉE par
  //  le contrôle 2 (génération changée).
  //
  //  Observables : la clé cible n'est PAS écrite (absente du journal SET-OK,
  //  absente du disque) et le compteur de refus augmente.
  //
  //  Tue la mutation qui retire le contrôle 2 (M13).
  // ══════════════════════════════════════════════════════════════════════════
  test('V27-2 — écriture suspendue dans getInstance() : rejetée par génération',
      () async {
    const cleCible = kPremiumDuJour;

    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    await amorcer(mem);

    // Le cache est invalidé : la prochaine `getInstance()` repassera par le
    // store, donc par le verrou.
    SharedPreferences.resetStatic();
    final entree = store.armerSuspensionGetAll();
    // `armerSuspensionGetAll` rend une future d'entrée.

    final refuseesAvant = mem.nbEcrituresRefuseesParReset;
    // Frontière du journal : tout ce qui précède vient de la préparation.
    final indexJournalAvantArmement = store.journal.length;
    final ecriture =
        mem.enregistrerParisPremiumDuJour(<String>['R2C2_2026-03-11']);

    final suspendue = await attendreEntreeOuFin(entree, ecriture);
    expect(suspendue, isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : l\'écriture doit être suspendue dans '
            'getInstance(), donc APRÈS avoir franchi le contrôle 1');
    expect(mem.nbEcrituresEnCours, 0,
        reason: 'TÉMOIN : elle n\'est pas encore au registre (elle n\'a pas '
            'franchi le contrôle 2) — c\'est bien la fenêtre visée');

    // ── Le reset démarre : génération +1, barrière fermée ────────────────
    final reset = BackupService.instance.reinitialiserComplet();
    await laisserProgresser();

    // ── Libération : l'écriture reprend et doit être refusée ─────────────
    store.libererGetAll();
    await ecriture;
    await reset;

    debugPrint('V27-2 refusees=${mem.nbEcrituresRefuseesParReset} '
        '(avant=$refuseesAvant) '
        'setCible=${store.setAppeles.where((k) => k.contains(cleCible)).length} '
        'disque=${store.contient(cleCible)}');

    // ── Le refus doit être compté comme refus, pas comme erreur ──────────
    expect(mem.nbEcrituresRefuseesParReset, greaterThan(refuseesAvant),
        reason: 'C1/contrôle 2 : la génération a changé, l\'écriture doit '
            'être REFUSÉE (mutation M13 : elle passe et écrit)');

    // ── Aucune écriture effective sur la clé cible ───────────────────────
    //    ⚠️ On ne regarde QUE les entrées postérieures à l'armement : le
    //       journal contient déjà les SET produits par `amorcer()` et
    //       `init()`, qui ne disent rien de l'écriture testée.
    final ecrituresCible = store.journal
        .skip(indexJournalAvantArmement)
        .where((e) => e.startsWith('SET-ENTREE') && e.contains(cleCible))
        .toList();
    debugPrint('V27-2 journal SET sur la cible : $ecrituresCible');
    expect(ecrituresCible, isEmpty,
        reason: 'un refus sort AVANT l\'action : aucun setValue ne doit être '
            'tenté sur la clé cible');
    expect(store.contient(cleCible), isFalse,
        reason: 'la clé cible a bien été effacée et n\'a pas été réécrite');

    // ── Les refus restent distincts des erreurs réelles ──────────────────
    expect(store.pannes, isEmpty,
        reason: 'un refus n\'est pas une erreur : aucune panne déclenchée');
    expect(mem.nbEcrituresEnCours, 0, reason: 'registre vide');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  V27-3 — scénario 4 : un `_load()` DÉJÀ ENGAGÉ ne repeuple pas la RAM
  //            après le reset
  //
  //  Interleaving : `_load()` est suspendu dans `getInstance()`. Le reset
  //  démarre, doit ATTENDRE ce chargement (étape 3), puis vider la RAM
  //  (étape 4). Si l'attente manquait, le chargement se terminerait APRÈS le
  //  vidage et repeuplerait la RAM : les pronostics « ressusciteraient ».
  //
  //  Observables : `mem.pronostics` ET `mem.poids` après la fin des deux
  //  opérations. Les données poison sont sur le DISQUE, donc un rechargement
  //  les rendrait visibles.
  //
  //  Tue la mutation qui retire l'étape 3 (attente du chargement en vol).
  // ══════════════════════════════════════════════════════════════════════════
  test('V27-3 — chargement en vol : ne repeuple pas la RAM après le reset',
      () async {
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    await amorcer(mem);

    // Poison sur le disque : un pronostic RÉSOLU et des poids modifiés.
    // `recharger()` les lira si on le laisse faire.
    final pronosticPoison = IaPronostic(
      courseKey: 'R7C7_2026-03-12',
      nomCourse: 'Prix Poison',
      hippodrome: 'Vincennes',
      discipline: 'TROT_ATTELE',
      datePronostic: DateTime(2026, 3, 12, 14),
      scoresIA: const <String, double>{'1': 91.0, '2': 12.0},
      confiancePredite: 91.0,
      resultatsReels: true,
      arriveeReelle: const <int>[1, 2, 3],
    );
    store.semer(kPronostics, '[${jsonEncode(pronosticPoison.toJson())}]');
    store.semer(kPoids, jsonEncode((IaPoidsAdaptatifs.defaut()..forme = 0.77).toJson()));

    // `_load()` doit repasser par le store : cache invalidé.
    SharedPreferences.resetStatic();
    final entree = store.armerSuspensionGetAll();

    final chargement = mem.recharger();
    final suspendu = await attendreEntreeOuFin(entree, chargement);
    expect(suspendu, isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : le chargement doit être suspendu dans '
            'getInstance() pour que le reset le voie « en vol »');
    expect(mem.pronostics, isEmpty,
        reason: 'TÉMOIN : `recharger()` a déjà vidé la RAM avant de charger');

    // ── Le reset démarre et doit attendre ce chargement ──────────────────
    final reset = BackupService.instance.reinitialiserComplet();
    await laisserProgresser();

    // ── Libération : le chargement lit le poison, puis le reset continue ──
    store.libererGetAll();
    await chargement;
    await reset;

    debugPrint('V27-3 après : pronostics=${mem.pronostics.length} '
        'poids.forme=${mem.poids.forme} '
        'disquePronostics=${store.contient(kPronostics)}');

    // ── Le poison a bien été chargé à un moment donné (témoin) ───────────
    expect(store.getAllAppels, greaterThan(0),
        reason: 'TÉMOIN : le chargement a bien lu le disque');

    // ── ASSERTION : ni la RAM ni la vue métier ne gardent le poison ──────
    expect(mem.pronostics, isEmpty,
        reason: 'le chargement ne doit pas repeupler la RAM APRÈS le vidage : '
            'sans l\'attente de l\'étape 3, ces pronostics réapparaîtraient');
    expect(mem.poids.toJson(), IaPoidsAdaptatifs.defaut().toJson(),
        reason: 'les poids doivent rester aux valeurs d\'usine');

    // ── Le disque ne contient plus le poison non plus ────────────────────
    expect(store.contient(kPronostics), isFalse,
        reason: 'la clé poison a été effacée par le reset');

    // ── Barrières libérées ───────────────────────────────────────────────
    expect(mem.nbEcrituresEnCours, 0);
    final refuseesAvant = mem.nbEcrituresRefuseesParReset;
    await mem.enregistrerParisPremiumDuJour(<String>['R1C1_2026-03-13']);
    expect(mem.nbEcrituresRefuseesParReset, refuseesAvant,
        reason: 'barrière libérée : opérations nouvelles fonctionnelles');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  V27-4 — scénario 5 : aucun chargement NOUVEAU ne contourne la barrière
  //
  //  Interleaving : pendant le reset, `recharger()` est appelé. Le garde de
  //  `_load()` doit faire une sortie PURE : aucun accès disque, aucune
  //  mutation de `_loaded`, aucun `Completer`.
  //
  //  Observables : `store.getAllAppels` (aucun accès disque) ET la RAM (le
  //  poison reste non chargé — vérifié sur `mem.poids`, pas seulement sur le
  //  compteur d'appels, comme demandé).
  //
  //  Tue la mutation qui retire le garde `if (_resetEnCours) return;`.
  // ══════════════════════════════════════════════════════════════════════════
  test('V27-4 — aucun chargement nouveau pendant le reset (sortie pure)',
      () async {
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    await amorcer(mem);

    // Poison lisible sur le disque : si un chargement avait lieu, `forme`
    // passerait à 0.77 et serait observable via `mem.poids`.
    store.semer(kPoids, jsonEncode((IaPoidsAdaptatifs.defaut()..forme = 0.77).toJson()));

    int? getAllPendantReset;
    double? formePendantReset;

    await mem.executerResetComplet(() async {
      // Le cache est invalidé pour rendre tout accès disque VISIBLE : sans
      // cela `getInstance()` réutiliserait la future en cache et le garde
      // serait indiscernable d'une absence de garde.
      SharedPreferences.resetStatic();
      final avant = store.getAllAppels;

      // `recharger()` est le seul chemin public qui force `_loaded = false`
      // et appelle `_load()` : c'est exactement la fenêtre à tester.
      await mem.recharger();

      getAllPendantReset = store.getAllAppels - avant;
      formePendantReset = mem.poids.forme;
    });

    debugPrint('V27-4 getAll pendant reset=$getAllPendantReset '
        'forme pendant reset=$formePendantReset '
        'forme après reset=${mem.poids.forme}');

    // ── Aucun accès disque : le garde est une sortie pure ────────────────
    expect(getAllPendantReset, 0,
        reason: 'le garde doit sortir AVANT tout accès disque '
            '(mutation : sans lui, un getAll a lieu)');

    // ── Et la RAM n\'a pas été repeuplée par le poison ───────────────────
    expect(formePendantReset, IaPoidsAdaptatifs.defaut().forme,
        reason: 'aucun chargement n\'a eu lieu : `forme` n\'est pas passée '
            'à la valeur poison 0.77 — on contrôle l\'effet en RAM, pas '
            'seulement le nombre d\'appels');
    expect(formePendantReset, isNot(0.77),
        reason: 'témoin négatif explicite : la valeur poison ne doit jamais '
            'apparaître');

    // ── État final cohérent ──────────────────────────────────────────────
    expect(mem.pronostics, isEmpty);
    expect(mem.poids.toJson(), IaPoidsAdaptatifs.defaut().toJson());
    expect(mem.nbEcrituresEnCours, 0);
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  V27-5 — scénario 7 : les opérations APRÈS le reset fonctionnent
  //
  //  Invariant : barrières libérées, génération stabilisée, écritures réelles
  //  persistées (clé vérifiée sur le DISQUE), et non confondues avec un refus.
  //
  //  Tue la mutation qui supprime `_resetEnCours = false` du `finally`.
  // ══════════════════════════════════════════════════════════════════════════
  test('V27-5 — après le reset, les écritures sont réelles (disque vérifié)',
      () async {
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    await amorcer(mem);

    await BackupService.instance.reinitialiserComplet();

    final refuseesAvant = mem.nbEcrituresRefuseesParReset;
    final pannesAvant = store.pannes.length;

    // Deux écritures post-reset, sur des clés distinctes.
    await mem.enregistrerParisPremiumDuJour(<String>['R5C5_2026-03-14']);
    await mem.sauvegarderSelectionWidgetPremiumDuJour(
      SelectionWidgetPremiumDuJour(
        dateKey: '2026-03-14',
        sourceWidget: 'meilleurPari',
        courseKey: 'R5C5_2026-03-14',
        typePari: 'Couplé Gagnant',
        numeros: const <String>['4', '8'],
        createdAt: DateTime(2026, 3, 14, 11),
      ),
    );

    debugPrint('V27-5 après reset : refusees=${mem.nbEcrituresRefuseesParReset} '
        '(avant=$refuseesAvant) premiumDuJour=${store.contient(kPremiumDuJour)} '
        'widgets=${store.contient(kWidgetsSelection)}');

    // ── Aucun refus : la barrière est bien ouverte ───────────────────────
    expect(mem.nbEcrituresRefuseesParReset, refuseesAvant,
        reason: 'aucune écriture ne doit être refusée après le reset '
            '(mutation : `_resetEnCours` jamais remis à false)');

    // ── Les clés sont RÉELLEMENT sur le disque, pas seulement comptées ───
    expect(store.contient(kPremiumDuJour), isTrue,
        reason: 'l\'écriture post-reset doit être persistée');
    expect(store.contient(kWidgetsSelection), isTrue,
        reason: 'l\'écriture post-reset doit être persistée');
    expect(store.pannes.length, pannesAvant,
        reason: 'aucune erreur réelle : ce sont des écritures réussies');

    // ── La donnée est relisible par le chargement métier ─────────────────
    await mem.recharger();
    debugPrint('V27-5 rechargé : pronostics=${mem.pronostics.length}');
    expect(store.contient(kPremiumDuJour), isTrue);
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  V27-6 — scénario 8 : reset qui ÉCHOUE pendant la suppression des clés
  //
  //  Invariants : l'exception remonte, la barrière est libérée, le cache est
  //  resynchronisé sur le stockage réellement restant, les archives E3/E4
  //  survivent, et le registre revient à zéro.
  // ══════════════════════════════════════════════════════════════════════════
  test('V27-6 — échec pendant l\'effacement : barrières libérées, archives '
      'préservées', () async {
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    await amorcer(mem);

    // Archive E3/E4 : doit survivre à l'échec comme au succès.
    store
      ..semer(kArchiveManifest, '{"mois":["2026-03"]}')
      ..semer(kArchiveShard, '[]');

    store
      ..clesEnPanne.add(kPremiumHistorique)
      ..panneParException = false;

    Object? erreur;
    try {
      await BackupService.instance.reinitialiserComplet();
    } catch (e) {
      erreur = e;
    } finally {
      store.clesEnPanne.clear();
    }

    debugPrint('V27-6 erreur=$erreur archives=${store.clesArchive} '
        'enCours=${mem.nbEcrituresEnCours} '
        'refusees=${mem.nbEcrituresRefuseesParReset}');

    // ── L'échec est signalé ──────────────────────────────────────────────
    expect(erreur, isA<StateError>(),
        reason: 'un remove() refusé doit lever, pas être ignoré');
    expect('$erreur', contains(kPremiumHistorique),
        reason: 'le message doit nommer la clé survivante');

    // ── Archives préservées ──────────────────────────────────────────────
    expect(store.clesArchive, hasLength(2),
        reason: 'les archives E3/E4 ne font pas partie des 107 clés');

    // ── Barrières libérées malgré l'échec ────────────────────────────────
    expect(mem.nbEcrituresEnCours, 0, reason: 'registre drainé et vide');
    final refuseesAvant = mem.nbEcrituresRefuseesParReset;
    await mem.enregistrerParisPremiumDuJour(<String>['R6C6_2026-03-15']);
    expect(mem.nbEcrituresRefuseesParReset, refuseesAvant,
        reason: 'une opération nouvelle doit fonctionner après l\'échec : la '
            'barrière est libérée par le `finally`');

    // ── La RAM est aux valeurs d'usine (échec disque, pas RAM) ───────────
    expect(mem.pronostics, isEmpty);
    expect(mem.poids.toJson(), IaPoidsAdaptatifs.defaut().toJson());
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  V27-7 — scénario 9 : deux resets concurrents
  //
  //  Interleaving : deux `reinitialiserComplet()` lancés sans attendre le
  //  premier. Les deux traversent `AlertService` puis `IaMemoryService`.
  //
  //  Invariants : ni blocage, ni exception, ni corruption. État final = état
  //  de premier démarrage. Aucune écriture résiduelle.
  //
  //  Note honnête : le point d'entrée est le même depuis l'UI unique, donc ce
  //  scénario n'est atteignable que par double appel programmatique. Il est
  //  testé pour caractériser le comportement, pas pour prétendre à un usage
  //  réel.
  // ══════════════════════════════════════════════════════════════════════════
  test('V27-7 — deux resets concurrents : ni blocage ni corruption', () async {
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    await amorcer(mem);

    store
      ..semer(kArchiveManifest, '{"mois":["2026-03"]}')
      ..semer(kArchiveShard, '[]');

    Object? erreur1;
    Object? erreur2;

    final r1 = () async {
      try {
        await BackupService.instance.reinitialiserComplet();
      } catch (e) {
        erreur1 = e;
      }
    }();
    await laisserProgresser(4);
    final r2 = () async {
      try {
        await BackupService.instance.reinitialiserComplet();
      } catch (e) {
        erreur2 = e;
      }
    }();

    await Future.wait<void>([r1, r2]);

    debugPrint('V27-7 erreur1=$erreur1 erreur2=$erreur2 '
        'pronostics=${mem.pronostics.length} '
        'poidsUsine=${jsonEncode(mem.poids.toJson()) == jsonEncode(IaPoidsAdaptatifs.defaut().toJson())} '
        'enCours=${mem.nbEcrituresEnCours} archives=${store.clesArchive}');

    // ── Aucune corruption : état final déterministe ──────────────────────
    expect(mem.pronostics, isEmpty, reason: 'RAM vide après les deux resets');
    expect(mem.poids.toJson(), IaPoidsAdaptatifs.defaut().toJson(),
        reason: 'poids aux valeurs d\'usine, pas dans un état intermédiaire');
    expect(mem.nbEcrituresEnCours, 0, reason: 'aucun Future orphelin');
    expect(store.contient(kPremiumDuJour), isFalse,
        reason: 'aucune clé réécrite entre les deux effacements');
    expect(store.contient(kPremiumHistorique), isFalse);
    expect(store.contient(kWidgetsSelection), isFalse);

    // ── Les archives survivent aux deux passes ───────────────────────────
    expect(store.clesArchive, hasLength(2),
        reason: 'les archives E3/E4 restent préservées');

    // ── Au moins un des deux resets a abouti, sans exception ─────────────
    expect(erreur1, isNull,
        reason: 'le premier reset concurrent doit aboutir');
    debugPrint('V27-7 erreur2 (2e reset concurrent) = $erreur2');

    // ── Le service reste utilisable ──────────────────────────────────────
    final refuseesAvant = mem.nbEcrituresRefuseesParReset;
    await mem.enregistrerParisPremiumDuJour(<String>['R7C7_2026-03-16']);
    expect(mem.nbEcrituresRefuseesParReset, refuseesAvant,
        reason: 'barrière ouverte après les deux resets');
    expect(store.contient(kPremiumDuJour), isTrue,
        reason: 'écriture post-concurrence persistée');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  V27-8 — scénario 3bis : la GÉNÉRATION est le SEUL rempart restant
  //
  //  Interleaving (A→G), rendu possible par le hook de test B5c-P4 :
  //    A. l'écriture franchit le contrôle 1 et capture la génération N ;
  //    B. `SharedPreferences.getInstance()` se termine ;
  //    C. le hook suspend UNIQUEMENT cette écriture, avant le contrôle 2 ;
  //    D. le reset complet s'exécute ENTIÈREMENT ;
  //    E. `_resetEnCours` est retombé à `false`, `_generationCache` a changé ;
  //    F. le hook libère l'écriture ;
  //    G. le contrôle 2 la REFUSE — le contrôle 1 ne peut plus rien, puisque
  //       le reset est fini.
  //
  //  Pourquoi ce test est nécessaire : dans V27-2 le reset est encore EN
  //  COURS au réveil de l'écriture, donc le contrôle 1 suffit à produire le
  //  refus. Ce partage de responsabilité rend l'incrément de génération
  //  indétectable (mutation M15 survivante). V27-8 isole la génération.
  //
  //  Pourquoi le hook est indispensable : dans le code de production, la
  //  fenêtre entre la capture de génération et le contrôle 2 ne contient
  //  AUCUN `await` (invariant P1). Elle est donc inobservable, et toute
  //  suspension placée dans `getInstance()` est partagée avec le reset via
  //  `SharedPreferences._completer` — ce qui interbloque. Le hook est le SEUL
  //  point de suspension privé, non partagé, placé dans cette fenêtre.
  //
  //  Observation : `nbEcrituresRefuseesParReset` ne peut PAS servir d'
  //  observable principal — le reset lui-même pourrait le faire bouger. On
  //  observe donc d'abord le DISQUE (la clé cible), puis le journal.
  // ══════════════════════════════════════════════════════════════════════════
  test('V27-8 — génération seule : écriture réveillée APRÈS la fin du reset',
      () async {
    const cleCible = kPremiumDuJour;

    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    await amorcer(mem);

    // ── TÉMOIN DE PRODUCTION : le hook est nul par défaut ────────────────
    expect(mem.hookApresGetInstancePourTest, isNull,
        reason: 'TÉMOIN : le hook doit être nul hors test — le chemin nominal '
            'ne doit comporter aucune suspension supplémentaire');
    expect(store.contient(cleCible), isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : la clé cible existe AVANT le test, '
            'sinon sa « réapparition » ne voudrait rien dire');

    // `getInstance()` doit repasser par le store : c'est ce qui rend
    // OBSERVABLE le fait que la suspension se produit APRÈS sa résolution.
    SharedPreferences.resetStatic();
    final indexAvantEcriture = store.journal.length;
    final getAllAvantEcriture = store.getAllAppels;

    // ── B/C : armement du hook — suspension ENTRE getInstance() et contrôle 2
    final entree = Completer<void>();
    final verrou = Completer<void>();
    var appelsHook = 0;
    int? getAllAuMomentDuHook;
    mem.hookApresGetInstancePourTest = () async {
      appelsHook++;
      // Seule la PREMIÈRE écriture est suspendue : les suivantes traversent.
      if (appelsHook == 1) {
        getAllAuMomentDuHook = store.getAllAppels;
        if (!entree.isCompleted) entree.complete();
        await verrou.future;
      }
    };

    // A : contrôle 1 franchi (aucun reset en cours), génération capturée.
    final ecriture =
        mem.enregistrerParisPremiumDuJour(<String>['R8C8_2026-03-17']);

    // ── TÉMOIN : l'écriture est suspendue DANS le hook ───────────────────
    final suspendue = await attendreEntreeOuFin(entree, ecriture);
    expect(suspendue, isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : l\'écriture doit atteindre le hook '
            'et y rester suspendue, sinon le test ne prouve rien');
    expect(appelsHook, 1, reason: 'TÉMOIN : le hook a été atteint une fois');

    // ── B : preuve que `getInstance()` s'est TERMINÉ avant le hook ────────
    //    Il a déclenché un accès disque, DÉJÀ comptabilisé au moment du hook.
    expect(getAllAuMomentDuHook, isNotNull);
    expect(getAllAuMomentDuHook!, greaterThan(getAllAvantEcriture),
        reason: 'TÉMOIN : `SharedPreferences.getInstance()` a bien lu le '
            'disque AVANT le hook — le reset, lui, réutilisera cette future');

    // L'écriture n'est PAS encore au registre : elle n'a pas franchi le
    // contrôle 2, donc le drain du reset ne peut pas l'attendre.
    expect(mem.nbEcrituresEnCours, 0,
        reason: 'TÉMOIN : l\'écriture est dans la fenêtre, pas au registre');

    // ── D : le reset s'exécute ENTIÈREMENT pendant la suspension ──────────
    final refusAvant = mem.nbEcrituresRefuseesParReset;
    await BackupService.instance.reinitialiserComplet();

    debugPrint('V27-8 reset terminal — pronostics=${mem.pronostics.length} '
        'enCours=${mem.nbEcrituresEnCours} '
        'disqueCible=${store.contient(cleCible)}');

    // ── E : le reset est VRAIMENT fini avant toute reprise ────────────────
    //    Preuve structurelle : `reinitialiserComplet()` attend les DEUX
    //    barrières, et `_resetEnCours` n'est remis à `false` que dans le
    //    `finally` d'`executerResetComplet()`. Ce `await` étant terminé,
    //    `_resetEnCours` vaut nécessairement `false` à partir d'ici — le
    //    contrôle 1 est donc hors jeu pour la suite.
    expect(mem.nbEcrituresEnCours, 0, reason: 'registre vide');
    expect(store.contient(cleCible), isFalse,
        reason: 'TÉMOIN : l\'effacement disque a bien eu lieu');
    expect(mem.pronostics, isEmpty,
        reason: 'TÉMOIN : la RAM a bien été vidée par le reset');
    expect(mem.poids.toJson(), IaPoidsAdaptatifs.defaut().toJson(),
        reason: 'TÉMOIN : les poids sont revenus aux valeurs d\'usine');

    // ── F : réveil de l'écriture (plus aucun reset en cours) ──────────────
    verrou.complete();
    await ecriture;

    final journalDepuisEcriture =
        store.journal.skip(indexAvantEcriture).toList();
    debugPrint('V27-8 journal depuis l\'écriture = $journalDepuisEcriture');
    debugPrint('V27-8 refusees=${mem.nbEcrituresRefuseesParReset} '
        '(avant=$refusAvant) '
        'deltaRefus=${mem.nbEcrituresRefuseesParReset - refusAvant} '
        'disqueCible=${store.contient(cleCible)}');

    // ── G — ASSERTION DISCRIMINANTE 1 (DISQUE) : aucune réapparition ──────
    //    Sous M15 (génération non incrémentée), `_resetEnCours` est déjà
    //    `false` au réveil et la génération est inchangée : le contrôle 2
    //    laisse passer, `setValue` réécrit la clé effacée, et CETTE assertion
    //    échoue sur la réapparition elle-même.
    expect(store.contient(cleCible), isFalse,
        reason: 'MUTATION M15 : sans incrément de génération, l\'écriture '
            'réveillée APRÈS la fin du reset RÉÉCRIT la clé effacée — elle '
            'réapparaît sur le disque');

    // ── ASSERTION DISCRIMINANTE 2 (journal) : aucune tentative d'écriture ─
    final tentatives = journalDepuisEcriture
        .where((e) => e.startsWith('SET-ENTREE') && e.contains(cleCible))
        .toList();
    expect(tentatives, isEmpty,
        reason: 'un refus sort AVANT l\'action : aucun `setValue` ne doit '
            'avoir été tenté sur la clé cible');

    // ── ASSERTION 3 : le refus est un refus de la barrière, pas une erreur ─
    expect(mem.nbEcrituresRefuseesParReset, greaterThan(refusAvant),
        reason: 'l\'écriture doit être REFUSÉE par le contrôle de génération');

    // ── ASSERTION 4 : aucun Future orphelin, aucune erreur réelle ─────────
    expect(mem.nbEcrituresEnCours, 0, reason: 'aucun Future orphelin');
    expect(store.pannes, isEmpty,
        reason: 'un refus n\'est pas une erreur : aucune panne déclenchée');

    // ── ASSERTION 5 : barrière libérée, le service reste utilisable ───────
    await mem.enregistrerParisPremiumDuJour(<String>['R8C9_2026-03-18']);
    debugPrint('V27-8 après écriture post-refus : '
        'disqueCible=${store.contient(cleCible)}');
    expect(store.contient(cleCible), isTrue,
        reason: 'une écriture POSTÉRIEURE doit réussir : la barrière est '
            'ouverte et la génération est stabilisée');
  });
}
