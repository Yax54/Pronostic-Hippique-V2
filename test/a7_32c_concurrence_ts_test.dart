// ═══════════════════════════════════════════════════════════════════════════
//  A7 — ÉTAPE 3.2 / LOT 2 : CONCURRENCE ET PERSISTANCE (PREUVES CIBLÉES)
//
//  Ce fichier ne teste AUCUNE règle métier. Il ne touche NI aux formules ELO,
//  NI aux coefficients K, NI aux poids/seuils IA, NI au TOP3, NI au mécanisme
//  de reset. Il MESURE deux comportements déjà écrits en 3.2.
//
//  TEST E — reset pendant `setInt()` sur `elo_ratings_v2_ts`
//  ─────────────────────────────────────────────────────────
//  Le scénario E est le seul des cinq fenêtres de concurrence qui n'était
//  couvert par AUCUN test : `v29` suspend `setValue` sur la clé des ratings
//  (`armerSuspensionSet(kEloKey)`), jamais sur `_ts`. Mesuré :
//    grep -rn "armerSuspension.*Ts" test/  → aucune occurrence.
//
//  Ce que le registre `_ecrituresEnCours` doit garantir ici :
//  `f` (la future de `_executerSauvegarde`) n'est retirée du registre QUE par
//  `f.whenComplete(...)` (elo_service l.271), c'est-à-dire après la fin
//  COMPLÈTE de `f` — donc après `setInt`, pas après `setString`. Le drain du
//  reset (l.594-602) attend cette même future. Conséquence attendue : aucune
//  suppression ne commence tant que `setInt` est suspendu.
//
//  ⚠️ PIÈGE DE DISPOSITIF, ÉVITÉ PAR CONSTRUCTION
//  ──────────────────────────────────────────────
//  Le store de `v29` suspend sur `key.contains(_cleSuspendue!)` (l.120).
//  Or `'flutter.elo_ratings_v2_ts'.contains('elo_ratings_v2')` est VRAI :
//  armer sur la clé des ratings armerait AUSSI `_ts`, et confondrait les deux
//  fenêtres. Le store ci-dessous compare les clés par ÉGALITÉ STRICTE.
//
//  TEST R — exception pendant l'écriture de `elo_ratings_v2`
//  ─────────────────────────────────────────────────────────
//  Fige la différence assumée en 3.2 (et documentée en C2) : `setString` lève
//  ⇒ `_ts` est NÉANMOINS tentée, alors qu'avant 3.2 les deux `await` vivaient
//  dans un seul `try` et `_ts` était sautée. L'état principal reste `echouee`.
//
//  ⚠️ LIMITE DE DURABILITÉ PHYSIQUE — REDITE, ELLE EST CENTRALE
//  ────────────────────────────────────────────────────────────
//  Le store est en mémoire. `SharedPreferences` côté Android n'appelle jamais
//  `.commit()` (7 `.apply()` mesurés dans `SharedPreferencesPlugin.kt`). Un
//  `setString → true` n'est donc PAS une preuve d'écriture physique, et aucun
//  test ci-dessous ne prétend le contraire. Ce qui est mesuré est l'ORDRE des
//  opérations et l'ÉTAT RETOURNÉ, pas la survie au redémarrage.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/services/elo_service.dart';

// ── Clés, SANS le préfixe natif (forme utilisée par `prefs.setX`) ──────────
const String kCleElo = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';

// ── Clés, AVEC le préfixe natif (forme utilisée par le store) ─────────────
const String kStoreElo = 'flutter.$kCleElo';
const String kStoreTs = 'flutter.$kCleTs';

/// Valeur SEMÉE pour `_ts` avant chaque test. Sert de témoin : pendant la
/// suspension, c'est elle qu'on doit encore lire.
const int kValTsSemee = 111;

