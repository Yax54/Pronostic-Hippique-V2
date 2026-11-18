// ═══════════════════════════════════════════════════════════════════════════
//  A7 — ÉTAPE 3.2 : OBSERVABILITÉ DE LA PERSISTANCE ELO
//
//  ⚠️ Aucune formule ELO, aucun K-factor, aucun gradient, aucun apprentissage,
//     aucun poids/seuil, aucun TOP3 n'est touché par ces tests.
//
//  CE QUI EST MESURÉ
//  ─────────────────
//  Avant 3.2, `_executerSauvegarde` jetait les retours `bool` de `setString`
//  et `setInt`, et avalait les exceptions dans un `debugPrint`. Un appelant
//  recevait la fin de la future sans pouvoir en déduire quoi que ce soit.
//
//  Après 3.2, trois méthodes publiques rendent un `EtatPersistanceElo` :
//  `mettreAJourApresArrivee`, `importerDepuisBackup`, `reinitialiser`.
//
//  ⚠️ LIMITE DE SÉMANTIQUE, REDITE ICI PARCE QU'ELLE EST CENTRALE :
//  `refusee` et `echouee` signifient **persistance NON CONFIRMÉE**, PAS
//  « ratings persistés inchangés ». Le stockage peut avoir écrit puis répondu
//  `false`, ou avoir levé après une écriture partielle. Les assertions ci-
//  dessous ne prétendent donc JAMAIS que le disque est resté intact : elles
//  vérifient que l'ÉTAT RETOURNÉ est le bon, et observent le disque pour
//  information.
//
//  ⚠️ LIMITE DE DURABILITÉ PHYSIQUE : le store de test est en mémoire.
//  `SharedPreferences` côté Android n'appelle jamais `.commit()` (7 `.apply()`
//  mesurés dans `SharedPreferencesPlugin.kt`). Un `true` de `setString` n'est
//  donc PAS une preuve d'écriture physique. Aucun test ne prétend le contraire.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';

const String kCleElo = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
const String kDisc = 'Trot Attelé';
const String kDiscNorm = 'TROT_ATTELE';

/// ★ A7 (3.3-B2-e) — IDENTITÉ DE COURSE DES APPELS DE CE FICHIER.
///
/// Depuis B2-e (§6), une application ELO sans identité exploitable est REFUSÉE
/// (`identiteNonExploitable`) : ces tests vérifiaient la PERSISTANCE des
/// ratings (`refusee`, `echouee`, `persistee`, `abandonneeParReset`) et ne
/// pouvaient plus l'atteindre. La clé fournie est donc une identité RÉELLE,
/// cohérente, calendairement valide et ANCRÉE DANS LE PASSÉ (B2-e refuse une
/// date postérieure au lendemain).
///
/// Elle est IDENTIQUE pour tous les tests de ce fichier : chacun repart d'un
/// `setUp` neuf (`_monter`), donc aucune course n'est rejouée d'un test à
/// l'autre — sauf dans T8, qui N'EXÉCUTE qu'un seul appel.
const String kCleCourse = 'R1C1_01112026';

String _cle(String nom) => '${nom.toUpperCase()}|$kDiscNorm';

// ───────────────────────────────────────────────────────────────────────────
//  Espion de stockage : contrôle fin du comportement de `setString`/`setInt`.
// ───────────────────────────────────────────────────────────────────────────
class _StoreT extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};

  /// Journal ordonné des opérations réellement demandées.
  final List<String> journal = <String>[];

  /// Clés dont l'écriture doit être REFUSÉE (`setValue` → `false`).
  final Set<String> refus = <String>{};

  /// Clés dont l'écriture doit LEVER une exception.
  final Set<String> levent = <String>{};

  /// Nombre de tentatives d'écriture par clé (préfixe compris).
  final Map<String, int> tentatives = <String, int>{};

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
    journal.add('SET $key');
    tentatives[key] = (tentatives[key] ?? 0) + 1;
    if (levent.contains(key)) {
      throw StateError('panne simulée sur $key');
    }
    if (refus.contains(key)) return false;
    _valeurs[key] = value;
    return true;
  }

  // ── Helpers (clé SANS le préfixe natif) ────────────────────────────────
  void poser(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? brut(String cle) => _valeurs['flutter.$cle'];

  int ecrituresDe(String cle) => journal.where((e) => e == 'SET flutter.$cle').length;
  int ecrituresElo() => ecrituresDe(kCleElo);
}

