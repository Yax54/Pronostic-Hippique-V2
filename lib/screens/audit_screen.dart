// ★ v10.32 — AuditScreen avec cache léger + bouton "Recalculer audit"
import 'package:flutter/material.dart';

import '../services/ia_audit_cache_service.dart';
import '../widgets/ia/ia_tab_audit.dart';
import '../widgets/ia/ia_tab_correlations.dart';
import '../widgets/ia/ia_tab_criteres_morts.dart';
import '../widgets/ia/ia_tab_discipline.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuditScreen — Section principale "Audit IA"  ★ v10.32
// 4 sous-onglets :
//   • 📊 19 Critères    (Top3 / HorsTop5 / Delta / Diagnostic)
//   • 💀 Morts          (% fallback 50 par critère)
//   • 🔗 Corrélations   (Pearson entre critères vivants)
//   • 🏇 Discipline     (audit séparé Plat / Trot / Obstacle)
//
// Nouveautés v10.32 :
//   • Cache léger IaAuditCacheService — bandeau date dernière MAJ
//   • Bouton "Recalculer audit" → invalide le cache et force le rechargement
//   • Lecture seule — aucun poids modifié, aucun apprentissage
// ─────────────────────────────────────────────────────────────────────────────

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final IaAuditCacheService _cache = IaAuditCacheService();

  DateTime? _cacheDate;
  int       _refreshKey = 0;   // incrémenté pour forcer le rechargement des onglets

  static const Color _gold = Color(0xFFFFD700);
  static const Color _bg   = Color(0xFF0D1B2A);
  static const Color _cyan = Color(0xFF00E5FF);

  @override
  void initState() {
    super.initState();
    _chargerDateCache();
  }

  Future<void> _chargerDateCache() async {
    final d = await _cache.lastUpdated();
    if (mounted) setState(() => _cacheDate = d);
  }

  Future<void> _recalculer() async {
    // Invalide le cache → les onglets recalculeront au prochain accès
    await _cache.invalidate();
    setState(() {
      _cacheDate  = null;
      _refreshKey++;   // force rebuild des onglets
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔄 Cache invalidé — recalcul en cours…'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    // Relire la date après recalcul potentiel
    await Future.delayed(const Duration(milliseconds: 500));
    await _chargerDateCache();
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2,"0")}/${d.month.toString().padLeft(2,"0")}/${d.year} '
           '${d.hour.toString().padLeft(2,"0")}:${d.minute.toString().padLeft(2,"0")}';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text('Audit IA',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: _bg,
          elevation: 0,
          actions: [
            // ── Bouton Recalculer ★ v10.32 ────────────────────────────
            TextButton.icon(
              icon: const Icon(Icons.refresh, color: _cyan, size: 18),
              label: const Text('Recalculer',
                style: TextStyle(color: _cyan, fontSize: 13, fontWeight: FontWeight.w600)),
              onPressed: _recalculer,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(_cacheDate != null ? 68 : 48),
            child: Column(
              children: [
                // ── Bandeau date cache ★ v10.32 ────────────────────────
                if (_cacheDate != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, color: Colors.white38, size: 13),
                        const SizedBox(width: 6),
                        Text(
                          'Dernière mise à jour : ${_formatDate(_cacheDate!)}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                        const Spacer(),
                        const Text('Lecture seule',
                          style: TextStyle(color: Colors.blue, fontSize: 11)),
                      ],
                    ),
                  ),
                // ── Onglets ──────────────────────────────────────────────
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    labelStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    unselectedLabelStyle: const TextStyle(fontSize: 11),
                    labelColor: _gold,
                    unselectedLabelColor: Colors.white54,
                    indicator: BoxDecoration(
                      color: _gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _gold.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: const [
                      Tab(text: '📊 19 Critères'),
                      Tab(text: '💀 Morts'),
                      Tab(text: '🔗 Corrélations'),
                      Tab(text: '🏇 Discipline'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: KeyedSubtree(
          key: ValueKey(_refreshKey),  // force rebuild quand refreshKey change
          child: const TabBarView(
            children: [
              IaTabAudit(),
              IaTabCriteresMorts(),
              IaTabCorrelations(),
              IaTabDiscipline(),
            ],
          ),
        ),
      ),
    );
  }
}
