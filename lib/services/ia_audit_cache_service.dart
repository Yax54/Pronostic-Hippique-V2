// ★ v10.32 — Cache léger pour l'Audit IA
// SharedPreferences key : "ia_audit_cache_v1"
// Lecture seule : aucune modification de poids, aucun apprentissage.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class IaAuditCacheService {
  static const String _key = 'ia_audit_cache_v1';

  // ── Modèle cache ──────────────────────────────────────────────────────────

  static Map<String, dynamic> _empty() => {
    'updatedAt': null,
    'nbPronosticsAvecResultat': 0,
    'auditUtiliteGlobal': null,
    'auditCriteresVivants': null,
    'auditCorrelations': null,
    'auditParDiscipline': null,
  };

  // ── Lecture ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> readCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Retourne true si le cache est valide pour [nbPronosticsAvecResultat].
  Future<bool> isCacheValid(int nbPronosticsAvecResultat) async {
    final cache = await readCache();
    if (cache == null) return false;
    final cached = cache['nbPronosticsAvecResultat'] as int? ?? 0;
    return cached == nbPronosticsAvecResultat;
  }

  // ── Écriture ──────────────────────────────────────────────────────────────

  Future<void> writeCache({
    required int nbPronosticsAvecResultat,
    required dynamic auditUtiliteGlobal,
    required dynamic auditCriteresVivants,
    required dynamic auditCorrelations,
    required dynamic auditParDiscipline,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final data = _empty();
    data['updatedAt'] = DateTime.now().toIso8601String();
    data['nbPronosticsAvecResultat'] = nbPronosticsAvecResultat;
    data['auditUtiliteGlobal'] = auditUtiliteGlobal;
    data['auditCriteresVivants'] = auditCriteresVivants;
    data['auditCorrelations'] = auditCorrelations;
    data['auditParDiscipline'] = auditParDiscipline;
    await prefs.setString(_key, jsonEncode(data));
  }

  // ── Invalidation ─────────────────────────────────────────────────────────

  /// Appelé depuis ia_memory_service.dart quand de nouveaux résultats réels
  /// sont ajoutés. Invalide le cache sans recalcul immédiat.
  Future<void> invalidate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  // ── Métadonnées ───────────────────────────────────────────────────────────

  Future<DateTime?> lastUpdated() async {
    final cache = await readCache();
    if (cache == null) return null;
    final s = cache['updatedAt'] as String?;
    if (s == null) return null;
    return DateTime.tryParse(s);
  }
}
