/// Restauration d'une sauvegarde, avec protections et retour arrière.
///
/// Consigne §16. Les exigences, et la manière dont chacune est tenue :
///
/// | Exigence §16                                            | Mise en œuvre |
/// |---------------------------------------------------------|---------------|
/// | compatibilité avec les anciennes sauvegardes JSON        | détection `legacy` |
/// | vérifier les données AVANT activation                    | `verifier()` puis refus |
/// | ne pas écraser silencieusement du plus récent            | conflits explicites tracés |
/// | ne pas supprimer du local absent de l'ancienne sauvegarde | aucune suppression |
/// | distinguer restauration totale et fusion conservatrice   | `ModeRestauration` |
/// | aucun état partiel en cas d'échec                        | transaction unique |
/// | intégrité des données financières                        | bloc dédié, jamais fusionné |
/// | espace insuffisant                                       | instantané écrit AVANT toute écriture |
/// | retour arrière possible                                  | `Restaurateur.rollback` |
///
/// ⚠️ Trois principes non négociables implémentés ici :
///
/// 1. **Aucune fusion mathématique d'un état d'apprentissage.** D-24 interdit
///    d'additionner ou de moyenner deux ratings divergents. En cas de conflit
///    sur un rating, le conflit est enregistré et la décision reste explicite.
/// 2. **Une donnée absente d'une ancienne sauvegarde n'est jamais une raison de
///    supprimer la donnée locale.** Ce fichier ne contient aucun `DELETE`.
/// 3. **Les bilans référencent la version EXACTE du rapport utilisé** (§13),
///    par empreinte de contenu. Une restauration ne repointe jamais un bilan
///    vers « la dernière version disponible ».
///
/// Ce que cette classe ne prouve pas : elle ne peut pas garantir l'absence de
/// perte si le processus est tué entre le `COMMIT` et le contrôle final. Le
/// journal d'opération (`journal_operations`) permet alors de constater l'état
/// réel, et l'instantané de retour arrière de le corriger.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../_adapters/depot_sqlite.dart';
import '../_core/depot.dart';
import '../_core/empreinte_contenu.dart';
import 'format_sauvegarde.dart';

/// Mode de restauration. La distinction est exigée par §16.
enum ModeRestauration {
  /// Remplace les valeurs locales par celles de la sauvegarde. Les données
  /// locales absentes de la sauvegarde sont signalées, jamais supprimées.
  complet,

  /// Conserve l'état local et n'ajoute que ce qui manque. Aucune valeur
  /// existante n'est remplacée.
  conservateur,
}

/// Décision prise pour un élément en conflit.
enum DecisionConflit {
  /// La sauvegarde est plus récente et remplace la valeur locale.
  sauvegardePlusRecente,

  /// La valeur locale est conservée : plus récente, ou non comparable.
  localConserve,

  /// Valeurs identiques : rien à faire.
  identique,

  /// Conflit non arbitrable automatiquement. Enregistré, jamais tranché seul.
  nonArbitrable,
}

/// Schéma de comparaison de contenu d'un rapport.
///
/// Les mêmes clés que le récupérateur de rapports : l'identité d'un rapport est
/// son contenu, pas sa date. `fnum2` est conservé tel quel (jamais supprimé).
const Set<String> kSchemaRapport = <String>{'date', 'fnum', 'fnum2', 'rj'};

/// Résultat détaillé d'une restauration.
class ResultatRestauration {
  ResultatRestauration({
    required this.reussie,
    required this.mode,
    required this.legacy,
    required this.blocsAppliques,
    required this.blocsIgnores,
    required this.eloRestaures,
    required this.eloIdentiques,
    required this.eloLocauxConserves,
    required this.eloConflits,
    required this.rapportsRestaures,
    required this.rapportsIgnores,
    required this.bilansRestaures,
    required this.bilansIgnores,
    required this.referencesEnregistrees,
    required this.referencesOrphelines,
    required this.conflitsEnregistres,
    required this.messages,
    required this.rollbackDisponible,
    this.instantane,
    this.erreur,
  });

  final bool reussie;
  final ModeRestauration mode;
  final bool legacy;
  final List<String> blocsAppliques;
  final List<String> blocsIgnores;
  final int eloRestaures;
  final int eloIdentiques;
  final int eloLocauxConserves;
  final int eloConflits;
  final int rapportsRestaures;
  final int rapportsIgnores;
  final int bilansRestaures;
  final int bilansIgnores;
  final int referencesEnregistrees;

