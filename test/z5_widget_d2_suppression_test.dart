// ═══════════════════════════════════════════════════════════════════════════
//  Z5 — D2 : LE BOUTON « SUPPRIMER CE SUIVI » DU VÉRITABLE ÉCRAN DE DÉTAIL
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE lib/.
//
//  ── POURQUOI CE TEST EXISTE ───────────────────────────────────────────────
//  `grep -rn "ParisDetailScreen" test/` ne renvoyait RIEN (mesuré, exit 1).
//  Les 1 358 tests historiques ne peuvent donc PAS détecter une correction D2
//  manquée : la ligne fautive (`paris_detail_screen.dart:1294`) n'était
//  couverte par aucun test. Z5 comble ce trou.
//
//  Z4-A et Z4-C appellent `AlertService.retirerSuivi(tc.key)` DIRECTEMENT :
//  ils reproduisent le défaut au niveau du service et resteront rouges après
//  la correction du seul appelant. Z5 est la preuve du VERT de D2, parce qu'il
//  passe par le widget réel, le bouton réel et le dialogue réel.
//
//  ── LE DÉFAUT REPRODUIT ───────────────────────────────────────────────────
//  `AlertService.ajouterSuivi()` indexe la map par une storageKey horodatée :
//        storageKey = '${baseKey}_${millisecondsSinceEpoch}'
//        _trackedCourses[storageKey] = course      (alert_service.dart:742)
//  Or le bouton passe `tc.key`, qui vaut 'R{nR}C{nC}_ddmmyyyy' (sans
//  millisecondes, alert_service.dart:3035-3040) :
//        widget.alertSvc.retirerSuivi(tc.key);     (paris_detail_screen.dart:1294)
//  → `Map.remove()` ne trouve aucune entrée : AUCUNE suppression.
//
//  ── SCÉNARIO (mandat, points 1 à 7) ───────────────────────────────────────
//   1. deux suivis différents pour la MÊME course (n°16 puis n°7) ;
//   2. ouverture du détail du PREMIER suivi ;
//   3. appui sur « Supprimer ce suivi » ;
//   4. confirmation de la suppression ;
//   5. le premier suivi disparaît ;
//   6. le deuxième suivi est conservé ;
//   7. `recharger()` (relecture disque) confirme la persistance.
//
//  ── STATUT ATTENDU AVANT CORRECTION : ROUGE ───────────────────────────────
//  Rouge pour la BONNE raison : tous les TÉMOINS (écran monté, course trouvée,
//  bouton présent, dialogue confirmé) passent AVANT l'assertion métier.
//
//  ── CE QUE CE TEST NE PROUVE PAS ──────────────────────────────────────────
//  La sandbox est x86_64 Linux, PAS Android : il prouve la logique de
//  l'application, pas le comportement tactile sur un appareil réel.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/main.dart' show NavigationNotifier;
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/screens/paris_detail_screen.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  1. CONSTANTES DU SCÉNARIO
// ───────────────────────────────────────────────────────────────────────────

const int kNumR = 1;
const int kNumC = 10;

/// Numéro du cheval du PREMIER suivi — celui que l'on va supprimer.
const int kPremierCheval = 16;

/// Numéro du cheval du SECOND suivi — celui qui doit SURVIVRE.
const int kSecondCheval = 7;

const String kNomCourse = 'PRIX DE BAD GODESBERG';
const String kHippodrome = 'SAINT-CLOUD';
const String kTypePari = 'Gagnant+Placé';

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

// ───────────────────────────────────────────────────────────────────────────
//  2. FIXTURES — les deux suivis réels
// ───────────────────────────────────────────────────────────────────────────

/// Suivi tel que `bet_bottom_sheet` le produit avant `AlertService.ajouterSuivi`.
///
/// `heureDepart` à −90 min :
///   • au-delà du seuil −20 min des écrans (donc « terminée ») ;
///   • très en deçà du seuil de purge 24 h de `_load()` (alert_service.dart:522) ;
///   • `isGagne` laissé à null pour NE PAS déclencher le chemin financier
///     `_majGainReelDansProfil` (D4, hors périmètre et non corrigé).
TrackedCourse _suivi(DateTime dep, {required int numeroCheval}) => TrackedCourse(
      numReunion: kNumR,
      numCourse: kNumC,
      nomCourse: kNomCourse,
      hippodrome: kHippodrome,
      heureDepart: dep,
      nomCheval: 'CHEVAL_$numeroCheval',
      numeroCheval: numeroCheval,
      miseEngagee: 20.0,
      typePari: kTypePari,
      numerosJoues: <int>[numeroCheval],
      scoreIA: 89.0,
      cote: 18.0,
    );

