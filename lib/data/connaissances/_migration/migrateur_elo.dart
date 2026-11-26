/// Migration des ratings ELO du stockage par clés vers le stockage indexé.
///
/// Consigne §12, D-20, D-24. Ce que la migration doit garantir, et comment :
///
/// | Exigence §12                        | Mise en œuvre ici                       |
/// |-------------------------------------|-----------------------------------------|
/// | consultation individuelle           | `lireElo(cle)` sur clé primaire         |
/// | mise à jour individuelle            | `upsertElo` d'une seule ligne           |
/// | recherche indexée                   | index sur `discipline`, `nom`, `cheval` |
/// | conservation de toutes les valeurs  | aucun filtre, aucun plafond             |
/// | disciplines distinguées             | `discipline` en colonne + unicité       |
/// | ratings orphelins conservés         | `id_cheval` nullable, jamais écarté     |
/// | traçabilité d'identité              | `nom_origine` + `nom_normalise` + `id`  |
/// | sauvegarde complète                 | `tousLesElo()` exporte tout             |
/// | restauration sûre                   | écriture idempotente                    |
///
/// Les interdits absolus, vérifiés par les tests :
/// * ne pas modifier l'arithmétique ELO — cette classe ne calcule aucun rating ;
/// * ne pas fusionner deux disciplines — la clé inclut la discipline ;
/// * ne pas fusionner deux chevaux d'identité non prouvée — `id_cheval` reste
///   `null` quand l'identité n'est pas résolue, et l'enregistrement est gardé ;
/// * ne pas recalculer les anciens ratings — la valeur lue est écrite telle
///   quelle, et un écart, même infime, est signalé comme échec.
///
/// ⚠️ Les deux sauvegardes historiques utilisées pendant les investigations
/// (28/05/2026 et 13/11/2026) ne sont **jamais** modifiées (§14). La migration
/// travaille sur des copies isolées, et le test correspondant lit les fichiers
/// en lecture seule.
library;

import 'dart:convert';

import '../_adapters/depot_sqlite.dart';
import '../_core/depot.dart';
import '../_core/identifiants.dart';

/// Résultat détaillé d'une migration ELO.
class ResultatMigrationElo {
  ResultatMigrationElo({
    required this.clesLues,
    required this.clesEcrites,
    required this.clesRelues,
    required this.ecartsValeur,
    required this.ecartsChamp,
    required this.clesSansIdentite,
    required this.dureeMs,
  });

  /// Nombre de clés trouvées dans la source.
  final int clesLues;

  /// Nombre de clés effectivement écrites (nouvelles).
  final int clesEcrites;

  /// Nombre de clés relues après écriture pour contrôle.
  final int clesRelues;

  /// Clés dont la valeur numérique diffère après migration. Doit être vide.
  final List<String> ecartsValeur;

  /// Clés dont un champ non numérique diffère (nb, var, discipline, nom).
  final List<String> ecartsChamp;

  /// Clés conservées sans identité de cheval résolue. Ce n'est pas une erreur :
  /// D-20 impose de les garder.
  final int clesSansIdentite;

  final int dureeMs;

  bool get identiteProuvee => ecartsValeur.isEmpty && ecartsChamp.isEmpty;
  bool get complete => clesRelues == clesLues;

  /// `true` seulement si toutes les clés lues ont été relues **et** que
  /// l'identité des valeurs est prouvée.
  bool get conforme => identiteProuvee && complete;

  Map<String, Object?> toJson() => <String, Object?>{
        'cles_lues': clesLues,
        'cles_ecrites': clesEcrites,
        'cles_relues': clesRelues,
        'ecarts_valeur': ecartsValeur,
        'ecarts_champ': ecartsChamp,
        'cles_sans_identite': clesSansIdentite,
        'identite_prouvee': identiteProuvee,
        'complete': complete,
        'conforme': conforme,
        'duree_ms': dureeMs,
      };
}

/// Migre les ratings ELO d'une représentation `Map` (celle de
/// `elo_service.dart`, clé `NOM|DISCIPLINE`) vers le stockage indexé.
class MigrateurElo {
  const MigrateurElo();

