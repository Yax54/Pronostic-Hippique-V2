/// Tests sur le **vrai moteur SQLite** (via `sqflite_common_ffi`).
///
/// Consigne §5 : les tests en mémoire ne valent pas validation du comportement
/// réel. Ces tests ouvrent une vraie base sur disque, appliquent le schéma
/// complet, et vérifient les propriétés que la consigne exige :
/// identités, idempotence, conservation ELO bit à bit, déduplication par
/// contenu, préservation de `fnum2`, absence de purge.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/depot_sqlite.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/schema_sqlite.dart';
import 'package:pronostic_hippique/data/connaissances/_core/depot.dart';
import 'package:pronostic_hippique/data/connaissances/_core/empreinte_contenu.dart';
import 'package:pronostic_hippique/data/connaissances/_core/identifiants.dart';
import 'package:pronostic_hippique/data/connaissances/_core/politiques_conservation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dossierTest;
  late DepotSqlite depot;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    dossierTest = await Directory.systemTemp.createTemp('ptg_sqlite_test_');
    depot = DepotSqlite(
      chemin: '${dossierTest.path}/pronostic.db',
      fabrique: databaseFactoryFfi,
    );
    await depot.ouvrir();
  });

  tearDown(() async {
    await depot.fermer();
    if (await dossierTest.exists()) {
      await dossierTest.delete(recursive: true);
    }
  });

  group('Schéma', () {
    test('le schéma s\'applique et la version est enregistrée', () async {
      expect(await depot.versionSchema(), kVersionSchema);
    });

    test('toutes les tables déclarées existent réellement', () async {
      final inv = await depot.inventaire();
      for (final table in <String>[...kTablesPermanentes, ...kTablesAPurgeExplicite]) {
        expect(inv.containsKey(table), isTrue,
            reason: 'table manquante dans la base : $table');
      }
    });

    test('le contrôle d\'intégrité SQLite répond ok', () async {
      final integrite = await depot.integrite();
      expect(integrite, contains('ok'));
    });

    test('la base vit sur un vrai fichier, pas en mémoire', () async {
      // La preuve que le moteur réel travaille sur disque : le fichier existe
      // et grandit après des écritures.
      final fichier = File('${dossierTest.path}/pronostic.db');
      expect(await fichier.exists(), isTrue);
      final avant = await fichier.length();
      for (var i = 0; i < 50; i++) {
        await depot.upsertCheval(
          identiteComposite(nom: 'CHEVAL $i', anneeNaissance: 2018),
        );
      }
      final apres = await fichier.length();
      expect(apres, greaterThan(avant),
          reason: 'le fichier doit grossir sur disque, preuve du moteur réel');
    });
  });

  group('Identités', () {
    test('deux homonymes d\'années différentes ne partagent pas l\'identité',
        () async {
      final a = identiteComposite(nom: 'NELSON DU RIB', anneeNaissance: 2015);
      final b = identiteComposite(nom: 'NELSON DU RIB', anneeNaissance: 2019);
      expect(a.id, isNot(equals(b.id)));
      await depot.upsertCheval(a);
      await depot.upsertCheval(b);
      expect(await depot.compterChevaux(), 2);
    });

    test('un nom sans année de naissance reste au niveau provisoire', () {
      final id = identiteComposite(nom: 'MYSTERE');
      expect(id.niveau, NiveauIdentite.provisoire);
    });

    test('un identifiant fournisseur est du niveau le plus élevé', () {
      final id = identiteFournisseur(idFournisseur: 'SIRE-123', nom: 'OURASI');
      expect(id.niveau, NiveauIdentite.fournisseur);
      expect(id.idFournisseur, 'SIRE-123');
    });

    test('la normalisation des noms est stable et sans accent', () {
      expect(normaliserNom('Étoile du Nord'), normaliserNom('ETOILE DU NORD'));
      expect(normaliserNom("L'AS DE PIQUE"), normaliserNom('L AS DE PIQUE'));
      // Mais l'égalité de noms normalisés ne vaut PAS preuve d'identité :
      // la fonction n'est pas utilisée seule pour fusionner (D-11).
    });
  });

  group('ELO — conservation des valeurs', () {
    test('un rating est restitué à l\'identique, sans arrondi', () async {
      // Valeur réelle relevée dans la sauvegarde du 13/11/2026.
      const rating = 1448.322864781434;
      await depot.upsertElo(const LigneElo(
        cle: 'NELSON DU RIB|TROT_ATTELE',
        nomOrigine: 'NELSON DU RIB',
        discipline: 'TROT_ATTELE',
        rating: rating,
        nb: 3,
        var_: -51.677135218565944,
      ));
      final relu = await depot.lireElo('NELSON DU RIB|TROT_ATTELE');
      expect(relu, isNotNull);
      expect(relu!.rating, rating);
      expect(relu.var_, -51.677135218565944);
      expect(relu.nb, 3);
    });

    test('les deux disciplines d\'un même cheval restent séparées', () async {
      await depot.upsertElo(const LigneElo(
        cle: 'OURASI|TROT_ATTELE',
        nomOrigine: 'OURASI',
        discipline: 'TROT_ATTELE',
        rating: 1600.0,
        nb: 10,
        var_: 0.0,
      ));
      await depot.upsertElo(const LigneElo(
        cle: 'OURASI|TROT_MONTE',
        nomOrigine: 'OURASI',
        discipline: 'TROT_MONTE',
        rating: 1500.0,
        nb: 4,
        var_: 0.0,
      ));
      expect(await depot.compterElo(), 2);
      expect((await depot.lireElo('OURASI|TROT_ATTELE'))!.rating, 1600.0);
      expect((await depot.lireElo('OURASI|TROT_MONTE'))!.rating, 1500.0);
    });

    test('un rating orphelin (identité non résolue) est conservé', () async {
      await depot.upsertElo(const LigneElo(
        cle: 'INCONNU X|TROT_ATTELE',
        nomOrigine: 'INCONNU X',
        discipline: 'TROT_ATTELE',
        rating: 1450.0,
        nb: 1,
        var_: -20.0,
        idCheval: null,
      ));
      expect(await depot.compterElo(), 1);
      final tous = await depot.tousLesElo();
      expect(tous.single.idCheval, isNull);
    });

    test('aucun plafond : 25 000 ratings coexistent sans purge', () async {
      // Consigne §11 : « pas de plafond ELO 20 000 clés ». Le test remplit la
      // table au-delà de ce seuil en une seule instruction SQL (pour rester
      // rapide sur FFI), puis écrit des clés supplémentaires **via l'API du
      // dépôt** : si une purge existait, le total diminuerait.
      await depot.executerSqlBrut('''
        WITH RECURSIVE serie(i) AS (
          SELECT 1 UNION ALL SELECT i + 1 FROM serie WHERE i < 25000
        )
        INSERT INTO elo_ratings
          (id, nom_origine, nom_normalise, discipline, rating, nb, var,
           id_cheval, cree_le, maj_le)
        SELECT 'MASSIF' || i || '|TROT_ATTELE',
               'MASSIF' || i,
               'MASSIF' || i,
               'TROT_ATTELE',
               1400.0 + i,
               1,
               0.0,
               NULL,
               '2026-01-01T00:00:00Z',
               '2026-01-01T00:00:00Z'
        FROM serie
      ''');
      expect(await depot.compterElo(), 25000);

      // Écriture supplémentaire via l'API normale, au-delà du seuil.
      await depot.upsertElo(const LigneElo(
        cle: 'APRES-SEUIL|TROT_ATTELE',
        nomOrigine: 'APRES-SEUIL',
        discipline: 'TROT_ATTELE',
        rating: 1500.0,
        nb: 1,
        var_: 0.0,
      ));
      expect(await depot.compterElo(), 25001,
          reason: 'aucune éviction ne doit se produire au-delà de 20 000 clés');
      expect(await depot.lireElo('MASSIF1|TROT_ATTELE'), isNotNull,
          reason: 'la première clé doit toujours être présente');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Rapports — déduplication par contenu', () {
    /// Contenu de rapport tel qu'observé dans le corpus : date + champs +
    /// `fnum2` présent ou absent.
    Map<String, Object?> rapport({required String date, bool avecFnum2 = true}) {
      return <String, Object?>{
        'date': date,
        'fnum': '20261113',
        if (avecFnum2) 'fnum2': '20261113B',
        'rj': <Object?>[<String, Object?>{'r': 1, 'c': 1, 'lib': 'Prix Test'}],
      };
    }

    test('deux copies identiques ne créent qu\'un enregistrement', () async {
      final contenu = rapport(date: '2026-11-13');
      final empreinte = empreinteContenu(contenu);
      final brut = jsonEncode(contenu);
      final normalise = serialiserCanonique(normaliserContenu(contenu));

      final r1 = await depot.insererRapport(RapportStocke(
        empreinte: empreinte,
        dateRapport: '2026-11-13',
        contenu: brut,
        contenuNormalise: normalise,
        tailleOrigine: brut.length,
        schemaVersion: 1,
      ));
      final r2 = await depot.insererRapport(RapportStocke(
        empreinte: empreinte,
        dateRapport: '2026-11-13',
        contenu: brut,
        contenuNormalise: normalise,
        tailleOrigine: brut.length,
        schemaVersion: 1,
      ));

      expect(r1, isTrue, reason: 'première insertion effective');
      expect(r2, isFalse, reason: 'seconde insertion ignorée (idempotence)');
      expect(await depot.compterRapports(), 1);
    });

    test('deux contenus de même date mais différents restent deux', () async {
      // C'est le cas mesuré du corpus : 219 dates pour 225 contenus.
      final sansFnum2 = rapport(date: '2026-11-13', avecFnum2: false);
      final avecFnum2 = rapport(date: '2026-11-13');

      expect(empreinteContenu(sansFnum2), isNot(equals(empreinteContenu(avecFnum2))),
          reason: 'fnum2 présent ou absent ne doit PAS produire la même empreinte');

      for (final c in <Map<String, Object?>>[sansFnum2, avecFnum2]) {
        final brut = jsonEncode(c);
        await depot.insererRapport(RapportStocke(
          empreinte: empreinteContenu(c),
          dateRapport: '2026-11-13',
          contenu: brut,
          contenuNormalise: serialiserCanonique(normaliserContenu(c)),
          tailleOrigine: brut.length,
          schemaVersion: 1,
        ));
      }
      expect(await depot.compterRapports(), 2,
          reason: 'la date n\'est jamais une clé : aucun écrasement');
    });

    test('fnum2 est conservé dans le contenu stocké', () async {
      final c = rapport(date: '2026-11-13');
      final brut = jsonEncode(c);
      await depot.insererRapport(RapportStocke(
        empreinte: empreinteContenu(c),
        dateRapport: '2026-11-13',
        contenu: brut,
        contenuNormalise: serialiserCanonique(normaliserContenu(c)),
        tailleOrigine: brut.length,
        schemaVersion: 1,
      ));
      final stockes = await depot.tousLesRapports();
      expect(stockes.single.contenu, contains('fnum2'),
          reason: 'consigne §13 : ne pas supprimer fnum2');
      final decode = jsonDecode(stockes.single.contenu) as Map<String, Object?>;
      expect(decode['fnum2'], '20261113B');
    });

    test('la normalisation est réversible : l\'original se reconstruit', () {
      final original = rapport(date: '2026-11-13', avecFnum2: false);
      final attendu = <String>{'date', 'fnum', 'fnum2', 'rj'};
      final normalise = normaliserContenu(original, schemaAttendu: attendu);
      final reconstruit = denormaliserContenu(normalise);

      // fnum2 était absent : après dénormalisation il disparaît à nouveau.
      expect((reconstruit! as Map<String, Object?>).containsKey('fnum2'), isFalse);
      expect(serialiserCanonique(reconstruit), serialiserCanonique(original));
    });

    test('absent, null et renseigné produisent trois empreintes distinctes', () {
      final absent = empreinteContenu(<String, Object?>{'a': 1},
          schemaAttendu: <String>{'a', 'b'});
      final nul = empreinteContenu(<String, Object?>{'a': 1, 'b': null},
          schemaAttendu: <String>{'a', 'b'});
      final rempli = empreinteContenu(<String, Object?>{'a': 1, 'b': 'x'},
          schemaAttendu: <String>{'a', 'b'});
      expect(<String>{absent, nul, rempli}.length, 3);
    });

    test('les copies multiples d\'un même contenu sont toutes tracées', () async {
      final c = rapport(date: '2026-11-13');
      final empreinte = empreinteContenu(c);
      final brut = jsonEncode(c);
      await depot.insererRapport(RapportStocke(
        empreinte: empreinte,
        dateRapport: '2026-11-13',
        contenu: brut,
        contenuNormalise: serialiserCanonique(normaliserContenu(c)),
        tailleOrigine: brut.length,
        schemaVersion: 1,
      ));
      await depot.ajouterCopieRapport(CopieRapport(
          empreinte: empreinte, source: 'collection', position: 10));
      await depot.ajouterCopieRapport(CopieRapport(
          empreinte: empreinte, source: 'bilan_semaine', position: 3));
      await depot.ajouterCopieRapport(CopieRapport(
          empreinte: empreinte, source: 'bilan_mois', position: 1));
      // Réinsérer la même copie ne la duplique pas.
      await depot.ajouterCopieRapport(CopieRapport(
          empreinte: empreinte, source: 'collection', position: 10));

      expect(await depot.compterRapports(), 1);
      expect(await depot.compterCopiesRapport(), 3);
      final copies = await depot.copiesDuRapport(empreinte);
      expect(copies.length, 3);
      expect(copies.any((c) => c.source == 'bilan_semaine'), isTrue,
          reason: 'les rapports présents UNIQUEMENT dans les bilans sont tracés');
    });
  });

  group('Pronostics — conservation conditionnelle', () {
    test('un pronostic avec résultat officiel est conservé et archivé', () async {
      await depot.insererPronostic(
        empreinte: 'p1',
        contenu: '{"x":1}',
        dateCourse: '2025-01-01',
        resultatOfficiel: '1-2-3',
        archive: true,
      );
      expect(await depot.compterPronosticsAvecResultat(), 1);
      expect(await depot.compterPronostics(archive: true), 1);
    });

    test('la contrainte d\'unicité empêche un doublon', () async {
      await depot.insererPronostic(empreinte: 'p2', contenu: '{}');
      await depot.insererPronostic(empreinte: 'p2', contenu: '{}');
      expect(await depot.compterPronostics(), 1);
    });
  });

  group('Transactions et interruption', () {
    test('une transaction annulée ne laisse aucune trace partielle', () async {
      await depot.upsertCheval(identiteComposite(nom: 'AVANT', anneeNaissance: 2018));
      final avant = await depot.compterChevaux();

      await expectLater(
        depot.transaction(() async {
          await depot.upsertCheval(
              identiteComposite(nom: 'INTERROMPU 1', anneeNaissance: 2018));
          await depot.upsertCheval(
              identiteComposite(nom: 'INTERROMPU 2', anneeNaissance: 2018));
          throw StateError('interruption simulée');
        }),
        throwsA(isA<StateError>()),
      );

      expect(await depot.compterChevaux(), avant,
          reason: 'consigne §14 : une interruption ne doit rien laisser de partiel');
    });

    test('rejouer une étape ne duplique rien (idempotence)', () async {
      final id = identiteComposite(nom: 'REJEU', anneeNaissance: 2019);
      await depot.upsertCheval(id);
      await depot.upsertCheval(id);
      await depot.upsertCheval(id);
      expect(await depot.compterChevaux(), 1);
    });
  });

  group('Conflits et journal', () {
    test('un conflit est enregistré en attente, jamais résolu seul', () async {
      await depot.enregistrerConflit(
        categorie: 'elo',
        description: 'Ratings divergents pour la même clé',
        cleEntite: 'X|TROT_ATTELE',
        valeurLocale: '1500',
        valeurDistante: '1520',
      );
      expect(await depot.compterConflits(resolution: 'en_attente'), 1);
      expect(await depot.compterConflits(resolution: 'auto'), 0,
          reason: 'D-24 : aucune fusion arbitraire, aucune résolution automatique');
    });

    test('le journal permet de reprendre une opération', () async {
      await depot.journaliser(
          operation: 'migration_v1', etape: 'elo', statut: 'termine');
      final lignes = await depot.journalDeLOperation('migration_v1');
      expect(lignes.length, 1);
      expect(lignes.single['etape'], 'elo');
    });
  });

  group('Politiques de conservation', () {
    test('chaque catégorie de la base a une politique déclarée', () {
      expect(RegistrePolitiques.pour('faits_courses'), isNotNull);
      expect(RegistrePolitiques.pour('ratings_elo'), isNotNull);
      expect(RegistrePolitiques.pour('rapports'), isNotNull);
      expect(RegistrePolitiques.pour('bilans'), isNotNull);
      expect(RegistrePolitiques.pour('pronostics_archives'), isNotNull);
    });

    test('aucune table permanente n\'est marquée purgeable', () {
      for (final nom in kTablesPermanentes) {
        expect(kTablesAPurgeExplicite.contains(nom), isFalse,
            reason: '$nom est permanente et ne peut pas être dans la liste purgeable');
      }
    });

    test('ELO et rapports sont déclarés permanents', () {
      expect(RegistrePolitiques.pour('ratings_elo')!.conservationPermanente, isTrue);
      expect(RegistrePolitiques.pour('rapports')!.conservationPermanente, isTrue);
      expect(RegistrePolitiques.pour('pronostics_actifs')!.conservationPermanente,
          isFalse);
      expect(RegistrePolitiques.pour('pronostics_archives')!.conservationPermanente,
          isTrue);
    });
  });
}
