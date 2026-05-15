// ═══════════════════════════════════════════════════════════════════════════
//  simulation_assistant_panel.dart — Panneau Assistant contextuel
//
//  LECTURE SEULE — guide l'utilisateur sans jamais modifier les poids IA.
//  Mise à jour dynamique selon : discipline, résultats, échantillon.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../../models/simulation_models.dart';

// ── Données statiques par discipline ────────────────────────────────────────

class _Suggestion {
  final String cle;      // clé courte critère
  final double minMult;
  final double maxMult;
  const _Suggestion(this.cle, this.minMult, this.maxMult);
}

const Map<String, List<_Suggestion>> _suggestionsByDisc = {
  'Plat': [
    _Suggestion('dv', 1.2, 1.4), // Divergence
    _Suggestion('g',  0.5, 0.8), // Gains
    _Suggestion('ds', 0.7, 0.9), // Distance
  ],
  'Trot': [
    _Suggestion('ds', 1.2, 1.5), // Distance
    _Suggestion('g',  1.1, 1.3), // Gains
    _Suggestion('j',  0.7, 0.9), // Jockey
  ],
  'Obstacle': [
    _Suggestion('f',  1.2, 1.5), // Forme
    _Suggestion('hp', 1.2, 1.5), // Hippodrome
    _Suggestion('g',  0.5, 0.8), // Gains
    _Suggestion('dv', 0.6, 0.8), // Divergence
  ],
  'Toutes': [
    _Suggestion('dv', 1.1, 1.4),
    _Suggestion('f',  1.1, 1.3),
    _Suggestion('g',  0.7, 0.9),
  ],
};

// ── Widget principal ─────────────────────────────────────────────────────────

class SimulationAssistantPanel extends StatelessWidget {
  final String           discipline;
  final Map<String, double> mults;          // multiplicateurs actifs
  final SimulationResultat? resultat;
  final List<Map<String, dynamic>> candidats;
  // Callbacks pour les boutons rapides
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

  // ── Helpers ──────────────────────────────────────────────────────────────

  static const Color _panelBg = Color(0xFF0F2540);
  static const Color _gold    = Color(0xFFFFD700);
  static const Color _vert    = Color(0xFF00E676);
  static const Color _rouge   = Color(0xFFEF5350);
  static const Color _orange  = Color(0xFFFF9800);
  static const Color _cyan    = Color(0xFF00E5FF);

