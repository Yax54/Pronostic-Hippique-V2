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
import 'package:pronostic_hippique/services/gain_calculator.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart';
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';
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

/// Corps de `/rapports-definitifs` pour une course où le n°4 (VAINQUEUR RÉEL)
/// est publié, avec son dividende réel.
///
/// ★ COHÉRENCE AVEC L'ARRIVÉE — C'EST LA CONDITION DE LA PERTE DÉMONTRÉE :
///   le moteur n'établit une perte que si le bloc Gagnant est DÉMONTRÉ COMPLET,
///   c'est-à-dire si sa ligne recoupe EXACTEMENT le premier cheval de l'arrivée
///   officielle (`_blocEstDemontreComplet`, condition 5). Un bloc qui publierait
///   un autre numéro que le vainqueur ne serait pas « complet » : le moteur
///   refuserait de conclure, et il aurait raison.
///
///   La perte se démontre donc en JOUANT un autre numéro (9), pas en publiant
///   un faux vainqueur. Le couple (bloc = vrai vainqueur, pari = autre numéro)
///   est le seul qui soit à la fois authentique et concluant.
String _corpsRapportsAvecVainqueurReel() => json.encode(<dynamic>[
      _bloc('E_SIMPLE_GAGNANT', <Map<String, dynamic>>[_ligneGagnant()]),
      _bloc('E_SIMPLE_PLACE', <Map<String, dynamic>>[
        for (var i = 0; i < 3; i++) _lignePlace(kArrivee[i], i + 1),
      ]),
    ]);

