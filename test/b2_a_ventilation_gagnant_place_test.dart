// ═══════════════════════════════════════════════════════════════════════════
//  LOT B2-A — VENTILATION GAGNANT / PLACÉ À LA CRÉATION DU PARI
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. Aucune autre modification de `lib/`.
//
//  ── CE QUI EST PROUVÉ ICI ─────────────────────────────────────────────────
//  `bet_bottom_sheet.dart` construit un `UserPrediction` (l.2864+) puis
//  l'enregistre via `PmuProvider.addPrediction` (l.2888+). Depuis B1 le
//  modèle porte 4 champs optionnels qui n'étaient renseignés par PERSONNE.
//  B2-A les renseigne POUR LE SEUL TYPE « Gagnant+Placé » :
//
//      miseGagnant = _mise        misePlace = _mise
//      coteGagnant = _coteGagnant cotePlace = _cotePlacee
//
//  Règle métier impérative : 10 € saisis = 10 € Gagnant + 10 € Placé
//  = 20 € engagés. La mise saisie n'est JAMAIS divisée par deux.
//
//  ── LES 3 NIVEAUX DE PREUVE ───────────────────────────────────────────────
//   T1..T3  WIDGET RÉEL : on monte `showBetSheet` (donc le VRAI `_BetSheet`
//           et son VRAI bouton « Valider »), on tape « Gagnant+Placé »,
//           on tape « Valider », et on lit ce qui a été réellement ajouté
//           au `PmuProvider`.
//   T4      PERSISTANCE : les 4 valeurs survivent à `toJson` → disque
//           simulé (SharedPreferences) → `fromJson` (nouveau provider).
//   T5..T7  NON-RÉGRESSION : les autres types de paris laissent les 4
//           champs à null ET conservent `montantMise` / `cote` inchangés.
//
//  ── CE QUI N'EST PAS TOUCHÉ ───────────────────────────────────────────────
//  Aucun calcul financier, aucun rapport PMU officiel, aucune garde A-0,
//  aucun `TrackedCourse`, aucun `race_detail_screen.dart`, aucun
//  `mes_paris_screen.dart`, aucun apprentissage IA.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/main.dart' show NavigationNotifier;
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/gain_calculator.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';
import 'package:pronostic_hippique/utils/type_pari_utils.dart';
import 'package:pronostic_hippique/widgets/bet_bottom_sheet.dart';

// ─────────────────────────── Constantes mesurées ───────────────────────────

/// Cote Gagnant du partant suggéré (champ `cote` de `ZtPartant`, lue par
/// `coteDecimale` zt_models.dart:306-309 après remplacement de ',' par '.').
const double kCoteMarche = 18.0;

/// Nombre de partants du fixture → diviseur Placé 4.0
/// (`gain_calculator.dart:287` : nbPartants >= 8 → 4.0).
const int kNbPartants = 9;

/// Cote Placé ESTIMÉE, recalculée par la MÊME fonction publique que la
/// production (`gain_calculator.dart:296-298`). Aucune valeur inventée.
final double kCotePlaceAttendue =
    GainCalculator.cotePlaceDepuisGagnant(kCoteMarche, kNbPartants);

// NOTE MESURÉE : aucune constante de mise n'est figée ici. `_mise` est
// calculée par `initState` (l.159-164) à partir du score IA du partant
// suggéré — score 82 → 20.0 €. Les tests lisent donc la valeur RÉELLE
// (`p.montantMise`) au lieu de la supposer : aucune constante inventée ne
// peut masquer une division par deux.

