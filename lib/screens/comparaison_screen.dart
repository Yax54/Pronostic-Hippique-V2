import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pmu_provider.dart';
import '../models/pmu_models.dart';
import '../services/prediction_engine.dart';
import '../widgets/gain_simulator_widget.dart';
import 'race_detail_screen.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Écran de comparaison : Pronostics IA Pronostic Hippique vs Equidia (officiel)
/// ─────────────────────────────────────────────────────────────────────────────
class ComparaisonScreen extends StatefulWidget {
  const ComparaisonScreen({super.key});

  @override
  State<ComparaisonScreen> createState() => _ComparaisonScreenState();
}

class _ComparaisonScreenState extends State<ComparaisonScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = false;
  String? _error;
  List<_ComparaisonData> _comparaisons = [];

  // Quel mode d'affichage : 0=IA, 1=Equidia, 2=Comparaison (suivi par tabController)

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });

    final provider = Provider.of<PmuProvider>(context, listen: false);
    if (provider.loadingState == LoadingState.loading) {
      await Future.delayed(const Duration(seconds: 2));
    }
    if (provider.loadingState == LoadingState.error) {
      if (mounted) setState(() { _loading = false; _error = provider.errorMessage; });
      return;
    }

    // Courses FRANÇAISES à venir / en cours uniquement
    final courses = provider.frenchCourses
        .where((c) => c.status != CourseStatus.terminee)
        .toList()
      ..sort((a, b) => a.heureDepart.compareTo(b.heureDepart));

    if (courses.isEmpty) {
      if (mounted) setState(() { _loading = false; _error = 'Aucune course à venir aujourd\'hui.'; });
      return;
    }

    final result = <_ComparaisonData>[];

    for (final course in courses) {
      // Charger partants et pronostics Equidia en parallèle
      await Future.wait([
        provider.loadParticipants(course),
        provider.loadEquidiaPronostics(course),
      ]);

      if (course.participants.isEmpty) continue;

      final reunion = provider.frenchReunions.firstWhere(
        (r) => r.numOfficiel == course.numReunion,
        orElse: () => PmuReunion(numOfficiel: 0, hippodrome: '?', hippodromeCode: '', dateStr: '', courses: []),
      );

      final equidia = provider.getEquidiaPronostics(course.numReunion, course.numOrdre);
      final rec = PredictionEngine.generateRecommendation(
        course, course.participants, reunion.hippodrome,
      );

      result.add(_ComparaisonData(
        course: course,
        hippodrome: reunion.hippodrome,
        recommendation: rec,
        equidia: equidia,
        participants: course.participants,
      ));
    }

    if (mounted) setState(() { _comparaisons = result; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D2818),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1F12),
        title: const Row(children: [
          Icon(Icons.compare_arrows, color: Color(0xFFFFD700), size: 20),
          SizedBox(width: 8),
          Text('IA vs Equidia', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF4CAF7D)),
            onPressed: _loadAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFD700),
          labelColor: const Color(0xFFFFD700),
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(icon: Icon(Icons.auto_awesome, size: 16), text: 'IA Only'),
            Tab(icon: Icon(Icons.tv, size: 16), text: 'Equidia'),
            Tab(icon: Icon(Icons.compare_arrows, size: 16), text: 'Comparaison'),
          ],
        ),
      ),
      body: _loading
          ? const _LoadingView()
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _loadAll)
              : _comparaisons.isEmpty
                  ? const _EmptyView()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildIaOnlyList(),
                        _buildEquidiaOnlyList(),
                        _buildComparaisonList(),
                      ],
                    ),
    );
  }

  // ─── Vue IA uniquement ────────────────────────────────────────────────────

  Widget _buildIaOnlyList() {
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _comparaisons.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) return _IaBanner(comparaisons: _comparaisons);
        final d = _comparaisons[i - 1];
        return _IaCard(data: d);
      },
    );
  }

  // ─── Vue Equidia uniquement ───────────────────────────────────────────────

  Widget _buildEquidiaOnlyList() {
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _comparaisons.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) return _EquidiaBanner(comparaisons: _comparaisons);
        final d = _comparaisons[i - 1];
        return _EquidiaCard(data: d);
      },
    );
  }

  // ─── Vue comparaison côte à côte ─────────────────────────────────────────

  Widget _buildComparaisonList() {
    final provider = context.watch<PmuProvider>();
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _comparaisons.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) return _ComparaisonBanner(comparaisons: _comparaisons);
        final d = _comparaisons[i - 1];
        return _ComparaisonCard(data: d, provider: provider);
      },
    );
  }
}

