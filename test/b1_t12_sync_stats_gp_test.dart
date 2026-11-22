// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / ÉTAPE 1 — LE G+P FAUX CONTAMINE-T-IL LES STATISTIQUES PAR TYPE ?
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. Aucune modification de lib/ par ce fichier.
//
//  ── LE CHEMIN EXERCÉ EST LE VRAI CHEMIN DE PRODUCTION ────────────────────
//  Ce fichier ne fabrique PAS de liste à la main : il déclenche
//  `PmuProvider.validatePrediction`, exactement comme le fait
//  `predictions_screen.dart:604` quand un ticket Gagnant+Placé à deux mises
//  valides est déclaré gagnant :
//
//      validatePrediction(id, isCorrect: true,
//                         montantMise: null, gainRealise: null)
//
//  `validatePrediction` écrit alors `..isCorrect = isCorrect` (toujours) et
//  `..gainRealise = gain` où `gain` vaut `null` pour un G+P (garde G+P
//  l.500). L'état persisté est donc :
//
//      { typePari: 'Gagnant+Placé', isCorrect: true,
//        gainRealise: null, cote: 18.00, montantMise: 10.00 }
//
//  Puis `_syncStatsTypesIA()` (l.597) transmet `p.gainNet` SANS garde à
//  `IaMemoryService.mettreAJourStatsTypes()`.
//
//  ── CE QUE CE FICHIER MESURE ─────────────────────────────────────────────
//    T1  G+P gagnant SANS gain officiel  → doit contribuer 0,00 €
//        (AVANT correction : contribue 170,00 € — c'est le défaut reproduit)
//    T2  G+P gagnant AVEC gain officiel  → montant conservé (202,00 €)
//    T3  G+P perdant                     → comportement existant conservé
//    T4  Pari simple gagnant             → comportement existant conservé
//    T5  Le ticket SOURCE n'est pas modifié par la synchronisation
//    T6  Le prédicat `gainGagnantPlaceEtabli` vaut bien `false` ici
//
//  ── CE QUE CE FICHIER NE PROUVE PAS (assumé) ─────────────────────────────
//    • il ne monte aucun écran : c'est `predictions_screen.dart` qui appelle
//      `validatePrediction` de cette façon, reproduit ici par appel direct ;
//    • il ne prouve rien sur `ia_performance_screen.dart:649-651`, qui est un
//      SECOND chemin vers les mêmes statistiques et reste hors de cette
//      correction (consigne : ne pas y toucher) ;
//    • il ne modifie ni ne recharge les tickets historiques : l'absence de
//      réécriture est vérifiée par la stabilité du ticket après le sync (T5).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ─────────────────────────── Constantes mesurées ───────────────────────────
//
// Reprises de la fixture B1-T12 (`test/b1_modele_gagnant_place_test.dart`) :
// mise PAR COMPOSANTE 10 €, cote Gagnant 18,00, cote Placé 4,20.
// Gain net réel d'un G+P gagnant : (10×18,00) + (10×4,20) − 20 = 202,00 €.
// Gain net produit par la branche « cote × mise » : (18,00 × 10) − 10 = 170,00 €.
const double kMiseComposante = 10.0;
const double kCoteGagnant = 18.00;
const double kCotePlace = 4.20;
const double kGainGpFaux = 170.0; // ce que la formule actuelle produit
const double kGainGpOfficiel = 202.0; // ce que la règle métier impose

const String kTypeGp = 'Gagnant+Placé';
const String kTypeSimple = 'Simple Gagnant';

UserPrediction _gp({
  bool? isCorrect,
  double? gainRealise,
  double? dividendePmuReel,
}) =>
    UserPrediction(
      id: 'gp_stats_1',
      dateStr: '20/11/2026',
      numReunion: 1,
      numCourse: 10,
      nomCourse: 'PRIX B1-T12',
      hippodrome: 'VINCENNES',
      numeroCheval: 7,
      nomCheval: 'CHEVAL_7',
      cote: kCoteGagnant,
      typePari: kTypeGp,
      createdAt: DateTime(2026, 11, 20, 14, 30),
      isCorrect: isCorrect,
      scoreIA: 70.0,
      montantMise: kMiseComposante,
      gainRealise: gainRealise,
      dividendePmuReel: dividendePmuReel,
      numerosJoues: const <int>[7],
      miseGagnant: kMiseComposante,
      misePlace: kMiseComposante,
      coteGagnant: kCoteGagnant,
      cotePlace: kCotePlace,
    );