/// Date du jour au format ddmmyyyy (format attendu par `heureDateTime`).
String get kDateStr {
  final DateTime n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

/// Heure de départ FUTURE (dans 2 h) : `AlertService._load()` purge au-delà
/// de 24 h **passées** (alert_service.dart:523), une course future n'est
/// jamais purgée. Volontairement relative : aucune date figée.
String get kHeure {
  final DateTime d = DateTime.now().add(const Duration(hours: 2));
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

// ───────────────────────────── Fixtures Zt ────────────────────────────────

ZtPartant _partant(String numero, String nom, String cote, double score) =>
    ZtPartant(
      numero: numero,
      nom: nom,
      driver: 'DRIVER $nom',
      entraineur: 'ENT $nom',
      proprietaire: 'PROP $nom',
      gains: '50000',
      record: '1\'12"0',
      musique: '1a2a3a4a5a',
      cote: cote,
      ageSexe: 'H5',
      statsJockeyCsv: 'J|10|20',
      statsHippodromeCsv: '5|2|3',
      statsEntraineurCsv: 'E|10|20|30|40|5',
      statsTerrainCsv: 'bon|5|2|3',
      joursRepos: 20,
      gainsDernierAn: 20000,
      placeDepartInt: 3,
      poids: 55.0,
      scoreIA: score,
    );

/// 9 partants : le suggéré porte la cote 18.0 et le meilleur score IA, donc
/// `_chevalSelectionne` (initState, l.150-152) et `_coteGagnant` (l.235-239)
/// ont une valeur MESURABLE et non le repli 2.5.
List<ZtPartant> _champ() => <ZtPartant>[
      _partant('7', 'ETOILE DU B2', kCoteMarche.toStringAsFixed(1), 82.0),
      _partant('1', 'ALPHA', '4.5', 61.0),
      _partant('2', 'BRAVO', '6.0', 55.0),
      _partant('3', 'CHARLIE', '8.0', 48.0),
      _partant('4', 'DELTA', '11.0', 42.0),
      _partant('5', 'ECHO', '15.0', 35.0),
      _partant('6', 'FOXTROT', '25.0', 30.0),
      _partant('8', 'GOLF', '32.0', 25.0),
      _partant('9', 'HOTEL', '40.0', 20.0),
    ];

ZtCourse _course({bool quinte = false}) => ZtCourse(
      numCourse: 3,
      anchor: '315',
      nom: 'PRIX B2-A',
      heure: kHeure,
      distance: '2850m',
      prix: '50000',
      type: 'Trot Attelé',
      piste: 'bon',
      categorie: 'Course D',
      isQuinte: quinte,
      pronosticZt: const <int>[7, 1, 2, 3, 4],
      partants: _champ(),
      dateStr: kDateStr,
    );

ZtReunion _reunion({bool quinte = false}) => ZtReunion(
      code: 'R1',
      lieu: 'VINCENNES',
      discipline: 'Trot',
      dateStr: kDateStr,
      courses: <ZtCourse>[_course(quinte: quinte)],
    );

// ────────────── Interception réseau (aucun appel réel) ───────────────────

MockClient _client() => MockClient((http.Request r) async {
      const Map<String, String> h = {'content-type': 'application/json'};
      return http.Response(
        '{"programme":{"reunions":[]}}',
        200,
        headers: h,
      );
    });

Future<T> _sansReseau<T>(Future<T> Function() action) {
  final MockClient client = _client();
  return http.runWithClient(action, () => client);
}

// ─────────────────────── Préférences simulées ─────────────────────────────

const Map<String, double> _poidsDefaut = <String, double>{
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
  'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
  'mouvCote': 0.06, 'placeDepart': 0.03,
};

Map<String, Object> _prefsSimulees() => <String, Object>{
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode(<String, dynamic>{
        ..._poidsDefaut,
        'nbMisesAJour': 0,
        'calibrationScore': 50.0,
      }),
      'ia_seuils_v1': json.encode(<String, dynamic>{}),
      'ia_precision_v2': json.encode(<String, dynamic>{}),
      'ia_stats_labels_v1': json.encode(<String, dynamic>{}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
      'user_predictions_v2': <String>[],
      'tracked_courses_v1': <String>[],
    };

Future<void> _resetServices() async {
  SharedPreferences.setMockInitialValues(_prefsSimulees());
  SharedPreferences.resetStatic();
  ZoneTurfService.viderCachePourResetComplet();
  await EloService.instance.reinitialiser();
  await ArriveeOfficielleService.instance.charger();
  await IaMemoryService.instance.recharger();
  await AlertService.instance.recharger();
}

// ─────────────── Montage du VRAI sheet via son point d'entrée ─────────────

/// Débordements éventuels du vrai sheet : comptés, jamais absorbés.
List<String> _debordements = <String>[];

/// Monte le VÉRITABLE `showBetSheet` — donc le VRAI `_BetSheet` et son VRAI
/// bouton « Valider » — dans un `MaterialApp` hôte, avec les providers que
/// `showBetSheet` lit lui-même (`PmuProvider` l.46, `DataRefreshService`
/// l.47) et ceux lus par `onBetPlaced` (`NavigationNotifier`).
///
/// `_BetSheet` n'arme AUCUN `Timer` ni `.timeout` (grep mesuré : 0), une
/// pompe bornée courte suffit donc.
Future<void> _monterSheet(WidgetTester tester, PmuProvider pmu) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.reset);

  _debordements = <String>[];
  final FlutterExceptionHandler? ancien = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final String t = details.toString();
    if (t.contains('overflowed')) {
      _debordements.add(t.replaceAll('\n', ' '));
      return; // cosmétique, sans rapport avec B2-A : compté et rapporté.
    }
    ancien?.call(details);
  };

  final ZtReunion reunion = _reunion();
  final ZtCourse course = reunion.courses.first;

  late BuildContext ctxHote;

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PmuProvider>.value(value: pmu),
        ChangeNotifierProvider<NavigationNotifier>(
            create: (_) => NavigationNotifier()),
        ChangeNotifierProvider.value(value: DataRefreshService.instance),
        ChangeNotifierProvider.value(value: AlertService.instance),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext c) {
              ctxHote = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  // Ouvre le sheet réel. `chevalSuggere` = le favori (cote 18.0).
  showBetSheet(
    ctxHote,
    reunion: reunion,
    course: course,
    alertService: AlertService.instance,
    chevalSuggere: course.partants.first,
    onBetPlaced: () {},
  );

  try {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  } finally {
    FlutterError.onError = ancien;
  }
}

