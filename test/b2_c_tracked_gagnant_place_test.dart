// ═══════════════════════════════════════════════════════════════════════════
//  LOT B2-C — VENTILATION GAGNANT / PLACÉ DANS `TrackedCourse`
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT.
//
//  ── CE QUI EST PROUVÉ ICI ─────────────────────────────────────────────────
//  B1 a créé `miseGagnant` / `misePlace` sur `UserPrediction` ; B2-A les
//  renseigne à la création du pari dans `bet_bottom_sheet.dart`. Mais
//  `TrackedCourse` — le modèle du SUIVI de course — ne les portait pas :
//  la ventilation disparaissait dès que la course était suivie.
//
//  B2-C ajoute au modèle :
//      final double? miseGagnant;
//      final double? misePlace;
//      double? get miseTotaleEngagee          (contrat B1, 3 cas)
//      bool   get misesGagnantPlaceIncompletes
//  et les propage dans les TROIS copies (`withResultat`, `withDividende`,
//  `ajouterSuivi`), `toJson` et `fromJson`.
//
//  ── RÈGLE MÉTIER IMPÉRATIVE ───────────────────────────────────────────────
//  10 € saisis = 10 € Gagnant + 10 € Placé = 20 € engagés.
//  La mise saisie n'est JAMAIS divisée par deux. Les assertions portent donc
//  sur des RELATIONS mesurées (`miseGagnant == miseEngagee`,
//  `miseTotaleEngagee == 2 × miseEngagee`) et non sur une constante figée.
//
//  ── C-2a : AUCUNE COTE ────────────────────────────────────────────────────
//  Aucune cote n'est enregistrée par B2-C, aucune estimation n'est inventée.
//
//  ── LES 7 NIVEAUX DE PREUVE ───────────────────────────────────────────────
//   T1  sérialisation : `toJson` écrit les 2 clés, `fromJson` les relit
//   T2  les TROIS copies conservent les composantes ET `storageKey`
//   T3  persistance RÉELLE : `ajouterSuivi` → disque → `recharger()`
//   T4  rétrocompatibilité : JSON hérité SANS les 2 clés → null, et
//       `miseTotaleEngagee` retombe sur `miseEngagee` (contrat B1)
//   T5  contrat `miseTotaleEngagee` / `misesGagnantPlaceIncompletes` (3 cas)
//   T6  FORMULAIRE RÉEL : `MesPariScreen` → FAB → `_AjouterCourseSheet`
//       → « Gagnant+Placé » → « Ajouter le suivi »
//   T7  NON-RÉGRESSION : le même formulaire en Simple Gagnant laisse les
//       deux champs à null et `miseTotaleEngagee == miseEngagee`
//
//  ── CE QUI N'EST PAS TOUCHÉ ───────────────────────────────────────────────
//  Aucun calcul financier, aucun rapport PMU officiel, aucune place payée,
//  aucun AFFICHAGE (arbitrage A-2 reporté), aucune garde A-0, aucun
//  `UserPrediction`, aucun apprentissage IA.
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

// ─────────────────────────── Constantes mesurées ──────────────────────────

/// Mise par DÉFAUT du formulaire réel, mesurée dans
/// `mes_paris_screen.dart:2694` (`double _mise = 10.0;`) et `:2696`
/// (`TextEditingController(text: '10')`).
///
/// C'est exactement l'exemple du mandat : 10 € saisis = 10 € Gagnant
/// + 10 € Placé = 20 € engagés. Aucune valeur inventée : T6 la MESURE
/// (il lit `tc.miseEngagee`) au lieu de la supposer, et les assertions
/// restent relationnelles pour ne pas dépendre de ce littéral.
const double kMiseDefautFormulaire = 10.0;

/// Mise DIFFÉRENTE, saisie par l'utilisateur dans T7 : elle doit se propager
/// telle quelle (c'est la preuve qu'aucune division par deux n'intervient).
const double kMiseSaisieT7 = 25.0;

const int kNumR = 1;
const int kNumC = 3;

/// Départ FUTUR, **le jour même** — contrainte MESURÉE, pas un choix :
///
/// • `AlertService._load()` purge les entrées de plus de 24 h PASSÉES
///   (`alert_service.dart:523`) → un départ futur n'est jamais purgé.
/// • `ZtCourse.heureDateTime` (`zt_models.dart:827-845`) ne conserve que
///   `HH:MM` et RECOMBINE avec `dateStr`, lequel vaut la date du jour fournie
///   par `chargerProgramme()`. Un départ à J+1 serait donc relu comme
///   « aujourd'hui à la même heure », c'est-à-dire dans le PASSÉ, et le filtre
///   `dt.isAfter(now)` de `_showAjouterCourseDialog`
///   (`mes_paris_screen.dart:270-271`) écarterait la course : le formulaire
///   réel (T6/T7) ne pourrait jamais s'ouvrir.
///
/// Volontairement RELATIF : aucune date figée, donc aucun test qui deviendrait
/// rouge le lendemain pour une raison étrangère à B2-C.
DateTime get kDepart {
  final DateTime n = DateTime.now();
  final DateTime cible = n.add(const Duration(minutes: 45));
  if (cible.day == n.day && cible.month == n.month) return cible;
  // Passage de minuit : on reste dans la journée, toujours future.
  return DateTime(n.year, n.month, n.day, 23, 59, 59);
}

