// ═══════════════════════════════════════════════════════════════════════════
//  A-0 / P1 + P4 — VALIDATION FONCTIONNELLE SUR LE VÉRITABLE ÉCRAN « MES PARIS »
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE lib/.
//
//  ── CE QUE CE FICHIER EXÉCUTE RÉELLEMENT ──────────────────────────────────
//  Il ne teste PAS une copie de la logique : il monte le VÉRITABLE
//  `MesPariScreen` (onglet « Suivi »), laisse sa carte de course suivie
//  (`_TrackedCourseCard`) exécuter SON `initState`, et laisse courir SES
//  méthodes privées `_verifierResultatAuto()` (protection P1) et
//  `_majGainReelDansProfil()` (protection P4).
//
//  Le réseau PMU est intercepté par `http.runWithClient()` + `MockClient`,
//  exactement comme `v10_a6s_production_path_test.dart` et
//  `z5_widget_d2_suppression_test.dart` (tests existants, verts). Aucun accès
//  à turfinfo.api.pmu.fr : mesuré, la production appelle `http.get` de
//  `package:http` (`zone_turf_service.dart:992`, `pmu_api_service.dart:141`),
//  ces deux points sont donc interceptables.
//
//  ── POURQUOI CE FICHIER EXISTE ────────────────────────────────────────────
//  `a0_03_gardes_structurelles_test.dart` prouve que les gardes EXISTENT et
//  PRÉCÈDENT leurs écritures (lecture de source). Il ne prouve pas qu'elles
//  S'EFFETTENT. Ce fichier le prouve en observant l'état final du
//  `PmuProvider` — c'est-à-dire exactement l'état que lit le Profil.
//
//  ── LE TÉMOIN QUI REND LA PREUVE NON TRIVIALE ────────────────────────────
//  Chaque scénario embarque un pari SIMPLE sur la MÊME course, dans le MÊME
//  passage. Si la garde bloquait tout, le pari simple serait aussi bloqué et
//  le test échouerait : la non-régression est donc prouvée par construction,
//  pas par un fichier séparé.
//
//  ── CHIFFRES (identiques à a0_02, mesurés sur la capture de référence) ────
//    mise G+P     : 20,00 € (une composante affichée ; le G+P en engage deux)
//    cote gagnant : ×18,00   →  gain fictif bloqué = 18×20 − 20 = 340,00 €
//    dividende P. : ×4,20
//
//  ── DÉBORDEMENTS DE RENDU ─────────────────────────────────────────────────
//  Le montage du VRAI écran produit des `RenderFlex` overflow PRÉEXISTANTS,
//  étrangers à A-0 (AppBar, en-tête de carte). Ils sont COMPTÉS et RAPPORTÉS,
//  jamais absorbés en silence ; ils ne peuvent pas faire échouer ce fichier
//  (même précaution que `a6_mes_paris_ecran_reel_test.dart`, qui les recense
//  aux mêmes emplacements).
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

// ─────────────────────────── Constantes du scénario ────────────────────────

const int kNumR = 1;
const int kNumC = 10;
const int kNumeroCheval = 7;

const String kNomCourse = 'PRIX A0 VALIDATION';
const String kHippodrome = 'VINCENNES';

const double kMise = 20.0;
const double kCoteGagnant = 18.00;
const double kDividendePlace = 4.20;

/// Gain FICTIF que produirait une validation G+P avec la seule cote Gagnant.
/// Le test T-P1b vérifie que cet état n'existe pas dans l'application.
const double kGainFictifGP = (kCoteGagnant * kMise) - kMise; // 340,00 €

/// Gain réel d'un Simple Gagnant : c'est le comportement NORMAL à préserver.
const double kGainReelSimple = (kCoteGagnant * kMise) - kMise; // 340,00 €

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

// ─────────────────────────── Fixtures ──────────────────────────────────────

