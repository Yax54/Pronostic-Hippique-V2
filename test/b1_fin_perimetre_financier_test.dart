// ═══════════════════════════════════════════════════════════════════════════
//  BLOC 1 — VALIDATION DU PÉRIMÈTRE FINANCIER (t6f / t6d / t6c / t6e)
//
//  OBJET DE CE FICHIER
//  ─────────────────────────────────────────────────────────────────────────
//  Tester les TROIS modules réels (Best Bet, Backtesting, Martingale) ET le
//  simulateur commun, sur des réponses PMU au FORMAT AUTHENTIQUE, en couvrant
//  ce que le mandat exige explicitement :
//
//    • tous les types de paris pris en charge et leurs tailles de combinaison ;
//    • gains, pertes, remboursements INTÉGRAUX, résultats mixtes ;
//    • résultats INDÉTERMINÉS (ni gain ni perte) ;
//    • un remboursement ne doit JAMAIS faire progresser une Martingale comme
//      une perte ;
//    • exactitude du capital, du résultat net, des séries et du ROI ;
//    • un indéterminé ne doit PAS relier artificiellement deux séries ;
//    • la couverture financière est affichée QUELLE QUE SOIT sa valeur ;
//    • les estimations Best Bet restent DISTINCTES des gains officiels, et la
//      suppression des cotes fictives ne perturbe pas le classement ;
//    • ABSENCE D'EFFETS DE BORD sur Mes Paris, notifications, décisions
//      financières réelles et apprentissage IA ;
//    • reprise après indisponibilité temporaire, actualisation des résultats
//      provisoires, récupération ultérieure des rapports manquants.
//
//  CE QUE CE FICHIER NE FAIT PAS
//  ─────────────────────────────────────────────────────────────────────────
//  Il ne modifie AUCUNE formule, AUCUN poids, AUCUN seuil, AUCUN mécanisme
//  d'apprentissage. Il mesure le comportement du code tel qu'il est.
//
//  ORIGINE DES DONNÉES
//  ─────────────────────────────────────────────────────────────────────────
//  Les arrivées, numéros et dividendes proviennent des captures authentiques
//  du dépôt (`test/fixtures/recherche_pmu/`). LÀ OÙ UNE FIXTURE EST
//  RECONSTITUÉE, c'est écrit en clair dans le test concerné — voir
//  `_blocRembourse()` et les tests C3-* du fichier
//  `b1_fin_persistance_officielle_test.dart`.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/chaine_financiere_officielle.dart';
import 'package:pronostic_hippique/services/estimation_best_bet.dart';
import 'package:pronostic_hippique/services/finance_simulateur_officiel.dart';
import 'package:pronostic_hippique/services/resultat_officiel_repository.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ─────────────────────── Données AUTHENTIQUES (mesurées) ───────────────────

/// Arrivée officielle de R1C1 (capture authentique
/// `test/fixtures/recherche_pmu/multi/prog_15112026.json`) :
/// `ordreArrivee = [[4],[6],[7],[9],[1],[3],[5]]`, `nombreDeclaresPartants = 9`.
const List<int> kArrivee = <int>[4, 6, 7, 9, 1, 3, 5];

/// Partants déclarés `ARRETE` (capture authentique `/participants`).
const List<int> kArretes = <int>[2, 8];

/// Dividende Gagnant authentique : 420 centimes pour 1 €, soit 4,20 €.
const int kCentimesGagnant = 420;
const double kDividendeGagnant = 4.20;

/// Dividende Placé authentique de la capture : 210 centimes, soit 2,10 €.
const int kCentimesPlace = 210;
const double kDividendePlace = 2.10;

/// Numéro gagnant retenu pour le bloc Gagnant.
///
/// ★ HONNÊTETÉ SUR LA FIXTURE — À LIRE AVANT TOUTE CONCLUSION :
///   la capture authentique `rapports/R1C1.json` publie `combinaison: "8"`
///   alors que la MÊME capture dit que le n°8 est `ARRETE`. Ces deux faits ne
///   peuvent pas être vrais simultanément : la fixture est incohérente.
///   On ne « corrige » donc pas le dividende (4,20 € reste le vrai chiffre
///   publié) et on ne prétend pas que le gagnant est 8 : on construit le bloc
///   Gagnant sur le VRAI vainqueur de l'arrivée officielle, le n°4, en
///   conservant le dividende réel. Cette substitution est dite, pas cachée.
///   → Les tests marqués « FIXTURE RECONSTITUÉE » héritent de cette réserve.
const int kNumeroGagnant = 4;

/// Course utilisée : R1C1, 15/11/2026 (date de la capture authentique).
final DateTime kDate = DateTime(2026, 11, 15);
int get _numR => 1;
int get _numC => 1;

// ─────────────────────────── Faux serveur PMU ──────────────────────────────

/// Compteur d'appels réseau par type de chemin. Il permet de PROUVER qu'une
/// seconde demande sur la même course ne repart pas sur le réseau.
class _Compteur {
  int rapports = 0;
  int participants = 0;
  int courses = 0;
  int autres = 0;
  int get total => rapports + participants + courses + autres;
}

Map<String, dynamic> _ligneGagnant({int combinaison = kNumeroGagnant}) =>
    <String, dynamic>{
      'combinaison': '$combinaison',
      'libelle': 'e-Simple Gagnant',
      'dividendePourUnEuro': kCentimesGagnant,
      'rangCombinaisonPayable': 1,
    };

Map<String, dynamic> _lignePlace(int numero, int rang) => <String, dynamic>{
      'combinaison': '$numero',
      'libelle': 'e-Simple Placé',
      'dividendePourUnEuro': kCentimesPlace,
      'rangCombinaisonPayable': rang,
    };

Map<String, dynamic> _bloc(
  String type,
  List<Map<String, dynamic>> lignes, {
  bool rembourse = false,
  int miseBase = 100,
}) =>
    <String, dynamic>{
      'typePari': type,
      if (rembourse) 'rembourse': true,
      'miseBase': miseBase,
      'rapports': lignes,
    };