String _ddmmyyyy(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Date de départ au format `ddmmyyyy` (format exigé par `TrackedCourse.key`
/// et par `RegExp(r'R\d+C\d+_\d{8}')` de `_load()`).
String get kDateStr => _ddmmyyyy(kDepart);

/// Clé de base au format attendu par `_load()` (`RegExp(r'R\d+C\d+_\d{8}')`).
String get kBaseKey => 'R${kNumR}C${kNumC}_$kDateStr';

/// Clé horodatée, comme celle produite par `ajouterSuivi`
/// (`alert_service.dart:719`).
const String kStorageKey = 'R1C3_01012027_1770000000000';

// ─────────────────── Fixture du modèle `TrackedCourse` ────────────────────

/// Course suivie Gagnant+Placé : `miseEngagee` = 10 € saisis, et les DEUX
/// composantes valent 10 € — total engagé 20 €.
TrackedCourse _suiviGP({
  double? miseGagnant = kMiseDefautFormulaire,
  double? misePlace = kMiseDefautFormulaire,
  double? miseEngagee = kMiseDefautFormulaire,
  String? storageKey = kStorageKey,
  String typePari = 'Gagnant+Placé',
}) =>
    TrackedCourse(
      numReunion: kNumR,
      numCourse: kNumC,
      nomCourse: 'PRIX B2-C',
      hippodrome: 'VINCENNES',
      heureDepart: kDepart,
      nomCheval: 'ETOILE B2C',
      numeroCheval: 7,
      miseEngagee: miseEngagee,
      miseGagnant: miseGagnant,
      misePlace: misePlace,
      typePari: typePari,
      numerosJoues: const <int>[7],
      cote: 0.0,
      storageKey: storageKey,
    );

/// Course suivie SIMPLE (aucune ventilation).
TrackedCourse _suiviSimple({
  String typePari = 'Simple Gagnant',
  String? storageKey = kStorageKey,
}) =>
    TrackedCourse(
      numReunion: kNumR,
      numCourse: kNumC,
      nomCourse: 'PRIX B2-C',
      hippodrome: 'VINCENNES',
      heureDepart: kDepart,
      nomCheval: 'ETOILE B2C',
      numeroCheval: 7,
      miseEngagee: kMiseDefautFormulaire,
      typePari: typePari,
      numerosJoues: const <int>[7],
      storageKey: storageKey,
    );

// ─────────────────── JSON hérité (AVANT B2-C, sans les 2 clés) ────────────

/// Sérialisation telle qu'elle existait AVANT B2-C : aucune clé
/// `miseGagnant` / `misePlace`. C'est la forme que l'on trouve sur les
/// appareils déjà installés.
Map<String, dynamic> _jsonHerite({String? storageKey = kStorageKey}) =>
    <String, dynamic>{
      'numReunion': kNumR,
      'numCourse': kNumC,
      'nomCourse': 'PRIX B2-C',
      'hippodrome': 'VINCENNES',
      'heureDepart': kDepart.toIso8601String(),
      'nomCheval': 'ETOILE B2C',
      'numeroCheval': 7,
      'miseEngagee': kMiseDefautFormulaire,
      'addedAt': kDepart.toIso8601String(),
      'typePari': 'Simple Gagnant',
      'numerosJoues': <int>[7],
      'iaMemKey': null,
      'scoreIA': 0.0,
      'cote': 0.0,
      'isGagne': null,
      'arriveeFinale': <int>[],
      'messageResultat': null,
      'dividendePmuReel': null,
      'combinaisonPmu': null,
      'storageKey': storageKey,
    };

// ─────────────────────── Préférences simulées ─────────────────────────────

const Map<String, double> _poidsDefaut = <String, double>{
  'forme': 0.25,
  'gains': 0.13,
  'record': 0.10,
  'cote': 0.08,
  'constance': 0.09,
  'victoires': 0.04,
  'discipline': 0.02,
  'distSpec': 0.08,
  'jockey': 0.07,
  'repos': 0.03,
  'hippo': 0.04,
  'entraineur': 0.04,
  'elo': 0.05,
  'terrain': 0.05,
  'divergence': 0.04,
  'poidsRel': 0.03,
  'progression': 0.03,
  'mouvCote': 0.06,
  'placeDepart': 0.03,
};

Map<String, Object> _prefsSimulees({
  List<String> tracked = const <String>[],
}) =>
    <String, Object>{
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
      'tracked_courses_v1': tracked,
    };

Future<void> _resetServices({List<String> tracked = const <String>[]}) async {
  SharedPreferences.setMockInitialValues(_prefsSimulees(tracked: tracked));
  SharedPreferences.resetStatic();
  ZoneTurfService.viderCachePourResetComplet();
  await EloService.instance.reinitialiser();
  await ArriveeOfficielleService.instance.charger();
  await IaMemoryService.instance.recharger();
  await AlertService.instance.recharger();
}

Future<void> _fermerSuivis() async {
  for (final String k in AlertService.instance.trackedCourses.keys.toList()) {
    await AlertService.instance.retirerSuivi(k);
  }
}

/// Relit ce qui a RÉELLEMENT été écrit par `AlertService._save()`.
Future<List<Map<String, dynamic>>> _trackedSurDisque() async {
  final SharedPreferences p = await SharedPreferences.getInstance();
  final List<String> raw = p.getStringList('tracked_courses_v1') ?? <String>[];
  return raw.map((String s) => jsonDecode(s) as Map<String, dynamic>).toList();
}

// ─────────────── Faux serveur PMU (formulaire réel : T6 / T7) ──────────────

/// Programme PMU minimal mais RÉELLEMENT parsé par
/// `ZoneTurfService.chargerProgramme` (`zone_turf_service.dart:58+`) :
/// `{"programme":{"reunions":[...]}}`, hippodrome français (le filtre
/// `_estHippodromeFrancais` écarte les réunions étrangères, l.119),
/// `discipline` reconnue, et `heureDepart` en millisecondes.
String _corpsProgramme() => json.encode(<String, dynamic>{
      'programme': <String, dynamic>{
        'reunions': <Map<String, dynamic>>[
          {
            'numOfficiel': kNumR,
            'hippodrome': <String, dynamic>{
              'libelleLong': 'VINCENNES',
              'libelleCourt': 'VINCENNES',
            },
            'courses': <Map<String, dynamic>>[
              {
                'numOrdre': kNumC,
                'libelle': 'PRIX B2-C',
                'distance': 2850,
                'montantPrix': 50000,
                'discipline': 'ATTELE',
                'heureDepart': kDepart.millisecondsSinceEpoch,
                'paris': <Map<String, dynamic>>[
                  {'typePari': 'E_SIMPLE_GAGNANT'},
                  {'typePari': 'E_SIMPLE_PLACE'},
                ],
              },
            ],
          },
        ],
      },
    });

/// Participants minimaux : seuls `numPmu`, `nom` et la cote sont exploités
/// par `_chargerPartants` (l.340+). Aucun appel réseau réel n'est émis.
String _corpsPartants() => json.encode(<String, dynamic>{
      'participants': <Map<String, dynamic>>[
        {
          'numPmu': 7,
          'nom': 'ETOILE B2C',
          'statut': 'PARTANT',
          'age': 5,
          'sexe': 'H',
          'dernierRapportDirect': <String, dynamic>{'rapport': 18.0},
          'driver': <String, dynamic>{'nom': 'DRIVER B2C'},
          'entraineur': <String, dynamic>{'nom': 'ENT B2C'},
          'gainsParticipant': <String, dynamic>{'gainsCarriere': 500000},
        },
        {
          'numPmu': 1,
          'nom': 'ALPHA B2C',
          'statut': 'PARTANT',
          'age': 6,
          'sexe': 'M',
          'dernierRapportDirect': <String, dynamic>{'rapport': 4.5},
          'driver': <String, dynamic>{'nom': 'DRIVER 1'},
          'entraineur': <String, dynamic>{'nom': 'ENT 1'},
          'gainsParticipant': <String, dynamic>{'gainsCarriere': 300000},
        },
      ],
    });

MockClient _client() => MockClient((http.Request r) async {
      const Map<String, String> h = {'content-type': 'application/json'};
      final String p = r.url.path;
      if (p.contains('participants')) {
        return http.Response(_corpsPartants(), 200, headers: h);
      }
      if (p.contains('programme')) {
        return http.Response(_corpsProgramme(), 200, headers: h);
      }
      return http.Response('{"programme":{"reunions":[]}}', 200, headers: h);
    });

/// Exécute [action] sans réseau réel, SOUS capture comptée des débordements
/// connus. La composition est volontaire : les tests UI de ce fichier ont
/// besoin des deux, dans cet ordre, et aucun autre test n'en dépend.
Future<T> _sansReseau<T>(Future<T> Function() action) {
  final MockClient client = _client();
  return _avecCapture(() => http.runWithClient(action, () => client));
}

// ════════════════════════════ FORMULAIRE RÉEL ══════════════════════════════

/// Signature EXACTE du SEUL débordement toléré.
///
/// Mesuré sur `_AjouterCourseSheet`, ligne d'en-tête de la course, viewport
/// simulé 900 × 1800 / dpr 1.0 (largeur utile mesurée : 408,8 px) :
///   « A RenderFlex overflowed by 0.750 pixels on the right. »
///
/// ⚠️ Ce n'est PAS un filtre « ça contient *overflowed* ». Un débordement
/// provoqué par le code de B2-C, ou le même à une AUTRE valeur de pixels ou
/// dans une autre direction, n'est pas toléré : il fait échouer le test.
const String kSignatureDebordementConnu =
    'A RenderFlex overflowed by 0.750 pixels on the right';

/// Débordements connus effectivement observés, et erreurs REFUSÉES.
List<String> _debordements = <String>[];
List<String> _erreursNonTolerees = <String>[];

/// Vrai UNIQUEMENT pour la signature mesurée ci-dessus.
bool _estDebordementConnu(FlutterErrorDetails details) =>
    details.toString().contains(kSignatureDebordementConnu);

/// Exécute [corps] sous interception STRICTE des erreurs Flutter.
///
/// Contrat — c'est lui qui rend les 5 exigences vérifiables :
///  1. la portée est le corps du test : l'interception est installée ici et
///     retirée dans `finally`, donc jamais au-delà du test concerné ;
///  2. le gestionnaire précédent est capturé dans une variable **locale**
///     (aucune globale ne peut être écrasée par un appel imbriqué) et
///     restauré INCONDITIONNELLEMENT, y compris si le corps lève ;
///  3. SEUL [kSignatureDebordementConnu] est toléré — tout autre débordement
///     tombe dans la branche de refus ;
///  4. toute autre exception Flutter est consignée dans
///     [_erreursNonTolerees] ET transmise au gestionnaire précédent ;
///  5. une erreur refusée fait échouer le test APRÈS la restauration, donc
///     même si toutes les assertions du corps étaient vertes.
Future<T> _avecCapture<T>(Future<T> Function() corps) async {
  final FlutterExceptionHandler? precedent = FlutterError.onError;
  _debordements = <String>[];
  _erreursNonTolerees = <String>[];

  FlutterError.onError = (FlutterErrorDetails details) {
    if (_estDebordementConnu(details)) {
      _debordements.add(details.toString().replaceAll('\n', ' '));
      return; // préexistant, sans rapport avec B2-C : compté et rapporté.
    }
    _erreursNonTolerees.add(details.toString().replaceAll('\n', ' '));
    precedent?.call(details); // le binding conserve son propre traitement
  };

  T? resultat;
  Object? erreurCorps;
  StackTrace? pileCorps;
  try {
    resultat = await corps();
  } catch (e, st) {
    erreurCorps = e;
    pileCorps = st;
  } finally {
    FlutterError.onError = precedent; // (2) restauration inconditionnelle
  }

  // Le corps a levé : on propage l'erreur d'origine, sans la masquer.
  if (erreurCorps != null) {
    Error.throwWithStackTrace(erreurCorps, pileCorps!);
  }

  // (4) et (5) : aucune erreur refusée ne peut cohabiter avec un test vert.
  if (_erreursNonTolerees.isNotEmpty) {
    fail('HARNAIS B2-C : ${_erreursNonTolerees.length} erreur(s) Flutter '
        'NON tolérée(s) — une seule signature est admise '
        '($kSignatureDebordementConnu).\n'
        'Aucune assertion ne peut rendre ce test vert :\n'
        '${_erreursNonTolerees.map((String e) => '  • $e').join('\n')}');
  }

  return resultat as T;
}

/// Monte le VÉRITABLE `MesPariScreen` sur l'onglet 0 (« Favoris »), seul
/// onglet où le FAB « Suivre une course » existe
/// (`mes_paris_screen.dart:244-252` : `_tabCtrl.index == 0 ? FAB : null`).
Future<void> _monterMesParis(WidgetTester tester, PmuProvider pmu) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 1800);
  addTearDown(tester.view.reset);

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
      child: const MaterialApp(home: MesPariScreen(initialTab: 0)),
    ),
  );

  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Appuie sur le FAB puis attend que le dialog ait CHARGÉ le programme et
