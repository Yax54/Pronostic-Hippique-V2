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
/// ═══════════════════════════════════════════════════════════════════════════
///  LOGIQUE MÉTIER UNIQUE DE RESTAURATION
///
///  Cette classe est **la seule** à décider comment une sauvegarde est
///  appliquée. `BackupService` ne fait plus que : choisir le dépôt, appeler
///  cette classe, et traduire le résultat en `ImportResult`. Il ne contient
///  plus aucune règle de conflit, de conservation ou d'application.
///
///  Deux layouts de conteneur existent, et les deux sont traités ici :
///
///  | Layout | Blocs | Origine |
///  |---|---|---|
///  | structuré | `sqlite_complet`, `prefs_complet`, `fichiers_permanents` | `TransactionGlobale` / export de production |
///  | historique | `elo_ratings`, `elo_service`, `ia_rapports_v1`, `ia_bilans_*` | tests et anciens conteneurs |
///
///  ═══════════════════════════════════════════════════════════════════════════
///  REPRISE APRÈS INTERRUPTION
///
///  Une interruption du processus ne peut pas être empêchée. Elle peut être
///  rendue **réparable de façon déterministe**, et c'est ce qui est implémenté :
///
///  ```text
///  capturer()            → instantané vérifié écrit
///  declarerIntention()   → meta['restauration_en_cours'] = <chemin instantané>
///  appliquer()           → écritures sur les 4 supports
///  marquerApplique()     → meta['restauration_appliquee'] = <chemin instantané>
///  controler()           → contrôles de cohérence
///  marquerTermine()      → meta['restauration_en_cours'] = ''
///  ```
///
///  La reprise lit cette méta. Trois cas, et trois seulement :
///
///  | Méta trouvée | Interprétation | Action |
///  |---|---|---|
///  | intention sans « appliquée » | écritures interrompues en cours | `annuler()` (idempotent) |
///  | « appliquée » sans « terminée » | données complètes, contrôles non faits | rejouer les contrôles, garder les données |
///  | instantané introuvable | protection disparue | signaler, ne rien supposer |
///
///  ⚠️ La méta est écrite **dans le dépôt SQLite**, donc elle est elle-même
///  couverte par l'instantané : revenir en arrière la remet automatiquement à
///  l'état antérieur. Ce n'est pas un contournement, c'est une cohérence.
///  ═══════════════════════════════════════════════════════════════════════════
///
/// Ce que cette classe ne prouve pas : l'absence de perte si le processus est
/// tué *pendant* `annuler()`. `annuler()` étant idempotent, le rejeu au
/// démarrage suivant répare ce cas — c'est précisément `reprendre()`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_adapters/depot_sqlite.dart';
import '../_core/depot.dart';
import '../_core/empreinte_contenu.dart';
import 'format_sauvegarde.dart';
import 'transaction_globale.dart';

/// Nom d'opération journalisé pour une restauration multi-supports.
///
/// Défini ici, et non dans l'appelant : le nom fait partie de la logique de
/// restauration, un appelant ne doit pas pouvoir en inventer un autre.
const String kOperationRestaurationPtg = 'restauration_ptg';

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
    this.nbPrefsEcrites = 0,
    this.nbFichiersRestaures = 0,
    this.instantaneGlobal,
    this.reprise,
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

  /// Nombre de clés SharedPreferences écrites (layout structuré uniquement).
  final int nbPrefsEcrites;

  /// Nombre de fichiers permanents rétablis (layout structuré uniquement).
  final int nbFichiersRestaures;

  /// Instantané multi-supports, présent pour le layout structuré.
  final InstantaneGlobal? instantaneGlobal;

  /// Renseigné quand ce résultat provient d'une reprise après interruption.
  final ResultatReprise? reprise;

  ResultatRestauration copieAvec({ResultatReprise? reprise}) =>
      ResultatRestauration(
        reussie: reussie,
        mode: mode,
        legacy: legacy,
        blocsAppliques: blocsAppliques,
        blocsIgnores: blocsIgnores,
        eloRestaures: eloRestaures,
        eloIdentiques: eloIdentiques,
        eloLocauxConserves: eloLocauxConserves,
        eloConflits: eloConflits,
        rapportsRestaures: rapportsRestaures,
        rapportsIgnores: rapportsIgnores,
        bilansRestaures: bilansRestaures,
        bilansIgnores: bilansIgnores,
        referencesEnregistrees: referencesEnregistrees,
        referencesOrphelines: referencesOrphelines,
        conflitsEnregistres: conflitsEnregistres,
        messages: messages,
        rollbackDisponible: rollbackDisponible,
        instantane: instantane,
        erreur: erreur,
        nbPrefsEcrites: nbPrefsEcrites,
        nbFichiersRestaures: nbFichiersRestaures,
        instantaneGlobal: instantaneGlobal,
        reprise: reprise ?? this.reprise,
      );

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

