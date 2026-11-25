// ═══════════════════════════════════════════════════════════════════════════
//  V18 — B5 : la réinitialisation complète efface-t-elle les données ELO ?
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/.
//
//  Défaut d'origine (B5) : `_toutesLesCles` (backup_service.dart:329) réunit
//  9 groupes de clés et N'INCLUT PAS `_keysELO`. Les ratings ELO, leur
//  timestamp, les deux clés de cote et la relique `elo_ratings_v1`
//  survivaient donc à `reinitialiserComplet()`.
//
//  Correctif testé :
//    1. `..._keysELO` ajouté à `_toutesLesCles`
//    2. `elo_ratings_v1` ajoutée à `_keysELO`
//    3. `EloService.viderMemoirePourResetComplet()` vide la RAM sans
//       réécrire les anciennes valeurs sur le disque
//
//  Périmètre STRICT : aucune formule ELO, aucun K-factor, aucun poids,
//  aucun seuil, aucun gradient, aucun TOP3, aucune analyseJourneeComplete.
//
//  ⚠️ Ces tests prouvent des observations ciblées, pas le bon
//     fonctionnement global de l'application.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart'; // EloScore
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Faux de plateforme (identiques à V5, aucune logique ré-implémentée)
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
//  Constantes et fabriques
// ───────────────────────────────────────────────────────────────────────────

/// Les 5 clés que le reset complet DOIT effacer.
const List<String> kClesELO = <String>[
  'elo_ratings_v2',
  'elo_ratings_v2_ts',
  'elo_ratings_v1',
  'cote_tracker_mouvements_v1',
  'cote_mouvements_live_v1',
];

