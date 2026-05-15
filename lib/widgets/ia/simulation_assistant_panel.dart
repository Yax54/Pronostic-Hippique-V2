// ═══════════════════════════════════════════════════════════════════════════
//  simulation_assistant_panel.dart — Panneau Assistant Simulation ★ v10.32
//
//  LECTURE SEULE — ne modifie aucun poids IA, aucun apprentissage.
//  Améliorations v10.32 :
//    - Score de confiance global 0–100
//    - Alerte incohérence 7j/30j
//    - Alerte sur-apprentissage renforcée
//    - Conseils dynamiques ROI/Top3
//    - Presets discipline-aware (Plat/Trot/Obstacle × prudent/agressif)
//    - Tailles de texte augmentées
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../models/simulation_models.dart';

// ── Suggestions par discipline ───────────────────────────────────────────────

class _Suggestion {
  final String cle;
  final double minMult;
  final double maxMult;
  const _Suggestion(this.cle, this.minMult, this.maxMult);
}

const Map<String, List<_Suggestion>> _suggestionsByDisc = {
  'Plat': [
    _Suggestion('dv', 1.2, 1.4),
    _Suggestion('g',  0.5, 0.8),
    _Suggestion('ds', 0.7, 0.9),
  ],
  'Trot': [
    _Suggestion('ds', 1.2, 1.5),
    _Suggestion('g',  1.1, 1.3),
    _Suggestion('j',  0.7, 0.9),
  ],
  'Obstacle': [
    _Suggestion('f',  1.2, 1.5),
    _Suggestion('hp', 1.2, 1.5),
    _Suggestion('g',  0.5, 0.8),
    _Suggestion('dv', 0.6, 0.8),
  ],
  'Toutes': [
    _Suggestion('dv', 1.1, 1.4),
    _Suggestion('f',  1.1, 1.3),
    _Suggestion('g',  0.7, 0.9),
  ],
};

// ═══════════════════════════════════════════════════════════════════════════
//  Widget principal
// ═══════════════════════════════════════════════════════════════════════════

class SimulationAssistantPanel extends StatelessWidget {
  final String discipline;
  final Map<String, double> mults;
  final SimulationResultat? resultat;
  final List<Map<String, dynamic>> candidats;

  // Callbacks boutons rapides
  final VoidCallback onTestPrudent;
  final VoidCallback onTestAgressif;
  final VoidCallback onReset;
  final VoidCallback onSauvegarder;
  final VoidCallback onExporter;

  const SimulationAssistantPanel({
    super.key,
    required this.discipline,
    required this.mults,
    required this.resultat,
    required this.candidats,
    required this.onTestPrudent,
    required this.onTestAgressif,
    required this.onReset,
    required this.onSauvegarder,
    required this.onExporter,
  });

  // ── Palette ───────────────────────────────────────────────────────────────
  static const Color _panelBg = Color(0xFF0F2540);
  static const Color _gold    = Color(0xFFFFD700);
  static const Color _vert    = Color(0xFF00E676);
  static const Color _rouge   = Color(0xFFEF5350);
  static const Color _orange  = Color(0xFFFF9800);
  static const Color _cyan    = Color(0xFF00E5FF);

  // ── Score de confiance global (0–100) ★ v10.32 ────────────────────────────
  int _scoreConfiance() {
    if (resultat == null) return 0;
    final n = resultat!.avant.nbCourses;

    // Base fiabilité selon nb courses
    int score;
    if (n < 30)       score = 10;
    else if (n < 50)  score = 35;
    else if (n < 150) score = 65;
    else              score = 85;

    // Bonus/malus résultat
    final dTop3 = resultat!.apres.top3 - resultat!.avant.top3;
    final dRoi  = resultat!.apres.roi  - resultat!.avant.roi;
    if (dTop3 > 0) score += 10;
    if (dRoi  > 0) score += 10;

    // Malus incohérence 7j vs 30j
    if (resultat!.avant30j.nbCourses >= 10 && resultat!.avant7j.nbCourses >= 5) {
      final dRoi7  = resultat!.apres7j.roi  - resultat!.avant7j.roi;
      final dRoi30 = resultat!.apres30j.roi - resultat!.avant30j.roi;
      if ((dRoi7 > 5 && dRoi30 < -2) || (dRoi7 < -5 && dRoi30 > 2)) {
        score -= 15;
      }
    }

    // Malus sur-apprentissage
    final nbModifies = mults.values.where((v) => (v - 1.0).abs() > 0.01).length;
    if (nbModifies > 3) score -= 15;
    if (mults.values.any((v) => v > 1.70)) score -= 20;

    return score.clamp(0, 100);
  }

