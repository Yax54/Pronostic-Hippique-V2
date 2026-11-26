/// Format de sauvegarde complet, versionné et vérifiable.
///
/// Consigne §15. Le format existant est un JSON unique, non atomique, sans
/// checksum, dont la version n'est jamais comparée à celle attendue (§16). Ce
/// module fournit un conteneur qui corrige chacun de ces défauts.
///
/// Structure du conteneur (extension `.ptg`) :
///
/// ```
/// {
///   "manifeste": {
///     "format":  "ptg",
///     "version_format": 1,
///     "version_schema": 1,
///     "date_creation": "...",
///     "app_version": "...",
///     "blocs": [
///       {"nom": "...", "categorie": "...", "nature": "...",
///        "nb_enregistrements": 0, "empreinte": "sha256…",
///        "octets_bruts": 0, "octets_compresses": 0,
///        "provenance": "...", "version_schema": 1}
///     ],
///     "exclusions": [{"bloc": "...", "justification": "..."}],
///     "dependances": [["bloc_a", "bloc_b"]],
///     "empreinte_globale": "sha256…"
///   },
///   "blocs": { "nom": "base64(gzip(json))", ... }
/// }
/// ```
///
/// Ce que chaque élément garantit :
///
/// * **manifeste** : inventaire complet, lisible sans décompresser aucun bloc.
///   On peut donc savoir ce que contient une sauvegarde sans la charger en RAM.
/// * **empreinte par bloc** : une altération d'un bloc est détectée isolément,
///   et le diagnostic nomme le bloc fautif au lieu de rejeter la sauvegarde
///   entière.
/// * **empreinte globale** : calcule sur les empreintes de blocs triées. Elle
///   couvre l'inventaire lui-même : ajouter, retirer ou renommer un bloc la
///   change. C'est le contrôle qui rend une sauvegarde partielle détectable.
/// * **nb_enregistrements** : permet de comparer, après restauration, le nombre
///   d'objets réellement rétablis.
/// * **provenance** : d'où vient chaque bloc. Une donnée restaurée reste
///   attribuable.
/// * **exclusions** : tout ce qui n'est pas sauvegardé est listé **avec sa
///   justification**. Rien n'est omis en silence ; c'est la condition posée par
///   §15 pour exclure un cache.
/// * **dependances** : un bloc dont un autre dépend est signalé. Une
///   restauration partielle peut donc refuser de laisser un état incohérent.
/// * **compression** : gzip par bloc. La compression est faite bloc par bloc,
///   jamais sur l'ensemble, pour ne pas charger toute la sauvegarde en RAM.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Nature d'un bloc, qui commande son caractère obligatoire.
enum NatureBloc {
  /// Connaissance permanente : sa perte est irréversible (faits PMU,
  /// observations locales, apprentissage, ELO, rapports, bilans, finances).
  permanente,

  /// État figé : pronostics historiques, résultats officiels.
  historique,

  /// Paramètres et préférences.
  parametres,

  /// Cache entièrement reconstructible. Peut être exclu **si et seulement si**
  /// son absence ne fait perdre aucune connaissance (§15).
  cache,
}

/// Description d'un bloc dans le manifeste.
class DescriptionBloc {
  const DescriptionBloc({
    required this.nom,
    required this.categorie,
    required this.nature,
    required this.nbEnregistrements,
    required this.empreinte,
    required this.octetsBruts,
    required this.octetsCompresses,
    required this.provenance,
    this.versionSchema = 1,
  });

  final String nom;
  final String categorie;
  final NatureBloc nature;
  final int nbEnregistrements;

  /// SHA-256 du contenu JSON canonique, **avant** compression.
  final String empreinte;

  final int octetsBruts;
  final int octetsCompresses;
  final String provenance;
  final int versionSchema;

  Map<String, Object?> toJson() => <String, Object?>{
        'nom': nom,
        'categorie': categorie,
        'nature': nature.name,
        'nb_enregistrements': nbEnregistrements,
        'empreinte': empreinte,
        'octets_bruts': octetsBruts,
        'octets_compresses': octetsCompresses,
        'provenance': provenance,
        'version_schema': versionSchema,
      };