// ─── Données de comparaison ───────────────────────────────────────────────────

class _ComparaisonData {
  final PmuCourse course;
  final String hippodrome;
  final RaceRecommendation recommendation;
  final EquidiaPronostics? equidia;
  final List<PmuParticipant> participants;

  _ComparaisonData({
    required this.course,
    required this.hippodrome,
    required this.recommendation,
    required this.equidia,
    required this.participants,
  });

  /// Accord entre IA et Equidia sur le gagnant
  bool get accordGagnant {
    if (recommendation.gagnant == null || equidia == null || equidia!.isEmpty) return false;
    return equidia!.selections.first.numPartant == recommendation.gagnant!.numero;
  }

  /// Nombre de chevaux en commun dans le top 3 IA vs top 3 Equidia
  int get chevauxEnCommun {
    if (equidia == null || equidia!.isEmpty) return 0;
    final iaTop = recommendation.tierce.map((p) => p.numero).toSet();
    final equTop = equidia!.numerosTop(3).toSet();
    return iaTop.intersection(equTop).length;
  }

  /// Score de convergence (0–100)
  int get scoreConvergence {
    if (equidia == null || equidia!.isEmpty) return 0;
    int score = chevauxEnCommun * 25; // 0/1/2/3 communs → 0/25/50/75
    if (accordGagnant) score += 25;   // accord sur gagnant = bonus 25
    return score.clamp(0, 100);
  }

  /// Qui a la meilleure sélection probabiliste ?
  String get verdict {
    if (equidia == null || equidia!.isEmpty) return 'IA uniquement';
    final conv = scoreConvergence;
    if (conv >= 75) return 'Accord fort';
    if (conv >= 50) return 'Accord partiel';
    if (conv >= 25) return 'Léger désaccord';
    return 'Désaccord total';
  }

  Color get verdictColor {
    final conv = scoreConvergence;
    if (conv >= 75) return const Color(0xFF4CAF7D);
    if (conv >= 50) return const Color(0xFF81C784);
    if (conv >= 25) return const Color(0xFFFFB74D);
    return const Color(0xFFEF9A9A);
  }
}

// ─── BANNIÈRES ────────────────────────────────────────────────────────────────

class _IaBanner extends StatelessWidget {
  final List<_ComparaisonData> comparaisons;
  const _IaBanner({required this.comparaisons});

  @override
  Widget build(BuildContext context) {
    final excellent = comparaisons.where((d) => d.recommendation.conseil == ConseilType.excellent).length;
    final bon = comparaisons.where((d) => d.recommendation.conseil == ConseilType.bon).length;
    return _BaseBanner(
      color: const Color(0xFF2E7D52),
      icon: Icons.auto_awesome,
      title: '🤖 Pronostics Pronostic Hippique IA',
      subtitle: 'Algorithme multi-critères : cotes + stats + forme',
      stats: [
        ('$excellent', 'Excellents', const Color(0xFF4CAF7D)),
        ('$bon', 'Bons', const Color(0xFF81C784)),
        ('${comparaisons.length}', 'Analysés', Colors.white),
      ],
    );
  }
}

class _EquidiaBanner extends StatelessWidget {
  final List<_ComparaisonData> comparaisons;
  const _EquidiaBanner({required this.comparaisons});

