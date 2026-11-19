// ═══════════════════════════════════════════════════════════════════════════
//  elo_registre_v3.dart — A7 / 3.3-A : MODÈLE DU REGISTRE D'INTENTION ELO
//
//  ⚠️ LOT PUREMENT PRÉPARATOIRE — AUCUNE INTÉGRATION.
//  Ce fichier n'est importé par AUCUN service et n'importe AUCUN service.
//  Il ne lit ni n'écrit aucune SharedPreferences.
//
//  RÔLE
//  ────
//  Décrire, sérialiser et diagnostiquer le témoin d'application ELO qui vivra
//  sous la clé `elo_registre_v3` (déjà présente dans `_keysELO`, donc déjà
//  dans le périmètre de reset et de sauvegarde — aucune clé n'est ajoutée).
//
//  CE QUE LE REGISTRE EST
//  ──────────────────────
//  Un TÉMOIN. Il dit : « pour la course K, une opération ELO a été engagée,
//  voici l'état des ratings avant et après, et voici quelle issue a été
//  observée ».
//
//  CE QU'IL N'EST JAMAIS — RÈGLE DE SÉCURITÉ CENTRALE
//  ─────────────────────────────────────────────────
//  • JAMAIS une source pour reconstruire `elo_ratings_v2`. Aucune fonction
//    publique de ce fichier ne rend une `Map<String, EloScore>` depuis un
//    registre, et il n'en existera pas.
//  • JAMAIS une preuve de durabilité physique. `shared_preferences_android`
//    écrit par `.apply()` (7 occurrences mesurées) et n'appelle JAMAIS
//    `.commit()` (0 occurrence). Une égalité d'empreinte est une cohérence
//    LOGIQUE constatée, pas une garantie de survie à une coupure.
//  • JAMAIS une protection rétroactive : en mode `historiqueInconnu`, les
//    courses antérieures ne sont pas mémorisées et une double application
//    historique est INDÉTECTABLE.
//
//  ÉTATS PERSISTABLES — `annuleeParReset` N'EN FAIT PAS PARTIE
//  ──────────────────────────────────────────────────────────
//  Décision contractuelle (3.3, correction 1) : `abandonneeParReset` est un
//  état de RAM TRANSITOIRE. Il n'est jamais sérialisé, pour deux raisons
//  démontrées :
//    • quand `_sauvegarder()` le rend par le CONTRÔLE 1, le reset est en
//      cours : toute écriture du registre est refusée et la clé est ensuite
//      effacée ;
//    • quand il le rend par le CONTRÔLE 2, le reset est TERMINÉ : écrire une
//      entrée recréerait `elo_registre_v3` APRÈS son effacement — la
//      transposition exacte de V29-A, défaut que le reset existe pour
//      interdire.
//  Les tests vérifient que la chaîne « annuleeParReset » n'apparaît dans
//  aucun chemin de sérialisation.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

// ───────────────────────────────────────────────────────────────────────────
//  VERSIONNEMENT
// ───────────────────────────────────────────────────────────────────────────

/// Version de SCHÉMA du registre. Un registre dont le `schema` diffère est
/// déclaré `schemaIncompatible` et N'EST JAMAIS interprété, ni supprimé.
const int kSchemaRegistreElo = 3;

/// Version de CONTENU du registre, à l'intérieur du schéma 3.
///
/// ⚠️ Contrôlée à l'égalité stricte, au même titre que [kSchemaRegistreElo].
///    Une `version` différente rend le registre `schemaIncompatible` : il n'est
///    ni interprété, ni supprimé, ni migré automatiquement.
const int kVersionRegistreElo = 1;

/// Clé SharedPreferences du registre. Déjà présente dans `_keysELO`
/// (`backup_service.dart` l.198) — ce fichier ne l'écrit pas.
const String kCleRegistreElo = 'elo_registre_v3';

/// Nombre maximum d'entrées conservées en mémoire avant évaluation de
/// rétention. Ne déclenche AUCUNE suppression : voir [NiveauRetentionElo].
const int kEntreeRegistreSeuilAlerte = 100000;

// ───────────────────────────────────────────────────────────────────────────
//  ÉNUMÉRATIONS PERSISTABLES
// ───────────────────────────────────────────────────────────────────────────

/// Origine du contenu des ratings au moment où le registre a été constitué.
enum OrigineRegistreElo {
  /// Le registre décrit l'historique complet des opérations ELO connues.
  courante,

  /// Les ratings ont été restaurés depuis une sauvegarde SANS registre, ou le
  /// registre a disparu. L'historique d'application antérieur est INCONNU.
  ///
  /// ⚠️ Ce mode n'est JAMAIS présenté comme protégé. Il est conservé jusqu'à
  ///    un reset complet explicite.
  historiqueInconnu,
}

/// Nature d'une entrée de registre.
enum TypeEntreeRegistre {
  /// Opération issue de la porte `appliquerArriveeOfficielle` (P1 uniquement).
  course,

  /// Écriture de ratings HORS porte : import de sauvegarde, réinitialisation,
  /// purge des orphelins, migration v1→v2.
  ///
  /// ⚠️ Ce type ne porte AUCUNE image par cheval : un import peut concerner
  ///    des centaines de chevaux (mesuré : l'export produit la map entière).
  ///    Le discriminant utile est la transition d'empreinte + le cardinal.
  horsCourse,
}

/// Motif précis d'une écriture hors porte.
enum MotifHorsCourse {
  importBackup,
  reinitialisation,
  purgeOrphelins,
  migrationV1,
}

/// Étape d'une entrée — SEULS TROIS ÉTATS SONT PERSISTABLES.
///
/// `abandonneeParReset` est volontairement ABSENT de cette énumération : le
/// rendre sérialisable rouvrirait le défaut V29-A (voir l'en-tête du fichier).
enum EtapeEntreeRegistre {
  /// Intention écrite, issue inconnue. État atteint si le processus s'arrête
  /// entre l'écriture de l'intention et l'acquittement.
  intention,

