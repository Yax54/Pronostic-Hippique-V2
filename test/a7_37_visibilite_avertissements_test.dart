// ═══════════════════════════════════════════════════════════════════════════
//  A7 / 3.3-C12 — VISIBILITÉ DES AVERTISSEMENTS DE SAUVEGARDE
//
//  OBJET : prouver que l'interface DISTINGUE trois issues d'export —
//  complète, complète avec avertissements, échouée — et que le texte affiché
//  décrit l'état RÉEL du fichier produit.
//
//  CE QUE CE FICHIER TESTE, ET CE QU'IL NE TESTE PAS
//  ─────────────────────────────────────────────────
//  • ICI : la DÉCISION D'AFFICHAGE de la vraie section Profil — quel widget
//    apparaît, avec quel texte, combien de temps, et comment il se ferme.
//  • AILLEURS (`a7_38_…`) : les opérations du SERVICE — collecte unique,
//    chemin de fichier, avertissements, trois états de `partageOuvert`.
//
//  ⚠️ POURQUOI LES OPÉRATIONS SONT SIMULÉES — MESURÉ, PAS SUPPOSÉ
//    Dans `testWidgets`, un `await` portant sur une E/S réelle ne reprend
//    JAMAIS, même après 1,5 s de temps réel et même sous `runAsync` :
//        [S6a] TERMINE en 94 ms        (hors widget, service réel)
//        [S6b] enCharge revenu a false au pump #-1 | -1 = jamais
//    Un `await Future.delayed` hors `pump` gèle définitivement :
//        [S8a] avant await  → puis plus rien, test tué à 180 s
//    Et une opération dont les futures sont DÉJÀ complétées produit bien
//    l'affichage :
//        [S7a] fini=true | [S7b] snackbars=1 | [S7c] dialogues=1
//    C'est exactement ce que fournit l'injection `OperationsSauvegarde`.
//
//  CE QUE LA SIMULATION NE PROUVE PAS : qu'un fichier a été envoyé ou reçu.
//  Aucun test de ce fichier n'affirme un partage effectif.
//
//  FORMULES / K-FACTORS / POIDS / SEUILS / CRITÈRES A–Q : non touchés.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/widgets/profile/profile_profil_tab.dart';

// ── Libellés et textes EXACTS de la production ──────────────────────────────
//    Écrits en dur : un renommage dans le widget doit faire ÉCHOUER ces tests.
const String kBtnTelecharger = 'Télécharger sur le téléphone';
const String kBtnPartager = 'Partager mes données';
const String kTitreDialogue = 'Sauvegarde avec avertissements';
const String kActionDialogue = "J'ai compris";

const String kEnteteCopie =
    'Le fichier a été créé sur cet appareil, mais certaines '
    'données ou garanties peuvent manquer :';
const String kEntetePartageOuvert =
    'Le fichier a été créé et le menu de partage a été ouvert, mais '
    'certaines données ou garanties peuvent manquer :';
const String kEntetePartageFerme =
    'Le fichier a été créé sur cet appareil, mais le menu de '
    'partage n\'a pas pu s\'ouvrir. Certaines données ou garanties '
    'peuvent également manquer :';

/// Référence d'un avertissement long, pour vérifier l'affichage VERBATIM.
const String kAvertLong = 'ELO : ratings sauvegardés SANS le registre '
    "d'historique (registre absent sur cet appareil). Aucune protection "
    "anti-double-application n'est revendiquée par cette sauvegarde.";

// ═══════════════════════════════════════════════════════════════════════════
//  FABRIQUE D'OPÉRATIONS SIMULÉES
//
//  Toute opération non fournie LÈVE : un appel inattendu du widget devient un
//  échec bruyant, jamais un silence.
// ═══════════════════════════════════════════════════════════════════════════
const String kFichier = 'backup_pronostic_hippique_01012026.json';

