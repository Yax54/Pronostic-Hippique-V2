/// Bascule ELO : la réplique en retard est MESURÉE, pas supposée.
///
/// Ce fichier ne rejoue pas la bascule (12 tests la couvrent déjà). Il mesure
/// le défaut précis qui subsistait après elle :
///
///   prefs confirme une écriture → SQLite ne la reçoit pas → au démarrage
///   suivant, `_charger()` lit SQLite en priorité et ne relit JAMAIS la valeur
///   confirmée sur disque.
///
/// C'est une perte SILENCIEUSE : aucune exception, aucun message, aucun écart
/// observable. §4 l'interdit (deux magasins ne doivent pas produire deux états)
/// et §27 exige que tout repli soit observable.
///
/// Chaque assertion ci-dessous imprime la valeur qu'elle a réellement lue.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pronostic_hippique/data/connaissances/_adapters/depot_sqlite.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/pont_elo.dart';

import 'package:pronostic_hippique/data/connaissances/_migration/bascule_elo.dart';
import 'package:pronostic_hippique/models/zt_models.dart' show EloScore;

/// Clé prefs du service ELO (format v2, `NOM|DISCIPLINE`).
const String _clePrefs = BasculeElo.clePrefsElo;

/// Prépare un dépôt SQLite réel (moteur FFI) dans un dossier isolé.
Future<DepotSqlite> _depotNeuf(Directory dir) async {
  final depot = DepotSqlite(
      chemin: '${dir.path}/pronostic.db', fabrique: databaseFactoryFfi);
  await depot.ouvrir();
  return depot;
}

