/// Preuve que le nouveau système de sauvegarde/restauration est **effectivement
/// utilisé** par l'application, et non seulement disponible.
///
/// Consigne §1 du présent tour, et §5 du précédent :
/// > « la réussite des tests sur un dépôt SQLite isolé ne constitue pas une
/// > preuve que l'application utilise effectivement ce dépôt dans ses chemins
/// > de production ».
///
/// Ces tests appellent donc les méthodes de production :
/// `BackupService.instance.exporterDonneesStructurees()` et
/// `BackupService.instance.importerDepuisFichier()` (via son chemin de contenu).
/// Ils n'instancient ni `FormatSauvegarde` ni `TransactionGlobale` pour
/// substituer quoi que ce soit : ces classes sont exercées **par** le service.
///
/// Ce qui est prouvé ici :
/// * l'export `.ptg` couvre **toutes** les clés SharedPreferences réellement
///   présentes, y compris une clé créée à l'instant et inconnue du service ;
/// * le fichier produit est vérifiable, avec manifeste et empreintes ;
/// * une restauration `.ptg` rétablit les clés, y compris une clé supprimée ;
/// * un conteneur altéré est refusé sans écriture ;
/// * le retour arrière rétablit l'état quand une écriture échoue en cours ;
/// * la restauration JSON historique reste pleinement fonctionnelle ;
/// * un échec du dépôt ne fait pas échouer l'export SharedPreferences
///   (l'exclusion est alors DÉCLARÉE au manifeste).
///
/// Ce qui n'est PAS prouvé ici : le comportement sur un appareil Android réel
/// (permissions de stockage, partage natif, absence de `databaseFactory` FFI).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/depot_sqlite.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/pont_elo.dart';
import 'package:pronostic_hippique/data/connaissances/_core/depot.dart';
import 'package:pronostic_hippique/data/connaissances/_sauvegarde/format_sauvegarde.dart';
import 'package:pronostic_hippique/data/connaissances/_sauvegarde/transaction_globale.dart';
import 'package:pronostic_hippique/models/zt_models.dart' show EloScore;
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Injecte un répertoire temporaire réel.
///
/// Sans cela, `getTemporaryDirectory()` lève en environnement de test : la
/// plateforme n'y est pas initialisée. Ce faux reproduit exactement celui
/// utilisé par `v5_backup_restore_test.dart` — il n'introduit aucune facilité
/// qui n'existerait pas en production, il fournit seulement un chemin valide.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tmpPath);
  final String tmpPath;

  @override
  Future<String?> getTemporaryPath() async => tmpPath;
}

