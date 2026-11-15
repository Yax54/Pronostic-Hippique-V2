// ═══════════════════════════════════════════════════════════════════════════
//  V43 — B : LE TROPHÉE 🏆 EST RÉSERVÉ AUX SÉRIES PREMIUM
//
//  OBJET
//  ─────
//  La phrase de série Premium doit porter 🏆 (et non 🔥) à partir de 2 jours
//  consécutifs gagnants. Les symboles des CARTES doivent rester strictement
//  inchangés : ⭐ (Best Bet), 🔥 (Gros Paris), ⭐🔥 (les deux).
//
//  SÉMANTIQUE VALIDÉE
//  ──────────────────
//   ⭐  = Best Bet gagnant
//   🔥  = Gros Paris gagnant
//   ⭐🔥 = Best Bet ET Gros Paris gagnants
//   🏆  = série Premium ≥ 2 jours consécutifs, même sous-catégorie Best Bet
//
//  PORTÉE : ce fichier ne teste QUE l'affichage. Aucune règle de calcul n'est
//  vérifiée ici (voir v42 pour A1/R1).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/utils/premium_streak_ui.dart';
import 'package:pronostic_hippique/utils/source_pronostic_utils.dart';

// ───────────────────────────────────────────────────────────────────────────
//  OUTILS
// ───────────────────────────────────────────────────────────────────────────

/// Monte la phrase de série et retourne les textes déclarés.
///
/// ⚠ Un `Text` engendre TOUJOURS un `RichText` enfant : collecter les deux
/// types compterait chaque phrase DEUX fois. On ne collecte donc que les
/// `Text` (source de vérité du widget que l'on teste).
Future<List<String>> renduPhrase(
    WidgetTester tester, PremiumStreak? streak) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Column(children: [buildPremiumStreakPhrase(streak: streak)]),
    ),
  ));
  await tester.pump();
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget;
    if (w is Text && w.data != null) out.add(w.data!);
  }
  return out;
}

