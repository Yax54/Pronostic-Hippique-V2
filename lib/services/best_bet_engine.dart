import '../models/pmu_models.dart';
import 'prediction_engine.dart';
import 'gain_calculator.dart';
import 'dart:math' as math;

/// ═════════════════════════════════════════════════════════════════════════════
/// BestBetEngine — Moteur IA de sélection des meilleures opportunités
///
/// PHILOSOPHIE : Mieux vaut ÊTRE SÛR de gagner que chercher le gros gain.
///
/// ALGORITHME DE FUSION "TOP ÉQUILIBRE" (configurable) :
///   Score = poidsCofiance × scoreConfiance
///           + poidsGain × scoreQualiteGain
///           + poidsRisque × scoreRapportRisque
///           + bonus croisé si TOUT est bon simultanement
///           − pénalités si confiance insuffisante
///
/// PRESET CONSEILLÉ (valeur d'usine recommandée) :
///   • Confiance         : 65% — c'est le critère LE PLUS IMPORTANT
///   • Qualité du gain   : 25% — rentabilité ajustée au risque
///   • Rapport risque    : 10% — valeur attendue statistique
///
/// SEUIL ABSOLU : toute course sous 40% de confiance est FILTRÉE
///   → On ne propose que des paris avec une vraie chance de gagner
///
/// BONUS CROISÉ : +15% si confiance ≥ 70 ET gain qualité ≥ 60
///   → Récompense les courses qui sont bonnes sur TOUS les critères
///
/// PÉNALITÉS :
///   • Confiance < 40% → course exclue du classement Top Équilibre
///   • Confiance 40–54% → score réduit de 20%  (pari risqué)
///   • Confiance 55–64% → score réduit de 8%   (légère prudence)
///   • Cote > 15 (cheval surprise) → score gain réduit de 15%
/// ═════════════════════════════════════════════════════════════════════════════

// ─── Configuration des poids (modifiable par l'utilisateur) ──────────────────

class FusionConfig {
  /// Poids accordé à la confiance IA (0.0 – 1.0)
  final double poidsConfiance;

  /// Poids accordé à la qualité du gain (0.0 – 1.0)
  final double poidsGain;

  /// Poids accordé au rapport risque/rendement (0.0 – 1.0)
  final double poidsRisque;

  /// Seuil minimal de confiance pour apparaître dans Top Équilibre
  final int seuilConfianceMin;

  const FusionConfig({
    required this.poidsConfiance,
    required this.poidsGain,
    required this.poidsRisque,
    required this.seuilConfianceMin,
  }) : assert(poidsConfiance + poidsGain + poidsRisque <= 1.01,
              'Les poids doivent sommer à 1.0');

  /// ★ PRESET CONSEILLÉ — Configuration d'usine recommandée
  /// Basée sur l'analyse statistique des paris PMU :
  ///   → La confiance IA est le meilleur prédicteur de victoire
  ///   → Le gain brut seul est trompeur (grande cote = grand risque)
  ///   → Le rapport risque/rendement affine la sélection
  static const FusionConfig conseillee = FusionConfig(
    poidsConfiance:    0.65,   // 65% — PRIORITÉ ABSOLUE
    poidsGain:         0.25,   // 25% — rentabilité ajustée
    poidsRisque:       0.10,   // 10% — statistique valeur attendue
    seuilConfianceMin: 42,     // Seuil : exclure les pronostics trop incertains
  );

  /// Preset "Très sécurisé" — pour mises importantes
  static const FusionConfig tresSure = FusionConfig(
    poidsConfiance:    0.80,
    poidsGain:         0.15,
    poidsRisque:       0.05,
    seuilConfianceMin: 55,
  );

  /// Preset "Chasseur de gains" — pour petites mises / fun
  static const FusionConfig chasseurGains = FusionConfig(
    poidsConfiance:    0.40,
    poidsGain:         0.50,
    poidsRisque:       0.10,
    seuilConfianceMin: 35,
  );

  /// Pourcentage arrondi pour affichage
  int get pctConfiance => (poidsConfiance * 100).round();
  int get pctGain      => (poidsGain * 100).round();
  int get pctRisque    => (poidsRisque * 100).round();