  // ── Alerte incohérence 7j/30j ★ v10.32 ───────────────────────────────────
  String? _alerteIncoherence() {
    if (resultat == null) return null;
    if (resultat!.avant30j.nbCourses < 10 || resultat!.avant7j.nbCourses < 5) return null;
    final dRoi7   = resultat!.apres7j.roi  - resultat!.avant7j.roi;
    final dRoi30  = resultat!.apres30j.roi - resultat!.avant30j.roi;
    final dTop7   = resultat!.apres7j.top3  - resultat!.avant7j.top3;
    final dTop30  = resultat!.apres30j.top3 - resultat!.avant30j.top3;

    if ((dRoi7 > 5 && dRoi30 < -2) || (dRoi7 < -5 && dRoi30 > 2)) {
      return 'Attention : résultat récent atypique, ne pas conclure trop vite.';
    }
    if ((dTop7 > 5 && dTop30 < -2) || (dTop7 < -5 && dTop30 > 2)) {
      return 'Attention : résultat récent atypique, ne pas conclure trop vite.';
    }
    return null;
  }

  // ── Alerte sur-apprentissage ★ v10.32 ─────────────────────────────────────
  String? _alerteSurApprentissage() {
    final nbModifies = mults.values.where((v) => (v - 1.0).abs() > 0.01).length;
    if (nbModifies > 3 ||
        mults.values.any((v) => v > 1.70) ||
        mults.values.any((v) => v < 0.60 && v > 0)) {
      return 'Risque de sur-ajustement : test trop agressif.';
    }
    return null;
  }

  // ── Conseil dynamique ROI/Top3 ★ v10.32 ──────────────────────────────────
  _ConseilDynamique _conseilDynamique() {
    if (resultat == null) {
      return _ConseilDynamique(
        'Ajuste les multiplicateurs puis lance la simulation.',
        Colors.white54,
        Icons.info_outline,
      );
    }
    final dRoi  = resultat!.apres.roi  - resultat!.avant.roi;
    final dTop3 = resultat!.apres.top3 - resultat!.avant.top3;

    if (dRoi > 1.0 && dTop3 > 1.0) {
      return _ConseilDynamique(
        'Piste intéressante à enregistrer.',
        _vert, Icons.trending_up,
      );
    }
    if (dRoi > 1.0 && dTop3 <= 0) {
      return _ConseilDynamique(
        'Plus rentable mais plus risqué.',
        _orange, Icons.show_chart,
      );
    }
    if (dTop3 > 1.0 && dRoi <= 0) {
      return _ConseilDynamique(
        'Plus stable mais moins rentable.',
        _gold, Icons.shield_outlined,
      );
    }
    return _ConseilDynamique(
      'Réglage défavorable.',
      _rouge, Icons.trending_down,
    );
  }

  // ── Badge danger surpondération ───────────────────────────────────────────
  String? _badgeDanger() {
    final extremes = mults.entries.where((e) => e.value >= 1.9).toList();
    final forts    = mults.entries.where((e) => e.value >= 1.6).toList();
    if (extremes.isNotEmpty) {
      final noms = extremes.map((e) =>
          '${kLabelsSimu[e.key] ?? e.key} x${e.value.toStringAsFixed(1)}').join(', ');
      return 'Valeur maximale atteinte sur : $noms';
    }
    if (forts.length >= 3) {
      final noms = forts.map((e) =>
          '${kLabelsSimu[e.key] ?? e.key} x${e.value.toStringAsFixed(1)}').join(', ');
      return '≥ 3 critères très amplifiés : $noms';
    }
    return null;
  }