  /// Ratings écrits ET acquittement écrit. Seul état terminal nominal.
  appliquee,

  /// Ratings NON confirmés (`refusee` ou `echouee`). État TERMINAL : aucune
  /// transition vers [appliquee] n'existe, et aucune n'existera.
  nonConfirmee,
}

/// Issue observée d'une écriture de ratings.
///
/// ⚠️ Miroir EXACT des valeurs atteignables de `EtatPersistanceElo`
///    (`elo_service.dart` l.39-57) MOINS les deux états non persistables
///    (`nonTentee`, `abandonneeParReset`). La conversion est explicite et
///    n'est PAS un `name`-mapping implicite : elle sera écrite dans le lot
///    d'intégration.
///
/// SÉMANTIQUE, REDITE PARCE QU'ELLE EST CENTRALE : [refusee] et [echouee]
/// signifient « persistance NON CONFIRMÉE », JAMAIS « disque inchangé ».
enum IssueEcritureElo {
  persistee,
  refusee,
  echouee,
}

// ───────────────────────────────────────────────────────────────────────────
//  IMAGES AVANT / APRÈS
// ───────────────────────────────────────────────────────────────────────────

/// Image des trois champs observables d'un `EloScore`.
///
/// Ce sont EXACTEMENT les champs sérialisés par `EloScore.toJson()`
/// (`zt_models.dart` l.74-79 : `nom`, `rating`, `nb`, `var`). Aucun autre
/// champ n'entre dans le registre : ni formule, ni probabilité, ni K, ni
/// delta intermédiaire. L'image est un ÉTAT, jamais un CALCUL — une entrée du
/// registre ne peut donc pas servir à recalculer un rating.
class ImageRatingElo {
  final double rating;
  final int nbCourses;
  final double variationMois;

  const ImageRatingElo({
    required this.rating,
    required this.nbCourses,
    required this.variationMois,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'rating': rating,
        'nb': nbCourses,
        'var': variationMois,
      };

  /// Désérialisation STRICTE : tout champ manquant ou mal typé lève.
  ///
  /// ⚠️ Aucune valeur par défaut n'est inventée. Une image incomplète est une
  ///    corruption, pas un cas nominal — la compléter silencieusement
  ///    fabriquerait une preuve.
  factory ImageRatingElo.fromJson(Map<String, dynamic> json) {
    return ImageRatingElo(
      rating: _reelStrict(json, 'rating'),
      nbCourses: _entierStrict(json, 'nb'),
      variationMois: _reelStrict(json, 'var'),
    );
  }

  @override
  String toString() =>
      'ImageRatingElo(rating: $rating, nb: $nbCourses, var: $variationMois)';
}

/// Cheval effectivement MUTÉ par une opération ELO, avec ses images.
///
/// Portée : uniquement les chevaux ayant reçu un delta. Mesuré dans
/// `elo_service.dart` l.435 : `deltas.forEach(...)` ne parcourt que ces clefs.
class ChevalJournalise {
  /// Clé composite `NOM_NORMALISÉ|DISCIPLINE`, telle que produite par
  /// `_cle(nom, discipline)` (`elo_service.dart` l.361-363).
  final String cle;

  /// Nom ORIGINAL du partant, non normalisé — pour l'audit humain.
  final String nom;

  /// `null` signifie : la clé était ABSENTE de `_ratings` avant l'opération.
  ///
  /// ⚠️ Ce `null` est indispensable : `elo_service.dart` l.442 lit
  ///    `ancien?.rating ?? _eloDefaut`, donc une CRÉATION et un rating déjà à
  ///    1500 sont INDISCERNABLES sans ce marqueur.
  final ImageRatingElo? avant;

  /// État après mutation. Toujours connu : `elo_service.dart` l.446 affecte
  /// inconditionnellement `_ratings[cle] = EloScore(...)`.
  final ImageRatingElo apres;