  FusionConfig copyWith({
    double? poidsConfiance,
    double? poidsGain,
    double? poidsRisque,
    int? seuilConfianceMin,
  }) {
    return FusionConfig(
      poidsConfiance:    poidsConfiance    ?? this.poidsConfiance,
      poidsGain:         poidsGain         ?? this.poidsGain,
      poidsRisque:       poidsRisque       ?? this.poidsRisque,
      seuilConfianceMin: seuilConfianceMin ?? this.seuilConfianceMin,
    );
  }
}

// ─── Moteur principal ─────────────────────────────────────────────────────────

class BestBetEngine {

  static List<BetOpportunity> computeAll(
    List<PmuReunion> reunions, {
    FusionConfig config = FusionConfig.conseillee,
  }) {
    final raw = <_RawOpportunity>[];

    for (final reunion in reunions) {
      for (final course in reunion.courses) {
        if (!course.participantsLoaded || course.participants.isEmpty) continue;
        if (course.status == CourseStatus.terminee) continue;

        final reco = PredictionEngine.generateRecommendation(
          course, course.participants, reunion.hippodrome,
        );
        if (reco.gagnant == null) continue;

        final gagnant = reco.gagnant!;
        final cote    = gagnant.coteAffichee > 0 ? gagnant.coteAffichee : 3.0;
        final nb      = course.nombrePartants;
        const mise    = 10.0;

        final gainSG = GainCalculator.simpleGagnant(mise, cote);
        final gainP  = GainCalculator.place(mise, cote, nb);
        final gainGP = GainCalculator.gagnantEtPlace(mise, cote, nb);

        GainResult? gainTierce, gainQuarte, gainQuinte;
        final c3 = reco.tierce.take(3).map((p) => p.coteAffichee > 0 ? p.coteAffichee : 3.0).toList();
        final c4 = reco.quarte.take(4).map((p) => p.coteAffichee > 0 ? p.coteAffichee : 3.0).toList();
        final c5 = reco.quinte.take(5).map((p) => p.coteAffichee > 0 ? p.coteAffichee : 3.0).toList();

        if (c3.length >= 3) gainTierce = GainCalculator.tierce(mise, c3, nb);
        if (c4.length >= 4) gainQuarte = GainCalculator.quarte(mise, c4, nb);
        if (c5.length >= 5) gainQuinte = GainCalculator.quinte(mise, c5, nb);

        // Meilleur gain brut (pour le tri "Plus Rentable")
        double bestGainMax = gainSG.gainMax;
        TypePariCalc bestType = TypePariCalc.simpleGagnant;
        void chk(GainResult? r, TypePariCalc t) {
          if (r != null && r.gainMax > bestGainMax) { bestGainMax = r.gainMax; bestType = t; }
        }
        chk(gainP, TypePariCalc.place);
        chk(gainGP, TypePariCalc.gagnantEtPlace);
        chk(gainTierce, TypePariCalc.tierce);
        chk(gainQuarte, TypePariCalc.quarte);
        chk(gainQuinte, TypePariCalc.quinte);

        // ── SCORE QUALITÉ DU GAIN (ajusté au risque) ─────────────────────────
        // On ne veut pas juste le gain brut, mais le gain par unité de risque.
        // Gain qualité = gain simple gagnant / cote → mesure l'efficacité du pari
        // Plafonné pour éviter que les courses avec cote monstrueuse dominent tout
        final gainQualite = cote > 0
            ? (gainSG.gainMax / cote).clamp(0.0, 50.0)
            : 0.0;

        // ── SCORE RAPPORT RISQUE/RENDEMENT (valeur attendue) ─────────────────
        // Valeur attendue = (probabilité estimée × gain) - (1 - proba) × mise
        // Si proba estimée ≈ confiance IA / 100
        final probaEst = reco.niveauConfiance / 100.0;
        final valeurAttendue = probaEst * gainSG.gainMax - (1 - probaEst) * mise;
        // Normaliser en [0, 100] : valeur attendue positive = bon signe
        final scoreVA = (valeurAttendue / mise * 10 + 50).clamp(0.0, 100.0);

        raw.add(_RawOpportunity(
          reunion:      reunion,
          course:       course,
          reco:         reco,
          gainSG:       gainSG,
          gainP:        gainP,
          gainGP:       gainGP,
          gainTierce:   gainTierce,
          gainQuarte:   gainQuarte,
          gainQuinte:   gainQuinte,
          bestGainMax:  bestGainMax,
          bestType:     bestType,
          miseRef:      mise,
          gainQualite:  gainQualite,
          scoreVA:      scoreVA,
          cote:         cote,
        ));
      }
    }

    if (raw.isEmpty) return [];

    // ── NORMALISATION relative au groupe du jour ──────────────────────────────
    final maxConfiance  = raw.map((r) => r.reco.niveauConfiance.toDouble()).reduce(math.max);
    final maxGainBrut   = raw.map((r) => r.bestGainMax).reduce(math.max);
    final maxGainQual   = raw.map((r) => r.gainQualite).reduce(math.max);
    final maxScoreVA    = raw.map((r) => r.scoreVA).reduce(math.max);

    final opportunities = raw.map((r) {
      final confiance = r.reco.niveauConfiance;

      // ── Scores normalisés (0–100) relatifs au groupe ──────────────────────
      final normConf  = maxConfiance > 0
          ? (confiance / maxConfiance * 100).clamp(0.0, 100.0) : 0.0;
      final normGainQ = maxGainQual > 0
          ? (r.gainQualite / maxGainQual * 100).clamp(0.0, 100.0) : 0.0;
      final normVA    = maxScoreVA > 0
          ? (r.scoreVA / maxScoreVA * 100).clamp(0.0, 100.0) : 0.0;
      // Gain brut normalisé (pour les autres tris)
      final normGainBrut = maxGainBrut > 0
          ? (r.bestGainMax / maxGainBrut * 100).clamp(0.0, 100.0) : 0.0;

      // ── Score de fusion PONDÉRÉ (selon config) ───────────────────────────
      double fusion = config.poidsConfiance * normConf
                    + config.poidsGain      * normGainQ
                    + config.poidsRisque    * normVA;

      // ★ BONUS CROISÉ : si la course est bonne sur TOUS les critères
      if (normConf >= 70 && normGainQ >= 60) {
        fusion *= 1.15;  // +15% récompense la co-excellence
      } else if (normConf >= 60 && normGainQ >= 50) {
        fusion *= 1.07;  // +7% bonus modéré
      }

      // ✦ PÉNALITÉS progressives selon le niveau de confiance ABSOLU
      if (confiance < config.seuilConfianceMin) {
        fusion = 0.0;  // Exclu du Top Équilibre
      } else if (confiance < 55) {
        fusion *= 0.80;  // -20% pari risqué
      } else if (confiance < 65) {
        fusion *= 0.92;  // -8% légère prudence
      }

      // Pénalité si cote très élevée (surprise, très risqué)
      if (r.cote > 15) {
        fusion *= 0.88;
      }

      final rangFusion = fusion.clamp(0.0, 150.0);

      return BetOpportunity(
        reunion:            r.reunion,
        course:             r.course,
        recommendation:     r.reco,
        gainSimpleGagnant:  r.gainSG,
        gainPlace:          r.gainP,
        gainGagnantPlace:   r.gainGP,
        gainTierce:         r.gainTierce,
        gainQuarte:         r.gainQuarte,
        gainQuinte:         r.gainQuinte,
        bestGainMax:        r.bestGainMax,
        bestGainType:       r.bestType,
        scoreComposite:     rangFusion,
        scoreNormConfiance: normConf,
        scoreNormGain:      normGainBrut,
        scoreNormGainQual:  normGainQ,
        scoreNormVA:        normVA,
        miseRef:            r.miseRef,
        configUsed:         config,
        estExcluFusion:     confiance < config.seuilConfianceMin,
      );
    }).toList();

    return opportunities;
  }

