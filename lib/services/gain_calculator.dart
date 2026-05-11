// ignore_for_file: depend_on_referenced_packages
import '../utils/format_euros.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Calculateur de gains PMU — Pronostic Hippique  (v3 — fourchettes réelles PMU)
//
// ══════════════════════════════════════════════════════════════════
//  RÈGLES PMU OFFICIELLES :
//
//  SIMPLE GAGNANT / SIMPLE PLACÉ
//    • Cote publiée en temps réel par PMU avant le départ
//    • Gain = mise × cote (cote réelle récupérée via API)
//    • Ces cotes sont VRAIES et disponibles avant la course
//
//  TIERCÉ / QUARTÉ+ / QUINTÉ+
//    • PMU NE PUBLIE PAS de cote avant la course pour les combinés
//    • Le dividende est calculé APRÈS la course par mutualisation
//    • Le gain dépend du total parié et du nombre de gagnants
//    • → On affiche une FOURCHETTE basée sur les statistiques PMU réelles
//    • → Après la course, on récupère le vrai dividende PMU via API
//
//  FOURCHETTES BASÉES SUR LES STATISTIQUES PMU (pour une mise de 2€)
//    Tiercé désordre :  30 € → 500 €     (moyenne ~150 €)
//    Tiercé ordre    : 150 € → 5 000 €   (moyenne ~800 €)
//    Quarté+ désordre: 100 € → 3 000 €   (moyenne ~600 €)
//    Quarté+ ordre   : 800 € → 80 000 €  (moyenne ~8 000 €)
//    Quinté+ désordre: 300 € → 15 000 €  (moyenne ~2 500 €)
//    Quinté+ ordre   : 3 000 € → 300 000 € (moyenne ~30 000 €)
//    Quinté+ 4/5     :  30 € → 500 €     (moyenne ~100 €)
// ══════════════════════════════════════════════════════════════════
// ─────────────────────────────────────────────────────────────────────────────

class GainCalculator {

  // ─── Simple Gagnant ──────────────────────────────────────────────────────────
  // Cote RÉELLE récupérée depuis l'API PMU. Gain = mise × cote.
  static GainResult simpleGagnant(double mise, double coteGagnant) {
    if (mise <= 0 || coteGagnant <= 1) {
      return GainResult.zero(TypePariCalc.simpleGagnant, mise);
    }
    final retour = mise * coteGagnant;
    final gainNet = retour - mise;
    final prob = _coteToProbabilite(coteGagnant);
    return GainResult(
      type: TypePariCalc.simpleGagnant,
      mise: mise,
      coteUtilisee: coteGagnant,
      gainNet: gainNet,
      retourTotal: retour,
      probabiliteEstimee: prob.clamp(1.0, 95.0),
      scenarioPessimiste: -mise,
      estFourchette: false,
      explication:
          'Cote réelle PMU × mise\n'
          'Si N°X arrive 1er → retour ${_fmt(retour)} (gain net ${_fmtGain(gainNet)})\n'
          'Si N°X arrive 2e ou plus → perte ${_fmtGain(-mise)}',
    );
  }

  // ─── Simple Placé ─────────────────────────────────────────────────────────────
  // Cote Placé calculée depuis la cote Gagnant réelle PMU.
  static GainResult place(double mise, double coteGagnant, int nbPartants) {
    if (mise <= 0 || coteGagnant <= 1) {
      return GainResult.zero(TypePariCalc.place, mise);
    }
    final cotePlace = _cotePlace(coteGagnant, nbPartants);
    final retour = mise * cotePlace;
    final gainNet = retour - mise;
    final prob = (_coteToProbabilite(coteGagnant) * 2.8).clamp(5.0, 85.0);
    return GainResult(
      type: TypePariCalc.place,
      mise: mise,
      coteUtilisee: cotePlace,
      gainNet: gainNet,
      retourTotal: retour,
      probabiliteEstimee: prob,
      scenarioPessimiste: -mise,
      estFourchette: false,
      explication:
          'Cote Placé ≈ ×${cotePlace.toStringAsFixed(2)} (cote Gagnant ÷ diviseur PMU)\n'
          'Si top 3 → retour ${_fmt(retour)} (gain net ${_fmtGain(gainNet)})\n'
          'Si 4e ou moins → perte ${_fmtGain(-mise)}',
    );
  }

