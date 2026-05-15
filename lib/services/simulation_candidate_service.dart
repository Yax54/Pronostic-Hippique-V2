// ★ v10.32 — Service de gestion des pistes de simulation (lecture seule IA)
// SharedPreferences key : "simulation_candidates_v1"
// JAMAIS d'écriture dans IaMemoryService.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/simulation_candidate_model.dart';

class SimulationCandidateService {
  static const String _key = 'simulation_candidates_v1';
  static const int _maxCandidates = 50;

  // ── Lecture ───────────────────────────────────────────────────────────────

  Future<List<SimulationCandidate>> listCandidates() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final result = <SimulationCandidate>[];
    for (final s in raw) {
      try {
        result.add(SimulationCandidate.fromJson(
            jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // entrée corrompue ignorée
      }
    }
    // tri par date décroissante
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  // ── Sauvegarde ────────────────────────────────────────────────────────────

  Future<void> saveCandidate(SimulationCandidate candidate) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await listCandidates();

    // Supprimer un éventuel doublon (même id)
    final filtered = existing.where((c) => c.id != candidate.id).toList();
    filtered.insert(0, candidate);

    // Limiter à _maxCandidates
    final trimmed = filtered.take(_maxCandidates).toList();
    await prefs.setStringList(
      _key,
      trimmed.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  // ── Suppression ───────────────────────────────────────────────────────────

  Future<void> deleteCandidate(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await listCandidates();
    final filtered = existing.where((c) => c.id != id).toList();
    await prefs.setStringList(
      _key,
      filtered.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  Future<void> clearCandidates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  // ── Rechargement (rejouer) ────────────────────────────────────────────────

  /// Retourne discipline + coefficients pour préremplir SimulationScreen.
  /// Ne lance PAS la simulation automatiquement.
  Future<({String discipline, Map<String, double> coefficients})?> reloadCandidate(
      String id) async {
    final list = await listCandidates();
    final match = list.where((c) => c.id == id).firstOrNull;
    if (match == null) return null;
    return (discipline: match.discipline, coefficients: Map.of(match.coefficients));
  }

  // ── Génération d'ID unique ────────────────────────────────────────────────

  static String generateId() {
    final now = DateTime.now();
    return 'simu_${now.millisecondsSinceEpoch}';
  }
}