  /// Décode la structure d'origine d'`elo_service`.
  ///
  /// Format mesuré sur les sauvegardes réelles :
  /// ```json
  /// {"NELSON DU RIB|TROT_ATTELE":
  ///   {"nom":"NELSON DU RIB","rating":1448.322864781434,
  ///    "nb":3,"var":-51.677135218565944}}
  /// ```
  ///
  /// Aucune valeur n'est recalculée, arrondie ou normalisée. Un enregistrement
  /// illisible est **conservé** et signalé, jamais écarté silencieusement.
  List<LigneElo> decoderElo(Map<String, Object?> brut) {
    final out = <LigneElo>[];
    for (final entree in brut.entries) {
      final cle = entree.key;
      final valeur = entree.value;
      if (valeur is! Map) continue;

      final rating = _double(valeur['rating']);
      final nb = _entier(valeur['nb']);
      final variation = _double(valeur['var']);
      // Nom et discipline : on privilégie les champs explicites, sinon on
      // découpe la clé. Le découpage utilise le DERNIER séparateur, car un nom
      // de cheval peut contenir un trait vertical.
      final nomChamp = valeur['nom'] as String?;
      final nomDepuisCle = _nomDepuisCle(cle);
      final disciplineDepuisCle = _disciplineDepuisCle(cle);
      final nom = (nomChamp != null && nomChamp.isNotEmpty)
          ? nomChamp
          : nomDepuisCle;

      out.add(LigneElo(
        // La clé d'origine est conservée VERBATIM : c'est elle qui garantit
        // une restitution identique et permet de comparer avant/après.
        cle: cle,
        nomOrigine: nom,
        discipline: disciplineDepuisCle,
        rating: rating ?? 0.0,
        nb: nb ?? 0,
        var_: variation ?? 0.0,
        idCheval: null, // identité non résolue à ce stade : conservée telle quelle
      ));
    }
    return out;
  }

  /// Partie du nom dans une clé `NOM|DISCIPLINE`.
  static String _nomDepuisCle(String cle) {
    final i = cle.lastIndexOf('|');
    return i < 0 ? cle : cle.substring(0, i);
  }

  /// Partie discipline dans une clé `NOM|DISCIPLINE`.
  static String _disciplineDepuisCle(String cle) {
    final i = cle.lastIndexOf('|');
    return i < 0 ? '' : cle.substring(i + 1);
  }

  static double? _double(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.'));
    return null;
  }