  // ─── Gagnant + Placé ──────────────────────────────────────────────────────────
  static GainResult gagnantEtPlace(double mise, double coteGagnant, int nbPartants) {
    if (mise <= 0 || coteGagnant <= 1) {
      return GainResult.zero(TypePariCalc.gagnantEtPlace, mise * 2);
    }
    final miseReelle = mise * 2;
    final cotePlace = _cotePlace(coteGagnant, nbPartants);
    final retourSi1er = mise * coteGagnant + mise * cotePlace;
    final gainSi1er = retourSi1er - miseReelle;
    final retourSiPlace = mise * cotePlace;
    final gainSiPlace = retourSiPlace - miseReelle;
    final prob = _coteToProbabilite(coteGagnant);
    return GainResult(
      type: TypePariCalc.gagnantEtPlace,
      mise: miseReelle,
      coteUtilisee: coteGagnant,
      gainNet: gainSi1er,
      gainSiPlace: gainSiPlace,
      retourTotal: retourSi1er,
      probabiliteEstimee: prob.clamp(1.0, 95.0),
      scenarioPessimiste: -miseReelle,
      estFourchette: false,
      explication:
          '⚠️ Mise réelle : ${_fmt(miseReelle)} (= ${_fmt(mise)} Gagnant + ${_fmt(mise)} Placé)\n'
          'Si 1er → +${_fmtGain(gainSi1er)} (Gagnant ×${coteGagnant.toStringAsFixed(2)} + Placé ×${cotePlace.toStringAsFixed(2)})\n'
          'Si 2e/3e → ${_fmtGain(gainSiPlace)} (seulement Placé encaissé)\n'
          'Si 4e+ → perte ${_fmtGain(-miseReelle)}',
    );
  }

  // ─── Couplé Gagnant ──────────────────────────────────────────────────────────
  static GainResult couple(double mise, double cote1, double cote2) {
    if (mise <= 0 || cote1 <= 1 || cote2 <= 1) {
      return GainResult.zero(TypePariCalc.couple, mise);
    }
    final gainBrut = mise * (cote1 - 1) * (cote2 - 1) * 0.75;
    final retour = mise + gainBrut;
    final prob = (_coteToProbabilite(cote1) * _coteToProbabilite(cote2) / 100 * 6).clamp(1.0, 40.0);
    return GainResult(
      type: TypePariCalc.couple,
      mise: mise,
      coteUtilisee: cote1 * cote2 * 0.75,
      gainNet: gainBrut,
      retourTotal: retour,
      probabiliteEstimee: prob,
      scenarioPessimiste: -mise,
      estFourchette: false,
      explication:
          '2 chevaux doivent être dans le top 2 (ordre libre)\n'
          'Gain estimé ≈ ${_fmtGain(gainBrut)}\n'
          'Dividende réel fixé par PMU après la course',
    );
  }

  // ─── Tiercé ──────────────────────────────────────────────────────────────────
  // Dividende INCONNU avant la course → fourchette statistique PMU réelle.
  // Base de calcul PMU : mise de 2€ → on ramène proportionnellement.
  static GainResult tierce(double mise, List<double> cotes3, int nbPartants) {
    if (cotes3.length < 3 || mise <= 0) {
      return GainResult.zero(TypePariCalc.tierce, mise);
    }
    // Facteur de mise par rapport à la base PMU de 2€
    final facteur = mise / 2.0;

    // Fourchettes réelles PMU pour Tiercé (base 2€) :
    // Désordre : min 30€, moy 150€, max 500€
    // Ordre    : min 150€, moy 800€, max 5 000€
    // On module légèrement selon le niveau des cotes (outsiders = plus)
    final coteMoy = cotes3.fold(0.0, (s, c) => s + c) / 3;
    final facteurCote = (coteMoy / 10.0).clamp(0.5, 3.0); // outsiders → dividendes plus élevés

    final minDesordre = (30  * facteur * facteurCote).roundToDouble();
    final maxDesordre = (500 * facteur * facteurCote).roundToDouble();
    final minOrdre    = (150  * facteur * facteurCote).roundToDouble();
    final maxOrdre    = (5000 * facteur * facteurCote).roundToDouble();

    final gainNetDesordre = (150 * facteur * facteurCote) - mise; // valeur centrale
    final gainNetOrdre    = (800 * facteur * facteurCote) - mise; // valeur centrale

    final prob = _probaTierce(cotes3, nbPartants);
    return GainResult(
      type: TypePariCalc.tierce,
      mise: mise,
      coteUtilisee: 0, // pas de cote unique pour les combinés
      gainNet: gainNetOrdre,
      gainSiDesordre: gainNetDesordre,
      retourTotal: 800 * facteur * facteurCote,
      probabiliteEstimee: prob,
      scenarioPessimiste: -mise,
      estFourchette: true,
      // Fourchettes
      fourchetteMinDesordre: minDesordre,
      fourchetteMaxDesordre: maxDesordre,
      fourchetteMinOrdre: minOrdre,
      fourchetteMaxOrdre: maxOrdre,
      explication:
          '3 chevaux dans le top 3\n'
          '⚠️ Dividende fixé par PMU après la course\n'
          'Désordre : entre ${_fmt(minDesordre)} et ${_fmt(maxDesordre)}\n'
          'Dans l\'ordre : entre ${_fmt(minOrdre)} et ${_fmt(maxOrdre)}',
    );
  }

