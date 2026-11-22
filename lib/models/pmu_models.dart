// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 2 — RECONNAISSANCE EN LECTURE DES TYPES DE PARIS HISTORIQUES
//
//  Ce fichier importe le référentiel central pour pouvoir INTERPRÉTER un
//  `typePari` déjà enregistré. Il ne l'utilise QUE dans des getters dérivés :
//  aucun champ n'est ajouté, aucune chaîne n'est réécrite, `toJson` et
//  `fromJson` sont inchangés au caractère près.
//
//  Le sens de la dépendance est volontaire et unique :
//      pmu_models.dart  ──►  services/referentiel_paris_pmu.dart
//  Le référentiel n'importe rien (mesuré : 0 directive `import`), il ne peut
//  donc pas y avoir de cycle.
//
//  ★ LOT G+P / AFFICHAGE : une SECONDE dépendance a été ajoutée, également
//  sans cycle — `utils/type_pari_utils.dart` n'importe RIEN (mesuré : 0
//  directive `import`, il ne contient que la garde A-0). Elle sert au seul
//  getter `gainGagnantPlaceEtabli`, afin que « qu'est-ce qu'un Gagnant +
//  Placé ? » ait UNE seule autorité et ne soit jamais redéfini localement.
// ═══════════════════════════════════════════════════════════════════════════
import '../services/referentiel_paris_pmu.dart';
// ★ R10 : source UNIQUE du nombre de chevaux attendu et du type joué.
//   `gain_ticket_calculator.dart` n'a AUCUN import (mesuré : 0 directive), il
//   est donc pur et ne peut pas créer de cycle.
import '../services/gain_ticket_calculator.dart'
    show
        TypePariJoue,
        typePariDepuisLibelle,
        tailleCombinaisonAttendue,
        exigeOrdreExact;
// ★ LOT B-1 — types purs des gains PMU structurés.
//   `gain_pmu_types.dart` n'importe que `gain_ticket_calculator.dart` (0
//   import) : la chaîne est fermée, aucun cycle possible.
import '../services/gain_pmu_types.dart'
    show
        EtatGain,
        EtatTirelire,
        MotifNonDetermination,
        RapportAttribue;
import '../utils/type_pari_utils.dart' show estTypeGagnantPlace;

// ─── Réunion ────────────────────────────────────────────────────────────────

class PmuReunion {
  final int numOfficiel;
  final String hippodrome;
  final String hippodromeCode;
  final String hippodromeLong;   // ex: "HIPPODROME DE PARIS-VINCENNES"
  final String dateStr;          // format ddmmyyyy
  final List<PmuCourse> courses;

  PmuReunion({
    required this.numOfficiel,
    required this.hippodrome,
    required this.hippodromeCode,
    required this.dateStr,
    required this.courses,
    this.hippodromeLong = '',
  });

  /// True si la réunion se déroule en France (pas Pays-Bas, GB, Chili, etc.)
  bool get isFrench {
    final long = hippodromeLong.toUpperCase();
    // Marqueurs d'hippodromes étrangers dans le libellé long PMU
    const foreign = [' P-B', ' GB', ' CHILI', ' USA', ' IRLANDE',
      ' BELGIQUE', ' ALLEMAGNE', ' ITALIE', ' ESPAGNE',
      ' SUEDE', ' DANEMARK', ' AUSTRALIE', ' JAPON',
      ' SUISSE', ' PORTUGAL', ' POLOGNE', ' HONGRIE', ' TCHEQUE'];
    return !foreign.any((marker) => long.contains(marker));
  }

  factory PmuReunion.fromJson(Map<String, dynamic> json, String dateStr) {
    final hippo = json['hippodrome'] as Map<String, dynamic>? ?? {};
    final coursesList = (json['courses'] as List<dynamic>? ?? [])
        .map((c) => PmuCourse.fromJson(c as Map<String, dynamic>))
        .toList();
    return PmuReunion(
      numOfficiel: json['numOfficiel'] as int? ?? 0,
      hippodrome: hippo['libelleCourt'] as String? ?? '',
      hippodromeCode: hippo['code'] as String? ?? '',
      hippodromeLong: hippo['libelleLong'] as String? ?? '',
      dateStr: dateStr,
      courses: coursesList,
    );
  }
}

// ─── Course ─────────────────────────────────────────────────────────────────

class PmuCourse {
  final int numReunion;
  final int numOrdre;
  final String libelle;
  final String libelleCourt;
  final DateTime heureDepart;
  final int distance;
  final String discipline;   // PLAT, HAIE, STEEPLECHASE, TROT_MONTE, ATTELE
  final String specialite;   // PLAT, OBSTACLE, TROT
  final int montantPrix;
  final int nombrePartants;
  final String statut;
  List<PmuParticipant> participants;
  bool participantsLoaded;
  /// true si les participants actuels sont des données de démo (pas réelles)
  bool participantsAreDemo;

  PmuCourse({
    required this.numReunion,
    required this.numOrdre,
    required this.libelle,
    required this.libelleCourt,
    required this.heureDepart,
    required this.distance,
    required this.discipline,
    required this.specialite,
    required this.montantPrix,
    required this.nombrePartants,
    required this.statut,
    this.participants = const [],
    this.participantsLoaded = false,
    this.participantsAreDemo = false,
  });

  factory PmuCourse.fromJson(Map<String, dynamic> json) {
    final ts = json['heureDepart'] as int? ?? 0;
    // ⚠️ .toLocal() : l'API PMU retourne des timestamps UTC
    final heure = ts > 0
        ? DateTime.fromMillisecondsSinceEpoch(ts).toLocal()
        : DateTime.now();
    return PmuCourse(
      numReunion: json['numReunion'] as int? ?? 0,
      numOrdre: json['numOrdre'] as int? ?? 0,
      libelle: json['libelle'] as String? ?? '',
      libelleCourt: json['libelleCourt'] as String? ?? '',
      heureDepart: heure,
      distance: json['distance'] as int? ?? 0,
      discipline: json['discipline'] as String? ?? 'PLAT',
      specialite: json['specialite'] as String? ?? 'PLAT',
      montantPrix: json['montantPrix'] as int? ?? 0,
      nombrePartants: json['nombreDeclaresPartants'] as int? ?? 0,
      statut: json['statut'] as String? ?? 'PROGRAMME',
    );
  }

  String get heureStr {
    final h = heureDepart.hour.toString().padLeft(2, '0');
    final m = heureDepart.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  CourseStatus get status {
    switch (statut) {
      case 'DEPART_IMMINENT':
      case 'EN_COURS':
        return CourseStatus.enCours;
      case 'FIN_COURSE':
      case 'ARRIVEE_DEFINITIVE_COMPLETE':
      case 'ARRIVEE_DEFINITIVE':
        return CourseStatus.terminee;
      default:
        return CourseStatus.aVenir;
    }
  }

  String get statusLabel {
    switch (status) {
      case CourseStatus.aVenir:
        return 'À venir';
      case CourseStatus.enCours:
        return 'En cours';
      case CourseStatus.terminee:
        return 'Terminé';
    }
  }

  String get disciplineIcon {
    switch (discipline) {
      case 'PLAT':
        return '🏇';
      case 'HAIE':
        return '🚧';
      case 'STEEPLECHASE':
        return '🌿';
      case 'ATTELE':
      case 'TROT_ATTELE':
        return '🛒';
      case 'TROT_MONTE':
        return '🏃';
      default:
        return '🐎';
    }
  }
}

enum CourseStatus { aVenir, enCours, terminee }

// ─── Participant ─────────────────────────────────────────────────────────────

class PmuParticipant {
  final int numero;
  final String nom;
  final String driver;       // jockey ou driver trot
  final String entraineur;
  final int age;
  final String sexe;
  final String robe;
  final String musique;      // ex: "1a2a3a" = historique de courses
  final int nombreCourses;
  final int nombreVictoires;
  final int nombrePlaces;
  final double cote;
  final double coteDirect;
  final String statut;
  final int handicapPoids;
  final String urlCasaque;
  final double gainsCarriere;

