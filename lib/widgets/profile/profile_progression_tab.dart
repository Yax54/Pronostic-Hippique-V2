import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/pmu_provider.dart';
import '../../models/pmu_models.dart';
// alert_service — TrackedCourse non utilisé directement dans cet onglet
import '../../services/backtesting_service.dart';
import '../../services/ia_user_prefs_service.dart'; // ★ v9.85
import '../../services/ia_memory_service.dart';     // ★ v9.94 : listener temps réel
import '../../utils/format_euros.dart';


// Onglet Progression du ProfileScreen

class ProfileProgressionTab extends StatefulWidget {
  final PmuProvider provider;
  const ProfileProgressionTab({required this.provider});
  @override
  State<ProfileProgressionTab> createState() => ProfileProgressionTabState();
}

class ProfileProgressionTabState extends State<ProfileProgressionTab> {
  static const _gold  = Color(0xFFFFD700);
  static const _green = Color(0xFF4CAF7D);
  static const _card  = Color(0xFF111F30);

  // Backtesting
  double _miseBt     = 10.0;
  String _typePari   = 'Conseil IA';
  int    _nbJours    = 30;
  BacktestResult? _resultatBt;
  bool   _chargement = false;

  // ★ v9.85 : Bankroll
  double _capitalDepart = 100.0;
  static const _keyCapital = 'bankroll_capital_v1';

  static const _typesPari = [
    'Conseil IA', 'Simple Gagnant', 'Simple Placé',
    'Gagnant+Placé', 'Couplé Gagnant', 'Tiercé', 'Quinté+',
  ];

  // ★ v9.94 : listener temps réel backtesting / stats IA
  void _onIaChange() { if (mounted) setState(() {}); }

  @override
  void initState() {
    super.initState();
    _chargerCapital();
    IaMemoryService.instance.addListener(_onIaChange);
  }

  @override
  void dispose() {
    IaMemoryService.instance.removeListener(_onIaChange);
    super.dispose();
  }

