/// Bascule ELO : SharedPreferences → SQLite comme source de référence unique.
///
/// Consigne §1 du présent tour :
/// > « Réalise la bascule effective des lectures et écritures vers SQLite.
/// > **Attention : une base SQLite vide ne doit pas automatiquement provoquer
/// > une réimportation des anciennes données SharedPreferences.** Prévoir un
/// > marqueur durable de migration réussie permettant de distinguer : première
/// > installation, migration nécessaire, migration déjà effectuée, base
/// > légitimement vide, restauration, anomalie de stockage. »
///
/// ═══════════════════════════════════════════════════════════════════════════
///  LE PROBLÈME QUE CE FICHIER RÉSOUT
///
///  « La base est vide » a **six** causes possibles, et cinq d'entre elles ne
///  sont pas « il faut réimporter ». Les confondre produit soit une perte, soit
///  une résurrection de données périmées :
///
///  | État | Lecture de la base vide | Action correcte |
///  |---|---|---|
///  | première installation | rien à importer | initialiser, marquer |
///  | migration nécessaire | les données sont dans prefs | importer, vérifier, marquer |
///  | migration déjà faite | base vidée depuis | **ne rien importer** |
///  | base légitimement vide | l'utilisateur n'a aucun rating | **ne rien importer** |
///  | restauration | une sauvegarde a remplacé l'état | suivre la sauvegarde |
///  | anomalie de stockage | on ne sait pas | **ne rien écrire**, signaler |
///
///  Le discriminant n'est donc **pas** le contenu de la base, c'est un
///  **marqueur durable** : sans lui, une base vide est indistinguable d'une
///  base jamais alimentée. C'est exactement l'erreur que la consigne interdit.
///
///  ═══════════════════════════════════════════════════════════════════════════
///  POURQUOI LE MARQUEUR VIT DANS SQLITE (table `meta`) ET NON DANS PREFS
///
///  Le marqueur doit survivre à ce qu'il décrit. Dans `meta`, il est :
///  * **atomique** avec les données qu'il qualifie : la migration écrit les
///    ratings puis le marqueur dans la même base ;
///  * **couvert par l'instantané** : un retour arrière restaure les ratings
///    ET le marqueur ensemble, donc l'état reste cohérent ;
///  * **impossible à ressusciter par une vieille sauvegarde prefs** : restaurer
///    une sauvegarde JSON ancienne dans prefs ne peut pas inventer un marqueur
///    de migration dans SQLite.
///
///  Un marqueur dans prefs serait, lui, exactement le vecteur de réintroduction
///  involontaire que la consigne demande d'empêcher.
///  ═══════════════════════════════════════════════════════════════════════════
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_adapters/depot_sqlite.dart';
import '../_core/depot.dart';
import '../_migration/migrateur_elo.dart';

/// Clé de méta portant le marqueur de migration réussie.
const String kMetaBasculeElo = 'elo_bascule_v1';

/// État du stockage ELO, tel qu'il doit être décidé **avant** toute lecture.
///
/// Chaque valeur est exclusive : la logique de bascule en produit exactement
/// une, et chacune commande une action différente.
enum EtatBasculeElo {
  /// Aucun rating nulle part et aucun marqueur : installation neuve.
  premiereInstallation,

  /// Des ratings existent dans prefs, aucun marqueur : il faut migrer.
  migrationNecessaire,

  /// Marqueur présent : la migration a eu lieu, SQLite fait référence.
  migrationDejaFaite,

  /// Marqueur présent et base vide : l'utilisateur n'a réellement rien.
  baseLegitimementVide,

  /// Une restauration a eu lieu : l'état vient de la sauvegarde.
  restauration,

  /// On ne peut pas décider (dépôt fermé, lecture en échec).
  anomalieStockage,
}

/// Ce que la bascule a réellement constaté et fait.
class BilanBasculeElo {
  const BilanBasculeElo({
    required this.etat,
    required this.nbLignesSqlite,
    required this.nbLignesPrefs,
    this.migrationExecutee = false,
    this.identiques = false,
    this.ecarts = 0,
    this.messages = const <String>[],
    this.erreur,
    this.empreinte = '',
  });

  final EtatBasculeElo etat;
  final int nbLignesSqlite;
  final int nbLignesPrefs;

  /// `true` si des données ont réellement été écrites lors de cet appel.
  final bool migrationExecutee;

  /// `true` si l'état SQLite reproduit exactement la source après migration.
  final bool identiques;