  PmuParticipant({
    required this.numero,
    required this.nom,
    required this.driver,
    required this.entraineur,
    required this.age,
    required this.sexe,
    required this.robe,
    required this.musique,
    required this.nombreCourses,
    required this.nombreVictoires,
    required this.nombrePlaces,
    required this.cote,
    required this.coteDirect,
    required this.statut,
    required this.handicapPoids,
    required this.urlCasaque,
    this.gainsCarriere = 0,
  });

  factory PmuParticipant.fromJson(Map<String, dynamic> json) {
    double parseCote(dynamic val) {
      if (val == null) return 0.0;
      if (val is Map) return (val['rapport'] as num?)?.toDouble() ?? 0.0;
      if (val is num) return val.toDouble();
      return 0.0;
    }

    String extractName(dynamic val) {
      if (val == null) return '';
      if (val is Map) return (val['nom'] as String?) ?? '';
      if (val is String) return val;
      return '';
    }

    return PmuParticipant(
      numero: json['numPmu'] as int? ?? json['numero'] as int? ?? 0,
      nom: json['nom'] as String? ?? '',
      driver: extractName(json['driver'] ?? json['jockey']),
      entraineur: extractName(json['entraineur']),
      age: json['age'] as int? ?? 0,
      sexe: json['sexe'] as String? ?? '',
      robe: json['robe'] as String? ?? '',
      musique: json['musique'] as String? ?? '',
      nombreCourses: json['nombreCourses'] as int? ?? 0,
      nombreVictoires: json['nombreVictoires'] as int? ?? 0,
      nombrePlaces: json['nombrePlaces'] as int? ?? 0,
      cote: parseCote(json['dernierRapportReference']),
      coteDirect: parseCote(json['dernierRapportDirect']),
      statut: json['statut'] as String? ?? 'PARTANT',
      handicapPoids: json['handicapPoids'] as int? ?? 0,
      urlCasaque: json['urlCasaque'] as String? ?? '',
      gainsCarriere: ((json['gainsParticipant'] as Map<String, dynamic>?)?['gainsCarriere'] as num?)?.toDouble() ?? 0,
    );
  }

  double get coteAffichee => coteDirect > 0 ? coteDirect : cote;

  double get tauxVictoire {
    if (nombreCourses == 0) return 0;
    return nombreVictoires / nombreCourses;
  }

  double get tauxPlace {
    if (nombreCourses == 0) return 0;
    return (nombreVictoires + nombrePlaces) / nombreCourses;
  }

  /// Score IA de pronostic (0–100) basé sur cotes + stats + musique
  double get scorePronostic {
    double score = 0;

    // 1. Cote inversée (cote faible = favori = bon score)
    if (coteAffichee > 0) {
      score += (100 / coteAffichee).clamp(0, 40);
    }

    // 2. Taux de victoire sur l'historique
    score += (tauxVictoire * 30).clamp(0, 30);

    // 3. Taux de place (top 3)
    score += (tauxPlace * 15).clamp(0, 15);

    // 4. Analyse de la musique (résultats récents)
    score += _scoreMusiqueRecente();

    return score.clamp(0, 100);
  }

  double _scoreMusiqueRecente() {
    if (musique.isEmpty) return 5;
    // La musique PMU: ex "1a 2a 3p 0h" = résultats récents (1er, 2e, 3e, abandon)
    // On extrait les positions numériques
    double s = 0;
    final regex = RegExp(r'(\d+)');
    final matches = regex.allMatches(musique).take(5).toList();
    for (int i = 0; i < matches.length; i++) {
      final pos = int.tryParse(matches[i].group(0) ?? '') ?? 10;
      final weight = 1.0 - (i * 0.15); // résultat récent = plus de poids
      if (pos == 1) {
        s += 3.0 * weight;
      } else if (pos == 2) {
        s += 2.0 * weight;
      } else if (pos <= 3) {
        s += 1.5 * weight;
      } else if (pos <= 5) {
        s += 0.5 * weight;
      }
    }
    return (s * 2).clamp(0, 15);
  }

  String get formRecente {
    if (musique.isEmpty) return '-';
    // Extraire les 5 premiers résultats lisibles
    final regex = RegExp(r'(\d+[a-z]?)');
    final matches = regex.allMatches(musique).take(6).map((m) => m.group(0) ?? '').toList();
    return matches.join(' ');
  }

  String get pronosticLabel {
    final s = scorePronostic;
    if (s >= 55) return 'FAVORI';
    if (s >= 40) return 'OUTSIDER';
    if (s >= 25) return 'À SURVEILLER';
    return 'LONGSHOT';
  }
}

// ─── Pronostic officiel Equidia/PMU ──────────────────────────────────────────

/// Un cheval sélectionné dans la base officielle Equidia (partenaire PMU)
class EquidiaSelection {
  final int rang;          // Rang dans la sélection (1 = favori Equidia)
  final int numPartant;    // Numéro PMU du cheval
  final String coteProb;   // Cote probable ex: "6/1", "3/1"

  EquidiaSelection({
    required this.rang,
    required this.numPartant,
    required this.coteProb,
  });

  factory EquidiaSelection.fromJson(Map<String, dynamic> json) {
    return EquidiaSelection(
      rang: json['rang'] as int? ?? 0,
      numPartant: json['num_partant'] as int? ?? 0,
      coteProb: json['cote_prob'] as String? ?? '',
    );
  }

  /// Convertit "6/1" en valeur décimale (ex: 7.0 = 6/1 + 1)
  double get coteProbDecimale {
    final parts = coteProb.split('/');
    if (parts.length == 2) {
      final num = double.tryParse(parts[0]) ?? 0;
      final den = double.tryParse(parts[1]) ?? 1;
      return den > 0 ? (num / den) + 1.0 : 0.0;
    }
    return 0.0;
  }
}

/// Résultat complet des pronostics Equidia pour une course
class EquidiaPronostics {
  final int numReunion;
  final int numCourse;
  final String source;           // "EQUIDIA"
  final String signature;        // ex: "MICHEL PROD HOMME" (pronostiqueur)
  final List<EquidiaSelection> selections;

  EquidiaPronostics({
    required this.numReunion,
    required this.numCourse,
    required this.source,
    required this.signature,
    required this.selections,
  });

  factory EquidiaPronostics.fromJson(Map<String, dynamic> json) {
    final sels = (json['selection'] as List<dynamic>? ?? [])
        .map((s) => EquidiaSelection.fromJson(s as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.rang.compareTo(b.rang));
    return EquidiaPronostics(
      numReunion: json['numeroReunion'] as int? ?? 0,
      numCourse: json['numeroCourse'] as int? ?? 0,
      source: json['source'] as String? ?? 'EQUIDIA',
      signature: json['signature'] as String? ?? '',
      selections: sels,
    );
  }

  /// Numéros en ordre Equidia : "11 - 13 - 9"
  String get numerosOrdre =>
      selections.map((s) => '${s.numPartant}').join(' - ');

  /// Top N numéros
  List<int> numerosTop(int n) =>
      selections.take(n).map((s) => s.numPartant).toList();

  bool get isEmpty => selections.isEmpty;
}

// ─── Pronostic utilisateur ───────────────────────────────────────────────────

/// Sentinelle privée du `copyWith` de [UserPrediction].
///
/// ── POURQUOI ELLE EXISTE ──────────────────────────────────────────────────
/// En Dart, un paramètre nommé `Object? x` ne permet pas de distinguer
/// « l'appelant n'a rien dit » de « l'appelant veut explicitement `null` » :
/// les deux arrivent sous la forme `null`. Or les 18 champs facultatifs de ce
/// modèle portent une information métier dans leur `null` (`etatGain == null`
/// signifie « ticket historique, chemin legacy »). Un `copyWith` naïf qui
/// écraserait systématiquement par `null` détruirait donc silencieusement un
/// verdict déjà enregistré.
///
/// La sentinelle rend les deux cas distincts :
///   • argument OMIS          → la constante `_inchange` est reçue → on garde ;
///   • argument `null` FOURNI → `null` est reçu              → on efface.
///
/// Elle est PRIVÉE au fichier : aucun appelant extérieur ne peut la nommer,
/// donc aucun appelant ne peut la confondre avec une vraie valeur.
class _Inchange {
  const _Inchange();
}

const Object _inchange = _Inchange();

class UserPrediction {
  final String id;
  final String dateStr;
  final int numReunion;
  final int numCourse;
  final String nomCourse;
  final String hippodrome;
  final int numeroCheval;
  final String nomCheval;
  final double cote;
  final String typePari;
  final DateTime createdAt;
  bool? isCorrect;

