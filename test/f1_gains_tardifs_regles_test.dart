// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — FONCTIONNEL 1/4 : RÈGLES MÉTIER A/B/C ET CALCUL DES ÉTAPES
// ═══════════════════════════════════════════════════════════════════════════
//
//  Ce fichier prouve les RÈGLES, pures, sans aucune simulation d'entrée/sortie.
//  Il ne prétend PAS démontrer le fonctionnement d'un bouton : c'est l'objet de
//  `f2_gains_tardifs_bout_en_bout_test.dart`.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/gains_tardifs_regles.dart';

void main() {
  group('F1/1 — CAS A : aucun gain manuel', () {
    test('F1/1.1 officiel établi, aucun manuel ⇒ sansGainManuel, AUCUNE notification',
        () {
      final d = deciderGainTardif(gainManuel: null, gainOfficiel: 75.0);
      expect(d.cas, CasGainTardif.sansGainManuel);
      // Exigence littérale : « Aucune notification spécifique de gain tardif ».
      expect(d.notificationRequise, isFalse);
      // Et aucune décision : personne ne « choisit » un rapport officiel.
      expect(d.decisionRequise, isFalse);
      // Mais l'écriture, elle, est requise.
      expect(d.ecritureRequise, isTrue);
    });

    test('F1/1.2 un officiel de 0 € est une PERTE ÉTABLIE, pas une absence', () {
      final d = deciderGainTardif(gainManuel: null, gainOfficiel: 0.0);
      expect(d.cas, CasGainTardif.sansGainManuel);
      expect(d.gainOfficiel, 0.0);
      expect(d.ecritureRequise, isTrue);
    });
  });

  group('F1/2 — CAS B : montants IDENTIQUES au centime', () {
    test('F1/2.1 75.00 vs 75.00 ⇒ identique, notification OUI, décision NON', () {
      final d = deciderGainTardif(gainManuel: 75.0, gainOfficiel: 75.0);
      expect(d.cas, CasGainTardif.identique);
      expect(d.notificationRequise, isTrue);
      // Exigence : « Ne pas demander d\'accepter ou de refuser un montant
      // identique » — donc aucune décision.
      expect(d.decisionRequise, isFalse);
    });

    test('F1/2.2 la comparaison est AU CENTIME : 75.001 vs 75.00 ⇒ identique',
        () {
      final d = deciderGainTardif(gainManuel: 75.001, gainOfficiel: 75.0);
      expect(d.cas, CasGainTardif.identique);
    });

    test('F1/2.3 un centime d\'écart suffit à créer une divergence', () {
      final d = deciderGainTardif(gainManuel: 75.01, gainOfficiel: 75.0);
      expect(d.cas, CasGainTardif.different);
      expect(d.decisionRequise, isTrue);
    });

    test('F1/2.4 dérive flottante de même centime : toujours identique', () {
      // 0.1 + 0.2 = 0.30000000000000004 en IEEE-754.
      final d = deciderGainTardif(gainManuel: 0.1 + 0.2, gainOfficiel: 0.3);
      expect(d.cas, CasGainTardif.identique);
    });
  });

  group('F1/3 — CAS C : montants différents', () {
    test('F1/3.1 20 € manuel vs 75 € officiel ⇒ different + décision requise',
        () {
      final d = deciderGainTardif(gainManuel: 20.0, gainOfficiel: 75.0);
      expect(d.cas, CasGainTardif.different);
      expect(d.notificationRequise, isTrue);
      expect(d.decisionRequise, isTrue);
      // Les deux montants sont conservés pour l'affichage.
      expect(d.gainManuel, 20.0);
      expect(d.gainOfficiel, 75.0);
    });

    test('F1/3.2 un gain manuel de ZÉRO euro EST un gain manuel', () {
      final d = deciderGainTardif(gainManuel: 0.0, gainOfficiel: 12.0);
      // ⚠️ Le cas décisif : `aUnGainManuel` doit être vrai pour 0.0.
      expect(d.aUnGainManuel, isTrue);
      expect(d.cas, CasGainTardif.different);
      expect(d.decisionRequise, isTrue);
    });

    test('F1/3.3 0 € manuel et 0 € officiel ⇒ identique, PAS different', () {
      final d = deciderGainTardif(gainManuel: 0.0, gainOfficiel: 0.0);
      expect(d.cas, CasGainTardif.identique);
      expect(d.aUnGainManuel, isTrue);
    });
  });

  group('F1/4 — Aucun gain officiel : rien n\'est fabriqué', () {
    test('F1/4.1 officiel null, manuel présent ⇒ aucun, rien à faire', () {
      final d = deciderGainTardif(gainManuel: 20.0, gainOfficiel: null);
      expect(d.cas, CasGainTardif.aucun);
      expect(d.ecritureRequise, isFalse);
      expect(d.notificationRequise, isFalse);
      expect(d.decisionRequise, isFalse);
    });

    test('F1/4.2 un remboursement n\'est PAS un gain : il ne fonde aucune comparaison',
        () {
      // La règle ne reçoit QUE le gain officiel. Un remboursement seul laisse
      // `gainOfficiel` à null ⇒ cas `aucun`. C'est la garantie qu'un
      // remboursement ne peut pas fabriquer une divergence de gain.
      final d = deciderGainTardif(gainManuel: 20.0, gainOfficiel: null);
      expect(d.cas, CasGainTardif.aucun);
    });

    test('F1/4.3 null n\'est jamais assimilé à 0.0', () {
      final absent = deciderGainTardif(gainManuel: null, gainOfficiel: null);
      final zero = deciderGainTardif(gainManuel: null, gainOfficiel: 0.0);
      expect(absent.cas, CasGainTardif.aucun);
      expect(zero.cas, CasGainTardif.sansGainManuel);
      expect(absent.cas, isNot(zero.cas));
    });
  });

  group('F1/5 — DÉFAUT CORRIGÉ : les étapes sont DISSOCIÉES', () {
    test('F1/5.1 écriture faite + notification manquante ⇒ notification seule', () {
      // C'EST LE DÉFAUT DE `dcb4b49` : ce cas était inexprimable, donc la
      // notification disparaissait définitivement.
      final e = resteAFaire(
        resultatOfficielPersiste: true,
        ecritureDejaConfirmee: true,
        notificationDejaEmise: false,
        decisionEnregistree: false,
        decisionRequiseParLaRegle: true,
      );
      expect(e.ecriture, isFalse, reason: 'aucune réécriture inutile');
      expect(e.notification, isTrue, reason: 'la notification manque');
      expect(e.decision, isTrue, reason: 'la décision reste à proposer');
      expect(e.notificationSeule, isTrue);
    });

    test('F1/5.2 l\'inverse : notification émise mais écriture non confirmée', () {
      final e = resteAFaire(
        resultatOfficielPersiste: false,
        ecritureDejaConfirmee: false,
        notificationDejaEmise: true,
        decisionEnregistree: false,
        decisionRequiseParLaRegle: true,
      );
      expect(e.ecriture, isTrue);
      expect(e.notification, isFalse, reason: 'jamais de doublon');
      expect(e.decision, isTrue);
    });

    test('F1/5.3 tout est fait ⇒ plus rien à faire', () {
      final e = resteAFaire(
        resultatOfficielPersiste: true,
        ecritureDejaConfirmee: true,
        notificationDejaEmise: true,
        decisionEnregistree: true,
        decisionRequiseParLaRegle: true,
      );
      expect(e.quelqueChoseAFaire, isFalse);
    });

    test('F1/5.4 CAS A (aucune notification requise) ⇒ jamais de notification', () {
      final e = resteAFaire(
        resultatOfficielPersiste: true,
        ecritureDejaConfirmee: true,
        notificationDejaEmise: false,
        decisionEnregistree: false,
        decisionRequiseParLaRegle: false,
      );
      expect(e.notification, isFalse);
      expect(e.decision, isFalse);
      expect(e.quelqueChoseAFaire, isFalse);
    });

    test('F1/5.5 les trois familles de marqueurs ont des PRÉFIXES DISTINCTS', () {
      const id = 'ticket_42';
      final e = cleIdempotenceEcriture(id);
      final n = cleIdempotenceNotification(id);
      final d = cleIdempotenceDecision(id);
      expect(e, 'ge1:$id');
      expect(n, 'gt1:$id');
      expect(d, 'gd1:$id');
      // Aucun préfixe n'est préfixe d'un autre : aucune collision possible.
      expect({e, n, d}.length, 3);
    });
  });
}
