// ═══════════════════════════════════════════════════════════════════════════
//  B5c — ÉTAPE 7 / R-DR-05 : EloService face au reset complet
//
//  OBJET DE CES TESTS : ÉTABLIR LES FAITS, PAS PROPOSER UN CORRECTIF.
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION N'EST REQUISE POUR LES EXÉCUTER.
//
//  État statique constaté avant écriture de ces tests (grep sur
//  lib/services/elo_service.dart, 314 lignes) :
//    • 0 occurrence de `_resetEnCours`
//    • 0 occurrence de `_generation`
//    • 0 occurrence de `_ecrituresEnCours`
//    • 0 occurrence d'un registre de drain
//  → EloService est le SEUL service inscripteur restant SANS aucune barrière.
//
//  Les trois sites d'écriture disque :
//    • `_sauvegarder()` l.116-126 — `setString('elo_ratings_v2')` puis
//      `setInt('elo_ratings_v2_ts')` ;
//    • `_charger()` l.82   — `remove('elo_ratings_v1')` (migration) ;
//    • `_charger()` l.104  — `setBool('elo_orphelins_purges_v1')`, suivi
//      éventuellement de `_sauvegarder()` l.107.
//
//  Position des clés dans `BackupService._toutesLesCles` : index 13, 14, 15
//  (sur 107) → effacées TRÈS TÔT dans la boucle. La vidange RAM
//  (`viderMemoirePourResetComplet`, l.310) a lieu APRÈS la fermeture de la
//  barrière, donc APRÈS TOUTES les suppressions.
//
//  ⚠️ PORTÉE EXPLICITE : ces tests prouvent des observations ciblées sur
//     `EloService` et sur l'ordre du reset. Ils ne prouvent PAS que
//     `DataRefreshService` atteint cet état en production — cela dépend du
//     calendrier réseau (`_mettreAJourEloApresArrivee` est appelé en
//     `.ignore()` depuis data_refresh_service.dart:946) et du moment où
//     l'utilisateur appuie sur « Réinitialiser ».
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';


