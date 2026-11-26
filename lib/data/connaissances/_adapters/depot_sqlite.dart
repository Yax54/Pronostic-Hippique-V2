/// Implémentation SQLite réelle du dépôt de connaissances.
///
/// Consigne §5 / D-17 : SQLite est la technologie retenue pour les catégories
/// volumineuses et structurées. Cette implémentation utilise `sqflite` sur
/// Android et `sqflite_common_ffi` en test, qui exécutent tous deux le **moteur
/// SQLite natif** — les tests ne sont donc pas des simulations en mémoire.
///
/// Points de conception imposés par la consigne, et comment ils sont tenus :
///
/// * **Transactions** (§14, §16) : [transaction] encapsule toute unité de
///   travail atomique ; une interruption laisse la base dans son état antérieur.
/// * **Idempotence** (§14) : toutes les insertions utilisent un `INSERT OR
///   IGNORE` ou un `ON CONFLICT` sur une clé déterministe. Rejouer une étape ne
///   duplique rien.
/// * **Aucune purge** : ce fichier ne contient aucun `DELETE`. Les suppressions
///   relèvent d'une décision explicite de politique, jamais du stockage.
/// * **Valeurs protégées** : les ratings ELO sont écrits et relus en `REAL`
///   sans transformation ; `ControleMigration` compare avant/après.
library;

import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../_core/depot.dart';
import '../_core/empreinte_contenu.dart';
import '../_core/identifiants.dart';
import 'schema_sqlite.dart';

/// Dépôt adossé à une base SQLite.
class DepotSqlite implements DepotConnaissances {
  DepotSqlite({
    required this.chemin,
    DatabaseFactory? fabrique,
    this.verbeux = false,
  }) : _fabrique = fabrique;

  /// Chemin du fichier de base. `inMemoryDatabasePath` pour un test isolé.
  final String chemin;

  /// Fabrique de bases. `null` ⇒ la fabrique par défaut de `sqflite`.
  /// En test, on passe `databaseFactoryFfi`, qui exécute le vrai SQLite.
  final DatabaseFactory? _fabrique;

  final bool verbeux;

  Database? _db;

  /// Exécuteur courant. Vaut `null` hors transaction, et le `Transaction` actif
  /// pendant une transaction. Toutes les opérations passent par lui : sans cela,
  /// une écriture faite depuis l'action d'une transaction utiliserait la base
  /// elle-même au lieu du contexte transactionnel, ce qui provoquerait un
  /// interblocage sur le verrou d'écriture.
  DatabaseExecutor? _txn;

  Database get _base {
    final db = _db;
    if (db == null) {
      throw StateError('Dépôt non ouvert : appeler ouvrir() avant toute lecture.');
    }
    return db;
  }

  /// Exécuteur à utiliser pour toute requête : le `Transaction` s'il y en a un
  /// en cours, sinon la base.
  DatabaseExecutor get _executeur => _txn ?? _base;

  DatabaseFactory get _factory => _fabrique ?? databaseFactory;

  @override
  Future<void> ouvrir() async {
    if (_db != null) return;
    _db = await _factory.openDatabase(
      chemin,
      options: OpenDatabaseOptions(
        version: kVersionSchema,
        onConfigure: (db) async {
          // Clés étrangères : une participation ne peut pas référencer une
          // course inexistante. Cela protège la cohérence des références (§15).
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _appliquerSchema(db);
        },
        onUpgrade: (db, ancienne, nouvelle) async {
          // Aucune version antérieure publiée à ce jour. Si le cas se présente,
          // la migration doit être écrite explicitement, jamais devinée.
          throw StateError(
            'Migration de schéma $ancienne → $nouvelle non définie. '
            'Aucune migration implicite n\'est autorisée.',
          );
        },
      ),
    );
    if (verbeux) {
      // ignore: avoid_print
      print('[DepotSqlite] ouvert: $chemin (schéma v$kVersionSchema)');
    }
  }

  Future<void> _appliquerSchema(Database db) async {
    for (final instruction in kInstructionsCreation) {
      await db.execute(instruction);
    }
    final maintenant = DateTime.now().toUtc().toIso8601String();
    await db.insert('meta', <String, Object?>{
      'cle': 'version_schema',
      'valeur': '$kVersionSchema',
      'maj_le': maintenant,
    });
    await db.insert('meta', <String, Object?>{
      'cle': 'cree_le',
      'valeur': maintenant,
      'maj_le': maintenant,
    });
  }

