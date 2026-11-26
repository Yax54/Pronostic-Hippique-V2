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
  Future<void> ecrireEtatElo(String cle, String valeur);

  // ------------------------------------------------------------ rapports
  Future<bool> insererRapport(RapportStocke rapport);
  Future<void> ajouterCopieRapport(CopieRapport copie);
  Future<List<RapportStocke>> tousLesRapports();
  Future<int> compterRapports();
  Future<int> compterCopiesRapport();
  Future<List<CopieRapport>> copiesDuRapport(String empreinte);

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