/// Écrit un état ELO dans prefs, au format exact attendu par le service.
Future<void> _ecrirePrefs(Map<String, EloScore> ratings) async {
  final data = <String, dynamic>{};
  ratings.forEach((k, v) => data[k] = v.toJson());
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_clePrefs, jsonEncode(data));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('réplique ELO en retard', () {
    late Directory dir;
    late DepotSqlite depot;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      dir = await Directory.systemTemp.createTemp('replique_test_');
      depot = await _depotNeuf(dir);
    });

    tearDown(() async {
      await depot.fermer();
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // Un dossier temporaire non supprimé n'invalide aucune mesure.
      }
    });

    test('le pont DIT la vérité sur son issue au lieu de se taire', () async {
      // Le pont doit être ouvert avec la MÊME fabrique que le reste du test :
      // sans elle, il tente la fabrique Android et échoue (`databaseFactory
      // not initialized`). C'est un défaut du test, pas du code de production.
      PontElo.instance.utiliserFabrique(databaseFactoryFfi);
      final ouvert = await PontElo.instance.ouvrir(racineForcee: dir.path);
      expect(ouvert, isTrue,
          reason: 'le pont doit s\'ouvrir sur le moteur SQLite reel');

      final ok = await PontElo.instance.repliquer(<String, EloScore>{
        'ALPHA|TROT_ATTELE': const EloScore(
            nomCheval: 'ALPHA',
            rating: 1520.0,
            nbCourses: 4,
            variationMois: 3.0),
      });
      // ignore: avoid_print
      print('[MESURE] réplication vers un dépôt ouvert : issue = $ok '
          '| message du pont : ${PontElo.instance.etat.dernierMessage}');
      expect(ok, isTrue, reason: 'un dépôt ouvert doit confirmer l\'écriture');

      // On interroge le dépôt DU PONT, pas une seconde connexion : ouvrir un
      // second handle FFI sur le même fichier ferme le premier et produirait un
      // `database_closed` trompeur (déjà rencontré au lot precedent).
      final depotPont = PontElo.instance.depotPourSauvegarde;
      expect(depotPont, isNotNull,
          reason: 'le pont doit exposer le depot qu\'il utilise reellement');
      final enBase = await depotPont!.tousLesElo();
      // ignore: avoid_print
      print('[MESURE] lignes reellement en base : ${enBase.length} '
          '(rating=${enBase.isEmpty ? "aucun" : enBase.first.rating})');
      expect(enBase.length, 1);

      // Dépôt fermé : la réplication ne peut rien écrire. Avant correction, elle
      // rendait `void` et l'appelant n'avait AUCUN moyen de le savoir.
      await PontElo.instance.fermer();
      final ko = await PontElo.instance.repliquer(<String, EloScore>{
        'BETA|TROT_ATTELE': const EloScore(
            nomCheval: 'BETA',
            rating: 1600.0,
            nbCourses: 9,
            variationMois: 1.0),
      });
      // ignore: avoid_print
      print('[MESURE] réplication vers un dépôt FERMÉ : issue = $ko '
          '(avant correction : aucun retour, échec muet)');
      expect(ko, isFalse, reason: 'un dépôt fermé ne peut pas confirmer');
    });

    test('une réplique en retard est RATTRAPÉE au démarrage suivant', () async {
      // ── Situation 1 : état cohérent, marqueur posé ────────────────────────
      await _ecrirePrefs(<String, EloScore>{
        'ALPHA|TROT_ATTELE': const EloScore(
            nomCheval: 'ALPHA',
            rating: 1520.0,
            nbCourses: 4,
            variationMois: 3.0),
      });
      final prefs = await SharedPreferences.getInstance();
      final premier =
          await const BasculeElo().executer(depot: depot, prefs: prefs);
      // ignore: avoid_print
      print('[MESURE] 1er démarrage : état=${premier.etat.name}, '
          'migré=${premier.migrationExecutee}, '
          'sqlite=${premier.nbLignesSqlite}, écarts=${premier.ecarts}');
      // L'état annoncé est celui qui a MOTIVÉ l'exécution : au premier
      // démarrage, c'est bien « migration nécessaire ». Ce qui compte est
      // qu'elle ait eu lieu et qu'elle soit conforme.
      expect(premier.etat, EtatBasculeElo.migrationNecessaire);
      expect(premier.nbLignesSqlite, 1);

      final marqueur1 = await depot.lireMeta(kMetaBasculeElo);
      // ignore: avoid_print
      print('[MESURE] marqueur posé : ${marqueur1?.substring(0, 60)}...');
      expect(marqueur1, isNotNull);

      // ── Situation 2 : prefs reçoit une écriture, SQLite la rate ───────────
      await _ecrirePrefs(<String, EloScore>{
        'ALPHA|TROT_ATTELE': const EloScore(
            nomCheval: 'ALPHA',
            rating: 1520.0,
            nbCourses: 4,
            variationMois: 3.0),
        'GAMMA|TROT_MONTE': const EloScore(
            nomCheval: 'GAMMA',
            rating: 1710.5,
            nbCourses: 12,
            variationMois: 9.5),
      });
      // La réplique a échoué : le service repose le marqueur en
      // « migration_necessaire ». On reproduit ce que fait _signalerRepliqueEnRetard.
      await depot
          .ecrireMeta(
            kMetaBasculeElo,
            jsonEncode(<String, Object?>{
              'etat': 'migration_necessaire',
              'date': DateTime.now().toUtc().toIso8601String(),
              'nb_lignes': await depot.compterElo(),
              'source': 'shared_preferences',
              'schema': 1,
              'motif': 'replique_en_retard',
            }),
          )
          .then((_) {});

      final avant = await depot.compterElo();
      // ignore: avoid_print
      print('[MESURE] état au redémarrage : $avant ligne(s) en base, '
          '2 rating(s) dans prefs');

      // ── Situation 3 : le démarrage suivant doit RATTRAPER ────────────────
      final second =
          await const BasculeElo().executer(depot: depot, prefs: prefs);
      // ignore: avoid_print
      print('[MESURE] 2e démarrage : état=${second.etat.name}, '
          'migré=${second.migrationExecutee}, '
          'sqlite=${second.nbLignesSqlite}, écarts=${second.ecarts}');

      expect(second.nbLignesSqlite, 2,
          reason: 'la clé GAMMA confirmée dans prefs doit être rattrapée');

      final gamma = await depot
          .tousLesElo()
          .then((l) => l.where((e) => e.cle.startsWith('GAMMA')).toList());
      // ignore: avoid_print
      print(
          '[MESURE] GAMMA retrouvé en base : ${gamma.isEmpty ? "NON" : gamma.first.rating}');
      expect(gamma.length, 1);
      expect(gamma.first.rating, 1710.5);

      // ── Situation 4 : une base à jour n'est PLUS rejouée ─────────────────
      final avantRejeu = await depot.compterElo();
      final troisieme =
          await const BasculeElo().executer(depot: depot, prefs: prefs);
      final apresRejeu = await depot.compterElo();
      // ignore: avoid_print
      print('[MESURE] 3e démarrage : état=${troisieme.etat.name}, '
          'migré=${troisieme.migrationExecutee}, '
          'sqlite avant=$avantRejeu après=$apresRejeu');
      expect(troisieme.migrationExecutee, isFalse,
          reason: 'aucune écriture ne doit avoir lieu quand tout est à jour');
      expect(apresRejeu, avantRejeu);
    });

    test('une base VIDÉE après migration ne réimporte PAS depuis prefs',
        () async {
      await _ecrirePrefs(<String, EloScore>{
        'ALPHA|TROT_ATTELE': const EloScore(
            nomCheval: 'ALPHA',
            rating: 1520.0,
            nbCourses: 4,
            variationMois: 3.0),
      });
      final prefs = await SharedPreferences.getInstance();
      await const BasculeElo().executer(depot: depot, prefs: prefs);

      // L'utilisateur n'a plus aucun rating : la base est vidée, le marqueur reste.
      await depot.executerSqlBrut('DELETE FROM elo_ratings');
      final vide = await depot.compterElo();
      // ignore: avoid_print
      print('[MESURE] base vidée : $vide ligne(s), prefs conserve '
          '${(jsonDecode(prefs.getString(_clePrefs)!) as Map).length} rating(s)');

      final bilan =
          await const BasculeElo().executer(depot: depot, prefs: prefs);
      // ignore: avoid_print
      print('[MESURE] décision sur base vide : ${bilan.etat.name}, '
          'migré=${bilan.migrationExecutee}, sqlite=${bilan.nbLignesSqlite}');
      expect(bilan.etat, EtatBasculeElo.baseLegitimementVide);
      expect(bilan.migrationExecutee, isFalse);
      expect(await depot.compterElo(), 0,
          reason: 'une base vidée légitimement ne doit pas être réalimentée');
    });
  });
}
