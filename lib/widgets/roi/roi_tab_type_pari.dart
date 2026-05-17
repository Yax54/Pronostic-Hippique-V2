// ══════════════════════════════════════════════════════════════════════════════
//  roi_tab_type_pari.dart — Onglet ROI par type de pari
//  ★ v10.46 — Lecture seule
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../models/roi_value_models.dart';
import '../../services/roi_value_service.dart';

class RoiTabTypePari extends StatelessWidget {
  final RoiValueFilters filters;

  const RoiTabTypePari({super.key, required this.filters});

  static const _card = Color(0xFF132035);

  @override
  Widget build(BuildContext context) {
    final groupes = RoiValueService.instance.roiParTypePari(filters);
    final avecDonnees = groupes.where((g) => g.summary.nbParisRoi > 0).toList();

    if (avecDonnees.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Aucune donnée disponible.\nEnregistrez des résultats de courses pour voir le ROI par type de pari.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // En-tête colonnes
        _headerRow(),
        const SizedBox(height: 8),
        ...groupes.map((g) => _ligneType(g)),
        const SizedBox(height: 16),
        _note(),
      ],
    );
  }

  Widget _headerRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(children: const [
        Expanded(flex: 3, child: Text('Type', style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold))),
        Expanded(flex: 1, child: Text('Nb', style: TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center)),
        Expanded(flex: 2, child: Text('Réussite', style: TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center)),
        Expanded(flex: 2, child: Text('ROI', style: TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.right)),
      ]),
    );
  }

  Widget _ligneType(RoiByGroup g) {
    final s        = g.summary;
    final roiColor = s.nbParisRoi == 0
        ? Colors.white24
        : s.roi >= 0 ? Colors.greenAccent : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ligne 1 : type + nb + réussite + ROI
          Row(children: [
            Expanded(
              flex: 3,
              child: Text(g.label,
                  style: const TextStyle(color: Colors.white, fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            Expanded(
              flex: 1,
              child: Text(
                s.nbParisRoi == 0 ? '—' : '${s.nbParisRoi}',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                s.nbParisRoi == 0
                    ? '—'
                    : '${s.tauxReussite.toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                s.nbParisRoi == 0
                    ? 'N/A'
                    : '${s.roi >= 0 ? '+' : ''}${s.roi.toStringAsFixed(1)}%',
                style: TextStyle(
                    color: roiColor, fontSize: 16,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.right,
              ),
            ),
          ]),
          // Ligne 2 : gain net + cote moyenne — Wrap pour petit écran
          if (s.nbParisRoi > 0) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  'Gain net : ${s.gainNet >= 0 ? '+' : ''}${s.gainNet.toStringAsFixed(2)} €',
                  style: TextStyle(
                      color: s.gainNet >= 0 ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 14),
                ),
                if (s.coteMoyenneGagnants > 0)
                  Text(
                    'Cote moy. : ${s.coteMoyenneGagnants.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.amber, fontSize: 14),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _note() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Text(
      '💡 Mise virtuelle 1 € par pari. '
      'Seuls les types avec cote PMU disponible sont inclus dans le ROI.',
      style: TextStyle(color: Colors.white38, fontSize: 14),
    ),
  );
}