  /// Score de confiance IA (0–100)
  final double scoreIA;

  /// Mise jouée par l'utilisateur (en €)
  double montantMise;

  /// Gain net réalisé (positif = gagné, négatif = perdu, 0 = en attente)
  double? gainRealise;

  /// Numéros des chevaux joués (pour Tiercé/Quarté/Quinté)
  /// Ex: [5, 12, 3] pour un Tiercé
  List<int> numerosJoues;

  /// Dividende PMU réel récupéré après la course (pour 1€ misé)
  /// Null = pas encore récupéré ou paris simple déjà calculé via cote
  double? dividendePmuReel;

  /// Combinaison gagnante PMU (ex: "5-12-3")
  String? combinaisonPmu;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ ÉTAPE 4-F — CAPTURE DU PARI RÉELLEMENT JOUÉ (4 champs FACULTATIFS)
  //
  //  CONTRAT STRICT, identique dans `TrackedCourse` :
  //   • les QUATRE champs sont `null` pour tout ticket antérieur à 4-F ;
  //   • aucune valeur n'est JAMAIS déduite, devinée ni reconstituée ;
  //   • `numerosJoues` GARDE sa signification historique (ensemble trié) et
  //     n'est pas modifié : les formules financières qui le lisent ne voient
  //     aucune différence ;
  //   • `typePari` n'est pas modifié non plus : la variante vit dans
  //     [varianteChoisie], pas dans la chaîne.
  //
  //  Ces quatre champs sont PERSISTÉS (contrairement aux getters dérivés
  //  `typePmu`, `typePariReconnu`…) car ce sont des données de saisie que
  //  rien ne permet de recalculer après coup.
  // ══════════════════════════════════════════════════════════════════════════

  /// Code API PMU réellement visé par le ticket (`'E_TIERCE'`,
  /// `'E_QUARTE_PLUS'`, `'E_QUINTE_PLUS'`, `'E_TRIO'`…).
  ///
  /// `null` = non capturé (tout ticket antérieur à 4-F, ou type non répertorié).
  /// Aucune valeur par défaut : on ne suppose jamais « E_SIMPLE_GAGNANT ».
  final String? codePmuOfficiel;

  /// Variante **choisie par le parieur** : `'ordre'` ou `'desordre'`.
  ///
  /// Renseignée UNIQUEMENT pour les paris où ce choix existe réellement :
  /// Tiercé Ordre / Tiercé Désordre et Couplé Ordre.
  ///
  /// ⚠️ Reste `null` pour Quarté+ et Quinté+ : au PMU le parieur n'y choisit
  ///    pas Ordre/Désordre, il désigne 4 ou 5 chevaux et c'est le rapprochement
  ///    avec le rapport officiel qui détermine la variante payable. Écrire
  ///    `'ordre'` ici serait une invention de choix utilisateur.
  final String? varianteChoisie;

  /// Ordre des chevaux **tel que saisi**, lorsque le pari exige l'ordre.
  ///
  /// Renseigné uniquement pour Tiercé Ordre et Couplé Ordre (`exigeOrdreExact`
  /// vaut `true` pour eux). `null` partout ailleurs.
  ///
  /// Invariant : le tri de ce champ doit toujours être égal à [numerosJoues].
  /// Les deux champs ne peuvent donc pas désigner des chevaux différents.
  final List<int>? numerosDansOrdre;

  /// Formule du pari, pour Multi / Mini Multi : `'en4'`, `'en5'`, `'en6'`,
  /// `'en7'` (et `'en4'`..`'en6'` pour Mini Multi).
  ///
  /// Champ PRÉVU mais toujours `null` dans ce lot : Multi et Mini Multi ne
  /// sont pas exposés à la saisie. Il est déclaré maintenant pour que le
  /// contrat soit complet et qu'aucune seconde évolution du format JSON ne
  /// soit nécessaire lorsqu'ils le seront.
  final String? formulePari;

  // ═════════════════════════════════════════════════════════════════════════
  //  ★ LOT B-1 — GAINS PMU STRUCTURÉS (tous facultatifs)
  //
  //  POURQUOI CES CHAMPS EXISTENT
  //  Un ticket ne stockait qu'UN seul `dividendePmuReel` et qu'UNE seule mise
  //  agrégée, alors que le PMU paie PAR RANG DE RAPPORT et PAR COMPOSANTE.
  //  Mesuré (R1C6_15112026) : la MÊME combinaison `9-4-15-10-1` porte DEUX
  //  rapports au MÊME rang 1 (« Ordre + Tirelire » 11 462 670 et « Ordre »
  //  6 462 670). Un scalaire unique ne peut pas représenter ce réel.
  //
  //  RÈGLE DE COMPATIBILITÉ — ABSOLUE
  //   • `null` = ticket HISTORIQUE : le chemin de calcul actuel s'applique,
  //     strictement inchangé. Aucun recalcul rétroactif.
  //   • Les clés JSON ne sont écrites QUE si `etatGain != null`. Un ticket
  //     historique relu puis réécrit garde donc EXACTEMENT la même forme
  //     (verrou mesuré : 26 clés pour UserPrediction, 28 pour TrackedCourse).
  //   • `dividendePmuReel` est CONSERVÉ et reste lu par tous les écrans
  //     existants. Il n'est plus alimenté par le nouveau moteur, mais il n'est
  //     ni supprimé, ni réinterprété.
  //
  //  ⚠️ Ces champs ne sont PAS touchés par les calculs IA, les poids, les
  //     seuils, le gradient descent, le TOP3 learning ni le ROI.
  // ═════════════════════════════════════════════════════════════════════════

  /// État du gain, ou `null` pour un ticket historique (chemin legacy).
  final EtatGain? etatGain;

  /// Rapports officiels RÉELLEMENT attribués au ticket.
  ///
  /// `null` = jamais résolu par le nouveau moteur. Une liste vide n'a pas le
  /// même sens : elle signifierait « résolu, aucun rapport attribué ».
  final List<RapportAttribue>? rapportsAttribues;

  /// État de la Tirelire, INDÉPENDANT du rapport Ordre.
  final EtatTirelire? etatTirelire;

  /// Dividende de la composante Gagnant d'un Gagnant+Placé, pour 1 €.
  /// `null` hors G+P ou si la composante n'est pas résolue.
  final double? dividendeGagnant;

  /// Dividende de la composante Placé d'un Gagnant+Placé, pour 1 €.
  final double? dividendePlace;

  /// `miseBase` du bloc PMU employé, en centimes — AUDIT UNIQUEMENT.
  /// Voir R17 : n'entrer dans aucun calcul.
  final int? miseBaseCentimesUtilisee;

