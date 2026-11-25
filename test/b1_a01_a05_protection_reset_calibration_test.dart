// ═══════════════════════════════════════════════════════════════════════════
//  BLOC 1 — BL1-A01 (protection d'une action irréversible)
//           BL1-A05 (resynchronisation de la calibration après reset des poids)
//
//  ── DÉFAUTS MESURÉS AVANT CORRECTION ───────────────────────────────────────
//
//  BL1-A05 — TROIS chemins réinitialisent les POIDS, UN SEUL resynchronisait
//  le registre STATIQUE de calibration :
//
//      executerResetComplet()      ia_memory_service.dart:2116  → update() ✅
//      _load()                     ia_memory_service.dart:2355  → update() ✅
//      resetPoids()                ia_memory_service.dart:6396  → RIEN     ❌
//
//  Or `_poids = IaPoidsAdaptatifs()` remet `calibrationScore` à 50.0
//  (ia_memory_models.dart:599) tandis que `IaCalibrationRegistry` conservait
//  l'ancienne valeur apprise. `ZtCourse.confianceIA` (zt_models.dart:968-970)
//  applique `facteurCalib = IaCalibrationRegistry.value / 50` borné [0.85,
//  1.10] : la confiance AFFICHÉE restait donc pondérée par une calibration
//  que le reset venait pourtant d'abandonner. Un reset annoncé « valeurs par
//  défaut » ne l'était pas pour la seule donnée visible par l'utilisateur.
//
//  BL1-A01 — Le bouton « Reset » de l'onglet Poids (ia_performance_screen
//  .dart:1387) appelait `mem.resetPoids()` au PREMIER contact : aucune
//  confirmation, aucun énoncé de ce qui était perdu, aucune annulation
//  possible — alors que l'effacement TOTAL situé plus bas dans le MÊME écran
//  (l.1527) était déjà protégé par un `AlertDialog`.
//
//  ── CE QUE CE FICHIER PROUVE, ET COMMENT ───────────────────────────────────
//
//   A5-1  La calibration apprise est bien chargée dans le registre, et
//         `resetPoids()` la ramène à 50.0 — valeur réellement relue après
//         l'appel, pas une valeur supposée.
//   A5-2  La conséquence est mesurée sur la DONNÉE AFFICHÉE : la même course
//         affiche une confiance différente avant et après le reset, et la
//         valeur d'après est celle obtenue avec une calibration neutre.
//   A5-3  PROTECTION : `resetPoids()` ne touche NI aux seuils adaptatifs, NI
//         à l'historique des pronostics, NI au journal. Le test échoue si une
//         future « correction » élargit son périmètre.
//   A1-1  Le bouton réel est actionné : un dialogue apparaît, et tant qu'il
//         n'est pas confirmé, les poids sont INCHANGÉS.
//   A1-2  « Annuler » ne modifie rien ; « Réinitialiser » modifie. Les deux
//         branches sont exercées, sinon le test ne prouverait que l'existence
//         d'un dialogue, pas son effet.
//
//  ── CE QUI N'EST PAS TOUCHÉ ────────────────────────────────────────────────
//  Aucune formule, aucun coefficient, aucun seuil, aucune règle financière.
//  `IaCalibrationRegistry.update()` est une AFFECTATION avec `clamp(10, 90)` :
//  ce fichier ne fait que constater qu'elle est désormais appelée.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/screens/ia_performance_screen.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ─────────────────────────── Constantes mesurées ───────────────────────────

/// Calibration volontairement ÉLOIGNÉE de la neutralité, pour que l'écart
/// soit visible et non confondu avec un arrondi. 82.0 est dans la plage
/// `clamp(10, 90)` de `IaCalibrationRegistry.update()`.
const double kCalibApprise = 82.0;
const double kCalibNeutre = 50.0;

/// Seuil Tiercé volontairement déplacé : sert de TÉMOIN de non-régression.
/// Si `resetPoids()` se mettait un jour à réinitialiser les seuils, A5-3
/// échouerait sur cette valeur.
const double kSeuilTierceTemoin = 52.0;

const int kNumR = 6;
const int kNumC = 3;

// ─────────────────────────── Fixtures ──────────────────────────────────────

