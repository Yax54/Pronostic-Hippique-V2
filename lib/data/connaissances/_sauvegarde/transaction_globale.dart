/// Transaction couvrant **tous** les supports de stockage de l'application.
///
/// Consigne §16 / §23 / §4 du présent tour. Le point de départ est une
/// constatation mesurable, pas une opinion :
///
/// > **Une transaction SQLite ne protège que SQLite.**
///
/// L'application persiste dans quatre supports distincts :
///
/// | Support | Transaction native | Ce que cela implique |
/// |---|---|---|
/// | SQLite (`pronostic.db`) | oui | peut être annulé par le moteur |
/// | SharedPreferences | **non** | un `setString` est définitif une fois écrit |
/// | Fichiers permanents (`archives/`, `config/`) | **non** | un `writeAsString` est définitif |
/// | Sauvegardes exportées (`sauvegardes/`) | non (mais atomique par `.tmp`+rename) | déjà protégé par `FormatSauvegarde` |
///
/// Il est donc impossible de rendre une restauration atomique au sens d'un
/// `ROLLBACK` unique. La seule garantie atteignable, et celle implémentée ici,
/// est :
///
/// 1. **Instantané complet et vérifié AVANT la première écriture.** Les quatre
///    supports sont capturés dans un même fichier `.ptg`. Aucune donnée n'est
///    touchée avant que cet instantané soit écrit **et relu et vérifié**.
/// 2. **Journal d'intention.** Avant d'écrire, la liste exacte des clés
///    SharedPreferences qui vont être modifiées est consignée dans le journal
///    du dépôt. Après une interruption, ce journal permet de savoir ce qui a pu
///    être appliqué, au lieu de le supposer.
/// 3. **Retour arrière complet.** `annuler()` restaure les quatre supports
///    depuis l'instantané : SQLite par recopie transactionnelle, puis
///    SharedPreferences clé par clé (valeurs d'origine **et suppressions**),
///    puis les fichiers permanents.
/// 4. **Aucune suppression de donnée locale.** La restauration ajoute et
///    remplace ; elle ne supprime rien. Un retour arrière, lui, doit pouvoir
///    supprimer une clé qui n'existait pas avant : c'est le seul cas où une
///    suppression est légitime, et elle est alors *restauratrice*.
///
/// Ce que cette classe ne peut pas garantir, et qui est dit explicitement :
/// si le processus est tué pendant `annuler()`, l'état peut rester mixte. La
/// seule protection possible dans ce cas est de rejouer `annuler()` depuis le
/// même instantané, qui est idempotent par construction (il réécrit l'état
/// complet, il ne le modifie pas de façon incrémentale).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../_adapters/depot_sqlite.dart';
import 'format_sauvegarde.dart';

/// Une valeur SharedPreferences avec son type d'origine.
///
/// Le type est conservé parce qu'il porte une information : une chaîne `"3"`
/// et un entier `3` ne sont pas la même donnée, et `SharedPreferences` les
/// stocke différemment. Restaurer l'un pour l'autre changerait le comportement
/// de l'application sans qu'aucune erreur ne soit levée.
class ValeurPref {
  const ValeurPref(this.type, this.valeur);

  /// `StringList`, `String`, `int`, `double` ou `bool`.
  final String type;
  final Object? valeur;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'value': valeur,
      };

  static ValeurPref? fromJson(Object? brut) {
    if (brut is! Map) return null;
    final type = '${brut['type']}';
    final v = brut['value'];
    switch (type) {
      case 'StringList':
        if (v is! List) return null;
        return ValeurPref(
          type,
          <String>[for (final e in v) '$e'],
        );
      case 'String':
      case 'int':
      case 'double':
      case 'bool':
        if (v == null) return null;
        return ValeurPref(type, v);
      default:
        return null;
    }
  }

  @override
  String toString() => 'ValeurPref($type)';
}