OperationsSauvegarde _opsAvec({
  Future<ExportResult> Function()? partager,
  Future<ExportResult> Function()? telecharger,
  Future<bool> Function()? drive,
  Future<ImportResult> Function()? importer,
}) =>
    OperationsSauvegarde(
      partagerAvecResultat: partager ??
          () async => throw StateError('partagerAvecResultat NON ATTENDU'),
      telecharger: telecharger ??
          () async => throw StateError('telecharger NON ATTENDU'),
      sauvegarderDrive:
          drive ?? () async => throw StateError('sauvegarderDrive NON ATTENDU'),
      importerFichier: importer ??
          () async => throw StateError('importerFichier NON ATTENDU'),
    );

ExportResult _complet() => ExportResult(
      succes: true,
      filePath: '/tmp/$kFichier',
      fileName: kFichier,
      tailleOctets: 1024,
    );

ExportResult _avecAvertissements({
  bool? partageOuvert,
  List<String> avertissements = const <String>[kAvertLong],
}) =>
    ExportResult(
      succes: true,
      filePath: '/tmp/$kFichier',
      fileName: kFichier,
      tailleOctets: 1024,
      avertissements: avertissements,
      partageOuvert: partageOuvert,
    );

ExportResult _echec(String erreur) => ExportResult(
      succes: false,
      erreur: erreur,
    );