  /// Nombre d'écarts constatés par le contrôle d'identité.
  final int ecarts;

  final List<String> messages;
  final String? erreur;

  /// Empreinte du marqueur posé, vide si aucun marqueur n'a été posé.
  final String empreinte;

  /// SQLite est-il la source de référence à l'issue de cet appel ?
  bool get sqliteEstReference =>
      etat == EtatBasculeElo.migrationDejaFaite ||
      etat == EtatBasculeElo.baseLegitimementVide ||
      etat == EtatBasculeElo.restauration ||
      (etat == EtatBasculeElo.premiereInstallation && !migrationExecutee) ||
      (migrationExecutee && identiques);

  Map<String, Object?> toJson() => <String, Object?>{
        'etat': etat.name,
        'nb_lignes_sqlite': nbLignesSqlite,
        'nb_lignes_prefs': nbLignesPrefs,
        'migration_executee': migrationExecutee,
        'identiques': identiques,
        'ecarts': ecarts,
        'empreinte': empreinte,
        'erreur': erreur,
        'messages': messages,
      };
}

/// Décide et exécute la bascule.
///
/// La classe ne contient **aucune formule** : elle déplace des valeurs telles
/// quelles et les vérifie. Aucun rating n'est recalculé, aucune discipline
/// n'est déduite autrement que par le découpage déjà validé, aucune fusion.
class BasculeElo {
  const BasculeElo();

  /// Clé SharedPreferences portant les ratings (format v2 : `NOM|DISCIPLINE`).
  static const String clePrefsElo = 'elo_service';

  /// Ancienne clé v1, sans discipline.
  static const String clePrefsEloV1 = 'elo_service_v1';

  // ─────────────────────────────────────────────────────────────────────────
  //  DÉCISION
  // ─────────────────────────────────────────────────────────────────────────

  /// Lit le marqueur durable, ou `null` s'il n'existe pas.
  ///
  /// Un marqueur illisible est traité comme **absent** : c'est le choix
  /// prudent, parce qu'un marqueur corrompu ne prouve rien. Le risque de
  /// re-migration est neutralisé par l'idempotence du migrateur, qui
  /// n'écrase aucune valeur divergente sans la tracer.
  Future<Map<String, Object?>?> lireMarqueur(DepotSqlite depot) async {
    try {
      final brut = await depot.lireMeta(kMetaBasculeElo);
      if (brut == null || brut.trim().isEmpty) return null;
      final decode = jsonDecode(brut);
      if (decode is! Map) return null;
      return <String, Object?>{for (final e in decode.entries) '${e.key}': e.value};
    } catch (e) {
      if (kDebugMode) debugPrint('[BasculeElo] marqueur illisible : $e');
      return null;
    }
  }