UserPrediction _simple({
  bool? isCorrect,
  double montantMise = 20.0,
}) =>
    UserPrediction(
      id: 'simple_stats_1',
      dateStr: '20/11/2026',
      numReunion: 1,
      numCourse: 11,
      nomCourse: 'PRIX B1-T12 SIMPLE',
      hippodrome: 'VINCENNES',
      numeroCheval: 3,
      nomCheval: 'CHEVAL_3',
      cote: kCoteGagnant,
      typePari: kTypeSimple,
      createdAt: DateTime(2026, 11, 20, 14, 0),
      isCorrect: isCorrect,
      scoreIA: 70.0,
      montantMise: montantMise,
      numerosJoues: const <int>[3],
    );

/// Laisse la chaîne asynchrone non attendue se dérouler :
/// `_syncStatsTypesIA()` → `mettreAJourStatsTypes()` → `_load()` → `_save()`.
/// `_syncStatsTypesIA` est « non bloquant » par conception (l.601), donc le
/// test doit rendre la main à l'event loop avant de lire les statistiques.
Future<void> _laisserLaSyncSeTerminer() async {
  for (int i = 0; i < 80; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Déclenche le VRAI chemin : ajout du ticket, validation, synchronisation.
Future<PmuProvider> _validerCommeEnProduction(
  UserPrediction pred, {
  required bool isCorrect,
  double? gainRealise,
  double? montantMise,
}) async {
  final provider = PmuProvider();
  // ★ Le constructeur (`PmuProvider()`, l.25-28) lance `_loadSavedPredictions()`
  //   de façon ASYNCHRONE, et ce chargement commence par `_predictions.clear()`.
  //   Si l'on ajoute le ticket avant qu'il n'ait terminé, il l'EFFACE.
  //   On laisse donc le chargement du constructeur s'achever AVANT d'ajouter.
  await _laisserLaSyncSeTerminer();

  provider.addPrediction(pred);

  final id = provider.predictions
      .firstWhere((e) => e.typePari == pred.typePari && e.id == pred.id)
      .id;

  // Reproduit exactement l'appel de `predictions_screen.dart:604-607`
  // pour un ticket à deux composantes : ni mise ni gain transmis.
  provider.validatePrediction(
    id,
    isCorrect: isCorrect,
    montantMise: montantMise,
    gainRealise: gainRealise,
  );

  await _laisserLaSyncSeTerminer();
  return provider;
}

StatsTypePari? _statDe(String type) {
  final liste = IaMemoryService.instance.statsParType
      .where((s) => s.typePari == type)
      .toList();
  return liste.isEmpty ? null : liste.first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Harnais partagé obligatoire : `IaMemoryService._load()` lit les prefs.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T0 — LE CHEMIN EST BIEN CELUI DE LA PRODUCTION
  //
  //  Avant de mesurer une conséquence, on prouve que l'état atteint est
  //  exactement celui que la production atteint : `isCorrect = true` écrit,
  //  `gainRealise` laissé `null`, et la formule actuelle produisant 170,00 €.
  // ═══════════════════════════════════════════════════════════════════════
  test('T0 — validatePrediction(G+P, gagné) écrit isCorrect=true et '
      'gainRealise=null : la formule produit 170,00 €', () async {
    final provider = await _validerCommeEnProduction(
      _gp(),
      isCorrect: true,
      gainRealise: null,
      montantMise: null,
    );

    final ticket = provider.predictions.firstWhere((p) => p.typePari == kTypeGp);

    // ignore: avoid_print
    print('─── MESURE T0 (état réellement écrit par la production) ────');
    // ignore: avoid_print
    print('  isCorrect            = ${ticket.isCorrect}');
    // ignore: avoid_print
    print('  gainRealise          = ${ticket.gainRealise}');
    // ignore: avoid_print
    print('  montantMise          = ${ticket.montantMise}');
    // ignore: avoid_print
    print('  miseTotaleEngagee    = ${ticket.miseTotaleEngagee}');
    // ignore: avoid_print
    print('  gainNet (formule)    = ${ticket.gainNet}');
    // ignore: avoid_print
    print('  gainGagnantPlaceEtabli = ${ticket.gainGagnantPlaceEtabli}');
    // ignore: avoid_print
    print('────────────────────────────────────────────────────────────');

    expect(ticket.isCorrect, isTrue,
        reason: 'validatePrediction écrit TOUJOURS isCorrect (résultat '
            'sportif) — commentaire de production l.494-496');
    expect(ticket.gainRealise, isNull,
        reason: 'la garde G+P de validatePrediction laisse gainRealise null');
    expect(ticket.montantMise, kMiseComposante,
        reason: 'montantMise non réécrit : il porte la mise PAR composante');
    expect(ticket.gainNet, closeTo(kGainGpFaux, 1e-9),
        reason: '(18,00 × 10) − 10 = 170,00 € — la composante Placé est '
            'ignorée par la formule');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T6 — LE PRÉDICAT EXISTANT EST DÉJÀ SÉMANTIQUEMENT EXACT
  // ═══════════════════════════════════════════════════════════════════════
  test('T6 — gainGagnantPlaceEtabli vaut false sur ce ticket', () async {
    final provider = await _validerCommeEnProduction(
      _gp(),
      isCorrect: true,
      gainRealise: null,
      montantMise: null,
    );

    final ticket = provider.predictions.firstWhere((p) => p.typePari == kTypeGp);
    expect(ticket.gainGagnantPlaceEtabli, isFalse,
        reason: 'G+P gagné SANS gain officiel : le gain n\'est pas établi');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T1 — LE DÉFAUT : 170,00 € ENTRENT DANS LES STATISTIQUES
  //
  //  C'EST LE TEST QUI DOIT ÉCHOUER AVANT LA CORRECTION.
  // ═══════════════════════════════════════════════════════════════════════
  test('T1 — ★ un G+P gagnant SANS gain officiel contribue 0,00 € aux '
      'statistiques, pas 170,00 €', () async {
    await _validerCommeEnProduction(
      _gp(),
      isCorrect: true,
      gainRealise: null,
      montantMise: null,
    );

    final st = _statDe(kTypeGp);

    // ignore: avoid_print
    print('─── MESURE T1 (statistiques par type) ──────────────────────');
    // ignore: avoid_print
    print('  entrée G+P présente  = ${st != null}');
    if (st != null) {
      // ignore: avoid_print
      print('  nbJoues=${st.nbJoues} nbGagnes=${st.nbGagnes} '
          'nbPerdus=${st.nbPerdus}');
      // ignore: avoid_print
      print('  gainNet STATISTIQUÉ  = ${st.gainNet} €');
    }
    // ignore: avoid_print
    print('  gainNet ATTENDU      = 0,00 € (aucun gain établi)');
    // ignore: avoid_print
    print('  gainNet RÉEL métier  = $kGainGpOfficiel € (jamais dans les stats)');
    // ignore: avoid_print
    print('────────────────────────────────────────────────────────────');

    expect(st, isNotNull,
        reason: 'le ticket est résolu (isCorrect=true) : il est compté, '
            'mais sa CONTRIBUTION FINANCIÈRE doit être nulle');
    expect(st!.gainNet, closeTo(0.0, 1e-9),
        reason: 'un G+P sans gain officiel ne doit transmettre AUCUN montant. '
            'Avant correction, la valeur transmise est 170,00 € '
            '(= (18,00 × 10) − 10), un produit cote × mise d\'UNE composante.');

    // La contribution au total des gains ne doit pas non plus être polluée.
    final totalGains = IaMemoryService.instance.statsParType
        .where((s) => s.typePari == kTypeGp)
        .fold<double>(0.0, (s, e) => s + e.gainNet);
    expect(totalGains, closeTo(0.0, 1e-9));
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T2 — G+P AVEC GAIN OFFICIELLEMENT ÉTABLI : MONTANT CONSERVÉ
  // ═══════════════════════════════════════════════════════════════════════
  test('T2 — un G+P dont le gain est officiellement établi conserve son '
      'montant (202,00 €)', () async {
    await _validerCommeEnProduction(
      _gp(),
      isCorrect: true,
      gainRealise: kGainGpOfficiel,
      montantMise: null,
    );

    final ticket = IaMemoryService.instance.statsParType;
    final st = _statDe(kTypeGp);

    // ignore: avoid_print
    print('─── MESURE T2 (G+P avec gain officiel) ─────────────────────');
    // ignore: avoid_print
    print('  types présents       = ${ticket.map((e) => e.typePari).toList()}');
    // ignore: avoid_print
    print('  gainNet STATISTIQUÉ  = ${st?.gainNet} €');
    // ignore: avoid_print
    print('────────────────────────────────────────────────────────────');

    expect(st, isNotNull);
    expect(st!.gainNet, closeTo(kGainGpOfficiel, 1e-9),
        reason: 'gainRealise officiel présent ⇒ gainEtabli=true ⇒ le montant '
            'doit traverser la garde INTACT');
    expect(st.nbGagnes, 1);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T3 — G+P PERDANT : COMPORTEMENT EXISTANT CONSERVÉ
  // ═══════════════════════════════════════════════════════════════════════
  test('T3 — un G+P perdant conserve sa contribution négative '
      '(−10,00 €)', () async {
    await _validerCommeEnProduction(
      _gp(),
      isCorrect: false,
      gainRealise: -kMiseComposante,
      montantMise: null,
    );

    final st = _statDe(kTypeGp);

    // ignore: avoid_print
    print('─── MESURE T3 (G+P perdant) ────────────────────────────────');
    // ignore: avoid_print
    print('  gainNet STATISTIQUÉ  = ${st?.gainNet} €');
    // ignore: avoid_print
    print('────────────────────────────────────────────────────────────');

    expect(st, isNotNull);
    expect(st!.gainNet, closeTo(-kMiseComposante, 1e-9),
        reason: 'une perte G+P est un FAIT : elle est conservée telle quelle. '
            'gainGagnantPlaceEtabli rend true sur un isCorrect=false.');
    expect(st.nbPerdus, 1);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T4 — PARI SIMPLE : COMPORTEMENT EXISTANT CONSERVÉ
  // ═══════════════════════════════════════════════════════════════════════
  test('T4 — un Simple Gagnant gagnant conserve sa contribution '
      '(340,00 €)', () async {
    await _validerCommeEnProduction(
      _simple(),
      isCorrect: true,
      gainRealise: null, // laissé à la formule, comme en production
      montantMise: null,
    );

    final st = _statDe(kTypeSimple);

    // ignore: avoid_print
    print('─── MESURE T4 (pari simple) ────────────────────────────────');
    // ignore: avoid_print
    print('  gainNet STATISTIQUÉ  = ${st?.gainNet} €');
    // ignore: avoid_print
    print('────────────────────────────────────────────────────────────');

    expect(st, isNotNull);
    expect(st!.gainNet, closeTo(340.0, 1e-9),
        reason: '(18,00 × 20) − 20 = 340,00 € — hors G+P, la garde rend true '
            'et la valeur est STRICTEMENT inchangée');
    expect(st.nbGagnes, 1);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T5 — LE TICKET SOURCE N'EST PAS MODIFIÉ PAR LA SYNCHRONISATION
  //
  //  La correction ne doit toucher que la VALEUR TRANSMISE, jamais le ticket,
  //  jamais son `gainNet`, jamais `gainRealise`.
  // ═══════════════════════════════════════════════════════════════════════
  test('T5 — la synchronisation des statistiques ne modifie aucune donnée '
      'du ticket source', () async {
    final provider = await _validerCommeEnProduction(
      _gp(),
      isCorrect: true,
      gainRealise: null,
      montantMise: null,
    );

    final ticket = provider.predictions.firstWhere((p) => p.typePari == kTypeGp);

    // ignore: avoid_print
    print('─── MESURE T5 (intégrité du ticket source) ─────────────────');
    // ignore: avoid_print
    print('  nombre de tickets    = ${provider.predictions.length}');
    // ignore: avoid_print
    print('  isCorrect            = ${ticket.isCorrect}');
    // ignore: avoid_print
    print('  gainRealise          = ${ticket.gainRealise}');
    // ignore: avoid_print
    print('  dividendePmuReel     = ${ticket.dividendePmuReel}');
    // ignore: avoid_print
    print('  gainNet (formule)    = ${ticket.gainNet}');
    // ignore: avoid_print
    print('────────────────────────────────────────────────────────────');

    expect(provider.predictions.length, 1,
        reason: 'aucun ticket créé ni supprimé');
    expect(ticket.isCorrect, isTrue,
        reason: 'le résultat sportif est conservé');
    expect(ticket.gainRealise, isNull,
        reason: 'aucun gain n\'est inventé sur le ticket');
    expect(ticket.dividendePmuReel, isNull,
        reason: 'aucun dividende n\'est inventé sur le ticket');
    expect(ticket.gainNet, closeTo(kGainGpFaux, 1e-9),
        reason: 'la FORMULE `gainNet` est inchangée par cette correction : '
            'le ticket rend toujours 170,00 €. Seule la valeur TRANSMISE aux '
            'statistiques est gardée.');
  });
}
