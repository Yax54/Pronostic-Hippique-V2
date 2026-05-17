// ══════════════════════════════════════════════════════════════════════════════
//  roi_tab_outsiders.dart — Onglet Outsiders
//  ★ v10.46 — Lecture seule
//  Chevaux cote >= 8 arrivés top 3 : l'IA les a-t-elle vus ?
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../models/roi_value_models.dart';
import '../../services/roi_value_service.dart';

class RoiTabOutsiders extends StatelessWidget {
  final RoiValueFilters filters;

  const RoiTabOutsiders({super.key, required this.filters});

  static const _card   = Color(0xFF132035);
  static const _amber  = Colors.amber;

  @override
  Widget build(BuildContext context) {
    final outsiders = RoiValueService.instance.analyserOutsiders(filters);

    if (outsiders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '🎰 Aucun outsider rentable détecté\n\n'
            'Critères : cote ≥ 8.0 + arrivé dans le top 3 réel',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
        ),
      );
    }

    final detectes  = outsiders.where((o) => o.detecteParIa).length;
    final ratesPct  = outsiders.isEmpty ? 0.0
        : (outsiders.length - detectes) / outsiders.length * 100;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _bandeauResume(outsiders.length, detectes, ratesPct),
        const SizedBox(height: 12),
        ...outsiders.map((o) => _carteOutsider(o)),
        const SizedBox(height: 16),
        _note(),
      ],
    );
  }

  Widget _bandeauResume(int total, int detectes, double ratesPct) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _mini('Total', '$total', Colors.white),
          _mini('Détectés IA', '$detectes', Colors.greenAccent),
          _mini('Ratés', '${ratesPct.toStringAsFixed(0)}%',
              ratesPct > 50 ? Colors.redAccent : Colors.orange),
        ],
      ),
    );
  }

  Widget _carteOutsider(OutsiderAnalyse o) {
    final couleur   = o.detecteParIa ? Colors.greenAccent : Colors.redAccent;
    final badge     = o.detecteParIa ? '✅ Vu' : '❌ Raté';
    final rangIaStr = o.rangIa == 0 ? 'Non classé' : 'Rang IA : ${o.rangIa}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ligne 1 : date + discipline
          Row(children: [
            Expanded(
              child: Text(o.date,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            _chip(o.discipline, Colors.white12),
            const SizedBox(width: 6),
            Text(badge,
                style: TextStyle(color: couleur, fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          // Nom course
          Text(o.courseNom,
              style: const TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w600),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          // Stats — Wrap pour petit écran
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _kv('N°', o.numero, _amber),
              _kv('Cote', o.cote.toStringAsFixed(1), _amber),
              _kv('Rang réel', '${o.rangReel}ème', Colors.white70),
              _kv('IA', rangIaStr, couleur),
            ],
          ),
          const SizedBox(height: 6),
          Text(o.commentaire,
              style: TextStyle(color: couleur.withValues(alpha: 0.8),
                  fontSize: 14),
              maxLines: 3, overflow: TextOverflow.ellipsis),
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
        color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label,
        style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
      '💡 Outsider = cheval avec cote ≥ 8.0 arrivé dans le top 3 réel.\n'
      'Détecté = présent dans le top 5 IA au moment du pronostic.',
      style: TextStyle(color: Colors.white38, fontSize: 14),
    ),
  );
}
