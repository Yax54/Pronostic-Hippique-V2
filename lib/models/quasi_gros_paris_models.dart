// ═══════════════════════════════════════════════════════════════════════════
//  QUASI GROS PARIS — Modèles de données v10.74
//
//  Module secondaire d'observation et suggestion prudente.
//  Ne modifie JAMAIS : apprentissage IA, poids, premium officiel,
//  streaks, taux officiels, ROI, calendrier principal.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

// ── Types de gros paris pris en compte ─────────────────────────────────────
enum TypeGrosPari {
  tierce,
  quarte,
  quinte,
}

// ── Source d'un quasi gagnant ───────────────────────────────────────────────
enum SourceQuasiGagnant {
  programme,           // Vient du programme IA (pronostics généraux)
  grosParisSurveiller, // Vient d'un signal "Gros paris à surveiller" Best Bet
}

// ── Niveau de fiabilité d'un signal ────────────────────────────────────────
enum NiveauFiabiliteGrosPari {
  fort,       // ≥ 80  — signal solide
  surveiller, // 65–79 — à considérer avec prudence
  speculatif, // 50–64 — spéculatif
  eviter,     // < 50  — éviter
}

// ── Couleur associée au niveau ──────────────────────────────────────────────
Color couleurNiveau(NiveauFiabiliteGrosPari niveau) {
  switch (niveau) {
    case NiveauFiabiliteGrosPari.fort:       return const Color(0xFFFFD700); // or
    case NiveauFiabiliteGrosPari.surveiller: return const Color(0xFF66BB6A); // vert
    case NiveauFiabiliteGrosPari.speculatif: return const Color(0xFFFF9800); // orange
    case NiveauFiabiliteGrosPari.eviter:     return const Color(0xFFE53935); // rouge
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  ★ v10.74 — ChevalScoreIA — snapshot du classement IA au moment du signal
// ══════════════════════════════════════════════════════════════════════════

class ChevalScoreIA {
  final String numero;
  final String nom;
  final double score;
  final int    rangIA;

  const ChevalScoreIA({
    required this.numero,
    required this.nom,
    required this.score,
    required this.rangIA,
  });

  Map<String, dynamic> toJson() => {
    'numero': numero,
    'nom':    nom,
    'score':  score,
    'rangIA': rangIA,
  };

  factory ChevalScoreIA.fromJson(Map<String, dynamic> json) => ChevalScoreIA(
    numero: json['numero']?.toString() ?? '',
    nom:    json['nom']?.toString()    ?? '',
    score:  (json['score'] as num?     ?? 0).toDouble(),
    rangIA: json['rangIA'] as int?     ?? 0,
  );
}

// ══════════════════════════════════════════════════════════════════════════
//  ★ v10.74 — ComparaisonCourseIA — résultat IA vs PMU
// ══════════════════════════════════════════════════════════════════════════

class ComparaisonCourseIA {
  final List<String>        selectionIA;
  final List<String>        arriveePMU;
  final List<String>        trouves;
  final List<String>        manquantsIA;
  final List<String>        remplacantsPMU;
  final Map<String, int?>   rangReelParNumero;

  const ComparaisonCourseIA({
    required this.selectionIA,
    required this.arriveePMU,
    required this.trouves,
    required this.manquantsIA,
    required this.remplacantsPMU,
    required this.rangReelParNumero,
  });
}

// ── Fonction utilitaire de comparaison IA vs PMU ──────────────────────────
ComparaisonCourseIA comparerCourseIA({
  required List<String> selectionIA,
  required List<String> arriveePMU,
  required int          nb,
}) {
  final ia  = selectionIA.take(nb).map((e) => e.toString()).toList();
  // PMU : toute l'arrivée disponible pour retrouver les positions réelles
  final pmuTopN = arriveePMU.take(nb).map((e) => e.toString()).toList();

  final setIA   = ia.toSet();
  final setPMU  = pmuTopN.toSet();

  final trouves      = setIA.intersection(setPMU).toList();
  final manquants    = setIA.difference(setPMU).toList();
  final remplacants  = setPMU.difference(setIA).toList();

  // Rang réel dans l'arrivée complète (pas seulement top N)
  final rangReelParNumero = <String, int?>{};
  for (final n in ia) {
    final idx = arriveePMU.indexOf(n);
    rangReelParNumero[n] = idx >= 0 ? idx + 1 : null;
  }

  return ComparaisonCourseIA(
    selectionIA:      ia,
    arriveePMU:       arriveePMU,
    trouves:          trouves,
    manquantsIA:      manquants,
    remplacantsPMU:   remplacants,
    rangReelParNumero: rangReelParNumero,
  );
}

// ══════════════════════════════════════════════════════════════════════════
//  GrosPariSurveiller — signal avant course (Best Bet ⚠️)
// ══════════════════════════════════════════════════════════════════════════

class GrosPariSurveiller {
  final String id;
  final String courseKey;
  final DateTime dateCourse;
  final String nomCourse;
  final String hippodrome;
  final String heure;
  final String discipline;

  final TypeGrosPari type;
  final List<String> numeros;
  final Map<String, double> scoresParNumero;

  final double scoreMoyenSelection;
  final double ecartAvecSuivant;
  final double fiabilite;
  final NiveauFiabiliteGrosPari niveau;

  // ★ v10.74 : snapshot du classement IA complet au moment du signal
  final List<ChevalScoreIA> classementCompletIA;

  final DateTime createdAt;

  const GrosPariSurveiller({
    required this.id,
    required this.courseKey,
    required this.dateCourse,
    required this.nomCourse,
    required this.hippodrome,
    required this.heure,
    required this.discipline,
    required this.type,
    required this.numeros,
    required this.scoresParNumero,
    required this.scoreMoyenSelection,
    required this.ecartAvecSuivant,
    required this.fiabilite,
    required this.niveau,
    required this.createdAt,
    this.classementCompletIA = const [], // ★ v10.74 : défaut vide pour compat anciens objets
  });

  Map<String, dynamic> toJson() => {
    'id':                   id,
    'courseKey':            courseKey,
    'dateCourse':           dateCourse.toIso8601String(),
    'nomCourse':            nomCourse,
    'hippodrome':           hippodrome,
    'heure':                heure,
    'discipline':           discipline,
    'type':                 type.name,
    'numeros':              numeros,
    'scoresParNumero':      scoresParNumero,
    'scoreMoyenSelection':  scoreMoyenSelection,
    'ecartAvecSuivant':     ecartAvecSuivant,
    'fiabilite':            fiabilite,
    'niveau':               niveau.name,
    'createdAt':            createdAt.toIso8601String(),
    // ★ v10.74 : snapshot classement
    'classementCompletIA':  classementCompletIA.map((e) => e.toJson()).toList(),
  };

  factory GrosPariSurveiller.fromJson(Map<String, dynamic> json) {
    return GrosPariSurveiller(
      id:                  json['id']         as String? ?? '',
      courseKey:           json['courseKey']  as String? ?? '',
      dateCourse:          DateTime.tryParse(json['dateCourse'] as String? ?? '')
                              ?? DateTime.now(),
      nomCourse:           json['nomCourse']  as String? ?? '',
      hippodrome:          json['hippodrome'] as String? ?? '',
      heure:               json['heure']      as String? ?? '',
      discipline:          json['discipline'] as String? ?? '',
      type: TypeGrosPari.values.firstWhere(
        (e) => e.name == (json['type'] as String? ?? ''),
        orElse: () => TypeGrosPari.tierce,
      ),
      numeros: List<String>.from(json['numeros'] as List? ?? const []),
      scoresParNumero: Map<String, double>.from(
        ((json['scoresParNumero'] as Map?) ?? {}).map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        ),
      ),
      scoreMoyenSelection: (json['scoreMoyenSelection'] as num? ?? 0).toDouble(),
      ecartAvecSuivant:    (json['ecartAvecSuivant']    as num? ?? 0).toDouble(),
      fiabilite:           (json['fiabilite']           as num? ?? 0).toDouble(),
      niveau: NiveauFiabiliteGrosPari.values.firstWhere(
        (e) => e.name == (json['niveau'] as String? ?? ''),
        orElse: () => NiveauFiabiliteGrosPari.speculatif,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')
                    ?? DateTime.now(),
      // ★ v10.74 : si absent (ancien signal) → liste vide, pas de crash
      classementCompletIA: (json['classementCompletIA'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ChevalScoreIA.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  QuasiGagnant — résultat après course (Calendrier 🎯)
// ══════════════════════════════════════════════════════════════════════════

class QuasiGagnant {
  final String id;
  final String courseKey;
  final DateTime dateCourse;
  final String nomCourse;
  final String hippodrome;
  final String heure;
  final String discipline;

  final TypeGrosPari type;
  final SourceQuasiGagnant source;

  final List<String> numerosIA;
  final List<String> arriveeReelle;   // arrivée PMU complète disponible
  final List<String> numerosTrouves;
  final List<String> numerosManquants;

  final int nbTrouves;
  final int nbRequis;
  final double fiabilite;

  final DateTime createdAt;

  const QuasiGagnant({
    required this.id,
    required this.courseKey,
    required this.dateCourse,
    required this.nomCourse,
    required this.hippodrome,
    required this.heure,
    required this.discipline,
    required this.type,
    required this.source,
    required this.numerosIA,
    required this.arriveeReelle,
    required this.numerosTrouves,
    required this.numerosManquants,
    required this.nbTrouves,
    required this.nbRequis,
    required this.fiabilite,
    required this.createdAt,
  });

  /// true si ce quasi gagnant vient d'un signal Best Bet
  bool get vientDeBestBet => source == SourceQuasiGagnant.grosParisSurveiller;

  Map<String, dynamic> toJson() => {
    'id':               id,
    'courseKey':        courseKey,
    'dateCourse':       dateCourse.toIso8601String(),
    'nomCourse':        nomCourse,
    'hippodrome':       hippodrome,
    'heure':            heure,
    'discipline':       discipline,
    'type':             type.name,
    'source':           source.name,
    'numerosIA':        numerosIA,
    'arriveeReelle':    arriveeReelle,
    'numerosTrouves':   numerosTrouves,
    'numerosManquants': numerosManquants,
    'nbTrouves':        nbTrouves,
    'nbRequis':         nbRequis,
    'fiabilite':        fiabilite,
    'createdAt':        createdAt.toIso8601String(),
  };

  factory QuasiGagnant.fromJson(Map<String, dynamic> json) {
    return QuasiGagnant(
      id:               json['id']        as String? ?? '',
      courseKey:        json['courseKey'] as String? ?? '',
      dateCourse:       DateTime.tryParse(json['dateCourse'] as String? ?? '')
                           ?? DateTime.now(),
      nomCourse:        json['nomCourse']  as String? ?? '',
      hippodrome:       json['hippodrome'] as String? ?? '',
      heure:            json['heure']      as String? ?? '',
      discipline:       json['discipline'] as String? ?? '',
      type: TypeGrosPari.values.firstWhere(
        (e) => e.name == (json['type'] as String? ?? ''),
        orElse: () => TypeGrosPari.tierce,
      ),
      source: SourceQuasiGagnant.values.firstWhere(
        (e) => e.name == (json['source'] as String? ?? ''),
        orElse: () => SourceQuasiGagnant.programme,
      ),
      numerosIA:        List<String>.from(json['numerosIA']        as List? ?? const []),
      arriveeReelle:    List<String>.from(json['arriveeReelle']    as List? ?? const []),
      numerosTrouves:   List<String>.from(json['numerosTrouves']   as List? ?? const []),
      numerosManquants: List<String>.from(json['numerosManquants'] as List? ?? const []),
      nbTrouves: json['nbTrouves'] as int? ?? 0,
      nbRequis:  json['nbRequis']  as int? ?? 0,
      fiabilite: (json['fiabilite'] as num? ?? 0).toDouble(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')
                    ?? DateTime.now(),
    );
  }
}