Future<void> _fermerSuivis() async {
  for (final String k in AlertService.instance.trackedCourses.keys.toList()) {
    await AlertService.instance.retirerSuivi(k);
  }
}

/// Sélectionne le type de pari comme un UTILISATEUR le ferait.

///
/// Le libellé apparaît DEUX fois dans le sheet (mesuré) :
///   • dans le tableau comparatif `_buildTableauComparatifParis` (l.806+),
///     qui est purement documentaire — aucun `onTap` de sélection ;
///   • dans `_buildTypePariSelector` (l.2062), le VRAI sélecteur, dont le
///     `GestureDetector.onTap` (l.2061) pose `_typePariIndex = i`.
///
/// On isole donc le vrai sélecteur par son `AnimatedContainer` cliquable
/// (l.2062) et on tape DEDANS, jamais sur le doublon du tableau.
Future<void> _choisirType(WidgetTester tester, String libelle) async {
  final Finder selecteur = find.ancestor(
    of: find.text(libelle),
    matching: find.byType(AnimatedContainer),
  );
  expect(selecteur, findsWidgets,
      reason: 'la puce « \$libelle » doit exister dans un AnimatedContainer');

  // Le DERNIER candidat est celui de `_buildTypePariSelector` : le tableau
  // comparatif est construit AVANT lui dans la ListView (l.788 puis l.793).
  final Finder cible = selecteur.last;
  await tester.ensureVisible(cible);
  await tester.pump();
  await tester.tap(cible, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 40));
}

