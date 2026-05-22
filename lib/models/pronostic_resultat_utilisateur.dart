// ═══════════════════════════════════════════════════════════════════════════
//  pronostic_resultat_utilisateur.dart — Modèles v10.76
//
//  Contient :
//    • PronosticResultatUtilisateur — résultat utilisateur enrichi
//    • HomeBestBetSnapshot          — snapshot figé "Meilleur Pari" Home
//    • MigrationGrosParisResult     — compteurs migration one-shot
//
//  RÈGLE ABSOLUE :
//    utilisableApprentissage = false pour source = 'grosParisSurveiller'
//    Ces modèles ne doivent JAMAIS alimenter le gradient descent.
// ═══════════════════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════════════════
//  PronosticResultatUtilisateur
// ══════════════════════════════════════════════════════════════════════════

class PronosticResultatUtilisateur {
  final String   courseKey;
  final DateTime dateCourse;
  final String   typePari;

  final List<String> predictionIA;
  final List<String> arriveePMUComplete;

  final bool   gagnant;
  final bool   ordreExact;
  final int    nbTrouves;
  final int    nbRequis;

  /// Source de traçabilité (ex: 'grosParisSurveiller', 'programme')
  final String source;

  /// true → utilisé dans stats utilisateur (Calendrier, IA Stats)
  final bool utilisableStatsUtilisateur;

  /// TOUJOURS false pour source = 'grosParisSurveiller'
  /// — isolation totale du gradient descent
  final bool utilisableApprentissage;

  const PronosticResultatUtilisateur({
    required this.courseKey,
    required this.dateCourse,
    required this.typePari,
    required this.predictionIA,
    required this.arriveePMUComplete,
    required this.gagnant,
    required this.ordreExact,
    required this.nbTrouves,
    required this.nbRequis,
    required this.source,
    required this.utilisableStatsUtilisateur,
    required this.utilisableApprentissage,
  });

  Map<String, dynamic> toJson() => {
    'courseKey':                 courseKey,
    'dateCourse':                dateCourse.toIso8601String(),
    'typePari':                  typePari,
    'predictionIA':              predictionIA,
    'arriveePMUComplete':        arriveePMUComplete,
    'gagnant':                   gagnant,
    'ordreExact':                ordreExact,
    'nbTrouves':                 nbTrouves,
    'nbRequis':                  nbRequis,
    'source':                    source,
    'utilisableStatsUtilisateur': utilisableStatsUtilisateur,
    // Sécurité : toujours false pour grosParisSurveiller — jamais dans gradient
    'utilisableApprentissage':
        source == 'grosParisSurveiller' ? false : utilisableApprentissage,
  };

  factory PronosticResultatUtilisateur.fromJson(Map<String, dynamic> json) {
    final src = json['source']?.toString() ?? 'grosParisSurveiller';
    return PronosticResultatUtilisateur(
      courseKey:   json['courseKey']?.toString()  ?? '',
      dateCourse:  DateTime.tryParse(json['dateCourse']?.toString() ?? '')
                       ?? DateTime.now(),
      typePari:    json['typePari']?.toString()   ?? '',
      predictionIA:      List<String>.from(
          json['predictionIA']       as List? ?? const []),
      arriveePMUComplete: List<String>.from(
          json['arriveePMUComplete'] as List? ?? const []),
      gagnant:     json['gagnant']    as bool? ?? false,
      ordreExact:  json['ordreExact'] as bool? ?? false,
      nbTrouves:   json['nbTrouves']  as int?  ?? 0,
      nbRequis:    json['nbRequis']   as int?  ?? 1,
      source:      src,
      utilisableStatsUtilisateur:
          json['utilisableStatsUtilisateur'] as bool? ?? true,
      // Sécurité : force false si grosParisSurveiller même en lecture
      utilisableApprentissage:
          src == 'grosParisSurveiller'
              ? false
              : (json['utilisableApprentissage'] as bool? ?? false),
    );
  }

