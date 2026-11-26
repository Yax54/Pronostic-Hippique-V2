/// Abstraction du dépôt de connaissances, indépendante du support physique.
///
/// Consigne §5 : « Mettre en place les abstractions nécessaires pour tester la
/// logique métier indépendamment du support physique. Les tests en mémoire ou
/// sur Web ne doivent pas être présentés comme une validation du comportement
/// réel de SQLite sur Android. Prévoir également des tests utilisant une
/// véritable base SQLite. »
///
/// Cette interface est volontairement étroite : elle expose les opérations dont
/// la logique métier a besoin, pas les détails SQL. Deux implémentations
/// existent :
///
/// * [DepotSqlite] — vraie base SQLite via `sqflite` (Android) ou
///   `sqflite_common_ffi` (tests de bureau sur le **moteur SQLite réel**).
/// * [DepotMemoire] — dépôt en mémoire, réservé aux tests de logique pure.
///
/// Une mesure obtenue avec [DepotMemoire] ne prouve **rien** sur le
/// comportement de SQLite. Les tests d'intégrité (transactions, contraintes,
/// collisions d'index) doivent utiliser [DepotSqlite].
library;

import 'dart:convert';

import 'empreinte_contenu.dart';
import 'identifiants.dart';

/// Ligne d'un rating ELO telle que conservée par la migration.
///
/// `cle` est la clé d'origine **verbatim** (`NOM|DISCIPLINE`), ce qui garantit
/// une restitution identique bit à bit (§12).
class LigneElo {
  const LigneElo({
    required this.cle,
    required this.nomOrigine,
    required this.discipline,
    required this.rating,
    required this.nb,
    required this.var_,
    this.idCheval,
  });

  final String cle;
  final String nomOrigine;
  final String discipline;
  final double rating;
  final int nb;
  final double var_;
  final String? idCheval;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': cle,
        'nom_origine': nomOrigine,
        'nom_normalise': normaliserNom(nomOrigine),
        'discipline': discipline,
        'rating': rating,
        'nb': nb,
        'var': var_,
        'id_cheval': idCheval,
      };

  @override
  String toString() => 'LigneElo($cle, rating=$rating, nb=$nb, var=$var_)';
}

/// Rapport avec son contenu d'origine intégral (donc `fnum2` inclus).
class RapportStocke {
  const RapportStocke({
    required this.empreinte,
    required this.dateRapport,
    required this.contenu,
    required this.contenuNormalise,
    required this.tailleOrigine,
    required this.schemaVersion,
  });

  final String empreinte;
  final String dateRapport;

  /// Contenu d'origine, jamais altéré. `fnum2` y est présent s'il y était.
  final String contenu;

  /// Projection normalisée, réversible (marqueur `Absent`, rien de supprimé).
  final String contenuNormalise;

  final int tailleOrigine;
  final int schemaVersion;

  /// Vérifie que la normalisation est bien réversible pour ce rapport.
  bool get normalisationReversible {
    final denorm = denormaliserContenu(
      _decoder(contenuNormalise),
    );
    return serialiserCanonique(denorm) == serialiserCanonique(_decoder(contenu));
  }

  static Object? _decoder(String brut) {
    final objet = decoderJsonTolerant(brut);
    return objet;
  }
}

/// Une copie physique d'un rapport, avec sa provenance.
class CopieRapport {
  const CopieRapport({
    required this.empreinte,
    required this.source,
    required this.position,
    this.chemin,
  });

  final String empreinte;

  /// `collection`, `bilan_semaine`, `bilan_mois`, ...
  final String source;

  /// Position dans la structure d'origine ; `-1` si non applicable.
  final int position;

  final String? chemin;
}

/// Bilan hebdomadaire ou mensuel conservé comme agrégat historique.
///
/// Consigne §13 : un bilan référence les versions **exactes** des rapports
/// utilisés, jamais « la dernière version disponible ». D'où [references] qui
/// porte des empreintes, et non des dates.
class BilanStocke {
  const BilanStocke({
    required this.id,
    required this.type,
    required this.contenu,
    required this.empreinte,
    required this.schemaVersion,
    this.periodeDebut,
    this.periodeFin,
    this.annee,
    this.mois,
    this.semaine,
    this.references = const <ReferenceRapport>[],
  });

  /// `bilan_semaine` ou `bilan_mois`.
  final String type;

  final String id;
  final String contenu;
  final String empreinte;
  final int schemaVersion;
  final String? periodeDebut;
  final String? periodeFin;
  final int? annee;
  final int? mois;
  final int? semaine;

  /// Références vers les versions exactes de rapports consommées.
  final List<ReferenceRapport> references;
}

/// Référence d'un bilan vers une version exacte de rapport.
class ReferenceRapport {
  const ReferenceRapport({
    required this.role,
    required this.empreinte,
    required this.ordre,
  });

  /// `rj` (rapport journalier), `sem` (bilan de semaine imbriqué), ...
  final String role;

  /// Empreinte du **contenu** du rapport : identifie une version exacte.
  final String empreinte;

  /// Position, qui conserve l'ordre et la multiplicité.
  final int ordre;
}

/// Résultat de comparaison avant/après migration, sur les valeurs protégées.
class ControleMigration {
  ControleMigration({
    required this.eloAvant,
    required this.eloApres,
    required this.rapportsAvant,
    required this.rapportsApres,
    required this.ecartsElo,
    required this.ecartsRapports,
  });

