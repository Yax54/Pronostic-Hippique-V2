// ═══════════════════════════════════════════════════════════════════════════
//  IA SPEECH WIDGET — v9.85
//  Phrase contextuelle de l'IA sous le score chiffré (non-binaire)
//  ★ v9.85 : Enrichi avec calibration par hippodrome
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import '../../services/ia_personality_service.dart';
import '../../services/ia_memory_service.dart';

class IaSpeechWidget extends StatelessWidget {
  final double score;       // 0–100
  final String nomCheval;
  final String hippodrome;  // ★ v9.85 : optionnel — enrichit la phrase si données dispo
  final bool compact;       // true = une seule ligne courte

  const IaSpeechWidget({
    super.key,
    required this.score,
    required this.nomCheval,
    this.hippodrome = '',   // rétrocompatible — '' = pas de contexte hippodrome
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final svc    = IaPersonalityService.instance;

    // ★ v9.87 : Récupérer le taux hippodrome si disponible
    double? tauxHippo;
    if (hippodrome.isNotEmpty) {
      final precisions = IaMemoryService.instance.precisionParHippodromeAvecFiabilite;
      final entry = precisions[hippodrome];
      tauxHippo = entry != null ? (entry['taux'] as num?)?.toDouble() : null;
    }

    final phrase = (hippodrome.isNotEmpty)
        ? svc.phraseConfianceHippodrome(score, nomCheval, hippodrome, tauxHippo)
        : svc.phraseConfiance(score, nomCheval);

    final color  = score >= 80
        ? const Color(0xFF4CAF7D)
        : score >= 65
            ? const Color(0xFFFFB74D)
            : const Color(0xFF90A4AE);

    if (compact) {
      return Row(
        children: [
          Text(svc.avatarEmoji,
              style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              phrase,
              style: TextStyle(
                color: color.withValues(alpha: 0.85),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(svc.avatarEmoji,
              style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              phrase,
              style: TextStyle(
                color: color.withValues(alpha: 0.9),
                fontSize: 13,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
