// ═══════════════════════════════════════════════════════════════════════════
//  A7 — 3.3-B1 : FILE FIFO STRICTE DES OPÉRATIONS CRITIQUES D'ELO
//
//  OBJET : prouver que la file introduite dans `EloService` sérialise les
//  opérations qui MUTENT `_ratings` puis persistent, SANS activer le registre
//  transactionnel et SANS toucher aux formules ELO.
//
//  ⚠️ CE QUE CES TESTS N'ACTIVENT PAS (interdits du lot, mesurés) :
//    • `elo_registre_v3` n'est ni lu ni écrit ici ;
//    • aucun format de `elo_ratings_v2` n'est modifié ;
//    • aucune intention / acquittement / journal ;
//    • aucune clé SharedPreferences nouvelle (`_toutesLesCles` reste 108).
//
//  DISPOSITIF : store SharedPreferences instrumenté. Il permet de SUSPENDRE
//  une écriture (pour observer l'état « opération en vol »), de la REFUSER
//  (`false`) et de la faire LEVER. Aucune assertion ne repose sur une durée :
//  les seuls observables sont le journal du store, les compteurs du service et
//  les ratings.
//
//  ⚠️ LIMITE EXPLICITE DE CE FICHIER (mesurée, voir B1-3) : aucune exception
//  ne s'échappe d'`EloService`. Ses opérations publiques CONVERTISSENT les
//  défaillances du stockage en `EtatPersistanceElo` (`echouee`, `refusee`).
//  Le `catch` de la file est donc une défense en profondeur ; il est exercé au
//  niveau atteignable le plus proche — une défaillance réelle du stockage.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Store instrumenté : journal, suspension, refus, exception.
//  Copie volontaire du dispositif validé en V29 (aucune factorisation : les
//  fichiers de test restent autonomes et lisibles isolément).
// ───────────────────────────────────────────────────────────────────────────
class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  /// Clés dont l'écriture `setValue` doit être SUSPENDUE.
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
    if (cleSuspendue != null && key.contains(cleSuspendue!)) {
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

  /// Arme une suspension : rend la future qui se complète quand l'écriture de
  /// [cle] est ENTRÉE et suspendue.
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
    _verrouSuspendu = null;
    refuse.clear();
    leve.clear();
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  /// ⚠️ NOTE DE MESURE (lot B2-e) — NE PAS UTILISER `remove(<clé nue>)` ICI.
  ///
  /// Les clés de ce fichier sont stockées PRÉFIXÉES (`flutter.`).
  /// `remove('elo_ratings_v2')` cible donc une clé SANS préfixe, inexistante :
  /// c'est un NO-OP silencieux. Ce fichier contourne déjà le problème en
  /// passant la forme préfixée (`kJournalElo`, `'flutter.$kCleTs'`) : toutes
  /// ses suppressions de reset sont donc RÉELLES, et aucun test de ce fichier
  /// n'est concerné par le défaut mesuré sur `a7_33b2a`. Cette note existe
  /// pour que la forme correcte soit explicite plutôt qu'implicite.
  int compterEntreesSet(String cle) =>
      journal.where((e) => e == 'SET-ENTREE $cle').length;
  int compterOkSet(String cle) =>
      journal.where((e) => e == 'SET-OK $cle').length;
}

// Type privé volontaire : le dispositif de store reste local à ce fichier,
// comme dans les tests V29 dont il est la copie assumée.
// ignore: library_private_types_in_public_api
late _Store store;

