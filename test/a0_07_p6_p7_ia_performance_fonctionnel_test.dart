// ═══════════════════════════════════════════════════════════════════════════
//  LOT A-0 — VALIDATION FONCTIONNELLE DE P6 ET P7 (écran IaPerformance)
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE lib/.
//
//  ── LES DEUX PROTECTIONS VISÉES ───────────────────────────────────────────
//   P6 `_syncTrackedCoursesToIa()`      ia_performance_screen.dart:320-362
//      → atteinte par `_loadStats()` (l.142, appelé depuis `initState`)
//        → `_loadStatsTravail()` (l.296) → `_syncTrackedCoursesToIa()` (l.305)
//        → `IaMemoryService.mettreAJourStatsTypes(...)`
//   P7 `_lancerAnalyseJournee()`        ia_performance_screen.dart:633
//      → bouton réel « 🔍 Analyser la journée » (l.1724)
//
//  ── POURQUOI CES DEUX PARCOURS SONT TESTABLES SANS TOUCHER À lib/ ────────
//   • `IaPerformanceScreen({required this.alertService})` est public (l.44-46)
//     et `AlertService.instance` est le singleton de production.
//   • `_loadStats()` est déclenché par `initState` : aucune méthode privée
//     n'est appelée depuis le test.
//   • P7 lit un fichier disque via `getApplicationDocumentsDirectory()`
//     (l.499), mais `PathProviderPlatform.instance` est un point d'injection
//     PUBLIC déjà utilisé par trois tests du dépôt (`a7_36`, `a7_38`,
//     `x6_noms_sauvegarde`) : le disque reste donc isolé et réel, jamais simulé.
//   • Le seul accès réseau de `analyseJourneeComplete` est un `http.get`
//     (ia_memory_service.dart:4845). `http.runWithClient` l'intercepte, comme
//     en production (`package:http`).
//
//  ── MESURE PRÉALABLE QUI A CHANGÉ LE DIAGNOSTIC ───────────────────────────
//  Une sonde a établi que `getApplicationDocumentsDirectory()` RÉSOUT bien
//  dans `testWidgets` dès que `PathProviderPlatform.instance` est injecté :
//      [SONDE A] resolu=true erreur=aucune
//      [SONDE B] resolu=true chemin=/tmp/.../ecriture=ok
//  Le blocage supposé dans `a7_37` ne venait donc PAS des E/S, mais de
//  l'ABSENCE d'injection. Aucun `@visibleForTesting` n'est nécessaire.
//
//  ── CE QUI EST VÉRIFIÉ ────────────────────────────────────────────────────
//   T-P6        : une course suivie G+P gagnante ne produit AUCUNE statistique
//                 de type « Gagnant+Placé » (entrée écartée), tandis qu'une
//                 course Simple Gagnant gagnante produit bien sa statistique.
//   T-P6b  (S2) : la neutralisation ne SUPPRIME pas la liste — la garde
//                 `if (statsFusionnees.isNotEmpty)` conserve son comportement.
//   T-P7        : le bouton réel est actionné ; le G+P n'entre dans aucune
//                 statistique, le Simple Gagnant oui, et les autres types
//                 existants ne sont pas altérés.
//
//  ── CE QUI N'EST PAS TOUCHÉ ───────────────────────────────────────────────
//  Gradient, poids, seuils, calibration, ELO, TOP3 learning, règles PMU,
//  calculs financiers. On ne fait que LIRE `statsParType`.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

// ─────────────────────────── Constantes ────────────────────────────────────

const List<int> kArrivee = <int>[7, 4, 2, 9, 1];
const double kMise = 20.0;
const double kCote = 18.00;

/// Gain attendu pour un Simple Gagnant : 20 × 18 − 20 = 340,00 €.
const double kGainSimple = kMise * kCote - kMise;

/// Libellés EXACTS de la production — un renommage doit faire échouer le test.
const String kTypeGP = 'Gagnant+Placé';
const String kTypeSimpleG = 'Simple Gagnant';
const String kBtnAnalyser = '🔍 Analyser la journée';

// ─────────────────── Disque isolé (injection publique) ─────────────────────

/// Injecte un répertoire temporaire RÉEL.
///
/// `getApplicationDocumentsPath` est la méthode effectivement appelée par
/// `_dossierRapports()` (`getApplicationDocumentsDirectory()` la délègue).
/// Même technique que `a7_38_service_backup_test.dart:112-121`.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.racine);
  final String racine;

  @override
  Future<String?> getTemporaryPath() async => racine;

  @override
  Future<String?> getApplicationDocumentsPath() async => racine;
}

