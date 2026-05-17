// ══════════════════════════════════════════════════════════════════════════════
//  roi_tab_global.dart — Onglet Vue globale ROI
//  ★ v10.46 — Lecture seule
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../models/roi_value_models.dart';
import '../../services/roi_value_service.dart';

class RoiTabGlobal extends StatelessWidget {
  final RoiValueFilters filters;

  const RoiTabGlobal({super.key, required this.filters});

  static const _card = Color(0xFF132035);
  static const _gold = Color(0xFFFFD700);

  @override
  Widget build(BuildContext context) {
    final summary  = RoiValueService.instance.calculerResume(filters);
    final parDisc  = RoiValueService.instance.roiParDiscipline(filters);

    if (summary.nbCourses == 0) {
      return _vide('Aucun pronostic avec résultat\npour les filtres sélectionnés.');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _carteRoiGlobal(summary),
        const SizedBox(height: 16),
        _sectionTitle('📊 ROI par discipline'),
        const SizedBox(height: 8),
        ...parDisc.map((g) => _ligneDisc(g)),
        const SizedBox(height: 24),
        _noteBasPage(),
      ],
    );
  }

  // ─── Carte ROI global ──────────────────────────────────────────────────────

  Widget _carteRoiGlobal(RoiSummary s) {
    final roiColor = s.roi >= 0 ? Colors.greenAccent : Colors.redAccent;
    final gainColor = s.gainNet >= 0 ? Colors.greenAccent : Colors.redAccent;

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (s.roi >= 0 ? Colors.greenAccent : Colors.redAccent)
              .withValues(alpha: 0.35),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ROI principal
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text('ROI global',
                    style: TextStyle(color: Colors.white70, fontSize: 16))),
              const SizedBox(width: 8),
              Text(
                '${s.roi >= 0 ? '+' : ''}${s.roi.toStringAsFixed(1)}%',
                style: TextStyle(
                    color: roiColor,
                    fontSize: 26,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 20),
          // Grille de stats
          _grille([
            _stat('Paris ROI', '${s.nbParisRoi}', Colors.white),
            _stat('Gain net',
                '${s.gainNet >= 0 ? '+' : ''}${s.gainNet.toStringAsFixed(2)} €',
                gainColor),
            _stat('Gagnants', '${s.gagnants}', Colors.greenAccent),
            _stat('Perdants', '${s.perdants}', Colors.redAccent),
            _stat('Taux réussite',
                '${s.tauxReussite.toStringAsFixed(1)}%', Colors.white70),
            _stat('Cote moy. G',
                s.coteMoyenneGagnants > 0
                    ? s.coteMoyenneGagnants.toStringAsFixed(2)
                    : '—',
                _gold),
          ]),
          if (s.outsidersGagnants > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Text('🎰', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${s.outsidersGagnants} outsider(s) gagnant(s) — cote ≥ 8.0',
                    style: const TextStyle(color: Colors.amber, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Ligne discipline ──────────────────────────────────────────────────────

  Widget _ligneDisc(RoiByGroup g) {
    final s        = g.summary;
    final roiColor = s.roi >= 0 ? Colors.greenAccent : Colors.redAccent;
    final emoji    = g.label == 'Plat' ? '🏇'
                   : g.label == 'Trot' ? '🐎'
                   : '🏔️';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(g.label,
              style: const TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ),
        if (s.nbParisRoi == 0)
          const Text('Pas de données',
              style: TextStyle(color: Colors.white38, fontSize: 14))
        else ...[
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${s.nbParisRoi} paris',
                style: const TextStyle(color: Colors.white54, fontSize: 14)),
            Text(
              '${s.roi >= 0 ? '+' : ''}${s.roi.toStringAsFixed(1)}%',
              style: TextStyle(
                  color: roiColor, fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ]),
        ],
      ]),
    );
  }

  // ─── Helpers UI ───────────────────────────────────────────────────────────

  Widget _grille(List<Widget> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(Row(children: [
        Expanded(child: items[i]),
        if (i + 1 < items.length) Expanded(child: items[i + 1]),
      ]));
      if (i + 2 < items.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }

  Widget _stat(String label, String value, Color valueColor) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(color: Colors.white38, fontSize: 14)),
      const SizedBox(height: 2),
      Text(value,
          style: TextStyle(
              color: valueColor, fontSize: 18, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(color: Colors.white, fontSize: 18,
          fontWeight: FontWeight.bold));

  Widget _noteBasPage() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Text(
      '💡 ROI calculé sur mise virtuelle de 1 € par pari.\n'
      'Seuls les pronostics avec cote PMU disponible sont inclus.',
      style: TextStyle(color: Colors.white38, fontSize: 14),
    ),
  );

  Widget _vide(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(msg,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 16)),
    ),
  );
}
