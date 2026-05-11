import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pmu_provider.dart';
import '../services/data_refresh_service.dart';
// ─── Onglets extraits ──────────────────────────────────────────────────────
import '../widgets/profile/profile_stats_tab.dart';
import '../widgets/profile/profile_historique_tab.dart';
import '../widgets/profile/profile_progression_tab.dart';
import '../widgets/profile/profile_profil_tab.dart';

// ─── Écran Tableau de bord / Profil ──────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // Filtre date (null = toutes les dates)
  DateTime? _dateDebut;
  DateTime? _dateFin;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this); // ★ Lot 3 : +Progression
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PmuProvider>();

    // Prédictions filtrées selon la plage de dates choisie
    final allFiltered = provider.getPredictionsByDateRange(_dateDebut, _dateFin);
    final gainsNet = provider.getGainsNetByDateRange(_dateDebut, _dateFin);
    final miseTotal = allFiltered.fold(0.0, (s, p) => s + p.montantMise);
    final nbGagnes = allFiltered.where((p) => p.isCorrect == true).length;
    final nbPerdus = allFiltered.where((p) => p.isCorrect == false).length;
    final nbAttente = allFiltered.where((p) => p.isCorrect == null).length;
    final taux = allFiltered.isNotEmpty ? (nbGagnes / allFiltered.length) * 100 : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF080E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        title: const Row(children: [
          Icon(Icons.dashboard, color: Color(0xFFFFD700), size: 22),
          SizedBox(width: 8),
          Text('Mon Tableau de Bord',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17)),
        ]),
        actions: [
          // Indicateur de chargement du DataRefreshService
          Consumer<DataRefreshService>(
            builder: (ctx, svc, _) => svc.loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFF4CAF7D), strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh, color: Color(0xFF4CAF7D)),
                    tooltip: svc.lastRefreshLabel,
                    onPressed: () async {
                      await svc.refresh();
                      await provider.reloadPredictions();
                    },
                  ),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFFFFD700),
          labelColor: const Color(0xFFFFD700),
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart, size: 18), text: 'Stats'),
            Tab(icon: Icon(Icons.history, size: 18), text: 'Historique'),
            Tab(icon: Icon(Icons.show_chart, size: 18), text: 'Progression'),
            Tab(icon: Icon(Icons.settings, size: 18), text: 'Profil'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // ── Onglet Stats ──────────────────────────────────────────────────
          ProfileStatsTab(
            provider: provider,
            dateDebut: _dateDebut,
            dateFin: _dateFin,
            allFiltered: allFiltered,
            gainsNet: gainsNet,
            miseTotal: miseTotal,
            nbGagnes: nbGagnes,
            nbPerdus: nbPerdus,
            nbAttente: nbAttente,
            taux: taux,
            onPickDate: _pickDateRange,
            onResetDate: () => setState(() {
              _dateDebut = null;
              _dateFin = null;
            }),
          ),

          // ── Onglet Historique ─────────────────────────────────────────────
          ProfileHistoriqueTab(
            provider: provider,
            allFiltered: allFiltered,
            dateDebut: _dateDebut,
            dateFin: _dateFin,
            onPickDate: _pickDateRange,
            onResetDate: () => setState(() {
              _dateDebut = null;
              _dateFin = null;
            }),
          ),

          // ── Onglet Progression ★ Lot 3 ────────────────────────────────────
          ProfileProgressionTab(provider: provider),

          // ── Onglet Profil / Paramètres ────────────────────────────────────
          ProfileProfilTab(provider: provider),
        ],
      ),
    );
  }

  // ─── Sélection de la plage de dates ─────────────────────────────────────────
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _dateDebut != null && _dateFin != null
          ? DateTimeRange(start: _dateDebut!, end: _dateFin!)
          : null,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF4CAF7D),
            onPrimary: Colors.white,
            surface: Color(0xFF162033),
            onSurface: Colors.white,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF080E1A)),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      setState(() {
        _dateDebut = range.start;
        _dateFin = range.end;
      });
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Onglet STATS
// ══════════════════════════════════════════════════════════════════════════════

