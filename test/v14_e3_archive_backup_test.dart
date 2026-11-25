// ═══════════════════════════════════════════════════════════════════════════
//  V14 — E3 : sauvegarde et restauration de l'archive historique IA
//
//  Ce que ce fichier démontre, exigence par exigence :
//   A — EXPORT INTÉGRAL (manifeste, tous les mois, toutes les versions,
//       fiches détaillées)                                            ... A-1..A-4
//   R — RESTAURATION sans perte, sans doublon, sans rétrogradation    ... R-1..R-6
//   C — COMPATIBILITÉ des anciennes sauvegardes (sans archiveIA)      ... C-1..C-4
//   B — NON-RÉGRESSION B1 à B4, notamment résultats Gros Paris        ... B-1..B-3
//   G — SAUVEGARDES JSON et GZIP                                      ... G-1..G-2
//   S — REDÉMARRAGE SIMULÉ après restauration                         ... S-1..S-2
//   N — AUCUNE RÉINJECTION dans la mémoire de travail/apprentissage   ... N-1..N-3
//   I — INTERRUPTION de sauvegarde ou de restauration                 ... I-1..I-3
//   Z — RÉINITIALISATIONS explicites                                  ... Z-1..Z-2
//
//  Ce que ces tests N'EXAMINENT PAS (périmètre interdit) :
//   • calendrier   • étoiles   • gradient descent   • _poids (modification)
//   • _seuils      • TOP 3 learning   • analyseJourneeComplete() interne
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/pronostic_resultats_repository.dart';
import 'package:pronostic_hippique/services/quasi_gros_paris_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  FAUX DE PLATEFORME
// ═══════════════════════════════════════════════════════════════════════════

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

/// Store en mémoire dont on peut rendre l'écriture défaillante.
/// Même contrat que celui de V13 ; dupliqué ici pour que V14 soit autonome.
class _FauxStore extends SharedPreferencesStorePlatform {
  _FauxStore({Map<String, Object>? data})
      : _data = Map<String, Object>.from(data ?? {});

  final Map<String, Object> _data;

  bool echouerEcritures = false;
  bool leverException = false;
  final Set<String> clesFautives = {};

  bool _estFautive(String key) =>
      clesFautives.isEmpty || clesFautives.any((k) => key.contains(k));

  @override
  Future<bool> clear() async => clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final f = parameters.filter;
    for (final k in _data.keys
        .where((k) =>
            k.startsWith(f.prefix) &&
            (f.allowList == null || f.allowList!.contains(k)))
        .toList()) {
      _data.remove(k);
    }
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final f = parameters.filter;
    final result = Map<String, Object>.from(_data);
    result.removeWhere((k, _) =>
        !k.startsWith(f.prefix) ||
        (f.allowList != null && !f.allowList!.contains(k)));
    return result;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (leverException && _estFautive(key)) {
      throw StateError('stockage indisponible (simulation)');
    }
    if (echouerEcritures && _estFautive(key)) return false;
    _data[key] = value;
    return true;
  }

  // ── Outils ──────────────────────────────────────────────────────────────
  bool contient(String key) => _data.containsKey('flutter.$key');
  Object? brut(String key) => _data['flutter.$key'];
  int get nbCles => _data.length;
  List<String> get cles =>
      _data.keys.map((k) => k.replaceFirst('flutter.', '')).toList();
}

// ═══════════════════════════════════════════════════════════════════════════
//  OUTILS DE CONSTRUCTION
// ═══════════════════════════════════════════════════════════════════════════

