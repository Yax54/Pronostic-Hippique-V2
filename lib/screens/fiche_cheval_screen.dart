// ═══════════════════════════════════════════════════════════════════
//  FICHE CHEVAL SCREEN — Pronostic Hippique v1.0 (Lot 3)
//
//  Affiche l'historique complet d'un cheval :
//   • En-tête : nom, entraîneur, jockey, statistiques globales
//   • Graphique de forme (CustomPainter, pas de dépendance externe)
//   • Historique des performances par hippodrome et distance
//   • Score ELO actuel + tendance
//   • Bouton "Suivre ce cheval" (alerte quand il court)
//
//  Ouverture depuis : course_detail_screen, races_screen, conseils_screen
//  Usage : Navigator.push(context, MaterialPageRoute(
//    builder: (_) => FicheChevalScreen(partant: p, courseActuelle: course)))
// ═══════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/zt_models.dart';
import '../services/elo_service.dart';
import '../widgets/ia/ia_speech_widget.dart'; // ★ v9.85

class FicheChevalScreen extends StatefulWidget {
  final ZtPartant partant;
  final ZtCourse? courseActuelle;

  const FicheChevalScreen({
    super.key,
    required this.partant,
    this.courseActuelle,
  });

  @override
  State<FicheChevalScreen> createState() => _FicheChevalScreenState();
}

class _FicheChevalScreenState extends State<FicheChevalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _suivi = false;

  static const _gold  = Color(0xFFFFD700);
  static const _green = Color(0xFF4CAF7D);
  static const _dark  = Color(0xFF0A1628);
  static const _card  = Color(0xFF111F30);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _chargerSuivi();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _chargerSuivi() async {
    final prefs = await SharedPreferences.getInstance();
    final suivis = prefs.getStringList('chevaux_suivis_v1') ?? [];
    setState(() => _suivi = suivis.contains(_cleCheval));
  }

  Future<void> _toggleSuivi() async {
    final prefs  = await SharedPreferences.getInstance();
    final suivis = (prefs.getStringList('chevaux_suivis_v1') ?? []).toSet();
    if (_suivi) {
      suivis.remove(_cleCheval);
    } else {
      suivis.add(_cleCheval);
    }
    await prefs.setStringList('chevaux_suivis_v1', suivis.toList());
    setState(() => _suivi = !_suivi);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_suivi
            ? '🔔 ${widget.partant.nom} suivi — vous serez alerté à sa prochaine course'
            : '🔕 ${widget.partant.nom} retiré des chevaux suivis'),
        backgroundColor: _suivi ? const Color(0xFF1B5E20) : Colors.grey.shade800,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  String get _cleCheval =>
      widget.partant.nom.trim().toUpperCase().replaceAll(' ', '_');

  @override
  Widget build(BuildContext context) {
    final p   = widget.partant;
    // ★ v9.92 : ELO par discipline — on passe le type de course si disponible
    final elo = EloService.instance.getScore(p.nom,
        discipline: widget.courseActuelle?.type ?? '');

    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          p.nom,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          // Bouton Suivre
          IconButton(
            icon: Icon(
              _suivi ? Icons.notifications_active : Icons.notifications_none,
              color: _suivi ? _gold : Colors.white54,
            ),
            tooltip: _suivi ? 'Ne plus suivre' : 'Suivre ce cheval',
            onPressed: _toggleSuivi,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: _gold,
          labelColor: _gold,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart, size: 16), text: 'Forme'),
            Tab(icon: Icon(Icons.place, size: 16), text: 'Hippos'),
            Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Infos'),
          ],
        ),
      ),
      body: Column(children: [
        // ── En-tête compact ──────────────────────────────────────────
        _buildHeader(p, elo),
        // ── Onglets ──────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _FormeTab(partant: p),
              _HippoTab(partant: p),
              _InfosTab(partant: p, elo: elo),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildHeader(ZtPartant p, EloScore elo) {
    final scoreIA = p.scoreIA > 0 ? p.scoreIA : p.scoreForme;
    final scoreColor = scoreIA >= 70
        ? _green
        : scoreIA >= 50
            ? _gold
            : const Color(0xFFEF5350);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: _card,
        border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(children: [
        // Numéro
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scoreColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: scoreColor, width: 2),
          ),
          child: Text(
            p.numero,
            style: TextStyle(
                color: scoreColor,
                fontWeight: FontWeight.bold,
                fontSize: 20),
          ),
        ),
        const SizedBox(width: 14),
        // Infos principales
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(p.nom,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 3),
            if (p.driver.isNotEmpty)
              Text('Jockey/Driver : ${p.driver}',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 13)),
            if (p.entraineur.isNotEmpty)
              Text('Entraîneur : ${p.entraineur}',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 5),
            // Badges
            Wrap(spacing: 6, children: [
              if (p.cote.isNotEmpty)
                _badge('×${p.cote}', Colors.white24, Colors.white54),
              if (p.ageSexe.isNotEmpty)
                _badge(p.ageSexe, Colors.white12, Colors.white38),
              _badge(p.tendanceLabel,
                  p.tendanceForme == TendanceForme.hausse
                      ? _green.withValues(alpha: 0.2)
                      : p.tendanceForme == TendanceForme.baisse
                          ? const Color(0xFFEF5350).withValues(alpha: 0.2)
                          : Colors.white12,
                  p.tendanceForme == TendanceForme.hausse
                      ? _green
                      : p.tendanceForme == TendanceForme.baisse
                          ? const Color(0xFFEF5350)
                          : Colors.white38),
            ]),
          ]),
        ),
        // Score IA
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scoreColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: scoreColor.withValues(alpha: 0.5)),
            ),
            child: Column(children: [
              Text('${scoreIA.round()}',
                  style: TextStyle(
                      color: scoreColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 22)),
              Text('/100',
                  style: TextStyle(
                      color: scoreColor.withValues(alpha: 0.7),
                      fontSize: 11)),
            ]),
          ),
          const SizedBox(height: 4),
          if (elo.nbCourses > 0)
            Text('ELO ${elo.rating.round()}',
                style: const TextStyle(
                    color: Colors.white38, fontSize: 11)),
          // ★ v9.85 : Phrase IA contextuelle (v9.87 : hippodrome enrichi)
          if (scoreIA >= 60) ...[
            const SizedBox(height: 6),
            IaSpeechWidget(
              score: scoreIA,
              nomCheval: p.nom,
              hippodrome: p.hippodromeActuel,
              compact: true,
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _badge(String txt, Color bg, Color fg) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(6)),
        child:
            Text(txt, style: TextStyle(color: fg, fontSize: 11)));
}