  @override
  Widget build(BuildContext context) {
    final avecProno = comparaisons.where((d) => d.equidia != null && !d.equidia!.isEmpty).length;
    return _BaseBanner(
      color: const Color(0xFF1565C0),
      icon: Icons.tv,
      title: '📺 Pronostics Equidia (Officiel)',
      subtitle: 'Sélection des experts hippiques partenaires PMU',
      stats: [
        ('$avecProno', 'Avec prono', const Color(0xFF64B5F6)),
        ('${comparaisons.length - avecProno}', 'Sans prono', Colors.white38),
        ('${comparaisons.length}', 'Courses', Colors.white),
      ],
    );
  }
}

class _ComparaisonBanner extends StatelessWidget {
  final List<_ComparaisonData> comparaisons;
  const _ComparaisonBanner({required this.comparaisons});

  @override
  Widget build(BuildContext context) {
    final accords = comparaisons.where((d) => d.accordGagnant).length;
    final avecEquidia = comparaisons.where((d) => d.equidia != null).length;
    final pctAccord = avecEquidia > 0 ? (accords / avecEquidia * 100).round() : 0;
    return _BaseBanner(
      color: const Color(0xFF6A1B9A),
      icon: Icons.compare_arrows,
      title: '⚖️ IA vs Equidia — Comparaison',
      subtitle: 'Convergence des deux sources pour maximiser vos chances',
      stats: [
        ('$accords', 'Accords gagnant', const Color(0xFF4CAF7D)),
        ('$pctAccord%', 'Convergence', const Color(0xFFFFD700)),
        ('$avecEquidia', 'Courses comp.', Colors.white),
      ],
    );
  }
}

class _BaseBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<(String, String, Color)> stats;
  const _BaseBanner({required this.color, required this.icon, required this.title, required this.subtitle, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.7), color.withValues(alpha: 0.3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: stats.map((s) => Column(children: [
              Text(s.$1, style: TextStyle(color: s.$3, fontSize: 20, fontWeight: FontWeight.bold)),
              Text(s.$2, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ])).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── CARTES IA ONLY ───────────────────────────────────────────────────────────

class _IaCard extends StatelessWidget {
  final _ComparaisonData data;
  const _IaCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final rec = data.recommendation;
    final color = _conseilColor(rec.conseil);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          _HeureChip(heure: rec.course.heureStr),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rec.course.libelle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
            Text('${rec.hippodrome} • ${rec.course.distance}m ${rec.course.disciplineIcon}', style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ])),
          _ConseilBadge(conseil: rec.conseil, confiance: rec.niveauConfiance),
        ]),
        const SizedBox(height: 12),

        // Sélection IA top 3
        const Text('🤖 Sélection IA', style: TextStyle(color: Color(0xFF4CAF7D), fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Row(children: rec.tierce.asMap().entries.map((e) =>
          _HorseChip(
            numero: e.value.numero,
            nom: e.value.nom,
            rang: e.key + 1,
            cote: e.value.coteAffichee,
            color: const Color(0xFF2E7D52),
            isFirst: e.key == 0,
          ),
        ).toList()),

        const SizedBox(height: 8),
        // Type de pari conseillé
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Text(rec.typePariLabel, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Text(rec.miseLabel, style: const TextStyle(color: Colors.white38, fontSize: 13)),
        ]),
      ]),
    );
  }

  Color _conseilColor(ConseilType t) {
    switch (t) {
      case ConseilType.excellent: return const Color(0xFF4CAF7D);
      case ConseilType.bon: return const Color(0xFF81C784);
      case ConseilType.moyen: return const Color(0xFFFFB74D);
      case ConseilType.incertain: return const Color(0xFFEF9A9A);
      case ConseilType.insuffisant: return const Color(0xFF9E9E9E);
    }
  }
}

// ─── CARTES EQUIDIA ONLY ──────────────────────────────────────────────────────

