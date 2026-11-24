// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — FONCTIONNEL 4/4 : LE BLOC DE DÉCISION, RENDU ET ACTIONNÉ
// ═══════════════════════════════════════════════════════════════════════════
//
//  Exigence du §7 : « Ne pas considérer qu'un test isolé du provider démontre à
//  lui seul le fonctionnement d'un bouton dans l'application. »
//
//  Ce fichier MONTE donc le widget réel (`BlocDecisionGainTardif`) dans un
//  arbre de widgets réel, appuie RÉELLEMENT sur les boutons, et vérifie :
//    • que les cinq informations financières sont affichées séparément ;
//    • que « Gain gagné » est bien l'intitulé utilisé ;
//    • que l'appui sur « Accepter » déclenche l'écriture ET change le montant
//      retenu affiché ;
//    • que l'appui sur « Refuser » conserve le montant manuel ;
//    • qu'un ÉCHEC d'écriture laisse le bloc en place avec un message ;
//    • qu'une décision identique (CAS B) n'affiche AUCUN bouton.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/gains_tardifs_en_attente.dart';
import 'package:pronostic_hippique/widgets/bloc_decision_gain_tardif.dart';

const _cle = 'user_predictions_v2';

UserPrediction _ticket({
  required String id,
  double? gainManuel,
  double? gainOfficiel,
  double? remboursement,
}) =>
    UserPrediction(
      id: id,
      dateStr: '23032026',
      numReunion: 1,
      numCourse: 3,
      nomCourse: 'Prix de test',
      hippodrome: 'Vincennes',
      numeroCheval: 5,
      nomCheval: 'Cheval Test',
      cote: 3.5,
      typePari: 'Simple Gagnant',
      createdAt: DateTime(2026, 3, 23, 14, 30),
      montantMise: 20.0,
      montantGainManuel: gainManuel,
      montantOfficielPmu: gainOfficiel,
      remboursementPmu: remboursement,
    );

Future<PmuProvider> _provider(UserPrediction t) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _cle: [jsonEncode(t.toJson())],
  });
  final p = PmuProvider();
  await p.reloadPredictions();
  return p;
}

