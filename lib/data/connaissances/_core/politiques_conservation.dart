/// Politiques de conservation déclarées, par catégorie de connaissance.
///
/// Consigne §5 : huit catégories de connaissance à distinguer.
/// Consigne §11 : « Aucun plafond arbitraire pour les connaissances permanentes
/// utiles », « Aucune suppression de connaissances pour atteindre une taille de
/// stockage prédéfinie ».
///
/// Ce registre rend chaque politique **explicite et vérifiable**. Il remplace
/// des plafonds dispersés et implicites par une déclaration unique, consultable
/// par le code comme par les diagnostics.
library;

/// Nature d'une connaissance. La distinction commande la politique applicable et
/// ce qui est perdu en cas de suppression.
enum NatureConnaissance {
  /// Fait hippique authentique fourni par le PMU (F1).
  faitPmu,

  /// Observation locale authentique, non rediffusée par le PMU (F1 locale).
  /// Sa perte est **irréversible** : le PMU ne la redonnera pas.
  observationLocale,

  /// Statistique déterministe recalculable à partir des faits (F2).
  statistiqueCalculee,

  /// Connaissance issue de l'apprentissage (F3) : non recalculable sans
  /// rejouer l'historique.
  apprentissage,

  /// Pronostic historique figé : ne doit jamais être recalculé (consigne §3).
  pronosticFige,

  /// Donnée financière : intégrité forte exigée.
  financier,

  /// Paramètre ou petite configuration.
  parametre,

  /// Cache entièrement reconstructible.
  cache,
}

/// Politique d'écriture applicable à une catégorie.
enum PolitiqueEcriture {
  /// Ajout seul : une ligne écrite n'est plus modifiée.
  ajoutSeul,

  /// Remplacement de la valeur courante, avec conservation des versions.
  remplacementVersionne,

  /// Fusion par identité démontrée.
  fusionParIdentite,

  /// Remplacement simple.
  remplacement,
}

/// Description déclarative d'une politique de conservation.
class PolitiqueConservation {
  const PolitiqueConservation({
    required this.categorie,
    required this.nature,
    required this.supportCible,
    required this.ecriture,
    required this.conservationPermanente,
    required this.commentaire,
  });

  /// Nom technique de la catégorie (clé de registre).
  final String categorie;

  final NatureConnaissance nature;

  /// Support de stockage cible, conforme à l'organisation des dossiers.
  final String supportCible;

  final PolitiqueEcriture ecriture;

  /// `true` : jamais supprimé automatiquement. `false` : peut être purgé selon
  /// une règle **explicite** de la catégorie.
  final bool conservationPermanente;

  /// Justification lisible, destinée aux diagnostics et à la documentation.
  final String commentaire;

  Map<String, Object?> toJson() => <String, Object?>{
        'categorie': categorie,
        'nature': nature.name,
        'support': supportCible,
        'ecriture': ecriture.name,
        'permanent': conservationPermanente,
        'commentaire': commentaire,
      };
}

/// Registre des politiques de conservation.
///
/// Chaque entrée est justifiée par la nature de la connaissance. Aucune
/// catégorie permanente n'est soumise à un plafond arbitraire.
class RegistrePolitiques {
  const RegistrePolitiques();

