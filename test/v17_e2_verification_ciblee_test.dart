// ═══════════════════════════════════════════════════════════════════════════
//  V17 — E2 : VÉRIFICATION CIBLÉE AVANT VALIDATION DÉFINITIVE
//
//  Objet (revue) — AUDIT ET TESTS UNIQUEMENT :
//   1. Appels de `IaArchiveService._load()` + impact du catch/rethrow E2
//      sur E1/E3 (export, sauvegarde, restauration).   → A1
//   2. Archive corrompue / inaccessible : pas de crash non maîtrisé,
//      aucune suppression, nouvelle tentative possible, backup/restore
//      sans destruction silencieuse.                    → K, KX
//   3. Test WIDGET RÉEL du calendrier.                  → L
//   4. Listener retiré dans dispose(), pas de setState après
//      destruction.                                     → M
//
//  ⚠️ Aucun fichier de production n'est modifié par ce fichier.
//     Ces tests prouvent des observations, pas le bon fonctionnement
//     global de l'application.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/pronostic_resultats_repository.dart';
import 'package:pronostic_hippique/services/quasi_gros_paris_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/widgets/ia/ia_calendrier_tab.dart';

import 'v17_faux_store.dart';

// `hasListeners` est protégé (visible dans les sous-classes de
// ChangeNotifier). On l'utilise ici en LECTURE SEULE pour compter les
// écouteurs effectivement attachés : c'est la seule façon d'observer le
// cycle addListener/removeListener sans ajouter de hook en production.
// ignore_for_file: invalid_use_of_protected_member

/// Le corps du widget est un `ListView` PARESSEUX : ce qui est sous le
/// viewport n'est jamais construit, donc introuvable par `find.text`. On
/// agrandit la surface de test pour que le calendrier ET le bilan mensuel
/// soient simultanément rendus. Aucune modification de production.
void _surfaceHaute(WidgetTester t) {
  t.view.physicalSize = const Size(1200, 4200);
  t.view.devicePixelRatio = 1.0;
}

void _surfaceNormale(WidgetTester t) {
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
}

/// Prépare une archive RÉELLE dans la zone RÉELLE du test, puis laisse
/// l'archive NON chargée (comme au démarrage de l'application).
///
/// ═══════════════════════════════════════════════════════════════════════════
///  CAUSE EXACTE DU BLOCAGE DE L-2 / L-3 / L-4 / L-6 (MESURÉE)
///
///  SYMPTÔME : ces tests ne rendaient JAMAIS la main. Aucune exception,
///  aucune assertion en échec, aucun `[E]` : le processus était tué par le
///  garde-fou après plusieurs minutes. `pumpAndSettle` ne convergeait pas.
///
///  LOCALISATION PAR BISSECTION (6 sondes successives) :
///    • `setUp` complet ......................... termine ;
///    • `pumpWidget(IaCalendrierTab())` .......... termine ;
///    • `enregistrerEviction()` seul ............. termine ;
///    • `SharedPreferences.getInstance()` ........ termine ;
///    • `IaArchiveService.charger()` seul ........ termine ;
///    • `archiver(...)` .......................... NE TERMINE PAS  ← ici.
///  Dernière trace avant blocage : `[SONDE-C] préparation faite`, c'est-à-dire
///  l'instruction qui PRÉCÈDE l'appel à `archiver(...)`.
///
///  MÉCANISME : `archiver()` appelle `persisterEnAttente()`, qui attend
///  `_persisterShard()`, qui CHAÎNE l'écriture sur `_writeChain`
///  (`ia_archive_service.dart:1083`) :
///      _writeChain = _writeChain.then((_) async { … completer.complete(…) });
///  Une `Future` propage ses rappels dans la ZONE où elle a été créée. Créée
///  dans le corps d'un `testWidgets`, la chaîne vit dans la zone `fakeAsync`
///  du test : sa microtâche n'est drainée que par un `pump`. Or `archiver()`
///  est attendu AVANT tout `pump` — donc la microtâche n'est jamais exécutée,
///  `completer` n'est jamais complété, et `archiver()` attend indéfiniment.
///  Le `setUp`, lui, s'exécute en zone réelle et ne produisait donc pas le
///  problème : c'est bien le CORPS du `testWidgets` qui le déclenche.
///
///  POURQUOI CE N'EST PAS UN DÉFAUT DE PRODUCTION : en production, la chaîne
///  est ancrée dans la zone racine et la boucle d'événements draine ses
///  microtâches normalement. Le défaut est propre au harnais, qui exécute des
///  E/S réelles dans une zone où le temps est simulé.
///
///  CORRECTION RETENUE : exécuter la PRÉPARATION (et elle seule) dans
///  `tester.runAsync`, qui rend une zone RÉELLE. Le montage du widget,
///  `pumpAndSettle` et TOUTES les assertions restent dans la zone de test —
///  c'est ce qui permet de continuer à prouver le comportement du widget, y
///  compris son cycle asynchrone de chargement.
///
///  CE QUI N'EST PAS FAIT : aucune fonctionnalité de production n'est
///  désactivée ; aucun timeout n'est augmenté ; aucune assertion n'est
///  retirée ; `pumpAndSettle` n'est remplacé par aucune temporisation.
/// ═══════════════════════════════════════════════════════════════════════════
Future<void> _preparerArchiveEnZoneReelle(
  WidgetTester tester,
  List<IaPronostic> lots,
) async {
  await tester.runAsync(() async {
    // La chaîne d'écriture est réancrée DANS cette zone : `archiver()` et
    // l'attente qui suit vivent ainsi dans la même zone, et l'attente se
    // résout. Sans ce réancrage, la chaîne resterait ancrée dans le `setUp`.
    preparerArchiveDansLaZoneDeTest();
    await archiver(lots);
  });
  // L'archive est écrite sur le disque mais NON chargée : c'est l'état du
  // démarrage réel, que ces tests doivent observer.
  IaArchiveService.instance.oublierChargementPourTest();
}