// ───────────────────────────────────────────────────────────────────────────
//  Store contrôlé
//
//  ⚠️ DIFFÉRENCE DÉLIBÉRÉE AVEC LE STORE DE `v29` : la suspension est armée
//  sur une clé EXACTE (`key == _cleSuspendue`), pas sur un `contains`. C'est
//  la seule façon de distinguer `elo_ratings_v2` de `elo_ratings_v2_ts`, dont
//  la première est un préfixe de la seconde.
// ───────────────────────────────────────────────────────────────────────────
class _StoreTs extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};

  /// Journal ORDONNÉ de tout ce qui est demandé au stockage.
  /// Entrées possibles : `GETALL`, `SET-ENTREE <clé>`, `SET-OK <clé>`,
  /// `REM <clé>`, `REM-DIRECT <clé>`, `CLEAR`.
  final List<String> journal = <String>[];

  /// Clés dont l'écriture doit LEVER une exception.
  final Set<String> levent = <String>{};

  String? _cleSuspendue;
  Completer<void>? _verrouSuspendu;
  Completer<void>? _entreeSuspendue;

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
    if (_cleSuspendue != null && key == _cleSuspendue) {
      final verrou = _verrouSuspendu;
      if (verrou != null) {
        final entree = _entreeSuspendue;
        _entreeSuspendue = null;
        if (entree != null && !entree.isCompleted) entree.complete();
        await verrou.future;
      }
    }
    if (levent.contains(key)) {
      throw StateError('panne simulée sur $key');
    }
    _valeurs[key] = value;
    journal.add('SET-OK $key');
    return true;
  }

  /// Arme la suspension sur `cle` (forme AVEC préfixe `flutter.`).
  /// Retourne la future complétée dès que la suspension est ATTEINTE.
  Completer<void> armerSuspension(String cle) {
    final entree = Completer<void>();
    _entreeSuspendue = entree;
    _cleSuspendue = cle;
    _verrouSuspendu = Completer<void>();
    return entree;
  }

  void liberer() {
    final v = _verrouSuspendu;
    _verrouSuspendu = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  // ── Helpers (clé SANS préfixe pour l'appelant) ─────────────────────────
  void poser(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');

  /// Effacement direct, utilisé pour fournir le callback de reset du test.
  /// Journalisé distinctement (`REM-DIRECT`) pour ne jamais être confondu
  /// avec un `REM` émis par la boucle de suppression réelle.
  void effacerDirect(String cle) {
    journal.add('REM-DIRECT flutter.$cle');
    _valeurs.remove('flutter.$cle');
  }

  /// Valeur brute détenue pour `cle` (forme SANS préfixe), ou `null`.
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  // ── Comptages sur le journal ───────────────────────────────────────────
  int get nbSetEntreeElo => journal.where((e) => e == 'SET-ENTREE $kStoreElo').length;
  int get nbSetOkElo     => journal.where((e) => e == 'SET-OK $kStoreElo').length;
  int get nbSetEntreeTs  => journal.where((e) => e == 'SET-ENTREE $kStoreTs').length;
  int get nbSetOkTs      => journal.where((e) => e == 'SET-OK $kStoreTs').length;
  int get nbRemDirect    => journal.where((e) => e.startsWith('REM-DIRECT ')).length;
}

// ignore: library_private_types_in_public_api
late _StoreTs _store;

void _monter() {
  _store = _StoreTs();
  SharedPreferencesStorePlatform.instance = _store;
  SharedPreferences.resetStatic();
  // Le singleton EloService survit d'un test à l'autre : on remet la RAM à
  // zéro. Aucun compteur public n'est remis à zéro (il n'en existe pas) :
  // toutes les assertions de compteur sont donc des DELTAS, comme v29/v29b.
  EloService.instance.viderMemoirePourResetComplet();
  SharedPreferences.resetStatic();
}

/// Vidage BORNÉ de la boucle d'événements. Aucune assertion ne repose sur une
/// durée : les observables sont le journal, l'état du store et les compteurs.
Future<void> _laisserProgresser([int tours = 30]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, dynamic> _payloadElo() => <String, dynamic>{
      for (final n in <String>['A7E ALPHA', 'A7E BRAVO'])
        '$n|TROT_ATTELE': <String, dynamic>{
          'nom': n, 'rating': 1550.0, 'nb': 8, 'var': 1.25,
        },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_monter);

  // ═════════════════════════════════════════════════════════════════════════
  //  TEST E — RESET PENDANT `setInt()` SUR `elo_ratings_v2_ts`
  //
  //  Les neuf points exigés sont numérotés dans les assertions ci-dessous.
  // ═════════════════════════════════════════════════════════════════════════
  test('E — reset pendant setInt(_ts) : le drain attend la future ELO entiere',
      () async {
    final elo = EloService.instance;

    // ── État de départ : les DEUX clés existent déjà sur le disque.
    //    Indispensable : sans cela, « les deux clés sont absentes après le
    //    reset » serait vrai même sans aucune suppression, donc VACUE.
    _store.poser(kCleElo, jsonEncode(<String, dynamic>{'ANCIEN|PLAT': 1}));
    _store.poser(kCleTs, kValTsSemee);

    // ── Suspension armée sur `_ts` SEULE, par égalité stricte.
    final entree = _store.armerSuspension(kStoreTs);

    // ── Écriture lancée SANS être attendue.
    //    `importerDepuisBackup` ne passe pas par `_charger()` : la RAM est
    //    peuplée puis `_sauvegarder()` est appelée directement.
    final maj = elo.importerDepuisBackup(_payloadElo());

    await entree.future;

    // ignore: avoid_print
    print('[LOT2-E] suspension atteinte — journal=${_store.journal}');

    // ① `setString` sur `elo_ratings_v2` s'est TERMINÉ.
    expect(_store.journal.contains('SET-OK $kStoreElo'), isTrue,
        reason: '① `setString($kCleElo)` doit être TERMINÉ avant que `_ts` '
            'ne soit tentée : c\'est l\'ordre de `_executerSauvegarde`');
    expect(_store.nbSetEntreeElo, 1,
        reason: '① une seule écriture des ratings a été tentée');
    expect(_store.nbSetOkElo, 1,
        reason: '① et elle a été confirmée par le store');

    // ② `setInt` sur `_ts` est SUSPENDU.
    expect(_store.journal.contains('SET-ENTREE $kStoreTs'), isTrue,
        reason: '② l\'écriture de `_ts` a bien été ENTRÉE');
    expect(_store.journal.contains('SET-OK $kStoreTs'), isFalse,
        reason: '② et elle n\'est PAS terminée : elle est suspendue');

    // ③ La future ELO reste inscrite dans `_ecrituresEnCours`.
    //    Preuve structurelle : `f` n'est retirée du registre que par
    //    `f.whenComplete` (elo_service l.271), donc seulement à la fin
    //    COMPLÈTE de `f` — `setInt` compris.
    expect(elo.nbEcrituresEnCours, 1,
        reason: '③ le registre retient encore la future pendant `setInt`');
    expect(elo.nbChevauxSuivis, greaterThan(0),
        reason: '③ témoin : les ratings sont déjà en RAM, seule l\'écriture '
            'de `_ts` est en vol');

    // ── ④ Reset complet démarré, SANS être attendu.
    //    Il est déclaré AVANT le `try` et TOUJOURS libéré/attendu dans le
    //    `finally` : sans cela, une assertion qui échoue laisserait
    //    `_resetEnCours == true` pour les tests suivants, qui recevraient
    //    tous `abandonneeParReset`. Défaut RÉELLEMENT rencontré pendant la
    //    mise au point (test R faussé en cascade), donc corrigé ici.
    final indexAvantReset = _store.journal.length;
    final remParReset = <String>[];
    var entreEffacement = 0;
    var resetTermine = false;
    final reset = elo.executerResetComplet(() async {
      entreEffacement++;
      _store.effacerDirect(kCleElo);
      _store.effacerDirect(kCleTs);
      remParReset.addAll(_store.journal.skip(indexAvantReset));
      await Future<void>.delayed(Duration.zero);
    });
    reset.whenComplete(() => resetTermine = true).ignore();

    try {
      await _laisserProgresser();

      // ⑤ Le DRAIN retient le reset : il attend la fin de la future ELO.
      expect(resetTermine, isFalse,
          reason: '⑤ le reset est RETENU dans son étape 2 (drain)');
      expect(elo.nbEcrituresEnCours, 1,
          reason: '⑤ témoin : la future est toujours en vol, le drain l\'attend');

      // ⑥ Aucune suppression ne commence avant la libération de `_ts`.
      expect(entreEffacement, 0,
          reason: '⑥ le callback d\'effacement n\'a PAS été atteint');
      final suppressionsPendant = _store.journal
          .skip(indexAvantReset)
          .where((e) => e.startsWith('REM'));
      expect(suppressionsPendant, isEmpty,
          reason: '⑥ AUCUNE suppression n\'a commencé : la clé ne peut donc '
              'pas être recréée après coup (protection V29-A/B appliquée à `_ts`)');
      expect(_store.contient(kCleElo), isTrue,
          reason: '⑥ témoin : la clé des ratings, écrite pendant le vol, est '
              'toujours là — le reset ne l\'a pas encore effacée');
      // ⚠️ TÉMOIN CORRIGÉ (mesuré) : `_ts` était SEMÉE au départ, donc la clé
      // EXISTE déjà. La suspension empêche de l'ÉCRASER, pas de la créer. Le
      // bon témoin est donc « l'ancienne valeur est toujours en place », et
      // non « la clé est absente » — première version, fausse, corrigée ici.
      expect(_store.lire(kCleTs), kValTsSemee,
          reason: '⑥ témoin : `_ts` porte encore la valeur SEMÉE — la nouvelle '
              'n\'a pas été posée, l\'écriture est bien suspendue');
    } finally {
      // ── Libération INCONDITIONNELLE : `setInt` s'achève, PUIS le reset
      //    efface. Le `finally` garantit qu'aucun reset ne survit au test.
      _store.liberer();
    }

    // ── Clôture : l'écriture se termine, puis le reset efface.
    final indexLiberation = _store.journal.length;
    final etat = await maj;
    await reset;

    final journalApres = _store.journal.skip(indexLiberation).toList();
    final iSetOkTs = _store.journal.indexOf('SET-OK $kStoreTs');
    final iPremierRem = _store.journal.indexWhere((e) => e.startsWith('REM'));

    // ignore: avoid_print
    print('[LOT2-E] apres liberation — etat=${etat.name} | '
        'journalApres=$journalApres | iSetOkTs=$iSetOkTs | '
        'iPremierRem=$iPremierRem | '
        'elo=${_store.contient(kCleElo)} ts=${_store.contient(kCleTs)} | '
        'enCours=${elo.nbEcrituresEnCours} RAM=${elo.nbChevauxSuivis} | '
        'entreEffacement=$entreEffacement');

    // ⑦ Après libération : l'écriture se termine, PUIS le reset efface.
    expect(_store.journal.contains('SET-OK $kStoreTs'), isTrue,
        reason: '⑦ `setInt` s\'est terminée après la libération');
    expect(iSetOkTs, greaterThanOrEqualTo(0),
        reason: '⑦ la fin de `_ts` est bien journalisée');
    expect(iPremierRem, greaterThan(iSetOkTs),
        reason: '⑦ ORDRE PROUVÉ : la fin de l\'écriture (`SET-OK _ts`, '
            'index $iSetOkTs) précède la PREMIÈRE suppression '
            '(index $iPremierRem). C\'est exactement ce que le drain garantit');
    expect(entreEffacement, 1,
        reason: '⑦ le callback d\'effacement a été atteint APRÈS la '
            'libération, et une seule fois');

    // ⑧ Les deux clés sont absentes après le reset.
    expect(_store.contient(kCleElo), isFalse,
        reason: '⑧ `$kCleElo` est absente : écrite pendant le vol, PUIS '
            'supprimée — elle n\'a pas ressuscité');
    expect(_store.contient(kCleTs), isFalse,
        reason: '⑧ `$kCleTs` est absente pour la même raison');
    expect(_store.nbRemDirect, 2,
        reason: '⑧ les deux suppressions ont bien eu lieu');

    // ⑨ Le registre est vidé.
    expect(elo.nbEcrituresEnCours, 0,
        reason: '⑨ `nbEcrituresEnCours == 0` : le drain a abouti');
    expect(elo.nbChevauxSuivis, 0,
        reason: '⑨ témoin : le `finally` du reset a vidé la RAM');
    expect(etat, EtatPersistanceElo.persistee,
        reason: 'témoin : l\'écriture ELO avait été CONFIRMÉE avant le reset — '
            'c\'est bien sa PERSISTANCE qui a été effacée ensuite');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  TEST R — EXCEPTION PENDANT L'ÉCRITURE DE `elo_ratings_v2`
  //
  //  Fige la différence assumée en 3.2 : `_ts` est NÉANMOINS tentée.
  // ═════════════════════════════════════════════════════════════════════════
  test('R — setString leve : etat echouee, _ts neanmoins tentee, aucun rejeu',
      () async {
    final elo = EloService.instance;

    // RAM peuplée pour que `_sauvegarder()` ait quelque chose à sérialiser.
    await elo.importerDepuisBackup(_payloadElo());
    await _laisserProgresser();

    // Remise à zéro du journal APRÈS la préparation, pour ne compter que
    // l'écriture mesurée.
    _store.journal.clear();

    // Compteurs de référence — DELTAS obligatoires (singleton cumulatif).
    final echoueesAvant  = elo.nbEchouees;
    final echecsTsAvant  = elo.nbEchecsTs;
    final persisteesAvant = elo.nbPersistees;

    // Injection de l'exception sur la clé des RATINGS uniquement.
    _store.levent.add(kStoreElo);

    final etat = await elo.reinitialiser();

    await _laisserProgresser();

    final deltaEchouees   = elo.nbEchouees - echoueesAvant;
    final deltaEchecsTs   = elo.nbEchecsTs - echecsTsAvant;
    final deltaPersistees = elo.nbPersistees - persisteesAvant;

    // ignore: avoid_print
    print('[LOT2-R] etat=${etat.name} | deltaEchouees=$deltaEchouees | '
        'deltaEchecsTs=$deltaEchecsTs | deltaPersistees=$deltaPersistees | '
        'tentativesElo=${_store.nbSetEntreeElo} | '
        'tsTentee=${_store.nbSetEntreeTs} | tsOk=${_store.nbSetOkTs} | '
        'erreur=${elo.derniereErreurEcriture.runtimeType}');

    // ── État principal : `echouee`, et non `refusee` ni `persistee`.
    expect(etat, EtatPersistanceElo.echouee,
        reason: 'l\'exception sur `elo_ratings_v2` doit produire `echouee`');

    // ── Le compteur des échecs augmente EXACTEMENT de 1.
    expect(deltaEchouees, 1,
        reason: 'un seul échec doit être compté — ni zéro, ni deux');
    expect(deltaPersistees, 0,
        reason: 'aucune persistance confirmée ne doit être comptée');
    expect(elo.derniereErreurEcriture, isA<StateError>(),
        reason: 'l\'exception doit rester CONSERVÉE, pas seulement imprimée');

    // ── L'écriture secondaire `_ts` est NÉANMOINS tentée.
    //    Avant 3.2, les deux `await` vivaient dans UN SEUL `try` : une
    //    exception sur `setString` sautait `setInt` (0 tentative). Depuis
    //    3.2 `_ts` est dans un `try` SÉPARÉ. C'est la différence documentée
    //    en C2, ici FIGÉE par un test.
    expect(_store.nbSetEntreeTs, 1,
        reason: '`_ts` doit être TENTÉE malgré l\'échec des ratings');
    expect(_store.nbSetEntreeElo, 1,
        reason: 'les ratings ne sont tentés qu\'UNE fois');

    // ── Le défaut secondaire NE TRANSFORME PAS l'état principal.
    //    Ici `_ts` réussit : si elle avait pu écraser l'état, on lirait
    //    `persistee`. Ce n'est pas le cas.
    expect(_store.nbSetOkTs, 1,
        reason: 'témoin : `_ts` a réussi');
    expect(etat, isNot(EtatPersistanceElo.persistee),
        reason: 'une `_ts` réussie ne doit JAMAIS promouvoir l\'état à '
            '`persistee` : `_ts` n\'est pas une preuve d\'application ELO');
    expect(deltaEchecsTs, 0,
        reason: 'aucun défaut secondaire à compter ici, `_ts` a réussi — et '
            'le compteur des échecs de ratings ne doit pas le recevoir');

    // ── Aucun rejeu automatique.
    //    On laisse tourner la boucle d'événements et l'on vérifie qu'AUCUNE
    //    seconde tentative n'apparaît. 3.2 n'ouvre aucun rejeu.
    _store.levent.clear(); // si un rejeu existait, il réussirait maintenant
    await _laisserProgresser(60);

    expect(_store.nbSetEntreeElo, 1,
        reason: 'AUCUN REJEU : même après disparition de la panne simulée, '
            'les ratings ne sont pas réécrits automatiquement');
    expect(elo.nbEchouees - echoueesAvant, 1,
        reason: 'aucun échec supplémentaire : rien n\'a été retenté');
    expect(elo.nbPersistees - persisteesAvant, 0,
        reason: 'aucune persistance nouvelle : donc aucun rejeu réussi');
  });
}