// ───────────────────────────────────────────────────────────────────────────
//  3. RÉSEAU SIMULÉ — programme réel + partants réels
// ───────────────────────────────────────────────────────────────────────────

/// `ParisDetailScreen._charger()` appelle `ZoneTurfService.chargerProgramme()`
/// (paris_detail_screen.dart:90) qui interroge `/programme/{date}` ; puis
/// `_chargerPartants()` pour chaque course. Sans ces deux réponses, l'écran
/// reste sur `_error` et le bouton « Supprimer ce suivi » n'existe jamais.
///
/// La charge respecte le format de l'API PMU réel lu par
/// `zone_turf_service.dart` : `programme.reunions[].hippodrome.libelleLong`,
/// `.libelleCourt`, `.numOfficiel`, `.courses[].numOrdre`, `.heureDepart`
/// (epoch millisecondes), `.distance`, `.montantPrix`, `.discipline`.
String _corpsProgramme(DateTime dep) => json.encode({
      'programme': {
        'reunions': <Map<String, dynamic>>[
          {
            'numOfficiel': kNumR,
            'hippodrome': {
              'libelleLong': '$kHippodrome (FRANCE)',
              'libelleCourt': kHippodrome,
            },
            'courses': <Map<String, dynamic>>[
              {
                'numOrdre': kNumC,
                'libelle': kNomCourse,
                'distance': 2000,
                'montantPrix': 25900,
                'discipline': 'PLAT',
                'heureDepart': dep.millisecondsSinceEpoch,
                'paris': <Map<String, dynamic>>[],
              },
            ],
          },
        ],
      },
    });

String _corpsPartants() => json.encode({
      'participants': <Map<String, dynamic>>[
        {'numPmu': kPremierCheval, 'nom': 'CHEVAL_$kPremierCheval', 'age': 5, 'sexe': 'H'},
        {'numPmu': kSecondCheval, 'nom': 'CHEVAL_$kSecondCheval', 'age': 6, 'sexe': 'M'},
      ],
    });

/// Intercepte toutes les requêtes. Seuls le programme, les partants et les
/// rapports sont servis ; les rapports sont VIDES pour ne pas exécuter le
/// chemin financier `_majGainReelDansProfil` (D4, hors périmètre).
Future<T> _avecPmu<T>(DateTime dep, Future<T> Function() action) {
  final String programme = _corpsProgramme(dep);
  final String partants = _corpsPartants();
  final client = MockClient((request) async {
    final String p = request.url.path;
    const Map<String, String> entetes = {'content-type': 'application/json'};
    if (p.contains('participants')) {
      return http.Response(partants, 200, headers: entetes);
    }
    if (p.contains('rapports-definitifs')) {
      return http.Response('[]', 200, headers: entetes);
    }
    if (p.contains('programme')) {
      return http.Response(programme, 200, headers: entetes);
    }
    // Tout le reste : charge neutre, jamais de données inventées.
    return http.Response('{}', 200, headers: entetes);
  });
  return http.runWithClient(action, () => client);
}

// ───────────────────────────────────────────────────────────────────────────
//  4. MONTAGE DU VÉRITABLE `ParisDetailScreen`
// ───────────────────────────────────────────────────────────────────────────

/// Débordements de rendu PRÉEXISTANTS : collectés et rapportés, jamais
/// confondus avec l'objet de Z5 (même précaution que le harnais de Z1).
List<String> _debordements = <String>[];

