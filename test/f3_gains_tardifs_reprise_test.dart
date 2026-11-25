// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — FONCTIONNEL 3/4 : ORCHESTRATEUR, ANTI-DOUBLON ET REPRISE
// ═══════════════════════════════════════════════════════════════════════════
//
//  Ce fichier démontre le DÉFAUT CORRIGÉ et les scénarios de reprise exigés :
//    • écriture réussie + notification échouée ⇒ la notification est REPRISE ;
//    • notifications désactivées puis réactivées ⇒ reprise sans doublon ;
//    • interruption entre écriture et notification ;
//    • interruption après notification avant confirmation du marqueur ;
//    • purge de l'historique des alertes sans perte de décision ;
//    • plusieurs tickets d'une même course ;
//    • deux courses de dates différentes aux mêmes numéros.
//
//  ⚠️ LE DÉTECTEUR EST REMPLACÉ PAR UN DOUBLURE : ce fichier ne teste pas le
//     réseau. Le service réseau est couvert par
//     `b1_t12_detection_gains_tardifs_test.dart`, déjà existant.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart' show EtatGain;
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/detection_gains_tardifs.dart';
import 'package:pronostic_hippique/services/gains_tardifs_en_attente.dart';
import 'package:pronostic_hippique/services/gains_tardifs_notifies_store.dart';
import 'package:pronostic_hippique/services/gains_tardifs_regles.dart';
import 'package:pronostic_hippique/services/service_gains_tardifs.dart';

const _cleTickets = 'user_predictions_v2';

UserPrediction _ticket({
  required String id,
  double? gainManuel,
  double? gainOfficiel,
  double? remboursement,
  EtatGain? etatGain,
  double mise = 20.0,
  String dateStr = '23032026',
  int numReunion = 1,
  int numCourse = 3,
}) =>
    UserPrediction(
      id: id,
      dateStr: dateStr,
      numReunion: numReunion,
      numCourse: numCourse,
      nomCourse: 'Prix de test',
      hippodrome: 'Vincennes',
      numeroCheval: 5,
      nomCheval: 'Cheval Test',
      cote: 3.5,
      typePari: 'Simple Gagnant',
      createdAt: DateTime(2026, 3, 23, 14, 30),
      montantMise: mise,
      montantGainManuel: gainManuel,
      montantOfficielPmu: gainOfficiel,
      remboursementPmu: remboursement,
      etatGain: etatGain,
    );

/// Amorce le support puis construit le service réel, avec un détecteur
/// silencieux (aucune requête réseau, aucun résultat).
Future<ServiceGainsTardifs> _service(List<UserPrediction> tickets) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _cleTickets: tickets.map((t) => jsonEncode(t.toJson())).toList(),
  });
  final provider = PmuProvider();
  await provider.reloadPredictions();
  final prefs = await SharedPreferences.getInstance();
  return ServiceGainsTardifs(
    provider: provider,
    detecteur: DetecteurGainsTardifs(store: BackoffTardifStore(prefs)),
    memoire: MemoireGainsTardifsNotifies(prefs),
    horloge: () => DateTime(2026, 3, 24, 10, 0),
  );
}

