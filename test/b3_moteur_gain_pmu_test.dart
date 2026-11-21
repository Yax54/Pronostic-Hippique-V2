// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-3 — TESTS DU MOTEUR PUR DE RÉSOLUTION DES GAINS PMU
//
//  Fixtures : bloc `E_QUINTE_PLUS` réel de R1C6_15112026 (mesuré) —
//      e-Quinté+ Ordre + Tirelire  9-4-15-10-1  pe 11462670 (centimes)
//      e-Quinté+ Ordre             9-4-15-10-1  pe  6462670
//      e-Quinté+ Désordre          9-4-15-10-1  pe   104390
//      e-Bonus 4sur5  ×5 (sous-combinaisons à 4 du top5)  pe 720
//      e-Bonus 3                   9-4-15      pe      510
//  Les valeurs `pourUnEuro` utilisées ici sont en EUROS (après la division
//  par 100 opérée par `RapportOfficiel.depuisJson`) : 114626,70 etc.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/arbitre_variante_pmu.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show
        RapportOfficiel,
        TypePariJoue,
        VarianteRapport,
        typePariDepuisLibelle,
        varianteDepuisLibelle;
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart';
import 'package:pronostic_hippique/services/resolveur_rapport_pmu.dart';

// ───────────────────────────────────────────────────────────────────────────
//  FABRIQUES
// ───────────────────────────────────────────────────────────────────────────

RapportPublie rp(
  String code,
  String libelle,
  String combinaison,
  double pourUnEuro, {
  bool rembourse = false,
}) =>
    RapportPublie(
      codePmu: code,
      libelle: libelle,
      combinaison: combinaison,
      variante: varianteDepuisLibelle(libelle),
      pourUnEuro: pourUnEuro,
      rembourse: rembourse,
    );

/// Bloc Quinté+ réel de R1C6_15112026, converti en euros.
List<RapportPublie> quinteReel() => <RapportPublie>[
      rp('E_QUINTE_PLUS', 'e-Quinté+ Ordre + Tirelire', '9-4-15-10-1', 114626.70),
      rp('E_QUINTE_PLUS', 'e-Quinté+ Ordre', '9-4-15-10-1', 64626.70),
      rp('E_QUINTE_PLUS', 'e-Quinté+ Désordre', '9-4-15-10-1', 1043.90),
      rp('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-4-15-10', 7.20),
      rp('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-4-15-1', 7.20),
      rp('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-4-10-1', 7.20),
      rp('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-15-10-1', 7.20),
      rp('E_QUINTE_PLUS', 'e-Bonus 4sur5', '4-15-10-1', 7.20),
      rp('E_QUINTE_PLUS', 'e-Bonus 3', '9-4-15', 5.10),
    ];

/// Même bloc SANS les deux rapports Tirelire — pour isoler l'Ordre simple.
List<RapportPublie> quinteSansTirelire() => quinteReel()
    .where((r) => r.variante != VarianteRapport.tirelire)
    .toList();

/// Bloc Quarté+ réel de R1C6_15112026, converti en euros.
List<RapportPublie> quarteReel() => <RapportPublie>[
      rp('E_QUARTE_PLUS', 'e-Quarté+ Ordre', '9-4-15-10', 6585.50),
      rp('E_QUARTE_PLUS', 'e-Quarté+ Désordre', '9-4-15-10', 576.20),
      rp('E_QUARTE_PLUS', 'e-Bonus', '9-4-15', 17.60),
    ];

