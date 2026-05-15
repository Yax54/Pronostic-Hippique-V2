import 'package:flutter/material.dart';

import '../widgets/ia/ia_tab_audit.dart';
import '../widgets/ia/ia_tab_criteres_morts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuditScreen — Section principale "Audit IA"
// 2 sous-onglets :
//   • 📊 19 Critères  (Top3 / HorsTop5 / Delta / Diagnostic)
//   • 💀 Critères Morts  (% fallback 50 par critère)
// ─────────────────────────────────────────────────────────────────────────────

class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        appBar: AppBar(
          title: const Text('Audit IA'),
          backgroundColor: const Color(0xFF0D1B2A),
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                labelColor: const Color(0xFFFFD700),
                unselectedLabelColor: Colors.white54,
                indicator: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: '📊 19 Critères'),
                  Tab(text: '💀 Critères Morts'),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            IaTabAudit(),
            IaTabCriteresMorts(),
          ],
        ),
      ),
    );
  }
}