/// Course suivie telle que `bet_bottom_sheet` la produit.
///
/// `heureDepart` à −60 min : au-delà du seuil −5 min de la carte (donc
/// `_verifierResultatAuto()` part automatiquement) et sous la purge 24 h
/// d'`AlertService._load()`.
TrackedCourse _suivi(
  DateTime dep, {
  required String typePari,
  bool? isGagne,
  List<int> arriveeFinale = const <int>[],
}) =>
    TrackedCourse(
      numReunion: kNumR,
      numCourse: kNumC,
      nomCourse: kNomCourse,
      hippodrome: kHippodrome,
      heureDepart: dep,
      nomCheval: 'CHEVAL_$kNumeroCheval',
      numeroCheval: kNumeroCheval,
      miseEngagee: kMise,
      typePari: typePari,
      numerosJoues: const <int>[kNumeroCheval],
      cote: kCoteGagnant,
      scoreIA: 89.0,
      isGagne: isGagne,
      arriveeFinale: arriveeFinale,
      messageResultat: arriveeFinale.isEmpty ? null : 'Résultat déjà enregistré',
      storageKey: 'R${kNumR}C${kNumC}_${_ddmmyyyy(dep)}',
    );

UserPrediction _pred(String typePari, {required String id}) => UserPrediction(
      id: id,
      dateStr: _ddmmyyyy(DateTime.now()),
      numReunion: kNumR,
      numCourse: kNumC,
      nomCourse: kNomCourse,
      hippodrome: kHippodrome,
      numeroCheval: kNumeroCheval,
      nomCheval: 'CHEVAL_$kNumeroCheval',
      cote: kCoteGagnant,
      typePari: typePari,
      createdAt: DateTime.now(),
      scoreIA: 89.0,
      montantMise: kMise,
      numerosJoues: const <int>[kNumeroCheval],
    );

Map<String, Object> _prefs({required List<UserPrediction> preds}) =>
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
      'user_predictions_v2':
          preds.map((p) => json.encode(p.toJson())).toList(),
    };

// ─────────────────────────── Faux serveur PMU ──────────────────────────────

/// Arrivée officielle servie : le cheval joué (n°7) est 1er.
/// `ZoneTurfService.chargerResultatsCourseComplet` lit
/// `participants[].numPmu` + `participants[].ordreArrivee`
/// (zone_turf_service.dart:1007-1033). Rangs 1 à 5 → arrivée complète.
const List<int> kArrivee = <int>[7, 4, 2, 9, 1];

String _corpsParticipants() => json.encode({
      'participants': <Map<String, dynamic>>[
        for (var i = 0; i < kArrivee.length; i++)
          {
            'numPmu': kArrivee[i],
            'nom': 'CHEVAL_${kArrivee[i]}',
            'statut': 'PARTANT',
            'ordreArrivee': i + 1,
          },
      ],
    });

/// Rapports définitifs PMU réellement attendus par
/// `PmuApiService.fetchRapportsDefinitifs` (dividende en CENTIMES).
String _corpsRapports() => json.encode(<Map<String, dynamic>>[
      {
        'typePari': 'E_SIMPLE_GAGNANT',
        'rapports': [
          {'combinaison': '7', 'dividendePourUnEuro': (kCoteGagnant * 100).round()},
        ],
      },
      {
        'typePari': 'E_SIMPLE_PLACE',
        'rapports': [
          {'combinaison': '7', 'dividendePourUnEuro': (kDividendePlace * 100).round()},
          {'combinaison': '4', 'dividendePourUnEuro': 280},
          {'combinaison': '2', 'dividendePourUnEuro': 310},
        ],
      },
    ]);

/// Intercepte TOUTES les requêtes HTTP émises par la production.
///
/// `rapportsVides: true` isole strictement P1 : `_chargerRapportsPmu()` reçoit
/// `[]` et n'exécute donc rien, seul `_verifierResultatAuto()` travaille.
Future<T> _avecPmu<T>(
  Future<T> Function() action, {
  required bool rapportsVides,
}) {
  final String partants = _corpsParticipants();
  final String rapports = rapportsVides ? '[]' : _corpsRapports();
  final client = MockClient((http.Request request) async {
    final String p = request.url.path;
    const Map<String, String> entetes = {'content-type': 'application/json'};
    // ORDRE IMPORTANT : l'URL « …/programme/…/participants » contient aussi
    // « programme ». On teste donc les suffixes les plus spécifiques d'abord.
    if (p.endsWith('/rapports-definitifs') || p.contains('rapports-definitifs')) {
      return http.Response(rapports, 200, headers: entetes);
    }
    if (p.contains('participants')) {
      return http.Response(partants, 200, headers: entetes);
    }
    if (p.contains('programme')) {
      // Programme vide : aucune donnée inventée, aucune réunion fantôme.
      return http.Response('{"programme":{"reunions":[]}}', 200, headers: entetes);
    }
    return http.Response('{}', 200, headers: entetes);
  });
  return http.runWithClient(action, () => client);
}