/// ouvert le VRAI `_AjouterCourseSheet`.
Future<void> _ouvrirSheetAjout(WidgetTester tester) async {
  final Finder fab = find.text('Suivre une course');
  expect(fab, findsWidgets,
      reason: 'TÉMOIN : le FAB « Suivre une course » de l\'onglet 0 doit '
          'être rendu (mes_paris_screen.dart:244-252)');
  await tester.tap(fab.first, warnIfMissed: false);
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(find.text('Choisissez une course à venir :'), findsWidgets,
      reason: 'TÉMOIN : le VRAI _AjouterCourseSheet est ouvert avec au moins '
          'une course future issue du programme servi');
}

/// Sélectionne la course proposée (ligne « R1C3 PRIX B2-C »).
Future<void> _choisirCourse(WidgetTester tester) async {
  final Finder course = find.text('PRIX B2-C');
  expect(course, findsWidgets,
      reason: 'TÉMOIN : la course du programme servi est listée');
  await tester.tap(course.first, warnIfMissed: false);
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Choisit le type de pari dans le VRAI `DropdownButton<String>`
/// (`mes_paris_screen.dart:2952-2964`) — c'est l'unique sélecteur de ce sheet,
/// il n'y a donc pas de doublon à départager ici (contrairement à B2-A).
Future<void> _choisirTypePari(WidgetTester tester, String libelle) async {
  final Finder dropdown = find.byType(DropdownButton<String>);
  expect(dropdown, findsWidgets,
      reason: 'TÉMOIN : le DropdownButton du type de pari doit être rendu');
  await tester.tap(dropdown.first, warnIfMissed: false);
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  // Le menu du Dropdown rend chaque item une seconde fois : on prend le
  // DERNIER, qui est celui de la route de menu (le plus récemment poussé).
  final Finder item = find.text(libelle);
  expect(item, findsWidgets,
      reason: 'TÉMOIN : l\'item « $libelle » doit être proposé');
  await tester.tap(item.last, warnIfMissed: false);
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Saisit une mise dans le champ « Mise (€) » (`mes_paris_screen.dart:2970+`).
/// `enterText` déclenche bien `onChanged: (v) => _mise = ...`.
Future<void> _saisirMise(WidgetTester tester, double montant) async {
  final Finder champ = find.widgetWithText(TextField, 'Mise (€)');
  final Finder cible =
      champ.evaluate().isNotEmpty ? champ : find.byType(TextField).last;
  expect(cible, findsWidgets,
      reason: 'TÉMOIN : le champ de mise doit être rendu');
  await tester.enterText(cible.first, montant.toStringAsFixed(0));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 40));
}