  // ── Fiabilité ─────────────────────────────────────────────────────────────
  _FiabiliteInfo _fiabilite() {
    final n = resultat?.avant.nbCourses ?? 0;
    if (n == 0)  return _FiabiliteInfo('Aucune simulation lancée.', Colors.white38, 0);
    if (n < 30)  return _FiabiliteInfo('Échantillon trop faible ($n courses) — observe seulement.', _rouge, n);
    if (n < 50)  return _FiabiliteInfo('Résultat indicatif ($n courses) — prudence requise.', _orange, n);
    if (n < 150) return _FiabiliteInfo('Piste intéressante ($n courses) — surveille sur 30j/7j.', _gold, n);
    return _FiabiliteInfo('Résultat exploitable ($n courses) — fiabilité satisfaisante.', _vert, n);
  }

  // ── Lecture résultat ──────────────────────────────────────────────────────
  _LectureResultat _lecture() {
    if (resultat == null) {
      return _LectureResultat('Lance une simulation pour obtenir une lecture.', Colors.white38);
    }
    final dRoi  = resultat!.apres.roi  - resultat!.avant.roi;
    final dTop3 = resultat!.apres.top3 - resultat!.avant.top3;

    String msg;
    Color  col;
    String emoji;
    if (dRoi > 1.0 && dTop3 > 1.0) {
      msg   = 'ROI et Top3 progressent : piste à surveiller.';
      col   = _vert;
      emoji = '🟢';
    } else if (dRoi > 1.0 && dTop3 <= 0) {
      msg   = 'ROI monte mais stabilité baisse.';
      col   = _orange;
      emoji = '🟠';
    } else if (dTop3 > 1.0 && dRoi <= 0) {
      msg   = 'Meilleure stabilité mais rentabilité moindre.';
      col   = _gold;
      emoji = '🟡';
    } else if (dRoi < -1.0 && dTop3 < -1.0) {
      msg   = 'Réglage défavorable.';
      col   = _rouge;
      emoji = '🔴';
    } else {
      msg   = 'Amélioration trop faible pour décider.';
      col   = Colors.white54;
      emoji = '🟡';
    }
    return _LectureResultat(msg, col, emoji: emoji,
        incoherence: _alerteIncoherence());
  }

  // ── Impact dominant ───────────────────────────────────────────────────────
  List<_Impact> _impactsDominants() {
    if (resultat == null) return [];
    final modifies = mults.entries
        .where((e) => (e.value - 1.0).abs() >= 0.15)
        .toList()
      ..sort((a, b) =>
          (b.value - 1.0).abs().compareTo((a.value - 1.0).abs()));
    return modifies.take(4).map((e) {
      final label = kLabelsSimu[e.key] ?? e.key;
      return _Impact(label, e.value - 1.0);
    }).toList();
  }