/// Ratings de référence — 3 chevaux, identifiables.
const Map<String, double> kEloAttendus = <String, double>{
  'ALPHA|TROT_ATTELE': 1922.5,
  'BRAVO|TROT_ATTELE': 1687.25,
  'CHARLIE|TROT_ATTELE': 1544.75,
};

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('v18_b5_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    EloService.instance.viderMemoirePourResetComplet();
  });

  tearDown(() async {
    EloService.instance.viderMemoirePourResetComplet();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  /// Installe des ratings ELO réels (écrit elo_ratings_v2 et son timestamp).
  Future<void> installerElo(Map<String, double> ratings) async {
    final payload = <String, dynamic>{};
    ratings.forEach((cle, rating) {
      payload[cle] = EloScore(
        nomCheval: cle.split('|').first,
        rating: rating,
        nbCourses: 17,
        variationMois: 12.5,
      ).toJson();
    });
    await EloService.instance.importerDepuisBackup(payload);
  }

  /// Écrit les 3 clés non gérées par EloService (v1 + les deux de cote).
  Future<void> installerClesAnnexes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('elo_ratings_v1',
        json.encode({'ALPHA': {'rating': 1500.0, 'nb': 3}}));
    await prefs.setString('cote_tracker_mouvements_v1',
        json.encode({'R1C1_10032026': []}));
    await prefs.setString('cote_mouvements_live_v1',
        json.encode([{'courseKey': 'R1C1_10032026'}]));
  }

  /// Snapshot des 5 clés telles qu'elles sont SUR LE DISQUE.
  Future<Map<String, Object?>> etatDisque() async {
    final prefs = await SharedPreferences.getInstance();
    return <String, Object?>{
      'elo_ratings_v2': prefs.getString('elo_ratings_v2'),
      'elo_ratings_v2_ts': prefs.getInt('elo_ratings_v2_ts'),
      'elo_ratings_v1': prefs.getString('elo_ratings_v1'),
      'cote_tracker_mouvements_v1':
          prefs.getString('cote_tracker_mouvements_v1'),
      'cote_mouvements_live_v1': prefs.getString('cote_mouvements_live_v1'),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  B5-1 — Le reset complet efface les 5 clés du DISQUE
  // ═══════════════════════════════════════════════════════════════════════
  test('B5-1 — reinitialiserComplet() efface les 5 clés ELO/Cote du disque',
      () async {
    await installerElo(kEloAttendus);
    await installerClesAnnexes();

    final avant = await etatDisque();
    // Contrôle de départ : les 5 clés sont bien présentes.
    for (final cle in kClesELO) {
      expect(avant[cle], isNotNull,
          reason: 'état de départ : $cle doit être sur le disque');
    }
    expect(EloService.instance.exporterPourBackup().length, 3);

    await BackupService.instance.reinitialiserComplet();

    final apres = await etatDisque();
    for (final cle in kClesELO) {
      expect(apres[cle], isNull,
          reason: 'B5 : $cle doit être effacée par un reset « complet »');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B5-2 — Aucune résurrection après un redémarrage simulé
  //
  //  Le scénario redouté : `elo_ratings_v2` effacée mais `elo_ratings_v1`
  //  encore présente → `_charger()` (elo_service.dart:66-83) réimporte les
  //  anciens ratings sous la forme « NOM| ». C'est exactement pourquoi la
  //  clé v1 doit figurer dans `_keysELO`.
  // ═══════════════════════════════════════════════════════════════════════
  test('B5-2 — aucun ancien rating ne ressuscite après redémarrage', () async {
    // La v1 contient des ratings DIFFÉRENTS de la v2 : si elle survit et
    // que la v2 disparaît, la migration les réimportera.
    final prefs0 = await SharedPreferences.getInstance();
    await prefs0.setString('elo_ratings_v1', json.encode({
      'ANCIEN': {'nom': 'ANCIEN', 'rating': 2300.0, 'nb': 42, 'var': 99.0},
    }));
    await installerElo(kEloAttendus);

    expect(EloService.instance.exporterPourBackup().length, 3);

    await BackupService.instance.reinitialiserComplet();

    // ── Redémarrage simulé ──────────────────────────────────────────────
    // Aucune méthode de test n'existe sur EloService et on n'en ajoute pas :
    // on utilise le seul déclencheur public de `_charger()`, à savoir
    // `init()` (l.56), après avoir jeté la RAM. C'est exactement ce que fait
    // le démarrage de l'application.
    EloService.instance.viderMemoirePourResetComplet();
    await EloService.init();

    final apres = EloService.instance.exporterPourBackup();
    expect(apres, isEmpty,
        reason: 'aucun rating ne doit réapparaître : ni ALPHA/BRAVO/CHARLIE '
            '(v2), ni ANCIEN (v1 réimportée par la migration)');
    expect(apres.containsKey('ANCIEN|'), isFalse,
        reason: 'elo_ratings_v1 ne doit pas être réimportée après un reset');
    expect(apres.keys.any((k) => k.startsWith('ALPHA')), isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B5-3 — EloService.reinitialiser() ne fait pas réapparaître les
  //         anciens ratings (une clé '{}' est acceptable)
  // ═══════════════════════════════════════════════════════════════════════
  test('B5-3 — après reset complet, reinitialiser() ne ressuscite aucun '
      "ancien rating (clé '{}' tolérée)", () async {
    await installerElo(kEloAttendus);
    expect(EloService.instance.exporterPourBackup().length, 3);

    await BackupService.instance.reinitialiserComplet();

    // Le point 3 du correctif : la RAM a été vidée, donc reinitialiser()
    // (qui écrit toujours '{}' via _sauvegarder) ne peut réécrire que du
    // vide — jamais les anciens ratings.
    await EloService.instance.reinitialiser();

    final prefs = await SharedPreferences.getInstance();
    final brut = prefs.getString('elo_ratings_v2');

    // Précision demandée : '{}' est ACCEPTABLE si le service l'écrit
    // normalement. On vérifie qu'aucune donnée ancienne n'est revenue.
    if (brut != null) {
      final decode = jsonDecode(brut) as Map<String, dynamic>;
      expect(decode, isEmpty,
          reason: "la clé peut valoir '{}' mais ne doit contenir AUCUN "
              'ancien rating (1922.5, 1687.25, 1544.75)');
    }

    final apres = EloService.instance.exporterPourBackup();
    expect(apres, isEmpty, reason: 'aucun rating ne doit réapparaître');
    for (final ancien in kEloAttendus.keys) {
      expect(brut, isNot(contains(ancien)),
          reason: '$ancien ne doit pas réapparaître sur le disque');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B5-4 — Les réinitialisations PARTIELLES ne touchent pas aux ELO
  //
  //  Non-régression : reinitialiserIA() et reinitialiserParis() ne doivent
  //  PAS hériter du correctif. Seul le reset COMPLET efface les ELO.
  // ═══════════════════════════════════════════════════════════════════════
  test('B5-4 — reinitialiserIA() et reinitialiserParis() préservent les ELO',
      () async {
    await installerElo(kEloAttendus);
    await installerClesAnnexes();
    final avant = await etatDisque();

    await BackupService.instance.reinitialiserIA();
    var apres = await etatDisque();
    for (final cle in kClesELO) {
      expect(apres[cle], avant[cle],
          reason: 'reinitialiserIA() ne doit PAS toucher à $cle');
    }
    expect(EloService.instance.exporterPourBackup().length, 3,
        reason: 'la mémoire ELO survit à reinitialiserIA()');

    await BackupService.instance.reinitialiserParis();
    apres = await etatDisque();
    for (final cle in kClesELO) {
      expect(apres[cle], avant[cle],
          reason: 'reinitialiserParis() ne doit PAS toucher à $cle');
    }
    expect(EloService.instance.exporterPourBackup().length, 3,
        reason: 'la mémoire ELO survit à reinitialiserParis()');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B5-5 — Cycle complet : export → reset → restauration
  // ═══════════════════════════════════════════════════════════════════════
  test('B5-5 — export → reset complet → restauration : les ELO reviennent '
      'à l\'identique', () async {
    await installerElo(kEloAttendus);

    // ── Export ──────────────────────────────────────────────────────────
    final export = await BackupService.instance.exporterDonnees();
    expect(export.succes, isTrue, reason: 'export échoué : ${export.erreur}');
    final bytes = await File(export.filePath!).readAsBytes();
    final contenu =
        json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(contenu.containsKey('elo_service'), isTrue,
        reason: "le backup doit contenir le bloc 'elo_service'");

    // ── Reset complet : les ELO disparaissent du disque ─────────────────
    await BackupService.instance.reinitialiserComplet();
    final disqueApresReset = await etatDisque();
    for (final cle in kClesELO) {
      expect(disqueApresReset[cle], isNull,
          reason: 'après reset, $cle doit être absente du disque');
    }

    // ── Restauration via la VRAIE API publique (FilePicker injecté) ─────
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(
          name: export.fileName!, size: bytes.length, bytes: bytes),
    ]));
    final import = await BackupService.instance.importerDepuisFichier();
    expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

    // ── Les ratings sont intégralement rétablis ────────────────────────
    final restaures = EloService.instance.exporterPourBackup();
    expect(restaures.length, kEloAttendus.length);
    kEloAttendus.forEach((cle, rating) {
      expect(restaures.containsKey(cle), isTrue,
          reason: '$cle doit être restauré');
      final score = EloScore.fromJson(
          restaures[cle] as Map<String, dynamic>);
      expect(score.rating, rating, reason: 'rating de $cle restauré à l\'identique');
      expect(score.nbCourses, 17);
      expect(score.variationMois, 12.5);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B5-6 — L'archive historique survit au reset complet (règle E3/E4)
  // ═══════════════════════════════════════════════════════════════════════
  test('B5-6 — le reset complet ne détruit AUCUNE clé ia_archive_v1_* '
      '(règle E3/E4)', () async {
    final prefs = await SharedPreferences.getInstance();
    // Shards et manifeste factices, avec le préfixe réel.
    await prefs.setString('ia_archive_v1_2026-01', 'shard-janvier');
    await prefs.setString('ia_archive_v1_2026-02', 'shard-fevrier');
    await prefs.setString('ia_archive_v1_manifest', 'manifeste');
    await installerElo(kEloAttendus);

    await BackupService.instance.reinitialiserComplet();

    final prefsApres = await SharedPreferences.getInstance();
    expect(prefsApres.getString('ia_archive_v1_2026-01'), 'shard-janvier',
        reason: 'l\'archive survit : décision E4 non tranchée');
    expect(prefsApres.getString('ia_archive_v1_2026-02'), 'shard-fevrier');
    expect(prefsApres.getString('ia_archive_v1_manifest'), 'manifeste');

    // Et les ELO, eux, sont bien partis.
    expect(prefsApres.getString('elo_ratings_v2'), isNull);
  });
}
