// ═══════════════════════════════════════════════════════════════════════════
//  IA NARRATIVE MEMORY SERVICE — v10.65
//  Gestion de la mémoire narrative légère (anti-répétition).
//  Clé SharedPreferences : 'ia_narrative_memory_v1'
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
}