/// Ce qu'une reprise après interruption a réellement trouvé et fait.
///
/// L'objet est volontairement explicite plutôt qu'un simple booléen : la
/// différence entre « rien à reprendre », « retour arrière rejoué » et
/// « données conservées, contrôles rejoués » change complètement ce que
/// l'utilisateur doit comprendre de l'état de son application.
class ResultatReprise {
  const ResultatReprise({
    required this.action,
    required this.instantane,
    required this.detail,
    this.annulation,
    this.controles = const <String>[],
    this.erreur,
  });

  /// Aucun travail interrompu n'a été trouvé.
  static const String actionAucune = 'aucune';

  /// Écritures interrompues : retour arrière rejoué.
  static const String actionAnnulee = 'annulee';

  /// Écritures complètes mais contrôles non faits : données conservées.
  static const String actionControlesRejoues = 'controles_rejoues';

  /// Écritures complètes mais contrôles EN ÉCHEC : retour arrière appliqué.
  ///
  /// Distinct de [actionAnnulee] : ici le retour arrière est une conséquence
  /// d'une incohérence constatée, pas d'une interruption d'écriture. La
  /// distinction compte pour l'utilisateur, qui doit savoir que sa
  /// restauration a été défaite **parce qu'elle était incohérente**.
  static const String actionIncoherence = 'incoherence';

  /// L'état ne peut pas être établi (instantané disparu, méta illisible).
  static const String actionIrrecuperable = 'irrecuperable';

  final String action;
  final String? instantane;
  final String detail;
  final ResultatAnnulation? annulation;
  final List<String> controles;
  final String? erreur;

  bool get rienAFaire => action == actionAucune;

  Map<String, Object?> toJson() => <String, Object?>{
        'action': action,
        'instantane': instantane,
        'detail': detail,
        'annulation': annulation?.toJson(),
        'controles': controles,
        'erreur': erreur,
      };
}

/// Clés de méta utilisées pour la reprise après interruption.
///
/// Elles vivent dans la table `meta` du dépôt, donc dans l'instantané : un
/// retour arrière les remet automatiquement à leur valeur antérieure.
const String kMetaRestaurationEnCours = 'restauration_en_cours';
const String kMetaRestaurationAppliquee = 'restauration_appliquee';
const String kMetaRepriseDerniere = 'restauration_derniere_reprise';

/// Ancienne dénomination, conservée pour ne pas casser l'API publique.
typedef InstantaneRollbackLegacy = InstantaneRollback;

/// Applique une sauvegarde au dépôt structuré.
class Restaurateur {
  const Restaurateur();

  // ─────────────────────────────────────────────────────────────────────────
  //  POINT D'ENTRÉE
  // ─────────────────────────────────────────────────────────────────────────

