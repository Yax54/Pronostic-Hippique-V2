// ═══════════════════════════════════════════════════════════════════════════
//  IA NARRATIVE MODELS — v10.64
//  Couche narrative d'affichage uniquement.
//  Ne modifie aucun calcul IA, aucun poids, aucun pronostic.
// ═══════════════════════════════════════════════════════════════════════════

class IaNarrativeContext {
  final String pseudoUtilisateur;

  final int nbCoursesJour;
  final int nbBonnesCoursesJour;

  final int nbCoursesHier;
  final int nbBonnesCoursesHier;

  final double roiJour;
  final double roiHier;

  final int streakPlusSur;
  final int streakMeilleurPari;
  final int streakTopEquilibre;
  final int streakPlusRentable;
  final int streakConseilJour;

  const IaNarrativeContext({
    required this.pseudoUtilisateur,
    required this.nbCoursesJour,
    required this.nbBonnesCoursesJour,
    required this.nbCoursesHier,
    required this.nbBonnesCoursesHier,
    required this.roiJour,
    required this.roiHier,
    required this.streakPlusSur,
    required this.streakMeilleurPari,
    required this.streakTopEquilibre,
    required this.streakPlusRentable,
    required this.streakConseilJour,
  });

  // ── Taux calculés ─────────────────────────────────────────────────────────

  double get tauxJour {
    if (nbCoursesJour <= 0) return 0;
    return nbBonnesCoursesJour / nbCoursesJour;
  }

  double get tauxHier {
    if (nbCoursesHier <= 0) return 0;
    return nbBonnesCoursesHier / nbCoursesHier;
  }

  // ── États comparatifs ─────────────────────────────────────────────────────

  /// Vrai si aujourd'hui est significativement meilleur qu'hier (>5% d'écart).
  bool get progressionJour => nbCoursesJour > 0 && nbCoursesHier > 0 &&
      tauxJour > tauxHier + 0.05;

  /// Vrai si aujourd'hui est significativement plus faible qu'hier (>5% d'écart).
  bool get regressionJour => nbCoursesJour > 0 && nbCoursesHier > 0 &&
      tauxJour < tauxHier - 0.05;

  /// Vrai si les deux journées sont comparables et sans écart significatif.
  bool get jourStable => nbCoursesJour > 0 && !progressionJour && !regressionJour;

  /// Vrai si au moins un widget premium est en série gagnante (≥ 2 jours).
  bool get premiumEnSerie =>
      streakPlusSur >= 2 ||
      streakMeilleurPari >= 2 ||
      streakTopEquilibre >= 2 ||
      streakPlusRentable >= 2 ||
      streakConseilJour >= 2;

  /// Pseudo à afficher (fallback 'Parieur' si vide).
  String get pseudoAffiche =>
      pseudoUtilisateur.trim().isEmpty ? 'Parieur' : pseudoUtilisateur.trim();
}
