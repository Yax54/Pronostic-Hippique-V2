// ═══════════════════════════════════════════════════════════════════════════
//  IA NARRATIVE ENGINE — v10.64
//  Génère le résumé narratif à partir du contexte.
//  Couche d'affichage uniquement — aucun calcul IA modifié.
//  Max 2 phrases par résumé. Ton analytique, jamais subjectif.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math';

import '../data/ia_narrative_templates.dart';
import '../models/ia_narrative_models.dart';

class IaNarrativeEngine {
  static final Random _random = Random();

  // ── Génération du résumé narratif ─────────────────────────────────────────
  /// Génère une phrase narrative (max 2 phrases) à partir du contexte.
  /// Ne modifie aucun état, aucun calcul IA.
  static String genererResume(IaNarrativeContext ctx) {
    final phrases = <String>[];

    // Phrase 1 : état comparatif jour J vs hier
    if (ctx.progressionJour) {
      phrases.add(_pick(IaNarrativeTemplates.progressionJour, ctx));
    } else if (ctx.regressionJour) {
      phrases.add(_pick(IaNarrativeTemplates.regressionJour, ctx));
    } else if (ctx.jourStable) {
      phrases.add(_pick(IaNarrativeTemplates.jourStable, ctx));
    }

    // Phrase 2 : série premium (uniquement si ≥ 2 jours)
    if (ctx.premiumEnSerie) {
      phrases.add(_pick(IaNarrativeTemplates.premiumSerie, ctx));
    }

    // Fallback : pas de données de comparaison
    if (phrases.isEmpty) {
      phrases.add(_pick(IaNarrativeTemplates.fallback, ctx));
    }

    // Limite stricte : 2 phrases maximum
    return phrases.take(2).join(' ');
  }

  // ── Sélection aléatoire + injection pseudo ─────────────────────────────────
  static String _pick(List<String> templates, IaNarrativeContext ctx) {
    final raw = templates[_random.nextInt(templates.length)];
    return raw.replaceAll('{pseudo}', ctx.pseudoAffiche);
  }
}
