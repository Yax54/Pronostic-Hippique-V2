// ★ v10.32 — Modèle "piste" sauvegardée depuis le Labo IA Simulation
// Lecture seule : aucun lien avec IaMemoryService ni les poids IA réels.

import 'dart:convert';

class SimulationCandidate {
  final String id;
  final DateTime createdAt;
  final String discipline;      // 'PLAT' | 'TROT' | 'OBSTACLE'
  final String label;           // libellé libre
  final Map<String, double> coefficients; // critère → multiplicateur

  // Métriques avant/après simulation
  final double top1Avant;
  final double top1Apres;
  final double top3Avant;
  final double top3Apres;
  final double top5Avant;
  final double top5Apres;
  final double roiAvant;
  final double roiApres;
  final double gainNetAvant;
  final double gainNetApres;
  final double outsidersAvant;
  final double outsidersApres;

  final int scoreConfiance;   // 0–100
  final String verdict;       // phrase courte
  final String? notes;        // optionnel

  const SimulationCandidate({
    required this.id,
    required this.createdAt,
    required this.discipline,
    required this.label,
    required this.coefficients,
    required this.top1Avant,
    required this.top1Apres,
    required this.top3Avant,
    required this.top3Apres,
    required this.top5Avant,
    required this.top5Apres,
    required this.roiAvant,
    required this.roiApres,
    required this.gainNetAvant,
    required this.gainNetApres,
    required this.outsidersAvant,
    required this.outsidersApres,
    required this.scoreConfiance,
    required this.verdict,
    this.notes,
  });

  // ── Sérialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'discipline': discipline,
    'label': label,
    'coefficients': coefficients,
    'top1Avant': top1Avant,
    'top1Apres': top1Apres,
    'top3Avant': top3Avant,
    'top3Apres': top3Apres,
    'top5Avant': top5Avant,
    'top5Apres': top5Apres,
    'roiAvant': roiAvant,
    'roiApres': roiApres,
    'gainNetAvant': gainNetAvant,
    'gainNetApres': gainNetApres,
    'outsidersAvant': outsidersAvant,
    'outsidersApres': outsidersApres,
    'scoreConfiance': scoreConfiance,
    'verdict': verdict,
    'notes': notes,
  };

  factory SimulationCandidate.fromJson(Map<String, dynamic> j) {
    final rawCoeff = j['coefficients'] as Map<String, dynamic>? ?? {};
    return SimulationCandidate(
      id:             j['id'] as String,
      createdAt:      DateTime.parse(j['createdAt'] as String),
      discipline:     j['discipline'] as String? ?? 'PLAT',
      label:          j['label'] as String? ?? '',
      coefficients:   rawCoeff.map((k, v) => MapEntry(k, (v as num).toDouble())),
      top1Avant:      (j['top1Avant'] as num?)?.toDouble() ?? 0,
      top1Apres:      (j['top1Apres'] as num?)?.toDouble() ?? 0,
      top3Avant:      (j['top3Avant'] as num?)?.toDouble() ?? 0,
      top3Apres:      (j['top3Apres'] as num?)?.toDouble() ?? 0,
      top5Avant:      (j['top5Avant'] as num?)?.toDouble() ?? 0,
      top5Apres:      (j['top5Apres'] as num?)?.toDouble() ?? 0,
      roiAvant:       (j['roiAvant'] as num?)?.toDouble() ?? 0,
      roiApres:       (j['roiApres'] as num?)?.toDouble() ?? 0,
      gainNetAvant:   (j['gainNetAvant'] as num?)?.toDouble() ?? 0,
      gainNetApres:   (j['gainNetApres'] as num?)?.toDouble() ?? 0,
      outsidersAvant: (j['outsidersAvant'] as num?)?.toDouble() ?? 0,
      outsidersApres: (j['outsidersApres'] as num?)?.toDouble() ?? 0,
      scoreConfiance: (j['scoreConfiance'] as num?)?.toInt() ?? 0,
      verdict:        j['verdict'] as String? ?? '',
      notes:          j['notes'] as String?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory SimulationCandidate.fromJsonString(String s) =>
      SimulationCandidate.fromJson(jsonDecode(s) as Map<String, dynamic>);

  // ── Helpers affichage ─────────────────────────────────────────────────────

  /// Coefficients différents de 1.0 (critères réellement modifiés)
  Map<String, double> get coefficientsModifies =>
      Map.fromEntries(coefficients.entries.where((e) => (e.value - 1.0).abs() > 0.01));

  String get disciplineLabel {
    switch (discipline) {
      case 'TROT':     return 'Trot';
      case 'OBSTACLE': return 'Obstacle';
      default:         return 'Plat';
    }
  }

  String get dateLabel {
    final d = createdAt;
    return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year} '
           '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }
}