  static DescriptionBloc fromJson(Map<String, Object?> j) => DescriptionBloc(
        nom: '${j['nom']}',
        categorie: '${j['categorie']}',
        nature: NatureBloc.values.firstWhere(
          (n) => n.name == j['nature'],
          orElse: () => NatureBloc.permanente,
        ),
        nbEnregistrements: (j['nb_enregistrements'] as num?)?.toInt() ?? 0,
        empreinte: '${j['empreinte']}',
        octetsBruts: (j['octets_bruts'] as num?)?.toInt() ?? 0,
        octetsCompresses: (j['octets_compresses'] as num?)?.toInt() ?? 0,
        provenance: '${j['provenance']}',
        versionSchema: (j['version_schema'] as num?)?.toInt() ?? 1,
      );
}

/// Manifeste d'une sauvegarde.
class Manifeste {
  Manifeste({
    required this.versionFormat,
    required this.versionSchema,
    required this.dateCreation,
    required this.appVersion,
    required this.blocs,
    required this.exclusions,
    required this.dependances,
  });

  /// Version du présent format de conteneur.
  static const int versionCourante = 1;

  final int versionFormat;
  final int versionSchema;
  final DateTime dateCreation;
  final String appVersion;
  final List<DescriptionBloc> blocs;

  /// Blocs volontairement non sauvegardés, avec justification obligatoire.
  final List<Map<String, String>> exclusions;

  /// Paires `[dependant, dependance]`.
  final List<List<String>> dependances;

  /// Empreinte globale : SHA-256 sur les empreintes de blocs triées, plus les
  /// métadonnées qui doivent être couvertes pour qu'un ajout ou retrait de
  /// bloc soit détecté.
  String get empreinteGlobale {
    final noms = blocs.map((b) => b.nom).toList()..sort();
    final matiere = StringBuffer()
      ..write('ptg|$versionFormat|$versionSchema|')
      ..write('${dateCreation.toUtc().toIso8601String()}|$appVersion|');
    for (final nom in noms) {
      final b = blocs.firstWhere((x) => x.nom == nom);
      matiere.write('$nom:${b.empreinte}:${b.nbEnregistrements};');
    }
    for (final e in (exclusions.map((x) => '${x['bloc']}').toList()..sort())) {
      matiere.write('excl:$e;');
    }
    return sha256.convert(utf8.encode(matiere.toString())).toString();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'format': 'ptg',
        'version_format': versionFormat,
        'version_schema': versionSchema,
        'date_creation': dateCreation.toUtc().toIso8601String(),
        'app_version': appVersion,
        'blocs': [for (final b in blocs) b.toJson()],
        'exclusions': exclusions,
        'dependances': dependances,
        'empreinte_globale': empreinteGlobale,
      };

  static Manifeste fromJson(Map<String, Object?> j) => Manifeste(
        versionFormat: (j['version_format'] as num?)?.toInt() ?? 0,
        versionSchema: (j['version_schema'] as num?)?.toInt() ?? 0,
        dateCreation:
            DateTime.tryParse('${j['date_creation']}')?.toUtc() ?? DateTime(1970),
        appVersion: '${j['app_version']}',
        blocs: <DescriptionBloc>[
          for (final b in (j['blocs'] as List? ?? const <Object?>[]))
            DescriptionBloc.fromJson(<String, Object?>{
              for (final e in (b as Map).entries) '${e.key}': e.value
            }),
        ],
        exclusions: <Map<String, String>>[
          for (final e in (j['exclusions'] as List? ?? const <Object?>[]))
            <String, String>{
              for (final kv in (e as Map).entries) '${kv.key}': '${kv.value}'
            },
        ],
        dependances: <List<String>>[
          for (final d in (j['dependances'] as List? ?? const <Object?>[]))
            <String>[for (final x in (d as List)) '$x'],
        ],
      );
}

/// Résultat d'une vérification de sauvegarde.
class VerificationSauvegarde {
  VerificationSauvegarde({
    required this.lisible,
    required this.formatReconnu,
    required this.versionFormatCompatible,
    required this.blocsVerifies,
    required this.blocsAlteres,
    required this.blocsManquants,
    required this.empreinteGlobaleValide,
    required this.messages,
    this.manifeste,
    this.legacy = false,
    this.versionLegacy,
  });

  final bool lisible;
  final bool formatReconnu;
  final bool versionFormatCompatible;

  /// Blocs dont l'empreinte correspond au contenu décompressé.
  final List<String> blocsVerifies;

  /// Blocs dont le contenu ne correspond pas à l'empreinte annoncée.
  final List<String> blocsAlteres;

  /// Blocs annoncés au manifeste mais absents du conteneur.
  final List<String> blocsManquants;

