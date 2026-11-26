/// Reprise après interruption d'une restauration ou d'un retour arrière.
///
/// Consigne §1 du présent tour :
/// > « Vérifie également la récupération après interruption du processus
/// > pendant une restauration ou un retour arrière. Le journal d'intention doit
/// > permettre une reprise sécurisée au prochain démarrage. Ne te contente pas
/// > de documenter cette limite si une correction technique est réalisable. »
///
/// Ce que ces tests prouvent, et comment :
///
/// * Une interruption **pendant les écritures** laisse un état mixte. La méta
///   `restauration_en_cours` porte le chemin de l'instantané ; `reprendre()`
///   rejoue le retour arrière et rétablit l'état antérieur. **Prouvé** par
///   simulation exacte de l'état intermédiaire (instantané écrit, intention
///   déclarée, écritures partielles, processus arrêté).
/// * Une interruption **après les écritures mais avant les contrôles** ne doit
///   PAS déclencher un retour arrière : les données sont complètes et les
///   annuler détruirait une restauration réussie. **Prouvé** par la méta
///   `restauration_appliquee` posée avant les contrôles.
/// * Une interruption **pendant le retour arrière lui-même** est réparable :
///   `annuler()` est idempotent, donc `reprendre()` le rejoue et obtient le
///   même état final. **Prouvé** par double rejeu.
/// * Un instantané disparu n'est pas compensé par une supposition : l'état est
///   déclaré irrécupérable, et **aucune donnée n'est supprimée**.
///
/// Ce qui n'est PAS prouvé ici : un arrêt brutal du système d'exploitation
/// (coupure d'alimentation). Le test simule l'état intermédiaire sur disque, ce
/// qui est le même état observable ; il ne simule pas une perte de tampon
/// d'écriture du noyau. Ce point relève d'une validation sur appareil réel et
/// est signalé comme tel dans le rapport final.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/depot_sqlite.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/pont_elo.dart';
import 'package:pronostic_hippique/data/connaissances/_core/depot.dart';
import 'package:pronostic_hippique/data/connaissances/_sauvegarde/format_sauvegarde.dart';
import 'package:pronostic_hippique/data/connaissances/_sauvegarde/restaurateur.dart';
import 'package:pronostic_hippique/data/connaissances/_sauvegarde/transaction_globale.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Injecte un répertoire temporaire réel : `getTemporaryDirectory()` lève en
/// environnement de test. Même faux que `v5_backup_restore_test.dart`.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tmpPath);
  final String tmpPath;

  @override
  Future<String?> getTemporaryPath() async => tmpPath;
}

