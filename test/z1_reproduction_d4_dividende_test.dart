// ═══════════════════════════════════════════════════════════════════════════
//  Z1 — REPRODUCTION DE D4 : MAUVAIS RAPPORT PMU (Gagnant+Placé)
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE lib/.
//      Aucun commit. Aucun push. Aucune correction.
//
//  ── CE QUI EST REPRODUIT ─────────────────────────────────────────────────
//  Le chemin RÉEL de l'application, sans copie simplifiée :
//
//      MesPariScreen(initialTab: 1)               (écran Suivi, réel)
//        └─ _CoursesTab                           (mes_paris_screen.dart)
//            └─ _TrackedCourseCard                (classe PRIVÉE)
//                └─ initState → _chargerRapportsPmu()
//                    └─ PmuApiService.fetchRapportsDefinitifs()  (MockClient)
//                        └─ _majGainReelDansProfil(rapports)
//                            └─ matching.reduce((a, b) => a.dividende > b.dividende ? a : b)
//                                (mes_paris_screen.dart:1093)
//
//  Aucune méthode privée n'est appelée directement : tout passe par le
//  montage du VRAI écran et par le VRAI service HTTP intercepté.
//
//  ── SCÉNARIO MÉTIER (mandat) ────────────────────────────────────────────
//    • Pari Gagnant+Placé, cheval n°16.
//    • Rapport PLACÉ du n°16 : ×4,20   (le n°16 est placé, non gagnant)
//    • Rapport GAGNANT du n°7 : ×18,00 (un AUTRE cheval)
//    • Mise : 20 € sur Gagnant + 20 € sur Placé → 40 € engagés (HYPOTHÈSE
//      PROVISOIRE, voir §6-A du mandat — non modifiée ici).
//
//    Attendu (règle métier) :
//      retour brut = 20 € × 4,20 = 84 €      bénéfice net = +44 €
//      → le dividende retenu DOIT être celui du n°16 (combinaison « 16 »)
//
//    Réel (à mesurer) : le code prend le dividende MAXIMAL parmi
//      E_SIMPLE_GAGNANT et E_SIMPLE_PLACE, sans regarder la combinaison.
//      → il retiendra ×18,00, combinaison « 7 » : le rapport d'un autre
//        cheval est attribué au n°16.
//
//  ── CE QUE LE TEST PROUVE, ET CE QU'IL NE PROUVE PAS ────────────────────
//  Il prouve la SÉLECTION DU DIVIDENDE (combinaison + valeur enregistrées).
//  Il ne prouve pas le montant final affiché par l'écran (D8/D5/D6), qui
//  n'est pas l'objet de ce test et n'est donc pas affirmé ici.
//
//  ── STATUT ATTENDU DE CE TEST : ROUGE ───────────────────────────────────
//  Rouge pour la BONNE raison : le TÉMOIN (prédiction chargée, course suivie
//  chargée, rapports servis) doit passer AVANT l'assertion métier.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/main.dart' show NavigationNotifier;
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/screens/mes_paris_screen.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/ia_badges_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_personality_service.dart';
import 'package:pronostic_hippique/services/ia_user_prefs_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  1. CONSTANTES DU SCÉNARIO
// ───────────────────────────────────────────────────────────────────────────

/// Numéro du cheval joué (celui du mandat : n°16).
const int kNumChevalJoue = 16;

/// Numéro de l'AUTRE cheval, gagnant de la course (rapport ×18,00).
const int kNumAutreCheval = 7;

/// Rapport placé du cheval joué — ×4,20 pour 1 € misé (→ 420 centimes).
const double kDividendePlaceAttendu = 4.20;

/// Rapport gagnant de l'autre cheval — ×18,00 pour 1 € misé (→ 1800 centimes).
const double kDividendeGagnantAutre = 18.00;

/// Mise PAR COMPOSANTE (hypothèse provisoire du mandat, §6-A).
/// `_mise` dans bet_bottom_sheet.dart:2878 est bien la mise par composante.
const double kMiseParComposante = 20.0;

const int kNumR = 1;
const int kNumC = 10;

