// ═══════════════════════════════════════════════════════════════════════════
//  simulation_models.dart — Data classes pour le Laboratoire IA
//
//  LECTURE SEULE — aucun poids modifié, aucun apprentissage, aucune sauvegarde
//  de scores ou de pronostics. Uniquement des structures de données en mémoire.
// ═══════════════════════════════════════════════════════════════════════════

// ── Correspondance clés JSON court → nom poids long ──────────────────────────
// ScoresCriteres.toJson() → 'f','g','r'...
// IaPoidsAdaptatifs       → 'forme','gains','record'...
const Map<String, String> kCleCourtVersLong = {
  'f':  'forme',
  'g':  'gains',
  'r':  'record',
  'c':  'cote',
  'k':  'constance',
  'v':  'victoires',
  'd':  'discipline',
  'ds': 'distSpec',
  'j':  'jockey',
  'rp': 'repos',
  'hp': 'hippo',
  'en': 'entraineur',
  'el': 'elo',
  'tr': 'terrain',
  'dv': 'divergence',
  'pr': 'poidsRel',
  'pg': 'progression',
  'mc': 'mouvCote',
  'pd': 'placeDepart',
};

// Inverse : nom long → clé courte
const Map<String, String> kCleLongVersCourt = {
  'forme':       'f',
  'gains':       'g',
  'record':      'r',
  'cote':        'c',
  'constance':   'k',
  'victoires':   'v',
  'discipline':  'd',
  'distSpec':    'ds',
  'jockey':      'j',
  'repos':       'rp',
  'hippo':       'hp',
  'entraineur':  'en',
  'elo':         'el',
  'terrain':     'tr',
  'divergence':  'dv',
  'poidsRel':    'pr',
  'progression': 'pg',
  'mouvCote':    'mc',
  'placeDepart': 'pd',
};

// Labels affichage court
const Map<String, String> kLabelsSimu = {
  'f':  'A · Forme',
  'g':  'B · Gains',
  'r':  'C · Record',
  'c':  'D · Cote',
  'k':  'E · Constance',
  'v':  'F · Victoires',
  'd':  'G · Discipline',
  'ds': 'H · Distance',
  'j':  'I · Jockey',
  'rp': 'J · Repos',
  'hp': 'K · Hippodrome',
  'en': 'L · Entraîneur',
  'el': 'M · ELO',
  'tr': 'N · Terrain',
  'dv': 'O · Divergence',
  'pr': 'P · Poids',
  'pg': 'Q · Progression',
  'mc': 'R · Mouv.Cote',
  'pd': 'S · Départ',
};

// ── Paramètres d'une simulation ───────────────────────────────────────────────
class SimulationParams {
  /// 'Toutes' | 'Plat' | 'Trot' | 'Obstacle'
  final String discipline;

  /// Multiplicateurs par clé courte de critère (ex: 'ds' → 1.4)
  /// Clés absentes = multiplicateur 1.0 (neutre)
  final Map<String, double> multiplicateurs;

  const SimulationParams({
    this.discipline = 'Toutes',
    this.multiplicateurs = const {},
  });

  /// Multiplicateur effectif pour un critère (défaut 1.0)
  double mult(String cleCourtCritere) =>
      multiplicateurs[cleCourtCritere] ?? 1.0;

  /// Retourne une copie avec un multiplicateur modifié
  SimulationParams copyWith({
    String? discipline,
    Map<String, double>? multiplicateurs,
  }) => SimulationParams(
    discipline:      discipline      ?? this.discipline,
    multiplicateurs: multiplicateurs ?? this.multiplicateurs,
  );

  /// Réinitialise tous les multiplicateurs à 1.0
  SimulationParams reset() => SimulationParams(discipline: discipline);

  /// Sérialisation pour SharedPreferences (candidat)
  Map<String, dynamic> toJson() => {
    'discipline':      discipline,
    'multiplicateurs': multiplicateurs,
  };

  factory SimulationParams.fromJson(Map<String, dynamic> j) => SimulationParams(
    discipline: j['discipline'] as String? ?? 'Toutes',
    multiplicateurs: (j['multiplicateurs'] as Map<String, dynamic>? ?? {})
        .map((k, v) => MapEntry(k, (v as num).toDouble())),
  );
}