PremiumStreak streakDe(int jours, {String source = 'topEquilibre'}) =>
    PremiumStreak(
      sourceWidget: source,
      jours: jours,
      dateFin: DateTime(2026, 11, 15),
    );

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC B-1 — SEUIL DU TROPHÉE
  // ═══════════════════════════════════════════════════════════════════════

  group('B-1 — seuil d\'affichage du trophée', () {
    testWidgets('B-T1 — streak null : rien n\'est rendu', (tester) async {
      final textes = await renduPhrase(tester, null);
      expect(textes, isEmpty, reason: 'null → SizedBox.shrink()');
      expect(find.textContaining('🏆'), findsNothing);
    });

    testWidgets('B-T2 — 1 jour : AUCUN trophée', (tester) async {
      final textes = await renduPhrase(tester, streakDe(1));
      expect(textes, isEmpty, reason: '1 jour < seuil de 2');
      expect(find.textContaining('🏆'), findsNothing);
      expect(find.textContaining('🔥'), findsNothing);
    });

    testWidgets('B-T3 — 2 jours : trophée VISIBLE, aucune flamme',
        (tester) async {
      final textes = await renduPhrase(tester, streakDe(2));
      expect(textes, hasLength(1));
      expect(textes.first.contains('🏆'), isTrue,
          reason: 'le trophée doit remplacer la flamme');
      expect(textes.first.contains('🔥'), isFalse,
          reason: 'aucune flamme ne doit subsister dans la phrase de série');
      expect(textes.first.contains('2 jours consécutifs'), isTrue,
          reason: 'texte conservé à l\'identique');
    });

    testWidgets('B-T4 — 3 jours : trophée VISIBLE', (tester) async {
      final textes = await renduPhrase(tester, streakDe(3));
      expect(textes, hasLength(1));
      expect(textes.first.contains('🏆'), isTrue);
      expect(textes.first.contains('🔥'), isFalse);
      expect(textes.first.contains('3 jours consécutifs'), isTrue);
    });

    testWidgets('B-T5 — 7 jours : trophée VISIBLE, pas de seconde flamme',
        (tester) async {
      final textes = await renduPhrase(tester, streakDe(7));
      expect(textes, hasLength(1));
      expect(textes.first.contains('🏆'), isTrue);
      expect(textes.first.split('🔥'), hasLength(1),
          reason: 'un seul emoji de série, et c\'est le trophée');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC B-2 — STYLE CONSERVÉ
  // ═══════════════════════════════════════════════════════════════════════

  group('B-2 — style et contenu conservés', () {
    testWidgets('B-T6 — couleur orange 0xFFFF9800 conservée', (tester) async {
      await renduPhrase(tester, streakDe(4));
      final text = tester.widget<Text>(find.textContaining('🏆'));
      expect(text.style?.color, const Color(0xFFFF9800));
      expect(text.style?.fontSize, 13.5);
      expect(text.style?.fontWeight, FontWeight.w800);
    });

    testWidgets('B-T7 — accord singulier/pluriel conservé', (tester) async {
      final deux = await renduPhrase(tester, streakDe(2));
      expect(deux.first.contains('2 jours consécutifs'), isTrue);
      final grand = await renduPhrase(tester, streakDe(12));
      expect(grand.first.contains('12 jours consécutifs'), isTrue);
    });

    testWidgets('B-T8 — les 5 sous-catégories produisent le même trophée',
        (tester) async {
      for (final source in <String>[
        'conseilJour',
        'meilleurPari',
        'topEquilibre',
        'plusSur',
        'plusRentable',
      ]) {
        final textes = await renduPhrase(tester, streakDe(2, source: source));
        expect(textes, hasLength(1), reason: 'source=$source');
        expect(textes.first.contains('🏆'), isTrue, reason: 'source=$source');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC B-3 — SYMBOLES DES CARTES INCHANGÉS (Gros Paris)
  // ═══════════════════════════════════════════════════════════════════════

  group('B-3 — symboles des cartes inchangés', () {
    test('B-T9 — iconeCombinaison : ⭐ / 🔥 / ⭐🔥 / \'\' inchangés', () {
      expect(
        SourcePronosticUtils.iconeCombinaison(
            hasBestBet: true, hasGrosParis: false),
        '⭐',
        reason: 'Best Bet seul',
      );
      expect(
        SourcePronosticUtils.iconeCombinaison(
            hasBestBet: false, hasGrosParis: true),
        '🔥',
        reason: 'Gros Paris seul : la flamme NE DOIT PAS devenir un trophée',
      );
      expect(
        SourcePronosticUtils.iconeCombinaison(
            hasBestBet: true, hasGrosParis: true),
        '⭐🔥',
        reason: 'double signal inchangé',
      );
      expect(
        SourcePronosticUtils.iconeCombinaison(
            hasBestBet: false, hasGrosParis: false),
        '',
        reason: 'aucun signal',
      );
    });

    test('B-T10 — iconeDoubleSignal et iconeSource inchangés', () {
      expect(SourcePronosticUtils.iconeDoubleSignal, '⭐🔥');
      expect(
        SourcePronosticUtils.iconeSource(
            SourcePronosticUtils.sourceGrosParis),
        '🔥',
        reason: 'la source Gros Paris garde sa flamme',
      );
      expect(
        SourcePronosticUtils.iconeSource(
            SourcePronosticUtils.sourceProgramme),
        '⭐',
        reason: 'la source programme garde son étoile',
      );
    });

    test('B-T11 — aucune flamme Gros Paris remplacée par un trophée', () {
      // Contrat explicite : le trophée n\'existe QUE dans la phrase de série.
      // Les trois fonctions d\'icône ne peuvent pas en produire.
      final combinaisons = <String>[
        SourcePronosticUtils.iconeCombinaison(
            hasBestBet: true, hasGrosParis: true),
        SourcePronosticUtils.iconeCombinaison(
            hasBestBet: true, hasGrosParis: false),
        SourcePronosticUtils.iconeCombinaison(
            hasBestBet: false, hasGrosParis: true),
        SourcePronosticUtils.iconeSource(
            SourcePronosticUtils.sourceGrosParis),
        SourcePronosticUtils.iconeSource(
            SourcePronosticUtils.sourceProgramme),
        SourcePronosticUtils.iconeDoubleSignal,
      ];
      for (final icone in combinaisons) {
        expect(icone.contains('🏆'), isFalse,
            reason: 'icône "$icone" ne doit jamais contenir un trophée');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC B-4 — PremiumStreak.emoji NON MODIFIÉ
  // ═══════════════════════════════════════════════════════════════════════

  group('B-4 — PremiumStreak.emoji laissé tel quel', () {
    test('B-T12 — le getter emoji garde son comportement historique', () {
      // Ce getter n\'est appelé NULLE PART dans lib/ : il ne doit pas être
      // modifié par cette intervention, uniquement constaté.
      expect(streakDe(6).emoji, '🏆');
      expect(streakDe(4).emoji, '🔥');
      expect(streakDe(2).emoji, '⭐');
    });
  });
}
