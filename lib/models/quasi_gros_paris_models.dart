// ═══════════════════════════════════════════════════════════════════════════
//  QUASI GROS PARIS — Modèles de données v10.75b
//
//  Module secondaire d'observation et suggestion prudente.
//  Ne modifie JAMAIS : apprentissage IA, poids, premium officiel,
//  streaks, taux officiels, ROI, calendrier principal.
//
//  v10.75b PATCH : GrosPariGagnant, ResultatGrosPariStatut
//  Règle critique : utilisableApprentissage = false TOUJOURS
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
//  ★ v10.75 — Extraction arrivée PMU complète (source unique de vérité)
// ══════════════════════════════════════════════════════════════════════════

/// Extrait l'arrivée PMU complète depuis n'importe quel objet résultat.
/// Normalise : supprime "N°", trim, filtre vides.
/// N'utilise jamais .take() pour l'affichage — garde toute l'arrivée.
List<String> extraireArriveePMUComplete(dynamic resultat) {
  if (resultat == null) return const [];
  List<dynamic> raw = const [];

  // Tente plusieurs champs dans l'ordre de priorité
  if (resultat is Map) {
    raw = (resultat['arriveeComplete']   as List?)
       ?? (resultat['arriveeReelle']     as List?)
       ?? (resultat['classement']        as List?)
       ?? (resultat['topArrivee']        as List?)
       ?? const [];
  } else {
    // Objet Dart avec getters (duck typing via try/catch)
    try { raw = (resultat.arriveeComplete as List?) ?? const []; } catch (_) {}
    if (raw.isEmpty) try { raw = (resultat.arriveeReelle as List?) ?? const []; } catch (_) {}
    if (raw.isEmpty) try { raw = (resultat.classement   as List?) ?? const []; } catch (_) {}
    if (raw.isEmpty) try { raw = (resultat.topArrivee   as List?) ?? const []; } catch (_) {}
  }

  return raw
      .map((e) => e.toString().replaceAll('N°', '').trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

// ══════════════════════════════════════════════════════════════════════════
//  ★ v10.75 — EvaluationGrosPari — évaluateur ordre/désordre/quasi/perdant
// ══════════════════════════════════════════════════════════════════════════

enum ResultatPariType {
  perdant,
  quasi,
  gagnantDesordre,
  gagnantOrdre,
}

class EvaluationGrosPari {
  final String          typePari;
  final ResultatPariType resultat;
  final int             nbTrouves;
  final int             nbRequis;
  final bool            ordreExact;

  const EvaluationGrosPari({
    required this.typePari,
    required this.resultat,
    required this.nbTrouves,
    required this.nbRequis,
    required this.ordreExact,
  });

  bool get estGagnant =>
      resultat == ResultatPariType.gagnantOrdre ||
      resultat == ResultatPariType.gagnantDesordre;

  bool get estQuasi => resultat == ResultatPariType.quasi;

  /// Label lisible : "Tiercé ordre", "Tiercé désordre", etc.
  String get labelResultat {
    switch (resultat) {
      case ResultatPariType.gagnantOrdre:   return '$typePari ordre ✅';
      case ResultatPariType.gagnantDesordre: return '$typePari désordre ✅';
      case ResultatPariType.quasi:          return '$typePari quasi ($nbTrouves/$nbRequis)';
      case ResultatPariType.perdant:        return '$typePari perdant ($nbTrouves/$nbRequis)';
    }
  }

  /// true si source Gros Paris → ne jamais injecter dans gradient descent
  bool get estSourceApprentissage => false;
}

/// Évalue un pari type (Tiercé, Quarté+, Quinté+) en ordre ou désordre.
/// Utilise TOUJOURS l'arrivée COMPLÈTE — ne tronque pas pour l'évaluation.
EvaluationGrosPari evaluerGrosPari({
  required String       typePari,
  required List<String> selectionIA,
  required List<String> arriveePMUComplete,
}) {
  final nb = _nbChevauxPourTypePariStr(typePari);

  final ia      = selectionIA.take(nb).map((e) => e.toString()).toList();
  final pmuTopN = arriveePMUComplete.take(nb).map((e) => e.toString()).toList();

  if (ia.isEmpty || pmuTopN.length < nb) {
    return EvaluationGrosPari(
      typePari: typePari, resultat: ResultatPariType.perdant,
      nbTrouves: 0, nbRequis: nb, ordreExact: false,
    );
  }

  final setIA  = ia.toSet();
  final setPMU = pmuTopN.toSet();
  final nbTrouves = setIA.intersection(setPMU).length;

  // Ordre exact ?
  final ordreExact = ia.length == pmuTopN.length &&
      List.generate(nb, (i) => ia[i] == pmuTopN[i]).every((e) => e);

  if (nbTrouves == nb && ordreExact) {
    return EvaluationGrosPari(
      typePari: typePari, resultat: ResultatPariType.gagnantOrdre,
      nbTrouves: nbTrouves, nbRequis: nb, ordreExact: true,
    );
  }

  if (nbTrouves == nb) {
    return EvaluationGrosPari(
      typePari: typePari, resultat: ResultatPariType.gagnantDesordre,
      nbTrouves: nbTrouves, nbRequis: nb, ordreExact: false,
    );
  }

  // Quasi = nb - 1 trouvé
  if (nbTrouves == nb - 1) {
    return EvaluationGrosPari(
      typePari: typePari, resultat: ResultatPariType.quasi,
      nbTrouves: nbTrouves, nbRequis: nb, ordreExact: false,
    );
  }

  return EvaluationGrosPari(
    typePari: typePari, resultat: ResultatPariType.perdant,
    nbTrouves: nbTrouves, nbRequis: nb, ordreExact: false,
  );
}

/// Nombre de chevaux selon le libellé de type de pari (ex: "Tiercé", "Quarté+", "Quinté+").
int _nbChevauxPourTypePariStr(String typePari) {
  final t = typePari.toLowerCase();
  if (t.contains('quint')) return 5;
  if (t.contains('quart')) return 4;
  if (t.contains('tierc') || t.contains('trio')) return 3;
  if (t.contains('coupl')) return 2;
  return 1;
}

/// Priorité d'un type de pari pour la déduplication par course.
/// Plus la valeur est haute, plus le type est prioritaire.
int prioritePari(String typePari) {
  final t = typePari.toLowerCase();
  if (t.contains('quint')) return 6;
  if (t.contains('quart')) return 5;
  if (t.contains('tierc') || t.contains('trio')) return 4;
  if (t.contains('coupl')) return 3;
  if (t.contains('plac')) return 2;
  if (t.contains('simple')) return 1;
  return 0;
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
//  ★ v10.75b PATCH — ResultatGrosPariStatut (alias / surensemble de ResultatPariType)
//  Utilisé dans GrosPariGagnant pour le champ 'statut'.
// ══════════════════════════════════════════════════════════════════════════

/// Alias sémantique de [ResultatPariType] pour les vrais gagnants uniquement.
/// Seules les valeurs gagnantOrdre et gagnantDesordre apparaissent dans
/// [GrosPariGagnant] — perdant et quasi ne sont jamais stockés ici.
typedef ResultatGrosPariStatut = ResultatPariType;

// ══════════════════════════════════════════════════════════════════════════
//  ★ v10.75b PATCH — GrosPariGagnant
//  Modèle séparé pour les gros paris gagnants (ordre ou désordre).
//  CRITIQUE :
//    • utilisableApprentissage = false — JAMAIS injecté dans gradient descent
//    • utilisableStatsUtilisateur = true — affiché dans Calendrier/IA Stats
//    • source = 'grosParisSurveiller' — tracé comme venant de Best Bet
//    • Aucun champ scoresCriteres — isolation totale du gradient
// ══════════════════════════════════════════════════════════════════════════

class GrosPariGagnant {
  final String   id;
  final String   courseKey;
  final DateTime dateCourse;
  final String   nomCourse;
  final String   hippodrome;
  final String   heure;
  final String   discipline;

  final String       typePari;           // ex: "Tiercé", "Quarté+", "Quinté+"
  final List<String> selectionIA;        // numéros IA conseillés
  final List<String> arriveePMUComplete; // arrivée PMU complète (source de vérité)

  /// Statut : gagnantOrdre ou gagnantDesordre uniquement
  final ResultatGrosPariStatut statut;
  final bool ordreExact;                 // true = ordre, false = désordre

  // ── Flags d'isolation IA ──────────────────────────────────────────────
  /// TOUJOURS false : ne jamais alimenter gradient descent / poids IA
  final bool utilisableApprentissage;
  /// TOUJOURS true : affiché dans stats utilisateur, Calendrier, Mémoire IA
  final bool utilisableStatsUtilisateur;
  /// Source traçabilité
  final String source;

  final DateTime createdAt;

  const GrosPariGagnant({
    required this.id,
    required this.courseKey,
    required this.dateCourse,
    required this.nomCourse,
    required this.hippodrome,
    required this.heure,
    required this.discipline,
    required this.typePari,
    required this.selectionIA,
    required this.arriveePMUComplete,
    required this.statut,
    required this.ordreExact,
    required this.createdAt,
    this.utilisableApprentissage  = false,           // immuable false
    this.utilisableStatsUtilisateur = true,          // immuable true
    this.source                   = 'grosParisSurveiller',
  });

  /// Label lisible pour l'affichage (ex: "Tiercé désordre ✅")
  String get labelStatut {
    if (ordreExact) return '$typePari ordre ✅';
    return '$typePari désordre ✅';
  }

  /// Badge court pour le Calendrier
  String get badgeStatut => ordreExact ? '🥇 Ordre' : '🥈 Désordre';

  Map<String, dynamic> toJson() => {
    'id':                       id,
    'courseKey':                courseKey,
    'dateCourse':               dateCourse.toIso8601String(),
    'nomCourse':                nomCourse,
    'hippodrome':               hippodrome,
    'heure':                    heure,
    'discipline':               discipline,
    'typePari':                 typePari,
    'selectionIA':              selectionIA,
    'arriveePMUComplete':       arriveePMUComplete,
    'statut':                   statut.name,
    'ordreExact':               ordreExact,
    'utilisableApprentissage':  false,   // toujours false en JSON
    'utilisableStatsUtilisateur': true,  // toujours true en JSON
    'source':                   source,
    'createdAt':                createdAt.toIso8601String(),
  };

  factory GrosPariGagnant.fromJson(Map<String, dynamic> json) {
    return GrosPariGagnant(
      id:           json['id']         as String? ?? '',
      courseKey:    json['courseKey']  as String? ?? '',
      dateCourse:   DateTime.tryParse(json['dateCourse'] as String? ?? '')
                        ?? DateTime.now(),
      nomCourse:    json['nomCourse']  as String? ?? '',
      hippodrome:   json['hippodrome'] as String? ?? '',
      heure:        json['heure']      as String? ?? '',
      discipline:   json['discipline'] as String? ?? '',
      typePari:     json['typePari']   as String? ?? '',
      selectionIA:  List<String>.from(json['selectionIA']       as List? ?? const []),
      arriveePMUComplete: List<String>.from(
                      json['arriveePMUComplete'] as List? ?? const []),
      statut: ResultatGrosPariStatut.values.firstWhere(
        (e) => e.name == (json['statut'] as String? ?? ''),
        orElse: () => ResultatGrosPariStatut.gagnantDesordre,
      ),
      ordreExact: json['ordreExact'] as bool? ?? false,
      createdAt:  DateTime.tryParse(json['createdAt'] as String? ?? '')
                      ?? DateTime.now(),
      // Flags immuables : ignorés depuis JSON pour sécurité
      utilisableApprentissage   : false,
      utilisableStatsUtilisateur: true,
      source: json['source'] as String? ?? 'grosParisSurveiller',
    );
  }

  /// Construit depuis un signal [GrosPariSurveiller] + évaluation
  factory GrosPariGagnant.depuisSignal({
    required GrosPariSurveiller signal,
    required EvaluationGrosPari evaluation,
    required List<String>       arriveePMUComplete,
  }) {
    assert(evaluation.estGagnant,
        'GrosPariGagnant.depuisSignal : evaluation doit être gagnante');
    return GrosPariGagnant(
      id:                 'gpg_${signal.courseKey}_${DateTime.now().millisecondsSinceEpoch}',
      courseKey:          signal.courseKey,
      dateCourse:         signal.dateCourse,
      nomCourse:          signal.nomCourse,
      hippodrome:         signal.hippodrome,
      heure:              signal.heure,
      discipline:         signal.discipline,
      typePari:           evaluation.typePari,
      selectionIA:        signal.numeros,
      arriveePMUComplete: arriveePMUComplete,
      statut:             evaluation.resultat,  // gagnantOrdre ou gagnantDesordre
      ordreExact:         evaluation.ordreExact,
      createdAt:          DateTime.now(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  ★ v10.75b — evaluerGrosPariOrdreDesordre()
//  Fonction top-level — alias enrichi de evaluerGrosPari().
//  Identique logiquement mais typée explicitement pour le patch.
//  Règle : si estGagnant → appeler enregistrerGrosPariGagnant(), return null
//          si estQuasi   → ajouter à _quasiGagnants normalement
// ══════════════════════════════════════════════════════════════════════════

EvaluationGrosPari evaluerGrosPariOrdreDesordre({
  required String       typePari,
  required List<String> selectionIA,
  required List<String> arriveePMUComplete,
}) {
  // Délègue à evaluerGrosPari() — logique commune, source unique
  return evaluerGrosPari(
    typePari:           typePari,
    selectionIA:        selectionIA,
    arriveePMUComplete: arriveePMUComplete,
  );
}

// ══════════════════════════════════════════════════════════════════════════
//  ★ v10.76 — EvaluationPari — évaluateur unifié (nouveau nom canonique)
//  Champs renommés vs EvaluationGrosPari : statut (vs resultat),
//  predictionIA (vs selectionIA, passé en paramètre).
//  Utilisation : evaluerPariOrdreDesordre() partout dans l'app.
//  RÈGLE ABSOLUE : jamais dans gradient descent.
// ══════════════════════════════════════════════════════════════════════════

class EvaluationPari {
  final ResultatPariType statut;
  final int              nbTrouves;
  final int              nbRequis;
  final bool             ordreExact;

  const EvaluationPari({
    required this.statut,
    required this.nbTrouves,
    required this.nbRequis,
    required this.ordreExact,
  });

  bool get estGagnant =>
      statut == ResultatPariType.gagnantOrdre ||
      statut == ResultatPariType.gagnantDesordre;

  bool get estQuasi => statut == ResultatPariType.quasi;
  bool get estPerdant => statut == ResultatPariType.perdant;
}

/// Nombre de chevaux requis pour un type de pari (version publique v10.76).
int nbChevauxPourType(String typePari) {
  final t = typePari.toLowerCase();
  if (t.contains('quint')) return 5;
  if (t.contains('quart')) return 4;
  if (t.contains('tierc') || t.contains('trio')) return 3;
  if (t.contains('coupl')) return 2;
  return 1;
}

/// Évaluateur unifié v10.76 — remplace tous les calculs locaux.
/// Utilise l'arrivée PMU COMPLÈTE — ne tronque pas pour l'affichage.
/// RÈGLE : seule source de vérité pour quasi/gagnant ordre/désordre.
EvaluationPari evaluerPariOrdreDesordre({
  required String       typePari,
  required List<String> predictionIA,
  required List<String> arriveePMUComplete,
}) {
  final nb = nbChevauxPourType(typePari);

  if (predictionIA.length < nb || arriveePMUComplete.length < nb) {
    return EvaluationPari(
      statut:     ResultatPariType.perdant,
      nbTrouves:  0,
      nbRequis:   nb,
      ordreExact: false,
    );
  }

  final ia      = predictionIA.take(nb).map((e) => e.trim()).toList();
  final pmuTopN = arriveePMUComplete.take(nb).map((e) => e.trim()).toList();

  final nbTrouves = ia.toSet().intersection(pmuTopN.toSet()).length;

  final ordreExact = ia.length == pmuTopN.length &&
      List.generate(nb, (i) => ia[i] == pmuTopN[i]).every((e) => e);

  if (nbTrouves == nb && ordreExact) {
    return EvaluationPari(
      statut:     ResultatPariType.gagnantOrdre,
      nbTrouves:  nbTrouves,
      nbRequis:   nb,
      ordreExact: true,
    );
  }

  if (nbTrouves == nb) {
    return EvaluationPari(
      statut:     ResultatPariType.gagnantDesordre,
      nbTrouves:  nbTrouves,
      nbRequis:   nb,
      ordreExact: false,
    );
  }

  if (nbTrouves == nb - 1) {
    return EvaluationPari(
      statut:     ResultatPariType.quasi,
      nbTrouves:  nbTrouves,
      nbRequis:   nb,
      ordreExact: false,
    );
  }

  return EvaluationPari(
    statut:     ResultatPariType.perdant,
    nbTrouves:  nbTrouves,
    nbRequis:   nb,
    ordreExact: false,
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
