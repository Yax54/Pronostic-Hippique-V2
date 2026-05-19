// ═══════════════════════════════════════════════════════════════════════════
//  PREMIUM STREAK UI — ★ v10.61
//  Helper commun : phrase dynamique série premium.
//
//  Règle :
//   - Afficher si streak.jours >= 2
//   - dateReference = date du widget affiché (JAMAIS DateTime.now() en dur)
//   - Un seul fichier, même style partout (Home, BestBet, Calendrier)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../services/ia_memory_models.dart' show PremiumStreak;
import '../services/ia_memory_service.dart';

/// Calcule le streak premium pour un [sourceWidget] à une [dateReference] donnée.
///
/// [dateReference] doit être la date du widget affiché (bulle calendrier, widget home...).
/// Ne jamais passer DateTime.now() : les historiques resteraient corrects à chaque date.
PremiumStreak streakPourSource({
  required String sourceWidget,
  required DateTime dateReference,
}) {
  return IaMemoryService.instance.calculerStreakPremium(
    sourceWidget:  sourceWidget,
    dateReference: dateReference,
  );
}

/// Widget phrase dynamique série premium.
///
/// Retourne [SizedBox.shrink()] si streak == null ou streak.jours < 2.
/// Sinon affiche :
///   🔥 Ce pari est gagnant depuis X jours consécutifs
Widget buildPremiumStreakPhrase({required PremiumStreak? streak}) {
  if (streak == null || streak.jours < 2) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      '🔥 Ce pari est gagnant depuis '
      '${streak.jours} jour${streak.jours > 1 ? 's' : ''} consécutifs',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFFFF9800),
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
        shadows: [
          Shadow(
            color: Color(0xAAFF6D00),
            blurRadius: 12,
          ),
        ],
      ),
    ),
  );
}