  final int eloAvant;
  final int eloApres;
  final int rapportsAvant;
  final int rapportsApres;

  /// Détail des écarts constatés : vide ⇒ identité prouvée.
  final List<String> ecartsElo;
  final List<String> ecartsRapports;

  bool get eloIdentique => eloAvant == eloApres && ecartsElo.isEmpty;
  bool get rapportsIdentiques =>
      rapportsAvant == rapportsApres && ecartsRapports.isEmpty;
  bool get conforme => eloIdentique && rapportsIdentiques;

  Map<String, Object?> toJson() => <String, Object?>{
        'elo_avant': eloAvant,
        'elo_apres': eloApres,
        'elo_identique': eloIdentique,
        'ecarts_elo': ecartsElo,
        'rapports_avant': rapportsAvant,
        'rapports_apres': rapportsApres,
        'rapports_identiques': rapportsIdentiques,
        'ecarts_rapports': ecartsRapports,
        'conforme': conforme,
      };
}

/// Contrat du dépôt de connaissances.
///
/// Toute opération d'écriture est **idempotente** ou explicitement versionnée :
/// une reprise après interruption ne doit produire ni doublon ni perte (§14).
abstract class DepotConnaissances {
  /// Ouvre le dépôt et applique le schéma si nécessaire.
  Future<void> ouvrir();

  /// Ferme le dépôt.
  Future<void> fermer();

  /// Version du schéma effectivement appliquée.
  Future<int> versionSchema();

  // -------------------------------------------------------------- chevaux
  Future<void> upsertCheval(IdentiteCheval identite, {String? nomAffichage});
  Future<void> ajouterAlias(String idCheval, String alias, String provenance);
  Future<List<Map<String, Object?>>> chevauxParNom(String nomNormalise);
  Future<int> compterChevaux();

  // ---------------------------------------------------------- entités nommées
  Future<String> upsertEntiteNommee({
    required String role,
    required String nom,
  });
  Future<int> compterEntites();

  // --------------------------------------------------------------- ELO
  Future<void> upsertElo(LigneElo ligne);
  Future<LigneElo?> lireElo(String cle);
  Future<List<LigneElo>> tousLesElo();
  Future<int> compterElo();
  /// Écrit un lot de ratings dans une seule instruction SQL.
  ///
  /// Exigence §19 : éviter les requêtes répétées et les réécritures inutiles.
  /// Une restauration de 9 001 ratings ne doit pas produire 9 001 allers-retours
  /// SQL. Le remplacement se fait sur la clé d'origine, sans fusion (D-24).
  Future<void> upsertEloEnLot(List<LigneElo> lignes);

  /// Lit un lot de ratings par leurs clés, en une seule requête.
  Future<Map<String, LigneElo>> lireEloEnLot(List<String> cles);

  Future<void> ecrireEtatElo(String cle, String valeur);

  // ------------------------------------------------------------ rapports
  Future<bool> insererRapport(RapportStocke rapport);
  Future<void> ajouterCopieRapport(CopieRapport copie);
  Future<List<RapportStocke>> tousLesRapports();
  Future<int> compterRapports();
  Future<int> compterCopiesRapport();
  Future<List<CopieRapport>> copiesDuRapport(String empreinte);

  // ---------------------------------------------------------------- bilans
  /// Enregistre un bilan. Idempotent sur son empreinte de contenu.
  Future<bool> insererBilan(BilanStocke bilan);

  /// Référence un rapport par sa **version exacte** (empreinte de contenu).
  Future<void> ajouterReferenceBilan(ReferenceRapport reference, String idBilan);

  Future<List<BilanStocke>> tousLesBilans({String? type});

  Future<int> compterBilans({String? type});

  /// Vérifie qu'aucune référence de bilan ne pointe vers un rapport absent.
  /// Une référence orpheline signalerait une restauration partielle.
  Future<int> compterReferencesOrphelines();

  // -------------------------------------------------------------- pronostics
  Future<bool> insererPronostic({
    required String empreinte,
    required String contenu,
    String? dateCourse,
    String? cleCourse,
    String? resultatOfficiel,
    bool archive,
  });
  Future<int> compterPronostics({bool? archive});
  Future<int> compterPronosticsAvecResultat();

  // ---------------------------------------------------------------- conflits
  Future<void> enregistrerConflit({
    required String categorie,
    required String description,
    String? cleEntite,
    String? valeurLocale,
    String? valeurDistante,
  });
  Future<int> compterConflits({String? resolution});

  // ---------------------------------------------------------------- journal
  Future<void> journaliser({
    required String operation,
    required String etape,
    required String statut,
    String? detail,
  });
  Future<List<Map<String, Object?>>> journalDeLOperation(String operation);

  // -------------------------------------------------------------- méta
  Future<void> ecrireMeta(String cle, String valeur);
  Future<String?> lireMeta(String cle);

  /// Exécute une unité de travail atomique. Si [action] lève, tout est annulé.
  Future<T> transaction<T>(Future<T> Function() action);
}

/// Décode un JSON de façon tolérante : renvoie la valeur décodée, ou la chaîne
/// brute si le contenu n'est pas du JSON valide. Une donnée illisible n'est
/// jamais remplacée par du vide : elle est conservée telle quelle (§13).
Object? decoderJsonTolerant(String brut) {
  try {
    return jsonDecode(brut);
  } on FormatException {
    return brut;
  }
}
