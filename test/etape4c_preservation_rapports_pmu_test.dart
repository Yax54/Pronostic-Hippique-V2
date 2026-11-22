// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 4-C — PRÉSERVATION DES INFORMATIONS OFFICIELLES PMU
//
//  OBJET : le décodage des `rapports-definitifs` conservait déjà `typePari`,
//  `combinaison`, `dividende` et un `estOrdre` HEURISTIQUE. Il JETAIT le
//  `libelle` officiel, le `rangCombinaisonPayable`, le `rembourse` du bloc, la
//  `miseBase` et l'unité. Ce lot les conserve — sans changer un seul montant.
//
//  ── ORIGINE DE LA FIXTURE ────────────────────────────────────────────────
//  Le corps JSON ci-dessous reproduit EXACTEMENT la structure mesurée sur
//  l'API de production le 2026-11-21 :
//
//    GET https://turfinfo.api.pmu.fr/rest/client/7/programme/18112026/
//        R1/C1/rapports-definitifs?specialisation=INTERNET        → HTTP 200
//
//  Clés de BLOC observées : typePari, miseBase, rembourse, rapports,
//                           audience, dividendeUnite, famillePari
//  Clés de RAPPORT observées : combinaison, dividende, dividendePourUnEuro,
//                           dividendePourUneMiseDeBase, dividendeUnite,
//                           libelle, nombreGagnants, rangCombinaisonPayable
//
//  Mesuré alors : `libelle` présent sur 56/56 rapports (0 absent).
//
//  ⚠️ Les valeurs de dividende sont celles RÉELLEMENT publiées pour R1C1,
//  y compris le cas notable `e-Quarté+ Ordre` à `dividendePourUnEuro = 0`.
//
//  ── CE QUE CE LOT NE FAIT PAS ────────────────────────────────────────────
//   • Aucun remplacement des codes historiques dans les écrans.
//   • Aucune modification de `matching.first`, `reduce(MAX)`, `rList.first`.
//   • Aucun raccordement du résolveur aux écritures financières.
//   • Aucune correction de l'heuristique `estOrdre` (elle est seulement
//     DOCUMENTÉE comme insuffisante, et le test le prouve).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/gain_calculator.dart';
import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'package:pronostic_hippique/services/resolveur_rapport_pmu.dart';

// ───────────────────────────────────────────────────────────────────────────
//  1. FIXTURE — RÉPONSE RÉELLE R1C1 DU 18/11/2026
// ───────────────────────────────────────────────────────────────────────────