class _EquidiaCard extends StatelessWidget {
  final _ComparaisonData data;
  const _EquidiaCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final equidia = data.equidia;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1976D2).withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _HeureChip(heure: data.course.heureStr),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(data.course.libelle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
            Text('${data.hippodrome} • ${data.course.distance}m ${data.course.disciplineIcon}', style: const TextStyle(color: Colors.white54, fontSize: 14)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1976D2).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF42A5F5).withValues(alpha: 0.7)),
            ),
            child: const Text('📺 EQUIDIA', style: TextStyle(color: Color(0xFF64B5F6), fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 12),

        if (equidia == null || equidia.isEmpty)
          const Text('Pronostic Equidia non disponible pour cette course', style: TextStyle(color: Colors.white38, fontSize: 14))
        else ...[
          Row(children: [
            const Text('📺 Sélection Equidia', style: TextStyle(color: Color(0xFF64B5F6), fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            if (equidia.signature.isNotEmpty)
              Text('— ${equidia.signature}', style: const TextStyle(color: Colors.white30, fontSize: 13)),
          ]),
          const SizedBox(height: 6),

          // Top 5 Equidia
          Wrap(spacing: 6, runSpacing: 6, children: equidia.selections.take(5).map((sel) {
            // Trouver le nom du cheval
            final participant = data.participants.where((p) => p.numero == sel.numPartant).toList();
            final nom = participant.isNotEmpty ? participant.first.nom : 'N°${sel.numPartant}';
            return _HorseChip(
              numero: sel.numPartant,
              nom: nom,
              rang: sel.rang,
              cote: sel.coteProbDecimale,
              coteLabel: sel.coteProb,
              color: const Color(0xFF1565C0),
              isFirst: sel.rang == 1,
            );
          }).toList()),
        ],
      ]),
    );
  }
}

// ─── CARTES COMPARAISON ───────────────────────────────────────────────────────

class _ComparaisonCard extends StatefulWidget {
  final _ComparaisonData data;
  final PmuProvider provider;
  const _ComparaisonCard({required this.data, required this.provider});

  @override
  State<_ComparaisonCard> createState() => _ComparaisonCardState();
}

class _ComparaisonCardState extends State<_ComparaisonCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final rec = d.recommendation;
    final equidia = d.equidia;
    final verdictColor = d.verdictColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1F12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: verdictColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(children: [
        // ─ Header ─
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Titre course
              Row(children: [
                _HeureChip(heure: rec.course.heureStr),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rec.course.libelle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                  Text('${rec.hippodrome} • ${rec.course.distance}m ${rec.course.disciplineIcon} • ${d.participants.length} partants', style: const TextStyle(color: Colors.white54, fontSize: 14)),
                ])),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: Colors.white30, size: 20),
              ]),

              const SizedBox(height: 12),

              // ─ Verdict de convergence ─
              _VerdictBadge(data: d),

              const SizedBox(height: 12),

              // ─ Comparaison côte à côte ─
              Row(children: [
                // IA
                Expanded(child: _SourceColumn(
                  label: '🤖 Pronostic Hippique IA',
                  color: const Color(0xFF2E7D52),
                  horses: rec.tierce.take(3).map((p) => (p.numero, p.nom, p.coteAffichee, '')).toList(),
                  badge: rec.conseilLabel,
                  badgeColor: _conseilColor(rec.conseil),
                )),
                // Séparateur VS
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: verdictColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: verdictColor.withValues(alpha: 0.6)),
                      ),
                      child: Text('VS', style: TextStyle(color: verdictColor, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ]),
                ),
                // Equidia
                Expanded(child: equidia != null && !equidia.isEmpty
                  ? _SourceColumn(
                      label: '📺 Equidia',
                      color: const Color(0xFF1565C0),
                      horses: equidia.selections.take(3).map((sel) {
                        final p = d.participants.where((p) => p.numero == sel.numPartant).toList();
                        final nom = p.isNotEmpty ? p.first.nom : '?';
                        return (sel.numPartant, nom, sel.coteProbDecimale, sel.coteProb);
                      }).toList(),
                      badge: 'OFFICIEL',
                      badgeColor: const Color(0xFF42A5F5),
                    )
                  : const _NoEquidiaColumn()),
              ]),
            ]),
          ),
        ),

        // ─ Détails expandés ─
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(),
          secondChild: _ExpandedComparaison(data: d, provider: widget.provider),
        ),
      ]),
    );
  }

  Color _conseilColor(ConseilType t) {
    switch (t) {
      case ConseilType.excellent: return const Color(0xFF4CAF7D);
      case ConseilType.bon: return const Color(0xFF81C784);
      case ConseilType.moyen: return const Color(0xFFFFB74D);
      case ConseilType.incertain: return const Color(0xFFEF9A9A);
      case ConseilType.insuffisant: return const Color(0xFF9E9E9E);
    }
  }
}