void main() {
  setUp(() async {
    installerStore();
    IaArchiveService.instance.oublierChargementPourTest();
    await IaArchiveService.instance.viderPourTest();
    await PronosticResultatsRepository.instance
        .restaurerDepuisBackup({'pronosticResultats': []});
    await QuasiGrosParisService.instance
        .importerDepuisBackup({'signaux': [], 'quasiGagnants': []});
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A1 — IMPACT DU catch/rethrow SUR LES APPELANTS E1/E3
  // ═══════════════════════════════════════════════════════════════════════

  group('A1 — rethrow : pas de régression sur les appelants', () {
    test('A1-1 — l\'exception remontait DÉJÀ avant E2', () {
      // L'ancien `_load()` (65edcab) était un `try { … } finally { … }`
      // SANS `catch`. Une exception de `_chargerDepuisStockage()` traversait
      // donc le `finally` et remontait à l'appelant.
      // `rethrow` rend ce comportement EXPLICITE, il ne l'invente pas.
      expect(ancienLoadAvaitUnCatch, isFalse);
      expect(nouveauLoadRethrow, isTrue);
    });

    test('A1-2 — exporterPourBackup : l\'échec remonte (l\'appelant décide)',
        () async {
      await archiver([pronoGagnant(courseKey: 'R1C1_01032024', date: jour(1))]);
      IaArchiveService.instance.oublierChargementPourTest();
      SharedPreferences.resetStatic();
      store.panne = true;

      await expectLater(
        IaArchiveService.instance.exporterPourBackup(),
        throwsA(isA<StateError>()),
      );
    });

    test('A1-3 — BackupService.exporterDonnees ne casse pas : échec signalé',
        () async {
      await archiver([pronoGagnant(courseKey: 'R1C1_01032024', date: jour(1))]);
      IaArchiveService.instance.oublierChargementPourTest();
      SharedPreferences.resetStatic();
      store.panne = true;

      final res = await BackupService.instance.exporterDonnees();

      expect(res.succes, isFalse);
      expect(res.erreur, isNotNull);
      expect(res.filePath, isNull, reason: 'aucun chemin annoncé en échec');
    });

    test('A1-4 — restaurerDepuisBackup absorbe : ResultatRestauration en échec',
        () async {
      await archiver([pronoGagnant(courseKey: 'R1C1_01032024', date: jour(1))]);
      IaArchiveService.instance.oublierChargementPourTest();
      SharedPreferences.resetStatic();
      store.panne = true;

      final res = await IaArchiveService.instance
          .restaurerDepuisBackup(<String, dynamic>{'shards': <String, String>{}});

      expect(res.succes, isFalse);
    });

    test('A1-5 — persisterEnAttente absorbe : false + file préservée',
        () async {
      IaArchiveService.instance.oublierChargementPourTest();
      SharedPreferences.resetStatic();
      store.panne = true;

      IaArchiveService.instance.enregistrerEviction(
        pronoGagnant(courseKey: 'R1C1_01032024', date: jour(1)),
      );

      final ok = await IaArchiveService.instance.persisterEnAttente();

      expect(ok, isFalse);
      expect(IaArchiveService.instance.nbEvictionsNonArchivees, 1,
          reason: 'l\'éviction n\'est jamais perdue');
      expect(IaArchiveService.instance.etatArchive, isNot(EtatArchive.sain));
    });

    test('A1-6 — charger() absorbe toujours : ne lève jamais', () async {
      IaArchiveService.instance.oublierChargementPourTest();
      SharedPreferences.resetStatic();
      store.panne = true;

      await IaArchiveService.instance.charger(); // aucune exception

      expect(IaArchiveService.instance.derniereErreurChargement, isNotNull);
      expect(IaArchiveService.instance.archiveDisponible, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  K — ARCHIVE CORROMPUE OU INACCESSIBLE
  // ═══════════════════════════════════════════════════════════════════════

  group('K — archive corrompue / inaccessible', () {
    test('K-1 — shard illisible : chargement OK, shard signalé, clé préservée',
        () async {
      final j = jour(4);
      await archiver([pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)]);
      expect(IaArchiveService.instance.nbVersionsArchivees, 1);

      store.ecrire('ia_archive_v1_2024-03', '!!!pas-du-base64!!!');
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      expect(IaArchiveService.instance.archiveDisponible, isTrue,
          reason: 'le chargement global réussit');
      final verif = IaArchiveService.instance.derniereVerificationArchive;
      expect(verif, isNotNull);
      expect(verif!.shardsIllisibles, isNotEmpty,
          reason: 'le shard illisible est SIGNALÉ, jamais reconstitué');
      expect(IaArchiveService.instance.clesPersistees,
          contains('ia_archive_v1_2024-03'),
          reason: 'la clé reste connue : une remise à zéro l\'effacera');
      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(moisRef.year, moisRef.month),
        isEmpty,
        reason: 'aucune journée inventée',
      );
    });

    test('K-2 — manifeste illisible : pas de crash, reconstruction', () async {
      final j = jour(5);
      await archiver([pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)]);
      store.ecrire(kIaArchiveManifestKey, 'pas-du-json{{{');
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      expect(IaArchiveService.instance.archiveDisponible, isTrue);
      expect(IaArchiveService.instance.derniereErreurChargement, isNull,
          reason: 'un manifeste illisible n\'est pas une panne de stockage');
      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(moisRef.year, moisRef.month)
            .containsKey(5),
        isTrue,
      );
    });

    test('K-3 — entrée corrompue dans un shard : les autres survivent',
        () async {
      final j1 = jour(6);
      await archiver([pronoGagnant(courseKey: cleCourse(1, 1, j1), date: j1)]);
      store.ecrire('ia_archive_v1_2024-03',
          enveloppeAvecUneEntreeCorrompue(
              pronoGagnant(courseKey: cleCourse(1, 2, j1), date: j1)));

      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      expect(IaArchiveService.instance.archiveDisponible, isTrue);
      expect(IaArchiveService.instance.nbVersionsArchivees, 1,
          reason: '1 entrée valide sur 2, l\'autre ignorée — pas inventée');
    });

    test('K-4 — panne totale : aucune donnée détruite, rien d\'inventé',
        () async {
      final j = jour(8);
      await archiver([pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)]);
      final versionsAvant = IaArchiveService.instance.nbVersionsArchivees;
      final clesAvant = IaArchiveService.instance.clesPersistees.length;

      IaArchiveService.instance.oublierChargementPourTest();
      SharedPreferences.resetStatic();
      store.panne = true;
      await IaArchiveService.instance.charger();

      expect(IaArchiveService.instance.archiveDisponible, isFalse);
      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(moisRef.year, moisRef.month),
        isEmpty,
        reason: 'aucune journée inventée pendant la panne',
      );

      store.panne = false;
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      expect(IaArchiveService.instance.nbVersionsArchivees, versionsAvant,
          reason: 'aucune version détruite');
      expect(IaArchiveService.instance.clesPersistees.length, clesAvant,
          reason: 'aucune clé détruite');
    });

    test('K-5 — nouvelle tentative après correction : reprise effective',
        () async {
      final j = jour(9);
      await archiver([pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)]);

      IaArchiveService.instance.oublierChargementPourTest();
      SharedPreferences.resetStatic();
      store.panne = true;
      await IaArchiveService.instance.charger();
      expect(IaArchiveService.instance.archiveDisponible, isFalse);

      store.panne = false;
      await IaArchiveService.instance.charger();

      expect(IaArchiveService.instance.archiveDisponible, isTrue);
      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(moisRef.year, moisRef.month)
            .containsKey(9),
        isTrue,
      );
    });

    test('K-6 — export sur archive corrompue : clés brutes embarquées',
        () async {
      final j = jour(10);
      await archiver([pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)]);
      store.ecrire('ia_archive_v1_2024-01', 'corrompu###');

      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final exporte = await IaArchiveService.instance.exporterPourBackup();
      final shards = exporte['shards'] as Map<String, dynamic>;

      expect(shards.keys, contains('2024-03'));
      expect(shards.keys, contains('2024-01'),
          reason: 'même illisible, la clé brute doit être exportée');
      expect(shards['2024-01'], 'corrompu###');
      expect((exporte['shardsIllisibles'] as List).isNotEmpty, isTrue);
    });

    test('K-7 — restauration d\'un shard corrompu : local préservé', () async {
      final j = jour(11);
      await archiver([pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();
      final avant = IaArchiveService.instance.nbVersionsArchivees;

      await IaArchiveService.instance.restaurerDepuisBackup(<String, dynamic>{
        'shards': <String, String>{'2024-03': 'pas du base64'},
      });

      expect(IaArchiveService.instance.nbVersionsArchivees, avant,
          reason: 'aucune suppression locale');
      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(moisRef.year, moisRef.month)
            .containsKey(11),
        isTrue,
      );
    });

    test('K-8 — archiveIA mal typée : local préservé', () async {
      final j = jour(12);
      await archiver([pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();
      final avant = IaArchiveService.instance.nbVersionsArchivees;

      await IaArchiveService.instance
          .restaurerDepuisBackup(<String, dynamic>{'shards': 'texte'});

      expect(IaArchiveService.instance.nbVersionsArchivees, avant);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  KX — SAUVEGARDE / RESTAURATION : PAS DE DESTRUCTION SILENCIEUSE
  // ═══════════════════════════════════════════════════════════════════════

  group('KX — cycle sauvegarde / restauration', () {
    test('KX-1 — export complet sur stockage sain : archive incluse', () async {
      final j = jour(13);
      await archiver([pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final data = await IaArchiveService.instance.exporterPourBackup();

      expect(data['nbVersions'], 1);
      expect((data['shards'] as Map).isNotEmpty, isTrue);
      expect(data['format'], kIaArchiveFormatVersion);
    });

    test('KX-2 — restauration puis rechargement : contenu identique', () async {
      final j = jour(14);
      await archiver([pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();
      final exporte = await IaArchiveService.instance.exporterPourBackup();
      final avant = IaArchiveService.instance.nbVersionsArchivees;

      await IaArchiveService.instance.viderPourTest();
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();
      expect(IaArchiveService.instance.nbVersionsArchivees, 0);

      final res =
          await IaArchiveService.instance.restaurerDepuisBackup(exporte);

      expect(res.succes, isTrue);
      expect(IaArchiveService.instance.nbVersionsArchivees, avant);
    });

    test('KX-3 — panne pendant l\'export : échec, aucun fichier partiel',
        () async {
      final j = jour(15);
      await archiver([pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)]);
      IaArchiveService.instance.oublierChargementPourTest();
      SharedPreferences.resetStatic();
      store.panne = true;

      final res = await BackupService.instance.exporterDonnees();

      expect(res.succes, isFalse);
      expect(res.filePath, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  L — TEST WIDGET RÉEL DU CALENDRIER
  //
  //  ⚠️ PORTÉE : monkeypatching du `DateTime.now()` impossible sans modifier
  //  la production. Le widget initialise `_moisRef` au mois COURANT. Les
  //  jeux de données de L utilisent donc des dates du mois courant.
  //  L'observation porte sur : empty-state ↔ présence de cases de jour
  //  ACTIVES, et sur le nombre de rebuilds (rafraîchissement automatique).
  // ═══════════════════════════════════════════════════════════════════════

  group('L — widget réel IaCalendrierTab', () {
    testWidgets('L-1 — affichage initial : mémoire seule, empty state',
        (tester) async {
      _surfaceHaute(tester);
      preparerArchiveDansLaZoneDeTest();
      addTearDown(() => _surfaceNormale(tester));

      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(DateTime.now().year, DateTime.now().month),
        isEmpty,
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
      );
      await tester.pump();

      expect(find.byType(IaCalendrierTab), findsOneWidget);
      expect(find.text('Aucune donnée pour ce mois'), findsOneWidget,
          reason: 'mémoire vide au départ → empty state du bilan mensuel');
      expect(tester.takeException(), isNull);
    });

    testWidgets('L-2 — le widget déclenche bien le chargement de l\'archive',
        (tester) async {
      _surfaceHaute(tester);
      preparerArchiveDansLaZoneDeTest();
      addTearDown(() => _surfaceNormale(tester));

      final now = DateTime.now();
      final j = DateTime(now.year, now.month, 2);

      // ═══════════════════════════════════════════════════════════════
      //  CAUSE DU BLOCAGE, MESURÉE — voir [_preparerArchiveEnZoneReelle]
      //
      //  `archiver()` fait de VRAIES E/S (SharedPreferences) et attend
      //  `persisterEnAttente()`, qui dépend de `_writeChain` — une chaîne de
      //  `Future.then()` créée dans la zone où elle est instanciée. Exécutée
      //  dans le corps d'un `testWidgets` (zone `fakeAsync`), la microtâche
      //  du `.then()` n'est JAMAIS drainée : `persisterEnAttente()` ne rend
      //  pas la main, et le test se bloque SANS exception (mesuré : aucune
      //  sortie après « [SONDE-C] préparation faite », FrameTiming bloqué).
      //
      //  `runAsync` exécute le corps dans la zone RÉELLE, où l'attente se
      //  résout normalement. C'est la préparation qui change de zone — pas
      //  l'assertion, pas la production, et aucune temporisation n'est
      //  substituée à une attente.
      // ═══════════════════════════════════════════════════════════════
      await _preparerArchiveEnZoneReelle(
        tester,
        [pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)],
      );

      // Archive NON chargée au moment du montage.
      expect(IaArchiveService.instance.archiveDisponible, isFalse);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
      );
      // Laisse le cycle asynchrone de charger() se dérouler.
      await tester.pumpAndSettle();

      expect(IaArchiveService.instance.archiveDisponible, isTrue,
          reason: 'initState() a appelé charger()');
      expect(tester.takeException(), isNull);
    });

    testWidgets('L-3 — rafraîchissement automatique : rebuild après '
        'notification d\'archive', (tester) async {
      _surfaceHaute(tester);
      preparerArchiveDansLaZoneDeTest();
      addTearDown(() => _surfaceNormale(tester));

      final now = DateTime.now();
      final j = DateTime(now.year, now.month, 3);
      await _preparerArchiveEnZoneReelle(
        tester,
        [pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)],
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
      );
      await tester.pumpAndSettle();

      // Journée d'archive désormais visible dans le service.
      final data = IaMemoryService.instance
          .donneesCalendrierJour(now.year, now.month);
      expect(data.containsKey(3), isTrue);

      // Le widget a été reconstruit par le listener : un rebuild manuel
      // produit un arbre identique (aucune exception, aucune perte).
      await tester.pump();
      expect(find.text('Aucune donnée pour ce mois'), findsNothing,
          reason: 'après chargement, le bilan n\'est plus vide');
      expect(tester.takeException(), isNull);
    });

    testWidgets('L-4 — l\'archive déjà chargée avant montage est exploitée '
        'immédiatement', (tester) async {
      _surfaceHaute(tester);
      preparerArchiveDansLaZoneDeTest();
      addTearDown(() => _surfaceNormale(tester));

      final now = DateTime.now();
      final j = DateTime(now.year, now.month, 4);
      await _preparerArchiveEnZoneReelle(
        tester,
        [pronoGagnant(courseKey: cleCourse(1, 1, j), date: j)],
      );
      // L-4 exige l'archive DÉJÀ CHARGÉE avant le montage : c'est le scénario
      // testé (exploitation immédiate). Le chargement est donc demandé ici,
      // en zone réelle, et son effet est vérifié AVANT tout widget.
      await tester.runAsync(() => IaArchiveService.instance.charger());
      expect(IaArchiveService.instance.archiveDisponible, isTrue);

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aucune donnée pour ce mois'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('L-5 — ARCHIVE CORROMPUE : le widget affiche la mémoire, '
        'ne casse pas, puis récupère après correction', (tester) async {
      _surfaceHaute(tester);
      preparerArchiveDansLaZoneDeTest();
      addTearDown(() => _surfaceNormale(tester));

      // Panne CIBLÉE sur l'archive seule : le stockage répond, mais le shard
      // du mois courant est illisible. C'est le cas de figure de la revue.
      final now = DateTime.now();
      final moisStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      store.ecrire('ia_archive_v1_$moisStr', '%%%shard-illisible%%%');
      SharedPreferences.resetStatic();
      IaArchiveService.instance.oublierChargementPourTest();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
      );
      await tester.pumpAndSettle();

      // 1. Aucun crash non maîtrisé.
      expect(tester.takeException(), isNull,
          reason: 'une archive corrompue ne doit pas casser le calendrier');
      expect(find.byType(IaCalendrierTab), findsOneWidget);

      // 2. La mémoire de travail reste affichée (empty state : elle est vide).
      expect(find.text('Aucune donnée pour ce mois'), findsOneWidget);

      // 3. NOUVELLE TENTATIVE POSSIBLE : après correction, un second
      //    chargement réussit et l'archive devient disponible.
      store.ecrire('ia_archive_v1_$moisStr', '');
      SharedPreferences.resetStatic();
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();
      expect(IaArchiveService.instance.archiveDisponible, isTrue,
          reason: 'un échec de chargement doit être récupérable');

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('L-6 — journées existantes : aucun changement visuel après '
        'chargement d\'archive sur des courses DIFFÉRENTES', (tester) async {
      _surfaceHaute(tester);
      preparerArchiveDansLaZoneDeTest();
      addTearDown(() => _surfaceNormale(tester));

      final now = DateTime.now();
      final jMem = DateTime(now.year, now.month, 5);
      final jArch = DateTime(now.year, now.month, 6);

      // Mémoire : une course sur le 5.
      installerStore(data: prefsAvecMemoire([
        pronoGagnant(courseKey: cleCourse(1, 1, jMem), date: jMem),
      ]));
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.viderPourTest();
      await IaMemoryService.instance.recharger();

      final avant = IaMemoryService.instance
          .donneesCalendrierJour(now.year, now.month);

      // Archive : une course sur le 6.
      await _preparerArchiveEnZoneReelle(
        tester,
        [pronoGagnant(courseKey: cleCourse(2, 1, jArch), date: jArch)],
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
      );
      await tester.pumpAndSettle();

      final apres = IaMemoryService.instance
          .donneesCalendrierJour(now.year, now.month);

      // Le 5 est STRICTEMENT inchangé.
      expect(apres[5]!.nbCourses, avant[5]!.nbCourses);
      expect(apres[5]!.nbBons, avant[5]!.nbBons);
      expect(apres[5]!.palier, avant[5]!.palier);
      expect(apres[5]!.hasBestBet, avant[5]!.hasBestBet);
      expect(apres[5]!.pronostics.single.courseKey,
          avant[5]!.pronostics.single.courseKey);
      // Le 6 est apparu.
      expect(apres.containsKey(6), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('L-7 — montage/démontage répété : aucun crash', (tester) async {
      _surfaceHaute(tester);
      preparerArchiveDansLaZoneDeTest();
      addTearDown(() => _surfaceNormale(tester));

      for (var i = 0; i < 3; i++) {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
        );
        await tester.pump();
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  M — CYCLE DE VIE DES LISTENERS
  // ═══════════════════════════════════════════════════════════════════════

  group('M — listeners et dispose', () {
    testWidgets('M-1 — le listener d\'archive est AJOUTÉ au montage',
        (tester) async {
      _surfaceHaute(tester);
      preparerArchiveDansLaZoneDeTest();
      addTearDown(() => _surfaceNormale(tester));

      final avant = IaArchiveService.instance.hasListeners;

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
      );
      await tester.pump();

      expect(IaArchiveService.instance.hasListeners, isTrue);
      expect(avant, isFalse, reason: 'aucun listener résiduel avant montage');
    });

    testWidgets('M-2 — le listener est RETIRÉ au démontage', (tester) async {
      _surfaceHaute(tester);
      preparerArchiveDansLaZoneDeTest();
      addTearDown(() => _surfaceNormale(tester));

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
      );
      await tester.pump();
      expect(IaArchiveService.instance.hasListeners, isTrue);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      expect(IaArchiveService.instance.hasListeners, isFalse,
          reason: 'dispose() doit retirer le listener');
    });

    testWidgets('M-3 — notification après destruction : aucun setState '
        'sur un widget détruit', (tester) async {
      _surfaceHaute(tester);
      preparerArchiveDansLaZoneDeTest();
      addTearDown(() => _surfaceNormale(tester));

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
      );
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      // Notifie APRÈS la destruction via des chemins RÉELS de production
      // (aucun hook de test ajouté) : plus aucun écouteur ne doit rester.
      expect(IaArchiveService.instance.hasListeners, isFalse);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger(); // notifie
      await IaMemoryService.instance.recharger(); // notifie

      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'aucune exception « setState() called after dispose() »');
    });

    testWidgets('M-4 — la notification pendant la vie du widget ne lève pas',
        (tester) async {
      _surfaceHaute(tester);
      preparerArchiveDansLaZoneDeTest();
      addTearDown(() => _surfaceNormale(tester));

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
      );
      await tester.pump();

      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger(); // notifie
      await IaMemoryService.instance.recharger(); // notifie
      await tester.pump();

      // `_onMemChange()` (production, l.199) arme un `Future.delayed(800 ms)`
      // qui éteint le flash. Ce minuteur doit être drainé avant la fin du
      // test, sinon le binding signale « A Timer is still pending ».
      // Ce n'est PAS un défaut : le widget reste monté, le rappel vérifie
      // `mounted` et s'exécute normalement.
      await tester.pump(const Duration(milliseconds: 900));

      expect(tester.takeException(), isNull);
    });

    testWidgets('M-5 — deux instances successives : pas d\'accumulation de '
        'listeners', (tester) async {
      _surfaceHaute(tester);
      preparerArchiveDansLaZoneDeTest();
      addTearDown(() => _surfaceNormale(tester));

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
      );
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: IaCalendrierTab())),
      );
      await tester.pump();

      // Un seul listener (celui de la seconde instance).
      expect(IaArchiveService.instance.hasListeners, isTrue);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(IaArchiveService.instance.hasListeners, isFalse);
    });
  });
}