// ── Bloc stats pour une période ───────────────────────────────────────────────
class SimBloc {
  final int    nbCourses;
  final int    nbCoursesRoi;    // courses avec dividende/cote utilisable
  final double top1;            // % favori IA gagne
  final double top3;            // % au moins 1 des top3 IA dans top3 réel
  final double top5;            // % au moins 1 des top5 IA dans top5 réel
  final double roi;             // (retour - mise) / mise * 100
  final double gainNet;         // en €, mise = 1€ par course
  final int    outsiders;       // chevaux cote > 10 dans Top3 simulé ET Top3 réel

  const SimBloc({
    this.nbCourses    = 0,
    this.nbCoursesRoi = 0,
    this.top1         = 0,
    this.top3         = 0,
    this.top5         = 0,
    this.roi          = 0,
    this.gainNet      = 0,
    this.outsiders    = 0,
  });

  /// Fiabilité de l'échantillon
  String get fiabiliteLabel {
    if (nbCourses < 30)  return '⚠️ Très faible (<30)';
    if (nbCourses < 50)  return '🟡 Indicatif (30–50)';
    if (nbCourses < 150) return '🟠 Intéressant (50–150)';
    return '🟢 Exploitable (>150)';
  }

  bool get fiable => nbCourses >= 50;
}

// ── Résultat complet d'une simulation ────────────────────────────────────────
class SimulationResultat {
  final SimulationParams params;

  // IA actuelle (classement réel enregistré)
  final SimBloc avant;         // historique complet
  final SimBloc avant30j;      // 30 derniers jours
  final SimBloc avant7j;       // 7 derniers jours

  // IA simulée (classement recalculé avec multiplicateurs)
  final SimBloc apres;
  final SimBloc apres30j;
  final SimBloc apres7j;

  final DateTime calculeLe;

  const SimulationResultat({
    required this.params,
    required this.avant,
    required this.avant30j,
    required this.avant7j,
    required this.apres,
    required this.apres30j,
    required this.apres7j,
    required this.calculeLe,
  });

  /// Verdict automatique basé sur historique complet
  String get verdict {
    final dTop3 = apres.top3 - avant.top3;
    final dRoi  = apres.roi  - avant.roi;

    if (!apres.fiable) return '⚠️ Échantillon insuffisant pour verdict';
    if (dTop3 > 3.0 && dRoi > 0) return '🟢 Piste prometteuse';
    if (dRoi  > 2.0 && dTop3 >= -1.0) return '🟡 Plus rentable, stabilité ok';
    if (dTop3 > 3.0 && dRoi < -1.0) return '🟠 Plus sûr mais moins rentable';
    if (dTop3 < -3.0 && dRoi < 0)   return '🔴 Défavorable';
    return '⬜ Neutre — pas d\'amélioration significative';
  }

  /// Sérialisation complète pour SharedPreferences (candidat journal)
  Map<String, dynamic> toJson() => {
    'params':     params.toJson(),
    'calculeLe':  calculeLe.toIso8601String(),
    'verdict':    verdict,
    'avant':  _blocToJson(avant),
    'apres':  _blocToJson(apres),
    'avant30j': _blocToJson(avant30j),
    'apres30j': _blocToJson(apres30j),
    'avant7j':  _blocToJson(avant7j),
    'apres7j':  _blocToJson(apres7j),
  };

  static Map<String, dynamic> _blocToJson(SimBloc b) => {
    'nbCourses':    b.nbCourses,
    'nbCoursesRoi': b.nbCoursesRoi,
    'top1':    b.top1,
    'top3':    b.top3,
    'top5':    b.top5,
    'roi':     b.roi,
    'gainNet': b.gainNet,
    'outsiders': b.outsiders,
  };
}

// ── Candidat sauvegardé ───────────────────────────────────────────────────────
class SimulationCandidat {
  final String id;          // UUID simple (timestamp)
  final String nom;         // nom libre
  final DateTime date;
  final SimulationResultat resultat;

  const SimulationCandidat({
    required this.id,
    required this.nom,
    required this.date,
    required this.resultat,
  });

  Map<String, dynamic> toJson() => {
    'id':  id,
    'nom': nom,
    'date': date.toIso8601String(),
    'resultat': resultat.toJson(),
  };
}
