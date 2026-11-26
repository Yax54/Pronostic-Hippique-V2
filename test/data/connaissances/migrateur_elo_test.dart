/// Migration ELO — tests d'identité des valeurs sur le **vrai moteur SQLite**
/// et sur des données **réelles** issues de la sauvegarde du 13/11/2026.
///
/// Consigne §12 : la vérification doit porter sur l'identité exacte des valeurs
/// avant et après migration. Ces tests comparent donc les flottants en égalité
/// stricte, pas avec une tolérance.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/depot_sqlite.dart';
import 'package:pronostic_hippique/data/connaissances/_core/empreinte_contenu.dart';
import 'package:pronostic_hippique/data/connaissances/_migration/migrateur_elo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Extrait le bloc `elo_service` d'une sauvegarde JSON réelle, **sans jamais
/// écrire dans le fichier**. Lecture seule, comme l'exige §14.
Map<String, Object?>? lireEloDepuisSauvegarde(String chemin) {
  final f = File(chemin);
  if (!f.existsSync()) return null;
  final contenu = f.readAsStringSync();
  final racine = jsonDecode(contenu);
  if (racine is! Map) return null;
  final elo = racine['elo_service'];
  if (elo is Map) {
    return <String, Object?>{
      for (final e in elo.entries) '${e.key}': e.value
    };
  }
  return null;
}

