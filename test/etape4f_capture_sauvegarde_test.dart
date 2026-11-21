// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 4-F / ÉTAPE 1 — SAUVEGARDE ET RESTAURATION DES NOUVEAUX CHAMPS
//
//  Le mandat 4-F §4 impose de VÉRIFIER — et non de supposer — que la
//  sauvegarde exportée et la restauration transportent les quatre champs de
//  capture, sans avoir à modifier `backup_service`.
//
//  Ces tests utilisent la VRAIE API publique de BackupService
//  (`exporterDonnees` / `importerDepuisFichier`), comme le fait déjà
//  `v5_backup_restore_test.dart` :
//     exporterDonnees()  →  fichier JSON sur disque
//     importerDepuisFichier()  →  _restaurerDepuisJson()  →  SharedPreferences
//
//  Si un jour `backup_service` se mettait à reconstruire les tickets champ
//  par champ au lieu de recopier la liste brute, ces tests deviendraient
//  rouges : c'est exactement leur rôle de garde-fou.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
// ───────────────────────────────────────────────────────────────────────────
//  Faux de plateforme
// ───────────────────────────────────────────────────────────────────────────

/// Injecte un répertoire temporaire réel : sans ce faux, `exporterDonnees()`
/// échoue avec `MissingPluginException` sur `getTemporaryDirectory`.
/// C'est exactement le mécanisme utilisé par `v5_backup_restore_test.dart`.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tmpPath);
  final String tmpPath;

  @override
  Future<String?> getTemporaryPath() async => tmpPath;
}

// FilePicker factice : rend le contenu du fichier exporté sans dialogue.
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this._resultat);
  final FilePickerResult? _resultat;

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
      _resultat;
}

TrackedCourse _ticket({
  String typePari = 'Tiercé Ordre',
  String? codePmuOfficiel = 'E_TIERCE',
  String? varianteChoisie = 'ordre',
  List<int>? numerosDansOrdre = const [3, 1, 5],
  String? storageKey = 'R1C1_21112026_900',
}) =>
    TrackedCourse(
      numReunion: 1,
      numCourse: 1,
      nomCourse: 'Prix de la capture',
      hippodrome: 'Vincennes',
      heureDepart: DateTime(2026, 11, 21, 14, 30),
      storageKey: storageKey,
      nomCheval: 'Cheval 3',
      numeroCheval: 3,
      miseEngagee: 10.0,
      typePari: typePari,
      numerosJoues: const [1, 3, 5],
      codePmuOfficiel: codePmuOfficiel,
      varianteChoisie: varianteChoisie,
      numerosDansOrdre: numerosDansOrdre,
    );

/// Écrit les tickets dans la clé réellement lue par `backup_service`.
Future<void> _installerTickets(List<TrackedCourse> tickets) async {
  SharedPreferences.setMockInitialValues({
    'tracked_courses_v1': tickets.map((t) => json.encode(t.toJson())).toList(),
  });
}