// ─── Badge verdict de convergence ────────────────────────────────────────────

class _VerdictBadge extends StatelessWidget {
  final _ComparaisonData data;
  const _VerdictBadge({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.equidia == null || data.equidia!.isEmpty) {
      return const SizedBox.shrink();
    }

    final color = data.verdictColor;
    final conv = data.scoreConvergence;
    final commun = data.chevauxEnCommun;

    String emoji;
    if (conv >= 75) { emoji = '🔥'; }
    else if (conv >= 50) { emoji = '✅'; }
    else if (conv >= 25) { emoji = '⚠️'; }
    else { emoji = '❓'; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${data.verdict} — $commun/3 chevaux en commun',
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
          Text(data.accordGagnant
              ? '✅ IA et Equidia s\'accordent sur le gagnant !'
              : '⚡ Gagnants différents — analyse détaillée recommandée',
              style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 13)),
        ])),
        // Jauge de convergence
        SizedBox(width: 50, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$conv%', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: conv / 100,
              backgroundColor: const Color(0xFF1A4731),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ])),
      ]),
    );
  }
}

// ─── Colonne source (IA ou Equidia) ──────────────────────────────────────────

class _SourceColumn extends StatelessWidget {
  final String label;
  final Color color;
  final List<(int, String, double, String)> horses; // (numero, nom, cote, coteLabel)
  final String badge;
  final Color badgeColor;
  const _SourceColumn({required this.label, required this.color, required this.horses, required this.badge, required this.badgeColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // En-tête
        Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
            ),
            child: Text(badge, style: TextStyle(color: badgeColor, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 8),
        // Chevaux
        ...horses.asMap().entries.map((e) {
          final idx = e.key;
          final h = e.value;
          final medals = ['🥇', '🥈', '🥉'];
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(children: [
              Text(medals[idx], style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: idx == 0 ? color.withValues(alpha: 0.3) : const Color(0xFF0D2818),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: color.withValues(alpha: 0.7)),
                ),
                child: Center(child: Text('${h.$1}', style: TextStyle(color: idx == 0 ? color : Colors.white70, fontSize: 13, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 5),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.$2, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, maxLines: 1),
                Text(h.$4.isNotEmpty ? h.$4 : (h.$3 > 0 ? '${h.$3.toStringAsFixed(1)}' : '-'),
                    style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 14)),
              ])),
            ]),
          );
        }),
      ]),
    );
  }
}

class _NoEquidiaColumn extends StatelessWidget {
  const _NoEquidiaColumn();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('📺', style: TextStyle(fontSize: 22)),
        SizedBox(height: 6),
        Text('Pronostic\nEquidia\nnon disponible', style: TextStyle(color: Colors.white30, fontSize: 13), textAlign: TextAlign.center),
      ]),
    );
  }
}

// ─── Détails expandés comparaison ────────────────────────────────────────────

class _ExpandedComparaison extends StatelessWidget {
  final _ComparaisonData data;
  final PmuProvider provider;
  const _ExpandedComparaison({required this.data, required this.provider});