  /// Construit depuis un GrosPariGagnant pour intégration dans le repository.
  factory PronosticResultatUtilisateur.depuisGrosPariGagnant({
    required String   courseKey,
    required DateTime dateCourse,
    required String   typePari,
    required List<String> predictionIA,
    required List<String> arriveePMUComplete,
    required bool   gagnant,
    required bool   ordreExact,
    required int    nbTrouves,
    required int    nbRequis,
  }) {
    return PronosticResultatUtilisateur(
      courseKey:                   courseKey,
      dateCourse:                  dateCourse,
      typePari:                    typePari,
      predictionIA:                predictionIA,
      arriveePMUComplete:          arriveePMUComplete,
      gagnant:                     gagnant,
      ordreExact:                  ordreExact,
      nbTrouves:                   nbTrouves,
      nbRequis:                    nbRequis,
      source:                      'grosParisSurveiller',
      utilisableStatsUtilisateur:  true,
      utilisableApprentissage:     false, // JAMAIS dans gradient
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  HomeBestBetSnapshot — Snapshot figé "Meilleur Pari" Home
//  Fige la sélection IA au moment de la création.
//  L'arrivée PMU est TOUJOURS hydratée dynamiquement depuis la course vivante.
// ══════════════════════════════════════════════════════════════════════════

class HomeBestBetSnapshot {
  final String   courseKey;
  final DateTime dateCourse;

  final String       typePari;
  final List<String> selectionIA;

  final String nomCourse;
  final String hippodrome;
  final String heure;

  final int scoreIA;
  final int confiance;

  final DateTime createdAt;

  const HomeBestBetSnapshot({
    required this.courseKey,
    required this.dateCourse,
    required this.typePari,
    required this.selectionIA,
    required this.nomCourse,
    required this.hippodrome,
    required this.heure,
    required this.scoreIA,
    required this.confiance,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'courseKey':  courseKey,
    'dateCourse': dateCourse.toIso8601String(),
    'typePari':   typePari,
    'selectionIA': selectionIA,
    'nomCourse':  nomCourse,
    'hippodrome': hippodrome,
    'heure':      heure,
    'scoreIA':    scoreIA,
    'confiance':  confiance,
    'createdAt':  createdAt.toIso8601String(),
  };

  factory HomeBestBetSnapshot.fromJson(Map<String, dynamic> json) {
    return HomeBestBetSnapshot(
      courseKey:  json['courseKey']?.toString()  ?? '',
      dateCourse: DateTime.tryParse(json['dateCourse']?.toString() ?? '')
                      ?? DateTime.now(),
      typePari:   json['typePari']?.toString()   ?? '',
      selectionIA: List<String>.from(json['selectionIA'] as List? ?? const []),
      nomCourse:  json['nomCourse']?.toString()  ?? '',
      hippodrome: json['hippodrome']?.toString() ?? '',
      heure:      json['heure']?.toString()      ?? '',
      scoreIA:    json['scoreIA']    as int? ?? 0,
      confiance:  json['confiance']  as int? ?? 0,
      createdAt:  DateTime.tryParse(json['createdAt']?.toString() ?? '')
                      ?? DateTime.now(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  MigrationGrosParisResult — Compteurs de la migration one-shot
//  Retourné par recalculerGrosParisHistorique() pour logging.
// ══════════════════════════════════════════════════════════════════════════

class MigrationGrosParisResult {
  final int signauxAnalyses;
  final int gagnantsDesordre;  // nouveaux gagnants enregistrés
  final int quasiSupprimes;    // quasi retirés car devenus gagnants

  const MigrationGrosParisResult({
    required this.signauxAnalyses,
    required this.gagnantsDesordre,
    required this.quasiSupprimes,
  });

  @override
  String toString() =>
      'MigrationGrosParisResult('
      'signaux=$signauxAnalyses, '
      'gagnants=$gagnantsDesordre, '
      'quasiSupprimes=$quasiSupprimes)';
}