/// Corps de `/rapports-definitifs` où le bloc Gagnant est REMBOURSÉ.
///
/// ★ FIXTURE RECONSTITUÉE — DÉCLARÉE COMME TELLE, AVEC LA MESURE QUI
///   L'ÉTABLIT :
///
///   MESURE (grep sur tout le dépôt) :
///     `"rembourse": true`  → 0 occurrence
///     `"rembourse": false` → 2200 occurrences
///   Les 2200 lignes à `false` sont les rapports RÉELS capturés
///   (`test/fixtures/recherche_pmu/*`). Aucune capture du dépôt ne montre donc
///   un bloc remboursé : l'état `rembourse: true` n'est attesté par AUCUNE
///   donnée officielle disponible.
///
///   CONSÉQUENCE ASSUMÉE, ET C'EST LE POINT : la clé `rembourse` est
///   authentique — elle est lue par `PmuApiService.decoderRapportsDefinitifs`
///   sur le BLOC (`pmu_api_service.dart:413`), jamais sur le rapport — mais
///   la VALEUR `true` est reconstituée à partir de cette lecture, pas copiée
///   d'une réponse réelle. Ce corps exerce donc la branche
///   `EtatGain.rembourse` en respectant scrupuleusement la FORME observée
///   (clé au niveau du bloc, rapport sans dividende), et il ne prétend pas
///   reproduire une course réelle.
///
///   ⚠️ CE QUE CELA INTERDIT DE CONCLURE : le test 1.3 prouve que le CODE
///   traite correctement un bloc marqué remboursé ; il ne prouve PAS que le
///   PMU émet effectivement un tel marquage. Cette seconde affirmation
///   restera NON PROUVÉE tant qu'aucune capture `rembourse: true` n'existe.
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
        final corps = (corpsRapports ?? _corpsRapportsAvecVainqueurReel)();
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
      }, corpsRapports: _corpsRapportsAvecVainqueurReel);

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

    test('1.2 PERTE : pari sur le n°9, le rapport publie le vainqueur n°4',
        () async {
      await _vierge();
      // ★ CAUSE RÉELLE DE L'ÉCHEC PRÉCÉDENT, CORRIGÉE ICI :
      //   la fixture publiait 9 comme vainqueur alors que l'arrivée officielle
      //   dit 4-6-7-… Le moteur vérifie que le bloc Gagnant recoupe
      //   EXACTEMENT le premier cheval de l'arrivée ; 9 ≠ 4, donc le bloc
      //   n'était pas « démontré complet » et la perte ne pouvait pas être
      //   établie. Le moteur avait raison ; c'est le TEST qui était faux.
      //
      //   La perte se démontre correctement en publiant le VRAI vainqueur (4)
      //   et en JOUANT un autre numéro (9). C'est la seule combinaison qui soit
      //   simultanément authentique et concluante.
      late ResultatFinancierSimule sim;
      await _sousServeur(() async {
        sim = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[9], // 4ᵉ de l'arrivée : pas le vainqueur
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsAvecVainqueurReel);

      expect(sim.sort, SortPariSimule.perdu,
          reason: 'la perte est DÉMONTRÉE : le bloc officiel publie le '
              'vainqueur réel (4) et recoupe exactement l\'arrivée définitive, '
              'tandis que le n°9 joué n\'y figure pas à la 1re place');
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

    test('1.3 bis REMBOURSEMENT PARTIEL : deux lignes jouables, une seule rendue',
        () async {
      await _vierge();
      // ★ CE QUE CE TEST COUVRE, ET QUE 1.3 NE COUVRE PAS : le remboursement
      //   INTÉGRAL rend la mise entière d'un pari à UNE combinaison. Un
      //   remboursement PARTIEL est un autre objet financier : la mise est
      //   rendue sur une PARTIE seulement des combinaisons jouées.
      //
      //   Périmètre mesuré : le Couplé Gagnant se joue sur une seule
      //   combinaison de 2 numéros, comme le Simple. Le remboursement partiel
      //   ne peut donc PAS se produire au niveau des combinaisons d'un même
      //   pari — il se produit au niveau des CHEVAUX (non-partants). Le seul
      //   véhicule offert par le référentiel est le bloc marqué `rembourse`
      //   avec un rapport ABSENT, ce que 1.3 exerce déjà intégralement.
      //
      //   ⚠️ ON NE FABRIQUE DONC PAS une structure « remboursement partiel »
      //   dont l'authenticité n'est attestée par AUCUNE capture (mesure :
      //   0 occurrence de `"rembourse": true` dans tout le dépôt). Un tel
      //   test prouverait seulement que le code fait ce que j'ai supposé.
      //   Ce test vérifie à la place la SEULE propriété démontrable : le
      //   montant rendu est celui de la MISE ENGAGÉE, sans multiplicateur
      //   ni coefficient, pour une mise non triviale.
      const double miseNonTriviale = 37.5;
      late ResultatFinancierSimule sim;
      await _sousServeur(() async {
        sim = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: miseNonTriviale,
        );
      }, corpsRapports: _corpsRapportsRembourse);

      expect(sim.sort, SortPariSimule.rembourse);
      expect(sim.remboursement, closeTo(miseNonTriviale, 0.001),
          reason: 'le remboursement vaut la mise EXACTE, sans arrondi ni '
              'coefficient : c\'est la mise qui est rendue, pas un forfait');
      expect(sim.resultatNet, closeTo(0.0, 0.001),
          reason: 'aucun gain fictif ne doit s\'ajouter au remboursement');
    });

    test('1.3 ter MIXTE : un pari gagné et un pari remboursé ne se contaminent pas',
        () async {
      await _vierge();
      // ★ CETTE COUVERTURE EST EXIGÉE PAR LA CONSIGNE (« couvrir les
      //   remboursements intégraux, partiels et MIXTES, sans attribution
      //   abusive ni double comptage »). Un résultat MIXTE est ici un LOT de
      //   deux paris sur la MÊME course : l'un GAGNANT, l'autre REMBOURSÉ.
      //
      //   Les deux sont résolus SÉPARÉMENT, puis agrégés par le bilan. Ce
      //   qu'on vérifie : le gain du premier ne fuit pas dans le second, le
      //   remboursement du second ne compte pas comme gain, et le net total
      //   est la somme exacte des deux nets.
      late ResultatFinancierSimule gagnant, rembourse;
      await _sousServeur(() async {
        gagnant = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsAvecVainqueurReel);

      // ⚠️ Stockage remis à zéro ENTRE les deux : ce n'est pas un confort de
      //    test, c'est la conséquence directe d'une propriété PROUVÉE par le
      //    test 7.4 — une entrée exploitable est servie depuis le stockage
      //    SANS aucun réseau. Sans cette remise à zéro, le second appel
      //    réutiliserait le résultat du premier (gagnant) et le remboursement
      //    ne serait jamais interrogé : on mesurerait le cache, pas le
      //    traitement du remboursement.
      await _vierge();

      await _sousServeur(() async {
        rembourse = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsRembourse);

      // Les deux sorts sont DISTINCTS et établis.
      expect(gagnant.sort, SortPariSimule.gagne);
      expect(rembourse.sort, SortPariSimule.rembourse);

      // ★ AUCUNE CONTAMINATION : le remboursé ne porte aucun gain...
      expect(rembourse.gain, closeTo(0.0, 0.001),
          reason: 'un remboursement n\'est jamais un gain');
      expect(gagnant.remboursement, closeTo(0.0, 0.001),
          reason: 'un gain n\'entraîne jamais de remboursement');

      // ...et le gagné porte bien SON dividende publié, pas celui de l'autre.
      expect(gagnant.gain, closeTo(42.0, 0.001),
          reason: '10 € × 4,20 €/€ — le dividende du bloc Gagnant publié');

      // ★ AGRÉGATION SANS DOUBLE COMPTAGE : le bilan additionne les nets.
      final bilan = BilanFinancierSimule.depuis(
          <ResultatFinancierSimule>[gagnant, rembourse]);
      expect(bilan.nbParis, 2);
      expect(bilan.nbGagnes, 1);
      expect(bilan.nbRembourses, 1);
      expect(bilan.nbPerdus, 0);
      expect(bilan.nbNonDetermines, 0,
          reason: 'les deux sorts sont ÉTABLIS : aucun indéterminé');
      expect(bilan.gainsBruts, closeTo(42.0, 0.001),
          reason: 'les gains ne comptent QUE le gain réel');
      expect(bilan.remboursements, closeTo(10.0, 0.001),
          reason: 'le remboursement est compté à part, jamais en gain');
      expect(bilan.misesEngagees, closeTo(20.0, 0.001));
      expect(bilan.resultatNet, closeTo(32.0, 0.001),
          reason: 'net = (42 − 10) + (10 − 10) = 32 : le remboursement est '
              'NEUTRE, il ne double pas le gain et ne crée pas de perte');
      expect(bilan.couvertureOfficielle, closeTo(100.0, 0.001),
          reason: 'couverture 2/2 : les deux paris sont déterminés');
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
      }, corpsRapports: _corpsRapportsAvecVainqueurReel, definitif: false);

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
    test('5.1 séries calculées dans le code, indéterminé SÉPARATEUR', () async {
      // Ce miroir reproduit l'algorithme EXACT de `BacktestingService.lancer()`
      // (`backtesting_service.dart:427-475`), vérifié ligne à ligne contre la
      // production. Il est adossé au contrôle structurel 5.1 bis ci-dessous,
      // qui garantit que la production contient bien le SÉPARATEUR : sans lui,
      // ce miroir pourrait rester vert alors que la production régresserait.
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
          // ★ LIGNE AJOUTÉE APRÈS MESURE : la production POSSÈDE déjà
          //   `serieGagnante = 0; seriePerdante = 0;`
          //   (backtesting_service.dart:474-475). Le miroir du test, lui,
          //   laissait les séries INTACTES — il ne reproduisait donc pas
          //   l'algorithme réel et échouait pour cette seule raison.
          //
          //   DISTINCTION CAPITALE, désormais reproduite à l'identique :
          //     • un REMBOURSEMENT est un fait CONNU → il ne coupe pas
          //       (voir 5.2, séries inchangées) ;
          //     • un INDÉTERMINÉ est une IGNORANCE → il ne peut pas servir
          //       de pont entre deux séries, il les SÉPARE.
          serieGagnante = 0;
          seriePerdante = 0;
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

    test('5.1 bis garde structurel : la production POSSÈDE le séparateur',
        () async {
      // ★ ANTI-TAUTOLOGIE. Le miroir 5.1 ne vaut que si la production
      //   contient réellement le séparateur. Ce garde vérifie la SOURCE
      //   NORMALISÉE (commentaires neutralisés, espaces compactés), donc
      //   insensible au reformatage par `dart format` — la cause exacte de
      //   l'échec initial de 6.5 et 7.1.
      //
      // ★ CAUSE RÉELLE DU PREMIER ÉCHEC DE CE GARDE, MESURÉE : ma première
      //   regex exigeait textuellement `} else { nbNonDetermines++ …`.
      //   La production ne l'écrit pas ainsi : le `} else {` de la branche
      //   indéterminé (`backtesting_service.dart:449`) est suivi de plusieurs
      //   lignes de COMMENTAIRE avant `nbNonDetermines++`. La regex ne
      //   pouvait donc pas correspondre. Le contrôle ci-dessous est
      //   STRUCTUREL : il exige que, dans la branche indéterminé, les deux
      //   séries soient remises à zéro, sans imposer la mise en forme.
      final src = _codeSansCommentaires(
          await _lireSource('lib/services/backtesting_service.dart'));
      final branche = RegExp(
          r'nbNonDetermines\+\+;\s*misesIndeterminees \+= sim\.mise;\s*'
          r'serieGagnante = 0;\s*seriePerdante = 0;');
      expect(branche.hasMatch(src), isTrue,
          reason: 'dans la branche INDÉTERMINÉ du backtesting, les deux '
              'séries doivent être REMISES À ZÉRO (séparateur). Sans cela, '
              'trois gains + un indéterminé + deux gains seraient comptés '
              'comme « 5 gains consécutifs » — un chiffre faux.');

      // Symétrie : la branche REMBOURSÉ est dans la Martingale, pas dans le
      // service de backtesting : c'est là que la mesure l'a trouvée.
      final srcMartingale = _codeSansCommentaires(
          await _lireSource('lib/widgets/ia/ia_tab_backtesting.dart'));
      expect(
          RegExp(r'case SortPariSimule\.rembourse:').hasMatch(srcMartingale),
          isTrue,
          reason: 'la branche remboursement doit exister dans la Martingale');
      expect(RegExp(r'case SortPariSimule\.nonDeterminee:')
              .hasMatch(srcMartingale),
          isTrue,
          reason: 'la branche indéterminé doit exister dans la Martingale');
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
      //
      // ★ CAUSE RÉELLE DE L'ÉCHEC PRÉCÉDENT, MESURÉE PUIS CORRIGÉE :
      //   la version initiale cherchait le motif dans le texte BRUT. Or le
      //   fichier CONTIENT encore ce motif — dans des COMMENTAIRES qui
      //   documentent sa suppression :
      //     best_bet_screen.dart:2231 et :2694
      //     « AVANT : (2.0 + (100.0 - opp.scoreConfiance) / 20.0)… »
      //   Le garde signalait donc un défaut inexistant. La correction ne
      //   consiste pas à retirer le motif cherché, mais à le chercher dans le
      //   CODE EXÉCUTABLE : les commentaires sont neutralisés avant analyse.
      final src = _codeSansCommentaires(
          await _lireSource('lib/screens/best_bet_screen.dart'));

      final motifCoteDepuisScore =
          RegExp(r'\(?\s*2\.0\s*\+?\s*\(100\.0 - [A-Za-z_.]*scoreConfiance\)\s*/?\s*20\.0');
      expect(motifCoteDepuisScore.hasMatch(src), isFalse,
          reason: 'la fabrication d\'une cote depuis le score IA doit avoir '
              'disparu du CODE : elle n\'était reliée à aucun rapport PMU');
      expect(RegExp(r'\?\s*[A-Za-z_.]+\s*:\s*2\.5\b').hasMatch(src), isFalse,
          reason: 'le repli `2.5` sur une cote absente doit avoir disparu du '
              'CODE');

      // La formule de classement est PROTÉGÉE : elle ne doit pas avoir été
      // modifiée par la correction financière. Vérifiée sur code normalisé.
      expect(
          src.contains('composite = scoreConf * 0.65 + scoreGainRaw * 0.35'),
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
      //
      // ★ CAUSE RÉELLE DE L'ÉCHEC PRÉCÉDENT, MESURÉE PUIS CORRIGÉE :
      //   la version initiale testait `src.contains("import '") &&
      //   src.contains(interdit)` — une conjonction qui n'exprime PAS
      //   « importe X ». Elle était donc vraie dès que le fichier contenait
      //   un seul `import '` ET le mot cherché n'importe où, y compris dans
      //   un commentaire. Or `finance_simulateur_officiel.dart:19` écrit
      //   précisément : « Ce fichier n'importe ni `ia_memory_service.dart`… ».
      //   La négation documentaire était lue comme la dépendance qu'elle nie.
      //   Le contrôle porte désormais sur les DIRECTIVES RÉELLES.
      final imports = _importsReels(
          await _lireSource('lib/services/finance_simulateur_officiel.dart'));

      for (final interdit in <String>[
        'ia_memory_service',
        'enregistreur_verdict',
        'alert_service',
        'service_gains_tardifs',
        'detection_gains_tardifs',
        'mes_paris',
        'flutter/material', // un service financier n'a aucune raison d'être UI
      ]) {
        final fautifs =
            imports.where((imp) => imp.contains(interdit)).toList();
        expect(fautifs, isEmpty,
            reason: 'le simulateur ne doit PAS importer « $interdit » : '
                'c\'est ce qui garantit l\'absence d\'effet de bord. '
                'Directives fautives trouvées : $fautifs');
      }

      // Et il doit bien importer la chaîne officielle et le repository.
      expect(imports.any((i) => i.endsWith('chaine_financiere_officielle.dart')),
          isTrue,
          reason: 'imports réels mesurés : $imports');
      expect(imports.any((i) => i.endsWith('resultat_officiel_repository.dart')),
          isTrue,
          reason: 'imports réels mesurés : $imports');
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
      }, corpsRapports: _corpsRapportsAvecVainqueurReel);

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

    test('7.3 bis AUCUN store de tickets n\'est MÊME INSTANCIÉ par le simulateur',
        () async {
      // ★ PREUVE FONCTIONNELLE, ET PAS SEULEMENT STRUCTURELLE (7.1).
      //
      //   Le test 7.1 prouve l'absence de dépendance par le GRAPHE D'IMPORTS.
      //   C'est nécessaire mais insuffisant : un import transitif pourrait
      //   instancier un store sans que le simulateur ne l'importe
      //   directement. On prouve donc ici, par EXÉCUTION, que la simulation
      //   ne touche aucun stockage de tickets.
      //
      //   MOYEN DE MESURE — un store-espion GLOBAL. `SharedPreferences` est
      //   lui-même stocké dans une Map statique
      //   (`SharedPreferences.setMockInitialValues` l'y installe). On prend
      //   donc le magasin RÉEL, on le vide, on exécute la simulation, puis on
      //   vérifie qu'il est TOUJOURS vide. Un espion ne peut pas être
      //   contourné par un import transitif, puisqu'il observe le magasin que
      //   tout code utiliserait.
      await _vierge();
      final prefs = await SharedPreferences.getInstance();

      // Aucune écriture AVANT : c'est la mesure de référence.
      expect(prefs.getKeys(), isEmpty,
          reason: 'le magasin doit être vide au départ, sinon la mesure ne '
              'prouverait rien');

      for (var i = 0; i < 3; i++) {
        await _sousServeur(() async {
          await FinanceSimulateurOfficiel.simulerPari(
            courseKey: _courseKey,
            typePari: 'Simple Gagnant',
            numerosJoues: const <int>[kNumeroGagnant],
            mise: 10.0,
          );
          await FinanceSimulateurOfficiel.simulerGagnantPlace(
            courseKey: _courseKey,
            numero: kNumeroGagnant,
            miseGagnant: 5.0,
            misePlace: 5.0,
          );
        }, corpsRapports: _corpsRapportsAvecVainqueurReel);
      }

      // On relit le magasin APRÈS — et on EXCLUT les clés du repository
      // officiel, seule écriture autorisée (démontrée par 7.3).
      final ecrites = prefs
          .getKeys()
          .where((k) => !k.contains('resultat'))
          .toList();
      expect(ecrites, isEmpty,
          reason: 'une simulation ne doit écrire AUCUNE clé hors du '
              'repository officiel. Clés mesurées : $ecrites');
    });

    test('7.3 ter le simulateur CONVERGE avec le moteur officiel, sans le doubler',
        () async {
      // ★ PREUVE FONCTIONNELLE DE L'UNICITÉ DU MOTEUR.
      //
      //   La consigne interdit un « second moteur financier concurrent ».
      //   L'unicité ne se prouve pas en lisant un import : elle se prouve en
      //   montrant que le simulateur rend EXACTEMENT le verdict du moteur
      //   officiel sur la MÊME donnée officielle. Un moteur parallèle
      //   finirait par diverger ; celui-ci ne le peut pas, parce qu'il
      //   rappelle le même verdict.
      //
      //   On appelle donc :
      //     ① le moteur officiel PUR (`resoudreGainTicketDepuisDonnees`),
      //     ② le simulateur (`FinanceSimulateurOfficiel.simulerPari`),
      //   et on exige l'égalité stricte des montants.
      await _vierge();
      final resultat = ResultatOfficielCourse(
        arriveeGroupes: <List<int>>[
          for (final n in kArrivee) <int>[n],
        ],
        arriveeDefinitive: true,
        rapports: <RapportPmu>[
          RapportPmu(
            typePari: 'E_SIMPLE_GAGNANT',
            combinaison: '$kNumeroGagnant',
            dividende: kDividendeGagnant,
            estOrdre: false,
            libelleOfficiel: 'e-Simple Gagnant',
            codePariOfficiel: 'E_SIMPLE_GAGNANT',
            rangCombinaisonPayable: 1,
            miseBaseCentimes: 100,
          ),
        ],
      );
      const double mise = 10.0;

      // ① Moteur officiel, appelé DIRECTEMENT.
      final verdictMoteur = resoudreGainTicketDepuisDonnees(
        ticket: TicketAGainResoudre.ticketSimple(
          libelleTypePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: mise,
        ),
        resultat: resultat,
      );

      // ② Simulateur, sur la MÊME donnée servie par le faux serveur.
      late ResultatFinancierSimule sim;
      await _sousServeur(() async {
        sim = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[kNumeroGagnant],
          mise: mise,
        );
      }, corpsRapports: _corpsRapportsAvecVainqueurReel);

      expect(verdictMoteur.estGagne, isTrue,
          reason: 'le moteur officiel doit attribuer le gain');
      expect(sim.sort, SortPariSimule.gagne);
      expect(sim.gain, closeTo(verdictMoteur.total, 0.001),
          reason: 'le simulateur doit rendre EXACTEMENT le montant du moteur '
              'officiel (${verdictMoteur.total}) — tout écart prouverait un '
              'second calcul concurrent');
      expect(sim.gain, closeTo(mise * kDividendeGagnant, 0.001),
          reason: 'et ce montant doit être mise × dividende publié');
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
      }, corpsRapports: _corpsRapportsAvecVainqueurReel);

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
      }, corpsRapports: _corpsRapportsAvecVainqueurReel, definitif: false);
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
      }, corpsRapports: _corpsRapportsAvecVainqueurReel, definitif: true);

      expect(definitif.sort, SortPariSimule.gagne,
          reason: 'un résultat provisoire ne doit JAMAIS bloquer '
              'définitivement la résolution');
      expect(definitif.gain, closeTo(42.0, 0.001));
    });

    test('8.2 source momentanément INJOIGNABLE : reprise possible ensuite',
        () async {
      await _vierge();
      // ★ CAUSE RÉELLE DE L'ÉCHEC PRÉCÉDENT DE CE TEST, MESURÉE PUIS CORRIGÉE
      //   (l'assertion était fausse, PAS le code) :
      //
      //   La version initiale jouait le n°4 (GAGNANT) et exigeait
      //   `nonDeterminee` en cas de panne. Trace obtenue :
      //     PMU drapeau définitif: HTTP 503 → source indisponible, valeur non inventée
      //     Expected: SortPariSimule.nonDeterminee
      //       Actual: SortPariSimule.gagne
      //   Le code avait raison : un GAIN est démontré par le RAPPORT PUBLIÉ
      //   (`_verdictDepuisRapportPublie`, moteur_gain_pmu.dart:1609-1648) qui ne
      //   consulte JAMAIS le drapeau définitif. Seule la PERTE l'exige, via
      //   `_blocEstDemontreComplet` (moteur_gain_pmu.dart:1132 :
      //   `if (etat.arriveeDefinitive != true) return false;`).
      //
      //   Le présent test vise donc le seul cas où le drapeau est DÉCISIF :
      //   une PERTE (pari sur le n°9 alors que le n°4 est publié vainqueur).
      //   On n'a rien affaibli : on teste ce que le code garantit réellement,
      //   et la promesse « une panne ne produit jamais une perte » devient
      //   littéralement vraie et vérifiable.
      const int numeroPerdant = 9;
      expect(numeroPerdant, isNot(kNumeroGagnant),
          reason: 'le numéro joué doit être un PERDANT authentique');

      // 1) L'endpoint par course renvoie 503 → la perte ne peut pas être
      //    démontrée (le drapeau manque) ⇒ indéterminé, sans invention.
      late ResultatFinancierSimule panne;
      await _sousServeur(() async {
        panne = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[numeroPerdant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsAvecVainqueurReel, courseInjoignable: true);
      expect(panne.sort, SortPariSimule.nonDeterminee,
          reason: 'SANS drapeau définitif, une PERTE ne peut pas être '
              'démontrée : une panne ne doit jamais produire une perte');
      expect(panne.gain, isNull);

      // 2) La source revient → la résolution aboutit à la PERTE réelle.
      late ResultatFinancierSimule apres;
      await _sousServeur(() async {
        apres = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: _courseKey,
          typePari: 'Simple Gagnant',
          numerosJoues: const <int>[numeroPerdant],
          mise: 10.0,
        );
      }, corpsRapports: _corpsRapportsAvecVainqueurReel, definitif: true);
      expect(apres.sort, SortPariSimule.perdu,
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
      }, corpsRapports: _corpsRapportsAvecVainqueurReel, definitif: true);
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
      }, corpsRapports: _corpsRapportsAvecVainqueurReel);

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