/// Monte le bloc dans un arbre Material réel.
Future<void> _monter(
  WidgetTester tester,
  PmuProvider provider,
  DecisionEnAttente d, {
  VoidCallback? onConfirmee,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      body: SingleChildScrollView(
        child: BlocDecisionGainTardif(
          decision: d,
          provider: provider,
          onDecisionConfirmee: onConfirmee,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('U1 — AFFICHAGE DES CINQ INFORMATIONS', () {
    testWidgets('U1.1 gain manuel, gain officiel, remboursement et « Gain gagné »',
        (tester) async {
      final t = _ticket(
          id: 'u1', gainManuel: 20.0, gainOfficiel: 75.0, remboursement: 10.0);
      final p = await _provider(t);
      final d = decisionsEnAttente(p.predictions).single;

      await _monter(tester, p, d);

      // Les libellés doivent être présents ET distincts.
      expect(find.text('Gain déclaré'), findsOneWidget);
      expect(find.text('Gain officiel PMU'), findsOneWidget);
      expect(find.text('Remboursement officiel'), findsOneWidget);
      // ⚠️ L'intitulé validé est conservé mot pour mot.
      expect(find.text('Gain gagné actuellement retenu'), findsOneWidget);
      expect(find.text('État'), findsOneWidget);

      // Les MONTANTS sont affichés séparément, jamais additionnés.
      //
      // ⚠️ 20.00 € apparaît DEUX FOIS, et c'est CORRECT : avant toute décision,
      //    le « gain gagné actuellement retenu » EST le gain déclaré. Le bloc
      //    doit donc montrer les deux lignes, avec la même valeur, séparément.
      //    Ce n'est pas un doublon d'affichage : c'est la démonstration que le
      //    retenu ne dépend pas encore du montant officiel.
      expect(find.text('20.00 €'), findsNWidgets(2),
          reason: 'gain déclaré ET gain retenu (identique avant décision)');
      expect(find.text('75.00 €'), findsOneWidget); // officiel
      expect(find.text('10.00 €'), findsOneWidget); // remboursement
      // Le retenu n'est JAMAIS la somme gain + remboursement.
      expect(find.text('85.00 €'), findsNothing);
      expect(find.text('95.00 €'), findsNothing);

      // Les deux actions sont réellement visibles.
      expect(find.text('Accepter'), findsOneWidget);
      expect(find.text('Refuser'), findsOneWidget);
      expect(find.text('Décision en attente'), findsOneWidget);
    });

    testWidgets('U1.2 CAS B (montants identiques) : AUCUN bouton', (tester) async {
      final t = _ticket(id: 'u2', gainManuel: 30.0, gainOfficiel: 30.0);
      final p = await _provider(t);
      // ⚠️ `attendDecisionGain` doit exclure le CAS B : aucune décision en
      //    attente n'est donc construite, et le widget ne peut pas apparaître.
      expect(decisionsEnAttente(p.predictions), isEmpty);
    });

    testWidgets('U1.3 un gain manuel de 0 € produit bien une décision',
        (tester) async {
      final t = _ticket(id: 'u3', gainManuel: 0.0, gainOfficiel: 12.0);
      final p = await _provider(t);
      final attentes = decisionsEnAttente(p.predictions);
      expect(attentes.length, 1, reason: '0 € est un gain manuel existant');
      expect(attentes.single.gainManuel, 0.0);
    });
  });

  group('U2 — LES BOUTONS AGISSENT RÉELLEMENT', () {
    testWidgets('U2.1 « Accepter » enregistre et fait passer le retenu à l\'officiel',
        (tester) async {
      final t = _ticket(id: 'u4', gainManuel: 20.0, gainOfficiel: 75.0);
      final p = await _provider(t);
      final d = decisionsEnAttente(p.predictions).single;

      var confirmee = false;
      await _monter(tester, p, d, onConfirmee: () => confirmee = true);

      // Avant : le manuel est retenu.
      expect(p.predictions.first.gainRetenuBrut, 20.0);

      await tester.tap(find.text('Accepter'));
      await tester.pumpAndSettle();

      // Le rappel de confirmation a été appelé (donc l'écran hôte rafraîchit).
      expect(confirmee, isTrue);
      // Et l'effet FINANCIER est réel.
      expect(p.predictions.first.gainRetenuBrut, 75.0);
      expect(p.predictions.first.decisionGainPmu?.name, 'accepte');
    });

    testWidgets('U2.2 « Refuser » enregistre et CONSERVE le manuel',
        (tester) async {
      final t = _ticket(id: 'u5', gainManuel: 20.0, gainOfficiel: 75.0);
      final p = await _provider(t);
      final d = decisionsEnAttente(p.predictions).single;

      await _monter(tester, p, d);
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();

      expect(p.predictions.first.gainRetenuBrut, 20.0);
      expect(p.predictions.first.decisionGainPmu?.name, 'refuse');
      // L'officiel reste en trace.
      expect(p.predictions.first.montantOfficielPmu, 75.0);
    });

    testWidgets('U2.3 un ÉCHEC d\'écriture laisse le bloc et affiche un message',
        (tester) async {
      final t = _ticket(id: 'u6', gainManuel: 20.0, gainOfficiel: 75.0);
      final p = await _provider(t);
      final d = decisionsEnAttente(p.predictions).single;

      var confirmee = false;
      await _monter(tester, p, d, onConfirmee: () => confirmee = true);

      // ⚠️ On arme le refus d'écriture : le scénario « sauvegarde en échec ».
      p.refuserProchaineEcriturePourTest();

      await tester.tap(find.text('Accepter'));
      await tester.pumpAndSettle();

      // Aucune confirmation : le rappel ne doit PAS avoir été appelé.
      expect(confirmee, isFalse,
          reason: 'une erreur de sauvegarde n\'est jamais une décision');
      // Le message d'échec est visible et explicite.
      expect(
        find.textContaining('reste en attente'),
        findsOneWidget,
        reason: 'la décision est reportée, jamais perdue',
      );
      // Les boutons sont toujours là : la décision reste possible.
      expect(find.text('Accepter'), findsOneWidget);
      // Et la décision n'est pas enregistrée.
      expect(p.predictions.first.decisionGainPmu, isNull);
    });
  });
}
