// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — F6 : PERSISTANCE DE BOUT EN BOUT PAR LE VRAI BACKUP
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ POURQUOI CE FICHIER EXISTE
//
//  F5 démontrait la persistance par le support `SharedPreferences` et par le
//  PÉRIMÈTRE de sauvegarde (`clesSauvegardeesPourTest`). Cela ne prouve pas
//  qu'un export produit par l'application, écrit sur le disque, puis restauré
//  par `importerDepuisFichier()` conserve réellement ces données.
//
//  Ce fichier emprunte donc les VÉRITABLES mécanismes :
//
//      BackupService.instance.exporterDonnees()   → fichier JSON sur disque
//      BackupService.instance.importerDepuisFichier() → _restaurerDepuisJson()
//
//  avec un faux `PathProvider` (répertoire temporaire RÉEL) et un faux
//  `FilePicker` injectant les OCTETS du fichier réellement produit. Aucune
//  logique de sauvegarde n'est réécrite ici.
//
//  ★ CE QUI EST DÉMONTRÉ, SCÉNARIO PAR SCÉNARIO
//    P5.1  une notification DÉJÀ ÉMISE n'est pas réémise après restauration ;
//    P5.2  une notification ENCORE NÉCESSAIRE survit (marqueur absent = renvoi) ;
//    P5.3  une DÉCISION EN ATTENTE survit (officiel + manuel, décision nulle) ;
//    P5.4  une ACCEPTATION survit (elle n'est JAMAIS reproposée) ;
//    P5.5  un REFUS survit et reste distinct de « pas encore décidé » ;
//    P5.6  les INFORMATIONS DE REPRISE (backoff) survivent ;
//    P5.7  AUCUNE notification dupliquée après restauration (compte exact) ;
//    P5.8  une ANCIENNE sauvegarde sans les nouvelles clés reste restaurable.
//
//  ⚠️ AUCUNE ASSERTION MÉTIER N'EST AFFAIBLIE, AUCUNE DONNÉE INVENTÉE : les
//     montants attendus sont ceux que les tests écrivent explicitement, et le
//     contrôle se fait par LECTURE de ce qui a été restauré.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/decision_gain_pmu.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/detection_gains_tardifs.dart';
import 'package:pronostic_hippique/services/gains_tardifs_en_attente.dart';
import 'package:pronostic_hippique/services/gains_tardifs_notifies_store.dart';
import 'package:pronostic_hippique/services/gains_tardifs_regles.dart';

const String _cleTickets = 'user_predictions_v2';
const String _cleAlertes = 'alert_history_v1';

// ───────────────────────────────────────────────────────────────────────────
//  Faux de plateforme — répertoire temporaire RÉEL et fichier injecté
// ───────────────────────────────────────────────────────────────────────────

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tmpPath);
  final String tmpPath;

  @override
  Future<String?> getTemporaryPath() async => tmpPath;
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this._result);
  final FilePickerResult? _result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      _result;
}

// ───────────────────────────────────────────────────────────────────────────
//  Outils
// ───────────────────────────────────────────────────────────────────────────