// ───────────────────────── Faux serveur PMU ────────────────────────────────

Map<String, dynamic> _bloc(String type, List<String> combos, int centimes) =>
    <String, dynamic>{
      'typePari': type,
      'rapports': <Map<String, dynamic>>[
        for (final c in combos)
          {'combinaison': c, 'dividendePourUnEuro': centimes},
      ],
    };

String _corpsRapports() => json.encode(<dynamic>[
      _bloc('E_SIMPLE_GAGNANT', <String>['7'], (kCote * 100).round()),
      _bloc('E_SIMPLE_PLACE', <String>['7', '4', '2'], 420),
      _bloc('E_QUINTE_PLUS', <String>[kArrivee.join('-')], 12000),
    ]);

MockClient _client() => MockClient((http.Request r) async {
      const Map<String, String> json = {'content-type': 'application/json'};
      final String p = r.url.path;
      if (p.contains('rapports-definitifs')) {
        return http.Response(_corpsRapports(), 200, headers: json);
      }
      if (p.contains('participants')) {
        return http.Response('{"participants":[]}', 200, headers: json);
      }
      return http.Response('{"programme":{"reunions":[]}}', 200, headers: json);
    });

// ─────────────────────────── État simulé ───────────────────────────────────

const Map<String, double> _poidsDefaut = {
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
  'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
  'mouvCote': 0.06, 'placeDepart': 0.03,
};

/// `scoresIA` couvre TOUS les partants de l'arrivée : aucune liste partielle.
const Map<String, double> _scoresIA = <String, double>{
  '7': 88.0, '4': 95.0, '2': 70.0, '9': 60.0, '1': 55.0,
};

Map<String, Object> _prefs({List<TrackedCourse> tracked = const <TrackedCourse>[]}) =>
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
      'user_predictions_v2': <String>[],
      'tracked_courses_v1':
          tracked.map((TrackedCourse t) => json.encode(t.toJson())).toList(),
    };

/// Course suivie déjà RÉSOLUE (`isGagne` non nul).
///
/// ⚠️ `isGagne` est posé directement dans la fixture, et c'est LÉGITIME :
///    P6/P7 filtrent sur `tc.isGagne != null`. En production, ce champ est
///    renseigné par `enregistrerResultatPari`, dont le raccordement est le
///    défaut R1 (hors périmètre A-0). Le présent test porte sur la PROTECTION
///    A-0, pas sur R1 : il faut donc que le filtre amont laisse passer
///    l'entrée, sinon P6/P7 ne serait jamais atteint et le test serait vide.
TrackedCourse _suivi({
  required int numR,
  required int numC,
  required String typePari,
  required bool gagne,
  double mise = kMise,
  double cote = kCote,
  List<int> numerosJoues = const <int>[],
}) =>
    TrackedCourse(
      numReunion: numR,
      numCourse: numC,
      nomCourse: 'PRIX A0 R$numR C$numC',
      hippodrome: 'VINCENNES',
      heureDepart: DateTime.now().subtract(const Duration(hours: 3)),
      numeroCheval: 7,
      nomCheval: 'CHEVAL_7',
      miseEngagee: mise,
      typePari: typePari,
      numerosJoues: numerosJoues,
      cote: cote,
      isGagne: gagne,
      // ⚠️ FORMAT OBLIGATOIRE, MESURÉ : `AlertService._load()` PURGE
      //    (`removeWhere`) toute clé qui ne contient pas `R\d+C\d+_\d{8}`
      //    (alert_service.dart:518-528). Une storageKey sans date fait donc
      //    disparaître la course au rechargement — T-P6b/T-P7 échouaient au
      //    témoin « deux/trois courses chargées » avec 0 entrée pour ce seul
      //    motif. Le suffixe garde l'unicité entre types d'un même scénario.
      storageKey: 'R${numR}C${numC}_20112026_$typePari',
    );

/// Pronostic IA résolu, pour que `analyseJourneeComplete` ait une course à
/// traiter. `resultatsReels` reste faux : c'est le réseau simulé qui résout.
IaPronostic _pronostic({required int numR, required int numC}) =>
    IaPronostic(
      courseKey: 'R${numR}C$numC',
      nomCourse: 'PRIX A0 R$numR C$numC',
      hippodrome: 'VINCENNES',
      discipline: 'Trot Attelé',
      // −3 h : la course est terminée depuis > 30 min → analysable
      datePronostic: DateTime.now().subtract(const Duration(hours: 3)),
      scoresIA: _scoresIA,
      scoresCriteres: const <String, ScoresCriteres>{},
      confiancePredite: 70.0,
      typePariConseille: kTypeSimpleG,
      resultatsReels: false,
      arriveeReelle: null,
    );