late _StoreT _store;

void _monter() {
  _store = _StoreT();
  SharedPreferencesStorePlatform.instance = _store;
  SharedPreferences.resetStatic();
  EloService.instance.viderMemoirePourResetComplet();
  SharedPreferences.resetStatic();
}

// ── Partants / helpers de données ─────────────────────────────────────────
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
      eloRating: 1500.0,
      eloNbCourses: 20,
      eloVariationMois: 0.0,
      statsTerrainCsv: 'BON|12|30|9',
      gainsDernierAn: num * 1000,
    );

Map<String, dynamic> _payloadElo() => <String, dynamic>{
      for (final n in <String>['CHEVAL_1', 'CHEVAL_2'])
        _cle(n): <String, dynamic>{
          'nom': n, 'rating': 1500.0, 'nb': 20, 'var': 0.0,
        },
    };

/// Prépare 2 chevaux à rating égal (delta attendu ±18, K=36, non débutants).
Future<void> _preparerElo() async {
  final data = _payloadElo();
  // ① état disque de référence
  _store.poser(kCleElo, jsonEncode(data));
  // ★ PIDÈGE MESURÉ : `importerDepuisBackup` APPEL`_sauvegarder()` et écrase
  //   donc la clé par `_ratings`, qui vient d'être vidée par un éventuel
  //   `clear()` antérieur. On injecte donc l'état en RAM PUIS on réécrit le
  //   disque AVEC le même contenu, de sorte que « disque = RAM » soit vrai
  //   au démarrage de chaque test.
  await EloService.instance.importerDepuisBackup(data);
  _store.poser(kCleElo, jsonEncode(
      EloService.instance.exporterPourBackup()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_monter);

  // ═════════════════════════════════════════════════════════════════════════
  //  T1 — `setString` RÉPOND `false`
  //
  //  Assertion demandée : l'état est `refusee`, et l'on N'EN DÉDUIT PAS que
  //  le disque est inchangé. On mesure donc l'état, les compteurs, et l'on
  //  observe le disque SANS en faire une preuve d'absence.
  // ═════════════════════════════════════════════════════════════════════════
  test('T1 — setString refuse : etat=refusee, rating RAM applique, disque non conclu',
      () async {
    await _preparerElo();
    final persisteesAvant = EloService.instance.nbPersistees;
    final refuseesAvant = EloService.instance.nbRefuseesStockage;

    _store.refus.add('flutter.$kCleElo');

    final etat = await EloService.instance.mettreAJourApresArrivee(
      arrivee: <int>[1, 2],
      partants: <ZtPartant>[_partant(1), _partant(2)],
      discipline: kDisc,
      courseKey: kCleCourse, // ★ B2-e : identité exigée pour journaliser
    );

    final rating1 = EloService.instance.getRating('CHEVAL_1', discipline: kDisc);

    // ignore: avoid_print
    print('[T1] etat=${etat.name} | rating1=$rating1 | '
        'persistees=$persisteesAvant→${EloService.instance.nbPersistees} | '
        'refusees=$refuseesAvant→${EloService.instance.nbRefuseesStockage} | '
        'erreur=${EloService.instance.derniereErreurEcriture}');

    expect(etat, EtatPersistanceElo.refusee,
        reason: 'setString → false doit donner `refusee`, pas `persistee`');
    expect(rating1, closeTo(1518.0, 0.001),
        reason: 'le CALCUL a bien eu lieu en RAM : 1500 + 18 (K=36, probA=0.5)');
    expect(EloService.instance.nbRefuseesStockage, refuseesAvant + 1,
        reason: 'le refus doit être COMPTÉ');
    expect(EloService.instance.nbPersistees, persisteesAvant,
        reason: 'aucune persistance confirmée ne doit être comptée');
    // ⚠️ Ce qui suit n'est PAS une preuve d'absence d'écriture physique :
    // c'est l'observation du store de test, qui n'a effectivement rien écrit
    // puisqu'il a refusé AVANT d'écrire. Un store réel pourrait différer.
    expect(EloService.instance.nbEchouees, 0,
        reason: 'un refus n\'est pas une exception : ne pas confondre les deux');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T2 — `setString` LÈVE une exception
  // ═════════════════════════════════════════════════════════════════════════
  test('T2 — setString leve : etat=echouee, exception conservee, pas de propagation',
      () async {
    await _preparerElo();
    final echoueesAvant = EloService.instance.nbEchouees;

    _store.levent.add('flutter.$kCleElo');

    // L'option (A) validée interdit toute propagation : l'acquisition doit
    // se terminer normalement, avec un état.
    final etat = await EloService.instance.mettreAJourApresArrivee(
      arrivee: <int>[1, 2],
      partants: <ZtPartant>[_partant(1), _partant(2)],
      discipline: kDisc,
      courseKey: kCleCourse, // ★ B2-e : identité exigée pour journaliser
    );

    final rating1 = EloService.instance.getRating('CHEVAL_1', discipline: kDisc);
    final err = EloService.instance.derniereErreurEcriture;

    // ignore: avoid_print
    print('[T2] etat=${etat.name} | rating1=$rating1 | '
        'echouees=$echoueesAvant→${EloService.instance.nbEchouees} | '
        'erreur=${err.runtimeType}');

    expect(etat, EtatPersistanceElo.echouee,
        reason: 'une exception doit donner `echouee`');
    expect(err, isA<StateError>(),
        reason: 'l\'exception doit être CONSERVÉE, plus seulement imprimée');
    expect(rating1, closeTo(1518.0, 0.001),
        reason: 'le calcul RAM a eu lieu AVANT l\'écriture : il n\'est pas annulé');
    expect(EloService.instance.nbEchouees, echoueesAvant + 1,
        reason: 'l\'exception doit être COMPTÉE séparément d\'un refus');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T3 — `_ts` REFUSÉ alors que les ratings sont confirmés
  //
  //  Exigence 3 du mandat : le résultat principal RESTE `persistee`, et le
  //  défaut secondaire est comptabilisé à part.
  // ═════════════════════════════════════════════════════════════════════════
  test('T3 — _ts refuse : etat reste persistee, nbEchecsTs incremente',
      () async {
    await _preparerElo();
    final tsAvant = EloService.instance.nbEchecsTs;
    final persisteesAvant = EloService.instance.nbPersistees;
    // ⚠️ Les compteurs du singleton sont CUMULATIFS sur la vie du processus :
    //    le `setUp` ne les remet pas à zéro (aucune API publique ne le fait).
    //    On mesure donc TOUJOURS par DELTA, comme v29/v29b.
    final echoueesAvant = EloService.instance.nbEchouees;

    _store.refus.add('flutter.$kCleTs');

    final etat = await EloService.instance.mettreAJourApresArrivee(
      arrivee: <int>[1, 2],
      partants: <ZtPartant>[_partant(1), _partant(2)],
      discipline: kDisc,
      courseKey: kCleCourse, // ★ B2-e : identité exigée pour journaliser
    );

    // ignore: avoid_print
    print('[T3] etat=${etat.name} | '
        'persistees=$persisteesAvant→${EloService.instance.nbPersistees} | '
        'echecsTs=$tsAvant→${EloService.instance.nbEchecsTs}');

    expect(etat, EtatPersistanceElo.persistee,
        reason: '`_ts` n\'est PAS une preuve ELO : son échec ne doit pas '
            'dégrader le résultat principal');
    expect(EloService.instance.nbEchecsTs, tsAvant + 1,
        reason: 'le défaut secondaire doit néanmoins être observable');
    expect(EloService.instance.nbEchouees, echoueesAvant,
        reason: 'un échec de `_ts` ne doit PAS incrémenter le compteur des '
            'échecs de RATINGS — les deux défauts sont distincts');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T4 — `_ts` LÈVE une exception alors que les ratings sont confirmés
  // ═════════════════════════════════════════════════════════════════════════
  test('T4 — _ts leve : etat reste persistee, nbEchecsTs incremente', () async {
    await _preparerElo();
    final tsAvant = EloService.instance.nbEchecsTs;
    final echoueesAvant = EloService.instance.nbEchouees;

    _store.levent.add('flutter.$kCleTs');

    final etat = await EloService.instance.mettreAJourApresArrivee(
      arrivee: <int>[1, 2],
      partants: <ZtPartant>[_partant(1), _partant(2)],
      discipline: kDisc,
      courseKey: kCleCourse, // ★ B2-e : identité exigée pour journaliser
    );

    // ignore: avoid_print
    print('[T4] etat=${etat.name} | '
        'echecsTs=$tsAvant→${EloService.instance.nbEchecsTs} | '
        'echouees=${EloService.instance.nbEchouees}');

    expect(etat, EtatPersistanceElo.persistee,
        reason: 'une exception sur `_ts` ne doit pas dégrader le rating');
    expect(EloService.instance.nbEchecsTs, tsAvant + 1);
    expect(EloService.instance.nbEchouees, echoueesAvant,
        reason: 'une exception sur `_ts` n\'est pas une exception sur les '
            'ratings : les compteurs restent indépendants');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T5 — Rien à écrire : `nonTentee`, et ZÉRO écriture tentée
  // ═════════════════════════════════════════════════════════════════════════
  test('T5 — arrivee vide / moins de 2 partants : nonTentee, aucune ecriture',
      () async {
    await _preparerElo();
    final ecrituresAvant = _store.ecrituresElo();
    final refuseesAvant = EloService.instance.nbRefuseesStockage;
    final echoueesAvant = EloService.instance.nbEchouees;

    final etatVide = await EloService.instance.mettreAJourApresArrivee(
      arrivee: const <int>[],
      partants: <ZtPartant>[_partant(1), _partant(2)],
      discipline: kDisc,
      courseKey: kCleCourse,
    );
    final etatUn = await EloService.instance.mettreAJourApresArrivee(
      arrivee: const <int>[1],
      partants: <ZtPartant>[_partant(1), _partant(2)],
      discipline: kDisc,
      courseKey: kCleCourse,
    );

    // ignore: avoid_print
    print('[T5] arriveeVide=${etatVide.name} | arrivee1=${etatUn.name} | '
        'ecrituresElo=$ecrituresAvant→${_store.ecrituresElo()}');

    expect(etatVide, EtatPersistanceElo.nonTentee);
    expect(etatUn, EtatPersistanceElo.nonTentee);
    expect(_store.ecrituresElo(), ecrituresAvant,
        reason: 'aucune écriture de `$kCleElo` ne doit être TENTÉE — '
            '`nonTentee` n\'est pas un échec, c\'est une absence de besoin');
    expect(EloService.instance.nbRefuseesStockage, refuseesAvant,
        reason: '« rien à écrire » n\'est pas un refus du stockage');
    expect(EloService.instance.nbEchouees, echoueesAvant,
        reason: '« rien à écrire » n\'est pas une exception');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T6 — `importerDepuisBackup` et `reinitialiser` suivent le même contrat
  // ═════════════════════════════════════════════════════════════════════════
  test('T6 — importerDepuisBackup / reinitialiser : meme contrat que W2',
      () async {
    // (a) succès
    final okImport = await EloService.instance
        .importerDepuisBackup(_payloadElo());
    final okReinit = await EloService.instance.reinitialiser();
    // (b) refus
    _store.refus.add('flutter.$kCleElo');
    final refusImport = await EloService.instance
        .importerDepuisBackup(_payloadElo());
    final refusReinit = await EloService.instance.reinitialiser();
    // (c) exception
    _store.refus.clear();
    _store.levent.add('flutter.$kCleElo');
    final excImport = await EloService.instance
        .importerDepuisBackup(_payloadElo());

    // ignore: avoid_print
    print('[T6] import=${okImport.name} | reinit=${okReinit.name} | '
        'importRefus=${refusImport.name} | reinitRefus=${refusReinit.name} | '
        'importException=${excImport.name}');

    expect(okImport, EtatPersistanceElo.persistee);
    expect(okReinit, EtatPersistanceElo.persistee);
    expect(refusImport, EtatPersistanceElo.refusee);
    expect(refusReinit, EtatPersistanceElo.refusee);
    expect(excImport, EtatPersistanceElo.echouee);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T7 — COMPTEURS HISTORIQUES préservés sous refus de stockage
  //
  //  Le refus du stockage survient APRÈS les deux contrôles : ni
  //  `nbRefusParReset` ni `nbRefusParGeneration` ne doivent bouger.
  // ═════════════════════════════════════════════════════════════════════════
  test('T7 — refus du stockage : compteurs historiques de reset INCHANGES',
      () async {
    await _preparerElo();
    final resetAvant = EloService.instance.nbRefusParReset;
    final genAvant = EloService.instance.nbRefusParGeneration;
    final generationAvant = EloService.instance.generationCache;

    _store.refus.add('flutter.$kCleElo');

    final etat = await EloService.instance.mettreAJourApresArrivee(
      arrivee: <int>[1, 2],
      partants: <ZtPartant>[_partant(1), _partant(2)],
      discipline: kDisc,
      courseKey: kCleCourse, // ★ B2-e : identité exigée pour journaliser
    );

    // ignore: avoid_print
    print('[T7] etat=${etat.name} | '
        'reset=$resetAvant→${EloService.instance.nbRefusParReset} | '
        'gen=$genAvant→${EloService.instance.nbRefusParGeneration} | '
        'generation=${EloService.instance.generationCache}');

    expect(EloService.instance.nbRefusParReset, resetAvant,
        reason: 'un refus du STOCKAGE n\'est pas un refus par RESET');
    expect(EloService.instance.nbRefusParGeneration, genAvant,
        reason: 'un refus du STOCKAGE n\'est pas un refus par GÉNÉRATION');
    expect(EloService.instance.generationCache, generationAvant);
    expect(EloService.instance.nbEcrituresEnCours, 0,
        reason: 'le registre de drainage doit être vide après l\'attente');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T8 — ÉCRITURE PENDANT LE RESET : `abandonneeParReset`, contrôle 1
  // ═════════════════════════════════════════════════════════════════════════
  test('T8 — ecriture pendant reset : abandonneeParReset, nbRefusParReset bouge',
      () async {
    await _preparerElo();
    final resetAvant = EloService.instance.nbRefusParReset;

    // On suspend le reset DANS la suppression des clés, pour que l'écriture
    // ELO naisse PENDANT l'effacement (scénario V29-A / contrôle 1).
    final entree = Completer<void>();
    final liberation = Completer<void>();

    final reset = EloService.instance.executerResetComplet(() async {
      if (!entree.isCompleted) entree.complete();
      await liberation.future;
    });

    await entree.future;

    final etat = await EloService.instance.mettreAJourApresArrivee(
      arrivee: <int>[1, 2],
      partants: <ZtPartant>[_partant(1), _partant(2)],
      discipline: kDisc,
      courseKey: kCleCourse, // ★ B2-e : identité exigée pour journaliser
    );

    liberation.complete();
    await reset;

    // ignore: avoid_print
    print('[T8] etat=${etat.name} | '
        'refusParReset=$resetAvant→${EloService.instance.nbRefusParReset}');

    expect(etat, EtatPersistanceElo.abandonneeParReset,
        reason: 'le contrôle 1 doit produire `abandonneeParReset`');
    expect(EloService.instance.nbRefusParReset, resetAvant + 1,
        reason: 'le compteur historique doit continuer d\'être incrémenté '
            'EXACTEMENT au même endroit');
  });
}