  const ChevalJournalise({
    required this.cle,
    required this.nom,
    required this.avant,
    required this.apres,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cle': cle,
        'nom': nom,
        'avant': avant?.toJson(),
        'apres': apres.toJson(),
      };

  factory ChevalJournalise.fromJson(Map<String, dynamic> json) {
    final avantBrut = json['avant'];
    if (avantBrut != null && avantBrut is! Map<String, dynamic>) {
      throw const FormatException('cheval.avant : objet ou null attendu');
    }
    return ChevalJournalise(
      cle: _chaineStrict(json, 'cle'),
      nom: _chaineStrict(json, 'nom'),
      avant: avantBrut == null
          ? null
          : ImageRatingElo.fromJson(avantBrut as Map<String, dynamic>),
      apres: ImageRatingElo.fromJson(_mapStrict(json, 'apres')),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
//  ENTRÉE DE REGISTRE
// ───────────────────────────────────────────────────────────────────────────

/// Une opération ELO journalisée.
///
/// Invariants vérifiés à la désérialisation (et testés) :
///   • [etape] == [EtapeEntreeRegistre.intention] ⇒ [issue] == null, [tsFinal] == null ;
///   • [etape] == [EtapeEntreeRegistre.appliquee] ⇒ [issue] == persistee, [tsFinal] != null ;
///   • [etape] == [EtapeEntreeRegistre.nonConfirmee] ⇒ [issue] ∈ {refusee, echouee}, [tsFinal] == null ;
///   • [type] == course ⇒ [cle], [numR], [numC], [date], [discipline] non nuls ;
///   • [type] == horsCourse ⇒ [motif] non nul, [chevaux] vide.
class EntreeRegistreElo {
  final int id;
  final TypeEntreeRegistre type;

  // — champs de type `course` —
  final String? cle;
  final int? numR;
  final int? numC;
  final String? date; // YYYY-MM-DD
  final String? discipline;

  // — champs de type `horsCourse` —
  final MotifHorsCourse? motif;
  final int? nbChevauxAvant;
  final int? nbChevauxApres;

  final EtapeEntreeRegistre etape;
  final IssueEcritureElo? issue;

  final int tsIntention;
  final int? tsFinal;

  /// Empreinte des ratings AVANT l'opération.
  final String empreinteAvant;

  /// Empreinte des ratings APRÈS l'opération. Calculée AVANT la mutation
  /// disque, elle est une PROMESSE vérifiable au chargement suivant — pas une
  /// constatation. C'est ce qui rend la vérification non circulaire.
  final String empreinteApres;

  /// Images des chevaux mutés. Vide pour [TypeEntreeRegistre.horsCourse].
  final List<ChevalJournalise> chevaux;

  const EntreeRegistreElo({
    required this.id,
    required this.type,
    this.cle,
    this.numR,
    this.numC,
    this.date,
    this.discipline,
    this.motif,
    this.nbChevauxAvant,
    this.nbChevauxApres,
    required this.etape,
    this.issue,
    required this.tsIntention,
    this.tsFinal,
    required this.empreinteAvant,
    required this.empreinteApres,
    this.chevaux = const <ChevalJournalise>[],
  });

  /// Vrai si l'entrée n'est pas dans un état terminal nominal. Une telle
  /// entrée BLOQUE toute nouvelle soumission de la même clé et n'est JAMAIS
  /// supprimée automatiquement.
  bool get estIncertaine => etape != EtapeEntreeRegistre.appliquee;

  /// Vrai si le blocage anti-double-application s'applique à cette entrée.
  ///
  /// Les TROIS états persistables bloquent. Aucune dérogation : `intention`
  /// (issue inconnue), `nonConfirmee` (ni preuve d'écriture ni preuve
  /// d'absence) et `appliquee` (déjà appliquée) sont tous bloquants.
  bool get bloqueNouvelleSoumission => true;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'id': id,
      'type': type.name,
      'etape': etape.name,
      'issue': issue?.name,
      'tsIntention': tsIntention,
      'tsFinal': tsFinal,
      'empreinteAvant': empreinteAvant,
      'empreinteApres': empreinteApres,
    };
    if (type == TypeEntreeRegistre.course) {
      json['cle'] = cle;
      json['numR'] = numR;
      json['numC'] = numC;
      json['date'] = date;
      json['discipline'] = discipline;
      json['chevaux'] = chevaux.map((c) => c.toJson()).toList();
    } else {
      json['motif'] = motif!.name;
      json['nbChevauxAvant'] = nbChevauxAvant;
      json['nbChevauxApres'] = nbChevauxApres;
    }
    return json;
  }

  factory EntreeRegistreElo.fromJson(Map<String, dynamic> json) {
    final type = _enumStrict(TypeEntreeRegistre.values, json, 'type');
    final etape = _enumStrict(EtapeEntreeRegistre.values, json, 'etape');

    final issueBrute = json['issue'];
    IssueEcritureElo? issue;
    if (issueBrute != null) {
      if (issueBrute is! String) {
        throw const FormatException('entree.issue : chaîne ou null attendu');
      }
      issue = _valeurEnum(TypeEcritureElo.valuesCompat, issueBrute, 'issue');
    }

    final tsFinalBrut = json['tsFinal'];
    final int? tsFinal;
    if (tsFinalBrut == null) {
      tsFinal = null;
    } else if (tsFinalBrut is int) {
      tsFinal = tsFinalBrut;
    } else if (tsFinalBrut is double && tsFinalBrut == tsFinalBrut.roundToDouble()) {
      tsFinal = tsFinalBrut.toInt();
    } else {
      throw const FormatException('entree.tsFinal : entier ou null attendu');
    }

    final empreinteAvant = _chaineStrict(json, 'empreinteAvant');
    final empreinteApres = _chaineStrict(json, 'empreinteApres');
    _validerEmpreinte(empreinteAvant, 'empreinteAvant');
    _validerEmpreinte(empreinteApres, 'empreinteApres');

    // ── Invariants étape / issue / tsFinal ──────────────────────────────
    switch (etape) {
      case EtapeEntreeRegistre.intention:
        if (issue != null) {
          throw const FormatException(
              'entree : etape=intention exige issue=null');
        }
        if (tsFinal != null) {
          throw const FormatException(
              'entree : etape=intention exige tsFinal=null');
        }
      case EtapeEntreeRegistre.appliquee:
        if (issue != IssueEcritureElo.persistee) {
          throw const FormatException(
              'entree : etape=appliquee exige issue=persistee');
        }
        if (tsFinal == null) {
          throw const FormatException(
              'entree : etape=appliquee exige tsFinal non nul');
        }
      case EtapeEntreeRegistre.nonConfirmee:
        if (issue != IssueEcritureElo.refusee &&
            issue != IssueEcritureElo.echouee) {
          throw const FormatException(
              'entree : etape=nonConfirmee exige issue=refusee|echouee');
        }
        if (tsFinal != null) {
          throw const FormatException(
              'entree : etape=nonConfirmee exige tsFinal=null');
        }
    }

    final id = _entierStrict(json, 'id');
    final tsIntention = _entierStrict(json, 'tsIntention');

    if (type == TypeEntreeRegistre.course) {
      final chevauxBruts = json['chevaux'];
      if (chevauxBruts is! List) {
        throw const FormatException('entree.chevaux : liste attendue');
      }
      final chevaux = <ChevalJournalise>[];
      for (final brut in chevauxBruts) {
        if (brut is! Map<String, dynamic>) {
          throw const FormatException('entree.chevaux[i] : objet attendu');
        }
        chevaux.add(ChevalJournalise.fromJson(brut));
      }
      return EntreeRegistreElo(
        id: id,
        type: type,
        cle: _chaineStrict(json, 'cle'),
        numR: _entierStrict(json, 'numR'),
        numC: _entierStrict(json, 'numC'),
        date: _chaineStrict(json, 'date'),
        discipline: _chaineStrict(json, 'discipline'),
        etape: etape,
        issue: issue,
        tsIntention: tsIntention,
        tsFinal: tsFinal,
        empreinteAvant: empreinteAvant,
        empreinteApres: empreinteApres,
        chevaux: chevaux,
      );
    }

    // horsCourse
    final chevauxBruts = json['chevaux'];
    if (chevauxBruts is List && chevauxBruts.isNotEmpty) {
      throw const FormatException(
          'entree horsCourse : chevaux doit être absente ou vide');
    }
    return EntreeRegistreElo(
      id: id,
      type: type,
      motif: _enumStrict(MotifHorsCourse.values, json, 'motif'),
      nbChevauxAvant: _entierStrict(json, 'nbChevauxAvant'),
      nbChevauxApres: _entierStrict(json, 'nbChevauxApres'),
      etape: etape,
      issue: issue,
      tsIntention: tsIntention,
      tsFinal: tsFinal,
      empreinteAvant: empreinteAvant,
      empreinteApres: empreinteApres,
    );
  }

  @override
  String toString() =>
      'EntreeRegistreElo(id: $id, type: ${type.name}, etape: ${etape.name}, '
      'issue: ${issue?.name}, chevaux: ${chevaux.length})';
}

// ───────────────────────────────────────────────────────────────────────────
//  REGISTRE
// ───────────────────────────────────────────────────────────────────────────

/// Contenu complet de la clé `elo_registre_v3`.
class RegistreEloV3 {
  final int schema;
  final int version;
  final int horloge;
  final String empreinteRatings;
  final OrigineRegistreElo origine;
  final List<EntreeRegistreElo> entrees;

  const RegistreEloV3({
    required this.schema,
    required this.version,
    required this.horloge,
    required this.empreinteRatings,
    required this.origine,
    required this.entrees,
  });

  /// Registre vierge, utilisé au tout premier usage.
  ///
  /// [origine] vaut [OrigineRegistreElo.courante] : il n'y a aucun historique
  /// antérieur à protéger.
  factory RegistreEloV3.vierge({required String empreinteRatings}) =>
      RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 0,
        empreinteRatings: empreinteRatings,
        origine: OrigineRegistreElo.courante,
        entrees: const <EntreeRegistreElo>[],
      );

  /// Vrai si ce registre peut être INTERPRÉTÉ par le code courant.
  ///
  /// Le contrôle porte sur les DEUX champs de versionnement, pas seulement sur
  /// `schema` :
  ///   • `schema == kSchemaRegistreElo` — la FORME du conteneur est connue ;
  ///   • `version == kVersionRegistreElo` — la SÉMANTIQUE du contenu est connue.
  ///
  /// ⚠️ POURQUOI LA VERSION COMPTE AUTANT QUE LE SCHÉMA. Un registre de schéma
  ///    3 et de `version` inconnue (2, 0, …) reste désérialisable : ses champs
  ///    existent, ses invariants tiennent. Mais la SIGNIFICATION de ses entrées
  ///    peut avoir changé. L'interpréter reviendrait à décider d'un sens qu'on
  ///    ne possède pas — exactement ce que ce modèle s'interdit. Il est donc
  ///    refusé comme un schéma étranger, et pour la même raison.
  ///
  /// Ce getter est le SEUL point de décision sur la lisibilité :
  /// `diagnostiquerRegistre` s'y ramène, et `autoriseApplication` comme
  /// `protegeContreDoubleApplication` en dérivent via la cohérence. Aucun autre
  /// chemin ne peut déclarer un registre lisible — et un registre refusé ici
  /// n'est ni supprimé, ni réinitialisé, ni migré, ni réinterprété.
  bool get interpretable =>
      schema == kSchemaRegistreElo && version == kVersionRegistreElo;

  /// Entrées INCERTAINES, dans l'ordre du journal. Elles ne sont JAMAIS
  /// supprimées automatiquement, pour aucun motif.
  List<EntreeRegistreElo> get entreesIncertaines =>
      entrees.where((e) => e.estIncertaine).toList(growable: false);

  /// Cherche une entrée de type `course` pour [cle]. Rend la PLUS RÉCENTE
  /// (id le plus grand), ou `null`.
  EntreeRegistreElo? entreePourCle(String cle) {
    EntreeRegistreElo? trouvee;
    for (final entree in entrees) {
      if (entree.type != TypeEntreeRegistre.course) continue;
      if (entree.cle != cle) continue;
      if (trouvee == null || entree.id > trouvee.id) trouvee = entree;
    }
    return trouvee;
  }

  RegistreEloV3 copyWith({
    int? horloge,
    String? empreinteRatings,
    OrigineRegistreElo? origine,
    List<EntreeRegistreElo>? entrees,
  }) =>
      RegistreEloV3(
        schema: schema,
        version: version,
        horloge: horloge ?? this.horloge,
        empreinteRatings: empreinteRatings ?? this.empreinteRatings,
        origine: origine ?? this.origine,
        entrees: entrees ?? this.entrees,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': schema,
        'version': version,
        'horloge': horloge,
        'empreinteRatings': empreinteRatings,
        'origine': origine.name,
        'entrees': entrees.map((e) => e.toJson()).toList(),
      };

  /// Sérialisation destinée à `setString`. **Aucune écriture n'est faite ici.**
  ///
  /// `jsonEncode` peut lever si un `double` non fini a été injecté dans une
  /// image (mesuré : `JsonUnsupportedObjectError` sur `NaN`/`Infinity`).
  /// Ce n'est pas un défaut du modèle : c'est la raison pour laquelle
  /// l'appelant devra traiter l'exception, comme le fait déjà
  /// `_executerSauvegarde` pour `elo_ratings_v2`.
  String encoder() => jsonEncode(toJson());

  /// Désérialisation STRICTE depuis une chaîne.
  ///
  /// Lève [FormatException] si le JSON est invalide, si un champ obligatoire
  /// manque, ou si un type est incorrect. **Un `schema` ou une `version`
  /// différents ne lèvent PAS** : le registre est rendu tel quel, intact, et
  /// c'est [interpretable] qui décide de son refus.
  factory RegistreEloV3.decoder(String jsonBrut) {
    final Object? decode;
    try {
      decode = jsonDecode(jsonBrut);
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('registre : JSON illisible ($e)');
    }
    if (decode is! Map<String, dynamic>) {
      throw const FormatException('registre : objet JSON attendu');
    }
    return RegistreEloV3.fromJson(decode);
  }

  factory RegistreEloV3.fromJson(Map<String, dynamic> json) {
    final schema = _entierStrict(json, 'schema');
    final version = _entierStrict(json, 'version');
    final horloge = _entierStrict(json, 'horloge');
    final empreinteRatings = _chaineStrict(json, 'empreinteRatings');
    _validerEmpreinte(empreinteRatings, 'empreinteRatings');
    final origine = _enumStrict(OrigineRegistreElo.values, json, 'origine');

    final entreesBrutes = json['entrees'];
    if (entreesBrutes is! List) {
      throw const FormatException('registre.entrees : liste attendue');
    }
    final entrees = <EntreeRegistreElo>[];
    for (final brut in entreesBrutes) {
      if (brut is! Map<String, dynamic>) {
        throw const FormatException('registre.entrees[i] : objet attendu');
      }
      entrees.add(EntreeRegistreElo.fromJson(brut));
    }

    return RegistreEloV3(
      schema: schema,
      version: version,
      horloge: horloge,
      empreinteRatings: empreinteRatings,
      origine: origine,
      entrees: entrees,
    );
  }

  @override
  String toString() => 'RegistreEloV3(schema: $schema, version: $version, '
      'horloge: $horloge, origine: ${origine.name}, '
      'entrees: ${entrees.length})';
}

// ───────────────────────────────────────────────────────────────────────────
//  DIAGNOSTICS — FONCTIONS PURES
// ───────────────────────────────────────────────────────────────────────────

/// Cohérence entre ce que le disque contient et ce que le registre déclare.
enum DiagnosticCoherenceElo {
  /// Aucun registre sur le disque. Traité par [OrigineRegistreElo].
  registreAbsent,