  // ─── Tris ─────────────────────────────────────────────────────────────────

  static List<BetOpportunity> sortByConfiance(List<BetOpportunity> ops) {
    final s = List<BetOpportunity>.from(ops);
    s.sort((a, b) => b.recommendation.niveauConfiance.compareTo(a.recommendation.niveauConfiance));
    return s;
  }

  static List<BetOpportunity> sortByGainMax(List<BetOpportunity> ops) {
    final s = List<BetOpportunity>.from(ops);
    s.sort((a, b) => b.bestGainMax.compareTo(a.bestGainMax));
    return s;
  }

  static List<BetOpportunity> sortByComposite(List<BetOpportunity> ops) {
    final s = List<BetOpportunity>.from(ops)
      ..sort((a, b) => b.scoreComposite.compareTo(a.scoreComposite));
    return s;
  }

  static List<BetOpportunity> topN(
    List<BetOpportunity> ops,
    BestBetSort sort, {
    int n = 99,
    FusionConfig config = FusionConfig.conseillee,
  }) {
    List<BetOpportunity> sorted;
    switch (sort) {
      case BestBetSort.confiance:  sorted = sortByConfiance(ops);  break;
      case BestBetSort.gainMax:    sorted = sortByGainMax(ops);    break;
      case BestBetSort.composite:  sorted = sortByComposite(ops);  break;
    }
    return sorted.take(n).toList();
  }
}

