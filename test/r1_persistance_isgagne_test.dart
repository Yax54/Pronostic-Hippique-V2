// ═══════════════════════════════════════════════════════════════════════════
//  LOT R1 — PERSISTANCE DE `isGagne` DANS `TrackedCourse`
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT.
//
//  ── LE DÉFAUT CORRIGÉ (mesuré) ────────────────────────────────────────────
//  `AlertService._trackedCourses` est indexée par la `storageKey` HORODATÉE
//  (`alert_service.dart:719-743`). Deux sites de production passaient
//  `course.key`, SANS horodatage : la lecture `_trackedCourses[courseKey]`
//  (`:779`) rendait `null` et sortait par `if (tc == null) return;`.
//  Résultat : `isGagne` n'était JAMAIS persisté.
//
//  Second défaut, aggravant : `withResultat()` (`:2992`) ne propageait pas
//  `storageKey`. Même avec la bonne clé d'appel, la copie perdait sa clé,
//  `toJson()` écrivait `'storageKey': null`, et `_load()` (`:509`) la
//  réindexait sous `tc.key` — la session semblait correcte, la persistance
//  après rechargement échouait.
//
//  ── TESTS T1..T5 : niveau SERVICE (sans UI) ───────────────────────────────
//   T1  écriture avec la clé RÉELLE → isGagne posé
//   T2  PERSISTANCE : _save réel → SharedPreferences → recharger → relu
//   T3  COLLISION : deux suivis de la MÊME course, un seul marqué
//   T4  COMPATIBILITÉ : entrée héritée SANS storageKey (clé = tc.key)
//   T5  ANTI-ÉCRASEMENT : le premier résultat enregistré est conservé
//
//  ── TESTS T6..T7 : niveau UI, protègent A-0 ───────────────────────────────
//   T6  PIVOT : G+P → résultat SPORTIF persisté, AUCUNE écriture financière
//   T7  NON-RÉGRESSION : Simple Gagnant → persisté ET écrit normalement
//
//  ── CE QUI N'EST PAS TOUCHÉ ───────────────────────────────────────────────
//  Gradient, poids, seuils, calendrier, ELO, TOP3 learning, règles PMU,
//  calculs de gains, `analyseJourneeComplete()`, Lots B et F.
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
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_badges_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_personality_service.dart';
import 'package:pronostic_hippique/services/ia_user_prefs_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ─────────────────────────── Constantes ────────────────────────────────────

const List<int> kArrivee = <int>[7, 4, 2, 9, 1];
const int kNumR = 1;
const int kNumC = 10;
const int kCheval = 7;
const double kMise = 20.0;
const double kCote = 18.00;
const double kGainSimple = kMise * kCote - kMise; // 340.0

/// Départ RÉCENT (il y a 10 min), volontairement PAS une date figée.
///
/// `AlertService._load()` purge `now.difference(tc.heureDepart).inHours > 24`
/// (alert_service.dart:523). Une date figée rendrait ce fichier vert le jour
/// de sa rédaction puis rouge dès le lendemain, pour une raison étrangère à
/// R1. Le départ est donc relatif, la `storageKey` reste littérale (seul le
/// format `R\d+C\d+_\d{8}` est contrôlé, l.520).
DateTime get kDepart => DateTime.now().subtract(const Duration(minutes: 10));

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

// ───────────────────────── Faux serveur PMU ────────────────────────────────

Map<String, dynamic> _bloc(String type, List<String> combos, int centimes) =>
    <String, dynamic>{
      'typePari': type,
      'rapports': <Map<String, dynamic>>[
        for (final c in combos)
          {'combinaison': c, 'dividendePourUnEuro': centimes},
      ],
    };