  static const List<PolitiqueConservation> entrees = <PolitiqueConservation>[
    PolitiqueConservation(
      categorie: 'faits_courses',
      nature: NatureConnaissance.faitPmu,
      supportCible: 'base/pronostic.db::courses',
      ecriture: PolitiqueEcriture.ajoutSeul,
      conservationPermanente: true,
      commentaire:
          'Fait authentique PMU. Aucune purge : une course courue ne disparaît '
          'jamais. Archive au-delà de la fenêtre active, sans suppression.',
    ),
    PolitiqueConservation(
      categorie: 'faits_participations',
      nature: NatureConnaissance.faitPmu,
      supportCible: 'base/pronostic.db::participations',
      ecriture: PolitiqueEcriture.ajoutSeul,
      conservationPermanente: true,
      commentaire:
          'Fait authentique PMU rattaché à une course et à une identité. '
          'Conservation permanente, aucun plafond.',
    ),
    PolitiqueConservation(
      categorie: 'observations_locales',
      nature: NatureConnaissance.observationLocale,
      supportCible: 'base/pronostic.db::observations',
      ecriture: PolitiqueEcriture.ajoutSeul,
      conservationPermanente: true,
      commentaire:
          'Observation non rediffusée par le PMU (cote horodatée, composition '
          'connue à un instant). Perte IRRÉVERSIBLE : jamais purgée.',
    ),
    PolitiqueConservation(
      categorie: 'ratings_elo',
      nature: NatureConnaissance.apprentissage,
      supportCible: 'base/pronostic.db::elo_ratings',
      ecriture: PolitiqueEcriture.remplacementVersionne,
      conservationPermanente: true,
      commentaire:
          'Rating ELO (D-20 validé) : conservation intégrale, y compris les '
          'ratings dont l\'identité n\'est pas résolue. Jamais de plafond, '
          'jamais de purge automatique.',
    ),
    PolitiqueConservation(
      categorie: 'rapports',
      nature: NatureConnaissance.faitPmu,
      supportCible: 'base/pronostic.db::rapports',
      ecriture: PolitiqueEcriture.ajoutSeul,
      conservationPermanente: true,
      commentaire:
          'Rapport journalier identifié par empreinte de contenu (D-12). '
          'La limite de consultation active ne vaut jamais limite de '
          'conservation définitive.',
    ),
    PolitiqueConservation(
      categorie: 'bilans',
      nature: NatureConnaissance.statistiqueCalculee,
      supportCible: 'base/pronostic.db::bilans',
      ecriture: PolitiqueEcriture.ajoutSeul,
      conservationPermanente: true,
      commentaire:
          'Agrégats historiques conservés + références vers la version EXACTE '
          'du rapport utilisé. Jamais de repointage vers la dernière version.',
    ),
    PolitiqueConservation(
      categorie: 'pronostics_actifs',
      nature: NatureConnaissance.pronosticFige,
      supportCible: 'base/pronostic.db::pronostics',
      ecriture: PolitiqueEcriture.ajoutSeul,
      conservationPermanente: false,
      commentaire:
          'Pronostic sans résultat officiel : purge après 90 jours conforme à '
          'la règle existante. Un pronostic AVEC résultat officiel bascule en '
          'pronostics_archives et devient permanent (§11).',
    ),
    PolitiqueConservation(
      categorie: 'pronostics_archives',
      nature: NatureConnaissance.pronosticFige,
      supportCible: 'archives/pronostics',
      ecriture: PolitiqueEcriture.ajoutSeul,
      conservationPermanente: true,
      commentaire:
          'Pronostic disposant d\'un résultat officiel : conservé sans limite '
          'de durée (§11). Jamais recalculé (§3).',
    ),
    PolitiqueConservation(
      categorie: 'poids_ia',
      nature: NatureConnaissance.apprentissage,
      supportCible: 'config/poids_ia',
      ecriture: PolitiqueEcriture.remplacementVersionne,
      conservationPermanente: true,
      commentaire:
          'Poids et poids par discipline. Conservés avec leur empreinte '
          'datée (D-28 : stockage uniquement). Aucune fabrication rétroactive '
          'de versions inexistantes.',
    ),
    PolitiqueConservation(
      categorie: 'etats_apprentissage',
      nature: NatureConnaissance.apprentissage,
      supportCible: 'config/etats_apprentissage',
      ecriture: PolitiqueEcriture.remplacementVersionne,
      conservationPermanente: true,
      commentaire:
          'Seuils, calibration, TOP3 Learning. Restaurés par préservation, '
          'jamais par fusion mathématique arbitraire (D-24).',
    ),
    PolitiqueConservation(
      categorie: 'donnees_financieres',
      nature: NatureConnaissance.financier,
      supportCible: 'base/pronostic.db::tickets',
      ecriture: PolitiqueEcriture.ajoutSeul,
      conservationPermanente: true,
      commentaire:
          'Tickets et données financières. Intégrité forte, jamais purgées, '
          'jamais modifiées par une migration.',
    ),
    PolitiqueConservation(
      categorie: 'parametres',
      nature: NatureConnaissance.parametre,
      supportCible: 'SharedPreferences + config/',
      ecriture: PolitiqueEcriture.remplacement,
      conservationPermanente: true,
      commentaire:
          'Paramètres, profil, alertes, widgets. Restent dans '
          'SharedPreferences : support adapté, aucun déplacement nécessaire.',
    ),
    PolitiqueConservation(
      categorie: 'caches',
      nature: NatureConnaissance.cache,
      supportCible: 'cache/',
      ecriture: PolitiqueEcriture.remplacement,
      conservationPermanente: false,
      commentaire:
          'Entièrement reconstructibles. Exclus de la sauvegarde SI leur '
          'absence ne perd aucune connaissance, donnée utilisateur ni état '
          'd\'apprentissage (§15).',
    ),
  ];

  /// Retourne la politique d'une catégorie, ou `null` si elle n'est pas
  /// déclarée. Un `null` est un signal : toute catégorie écrite doit avoir une
  /// politique, sinon sa durabilité n'est pas définie.
  static PolitiqueConservation? pour(String categorie) {
    for (final p in entrees) {
      if (p.categorie == categorie) return p;
    }
    return null;
  }

  /// Les catégories dont la perte est définitive.
  static List<String> get irreversibles => entrees
      .where((p) =>
          p.nature == NatureConnaissance.observationLocale ||
          p.nature == NatureConnaissance.apprentissage)
      .map((p) => p.categorie)
      .toList(growable: false);

  static Map<String, Object?> toJson() => <String, Object?>{
        'version': 1,
        'entrees': [for (final p in entrees) p.toJson()],
      };
}