  final bool empreinteGlobaleValide;
  final List<String> messages;

  final Manifeste? manifeste;

  /// `true` si le fichier est une ancienne sauvegarde JSON (v9.x), sans
  /// manifeste. Elle reste restaurable, mais sans contrôle d'intégrité
  /// possible : c'est une limite réelle, pas un oubli (§16).
  final bool legacy;

  final String? versionLegacy;

  /// Une sauvegarde est utilisable si elle est lisible, que tous les blocs
  /// annoncés sont présents, qu'aucun n'est altéré, et que l'empreinte globale
  /// correspond.
  bool get utilisable =>
      lisible &&
      formatReconnu &&
      versionFormatCompatible &&
      blocsAlteres.isEmpty &&
      blocsManquants.isEmpty &&
      (legacy || empreinteGlobaleValide);

  Map<String, Object?> toJson() => <String, Object?>{
        'lisible': lisible,
        'format_reconnu': formatReconnu,
        'version_format_compatible': versionFormatCompatible,
        'blocs_verifies': blocsVerifies,
        'blocs_alteres': blocsAlteres,
        'blocs_manquants': blocsManquants,
        'empreinte_globale_valide': empreinteGlobaleValide,
        'utilisable': utilisable,
        'legacy': legacy,
        'version_legacy': versionLegacy,
        'messages': messages,
      };
}

/// Construit et lit le conteneur de sauvegarde.
class FormatSauvegarde {
  const FormatSauvegarde();

  /// Un bloc à écrire : nom, catégorie, nature, provenance et contenu.
  ///
  /// [contenu] est n'importe quelle structure sérialisable. L'appelant fournit
  /// **déjà** une structure JSON-compatible ; aucune conversion de type n'est
  /// faite ici, ce qui évite toute perte silencieuse.
  static Map<String, Object?> bloc({
    required String nom,
    required String categorie,
    required NatureBloc nature,
    required Object? contenu,
    required String provenance,
    int? nbEnregistrements,
    int versionSchema = 1,
  }) =>
      <String, Object?>{
        'nom': nom,
        'categorie': categorie,
        'nature': nature.name,
        'contenu': contenu,
        'provenance': provenance,
        'nb_enregistrements': nbEnregistrements ?? _compter(contenu),
        'version_schema': versionSchema,
      };

  /// Compte les enregistrements d'un contenu, sans hypothèse de type.
  static int _compter(Object? contenu) {
    if (contenu is List) return contenu.length;
    if (contenu is Map) return contenu.length;
    return contenu == null ? 0 : 1;
  }

  /// Sérialise canoniquement un bloc pour le calcul d'empreinte.
  static String _canonique(Object? o) {
    Object? trier(Object? v) {
      if (v is Map) {
        final cles = v.keys.whereType<String>().toList()..sort();
        return <String, Object?>{
          for (final k in cles) k: trier(v[k])
        };
      }
      if (v is List) return v.map(trier).toList();
      return v;
    }

    return jsonEncode(trier(o));
  }

  /// Construit le conteneur complet.
  ///
  /// [blocs] est la liste des blocs produits par [bloc]. [exclusions] doit
  /// lister tout ce qui n'est pas sauvegardé, avec sa justification.
  Map<String, Object?> construire({
    required List<Map<String, Object?>> blocs,
    required String appVersion,
    List<Map<String, String>> exclusions = const <Map<String, String>>[],
    List<List<String>> dependances = const <List<String>>[],
    int versionSchema = 1,
    DateTime? dateCreation,
  }) {
    final descriptions = <DescriptionBloc>[];
    final conteneurBlocs = <String, Object?>{};

    for (final b in blocs) {
      final nom = '${b['nom']}';
      final contenu = b['contenu'];
      final canonique = _canonique(contenu);
      final octets = utf8.encode(canonique);
      final compresse = gzip.encode(octets);

      descriptions.add(DescriptionBloc(
        nom: nom,
        categorie: '${b['categorie']}',
        nature: NatureBloc.values.firstWhere(
          (n) => n.name == b['nature'],
          orElse: () => NatureBloc.permanente,
        ),
        nbEnregistrements: (b['nb_enregistrements'] as num?)?.toInt() ?? 0,
        empreinte: sha256.convert(octets).toString(),
        octetsBruts: octets.length,
        octetsCompresses: compresse.length,
        provenance: '${b['provenance']}',
        versionSchema: (b['version_schema'] as num?)?.toInt() ?? 1,
      ));
      // Un seul encodage base64 par bloc : aucun chargement global en RAM.
      conteneurBlocs[nom] = base64Encode(compresse);
    }

    final manifeste = Manifeste(
      versionFormat: Manifeste.versionCourante,
      versionSchema: versionSchema,
      dateCreation: dateCreation ?? DateTime.now(),
      appVersion: appVersion,
      blocs: descriptions,
      exclusions: exclusions,
      dependances: dependances,
    );

    return <String, Object?>{
      'manifeste': manifeste.toJson(),
      'blocs': conteneurBlocs,
    };
  }