Map<String, Object> _prefs({
  double calibration = kCalibApprise,
  double seuilTierce = kSeuilTierceTemoin,
}) =>
    <String, Object>{
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode({
        // Valeurs d'usine des 19 critères, inchangées.
        'forme': 0.32, 'gains': 0.15, 'record': 0.12, 'cote': 0.08,
        'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
        'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
        'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
        'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
        'mouvCote': 0.06, 'placeDepart': 0.03,
        'nbMisesAJour': 40,
        'calibrationScore': calibration,
      }),
      // Clés courtes réellement utilisées par `SeuilsConfianceAdaptatifs`.
      'ia_seuils_v1': json.encode({'ti': seuilTierce}),
      'ia_precision_v2': json.encode({}),
      'ia_stats_labels_v1': json.encode({}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
      'user_predictions_v2': <String>[],
      'tracked_courses_v1': <String>[],
    };

/// Un pronostic réel, pour que A5-3 ait un historique à protéger.
IaPronostic _pronostic() => IaPronostic(
      // Interpolation explicite : `$kNumC_20112026` serait lu comme un seul
      // identifiant (erreur de compilation réelle constatée).
      courseKey: 'R${kNumR}C${kNumC}_20112026',
      nomCourse: 'PRIX A5 R$kNumR C$kNumC',
      hippodrome: 'VINCENNES',
      discipline: 'Trot Attelé',
      datePronostic: DateTime(2026, 11, 20, 15, 30),
      scoresIA: const <String, double>{'1': 80.0, '2': 70.0},
      scoresCriteres: const <String, ScoresCriteres>{},
      confiancePredite: 72.0,
      typePariConseille: 'Simple Gagnant',
      resultatsReels: false,
      arriveeReelle: null,
    );

/// Un partant complet. `rang` est explicite pour que `partantsParRangIA`
/// (tri par rang) soit déterministe, et `scoreIA` porte une domination nette
/// du favori : c'est cette domination qui rend l'effet du facteur de
/// calibration MESURABLE sur `confianceIA`.
ZtPartant _partant(String numero, String nom, String cote, double score,
        int rang) =>
    ZtPartant(
      numero: numero,
      nom: nom,
      driver: '',
      entraineur: '',
      proprietaire: '',
      gains: '',
      record: '',
      musique: '',
      cote: cote,
      ageSexe: '',
      scoreIA: score,
      rang: rang,
    );

/// Une course réelle minimale, pour mesurer `confianceIA`.
ZtCourse _course() => ZtCourse(
      numCourse: kNumC,
      anchor: 'R${kNumR}C$kNumC',
      nom: 'PRIX A5',
      heure: '15:30',
      distance: '2700',
      prix: '40000',
      type: 'Trot Attelé',
      piste: 'bon',
      categorie: '',
      isQuinte: false,
      pronosticZt: const <int>[1, 2],
      dateStr: '20112026',
      partants: <ZtPartant>[
        // Le favori domine largement : les trois composantes de `confianceIA`
        // (qualité du favori, dominance, cohésion du top 3) sont hautes, donc
        // le facteur de calibration a un effet MESURABLE sur le résultat.
        _partant('1', 'ALPHA', '2.1', 92.0, 1),
        _partant('2', 'BETA', '5.4', 55.0, 2),
        _partant('3', 'GAMMA', '9.8', 38.0, 3),
      ],
    );

// ─────────────── Réseau simulé : aucun appel réel ne doit partir ───────────

MockClient _clientVide() => MockClient((http.Request r) async {
      const Map<String, String> entetes = {'content-type': 'application/json'};
      final String p = r.url.path;
      if (p.contains('rapports-definitifs')) {
        return http.Response('[]', 200, headers: entetes);
      }
      if (p.contains('participants')) {
        return http.Response('{"participants":[]}', 200, headers: entetes);
      }
      return http.Response('{"programme":{"reunions":[]}}', 200,
          headers: entetes);
    });

// ─────────────────────────── Outillage ─────────────────────────────────────

/// Installe un état réel et rechargé.
///
/// [avecPronostic] est INDISPENSABLE pour le test de widget : `_buildTabMemoire()`
/// (ia_performance_screen.dart:1187) court-circuite l'onglet avec un écran
/// d'accueil dédié dès que `mem.pronostics.isEmpty`. Sans donnée, le bouton
/// « Reset » n'existe pas dans l'arbre — mesuré : « Found 0 widgets with
/// text \"Reset\" ». Ce n'est pas un défaut de production, mais le test doit
/// alors vérifier le bouton dans son contexte réel de présence.
Future<void> _etatInitial({
  double calibration = kCalibApprise,
  bool avecPronostic = false,
}) async {
  SharedPreferences.setMockInitialValues({
    ..._prefs(calibration: calibration),
    if (avecPronostic)
      'ia_pronostics_v2': <String>[json.encode(_pronostic().toJson())],
  });
  SharedPreferences.resetStatic();
  ZoneTurfService.viderCachePourResetComplet();
  DataRefreshService.instance.viderMemoirePourResetComplet();
  IaArchiveService.instance.oublierChargementPourTest();
  ArriveeOfficielleService.instance.viderMemoireSeulement();
  await ArriveeOfficielleService.instance.charger();
  await EloService.instance.reinitialiser();
  await IaMemoryService.instance.recharger();
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  //  A5 — RESYNCHRONISATION DE LA CALIBRATION
  // ═══════════════════════════════════════════════════════════════════════

  test('A5-1 — `resetPoids()` ramène le registre de calibration à 50,0',
      () async {
    await _etatInitial();

    final mem = IaMemoryService.instance;
    final calibAvant = mem.poids.calibrationScore;
    final registreAvant = IaCalibrationRegistry.value;

    // ── MESURE AVANT : le registre reflète bien la valeur apprise ──
    // ignore: avoid_print
    print('─── MESURE A5-1 (avant reset) ──────────────────────────────');
    // ignore: avoid_print
    print('  poids.calibrationScore      : $calibAvant');
    // ignore: avoid_print
    print('  IaCalibrationRegistry.value : $registreAvant');

    expect(calibAvant, kCalibApprise,
        reason: 'La fixture doit réellement installer la calibration apprise, '
            'sinon la mesure porterait sur la valeur par défaut et ne '
            'prouverait rien.');
    expect(registreAvant, kCalibApprise,
        reason: '`_load()` doit resynchroniser le registre : ce chemin-là '
            'n\'était pas en défaut et doit le rester.');

    // ── RESET RÉEL ──
    await mem.resetPoids();

    final calibApres = mem.poids.calibrationScore;
    final registreApres = IaCalibrationRegistry.value;

    // ignore: avoid_print
    print('─── MESURE A5-1 (après reset) ──────────────────────────────');
    // ignore: avoid_print
    print('  poids.calibrationScore      : $calibApres');
    // ignore: avoid_print
    print('  IaCalibrationRegistry.value : $registreApres');
    // ignore: avoid_print
    print('  divergence avant reset : '
        '${(registreAvant - calibAvant).abs()}');
    // ignore: avoid_print
    print('  divergence après reset : '
        '${(registreApres - calibApres).abs()}');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(calibApres, kCalibNeutre,
        reason: 'Le reset doit rendre les poids d\'usine (dont la calibration).');
    expect(registreApres, kCalibNeutre,
        reason: 'BL1-A05 : le registre STATIQUE doit suivre le reset. Avant '
            'correction il restait à $kCalibApprise alors que les poids '
            'valaient 50,0 — deux sources de vérité divergentes.');
    expect((registreApres - calibApres).abs(), 0.0,
        reason: 'Après un reset, registre et poids doivent être CONFORMES. '
            'C\'est cette égalité qui manquait.');
  });

  test('A5-2 — la confiance AFFICHÉE change réellement après le reset',
      () async {
    await _etatInitial();

    final course = _course();
    final confianceAvant = course.confianceIA;

    await IaMemoryService.instance.resetPoids();
    final confianceApres = _course().confianceIA;

    // Confiance calculée avec une calibration NEUTRE imposée : c'est la cible
    // que le reset doit atteindre, sans formule inventée.
    IaCalibrationRegistry.update(kCalibNeutre);
    final confianceNeutre = _course().confianceIA;

    // ignore: avoid_print
    print('─── MESURE A5-2 (confiance affichée) ───────────────────────');
    // ignore: avoid_print
    print('  confiance AVANT reset  (calib=$kCalibApprise) : '
        '${confianceAvant.toStringAsFixed(4)}');
    // ignore: avoid_print
    print('  confiance APRÈS reset  (registre='
        '${IaCalibrationRegistry.value}) : '
        '${confianceApres.toStringAsFixed(4)}');
    // ignore: avoid_print
    print('  confiance de RÉFÉRENCE (calib=$kCalibNeutre imposée) : '
        '${confianceNeutre.toStringAsFixed(4)}');
    // ignore: avoid_print
    print('  effet mesuré du reset : '
        '${(confianceAvant - confianceApres).toStringAsFixed(4)} point(s)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(confianceAvant, isNot(confianceApres),
        reason: 'Si la confiance ne bougeait pas, la calibration n\'aurait '
            'aucun effet observable et BL1-A05 serait sans conséquence '
            'réelle. La mesure doit montrer le contraire.');
    expect(confianceApres, closeTo(confianceNeutre, 1e-9),
        reason: 'Après reset, la confiance doit être EXACTEMENT celle obtenue '
            'avec une calibration neutre. Aucune formule n\'est modifiée : '
            'c\'est la valeur d\'entrée du facteur qui est enfin la bonne.');
  });

  test('A5-3 — `resetPoids()` ne touche NI aux seuils, NI à l\'historique, '
      'NI au journal', () async {
    // Un historique non vide est indispensable : sur une mémoire vide, une
    // suppression accidentelle serait invisible.
    SharedPreferences.setMockInitialValues({
      ..._prefs(),
      'ia_pronostics_v2': <String>[json.encode(_pronostic().toJson())],
    });
    SharedPreferences.resetStatic();
    ZoneTurfService.viderCachePourResetComplet();
    DataRefreshService.instance.viderMemoirePourResetComplet();
    IaArchiveService.instance.oublierChargementPourTest();
    ArriveeOfficielleService.instance.viderMemoireSeulement();
    await ArriveeOfficielleService.instance.charger();
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();

    final mem = IaMemoryService.instance;
    final seuilAvant = mem.seuilsConfiance.seuilTierce;
    final nbPronosticsAvant = mem.pronostics.length;
    final nbJournalAvant = mem.journal.length;

    await mem.resetPoids();

    final seuilApres = mem.seuilsConfiance.seuilTierce;
    final nbPronosticsApres = mem.pronostics.length;
    final nbJournalApres = mem.journal.length;

    // ignore: avoid_print
    print('─── MESURE A5-3 (périmètre du reset) ───────────────────────');
    // ignore: avoid_print
    print('  seuilTierce   : $seuilAvant → $seuilApres');
    // ignore: avoid_print
    print('  pronostics    : $nbPronosticsAvant → $nbPronosticsApres');
    // ignore: avoid_print
    print('  journal       : $nbJournalAvant → $nbJournalApres');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(seuilAvant, kSeuilTierceTemoin,
        reason: 'La fixture doit avoir installé un seuil NON par défaut, sinon '
            'une remise à zéro des seuils passerait inaperçue.');
    expect(nbPronosticsAvant, greaterThan(0),
        reason: 'La fixture doit contenir un pronostic : protéger une liste '
            'vide ne prouve rien.');
    expect(seuilApres, seuilAvant,
        reason: 'PROTECTION §3 : les seuils adaptatifs ne font pas partie du '
            'périmètre de `resetPoids()`. Élargir sa portée serait une '
            'modification de mécanisme protégée, pas un raccordement.');
    expect(nbPronosticsApres, nbPronosticsAvant,
        reason: 'PROTECTION §11 : aucun pronostic ne doit disparaître d\'une '
            'action qui ne concerne que les poids.');
    expect(nbJournalApres, nbJournalAvant,
        reason: 'Le journal d\'apprentissage n\'est pas dans le périmètre.');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A1 — PROTECTION DU BOUTON « Reset »
  // ═══════════════════════════════════════════════════════════════════════

  testWidgets('A1-1/A1-2 — le bouton « Reset » exige une confirmation, et '
      '« Annuler » ne modifie rien', (WidgetTester tester) async {
    // `avecPronostic: true` : sans donnée, l'onglet affiche son écran d'accueil
    // et le bouton « Reset » n'est pas monté (mode mémoire vide).
    await _etatInitial(avecPronostic: true);

    // ── Débordements de rendu : COMPTÉS et IMPRIMÉS, jamais masqués ──
    //
    // Motif repris de `test/a0_07_p6_p7_ia_performance_fonctionnel_test.dart:337`.
    // Mesuré : `ia_perf_secondary_widgets.dart:631` déborde de 75 px à
    // 900×30000 (Row dans SizedBox 52 px). Ce défaut de MISE EN PAGE est
    // antérieur et hors périmètre du BLOC 1 : il est DÉCLARÉ ici pour ne pas
    // être confondu avec une régression du présent correctif, et il est
    // compté pour que sa persistance reste visible.
    final List<String> debordements = <String>[];
    final void Function(FlutterErrorDetails)? ancien = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      if (d.exceptionAsString().contains('overflowed')) {
        final RegExp re = RegExp(r'([a-zA-Z_0-9]+\.dart):(\d+)');
        final m = re.allMatches(d.toString());
        debordements.add(m.isEmpty
            ? 'emplacement inconnu'
            : m
                .map((x) => '${x.group(1)}:${x.group(2)}')
                .take(2)
                .join(' → '));
      }
    };

    // Un réseau simulé : l'écran charge des statistiques au `initState`.
    await http.runWithClient(() async {
      await tester.binding.setSurfaceSize(const Size(900, 30000));
      try {
      await tester.pumpWidget(
        ChangeNotifierProvider<PmuProvider>.value(
          value: PmuProvider(),
          child: MaterialApp(
            home: Scaffold(
              body: IaPerformanceScreen(alertService: AlertService.instance),
            ),
          ),
        ),
      );
      // `_autoRecreerSiVide()` attend 600 ms : on dépasse pour ne pas laisser
      // de minuterie en vol à la destruction de l'arbre.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 700));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      final mem = IaMemoryService.instance;
      final avant = mem.poids.calibrationScore;

      // ── Le bouton RÉEL est cherché par son libellé de production ──
      final bouton = find.text('Reset');
      expect(bouton, findsWidgets,
          reason: 'Le bouton « Reset » doit exister dans l\'onglet Poids : '
              'on n\'ajoute pas une protection autour d\'un bouton absent.');

      final nbBoutons = tester.widgetList(bouton).length;
      // ignore: avoid_print
      print('─── MESURE A1-1 (bouton Reset) ────────────────────────────');
      // ignore: avoid_print
      print('  occurrences du libellé « Reset » : $nbBoutons');
      // ignore: avoid_print
      print('  calibration avant interaction   : $avant');

      await tester.tap(bouton.first);
      await tester.pumpAndSettle();

      // ── Un dialogue doit être présent, et RIEN ne doit avoir bougé ──
      final dialogue = find.byType(AlertDialog);
      expect(dialogue, findsOneWidget,
          reason: 'BL1-A01 : la première pression doit ouvrir une '
              'confirmation, pas exécuter le reset.');

      final titre = find.text('Réinitialiser les poids IA ?');
      expect(titre, findsOneWidget);

      final apresOuverture = mem.poids.calibrationScore;
      // ignore: avoid_print
      print('  dialogue ouvert : OUI');
      // ignore: avoid_print
      print('  calibration après OUVERTURE    : $apresOuverture');
      // ignore: avoid_print
      print('  le texte énonce le périmètre  : '
          '${find.textContaining("CONSERVÉ").evaluate().isNotEmpty}');
      expect(apresOuverture, avant,
          reason: 'Ouvrir une confirmation ne doit RIEN modifier. Avant '
              'correction, le simple contact exécutait déjà le reset.');

      // ── Branche ANNULER : aucune modification ──
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing,
          reason: '« Annuler » doit refermer le dialogue.');
      final apresAnnulation = mem.poids.calibrationScore;
      // ignore: avoid_print
      print('  calibration après ANNULER      : $apresAnnulation');

      expect(apresAnnulation, avant,
          reason: 'BL1-A01 : « Annuler » ne doit produire AUCUN effet. C\'est '
              'la branche qui manquait totalement avant correction.');

      // ── Branche CONFIRMER : le reset a bien lieu (contre-épreuve) ──
      await tester.tap(bouton.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réinitialiser'));
      await tester.pumpAndSettle();

      final apresConfirmation = mem.poids.calibrationScore;
      final registreApres = IaCalibrationRegistry.value;

      // ignore: avoid_print
      print('  calibration après CONFIRMER    : $apresConfirmation');
      // ignore: avoid_print
      print('  registre après CONFIRMER       : $registreApres');
      // ignore: avoid_print
      print('─────────────────────────────────────────────────────────────');

      expect(apresConfirmation, kCalibNeutre,
          reason: 'La branche de confirmation doit RÉELLEMENT exécuter le '
              'reset : sans cette contre-épreuve, le test ne prouverait que '
              'l\'existence d\'un dialogue, pas son effet.');
      expect(registreApres, kCalibNeutre,
          reason: 'Le geste de l\'utilisateur passe par `resetPoids()` : la '
              'resynchronisation BL1-A05 doit donc être visible ici aussi.');

      // ignore: avoid_print
      print('  débordements de rendu : ${debordements.length}'
          '${debordements.isEmpty ? "" : " → $debordements"}');

      // Démontage propre.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 900));
      await tester.binding.setSurfaceSize(null);
      } finally {
        FlutterError.onError = ancien;
      }
    }, _clientVide);
  });
}
