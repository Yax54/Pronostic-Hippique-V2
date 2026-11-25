// ═══════════════════════════════════════════════════════════════════════════
//  A7 / 3.3-B2-a — SUIVI DES ÉCRITURES PERSISTANTES ET DRAIN ÉLARGI
//
//  OBJET DU LOT
//  ────────────
//  Préparer le reset à attendre TOUTES les écritures persistantes, y compris
//  celles qu'un lot ultérieur ajoutera pour le registre ELO, SANS jamais
//  modifier la valeur de `nbEcrituresEnCours`.
//
//  CE QUE CE LOT NE FAIT **PAS** — À LIRE AVANT TOUTE INTERPRÉTATION
//  ─────────────────────────────────────────────────────────────────
//  • il n'accède PAS à `elo_registre_v3` : le registre n'est ni lu, ni écrit,
//    ni supprimé, ni migré. Aucun test de ce fichier ne sème cette clé ;
//  • il ne modifie AUCUN calcul ELO, aucun coefficient K, aucun mécanisme IA ;
//  • il ne change pas la valeur de `nbEcrituresEnCours` : les deux ensembles
//    reçoivent la même future, mais SEUL le compteur historique est exposé
//    exactement comme avant ;
//  • il ne change pas le comportement des opérations commencées pendant un
//    reset : ni `_resetEnCours`, ni la génération, ni l'annulation ne sont
//    touchés.
//
//  STORE INSTRUMENTÉ — MÊME CONTRAT QUE B1
//  ───────────────────────────────────────
//  Chaque `setValue` est journalisé `SET-ENTREE <clé>` à l'ENTRÉE et
//  `SET-OK <clé>` à la SORTIE. Une suspension peut être armée sur une clé :
//  l'écriture reste alors EN VOL tant qu'elle n'est pas libérée. C'est ce
//  dispositif qui rend observable « le drain attend ».
//
//  MESURE PRÉALABLE, IMPORTANTE POUR LA LECTURE DES ASSERTIONS
//  ───────────────────────────────────────────────────────────
//  `setUp()` appelle `EloService.init()` → `_charger()`, qui écrit
//  `elo_orphelins_purges_v1` (elo_service.dart l.279). Le journal du store
//  contient donc déjà cette écriture AVANT chaque test. Toute assertion sur
//  le CONTENU du journal est par conséquent bornée par un index relevé au
//  début du test — jamais absolue.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  STORE INSTRUMENTÉ
// ───────────────────────────────────────────────────────────────────────────