void main() {
  late Directory dossierTest;
  late DepotSqlite depot;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    dossierTest = await Directory.systemTemp.createTemp('ptg_elo_test_');
    depot = DepotSqlite(
      chemin: '${dossierTest.path}/pronostic.db',
      fabrique: databaseFactoryFfi,
    );
    await depot.ouvrir();
  });

  tearDown(() async {
    await depot.fermer();
    if (await dossierTest.exists()) await dossierTest.delete(recursive: true);
  });

  group('Décodage de la structure réelle', () {
    test('le format mesuré est décodé sans altération', () {
      final brut = <String, Object?>{
        'NELSON DU RIB|TROT_ATTELE': <String, Object?>{
          'nom': 'NELSON DU RIB',
          'rating': 1448.322864781434,
          'nb': 3,
          'var': -51.677135218565944,
        },
      };
      const m = MigrateurElo();
      final lignes = m.decoderElo(brut);
      expect(lignes.length, 1);
      final l = lignes.single;
      expect(l.cle, 'NELSON DU RIB|TROT_ATTELE');
      expect(l.nomOrigine, 'NELSON DU RIB');
      expect(l.discipline, 'TROT_ATTELE');
      expect(l.rating, 1448.322864781434);
      expect(l.nb, 3);
      expect(l.var_, -51.677135218565944);
      expect(l.idCheval, isNull, reason: 'identité non résolue à ce stade');
    });

    test('un nom contenant un trait vertical ne casse pas le découpage', () {
      // La clé utilise « | » comme séparateur ; on découpe au DERNIER.
      const m = MigrateurElo();
      final lignes = m.decoderElo(<String, Object?>{
        'CHEVAL|BIS|TROT_MONTE': <String, Object?>{
          'rating': 1500.0, 'nb': 2, 'var': 1.0,
        },
      });
      expect(lignes.single.nomOrigine, 'CHEVAL|BIS');
      expect(lignes.single.discipline, 'TROT_MONTE');
    });

    test('aucun rating n\'est écarté, même sans champ nom', () {
      const m = MigrateurElo();
      final lignes = m.decoderElo(<String, Object?>{
        'ANONYME|PLAT': <String, Object?>{'rating': 1400.0},
        'SANS-CHAMPS|OBSTACLE': <String, Object?>{},
      });
      expect(lignes.length, 2, reason: 'aucun filtre, aucune perte');
      expect(lignes.first.nomOrigine, 'ANONYME');
    });
  });

  group('Migration et identité des valeurs', () {
    test('les valeurs sont identiques au chiffre près après migration', () async {
      final brut = <String, Object?>{
        'A|TROT_ATTELE': <String, Object?>{
          'nom': 'A', 'rating': 1448.322864781434, 'nb': 3,
          'var': -51.677135218565944,
        },
        'B|PLAT': <String, Object?>{
          'nom': 'B', 'rating': 1234.5678901234567, 'nb': 17, 'var': 12.5,
        },
        'C|OBSTACLE': <String, Object?>{
          'nom': 'C', 'rating': 0.1, 'nb': 1, 'var': 0.30000000000000004,
        },
      };
      final res = await const MigrateurElo().migrer(depot, brut);

      expect(res.clesLues, 3);
      expect(res.clesEcrites, 3);
      expect(res.clesRelues, 3);
      expect(res.ecartsValeur, isEmpty,
          reason: 'aucun écart de valeur toléré');
      expect(res.ecartsChamp, isEmpty);
      expect(res.conforme, isTrue);
    });

    test('rejouer la migration ne change rien (idempotence)', () async {
      final brut = <String, Object?>{
        'A|TROT_ATTELE': <String, Object?>{
          'nom': 'A', 'rating': 1448.322864781434, 'nb': 3, 'var': -51.677,
        },
      };
      const m = MigrateurElo();
      await m.migrer(depot, brut);
      final empreinte1 = await MigrateurElo.empreinteEtat(depot);

      final res2 = await m.migrer(depot, brut);
      final empreinte2 = await MigrateurElo.empreinteEtat(depot);

      expect(await depot.compterElo(), 1, reason: 'aucun doublon');
      expect(empreinte2, empreinte1, reason: 'état identique après rejeu');
      expect(res2.conforme, isTrue);
    });

    test('deux disciplines d\'un même nom restent deux lignes distinctes',
        () async {
      final brut = <String, Object?>{
        'OURASI|TROT_ATTELE': <String, Object?>{
          'nom': 'OURASI', 'rating': 1600.0, 'nb': 10, 'var': 0.0,
        },
        'OURASI|TROT_MONTE': <String, Object?>{
          'nom': 'OURASI', 'rating': 1500.0, 'nb': 4, 'var': 0.0,
        },
      };
      await const MigrateurElo().migrer(depot, brut);
      expect(await depot.compterElo(), 2);
      expect((await depot.lireElo('OURASI|TROT_ATTELE'))!.rating, 1600.0);
      expect((await depot.lireElo('OURASI|TROT_MONTE'))!.rating, 1500.0);
      // D-24 : aucune fusion par moyenne (qui donnerait 1550).
      final tous = await depot.tousLesElo();
      expect(tous.map((l) => l.rating), isNot(contains(1550.0)));
    });

    test('les ratings orphelins sont conservés et comptés', () async {
      final brut = <String, Object?>{
        'ORPHELIN 1|TROT_ATTELE': <String, Object?>{
          'nom': 'ORPHELIN 1', 'rating': 1400.0, 'nb': 1, 'var': -20.0,
        },
        'ORPHELIN 2|PLAT': <String, Object?>{
          'nom': 'ORPHELIN 2', 'rating': 1350.0, 'nb': 1, 'var': -30.0,
        },
      };
      final res = await const MigrateurElo().migrer(depot, brut);
      expect(await depot.compterElo(), 2);
      expect(res.clesSansIdentite, 2,
          reason: 'D-20 : les identités non résolues sont conservées, pas supprimées');
    });

    test('aucun rating n\'est recalculé : la valeur écrite est la valeur lue',
        () async {
      // Valeur volontairement « laide » pour détecter tout arrondi.
      const rating = 1448.3228647814349;
      final brut = <String, Object?>{
        'X|TROT_ATTELE': <String, Object?>{
          'nom': 'X', 'rating': rating, 'nb': 1, 'var': 0.0,
        },
      };
      await const MigrateurElo().migrer(depot, brut);
      final relu = await depot.lireElo('X|TROT_ATTELE');
      expect(relu!.rating, rating);
      // Preuve supplémentaire : la représentation textuelle est identique.
      expect(relu.rating.toString(), rating.toString());
    });
  });

  group('Données réelles de la sauvegarde 13/11/2026', () {
    const cheminsPossibles = <String>[
      '/home/user/uploaded_files/backup_pronostic_hippique_13112026.json.txt',
      '/home/user/uploaded_files/backup_pronostic_hippique_13112026.json',
    ];

    test('migration complète du bloc ELO réel, valeurs identiques', () async {
      String? chemin;
      for (final c in cheminsPossibles) {
        if (File(c).existsSync()) {
          chemin = c;
          break;
        }
      }
      // Aucun test n'est désactivé : si la sauvegarde réelle est absente, le
      // test DOIT échouer avec un message explicite. Un succès silencieux
      // ferait croire à une vérification qui n'a pas eu lieu (§25).
      if (chemin == null) {
        fail('DONNEES REELLES ABSENTES : la sauvegarde 13/11/2026 est requise '
            'pour verifier l\'identite des valeurs ELO. Test non concluant.');
      }

      // Empreinte du fichier AVANT lecture, pour prouver qu'il n'est pas modifié.
      final octetsAvant = File(chemin).lengthSync();
      final md5Avant = empreinteValeur(File(chemin).readAsStringSync());

      final elo = lireEloDepuisSauvegarde(chemin);
      expect(elo, isNotNull, reason: 'le bloc elo_service doit exister');
      expect(elo!.isNotEmpty, isTrue, reason: 'le bloc ne doit pas être vide');

      final res = await const MigrateurElo().migrer(depot, elo);

      expect(res.clesLues, elo.length);
      expect(res.clesRelues, elo.length);
      expect(res.ecartsValeur, isEmpty,
          reason: 'consigne §12 : identité des valeurs exigée sur données réelles');
      expect(res.ecartsChamp, isEmpty);
      expect(res.conforme, isTrue);
      expect(await depot.compterElo(), elo.length);

      // Le fichier source n'a pas bougé (§14 : sauvegardes historiques
      // intouchables).
      final octetsApres = File(chemin).lengthSync();
      final md5Apres = empreinteValeur(File(chemin).readAsStringSync());
      expect(octetsApres, octetsAvant);
      expect(md5Apres, md5Avant,
          reason: 'la sauvegarde historique ne doit jamais être modifiée');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
