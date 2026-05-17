// ══════════════════════════════════════════════════════════════════════════════
//  roi_value_screen.dart — Écran ROI / Value Analytics
//  ★ v10.46 — Module 100% LECTURE SEULE
//  ★ v10.47 — Export PNG (RepaintBoundary + SharePlus)
//  ★ v10.48 — Export PNG complet (offscreen rendering — contenu intégral)
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

  // Couleur en-tête export
  static const _exportBg = Color(0xFF0D1B2A);

  late TabController _tabController;
  RoiValueFilters _filters = const RoiValueFilters();

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

  // ─── Construit le widget de contenu pour l'onglet donné ───────────────────
  Widget _buildTabContent(int idx) {
    switch (idx) {
      case 0: return RoiTabGlobal(filters: _filters);
      case 1: return RoiTabTypePari(filters: _filters);
      case 2: return RoiTabValue(filters: _filters);
      case 3: return RoiTabOutsiders(filters: _filters);
      case 4: return RoiTabFauxFavoris(filters: _filters);
      default: return const SizedBox.shrink();
    }
  }

  // ─── Export PNG complet — offscreen rendering ★ v10.48 ───────────────────
  //
  //  Technique :
  //  1. Construire le contenu complet dans un widget offscreen
  //     (largeur = largeur écran, hauteur libre → IntrinsicHeight)
  //  2. Le monter via Overlay pour forcer le layout Flutter
  //  3. Attendre le rendu (2 frames)
  //  4. Capturer via RenderRepaintBoundary.toImage()
  //  5. Démonter l'overlay → partager via SharePlus
  //
  Future<void> _exporter() async {
    if (_exporting) return;
    setState(() => _exporting = true);

    OverlayEntry? overlayEntry;

    try {
      final tabIdx   = _tabController.index;
      final label    = _tabLabels[tabIdx];
      final title    = _tabTitles[tabIdx];
      final now      = DateTime.now();
      final dateStr  = '${now.day.toString().padLeft(2, "0")}/'
          '${now.month.toString().padLeft(2, "0")}/${now.year}  '
          '${now.hour.toString().padLeft(2, "0")}:'
          '${now.minute.toString().padLeft(2, "0")}';
      final filtreStr = [
        '📅 ${_filters.periode}',
        if (_filters.discipline != 'Toutes') '🏇 ${_filters.discipline}',
        if (_filters.typePari   != 'Tous')   '🎯 ${_filters.typePari}',
      ].join('  •  ');

      // Largeur de capture = largeur de l'écran courant
      final screenW = MediaQuery.of(context).size.width;
      final repaintKey = GlobalKey();

      // ── Widget offscreen complet ─────────────────────────────────────────
      // Positionné hors écran (left: -screenW * 2) → invisible mais rendu
      overlayEntry = OverlayEntry(
        builder: (_) => Positioned(
          left:  -screenW * 2,   // hors écran
          top:   0,
          width: screenW,
          child: RepaintBoundary(
            key: repaintKey,
            child: Material(
              color: _bg,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── En-tête export ──────────────────────────────────────
                  Container(
                    width: double.infinity,
                    color: _exportBg,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '📈 ROI / Value — $title',
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
                          const SizedBox(height: 4),
                          Text(
                            filtreStr,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '🔒 Lecture seule — Pronostic Hippique',
                            style: TextStyle(
                                color: Colors.teal, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Contenu onglet complet (non scrollable) ─────────────
                  // On extrait le contenu réel en remplaçant ListView par Column
                  _OffscreenTabContent(
                    tabIndex: tabIdx,
                    filters: _filters,
                    backgroundColor: _bg,
                    cardColor:       _card,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Monter l'overlay
      if (!mounted) return;
      Overlay.of(context).insert(overlayEntry);

      // Attendre 2 frames : layout + paint
      await Future.delayed(const Duration(milliseconds: 100));
      // ignore: use_build_context_synchronously
      await null; // microtask flush
      await Future.delayed(const Duration(milliseconds: 150));

      // Capturer
      final boundary = repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur : rendu non disponible.')));
        }
        return;
      }

      final image    = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final dir   = await getTemporaryDirectory();
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
      overlayEntry?.remove();
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
            message: 'Exporter contenu complet en PNG',
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
          _buildFiltres(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabContent(0),
                _buildTabContent(1),
                _buildTabContent(2),
                _buildTabContent(3),
                _buildTabContent(4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Barre de filtres ──────────────────────────────────────────────────────

  Widget _buildFiltres() {
    return Container(
      color: _card,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Expanded(child: _dropdownFiltre(
          value: _filters.periode,
          items: _periodes,
          label: '📅',
          onChanged: (v) => setState(() {
            _filters = _filters.copyWith(periode: v);
          }),
        )),
        const SizedBox(width: 8),
        Expanded(child: _dropdownFiltre(
          value: _filters.discipline,
          items: _disciplines,
          label: '🏇',
          onChanged: (v) => setState(() {
            _filters = _filters.copyWith(discipline: v);
          }),
        )),
        const SizedBox(width: 8),
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

// ══════════════════════════════════════════════════════════════════════════════
//  _OffscreenTabContent — rendu complet non-scrollable pour export PNG
//  ★ v10.48 — chaque onglet expose son contenu via _buildItems()
//
//  Principe : les widgets ROI retournent un ListView(children:[...]).
//  Pour l'export on récupère les mêmes items dans un Column
//  (pas de scroll → contenu intégral capturé).
// ══════════════════════════════════════════════════════════════════════════════

class _OffscreenTabContent extends StatelessWidget {
  final int tabIndex;
  final RoiValueFilters filters;
  final Color backgroundColor;
  final Color cardColor;

  const _OffscreenTabContent({
    required this.tabIndex,
    required this.filters,
    required this.backgroundColor,
    required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildItems(),
      ),
    );
  }

  List<Widget> _buildItems() {
    switch (tabIndex) {
      case 0: return _itemsGlobal();
      case 1: return _itemsTypePari();
      case 2: return _itemsValue();
      case 3: return _itemsOutsiders();
      case 4: return _itemsFauxFavoris();
      default: return [];
    }
  }

  // ─── Onglet 0 : Vue globale ───────────────────────────────────────────────
  List<Widget> _itemsGlobal() {
    final summary = RoiValueService.instance.calculerResume(filters);
    final parDisc = RoiValueService.instance.roiParDiscipline(filters);

    if (summary.nbCourses == 0) {
      return [_vide('Aucun pronostic avec résultat\npour les filtres sélectionnés.')];
    }

    return [
      _carteRoiGlobal(summary),
      const SizedBox(height: 16),
      _sectionTitle('📊 ROI par discipline'),
      const SizedBox(height: 8),
      ...parDisc.map((g) => _ligneDisc(g)),
      const SizedBox(height: 24),
      _noteBasPage('💡 ROI calculé sur mise virtuelle de 1 € par pari.\n'
          'Seuls les pronostics avec cote PMU disponible sont inclus.'),
    ];
  }

  Widget _carteRoiGlobal(RoiSummary s) {
    const gold     = Color(0xFFFFD700);
    final roiColor  = s.roi  >= 0 ? Colors.greenAccent : Colors.redAccent;
    final gainColor = s.gainNet >= 0 ? Colors.greenAccent : Colors.redAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (s.roi >= 0 ? Colors.greenAccent : Colors.redAccent)
              .withValues(alpha: 0.35),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('ROI global',
              style: TextStyle(color: Colors.white70, fontSize: 16)),
          Text(
            '${s.roi >= 0 ? '+' : ''}${s.roi.toStringAsFixed(1)}%',
            style: TextStyle(color: roiColor, fontSize: 26,
                fontWeight: FontWeight.bold),
          ),
        ]),
        const Divider(color: Colors.white12, height: 20),
        _grille2col([
          _stat('Paris ROI',     '${s.nbParisRoi}',          Colors.white),
          _stat('Gain net',
              '${s.gainNet >= 0 ? '+' : ''}${s.gainNet.toStringAsFixed(2)} €',
              gainColor),
          _stat('Gagnants',      '${s.gagnants}',            Colors.greenAccent),
          _stat('Perdants',      '${s.perdants}',            Colors.redAccent),
          _stat('Taux réussite', '${s.tauxReussite.toStringAsFixed(1)}%', Colors.white70),
          _stat('Cote moy. G',
              s.coteMoyenneGagnants > 0
                  ? s.coteMoyenneGagnants.toStringAsFixed(2) : '—',
              gold),
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
              Text(
                '${s.outsidersGagnants} outsider(s) gagnant(s) — cote ≥ 8.0',
                style: const TextStyle(color: Colors.amber, fontSize: 14),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _ligneDisc(RoiByGroup g) {
    final s       = g.summary;
    final roiColor = s.roi >= 0 ? Colors.greenAccent : Colors.redAccent;
    final emoji   = g.label == 'Plat' ? '🏇'
                  : g.label == 'Trot' ? '🐎' : '🏔️';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardColor,
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
        else
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${s.nbParisRoi} paris',
                style: const TextStyle(color: Colors.white54, fontSize: 14)),
            Text(
              '${s.roi >= 0 ? '+' : ''}${s.roi.toStringAsFixed(1)}%',
              style: TextStyle(color: roiColor, fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ]),
      ]),
    );
  }

  // ─── Onglet 1 : Type de pari ──────────────────────────────────────────────
  List<Widget> _itemsTypePari() {
    final groupes = RoiValueService.instance.roiParTypePari(filters);
    final avecDonnees = groupes.where((g) => g.summary.nbParisRoi > 0).toList();
    if (avecDonnees.isEmpty) {
      return [_vide('Aucune donnée disponible.\nEnregistrez des résultats pour voir le ROI par type.')];
    }
    return [
      _headerTypePari(),
      const SizedBox(height: 8),
      ...groupes.map((g) => _ligneType(g)),
      const SizedBox(height: 16),
      _noteBasPage('💡 Mise virtuelle 1 € par pari. '
          'Seuls les types avec cote PMU disponible sont inclus dans le ROI.'),
    ];
  }

  Widget _headerTypePari() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    child: Row(children: const [
      Expanded(flex: 3, child: Text('Type',     style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold))),
      Expanded(flex: 1, child: Text('Nb',       style: TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center)),
      Expanded(flex: 2, child: Text('Réussite', style: TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.center)),
      Expanded(flex: 2, child: Text('ROI',      style: TextStyle(color: Colors.white54, fontSize: 14), textAlign: TextAlign.right)),
    ]),
  );

  Widget _ligneType(RoiByGroup g) {
    final s        = g.summary;
    final roiColor = s.nbParisRoi == 0 ? Colors.white24
        : s.roi >= 0 ? Colors.greenAccent : Colors.redAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(flex: 3,
            child: Text(g.label,
                style: const TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(flex: 1,
            child: Text(s.nbParisRoi == 0 ? '—' : '${s.nbParisRoi}',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center),
          ),
          Expanded(flex: 2,
            child: Text(s.nbParisRoi == 0 ? '—'
                : '${s.tauxReussite.toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center),
          ),
          Expanded(flex: 2,
            child: Text(
              s.nbParisRoi == 0 ? 'N/A'
                  : '${s.roi >= 0 ? '+' : ''}${s.roi.toStringAsFixed(1)}%',
              style: TextStyle(color: roiColor, fontSize: 16,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ]),
        if (s.nbParisRoi > 0) ...[
          const SizedBox(height: 6),
          Row(children: [
            Text(
              'Gain net : ${s.gainNet >= 0 ? '+' : ''}${s.gainNet.toStringAsFixed(2)} €',
              style: TextStyle(
                  color: s.gainNet >= 0 ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 14),
            ),
            const SizedBox(width: 16),
            if (s.coteMoyenneGagnants > 0)
              Text('Cote moy. : ${s.coteMoyenneGagnants.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.amber, fontSize: 14)),
          ]),
        ],
      ]),
    );
  }

  // ─── Onglet 2 : Value ─────────────────────────────────────────────────────
  List<Widget> _itemsValue() {
    final values = RoiValueService.instance.detecterValue(filters);
    if (values.isEmpty) {
      return [_vide('🔍 Aucune value détectée\n\n'
          'Critères : score IA ≥ 70 + cote ≥ 5.0 + divergence ≥ 60')];
    }
    final gagnees = values.where((v) => v.gagne).length;
    final tx      = gagnees / values.length * 100;
    return [
      _bandeauResume3(values.length, gagnees, tx),
      const SizedBox(height: 12),
      ...values.map((v) => _carteValue(v)),
      const SizedBox(height: 16),
      _noteBasPage('💡 Une "value" est détectée quand l\'IA est fortement optimiste '
          '(score ≥ 70) sur un cheval que le marché sous-cote '
          '(cote ≥ 5, divergence ≥ 60).'),
    ];
  }

  Widget _bandeauResume3(int total, int gagnees, double tx) {
    const purple = Color(0xFF9C27B0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: purple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: purple.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _mini('Détectées', '$total',   Colors.white),
        _mini('Validées',  '$gagnees', Colors.greenAccent),
        _mini('Taux', '${tx.toStringAsFixed(0)}%',
            tx >= 30 ? Colors.greenAccent : Colors.orange),
      ]),
    );
  }

  Widget _carteValue(ValueOpportunity v) {
    const purple = Color(0xFF9C27B0);
    final couleur = v.gagne ? Colors.greenAccent : Colors.redAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (v.gagne ? Colors.greenAccent : Colors.white12)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(v.date, style: const TextStyle(color: Colors.white54, fontSize: 14),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          _chip(v.discipline, Colors.white24),
          const SizedBox(width: 6),
          Text(v.gagne ? '✅' : '❌', style: const TextStyle(fontSize: 16)),
        ]),
        const SizedBox(height: 6),
        Text(v.courseNom,
            style: const TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w600),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8, runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _chip(v.typePari, purple.withValues(alpha: 0.4)),
            Text('N°${v.favoriIa}',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12, runSpacing: 8,
          children: [
            _kv('Score IA', '${v.scoreIa.toStringAsFixed(0)}',   Colors.amber),
            _kv('Cote',     v.cote.toStringAsFixed(1),           Colors.white70),
            _kv('Diverg.',  '${v.divergence.toStringAsFixed(0)}', purple),
            if (v.gagne)
              _kv('Retour', '+${v.retour.toStringAsFixed(2)} €', couleur),
          ],
        ),
        const SizedBox(height: 6),
        Text(v.explication,
            style: TextStyle(color: couleur.withValues(alpha: 0.8), fontSize: 14),
            maxLines: 3, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  // ─── Onglet 3 : Outsiders ─────────────────────────────────────────────────
  List<Widget> _itemsOutsiders() {
    final outsiders = RoiValueService.instance.analyserOutsiders(filters);
    if (outsiders.isEmpty) {
      return [_vide('🎰 Aucun outsider rentable détecté\n\n'
          'Critères : cote ≥ 8.0 + arrivé dans le top 3 réel')];
    }
    final detectes = outsiders.where((o) => o.detecteParIa).length;
    final ratesPct = (outsiders.length - detectes) / outsiders.length * 100;
    return [
      _bandeauOutsiders(outsiders.length, detectes, ratesPct),
      const SizedBox(height: 12),
      ...outsiders.map((o) => _carteOutsider(o)),
      const SizedBox(height: 16),
      _noteBasPage('💡 Outsider = cheval avec cote ≥ 8.0 arrivé dans le top 3 réel.\n'
          'Détecté = présent dans le top 5 IA au moment du pronostic.'),
    ];
  }

  Widget _bandeauOutsiders(int total, int detectes, double ratesPct) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _mini('Total',       '$total',    Colors.white),
        _mini('Détectés IA', '$detectes', Colors.greenAccent),
        _mini('Ratés', '${ratesPct.toStringAsFixed(0)}%',
            ratesPct > 50 ? Colors.redAccent : Colors.orange),
      ]),
    );
  }

  Widget _carteOutsider(OutsiderAnalyse o) {
    final couleur   = o.detecteParIa ? Colors.greenAccent : Colors.redAccent;
    final rangIaStr = o.rangIa == 0   ? 'Non classé' : 'Rang IA : ${o.rangIa}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(o.date, style: const TextStyle(color: Colors.white54, fontSize: 14),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          _chip(o.discipline, Colors.white12),
          const SizedBox(width: 6),
          Text(o.detecteParIa ? '✅ Vu' : '❌ Raté',
              style: TextStyle(color: couleur, fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        Text(o.courseNom,
            style: const TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w600),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16, runSpacing: 8,
          children: [
            _kv('N°',        o.numero,                  Colors.amber),
            _kv('Cote',      o.cote.toStringAsFixed(1), Colors.amber),
            _kv('Rang réel', '${o.rangReel}ème',        Colors.white70),
            _kv('IA',        rangIaStr,                 couleur),
          ],
        ),
        const SizedBox(height: 6),
        Text(o.commentaire,
            style: TextStyle(color: couleur.withValues(alpha: 0.8), fontSize: 14),
            maxLines: 3, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  // ─── Onglet 4 : Faux favoris ──────────────────────────────────────────────
  List<Widget> _itemsFauxFavoris() {
    final fauxFav = RoiValueService.instance.detecterFauxFavoris(filters);
    if (fauxFav.isEmpty) {
      return [_vide('✅ Aucun faux favori détecté\n\n'
          'Critères : confiance IA ≥ 80 + pari perdant')];
    }
    final confMoy = fauxFav.map((f) => f.confianceIa).reduce((a, b) => a + b)
        / fauxFav.length;
    return [
      _bandeauFauxFav(fauxFav.length, confMoy),
      const SizedBox(height: 12),
      ...fauxFav.map((f) => _carteFauxFavori(f)),
      const SizedBox(height: 16),
      _noteBasPage('💡 Faux favori IA = confiance prédite ≥ 80% mais pari non validé.\n'
          'Permet d\'identifier les situations où l\'IA sur-estime ses chances.'),
    ];
  }

  Widget _bandeauFauxFav(int total, double confMoy) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _mini('Faux favoris', '$total',                      Colors.redAccent),
        _mini('Conf. moy.',   '${confMoy.toStringAsFixed(0)}%', Colors.orange),
      ]),
    );
  }

  Widget _carteFauxFavori(FauxFavoriIa f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(f.date, style: const TextStyle(color: Colors.white54, fontSize: 14),
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
        Text(f.courseNom,
            style: const TextStyle(color: Colors.white, fontSize: 16,
                fontWeight: FontWeight.w600),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        _chip(f.typePari, Colors.deepPurple.withValues(alpha: 0.4)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16, runSpacing: 8,
          children: [
            _kv('N°',       f.favoriIa, Colors.orange),
            _kv('Confiance', '${f.confianceIa.toStringAsFixed(0)}%',
                f.confianceIa >= 90 ? Colors.redAccent : Colors.orange),
            _kv('Cote', f.cote > 0 ? f.cote.toStringAsFixed(1) : '—',
                Colors.white70),
          ],
        ),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.info_outline, color: Colors.white38, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(f.raisonProbable,
                style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ),
        ]),
      ]),
    );
  }

  // ─── Helpers communs ──────────────────────────────────────────────────────

  Widget _grille2col(List<Widget> items) {
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

  Widget _stat(String label, String value, Color valueColor) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 14)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(color: valueColor, fontSize: 18,
          fontWeight: FontWeight.bold)),
    ]);

  Widget _mini(String label, String value, Color color) =>
    Column(children: [
      Text(value, style: TextStyle(color: color, fontSize: 20,
          fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
    ]);

  Widget _chip(String label, Color bg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
  );

  Widget _kv(String label, String value, Color color) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
      Text(value, style: TextStyle(color: color, fontSize: 16,
          fontWeight: FontWeight.bold)),
    ]);

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(color: Colors.white, fontSize: 18,
          fontWeight: FontWeight.bold));

  Widget _noteBasPage(String msg) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(msg,
        style: const TextStyle(color: Colors.white38, fontSize: 14)),
  );

  Widget _vide(String msg) => Padding(
    padding: const EdgeInsets.all(32),
    child: Text(msg, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white38, fontSize: 16)),
  );
}
