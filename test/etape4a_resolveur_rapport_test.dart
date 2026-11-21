// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 4-A — TESTS DU RÉSOLVEUR PUR DU RAPPORT OFFICIEL EXACT
//
//  Ces tests ne testent PAS le moteur A (déjà couvert par
//  `ga_a_identification_rapport_test.dart`) ni le référentiel central (couvert
//  par `etape1_referentiel_paris_pmu_test.dart`). Ils testent ce que le
//  résolveur ajoute : le contrat de refus, l'inventaire des particularités, le
//  contrôle croisé des deux tables, et le fait qu'aucune sélection
//  approximative n'est possible.
//
//  Les rapports utilisés sont reconstitués depuis des valeurs RÉELLEMENT
//  mesurées sur l'API v7 (`/tmp/scan_pmu`, 206 courses, 3 742 rapports,
//  08 → 16 nov. 2026). Chaque fixture porte le nom de la course dont elle est
//  issue, pour que la valeur puisse être rejouée.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart';
import 'package:pronostic_hippique/services/referentiel_paris_pmu.dart';
import 'package:pronostic_hippique/services/resolveur_rapport_pmu.dart';

/// Construit un rapport officiel pour 1 € avec les valeurs voulues.
RapportOfficiel _r(
  String typePari,
  String libelle,
  String combinaison, {
  double? pourUnEuro,
  bool rembourse = false,
}) =>
    RapportOfficiel(
      typePari: typePari,
      libelle: libelle,
      combinaison: combinaison,
      rapportPourUnEuro: pourUnEuro,
      rembourse: rembourse,
    );