// ═══════════════════════════════════════════════════════════════════════════
//  ATTENTES BORNÉES
//
//  ⚠️ RÈGLE ISSUE DES MESURES : on attend la PRÉSENCE de ce qui doit
//     apparaître, jamais l'absence de ce qu'on suppose déjà absent.
//     L'ancienne version de ce fichier appelait `_pomperJusquaAbsence` en
//     attendant un dialogue : elle sortait au premier tour et lisait un arbre
//     vide — défaut réel, indépendant de tout blocage.
//
//  Chaque attente est BORNÉE (nombre de tours) : jamais de boucle ouverte.
// ═══════════════════════════════════════════════════════════════════════════
Future<void> _pomperPresence(WidgetTester tester, Finder cible,
    {int maxTours = 60}) async {
  for (var i = 0; i < maxTours; i++) {
    if (cible.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _pomperAbsence(WidgetTester tester, Finder cible,
    {int maxTours = 60}) async {
  for (var i = 0; i < maxTours; i++) {
    if (cible.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  MONTAGE
// ═══════════════════════════════════════════════════════════════════════════
Future<void> _monter(WidgetTester tester, OperationsSauvegarde operations) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final PmuProvider p = PmuProvider();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChangeNotifierProvider<PmuProvider>.value(
            value: p,
            child: ProfileBackupSection(provider: p, operations: operations),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  W1 — TÉLÉCHARGEMENT RÉUSSI SANS AVERTISSEMENT
  //
  //  Attendu : la confirmation normale (SnackBar), AUCUN dialogue.
  // ═════════════════════════════════════════════════════════════════════════
  group('W1 — téléchargement complet', () {
    testWidgets('W1a — SnackBar de confirmation, aucun dialogue',
        (WidgetTester tester) async {
      await _monter(tester, _opsAvec(telecharger: () async => _complet()));

      // Le bouton doit être présent AVANT le tap (sinon le tap ne prouve rien).
      expect(find.text(kBtnTelecharger), findsOneWidget);

      await tester.tap(find.text(kBtnTelecharger));
      await tester.pump(); // reprise des futures déjà complétées + setState
      await tester.pump(const Duration(milliseconds: 400)); // animation SnackBar

      expect(find.byType(SnackBar), findsOneWidget,
          reason: 'un succès sans avertissement doit être confirmé');
      expect(
        find.text('📥 Sauvegardé dans Téléchargements : $kFichier'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'aucun avertissement → aucun dialogue');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  W2 — PARTAGE RÉUSSI SANS AVERTISSEMENT
  // ═════════════════════════════════════════════════════════════════════════
  group('W2 — partage complet', () {
    testWidgets('W2a — SnackBar de confirmation, aucun dialogue',
        (WidgetTester tester) async {
      await _monter(tester, _opsAvec(partager: () async => _complet()));

      expect(find.text(kBtnPartager), findsOneWidget);
      await tester.tap(find.text(kBtnPartager));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text('✅ Sauvegarde complète prête à être partagée : $kFichier'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  W7 — ÉCHEC : SnackBar, AUCUN dialogue
  // ═════════════════════════════════════════════════════════════════════════
  group('W7 — échec', () {
    testWidgets('W7a — téléchargement en échec : message, pas de dialogue',
        (WidgetTester tester) async {
      await _monter(tester,
          _opsAvec(telecharger: () async => _echec('disque plein')));

      await tester.tap(find.text(kBtnTelecharger));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('❌ Erreur téléchargement : disque plein'),
          findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'un échec n\'est pas un avertissement : pas de dialogue');
    });

    testWidgets('W7b — partage en échec : message, pas de dialogue',
        (WidgetTester tester) async {
      await _monter(
          tester, _opsAvec(partager: () async => _echec('collecte avortée')));

      await tester.tap(find.text(kBtnPartager));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('❌ Erreur export : collecte avortée'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  W3 — AVERTISSEMENTS : le dialogue apparaît
  // ═════════════════════════════════════════════════════════════════════════
  group('W3 — apparition du dialogue', () {
    testWidgets('W3a — téléchargement avec avertissement → dialogue',
        (WidgetTester tester) async {
      await _monter(tester,
          _opsAvec(telecharger: () async => _avecAvertissements()));

      await tester.tap(find.text(kBtnTelecharger));
      await _pomperPresence(tester, find.byType(AlertDialog));

      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'un succès partiel ne doit jamais être confirmé normalement');
      expect(find.text(kTitreDialogue), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing,
          reason: 'aucun ✅ vert quand il y a des avertissements');
    });

    testWidgets('W3b — partage avec avertissement → dialogue',
        (WidgetTester tester) async {
      await _monter(tester,
          _opsAvec(partager: () async => _avecAvertissements(partageOuvert: true)));

      await tester.tap(find.text(kBtnPartager));
      await _pomperPresence(tester, find.byType(AlertDialog));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(kTitreDialogue), findsOneWidget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  W4 — CONTENU : chaque avertissement est affiché VERBATIM
  // ═════════════════════════════════════════════════════════════════════════
  group('W4 — contenu du dialogue', () {
    testWidgets('W4a — avertissement long affiché intégralement',
        (WidgetTester tester) async {
      await _monter(tester,
          _opsAvec(telecharger: () async => _avecAvertissements()));

      await tester.tap(find.text(kBtnTelecharger));
      await _pomperPresence(tester, find.byType(AlertDialog));

      expect(find.text(kAvertLong), findsOneWidget,
          reason: 'l\'avertissement doit être affiché sans troncature');
      expect(find.text('Fichier : $kFichier'), findsOneWidget,
          reason: 'le nom du fichier produit doit être lisible');
    });

    testWidgets('W4b — plusieurs avertissements : tous présents, dans l\'ordre',
        (WidgetTester tester) async {
      const String a2 = 'PARIS : 3 paris illisibles ont été ignorés.';
      const String a3 = 'ALERTES : configuration absente.';
      await _monter(
        tester,
        _opsAvec(
            telecharger: () async =>
                _avecAvertissements(avertissements: <String>[kAvertLong, a2, a3])),
      );

      await tester.tap(find.text(kBtnTelecharger));
      await _pomperPresence(tester, find.byType(AlertDialog));

      for (final a in <String>[kAvertLong, a2, a3]) {
        expect(find.text(a), findsOneWidget, reason: 'avertissement manquant : $a');
      }
    });

    testWidgets('W4c — en-tête « copie » : parle du fichier, jamais d\'envoi',
        (WidgetTester tester) async {
      await _monter(tester,
          _opsAvec(telecharger: () async => _avecAvertissements()));

      await tester.tap(find.text(kBtnTelecharger));
      await _pomperPresence(tester, find.byType(AlertDialog));

      expect(find.text(kEnteteCopie), findsOneWidget);
      expect(find.textContaining('partagé'), findsNothing,
          reason: 'aucun test ne doit laisser croire à un envoi');
      expect(find.textContaining('reçu'), findsNothing);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  W5 — PERSISTANCE : le dialogue ne s'efface pas tout seul
  // ═════════════════════════════════════════════════════════════════════════
  group('W5 — persistance', () {
    testWidgets('W5a — toujours présent après 3 s puis 7 s',
        (WidgetTester tester) async {
      await _monter(tester,
          _opsAvec(telecharger: () async => _avecAvertissements()));

      await tester.tap(find.text(kBtnTelecharger));
      await _pomperPresence(tester, find.byType(AlertDialog));
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'un avertissement ne doit pas disparaître comme un SnackBar');

      await tester.pump(const Duration(seconds: 7));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(kTitreDialogue), findsOneWidget);
    });

    testWidgets('W5b — un tap hors du dialogue ne le referme pas',
        (WidgetTester tester) async {
      await _monter(tester,
          _opsAvec(telecharger: () async => _avecAvertissements()));

      await tester.tap(find.text(kBtnTelecharger));
      await _pomperPresence(tester, find.byType(AlertDialog));

      // `barrierDismissible: false` : un tap sur la barrière ne doit rien faire.
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget,
          reason: 'barrierDismissible:false doit empêcher la fermeture');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  W6 — FERMETURE : un seul bouton, et il referme
  //  ⚠️ MESURÉ : avec un TextButton, la fermeture exige ~200 ms de transition
  //     ([S7e] +0ms=1 | +50ms=1 | +200ms=0). Un seul pump() ne suffit pas.
  // ═════════════════════════════════════════════════════════════════════════
  group('W6 — fermeture', () {
    testWidgets('W6a — « J\'ai compris » est le SEUL bouton du dialogue',
        (WidgetTester tester) async {
      await _monter(tester,
          _opsAvec(telecharger: () async => _avecAvertissements()));

      await tester.tap(find.text(kBtnTelecharger));
      await _pomperPresence(tester, find.byType(AlertDialog));

      final Finder actions = find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextButton));
      expect(actions, findsOneWidget,
          reason: 'un dialogue à acquittement unique ne doit pas offrir '
              'plusieurs issues');
      expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(kActionDialogue)),
        findsOneWidget,
      );
    });

    testWidgets('W6b — « J\'ai compris » referme le dialogue',
        (WidgetTester tester) async {
      await _monter(tester,
          _opsAvec(telecharger: () async => _avecAvertissements()));

      await tester.tap(find.text(kBtnTelecharger));
      await _pomperPresence(tester, find.byType(AlertDialog));
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text(kActionDialogue));
      await tester.pump(); // déclenche la fermeture
      await _pomperAbsence(tester, find.byType(AlertDialog));

      expect(find.byType(AlertDialog), findsNothing,
          reason: 'après acquittement, le dialogue doit disparaître');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  W8 — ÉCHEC D'OUVERTURE DU PARTAGE : l'en-tête ne ment pas
  // ═════════════════════════════════════════════════════════════════════════
  group('W8 — partage non ouvert', () {
    testWidgets('W8a — partageOuvert=false : « n\'a pas pu s\'ouvrir »',
        (WidgetTester tester) async {
      await _monter(
        tester,
        _opsAvec(partager: () async => _avecAvertissements(partageOuvert: false)),
      );

      await tester.tap(find.text(kBtnPartager));
      await _pomperPresence(tester, find.byType(AlertDialog));

      expect(find.text(kEntetePartageFerme), findsOneWidget,
          reason: 'quand le menu n\'a pas pu s\'ouvrir, le dire explicitement');
      expect(find.text(kEntetePartageOuvert), findsNothing,
          reason: 'ne jamais affirmer une ouverture qui n\'a pas eu lieu');
    });

    testWidgets('W8b — partageOuvert=true : « a été ouvert »',
        (WidgetTester tester) async {
      await _monter(
        tester,
        _opsAvec(partager: () async => _avecAvertissements(partageOuvert: true)),
      );

      await tester.tap(find.text(kBtnPartager));
      await _pomperPresence(tester, find.byType(AlertDialog));

      expect(find.text(kEntetePartageOuvert), findsOneWidget);
      expect(find.text(kEntetePartageFerme), findsNothing);
    });
  });
}