void main() {
  late Directory racine;
  late DepotSqlite depot;
  const restaurateur = Restaurateur();
  const format = FormatSauvegarde();

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    racine = await Directory.systemTemp.createTemp('ptg_reprise_');
    PathProviderPlatform.instance = _FakePathProvider(racine.path);
    PontElo.instance.utiliserFabrique(databaseFactoryFfi);
    final ok = await PontElo.instance.ouvrir(racineForcee: racine.path);
    expect(ok, isTrue, reason: 'le dépôt doit s\'ouvrir pour ce test');
    depot = PontElo.instance.depotPourSauvegarde!;

    for (final sous in <String>['base', 'archives', 'config', 'temp']) {
      final d = Directory('${racine.path}/$sous');
      if (!await d.exists()) await d.create(recursive: true);
    }
  });

  tearDown(() async {
    await PontElo.instance.fermer();
    if (await racine.exists()) await racine.delete(recursive: true);
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Reprise après interruption', () {
    test('aucun travail en cours : reprendre() ne fait rien', () async {
      final r = await restaurateur.reprendre(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
        versionLocale: 'test',
      );
      expect(r, isNull,
          reason: 'une installation saine ne doit rien avoir à reprendre');
      // Et surtout : aucune écriture, aucun retour arrière inutile.
      expect(await depot.lireMeta(kMetaRestaurationEnCours), isNull);
    });

    test(
        'interruption PENDANT les écritures : le retour arrière est rejoué et '
        'l\'état antérieur est rétabli', () async {
      // ── 1. État initial : 3 ratings + une clé prefs ────────────────────
      await depot.upsertEloEnLot(<LigneElo>[
        const LigneElo(cle: 'ALPHA|trot', nomOrigine: 'ALPHA', discipline: 'trot', rating: 1500.0, nb: 0, var_: 0.0),
        const LigneElo(cle: 'BETA|trot', nomOrigine: 'BETA', discipline: 'trot', rating: 1600.0, nb: 0, var_: 0.0),
        const LigneElo(cle: 'GAMMA|galop', nomOrigine: 'GAMMA', discipline: 'galop', rating: 1400.0, nb: 0, var_: 0.0),
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', '{"forme":0.31}');
      await prefs.setInt('compteur_essai', 7);

      final etatEloAvant = <String, double>{
        for (final l in await depot.tousLesElo()) l.cle: l.rating,
      };

      // ── 2. Simuler EXACTEMENT une restauration interrompue ─────────────
      // On reproduit ce que fait le code de production jusqu'à l'instant
      // fatal : instantané capturé, intention déclarée, puis écritures
      // partielles, puis plus rien.
      final transaction = TransactionGlobale(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
        versionLocale: 'test',
      );
      final instantane = await transaction.capturer(
        nom: 'avant_restauration',
      );
      await transaction.declarerIntention(
        operation: kOperationRestaurationPtg,
        clesPrefsTouchees: <String>['ia_poids_v3'],
        cheminInstantane: instantane.chemin,
      );
      depot.ecrireMeta(kMetaRestaurationEnCours, instantane.chemin);
      depot.ecrireMeta(kMetaRestaurationAppliquee, '');

      // Écritures partielles : une clé prefs modifiée ET une clé apparue, un
      // rating modifié, un rating ajouté. C'est un état mixte typique.
      await prefs.setString('ia_poids_v3', '{"forme":0.99}');
      await prefs.setString('cle_apparue_pendant_la_restauration', 'pollution');
      await depot.upsertElo(const LigneElo(
          cle: 'ALPHA|trot', nomOrigine: 'ALPHA', discipline: 'trot', rating: 9999.0, nb: 0, var_: 0.0));
      await depot.upsertElo(const LigneElo(
          cle: 'DELTA|trot', nomOrigine: 'DELTA', discipline: 'trot', rating: 1111.0, nb: 0, var_: 0.0));

      expect(prefs.getString('ia_poids_v3'), '{"forme":0.99}');
      expect(await depot.lireElo('DELTA|trot'), isNotNull,
          reason: 'état intermédiaire : la pollution doit être présente');

      // ── 3. Redémarrage : reprise ───────────────────────────────────────
      final reprise = await restaurateur.reprendre(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
        versionLocale: 'test',
      );

      expect(reprise, isNotNull, reason: 'un travail interrompu doit être vu');
      expect(reprise!.action, ResultatReprise.actionAnnulee);
      expect(reprise.annulation, isNotNull);
      expect(reprise.annulation!.reussie, isTrue,
          reason: 'le retour arrière doit aboutir');

      // ── 4. L'état antérieur est-il réellement rétabli ? ────────────────
      final prefsApres = await SharedPreferences.getInstance();
      expect(prefsApres.getString('ia_poids_v3'), '{"forme":0.31}',
          reason: 'la valeur d\'origine doit être revenue');
      expect(prefsApres.getInt('compteur_essai'), 7);
      expect(prefsApres.containsKey('cle_apparue_pendant_la_restauration'),
          isFalse,
          reason: 'une clé née après l\'instantané doit disparaître, sinon '
              'l\'état reste mixte');

      final eloApres = <String, double>{
        for (final l in await depot.tousLesElo()) l.cle: l.rating,
      };
      expect(eloApres['ALPHA|trot'], 1500.0,
          reason: 'le rating écrasé doit retrouver sa valeur exacte');
      expect(eloApres.length, etatEloAvant.length,
          reason: 'le rating ajouté après l\'instantané doit avoir disparu');

      // ── 5. La méta est nettoyée : plus rien à reprendre ───────────────
      expect((await depot.lireMeta(kMetaRestaurationEnCours)) ?? '', isEmpty);
      expect((await depot.lireMeta(kMetaRestaurationAppliquee)) ?? '', isEmpty);

      final seconde = await restaurateur.reprendre(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
        versionLocale: 'test',
      );
      expect(seconde, isNull,
          reason: 'une reprise traitée ne doit pas être rejouée indéfiniment');
    });

    test(
        'interruption APRÈS les écritures mais AVANT les contrôles : les '
        'données sont conservées, jamais annulées', () async {
      await depot.upsertEloEnLot(<LigneElo>[
        const LigneElo(cle: 'ALPHA|trot', nomOrigine: 'ALPHA', discipline: 'trot', rating: 1500.0, nb: 0, var_: 0.0),
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', '{"forme":0.31}');

      // État intermédiaire n°2 : l'instantané existe, l'intention existe, ET
      // le marqueur « appliquée » est posé — les données sont donc complètes.
      final transaction = TransactionGlobale(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
        versionLocale: 'test',
      );
      final instantane = await transaction.capturer(nom: 'avant_restauration');
      await transaction.declarerIntention(
        operation: kOperationRestaurationPtg,
        clesPrefsTouchees: <String>['ia_poids_v3'],
        cheminInstantane: instantane.chemin,
      );
      depot.ecrireMeta(kMetaRestaurationEnCours, instantane.chemin);
      // Données réellement appliquées :
      await prefs.setString('ia_poids_v3', '{"forme":0.77}');
      await depot.upsertElo(const LigneElo(
          cle: 'NOUVEAU|trot', nomOrigine: 'NOUVEAU', discipline: 'trot', rating: 1234.0, nb: 0, var_: 0.0));
      // Puis le marqueur, juste avant les contrôles — et le processus meurt.
      depot.ecrireMeta(kMetaRestaurationAppliquee, instantane.chemin);

      final reprise = await restaurateur.reprendre(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
        versionLocale: 'test',
      );

      expect(reprise, isNotNull);
      expect(reprise!.action, ResultatReprise.actionControlesRejoues,
          reason: 'des données complètes ne doivent PAS être annulées');
      expect(reprise.annulation, isNull);

      // La restauration survit : c'est le comportement attendu.
      final prefsApres = await SharedPreferences.getInstance();
      expect(prefsApres.getString('ia_poids_v3'), '{"forme":0.77}',
          reason: 'une restauration réussie ne doit pas être défaite par la '
              'reprise');
      expect(await depot.lireElo('NOUVEAU|trot'), isNotNull,
          reason: 'les ratings restaurés doivent être conservés');

      expect((await depot.lireMeta(kMetaRestaurationEnCours)) ?? '', isEmpty);
      expect((await depot.lireMeta(kMetaRestaurationAppliquee)) ?? '', isEmpty);
    });

    test('interruption PENDANT le retour arrière : le rejeu est idempotent',
        () async {
      await depot.upsertEloEnLot(<LigneElo>[
        const LigneElo(cle: 'ALPHA|trot', nomOrigine: 'ALPHA', discipline: 'trot', rating: 1500.0, nb: 0, var_: 0.0),
        const LigneElo(cle: 'BETA|trot', nomOrigine: 'BETA', discipline: 'trot', rating: 1600.0, nb: 0, var_: 0.0),
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', '{"forme":0.31}');

      final transaction = TransactionGlobale(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
        versionLocale: 'test',
      );
      final instantane = await transaction.capturer(nom: 'avant_restauration');

      // Pollution, puis un PREMIER retour arrière mené à son terme.
      await prefs.setString('ia_poids_v3', '{"forme":0.99}');
      await depot.upsertElo(const LigneElo(
          cle: 'ALPHA|trot', nomOrigine: 'ALPHA', discipline: 'trot', rating: 9999.0, nb: 0, var_: 0.0));
      final premier = await transaction.annuler(instantane);
      expect(premier.reussie, isTrue);
      expect(prefs.getString('ia_poids_v3'), '{"forme":0.31}');

      final etatApresPremier = <String, double>{
        for (final l in await depot.tousLesElo()) l.cle: l.rating,
      };

      // Le processus est tué PENDANT `annuler()` : la méta d'intention est
      // toujours présente, comme si le retour arrière n'avait pas été mené au
      // bout. On rejoue donc `annuler()` avec le MÊME instantané.
      depot.ecrireMeta(kMetaRestaurationEnCours, instantane.chemin);
      depot.ecrireMeta(kMetaRestaurationAppliquee, '');

      final reprise = await restaurateur.reprendre(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
        versionLocale: 'test',
      );
      expect(reprise, isNotNull);
      expect(reprise!.action, ResultatReprise.actionAnnulee);
      expect(reprise.annulation!.reussie, isTrue);

      // Idempotence : le second passage n'a rien dégradé.
      expect(prefs.getString('ia_poids_v3'), '{"forme":0.31}');
      final etatApresSecond = <String, double>{
        for (final l in await depot.tousLesElo()) l.cle: l.rating,
      };
      expect(etatApresSecond, etatApresPremier,
          reason: 'rejouer un retour arrière ne doit rien altérer');
    });

    test(
        'instantané disparu : l\'état est déclaré irrécupérable, aucune donnée '
        'n\'est supprimée', () async {
      await depot.upsertEloEnLot(<LigneElo>[
        const LigneElo(cle: 'ALPHA|trot', nomOrigine: 'ALPHA', discipline: 'trot', rating: 1500.0, nb: 0, var_: 0.0),
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', '{"forme":0.42}');

      // Un chemin qui n'existe pas : la protection a disparu.
      depot.ecrireMeta(
          kMetaRestaurationEnCours, '${racine.path}/temp/inexistant.ptg');
      depot.ecrireMeta(kMetaRestaurationAppliquee, '');

      final reprise = await restaurateur.reprendre(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
        versionLocale: 'test',
      );

      expect(reprise, isNotNull);
      expect(reprise!.action, ResultatReprise.actionIrrecuperable);
      expect(reprise.erreur, isNotNull);

      // Le point capital : on ne devine pas, et on ne détruit rien.
      expect(prefs.getString('ia_poids_v3'), '{"forme":0.42}',
          reason: 'une protection disparue n\'autorise aucune suppression');
      expect(await depot.lireElo('ALPHA|trot'), isNotNull);

      // La méta est nettoyée pour ne pas boucler à chaque démarrage, et le
      // diagnostic reste lisible dans le journal.
      expect((await depot.lireMeta(kMetaRestaurationEnCours)) ?? '', isEmpty);
      final journal = await depot.journalDeLOperation('reprise_restauration');
      expect(journal, isNotEmpty);
      expect(journal.last['statut'], 'irrecuperable');
    });

    test('le journal d\'intention porte bien le chemin de l\'instantané',
        () async {
      // Sans ce chemin, la reprise serait impossible : c'est précisément le
      // défaut qui rendait la protection inutilisable. Ce test le verrouille.
      final transaction = TransactionGlobale(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
        versionLocale: 'test',
      );
      final instantane = await transaction.capturer(nom: 'avant_restauration');
      await transaction.declarerIntention(
        operation: kOperationRestaurationPtg,
        clesPrefsTouchees: <String>['a', 'b'],
        cheminInstantane: instantane.chemin,
      );

      final journal =
          await depot.journalDeLOperation(kOperationRestaurationPtg);
      expect(journal, isNotEmpty);
      final intention = journal.firstWhere(
        (l) => l['etape'] == 'intention',
        orElse: () => <String, Object?>{},
      );
      expect(intention, isNotEmpty, reason: 'l\'intention doit être journalisée');
      final detail = jsonDecode('${intention['detail']}') as Map;
      expect(detail['instantane'], instantane.chemin,
          reason: 'le chemin de l\'instantané doit être consigné');
      expect(detail['nb_cles'], 2);
      expect(detail['supports'], contains('shared_preferences'));
    });

    test('l\'instantané couvre réellement les quatre supports', () async {
      await depot.upsertEloEnLot(<LigneElo>[
        const LigneElo(cle: 'ALPHA|trot', nomOrigine: 'ALPHA', discipline: 'trot', rating: 1500.0, nb: 0, var_: 0.0),
      ]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ia_poids_v3', '{}');
      File('${racine.path}/config/reglages.json')
          .writeAsStringSync('{"version":1}');

      final transaction = TransactionGlobale(
        depot: depot,
        dossierTemp: '${racine.path}/temp',
        dossierBase: racine.path,
        versionLocale: 'test',
      );
      final instantane = await transaction.capturer(nom: 'multi_supports');

      expect(instantane.nbClefsPrefs, greaterThan(0));
      expect(instantane.nbLignesSqlite, greaterThan(0));
      expect(instantane.nbFichiers, greaterThan(0),
          reason: 'les fichiers permanents doivent être couverts');
      expect(instantane.inventaireAvant, isNotEmpty,
          reason: 'l\'inventaire d\'avant est nécessaire au contrôle de '
              'cohérence d\'après restauration');
      expect(File(instantane.chemin).existsSync(), isTrue);

      // Le fichier de config est réellement dans l'instantané : on le vérifie
      // en le relisant, pas en le supposant.
      final contenu = File(instantane.chemin).readAsStringSync();
      final bloc = format.extraireBloc(contenu, 'fichiers_permanents') as Map;
      expect(bloc.keys, contains('config/reglages.json'));
    });
  });
}