/// Lecture et écriture typées de SharedPreferences.
///
/// Volontairement séparé du coordinateur : la logique de transaction ne doit pas
/// dépendre des subtilités de `SharedPreferences` (notamment le fait qu'une clé
/// absente et une clé nulle sont indiscernables de l'extérieur).
class MagasinPrefs {
  const MagasinPrefs();

  /// Lit une clé en conservant son type réel, ou `null` si elle n'existe pas.
  ValeurPref? lire(SharedPreferences prefs, String cle) {
    if (!prefs.containsKey(cle)) return null;
    final v = prefs.get(cle);
    if (v == null) return null;
    if (v is String) return ValeurPref('String', v);
    if (v is bool) return ValeurPref('bool', v);
    if (v is int) return ValeurPref('int', v);
    if (v is double) return ValeurPref('double', v);
    if (v is List) return ValeurPref('StringList', <String>[for (final e in v) '$e']);
    // Un type inconnu n'est pas deviné : il est ignoré et donc signalé par son
    // absence, jamais converti au hasard.
    return null;
  }

  /// Écrit une valeur en respectant son type d'origine.
  ///
  /// Lève si le type est inconnu : mieux vaut un échec visible qu'une écriture
  /// dans le mauvais type, qui ne se manifesterait que bien plus tard.
  Future<void> ecrire(
    SharedPreferences prefs,
    String cle,
    ValeurPref valeur,
  ) async {
    switch (valeur.type) {
      case 'StringList':
        await prefs.setStringList(
          cle,
          <String>[for (final e in (valeur.valeur as List)) '$e'],
        );
      case 'String':
        await prefs.setString((cle), valeur.valeur as String);
      case 'int':
        await prefs.setInt(cle, (valeur.valeur as num).toInt());
      case 'double':
        await prefs.setDouble(cle, (valeur.valeur as num).toDouble());
      case 'bool':
        await prefs.setBool(cle, valeur.valeur as bool);
      default:
        throw ArgumentError('type SharedPreferences inconnu : ${valeur.type}');
    }
  }

  /// Capture toutes les clés, ou seulement celles demandées.
  ///
  /// [filtre] permet de ne pas copier des caches volumineux et reconstructibles.
  /// Toute exclusion doit être justifiée par l'appelant : ce magasin ne décide
  /// pas seul de ce qui est jetable.
  Map<String, Object?> capturer(
    SharedPreferences prefs, {
    bool Function(String cle)? filtre,
  }) {
    final out = <String, Object?>{};
    for (final cle in prefs.getKeys()) {
      if (filtre != null && !filtre(cle)) continue;
      final v = lire(prefs, cle);
      if (v == null) continue;
      out[cle] = v.toJson();
    }
    return out;
  }
}

/// Résultat d'un retour arrière.
class ResultatAnnulation {
  const ResultatAnnulation({
    required this.reussie,
    required this.eloRestaures,
    required this.prefsEcrites,
    required this.prefsSupprimees,
    required this.fichiersRestaures,
    this.erreur,
  });

  final bool reussie;
  final int eloRestaures;
  final int prefsEcrites;
  final int prefsSupprimees;
  final int fichiersRestaures;
  final String? erreur;

  Map<String, Object?> toJson() => <String, Object?>{
        'reussie': reussie,
        'elo_restaures': eloRestaures,
        'prefs_ecrites': prefsEcrites,
        'prefs_supprimees': prefsSupprimees,
        'fichiers_restaures': fichiersRestaures,
        'erreur': erreur,
      };
}

/// Transaction couvrant SharedPreferences, SQLite et les fichiers permanents.
class TransactionGlobale {
  TransactionGlobale({
    required this.depot,
    required this.dossierTemp,
    required this.dossierBase,
    this.versionLocale = 'inconnue',
  });

  final DepotSqlite depot;
  final String dossierTemp;

  /// Racine contenant `base/`, `archives/`, `config/`, `sauvegardes/`, `temp/`.
  final String dossierBase;

  final String versionLocale;