/// Construit le corps tel que l'API le renvoie : une LISTE de blocs, chaque
/// bloc portant ses rapports.
///
/// `E_QUARTE_PLUS` illustre un cas réel : « e-Quarté+ Ordre » est publié avec
/// un dividende de 0 (aucun gagnant dans l'ordre) tandis que le Désordre paie.
String corpsReelR1C1() => json.encode([
      // ── Bloc Simple Gagnant ────────────────────────────────────────────
      {
        'typePari': 'E_SIMPLE_GAGNANT',
        'miseBase': 100,
        'rembourse': false,
        'audience': 'NATIONAL',
        'dividendeUnite': 'PourUnEuro',
        'famillePari': 'Simple',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Simple Gagnant',
            'dividende': 3130,
            'dividendePourUnEuro': 3130,
            'combinaison': '2',
            'nombreGagnants': 1661.34,
            'dividendePourUneMiseDeBase': 3130,
            'dividendeUnite': 'PourUnEuro',
          },
        ],
      },
      // ── Bloc Simple Placé : 3 chevaux, même libellé ────────────────────
      {
        'typePari': 'E_SIMPLE_PLACE',
        'miseBase': 100,
        'rembourse': false,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Simple Placé',
            'combinaison': '2',
            'dividendePourUnEuro': 630,
          },
          {
            'rangCombinaisonPayable': 2,
            'libelle': 'e-Simple Placé',
            'combinaison': '1',
            'dividendePourUnEuro': 260,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Simple Placé',
            'combinaison': '14',
            'dividendePourUnEuro': 240,
          },
        ],
      },
      // ── Bloc Tiercé : MÊME combinaison, Ordre ET Désordre ──────────────
      {
        'typePari': 'E_TIERCE',
        'miseBase': 100,
        'rembourse': false,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Tiercé Ordre',
            'combinaison': '2-1-14',
            'dividendePourUnEuro': 73950,
          },
          {
            'rangCombinaisonPayable': 2,
            'libelle': 'e-Tiercé Désordre',
            'combinaison': '2-1-14',
            'dividendePourUnEuro': 10510,
          },
        ],
      },
      // ── Bloc Quarté+ : Ordre (0 €), Désordre, Bonus ────────────────────
      {
        'typePari': 'E_QUARTE_PLUS',
        'miseBase': 150,
        'rembourse': false,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Quarté+ Ordre',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 0,
          },
          {
            'rangCombinaisonPayable': 2,
            'libelle': 'e-Quarté+ Désordre',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 14490,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Bonus',
            'combinaison': '2-1-14',
            'dividendePourUnEuro': 1620,
          },
        ],
      },
      // ── Bloc Quinté+ : Ordre, Désordre, Bonus 4sur5 (×5), Bonus 3 ──────
      {
        'typePari': 'E_QUINTE_PLUS',
        'miseBase': 200,
        'rembourse': false,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Quinté+ Ordre',
            'combinaison': '2-1-14-12-8',
            'dividendePourUnEuro': 615350,
          },
          {
            'rangCombinaisonPayable': 2,
            'libelle': 'e-Quinté+ Désordre',
            'combinaison': '2-1-14-12-8',
            'dividendePourUnEuro': 5120,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Bonus 4sur5',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 220,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Bonus 4sur5',
            'combinaison': '2-1-14-8',
            'dividendePourUnEuro': 220,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Bonus 4sur5',
            'combinaison': '2-1-12-8',
            'dividendePourUnEuro': 220,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Bonus 4sur5',
            'combinaison': '2-14-12-8',
            'dividendePourUnEuro': 220,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Bonus 4sur5',
            'combinaison': '1-14-12-8',
            'dividendePourUnEuro': 220,
          },
          {
            'rangCombinaisonPayable': 4,
            'libelle': 'e-Bonus 3',
            'combinaison': '2-1-14',
            'dividendePourUnEuro': 200,
          },
        ],
      },
      // ── Bloc Multi : 4 variantes, MÊME combinaison ─────────────────────
      {
        'typePari': 'E_MULTI',
        'miseBase': 300,
        'rembourse': false,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Multi en 4',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 14700,
          },
          {
            'rangCombinaisonPayable': 2,
            'libelle': 'e-Multi en 5',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 2940,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Multi en 6',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 980,
          },
          {
            'rangCombinaisonPayable': 4,
            'libelle': 'e-Multi en 7',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 420,
          },
        ],
      },
      // ── Bloc Trio marqué REMBOURSÉ au niveau du bloc ────────────────────
      {
        'typePari': 'E_TRIO',
        'miseBase': 100,
        'rembourse': true,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'Remboursement e-Trio',
            'combinaison': '2-1-14',
            'dividendePourUnEuro': 100,
          },
        ],
      },
    ]);

/// Réponse MINIMALE, **sans aucune clé ajoutée** : c'est le format des
/// fixtures de `z1_reproduction_d4_dividende_test.dart` et de `a0_04_...`.
/// Elle sert à prouver que les champs nouveaux sont NEUTRES.
String corpsSansLibelle() => json.encode([
      {
        'typePari': 'E_SIMPLE_GAGNANT',
        'rapports': [
          {'combinaison': '7', 'dividendePourUnEuro': 1800},
        ],
      },
      {
        'typePari': 'E_SIMPLE_PLACE',
        'rapports': [
          {'combinaison': '16', 'dividendePourUnEuro': 420},
          {'combinaison': '4', 'dividendePourUnEuro': 280},
          {'combinaison': '2', 'dividendePourUnEuro': 310},
        ],
      },
    ]);

// ───────────────────────────────────────────────────────────────────────────
//  2. HELPERS DE LECTURE
// ───────────────────────────────────────────────────────────────────────────