/// Tape le bouton « Valider » RÉEL (`_buildValiderBtn`, l.2584 → l.2617).
///
/// ⚠️ La `ListView` de l'onglet « Parier » est PARESSEUSE : le bouton est le
/// dernier enfant (l.797) et n'est construit qu'après défilement. On fait
/// donc défiler comme un utilisateur, puis on vérifie qu'il est bien là.
Future<void> _valider(WidgetTester tester) async {
  Finder bouton = find.textContaining('Valider');
  if (bouton.evaluate().isEmpty) {
    // Défilement réel dans la ListView du sheet.
    final Finder listes = find.byType(ListView);
    expect(listes, findsWidgets, reason: 'la ListView du sheet doit exister');
    await tester.drag(listes.last, const Offset(0, -2600));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    bouton = find.textContaining('Valider');
  }
  expect(bouton, findsWidgets, reason: 'le bouton Valider doit être rendu');
  await tester.tap(bouton.first, warnIfMissed: false);
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Lit les préférences RÉELLEMENT écrites par `PmuProvider._savePredictions`
/// (l.291-299) — aucune valeur en RAM n'est utilisée.
Future<List<Map<String, dynamic>>> _predictionsSurDisque() async {
  final SharedPreferences p = await SharedPreferences.getInstance();
  final List<String> raw = p.getStringList('user_predictions_v2') ?? <String>[];
  return raw
      .map((String s) => jsonDecode(s) as Map<String, dynamic>)
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PmuProvider pmu;

  setUp(() async {
    await _resetServices();
    await _fermerSuivis();
    pmu = PmuProvider();
  });

  // Le vrai bouton « Valider » appelle AUSSI `ajouterSuivi` (l.2846) : on
  // retire les suivis créés pour ne pas polluer le test suivant. Aucun
  // `dispose()` n'est appelé : `AlertService` est un singleton irréversible.
  tearDown(() async {
    await _fermerSuivis();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-T1 — WIDGET RÉEL : « Gagnant+Placé » renseigne les 4 champs.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('B2-T1 — le VRAI sheet, type Gagnant+Placé : les 4 champs B1 '
      'sont renseignés avec miseGagnant = misePlace = mise saisie',
      (WidgetTester tester) async {
    await _sansReseau(() async {
      await _monterSheet(tester, pmu);

      await _choisirType(tester, 'Gagnant+Placé');
      await _valider(tester);

      final List<UserPrediction> preds = pmu.predictions;
      expect(preds, hasLength(1),
          reason: 'un appui sur Valider doit créer EXACTEMENT un pari');

      final UserPrediction p = preds.first;

      // ignore: avoid_print
      print('─── MESURE B2-T1 (widget réel) ───────────────────────────────');
      // ignore: avoid_print
      print('  typePari      : ${p.typePari}');
      // ignore: avoid_print
      print('  montantMise   : ${p.montantMise}');
      // ignore: avoid_print
      print('  cote          : ${p.cote}');
      // ignore: avoid_print
      print('  miseGagnant   : ${p.miseGagnant}');
      // ignore: avoid_print
      print('  misePlace     : ${p.misePlace}');
      // ignore: avoid_print
      print('  coteGagnant   : ${p.coteGagnant}');
      // ignore: avoid_print
      print('  cotePlace     : ${p.cotePlace}');
      // ignore: avoid_print
      print('  miseTotaleEngagee : ${p.miseTotaleEngagee}');
      // ignore: avoid_print
      print('──────────────────────────────────────────────────────────────');

      expect(p.typePari, 'Gagnant+Placé',
          reason: 'TÉMOIN : le type réellement enregistré');

      // ── Les 4 champs B1 sont renseignés ────────────────────────────────
      expect(p.miseGagnant, isNotNull,
          reason: 'B2-A : miseGagnant doit être renseignée');
      expect(p.misePlace, isNotNull,
          reason: 'B2-A : misePlace doit être renseignée');
      expect(p.coteGagnant, isNotNull,
          reason: 'B2-A : coteGagnant doit être renseignée');
      expect(p.cotePlace, isNotNull,
          reason: 'B2-A : cotePlace doit être renseignée');

      // ── RÈGLE MÉTIER : aucune division par deux ────────────────────────
      expect(p.miseGagnant, p.montantMise,
          reason: '10 € saisis = 10 € Gagnant (jamais 5 €)');
      expect(p.misePlace, p.montantMise,
          reason: '10 € saisis = 10 € Placé (jamais 5 €)');
      expect(p.miseGagnant, p.misePlace,
          reason: 'miseGagnant et misePlace sont ÉGALES à la mise saisie');

      // ── 20 € réellement engagés ────────────────────────────────────────
      expect(p.miseTotaleEngagee, (p.montantMise) * 2,
          reason: 'miseTotaleEngagee = mise Gagnant + mise Placé');
      expect(p.misesGagnantPlaceIncompletes, isFalse,
          reason: 'les deux mises sont posées : état COMPLET');

      // ── Les cotes stockées sont celles du chemin réel ───────────────────
      expect(p.coteGagnant, kCoteMarche,
          reason: 'coteGagnant = coteDecimale du partant suggéré (18.0)');
      expect(p.cotePlace, closeTo(kCotePlaceAttendue, 1e-9),
          reason: 'cotePlace = ESTIMATION GainCalculator, pas un rapport PMU');

      // ── `montantMise` et `cote` HISTORIQUES inchangés ──────────────────
      expect(p.cote, kCoteMarche,
          reason: '`cote` garde son sens historique : cote Gagnant affichée');
      expect(p.montantMise, greaterThan(0),
          reason: '`montantMise` reste la mise saisie (inchangé par B2-A)');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-T2 — WIDGET RÉEL : la mise saisie n'est pas divisée par deux.
  //           Vérifié sur la valeur MESURÉE, pas sur une constante du test.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('B2-T2 — deux appuis successifs produisent deux paris avec '
      'des ventilations exactes (aucune division par deux)',
      (WidgetTester tester) async {
    await _sansReseau(() async {
      await _monterSheet(tester, pmu);
      await _choisirType(tester, 'Gagnant+Placé');
      await _valider(tester);

      final UserPrediction p = pmu.predictions.first;
      final double mise = p.montantMise;

      // ignore: avoid_print
      print('─── MESURE B2-T2 ─────────────────────────────────────────────');
      // ignore: avoid_print
      print('  mise saisie (montantMise) : $mise');
      // ignore: avoid_print
      print('  miseGagnant              : ${p.miseGagnant}');
      // ignore: avoid_print
      print('  misePlace                : ${p.misePlace}');
      // ignore: avoid_print
      print('  total engagé             : ${p.miseTotaleEngagee}');
      // ignore: avoid_print
      print('  division par 2 ?          ${p.miseGagnant == mise / 2}');
      // ignore: avoid_print
      print('──────────────────────────────────────────────────────────────');

      expect(mise, greaterThan(0), reason: 'TÉMOIN : une mise a été saisie');
      expect(p.miseGagnant, isNot(closeTo(mise / 2, 1e-9)),
          reason: "RÈGLE MÉTIER : la mise saisie n'est JAMAIS divisée par deux");
      expect(p.misePlace, isNot(closeTo(mise / 2, 1e-9)),
          reason: "RÈGLE MÉTIER : la mise saisie n'est JAMAIS divisée par deux");
      expect(p.miseTotaleEngagee, mise * 2,
          reason: 'le total engagé vaut bien le double de la mise saisie');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-T3 — WIDGET RÉEL : `cotePlace` = estimation, PAS un rapport PMU.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets("B2-T3 — la cote Placé enregistrée est l'estimation "
      "arithmétique pré-course, jamais un rapport officiel",
      (WidgetTester tester) async {
    await _sansReseau(() async {
      await _monterSheet(tester, pmu);
      await _choisirType(tester, 'Gagnant+Placé');
      await _valider(tester);

      final UserPrediction p = pmu.predictions.first;

      // L'estimation est reproductible : (18 - 1) / 4 + 1 = 5.25, bornée par
      // (18 × 0.65) = 11.7 → 5.25 retenu.
      final double estimation =
          GainCalculator.cotePlaceDepuisGagnant(kCoteMarche, kNbPartants);

      // ignore: avoid_print
      print('─── MESURE B2-T3 ─────────────────────────────────────────────');
      // ignore: avoid_print
      print('  coteGagnant enregistrée : ${p.coteGagnant}');
      // ignore: avoid_print
      print('  cotePlace enregistrée   : ${p.cotePlace}');
      // ignore: avoid_print
      print('  estimation recalculée   : $estimation');
      // ignore: avoid_print
      print('──────────────────────────────────────────────────────────────');

      expect(p.cotePlace, closeTo(estimation, 1e-9),
          reason: 'cotePlace = GainCalculator.cotePlaceDepuisGagnant');
      // Le champ PMU officiel reste VIERGE à la création : B2-A ne prétend
      // jamais détenir un rapport officiel.
      expect(p.dividendePmuReel, isNull,
          reason: "aucun rapport PMU officiel n'existe avant la course");
      expect(p.combinaisonPmu, isNull,
          reason: "aucune combinaison PMU officielle avant la course");
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-T4 — PERSISTANCE : les 4 valeurs survivent au disque simulé.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('B2-T4 — persistance : les 4 champs B1 relus depuis le disque '
      'sont identiques aux valeurs du widget', (WidgetTester tester) async {
    await _sansReseau(() async {
      await _monterSheet(tester, pmu);
      await _choisirType(tester, 'Gagnant+Placé');
      await _valider(tester);

      final UserPrediction enMemoire = pmu.predictions.first;

      // ── 1. Ce qui a RÉELLEMENT été écrit sur disque ────────────────────
      final List<Map<String, dynamic>> disque = await _predictionsSurDisque();
      expect(disque, hasLength(1),
          reason: 'TÉMOIN : `_savePredictions` a bien écrit une entrée');

      final Map<String, dynamic> brut = disque.first;
      // ignore: avoid_print
      print('─── MESURE B2-T4 (disque) ────────────────────────────────────');
      for (final String k in <String>[
        'typePari', 'montantMise', 'cote',
        'miseGagnant', 'misePlace', 'coteGagnant', 'cotePlace',
      ]) {
        // ignore: avoid_print
        print('  $k = ${brut[k]}');
      }
      // ignore: avoid_print
      print('──────────────────────────────────────────────────────────────');

      // Sérialisation : les 4 clés existent et ne sont pas nulles
      for (final String k in <String>[
        'miseGagnant', 'misePlace', 'coteGagnant', 'cotePlace',
      ]) {
        expect(brut.containsKey(k), isTrue,
            reason: 'toJson doit écrire la clé $k');
        expect(brut[k], isNotNull,
            reason: '$k doit être sérialisée pour un Gagnant+Placé');
      }

      // ── 2. Relecture par un NOUVEAU provider (fromJson réel) ───────────
      final PmuProvider pmuRelu = PmuProvider();
      await pmuRelu.reloadPredictions();

      expect(pmuRelu.predictions, hasLength(1),
          reason: 'TÉMOIN : relecture disque opérationnelle');
      final UserPrediction relu = pmuRelu.predictions.first;

      // ignore: avoid_print
      print('─── MESURE B2-T4 (après fromJson) ────────────────────────────');
      // ignore: avoid_print
      print('  miseGagnant=${relu.miseGagnant} misePlace=${relu.misePlace} '
          'coteGagnant=${relu.coteGagnant} cotePlace=${relu.cotePlace}');
      // ignore: avoid_print
      print('  montantMise=${relu.montantMise} cote=${relu.cote} '
          'totalEngage=${relu.miseTotaleEngagee}');
      // ignore: avoid_print
      print('──────────────────────────────────────────────────────────────');

      expect(relu.miseGagnant, enMemoire.miseGagnant,
          reason: 'persistance : miseGagnant identique');
      expect(relu.misePlace, enMemoire.misePlace,
          reason: 'persistance : misePlace identique');
      expect(relu.coteGagnant, enMemoire.coteGagnant,
          reason: 'persistance : coteGagnant identique');
      expect(relu.cotePlace, enMemoire.cotePlace,
          reason: 'persistance : cotePlace identique');

      // Les champs historiques ne bougent pas non plus
      expect(relu.montantMise, enMemoire.montantMise);
      expect(relu.cote, enMemoire.cote);
      expect(relu.miseTotaleEngagee, enMemoire.miseTotaleEngagee);
      expect(relu.misesGagnantPlaceIncompletes, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-T5 — NON-RÉGRESSION : « Simple Gagnant » laisse les 4 champs null.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('B2-T5 — Simple Gagnant : les 4 champs B1 restent null et les '
      'valeurs historiques sont inchangées', (WidgetTester tester) async {
    await _sansReseau(() async {
      await _monterSheet(tester, pmu);
      await _choisirType(tester, 'Simple Gagnant');
      await _valider(tester);

      final UserPrediction p = pmu.predictions.first;

      // ignore: avoid_print
      print('─── MESURE B2-T5 ─────────────────────────────────────────────');
      // ignore: avoid_print
      print('  typePari=${p.typePari} montantMise=${p.montantMise} '
          'cote=${p.cote}');
      // ignore: avoid_print
      print('  miseGagnant=${p.miseGagnant} misePlace=${p.misePlace} '
          'coteGagnant=${p.coteGagnant} cotePlace=${p.cotePlace}');
      // ignore: avoid_print
      print('  miseTotaleEngagee=${p.miseTotaleEngagee}');
      // ignore: avoid_print
      print('──────────────────────────────────────────────────────────────');

      expect(p.typePari, 'Simple Gagnant');

      // Aucune ventilation pour un pari mono-composante
      expect(p.miseGagnant, isNull, reason: 'B2-A ne touche pas Simple Gagnant');
      expect(p.misePlace, isNull, reason: 'B2-A ne touche pas Simple Gagnant');
      expect(p.coteGagnant, isNull,
          reason: 'B2-A ne touche pas Simple Gagnant');
      expect(p.cotePlace, isNull, reason: 'B2-A ne touche pas Simple Gagnant');
      expect(p.misesGagnantPlaceIncompletes, isFalse,
          reason: 'les deux sont null → état NON incomplet');

      // `miseTotaleEngagee` retombe sur le sens historique
      expect(p.miseTotaleEngagee, p.montantMise,
          reason: 'CONTRAT B1 : deux null → montantMise historique');

      // Valeurs historiques intactes
      expect(p.cote, kCoteMarche,
          reason: '`cote` inchangée pour Simple Gagnant');
      expect(p.montantMise, greaterThan(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-T6 — NON-RÉGRESSION : « Simple Placé » laisse les 4 champs null.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('B2-T6 — Simple Placé : les 4 champs B1 restent null',
      (WidgetTester tester) async {
    await _sansReseau(() async {
      await _monterSheet(tester, pmu);
      await _choisirType(tester, 'Simple Placé');
      await _valider(tester);

      final UserPrediction p = pmu.predictions.first;

      // ignore: avoid_print
      print('─── MESURE B2-T6 ─────────────────────────────────────────────');
      // ignore: avoid_print
      print('  typePari=${p.typePari} montantMise=${p.montantMise} '
          'cote=${p.cote} miseGagnant=${p.miseGagnant} '
          'cotePlace=${p.cotePlace}');
      // ignore: avoid_print
      print('──────────────────────────────────────────────────────────────');

      expect(p.typePari, 'Simple Placé');
      expect(p.miseGagnant, isNull);
      expect(p.misePlace, isNull);
      expect(p.coteGagnant, isNull);
      expect(p.cotePlace, isNull);
      // `cote` pour Simple Placé vaut la cote Placé affichée (comportement
      // historique de `_coteAffichee`, l.248) — INCHANGÉ par B2-A.
      expect(p.cote, closeTo(kCotePlaceAttendue, 1e-9),
          reason: '`cote` historique de Simple Placé = cote Placé affichée');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-T7 — NON-RÉGRESSION : un combiné (Tiercé) laisse les 4 champs null.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('B2-T7 — Tiercé : les 4 champs B1 restent null et le pari est '
      'bien créé', (WidgetTester tester) async {
    await _sansReseau(() async {
      await _monterSheet(tester, pmu);
      await _choisirType(tester, 'Tiercé');
      await _valider(tester);

      final UserPrediction p = pmu.predictions.first;

      // ignore: avoid_print
      print('─── MESURE B2-T7 ─────────────────────────────────────────────');
      // ignore: avoid_print
      print('  typePari=${p.typePari} numerosJoues=${p.numerosJoues} '
          'miseGagnant=${p.miseGagnant} cotePlace=${p.cotePlace}');
      // ignore: avoid_print
      print('──────────────────────────────────────────────────────────────');

      expect(p.typePari, 'Tiercé');
      expect(p.miseGagnant, isNull, reason: 'B2-A : Tiercé non concerné');
      expect(p.misePlace, isNull);
      expect(p.coteGagnant, isNull);
      expect(p.cotePlace, isNull);
      expect(p.montantMise, greaterThan(0),
          reason: '`montantMise` historique conservée');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-T8 — PREUVE DE MUTATION : sans l'appel `estTypeGagnantPlace`, les
  //           champs seraient null. On vérifie que la reconnaissance du
  //           libellé RÉEL du widget est bien celle de l'utilitaire A-0.
  // ═══════════════════════════════════════════════════════════════════════
  test('B2-T8 — le libellé rendu par le sheet (« Gagnant+Placé ») est bien '
      'reconnu par estTypeGagnantPlace', () {
    // La liste est `_typesPari` de bet_bottom_sheet.dart:128 — rendue telle
    // quelle dans les puces (l.2058-2062) et enregistrée telle quelle
    // (l.2780 : `final typePariLabel = _typesPari[_typePariIndex];`).
    const String libelle = 'Gagnant+Placé';
    // ignore: avoid_print
    print('─── MESURE B2-T8 ─────────────────────────────────────────────');
    // ignore: avoid_print
    print('  libellé du sheet        : "$libelle"');
    // ignore: avoid_print
    print('  estGagnantPlace(libellé) : '
        '${estTypeGagnantPlace(libelle)}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(estTypeGagnantPlace(libelle), isTrue,
        reason: 'la condition du widget doit être VRAIE pour ce libellé');
    expect(estTypeGagnantPlace('Simple Gagnant'), isFalse);
    expect(estTypeGagnantPlace('Simple Placé'), isFalse);
    expect(estTypeGagnantPlace('Tiercé'), isFalse);
  });
}