UserPrediction _ticket({
  required String id,
  double? gainManuel,
  double? gainOfficiel,
  double? remboursement,
  DecisionGainPmu? decision,
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
      remboursementPmu: remboursement,
      decisionGainPmu: decision,
    );

/// Exporte par la VOIE RÉELLE, rend les octets du fichier réellement produit.
Future<Uint8List> _exporterOctets() async {
  final export = await BackupService.instance.exporterDonnees();
  expect(export.succes, isTrue, reason: 'exporterDonnees a échoué');
  final f = File(export.filePath!);
  expect(await f.exists(), isTrue,
      reason: 'le fichier de sauvegarde doit exister sur le disque');
  return f.readAsBytes();
}

/// Restaure par la VOIE RÉELLE, à partir des octets d'une sauvegarde.
Future<void> _restaurerOctets(Uint8List octets, {String nom = 'backup.json'}) async {
  FilePicker.platform = _FakeFilePicker(FilePickerResult([
    PlatformFile(name: nom, size: octets.length, bytes: octets),
  ]));
  final import = await BackupService.instance.importerDepuisFichier();
  expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');
}

AlertService _alerteService() => AlertService.instance;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String cheminTmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('f6_backup_');
    cheminTmp = tmp.path;
    PathProviderPlatform.instance = _FakePathProvider(cheminTmp);
  });

  tearDown(() async {
    if (await tmp.exists()) {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('P5 — PERSISTANCE DE BOUT EN BOUT (vrai export / vraie restauration)', () {
    // ═══════════════════════════════════════════════════════════════════════
    //  P5.1 — UNE NOTIFICATION DÉJÀ ÉMISE N'EST PAS RÉÉMISE
    // ═══════════════════════════════════════════════════════════════════════
    test(
        'P5.1 une notification déjà émise survit à un export puis une '
        'restauration réels, et n\'est pas réémise', () async {
      // État de départ : un ticket avec décision en attente, et le marqueur de
      // notification posé (la notification a déjà été produite).
      SharedPreferences.setMockInitialValues(<String, Object>{
        _cleTickets: [
          jsonEncode(_ticket(id: 'b1', gainManuel: 20.0, gainOfficiel: 75.0)
              .toJson()),
        ],
      });

      final prefs0 = await SharedPreferences.getInstance();
      await prefs0.setString(
        MemoireGainsTardifsNotifies.clePrefs,
        jsonEncode({'gt1:b1': '2026-03-23T15:00:00.000'}),
      );
      // ⚠️ LE BACKOFF DOIT RÉELLEMENT EXISTER POUR ÊTRE EXPORTÉ.
      //
      //   `_collecterDonnees()` n'écrit une clé dans le fichier que si elle
      //   est PRÉSENTE dans les préférences (`_lireEntree` rend `null` sinon).
      //   L'assertion « la clé est dans le fichier » n'est donc vérifiable que
      //   si la donnée a été produite. On la produit ici avec l'état RÉEL d'une
      //   course déjà tentée, au lieu d'exiger du produit qu'il invente une
      //   clé vide — ce serait l'assertion qui mentirait, pas le produit.
      await prefs0.setString(
        BackoffTardifStore.clePrefs,
        jsonEncode({
          '23032026_R1C3': EtatSuiviCourse(
            tentatives: 1,
            dernierEssai: DateTime(2026, 3, 23, 15, 0),
            derniereClassification:
                ClassificationCourseTardive.rapportsAbsents,
          ).toJson(),
        }),
      );

      // L'alerte elle-même a bien été émise et persistée.
      final alertSvc = _alerteService();
      // Motif identique à F3, qui émet réellement : on purge d'abord
      // l'historique et on laisse `_save()` réarmer l'état, puis on émet.
      await alertSvc.reinitialiserHistoriquePourTest();
      final emise = await alertSvc.emettreAlerteGainTardif(
        idTicket: 'b1',
        titre: '🏆 Gain officiel disponible',
        message: 'Gain officiel 75,00 € pour votre pari.',
        numReunion: 1,
        numCourse: 3,
      );
      expect(emise, isTrue, reason: 'la notification doit réellement exister');

      final avant = alertSvc.alerts
          .where((a) => a.type == AlertType.gainTardif)
          .length;
      expect(avant, 1);

      // ── EXPORT RÉEL ────────────────────────────────────────────────────
      final octets = await _exporterOctets();

      // Contenu du fichier : les deux clés du chantier sont bien présentes.
      final contenu = json.decode(utf8.decode(octets)) as Map<String, dynamic>;
      final alertes = contenu['alertes'] as Map<String, dynamic>;
      expect(alertes.containsKey(MemoireGainsTardifsNotifies.clePrefs), isTrue,
          reason: 'le marqueur d\'idempotence doit être DANS le fichier');
      expect(alertes.containsKey('gains_tardifs_backoff_v1'), isTrue,
          reason: 'les informations de reprise doivent être DANS le fichier');
      expect(alertes.containsKey(_cleAlertes), isTrue,
          reason: 'la notification émise doit être DANS le fichier');

      // ── APPAREIL VIERGE ────────────────────────────────────────────────
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final vierge = await SharedPreferences.getInstance();
      expect(vierge.getString(MemoireGainsTardifsNotifies.clePrefs), isNull);

      // ── RESTAURATION RÉELLE ────────────────────────────────────────────
      await _restaurerOctets(octets);

      final apres = await SharedPreferences.getInstance();
      final marqueur = apres.getString(MemoireGainsTardifsNotifies.clePrefs);
      expect(marqueur, isNotNull,
          reason: 'sans le marqueur, la notification serait réémise');
      final memoire = await MemoireGainsTardifsNotifies.ouvrir();
      expect(memoire.dejaMarque(cleIdempotenceNotification('b1')), isTrue);

      // La notification restaurée est bien là, une seule fois.
      final alertSvc2 = _alerteService();
      await alertSvc2.recharger();
      final apresRestau = alertSvc2.alerts
          .where((a) => a.type == AlertType.gainTardif)
          .toList();
      expect(apresRestau.length, 1,
          reason: 'la notification émise doit être conservée, sans doublon');
    });

    // ═══════════════════════════════════════════════════════════════════════
    //  P5.2 — UNE NOTIFICATION ENCORE NÉCESSAIRE SURVIT (marqueur absent)
    // ═══════════════════════════════════════════════════════════════════════
    test(
        'P5.2 une notification ENCORE NÉCESSAIRE survit : la décision en '
        'attente est intacte et reste renotifiable', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _cleTickets: [
          jsonEncode(_ticket(id: 'b2', gainManuel: 20.0, gainOfficiel: 75.0)
              .toJson()),
        ],
      });

      final octets = await _exporterOctets();

      SharedPreferences.setMockInitialValues(<String, Object>{});
      await _restaurerOctets(octets);

      // Le ticket est restauré, la décision est TOUJOURS attendue.
      final provider = PmuProvider();
      await provider.reloadPredictions();
      final t = provider.predictions.firstWhere((p) => p.id == 'b2');
      expect(t.montantOfficielPmu, 75.0);
      expect(t.montantGainManuel, 20.0);
      expect(t.decisionGainPmu, isNull);
      expect(attendDecisionGain(t), isTrue,
          reason: 'la décision doit rester proposable après restauration');

      // Le marqueur de notification est ABSENT : la notification reste due.
      final memoire = await MemoireGainsTardifsNotifies.ouvrir();
      expect(memoire.dejaMarque(cleIdempotenceNotification('b2')), isFalse,
          reason: 'une notification encore nécessaire ne doit pas être '
              'marquée comme émise');
    });

    // ═══════════════════════════════════════════════════════════════════════
    //  P5.3 — UNE DÉCISION EN ATTENTE SURVIT
    // ═══════════════════════════════════════════════════════════════════════
    test('P5.3 une décision en attente survit, montants exacts', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _cleTickets: [
          jsonEncode(_ticket(
            id: 'b3',
            gainManuel: 12.34,
            gainOfficiel: 98.76,
            remboursement: 20.0,
          ).toJson()),
        ],
      });

      final octets = await _exporterOctets();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await _restaurerOctets(octets);

      final provider = PmuProvider();
      await provider.reloadPredictions();
      final t = provider.predictions.firstWhere((p) => p.id == 'b3');

      expect(t.montantGainManuel, 12.34);
      expect(t.montantOfficielPmu, 98.76);
      expect(t.remboursementPmu, 20.0);
      expect(t.decisionGainPmu, isNull);
      // Le gain retenu AVANT décision reste le gain DÉCLARÉ.
      expect(t.gainRetenuBrut, 12.34,
          reason: 'sans décision, l\'officiel ne remplace jamais le manuel');
    });

    // ═══════════════════════════════════════════════════════════════════════
    //  P5.4 — UNE ACCEPTATION SURVIT ET N'EST JAMAIS REPROPOSÉE
    // ═══════════════════════════════════════════════════════════════════════
    test(
        'P5.4 une ACCEPTATION survit à la restauration et n\'est plus jamais '
        'reproposée', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _cleTickets: [
          jsonEncode(_ticket(
            id: 'b4',
            gainManuel: 20.0,
            gainOfficiel: 75.0,
            decision: DecisionGainPmu.accepte,
          ).toJson()),
        ],
      });

      final octets = await _exporterOctets();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await _restaurerOctets(octets);

      final provider = PmuProvider();
      await provider.reloadPredictions();
      final t = provider.predictions.firstWhere((p) => p.id == 'b4');

      expect(t.decisionGainPmu, DecisionGainPmu.accepte);
      expect(attendDecisionGain(t), isFalse,
          reason: 'une décision prise ne doit JAMAIS être représentée');
      expect(t.gainRetenuBrut, 75.0,
          reason: 'accepter, c\'est retenir l\'officiel');
    });

    // ═══════════════════════════════════════════════════════════════════════
    //  P5.5 — UN REFUS SURVIT ET RESTE DISTINCT DE « PAS ENCORE DÉCIDÉ »
    // ═══════════════════════════════════════════════════════════════════════
    test(
        'P5.5 un REFUS survit, reste distinct de « non décidé », et le manuel '
        'reste retenu', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _cleTickets: [
          jsonEncode(_ticket(
            id: 'b5',
            gainManuel: 20.0,
            gainOfficiel: 75.0,
            decision: DecisionGainPmu.refuse,
          ).toJson()),
        ],
      });

      final octets = await _exporterOctets();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await _restaurerOctets(octets);

      final provider = PmuProvider();
      await provider.reloadPredictions();
      final t = provider.predictions.firstWhere((p) => p.id == 'b5');

      expect(t.decisionGainPmu, DecisionGainPmu.refuse);
      expect(t.decisionGainPmu, isNotNull,
          reason: 'refuser n\'est pas « ne pas décider »');
      expect(attendDecisionGain(t), isFalse);
      expect(t.gainRetenuBrut, 20.0,
          reason: 'refuser, c\'est conserver son propre gain');
      // La trace du résultat officiel est CONSERVÉE : refuser n'efface rien.
      expect(t.montantOfficielPmu, 75.0);
    });

    // ═══════════════════════════════════════════════════════════════════════
    //  P5.6 — LES INFORMATIONS DE REPRISE (BACKOFF) SURVIVENT
    // ═══════════════════════════════════════════════════════════════════════
    test('P5.6 les informations de reprise des tentatives survivent', () async {
      final date = DateTime(2026, 3, 23, 15, 0);
      SharedPreferences.setMockInitialValues(<String, Object>{
        _cleTickets: [
          jsonEncode(_ticket(id: 'b6', gainManuel: 20.0, gainOfficiel: 75.0)
              .toJson()),
        ],
        BackoffTardifStore.clePrefs: jsonEncode({
          '23032026_R1C3': EtatSuiviCourse(
            tentatives: 3,
            dernierEssai: date,
            derniereClassification: ClassificationCourseTardive.rapportsAbsents,
          ).toJson(),
        }),
      });

      final octets = await _exporterOctets();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await _restaurerOctets(octets);

      final store = await BackoffTardifStore.ouvrir();
      final etat = store.lire('23032026_R1C3');
      expect(etat, isNotNull,
          reason: 'sans backoff, une restauration provoquerait une rafale de '
              'requêtes');
      expect(etat.tentatives, 3);
      expect(etat.dernierEssai, date);
      expect(etat.derniereClassification,
          ClassificationCourseTardive.rapportsAbsents);
      // Et l'échéance correspond bien au 3e palier (6 h).
      expect(etat.prochainEssai, date.add(const Duration(hours: 6)));
    });

    // ═══════════════════════════════════════════════════════════════════════
    //  P5.7 — AUCUNE NOTIFICATION DUPLIQUÉE APRÈS RESTAURATION
    // ═══════════════════════════════════════════════════════════════════════
    test(
        'P5.7 après restauration, relancer l\'émission ne crée AUCUN doublon',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _cleTickets: [
          jsonEncode(_ticket(id: 'b7', gainManuel: 20.0, gainOfficiel: 75.0)
              .toJson()),
        ],
      });

      // Émission une première fois, puis export.
      //
      // ⚠️ ON PURGE AVANT D'ÉMETTRE, JAMAIS APRÈS AVOIR RESTAURÉ.
      //   `AlertService` est un SINGLETON : son état mémoire survit d'un test
      //   à l'autre. Sans purge préalable, `_save()` réécrirait sur le disque
      //   les alertes des tests précédents, et l'export ne représenterait plus
      //   l'état de ce scénario. La purge est donc faite ICI, en tête, comme
      //   dans F3 — et surtout PAS après `recharger()`, où elle détruirait
      //   précisément ce que la restauration vient de reconstituer.
      final s1 = _alerteService();
      await s1.reinitialiserHistoriquePourTest();
      expect(
        await s1.emettreAlerteGainTardif(
          idTicket: 'b7',
          titre: '🏆 Gain officiel disponible',
          message: 'Gain officiel 75,00 €.',
          numReunion: 1,
          numCourse: 3,
        ),
        isTrue,
      );
      final octets = await _exporterOctets();

      // Effacement total puis restauration.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await _restaurerOctets(octets);

      // Un NOUVEAU service, comme après un redémarrage de l'application :
      // `recharger()` relit le disque restauré et REBÂTIT l'historique. On ne
      // purge surtout pas ici.
      final s2 = _alerteService();
      await s2.recharger();
      final apresChargement = s2.alerts
          .where((a) => a.type == AlertType.gainTardif)
          .length;
      expect(apresChargement, 1,
          reason: 'la notification restaurée doit être rechargée depuis le '
              'disque, sans doublon');

      // Réémission : c'est un succès idempotent, mais AUCUNE seconde entrée.
      expect(
        await s2.emettreAlerteGainTardif(
          idTicket: 'b7',
          titre: '🏆 Gain officiel disponible',
          message: 'Gain officiel 75,00 €.',
          numReunion: 1,
          numCourse: 3,
        ),
        isTrue,
        reason: 'la notification existe déjà : succès, pas échec',
      );

      final final_ = s2.alerts
          .where((a) => a.type == AlertType.gainTardif)
          .toList();
      expect(final_.length, 1,
          reason: 'aucune notification dupliquée après restauration');
      // Et sur le disque non plus.
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final lignes = prefs.getStringList(_cleAlertes) ?? const <String>[];
      final surDisque = lignes.where((l) {
        try {
          final j = json.decode(l) as Map<String, dynamic>;
          return AlertType.values[j['type'] as int] == AlertType.gainTardif;
        } catch (_) {
          return false;
        }
      }).length;
      expect(surDisque, 1, reason: 'le disque ne doit porter qu\'une entrée');
    });

    // ═══════════════════════════════════════════════════════════════════════
    //  P5.8 — COMPATIBILITÉ AVEC UNE ANCIENNE SAUVEGARDE
    // ═══════════════════════════════════════════════════════════════════════
    test(
        'P5.8 une ancienne sauvegarde SANS les nouvelles clés reste restaurable '
        'et conserve les tickets', () async {
      // Sauvegarde « historique » : ni gains_tardifs_notifies_v1, ni
      // gains_tardifs_backoff_v1 — exactement ce que produisait la version
      // précédente de l'application.
      final ancienne = <String, dynamic>{
        'version': '9.1',
        'appName': 'Pronostic Hippique',
        'dateBackup': '2026-03-20T10:00:00.000',
        'ia': <String, dynamic>{},
        'configIA': <String, dynamic>{},
        'paris': {
          _cleTickets: {
            'type': 'StringList',
            'value': [
              jsonEncode(_ticket(
                id: 'old1',
                gainManuel: 20.0,
                gainOfficiel: 75.0,
              ).toJson()),
            ],
          },
        },
        'alertes': {
          _cleAlertes: {
            'type': 'StringList',
            'value': <String>[],
          },
        },
        'profil': <String, dynamic>{},
        'widget': <String, dynamic>{},
        'laboIA': <String, dynamic>{},
        'auditCache': <String, dynamic>{},
        'grosParis': <String, dynamic>{},
      };

      final octets = Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(ancienne)));

      expect(ancienne['alertes']
          .toString()
          .contains(MemoireGainsTardifsNotifies.clePrefs), isFalse,
          reason: 'l\'ancienne sauvegarde ne doit PAS porter la nouvelle clé');

      SharedPreferences.setMockInitialValues(<String, Object>{});
      await _restaurerOctets(octets, nom: 'backup_ancienne.json');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(MemoireGainsTardifsNotifies.clePrefs), isNull,
          reason: 'une clé absente reste absente — elle n\'est pas inventée');

      final provider = PmuProvider();
      await provider.reloadPredictions();
      final t = provider.predictions.firstWhere((p) => p.id == 'old1');
      expect(t.montantOfficielPmu, 75.0);
      expect(t.montantGainManuel, 20.0);
      expect(attendDecisionGain(t), isTrue,
          reason: 'la décision reste proposable après une ancienne sauvegarde');

      // La mémoire d'idempotence est vide et parfaitement fonctionnelle.
      final memoire = await MemoireGainsTardifsNotifies.ouvrir();
      expect(memoire.lireTout(), isEmpty);
      expect(await memoire.marquer(cleIdempotenceNotification('old1')), isTrue);
      expect(memoire.dejaMarque(cleIdempotenceNotification('old1')), isTrue);
    });
  });
}