/// Appuie sur « Ajouter le suivi » (`mes_paris_screen.dart:2992-3027`).
Future<void> _ajouterSuivi(WidgetTester tester) async {
  final Finder bouton = find.text('Ajouter le suivi');
  expect(bouton, findsWidgets,
      reason: 'TÉMOIN : le bouton « Ajouter le suivi » doit être rendu');
  await tester.tap(bouton.first, warnIfMissed: false);
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PmuProvider pmu;

  setUp(() async {
    await _resetServices();
    await _fermerSuivis();
    pmu = PmuProvider();
  });

  // `AlertService` est un singleton `ChangeNotifier` : `dispose()` est
  // irréversible, on nettoie donc par `retirerSuivi`.
  tearDown(() async {
    await _fermerSuivis();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-C-T1 — SÉRIALISATION : `toJson` écrit les 2 clés, `fromJson` relit.
  // ═══════════════════════════════════════════════════════════════════════
  test(
      'B2C-T1 — toJson écrit miseGagnant/misePlace et une relecture '
      'fromJson les restitue à l\'identique', () {
    final TrackedCourse gp = _suiviGP();
    final Map<String, dynamic> json = gp.toJson();

    // ignore: avoid_print
    print('─── MESURE B2C-T1 (sérialisation) ───────────────────────────');
    // ignore: avoid_print
    print('  toJson[miseEngagee] = ${json['miseEngagee']}');
    // ignore: avoid_print
    print('  toJson[miseGagnant] = ${json['miseGagnant']}');
    // ignore: avoid_print
    print('  toJson[misePlace]   = ${json['misePlace']}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(json.containsKey('miseGagnant'), isTrue,
        reason: 'B2-C : la clé doit être sérialisée');
    expect(json.containsKey('misePlace'), isTrue,
        reason: 'B2-C : la clé doit être sérialisée');
    expect(json['miseGagnant'], kMiseDefautFormulaire);
    expect(json['misePlace'], kMiseDefautFormulaire);

    final TrackedCourse relu = TrackedCourse.fromJson(json);

    expect(relu.miseGagnant, gp.miseGagnant,
        reason: 'B2-C : fromJson doit restituer miseGagnant');
    expect(relu.misePlace, gp.misePlace,
        reason: 'B2-C : fromJson doit restituer misePlace');
    expect(relu.miseEngagee, gp.miseEngagee,
        reason: 'B2-C : miseEngagee est inchangée');
    // RÈGLE MÉTIER : 10 € saisis = 20 € réellement engagés.
    expect(relu.miseTotaleEngagee, 2 * kMiseDefautFormulaire,
        reason:
            'B2-C : total engagé = Gagnant + Placé, sans division par deux');
    expect(relu.misesGagnantPlaceIncompletes, isFalse,
        reason: 'B2-C : les deux composantes sont présentes, donc complètes');
    expect(relu.storageKey, kStorageKey,
        reason: 'B2-C : storageKey traverse la sérialisation');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-C-T2 — LES TROIS COPIES conservent composantes ET `storageKey`.
  //
  //  `TrackedCourse` n'a pas de `copyWith` : `withResultat` et `withDividende`
  //  recopient champ par champ, et `AlertService.ajouterSuivi` fait de même
  //  (`alert_service.dart:721-742`). Trois zones distinctes, trois occasions
  //  de perte — c'est exactement le défaut corrigé par R1 sur `storageKey`.
  // ═══════════════════════════════════════════════════════════════════════
  test(
      'B2C-T2 — withResultat, withDividende et ajouterSuivi conservent '
      'miseGagnant, misePlace ET storageKey', () async {
    final TrackedCourse gp = _suiviGP();

    // ── Copie 1 : withResultat ──────────────────────────────────────────
    final TrackedCourse avecResultat = gp.withResultat(
      isGagne: true,
      arrivee: const <int>[7, 1],
      message: '🏆 Gagnant !',
    );

    // ── Copie 2 : withDividende ─────────────────────────────────────────
    final TrackedCourse avecDividende = gp.withDividende(
      dividende: 12.5,
      combinaison: '7',
    );

    // ── Copie 3 : ajouterSuivi (copie interne du service) ───────────────
    await _resetServices();
    await AlertService.instance.ajouterSuivi(gp);
    final Map<String, TrackedCourse> suivis =
        AlertService.instance.trackedCourses;
    expect(suivis, hasLength(1),
        reason: 'TÉMOIN : un suivi a bien été enregistré');

    final String cleHorodatee = suivis.keys.first;
    final TrackedCourse apresSuivi = suivis[cleHorodatee]!;

    // ignore: avoid_print
    print('─── MESURE B2C-T2 (les trois copies) ────────────────────────');
    // ignore: avoid_print
    print('  withResultat  : G=${avecResultat.miseGagnant} '
        'P=${avecResultat.misePlace} total=${avecResultat.miseTotaleEngagee} '
        'sk=${avecResultat.storageKey}');
    // ignore: avoid_print
    print('  withDividende : G=${avecDividende.miseGagnant} '
        'P=${avecDividende.misePlace} total=${avecDividende.miseTotaleEngagee} '
        'sk=${avecDividende.storageKey}');
    // ignore: avoid_print
    print('  ajouterSuivi  : clé=$cleHorodatee G=${apresSuivi.miseGagnant} '
        'P=${apresSuivi.misePlace} total=${apresSuivi.miseTotaleEngagee} '
        'sk=${apresSuivi.storageKey}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    // withResultat
    expect(avecResultat.miseGagnant, kMiseDefautFormulaire,
        reason: 'B2-C : withResultat doit propager miseGagnant');
    expect(avecResultat.misePlace, kMiseDefautFormulaire,
        reason: 'B2-C : withResultat doit propager misePlace');
    expect(avecResultat.storageKey, kStorageKey,
        reason: 'R1 préservé : withResultat propage storageKey');

    // withDividende
    expect(avecDividende.miseGagnant, kMiseDefautFormulaire,
        reason: 'B2-C : withDividende doit propager miseGagnant');
    expect(avecDividende.misePlace, kMiseDefautFormulaire,
        reason: 'B2-C : withDividende doit propager misePlace');
    expect(avecDividende.storageKey, kStorageKey,
        reason: 'R1 préservé : withDividende propage storageKey');

    // ajouterSuivi
    expect(apresSuivi.miseGagnant, kMiseDefautFormulaire,
        reason: 'B2-C : SANS la propagation dans ajouterSuivi '
            '(alert_service.dart:729+), la ventilation serait perdue ici — '
            'exactement le défaut R1 sur storageKey');
    expect(apresSuivi.misePlace, kMiseDefautFormulaire,
        reason: 'B2-C : idem pour misePlace');
    expect(apresSuivi.storageKey, cleHorodatee,
        reason: 'R1 préservé : la copie porte la clé HORODATÉE, pas la clé '
            'passée par l\'appelant');
    expect(cleHorodatee, startsWith(kBaseKey),
        reason: 'TÉMOIN : la clé suit le format R\\d+C\\d+_\\d{8}_<ms>');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-C-T3 — PERSISTANCE RÉELLE : disque puis `recharger()`.
  //
  //  Sans la propagation dans `ajouterSuivi` OU dans `toJson`, la ventilation
  //  survivrait en RAM et disparaîtrait au rechargement : ce test l'interdit.
  // ═══════════════════════════════════════════════════════════════════════
  test(
      'B2C-T3 — ajouterSuivi → disque → recharger : la ventilation G+P '
      'survit au redémarrage', () async {
    await _resetServices();
    await AlertService.instance.ajouterSuivi(_suiviGP());

    // ── Ce qui a RÉELLEMENT été écrit sur disque ────────────────────────
    final List<Map<String, dynamic>> disque = await _trackedSurDisque();
    final Map<String, dynamic>? surDisque =
        disque.isEmpty ? null : disque.first;

    // ignore: avoid_print
    print('─── MESURE B2C-T3 (disque) ──────────────────────────────────');
    // ignore: avoid_print
    print('  miseEngagee sur disque : ${surDisque?['miseEngagee']}');
    // ignore: avoid_print
    print('  miseGagnant sur disque : ${surDisque?['miseGagnant']}');
    // ignore: avoid_print
    print('  misePlace   sur disque : ${surDisque?['misePlace']}');
    // ignore: avoid_print
    print('  typePari    sur disque : ${surDisque?['typePari']}');
    // ignore: avoid_print
    print('  storageKey  sur disque : ${surDisque?['storageKey']}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(surDisque, isNotNull, reason: 'TÉMOIN : une entrée est écrite');
    expect(surDisque!['miseGagnant'], kMiseDefautFormulaire,
        reason: 'B2-C : miseGagnant est écrite sur disque');
    expect(surDisque['misePlace'], kMiseDefautFormulaire,
        reason: 'B2-C : misePlace est écrite sur disque');
    final String skSurDisque = surDisque['storageKey'] as String;

    // ── Rechargement RÉEL depuis les préférences ────────────────────────
    await AlertService.instance.recharger();
    final Map<String, TrackedCourse> apres =
        AlertService.instance.trackedCourses;

    // ignore: avoid_print
    print('  après rechargement : clés=${apres.keys.toList()}');

    expect(apres.containsKey(skSurDisque), isTrue,
        reason: 'B2-C : la clé d\'origine doit être retrouvée après '
            'rechargement. Clés mesurées : ${apres.keys.toList()}');

    final TrackedCourse relu = apres[skSurDisque]!;
    expect(relu.miseGagnant, kMiseDefautFormulaire,
        reason: 'B2-C : miseGagnant survit au rechargement');
    expect(relu.misePlace, kMiseDefautFormulaire,
        reason: 'B2-C : misePlace survit au rechargement');
    expect(relu.miseTotaleEngagee, 2 * kMiseDefautFormulaire,
        reason: 'B2-C : 10 € saisis = 20 € engagés, aussi après rechargement');
    expect(relu.misesGagnantPlaceIncompletes, isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-C-T4 — RÉTROCOMPATIBILITÉ : données ANTÉRIEURES à B2-C.
  //
  //  Un appareil déjà installé contient des JSON SANS les deux nouvelles
  //  clés. `fromJson` doit rendre null (aucune exception, aucune valeur
  //  inventée) et `miseTotaleEngagee` doit retomber sur `miseEngagee`.
  // ═══════════════════════════════════════════════════════════════════════
  test(
      'B2C-T4 — un JSON hérité sans les 2 clés se relit sans erreur et '
      'retombe sur miseEngagee', () async {
    final Map<String, dynamic> herite = _jsonHerite();
    expect(herite.containsKey('miseGagnant'), isFalse,
        reason: 'TÉMOIN : le fixture est bien un JSON d\'AVANT B2-C');
    expect(herite.containsKey('misePlace'), isFalse,
        reason: 'TÉMOIN : idem pour misePlace');

    final TrackedCourse relu = TrackedCourse.fromJson(herite);

    // ignore: avoid_print
    print('─── MESURE B2C-T4 (JSON hérité) ─────────────────────────────');
    // ignore: avoid_print
    print('  miseEngagee     = ${relu.miseEngagee}');
    // ignore: avoid_print
    print('  miseGagnant     = ${relu.miseGagnant}');
    // ignore: avoid_print
    print('  misePlace       = ${relu.misePlace}');
    // ignore: avoid_print
    print('  miseTotaleEngagee = ${relu.miseTotaleEngagee}');
    // ignore: avoid_print
    print('  incompletes     = ${relu.misesGagnantPlaceIncompletes}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(relu.miseGagnant, isNull,
        reason: 'B2-C : clé absente → null, aucune valeur inventée');
    expect(relu.misePlace, isNull,
        reason: 'B2-C : clé absente → null, aucune valeur inventée');
    expect(relu.miseTotaleEngagee, kMiseDefautFormulaire,
        reason: 'Contrat B1 : les deux composantes nulles → miseEngagee '
            '(comportement historique préservé)');
    expect(relu.misesGagnantPlaceIncompletes, isFalse,
        reason: 'Contrat B1 : 0//0 n\'est PAS un état incomplet');
    expect(relu.storageKey, kStorageKey,
        reason: 'TÉMOIN : storageKey héritée relue correctement');

    // ── Le même JSON hérité passe aussi par le VRAI `_load()` ───────────
    await _resetServices(tracked: <String>[json.encode(herite)]);
    final Map<String, TrackedCourse> charges =
        AlertService.instance.trackedCourses;

    expect(charges.containsKey(kStorageKey), isTrue,
        reason: 'TÉMOIN : _load() accepte toujours l\'entrée héritée');
    final TrackedCourse charge = charges[kStorageKey]!;
    expect(charge.miseGagnant, isNull,
        reason: 'B2-C : _load() sur donnée héritée → miseGagnant null');
    expect(charge.miseTotaleEngagee, kMiseDefautFormulaire,
        reason: 'B2-C : aucun total fictif pour une donnée héritée');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-C-T5 — CONTRAT B1 des deux getters, sur les TROIS cas.
  //
  //  Ces getters ne sont PAS de simples sommes : le cas « une seule
  //  composante » doit rendre `null` (état incomplet signalé) et non un
  //  total partiel trompeur. C'est le cœur du contrat gelé en B1.
  // ═══════════════════════════════════════════════════════════════════════
  test(
      'B2C-T5 — miseTotaleEngagee / misesGagnantPlaceIncompletes : '
      'les trois cas du contrat B1', () async {
    // Cas 1 : les deux nulles → miseEngagee (historique)
    final TrackedCourse cas1 = _suiviSimple();
    // Cas 2 : une seule nulle → null (incomplet)
    final TrackedCourse cas2a =
        _suiviGP(miseGagnant: 10.0, misePlace: null, miseEngagee: 10.0);
    final TrackedCourse cas2b =
        _suiviGP(miseGagnant: null, misePlace: 10.0, miseEngagee: 10.0);
    // Cas 3 : les deux présentes → somme. Composantes DIFFÉRENTES pour
    // prouver qu'il s'agit d'une somme et non d'un « doublage » de l'une.
    final TrackedCourse cas3 =
        _suiviGP(miseGagnant: 10.0, misePlace: 4.0, miseEngagee: 10.0);

    // ignore: avoid_print
    print('─── MESURE B2C-T5 (contrat des getters) ─────────────────────');
    // ignore: avoid_print
    print('  cas 1 (null, null)   : total=${cas1.miseTotaleEngagee} '
        'incomplet=${cas1.misesGagnantPlaceIncompletes}');
    // ignore: avoid_print
    print('  cas 2a (10, null)    : total=${cas2a.miseTotaleEngagee} '
        'incomplet=${cas2a.misesGagnantPlaceIncompletes}');
    // ignore: avoid_print
    print('  cas 2b (null, 10)    : total=${cas2b.miseTotaleEngagee} '
        'incomplet=${cas2b.misesGagnantPlaceIncompletes}');
    // ignore: avoid_print
    print('  cas 3  (10, 4)       : total=${cas3.miseTotaleEngagee} '
        'incomplet=${cas3.misesGagnantPlaceIncompletes}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(cas1.miseTotaleEngagee, 10.0,
        reason: 'Contrat B1, cas 1 : aucune ventilation → miseEngagee');
    expect(cas1.misesGagnantPlaceIncompletes, isFalse);

    expect(cas2a.miseTotaleEngagee, isNull,
        reason: 'Contrat B1, cas 2 : Placé manquant → AUCUN total inventé');
    expect(cas2a.misesGagnantPlaceIncompletes, isTrue,
        reason: 'Contrat B1 : l\'incomplétude doit être signalée');

    expect(cas2b.miseTotaleEngagee, isNull,
        reason: 'Contrat B1, cas 2 symétrique : Gagnant manquant → null');
    expect(cas2b.misesGagnantPlaceIncompletes, isTrue);

    expect(cas3.miseTotaleEngagee, 14.0,
        reason: 'Contrat B1, cas 3 : 10 + 4 = 14 (vraie somme)');
    expect(cas3.misesGagnantPlaceIncompletes, isFalse);

    // Les deux cas 2 se sérialisent SANS perte d'information : le champ
    // manquant reste null sur disque, il n'est pas « complété » par 0.
    final TrackedCourse reluCas2 = TrackedCourse.fromJson(cas2a.toJson());
    expect(reluCas2.miseGagnant, 10.0);
    expect(reluCas2.misePlace, isNull,
        reason: 'B2-C : un Placé absent reste absent, jamais 0.0');
    expect(reluCas2.misesGagnantPlaceIncompletes, isTrue,
        reason: 'B2-C : l\'état incomplet survit à la sérialisation');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-C-T6 — FORMULAIRE RÉEL, type « Gagnant+Placé ».
  //
  //  Parcours intégral d'un UTILISATEUR : MesPariScreen (onglet 0) → FAB
  //  « Suivre une course » → programme PMU (servi par MockClient) → sélection
  //  de la course → type « Gagnant+Placé » → « Ajouter le suivi ».
  //  On lit ensuite ce qui a RÉELLEMENT été enregistré.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets(
      'B2C-T6 — le VRAI formulaire, type Gagnant+Placé : '
      'miseGagnant = misePlace = mise saisie, total = 2 × la mise',
      (WidgetTester tester) async {
    late TrackedCourse tc;
    // (2) MESURE de la restauration : identité du gestionnaire AVANT/APRÈS.
    final FlutterExceptionHandler? gestionnaireAvant = FlutterError.onError;

    await _sansReseau(() async {
      await _monterMesParis(tester, pmu);
      await _ouvrirSheetAjout(tester);
      await _choisirCourse(tester);
      await _choisirTypePari(tester, 'Gagnant+Placé');

      // Mise par DÉFAUT du formulaire (10), volontairement NON saisie ici :
      // on vérifie d'abord le comportement sans interaction sur le champ.
      await _ajouterSuivi(tester);

      final Map<String, TrackedCourse> suivis =
          AlertService.instance.trackedCourses;
      expect(suivis, hasLength(1),
          reason: 'TÉMOIN : un seul suivi doit être créé');
      tc = suivis.values.first;

      // ignore: avoid_print
      print('─── MESURE B2C-T6 (formulaire réel, G+P) ────────────────────');
      // ignore: avoid_print
      print('  typePari        : ${tc.typePari}');
      // ignore: avoid_print
      print('  miseEngagee     : ${tc.miseEngagee}');
      // ignore: avoid_print
      print('  miseGagnant     : ${tc.miseGagnant}');
      // ignore: avoid_print
      print('  misePlace       : ${tc.misePlace}');
      // ignore: avoid_print
      print('  miseTotaleEngagee : ${tc.miseTotaleEngagee}');
      // ignore: avoid_print
      print('  incompletes     : ${tc.misesGagnantPlaceIncompletes}');
      // ignore: avoid_print
      print('  storageKey      : ${tc.storageKey}');
      // ignore: avoid_print
      print('  débordements    : ${_debordements.length}');
      // ignore: avoid_print
      print('──────────────────────────────────────────────────────────────');
    });

    // ── TÉMOINS : c'est bien le VRAI parcours ──────────────────────────
    expect(tc.typePari, 'Gagnant+Placé',
        reason: 'TÉMOIN : le type sélectionné est bien enregistré');
    expect(tc.miseEngagee, kMiseDefautFormulaire,
        reason: 'B2-C : `miseEngagee` CONSERVE la mise saisie (inchangée)');
    expect(tc.numReunion, kNumR);
    expect(tc.numCourse, kNumC);

    // ── B2-C : la ventilation est enregistrée ──────────────────────────
    expect(tc.miseGagnant, tc.miseEngagee,
        reason: 'B2-C : miseGagnant = mise saisie, TELLE QUELLE');
    expect(tc.misePlace, tc.miseEngagee,
        reason: 'B2-C : misePlace = mise saisie, TELLE QUELLE. '
            'La mise n\'est JAMAIS divisée par deux.');
    expect(tc.miseGagnant, isNotNull);
    expect(tc.misePlace, isNotNull);
    expect(tc.misesGagnantPlaceIncompletes, isFalse,
        reason: 'B2-C : les deux composantes sont renseignées');

    // RÈGLE MÉTIER IMPÉRATIVE, exprimée en RELATION (aucune constante figée).
    expect(tc.miseTotaleEngagee, 2 * tc.miseEngagee!,
        reason: 'B2-C : 10 € saisis = 10 € Gagnant + 10 € Placé = 20 € '
            'engagés. Le total est le DOUBLE de la mise saisie, pas la mise.');
    expect(tc.miseTotaleEngagee, tc.miseGagnant! + tc.misePlace!,
        reason: 'B2-C : le total EST la somme des deux composantes');

    // ── R1 préservé : la clé est horodatée par `ajouterSuivi` ──────────
    expect(tc.storageKey, isNotNull);
    expect(tc.storageKey, startsWith(kBaseKey),
        reason: 'R1 préservé : ajouterSuivi fabrique une clé horodatée');

    // (2) MESURE : le harnais a rendu le gestionnaire d'origine, à l'identique.
    expect(identical(FlutterError.onError, gestionnaireAvant), isTrue,
        reason: 'HARNAIS B2-C : FlutterError.onError doit être RESTAURÉ à '
            'l\'identique après _avecCapture (aucune fuite inter-tests)');

    await _demonter(tester);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2-C-T7 — NON-RÉGRESSION du formulaire : les paris SIMPLES restent
  //  mono-composante.
  //
  //  Ici la mise est SAISIE (25 €), pour prouver deux choses d'un coup :
  //  la saisie se propage bien, et la ventilation reste à null hors G+P.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets(
      'B2C-T7 — le VRAI formulaire en Simple Gagnant : aucune '
      'ventilation, miseTotaleEngagee == miseEngagee (non-régression)',
      (WidgetTester tester) async {
    late TrackedCourse tc;
    // (2) MESURE de la restauration : identité du gestionnaire AVANT/APRÈS.
    final FlutterExceptionHandler? gestionnaireAvant = FlutterError.onError;

    await _sansReseau(() async {
      await _monterMesParis(tester, pmu);
      await _ouvrirSheetAjout(tester);
      await _choisirCourse(tester);
      await _saisirMise(tester, kMiseSaisieT7);
      // Type laissé à sa valeur par défaut « Simple Gagnant » (l.2695).
      await _ajouterSuivi(tester);

      final Map<String, TrackedCourse> suivis =
          AlertService.instance.trackedCourses;
      expect(suivis, hasLength(1),
          reason: 'TÉMOIN : un seul suivi doit être créé');
      tc = suivis.values.first;

      // ignore: avoid_print
      print('─── MESURE B2C-T7 (formulaire réel, Simple) ─────────────────');
      // ignore: avoid_print
      print('  typePari        : ${tc.typePari}');
      // ignore: avoid_print
      print('  miseEngagee     : ${tc.miseEngagee}');
      // ignore: avoid_print
      print('  miseGagnant     : ${tc.miseGagnant}');
      // ignore: avoid_print
      print('  misePlace       : ${tc.misePlace}');
      // ignore: avoid_print
      print('  miseTotaleEngagee : ${tc.miseTotaleEngagee}');
      // ignore: avoid_print
      print('  incompletes     : ${tc.misesGagnantPlaceIncompletes}');
      // ignore: avoid_print
      print('──────────────────────────────────────────────────────────────');
    });

    expect(tc.typePari, 'Simple Gagnant',
        reason: 'TÉMOIN : type par défaut du formulaire (l.2695)');
    expect(tc.miseEngagee, kMiseSaisieT7,
        reason: 'Non-régression : la mise SAISIE se propage à l\'identique, '
            'donc ni divisée ni doublée');
    expect(tc.miseGagnant, isNull,
        reason: 'B2-C : hors G+P, miseGagnant reste null');
    expect(tc.misePlace, isNull,
        reason: 'B2-C : hors G+P, misePlace reste null');
    expect(tc.misesGagnantPlaceIncompletes, isFalse,
        reason: 'Contrat B1 : deux null ne forment pas un état incomplet');
    expect(tc.miseTotaleEngagee, kMiseSaisieT7,
        reason: 'Contrat B1 : aucune ventilation → miseEngagee, '
            'comportement historique intact');

    // (2) MESURE : le harnais a rendu le gestionnaire d'origine, à l'identique.
    expect(identical(FlutterError.onError, gestionnaireAvant), isTrue,
        reason: 'HARNAIS B2-C : FlutterError.onError doit être RESTAURÉ à '
            'l\'identique après _avecCapture (aucune fuite inter-tests)');

    await _demonter(tester);
  });
}