// ─────────────────────────── Montage de l'écran réel ───────────────────────

/// Débordements PRÉEXISTANTS du vrai écran, comptés puis rapportés.
List<String> _debordements = <String>[];

Future<void> _monterMesParis(WidgetTester tester, PmuProvider pmu) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 1200);
  addTearDown(tester.view.reset);

  _debordements = <String>[];
  final ancien = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final String t = details.toString();
    if (t.contains('overflowed')) {
      _debordements.add(t.replaceAll('\n', ' '));
      return; // PRÉEXISTANT, hors A-0 : compté, rapporté, non absorbé.
    }
    ancien?.call(details);
  };

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
        // initialTab: 1 = onglet « Suivi », celui qui porte les cartes.
        home: MesPariScreen(initialTab: 1),
      ),
    ),
  );

  // Pompe BORNÉE : `_chargerRapportsPmu` arme un `.timeout(15 s)` ; avancer
  // de 15 s le déclencherait. 40 × 20 ms = 800 ms simulées, très en deçà.
  try {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  } finally {
    FlutterError.onError = ancien;
  }
}

Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Prépare un état disque VIERGE et connu, puis recharge les singletons.
Future<void> _preparer({required List<UserPrediction> preds}) async {
  // 1. Le store mocké est posé AVANT tout `getInstance()`.
  SharedPreferences.setMockInitialValues(_prefs(preds: preds));
  ZoneTurfService.viderCachePourResetComplet();
  DataRefreshService.instance.viderMemoirePourResetComplet();
  await IaMemoryService.instance.recharger();
}