  @override
  Widget build(BuildContext context) {
    final rec = data.recommendation;
    final equidia = data.equidia;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Divider(color: const Color(0xFF2E7D52).withValues(alpha: 0.3), height: 20),

        // ─ Analyse de convergence ─
        if (equidia != null && !equidia.isEmpty) ...[
          _ConvergenceAnalysis(data: data),
          const SizedBox(height: 14),
        ],

        // ─ Classement complet ─
        const Text('📊 Classement complet IA (tous les partants)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...rec.ranked.take(6).toList().asMap().entries.map((e) {
          final p = e.value;
          final rank = e.key + 1;
          final score = PredictionEngine.computeScore(p);
          // Est-il dans la sélection Equidia ?
          final inEquidia = equidia != null && equidia.selections.any((s) => s.numPartant == p.numero);
          final equidiaRank = equidia != null
              ? equidia.selections.indexWhere((s) => s.numPartant == p.numero) + 1
              : 0;
          return _FullRankRow(
            participant: p,
            rank: rank,
            score: score,
            inEquidia: inEquidia,
            equidiaRank: equidiaRank,
          );
        }),

        const SizedBox(height: 14),

        // ─ Notre recommandation finale ─
        _FinalRecommendation(data: data),

        const SizedBox(height: 14),

        // ─ Simulateur de gain (avec choix IA / Equidia) ─
        GainSimulatorWidget(
          rec: data.recommendation,
          nbPartants: data.participants.length,
          equidia: data.equidia,
          participants: data.participants,
        ),

        const SizedBox(height: 12),

        // Bouton voir la course
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => RaceDetailScreen(numReunion: rec.course.numReunion, numOrdre: rec.course.numOrdre, hippodrome: rec.hippodrome, dateStr: provider.dateStr),
          )),
          icon: const Icon(Icons.visibility, size: 16),
          label: const Text('Voir tous les partants'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF4CAF7D),
            side: const BorderSide(color: Color(0xFF2E7D52)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            minimumSize: const Size(double.infinity, 40),
          ),
        ),
      ]),
    );
  }
}

// ─── Analyse de convergence détaillée ────────────────────────────────────────

class _ConvergenceAnalysis extends StatelessWidget {
  final _ComparaisonData data;
  const _ConvergenceAnalysis({required this.data});

  @override
  Widget build(BuildContext context) {
    final equidia = data.equidia!;
    final rec = data.recommendation;

    // Trouver le numéro Equidia 1er et sa position dans le classement IA
    final equidiaGagnantNum = equidia.selections.first.numPartant;
    final iaRankOfEquidiaGagnant = rec.ranked.indexWhere((p) => p.numero == equidiaGagnantNum) + 1;

    // Position IA gagnant dans classement Equidia
    final iaGagnantNum = rec.gagnant?.numero ?? 0;
    final equidiaRankOfIaGagnant = equidia.selections.indexWhere((s) => s.numPartant == iaGagnantNum) + 1;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: data.verdictColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: data.verdictColor.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('⚖️ Analyse de convergence', style: TextStyle(color: data.verdictColor, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),

        // Gagnant IA dans classement Equidia
        _ConvergenceLine(
          icon: '🤖',
          label: 'Notre favori IA (N°$iaGagnantNum ${rec.gagnant?.nom ?? "?"}) est classé',
          value: equidiaRankOfIaGagnant > 0 ? '${equidiaRankOfIaGagnant}e chez Equidia' : 'hors sélection Equidia',
          color: equidiaRankOfIaGagnant == 1 ? const Color(0xFF4CAF7D) : equidiaRankOfIaGagnant <= 3 && equidiaRankOfIaGagnant > 0 ? const Color(0xFFFFB74D) : const Color(0xFFEF9A9A),
        ),
        const SizedBox(height: 6),

        // Gagnant Equidia dans classement IA
        _ConvergenceLine(
          icon: '📺',
          label: 'Favori Equidia (N°$equidiaGagnantNum) est classé',
          value: iaRankOfEquidiaGagnant > 0 ? '${iaRankOfEquidiaGagnant}e dans notre IA' : 'non analysé',
          color: iaRankOfEquidiaGagnant == 1 ? const Color(0xFF4CAF7D) : iaRankOfEquidiaGagnant <= 3 ? const Color(0xFFFFB74D) : const Color(0xFFEF9A9A),
        ),
        const SizedBox(height: 6),

        // Chevaux en commun top 3
        _ConvergenceLine(
          icon: '🔗',
          label: 'Chevaux en commun (top 3)',
          value: '${data.chevauxEnCommun}/3',
          color: data.chevauxEnCommun >= 2 ? const Color(0xFF4CAF7D) : data.chevauxEnCommun == 1 ? const Color(0xFFFFB74D) : const Color(0xFFEF9A9A),
        ),
      ]),
    );
  }
}

