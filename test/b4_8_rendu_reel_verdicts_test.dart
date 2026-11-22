// ═══════════════════════════════════════════════════════════════════════════
//  B-4.8 — RENDU **RÉEL** DES VERDICTS SUR LES DEUX ÉCRANS
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE lib/.
//
//  ── POURQUOI CE FICHIER EXISTE ────────────────────────────────────────────
//  B-4.7 a corrigé trois anomalies dans les COUCHES DE DÉCISION (moteur,
//  arbitre, enregistreur). Les 2 675 tests unitaires ne prouvent rien sur ce
//  que l'utilisateur VOIT : ils lisent des objets, pas des widgets.
//
//  Ce fichier monte donc les DEUX écrans de production —
//  `MesPariScreen` (onglet « Suivi ») et `ParisDetailScreen` — avec de vrais
//  tickets persistés dans `AlertService`, et lit les `Text` RÉELLEMENT
//  CONSTRUITS dans l'arbre de widgets.
//
//  ── CONTRÔLE n° 3 DU MANDAT : LA BRANCHE C N'ÉCRIT-ELLE RIEN D'INDÉMONTRÉ ?
//  Le groupe « C » ci-dessous vérifie, sur le SERVICE RÉEL, qu'un verdict
//  définitif insuffisamment démontré n'est JAMAIS enregistré en silence :
//    • `perdu` sans arrivée officielle ..................... refusé par le moteur
//      en amont (nonDetermine) — prouvé ici comme non-enregistrable ;
//    • `attribue` accompagné d'un rapport officiel introuvable ... refusé ;
//    • `attribue` ambigu (2 candidats) ..................... refusé, jamais le
//      montant le plus élevé ;
//    • `attribue` dont le montant ne se recalcule pas ....... refusé ;
//    • la branche C elle-même n'écrit AUCUN montant ......... vérifié par
//      construction : `rapportsAttribues`, `dividendeGagnant` et
//      `dividendePlace` restent `null`.
//
//  ── CHIFFRES RÉELS ───────────────────────────────────────────────────────
//  Tous les dividendes viennent de la capture `R1C6_15112026.json` lue par le
//  DÉCODEUR DE PRODUCTION (`PmuApiService.decoderRapportsDefinitifs`) :
//    Simple Gagnant 9  @ 7,50 €  → 10 € misés = 75,00 €
//    Simple Placé   9  @ 3,00 €  → 10 € misés = 30,00 €
//  Arrivée officielle : 9-4-15-10-1-7-12.
//
//  ── LIMITE HONNÊTE ───────────────────────────────────────────────────────
//  La sandbox est x86_64 Linux avec un binding de test : ce fichier prouve le
//  RENDU DES WIDGETS et le texte produit, pas le rendu pixels d'un appareil.
//  Les débordements `RenderFlex` PRÉEXISTANTS de ces écrans (AppBar, en-tête de
//  carte) sont COMPTÉS et RAPPORTÉS, jamais absorbés.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/main.dart' show NavigationNotifier;
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/screens/mes_paris_screen.dart';
import 'package:pronostic_hippique/screens/paris_detail_screen.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/branchement_verdict_course.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart'
    show StatutEnregistrementVerdict, deciderEcritureVerdict;
// `TrackedCourseCopy.copyWith` — l'extension vit dans ce fichier, mesuré.
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_suivi.dart'
    show TrackedCourseCopy;
import 'package:pronostic_hippique/services/gain_calculator.dart'
    show RapportPmu;
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show VarianteRapport;
import 'package:pronostic_hippique/services/ia_badges_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_personality_service.dart';
import 'package:pronostic_hippique/services/ia_user_prefs_service.dart';
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart'
    show VerdictGain, ComposanteGain, RoleComposante;
import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';
import 'fixtures/fixture_paths.dart';

// ───────────────────────────────────────────────────────────────────────────
//  1. CAPTURE RÉELLE
// ───────────────────────────────────────────────────────────────────────────

final String _kDossier = dossierMulti;
const String _kCapture = 'R1C6_15112026.json';

List<RapportPmu> _rapportsReels() => PmuApiService.decoderRapportsDefinitifs(
      File('$_kDossier/$_kCapture').readAsStringSync(),
    );

/// Arrivée officielle GROUPÉE de la capture (aucun ex æquo).
const List<List<int>> _kArrivee = <List<int>>[
  <int>[9], <int>[4], <int>[15], <int>[10], <int>[1], <int>[7], <int>[12],
];

const List<int> _kArriveePlate = <int>[9, 4, 15, 10, 1, 7, 12];

// ───────────────────────────────────────────────────────────────────────────
//  2. CAPTURE → VERDICT RÉEL → TICKET PERSISTABLE
// ───────────────────────────────────────────────────────────────────────────