const Map<String, double> _poidsDefaut = {
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
  'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
  'mouvCote': 0.06, 'placeDepart': 0.03,
};

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String _yyyyMMdd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Le corps EXACT renvoyé par `/rapports-definitifs` (format API PMU réel :
/// `dividendePourUnEuro` en CENTIMES, voir pmu_api_service.dart:169).
///
/// Deux courses différentes dans la même réponse :
///   • E_SIMPLE_GAGNANT, combinaison « 7 »  → ×18,00 (autre cheval)
///   • E_SIMPLE_PLACE,   combinaison « 16 » → ×4,20  (cheval joué)
String _corpsRapports() => json.encode([
      {
        'typePari': 'E_SIMPLE_GAGNANT',
        'rapports': [
          {'combinaison': '$kNumAutreCheval', 'dividendePourUnEuro': 1800},
        ],
      },
      {
        'typePari': 'E_SIMPLE_PLACE',
        'rapports': [
          {'combinaison': '$kNumChevalJoue', 'dividendePourUnEuro': 420},
        ],
      },
    ]);

// ───────────────────────────────────────────────────────────────────────────
//  2. FIXTURES
// ───────────────────────────────────────────────────────────────────────────

Map<String, Object> _prefs({List<String>? tracked, List<String>? preds}) =>
    <String, Object>{
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode({
        ..._poidsDefaut,
        'nbMisesAJour': 0,
        'calibrationScore': 50.0,
      }),
      'ia_seuils_v1': json.encode({}),
      'ia_precision_v2': json.encode({}),
      'ia_stats_labels_v1': json.encode({}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
      if (tracked != null) 'tracked_courses_v1': tracked,
      if (preds != null) 'user_predictions_v2': preds,
    };

/// Course suivie RÉELLE, telle que produite par `bet_bottom_sheet` puis
/// `AlertService.ajouterSuivi` : Gagnant+Placé sur le n°16, mise 20 €,
/// résultat déjà connu (gagné) et arrivée persistée.
///
/// `heureDepart` à −90 min : au-delà du seuil de −20 min de
/// `_chargerRapportsPmu` (l.1026), sous la purge 24 h de `_load` (l.517).
TrackedCourse _suiviGagnantPlace(DateTime dep) => TrackedCourse(
      numReunion: kNumR,
      numCourse: kNumC,
      nomCourse: 'PRIX DE BAD GODESBERG',
      hippodrome: 'SAINT-CLOUD',
      heureDepart: dep,
      nomCheval: 'SIM CARD',
      numeroCheval: kNumChevalJoue,
      miseEngagee: kMiseParComposante,
      typePari: 'Gagnant+Placé',
      numerosJoues: const <int>[kNumChevalJoue],
      scoreIA: 89.0,
      cote: kDividendeGagnantAutre,
      isGagne: true,
      arriveeFinale: const <int>[kNumAutreCheval, kNumChevalJoue, 2],
      messageResultat: 'Résultat officiel enregistré',
      // storageKey RÉELLE (avec millisecondes), comme ajouterSuivi l'écrit.
      storageKey: 'R${kNumR}C${kNumC}_${_ddmmyyyy(dep)}_1758281340000',
    );

/// Pari du PROFIL (`PmuProvider`), créé par `bet_bottom_sheet` :
/// montantMise = mise par composante, aucun dividende encore récupéré.
UserPrediction _prediction(DateTime dep) => UserPrediction(
      id: 'pred_d4_1',
      dateStr: _yyyyMMdd(dep),
      numReunion: kNumR,
      numCourse: kNumC,
      nomCourse: 'PRIX DE BAD GODESBERG',
      hippodrome: 'SAINT-CLOUD',
      numeroCheval: kNumChevalJoue,
      nomCheval: 'SIM CARD',
      cote: kDividendeGagnantAutre,
      typePari: 'Gagnant+Placé',
      createdAt: dep,
      scoreIA: 89.0,
      montantMise: kMiseParComposante,
      numerosJoues: const <int>[kNumChevalJoue],
    );

// ───────────────────────────────────────────────────────────────────────────
//  3. RÉSEAU SIMULÉ
// ───────────────────────────────────────────────────────────────────────────

/// Intercepte TOUTES les requêtes PMU. Seul `/rapports-definitifs` porte le
/// corps du scénario ; tout le reste renvoie une charge vide et valide, ce
/// qui laisse le chemin de production inchangé sans données inventées.
Future<T> _avecPmu<T>(Future<T> Function() action) {
  final client = MockClient((request) async {
    final p = request.url.path;
    if (p.contains('rapports-definitifs')) {
      return http.Response(_corpsRapports(), 200,
          headers: {'content-type': 'application/json'});
    }
    if (p.contains('participants')) {
      return http.Response(
          json.encode({'participants': <Map<String, dynamic>>[]}), 200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response(
        json.encode({
          'programme': {'reunions': <Map<String, dynamic>>[]},
        }),
        200,
        headers: {'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

// ───────────────────────────────────────────────────────────────────────────
//  4. MONTAGE DE L'ÉCRAN RÉEL
// ───────────────────────────────────────────────────────────────────────────

/// Débordements de rendu PRÉEXISTANTS de `mes_paris_screen` — mesurés et
/// déjà recensés par `test/a6_mes_paris_ecran_reel_test.dart` (6 emplacements).
/// Ils sont COLLECTÉS et RAPPORTÉS, jamais confondus avec l'objet de Z1.
List<String> _debordements = <String>[];

Future<void> _monterEcranSuivi(WidgetTester tester, PmuProvider pmu) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 2400);
  addTearDown(tester.view.reset);

  _debordements = <String>[];
  final ancien = FlutterError.onError;
  FlutterError.onError = (details) {
    final t = details.toString();
    if (t.contains('overflowed')) {
      _debordements.add(t.replaceAll('\n', ' '));
      return; // bruit de rendu préexistant, sans rapport avec D4
    }
    ancien?.call(details);
  };

  try {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PmuProvider>.value(value: pmu),
          ChangeNotifierProvider<NavigationNotifier>(
              create: (_) => NavigationNotifier()),
          ChangeNotifierProvider.value(value: DataRefreshService.instance),
          ChangeNotifierProvider.value(value: AlertService.instance),
          ChangeNotifierProvider.value(value: IaPersonalityService.instance),
          ChangeNotifierProvider.value(value: IaUserPrefsService.instance),
          ChangeNotifierProvider.value(value: IaBadgesService.instance),
          ChangeNotifierProvider.value(value: IaMemoryService.instance),
        ],
        child: const MaterialApp(
          home: MesPariScreen(initialTab: 1), // 1 = onglet « Suivi »
        ),
      ),
    );
  } finally {
    FlutterError.onError = ancien;
  }

  // Plusieurs pumps : laisse se dérouler la chaîne
  // initState → postFrame → _chargerRapportsPmu → fetch → _majGainReelDansProfil.
  // ⚠️ Durées COURTES : `_chargerRapportsPmu` arme un `.timeout(15 s)` ; avancer
  //    le temps de 15 s déclencherait le timeout au lieu de la réponse.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

// ───────────────────────────────────────────────────────────────────────────
//  5. TEST
// ───────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Z1 / D4 — le dividende du cheval 16 doit être ×4,20, jamais ×18,00 (n°7)',
      (WidgetTester tester) async {
    // ── État simulé : disque posé AVANT tout getInstance() ────────────────
    final dep = DateTime.now().subtract(const Duration(minutes: 90));
    final suivi = _suiviGagnantPlace(dep);
    final pred = _prediction(dep);

    SharedPreferences.setMockInitialValues(_prefs(
      tracked: <String>[json.encode(suivi.toJson())],
      preds: <String>[json.encode(pred.toJson())],
    ));
    ZoneTurfService.viderCachePourResetComplet();
    DataRefreshService.instance.viderMemoirePourResetComplet();
    await IaMemoryService.instance.recharger();
    await AlertService.instance.recharger();

    // ── TÉMOINS : l'état de départ est bien celui du scénario ─────────────
    expect(AlertService.instance.trackedCourses.length, 1,
        reason: 'TÉMOIN : la course suivie doit être chargée depuis le disque');
    final cleStockage = AlertService.instance.trackedCourses.keys.single;
    expect(cleStockage, startsWith('R${kNumR}C${kNumC}_'),
        reason: 'TÉMOIN : la clé réelle de stockage est la storageKey datée');

    final pmu = PmuProvider();
    await pmu.reloadPredictions();
    final predChargee = pmu.getPredictionForCourse(kNumR, kNumC);
    expect(predChargee, isNotNull,
        reason: 'TÉMOIN : le pari du profil doit être présent (sinon le '
            'chemin _majGainReelDansProfil sortirait sans rien faire)');
    expect(predChargee!.dividendeRecupere, isFalse,
        reason: 'TÉMOIN : aucun dividende ne doit être déjà enregistré');

    await _avecPmu(() async {
      await _monterEcranSuivi(tester, pmu);
    });

    // ── MESURE ────────────────────────────────────────────────────────────
    final apres = AlertService.instance.trackedCourses[cleStockage];
    expect(apres, isNotNull, reason: 'TÉMOIN : la course suivie doit survivre');

    // TÉMOIN indispensable : la chaîne a-t-elle seulement écrit un dividende ?
    // Sans ce témoin, un `null` ferait échouer le test pour la MAUVAISE raison
    // (chemin non exécuté) au lieu de révéler le mauvais dividende.
    expect(apres!.dividendePmuReel, isNotNull,
        reason: 'TÉMOIN : le dividende PMU doit avoir été enregistré par '
            '_majGainReelDansProfil (chemin réellement exécuté)');

    final reel = apres.dividendePmuReel!;
    final reelComb = apres.combinaisonPmu;
    final reelGain = pmu.getPredictionForCourse(kNumR, kNumC)?.gainRealise;

    // Trace exploitable dans le journal de test, quelle que soit l'issue.
    // ignore: avoid_print
    print('─── MESURE Z1 / D4 ───────────────────────────────────────────');
    // ignore: avoid_print
    print('  dividendePmuReel enregistré : ×${reel.toStringAsFixed(2)}');
    // ignore: avoid_print
    print('  combinaisonPmu enregistrée  : « $reelComb »');
    // ignore: avoid_print
    print('  gainRealise (profil)        : $reelGain €');
    // ignore: avoid_print
    print('  ATTENDU : ×${kDividendePlaceAttendu.toStringAsFixed(2)} '
        '« $kNumChevalJoue »  (retour 84 € / net +44 €)');
    // ignore: avoid_print
    print('  débordements de rendu préexistants : ${_debordements.length}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    // ── ASSERTION MÉTIER (doit être ROUGE aujourd'hui) ────────────────────
    //
    // Règle : le rapport attribué au n°16 doit être CELUI DU N°16.
    // Le code fautif est
    //   mes_paris_screen.dart:1093
    //     final meilleur = matching.reduce((a, b) => a.dividende > b.dividende ? a : b);
    // qui compare les dividendes SANS regarder `r.combinaison`.
    expect(reelComb, '$kNumChevalJoue',
        reason: 'D4 (mes_paris_screen.dart:1093) — le système attribue au '
            'cheval n°$kNumChevalJoue le rapport du cheval n°$kNumAutreCheval : '
            'il retient le dividende MAXIMAL parmi E_SIMPLE_GAGNANT et '
            'E_SIMPLE_PLACE au lieu du rapport correspondant au cheval joué '
            '(combinaison « $kNumChevalJoue »).');

    expect(reel, closeTo(kDividendePlaceAttendu, 0.001),
        reason: 'D4 — dividende attendu ×${kDividendePlaceAttendu.toStringAsFixed(2)} '
            '(placé du n°$kNumChevalJoue), réel ×${reel.toStringAsFixed(2)}');

    // Retour brut / bénéfice net attendus sous l'hypothèse 40 € engagés.
    final retourBrut = kMiseParComposante * kDividendePlaceAttendu; // 84 €
    final beneficeNet = retourBrut - (kMiseParComposante * 2); // +44 €
    expect(retourBrut, closeTo(84.0, 0.001));
    expect(beneficeNet, closeTo(44.0, 0.001));

    await _demonter(tester);
  });
}
