// ══════════════════════════════════════════════════════════════════════════════
//  roi_tab_value.dart — Onglet Value Opportunities
//  ★ v10.46 — Lecture seule
//  Cas : IA plus optimiste que le marché (score élevé + cote >= 5 + divergence)
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../models/roi_value_models.dart';
import '../../services/roi_value_service.dart';

class RoiTabValue extends StatelessWidget {
  final RoiValueFilters filters;

  const RoiTabValue({super.key, required this.filters});

  static const _card   = Color(0xFF132035);
  static const _purple = Color(0xFF9C27B0);

  @override
  Widget build(BuildContext context) {
    final values = RoiValueService.instance.detecterValue(filters);

    if (values.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '🔍 Aucune value détectée\n\n'
            'Critères : score IA ≥ 70 + cote ≥ 5.0 + divergence ≥ 60\n'
            '(IA significativement plus optimiste que le marché PMU)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
        ),
      );
    }

    final gagnees = values.where((v) => v.gagne).length;
    final txReuss = values.isEmpty ? 0.0 : gagnees / values.length * 100;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Résumé
        _bandeauResume(values.length, gagnees, txReuss),
        const SizedBox(height: 12),
        // Liste
        ...values.map((v) => _carteValue(v)),
        const SizedBox(height: 16),
        _note(),
      ],
    );
  }

  Widget _bandeauResume(int total, int gagnees, double tx) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _purple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _purple.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _mini('Détectées', '$total', Colors.white),
          _mini('Validées', '$gagnees', Colors.greenAccent),
          _mini('Taux', '${tx.toStringAsFixed(0)}%',
              tx >= 30 ? Colors.greenAccent : Colors.orange),
        ],
      ),
    );
  }

  Widget _carteValue(ValueOpportunity v) {
    final couleur = v.gagne ? Colors.greenAccent : Colors.redAccent;
    final badge   = v.gagne ? '✅' : '❌';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (v.gagne ? Colors.greenAccent : Colors.white12)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ligne 1 : date + discipline + résultat
          Row(children: [
            Text(v.date,
                style: const TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(width: 8),
            _chip(v.discipline, Colors.white24),
            const Spacer(),
            Text(badge, style: const TextStyle(fontSize: 16)),
          ]),
          const SizedBox(height: 6),
          // Nom course
          Text(v.courseNom,
              style: const TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          // Type pari + N° favori IA
          Row(children: [
            _chip(v.typePari, _purple.withValues(alpha: 0.4)),
            const SizedBox(width: 8),
            Text('N°${v.favoriIa}',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ]),
          const SizedBox(height: 8),
          // Stats : score IA / cote / divergence / retour
          Row(children: [
            _kv('Score IA', '${v.scoreIa.toStringAsFixed(0)}', Colors.amber),
            const SizedBox(width: 12),
            _kv('Cote', v.cote.toStringAsFixed(1), Colors.white70),
            const SizedBox(width: 12),
            _kv('Diverg.', '${v.divergence.toStringAsFixed(0)}', _purple),
            const SizedBox(width: 12),
            if (v.gagne)
              _kv('Retour', '+${v.retour.toStringAsFixed(2)} €', couleur),
          ]),
          const SizedBox(height: 6),
          Text(v.explication,
              style: TextStyle(color: couleur.withValues(alpha: 0.8),
                  fontSize: 14)),
        ],
      ),
    );
  }

  Widget _mini(String label, String value, Color color) => Column(
    children: [
      Text(value,
          style: TextStyle(color: color, fontSize: 20,
              fontWeight: FontWeight.bold)),
      Text(label,
          style: const TextStyle(color: Colors.white54, fontSize: 14)),
    ],
  );

  Widget _chip(String label, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label,
        style: const TextStyle(color: Colors.white, fontSize: 12)),
  );

  Widget _kv(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
      Text(value,
          style: TextStyle(color: color, fontSize: 16,
              fontWeight: FontWeight.bold)),
    ],
  );

  Widget _note() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Text(
      '💡 Une "value" est détectée quand l\'IA est fortement optimiste (score ≥ 70) '
      'sur un cheval que le marché sous-cote (cote ≥ 5, divergence ≥ 60).',
      style: TextStyle(color: Colors.white38, fontSize: 14),
    ),
  );
}