/// Relit les tickets depuis SharedPreferences, comme le fait l'application.
Future<List<TrackedCourse>> _relireTickets() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getStringList('tracked_courses_v1') ?? [];
  return raw
      .map((s) => TrackedCourse.fromJson(json.decode(s) as Map<String, dynamic>))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('4f_backup_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);

    // `AlertService` est un SINGLETON : ses tickets suivis survivent d'un test
    // à l'autre. On le vide par son API publique de reset (celle qu'utilise
    // réellement l'application pour tout effacer), sinon les assertions
    // porteraient sur les tickets d'un test précédent — défaut que j'ai
    // moi-même rencontré ici.
    SharedPreferences.setMockInitialValues({});
    await AlertService.instance.executerResetComplet(() async {});
  });

  tearDown(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  group('4F-E1/8 — export : les nouveaux champs sont dans le fichier', () {
    test('le JSON exporté contient les quatre champs, valeurs comprises',
        () async {
      await _installerTickets([_ticket()]);

      final export = await BackupService.instance.exporterDonnees();
      expect(export.succes, isTrue, reason: 'exporterDonnees a échoué');
      expect(export.filePath, isNotNull);

      final fichier = File(export.filePath!);
      expect(await fichier.exists(), isTrue);

      final contenu =
          json.decode(await fichier.readAsString()) as Map<String, dynamic>;

      // MESURÉ : `tracked_courses_v1` appartient au groupe « alertes »
      // (voir `BackupService._keysAlertes`), et NON au groupe « paris »,
      // qui ne contient que `user_predictions_v2`. Les deux groupes sont
      // exportés de la même façon (liste brute), mais il faut viser le bon.
      final alertes = contenu['alertes'] as Map<String, dynamic>?;
      expect(alertes, isNotNull, reason: 'groupe alertes absent du backup');
      final entree = alertes!['tracked_courses_v1'] as Map<String, dynamic>?;
      expect(entree, isNotNull,
          reason: 'tracked_courses_v1 absent du groupe alertes');
      expect(entree!['type'], 'StringList');

      final liste = List<String>.from(entree['value'] as List);
      expect(liste.length, 1);

      final ticketJson = json.decode(liste.first) as Map<String, dynamic>;
      expect(ticketJson['codePmuOfficiel'], 'E_TIERCE');
      expect(ticketJson['varianteChoisie'], 'ordre');
      expect(ticketJson['numerosDansOrdre'], [3, 1, 5],
          reason: "l'ORDRE doit être présent dans le fichier exporté");
      expect(ticketJson.containsKey('formulePari'), isTrue);
    });
  });

  group('4F-E1/9 — restauration : identité stricte avant / après', () {
    test('export puis restauration rendent un ticket strictement identique',
        () async {
      final origine = _ticket();
      await _installerTickets([origine]);

      final export = await BackupService.instance.exporterDonnees();
      expect(export.succes, isTrue);
      final fichier = File(export.filePath!);
      final octets = await fichier.readAsBytes();

      // ── Appareil vierge : tout est effacé ─────────────────────────────
      SharedPreferences.setMockInitialValues({});
      expect(await _relireTickets(), isEmpty,
          reason: 'état de départ non vide — le test serait muet');

      // ── Restauration par la vraie API publique ────────────────────────
      FilePicker.platform = _FakeFilePicker(FilePickerResult([
        PlatformFile(
          name: export.fileName!,
          size: octets.length,
          bytes: Uint8List.fromList(octets),
        ),
      ]));

      final import = await BackupService.instance.importerDepuisFichier();
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

      final relus = await _relireTickets();
      expect(relus.length, 1, reason: 'le ticket doit être restauré');

      final relu = relus.first;
      // ── Identité stricte des quatre champs ────────────────────────────
      expect(relu.codePmuOfficiel, origine.codePmuOfficiel);
      expect(relu.varianteChoisie, origine.varianteChoisie);
      expect(relu.numerosDansOrdre, origine.numerosDansOrdre,
          reason: "l'ORDRE saisi doit survivre à l'aller-retour complet");
      expect(relu.formulePari, origine.formulePari);

      // ── Identité des champs historiques ───────────────────────────────
      expect(relu.typePari, origine.typePari);
      expect(relu.numerosJoues, origine.numerosJoues);
      expect(relu.storageKey, origine.storageKey);
      expect(relu.miseEngagee, origine.miseEngagee);
    });

    test('variante Désordre et Couplé Ordre survivent aussi', () async {
      await _installerTickets([
        _ticket(
          typePari: 'Tiercé Désordre',
          varianteChoisie: 'desordre',
          numerosDansOrdre: const [5, 1, 3],
          storageKey: 'R1C2_21112026_901',
        ),
        _ticket(
          typePari: 'Couplé Ordre',
          codePmuOfficiel: 'E_COUPLE_ORDRE',
          varianteChoisie: 'ordre',
          numerosDansOrdre: const [7, 2],
          storageKey: 'R1C3_21112026_902',
        ),
      ]);

      final export = await BackupService.instance.exporterDonnees();
      expect(export.succes, isTrue);
      final octets = await File(export.filePath!).readAsBytes();

      SharedPreferences.setMockInitialValues({});
      FilePicker.platform = _FakeFilePicker(FilePickerResult([
        PlatformFile(
          name: export.fileName!,
          size: octets.length,
          bytes: Uint8List.fromList(octets),
        ),
      ]));
      final import = await BackupService.instance.importerDepuisFichier();
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

      final relus = await _relireTickets();
      expect(relus.length, 2);

      expect(relus[0].varianteChoisie, 'desordre');
      expect(relus[0].numerosDansOrdre, const [5, 1, 3]);
      expect(relus[1].varianteChoisie, 'ordre');
      expect(relus[1].numerosDansOrdre, const [7, 2]);
      expect(relus[1].codePmuOfficiel, 'E_COUPLE_ORDRE');
    });
  });

  group('4F-E1/11 — ajouterSuivi : la reconstruction ne perd rien', () {
    test('les quatre champs survivent à ajouterSuivi puis au rechargement',
        () async {
      SharedPreferences.setMockInitialValues({});

      final origine = _ticket();
      await AlertService.instance.ajouterSuivi(origine);

      // 1) Relecture en mémoire : `ajouterSuivi` RECONSTRUIT le ticket
      //    (pour y injecter `storageKey`). C'est le point de perte exact
      //    identifié en 4-F, celui qui avait déjà fait disparaître
      //    `storageKey` (R1) puis la ventilation G+P (B2-C).
      // 2) Relecture depuis le disque : prouve que la persistance suit.
      final relus = await _relireTickets();
      expect(relus.length, 1, reason: 'le ticket doit être persisté');

      final relu = relus.first;
      expect(relu.codePmuOfficiel, 'E_TIERCE',
          reason: 'perdu par la reconstruction de ajouterSuivi');
      expect(relu.varianteChoisie, 'ordre',
          reason: 'perdu par la reconstruction de ajouterSuivi');
      expect(relu.numerosDansOrdre, const [3, 1, 5],
          reason: 'perdu par la reconstruction de ajouterSuivi');
      expect(relu.formulePari, isNull);

      // Les champs historiques restent eux aussi intacts.
      expect(relu.typePari, 'Tiercé Ordre');
      expect(relu.numerosJoues, const [1, 3, 5]);
      expect(relu.miseEngagee, 10.0);
      expect(relu.storageKey, isNotNull,
          reason: 'storageKey est injectée par ajouterSuivi (lot R1)');
    });

    test('un ticket sans capture reste sans capture après ajouterSuivi',
        () async {
      SharedPreferences.setMockInitialValues({});
      await AlertService.instance.ajouterSuivi(_ticket(
        typePari: 'Simple Gagnant',
        codePmuOfficiel: null,
        varianteChoisie: null,
        numerosDansOrdre: null,
      ));

      final relu = (await _relireTickets()).first;
      expect(relu.codePmuOfficiel, isNull);
      expect(relu.varianteChoisie, isNull);
      expect(relu.numerosDansOrdre, isNull);
      expect(relu.formulePari, isNull);
      expect(relu.capturePariComplete, isFalse);
    });
  });

  group('4F-E1/10 — compatibilité des anciennes sauvegardes', () {
    test('un backup SANS les nouveaux champs se restaure sans invention',
        () async {
      // Ticket au format strictement antérieur à 4-F.
      final ancien = <String, dynamic>{
        'numReunion': 2,
        'numCourse': 5,
        'nomCourse': 'Ancienne course',
        'hippodrome': 'Deauville',
        'heureDepart': '2026-11-01T15:00:00.000',
        'typePari': 'Tiercé',
        'numerosJoues': [1, 3, 5],
        'storageKey': 'R2C5_01112026_777',
      };
      SharedPreferences.setMockInitialValues({
        'tracked_courses_v1': [json.encode(ancien)],
      });

      // Format de backup historique : valeur brute, sans enveloppe « type ».
      // `tracked_courses_v1` se restaure depuis le groupe « alertes ».
      final backupAncien = {
        'appName': 'Pronostic Hippique',
        'version': '1.0',
        'dateBackup': '2026-11-01T00:00:00.000',
        'alertes': {
          'tracked_courses_v1': [json.encode(ancien)],
        },
      };

      SharedPreferences.setMockInitialValues({});
      FilePicker.platform = _FakeFilePicker(FilePickerResult([
        PlatformFile(
          name: 'backup_ancien.json',
          size: json.encode(backupAncien).length,
          bytes: Uint8List.fromList(utf8.encode(json.encode(backupAncien))),
        ),
      ]));

      final import = await BackupService.instance.importerDepuisFichier();
      expect(import.succes, isTrue,
          reason: 'un ancien backup doit rester restaurable : ${import.erreur}');

      final relus = await _relireTickets();
      expect(relus.length, 1);
      final relu = relus.first;

      // Aucune valeur inventée : tout reste null.
      expect(relu.codePmuOfficiel, isNull);
      expect(relu.varianteChoisie, isNull);
      expect(relu.numerosDansOrdre, isNull);
      expect(relu.formulePari, isNull);
      // Les données historiques sont intactes.
      expect(relu.typePari, 'Tiercé');
      expect(relu.numerosJoues, const [1, 3, 5]);
      expect(relu.storageKey, 'R2C5_01112026_777');
    });

    test('un ancien ticket est identifié comme capture incomplète', () {
      final ancien = TrackedCourse.fromJson({
        'numReunion': 2,
        'numCourse': 5,
        'nomCourse': 'Ancienne',
        'hippodrome': 'Deauville',
        'heureDepart': '2026-11-01T15:00:00.000',
        'typePari': 'Tiercé Ordre',
        'numerosJoues': [1, 3, 5],
        'storageKey': 'R2C5_01112026_778',
      });
      expect(ancien.capturePariComplete, isFalse,
          reason: 'un ticket non capturé doit rester SIGNALÉ comme tel');
    });
  });
}