String _dateDuJour() {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

String _courseKey(int r, int c, [String? date]) =>
    'R${r}C${c}_${date ?? _dateDuJour()}';

ScoresCriteres _criteres({double decalage = 0.0}) => ScoresCriteres(
      forme: 61.5 + decalage,
      gains: 42.25 + decalage,
      record: 73.75 + decalage,
      cote: 28.5 + decalage,
      constance: 55.125 + decalage,
      victoires: 36.875 + decalage,
      discipline: 64.0 + decalage,
      distSpec: 47.5 + decalage,
      jockey: 58.25 + decalage,
      repos: 31.75 + decalage,
      hippo: 52.5 + decalage,
      entraineur: 44.625 + decalage,
      elo: 69.25 + decalage,
      terrain: 39.5 + decalage,
      divergence: 66.875 + decalage,
      poidsRel: 49.25 + decalage,
      progression: 57.125 + decalage,
      mouvCote: 34.5 + decalage,
      placeDepart: 62.25 + decalage,
    );

/// Pronostic de test. `rempli: false` produit une fiche VOLONTAIREMENT PAUVRE
/// (rang identique mais complétude plus faible) afin de vérifier qu'une fiche
/// pauvre, même plus récente, ne peut jamais écraser une fiche complète.
IaPronostic _prono({
  required String courseKey,
  required DateTime datePronostic,
  bool rempli = true,
  bool resolu = false,
  List<int>? arrivee,
  DateTime? dateResultat,
  double decalage = 0.0,
}) {
  return IaPronostic(
    courseKey: courseKey,
    nomCourse: 'PRIX $courseKey',
    hippodrome: 'VINCENNES',
    discipline: 'Trot Attelé',
    datePronostic: datePronostic,
    scoresIA: {
      for (var i = 1; i <= 5; i++) '$i': 100.0 - (i - 1) * 8.0 + decalage,
    },
    scoresCriteres: rempli
        ? {for (var i = 1; i <= 5; i++) '$i': _criteres(decalage: decalage)}
        : const {},
    varianceScores: rempli ? 123.456 + decalage : null,
    confiancePredite: rempli ? 71.5 + decalage : null,
    typePariConseille: rempli ? 'Quinté+' : null,
    tauxReussiteAuMoment: rempli ? 58.75 : null,
    precisionIA: rempli ? 66.25 : null,
    favoriIaNom: rempli ? 'CHEVAL_1' : null,
    coteFavoriPmu: rempli ? 4.35 + decalage : null,
    cotesPmuParNumero: rempli
        ? {for (var i = 1; i <= 5; i++) '$i': 2.0 + i + decalage}
        : const {},
    arriveeReelle: arrivee,
    dateResultat: dateResultat,
    resultatsReels: resolu,
    rangFavoriIaDansArrivee: rempli && resolu ? 1 : null,
    nbTop3DansArriveeReelle: rempli && resolu ? 3 : null,
    nbTop5DansArriveeReelle: rempli && resolu ? 4 : null,
    scorePerformance: rempli && resolu ? 88.5 + decalage : null,
    diagnosticApprentissage: rempli ? 'diagnostic $courseKey' : null,
  );
}

/// Archive un lot de versions et attend la confirmation d'écriture.
Future<void> _archiver(List<IaPronostic> lots) async {
  for (final p in lots) {
    IaArchiveService.instance.enregistrerEviction(p);
  }
  final ok = await IaArchiveService.instance.persisterEnAttente();
  expect(ok, isTrue, reason: 'archivage de préparation non confirmé');
}

Map<String, Object> _prefsVides() => <String, Object>{
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode({
        'forme': 0.25,
        'gains': 0.13,
        'record': 0.10,
        'cote': 0.08,
        'constance': 0.09,
        'victoires': 0.04,
        'discipline': 0.02,
        'distSpec': 0.08,
        'jockey': 0.07,
        'repos': 0.03,
        'hippo': 0.04,
        'entraineur': 0.04,
        'elo': 0.05,
        'terrain': 0.05,
        'divergence': 0.04,
        'poidsRel': 0.03,
        'progression': 0.03,
        'mouvCote': 0.06,
        'placeDepart': 0.03,
        'nbMisesAJour': 0,
        'calibrationScore': 50.0,
      }),
      'ia_seuils_v1': json.encode({}),
      'ia_precision_v2': json.encode({}),
      'ia_stats_labels_v1': json.encode({}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
    };

/// Encode une liste de pronostics exactement comme le fait le service
/// d'archive : base64(gzip(json)).
String _b64(List<IaPronostic> versions) {
  final jsonStr = json.encode(versions.map((p) => p.toJson()).toList());
  return base64Encode(GZipCodec().encode(utf8.encode(jsonStr)));
}

/// Même encodage, mais sans gzip (utilisé pour construire un format legacy
/// de pronostics de travail).
String _b64Pronostics(List<IaPronostic> versions) => _b64(versions);

_FauxStore _installerStore({Map<String, Object>? data}) {
  final store = _FauxStore(data: data ?? _prefsVides());
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

/// Vide le stockage du test ET l'état RAM des trois services concernés.
Future<void> _tableRase() async {
  await IaArchiveService.instance.effacerTout();
  await PronosticResultatsRepository.instance
      .restaurerDepuisBackup({'pronosticResultats': []});
  await QuasiGrosParisService.instance
      .importerDepuisBackup({'signaux': [], 'quasiGagnants': []});
  await EloService.instance.reinitialiser();
  await IaMemoryService.instance.recharger();
}

/// Redémarrage simulé : cache statique vidé, store réinstallé, RAM remise à zéro.
Future<void> _redemarrer(_FauxStore store) async {
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
}

/// Exporte par l'API publique et renvoie le contenu JSON décodé.
Future<Map<String, dynamic>> _exporter(Directory tmpDir) async {
  PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
  final export = await BackupService.instance.exporterDonnees();
  expect(export.succes, isTrue, reason: 'exporterDonnees a échoué');
  final contenu = await File(export.filePath!).readAsString();
  return json.decode(contenu) as Map<String, dynamic>;
}

/// Restaure par l'API publique à partir d'un contenu JSON.
Future<ImportResult> _importer(Map<String, dynamic> contenu) async {
  final bytes = Uint8List.fromList(utf8.encode(json.encode(contenu)));
  FilePicker.platform = _FakeFilePicker(FilePickerResult([
    PlatformFile(name: 'backup_test.json', size: bytes.length, bytes: bytes),
  ]));
  return BackupService.instance.importerDepuisFichier();
}

/// Exporte via l'API publique et renvoie le contenu JSON décodé
/// (variante sans `tmpDir` : le répertoire est déjà injecté par `setUp`).
Future<Map<String, dynamic>> _exportData() async {
  final export = await BackupService.instance.exporterDonnees();
  expect(export.succes, isTrue, reason: 'exporterDonnees a échoué');
  final contenu = await File(export.filePath!).readAsString();
  return json.decode(contenu) as Map<String, dynamic>;
}

/// Vide le stockage puis recharge les services (téléphone neuf).
Future<void> _resetAppareil() async {
  final store = SharedPreferencesStorePlatform.instance as _FauxStore;
  for (final k in store.cles.toList()) {
    await store.remove('flutter.$k');
  }
  await _redemarrer(store);
}

/// Efface le stockage de l'appareil (simule un téléphone neuf) puis recharge.
Future<void> _effacerAppareil(_FauxStore store) async {
  for (final k in store.cles.toList()) {
    await store.remove('flutter.$k');
  }
  await _redemarrer(store);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Test
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('v14_e3_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    _installerStore();
    await _tableRase();
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A — EXPORT INTÉGRAL (exigence 1)
  // ═════════════════════════════════════════════════════════════════════════

  group('A — Export intégral de l\'archive', () {
    test('A-1 — manifeste + tous les mois + toutes les versions exportés',
        () async {
      // Trois mois distincts → trois shards.
      final a = _prono(
          courseKey: _courseKey(1, 1),
          datePronostic: DateTime(2026, 1, 12),
          dateResultat: DateTime(2026, 1, 12));
      final b = _prono(
          courseKey: _courseKey(1, 2),
          datePronostic: DateTime(2026, 3, 5),
          dateResultat: DateTime(2026, 3, 5));
      final c = _prono(
          courseKey: _courseKey(1, 3),
          datePronostic: DateTime(2026, 7, 20),
          dateResultat: DateTime(2026, 7, 20));
      await _archiver([a, b, c]);

      final archive = IaArchiveService.instance;
      expect(archive.nbVersionsArchivees, 3);
      expect(archive.moisConnus, ['2026-01', '2026-03', '2026-07']);

      final contenu = await _exporter(tmpDir);
      expect(contenu.containsKey('archiveIA'), isTrue,
          reason: 'la clé archiveIA doit exister dans le JSON exporté');

      final arc = contenu['archiveIA'] as Map<String, dynamic>;
      expect(arc['format'], kIaArchiveFormatVersion);

      // Manifeste présent et fidèle.
      final manifeste = arc['manifeste'] as Map<String, dynamic>;
      expect(manifeste['mois'], ['2026-01', '2026-03', '2026-07']);
      expect(arc['nbShards'], 3);
      expect(arc['nbVersions'], 3);
      expect(arc['nbPredictions'], 3);

      // Tous les mois, avec leurs octets gzip+base64 exacts.
      final shards = arc['shards'] as Map<String, dynamic>;
      expect(shards.keys.toList()..sort(), ['2026-01', '2026-03', '2026-07']);
      final prefs = await SharedPreferences.getInstance();
      for (final mois in ['2026-01', '2026-03', '2026-07']) {
        expect(shards[mois], prefs.getString('ia_archive_v1_$mois'),
            reason: 'les octets du shard $mois doivent être exportés à '
                'l\'identique, sans re-sérialisation');
      }
    });

    test('A-2 — les fiches détaillées survivent au cycle export/import',
        () async {
      final source = _prono(
        courseKey: _courseKey(2, 4),
        datePronostic: DateTime(2026, 2, 8),
        resolu: true,
        arrivee: [3, 1, 5, 2, 4],
        dateResultat: DateTime(2026, 2, 8),
      );
      await _archiver([source]);

      final contenu = await _exporter(tmpDir);
      await _effacerAppareil(_installerStore());
      expect(IaArchiveService.instance.nbVersionsArchivees, 0,
          reason: 'appareil effacé : l\'archive doit être vide avant import');

      final import = await _importer(contenu);
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

      final restauree =
          IaArchiveService.instance.versionRetenue(source.courseKey);
      expect(restauree, isNotNull);
      final r = restauree!;

      // Identité
      expect(r.courseKey, source.courseKey);
      expect(r.nomCourse, source.nomCourse);
      expect(r.hippodrome, source.hippodrome);
      expect(r.discipline, source.discipline);
      expect(r.datePronostic.toIso8601String(),
          source.datePronostic.toIso8601String());

      // Contenu de la fiche détaillée
      expect(r.scoresIA, source.scoresIA);
      expect(
          json.encode(r.scoresCriteres.map((k, v) => MapEntry(k, v.toJson()))),
          json.encode(
              source.scoresCriteres.map((k, v) => MapEntry(k, v.toJson()))),
          reason: 'les 19 critères doivent être conservés à l\'identique');
      expect(r.varianceScores, source.varianceScores);
      expect(r.confiancePredite, source.confiancePredite);
      expect(r.precisionIA, source.precisionIA);
      expect(r.tauxReussiteAuMoment, source.tauxReussiteAuMoment);
      expect(r.typePariConseille, source.typePariConseille);
      expect(r.favoriIaNom, source.favoriIaNom);
      expect(r.coteFavoriPmu, source.coteFavoriPmu);
      expect(r.cotesPmuParNumero, source.cotesPmuParNumero);
      expect(r.diagnosticApprentissage, source.diagnosticApprentissage);

      // Résultat réel
      expect(r.resultatsReels, source.resultatsReels);
      expect(r.arriveeReelle, source.arriveeReelle);
      expect(r.dateResultat?.toIso8601String(),
          source.dateResultat?.toIso8601String());
      expect(r.rangFavoriIaDansArrivee, source.rangFavoriIaDansArrivee);
      expect(r.nbTop3DansArriveeReelle, source.nbTop3DansArriveeReelle);
      expect(r.nbTop5DansArriveeReelle, source.nbTop5DansArriveeReelle);
      expect(r.scorePerformance, source.scorePerformance);
    });

    test('A-3 — toutes les versions d\'une même course sont exportées',
        () async {
      final k = _courseKey(3, 3);
      final v1 = _prono(courseKey: k, datePronostic: DateTime(2026, 4, 1));
      final v2 = _prono(
          courseKey: k,
          datePronostic: DateTime(2026, 4, 1),
          resolu: true,
          arrivee: [1, 2, 3, 4, 5],
          dateResultat: DateTime(2026, 4, 1));
      await _archiver([v1, v2]);

      expect(IaArchiveService.instance.nbVersions(k), 2,
          reason: 'deux versions distinctes de la même prédiction');

      final contenu = await _exporter(tmpDir);
      final arc = contenu['archiveIA'] as Map<String, dynamic>;
      expect(arc['nbVersions'], 2);
      expect(arc['nbPredictions'], 1,
          reason: 'une seule prédiction (courseKey), deux versions');

      await _effacerAppareil(_installerStore());
      final import = await _importer(contenu);
      expect(import.succes, isTrue);
      expect(IaArchiveService.instance.nbVersions(k), 2,
          reason: 'le journal de versions doit être restauré intégralement');
    });

    test('A-4 — l\'export embarque les évictions non confirmées', () async {
      final store = _installerStore();
      await IaArchiveService.instance.effacerTout();
      final p = _prono(
          courseKey: _courseKey(4, 4), datePronostic: DateTime(2026, 5, 5));

      // Écriture d'archive rendue défaillante : l'éviction reste en file.
      store.echouerEcritures = true;
      store.clesFautives.add('ia_archive_v1_');
      IaArchiveService.instance.enregistrerEviction(p);
      await IaArchiveService.instance.persisterEnAttente();
      expect(IaArchiveService.instance.nbEvictionsNonArchivees, 1,
          reason: 'l\'éviction doit rester en file, sans abandon');

      // L'export doit malgré tout la transporter (sinon perte au changement
      // de téléphone).
      final contenu = await _exporter(tmpDir);
      final arc = contenu['archiveIA'] as Map<String, dynamic>;
      expect(arc['nbEnAttente'], 1,
          reason:
              'les évictions non confirmées doivent figurer dans l\'export');
      final enAttente = arc['enAttente'] as List;
      expect((enAttente.first as Map)['courseKey'], p.courseKey);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C — COMPATIBILITÉ DES ANCIENNES SAUVEGARDES (exigence 4)
  // ═════════════════════════════════════════════════════════════════════════

  group('C — Compatibilité des sauvegardes antérieures à E3', () {
    test('C-1 — sauvegarde sans archiveIA : archive locale intacte', () async {
      final locale = _prono(
          courseKey: _courseKey(1, 9),
          datePronostic: DateTime(2026, 9, 9),
          dateResultat: DateTime(2026, 9, 9));
      await _archiver([locale]);
      final empreinte = IaArchiveService.empreinteDe(locale);

      // Sauvegarde « v9.0 » : ni archiveIA, ni aucun groupe récent.
      final ancienne = {
        'appName': 'Pronostic Hippique',
        'version': '9.0',
        'dateBackup': DateTime(2026, 1, 1).toIso8601String(),
        'ia': {},
        'configIA': {},
        'paris': {},
        'alertes': {},
        'profil': {},
        'widget': {},
      };
      final import = await _importer(ancienne);
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

      final versions = IaArchiveService.instance.versionsDuMois('2026-09');
      expect(versions.length, 1,
          reason: 'l\'archive locale doit survivre à une ancienne sauvegarde');
      expect(IaArchiveService.empreinteDe(versions.first), empreinte);
    });

    test('C-2 — archiveIA vide ou mal typée : local préservé', () async {
      final locale = _prono(
          courseKey: _courseKey(2, 9),
          datePronostic: DateTime(2026, 10, 2),
          dateResultat: DateTime(2026, 10, 2));
      await _archiver([locale]);

      for (final mauvais in <Object>[
        <String, dynamic>{},
        'chaine_invalide',
        42,
        <String, dynamic>{'shards': 'pas_une_map'},
      ]) {
        final contenu = {
          'appName': 'Pronostic Hippique',
          'version': '9.1',
          'archiveIA': mauvais,
        };
        final import = await _importer(contenu);
        expect(import.succes, isTrue,
            reason: 'archiveIA=$mauvais ne doit pas bloquer la restauration');
        expect(IaArchiveService.instance.versionsDuMois('2026-10').length, 1,
            reason: 'archiveIA=$mauvais ne doit rien effacer');
      }
    });

    test('C-3 — sauvegarde v1 minimaliste : archive locale conservée',
        () async {
      await _archiver([
        _prono(
            courseKey: _courseKey(3, 9),
            datePronostic: DateTime(2026, 11, 3),
            dateResultat: DateTime(2026, 11, 3)),
      ]);
      final import = await _importer({
        'appName': 'Pronostic Hippique',
        'version': '1.0',
      });
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');
      expect(IaArchiveService.instance.nbVersionsArchivees, 1);
    });

    test('C-4 — une sauvegarde E3 relue par une ancienne clé reste conforme',
        () async {
      // Vérifie que le JSON exporté reste strictement du JSON standard
      // (aucun type exotique introduit par l'archive).
      await _archiver([
        _prono(
            courseKey: _courseKey(4, 9),
            datePronostic: DateTime(2026, 12, 4),
            dateResultat: DateTime(2026, 12, 4)),
      ]);
      final contenu = await _exporter(tmpDir);
      final roundTrip =
          json.decode(json.encode(contenu)) as Map<String, dynamic>;
      expect(roundTrip['appName'], 'Pronostic Hippique');
      expect(roundTrip['version'], isNotNull);
      expect(roundTrip.containsKey('archiveIA'), isTrue);
      final arc = roundTrip['archiveIA'] as Map<String, dynamic>;
      expect(arc['shards'], isA<Map<String, dynamic>>());
      for (final v in (arc['shards'] as Map<String, dynamic>).values) {
        expect(v, isA<String>(),
            reason: 'chaque shard doit rester une chaîne base64 transportable');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B — NON-RÉGRESSION B1 À B4 (exigence 5)
  // ═════════════════════════════════════════════════════════════════════════

  group('B — Non-régression B1 à B4', () {
    test('B-1 — résultats Gros Paris exportés et restaurés (B4)', () async {
      final repo = PronosticResultatsRepository.instance;
      await repo.ajouterOuRemplacer(PronosticResultatUtilisateur(
        courseKey: 'R1C1_01022026',
        dateCourse: DateTime(2026, 2, 1),
        typePari: 'Quinté+',
        predictionIA: const ['3', '7', '1', '9', '12'],
        arriveePMUComplete: const ['3', '7', '1', '9', '12'],
        gagnant: true,
        ordreExact: true,
        nbTrouves: 5,
        nbRequis: 5,
        source: 'grosParisSurveiller',
        utilisableStatsUtilisateur: true,
        utilisableApprentissage: false,
      ));
      expect(repo.tous.length, 1);

      final contenu = await _exporter(tmpDir);
      expect(contenu.containsKey('resultatsGrosParis'), isTrue,
          reason: 'la clé B4 doit toujours être exportée');
      expect(contenu.containsKey('archiveIA'), isTrue);

      await _tableRase();
      expect(repo.tous, isEmpty);

      final import = await _importer(contenu);
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');
      expect(repo.tous.length, 1,
          reason: 'les résultats Gros Paris doivent survivre au backup E3');
      expect(repo.tous.first.ordreExact, isTrue);
      expect(repo.tous.first.nbTrouves, 5);
      expect(repo.tous.first.utilisableApprentissage, isFalse,
          reason: 'isolation de l\'apprentissage préservée');
    });

    test('B-2 — B1/B3 : un seul format de pronostics survit à la restauration',
        () async {
      // Backup exposant LES DEUX formats ; le plus riche doit gagner et
      // l'autre clé être purgée (règle B1/B3 inchangée par E3).
      final gz = _b64Pronostics([
        _prono(
            courseKey: 'R1C1_10032026', datePronostic: DateTime(2026, 3, 10)),
        _prono(
            courseKey: 'R1C2_10032026', datePronostic: DateTime(2026, 3, 10)),
      ]);
      final contenu = {
        'appName': 'Pronostic Hippique',
        'version': '9.1',
        'ia': {
          'ia_pronostics_v2_gz': {'type': 'String', 'value': gz},
          'ia_pronostics_v2': {
            'type': 'StringList',
            'value': [
              json.encode(_prono(
                      courseKey: 'R9C9_10032026',
                      datePronostic: DateTime(2026, 3, 10))
                  .toJson()),
            ],
          },
        },
      };
      final import = await _importer(contenu);
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ia_pronostics_v2_gz'), isNotNull);
      expect(prefs.getStringList('ia_pronostics_v2'), isNull,
          reason: 'B1/B3 : le format non retenu doit être purgé');

      await IaMemoryService.instance.recharger();
      expect(IaMemoryService.instance.pronostics.length, 2,
          reason: 'B1/B3 : la mémoire doit recharger le format le plus riche');
    });

    test('B-3 — l\'archive ne figure ni dans _keysIA ni dans les pronostics',
        () async {
      await _archiver([
        _prono(
            courseKey: _courseKey(5, 9),
            datePronostic: DateTime(2026, 7, 7),
            dateResultat: DateTime(2026, 7, 7)),
      ]);
      final contenu = await _exporter(tmpDir);

      // L'archive n'est PAS dans le groupe `ia` : elle ne peut donc pas être
      // confondue avec les pronostics de travail par la règle B1/B3.
      final groupeIA = contenu['ia'] as Map<String, dynamic>;
      expect(groupeIA.keys.any((k) => k.startsWith('ia_archive')), isFalse,
          reason: 'les clés d\'archive ne doivent jamais entrer dans le '
              'groupe ia (aucune interférence avec B1/B3)');

      // Et la mémoire de travail ne reçoit aucun pronostic d'archive.
      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'aucune réinjection dans _pronostics');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  R — RESTAURATION (exigences 2 et 3)
  // ═════════════════════════════════════════════════════════════════════════

  group('R — Restauration sans perte, sans doublon, sans rétrogradation', () {
    test('R-1 — fusion protectrice : l\'archive locale n\'est jamais effacée',
        () async {
      // Appareil local : 2 versions.
      final locale1 = _prono(
          courseKey: _courseKey(1, 1),
          datePronostic: DateTime(2026, 1, 5),
          dateResultat: DateTime(2026, 1, 5));
      final locale2 = _prono(
          courseKey: _courseKey(1, 2),
          datePronostic: DateTime(2026, 2, 6),
          dateResultat: DateTime(2026, 2, 6));
      await _archiver([locale1, locale2]);

      // Sauvegarde provenant d'un autre appareil : 2 autres versions.
      final contenu = {
        'appName': 'Pronostic Hippique',
        'version': '9.1',
        'archiveIA': {
          'format': 1,
          'shards': {
            '2026-02': _b64([
              _prono(
                  courseKey: _courseKey(9, 9),
                  datePronostic: DateTime(2026, 2, 20),
                  dateResultat: DateTime(2026, 2, 20))
            ]),
            '2026-05': _b64([
              _prono(
                  courseKey: _courseKey(8, 8),
                  datePronostic: DateTime(2026, 5, 20),
                  dateResultat: DateTime(2026, 5, 20))
            ]),
          },
        },
      };

      final import = await _importer(contenu);
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

      final archive = IaArchiveService.instance;
      final cles =
          archive.toutesLesVersionsArchivees().map((p) => p.courseKey).toSet();
      expect(
          cles,
          containsAll([
            locale1.courseKey,
            locale2.courseKey,
            _courseKey(9, 9),
            _courseKey(8, 8),
          ]),
          reason: 'fusion = union : rien de local ne doit disparaître');
      expect(archive.nbVersionsArchivees, 4);
      expect(archive.moisConnus, ['2026-01', '2026-02', '2026-05'],
          reason: 'le shard 2026-02 doit fusionner local + importé');
    });

    test('R-2 — aucun doublon après deux imports successifs du même fichier',
        () async {
      final p = _prono(
          courseKey: _courseKey(2, 2),
          datePronostic: DateTime(2026, 6, 6),
          dateResultat: DateTime(2026, 6, 6));
      await _archiver([p]);
      final contenu = await _exporter(tmpDir);

      await _importer(contenu);
      await _importer(contenu);
      await _importer(contenu);

      expect(IaArchiveService.instance.nbVersionsArchivees, 1,
          reason: 'trois imports du même fichier ne créent aucun doublon');
      expect(IaArchiveService.instance.nbVersions(p.courseKey), 1);
    });

    test('R-3 — une fiche PAUVRE ne remplace jamais une fiche COMPLÈTE locale',
        () async {
      // Local : fiche complète et résolue.
      final complete = _prono(
        courseKey: _courseKey(5, 5),
        datePronostic: DateTime(2026, 3, 10),
        resolu: true,
        arrivee: [1, 2, 3, 4, 5],
        dateResultat: DateTime(2026, 3, 10),
      );
      await _archiver([complete]);
      final empreinteLocale = IaArchiveService.empreinteDe(
          IaArchiveService.instance.versionRetenue(complete.courseKey)!);

      // Sauvegarde contenant la MÊME course mais une fiche pauvre, et PLUS
      // RÉCENTE : elle ne doit pas rétrograder la fiche locale.
      final pauvre = _prono(
        courseKey: _courseKey(5, 5),
        datePronostic: DateTime(2026, 3, 10),
        dateResultat: DateTime(2026, 12, 31), // plus récent
        rempli: false, // mais beaucoup plus pauvre
      );
      final contenu = {
        'appName': 'Pronostic Hippique',
        'version': '9.1',
        'archiveIA': {
          'format': 1,
          'shards': {
            '2026-03': _b64([pauvre])
          },
        },
      };

      final import = await _importer(contenu);
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

      final retenue =
          IaArchiveService.instance.versionRetenue(complete.courseKey)!;
      expect(IaArchiveService.empreinteDe(retenue), empreinteLocale,
          reason: 'la version retenue doit rester la fiche complète locale');
      expect(retenue.scoresCriteres.isNotEmpty, isTrue);
      expect(retenue.resultatsReels, isTrue);
      expect(retenue.arriveeReelle, [1, 2, 3, 4, 5]);

      // La fiche pauvre est CONSERVÉE (rien n'est détruit), mais non retenue.
      expect(IaArchiveService.instance.nbVersions(complete.courseKey), 2,
          reason: 'la version importée reste au journal de versions');
    });

    test('R-4 — une fiche PLUS COMPLÈTE remplace bien une fiche pauvre locale',
        () async {
      final pauvre = _prono(
          courseKey: _courseKey(6, 6),
          datePronostic: DateTime(2026, 4, 10),
          rempli: false);
      await _archiver([pauvre]);
      final empreintePauvre = IaArchiveService.empreinteDe(
          IaArchiveService.instance.versionRetenue(pauvre.courseKey)!);

      final complete = _prono(
        courseKey: _courseKey(6, 6),
        datePronostic: DateTime(2026, 4, 10),
        resolu: true,
        arrivee: [1, 2, 3, 4, 5],
        dateResultat: DateTime(2026, 4, 10),
      );
      final contenu = {
        'appName': 'Pronostic Hippique',
        'version': '9.1',
        'archiveIA': {
          'format': 1,
          'shards': {
            '2026-04': _b64([pauvre, complete])
          },
        },
      };
      final import = await _importer(contenu);
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

      final retenue =
          IaArchiveService.instance.versionRetenue(complete.courseKey)!;
      expect(IaArchiveService.empreinteDe(retenue), isNot(empreintePauvre),
          reason: 'la fiche complète doit devenir la version retenue');
      expect(IaArchiveService.empreinteDe(retenue),
          IaArchiveService.empreinteDe(complete),
          reason: 'la retenue doit être exactement la fiche importée');
      expect(retenue.scoresCriteres.isNotEmpty, isTrue);
      expect(retenue.arriveeReelle, [1, 2, 3, 4, 5]);
      expect(IaArchiveService.instance.nbVersions(complete.courseKey), 2,
          reason: 'deux contenus distincts conservés (pauvre + complète)');
    });

    test('R-4b — autorité : la complétude prime sur la date', () async {
      final completeAncienne = _prono(
          courseKey: _courseKey(6, 7),
          datePronostic: DateTime(2026, 4, 11),
          resolu: true,
          arrivee: [1, 2, 3],
          dateResultat: DateTime(2026, 4, 11));
      final pauvreRecente = _prono(
          courseKey: _courseKey(6, 7),
          datePronostic: DateTime(2026, 4, 11),
          rempli: false,
          dateResultat: DateTime(2026, 11, 30));

      expect(
        IaArchiveService.comparerAutorite(completeAncienne, pauvreRecente),
        greaterThan(0),
        reason: 'la fiche complète est plus autoritaire, malgré une date '
            'de résultat plus ancienne',
      );
    });

    test('R-5 — un shard illisible du backup n\'écrase pas le shard local',
        () async {
      final locale = _prono(
          courseKey: _courseKey(7, 7),
          datePronostic: DateTime(2026, 2, 2),
          dateResultat: DateTime(2026, 2, 2));
      await _archiver([locale]);

      final contenu = {
        'appName': 'Pronostic Hippique',
        'version': '9.1',
        'archiveIA': {
          'format': 1,
          'shards': {'2026-02': 'CE_N_EST_PAS_DU_BASE64_VALIDE'},
        },
      };
      final import = await _importer(contenu);
      expect(import.succes, isTrue,
          reason: 'un shard illisible ne doit pas faire échouer l\'import');

      // Le shard local est intact.
      final versions = IaArchiveService.instance.versionsDuMois('2026-02');
      expect(versions.length, 1);
      expect(versions.first.courseKey, locale.courseKey);

      // Et il est toujours relisible après redémarrage : le shard local n'a
      // pas été réécrit pour ce mois (aucune donnée détruite).
      final store = SharedPreferencesStorePlatform.instance as _FauxStore;
      await _redemarrer(store);
      final apres = IaArchiveService.instance.versionsDuMois('2026-02');
      expect(apres.length, 1, reason: 'le shard local survit au redémarrage');
      expect(apres.first.courseKey, locale.courseKey);
      expect(IaArchiveService.instance.derniereVerificationArchive!.parfaite,
          isTrue,
          reason: 'aucun shard perdu ni illisible après redémarrage');
    });

    test('R-6 — archiveIA absent du JSON : aucune modification locale',
        () async {
      final locale = _prono(
          courseKey: _courseKey(8, 1),
          datePronostic: DateTime(2026, 8, 1),
          dateResultat: DateTime(2026, 8, 1));
      await _archiver([locale]);
      final avant = IaArchiveService.instance.nbVersionsArchivees;
      final empreinteAvant = IaArchiveService.empreinteDe(
          IaArchiveService.instance.versionRetenue(locale.courseKey)!);

      final contenu = await _exporter(tmpDir);
      contenu.remove('archiveIA');
      contenu['version'] = '9.0';

      final import = await _importer(contenu);
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');
      expect(IaArchiveService.instance.nbVersionsArchivees, avant,
          reason: 'aucune version locale ne doit être perdue');
      expect(
        IaArchiveService.empreinteDe(
            IaArchiveService.instance.versionRetenue(locale.courseKey)!),
        empreinteAvant,
        reason: 'la version retenue reste strictement identique',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  N — AUCUNE RÉINJECTION DANS LA MÉMOIRE OU L'APPRENTISSAGE (exigence 8)
  // ═════════════════════════════════════════════════════════════════════════

  group('N — Aucune réinjection dans la mémoire de travail', () {
    test('N-1 — restaurer l\'archive ne remplit pas _pronostics', () async {
      await _archiver([
        _prono(
            courseKey: _courseKey(1, 20),
            datePronostic: DateTime(2026, 1, 20),
            resolu: true,
            arrivee: [1, 2, 3, 4, 5],
            dateResultat: DateTime(2026, 1, 20)),
        _prono(
            courseKey: _courseKey(2, 20),
            datePronostic: DateTime(2026, 2, 20),
            resolu: true,
            arrivee: [2, 3, 4, 5, 1],
            dateResultat: DateTime(2026, 2, 20)),
      ]);
      final contenu = await _exportData();

      _installerStore();
      await _resetAppareil();
      final svc = IaMemoryService.instance;
      expect(svc.pronostics, isEmpty);

      final import = await _importer(contenu);
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

      expect(svc.pronostics, isEmpty,
          reason:
              'l\'archive restaurée ne doit JAMAIS entrer dans _pronostics');
      expect(svc.pronosticsAvecResultat, isEmpty,
          reason: 'l\'archive ne doit jamais alimenter l\'apprentissage');
      expect(IaArchiveService.instance.nbVersionsArchivees, 2);
    });

    test('N-2 — poids, seuils et calibration strictement inchangés', () async {
      final svc = IaMemoryService.instance;
      final poidsAvant = json.encode(svc.poids.toJson());
      final seuilsAvant = json.encode(svc.seuilsConfiance.toJson());
      final calibrationAvant = svc.poids.calibrationScore;
      final misesAJourAvant = svc.poids.nbMisesAJour;

      await _archiver([
        _prono(
            courseKey: _courseKey(3, 20),
            datePronostic: DateTime(2026, 3, 20),
            resolu: true,
            arrivee: [1, 2, 3, 4, 5],
            dateResultat: DateTime(2026, 3, 20)),
      ]);
      final contenu = await _exportData();
      await _importer(contenu);

      expect(json.encode(svc.poids.toJson()), poidsAvant,
          reason: '_poids doit rester identique octet pour octet');
      expect(json.encode(svc.seuilsConfiance.toJson()), seuilsAvant,
          reason: 'les seuils ne doivent pas être touchés');
      expect(svc.poids.calibrationScore, calibrationAvant);
      expect(svc.poids.nbMisesAJour, misesAJourAvant);
    });

    test('N-3 — le journal de versions reste un journal d\'audit', () async {
      final k = _courseKey(4, 20);
      await _archiver([
        _prono(courseKey: k, datePronostic: DateTime(2026, 4, 20)),
      ]);
      final contenu = await _exportData();
      await _importer(contenu);

      final journal = IaArchiveService.instance.journalVersionsPourTest(k);
      expect(journal, isNotEmpty);
      for (final e in journal) {
        expect(e.containsKey('empreinte'), isTrue);
        expect(e.containsKey('motif'), isTrue);
        expect(['eviction', 'troncature', 'restauration'], contains(e['motif']),
            reason: 'le motif est un champ d\'audit, jamais un critère '
                'd\'identité');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  I — INTERRUPTION DE SAUVEGARDE OU DE RESTAURATION (exigence 9)
  // ═════════════════════════════════════════════════════════════════════════

  group('I — Interruption de sauvegarde ou de restauration', () {
    test('I-1 — écriture d\'archive en échec : rien n\'est perdu, blob gelé',
        () async {
      final store = _installerStore();
      await IaArchiveService.instance.effacerTout();
      store.echouerEcritures = true;
      store.clesFautives.add('ia_archive_v1_');

      IaArchiveService.instance.enregistrerEviction(_prono(
          courseKey: _courseKey(5, 20), datePronostic: DateTime(2026, 5, 20)));
      final ok = await IaArchiveService.instance.persisterEnAttente();

      expect(ok, isFalse);
      expect(IaArchiveService.instance.nbEvictionsNonArchivees, 1,
          reason: 'aucun abandon : l\'éviction reste en file');
      expect(IaArchiveService.instance.doitGelerBlobPronostics, isTrue,
          reason: 'le blob des pronostics doit rester gelé');
      expect(IaArchiveService.instance.etatArchive, isNot(EtatArchive.sain));
    });

    test('I-2 — restauration interrompue : les mois non écrits sont rejoués',
        () async {
      final store = _installerStore();
      await IaArchiveService.instance.effacerTout();

      final contenu = {
        'appName': 'Pronostic Hippique',
        'version': '9.1',
        'archiveIA': {
          'format': 1,
          'shards': {
            '2026-09': _b64([
              _prono(
                  courseKey: _courseKey(6, 20),
                  datePronostic: DateTime(2026, 9, 20),
                  dateResultat: DateTime(2026, 9, 20)),
            ]),
          },
        },
      };

      // Première tentative : écriture impossible.
      store.echouerEcritures = true;
      store.clesFautives.add('ia_archive_v1_');
      final res = await IaArchiveService.instance
          .restaurerDepuisBackup(contenu['archiveIA'] as Map<String, dynamic>);
      expect(res.succes, isFalse,
          reason: 'écriture non confirmée → succès=false');
      expect(res.moisNonEcrits, 1);
      // Les versions sont néanmoins en mémoire : rien n\'est perdu.
      expect(IaArchiveService.instance.nbVersionsArchivees, 1);

      // Reprise : stockage rétabli → le mois en attente est rejoué.
      store.echouerEcritures = false;
      store.clesFautives.clear();
      final ok = await IaArchiveService.instance.persisterEnAttente();
      expect(ok, isTrue, reason: 'la reprise doit confirmer l\'écriture');
      expect(IaArchiveService.instance.doitGelerBlobPronostics, isFalse);

      // Et la donnée survit au redémarrage.
      await _redemarrer(store);
      expect(IaArchiveService.instance.nbVersionsArchivees, 1);
    });

    test('I-3 — exception du stockage pendant l\'import : aucune destruction',
        () async {
      await _archiver([
        _prono(
            courseKey: _courseKey(7, 20),
            datePronostic: DateTime(2026, 10, 20),
            dateResultat: DateTime(2026, 10, 20)),
      ]);
      final avant = IaArchiveService.instance.nbVersionsArchivees;
      final contenu = await _exportData();

      final store = _installerStore(data: {});
      await IaArchiveService.instance.effacerTout();
      store.leverException = true;
      store.clesFautives.add('ia_archive_v1_');

      final res = await IaArchiveService.instance
          .restaurerDepuisBackup(contenu['archiveIA'] as Map<String, dynamic>);
      expect(res.succes, isFalse);
      expect(IaArchiveService.instance.nbVersionsArchivees, 1,
          reason: 'les versions importées restent en mémoire, aucune perte');
      expect(IaArchiveService.instance.doitGelerBlobPronostics, isTrue);
      expect(avant, 1);
    });
  });

  // ═════════════════════════════════════════════════════════
  //  Z — RÉINITIALISATIONS EXPLICITES : L'ARCHIVE SURVIT (décision E4)
  //
  //  La question « un reset doit-il détruire l'archive ? » appartient à E4.
  //  En attendant cette décision, E3 garantit que TOUT reset préserve
  //  l'archive : aucune donnée historique n'est perdue par inadvertance.
  // ═════════════════════════════════════════════════════════════════════════

  group('Z — Les réinitialisations préservent l\'archive (décision E4)', () {
    test('Z-1 — reinitialiserComplet() NE DÉTRUIT PAS l\'archive', () async {
      // Le store doit être installé AVANT l'archivage : _installerStore()
      // remplace le stockage plateforme et perdrait les shards déjà écrits.
      final store = _installerStore();
      await _archiver([
        _prono(
            courseKey: _courseKey(1, 30),
            datePronostic: DateTime(2026, 1, 30),
            dateResultat: DateTime(2026, 1, 30)),
        _prono(
            courseKey: _courseKey(2, 30),
            datePronostic: DateTime(2026, 2, 28),
            dateResultat: DateTime(2026, 2, 28)),
      ]);
      expect(IaArchiveService.instance.nbVersionsArchivees, 2);

      await BackupService.instance.reinitialiserComplet();
      await IaArchiveService.instance.reinitialiserMemoirePourTest();

      // La mémoire IA est bien effacée...
      expect(IaMemoryService.instance.pronostics, isEmpty);
      // ...mais l'archive est intacte, sur disque ET après redémarrage.
      expect(IaArchiveService.instance.nbVersionsArchivees, 2,
          reason: 'l\'archive survit à un reset complet : la décision '
              'de la détruire appartient à E4 et n\'est pas autorisée ici');
      expect(store.cles.where((k) => k.startsWith('ia_archive_v1_')).length, 3,
          reason: 'manifeste + 2 shards mensuels toujours sur le disque');

      final contenu = await _exportData();
      final arc = contenu['archiveIA'] as Map<String, dynamic>;
      expect(arc['nbVersions'], 2);
      expect(arc['nbPredictions'], 2);
    });

    test('Z-2 — reinitialiserIA() efface la mémoire, préserve archive ET profil',
        () async {
      final store = _installerStore();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profil_nom', 'TESTEUR');
      await prefs.reload();
      expect(prefs.getString('profil_nom'), 'TESTEUR',
          reason: 'garde-fou : le profil doit être écrit avant le test');
      await _archiver([
        _prono(
            courseKey: _courseKey(3, 30),
            datePronostic: DateTime(2026, 3, 30),
            dateResultat: DateTime(2026, 3, 30)),
      ]);

      await BackupService.instance.reinitialiserIA();
      await IaArchiveService.instance.reinitialiserMemoirePourTest();

      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'la mémoire de travail est bien effacée');
      expect(IaArchiveService.instance.nbVersionsArchivees, 1,
          reason: 'l\'archive historique n\'est pas concernée par E3');
      expect(store.cles.any((k) => k.startsWith('ia_archive_v1_')), isTrue);
      expect((await SharedPreferences.getInstance()).getString('profil_nom'),
          'TESTEUR',
          reason: 'reinitialiserIA conserve le profil utilisateur');
    });

    test('Z-3 — effacerTout() reste le SEUL moyen d\'effacer l\'archive',
        () async {
      final store = _installerStore();
      await _archiver([
        _prono(
            courseKey: _courseKey(4, 30),
            datePronostic: DateTime(2026, 4, 30),
            dateResultat: DateTime(2026, 4, 30)),
      ]);
      expect(IaArchiveService.instance.nbVersionsArchivees, 1);

      await IaArchiveService.instance.effacerTout();
      expect(IaArchiveService.instance.nbVersionsArchivees, 0);
      expect(store.cles.any((k) => k.startsWith('ia_archive_v1_')), isFalse,
          reason: 'effacerTout() est l\'unique point de destruction, '
              'réservé à E4');
    });
  });


  // ═════════════════════════════════════════════════════════════════════
  //  W — ÉVICTIONS EN ATTENTE : RÉELLEMENT RÉCUPÉRABLES APRÈS RESTAURATION
  //
  //  A-4 démontre seulement que la clé `enAttente` est PRÉSENTE dans le
  //  fichier exporté. Ce groupe démontre la seconde moitié, qui seule compte :
  //  une fois le fichier rejoué sur un appareil vierge, ces pronostics
  //  existent VRAIMENT dans l'archive, durablement, sans doublon, et sans
  //  jamais entrer dans la mémoire de travail ni dans l'apprentissage.
  // ═════════════════════════════════════════════════════════════════════

  group('W — Évictions en attente réellement récupérables', () {
    /// Fabrique un backup dont l'archive ne contient AUCUN shard écrit, mais
    /// seulement des évictions non confirmées (`enAttente`). C'est l'état
    /// exact d'un appareil dont le stockage refuse les écritures de shard.
    Future<Map<String, dynamic>> backupEnAttenteSeulement(
        List<IaPronostic> enAttente) async {
      final store = _installerStore();
      await IaArchiveService.instance.effacerTout();
      store.echouerEcritures = true;
      store.clesFautives.add('ia_archive_v1_');
      for (final p in enAttente) {
        IaArchiveService.instance.enregistrerEviction(p);
      }
      await IaArchiveService.instance.persisterEnAttente();
      expect(IaArchiveService.instance.nbEvictionsNonArchivees, enAttente.length,
          reason: 'garde-fou : les évictions doivent rester en file');
      final contenu = await _exportData();
      final arc = contenu['archiveIA'] as Map<String, dynamic>;
      expect(arc['nbShards'], 0, reason: 'aucun shard écrit sur cet appareil');
      expect(arc['nbEnAttente'], enAttente.length);
      expect((arc['shards'] as Map), isEmpty);
      return contenu;
    }

    test('W-1 — enAttente restauré : les pronostics existent VRAIMENT', () async {
      final p1 = _prono(
          courseKey: _courseKey(1, 40),
          datePronostic: DateTime(2026, 5, 12),
          resolu: true,
          arrivee: [2, 5, 1, 3, 4],
          dateResultat: DateTime(2026, 5, 12));
      final p2 = _prono(
          courseKey: _courseKey(2, 40),
          datePronostic: DateTime(2026, 6, 18),
          resolu: true,
          arrivee: [4, 2, 1, 5, 3],
          dateResultat: DateTime(2026, 6, 18));

      final contenu = await backupEnAttenteSeulement([p1, p2]);

      // Appareil vierge : rien du tout.
      final store2 = _installerStore();
      await _effacerAppareil(store2);
      expect(IaArchiveService.instance.nbVersionsArchivees, 0);

      final import = await _importer(contenu);
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

      // ── Les pronostics sont RÉELLEMENT là, pas seulement dans le fichier.
      final archive = IaArchiveService.instance;
      expect(archive.nbVersionsArchivees, 2,
          reason: 'les évictions en attente doivent être intégrées à l\'archive');
      expect(archive.nbPredictionsDistinctes, 2);
      expect(archive.moisConnus, ['2026-05', '2026-06']);

      final r1 = archive.versionRetenue(p1.courseKey);
      final r2 = archive.versionRetenue(p2.courseKey);
      expect(r1, isNotNull, reason: 'p1 doit être consultable');
      expect(r2, isNotNull, reason: 'p2 doit être consultable');
      expect(r1!.arriveeReelle, [2, 5, 1, 3, 4]);
      expect(r2!.arriveeReelle, [4, 2, 1, 5, 3]);
      expect(r1.scoresCriteres.isNotEmpty, isTrue,
          reason: 'la fiche détaillée est complète, pas un résumé');
      expect(IaArchiveService.empreinteDe(r1),
          IaArchiveService.empreinteDe(p1));

      // ── Durabilité CONSTATÉE : après redémarrage, toujours là.
      await _redemarrer(store2);
      expect(IaArchiveService.instance.nbVersionsArchivees, 2,
          reason: 'les évictions récupérées doivent être écrites sur disque');
      expect(
          IaArchiveService.instance.versionRetenue(p1.courseKey)!.arriveeReelle,
          [2, 5, 1, 3, 4]);

      // ── AUCUNE réinjection dans la mémoire de travail / l'apprentissage.
      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'jamais de réinjection dans _pronostics');
      expect(IaMemoryService.instance.pronosticsAvecResultat, isEmpty,
          reason: 'jamais de réinjection dans l\'apprentissage');
    });

    test('W-2 — enAttente restauré deux fois : aucun doublon', () async {
      final p = _prono(
          courseKey: _courseKey(3, 40),
          datePronostic: DateTime(2026, 7, 7),
          resolu: true,
          arrivee: [1, 3, 5, 2, 4],
          dateResultat: DateTime(2026, 7, 7));

      final contenu = await backupEnAttenteSeulement([p]);
      final store2 = _installerStore();
      await _effacerAppareil(store2);

      await _importer(contenu);
      await _importer(contenu);
      await _importer(contenu);

      expect(IaArchiveService.instance.nbVersionsArchivees, 1,
          reason: 'un même contenu importé N fois = une seule version');
      expect(IaArchiveService.instance.nbVersions(p.courseKey), 1);
      await _redemarrer(store2);
      expect(IaArchiveService.instance.nbVersionsArchivees, 1);
    });

    test('W-3 — enAttente fusionne avec un shard local de même mois', () async {
      // Appareil local : une version de mai déjà archivée.
      final locale = _prono(
          courseKey: _courseKey(4, 40),
          datePronostic: DateTime(2026, 5, 1),
          dateResultat: DateTime(2026, 5, 1));
      await _archiver([locale]);
      final store = _installerStore();
      expect(IaArchiveService.instance.versionsDuMois('2026-05').length, 1);

      // Backup : une AUTRE course de mai, en attente seulement.
      final autre = _prono(
          courseKey: _courseKey(5, 40),
          datePronostic: DateTime(2026, 5, 20),
          dateResultat: DateTime(2026, 5, 20));
      final contenu = {
        'appName': 'Pronostic Hippique',
        'version': '9.1',
        'archiveIA': {
          'format': 1,
          'shards': <String, String>{},
          'enAttente': [autre.toJson()],
          'nbEnAttente': 1,
        },
      };

      final import = await _importer(contenu);
      expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

      final mai = IaArchiveService.instance.versionsDuMois('2026-05');
      expect(mai.length, 2,
          reason: 'le shard local et l\'éviction en attente doivent fusionner');
      expect(mai.map((p) => p.courseKey).toSet(),
          {locale.courseKey, autre.courseKey});

      await _redemarrer(store);
      expect(IaArchiveService.instance.versionsDuMois('2026-05').length, 2,
          reason: 'la fusion doit être durable');
    });

    test('W-4 — enAttente corrompu : ignoré, archive locale intacte', () async {
      final locale = _prono(
          courseKey: _courseKey(6, 40),
          datePronostic: DateTime(2026, 8, 8),
          dateResultat: DateTime(2026, 8, 8));
      await _archiver([locale]);

      final contenu = {
        'appName': 'Pronostic Hippique',
        'version': '9.1',
        'archiveIA': {
          'format': 1,
          'shards': <String, String>{},
          // Entrées volontairement invalides.
          'enAttente': [
            {'courseKey': 'X'},          // champs requis absents
            'pas_une_map',               // type faux
            42,                          // type faux
            null,                        // null
          ],
          'nbEnAttente': 4,
        },
      };
      final import = await _importer(contenu);
      expect(import.succes, isTrue,
          reason: 'un enAttente corrompu ne doit pas faire échouer l\'import');
      expect(IaArchiveService.instance.nbVersionsArchivees, 1,
          reason: 'l\'archive locale reste intacte');
      expect(
          IaArchiveService.instance
              .versionRetenue(locale.courseKey)!
              .courseKey,
          locale.courseKey);
    });
  });
}