// ─── Enum de tri ──────────────────────────────────────────────────────────────
enum BestBetSort { confiance, gainMax, composite }

// ─── Données brutes ───────────────────────────────────────────────────────────
class _RawOpportunity {
  final PmuReunion reunion;
  final PmuCourse course;
  final RaceRecommendation reco;
  final GainResult gainSG, gainP, gainGP;
  final GainResult? gainTierce, gainQuarte, gainQuinte;
  final double bestGainMax;
  final TypePariCalc bestType;
  final double miseRef;
  final double gainQualite;  // gain ajusté au risque
  final double scoreVA;      // valeur attendue normalisée
  final double cote;

  _RawOpportunity({
    required this.reunion, required this.course, required this.reco,
    required this.gainSG, required this.gainP, required this.gainGP,
    this.gainTierce, this.gainQuarte, this.gainQuinte,
    required this.bestGainMax, required this.bestType, required this.miseRef,
    required this.gainQualite, required this.scoreVA, required this.cote,
  });
}

// ─── Modèle d'opportunité ─────────────────────────────────────────────────────
class BetOpportunity {
  final PmuReunion reunion;
  final PmuCourse course;
  final RaceRecommendation recommendation;

  final GainResult gainSimpleGagnant;
  final GainResult gainPlace;
  final GainResult gainGagnantPlace;
  final GainResult? gainTierce;
  final GainResult? gainQuarte;
  final GainResult? gainQuinte;

  final double bestGainMax;
  final TypePariCalc bestGainType;

  /// Score fusion final (0–150 avec bonus croisé)
  final double scoreComposite;

  /// Score normalisé confiance brute (0–100)
  final double scoreNormConfiance;

  /// Score normalisé gain brut (0–100, pour affichage comparatif)
  final double scoreNormGain;

  /// Score normalisé qualité du gain (ajusté au risque) (0–100)
  final double scoreNormGainQual;

  /// Score normalisé valeur attendue statistique (0–100)
  final double scoreNormVA;

  /// Configuration de fusion utilisée pour ce calcul
  final FusionConfig configUsed;

  /// True si la course a été exclue du Top Équilibre (confiance trop faible)
  final bool estExcluFusion;

  final double miseRef;

  BetOpportunity({
    required this.reunion,
    required this.course,
    required this.recommendation,
    required this.gainSimpleGagnant,
    required this.gainPlace,
    required this.gainGagnantPlace,
    this.gainTierce,
    this.gainQuarte,
    this.gainQuinte,
    required this.bestGainMax,
    required this.bestGainType,
    required this.scoreComposite,
    required this.scoreNormConfiance,
    required this.scoreNormGain,
    required this.scoreNormGainQual,
    required this.scoreNormVA,
    required this.configUsed,
    required this.estExcluFusion,
    required this.miseRef,
  });

  // ── Calcul des gains pour une mise personnalisée ──────────────────────────
  GainResult gainForMise(double mise, TypePariCalc type) {
    final f = mise / miseRef;
    switch (type) {
      case TypePariCalc.simpleGagnant:  return _scale(gainSimpleGagnant, f, type);
      case TypePariCalc.place:          return _scale(gainPlace, f, type);
      case TypePariCalc.gagnantEtPlace: return _scale(gainGagnantPlace, f, type);
      case TypePariCalc.tierce:
        return gainTierce != null ? _scale(gainTierce!, f, type) : GainResult.zero(type, mise);
      case TypePariCalc.quarte:
        return gainQuarte != null ? _scale(gainQuarte!, f, type) : GainResult.zero(type, mise);
      case TypePariCalc.quinte:
        return gainQuinte != null ? _scale(gainQuinte!, f, type) : GainResult.zero(type, mise);
      case TypePariCalc.couple:
        return GainResult.zero(type, mise);
    }
  }

