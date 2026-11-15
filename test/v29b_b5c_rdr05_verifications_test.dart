// ═══════════════════════════════════════════════════════════════════════════
//  B5c — ÉTAPE 7 / R-DR-05 — VÉRIFICATIONS CIBLÉES AVANT APPLICATION
//
//  OBJET : ÉTABLIR LES FAITS. AUCUNE MODIFICATION DE PRODUCTION.
//
//  Trois vérifications demandées :
//    1. les deux écritures de `_charger()` — `remove('elo_ratings_v1')` (l.82)
//       et `setBool('elo_orphelins_purges_v1')` (l.104) — face à un reset,
//       notamment lors du PREMIER chargement ;
//    2. M26 : une écriture ELO née PENDANT l'effacement des clés — la
//       génération suffit-elle, ou `_resetEnCours` est-il indispensable ?
//    3. échec partiel du reset : propagation, `_ratings`, `_charge`, disque,
//       nouveau reset, blocage permanent éventuel de la barrière.
//
//  ── DISPOSITIF ────────────────────────────────────────────────────────────
//  Store instrumenté avec TROIS capacités :
//    • verrou sur `setValue` (comme V28/V29) ;
//    • verrou sur `remove`     ← AJOUT, indispensable pour suspendre la
//      boucle d'effacement du reset à un index choisi ;
//    • politique de panne sur `remove` (retour `false`, clé NON supprimée)
//      ← AJOUT, pour provoquer un échec partiel déterministe.
//
//  ⚠️ ORDRE D'EXÉCUTION : `_charge` n'a AUCUN setter. Le test « F » exige
//     `_charge == false`, ce qui n'est vrai qu'UNE fois par processus. Il est
//     donc déclaré EN PREMIER et son `setUp` ne touche pas à EloService.
//     Une garde explicite échoue bruyamment si cette précondition est
//     violée, plutôt que de produire un résultat trompeur.
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
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Store instrumenté
// ───────────────────────────────────────────────────────────────────────────
class _StoreControle extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  // Verrou sur setValue
  Completer<void>? _verrouSet;
  String? _cleSetSuspendue;
  Completer<void>? _entreeSet;

  // Verrou sur remove
  Completer<void>? _verrouRemove;
  String? _cleRemoveSuspendue;
  Completer<void>? _entreeRemove;

  // Politique de panne sur remove
  final Set<String> _echecsRemove = <String>{};

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
    if (_echecsRemove.any((c) => key.contains(c))) {
      journal.add('REM-REFUS $key');
      return false; // clé NON supprimée : le cache local est déjà vidé par
                    // `remove()` de shared_preferences, mais le store refuse
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

  Completer<void> armerSuspensionRemove(String cle) {
    final entree = Completer<void>();
    _entreeRemove = entree;
    _cleRemoveSuspendue = cle;
    _verrouRemove = Completer<void>();
    return entree;
  }

  void libererSet() {
    final v = _verrouSet;
    _verrouSet = null;
    if (v != null && !v.isCompleted) v.complete();
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
    _echecsRemove.clear();
  }

  void provoquerEchecRemove(String cle) => _echecsRemove.add(cle);

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];
}

// ignore: library_private_types_in_public_api
late _StoreControle store;