  // ─── Quarté+ ─────────────────────────────────────────────────────────────────
  static GainResult quarte(double mise, List<double> cotes4, int nbPartants) {
    if (cotes4.length < 4 || mise <= 0) {
      return GainResult.zero(TypePariCalc.quarte, mise);
    }
    final facteur = mise / 2.0;
    final coteMoy = cotes4.fold(0.0, (s, c) => s + c) / 4;
    final facteurCote = (coteMoy / 10.0).clamp(0.5, 4.0);

    // Fourchettes réelles PMU pour Quarté+ (base 2€) :
    // Désordre : min 100€, moy 600€, max 3 000€
    // Ordre    : min 800€, moy 8 000€, max 80 000€
    final minDesordre = (100   * facteur * facteurCote).roundToDouble();
    final maxDesordre = (3000  * facteur * facteurCote).roundToDouble();
    final minOrdre    = (800   * facteur * facteurCote).roundToDouble();
    final maxOrdre    = (80000 * facteur * facteurCote).roundToDouble();

    final gainNetDesordre = (600   * facteur * facteurCote) - mise;
    final gainNetOrdre    = (8000  * facteur * facteurCote) - mise;

    final prob = (_probaTierce(cotes4.take(3).toList(), nbPartants) * 0.30).clamp(0.1, 20.0);
    return GainResult(
      type: TypePariCalc.quarte,
      mise: mise,
      coteUtilisee: 0,
      gainNet: gainNetOrdre,
      gainSiDesordre: gainNetDesordre,
      retourTotal: 8000 * facteur * facteurCote,
      probabiliteEstimee: prob,
      scenarioPessimiste: -mise,
      estFourchette: true,
      fourchetteMinDesordre: minDesordre,
      fourchetteMaxDesordre: maxDesordre,
      fourchetteMinOrdre: minOrdre,
      fourchetteMaxOrdre: maxOrdre,
      explication:
          '4 chevaux dans le top 4\n'
          '⚠️ Dividende fixé par PMU après la course\n'
          'Désordre : entre ${_fmt(minDesordre)} et ${_fmt(maxDesordre)}\n'
          'Dans l\'ordre : entre ${_fmt(minOrdre)} et ${_fmt(maxOrdre)}',
    );
  }