// ─────────────────────────── Tests ────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  T-P1 — VOIE 1 : VÉRIFICATION AUTOMATIQUE DEPUIS « MES PARIS »
  //
  //  Scénario : une seule course suivie, deux paris en attente dessus —
  //  un « Simple Gagnant » et un « Gagnant + Placé » sur le MÊME cheval
  //  (n°7), qui est le gagnant officiel de l'arrivée servie.
  //
  //  Sans A-0, les DEUX recevraient `isCorrect = true` et le G+P recevrait
  //  un gain net de 340 €, calculé avec la cote du seul Gagnant alors qu'il
  //  engage deux mises.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('T-P1 — le G+P reste en attente, le Simple Gagnant est écrit '
      'normalement (écran réel, réseau simulé)', (tester) async {
    final dep = DateTime.now().subtract(const Duration(minutes: 60));
    final predGP = _pred('Gagnant+Placé', id: 'p_gp');
    final predSG = _pred('Simple Gagnant', id: 'p_sg');

    await _preparer(preds: <UserPrediction>[predGP, predSG]);
    // Course suivie SANS résultat (isGagne == null) → `initState` déclenche
    // la vérification automatique (mes_paris_screen.dart:982-984).
    SharedPreferences.setMockInitialValues({
      ..._prefs(preds: <UserPrediction>[predGP, predSG]),
      'tracked_courses_v1': <String>[
        json.encode(_suivi(dep, typePari: 'Gagnant+Placé').toJson()),
      ],
    });
    await AlertService.instance.recharger();

    expect(AlertService.instance.trackedCourses.length, 1,
        reason: 'TÉMOIN : la course suivie du scénario est chargée');
    expect(AlertService.instance.trackedCourses.values.first.isGagne, isNull,
        reason: 'TÉMOIN : aucun résultat préexistant → la vérification '
            'automatique DOIT se déclencher');

    late PmuProvider pmu;
    await _avecPmu(rapportsVides: true, () async {
      pmu = PmuProvider();
      await pmu.reloadPredictions();

      expect(pmu.predictions.length, 2,
          reason: 'TÉMOIN : les deux paris du scénario sont chargés');

      await _monterMesParis(tester, pmu);
    });

    // ── TÉMOINS : c'est bien le VRAI écran, sur le bon onglet ────────────
    expect(find.text('Mes Paris & Alertes'), findsWidgets,
        reason: 'TÉMOIN : le VÉRITABLE MesPariScreen est monté');
    expect(find.text('CHEVAL_$kNumeroCheval'), findsWidgets,
        reason: 'TÉMOIN : la carte de la course suivie est rendue');

    final apresGP = pmu.predictions.firstWhere((p) => p.id == 'p_gp');
    final apresSG = pmu.predictions.firstWhere((p) => p.id == 'p_sg');

    // ignore: avoid_print
    print('─── MESURE T-P1 (voie 1 — Mes Paris) ─────────────────────────');
    // ignore: avoid_print
    print('  G+P          : isCorrect=${apresGP.isCorrect} '
        'gainRealise=${apresGP.gainRealise} gainNet=${apresGP.gainNet}');
    // ignore: avoid_print
    print('  Simple Gagnant: isCorrect=${apresSG.isCorrect} '
        'gainRealise=${apresSG.gainRealise} gainNet=${apresSG.gainNet}');
    // ignore: avoid_print
    print('  débordements préexistants mesurés : ${_debordements.length}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    // ══ ASSERTION 1 : le G+P n'a subi AUCUNE écriture financière ═════════
    expect(apresGP.isCorrect, isNull,
        reason: 'P1 — le Gagnant+Placé doit rester « en attente » : sa cote '
            'enregistrée est celle du Gagnant seul, elle ne peut pas produire '
            'un gain G+P exact. Obtenu isCorrect=${apresGP.isCorrect}.');
    expect(apresGP.gainRealise, isNull,
        reason: 'P1 — aucun gain ne doit être écrit pour un G+P');
    expect(apresGP.gainNet, 0.0,
        reason: 'P1 — gainNet d\'un G+P en attente vaut 0,0 €');
    expect(apresGP.gainNet, isNot(kGainFictifGP),
        reason: 'P1 — le gain FICTIF de ${kGainFictifGP.toStringAsFixed(2)} € '
            'ne doit jamais exister');
    expect(apresGP.retourTotal, 0.0,
        reason: 'P1 — aucun retour encaissé pour un G+P en attente');

    // ══ ASSERTION 2 : NON-RÉGRESSION — le pari simple est écrit ══════════
    expect(apresSG.isCorrect, isTrue,
        reason: 'NON-RÉGRESSION — un Simple Gagnant sur le cheval gagnant '
            'doit conserver son comportement normal');
    expect(apresSG.gainRealise, isNotNull,
        reason: 'NON-RÉGRESSION — le gain du Simple Gagnant doit être calculé');
    expect(apresSG.gainNet, closeTo(kGainReelSimple, 1e-9),
        reason: 'NON-RÉGRESSION — gain Simple Gagnant = (18,00 × 20) − 20 = '
            '340,00 €');

    await _demonter(tester);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T-P1b — CONDITION IMPÉRATIVE N°4 : LA LISTE NE CONTIENT QUE DU G+P
  //
  //  Même voie, mais AUCUN pari simple : si la garde bloquait la boucle
  //  entière au lieu de l'entrée G+P, ce scénario ne le distinguerait pas.
  //  Il est donc doublé d'un TÉMOIN de cardinalité : le provider contient
  //  bien 1 pari avant et après, et c'est bien CELUI-LÀ qui n'a pas bougé.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('T-P1b — liste composée UNIQUEMENT de G+P : aucune écriture, '
      'aucune perte de pari', (tester) async {
    final dep = DateTime.now().subtract(const Duration(minutes: 60));
    final predGP = _pred('Gagnant+Placé', id: 'p_gp_seul');

    await _preparer(preds: <UserPrediction>[predGP]);
    SharedPreferences.setMockInitialValues({
      ..._prefs(preds: <UserPrediction>[predGP]),
      'tracked_courses_v1': <String>[
        json.encode(_suivi(dep, typePari: 'Gagnant+Placé').toJson()),
      ],
    });
    await AlertService.instance.recharger();

    late PmuProvider pmu;
    await _avecPmu(rapportsVides: true, () async {
      pmu = PmuProvider();
      await pmu.reloadPredictions();
      expect(pmu.predictions.length, 1, reason: 'TÉMOIN : un seul pari');
      await _monterMesParis(tester, pmu);
    });

    expect(pmu.predictions.length, 1,
        reason: 'P1 — le pari ne doit être NI supprimé NI dupliqué');
    final apres = pmu.predictions.single;
    expect(apres.isCorrect, isNull, reason: 'P1 — toujours en attente');
    expect(apres.gainNet, 0.0, reason: 'P1 — toujours aucun gain');

    // ignore: avoid_print
    print('─── MESURE T-P1b (liste 100 % G+P) : '
        'paris=${pmu.predictions.length} '
        'isCorrect=${apres.isCorrect} gainNet=${apres.gainNet}');

    await _demonter(tester);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T-P4 — PROTECTION P4 : ATTRIBUTION DU DIVIDENDE RÉEL (Mes Paris)
  //
  //  ── CONDITION D'ATTEINTE, MESURÉE ─────────────────────────────────────
  //  `_majGainReelDansProfil` ne s'exécute QUE si `course.isGagne == true`
  //  (mes_paris_screen.dart:1061). Le scénario pose donc une course DÉJÀ
  //  RÉSOLUE gagnante : la garde n'est PAS inerte ici, elle est mise à
  //  l'épreuve.
  //
  //  ── CE QUE LA GARDE EMPÊCHE, CHIFFRÉ ──────────────────────────────────
  //  Sans elle, `codesPmu` vaudrait `[E_SIMPLE_GAGNANT, E_SIMPLE_PLACE]`
  //  puis `matching.reduce((a,b) => a.dividende > b.dividende ? a : b)`
  //  (l.1105) sélectionnerait le MAXIMUM des rapports servis — soit ×18,00
  //  (le Gagnant) — et l'écrirait comme dividende du G+P. C'est précisément
  //  le gain G+P faux que A-0 interdit.
  //
  //  ── POURQUOI DEUX SCÉNARIOS SÉPARÉS ───────────────────────────────────
  //  MESURÉ : `PmuProvider.getPredictionForCourse` est un `firstWhere`
  //  (pmu_provider.dart:434-441) — il rend le PREMIER pari de la course, et
  //  lui seul. Mettre un G+P et un Simple Gagnant sur la même course ne
  //  prouverait donc rien sur le Simple (jamais atteint, quel que soit A-0).
  //  Chaque scénario ne pose donc QUE le pari dont il parle, ce qui rend
  //  l'attribution sans ambiguïté.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('T-P4a — course gagnante G+P : AUCUN dividende écrit, '
      'aucun gain de 340 € (la garde S\'EFFETTE)', (tester) async {
    final dep = DateTime.now().subtract(const Duration(minutes: 60));
    final predGP = _pred('Gagnant+Placé', id: 'p_gp');

    await _preparer(preds: <UserPrediction>[predGP]);
    // `isGagne: true` + arrivée persistée → `_arrivee` est renseigné en
    // synchrone par `initState` (mes_paris_screen.dart:970-974) : la
    // vérification réseau automatique ne part PAS, seul `_chargerRapportsPmu`
    // → `_majGainReelDansProfil` (P4) travaille.
    SharedPreferences.setMockInitialValues({
      ..._prefs(preds: <UserPrediction>[predGP]),
      'tracked_courses_v1': <String>[
        json.encode(_suivi(
          dep,
          typePari: 'Gagnant+Placé',
          isGagne: true,
          arriveeFinale: kArrivee,
        ).toJson()),
      ],
    });
    await AlertService.instance.recharger();
    expect(AlertService.instance.trackedCourses.values.first.isGagne, isTrue,
        reason: 'TÉMOIN : la course est DÉJÀ gagnante → P4 est atteignable');

    late PmuProvider pmu;
    await _avecPmu(rapportsVides: false, () async {
      pmu = PmuProvider();
      await pmu.reloadPredictions();
      expect(pmu.predictions.single.id, 'p_gp',
          reason: 'TÉMOIN : le seul pari visé par `firstWhere` est le G+P');
      await _monterMesParis(tester, pmu);
    });

    final apres = pmu.predictions.single;

    // ignore: avoid_print
    print('─── MESURE T-P4a (P4 — course G+P gagnante) ──────────────────');
    // ignore: avoid_print
    print('  G+P : dividendePmuReel=${apres.dividendePmuReel} '
        'combinaison=${apres.combinaisonPmu} '
        'isCorrect=${apres.isCorrect} gainNet=${apres.gainNet}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(apres.dividendePmuReel, isNull,
        reason: 'P4 — AUCUN dividende ne doit être attribué à un G+P : le '
            '`reduce(MAX)` l.1105 ne peut pas choisir la bonne composante. '
            'Obtenu : ${apres.dividendePmuReel}');
    expect(apres.combinaisonPmu, isNull,
        reason: 'P4 — aucune combinaison PMU ne doit être écrite non plus');
    expect(apres.isCorrect, isNull, reason: 'P4 — le G+P reste en attente');
    expect(apres.gainRealise, isNull, reason: 'P4 — aucun gainRealise écrit');
    expect(apres.gainNet, 0.0, reason: 'P4 — gainNet nul');
    expect(apres.gainNet, isNot(closeTo(kGainFictifGP, 1e-6)),
        reason: 'P4 — le gain FICTIF de ${kGainFictifGP.toStringAsFixed(2)} € '
            '(MAX des rapports ×18,00 appliqué au G+P) ne doit pas exister');

    await _demonter(tester);
  });

  testWidgets('T-P4b — course gagnante Simple : le dividende EST écrit '
      '(le MÊME chemin fonctionne : c\'est bien la garde qui diffère)',
      (tester) async {
    final dep = DateTime.now().subtract(const Duration(minutes: 60));
    final predSG = _pred('Simple Gagnant', id: 'p_sg');

    await _preparer(preds: <UserPrediction>[predSG]);
    SharedPreferences.setMockInitialValues({
      ..._prefs(preds: <UserPrediction>[predSG]),
      'tracked_courses_v1': <String>[
        json.encode(_suivi(
          dep,
          typePari: 'Simple Gagnant',
          isGagne: true,
          arriveeFinale: kArrivee,
        ).toJson()),
      ],
    });
    await AlertService.instance.recharger();

    late PmuProvider pmu;
    await _avecPmu(rapportsVides: false, () async {
      pmu = PmuProvider();
      await pmu.reloadPredictions();
      await _monterMesParis(tester, pmu);
    });

    final apres = pmu.predictions.single;

    // ignore: avoid_print
    print('─── MESURE T-P4b (P4 — course Simple Gagnant gagnante) ───────');
    // ignore: avoid_print
    print('  Simple : dividendePmuReel=${apres.dividendePmuReel} '
        'combinaison=${apres.combinaisonPmu} '
        'isCorrect=${apres.isCorrect} gainNet=${apres.gainNet}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    // CONTRÔLE CROISÉ : mêmes fixtures réseau, même chemin de code, seul le
    // type de pari change. Si l'écriture fonctionne ici et pas en T-P4a,
    // c'est bien la garde A-0 qui produit la différence.
    expect(apres.dividendePmuReel, closeTo(kCoteGagnant, 1e-9),
        reason: 'NON-RÉGRESSION — un Simple Gagnant doit recevoir son '
            'dividende (×18,00). Obtenu : ${apres.dividendePmuReel}');
    expect(apres.combinaisonPmu, '7',
        reason: 'NON-RÉGRESSION — la combinaison gagnante est écrite');
    expect(apres.isCorrect, isTrue, reason: 'NON-RÉGRESSION');
    expect(apres.gainNet, closeTo(kGainReelSimple, 1e-9),
        reason: 'NON-RÉGRESSION — gain = (18,00 × 20) − 20 = 340,00 €');

    await _demonter(tester);
  });
}