import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Store instrumenté : verrou par clé, journal, lecture directe.
//  Copie volontaire du dispositif validé en V28 (aucune factorisation : les
//  fichiers de test B5c restent autonomes et lisibles isolément).
// ───────────────────────────────────────────────────────────────────────────
class _StoreControle extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  Completer<void>? _verrouSet;
  String? _cleSuspendue;
  Completer<void>? _entreeSet;

  Completer<void>? _verrouRemove;
  String? _cleRemoveSuspendue;
  Completer<void>? _entreeRemove;

  // Verrou sur getAllWithParameters — SEUL moyen de suspendre un appelant
  // À L'INTÉRIEUR de `SharedPreferences.getInstance()`.
  Completer<void>? _verrouGetAll;
  Completer<void>? _entreeGetAll;

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

  Completer<void> armerSuspensionGetAll() {
    final entree = Completer<void>();
    _entreeGetAll = entree;
    _verrouGetAll = Completer<void>();
    return entree;
  }

  void libererGetAll() {
    final v = _verrouGetAll;
    _verrouGetAll = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void desarmer() {
    _cleSuspendue = null;
    _verrouSet = null;
    _entreeSet = null;
    _cleRemoveSuspendue = null;
    _verrouRemove = null;
    _entreeRemove = null;
    _verrouGetAll = null;
    _entreeGetAll = null;
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  /// Effacement direct, utilisé par la clôture de suppression du test G.
  /// Journalisé « REM » pour rester cohérent avec le reste du dispositif.
  void effacerDirect(String cle) {
    journal.add('REM flutter.$cle');
    _valeurs.remove('flutter.$cle');
  }

  int get nbRem => journal.where((e) => e.startsWith('REM ')).length;
}

// ignore: library_private_types_in_public_api
late _StoreControle store;

void _installerStore() {
  store = _StoreControle();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

/// Vidage BORNÉ de la boucle d'événements. Aucune assertion ne repose sur une
/// durée : les observables sont le journal, l'état du store et les ratings.
Future<void> _laisserProgresser([int tours = 24]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Avance jusqu'à ce que [condition] soit vraie, ou épuisement du budget.
/// Retourne `true` si la condition a été observée. DÉTERMINISTE : aucune durée.
Future<bool> _attendreQue(bool Function() condition, [int maxTours = 600]) async {
  for (var i = 0; i < maxTours; i++) {
    if (condition()) return true;
    await Future<void>.delayed(Duration.zero);
  }
  return condition();
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

// ── Constructeurs ──────────────────────────────────────────────────────────

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
    );

/// Discipline réellement utilisée par DataRefreshService
/// (`course.type` de la course, l.940-949). `normaliserDiscipline` la
/// convertit en `TROT_ATTELE`.
const String kDiscipline = 'Trot Attelé';

/// Reproduit `EloService._cle` (l.147-148) — sert à fabriquer des clés
/// attendues, JAMAIS à modifier le service.
String kCleElo(String nom, [String discipline = kDiscipline]) {
  final nomNorm = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  return '$nomNorm|${EloService.normaliserDiscipline(discipline)}';
}

const String kEloKey = 'elo_ratings_v2';

/// ★ A7 (3.3-B2-e) — IDENTITÉ DE COURSE DES APPELS DE CE FICHIER.
///
/// Depuis B2-e (§6), une application ELO sans identité exploitable est REFUSÉE
/// (`identiteNonExploitable`). Ces tests mesurent la PERSISTANCE et la
/// PROTECTION DE RESET (`persistee`, `refusee`, `abandonneeParReset`, drain,
/// non-résurrection) : sans identité, ils n'atteignaient plus le code testé.
/// La clé est RÉELLE, calendairement valide et ANCRÉE DANS LE PASSÉ.
///
/// ⚠️ IDENTIQUE pour tous les appels d'un même test : aucun scénario de ce
///    fichier ne représente DEUX courses distinctes, et plusieurs tests
///    enchaînent volontairement des appels sur LA MÊME course (cumul, rejeu).
///    Chaque test dispose d'un store neuf (setUp), donc aucune collision
///    entre tests n'est possible.
const String kCleCourseV29 = 'R1C1_01112026';

/// ★ B2-e — identité de la SECONDE course du test G.
///
/// Le test G applique DEUX courses logiquement différentes :
///   1. une course de PEUPLEMENT (état de départ : RAM et disque peuplés) ;
///   2. une course NOUVELLE, née AVANT le reset et dont l'écriture atteint le
///      disque APRÈS — c'est CETTE opération que le contrôle de génération
///      doit refuser.
///
/// Réutiliser l'identité de la course de peuplement ferait refuser la seconde
/// dès l'étape A.4 (`courseDejaJournalisee`) : elle n'atteindrait jamais
/// `_sauvegarder()`, `deltaGen` resterait à 0, et le test mesurerait un refus
/// de doublon au lieu du contrôle 2 qu'il a pour objet de vérifier.
/// Deux courses différentes ⇒ deux identités différentes. Date dans le PASSÉ.
const String kCleCourseV29G = 'R2C2_02112026';
const String kEloTsKey = 'elo_ratings_v2_ts';
const String kCleTardive = 'alert_config_v2'; // index 86 sur 107

/// Arrivée de 3 chevaux sur 6 partants → 2 mises à jour minimum (paires).
final List<ZtPartant> kPartants =
    List.generate(6, (i) => _partant(i + 1));
const List<int> kArrivee = <int>[1, 2, 3];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _installerStore();
    // `_charge` est un état privé SANS getter : on le stabilise à `true` pour
    // tout le fichier via `init()`, puis on vide la RAM sans écrire sur le
    // disque. Sans cela, `_charge` dépendrait de l'ordre d'exécution des tests.
    await EloService.init();
    EloService.instance.viderMemoirePourResetComplet();
  });

  tearDown(() {
    store.desarmer();
    store.libererSet();
    store.libererGetAll();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V29-0 — TÉMOIN ABSOLU
  //
  //  Sans lui, « la clé est absente après reset » ne prouverait rien : elle
  //  pourrait manquer simplement parce que la mise à jour ELO n'écrit jamais.
  // ═══════════════════════════════════════════════════════════════════════
  test('V29-0 — TÉMOIN : la mise à jour ELO écrit en RAM et sur le disque',
      () async {
    final elo = EloService.instance;

    expect(elo.nbChevauxSuivis, 0, reason: 'TÉMOIN : RAM vide au départ');
    expect(store.contient(kEloKey), isFalse,
        reason: 'TÉMOIN : disque vide au départ');

    await elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
      courseKey: kCleCourseV29, // ★ B2-e : identité exigée
    );

    debugPrint('V29-0 → nbChevauxSuivis=${elo.nbChevauxSuivis} '
        'disque=${store.contient(kEloKey)} '
        'ts=${store.contient(kEloTsKey)} '
        'rating1=${elo.getRating('CHEVAL_1', discipline: kDiscipline)}');

    expect(elo.nbChevauxSuivis, greaterThan(0),
        reason: 'TÉMOIN : des ratings existent en RAM');
    expect(store.contient(kEloKey), isTrue,
        reason: 'TÉMOIN : la clé elo_ratings_v2 est écrite — sinon une clé '
            'absente après reset ne prouverait rien');
    expect(store.contient(kEloTsKey), isTrue,
        reason: 'TÉMOIN : la seconde écriture de `_sauvegarder()` a lieu aussi');

    // Un cheval de l'arrivée voit son rating BOUGER depuis le défaut : preuve
    // que le calcul a réellement tourné (aucune formule n'est vérifiée ici).
    final r1 = elo.getRating('CHEVAL_1', discipline: kDiscipline);
    expect(r1, isNot(1500.0),
        reason: 'TÉMOIN : le gagnant gagne des points — le calcul a tourné');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  SCÉNARIO A — mise à jour ELO suspendue DANS `_sauvegarder()`, le reset
  //  laisse passer la suppression de la clé, PUIS l'écriture se termine.
  //
  //    A1. `mettreAJourApresArrivee` calcule les deltas (synchrone) ;
  //    A2. `_sauvegarder()` entre dans `setString('elo_ratings_v2')` et s'y
  //        SUSPEND (verrou du store) ;
  //    A3. le reset démarre et parcourt ses 107 suppressions, dont la clé
  //        ELO (index 13) ;
  //    A4. on libère le verrou : l'écriture suspendue se termine APRÈS la
  //        suppression ;
  //    A5. mesure : la clé effacée est-elle recréée ?
  // ═══════════════════════════════════════════════════════════════════════
  test('V29-A — écriture ELO suspendue, terminée APRÈS la suppression de la clé',
      () async {
    final elo = EloService.instance;

    final entree = store.armerSuspensionSet(kEloKey);
    final maj = elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
      courseKey: kCleCourseV29, // ★ B2-e : identité exigée
    );

    final suspendue = await _attendreEntreeOuFin(entree, maj);
    expect(suspendue, isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : la mise à jour doit être suspendue '
            'DANS `_sauvegarder()`, donc après avoir calculé ses deltas en RAM');

    // TÉMOIN : la RAM contient déjà les nouveaux ratings, le disque pas encore.
    final nbAvantReset = elo.nbChevauxSuivis;
    debugPrint('V29-A avant reset : RAM=$nbAvantReset '
        'disque=${store.contient(kEloKey)} '
        'journal=${store.journal.where((e) => e.contains(kEloKey)).toList()}');

    expect(nbAvantReset, greaterThan(0),
        reason: 'TÉMOIN : les ratings sont déjà appliqués en RAM pendant que '
            'l\'écriture disque est suspendue');
    expect(store.contient(kEloKey), isFalse,
        reason: 'TÉMOIN : le disque ne contient pas encore la clé');

    // ── A3 : reset lancé SANS être attendu ───────────────────────────────
    //    AVEC LE DRAIN, le reset est RETENU dans son étape 2 tant que
    //    l'écriture engagée n'est pas terminée : aucune suppression ne doit
    //    donc apparaître ici. Le `REM` observé plus bas vient forcément
    //    d'APRÈS la libération.
    final indexDebutReset = store.journal.length;
    final reset = BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();
    final remPendantSuspension =
        store.journal.skip(indexDebutReset).where((e) => e.startsWith('REM '));
    debugPrint('V29-A drain : remPendantSuspension=${remPendantSuspension.length} '
        'enCours=${elo.nbEcrituresEnCours}');

    expect(remPendantSuspension, isEmpty,
        reason: 'PREUVE DU DRAIN : le reset n\'a exécuté AUCUNE suppression '
            'tant que l\'écriture engagée n\'était pas terminée');
    expect(elo.nbEcrituresEnCours, 1,
        reason: 'TÉMOIN : l\'écriture est au registre, c\'est elle que le '
            'drain attend');

    // ── A4 : on libère → l'écriture suspendue se termine MAINTENANT ───────
    final refusParResetAvant = elo.nbRefusParReset;
    final refusParGenAvant = elo.nbRefusParGeneration;
    store.libererSet();
    await maj;
    await reset;

    final ramApres = elo.nbChevauxSuivis;
    final disqueApres = store.contient(kEloKey);
    final deltaReset = elo.nbRefusParReset - refusParResetAvant;
    final deltaGen = elo.nbRefusParGeneration - refusParGenAvant;
    debugPrint('V29-A après : RAM=$ramApres disque=$disqueApres '
        'ts=${store.contient(kEloTsKey)} '
        'deltaReset=$deltaReset deltaGen=$deltaGen '
        'enCours=${elo.nbEcrituresEnCours}');

    // ── CORRECTION R-DR-05 ───────────────────────────────────────────────
    // Le vidage RAM est dans le `finally` du reset : il a bien lieu.
    expect(ramApres, 0,
        reason: 'CORRECTION : le vidage RAM du reset a bien eu lieu');

    // La clé supprimée N'EST PLUS recréée : le DRAIN a laissé l'écriture
    // engagée se terminer AVANT la première suppression.
    expect(disqueApres, isFalse,
        reason: 'CORRECTION : l\'écriture ELO engagée avant le reset est '
            'drainée AVANT l\'effacement — elle ne peut plus recréer '
            '`elo_ratings_v2` après sa suppression (scénario A)');
    expect(store.contient(kEloTsKey), isFalse,
        reason: 'CORRECTION : la seconde écriture de `_sauvegarder()` '
            '(`elo_ratings_v2_ts`) est également absente');

    // PROTECTION RÉELLEMENT RESPONSABLE : le DRAIN, pas les contrôles.
    // L'écriture avait franchi les deux contrôles avant de se suspendre ;
    // elle n'a donc été ni refusée par le contrôle 1, ni par le contrôle 2.
    expect(deltaReset, 0,
        reason: 'FAIT MESURÉ : une écriture déjà ENGAGÉE n\'est jamais '
            'refusée — elle a franchi les deux contrôles. Le contrôle 1 n\'est '
            'donc PAS la protection du scénario A');
    expect(deltaGen, 0,
        reason: 'FAIT MESURÉ : et le contrôle 2 (génération) ne la refuse pas '
            'davantage — c\'est le DRAIN qui protège, en la faisant aboutir '
            'AVANT l\'effacement');

    // Preuve de l'ordre : le SET de l'écriture drainée précède le REM du reset.
    final journalReset = store.journal.skip(indexDebutReset).toList();
    final iPremierRem = journalReset.indexWhere((e) => e.startsWith('REM '));
    final iPremierSetOk =
        journalReset.indexWhere((e) => e.startsWith('SET-OK'));
    debugPrint('V29-A ordre : iPremierSetOk=$iPremierSetOk '
        'iPremierRem=$iPremierRem');
    expect(iPremierSetOk, greaterThanOrEqualTo(0),
        reason: 'TÉMOIN : l\'écriture drainée a bien fini par écrire');
    expect(iPremierSetOk, lessThan(iPremierRem),
        reason: 'PREUVE DU DRAIN : l\'écriture engagée se termine AVANT la '
            'première suppression — c\'est cela qui rend le scénario A sûr');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  SCÉNARIO B — mise à jour ELO démarrée AVANT le reset et terminée APRÈS
  //  la fin complète de celui-ci.
  //
  //  C'est le cas que le vidage RAM (`viderMemoirePourResetComplet`) ne peut
  //  PAS couvrir : il a lieu une fois, à un instant donné. Une écriture qui
  //  se termine plus tard écrit APRÈS lui.
  // ═══════════════════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════════════════
  //  SCÉNARIO B — l'écriture était suspendue quand le reset démarre.
  //
  //  AVANT R-DR-05, on pouvait attendre la fin complète du reset PUIS libérer,
  //  et la clé était réécrite : c'était la fenêtre B.
  //
  //  AVEC LE DRAIN, cette manœuvre N'EST PLUS POSSIBLE : le reset se BLOQUE
  //  dans son étape 2 tant que l'écriture engagée n'est pas terminée. Le test
  //  mesure ce blocage — c'est la preuve directe que la fenêtre B est fermée
  //  PAR CONSTRUCTION et non par chance de calendrier.
  // ═══════════════════════════════════════════════════════════════════════
  test('V29-B — le DRAIN retient le reset jusqu\'à la fin de l\'écriture engagée',
      () async {
    final elo = EloService.instance;

    final entree = store.armerSuspensionSet(kEloKey);
    final maj = elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
      courseKey: kCleCourseV29, // ★ B2-e : identité exigée
    );
    final suspendue = await _attendreEntreeOuFin(entree, maj);
    expect(suspendue, isTrue, reason: 'TÉMOIN DE PRÉPARATION');
    expect(elo.nbEcrituresEnCours, 1,
        reason: 'TÉMOIN : l\'écriture est au registre, le drain la verra');

    // ── Reset lancé SANS être attendu ────────────────────────────────────
    var resetTermine = false;
    final reset = BackupService.instance.reinitialiserComplet();
    reset.whenComplete(() => resetTermine = true).ignore();

    // ── PREUVE DU DRAIN : le reset n'aboutit pas tant que l'écriture vit ──
    await _laisserProgresser();
    final effacementCommence =
        store.journal.any((e) => e.startsWith('REM '));
    debugPrint('V29-B reset bloqué : termine=$resetTermine '
        'effacementCommence=$effacementCommence '
        'enCours=${elo.nbEcrituresEnCours}');

    expect(resetTermine, isFalse,
        reason: 'PREUVE DU DRAIN : le reset est RETENU dans son étape 2 — '
            'il attend l\'écriture engagée');
    expect(effacementCommence, isFalse,
        reason: 'PREUVE DU DRAIN : aucune suppression n\'a commencé, donc '
            'aucune clé ne peut être recréée après coup — la fenêtre du '
            'scénario B n\'existe plus');
    expect(elo.nbEcrituresEnCours, 1,
        reason: 'TÉMOIN : l\'écriture est toujours en vol, le registre la '
            'retient');

    // ── Libération : l'écriture s'achève, ALORS le reset efface ───────────
    store.libererSet();
    await maj;
    await reset;

    final ramApres = elo.nbChevauxSuivis;
    final disqueApres = store.contient(kEloKey);
    debugPrint('V29-B après : RAM=$ramApres disque=$disqueApres '
        'ts=${store.contient(kEloTsKey)} '
        'enCours=${elo.nbEcrituresEnCours}');

    expect(ramApres, 0, reason: 'CORRECTION : RAM vidée par le `finally`');
    expect(disqueApres, isFalse,
        reason: 'CORRECTION : la clé n\'existe plus sur le disque — elle a été '
            'écrite par l\'écriture drainée, PUIS supprimée par le reset');
    expect(store.contient(kEloTsKey), isFalse,
        reason: 'CORRECTION : idem pour le timestamp');
    expect(elo.nbEcrituresEnCours, 0, reason: 'registre drainé');

    // ── Ordre : l'écriture drainée AVANT la première suppression ─────────
    final iPremierRem = store.journal.indexWhere((e) => e.startsWith('REM '));
    final iDernierSetOk =
        store.journal.lastIndexWhere((e) => e.startsWith('SET-OK'));
    debugPrint('V29-B ordre : iDernierSetOk=$iDernierSetOk '
        'iPremierRem=$iPremierRem');
    expect(iDernierSetOk, greaterThanOrEqualTo(0),
        reason: 'TÉMOIN : l\'écriture drainée a bien écrit');
    expect(iDernierSetOk, lessThan(iPremierRem),
        reason: 'PREUVE DE L\'ORDRE : drain complet AVANT tout effacement');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  C — ÉTAT DE `_charge` APRÈS LE RESET ET EFFET SUR LES LECTURES
  //
  //  `_charge` n'a AUCUN getter : il n'est donc pas directement observable.
  //  On l'observe par son SEUL effet mesurable — `mettreAJourApresArrivee`
  //  commence par `if (!_charge) await _charger()`. Si `_charge` valait
  //  `false`, `_charger()` relirait le disque et IMPORTERAIT ce qu'il y
  //  trouve ; s'il vaut `true`, elle ne lit rien.
  //
  //  Dispositif : après le reset, on sème sur le disque un rating MARQUEUR
  //  (situation d'une suppression refusée par le stockage, cf. C1-a), puis on
  //  lance une mise à jour et on regarde si le marqueur est importé.
  // ═══════════════════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════════════════
  //  C — `_charge` APRÈS UN RESET RÉUSSI, ET MISE À JOUR NORMALE ENSUITE
  //
  //  Deux exigences de la validation :
  //    • cohérence RAM/disque après un reset réussi ;
  //    • une mise à jour ELO NORMALE fonctionne après ce reset.
  //
  //  `_charge` n'a pas de getter : on l'observe par son seul effet mesurable.
  // ═══════════════════════════════════════════════════════════════════════
  test('C — après reset réussi : cohérence RAM/disque et mise à jour normale',
      () async {
    final elo = EloService.instance;

    // ── Reset réussi, sur un état ELO préalablement peuplé ───────────────
    await elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
      courseKey: kCleCourseV29, // ★ B2-e : identité exigée
    );
    expect(elo.nbChevauxSuivis, greaterThan(0), reason: 'TÉMOIN : RAM peuplée');
    expect(store.contient(kEloKey), isTrue, reason: 'TÉMOIN : disque peuplé');

    Object? erreur;
    try {
      await BackupService.instance.reinitialiserComplet();
    } catch (e) {
      erreur = e;
    }

    debugPrint('C → reset : erreur=$erreur RAM=${elo.nbChevauxSuivis} '
        'disque=${store.contient(kEloKey)} ts=${store.contient(kEloTsKey)}');

    // ── COHÉRENCE RAM/DISQUE après reset réussi ──────────────────────────
    expect(erreur, isNull, reason: 'TÉMOIN : reset sans erreur');
    expect(elo.nbChevauxSuivis, 0, reason: 'CORRECTION : RAM vide');
    expect(store.contient(kEloKey), isFalse,
        reason: 'CORRECTION : disque vide — RAM et disque sont COHÉRENTS');
    expect(store.contient(kEloTsKey), isFalse, reason: 'CORRECTION : idem ts');

    // ── Une mise à jour ELO NORMALE fonctionne après le reset ────────────
    await elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
      courseKey: kCleCourseV29, // ★ B2-e : identité exigée
    );
    debugPrint('C → maj après reset : RAM=${elo.nbChevauxSuivis} '
        'disque=${store.contient(kEloKey)} '
        'rating1=${elo.getRating('CHEVAL_1', discipline: kDiscipline)}');

    expect(elo.nbChevauxSuivis, greaterThan(0),
        reason: 'CORRECTION : le service reste pleinement opérationnel');
    expect(store.contient(kEloKey), isTrue,
        reason: 'CORRECTION : et il persiste normalement');
    expect(elo.getRating('CHEVAL_1', discipline: kDiscipline), isNot(1500.0),
        reason: 'TÉMOIN : le calcul a réellement tourné');

    // ── `_charge` reste `true` : le disque ne sera PAS relu ──────────────
    elo.viderMemoirePourResetComplet(); // utilitaire public, hors reset
    await elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: <ZtPartant>[_partant(1), _partant(2)],
      discipline: kDiscipline,
      courseKey: kCleCourseV29, // ★ B2-e : identité exigée
    );
    final nbApresVidage = elo.nbChevauxSuivis;
    debugPrint('C → après vidage + maj : RAM=$nbApresVidage '
        '(les 3 ratings ne sont PAS rechargés si _charge==true)');

    expect(nbApresVidage, lessThanOrEqualTo(2),
        reason: 'CONFIRMATION : `_charge` reste `true`, donc `_charger()` ne '
            'relit pas le disque et ne réimporte pas les 3 ratings. '
            'Repasser `_charge` à `false` les ferait REVENIR — ce n\'est '
            'donc pas le correctif');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D — DURABILITÉ : après le reset, un rechargement ne ramène RIEN
  //
  //  Avant R-DR-05, le disque était réécrit et un rechargement réinjectait
  //  les anciens ratings : la réinitialisation était annulée DURABLEMENT.
  //  Après correctif, le disque reste vide et le rechargement ne ramène rien.
  // ═══════════════════════════════════════════════════════════════════════
  test('D — aucun rating ne ressuscite après un rechargement', () async {
    final elo = EloService.instance;

    // Établir un état ELO réel AVANT le reset.
    await elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
      courseKey: kCleCourseV29, // ★ B2-e : identité exigée
    );
    final nbAvant = elo.nbChevauxSuivis;
    expect(store.contient(kEloKey), isTrue, reason: 'TÉMOIN : clé présente');

    // Mise à jour suspendue, reset lancé, puis achèvement de l'écriture.
    final entree = store.armerSuspensionSet(kEloKey);
    final maj = elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
      courseKey: kCleCourseV29, // ★ B2-e : identité exigée
    );
    await _attendreEntreeOuFin(entree, maj);
    final reset = BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();
    store.libererSet();
    await maj;
    await reset;

    debugPrint('D → apresReset RAM=${elo.nbChevauxSuivis} '
        'disque=${store.contient(kEloKey)} nbAvant=$nbAvant');

    expect(elo.nbChevauxSuivis, 0, reason: 'CORRECTION : RAM vidée');
    expect(store.contient(kEloKey), isFalse,
        reason: 'CORRECTION : disque vide — plus rien à ressusciter');

    // ── Rechargement « nouvelle session » : le disque est vide ────────────
    final contenu = store.lire(kEloKey);
    expect(contenu, isNull,
        reason: 'CORRECTION : aucune donnée sur le disque à recharger');
    elo.chargerDepuisMapIsolate(<String, dynamic>{});

    debugPrint('D → apresReload nb=${elo.nbChevauxSuivis}');

    expect(elo.nbChevauxSuivis, 0,
        reason: 'CORRECTION : un rechargement ne ramène AUCUN rating — la '
            'réinitialisation tient au-delà du processus');
    expect(elo.getRating('CHEVAL_1', discipline: kDiscipline), 1500.0,
        reason: 'CORRECTION : la valeur est celle d\'usine, pas celle d\'avant '
            'le reset');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  E — Le vidage RAM seul ne suffit pas : preuve par le nombre d'écritures
  //
  //  `viderMemoirePourResetComplet()` est synchrone et n'attend RIEN. Une
  //  écriture déjà partie n'est ni annulée ni attendue. Ce test fige le fait
  //  qu'aucun drain n'existe : le journal montre `SET-ENTREE` (écriture
  //  engagée) SANS qu'aucune mécanique ne vienne l'invalider.
  // ═══════════════════════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════════════════════
  //  E — LE CONTRÔLE 1 (`_resetEnCours`) : écriture née PENDANT l'effacement
  //
  //  Ce test isole le CONTRÔLE 1 des deux autres mécanismes. Pour cela il faut
  //  une écriture qui :
  //    • naît APRÈS l'incrément de génération → le contrôle 2 ne peut pas la
  //      refuser (elle capture la génération courante) ;
  //    • naît alors qu'AUCUNE écriture n'est au registre → le drain n'est pas
  //      concerné.
  //
  //  Dispositif : la mise à jour est lancée pendant que le reset est SUSPENDU
  //  sur une clé tardive (`alert_config_v2`, index 86/107), après que les clés
  //  ELO (index 13-15) ont déjà été supprimées.
  // ═══════════════════════════════════════════════════════════════════════
  test('E — contrôle 1 : une écriture née PENDANT l\'effacement est refusée',
      () async {
    final elo = EloService.instance;

    // La clé tardive doit exister pour que la suspension ait lieu.
    store.semer(kCleTardive, 'sentinelle');
    store.armerSuspensionRemove(kCleTardive);
    final reset = BackupService.instance.reinitialiserComplet();

    final suspendu = await _attendreQue(
        () => store.journal.any((e) => e == 'REM flutter.$kCleTardive'));
    expect(suspendu, isTrue, reason: 'TÉMOIN DE PRÉPARATION : reset suspendu');
    expect(store.journal.contains('REM flutter.$kEloKey'), isTrue,
        reason: 'TÉMOIN : les clés ELO sont DÉJÀ supprimées');
    expect(elo.nbEcrituresEnCours, 0,
        reason: 'TÉMOIN : le registre est VIDE — le drain n\'est pas concerné');

    // ── Écriture née ICI, pendant l'effacement ───────────────────────────
    final refusResetAvant = elo.nbRefusParReset;
    final refusGenAvant = elo.nbRefusParGeneration;
    final indexDebutEcriture = store.journal.length;

    await elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
      courseKey: kCleCourseV29, // ★ B2-e : identité exigée
    );
    await _laisserProgresser(4);

    final deltaReset = elo.nbRefusParReset - refusResetAvant;
    final deltaGen = elo.nbRefusParGeneration - refusGenAvant;
    final journalEcriture =
        store.journal.skip(indexDebutEcriture).toList();
    debugPrint('E → deltaReset=$deltaReset deltaGen=$deltaGen '
        'journal=${journalEcriture.where((e) => e.contains(kEloKey)).toList()}');

    // ── CORRECTION : refusée par le CONTRÔLE 1, et par lui SEUL ──────────
    expect(deltaReset, 1,
        reason: 'CORRECTION : le CONTRÔLE 1 (`_resetEnCours`) refuse '
            'l\'écriture — c\'est le mécanisme qui couvre CE scénario');
    expect(deltaGen, 0,
        reason: 'PREUVE D\'ISOLATION : le CONTRÔLE 2 n\'est PAS sollicité. '
            'L\'écriture est née APRÈS l\'incrément, donc sa génération est à '
            'jour et le contrôle 2 laisserait passer. La génération seule ne '
            'suffirait donc PAS');
    expect(journalEcriture.where((e) => e.contains(kEloKey)), isEmpty,
        reason: 'CORRECTION : aucune écriture disque n\'est même tentée — le '
            'refus a lieu avant `_executerSauvegarde`');

    // ── Fin du reset : les clés ELO ne sont PAS recréées ─────────────────
    store.libererRemove();
    await reset;

    debugPrint('E → après fin du reset : disque=${store.contient(kEloKey)} '
        'RAM=${elo.nbChevauxSuivis}');
    expect(store.contient(kEloKey), isFalse,
        reason: 'CORRECTION : la clé n\'est pas recréée pendant l\'effacement');
    expect(elo.nbChevauxSuivis, 0,
        reason: 'CORRECTION : et la RAM est vidée par le `finally` — RAM et '
            'disque restent COHÉRENTS');

    // ── Et le service reste opérationnel ─────────────────────────────────
    await elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
      courseKey: kCleCourseV29, // ★ B2-e : identité exigée
    );
    expect(store.contient(kEloKey), isTrue,
        reason: 'CORRECTION : une mise à jour normale, après le reset, écrit '
            'de nouveau');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G — ISOLATION DU CONTRÔLE 2 (génération) : écriture NÉE AVANT le reset
  //      et dont le disque n'est atteint qu'APRÈS la fin complète du reset.
  //
  //  C'est le SEUL scénario que le drain ne peut pas couvrir : au moment du
  //  reset, l'écriture n'est PAS encore au registre (`nbEcrituresEnCours == 0`)
  //  — elle est retenue dans `SharedPreferences.getInstance()`. Quand elle
  //  reprend, le reset est TERMINÉ : `_resetEnCours` vaut `false`, donc le
  //  contrôle 1 laisse passer. Seule la génération peut la refuser.
  //
  //  Dispositif : `SharedPreferences.resetStatic()` + suspension de `getAll`
  //  (le seul `await` situé entre le contrôle 1 et le contrôle 2). Le reset est
  //  appelé DIRECTEMENT sur `EloService` — sa clôture d'effacement est fournie
  //  par le test — précisément pour qu'il n'ait pas besoin de `getInstance()`
  //  et puisse donc aboutir pendant que l'écriture est suspendue.
  // ═══════════════════════════════════════════════════════════════════════
  test('G — contrôle 2 : écriture née AVANT le reset, atteignant le disque APRÈS',
      () async {
    final elo = EloService.instance;

    // État de départ : ratings en RAM et sur le disque.
    await elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
      courseKey: kCleCourseV29, // ★ B2-e : identité exigée
    );
    expect(elo.nbChevauxSuivis, greaterThan(0), reason: 'TÉMOIN : RAM peuplée');
    expect(store.contient(kEloKey), isTrue, reason: 'TÉMOIN : disque peuplé');

    // ── On force un rechargement du cache de préférences, puis on suspend
    //    `getAll` : la prochaine `getInstance()` restera en vol.
    SharedPreferences.resetStatic();
    final entreeGetAll = store.armerSuspensionGetAll();

    final maj = elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
      courseKey: kCleCourseV29G, // ★ B2-e : 2e course, DISTINCTE (test G)
    );
    final suspendue = await _attendreEntreeOuFin(entreeGetAll, maj);
    expect(suspendue, isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : l\'écriture est suspendue dans '
            '`SharedPreferences.getInstance()`');

    // TÉMOIN CAPITAL : l'écriture n'est PAS encore au registre → le drain,
    // même présent, ne peut rien faire pour elle.
    expect(elo.nbEcrituresEnCours, 0,
        reason: 'FAIT : l\'écriture n\'a pas encore franchi la barrière — le '
            'DRAIN est hors jeu, c\'est bien le contrôle 2 qui est mesuré ici');
    expect(elo.nbChevauxSuivis, greaterThan(0),
        reason: 'TÉMOIN : les deltas sont déjà appliqués en RAM');

    final genAvant = elo.generationCache;

    // ── Reset mené à son TERME pendant la suspension ─────────────────────
    var effacement = 0;
    await elo.executerResetComplet(() async {
      store.effacerDirect(kEloKey);
      store.effacerDirect(kEloTsKey);
      effacement++;
      await Future<void>.delayed(Duration.zero);
    });

    debugPrint('G → reset terminé pendant la suspension : '
        'effacement=$effacement RAM=${elo.nbChevauxSuivis} '
        'disque=${store.contient(kEloKey)} '
        'barriere=${elo.nbRefusParReset} gen=${elo.generationCache}');
    expect(effacement, 1, reason: 'TÉMOIN : le reset est bien allé au bout');
    expect(store.contient(kEloKey), isFalse,
        reason: 'TÉMOIN : la clé a bien été effacée par le reset');
    expect(elo.generationCache, genAvant + 1,
        reason: 'TÉMOIN : la génération a été incrémentée par le reset');

    // ── Libération : l'écriture reprend, le reset est FINI ───────────────
    final refusResetAvant = elo.nbRefusParReset;
    final refusGenAvant = elo.nbRefusParGeneration;
    final abandonsGenAvant = elo.nbAbandonsFileParGeneration;
    final indexLiberation = store.journal.length;
    store.libererGetAll();
    await maj;
    await _laisserProgresser();

    final deltaReset = elo.nbRefusParReset - refusResetAvant;
    final deltaGen = elo.nbRefusParGeneration - refusGenAvant;
    final deltaAbandonsGen = elo.nbAbandonsFileParGeneration - abandonsGenAvant;
    final journalEcriture =
        store.journal.skip(indexLiberation).where((e) => e.contains(kEloKey));
    debugPrint('G → après libération : disque=${store.contient(kEloKey)} '
        'deltaReset=$deltaReset deltaGen=$deltaGen '
        'deltaAbandonsGen=$deltaAbandonsGen '
        'journal=${journalEcriture.toList()}');

    // ── CONTRÔLE 1 HORS JEU : le reset est terminé, `_resetEnCours` est faux ─
    expect(deltaReset, 0,
        reason: 'PREUVE D\'ISOLATION : le CONTRÔLE 1 n\'est PAS sollicité — '
            'au moment où l\'écriture reprend, le reset est terminé et '
            '`_resetEnCours` vaut `false`');

    // ── GÉNÉRATION SEULE RESPONSABLE — ASSERTION INITIALE CONSERVÉE ───────
    //
    // OBJECTIF DU TEST, INCHANGÉ : prouver que c'est la GÉNÉRATION, et elle
    // seule, qui empêche cette écriture d'atteindre le disque.
    //
    // ⚠ CE QUI CHANGE (et pourquoi) : AVANT B2-e, le refus survenait dans
    //   `_sauvegarder()` (contrôle 2) et s'observait donc par
    //   `nbRefusParGeneration == +1`. Avec B2-e, la même vérification de
    //   génération a lieu PLUS TÔT — à l'étape A.3 de
    //   `_mettreAJourApresArrivee`, AVANT toute mutation RAM — et c'est
    //   `_abandonnerParGenerationFile` qui l'exécute, donc l'observable
    //   `nbAbandonsFileParGeneration` qui l'enregistre.
    //   MESURÉ : deltaGen == 0, deltaAbandonsGen == 1.
    //
    //   Ce n'est PAS un affaiblissement : la protection est PLUS forte (elle
    //   empêche désormais la mutation RAM, pas seulement l'écriture). Ce n'est
    //   pas non plus un déplacement silencieux — l'assertion ci-dessous ÉCHOUE
    //   si le refus cesse d'être d'origine « génération ».
    //
    // PREUVE D'ISOLATION renforcée : les DEUX compteurs de refus restent à 0,
    // donc AUCUN autre mécanisme n'est intervenu.
    expect(deltaGen, 0,
        reason: 'PREUVE D\'ISOLATION : le contrôle 2 de `_sauvegarder()` n\'est '
            'plus atteint — la génération est vérifiée AVANT la mutation RAM');
    expect(deltaAbandonsGen, 1,
        reason: 'CORRECTION : c\'est bien le CONTRÔLE DE GÉNÉRATION (contrôle G) '
            'qui refuse l\'écriture née avant le reset. Sans lui (mutation M21), '
            'l\'écriture atteindrait le disque APRÈS l\'effacement et '
            'recréerait la clé supprimée');
    expect(journalEcriture.toList(), isEmpty,
        reason: 'CORRECTION : aucune écriture disque n\'est tentée');
    expect(elo.nbChevauxSuivis, 0,
        reason: 'CORRECTION RENFORCÉE : refus AVANT la mutation, donc aucun '
            'rating n\'est ressuscité en RAM — c\'est plus fort qu\'avant B2-e');

    expect(store.contient(kEloKey), isFalse,
        reason: 'CORRECTION : la clé reste ABSENTE — c\'est la conséquence '
            'directe du refus par génération');
    expect(store.lire(kEloKey), isNull, reason: 'CORRECTION : idem au contenu');
  });
}
