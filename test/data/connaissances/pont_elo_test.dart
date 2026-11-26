/// Tests du raccordement ELO au dépôt structuré — sur le **chemin de
/// production réel** (`EloService` → `PontElo` → SQLite).
///
/// Réponse directe à l'objection : « la réussite des tests sur un dépôt SQLite
/// isolé ne constitue pas une preuve que l'application utilise effectivement ce
/// dépôt dans ses chemins de production ».
///
/// Ces tests n'appellent pas `DepotSqlite` directement : ils passent par
/// `PontElo`, exactement comme le fait `EloService._executerSauvegarde()`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/pont_elo.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory racineTest;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    racineTest = await Directory.systemTemp.createTemp('ptg_pont_elo_');
    // Moteur SQLite réel en environnement de bureau. Le code testé est celui de
    // production (`PontElo` → `DepotSqlite`), seul le moteur diffère : c'est la
    // condition pour que ces tests prouvent quelque chose sur le vrai SQLite.
    PontElo.instance.utiliserFabrique(databaseFactoryFfi);
    // Dossier isolé : aucune donnée réelle de l'utilisateur n'est touchée (§14).
    final ok = await PontElo.instance.ouvrir(racineForcee: racineTest.path);
    expect(ok, isTrue, reason: 'ouverture du dépôt requise pour ce test');
  });

  tearDown(() async {
    await PontElo.instance.fermer();
    if (await racineTest.exists()) await racineTest.delete(recursive: true);
  });

  group('Ouverture du dépôt par le chemin de production', () {
    test('le pont ouvre réellement un dépôt', () {
      expect(PontElo.instance.ouvert, isTrue);
      expect(PontElo.instance.etat.chemin, contains('pronostic.db'));
    });

    test('les 6 dossiers sont créés sous la racine applicative', () async {
      for (final nom in <String>[
        'base', 'archives', 'config', 'cache', 'sauvegardes', 'temp',
      ]) {
        expect(Directory('${racineTest.path}/$nom').existsSync(), isTrue,
            reason: 'dossier $nom manquant');
      }
    });

    test('le fichier de base existe sur disque après ouverture', () {
      expect(File('${racineTest.path}/base/pronostic.db').existsSync(), isTrue);
    });
  });

  group('Réplication des écritures (chemin réel)', () {
    test('une écriture ELO est répliquée dans le dépôt', () async {
      await PontElo.instance.repliquer(<String, EloScore>{
        'NELSON DU RIB|TROT_ATTELE': const EloScore(
          nomCheval: 'NELSON DU RIB',
          rating: 1448.322864781434,
          nbCourses: 3,
          variationMois: -51.677135218565944,
        ),
      });

      expect(PontElo.instance.etat.nbReplications, greaterThan(0));
      expect(PontElo.instance.etat.nbEchecs, 0);

      final exporte = await PontElo.instance.exporterTout();
      expect(exporte.length, 1);
      expect(exporte.single['id'], 'NELSON DU RIB|TROT_ATTELE');
      // La valeur est identique au chiffre près : aucune transformation.
      expect(exporte.single['rating'], 1448.322864781434);
      expect(exporte.single['var'], -51.677135218565944);
      expect(exporte.single['nb'], 3);
    });

    test('les deux disciplines d\'un même cheval restent distinctes', () async {
      await PontElo.instance.repliquer(<String, EloScore>{
        'OURASI|TROT_ATTELE': const EloScore(
            nomCheval: 'OURASI', rating: 1600.0, nbCourses: 10),
        'OURASI|TROT_MONTE': const EloScore(
            nomCheval: 'OURASI', rating: 1500.0, nbCourses: 4),
      });
      final exporte = await PontElo.instance.exporterTout();
      expect(exporte.length, 2);
      final ratings = exporte.map((e) => e['rating']).toSet();
      expect(ratings, containsAll(<double>[1600.0, 1500.0]));
      // D-24 : aucune moyenne (1550) ne doit apparaître.
      expect(ratings, isNot(contains(1550.0)));
    });

    test('les ratings d\'identité non résolue sont conservés (D-20)', () async {
      // Clé se terminant par « | » : discipline vide, issue de la migration
      // v1→v2. L'ancien code les DÉTRUISAIT. Ils doivent désormais survivre.
      await PontElo.instance.repliquer(<String, EloScore>{
        'ANCIEN CHEVAL|': const EloScore(
            nomCheval: 'ANCIEN CHEVAL', rating: 1520.0, nbCourses: 1),
        'AUTRE ANCIEN|': const EloScore(
            nomCheval: 'AUTRE ANCIEN', rating: 1480.0, nbCourses: 1),
      });
      final exporte = await PontElo.instance.exporterTout();
      expect(exporte.length, 2, reason: 'aucune purge autorisée par D-20');
      expect(await PontElo.instance.compterOrphelins(), 2);
    });

    test('rejouer la réplication ne duplique rien', () async {
      final etat = <String, EloScore>{
        'A|PLAT': const EloScore(nomCheval: 'A', rating: 1500.0, nbCourses: 1),
      };
      await PontElo.instance.repliquer(etat);
      await PontElo.instance.repliquer(etat);
      await PontElo.instance.repliquer(etat);
      final exporte = await PontElo.instance.exporterTout();
      expect(exporte.length, 1, reason: 'idempotence : une seule ligne');
    });

    test('une mise à jour remplace la valeur, sans en créer une seconde',
        () async {
      await PontElo.instance.repliquer(<String, EloScore>{
        'A|PLAT': const EloScore(nomCheval: 'A', rating: 1500.0, nbCourses: 1),
      });
      await PontElo.instance.repliquer(<String, EloScore>{
        'A|PLAT': const EloScore(nomCheval: 'A', rating: 1516.0, nbCourses: 2),
      });
      final exporte = await PontElo.instance.exporterTout();
      expect(exporte.length, 1);
      expect(exporte.single['rating'], 1516.0);
      expect(exporte.single['nb'], 2);
    });

    test('l\'inventaire reflète les lignes réellement écrites', () async {
      await PontElo.instance.repliquer(<String, EloScore>{
        'A|PLAT': const EloScore(nomCheval: 'A', rating: 1500.0),
        'B|PLAT': const EloScore(nomCheval: 'B', rating: 1500.0),
        'C|TROT_ATTELE': const EloScore(nomCheval: 'C', rating: 1500.0),
      });
      final inv = await PontElo.instance.inventaire();
      expect(inv['elo_ratings'], 3);
      expect(inv.containsKey('courses'), isTrue,
          reason: 'le schéma complet doit être appliqué');
    });

    test('l\'intégrité SQLite du dépôt de production est saine', () async {
      await PontElo.instance.repliquer(<String, EloScore>{
        'A|PLAT': const EloScore(nomCheval: 'A', rating: 1500.0),
      });
      expect(await PontElo.instance.integrite(), contains('ok'));
    });

    test('la recherche par cheval fonctionne sur le dépôt de production',
        () async {
      await PontElo.instance.repliquer(<String, EloScore>{
        'OURASI|TROT_ATTELE': const EloScore(
            nomCheval: 'OURASI', rating: 1600.0),
        'OURASI|TROT_MONTE': const EloScore(
            nomCheval: 'OURASI', rating: 1500.0),
        'AUTRE|PLAT': const EloScore(nomCheval: 'AUTRE', rating: 1400.0),
      });
      final duCheval = await PontElo.instance.ratingsDuCheval('Ourasi');
      expect(duCheval.length, 2,
          reason: 'recherche insensible à la casse via normalisation');
      final plat = await PontElo.instance.ratingsDeDiscipline('PLAT');
      expect(plat.length, 1);
    });
  });

  group('Robustesse du pont', () {
    test('après fermeture, une réplication ne lève pas', () async {
      await PontElo.instance.fermer();
      // Ne doit pas lever : le pont est secondaire, jamais bloquant.
      await PontElo.instance.repliquer(<String, EloScore>{
        'A|PLAT': const EloScore(nomCheval: 'A', rating: 1500.0),
      });
      expect(PontElo.instance.ouvert, isFalse);
    });

    test('après fermeture, l\'export rend une liste vide sans lever', () async {
      await PontElo.instance.fermer();
      expect(await PontElo.instance.exporterTout(), isEmpty);
      expect(await PontElo.instance.compterOrphelins(), 0);
    });
  });
}