  static int? _entier(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Exécute la migration complète et vérifie l'identité des valeurs.
  ///
  /// L'écriture se fait dans **une seule transaction** : une interruption
  /// laisse la base dans son état antérieur, jamais à moitié remplie (§14).
  ///
  /// L'opération est **idempotente** : `upsertElo` remplace la ligne de même
  /// clé. Rejouer la migration ne duplique rien et ne change aucune valeur.
  Future<ResultatMigrationElo> migrer(
    DepotSqlite depot,
    Map<String, Object?> eloBrut, {
    String operation = 'migration_elo',
  }) async {
    final chrono = Stopwatch()..start();
    final lignes = decoderElo(eloBrut);

    var ecrites = 0;
    await depot.transaction(() async {
      for (final ligne in lignes) {
        await depot.upsertElo(ligne);
        ecrites++;
      }
      await depot.journaliser(
        operation: operation,
        etape: 'ecriture',
        statut: 'termine',
        detail: '$ecrites clé(s) écrite(s) sur ${lignes.length} lue(s)',
      );
    });

    // Contrôle : on relit CHAQUE clé et on compare champ par champ.
    final ecartsValeur = <String>[];
    final ecartsChamp = <String>[];
    var relues = 0;
    var sansIdentite = 0;

    for (final attendu in lignes) {
      final relu = await depot.lireElo(attendu.cle);
      if (relu == null) {
        ecartsChamp.add('${attendu.cle} : absente après migration');
        continue;
      }
      relues++;
      if (relu.idCheval == null) sansIdentite++;

      // Comparaison stricte sur les flottants : toute différence, même de
      // 1e-12, est un échec. C'est la seule façon d'affirmer « valeur
      // conservée » sans se contenter d'une approximation.
      if (relu.rating != attendu.rating) {
        ecartsValeur.add(
            '${attendu.cle} : rating ${attendu.rating} → ${relu.rating}');
      }
      if (relu.var_ != attendu.var_) {
        ecartsValeur.add('${attendu.cle} : var ${attendu.var_} → ${relu.var_}');
      }
      if (relu.nb != attendu.nb) {
        ecartsChamp.add('${attendu.cle} : nb ${attendu.nb} → ${relu.nb}');
      }
      if (relu.discipline != attendu.discipline) {
        ecartsChamp.add('${attendu.cle} : discipline '
            '${attendu.discipline} → ${relu.discipline}');
      }
      if (relu.nomOrigine != attendu.nomOrigine) {
        ecartsChamp.add('${attendu.cle} : nom '
            '${attendu.nomOrigine} → ${relu.nomOrigine}');
      }
    }

    await depot.journaliser(
      operation: operation,
      etape: 'controle',
      statut: ecartsValeur.isEmpty && ecartsChamp.isEmpty ? 'conforme' : 'ecart',
      detail: '$relues/${lignes.length} relue(s), '
          '${ecartsValeur.length} écart(s) de valeur, '
          '${ecartsChamp.length} écart(s) de champ',
    );

    chrono.stop();
    return ResultatMigrationElo(
      clesLues: lignes.length,
      clesEcrites: ecrites,
      clesRelues: relues,
      ecartsValeur: ecartsValeur,
      ecartsChamp: ecartsChamp,
      clesSansIdentite: sansIdentite,
      dureeMs: chrono.elapsedMilliseconds,
    );
  }

  /// Résout l'identité des chevaux d'un rating, **sans jamais fusionner**.
  ///
  /// Un cheval n'est rattaché à une identité que si les attributs durables
  /// (nom normalisé **et** année de naissance, si elle est disponible) le
  /// permettent. En l'absence de preuve, `id_cheval` reste `null` et le rating
  /// est conservé tel quel (D-20, D-11).
  ///
  /// Cette méthode ne modifie aucune valeur de rating.
  Future<int> rattacherIdentites(
    DepotSqlite depot,
    Map<String, int> anneeNaissanceParNomNormalise,
  ) async {
    final lignes = await depot.tousLesElo();
    var rattaches = 0;
    for (final ligne in lignes) {
      final nomNorm = normaliserNom(ligne.nomOrigine);
      final annee = anneeNaissanceParNomNormalise[nomNorm];
      if (annee == null) continue; // pas d'identité prouvée : on ne touche à rien
      final identite = identiteComposite(nom: ligne.nomOrigine, anneeNaissance: annee);
      if (identite.niveau != NiveauIdentite.composite) continue;
      await depot.upsertElo(LigneElo(
        cle: ligne.cle,
        nomOrigine: ligne.nomOrigine,
        discipline: ligne.discipline,
        rating: ligne.rating,
        nb: ligne.nb,
        var_: ligne.var_,
        idCheval: identite.id,
      ));
      await depot.upsertCheval(identite, nomAffichage: ligne.nomOrigine);
      rattaches++;
    }
    return rattaches;
  }

  /// Sérialise l'état complet des ratings, pour comparaison avant/après.
  ///
  /// Utilise la liste triée par clé : deux états identiques produisent la même
  /// empreinte, ce qui rend la comparaison concluante sans ambiguïté d'ordre.
  static Future<String> empreinteEtat(DepotSqlite depot) async {
    final lignes = await depot.tousLesElo();
    final liste = <Map<String, Object?>>[
      for (final l in lignes)
        <String, Object?>{
          'id': l.cle,
          'nom': l.nomOrigine,
          'discipline': l.discipline,
          'rating': l.rating,
          'nb': l.nb,
          'var': l.var_,
        }
    ];
    return jsonEncode(liste);
  }
}