  /// Références de bilan pointant un rapport absent du dépôt après
  /// restauration. Doit valoir 0 ; toute autre valeur signale une incohérence
  /// entre magasins (§15).
  final int referencesOrphelines;

  final int conflitsEnregistres;
  final List<String> messages;
  final bool rollbackDisponible;
  final InstantaneRollback? instantane;
  final String? erreur;

  Map<String, Object?> toJson() => <String, Object?>{
        'reussie': reussie,
        'mode': mode.name,
        'legacy': legacy,
        'blocs_appliques': blocsAppliques,
        'blocs_ignores': blocsIgnores,
        'elo_restaures': eloRestaures,
        'elo_identiques': eloIdentiques,
        'elo_locaux_conserves': eloLocauxConserves,
        'elo_conflits': eloConflits,
        'rapports_restaures': rapportsRestaures,
        'rapports_ignores': rapportsIgnores,
        'bilans_restaures': bilansRestaures,
        'bilans_ignores': bilansIgnores,
        'references_enregistrees': referencesEnregistrees,
        'references_orphelines': referencesOrphelines,
        'conflits_enregistres': conflitsEnregistres,
        'rollback_disponible': rollbackDisponible,
        'instantane': instantane?.chemin,
        'erreur': erreur,
        'messages': messages,
      };
}

/// Instantané pris avant application, pour permettre le retour arrière.
class InstantaneRollback {
  InstantaneRollback({
    required this.chemin,
    required this.dateCreation,
    required this.nbElo,
    required this.nbRapports,
  });

  final String chemin;
  final DateTime dateCreation;
  final int nbElo;
  final int nbRapports;
}

/// Applique une sauvegarde au dépôt structuré.
class Restaurateur {
  const Restaurateur();

  // ─────────────────────────────────────────────────────────────────────────
  //  POINT D'ENTRÉE
  // ─────────────────────────────────────────────────────────────────────────