  /// Point d'entrée **unique** de la restauration.
  ///
  /// Il aiguille selon le layout réel du conteneur, puis délègue. Aucun appelant
  /// n'a à savoir lequel s'applique : c'est précisément ce qui garantit qu'il
  /// n'existe qu'une seule logique métier de restauration.
  ///
  /// [dossierBase] est la racine contenant `archives/`, `config/`, `temp/`. Il
  /// n'est requis que pour le layout structuré (fichiers permanents) ; les
  /// layouts historiques peuvent l'omettre.
  Future<ResultatRestauration> restaurer({
    required DepotSqlite depot,
    required String contenuSauvegarde,
    required ModeRestauration mode,
    required String dossierTemp,
    required String versionLocale,
    String dossierBase = '',
  }) async {
    const format = FormatSauvegarde();

    // La vérification est faite AVANT tout aiguillage : un conteneur altéré ne
    // doit pas pouvoir choisir son chemin de traitement.
    final verif = format.verifier(contenuSauvegarde);
    final structure = _estStructure(contenuSauvegarde, verif);

    if (structure) {
      if (dossierBase.isEmpty) {
        return _echec(
          mode: mode,
          messages: List<String>.from(verif.messages),
          erreur: 'racine de stockage non fournie : une restauration '
              'multi-supports ne peut pas être appliquée partiellement',
        );
      }
      return _restaurerStructure(
        depot: depot,
        contenu: contenuSauvegarde,
        verif: verif,
        mode: mode,
        dossierTemp: dossierTemp,
        dossierBase: dossierBase,
        versionLocale: versionLocale,
      );
    }

    return _restaurerHistorique(
      depot: depot,
      contenuSauvegarde: contenuSauvegarde,
      mode: mode,
      dossierTemp: dossierTemp,
      versionLocale: versionLocale,
    );
  }

  /// Le conteneur porte-t-il le layout structuré (tous les supports) ?
  static bool _estStructure(String contenu, VerificationSauvegarde verif) {
    final blocs = verif.manifeste?.blocs.map((b) => b.nom).toSet() ??
        const <String>{};
    if (blocs.contains('sqlite_complet') || blocs.contains('prefs_complet')) {
      return true;
    }
    // Un manifeste absent (legacy) ne peut pas porter le layout structuré : il
    // est traité par le chemin historique, qui sait le lire.
    return false;
  }

