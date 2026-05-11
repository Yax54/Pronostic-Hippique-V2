// ═══════════════════════════════════════════════════════════════════════════
//  PARIS DETAIL SCREEN — Détail complet d'un pari suivi v1.0
//  Charge les données ZoneTurf en temps réel et affiche :
//   • Infos course (hippodrome, distance, type, dotation)
//   • Pronostic IA avec top 5 chevaux et scores
//   • Ton cheval mis en valeur
//   • Comparatif bookmakers avec cotes estimées
//   • Minuterie/countdown avant le départ
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart' show NavigationNotifier;
import '../models/zt_models.dart';
import '../providers/pmu_provider.dart';
import '../services/alert_service.dart';
import '../services/zone_turf_service.dart';
import '../services/pmu_api_service.dart';
import '../services/gain_calculator.dart';
import '../utils/format_euros.dart';
import '../services/ia_pronostic_engine.dart';
import '../services/bookmaker_service.dart';
import '../widgets/bet_bottom_sheet.dart';
import '../widgets/share_card_generator.dart';

import 'package:url_launcher/url_launcher.dart';

class ParisDetailScreen extends StatefulWidget {
  final TrackedCourse tracked;
  final AlertService alertSvc;

  const ParisDetailScreen({
    super.key,
    required this.tracked,
    required this.alertSvc,
  });

  @override
  State<ParisDetailScreen> createState() => _ParisDetailScreenState();
}