/// Corps de `/rapports-definitifs` pour un type Gagnant PERDANT.
///
/// ★ FIXTURE RECONSTITUÉE — DÉCLARÉE COMME TELLE :
///   le bloc Gagnant porte ici le numéro 9, qui est bien 4ᵉ de l'arrivée
///   officielle. Le n°4 joué n'y figure donc pas. Le COUPLE (bloc + arrivée)
///   reste cohérent : le bloc Gagnant d'une course ne contient par nature
///   qu'UNE ligne, le vainqueur.
///
///   ⚠️ La capture authentique `rapports/R1C1.json` publie, elle,
///   `combinaison: "8"` alors que la même capture déclare 8 `ARRETE`. Ce
///   couple-là est incohérent et ne peut servir de base à un test de perte :
///   le moteur refuse d'ailleurs de conclure dessus (`nonDeterminee`), ce qui
///   est le comportement CORRECT. On construit donc un rapport cohérent avec
///   l'arrivée réelle, et on le DIT.
String _corpsRapportsPerdant() => json.encode(<dynamic>[
      _bloc('E_SIMPLE_GAGNANT', <Map<String, dynamic>>[
        _ligneGagnant(combinaison: 9),
      ]),
      _bloc('E_SIMPLE_PLACE', <Map<String, dynamic>>[
        for (var i = 0; i < 3; i++) _lignePlace(kArrivee[i], i + 1),
      ]),
    ]);

/// Corps de `/rapports-definitifs` pour un type Gagnant GAGNANT (n°4).
String _corpsRapportsGagnant() => json.encode(<dynamic>[
      _bloc('E_SIMPLE_GAGNANT', <Map<String, dynamic>>[_ligneGagnant()]),
      _bloc('E_SIMPLE_PLACE', <Map<String, dynamic>>[
        for (var i = 0; i < 3; i++) _lignePlace(kArrivee[i], i + 1),
      ]),
    ]);

/// Corps de `/rapports-definitifs` où le bloc Gagnant est REMBOURSÉ.
///
/// ★ FIXTURE RECONSTITUÉE — DÉCLARÉE COMME TELLE :
///   la clé `rembourse` est authentique (elle est lue par
///   `PmuApiService.decoderRapportsDefinitifs` sur le BLOC, mesuré), mais
///   AUCUNE capture du dépôt ne montre un bloc `E_SIMPLE_GAGNANT` remboursé
///   pour R1C1. Ce corps est donc fabriqué pour exercer la branche
///   `EtatGain.rembourse`, en conservant scrupuleusement le format observé
///   (clé au niveau du bloc, rapport sans dividende). Il ne prétend pas
///   reproduire une course réelle.
String _corpsRapportsRembourse() => json.encode(<dynamic>[
      _bloc(
        'E_SIMPLE_GAGNANT',
        <Map<String, dynamic>>[
          <String, dynamic>{
            'combinaison': '$kNumeroGagnant',
            'libelle': 'e-Simple Gagnant',
            // Aucun dividende : un remboursement ne dépend d'aucun rapport.
          },
        ],
        rembourse: true,
      ),
    ]);

/// Corps de `/participants` au format AUTHENTIQUE (4 clés racine, 7 arrivants
/// classés + 2 `ARRETE`).
String _corpsParticipants() => json.encode(<String, dynamic>{
      'participants': <Map<String, dynamic>>[
        for (var i = 0; i < kArrivee.length; i++)
          {
            'numPmu': kArrivee[i],
            'statut': 'PARTANT',
            'ordreArrivee': i + 1,
          },
        for (final n in kArretes)
          {
            'numPmu': n,
            'statut': 'PARTANT',
            'incident': 'ARRETE',
          },
      ],
      'ecuries': <dynamic>[],
      'spriteCasaques': <String, dynamic>{},
      'cached': false,
    });

/// Corps de l'endpoint PAR COURSE — le seul qui PORTE le drapeau définitif.
/// [definitif] = `true` / `false` / `null` (clé absente).
String _corpsCourse({required bool? definitif}) {
  final corps = <String, dynamic>{
    'numReunion': _numR,
    'numOrdre': _numC,
    'nombreDeclaresPartants': 9,
    'ordreArrivee': [
      for (final n in kArrivee) <int>[n],
    ],
  };
  if (definitif != null) {
    corps['arriveeDefinitive'] = definitif;
    corps['isArriveeDefinitive'] = definitif;
    corps['statut'] = definitif ? 'ARRIVEE_DEFINITIVE_COMPLETE' : 'FIN_COURSE';
  }
  return json.encode(corps);
}

/// Faux serveur PMU reproduisant les TROIS endpoints réellement appelés.
///
/// [servirRapports] = `false` → le PMU ne publie AUCUN rapport (cas
/// « résultats provisoires » : la source répond mais ne sait pas encore).
/// [courseInjoignable] → HTTP 503 sur l'endpoint par course seulement.
MockClient _client(
  _Compteur c, {
  String Function()? corpsRapports,
  bool servirRapports = true,
  bool? definitif = true,
  bool courseInjoignable = false,
}) =>
    MockClient((http.Request r) async {
      final String p = r.url.path;
      const Map<String, String> entetes = {'content-type': 'application/json'};

      if (p.contains('rapports-definitifs')) {
        c.rapports++;
        if (!servirRapports) {
          // Source disponible, mais aucun rapport encore publié.
          return http.Response('[]', 200, headers: entetes);
        }
        final corps = (corpsRapports ?? _corpsRapportsPerdant)();
        return http.Response(corps, 200, headers: entetes);
      }
      if (p.contains('participants')) {
        c.participants++;
        return http.Response(_corpsParticipants(), 200, headers: entetes);
      }
      if (RegExp(r'/R\d+/C\d+$').hasMatch(p)) {
        c.courses++;
        if (courseInjoignable) {
          return http.Response('indisponible', 503, headers: entetes);
        }
        return http.Response(_corpsCourse(definitif: definitif), 200,
            headers: entetes);
      }
      c.autres++;
      return http.Response('{}', 200, headers: entetes);
    });

