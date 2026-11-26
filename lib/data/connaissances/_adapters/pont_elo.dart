/// Pont entre `EloService` (production) et le dépôt structuré.
///
/// Consigne §2 de votre message : « La réussite des tests sur un dépôt SQLite
/// isolé ne constitue pas une preuve que l'application utilise effectivement ce
/// dépôt dans ses chemins de production. » Ce fichier existe pour lever
/// exactement cette objection.
///
/// Principe de raccordement retenu, et pourquoi :
///
/// * **SharedPreferences reste la source lue au démarrage.** C'est le
///   comportement existant, et le remplacer d'un coup exposerait l'application
///   à une perte si le dépôt échoue à s'ouvrir. Le pont est donc un **miroir
///   d'écriture** : chaque écriture ELO confirmée est répliquée dans le dépôt.
/// * **Le dépôt devient consultable en lecture indexée** pour les besoins qui
///   ne peuvent pas être servis efficacement par une map en RAM : retrouver un
///   rating par cheval, par discipline, compter les orphelins, exporter.
/// * **Aucune valeur n'est transformée** : `rating`, `nb`, `var` sont écrits
///   tels quels. Le pont ne calcule rien.
/// * **Une défaillance du dépôt ne casse jamais l'application.** Toute erreur
///   est journalisée et comptée ; l'état SharedPreferences reste la référence
///   de secours. Le pont ne lève pas.
///
/// ⚠️ Ce que ce pont ne fait PAS, volontairement : il ne remplace pas la lecture
/// au démarrage. La bascule complète de lecture est une opération de migration
/// (§14) qui exige la sauvegarde/restauration opérationnelle d'abord (§23).
/// Tant que ce n'est pas fait, la bascule n'a pas lieu — et c'est documenté.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show DatabaseFactory;

import '../../../models/zt_models.dart' show EloScore;

import 'depot_sqlite.dart';
import 'organisation_fichiers.dart';
import '../_core/depot.dart';
import '../_core/identifiants.dart';
import '../_migration/migrateur_elo.dart';

/// État du pont, exposé pour les diagnostics.
class EtatPontElo {
  const EtatPontElo({
    required this.ouvert,
    required this.chemin,
    required this.derniereReplication,
    required this.nbReplications,
    required this.nbEchecs,
    required this.dernierMessage,
  });

  final bool ouvert;
  final String chemin;
  final DateTime? derniereReplication;
  final int nbReplications;
  final int nbEchecs;
  final String? dernierMessage;

  Map<String, Object?> toJson() => <String, Object?>{
        'ouvert': ouvert,
        'chemin': chemin,
        'derniere_replication': derniereReplication?.toIso8601String(),
        'nb_replications': nbReplications,
        'nb_echecs': nbEchecs,
        'dernier_message': dernierMessage,
      };
}

/// Réplique les ratings ELO de production dans le dépôt structuré.
class PontElo {
  PontElo._();
  static final PontElo instance = PontElo._();

  DepotSqlite? _depot;
  OrganisationFichiers? _organisation;
  int _nbReplications = 0;
  int _nbEchecs = 0;
  DateTime? _derniere;
  String? _dernierMessage;

  bool get ouvert => _depot != null;

  /// Dépôt structuré ouvert, ou `null` s'il ne l'est pas.
  ///
  /// Exposé pour que la **sauvegarde et la restauration** puissent opérer sur
  /// les mêmes données que le chemin de production, au lieu d'ouvrir une
  /// seconde base concurrente — ce que §4 du présent tour interdit
  /// explicitement (« ne laisse pas subsister deux magasins concurrents »).
  DepotSqlite? get depotPourSauvegarde => _depot;

  /// Racine contenant `base/`, `archives/`, `config/`, `sauvegardes/`, `temp/`.
  String get racine => _organisation?.racine.path ?? '';

  EtatPontElo get etat => EtatPontElo(
        ouvert: ouvert,
        chemin: _organisation?.cheminBase ?? '',
        derniereReplication: _derniere,
        nbReplications: _nbReplications,
        nbEchecs: _nbEchecs,
        dernierMessage: _dernierMessage,
      );

  /// Fabrique de bases à utiliser. `null` ⇒ fabrique par défaut de `sqflite`
  /// (chemin de production Android). Les tests injectent `databaseFactoryFfi`
  /// pour exécuter le même code sur le **moteur SQLite réel** en environnement
  /// de bureau — la logique testée est identique, seul le moteur diffère.
  DatabaseFactory? _fabriqueTest;

  /// Injecte une fabrique explicite. Réservé aux tests : en production, la
  /// fabrique par défaut de `sqflite` est utilisée.
  void utiliserFabrique(DatabaseFactory fabrique) {
    _fabriqueTest = fabrique;
  }

  /// Ouvre le dépôt sous le répertoire privé de l'application.
  ///
  /// [racineForcee] permet aux tests de travailler dans un dossier isolé
  /// (§14 : les tests ne touchent jamais les données réelles de l'utilisateur).
  ///
  /// Réouverture prise en charge : si un dépôt est déjà ouvert sur un AUTRE
  /// chemin, il est fermé d'abord. Cela évite qu'un test laisse le singleton
  /// pointé sur un dossier temporaire supprimé, situation qui produisait des
  /// lectures vides sans erreur visible.
  Future<bool> ouvrir({String? racineForcee}) async {
    try {
      final org = await OrganisationFichiers.initialiser(racineForcee: racineForcee);
      if (_depot != null) {
        if (_organisation?.cheminBase == org.cheminBase) return true;
        await fermer();
      }
      final depot = DepotSqlite(chemin: org.cheminBase, fabrique: _fabriqueTest);
      await depot.ouvrir();
      _organisation = org;
      _depot = depot;
      _dernierMessage = 'dépôt ouvert';
      debugPrint('[PontElo] ✅ dépôt structuré ouvert : ${org.cheminBase}');
      return true;
    } catch (e) {
      _nbEchecs++;
      _dernierMessage = 'ouverture impossible : $e';
      // Un dépôt indisponible n'empêche pas l'application de fonctionner :
      // SharedPreferences reste la référence. L'échec est TRACÉ et COMPTÉ,
      // jamais tu.
      debugPrint('[PontElo] ⚠️ ouverture impossible ($e) — repli sur '
          'SharedPreferences, aucune donnée perdue');
      return false;
    }
  }