/// Bloc Tiercé réel de R1C6_15112026. Mesuré : AUCUN Bonus.
List<RapportPublie> tierceReel() => <RapportPublie>[
      rp('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 477.40),
      rp('E_TIERCE', 'e-Tiercé Désordre', '9-4-15', 80.30),
    ];

/// Bloc Simple réel de R1C6_15112026.
List<RapportPublie> simpleReel() => <RapportPublie>[
      rp('E_SIMPLE_GAGNANT', 'e-Simple Gagnant', '9', 7.50),
      rp('E_SIMPLE_PLACE', 'e-Simple Placé', '9', 3.00),
      rp('E_SIMPLE_PLACE', 'e-Simple Placé', '4', 2.60),
      rp('E_SIMPLE_PLACE', 'e-Simple Placé', '15', 6.90),
    ];

/// Arrivée officielle singulière : 9-4-15-10-1-7-12.
const List<List<int>> arriveeSinguliere = <List<int>>[
  <int>[9],
  <int>[4],
  <int>[15],
  <int>[10],
  <int>[1],
  <int>[7],
  <int>[12],
];

EtatCourseOfficiel etat(
  List<RapportPublie> rapports, {
  List<List<int>>? groupes,
  bool? definitive = true,
}) =>
    EtatCourseOfficiel(
      arriveeGroupes: groupes,
      arriveeDefinitive: definitive,
      rapports: rapports,
    );

VerdictGain jouer(
  String type,
  List<int> numeros,
  double mise,
  EtatCourseOfficiel e,
) =>
    resoudreGainTicket(
      libelleTypePari: type,
      numerosJoues: numeros,
      mise: MiseEngagee.simple(mise),
      etat: e,
    );

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/1 — TYPES DE PARIS DIFFÉRENTS
  // ═════════════════════════════════════════════════════════════════════════
  group('B3/1 types de paris différents', () {
    test('B3/1.1 Tiercé : un E_TIERCE n\'est jamais assimilé à un Trio', () {
      final v = jouer('Tiercé', const [9, 4, 15], 1, etat(tierceReel(),
              groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.ordre);
      // 1 € × 477,40 = 477,40 €
      expect(v.total, closeTo(477.40, 1e-9));
    });

    test('B3/1.2 Quarté+ exige E_QUARTE_PLUS, pas E_SUPER_QUATRE', () {
      // Seul un E_SUPER_QUATRE est publié : le Quarté+ doit être NON DÉTERMINÉ.
      final etatSuperQuatre = etat(<RapportPublie>[
        rp('E_SUPER_QUATRE', 'e-Super4', '9-4-15-10', 5000.0),
      ], groupes: arriveeSinguliere);
      // On passe par le mode bonusSeulement (ticket ≠ top4) : aucun Bonus non
      // plus → perdu, jamais payé avec un rapport d'un AUTRE pari.
      final v = jouer('Quarté+', const [9, 4, 15, 2], 1, etatSuperQuatre);
      expect(v.estGagne, isFalse,
          reason: 'aucun rapport E_QUARTE_PLUS ne doit être substitué');
      expect(v.total, 0.0);
    });

    test('B3/1.3 Quinté+ exige E_QUINTE_PLUS, pas E_MULTI', () {
      final etatMulti = etat(<RapportPublie>[
        rp('E_MULTI', 'e-Multi en 4', '9-4-15-10', 1491.0),
      ], groupes: arriveeSinguliere);
      final v = jouer('Quinté+', const [9, 4, 15, 10, 1], 2, etatMulti);
      expect(v.estGagne, isFalse);
      expect(v.total, 0.0);
    });

    test('B3/1.4 Simple Gagnant sur cheval 1er', () {
      final v = jouer('Simple Gagnant', const [9], 5, etat(simpleReel(),
              groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.total, closeTo(37.50, 1e-9)); // 5 € × 7,50
    });

    test('B3/1.5 libellé non répertorié ⇒ aucun calcul', () {
      final v = jouer('Trio', const [9, 4, 15], 10, etat(tierceReel(),
              groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.typeNonRepertorie);
      expect(v.total, 0.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/2 — VARIANTES ORDRE / DÉSORDRE
  // ═════════════════════════════════════════════════════════════════════════
  group('B3/2 Ordre et Désordre', () {
    test('B3/2.1 Ordre exact ⇒ rapport Ordre (aucune Tirelire publiée)', () {
      final v = jouer('Quinté+', const [9, 4, 15, 10, 1], 2,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.ordre);
      expect(v.composantes.single.combinaisonRapport, '9-4-15-10-1');
      // 2 € × 64626,70 = 129253,40 €
      expect(v.total, closeTo(129253.40, 1e-6));
    });

    test('B3/2.2 Ordre différent ⇒ rapport Désordre', () {
      final v = jouer('Quinté+', const [4, 9, 15, 10, 1], 2,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.desordre);
      // 2 € × 1043,90 = 2087,80 €
      expect(v.total, closeTo(2087.80, 1e-6));
    });

    test('B3/2.3 Tiercé Ordre puis Désordre, deux rapports distincts', () {
      final o = jouer('Tiercé', const [9, 4, 15], 1,
          etat(tierceReel(), groupes: arriveeSinguliere));
      final d = jouer('Tiercé', const [4, 15, 9], 1,
          etat(tierceReel(), groupes: arriveeSinguliere));
      expect(o.composantes.single.categorie, VarianteRapport.ordre);
      expect(d.composantes.single.categorie, VarianteRapport.desordre);
      expect(o.composantes.single.pourUnEuro,
          isNot(equals(d.composantes.single.pourUnEuro)));
    });

    test('B3/2.4 ticket PERDANT : Tiercé hors du top3', () {
      final v = jouer('Tiercé', const [7, 12, 14], 1,
          etat(tierceReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.perdu);
      expect(v.total, 0.0);
      expect(v.explication, isNotEmpty);
    });

    test('B3/2.5 l\'arrivée décide, PAS le montant : le Désordre est payé même '
        's\'il est BIEN PLUS FAIBLE que l\'Ordre', () {
      // Le Désordre réel (1043,90) est ~62× plus faible que l'Ordre (64626,70).
      // Un moteur qui prendrait « le plus élevé » paierait l'Ordre à tort.
      final v = jouer('Quinté+', const [4, 9, 15, 10, 1], 1,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      expect(v.composantes.single.categorie, VarianteRapport.desordre);
      expect(v.total, closeTo(1043.90, 1e-6));
      expect(v.total, lessThan(64626.70));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/3 — BONUS 4SUR5 ET BONUS 3 (R22)
  // ═════════════════════════════════════════════════════════════════════════
  group('B3/3 Bonus 4sur5 et Bonus 3', () {
    test('B3/3.1 Bonus 4sur5 : 4 du top5 + 1 cheval au-delà du 5e', () {
      // 9-4-15-10 (comb4 publiée) + 7 (hors top5) ⇒ |T ∖ top5| = 1 ≥ 1
      final v = jouer('Quinté+', const [9, 4, 15, 10, 7], 2,
          etat(quinteReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.bonus4sur5);
      // 2 € × 7,20 = 14,40 €
      expect(v.total, closeTo(14.40, 1e-9));
    });

    test('B3/3.2 Bonus 3 : 3 du top3 + 2 chevaux au-delà du 4e', () {
      // 9-4-15 (comb3 publiée) + 7 + 12 ⇒ |T ∖ top4| = 2 ≥ 2
      final v = jouer('Quinté+', const [9, 4, 15, 7, 12], 2,
          etat(quinteReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.bonus3);
      // 2 € × 5,10 = 10,20 €
      expect(v.total, closeTo(10.20, 1e-9));
    });

    test('B3/3.3 GARDE-FOU : le Bonus 3 est BLOQUÉ quand |T ∖ top4| < 2, '
        'même si sa comb3 est incluse', () {
      // Ticket 9-4-15-7-10 : top4 officiel = {9,4,15,10}, donc
      // T ∖ top4 = {7} de cardinalité 1 < 2 ⇒ BONUS 3 INTERDIT.
      // (R22 évalue ③ avant ④ : comme 9-4-15-10 ⊆ T et 7 est hors top5,
      //  le Bonus 4sur5 est éligible et il est servi AVANT le Bonus 3.
      //  C'est la règle validée, et ce test le vérifie explicitement.)
      final v = jouer('Quinté+', const [9, 4, 15, 7, 10], 2,
          etat(quinteReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.bonus4sur5,
          reason: '③ est évalué avant ④ : le 4sur5 est servi en premier');
      expect(v.composantes.single.categorie, isNot(VarianteRapport.bonus3),
          reason: 'le Bonus 3 est bloqué : |T ∖ top4| = 1 < 2');
    });

    test('B3/3.3bis le Bonus 3 est servi quand |T ∖ top4| ≥ 2 ET aucune '
        'comb4 publiée n\'est incluse', () {
      // Ticket 9-4-15-11-14 : aucune comb4 publiée n'est incluse (11 et 14 ne
      // sont dans aucune), mais 9-4-15 ⊆ T et T ∖ top4 = {11,14} (2) ⇒ B3.
      final v = jouer('Quinté+', const [9, 4, 15, 11, 14], 2,
          etat(quinteReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.bonus3);
    });

    test('B3/3.4 un ticket = top5 dans le désordre touche le DÉSORDRE, '
        'jamais un Bonus en plus', () {
      final v = jouer('Quinté+', const [1, 10, 15, 4, 9], 2,
          etat(quinteReel(), groupes: arriveeSinguliere));
      expect(v.composantes.length, 1, reason: 'une seule catégorie');
      expect(v.composantes.single.categorie, VarianteRapport.desordre);
      expect(v.composantes.single.categorie, isNot(VarianteRapport.bonus4sur5));
    });

    test('B3/3.5 Quinté+ PERDU : aucun cheval du top5', () {
      final v = jouer('Quinté+', const [7, 12, 14, 16, 11], 2,
          etat(quinteReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.perdu);
      expect(v.total, 0.0);
    });

    test('B3/3.6 Quarté+ Bonus : comb3 ⊂ T avec un cheval hors du top3', () {
      final v = jouer('Quarté+', const [9, 4, 15, 2], 10,
          etat(quarteReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.bonusQuarte);
      // 10 € × 17,60 = 176 €
      expect(v.total, closeTo(176.0, 1e-9));
    });

    test('B3/3.7 Quarté+ Ordre exact ⇒ Ordre, pas Bonus', () {
      final v = jouer('Quarté+', const [9, 4, 15, 10], 10,
          etat(quarteReel(), groupes: arriveeSinguliere));
      expect(v.composantes.single.categorie, VarianteRapport.ordre);
      expect(v.total, closeTo(65855.0, 1e-6)); // 10 × 6585,50
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/4 — CAS R22 RÉELS (énumération sur le bloc R1C6)
  // ═════════════════════════════════════════════════════════════════════════
  group('B3/4 cas R22 réels', () {
    /// Rejoue la règle R22 explicitement sur chaque ticket, et vérifie que le
    /// moteur rend EXACTEMENT la catégorie attendue par la règle.
    VarianteRapport? attenduR22(List<int> ticket) {
      const top5 = <int>[9, 4, 15, 10, 1];
      final t = ticket.toSet();
      final top5s = top5.toSet();
      final top4s = top5.take(4).toSet();

      if (t.length == 5 && t.containsAll(top5s) && top5s.containsAll(t)) {
        for (var i = 0; i < 5; i++) {
          if (ticket[i] != top5[i]) return VarianteRapport.desordre;
        }
        return VarianteRapport.ordre;
      }
      final comb4 = <List<int>>[
        [9, 4, 15, 10],
        [9, 4, 15, 1],
        [9, 4, 10, 1],
        [9, 15, 10, 1],
        [4, 15, 10, 1],
      ];
      if (t.difference(top5s).isNotEmpty) {
        for (final c in comb4) {
          if (t.containsAll(c)) return VarianteRapport.bonus4sur5;
        }
      }
      if (t.difference(top4s).length >= 2 && t.containsAll(const [9, 4, 15])) {
        return VarianteRapport.bonus3;
      }
      return null; // perdu
    }

    test('B3/4.1 24 tickets réels rendent la catégorie R22 attendue', () {
      final tickets = <List<int>>[
        [9, 4, 15, 10, 1], // ordre
        [4, 9, 15, 10, 1], // désordre
        [1, 10, 15, 4, 9], // désordre
        [9, 4, 15, 10, 7], // bonus 4sur5
        [9, 4, 15, 1, 7], // bonus 4sur5
        [9, 4, 10, 1, 12], // bonus 4sur5
        [9, 15, 10, 1, 14], // bonus 4sur5
        [4, 15, 10, 1, 7], // bonus 4sur5
        [9, 4, 15, 7, 12], // bonus 3
        [9, 4, 15, 11, 14], // bonus 3
        [7, 12, 14, 16, 11], // perdu
        [2, 3, 5, 6, 8], // perdu
        [9, 4, 15, 7, 10], // 4sur5 (voir 3.3)
        [4, 15, 9, 10, 1], // désordre
        [15, 10, 1, 9, 4], // désordre
        [9, 4, 15, 6, 8], // bonus 3
        [9, 4, 15, 10, 3], // 4sur5
        [10, 1, 15, 4, 9], // désordre
        [9, 4, 15, 1, 2], // 4sur5
        [4, 9, 10, 1, 15], // 4sur5
        [9, 4, 15, 5, 6], // bonus 3
        [1, 4, 9, 10, 15], // désordre
        [11, 12, 13, 14, 16], // perdu
        [9, 4, 15, 10, 5], // 4sur5
      ];
      expect(tickets, hasLength(24));

      for (final t in tickets) {
        final attendu = attenduR22(t);
        final v = jouer('Quinté+', t, 1,
            etat(quinteSansTirelire(), groupes: arriveeSinguliere));

        if (attendu == null) {
          expect(v.etat, EtatGain.perdu,
              reason: '${t.join("-")} devrait être perdu');
        } else if (conformeAuReglement(t, attendu)) {
          // Conditions réglementaires ÉTABLIES ⇒ attribution conservée.
          expect(v.etat, EtatGain.attribue,
              reason: '${t.join("-")} devrait gagner (${attendu.name})');
          expect(v.composantes.single.categorie, attendu,
              reason: '${t.join("-")} : catégorie R22');
          expect(v.composantes.length, 1,
              reason: '${t.join("-")} : une seule catégorie, jamais deux');
        } else {
          // ★ LOT B-3 — la règle mesurée rendrait ce ticket payable, mais la
          // combinaison publiée n'est PAS conforme à l'art. 1 c)/d) : on ne
          // tranche pas. Ni gain, ni perte.
          expect(v.etat, EtatGain.nonDetermine,
              reason: '${t.join("-")} : divergence réglementaire ⇒ nonDetermine');
          expect(v.motif, MotifNonDetermination.ambiguiteReglementaireBonus,
              reason: '${t.join("-")} : motif explicite exigé');
          expect(v.total, 0.0,
              reason: '${t.join("-")} : aucun montant ne doit être attribué');
        }
      }
    });

    test('B3/4.2 aucun ticket ne reçoit deux catégories incompatibles', () {
      for (var a = 1; a <= 16; a++) {
        for (var b = a + 1; b <= 16; b++) {
          for (var c = b + 1; c <= 16; c++) {
            final t = [9, a, b, c, 15];
            final v = jouer('Quinté+', t, 1,
                etat(quinteSansTirelire(), groupes: arriveeSinguliere));
            expect(v.composantes.length, lessThanOrEqualTo(1),
                reason: '${t.join("-")} ne doit jamais cumuler');
          }
        }
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/5 — TIRELIRE : LE RAPPORT DÉFINITIF MAJORÉ, JAMAIS SOMMÉ
  //
  //  Règlement en ligne art. 7.1 : « Le ou les rapports bruts communs
  //  "e-Quinté+ Ordre" [...] sont alors AUGMENTÉS du quotient ainsi obtenu,
  //  pour constituer le ou les rapports bruts communs "e-Quinté+ Ordre"
  //  définitifs. » Règlement PDV (ANJ) art. 129 : « sont alors AJOUTÉS au
  //  quotient ainsi obtenu ». Il y a MAJORATION, non substitution.
  //
  //  Conséquence vérifiée ci-dessous : additionner les deux lignes publiées
  //  compterait DEUX FOIS la part « rapport Ordre ». Ce n'est donc pas
  //  « Tirelire au lieu d'Ordre », c'est « deux fois Ordre + Tirelire ».
  // ═════════════════════════════════════════════════════════════════════════
  group('B3/5 Tirelire', () {
    test('B3/5.1 Ordre exact + Tirelire publiée ⇒ refus DÉCLARÉ du résolveur, '
        'ni Ordre simple ni somme', () {
      final v = jouer('Quinté+', const [9, 4, 15, 10, 1], 2,
          etat(quinteReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.tirelireNonDeterminee);
      expect(v.etatTirelire, EtatTirelire.incluse);
      expect(v.total, 0.0);
      // La somme interdite serait 2 × (114626,70 + 64626,70) = 358506,80 €.
      expect(v.total, isNot(closeTo(358506.80, 1e-6)));
      // Le rapport Ordre simple ne doit pas être payé non plus.
      expect(v.total, isNot(closeTo(129253.40, 1e-6)));
      expect(v.explication, contains('art. 7.1'));
    });

    test('B3/5.2 l\'arbitre ISOLE bien la Tirelire et écarte l\'Ordre simple',
        () {
      final a = arbitrerVariante(
        type: typePariDepuisLibelleTest('Quinté+'),
        numerosJoues: const [9, 4, 15, 10, 1],
        etat: etat(quinteReel(), groupes: arriveeSinguliere),
      );
      expect(a.variante, VarianteRapport.tirelire);
      expect(a.etatTirelire, EtatTirelire.incluse);
      expect(a.rapportsCompatibles, hasLength(1));
      expect(a.rapportsCompatibles.single.variante, VarianteRapport.tirelire);
      // L'Ordre simple n'est PAS dans la liste : il est écarté.
      expect(
        a.rapportsCompatibles.any((r) => r.variante == VarianteRapport.ordre),
        isFalse,
      );
    });

    test('B3/5.3 Désordre + Tirelire publiée ⇒ le Désordre N\'EST PAS affecté',
        () {
      final v = jouer('Quinté+', const [4, 9, 15, 10, 1], 2,
          etat(quinteReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.desordre);
      expect(v.etatTirelire, EtatTirelire.sansObjet,
          reason: 'la Tirelire ne concerne que le rang Ordre');
      expect(v.total, closeTo(2087.80, 1e-6));
    });

    test('B3/5.4 sans Tirelire publiée, l\'Ordre simple est payé normalement',
        () {
      final v = jouer('Quinté+', const [9, 4, 15, 10, 1], 2,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.etatTirelire, EtatTirelire.sansObjet);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/6 — GAGNANT + PLACÉ : DEUX COMPOSANTES, DEUX MISES
  // ═════════════════════════════════════════════════════════════════════════
  group('B3/6 Gagnant+Placé', () {
    VerdictGain jouerGP(List<int> numeros, double g, double p) =>
        resoudreGainTicket(
          libelleTypePari: 'Gagnant+Placé',
          numerosJoues: numeros,
          mise: MiseEngagee.gagnantPlace(gagnant: g, place: p),
          etat: etat(simpleReel(), groupes: arriveeSinguliere),
        );

    test('B3/6.1 gagnant + placé gagnants : deux montants distincts', () {
      final v = jouerGP(const [9], 10, 5);
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes, hasLength(2));
      // Gagnant : 10 € × 7,50 = 75 €
      expect(v.gainGagnant, closeTo(75.0, 1e-9));
      // Placé : 5 € × 3,00 = 15 €
      expect(v.gainPlace, closeTo(15.0, 1e-9));
      expect(v.total, closeTo(90.0, 1e-9));
    });

    test('B3/6.2 chaque composante ne porte QUE sa propre mise', () {
      final v = jouerGP(const [9], 10, 5);
      final g = v.composantes
          .firstWhere((c) => c.role == RoleComposante.gagnant);
      final p =
          v.composantes.firstWhere((c) => c.role == RoleComposante.place);
      expect(g.mise, 10.0);
      expect(p.mise, 5.0);
      // Aucune composante ne porte la mise totale (15 €).
      expect(v.composantes.every((c) => c.mise != 15.0), isTrue);
    });

    test('B3/6.3 Gagnant seul (pas de mise Placé) : une seule composante', () {
      final v = jouerGP(const [9], 10, 0);
      expect(v.composantes, hasLength(1));
      expect(v.composantes.single.role, RoleComposante.gagnant);
      expect(v.gainGagnant, closeTo(75.0, 1e-9));
      expect(v.gainPlace, 0.0);
    });

    test('B3/6.4 Placé seul (pas de mise Gagnant) : une seule composante', () {
      final v = jouerGP(const [9], 0, 5);
      expect(v.composantes, hasLength(1));
      expect(v.composantes.single.role, RoleComposante.place);
      expect(v.gainPlace, closeTo(15.0, 1e-9));
      expect(v.gainGagnant, 0.0);
    });

    test('B3/6.5 cheval placé mais PAS gagnant : seule la composante Placé paie',
        () {
      // Le cheval 4 est 2e : Simple Placé existe (2,60), Simple Gagnant non.
      final v = jouerGP(const [4], 10, 5);
      expect(v.composantes, hasLength(1));
      expect(v.composantes.single.role, RoleComposante.place);
      expect(v.gainPlace, closeTo(13.0, 1e-9)); // 5 × 2,60
      expect(v.gainGagnant, 0.0);
    });

    test('B3/6.6 aucun rapport publié pour ce cheval ⇒ NON DÉTERMINÉ, '
        'jamais « perdu » par supposition', () {
      // Le cheval 12 n'a ni « e-Simple Gagnant » ni « e-Simple Placé » publié.
      // L'absence de rapport ne DÉMONTRE pas la perte : elle rend le gain
      // indéterminable. Un « perdu » ici serait une supposition.
      final v = jouerGP(const [12], 10, 5);
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.blocJusteAbsent);
      expect(v.total, 0.0);
      expect(v.gainGagnant, 0.0);
      expect(v.gainPlace, 0.0);
    });

    test('B3/6.7 absence totale de mise sur les deux composantes', () {
      final v = jouerGP(const [9], 0, 0);
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.montantAbsent);
    });

    test('B3/6.8 total = gainGagnant + gainPlace, jamais mise + gain', () {
      final v = jouerGP(const [9], 10, 5);
      expect(v.total, closeTo(v.gainGagnant + v.gainPlace, 1e-9));
      // La mise totale (15 €) ne s'ajoute nulle part.
      expect(v.total, isNot(closeTo(90.0 + 15.0, 1e-9)));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/7 — MISES DE BASE VARIABLES
  // ═════════════════════════════════════════════════════════════════════════
  group('B3/7 mises variables', () {
    test('B3/7.1 le gain est strictement proportionnel à la mise', () {
      final v1 = jouer('Tiercé', const [9, 4, 15], 1,
          etat(tierceReel(), groupes: arriveeSinguliere));
      final v2 = jouer('Tiercé', const [9, 4, 15], 2,
          etat(tierceReel(), groupes: arriveeSinguliere));
      final v15 = jouer('Tiercé', const [9, 4, 15], 1.5,
          etat(tierceReel(), groupes: arriveeSinguliere));
      expect(v2.total, closeTo(v1.total * 2, 1e-9));
      expect(v15.total, closeTo(v1.total * 1.5, 1e-9));
    });

    test('B3/7.2 une mise de 0,01 € reste un montant, pas un zéro', () {
      final v = jouer('Tiercé', const [9, 4, 15], 0.01,
          etat(tierceReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.total, closeTo(4.774, 1e-9));
    });

    test('B3/7.3 mise nulle ⇒ non déterminé, jamais « perdu »', () {
      final v = jouer('Tiercé', const [9, 4, 15], 0,
          etat(tierceReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.montantAbsent);
    });

    test('B3/7.4 mise négative ⇒ non déterminé', () {
      final v = jouer('Tiercé', const [9, 4, 15], -5,
          etat(tierceReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
    });

    test('B3/7.5 une mise de Gagnant/Placé seule ne fonde PAS un pari simple',
        () {
      // Aucun repli sur `miseGagnant` pour un Tiercé : la mise n'a pas été jouée.
      final v = resoudreGainTicket(
        libelleTypePari: 'Tiercé',
        numerosJoues: const [9, 4, 15],
        mise: const MiseEngagee.gagnantPlace(gagnant: 10, place: 5),
        etat: etat(tierceReel(), groupes: arriveeSinguliere),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.montantAbsent);
      expect(v.total, 0.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/8 — RAPPORTS MANQUANTS OU AMBIGUS
  // ═════════════════════════════════════════════════════════════════════════
  group('B3/8 rapports manquants ou ambigus', () {
    test('B3/8.1 aucun rapport du tout ⇒ non déterminé', () {
      final v = jouer('Tiercé', const [9, 4, 15], 1,
          etat(<RapportPublie>[], groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.total, 0.0);
    });

    test('B3/8.2 rapport sans montant exploitable ⇒ non déterminé, '
        'aucune valeur inventée', () {
      final sansMontant = <RapportPublie>[
        const RapportPublie(
          codePmu: 'E_TIERCE',
          libelle: 'e-Tiercé Ordre',
          combinaison: '9-4-15',
          variante: VarianteRapport.ordre,
          pourUnEuro: null,
        ),
      ];
      final v = jouer('Tiercé', const [9, 4, 15], 1,
          etat(sansMontant, groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.montantAbsent);
      expect(v.total, 0.0);
    });

    test('B3/8.3 montant nul ⇒ pas un montant, non déterminé', () {
      final montantNul = <RapportPublie>[
        rp('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 0.0),
      ];
      final v = jouer('Tiercé', const [9, 4, 15], 1,
          etat(montantNul, groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.total, 0.0);
    });

    test('B3/8.4 DEUX rapports Ordre avec des montants différents ⇒ '
        'jamais « le plus élevé »', () {
      final deux = <RapportPublie>[
        rp('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 100.0),
        rp('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 9999.0),
      ];
      final v = jouer('Tiercé', const [9, 4, 15], 1,
          etat(deux, groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.rapportAmbigu);
      expect(v.total, 0.0);
      expect(v.total, isNot(closeTo(9999.0, 1e-9)));
    });

    test('B3/8.5 Bonus 4sur5 absent du bloc ⇒ non déterminé, pas « perdu »', () {
      final sansBonus = quinteSansTirelire()
          .where((r) => r.variante != VarianteRapport.bonus4sur5)
          .toList();
      final v = jouer('Quinté+', const [9, 4, 15, 10, 7], 2,
          etat(sansBonus, groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.blocJusteAbsent);
    });

    test('B3/8.6 divergence arrivée officielle ↔ rapport Ordre ⇒ refus',
        () {
      // L'arrivée dit 9-4-15-10-1, le rapport Ordre publié dit 5-6-7-8-2.
      final divergents = <RapportPublie>[
        rp('E_QUINTE_PLUS', 'e-Quinté+ Ordre', '5-6-7-8-2', 100.0),
        rp('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-4-15-10', 7.20),
      ];
      final v = jouer('Quinté+', const [9, 4, 15, 10, 7], 2,
          etat(divergents, groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.rapportAmbigu);
      expect(v.explication, contains('DIVERGENT'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/9 — ARRIVÉES PROVISOIRES ET EX ÆQUO
  // ═════════════════════════════════════════════════════════════════════════
  group('B3/9 arrivées provisoires et ex æquo', () {
    test('B3/9.1 arrivée provisoire ⇒ non déterminé, aucun gain', () {
      final v = jouer('Quinté+', const [9, 4, 15, 10, 1], 2,
          etat(quinteReel(),
              groupes: arriveeSinguliere, definitive: false));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.arriveeNonDefinitive);
      expect(v.total, 0.0);
    });

    test('B3/9.2 arrivée provisoire : le Tiercé est aussi refusé', () {
      final v = jouer('Tiercé', const [9, 4, 15], 1,
          etat(tierceReel(),
              groupes: arriveeSinguliere, definitive: false));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.arriveeNonDefinitive);
    });

    test('B3/9.3 drapeau définitif ABSENT (null) ⇒ l\'arrivée n\'est pas '
        'tenue pour provisoire', () {
      final v = jouer('Tiercé', const [9, 4, 15], 1,
          etat(tierceReel(), groupes: arriveeSinguliere, definitive: null));
      expect(v.etat, EtatGain.attribue);
    });

    test('B3/9.4 GROUPES ABSENTS ⇒ deadHeatSansGroupes, AUCUNE attribution',
        () {
      final v = jouer('Quinté+', const [9, 4, 15, 10, 1], 2,
          etat(quinteReel(), groupes: null));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.deadHeatSansGroupes);
      expect(v.total, 0.0,
          reason: 'aucun montant ne doit être attribué sans les groupes');
    });

    test('B3/9.5 EX ÆQUO sur un rang COMPARÉ ⇒ refus, aucun ordre inventé', () {
      // R5C5 réelle : [[2],[4],[5,7],[8],[3],[6]] — le rang 3 est ex æquo.
      final v = jouer('Tiercé', const [2, 4, 5], 1,
          etat(tierceReel(), groupes: const <List<int>>[
            <int>[2],
            <int>[4],
            <int>[5, 7],
            <int>[8],
            <int>[3],
            <int>[6],
          ]));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.deadHeatSansGroupes);
      expect(v.explication, contains('EX ÆQUO'));
      expect(v.total, 0.0);
    });

    test('B3/9.6 EX ÆQUO HORS des rangs comparés ⇒ la comparaison reste valide',
        () {
      // R5C5 réelle : [[2],[4],[5,7],[8],[3],[6]] — l'ex æquo est au RANG 3.
      // Un Couplé Gagnant ne compare que les rangs 1 et 2 (tous singletons) :
      // l'ex æquo du rang 3 est HORS du périmètre, la comparaison est valide.
      final v = jouer('Couplé Gagnant', const [2, 4], 5,
          etat(<RapportPublie>[
            rp('E_COUPLE_GAGNANT', 'e-Couplé Gagnant', '2-4', 12.50),
            rp('E_COUPLE_GAGNANT', 'e-Couplé Gagnant', '2-5', 30.00),
          ], groupes: const <List<int>>[
            <int>[2],
            <int>[4],
            <int>[5, 7],
            <int>[8],
            <int>[3],
            <int>[6],
          ]));
      expect(v.etat, EtatGain.attribue,
          reason: 'les rangs comparés (1,2) sont tous des singletons');
      expect(v.total, closeTo(62.50, 1e-9)); // 5 × 12,50
    });

    test('B3/9.7 R6C5 réelle : ex æquo au rang 2, Quinté+ refusé', () {
      final v = jouer('Quinté+', const [12, 1, 9, 2, 10], 2,
          etat(quinteSansTirelire(), groupes: const <List<int>>[
            <int>[12],
            <int>[1, 7],
            <int>[9],
            <int>[2],
            <int>[10],
            <int>[8],
            <int>[6],
            <int>[13],
            <int>[5],
          ]));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.deadHeatSansGroupes);
    });

    test('B3/9.8 arrivée trop courte (< taille comparée) ⇒ refus', () {
      final v = jouer('Quinté+', const [9, 4, 15, 10, 1], 2,
          etat(quinteReel(), groupes: const <List<int>>[
            <int>[9],
            <int>[4],
            <int>[15],
          ]));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.deadHeatSansGroupes);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/10 — DÉLÉGATION AU RÉSOLVEUR EXISTANT
  // ═════════════════════════════════════════════════════════════════════════
  group('B3/10 délégation au résolveur existant', () {
    test('B3/10.1 DÉMONSTRATION : la liste COMPLÈTE est refusée par le '
        'résolveur, la liste RESTREINTE est acceptée', () {
      final tous = <RapportOfficiel>[
        for (final r in tierceReel()) versRapportOfficiel(r),
      ];
      final complet = resoudreRapportPmu(
        libelleTypePari: 'Tiercé',
        numerosJoues: const [9, 4, 15],
        rapports: tous,
      );
      expect(complet.trouve, isFalse,
          reason: 'deux candidats à combinaison égale ⇒ refus');
      expect(complet.motifRefus, MotifRefusPmu.ambiguitePlusieursRapports);

      final restreint = resoudreRapportPmu(
        libelleTypePari: 'Tiercé',
        numerosJoues: const [9, 4, 15],
        rapports: tous
            .where((r) => r.variante == VarianteRapport.ordre)
            .toList(),
      );
      expect(restreint.trouve, isTrue,
          reason: 'la restriction à la variante rend le rapport résolvable');
    });

    test('B3/10.2 cohérence : le rapport payé est EXACTEMENT celui que le '
        'résolveur retient sur la liste restreinte', () {
      final a = arbitrerVariante(
        type: typePariDepuisLibelleTest('Tiercé'),
        numerosJoues: const [9, 4, 15],
        etat: etat(tierceReel(), groupes: arriveeSinguliere),
      );
      final res = resoudreRapportPmu(
        libelleTypePari: 'Tiercé',
        numerosJoues: const [9, 4, 15],
        rapports: a.rapportsCompatibles.map(versRapportOfficiel).toList(),
      );
      final v = jouer('Tiercé', const [9, 4, 15], 1,
          etat(tierceReel(), groupes: arriveeSinguliere));

      expect(res.trouve, isTrue);
      expect(v.composantes.single.libelleRapport, res.rapport!.libelle);
      expect(v.composantes.single.combinaisonRapport,
          res.rapport!.combinaison);
      expect(v.composantes.single.pourUnEuro, res.rapport!.rapportPourUnEuro);
    });

    test('B3/10.3 l\'arbitre ne duplique PAS les contrôles financiers : '
        'il ne lit aucun dividende', () {
      final a = arbitrerVariante(
        type: typePariDepuisLibelleTest('Quinté+'),
        numerosJoues: const [4, 9, 15, 10, 1],
        etat: etat(quinteSansTirelire(), groupes: arriveeSinguliere),
      );
      // La liste restreinte porte les rapports Désordre, quel que soit leur
      // montant — y compris bien plus faible que l'Ordre.
      expect(a.rapportsCompatibles, hasLength(1));
      expect(a.rapportsCompatibles.single.variante, VarianteRapport.desordre);
      expect(a.rapportsCompatibles.single.pourUnEuro,
          closeTo(1043.90, 1e-9));
      // L'arbitre ne rend PAS de montant : son type ne le permet pas.
      expect(a.rapportsCompatibles.single.pourUnEuro, lessThan(64626.70));
    });

    test('B3/10.4 refus du résolveur traduit en motif B-3, jamais forcé', () {
      final a = arbitrerVariante(
        type: typePariDepuisLibelleTest('Tiercé'),
        numerosJoues: const [9, 4, 15],
        etat: etat(tierceReel(), groupes: arriveeSinguliere),
      );
      expect(a.estDeterminee, isTrue);
      // On force un refus en demandant une combinaison absente de la liste
      // restreinte : le résolveur refuse, le moteur ne paye pas.
      final v = jouer('Tiercé', const [9, 4, 15], 1,
          etat(<RapportPublie>[
            rp('E_TIERCE', 'e-Tiercé Désordre', '9-4-15', 80.30),
          ], groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.blocJusteAbsent);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/11 — NON-RÉGRESSION ET INTERDITS STRUCTURELS
  // ═════════════════════════════════════════════════════════════════════════
  group('B3/11 non-régression et interdits', () {
    test('B3/11.1 le moteur ne rend JAMAIS null', () {
      final cas = <List<Object>>[
        ['Tiercé', const [9, 4, 15], 1.0],
        ['', const <int>[], 0.0],
        ['Inconnu', const [1], 5.0],
        ['Quinté+', const [1, 2, 3, 4, 5], 2.0],
      ];
      for (final c in cas) {
        final v = resoudreGainTicket(
          libelleTypePari: c[0] as String,
          numerosJoues: c[1] as List<int>,
          mise: MiseEngagee.simple(c[2] as double),
          etat: etat(tierceReel(), groupes: arriveeSinguliere),
        );
        expect(v, isNotNull);
        expect(v.total, greaterThanOrEqualTo(0.0));
      }
    });

    test('B3/11.2 un gain attribué a TOUJOURS au moins une composante', () {
      expect(
        () => VerdictGain.attribue(composantes: const <ComposanteGain>[]),
        throwsArgumentError,
      );
    });

    test('B3/11.3 non déterminé ⇒ motif FERMÉ obligatoire, jamais un montant',
        () {
      final v = jouer('Quinté+', const [9, 4, 15, 10, 1], 2,
          etat(quinteReel(), groupes: null));
      expect(v.estNonDetermine, isTrue);
      expect(v.motif, isNotNull);
      expect(v.composantes, isEmpty);
      expect(v.total, 0.0);
    });

    test('B3/11.4 perdu ⇒ motif nul et montant nul, mais état EXPLICITE', () {
      final v = jouer('Tiercé', const [7, 12, 14], 1,
          etat(tierceReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.perdu);
      expect(v.motif, isNull);
      expect(v.total, 0.0);
    });

    test('B3/11.5 aucun rapport ne peut être payé si son code ne correspond '
        'pas au pari joué', () {
      // Un E_MULTI bien payant ne doit jamais rémunérer un Quinté+.
      final melange = <RapportPublie>[
        rp('E_MULTI', 'e-Multi en 4', '9-4-15-10', 99999.0),
        ...quinteSansTirelire(),
      ];
      final v = jouer('Quinté+', const [9, 4, 15, 10, 1], 1,
          etat(melange, groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.libelleRapport, isNot(contains('Multi')));
      expect(v.total, closeTo(64626.70, 1e-6));
    });

    test('B3/11.6 sérialisation CompositionGain aller-retour', () {
      final v = jouer('Tiercé', const [9, 4, 15], 2,
          etat(tierceReel(), groupes: arriveeSinguliere));
      final c = v.composantes.single;
      final relu = ComposanteGain.fromJson(c.toJson());
      expect(relu, isNotNull);
      expect(relu!.categorie, c.categorie);
      expect(relu.role, c.role);
      expect(relu.mise, c.mise);
      expect(relu.pourUnEuro, c.pourUnEuro);
      expect(relu.montantRetour, c.montantRetour);
    });

    test('B3/11.7 remboursé ⇒ état remboursé, pas un gain', () {
      final remb = <RapportPublie>[
        rp('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 477.40, rembourse: true),
      ];
      final v = jouer('Tiercé', const [9, 4, 15], 1,
          etat(remb, groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.rembourse);
      expect(v.total, 0.0);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/12 — R22 : PROTECTIONS CONTRE LES FAUX BONUS
  //
  //  Ajouté sur demande expresse (arbitrage) : « Vérifier que les tests
  //  couvrent les cas où une sous-combinaison Bonus est publiée mais où le
  //  ticket ne doit pas recevoir ce Bonus. »
  //
  //  Le risque réel que ces tests verrouillent : le moteur ne doit JAMAIS
  //  servir un Bonus au seul motif qu'une sous-combinaison publiée est
  //  incluse. La cardinalité hors top est un garde-fou décisif, pas un
  //  détail. Chaque cas ci-dessous est nommé et sa réponse est VÉRIFIÉE.
  // ══════════════════════════════════════════════════════════════════════════
  group('B3/12 R22 — aucun faux Bonus', () {
    test('B3/12.1 comb3 INCLUSE mais |T ∖ top4| = 1 ⇒ JAMAIS le Bonus 3', () {
      // top4 = {9,4,15,10}. T = {9,4,15,10,7} : 9-4-15 ⊆ T, mais 7 est le
      // seul cheval hors top4 ⇒ |T ∖ top4| = 1 < 2 ⇒ Bonus 3 INTERDIT.
      // Et comme 9-4-15-10 ⊆ T avec 7 hors top5, c'est le 4sur5 qui paie.
      final v = jouer('Quinté+', const [9, 4, 15, 10, 7], 2,
          etat(quinteReel(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, isNot(VarianteRapport.bonus3),
          reason: 'la présence de la comb3 {9,4,15} ne suffit PAS : '
              'le garde-fou |T ∖ top4| ≥ 2 est décisif');
      expect(v.composantes.single.categorie, VarianteRapport.bonus4sur5);
      // Montant : 2 € × 7,20 € = 14,40 € (et JAMAIS 2 × 5,10 € = 10,20 €).
      expect(v.total, closeTo(14.40, 1e-9));
      expect(v.total, isNot(closeTo(10.20, 1e-9)));
    });

    test('B3/12.2 ticket = top5 dans le désordre : Bonus 4sur5 exclu AUSSI',
        () {
      // T = top5 permuté. Les 5 comb4 publiées sont incluses, et horsTop5 = ∅
      // ⇒ le garde-fou |T ∖ top5| ≥ 1 est FAUX. Un ticket qui a les 5 bons
      // chevaux mal ordonnés touche le DÉSORDRE, pas un Bonus.
      final v = jouer('Quinté+', const [4, 9, 10, 15, 1], 2,
          etat(quinteReel(), groupes: arriveeSinguliere));
      expect(v.composantes.length, 1);
      expect(v.composantes.single.categorie, VarianteRapport.desordre);
      expect(v.composantes.single.categorie, isNot(VarianteRapport.bonus4sur5));
      expect(v.composantes.single.categorie, isNot(VarianteRapport.bonus3));
    });

    test('B3/12.3 un Bonus n\'est JAMAIS doublé avec le Désordre', () {
      // Balayage exhaustif : aucun ticket de 5 numéros ne doit recevoir plus
      // d'une composante. Total de catégories incompatible > 1 = échec.
      for (final a in <int>[1, 7, 12]) {
        for (final b in <int>[2, 8, 14]) {
          final t = <int>[9, 4, 15, a, b];
          if (t.toSet().length != 5) continue;
          final v = jouer('Quinté+', t, 2,
              etat(quinteReel(), groupes: arriveeSinguliere));
          expect(v.composantes.length, lessThanOrEqualTo(1),
              reason: 'ticket $t : plusieurs catégories empilées');
        }
      }
    });

    test('B3/12.4 sans rapport Bonus publié ⇒ nonDetermine, jamais un gain',
        () {
      // Le bloc ne publie AUCUN Bonus : on ne peut pas conclure à une perte,
      // car le règlement prévoit des catégories Bonus. On ne peut pas non
      // plus en inventer une. Le seul état honnête est nonDetermine.
      final sansBonus = quinteReel()
          .where((r) =>
              r.variante != VarianteRapport.bonus4sur5 &&
              r.variante != VarianteRapport.bonus3)
          .toList();
      final v = jouer('Quinté+', const [9, 4, 15, 7, 8], 2,
          etat(sansBonus, groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.blocJusteAbsent);
      expect(v.total, 0.0,
          reason: 'aucun montant ne doit être inventé');
    });

    test('B3/12.5 la règle R22 est MESURÉE, pas réglementaire — écart nommé',
        () {
      // Le règlement (art. 1 c) décrit le Bonus comme « 4 chevaux dans le
      // top 4 + 1 cheval classé au-delà du 5e ». Les 30 combinaisons Bonus
      // publiées dans nos captures sont TOUTES des sous-ensembles du top5,
      // sans un seul contre-exemple. La règle appliquée est donc la règle
      // MESURÉE, et elle est plus restrictive que la lettre du texte.
      //
      // On l'atteste ici : le moteur ne sert un Bonus 4sur5 que si la
      // combinaison publiée est incluse ET qu'un cheval est hors top5.
      // Un ticket dont le 5e cheval est DANS le top5 ne peut donc jamais
      // recevoir de Bonus par cette voie.
      // On utilise le bloc SANS Tirelire : avec la Tirelire publiée, ce ticket
      // emprunte le chemin « + Tirelire » et rend nonDetermine (refus structurel
      // du résolveur, cas arbitré séparément). Le point testé ici est
      // uniquement « Ordre, jamais Bonus ».
      final v = jouer('Quinté+', const [9, 4, 15, 10, 1], 2,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      // T = top5 exact et ordonné ⇒ ORDRE, jamais Bonus.
      expect(v.composantes.single.categorie, VarianteRapport.ordre);
      expect(v.composantes.single.categorie, isNot(VarianteRapport.bonus4sur5));
      expect(v.composantes.single.categorie, isNot(VarianteRapport.bonus3));
    });

    test('B3/12.6 divergence arrivée ↔ rapport Ordre ⇒ nonDetermine', () {
      // Si l'arrivée officielle et le rapport Ordre publié ne donnent pas le
      // même top5, aucune des deux références n'est choisie en silence.
      final divergents = <RapportPublie>[
        rp('E_QUINTE_PLUS', 'e-Quinté+ Ordre', '1-2-3-4-5', 100.0),
        rp('E_QUINTE_PLUS', 'e-Bonus 4sur5', '1-2-3-4', 7.20),
        rp('E_QUINTE_PLUS', 'e-Bonus 3', '1-2-3', 5.10),
      ];
      final v = jouer('Quinté+', const [1, 2, 3, 4, 9], 2,
          etat(divergents, groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.rapportAmbigu);
      expect(v.total, 0.0);
    });
  });
  // ══════════════════════════════════════════════════════════════════════════
  //  GROUPE B3/13 — CONFORMITÉ RÉGLEMENTAIRE DES BONUS (OPTION 3)
  //
  //  DÉCISION UTILISATEUR : « Lorsqu'une combinaison Bonus publiée par l'API
  //  ne satisfait pas les conditions réglementaires étudiées : retourner
  //  nonDetermine ; fournir un motif explicite d'ambiguïté réglementaire ; ne
  //  pas attribuer de montant ; ne pas déclarer le ticket perdant ; ne pas
  //  sélectionner une autre catégorie de gain par défaut. Conserver les
  //  attributions dont les conditions sont établies. »
  //
  //  RAPPEL DE LA MESURE : les combinaisons réellement publiées par l'API
  //  comprennent 4 rotations du top5 qui ne satisfont PAS l'art. 1 c). Un
  //  ticket qui les inclut n'a donc pas de catégorie réglementaire établie.
  // ══════════════════════════════════════════════════════════════════════════
  group('B3/13 conformité réglementaire des Bonus', () {
    test('B3/13.1 ticket 9-4-10-1-7 ⇒ AUCUN Bonus attribué (exigence nommée)',
        () {
      // Rangs : 9→1, 4→2, 10→4, 1→5, 7→6.
      // La comb4 {9,4,10,1} est publiée et incluse, mais elle n'est PAS le
      // top4 {9,4,15,10} : l'art. 1 c) exige 4 chevaux du top4. → nonDetermine.
      final v = jouer('Quinté+', const [9, 4, 10, 1, 7], 2,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.ambiguiteReglementaireBonus);
      expect(v.total, 0.0);
      expect(v.estGagne, isFalse);
      expect(v.etat, isNot(EtatGain.perdu),
          reason: 'la perte ne doit pas être déclarée sur une ambiguïté');
      expect(v.composantes, isEmpty);
    });

    test('B3/13.2 ticket 9-4-15-1-7 ⇒ PAS de Bonus 4sur5 attribué '
        '(exigence nommée)', () {
      // Rangs : 9→1, 4→2, 15→3, 1→5, 7→6.
      // À la lettre de l'art. 1 d), ce ticket est un BONUS 3 (3 du top3 + 2 de
      // rang > 4). Mais l'API ne publie que {9,4,15} comme comb3 et l'ancienne
      // règle servait {9,4,15,1} comme 4sur5. Le moteur ne doit pas trancher.
      final v = jouer('Quinté+', const [9, 4, 15, 1, 7], 2,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.ambiguiteReglementaireBonus);
      expect(v.total, 0.0);
      expect(v.composantes, isEmpty,
          reason: 'aucune catégorie choisie par défaut');
    });

    test('B3/13.3 la combinaison CONFORME au top4 reste attribuée', () {
      final v = jouer('Quinté+', const [9, 4, 15, 10, 6], 2,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.bonus4sur5);
      expect(v.composantes.single.combinaisonRapport, '9-4-15-10');
      expect(v.total, closeTo(14.40, 1e-9));
    });

    test('B3/13.4 la combinaison CONFORME au top3 reste attribuée', () {
      final v = jouer('Quinté+', const [9, 4, 15, 11, 14], 2,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.bonus3);
      expect(v.total, closeTo(10.20, 1e-9));
    });

    test('B3/13.5 Ordre établi ⇒ conservé', () {
      final v = jouer('Quinté+', const [9, 4, 15, 10, 1], 2,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.ordre);
      expect(v.total, closeTo(2 * 64626.70, 1e-9));
    });

    test('B3/13.6 Désordre établi ⇒ conservé', () {
      final v = jouer('Quinté+', const [1, 10, 15, 4, 9], 2,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.desordre);
      expect(v.total, closeTo(2 * 1043.90, 1e-9));
    });

    test('B3/13.7 ÉNUMÉRATION 126 : aucune attribution non conforme', () {
      const champ = <int>[9, 4, 15, 10, 1, 7, 12, 16, 20];
      var n = 0;
      for (var a = 0; a < champ.length; a++) {
        for (var b = a + 1; b < champ.length; b++) {
          for (var c = b + 1; c < champ.length; c++) {
            for (var d = c + 1; d < champ.length; d++) {
              for (var e = d + 1; e < champ.length; e++) {
                final t = [champ[a], champ[b], champ[c], champ[d], champ[e]];
                n++;
                final v = jouer('Quinté+', t, 1,
                    etat(quinteSansTirelire(), groupes: arriveeSinguliere));
                if (v.estGagne) {
                  expect(
                    conformeAuReglement(t, v.composantes.single.categorie),
                    isTrue,
                    reason: '${t.join("-")} : attribué non conforme',
                  );
                }
                if (v.estNonDetermine) {
                  expect(v.motif,
                      MotifNonDetermination.ambiguiteReglementaireBonus,
                      reason: '${t.join("-")} : motif inattendu');
                  expect(v.total, 0.0);
                }
              }
            }
          }
        }
      }
      expect(n, 126, reason: 'C(9,5) = 126 tickets énumérés');
    });

    test('B3/13.8 ÉNUMÉRATION 252 : même invariant sur 10 chevaux', () {
      const champ = <int>[9, 4, 15, 10, 1, 7, 12, 16, 20, 2];
      var n = 0;
      for (var a = 0; a < champ.length; a++) {
        for (var b = a + 1; b < champ.length; b++) {
          for (var c = b + 1; c < champ.length; c++) {
            for (var d = c + 1; d < champ.length; d++) {
              for (var e = d + 1; e < champ.length; e++) {
                final t = [champ[a], champ[b], champ[c], champ[d], champ[e]];
                n++;
                final v = jouer('Quinté+', t, 1,
                    etat(quinteSansTirelire(), groupes: arriveeSinguliere));
                if (v.estGagne) {
                  expect(
                    conformeAuReglement(t, v.composantes.single.categorie),
                    isTrue,
                    reason: '${t.join("-")} : attribué non conforme',
                  );
                }
              }
            }
          }
        }
      }
      expect(n, 252, reason: 'C(10,5) = 252 tickets énumérés');
    });

    test('B3/13.9 le motif est EXPLICITE et nomme les deux références', () {
      final v = jouer('Quinté+', const [9, 4, 10, 1, 7], 2,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      expect(v.explication, contains('art. 1 c)'));
      expect(v.explication, contains('top4'));
      expect(v.explication, contains('Aucune attribution'));
    });

    test('B3/13.10 ce contrôle n\'est PAS une règle réglementaire générale',
        () {
      // Preuve de portée : un ticket réellement perdu (aucune combinaison
      // incluse) reste PERDU, il ne devient pas nonDetermine.
      final v = jouer('Quinté+', const [7, 12, 16, 20, 2], 2,
          etat(quinteSansTirelire(), groupes: arriveeSinguliere));
      expect(v.etat, EtatGain.perdu,
          reason: 'aucune ambiguïté : la perte est établie');
      expect(v.motif, isNull);
    });

    test('B3/13.11 arrivée ex æquo ⇒ nonDetermine, jamais un Bonus', () {
      // Arrivée réelle R5C5 : [[2],[4],[5,7],[8],[3],[6]] — ex æquo au rang 3,
      // donc le top5 n'est pas déterminé sans groupes de rangs.
      final exAequo = <RapportPublie>[
        rp('E_QUINTE_PLUS', 'e-Quinté+ Ordre', '2-4-5-7-8', 1000.0),
        rp('E_QUINTE_PLUS', 'e-Bonus 4sur5', '2-4-5-7', 7.20),
        rp('E_QUINTE_PLUS', 'e-Bonus 3', '2-4-5', 5.10),
      ];
      final v = jouer('Quinté+', const [2, 4, 5, 7, 8], 2,
          etat(exAequo, groupes: const [
            [2], [4], [5, 7], [8], [3], [6]
          ]));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.deadHeatSansGroupes);
      expect(v.total, 0.0);
    });
  });
}

/// Petit utilitaire de test : type depuis libellé, via l'autorité.
TypePariJoue typePariDepuisLibelleTest(String l) =>
    typePariDepuisLibelle(l);

/// ★ LOT B-3 — second oracle, INDÉPENDANT du premier : dit si la combinaison
/// Bonus qui serait servie est CONFORME au règlement e-QUINTÉ+ art. 1 c)/d).
/// Sert à distinguer « gagnant établi » de « ambiguïté réglementaire »
/// (décision utilisateur, option 3).
///
/// Art. 1 c) : Bonus 4sur5 exige 4 chevaux du TOP4 **et** 1 cheval de rang
/// > 5 ⇒ la combinaison publiée doit être exactement [9,4,15,10] (le top4).
/// Art. 1 d) : Bonus 3 exige 3 chevaux du TOP3 **et** 2 chevaux de rang
/// > 4 ⇒ la combinaison publiée doit être exactement [9,4,15] (le top3).
///
/// Ordre et Désordre, eux, sont établis par l'arrivée seule : aucune
/// ambiguïté de Bonus ne peut les affecter.
bool conformeAuReglement(List<int> ticket, VarianteRapport cat) {
  const top5 = <int>[9, 4, 15, 10, 1];
  final t = ticket.toSet();
  final top5s = top5.toSet();
  if (cat == VarianteRapport.bonus4sur5) {
    // La comb4 servie est celle qui est incluse ; elle est conforme
    // seulement si c'est le top4 exact.
    const top4 = <int>[9, 4, 15, 10];
    final servie = <List<int>>[
      [9, 4, 15, 10],
      [9, 4, 15, 1],
      [9, 4, 10, 1],
      [9, 15, 10, 1],
      [4, 15, 10, 1],
    ].firstWhere((c) => t.containsAll(c), orElse: () => const []);
    return servie.toSet().length == 4 &&
        servie.toSet().difference(top4.toSet()).isEmpty;
  }
  if (cat == VarianteRapport.bonus3) {
    const top3 = <int>[9, 4, 15];
    return t.containsAll(top3) && t.difference(top5s).isNotEmpty;
  }
  // Ordre / Désordre : établis par l'arrivée, aucune ambiguïté de Bonus.
  return true;
}
