// ═══════════════════════════════════════════════════════════════════════════
//  SOUS-LOT B — TESTS CIBLÉS : MISES, RETOUR BRUT, BÉNÉFICE NET
//
//  Ce fichier vérifie l'arithmétique PURE du sous-lot B, sans UI ni I/O.
//  Convention de référence (mandat §2 et §4-B) :
//    « 10 € saisis en Gagnant+Placé = 10 € Gagnant + 10 € Placé = 20 €
//      engagés ». La mise saisie n'est JAMAIS divisée par deux.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/gain_mise_calculator.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // 1. MISE TOTALE = SOMME RÉELLE DES COMPOSANTES
  // ─────────────────────────────────────────────────────────────────────────
  group('B/1 — mise totale engagée', () {
    test('Gagnant+Placé à 10 €/composante engage 20 €, jamais 10 €', () {
      final comp = composantesDepuisTicket(
        estGagnantPlace: true,
        miseEngagee: 10.0,
        miseGagnant: 10.0,
        misePlace: 10.0,
        rapport: null,
      );
      expect(comp.length, 2);
      expect(miseTotaleEngagee(comp), closeTo(20.0, 0.0001));
      // Preuve du défaut évité : `miseEngagee` seul vaut 10 €.
      expect(miseTotaleEngagee(comp), isNot(closeTo(10.0, 0.0001)));
    });

    test('Gagnant+Placé à 5 € Gagnant / 15 € Placé engage 20 €', () {
      final comp = composantesDepuisTicket(
        estGagnantPlace: true,
        miseEngagee: null,
        miseGagnant: 5.0,
        misePlace: 15.0,
        rapport: null,
      );
      expect(miseTotaleEngagee(comp), closeTo(20.0, 0.0001));
    });

    test('Simple Gagnant à 10 € engage 10 €', () {
      final comp = composantesDepuisTicket(
        estGagnantPlace: false,
        miseEngagee: 10.0,
        miseGagnant: null,
        misePlace: null,
        rapport: 4.73,
      );
      expect(comp.length, 1);
      expect(miseTotaleEngagee(comp), closeTo(10.0, 0.0001));
    });

    test('Gagnant+Placé avec une seule mise ⇒ total INCONNU (pas 10 €)', () {
      final comp = composantesDepuisTicket(
        estGagnantPlace: true,
        miseEngagee: 10.0,
        miseGagnant: 10.0,
        misePlace: null, // composante non renseignée
        rapport: null,
      );
      expect(comp.length, 2);
      expect(miseTotaleEngagee(comp), isNull);
    });

    test('aucune mise ⇒ total null', () {
      final comp = composantesDepuisTicket(
        estGagnantPlace: false,
        miseEngagee: null,
        miseGagnant: null,
        misePlace: null,
        rapport: 4.73,
      );
      expect(miseTotaleEngagee(comp), isNull);
    });

    test('mise à 0 € ⇒ traitée comme non renseignée', () {
      const c = ComposanteMise(mise: 0.0, rapport: 4.73);
      expect(c.complete, isFalse);
      expect(c.retourBrut, isNull);
    });

    test('liste vide ⇒ total null', () {
      expect(miseTotaleEngagee(const []), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. RETOUR BRUT ≠ BÉNÉFICE NET
  // ─────────────────────────────────────────────────────────────────────────
  group('B/2 — retour brut et bénéfice net restent distincts', () {
    test('Simple Gagnant 10 € à ×4.73 : brut 47.30, net 37.30', () {
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: 10.0, rapport: 4.73),
      ]);
      expect(r.calculable, isTrue);
      expect(r.miseTotale, closeTo(10.0, 0.0001));
      expect(r.retourBrut, closeTo(47.30, 0.0001));
      expect(r.beneficeNet, closeTo(37.30, 0.0001));
      // Le brut n'est pas le net : c'est le piège à ne pas confondre.
      expect(r.retourBrut, isNot(closeTo(r.beneficeNet!, 0.0001)));
    });

    test('rapport ×1.00 : brut = mise, net = 0 (pas une perte)', () {
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: 10.0, rapport: 1.0),
      ]);
      expect(r.retourBrut, closeTo(10.0, 0.0001));
      expect(r.beneficeNet, closeTo(0.0, 0.0001));
    });

    test('rapport inférieur à 1 : net négatif (perte réelle)', () {
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: 10.0, rapport: 0.5),
      ]);
      expect(r.retourBrut, closeTo(5.0, 0.0001));
      expect(r.beneficeNet, closeTo(-5.0, 0.0001));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. GAGNANT + PLACÉ : trois scénarios réels exigés par le mandat
  //    (gagnant / seulement placé / perdant)
  // ─────────────────────────────────────────────────────────────────────────
  group('B/3 — Gagnant+Placé : gagnant, seulement placé, perdant', () {
    test('le cheval GAGNE : les DEUX composantes sont payées', () {
      // 10 € Gagnant à ×4.73 = 47.30 ; 10 € Placé à ×1.40 = 14.00
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: 10.0, rapport: 4.73),
        const ComposanteMise(mise: 10.0, rapport: 1.40),
      ]);
      expect(r.miseTotale, closeTo(20.0, 0.0001));
      expect(r.retourBrut, closeTo(61.30, 0.0001)); // 47.30 + 14.00
      expect(r.beneficeNet, closeTo(41.30, 0.0001)); // 61.30 − 20.00
    });

    test('le cheval est SEULEMENT PLACÉ : composante Gagnant non payée', () {
      // Le rapport Gagnant n'existe pas pour ce cheval ⇒ null, donc le
      // résultat global n'est pas calculable : on ne peut pas affirmer un
      // montant sans savoir si la composante Gagnant rapporte 0.
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: 10.0, rapport: null),
        const ComposanteMise(mise: 10.0, rapport: 1.40),
      ]);
      expect(r.calculable, isFalse);
      expect(r.retourBrut, isNull);
      // La mise totale reste connue : 20 € engagés, même sans rapport.
      expect(r.miseTotale, closeTo(20.0, 0.0001));
      expect(r.motif, contains('En attente du rapport officiel'));
    });

    test('le cheval PERD : aucun rapport ⇒ non calculable, mise 20 € connue', () {
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: 10.0, rapport: null),
        const ComposanteMise(mise: 10.0, rapport: null),
      ]);
      expect(r.calculable, isFalse);
      expect(r.beneficeNet, isNull);
      expect(r.miseTotale, closeTo(20.0, 0.0001));
    });

    test('la mise totale de G+P ne dépend jamais du rapport', () {
      final scenarios = <List<double?>>[
        [4.73, 1.40],
        [null, 1.40],
        [null, null],
      ];
      for (final rapports in scenarios) {
        final r = calculerGain(composantes: [
          ComposanteMise(mise: 10.0, rapport: rapports[0]),
          ComposanteMise(mise: 10.0, rapport: rapports[1]),
        ]);
        expect(r.miseTotale, closeTo(20.0, 0.0001),
            reason: 'rapports $rapports');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. AUCUN MULTIPLICATEUR FICTIF
  // ─────────────────────────────────────────────────────────────────────────
  group('B/4 — aucun repli fictif (×2, ×2.5, ×3)', () {
    test('rapport absent ⇒ PAS de ×2 : non calculable', () {
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: 10.0, rapport: null),
      ]);
      expect(r.calculable, isFalse);
      expect(r.retourBrut, isNull);
      // La valeur ×2 fautive aurait donné 20 €.
      expect(r.retourBrut, isNot(closeTo(20.0, 0.0001)));
    });

    test('rapport absent ⇒ PAS de ×2.5 : non calculable', () {
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: 10.0, rapport: null),
      ]);
      expect(r.retourBrut, isNot(closeTo(25.0, 0.0001)));
    });

    test('rapport absent ⇒ PAS de ×3 : non calculable', () {
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: 10.0, rapport: null),
      ]);
      expect(r.retourBrut, isNot(closeTo(30.0, 0.0001)));
    });

    test('mise par défaut 10 € jamais inventée', () {
      // Une mise absente ne devient jamais 10 € : le calcul s'arrête.
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: null, rapport: 4.73),
      ]);
      expect(r.calculable, isFalse);
      expect(r.miseTotale, isNull);
      expect(r.motif, contains('Mises non renseignées'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 5. DISTINCTION DES DEUX MOTIFS D'ÉCHEC
  // ─────────────────────────────────────────────────────────────────────────
  group('B/5 — motifs d\'échec distingués', () {
    test('mise inconnue ⇒ motif « Mises non renseignées »', () {
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: null, rapport: null),
      ]);
      expect(r.motif, contains('Mises non renseignées'));
    });

    test('mise connue mais rapport inconnu ⇒ « En attente du rapport officiel »',
        () {
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: 10.0, rapport: null),
      ]);
      expect(r.motif, contains('En attente du rapport officiel'));
      expect(r.motif, isNot(contains('Mises non renseignées')));
    });

    test('aucune composante ⇒ motif explicite', () {
      final r = calculerGain(composantes: const []);
      expect(r.calculable, isFalse);
      expect(r.motif, isNotEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 6. COHÉRENCE AVEC LES VALEURS RÉELLES MESURÉES
  // ─────────────────────────────────────────────────────────────────────────
  group('B/6 — cohérence avec les rapports réels mesurés', () {
    test('Tiercé Ordre 2 € à ×4735.20 : brut 9470.40, net 9468.40', () {
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: 2.0, rapport: 4735.20),
      ]);
      expect(r.retourBrut, closeTo(9470.40, 0.01));
      expect(r.beneficeNet, closeTo(9468.40, 0.01));
    });

    test('Tiercé Désordre 2 € à ×614.80 : brut 1229.60, net 1227.60', () {
      final r = calculerGain(composantes: [
        const ComposanteMise(mise: 2.0, rapport: 614.80),
      ]);
      expect(r.retourBrut, closeTo(1229.60, 0.01));
      expect(r.beneficeNet, closeTo(1227.60, 0.01));
    });

    test('le même ticket Ordre vs Désordre ne donne JAMAIS le même montant', () {
      final ordre = calculerGain(composantes: [
        const ComposanteMise(mise: 2.0, rapport: 4735.20),
      ]);
      final desordre = calculerGain(composantes: [
        const ComposanteMise(mise: 2.0, rapport: 614.80),
      ]);
      expect(ordre.retourBrut, isNot(closeTo(desordre.retourBrut!, 0.01)));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 7. GAIN POTENTIEL : ce n'est pas un gain gagné
  // ─────────────────────────────────────────────────────────────────────────
  group('B/7 — gain potentiel', () {
    test('calculable AVANT la course à partir d\'une cote', () {
      final r = calculerGainPotentiel(composantes: [
        const ComposanteMise(mise: 10.0, rapport: 3.20), // cote de référence
      ]);
      expect(r.calculable, isTrue);
      expect(r.retourBrut, closeTo(32.0, 0.0001));
      expect(r.beneficeNet, closeTo(22.0, 0.0001));
    });

    test('un gain potentiel non calculable ne produit AUCUN montant', () {
      final r = calculerGainPotentiel(composantes: [
        const ComposanteMise(mise: 10.0, rapport: null),
      ]);
      expect(r.calculable, isFalse);
      expect(r.retourBrut, isNull);
      expect(r.beneficeNet, isNull);
    });
  });
}
