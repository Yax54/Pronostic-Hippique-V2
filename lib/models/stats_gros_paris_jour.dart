// ★ v10.78 — Statistiques Gros Paris pour un jour donné
//
// X = signaux devenus gagnants ce jour-là
// Y = signaux réellement proposés ce jour-là (depuis _signaux persisté)
//
// ⚠️ Règle absolue : Y est lu depuis ia_quasi_gros_paris_v1 (_signaux),
//    jamais recalculé rétrospectivement.
//    _signaux est conservé indéfiniment (MERGE strict, purge > 90j uniquement).

/// Statistiques "Gros Paris à surveiller" pour une journée.
///
/// Compteur affiché dans le Calendrier : 🔥 X/Y
/// - [gagnes]   : X — signaux devenus vrais gagnants ce jour
/// - [proposes] : Y — signaux proposés dans "⚠️ Gros paris à surveiller" ce jour
class StatsGrosParisJour {
  /// Nombre de gros paris gagnants ce jour (ordre ou désordre).
  final int gagnes;

  /// Nombre de signaux proposés ce jour (Y — source de vérité : _signaux).
  final int proposes;

  const StatsGrosParisJour({
    required this.gagnes,
    required this.proposes,
  });

  /// Aucun signal proposé ce jour.
  static const StatsGrosParisJour vide = StatsGrosParisJour(
    gagnes:   0,
    proposes: 0,
  );

  /// Taux de réussite (0.0 → 1.0). Retourne 0.0 si aucun signal proposé.
  double get taux => proposes > 0 ? gagnes / proposes : 0.0;

  /// Taux en pourcentage arrondi (0 → 100).
  int get tauxPourcent => (taux * 100).round();

  /// Vrai s'il y a au moins un signal proposé ce jour.
  bool get aDesSignaux => proposes > 0;

  /// Vrai s'il y a au moins un gagnant parmi les signaux proposés.
  bool get aDesGagnants => gagnes > 0;

  /// Label pour l'affichage dans le compteur du Calendrier.
  /// Format : "🔥 X/Y" ou "" si aucun signal.
  String get labelCompteur {
    if (!aDesSignaux) return '';
    return '🔥 $gagnes/$proposes';
  }

  /// Label avec taux pour les tooltips.
  String get labelAvecTaux {
    if (!aDesSignaux) return 'Aucun gros pari proposé';
    if (proposes == 1) {
      return '🔥 $gagnes gagnant sur 1 signal ($tauxPourcent%)';
    }
    return '🔥 $gagnes gagnant${gagnes > 1 ? "s" : ""} sur $proposes signaux ($tauxPourcent%)';
  }

  @override
  String toString() =>
      'StatsGrosParisJour(gagnes: $gagnes, proposes: $proposes, taux: $tauxPourcent%)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatsGrosParisJour &&
          other.gagnes == gagnes &&
          other.proposes == proposes;

  @override
  int get hashCode => Object.hash(gagnes, proposes);
}