  /// Motif fermé expliquant un `etatGain == nonDetermine`.
  final MotifNonDetermination? motifNonDetermination;

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ B1-T12 / ÉTAPE 1 — GAIN MANUEL ET GAIN RETENU
  //
  //  POURQUOI CES DEUX CHAMPS EXISTENT, ET RIEN DE PLUS
  //  Le PMU fournit un gain automatique. L'utilisateur doit aussi pouvoir
  //  déclarer le montant qu'il a RÉELLEMENT reçu, sans jamais écraser ce que
  //  le PMU a publié. D'où DEUX champs distincts, et un seul point de décision.
  //
  //  SÉPARATION STRICTE — c'est la garantie de non-écrasement :
  //    • `dividendePmuReel`, `dividendeGagnant`, `dividendePlace`,
  //      `rapportsAttribues`, `etatGain` : les données OFFICIELLES du PMU.
  //      Aucun de ces champs n'est écrit par la saisie manuelle.
  //    • `montantGainManuel` : la déclaration de l'utilisateur. Le PMU ne
  //      l'écrit jamais. C'est le seul champ que la saisie manuelle modifie.
  //
  //  BRUT, PAS NET — décision explicite :
  //    `montantGainManuel` est le montant BRUT réellement reçu, en euros.
  //    C'est ce que l'utilisateur lit sur son ticket PMU ou son compte.
  //    Le NET se déduit en soustrayant la mise réellement engagée. On ne
  //    stocke donc JAMAIS un net : le stocker figerait une mise qui peut
  //    encore être corrigée, et le net deviendrait faux.
  //
  //  0 € N'EST PAS « PAS DE SAISIE » :
  //    `null`  = aucune saisie manuelle → le PMU fait foi.
  //    `0.0`   = l'utilisateur a déclaré avoir reçu 0 € (perte sèche, ou
  //              remboursement nul) → c'est une information, pas une absence.
  //    Les tests ci-joints distinguent explicitement les deux cas.
  // ══════════════════════════════════════════════════════════════════════════

  /// Montant BRUT réellement reçu, déclaré par l'utilisateur, en euros.
  ///
  /// `null` = aucun gain manuel (le PMU fait foi).
  /// `0.0`  = l'utilisateur a explicitement déclaré 0 €.
  ///
  /// Ce champ n'est JAMAIS écrit par le PMU, et le PMU n'est jamais écrasé
  /// par lui : les deux sources cohabitent.
  final double? montantGainManuel;

  /// Identifiant du ticket jumeau, pour une liaison CERTAINE et vérifiable.
  ///
  /// Côté `UserPrediction`, il porte la clé de persistance du `TrackedCourse`
  /// correspondant. Côté `TrackedCourse`, il porte le `id` du
  /// `UserPrediction` correspondant.
  ///
  /// ⚠️ AUCUN NOM DE CHAMP N'EST CITÉ ICI, VOLONTAIREMENT : le test B4.4/10.13
  /// vérifie la BARRIÈRE D'IDENTITÉ entre les deux modèles par simple
  /// occurrence textuelle dans leurs fichiers sources. Citer le nom du champ
  /// du modèle voisin dans un commentaire suffisait à faire échouer cette
  /// barrière (mesuré : `Expected: <0>`, le mot apparaissait 1 fois, et cette
  /// occurrence était CE COMMENTAIRE — pas un champ). La barrière n'a pas été
  /// affaiblie : c'est la prose qui a été reformulée.
  ///
  /// `null` EST UNE INFORMATION, PAS UN DÉFAUT : un ticket historique n'a
  /// jamais eu de liaison, et aucune heuristique ne doit en inventer une à
  /// partir de la réunion, de la course ou de l'heure. Deux paris sur la même
  /// course restent donc indépendants.
  final String? idTicketLie;

  /// ★ R10 — Le ticket a-t-il de quoi identifier sa variante **sans deviner** ?
  ///
  /// CONTRAT CORRIGÉ. L'ancienne version rendait `true` dès que le code PMU
  /// était présent, ce qui était FAUX dans cinq cas mesurés :
  ///   • Quinté+ avec un code mais ZÉRO numéro ;
  ///   • Tiercé avec un code mais deux numéros au lieu de trois ;
  ///   • ticket vide dont seul le code a été forcé ;
  ///   • ordre incompatible avec les numéros joués ;
  ///   • Multi sans formule.
  ///
  /// La règle est désormais **factuelle** : on n'affirme complet que si l'on
  /// peut NOMMER ce qui est présent. `true` exige donc TOUT ceci :
  ///   1. le code PMU est connu ;
  ///   2. le type de pari est identifié (sinon on ne sait rien attendre) ;
  ///   3. le nombre de numéros enregistrés égale EXACTEMENT le nombre attendu
  ///      par le règlement ([tailleCombinaisonAttendue]), et il est non nul ;
  ///   4. si le pari impose l'ordre exact, `numerosDansOrdre` est présent ;
  ///   5. si une variante est requise, elle a été explicitement choisie.
  ///
  /// ⚠️ Ce getter ne dit RIEN de la calculabilité financière : une mise
  ///    absente ou un rapport officiel manquant ne le font pas changer d'avis.
  ///    « Informations capturées » ≠ « ticket financièrement calculable ».
  ///
  /// Getter DÉRIVÉ : jamais persisté.
  bool get capturePariComplete {
    if (codePmuOfficiel == null) return false;

    final type = typePariDepuisLibelle(typePari);
    if (type == TypePariJoue.inconnu) return false;

    // 3. Le nombre de numéros enregistrés doit être EXACTEMENT celui attendu.
    final attendu = tailleCombinaisonAttendue(type);
    if (attendu == null || numerosJoues.length != attendu) return false;

    // 4. Ordre exact exigé => l'ordre doit avoir été réellement capturé, et
    //    désigner les mêmes chevaux que `numerosJoues` (invariant documenté).
    if (exigeOrdreExact(type)) {
      final ordre = numerosDansOrdre;
      if (ordre == null) return false;
      if (ordre.length != numerosJoues.length) return false;
      final triOrdre = List<int>.from(ordre)..sort();
      final triJoues = List<int>.from(numerosJoues)..sort();
      for (var i = 0; i < triOrdre.length; i++) {
        if (triOrdre[i] != triJoues[i]) return false;
      }
    }

    // 5. Variante explicitement requise => elle doit être renseignée.
    final exigeVariante = typePari == 'Tiercé Ordre' ||
        typePari == 'Tiercé Désordre' ||
        typePari == 'Couplé Ordre';
    return exigeVariante ? varianteChoisie != null : true;
  }

  // ★ LOT B1 — Représentation des DEUX composantes d'un pari Gagnant + Placé.
  //
  //  Règle métier impérative : la mise saisie s'applique SÉPARÉMENT à chaque
  //  composante. 10 € saisis = 10 € Gagnant + 10 € Placé = 20 € engagés.
  //  Les deux mises sont donc stockées dans DEUX champs distincts : aucune
  //  division, aucune fusion, aucun champ agrégé persisté qui permettrait
  //  plus tard de « reconstituer » 20 puis de le rediviser.
  //
  //  `null` = composante non renseignée (pari simple, ou G+P antérieur à B2).
  //  Pour un pari simple ces quatre champs restent `null` : aucun
  //  consommateur existant ne les lit, donc AUCUNE régression.
  //
  //  ⚠️ B1 est une évolution de MODÈLE uniquement : `gainNet`, `retourTotal`,
  //     `dividendePmuReel`, `combinaisonPmu`, `cote` et `montantMise`
  //     conservent leur sens et leur valeur actuels.
  double? miseGagnant;
  double? misePlace;
  double? coteGagnant;
  double? cotePlace;