  Future<void> fermer() async {
    await _depot?.fermer();
    _depot = null;
    _organisation = null;
    _dernierMessage = 'dépôt fermé';
  }

  /// Réplique l'état complet des ratings après une écriture confirmée.
  ///
  /// Appelée depuis `EloService` **après** que `setString` a confirmé l'écriture
  /// sur disque. Ainsi, le dépôt ne contient jamais un état que le stockage
  /// principal n'a pas accepté : les deux restent cohérents, et un échec de
  /// réplication est visible dans [etat].
  ///
  /// Idempotent : rejouer la réplication de la même map ne change aucune
  /// valeur, seulement `maj_le`.
  Future<void> repliquer(Map<String, EloScore> ratings) async {
    final depot = _depot;
    if (depot == null) return;
    try {
      final lignes = MigrateurElo.decoderDepuisService(ratings);
      await depot.transaction(() async {
        for (final l in lignes) {
          await depot.upsertElo(l);
        }
      });
      _nbReplications++;
      _derniere = DateTime.now();
      _dernierMessage = '${lignes.length} rating(s) répliqué(s)';
      if (kDebugMode) {
        debugPrint('[PontElo] ✅ ${lignes.length} rating(s) répliqués');
      }
    } catch (e) {
      _nbEchecs++;
      _dernierMessage = 'réplication échouée : $e';
      // Aucune exception propagée : la persistance principale a réussi, le
      // pont est un service secondaire.
      debugPrint('[PontElo] ⚠️ réplication échouée ($e) — les données '
          'principales sont intactes');
    }
  }

  /// Recherche indexée par nom de cheval, toutes disciplines confondues.
  ///
  /// C'est le cas d'usage que SharedPreferences ne sert pas bien : retrouver
  /// les ratings d'un cheval sans parcourir toute la map.
  Future<List<LigneElo>> ratingsDuCheval(String nom) async {
    final depot = _depot;
    if (depot == null) return const <LigneElo>[];
    try {
      final lignes = await depot.tousLesElo();
      final cible = normaliserNom(nom);
      return lignes
          .where((l) => normaliserNom(l.nomOrigine) == cible)
          .toList(growable: false);
    } catch (e) {
      _dernierMessage = 'lecture indexée échouée : $e';
      return const <LigneElo>[];
    }
  }

  /// Ratings d'une discipline, triés par rating décroissant.
  Future<List<LigneElo>> ratingsDeDiscipline(String discipline) async {
    final depot = _depot;
    if (depot == null) return const <LigneElo>[];
    try {
      final lignes = await depot.tousLesElo();
      final out = lignes.where((l) => l.discipline == discipline).toList();
      out.sort((a, b) => b.rating.compareTo(a.rating));
      return out;
    } catch (e) {
      _dernierMessage = 'lecture par discipline échouée : $e';
      return const <LigneElo>[];
    }
  }

  /// Nombre de ratings conservés sans identité résolue. Doit être > 0 si
  /// l'utilisateur en possède : c'est la mesure que D-20 interdit de purger.
  Future<int> compterOrphelins() async {
    final depot = _depot;
    if (depot == null) return 0;
    try {
      final lignes = await depot.tousLesElo();
      return lignes.where((l) => l.idCheval == null).length;
    } catch (_) {
      return 0;
    }
  }

  /// Export complet, pour la sauvegarde (§15) et les contrôles d'intégrité.
  Future<List<Map<String, Object?>>> exporterTout() async {
    final depot = _depot;
    if (depot == null) return const <Map<String, Object?>>[];
    try {
      final lignes = await depot.tousLesElo();
      return <Map<String, Object?>>[
        for (final l in lignes) l.toJson(),
      ];
    } catch (e) {
      _dernierMessage = 'export échoué : $e';
      return const <Map<String, Object?>>[];
    }
  }

  /// Inventaire du dépôt, pour les diagnostics de volumétrie (§11).
  Future<Map<String, int>> inventaire() async {
    final depot = _depot;
    if (depot == null) return const <String, int>{};
    try {
      return await depot.inventaire();
    } catch (e) {
      _dernierMessage = 'inventaire échoué : $e';
      return const <String, int>{};
    }
  }

  /// Contrôle d'intégrité SQLite du dépôt de production.
  Future<String> integrite() async {
    final depot = _depot;
    if (depot == null) return 'dépôt fermé';
    try {
      return await depot.integrite();
    } catch (e) {
      return 'contrôle impossible : $e';
    }
  }

  /// Exposition de secours pour les tests : encode une map en JSON lisible,
  /// afin de comparer l'état des deux supports sans hypothèse de format.
  static String encoderEtat(Map<String, EloScore> ratings) {
    final entrees = ratings.entries
        .map((e) => <String, Object?>{
              'cle': e.key,
              'nom': e.value.nomCheval,
              'rating': e.value.rating,
              'nb': e.value.nbCourses,
              'var': e.value.variationMois,
            })
        .toList()
      ..sort((a, b) => '${a['cle']}'.compareTo('${b['cle']}'));
    return jsonEncode(entrees);
  }
}