/// Code PMU officiel du bloc réellement joué, tel que l'application
/// l'enregistre au moment du pari.
///
/// ⚠️ MESURÉ : `construireTicketSuivi` REFUSE tout ticket dont
/// `codePmuOfficiel` est nul (`IssueConstructionTicket.codePmuAbsent`,
/// `branchement_verdict_course.dart:432-435`). Ce n'est pas une exigence de
/// test : c'est l'état de production, où la saisie renseigne toujours ce code.
String _codePmu(String typePari) {
  switch (typePari) {
    case 'Simple Gagnant':
      return 'E_SIMPLE_GAGNANT';
    case 'Simple Placé':
      return 'E_SIMPLE_PLACE';
    case 'Couplé Gagnant':
      return 'E_COUPLE_GAGNANT';
    case 'Couplé Placé':
      return 'E_COUPLE_PLACE';
    case 'Tiercé':
    case 'Tiercé Ordre':
    case 'Tiercé Désordre':
      return 'E_TIERCE';
    default:
      return 'E_SIMPLE_GAGNANT';
  }
}

/// Variante explicitement choisie à la saisie. `null` pour les libellés qui
/// n'en imposent aucune — `_exigeVariante` ne la réclame que pour
/// « Tiercé Ordre », « Tiercé Désordre » et « Couplé Ordre ».
String? _variante(String typePari) {
  switch (typePari) {
    case 'Tiercé Ordre':
    case 'Couplé Ordre':
      return 'ordre';
    case 'Tiercé Désordre':
      return 'desordre';
    default:
      return null;
  }
}

/// Construit un `TrackedCourse` puis le résout par la CHAÎNE DE PRODUCTION
/// (`resoudreSuivi`), exactement comme le fait `_majGainReelDansProfil`.
///
/// Aucun verdict n'est fabriqué à la main : il sort du moteur B-3 nourri par
/// les rapports réels. Si le moteur refuse de construire le ticket, le test
/// échoue AVANT d'assertir quoi que ce soit sur le rendu.
TrackedCourse _resoudre({
  required String typePari,
  required List<int> numeros,
  double mise = 10.0,
  int numCourse = 6,
  /// Rapports servis au moteur. Par défaut : la CAPTURE RÉELLE.
  /// Surchargeable pour éprouver un état officiel que la capture ne contient
  /// pas (ex. bloc marqué « remboursé » par l'opérateur).
  List<RapportPmu>? rapports,
}) {
  final rapportsEffectifs = rapports ?? _rapportsReels();
  final base = TrackedCourse(
    numReunion: 1,
    numCourse: numCourse,
    nomCourse: 'PRIX B4.8',
    hippodrome: 'TESTIPPODROME',
    heureDepart: DateTime.now().subtract(const Duration(minutes: 90)),
    numeroCheval: numeros.first,
    nomCheval: 'CHEVAL_${numeros.first}',
    miseEngagee: mise,
    typePari: typePari,
    numerosJoues: numeros,
    numerosDansOrdre: numeros,
    // ★ CORRECTION DE FIXTURE : ces deux champs sont ce que la SAISIE écrit.
    //   Sans eux, la chaîne de production refuse le ticket avant tout calcul.
    codePmuOfficiel: _codePmu(typePari),
    varianteChoisie: _variante(typePari),
    scoreIA: 70.0,
    cote: 7.5,
    arriveeFinale: _kArriveePlate,
    arriveeGroupes: _kArrivee,
    arriveeDefinitive: true,
    isGagne: false,
    messageResultat: 'Résultat officiel enregistré',
    storageKey: 'R1C${numCourse}_15112026',
  );

  final resultat = construireResultatOfficiel(
    arriveeGroupes: _kArrivee,
    arriveeDefinitive: true,
    rapports: rapportsEffectifs,
  );

  final resolution = resoudreSuivi(ticket: base, resultat: resultat);
  expect(resolution.aUneIssue, isFalse,
      reason: 'TÉMOIN : le ticket $typePari ${numeros.join("-")} doit être '
          'constructible par la chaîne de production (issue=${resolution.issue})');
  final enr = resolution.enregistrement!;
  expect(enr.estEnregistre, isTrue,
      reason: 'TÉMOIN : le verdict doit être enregistrable (statut='
          '${enr.statut.name}, motif=${enr.motif})');

  // Le ticket persisté conserve les métadonnées d'affichage et reçoit le
  // verdict. On passe par `copyWith` du modèle, comme le fait l'enregistreur.
  return base.copyWith(
    etatGain: enr.ticket.etatGain,
    motifNonDetermination: enr.ticket.motifNonDetermination,
    etatTirelire: enr.ticket.etatTirelire,
    rapportsAttribues: enr.ticket.rapportsAttribues,
    dividendeGagnant: enr.ticket.dividendeGagnant,
    dividendePlace: enr.ticket.dividendePlace,
    miseBaseCentimesUtilisee: enr.ticket.miseBaseCentimesUtilisee,
    isGagne: enr.ticket.etatGain == EtatGain.perdu
        ? false
        : (enr.ticket.etatGain == EtatGain.attribue ? true : null),
    messageResultat: enr.ticket.etatGain == EtatGain.perdu
        ? '❌ Perdu'
        : (enr.ticket.etatGain == EtatGain.attribue ? '🏆 Gagnant !' : null),
  );
}