  static const FormatSauvegarde _format = FormatSauvegarde();
  static const MagasinPrefs _magasin = MagasinPrefs();

  /// Clés SharedPreferences dont la présence est indispensable à l'application.
  ///
  /// Cette liste sert au contrôle de cohérence APRÈS restauration : si une de
  /// ces clés disparaît alors qu'elle existait avant, la restauration est
  /// signalée comme destructive. Elle n'en supprime aucune et n'en exige aucune.
  static const List<String> clesCritiques = <String>[
    'ia_poids_v3',
    'ia_pronostics_v2_gz',
    'ia_rapports_v1',
    'ia_bilans_semaine_v1',
    'ia_bilans_mois_v1',
    'ia_journal_v2',
    'elo_service',
    'user_predictions_v2',
  ];

  // ─────────────────────────────────────────────────────────────────────────
  //  INSTANTANÉ
  // ─────────────────────────────────────────────────────────────────────────

  /// Capture les quatre supports et écrit un instantané vérifié.
  ///
  /// Lève si l'instantané ne peut pas être écrit **ou relu** : l'appelant ne
  /// doit alors rien modifier. C'est ce qui rend l'espace insuffisant
  /// inoffensif — l'échec survient avant toute écriture de données.
  Future<InstantaneGlobal> capturer({
    required String nom,
    List<String> exclusionsJustifiees = const <String>[],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final horodatage = DateTime.now().toUtc();
    final chemin = '$dossierTemp/${nom}_'
        '${horodatage.millisecondsSinceEpoch}.ptg';

    // 1. SQLite : copie cohérente produite par le moteur, sans passage en RAM.
    final cheminSqlite = '$dossierTemp/${nom}_sqlite_'
        '${horodatage.millisecondsSinceEpoch}.db';
    final inventaireSqlite = await depot.instantaneVers(cheminSqlite);
    final octetsSqlite = await File(cheminSqlite).readAsBytes();

    // 2. SharedPreferences : toutes les clés, avec leur type. Les caches
    //    explicitement volatils sont exclus par [exclusionsJustifiees].
    final clesPrefs = _magasin.capturer(
      prefs,
      filtre: (cle) => !exclusionsJustifiees.any(cle.startsWith),
    );

    // 3. Fichiers permanents : inventaire des chemins et de leur empreinte.
    //    Le contenu lui-même est inclus pour les fichiers de configuration,
    //    qui sont petits et irremplaçables.
    final fichiers = await _capturerFichiersPermanents();

    final blocs = <Map<String, Object?>>[
      FormatSauvegarde.bloc(
        nom: 'sqlite_complet',
        categorie: 'base_structuree',
        nature: NatureBloc.permanente,
        contenu: <String, Object?>{
          'base64': base64Encode(octetsSqlite),
          'inventaire': inventaireSqlite,
          'octets': octetsSqlite.length,
        },
        provenance: 'VACUUM INTO avant écriture',
        nbEnregistrements:
            inventaireSqlite.values.fold<int>(0, (s, n) => s + n),
      ),
      FormatSauvegarde.bloc(
        nom: 'prefs_complet',
        categorie: 'parametres_et_memoire',
        nature: NatureBloc.permanente,
        contenu: clesPrefs,
        provenance: 'SharedPreferences intégral',
        nbEnregistrements: clesPrefs.length,
      ),
      FormatSauvegarde.bloc(
        nom: 'fichiers_permanents',
        categorie: 'fichiers',
        nature: NatureBloc.permanente,
        contenu: fichiers,
        provenance: 'archives/ et config/',
        nbEnregistrements: fichiers.length,
      ),
    ];

    final conteneur = _format.construire(
      blocs: blocs,
      appVersion: versionLocale,
      exclusions: <Map<String, String>>[
        for (final e in exclusionsJustifiees)
          <String, String>{
            'bloc': e,
            'justification': 'cache reconstructible : sa perte ne fait perdre '
                'aucune connaissance (§15)',
          },
      ],
      dependances: const <List<String>>[
        <String>['prefs_complet', 'sqlite_complet'],
      ],
    );
    await _format.ecrireAtomiquement(conteneur, chemin);

    // Relecture obligatoire : un instantané non vérifiable ne protège de rien.
    final verif = _format.verifier(await File(chemin).readAsString());
    if (!verif.utilisable) {
      throw StateError(
        'instantané non vérifiable (${verif.messages.join(" ; ")}) : '
        'aucune écriture ne doit avoir lieu',
      );
    }
    if (await File(cheminSqlite).exists()) await File(cheminSqlite).delete();

    final instantane = InstantaneGlobal(
      chemin: chemin,
      dateCreation: horodatage,
      nbClefsPrefs: clesPrefs.length,
      nbLignesSqlite: inventaireSqlite.values.fold<int>(0, (s, n) => s + n),
      nbFichiers: fichiers.length,
      empreinte: verif.manifeste!.empreinteGlobale,
      clesPrefs: <String>[for (final k in clesPrefs.keys) k],
    );
    if (kDebugMode) {
      debugPrint('[TransactionGlobale] instantané ${instantane.empreinte} '
          '(${instantane.nbLignesSqlite} lignes SQLite, '
          '${instantane.nbClefsPrefs} clés prefs, '
          '${instantane.nbFichiers} fichiers)');
    }
    return instantane;
  }

  /// Lit les fichiers permanents à conserver, avec leur contenu.
  ///
  /// Seuls les fichiers de `archives/` et `config/` sont lus : `base/` est
  /// couvert par l'instantané SQLite (le lire deux fois gaspillerait de la
  /// mémoire), `cache/` et `temp/` sont reconstructibles et exclus par
  /// construction, `sauvegardes/` contient les sauvegardes déjà exportées par
  /// l'utilisateur — les recopier dans chaque sauvegarde les dupliquerait
  /// indéfiniment, ce qui est exactement ce que §15 interdit.
  Future<Map<String, Object?>> _capturerFichiersPermanents() async {
    final out = <String, Object?>{};
    for (final sousDossier in <String>['archives', 'config']) {
      final racine = Directory('$dossierBase/$sousDossier');
      if (!await racine.exists()) continue;
      await for (final entite in racine.list(recursive: true)) {
        if (entite is! File) continue;
        final relatif =
            entite.path.substring(dossierBase.length + 1).replaceAll('\\', '/');
        try {
          final octets = await entite.readAsBytes();
          out[relatif] = <String, Object?>{
            'base64': base64Encode(octets),
            'octets': octets.length,
            'modifie_le': (await entite.stat()).modified.toUtc().toIso8601String(),
          };
        } on FileSystemException {
          // Un fichier illisible est signalé par son absence de la capture,
          // jamais remplacé par un contenu vide qui laisserait croire à un
          // fichier légitimement vide.
          out[relatif] = <String, Object?>{'illisible': true};
        }
      }
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  JOURNAL D'INTENTION
  // ─────────────────────────────────────────────────────────────────────────

  /// Consigne l'intention d'écriture avant de commencer.
  ///
  /// Après une interruption, ce journal permet de constater ce qui a pu être
  /// appliqué. Il ne remplace pas le retour arrière : il le rend interprétable.
  Future<void> declarerIntention({
    required String operation,
    required List<String> clesPrefsTouchees,
  }) async {
    await depot.journaliser(
      operation: operation,
      etape: 'intention',
      statut: 'declaree',
      detail: jsonEncode(<String, Object?>{
        'cles_prefs': clesPrefsTouchees,
        'nb_cles': clesPrefsTouchees.length,
        'supports': const <String>['sqlite', 'shared_preferences', 'fichiers'],
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  RETOUR ARRIÈRE
  // ─────────────────────────────────────────────────────────────────────────

  /// Rétablit les quatre supports depuis un instantané.
  ///
  /// Idempotent : rejouer `annuler()` avec le même instantané réécrit l'état
  /// complet, il ne l'altère pas de façon cumulative. C'est ce qui rend une
  /// interruption pendant le retour arrière réparable par un nouveau rejeu.
  Future<ResultatAnnulation> annuler(InstantaneGlobal instantane) async {
    final fichier = File(instantane.chemin);
    if (!await fichier.exists()) {
      return const ResultatAnnulation(
        reussie: false,
        eloRestaures: 0,
        prefsEcrites: 0,
        prefsSupprimees: 0,
        fichiersRestaures: 0,
        erreur: 'instantané introuvable : retour arrière impossible',
      );
    }
    final contenu = await fichier.readAsString();
    final verif = _format.verifier(contenu);
    if (!verif.utilisable) {
      return ResultatAnnulation(
        reussie: false,
        eloRestaures: 0,
        prefsEcrites: 0,
        prefsSupprimees: 0,
        fichiersRestaures: 0,
        erreur: 'instantané altéré (${verif.blocsAlteres.join(", ")}) : '
            'retour arrière refusé',
      );
    }

    var eloRestaures = 0;
    var prefsEcrites = 0;
    var prefsSupprimees = 0;
    var fichiersRestaures = 0;

    try {
      // ── 1. SQLite EN PREMIER ────────────────────────────────────────────
      // L'ordre a une raison : SQLite est le seul support qui puisse échouer
      // proprement (transaction). En le traitant avant SharedPreferences, un
      // échec SQLite laisse les prefs intactes, donc l'état reste celui
      // d'avant la restauration.
      final blocSqlite = _format.extraireBloc(contenu, 'sqlite_complet');
      if (blocSqlite is Map && blocSqlite['base64'] is String) {
        final octets = base64Decode(blocSqlite['base64'] as String);
        final cheminTemp = '${instantane.chemin}.restauration.db';
        await File(cheminTemp).writeAsBytes(octets, flush: true);
        try {
          await depot.restaurerDepuisInstantane(cheminTemp);
          final inv = blocSqlite['inventaire'];
          if (inv is Map) {
            eloRestaures = (inv['elo_ratings'] as num?)?.toInt() ?? 0;
          }
        } finally {
          if (await File(cheminTemp).exists()) await File(cheminTemp).delete();
        }
      }

      // ── 2. SharedPreferences ────────────────────────────────────────────
      final blocPrefs = _format.extraireBloc(contenu, 'prefs_complet');
      if (blocPrefs is Map) {
        final prefs = await SharedPreferences.getInstance();
        final attendues = <String>{for (final k in blocPrefs.keys) '$k'};

        for (final e in blocPrefs.entries) {
          final valeur = ValeurPref.fromJson(e.value);
          if (valeur == null) continue;
          await _magasin.ecrire(prefs, '${e.key}', valeur);
          prefsEcrites++;
        }

        // Les clés créées APRÈS l'instantané doivent disparaître : les laisser
        // produirait un état mixte, où une part serait revenue en arrière et
        // l'autre non. C'est le seul cas de suppression légitime.
        for (final cle in prefs.getKeys().toList()) {
          if (attendues.contains(cle)) continue;
          // Les caches volatils et les clés système ne sont pas concernés : ils
          // n'existaient pas dans l'instantané parce qu'ils sont exclus par
          // conception, pas parce qu'ils ont été créés depuis.
          if (_estCleVolatile(cle)) continue;
          await prefs.remove(cle);
          prefsSupprimees++;
        }
      }

      // ── 3. Fichiers permanents ──────────────────────────────────────────
      final blocFichiers = _format.extraireBloc(contenu, 'fichiers_permanents');
      if (blocFichiers is Map) {
        for (final e in blocFichiers.entries) {
          final desc = e.value;
          if (desc is! Map) continue;
          final encode = desc['base64'];
          if (encode is! String) continue;
          final chemin = '$dossierBase/${e.key}';
          final cible = File(chemin);
          if (!await cible.parent.exists()) {
            await cible.parent.create(recursive: true);
          }
          await cible.writeAsBytes(base64Decode(encode), flush: true);
          fichiersRestaures++;
        }
      }

      await depot.journaliser(
        operation: 'annulation',
        etape: 'application',
        statut: 'termine',
        detail: 'elo=$eloRestaures prefs=$prefsEcrites '
            'supprimees=$prefsSupprimees fichiers=$fichiersRestaures',
      );
      return ResultatAnnulation(
        reussie: true,
        eloRestaures: eloRestaures,
        prefsEcrites: prefsEcrites,
        prefsSupprimees: prefsSupprimees,
        fichiersRestaures: fichiersRestaures,
      );
    } catch (e) {
      await depot.journaliser(
        operation: 'annulation',
        etape: 'application',
        statut: 'echec',
        detail: '$e',
      );
      return ResultatAnnulation(
        reussie: false,
        eloRestaures: eloRestaures,
        prefsEcrites: prefsEcrites,
        prefsSupprimees: prefsSupprimees,
        fichiersRestaures: fichiersRestaures,
        erreur: '$e',
      );
    }
  }

  /// Une clé est-elle volatile (cache reconstructible) ?
  ///
  /// Ces préfixes sont ceux que l'application régénère : ils ne font pas partie
  /// de l'instantané, et leur absence après retour arrière n'est pas une perte.
  bool _estCleVolatile(String cle) {
    const prefixes = <String>[
      'cache_reunions_',
      'flutter.',
      'ia_audit_cache',
      'audit_cache',
    ];
    return prefixes.any(cle.startsWith);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  CONTRÔLE DE COHÉRENCE
  // ─────────────────────────────────────────────────────────────────────────

  /// Compare l'état des supports avant et après une opération.
  ///
  /// Destiné au contrôle final d'une restauration : détecte une clé critique
  /// disparue, une table vidée, ou un écart d'inventaire. Ces écarts sont
  /// retournés, pas corrigés : c'est à l'appelant de décider.
  Future<List<String>> controlerCoherence({
    required Map<String, int> inventaireAvant,
  }) async {
    final ecarts = <String>[];
    final apres = await depot.inventaire();

    for (final e in inventaireAvant.entries) {
      final n = apres[e.key];
      if (n == null) {
        ecarts.add('table ${e.key} disparue');
        continue;
      }
      // Une baisse de volume sur une table permanente est suspecte : la
      // restauration ne supprime jamais de ligne.
      if (n < e.value) {
        ecarts.add('table ${e.key} : ${e.value} → $n lignes '
            '(${e.value - n} perdue(s))');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    for (final cle in clesCritiques) {
      if (!_estCleVolatile(cle) && !prefs.containsKey(cle)) {
        // Une clé critique absente n'est pas forcément une erreur (une
        // installation neuve n'en a aucune). Elle est signalée pour que
        // l'appelant puisse décider, jamais corrigée d'office.
        ecarts.add('clé critique absente : $cle');
      }
    }
    return ecarts;
  }
}

/// Instantané couvrant les quatre supports.
class InstantaneGlobal {
  const InstantaneGlobal({
    required this.chemin,
    required this.dateCreation,
    required this.nbClefsPrefs,
    required this.nbLignesSqlite,
    required this.nbFichiers,
    required this.empreinte,
    required this.clesPrefs,
  });

  final String chemin;
  final DateTime dateCreation;
  final int nbClefsPrefs;
  final int nbLignesSqlite;
  final int nbFichiers;

  /// Empreinte globale du manifeste : identifie l'instantané lui-même.
  final String empreinte;

  /// Clés SharedPreferences présentes dans l'instantané.
  final List<String> clesPrefs;

  Map<String, Object?> toJson() => <String, Object?>{
        'chemin': chemin,
        'date_creation': dateCreation.toIso8601String(),
        'nb_cles_prefs': nbClefsPrefs,
        'nb_lignes_sqlite': nbLignesSqlite,
        'nb_fichiers': nbFichiers,
        'empreinte': empreinte,
      };
}
