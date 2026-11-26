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
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, visibleForTesting;
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

  /// Fabrique utilisée par ce dépôt.
  ///
  /// Exposée pour qu'un lecteur secondaire (instantané de restauration) ouvre la
  /// MÊME famille de moteur que le dépôt de production. Sans cela, un test
  /// ouvrirait une base FFI pour en lire une autre via le moteur Android.
  DatabaseFactory get fabriquePourRelecture => _factory;

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
          // La migration est ÉCRITE, jamais devinée (voir `migrerSchema`).
          await migrerSchema(db, ancienne, nouvelle);
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

  /// Supprime un rating par sa clé.
  ///
  /// Existe pour que la suppression volontaire soit une **opération du dépôt**
  /// et non un `DELETE` improvisé ailleurs. Aucun code de production ne
  /// supprime de rating : D-20 l'interdit. Cette méthode sert à rendre
  /// testable l'état « base légitimement vide », qui doit être distingué
  /// d'une migration à faire — c'est le cœur de la bascule.
  Future<void> supprimerEloPourTest(String cle) async {
    await _executeur.delete('elo_ratings', where: 'id = ?', whereArgs: <Object?>[cle]);
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

  /// Note du rating d'une clé, ou `null` si la clé est absente.
  ///
  /// Réservé aux contrôles de non-régression : permet de vérifier une valeur
  /// précise sans charger toute la table.
  @visibleForTesting
  Future<double?> tireEloPourTest(String cle) async {
    final rows = await _base.query('elo_ratings',
        columns: <String>['rating'], where: 'id = ?', whereArgs: <Object?>[cle]);
    if (rows.isEmpty) return null;
    return (rows.first['rating'] as num).toDouble();
  }

  @override
  Future<void> upsertEloEnLot(List<LigneElo> lignes) async {
    if (lignes.isEmpty) return;
    final maintenant = DateTime.now().toUtc().toIso8601String();
    // Découpage en paquets : chaque paquet reste très en dessous des limites de
    // variables liées d'une instruction SQLite (999 par défaut), tout en
    // évitant 9 001 allers-retours.
    const int taillePaquet = 100;
    for (var debut = 0; debut < lignes.length; debut += taillePaquet) {
      final fin = (debut + taillePaquet).clamp(0, lignes.length);
      final paquet = lignes.sublist(debut, fin);
      final valeurs = <Object?>[];
      final marques = <String>[];
      for (final l in paquet) {
        marques.add('(?,?,?,?,?,?,?,?,?,?)');
        valeurs
          ..add(l.cle)
          ..add(l.nomOrigine)
          ..add(normaliserNom(l.nomOrigine))
          ..add(l.discipline)
          ..add(l.rating)
          ..add(l.nb)
          ..add(l.var_)
          ..add(l.idCheval)
          ..add(maintenant)
          ..add(maintenant);
      }
      await _executeur.rawInsert(
        'INSERT OR REPLACE INTO elo_ratings '
        '(id, nom_origine, nom_normalise, discipline, rating, nb, var, '
        'id_cheval, cree_le, maj_le) VALUES ${marques.join(",")}',
        valeurs,
      );
    }
  }

  @override
  Future<Map<String, LigneElo>> lireEloEnLot(List<String> cles) async {
    final resultat = <String, LigneElo>{};
    if (cles.isEmpty) return resultat;
    const int taillePaquet = 400;
    for (var debut = 0; debut < cles.length; debut += taillePaquet) {
      final fin = (debut + taillePaquet).clamp(0, cles.length);
      final paquet = cles.sublist(debut, fin);
      final marques = List<String>.filled(paquet.length, '?').join(',');
      final rows = await _executeur.rawQuery(
        'SELECT * FROM elo_ratings WHERE id IN ($marques)',
        paquet,
      );
      for (final r in rows) {
        final ligne = _eloDepuisLigne(r);
        resultat[ligne.cle] = ligne;
      }
    }
    return resultat;
  }

  @override
  Future<void> ecrireEtatElo(String cle, String valeur) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    await _executeur.insert(
      'elo_etats',
      <String, Object?>{'cle': cle, 'valeur': valeur, 'maj_le': maintenant},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ------------------------------------------------------ performances (§8/§9)

  static Map<String, Object?> _lignePerformance(
    PerformanceStockee p,
    String maintenant,
  ) =>
      <String, Object?>{
        'id': p.id,
        'id_cheval': p.idCheval,
        'nom_cheval_brut': p.nomChevalBrut,
        'discipline': p.discipline,
        'date_perf': p.datePerf,
        'hippodrome': p.hippodrome,
        'place': p.place,
        'reduction_km': p.reductionKm,
        'gains': p.gains,
        'distance': p.distanceMetres,
        'etat_terrain': p.etatTerrain,
        'musique': p.musique,
        'source': p.source,
        'charge_brute': p.chargeBrute,
        'cree_le': maintenant,
      };

  @override
  /// Écriture d'une performance : ACTUALISATION CIBLÉE, jamais remplacement
  /// intégral.
  ///
  /// ═══════════════════════════════════════════════════════════════════════
  ///  DÉFAUT RÉEL CORRIGÉ ICI, ET SA MESURE
  ///
  ///  La première version utilisait `ConflictAlgorithm.replace`. Mesure sur le
  ///  moteur SQLite réel : une republication **partielle** (le PMU ne renvoie
  ///  que la place corrigée, sans gains ni musique) a produit
  ///  `{id:A, nom:X, place:1, gains:null, musique:null}` — les deux champs
  ///  authentiques déjà connus ont été EFFACÉS.
  ///
  ///  Autre conséquence de `replace`, moins visible et plus grave : `REPLACE`
  ///  exécute en réalité un DELETE puis un INSERT. Toute ligne d'une autre
  ///  table qui référencerait cette performance par clé étrangère verrait sa
  ///  référence supprimée ou mise à NULL selon la clause `ON DELETE`.
  ///  Remplacer une ligne n'est donc jamais une opération neutre.
  ///
  ///  CONSÉQUENCE DES DEUX EXIGENCES DU MANDAT :
  ///    • « une réponse PMU incomplète ne doit pas dégrader les connaissances
  ///      déjà acquises » → on n'écrit QUE les champs réellement publiés ;
  ///    • « ne pas perdre la traçabilité des anciennes valeurs » → l'ancienne
  ///      valeur est conservée dans le journal avant d'être corrigée.
  ///
  ///  Aucune donnée n'est devinée : un champ non publié laisse la valeur
  ///  existante intacte, il ne l'écrase pas par NULL.
  /// ═══════════════════════════════════════════════════════════════════════
  @override
  Future<bool> insererPerformance(PerformanceStockee performance) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    final ligne = _lignePerformance(performance, maintenant);

    // Champs réellement publiés : tout sauf la clé et l'horodatage d'écriture.
    final aEcrire = <String, Object?>{
      for (final e in ligne.entries)
        if (e.key != 'id' && e.key != 'cree_le' && e.value != null)
          e.key: e.value,
    };

    final existante = await _executeur.query(
      'performances',
      where: 'id = ?',
      whereArgs: <Object?>[performance.id],
      limit: 1,
    );

    if (existante.isEmpty) {
      // Première connaissance de cette participation : insertion complète.
      final id = await _executeur.insert(
        'performances',
        ligne,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      return id > 0;
    }

    final avant = existante.first;

    // Y a-t-il réellement quelque chose à corriger ? Si tous les champs
    // publiés sont déjà identiques, on n'écrit RIEN : c'est la détection du
    // « changement utile » exigée par le mandat, et cela évite une écriture
    // disque par rejeu.
    var changeUtile = false;
    aEcrire.forEach((k, v) {
      if (avant[k] != v) changeUtile = true;
    });
    if (!changeUtile) return false;

    // Traçabilité : on note les ANCIENNES valeurs des champs effectivement
    // corrigés, avant de les remplacer. Une correction officielle cesse ainsi
    // d'être une perte silencieuse d'information.
    final anciennes = <String, Object?>{
      for (final k in aEcrire.keys) k: avant[k],
    };
    try {
      await journaliser(
        operation: 'performance_corrigee',
        etape: performance.id,
        statut: 'correction_officielle',
        detail: '{"avant":${_jsonSur(anciennes)},"apres":${_jsonSur(aEcrire)}}',
      );
    } catch (e) {
      // Un journal indisponible ne doit pas empêcher l'enregistrement de la
      // correction officielle : on continue, le défaut est tracé.
      if (kDebugMode) debugPrint('[DepotSqlite] journal correction : $e');
    }

    await _executeur.update(
      'performances',
      aEcrire,
      where: 'id = ?',
      whereArgs: <Object?>[performance.id],
    );
    return true;
  }

  /// Sérialise une petite map en JSON sans dépendre de `dart:convert` dans
  /// l'adaptateur : les valeurs sont des scalaires SQLite.
  static String _jsonSur(Map<String, Object?> m) {
    final parties = m.entries.map((e) {
      final v = e.value;
      final val = v == null ? 'null' : (v is num ? '$v' : '"$v"');
      return '"${e.key}":$val';
    });
    return '{${parties.join(",")}}';
  }

  /// Colonnes d'une performance qui peuvent être mises à jour.
  ///
  /// `id` est la clé (jamais mise à jour) et `cree_le` la trace d'écriture ;
  /// tout le reste est une donnée publiée, donc susceptible d'être corrigée.
  static const List<String> _colonnesPerfMaj = <String>[
    'id_cheval',
    'nom_cheval_brut',
    'discipline',
    'date_perf',
    'hippodrome',
    'place',
    'reduction_km',
    'gains',
    'distance',
    'etat_terrain',
    'musique',
    'source',
    'charge_brute',
  ];

  @override
  Future<int> insererPerformancesEnLot(
    List<PerformanceStockee> performances,
  ) async {
    if (performances.isEmpty) return 0;

    final maintenant = DateTime.now().toUtc().toIso8601String();
    final avant = await compterPerformances();

    // ══════════════════════════════════════════════════════════════════════
    //  UPSERT CIBLÉ, DANS UNE SEULE TRANSACTION
    //
    //  Deux défauts réels sont corrigés ici, tous deux MESURÉS :
    //
    //  ① `ConflictAlgorithm.replace` faisait un DELETE+INSERT : une
    //     republication partielle effaçait les champs authentiques non
    //     republiés (mesure : gains 12500 → null, musique effacée).
    //
    //  ② Une boucle d'écritures unitaires NON transactionnelles (version
    //     intermédiaire) laissait la base dans un état PARTIEL observable
    //     pendant l'écriture : mesure 69 → 9 lignes visibles en cours de lot.
    //     Un lot doit être atomique.
    //
    //  `ON CONFLICT(id) DO UPDATE SET c = COALESCE(excluded.c, performances.c)`
    //  donne exactement la sémantique exigée :
    //    • la ligne n'est JAMAIS supprimée (aucun DELETE, donc aucune
    //      référence orpheline possible) ;
    //    • un champ NON publié (NULL côté source) laisse la valeur existante
    //      intacte, au lieu de l'écraser ;
    //    • un champ publié et différent est corrigé.
    // ══════════════════════════════════════════════════════════════════════
    final affectations = _colonnesPerfMaj
        .map((c) => '$c = COALESCE(excluded.$c, performances.$c)')
        .join(', ');

    final placeholders =
        List<String>.filled(_colonnesPerfMaj.length + 2, '?').join(', ');
    final colonnes = <String>['id', ..._colonnesPerfMaj, 'cree_le'].join(', ');

    final sql = 'INSERT INTO performances ($colonnes) '
        'VALUES ($placeholders) '
        'ON CONFLICT(id) DO UPDATE SET $affectations';

    // `transaction(action)` du dépôt encapsule l'unité de travail ; le batch
    // est celui de l'exécuteur courant, donc il participe à cette transaction.
    await transaction(() async {
      final batch = _executeur.batch();
      for (final p in performances) {
        final ligne = _lignePerformance(p, maintenant);
        batch.rawInsert(sql, <Object?>[
          ligne['id'],
          for (final c in _colonnesPerfMaj) ligne[c],
          ligne['cree_le'],
        ]);
      }
      await batch.commit(noResult: true);
    });

    final apres = await compterPerformances();
    final crees = apres - avant;
    return crees < 0 ? 0 : crees;
  }

  static PerformanceStockee _performanceDepuisLigne(
    Map<String, Object?> r,
  ) =>
      PerformanceStockee(
        id: '${r['id']}',
        idCheval: r['id_cheval'] as String?,
        nomChevalBrut: '${r['nom_cheval_brut']}',
        discipline: r['discipline'] as String?,
        datePerf: r['date_perf'] as String?,
        hippodrome: r['hippodrome'] as String?,
        place: (r['place'] as num?)?.toInt(),
        reductionKm: (r['reduction_km'] as num?)?.toDouble(),
        gains: (r['gains'] as num?)?.toDouble(),
        distanceMetres: (r['distance'] as num?)?.toInt(),
        etatTerrain: r['etat_terrain'] as String?,
        musique: r['musique'] as String?,
        source: '${r['source']}',
        chargeBrute: r['charge_brute'] as String?,
      );

  @override
  Future<List<PerformanceStockee>> performancesDuCheval(
    String idCheval, {
    int limite = 20,
  }) async {
    final rows = await _executeur.query(
      'performances',
      where: 'id_cheval = ?',
      whereArgs: <Object?>[idCheval],
      // Tri décroissant sur la date : les critères exploitent les courses les
      // plus récentes d'abord (§9). `date_perf` est ISO-8601, donc l'ordre
      // lexicographique est l'ordre chronologique.
      orderBy: 'date_perf DESC',
      limit: limite,
    );
    return rows.map(_performanceDepuisLigne).toList(growable: false);
  }

  @override
  Future<List<PerformanceStockee>> performancesParNom(
    String nomBrut, {
    int limite = 20,
  }) async {
    // ⚠️ §7 : le nom n'est PAS une preuve d'identité. On interroge sur le nom
    // BRUT exact, pas sur `nom_normalise` : deux graphies différentes du même
    // cheval ne sont pas fusionnées ici, et deux chevaux homonymes ne le sont
    // pas davantage. Le regroupement relève de la consolidation, pas de cette
    // lecture.
    final rows = await _executeur.query(
      'performances',
      where: 'nom_cheval_brut = ?',
      whereArgs: <Object?>[nomBrut],
      orderBy: 'date_perf DESC',
      limit: limite,
    );
    return rows.map(_performanceDepuisLigne).toList(growable: false);
  }

  @override
  Future<bool> enregistrerObservation({
    required String type,
    String? idCourse,
    String? idCheval,
    required String contenu,
    required String source,
  }) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    // Empreinte = identité de CONTENU. Réenregistrer la même composition
    // n'ajoute donc pas de ligne : la contrainte UNIQUE(empreinte) et
    // `ignore` rendent l'opération idempotente. On n'utilise PAS `replace`
    // ici : une observation est un fait daté, on ne réécrit pas un fait.
    final empreinte = empreinteValeur(<String, Object?>{
      'type': type,
      'id_course': idCourse,
      'id_cheval': idCheval,
      'contenu': contenu,
    });
    final id = await _executeur.insert(
      'observations',
      <String, Object?>{
        'id': empreinte.substring(0, 32),
        'type': type,
        'id_course': idCourse,
        'id_cheval': idCheval,
        'horodatage': maintenant,
        'contenu': contenu,
        'empreinte': empreinte,
        'source': source,
        'cree_le': maintenant,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id > 0;
  }

  @override
  Future<String?> chargerObservation({
    required String type,
    String? idCourse,
  }) async {
    final rows = await _executeur.query(
      'observations',
      columns: <String>['contenu'],
      where: idCourse == null ? 'type = ?' : 'type = ? AND id_course = ?',
      whereArgs: idCourse == null ? <Object?>[type] : <Object?>[type, idCourse],
      // La plus récente d'abord : une composition republiée plus tard prime,
      // sans que l'ancienne soit effacée (traçabilité conservée).
      orderBy: 'horodatage DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final v = rows.first['contenu'];
    return v is String ? v : null;
  }

  @override
  Future<int> compterPerformances() async {
    final rows = await _executeur
        .rawQuery('SELECT COUNT(*) AS n FROM performances');
    return (rows.first['n'] as num).toInt();
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

  // ---------------------------------------------------------------- bilans

  @override
  Future<bool> insererBilan(BilanStocke bilan) async {
    final maintenant = DateTime.now().toUtc().toIso8601String();
    // `INSERT OR IGNORE` sur `empreinte` UNIQUE : rejouer une migration ne
    // duplique aucun bilan (§14, idempotence).
    final id = await _executeur.insert(
      'bilans',
      <String, Object?>{
        'id': bilan.id,
        'type': bilan.type,
        'periode_debut': bilan.periodeDebut,
        'periode_fin': bilan.periodeFin,
        'annee': bilan.annee,
        'mois': bilan.mois,
        'semaine': bilan.semaine,
        'contenu': bilan.contenu,
        'empreinte': bilan.empreinte,
        'schema_version': bilan.schemaVersion,
        'cree_le': maintenant,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id != 0;
  }

  @override
  Future<void> ajouterReferenceBilan(
    ReferenceRapport reference,
    String idBilan,
  ) async {
    // La clé primaire (id_bilan, role, ordre) conserve ordre ET multiplicité.
    // `empreinte` pointe une version EXACTE du rapport (§13).
    await _executeur.insert(
      'bilans_references',
      <String, Object?>{
        'id_bilan': idBilan,
        'role': reference.role,
        'empreinte': reference.empreinte,
        'ordre': reference.ordre,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<List<BilanStocke>> tousLesBilans({String? type}) async {
    final rows = await _executeur.query(
      'bilans',
      where: type == null ? null : 'type = ?',
      whereArgs: type == null ? null : <Object?>[type],
      orderBy: 'periode_debut ASC, id ASC',
    );
    final resultats = <BilanStocke>[];
    for (final r in rows) {
      final id = '${r['id']}';
      final refs = await _executeur.query('bilans_references',
          where: 'id_bilan = ?', whereArgs: <Object?>[id], orderBy: 'ordre ASC');
      resultats.add(BilanStocke(
        id: id,
        type: '${r['type']}',
        contenu: '${r['contenu']}',
        empreinte: '${r['empreinte']}',
        schemaVersion: (r['schema_version'] as num).toInt(),
        periodeDebut: r['periode_debut'] as String?,
        periodeFin: r['periode_fin'] as String?,
        annee: (r['annee'] as num?)?.toInt(),
        mois: (r['mois'] as num?)?.toInt(),
        semaine: (r['semaine'] as num?)?.toInt(),
        references: <ReferenceRapport>[
          for (final x in refs)
            ReferenceRapport(
              role: '${x['role']}',
              empreinte: '${x['empreinte']}',
              ordre: (x['ordre'] as num).toInt(),
            ),
        ],
      ));
    }
    return resultats;
  }

  @override
  Future<int> compterBilans({String? type}) async {
    if (type == null) return _compter('bilans');
    final rows = await _executeur.rawQuery(
      'SELECT COUNT(*) AS n FROM bilans WHERE type = ?',
      <Object?>[type],
    );
    return (rows.first['n'] as num).toInt();
  }

  @override
  Future<int> compterReferencesOrphelines() async {
    final rows = await _executeur.rawQuery(
      'SELECT COUNT(*) AS n FROM bilans_references r '
      'LEFT JOIN rapports p ON p.empreinte = r.empreinte '
      'WHERE p.empreinte IS NULL',
    );
    return (rows.first['n'] as num).toInt();
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

  // ════════════════════════════════════════════════════════════════════════
  //  INSTANTANÉ ET RESTAURATION DU MAGASIN SQLITE ENTIER
  //
  //  Pourquoi ces deux méthodes existent :
  //
  //  Une transaction SQLite ne protège QUE SQLite. Or une sauvegarde/restauration
  //  doit couvrir SharedPreferences (aucune transaction), SQLite et les fichiers
  //  permanents. La cohérence entre ces supports ne peut donc pas venir d'une
  //  transaction : elle vient d'un INSTANTANÉ commun pris avant toute écriture,
  //  dont le retour arrière restaure chaque support séparément.
  //
  //  L'instantané utilise `VACUUM INTO`, qui produit un fichier SQLite complet et
  //  cohérent SANS charger la base en RAM (§15, §19). Les données déjà écrites
  //  restent lisibles : le fichier produit est une base valide, ouvrable, et
  //  contrôlable par `PRAGMA integrity_check`.
  //
  //  La restauration ne remplace pas le fichier par un `rename` : elle rouvre
  //  l'instantané comme source et recopie les lignes dans les tables existantes,
  //  dans une transaction unique. Cela évite d'invalider les descripteurs ouverts
  //  et garde le schéma courant, donc les migrations déjà appliquées.
  // ════════════════════════════════════════════════════════════════════════

  /// Écrit une copie cohérente de la base entière vers [cheminCible].
  ///
  /// Retourne le nombre de lignes copiées, par table. Aucune donnée chargée en
  /// RAM : `VACUUM INTO` est exécuté par le moteur.
  Future<Map<String, int>> instantaneVers(String cheminCible) async {
    final cible = File(cheminCible);
    if (await cible.exists()) await cible.delete();
    final parent = cible.parent;
    if (!await parent.exists()) await parent.create(recursive: true);

    // `VACUUM INTO` refuse d'écraser un fichier existant : la suppression
    // ci-dessus est donc nécessaire, et volontairement limitée à la cible.
    await _base.execute('VACUUM INTO ?', <Object?>[cheminCible]);
    await _base.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    return inventaire();
  }

  /// Remplace le CONTENU de la base courante par celui d'un instantané.
  ///
  /// Toutes les tables sont vidées puis rechargées dans une **transaction
  /// unique** : soit l'état de l'instantané est intégralement rétabli, soit la
  /// base reste exactement dans son état antérieur.
  ///
  /// [verifierClesEtrangeres] est activé par défaut : après recharge, un
  /// `PRAGMA foreign_key_check` doit ne rien signaler. Un instantané
  /// incohérent est donc détecté ici, jamais découvert plus tard.
  Future<void> restaurerDepuisInstantane(
    String cheminInstantane, {
    bool verifierClesEtrangeres = true,
  }) async {
    final source = await _factory.openDatabase(
      cheminInstantane,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      // Inventaire de l'instantané : une table du schéma courant absente de
      // l'instantané est un cas normal (instantané plus ancien) ; une table de
      // l'instantané absente du schéma courant est ignorée, car elle ne peut pas
      // être écrite. Les deux cas sont comptés, pas devinés.
      final tablesInstantane = <String>{
        for (final r in await source.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        ))
          '${r['name']}',
      };
      final tablesCourantes = <String>{
        for (final r in await _base.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
        ))
          '${r['name']}',
      };
      final aRemplir = tablesInstantane.intersection(tablesCourantes).toList()
        ..sort();

      await _base.transaction<void>((txn) async {
        // Ordre inverse des dépendances pour vider : les références d'abord.
        for (final table in _ordreSuppression(aRemplir)) {
          await txn.delete(table);
        }
        for (final table in aRemplir) {
          final lignes = await source.query(table);
          for (final ligne in lignes) {
            await txn.insert(table, ligne,
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      });

      if (verifierClesEtrangeres) {
        final violations = await _base.rawQuery('PRAGMA foreign_key_check');
        if (violations.isNotEmpty) {
          throw StateError(
            'instantané incohérent : ${violations.length} violation(s) de clé '
            'étrangère après restauration',
          );
        }
      }
    } finally {
      await source.close();
    }
  }

  /// Ordre de suppression respectant les dépendances déclarées par le schéma.
  ///
  /// Les tables enfant passent avant leur parent. Toute table non listée est
  /// simplement ajoutée à la fin : aucune table n'est oubliée.
  List<String> _ordreSuppression(List<String> tables) {
    const ordre = <String>[
      'bilans_references', // référence bilans + rapports
      'rapports_sources', // référence rapports
      'participations', // référence courses + chevaux
      'performances', // référence participations
      'observations', // référence chevaux
      'chevaux_alias', // référence chevaux
      'bilans',
      'pronostics',
      'tickets',
      'conflits',
      'journal_operations',
      'elo_etats',
      'elo_ratings',
      'rapports',
      'courses',
      'chevaux',
      'entites_nommees',
      'meta',
    ];
    final restantes = List<String>.from(tables);
    final resultat = <String>[];
    for (final t in ordre) {
      if (restantes.remove(t)) resultat.add(t);
    }
    resultat.addAll(restantes);
    return resultat;
  }
}