  /// L'empreinte des ratings du disque est celle que le registre déclare.
  coherent,

  /// Les empreintes diffèrent. **La CAUSE n'est pas identifiée** : downgrade,
  /// écriture interrompue, modification externe, reset partiel et défaut de
  /// l'application produisent le MÊME écart.
  divergent,

  /// Le contenu n'est pas désérialisable (JSON invalide, champ manquant,
  /// type incorrect, invariant violé).
  corrompu,

  /// Le registre est REFUSÉ, jamais `coherent`, même empreinte identique.
  ///
  /// Couvre DEUX causes distinctes, volontairement réunies sous un seul état
  /// pour rester une correction minimale :
  ///   • `schema` différent de [kSchemaRegistreElo] — forme inconnue ;
  ///   • `version` différente de [kVersionRegistreElo] — forme connue mais
  ///     SÉMANTIQUE de contenu inconnue (voir [RegistreEloV3.interpretable]).
  ///
  /// ⚠️ Ce diagnostic l'emporte sur la comparaison d'empreintes. Une empreinte
  ///    identique ne peut donc JAMAIS produire `coherent` sur un registre
  ///    incompatible : le test T-V7 le vérifie explicitement.
  schemaIncompatible,
}

/// Verdict complet, rendu par [diagnostiquerRegistre].
///
/// Porte DEUX informations distinctes, qu'il ne faut jamais confondre :
///   • [coherence] — l'état des ratings correspond-il à ce qui est déclaré ?
///   • [origine] — l'historique d'application est-il connu ?
///
/// Un registre `coherent` d'origine `historiqueInconnu` est parfaitement
/// normal : il déclare simplement que les courses ANTÉRIEURES à la
/// restauration ne sont pas mémorisées.
class ResultatDiagnosticElo {
  final DiagnosticCoherenceElo coherence;
  final OrigineRegistreElo origine;