// ──────────────────────────────── Outils ───────────────────────────────────

String get _courseKey => 'R${_numR}C${_numC}_15112026';

IdentiteCoursePmu get _identite =>
    IdentiteCoursePmu(numReunion: _numR, numCourse: _numC, date: kDate);

Future<void> _vierge() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  ZoneTurfService.viderCachePourResetComplet();
  final repo = ResultatOfficielRepository.instance;
  repo.oublierChargementPourTest();
  await repo.viderPourTest();
  repo.oublierChargementPourTest();
  await repo.charger();
}

/// Exécute [corps] sous un faux serveur PMU, et rend le compteur.
Future<_Compteur> _sousServeur(
  Future<void> Function() corps, {
  String Function()? corpsRapports,
  bool servirRapports = true,
  bool? definitif = true,
  bool courseInjoignable = false,
}) async {
  final c = _Compteur();
  await http.runWithClient(
    corps,
    () => _client(
      c,
      corpsRapports: corpsRapports,
      servirRapports: servirRapports,
      definitif: definitif,
      courseInjoignable: courseInjoignable,
    ),
  );
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  1. SIMULATEUR COMMUN — les QUATRE sorts, sur données officielles
  // ═══════════════════════════════════════════════════════════════════════
  group('1. Simulateur officiel — quatre sorts', () {
    test('1.1 GAIN : le n°4 gagne, dividende réel 4,20 €/€, mise 10 €',
        () async {
      await _vierge();
      late ResultatFinancierSimule sim;
      final c = await _sousServeur(() async {
        sim = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsGagnant);

      expect(sim.sort, SortPariSimule.gagne,
          reason: 'le n°4 est le vainqueur officiel et son rapport est publié');
      // Gain BRUT = mise × dividende = 10 × 4,20 = 42,00 €.
      expect(sim.gain, closeTo(10.0 * kDividendeGagnant, 0.001));
      expect(sim.remboursement, closeTo(0.0, 0.001),
          reason: 'un gain n\'est pas un remboursement');
      // Net = 42,00 − 10,00 = 32,00 €.
      expect(sim.resultatNet, closeTo(32.0, 0.001));
      expect(c.total, greaterThan(0),
          reason: 'le test doit réellement avoir exercé le réseau');
      expect(sim.servieDepuisStockage, isFalse,
          reason: 'première demande : la source est interrogée');
    });

    test('1.2 PERTE : le n°4 joué, le rapport paie le n°6', () async {
      await _vierge();
      late ResultatFinancierSimule sim;
      await _sousServeur(() async {
        sim = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsPerdant);

      expect(sim.sort, SortPariSimule.perdu,
          reason: 'la perte est DÉMONTRÉE : le rapport officiel paie un autre '
              'numéro et l\'arrivée est définitive');
      expect(sim.gain, closeTo(0.0, 0.001));
      expect(sim.resultatNet, closeTo(-10.0, 0.001));
      expect(sim.estRembourse, isFalse,
          reason: 'une perte n\'est jamais un remboursement');
    });

    test('1.3 REMBOURSEMENT INTÉGRAL : mise rendue, ni gain ni perte',
        () async {
      await _vierge();
      late ResultatFinancierSimule sim;
      await _sousServeur(() async {
        sim = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsRembourse);

      // ★ C'EST LE CŒUR DE LA CORRECTION : avant elle, ce cas tombait dans
      //   « perdu » et faisait doubler la mise en Martingale.
      expect(sim.sort, SortPariSimule.rembourse,
          reason: 'EtatGain.rembourse doit produire SortPariSimule.rembourse, '
              'PAS perdu');
      expect(sim.gain, closeTo(0.0, 0.001),
          reason: 'un remboursement n\'est pas un gain');
      expect(sim.remboursement, closeTo(10.0, 0.001),
          reason: 'la mise ENGAGÉE est rendue');
      expect(sim.resultatNet, closeTo(0.0, 0.001),
          reason: 'net = remboursement − mise = 0 : le joueur n\'a rien perdu');
      expect(sim.estDetermine, isTrue,
          reason: 'un remboursement est un sort ÉTABLI, pas une ignorance');
      expect(sim.estRembourse, isTrue);
    });

    test('1.4 INDÉTERMINÉ : aucun rapport publié (source muette)', () async {
      await _vierge();
      late ResultatFinancierSimule sim;
      await _sousServeur(() async {
        sim = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, servirRapports: false);

      expect(sim.sort, SortPariSimule.nonDeterminee);
      expect(sim.gain, isNull,
          reason: 'null ≠ 0 : un gain inconnu ne vaut pas zéro');
      expect(sim.resultatNet, isNull);
      expect(sim.motifIndetermination, isNotNull,
          reason: 'un indéterminé doit toujours dire POURQUOI');
      expect(sim.estDetermine, isFalse);
    });

    test('1.5 INDÉTERMINÉ : arrivée provisoire — aucune perte prononcée',
        () async {
      await _vierge();
      late ResultatFinancierSimule sim;
      await _sousServeur(() async {
        sim = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[6],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsPerdant, definitif: false);

      expect(sim.sort, SortPariSimule.nonDeterminee,
          reason: 'arrivée non définitive : la perte ne peut pas être établie');
      expect(sim.gain, isNull);
      // Le n°6 est pourtant le numéro payé par le rapport : sans drapeau
      // définitif à `true`, le moteur refuse de conclure. C'est voulu.
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  2. AGRÉGAT — exactitude du capital, du net, des séries et du ROI
  // ═══════════════════════════════════════════════════════════════════════
  group('2. Bilan financier — exactitude des agrégats', () {
    test('2.1 gain + perte + remboursement + indéterminé : comptes exacts', () {
      final paris = <ResultatFinancierSimule>[
        // Gagné : mise 10, gain brut 42, net +32.
        const ResultatFinancierSimule(
          courseKey: 'R1C1_15112026',
          typePari: 'Simple Gagnant',
          numerosJoues: <int>[4],
          mise: 10.0,
          sort: SortPariSimule.gagne,
          gain: 42.0,
          remboursement: 0.0,
          resultatNet: 32.0,
        ),
        // Perdu : mise 10, net −10.
        const ResultatFinancierSimule(
          courseKey: 'R1C2_15112026',
          typePari: 'Simple Gagnant',
          numerosJoues: <int>[4],
          mise: 10.0,
          sort: SortPariSimule.perdu,
          gain: 0.0,
          remboursement: 0.0,
          resultatNet: -10.0,
        ),
        // Remboursé : mise 10 rendue, net 0.
        const ResultatFinancierSimule(
          courseKey: 'R1C3_15112026',
          typePari: 'Simple Gagnant',
          numerosJoues: <int>[4],
          mise: 10.0,
          sort: SortPariSimule.rembourse,
          gain: 0.0,
          remboursement: 10.0,
          resultatNet: 0.0,
        ),
        // Indéterminé : mise 10, AUCUN montant.
        const ResultatFinancierSimule(
          courseKey: 'R1C4_15112026',
          typePari: 'Simple Gagnant',
          numerosJoues: <int>[4],
          mise: 10.0,
          sort: SortPariSimule.nonDeterminee,
          motifIndetermination: 'rapport absent',
        ),
      ];

      final b = BilanFinancierSimule.depuis(paris);

      expect(b.nbParis, 4);
      expect(b.nbGagnes, 1);
      expect(b.nbPerdus, 1);
      expect(b.nbRembourses, 1,
          reason: 'le remboursement a son propre compteur');
      expect(b.nbNonDetermines, 1);
      expect(b.nbDetermines, 3,
          reason: 'gagné + perdu + remboursé sont tous ÉTABLIS');

      // Mises engagées = les 3 paris établis (10 + 10 + 10). La mise de
      // l'indéterminé va dans un compteur SÉPARÉ.
      expect(b.misesEngagees, closeTo(30.0, 0.001));
      expect(b.misesIndeterminees, closeTo(10.0, 0.001));
      expect(b.gainsBruts, closeTo(42.0, 0.001));
      expect(b.remboursements, closeTo(10.0, 0.001),
          reason: 'remboursement distinct du gain, jamais fondu dedans');
      // Net = +32 − 10 + 0 = +22.
      expect(b.resultatNet, closeTo(22.0, 0.001));

      // Couverture = 3 établis / 4 = 75 %.
      expect(b.couvertureOfficielle, closeTo(75.0, 0.001));
      expect(b.couvertureInsuffisante, isFalse);

      // ROI = 22 / 30 × 100 = 73,33… %.
      expect(b.roi, closeTo(73.333333, 0.01));
    });

    test('2.2 ROI et couverture : `null` quand rien n\'est établi', () {
      final b = BilanFinancierSimule.depuis(<ResultatFinancierSimule>[
        const ResultatFinancierSimule(
          courseKey: 'R1C1_15112026',
          typePari: 'Simple Gagnant',
          numerosJoues: <int>[4],
          mise: 10.0,
          sort: SortPariSimule.nonDeterminee,
          motifIndetermination: 'rapport absent',
        ),
      ]);
      expect(b.nbDetermines, 0);
      expect(b.misesEngagees, closeTo(0.0, 0.001),
          reason: 'aucune mise n\'est engagée « pour de vrai »');
      expect(b.roi, isNull, reason: 'un ROI inconnu n\'est pas un ROI nul');
      expect(b.couvertureOfficielle, closeTo(0.0, 0.001));
      expect(b.couvertureInsuffisante, isTrue);
    });

    test('2.3 couverture affichée QUELLE QUE SOIT sa valeur', () {
      // 1 établi sur 4 → 25 %, et le drapeau d'insuffisance doit être levé.
      final b = BilanFinancierSimule.depuis(<ResultatFinancierSimule>[
        const ResultatFinancierSimule(
          courseKey: 'R1C1_15112026',
          typePari: 'Simple Gagnant',
          numerosJoues: <int>[4],
          mise: 10.0,
          sort: SortPariSimule.perdu,
          gain: 0.0,
          remboursement: 0.0,
          resultatNet: -10.0,
        ),
        for (var i = 2; i <= 4; i++)
          ResultatFinancierSimule(
            courseKey: 'R1C${i}_15112026',
            typePari: 'Simple Gagnant',
            numerosJoues: const <int>[4],
            mise: 10.0,
            sort: SortPariSimule.nonDeterminee,
            motifIndetermination: 'rapport absent',
          ),
      ]);
      expect(b.couvertureOfficielle, closeTo(25.0, 0.001));
      expect(b.couvertureInsuffisante, isTrue);
      // Le ROI est calculé, mais il porte sur une base minuscule : c'est la
      // couverture qui doit l'annoncer, pas le ROI qui doit être masqué.
      expect(b.roi, closeTo(-100.0, 0.001));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  3. TYPES DE PARIS ET TAILLES DE COMBINAISON
  // ═══════════════════════════════════════════════════════════════════════
  group('3. Types de paris pris en charge', () {
    test('3.1 tailles de combinaison alignées sur le moteur officiel', () {
      expect(FinanceSimulateurOfficiel.nbNumerosPourType('Simple Gagnant'), 1);
      expect(FinanceSimulateurOfficiel.nbNumerosPourType('Simple Placé'), 1);
      expect(FinanceSimulateurOfficiel.nbNumerosPourType('Couplé Gagnant'), 2);
      expect(FinanceSimulateurOfficiel.nbNumerosPourType('Couplé Placé'), 2);
      expect(FinanceSimulateurOfficiel.nbNumerosPourType('Tiercé'), 3);
      expect(FinanceSimulateurOfficiel.nbNumerosPourType('Quarté+'), 4);
      expect(FinanceSimulateurOfficiel.nbNumerosPourType('Quinté+'), 5);
      // Gagnant+Placé est un ticket à DEUX composantes sur un seul numéro.
      expect(FinanceSimulateurOfficiel.nbNumerosPourType('Gagnant+Placé'), 1);
    });

    test('3.2 types non reconnus : indéterminé, jamais deviné', () async {
      await _vierge();
      final sim = await FinanceSimulateurOfficiel.simulerPari(
        courseKey: _courseKey,
        typePari: 'Pari inventé',
        numerosJoues: const <int>[4],
        mise: 10.0,
        autoriserReseau: false,
      );
      expect(sim.sort, SortPariSimule.nonDeterminee);
      expect(sim.gain, isNull);
      expect(sim.motifIndetermination, isNotNull);
    });

    test('3.3 mise nulle ou négative : refus explicite, pas un gain nul',
        () async {
      await _vierge();
      for (final mise in <double>[0.0, -5.0]) {
        final sim = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[4],
          mise: mise,
          autoriserReseau: false,
        );
        expect(sim.sort, SortPariSimule.nonDeterminee);
        expect(sim.gain, isNull);
        expect(sim.resultatNet, isNull);
      }
    });

    test('3.4 aucun numéro joué : refus explicite', () async {
      await _vierge();
      final sim = await FinanceSimulateurOfficiel.simulerPari(
        courseKey: _courseKey,
        typePari: 'Simple Gagnant',
        numerosJoues: const <int>[],
        mise: 10.0,
        autoriserReseau: false,
      );
      expect(sim.sort, SortPariSimule.nonDeterminee);
      expect(sim.motifIndetermination, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  4. MARTINGALE — un remboursement ne fait PAS progresser la série
  // ═══════════════════════════════════════════════════════════════════════
  group('4. Martingale — remboursement vs perte', () {
    test('4.1 un remboursement n\'aggrave NI la série NI la mise', () {
      // On reproduit ICI la règle de progression de `_lancerMartingale` sur
      // des RésultatsFinanciersSimules, pour PROUVER l'arithmétique sans
      // dépendre du widget. Toute divergence entre cette règle et le widget
      // serait un défaut : les deux doivent donner le même résultat, et le
      // test 4.3 vérifie la cohérence du code source du widget.
      double mise = 10.0;
      int seriePerte = 0;
      int doublements = 0;
      double capital = 0.0;
      int nbRembourses = 0;

      final paris = <ResultatFinancierSimule>[
        // Une perte : la mise double.
        const ResultatFinancierSimule(
          courseKey: 'R1C1_15112026',
          typePari: 'Simple Gagnant',
          numerosJoues: <int>[4],
          mise: 10.0,
          sort: SortPariSimule.perdu,
          gain: 0.0,
          remboursement: 0.0,
          resultatNet: -10.0,
        ),
        // Un remboursement : la mise NE double PAS.
        const ResultatFinancierSimule(
          courseKey: 'R1C2_15112026',
          typePari: 'Simple Gagnant',
          numerosJoues: <int>[4],
          mise: 20.0,
          sort: SortPariSimule.rembourse,
          gain: 0.0,
          remboursement: 20.0,
          resultatNet: 0.0,
        ),
      ];

      for (final sim in paris) {
        capital += sim.resultatNet ?? 0.0;
        switch (sim.sort) {
          case SortPariSimule.gagne:
            seriePerte = 0;
            doublements = 0;
            mise = 10.0;
          case SortPariSimule.perdu:
            seriePerte++;
            doublements++;
            mise = mise * 2;
          case SortPariSimule.rembourse:
            nbRembourses++;
          case SortPariSimule.nonDeterminee:
            break;
        }
      }

      expect(nbRembourses, 1);
      // Après une perte (10 → 20), le remboursement laisse la mise à 20.
      // Si le remboursement avait été traité comme une perte, elle serait
      // à 40 : c'est exactement le défaut corrigé.
      expect(mise, closeTo(20.0, 0.001),
          reason: 'un remboursement ne doit PAS doubler la mise');
      expect(seriePerte, 1,
          reason: 'seule la vraie perte compte dans la série');
      expect(doublements, 1);
      // Capital : −10 (perte) + 0 (remboursement) = −10.
      expect(capital, closeTo(-10.0, 0.001),
          reason: 'la mise remboursée n\'est pas une perte de capital');
    });

    test('4.2 un remboursement isolé laisse la mise de base', () {
      double mise = 10.0;
      int seriePerte = 0;
      final sim = const ResultatFinancierSimule(
        courseKey: 'R1C1_15112026',
        typePari: 'Simple Gagnant',
        numerosJoues: <int>[4],
        mise: 10.0,
        sort: SortPariSimule.rembourse,
        gain: 0.0,
        remboursement: 10.0,
        resultatNet: 0.0,
      );
      switch (sim.sort) {
        case SortPariSimule.gagne:
          mise = 10.0;
        case SortPariSimule.perdu:
          seriePerte++;
          mise = mise * 2;
        case SortPariSimule.rembourse:
          break; // neutralité totale
        case SortPariSimule.nonDeterminee:
          break;
      }
      expect(mise, closeTo(10.0, 0.001));
      expect(seriePerte, 0);
    });

    test('4.3 le code de la Martingale traite EXPLICITEMENT les quatre sorts',
        () async {
      // Garde structurelle : on lit la source pour s'assurer qu'aucun sort
      // ne retombe dans une branche `else` implicite.
      final src = await _lireSource('lib/widgets/ia/ia_tab_backtesting.dart');
      expect(src.contains('case SortPariSimule.rembourse:'), isTrue,
          reason: 'la Martingale DOIT avoir une branche dédiée au '
              'remboursement, sinon il retombe dans « perdu »');
      expect(src.contains('case SortPariSimule.nonDeterminee:'), isTrue);
      expect(src.contains('case SortPariSimule.gagne:'), isTrue);
      expect(src.contains('case SortPariSimule.perdu:'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  5. BACKTESTING — un indéterminé ne relie pas deux séries
  // ═══════════════════════════════════════════════════════════════════════
  group('5. Backtesting — séries, remboursement, indéterminés', () {
    test('5.1 séries calculées dans le code, indéterminé neutre', () async {
      // On reproduit l'algorithme EXACT de `lancer()` sur quatre résultats
      // et on vérifie que l'indéterminé ne relie pas deux séries.
      int serieGagnante = 0, maxGagnante = 0;
      int seriePerdante = 0, maxPerdante = 0;
      int nbGagnes = 0, nbPerdus = 0, nbRembourses = 0, nbNonDet = 0;

      final paris = <ResultatFinancierSimule>[
        _gain('R1C1', 10.0),
        _gain('R1C2', 10.0),
        _gain('R1C3', 10.0),
        // ← indéterminé : ne doit RIEN faire aux séries
        const ResultatFinancierSimule(
          courseKey: 'R1C4',
          typePari: 'Simple Gagnant',
          numerosJoues: <int>[4],
          mise: 10.0,
          sort: SortPariSimule.nonDeterminee,
          motifIndetermination: 'rapport absent',
        ),
        _gain('R1C5', 10.0),
        _gain('R1C6', 10.0),
      ];

      for (final sim in paris) {
        final gagne = sim.sort == SortPariSimule.gagne;
        final rembourse = sim.sort == SortPariSimule.rembourse;
        if (sim.estDetermine) {
          if (gagne) {
            nbGagnes++;
            serieGagnante++;
            seriePerdante = 0;
            if (serieGagnante > maxGagnante) maxGagnante = serieGagnante;
          } else if (rembourse) {
            nbRembourses++;
            // séries INCHANGÉES
          } else {
            nbPerdus++;
            seriePerdante++;
            serieGagnante = 0;
            if (seriePerdante > maxPerdante) maxPerdante = seriePerdante;
          }
        } else {
          nbNonDet++;
          // séries INCHANGÉES : c'est ce qui interdit de RELIER deux séries
        }
      }

      expect(nbGagnes, 5);
      expect(nbNonDet, 1);
      // ★ Le point capital : la meilleure série vaut 3, PAS 5. Si
      //   l'indéterminé avait été ignoré comme un simple « trou » sans
      //   casser la série, on aurait annoncé 5 gains consécutifs — un
      //   chiffre faux, puisque la 4ᵉ course n'a pas de résultat.
      expect(maxGagnante, 3,
          reason: 'un indéterminé ne doit pas relier deux séries de gains');
    });

    test('5.2 un remboursement ne brise pas une série gagnante', () {
      int serieGagnante = 0, maxGagnante = 0;
      final paris = <ResultatFinancierSimule>[
        _gain('R1C1', 10.0),
        _gain('R1C2', 10.0),
        const ResultatFinancierSimule(
          courseKey: 'R1C3',
          typePari: 'Simple Gagnant',
          numerosJoues: <int>[4],
          mise: 10.0,
          sort: SortPariSimule.rembourse,
          gain: 0.0,
          remboursement: 10.0,
          resultatNet: 0.0,
        ),
        _gain('R1C4', 10.0),
      ];
      for (final sim in paris) {
        if (sim.sort == SortPariSimule.gagne) {
          serieGagnante++;
          if (serieGagnante > maxGagnante) maxGagnante = serieGagnante;
        }
        // Un remboursement n'entre dans AUCUNE des deux branches.
      }
      expect(maxGagnante, 3,
          reason: 'le remboursement ne coupe ni n\'allonge la série : '
              '2 gains + 1 remboursement + 1 gain = série de 3');
    });

    test('5.3 agrégats StatistiqueTypePari : remboursement hors séries', () {
      // Vérifie `ajouterPariRembourse` : ni gain, ni perte, ni série.
      final st = _FauxStat();
      st.ajouterPari(gagne: true, gain: 32.0, mise: 10.0);
      st.ajouterPariRembourse(remboursement: 10.0, mise: 10.0);
      expect(st.nbTotal, 2);
      expect(st.nbGagnes, 1);
      expect(st.nbRembourses, 1);
      expect(st.maxSerie, 0,
          reason: 'un remboursement ne crée aucune série perdante');
      expect(st.gainNet, closeTo(32.0, 0.001));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  6. BEST BET — estimations distinctes des gains officiels
  // ═══════════════════════════════════════════════════════════════════════
  group('6. Best Bet — estimations honnêtes', () {
    test('6.1 Simple Gagnant + cote publiée : estimation étiquetée', () {
      final e = EstimationBestBet.avantCourse(
        typePari: 'Simple Gagnant',
        mise: 10.0,
        coteGagnant: 4.2,
      );
      expect(e.nature, NatureMontantBestBet.estimationAvantCourse);
      expect(e.estUneEstimation, isTrue);
      expect(e.montant, closeTo(42.0, 0.001));
      expect(e.coteUtilisee, closeTo(4.2, 0.001));
      expect(e.mention, contains('Estimation avant course'));
      expect(e.mention, contains('non garantie'));
    });

    test('6.2 cote absente (sentinelle 99) : AUCUN montant, pas de 2.5', () {
      final e = EstimationBestBet.avantCourse(
        typePari: 'Simple Gagnant',
        mise: 10.0,
        coteGagnant: 99.0,
      );
      expect(e.nature, NatureMontantBestBet.nonEstimable);
      expect(e.montant, isNull,
          reason: 'avant la correction, le code substituait 2.5 et affichait '
              'un « gain estimé » de 25 €');
      expect(e.coteUtilisee, isNull);
    });

    test('6.3 AUCUN type autre que Simple Gagnant n\'a d\'estimation', () {
      // C'est la règle métier centrale : une cote Gagnant n'est pas un
      // dividende de Couplé, Tiercé, Quarté+ ou Quinté+.
      for (final t in <String>[
        'Couplé Gagnant',
        'Couplé Placé',
        'Couplé Ordre',
        'Couplé Désordre',
        'Tiercé',
        'Tiercé Ordre',
        'Tiercé Désordre',
        'Quarté+',
        'Quinté+',
        'Simple Placé',
        'Gagnant+Placé',
        'À surveiller',
      ]) {
        expect(EstimationBestBet.coteUtilisablePour(t), isFalse,
            reason: '« $t » ne doit JAMAIS utiliser une cote Gagnant');
        final e = EstimationBestBet.avantCourse(
          typePari: t,
          mise: 10.0,
          coteGagnant: 4.2, // une cote pourtant bien publiée
        );
        expect(e.montant, isNull,
            reason: '« $t » ne doit produire aucun montant');
        expect(e.mention.isNotEmpty, isTrue,
            reason: '« $t » doit expliquer POURQUOI il n\'y a pas de montant');
      }
    });

    test('6.4 mise nulle : aucune estimation', () {
      final e = EstimationBestBet.avantCourse(
        typePari: 'Simple Gagnant',
        mise: 0.0,
        coteGagnant: 4.2,
      );
      expect(e.aUnMontant, isFalse);
    });

    test('6.5 le classement des opportunités n\'utilise AUCUNE cote', () async {
      // Garde structurelle : `composite` doit rester adossé au score IA, et
      // non à une cote inventée. On vérifie que la ligne historique de
      // fabrication de cote a bien disparu du calcul de classement.
      final src = await _lireSource('lib/screens/best_bet_screen.dart');
      expect(
          src.contains('(2.0 + (100.0 - opp.scoreConfiance) / 20.0)'), isFalse,
          reason: 'la fabrication d\'une cote depuis le score IA doit avoir '
              'disparu : elle n\'était reliée à aucun rapport PMU');
      expect(src.contains('? c : 2.5'), isFalse,
          reason: 'le repli `2.5` sur une cote absente doit avoir disparu');
      expect(src.contains('composite = scoreConf * 0.65 + scoreGainRaw * 0.35'),
          isTrue,
          reason: 'la formule de classement est PROTÉGÉE : elle ne doit pas '
              'avoir été modifiée par la correction financière');
    });

    test('6.6 estimation et gain officiel sont des natures DISTINCTES', () {
      // On construit une estimation réelle, puis on vérifie que sa nature
      // n'est pas celle d'un gain officiel. Le type `officielApresCourse`
      // n'est produit QUE par le simulateur, après la course : aucun appel
      // ne doit permettre à une estimation de s'en réclamer.
      final estimation = EstimationBestBet.avantCourse(
        typePari: 'Simple Gagnant',
        mise: 10.0,
        coteGagnant: 4.2,
      );
      expect(estimation.nature, NatureMontantBestBet.estimationAvantCourse);
      expect(estimation.estUneEstimation, isTrue,
          reason: 'le chiffre avant course DOIT être identifié comme une '
              'estimation');
      expect(estimation.nature, isNot(NatureMontantBestBet.officielApresCourse),
          reason: 'aucune estimation ne doit se présenter comme un gain '
              'officiel');
      // Et l'énumération doit rester exhaustive : trois natures, trois usages.
      expect(NatureMontantBestBet.values.length, 3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  7. ABSENCE D'EFFETS DE BORD
  // ═══════════════════════════════════════════════════════════════════════
  group('7. Absence d\'effets de bord', () {
    test('7.1 le simulateur n\'importe NI l\'IA NI un enregistreur', () async {
      // ★ Preuve par le GRAPHE D'IMPORTS : c'est structurel, pas déclaratif.
      final src =
          await _lireSource('lib/services/finance_simulateur_officiel.dart');
      for (final interdit in <String>[
        'ia_memory_service',
        'enregistreur_verdict',
        'alert_service',
        'service_gains_tardifs',
        'detection_gains_tardifs',
        'mes_paris',
        'flutter/material', // un service financier n'a aucune raison d'être UI
      ]) {
        expect(src.contains("import '") && src.contains(interdit), isFalse,
            reason: 'le simulateur ne doit PAS importer « $interdit » : '
                'c\'est ce qui garantit l\'absence d\'effet de bord');
      }
      // Et il doit bien importer la chaîne officielle et le repository.
      expect(src.contains('chaine_financiere_officielle.dart'), isTrue);
      expect(src.contains('resultat_officiel_repository.dart'), isTrue);
    });

    test('7.2 l\'estimation Best Bet n\'importe RIEN', () async {
      final src = await _lireSource('lib/services/estimation_best_bet.dart');
      final imports =
          RegExp(r"^import\s+'", multiLine: true).allMatches(src).length;
      expect(imports, 0,
          reason: 'un calcul d\'estimation pur ne doit avoir aucune '
              'dépendance : ni réseau, ni stockage, ni IA');
    });

    test('7.3 une simulation ne modifie AUCUN ticket réel', () async {
      // On simule 3 paris et on vérifie qu'aucune clé de « Mes Paris » n'a
      // été écrite dans SharedPreferences.
      await _vierge();
      await _sousServeur(() async {
        for (var i = 0; i < 3; i++) {
          await FinanceSimulateurOfficiel.simulerPari(
            courseKey: _courseKey,
            typePari: 'Simple Gagnant',
            numerosJoues: const <int>[kNumeroGagnant],
            mise: 10.0,
          );
        }
      }, corpsRapports: _corpsRapportsGagnant);

      final prefs = await SharedPreferences.getInstance();
      final cles = prefs.getKeys();
      // Aucune clé de ticket/alerte/notification ne doit apparaître.
      for (final k in cles) {
        final bas = k.toLowerCase();
        expect(bas.contains('ticket'), isFalse,
            reason: 'clé de ticket écrite par une simulation : $k');
        expect(bas.contains('mes_paris'), isFalse,
            reason: 'clé Mes Paris écrite par une simulation : $k');
        expect(bas.contains('alerte'), isFalse,
            reason: 'clé d\'alerte écrite par une simulation : $k');
        expect(bas.contains('notification'), isFalse,
            reason: 'clé de notification écrite par une simulation : $k');
      }
      // Seul le repository des résultats officiels a le droit d'écrire.
      expect(cles.any((k) => k.contains('resultat')), isTrue,
          reason: 'le repository DOIT persister le résultat officiel');
    });

    test('7.4 deux simulations identiques : un seul échange réseau', () async {
      await _vierge();
      late ResultatFinancierSimule a, b;
      final c = await _sousServeur(() async {
        a = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
        b = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsGagnant);

      expect(a.sort, SortPariSimule.gagne);
      expect(b.sort, SortPariSimule.gagne);
      expect(b.servieDepuisStockage, isTrue,
          reason: 'la seconde demande doit être servie depuis le stockage');
      // Une seule campagne de rapports pour deux simulations.
      expect(c.rapports, 1,
          reason: 'aucune requête répétitive inutile : '
              '${c.rapports} campagne(s) de rapports pour 2 simulations');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  8. RÉSILIENCE — provisoire, indisponibilité, récupération tardive
  // ═══════════════════════════════════════════════════════════════════════
  group('8. Résilience de la résolution', () {
    test('8.1 résultat PROVISOIRE puis DEFINITIF : la résolution se met à jour',
        () async {
      await _vierge();
      // 1) Arrivée provisoire → non déterminé.
      late ResultatFinancierSimule provisoire;
      await _sousServeur(() async {
        provisoire = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsGagnant, definitif: false);
      expect(provisoire.sort, SortPariSimule.nonDeterminee);

      // 2) Le PMU publie l'arrivée définitive → la résolution DOIT progresser,
      //    et non rester bloquée sur l'indétermination précédente.
      late ResultatFinancierSimule definitif;
      await _sousServeur(() async {
        definitif = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsGagnant, definitif: true);

      expect(definitif.sort, SortPariSimule.gagne,
          reason: 'un résultat provisoire ne doit JAMAIS bloquer '
              'définitivement la résolution');
      expect(definitif.gain, closeTo(42.0, 0.001));
    });

    test('8.2 source momentanément INJOIGNABLE : reprise possible ensuite',
        () async {
      await _vierge();
      // 1) L'endpoint par course renvoie 503 → indéterminé, sans invention.
      late ResultatFinancierSimule panne;
      await _sousServeur(() async {
        panne = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsGagnant, courseInjoignable: true);
      expect(panne.sort, SortPariSimule.nonDeterminee,
          reason: 'une panne ne doit jamais produire une perte');
      expect(panne.gain, isNull);

      // 2) La source revient → la résolution aboutit.
      late ResultatFinancierSimule apres;
      await _sousServeur(() async {
        apres = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsGagnant, definitif: true);
      expect(apres.sort, SortPariSimule.gagne,
          reason: 'une indisponibilité temporaire ne doit pas bloquer '
              'définitivement la résolution');
    });

    test('8.3 rapport ABSENT puis PUBLIÉ : récupération ultérieure', () async {
      await _vierge();
      // 1) Aucun rapport publié → indéterminé.
      late ResultatFinancierSimule avant;
      await _sousServeur(() async {
        avant = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, servirRapports: false);
      expect(avant.sort, SortPariSimule.nonDeterminee);

      // 2) Le rapport paraît → l'indétermination ne doit pas être figée.
      late ResultatFinancierSimule apres;
      await _sousServeur(() async {
        apres = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsGagnant, definitif: true);
      expect(apres.sort, SortPariSimule.gagne,
          reason: 'un rapport publié après coup doit être récupéré');
      expect(apres.gain, closeTo(42.0, 0.001));
    });

    test('8.4 Gagnant+Placé : deux mises distinctes, refus d\'une mise unique',
        () async {
      await _vierge();
      late ResultatFinancierSimule sim;
      await _sousServeur(() async {
        sim = await FinanceSimulateurOfficiel.simulerGagnantPlace(
          courseKey: _courseKey,
          numero: kNumeroGagnant,
          miseGagnant: 5.0,
          misePlace: 5.0,
        );
      }, corpsRapports: _corpsRapportsGagnant);

      expect(sim.typePari, 'Gagnant+Placé');
      // La mise totale est la SOMME DES DEUX composantes : 5 + 5 = 10.
      expect(sim.mise, closeTo(10.0, 0.001));
      expect(sim.sort, SortPariSimule.gagne,
          reason: 'le n°4 est 1er : ses deux composantes sont gagnantes');
      // Gain = 5×4.20 (Gagnant) + 5×2.10 (Placé) = 21 + 10.50 = 31.50.
      expect(sim.gain, closeTo(31.50, 0.001));
      // Net = 31.50 − 10 = 21.50.
      expect(sim.resultatNet, closeTo(21.50, 0.001));
    });
  });
}

// ─────────────────────────── utilitaires de test ───────────────────────────

ResultatFinancierSimule _gain(String key, double mise) =>
    ResultatFinancierSimule(
      courseKey: key,
      typePari: 'Simple Gagnant',
      numerosJoues: const <int>[4],
      mise: mise,
      sort: SortPariSimule.gagne,
      gain: mise * kDividendeGagnant,
      remboursement: 0.0,
      resultatNet: mise * kDividendeGagnant - mise,
    );

/// Miroir minimal de `StatTypePari.ajouterPari` / `ajouterPariRembourse`,
/// pour vérifier l'arithmétique SANS instancier le service complet.
class _FauxStat {
  int nbTotal = 0;
  int nbGagnes = 0;
  int nbRembourses = 0;
  int maxSerie = 0;
  double gainNet = 0.0;
  int _serie = 0;

  void ajouterPari({
    required bool gagne,
    required double gain,
    required double mise,
  }) {
    nbTotal++;
    gainNet += gain;
    if (gagne) {
      nbGagnes++;
      _serie = 0;
    } else {
      _serie++;
      if (_serie > maxSerie) maxSerie = _serie;
    }
  }

  void ajouterPariRembourse({
    required double remboursement,
    required double mise,
  }) {
    nbTotal++;
    gainNet += remboursement - mise;
    nbRembourses++;
    // Séries INCHANGÉES.
  }
}

/// Lit un fichier source du dépôt (garde structurelle).
/// Le test tourne sur la VM Dart : `dart:io` est disponible.
Future<String> _lireSource(String chemin) => File(chemin).readAsString();
