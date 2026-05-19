// ═══════════════════════════════════════════════════════════════════════════
//  IA NARRATIVE MODELS — v10.66
//  Couche narrative d'affichage uniquement.
//  Ne modifie aucun calcul IA, aucun poids, aucun pronostic.
//
//  v10.65 : ajout taux7j, taux7jPrecedent, meilleureDiscipline,
//           widgetPremiumLePlusStable, progression7j, regression7j
//  v10.66 : ajout typePariLePlusStable, typePariLePlusInstable,
//           signalExpertDisponible, getter aTypePari
// ═══════════════════════════════════════════════════════════════════════════

class IaNarrativeContext {
  final String pseudoUtilisateur;

  // ── Comparaison jour J vs hier ────────────────────────────────────────────
  final int nbCoursesJour;
  final int nbBonnesCoursesJour;
  final int nbCoursesHier;
  final int nbBonnesCoursesHier;

  final double roiJour;
  final double roiHier;

  // ── Streaks premium ───────────────────────────────────────────────────────
  final int streakPlusSur;
  final int streakMeilleurPari;
  final int streakTopEquilibre;
  final int streakPlusRentable;
  final int streakConseilJour;

  // ── ★ v10.65 : Tendances 7 jours ─────────────────────────────────────────
  /// Taux de réussite moyen sur les 7 derniers jours (0.0–1.0).
  final double taux7j;

  /// Taux de réussite moyen sur les 7 jours précédents (jours 8–14).
  final double taux7jPrecedent;

  // ── ★ v10.65 : Points forts ───────────────────────────────────────────────
  /// Meilleure discipline IA sur la période récente (ex : 'Plat', 'Trot').
  /// Vide si non disponible.
  final String meilleureDiscipline;

  /// Widget premium le plus stable (ex : 'Conseil du Jour', 'Meilleur Pari').
  /// Vide si non disponible.
  final String widgetPremiumLePlusStable;

  // ── ★ v10.66 : Type de pari & signal expert ───────────────────────────────
  /// Type de pari le plus stable sur 14 jours (ex : 'Simple Gagnant').
  /// Null si données insuffisantes.
  final String? typePariLePlusStable;

  /// Type de pari le moins stable sur 14 jours (ex : 'Quinté+').
  /// Null si données insuffisantes.
  final String? typePariLePlusInstable;

  /// Vrai si au moins un signal expert est calculable (discipline ou typePari disponible).
  final bool signalExpertDisponible;

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
    this.taux7j = 0.0,
    this.taux7jPrecedent = 0.0,
    this.meilleureDiscipline = '',
    this.widgetPremiumLePlusStable = '',
    this.typePariLePlusStable,
    this.typePariLePlusInstable,
    this.signalExpertDisponible = false,
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

  // ── États comparatifs jour J vs hier ─────────────────────────────────────

  /// Vrai si aujourd'hui est significativement meilleur qu'hier (>5% d'écart).
  bool get progressionJour =>
      nbCoursesJour > 0 && nbCoursesHier > 0 && tauxJour > tauxHier + 0.05;

  /// Vrai si aujourd'hui est significativement plus faible qu'hier (>5% d'écart).
  bool get regressionJour =>
      nbCoursesJour > 0 && nbCoursesHier > 0 && tauxJour < tauxHier - 0.05;

  /// Vrai si les deux journées sont comparables sans écart significatif.
  bool get jourStable => nbCoursesJour > 0 && !progressionJour && !regressionJour;

  // ── ★ v10.65 : États comparatifs 7 jours ─────────────────────────────────

  /// Vrai si la tendance hebdomadaire progresse (>3% d'écart).
  bool get progression7j =>
      taux7j > 0 && taux7jPrecedent > 0 && taux7j > taux7jPrecedent + 0.03;

  /// Vrai si la tendance hebdomadaire régresse (>3% d'écart).
  bool get regression7j =>
      taux7j > 0 && taux7jPrecedent > 0 && taux7j < taux7jPrecedent - 0.03;

  /// Vrai si la tendance 7j est disponible (données suffisantes).
  bool get a7jDonnees => taux7j > 0 && taux7jPrecedent > 0;

  // ── Série premium ─────────────────────────────────────────────────────────

  /// Vrai si au moins un widget premium est en série gagnante (≥ 2 jours).
  bool get premiumEnSerie =>
      streakPlusSur >= 2 ||
      streakMeilleurPari >= 2 ||
      streakTopEquilibre >= 2 ||
      streakPlusRentable >= 2 ||
      streakConseilJour >= 2;

  // ── ★ v10.66 : Getters type de pari ──────────────────────────────────────

  /// Vrai si un type de pari stable est disponible.
  bool get aTypePari =>
      typePariLePlusStable != null && typePariLePlusStable!.isNotEmpty;

  // ── Pseudo à afficher ─────────────────────────────────────────────────────

  /// Pseudo à afficher (fallback 'Parieur' si vide).
  String get pseudoAffiche =>
      pseudoUtilisateur.trim().isEmpty ? 'Parieur' : pseudoUtilisateur.trim();

  /// Libellé lisible du widget premium le plus stable.
  String get widgetLibelle {
    switch (widgetPremiumLePlusStable) {
      case 'conseilJour':
        return 'Conseil du Jour';
      case 'meilleurPari':
        return 'Meilleur Pari';
      case 'topEquilibre':
        return 'Top Équilibre';
      case 'plusSur':
        return 'Plus Sûr';
      case 'plusRentable':
        return 'Plus Rentable';
      default:
        return widgetPremiumLePlusStable;
    }
  }
}