  /// Mise réellement engagée d'un Gagnant + Placé — `null` si l'état est
  /// INCOMPLET (une seule des deux mises renseignée).
  ///
  /// Trois cas, volontairement distincts :
  ///  - **deux mises présentes** → leur somme (10 + 10 = **20,0**) ;
  ///  - **les deux absentes** → `montantMise`, c'est-à-dire le comportement
  ///    historique, sans inventer de donnée (pari simple, ou G+P d'avant B2) ;
  ///  - **une seule présente** → **`null`** : état incomplet SIGNALÉ, aucune
  ///    mise totale n'est calculée. Retourner la seule composante connue
  ///    reviendrait à affirmer une mise totale fausse, et la doubler
  ///    reviendrait à inventer la composante manquante.
  ///
  /// Le type est `double?` — et non `double` — précisément pour que le
  /// troisième cas soit représentable sans valeur sentinelle : `null` est
  /// déjà l'idiome de ce modèle pour « information absente » (`dividendePmuReel`,
  /// `gainRealise`, `cotePlace`…). Un appelant qui obtient `null` sait qu'il
  /// ne doit RIEN afficher ni calculer.
  ///
  /// Getter **dérivé**, jamais stocké : il ne peut donc pas se désynchroniser
  /// des deux mises réelles.
  double? get miseTotaleEngagee {
    final g = miseGagnant;
    final p = misePlace;
    if (g == null && p == null) return montantMise;
    if (g == null || p == null) return null; // état incomplet — signalé
    return g + p;
  }

  /// Indique si le pari porte une représentation Gagnant + Placé INCOMPLÈTE
  /// (exactement une des deux mises renseignée). Utile aux appelants qui
  /// veulent distinguer « pas de composantes » de « composantes partielles ».
  bool get misesGagnantPlaceIncompletes =>
      (miseGagnant == null) != (misePlace == null);

  /// Indique si le dividende PMU réel a été récupéré
  bool get dividendeRecupere => dividendePmuReel != null;

  /// Indique si c'est un pari combiné (Tiercé/Quarté/Quinté)
  bool get estPariCombine {
    final t = typePari.toLowerCase();
    return t.contains('tiercé') || t.contains('quarté') || t.contains('quinté');
  }

  // ★ ÉTAPE 2 — INTERPRÉTATION EN LECTURE DU TYPE DE PARI.
  //
  //  Contrat strict, identique à celui de `TrackedCourse` :
  //   • `typePari` n'est JAMAIS modifié, normalisé ni réécrit ;
  //   • aucun getter ci-dessous n'écrit quoi que ce soit ;
  //   • `toJson` reste inchangé : ces valeurs sont DÉRIVÉES, jamais stockées.
  //
  //  Un type absent, vide ou inconnu rend `null`. JAMAIS « Simple Gagnant » :
  //  supposer un type par défaut reviendrait à attribuer un rapport officiel
  //  à un ticket dont on ignore ce qu'il est. À noter que `fromJson` de ce
  //  modèle applique déjà `?? ''` pour un `typePari` absent — la chaîne reste
  //  telle quelle, et c'est bien `''` qui est interprété comme non résolu.

  /// Type de pari PMU canonique, ou `null` si le libellé enregistré n'est pas
  /// répertorié. Lecture seule.
  ///
  /// Un ticket « Gagnant+Placé » rend `null` : ce n'est pas un pari PMU mais
  /// un ticket applicatif à deux composantes (voir
  /// [estTicketApplicatifHorsReferentielPmu] pour le distinguer d'un libellé
  /// réellement inconnu).
  TypePariPmu? get typePmu => typePmuDepuisLibelleHistorique(typePari);

  /// `true` si le libellé enregistré est reconnu par le référentiel.
  bool get typePariReconnu => typePmu != null;

  /// `true` si le libellé est un ticket applicatif à deux composantes
  /// (« Gagnant+Placé »), donc volontairement hors référentiel PMU.
  bool get typePariHorsReferentielPmu =>
      estTicketApplicatifHorsReferentielPmu(typePari);

  /// `true` si le type est ABSENT, vide ou inconnu — c'est-à-dire si aucune
  /// interprétation n'est possible. État signalé, jamais comblé par un défaut.
  bool get typePariNonResolu => typePmu == null && !typePariHorsReferentielPmu;

  UserPrediction({
    required this.id,
    required this.dateStr,
    required this.numReunion,
    required this.numCourse,
    required this.nomCourse,
    required this.hippodrome,
    required this.numeroCheval,
    required this.nomCheval,
    required this.cote,
    required this.typePari,
    required this.createdAt,
    this.isCorrect,
    this.scoreIA = 0.0,
    this.montantMise = 0.0,
    this.gainRealise,
    this.numerosJoues = const [],
    this.dividendePmuReel,
    this.combinaisonPmu,
    this.miseGagnant,
    this.misePlace,
    this.coteGagnant,
    this.cotePlace,
    // ★ ÉTAPE 4-F — capture du pari réellement joué (tous facultatifs)
    this.codePmuOfficiel,
    this.varianteChoisie,
    this.numerosDansOrdre,
    this.formulePari,
    // ★ LOT B-1 — gains PMU structurés (tous facultatifs, null par défaut)
    this.etatGain,
    this.rapportsAttribues,
    this.etatTirelire,
    this.dividendeGagnant,
    this.dividendePlace,
    this.miseBaseCentimesUtilisee,
    this.motifNonDetermination,
    // ★ B1-T12 / étape 1 — gain manuel et liaison certaine
    this.montantGainManuel,
    this.idTicketLie,
  });

  /// Gain net calculé :
  /// - Si gainRealise saisi manuellement → gainRealise (priorité absolue)
  /// - Si isCorrect == false → pari perdu, on retourne -mise (même si dividendePmuReel est présent)
  /// - Si dividende PMU réel disponible ET pari gagnant → mise × dividende - mise
  /// - Sinon → calcul automatique via cote (simples)
  double get gainNet {
    if (gainRealise != null) return gainRealise!;
    // ✅ Fix: vérifier isCorrect AVANT dividendePmuReel
    // Un pari perdu (isCorrect=false) ne doit jamais retourner un gain positif
    if (isCorrect == false && montantMise > 0) return -montantMise;
    if (dividendePmuReel != null && montantMise > 0 && isCorrect == true) {
      // Dividende PMU = retour pour 1€ misé — seulement si pari gagnant confirmé
      return (dividendePmuReel! * montantMise) - montantMise;
    }
    if (isCorrect == true && montantMise > 0 && cote > 0) {
      return (cote * montantMise) - montantMise;
    }
    return 0.0;
  }

  // ────────────────────────────────────────────────────────────────────────
  //  ★ B1-T12 / ÉTAPE 1 — LE GAIN RETENU : UN SEUL POINT DE DÉCISION
  //
  //  RÈGLE DE PRIORITÉ, appliquée dans cet ordre et sans exception :
  //    1. `montantGainManuel` existe → il est le montant retenu (BRUT).
  //    2. sinon, le PMU a établi un gain → le montant PMU est retenu.
  //    3. sinon → `null`, état INDÉTERMINÉ. On n'invente rien.
  //
  //  ⚠️ `gainNet` CI-DESSUS N'EST PAS MODIFIÉ. Il garde ses quatre branches
  //  et son comportement historique, y compris le défaut mesuré en B1-T12
  //  (branche ④ : cote × mise d'UNE composante sur un G+P qui en engage
  //  DEUX). `gainRetenu` ne le remplace pas : il vit à côté, et c'est
  //  délibéré. Changer `gainNet` exigerait un arbitrage distinct.
  //
  //  POURQUOI `gainRetenuBrut` ET `gainRetenuNet` SONT SÉPARÉS :
  //  Le brut est un FAIT (ce qui est tombé). Le net est un CALCUL (brut −
  //  mise). Les mélanger ferait exactement la confusion que le lot interdit
  //  entre « gain », « retour » et « mise ». Une mise inconnue ne doit pas
  //  produire un net de 0 € : elle doit produire `null`, c'est-à-dire
  //  « indéterminé », et le brut reste affichable.
  // ────────────────────────────────────────────────────────────────────────