  /// Empreinte attendue par le registre, `null` si registre absent ou illisible.
  final String? empreinteRegistre;

  /// Empreinte effectivement calculée sur les ratings du disque.
  final String empreinteDisque;

  /// Empreinte AVANT du registre, si lisible — utile au diagnostic.
  final RegistreEloV3? registre;

  const ResultatDiagnosticElo({
    required this.coherence,
    required this.origine,
    required this.empreinteRegistre,
    required this.empreinteDisque,
    this.registre,
  });

  /// Vrai si une nouvelle application ELO peut être tentée.
  ///
  /// Fail-closed : `divergent`, `corrompu` et `schemaIncompatible` refusent.
  /// `registreAbsent` et `coherent` autorisent — mais voir
  /// [protegeContreDoubleApplication].
  bool get autoriseApplication =>
      coherence == DiagnosticCoherenceElo.coherent ||
      coherence == DiagnosticCoherenceElo.registreAbsent;

  /// Vrai si le registre protège EFFECTIVEMENT contre une double application.
  ///
  /// ⚠️ FAUX en mode `historiqueInconnu`. Aucun message, aucun log et aucune
  ///    UI ne doit présenter ce mode comme protégé.
  bool get protegeContreDoubleApplication =>
      coherence == DiagnosticCoherenceElo.coherent &&
      origine == OrigineRegistreElo.courante;