  // ── Analyse danger surpondération ────────────────────────────────────────
  /// Retourne null si OK, sinon le message d'alerte danger
  String? _badgeDanger() {
    final extremes = mults.entries.where((e) => e.value >= 1.9).toList();
    final forts    = mults.entries.where((e) => e.value >= 1.6).toList();
    if (extremes.isNotEmpty) {
      final noms = extremes.map((e) => '${kLabelsSimu[e.key] ?? e.key} x${e.value.toStringAsFixed(1)}').join(', ');
      return 'Valeur maximale atteinte sur : $noms';
    }
    if (forts.length >= 3) {
      final noms = forts.map((e) => '${kLabelsSimu[e.key] ?? e.key} x${e.value.toStringAsFixed(1)}').join(', ');
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

  // ── Lecture automatique résultat ─────────────────────────────────────────
  _LectureResultat _lecture() {
    if (resultat == null) return _LectureResultat('Lance une simulation pour obtenir une lecture.', Colors.white38);
    final dRoi  = resultat!.apres.roi  - resultat!.avant.roi;
    final dTop3 = resultat!.apres.top3 - resultat!.avant.top3;
    final dRoi30  = resultat!.apres30j.roi  - resultat!.avant30j.roi;

    // Détection incohérence 7j vs 30j
    String? incoherence;
    if (resultat!.avant30j.nbCourses >= 10 && resultat!.avant7j.nbCourses >= 5) {
      final dRoi7   = resultat!.apres7j.roi  - resultat!.avant7j.roi;
      if ((dRoi7 > 5 && dRoi30 < -2) || (dRoi7 < -5 && dRoi30 > 2)) {
        incoherence = '⚠️ Incohérence 7j/30j : résultat récent atypique — attends plus de données.';
      }
    }

    String msg;
    Color  col;
    if (dRoi > 1.0 && dTop3 > 1.0) {
      msg = 'ROI ↑ et Top3 ↑ — Piste prometteuse.';
      col = _vert;
    } else if (dRoi > 1.0 && dTop3 <= 0) {
      msg = 'ROI ↑ mais Top3 ↓ — Plus rentable mais plus risqué.';
      col = _orange;
    } else if (dTop3 > 1.0 && dRoi <= 0) {
      msg = 'Top3 ↑ mais ROI ↓ — Plus sûr mais moins rentable.';
      col = _gold;
    } else if (dRoi < -1.0 && dTop3 < -1.0) {
      msg = 'ROI ↓ et Top3 ↓ — Réglage défavorable.';
      col = _rouge;
    } else {
      msg = 'Pas d\'amélioration significative — réglage neutre.';
      col = Colors.white54;
    }
    return _LectureResultat(msg, col, incoherence: incoherence);
  }

  // ── Conseil d'action ─────────────────────────────────────────────────────
  String _conseil() {
    if (resultat == null) return 'Ajuste les multiplicateurs puis lance la simulation.';
    final fib  = _fiabilite();
    final lect = _lecture();
    final estPrometteur = lect.message.contains('prometteuse') || lect.message.contains('rentable');
    final estDefavorable = lect.message.contains('Défavorable') || lect.message.contains('défavorable');

    if (fib.nbCourses < 30) {
      return 'Attends d\'avoir ≥ 30 courses dans l\'historique avant d\'interpréter.';
    }
    if (fib.nbCourses < 50) {
      return 'Refais le test avec plus de courses ou attends plus d\'historique.';
    }
    if (estDefavorable) {
      return 'Réinitialise les multiplicateurs ou teste des valeurs plus légères (< 1.3x).';
    }
    if (estPrometteur && fib.nbCourses >= 150) {
      return 'Sauvegarde comme candidat, puis surveille les résultats réels sur 15 jours.';
    }
    if (estPrometteur) {
      return 'Piste intéressante — vérifie la cohérence sur 30j et 7j avant de sauvegarder.';
    }
    return 'Essaie de modifier un seul critère à la fois pour isoler l\'impact.';
  }

  // ── Impact dominant ──────────────────────────────────────────────────────
  /// Top contributeurs positifs et négatifs (critères éloignés de 1.0)
  List<_Impact> _impactsDominants() {
    if (resultat == null) return [];
    final modifies = mults.entries
        .where((e) => (e.value - 1.0).abs() >= 0.15)
        .toList();
    if (modifies.isEmpty) return [];

    // Estimation simplifiée : |Δ| = |mult - 1.0| * poids relatif
    // On trie par amplitude de modification
    modifies.sort((a, b) => (b.value - 1.0).abs().compareTo((a.value - 1.0).abs()));
    return modifies.take(4).map((e) {
      final label = kLabelsSimu[e.key] ?? e.key;
      final delta = e.value - 1.0;
      return _Impact(label, delta);
    }).toList();
  }

  // ── Top 5 historique ─────────────────────────────────────────────────────
  List<Map<String, dynamic>> _top5Roi() {
    final list = List<Map<String, dynamic>>.from(candidats);
    list.sort((a, b) {
      final ra = ((a['resultat'] as Map?)?['apres'] as Map?)?['roi'] as num? ?? 0;
      final rb = ((b['resultat'] as Map?)?['apres'] as Map?)?['roi'] as num? ?? 0;
      return rb.compareTo(ra);
    });
    return list.take(5).toList();
  }

  List<Map<String, dynamic>> _top5Stabilite() {
    final list = List<Map<String, dynamic>>.from(candidats);
    list.sort((a, b) {
      final ta = ((a['resultat'] as Map?)?['apres'] as Map?)?['top3'] as num? ?? 0;
      final tb = ((b['resultat'] as Map?)?['apres'] as Map?)?['top3'] as num? ?? 0;
      return tb.compareTo(ta);
    });
    return list.take(5).toList();
  }

  List<Map<String, dynamic>> _top5Outsiders() {
    final list = List<Map<String, dynamic>>.from(candidats);
    list.sort((a, b) {
      final oa = ((a['resultat'] as Map?)?['apres'] as Map?)?['outsiders'] as num? ?? 0;
      final ob = ((b['resultat'] as Map?)?['apres'] as Map?)?['outsiders'] as num? ?? 0;
      return ob.compareTo(oa);
    });
    return list.take(5).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final danger   = _badgeDanger();
    final fib      = _fiabilite();
    final lect     = _lecture();
    final conseil  = _conseil();
    final impacts  = _impactsDominants();
    final suggs    = _suggestionsByDisc[discipline] ?? _suggestionsByDisc['Toutes']!;

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cyan.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête panneau ─────────────────────────────────────────────
          _buildHeader(),
          const Divider(color: Colors.white12, height: 1),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Badge danger ─────────────────────────────────────────
                if (danger != null) ...[
                  _buildBadgeDanger(danger),
                  const SizedBox(height: 10),
                ],

                // ── Boutons rapides ──────────────────────────────────────
                _buildBoutonsRapides(),
                const SizedBox(height: 12),

                // ── 1. Fiabilité ─────────────────────────────────────────
                _buildSection('1 · État de fiabilité', fib.color,
                  child: _buildFiabilite(fib),
                ),
                const SizedBox(height: 10),

                // ── 2. Lecture résultat ──────────────────────────────────
                _buildSection('2 · Lecture automatique', lect.color,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lect.message,
                        style: TextStyle(color: lect.color, fontSize: 13, fontWeight: FontWeight.w600)),
                      if (lect.incoherence != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _rouge.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _rouge.withValues(alpha: 0.4)),
                          ),
                          child: Text(lect.incoherence!,
                            style: const TextStyle(color: _rouge, fontSize: 11)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // ── 3. Conseil d'action ──────────────────────────────────
                _buildSection('3 · Conseil d\'action', Colors.white70,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.assistant_outlined, color: _cyan, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(conseil,
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // ── Impact dominant ──────────────────────────────────────
                if (impacts.isNotEmpty) ...[
                  _buildSection('4 · Impact dominant détecté', _cyan,
                    child: _buildImpacts(impacts),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── 5. Suggestions discipline ────────────────────────────
                _buildSection('5 · Suggestions — $discipline', Colors.white54,
                  child: _buildSuggestions(suggs),
                ),
                const SizedBox(height: 10),

                // ── 6. Sur-apprentissage ─────────────────────────────────
                _buildSurApprentissage(),
                const SizedBox(height: 10),

                // ── 7. Top 5 historique ──────────────────────────────────
                if (candidats.isNotEmpty) ...[
                  _buildSection('6 · Meilleurs candidats sauvegardés', _gold,
                    child: _buildTop5(),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Boutons Export + Sauvegarder ──────────────────────────
                if (resultat != null) _buildBoutonsResultat(),

                // ── Pied lecture seule ───────────────────────────────────
                const SizedBox(height: 8),
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
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: _cyan.withValues(alpha: 0.08),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
    ),
    child: Row(
      children: [
        const Icon(Icons.auto_awesome, color: _cyan, size: 18),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('Assistant Simulation',
            style: TextStyle(color: _cyan, fontSize: 14, fontWeight: FontWeight.bold)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
          ),
          child: const Text('Lecture seule',
            style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

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
        const Icon(Icons.warning_amber_rounded, color: _rouge, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⚠️ Risque de surpondération extrême',
                style: TextStyle(color: _rouge, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 4),
              const Text(
                'Un résultat positif peut être dû au sur-apprentissage, pas à une vraie amélioration.',
                style: TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ── Boutons rapides ────────────────────────────────────────────────────────
  Widget _buildBoutonsRapides() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Actions rapides',
        style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
      const SizedBox(height: 7),
      Wrap(
        spacing: 7,
        runSpacing: 6,
        children: [
          _btnRapide('🛡️ Prudent',   _vert,   onTestPrudent),
          _btnRapide('🚀 Agressif',  _rouge,  onTestAgressif),
          _btnRapide('↺ Réinitialiser', Colors.white54, onReset),
        ],
      ),
    ],
  );

  Widget _btnRapide(String label, Color col, VoidCallback cb) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      foregroundColor: col,
      side: BorderSide(color: col.withValues(alpha: 0.6)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: cb,
    child: Text(label, style: TextStyle(fontSize: 11, color: col, fontWeight: FontWeight.w600)),
  );

  // ── Section générique ──────────────────────────────────────────────────────
  Widget _buildSection(String titre, Color titreColor, {required Widget child}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(titre, style: TextStyle(
        color: titreColor,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.4,
      )),
      const SizedBox(height: 5),
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
          style: TextStyle(color: fib.color, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        // Barre de progression fiabilité
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: n == 0 ? 0 : (n / 200.0).clamp(0.0, 1.0),
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation<Color>(fib.color),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('<30', style: TextStyle(color: Colors.white24, fontSize: 9)),
            Text('30',  style: TextStyle(color: Colors.white24, fontSize: 9)),
            Text('50',  style: TextStyle(color: Colors.white24, fontSize: 9)),
            Text('150+',style: TextStyle(color: Colors.white24, fontSize: 9)),
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
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 5),
        if (positifs.isNotEmpty)
          Wrap(
            spacing: 6, runSpacing: 4,
            children: positifs.map((i) => _chipImpact(i, _vert)).toList(),
          ),
        if (negatifs.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6, runSpacing: 4,
            children: negatifs.map((i) => _chipImpact(i, _rouge)).toList(),
          ),
        ],
        const SizedBox(height: 5),
        const Text(
          'Modifie un seul critère à la fois pour isoler son impact réel.',
          style: TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _chipImpact(_Impact i, Color col) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: col.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: col.withValues(alpha: 0.4)),
    ),
    child: Text(
      '${i.delta > 0 ? "+" : ""}${(i.delta * 100).round()}%  ${i.label}',
      style: TextStyle(color: col, fontSize: 11, fontWeight: FontWeight.bold),
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
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(
                actif ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                size: 13,
                color: actif ? _vert : Colors.white24,
              ),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                color: actif ? _vert : Colors.white70,
                fontSize: 12,
                fontWeight: actif ? FontWeight.w600 : FontWeight.normal,
              )),
              const Spacer(),
              Text(
                'x${s.minMult.toStringAsFixed(1)} → x${s.maxMult.toStringAsFixed(1)}',
                style: TextStyle(
                  color: actif ? _vert : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }),
      const SizedBox(height: 4),
      const Text(
        'Plages recommandées selon le comportement historique de la discipline.',
        style: TextStyle(color: Colors.white24, fontSize: 10, fontStyle: FontStyle.italic),
      ),
    ],
  );

  // ── Avertissement sur-apprentissage ────────────────────────────────────────
  Widget _buildSurApprentissage() {
    final nbMultsForts = mults.values.where((v) => (v - 1.0).abs() >= 0.4).length;
    final couleur = nbMultsForts >= 3 ? _rouge : _orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: couleur.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_alt_outlined, color: couleur, size: 14),
              const SizedBox(width: 6),
              Text('Risque de sur-apprentissage',
                style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('$nbMultsForts critère(s) ≥ ±40%',
                style: TextStyle(color: couleur, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Un bon résultat sur l\'historique complet peut ne pas se reproduire en conditions réelles. '
            'Validez toujours sur 30j et 7j avant de conclure.',
            style: TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }

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
            labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            unselectedLabelStyle: TextStyle(fontSize: 11),
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
            height: roi.isEmpty ? 40 : (roi.length * 44.0).clamp(44, 220),
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
          style: TextStyle(color: Colors.white38, fontSize: 11)),
      );
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
          leading: Text(medal, style: const TextStyle(fontSize: 14)),
          title: Text(nom,
            style: const TextStyle(color: Colors.white, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(disc, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          trailing: Text(
            '${val.toStringAsFixed(1)}$suffix',
            style: const TextStyle(color: _gold, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }

  // ── Boutons Export + Sauvegarder ───────────────────────────────────────────
  Widget _buildBoutonsResultat() => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: _gold,
            side: const BorderSide(color: _gold),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          icon: const Icon(Icons.share, size: 15),
          label: const Text('Export PNG', style: TextStyle(fontSize: 12)),
          onPressed: onExporter,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1565C0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          icon: const Icon(Icons.bookmark_add, size: 15, color: Colors.white),
          label: const Text('Sauvegarder candidat',
            style: TextStyle(color: Colors.white, fontSize: 12)),
          onPressed: onSauvegarder,
        ),
      ),
    ],
  );

  // ── Pied de panneau ────────────────────────────────────────────────────────
  Widget _buildPiedLecture() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.blue.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.blue.withValues(alpha: 0.20)),
    ),
    child: const Row(
      children: [
        Icon(Icons.lock_outline, color: Colors.blue, size: 12),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            'Lecture seule — aucune modification IA réelle · Sauvegarde = SharedPreferences uniquement',
            style: TextStyle(color: Colors.blue, fontSize: 10),
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
  final String? incoherence;
  const _LectureResultat(this.message, this.color, {this.incoherence});
}

class _Impact {
  final String label;
  final double delta; // mult - 1.0
  const _Impact(this.label, this.delta);
}