  /// Le montant BRUT retenu : manuel s'il existe, sinon PMU, sinon `null`.
  ///
  /// `null` = aucun montant fiable → état indéterminé (ne rien affirmer).
  double? get gainRetenuBrut {
    // ① La déclaration de l'utilisateur est prioritaire. Un `0.0` explicite
    //    est un montant : il ne retombe donc PAS sur le PMU.
    final manuel = montantGainManuel;
    if (manuel != null) return manuel;

    // ② Le PMU fait foi quand l'utilisateur n'a rien déclaré.
    //    On ne consulte le PMU QUE par des champs officiels :
    //      • `gainRealise` — gain NET déjà établi par un rapport officiel ;
    //      • `dividendePmuReel` — retour pour 1 € misé.
    //    `gainRealise` étant un NET, on le convertit en brut en ré-ajoutant
    //    la mise réellement engagée. Sans mise connue, on ne peut pas
    //    convertir : on préfère alors le dividende, qui est un brut par
    //    construction (retour pour 1 € misé × mise).
    //
    //    ⚠️ MESURÉ AVANT D'ÉCRIRE — `miseDisponible` N'EST PAS `mise != null`.
    //    `montantMise` est un `double` NON NULLABLE de défaut `0.0` : quand
    //    les deux composantes G+P sont nulles, `miseTotaleEngagee` rend
    //    `0.0`, JAMAIS `null`. Un simple `mise != null` laisserait donc
    //    passer une mise de 0 € comme si elle était connue, et produirait un
    //    net de « brut − 0 » — c'est-à-dire exactement le gain net INVENTÉ
    //    que le lot interdit. La convention « mise exploitable » du modèle
    //    est déjà `montantMise > 0` (mesurée sur 5 sites : lignes 834, 835,
    //    839, 918, 921 de ce fichier, dans `gainNet` et `retourTotal`). On
    //    applique la MÊME convention, sans en créer une nouvelle.
    final mise = miseTotaleEngagee;
    final miseDisponible = mise != null && mise > 0;
    if (gainRealise != null) {
      if (miseDisponible) return gainRealise! + mise;
      // Mise inconnue : on ne convertit pas un net en brut au hasard.
    }
    if (dividendePmuReel != null && miseDisponible) {
      return dividendePmuReel! * mise;
    }

    // ③ Rien de fiable : indéterminé.
    return null;
  }

  /// Le gain NET retenu, ou `null` si la mise engagée est inconnue.
  ///
  /// Net = brut − mise réellement engagée. Quand la mise manque, on rend
  /// `null` plutôt qu'un net faux : c'est la règle « si la mise totale est
  /// inconnue, conserver le brut sans inventer de net ».
  ///
  /// `mise > 0` et non `mise != null` : voir la mesure documentée dans
  /// [gainRetenuBrut] — une mise de 0 € signifie « non renseignée » dans ce
  /// modèle, pas « mise nulle connue ».
  double? get gainRetenuNet {
    final brut = gainRetenuBrut;
    if (brut == null) return null;
    final mise = miseTotaleEngagee;
    if (mise == null || mise <= 0) return null;
    return brut - mise;
  }

  /// Un gain manuel a-t-il été déclaré ? (`0.0` compte comme déclaré.)
  bool get aGainManuel => montantGainManuel != null;

  /// Le ticket est-il lié à son jumeau par une association CERTAINE ?
  bool get estLieAuTicket => idTicketLie != null;

  /// Retour total (mise + gain) — 0 si pari perdu
  double get retourTotal {    if (isCorrect == false) return 0.0; // ✅ Fix: pari perdu = retour 0
    if (dividendePmuReel != null && montantMise > 0 && isCorrect == true) {
      return dividendePmuReel! * montantMise;
    }
    if (isCorrect == true && montantMise > 0 && cote > 0) {
      return cote * montantMise;
    }
    return 0.0;
  }