class _ParisDetailScreenState extends State<ParisDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _countdownTimer;

  bool _loading = true;
  String? _error;
  ZtCourse? _course;
  ZtReunion? _reunion;
  PronosticIA? _pronostic;

  // Dividendes PMU réels récupérés après la course
  List<RapportPmu> _rapportsPmu = [];
  bool _chargementRapports = false;

  static const _kGreen = Color(0xFF4CAF7D);
  static const _kGold = Color(0xFFFFD700);
  static const _kBg   = Color(0xFF0B0F1A);   // bleu nuit neutre
  static const _kCard = Color(0xFF151C2E);   // carte bleu foncé
  // ignore: unused_field
  static const _kAccentBlue   = Color(0xFF2979FF);
  // ignore: unused_field
  static const _kAccentPurple = Color(0xFF9C27B0);
  // ignore: unused_field
  static const _kAccentOrange = Color(0xFFFF6D00);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted) setState(() {});
      },
    );
    _charger();
    WidgetsBinding.instance.addPostFrameCallback((_) => _chargerRapportsPmu());
  }

  Future<void> _charger() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reunions = await ZoneTurfService.chargerProgramme();
      if (!mounted) return;

      ZtReunion? foundReunion;
      ZtCourse? foundCourse;

      for (final r in reunions) {
        for (final c in r.courses) {
          if (c.numCourse == widget.tracked.numCourse) {
            final lieuNorm = r.lieu.toLowerCase().trim();
            final hippoNorm = widget.tracked.hippodrome.toLowerCase().trim();
            if (lieuNorm.contains(hippoNorm) ||
                hippoNorm.contains(lieuNorm) ||
                _numReunionMatch(r, widget.tracked.numReunion)) {
              foundReunion = r;
              foundCourse = c;
              break;
            }
          }
        }
        if (foundCourse != null) break;
      }

      // Fallback : chercher uniquement par numéro réunion + numéro course
      if (foundCourse == null) {
        for (final r in reunions) {
          for (final c in r.courses) {
            if (c.numCourse == widget.tracked.numCourse) {
              foundReunion = r;
              foundCourse = c;
              break;
            }
          }
          if (foundCourse != null) break;
        }
      }

      if (foundCourse != null && foundReunion != null) {
        final pronostic = IaPronosticEngine.genererPronostic(
            foundCourse, foundReunion.lieu);
        setState(() {
          _course = foundCourse;
          _reunion = foundReunion;
          _pronostic = pronostic;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'Course non trouvée dans le programme du jour.\n'
              'Elle est peut-être terminée ou le programme a changé.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Impossible de charger les données : $e';
        });
      }
    }
  }

  bool _numReunionMatch(ZtReunion r, int num) {
    final code = r.code.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(code) == num;
  }

  /// Formate la date : "Aujourd'hui", "Demain", "Hier" ou "Lun 07/04"
  String _formatDateCourte(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(dt.year, dt.month, dt.day);
    final diff = dateOnly.difference(today).inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Demain';
    if (diff == -1) return 'Hier';
    final jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return '${jours[dt.weekday - 1]} ${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}';
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ── Build principal ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          _buildAppBar(),
        ],
        body: _loading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: _kGreen),
                    SizedBox(height: 16),
                    Text('Chargement du programme…',
                        style: TextStyle(color: Colors.white54)),
                  ],
                ),
              )
            : _error != null
                ? _buildErrorView()
                : _buildContent(),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  SliverAppBar _buildAppBar() {
    final tc = widget.tracked;
    final statColor = tc.statutColor;
    final diff = tc.heureDepart.difference(DateTime.now());
    // ★ Fix seuils cohérents avec TrackedCourse.statutLabel
    final isEnCours = diff.inMinutes <= 0 && diff.inMinutes > -20;
    final isTerminee = diff.inMinutes <= -20 || tc.isGagne != null;

    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: _kBg,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (_course != null && _reunion != null)
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: _kGold),
            tooltip: 'Parier sur cette course',
            onPressed: () => showBetSheet(
              context,
              reunion: _reunion!,
              course: _course!,
              alertService: widget.alertSvc,
              onBetPlaced: () => context.read<NavigationNotifier>().goToMesParis(),
            ),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D1535), _kBg],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 52, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Statut + countdown
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: statColor.withValues(alpha: 0.5)),
                      ),
                      child: Row(children: [
                        if (isEnCours)
                          const _PulsingDot()
                        else
                          Icon(
                            isTerminee ? Icons.flag : Icons.timer,
                            color: statColor,
                            size: 12,
                          ),
                        const SizedBox(width: 6),
                        Text(tc.statutLabel,
                            style: TextStyle(
                                color: statColor,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      ]),
                    ),
                    const Spacer(),
                    _buildCountdownBadge(diff),
                  ]),
                  const SizedBox(height: 12),
                  // Nom course
                  Text(
                    tc.nomCourse,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.location_on,
                        color: Colors.white38, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${tc.hippodrome}  •  R${tc.numReunion} C${tc.numCourse}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 14),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.calendar_today,
                        color: Colors.white38, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatDateCourte(tc.heureDepart)} — ${tc.heureDepart.hour.toString().padLeft(2,'0')}h${tc.heureDepart.minute.toString().padLeft(2,'0')}',
                      style: const TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ]),
                  // ── Badge DQ (si des chevaux ont été disqualifiés/retirés) ──
                  Builder(builder: (ctx) {
                    final disqNums = widget.alertSvc.disqPourCourse(tc.key);
                    if (disqNums.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6F00).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFFFF6F00).withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFFF6F00), size: 14),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '⚠️ DQ/Retrait détecté : '
                                '${disqNums.map((n) => "N°$n").join(", ")}\n'
                                'Pronostic IA recalculé sans ces chevaux',
                                style: const TextStyle(
                                  color: Color(0xFFFF6F00),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                  if (_course != null) _buildCourseInfoChips(),
                ],
              ),
            ),
          ),
        ),
        title: Text(
          tc.nomCourse,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(46),
        child: Container(
          color: _kBg,
          child: TabBar(
            controller: _tabController,
            indicatorColor: _kGreen,
            labelColor: _kGreen,
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'MON PARI'),
              Tab(text: 'PRONOSTIC IA'),
              Tab(text: 'BOOKMAKERS'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownBadge(Duration diff) {
    if (diff.isNegative && diff.inMinutes <= -5) {
      return const SizedBox.shrink();
    }
    String label;
    Color col;
    if (diff.inMinutes <= 0) {
      label = 'En cours';
      col = const Color(0xFFEF5350);
    } else if (diff.inMinutes < 60) {
      label = 'Dans ${diff.inMinutes} min';
      col = const Color(0xFFFF9800);
    } else {
      label = 'Dans ${diff.inHours}h${(diff.inMinutes % 60).toString().padLeft(2, '0')}';
      col = const Color(0xFF64B5F6);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: col,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildCourseInfoChips() {
    final c = _course!;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _Chip('${c.typeIcon} ${c.type}', Colors.white30),
        _Chip('📏 ${c.distance}', Colors.white30),
        if (c.isQuinte) _Chip('🎯 Quinté+', _kGold),
        if (c.partants.isNotEmpty)
          _Chip('👥 ${c.partants.length} partants', Colors.white30),
      ],
    );
  }

  // ── Contenu principal ─────────────────────────────────────────────────────

  Widget _buildContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildTabMonPari(),
        _buildTabPronosticIA(),
        _buildTabBookmakers(),
      ],
    );
  }

  // ── Onglet 1 : Mon Pari ───────────────────────────────────────────────────

  Widget _buildTabMonPari() {
    final tc = widget.tracked;

    ZtPartant? myPartant;
    if (tc.numeroCheval != null && _pronostic != null) {
      final numStr = tc.numeroCheval.toString();
      try {
        myPartant = _pronostic!.top5
            .firstWhere((p) => p.numero == numStr);
      } catch (_) {
        if (_course != null) {
          try {
            myPartant = _course!.partants
                .firstWhere((p) => p.numero == numStr);
          } catch (_) {}
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        children: [
          if (tc.nomCheval != null)
            _buildMyHorseCard(
                tc.nomCheval!, tc.numeroCheval, tc.miseEngagee, myPartant),
          const SizedBox(height: 16),
          _buildPariResume(tc.miseEngagee, myPartant),
          const SizedBox(height: 16),
          _buildInfoCourse(tc),
          const SizedBox(height: 16),
          _buildActions(tc),
        ],
      ),
    );
  }

  Widget _buildMyHorseCard(
      String nom, int? num, double? mise, ZtPartant? partant) {
    final scoreColor = partant != null
        ? Color(IaPronosticEngine.scoreColor(partant.scoreIA))
        : Colors.white38;
    final label = partant?.labelIA ?? (num != null ? 'N°$num' : 'Sélection');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1040), Color(0xFF151C2E)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(0xFF7C4DFF), width: 1.5),
        boxShadow: [
          BoxShadow(color: Color(0x337C4DFF), blurRadius: 20),
        ],
      ),
      child: Column(
        children: [
          Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0x337C4DFF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Color(0xFF7C4DFF)),
              ),
              child: Center(
                child: Text(
                  num != null ? '$num' : '?',
                  style: const TextStyle(
                      color: Color(0xFFB39DDB),
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nom,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    if (partant != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        partant.driver.isNotEmpty
                            ? 'Driver : ${partant.driver}'
                            : partant.entraineur.isNotEmpty
                                ? 'Entraîneur : ${partant.entraineur}'
                                : '',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ]),
            ),
            if (partant != null)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  '${partant.scoreIA.toStringAsFixed(0)}/100',
                  style: TextStyle(
                      color: scoreColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
                Text('Score IA',
                    style: TextStyle(color: scoreColor, fontSize: 13)),
              ]),
          ]),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scoreColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
            ),
            child: Text(label,
                style: TextStyle(
                    color: scoreColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
          ),
          if (partant != null && partant.explicationIA.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              partant.explicationIA,
              style: const TextStyle(
                  color: Colors.white60, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  // ── Charge les rapports définitifs PMU après la course ───────────────────
  Future<void> _chargerRapportsPmu() async {
    final tc = widget.tracked;
    final diff = tc.heureDepart.difference(DateTime.now());
    // Autoriser si la course est terminée (≤ -20 min) OU si un résultat est déjà enregistré
    final courseTerminee = diff.inMinutes <= -20 || tc.isGagne != null;
    if (!courseTerminee) return;
    // ✅ Fix spinner infini : on ignore _chargementRapports (peut rester bloqué sur timeout)
    if (_rapportsPmu.isNotEmpty) return;
    if (!mounted) return;

    setState(() => _chargementRapports = true);
    try {
      final dep = tc.heureDepart;
      final dateStr =
          '${dep.day.toString().padLeft(2, '0')}${dep.month.toString().padLeft(2, '0')}${dep.year}';
      // ✅ Fix spinner infini : timeout 15s, jamais de spinner bloqué
      final rapports = await PmuApiService.fetchRapportsDefinitifs(
          dateStr, tc.numReunion, tc.numCourse)
          .timeout(const Duration(seconds: 15), onTimeout: () => []);
      if (!mounted) return;
      setState(() {
        _rapportsPmu = rapports;
        _chargementRapports = false;
      });
      if (rapports.isNotEmpty && mounted) {
        _majGainReelDansProfil(rapports);
      }
    } catch (e) {
      // ✅ Fix : toujours remettre _chargementRapports à false
      if (mounted) setState(() => _chargementRapports = false);
      if (kDebugMode) debugPrint('Erreur rapports PMU: $e');
    }
  }

  /// Met à jour le vrai gain PMU dans le profil utilisateur
  /// UNIQUEMENT si le pari est réellement gagnant — jamais pour un pari perdu ou en attente
  void _majGainReelDansProfil(List<RapportPmu> rapports) {
    if (!mounted) return;
    // ★ CRITIQUE : enregistrer SEULEMENT si isGagne == true (pas null, pas false)
    // isGagne == null = résultat inconnu → on n'enregistre pas encore
    // isGagne == false = perdu → on n'enregistre pas de gain
    if (widget.tracked.isGagne != true) return;
    try {
      final provider = context.read<PmuProvider>();
      final tc = widget.tracked;
      final pred = provider.getPredictionForCourse(tc.numReunion, tc.numCourse);
      if (pred == null || pred.dividendeRecupere) return;

      final typePariLower = tc.typePari.toLowerCase();
      List<String> codesPmu = [];
      if (typePariLower.contains('gagnant+placé') || typePariLower.contains('gagnant + placé') || typePariLower.contains('gagnant+place')) {
        codesPmu = ['E_SIMPLE_GAGNANT', 'E_SIMPLE_PLACE'];
      } else if (typePariLower.contains('couplé gagnant')) {
        codesPmu = ['E_COUPLE_GAGNANT'];
      } else if (typePariLower.contains('couplé placé')) {
        codesPmu = ['E_COUPLE_PLACE'];
      } else if (typePariLower.contains('quinté')) {
        codesPmu = ['E_MULTI', 'E_MINI_MULTI'];
      } else if (typePariLower.contains('quarté')) {
        codesPmu = ['E_SUPER_QUATRE'];
      } else if (typePariLower.contains('tiercé')) {
        codesPmu = ['E_TRIO'];
      } else if (typePariLower.contains('simple gagnant')) {
        codesPmu = ['E_SIMPLE_GAGNANT'];
      } else if (typePariLower.contains('simple placé')) {
        codesPmu = ['E_SIMPLE_PLACE'];
      } else if (typePariLower.contains('gagnant')) {
        codesPmu = ['E_SIMPLE_GAGNANT'];
      } else if (typePariLower.contains('placé')) {
        codesPmu = ['E_SIMPLE_PLACE'];
      }
      if (codesPmu.isEmpty) return;

      final matching = rapports.where((r) => codesPmu.contains(r.typePari)).toList();
      if (matching.isEmpty) return;
      final meilleur = matching.reduce((a, b) => a.dividende > b.dividende ? a : b);
      // 1. Mettre à jour UserPrediction dans PmuProvider (profil / historique)
      // isCorrect calculé depuis dividendePmuReel > 0 (jamais hardcodé à true)
      provider.enregistrerDividendePmu(
        pred.id,
        dividendePmuReel: meilleur.dividende,
        combinaisonPmu: meilleur.combinaison,
      );
      // 2. Mettre à jour TrackedCourse dans AlertService (mes paris / sauvegarde)
      final storageKey = tc.storageKey ?? tc.key;
      widget.alertSvc.enregistrerDividendePmuTracked(
        storageKey,
        dividende: meilleur.dividende,
        combinaison: meilleur.combinaison,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Erreur maj gain réel: $e');
    }
  }

  Widget _buildPariResume(double? mise, ZtPartant? partant) {
    final tc = widget.tracked;
    final coteEnregistree = tc.cote > 0 ? tc.cote : 0.0;
    final coteLive = partant != null
        ? double.tryParse(partant.cote.replaceAll(',', '.').replaceAll(' ', '')) ?? 0.0
        : 0.0;
    final cote = coteEnregistree > 0 ? coteEnregistree : (coteLive > 0 ? coteLive : 2.5);
    final gainPotentiel = mise != null && mise > 0 ? mise * cote : null;

    final diff = tc.heureDepart.difference(DateTime.now());
    final isTerminee = diff.inMinutes <= -20 || tc.isGagne != null;

    final typePariLower = tc.typePari.toLowerCase();
    final estCombine = typePariLower.contains('tiercé') ||
        typePariLower.contains('quarté') ||
        typePariLower.contains('quinté');

    List<String> codesPmuRecherche = [];
    if (typePariLower.contains('gagnant+placé') || typePariLower.contains('gagnant + placé') || typePariLower.contains('gagnant+place')) {
      codesPmuRecherche = ['E_SIMPLE_GAGNANT', 'E_SIMPLE_PLACE'];
    } else if (typePariLower.contains('couplé gagnant')) {
      codesPmuRecherche = ['E_COUPLE_GAGNANT'];
    } else if (typePariLower.contains('couplé placé')) {
      codesPmuRecherche = ['E_COUPLE_PLACE'];
    } else if (typePariLower.contains('quinté')) {
      codesPmuRecherche = ['E_MULTI', 'E_MINI_MULTI'];
    } else if (typePariLower.contains('quarté')) {
      codesPmuRecherche = ['E_SUPER_QUATRE'];
    } else if (typePariLower.contains('tiercé')) {
      codesPmuRecherche = ['E_TRIO'];
    } else if (typePariLower.contains('simple gagnant')) {
      codesPmuRecherche = ['E_SIMPLE_GAGNANT'];
    } else if (typePariLower.contains('simple placé')) {
      codesPmuRecherche = ['E_SIMPLE_PLACE'];
    } else if (typePariLower.contains('gagnant')) {
      codesPmuRecherche = ['E_SIMPLE_GAGNANT'];
    } else if (typePariLower.contains('placé')) {
      codesPmuRecherche = ['E_SIMPLE_PLACE'];
    }

    // ★ Fix dividendes vides : filtrage élargi avec fallback
    List<RapportPmu> rapportsPouri = [];
    if (codesPmuRecherche.isNotEmpty) {
      rapportsPouri = _rapportsPmu.where((r) => codesPmuRecherche.contains(r.typePari)).toList();
      // Fallback : si aucun rapport trouvé, chercher par mot-clé dans le code
      if (rapportsPouri.isEmpty) {
        if (typePariLower.contains('tiercé') || typePariLower.contains('tierce')) {
          rapportsPouri = _rapportsPmu.where((r) {
            final c = r.typePari.toUpperCase();
            return c.contains('TRIO') || c.contains('TIERCE') || c.contains('TIERCÉ');
          }).toList();
        } else if (typePariLower.contains('quarté') || typePariLower.contains('quarte')) {
          rapportsPouri = _rapportsPmu.where((r) {
            final c = r.typePari.toUpperCase();
            return c.contains('QUATRE') || c.contains('QUARTE') || c.contains('QUARTÉ');
          }).toList();
        } else if (typePariLower.contains('quinté') || typePariLower.contains('quinte')) {
          rapportsPouri = _rapportsPmu.where((r) {
            final c = r.typePari.toUpperCase();
            return c.contains('MULTI') || c.contains('QUINTE') || c.contains('QUINTÉ');
          }).toList();
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color(0xFFFF6D00), width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.receipt_long, color: Color(0xFFFF6D00), size: 16),
          SizedBox(width: 8),
          Text('RÉSUMÉ DU PARI',
              style: TextStyle(
                  color: Color(0xFFFF6D00),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
        ]),
        const SizedBox(height: 12),
        _InfoRow('Type de pari', tc.typePari, Colors.white70),
        const Divider(color: Colors.white10, height: 16),
        _InfoRow('Mise engagée',
            mise != null ? '${mise.toStringAsFixed(0)} €' : 'Non renseignée',
            _kGold),
        // Numéros joués pour les combinés — "Votre paris"
        if (tc.numerosJoues.isNotEmpty) ...[
          const Divider(color: Colors.white10, height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Votre paris',
                  style: TextStyle(
                    color: Color(0xFFFF6D00),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: tc.numerosJoues.map((n) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6D00).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFFF6D00).withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      'N°$n',
                      style: const TextStyle(
                        color: Color(0xFFFF6D00),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),
        ],
        // Cote uniquement pour paris simples
        if (!estCombine) ...[
          const Divider(color: Colors.white10, height: 16),
          _InfoRow('Cote enregistrée',
              cote > 0 ? '×${cote.toStringAsFixed(2)}' : 'Non disponible',
              Colors.white70),
          if (gainPotentiel != null) ...[
            const Divider(color: Colors.white10, height: 16),
            _InfoRow('Gain potentiel',
                '${fmtEuros(gainPotentiel)} €', _kGold,
                highlight: true),
          ],
        ],
        // ── Dividendes PMU réels après course ───────────────────────────
        if (isTerminee) ...[
          const SizedBox(height: 14),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 14),
          if (_chargementRapports)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1A0A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(children: [
                SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF4CAF7D))),
                SizedBox(width: 10),
                Text('Récupération des dividendes PMU…',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
              ]),
            )
          else if (_rapportsPmu.isNotEmpty)
            _buildDividendesPmuReels(
              rapportsPouri,
              mise ?? 0,
              estPerdu: tc.isGagne == false,
            )
          else
            // Bouton de récupération — pour TOUS les types de paris terminés
            GestureDetector(
              onTap: () {
                setState(() => _rapportsPmu = []);
                _chargerRapportsPmu();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1F0D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF4CAF7D).withValues(alpha: 0.45)),
                ),
                child: Row(children: [
                  const Icon(Icons.download_outlined,
                      color: Color(0xFF4CAF7D), size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Afficher les dividendes PMU officiels',
                      style: TextStyle(
                          color: Color(0xFF4CAF7D),
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: Color(0xFF4CAF7D), size: 18),
                ]),
              ),
            ),
        ],
        if (partant != null && partant.musique.isNotEmpty) ...[
          const Divider(color: Colors.white10, height: 16),
          _InfoRow('Musique', partant.musique, Colors.white54),
        ],
        if (partant != null && partant.gains.isNotEmpty) ...[
          const Divider(color: Colors.white10, height: 16),
          _InfoRow('Gains carrière', partant.gains, Colors.white54),
        ],
      ]),
    );
  }

  /// Libellé lisible pour un type de pari PMU + ordre/désordre
  String _labelRapport(RapportPmu r) {
    final t = r.typePari.toUpperCase();
    // Vrais codes API PMU
    if (t == 'E_TRIO' || t.contains('TRIO') || t.contains('TIERCE')) {
      return r.estOrdre ? 'Tiercé — Dans l\'ordre' : 'Tiercé — Désordre';
    }
    if (t == 'E_SUPER_QUATRE' || t.contains('QUATRE') || t.contains('QUARTE')) {
      return r.estOrdre ? 'Quarté+ — Dans l\'ordre' : 'Quarté+ — Désordre';
    }
    if (t == 'E_MULTI' || t.contains('QUINTE')) {
      return r.estOrdre ? 'Quinté+ — Dans l\'ordre' : 'Quinté+ — Désordre';
    }
    if (t == 'E_MINI_MULTI') {
      return r.estOrdre ? 'Quinté+ Mini — Dans l\'ordre' : 'Quinté+ Mini — Désordre';
    }
    if (t == 'E_COUPLE_GAGNANT' || t == 'E_COUPLE_ORDRE') return 'Couplé Gagnant';
    if (t == 'E_COUPLE_PLACE')   return 'Couplé Placé';
    if (t == 'E_SIMPLE_GAGNANT') return 'Simple Gagnant';
    if (t == 'E_SIMPLE_PLACE')   return 'Simple Placé';
    if (t == 'E_DEUX_SUR_QUATRE') return '2 sur 4';
    // ★ Fallback lisible pour les codes inconnus
    final clean = t.replaceAll('E_', '').replaceAll('_', ' ').toLowerCase();
    return clean.split(' ').map((w) => w.isEmpty ? '' : '\${w[0].toUpperCase()}\${w.substring(1)}').join(' ');
  }

  /// Icône + couleur de fond selon le vrai code API PMU
  Map<String, dynamic> _styleRapport(RapportPmu r) {
    final t = r.typePari.toUpperCase();
    if (t == 'E_MULTI' || t == 'E_MINI_MULTI') {
      return {'icon': '🌟', 'bg': const Color(0xFF2D1B00), 'border': const Color(0xFFFFD700),
              'labelColor': const Color(0xFFFFD700)};
    }
    if (t == 'E_SUPER_QUATRE') {
      return {'icon': '🎰', 'bg': const Color(0xFF1A0D2E), 'border': const Color(0xFFAB47BC),
              'labelColor': const Color(0xFFCE93D8)};
    }
    if (t == 'E_TRIO') {
      return r.estOrdre
          ? {'icon': '🥇', 'bg': const Color(0xFF0A2B18), 'border': const Color(0xFF4CAF7D),
             'labelColor': const Color(0xFF81C784)}
          : {'icon': '🥈', 'bg': const Color(0xFF102018), 'border': const Color(0xFF26A69A),
             'labelColor': const Color(0xFF80CBC4)};
    }
    if (t == 'E_COUPLE_GAGNANT' || t == 'E_COUPLE_PLACE') {
      return {'icon': '🤝', 'bg': const Color(0xFF001A2E), 'border': const Color(0xFF29B6F6),
              'labelColor': const Color(0xFF81D4FA)};
    }
    // Simple Gagnant, Simple Placé, Gagnant+Placé
    return {'icon': '🏇', 'bg': const Color(0xFF1A1500), 'border': const Color(0xFFFFB74D),
            'labelColor': const Color(0xFFFFCC80)};
  }

  /// Affiche les vrais dividendes PMU récupérés après la course — tous types
  Widget _buildDividendesPmuReels(List<RapportPmu> rapports, double mise,
      {bool estPerdu = false}) {
    // Couleur d'accent de l'en-tête : orange/doré pour perdu (hypothétique),
    // vert validé pour gagné
    final headerColor = estPerdu
        ? const Color(0xFFFFB300)   // ambre chaud
        : const Color(0xFF4CAF7D);  // vert officiel

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1422),   // bleu nuit neutre (plus sombre que _kCard)
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: headerColor.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── En-tête ─────────────────────────────────────────────────────
        Row(children: [
          Icon(
            estPerdu ? Icons.emoji_events_outlined : Icons.verified_outlined,
            color: headerColor, size: 16),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              estPerdu
                  ? 'SI TU AVAIS GAGNÉ — DIVIDENDES PMU'
                  : 'DIVIDENDES PMU OFFICIELS',
              style: TextStyle(
                color: headerColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
          if (estPerdu)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF7F1919).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: const Color(0xFFEF5350).withValues(alpha: 0.5)),
              ),
              child: const Text('PERDU',
                  style: TextStyle(
                      color: Color(0xFFEF9A9A),
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
        ]),
        const SizedBox(height: 4),
        if (estPerdu)
          Text(
            'Montants que tu aurais touchés avec ta mise de ${mise > 0 ? "${mise.toStringAsFixed(0)} €" : "ta mise"}',
            style: const TextStyle(
                color: Colors.white54, fontSize: 11, fontStyle: FontStyle.italic),
          ),
        const SizedBox(height: 10),
        const Divider(color: Colors.white10, height: 1),
        const SizedBox(height: 10),

        // ── Lignes de dividendes ─────────────────────────────────────────
        ...rapports.map((r) {
          final effectiveMise = mise > 0 ? mise : 1.0;
          final gainNet = r.gainNetPourMise(effectiveMise);
          final retour = r.retourPourMise(effectiveMise);
          final style = _styleRapport(r);
          final label = _labelRapport(r);
          final icon = style['icon'] as String;
          final bgColor = style['bg'] as Color;
          final borderColor = style['border'] as Color;
          final labelColor = style['labelColor'] as Color;

          // Couleur et icône du montant : doré pour paris perdu, vert vif pour gagné
          final gainColor = estPerdu
              ? const Color(0xFFFFD54F)   // doré/ambre
              : const Color(0xFF69F0AE);  // vert vif
          final retourColor = estPerdu
              ? const Color(0xFFFFCC80)   // orange clair
              : const Color(0xFF80CBC4);  // cyan clair

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(0),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: borderColor.withValues(alpha: 0.65), width: 1),
              ),
              child: Column(children: [
                // Ligne principale : label + montant
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(children: [
                    // Icône + label + cote
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Text(icon,
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: labelColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        if (r.combinaison.isNotEmpty)
                          Text(
                            'Arr. ${r.combinaison}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11),
                          ),
                        Text(
                          '×${r.dividende.toStringAsFixed(2)} pour 1 € misé',
                          style: TextStyle(
                              color: labelColor.withValues(alpha: 0.55),
                              fontSize: 10),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    // Badge montant coloré
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: gainColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: gainColor.withValues(alpha: 0.5),
                              width: 1),
                        ),
                        child: Text(
                          mise > 0
                              ? '${gainNet >= 0 ? "+" : ""}${fmtEuros(gainNet)} €'
                              : '×${r.dividende.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: gainColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      if (mise > 0) ...[  
                        const SizedBox(height: 3),
                        Text(
                          'retour ${fmtEuros(retour)} €',
                          style: TextStyle(
                              color: retourColor, fontSize: 11),
                        ),
                      ],
                    ]),
                  ]),
                ),
              ]),
            ),
          );
        }),
      ]),
    );
  }

  Widget _buildInfoCourse(TrackedCourse tc) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Color(0xFF29B6F6), width: 1.2),
      ),
      child: Column(children: [
        const Row(children: [
          Icon(Icons.info_outline, color: Color(0xFF29B6F6), size: 16),
          SizedBox(width: 8),
          Text('INFORMATIONS COURSE',
              style: TextStyle(
                  color: Color(0xFF29B6F6),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
        ]),
        const SizedBox(height: 12),
        _InfoRow('Hippodrome', tc.hippodrome, Colors.white70),
        const Divider(color: Colors.white10, height: 16),
        _InfoRow(
            'Départ',
            '${_formatDateCourte(tc.heureDepart)} — ${tc.heureDepart.hour.toString().padLeft(2, '0')}h${tc.heureDepart.minute.toString().padLeft(2, '0')}',
            Colors.white70),
        const Divider(color: Colors.white10, height: 16),
        _InfoRow('Réunion / Course',
            'R${tc.numReunion} — Course n°${tc.numCourse}',
            Colors.white70),
        if (_course != null) ...[
          const Divider(color: Colors.white10, height: 16),
          _InfoRow('Distance', _course!.distance, Colors.white70),
          const Divider(color: Colors.white10, height: 16),
          _InfoRow('Type', '${_course!.typeIcon} ${_course!.type}',
              Colors.white70),
          if (_course!.prix.isNotEmpty) ...[
            const Divider(color: Colors.white10, height: 16),
            _InfoRow('Dotation', _course!.prix, _kGold),
          ],
        ],
        const Divider(color: Colors.white10, height: 16),
        _InfoRow(
            'Suivi ajouté le',
            '${tc.addedAt.day.toString().padLeft(2, '0')}/${tc.addedAt.month.toString().padLeft(2, '0')} à ${tc.addedAt.hour.toString().padLeft(2, '0')}h${tc.addedAt.minute.toString().padLeft(2, '0')}',
            Colors.white38),
      ]),
    );
  }

  Widget _buildActions(TrackedCourse tc) {
    final diff = tc.heureDepart.difference(DateTime.now());
    final isTerminee = diff.inMinutes <= -20 || tc.isGagne != null;

    final shareData = ShareCardData(
      typePariLabel: tc.typePari,
      paris: [tc],
      miseTotal: tc.miseEngagee ?? 0.0,
      gainTotal: null,
      estGagnant: null,
      scoreIA: tc.scoreIA,
    );

    return Column(children: [
      // ── Bouton Partager ce pari ──────────────────────────────────────────
      _BigButton(
        icon: Icons.share,
        label: 'PARTAGER MON PARI',
        color: const Color(0xFF4CAF7D),
        onTap: () => ShareCardService.partagerCourse(context, data: shareData),
      ),
      const SizedBox(height: 8),
      // ── Bouton Sauvegarder en JPEG ────────────────────────────────────────
      _BigButton(
        icon: Icons.image_outlined,
        label: 'SAUVEGARDER EN JPEG',
        color: const Color(0xFF26C6DA),
        onTap: () => ShareCardService.sauvegarderEnJpeg(context, data: shareData),
      ),
      const SizedBox(height: 10),
      _BigButton(
        icon: Icons.open_in_new,
        label: 'Parier sur PMU.fr',
        color: const Color(0xFF1565C0),
        onTap: () async {
          final dep = tc.heureDepart;
          final dd   = dep.day.toString().padLeft(2, '0');
          final mm   = dep.month.toString().padLeft(2, '0');
          final yyyy = dep.year.toString();
          final dateStr = '$dd$mm$yyyy';
          final rr = tc.numReunion.toString().padLeft(2, '0');
          final cc = tc.numCourse.toString().padLeft(2, '0');
          final url = 'https://www.pmu.fr/turf/$dateStr/R$rr/C$cc';
          final uri = Uri.parse(url);
          bool launched = false;
          try {
            launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {}
          if (!launched) {
            try {
              launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
            } catch (_) {}
          }
          if (!launched) {
            final fallback = Uri.parse('https://www.pmu.fr/turf/offre/courses');
            try { await launchUrl(fallback, mode: LaunchMode.externalApplication); } catch (_) {}
          }
        },
      ),
      const SizedBox(height: 10),
      if (!isTerminee)
        _BigButton(
          icon: Icons.edit_note,
          label: 'Saisir le résultat',
          color: _kGreen,
          onTap: () {
            Navigator.pop(context);
          },
        ),
      const SizedBox(height: 10),
      _BigButton(
        icon: Icons.delete_outline,
        label: 'Supprimer ce suivi',
        color: const Color(0xFFEF5350),
        onTap: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: _kCard,
              title: const Text('Supprimer ?',
                  style: TextStyle(color: Colors.white)),
              content: const Text(
                'Voulez-vous supprimer ce suivi ? Cette action est irréversible.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Annuler')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Supprimer',
                        style: TextStyle(color: Color(0xFFEF5350)))),
              ],
            ),
          );
          if (confirm == true && mounted) {
            widget.alertSvc.retirerSuivi(tc.key);
            Navigator.pop(context);
          }
        },
      ),
    ]);
  }

  // ── Onglet 2 : Pronostic IA ───────────────────────────────────────────────

  Widget _buildTabPronosticIA() {
    if (_pronostic == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.psychology_outlined, color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text('Pronostic IA non disponible',
                style: TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }

    final pronostic = _pronostic!;
    final myNum = widget.tracked.numeroCheval?.toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        children: [
          _buildAnalyseCard(pronostic),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.star, color: _kGold, size: 16),
            const SizedBox(width: 6),
            Text(
              'TOP ${pronostic.top5.length} — SÉLECTION IA',
              style: const TextStyle(
                  color: _kGold,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 1),
            ),
          ]),
          const SizedBox(height: 8),
          ...pronostic.top5.asMap().entries.map((e) {
            final idx = e.key;
            final p = e.value;
            final isMy = myNum != null && p.numero == myNum;
            return _buildPartantCard(p, idx + 1, isMy);
          }),
          const SizedBox(height: 16),
          _buildConseilCard(pronostic),
          // ── Pronostic PMU (favoris par cote) ──
          if (_course != null) ...[ 
            const SizedBox(height: 16),
            _buildPMUPronostic(_course!),
          ],
        ],
      ),
    );
  }

  /// Bloc Pronostic PMU — favoris par cote croissante
  Widget _buildPMUPronostic(ZtCourse course) {
    final pmu = course.pronosticPMU;

    // Si pas de cotes : afficher quand même un message
    if (pmu.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFD700).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          const Text('🏇', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PRONOSTIC PMU', style: TextStyle(
                color: Color(0xFFFFD700), fontWeight: FontWeight.bold,
                fontSize: 13, letterSpacing: 1)),
              SizedBox(height: 3),
              Text('Cotes PMU disponibles H-2 avant la course',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          )),
        ]),
      );
    }

    // Récupérer les partants correspondant aux numéros PMU
    final partantsByNum = { for (var p in course.partants) p.numero: p };
    final myNum = widget.tracked.numeroCheval?.toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('🏇', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            const Text('FAVORIS PMU', style: TextStyle(
              color: Color(0xFFFFD700), fontWeight: FontWeight.bold,
              fontSize: 13, letterSpacing: 1)),
            const Spacer(),
            const Text('par cote croissante',
              style: TextStyle(color: Colors.white30, fontSize: 11)),
          ]),
          const SizedBox(height: 10),
          ...pmu.take(5).toList().asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final num = entry.value;
            final numStr = num.toString();
            final partant = partantsByNum[numStr];
            final isMy = myNum == numStr;
            final cote = partant != null
                ? double.tryParse(partant.cote.replaceAll(',', '.')) ?? 0.0
                : 0.0;

            final rankColors = [
              const Color(0xFFFFD700),  // Or
              const Color(0xFFC0C0C0),  // Argent
              const Color(0xFFCD7F32),  // Bronze
              Colors.white54,
              Colors.white38,
            ];
            final rankColor = rankColors[entry.key < 5 ? entry.key : 4];

            return Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: isMy
                    ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isMy
                      ? const Color(0xFFFFD700).withValues(alpha: 0.6)
                      : rank == 1
                          ? const Color(0xFFFFD700).withValues(alpha: 0.3)
                          : Colors.white10,
                  width: isMy ? 1.5 : 1,
                ),
              ),
              child: Row(children: [
                // Rang PMU
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: rankColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(child: Text(
                    '$rank',
                    style: TextStyle(color: rankColor, fontSize: 12, fontWeight: FontWeight.bold),
                  )),
                ),
                const SizedBox(width: 8),
                // Numéro du cheval
                Container(
                  width: 30, height: 26,
                  decoration: BoxDecoration(
                    color: isMy
                        ? const Color(0xFFFFD700).withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: isMy
                          ? const Color(0xFFFFD700)
                          : Colors.white24),
                  ),
                  child: Center(child: Text(
                    'N°$num',
                    style: TextStyle(
                      color: isMy ? const Color(0xFFFFD700) : Colors.white70,
                      fontSize: 11, fontWeight: FontWeight.bold),
                  )),
                ),
                const SizedBox(width: 8),
                // Nom + jockey
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partant?.nom ?? 'N°$num',
                      style: TextStyle(
                        color: isMy ? const Color(0xFFFFD700) : Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    if (partant?.driver.isNotEmpty == true)
                      Text(
                        partant!.driver,
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                  ],
                )),
                // Cote
                if (cote > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '×${cote.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: Color(0xFFFFD700), fontSize: 12,
                        fontWeight: FontWeight.bold),
                    ),
                  ),
                if (isMy) ...[ 
                  const SizedBox(width: 6),
                  const Icon(Icons.star, color: Color(0xFFFFD700), size: 14),
                ],
              ]),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildAnalyseCard(PronosticIA pronostic) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.psychology, color: _kGreen, size: 18),
            const SizedBox(width: 8),
            const Text('ANALYSE IA',
                style: TextStyle(
                    color: _kGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${pronostic.confianceGlobale.toStringAsFixed(0)}% confiance',
                style: const TextStyle(
                    color: _kGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            pronostic.analyseTextuelle,
            style: const TextStyle(
                color: Colors.white70, fontSize: 14, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildPartantCard(ZtPartant p, int rank, bool isMy) {
    final scoreColor = Color(IaPronosticEngine.scoreColor(p.scoreIA));
    final labelColor = Color(IaPronosticEngine.labelColor(p.labelIA));
    final cote = double.tryParse(
            p.cote.replaceAll(',', '.').replaceAll(' ', '')) ??
        0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMy ? _kGreen.withValues(alpha: 0.08) : _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMy
              ? _kGreen.withValues(alpha: 0.6)
              : rank == 1
                  ? _kGold.withValues(alpha: 0.4)
                  : Colors.white10,
          width: isMy ? 1.5 : 1,
        ),
      ),
      child: Row(children: [
        // Rang
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: rank == 1 ? _kGold.withValues(alpha: 0.15) : Colors.white10,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$rank',
              style: TextStyle(
                  color: rank == 1 ? _kGold : Colors.white38,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Numéro
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: scoreColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: scoreColor.withValues(alpha: 0.5)),
          ),
          child: Center(
            child: Text(p.numero,
                style: TextStyle(
                    color: scoreColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 10),
        // Infos
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      p.nom,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isMy) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _kGreen.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('MON CHEVAL',
                          style: TextStyle(
                              color: _kGreen,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(p.labelIA,
                    style: TextStyle(
                        color: labelColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                if (p.musique.isNotEmpty)
                  Text(p.musique,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
              ]),
        ),
        // Score + cote
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${p.scoreIA.toStringAsFixed(0)}',
            style: TextStyle(
                color: scoreColor, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text('/100', style: TextStyle(color: scoreColor, fontSize: 14)),
          if (cote > 0)
            Text('×${cote.toStringAsFixed(1)}',
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
        ]),
      ]),
    );
  }

  Widget _buildConseilCard(PronosticIA pronostic) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kGold.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGold.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CONSEIL IA',
                    style: TextStyle(
                        color: _kGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1)),
                const SizedBox(height: 6),
                Text(pronostic.conseil,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Onglet 3 : Bookmakers ─────────────────────────────────────────────────

  Widget _buildTabBookmakers() {
    final tc = widget.tracked;
    ZtPartant? myPartant;
    if (tc.numeroCheval != null) {
      final numStr = tc.numeroCheval.toString();
      if (_pronostic != null) {
        try {
          myPartant = _pronostic!.top5.firstWhere((p) => p.numero == numStr);
        } catch (_) {}
      }
      if (myPartant == null && _course != null) {
        try {
          myPartant = _course!.partants.firstWhere((p) => p.numero == numStr);
        } catch (_) {}
      }
    }

    final coteRef = myPartant != null
        ? double.tryParse(
                myPartant.cote.replaceAll(',', '.').replaceAll(' ', '')) ??
            3.0
        : 3.0;

    final cotes = BookmakerService.getCotesTriees(coteRef);
    final mise = tc.miseEngagee ?? 10.0;
    final nomCheval = tc.nomCheval ?? 'le cheval sélectionné';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(children: [
              const Icon(Icons.compare_arrows,
                  color: Colors.white38, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Comparaison des cotes pour $nomCheval '
                  '(cote PMU de référence : ×${coteRef.toStringAsFixed(2)})',
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          ...cotes.map((bc) => _buildBookmakerCard(bc, mise)),
        ],
      ),
    );
  }

  Widget _buildBookmakerCard(BookmakerCote bc, double mise) {
    final info = bc.bookmaker;
    final gain = bc.gainPour(mise);
    final gainTotal = bc.cote * mise;
    final isBest = bc.isMeilleure;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isBest ? _kGold.withValues(alpha: 0.7) : Colors.white12,
          width: isBest ? 1.5 : 1,
        ),
      ),
      child: Column(children: [
        Row(children: [
          Text(info.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(info.nom,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    if (isBest) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _kGold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('MEILLEURE COTE',
                            style: TextStyle(
                                color: _kGold,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ]),
                  Text(info.description,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 13)),
                ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '×${bc.cote.toStringAsFixed(2)}',
              style: TextStyle(
                  color: isBest ? _kGold : Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            Text('Gain : +${fmtEuros(gain)} €',
                style: const TextStyle(color: _kGreen, fontSize: 14)),
          ]),
        ]),
        const SizedBox(height: 10),
        // Barre de progression
        Row(children: [
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (bc.cote / 10).clamp(0.05, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: isBest ? _kGold : _kGreen,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Retour : ${fmtEuros(gainTotal)} €',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ]),
        if (info.bonus.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              const Icon(Icons.card_giftcard, color: Colors.white38, size: 13),
              const SizedBox(width: 6),
              Expanded(
                child: Text(info.bonus,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 13)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.open_in_new, size: 14),
            label: Text('Parier sur ${info.nom}'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  Color(info.couleur).withValues(alpha: 0.85),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              final url = info.urlApp.isNotEmpty ? info.urlApp : info.urlBase;
              final uri = Uri.parse(url);
              bool launched = false;
              try {
                launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
              if (!launched) {
                try { await launchUrl(uri, mode: LaunchMode.platformDefault); } catch (_) {}
              }
            },
          ),
        ),
      ]),
    );
  }

  // ── Vue erreur ────────────────────────────────────────────────────────────

  Widget _buildErrorView() {
    final tc = widget.tracked;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, color: Colors.white24, size: 56),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            // Données enregistrées en fallback
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DONNÉES ENREGISTRÉES',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 10),
                  Text(tc.nomCourse,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                      '${tc.hippodrome}  •  R${tc.numReunion}C${tc.numCourse}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 14)),
                  if (tc.nomCheval != null) ...[
                    const Divider(color: Colors.white10, height: 20),
                    Row(children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _kGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _kGreen),
                        ),
                        child: Center(
                          child: Text(
                            '${tc.numeroCheval ?? "?"}',
                            style: const TextStyle(
                                color: _kGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(tc.nomCheval!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ]),
                    if (tc.miseEngagee != null) ...[
                      const SizedBox(height: 6),
                      Text(
                          'Mise : ${tc.miseEngagee!.toStringAsFixed(0)} €',
                          style: const TextStyle(
                              color: _kGold, fontSize: 14)),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, color: _kGreen),
              label: const Text('Réessayer',
                  style: TextStyle(color: _kGreen)),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kGreen)),
              onPressed: _charger,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  WIDGETS UTILITAIRES
// ══════════════════════════════════════════════════════════════════════════════

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool highlight;

  const _InfoRow(this.label, this.value, this.valueColor,
      {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 14)),
      ),
      Text(
        value,
        style: TextStyle(
            color: valueColor,
            fontSize: highlight ? 15 : 12,
            fontWeight:
                highlight ? FontWeight.bold : FontWeight.normal),
      ),
    ]);
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _BigButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.85),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        onPressed: onTap,
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _anim = Tween<double>(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _ctrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: const Color(0xFFEF5350).withValues(alpha: _anim.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
