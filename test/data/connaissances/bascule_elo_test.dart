/// Bascule ELO vers SQLite : les six états que la consigne exige de distinguer.
///
/// §1 du présent tour :
/// > « une base SQLite vide ne doit pas automatiquement provoquer une
/// > réimportation des anciennes données SharedPreferences. Prévoir un marqueur
/// > durable de migration réussie permettant de distinguer : première
/// > installation, migration nécessaire, migration déjà effectuée, base
/// > légitimement vide, restauration, anomalie de stockage. »
///
/// Le défaut que ces tests verrouillent est précis : sans marqueur, « base
/// vide » est indiscernable de « jamais alimentée ». Le remède naïf — réimporter
/// dès que la base est vide — ressuscite des données supprimées ; l'autre remède
/// naïf — ne jamais réimporter — perd les données d'une vraie migration. Les six
/// états existent pour éviter les deux.
///
/// Prouvé ici : les six états sont réellement distingués, la migration est
/// idempotente, les valeurs/disciplines/identités sont conservées à l'identique,
/// et aucune réimportation involontaire n'est possible.
///
/// Non prouvé ici : le comportement sur appareil Android réel. Les mesures sont
/// prises sur le moteur SQLite réel via FFI (même moteur, hôte différent).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/depot_sqlite.dart';
import 'package:pronostic_hippique/data/connaissances/_migration/bascule_elo.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Jeu de ratings réaliste, avec un orphelin (discipline vide, D-20).
const Map<String, Object?> _ratings = <String, Object?>{
  'IDEAL DU MOULIN|trot': <String, Object?>{
    'nom': 'IDEAL DU MOULIN',
    'rating': 1448.322864781434,
    'nb': 42,
    'var': -51.677135218565944,
  },
  'READY CASH|galop': <String, Object?>{
    'nom': 'READY CASH',
    'rating': 2100.5,
    'nb': 17,
    'var': 12.25,
  },
  'OURAGAN DE CELLAND|': <String, Object?>{
    'nom': 'OURAGAN DE CELLAND',
    'rating': 1500.0,
    'nb': 3,
    'var': 0.0,
  },
};

String _jsonRatings([Map<String, Object?>? source]) =>
    _encoder(source ?? _ratings);

String _encoder(Map<String, Object?> m) {
  final buf = StringBuffer('{');
  var first = true;
  m.forEach((k, v) {
    if (!first) buf.write(',');
    first = false;
    final val = v as Map<String, Object?>;
    buf.write('"$k":{"nom":"${val['nom']}",'
        '"rating":${val['rating']},"nb":${val['nb']},"var":${val['var']}}');
  });
  buf.write('}');
  return buf.toString();
}