// ══════════════════════════════════════════════════════════════════
//  Onglet FORME — Graphique de forme + musique détaillée
// ══════════════════════════════════════════════════════════════════
class _FormeTab extends StatelessWidget {
  final ZtPartant partant;
  const _FormeTab({required this.partant});

  static const _gold  = Color(0xFFFFD700);
  static const _green = Color(0xFF4CAF7D);
  static const _card  = Color(0xFF111F30);

  @override
  Widget build(BuildContext context) {
    final positions = _extrairePositions(partant.musique);
    final score     = partant.scoreFormeLong;
    final tendance  = partant.tendanceForme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Score de forme global ─────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Score de forme (12 courses)',
                    style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 8),
                // Barre de progression
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: score / 100,
                    backgroundColor:
                        Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      score >= 70
                          ? _green
                          : score >= 50
                              ? _gold
                              : const Color(0xFFEF5350),
                    ),
                    minHeight: 10,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${score.round()}/100 — ${partant.tendanceLabel}',
                  style: TextStyle(
                    color: tendance == TendanceForme.hausse
                        ? _green
                        : tendance == TendanceForme.baisse
                            ? const Color(0xFFEF5350)
                            : Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 16),
            // Nb victoires
            Column(children: [
              Text('${partant.nbVictoiresRecentes}',
                  style: const TextStyle(
                      color: _gold,
                      fontSize: 30,
                      fontWeight: FontWeight.bold)),
              const Text('victoires',
                  style:
                      TextStyle(color: Colors.white38, fontSize: 12)),
            ]),
          ]),
        ),

        const SizedBox(height: 16),

        // ★ v9.94 Amél. 4 : Détail des 19 critères IA (top 3 forts / 2 faibles)
        if (partant.scoreIA > 0) _buildDetailCriteres(partant),

        const SizedBox(height: 16),

        // ── Graphique de forme ────────────────────────────────────
        if (positions.isNotEmpty) ...[
          const Text('Graphique de forme',
              style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(height: 10),
          Container(
            height: 160,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: CustomPaint(
              painter: _FormeChartPainter(positions: positions),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 8),
          // Légende
          Row(children: [
            _legendeDot(_green, '1er–3e'),
            const SizedBox(width: 12),
            _legendeDot(_gold, '4e–6e'),
            const SizedBox(width: 12),
            _legendeDot(Colors.white38, '7e+'),
            const SizedBox(width: 12),
            _legendeDot(const Color(0xFFEF5350), 'DQ/Arr'),
          ]),
          const SizedBox(height: 16),
        ],

        // ── Détail musique course par course ──────────────────────
        const Text('Détail des 12 dernières courses',
            style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
        const SizedBox(height: 8),
        ..._buildMusiqueCourses(partant.musique),
      ]),
    );
  }

  Widget _legendeDot(Color c, String label) => Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ]);

  List<({int position, bool penalite})> _extrairePositions(String musique) {
    final tokenRegex = RegExp(
      r'(\()|(\))|([Aa][amhp])|([Dd][abmhp])|([Bb][amhp])|(0[amhp])|(1\d[amhp]|[2-9]\d[amhp]|[1-9][amhp])',
      caseSensitive: true,
    );
    final result = <({int position, bool penalite})>[];
    bool inP = false;
    for (final m in tokenRegex.allMatches(musique)) {
      if (m.group(1) != null) { inP = true;  continue; }
      if (m.group(2) != null) { inP = false; continue; }
      if (inP) continue;
      if (m.group(3) != null || m.group(4) != null ||
          m.group(5) != null || m.group(6) != null) {
        result.add((position: 99, penalite: true));
      } else if (m.group(7) != null) {
        final raw = m.group(7)!;
        final pos = int.tryParse(raw.substring(0, raw.length - 1)) ?? 99;
        result.add((position: pos, penalite: false));
      }
    }
    return result.take(12).toList();
  }

  List<Widget> _buildMusiqueCourses(String musique) {
    final sorties = _extrairePositions(musique);
    if (sorties.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Aucune donnée de musique disponible',
              style: TextStyle(color: Colors.white38, fontSize: 14)),
        )
      ];
    }

    return sorties.asMap().entries.map((entry) {
      final i = entry.key;
      final s = entry.value;
      final Color color;
      final String label;
      if (s.penalite) {
        color = const Color(0xFFEF5350);
        label = 'DQ/Arr';
      } else if (s.position <= 3) {
        color = const Color(0xFF4CAF7D);
        label = '${s.position}e';
      } else if (s.position <= 6) {
        color = _gold;
        label = '${s.position}e';
      } else if (s.position < 99) {
        color = Colors.white38;
        label = '${s.position}e';
      } else {
        color = Colors.white24;
        label = '?';
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: color.withValues(alpha: i == 0 ? 0.6 : 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 32,
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 15),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            i == 0 ? 'Dernière course' : 'Course -${i + 1}',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          if (i == 0) ...[
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Récent',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
      );
    }).toList();
  }

  // ★ v9.94 Amél. 4 : Détail des 19 critères IA (top 3 forts / 2 faibles)
  Widget _buildDetailCriteres(ZtPartant p) {
    // Construire la map nom→score depuis les getters disponibles dans ZtPartant
    // (scoreJockey n'est pas un getter direct — calculé dans ia_pronostic_engine)
    final criteres = <String, double>{
      'Forme':        p.scoreFormeLong,
      'ELO':          p.scoreElo,
      'Entraîneur':   p.scoreEntraineur,
      'Fraîcheur':    p.scoreRepos,
      'Hippodrome':   p.scoreHippodrome,
      'Terrain':      p.scoreTerrain(''),
      'Progression':  p.scoreProgression,
      'Divergence':   p.scoreDivergenceFormeCote,
      'Mouv. cote':   p.scoreMouvementCote,
    };

    // Trier : top 3 forts (score > 55), 2 plus faibles (score < 50)
    final sorted = criteres.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3   = sorted.where((e) => e.value > 55).take(3).toList();
    final faibles = sorted.reversed.where((e) => e.value < 50).take(2).toList();

    if (top3.isEmpty && faibles.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Analyse IA — Points clés',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 10),
        if (top3.isNotEmpty) ...[
          const Text('✅ Points forts',
              style: TextStyle(color: Color(0xFF4CAF7D), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...top3.map((e) => _critereLigne(e.key, e.value, const Color(0xFF4CAF7D))),
          const SizedBox(height: 8),
        ],
        if (faibles.isNotEmpty) ...[
          const Text('⚠️ Points faibles',
              style: TextStyle(color: Color(0xFFEF5350), fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...faibles.map((e) => _critereLigne(e.key, e.value, const Color(0xFFEF5350))),
        ],
      ]),
    );
  }

  Widget _critereLigne(String nom, double score, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        SizedBox(
          width: 90,
          child: Text(nom, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              valueColor: AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.7)),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('${score.round()}', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

// ── CustomPainter pour le graphique de forme ─────────────────────
class _FormeChartPainter extends CustomPainter {
  final List<({int position, bool penalite})> positions;
  const _FormeChartPainter({required this.positions});

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty) return;
    final maxPos = 12; // afficher max 12 positions
    final n      = math.min(positions.length, maxPos);

    final paintGrid = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;

    // Grille horizontale (positions 1, 3, 6, 10+)
    for (final gridPos in [1, 3, 6, 10]) {
      final y = _yForPosition(gridPos, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    // Points et ligne
    final pts = <Offset>[];
    for (int i = 0; i < n; i++) {
      final s   = positions[n - 1 - i]; // ordre chronologique (ancien → récent)
      final x   = size.width * i / (n - 1 == 0 ? 1 : n - 1);
      final pos = s.penalite ? 12 : math.min(s.position, 12);
      final y   = _yForPosition(pos, size.height);
      pts.add(Offset(x, y));
    }

    // Ligne de connexion
    if (pts.length > 1) {
      final paintLine = Paint()
        ..color = const Color(0xFF4CAF7D).withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, paintLine);
    }

    // Points colorés
    for (int i = 0; i < pts.length; i++) {
      final s   = positions[n - 1 - i];
      final pos = s.penalite ? 12 : s.position;
      final Color c;
      if (s.penalite)   c = const Color(0xFFEF5350);
      else if (pos <= 3) c = const Color(0xFF4CAF7D);
      else if (pos <= 6) c = const Color(0xFFFFD700);
      else               c = Colors.white38;

      // Point dernier = plus grand
      final isLast = i == pts.length - 1;
      final radius = isLast ? 7.0 : 5.0;

      canvas.drawCircle(pts[i], radius + 2,
          Paint()..color = c.withValues(alpha: 0.25));
      canvas.drawCircle(pts[i], radius, Paint()..color = c);

      // Label position sur le dernier point
      if (isLast) {
        final label = s.penalite ? 'DQ' : (pos >= 12 ? '12+' : '$pos');
        final tp = TextPainter(
          text: TextSpan(
              text: label,
              style: TextStyle(
                  color: c, fontSize: 10, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas,
            Offset(pts[i].dx - tp.width / 2, pts[i].dy - 20));
      }
    }
  }

  double _yForPosition(int pos, double height) {
    // Position 1 (haut) → y = 10%, position 12+ (bas) → y = 90%
    final clamped = pos.clamp(1, 12).toDouble();
    return height * 0.10 + (height * 0.80) * ((clamped - 1) / 11);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ══════════════════════════════════════════════════════════════════
//  Onglet HIPPODROMES — Performances par circuit
// ══════════════════════════════════════════════════════════════════
class _HippoTab extends StatelessWidget {
  final ZtPartant partant;
  const _HippoTab({required this.partant});

  @override
  Widget build(BuildContext context) {
    final scoreHippo = partant.scoreHippodrome;
    final stats      = partant.statsHippodromeCsv;
    final hippoActuel = partant.hippodromeActuel;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Score hippodrome actuel
        if (hippoActuel.isNotEmpty) ...[
          const Text('Performance sur ce circuit',
              style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111F30),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                const Icon(Icons.place,
                    color: Color(0xFF4CAF7D), size: 18),
                const SizedBox(width: 8),
                Text(hippoActuel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const Spacer(),
                _ScoreBadge(score: scoreHippo),
              ]),
              const SizedBox(height: 12),
              if (stats.isNotEmpty) _buildStatsHippo(stats)
              else
                const Text(
                    'Pas d\'historique disponible sur ce circuit',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 20),
        ],

        // Explication du score
        const Text('Comment le score hippodrome fonctionne',
            style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1520),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: const Text(
            '• 50/100 = pas de données (neutre)\n'
            '• < 3 courses sur ce circuit = 55 (légèrement connu)\n'
            '• Score basé sur taux de victoire (60%) + taux top-3 (40%)\n'
            '• Bonus de confiance si ≥ 10 courses sur ce circuit',
            style: TextStyle(
                color: Colors.white54, fontSize: 12, height: 1.7),
          ),
        ),
      ]),
    );
  }

  Widget _buildStatsHippo(String csv) {
    final parts     = csv.split('|');
    if (parts.length < 3) return const SizedBox();
    final nbCourses = int.tryParse(parts[0]) ?? 0;
    final nbVict    = int.tryParse(parts[1]) ?? 0;
    final nbTop3    = int.tryParse(parts[2]) ?? 0;
    final pctVict   = nbCourses > 0 ? (nbVict / nbCourses * 100).round() : 0;
    final pctTop3   = nbCourses > 0 ? (nbTop3 / nbCourses * 100).round() : 0;

    return Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
      _StatColonne(
          valeur: '$nbCourses', label: 'Courses', color: Colors.white70),
      _StatColonne(
          valeur: '$nbVict',
          label: 'Victoires',
          color: const Color(0xFF4CAF7D)),
      _StatColonne(
          valeur: '$nbTop3',
          label: 'Top 3',
          color: const Color(0xFFFFD700)),
      _StatColonne(
          valeur: '$pctVict%',
          label: 'Taux vic',
          color: const Color(0xFF4CAF7D)),
      _StatColonne(
          valeur: '$pctTop3%',
          label: 'Taux top3',
          color: const Color(0xFFFFB74D)),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════
//  Onglet INFOS — ELO, entraîneur, record, jockey
// ══════════════════════════════════════════════════════════════════
class _InfosTab extends StatelessWidget {
  final ZtPartant partant;
  final EloScore  elo;
  const _InfosTab({required this.partant, required this.elo});

  static const _gold  = Color(0xFFFFD700);
  static const _green = Color(0xFF4CAF7D);
  static const _card  = Color(0xFF111F30);

  @override
  Widget build(BuildContext context) {
    final p = partant;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── ELO ──────────────────────────────────────────────────
        _SectionTitre('Score ELO'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08))),
          child: elo.nbCourses == 0
              ? const Text('Pas encore d\'historique ELO',
                  style: TextStyle(color: Colors.white38))
              : Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(children: [
                    Text(
                      '${elo.rating.round()}',
                      style: const TextStyle(
                          color: _gold,
                          fontSize: 36,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 12),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(elo.niveau,
                          style: const TextStyle(
                              color: _green,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      Text('${elo.nbCourses} courses analysées',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12)),
                    ]),
                    const Spacer(),
                    // Variation mensuelle
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: elo.variationMois >= 0
                            ? _green.withValues(alpha: 0.15)
                            : const Color(0xFFEF5350)
                                .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${elo.variationMois >= 0 ? "+" : ""}${elo.variationMois.round()} ce mois',
                        style: TextStyle(
                          color: elo.variationMois >= 0
                              ? _green
                              : const Color(0xFFEF5350),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  // Barre ELO
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ((elo.rating - 1000) / 1500).clamp(0.0, 1.0),
                      backgroundColor:
                          Colors.white.withValues(alpha: 0.08),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(_gold),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                    Text('1000 (faible)',
                        style: TextStyle(
                            color: Colors.white24, fontSize: 10)),
                    Text('1500 (moyen)',
                        style: TextStyle(
                            color: Colors.white24, fontSize: 10)),
                    Text('2500 (élite)',
                        style: TextStyle(
                            color: Colors.white24, fontSize: 10)),
                  ]),
                ]),
        ),

        const SizedBox(height: 16),

        // ── Entraîneur ────────────────────────────────────────────
        if (p.entraineur.isNotEmpty) ...[
          _SectionTitre('Entraîneur'),
          _InfoCard(children: [
            _InfoRow(
                label: 'Nom',
                value: p.entraineur,
                color: Colors.white),
            if (p.statsEntraineurCsv.isNotEmpty)
              ..._buildStatsEntraineur(p.statsEntraineurCsv),
            _InfoRow(
                label: 'Score IA',
                value: '${p.scoreEntraineur.round()}/100',
                color: p.scoreEntraineur >= 70
                    ? _green
                    : p.scoreEntraineur >= 50
                        ? _gold
                        : Colors.white54),
          ]),
          const SizedBox(height: 16),
        ],

        // ── Jockey / Driver ───────────────────────────────────────
        if (p.driver.isNotEmpty) ...[
          _SectionTitre('Jockey / Driver'),
          _InfoCard(children: [
            _InfoRow(
                label: 'Nom',
                value: p.driver,
                color: Colors.white),
            if (p.statsJockeyCsv.isNotEmpty)
              ..._buildStatsJockey(p.statsJockeyCsv),
          ]),
          const SizedBox(height: 16),
        ],

        // ── Performances générales ────────────────────────────────
        _SectionTitre('Performances'),
        _InfoCard(children: [
          _InfoRow(
              label: 'Gains de carrière',
              value: _formatGains(p.gainsInt)),
          if (p.record.isNotEmpty)
            _InfoRow(label: 'Record', value: p.record),
          _InfoRow(
              label: 'Victoires récentes',
              value: '${p.nbVictoiresRecentes}',
              color: p.nbVictoiresRecentes > 0
                  ? _green
                  : Colors.white54),
          if (p.joursRepos > 0)
            _InfoRow(
                label: 'Repos depuis dernière course',
                value: '${p.joursRepos} jours',
                color: p.joursRepos >= 14 && p.joursRepos <= 35
                    ? _green
                    : Colors.white54),
          if (p.poids > 0)
            _InfoRow(label: 'Poids', value: '${p.poids} kg'),
          if (p.ageSexe.isNotEmpty)
            _InfoRow(label: 'Âge/Sexe', value: p.ageSexe),
        ]),
      ]),
    );
  }

  List<Widget> _buildStatsEntraineur(String csv) {
    final parts = csv.split('|');
    if (parts.length < 2) return [];
    final pctVic = parts.length > 1 ? parts[1] : '?';
    final pctPlc = parts.length > 2 ? parts[2] : '?';
    final nb30j  = parts.length > 3 ? parts[3] : '?';
    return [
      _InfoRow(label: 'Taux victoire',  value: '$pctVic%'),
      _InfoRow(label: 'Taux placé',     value: '$pctPlc%'),
      _InfoRow(label: 'Courses/30 jrs', value: nb30j),
    ];
  }

  List<Widget> _buildStatsJockey(String csv) {
    final parts  = csv.split('|');
    if (parts.length < 2) return [];
    final pctVic = parts.length > 1 ? parts[1] : '?';
    final pctPlc = parts.length > 2 ? parts[2] : '?';
    return [
      _InfoRow(label: 'Taux victoire', value: '$pctVic%'),
      _InfoRow(label: 'Taux placé',    value: '$pctPlc%'),
    ];
  }

  String _formatGains(int g) {
    if (g <= 0) return 'Non renseigné';
    if (g >= 1000000)
      return '${(g / 1000000).toStringAsFixed(1)} M€';
    if (g >= 1000) return '${(g / 1000).toStringAsFixed(0)} k€';
    return '${g} €';
  }
}

// ══════════════════════════════════════════════════════════════════
//  Widgets helpers réutilisables
// ══════════════════════════════════════════════════════════════════
class _SectionTitre extends StatelessWidget {
  final String titre;
  const _SectionTitre(this.titre);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(titre,
            style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      );
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF111F30),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(children: children),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _InfoRow({
    required this.label,
    required this.value,
    this.color = Colors.white,
  });
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ]),
      );
}

class _StatColonne extends StatelessWidget {
  final String valeur;
  final String label;
  final Color  color;
  const _StatColonne(
      {required this.valeur,
      required this.label,
      required this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(valeur,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        const SizedBox(height: 3),
        Text(label,
            style: const TextStyle(
                color: Colors.white38, fontSize: 11)),
      ]);
}

class _ScoreBadge extends StatelessWidget {
  final double score;
  const _ScoreBadge({required this.score});
  @override
  Widget build(BuildContext context) {
    final color = score >= 70
        ? const Color(0xFF4CAF7D)
        : score >= 50
            ? const Color(0xFFFFD700)
            : Colors.white38;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text('${score.round()}/100',
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13)),
    );
  }
}