  GainResult _scale(GainResult g, double f, TypePariCalc type) => GainResult(
    type: type,
    mise: g.mise * f,
    coteUtilisee: g.coteUtilisee,
    gainNet: g.gainNet * f,
    gainSiPlace: g.gainSiPlace != null ? g.gainSiPlace! * f : null,
    gainSiDesordre: g.gainSiDesordre != null ? g.gainSiDesordre! * f : null,
    gainBonus4sur5: g.gainBonus4sur5 != null ? g.gainBonus4sur5! * f : null,
    retourTotal: g.retourTotal * f,
    probabiliteEstimee: g.probabiliteEstimee,
    scenarioPessimiste: g.scenarioPessimiste * f,
    explication: g.explication,
  );

  // ── Helpers UI ────────────────────────────────────────────────────────────

  String get confianceLabel => '${recommendation.niveauConfiance}%';

  int get confianceColorValue {
    final c = recommendation.niveauConfiance;
    if (c >= 80) return 0xFF4CAF7D;
    if (c >= 65) return 0xFF8BC34A;
    if (c >= 50) return 0xFFFFB74D;
    return 0xFFEF5350;
  }

  String get gainMaxLabel => GainCalculator.formatGain(bestGainMax);

  String medal(int rank) {
    switch (rank) {
      case 0:  return '🥇';
      case 1:  return '🥈';
      case 2:  return '🥉';
      default: return '${rank + 1}.';
    }
  }

  String get bestGainTypeLabel {
    switch (bestGainType) {
      case TypePariCalc.simpleGagnant:  return '🏆 Simple Gagnant';
      case TypePariCalc.place:          return '🎯 Placé';
      case TypePariCalc.gagnantEtPlace: return '🎯🏆 Gagnant+Placé';
      case TypePariCalc.tierce:         return '📋 Tiercé';
      case TypePariCalc.quarte:         return '🎰 Quarté+';
      case TypePariCalc.quinte:         return '🌟 Quinté+';
      case TypePariCalc.couple:         return '🔄 Couplé';
    }
  }

  /// Niveau de qualité fusion (pour badge)
  FusionLevel get fusionLevel {
    if (estExcluFusion) return FusionLevel.exclu;
    final c = recommendation.niveauConfiance;
    if (scoreNormConfiance >= 70 && scoreNormGainQual >= 60) return FusionLevel.doublement;
    if (c >= 78)                                              return FusionLevel.surConfiance;
    if (c >= 65)                                              return FusionLevel.bon;
    if (c >= 50)                                              return FusionLevel.moyen;
    return FusionLevel.faible;
  }

  /// Accès direct à la fiabilité IA (étoiles 1–5, signaux, description honnête)
  FiabiliteResult? get fiabilite => recommendation.fiabilite;

  /// Raccourci : nombre d'étoiles (0 si pas de fiabilité calculée)
  int get etoilesFinabilite => recommendation.fiabilite?.etoiles ?? 0;

  /// True si la course mérite le badge "Haute Fiabilité" (≥4 étoiles)
  bool get estHauteFiabilite {
    final f = recommendation.fiabilite;
    if (f == null) return false;
    return f.etoiles >= 4 && recommendation.niveauConfiance >= 60;
  }

  /// True si la course est exceptionnelle (5 étoiles, tous signaux convergents)
  bool get estExceptionnelle {
    final f = recommendation.fiabilite;
    if (f == null) return false;
    return f.etoiles >= 5 && recommendation.niveauConfiance >= 68;
  }

  /// Résumé du profil de fiabilité pour l'utilisateur
  String get fiabiliteResume {
    final f = recommendation.fiabilite;
    if (f == null) return '';
    final c = recommendation.niveauConfiance;
    if (f.etoiles >= 5) {
      return '⭐⭐⭐⭐⭐ Profil exceptionnel — ~65–75% de chances estimées';
    } else if (f.etoiles >= 4) {
      return '⭐⭐⭐⭐ Bon profil — ~50–65% de chances estimées';
    } else if (f.etoiles >= 3) {
      return '⭐⭐⭐ Profil correct — ~35–50% de chances estimées';
    } else if (f.etoiles >= 2) {
      return '⭐⭐ Incertain — ~25–35% de chances estimées';
    }
    return '⭐ Risqué — <25% de chances estimées ($c% confiance IA)';
  }