  @override
  Future<void> fermer() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  @override
  Future<int> versionSchema() async {
    final rows = await _executeur.query('meta',
        columns: <String>['valeur'], where: 'cle = ?', whereArgs: <Object?>['version_schema']);
    if (rows.isEmpty) return 0;
    return int.tryParse('${rows.first['valeur']}') ?? 0;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    // Transaction imbriquée : on réutilise la transaction en cours au lieu
    // d'en ouvrir une seconde, qui serait rejetée par SQLite et laisserait un
    // état incohérent. Une transaction imbriquée devient donc une unité de la
    // transaction englobante.
    if (_txn != null) return action();
    return _base.transaction<T>((txn) async {
      _txn = txn;
      try {
        return await action();
      } finally {
        _txn = null;
      }
    });
  }

  // ------------------------------------------------------------------ chevaux

  @override
  Future<void> upsertCheval(IdentiteCheval identite, {String? nomAffichage}) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    await _executeur.insert(
      'chevaux',
      <String, Object?>{
        'id': identite.id,
        'nom_normalise': identite.nomNormalise,
        'nom_affichage': nomAffichage ?? identite.nomNormalise,
        'niveau_identite': identite.niveau.name,
        'id_fournisseur': identite.idFournisseur,
        'annee_naissance': identite.anneeNaissance,
        'sexe': identite.sexe,
        'cree_le': maintenant,
        'maj_le': maintenant,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> ajouterAlias(String idCheval, String alias, String provenance) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    await _executeur.insert(
      'chevaux_alias',
      <String, Object?>{
        'id_cheval': idCheval,
        'alias_normalise': normaliserNom(alias),
        'provenance': provenance,
        'cree_le': maintenant,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<List<Map<String, Object?>>> chevauxParNom(String nomNormalise) {
    return _executeur.query('chevaux',
        where: 'nom_normalise = ?', whereArgs: <Object?>[nomNormalise]);
  }

  @override
  Future<int> compterChevaux() async => _compter('chevaux');

  // -------------------------------------------------------- entités nommées

  @override
  Future<String> upsertEntiteNommee({
    required String role,
    required String nom,
  }) async {
    final id = cleEntiteNommee(role: role, nom: nom);
    final maintenant = DateTime.now().toUtc().toIso8601String();
    await _executeur.insert(
      'entites_nommees',
      <String, Object?>{
        'id': id,
        'role': role,
        'nom_normalise': normaliserNom(nom),
        'nom_affichage': nom,
        'cree_le': maintenant,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id;
  }

  @override
  Future<int> compterEntites() async => _compter('entites_nommees');

  // --------------------------------------------------------------------- ELO

  @override
  Future<void> upsertElo(LigneElo ligne) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    final valeurs = <String, Object?>{
      'id': ligne.cle,
      'nom_origine': ligne.nomOrigine,
      'nom_normalise': normaliserNom(ligne.nomOrigine),
      'discipline': ligne.discipline,
      'rating': ligne.rating,
      'nb': ligne.nb,
      'var': ligne.var_,
      'id_cheval': ligne.idCheval,
      'cree_le': maintenant,
      'maj_le': maintenant,
    };
    // Remplacement de la valeur courante, la ligne garde sa clé d'origine :
    // aucune valeur n'est moyennée, additionnée ni fusionnée (D-24).
    await _executeur.insert('elo_ratings', valeurs,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<LigneElo?> lireElo(String cle) async {
    final rows = await _base
        .query('elo_ratings', where: 'id = ?', whereArgs: <Object?>[cle], limit: 1);
    if (rows.isEmpty) return null;
    return _eloDepuisLigne(rows.first);
  }

  @override
  Future<List<LigneElo>> tousLesElo() async {
    final rows = await _executeur.query('elo_ratings', orderBy: 'id ASC');
    return rows.map(_eloDepuisLigne).toList(growable: false);
  }

  LigneElo _eloDepuisLigne(Map<String, Object?> r) => LigneElo(
        cle: '${r['id']}',
        nomOrigine: '${r['nom_origine']}',
        discipline: '${r['discipline']}',
        // Lecture en double sans arrondi : la valeur doit être identique.
        rating: (r['rating'] as num).toDouble(),
        nb: (r['nb'] as num).toInt(),
        var_: (r['var'] as num).toDouble(),
        idCheval: r['id_cheval'] as String?,
      );

  @override
  Future<int> compterElo() async => _compter('elo_ratings');

  @override
  Future<void> ecrireEtatElo(String cle, String valeur) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    await _executeur.insert(
      'elo_etats',
      <String, Object?>{'cle': cle, 'valeur': valeur, 'maj_le': maintenant},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------- rapports

  @override
  Future<bool> insererRapport(RapportStocke rapport) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    // `INSERT OR IGNORE` sur une empreinte UNIQUE : une seconde insertion du
    // même contenu est un no-op. C'est l'idempotence exigée par §14.
    final id = await _executeur.insert(
      'rapports',
      <String, Object?>{
        'id': rapport.empreinte,
        'date_rapport': rapport.dateRapport,
        'empreinte': rapport.empreinte,
        'schema_version': rapport.schemaVersion,
        'contenu': rapport.contenu,
        'contenu_normalise': rapport.contenuNormalise,
        'taille_origine': rapport.tailleOrigine,
        'cree_le': maintenant,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id != 0;
  }

  @override
  Future<void> ajouterCopieRapport(CopieRapport copie) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    await _executeur.insert(
      'rapports_sources',
      <String, Object?>{
        'empreinte': copie.empreinte,
        'source': copie.source,
        'position': copie.position,
        'chemin': copie.chemin,
        'cree_le': maintenant,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<List<RapportStocke>> tousLesRapports() async {
    final rows = await _executeur.query('rapports', orderBy: 'date_rapport ASC, id ASC');
    return rows
        .map((r) => RapportStocke(
              empreinte: '${r['empreinte']}',
              dateRapport: '${r['date_rapport']}',
              contenu: '${r['contenu']}',
              contenuNormalise: '${r['contenu_normalise']}',
              tailleOrigine: (r['taille_origine'] as num).toInt(),
              schemaVersion: (r['schema_version'] as num).toInt(),
            ))
        .toList(growable: false);
  }

  @override
  Future<int> compterRapports() async => _compter('rapports');

  @override
  Future<int> compterCopiesRapport() async => _compter('rapports_sources');

  @override
  Future<List<CopieRapport>> copiesDuRapport(String empreinte) async {
    final rows = await _executeur.query('rapports_sources',
        where: 'empreinte = ?', whereArgs: <Object?>[empreinte]);
    return rows
        .map((r) => CopieRapport(
              empreinte: '${r['empreinte']}',
              source: '${r['source']}',
              position: (r['position'] as num).toInt(),
              chemin: r['chemin'] as String?,
            ))
        .toList(growable: false);
  }

  // -------------------------------------------------------------- pronostics

  @override
  Future<bool> insererPronostic({
    required String empreinte,
    required String contenu,
    String? dateCourse,
    String? cleCourse,
    String? resultatOfficiel,
    bool archive = false,
  }) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    final id = await _executeur.insert(
      'pronostics',
      <String, Object?>{
        'id': empreinte,
        'cle_course': cleCourse,
        'date_course': dateCourse,
        'contenu': contenu,
        'empreinte': empreinte,
        'resultat_officiel': resultatOfficiel,
        'archive': archive ? 1 : 0,
        'cree_le': maintenant,
        'maj_le': maintenant,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id != 0;
  }

  @override
  Future<int> compterPronostics({bool? archive}) async {
    final rows = await _executeur.rawQuery(
      archive == null
          ? 'SELECT COUNT(*) AS n FROM pronostics'
          : 'SELECT COUNT(*) AS n FROM pronostics WHERE archive = ?',
      archive == null ? const <Object?>[] : <Object?>[archive ? 1 : 0],
    );
    return (rows.first['n'] as num).toInt();
  }

  @override
  Future<int> compterPronosticsAvecResultat() async {
    final rows = await _executeur.rawQuery(
      'SELECT COUNT(*) AS n FROM pronostics WHERE resultat_officiel IS NOT NULL',
    );
    return (rows.first['n'] as num).toInt();
  }

  // ---------------------------------------------------------------- conflits

  @override
  Future<void> enregistrerConflit({
    required String categorie,
    required String description,
    String? cleEntite,
    String? valeurLocale,
    String? valeurDistante,
  }) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    final id = empreinteValeur(<String, Object?>{
      'categorie': categorie,
      'cle': cleEntite,
      'locale': valeurLocale,
      'distante': valeurDistante,
      'description': description,
    }).substring(0, 32);
    await _executeur.insert(
      'conflits',
      <String, Object?>{
        'id': id,
        'categorie': categorie,
        'cle_entite': cleEntite,
        'description': description,
        'valeur_locale': valeurLocale,
        'valeur_distante': valeurDistante,
        'resolution': 'en_attente',
        'cree_le': maintenant,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<int> compterConflits({String? resolution}) async {
    final rows = await _executeur.rawQuery(
      resolution == null
          ? 'SELECT COUNT(*) AS n FROM conflits'
          : 'SELECT COUNT(*) AS n FROM conflits WHERE resolution = ?',
      resolution == null ? const <Object?>[] : <Object?>[resolution],
    );
    return (rows.first['n'] as num).toInt();
  }

  // ----------------------------------------------------------------- journal

  @override
  Future<void> journaliser({
    required String operation,
    required String etape,
    required String statut,
    String? detail,
  }) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    final id = empreinteValeur(<String, Object?>{
      'op': operation,
      'etape': etape,
      'statut': statut,
      'detail': detail,
    }).substring(0, 32);
    await _executeur.insert(
      'journal_operations',
      <String, Object?>{
        'id': id,
        'operation': operation,
        'etape': etape,
        'statut': statut,
        'detail': detail,
        'horodatage': maintenant,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<List<Map<String, Object?>>> journalDeLOperation(String operation) {
    return _executeur.query('journal_operations',
        where: 'operation = ?',
        whereArgs: <Object?>[operation],
        orderBy: 'horodatage ASC');
  }

  // -------------------------------------------------------------------- méta

  @override
  Future<void> ecrireMeta(String cle, String valeur) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    await _executeur.insert(
      'meta',
      <String, Object?>{'cle': cle, 'valeur': valeur, 'maj_le': maintenant},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<String?> lireMeta(String cle) async {
    final rows = await _base
        .query('meta', where: 'cle = ?', whereArgs: <Object?>[cle], limit: 1);
    if (rows.isEmpty) return null;
    return '${rows.first['valeur']}';
  }

  Future<int> _compter(String table) async {
    final rows = await _executeur.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return (rows.first['n'] as num).toInt();
  }

  /// Exécute une instruction SQL brute. Réservé aux diagnostics et aux tests de
  /// volumétrie : la logique métier ne doit pas dépendre de cette méthode.
  Future<void> executerSqlBrut(String sql) async {
    await _executeur.execute(sql);
  }

  /// Exporte la liste des tables et leur nombre de lignes. Sert aux diagnostics
  /// et aux contrôles d'intégrité de sauvegarde (§15 : inventaire des blocs).
  Future<Map<String, int>> inventaire() async {
    final tables = await _executeur.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%' ORDER BY name",
    );
    final out = <String, int>{};
    for (final t in tables) {
      final nom = '${t['name']}';
      out[nom] = await _compter(nom);
    }
    return out;
  }

  /// Contrôle d'intégrité du moteur SQLite lui-même.
  /// `ok` ⇒ aucune corruption détectée (§15, contrôle d'intégrité global).
  Future<String> integrite() async {
    final rows = await _executeur.rawQuery('PRAGMA integrity_check');
    return rows.map((r) => '${r.values.first}').join('; ');
  }

  /// Taille du fichier de base en octets, `0` si la base est en mémoire.
  Future<int> tailleFichier() async {
    if (chemin == inMemoryDatabasePath) return 0;
    final rows = await _executeur.rawQuery(
      'SELECT page_count * page_size AS n FROM pragma_page_count(), pragma_page_size()',
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Sérialise une ligne de rating pour les tests de non-régression.
  static String encoderElo(LigneElo ligne) => jsonEncode(ligne.toJson());
}