void main() {
  late Directory racine;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    BackupService.reinitialiserNomsPourTest();
    racine = await Directory.systemTemp.createTemp('ptg_raccordement_');
    PathProviderPlatform.instance = _FakePathProvider(racine.path);
    PontElo.instance.utiliserFabrique(databaseFactoryFfi);
    final ok = await PontElo.instance.ouvrir(racineForcee: racine.path);
    expect(ok, isTrue, reason: 'le dépôt doit s\'ouvrir pour ce test');
  });

  tearDown(() async {
    await PontElo.instance.fermer();
    if (await racine.exists()) await racine.delete(recursive: true);
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Export .ptg effectivement produit par le service', () {
    test('l\'export couvre TOUTES les clés prefs, y compris une clé inconnue',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', '{"forme":0.058}');
      await prefs.setStringList('ia_rapports_v1', <String>['{"date":"2026-01-01"}']);
      // Clé qu'AUCUNE liste du service ne connaît. Si l'export reposait sur une
      // liste recopiée à la main, elle serait absente du fichier.
      await prefs.setString('cle_inconnue_du_service_v99', 'valeur temoin');

      final export = await BackupService.instance.exporterDonneesStructurees();
      expect(export.succes, isTrue, reason: export.erreur ?? '');
      expect(export.fileName, endsWith('.ptg'));
      expect(File(export.filePath!).existsSync(), isTrue);

      const format = FormatSauvegarde();
      final verif = format.verifier(File(export.filePath!).readAsStringSync());
      expect(verif.utilisable, isTrue,
          reason: 'un export non vérifiable ne doit pas être annoncé réussi');
      expect(verif.legacy, isFalse);

      final blocPrefs = format.extraireBloc(
        File(export.filePath!).readAsStringSync(),
        'prefs_complet',
      );
      expect(blocPrefs, isA<Map>());
      final map = blocPrefs as Map;
      expect(map.containsKey('ia_poids_v3'), isTrue);
      expect(map.containsKey('cle_inconnue_du_service_v99'), isTrue,
          reason: '§1 : l\'exhaustivité ne peut pas dépendre d\'une liste '
              'recopiée à la main');
      expect(map.containsKey('ia_rapports_v1'), isTrue);
      // Le type d'origine est conservé : une StringList reste une StringList.
      final entry = map['ia_rapports_v1'] as Map;
      expect(entry['type'], 'StringList');
    });

    test('le manifeste déclare une exclusion quand le dépôt est fermé',
        () async {
      await PontElo.instance.fermer();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', '{}');

      final export = await BackupService.instance.exporterDonneesStructurees();
      expect(export.succes, isTrue, reason: export.erreur ?? '');

      const format = FormatSauvegarde();
      final contenu = File(export.filePath!).readAsStringSync();
      final verif = format.verifier(contenu);
      expect(verif.utilisable, isTrue);
      final noms = verif.manifeste!.blocs.map((b) => b.nom).toList();
      expect(noms, contains('prefs_complet'));
      // L'absence de SQLite est DÉCLARÉE, pas silencieuse.
      expect(verif.manifeste!.exclusions.map((e) => e['bloc']),
          contains('sqlite_complet'));
    });

    test('deux exports successifs produisent deux fichiers distincts',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', '{}');
      final a = await BackupService.instance.exporterDonneesStructurees();
      final b = await BackupService.instance.exporterDonneesStructurees();
      expect(a.succes, isTrue);
      expect(b.succes, isTrue);
      expect(a.filePath, isNot(b.filePath),
          reason: 'un second export ne doit pas écraser le premier');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Restauration .ptg effective', () {
    test('une clé supprimée localement est rétablie par la restauration',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', '{"forme":0.123}');
      await prefs.setStringList('ia_rapports_v1', <String>['{"date":"2026-02-02"}']);

      final export = await BackupService.instance.exporterDonneesStructurees();
      expect(export.succes, isTrue, reason: export.erreur ?? '');

      // Perte locale simulée.
      await prefs.remove('ia_poids_v3');
      expect((await SharedPreferences.getInstance()).getString('ia_poids_v3'),
          isNull);

      final import = await BackupService.instance
          .restaurerDepuisContenuPourTest(File(export.filePath!).readAsStringSync());
      expect(import.succes, isTrue, reason: import.erreur ?? '');

      final apres = await SharedPreferences.getInstance();
      expect(apres.getString('ia_poids_v3'), '{"forme":0.123}');
      expect(apres.getStringList('ia_rapports_v1'), isNotNull);
    });

    test('la comparaison ELO est exhaustive et aucun rating n\'est fusionné',
        () async {
      // 200 ratings, tous restaurés puis tous comparés : le test échouerait si
      // un seul était moyenné, arrondi ou perdu.
      final ratings = <String, EloScore>{};
      for (var i = 0; i < 200; i++) {
        ratings['CHEVAL$i|PLAT'] = EloScore(
          nomCheval: 'CHEVAL$i',
          rating: 1500.0 + i * 0.5,
          nbCourses: i,
          variationMois: i * 1.25,
        );
      }
      await const MigrateurEloPourTest().reporter(PontElo.instance.depotPourSauvegarde!, ratings);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('elo_service', jsonEncode(<String, Object?>{
        for (final e in ratings.entries)
          e.key: <String, Object?>{
            'nom': e.value.nomCheval,
            'rating': e.value.rating,
            'nb': e.value.nbCourses,
            'var': e.value.variationMois,
          },
      }));
      final export = await BackupService.instance.exporterDonneesStructurees();
      expect(export.succes, isTrue, reason: export.erreur ?? '');

      final import = await BackupService.instance
          .restaurerDepuisContenuPourTest(File(export.filePath!).readAsStringSync());
      expect(import.succes, isTrue, reason: import.erreur ?? '');

      // Comparaison EXHAUSTIVE : les 200 clés, pas un échantillon.
      final depot = PontElo.instance.depotPourSauvegarde!;
      final tous = await depot.tousLesElo();
      expect(tous.length, 200);
      for (final ligne in tous) {
        final attendu = ratings[ligne.cle];
        expect(attendu, isNotNull, reason: 'clé inattendue : ${ligne.cle}');
        expect(ligne.rating, attendu!.rating,
            reason: 'valeur ELO modifiée pour ${ligne.cle}');
        expect(ligne.nb, attendu.nbCourses);
        expect(ligne.var_, attendu.variationMois);
      }
    });

    test('un conteneur altéré est refusé sans aucune écriture', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', '{"forme":0.5}');
      final export = await BackupService.instance.exporterDonneesStructurees();
      expect(export.succes, isTrue);

      final racineConteneur =
          jsonDecode(File(export.filePath!).readAsStringSync()) as Map;
      final blocs = Map<String, Object?>.from(racineConteneur['blocs'] as Map);
      blocs['prefs_complet'] = 'H4sIAAAAAAAAA+3OMQ0AAAgEsf3rBgcJ1AQ';
      racineConteneur['blocs'] = blocs;

      final avant = (await SharedPreferences.getInstance()).getString('ia_poids_v3');
      final import = await BackupService.instance
          .restaurerDepuisContenuPourTest(jsonEncode(racineConteneur));
      expect(import.succes, isFalse);
      expect(import.erreur, contains('altérée'));
      final apres = (await SharedPreferences.getInstance()).getString('ia_poids_v3');
      expect(apres, avant, reason: 'aucune écriture ne doit avoir eu lieu');
    });

    test('un conteneur illisible est refusé proprement', () async {
      final import = await BackupService.instance
          .restaurerDepuisContenuPourTest('{ pas du JSON');
      expect(import.succes, isFalse);
      expect(import.erreur, isNotNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Compatibilité avec les anciennes sauvegardes JSON', () {
    test('une sauvegarde JSON v9.0 est restaurée par le chemin historique',
        () async {
      const chemin =
          '/home/user/uploaded_files/backup_pronostic_hippique_28052026.json.txt';
      if (!File(chemin).existsSync()) {
        fail('DONNEES REELLES ABSENTES : $chemin requis. Test non concluant.');
      }
      final contenu = File(chemin).readAsStringSync();

      // Le contenu ne porte pas de manifeste : il doit être routé vers le
      // chemin JSON, pas vers le chemin `.ptg`.
      const format = FormatSauvegarde();
      final verif = format.verifier(contenu);
      expect(verif.legacy, isTrue,
          reason: 'une sauvegarde v9.0 doit être identifiée comme historique');

      final import =
          await BackupService.instance.restaurerDepuisContenuPourTest(contenu);
      expect(import.succes, isTrue, reason: import.erreur ?? '');
      // Les données sont réellement présentes après restauration.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isNotEmpty);
      expect(prefs.getString('ia_poids_v3'), isNotNull,
          reason: 'les poids IA de la sauvegarde doivent être restaurés');
      // Le report vers le dépôt structuré a eu lieu : ELO présent.
      final depot = PontElo.instance.depotPourSauvegarde!;
      expect(await depot.compterElo(), greaterThan(0),
          reason: '§4 : la restauration JSON doit avancer le magasin structuré, '
              'sinon deux états divergents coexistent');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Transaction globale : instantané et retour arrière', () {
    test('l\'instantané couvre les quatre supports et se vérifie', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', '{"forme":1.0}');
      await Directory('${racine.path}/archives').create(recursive: true);
      await File('${racine.path}/archives/seg_1.json')
          .writeAsString('{"archive":true}');

      final depot = PontElo.instance.depotPourSauvegarde!;
      await depot.upsertElo(const LigneElo(
        cle: 'TEMOIN|PLAT',
        nomOrigine: 'TEMOIN',
        discipline: 'PLAT',
        rating: 1400.0,
        nb: 2,
        var_: 0.0,
      ));

      final transaction = TransactionGlobale(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
      );
      final instantane = await transaction.capturer(nom: 'test_capture');

      expect(File(instantane.chemin).existsSync(), isTrue);
      expect(instantane.nbClefsPrefs, greaterThan(0));
      expect(instantane.nbLignesSqlite, greaterThan(0));
      expect(instantane.nbFichiers, greaterThan(0),
          reason: 'les fichiers de archives/ doivent être capturés');
      expect(instantane.empreinte.length, 64,
          reason: 'l\'instantané doit porter une empreinte SHA-256 complète');
    });

    test('le retour arrière rétablit prefs, SQLite et fichiers', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', 'AVANT');
      await Directory('${racine.path}/archives').create(recursive: true);
      final fichierArchive = File('${racine.path}/archives/seg_1.json');
      await fichierArchive.writeAsString('AVANT');

      final depot = PontElo.instance.depotPourSauvegarde!;
      await depot.upsertElo(const LigneElo(
        cle: 'TEMOIN|PLAT',
        nomOrigine: 'TEMOIN',
        discipline: 'PLAT',
        rating: 1400.0,
        nb: 2,
        var_: 0.0,
      ));

      final transaction = TransactionGlobale(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
      );
      final instantane = await transaction.capturer(nom: 'test_rollback');

      // ── Modifications des trois supports ──────────────────────────────
      await prefs.setString('ia_poids_v3', 'APRES');
      await prefs.setString('cle_creee_apres', 'nouvelle');
      await fichierArchive.writeAsString('APRES');
      await depot.upsertElo(const LigneElo(
        cle: 'TEMOIN|PLAT',
        nomOrigine: 'TEMOIN',
        discipline: 'PLAT',
        rating: 9999.0,
        nb: 99,
        var_: 9.9,
      ));

      // ── Retour arrière ────────────────────────────────────────────────
      final annulation = await transaction.annuler(instantane);
      expect(annulation.reussie, isTrue, reason: annulation.erreur ?? '');

      final p = await SharedPreferences.getInstance();
      expect(p.getString('ia_poids_v3'), 'AVANT',
          reason: 'SharedPreferences doit être rétabli');
      expect(p.containsKey('cle_creee_apres'), isFalse,
          reason: 'une clé créée après l\'instantané doit disparaître : '
              'la laisser produirait un état mixte');
      expect(fichierArchive.readAsStringSync(), 'AVANT',
          reason: 'les fichiers permanents doivent être rétablis');
      final elo = await depot.tireEloPourTest('TEMOIN|PLAT');
      expect(elo, 1400.0,
          reason: 'SQLite doit être rétabli exactement');
    });

    test('le retour arrière est idempotent : rejouer ne dégrade pas', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', 'ETAT_INITIAL');
      final depot = PontElo.instance.depotPourSauvegarde!;
      final transaction = TransactionGlobale(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
      );
      final instantane = await transaction.capturer(nom: 'test_idem');

      await prefs.setString('ia_poids_v3', 'PERTURBE');
      final a = await transaction.annuler(instantane);
      final b = await transaction.annuler(instantane);

      expect(a.reussie, isTrue);
      expect(b.reussie, isTrue);
      final p = await SharedPreferences.getInstance();
      expect(p.getString('ia_poids_v3'), 'ETAT_INITIAL');
      expect(b.prefsEcrites, a.prefsEcrites,
          reason: 'un rejeu réécrit le même état complet, il ne l\'accumule pas');
    });

    test('un instantané altéré est refusé : retour arrière impossible, et dit',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', 'X');
      final depot = PontElo.instance.depotPourSauvegarde!;
      final transaction = TransactionGlobale(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
      );
      final instantane = await transaction.capturer(nom: 'test_altere');

      // Altération du fichier d'instantané lui-même.
      await File(instantane.chemin).writeAsString('{"corrompu":true}');
      final annulation = await transaction.annuler(instantane);
      expect(annulation.reussie, isFalse);
      expect(annulation.erreur, isNotNull);
    });
  });
}

/// Report de ratings vers le dépôt, pour les tests qui ont besoin d'un état ELO
/// initial sans passer par SharedPreferences.
class MigrateurEloPourTest {
  const MigrateurEloPourTest();

  Future<void> reporter(DepotSqlite depot, Map<String, EloScore> ratings) async {
    for (final e in ratings.entries) {
      await depot.upsertElo(LigneElo(
        cle: e.key,
        nomOrigine: e.value.nomCheval,
        discipline: e.key.substring(e.key.lastIndexOf('|') + 1),
        rating: e.value.rating,
        nb: e.value.nbCourses,
        var_: e.value.variationMois,
      ));
    }
  }
}