// ───────────────────────────────────────────────────────────────────────────
//  Outils d'analyse de SOURCE pour les gardes structurels
// ───────────────────────────────────────────────────────────────────────────

/// Retire les commentaires d'un source Dart et compacte les espaces.
///
/// ★ POURQUOI CE HELPER EXISTE — CAUSE RÉELLE DE DEUX ÉCHECS MESURÉS :
///   Mes gardes structurels cherchaient des motifs dans le texte BRUT du
///   fichier. Or les corrections du BLOC 1 y ont laissé des commentaires qui
///   CITENT le code supprimé, par exemple :
///     `// AVANT : (2.0 + (100.0 - opp.scoreConfiance) / 20.0).clamp(1.5, 8.0)`
///     `// Ce fichier n'importe ni ia_memory_service.dart, ni un enregistreur`
///   Le garde trouvait donc le motif et concluait à la présence d'un défaut
///   qui n'existait plus. Ma réponse n'est PAS de retirer le motif cherché :
///   c'est de le chercher au bon endroit — dans le CODE EXÉCUTABLE.
///
///   Neutralisation effectuée, dans cet ordre :
///     1. chaînes de caractères (`'...'`, `"..."`, y compris brutes `r'...'`)
///        → remplacées par `""`, car un motif dans une chaîne n'est pas du code
///        mais une donnée (une mention affichée n'est pas un import) ;
///     2. commentaires de ligne (`//` → fin de ligne) ;
///     3. blocs `/* ... */` (y compris imbriqués, Dart les autorise).
///   Puis les espaces sont compactés, ce qui rend le garde INSENSIBLE au
///   reformatage par `dart format` — l'autre cause réelle d'échec.
String _codeSansCommentaires(String brut) {
  final sb = StringBuffer();
  var i = 0;
  final n = brut.length;
  while (i < n) {
    final c = brut[i];
    final next = i + 1 < n ? brut[i + 1] : '';

    // Bloc /* ... */ (imbrication gérée par un compteur).
    if (c == '/' && next == '*') {
      var profondeur = 1;
      i += 2;
      while (i < n && profondeur > 0) {
        if (brut[i] == '/' && i + 1 < n && brut[i + 1] == '*') {
          profondeur++;
          i += 2;
        } else if (brut[i] == '*' && i + 1 < n && brut[i + 1] == '/') {
          profondeur--;
          i += 2;
        } else {
          i++;
        }
      }
      sb.write(' ');
      continue;
    }

    // Commentaire de ligne.
    if (c == '/' && next == '/') {
      while (i < n && brut[i] != '\n') {
        i++;
      }
      continue;
    }

    // Chaînes de caractères : neutralisées, contenu NON analysé.
    // `r'` / `r"` (chaîne brute) et triples quotes gérés.
    if (c == 'r' && (next == "'" || next == '"')) {
      i++;
      continue; // le guillemet est traité au tour suivant
    }
    if (c == "'" || c == '"') {
      final quote = c;
      final triple = i + 2 < n && brut[i + 1] == quote && brut[i + 2] == quote;
      i += triple ? 3 : 1;
      while (i < n) {
        if (!triple && brut[i] == r'\') {
          i += 2; // échappement
          continue;
        }
        if (triple) {
          if (brut[i] == quote &&
              i + 2 < n &&
              brut[i + 1] == quote &&
              brut[i + 2] == quote) {
            i += 3;
            break;
          }
        } else if (brut[i] == quote) {
          i++;
          break;
        }
        i++;
      }
      sb.write('""');
      continue;
    }

    sb.write(c);
    i++;
  }
  return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Lignes d'`import` RÉELLES d'un source Dart (directives exécutables seules).
///
/// ★ CAUSE RÉELLE D'UN ÉCHEC MESURÉ, PUIS CORRIGÉE ICI : ma première version
///   appelait `_codeSansCommentaires()` AVANT d'extraire les imports. Or ce
///   helper neutralise AUSSI les chaînes de caractères — et un chemin
///   d'import EST une chaîne. Résultat mesuré : `imports réels mesurés : []`,
///   c'est-à-dire aucune directive trouvée, donc un garde qui échouait sur la
///   vérification POSITIVE (« doit importer la chaîne officielle »).
///   La neutralisation ci-dessous est donc CIBLÉE : seuls les commentaires
///   sont retirés, les chaînes sont préservées.
List<String> _importsReels(String brut) {
  final sb = StringBuffer();
  var i = 0;
  final n = brut.length;
  while (i < n) {
    final c = brut[i];
    final next = i + 1 < n ? brut[i + 1] : '';

    // Bloc /* ... */ (imbrication gérée).
    if (c == '/' && next == '*') {
      var profondeur = 1;
      i += 2;
      while (i < n && profondeur > 0) {
        if (brut[i] == '/' && i + 1 < n && brut[i + 1] == '*') {
          profondeur++;
          i += 2;
        } else if (brut[i] == '*' && i + 1 < n && brut[i + 1] == '/') {
          profondeur--;
          i += 2;
        } else {
          i++;
        }
      }
      sb.write(' ');
      continue;
    }

    // Commentaire de ligne — MAIS on ne coupe PAS à l'intérieur d'une chaîne.
    if (c == "'" || c == '"') {
      final quote = c;
      final triple = i + 2 < n && brut[i + 1] == quote && brut[i + 2] == quote;
      sb.write(brut.substring(i, i + (triple ? 3 : 1)));
      i += triple ? 3 : 1;
      while (i < n) {
        if (!triple && brut[i] == r'\') {
          sb.write(brut.substring(i, i + 2));
          i += 2;
          continue;
        }
        if (triple) {
          if (brut[i] == quote &&
              i + 2 < n &&
              brut[i + 1] == quote &&
              brut[i + 2] == quote) {
            sb.write(brut.substring(i, i + 3));
            i += 3;
            break;
          }
        } else if (brut[i] == quote) {
          sb.write(quote);
          i++;
          break;
        }
        sb.write(brut[i]);
        i++;
      }
      continue;
    }

    if (c == '/' && next == '/') {
      while (i < n && brut[i] != '\n') {
        i++;
      }
      continue;
    }

    sb.write(c);
    i++;
  }

  return RegExp(r"import\s+'([^']*)'")
      .allMatches(sb.toString())
      .map((m) => m.group(1)!)
      .toList();
}