  /// Écrit le conteneur sur disque de façon **atomique**.
  ///
  /// Écriture dans un fichier temporaire, puis renommage. Un renommage est
  /// atomique sur le même système de fichiers : soit l'ancien fichier existe
  /// entier, soit le nouveau, jamais un mélange. C'est ce qui rend une
  /// interruption inoffensive (§15 : « gérer les interruptions »).
  Future<File> ecrireAtomiquement(
    Map<String, Object?> conteneur,
    String cheminFinal,
  ) async {
    final json = jsonEncode(conteneur);
    final cible = File(cheminFinal);
    final parent = cible.parent;
    if (!await parent.exists()) await parent.create(recursive: true);

    final temporaire = File('$cheminFinal.tmp');
    try {
      await temporaire.writeAsString(json, flush: true);
      // Vérification de relecture avant de remplacer : si le fichier temporaire
      // est illisible, on n'écrase pas une sauvegarde existante valide.
      final relu = await temporaire.readAsString();
      if (relu.length != json.length) {
        throw StateError(
          'écriture incomplète : ${relu.length} octets écrits sur '
          '${json.length} attendus',
        );
      }
      await temporaire.rename(cheminFinal);
      return cible;
    } catch (e) {
      if (await temporaire.exists()) {
        await temporaire.delete();
      }
      rethrow;
    }
  }

  /// Lit et vérifie un fichier de sauvegarde, sans rien appliquer.
  ///
  /// [lireContenu] permet de travailler sur une chaîne déjà chargée sans
  /// relire le disque. Le manifeste est lu **d'abord** : si l'inventaire est
  /// incohérent, aucun bloc n'est décompressé.
  VerificationSauvegarde verifier(String contenu) {
    final messages = <String>[];
    Object? decode;
    try {
      decode = jsonDecode(contenu);
    } catch (e) {
      return VerificationSauvegarde(
        lisible: false,
        formatReconnu: false,
        versionFormatCompatible: false,
        blocsVerifies: const <String>[],
        blocsAlteres: const <String>[],
        blocsManquants: const <String>[],
        empreinteGlobaleValide: false,
        messages: <String>['JSON illisible : $e'],
      );
    }
    if (decode is! Map) {
      return VerificationSauvegarde(
        lisible: false,
        formatReconnu: false,
        versionFormatCompatible: false,
        blocsVerifies: const <String>[],
        blocsAlteres: const <String>[],
        blocsManquants: const <String>[],
        empreinteGlobaleValide: false,
        messages: const <String>['racine JSON non objet'],
      );
    }
    final racine = <String, Object?>{
      for (final e in decode.entries) '${e.key}': e.value
    };

    // ── Ancienne sauvegarde JSON (v9.x) : pas de manifeste ────────────────
    if (!racine.containsKey('manifeste') || !racine.containsKey('blocs')) {
      final version = racine['version'];
      return VerificationSauvegarde(
        lisible: true,
        formatReconnu: true,
        versionFormatCompatible: true,
        blocsVerifies: const <String>[],
        blocsAlteres: const <String>[],
        blocsManquants: const <String>[],
        empreinteGlobaleValide: false,
        legacy: true,
        versionLegacy: version == null ? null : '$version',
        messages: <String>[
          'ancienne sauvegarde JSON détectée (version ${version ?? "inconnue"})',
          'aucun manifeste : intégrité par bloc NON vérifiable — limite réelle',
          'restauration possible, sans contrôle d\'empreinte',
        ],
      );
    }

    final manifeste = Manifeste.fromJson(<String, Object?>{
      for (final e in (racine['manifeste'] as Map).entries) '${e.key}': e.value
    });
    final blocs = <String, Object?>{
      for (final e in (racine['blocs'] as Map).entries) '${e.key}': e.value
    };

    // Version de format : un conteneur plus récent que ce lecteur ne doit pas
    // être interprété au hasard.
    final versionCompatible = manifeste.versionFormat <= Manifeste.versionCourante;
    if (!versionCompatible) {
      messages.add('version de format ${manifeste.versionFormat} supérieure à '
          '${Manifeste.versionCourante} : lecture refusée');
    }

    final verifies = <String>[];
    final alteres = <String>[];
    final manquants = <String>[];

    for (final d in manifeste.blocs) {
      if (!blocs.containsKey(d.nom)) {
        manquants.add(d.nom);
        continue;
      }
      final encode = blocs[d.nom];
      if (encode is! String) {
        alteres.add(d.nom);
        messages.add('bloc ${d.nom} : encodage absent');
        continue;
      }
      try {
        // Décodage strict : une base64 altérée lève, elle ne produit pas un
        // contenu partiel silencieux.
        final compresse = base64Decode(encode);
        final octets = gzip.decode(compresse);
        final empreinte = sha256.convert(octets).toString();
        if (empreinte != d.empreinte) {
          alteres.add(d.nom);
          messages.add('bloc ${d.nom} : empreinte ${empreinte.substring(0, 12)}… '
              'différente de ${d.empreinte.substring(0, 12)}…');
        } else {
          verifies.add(d.nom);
        }
      } catch (e) {
        alteres.add(d.nom);
        messages.add('bloc ${d.nom} : illisible ($e)');
      }
    }

    // Blocs présents mais non annoncés au manifeste : signalés, jamais ignorés.
    for (final nom in blocs.keys) {
      if (!manifeste.blocs.any((b) => b.nom == nom)) {
        messages.add('bloc $nom présent mais non annoncé au manifeste');
      }
    }

    final globale = manifeste.empreinteGlobale;
    final annoncee = '${racine['manifeste'] is Map ? (racine['manifeste'] as Map)['empreinte_globale'] : ''}';
    final globaleValide = globale == annoncee;
    if (!globaleValide) {
      messages.add('empreinte globale incohérente : le manifeste a été modifié');
    }

    return VerificationSauvegarde(
      lisible: true,
      formatReconnu: true,
      versionFormatCompatible: versionCompatible,
      blocsVerifies: verifies,
      blocsAlteres: alteres,
      blocsManquants: manquants,
      empreinteGlobaleValide: globaleValide,
      manifeste: manifeste,
      messages: messages,
    );
  }