Future<void> _monterDetail(
  WidgetTester tester,
  TrackedCourse premier,
  PmuProvider pmu,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 2400);
  addTearDown(tester.view.reset);

  // Les débordements de rendu PRÉEXISTANTS de cet écran ne doivent pas faire
  // échouer Z5 : ils sont collectés puis rapportés, jamais confondus avec D2.
  _debordements = <String>[];
  final ancien = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final String t = details.toString();
    if (t.contains('overflowed')) {
      _debordements.add(t.replaceAll('\n', ' '));
      return;
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
        ChangeNotifierProvider.value(value: IaMemoryService.instance),
      ],
      child: MaterialApp(
        home: ParisDetailScreen(
          tracked: premier,
          alertSvc: AlertService.instance,
        ),
      ),
    ),
  );

  // Pompe COURTES : `_chargerRapportsPmu` arme un `.timeout(15 s)`
  // (paris_detail_screen.dart:618) ; avancer de 15 s déclencherait le timeout.
  try {
    for (var i = 0; i < 25; i++) {
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

// ───────────────────────────────────────────────────────────────────────────
//  5. TEST
// ───────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Z5 / D2 — « Supprimer ce suivi » doit retirer LE suivi ouvert et lui seul',
      (WidgetTester tester) async {
    // ── État simulé : disque posé AVANT tout getInstance() ────────────────
    final DateTime dep = DateTime.now().subtract(const Duration(minutes: 90));

    SharedPreferences.setMockInitialValues(<String, Object>{
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
    });

    ZoneTurfService.viderCachePourResetComplet();
    DataRefreshService.instance.viderMemoirePourResetComplet();
    await IaMemoryService.instance.recharger();
    await AlertService.instance.recharger();

    expect(AlertService.instance.trackedCourses, isEmpty,
        reason: 'TÉMOIN : départ à vide (aucune donnée résiduelle du disque)');

    // ── POINT 1 DU MANDAT : deux suivis sur la MÊME course ────────────────
    // `runAsync` = horloge RÉELLE. Nécessaire ici : l'écart de quelques
    // millisecondes entre les deux appels garantit deux storageKey distinctes
    // (sinon le second pari écraserait le premier, ce qui n'est pas D2).
    await tester.runAsync(() async {
      await AlertService.instance
          .ajouterSuivi(_suivi(dep, numeroCheval: kPremierCheval));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await AlertService.instance
          .ajouterSuivi(_suivi(dep, numeroCheval: kSecondCheval));
    });

    final Map<String, TrackedCourse> apresAjout =
        AlertService.instance.trackedCourses;
    expect(apresAjout.length, 2,
        reason: 'TÉMOIN : deux paris sur la même course doivent coexister '
            '(clés de stockage horodatées distinctes)');

    final List<String> cles = apresAjout.keys.toList();
    final TrackedCourse premier = apresAjout[cles[0]]!;
    final TrackedCourse second = apresAjout[cles[1]]!;

    // TÉMOINS sur la dualité d'identifiants — c'est le cœur du défaut.
    expect(premier.numeroCheval, kPremierCheval,
        reason: 'TÉMOIN : le premier suivi est bien celui du n°$kPremierCheval');
    expect(second.numeroCheval, kSecondCheval,
        reason: 'TÉMOIN : le second suivi est bien celui du n°$kSecondCheval');
    expect(premier.storageKey, isNotNull,
        reason: 'TÉMOIN : `ajouterSuivi` doit avoir posé une storageKey');
    expect(cles[0], premier.storageKey,
        reason: 'TÉMOIN : la map est indexée par la storageKey (pas par tc.key)');
    expect(premier.key, isNot(cles[0]),
        reason: 'TÉMOIN : `tc.key` (utilisé par le bouton) diffère de la clé '
            'd\'index — c\'est exactement le défaut D2');
    // Forme exacte de `tc.key` (alert_service.dart:3035-3040) : sans millisecondes.
    expect(premier.key, 'R${kNumR}C${kNumC}_${_ddmmyyyy(dep)}',
        reason: 'TÉMOIN : `tc.key` est « R{nR}C{nC}_ddmmyyyy », la forme que le '
            'bouton transmet à `retirerSuivi`');
    expect(premier.storageKey, isNot(premier.key),
        reason: 'TÉMOIN : storageKey horodatée ≠ tc.key — les deux espaces de '
            'clés sont bien disjoints');

    // ignore: avoid_print
    print('─── MESURE Z5 / D2 ───────────────────────────────────────────');
    // ignore: avoid_print
    print('  tc.key du suivi ouvert  (bouton) : ${premier.key}');
    // ignore: avoid_print
    print('  sa storageKey d\'index            : ${premier.storageKey}');
    // ignore: avoid_print
    print('  seconde storageKey (à préserver) : ${second.storageKey}');

    // PmuProvider : construit SOUS le client simulé (son constructeur réseau
    // est neutralisé, sinon le binding de test renvoie 400).
    //
    // ⚠️ AUCUN `Future.delayed` dans un corps `testWidgets` : l'horloge du
    // binding est simulée, un délai nu ne se résoudrait jamais et le test
    // dépasserait son timeout (« did not complete ») — mesuré, puis corrigé.
    // `reloadPredictions()` se résout par microtâches, comme dans Z1.
    late PmuProvider pmu;
    await _avecPmu(dep, () async {
      pmu = PmuProvider();
      await pmu.reloadPredictions();

      // ── POINT 2 DU MANDAT : ouvrir le détail du PREMIER suivi ───────────
      await _monterDetail(tester, premier, pmu);
    });

    // ── TÉMOINS : l'écran est monté et le bouton existe réellement ───────
    // ⚠️ On cherche par TEXTE, pas par type : `_BigButton` enveloppe un
    // `ElevatedButton.icon`, qui produit la sous-classe privée
    // `_ElevatedButtonWithIcon`. `find.byType(ElevatedButton)` compare le
    // `runtimeType` exact et ne la trouve pas — mesuré, puis contourné ici.
    final Finder boutonSupprimer = find.text('Supprimer ce suivi');
    expect(boutonSupprimer, findsOneWidget,
        reason: 'TÉMOIN : l\'écran de détail doit être chargé (programme '
            'trouvé) et afficher le bouton « Supprimer ce suivi ». S\'il est '
            'absent, c\'est un problème de HARNAIS, pas D2.');
    expect(find.text(kNomCourse), findsWidgets,
        reason: 'TÉMOIN : la course réelle est bien celle du scénario');

    // ── POINT 3 DU MANDAT : appui sur le bouton réel ─────────────────────
    await tester.ensureVisible(boutonSupprimer);
    await tester.pump();
    await tester.tap(boutonSupprimer);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // ── POINT 4 DU MANDAT : confirmation dans le dialogue réel ───────────
    final Finder confirmer = find.widgetWithText(TextButton, 'Supprimer');
    expect(confirmer, findsOneWidget,
        reason: 'TÉMOIN : le dialogue de confirmation doit être ouvert');
    await tester.tap(confirmer);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // ── MESURE ───────────────────────────────────────────────────────────
    final Map<String, TrackedCourse> apresSuppression =
        AlertService.instance.trackedCourses;

    // ignore: avoid_print
    print('  après « Supprimer ce suivi » + confirmation : '
        '${apresSuppression.length} entrée(s)');
    // ignore: avoid_print
    print('  débordements de rendu préexistants : ${_debordements.length}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    // ── POINT 5 : le premier suivi doit disparaître ───────────────────────
    expect(apresSuppression.containsKey(premier.storageKey), isFalse,
        reason: 'D2 (paris_detail_screen.dart:1294) — le bouton passe `tc.key` '
            '(« ${premier.key} ») alors que la map est indexée par la '
            'storageKey (« ${premier.storageKey} ») : `Map.remove()` ne trouve '
            'aucune entrée, le suivi ouvert n\'est PAS supprimé.');

    expect(apresSuppression.length, 1,
        reason: 'D2 — après suppression d\'un suivi sur deux, il doit rester '
            'UNE entrée ; il en reste ${apresSuppression.length}.');

    // ── POINT 6 : le second suivi est conservé ────────────────────────────
    expect(apresSuppression.containsKey(second.storageKey), isTrue,
        reason: 'D2 — le SECOND suivi (n°$kSecondCheval, storageKey '
            '« ${second.storageKey} ») ne doit JAMAIS être touché');
    expect(apresSuppression[second.storageKey]?.numeroCheval, kSecondCheval,
        reason: 'TÉMOIN : la donnée conservée est bien celle du second suivi');

    // ── POINT 7 : persistance après rechargement (relecture disque) ───────
    await AlertService.instance.recharger();
    final Map<String, TrackedCourse> apresRechargement =
        AlertService.instance.trackedCourses;

    // ignore: avoid_print
    print('  après rechargement (relecture disque) : '
        '${apresRechargement.length} entrée(s)');

    expect(apresRechargement.length, 1,
        reason: 'D2 — la suppression doit PERSISTER : après `recharger()`, '
            'il doit rester UNE entrée ; il en reste '
            '${apresRechargement.length}.');
    expect(apresRechargement.containsKey(second.storageKey), isTrue,
        reason: 'D2 — le second suivi doit survivre au rechargement');

    await _demonter(tester);
  });
}
