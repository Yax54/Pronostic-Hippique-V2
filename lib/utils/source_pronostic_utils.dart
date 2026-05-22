// ★ v10.78 — Utilitaires de classification des sources de pronostic
//
// Règles d'affichage :
//   'grosParisSurveiller' → 🔥  (Gros Pari à surveiller)
//   'programme'           → ⭐  (Best Bet classique / Premium)
//   double signal         → ⭐🔥 (même course présente dans les deux sources)

/// Utilitaires statiques pour classifier et afficher les sources de pronostic.
class SourcePronosticUtils {
  SourcePronosticUtils._();

  // ── Constantes de source ──────────────────────────────────────────────
  static const String sourceGrosParis = 'grosParisSurveiller';
  static const String sourceProgramme = 'programme';

  // ── Classification ────────────────────────────────────────────────────

  /// Vrai si la [source] correspond à un signal "Gros Pari à surveiller".
  static bool estSourceGrosParis(String? source) =>
      source == sourceGrosParis;

  /// Vrai si la [source] correspond au programme classique / Best Bet.
  static bool estSourceBestBetClassique(String? source) =>
      source == sourceProgramme;

  // ── Icônes d'affichage ────────────────────────────────────────────────

  /// Retourne l'icône correspondant à la [source] :
  /// - 🔥  → grosParisSurveiller
  /// - ⭐  → programme (Best Bet classique)
  /// - ''  → source inconnue
  static String iconeSource(String? source) {
    switch (source) {
      case sourceGrosParis:
        return '🔥';
      case sourceProgramme:
        return '⭐';
      default:
        return '';
    }
  }

  /// Icône pour un double signal (même course dans les deux sources).
  static const String iconeDoubleSignal = '⭐🔥';

  /// Retourne l'icône en fonction de la présence des deux signaux.
  /// - [hasBestBet]  : source 'programme' présente
  /// - [hasGrosParis]: source 'grosParisSurveiller' présente
  static String iconeCombinaison({
    required bool hasBestBet,
    required bool hasGrosParis,
  }) {
    if (hasBestBet && hasGrosParis) return iconeDoubleSignal;
    if (hasGrosParis)               return '🔥';
    if (hasBestBet)                 return '⭐';
    return '';
  }

  // ── Labels texte ──────────────────────────────────────────────────────

  /// Libellé court de la [source].
  static String labelSource(String? source) {
    switch (source) {
      case sourceGrosParis:
        return 'Gros Pari';
      case sourceProgramme:
        return 'Best Bet';
      default:
        return source ?? 'Inconnu';
    }
  }

  /// Libellé long pour les tooltips / accessibilité.
  static String labelSourceLong(String? source) {
    switch (source) {
      case sourceGrosParis:
        return 'Gros Pari à surveiller (signal IA)';
      case sourceProgramme:
        return 'Best Bet classique (programme IA)';
      default:
        return source ?? 'Source inconnue';
    }
  }

  // ── Couleurs ──────────────────────────────────────────────────────────
  // (retourne une chaîne hex pour usage dans les widgets)

  /// Code couleur hex associé à la [source].
  /// Utilisé par les widgets pour colorer les badges.
  static String couleurHexSource(String? source) {
    switch (source) {
      case sourceGrosParis:
        return '#FF6B35'; // Orange feu
      case sourceProgramme:
        return '#FFD700'; // Or
      default:
        return '#9E9E9E'; // Gris
    }
  }
}