  /// Message destiné à l'utilisateur. Pour `historiqueInconnu`, la chaîne est
  /// IMPOSÉE par le contrat : elle ne doit jamais être reformulée en
  /// « protégé », « sécurisé » ou « vérifié ».
  String get message {
    switch (coherence) {
      case DiagnosticCoherenceElo.registreAbsent:
        if (origine == OrigineRegistreElo.historiqueInconnu) {
          return 'Historique d\'application ELO inconnu. Les courses '
              'antérieures ne sont pas mémorisées. Une nouvelle application '
              'sur l\'une d\'elles ne peut pas être détectée par le registre.';
        }
        return 'Premier usage : aucun registre ELO antérieur.';
      case DiagnosticCoherenceElo.coherent:
        if (origine == OrigineRegistreElo.historiqueInconnu) {
          return 'Historique d\'application ELO inconnu. Les courses '
              'antérieures ne sont pas mémorisées. Une nouvelle application '
              'sur l\'une d\'elles ne peut pas être détectée par le registre.';
        }
        return 'Registre ELO cohérent.';
      case DiagnosticCoherenceElo.divergent:
        return 'Incohérence ELO : les ratings ne correspondent pas à ce que '
            'le registre déclare. La cause n\'est pas identifiée. Aucune '
            'application automatique, aucune reconstruction.';
      case DiagnosticCoherenceElo.corrompu:
        return 'Registre ELO illisible. Aucune application automatique. '
            'Le registre n\'est pas supprimé.';
      case DiagnosticCoherenceElo.schemaIncompatible:
        return 'Registre ELO d\'un schéma ou d\'une version incompatible. '
            'Aucune application automatique. Le registre n\'est pas supprimé.';
    }
  }

  @override
  String toString() => 'ResultatDiagnosticElo(coherence: ${coherence.name}, '
      'origine: ${origine.name}, autoriseApplication: $autoriseApplication, '
      'protege: $protegeContreDoubleApplication)';
}

/// Diagnostique l'état ELO à partir de la valeur brute de `elo_registre_v3`
/// et de l'empreinte calculée sur les ratings effectivement chargés.
///
/// FONCTION PURE : aucun accès disque, aucune mutation.
///
/// @param jsonRegistre valeur brute de la clé, `null` si la clé est absente.
/// @param empreinteDisque `empreinte64Ratings(_ratings)` au moment de l'appel.
/// @param nombreRatings `_ratings.length` — seul moyen de distinguer un
///        premier usage d'un historique inconnu, une empreinte ne portant pas
///        le cardinal de façon lisible sans la re-calculer.
ResultatDiagnosticElo diagnostiquerRegistre({
  required String? jsonRegistre,
  required String empreinteDisque,
  required int nombreRatings,
}) {
  if (jsonRegistre == null) {
    return ResultatDiagnosticElo(
      coherence: DiagnosticCoherenceElo.registreAbsent,
      origine: nombreRatings == 0
          ? OrigineRegistreElo.courante
          : OrigineRegistreElo.historiqueInconnu,
      empreinteRegistre: null,
      empreinteDisque: empreinteDisque,
    );
  }

  if (jsonRegistre.trim().isEmpty) {
    return ResultatDiagnosticElo(
      coherence: DiagnosticCoherenceElo.corrompu,
      origine: OrigineRegistreElo.historiqueInconnu,
      empreinteRegistre: null,
      empreinteDisque: empreinteDisque,
    );
  }

  final RegistreEloV3 registre;
  try {
    registre = RegistreEloV3.decoder(jsonRegistre);
  } on FormatException {
    return ResultatDiagnosticElo(
      coherence: DiagnosticCoherenceElo.corrompu,
      origine: OrigineRegistreElo.historiqueInconnu,
      empreinteRegistre: null,
      empreinteDisque: empreinteDisque,
    );
  }

  if (!registre.interpretable) {
    return ResultatDiagnosticElo(
      coherence: DiagnosticCoherenceElo.schemaIncompatible,
      origine: registre.origine,
      empreinteRegistre: registre.empreinteRatings,
      empreinteDisque: empreinteDisque,
      registre: registre,
    );
  }

  return ResultatDiagnosticElo(
    coherence: registre.empreinteRatings == empreinteDisque
        ? DiagnosticCoherenceElo.coherent
        : DiagnosticCoherenceElo.divergent,
    origine: registre.origine,
    empreinteRegistre: registre.empreinteRatings,
    empreinteDisque: empreinteDisque,
    registre: registre,
  );
}

// ───────────────────────────────────────────────────────────────────────────
//  SOUS-ÉTATS D'INTERRUPTION — FONCTION PURE
// ───────────────────────────────────────────────────────────────────────────

/// Ce que l'on peut déduire d'une entrée non terminale au redémarrage.
///
/// ⚠️ La distinction repose UNIQUEMENT sur une comparaison positive
///    d'empreintes. Elle dit à quel ÉTAT CONNU le disque correspond, elle ne
///    dit JAMAIS POURQUOI.
enum SousEtatInterruptionElo {
  /// Aucune entrée non terminale : rien à déduire.
  aucune,

  /// L'empreinte disque est celle d'AVANT l'opération : les ratings n'ont pas
  /// bougé. Le système ne sait pas si l'écriture a été tentée puis annulée.
  intentionSansEcriture,

  /// L'empreinte disque est celle d'APRÈS l'opération : les ratings SONT
  /// l'après. Le système ne sait pas si `setString` a répondu `true`.
  appliqueeSansAcquittement,