  // ─── Quinté+ ─────────────────────────────────────────────────────────────────
  static GainResult quinte(double mise, List<double> cotes5, int nbPartants) {
    if (cotes5.length < 5 || mise <= 0) {
      return GainResult.zero(TypePariCalc.quinte, mise);
    }
    final facteur = mise / 2.0;
    final coteMoy = cotes5.fold(0.0, (s, c) => s + c) / 5;
    final facteurCote = (coteMoy / 10.0).clamp(0.5, 5.0);

    // Fourchettes réelles PMU pour Quinté+ (base 2€) :
    // Désordre : min 300€, moy 2 500€, max 15 000€
    // Ordre    : min 3 000€, moy 30 000€, max 300 000€
    // 4/5      : min 30€, moy 100€, max 500€
    final minDesordre  = (300     * facteur * facteurCote).roundToDouble();
    final maxDesordre  = (15000   * facteur * facteurCote).roundToDouble();
    final minOrdre     = (3000    * facteur * facteurCote).roundToDouble();
    final maxOrdre     = (300000  * facteur * facteurCote).roundToDouble();
    final min4sur5     = (30      * facteur * facteurCote).roundToDouble();
    final max4sur5     = (500     * facteur * facteurCote).roundToDouble();

    final gainNetDesordre = (2500   * facteur * facteurCote) - mise;
    final gainNetOrdre    = (30000  * facteur * facteurCote) - mise;
    final gainBonus4sur5  = 100     * facteur * facteurCote;

    final prob = (_probaTierce(cotes5.take(3).toList(), nbPartants) * 0.20 * 0.30).clamp(0.05, 5.0);
    return GainResult(
      type: TypePariCalc.quinte,
      mise: mise,
      coteUtilisee: 0,
      gainNet: gainNetOrdre,
      gainSiDesordre: gainNetDesordre,
      gainBonus4sur5: gainBonus4sur5,
      retourTotal: 30000 * facteur * facteurCote,
      probabiliteEstimee: prob,
      scenarioPessimiste: -mise,
      estFourchette: true,
      fourchetteMinDesordre: minDesordre,
      fourchetteMaxDesordre: maxDesordre,
      fourchetteMinOrdre: minOrdre,
      fourchetteMaxOrdre: maxOrdre,
      fourchetteMin4sur5: min4sur5,
      fourchetteMax4sur5: max4sur5,
      explication:
          '5 chevaux dans le top 5 (mise min PMU : 1.50€)\n'
          '⚠️ Dividende fixé par PMU après la course\n'
          'Désordre : entre ${_fmt(minDesordre)} et ${_fmt(maxDesordre)}\n'
          'Dans l\'ordre : entre ${_fmt(minOrdre)} et ${_fmt(maxOrdre)}\n'
          '4/5 bons → consolation entre ${_fmt(min4sur5)} et ${_fmt(max4sur5)}',
    );
  }

  // ─── Utilitaires ─────────────────────────────────────────────────────────────

  static double _cotePlace(double coteGagnant, int nbPartants) {
    if (coteGagnant <= 0) return 1.10;
    final diviseur = nbPartants >= 8 ? 4.0 : nbPartants >= 5 ? 3.0 : 2.0;
    final cotePlace = (coteGagnant - 1) / diviseur + 1;
    // ★ Fix : si coteGagnant est très faible (ex: 1.1), coteGagnant * 0.65 < 1.10
    // → clamp(min, max) avec min > max → crash "Invalid argument(s)"
    // Solution : s'assurer que max >= min avant le clamp
    final maxClamp = (coteGagnant * 0.65).clamp(1.10, double.infinity);
    return cotePlace.clamp(1.10, maxClamp);
  }

  static double cotePlaceDepuisGagnant(double coteGagnant, int nbPartants) {
    return _cotePlace(coteGagnant, nbPartants);
  }

  static double _coteToProbabilite(double cote) {
    if (cote <= 0) return 0;
    return (1 / cote * 100).clamp(1.0, 95.0);
  }

  // ★ v9.93 POINT 3 : Critère de Kelly — mise optimale
  //
  // f* = (b×p - q) / b
  //   b = gain net par unité misée (cote - 1)
  //   p = probabilité estimée de gagner (0-1)
  //   q = probabilité de perdre (1 - p)
  //
  // Retourne la fraction OPTIMALE du bankroll à miser (0.0 - 1.0).
  // On applique un Kelly fractionnel (÷4) pour limiter la volatilité :
  //   Kelly plein → trop agressif pour des probabilités estimées imparfaites.
  //   Kelly ÷4 → fraction sûre, largement utilisée en pratique.
  //
  // Si kelly < 0 → pari sans espérance positive → ne pas miser (retourne 0).
  static double kellyFraction({
    required double cote,          // Cote décimale PMU (ex: 4.5)
    required double probabiliteIA, // Probabilité estimée par l'IA (0-100)
    double diviseur = 4.0,         // Diviseur de sécurité (Kelly fractionnel)
  }) {
    if (cote <= 1.0 || probabiliteIA <= 0) return 0.0;
    final b = cote - 1.0;          // gain net par unité
    final p = probabiliteIA / 100; // prob gagner
    final q = 1.0 - p;             // prob perdre
    final kelly = (b * p - q) / b;
    if (kelly <= 0) return 0.0;    // Pas d'espérance positive
    return (kelly / diviseur).clamp(0.0, 0.25); // max 25% du bankroll
  }