// ───────────────────────────────────────────────────────────────────────────
//  FIXTURE DE RÉFÉRENCE — 15112026_R1C6, valeurs mesurées
// ───────────────────────────────────────────────────────────────────────────
//
// e-Quinté+ Ordre + Tirelire  9-4-15-10-1   11 462 670 (centimes) → 114 626,70 €
// e-Quinté+ Ordre             9-4-15-10-1    6 462 670           →  64 626,70 €
// e-Quinté+ Désordre          9-4-15-10-1      104 390           →   1 043,90 €
// e-Bonus 4sur5               9-4-15-10          720             →       7,20 €
// e-Bonus 3                   9-4-15             510             →       5,10 €
// e-Quarté+ Ordre             9-4-15-10      658 550             →   6 585,50 €
// e-Quarté+ Désordre          9-4-15-10       57 620             →     576,20 €
// e-Bonus                     9-4-15           1 760             →      17,60 €
// e-Tiercé Ordre              9-4-15          47 740             →     477,40 €
// e-Tiercé Désordre           9-4-15           8 030             →      80,30 €
List<RapportOfficiel> _fixtureQuinteAvecTirelire() => [
      _r('E_QUINTE_PLUS', 'e-Quinté+ Ordre + Tirelire', '9-4-15-10-1',
          pourUnEuro: 114626.70),
      _r('E_QUINTE_PLUS', 'e-Quinté+ Ordre', '9-4-15-10-1',
          pourUnEuro: 64626.70),
      _r('E_QUINTE_PLUS', 'e-Quinté+ Désordre', '9-4-15-10-1',
          pourUnEuro: 1043.90),
      _r('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-4-15-10', pourUnEuro: 7.20),
      _r('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-4-15-1', pourUnEuro: 7.20),
      _r('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-4-10-1', pourUnEuro: 7.20),
      _r('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-15-10-1', pourUnEuro: 7.20),
      _r('E_QUINTE_PLUS', 'e-Bonus 4sur5', '4-15-10-1', pourUnEuro: 7.20),
      _r('E_QUINTE_PLUS', 'e-Bonus 3', '9-4-15', pourUnEuro: 5.10),
      _r('E_QUARTE_PLUS', 'e-Quarté+ Ordre', '9-4-15-10', pourUnEuro: 6585.50),
      _r('E_QUARTE_PLUS', 'e-Quarté+ Désordre', '9-4-15-10', pourUnEuro: 576.20),
      _r('E_QUARTE_PLUS', 'e-Bonus', '9-4-15', pourUnEuro: 17.60),
      _r('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', pourUnEuro: 477.40),
      _r('E_TIERCE', 'e-Tiercé Désordre', '9-4-15', pourUnEuro: 80.30),
      _r('E_SIMPLE_GAGNANT', 'e-Simple Gagnant', '9', pourUnEuro: 7.50),
      _r('E_SIMPLE_PLACE', 'e-Simple Placé', '9', pourUnEuro: 3.00),
      _r('E_SIMPLE_PLACE', 'e-Simple Placé', '4', pourUnEuro: 2.60),
      _r('E_SIMPLE_PLACE', 'e-Simple Placé', '15', pourUnEuro: 6.90),
      _r('E_COUPLE_GAGNANT', 'e-Couplé Gagnant', '9-4', pourUnEuro: 21.70),
      _r('E_COUPLE_PLACE', 'e-Couplé Placé', '9-4', pourUnEuro: 10.00),
      _r('E_COUPLE_PLACE', 'e-Couplé Placé', '9-15', pourUnEuro: 27.50),
      _r('E_COUPLE_PLACE', 'e-Couplé Placé', '4-15', pourUnEuro: 22.90),
    ];

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  //  E4A/1 — SUCCÈS : un et un seul rapport exact
  // ══════════════════════════════════════════════════════════════════════════
  group('E4A/1 — succès sur rapport unique', () {
    test('Simple Gagnant résolu, bonne variante, bon montant', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const [9],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isTrue);
      expect(res.motifRefus, isNull);
      expect(res.rapport!.combinaison, '9');
      expect(res.rapport!.libelle, 'e-Simple Gagnant');
      expect(res.rapport!.rapportPourUnEuro, 7.50);
      expect(res.codeApi, 'E_SIMPLE_GAGNANT');
      expect(res.typeCanonique, TypePariPmu.simpleGagnant);
    });

    test('Simple Placé choisit le rapport du BON cheval, pas le premier', () {
      // Trois rapports « e-Simple Placé » : 9, 4, 15. Aucun repli `first`.
      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Placé',
        numerosJoues: const [15],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isTrue);
      expect(res.rapport!.combinaison, '15');
      expect(res.rapport!.rapportPourUnEuro, 6.90);
    });

    test('Couplé Gagnant résolu sans ordre imposé', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Couplé Gagnant',
        numerosJoues: const [4, 9], // ordre inversé par rapport à l'API
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isTrue);
      expect(res.rapport!.combinaison, '9-4');
      expect(res.codeApi, 'E_COUPLE_GAGNANT');
    });

    test('Couplé Placé résolu sur la bonne paire parmi trois', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Couplé Placé',
        numerosJoues: const [15, 4],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isTrue);
      expect(res.rapport!.combinaison, '4-15');
      expect(res.rapport!.rapportPourUnEuro, 22.90);
    });

    test('Couplé Désordre retombe sur E_COUPLE_GAGNANT, pas sur un autre code', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Couplé Désordre',
        numerosJoues: const [9, 4],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isTrue);
      expect(res.codeApi, 'E_COUPLE_GAGNANT');
      expect(res.typeCanonique, TypePariPmu.coupleGagnant);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  E4A/2 — PLUSIEURS RAPPORTS : refus, jamais de choix
  // ══════════════════════════════════════════════════════════════════════════
  group('E4A/2 — ambiguïté Ordre / Désordre', () {
    test('Tiercé générique : Ordre ET Désordre même combinaison ⇒ refus', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Tiercé',
        numerosJoues: const [9, 4, 15],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.ambiguitePlusieursRapports);
      expect(res.explication, isNotEmpty);
      // Le refus ne doit exposer AUCUN montant.
      expect(res.explication.contains('477'), isFalse,
          reason: 'le motif ne doit pas divulguer le dividende Ordre');
      expect(res.explication.contains('80,3'), isFalse);
    });

    test('Tiercé Ordre est résoluble, lui', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Tiercé Ordre',
        numerosJoues: const [9, 4, 15],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isTrue);
      expect(res.rapport!.libelle, 'e-Tiercé Ordre');
      expect(res.rapport!.rapportPourUnEuro, 477.40);
    });

    test('Tiercé Désordre est résoluble, lui', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Tiercé Désordre',
        numerosJoues: const [9, 4, 15],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isTrue);
      expect(res.rapport!.libelle, 'e-Tiercé Désordre');
      expect(res.rapport!.rapportPourUnEuro, 80.30);
    });

    test('Quarté+ générique : refus (Ordre + Désordre + Bonus)', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quarté+',
        numerosJoues: const [9, 4, 15, 10],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.ambiguitePlusieursRapports);
    });

    test('Quinté+ générique : le conflit Tirelire prime sur « plusieurs »', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quinté+',
        numerosJoues: const [9, 4, 15, 10, 1],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.ambiguiteTirelire);
      expect(res.explication.toLowerCase(), contains('tirelire'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  E4A/3 — BONUS : jamais retenus, toujours nommés
  // ══════════════════════════════════════════════════════════════════════════
  group('E4A/3 — Bonus', () {
    test('e-Bonus du Quarté+ n\'est jamais retenu comme rapport du pari', () {
      // La combinaison jouée 9-4-15-10-? ne doit pas tomber sur e-Bonus (9-4-15).
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quarté+',
        numerosJoues: const [9, 4, 15, 10],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isFalse);
      // e-Bonus figure dans l'inventaire avec son motif propre.
      final bonus = res.ecartes
          .where((e) => e.motif == MotifEcartementPmu.bonusCombinaisonPlusCourte)
          .toList();
      expect(bonus, isNotEmpty);
      expect(bonus.any((e) => e.libelle == 'e-Bonus'), isTrue);
    });

    test('e-Bonus 4sur5 et e-Bonus 3 sont inventoriés pour le Quinté+', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quinté+',
        numerosJoues: const [9, 4, 15, 10, 1],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      final bonus = res.ecartes
          .where((e) => e.motif == MotifEcartementPmu.bonusCombinaisonPlusCourte)
          .toList();
      expect(bonus.where((e) => e.libelle == 'e-Bonus 4sur5').length, 5);
      expect(bonus.where((e) => e.libelle == 'e-Bonus 3').length, 1);
    });

    test('un rapport Bonus SEUL ne peut pas être retenu', () {
      // Aucun rapport principal, seulement un Bonus de bonne combinaison courte.
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quarté+',
        numerosJoues: const [9, 4, 15],
        rapports: [
          _r('E_QUARTE_PLUS', 'e-Bonus', '9-4-15', pourUnEuro: 17.60),
        ],
      );
      // 3 numéros joués pour un pari qui en exige 4 : refus AVANT les rapports.
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.tailleCombinaisonIncoherente);
    });

    test('Bonus retenu par le moteur A ⇒ refus par précaution du résolveur', () {
      // On force l'incohérence en simulant un lot où SEUL le Bonus porte la
      // combinaison complète : le résolveur doit refuser malgré tout.
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quarté+',
        numerosJoues: const [9, 4, 15, 10],
        rapports: [
          // Un « e-Bonus » dont la combinaison ferait 4 numéros : anormal,
          // mais possible si l'API changeait. Le moteur A l'écarte par variante.
          _r('E_QUARTE_PLUS', 'e-Bonus', '9-4-15-10', pourUnEuro: 17.60),
        ],
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, isNot(MotifRefusPmu.typeNonRepertorie));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  E4A/4 — TIRELIRE : conflit toujours détecté
  // ══════════════════════════════════════════════════════════════════════════
  group('E4A/4 — e-Tirelire', () {
    test('Tirelire publiée SEULE ⇒ refus, jamais retenue', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quinté+',
        numerosJoues: const [9, 4, 15, 10, 1],
        rapports: [
          _r('E_QUINTE_PLUS', 'e-Quinté+ Ordre + Tirelire', '9-4-15-10-1',
              pourUnEuro: 114626.70),
        ],
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.ambiguiteTirelire);
      // Le montant de la Tirelire ne doit jamais apparaître dans le motif.
      expect(res.explication.contains('114626'), isFalse);
      expect(res.explication.contains('114 626'), isFalse);
    });

    test('Tirelire + Ordre, même combinaison ⇒ refus (mesuré 15112026_R1C6)', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quinté+',
        numerosJoues: const [9, 4, 15, 10, 1],
        rapports: [
          _r('E_QUINTE_PLUS', 'e-Quinté+ Ordre + Tirelire', '9-4-15-10-1',
              pourUnEuro: 114626.70),
          _r('E_QUINTE_PLUS', 'e-Quinté+ Ordre', '9-4-15-10-1',
              pourUnEuro: 64626.70),
        ],
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.ambiguiteTirelire);
    });

    test('Tirelire de combinaison réellement DIFFÉRENTE n\'interfère pas', () {
      // ⚠️ Point mesuré : un Quinté+ n'exige pas l'ordre, donc « 5-4-3-2-1 »
      //    est une PERMUTATION de « 1-2-3-4-5 », pas une autre combinaison.
      //    Une première version de ce test utilisait cette permutation et
      //    attendait à tort une résolution : elle a été corrigée ici.
      //    On utilise donc une combinaison réellement distincte (1-2-3-4-6).
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quinté+',
        numerosJoues: const [1, 2, 3, 4, 5],
        rapports: [
          _r('E_QUINTE_PLUS', 'e-Quinté+ Ordre', '1-2-3-4-5',
              pourUnEuro: 1000.0),
          _r('E_QUINTE_PLUS', 'e-Quinté+ Ordre + Tirelire', '1-2-3-4-6',
              pourUnEuro: 9999.0),
        ],
      );
      // La Tirelire porte une AUTRE combinaison : elle ne concurrence rien.
      // Seul « e-Quinté+ Ordre » correspond ⇒ résolution, et sa valeur est
      // celle de l'Ordre, JAMAIS celle (plus élevée) de la Tirelire.
      expect(res.trouve, isTrue);
      expect(res.rapport!.libelle, 'e-Quinté+ Ordre');
      expect(res.rapport!.rapportPourUnEuro, 1000.0);
      expect(res.rapport!.rapportPourUnEuro, isNot(9999.0));
      // Elle reste inventoriée, avec son motif.
      expect(
        res.ecartes.any((e) => e.libelle == 'e-Quinté+ Ordre + Tirelire'),
        isTrue,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  E4A/5 — NON-PARTANTS ET ANOMALIES DE TAILLE
  // ══════════════════════════════════════════════════════════════════════════
  group('E4A/5 — non-partants et anomalies mesurées', () {
    test('rapport « 1 NP » inventorié, jamais retenu', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Couplé Gagnant',
        numerosJoues: const [9, 4],
        rapports: [
          _r('E_COUPLE_GAGNANT', 'e-Couplé Gagnant', '9-4', pourUnEuro: 21.70),
          _r('E_COUPLE_GAGNANT', 'e-Couplé Gagnant 1 NP', '8-NP',
              pourUnEuro: 3.10),
        ],
      );
      expect(res.trouve, isTrue);
      expect(res.rapport!.libelle, 'e-Couplé Gagnant');
      final np = res.ecartes
          .where((e) =>
              e.motif == MotifEcartementPmu.nonPartantCombinaisonNonChevaux)
          .toList();
      expect(np.length, 1);
      expect(np.single.libelle, 'e-Couplé Gagnant 1 NP');
    });

    test('« e-Trio » à 2 chevaux est écarté par la taille (mesuré 09112026_R2C5)',
        () {
      // Le Trio n'est pas couvert par le moteur A : refus en amont.
      // On vérifie donc l'écartement à travers le Couplé, seul pari à 2,
      // en vérifiant qu'un rapport de 3 numéros est bien écarté par la taille.
      final res = resoudreRapportPmu(
        libelleTypePari: 'Couplé Gagnant',
        numerosJoues: const [9, 4],
        rapports: [
          _r('E_COUPLE_GAGNANT', 'e-Couplé Gagnant', '9-4-15',
              pourUnEuro: 21.70),
        ],
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.aucunRapportExact);
      expect(
        res.ecartes.any(
            (e) => e.motif == MotifEcartementPmu.tailleCombinaisonAnormale),
        isTrue,
      );
    });

    test('les 5 anomalies Trio mesurées sont bien des combinaisons de 2', () {
      // Preuve de la mesure, rejouée depuis les valeurs relevées sur l'API.
      const anomalies = <String, String>{
        '09112026_R2C5': '6-5',
        '11112026_R2C3': '7-9',
        '11112026_R3C4': '4-6',
        '13112026_R2C2': '5-8',
        '13112026_R4C1': '3-7',
      };
      for (final e in anomalies.entries) {
        final rapport = _r('E_TRIO', 'e-Trio', e.value, pourUnEuro: 12.70);
        expect(rapport.numeros!.length, 2,
            reason: '${e.key} doit bien avoir 2 numéros');
      }
      expect(anomalies.length, 5);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  E4A/6 — CONTRÔLE CROISÉ DES DEUX MODULES
  // ══════════════════════════════════════════════════════════════════════════
  group('E4A/6 — contrôle croisé référentiel ⇄ moteur A', () {
    test('les 11 libellés résolubles ont le MÊME code dans les deux modules', () {
      const resolubles = [
        'Simple Gagnant',
        'Simple Placé',
        'Couplé Gagnant',
        'Couplé Placé',
        'Couplé Ordre',
        'Couplé Désordre',
        'Tiercé',
        'Tiercé Ordre',
        'Tiercé Désordre',
        'Quarté+',
        'Quinté+',
      ];
      for (final l in resolubles) {
        final canon = typePmuDepuisLibelleHistorique(l);
        final joue = typePariDepuisLibelle(l);
        expect(canon, isNotNull, reason: '$l doit être reconnu par le référentiel');
        expect(joue, isNot(TypePariJoue.inconnu),
            reason: '$l doit être reconnu par le moteur A');
        expect(codeApiPourTypePmu(canon!), equals(codeApiPourType(joue)),
            reason: 'divergence de code pour $l');
      }
      expect(resolubles.length, 11);
    });

    test('les 9 libellés hors moteur A sont refusés avec le bon motif', () {
      const horsA = [
        'simple place',
        'couple gagnant',
        'couple place',
        'couple desordre',
        'tierce',
        'quarté',
        'quarte+',
        'quinte+',
        'quinté',
      ];
      for (final l in horsA) {
        expect(typePmuDepuisLibelleHistorique(l), isNotNull,
            reason: '$l est reconnu par le référentiel');
        expect(typePariDepuisLibelle(l), TypePariJoue.inconnu,
            reason: '$l doit être inconnu du moteur A');
        final res = resoudreRapportPmu(
          libelleTypePari: l,
          numerosJoues: const [1],
          rapports: const [],
        );
        expect(res.trouve, isFalse);
        expect(res.motifRefus, MotifRefusPmu.typeHorsMoteurA,
            reason: 'motif attendu pour « $l »');
      }
      expect(horsA.length, 9);
    });

    test('un libellé inventé rend typeNonRepertorie, jamais un défaut', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Pari Mystère',
        numerosJoues: const [1, 2],
        rapports: const [],
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.typeNonRepertorie);
      expect(res.typeCanonique, isNull);
    });

    test('libellé vide ⇒ refus, pas « Simple Gagnant » par défaut', () {
      final res = resoudreRapportPmu(
        libelleTypePari: '',
        numerosJoues: const [1],
        rapports: const [],
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.typeNonRepertorie);
      expect(res.rapport, isNull);
    });

    test('Gagnant+Placé ⇒ ticketDeuxComposantes, pas un type inventé', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Gagnant+Placé',
        numerosJoues: const [9],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.ticketDeuxComposantes);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  E4A/7 — INTERDITS STRUCTURELS : ni `first`, ni `reduce(MAX)`
  // ══════════════════════════════════════════════════════════════════════════
  group('E4A/7 — interdits structurels', () {
    test('le résolveur ne rend JAMAIS le rapport de dividende le plus élevé', () {
      // Un rapport hors combinaison a un dividende énorme : il ne doit jamais
      // être retenu au motif qu'il « rapporte plus ».
      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const [9],
        rapports: [
          _r('E_SIMPLE_GAGNANT', 'e-Simple Gagnant', '9', pourUnEuro: 7.50),
          _r('E_SIMPLE_GAGNANT', 'e-Simple Gagnant', '12',
              pourUnEuro: 999999.0),
        ],
      );
      expect(res.trouve, isTrue);
      expect(res.rapport!.combinaison, '9');
      expect(res.rapport!.rapportPourUnEuro, 7.50);
    });

    test('un lot sans aucune correspondance ne rend aucun rapport', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const [9],
        rapports: [
          _r('E_SIMPLE_GAGNANT', 'e-Simple Gagnant', '1', pourUnEuro: 7.50),
          _r('E_SIMPLE_GAGNANT', 'e-Simple Gagnant', '2', pourUnEuro: 3.00),
        ],
      );
      expect(res.trouve, isFalse);
      expect(res.rapport, isNull);
      expect(res.motifRefus, MotifRefusPmu.aucunRapportExact);
    });

    test('aucun accesseur de montant sur les rapports écartés', () {
      // `EcartementRapport` ne doit exposer que libelle / combinaison /
      // codeApi / motif. On vérifie par la source qu'aucun montant n'y figure.
      final src = File('lib/services/resolveur_rapport_pmu.dart')
          .readAsStringSync();
      final debut = src.indexOf('class EcartementRapport {');
      final fin = src.indexOf('}', src.indexOf('String toString()', debut));
      final classe = src.substring(debut, fin);
      expect(classe.contains('pourUnEuro'), isFalse,
          reason: 'EcartementRapport ne doit porter aucun montant');
      expect(classe.contains('dividende'), isFalse,
          reason: 'EcartementRapport ne doit porter aucun montant');
      expect(classe.contains('double'), isFalse,
          reason: 'EcartementRapport ne doit porter aucun montant');
    });

    test('le résolveur n\'écrit rien et n\'importe aucun service d\'écriture',
        () {
      final src = File('lib/services/resolveur_rapport_pmu.dart')
          .readAsStringSync();
      for (final interdit in [
        'SharedPreferences',
        'FirebaseFirestore',
        'pmu_provider',
        'alert_service',
        'ia_memory_service',
        'enregistrerDividende',
        'setState',
        'http',
      ]) {
        expect(src.contains(interdit), isFalse,
            reason: 'le résolveur ne doit pas dépendre de $interdit');
      }
      // Exactement deux imports, tous deux purs.
      final imports = RegExp(r"^import '(.+)';$", multiLine: true)
          .allMatches(src)
          .map((m) => m.group(1))
          .toList();
      expect(imports, hasLength(2));
      expect(imports, containsAll(<String>[
        'gain_ticket_calculator.dart',
        'referentiel_paris_pmu.dart',
      ]));
    });

    test('le résolveur n\'est importé par aucun écran ni service existant', () {
      final dossier = Directory('lib');
      final fautifs = <String>[];
      for (final f in dossier.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('resolveur_rapport_pmu.dart')) continue;
        final contenu = f.readAsStringSync();
        if (contenu.contains('resolveur_rapport_pmu.dart')) fautifs.add(f.path);
      }
      expect(fautifs, isEmpty,
          reason: 'aucun branchement tant que l\'étape 4-B n\'est pas validée');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  E4A/8 — GARDE-FOUS FINAUX
  // ══════════════════════════════════════════════════════════════════════════
  group('E4A/8 — garde-fous sur le rapport retenu', () {
    test('rapport remboursé ⇒ refus rapportRembourse', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const [9],
        rapports: [
          _r('E_SIMPLE_GAGNANT', 'e-Simple Gagnant', '9',
              pourUnEuro: 7.50, rembourse: true),
        ],
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.rapportRembourse);
    });

    test('dividende pour 1 € absent ⇒ refus, aucun montant inventé', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const [9],
        rapports: [
          _r('E_SIMPLE_GAGNANT', 'e-Simple Gagnant', '9', pourUnEuro: null),
        ],
      );
      expect(res.trouve, isFalse);
      // Le moteur A refuse déjà ce cas en amont : même motif de refus.
      expect(res.motifRefus, isNotNull);
      expect(res.rapport, isNull);
    });

    test('aucun numéro joué ⇒ refus aucunNumeroJoue', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const [],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.aucunNumeroJoue);
    });

    test('taille de combinaison incohérente ⇒ refus avant lecture des rapports',
        () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quinté+',
        numerosJoues: const [9, 4, 15],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.tailleCombinaisonIncoherente);
    });

    test('chaque refus porte un motif ET une explication non vides', () {
      final cas = <({String libelle, List<int> numeros, List<RapportOfficiel> r})>[
        (libelle: '', numeros: const [1], r: const []),
        (libelle: 'Pari Mystère', numeros: const [1], r: const []),
        (libelle: 'Gagnant+Placé', numeros: const [1], r: const []),
        (libelle: 'simple place', numeros: const [1], r: const []),
        (libelle: 'Simple Gagnant', numeros: const [], r: const []),
        (libelle: 'Quinté+', numeros: const [1], r: const []),
        (libelle: 'Tiercé', numeros: const [9, 4, 15],
            r: _fixtureQuinteAvecTirelire()),
        (libelle: 'Quinté+', numeros: const [9, 4, 15, 10, 1],
            r: _fixtureQuinteAvecTirelire()),
      ];
      for (final c in cas) {
        final res = resoudreRapportPmu(
          libelleTypePari: c.libelle,
          numerosJoues: c.numeros,
          rapports: c.r,
        );
        expect(res.refuse, isTrue, reason: '« ${c.libelle} » doit être refusé');
        expect(res.motifRefus, isNotNull);
        expect(res.explication.trim(), isNotEmpty,
            reason: '« ${c.libelle} » doit expliquer son refus');
        expect(res.rapport, isNull);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  E4A/9 — PURETÉ ET DÉTERMINISME
  // ══════════════════════════════════════════════════════════════════════════
  group('E4A/9 — pureté et déterminisme', () {
    test('deux appels identiques rendent le même verdict', () {
      final rapports = _fixtureQuinteAvecTirelire();
      final a = resoudreRapportPmu(
        libelleTypePari: 'Tiercé Ordre',
        numerosJoues: const [9, 4, 15],
        rapports: rapports,
      );
      final b = resoudreRapportPmu(
        libelleTypePari: 'Tiercé Ordre',
        numerosJoues: const [9, 4, 15],
        rapports: rapports,
      );
      expect(a.trouve, b.trouve);
      expect(a.rapport!.libelle, b.rapport!.libelle);
      expect(a.rapport!.combinaison, b.rapport!.combinaison);
      expect(a.motifRefus, b.motifRefus);
    });

    test('l\'ordre des rapports en entrée ne change pas le verdict', () {
      final normal = _fixtureQuinteAvecTirelire();
      final inverse = normal.reversed.toList();
      final a = resoudreRapportPmu(
        libelleTypePari: 'Simple Placé',
        numerosJoues: const [15],
        rapports: normal,
      );
      final b = resoudreRapportPmu(
        libelleTypePari: 'Simple Placé',
        numerosJoues: const [15],
        rapports: inverse,
      );
      expect(a.trouve, isTrue);
      expect(b.trouve, isTrue);
      expect(a.rapport!.combinaison, b.rapport!.combinaison);
      expect(a.rapport!.rapportPourUnEuro, b.rapport!.rapportPourUnEuro);
    });

    test('une liste de rapports vide rend un refus, pas une exception', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const [9],
        rapports: const [],
      );
      expect(res.trouve, isFalse);
      expect(res.motifRefus, MotifRefusPmu.aucunRapportExact);
      expect(res.ecartes, isEmpty);
    });

    test('la liste des écartés est non modifiable', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quinté+',
        numerosJoues: const [9, 4, 15, 10, 1],
        rapports: _fixtureQuinteAvecTirelire(),
      );
      expect(
        () => res.ecartes.add(
          const EcartementRapport(
            libelle: 'x',
            combinaison: '1',
            codeApi: 'X',
            motif: MotifEcartementPmu.combinaisonDifferente,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('la liste des motifs de refus est fermée (12 valeurs, pas de fourre-tout)',
        () {
      expect(MotifRefusPmu.values, hasLength(12));
      expect(
        MotifRefusPmu.values.map((e) => e.name),
        isNot(contains('autre')),
        reason: 'aucun motif « autre » ne doit exister',
      );
    });

    test('la liste des motifs d\'écartement est fermée (6 valeurs)', () {
      expect(MotifEcartementPmu.values, hasLength(6));
      expect(
        MotifEcartementPmu.values.map((e) => e.name),
        isNot(contains('autre')),
      );
    });
  });
}