  /// L'empreinte disque n'est ni l'avant ni l'après de l'entrée : elle ne
  /// permet aucune attribution.
  indetermine,
}

/// Déduit le sous-état d'interruption d'une entrée.
///
/// FONCTION PURE. Ne lit rien, ne décide rien.
///
/// ⚠️ LIMITE DÉCLARÉE : la comparaison porte sur une empreinte GLOBALE. Si
///    plusieurs entrées non terminales coexistent, l'empreinte disque ne peut
///    correspondre qu'à au plus UNE d'entre elles ; les autres rendent
///    [SousEtatInterruptionElo.indetermine]. Ce n'est pas une erreur : c'est
///    la reconnaissance honnête qu'une empreinte globale ne localise rien.
SousEtatInterruptionElo sousEtatInterruption({
  required EntreeRegistreElo entree,
  required String empreinteDisque,
}) {
  if (!entree.estIncertaine) return SousEtatInterruptionElo.aucune;
  if (empreinteDisque == entree.empreinteApres) {
    return SousEtatInterruptionElo.appliqueeSansAcquittement;
  }
  if (empreinteDisque == entree.empreinteAvant) {
    return SousEtatInterruptionElo.intentionSansEcriture;
  }
  return SousEtatInterruptionElo.indetermine;
}

// ───────────────────────────────────────────────────────────────────────────
//  RÉTENTION — SEUILS DE NOMMAGE EN OCTETS UTF-8
//
//  ⚠️ CES SEUILS NE DÉCIDENT DE RIEN. Ils ne servent qu'à NOMMER un niveau
//    d'affichage. Aucune écriture, aucun refus, aucune autorisation, aucune
//    compaction, aucune purge n'en dépend. Vérifiable : la recherche
//      grep -rn "classerRetention" lib/
//    ne rend que sa définition et DEUX appels, tous deux dans
//    `services/elo_service.dart` (`_hydraterNiveauRegistre` /
//    `_observerNiveauRegistre`), qui n'écrivent qu'un champ lu par AUCUNE
//    décision.
//
//  ── CROISSANCE ────────────────────────────────────────────────────────────
//
//  Les AJOUTS ORDINAIRES sont APPEND-ONLY : une nouvelle entrée est
//  concaténée (`[...registre.entrees, entree]`) et AUCUNE entrée n'est jamais
//  retirée, filtrée, compactée ni purgée. Aucun plafond de taille n'existe.
//
//  Ce caractère append-only décrit les AJOUTS, PAS la totalité des écritures.
//  DEUX opérations EXPLICITES de l'utilisateur réécrivent le registre entier
//  et peuvent donc le faire DÉCROÎTRE comme CROÎTRE :
//    • le RESET COMPLET : la clé `elo_registre_v3` est effacée, le registre
//      devient ABSENT ; les ratings sont effacés dans le même geste.
//    • la RESTAURATION d'une sauvegarde : `_ecrireRegistreVerbatim` écrit le
//      JSON de sauvegarde TEL QUEL, sans AUCUN contrôle de taille — ni
//      minimum, ni maximum, ni comparaison avec l'état précédent. Mesuré sur
//      le registre de test : 7 144 737 → 1 561 octets dans un sens, puis
//      1 561 → 7 144 737 dans l'autre.
//  Ni l'un ni l'autre n'est un mécanisme de rétention : aucun ne s'exécute
//  sans une action explicite. Aucune compaction ni purge automatique
//  n'existe à ce jour.
//
//  ── TAILLES : POINTS D'UN BANC DE MESURE, PAS UNE PRÉVISION ───────────────
//
//  Les valeurs ci-dessous proviennent d'un banc reproductible et dépendent
//  FORTEMENT du contenu. Conditions exactes : entrées `course`, 12 chevaux
//  par entrée, images `avant` ET `apres` présentes pour chaque cheval,
//  empreintes de 16 caractères hexadécimaux, série encodée dans l'enveloppe
//  réelle du modèle.
//
//    • noms courts « C0 »..« C11 »         ≈ 1 798 o par course
//    • noms réels « JAZZ DE BEAUVOIR0 »..   ≈ 2 158 o par course
//    • mêmes noms avec accents              ≈ 2 326 o par course
//
//  Le seuil de 6 Mio est franchi vers 3 500 courses avec des noms courts,
//  vers 2 900 avec des noms réels, et seulement vers 21 000 si les `chevaux`
//  sont absents. Ce sont des ordres de grandeur de CE banc, PAS une garantie
//  pour un usage réel : nombre de chevaux, longueur des noms et présence des
//  images font varier la taille du simple au double. Aucune extrapolation à
//  un usage réel n'est revendiquée ici.
//
//  ⚠️ LES VALEURS ANTÉRIEUREMENT DOCUMENTÉES (2 195 o, 149 o, 14,7×,
//    ≈ 1,81 Mio pour 10 000 courses) ont été retirées. Ce n'étaient pas des
//    mesures mais une PROJECTION SOUS HYPOTHÈSE : 1,81 Mio vaut exactement
//    200 x 2 195 + 9 800 x 149, soit « 2 % d'entrées intactes et 98 %
//    compactées ». Or cette compaction n'existe PAS en production : la
//    fonction `compacterEntree` n'a AUCUN appelant (voir sa documentation).
//    Sans elle, la même série de 10 000 courses pèse un ordre de grandeur de
//    plus. Rien ne permet d'affirmer que ces valeurs redeviendraient exactes
//    si une compaction était un jour branchée : elles reposaient sur un
//    format d'entrée et une proportion qui n'ont jamais été confrontés au
//    code exécuté.
// ───────────────────────────────────────────────────────────────────────────

/// Niveau de rétention, calculé sur la taille sérialisée.
///
/// PUREMENT INFORMATIF : le niveau nomme une tranche de taille, il ne
/// conditionne aucun comportement. Voir l'en-tête de section ci-dessus.
enum NiveauRetentionElo {
  /// Sous le seuil de veille.
  normal,

  /// ≥ 1,5 Mio. Niveau PUREMENT INFORMATIF : aucun comportement ne lui est
  /// associé. En particulier, AUCUNE compaction n'est déclenchée ni même
  /// disponible en production — `compacterEntree` n'a aucun appelant (voir sa
  /// documentation). Les entrées incertaines ne sont jamais compactées ni
  /// supprimées, comme toutes les autres.
  veille,

  /// ≥ 3 Mio. Niveau PUREMENT INFORMATIF : simple signal d'affichage.
  /// L'ELO continue exactement comme en `normal`.
  alerte,