  Future<void> _chargerCapital() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _capitalDepart = prefs.getDouble(_keyCapital) ?? 100.0;
    });
  }

  Future<void> _sauvegarderCapital(double val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCapital, val);
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final preds    = provider.predictions;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── ★ v9.85 : Bankroll ────────────────────────────────────────────
        _buildSectionBankroll(preds),
        const SizedBox(height: 20),

        // ── ★ v9.85 : Mise adaptative ────────────────────────────────────
        _buildSectionMiseAdaptative(),
        const SizedBox(height: 20),

        // ── Graphique gains cumulés ───────────────────────────────────────
        _buildGraphiqueGains(preds),
        const SizedBox(height: 20),

        // ── Graphique taux réussite par type de pari ──────────────────────
        _buildGraphiqueTauxParType(preds),
        const SizedBox(height: 20),

        // ── Section Backtesting ───────────────────────────────────────────
        _buildSectionBacktesting(),
      ]),
    );
  }

  // ── ★ v9.85 : Bankroll ────────────────────────────────────────────────────
  Widget _buildSectionBankroll(List<UserPrediction> preds) {
    final resolus = preds.where((p) => p.isCorrect != null && p.montantMise > 0).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    double capital = _capitalDepart;
    for (final p in resolus) capital += p.gainNet;

    final gain      = capital - _capitalDepart;
    final gainColor = gain >= 0 ? _green : const Color(0xFFEF5350);
    final roi       = _capitalDepart > 0 ? (gain / _capitalDepart * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gain >= 0
              ? [const Color(0xFF0A2B18), const Color(0xFF0D1B2A)]
              : [const Color(0xFF2B0A0A), const Color(0xFF0D1B2A)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gainColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: gainColor, size: 20),
              const SizedBox(width: 8),
              const Text('Bankroll', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              GestureDetector(
                onTap: () => _editerCapital(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, color: Colors.white38, size: 12),
                      SizedBox(width: 4),
                      Text('Capital', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _bankrollStat('Capital départ', '${_capitalDepart.toStringAsFixed(0)} €', Colors.white54),
              _bankrollStat('Capital actuel', '${capital.toStringAsFixed(0)} €', gainColor),
              _bankrollStat('ROI', '${roi >= 0 ? "+" : ""}${roi.toStringAsFixed(1)}%', gainColor),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(gain >= 0 ? Icons.trending_up : Icons.trending_down, color: gainColor, size: 16),
              const SizedBox(width: 6),
              Text(
                '${gain >= 0 ? "+" : ""}${gain.toStringAsFixed(0)} € depuis le départ · ${resolus.length} paris résolus',
                style: TextStyle(color: gainColor, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bankrollStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }

  void _editerCapital() {
    final ctrl = TextEditingController(text: _capitalDepart.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A1628),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Capital de départ', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Ex: 100',
            hintStyle: TextStyle(color: Colors.white38),
            suffixText: '€',
            suffixStyle: TextStyle(color: Colors.white54),
            filled: true, fillColor: Color(0xFF111F30),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () async {
              final val = double.tryParse(ctrl.text) ?? _capitalDepart;
              setState(() => _capitalDepart = val.clamp(1.0, 100000.0));
              await _sauvegarderCapital(_capitalDepart);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Valider', style: TextStyle(color: Color(0xFF4CAF7D))),
          ),
        ],
      ),
    );
  }

  // ── ★ v9.85 : Mise adaptative ─────────────────────────────────────────────
  Widget _buildSectionMiseAdaptative() {
    final userPrefs = IaUserPrefsService.instance.prefs;
    if (userPrefs.miseHabituelle == 0) return const SizedBox();

    final suggestions = [
      (label: 'Confiance < 60%',  score: 50.0),
      (label: 'Confiance 60–75%', score: 68.0),
      (label: 'Confiance 75–88%', score: 80.0),
      (label: 'Confiance ≥ 88%',  score: 92.0),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111F30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('💡', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text('Mise adaptative IA',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Basée sur votre mise habituelle de ${userPrefs.miseHabituelle.toStringAsFixed(0)} €',
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 12),
          ...suggestions.map((s) {
            final mise = IaUserPrefsService.instance.miseSuggeree(s.score);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text(s.label,
                      style: const TextStyle(color: Colors.white70, fontSize: 13))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00BCD4).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00BCD4).withValues(alpha: 0.3)),
                    ),
                    child: Text('${mise.toStringAsFixed(0)} €',
                        style: const TextStyle(color: Color(0xFF00BCD4), fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }


  Widget _buildGraphiqueGains(List<UserPrediction> preds) {
    // Construire les points du graphique : gain cumulé après chaque pari
    final sortedPreds = preds
        .where((p) => p.isCorrect != null && p.montantMise > 0)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (sortedPreds.isEmpty) {
      return _emptyCard('Pas encore de données',
          'Vos paris apparaîtront ici une fois validés.');
    }

    double cumule = 0.0;
    final points = <double>[];
    for (final p in sortedPreds) {
      cumule += p.gainNet;
      points.add(cumule);
    }

    final gainFinal = points.last;
    final gainColor = gainFinal >= 0 ? _green : const Color(0xFFEF5350);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Évolution des gains cumulés',
          style: TextStyle(
              color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(children: [
          // Résumé rapide
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Total cumulé',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
              Text(
                '${gainFinal >= 0 ? "+" : ""}${fmtEuros(gainFinal)} €',
                style: TextStyle(
                    color: gainColor,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
              ),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${sortedPreds.length} paris',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              Text(
                '${sortedPreds.where((p) => p.isCorrect == true).length} gagnes',
                style: const TextStyle(color: _green, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ]),
          ]),
          const SizedBox(height: 14),
          // Graphique
          SizedBox(
            height: 120,
            child: CustomPaint(
              painter: ProfileGainsCumulsPainter(points: points),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 8),
          // Axe X simplifié
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(
              sortedPreds.first.createdAt.day.toString().padLeft(2,'0') +
              '/' + sortedPreds.first.createdAt.month.toString().padLeft(2,'0'),
              style: const TextStyle(color: Colors.white24, fontSize: 10),
            ),
            Text(
              'Paris N°${sortedPreds.length}',
              style: const TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ]),
        ]),
      ),
    ]);
  }

  // ── Graphique 2 : Taux par type de pari ───────────────────────────────────
  Widget _buildGraphiqueTauxParType(List<UserPrediction> preds) {
    // Grouper par type de pari
    final statsParType = <String, ({int nb, int gagnes, double gainNet})>{};
    for (final p in preds.where((p) => p.isCorrect != null)) {
      final t = p.typePari;
      final s = statsParType[t];
      if (s == null) {
        statsParType[t] = (nb: 1, gagnes: p.isCorrect == true ? 1 : 0, gainNet: p.gainNet);
      } else {
        statsParType[t] = (
          nb:      s.nb + 1,
          gagnes:  s.gagnes + (p.isCorrect == true ? 1 : 0),
          gainNet: s.gainNet + p.gainNet,
        );
      }
    }

    if (statsParType.isEmpty) {
      return _emptyCard('Pas encore de données',
          'Les statistiques par type de pari s\'afficheront ici.');
    }

    final sorted = statsParType.entries.toList()
      ..sort((a, b) => b.value.nb.compareTo(a.value.nb));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Performance par type de pari',
          style: TextStyle(
              color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: sorted.map((e) {
            final taux = e.value.nb > 0
                ? e.value.gagnes / e.value.nb : 0.0;
            final gainColor = e.value.gainNet >= 0 ? _green : const Color(0xFFEF5350);
            final barColor = taux >= 0.4 ? _green : taux >= 0.25 ? _gold : const Color(0xFFEF5350);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(e.key,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                  Text(
                    '${e.value.gagnes}/${e.value.nb} — '
                    '${(taux * 100).round()}%',
                    style: TextStyle(color: barColor, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${e.value.gainNet >= 0 ? "+" : ""}${fmtEuros(e.value.gainNet)}€',
                    style: TextStyle(color: gainColor, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ]),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: taux.clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    minHeight: 7,
                  ),
                ),
              ]),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  // ── Section Backtesting ───────────────────────────────────────────────────
  Widget _buildSectionBacktesting() {
    final nbDispo = BacktestingService.instance.nbCoursesDisponibles;
    final plage   = BacktestingService.instance.plageDisponible;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Simulateur de stratégie',
            style: TextStyle(
                color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$nbDispo courses',
              style: const TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ]),

      if (nbDispo == 0) ...[
        const SizedBox(height: 10),
        _emptyCard('Pas encore de données',
            'Le simulateur a besoin de courses avec résultats réels.'
            ' Attendez quelques jours que l\'IA accumule de l\'historique.'),
      ] else ...[
        const SizedBox(height: 4),
        if (plage.debut != null)
          Text(
            'Historique disponible : du ${_fmt(plage.debut!)} au ${_fmt(plage.fin!)}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        const SizedBox(height: 12),

        // Paramètres
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(children: [
            // Mise
            Row(children: [
              const Text('Mise par course :',
                  style: TextStyle(color: Colors.white60, fontSize: 13)),
              const Spacer(),
              Text('${_miseBt.round()} €',
                  style: const TextStyle(
                      color: _gold, fontSize: 15, fontWeight: FontWeight.bold)),
            ]),
            Slider(
              value: _miseBt,
              min: 2, max: 100,
              divisions: 49,
              activeColor: _gold,
              inactiveColor: Colors.white.withValues(alpha: 0.1),
              onChanged: (v) => setState(() => _miseBt = v.roundToDouble()),
            ),

            const SizedBox(height: 8),

            // Type de pari
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Stratégie :',
                  style: TextStyle(color: Colors.white60, fontSize: 13)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: _typesPari.map((t) {
                final sel = _typePari == t;
                return GestureDetector(
                  onTap: () => setState(() => _typePari = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: sel ? _green.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: sel ? _green : Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Text(t,
                        style: TextStyle(
                            color: sel ? _green : Colors.white38,
                            fontSize: 12,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 10),

            // Période
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Période :',
                  style: TextStyle(color: Colors.white60, fontSize: 13)),
            ),
            const SizedBox(height: 6),
            Row(
              children: [7, 14, 30, 60, 90].map((d) {
                final sel = _nbJours == d;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _nbJours = d),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: sel
                            ? _gold.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: sel ? _gold : Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: Text('${d}j',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: sel ? _gold : Colors.white38,
                              fontSize: 13,
                              fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 14),

            // Bouton lancer
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _chargement
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.play_arrow, size: 20),
                label: Text(
                    _chargement ? 'Simulation en cours...' : 'Lancer la simulation',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _chargement ? null : _lancerBacktest,
              ),
            ),
          ]),
        ),

        // Résultats
        if (_resultatBt != null) ...[
          const SizedBox(height: 16),
          _buildResultatBacktest(_resultatBt!),
        ],
      ],
    ]);
  }

  Future<void> _lancerBacktest() async {
    setState(() { _chargement = true; _resultatBt = null; });
    try {
      final result = await BacktestingService.instance.lancer(
        mise:     _miseBt,
        typePari: _typePari,
        nbJours:  _nbJours,
      );
      setState(() => _resultatBt = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur simulation : $e'),
              backgroundColor: Colors.red));
      }
    } finally {
      setState(() => _chargement = false);
    }
  }

  Widget _buildResultatBacktest(BacktestResult r) {
    final gainColor = r.gainNet >= 0 ? _green : const Color(0xFFEF5350);
    final roiColor  = r.roi >= 0 ? _green : const Color(0xFFEF5350);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: r.estRentable
                ? _green.withValues(alpha: 0.4)
                : const Color(0xFFEF5350).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // En-tête résultat
        Row(children: [
          Text(
            r.estRentable ? '✅ Stratégie rentable !' : '📊 Résultat de la simulation',
            style: TextStyle(
                color: r.estRentable ? _green : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 14),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: gainColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${r.gainNet >= 0 ? "+" : ""}${fmtEuros(r.gainNet)} €',
              style: TextStyle(
                  color: gainColor, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ]),

        const SizedBox(height: 12),
        const Divider(color: Color(0xFF1A2A3A), height: 1),
        const SizedBox(height: 12),

        // Métriques clés
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          ProfileMetriqueCol(
              label: 'Paris', valeur: '${r.nbTotal}', couleur: Colors.white70),
          ProfileMetriqueCol(
              label: 'Gagnés', valeur: '${r.nbGagnes}', couleur: _green),
          ProfileMetriqueCol(
              label: 'Taux', valeur: '${r.tauxReussite.round()}%',
              couleur: r.tauxReussite >= 30 ? _green : _gold),
          ProfileMetriqueCol(
              label: 'ROI',
              valeur: '${r.roi >= 0 ? "+" : ""}${r.roi.round()}%',
              couleur: roiColor),
        ]),

        const SizedBox(height: 12),

        // Mise / Gains / Gain net
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          ProfileMetriqueCol(
              label: 'Misé total',
              valeur: '${r.miseTotal.round()}€',
              couleur: Colors.white54),
          ProfileMetriqueCol(
              label: 'Retours',
              valeur: '${r.gainsTotal.round()}€',
              couleur: Colors.white70),
          ProfileMetriqueCol(
              label: 'Gain net',
              valeur: '${r.gainNet >= 0 ? "+" : ""}${r.gainNet.round()}€',
              couleur: gainColor),
        ]),

        if (r.nbTotal > 2) ...[
          const SizedBox(height: 12),
          // Séries
          Row(children: [
            _badge('🔥 Série max gagnante : ${r.meilleureSerieGagnante}',
                _green.withValues(alpha: 0.15), _green),
            const SizedBox(width: 8),
            _badge('📉 Série max perdante : ${r.pireSeriesPerdantes}',
                const Color(0xFFEF5350).withValues(alpha: 0.15),
                const Color(0xFFEF5350)),
          ]),
        ],

        // Courbe gains simulés
        if (r.courbeGains.length > 2) ...[
          const SizedBox(height: 14),
          const Text('Évolution du capital simulé',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 6),
          SizedBox(
            height: 80,
            child: CustomPaint(
              painter: ProfileGainsCumulsPainter(points: r.courbeGains),
              size: Size.infinite,
            ),
          ),
        ],

        // Top discipline
        if (r.parDiscipline.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF1A2A3A), height: 1),
          const SizedBox(height: 10),
          const Text('Par discipline',
              style: TextStyle(
                  color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...r.parDiscipline.entries.map((e) {
            final taux = e.value.taux;
            final color = taux >= 35 ? _green : taux >= 20 ? _gold : Colors.white38;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Expanded(
                    child: Text(e.key,
                        style: const TextStyle(color: Colors.white54, fontSize: 12))),
                Text('${e.value.nbGagnes}/${e.value.nbTotal}',
                    style: TextStyle(color: color, fontSize: 12)),
                const SizedBox(width: 8),
                Text('${taux.round()}%',
                    style: TextStyle(
                        color: color, fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Widget _emptyCard(String titre, String message) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(children: [
          Icon(Icons.hourglass_empty,
              color: Colors.white.withValues(alpha: 0.15), size: 48),
          const SizedBox(height: 12),
          Text(titre,
              style: const TextStyle(
                  color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          Text(message,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center),
        ]),
      );

  Widget _badge(String txt, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(txt, style: TextStyle(color: fg, fontSize: 11)));

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
}

// ── Métriques column ──────────────────────────────────────────────────────────
class ProfileMetriqueCol extends StatelessWidget {
  final String label, valeur;
  final Color  couleur;
  const ProfileMetriqueCol({required this.label, required this.valeur, required this.couleur});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(valeur, style: TextStyle(color: couleur, fontWeight: FontWeight.bold, fontSize: 18)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
  ]);
}

// ── CustomPainter : courbe de gains cumulés ───────────────────────────────────
class ProfileGainsCumulsPainter extends CustomPainter {
  final List<double> points;
  const ProfileGainsCumulsPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final n   = points.length;
    final min = points.reduce(math.min);
    final max = points.reduce(math.max);
    final range = (max - min).abs();

    // Ligne zéro
    if (min < 0 && max > 0) {
      final zeroY = size.height - ((0 - min) / (range == 0 ? 1 : range)) * size.height * 0.85 - size.height * 0.07;
      canvas.drawLine(
        Offset(0, zeroY),
        Offset(size.width, zeroY),
        Paint()..color = Colors.white.withValues(alpha: 0.12)..strokeWidth = 1,
      );
    }

    double _y(double v) {
      if (range == 0) return size.height / 2;
      return size.height - ((v - min) / range) * size.height * 0.85 - size.height * 0.07;
    }

    // Chemin dégradé sous la courbe
    final lastVal  = points.last;
    final lineColor = lastVal >= 0 ? const Color(0xFF4CAF7D) : const Color(0xFFEF5350);

    final path = Path();
    path.moveTo(0, _y(points.first));
    for (int i = 1; i < n; i++) {
      final x = size.width * i / (n - 1);
      path.lineTo(x, _y(points[i]));
    }

    // Remplissage transparent
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = lineColor.withValues(alpha: 0.08));

    // Ligne principale
    canvas.drawPath(path,
        Paint()
          ..color = lineColor
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);

    // Point final
    final lastX = size.width;
    final lastY = _y(lastVal);
    canvas.drawCircle(Offset(lastX, lastY), 5,
        Paint()..color = lineColor.withValues(alpha: 0.3));
    canvas.drawCircle(Offset(lastX, lastY), 3.5,
        Paint()..color = lineColor);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