  /// Vérifie, prend un instantané, applique, contrôle.
  ///
  /// Aucune écriture n'a lieu avant que la sauvegarde soit déclarée utilisable.
  /// Aucune écriture de données n'a lieu avant que l'instantané de retour
  /// arrière soit écrit et relu : c'est la protection contre l'espace
  /// insuffisant (§16). L'application elle-même se fait dans une transaction :
  /// une erreur en cours laisse le dépôt dans son état antérieur.
  Future<ResultatRestauration> restaurer({
    required DepotSqlite depot,
    required String contenuSauvegarde,
    required ModeRestauration mode,
    required String dossierTemp,
    required String versionLocale,
  }) async {
    final messages = <String>[];
    const format = FormatSauvegarde();

    // ── 1. VÉRIFICATION AVANT TOUTE ÉCRITURE ─────────────────────────────
    final verif = format.verifier(contenuSauvegarde);
    messages.addAll(verif.messages);

    if (!verif.lisible || !verif.formatReconnu) {
      return _echec(
        mode: mode,
        messages: messages,
        erreur: 'sauvegarde illisible ou format non reconnu',
      );
    }
    if (!verif.utilisable) {
      return _echec(
        mode: mode,
        legacy: verif.legacy,
        messages: messages,
        erreur: verif.blocsAlteres.isNotEmpty
            ? 'bloc(s) altéré(s) : ${verif.blocsAlteres.join(", ")}'
            : 'sauvegarde inutilisable',
      );
    }

    // ── 2. INSTANTANÉ AVANT APPLICATION ──────────────────────────────────
    // Sa raison d'être est double :
    //   a) retour arrière en cas de résultat inacceptable ;
    //   b) détection d'un espace insuffisant AVANT la moindre modification de
    //      données : si le disque est plein, c'est ici que l'écriture échoue,
    //      alors que rien n'a encore été touché.
    final cheminInstantane =
        '$dossierTemp/rollback_${DateTime.now().millisecondsSinceEpoch}.ptg';
    final nbEloAvant = await depot.compterElo();
    final nbRapportsAvant = await depot.compterRapports();

    InstantaneRollback instantane;
    try {
      final elo = await depot.tousLesElo();
      final conteneur = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'elo_ratings',
            categorie: 'ratings_elo',
            nature: NatureBloc.permanente,
            contenu: <String, Object?>{
              for (final l in elo) l.cle: l.toJson(),
            },
            provenance: 'instantane_avant_restauration',
          ),
        ],
        appVersion: versionLocale,
        exclusions: const <Map<String, String>>[
          <String, String>{
            'bloc': 'rapports',
            'justification': 'instantané limité à ELO : une restauration '
                'n\'écrase jamais un rapport (identifié par empreinte de '
                'contenu) et n\'en supprime aucun',
          },
        ],
      );
      await format.ecrireAtomiquement(conteneur, cheminInstantane);

      // Relecture de l'instantané : un retour arrière n'est proposé que s'il
      // est lui-même vérifiable.
      final relu = await File(cheminInstantane).readAsString();
      final verifInstantane = format.verifier(relu);
      if (!verifInstantane.utilisable) {
        return _echec(
          mode: mode,
          legacy: verif.legacy,
          messages: messages,
          erreur: 'instantané de retour arrière non vérifiable : restauration '
              'refusée sans avoir touché aux données',
        );
      }
      instantane = InstantaneRollback(
        chemin: cheminInstantane,
        dateCreation: DateTime.now(),
        nbElo: nbEloAvant,
        nbRapports: nbRapportsAvant,
      );
      messages.add('instantané de retour arrière écrit et vérifié '
          '($nbEloAvant rating(s), $nbRapportsAvant rapport(s))');
    } on FileSystemException catch (e) {
      // Espace insuffisant (ENOSPC), permission, chemin invalide : rien n'a été
      // modifié dans les données.
      return _echec(
        mode: mode,
        legacy: verif.legacy,
        messages: messages,
        erreur: 'instantané impossible (${e.message}) : restauration refusée '
            'avant toute modification de données',
      );
    }

    // ── 3. APPLICATION DANS UNE TRANSACTION UNIQUE ───────────────────────
    final compteurs = _Compteurs();
    final blocsAppliques = <String>[];
    final blocsIgnores = <String>[];

    try {
      final racine = jsonDecode(contenuSauvegarde) as Map;
      final iaBrut = <String, Object?>{};

      if (verif.legacy) {
        messages.add('restauration depuis une ancienne sauvegarde : aucun '
            'manifeste, intégrité par bloc NON vérifiable — limite réelle');
        final ia = racine['ia'];
        if (ia is Map) {
          for (final e in ia.entries) {
            final v = e.value;
            // Format d'export SharedPreferences : {type, value}.
            iaBrut['${e.key}'] =
                (v is Map && v.containsKey('value')) ? v['value'] : v;
          }
        }
        final eloLegacy = racine['elo_service'];
        if (eloLegacy is Map) {
          iaBrut['elo_service'] = <String, Object?>{
            for (final e in eloLegacy.entries) '${e.key}': e.value
          };
        }
      } else {
        for (final d in verif.manifeste!.blocs) {
          if (d.nature == NatureBloc.cache) {
            // Un cache n'est pas restauré : il est reconstructible, et le
            // restaurer propagerait un état périmé. Exigence §15.
            messages.add('bloc ${d.nom} ignoré (cache reconstructible)');
            blocsIgnores.add(d.nom);
            continue;
          }
          iaBrut[d.nom] = format.extraireBloc(contenuSauvegarde, d.nom);
          blocsAppliques.add(d.nom);
        }
      }

      await depot.transaction(() async {
        // ── 3a. ELO : conflits traités un par un, jamais fusionnés ────────
        final eloSource = _premierDe(iaBrut, <String>['elo_service', 'elo_ratings']);
        if (eloSource is Map) {
          await _appliquerElo(depot, eloSource, mode, compteurs);
        } else {
          messages.add('aucun bloc ELO dans la sauvegarde');
        }

        // ── 3b. Rapports : identifiés par contenu, jamais écrasés ─────────
        final rapports = iaBrut['ia_rapports_v1'];
        if (rapports is List) {
          await _appliquerRapports(
            depot,
            rapports,
            source: 'restauration',
            compteurs: compteurs,
          );
          if (verif.legacy) blocsAppliques.add('ia_rapports_v1');
        }

        // ── 3c. Bilans : références vers les VERSIONS EXACTES (§13) ────────
        final semaines = iaBrut['ia_bilans_semaine_v1'];
        if (semaines is List) {
          await _appliquerBilans(
            depot,
            semaines,
            type: 'bilan_semaine',
            compteurs: compteurs,
          );
          if (verif.legacy) blocsAppliques.add('ia_bilans_semaine_v1');
        }
        final mois = iaBrut['ia_bilans_mois_v1'];
        if (mois is List) {
          await _appliquerBilans(
            depot,
            mois,
            type: 'bilan_mois',
            compteurs: compteurs,
          );
          if (verif.legacy) blocsAppliques.add('ia_bilans_mois_v1');
        }

        await depot.journaliser(
          operation: 'restauration',
          etape: 'application',
          statut: 'termine',
          detail: 'mode=${mode.name} legacy=${verif.legacy} '
              'elo=${compteurs.eloRestaures} '
              'rapports=${compteurs.rapportsRestaures} '
              'bilans=${compteurs.bilansRestaures} '
              'conflits=${compteurs.conflits}',
        );
      });
    } catch (e) {
      messages.add('échec pendant l\'application, transaction annulée : $e');
      return ResultatRestauration(
        reussie: false,
        mode: mode,
        legacy: verif.legacy,
        blocsAppliques: blocsAppliques,
        blocsIgnores: blocsIgnores,
        eloRestaures: 0,
        eloIdentiques: 0,
        eloLocauxConserves: 0,
        eloConflits: 0,
        rapportsRestaures: 0,
        rapportsIgnores: 0,
        bilansRestaures: 0,
        bilansIgnores: 0,
        referencesEnregistrees: 0,
        referencesOrphelines: -1,
        conflitsEnregistres: 0,
        messages: messages,
        rollbackDisponible: await File(instantane.chemin).exists(),
        instantane: instantane,
        erreur: '$e',
      );
    }

    // ── 4. CONTRÔLE APRÈS APPLICATION ────────────────────────────────────
    // (a) le nombre d'enregistrements annoncé par le manifeste est comparé au
    //     réel ;
    // (b) la cohérence entre magasins est vérifiée : aucune référence de bilan
    //     ne doit pointer un rapport absent.
    if (verif.manifeste != null) {
      for (final d in verif.manifeste!.blocs) {
        if (d.nom != 'elo_ratings' && d.nom != 'elo_service') continue;
        final reel = await depot.compterElo();
        if (reel < d.nbEnregistrements) {
          messages.add('contrôle : $reel rating(s) en base pour '
              '${d.nbEnregistrements} annoncé(s)');
        }
      }
    }
    final orphelines = await depot.compterReferencesOrphelines();
    if (orphelines > 0) {
      messages.add('incohérence entre magasins : $orphelines référence(s) de '
          'bilan pointent un rapport absent');
    }

    return ResultatRestauration(
      reussie: true,
      mode: mode,
      legacy: verif.legacy,
      blocsAppliques: blocsAppliques,
      blocsIgnores: blocsIgnores,
      eloRestaures: compteurs.eloRestaures,
      eloIdentiques: compteurs.eloIdentiques,
      eloLocauxConserves: compteurs.eloLocauxConserves,
      eloConflits: compteurs.eloConflits,
      rapportsRestaures: compteurs.rapportsRestaures,
      rapportsIgnores: compteurs.rapportsIgnores,
      bilansRestaures: compteurs.bilansRestaures,
      bilansIgnores: compteurs.bilansIgnores,
      referencesEnregistrees: compteurs.references,
      referencesOrphelines: orphelines,
      conflitsEnregistres: compteurs.conflits,
      messages: messages,
      rollbackDisponible: await File(instantane.chemin).exists(),
      instantane: instantane,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  ELO
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _appliquerElo(
    DepotSqlite depot,
    Map eloSource,
    ModeRestauration mode,
    _Compteurs c,
  ) async {
    final lignes = decoderEloRestauration(<String, Object?>{
      for (final e in eloSource.entries) '${e.key}': e.value
    });
    if (lignes.isEmpty) return;

    // Une seule lecture pour tout le lot (§19) : pas une requête par rating.
    final locales = await depot.lireEloEnLot(
      <String>[for (final l in lignes) l.cle],
    );

    final aEcrire = <LigneElo>[];
    final conflits = <List<String>>[];
    var nouvelles = 0;

    for (final ligne in lignes) {
      final locale = locales[ligne.cle];
      if (locale == null) {
        aEcrire.add(ligne);
        nouvelles++;
        continue;
      }
      // Comparaison stricte, sans tolérance : une valeur ELO n'est jamais
      // « à peu près » égale (§12).
      if (locale.rating == ligne.rating &&
          locale.nb == ligne.nb &&
          locale.var_ == ligne.var_) {
        c.eloIdentiques++;
        continue;
      }
      // Valeurs divergentes : D-24 interdit toute fusion arithmétique.
      if (mode == ModeRestauration.conservateur) {
        c.eloLocauxConserves++;
        conflits.add(<String>[
          ligne.cle,
          '${locale.rating}',
          '${ligne.rating}',
          'conservateur',
        ]);
        continue;
      }
      conflits.add(<String>[
        ligne.cle,
        '${locale.rating}',
        '${ligne.rating}',
        'complet',
      ]);
      c.eloConflits++;
      aEcrire.add(ligne);
    }

    // Une seule écriture groupée, puis contrôle du compte réel (§19, §12).
    final avant = await depot.compterElo();
    await depot.upsertEloEnLot(aEcrire);
    final apres = await depot.compterElo();
    c.eloRestaures = nouvelles;

    // Contrôle : le nombre de lignes créées doit correspondre exactement au
    // nombre de ratings absents localement. Un écart signalerait une écriture
    // perdue, jamais un succès partiel présenté comme complet.
    if (apres - avant != nouvelles) {
      throw StateError(
        'restauration ELO incohérente : ${apres - avant} ligne(s) créée(s) '
        'pour $nouvelles rating(s) absents localement',
      );
    }

    for (final k in conflits) {
      final conservateur = k[3] == 'conservateur';
      await depot.enregistrerConflit(
        categorie: 'elo_rating',
        cleEntite: k[0],
        description: conservateur
            ? 'Rating divergent conservé en local (mode conservateur) : '
                'local=${k[1]}, sauvegarde=${k[2]}. Aucune fusion (D-24).'
            : 'Rating divergent remplacé (mode complet) : local=${k[1]}, '
                'sauvegarde=${k[2]}. Aucune fusion arithmétique (D-24).',
        valeurLocale: k[1],
        valeurDistante: k[2],
      );
      c.conflits++;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  RAPPORTS
  // ─────────────────────────────────────────────────────────────────────────

  /// Enregistre une liste de rapports (chacun éventuellement encodé en JSON).
  ///
  /// L'identité est l'empreinte du contenu. Deux copies identiques ne créent
  /// qu'une ligne ; deux contenus différents à la même date créent deux lignes
  /// (§13). La provenance est conservée pour chaque copie.
  Future<void> _appliquerRapports(
    DepotSqlite depot,
    List<Object?> rapports, {
    required String source,
    required _Compteurs compteurs,
  }) async {
    for (var i = 0; i < rapports.length; i++) {
      final empreinte = await _enregistrerUnRapport(
        depot,
        rapports[i],
        source: source,
        position: i,
      );
      if (empreinte == null) {
        compteurs.rapportsIgnores++;
      } else {
        compteurs.rapportsRestaures++;
      }
    }
  }

  /// Enregistre un rapport et sa copie. Retourne son empreinte, ou `null` si le
  /// contenu n'est pas exploitable.
  Future<String?> _enregistrerUnRapport(
    DepotSqlite depot,
    Object? brut, {
    required String source,
    required int position,
  }) async {
    if (brut == null) return null;
    final texte = brut is String ? brut : jsonEncode(brut);
    if (texte.trim().isEmpty) return null;
    final decode = decoderJsonTolerant(texte);
    final empreinte = empreinteContenu(decode, schemaAttendu: kSchemaRapport);
    final insere = await depot.insererRapport(RapportStocke(
      empreinte: empreinte,
      dateRapport: _dateDe(decode) ?? '',
      contenu: texte,
      contenuNormalise: serialiserCanonique(
        normaliserContenu(decode, schemaAttendu: kSchemaRapport),
      ),
      tailleOrigine: texte.length,
      schemaVersion: 1,
    ));
    await depot.ajouterCopieRapport(CopieRapport(
      empreinte: empreinte,
      source: source,
      position: position,
    ));
    // La valeur de retour indique si la ligne est nouvelle ; une copie
    // supplémentaire d'un contenu déjà présent n'est pas une erreur.
    return insere || empreinte.isNotEmpty ? empreinte : null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BILANS
  // ─────────────────────────────────────────────────────────────────────────

  /// Restaure les bilans d'un type donné, avec leurs références exactes.
  ///
  /// Chaque rapport cité par un bilan est enregistré comme rapport à part
  /// entière (avec sa provenance `bilan_semaine` / `bilan_mois`), puis
  /// référencé par son empreinte. Une référence ne pointe donc jamais une
  /// « dernière version » mais le contenu exact consommé (§13).
  Future<void> _appliquerBilans(
    DepotSqlite depot,
    List<Object?> bilans, {
    required String type,
    required _Compteurs compteurs,
  }) async {
    for (var i = 0; i < bilans.length; i++) {
      final brut = bilans[i];
      final texte = brut is String ? brut : jsonEncode(brut);
      final decode = decoderJsonTolerant(texte);
      if (decode is! Map) {
        compteurs.bilansIgnores++;
        continue;
      }
      final map = <String, Object?>{for (final e in decode.entries) '${e.key}': e.value};
      final empreinte = empreinteContenu(map, schemaAttendu: kSchemaRapport);
      final id = '$type:$empreinte';

      final insere = await depot.insererBilan(BilanStocke(
        id: id,
        type: type,
        contenu: texte,
        empreinte: empreinte,
        schemaVersion: 1,
        periodeDebut: _texte(map['lundi']) ?? _texte(map['debut']),
        periodeFin: _texte(map['dim']) ?? _texte(map['fin']),
        annee: (map['an'] as num?)?.toInt(),
        mois: (map['mo'] as num?)?.toInt(),
        semaine: (map['semaine'] as num?)?.toInt(),
      ));
      if (insere) {
        compteurs.bilansRestaures++;
      } else {
        compteurs.bilansIgnores++;
      }

      // Références vers les rapports réellement cités.
      final references = <ReferenceRapport>[];
      await _collecterReferences(
        depot,
        map['rj'],
        role: 'rj',
        source: type,
        references: references,
        compteurs: compteurs,
      );
      // Un bilan mensuel agrège des bilans de semaine : leurs rapports sont
      // eux aussi référencés, avec un rôle distinct pour ne rien confondre.
      final semaines = map['sem'];
      if (semaines is List) {
        for (var s = 0; s < semaines.length; s++) {
          final sem = decoderJsonTolerant(
            semaines[s] is String ? '${semaines[s]}' : jsonEncode(semaines[s]),
          );
          if (sem is! Map) continue;
          final semMap = <String, Object?>{for (final e in sem.entries) '${e.key}': e.value};
          await _collecterReferences(
            depot,
            semMap['rj'],
            role: 'sem:$s',
            source: type,
            references: references,
            compteurs: compteurs,
          );
        }
      }

      for (final r in references) {
        await depot.ajouterReferenceBilan(r, id);
        compteurs.references++;
      }
    }
  }

  /// Enregistre les rapports cités par un bilan et construit les références.
  Future<void> _collecterReferences(
    DepotSqlite depot,
    Object? liste, {
    required String role,
    required String source,
    required List<ReferenceRapport> references,
    required _Compteurs compteurs,
  }) async {
    if (liste is! List) return;
    for (var k = 0; k < liste.length; k++) {
      final empreinte = await _enregistrerUnRapport(
        depot,
        liste[k],
        source: source,
        position: k,
      );
      if (empreinte == null) {
        compteurs.rapportsIgnores++;
        continue;
      }
      compteurs.rapportsRestaures++;
      references.add(ReferenceRapport(
        role: role,
        empreinte: empreinte,
        ordre: k,
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  RETOUR ARRIÈRE
  // ─────────────────────────────────────────────────────────────────────────

  /// Applique un instantané pour revenir à l'état antérieur.
  ///
  /// Les valeurs de l'instantané remplacent les lignes de même clé ; aucune
  /// ligne n'est supprimée, donc un retour arrière ne peut pas détruire une
  /// donnée (§16 : « retour arrière possible »).
  Future<int> rollback(
    DepotSqlite depot,
    InstantaneRollback instantane, {
    required String dossierTemp,
  }) async {
    final fichier = File(instantane.chemin);
    if (!await fichier.exists()) return 0;
    const format = FormatSauvegarde();
    final contenu = await fichier.readAsString();
    final verif = format.verifier(contenu);
    if (!verif.utilisable) return 0;

    final elo = format.extraireBloc(contenu, 'elo_ratings');
    if (elo is! Map) return 0;

    final lignes = decoderEloRestauration(<String, Object?>{
      for (final e in elo.entries) '${e.key}': e.value
    });
    var restaures = 0;
    await depot.transaction(() async {
      for (final l in lignes) {
        await depot.upsertElo(l);
        restaures++;
      }
    });
    await depot.journaliser(
      operation: 'rollback',
      etape: 'application',
      statut: 'termine',
      detail: '$restaures rating(s) rétablis',
    );
    if (kDebugMode) {
      debugPrint('[Restaurateur] rollback : $restaures rating(s) rétablis');
    }
    return restaures;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  OUTILS
  // ─────────────────────────────────────────────────────────────────────────

  ResultatRestauration _echec({
    required ModeRestauration mode,
    required List<String> messages,
    required String erreur,
    bool legacy = false,
  }) =>
      ResultatRestauration(
        reussie: false,
        mode: mode,
        legacy: legacy,
        blocsAppliques: const <String>[],
        blocsIgnores: const <String>[],
        eloRestaures: 0,
        eloIdentiques: 0,
        eloLocauxConserves: 0,
        eloConflits: 0,
        rapportsRestaures: 0,
        rapportsIgnores: 0,
        bilansRestaures: 0,
        bilansIgnores: 0,
        referencesEnregistrees: 0,
        referencesOrphelines: -1,
        conflitsEnregistres: 0,
        messages: messages,
        rollbackDisponible: false,
        erreur: erreur,
      );

  static Object? _premierDe(Map<String, Object?> m, List<String> cles) {
    for (final c in cles) {
      final v = m[c];
      if (v != null) return v;
    }
    return null;
  }

  static String? _texte(Object? v) {
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  static String? _dateDe(Object? decode) {
    if (decode is Map) {
      final d = decode['date'];
      if (d is String && d.isNotEmpty) return d;
      if (d != null) return '$d';
    }
    return null;
  }
}

/// Compteurs mutables d'une restauration.
class _Compteurs {
  int eloRestaures = 0;
  int eloIdentiques = 0;
  int eloLocauxConserves = 0;
  int eloConflits = 0;
  int rapportsRestaures = 0;
  int rapportsIgnores = 0;
  int bilansRestaures = 0;
  int bilansIgnores = 0;
  int references = 0;
  int conflits = 0;
}

/// Décode les ratings ELO d'une sauvegarde (format `NOM|DISCIPLINE` →
/// `{nom, rating, nb, var}`). Le découpage se fait sur le **dernier** `|` : un
/// nom contenant un `|` survit. La clé est conservée **verbatim**.
///
/// Cette fonction ne calcule aucun rating : elle recopie la valeur telle
/// qu'elle était stockée, à la précision du `double` (§12).
List<LigneElo> decoderEloRestauration(Map<String, Object?> source) {
  final lignes = <LigneElo>[];
  for (final e in source.entries) {
    final cle = e.key;
    final v = e.value;
    if (v is! Map) continue;
    final nom = '${v['nom'] ?? _nomDeCle(cle)}';
    final rating = (v['rating'] as num?)?.toDouble();
    // Un rating sans valeur numérique n'est pas inventé : il est ignoré et
    // signalé par son absence, jamais remplacé par un défaut (D-24).
    if (rating == null) continue;
    lignes.add(LigneElo(
      cle: cle,
      nomOrigine: nom,
      discipline: _disciplineDeCle(cle),
      rating: rating,
      nb: (v['nb'] as num?)?.toInt() ?? 0,
      var_: (v['var'] as num?)?.toDouble() ?? 0.0,
      idCheval: v['id_cheval'] as String?,
    ));
  }
  return lignes;
}

String _nomDeCle(String cle) {
  final i = cle.lastIndexOf('|');
  return i < 0 ? cle : cle.substring(0, i);
}

String _disciplineDeCle(String cle) {
  final i = cle.lastIndexOf('|');
  // Une discipline absente reste absente : la chaîne vide est conservée telle
  // quelle, elle n'est pas remplacée par `global` (D-09, D-27).
  return i < 0 ? '' : cle.substring(i + 1);
}