void _installerStore() {
  store = _StoreControle();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

/// Avance jusqu'à ce que [condition] soit vraie, ou épuisement du budget.
/// DÉTERMINISTE : aucune durée, seulement des tours de boucle bornés.
Future<bool> _attendreQue(bool Function() condition, [int maxTours = 800]) async {
  for (var i = 0; i < maxTours; i++) {
    if (condition()) return true;
    await Future<void>.delayed(Duration.zero);
  }
  return condition();
}

Future<void> _laisserProgresser([int tours = 24]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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

const String kDiscipline = 'Trot Attelé';
const String kEloKey = 'elo_ratings_v2';
const String kEloTsKey = 'elo_ratings_v2_ts';
const String kEloV1Key = 'elo_ratings_v1';
const String kPurgeKey = 'elo_orphelins_purges_v1';
const String kCleTardive = 'alert_config_v2'; // index 86 sur 107

String kCleElo(String nom, [String discipline = kDiscipline]) {
  final nomNorm = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  return '$nomNorm|${EloService.normaliserDiscipline(discipline)}';
}

final List<ZtPartant> kPartants = List.generate(6, (i) => _partant(i + 1));
const List<int> kArrivee = <int>[1, 2, 3];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ⚠️ Ce setUp ne touche PAS à EloService : le premier test du fichier doit
  //    trouver `_charge == false`.
  setUp(() {
    _installerStore();
  });

  tearDown(() {
    store.desarmer();
    store.libererSet();
    store.libererRemove();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  VÉRIFICATION 1 — LES DEUX ÉCRITURES DE `_charger()` FACE À UN RESET
  //
  //  Ce test DOIT être le premier du fichier : `_charge` n'a pas de setter et
  //  ne repasse jamais à `false`. Une seule exécution par processus peut donc
  //  observer le PREMIER chargement.
  //
  //  Chemin réel de `_charger()` quand `elo_ratings_v2` est absent et
  //  `elo_ratings_v1` présent (l.66-108) :
  //      getInstance                                    (l.61)
  //      getString('elo_ratings_v2') → null
  //      getString('elo_ratings_v1') → contenu  → import des entrées « NOM| »
  //      await prefs.remove('elo_ratings_v1')           (l.82)  ← ÉCRITURE 1
  //      _charge = true                                 (l.92)
  //      purge des clés finissant par « | »             (l.100-103)
  //      await prefs.setBool('elo_orphelins_purges_v1')  (l.104) ← ÉCRITURE 2
  //      await _sauvegarder()  si orphelins trouvés     (l.107) ← ÉCRITURE 3
  //
  //  On suspend le chargement SUR l'écriture 2 (clé effacée par le reset à
  //  l'index 69), on laisse le reset finir, puis on libère : les écritures
  //  2 et 3 se terminent APRÈS l'effacement.
  // ═══════════════════════════════════════════════════════════════════════
  test('V29-F — écritures de `_charger()` au PREMIER chargement pendant un reset',
      () async {
    final elo = EloService.instance;

    // État disque d'une installation v1 : ancienne clé présente, aucune v2,
    // aucun drapeau de purge. L'entrée est un « orphelin » (discipline vide).
    store.semer(
        kEloV1Key,
        jsonEncode(<String, dynamic>{
          'ANCIEN_CHEVAL': EloScore(
            nomCheval: 'ANCIEN_CHEVAL',
            rating: 1900.0,
            nbCourses: 50,
          ).toJson(),
        }));
    expect(store.contient(kEloKey), isFalse, reason: 'TÉMOIN : pas de v2');
    expect(store.contient(kPurgeKey), isFalse, reason: 'TÉMOIN : pas de drapeau');

    // ── Suspension sur l'écriture 2 ───────────────────────────────────────
    final entree = store.armerSuspensionSet(kPurgeKey);
    final chargement = EloService.init();

    final suspendu = await _attendreEntreeOuFin(entree, chargement);
    // GARDE DE PRÉCONDITION : si `_charge` valait déjà `true`, `init()` aurait
    // rendu la main sans jamais lire le disque.
    expect(store.journal.contains('GETALL'), isTrue,
        reason: 'GARDE : `_charger()` a bien lu le disque — donc `_charge` '
            'valait `false` au départ. Sinon ce test ne mesurerait rien.');
    expect(suspendu, isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : le chargement doit être suspendu sur '
            '`setBool(elo_orphelins_purges_v1)`');

    // TÉMOIN : l'écriture 1 (`remove`) a déjà eu lieu AVANT la suspension.
    expect(store.journal.contains('REM flutter.$kEloV1Key'), isTrue,
        reason: 'TÉMOIN : `remove(elo_ratings_v1)` s\'exécute avant l\'écriture 2');
    debugPrint('V29-F avant reset : journal=${store.journal}');

    // ── Reset complet, mené jusqu'au bout ─────────────────────────────────
    await BackupService.instance.reinitialiserComplet();

    final purgeApresReset = store.contient(kPurgeKey);
    final eloApresReset = store.contient(kEloKey);
    debugPrint('V29-F reset terminal : purge=$purgeApresReset '
        'elo_v2=$eloApresReset v1=${store.contient(kEloV1Key)}');

    expect(purgeApresReset, isFalse,
        reason: 'TÉMOIN : le reset a bien enlevé le drapeau (index 69)');
    expect(eloApresReset, isFalse,
        reason: 'TÉMOIN : le reset a bien enlevé elo_ratings_v2 (index 13)');
    expect(store.contient(kEloV1Key), isFalse,
        reason: 'TÉMOIN : elo_ratings_v1 absent — soit par le reset, soit par '
            'l\'écriture 1 de `_charger()` : les deux sont destructrices');

    // ── Libération : les écritures 2 et 3 se terminent APRÈS le reset ─────
    store.libererSet();
    await chargement;
    await _laisserProgresser();

    final purgeFinal = store.contient(kPurgeKey);
    final eloFinal = store.contient(kEloKey);
    final contenuFinal = store.lire(kEloKey);
    var clesFinales = <String>[];
    if (contenuFinal is String) {
      clesFinales =
          (jsonDecode(contenuFinal) as Map<String, dynamic>).keys.toList();
    }
    debugPrint('V29-F après libération : purge=$purgeFinal elo_v2=$eloFinal '
        'cles=$clesFinales RAM=${elo.nbChevauxSuivis}');

    // ── FAIT 1a : `setBool` recrée le drapeau APRÈS l'effacement ──────────
    // NON CORRIGÉ, et c'est la décision D-M2 : cette écriture n'est PAS
    // passée par `_sauvegarder()`, donc la barrière ne la couvre pas.
    expect(purgeFinal, isTrue,
        reason: 'COMPORTEMENT RÉSIDUEL DOCUMENTÉ (D-M2) : '
            '`setBool(elo_orphelins_purges_v1, true)` (l.104) recrée la clé '
            'supprimée par le reset. Effet NUISIBLE NUL : c\'est un booléen de '
            'contrôle, et sa réécriture rend la purge idempotente');

    // ── FAIT 1b : `_sauvegarder()` (l.107) est ACCEPTÉE — et c'est logique ─
    //
    // Elle passe bien par la barrière (D-M2), mais elle NAÎT APRÈS la fin
    // complète du reset : au moment de la capture de génération, `_resetEnCours`
    // est retombé à `false` et la génération courante est celle qu'elle
    // capture. Les DEUX contrôles passent donc légitimement.
    //
    // ⇒ La barrière ne peut PAS refuser une écriture née après le reset. Ce
    //   n'est pas un défaut du correctif : c'est la frontière du mécanisme,
    //   déjà établie en R-DR-02 (le contrôle de génération est per-écriture,
    //   pas par transaction). Ce qui compte ici est la CONSÉQUENCE.
    expect(eloFinal, isTrue,
        reason: 'COMPORTEMENT RÉSIDUEL DOCUMENTÉ : `_sauvegarder()` appelée '
            'depuis `_charger()` naît APRÈS le reset et n\'est donc pas '
            'refusée — les deux contrôles passent légitimement');

    // ── FAIT 1c : MAIS la map écrite est VIDE — aucun rating ne ressuscite ─
    expect(clesFinales, isEmpty,
        reason: 'FAIT CAPITAL : la map réécrite est VIDE, pour DEUX raisons '
            'cumulatives : (1) les orphelins ont été retirés de `_ratings` '
            'l.103 AVANT la sauvegarde ; (2) le `finally` du reset a vidé '
            '`_ratings` entre-temps. Aucune donnée ELO ancienne n\'est '
            'réinjectée par ce chemin');

    // ── FAIT 1d : aucune ancienne valeur ELO ne ressuscite par ce chemin ──
    final ratingAncienBranche = elo.getRating('ANCIEN_CHEVAL');
    debugPrint('V29-F ANCIEN_CHEVAL en RAM=$ratingAncienBranche '
        'clésDisque=$clesFinales');
    expect(clesFinales.any((k) => k.contains('ANCIEN_CHEVAL')), isFalse,
        reason: 'FAIT CAPITAL : l\'entrée migrée depuis v1 a été purgée de '
            '`_ratings` avant l\'écriture — ce chemin ne peut PAS réinjecter '
            'un ancien rating sur le disque');
    expect(elo.nbChevauxSuivis, 0,
        reason: 'FAIT : la RAM reste vide — le reset n\'est pas annulé');

    // ── Conclusion sur `remove('elo_ratings_v1')` ─────────────────────────
    // NON MODIFIÉ (D-M2). Cette écriture ne fait que SUPPRIMER : idempotente,
    // elle ne peut rien ressusciter quel que soit l'ordre.
    final nbRemV1 =
        store.journal.where((e) => e == 'REM flutter.$kEloV1Key').length;
    debugPrint('V29-F nb REM elo_ratings_v1 = $nbRemV1');
    expect(nbRemV1, greaterThanOrEqualTo(1),
        reason: 'TÉMOIN : au moins une suppression de v1 a eu lieu');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  VÉRIFICATION 2 — M26 : écriture NÉE PENDANT l'effacement des clés
  //
  //  La boucle du reset est suspendue sur la clé TARDIVE `alert_config_v2`
  //  (index 86/107). À cet instant, `elo_ratings_v2` (index 13) et
  //  `elo_ratings_v1` (index 15) sont DÉJÀ supprimées, et la boucle n'a plus
  //  aucune clé ELO à parcourir ensuite.
  //
  //  On lance alors une mise à jour ELO COMPLÈTE. Deux mécanismes possibles :
  //    • `_resetEnCours`  → refus immédiat (contrôle 1) ;
  //    • génération       → refus SEULEMENT si la génération capturée diffère
  //      de la courante. Or l'incrément est à l'ÉTAPE 1, donc la mise à jour,
  //      née APRÈS, capture la valeur DÉJÀ incrémentée : contrôle 2 PASSE.
  //  → La génération seule ne peut pas couvrir ce cas : `_resetEnCours` est
  //    indispensable. C'est ce que ce test établit.
  // ═══════════════════════════════════════════════════════════════════════
  test('V29-I / M26 — écriture née PENDANT l\'effacement : la génération ne suffit pas',
      () async {
    final elo = EloService.instance;

    // Précondition : le service est chargé (test F précédent) et vide.
    elo.viderMemoirePourResetComplet();
    await _laisserProgresser(4);

    store.armerSuspensionRemove(kCleTardive);
    final reset = BackupService.instance.reinitialiserComplet();

    final suspendu = await _attendreQue(() => store.journal
        .any((e) => e == 'REM flutter.$kCleTardive'));
    expect(suspendu, isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : la boucle est suspendue sur la clé '
            'tardive');
    expect(store.journal.contains('REM flutter.$kEloKey'), isTrue,
        reason: 'TÉMOIN : les clés ELO (index 13) sont DÉJÀ supprimées, et '
            'aucune ne sera repassée ensuite (index 13 < 86)');

    // ── Écriture née ICI, pendant l'effacement ───────────────────────────
    final refusResetAvant = elo.nbRefusParReset;
    final refusGenAvant = elo.nbRefusParGeneration;
    final indexDebutEcriture = store.journal.length;

    final maj = elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
    );
    await maj;
    await _laisserProgresser(4);

    final ecritPendant = store.contient(kEloKey);
    final deltaReset = elo.nbRefusParReset - refusResetAvant;
    final deltaGen = elo.nbRefusParGeneration - refusGenAvant;
    final journalEcriture =
        store.journal.skip(indexDebutEcriture).where((e) => e.contains(kEloKey));
    debugPrint('V29-I écriture née pendant l\'effacement : '
        'RAM=${elo.nbChevauxSuivis} disque=$ecritPendant '
        'deltaReset=$deltaReset deltaGen=$deltaGen '
        'journal=${journalEcriture.toList()}');

    expect(elo.nbChevauxSuivis, greaterThan(0),
        reason: 'TÉMOIN : la mise à jour a bien calculé ses deltas en RAM');

    // ── CORRECTION : refusée par le CONTRÔLE 1, et par lui SEUL ──────────
    expect(ecritPendant, isFalse,
        reason: 'CORRECTION R-DR-05 : l\'écriture née pendant l\'effacement '
            'est REFUSÉE — elle ne recrée donc pas la clé supprimée');
    expect(deltaReset, 1,
        reason: 'PREUVE : c\'est bien le CONTRÔLE 1 (`_resetEnCours`) qui '
            'refuse');
    expect(deltaGen, 0,
        reason: 'PREUVE D\'ISOLATION : le CONTRÔLE 2 n\'est PAS sollicité — '
            'l\'écriture est née APRÈS l\'incrément de génération, donc sa '
            'génération est à jour. La génération SEULE ne couvrirait pas ce '
            'scénario : `_resetEnCours` est indispensable (réponse à M26)');
    expect(journalEcriture.toList(), isEmpty,
        reason: 'CORRECTION : aucune écriture disque n\'est même tentée');

    // ── Fin du reset : rien n\'a été recréé, RAM et disque cohérents ─────
    store.libererRemove();
    await reset;

    final survit = store.contient(kEloKey);
    final nbApres = elo.nbChevauxSuivis;
    debugPrint('V29-I après fin du reset : disque=$survit RAM=$nbApres');

    expect(survit, isFalse,
        reason: 'CORRECTION : la clé n\'existe plus — elle n\'a pas été '
            'recréée pendant l\'effacement');
    expect(nbApres, 0,
        reason: 'CORRECTION : la RAM est vidée par le `finally` — RAM et '
            'disque sont COHÉRENTS');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  VÉRIFICATION 3 — ÉCHEC PARTIEL DU RESET
  //
  //  On provoque un refus de suppression sur une clé TARDIVE (`alert_config_v2`,
  //  index 86). Les clés ELO (index 13, 14, 15) sont donc supprimées AVANT.
  //  `BackupService` collecte l'échec et lève une `StateError`.
  //
  //  Point structurel à mesurer : `viderMemoirePourResetComplet()` est à la
  //  l.1486, c'est-à-dire APRÈS la fermeture du bloc qui lève (l.1479). Sur
  //  ce chemin, elle n'est donc JAMAIS exécutée.
  // ═══════════════════════════════════════════════════════════════════════
  test('V29-H — échec partiel : propagation, `_ratings`, `_charge`, disque, nouveau reset',
      () async {
    final elo = EloService.instance;

    // ── Établir un état ELO réel, persisté ────────────────────────────────
    await elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
    );
    final nbAvant = elo.nbChevauxSuivis;
    expect(nbAvant, greaterThan(0), reason: 'TÉMOIN : ratings en RAM');
    expect(store.contient(kEloKey), isTrue, reason: 'TÉMOIN : clé sur le disque');

    // ── Panne déterministe sur une clé TARDIVE ────────────────────────────
    // ⚠️ La clé doit EXISTER sur le disque : sans elle, sa « survie » après
    //    refus ne mesurerait rien (`remove` refuserait une clé absente).
    store.semer(kCleTardive, 'sentinelle');
    expect(store.contient(kCleTardive), isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : la clé tardive existe sur le disque');
    store.provoquerEchecRemove(kCleTardive);

    // La génération est mesurée AVANT et APRÈS : son incrément doit avoir lieu
    // même sur le chemin d'échec (il est à l'étape 1, avant tout `await`).
    // Sans cela, une écriture née avant le reset et achevée après lui ne
    // serait pas invalidée par le contrôle 2.
    final genAvant = elo.generationCache;

    Object? erreur;
    StackTrace? pile;
    try {
      await BackupService.instance.reinitialiserComplet();
    } catch (e, st) {
      erreur = e;
      pile = st;
    }
    final genApres = elo.generationCache;
    debugPrint('V29-H génération : $genAvant → $genApres');

    debugPrint('V29-H erreur=${erreur.runtimeType}');
    debugPrint('V29-H message=${erreur is Error ? erreur.toString().split("\n").first : erreur}');

    // ── 3a. Propagation de la StateError ORIGINALE ────────────────────────
    expect(erreur, isNotNull,
        reason: 'FAIT : l\'échec remonte au lieu d\'être avalé');
    expect(erreur, isA<StateError>(),
        reason: 'FAIT : c\'est bien la StateError de `BackupService` (C1-a) '
            'qui parvient à l\'appelant');
    expect(erreur.toString(), contains('Reset complet INCOMPLET'),
        reason: 'FAIT : le message d\'origine est préservé');
    expect(erreur.toString(), contains(kCleTardive),
        reason: 'FAIT : la clé survivante est nommée dans le message');
    expect(erreur.toString(),
        contains('Les suppressions déjà réussies ne sont PAS annulées'),
        reason: 'FAIT : la sémantique « pas une transaction annulée » est '
            'préservée');
    debugPrint('V29-H pile présente=${pile != null}');

    // ── 3a-bis. La génération a bien été incrémentée sur le chemin d'échec ─
    expect(genApres, genAvant + 1,
        reason: 'FAIT : l\'incrément de génération est à l\'ÉTAPE 1, donc AVANT '
            'tout `await` — il a lieu même quand l\'effacement échoue. '
            'C\'est ce qui permet au contrôle 2 d\'invalider une écriture née '
            'avant le reset et achevée après lui (mutation M23)');

    // ── 3b. État de `_ratings` — VIDÉ MALGRÉ L'ÉCHEC (décision D-M1) ──────
    final nbApresEchec = elo.nbChevauxSuivis;
    debugPrint('V29-H _ratings après échec : $nbApresEchec (avant $nbAvant)');

    expect(nbApresEchec, 0,
        reason: 'CORRECTION R-DR-05 (D-M1) : le vidage est dans le `finally` '
            'de `executerResetComplet`, donc INCONDITIONNEL — même sur le '
            'chemin d\'échec, `_ratings` est vidé. Avant le correctif, '
            'l\'appel était APRÈS le bloc qui lève et n\'était jamais atteint');

    // ── 3c. Données restant sur le disque ─────────────────────────────────
    final eloDisque = store.contient(kEloKey);
    final tsDisque = store.contient(kEloTsKey);
    final v1Disque = store.contient(kEloV1Key);
    final tardiveDisque = store.contient(kCleTardive);
    debugPrint('V29-H disque : elo_v2=$eloDisque ts=$tsDisque v1=$v1Disque '
        'tardive=$tardiveDisque');

    expect(eloDisque, isFalse,
        reason: 'FAIT : les clés ELO (index 13-15) ont été supprimées AVANT '
            'le refus (index 86)');
    expect(tsDisque, isFalse, reason: 'FAIT : idem pour le timestamp');
    expect(v1Disque, isFalse, reason: 'FAIT : idem pour la relique v1');
    expect(tardiveDisque, isTrue,
        reason: 'FAIT : la clé refusée survit bien sur le disque — '
            'l\'échec est donc PARTIEL, pas total');

    // ── 3d. COHÉRENCE RAM/disque malgré l'échec ──────────────────────────
    // Avant correctif : RAM peuplée + disque ELO vide = divergence.
    // Après : RAM vidée + disque ELO vide = COHÉRENT.
    expect(nbApresEchec, 0,
        reason: 'CORRECTION (D-M1) : RAM vidée');
    expect(eloDisque, isFalse,
        reason: 'CORRECTION : disque vide de clés ELO — RAM et disque ne '
            'divergent PLUS après un échec partiel');

    // ── 3e. Service opérationnel après l'échec (`_charge` inchangé) ───────
    // `_charge` n'est pas touché par le reset : il reste `true`. Effet
    // observable : la mise à jour suivante fonctionne sans relire le disque
    // et réécrit la clé absente depuis la RAM.
    final maj2 = elo.mettreAJourApresArrivee(
      arrivee: kArrivee,
      partants: kPartants,
      discipline: kDiscipline,
    );
    var maj2Terminee = false;
    maj2.whenComplete(() => maj2Terminee = true).ignore();
    final aboutie = await _attendreQue(() => maj2Terminee);
    debugPrint('V29-H maj après échec terminée=$aboutie '
        'RAM=${elo.nbChevauxSuivis} disque=${store.contient(kEloKey)}');

    expect(aboutie, isTrue,
        reason: 'FAIT : aucune mise à jour n\'est bloquée après l\'échec — '
            'le service reste opérationnel');
    expect(store.contient(kEloKey), isTrue,
        reason: 'FAIT : et elle réécrit la clé absente depuis la RAM, ce qui '
            'est cohérent avec `_charge == true`');

    // ── 3f. Barrière non bloquée : un SECOND reset aboutit ────────────────
    // On retire la panne. Aucune restauration automatique n'est inventée :
    // on vérifie seulement que la barrière n'est pas restée fermée.
    store.desarmer();
    final refusIaAvant = IaMemoryService.instance.nbEcrituresRefuseesParReset;

    Object? erreur2;
    try {
      await BackupService.instance.reinitialiserComplet();
    } catch (e) {
      erreur2 = e;
    }
    final refusIaApres = IaMemoryService.instance.nbEcrituresRefuseesParReset;

    debugPrint('V29-H second reset : erreur=$erreur2 '
        'RAM=${elo.nbChevauxSuivis} disque=${store.contient(kEloKey)} '
        'refusIA $refusIaAvant→$refusIaApres');

    expect(erreur2, isNull,
        reason: 'FAIT CAPITAL : un SECOND reset aboutit — la barrière d\''
            'EloService a bien un `finally`, elle n\'est donc pas restée '
            'fermée après l\'échec (comme celles d\'IA et d\'Alertes)');
    expect(elo.nbChevauxSuivis, 0,
        reason: 'FAIT : et cette fois le vidage RAM a bien lieu');
    expect(store.contient(kEloKey), isFalse,
        reason: 'FAIT : disque et RAM redeviennent cohérents');
    expect(store.contient(kCleTardive), isFalse,
        reason: 'FAIT : la clé précédemment refusée est maintenant supprimée');
  });
}