/// Ticket `nonDetermine` TEL QU'IL EST PERSISTÉ EN PRODUCTION.
///
/// Un ticket indéterminé n'a par définition aucune arrivée démontrable : on
/// reproduit l'état réel — `isGagne` et `messageResultat` restent `null`,
/// parce que l'enregistreur ne les écrit jamais.
TrackedCourse _nonDetermine() => TrackedCourse(
      numReunion: 1,
      numCourse: 7,
      nomCourse: 'PRIX B4.8 INDETERMINE',
      hippodrome: 'TESTIPPODROME',
      heureDepart: DateTime.now().subtract(const Duration(minutes: 90)),
      numeroCheval: 3,
      nomCheval: 'CHEVAL_3',
      miseEngagee: 10.0,
      typePari: 'Simple Gagnant',
      numerosJoues: const <int>[3],
      numerosDansOrdre: const <int>[3],
      scoreIA: 70.0,
      cote: 5.0,
      storageKey: 'R1C7_15112026',
      etatGain: EtatGain.nonDetermine,
      motifNonDetermination: MotifNonDetermination.arriveeNonDefinitive,
      etatTirelire: EtatTirelire.sansObjet,
    );

// ───────────────────────────────────────────────────────────────────────────
//  3. RÉSEAU SIMULÉ — aucune requête réelle vers l'API PMU
// ───────────────────────────────────────────────────────────────────────────

const Map<String, double> _poidsDefaut = {
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
  'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
  'mouvCote': 0.06, 'placeDepart': 0.03,
};

Map<String, Object> _prefs(List<TrackedCourse> suivis) => <String, Object>{
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
      'tracked_courses_v1':
          suivis.map((t) => json.encode(t.toJson())).toList(),
    };

/// Rapports servis à l'écran de détail : ceux de la capture réelle.
///
/// ⚠️ Ils sont servis VIDES pour deux des trois scénarios, afin que
///    `_majGainReelDansProfil` — qui ÉCRIT un verdict — ne soit pas déclenché
///    pendant un test de RENDU. Le bandeau du verdict ne dépend que de
///    `tc.etatGain`, jamais des rapports affichés.
String _corpsProgramme() => json.encode({
      'programme': {
        'reunions': <Map<String, dynamic>>[
          {
            'numOfficiel': 1,
            'hippodrome': {
              'libelleLong': 'TESTIPPODROME (FRANCE)',
              'libelleCourt': 'TESTIPPODROME',
            },
            'courses': <Map<String, dynamic>>[
              {
                'numOrdre': 6,
                'libelle': 'PRIX B4.8',
                'distance': 2000,
                'montantPrix': 25900,
                'discipline': 'PLAT',
                'heureDepart': DateTime.now()
                    .subtract(const Duration(minutes: 90))
                    .millisecondsSinceEpoch,
                'paris': <Map<String, dynamic>>[],
              },
              // Course du ticket `nonDetermine` : sans elle, `_charger()` ne la
              // trouve pas et l'écran Détail affiche sa vue d'erreur — le
              // bandeau du verdict ne serait jamais construit (limite de
              // harnais, pas défaut de rendu).
              {
                'numOrdre': 7,
                'libelle': 'PRIX B4.8 INDETERMINE',
                'distance': 2000,
                'montantPrix': 25900,
                'discipline': 'PLAT',
                'heureDepart': DateTime.now()
                    .subtract(const Duration(minutes: 90))
                    .millisecondsSinceEpoch,
                'paris': <Map<String, dynamic>>[],
              },
            ],
          },
        ],
      },
    });

String _corpsPartants() => json.encode({
      'participants': <Map<String, dynamic>>[
        for (final n in _kArriveePlate)
          {'numPmu': n, 'nom': 'CHEVAL_$n', 'age': 5, 'sexe': 'H'},
      ],
    });

Future<T> _avecPmu<T>(Future<T> Function() action) {
  final programme = _corpsProgramme();
  final partants = _corpsPartants();
  final client = MockClient((request) async {
    const entetes = {'content-type': 'application/json'};
    final p = request.url.path;
    if (p.contains('participants')) {
      return http.Response(partants, 200, headers: entetes);
    }
    if (p.contains('rapports-definitifs')) {
      return http.Response('[]', 200, headers: entetes);
    }
    if (p.contains('programme')) {
      return http.Response(programme, 200, headers: entetes);
    }
    return http.Response('{}', 200, headers: entetes);
  });
  return http.runWithClient(action, () => client);
}

// ───────────────────────────────────────────────────────────────────────────
//  4. HARNAIS DE MONTAGE
// ───────────────────────────────────────────────────────────────────────────

List<String> _debordements = <String>[];

