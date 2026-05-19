// ═══════════════════════════════════════════════════════════════════════════
//  IA NARRATIVE MEMORY MODELS — v10.66
//  Mémoire narrative légère : anti-répétition de templates.
//  Stockée dans SharedPreferences sous 'ia_narrative_memory_v1'.
//
//  ★ v10.66 : ajout IaNarrativeDailyCache (cache journalier anti-rebuild)
//             Clé : 'ia_narrative_daily_cache_v1'
//
//  RÈGLES BACKUP/RESTAURATION :
//  - Si absente dans un ancien backup → créer mémoire vide (jamais crash)
//  - Si corrompue → reset automatique vers mémoire vide
//  - La narration est secondaire : ne jamais bloquer une restauration principale
// ═══════════════════════════════════════════════════════════════════════════

// ── ★ v10.66 : Cache journalier anti-rebuild ──────────────────────────────
/// Clé SharedPreferences pour le cache narratif journalier.
/// Fige le message narratif du jour pour éviter les changements à chaque rebuild.
// ignore: constant_identifier_names
const String iaNarrativeDailyCacheKey = 'ia_narrative_daily_cache_v1';

/// Cache journalier du message narratif.
/// Pour une même date (dateKey = 'YYYY-MM-DD'), le message est généré UNE seule fois.
/// Régénération possible uniquement avec reason = 'analyseJournee'.
class IaNarrativeDailyCache {
  /// Date au format 'YYYY-MM-DD' — utilisée pour détecter le changement de jour.
  final String dateKey;

  /// Message narratif figé pour cette journée.
  final String message;

  /// IDs des templates utilisés pour ce message (anti-répétition mémoire).
  final List<String> templateIds;

  /// Horodatage de création du cache (non utilisé pour l'expiration — seul dateKey compte).
  final DateTime createdAt;

  const IaNarrativeDailyCache({
    required this.dateKey,
    required this.message,
    required this.templateIds,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'dateKey'    : dateKey,
        'message'    : message,
        'templateIds': templateIds,
        'createdAt'  : createdAt.toIso8601String(),
      };

  factory IaNarrativeDailyCache.fromJson(Map<String, dynamic> json) {
    return IaNarrativeDailyCache(
      dateKey    : json['dateKey'] as String? ?? '',
      message    : json['message'] as String? ?? '',
      templateIds: List<String>.from(json['templateIds'] as List<dynamic>? ?? const []),
      createdAt  : DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

// ── Mémoire anti-répétition (existante) ───────────────────────────────────

class IaNarrativeMemory {
  /// IDs des derniers templates utilisés (max 8 en mémoire).
  final List<String> derniersTemplates;

  /// Date de la dernière mise à jour.
  final DateTime updatedAt;

  const IaNarrativeMemory({
    required this.derniersTemplates,
    required this.updatedAt,
  });

  /// Mémoire vide — utilisée comme fallback si absente ou corrompue.
  factory IaNarrativeMemory.vide() => IaNarrativeMemory(
        derniersTemplates: const [],
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'derniersTemplates': derniersTemplates,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory IaNarrativeMemory.fromJson(Map<String, dynamic> json) {
    return IaNarrativeMemory(
      derniersTemplates: List<String>.from(
          (json['derniersTemplates'] as List<dynamic>?) ?? []),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
