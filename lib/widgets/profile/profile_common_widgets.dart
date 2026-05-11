import 'package:flutter/material.dart';

// Widgets partagés entre plusieurs onglets du ProfileScreen

class ProfileDateFilterBar extends StatelessWidget {
  final DateTime? dateDebut;
  final DateTime? dateFin;
  final VoidCallback onPickDate;
  final VoidCallback onReset;

  const ProfileDateFilterBar({
    required this.dateDebut,
    required this.dateFin,
    required this.onPickDate,
    required this.onReset,
  });

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final hasFilter = dateDebut != null;

    return Row(children: [
      // Bouton choisir dates
      Expanded(
        child: InkWell(
          onTap: onPickDate,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: hasFilter
                  ? const Color(0xFF1565C0).withValues(alpha: 0.2)
                  : const Color(0xFF162033).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasFilter ? const Color(0xFF4CAF7D) : const Color(0xFF1E3A5C).withValues(alpha: 0.4),
              ),
            ),
            child: Row(children: [
              const Icon(Icons.calendar_month, color: Color(0xFF4CAF7D), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasFilter
                      ? '${_fmt(dateDebut!)} → ${_fmt(dateFin!)}'
                      : 'Filtrer par période…',
                  style: TextStyle(
                    color: hasFilter ? Colors.white : Colors.white38,
                    fontSize: 14,
                    fontWeight: hasFilter ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),

      // Bouton reset si filtre actif
      if (hasFilter) ...[
        const SizedBox(width: 8),
        InkWell(
          onTap: onReset,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEF5350).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.close, color: Color(0xFFEF5350), size: 18),
          ),
        ),
      ],
    ]);
  }
}

// ─── Grille de stats ───────────────────────────────────────────────────────────