/// Remise à zéro. `SharedPreferences` AVANT tout `getInstance()`.
Future<void> _reset({
  List<TrackedCourse> tracked = const <TrackedCourse>[],
  List<IaPronostic> pronostics = const <IaPronostic>[],
  required Directory tmp,
}) async {
  PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  final Map<String, Object> base = _prefs(tracked: tracked);
  if (pronostics.isNotEmpty) {
    base['ia_pronostics_v2'] =
        pronostics.map((IaPronostic p) => json.encode(p.toJson())).toList();
  }
  SharedPreferences.setMockInitialValues(base);
  SharedPreferences.resetStatic();
  ZoneTurfService.viderCachePourResetComplet();
  DataRefreshService.instance.viderMemoirePourResetComplet();
  IaArchiveService.instance.oublierChargementPourTest();
  ArriveeOfficielleService.instance.viderMemoireSeulement();
  await ArriveeOfficielleService.instance.charger();
  await EloService.instance.reinitialiser();
  await IaMemoryService.instance.recharger();
}

/// Monte l'écran RÉEL et laisse `initState` → `_loadStats()` aller au bout.
Future<void> _monter(WidgetTester tester, PmuProvider pmu) async {
  await tester.binding.setSurfaceSize(const Size(900, 30000));
  await tester.pumpWidget(
    ChangeNotifierProvider<PmuProvider>.value(
      value: pmu,
      child: MaterialApp(
        home: Scaffold(body: IaPerformanceScreen(alertService: AlertService.instance)),
      ),
    ),
  );
  // `_autoRecreerSiVide()` attend 600 ms (l.165) : on avance au-delà pour
  // que son timer ne reste pas en vol à la destruction de l'arbre.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 700));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 900));
  await tester.binding.setSurfaceSize(null);
}

/// Statistique d'un type, ou `null` s'il n'apparaît pas du tout.
StatsTypePari? _stat(String type) {
  for (final StatsTypePari s in IaMemoryService.instance.statsParType) {
    if (s.typePari == type) return s;
  }
  return null;
}

/// Affichage compact d'une statistique.
String _desc(StatsTypePari? s) => s == null
    ? 'ABSENT'
    : 'joués=${s.nbJoues} gagnés=${s.nbGagnes} '
        'perdus=${s.nbPerdus} gainNet=${s.gainNet}';