class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};

  /// Écritures et suppressions réellement exécutées, dans l'ordre.
  final List<String> journal = <String>[];

  /// Clé (forme AVEC préfixe `flutter.`) dont l'écriture doit être suspendue.
  String? cleSuspendue;
  Completer<void>? _entreeSuspendue;
  Completer<void>? _verrouSuspendu;

  /// Clés dont l'écriture `setValue` doit RENDRE `false`.
  final Set<String> refuse = <String>{};

  /// Clés dont l'écriture `setValue` doit LEVER.
  final Set<String> leve = <String>{};

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
    // ÉGALITÉ STRICTE — jamais `contains`.
    if (cleSuspendue != null && key == cleSuspendue) {
      final entree = _entreeSuspendue;
      _entreeSuspendue = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      final verrou = _verrouSuspendu;
      if (verrou != null) await verrou.future;
    }
    if (leve.contains(key)) {
      journal.add('SET-LEVE $key');
      throw StateError('panne de stockage simulée sur $key');
    }
    if (refuse.contains(key)) {
      journal.add('SET-REFUS $key');
      return false;
    }
    _valeurs[key] = value;
    journal.add('SET-OK $key');
    return true;
  }

  /// Arme une suspension sur [cle] (forme AVEC préfixe `flutter.`).
  /// Rend la future complétée dès que la suspension est ATTEINTE.
  Future<void> armerSuspension(String cle) {
    final entree = Completer<void>();
    _entreeSuspendue = entree;
    cleSuspendue = cle;
    _verrouSuspendu = Completer<void>();
    return entree.future;
  }

  /// Libère la suspension armée : l'écriture reprend et se termine.
  void libererSuspension() {
    final v = _verrouSuspendu;
    _verrouSuspendu = null;
    cleSuspendue = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void desarmer() {
    cleSuspendue = null;
    _entreeSuspendue = null;
    final v = _verrouSuspendu;
    _verrouSuspendu = null;
    if (v != null && !v.isCompleted) v.complete();
    refuse.clear();
    leve.clear();
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  /// Efface une clé comme le fait RÉELLEMENT le service de reset.
  ///
  /// ⚠️ DÉFAUT DE HARNAIS CORRIGÉ (mesuré) : les clés de ce fichier sont
  ///    stockées PRÉFIXÉES (`flutter.`). Appeler `remove('elo_ratings_v2')`
  ///    cible la clé `elo_ratings_v2` SANS préfixe, qui n'existe pas : le
  ///    `remove` est un NO-OP silencieux. Utiliser cette fonction pour que le
  ///    reset simulé efface réellement ce qu'il prétend effacer.
  Future<void> effacer(String cle) async {
    if (cle.startsWith('flutter.')) {
      await remove(cle);
    } else {
      await remove('flutter.$cle');
    }
  }

  int compterEntreesSet(String cle) =>
      journal.where((e) => e == 'SET-ENTREE $cle').length;
  int compterOkSet(String cle) =>
      journal.where((e) => e == 'SET-OK $cle').length;
}

// Type privé volontaire : le dispositif de store reste local à ce fichier,
// comme dans les tests B1/V29 dont il est la copie assumée.
// ignore: library_private_types_in_public_api
late _Store store;

void _installerStore() {
  store = _Store();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

/// Vidage BORNÉ de la boucle d'événements : aucune assertion ne dépend d'une
/// durée, seulement du nombre de tours de boucle.
///
/// Nécessaire parce que `whenComplete` (elo_service.dart l.469-472) s'exécute
/// en microtâche APRÈS la complétion : le retrait des ensembles n'est donc
/// pas observable dans la même microtâche que la fin de la future.
Future<void> _laisserProgresser([int tours = 24]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ── Constantes partagées avec les tests B1 / V29 ────────────────────────────

const String kDisc = 'Trot Attelé';
const String kCleElo = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
/// Clés telles que le STORE les nomme dans son journal : préfixe natif
/// `flutter.` (mesuré : `SharedPreferences` le préfixe lui-même).
const String kJournalElo = 'flutter.$kCleElo';
const String kJournalTs = 'flutter.$kCleTs';
const String kCleRegistre = 'elo_registre_v3';
const String kJournalRegistre = 'flutter.$kCleRegistre';

/// ★ A7 (3.3-B2-e) — IDENTITÉS DE COURSE DES APPLICATIONS DE CE FICHIER.
///
/// Le contrat B2-e exige une identité exploitable pour TOUTE application ELO :
/// un appel sans `courseKey` rend `identiteNonExploitable` et ne mute rien,
/// ce qui rendrait invisibles les écritures que ce fichier mesure.
///
/// Ces tests vérifient des COMPTEURS D'ÉCRITURES, un DRAIN et des GÉNÉRATIONS,
/// pas l'absence d'identité : ils reçoivent donc des identités RÉELLES et
/// calendairement valides (dates ancrées dans le PASSÉ).
///
/// ⚠️ CHAQUE COURSE LOGIQUEMENT DIFFÉRENTE A SA PROPRE CLÉ. Deux applications
///    qui représentent réellement deux courses distinctes ne partagent JAMAIS
///    une clé : ce serait un refus légitime (`courseDejaJournalisee`) et non
///    l'écriture mesurée.
const String kCleCourse1 = 'R1C1_01112026'; // 1re course d'un test
const String kCleCourse2 = 'R2C2_02112026'; // 2e course, distincte
const String kCleCourse3 = 'R3C3_03112026'; // 3e course, distincte
const String kCleCourse4 = 'R4C4_04112026'; // 4e course, distincte

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

final List<ZtPartant> kPartants = List.generate(6, (i) => _partant(i + 1));
const List<int> kArrivee = <int>[1, 2, 3];

/// Reproduit `EloService._cle` (lecture de production, jamais une modification).
String kCle(String nom) {
  final nomNorm = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  return '$nomNorm|${EloService.normaliserDiscipline(kDisc)}';
}

/// Charge ELO d'import, volontairement distincte de ce que produit une
/// application : sert à prouver QUEL contenu est en RAM à un instant donné.
Map<String, dynamic> _chargeImport(String nom, double rating) =>
    <String, dynamic>{
      kCle(nom): EloScore(
        nomCheval: nom,
        rating: rating,
        nbCourses: 7,
        variationMois: 3.0,
      ).toJson(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _installerStore();
    // `_charge` n'a pas de getter : on le stabilise à `true` pour tout le
    // fichier via `init()`, puis on vide la RAM sans écrire sur le disque.
    await EloService.init();
    EloService.instance.viderMemoirePourResetComplet();
  });

  tearDown(() {
    store.desarmer();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2a-1 — LE SUIVI EXISTE, COMPTE, ET SE VIDE DANS TOUS LES CAS
  //
  //  Exigences 1 et 5 du mandat.
  // ═════════════════════════════════════════════════════════════════════════
  group('B2a-1 — suivi des écritures persistantes', () {
    test('B2a-1a — 0 au repos, 1 pendant une écriture suspendue, 0 après',
        () async {
      final elo = EloService.instance;

      expect(elo.nbEcrituresPersistantesEnCours, 0,
          reason: 'au repos, aucune écriture persistante n\'est en vol');
      expect(elo.nbEcrituresEnCours, 0,
          reason: 'TÉMOIN : les deux ensembles sont vides au repos');

      // Écriture lancée SANS être attendue, suspendue DANS `setString`.
      final entree = store.armerSuspension(kJournalElo);
      final f = elo.importerDepuisBackup(_chargeImport('ALPHA', 1700.0));
      await entree;

      // ignore: avoid_print
      print('[B2a-1a] pendant : persistentes='
          '${elo.nbEcrituresPersistantesEnCours} | '
          'historiques=${elo.nbEcrituresEnCours}');

      expect(elo.nbEcrituresPersistantesEnCours, 1,
          reason: 'l\'écriture est EN VOL : elle est suivie');
      expect(elo.nbEcrituresEnCours, 1,
          reason: 'TÉMOIN : la même future est aussi dans l\'ensemble '
              'historique — B2-a ne rétrécit pas ce dernier');

      store.libererSuspension();
      final etat = await f;
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.persistee);
      expect(elo.nbEcrituresPersistantesEnCours, 0,
          reason: 'l\'écriture terminée doit être RETIRÉE du suivi');
      expect(elo.nbEcrituresEnCours, 0,
          reason: 'TÉMOIN : retirée aussi de l\'ensemble historique');
    });

    test('B2a-1b — retrait MÊME QUAND l\'écriture LÈVE une exception',
        () async {
      final elo = EloService.instance;
      store.leve.add(kJournalElo);

      final etat =
          await elo.importerDepuisBackup(_chargeImport('BETA', 1600.0));
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2a-1b] etat=${etat.name} | persistentes='
          '${elo.nbEcrituresPersistantesEnCours} | '
          'historiques=${elo.nbEcrituresEnCours}');

      expect(etat, EtatPersistanceElo.echouee,
          reason: 'TÉMOIN : l\'écriture des ratings a bien levé');
      expect(elo.nbEcrituresPersistantesEnCours, 0,
          reason: 'INVARIANT CRITIQUE : une future levée est RETIRÉE du '
              'suivi. Sans ce retrait, le drain boucherait indéfiniment sur '
              'un ensemble qui ne se vide jamais');
      expect(elo.nbEcrituresEnCours, 0,
          reason: 'TÉMOIN : même retrait côté historique');
    });

    test('B2a-1c — retrait MÊME QUAND le stockage REND false', () async {
      final elo = EloService.instance;
      store.refuse.add(kJournalElo);

      final etat =
          await elo.importerDepuisBackup(_chargeImport('GAMMA', 1500.0));
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2a-1c] etat=${etat.name} | persistentes='
          '${elo.nbEcrituresPersistantesEnCours} | '
          'historiques=${elo.nbEcrituresEnCours}');

      expect(etat, EtatPersistanceElo.refusee,
          reason: 'TÉMOIN : le stockage a refusé');
      expect(elo.nbEcrituresPersistantesEnCours, 0,
          reason: 'un refus n\'est pas une erreur : la future se termine '
              'normalement et doit être retirée');
      expect(elo.nbEcrituresEnCours, 0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2a-2 — LE COMPTEUR HISTORIQUE GARDE SA VALEUR
  //
  //  Exigence 4 du mandat. Les tests historiques mesurent `nbEcrituresEnCours`
  //  à 0 ou 1 dans des fenêtres précises ; ce groupe reproduit les mêmes
  //  fenêtres et vérifie que B2-a ne les a pas déplacées.
  // ═════════════════════════════════════════════════════════════════════════
  group('B2a-2 — compteur historique préservé', () {
    test('B2a-2a — 1 pendant la suspension sur `_ts` (fenêtre de a7_32c E)',
        () async {
      final elo = EloService.instance;

      // État de départ : les deux clés existent déjà sur le disque.
      // Indispensable pour que « les deux clés existent » ne soit pas un
      // témoin vide au moment de mesurer.
      store.semer(kCleElo, jsonEncode(<String, dynamic>{'ANCIEN|PLAT': 1}));
      store.semer(kCleTs, 1794900000000);

      // Suspension armée sur `_ts` SEULE, par égalité stricte.
      final entree = store.armerSuspension(kJournalTs);
      final f = elo.importerDepuisBackup(_chargeImport('DELTA', 1550.0));
      await entree;

      // ignore: avoid_print
      print('[B2a-2a] pendant _ts : historiques=${elo.nbEcrituresEnCours} | '
          'persistentes=${elo.nbEcrituresPersistantesEnCours} | '
          'ratingsEcrit=${store.compterOkSet(kJournalElo)}');

      expect(store.journal.contains('SET-OK $kJournalElo'), isTrue,
          reason: 'TÉMOIN : `setString` sur les ratings est TERMINÉ');
      expect(elo.nbEcrituresEnCours, 1,
          reason: 'EXIGENCE HISTORIQUE (a7_32c:261) : la future ELO entière '
              'est encore en vol, `_ts` compris');
      expect(elo.nbEcrituresPersistantesEnCours, 1,
          reason: 'le suivi élargi voit la MÊME et unique future — il ne la '
              'dédouble pas');

      store.libererSuspension();
      final etat = await f;
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.persistee);
      expect(elo.nbEcrituresEnCours, 0,
          reason: 'EXIGENCE HISTORIQUE : 0 après la fin complète');
      expect(elo.nbEcrituresPersistantesEnCours, 0);
    });

    test('B2a-2b — les deux ensembles portent le MÊME cardinal en B2-a',
        () async {
      final elo = EloService.instance;
      final entree = store.armerSuspension(kJournalElo);
      final f = elo.importerDepuisBackup(_chargeImport('EPSILON', 1450.0));
      await entree;

      // ignore: avoid_print
      print('[B2a-2b] pendant : historiques=${elo.nbEcrituresEnCours} | '
          'persistentes=${elo.nbEcrituresPersistantesEnCours}');

      expect(elo.nbEcrituresPersistantesEnCours, elo.nbEcrituresEnCours,
          reason: 'en B2-a, la seule écriture persistante existante est celle '
              'de `_sauvegarder()` : les deux ensembles doivent donc porter '
              'EXACTEMENT le même cardinal');

      store.libererSuspension();
      await f;
      await _laisserProgresser();

      expect(elo.nbEcrituresPersistantesEnCours, 0);
      expect(elo.nbEcrituresEnCours, 0);
    });

    test('B2a-2c — le lot n\'écrit AUCUNE clé nouvelle', () async {
      final elo = EloService.instance;
      final indexAvant = store.journal.length;

      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse1, // ★ B2-e : identité exigée
      );
      await _laisserProgresser();

      final cles = store.journal
          .skip(indexAvant)
          .where((e) => e.startsWith('SET-OK '))
          .map((e) => e.substring('SET-OK '.length))
          .toSet();

      // ignore: avoid_print
      print('[B2a-2c] clés écrites=${cles.toList()..sort()}');

      // ★ A7 (3.3-B2-e) — CONTRAT B2-a RÉVISÉ, ET LA RAISON EXACTE.
      //
      // ASSERTION INITIALE : `{elo_ratings_v2, elo_ratings_v2_ts}`.
      // Elle était vraie en B2-a, où le registre n'existait pas encore dans le
      // chemin d'écriture. Elle est FAUSSE depuis B2-e, et c'est VOULU : B2-e
      // journalise une intention AVANT toute mutation, donc il écrit
      // `elo_registre_v3`. Ce n'est pas une régression, c'est l'objet du lot.
      //
      // L'OBJECTIF DE MESURE EST PRÉSERVÉ ET MÊME RENFORCÉ : le test continue
      // de vérifier que l'ensemble des clés écrites est EXACTEMENT celui
      // attendu — donc qu'AUCUNE clé inattendue n'apparaît. La seule
      // différence est l'ajout documenté du registre, désormais NÉCESSAIRE.
      expect(cles, <String>{kJournalElo, kJournalTs, kJournalRegistre},
          reason: 'l\'ensemble EXACT des clés écrites est mesuré : les deux '
              'clés ELO historiques, PLUS le registre exigé par B2-e. Tout '
              'autre clé serait une écriture non déclarée');
      expect(store.contient(kCleRegistre), isTrue,
          reason: '★ B2-e : le registre est AMORCÉ puis journalisé — il ne '
              'peut plus rester absent, c\'est la condition de la protection '
              'transactionnelle (sans lui, aucune entrée, donc aucun refus '
              'possible au rejeu)');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2a-3 — LE DRAIN ATTEND LES DEUX ENSEMBLES
  //
  //  Exigence 3 du mandat : ne pas terminer prématurément (3a), ne pas rester
  //  bloqué (3b, 3c).
  // ═════════════════════════════════════════════════════════════════════════
  group('B2a-3 — drain élargi', () {
    test('B2a-3a — le reset est RETENU tant que l\'écriture est en vol',
        () async {
      final elo = EloService.instance;

      final entree = store.armerSuspension(kJournalElo);
      final f = elo.importerDepuisBackup(_chargeImport('ZETA', 1800.0));
      await entree;

      var effacements = 0;
      var resetTermine = false;
      final reset = elo.executerResetComplet(() async {
        effacements++;
        await store.effacer(kCleElo);
        await Future<void>.delayed(Duration.zero);
      });
      reset.whenComplete(() => resetTermine = true).ignore();

      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2a-3a] pendant : effacements=$effacements | '
          'resetTermine=$resetTermine | '
          'persistentes=${elo.nbEcrituresPersistantesEnCours} | '
          'historiques=${elo.nbEcrituresEnCours}');

      expect(elo.nbEcrituresPersistantesEnCours, 1,
          reason: 'TÉMOIN : l\'écriture est en vol, le drain doit la voir');
      expect(resetTermine, isFalse,
          reason: 'DRAIN : le reset ne peut pas se terminer tant que '
              'l\'écriture persistante n\'est pas achevée');
      expect(effacements, 0,
          reason: 'DRAIN : aucune suppression ne commence avant la libération');

      store.libererSuspension();
      await f;
      await reset;

      // ignore: avoid_print
      print('[B2a-3a] après : effacements=$effacements | '
          'persistentes=${elo.nbEcrituresPersistantesEnCours} | '
          'historiques=${elo.nbEcrituresEnCours}');

      expect(effacements, 1,
          reason: 'ANTI-BLOCAGE : le drain a abouti, le reset est allé au bout');
      expect(elo.nbEcrituresPersistantesEnCours, 0,
          reason: 'ANTI-BLOCAGE : le suivi est vidé après le drain');
      expect(elo.nbEcrituresEnCours, 0,
          reason: 'TÉMOIN historique : registre d\'écritures vide');
      expect(elo.nbChevauxSuivis, 0, reason: 'le reset a bien vidé la RAM');
    });

    test('B2a-3b — une écriture dont `_ts` LÈVE est drainée, le reset aboutit',
        () async {
      final elo = EloService.instance;

      // L'écriture des ratings réussit ; c'est `_ts` qui lèvera. La future
      // reste EN VOL tant que la suspension n'est pas libérée : le drain la
      // voit donc encore inscrite au moment où le reset démarre.
      final entree = store.armerSuspension(kJournalTs);
      store.leve.add(kJournalTs);

      final f = elo.importerDepuisBackup(_chargeImport('ETA', 1300.0));
      await entree;

      expect(elo.nbEcrituresPersistantesEnCours, 1,
          reason: 'TÉMOIN : la future est en vol avant le reset');

      final echecsTsAvant = elo.nbEchecsTs;
      var effacements = 0;
      final reset = elo.executerResetComplet(() async {
        effacements++;
        await store.effacer(kCleElo);
      });

      // Le drain doit être RETENU par la future suspendue.
      await _laisserProgresser();
      expect(effacements, 0,
          reason: 'TÉMOIN : le drain retient encore le reset');

      store.libererSuspension();

      final etat = await f;
      await reset;
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2a-3b] etat=${etat.name} | effacements=$effacements | '
          'deltaEchecsTs=${elo.nbEchecsTs - echecsTsAvant} | '
          'persistentes=${elo.nbEcrituresPersistantesEnCours}');

      expect(etat, EtatPersistanceElo.persistee,
          reason: 'l\'échec de `_ts` est SECONDAIRE : il ne dégrade jamais '
              'l\'état principal du rating');
      expect(elo.nbEchecsTs - echecsTsAvant, 1,
          reason: 'TÉMOIN : l\'exception de `_ts` a bien été comptée');
      expect(effacements, 1,
          reason: 'ANTI-BLOCAGE : une exception dans l\'écriture n\'empêche '
              'jamais le drain d\'aboutir — la boucle capture l\'erreur');
      expect(elo.nbEcrituresPersistantesEnCours, 0,
          reason: 'ANTI-BLOCAGE : le suivi est vidé, même après exception');
    });

    test('B2a-3c — séquence d\'opérations puis reset : le drain se vide',
        () async {
      final elo = EloService.instance;

      // Deux opérations sérialisées par la FIFO B1 : elles écrivent l'une
      // APRÈS l'autre. Le drain doit n'en trouver aucune résiduelle ensuite.
      //
      // ★ B2-e : ce sont DEUX courses différentes (arrivées différentes : 3
      //   partants puis 2). Leur donner deux identités distinctes est la
      //   traduction fidèle du scénario, pas un contournement.
      final f1 = elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse1, // ★ B2-e : identité de la 1re course
      );
      final f2 = elo.mettreAJourApresArrivee(
        arrivee: <int>[1, 2],
        partants: <ZtPartant>[_partant(1), _partant(2)],
        discipline: kDisc,
        courseKey: kCleCourse2, // ★ B2-e : 2e course, DISTINCTE
      );

      final etats = await Future.wait<EtatPersistanceElo>([f1, f2]);
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2a-3c] etats=${etats.map((e) => e.name).toList()} | '
          'persistentes=${elo.nbEcrituresPersistantesEnCours} | '
          'historiques=${elo.nbEcrituresEnCours}');

      expect(etats, everyElement(EtatPersistanceElo.persistee));
      expect(elo.nbEcrituresPersistantesEnCours, 0,
          reason: 'ANTI-BLOCAGE : aucune future résiduelle dans le suivi');
      expect(elo.nbEcrituresEnCours, 0);

      var effacements = 0;
      await elo.executerResetComplet(() async {
        effacements++;
        await store.effacer(kCleElo);
      });

      expect(effacements, 1, reason: 'le reset aboutit immédiatement : il n\'y '
          'avait rien à drainer');
      expect(elo.nbEcrituresPersistantesEnCours, 0);
      expect(elo.nbEcrituresEnCours, 0);
      expect(elo.nbChevauxSuivis, 0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2a-4 — GÉNÉRATIONS RESET PRÉSERVÉES
  //
  //  Exigence 5 du mandat. Les compteurs de refus sont mesurés par DELTA :
  //  EloService est un singleton dont les compteurs sont cumulatifs.
  // ═════════════════════════════════════════════════════════════════════════
  group('B2a-4 — générations reset', () {
    test('B2a-4a — une opération nominale n\'incrémente AUCUN compteur de '
        'refus ni la génération', () async {
      final elo = EloService.instance;

      final refusResetAvant = elo.nbRefusParReset;
      final refusGenAvant = elo.nbRefusParGeneration;
      final genAvant = elo.generationCache;

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: kCleCourse1, // ★ B2-e : identité exigée
      );
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2a-4a] etat=${etat.name} | gen=$genAvant→'
          '${elo.generationCache} | refusReset=$refusResetAvant→'
          '${elo.nbRefusParReset} | refusGen=$refusGenAvant→'
          '${elo.nbRefusParGeneration}');

      expect(etat, EtatPersistanceElo.persistee);
      expect(elo.generationCache, genAvant,
          reason: 'une opération nominale n\'incrémente PAS la génération');
      expect(elo.nbRefusParReset, refusResetAvant,
          reason: 'une opération nominale n\'est pas refusée par le reset');
      expect(elo.nbRefusParGeneration, refusGenAvant,
          reason: 'une opération nominale n\'est pas refusée par génération');
    });

    test('B2a-4b — écriture née PENDANT l\'effacement : contrôle 1, EXACTEMENT '
        '+1', () async {
      final elo = EloService.instance;
      await elo.importerDepuisBackup(_chargeImport('THETA', 1600.0));
      await _laisserProgresser();

      final refusResetAvant = elo.nbRefusParReset;
      final genAvant = elo.generationCache;

      // Reset SUSPENDU dans sa suppression : l'écriture ELO naît PENDANT
      // l'effacement, donc après la barrière synchrone.
      final entree = Completer<void>();
      final liberation = Completer<void>();
      final reset = elo.executerResetComplet(() async {
        if (!entree.isCompleted) entree.complete();
        await liberation.future;
      });
      await entree.future;

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: <int>[1, 2],
        partants: <ZtPartant>[_partant(1), _partant(2)],
        discipline: kDisc,
        // ★ B2-e : SANS identité, l'opération serait refusée AVANT le contrôle 1
        //   (`identiteNonExploitable`, rendu `nonTentee`), et le test mesurerait
        //   ce refus au lieu du CONTRÔLE 1 qu'il a pour objet de vérifier.
        //   L'identité est donc fournie pour que le scénario atteigne bien la
        //   persistance et déclenche le contrôle de reset.
        courseKey: kCleCourse1,
      );

      // ignore: avoid_print
      print('[B2a-4b] etat=${etat.name} | refusReset=$refusResetAvant→'
          '${elo.nbRefusParReset} | gen=$genAvant→${elo.generationCache}');

      expect(etat, EtatPersistanceElo.abandonneeParReset,
          reason: 'l\'écriture née pendant l\'effacement est REFUSÉE par le '
              'CONTRÔLE 1');
      expect(elo.nbRefusParReset, refusResetAvant + 1,
          reason: 'EXIGENCE HISTORIQUE (a7_32 T8, l.467) : le compteur est '
              'incrémenté EXACTEMENT une fois, au même endroit qu\'avant B2-a');
      expect(elo.nbEcrituresPersistantesEnCours, 0,
          reason: 'aucune écriture persistante engagée : le contrôle 1 refuse '
              'AVANT `_executerSauvegarde`, donc rien n\'est inscrit');

      // Clôture : le reset doit finir pour ne pas laisser la barrière fermée.
      liberation.complete();
      await reset;

      expect(elo.nbChevauxSuivis, 0, reason: 'le reset a vidé la RAM');
      expect(elo.nbEcrituresPersistantesEnCours, 0);
    });

    test('B2a-4c — la barrière est RELÂCHÉE : une opération postérieure '
        'aboutit encore', () async {
      final elo = EloService.instance;

      var effacements = 0;
      await elo.executerResetComplet(() async {
        effacements++;
        await store.effacer(kCleElo);
        await store.effacer(kCleTs);
      });
      expect(effacements, 1);

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: <int>[1, 2],
        partants: <ZtPartant>[_partant(1), _partant(2)],
        discipline: kDisc,
        // ★ B2-e : identité exigée — sans elle le refus serait
        //   `identiteNonExploitable`, et le test ne mesurerait plus la
        //   RÉOUVERTURE de la barrière (objet réel de B2a-4c).
        courseKey: kCleCourse1,
      );
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2a-4c] après reset : etat=${etat.name} | '
          'persistentes=${elo.nbEcrituresPersistantesEnCours} | '
          'historiques=${elo.nbEcrituresEnCours}');

      expect(etat, EtatPersistanceElo.persistee,
          reason: 'ANTI-BLOCAGE : le reset a bien rouvert la barrière — '
              'aucun verrou n\'est resté fermé');
      expect(elo.nbEcrituresPersistantesEnCours, 0);
      expect(elo.nbEcrituresEnCours, 0);
    });
  });
}
