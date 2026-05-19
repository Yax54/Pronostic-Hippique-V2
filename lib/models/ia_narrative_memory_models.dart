// ═══════════════════════════════════════════════════════════════════════════
//  IA NARRATIVE MEMORY MODELS — v10.65
//  Mémoire narrative légère : anti-répétition de templates.
//  Stockée dans SharedPreferences sous 'ia_narrative_memory_v1'.
//
//  RÈGLES BACKUP/RESTAURATION :
//  - Si absente dans un ancien backup → créer mémoire vide (jamais crash)
//  - Si corrompue → reset automatique vers mémoire vide
//  - La narration est secondaire : ne jamais bloquer une restauration principale
// ═══════════════════════════════════════════════════════════════════════════

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