  /// ≥ 6 Mio. Niveau PUREMENT INFORMATIF.
  ///
  /// ⚠️ Malgré la formulation antérieure, ce n'est PAS un état « fail-closed »
  /// et l'ELO ne s'arrête PAS : « plus aucune application » était FAUX. Aucun
  /// des neuf `MotifRefusApplicationElo` ne dépend de la taille, et une course
  /// s'applique normalement au-delà de 6 Mio (mesuré).
  saturation,
}

const int kSeuilVeilleOctets = 1572864; // 1,5 Mio
const int kSeuilAlerteOctets = 3145728; // 3 Mio
const int kSeuilSaturationOctets = 6291456; // 6 Mio

/// Classe une taille en octets. FONCTION PURE.
NiveauRetentionElo classerRetention(int tailleOctets) {
  if (tailleOctets >= kSeuilSaturationOctets) return NiveauRetentionElo.saturation;
  if (tailleOctets >= kSeuilAlerteOctets) return NiveauRetentionElo.alerte;
  if (tailleOctets >= kSeuilVeilleOctets) return NiveauRetentionElo.veille;
  return NiveauRetentionElo.normal;
}

/// Compacte une entrée `appliquee` en retirant ses images par cheval.
///
/// ⚠️ AUCUN APPELANT EN PRODUCTION — FONCTION NON BRANCHÉE.
/// Vérifiable : `grep -rn "compacterEntree" lib/` ne rend QUE cette
/// définition. Les seuls appels existants sont dans
/// `test/a7_33a_registre_empreinte_test.dart` (groupe T-L). Aucune compaction
/// automatique n'existe donc, et aucun seuil ne la déclenche : cette fonction
/// est conservée comme outil documenté, PAS comme mécanisme de rétention
/// actif. Ne pas la présenter comme une politique de compaction en vigueur.
///
/// Conséquence directe : les tailles de registre réelles sont celles d'entrées
/// NON compactées. Toute estimation qui suppose une compaction décrit un état
/// que le code n'atteint pas (voir l'en-tête de section ci-dessus).
///
/// SÉCURITÉ (propriété de cette fonction, si elle était un jour branchée) :
/// refuse de compacter une entrée incertaine — ses `chevaux` sont sa seule
/// valeur de preuve. Rend l'entrée inchangée dans ce cas.
///
/// Aucune information n'est perdue par la compaction au regard des garanties
/// du modèle : le blocage ne dépend que de `cle` + `etape` + `issue`, et la
/// vérification d'empreinte ne dépend que de `empreinteAvant` /
/// `empreinteApres`. Ce qui disparaît, ce sont les images par cheval —
/// c'est-à-dire la preuve détaillée de la mutation, et non la preuve
/// d'application.
EntreeRegistreElo compacterEntree(EntreeRegistreElo entree) {
  if (entree.estIncertaine) return entree;
  if (entree.chevaux.isEmpty) return entree;
  return EntreeRegistreElo(
    id: entree.id,
    type: entree.type,
    cle: entree.cle,
    numR: entree.numR,
    numC: entree.numC,
    date: entree.date,
    discipline: entree.discipline,
    motif: entree.motif,
    nbChevauxAvant: entree.nbChevauxAvant,
    nbChevauxApres: entree.nbChevauxApres,
    etape: entree.etape,
    issue: entree.issue,
    tsIntention: entree.tsIntention,
    tsFinal: entree.tsFinal,
    empreinteAvant: entree.empreinteAvant,
    empreinteApres: entree.empreinteApres,
    chevaux: const <ChevalJournalise>[],
  );
}

// ───────────────────────────────────────────────────────────────────────────
//  LECTEURS STRICTS
//
//  Aucune valeur par défaut n'est inventée : un champ manquant est une
//  CORRUPTION, pas un cas nominal. Compléter silencieusement fabriquerait une
//  preuve.
// ───────────────────────────────────────────────────────────────────────────

/// Accès aux valeurs de `IssueEcritureElo` par leur nom, isolé pour que
/// `_enumStrict` reste générique.
class TypeEcritureElo {
  static const List<IssueEcritureElo> valuesCompat = IssueEcritureElo.values;
}

String _chaineStrict(Map<String, dynamic> json, String champ) {
  final v = json[champ];
  if (v is! String) {
    throw FormatException('$champ : chaîne attendue (reçu ${v.runtimeType})');
  }
  return v;
}

int _entierStrict(Map<String, dynamic> json, String champ) {
  final v = json[champ];
  if (v is int) return v;
  if (v is double && v == v.roundToDouble()) return v.toInt();
  throw FormatException('$champ : entier attendu (reçu ${v.runtimeType})');
}

double _reelStrict(Map<String, dynamic> json, String champ) {
  final v = json[champ];
  if (v is num) return v.toDouble();
  throw FormatException('$champ : nombre attendu (reçu ${v.runtimeType})');
}

Map<String, dynamic> _mapStrict(Map<String, dynamic> json, String champ) {
  final v = json[champ];
  if (v is! Map<String, dynamic>) {
    throw FormatException('$champ : objet attendu (reçu ${v.runtimeType})');
  }
  return v;
}

T _enumStrict<T extends Enum>(
    List<T> valeurs, Map<String, dynamic> json, String champ) {
  final nom = json[champ];
  if (nom is! String) {
    throw FormatException('$champ : chaîne attendue (reçu ${nom.runtimeType})');
  }
  return _valeurEnum(valeurs, nom, champ);
}

T _valeurEnum<T extends Enum>(List<T> valeurs, String nom, String champ) {
  for (final v in valeurs) {
    if (v.name == nom) return v;
  }
  throw FormatException('$champ : valeur inconnue "$nom"');
}

final RegExp _reEmpreinte = RegExp(r'^[0-9a-f]{16}$');

void _validerEmpreinte(String valeur, String champ) {
  if (!_reEmpreinte.hasMatch(valeur)) {
    throw FormatException('$champ : 16 caractères hexadécimaux attendus');
  }
}