/// Extrait l'emplacement (fichier:ligne) du widget fautif d'un message
/// de débordement, pour que la mesure soit VÉRIFIABLE et non un simple
/// compteur. Aucun masquage : les emplacements sont imprimés.
String _ou(FlutterErrorDetails d) {
  final String txt = d.toString();
  final RegExp re = RegExp(r'([a-zA-Z_0-9]+\.dart):(\d+)');
  final Iterable<RegExpMatch> m = re.allMatches(txt);
  if (m.isEmpty) return 'emplacement inconnu';
  return m.map((RegExpMatch x) => '${x.group(1)}:${x.group(2)}').take(2).join(' → ');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('a0_p67_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T-P6 — P6 neutralise le G+P et conserve le Simple Gagnant.
  //
  //  Les deux courses suivies sont RÉSOLUES (isGagne: true) : elles passent
  //  donc le filtre amont de P6 (l.322). La seule différence entre elles est
  //  `typePari` — ce que la garde A-0 discrimine.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('T-P6 — le G+P gagnant ne produit aucune statistique, '
      'le Simple Gagnant gagnant produit la sienne', (WidgetTester tester) async {
    await _reset(
      tmp: tmp,
      tracked: <TrackedCourse>[
        _suivi(numR: 1, numC: 1, typePari: kTypeGP, gagne: true),
        _suivi(numR: 2, numC: 1, typePari: kTypeSimpleG, gagne: true),
      ],
    );
    await AlertService.instance.recharger();

    expect(AlertService.instance.trackedCourses.length, 2,
        reason: 'TÉMOIN : les deux courses suivies sont chargées');

    final PmuProvider pmu = PmuProvider();
    final List<String> debordements = <String>[];
    final void Function(FlutterErrorDetails)? ancien = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      if (d.exceptionAsString().contains('overflowed')) {
        debordements.add(_ou(d));
      }
    };

    try {
      await tester.runAsync(() => _monter(tester, pmu));
    } finally {
      FlutterError.onError = ancien;
    }

    final StatsTypePari? statGp = _stat(kTypeGP);
    final StatsTypePari? statSg = _stat(kTypeSimpleG);

    // ignore: avoid_print
    print('─── MESURE T-P6 (protection P6) ─────────────────────────────');
    // ignore: avoid_print
    print('  $kTypeGP     : ${_desc(statGp)}');
    // ignore: avoid_print
    print('  $kTypeSimpleG : ${_desc(statSg)}');
    // ignore: avoid_print
    print('  débordements de rendu : ${debordements.length}');
    // ignore: avoid_print
    print('  emplacements : ${debordements.toSet().toList()}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    // ── G+P : aucune statistique ────────────────────────────────────────
    expect(statGp, isNull,
        reason: 'P6 : un G+P ne doit produire AUCUNE statistique de type '
            '« Gagnant+Placé » (isCorrect neutralisé à null). '
            'Mesuré : ${_desc(statGp)}');

    // ── Simple Gagnant : statistique normale conservée ──────────────────
    expect(statSg, isNotNull,
        reason: 'TÉMOIN : le Simple Gagnant doit produire sa statistique. '
            'S\'il est absent, c\'est un problème de HARNAIS, pas de P6.');
    expect(statSg!.nbGagnes, 1,
        reason: 'Simple Gagnant gagnant : 1 gain compté');
    expect(statSg.nbJoues, 1, reason: 'Simple Gagnant : 1 pari joué');
    expect(statSg.gainNet, closeTo(kGainSimple, 1e-9),
        reason: 'Simple Gagnant : gain net 340,00 € conservé');

    await _demonter(tester);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T-P6b — SOLUTION S2 : la liste n'est pas vidée, seules les valeurs
  //  financières sont neutralisées. On le prouve par la CARDINALITÉ.
  //
  //  Si P6 avait SUPPRIMÉ l'entrée, `statsFusionnees` pourrait devenir vide
  //  et `mettreAJourStatsTypes` ne serait plus appelée du tout — changeant le
  //  comportement de la garde `if (statsFusionnees.isNotEmpty)` (l.5124).
  //  Ici, seule la donnée G+P est présente : `statsParType` doit rester VIDE
  //  (aucune écriture) sans qu'aucune exception ne soit levée.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('T-P6b — une liste composée UNIQUEMENT de G+P laisse les '
      'statistiques vides (neutralisation sans suppression)', (WidgetTester tester) async {
    await _reset(
      tmp: tmp,
      tracked: <TrackedCourse>[
        _suivi(numR: 3, numC: 1, typePari: kTypeGP, gagne: true),
        _suivi(numR: 3, numC: 2, typePari: kTypeGP, gagne: false),
      ],
    );
    await AlertService.instance.recharger();

    expect(AlertService.instance.trackedCourses.length, 2,
        reason: 'TÉMOIN : deux courses G+P chargées (une gagnante, une perdante)');

    final PmuProvider pmu = PmuProvider();
    await tester.runAsync(() => _monter(tester, pmu));

    final List<StatsTypePari> toutes = IaMemoryService.instance.statsParType;

    // ignore: avoid_print
    print('─── MESURE T-P6b (liste 100 % G+P) ──────────────────────────');
    // ignore: avoid_print
    print('  nombre de types statistiques : ${toutes.length}');
    // ignore: avoid_print
    print('  types : ${toutes.map((StatsTypePari s) => s.typePari).toList()}');
    // ignore: avoid_print
    print('  $kTypeGP : ${_desc(_stat(kTypeGP))}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(_stat(kTypeGP), isNull,
        reason: 'P6 : ni la victoire ni la défaite G+P ne créent de statistique');
    expect(toutes, isEmpty,
        reason: 'TÉMOIN : aucune autre statistique ne doit apparaître');

    await _demonter(tester);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T-P7 — bouton RÉEL « 🔍 Analyser la journée » (P7).
  //
  //  Le disque est isolé (`PathProviderPlatform`), le réseau est simulé
  //  (`http.runWithClient`). Le traitement réel de `_lancerAnalyseJournee`
  //  est exécuté : statut des fichiers J-2/J-1, rattrapage, puis analyse.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('T-P7 — le bouton réel d\'analyse neutralise le G+P et conserve '
      'les autres types', (WidgetTester tester) async {
    await _reset(
      tmp: tmp,
      pronostics: <IaPronostic>[
        _pronostic(numR: 4, numC: 1),
      ],
      tracked: <TrackedCourse>[
        // Coloriage G+P GAGNANT : ne doit produire aucune statistique.
        _suivi(numR: 4, numC: 1, typePari: kTypeGP, gagne: true),
        // Contrôle : Simple Gagnant GAGNANT, doit produire la sienne.
        _suivi(numR: 4, numC: 2, typePari: kTypeSimpleG, gagne: true),
        // Contrôle de non-régression : Tiercé PERDANT, autre type de pari.
        _suivi(numR: 4, numC: 3, typePari: 'Tiercé', gagne: false,
            mise: 10.0, numerosJoues: <int>[1, 2, 3]),
      ],
    );
    await AlertService.instance.recharger();

    expect(AlertService.instance.trackedCourses.length, 3,
        reason: 'TÉMOIN : les trois courses suivies sont chargées');

    final PmuProvider pmu = PmuProvider();
    final List<String> debordements = <String>[];
    final void Function(FlutterErrorDetails)? ancien = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      if (d.exceptionAsString().contains('overflowed')) {
        debordements.add(_ou(d));
      }
    };

    try {
      await tester.runAsync(() async {
        await _monter(tester, pmu);
      });

      // ── TÉMOIN : le bouton existe réellement ──────────────────────────
      final Finder bouton = find.text(kBtnAnalyser);
      expect(bouton, findsOneWidget,
          reason: 'TÉMOIN : le bouton « $kBtnAnalyser » doit être présent. '
              'S\'il est absent, c\'est un problème de HARNAIS.');

      // ── Appui sur le bouton RÉEL, puis exécution asynchrone réelle ─────
      await tester.ensureVisible(bouton);
      await tester.pump();
      await tester.tap(bouton);
      await tester.pump();

      await tester.runAsync(() async {
        // `_lancerAnalyseJournee` enchaîne : statut fichiers disque (réels,
        // isolés), rattrapage éventuel, puis `analyseJourneeComplete` dont le
        // seul accès réseau est intercepté ci-dessous.
        await http.runWithClient(() async {
          for (var i = 0; i < 120; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
            if (_stat(kTypeSimpleG) != null) break;
          }
        }, () => _client());
      });

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    } finally {
      FlutterError.onError = ancien;
    }

    final StatsTypePari? statGp = _stat(kTypeGP);
    final StatsTypePari? statSg = _stat(kTypeSimpleG);
    final StatsTypePari? statTierce = _stat('Tiercé');

    // ignore: avoid_print
    print('─── MESURE T-P7 (protection P7, bouton réel) ────────────────');
    // ignore: avoid_print
    print('  $kTypeGP     : ${_desc(statGp)}');
    // ignore: avoid_print
    print('  $kTypeSimpleG : ${_desc(statSg)}');
    // ignore: avoid_print
    print('  Tiercé       : ${_desc(statTierce)}');
    // ignore: avoid_print
    print('  débordements de rendu : ${debordements.length}');
    // ignore: avoid_print
    print('  emplacements : ${debordements.toSet().toList()}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    // ── G+P : neutralisé ────────────────────────────────────────────────
    expect(statGp, isNull,
        reason: 'P7 : un G+P gagnant ne doit produire aucune statistique '
            '« Gagnant+Placé ». Mesuré : ${_desc(statGp)}');

    // ── Simple Gagnant : conservé ───────────────────────────────────────
    expect(statSg, isNotNull,
        reason: 'P7 : le Simple Gagnant doit conserver sa statistique '
            '(témoin de non-vacuité du chemin). Mesuré : ${_desc(statSg)}');
    expect(statSg!.nbGagnes, 1, reason: 'P7 : Simple Gagnant gagné compté');
    expect(statSg.gainNet, closeTo(kGainSimple, 1e-9),
        reason: 'P7 : gain net 340,00 € conservé');

    // ── Tiercé (autre type) : non-régression ────────────────────────────
    expect(statTierce, isNotNull,
        reason: 'P7 : un Tiercé perdant reste compté comme tel (aucune '
            'régression sur les autres types). Mesuré : ${_desc(statTierce)}');
    expect(statTierce!.nbPerdus, 1,
        reason: 'P7 : un Tiercé perdant compte 1 perte');
    expect(statTierce.nbGagnes, 0, reason: 'P7 : aucun gain sur un Tiercé perdu');

    await _demonter(tester);
  });
}