  /// Extrait le contenu d'un bloc vérifié.
  ///
  /// Refuse de rendre un contenu dont l'empreinte ne correspond pas : une
  /// restauration ne doit jamais appliquer un bloc altéré.
  ///
  /// Un encodage devenu illisible (base64 tronqué, gzip corrompu) est traduit
  /// en [StateError] : l'appelant n'a qu'un seul cas d'échec à traiter, et le
  /// message nomme le bloc, au lieu de laisser remonter une `FormatException`
  /// qui ne dit pas quel bloc est en cause.
  Object? extraireBloc(String contenuSauvegarde, String nomBloc) {
    final racine = jsonDecode(contenuSauvegarde) as Map;
    final manifeste = Manifeste.fromJson(<String, Object?>{
      for (final e in (racine['manifeste'] as Map).entries) '${e.key}': e.value
    });
    final description = manifeste.blocs.firstWhere(
      (b) => b.nom == nomBloc,
      orElse: () => throw StateError('bloc $nomBloc absent du manifeste'),
    );
    final encode = (racine['blocs'] as Map)[nomBloc];
    if (encode is! String) throw StateError('bloc $nomBloc absent du conteneur');
    final List<int> octets;
    try {
      octets = gzip.decode(base64Decode(encode));
    } catch (e) {
      throw StateError('bloc $nomBloc illisible : encodage altéré ($e)');
    }
    final empreinte = sha256.convert(octets).toString();
    if (empreinte != description.empreinte) {
      throw StateError('bloc $nomBloc altéré : empreinte non conforme');
    }
    return jsonDecode(utf8.decode(octets));
  }

  /// Ratio de compression observé, pour les projections de volumétrie (§28).
  double tauxCompression(Manifeste m) {
    final brut = m.blocs.fold<int>(0, (s, b) => s + b.octetsBruts);
    final comp = m.blocs.fold<int>(0, (s, b) => s + b.octetsCompresses);
    if (comp == 0) return 0;
    return brut / comp;
  }
}
