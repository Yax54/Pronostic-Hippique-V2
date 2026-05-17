// ══════════════════════════════════════════════════════════════════════════════
//  roi_tab_faux_favoris.dart — Onglet Faux Favoris IA
//  ★ v10.46 — Lecture seule
//  confiancePredite >= 80 + pari perdant
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../models/roi_value_models.dart';
import '../../services/roi_value_service.dart';

class RoiTabFauxFavoris extends StatelessWidget {
  final RoiValueFilters filters;

  const RoiTabFauxFavoris({super.key, required this.filters});

  static const _card = Color(0xFF132035);

  @override
  Widget build(BuildContext context) {
    final fauxFav = RoiValueService.instance.detecterFauxFavoris(filters);

    if (fauxFav.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '✅ Aucun faux favori détecté\n\n'
            'Critères : confiance IA ≥ 80 + pari perdant',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
        ),
      );
    }

    final confMoyenne = fauxFav.isEmpty
        ? 0.0
        : fauxFav.map((f) => f.confianceIa).reduce((a, b) => a + b) /
            fauxFav.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _bandeauResume(fauxFav.length, confMoyenne),
        const SizedBox(height: 12),
        ...fauxFav.map((f) => _carteFauxFavori(f)),
        const SizedBox(height: 16),
        _note(),
      ],
    );
  }

  Widget _bandeauResume(int total, double confMoy) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _mini('Faux favoris', '$total', Colors.redAccent),
          _mini('Conf. moy.', '${confMoy.toStringAsFixed(0)}%', Colors.orange),
        ],
      ),
    );
  }

  Widget _carteFauxFavori(FauxFavoriIa f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Colors.redAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ligne 1 : date + discipline
          Row(children: [
            Expanded(
              child: Text(f.date,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            _chip(f.discipline, Colors.white12),
            const SizedBox(width: 6),
            const Text('❌ Perdant',
                style: TextStyle(color: Colors.redAccent, fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          // Nom course
          Text(f.courseNom,
              style: const TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w600),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          // Type pari
          _chip(f.typePari, Colors.deepPurple.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          // Stats — Wrap pour petit écran
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _kv('N°', f.favoriIa, Colors.orange),
              _kv('Confiance', '${f.confianceIa.toStringAsFixed(0)}%',
                  f.confianceIa >= 90 ? Colors.redAccent : Colors.orange),
              _kv('Cote',
                  f.cote > 0 ? f.cote.toStringAsFixed(1) : '—',
                  Colors.white70),
            ],
          ),
          const SizedBox(height: 6),
          // Raison
          Row(children: [
            const Icon(Icons.info_outline, color: Colors.white38, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(f.raisonProbable,
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          ]),
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
      '💡 Faux favori IA = confiance prédite ≥ 80% mais pari non validé.\n'
      'Permet d\'identifier les situations où l\'IA sur-estime ses chances.',
      style: TextStyle(color: Colors.white38, fontSize: 14),
    ),
  );
}