/// `E_QUINTE_PLUS` est INDISPENSABLE : sans rapport ORDONNÉ d'au moins
/// `kLongueurMinimaleArrivee` chevaux, `deciderArriveeOfficielle` rend
/// `decision.disponible == false` et `_fetchResultatAuto` sort avant tout
/// point d'écriture (alert_service.dart:2253-2257).
String _corpsRapports() => json.encode(<dynamic>[
      _bloc('E_SIMPLE_GAGNANT', <String>['$kCheval'], (kCote * 100).round()),
      _bloc('E_SIMPLE_PLACE', <String>['7', '4', '2'], 420),
      _bloc('E_QUINTE_PLUS', <String>[kArrivee.join('-')], 12000),
    ]);

MockClient _client() => MockClient((http.Request r) async {
      const Map<String, String> h = {'content-type': 'application/json'};
      final String p = r.url.path;
      if (p.contains('rapports-definitifs')) {
        return http.Response(_corpsRapports(), 200, headers: h);
      }
      if (p.contains('participants')) {
        return http.Response(
          json.encode({
            'participants': <Map<String, dynamic>>[
              for (var i = 0; i < kArrivee.length; i++)
                {
                  'numPmu': kArrivee[i],
                  'nom': 'CHEVAL_${kArrivee[i]}',
                  'statut': 'PARTANT',
                  'ordreArrivee': i + 1,
                },
            ],
          }),
          200,
          headers: h,
        );
      }
      return http.Response('{"programme":{"reunions":[]}}', 200, headers: h);
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

Map<String, Object> _prefs({
  List<Map<String, dynamic>> predictions = const <Map<String, dynamic>>[],
  List<TrackedCourse> tracked = const <TrackedCourse>[],
  bool avecTracked = true,
}) =>
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
          predictions.map((Map<String, dynamic> p) => json.encode(p)).toList(),
      if (avecTracked)
        'tracked_courses_v1':
            tracked.map((TrackedCourse t) => json.encode(t.toJson())).toList(),
    };

Map<String, dynamic> _predJson({
  required String id,
  required String typePari,
  double cote = kCote,
  double mise = kMise,
  int numC = kNumC,
}) =>
    <String, dynamic>{
      'id': id,
      'dateStr': '20/11/2026',
      'numReunion': kNumR,
      'numCourse': numC,
      'nomCourse': 'PRIX R1 C$numC',
      'hippodrome': 'VINCENNES',
      'numeroCheval': kCheval,
      'nomCheval': 'CHEVAL_$kCheval',
      'cote': cote,
      'typePari': typePari,
      'createdAt': kDepart.toIso8601String(),
      'isCorrect': null,
      'scoreIA': 70.0,
      'montantMise': mise,
      'gainRealise': null,
      'numerosJoues': <int>[],
      'dividendePmuReel': null,
      'combinaisonPmu': null,
    };

/// Course suivie. [storageKey] est OBLIGATOIRE ici : c'est l'objet du test.
TrackedCourse _suivi({
  String? storageKey,
  int numC = kNumC,
  String typePari = 'Simple Gagnant',
  bool? isGagne,
  DateTime? depart,
}) =>
    TrackedCourse(
      numReunion: kNumR,
      numCourse: numC,
      nomCourse: 'PRIX R1 C$numC',
      hippodrome: 'VINCENNES',
      heureDepart: depart ?? kDepart,
      numeroCheval: kCheval,
      nomCheval: 'CHEVAL_$kCheval',
      miseEngagee: kMise,
      typePari: typePari,
      numerosJoues: const <int>[kCheval],
      cote: kCote,
      isGagne: isGagne,
      storageKey: storageKey,
    );

// ────────────── Interception réseau + montage du VRAI écran ────────────────

/// Exécute [action] en redirigeant TOUT `http.get` de production vers
/// [MockClient]. Même mécanisme que `a0_04` (test vert) : la production
/// appelle bien `http.get` de `package:http`
/// (`zone_turf_service.dart:992`, `pmu_api_service.dart:141`), donc ces
/// deux points sont interceptables. Aucun paquet réel n'est joint.
Future<T> _avecPmu<T>(Future<T> Function() action) {
  final MockClient client = _client();
  return http.runWithClient(action, () => client);
}

/// Débordements PRÉEXISTANTS du vrai écran : comptés, jamais absorbés.
List<String> _debordements = <String>[];

/// Monte le VÉRITABLE `MesPariScreen` (onglet « Suivi ») avec les providers
/// qu'il consomme réellement — mesuré : `NavigationNotifier` (l.88),
/// `PmuProvider` (l.288, 1074, 1448), plus les singletons lus par les cartes.
Future<void> _monterMesParis(WidgetTester tester, PmuProvider pmu) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(500, 1600);
  addTearDown(tester.view.reset);

  _debordements = <String>[];
  final ancien = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final String t = details.toString();
    if (t.contains('overflowed')) {
      _debordements.add(t.replaceAll('\n', ' '));
      return; // PRÉEXISTANT, hors R1 : compté, rapporté.
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

  // Pompe BORNÉE hors `runAsync` : `_chargerRapportsPmu` arme un
  // `.timeout(15 s)` ; avancer de 15 s le déclencherait. 60 × 20 ms =
  // 1,2 s simulées, très en deçà. `runAsync` enveloppait `pumpWidget` dans
  // la version précédente de ce fichier, ce qui empêchait `Timer` /
  // microtâches de la sonde de se vider dans l'horloge du test.
  try {
    for (var i = 0; i < 60; i++) {
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

Future<void> _reset({
  List<Map<String, dynamic>> predictions = const <Map<String, dynamic>>[],
  List<TrackedCourse> tracked = const <TrackedCourse>[],
  bool avecTracked = true,
}) async {
  SharedPreferences.setMockInitialValues(_prefs(
    predictions: predictions,
    tracked: tracked,
    avecTracked: avecTracked,
  ));
  SharedPreferences.resetStatic();
  ZoneTurfService.viderCachePourResetComplet();
  await EloService.instance.reinitialiser();
  await ArriveeOfficielleService.instance.charger();
  await IaMemoryService.instance.recharger();
  await AlertService.instance.recharger();
}

/// Relit les préférences RÉELLEMENT écrites (aucune valeur en RAM).
Future<List<Map<String, dynamic>>> _prefsTracked() async {
  final SharedPreferences p = await SharedPreferences.getInstance();
  final List<String> raw = p.getStringList('tracked_courses_v1') ?? <String>[];
  return raw
      .map((String s) => jsonDecode(s) as Map<String, dynamic>)
      .toList();
}

Future<void> _fermer() async {
  for (final String k in AlertService.instance.trackedCourses.keys.toList()) {
    await AlertService.instance.retirerSuivi(k);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  R1-T1 — écriture avec la clé RÉELLE : le résultat sportif est posé.
  // ═══════════════════════════════════════════════════════════════════════
  test('R1-T1 — enregistrerResultatPari(storageKey) pose isGagne sur la '
      'bonne entrée', () async {
    const String sk = 'R1C10_20112026_1730000000000';
    await _reset(tracked: <TrackedCourse>[_suivi(storageKey: sk)]);

    expect(AlertService.instance.trackedCourses.containsKey(sk), isTrue,
        reason: 'TÉMOIN : entrée indexée par SA storageKey');

    await AlertService.instance.enregistrerResultatPari(
      sk,
      isGagne: true,
      arrivee: kArrivee,
      message: '🏆 Gagnant !',
    );

    final TrackedCourse tc = AlertService.instance.trackedCourses[sk]!;
    // ignore: avoid_print
    print('─── MESURE R1-T1 ────────────────────────────────────────────');
    // ignore: avoid_print
    print('  clé=${tc.storageKey} isGagne=${tc.isGagne} '
        'arrivee=${tc.arriveeFinale} msg=${tc.messageResultat}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(tc.isGagne, isTrue, reason: 'R1 : isGagne doit être posé');
    expect(tc.arriveeFinale, equals(kArrivee),
        reason: 'R1 : l\'arrivée officielle est conservée');
    expect(tc.messageResultat, '🏆 Gagnant !',
        reason: 'R1 : le message de résultat est conservé');
    expect(tc.storageKey, sk,
        reason: 'R1 : storageKey PROPAGÉE par withResultat()');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R1-T2 — PERSISTANCE RÉELLE.
  //
  //  C'est le test central du mandat : il exige que `isGagne` ET `storageKey`
  //  survivent à un rechargement depuis le disque simulé. Il échoue si l'on
  //  ne corrige que l'appelant (défaut B non traité).
  // ═══════════════════════════════════════════════════════════════════════
  test('R1-T2 — après _save puis rechargement, isGagne ET storageKey sont '
      'conservés à l\'identique', () async {
    const String sk = 'R1C10_20112026_1730000000001';
    await _reset(tracked: <TrackedCourse>[_suivi(storageKey: sk)]);

    await AlertService.instance.enregistrerResultatPari(
      sk,
      isGagne: true,
      arrivee: kArrivee,
      message: '🏆 Gagnant !',
    );

    // ── Ce qui a RÉELLEMENT été écrit sur disque ────────────────────────
    final List<Map<String, dynamic>> disque = await _prefsTracked();
    final Map<String, dynamic>? surDisque = disque.isEmpty ? null : disque.first;

    // ignore: avoid_print
    print('─── MESURE R1-T2 (disque) ───────────────────────────────────');
    // ignore: avoid_print
    print('  storageKey écrite  : ${surDisque?['storageKey']}');
    // ignore: avoid_print
    print('  isGagne écrit      : ${surDisque?['isGagne']}');
    // ignore: avoid_print
    print('  arriveeFinale      : ${surDisque?['arriveeFinale']}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(surDisque, isNotNull, reason: 'TÉMOIN : une entrée est écrite');
    expect(surDisque!['storageKey'], sk,
        reason: 'R1 (défaut B) : withResultat doit PROPAGER storageKey, '
            'sinon toJson écrit null et _load réindexe sous tc.key');
    expect(surDisque['isGagne'], isTrue,
        reason: 'R1 : isGagne est bien sérialisé');

    // ── Rechargement RÉEL depuis les préférences ────────────────────────
    await AlertService.instance.recharger();
    final Map<String, TrackedCourse> apres =
        AlertService.instance.trackedCourses;

    // ignore: avoid_print
    print('  après rechargement : clés=${apres.keys.toList()}');

    expect(apres.containsKey(sk), isTrue,
        reason: 'R1 : la clé d\'origine doit être RETROUVÉE après '
            'rechargement (pas une clé recalculée sans horodatage). '
            'Clés mesurées : ${apres.keys.toList()}');
    expect(apres[sk]!.isGagne, isTrue,
        reason: 'R1 : le résultat sportif survit au rechargement');
    expect(apres[sk]!.storageKey, sk,
        reason: 'R1 : la storageKey relue est identique');
    expect(apres[sk]!.arriveeFinale, equals(kArrivee),
        reason: 'R1 : l\'arrivée survit au rechargement');

    await _fermer();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R1-T3 — COLLISION : deux suivis de la MÊME course.
  //
  //  La `storageKey` inclut `millisecondsSinceEpoch` : les deux entrées
  //  coexistent. Seule celle dont la clé est passée doit être marquée.
  // ═══════════════════════════════════════════════════════════════════════
  test('R1-T3 — deux suivis de la même course : un seul est marqué', () async {
    const String sk1 = 'R1C10_20112026_1730000000002';
    const String sk2 = 'R1C10_20112026_1730000000003';
    await _reset(tracked: <TrackedCourse>[
      _suivi(storageKey: sk1),
      _suivi(storageKey: sk2),
    ]);

    expect(AlertService.instance.trackedCourses.length, 2,
        reason: 'TÉMOIN : les deux suivis coexistent (clés horodatées)');

    await AlertService.instance.enregistrerResultatPari(
      sk2,
      isGagne: true,
      arrivee: kArrivee,
      message: '🏆 Gagnant ! (2e suivi)',
    );

    final TrackedCourse a = AlertService.instance.trackedCourses[sk1]!;
    final TrackedCourse b = AlertService.instance.trackedCourses[sk2]!;

    // ignore: avoid_print
    print('─── MESURE R1-T3 ────────────────────────────────────────────');
    // ignore: avoid_print
    print('  suivi 1 ($sk1) : isGagne=${a.isGagne}');
    // ignore: avoid_print
    print('  suivi 2 ($sk2) : isGagne=${b.isGagne}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(b.isGagne, isTrue,
        reason: 'R1 : le suivi ciblé par sa storageKey est marqué');
    expect(a.isGagne, isNull,
        reason: 'R1 : l\'AUTRE suivi de la même course reste intact '
            '(aucune correspondance ambiguë par préfixe)');

    await _fermer();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R1-T4 — COMPATIBILITÉ : entrée héritée SANS storageKey.
  //
  //  `_load()` applique `tc.storageKey ?? tc.key` (l.509) : la map est
  //  indexée par `tc.key`. L'écriture par cette clé doit fonctionner.
  // ═══════════════════════════════════════════════════════════════════════
  test('R1-T4 — entrée sans storageKey : enregistrerResultatPari(tc.key) '
      'fonctionne encore', () async {
    final TrackedCourse heritage = _suivi(storageKey: null);
    final String cleHeritee = heritage.key;
    await _reset(tracked: <TrackedCourse>[heritage]);

    expect(AlertService.instance.trackedCourses.containsKey(cleHeritee), isTrue,
        reason: 'TÉMOIN : _load() a indexé par tc.key (storageKey absente)');

    await AlertService.instance.enregistrerResultatPari(
      cleHeritee,
      isGagne: true,
      arrivee: kArrivee,
      message: '🏆 Gagnant ! (héritage)',
    );

    final TrackedCourse tc =
        AlertService.instance.trackedCourses[cleHeritee]!;

    // ignore: avoid_print
    print('─── MESURE R1-T4 (héritage) ────────────────────────────────');
    // ignore: avoid_print
    print('  clé=$cleHeritee isGagne=${tc.isGagne} '
        'storageKey=${tc.storageKey}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(tc.isGagne, isTrue,
        reason: 'R1 : une entrée héritée reste enregistrable par tc.key');
    // `withResultat` propage `storageKey` qui vaut `null` ici : le champ
    // reste null, et `_load()` continuera de retomber sur `tc.key`.
    // Aucune clé n'est INVENTÉE — comportement identique à avant.
    expect(tc.storageKey, isNull,
        reason: 'R1 : aucune storageKey n\'est fabriquée pour un héritage');

    await _fermer();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R1-T5 — ANTI-ÉCRASEMENT : le premier résultat est conservé.
  //
  //  `enregistrerResultatPari` contient `if (tc.isGagne != null) return;`
  //  (alert_service.dart:781). Un second appel ne doit RIEN changer.
  // ═══════════════════════════════════════════════════════════════════════
  test('R1-T5 — un second enregistrement n\'écrase pas le premier résultat',
      () async {
    const String sk = 'R1C10_20112026_1730000000004';
    await _reset(tracked: <TrackedCourse>[_suivi(storageKey: sk)]);

    await AlertService.instance.enregistrerResultatPari(
      sk,
      isGagne: true,
      arrivee: kArrivee,
      message: 'PREMIER',
    );
    // Second appel, volontairement contradictoire
    await AlertService.instance.enregistrerResultatPari(
      sk,
      isGagne: false,
      arrivee: <int>[1, 2, 3, 4, 5],
      message: 'SECOND',
    );

    final TrackedCourse tc = AlertService.instance.trackedCourses[sk]!;

    // ignore: avoid_print
    print('─── MESURE R1-T5 (anti-écrasement) ─────────────────────────');
    // ignore: avoid_print
    print('  isGagne=${tc.isGagne} msg=${tc.messageResultat} '
        'arrivee=${tc.arriveeFinale}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(tc.isGagne, isTrue,
        reason: 'R1 : le PREMIER résultat (gagnant) est conservé');
    expect(tc.messageResultat, 'PREMIER',
        reason: 'R1 : le message du premier enregistrement est conservé');
    expect(tc.arriveeFinale, equals(kArrivee),
        reason: 'R1 : l\'arrivée du premier enregistrement est conservée');

    await _fermer();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R1-T6 — TEST PIVOT : G+P persisté sportivement, ZÉRO écriture
  //  financière. C'est l'exigence « R1 ne doit pas contourner A-0 ».
  //
  //  On monte le VRAI `MesPariScreen` : c'est la seule façon d'exercer les
  //  appelants corrigés (l.1286 et l.1426), donc le correctif R1 lui-même.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('R1-T6 — G+P : le résultat sportif est persisté, mais aucune '
      'écriture financière n\'a lieu (A-0 intact)', (WidgetTester tester) async {
    // Départ il y a 10 min : `_verifierResultatAuto` est déclenché par
    // `initState` (diff <= -5, mes_paris_screen.dart:982).
    final DateTime dep = DateTime.now().subtract(const Duration(minutes: 10));
    final String sk = 'R1C10_${_fmt(dep)}_r1t6';

    await _reset(
      predictions: <Map<String, dynamic>>[
        _predJson(id: 'gp_r1', typePari: 'Gagnant+Placé'),
      ],
      tracked: <TrackedCourse>[
        _suivi(storageKey: sk, typePari: 'Gagnant+Placé', depart: dep),
      ],
    );

    late PmuProvider pmu;
    await _avecPmu(() async {
      pmu = PmuProvider();
      await pmu.reloadPredictions();
      expect(pmu.predictions.length, 1,
          reason: 'TÉMOIN : le pari G+P est chargé');

      expect(AlertService.instance.trackedCourses.containsKey(sk), isTrue,
          reason: 'TÉMOIN : la course suivie est chargée sous SA storageKey');
      expect(AlertService.instance.trackedCourses[sk]!.isGagne, isNull,
          reason: 'TÉMOIN : aucun résultat préexistant → la vérification '
              'automatique DOIT se déclencher');

      await _monterMesParis(tester, pmu);
    });

    final TrackedCourse? tc = AlertService.instance.trackedCourses[sk];
    final UserPrediction gp = pmu.predictions.first;

    // ignore: avoid_print
    print('─── MESURE R1-T6 (PIVOT : G+P) ─────────────────────────────');
    // ignore: avoid_print
    print('  SPORTIF  : isGagne=${tc?.isGagne} '
        'arrivee=${tc?.arriveeFinale} msg=${tc?.messageResultat}');
    // ignore: avoid_print
    print('  FINANCIER: isCorrect=${gp.isCorrect} '
        'gainRealise=${gp.gainRealise} gainNet=${gp.gainNet} '
        'mise=${gp.montantMise}');
    // ignore: avoid_print
    print('  storageKey après écriture : ${tc?.storageKey}');
    // ignore: avoid_print
    print('  débordements préexistants : ${_debordements.length}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    // TÉMOIN : c'est bien le VRAI écran, sur le bon onglet
    expect(find.text('Mes Paris & Alertes'), findsWidgets,
        reason: 'TÉMOIN : le VÉRITABLE MesPariScreen est monté');
    expect(find.text('CHEVAL_$kCheval'), findsWidgets,
        reason: 'TÉMOIN : la carte de la course suivie est rendue');

    // ── R1 : le résultat SPORTIF est bien persisté ──────────────────────
    expect(tc, isNotNull, reason: 'TÉMOIN : l\'entrée existe toujours');
    expect(tc!.isGagne, isNotNull,
        reason: 'R1 : le résultat sportif EST persisté (sans le correctif, '
            'isGagne restait null car l\'écriture sortait sur tc == null)');
    expect(tc.arriveeFinale, isNotEmpty,
        reason: 'R1 : l\'arrivée officielle est enregistrée');
    expect(tc.storageKey, sk,
        reason: 'R1 (défaut B) : storageKey conservée après écriture');

    // ── A-0 : AUCUNE écriture financière ────────────────────────────────
    expect(gp.isCorrect, isNull,
        reason: 'A-0 (P1) : le G+P reste « en attente », aucun gain écrit');
    expect(gp.gainRealise, isNull,
        reason: 'A-0 (P1) : aucun gain réalisé sur le G+P');
    expect(gp.gainNet, 0.0,
        reason: 'A-0 : gain net G+P nul, aucun montant fictif');
    expect(gp.montantMise, kMise,
        reason: 'A-0 : la mise du G+P n\'est pas réécrite');

    await _demonter(tester);
    await _fermer();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R1-T7 — NON-RÉGRESSION : Simple Gagnant.
  //
  //  Même parcours, même correctif : le Simple doit être persisté ET écrit
  //  financièrement comme avant.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('R1-T7 — Simple Gagnant : persisté ET écrit financièrement '
      '(non-régression)', (WidgetTester tester) async {
    final DateTime dep = DateTime.now().subtract(const Duration(minutes: 10));
    final String sk = 'R1C10_${_fmt(dep)}_r1t7';

    await _reset(
      predictions: <Map<String, dynamic>>[
        _predJson(id: 'sg_r1', typePari: 'Simple Gagnant'),
      ],
      tracked: <TrackedCourse>[_suivi(storageKey: sk, depart: dep)],
    );

    late PmuProvider pmu;
    await _avecPmu(() async {
      pmu = PmuProvider();
      await pmu.reloadPredictions();
      expect(pmu.predictions.length, 1,
          reason: 'TÉMOIN : le pari Simple Gagnant est chargé');
      expect(AlertService.instance.trackedCourses[sk]!.isGagne, isNull,
          reason: 'TÉMOIN : aucun résultat préexistant');

      await _monterMesParis(tester, pmu);
    });

    final TrackedCourse? tc = AlertService.instance.trackedCourses[sk];
    final UserPrediction sg = pmu.predictions.first;

    // ignore: avoid_print
    print('─── MESURE R1-T7 (Simple Gagnant) ──────────────────────────');
    // ignore: avoid_print
    print('  SPORTIF  : isGagne=${tc?.isGagne} arrivee=${tc?.arriveeFinale}');
    // ignore: avoid_print
    print('  FINANCIER: isCorrect=${sg.isCorrect} '
        'gainRealise=${sg.gainRealise} gainNet=${sg.gainNet}');
    // ignore: avoid_print
    print('  débordements préexistants : ${_debordements.length}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(find.text('Mes Paris & Alertes'), findsWidgets,
        reason: 'TÉMOIN : le VÉRITABLE MesPariScreen est monté');

    expect(tc, isNotNull, reason: 'TÉMOIN : l\'entrée existe');
    expect(tc!.isGagne, isNotNull,
        reason: 'R1 : le résultat sportif du Simple est persisté');
    expect(tc.isGagne, isTrue,
        reason: 'R1 : le n°$kCheval est 1er de l\'arrivée servie');
    expect(sg.isCorrect, isTrue,
        reason: 'Non-régression : le Simple Gagnant reste validé gagnant');
    expect(sg.gainRealise, isNotNull,
        reason: 'Non-régression : un gain réel est enregistré');
    expect(sg.gainNet, closeTo(kGainSimple, 1e-9),
        reason: 'Non-régression : (18,00 × 20) − 20 = 340,00 €');

    await _demonter(tester);
    await _fermer();
  });
}
