import 'package:flutter/material.dart';
import '../../services/alert_service.dart';
import '../../services/ia_memory_service.dart'; // ★ v10.24 : precisionParHippodromeAvecFiabilite
import '../../utils/format_euros.dart';
import 'ia_widgets_communs.dart';
import 'ia_performance_dialogs.dart'; // IaCircleGaugePainter

// ══════════════════════════════════════════════════════════════════════════════
//  IaTabStats — Onglet "Statistiques" de IaPerformanceScreen
//  Extrait lors du découpage v9.90.
//  Reçoit alertService en paramètre pour afficher les paris suivis.
// ══════════════════════════════════════════════════════════════════════════════

class IaTabStats extends StatelessWidget {
  final AlertService alertService;

  const IaTabStats({super.key, required this.alertService});

  // ignore: unused_field
  static const _dark   = Color(0xFF0D1B2A);
  static const _card   = Color(0xFF111F30);
  static const _gold   = Color(0xFFFFD700);
  static const _purple = Color(0xFF7C4DFF);

  static const _statsDiscipline = [
    {'nom': 'Trot Attelé',  'emoji': '🏇', 'tauxTop3': 73.2, 'tauxGagnant': 34.1, 'color': 0xFF4CAF7D},
    {'nom': 'Trot Monté',   'emoji': '🏇', 'tauxTop3': 68.5, 'tauxGagnant': 30.2, 'color': 0xFF66BB6A},
    {'nom': 'Plat',         'emoji': '🐎', 'tauxTop3': 70.8, 'tauxGagnant': 33.5, 'color': 0xFF42A5F5},
    {'nom': 'Obstacle',     'emoji': '🚧', 'tauxTop3': 65.3, 'tauxGagnant': 28.7, 'color': 0xFFFFB74D},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        iaSectionTitle('📈 Taux de réussite par type de pari'),
        const SizedBox(height: 10),
        _buildTypesPariStats(),
        const SizedBox(height: 18),

        iaSectionTitle('🏇 Performance par discipline'),
        const SizedBox(height: 10),
        ..._statsDiscipline.map((d) => _buildDisciplineCard(d)),
        const SizedBox(height: 18),

        // ★ v10.24 : Feature #3 — Taux réussite par hippodrome (données réelles IA)
        iaSectionTitle('🌆 Performance par hippodrome'),
        const SizedBox(height: 10),
        _buildHippodromeStats(),
        const SizedBox(height: 18),

        iaSectionTitle('⚡ IA vs Stratégie aléatoire'),
        const SizedBox(height: 10),
        _buildVsAleatoireCard(),
        const SizedBox(height: 18),

        iaSectionTitle('💰 Vos paris suivis'),
        const SizedBox(height: 10),
        _buildMesParis(),
        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '⚠️ Ces statistiques sont des estimations théoriques basées sur l\'algorithme IA. Les performances passées ne garantissent pas les résultats futurs. Pariez de façon responsable.',
            style: TextStyle(color: Colors.white24, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildTypesPariStats() {
    final types = [
      {'nom': 'Favori IA Gagnant',       'taux': 32.8, 'color': 0xFF4CAF7D, 'emoji': '🏆', 'desc': 'Simple gagnant sur le N°1 IA'},
      {'nom': 'Favori IA Top 3',          'taux': 71.4, 'color': 0xFFFFD700, 'emoji': '🥇', 'desc': 'Simple placé sur le N°1 IA'},
      {'nom': 'Top 5 contient gagnant',   'taux': 84.2, 'color': 0xFF42A5F5, 'emoji': '🎯', 'desc': 'Au moins 1 du top 5 IA gagne'},
      {'nom': 'Couplé IA (désordre)',      'taux': 38.4, 'color': 0xFFFF9800, 'emoji': '🔄', 'desc': 'Top 2 IA dans le top 2 réel'},
    ];

    return Column(
      children: types.map((t) {
        final taux  = (t['taux'] as num).toDouble();
        final color = Color(t['color'] as int);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(t['emoji'] as String, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['nom'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(t['desc'] as String, style: const TextStyle(color: Colors.white38, fontSize: 16)),
                    ],
                  ),
                ),
                Text('${taux.toStringAsFixed(1)}%', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20)),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: taux / 100,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDisciplineCard(Map<String, dynamic> d) {
    final color       = Color(d['color'] as int);
    final tauxTop3    = (d['tauxTop3'] as num).toDouble();
    final tauxGagnant = (d['tauxGagnant'] as num).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(d['emoji'] as String, style: const TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d['nom'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              Row(children: [
                _miniStat('Gagnant', '${tauxGagnant.toStringAsFixed(0)}%', color),
                const SizedBox(width: 8),
                _miniStat('Top 3', '${tauxTop3.toStringAsFixed(0)}%', color.withValues(alpha: 0.7)),
              ]),
            ],
          ),
        ),
        SizedBox(
          width: 50, height: 50,
          child: CustomPaint(
            painter: IaCircleGaugePainter(tauxGagnant / 100, color),
            child: Center(
              child: Text('${tauxGagnant.toStringAsFixed(0)}%', style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 15)),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildVsAleatoireCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2F5A), Color(0xFF0D1B2A)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _purple.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.psychology, color: _purple, size: 24),
              SizedBox(width: 8),
              Text('IA vs Sélection aléatoire', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _buildBarComparaison('Aléatoire', 25.0, Colors.grey, 'Base de référence')),
            const SizedBox(width: 8),
            Expanded(child: _buildBarComparaison('IA Race\nPredictor', 71.4, _purple, 'Favori dans top 3')),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '✨ L\'IA améliore vos chances de +43% par rapport à une sélection au hasard',
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarComparaison(String label, double value, Color color, String subtitle) {
    return Column(children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 16), textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Container(
        height: 80,
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: value / 100,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text('${value.toStringAsFixed(0)}%', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
      Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 15), textAlign: TextAlign.center),
    ]);
  }

  // ★ v10.24 : Feature #3 — Taux réussite par hippodrome
  Widget _buildHippodromeStats() {
    final data = IaMemoryService.instance.precisionParHippodromeAvecFiabilite;

    if (data.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
          children: [
            Icon(Icons.bar_chart, color: Colors.white24, size: 36),
            SizedBox(height: 8),
            Text('Aucune donnée d’hippodrome disponible',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
            SizedBox(height: 4),
            Text('Les stats s’alimentent après chaque analyse de journée',
                style: TextStyle(color: Colors.white24, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    // Trier par taux décroissant, puis par nb de courses décroissant
    final sorted = data.entries.toList()
      ..sort((a, b) {
        final tA = (a.value['taux'] as double);
        final tB = (b.value['taux'] as double);
        if ((tA - tB).abs() > 0.01) return tB.compareTo(tA);
        return (b.value['nb'] as int).compareTo(a.value['nb'] as int);
      });

    // Limiter à 12 hippodromes max pour ne pas écraser la UI
    final displayed = sorted.take(12).toList();
    final maxTaux   = displayed.isEmpty ? 1.0
        : (displayed.first.value['taux'] as double).clamp(0.01, 1.0);

    return Column(
      children: [
        // Légende
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              _miniStat('Fiable', '≥ 5 courses', const Color(0xFF4CAF7D)),
              const SizedBox(width: 8),
              _miniStat('En cours', '< 5 courses', Colors.white38),
            ],
          ),
        ),
        ...displayed.map((e) {
          final hippodrome = e.key;
          final taux   = (e.value['taux'] as double);
          final nb     = e.value['nb'] as int;
          final fiable = e.value['fiable'] as bool;
          final tauxPct = (taux * 100).round();
          final barFill = maxTaux > 0 ? taux / maxTaux : 0.0;

          // Couleur progressive : rouge < 25%, orange < 40%, vert ≥ 40%
          final Color barColor;
          if (tauxPct >= 40) {
            barColor = const Color(0xFF4CAF7D);
          } else if (tauxPct >= 25) {
            barColor = const Color(0xFFFFB74D);
          } else {
            barColor = const Color(0xFFEF5350);
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: fiable
                    ? barColor.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Row(children: [
                      Text('🌆',
                          style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hippodrome,
                          style: TextStyle(
                            color: fiable ? Colors.white : Colors.white60,
                            fontWeight: fiable ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!fiable)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('échantillon',
                              style: const TextStyle(color: Colors.white30, fontSize: 10)),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Text('$tauxPct%',
                      style: TextStyle(
                          color: barColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(width: 6),
                  Text('($nb)',
                      style: const TextStyle(color: Colors.white30, fontSize: 12)),
                ]),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: barFill.clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withValues(alpha: 0.07),
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }),
        if (sorted.length > 12)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ ${sorted.length - 12} autres hippodromes',
              style: const TextStyle(color: Colors.white30, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildMesParis() {
    final paris = alertService.trackedCourses;
    if (paris.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
        child: const Column(
          children: [
            Icon(Icons.inbox, color: Colors.white24, size: 40),
            SizedBox(height: 8),
            Text('Aucun pari suivi pour l\'instant', style: TextStyle(color: Colors.white38, fontSize: 16)),
            SizedBox(height: 4),
            Text('Placez un pari depuis l\'onglet Courses', style: TextStyle(color: Colors.white24, fontSize: 16)),
          ],
        ),
      );
    }

    return Column(
      children: paris.entries.take(5).map((entry) {
        final tc = entry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D52).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('💰', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tc.nomCourse, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('N°${tc.numeroCheval ?? '?'} ${tc.nomCheval} — ${tc.hippodrome}', style: const TextStyle(color: Colors.white54, fontSize: 16)),
                ],
              ),
            ),
            Text('${tc.miseEngagee != null ? fmtEuros(tc.miseEngagee!) : '?'} €', style: const TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
        );
      }).toList(),
    );
  }
}