  // ── Top 5 historique ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> _top5Roi() {
    final list = List<Map<String, dynamic>>.from(candidats)
      ..sort((a, b) {
        final ra = ((a['resultat'] as Map?)?['apres'] as Map?)?['roi'] as num? ?? 0;
        final rb = ((b['resultat'] as Map?)?['apres'] as Map?)?['roi'] as num? ?? 0;
        return rb.compareTo(ra);
      });
    return list.take(5).toList();
  }

  List<Map<String, dynamic>> _top5Stabilite() {
    final list = List<Map<String, dynamic>>.from(candidats)
      ..sort((a, b) {
        final ta = ((a['resultat'] as Map?)?['apres'] as Map?)?['top3'] as num? ?? 0;
        final tb = ((b['resultat'] as Map?)?['apres'] as Map?)?['top3'] as num? ?? 0;
        return tb.compareTo(ta);
      });
    return list.take(5).toList();
  }

  List<Map<String, dynamic>> _top5Outsiders() {
    final list = List<Map<String, dynamic>>.from(candidats)
      ..sort((a, b) {
        final oa = ((a['resultat'] as Map?)?['apres'] as Map?)?['outsiders'] as num? ?? 0;
        final ob = ((b['resultat'] as Map?)?['apres'] as Map?)?['outsiders'] as num? ?? 0;
        return ob.compareTo(oa);
      });
    return list.take(5).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final danger      = _badgeDanger();
    final fib         = _fiabilite();
    final lect        = _lecture();
    final conseil     = _conseilDynamique();
    final impacts     = _impactsDominants();
    final suggs       = _suggestionsByDisc[discipline] ?? _suggestionsByDisc['Toutes']!;
    final score       = _scoreConfiance();
    final alerteSura  = _alerteSurApprentissage();

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cyan.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const Divider(color: Colors.white12, height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Score de confiance ★ v10.32 ──────────────────────────
                _buildScoreConfiance(score),
                const SizedBox(height: 14),

                // ── Badge danger ─────────────────────────────────────────
                if (danger != null) ...[
                  _buildBadgeDanger(danger),
                  const SizedBox(height: 12),
                ],

                // ── Alerte sur-apprentissage ★ v10.32 ────────────────────
                if (alerteSura != null) ...[
                  _buildAlerteBox(alerteSura, _rouge, Icons.psychology_alt_outlined),
                  const SizedBox(height: 12),
                ],

                // ── Alerte incohérence ★ v10.32 ──────────────────────────
                if (lect.incoherence != null) ...[
                  _buildAlerteBox(lect.incoherence!, _orange, Icons.warning_amber_rounded),
                  const SizedBox(height: 12),
                ],

                // ── Boutons rapides ──────────────────────────────────────
                _buildBoutonsRapides(),
                const SizedBox(height: 14),

                // ── 1. Fiabilité ─────────────────────────────────────────
                _buildSection('1 · État de fiabilité', fib.color,
                  child: _buildFiabilite(fib)),
                const SizedBox(height: 12),

                // ── 2. Lecture résultat + conseil dynamique ───────────────
                _buildSection('2 · Lecture automatique', lect.color,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(lect.emoji ?? '', style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(lect.message,
                              style: TextStyle(
                                color: lect.color,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              )),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(conseil.icon, color: conseil.color, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(conseil.message,
                              style: TextStyle(
                                color: conseil.color,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              )),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── 3. Impact dominant ───────────────────────────────────
                if (impacts.isNotEmpty) ...[
                  _buildSection('3 · Impact dominant', _cyan,
                    child: _buildImpacts(impacts)),
                  const SizedBox(height: 12),
                ],

                // ── 4. Suggestions discipline ────────────────────────────
                _buildSection('4 · Suggestions — $discipline', Colors.white54,
                  child: _buildSuggestions(suggs)),
                const SizedBox(height: 12),

                // ── 5. Top 5 historique ──────────────────────────────────
                if (candidats.isNotEmpty) ...[
                  _buildSection('5 · Meilleurs candidats sauvegardés', _gold,
                    child: _buildTop5()),
                  const SizedBox(height: 12),
                ],

                // ── Boutons Export + Enregistrer ─────────────────────────
                if (resultat != null) _buildBoutonsResultat(),

                // ── Pied lecture seule ───────────────────────────────────
                const SizedBox(height: 10),
                _buildPiedLecture(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── En-tête ────────────────────────────────────────────────────────────────
  Widget _buildHeader() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: _cyan.withValues(alpha: 0.08),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    ),
    child: Row(
      children: [
        const Icon(Icons.auto_awesome, color: _cyan, size: 20),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('Assistant Simulation',
            style: TextStyle(color: _cyan, fontSize: 17, fontWeight: FontWeight.bold)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
          ),
          child: const Text('Lecture seule',
            style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  // ── Score de confiance ★ v10.32 ────────────────────────────────────────────
  Widget _buildScoreConfiance(int score) {
    final color = score >= 70
        ? _vert
        : score >= 45
            ? _gold
            : score >= 20
                ? _orange
                : _rouge;
    final label = score >= 70
        ? 'Fiable'
        : score >= 45
            ? 'Indicatif'
            : score >= 20
                ? 'Faible'
                : 'Insuffisant';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined, color: color, size: 18),
              const SizedBox(width: 8),
              Text('Score de confiance',
                style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('$score / 100',
                style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(label,
                  style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: score / 100.0,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  // ── Badge danger surpondération ────────────────────────────────────────────
  Widget _buildBadgeDanger(String msg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _rouge.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _rouge.withValues(alpha: 0.6)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, color: _rouge, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Risque de surpondération extrême',
                style: TextStyle(color: _rouge, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 5),
              const Text(
                'Un résultat positif peut être dû au sur-apprentissage, pas à une vraie amélioration.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ── Alerte générique ★ v10.32 ──────────────────────────────────────────────
  Widget _buildAlerteBox(String msg, Color color, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(msg,
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  // ── Boutons rapides ────────────────────────────────────────────────────────
  Widget _buildBoutonsRapides() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Actions rapides',
        style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 7,
        children: [
          _btnRapide('🛡️ Test prudent',      _vert,         onTestPrudent),
          _btnRapide('🚀 Test agressif',     _rouge,        onTestAgressif),
          _btnRapide('↺ Réinitialiser',      Colors.white54, onReset),
          _btnRapide('📋 Enregistrer piste', _cyan,         onSauvegarder),
          _btnRapide('🖼 Export PNG',         _gold,         onExporter),
        ],
      ),
    ],
  );

  Widget _btnRapide(String label, Color col, VoidCallback cb) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      foregroundColor: col,
      side: BorderSide(color: col.withValues(alpha: 0.65)),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: cb,
    child: Text(label, style: TextStyle(fontSize: 13, color: col, fontWeight: FontWeight.w600)),
  );

  // ── Section générique ──────────────────────────────────────────────────────
  Widget _buildSection(String titre, Color titreColor, {required Widget child}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(titre, style: TextStyle(
        color: titreColor,
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.4,
      )),
      const SizedBox(height: 6),
      child,
    ],
  );

  // ── Fiabilité visuelle ─────────────────────────────────────────────────────
  Widget _buildFiabilite(_FiabiliteInfo fib) {
    final n = fib.nbCourses;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(fib.message,
          style: TextStyle(color: fib.color, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: n == 0 ? 0 : (n / 200.0).clamp(0.0, 1.0),
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(fib.color),
            minHeight: 7,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('<30', style: TextStyle(color: Colors.white24, fontSize: 10)),
            Text('30',  style: TextStyle(color: Colors.white24, fontSize: 10)),
            Text('50',  style: TextStyle(color: Colors.white24, fontSize: 10)),
            Text('150+',style: TextStyle(color: Colors.white24, fontSize: 10)),
          ],
        ),
      ],
    );
  }

  // ── Impact dominant ────────────────────────────────────────────────────────
  Widget _buildImpacts(List<_Impact> impacts) {
    final positifs = impacts.where((i) => i.delta > 0).toList();
    final negatifs = impacts.where((i) => i.delta < 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Critères avec le plus grand écart par rapport au neutre :',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 6),
        if (positifs.isNotEmpty)
          Wrap(spacing: 7, runSpacing: 5,
            children: positifs.map((i) => _chipImpact(i, _vert)).toList()),
        if (negatifs.isNotEmpty) ...[
          const SizedBox(height: 5),
          Wrap(spacing: 7, runSpacing: 5,
            children: negatifs.map((i) => _chipImpact(i, _rouge)).toList()),
        ],
        const SizedBox(height: 6),
        const Text(
          'Modifie un seul critère à la fois pour isoler son impact réel.',
          style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _chipImpact(_Impact i, Color col) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: col.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: col.withValues(alpha: 0.4)),
    ),
    child: Text(
      '${i.delta > 0 ? "+" : ""}${(i.delta * 100).round()}%  ${i.label}',
      style: TextStyle(color: col, fontSize: 13, fontWeight: FontWeight.bold),
    ),
  );

  // ── Suggestions discipline ─────────────────────────────────────────────────
  Widget _buildSuggestions(List<_Suggestion> suggs) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ...suggs.map((s) {
        final label = kLabelsSimu[s.cle] ?? s.cle;
        final actif = (mults[s.cle] ?? 1.0) != 1.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(
                actif ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                size: 15,
                color: actif ? _vert : Colors.white24,
              ),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(
                color: actif ? _vert : Colors.white70,
                fontSize: 14,
                fontWeight: actif ? FontWeight.w600 : FontWeight.normal,
              )),
              const Spacer(),
              Text(
                'x${s.minMult.toStringAsFixed(1)} → x${s.maxMult.toStringAsFixed(1)}',
                style: TextStyle(
                  color: actif ? _vert : Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }),
      const SizedBox(height: 5),
      const Text(
        'Plages recommandées selon le comportement historique de la discipline.',
        style: TextStyle(color: Colors.white24, fontSize: 11, fontStyle: FontStyle.italic),
      ),
    ],
  );

  // ── Top 5 historique ───────────────────────────────────────────────────────
  Widget _buildTop5() {
    final roi       = _top5Roi();
    final stabilite = _top5Stabilite();
    final outsiders = _top5Outsiders();
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            unselectedLabelStyle: TextStyle(fontSize: 13),
            labelColor: _gold,
            unselectedLabelColor: Colors.white38,
            indicatorColor: _gold,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: '📈 ROI'),
              Tab(text: '🎯 Stabilité'),
              Tab(text: '🎲 Outsiders'),
            ],
          ),
          SizedBox(
            height: roi.isEmpty ? 44 : (roi.length * 48.0).clamp(48, 240),
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _listeTop5(roi,       'roi'),
                _listeTop5(stabilite, 'top3'),
                _listeTop5(outsiders, 'outsiders'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listeTop5(List<Map<String, dynamic>> items, String metrique) {
    if (items.isEmpty) {
      return const Center(
        child: Text('Aucun candidat sauvegardé.',
          style: TextStyle(color: Colors.white38, fontSize: 13)));
    }
    return ListView.builder(
      itemCount: items.length,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemBuilder: (ctx, i) {
        final c     = items[i];
        final nom   = c['nom'] as String? ?? '—';
        final res   = (c['resultat'] as Map?) ?? {};
        final apres = (res['apres'] as Map?) ?? {};
        final val   = (apres[metrique] as num?)?.toDouble() ?? 0.0;
        final disc  = ((res['params'] as Map?)?['discipline'] as String?) ?? '—';
        final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i + 1}.';
        final suffix = metrique == 'roi' || metrique == 'top3' ? '%' : '';
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Text(medal, style: const TextStyle(fontSize: 16)),
          title: Text(nom,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            overflow: TextOverflow.ellipsis),
          subtitle: Text(disc,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
          trailing: Text(
            '${val.toStringAsFixed(1)}$suffix',
            style: const TextStyle(color: _gold, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }

  // ── Boutons Export + Enregistrer piste ★ v10.32 ────────────────────────────
  Widget _buildBoutonsResultat() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: const BorderSide(color: _gold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.share, size: 17),
              label: const Text('Export PNG', style: TextStyle(fontSize: 14)),
              onPressed: onExporter,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.bookmark_add, size: 17, color: Colors.white),
              label: const Text('Enregistrer comme piste',
                style: TextStyle(color: Colors.white, fontSize: 13)),
              onPressed: onSauvegarder,
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      const Center(
        child: Text(
          'Ne modifie pas l\'IA réelle.',
          style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
        ),
      ),
    ],
  );

  // ── Pied lecture seule ─────────────────────────────────────────────────────
  Widget _buildPiedLecture() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.blue.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.blue.withValues(alpha: 0.20)),
    ),
    child: const Row(
      children: [
        Icon(Icons.lock_outline, color: Colors.blue, size: 14),
        SizedBox(width: 7),
        Expanded(
          child: Text(
            'Lecture seule — aucune modification IA réelle · Enregistrer = SharedPreferences uniquement',
            style: TextStyle(color: Colors.blue, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

// ── Data classes internes ─────────────────────────────────────────────────────

class _FiabiliteInfo {
  final String message;
  final Color  color;
  final int    nbCourses;
  const _FiabiliteInfo(this.message, this.color, this.nbCourses);
}

class _LectureResultat {
  final String  message;
  final Color   color;
  final String? emoji;
  final String? incoherence;
  const _LectureResultat(this.message, this.color, {this.emoji, this.incoherence});
}

class _Impact {
  final String label;
  final double delta;
  const _Impact(this.label, this.delta);
}

class _ConseilDynamique {
  final String  message;
  final Color   color;
  final IconData icon;
  const _ConseilDynamique(this.message, this.color, this.icon);
}
