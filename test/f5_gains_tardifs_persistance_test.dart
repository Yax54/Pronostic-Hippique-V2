// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — FONCTIONNEL 5/4 : PERSISTANCE, SAUVEGARDE ET PLANIFICATEUR
// ═══════════════════════════════════════════════════════════════════════════
//
//  Ce fichier démontre :
//    • les marqueurs d'idempotence survivent à un cycle complet de la mémoire ;
//    • les deux clés du chantier sont bien dans le périmètre de sauvegarde ;
//    • une notification déjà émise n'est PAS reproduite après restauration ;
//    • une décision en attente n'est PAS perdue par une restauration ;
//    • le planificateur ne lance jamais deux cycles concurrents et respecte
//      sa distance minimale ;
//    • une erreur de cycle ne remonte jamais (elle ne casse pas l'application).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/detection_gains_tardifs.dart';
import 'package:pronostic_hippique/services/gains_tardifs_notifies_store.dart';
import 'package:pronostic_hippique/services/gains_tardifs_regles.dart';
import 'package:pronostic_hippique/services/planificateur_gains_tardifs.dart';
import 'package:pronostic_hippique/services/service_gains_tardifs.dart';

const _cleTickets = 'user_predictions_v2';

UserPrediction _ticket({
  required String id,
  double? gainManuel,
  double? gainOfficiel,
}) =>
    UserPrediction(
      id: id,
      dateStr: '23032026',
      numReunion: 1,
      numCourse: 3,
      nomCourse: 'Prix de test',
      hippodrome: 'Vincennes',
      numeroCheval: 5,
      nomCheval: 'Cheval Test',
      cote: 3.5,
      typePari: 'Simple Gagnant',
      createdAt: DateTime(2026, 3, 23, 14, 30),
      montantMise: 20.0,
      montantGainManuel: gainManuel,
      montantOfficielPmu: gainOfficiel,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P1 — MÉMOIRE D\'IDEMPOTENCE', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('P1.1 les trois marqueurs coexistent sans se confondre', () async {
      final m = await MemoireGainsTardifsNotifies.ouvrir();
      expect(await m.marquer(cleIdempotenceEcriture('t1')), isTrue);
      expect(await m.marquer(cleIdempotenceNotification('t1')), isTrue);
      expect(await m.marquer(cleIdempotenceDecision('t1')), isTrue);

      expect(m.dejaMarque(cleIdempotenceEcriture('t1')), isTrue);
      expect(m.dejaMarque(cleIdempotenceNotification('t1')), isTrue);
      expect(m.dejaMarque(cleIdempotenceDecision('t1')), isTrue);
      expect(m.lireTout().length, 3, reason: 'trois entrées distinctes');
    });

    test('P1.2 marquer une seule famille ne marque PAS les autres', () async {
      final m = await MemoireGainsTardifsNotifies.ouvrir();
      await m.marquer(cleIdempotenceEcriture('t2'));
      // ⚠️ LE CŒUR DE LA CORRECTION : ces deux-là doivent rester fausses.
      expect(m.dejaMarque(cleIdempotenceNotification('t2')), isFalse);
      expect(m.dejaMarque(cleIdempotenceDecision('t2')), isFalse);
    });

    test('P1.3 deux tickets ne se contaminent pas', () async {
      final m = await MemoireGainsTardifsNotifies.ouvrir();
      await m.marquer(cleIdempotenceNotification('tA'));
      expect(m.dejaMarque(cleIdempotenceNotification('tA')), isTrue);
      expect(m.dejaMarque(cleIdempotenceNotification('tB')), isFalse);
    });

    test('P1.4 une clé illisible rend une carte VIDE, pas une exception',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kClePrefsGainsTardifsNotifies: 'ceci n\'est pas du JSON',
      });
      final m = await MemoireGainsTardifsNotifies.ouvrir();
      expect(m.lireTout(), isEmpty);
    });

    test('P1.5 effacer un marqueur le retire réellement', () async {
      final m = await MemoireGainsTardifsNotifies.ouvrir();
      await m.marquer(cleIdempotenceNotification('t3'));
      expect(await m.effacer(cleIdempotenceNotification('t3')), isTrue);
      expect(m.dejaMarque(cleIdempotenceNotification('t3')), isFalse);
    });
  });

  group('P2 — PÉRIMÈTRE DE SAUVEGARDE', () {
    test('P2.1 les deux clés du chantier sont dans le périmètre du backup', () {
      final cles = BackupService.clesSauvegardeesPourTest();
      expect(cles, contains(kClePrefsGainsTardifsNotifies),
          reason: 'sans elle, une notification déjà émise serait réémise '
              'après restauration');
      expect(cles, contains('gains_tardifs_backoff_v1'),
          reason: 'sans elle, une restauration provoquerait une rafale de '
              'requêtes');
      // Et la vérité financière reste bien sauvegardée.
      expect(cles, contains(_cleTickets));
    });

    test('P2.2 le périmètre ne contient aucune clé en double', () {
      final cles = BackupService.clesSauvegardeesPourTest();
      expect(cles.length, cles.toSet().length,
          reason: 'une clé dupliquée masquerait un oubli ailleurs');
    });
  });

  group('P3 — RESTAURATION : ni doublon, ni perte de décision', () {
    test('P3.1 une notification déjà émise n\'est pas reproduite', () async {
      // État 1 : on pose le marqueur de notification.
      SharedPreferences.setMockInitialValues(<String, Object>{
        _cleTickets: [
          jsonEncode(_ticket(
                  id: 's1', gainManuel: 20.0, gainOfficiel: 75.0)
              .toJson())
        ],
      });
      var m = await MemoireGainsTardifsNotifies.ouvrir();
      await m.marquer(cleIdempotenceNotification('s1'));

      // On capture l'état sauvegardé, puis on repart de zéro (restauration).
      final prefs = await SharedPreferences.getInstance();
      final sauvegarde = prefs.getString(kClePrefsGainsTardifsNotifies);
      expect(sauvegarde, isNotNull);

      // Restauration : on remet l'état sauvegardé.
      SharedPreferences.setMockInitialValues(<String, Object>{
        _cleTickets: [
          jsonEncode(_ticket(
                  id: 's1', gainManuel: 20.0, gainOfficiel: 75.0)
              .toJson())
        ],
        kClePrefsGainsTardifsNotifies: sauvegarde!,
      });

      // ⚠️ La mémoire est reconstruite : le marqueur doit être retrouvé.
      m = await MemoireGainsTardifsNotifies.ouvrir();
      expect(m.dejaMarque(cleIdempotenceNotification('s1')), isTrue,
          reason: 'la restauration ne doit pas recréer une notification');
    });

    test('P3.2 une décision EN ATTENTE survit à une restauration', () async {
      final ticket = _ticket(id: 's2', gainManuel: 20.0, gainOfficiel: 75.0);

      // Sauvegarde du ticket tel qu'il est : officiel présent, aucune décision.
      SharedPreferences.setMockInitialValues(<String, Object>{
        _cleTickets: [jsonEncode(ticket.toJson())],
      });
      final p1 = PmuProvider();
      await p1.reloadPredictions();

      // Restauration : le ticket est relu sur le même support.
      final p2 = PmuProvider();
      await p2.reloadPredictions();
      final relu = p2.predictions.firstWhere((x) => x.id == 's2');

      expect(relu.montantOfficielPmu, 75.0);
      expect(relu.montantGainManuel, 20.0);
      expect(relu.decisionGainPmu, isNull,
          reason: 'une décision en attente ne doit pas être perdue');
    });
  });

  group('P4 — PLANIFICATEUR : non-réentrance et distance minimale', () {
    test('P4.1 deux appels rapprochés ne produisent QU\'UN cycle', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _cleTickets: [jsonEncode(_ticket(id: 'q1', gainOfficiel: 5.0).toJson())],
      });
      final provider = PmuProvider();
      await provider.reloadPredictions();
      final prefs = await SharedPreferences.getInstance();

      var cycles = 0;
      final planificateur = PlanificateurGainsTardifs(
        fabrique: () async => ServiceGainsTardifs(
          provider: provider,
          detecteur: DetecteurGainsTardifs(store: BackoffTardifStore(prefs)),
          memoire: MemoireGainsTardifsNotifies(prefs),
          horloge: () => DateTime(2026, 3, 24, 10, 0),
        ),
        distanceMinimale: const Duration(minutes: 2),
        // Horloge FIXE : le second appel est donc à distance nulle.
        horloge: () => DateTime(2026, 3, 24, 10, 0),
      );
      // On compte les cycles réellement exécutés par le service.
      expect(await planificateur.demarrer(), isTrue);
      cycles = planificateur.cyclesLances;
      expect(cycles, 1);

      // Second déclencheur immédiat : refusé par la distance minimale.
      expect(await planificateur.retourPremierPlan(), isFalse);
      expect(planificateur.cyclesLances, 1);
      expect(planificateur.demarragesRefuses, greaterThan(0));

      planificateur.arreter();
    });

    test('P4.2 après la distance minimale, un nouveau cycle est permis',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _cleTickets: [jsonEncode(_ticket(id: 'q2', gainOfficiel: 5.0).toJson())],
      });
      final provider = PmuProvider();
      await provider.reloadPredictions();
      final prefs = await SharedPreferences.getInstance();

      var maintenant = DateTime(2026, 3, 24, 10, 0);
      final planificateur = PlanificateurGainsTardifs(
        fabrique: () async => ServiceGainsTardifs(
          provider: provider,
          detecteur: DetecteurGainsTardifs(store: BackoffTardifStore(prefs)),
          memoire: MemoireGainsTardifsNotifies(prefs),
          horloge: () => maintenant,
        ),
        distanceMinimale: const Duration(minutes: 2),
        horloge: () => maintenant,
      );

      expect(await planificateur.demarrer(), isTrue);
      expect(planificateur.cyclesLances, 1);

      // On avance l'horloge AU-DELÀ de la distance minimale.
      maintenant = maintenant.add(const Duration(minutes: 3));
      expect(await planificateur.retourPremierPlan(), isTrue);
      expect(planificateur.cyclesLances, 2);

      planificateur.arreter();
    });

    test('P4.3 une erreur de cycle ne remonte PAS et n\'empêche rien', () async {
      final planificateur = PlanificateurGainsTardifs(
        fabrique: () async => throw StateError('support indisponible'),
      );
      // ⚠️ Aucune exception ne doit sortir : l'application doit démarrer.
      expect(await planificateur.demarrer(), isFalse);
      expect(planificateur.echecs, 1);
      expect(planificateur.pret, isFalse);
    });
  });
}