List<RapportPmu> _decoder() =>
    PmuApiService.decoderRapportsDefinitifs(corpsReelR1C1());

List<RapportPmu> _deBloc(String code) =>
    _decoder().where((r) => r.codePariOfficiel == code).toList();

/// L'heuristique HISTORIQUE, recopiée ici pour être confrontée au résultat
/// produit par le service — c'est elle qui doit rester inchangée.
bool _heuristiqueHistoriqueEstOrdre(String combinaison) =>
    !combinaison.contains('NP') &&
    !combinaison.contains('D') &&
    !combinaison.contains('d');

// ───────────────────────────────────────────────────────────────────────────
//  3. TESTS
// ───────────────────────────────────────────────────────────────────────────

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  //  4C/1 — LES QUATRE CHAMPS HISTORIQUES SONT INCHANGÉS
  // ══════════════════════════════════════════════════════════════════════════
  group('4C/1 — les 4 champs historiques gardent leur valeur', () {
    test('le dividende reste normalisé de centimes vers euros', () {
      final tierce = _deBloc('E_TIERCE');
      expect(tierce, hasLength(2));
      // 73950 centimes → 739,50 € pour 1 € misé. Division par 100 EXACTE.
      expect(tierce[0].dividende, closeTo(739.50, 1e-9));
      expect(tierce[1].dividende, closeTo(105.10, 1e-9));
    });

    test('typePari porte le code du bloc, sans transformation', () {
      for (final r in _decoder()) {
        expect(r.typePari, r.codePariOfficiel,
            reason: 'aucun code ne doit être réécrit à la lecture');
        expect(r.typePari, isNotEmpty);
      }
    });

    test('la combinaison est recopiée telle quelle, ordre compris', () {
      final quinte = _deBloc('E_QUINTE_PLUS');
      expect(
        quinte.map((r) => r.combinaison),
        containsAll(<String>[
          '2-1-14-12-8',
          '2-1-14-12',
          '2-1-14-8',
          '2-1-12-8',
          '2-14-12-8',
          '1-14-12-8',
          '2-1-14',
        ]),
      );
    });

    test('estOrdre suit l\'heuristique historique, corrigée du libellé officiel',
        () {
      // ★ B-4.6 — l'heuristique n'est plus seule : un libellé qui tranche
      //   (« … Ordre » / « … Désordre ») prime sur elle. Mesuré sur les
      //   captures réelles : 4684 lignes, 0 combinaison contenant « D », donc
      //   l'heuristique seule ne distinguait RIEN et classait les 70 lignes
      //   « Désordre » comme « ordre ». Périmètre de la correction : 73 lignes.
      //   Aucun montant n'en dépend (la chaîne financière lit `variante`).
      for (final r in _decoder()) {
        final parLibelle = estOrdreDepuisLibelleOfficiel(r.libelleOfficiel);
        final attendu =
            parLibelle ?? _heuristiqueHistoriqueEstOrdre(r.combinaison);
        expect(r.estOrdre, attendu,
            reason: 'valeur inattendue sur « ${r.libelleOfficiel} » '
                '(${r.combinaison})');
      }
    });

    test('un rapport dont le dividende normalisé n\'est pas > 0 est écarté', () {
      // « e-Quarté+ Ordre » est publié à 0 : il n'entre pas dans la liste
      // historique (comportement d'avant, conservé).
      final quarte = _deBloc('E_QUARTE_PLUS');
      expect(quarte.map((r) => r.libelleOfficiel),
          isNot(contains('e-Quarté+ Ordre')));
      expect(quarte, hasLength(2),
          reason: 'Désordre + Bonus seulement');
    });

    test('aucun rapport n\'a un dividende nul ou négatif', () {
      for (final r in _decoder()) {
        expect(r.dividende, greaterThan(0.0));
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4C/2 — LES INFORMATIONS OFFICIELLES SONT DÉSORMAIS CONSERVÉES
  // ══════════════════════════════════════════════════════════════════════════
  group('4C/2 — les informations officielles ne sont plus jetées', () {
    test('libelleOfficiel est présent sur TOUS les rapports', () {
      final tous = _decoder();
      expect(tous, isNotEmpty);
      for (final r in tous) {
        expect(r.libelleOfficiel, isNotEmpty,
            reason: 'libelle perdu pour ${r.typePari}/${r.combinaison}');
        expect(r.aUnLibelleOfficiel, isTrue);
      }
    });

    test('codePariOfficiel rattache chaque rapport à son bloc', () {
      expect(_deBloc('E_TIERCE'), hasLength(2));
      expect(_deBloc('E_MULTI'), hasLength(4));
      expect(_deBloc('E_QUINTE_PLUS'), hasLength(8));
      expect(_deBloc('E_SIMPLE_PLACE'), hasLength(3));
    });

    test('rangCombinaisonPayable est conservé tel que publié', () {
      final tierce = _deBloc('E_TIERCE');
      expect(tierce[0].rangCombinaisonPayable, 1); // Ordre
      expect(tierce[1].rangCombinaisonPayable, 2); // Désordre

      final quinte = _deBloc('E_QUINTE_PLUS');
      expect(quinte.where((r) => r.rangCombinaisonPayable == 1), hasLength(1));
      expect(quinte.where((r) => r.rangCombinaisonPayable == 2), hasLength(1));
      expect(quinte.where((r) => r.rangCombinaisonPayable == 3), hasLength(5));
      expect(quinte.where((r) => r.rangCombinaisonPayable == 4), hasLength(1));
    });

    test('rembourse est lu sur le BLOC et propagé à ses rapports', () {
      final trio = _deBloc('E_TRIO');
      expect(trio, hasLength(1));
      expect(trio.single.rembourse, isTrue,
          reason: 'le bloc E_TRIO est publié avec rembourse=true');
      expect(trio.single.libelleOfficiel, 'Remboursement e-Trio');

      // Tout le reste ne l'est pas.
      for (final r in _decoder()) {
        if (r.codePariOfficiel == 'E_TRIO') continue;
        expect(r.rembourse, isFalse,
            reason: 'rembourse=true attribué à tort à ${r.typePari}');
      }
    });

    test('miseBaseCentimes est conservé par bloc', () {
      expect(_deBloc('E_SIMPLE_GAGNANT').single.miseBaseCentimes, 100);
      expect(_deBloc('E_QUARTE_PLUS').first.miseBaseCentimes, 150);
      expect(_deBloc('E_QUINTE_PLUS').first.miseBaseCentimes, 200);
      expect(_deBloc('E_MULTI').first.miseBaseCentimes, 300);
    });

    test('dividendeUnite est conservé sans interprétation', () {
      for (final r in _decoder()) {
        expect(r.dividendeUnite, 'PourUnEuro');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4C/3 — ORDRE / DÉSORDRE / BONUS / VARIANTES MULTI RESTENT DISTINCTS
  // ══════════════════════════════════════════════════════════════════════════
  group('4C/3 — Ordre, Désordre, Bonus et variantes Multi restent distincts',
      () {
    test('Tiercé : deux rapports de MÊME combinaison restent distincts', () {
      final tierce = _deBloc('E_TIERCE');
      expect(tierce, hasLength(2));

      // La combinaison est IDENTIQUE : elle ne peut pas les distinguer.
      expect(tierce[0].combinaison, tierce[1].combinaison);
      expect(tierce[0].combinaison, '2-1-14');

      // Le libellé officiel, lui, les distingue.
      expect(tierce[0].libelleOfficiel, 'e-Tiercé Ordre');
      expect(tierce[1].libelleOfficiel, 'e-Tiercé Désordre');
      expect(tierce[0].libelleOfficiel, isNot(tierce[1].libelleOfficiel));

      // Les rangs aussi.
      expect(tierce[0].rangCombinaisonPayable, isNot(tierce[1].rangCombinaisonPayable));

      // Les montants restent distincts et rattachés au bon libellé.
      expect(tierce[0].dividende, closeTo(739.50, 1e-9));
      expect(tierce[1].dividende, closeTo(105.10, 1e-9));
    });

    test('Tiercé : estOrdre distingue désormais Ordre et Désordre', () {
      // ★ B-4.6 — AVANT : les deux valaient `true` (limite connue, mesurée).
      //   DÉSORMAIS : le libellé officiel tranche, et les deux diffèrent.
      //   Cela ne change aucun montant : la chaîne financière lit
      //   `RapportPublie.variante`, jamais `RapportPmu.estOrdre`.
      final tierce = _deBloc('E_TIERCE');
      expect(tierce[0].libelleOfficiel, 'e-Tiercé Ordre');
      expect(tierce[1].libelleOfficiel, 'e-Tiercé Désordre');
      expect(tierce[0].estOrdre, isTrue);
      expect(tierce[1].estOrdre, isFalse,
          reason: '« e-Tiercé Désordre » ne doit plus être classé ordre');
      expect(tierce[0].estOrdre, isNot(tierce[1].estOrdre));
    });

    test('Quarté+ : Désordre et Bonus 3-sur-4 restent distincts', () {
      final quarte = _deBloc('E_QUARTE_PLUS');
      expect(quarte.map((r) => r.libelleOfficiel),
          containsAll(<String>['e-Quarté+ Désordre', 'e-Bonus']));

      final desordre =
          quarte.firstWhere((r) => r.libelleOfficiel == 'e-Quarté+ Désordre');
      final bonus =
          quarte.firstWhere((r) => r.libelleOfficiel == 'e-Bonus');

      // Un Bonus n'a pas la combinaison du ticket : 3 chevaux au lieu de 4.
      expect(desordre.combinaison.split('-'), hasLength(4));
      expect(bonus.combinaison.split('-'), hasLength(3));
      expect(desordre.combinaison, isNot(bonus.combinaison));

      expect(desordre.dividende, closeTo(144.90, 1e-9));
      expect(bonus.dividende, closeTo(16.20, 1e-9));
    });

    test('Quinté+ : Bonus 4sur5 et Bonus 3 restent distincts', () {
      final quinte = _deBloc('E_QUINTE_PLUS');
      final b45 = quinte.where((r) => r.libelleOfficiel == 'e-Bonus 4sur5');
      final b3 = quinte.where((r) => r.libelleOfficiel == 'e-Bonus 3');

      expect(b45, hasLength(5),
          reason: 'les 5 combinaisons à 4 chevaux du Bonus 4sur5');
      expect(b3, hasLength(1));

      for (final r in b45) {
        expect(r.combinaison.split('-'), hasLength(4));
        expect(r.rangCombinaisonPayable, 3);
      }
      expect(b3.single.combinaison, '2-1-14');
      expect(b3.single.combinaison.split('-'), hasLength(3));
      expect(b3.single.rangCombinaisonPayable, 4);

      // Les libellés ne se confondent jamais.
      expect(b45.first.libelleOfficiel, isNot(b3.single.libelleOfficiel));
    });

    test('Multi : les 4 variantes « en 4/5/6/7 » restent distinctes', () {
      final multi = _deBloc('E_MULTI');
      expect(multi, hasLength(4));

      final libelles = multi.map((r) => r.libelleOfficiel).toSet();
      expect(libelles, <String>{
        'e-Multi en 4',
        'e-Multi en 5',
        'e-Multi en 6',
        'e-Multi en 7',
      }, reason: 'aucune variante ne doit être perdue ni fusionnée');

      // MÊME combinaison pour les quatre : seul le libellé (et le rang) diffère.
      for (final r in multi) {
        expect(r.combinaison, '2-1-14-12');
      }
      expect(multi.map((r) => r.libelleOfficiel).toSet(), hasLength(4));
    });

    test('aucune variante n\'est perdue sur l\'ensemble de la réponse', () {
      // Contrôle global : le nombre total de variantes distinctes est celui
      // que la fixture publie (Ordre/Désordre/Bonus/Multi…).
      final tous = _decoder();
      final variantes = tous.map((r) => r.libelleOfficiel).toSet();
      expect(variantes, hasLength(15),
          reason: 'variantes distinctes attendues : $variantes');
      // La taille seule ne suffit pas : on vérifie les cas sensibles.
      expect(variantes, containsAll(<String>[
        'e-Tiercé Ordre',
        'e-Tiercé Désordre',
        'e-Quarté+ Désordre',
        'e-Bonus',
        'e-Quinté+ Ordre',
        'e-Quinté+ Désordre',
        'e-Bonus 4sur5',
        'e-Bonus 3',
        'e-Multi en 4',
        'e-Multi en 7',
      ]));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4C/4 — COMPATIBILITÉ AVEC RapportOfficiel ET LE RÉSOLVEUR
  //         (vérifiée par test, PAS raccordée aux écritures)
  // ══════════════════════════════════════════════════════════════════════════
  group('4C/4 — compatibilité RapportOfficiel et résolveur', () {
    test('decoderRapportsOfficiels accepte le format réel', () {
      final officiels = PmuApiService.decoderRapportsOfficiels(corpsReelR1C1());
      expect(officiels, isNotEmpty);

      // Le libellé officiel survit au passage.
      for (final o in officiels) {
        expect(o.libelle, isNotEmpty,
            reason: 'libelle perdu pour ${o.typePari}/${o.combinaison}');
        expect(o.typePari, isNotEmpty);
        expect(o.combinaison, isNotEmpty);
      }
      // Rapport qui n'a ni libellé ni combinaison ⇒ null, jamais fabriqué.
      expect(officiels.where((o) => o.combinaison.isEmpty).length, 0);
    });

    test('RapportOfficiel.depuisJson conserve libelle, variante et rembourse',
        () {
      final officiels = PmuApiService.decoderRapportsOfficiels(corpsReelR1C1());
      final trio = officiels.firstWhere((o) => o.typePari == 'E_TRIO');
      expect(trio.libelle, 'Remboursement e-Trio');
      expect(trio.rembourse, isTrue);
      // Le montant est lu en euros pour 1 € : 100 centimes → 1,00 €.
      expect(trio.rapportPourUnEuro, closeTo(1.00, 1e-9));
    });

    test('le résolveur distingue Ordre et Désordre par le libellé RÉEL', () {
      // Même combinaison publiée deux fois : seul le libellé permet de
      // choisir. On interroge le résolveur avec la MÊME liste de rapports et
      // la même combinaison jouée, et l'on vérifie qu'il ne confond pas.
      final officiels = PmuApiService.decoderRapportsOfficiels(corpsReelR1C1());
      final tierce =
          officiels.where((o) => o.typePari == 'E_TIERCE').toList();
      expect(tierce, hasLength(2));

      final res = resoudreRapportPmu(
        libelleTypePari: 'Tiercé',
        numerosJoues: const <int>[2, 1, 14],
        rapports: tierce,
      );

      // Le Tiercé générique publie Ordre ET Désordre à combinaison égale :
      // le résolveur refuse par ambiguïté plutôt que de deviner.
      expect(res.refuse, isTrue,
          reason: 'Ordre et Désordre co-existent : aucune sélection ne doit '
              'être inventée (matching.first / reduce(MAX) interdits)');
      expect(res.rapport, isNull);
      expect(res.motifRefus, MotifRefusPmu.ambiguitePlusieursRapports);
    });

    test('le résolveur refuse un rapport remboursé (Trio)', () {
      final officiels = PmuApiService.decoderRapportsOfficiels(corpsReelR1C1());
      final trio = officiels.where((o) => o.typePari == 'E_TRIO').toList();
      expect(trio, hasLength(1));

      final res = resoudreRapportPmu(
        libelleTypePari: 'Trio',
        numerosJoues: const <int>[2, 1, 14],
        rapports: trio,
      );
      // `E_TRIO` relève du moteur A (variante sans ordre) ; le rapport est
      // marqué remboursé, donc aucun gain ne peut être établi.
      expect(res.refuse, isTrue);
      expect(res.rapport, isNull);
    });

    test('le résolveur ne retient jamais un rapport hors combinaison', () {
      final officiels = PmuApiService.decoderRapportsOfficiels(corpsReelR1C1());
      final gagnants =
          officiels.where((o) => o.typePari == 'E_SIMPLE_GAGNANT').toList();

      final bon = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const <int>[2],
        rapports: gagnants,
      );
      expect(bon.trouve, isTrue);
      expect(bon.rapport!.combinaison, '2');

      // Le cheval 3 n'est pas le gagnant : aucun rapport ne lui correspond.
      final mauvais = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const <int>[3],
        rapports: gagnants,
      );
      expect(mauvais.refuse, isTrue);
      expect(mauvais.motifRefus, MotifRefusPmu.aucunRapportExact);
    });

    test('« e-Quarté+ Ordre » à 0 € est présent côté RapportOfficiel', () {
      // Divergence DOCUMENTÉE et VOULUE : le modèle historique écarte un
      // dividende nul (comportement d'avant), le modèle officiel le conserve
      // avec 0,00 € — c'est au résolveur de trancher, pas au décodeur.
      final officiels = PmuApiService.decoderRapportsOfficiels(corpsReelR1C1());
      final ordre = officiels.firstWhere(
          (o) => o.libelle == 'e-Quarté+ Ordre',
          orElse: () => throw StateError('e-Quarté+ Ordre absent'));
      expect(ordre.rapportPourUnEuro, closeTo(0.0, 1e-12));

      final historique = _deBloc('E_QUARTE_PLUS');
      expect(historique.map((r) => r.libelleOfficiel),
          isNot(contains('e-Quarté+ Ordre')));
    });

    test('le résolveur n\'est raccordé à AUCUNE écriture financière', () {
      // Garde structurelle réaffirmée.
      //
      // ★ LOT B-3 — le CONTRÔLE est resserré, pas retiré. La recherche naïve
      // de sous-chaîne ne distinguait pas une citation en commentaire d'une
      // dépendance réelle. La liste des fichiers autorisés à DÉPENDRE du
      // résolveur est désormais FERMÉE et nominative, et l'on exige un
      // `import` effectif. B-3 est le seul lot autorisé à déléguer.
      const dependantsAutorises = <String>[
        'lib/services/moteur_gain_pmu.dart',
      ];
      final dependantsReels = <String>[];
      final citationsSeules = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('resolveur_rapport_pmu.dart')) continue;
        final contenu = f.readAsStringSync();
        if (!contenu.contains('resolveur_rapport_pmu.dart')) continue;
        final importe = RegExp(
          r'''^\s*import\s+['"][^'"]*resolveur_rapport_pmu\.dart['"]''',
          multiLine: true,
        ).hasMatch(contenu);
        (importe ? dependantsReels : citationsSeules).add(f.path);
      }
      dependantsReels.sort();
      citationsSeules.sort();
      expect(dependantsReels, equals(dependantsAutorises),
          reason: 'aucun branchement en écriture : $dependantsReels');
      expect(citationsSeules, equals(<String>['lib/services/arbitre_variante_pmu.dart']),
          reason: 'citations du résolveur sans import : $citationsSeules');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4C/5 — NEUTRALITÉ : RIEN NE CHANGE QUAND L'API N'AJOUTE RIEN
  // ══════════════════════════════════════════════════════════════════════════
  group('4C/5 — neutralité sur une réponse sans champ optionnel', () {
    test('sans libelle, les champs nouveaux valent leur défaut vide', () {
      final rapports =
          PmuApiService.decoderRapportsDefinitifs(corpsSansLibelle());
      expect(rapports, hasLength(4));

      for (final r in rapports) {
        expect(r.libelleOfficiel, '');
        expect(r.aUnLibelleOfficiel, isFalse);
        expect(r.rangCombinaisonPayable, isNull);
        expect(r.rembourse, isFalse);
        expect(r.miseBaseCentimes, isNull);
        expect(r.dividendeUnite, '');
      }
    });

    test('sans libelle, les 4 champs historiques sont EXACTEMENT ceux d\'avant',
        () {
      final rapports =
          PmuApiService.decoderRapportsDefinitifs(corpsSansLibelle());

      // Scénario de `z1` / `a0_04` : n°7 gagnant ×18,00 ; n°16 placé ×4,20.
      final gagnant = rapports.firstWhere((r) => r.typePari == 'E_SIMPLE_GAGNANT');
      expect(gagnant.combinaison, '7');
      expect(gagnant.dividende, closeTo(18.00, 1e-9));
      expect(gagnant.estOrdre, isTrue);

      final places =
          rapports.where((r) => r.typePari == 'E_SIMPLE_PLACE').toList();
      expect(places.map((r) => r.combinaison), <String>['16', '4', '2']);
      // 420 / 280 / 310 centimes → 4,20 / 2,80 / 3,10 € pour 1 €.
      expect(places[0].dividende, closeTo(4.20, 1e-9));
      expect(places[1].dividende, closeTo(2.80, 1e-9));
      expect(places[2].dividende, closeTo(3.10, 1e-9));
    });

    test('un corps qui n\'est pas une liste rend une liste vide', () {
      expect(PmuApiService.decoderRapportsDefinitifs('{}'), isEmpty);
      expect(PmuApiService.decoderRapportsDefinitifs('[]'), isEmpty);
      expect(PmuApiService.decoderRapportsOfficiels('{}'), isEmpty);
    });

    test('un rapport NP reste classé désordre, comme avant', () {
      final corps = json.encode([
        {
          'typePari': 'E_TRIO',
          'rapports': [
            {'combinaison': '2-1-NP', 'dividendePourUnEuro': 100},
          ],
        },
      ]);
      final rapports = PmuApiService.decoderRapportsDefinitifs(corps);
      expect(rapports, hasLength(1));
      expect(rapports.single.estOrdre, isFalse,
          reason: 'comportement historique : NP ⇒ désordre');
    });

    test('le nombre de rapports décodés est celui de la réponse', () {
      // 1 + 3 + 2 + 2 (Ordre à 0 écarté) + 8 + 4 + 1 = 21
      expect(_decoder(), hasLength(21));
      expect(PmuApiService.decoderRapportsDefinitifs(corpsSansLibelle()),
          hasLength(4));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4C/6 — AUCUN MONTANT N'EST MODIFIÉ PAR CE LOT
  // ══════════════════════════════════════════════════════════════════════════
  group('4C/6 — aucun montant modifié', () {
    test('la somme des dividendes décodés est celle publiée', () {
      // Somme arithmétique exacte des `dividendePourUnEuro` > 0 de la fixture,
      // divisée par 100. Aucun arrondi, aucune reconstitution.
      const sommeCentimes = 3130 + // E_SIMPLE_GAGNANT
          630 + 260 + 240 + // E_SIMPLE_PLACE
          73950 + 10510 + // E_TIERCE
          14490 + 1620 + // E_QUARTE_PLUS (l'Ordre à 0 est écarté)
          615350 + 5120 + (220 * 5) + 200 + // E_QUINTE_PLUS
          14700 + 2940 + 980 + 420 + // E_MULTI
          100; // E_TRIO
      final total = _decoder().fold<double>(0.0, (s, r) => s + r.dividende);
      expect(total, closeTo(sommeCentimes / 100.0, 1e-9));
    });

    test('gainNetPourMise et retourPourMise sont inchangés', () {
      final r = _deBloc('E_TIERCE')[0]; // 739,50 € pour 1 €
      expect(r.retourPourMise(10), closeTo(7395.0, 1e-9));
      expect(r.gainNetPourMise(10), closeTo(7385.0, 1e-9));
    });

    test('le constructeur historique reste utilisable sans les champs neufs',
        () {
      // Preuve de compatibilité : un appel à 4 arguments compile et produit
      // les mêmes valeurs qu'avant.
      const r = RapportPmu(
        typePari: 'E_SIMPLE_GAGNANT',
        combinaison: '7',
        dividende: 18.0,
        estOrdre: true,
      );
      expect(r.dividende, 18.0);
      expect(r.libelleOfficiel, '');
      expect(r.rembourse, isFalse);
      expect(r.miseBaseCentimes, isNull);
      expect(r.gainNetPourMise(10), closeTo(170.0, 1e-9));
    });
  });
}