class _ConvergenceLine extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color color;
  const _ConvergenceLine({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(icon, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 6),
      Expanded(child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 14))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
      ),
    ]);
  }
}

// ─── Ligne de classement complet ─────────────────────────────────────────────

class _FullRankRow extends StatelessWidget {
  final PmuParticipant participant;
  final int rank;
  final double score;
  final bool inEquidia;
  final int equidiaRank;
  const _FullRankRow({required this.participant, required this.rank, required this.score, required this.inEquidia, required this.equidiaRank});

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final pct = (score / 100).clamp(0.0, 1.0);
    final iaColor = pct >= 0.55 ? const Color(0xFF4CAF7D) : pct >= 0.35 ? const Color(0xFFFFB74D) : const Color(0xFFEF9A9A);
    final medals = {1: '🥇', 2: '🥈', 3: '🥉'};

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2818).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: inEquidia && equidiaRank <= 3
            ? const Color(0xFF42A5F5).withValues(alpha: 0.4)
            : const Color(0xFF1A4731)),
      ),
      child: Row(children: [
        // Rang IA
        Text(medals[rank] ?? '$rank.', style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(color: const Color(0xFF1A4731), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF2E7D52))),
          child: Center(child: Text('${p.numero}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.nom, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          Row(children: [
            Text('Cote: ${p.coteAffichee > 0 ? p.coteAffichee.toStringAsFixed(1) : "-"}', style: const TextStyle(color: Colors.white38, fontSize: 13)),
            if (inEquidia) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('📺 Eq.${equidiaRank}', style: const TextStyle(color: Color(0xFF64B5F6), fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
        ])),
        // Score IA + barre
        SizedBox(width: 60, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${score.toStringAsFixed(0)}pts IA', style: TextStyle(color: iaColor, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: pct, backgroundColor: const Color(0xFF1A4731), valueColor: AlwaysStoppedAnimation<Color>(iaColor), minHeight: 5),
          ),
        ])),
      ]),
    );
  }
}

// ─── Recommandation finale synthèse ──────────────────────────────────────────

class _FinalRecommendation extends StatelessWidget {
  final _ComparaisonData data;
  const _FinalRecommendation({required this.data});