  /// Compte les ratings présents dans SharedPreferences, sans les interpréter.
  ///
  /// Une entrée non exploitable n'est pas comptée comme présente : mieux vaut
  /// sous-estimer la source que de conclure à une migration inutile.
  int compterDansPrefs(SharedPreferences prefs) {
    final brut = prefs.getString(clePrefsElo);
    if (brut == null || brut.isEmpty) return 0;
    try {
      final decode = jsonDecode(brut);
      if (decode is! Map) return 0;
      var n = 0;
      for (final v in decode.values) {
        if (v is Map && v['rating'] is num) n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  /// Détermine l'état, **sans rien écrire**.
  ///
  /// C'est la fonction qui répond à l'exigence : « une base vide ne doit pas
  /// automatiquement provoquer une réimportation ». La réponse dépend du
  /// marqueur, jamais du seul compte de lignes.
  Future<EtatBasculeElo> determinerEtat({
    required DepotSqlite? depot,
    required SharedPreferences prefs,
  }) async {
    if (depot == null) return EtatBasculeElo.anomalieStockage;

    final int nbPrefs;
    try {
      nbPrefs = compterDansPrefs(prefs);
    } catch (_) {
      return EtatBasculeElo.anomalieStockage;
    }

    final int nbSqlite;
    try {
      nbSqlite = await depot.compterElo();
    } catch (e) {
      if (kDebugMode) debugPrint('[BasculeElo] lecture base impossible : $e');
      return EtatBasculeElo.anomalieStockage;
    }

    final marqueur = await lireMarqueur(depot);

    // Une restauration en cours prime sur tout le reste : si une sauvegarde a
    // été appliquée, l'état vient d'elle et aucune décision antérieure n'est
    // plus valable.
    if (marqueur != null && marqueur['etat'] == 'restauration') {
      return EtatBasculeElo.restauration;
    }

    if (marqueur != null) {
      // La migration a eu lieu. Une base vide est alors LÉGITIME : c'est le
      // cas que la consigne interdit de confondre avec une migration à faire.
      return nbSqlite == 0
          ? EtatBasculeElo.baseLegitimementVide
          : EtatBasculeElo.migrationDejaFaite;
    }

    // Pas de marqueur : deux cas seulement.
    if (nbPrefs == 0) return EtatBasculeElo.premiereInstallation;
    return EtatBasculeElo.migrationNecessaire;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  EXÉCUTION
  // ─────────────────────────────────────────────────────────────────────────

  /// Applique l'action exigée par l'état, et pose le marqueur.
  ///
  /// Ne migre que dans l'état `migrationNecessaire`. Dans tous les autres cas,
  /// elle constate et marque — sans jamais réimporter.
  ///
  /// [motifRestauration] permet à l'appelant qui vient de restaurer de le dire
  /// explicitement, plutôt que de laisser la fonction le deviner.
  Future<BilanBasculeElo> executer({
    required DepotSqlite? depot,
    required SharedPreferences prefs,
    bool motifRestauration = false,
  }) async {
    final messages = <String>[];
    final etat = await determinerEtat(depot: depot, prefs: prefs);

    if (etat == EtatBasculeElo.anomalieStockage) {
      return BilanBasculeElo(
        etat: etat,
        nbLignesSqlite: 0,
        nbLignesPrefs: compterDansPrefs(prefs),
        messages: messages,
        erreur: 'dépôt illisible : aucune écriture effectuée, aucune décision '
            'prise sur l\'état des ratings',
      );
    }

    final d = depot!;
    final nbSqlite = await d.compterElo();
    final nbPrefs = compterDansPrefs(prefs);

    if (motifRestauration) {
      await _poserMarqueur(d, etat: 'restauration', nbLignes: nbSqlite,
          source: 'sauvegarde');
      messages.add('marqueur de restauration posé ($nbSqlite rating(s))');
      return BilanBasculeElo(
        etat: EtatBasculeElo.restauration,
        nbLignesSqlite: nbSqlite,
        nbLignesPrefs: nbPrefs,
        messages: messages,
        empreinte: await _empreinteMarqueur(d),
      );
    }

    switch (etat) {
      case EtatBasculeElo.premiereInstallation:
        await _poserMarqueur(d, etat: 'initiale', nbLignes: 0, source: 'aucune');
        messages.add('installation neuve : aucun rating à migrer, marqueur posé');
        return BilanBasculeElo(
          etat: etat,
          nbLignesSqlite: nbSqlite,
          nbLignesPrefs: nbPrefs,
          messages: messages,
          identiques: true,
          empreinte: await _empreinteMarqueur(d),
        );

      case EtatBasculeElo.baseLegitimementVide:
        messages.add('base vide APRÈS migration : état légitime, aucune '
            'réimportation depuis SharedPreferences ($nbPrefs rating(s) '
            'archivés restent non relus)');
        return BilanBasculeElo(
          etat: etat,
          nbLignesSqlite: 0,
          nbLignesPrefs: nbPrefs,
          messages: messages,
          identiques: true,
          empreinte: await _empreinteMarqueur(d),
        );

      case EtatBasculeElo.migrationDejaFaite:
        messages.add('migration déjà effectuée : SQLite est la référence '
            '($nbSqlite rating(s))');
        return BilanBasculeElo(
          etat: etat,
          nbLignesSqlite: nbSqlite,
          nbLignesPrefs: nbPrefs,
          messages: messages,
          identiques: true,
          empreinte: await _empreinteMarqueur(d),
        );

      case EtatBasculeElo.restauration:
        return BilanBasculeElo(
          etat: etat,
          nbLignesSqlite: nbSqlite,
          nbLignesPrefs: nbPrefs,
          messages: messages,
          identiques: true,
          empreinte: await _empreinteMarqueur(d),
        );

      case EtatBasculeElo.migrationNecessaire:
        return _migrer(d, prefs, nbPrefs: nbPrefs, messages: messages);

      case EtatBasculeElo.anomalieStockage:
        // Traité plus haut : ce cas est inatteignable ici.
        return BilanBasculeElo(
          etat: etat,
          nbLignesSqlite: 0,
          nbLignesPrefs: nbPrefs,
          messages: messages,
          erreur: 'état incohérent',
        );
    }
  }

  /// Migre réellement les ratings de prefs vers SQLite, puis vérifie.
  ///
  /// L'ordre est délibéré : on **écrit**, on **relit**, on **compare**, et on
  /// ne pose le marqueur qu'en cas d'égalité stricte. Poser le marqueur avant
  /// la vérification rendrait une migration incomplète indiscernable d'une
  /// migration réussie — c'est-à-dire exactement le défaut à éviter.
  Future<BilanBasculeElo> _migrer(
    DepotSqlite depot,
    SharedPreferences prefs, {
    required int nbPrefs,
    required List<String> messages,
  }) async {
    final brut = prefs.getString(clePrefsElo);
    final Map<String, dynamic> source;
    try {
      source = jsonDecode(brut!) as Map<String, dynamic>;
    } catch (e) {
      return BilanBasculeElo(
        etat: EtatBasculeElo.migrationNecessaire,
        nbLignesSqlite: await depot.compterElo(),
        nbLignesPrefs: nbPrefs,
        messages: messages,
        erreur: 'SharedPreferences illisible ($e) : migration refusée pour ne '
            'pas poser un marqueur sur un état inconnu',
      );
    }

    // Le migrateur est celui déjà validé sur les deux sauvegardes réelles : il
    // conserve les clés verbatim, ne fusionne rien et vérifie l'identité des
    // valeurs. On ne réimplémente pas sa logique ici.
    final resultat = await const MigrateurElo()
        .migrer(depot, source, operation: 'bascule_elo_v1');
    messages.add('migration exécutée : ${resultat.clesEcrites} clé(s) écrite(s), '
        '${resultat.ecartsValeur.length} écart(s) de valeur, '
        '${resultat.ecartsChamp.length} écart(s) de champ');

    if (!resultat.conforme) {
      // Pas de marqueur : l'état n'est pas prouvé. La bascule ne doit pas
      // déclarer SQLite comme référence sur une migration douteuse.
      await depot.enregistrerConflit(
        categorie: 'bascule_elo',
        description: 'Migration ELO non conforme : '
            '${resultat.ecartsValeur.length} écart(s) de valeur, '
            '${resultat.ecartsChamp.length} écart(s) de champ. Marqueur NON posé.',
        valeurLocale: '${resultat.clesLues}',
        valeurDistante: '${resultat.clesEcrites}',
      );
      return BilanBasculeElo(
        etat: EtatBasculeElo.migrationNecessaire,
        nbLignesSqlite: await depot.compterElo(),
        nbLignesPrefs: nbPrefs,
        migrationExecutee: true,
        identiques: false,
        ecarts: resultat.ecartsValeur.length + resultat.ecartsChamp.length,
        messages: messages,
        erreur: 'migration non conforme : SQLite n\'est PAS déclaré '
            'référence, marqueur non posé',
      );
    }

    // Contrôle indépendant du migrateur : on relit ce qui est réellement en
    // base et on le compare à la source. Un migrateur qui se tromperait sur
    // son propre compte serait ainsi détecté.
    final verif = await _verifierIdentite(depot, source);
    if (verif.$1 != 0) {
      await depot.enregistrerConflit(
        categorie: 'bascule_elo',
        description: 'Contrôle indépendant après migration : ${verif.$1} '
            'écart(s) entre SharedPreferences et SQLite. Marqueur NON posé.',
        valeurLocale: '${source.length}',
        valeurDistante: '${await depot.compterElo()}',
      );
      messages.addAll(verif.$2.take(10));
      return BilanBasculeElo(
        etat: EtatBasculeElo.migrationNecessaire,
        nbLignesSqlite: await depot.compterElo(),
        nbLignesPrefs: nbPrefs,
        migrationExecutee: true,
        identiques: false,
        ecarts: verif.$1,
        messages: messages,
        erreur: 'contrôle indépendant en échec : marqueur non posé',
      );
    }

    final nbFinal = await depot.compterElo();
    await _poserMarqueur(
      depot,
      etat: 'migree',
      nbLignes: nbFinal,
      source: 'shared_preferences',
      nbSource: source.length,
    );
    messages.add('identité vérifiée sur ${verif.$3} rating(s) : marqueur posé, '
        'SQLite devient la source de référence unique');

    if (kDebugMode) {
      debugPrint('[BasculeElo] ✅ migration terminée : $nbFinal rating(s), '
          '0 écart, marqueur posé');
    }

    return BilanBasculeElo(
      etat: EtatBasculeElo.migrationDejaFaite,
      nbLignesSqlite: nbFinal,
      nbLignesPrefs: nbPrefs,
      migrationExecutee: true,
      identiques: true,
      ecarts: 0,
      messages: messages,
      empreinte: await _empreinteMarqueur(depot),
    );
  }

  /// Compare la source prefs et la base, attribut par attribut.
  ///
  /// Retourne `(nbEcarts, messages, nbVérifiés)`. Comparaison **stricte** :
  /// aucune tolérance sur un rating (§12).
  Future<(int, List<String>, int)> _verifierIdentite(
    DepotSqlite depot,
    Map<String, dynamic> source,
  ) async {
    final ecarts = <String>[];
    final lignes = await depot.tousLesElo();
    final parCle = <String, LigneElo>{for (final l in lignes) l.cle: l};

    var verifies = 0;
    for (final e in source.entries) {
      final cle = e.key;
      final v = e.value;
      if (v is! Map) continue;
      final rating = (v['rating'] as num?)?.toDouble();
      if (rating == null) continue;
      final locale = parCle[cle];
      if (locale == null) {
        ecarts.add('$cle : absent de SQLite après migration');
        continue;
      }
      if (locale.rating != rating) {
        ecarts.add('$cle : rating ${locale.rating} != $rating');
      }
      final nb = (v['nb'] as num?)?.toInt() ?? 0;
      if (locale.nb != nb) ecarts.add('$cle : nb ${locale.nb} != $nb');
      final var_ = (v['var'] as num?)?.toDouble() ?? 0.0;
      if (locale.var_ != var_) ecarts.add('$cle : var ${locale.var_} != $var_');
      // Identité : le nom d'origine est conservé, la discipline vient de la clé.
      final i = cle.lastIndexOf('|');
      final nomAttendu = '${v['nom'] ?? (i < 0 ? cle : cle.substring(0, i))}';
      if (locale.nomOrigine != nomAttendu) {
        ecarts.add('$cle : nom "${locale.nomOrigine}" != "$nomAttendu"');
      }
      final disciplineAttendue = i < 0 ? '' : cle.substring(i + 1);
      if (locale.discipline != disciplineAttendue) {
        ecarts.add('$cle : discipline "${locale.discipline}" != '
            '"$disciplineAttendue"');
      }
      verifies++;
    }
    return (ecarts.length, ecarts, verifies);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  MARQUEUR
  // ─────────────────────────────────────────────────────────────────────────

  /// Écrit le marqueur durable.
  ///
  /// `etat` vaut `initiale`, `migree` ou `restauration`. Le nombre de lignes
  /// est consigné pour qu'un écart futur soit décelable sans rejouer la
  /// migration.
  Future<void> _poserMarqueur(
    DepotSqlite depot, {
    required String etat,
    required int nbLignes,
    required String source,
    int? nbSource,
  }) async {
    final contenu = <String, Object?>{
      'etat': etat,
      'date': DateTime.now().toUtc().toIso8601String(),
      'nb_lignes': nbLignes,
      if (nbSource != null) 'nb_source': nbSource,
      'source': source,
      'schema': 1,
    };
    await depot.ecrireMeta(kMetaBasculeElo, jsonEncode(contenu));
  }

  /// Empreinte courte du marqueur, pour l'affichage et le rapport.
  Future<String> _empreinteMarqueur(DepotSqlite depot) async {
    try {
      final brut = await depot.lireMeta(kMetaBasculeElo);
      if (brut == null || brut.isEmpty) return '';
      var h = 0;
      for (final c in brut.codeUnits) {
        h = (h * 31 + c) & 0x7fffffff;
      }
      return h.toRadixString(16).padLeft(8, '0');
    } catch (_) {
      return '';
    }
  }

  /// Marque explicitement qu'une restauration a eu lieu.
  ///
  /// Appelé par le chemin de restauration. Sans cet appel, une restauration
  /// qui ramène 0 rating serait vue comme « base légitimement vide » et le
  /// prochain démarrage pourrait conclure à tort. Le marqueur rend le fait
  /// explicite au lieu de le laisser déductible.
  Future<void> marquerRestauration(
    DepotSqlite depot, {
    required int nbLignes,
    required String versionSauvegarde,
  }) async {
    await _poserMarqueur(
      depot,
      etat: 'restauration',
      nbLignes: nbLignes,
      source: 'sauvegarde:$versionSauvegarde',
    );
  }
}