  /// Calcule la mise conseillée par Kelly en euros.
  /// [bankroll] = capital total disponible (ex: 500€)
  /// [cote] = cote PMU décimale
  /// [probabiliteIA] = probabilité estimée par l'IA (0-100)
  static double miseConseilleeKelly({
    required double bankroll,
    required double cote,
    required double probabiliteIA,
  }) {
    final fraction = kellyFraction(cote: cote, probabiliteIA: probabiliteIA);
    if (fraction <= 0) return 0.0;
    return (bankroll * fraction).clamp(1.0, bankroll * 0.25);
  }

  static double _probaTierce(List<double> cotes, int nbPartants) {
    if (cotes.length < 3) return 0;
    final p1 = _coteToProbabilite(cotes[0]) / 100;
    final p2 = _coteToProbabilite(cotes[1]) / 100 * 0.75;
    final p3 = _coteToProbabilite(cotes[2]) / 100 * 0.55;
    return (p1 * p2 * p3 * 100).clamp(0.1, 30.0);
  }

  static String formatEuros(double montant) {
    if (montant.abs() >= 1000000) {
      return '${(montant / 1000000).toStringAsFixed(1)}M€';
    }
    if (montant.abs() >= 1000) {
      return '${(montant / 1000).toStringAsFixed(1)}k€';
    }
    return '${fmtEuros(montant)} €';
  }

  static String formatGain(double gain) {
    final prefix = gain >= 0 ? '+' : '';
    return '$prefix${fmtEuros(gain.abs())} €';
  }

  static String _fmt(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M€';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(0)}k€';
    return '${fmtEuros(v)} €';
  }
  static String _fmtGain(double v) => '${v >= 0 ? "+" : ""}${fmtEuros(v.abs())} €';
}

// ─── Modèles de résultat ──────────────────────────────────────────────────────

enum TypePariCalc {
  simpleGagnant,
  place,
  gagnantEtPlace,
  couple,
  tierce,
  quarte,
  quinte,
}

class GainResult {
  final TypePariCalc type;
  final double mise;
  final double coteUtilisee;
  final double gainNet;
  final double? gainSiPlace;
  final double? gainSiDesordre;
  final double? gainBonus4sur5;
  final double retourTotal;
  final double probabiliteEstimee;
  final double scenarioPessimiste;
  final String explication;

  /// true = paris combiné → fourchette affichée, pas un gain exact
  final bool estFourchette;

  /// Fourchettes pour Tiercé/Quarté/Quinté (null pour paris simples)
  final double? fourchetteMinDesordre;
  final double? fourchetteMaxDesordre;
  final double? fourchetteMinOrdre;
  final double? fourchetteMaxOrdre;
  final double? fourchetteMin4sur5;
  final double? fourchetteMax4sur5;

  GainResult({
    required this.type,
    required this.mise,
    required this.coteUtilisee,
    required this.gainNet,
    this.gainSiPlace,
    this.gainSiDesordre,
    this.gainBonus4sur5,
    required this.retourTotal,
    required this.probabiliteEstimee,
    required this.scenarioPessimiste,
    required this.explication,
    this.estFourchette = false,
    this.fourchetteMinDesordre,
    this.fourchetteMaxDesordre,
    this.fourchetteMinOrdre,
    this.fourchetteMaxOrdre,
    this.fourchetteMin4sur5,
    this.fourchetteMax4sur5,
  });

  double get gainMin => scenarioPessimiste;
  double get gainMax => gainNet;
  double get scenarioOptimiste => gainNet;

  factory GainResult.zero(TypePariCalc type, double mise) {
    return GainResult(
      type: type,
      mise: mise,
      coteUtilisee: 1.0,
      gainNet: 0.0,
      retourTotal: 0.0,
      probabiliteEstimee: 0.0,
      scenarioPessimiste: -mise,
      explication: 'Données insuffisantes pour calculer le gain.',
    );
  }

