// ═══════════════════════════════════════════════════════════════════
//  COURSE DETAIL SCREEN — Détail complet d'une course + Pronostics IA
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/favori_button.dart'; // ★ v9.3
import 'package:provider/provider.dart';
import '../main.dart' show NavigationNotifier;
import '../models/zt_models.dart';
import '../services/ia_pronostic_engine.dart';
import '../services/alert_service.dart';
import '../services/data_refresh_service.dart';
import '../providers/pmu_provider.dart';
import '../widgets/bet_bottom_sheet.dart';
import '../widgets/arrivee_reelle_widget.dart';
import '../widgets/ia/ia_speech_widget.dart'; // ★ v9.85
import '../services/cote_tracker_service.dart'; // ★ v9.97
import '../services/outsider_service.dart';      // ★ v9.92


class CourseDetailScreen extends StatefulWidget {
  final ZtCourse course;
  final ZtReunion reunion;

  const CourseDetailScreen({
    super.key,
    required this.course,
    required this.reunion,
  });

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PronosticIA _pronostic;
  // fix #5 : _viewMode supprimé (réservé futur, inutilisé)

  // Timer pour mettre à jour le statut "Paris fermés" en temps réel
  Timer? _statutTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // fix #5 : _viewMode supprimé, listener conservé pour usage futur
    _tabController.addListener(() {});
    _pronostic = IaPronosticEngine.genererPronostic(
        widget.course, widget.reunion.lieu);
    // Actualisation périodique du statut (Paris ouverts → fermés au départ)
    _statutTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _statutTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _ouvrirPari() {
    // ★ Fix écran gris (v9.79.15) : CourseDetailScreen est une nouvelle route
    // (MaterialPageRoute) → les Providers du contexte parent ne sont plus dans
    // l'arbre. On les capture AVANT d'ouvrir le sheet via context.read() pour
    // forcer leur injection dans showBetSheet → identique au fix programme_screen.
    try {
      context.read<PmuProvider>();
      context.read<DataRefreshService>();
      showBetSheet(
        context,
        reunion: widget.reunion,
        course: widget.course,
        alertService: AlertService.instance,
        onBetPlaced: () {
          if (mounted) Navigator.pop(context);
          context.read<NavigationNotifier>().goToMesParis();
        },
      );
    } catch (e) {
      debugPrint('[CourseDetail] _ouvrirPari erreur : $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'ouvrir le pari — réessayez'),
            backgroundColor: Color(0xFFEF5350),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildInfoBanner(),
            // Bouton Parier — masqué si terminée, grisé si sans cote PMU
            Builder(builder: (_) {
              final courseTerminee = widget.course.heureDateTime
                  .isBefore(DateTime.now());
              final sansCote = widget.course.partants.isNotEmpty &&
                  widget.course.partants.every((p) => p.coteDecimale >= 99);
              if (!courseTerminee && !sansCote) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _ouvrirPari,
                      icon: const Icon(Icons.euro, size: 18),
                      label: const Text(
                        '💰 Parier sur cette course',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D52),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                    ),
                  ),
                );
              }
              // Cotes PMU non disponibles — bouton grisé non cliquable
              if (!courseTerminee && sansCote) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C2233),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFB74D).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB74D), size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Cotes indisponibles — Revenez 1h avant',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFFFB74D)),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag, color: Colors.white38, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Course terminée — Paris fermés',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
              );
            }),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTabIA(),
                  _buildTabClassique(),
                  _buildTabStats(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // HEADER
  // ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFF0D1B2A),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.course.nom.isNotEmpty
                      ? widget.course.nom
                      : 'Course ${widget.course.numCourse}',
                  style: const TextStyle(color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.bold),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${widget.reunion.lieu} • C${widget.course.numCourse} • ${widget.course.heure}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 14),
                ),
              ],
            ),
          ),
          if (widget.course.isQuinte)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.6)),
              ),
              child: const Text('QUINTÉ+',
                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ),
          // ★ v9.3 : Bouton favori
          FavoriButton(
            numR:       int.tryParse(widget.reunion.code.replaceAll('R', '')) ?? 1,
            numC:       widget.course.numCourse,
            nomCourse:  widget.course.nom.isNotEmpty ? widget.course.nom : 'Course \${widget.course.numCourse}',
            hippodrome: widget.reunion.lieu,
            scoreIA:    widget.course.partantsParRangIA.isNotEmpty
                ? widget.course.partantsParRangIA.first.scoreIA : 0.0,
            heure:      widget.course.heure,
            distance:   widget.course.distance,
            prix:       widget.course.prix,
            size: 26,
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // BANNER INFO COURSE
  // ──────────────────────────────────────────────────────────────────
  Widget _buildInfoBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A3A5C).withValues(alpha: 0.8),
            const Color(0xFF132035),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _infoItem('⏰', widget.course.heure, 'Départ'),
          _divider(),
          _infoItem('📏', widget.course.distance, 'Distance'),
          _divider(),
          _infoItem('💰', '${widget.course.prix}€', 'Dotation'),
          _divider(),
          _infoItem('🏇', '${widget.course.partants.length}', 'Partants'),
          _divider(),
          Flexible(child: _infoItem(widget.course.typeIcon, widget.course.type.isEmpty ? 'N/A' : widget.course.type, 'Type')),
        ],
      ),
    );
  }

  Widget _infoItem(String icon, String value, String label) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14,
            fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.4),
            fontSize: 14)),
      ],
    );
  }

  Widget _divider() => Container(width: 1, height: 36,
      color: Colors.white.withValues(alpha: 0.1));

  // ──────────────────────────────────────────────────────────────────
  // TAB BAR
  // ──────────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      color: const Color(0xFF0D1B2A),
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xFF4CAF7D),
        indicatorWeight: 2,
        labelColor: const Color(0xFF4CAF7D),
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        tabs: const [
          Tab(text: '🤖 IA'),
          Tab(text: '📋 Classique'),
          Tab(text: '📊 Stats'),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // ONGLET 1 : VUE IA (pronostics + scores)
  // ──────────────────────────────────────────────────────────────────
  Widget _buildTabIA() {
    final partantsIA = widget.course.partantsParRangIA;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Card analyse IA
        _buildAnalyseCard(),
        const SizedBox(height: 12),
        // Top 5 sélection
        _buildTop5Card(),
        const SizedBox(height: 12),
        // Tous les partants classés par IA
        _buildSectionTitle('🏅 Classement IA complet'),
        const SizedBox(height: 8),
        ...partantsIA.map((p) => _buildPartantCardIA(p)).toList(),
        // ★ v9.92 : Outsiders systématiques
        _buildOutsidersSystematiques(widget.course),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildAnalyseCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A3A5C).withValues(alpha: 0.9),
            const Color(0xFF0D2440),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('🤖', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Analyse IA Pronostic Hippique',
                    style: TextStyle(color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              _confianceIndicateur(_pronostic.confianceGlobale),
            ],
          ),
          const SizedBox(height: 12),
          Text(_pronostic.analyseTextuelle,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14, height: 1.6)),
          const SizedBox(height: 12),
          // Conseil — couleur adaptée selon la confiance (seuils unifiés)
          Builder(builder: (context) {
            final conf = _pronostic.confianceGlobale;
            final conseilColor = conf >= 80
                ? const Color(0xFF4CAF7D)   // vert — HAUTE
                : conf >= 65
                    ? const Color(0xFFFFD700) // or — BONNE
                    : conf >= 50
                        ? const Color(0xFFFFB74D) // orange — MOY.
                        : const Color(0xFFEF5350); // rouge — FAIBLE
            final conseilIcon = conf >= 80 ? '✅' : conf >= 65 ? '💡' : conf >= 50 ? '⚠️' : '🚫';
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: conseilColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: conseilColor.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Text(conseilIcon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_pronostic.conseil,
                        style: TextStyle(color: conseilColor,
                            fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            );
          }),
          // ★ v9.85 : Phrase IA contextuelle sous le conseil
          if (widget.course.partantsParRangIA.isNotEmpty) ...[
            const SizedBox(height: 8),
            IaSpeechWidget(
              score: widget.course.partantsParRangIA.first.scoreIA,
              nomCheval: widget.course.partantsParRangIA.first.nom,
              compact: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _confianceIndicateur(double confiance) {
    Color color;
    String label;
    // Seuils unifiés avec home_screen.dart pour cohérence
    if (confiance >= 80) {
      color = const Color(0xFF00C853); label = 'HAUTE';
    } else if (confiance >= 65) {
      color = const Color(0xFFFFEA00); label = 'BONNE';
    } else if (confiance >= 50) {
      color = const Color(0xFFFF6D00); label = 'MOY.';
    } else {
      color = const Color(0xFFFF1744); label = 'FAIBLE';
    }
    // ── Taille contrainte pour éviter le débordement hors écran ──
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 90),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${confiance.toInt()}%',
                style: TextStyle(color: color, fontSize: 13,
                    fontWeight: FontWeight.bold)),
            Text(label,
                style: TextStyle(color: color.withValues(alpha: 0.85),
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildTop5Card() {
    if (_pronostic.top5.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF132035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF7D).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎯 Sélection IA :',
                  style: TextStyle(color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(_pronostic.selection,
                  style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 15,
                      fontWeight: FontWeight.w800, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 10),
          // Podium visual
          Row(
            children: _pronostic.top5.take(5).toList().asMap().entries.map((e) {
              final idx = e.key;
              final p = e.value;
              return _buildPodiumItem(p, idx);
            }).toList(),
          ),
          // ── Arrivée réelle PMU ──
          Builder(builder: (_) {
            final isTerminee = widget.course.heureDateTime
                .isBefore(DateTime.now().subtract(const Duration(minutes: 90)));
            final courseKey = buildCourseKey(
              reunionCode: widget.reunion.code,
              numCourse: widget.course.numCourse,
              dateStr: widget.course.dateStr,
            );
            final selIA = widget.course.partantsParRangIA
                .take(5)
                .map((p) => p.numero)
                .toList();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ArriveReelleWidget(
                courseKey: courseKey,
                isTerminee: isTerminee,
                heureDepart: widget.course.heureDateTime, // ★ v9.6
                selectionIA: selIA,
                compact: false,
              ),
            );
          }),
          // Pronostic ZT officiel
          if (widget.course.pronosticZt.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('📊 Pronostic PMU : ',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14)),
                ...widget.course.pronosticZt.map((n) => Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B68EE).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFF7B68EE).withValues(alpha: 0.5)),
                  ),
                  child: Text('$n',
                      style: const TextStyle(color: Color(0xFF7B68EE),
                          fontSize: 14, fontWeight: FontWeight.bold)),
                )),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPodiumItem(ZtPartant p, int idx) {
    final colors = [
      const Color(0xFFFFD700), // Or
      const Color(0xFFC0C0C0), // Argent
      const Color(0xFFCD7F32), // Bronze
      const Color(0xFF4CAF7D), // Vert
      const Color(0xFF80DEEA), // Cyan
    ];
    final medals = ['🥇', '🥈', '🥉', '4️⃣', '5️⃣'];
    final color = idx < colors.length ? colors[idx] : Colors.white38;
    final medal = idx < medals.length ? medals[idx] : '${idx + 1}';

    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(medal, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text(p.numero,
                style: TextStyle(color: color, fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(p.nom, style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center, maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              height: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: p.scoreIA / 100,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text('${p.scoreIA.toInt()}',
                style: TextStyle(color: color, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildPartantCardIA(ZtPartant p) {
    final scoreColor = Color(IaPronosticEngine.scoreColor(p.scoreIA));
    final labelColor = Color(IaPronosticEngine.labelColor(p.labelIA));
    final isTop3 = p.rang <= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isTop3
            ? const Color(0xFF1A3A5C).withValues(alpha: 0.5)
            : const Color(0xFF132035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTop3
              ? scoreColor.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Rang IA
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
                ),
                child: Center(
                  child: Text('${p.rang}',
                      style: TextStyle(color: scoreColor, fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              // Numéro dossard
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF7D).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(p.numero,
                      style: const TextStyle(color: Color(0xFF4CAF7D),
                          fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              // Nom + driver
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nom,
                        style: const TextStyle(color: Colors.white,
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    if (p.driver.isNotEmpty)
                      Text(p.driver,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 14)),
                  ],
                ),
              ),
              // Score IA
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${p.scoreIA.toInt()}',
                      style: TextStyle(color: scoreColor, fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  Text('/ 100', style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
                ],
              ),
            ],
          ),
          // Barre de score
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 42),
              Expanded(
                child: Stack(
                  children: [
                    Container(height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(3),
                        )),
                    FractionallySizedBox(
                      widthFactor: p.scoreIA / 100,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            scoreColor.withValues(alpha: 0.7),
                            scoreColor,
                          ]),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Label IA
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: labelColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: labelColor.withValues(alpha: 0.4)),
                ),
                child: Text(p.labelIA,
                    style: TextStyle(color: labelColor, fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          // ★ v9.93 — Mouvement de cote (critère R) — affichage complet
          Builder(builder: (_) {
            final courseKey = buildCourseKey(
              reunionCode: widget.reunion.code,
              numCourse:   widget.course.numCourse,
              dateStr:     widget.course.dateStr,
            );
            final dansFenetre = CoteTrackerService.instance.estDansFenetre(widget.course);
            final mouv = CoteTrackerService.instance.mouvementPourPartant(courseKey, p.numero);

            // Hors fenêtre — afficher le compte à rebours si < 90 min
            if (!dansFenetre) {
              final diff = widget.course.heureDateTime.difference(DateTime.now()).inMinutes;
              if (diff > 30 && diff <= 90) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    const SizedBox(width: 42),
                    Text('📊 Mvt cote actif dans ${diff - 30} min',
                        style: const TextStyle(color: Colors.white24, fontSize: 11)),
                  ]),
                );
              }
              return const SizedBox.shrink();
            }

            // Dans la fenêtre — pas encore de données
            if (mouv == null) {
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const SizedBox(width: 42),
                  const Text('📊 Surveillance cote active…',
                      style: TextStyle(color: Colors.white24, fontSize: 11)),
                ]),
              );
            }

            // Mouvement stable
            if (mouv.categorie == 'stable') {
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const SizedBox(width: 42),
                  Text('→ Cote ${mouv.coteCourante.toStringAsFixed(1)} (stable)',
                      style: const TextStyle(color: Colors.white24, fontSize: 11)),
                ]),
              );
            }

            // Mouvement significatif — affichage complet avec flèche + delta
            final isHausse = mouv.variationPct > 0;
            final couleur  = !isHausse ? const Color(0xFF4CAF7D) : const Color(0xFFEF5350);
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const SizedBox(width: 42),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: couleur.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: couleur.withValues(alpha: 0.45)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(mouv.emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 5),
                    Text(
                      '${mouv.coteDebut.toStringAsFixed(1)} → ${mouv.coteCourante.toStringAsFixed(1)}',
                      style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: couleur.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(mouv.deltaStr,
                          style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(_libelleMouvement(mouv.categorie),
                      style: TextStyle(color: couleur.withValues(alpha: 0.8), fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            );
          }),
          // Explication
          if (p.explicationIA.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 42),
                Expanded(
                  child: Text(p.explicationIA,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13, height: 1.4),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
          // ★ v9.93 : Place au départ
          if (p.placeDepartInt > 0) ...[
            const SizedBox(height: 6),
            Row(children: [
              const SizedBox(width: 42),
              Builder(builder: (ctx) {
                final course = widget.course;
                final isTrot = course.type.toLowerCase().contains('trot') ||
                    course.type.toLowerCase().contains('attele');
                final distM  = int.tryParse(
                    course.distance.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                final isLongue = distM >= 2200;
                final isFavorable = isTrot &&
                    (isLongue ? p.placeDepartInt <= 6 : p.placeDepartInt <= 4);
                final color = isFavorable
                    ? const Color(0xFF4CAF7D)
                    : p.placeDepartInt > 9 && isTrot
                        ? Colors.redAccent.withValues(alpha: 0.8)
                        : Colors.white38;
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('🏁 Place ${p.placeDepartInt}',
                      style: TextStyle(color: color, fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  if (isTrot && isFavorable) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF7D).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Bonne corde',
                          style: TextStyle(color: Color(0xFF4CAF7D), fontSize: 10)),
                    ),
                  ],
                ]);
              }),
            ]),
          ],
          // Musique
          if (p.musique.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: 42),
                Text('Forme : ',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 13)),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _parseMusiqueWidgets(p.musique),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _libelleMouvement(String categorie) {
    switch (categorie) {
      case 'effondrement':  return 'Effondrement de cote';
      case 'forte_baisse':  return 'Forte baisse';
      case 'baisse':        return 'Baisse';
      case 'forte_hausse':  return 'Forte hausse';
      case 'hausse':        return 'Hausse';
      case 'legere_hausse': return 'Légère hausse';
      default:              return '';
    }
  }

  List<Widget> _parseMusiqueWidgets(String musique) {
    final positions = musique.trim().split(RegExp(r'\s+'));
    return positions.take(8).map((pos) {
      Color color;
      if (pos.startsWith('1')) color = const Color(0xFF00C853);
      else if (pos.startsWith('2')) color = const Color(0xFF64DD17);
      else if (pos.startsWith('3')) color = const Color(0xFFFFD600);
      else if (pos.startsWith('Da') || pos.startsWith('Dm') || pos.startsWith('0')) {
        color = const Color(0xFFFF1744);
      }
      else {
        final num = int.tryParse(pos.replaceAll(RegExp(r'[^\d]'), '')) ?? 99;
        if (num <= 5) color = const Color(0xFFFF9100);
        else color = Colors.white38;
      }
      return Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
        ),
        child: Text(pos, style: TextStyle(color: color, fontSize: 13,
            fontWeight: FontWeight.w600)),
      );
    }).toList();
  }

  // ──────────────────────────────────────────────────────────────────
  // ONGLET 2 : VUE CLASSIQUE (tous les partants)
  // ──────────────────────────────────────────────────────────────────
  Widget _buildTabClassique() {
    final partants = [...widget.course.partants]
      ..sort((a, b) => a.numInt.compareTo(b.numInt));

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildSectionTitle('🐎 Tous les partants (${partants.length})'),
        const SizedBox(height: 8),
        ...partants.map((p) => _buildPartantCardClassique(p)).toList(),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildPartantCardClassique(ZtPartant p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF132035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Numéro
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF1A3A5C),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(p.numero,
                  style: const TextStyle(color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          // Infos principales
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nom, style: const TextStyle(color: Colors.white,
                    fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (p.driver.isNotEmpty) ...[
                      const Icon(Icons.person, color: Color(0xFF80DEEA), size: 12),
                      const SizedBox(width: 3),
                      Text(p.driver,
                          style: const TextStyle(color: Color(0xFF80DEEA),
                              fontSize: 14)),
                      const SizedBox(width: 8),
                    ],
                    if (p.entraineur.isNotEmpty) ...[
                      const Icon(Icons.sports, color: Color(0xFFCE93D8), size: 12),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(p.entraineur,
                            style: const TextStyle(color: Color(0xFFCE93D8),
                                fontSize: 14),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // Musique colorée
                if (p.musique.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: _parseMusiqueWidgets(p.musique)),
                  ),
              ],
            ),
          ),
          // Stats droite
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (p.gains.isNotEmpty && p.gains != '-')
                Text('${p.gains}€',
                    style: const TextStyle(color: Color(0xFF4CAF7D),
                        fontSize: 14, fontWeight: FontWeight.bold)),
              if (p.record.isNotEmpty)
                Text(p.record,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 14)),
              if (p.cote.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
                  ),
                  child: Text(p.cote,
                      style: const TextStyle(color: Color(0xFFFFD700),
                          fontSize: 14, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // ONGLET 3 : STATS
  // ──────────────────────────────────────────────────────────────────
  Widget _buildTabStats() {
    final partants = widget.course.partants;
    if (partants.isEmpty) {
      return const Center(child: Text('Pas de données',
          style: TextStyle(color: Colors.white38)));
    }

    // Calcul stats
    final avecGains = partants.where((p) => p.gainsInt > 0).toList();
    final avecRecord = partants.where((p) => p.record.isNotEmpty).toList();

    // Top gagnants (par gains)
    final topGains = [...avecGains]
      ..sort((a, b) => b.gainsInt.compareTo(a.gainsInt));

    // Top records (meilleur temps)
    final topRecord = [...avecRecord]
      ..sort((a, b) => a.recordEnSecondes.compareTo(b.recordEnSecondes));

    // Distribution des positions
    final allPositions = <int>[];
    for (final p in partants) {
      final positions = RegExp(r'\b(\d+)[amph]\b').allMatches(p.musique);
      for (final m in positions.take(5)) {
        final pos = int.tryParse(m.group(1) ?? '') ?? 0;
        if (pos > 0) allPositions.add(pos);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Distribution scores IA
        _buildSectionTitle('📊 Distribution scores IA'),
        const SizedBox(height: 8),
        _buildIADistributionChart(),
        const SizedBox(height: 16),
        // Top gains
        if (topGains.isNotEmpty) ...[
          _buildSectionTitle('💰 Gains carrière (top 5)'),
          const SizedBox(height: 8),
          _buildGainsChart(topGains.take(5).toList()),
          const SizedBox(height: 16),
        ],
        // Top records
        if (topRecord.isNotEmpty) ...[
          _buildSectionTitle('⏱️ Meilleurs records'),
          const SizedBox(height: 8),
          ...topRecord.take(5).map((p) => _buildRecordRow(p, topRecord[0])).toList(),
          const SizedBox(height: 16),
        ],
        // Forme générale
        _buildSectionTitle('🎵 Analyse de forme (musique)'),
        const SizedBox(height: 8),
        _buildFormeGlobale(),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildIADistributionChart() {
    final partants = widget.course.partantsParRangIA;
    final maxScore = partants.isNotEmpty
        ? partants.map((p) => p.scoreIA).reduce((a, b) => a > b ? a : b)
        : 100.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF132035),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: partants.take(8).map((p) {
          final color = Color(IaPronosticEngine.scoreColor(p.scoreIA));
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(width: 22,
                    child: Text(p.numero,
                        style: TextStyle(color: color, fontSize: 14,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.right)),
                const SizedBox(width: 8),
                SizedBox(width: 80,
                    child: Text(p.nom, style: const TextStyle(
                        color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Expanded(
                  child: Stack(
                    children: [
                      Container(height: 18,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(4),
                          )),
                      FractionallySizedBox(
                        widthFactor: maxScore > 0 ? p.scoreIA / maxScore : 0,
                        child: Container(
                          height: 18,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text('${p.scoreIA.toInt()}',
                                style: TextStyle(color: color, fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGainsChart(List<ZtPartant> partants) {
    final maxGains = partants.isNotEmpty
        ? partants.map((p) => p.gainsInt).reduce((a, b) => a > b ? a : b)
        : 1;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF132035),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: partants.map((p) {
          final ratio = maxGains > 0 ? p.gainsInt / maxGains : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A3A5C),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(child: Text(p.numero,
                      style: const TextStyle(color: Colors.white, fontSize: 13))),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: Text(p.nom,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Expanded(
                  child: Stack(
                    children: [
                      Container(height: 18,
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(4))),
                      FractionallySizedBox(
                        widthFactor: ratio,
                        child: Container(
                          height: 18,
                          decoration: BoxDecoration(
                              color: const Color(0xFF4CAF7D).withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('${p.gains}€',
                    style: const TextStyle(color: Color(0xFF4CAF7D), fontSize: 13)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecordRow(ZtPartant p, ZtPartant best) {
    final isBest = p.numero == best.numero;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isBest
            ? const Color(0xFF4CAF7D).withValues(alpha: 0.15)
            : const Color(0xFF132035),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isBest
              ? const Color(0xFF4CAF7D).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          if (isBest)
            const Text('⚡ ', style: TextStyle(fontSize: 14))
          else
            const SizedBox(width: 18),
          Text(p.numero,
              style: TextStyle(
                  color: isBest ? const Color(0xFF4CAF7D) : Colors.white54,
                  fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(p.nom,
              style: const TextStyle(color: Colors.white, fontSize: 14))),
          Text(p.record,
              style: TextStyle(
                  color: isBest ? const Color(0xFF4CAF7D) : Colors.white54,
                  fontSize: 13, fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildFormeGlobale() {
    final partants = widget.course.partants;
    int nbBonneForme = 0;
    int nbMoyenne = 0;
    int nbMauvaise = 0;

    for (final p in partants) {
      final score = p.scoreForme;
      if (score >= 60) nbBonneForme++;
      else if (score >= 35) nbMoyenne++;
      else nbMauvaise++;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF132035),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _formeItem('🟢 Bonne forme', nbBonneForme, const Color(0xFF00C853)),
              _formeItem('🟡 Moyenne', nbMoyenne, const Color(0xFFFFD600)),
              _formeItem('🔴 Mauvaise', nbMauvaise, const Color(0xFFFF1744)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  if (nbBonneForme > 0) Flexible(
                    flex: nbBonneForme,
                    child: Container(color: const Color(0xFF00C853)),
                  ),
                  if (nbMoyenne > 0) Flexible(
                    flex: nbMoyenne,
                    child: Container(color: const Color(0xFFFFD600)),
                  ),
                  if (nbMauvaise > 0) Flexible(
                    flex: nbMauvaise,
                    child: Container(color: const Color(0xFFFF1744)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formeItem(String label, int count, Color color) {
    return Column(
      children: [
        Text('$count', style: TextStyle(color: color, fontSize: 22,
            fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: color.withValues(alpha: 0.7),
            fontSize: 13), textAlign: TextAlign.center),
      ],
    );
  }

  // ★ v9.92 POINT 3 : Outsiders systématiques ────────────────────────────────
  Widget _buildOutsidersSystematiques(ZtCourse course) {
    final outsiders = OutsiderService.instance.detecterDansCourse(course);
    if (outsiders.isEmpty) return const SizedBox();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      _buildSectionTitle('💎 Outsiders systématiques'),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Ces chevaux ont un bon niveau ELO mais une cote élevée. '
            'Le marché les sous-estime systématiquement — ce sont '
            'les paris potentiellement les plus rentables.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          ...outsiders.map((o) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('💎', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(o.nomCheval,
                        style: const TextStyle(color: Colors.white,
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(o.label.split(' ').skip(1).join(' '),
                          style: const TextStyle(color: Color(0xFFFFD700),
                              fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                    'ELO ${o.eloRating.toStringAsFixed(0)} · '
                    'Cote ×${o.coteMoyenne.toStringAsFixed(1)} · '
                    'Top3 ${(o.tauxTop3 * 100).toStringAsFixed(0)}% '
                    '(${o.nbCourses} courses)',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              )),
              // Score d'opportunité
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${o.scoreOpportunite.toStringAsFixed(0)}',
                    style: const TextStyle(color: Color(0xFFFFD700),
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const Text('/100', style: TextStyle(color: Colors.white24, fontSize: 10)),
              ]),
            ]),
          )),
        ]),
      ),
    ]);
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(color: Colors.white, fontSize: 14,
            fontWeight: FontWeight.bold));
  }
}
