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

  /// Indique si le dividende PMU réel a été récupéré
  bool get dividendeRecupere => dividendePmuReel != null;

  /// Indique si c'est un pari combiné (Tiercé/Quarté/Quinté)
  bool get estPariCombine {
    final t = typePari.toLowerCase();
    return t.contains('tiercé') || t.contains('quarté') || t.contains('quinté');
  }

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

  /// Retour total (mise + gain) — 0 si pari perdu
  double get retourTotal {
    if (isCorrect == false) return 0.0; // ✅ Fix: pari perdu = retour 0
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
    );
  }
}
