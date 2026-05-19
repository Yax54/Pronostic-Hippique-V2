// ═══════════════════════════════════════════════════════════════════════════
//  IA NARRATIVE MEMORY SERVICE — v10.66
//  Gestion de la mémoire narrative légère (anti-répétition).
//  Clé SharedPreferences : 'ia_narrative_memory_v1'
//
//  ★ v10.66 : Cache journalier anti-rebuild
//    - obtenirOuGenererNarratifDuJour() : cache-first pattern
//    - _dateKey() : helper format 'YYYY-MM-DD'
//    - reason = 'analyseJournee' : force régénération après analyse du soir
//    - Cache figé pour toute la journée — seul le message est figé
//
//  RÈGLES SÉCURITÉ :
//  - Fallback automatique vers mémoire vide si données absentes/corrompues
//  - Ne jamais bloquer le flux principal (catch complet)
//  - La mémoire est secondaire — recréer proprement si reset nécessaire
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ia_narrative_memory_models.dart';
import '../models/ia_narrative_models.dart';
import '../services/ia_narrative_engine.dart';

class IaNarrativeMemoryService {
  static const _key = 'ia_narrative_memory_v1';

  // ── Chargement ────────────────────────────────────────────────────────────
  /// Charge la mémoire narrative depuis SharedPreferences.
  /// Retourne une mémoire vide si absente ou corrompue (jamais d'exception).
  Future<IaNarrativeMemory> charger() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);

      // Absent → mémoire vide (compatibilité anciennes sauvegardes)
      if (raw == null || raw.isEmpty) {
        return IaNarrativeMemory.vide();
      }

      // Corrompu → mémoire vide (reset propre)
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        if (kDebugMode) {
          debugPrint('[NarrativeMemory] Format invalide → mémoire vide');
        }
        return IaNarrativeMemory.vide();
      }

      return IaNarrativeMemory.fromJson(decoded);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NarrativeMemory] Erreur chargement → mémoire vide : $e');
      }
      return IaNarrativeMemory.vide();
    }
  }

  // ── Sauvegarde d'un template utilisé ─────────────────────────────────────
  /// Enregistre un templateId dans les derniers templates utilisés (max 8).
  /// Silencieux en cas d'erreur — la narration est secondaire.
  Future<void> sauvegarderTemplate(String templateId) async {
    try {
      if (templateId.isEmpty) return;

      final memory = await charger();

      // Ajouter en tête, dédoublonner, garder 8 max
      final updated = [
        templateId,
        ...memory.derniersTemplates.where((id) => id != templateId),
      ].take(8).toList();

      final next = IaNarrativeMemory(
        derniersTemplates: updated,
        updatedAt: DateTime.now(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(next.toJson()));
    } catch (e) {
      // Silencieux : ne jamais crasher pour une mémoire de phrases
      if (kDebugMode) {
        debugPrint('[NarrativeMemory] Erreur sauvegarde (ignorée) : $e');
      }
    }
  }

  // ── Sauvegarde d'une liste de templates ──────────────────────────────────
  /// Enregistre plusieurs templateIds en une seule passe (plus efficace).
  Future<void> sauvegarderTemplates(List<String> templateIds) async {
    try {
      if (templateIds.isEmpty) return;

      final memory = await charger();
      var updated = [...memory.derniersTemplates];

      // Ajouter chaque ID en dédoublonnant
      for (final id in templateIds.reversed) {
        if (id.isEmpty) continue;
        updated = [id, ...updated.where((x) => x != id)];
      }

      final next = IaNarrativeMemory(
        derniersTemplates: updated.take(8).toList(),
        updatedAt: DateTime.now(),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(next.toJson()));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NarrativeMemory] Erreur sauvegarde multiple (ignorée) : $e');
      }
    }
  }

  // ── Reset propre ──────────────────────────────────────────────────────────
  /// Remet la mémoire à zéro proprement.
  Future<void> reinitialiser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  // ── ★ v10.66 : Cache journalier anti-rebuild ──────────────────────────────

  /// Formate une date en 'YYYY-MM-DD' pour la clé de cache journalier.
  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Cache-first : retourne le message narratif du jour sans régénération inutile.
  ///
  /// CACHE HIT : même date → retourne le message figé immédiatement.
  /// CACHE MISS : date différente, absent, corrompu → génère avec genererResumeV3().
  /// FORCE REFRESH : [reason] = 'analyseJournee' → bypass le cache (soir post-analyse).
  ///
  /// Le cache ne bloque PAS : apprentissage IA, résultats, premium, ROI.
  Future<String> obtenirOuGenererNarratifDuJour({
    required DateTime date,
    required IaNarrativeContext context,
    String? reason,
  }) async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final dateKey = _dateKey(date);

      // ── Vérifier le cache (sauf force-refresh) ────────────────────────────
      if (reason != 'analyseJournee') {
        final raw = prefs.getString(iaNarrativeDailyCacheKey);
        if (raw != null && raw.isNotEmpty) {
          try {
            final cache = IaNarrativeDailyCache.fromJson(
                jsonDecode(raw) as Map<String, dynamic>);
            // Cache hit : même date ET message non vide → retourner directement
            if (cache.dateKey == dateKey && cache.message.trim().isNotEmpty) {
              if (kDebugMode) {
                debugPrint('[NarrativeCache] Cache hit — message figé du $dateKey');
              }
              return cache.message;
            }
          } catch (e) {
            // Cache corrompu → reset propre uniquement (ne bloque pas)
            await prefs.remove(iaNarrativeDailyCacheKey);
            if (kDebugMode) {
              debugPrint('[NarrativeCache] Cache corrompu → reset : $e');
            }
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('[NarrativeCache] Force-refresh (reason=analyseJournee)');
        }
      }

      // ── Générer V3 (nouveau message) ──────────────────────────────────────
      final result = await IaNarrativeEngine.genererResumeV3(context);

      // ── Sauvegarder le cache journalier ───────────────────────────────────
      if (result.message.isNotEmpty) {
        try {
          await prefs.setString(
            iaNarrativeDailyCacheKey,
            jsonEncode(IaNarrativeDailyCache(
              dateKey    : dateKey,
              message    : result.message,
              templateIds: result.templateIds,
              createdAt  : DateTime.now(),
            ).toJson()),
          );
          if (kDebugMode) {
            debugPrint('[NarrativeCache] Cache écrit pour $dateKey');
          }
        } catch (e) {
          // Erreur d'écriture cache non bloquante
          if (kDebugMode) {
            debugPrint('[NarrativeCache] Erreur écriture cache (ignorée) : $e');
          }
        }
      }

      return result.message;
    } catch (e) {
      // Fallback ultime — la narration est secondaire
      if (kDebugMode) {
        debugPrint('[NarrativeCache] Erreur globale → fallback sobre : $e');
      }
      return context.nbCoursesJour > 0
          ? '${context.pseudoAffiche}, l\'analyse du jour continue d\'enrichir les données.'
          : 'Les données continuent d\'être analysées.';
    }
  }

  /// Efface le cache journalier narratif (pour debug ou réinitialisation).
  Future<void> reinitialiserCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(iaNarrativeDailyCacheKey);
    } catch (_) {}
  }
}
