// ═══════════════════════════════════════════════════════════════════════════
//  IA NARRATIVE CARD — v10.64
//  Widget d'affichage du résumé narratif IA.
//  Complète les stats existantes, ne les remplace pas.
//  Retourne SizedBox.shrink() si le message est vide.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class IaNarrativeCard extends StatelessWidget {
  final String message;

  const IaNarrativeCard({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF17212B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0x3329B6F6),
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🧠', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