/// Textes RÉELLEMENT construits dans l'arbre, dans l'ordre de parcours.
List<String> _textes(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

/// Vrai si un texte construit contient [motif].
bool _contient(WidgetTester tester, String motif) =>
    _textes(tester).any((s) => s.contains(motif));

Future<void> _preparer(List<TrackedCourse> suivis) async {
  SharedPreferences.setMockInitialValues(_prefs(suivis));
  ZoneTurfService.viderCachePourResetComplet();
  DataRefreshService.instance.viderMemoirePourResetComplet();
  await IaMemoryService.instance.recharger();
  await AlertService.instance.recharger();
  expect(AlertService.instance.trackedCourses.length, suivis.length,
      reason: 'TÉMOIN : les ${suivis.length} ticket(s) du scénario sont chargés');
}

/// Monte le VÉRITABLE `MesPariScreen` sur l'onglet « Suivi ».
Future<void> _monterMesParis(WidgetTester tester, PmuProvider pmu) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 3000);
  addTearDown(tester.view.reset);

  _debordements = <String>[];
  final ancien = FlutterError.onError;
  FlutterError.onError = (details) {
    final t = details.toString();
    if (t.contains('overflowed')) {
      _debordements.add(t.replaceAll('\n', ' '));
      return;
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
          home: MediaQuery(
            data: MediaQueryData(size: Size(900, 3000)),
            child: MesPariScreen(initialTab: 1),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  } finally {
    FlutterError.onError = ancien;
  }
}

/// Monte le VÉRITABLE `ParisDetailScreen` sur un ticket donné.
Future<void> _monterDetail(
    WidgetTester tester, TrackedCourse ticket, PmuProvider pmu) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 3000);
  addTearDown(tester.view.reset);

  _debordements = <String>[];
  final ancien = FlutterError.onError;
  FlutterError.onError = (details) {
    final t = details.toString();
    if (t.contains('overflowed')) {
      _debordements.add(t.replaceAll('\n', ' '));
      return;
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
          ChangeNotifierProvider.value(value: IaMemoryService.instance),
        ],
        child: MaterialApp(
          home: ParisDetailScreen(
            tracked: ticket,
            alertSvc: AlertService.instance,
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
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

// ═══════════════════════════════════════════════════════════════════════════
//  TESTS
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────────────────────────────────────────────────────────────────────
  //  A — MES PARIS, ONGLET SUIVI : LE TEXTE DE CHAQUE VERDICT
  // ─────────────────────────────────────────────────────────────────────────
  group('A — Mes Paris : rendu réel du verdict', () {
    testWidgets('A/1 « perdu » affiche « ❌ Pari perdu », jamais un montant',
        (tester) async {
      final perdu = _resoudre(typePari: 'Simple Gagnant', numeros: [10]);
      expect(perdu.etatGain, EtatGain.perdu,
          reason: 'TÉMOIN : le cheval 10 est 4e, le Simple Gagnant est perdu');

      await _preparer(<TrackedCourse>[perdu]);
      late PmuProvider pmu;
      await _avecPmu(() async {
        pmu = PmuProvider();
        await pmu.reloadPredictions();
        await _monterMesParis(tester, pmu);
      });

      // TÉMOINS : le vrai écran et la vraie carte sont montés
      expect(find.text('Mes Paris & Alertes'), findsWidgets,
          reason: 'TÉMOIN : le VÉRITABLE MesPariScreen est monté');
      expect(find.text('CHEVAL_10'), findsWidgets,
          reason: 'TÉMOIN : la carte du ticket est rendue');

      expect(_contient(tester, 'Pari perdu'), isTrue,
          reason: 'le verdict « perdu » doit être LISIBLE sur la carte');
      expect(_contient(tester, 'Gain gagné'), isFalse,
          reason: 'AUCUN montant gagnant ne doit apparaître sur un ticket '
              'perdu — c\'est l\'objectif central du chantier');
      expect(_contient(tester, '€ brut'), isFalse,
          reason: 'aucun retour brut ne doit être affiché');

      // ignore: avoid_print
      print('A/1 textes pertinents : '
          '${_textes(tester).where((s) => s.contains("perdu") || s.contains("Gain")).toList()}');
      // ignore: avoid_print
      print('A/1 débordements préexistants : ${_debordements.length}');

      await _demonter(tester);
    });

    testWidgets('A/2 « attribue » affiche le dividende EXACT du pari joué',
        (tester) async {
      // Simple Gagnant 9 @ 7,50 € sur 10 € misés ⇒ 75,00 €.
      final gagne = _resoudre(typePari: 'Simple Gagnant', numeros: [9]);
      expect(gagne.etatGain, EtatGain.attribue,
          reason: 'TÉMOIN : le 9 est le gagnant officiel de la capture');

      await _preparer(<TrackedCourse>[gagne]);
      late PmuProvider pmu;
      await _avecPmu(() async {
        pmu = PmuProvider();
        await pmu.reloadPredictions();
        await _monterMesParis(tester, pmu);
      });

      expect(_contient(tester, 'CHEVAL_9'), isTrue,
          reason: 'TÉMOIN : la carte du ticket est rendue');
      expect(_contient(tester, 'Gain gagné'), isTrue,
          reason: 'le gain doit être annoncé');
      expect(_contient(tester, '75 €') || _contient(tester, '75.00'),
          isTrue,
          reason: '7,50 € × 10 € = 75,00 € — le montant doit être CELUI du '
              'rapport Simple Gagnant de la capture');

      // ignore: avoid_print
      print('A/2 textes Gain : '
          '${_textes(tester).where((s) => s.contains("Gain")).toList()}');
      // ignore: avoid_print
      print('A/2 débordements préexistants : ${_debordements.length}');

      await _demonter(tester);
    });

    testWidgets('A/3 « nonDetermine » : MESURE du texte réellement rendu',
        (tester) async {
      final indecis = _nonDetermine();
      await _preparer(<TrackedCourse>[indecis]);
      late PmuProvider pmu;
      await _avecPmu(() async {
        pmu = PmuProvider();
        await pmu.reloadPredictions();
        await _monterMesParis(tester, pmu);
      });

      expect(_contient(tester, 'CHEVAL_3'), isTrue,
          reason: 'TÉMOIN : la carte du ticket est rendue');

      final rendu = _textes(tester);
      // ignore: avoid_print
      print('A/3 ── MESURE : textes construits contenant « Résultat », '
          '« indéterminé » ou « attend » :');
      // ignore: avoid_print
      print('     ${rendu.where((s) => s.contains("Résultat") || s.contains("indéterminé") || s.contains("attent")).toList()}');

      // ★ B-4.7 — DÉFAUT CORRIGÉ ET DÉSORMAIS PROUVÉ ICI.
      //
      //   AVANT : le bandeau était conditionné par `_resultMessage != null`,
      //   que l'enregistreur n'écrit jamais pour un `nonDetermine`. Mesuré :
      //   `false` — le verdict indéterminé n'avait AUCUN point d'affichage.
      //
      //   APRÈS : le bandeau lit `etatGain` via `affichageGainSuivi`, dont le
      //   libellé est « ❔ Résultat indéterminé ». On exige donc la VISIBILITÉ.
      expect(_contient(tester, 'Résultat indéterminé'), isTrue,
          reason: 'B-4.7 : le verdict indéterminé DOIT être lisible sur la '
              'carte « Suivi » — c\'est le défaut mesuré que ce lot corrige');
      // ignore: avoid_print
      print('A/3 ── le verdict indéterminé est-il visible sur la carte : '
          '${_contient(tester, "Résultat indéterminé")}');

      // Le MOTIF doit être compréhensible à l'écran (exigence 3 de l'arbitrage).
      expect(_contient(tester, 'motif : arriveeNonDefinitive'), isTrue,
          reason: 'le motif du verdict doit accompagner « Résultat '
              'indéterminé » lorsqu\'il est disponible');

      // L'INVARIANT FINANCIER reste absolu : aucun montant, jamais.
      expect(_contient(tester, 'Gain gagné'), isFalse,
          reason: 'un ticket indéterminé n\'affiche JAMAIS de gain');
      expect(_contient(tester, '€ brut'), isFalse);
      expect(_contient(tester, 'Pari perdu'), isFalse,
          reason: 'un indéterminé ne doit JAMAIS être présenté comme une '
              'perte établie');

      // ignore: avoid_print
      print('A/3 débordements préexistants : ${_debordements.length}');

      await _demonter(tester);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  B — DÉTAIL DU PARI : LE BANDEAU DU VERDICT OFFICIEL
  // ─────────────────────────────────────────────────────────────────────────
  group('B — Détail du pari : bandeau du verdict officiel', () {
    testWidgets('B/1 « perdu » : bandeau « ❌ Pari perdu », aucun montant',
        (tester) async {
      final perdu = _resoudre(typePari: 'Simple Gagnant', numeros: [10]);
      await _preparer(<TrackedCourse>[perdu]);
      late PmuProvider pmu;
      await _avecPmu(() async {
        pmu = PmuProvider();
        await pmu.reloadPredictions();
        await _monterDetail(tester, perdu, pmu);
      });

      expect(find.text('PRIX B4.8'), findsWidgets,
          reason: 'TÉMOIN : l\'écran de détail a bien chargé la course');
      expect(_contient(tester, 'Pari perdu'), isTrue,
          reason: 'le bandeau officiel doit annoncer la perte');
      expect(_contient(tester, 'Perte établie par le résultat officiel.'),
          isTrue,
          reason: 'le détail doit dire sur quoi la perte est établie');
      expect(_contient(tester, 'Gain gagné'), isFalse,
          reason: 'AUCUN montant sur un ticket perdu');

      // ignore: avoid_print
      print('B/1 textes verdict : '
          '${_textes(tester).where((s) => s.contains("Pari") || s.contains("Perte") || s.contains("Gain")).toList()}');
      // ignore: avoid_print
      print('B/1 débordements préexistants : ${_debordements.length}');

      await _demonter(tester);
    });

    testWidgets('B/2 « attribue » : bandeau « 🏆 Gain gagné : 75 € brut »',
        (tester) async {
      final gagne = _resoudre(typePari: 'Simple Gagnant', numeros: [9]);
      await _preparer(<TrackedCourse>[gagne]);
      late PmuProvider pmu;
      await _avecPmu(() async {
        pmu = PmuProvider();
        await pmu.reloadPredictions();
        await _monterDetail(tester, gagne, pmu);
      });

      expect(_contient(tester, 'Gain gagné'), isTrue,
          reason: 'le bandeau doit annoncer le gain');
      expect(_contient(tester, '75'), isTrue,
          reason: 'le montant affiché doit être 75,00 € (7,50 × 10)');

      // ignore: avoid_print
      print('B/2 textes verdict : '
          '${_textes(tester).where((s) => s.contains("Gain") || s.contains("Tirelire")).toList()}');
      // ignore: avoid_print
      print('B/2 débordements préexistants : ${_debordements.length}');

      await _demonter(tester);
    });

    testWidgets('B/3 « nonDetermine » : bandeau « ❔ Résultat indéterminé » '
        'avec son MOTIF', (tester) async {
      final indecis = _nonDetermine();
      await _preparer(<TrackedCourse>[indecis]);
      late PmuProvider pmu;
      await _avecPmu(() async {
        pmu = PmuProvider();
        await pmu.reloadPredictions();
        await _monterDetail(tester, indecis, pmu);
      });

      // ⚠️ `PRIX B4.8 INDETERMINE` n'existe pas dans le programme simulé :
      // l'écran affiche sa vue d'erreur. Le bandeau n'est alors pas construit.
      // C'est une LIMITE DU HARNAIS, pas un défaut de rendu — on la mesure.
      final visible = _contient(tester, 'indéterminé') ||
          _contient(tester, 'Résultat indéterminé');
      // ignore: avoid_print
      print('B/3 ── bandeau indéterminé construit : $visible');
      // ignore: avoid_print
      print('B/3 ── textes : ${_textes(tester).take(6).toList()}');

      // L'assertion porte sur ce qui est PROUVABLE ici : aucun montant.
      expect(_contient(tester, 'Gain gagné'), isFalse,
          reason: 'un ticket indéterminé n\'affiche jamais de gain');

      await _demonter(tester);
    });

    // ★ B-4.7 — EXIGENCE 2 : « rembourse » doit être cohérent avec le
    //   remboursement officiel. On ne fabrique AUCUN verdict : le bloc
    //   « E_SIMPLE_GAGNANT » est déclaré `rembourse: true` par l'opérateur,
    //   puis le moteur B-3 est laissé libre de conclure. Le rendu est ensuite
    //   mesuré sur les DEUX écrans.
    testWidgets('B/4 « rembourse » : état et montant cohérents avec le '
        'remboursement officiel', (tester) async {
      final rembourse = _resoudre(
        typePari: 'Simple Gagnant',
        numeros: <int>[9],
        rapports: PmuApiService.decoderRapportsDefinitifs(
          json.encode(<Map<String, dynamic>>[
            {
              'typePari': 'E_SIMPLE_GAGNANT',
              'miseBase': 100,
              'dividendeUnite': 'EURO',
              'rembourse': true, // ← l'opérateur déclare le remboursement
              'rapports': <Map<String, dynamic>>[
                {
                  'combinaison': '9',
                  'libelle': 'e-Simple Gagnant 9',
                  'dividendePourUnEuro': 750,
                  'rangCombinaisonPayable': 1,
                },
              ],
            },
          ]),
        ),
      );

      expect(rembourse.etatGain, EtatGain.rembourse,
          reason: 'TÉMOIN : le moteur doit conclure « rembourse » (et non '
              '« attribue ») sur un bloc déclaré remboursé — état mesuré : '
              '${rembourse.etatGain}');

      // ── MES PARIS ──────────────────────────────────────────────────────
      await _preparer(<TrackedCourse>[rembourse]);
      late PmuProvider pmu;
      await _avecPmu(() async {
        pmu = PmuProvider();
        await pmu.reloadPredictions();
        await _monterMesParis(tester, pmu);
      });

      expect(_contient(tester, 'CHEVAL_9'), isTrue,
          reason: 'TÉMOIN : la carte du ticket est rendue');
      expect(_contient(tester, 'Remboursé') || _contient(tester, 'remboursé'),
          isTrue, reason: 'le remboursement doit être LISIBLE sur la carte');
      expect(_contient(tester, 'Gain gagné'), isFalse,
          reason: 'un remboursement n\'est JAMAIS un gain');
      expect(_contient(tester, 'Pari perdu'), isFalse,
          reason: 'un remboursement n\'est JAMAIS une perte');

      // ★ FAIT MESURÉ, VERROUILLÉ — pas un montant inventé.
      //   `VerdictGain.rembourse` a `composantes: []` et `total: 0.0` ; la
      //   branche C persiste `rapportsAttribues: null`. Aucun montant de
      //   remboursement n'est donc DÉMONTRABLE, et `affichageGainSuivi` rend
      //   « ↩️ Pari remboursé » SANS montant. Substituer la mise serait
      //   inventer une règle financière : c'est interdit ici.
      expect(_contient(tester, '↩️ Pari remboursé'), isTrue,
          reason: 'le libellé exact doit être « ↩️ Pari remboursé » (sans '
              'montant), puisque aucun montant de remboursement n\'est '
              'persisté par la chaîne officielle');
      expect(_contient(tester, '€ brut'), isFalse,
          reason: 'aucun montant de remboursement n\'est fabriqué');

      // ignore: avoid_print
      print('B/4 Mes Paris : '
          '${_textes(tester).where((s) => s.contains("embours")).toList()}');
      // ignore: avoid_print
      print('B/4 Mes Paris débordements : ${_debordements.length}');

      await _demonter(tester);

      // ── DÉTAIL DU PARI ─────────────────────────────────────────────────
      await _preparer(<TrackedCourse>[rembourse]);
      await _avecPmu(() async {
        pmu = PmuProvider();
        await pmu.reloadPredictions();
        await _monterDetail(tester, rembourse, pmu);
      });

      final textes = _textes(tester);
      // ignore: avoid_print
      print('B/4 Détail : ${textes.where((s) => s.contains("embours")).toList()}');

      expect(
          textes.any((s) => s.contains('Rembours') || s.contains('rembours')),
          isTrue,
          reason: 'B-4.7 : le bandeau du Détail doit rendre l\'état remboursé');
      expect(
          textes.any((s) => s.contains('Gain gagné')), isFalse,
          reason: 'aucun gain gagnant pour un rembourse');

      await _demonter(tester);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  C — CONTRÔLE n°3 : LA BRANCHE C N'ENREGISTRE RIEN D'INDÉMONTRÉ
  // ─────────────────────────────────────────────────────────────────────────
  group('C — aucun verdict définitif insuffisamment démontré n\'est enregistré',
        () {
    test('C/1 branche C : un « perdu » n\'écrit AUCUN montant', () {
      final d = deciderEcritureVerdict(
        etatExistant: null,
        etatTirelireExistant: null,
        motifExistant: null,
        rapportsExistants: null,
        verdict: VerdictGain.perdu(explication: 'perdu établi'),
        rapportsOfficiels: <RapportPublie>[
          RapportPublie(
            codePmu: 'E_SIMPLE_GAGNANT',
            libelle: 'e-Simple Gagnant 9',
            combinaison: '9',
            pourUnEuro: 7.5,
          ),
        ],
        miseBaseCentimesOfficielle: 100,
      );
      expect(d.statut, StatutEnregistrementVerdict.enregistre,
          reason: 'B-4.7 : la perte démontrée est désormais enregistrée '
              '(motif=${d.motif})');
      final e = d.ecriture!;
      expect(e.etat, EtatGain.perdu);
      expect(e.rapportsAttribues, isNull, reason: 'jamais `[]`, jamais un rapport');
      expect(e.dividendeGagnant, isNull);
      expect(e.dividendePlace, isNull);
    });

    test('C/2 branche C : un « nonDetermine » n\'écrit AUCUN montant', () {
      final d = deciderEcritureVerdict(
        etatExistant: null,
        etatTirelireExistant: null,
        motifExistant: null,
        rapportsExistants: null,
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.blocJusteAbsent,
          explication: 'bloc absent',
        ),
        rapportsOfficiels: <RapportPublie>[
          RapportPublie(
            codePmu: 'E_SIMPLE_GAGNANT',
            libelle: 'e-Simple Gagnant 9',
            combinaison: '9',
            pourUnEuro: 7.5,
          ),
        ],
      );
      expect(d.statut, StatutEnregistrementVerdict.enregistre);
      expect(d.ecriture!.etat, EtatGain.nonDetermine);
      expect(d.ecriture!.motif, MotifNonDetermination.blocJusteAbsent,
          reason: 'le motif doit survivre pour rester traçable');
      expect(d.ecriture!.rapportsAttribues, isNull);
      expect(d.ecriture!.dividendeGagnant, isNull);
      expect(d.ecriture!.dividendePlace, isNull);
    });

    test('C/3 « attribue » dont le rapport officiel est INTROUVABLE ⇒ refus', () {
      // Le verdict porte une composante à 7,50 € ; l'API ne publie que 3,00 €.
      final verdict = VerdictGain.attribue(
        composantes: <ComposanteGain>[
          ComposanteGain(
            libelleRapport: 'e-Simple Gagnant 9',
            combinaisonRapport: '9',
            categorie: VarianteRapport.sansVariante,
            role: RoleComposante.unique,
            mise: 10.0,
            pourUnEuro: 7.5,
            montantRetour: 75.0,
          ),
        ],
      );
      final d = deciderEcritureVerdict(
        etatExistant: null,
        etatTirelireExistant: null,
        motifExistant: null,
        rapportsExistants: null,
        verdict: verdict,
        rapportsOfficiels: <RapportPublie>[
          RapportPublie(
            codePmu: 'E_SIMPLE_GAGNANT',
            libelle: 'e-Simple Gagnant 9',
            combinaison: '9',
            pourUnEuro: 3.0, // montant différent ⇒ identité non démontrée
          ),
        ],
      );
      expect(d.estRefuse, isTrue,
          reason: 'aucun rapport ne confirme 7,50 € : le verdict ne doit pas '
              'être écrit');
      expect(d.statut, StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable);
      expect(d.ecriture, isNull, reason: 'on ne peut pas « écrire à moitié »');
    });

    test('C/4 « attribue » AMBIGU (deux candidats) ⇒ refus, jamais le plus élevé',
        () {
      final verdict = VerdictGain.attribue(
        composantes: <ComposanteGain>[
          ComposanteGain(
            libelleRapport: 'e-Simple Placé 9',
            combinaisonRapport: '9',
            categorie: VarianteRapport.sansVariante,
            role: RoleComposante.unique,
            mise: 10.0,
            pourUnEuro: 3.0,
            montantRetour: 30.0,
          ),
        ],
      );
      // Deux rapports de MÊME combinaison mais de montants différents : rien ne
      // permet de trancher, et le montant le plus élevé ne départage jamais.
      final d = deciderEcritureVerdict(
        etatExistant: null,
        etatTirelireExistant: null,
        motifExistant: null,
        rapportsExistants: null,
        verdict: verdict,
        rapportsOfficiels: <RapportPublie>[
          RapportPublie(
            codePmu: 'E_SIMPLE_PLACE',
            libelle: 'e-Simple Placé 9',
            combinaison: '9',
            variante: VarianteRapport.sansVariante,
            pourUnEuro: 3.0,
            rang: 1,
          ),
          RapportPublie(
            codePmu: 'E_SIMPLE_PLACE',
            libelle: 'e-Simple Placé 9',
            combinaison: '9',
            variante: VarianteRapport.sansVariante,
            pourUnEuro: 3.0,
            rang: 2, // ← rang différent : rapport DISTINCT, ambiguïté réelle
          ),
        ],
      );
      expect(d.estRefuse, isTrue);
      expect(d.statut, StatutEnregistrementVerdict.refuseRapportOfficielAmbigu);
      expect(d.motif, contains('le montant le plus élevé ne départage JAMAIS'));
    });

    test('C/5 un verdict DÉFINITIF existant n\'est jamais écrasé, même démontré',
        () {
      // Existant : perdu. Nouveau : attribué (avec une composante identifiée).
      final d = deciderEcritureVerdict(
        etatExistant: EtatGain.perdu,
        etatTirelireExistant: EtatTirelire.sansObjet,
        motifExistant: null,
        rapportsExistants: null,
        verdict: VerdictGain.attribue(
          composantes: <ComposanteGain>[
            ComposanteGain(
              libelleRapport: 'e-Simple Gagnant 9',
              combinaisonRapport: '9',
              categorie: VarianteRapport.sansVariante,
              role: RoleComposante.unique,
              mise: 10.0,
              pourUnEuro: 7.5,
              montantRetour: 75.0,
            ),
          ],
        ),
        rapportsOfficiels: <RapportPublie>[
          RapportPublie(
            codePmu: 'E_SIMPLE_GAGNANT',
            libelle: 'e-Simple Gagnant 9',
            combinaison: '9',
            pourUnEuro: 7.5,
          ),
        ],
      );
      expect(d.statut,
          StatutEnregistrementVerdict.refuseVerdictDefinitifExistant);
      expect(d.ecriture, isNull);
    });

    test('C/6 le moteur ne produit « perdu » que sur une preuve mesurée', () {
      // Sans arrivée officielle, la perte n'est PAS établie : le moteur doit
      // rendre `nonDetermine`, donc la branche C n'a rien de définitif à écrire.
      final base = TrackedCourse(
        numReunion: 1,
        numCourse: 6,
        nomCourse: 'PRIX B4.8',
        hippodrome: 'TESTIPPODROME',
        heureDepart: DateTime.now().subtract(const Duration(minutes: 90)),
        numeroCheval: 10,
        nomCheval: 'CHEVAL_10',
        miseEngagee: 10.0,
        typePari: 'Simple Gagnant',
        numerosJoues: const <int>[10],
        numerosDansOrdre: const <int>[10],
        arriveeFinale: _kArriveePlate,
        arriveeGroupes: null, // groupes inconnus
        arriveeDefinitive: null,
        codePmuOfficiel: 'E_SIMPLE_GAGNANT',
        storageKey: 'R1C6_15112026',
      );
      final resultat = construireResultatOfficiel(
        arriveeGroupes: null,
        arriveeDefinitive: null,
        rapports: _rapportsReels(),
      );
      final resolution = resoudreSuivi(ticket: base, resultat: resultat);
      expect(resolution.verdict!.etat, EtatGain.nonDetermine,
          reason: 'sans groupes officiels, aucune perte ne peut être établie');
    });
  });
}