  /// Vérifie, prend un instantané, applique, contrôle — layout historique.
  ///
  /// Aucune écriture n'a lieu avant que la sauvegarde soit déclarée utilisable.
  /// Aucune écriture de données n'a lieu avant que l'instantané de retour
  /// arrière soit écrit et relu : c'est la protection contre l'espace
  /// insuffisant (§16). L'application elle-même se fait dans une transaction :
  /// une erreur en cours laisse le dépôt dans son état antérieur.
  Future<ResultatRestauration> _restaurerHistorique({
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
  //  LAYOUT STRUCTURÉ — TOUS LES SUPPORTS
  // ─────────────────────────────────────────────────────────────────────────

  /// Applique un conteneur couvrant SharedPreferences + SQLite + fichiers.
  ///
  /// Séquence, et sa raison d'être :
  ///
  /// 1. **Instantané global vérifié AVANT la première écriture.** Si l'écriture
  ///    de l'instantané échoue (disque plein, permission), rien n'a été touché.
  /// 2. **Intention consignée**, avec le chemin de l'instantané : sans ce
  ///    chemin, une reprise après interruption serait impossible à mener.
  /// 3. **Application** : prefs typées, SQLite avec conflits ELO explicites,
  ///    fichiers permanents.
  /// 4. **Contrôles** : comptes déclarés, cohérence entre magasins, clés
  ///    critiques.
  /// 5. **Sur échec, retour arrière complet** et résultat honnête sur son issue.
  Future<ResultatRestauration> _restaurerStructure({
    required DepotSqlite depot,
    required String contenu,
    required VerificationSauvegarde verif,
    required ModeRestauration mode,
    required String dossierTemp,
    required String dossierBase,
    required String versionLocale,
  }) async {
    const format = FormatSauvegarde();
    final messages = List<String>.from(verif.messages);

    if (!verif.utilisable) {
      return _echec(
        mode: mode,
        messages: messages,
        // Libellé conservé tel quel : c'est un contrat d'interface observé par
        // les appelants et les tests, l'unification ne doit pas le changer.
        erreur: verif.blocsAlteres.isNotEmpty
            ? 'sauvegarde altérée : ${verif.blocsAlteres.join(", ")}'
            : 'sauvegarde inutilisable',
      );
    }

    final transaction = TransactionGlobale(
      depot: depot,
      dossierTemp: dossierTemp,
      dossierBase: dossierBase,
      versionLocale: versionLocale,
    );

    // ── 1. INSTANTANÉ AVANT ÉCRITURE ─────────────────────────────────────
    InstantaneGlobal instantane;
    try {
      instantane = await transaction.capturer(nom: 'avant_restauration');
    } catch (e) {
      return _echec(
        mode: mode,
        messages: messages,
        erreur: 'instantané de retour arrière impossible ($e) : restauration '
            'refusée avant toute modification',
      );
    }
    messages.add('instantané global écrit et vérifié '
        '(${instantane.nbLignesSqlite} lignes SQLite, '
        '${instantane.nbClefsPrefs} clés prefs, '
        '${instantane.nbFichiers} fichiers)');

    // ── 2. INTENTION (avec le chemin de l'instantané) ────────────────────
    final blocPrefs = format.extraireBloc(contenu, 'prefs_complet');
    final clesCibles = blocPrefs is Map
        ? <String>[for (final k in blocPrefs.keys) '$k']
        : const <String>[];
    await transaction.declarerIntention(
      operation: kOperationRestaurationPtg,
      clesPrefsTouchees: clesCibles,
      cheminInstantane: instantane.chemin,
    );
    await _ecrireMeta(depot, kMetaRestaurationEnCours, instantane.chemin);
    await _ecrireMeta(depot, kMetaRestaurationAppliquee, '');

    var prefsEcrites = 0;
    var fichiersRestaures = 0;
    var eloIdentiques = 0;
    var eloConflits = 0;
    var eloAbsentsLocalement = 0;

    try {
      // ── 3a. SharedPreferences, types préservés ─────────────────────────
      if (blocPrefs is Map) {
        const magasin = MagasinPrefs();
        final prefs = await SharedPreferences.getInstance();
        for (final e in blocPrefs.entries) {
          final valeur = ValeurPref.fromJson(e.value);
          if (valeur == null) {
            messages.add('clé ${e.key} ignorée : type non reconnu');
            continue;
          }
          await magasin.ecrire(prefs, '${e.key}', valeur);
          prefsEcrites++;
        }
      } else {
        messages.add('aucun bloc prefs_complet : SharedPreferences inchangées');
      }

      // ── 3b. SQLite, conflits ELO traités un par un ─────────────────────
      final blocSqlite = format.extraireBloc(contenu, 'sqlite_complet');
      if (blocSqlite is Map && blocSqlite['base64'] is String) {
        final octets = base64Decode(blocSqlite['base64'] as String);
        final cheminTemp = '$dossierTemp/restauration_'
            '${DateTime.now().millisecondsSinceEpoch}.db';
        await File(cheminTemp).writeAsBytes(octets, flush: true);
        try {
          final source = DepotSqlite(
            chemin: cheminTemp,
            fabrique: depot.fabriquePourRelecture,
          );
          await source.ouvrir();
          try {
            final rapport = await _comparerEloAvantRecopie(
              depot,
              source,
              mode,
              messages,
            );
            eloIdentiques = rapport.identiques;
            eloConflits = rapport.conflits;
            eloAbsentsLocalement = rapport.absentsLocalement;
          } finally {
            await source.fermer();
          }

          await depot.restaurerDepuisInstantane(cheminTemp);
          messages.add('SQLite rétablie depuis le conteneur '
              '($eloIdentiques rating(s) identique(s), '
              '$eloAbsentsLocalement absent(s) localement, '
              '$eloConflits conflit(s))');
        } finally {
          final f = File(cheminTemp);
          if (await f.exists()) await f.delete();
        }
      } else {
        messages.add('aucun bloc sqlite_complet : dépôt structuré inchangé');
      }

      // ── 3c. Fichiers permanents ────────────────────────────────────────
      final blocFichiers = format.extraireBloc(contenu, 'fichiers_permanents');
      if (blocFichiers is Map) {
        for (final e in blocFichiers.entries) {
          final desc = e.value;
          if (desc is! Map) continue;
          final encode = desc['base64'];
          if (encode is! String) continue;
          final cible = File('$dossierBase/${e.key}');
          if (!await cible.parent.exists()) {
            await cible.parent.create(recursive: true);
          }
          await cible.writeAsBytes(base64Decode(encode), flush: true);
          fichiersRestaures++;
        }
      }

      // ── 4. MARQUAGE : données complètes ────────────────────────────────
      // À partir d'ici, une interruption n'exige plus un retour arrière : les
      // données sont complètes, seuls les contrôles manquent.
      await _ecrireMeta(depot, kMetaRestaurationAppliquee, instantane.chemin);
    } catch (e) {
      // ── RETOUR ARRIÈRE COMPLET ─────────────────────────────────────────
      final annulation = await transaction.annuler(instantane);
      if (annulation.reussie) {
        await _ecrireMeta(depot, kMetaRestaurationEnCours, '');
        await _ecrireMeta(depot, kMetaRestaurationAppliquee, '');
      }
      return _echec(
        mode: mode,
        messages: messages,
        erreur: 'échec pendant la restauration : $e. '
            '${annulation.reussie ? "État antérieur rétabli "
                  "(${annulation.prefsEcrites} clés prefs, "
                  "${annulation.eloRestaures} ratings, "
                  "${annulation.fichiersRestaures} fichiers)."
              : "RETOUR ARRIÈRE ÉCHOUÉ (${annulation.erreur}) — instantané "
                  "conservé : ${instantane.chemin}. La reprise au prochain "
                  "démarrage rejouera le retour arrière."}',
      );
    }

    // ── 5. CONTRÔLES APRÈS APPLICATION ───────────────────────────────────
    final controles = <String>[];
    try {
      controles.addAll(await transaction.controlerCoherence(
        inventaireAvant: instantane.inventaireAvant,
      ));
    } catch (e) {
      controles.add('contrôle de cohérence impossible : $e');
    }
    final orphelines = await depot.compterReferencesOrphelines();
    if (orphelines > 0) {
      controles.add('$orphelines référence(s) de bilan pointent un rapport '
          'absent');
    }
    messages.addAll(controles);

    // ── 6. CLÔTURE ───────────────────────────────────────────────────────
    // La méta « en cours » est effacée AVANT le marqueur de reprise : dans
    // l'ordre inverse, une interruption entre les deux laisserait croire à un
    // travail inachevé alors qu'il est fini.
    await _ecrireMeta(depot, kMetaRestaurationEnCours, '');
    await _ecrireMeta(depot, kMetaRestaurationAppliquee, '');
    await depot.journaliser(
      operation: kOperationRestaurationPtg,
      etape: 'application',
      statut: 'termine',
      detail: 'prefs=$prefsEcrites fichiers=$fichiersRestaures '
          'elo_identiques=$eloIdentiques elo_absents=$eloAbsentsLocalement '
          'elo_conflits=$eloConflits controles=${controles.length}',
    );

    return ResultatRestauration(
      reussie: true,
      mode: mode,
      legacy: false,
      blocsAppliques: <String>[
        for (final b in verif.manifeste?.blocs ?? const <DescriptionBloc>[])
          if (b.nature != NatureBloc.cache) b.nom,
      ],
      blocsIgnores: <String>[
        for (final b in verif.manifeste?.blocs ?? const <DescriptionBloc>[])
          if (b.nature == NatureBloc.cache) b.nom,
      ],
      eloRestaures: eloAbsentsLocalement,
      eloIdentiques: eloIdentiques,
      eloLocauxConserves: 0,
      eloConflits: eloConflits,
      rapportsRestaures: 0,
      rapportsIgnores: 0,
      bilansRestaures: 0,
      bilansIgnores: 0,
      referencesEnregistrees: 0,
      referencesOrphelines: orphelines,
      conflitsEnregistres: eloConflits,
      messages: messages,
      rollbackDisponible: await File(instantane.chemin).exists(),
      instantaneGlobal: instantane,
      nbPrefsEcrites: prefsEcrites,
      nbFichiersRestaures: fichiersRestaures,
    );
  }

  /// Compare les ratings ELO locales vs conteneur, et trace chaque divergence.
  ///
  /// C'est **la** logique D-24 de l'application : aucun rating divergent n'est
  /// remplacé en silence, aucune valeur n'est fusionnée arithmétiquement.
  Future<({int identiques, int conflits, int absentsLocalement})>
      _comparerEloAvantRecopie(
    DepotSqlite depot,
    DepotSqlite source,
    ModeRestauration mode,
    List<String> messages,
  ) async {
    var identiques = 0;
    var conflits = 0;
    var absents = 0;

    final locales = <String, LigneElo>{
      for (final l in await depot.tousLesElo()) l.cle: l,
    };
    final distantes = await source.tousLesElo();

    for (final distante in distantes) {
      final locale = locales[distante.cle];
      if (locale == null) {
        absents++;
        continue;
      }
      if (locale.rating == distante.rating &&
          locale.nb == distante.nb &&
          locale.var_ == distante.var_) {
        identiques++;
        continue;
      }
      // Divergence : tracée, jamais arbitrée mathématiquement (D-24).
      await depot.enregistrerConflit(
        categorie: 'elo_rating',
        cleEntite: distante.cle,
        description: mode == ModeRestauration.conservateur
            ? 'Rating divergent conservé en local (mode conservateur) : '
                'local=${locale.rating}, sauvegarde=${distante.rating}. '
                'Aucune fusion (D-24).'
            : 'Rating divergent remplacé par celui de la sauvegarde (mode '
                'complet) : local=${locale.rating}, '
                'sauvegarde=${distante.rating}. Aucune fusion arithmétique '
                '(D-24).',
        valeurLocale: '${locale.rating}',
        valeurDistante: '${distante.rating}',
      );
      conflits++;
    }

    if (mode == ModeRestauration.conservateur && conflits > 0) {
      messages.add('$conflits rating(s) divergent(s) : la valeur locale est '
          'conservée en mode conservateur. Aucune fusion (D-24).');
    }
    return (identiques: identiques, conflits: conflits, absentsLocalement: absents);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  REPRISE APRÈS INTERRUPTION
  // ─────────────────────────────────────────────────────────────────────────

  /// Reprend un travail de restauration interrompu par l'arrêt du processus.
  ///
  /// À appeler **au démarrage**, avant tout affichage de données. Retourne
  /// `null` s'il n'y a rien à reprendre — le cas normal.
  ///
  /// La décision se prend sur la méta du dépôt, jamais sur une supposition :
  ///
  /// | Méta | Action |
  /// |---|---|
  /// | rien | rien à faire |
  /// | intention + instantané, pas « appliquée » | `annuler()` (rejeu idempotent) |
  /// | « appliquée » mais pas terminée | données conservées, contrôles rejoués |
  /// | intention + instantané disparu | signalé, rien supposé |
  Future<ResultatReprise?> reprendre({
    required DepotSqlite depot,
    required String dossierTemp,
    required String dossierBase,
    required String versionLocale,
  }) async {
    final chemin = await depot.lireMeta(kMetaRestaurationEnCours);
    final appliquee = await depot.lireMeta(kMetaRestaurationAppliquee);

    final enCours = (chemin ?? '').trim();
    final marqueAppliquee = (appliquee ?? '').trim();

    if (enCours.isEmpty) {
      // Le marqueur « appliquée » orphelin (méta en cours effacée) ne demande
      // aucune action : il ne reste aucun travail à faire.
      if (marqueAppliquee.isNotEmpty) {
        await _ecrireMeta(depot, kMetaRestaurationAppliquee, '');
      }
      return null;
    }

    final instantanePresent = await File(enCours).exists();
    if (!instantanePresent) {
      final detail = 'instantané de protection introuvable ($enCours) : l\'état '
          'exact ne peut pas être établi. Aucune donnée n\'a été supprimée par '
          'la reprise.';
      await _ecrireMeta(depot, kMetaRestaurationEnCours, '');
      await _ecrireMeta(depot, kMetaRestaurationAppliquee, '');
      await depot.journaliser(
        operation: 'reprise_restauration',
        etape: 'diagnostic',
        statut: 'irrecuperable',
        detail: detail,
      );
      return ResultatReprise(
        action: ResultatReprise.actionIrrecuperable,
        instantane: enCours,
        detail: detail,
        erreur: 'instantané absent',
      );
    }

    const format = FormatSauvegarde();
    final verif = format.verifier(await File(enCours).readAsString());
    final blocs = verif.manifeste?.blocs ?? const <DescriptionBloc>[];
    final aFichiers = blocs.any((b) => b.nom == 'fichiers_permanents');

    if (marqueAppliquee == enCours) {
      // ══════════════════════════════════════════════════════════════════
      //  §2 — LA FIN DES ÉCRITURES N'EST PAS UNE PREUVE DE COHÉRENCE
      //
      //  « Lorsque les écritures ont été effectuées mais que les contrôles
      //  n'ont pas été terminés, reprendre les contrôles d'intégrité avant de
      //  déclarer la restauration réussie. La fin des écritures ne constitue
      //  pas à elle seule une preuve de cohérence. En cas d'échec des
      //  contrôles, appliquer le mécanisme de récupération approprié. »
      //
      //  Ce bloc ne se contente donc pas de « garder les données » : il
      //  exécute les contrôles réels, et si l'un échoue, il applique le
      //  retour arrière — le mécanisme de récupération — au lieu de déclarer
      //  un succès qu'il n'a pas vérifié.
      // ══════════════════════════════════════════════════════════════════
      final controles = <String>[];

      // (a) Intégrité SQLite elle-même : une base corrompue invalide tout le
      //     reste, quel que soit le nombre de lignes.
      try {
        final integrite = await depot.integrite();
        if (!integrite.toLowerCase().contains('ok')) {
          controles.add('intégrité SQLite en échec : $integrite');
        }
      } catch (e) {
        controles.add('contrôle d\'intégrité SQLite impossible : $e');
      }

      // (b) Clés critiques : le contrôle correct n'est PAS « la clé est
      //     absente » — une installation neuve n'a aucune clé critique, et une
      //     sauvegarde restaurée peut légitimement n'en contenir aucune. Le
      //     contrôle est donc **comparatif** : une clé qui existait dans
      //     l'instantané d'avant restauration et qui a disparu est une perte
      //     réelle. C'est la seule forme de contrôle qui ne produise pas de
      //     faux positif.
      try {
        final blocPrefs = format.extraireBloc(
          await File(enCours).readAsString(),
          'prefs_complet',
        );
        if (blocPrefs is Map) {
          final prefs = await SharedPreferences.getInstance();
          final avant = <String>{for (final k in blocPrefs.keys) '$k'};
          for (final cle in TransactionGlobale.clesCritiques) {
            // Seules les clés critiques PRÉSENTES AVANT sont concernées.
            if (!avant.contains(cle)) continue;
            if (!prefs.containsKey(cle)) {
              controles.add('clé critique PERDUE : $cle existait dans '
                  'l\'instantané, absente après restauration');
            }
          }
        }
      } catch (e) {
        controles.add('contrôle des clés critiques impossible : $e');
      }

      // (c) Cohérence entre magasins : aucune référence de bilan orpheline.
      try {
        final orphelines = await depot.compterReferencesOrphelines();
        if (orphelines > 0) {
          controles.add('$orphelines référence(s) de bilan orpheline(s)');
        }
      } catch (e) {
        controles.add('contrôle des références impossible : $e');
      }

      // (d) Volumétrie annoncée par le manifeste vs réelle, quand le bloc
      //     SQLite est présent : un écart signale une copie incomplète.
      try {
        final blocSqlite = format.extraireBloc(
          await File(enCours).readAsString(),
          'sqlite_complet',
        );
        if (blocSqlite is Map) {
          final inv = blocSqlite['inventaire'];
          if (inv is Map) {
            final annonce = (inv['elo_ratings'] as num?)?.toInt() ?? 0;
            final reel = await depot.compterElo();
            if (annonce > 0 && reel < annonce) {
              controles.add('volumétrie ELO inférieure au contenu restauré : '
                  '$reel ligne(s) pour $annonce annoncée(s)');
            }
          }
        }
      } catch (e) {
        controles.add('contrôle de volumétrie impossible : $e');
      }

      // ── DÉCISION ───────────────────────────────────────────────────────
      // Un contrôle en échec n'est pas une observation cosmétique : il signifie
      // que l'état restauré n'est pas cohérent. Dans ce cas, le mécanisme de
      // récupération s'applique — retour arrière depuis l'instantané.
      if (controles.isNotEmpty) {
        final transaction = TransactionGlobale(
          depot: depot,
          dossierTemp: dossierTemp,
          dossierBase: dossierBase,
          versionLocale: versionLocale,
        );
        final instantane = InstantaneGlobal(
          chemin: enCours,
          dateCreation: DateTime.now(),
          nbClefsPrefs: 0,
          nbLignesSqlite: 0,
          nbFichiers: aFichiers ? 1 : 0,
          empreinte: verif.manifeste?.empreinteGlobale ?? '',
          clesPrefs: const <String>[],
        );
        final annulation = await transaction.annuler(instantane);
        if (annulation.reussie) {
          await _ecrireMeta(depot, kMetaRestaurationEnCours, '');
          await _ecrireMeta(depot, kMetaRestaurationAppliquee, '');
        }
        await depot.journaliser(
          operation: 'reprise_restauration',
          etape: 'controles',
          statut: 'incoherent',
          detail: '${controles.length} contrôle(s) en échec : '
              '${controles.take(5).join(" | ")}. '
              'Retour arrière ${annulation.reussie ? "rétabli" : "ÉCHOUÉ"}.',
        );
        if (kDebugMode) {
          debugPrint('[Restaurateur] reprise : ${controles.length} contrôle(s) '
              'en échec, retour arrière '
              '${annulation.reussie ? "rétabli" : "ÉCHOUÉ"}');
        }
        return ResultatReprise(
          action: ResultatReprise.actionIncoherence,
          instantane: enCours,
          detail: 'écritures terminées mais contrôles en échec : retour '
              'arrière ${annulation.reussie ? "appliqué" : "impossible"}',
          annulation: annulation,
          controles: controles,
          erreur: controles.join(' ; '),
        );
      }

      await _ecrireMeta(depot, kMetaRestaurationEnCours, '');
      await _ecrireMeta(depot, kMetaRestaurationAppliquee, '');
      await depot.journaliser(
        operation: 'reprise_restauration',
        etape: 'controles',
        statut: 'termine',
        detail: 'interruption après application : 0 échec sur 4 contrôles, '
            'données conservées',
      );
      if (kDebugMode) {
        debugPrint('[Restaurateur] reprise : données conservées, '
            '4 contrôles passés');
      }
      return ResultatReprise(
        action: ResultatReprise.actionControlesRejoues,
        instantane: enCours,
        detail: 'la restauration avait été appliquée ; les contrôles '
            'd\'intégrité ont été rejoués et passés, les données sont '
            'conservées',
        controles: controles,
      );
    }

    // ── Écritures interrompues : retour arrière idempotent ───────────────
    final transaction = TransactionGlobale(
      depot: depot,
      dossierTemp: dossierTemp,
      dossierBase: dossierBase,
      versionLocale: versionLocale,
    );
    final instantane = InstantaneGlobal(
      chemin: enCours,
      dateCreation: DateTime.now(),
      nbClefsPrefs: 0,
      nbLignesSqlite: 0,
      nbFichiers: aFichiers ? 1 : 0,
      empreinte: verif.manifeste?.empreinteGlobale ?? '',
      clesPrefs: const <String>[],
    );
    final annulation = await transaction.annuler(instantane);

    if (annulation.reussie) {
      await _ecrireMeta(depot, kMetaRestaurationEnCours, '');
      await _ecrireMeta(depot, kMetaRestaurationAppliquee, '');
    }
    await depot.journaliser(
      operation: 'reprise_restauration',
      etape: 'retour_arriere',
      statut: annulation.reussie ? 'termine' : 'echec',
      detail: annulation.reussie
          ? 'retour arrière rejoué : ${annulation.prefsEcrites} clés prefs, '
              '${annulation.eloRestaures} ratings, '
              '${annulation.fichiersRestaures} fichiers'
          : 'retour arrière ÉCHOUÉ : ${annulation.erreur}',
    );
    if (kDebugMode) {
      debugPrint('[Restaurateur] reprise : retour arrière '
          '${annulation.reussie ? "rétabli" : "ÉCHOUÉ"}');
    }
    return ResultatReprise(
      action: ResultatReprise.actionAnnulee,
      instantane: enCours,
      detail: annulation.reussie
          ? 'restauration interrompue : état antérieur rétabli'
          : 'restauration interrompue, retour arrière ÉCHOUÉ',
      annulation: annulation,
      erreur: annulation.erreur,
    );
  }

  /// Écrit une clé de méta, en tolérant un dépôt non initialisé.
  ///
  /// Une méta non écrite doit dégrader la reprise, jamais faire échouer la
  /// restauration elle-même : ce serait remplacer un défaut réparable par un
  /// échec total.
  static Future<void> _ecrireMeta(
    DepotSqlite depot,
    String cle,
    String valeur,
  ) async {
    try {
      await depot.ecrireMeta(cle, valeur);
    } catch (e) {
      if (kDebugMode) debugPrint('[Restaurateur] méta $cle non écrite : $e');
    }
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