void main() {
  late DepotSqlite depot;
  late String chemin;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final dir = await Directory.systemTemp.createTemp('ptg_bascule_');
    chemin = '${dir.path}/pronostic.db';
    depot = DepotSqlite(chemin: chemin, fabrique: databaseFactoryFfi);
    await depot.ouvrir();
  });

  tearDown(() async {
    await depot.fermer();
  });

  group('Détermination de l\'état — sans rien écrire', () {
    test('première installation : aucun rating nulle part', () async {
      final prefs = await SharedPreferences.getInstance();
      final etat = await const BasculeElo().determinerEtat(
        depot: depot,
        prefs: prefs,
      );
      expect(etat, EtatBasculeElo.premiereInstallation);
      // Déterminer l'état ne doit RIEN écrire : le marqueur ne doit pas
      // apparaître à la simple lecture.
      expect(await depot.lireMeta(kMetaBasculeElo), isNull);
    });

    test('migration nécessaire : des ratings dans prefs, pas de marqueur',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BasculeElo.clePrefsElo, _jsonRatings());
      final etat = await const BasculeElo().determinerEtat(
        depot: depot,
        prefs: prefs,
      );
      expect(etat, EtatBasculeElo.migrationNecessaire);
      expect(await depot.compterElo(), 0,
          reason: 'la détermination ne doit pas migrer');
    });

    test('anomalie de stockage : dépôt absent', () async {
      final prefs = await SharedPreferences.getInstance();
      final etat = await const BasculeElo().determinerEtat(
        depot: null,
        prefs: prefs,
      );
      expect(etat, EtatBasculeElo.anomalieStockage);
    });
  });

  group('Migration effective', () {
    test('migre, vérifie l\'identité, et pose le marqueur durable', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BasculeElo.clePrefsElo, _jsonRatings());

      final bilan = await const BasculeElo().executer(
        depot: depot,
        prefs: prefs,
      );

      expect(bilan.migrationExecutee, isTrue);
      expect(bilan.identiques, isTrue, reason: bilan.erreur ?? '');
      expect(bilan.ecarts, 0);
      expect(bilan.nbLignesSqlite, 3);
      expect(bilan.sqliteEstReference, isTrue);
      expect(bilan.empreinte, isNotEmpty,
          reason: 'le marqueur doit laisser une empreinte lisible');

      // Le marqueur existe réellement et qualifie l'état.
      final marqueur = await const BasculeElo().lireMarqueur(depot);
      expect(marqueur, isNotNull);
      expect(marqueur!['etat'], 'migree');
      expect(marqueur['nb_lignes'], 3);
      expect(marqueur['schema'], 1);

      // ── Les valeurs sont CONSERVÉES À L'IDENTIQUE ──────────────────────
      // Précision complète du double, sans tolérance.
      final ideal = await depot.lireElo('IDEAL DU MOULIN|trot');
      expect(ideal, isNotNull);
      expect(ideal!.rating, 1448.322864781434);
      expect(ideal.var_, -51.677135218565944);
      expect(ideal.nb, 42);

      // Discipline conservée, y compris VIDE (D-20 : orphelin préservé).
      final orphelin = await depot.lireElo('OURAGAN DE CELLAND|');
      expect(orphelin, isNotNull, reason: 'D-20 : l\'orphelin est conservé');
      expect(orphelin!.discipline, '');
    });

    test('est idempotente : rejouer ne duplique ni ne modifie', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BasculeElo.clePrefsElo, _jsonRatings());

      await const BasculeElo().executer(depot: depot, prefs: prefs);
      final apres1 = <String, double>{
        for (final l in await depot.tousLesElo()) l.cle: l.rating,
      };

      final bilan2 = await const BasculeElo().executer(
        depot: depot,
        prefs: prefs,
      );
      expect(bilan2.etat, EtatBasculeElo.migrationDejaFaite,
          reason: 'le marqueur doit empêcher une seconde migration');
      expect(bilan2.migrationExecutee, isFalse);

      final apres2 = <String, double>{
        for (final l in await depot.tousLesElo()) l.cle: l.rating,
      };
      expect(apres2, apres1);
      expect(await depot.compterElo(), 3);
    });
  });

  group('LA PROTECTION CENTRALE : base vide ≠ réimportation', () {
    test(
        'base vidée APRÈS migration : état « légitimement vide », aucune '
        'réimportation depuis prefs', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BasculeElo.clePrefsElo, _jsonRatings());

      // 1. Migration normale.
      await const BasculeElo().executer(depot: depot, prefs: prefs);
      expect(await depot.compterElo(), 3);

      // 2. La base est légitimement vidée (l'utilisateur a tout supprimé, ou
      //    une purge explicite a eu lieu). Le marqueur reste.
      await depot.transaction(() async {
        for (final l in await depot.tousLesElo()) {
          // Suppression volontaire, simulée par la voie normale du dépôt.
          await depot.supprimerEloPourTest(l.cle);
        }
      });
      expect(await depot.compterElo(), 0);
      // Les anciennes données sont TOUJOURS dans prefs — c'est le piège.
      expect(prefs.getString(BasculeElo.clePrefsElo), isNotNull);

      // 3. Redémarrage : la bascule ne doit RIEN réimporter.
      final bilan = await const BasculeElo().executer(
        depot: depot,
        prefs: prefs,
      );
      expect(bilan.etat, EtatBasculeElo.baseLegitimementVide);
      expect(bilan.migrationExecutee, isFalse,
          reason: 'le cœur de l\'exigence : aucune réimportation');
      expect(await depot.compterElo(), 0,
          reason: 'la base doit RESTER vide');
    });

    test('sans marqueur, la même base vide déclenche la migration', () async {
      // Le contre-exemple, indispensable : c'est bien le MARQUEUR qui protège,
      // pas le nombre de lignes. Sans lui, une base vide + prefs remplis EST
      // une migration nécessaire — et c'est correct, car aucune migration n'a
      // encore eu lieu.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BasculeElo.clePrefsElo, _jsonRatings());
      expect(await depot.lireMeta(kMetaBasculeElo), isNull);

      final etat = await const BasculeElo().determinerEtat(
        depot: depot,
        prefs: prefs,
      );
      expect(etat, EtatBasculeElo.migrationNecessaire,
          reason: 'sans marqueur, l\'absence de données est une migration à '
              'faire, pas un vide légitime');
    });

    test(
        'une vieille sauvegarde JSON ne peut pas ressusciter le marqueur ni '
        'réintroduire des ratings', () async {
      // Ce test vérifie le choix d'architecture : le marqueur vit dans SQLite,
      // pas dans prefs. Restaurer une sauvegarde JSON écrit dans prefs ; cela
      // ne peut donc pas inventer un marqueur de migration dans SQLite.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BasculeElo.clePrefsElo, _jsonRatings());
      await const BasculeElo().executer(depot: depot, prefs: prefs);
      expect(await depot.compterElo(), 3);

      // Vidage légitime.
      await depot.transaction(() async {
        for (final l in await depot.tousLesElo()) {
          await depot.supprimerEloPourTest(l.cle);
        }
      });
      expect(await depot.compterElo(), 0);

      // Une « vieille sauvegarde » réécrit prefs avec 3 ratings.
      await prefs.setString(BasculeElo.clePrefsElo, _jsonRatings());

      // La bascule suivante constate le marqueur et ne réimporte pas.
      final bilan = await const BasculeElo().executer(
        depot: depot,
        prefs: prefs,
      );
      expect(bilan.etat, EtatBasculeElo.baseLegitimementVide);
      expect(await depot.compterElo(), 0,
          reason: 'des données présentes dans prefs ne doivent pas, à elles '
              'seules, repeupler la base après migration validée');
    });
  });

  group('Restauration', () {
    test('le marqueur de restauration est explicite et prime', () async {
      await const BasculeElo().marquerRestauration(
        depot,
        nbLignes: 0,
        versionSauvegarde: 'ptg/1',
      );
      final prefs = await SharedPreferences.getInstance();
      final etat = await const BasculeElo().determinerEtat(
        depot: depot,
        prefs: prefs,
      );
      expect(etat, EtatBasculeElo.restauration,
          reason: 'une sauvegarde qui ramène 0 rating ne doit pas être vue '
              'comme une base légitimement vide');
    });

    test('motifRestauration est pris en compte même sans marqueur préalable',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BasculeElo.clePrefsElo, _jsonRatings());
      final bilan = await const BasculeElo().executer(
        depot: depot,
        prefs: prefs,
        motifRestauration: true,
      );
      expect(bilan.etat, EtatBasculeElo.restauration);
      // Une restauration ne migre pas les anciennes données : elle fait foi.
      expect(bilan.migrationExecutee, isFalse);
      expect(await depot.compterElo(), 0);
    });
  });

  group('Identité des valeurs : aucune altération', () {
    test('les 3 ratings conservent clé, nom, discipline, rating, nb, var',
        () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BasculeElo.clePrefsElo, _jsonRatings());
      await const BasculeElo().executer(depot: depot, prefs: prefs);

      for (final e in _ratings.entries) {
        final attendu = e.value as Map<String, Object?>;
        final lu = await depot.lireElo(e.key);
        expect(lu, isNotNull, reason: '${e.key} doit exister');
        expect(lu!.cle, e.key);
        expect(lu.nomOrigine, attendu['nom']);
        expect(lu.rating, attendu['rating'],
            reason: 'la valeur ELO doit être bit-à-bit identique');
        expect(lu.nb, attendu['nb']);
        expect(lu.var_, attendu['var']);
      }
    });

    test('un rating source sans valeur numérique n\'est pas inventé', () async {
      // D-24 / §12 : on ne devine pas. Une entrée sans rating est ignorée,
      // jamais remplacée par un 1500 par défaut.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        BasculeElo.clePrefsElo,
        '{"SANS VALEUR|trot":{"nom":"SANS VALEUR","nb":5}}',
      );
      final bilan = await const BasculeElo().executer(
        depot: depot,
        prefs: prefs,
      );
      // Aucun rating écrit : la source n'en portait aucun d'exploitable.
      expect(await depot.compterElo(), 0);
      expect(bilan.identiques, isTrue,
          reason: 'rien à migrer et rien d\'écrit est un état cohérent');
    });
  });
}