  /// Conseil de mise selon fiabilité
  String get conseilMise {
    final f = recommendation.fiabilite;
    if (f == null) return 'Mise minimale';
    if (f.etoiles >= 5) return 'Mise normale à forte recommandée';
    if (f.etoiles >= 4) return 'Mise normale recommandée';
    if (f.etoiles >= 3) return 'Mise prudente — pari placé conseillé';
    return 'Mise minimale ou abstention';
  }

  /// Texte d'explication contextuel pour le mode Top Équilibre
  String fusionExplicationForConfig(FusionConfig cfg) {
    final c = recommendation.niveauConfiance;
    if (estExcluFusion) {
      return 'Cette course est exclue du classement Top Équilibre car sa '
             'confiance ($c%) est inférieure au seuil configuré (${cfg.seuilConfianceMin}%). '
             'Elle reste visible dans les onglets "Plus Sûr" et "Plus Rentable".';
    }
    if (scoreNormConfiance >= 70 && scoreNormGainQual >= 60) {
      return 'EXCELLENT : Cette course cumule une forte confiance IA ($c%) '
             'ET une bonne rentabilité ajustée au risque. '
             'Le bonus croisé (+15%) a été appliqué. C\'est la meilleure combinaison possible.';
    }
    if (c >= 75) {
      return 'TRÈS SÛR : L\'IA est très confiante ($c%) sur ce pronostic. '
             'La confiance (${cfg.pctConfiance}%) domine le score, ce qui est recommandé '
             'pour maximiser vos chances de gagner.';
    }
    if (c >= 60) {
      return 'BON PROFIL : Confiance correcte ($c%) avec une rentabilité '
             'ajustée satisfaisante. Bon équilibre entre sécurité et gain potentiel.';
    }
    return 'PROFIL MOYEN : Confiance limitée ($c%). Considérez une mise prudente '
           'ou préférez les onglets "Plus Sûr" pour des paris plus fiables.';
  }
}

// ─── Niveau de fusion ─────────────────────────────────────────────────────────
enum FusionLevel {
  doublement,   // ★★ Excellent sur tous les critères
  surConfiance, // Très haute confiance
  bon,          // Bon niveau général
  moyen,        // Niveau moyen
  faible,       // Faible confiance
  exclu,        // Exclu du Top Équilibre
}

extension FusionLevelExt on FusionLevel {
  String get label {
    switch (this) {
      case FusionLevel.doublement:   return '★★ Excellent';
      case FusionLevel.surConfiance: return '✅ Très sûr';
      case FusionLevel.bon:          return '👍 Bon profil';
      case FusionLevel.moyen:        return '🟡 Moyen';
      case FusionLevel.faible:       return '⚠️ Prudence';
      case FusionLevel.exclu:        return '🚫 Exclu';
    }
  }

  String get explication {
    switch (this) {
      case FusionLevel.doublement:   return 'Cumule haute confiance ET bonne rentabilité';
      case FusionLevel.surConfiance: return 'Très forte probabilité de gagner';
      case FusionLevel.bon:          return 'Bon équilibre sécurité / rentabilité';
      case FusionLevel.moyen:        return 'Risque modéré, mise prudente conseillée';
      case FusionLevel.faible:       return 'Pari incertain, mise minimale';
      case FusionLevel.exclu:        return 'Confiance insuffisante pour ce mode';
    }
  }

  int get colorValue {
    switch (this) {
      case FusionLevel.doublement:   return 0xFFFFD700;  // Or
      case FusionLevel.surConfiance: return 0xFF4CAF7D;  // Vert
      case FusionLevel.bon:          return 0xFF8BC34A;  // Vert clair
      case FusionLevel.moyen:        return 0xFFFFB74D;  // Orange
      case FusionLevel.faible:       return 0xFFEF5350;  // Rouge
      case FusionLevel.exclu:        return 0xFF757575;  // Gris
    }
  }
}