  bool get isPositif => gainNet > 0;

  String get typeLabel {
    switch (type) {
      case TypePariCalc.simpleGagnant: return 'Simple Gagnant';
      case TypePariCalc.place:         return 'Simple Placé';
      case TypePariCalc.gagnantEtPlace:return 'Gagnant + Placé';
      case TypePariCalc.couple:        return 'Couplé Gagnant';
      case TypePariCalc.tierce:        return 'Tiercé';
      case TypePariCalc.quarte:        return 'Quarté+';
      case TypePariCalc.quinte:        return 'Quinté+';
    }
  }

  String get typeEmoji {
    switch (type) {
      case TypePariCalc.simpleGagnant: return '🏆';
      case TypePariCalc.place:         return '🎯';
      case TypePariCalc.gagnantEtPlace:return '🎯🏆';
      case TypePariCalc.couple:        return '🔗';
      case TypePariCalc.tierce:        return '📋';
      case TypePariCalc.quarte:        return '🎰';
      case TypePariCalc.quinte:        return '🌟';
    }
  }

  String get difficulteLabel {
    switch (type) {
      case TypePariCalc.simpleGagnant: return 'Difficile';
      case TypePariCalc.place:         return 'Facile';
      case TypePariCalc.gagnantEtPlace:return 'Moyen';
      case TypePariCalc.couple:        return 'Moyen';
      case TypePariCalc.tierce:        return 'Difficile';
      case TypePariCalc.quarte:        return 'Très difficile';
      case TypePariCalc.quinte:        return 'Expert';
    }
  }

  /// Label fourchette courte pour l'affichage UI
  String get labelFourchetteOrdre {
    if (!estFourchette || fourchetteMinOrdre == null) return '';
    return '${GainCalculator.formatEuros(fourchetteMinOrdre!)} → ${GainCalculator.formatEuros(fourchetteMaxOrdre!)}';
  }

  String get labelFourchetteDesordre {
    if (!estFourchette || fourchetteMinDesordre == null) return '';
    return '${GainCalculator.formatEuros(fourchetteMinDesordre!)} → ${GainCalculator.formatEuros(fourchetteMaxDesordre!)}';
  }

  String get labelFourchette4sur5 {
    if (!estFourchette || fourchetteMin4sur5 == null) return '';
    return '${GainCalculator.formatEuros(fourchetteMin4sur5!)} → ${GainCalculator.formatEuros(fourchetteMax4sur5!)}';
  }
}

// ─── Rapport PMU réel (après course) ─────────────────────────────────────────

/// Dividende réel reçu depuis l'API PMU rapports-definitifs
class RapportPmu {
  final String typePari;       // ex: "E_TIERCE", "E_QUARTE_PLUS", "E_QUINTE_PLUS"
  final String combinaison;    // ex: "5-12-3" (numéros des chevaux gagnants)
  final double dividende;      // ex: 452.0 (pour 1€ misé)
  final bool estOrdre;         // true = ordre, false = désordre

  const RapportPmu({
    required this.typePari,
    required this.combinaison,
    required this.dividende,
    required this.estOrdre,
  });

  factory RapportPmu.fromJson(Map<String, dynamic> json, {bool estOrdre = false}) {
    return RapportPmu(
      typePari: json['typePari'] as String? ?? '',
      combinaison: json['combinaison'] as String? ?? '',
      dividende: (json['dividende'] as num?)?.toDouble() ?? 0.0,
      estOrdre: estOrdre,
    );
  }

  /// Gain net pour une mise donnée (dividende PMU = retour pour 1€)
  double gainNetPourMise(double mise) => (dividende * mise) - mise;
  double retourPourMise(double mise) => dividende * mise;
}

// ─── Préréglages de mises rapides ────────────────────────────────────────────

class MisePreset {
  final String label;
  final double valeur;
  const MisePreset(this.label, this.valeur);

  static const List<MisePreset> presets = [
    MisePreset('2€', 2),
    MisePreset('5€', 5),
    MisePreset('10€', 10),
    MisePreset('20€', 20),
    MisePreset('50€', 50),
    MisePreset('100€', 100),
  ];
}