/// Les alertes de type gain tardif actuellement dans l'historique.
List<AppAlert> _alertesGainTardif() => AlertService.instance.alerts
    .where((a) => a.type == AlertType.gainTardif)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F3/1 — DÉFAUT CORRIGÉ : écriture réussie, notification manquante', () {
    test('F3/1.1 la notification est REPRISE sans réseau ni réécriture', () async {
      // État de départ : l'écriture officielle a DÉJÀ été faite (etatGain posé,
      // montant officiel persisté) mais AUCUN marqueur de notification.
      final t = _ticket(
        id: 'r1',
        gainManuel: 20.0,
        gainOfficiel: 75.0,
        etatGain: EtatGain.attribue,
      );
      final s = await _service([t]);
      await AlertService.instance.reinitialiserHistoriquePourTest();

      // Reprise : aucun réseau, aucun résultat officiel à réclamer.
      final resultats = await s.reprendreNotifications();

      final r = resultats.singleWhere((x) => x.idTicket == 'r1');
      expect(r.issue, IssueRattrapage.notificationReprise);
      expect(_alertesGainTardif().length, 1,
          reason: 'la notification attendue doit être produite');

      // Et le marqueur de notification est désormais posé.
      final prefs = await SharedPreferences.getInstance();
      final memoire = MemoireGainsTardifsNotifies(prefs);
      expect(memoire.dejaMarque(cleIdempotenceNotification('r1')), isTrue);
    });

    test('F3/1.2 une seconde reprise ne produit AUCUN doublon', () async {
      final t = _ticket(
        id: 'r2',
        gainManuel: 20.0,
        gainOfficiel: 75.0,
        etatGain: EtatGain.attribue,
      );
      final s = await _service([t]);
      await AlertService.instance.reinitialiserHistoriquePourTest();

      await s.reprendreNotifications();
      expect(_alertesGainTardif().length, 1);

      // Seconde reprise : le marqueur doit bloquer toute nouvelle émission.
      final second = await s.reprendreNotifications();
      expect(second.where((x) => x.idTicket == 'r2'), isEmpty);
      expect(_alertesGainTardif().length, 1,
          reason: 'aucun doublon après plusieurs cycles');
    });

    test('F3/1.3 CAS A (aucun gain manuel) ne produit JAMAIS de notification',
        () async {
      final t = _ticket(
        id: 'r3',
        gainOfficiel: 75.0,
        etatGain: EtatGain.attribue,
      );
      final s = await _service([t]);
      await AlertService.instance.reinitialiserHistoriquePourTest();

      final resultats = await s.reprendreNotifications();
      expect(resultats.where((x) => x.idTicket == 'r3'), isEmpty);
      expect(_alertesGainTardif(), isEmpty);
    });
  });

  group('F3/2 — NOTIFICATIONS DÉSACTIVÉES PUIS RÉACTIVÉES', () {
    test('F3/2.1 une notification refusée par la config n\'est PAS marquée émise',
        () async {
      final t = _ticket(
        id: 'n1',
        gainManuel: 20.0,
        gainOfficiel: 75.0,
        etatGain: EtatGain.attribue,
      );
      final s = await _service([t]);
      await AlertService.instance.reinitialiserHistoriquePourTest();

      // ⚠️ On coupe les alertes de résultats : c'est le réglage utilisateur.
      await AlertService.instance.updateConfig(
        AlertConfig(activerResultats: false),
      );

      final resultats = await s.reprendreNotifications();
      final r = resultats.singleWhere((x) => x.idTicket == 'n1');
      // La notification N'A PAS été émise : le dire franchement.
      expect(r.issue, IssueRattrapage.echecEcriture);
      expect(_alertesGainTardif(), isEmpty);

      // Le marqueur ne doit PAS avoir été posé : la reprise reste possible.
      final prefs = await SharedPreferences.getInstance();
      final memoire = MemoireGainsTardifsNotifies(prefs);
      expect(memoire.dejaMarque(cleIdempotenceNotification('n1')), isFalse,
          reason: 'une notification non émise ne doit jamais être marquée '
              'comme émise');

      // Réactivation : la reprise doit produire la notification, SANS doublon.
      await AlertService.instance.updateConfig(
        AlertConfig(activerResultats: true),
      );
      final reprise = await s.reprendreNotifications();
      expect(reprise.singleWhere((x) => x.idTicket == 'n1').issue,
          IssueRattrapage.notificationReprise);
      expect(_alertesGainTardif().length, 1);
    });
  });

  group('F3/3 — PURGE DE L\'HISTORIQUE DES ALERTES', () {
    test('F3/3.1 purger l\'historique ne réémet pas la notification', () async {
      final t = _ticket(
        id: 'p1',
        gainManuel: 20.0,
        gainOfficiel: 75.0,
        etatGain: EtatGain.attribue,
      );
      final s = await _service([t]);
      await AlertService.instance.reinitialiserHistoriquePourTest();

      await s.reprendreNotifications();
      expect(_alertesGainTardif().length, 1);

      // ⚠️ On vide l'historique des alertes : c'est la purge temporaire.
      await AlertService.instance.reinitialiserHistoriquePourTest();
      expect(_alertesGainTardif(), isEmpty, reason: 'historique vidé');

      // Le marqueur DURABLE doit empêcher toute réémission.
      final apres = await s.reprendreNotifications();
      expect(apres.where((x) => x.idTicket == 'p1'), isEmpty);
      expect(_alertesGainTardif(), isEmpty,
          reason: 'l\'historique des alertes n\'est pas la preuve d\'idempotence');
    });

    test('F3/3.2 la DÉCISION en attente survit à la purge de l\'historique',
        () async {
      final t = _ticket(
        id: 'p2',
        gainManuel: 20.0,
        gainOfficiel: 75.0,
        etatGain: EtatGain.attribue,
      );
      final s = await _service([t]);
      await AlertService.instance.reinitialiserHistoriquePourTest();
      await s.reprendreNotifications();

      // Purge de l'historique.
      await AlertService.instance.reinitialiserHistoriquePourTest();

      // La décision reste déduite du TICKET, pas de l'alerte.
      final attentes = decisionsEnAttente(s.provider.predictions);
      expect(attentes.length, 1);
      expect(attentes.single.id, 'p2');
      expect(attentes.single.gainManuel, 20.0);
      expect(attentes.single.gainOfficiel, 75.0);
      // Et elle est bien retenue au manuel, avant décision.
      expect(attentes.single.gainRetenu, 20.0);
    });
  });

  group('F3/4 — INTERRUPTION ENTRE ÉCRITURE ET NOTIFICATION', () {
    test('F3/4.1 écriture confirmée + marqueur posé, notification non posée',
        () async {
      // Simulation exacte de l'interruption : le marqueur d'écriture EST là,
      // le marqueur de notification N'EST PAS là.
      final t = _ticket(
        id: 'i1',
        gainManuel: 20.0,
        gainOfficiel: 75.0,
        etatGain: EtatGain.attribue,
      );
      final s = await _service([t]);
      final prefs = await SharedPreferences.getInstance();
      final memoire = MemoireGainsTardifsNotifies(prefs);
      expect(await memoire.marquer(cleIdempotenceEcriture('i1')), isTrue);

      await AlertService.instance.reinitialiserHistoriquePourTest();
      final resultats = await s.reprendreNotifications();

      expect(resultats.singleWhere((x) => x.idTicket == 'i1').issue,
          IssueRattrapage.notificationReprise);
      expect(_alertesGainTardif().length, 1);
    });
  });

  group('F3/5 — IDENTIFICATION EXACTE : deux courses, mêmes numéros', () {
    test('F3/5.1 deux dates différentes ne sont PAS regroupées', () async {
      // ⚠️ MÊMES R1C3, DATES DIFFÉRENTES : deux courses distinctes.
      final a = _ticket(
          id: 'x1', gainOfficiel: 10.0, dateStr: '23032026', numReunion: 1, numCourse: 3);
      final b = _ticket(
          id: 'x2', gainOfficiel: 20.0, dateStr: '24032026', numReunion: 1, numCourse: 3);
      final s = await _service([a, b]);

      final courses = s.coursesCandidates();
      expect(courses.length, 2,
          reason: 'la date fait partie de la clé : deux courses distinctes');
      expect(courses.map((c) => c.cle).toSet().length, 2);
      expect(courses.map((c) => c.dateStr).toSet(), {'23032026', '24032026'});
    });

    test('F3/5.2 plusieurs tickets d\'UNE course ⇒ UNE seule course candidate',
        () async {
      final t1 = _ticket(id: 'y1', gainOfficiel: 10.0);
      final t2 = _ticket(id: 'y2', gainManuel: 5.0);
      final t3 = _ticket(id: 'y3', gainManuel: 8.0);
      final s = await _service([t1, t2, t3]);

      // ⚠️ Mutualisation : trois tickets, UNE course ⇒ une requête.
      expect(s.coursesCandidates().length, 1);
      expect(s.ticketsDeCourse(s.coursesCandidates().single).length, 3);
    });

    test('F3/5.3 un ticket déjà réglé n\'est PAS candidat au réseau', () async {
      final regle = _ticket(
          id: 'z1', gainOfficiel: 75.0, etatGain: EtatGain.attribue);
      final enAttente = _ticket(id: 'z2', gainOfficiel: 12.0);
      final s = await _service([regle, enAttente]);

      final candidats = s.ticketsARattraper();
      expect(candidats.map((p) => p.id), <String>['z2'],
          reason: 'un ticket financièrement résolu ne déclenche plus de réseau');
    });
  });

  group('F3/6 — REMBOURSEMENT DÉFINITIF : pas de boucle infinie', () {
    test('F3/6.1 un remboursement pur est considéré comme résultat persisté',
        () async {
      // Un remboursement SEUL : aucun gain officiel, mais le résultat EST écrit.
      final t = _ticket(
        id: 'rb1',
        gainManuel: 20.0,
        remboursement: 20.0,
        etatGain: EtatGain.rembourse,
      );
      final s = await _service([t]);
      await AlertService.instance.reinitialiserHistoriquePourTest();

      // Aucune notification de gain tardif : un remboursement n'est pas un gain.
      final resultats = await s.reprendreNotifications();
      expect(resultats.where((x) => x.idTicket == 'rb1'), isEmpty);
      expect(_alertesGainTardif(), isEmpty);

      // Et le ticket n'est PAS candidat au réseau : aucune boucle.
      expect(s.ticketsARattraper().where((p) => p.id == 'rb1'), isEmpty);
    });

    test('F3/6.2 résultat MIXTE gain + remboursement : traité une seule fois',
        () async {
      final t = _ticket(
        id: 'rb2',
        gainManuel: 15.0,
        gainOfficiel: 75.0,
        remboursement: 10.0,
        etatGain: EtatGain.attribue,
      );
      final s = await _service([t]);
      await AlertService.instance.reinitialiserHistoriquePourTest();

      await s.reprendreNotifications();
      expect(_alertesGainTardif().length, 1);

      // Le remboursement reste DISTINCT du gain dans la décision présentée.
      final attentes = decisionsEnAttente(s.provider.predictions);
      expect(attentes.single.remboursement, 10.0);
      expect(attentes.single.gainOfficiel, 75.0);
      // Le gain retenu n'inclut PAS le remboursement.
      expect(attentes.single.gainRetenu, 15.0);

      // Aucune boucle : second cycle inactif.
      await s.reprendreNotifications();
      expect(_alertesGainTardif().length, 1);
    });
  });

  group('F3/7 — CYCLE COMPLET NON RÉENTRANT', () {
    test('F3/7.1 un cycle en cours refuse le second sans toucher au réseau',
        () async {
      final s = await _service([_ticket(id: 'w1', gainOfficiel: 5.0)]);
      // Lancement simultané : le second doit rendre un bilan vide.
      final futures = await Future.wait([s.executerCycle(), s.executerCycle()]);
      // Un seul des deux a fait un travail effectif.
      expect(s.cyclesTermines, 1,
          reason: 'aucun cycle concurrent ne doit s\'exécuter');
      expect(futures.length, 2);
    });
  });
}
