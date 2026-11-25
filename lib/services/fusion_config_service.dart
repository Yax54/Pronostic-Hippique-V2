import 'package:shared_preferences/shared_preferences.dart';
import 'best_bet_engine.dart';

/// Service de persistance de la configuration de fusion
///
/// ⚠️ BL1-A16 — SERVICE INATTEIGNABLE, CONSERVÉ ET DOCUMENTÉ.
///
///   MESURE (`grep -rn "FusionConfigService" lib/`) : 0 appelant. Les trois
///   méthodes `load`, `save` et `reset` ne sont invoquées nulle part. Seule
///   mention externe : un commentaire de `backup_service.dart:29` qui liste
///   les 4 clés persistées ci-dessous.
///
///   COHÉRENCE DU CONSTAT : les clés `fusion_poids_confiance`,
///   `fusion_poids_gain`, `fusion_poids_risque` et `fusion_seuil_min` sont
///   donc écrites par aucune interface et restaurées par la sauvegarde — une
///   configuration morte mais sauvegardée.
///
///   AUCUNE CORRECTION APPLIQUÉE : raccorder ce service suppose de raccorder
///   `FusionConfigScreen`, donc `BestBetEngine.computeAll`, qui contredit la
///   directive financière (voir l'en-tête de `best_bet_engine.dart`).
///   STATUT : DÉCISION UTILISATEUR INDISPENSABLE. Le code est conservé : §16
///   interdit de supprimer un composant sur la seule absence d'import.
///
///   ⚠️ La cohérence `total < 0.99 || total > 1.01` ci-dessous est SAINE et
///   n'est pas concernée par BL1-A04/A06 : elle porte sur les 3 poids de
///   FUSION de cet écran mort, pas sur les 19 critères de l'IA.
class FusionConfigService {
  static const _keyConfiance = 'fusion_poids_confiance';
  static const _keyGain      = 'fusion_poids_gain';
  static const _keyRisque    = 'fusion_poids_risque';
  static const _keySeuil     = 'fusion_seuil_min';

  /// Charger la config depuis les préférences (ou retourner la config conseillée)
  static Future<FusionConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final confiance = prefs.getDouble(_keyConfiance);
      if (confiance == null) return FusionConfig.conseillee;

      final gain    = prefs.getDouble(_keyGain)    ?? 0.25;
      final risque  = prefs.getDouble(_keyRisque)  ?? 0.10;
      final seuil   = prefs.getInt(_keySeuil)      ?? 42;

      // Vérification de cohérence
      final total = confiance + gain + risque;
      if (total < 0.99 || total > 1.01) return FusionConfig.conseillee;

      return FusionConfig(
        poidsConfiance:    confiance,
        poidsGain:         gain,
        poidsRisque:       risque,
        seuilConfianceMin: seuil,
      );
    } catch (_) {
      return FusionConfig.conseillee;
    }
  }

  /// Sauvegarder la config dans les préférences
  static Future<void> save(FusionConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyConfiance, config.poidsConfiance);
      await prefs.setDouble(_keyGain,      config.poidsGain);
      await prefs.setDouble(_keyRisque,    config.poidsRisque);
      await prefs.setInt(_keySeuil,        config.seuilConfianceMin);
    } catch (_) {}
  }

  /// Réinitialiser aux valeurs conseillées
  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyConfiance);
      await prefs.remove(_keyGain);
      await prefs.remove(_keyRisque);
      await prefs.remove(_keySeuil);
    } catch (_) {}
  }

  /// Vérifier si la config actuelle est la config conseillée
  static bool estConfigConseillee(FusionConfig config) {
    return (config.poidsConfiance - FusionConfig.conseillee.poidsConfiance).abs() < 0.01 &&
           (config.poidsGain      - FusionConfig.conseillee.poidsGain).abs()      < 0.01 &&
           (config.poidsRisque    - FusionConfig.conseillee.poidsRisque).abs()    < 0.01 &&
            config.seuilConfianceMin == FusionConfig.conseillee.seuilConfianceMin;
  }
}