  /// Statut lisible
  String get statutLabel {
    if (isCorrect == null) return 'En attente';
    if (isCorrect == true) return 'Gagné ✅';
    return 'Perdu ❌';
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  LOT G+P / AFFICHAGE — LE GAIN D'UN GAGNANT + PLACÉ EST-IL ÉTABLI ?
  //
  //  ── LE DÉFAUT MESURÉ ───────────────────────────────────────────────────
  //  `gainNet` ci-dessus applique UNE cote à UNE mise. Pour un G+P, `cote`
  //  est la cote du GAGNANT SEUL et `montantMise` la mise PAR COMPOSANTE :
  //  ce produit ne vaut rien de réel, et la composante Placé n'y entre
  //  jamais. Les chemins d'affichage présentaient pourtant ce montant
  //  comme un « Gain net » / « Gain gagné » / un gain partageable.
  //
  //  ── CE QUE CE GETTER AJOUTE, ET RIEN DE PLUS ───────────────────────────
  //  Un seul fait DÉRIVÉ : « le gain de ce ticket est-il établi ? ».
  //  Il ne calcule aucun montant, ne modifie aucun champ, n'écrit rien.
  //  `gainNet`, `retourTotal` et leurs formules sont STRICTEMENT INCHANGÉS :
  //  un compteur ou une agrégation qui lit `gainNet` obtient toujours la
  //  même valeur qu'avant.
  //
  //  ── POURQUOI LA REGLE EST CELLE-CI ─────────────────────────────────────
  //  Pour un G+P, un gain n'est établi que si les DEUX composantes sont
  //  ventilées ET si le résultat financier vient d'un rapport officiel
  //  (`gainRealise` écrit par `enregistrerDividendePmu`, dont la formule
  //  est protégée). Dans TOUT autre cas — gain déduit d'une cote, d'un
  //  dividende mono-combinaison, ou composantes incomplètes — le gain
  //  n'est pas établi.
  //
  //  Aucun autre type de pari n'est concerné : la règle ne s'applique
  //  jamais hors Gagnant + Placé.
  //
  //  ⚠️ Ne PAS déduire de `true` que le montant est exact : cet indicateur
  //     dit seulement qu'il n'est pas un produit cote × mise d'une seule
  //     composante. Le montant reste celui des formules existantes.
  bool get gainGagnantPlaceEtabli {
    if (!estTypeGagnantPlace(typePari)) return true; // hors G+P : inchangé
    if (miseGagnant == null || misePlace == null) return false;

    // Perdu : `-montantMise` n'est pas une cote appliquée à une mise.
    if (isCorrect == false) return true;

    // Gagné : il faut un résultat financier OFFICIEL (ou une saisie
    // explicite), et non le repli cote × mise.
    if (isCorrect == true) return gainRealise != null;

    // En attente : aucun gain n'est établi, mais aucun n'est affiché non
    // plus — la valeur est sans effet. On reste conservateur.
    return false;
  }

  /// Sérialisation pour shared_preferences
  Map<String, dynamic> toJson() => {
    'id': id,
    'dateStr': dateStr,
    'numReunion': numReunion,
    'numCourse': numCourse,
    'nomCourse': nomCourse,
    'hippodrome': hippodrome,
    'numeroCheval': numeroCheval,
    'nomCheval': nomCheval,
    'cote': cote,
    'typePari': typePari,
    'createdAt': createdAt.toIso8601String(),
    'isCorrect': isCorrect,
    'scoreIA': scoreIA,
    'montantMise': montantMise,
    'gainRealise': gainRealise,
    'numerosJoues': numerosJoues,
    'dividendePmuReel': dividendePmuReel,
    'combinaisonPmu': combinaisonPmu,
    'miseGagnant': miseGagnant,
    'misePlace': misePlace,
    'coteGagnant': coteGagnant,
    'cotePlace': cotePlace,
    // ★ ÉTAPE 4-F — capture du pari réellement joué.
    //   Ces quatre clés sont TOUJOURS écrites, y compris à `null` : c'est le
    //   choix déjà fait pour `miseGagnant`, `cotePlace`, etc. Un ticket ancien
    //   relu puis réécrit conserve donc la MÊME forme, et `fromJson` tolère
    //   l'absence des clés (→ `null`, jamais une valeur inventée).
    'codePmuOfficiel': codePmuOfficiel,
    'varianteChoisie': varianteChoisie,
    'numerosDansOrdre': numerosDansOrdre,
    'formulePari': formulePari,
    // ★ LOT B-1 — gains PMU structurés.
    //
    //   ⚠️ ÉCRITURE CONDITIONNELLE, ET C'EST VOLONTAIRE.
    //   Les quatre clés 4-F ci-dessus sont inconditionnelles : un ticket
    //   historique relu puis réécrit conserve donc 26 clés exactement.
    //   Ajouter sept clés inconditionnelles ferait passer ce même ticket à 33
    //   clés, ce qui romprait le verrou mesuré `expect(json.length, 26)` et,
    //   plus grave, modifierait la FORME des sauvegardes historiques.
    //
    //   On écrit donc les gains structurés SEULEMENT si le ticket a été résolu
    //   par le nouveau moteur (`etatGain != null`). Un ticket historique garde
    //   sa forme d'origine, à l'octet près.
    ...?etatGain == null
        ? null
        : <String, dynamic>{
            'etatGain': etatGain!.toJson(),
            'rapportsAttribues':
                rapportsAttribues?.map((a) => a.toJson()).toList(),
            'etatTirelire': etatTirelire?.toJson(),
            'dividendeGagnant': dividendeGagnant,
            'dividendePlace': dividendePlace,
            'miseBaseCentimesUtilisee': miseBaseCentimesUtilisee,
            'motifNonDetermination': motifNonDetermination?.toJson(),
          },
    // ★ B1-T12 / étape 1 — gain manuel et liaison certaine.
    //
    //   ⚠️ ÉCRITURE CONDITIONNELLE, ET C'EST LE CŒUR DE LA COMPATIBILITÉ.
    //   Le verrou mesuré `expect(json.length, 26)` protège la FORME des
    //   sauvegardes historiques. Un ticket sans gain manuel et sans liaison
    //   ne doit pas grossir d'un seul octet : les deux clés ne sont donc
    //   écrites que si l'une des deux au moins est renseignée.
    //
    //   `montantGainManuel` à `0.0` DOIT être écrit : c'est une déclaration
    //   explicite, distincte de l'absence. Le test `!= null` le garantit
    //   (`0.0 != null` est vrai), contrairement à un test de véracité.
    ...?(montantGainManuel == null && idTicketLie == null)
        ? null
        : <String, dynamic>{
            'montantGainManuel': montantGainManuel,
            'idTicketLie': idTicketLie,
          },
  };

  factory UserPrediction.fromJson(Map<String, dynamic> json) {
    return UserPrediction(
      id: json['id'] as String? ?? '',
      dateStr: json['dateStr'] as String? ?? '',
      numReunion: json['numReunion'] as int? ?? 0,
      numCourse: json['numCourse'] as int? ?? 0,
      nomCourse: json['nomCourse'] as String? ?? '',
      hippodrome: json['hippodrome'] as String? ?? '',
      numeroCheval: json['numeroCheval'] as int? ?? 0,
      nomCheval: json['nomCheval'] as String? ?? '',
      cote: (json['cote'] as num?)?.toDouble() ?? 0.0,
      typePari: json['typePari'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      isCorrect: json['isCorrect'] as bool?,
      scoreIA: (json['scoreIA'] as num?)?.toDouble() ?? 0.0,
      montantMise: (json['montantMise'] as num?)?.toDouble() ?? 0.0,
      gainRealise: (json['gainRealise'] as num?)?.toDouble(),
      numerosJoues: (json['numerosJoues'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      dividendePmuReel: (json['dividendePmuReel'] as num?)?.toDouble(),
      combinaisonPmu: json['combinaisonPmu'] as String?,
      // ★ B1 — lecture TOLÉRANTE à l'absence de clé (→ null), mais STRICTE
      //   sur le type : `as num?` lève un `_TypeError` si la valeur est une
      //   chaîne (mesuré : `{'x': '10'}` → `as num?` lève `_TypeError`).
      //   Ce comportement est celui des 8 autres champs optionnels ci-dessus.
      miseGagnant: (json['miseGagnant'] as num?)?.toDouble(),
      misePlace: (json['misePlace'] as num?)?.toDouble(),
      coteGagnant: (json['coteGagnant'] as num?)?.toDouble(),
      cotePlace: (json['cotePlace'] as num?)?.toDouble(),
      // ★ ÉTAPE 4-F — lecture TOLÉRANTE : clé absente ⇒ `null`.
      //   Aucune valeur de repli, aucun ordre fabriqué, aucune variante devinée.
      //   `numerosDansOrdre` reste `null` (et non `[]`) quand la clé manque :
      //   « non capturé » et « liste vide » sont deux états différents, et
      //   confondre les deux reviendrait à affirmer qu'aucun cheval n'était
      //   joué dans l'ordre.
      codePmuOfficiel: json['codePmuOfficiel'] as String?,
      varianteChoisie: json['varianteChoisie'] as String?,
      numerosDansOrdre: (json['numerosDansOrdre'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      formulePari: json['formulePari'] as String?,
      // ★ LOT B-1 — lecture TOLÉRANTE des gains structurés.
      //   Clé absente ⇒ `null` ⇒ chemin legacy. Aucun état déduit, aucun
      //   rapport reconstruit, aucun montant complété.
      etatGain: EtatGain.fromJson(json['etatGain']),
      rapportsAttribues: _lireRapportsAttribues(json['rapportsAttribues']),
      etatTirelire: EtatTirelire.fromJson(json['etatTirelire']),
      dividendeGagnant: (json['dividendeGagnant'] as num?)?.toDouble(),
      dividendePlace: (json['dividendePlace'] as num?)?.toDouble(),
      miseBaseCentimesUtilisee:
          (json['miseBaseCentimesUtilisee'] as num?)?.toInt(),
      motifNonDetermination:
          MotifNonDetermination.fromJson(json['motifNonDetermination']),
      // ★ B1-T12 / étape 1 — lecture TOLÉRANTE : clé absente ⇒ `null`.
      //   Un ancien ticket n'a jamais eu ces clés : il reste à `null`, donc
      //   « aucun gain manuel » et « aucune liaison », ce qui est exact.
      //   Aucune valeur de repli n'est inventée, et aucun gain n'est recalculé
      //   au chargement (interdiction du mandat).
      montantGainManuel: (json['montantGainManuel'] as num?)?.toDouble(),
      idTicketLie: json['idTicketLie'] as String?,
    );
  }

  /// Relecture tolérante d'une liste de rapports attribués.
  ///
  /// Rend `null` — et non une liste vide — quand la clé est absente ou n'est
  /// pas une liste : « non résolu » et « résolu sans rapport » sont deux états
  /// différents. Un élément illisible est IGNORÉ plutôt que fabriqué ; s'il
  /// n'en reste aucun, on rend `null` pour ne pas affirmer une résolution.
  static List<RapportAttribue>? _lireRapportsAttribues(dynamic valeur) {
    if (valeur is! List) return null;
    final out = <RapportAttribue>[];
    for (final item in valeur) {
      if (item is! Map) continue;
      try {
        out.add(RapportAttribue.fromJson(Map<String, dynamic>.from(item)));
      } on FormatException {
        // Élément illisible : ignoré, jamais deviné.
        continue;
      }
    }
    return out.isEmpty ? null : out;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ★ LOT B-4.3 — COPIE SÛRE
  //
  //  CRÉÉ POUR L'ENREGISTREMENT DU VERDICT (B-4.3), UTILISABLE PARTOUT.
  //
  //  CONTRAT — L'UN SEUL QUI COMPTE
  //   • argument OMIS      → l'ancienne valeur est conservée ;
  //   • argument `null`    → la valeur devient `null` (effacement explicite) ;
  //   • aucune valeur par défaut n'est inventée : les `?? ` de `fromJson`
  //     ne s'appliquent PAS ici ;
  //   • aucune mutation : l'instance source n'est jamais modifiée ;
  //   • `toJson` est INCHANGÉ : un ticket historique copié garde ses 26 clés.
  //
  //  Les collections sont recopiées (`List.of`) : la copie et l'original ne
  //  partagent pas la même liste, donc modifier l'une ne peut pas altérer
  //  l'autre. Les éléments eux-mêmes sont immuables (`int`) ou traités comme
  //  tels (`RapportAttribue` n'a que des champs `final`).
  // ══════════════════════════════════════════════════════════════════════════
  UserPrediction copyWith({
    String? id,
    String? dateStr,
    int? numReunion,
    int? numCourse,
    String? nomCourse,
    String? hippodrome,
    int? numeroCheval,
    String? nomCheval,
    double? cote,
    String? typePari,
    DateTime? createdAt,
    // ── Champs MUTABLES du modèle historique : sentinelle obligatoire ───────
    Object? isCorrect = _inchange,
    double? scoreIA,
    Object? montantMise = _inchange,
    Object? gainRealise = _inchange,
    Object? numerosJoues = _inchange,
    Object? dividendePmuReel = _inchange,
    Object? combinaisonPmu = _inchange,
    // ── G+P / B2 ───────────────────────────────────────────────────────────
    Object? miseGagnant = _inchange,
    Object? misePlace = _inchange,
    Object? coteGagnant = _inchange,
    Object? cotePlace = _inchange,
    // ── ÉTAPE 4-F — capture du pari joué ───────────────────────────────────
    Object? codePmuOfficiel = _inchange,
    Object? varianteChoisie = _inchange,
    Object? numerosDansOrdre = _inchange,
    Object? formulePari = _inchange,
    // ── LOT B-1 — gains PMU structurés (les 7 champs, un par un) ───────────
    Object? etatGain = _inchange,
    Object? rapportsAttribues = _inchange,
    Object? etatTirelire = _inchange,
    Object? dividendeGagnant = _inchange,
    Object? dividendePlace = _inchange,
    Object? miseBaseCentimesUtilisee = _inchange,
    Object? motifNonDetermination = _inchange,
    // ── B1-T12 / étape 1 — gain manuel et liaison certaine ────────────────
    //  ⚠️ SENTINELLE OBLIGATOIRE : `null` doit pouvoir ÊTRE ÉCRIT
    //  explicitement pour ANNULER un gain manuel (retour au calcul PMU).
    //  Un paramètre `double?` nu confondrait « non fourni » et « mis à null »,
    //  et l'annulation deviendrait impossible. D'où `Object?` + sentinelle.
    Object? montantGainManuel = _inchange,
    Object? idTicketLie = _inchange,
  }) {
    return UserPrediction(
      // Champs REQUIS : jamais nuls, donc `?? this.x` est sans ambiguïté.
      id: id ?? this.id,
      dateStr: dateStr ?? this.dateStr,
      numReunion: numReunion ?? this.numReunion,
      numCourse: numCourse ?? this.numCourse,
      nomCourse: nomCourse ?? this.nomCourse,
      hippodrome: hippodrome ?? this.hippodrome,
      numeroCheval: numeroCheval ?? this.numeroCheval,
      nomCheval: nomCheval ?? this.nomCheval,
      cote: cote ?? this.cote,
      typePari: typePari ?? this.typePari,
      createdAt: createdAt ?? this.createdAt,
      // Champs OPTIONNELS : la sentinelle fait foi.
      isCorrect: identical(isCorrect, _inchange)
          ? this.isCorrect
          : isCorrect as bool?,
      scoreIA: scoreIA ?? this.scoreIA,
      montantMise: identical(montantMise, _inchange)
          ? this.montantMise
          : montantMise as double,
      gainRealise: identical(gainRealise, _inchange)
          ? this.gainRealise
          : gainRealise as double?,
      numerosJoues: identical(numerosJoues, _inchange)
          ? List<int>.of(this.numerosJoues)
          : List<int>.of(numerosJoues as List<int>),
      dividendePmuReel: identical(dividendePmuReel, _inchange)
          ? this.dividendePmuReel
          : dividendePmuReel as double?,
      combinaisonPmu: identical(combinaisonPmu, _inchange)
          ? this.combinaisonPmu
          : combinaisonPmu as String?,
      miseGagnant: identical(miseGagnant, _inchange)
          ? this.miseGagnant
          : miseGagnant as double?,
      misePlace: identical(misePlace, _inchange)
          ? this.misePlace
          : misePlace as double?,
      coteGagnant: identical(coteGagnant, _inchange)
          ? this.coteGagnant
          : coteGagnant as double?,
      cotePlace: identical(cotePlace, _inchange)
          ? this.cotePlace
          : cotePlace as double?,
      codePmuOfficiel: identical(codePmuOfficiel, _inchange)
          ? this.codePmuOfficiel
          : codePmuOfficiel as String?,
      varianteChoisie: identical(varianteChoisie, _inchange)
          ? this.varianteChoisie
          : varianteChoisie as String?,
      numerosDansOrdre: identical(numerosDansOrdre, _inchange)
          ? (this.numerosDansOrdre == null
              ? null
              : List<int>.of(this.numerosDansOrdre!))
          : (numerosDansOrdre == null
              ? null
              : List<int>.of(numerosDansOrdre as List<int>)),
      formulePari: identical(formulePari, _inchange)
          ? this.formulePari
          : formulePari as String?,
      // ★ Les 7 champs B-1 : jamais fusionnés, jamais déduits les uns des autres.
      etatGain: identical(etatGain, _inchange)
          ? this.etatGain
          : etatGain as EtatGain?,
      rapportsAttribues: identical(rapportsAttribues, _inchange)
          ? (this.rapportsAttribues == null
              ? null
              : List<RapportAttribue>.of(this.rapportsAttribues!))
          : (rapportsAttribues == null
              ? null
              : List<RapportAttribue>.of(
                  rapportsAttribues as List<RapportAttribue>)),
      etatTirelire: identical(etatTirelire, _inchange)
          ? this.etatTirelire
          : etatTirelire as EtatTirelire?,
      dividendeGagnant: identical(dividendeGagnant, _inchange)
          ? this.dividendeGagnant
          : dividendeGagnant as double?,
      dividendePlace: identical(dividendePlace, _inchange)
          ? this.dividendePlace
          : dividendePlace as double?,
      miseBaseCentimesUtilisee: identical(miseBaseCentimesUtilisee, _inchange)
          ? this.miseBaseCentimesUtilisee
          : miseBaseCentimesUtilisee as int?,
      motifNonDetermination: identical(motifNonDetermination, _inchange)
          ? this.motifNonDetermination
          : motifNonDetermination as MotifNonDetermination?,
      // ★ B1-T12 / étape 1 — propagés avec la sentinelle : `null` peut être
      //   écrit explicitement (annulation d'un gain manuel, déliaison).
      montantGainManuel: identical(montantGainManuel, _inchange)
          ? this.montantGainManuel
          : montantGainManuel as double?,
      idTicketLie: identical(idTicketLie, _inchange)
          ? this.idTicketLie
          : idTicketLie as String?,
    );
  }
}