void _installerStore() {
  store = _Store();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

// ── Attentes BORNÉES : aucune assertion ne dépend d'une durée ───────────────

/// Vidage borné de la boucle d'événements.
Future<void> _laisserProgresser([int tours = 24]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ── Constructeurs ───────────────────────────────────────────────────────────

const String kDisc = 'Trot Attelé'; // → normaliserDiscipline → TROT_ATTELE
const String kCleElo = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
/// Clés telles que le STORE les nomme dans son journal : préfixe natif
/// `flutter.` (le même que `prefs.remove` ajoute lui-même, cf. backup_service).
const String kJournalElo = 'flutter.$kCleElo';
const String kCleRegistre = 'elo_registre_v3';
const String kJournalRegistre = 'flutter.$kCleRegistre';

/// ★ A7 (3.3-B2-e) — IDENTITÉS DE COURSE DES APPLICATIONS DE CE FICHIER.
///
/// Le contrat B2-e exige une identité exploitable pour TOUTE application ELO :
/// un appel sans `courseKey` rend `identiteNonExploitable` et ne mute rien.
/// Or ce fichier vérifie la FILE FIFO, les délais d'attente, les calculs ELO
/// (B1-7a/b/c) et les resets — jamais l'absence d'identité. Il reçoit donc des
/// identités RÉELLES, calendairement valides et ANCRÉES DANS LE PASSÉ.
///
/// ⚠️ RÈGLE APPLIQUÉE, SANS EXCEPTION : une clé par course LOGIQUEMENT
///    DIFFÉRENTE. Deux applications sérialisées par la file, avec des arrivées
///    ou des partants différents, sont deux courses : elles reçoivent deux clés.
///    Réutiliser une clé ferait refuser la seconde (`courseDejaJournalisee`) et
///    le test mesurerait un doublon au lieu de la file.
const String kCleCourseA = 'R1C1_01112026';
const String kCleCourseB = 'R2C2_02112026';
const String kCleCourseC = 'R3C3_03112026';
const String kCleCourseD = 'R4C4_04112026';
const String kCleCourseE = 'R5C5_05112026';

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
  //  B1-1 — FIFO AVEC OPÉRATIONS CONCURRENTES
  //
  //  Deux imports lancés ENSEMBLE, le premier étant SUSPENDU dans son
  //  écriture. Sans file, le second pourrait vider la RAM et écrire AVANT que
  //  le premier n'ait fini : le contenu final serait celui du second, mais
  //  l'ordre des écritures disque serait entrelacé. Avec la file, le second ne
  //  doit RIEN faire tant que le premier n'est pas terminé.
  // ═════════════════════════════════════════════════════════════════════════
  group('B1-1 — FIFO avec opérations concurrentes', () {
    test('B1-1a — une opération en attente ne démarre pas avant la fin de la '
        'précédente', () async {
      final elo = EloService.instance;

      final entree = store.armerSuspension(kCleElo);
      final execAvant = elo.nbOperationsFileExecutees;

      // Opération 1 : suspendue DANS l'écriture de `elo_ratings_v2`.
      final f1 = elo.importerDepuisBackup(_chargeImport('ALPHA', 1700.0));
      await entree;

      expect(store.compterEntreesSet(kJournalElo), 1,
          reason: 'TÉMOIN : la 1re opération a bien ENTRÉ dans son écriture');
      expect(elo.nbOperationsFileEnAttente, 0,
          reason: 'TÉMOIN : à cet instant, la 2e n\'est pas encore soumise');

      // Opération 2 : soumise pendant que la 1re est en vol.
      final f2 = elo.importerDepuisBackup(_chargeImport('BETA', 1900.0));

      // Elle doit être EN ATTENTE, et n'avoir rien écrit.
      expect(elo.nbOperationsFileEnAttente, 1,
          reason: 'FIFO : la 2e opération est EN ATTENTE derrière la 1re');
      expect(store.compterEntreesSet(kJournalElo), 1,
          reason: 'FIFO : la 2e n\'a PAS tenté sa propre écriture — elle '
              'attend la fin complète de la 1re');

      // Aucune des deux n'est terminée : la 1re est suspendue, la 2e attend.
      expect(elo.nbOperationsFileExecutees, execAvant,
          reason: 'FIFO : aucune opération n\'est encore allée au bout');

      // Libération : la 1re se termine, PUIS la 2e s'exécute.
      store.libererSuspension();
      final e1 = await f1;
      final e2 = await f2;

      expect(e1, EtatPersistanceElo.persistee);
      expect(e2, EtatPersistanceElo.persistee);

      // ORDRE STRICT : l'entrée d'écriture de la 1re précède celle de la 2e,
      // et la 1re est terminée (SET-OK) avant que la 2e n'entre.
      final iEntree1 = store.journal.indexOf('SET-ENTREE $kJournalElo');
      final iOk1     = store.journal.indexOf('SET-OK $kJournalElo');
      final iEntree2 = store.journal.lastIndexOf('SET-ENTREE $kJournalElo');

      expect(iEntree1, greaterThanOrEqualTo(0),
          reason: 'TÉMOIN : la 1re écriture est journalisée');
      expect(iOk1, greaterThanOrEqualTo(0),
          reason: 'TÉMOIN : la 1re écriture est confirmée');
      expect(iEntree2, greaterThan(iOk1),
          reason: 'PREUVE FIFO : la 2e écriture n\'entre qu\'APRÈS la '
              'confirmation de la 1re (journal : $iEntree1 < $iOk1 < $iEntree2)');

      expect(elo.nbOperationsFileExecutees, execAvant + 2,
          reason: 'les DEUX opérations ont été exécutées jusqu\'au bout');
      expect(elo.nbOperationsFileEnAttente, 0,
          reason: 'la file est VIDÉE : plus rien en attente');

      // CONTENU FINAL : c'est la 2e opération qui est la dernière appliquée,
      // donc la RAM porte BETA et non ALPHA. C'est l'ORDRE qui le garantit.
      final disque = jsonDecode(store.lire(kCleElo)! as String)
          as Map<String, dynamic>;
      expect(disque.containsKey(kCle('BETA')), isTrue,
          reason: 'la dernière opération appliquée est la 2e (BETA)');
      expect(disque.containsKey(kCle('ALPHA')), isFalse,
          reason: 'l\'import REMPLACE la map : ALPHA a bien été écrasé par BETA');
    });

    test('B1-1b — ordre FIFO préservé sur TROIS opérations', () async {
      final elo = EloService.instance;

      final entree = store.armerSuspension(kCleElo);
      final f1 = elo.importerDepuisBackup(_chargeImport('UN', 1600.0));
      await entree;

      final f2 = elo.importerDepuisBackup(_chargeImport('DEUX', 1700.0));
      final f3 = elo.importerDepuisBackup(_chargeImport('TROIS', 1800.0));

      expect(elo.nbOperationsFileEnAttente, 2,
          reason: 'FIFO : les 2e et 3e opérations attendent toutes les deux');
      expect(store.compterEntreesSet(kJournalElo), 1,
          reason: 'FIFO : une seule écriture tentée, celle de la tête de file');

      store.libererSuspension();
      await Future.wait(<Future<EtatPersistanceElo>>[f1, f2, f3]);

      // Exactement TROIS écritures, sérialisées, dans cet ordre.
      expect(store.compterEntreesSet(kJournalElo), 3,
          reason: 'les trois opérations ont écrit, une par une');

      // Les trois SET-ENTREE sont séparés chacun par un SET-OK : aucune
      // n'a démarré avant la confirmation de la précédente.
      final etapes = store.journal
          .where((e) => e == 'SET-ENTREE $kJournalElo' || e == 'SET-OK $kJournalElo')
          .toList();
      expect(etapes.length, 6,
          reason: 'TÉMOIN : 3 entrées + 3 confirmations');
      for (var i = 0; i < 6; i += 2) {
        expect(etapes[i], 'SET-ENTREE $kJournalElo',
            reason: 'position $i : entrée');
        expect(etapes[i + 1], 'SET-OK $kJournalElo',
            reason: 'position ${i + 1} : confirmation immédiatement après — '
                'aucune écriture ne s\'intercale');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1-2 — APPLICATION ELO PUIS IMPORT (D11, option A)
  //
  //  Exigence : une application ELO en cours TERMINE avant qu'un import ne
  //  puisse commencer. Sans file, l'import pourrait `_ratings.clear()` pendant
  //  que l'application est en vol et détruire ses deltas.
  // ═════════════════════════════════════════════════════════════════════════
  group('B1-2 — application puis import', () {
    test('B1-2 — l\'import attend la fin complète de l\'application ELO',
        () async {
      final elo = EloService.instance;

      final entree = store.armerSuspension(kCleElo);
      final relance = elo.mettreAJourApresArrivee(
        arrivee:    kArrivee,
        partants:   kPartants,
        discipline: kDisc,
        courseKey:  kCleCourseA, // ★ B2-e : identité exigée
      );
      await entree;

      // À cet instant : les deltas sont calculés, la RAM est mutée, l'écriture
      // est suspendue. C'est la situation exacte que D11 doit protéger.
      final nbRamPendant = elo.nbChevauxSuivis;
      expect(nbRamPendant, greaterThan(0),
          reason: 'TÉMOIN : l\'application a déjà muté la RAM');
      expect(store.contient(kCleElo), isFalse,
          reason: 'TÉMOIN : l\'écriture n\'est PAS encore confirmée');

      // L'import est soumis MAINTENANT : il ne doit pas toucher la RAM.
      final import_ = elo.importerDepuisBackup(_chargeImport('GAMMA', 2100.0));

      expect(elo.nbOperationsFileEnAttente, 1,
          reason: 'D11-A : l\'import est EN ATTENTE derrière l\'application');
      expect(elo.nbChevauxSuivis, nbRamPendant,
          reason: 'D11-A MESURÉ : l\'import n\'a PAS vidé la RAM — les deltas '
              'de l\'application en cours sont intacts ($nbRamPendant ratings)');
      expect(elo.getRating('CHEVAL_1', discipline: kDisc), isNot(1500.0),
          reason: 'D11-A : le rating calculé par l\'application est toujours '
              'là, il n\'a pas été écrasé par l\'import');

      store.libererSuspension();
      final etatMaj = await relance;
      final etatImport = await import_;

      expect(etatMaj, EtatPersistanceElo.persistee,
          reason: 'l\'application s\'est terminée normalement');
      expect(etatImport, EtatPersistanceElo.persistee,
          reason: 'puis l\'import s\'est exécuté');

      // ORDRE : l'application écrit AVANT l'import.
      final iOk1 = store.journal.indexOf('SET-OK $kJournalElo');
      final iEntree2 = store.journal.lastIndexOf('SET-ENTREE $kJournalElo');
      expect(iOk1, greaterThanOrEqualTo(0));
      expect(iEntree2, greaterThan(iOk1),
          reason: 'D11-A : l\'écriture de l\'application est CONFIRMÉE avant '
              'que l\'import n\'entre dans la sienne');

      // Après l'import, la RAM est celle de l'import : il est bien passé en
      // dernier, comme l'exige l'ordre d'appel.
      final disque = jsonDecode(store.lire(kCleElo)! as String)
          as Map<String, dynamic>;
      expect(disque.containsKey(kCle('GAMMA')), isTrue,
          reason: 'l\'import est bien la DERNIÈRE opération appliquée');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1-3 — UNE ERREUR NE BLOQUE PAS LA FILE
  //
  //  ⚠️ CONSTAT MESURÉ, à ne pas confondre avec un échec de test :
  //  `EloService` ne laisse FUIR aucune exception. Ses deux écritures
  //  (`ratings` et `_ts`) sont capturées ; une panne du stockage est convertie
  //  en `EtatPersistanceEnum.echouee`, jamais propagée. Le `catch` de la file
  //  est donc une protection EN PROFONDEUR, et le « ne pas bloquer » se prouve
  //  au niveau observable réel : après une opération en échec, la suivante est
  //  exécutée.
  // ═════════════════════════════════════════════════════════════════════════
  group('B1-3 — erreur puis opération suivante', () {
    test('B1-B — écriture LEVANT puis écriture valide : la file continue',
        () async {
      final elo = EloService.instance;
      final execAvant = elo.nbOperationsFileExecutees;
      final echoueesAvant = elo.nbEchouees;

      // L'écriture des ratings LÈVE (défaillance réelle du stockage).
      store.leve.add(kJournalElo);

      final etatEchec = await elo.importerDepuisBackup(
          _chargeImport('DELTA', 1650.0));

      expect(etatEchec, EtatPersistanceElo.echouee,
          reason: 'MESURÉ : la défaillance est CONVERTIE en `echouee` — elle '
              'n\'est pas propagée à l\'appelant (contrat 3.2 conservé)');
      expect(elo.nbEchouees, echoueesAvant + 1,
          reason: 'le compteur d\'échecs a bien été incrémenté');

      // La file a bien été RELÂCHÉE malgré l'échec.
      expect(elo.nbOperationsFileEnAttente, 0,
          reason: 'FIFO : plus rien en attente après l\'échec');
      expect(elo.nbOperationsFileExecutees, execAvant + 1,
          reason: 'l\'opération en échec a bien été EXÉCUTÉE (et non perdue)');

      // ── L'opération SUIVANTE doit s'exécuter normalement. ────────────────
      store.leve.remove(kJournalElo);

      final etatSuivant = await elo.importerDepuisBackup(
          _chargeImport('EPSILON', 1750.0));

      expect(etatSuivant, EtatPersistanceElo.persistee,
          reason: 'PREUVE : la file n\'est PAS restée bloquée par l\'échec — '
              'l\'opération suivante aboutit normalement');
      expect(elo.nbOperationsFileExecutees, execAvant + 2,
          reason: 'les deux opérations ont été exécutées');
      expect(elo.nbOperationsFileEnAttente, 0,
          reason: 'file vide après les deux opérations');

      // Le contenu persisté est bien celui de l'opération devenue valide.
      final disque = jsonDecode(store.lire(kCleElo)! as String)
          as Map<String, dynamic>;
      expect(disque.containsKey(kCle('EPSILON')), isTrue,
          reason: 'la 2e opération a réellement écrit sur le disque');
    });

    test('B1-B2 — écriture REFUSÉE puis écriture valide : la file continue',
        () async {
      final elo = EloService.instance;

      store.refuse.add(kJournalElo);
      final etatRefus = await elo.importerDepuisBackup(
          _chargeImport('ZETA', 1600.0));

      expect(etatRefus, EtatPersistanceElo.refusee,
          reason: 'MESURÉ : `setValue → false` est converti en `refusee`');

      store.refuse.remove(kJournalElo);
      final etatOk = await elo.importerDepuisBackup(
          _chargeImport('ETA', 1850.0));

      expect(etatOk, EtatPersistanceElo.persistee,
          reason: 'PREUVE : après un REFUS, la file laisse passer la suivante');
      expect(elo.nbOperationsFileEnAttente, 0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1-4 — RESET PENDANT UNE OPÉRATION : AUCUNE RÉSURRECTION
  //
  //  Partie (a) : comportement HISTORIQUE préservé — une écriture née pendant
  //  le reset mute la RAM puis est refusée par le contrôle 1. C'est ce
  //  qu'attendent V29-I (v29b:469-470) et T8 (a7_32:467), mesuré ici aussi.
  //
  //  Partie (b) : le reset VIDE la RAM ; aucune opération ultérieure ne doit
  //  la repeupler à partir de l'ancien contenu.
  // ═════════════════════════════════════════════════════════════════════════
  group('B1-4 — reset pendant une opération', () {
    test('B1-4a — opération née PENDANT le reset : RAM mutée, écriture refusée '
        'par le contrôle 1 (comportements V29-I et T8 préservés)', () async {
      final elo = EloService.instance;

      // Un reset est mené et SUSPENDU dans son effacement.
      final entree = Completer<void>();
      final liberation = Completer<void>();
      final reset = elo.executerResetComplet(() async {
        if (!entree.isCompleted) entree.complete();
        await liberation.future;
      });
      await entree.future;

      final refusResetAvant = elo.nbRefusParReset;
      final refusGenAvant = elo.nbRefusParGeneration;
      final abandonsAvant = elo.nbAbandonsFileParGeneration;

      // L'opération NAÎT pendant l'effacement : sa génération est À JOUR
      // (le reset l'a déjà incrémentée), donc le contrôle G ne la rejette pas.
      final etat = await elo.mettreAJourApresArrivee(
        arrivee:    kArrivee,
        partants:   kPartants,
        discipline: kDisc,
        courseKey:  kCleCourseA, // ★ B2-e : identité exigée
      );

      liberation.complete();
      await reset;

      expect(etat, EtatPersistanceElo.abandonneeParReset,
          reason: 'PRÉSERVÉ : le contrôle 1 refuse l\'écriture (état attendu '
              'par V29-I et T8)');
      expect(elo.nbRefusParReset, refusResetAvant + 1,
          reason: 'PRÉSERVÉ : `nbRefusParReset` est incrémenté EXACTEMENT une '
              'fois, au même endroit — c\'est ce que mesure T8');
      expect(elo.nbRefusParGeneration, refusGenAvant,
          reason: 'PRÉSERVÉ : le contrôle 2 n\'est PAS sollicité (isolation '
              'mesurée par V29-I)');
      expect(elo.nbAbandonsFileParGeneration, abandonsAvant,
          reason: 'le contrôle G n\'est PAS sollicité : l\'opération n\'était '
              'pas périmée, elle est née après l\'incrément de génération');

      // Le reset a vidé la RAM dans son `finally`, et n\'a RIEN laissé sur le
      // disque : RAM et disque sont cohérents.
      expect(elo.nbChevauxSuivis, 0,
          reason: 'le `finally` du reset a vidé la RAM');
      expect(store.contient(kCleElo), isFalse,
          reason: 'AUCUNE résurrection : la clé n\'a pas été recréée');
    });

    test('B1-4b — après le reset, une opération valide repart de la RAM VIDE : '
        'pas de résurrection', () async {
      final elo = EloService.instance;

      // État initial peuplé et persisté.
      await elo.importerDepuisBackup(_chargeImport('THETA', 2000.0));
      expect(elo.nbChevauxSuivis, 1, reason: 'TÉMOIN : la RAM est peuplée');
      expect(store.contient(kCleElo), isTrue,
          reason: 'TÉMOIN : le disque est peuplé');

      // Reset complet, mené à son terme.
      await elo.executerResetComplet(() async {
        await store.remove(kJournalElo); // efface réellement `elo_ratings_v2`
      });

      expect(elo.nbChevauxSuivis, 0, reason: 'reset : RAM vidée');
      expect(store.contient(kCleElo), isFalse, reason: 'reset : disque vidé');

      // `_charge` reste `true` : la mise à jour suivante ne relit PAS le
      // disque, elle repart de la RAM vide. Elle ne peut donc pas ramener
      // THETA. C'est la preuve de non-résurrection au niveau le plus fort.
      await elo.mettreAJourApresArrivee(
        arrivee:    <int>[1, 2],
        partants:   <ZtPartant>[_partant(1), _partant(2)],
        discipline: kDisc,
        courseKey:  kCleCourseB, // ★ B2-e : course NOUVELLE après reset
      );

      final ratings = jsonDecode(store.lire(kCleElo)! as String)
          as Map<String, dynamic>;
      expect(ratings.containsKey(kCle('THETA')), isFalse,
          reason: 'NON-RÉSURRECTION : le rating supprimé n\'est PAS revenu');
      expect(elo.getRating('THETA', discipline: kDisc), 1500.0,
          reason: 'NON-RÉSURRECTION : THETA n\'existe plus, `getRating` rend '
              'le défaut — l\'ancienne valeur 2000.0 a bien disparu');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1-5 — OPÉRATION EN ATTENTE DEVENUE PÉRIMÉE (contrôle G)
  //
  //  C'est le scénario qui N'EXISTAIT PAS avant la file : une opération est
  //  SOUMISE mais n'a pas encore couru ; un reset complet intervient ENTIÈREMENT
  //  pendant qu'elle attend ; puis elle reprend. Sans contrôle G, elle
  //  appliquerait ses deltas à une RAM que le reset vient de vider, et
  //  RESSUSCITERAIT des ratings.
  //
  //  Dispositif : l'opération de tête est suspendue dans son écriture afin
  //  d'occuper la file. Une SECONDE opération est alors soumise (elle attend).
  //  Le reset est lancé : il draine la 1re, s'exécute, vide la RAM et incrémente
  //  la génération. Puis on libère : la 1re se termine, la 2e reprend et doit
  //  s'ABANDONNER avant toute mutation RAM.
  // ═════════════════════════════════════════════════════════════════════════
  group('B1-5 — opération en attente devenue périmée', () {
    test('B1-5a — une opération EN ATTENTE pendant un reset s\'abandonne SANS '
        'mutations RAM', () async {
      final elo = EloService.instance;

      // ── Opération de tête : suspendue dans son écriture, elle occupe la file.
      final entree = store.armerSuspension(kCleElo);
      final f1 = elo.importerDepuisBackup(_chargeImport('IOTA', 1600.0));
      await entree;

      // ── Seconde opération : SOUMISE, donc EN ATTENTE.
      final abandonsAvant = elo.nbAbandonsFileParGeneration;
      final f2 = elo.importerDepuisBackup(_chargeImport('KAPPA', 2400.0));

      expect(elo.nbOperationsFileEnAttente, 1,
          reason: 'TÉMOIN : la 2e opération attend bien son tour');

      // ── Reset complet, mené à son TERME pendant que la 2e attend. ─────────
      final genAvant = elo.generationCache;
      var effacements = 0;
      final reset = elo.executerResetComplet(() async {
        effacements++;
        await store.remove(kJournalElo);
        // Laisse la boucle d'événements tourner : si la 2e opération pouvait
        // courir hors file, elle le ferait ICI, pendant que la RAM est vide.
        await Future<void>.delayed(Duration.zero);
      });

      // Le reset ne peut pas se terminer tant que la 1re écriture est en vol
      // (drain) : on vérifie ce point capital avant de libérer.
      await _laisserProgresser();
      expect(elo.generationCache, genAvant + 1,
          reason: 'TÉMOIN : la génération a DÉJÀ été incrémentée — c\'est la '
              'barrière SYNCHRONE d\'`executerResetComplet` (l.584-585), posée '
              'AVANT le drain. C\'est ce décrément qui rend la 2e opération '
              'périmée alors qu\'elle n\'a pas encore couru');
      expect(effacements, 0,
          reason: 'DRAIN PRÉSERVÉ : aucune suppression n\'a commencé tant que '
              'l\'écriture de la 1re opération est en vol');

      // ── La 2e opération, elle, n\'est PAS encore entrée dans `_ecrituresEnCours` :
      //    elle attend son tour et n\'a donc rien engagé. Le drain ne l\'attend
      //    PAS — c\'est précisément ce qui interdit toute attente circulaire.
      expect(elo.nbEcrituresEnCours, 1,
          reason: 'ANTI-INTERBLOCAGE : le drain n\'attend QUE la future de la '
              '1re opération ; l\'opération en attente n\'a rien engagé dans '
              'le registre d\'écritures');

      // ── Libération : la 1re écriture se termine, le reset efface. ─────────
      store.libererSuspension();
      await f1;

      // Le reset s'achève : la 2e opération, elle, est TOUJOURS en attente.
      await reset;

      expect(effacements, 1, reason: 'TÉMOIN : le reset est allé au bout');
      expect(elo.nbChevauxSuivis, 0,
          reason: 'TÉMOIN : le `finally` du reset a vidé la RAM');

      // ── Reprise de la 2e opération : elle doit S'ABANDONNER. ─────────────
      final etat2 = await f2;

      expect(etat2, EtatPersistanceElo.abandonneeParReset,
          reason: 'CONTRÔLE G : l\'opération devenue périmée est ABANDONNÉE');
      expect(elo.nbAbandonsFileParGeneration, abandonsAvant + 1,
          reason: 'le compteur NOUVEAU d\'abandons par génération a été '
              'incrémenté — et lui seul');
      expect(elo.nbChevauxSuivis, 0,
          reason: 'NON-RÉSURRECTION MESURÉE : l\'opération périmée n\'a PAS '
              'muté la RAM — elle n\'a pas ressuscité KAPPA après le reset');
      expect(store.contient(kCleElo), isFalse,
          reason: 'NON-RÉSURRECTION : aucune écriture disque n\'a été tentée '
              'par l\'opération abandonnée');
      expect(elo.getRating('KAPPA', discipline: kDisc), 1500.0,
          reason: 'NON-RÉSURRECTION : KAPPA n\'existe pas — `getRating` rend '
              'le défaut 1500');
    });

    test('B1-5b — l\'abandon par le contrôle G n\'incrémente NI '
        'nbRefusParReset NI nbRefusParGeneration', () async {
      final elo = EloService.instance;

      final entree = store.armerSuspension(kCleElo);
      final f1 = elo.importerDepuisBackup(_chargeImport('LAMBDA', 1600.0));
      await entree;

      final resetAvant = elo.nbRefusParReset;
      final genAvantNb = elo.nbRefusParGeneration;
      final abandonsAvant = elo.nbAbandonsFileParGeneration;

      final f2 = elo.importerDepuisBackup(_chargeImport('MU', 2400.0));
      expect(elo.nbOperationsFileEnAttente, 1);

      final reset = elo.executerResetComplet(() async {
        await store.remove(kJournalElo);
      });

      store.libererSuspension();
      await f1;
      await reset;
      final etat2 = await f2;

      expect(etat2, EtatPersistanceElo.abandonneeParReset);
      expect(elo.nbAbandonsFileParGeneration, abandonsAvant + 1,
          reason: 'SEUL le compteur d\'abandons de file a bougé');
      expect(elo.nbRefusParReset, resetAvant,
          reason: 'PRÉSERVATION STRICTE : `nbRefusParReset` n\'a PAS bougé — '
              'il est mesuré par delta EXACT dans T8 (a7_32:467)');
      expect(elo.nbRefusParGeneration, genAvantNb,
          reason: 'PRÉSERVATION STRICTE : `nbRefusParGeneration` n\'a PAS '
              'bougé non plus');
    });

    test('B1-5c — contrôle G hors reset : une opération NON périmée n\'est '
        'jamais abandonnée', () async {
      final elo = EloService.instance;
      final abandonsAvant = elo.nbAbandonsFileParGeneration;

      // Aucun reset : la génération est inchangée, le contrôle G est inerte.
      final etat = await elo.mettreAJourApresArrivee(
        arrivee:    kArrivee,
        partants:   kPartants,
        discipline: kDisc,
        courseKey:  kCleCourseA, // ★ B2-e : identité exigée
      );

      expect(etat, EtatPersistanceElo.persistee,
          reason: 'une opération normale aboutit');
      expect(elo.nbAbandonsFileParGeneration, abandonsAvant,
          reason: 'TÉMOIN NÉGATIF : le contrôle G ne s\'est PAS déclenché — '
              'sans reset, il laisserait passer n\'importe quoi');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1-6 — AUCUNE DOUBLE APPLICATION CAUSÉE PAR LA FILE
  //
  //  La file ne doit ni dupliquer ni perdre une opération. Elle ne rend PAS la
  //  primitive idempotente (elle ne reçoit pas `courseKey`) : deux APPELS
  //  restent deux applications — c'est le fait caractérisé T-A7-6a, conservé.
  //  Ce qui est exigé ici : N appels ⟹ N applications, jamais N+1 ni N-1.
  // ═════════════════════════════════════════════════════════════════════════
  group('B1-6 — pas de double application due à la file', () {
    test('B1-6a — deux appels concurrents : exactement DEUX applications '
        '(caractérisation T-A7-6a préservée)', () async {
      final elo = EloService.instance;

      await elo.importerDepuisBackup(_chargeImport('NU', 1500.0));

      final nbAvant = elo.getScore('CHEVAL_1', discipline: kDisc).nbCourses;
      final execAvant = elo.nbOperationsFileExecutees;
      // Compte de référence : l'import de préparation a DÉJÀ écrit une fois.
      // Toutes les assertions d'écriture sont donc mesurées par DELTA.
      final ecrituresAvant = store.compterEntreesSet(kJournalElo);

      final f1 = elo.mettreAJourApresArrivee(
        arrivee:    kArrivee,
        partants:   kPartants,
        discipline: kDisc,
        courseKey:  kCleCourseA, // ★ B2-e : 1re course
      );
      final f2 = elo.mettreAJourApresArrivee(
        arrivee:    kArrivee,
        partants:   kPartants,
        discipline: kDisc,
        courseKey:  kCleCourseB, // ★ B2-e : 2e course, DISTINCTE
      );
      final etats = await Future.wait(<Future<EtatPersistanceElo>>[f1, f2]);

      expect(etats, everyElement(EtatPersistanceElo.persistee),
          reason: 'les DEUX opérations ont abouti');
      expect(elo.nbOperationsFileExecutees, execAvant + 2,
          reason: 'la file a exécuté exactement DEUX opérations — ni une de '
              'plus (ce serait une double application), ni une de moins (ce '
              'serait une perte)');
      expect(elo.getScore('CHEVAL_1', discipline: kDisc).nbCourses, nbAvant + 2,
          reason: 'CARACTÉRISATION PRÉSERVÉE (T-A7-6a) : deux APPELS restent '
              'deux applications. La file sérialise, elle ne déduplique pas.');

      // Delta = 2 : une écriture par opération, aucune surnuméraire.
      expect(store.compterEntreesSet(kJournalElo) - ecrituresAvant, 2,
          reason: 'AUCUNE écriture surnuméraire introduite par la file — '
              'mesuré par DELTA, l\'import de préparation ayant déjà écrit 1');
    });

    test('B1-6b — deux IMPORTS concurrents : une seule écriture finale, '
        'celle du dernier', () async {
      final elo = EloService.instance;
      final ecrituresAvant = store.compterEntreesSet(kJournalElo);

      final f1 = elo.importerDepuisBackup(_chargeImport('XI', 1550.0));
      final f2 = elo.importerDepuisBackup(_chargeImport('OMICRON', 1650.0));
      await Future.wait(<Future<EtatPersistanceElo>>[f1, f2]);

      // Delta = 2 : une écriture par opération, aucune en double.
      expect(store.compterEntreesSet(kJournalElo) - ecrituresAvant, 2,
          reason: 'une écriture par opération, aucune en double (mesuré par '
              'delta : les tests précédents ont pu écrire)');
      final disque = jsonDecode(store.lire(kCleElo)! as String)
          as Map<String, dynamic>;
      expect(disque.containsKey(kCle('OMICRON')), isTrue,
          reason: 'la dernière opération soumise est bien la dernière écrite');
      expect(disque.keys.length, 1,
          reason: 'un import REMPLACE la map : pas d\'accumulation parasite');
    });

    test('B1-6c — appel séquentiel : UNE seule application', () async {
      final elo = EloService.instance;
      final nbAvant = elo.getScore('CHEVAL_2', discipline: kDisc).nbCourses;

      await elo.mettreAJourApresArrivee(
        arrivee:    kArrivee,
        partants:   kPartants,
        discipline: kDisc,
        courseKey:  kCleCourseA, // ★ B2-e : identité exigée
      );

      expect(elo.getScore('CHEVAL_2', discipline: kDisc).nbCourses, nbAvant + 1,
          reason: 'CAS NOMINAL : un appel = une application. Témoin négatif '
              'indispensable : sans lui, « 2 appels = 2 » pourrait venir d\'un '
              'doublement généralisé');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1-7 — LES CALCULS ELO SONT INCHANGÉS
  //
  //  Oracle recalculé à partir des CONSTANTES PUBLIQUES du service, sans
  //  réimplémenter la formule dans le test : on lit `getRating`/`getScore` et
  //  on applique la formule HISTORIQUE (avant 3.3-B1), écrite ici une seule
  //  fois, pour une arrivée de DEUX chevaux — le cas le plus simple, donc le
  //  plus vérifiable.
  //
  //  Formule historique (elo_service l.417-429, inchangée par ce lot) :
  //    probA = 1 / (1 + 10^((rB - rA)/400))
  //    K     = K de la discipline (débutant si nbCourses < 20)
  //    delta_A = K_A * (1 - probA) * facteurDistance
  //    facteurDistance = 0.7^(j-i-1) = 1 pour une paire adjacente
  //  puis rating = clamp(rA + delta, 800, 2500) et nbCourses + 1.
  // ═════════════════════════════════════════════════════════════════════════
  group('B1-7 — calculs ELO inchangés', () {
    test('B1-7a — le rating produit est EXACTEMENT celui de la formule '
        'historique, pour deux chevaux de départ', () async {
      final elo = EloService.instance;

      // Deux chevaux neufs : rating par défaut, 0 course → K débutant.
      const rA = 1500.0;
      const rB = 1500.0;
      const nb = 0; // < _seuilDebutant (20)

      // Oracle, recalculé depuis les constantes HISTORIQUES.
      // TROT_ATTELE débutant → 52.0 (l.79, NON MODIFIÉE par ce lot).
      const kAttendu = 52.0;
      final probAAttendue = 1.0 / (1.0 + math.pow(10, (rB - rA) / 400));
      final deltaAAttendu = kAttendu * (1.0 - probAAttendue) * 1.0;
      final ratingAAttendu =
          (rA + deltaAAttendu).clamp(800.0, 2500.0);

      await elo.mettreAJourApresArrivee(
        arrivee:    <int>[1, 2],
        partants:   <ZtPartant>[_partant(1), _partant(2)],
        discipline: kDisc,
        courseKey:  kCleCourseC, // ★ B2-e : identité exigée
      );

      final ratingObtenu = elo.getRating('CHEVAL_1', discipline: kDisc);
      final nbObtenu = elo.getScore('CHEVAL_1', discipline: kDisc).nbCourses;

      expect(nb, 0, reason: 'TÉMOIN : le cheval est bien DÉBUTANT (0 course)');
      expect(ratingObtenu, closeTo(ratingAAttendu, 1e-9),
          reason: 'CALCUL INCHANGÉ : $ratingObtenu attendu '
              '$ratingAAttendu (formule historique, K débutant TROT_ATTELE)');
      expect(nbObtenu, 1,
          reason: 'nbCourses incrémenté de 1, comme avant 3.3-B1');

      // Le perdant : delta symétrique négatif, même K.
      final probBAttendue = 1.0 - probAAttendue;
      final deltaBAttendu = kAttendu * (0.0 - probBAttendue) * 1.0;
      final ratingBAttendu = (rB + deltaBAttendu).clamp(800.0, 2500.0);
      expect(elo.getRating('CHEVAL_2', discipline: kDisc),
          closeTo(ratingBAttendu, 1e-9),
          reason: 'CALCUL INCHANGÉ côté perdant également');
    });

    test('B1-7b — coefficient K par discipline NON modifié', () async {
      final elo = EloService.instance;

      // Même paire, mais en PLAT : K débutant = 48.0 (l.84, non modifiée).
      const kPlat = 48.0;
      const probA = 0.5; // ratings égaux
      final attendu = (1500.0 + kPlat * (1.0 - probA) * 1.0).clamp(800.0, 2500.0);

      await elo.mettreAJourApresArrivee(
        arrivee:    <int>[1, 2],
        partants:   <ZtPartant>[_partant(1), _partant(2)],
        discipline: 'Plat',
        courseKey:  kCleCourseD, // ★ B2-e : identité exigée
      );

      expect(elo.getRating('CHEVAL_1', discipline: 'Plat'),
          closeTo(attendu, 1e-9),
          reason: 'K PAR DISCIPLINE INCHANGÉ : PLAT débutant = $kPlat');
    });

    test('B1-7c — facteur de distance NON modifié (arrivée de 3)', () async {
      final elo = EloService.instance;

      // Paire (i=0, j=1) : facteur 0.7^0 = 1.
      // Paire (i=0, j=2) : facteur 0.7^1 = 0.7.
      // CHEVAL_1 est présent dans LES DEUX paires → son delta est la SOMME.
      const k = 52.0;
      const prob = 0.5;
      final attendu = (1500.0 + k * (1.0 - prob) * 1.0 + k * (1.0 - prob) * 0.7)
          .clamp(800.0, 2500.0);

      await elo.mettreAJourApresArrivee(
        arrivee:    kArrivee, // [1, 2, 3]
        partants:   kPartants,
        discipline: kDisc,
        courseKey:  kCleCourseE, // ★ B2-e : identité exigée
      );

      final obtenu = elo.getRating('CHEVAL_1', discipline: kDisc);
      expect(obtenu, closeTo(attendu, 1e-9),
          reason: 'FACTEUR DE DISTANCE INCHANGÉ : cumul des paires (1,2) et '
              '(1,3) — attendu $attendu, obtenu $obtenu');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1-8 — ABSENCE D'INTERBLOCAGE
  //
  //  Trois configurations à risque, toutes mesurées :
  //   (a) le reset ne passe JAMAIS par la file : il progresse alors même
  //       qu'une opération est en attente derrière une écriture suspendue ;
  //   (b) une opération ne s'auto-attend pas : elle ne démarre qu'une fois ;
  //   (c) la file se vide après un mélange d'opérations, y compris après un
  //       reset complet effectué pendant une opération.
  // ═════════════════════════════════════════════════════════════════════════
  group('B1-8 — absence d\'interblocage', () {
    test('B1-8a — le reset progresse alors qu\'une opération attend dans la '
        'file : aucune attente circulaire', () async {
      final elo = EloService.instance;

      final entree = store.armerSuspension(kCleElo);
      final f1 = elo.importerDepuisBackup(_chargeImport('PI', 1600.0));
      await entree;

      final f2 = elo.importerDepuisBackup(_chargeImport('RHO', 1700.0));
      expect(elo.nbOperationsFileEnAttente, 1,
          reason: 'TÉMOIN : une opération attend dans la file');

      var resetTermine = false;
      final reset = elo.executerResetComplet(() async {
        await store.remove(kJournalElo);
      });
      reset.whenComplete(() => resetTermine = true).ignore();

      await _laisserProgresser();
      expect(resetTermine, isFalse,
          reason: 'DRAIN : le reset est retenu par l\'écriture suspendue — '
              'il n\'est PAS bloqué par la file, qui n\'entre pas dans son '
              'drain (sinon : attente circulaire)');

      // Libération. L'ORDRE de complétion est le cœur de la preuve :
      // la 1re écriture finit → le drain libère le reset → le reset efface.
      store.libererSuspension();
      await f1;
      await reset;
      final etat2 = await f2;

      expect(resetTermine, isTrue,
          reason: 'ANTI-INTERBLOCAGE : le reset s\'est TERMINÉ');
      expect(etat2, EtatPersistanceElo.abandonneeParReset,
          reason: 'et l\'opération en attente s\'est abandonnée après le reset');

      // Aucune future ne reste en vol : la preuve que rien n'attend rien.
      expect(elo.nbEcrituresEnCours, 0,
          reason: 'ANTI-INTERBLOCAGE : le registre d\'écritures est DRAINÉ');
      expect(elo.nbOperationsFileEnAttente, 0,
          reason: 'ANTI-INTERBLOCAGE : la file est VIDE');

      // Le service reste opérationnel APRÈS tout cela : aucune barrière ni
      // file n\'est restée fermée.
      final etatApres = await elo.mettreAJourApresArrivee(
        arrivee:    kArrivee,
        partants:   kPartants,
        discipline: kDisc,
        courseKey:  kCleCourseA, // ★ B2-e : identité exigée
      );
      expect(etatApres, EtatPersistanceElo.persistee,
          reason: 'ANTI-INTERBLOCAGE : après la séquence complète, une '
              'opération normale aboutit — ni la file ni le reset ne sont '
              'restés verrouillés');
    });

    test('B1-8b — une opération ne s\'auto-attend pas : elle ne démarre '
        'qu\'une seule fois', () async {
      final elo = EloService.instance;
      final execAvant = elo.nbOperationsFileExecutees;

      final etat = await elo.importerDepuisBackup(_chargeImport('SIGMA', 1600.0));

      expect(etat, EtatPersistanceElo.persistee);
      expect(elo.nbOperationsFileExecutees, execAvant + 1,
          reason: 'la file n\'a exécuté qu\'UNE opération pour un appel — '
              'aucun démarrage en double, donc aucune auto-attente');
      expect(store.compterEntreesSet(kJournalElo), 1,
          reason: 'une seule écriture tentée : preuve au niveau du stockage');
      expect(elo.nbOperationsFileEnAttente, 0,
          reason: 'file vide : l\'opération ne s\'est pas mise en attente '
              'derrière elle-même');
    });

    test('B1-8c — séquence mixte (imports + application + reset) : la file '
        'se vide et le service reste opérationnel', () async {
      final elo = EloService.instance;
      final execAvant = elo.nbOperationsFileExecutees;

      // Quatre opérations concurrentes de natures différentes.
      final f1 = elo.importerDepuisBackup(_chargeImport('TAU', 1500.0));
      final f2 = elo.mettreAJourApresArrivee(
        arrivee:    kArrivee,
        partants:   kPartants,
        discipline: kDisc,
        courseKey:  kCleCourseA, // ★ B2-e : course A
      );
      final f3 = elo.mettreAJourApresArrivee(
        arrivee:    <int>[1, 2],
        partants:   <ZtPartant>[_partant(1), _partant(2)],
        discipline: kDisc,
        courseKey:  kCleCourseB, // ★ B2-e : course B, DISTINCTE
      );
      final f4 = elo.importerDepuisBackup(_chargeImport('UPSILON', 1900.0));

      final etats = await Future.wait(<Future<EtatPersistanceElo>>[
        f1, f2, f3, f4,
      ]);

      expect(etats, everyElement(EtatPersistanceElo.persistee),
          reason: 'les quatre opérations ont abouti — aucune n\'est restée '
              'bloquée derrière une autre');
      expect(elo.nbOperationsFileExecutees, execAvant + 4,
          reason: 'la file a exécuté exactement quatre opérations');
      expect(elo.nbOperationsFileEnAttente, 0,
          reason: 'ANTI-INTERBLOCAGE : file vide après la séquence');
      expect(elo.nbEcrituresEnCours, 0,
          reason: 'ANTI-INTERBLOCAGE : registre d\'écritures drainé');

      // Puis un reset complet : il doit aboutir et vider la RAM.
      //
      // ★ A7 (3.3-B2-e) — le reset simulé doit effacer AUSSI le registre.
      //   Mesure : `elo_registre_v3` appartient à `_keysELO`
      //   (`backup_service.dart` l.198), lui-même dans `_toutesLesCles` (l.405),
      //   donc le reset de PRODUCTION efface cette clé. Ne pas l'effacer ici
      //   laissait un registre dont l'empreinte déclarée ne correspondait plus
      //   aux ratings supprimés : il devenait `divergent`, et l'opération finale
      //   était refusée (`registreNonCoherent`) — un artefact du harnais, pas un
      //   défaut du service. La simulation est désormais FIDÈLE.
      await elo.executerResetComplet(() async {
        await store.remove(kJournalElo);
        await store.remove('flutter.$kCleTs');
        await store.remove(kJournalRegistre);
      });

      expect(elo.nbChevauxSuivis, 0, reason: 'reset : RAM vidée');
      expect(elo.nbEcrituresEnCours, 0,
          reason: 'ANTI-INTERBLOCAGE : toujours aucun future en vol');
      expect(elo.nbOperationsFileEnAttente, 0,
          reason: 'ANTI-INTERBLOCAGE : la file est restée vide');

      // Et une dernière opération fonctionne : aucune barrière n\'est restée
      // fermée après toute la séquence.
      final etatFinal = await elo.mettreAJourApresArrivee(
        arrivee:    <int>[1, 2],
        partants:   <ZtPartant>[_partant(1), _partant(2)],
        discipline: kDisc,
        courseKey:  kCleCourseC, // ★ B2-e : course NOUVELLE après reset
      );
      expect(etatFinal, EtatPersistanceElo.persistee,
          reason: 'le service est pleinement opérationnel après tout cela');
    });
  });
}