  @override
  Widget build(BuildContext context) {
    final rec = data.recommendation;
    final equidia = data.equidia;
    final conv = data.scoreConvergence;

    // Logique de recommandation finale
    String conseil;
    String details;
    Color color;
    String cheval;

    if (equidia == null || equidia.isEmpty) {
      // Seulement IA disponible
      cheval = rec.gagnant != null ? 'N°${rec.gagnant!.numero} ${rec.gagnant!.nom}' : '-';
      conseil = '🤖 Suivre l\'IA';
      details = 'Pronostic Equidia non disponible — misez sur notre sélection IA';
      color = const Color(0xFF4CAF7D);
    } else if (data.accordGagnant) {
      // Double accord → fort signal
      cheval = rec.gagnant != null ? 'N°${rec.gagnant!.numero} ${rec.gagnant!.nom}' : '-';
      conseil = '🔥 Misez FORT';
      details = 'IA et Equidia sont unanimes sur ce cheval — signal très fort !';
      color = const Color(0xFF4CAF7D);
    } else if (conv >= 50) {
      // Accord partiel → signal modéré
      cheval = rec.gagnant != null ? 'N°${rec.gagnant!.numero} ${rec.gagnant!.nom}' : '-';
      conseil = '✅ Bon signal';
      details = '${data.chevauxEnCommun} cheval(aux) en commun — notre IA reste favori';
      color = const Color(0xFF81C784);
    } else {
      // Désaccord → prudence, jouer les 2
      final equidiaNum = equidia.selections.first.numPartant;
      final iaNum = rec.gagnant?.numero ?? 0;
      cheval = 'N°$iaNum (IA) ou N°$equidiaNum (Equidia)';
      conseil = '⚠️ Jouer les 2';
      details = 'Désaccord IA/Equidia — couvrir les 2 favoris en Placé pour sécuriser';
      color = const Color(0xFFFFB74D);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(conseil, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.5))),
            child: Text('Conv. ${conv}%', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(cheval, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(details, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 14)),
      ]),
    );
  }
}

// ─── Widgets utilitaires ──────────────────────────────────────────────────────

class _HeureChip extends StatelessWidget {
  final String heure;
  const _HeureChip({required this.heure});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFF0D2818), borderRadius: BorderRadius.circular(8)),
      child: Text(heure, style: const TextStyle(color: Color(0xFF4CAF7D), fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}

class _HorseChip extends StatelessWidget {
  final int numero;
  final String nom;
  final int rang;
  final double cote;
  final String coteLabel;
  final Color color;
  final bool isFirst;
  const _HorseChip({required this.numero, required this.nom, required this.rang, required this.cote, this.coteLabel = '', required this.color, required this.isFirst});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isFirst ? color.withValues(alpha: 0.2) : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isFirst ? color : color.withValues(alpha: 0.4), width: isFirst ? 1.5 : 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$numero', style: TextStyle(color: isFirst ? color : Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nom.length > 10 ? '${nom.substring(0, 10)}…' : nom, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(coteLabel.isNotEmpty ? coteLabel : (cote > 0 ? '${cote.toStringAsFixed(1)}' : '-'),
              style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 14)),
        ]),
      ]),
    );
  }
}

class _ConseilBadge extends StatelessWidget {
  final ConseilType conseil;
  final int confiance;
  const _ConseilBadge({required this.conseil, required this.confiance});

  @override
  Widget build(BuildContext context) {
    Color color;
    String emoji;
    switch (conseil) {
      case ConseilType.excellent: color = const Color(0xFF4CAF7D); emoji = '🔥';
      case ConseilType.bon: color = const Color(0xFF81C784); emoji = '✅';
      case ConseilType.moyen: color = const Color(0xFFFFB74D); emoji = '⚠️';
      case ConseilType.incertain: color = const Color(0xFFEF9A9A); emoji = '❓';
      case ConseilType.insuffisant: color = const Color(0xFF9E9E9E); emoji = '—';
    }
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.6))),
        child: Text('$emoji $confiance%', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
      ),
    ]);
  }
}

// ─── États ────────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) {
    return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      CircularProgressIndicator(color: Color(0xFFFFD700)),
      SizedBox(height: 16),
      Text('⚖️ Chargement de la comparaison...', style: TextStyle(color: Colors.white54, fontSize: 15)),
      SizedBox(height: 6),
      Text('Récupération des pronostics IA et Equidia', style: TextStyle(color: Colors.white30, fontSize: 14)),
    ]));
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.error_outline, color: Color(0xFFEF5350), size: 48),
      const SizedBox(height: 12),
      Text(message, style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: onRetry, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D52)), child: const Text('Réessayer')),
    ]));
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) {
    return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('⚖️', style: TextStyle(fontSize: 54)),
      SizedBox(height: 16),
      Text('Aucune course à comparer', style: TextStyle(color: Colors.white54, fontSize: 16)),
    ]));
  }
}
