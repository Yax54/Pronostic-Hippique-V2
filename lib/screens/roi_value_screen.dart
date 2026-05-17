// ══════════════════════════════════════════════════════════════════════════════
//  roi_value_screen.dart — Écran ROI / Value Analytics
//  ★ v10.46 — Module 100% LECTURE SEULE
//  ★ v10.47 — Export PNG par onglet (RepaintBoundary + SharePlus)
//
//  ⚠️ Aucune écriture dans IaMemoryService, poids ou SharedPreferences.
//  Ce module est un radar ROI, pas un pilote automatique.
//
//  5 onglets :
//    0 Vue globale
//    1 Type de pari
//    2 Value
//    3 Outsiders
//    4 Faux favoris
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/roi_value_models.dart';
import '../services/roi_value_service.dart';
import '../widgets/roi/roi_tab_global.dart';
import '../widgets/roi/roi_tab_type_pari.dart';
import '../widgets/roi/roi_tab_value.dart';
import '../widgets/roi/roi_tab_outsiders.dart';
import '../widgets/roi/roi_tab_faux_favoris.dart';

class RoiValueScreen extends StatefulWidget {
  const RoiValueScreen({super.key});

  @override
  State<RoiValueScreen> createState() => _RoiValueScreenState();
}

class _RoiValueScreenState extends State<RoiValueScreen>
    with SingleTickerProviderStateMixin {

  static const _bg   = Color(0xFF0A1628);
  static const _card = Color(0xFF132035);

  late TabController _tabController;
  RoiValueFilters _filters = const RoiValueFilters();

  // ── Clés RepaintBoundary — une par onglet ──────────────────────────────────
  final List<GlobalKey> _exportKeys = List.generate(5, (_) => GlobalKey());

  // ── Labels onglets (pour le nom de fichier export) ─────────────────────────
  static const _tabLabels = [
    'global', 'type_pari', 'value', 'outsiders', 'faux_favoris',
  ];
  static const _tabTitles = [
    '🌐 Vue globale',
    '🎯 Type de pari',
    '💎 Value',
    '🎰 Outsiders',
    '⚠️ Faux favoris',
  ];

  // Options filtres
  static const _disciplines = ['Toutes', 'Plat', 'Trot', 'Obstacle'];
  static const _periodes    = ['complet', '30j', '7j'];
  static const _typesPari   = [
    'Tous', 'Simple Gagnant', 'Simple Placé',
    'Couplé Gagnant', 'Couplé Placé',
    'Tiercé', 'Quarté+', 'Quinté+',
  ];

  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Export PNG de l'onglet actif ──────────────────────────────────────────
  Future<void> _exporter() async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      // Laisser Flutter finir le rendu
      await Future.delayed(const Duration(milliseconds: 200));

      final tabIdx  = _tabController.index;
      final key     = _exportKeys[tabIdx];
      final label   = _tabLabels[tabIdx];
      final title   = _tabTitles[tabIdx];

      final boundary = key.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur : widget non rendu.')));
        }
        return;
      }

      final image    = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final dir   = await getTemporaryDirectory();
      final now   = DateTime.now();
      final fname = 'roi_value_${label}_'
          '${now.year}${now.month.toString().padLeft(2, "0")}${now.day.toString().padLeft(2, "0")}'
          '_${now.hour.toString().padLeft(2, "0")}${now.minute.toString().padLeft(2, "0")}.png';
      final file  = File('${dir.path}/$fname');
      await file.writeAsBytes(bytes);

      await SharePlus.instance.share(ShareParams(
        files:   [XFile(file.path, mimeType: 'image/png')],
        subject: 'ROI/Value $title — ${_filters.periode} — Pronostic Hippique',
      ));

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur export : $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nbTotal = RoiValueService.instance.nbPronosticsTotal;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        elevation: 0,
        title: const Text(
          '📈 ROI / Value',
          style: TextStyle(color: Colors.white, fontSize: 20,
              fontWeight: FontWeight.bold),
        ),
        actions: [
          // ── Bouton Export PNG ──────────────────────────────────────────────
          Tooltip(
            message: 'Exporter l\'onglet en PNG',
            child: IconButton(
              onPressed: _exporting ? null : _exporter,
              icon: _exporting
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  : const Icon(Icons.ios_share, color: Colors.white, size: 22),
            ),
          ),
          // Nb pronostics source
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$nbTotal courses',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              // ── Bandeau lecture seule ──────────────────────────────────────
              Container(
                width: double.infinity,
                color: Colors.teal.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
                child: const Row(children: [
                  Icon(Icons.lock_outline, color: Colors.teal, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'Lecture seule — aucune modification IA',
                    style: TextStyle(color: Colors.teal, fontSize: 14),
                  ),
                ]),
              ),
              // ── TabBar ─────────────────────────────────────────────────────
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: Colors.amber,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(fontSize: 14),
                tabs: const [
                  Tab(text: '🌐 Global'),
                  Tab(text: '🎯 Type pari'),
                  Tab(text: '💎 Value'),
                  Tab(text: '🎰 Outsiders'),
                  Tab(text: '⚠️ Faux favoris'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Filtres ────────────────────────────────────────────────────────
          _buildFiltres(),
          // ── Contenu onglets avec RepaintBoundary ───────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Chaque onglet est enveloppé dans un RepaintBoundary dédié
                // + en-tête d'export (nom onglet + filtres + date)
                _wrapExport(0, RoiTabGlobal(filters: _filters)),
                _wrapExport(1, RoiTabTypePari(filters: _filters)),
                _wrapExport(2, RoiTabValue(filters: _filters)),
                _wrapExport(3, RoiTabOutsiders(filters: _filters)),
                _wrapExport(4, RoiTabFauxFavoris(filters: _filters)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Enveloppe RepaintBoundary avec en-tête export ─────────────────────────
  Widget _wrapExport(int tabIdx, Widget child) {
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, "0")}/'
        '${now.month.toString().padLeft(2, "0")}/'
        '${now.year}  '
        '${now.hour.toString().padLeft(2, "0")}:'
        '${now.minute.toString().padLeft(2, "0")}';

    // Résumé filtres actifs
    final filtreStr = [
      '📅 ${_filters.periode}',
      if (_filters.discipline != 'Toutes') '🏇 ${_filters.discipline}',
      if (_filters.typePari   != 'Tous')   '🎯 ${_filters.typePari}',
    ].join('  •  ');

    return RepaintBoundary(
      key: _exportKeys[tabIdx],
      child: Container(
        color: _bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── En-tête visible sur l'export PNG ────────────────────────────
            Container(
              width: double.infinity,
              color: const Color(0xFF0D1B2A),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _tabTitles[tabIdx],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                  if (filtreStr.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      filtreStr,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            // ── Contenu onglet ───────────────────────────────────────────────
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  // ─── Barre de filtres ──────────────────────────────────────────────────────

  Widget _buildFiltres() {
    return Container(
      color: _card,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        // Période
        Expanded(child: _dropdownFiltre(
          value: _filters.periode,
          items: _periodes,
          label: '📅',
          onChanged: (v) => setState(() {
            _filters = _filters.copyWith(periode: v);
          }),
        )),
        const SizedBox(width: 8),
        // Discipline
        Expanded(child: _dropdownFiltre(
          value: _filters.discipline,
          items: _disciplines,
          label: '🏇',
          onChanged: (v) => setState(() {
            _filters = _filters.copyWith(discipline: v);
          }),
        )),
        const SizedBox(width: 8),
        // Type pari
        Expanded(flex: 2, child: _dropdownFiltre(
          value: _filters.typePari,
          items: _typesPari,
          label: '🎯',
          onChanged: (v) => setState(() {
            _filters = _filters.copyWith(typePari: v);
          }),
        )),
      ]),
    );
  }

  Widget _dropdownFiltre({
    required String value,
    required List<String> items,
    required String label,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1A2840),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          icon: const Icon(Icons.keyboard_arrow_down,
              color: Colors.white38, size: 18),
          items: items.map((it) => DropdownMenuItem(
            value: it,
            child: Text(it,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
