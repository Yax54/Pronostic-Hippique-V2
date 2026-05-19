// ═══════════════════════════════════════════════════════════════════════════
//  IA NARRATIVE ENGINE — v10.66
//  Moteur narratif V3 :
//    - IaNarrativeResult : retourne message + templateIds
//    - genererResumeV3() : cache-first via IaNarrativeMemoryService
//    - Anti-répétition via IaNarrativeMemoryService
//    - Sélection pondérée par templates récents
//    - Tendances 7 jours, discipline forte, widget stable, type de pari
//    - Max 2 phrases, ton analytique, jamais de répétition
//
//  RÈGLE ABSOLUE : couche affichage uniquement.
//  Aucun calcul IA, aucun poids, aucun pronostic modifié.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math';

import '../data/ia_narrative_templates.dart';
import '../models/ia_narrative_models.dart';
import '../services/ia_narrative_memory_service.dart';

// ── ★ v10.66 : Résultat de genererResumeV3() ──────────────────────────────
/// Retourne le message narratif ET les IDs des templates utilisés.
/// Utilisé par IaNarrativeMemoryService pour le cache journalier.
class IaNarrativeResult {
  final String message;
  final List<String> templateIds;

  const IaNarrativeResult({
    required this.message,
    required this.templateIds,
  });
}

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
  /// ★ v10.66 : gère aussi {typePari}
  static String _render(
    IaNarrativeTemplate template,
    IaNarrativeContext ctx,
  ) {
    return template.text
        .replaceAll('{pseudo}', ctx.pseudoAffiche)
        .replaceAll('{discipline}',
            ctx.meilleureDiscipline.isNotEmpty ? ctx.meilleureDiscipline : 'cette discipline')
        .replaceAll('{widget}',
            ctx.widgetLibelle.isNotEmpty ? ctx.widgetLibelle : 'premium')
        .replaceAll('{typePari}',
            (ctx.typePariLePlusStable != null && ctx.typePariLePlusStable!.isNotEmpty)
                ? ctx.typePariLePlusStable!
                : 'simples');
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

  // ── Génération V3 (async — retourne IaNarrativeResult) ───────────────────
  /// ★ v10.66 — Même logique que V2 mais retourne message + templateIds.
  /// Utilisé par obtenirOuGenererNarratifDuJour() pour le cache journalier.
  /// Templates V3 prioritaires sur V2 (discipline, widget, typePari enrichis).
  /// Silencieux en cas d'erreur : retourne un fallback avec IDs vides.
  static Future<IaNarrativeResult> genererResumeV3(IaNarrativeContext ctx) async {
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
        selected = pickTemplate(IaNarrativeTemplates.fallback, recents);
      }

      phrases.add(_render(selected, ctx));
      usedIds.add(selected.id);

      // ── Phrase 2 : signal expert prioritaire (1 seul) ────────────────────
      // Priorité 1 : tendance 7 jours
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

      // Priorité 2 : discipline forte V3
      if (phrases.length < 2 && ctx.meilleureDiscipline.isNotEmpty) {
        final t = pickTemplate(IaNarrativeTemplates.disciplineForteV3,
            [...recents, ...usedIds]);
        phrases.add(_render(t, ctx));
        usedIds.add(t.id);
      }

      // Priorité 3 : widget premium stable V3
      if (phrases.length < 2 && ctx.widgetPremiumLePlusStable.isNotEmpty) {
        final t = pickTemplate(IaNarrativeTemplates.widgetStableV3,
            [...recents, ...usedIds]);
        phrases.add(_render(t, ctx));
        usedIds.add(t.id);
      }

      // Priorité 4 : type de pari V3 (★ v10.66)
      if (phrases.length < 2 && ctx.aTypePari) {
        final t = pickTemplate(IaNarrativeTemplates.typePariV3,
            [...recents, ...usedIds]);
        phrases.add(_render(t, ctx));
        usedIds.add(t.id);
      }

      // Priorité 5 : série premium
      if (phrases.length < 2 && ctx.premiumEnSerie) {
        final t = pickTemplate(IaNarrativeTemplates.premiumSerie,
            [...recents, ...usedIds]);
        phrases.add(_render(t, ctx));
        usedIds.add(t.id);
      }

      // ── Sauvegarde mémoire (silencieuse — ne duplique pas si cache hit) ───
      await memSvc.sauvegarderTemplates(usedIds);

      return IaNarrativeResult(
        message    : phrases.take(2).join(' '),
        templateIds: usedIds,
      );
    } catch (_) {
      // Fallback ultime : phrase sobre, IDs vides
      final msg = ctx.nbCoursesJour > 0
          ? '${ctx.pseudoAffiche}, l\'analyse du jour continue d\'enrichir les données.'
          : 'Les données continuent d\'être analysées.';
      return IaNarrativeResult(message: msg, templateIds: const []);
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
