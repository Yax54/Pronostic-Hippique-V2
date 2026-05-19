// ═══════════════════════════════════════════════════════════════════════════
//  IA NARRATIVE ENGINE — v10.65
//  Moteur narratif V2 :
//    - Anti-répétition via IaNarrativeMemoryService
//    - Sélection pondérée par templates récents
//    - Tendances 7 jours
//    - Discipline forte & widget stable
//    - Max 2 phrases, ton analytique
//
//  RÈGLE ABSOLUE : couche affichage uniquement.
//  Aucun calcul IA, aucun poids, aucun pronostic modifié.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math';

import '../data/ia_narrative_templates.dart';
import '../models/ia_narrative_models.dart';
import '../services/ia_narrative_memory_service.dart';

class IaNarrativeEngine {
  static final Random _random = Random();

  // ── Sélection anti-répétition ─────────────────────────────────────────────
  /// Choisit un template en évitant les IDs récemment utilisés.
  /// Si tous les templates ont été récemment utilisés → pool complet (fallback).
  static IaNarrativeTemplate pickTemplate(
    List<IaNarrativeTemplate> templates,
    List<String> recents,
  ) {
    final disponibles =
        templates.where((t) => !recents.contains(t.id)).toList();
    final pool = disponibles.isNotEmpty ? disponibles : templates;
    return pool[_random.nextInt(pool.length)];
  }

  // ── Injection des variables dans le texte ─────────────────────────────────
  static String _render(
    IaNarrativeTemplate template,
    IaNarrativeContext ctx,
  ) {
    return template.text
        .replaceAll('{pseudo}', ctx.pseudoAffiche)
        .replaceAll('{discipline}',
            ctx.meilleureDiscipline.isNotEmpty ? ctx.meilleureDiscipline : 'cette discipline')
        .replaceAll('{widget}',
            ctx.widgetLibelle.isNotEmpty ? ctx.widgetLibelle : 'premium');
  }

  // ── Génération V2 (async — mémoire narrative) ─────────────────────────────
  /// Génère le résumé narratif (max 2 phrases) en évitant les répétitions.
  /// Sauvegarde les templates utilisés dans la mémoire narrative.
  /// Silencieux en cas d'erreur : retourne un fallback.
  static Future<String> genererResumeV2(IaNarrativeContext ctx) async {
    try {
      final memSvc = IaNarrativeMemoryService();
      final memory = await memSvc.charger();
      final recents = memory.derniersTemplates;

      final phrases = <String>[];
      final usedIds = <String>[];

      // ── Phrase 1 : état jour J vs hier ───────────────────────────────────
      IaNarrativeTemplate selected;

      if (ctx.progressionJour) {
        selected = pickTemplate(IaNarrativeTemplates.progressionJour, recents);
      } else if (ctx.regressionJour) {
        selected = pickTemplate(IaNarrativeTemplates.regressionJour, recents);
      } else if (ctx.jourStable) {
        selected = pickTemplate(IaNarrativeTemplates.jourStable, recents);
      } else {
        // Fallback : pas de données de comparaison jour J/J-1
        selected = pickTemplate(IaNarrativeTemplates.fallback, recents);
      }

      phrases.add(_render(selected, ctx));
      usedIds.add(selected.id);

      // ── Phrase 2 : signal secondaire (1 seul, priorité décroissante) ─────

      // Priorité 1 : tendance 7 jours (si données disponibles)
      if (phrases.length < 2 && ctx.a7jDonnees && ctx.progression7j) {
        final t = pickTemplate(IaNarrativeTemplates.tendance7j,
            [...recents, ...usedIds]);
        phrases.add(_render(t, ctx));
        usedIds.add(t.id);
      } else if (phrases.length < 2 && ctx.a7jDonnees && ctx.regression7j) {
        final t = pickTemplate(IaNarrativeTemplates.regression7j,
            [...recents, ...usedIds]);
        phrases.add(_render(t, ctx));
        usedIds.add(t.id);
      }

      // Priorité 2 : discipline forte (si disponible et pas encore 2 phrases)
      if (phrases.length < 2 && ctx.meilleureDiscipline.isNotEmpty) {
        final t = pickTemplate(IaNarrativeTemplates.disciplineForte,
            [...recents, ...usedIds]);
        phrases.add(_render(t, ctx));
        usedIds.add(t.id);
      }

      // Priorité 3 : widget premium stable (si disponible)
      if (phrases.length < 2 && ctx.widgetPremiumLePlusStable.isNotEmpty) {
        final t = pickTemplate(IaNarrativeTemplates.widgetStable,
            [...recents, ...usedIds]);
        phrases.add(_render(t, ctx));
        usedIds.add(t.id);
      }

      // Priorité 4 : série premium (si ≥ 2 jours)
      if (phrases.length < 2 && ctx.premiumEnSerie) {
        final t = pickTemplate(IaNarrativeTemplates.premiumSerie,
            [...recents, ...usedIds]);
        phrases.add(_render(t, ctx));
        usedIds.add(t.id);
      }

      // ── Sauvegarde mémoire (silencieuse) ──────────────────────────────────
      await memSvc.sauvegarderTemplates(usedIds);

      // ── Limite stricte 2 phrases ──────────────────────────────────────────
      return phrases.take(2).join(' ');
    } catch (_) {
      // Fallback ultime : phrase sobre sans mémoire
      return ctx.nbCoursesJour > 0
          ? '${ctx.pseudoAffiche}, l\'analyse du jour continue d\'enrichir les données.'
          : 'Les données continuent d\'être analysées.';
    }
  }

  // ── Méthode synchrone V1 conservée (rétrocompatibilité) ──────────────────
  /// Version synchrone V1 — conservée pour compatibilité.
  /// Préférer genererResumeV2() pour les nouvelles intégrations.
  static String genererResume(IaNarrativeContext ctx) {
    final phrases = <String>[];

    IaNarrativeTemplate selected;
    if (ctx.progressionJour) {
      selected = IaNarrativeTemplates.progressionJour[
          _random.nextInt(IaNarrativeTemplates.progressionJour.length)];
    } else if (ctx.regressionJour) {
      selected = IaNarrativeTemplates.regressionJour[
          _random.nextInt(IaNarrativeTemplates.regressionJour.length)];
    } else if (ctx.jourStable) {
      selected = IaNarrativeTemplates.jourStable[
          _random.nextInt(IaNarrativeTemplates.jourStable.length)];
    } else {
      selected = IaNarrativeTemplates.fallback[
          _random.nextInt(IaNarrativeTemplates.fallback.length)];
    }

    phrases.add(_render(selected, ctx));

    if (ctx.premiumEnSerie) {
      final t = IaNarrativeTemplates.premiumSerie[
          _random.nextInt(IaNarrativeTemplates.premiumSerie.length)];
      phrases.add(_render(t, ctx));
    }

    return phrases.take(2).join(' ');
  }
}
