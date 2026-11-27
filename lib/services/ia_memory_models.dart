// imports unused supprimés (dart:convert, dart:math, foundation, zt_models)

// ══════════════════════════════════════════════════════════════════════════════
//  ia_memory_models.dart — Classes de données de IaMemoryService
//  Extrait de ia_memory_service.dart.
//  IaMemoryService lui-même + les classes du bas (_DiscStats, AnalyseJourneeResultat,
//  etc.) restent dans ia_memory_service.dart car elles ont des interdépendances.
// ══════════════════════════════════════════════════════════════════════════════

class ScoresCriteres {
  final double forme;       // A - score musique récente
  final double gains;       // B - score gains carrière
  final double record;      // C - score record/vitesse
  final double cote;        // D - score cote marché
  final double constance;   // E - score régularité
  final double victoires;   // F - score victoires récentes
  final double discipline;  // G - score compatibilité discipline
  // ★ v4.0 : Nouveaux critères enrichis — inclus dans l'apprentissage
  final double distSpec;    // H - score forme distance spécifique (8%)
  final double jockey;      // I - score jockey/driver (7%)
  final double repos;       // J - score fraîcheur physique (3%)
  // ★ v7.0 : Critère hippodrome — spécialité de circuit
  final double hippo;       // K - score spécialité hippodrome (4%)
  // ★ v8.0 : Nouveaux critères Lot 1
  final double entraineur;  // L - score entraîneur (4%)
  final double elo;         // M - score ELO dynamique (5%)
  // ★ v9.0 : Nouveaux critères Lot 2
  final double terrain;     // N - score performance sur ce terrain (5%)
  final double divergence;  // O - divergence forme/cote, coup préparé (4%)
  final double poidsRel;    // P - poids porté relatif (3%)
  final double progression; // Q - progression de carrière (3%)
  final double mouvCote;    // ★ v9.92 R - mouvement de cote (6%)
  final double placeDepart; // ★ v9.93 S - place au départ/corde (3%)

  const ScoresCriteres({
    required this.forme,
    required this.gains,
    required this.record,
    required this.cote,
    required this.constance,
    required this.victoires,
    required this.discipline,
    this.distSpec  = 50.0,
    this.jockey    = 50.0,
    this.repos     = 50.0,
    this.hippo       = 50.0, // ★ v7.0 : neutre par défaut
    this.entraineur  = 50.0, // ★ v8.0 : neutre par défaut
    this.elo         = 50.0, // ★ v8.0 : neutre si pas de données ELO
    this.terrain     = 50.0, // ★ v9.0 : neutre si pas de données terrain
    this.divergence  = 50.0, // ★ v9.0 : neutre par défaut
    this.poidsRel    = 50.0, // ★ v9.0 : neutre si pas de poids
    this.progression = 50.0, // ★ v9.0 : neutre par défaut
    this.mouvCote    = 50.0, // ★ v9.92 : neutre si hors fenêtre 30 min
    this.placeDepart = 50.0, // ★ v9.93 : neutre si données indispo
  });

  Map<String, dynamic> toJson() => {
    'f': forme, 'g': gains, 'r': record, 'c': cote,
    'k': constance, 'v': victoires, 'd': discipline,
    'ds': distSpec, 'j': jockey, 'rp': repos,
    'hp': hippo,   // ★ v7.0 : hippodrome
    'en': entraineur, // ★ v8.0 : entraîneur
    'el': elo,        // ★ v8.0 : ELO
    'tr': terrain,    // ★ v9.0 : terrain
    'dv': divergence, // ★ v9.0 : divergence forme/cote
    'pr': poidsRel,   // ★ v9.0 : poids relatif
    'pg': progression,// ★ v9.0 : progression
    'mc': mouvCote,   // ★ v9.92 : mouvement de cote
    'pd': placeDepart, // ★ v9.93 : place au départ
  };

  factory ScoresCriteres.fromJson(Map<String, dynamic> j) => ScoresCriteres(
    forme:      (j['f']  as num?)?.toDouble() ?? 50.0,
    gains:      (j['g']  as num?)?.toDouble() ?? 50.0,
    record:     (j['r']  as num?)?.toDouble() ?? 50.0,
    cote:       (j['c']  as num?)?.toDouble() ?? 50.0,
    constance:  (j['k']  as num?)?.toDouble() ?? 50.0,
    victoires:  (j['v']  as num?)?.toDouble() ?? 50.0,
    discipline: (j['d']  as num?)?.toDouble() ?? 50.0,
    distSpec:   (j['ds'] as num?)?.toDouble() ?? 50.0,
    jockey:     (j['j']  as num?)?.toDouble() ?? 50.0,
    repos:      (j['rp'] as num?)?.toDouble() ?? 50.0,
    hippo:      (j['hp'] as num?)?.toDouble() ?? 50.0,
    entraineur: (j['en'] as num?)?.toDouble() ?? 50.0, // ★ v8.0
    elo:        (j['el'] as num?)?.toDouble() ?? 50.0, // ★ v8.0
    terrain:    (j['tr'] as num?)?.toDouble() ?? 50.0, // ★ v9.0
    divergence: (j['dv'] as num?)?.toDouble() ?? 50.0, // ★ v9.0
    poidsRel:   (j['pr'] as num?)?.toDouble() ?? 50.0, // ★ v9.0
    progression:(j['pg'] as num?)?.toDouble() ?? 50.0, // ★ v9.0
    mouvCote:   (j['mc'] as num?)?.toDouble() ?? 50.0, // ★ v9.92
    placeDepart:(j['pd'] as num?)?.toDouble() ?? 50.0, // ★ v9.93
  );

  factory ScoresCriteres.neutre() => const ScoresCriteres(
    forme: 50, gains: 50, record: 50,
    cote: 50, constance: 50, victoires: 50, discipline: 50,
    distSpec: 50, jockey: 50, repos: 50, hippo: 50,
    entraineur: 50, elo: 50, // ★ v8.0
    terrain: 50, divergence: 50, poidsRel: 50, progression: 50, // ★ v9.0
    mouvCote: 50, // ★ v9.92
    placeDepart: 50, // ★ v9.93
  );

  /// Retourne la valeur d'un critère par son nom (utilisé par l'algorithme de gradient)
  double valeurPourCritere(String c) {
    switch (c) {
      case 'forme':      return forme;
      case 'gains':      return gains;
      case 'record':     return record;
      case 'cote':       return cote;
      case 'constance':  return constance;
      case 'victoires':  return victoires;
      case 'discipline': return discipline;
      case 'distSpec':   return distSpec;
      case 'jockey':     return jockey;
      case 'repos':      return repos;
      case 'hippo':      return hippo;
      case 'entraineur': return entraineur; // ★ v8.0
      case 'elo':        return elo;        // ★ v8.0
      case 'mouvCote':  return mouvCote;    // ★ v9.92
      case 'placeDepart': return placeDepart; // ★ v9.93
      case 'terrain':    return terrain;    // ★ v9.0
      case 'divergence': return divergence; // ★ v9.0
      case 'poidsRel':   return poidsRel;   // ★ v9.0
      case 'progression':return progression;// ★ v9.0
      default:           return 50.0;
    }
  }
}

// ─── ★ v10.38 : Pronostic premium du jour (étoile ⭐ calendrier) ─────────────
// Stocke courseKey + typePari + numeros + sourceWidget pour validation stricte.
// L'étoile ⭐ n'est accordée QUE si ce conseil exact (tous les 4 champs) est gagnant.
// Historique multi-jours dans IaMemoryService._premiumHistorique (90 jours).
class PremiumPronosticDuJour {
  final String       courseKey;    // ex: 'R1C5_01072025' — identifiant unique de la course
  final String       typePari;     // ex: 'Simple Gagnant', 'Quinté+' — type affiché dans le widget
  final List<String> numeros;      // numéros conseillés dans l'ordre IA (ex: ['3','7','1'])
  final String       sourceWidget; // widget source : 'conseilJour' | 'meilleurPari' |
                                   //   'topEquilibre' | 'plusSur' | 'plusRentable'

  const PremiumPronosticDuJour({
    required this.courseKey,
    required this.typePari,
    required this.numeros,
    required this.sourceWidget,
  });

  Map<String, dynamic> toJson() => {
    'courseKey':    courseKey,
    'typePari':     typePari,
    'numeros':      numeros,
    'sourceWidget': sourceWidget,
  };

  factory PremiumPronosticDuJour.fromJson(Map<String, dynamic> j) {
    return PremiumPronosticDuJour(
      courseKey:    j['courseKey']    as String? ?? '',
      typePari:     j['typePari']     as String? ?? '',
      sourceWidget: j['sourceWidget'] as String? ?? '',
      numeros: (j['numeros'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

// ─── ★ v10.57 : Série premium gagnante ───────────────────────────────────────
// Calculée par IaMemoryService.calculerStreakPremium() — lecture seule.
// Affichée dans ia_calendrier_tab quand jours >= 2.
class PremiumStreak {
  final String   sourceWidget; // 'conseilJour' | 'meilleurPari' | etc.
  final int      jours;        // nombre de jours consécutifs gagnants
  final DateTime dateFin;      // dernier jour de la série (date de référence)

  const PremiumStreak({
    required this.sourceWidget,
    required this.jours,
    required this.dateFin,
  });

  /// La série est affichable seulement à partir de 2 jours consécutifs.
  bool get actif => jours >= 2;

  /// Emoji selon la longueur de la série.
  String get emoji {
    if (jours >= 5) return '🏆';
    if (jours >= 3) return '🔥';
    return '⭐';
  }
}

// ─── Modèle de sélection figée d'un widget premium pour le jour J ────────────
// ★ v10.62 : utilisé pour figer les 5 widgets premium (conseilJour, meilleurPari,
//            topEquilibre, plusSur, plusRentable) une seule fois par jour.
//            Stocké dans 'premium_widgets_selection_jour_v1'.
//            Ne concerne PAS les pronostics généraux ni le calendrier.

class SelectionWidgetPremiumDuJour {
  final String dateKey;       // 'YYYY-MM-DD' — date de référence du widget
  final String sourceWidget;  // l'un des 5 : conseilJour|meilleurPari|topEquilibre|plusSur|plusRentable
  final String courseKey;     // clé unique de la course (non vide)
  final String typePari;      // type de pari valide (non vide)
  final List<String> numeros; // numéros de chevaux (non vide)
  final String? nomCourse;
  final String? hippodrome;
  final String? heure;
  final String? chevalNom;
  final double? score;
  final DateTime createdAt;

  const SelectionWidgetPremiumDuJour({
    required this.dateKey,
    required this.sourceWidget,
    required this.courseKey,
    required this.typePari,
    required this.numeros,
    required this.createdAt,
    this.nomCourse,
    this.hippodrome,
    this.heure,
    this.chevalNom,
    this.score,
  });

  /// Vérifie que la sélection contient les données minimales obligatoires.
  bool get estValide =>
      dateKey.isNotEmpty &&
      sourceWidget.isNotEmpty &&
      courseKey.isNotEmpty &&
      typePari.isNotEmpty &&
      numeros.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'dateKey':      dateKey,
        'sourceWidget': sourceWidget,
        'courseKey':    courseKey,
        'typePari':     typePari,
        'numeros':      numeros,
        'nomCourse':    nomCourse,
        'hippodrome':   hippodrome,
        'heure':        heure,
        'chevalNom':    chevalNom,
        'score':        score,
        'createdAt':    createdAt.toIso8601String(),
      };

  factory SelectionWidgetPremiumDuJour.fromJson(Map<String, dynamic> json) {
    return SelectionWidgetPremiumDuJour(
      dateKey:      json['dateKey']      as String? ?? '',
      sourceWidget: json['sourceWidget'] as String? ?? '',
      courseKey:    json['courseKey']    as String? ?? '',
      typePari:     json['typePari']     as String? ?? '',
      numeros:      List<String>.from(json['numeros'] as List? ?? const []),
      nomCourse:    json['nomCourse']    as String?,
      hippodrome:   json['hippodrome']   as String?,
      heure:        json['heure']        as String?,
      chevalNom:    json['chevalNom']    as String?,
      score:        (json['score']       as num?)?.toDouble(),
      createdAt:    DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

// ─── Modèle d'un pronostic enregistré ────────────────────────────────────────

class IaPronostic {
  final String courseKey;
  final String nomCourse;
  final String hippodrome;
  final String discipline;
  final DateTime datePronostic;

  // Classement IA : numéro → scoreIA normalisé (0-100)
  final Map<String, double> scoresIA;

  // Scores bruts par critère pour chaque cheval
  // numéro → ScoresCriteres (pour l'apprentissage par gradient)
  final Map<String, ScoresCriteres> scoresCriteres;

  // ★ v3 : Variance des scores IA (mesure de la clarté du champ)
  final double? varianceScores;

  // Résultat réel
  List<int>? arriveeReelle;
  DateTime? dateResultat;
  bool resultatsReels = false;

  // Métriques de performance
  int? rangFavoriIaDansArrivee;
  int? nbTop3DansArriveeReelle;
  int? nbTop5DansArriveeReelle;
  double? scorePerformance;

  // Diagnostic de l'apprentissage (ce qui a été appris)
  String? diagnosticApprentissage;

  // ★ v3 : Score de confiance prédit par l'IA avant la course
  double? confiancePredite;

  // ★ v4 : Type de pari conseillé par l'IA au moment du pronostic
  // (ex: 'Quinté+', 'Simple Gagnant', 'Tiercé', etc.)
  // Permet de comparer APRÈS la course si le conseil était bon
  String? typePariConseille;

  // ★ v5 : Taux de réussite historique (par type de pari) au moment où le pronostic est enregistré
  // Ex: Si au moment du pronostic l'IA a 60% de réussite sur Quinté+, cette valeur = 60.0
  // Permet de mesurer l'évolution du taux dans le temps
  double? tauxReussiteAuMoment;

  // ★ v5 : Précision IA synthèse des 3 indices (calculée lors de l'enregistrement ET après résultats)
  // = poidsCriteres * scoreIA_max + poidsConfiance * confiancePredite + poidsReussite * tauxReussite
  // Évolue avec les poids adaptatifs PoidsIndices
  double? precisionIA;

  // ★ v9.9 : Nom du cheval favori IA (ex: "PINK PANTHERA")
  String? favoriIaNom;

  // ★ v9.84 : Cote PMU décimale réelle du favori IA au moment du pronostic
  // (ex: 4.5 = 4,5 contre 1 au PMU). null si non disponible (pronostics antérieurs).
  // Permet un backtesting réaliste sans cotes fixes.
  double? coteFavoriPmu;

  // ★ v10.31 : Cotes PMU Simple Gagnant par numéro de cheval.
  // Rempli lors de l'enregistrement du résultat depuis E_SIMPLE_GAGNANT (rList complet).
  // Format : { '1': 2.10, '3': 5.40, '7': 12.60, ... }
  // Permet à la simulation de retrouver la cote de n'importe quel cheval choisi.
  Map<String, double> cotesPmuParNumero;

  IaPronostic({
    required this.courseKey,
    required this.nomCourse,
    required this.hippodrome,
    required this.discipline,
    required this.datePronostic,
    required this.scoresIA,
    this.scoresCriteres = const {},
    this.varianceScores,
    this.arriveeReelle,
    this.dateResultat,
    this.resultatsReels = false,
    this.rangFavoriIaDansArrivee,
    this.nbTop3DansArriveeReelle,
    this.nbTop5DansArriveeReelle,
    this.scorePerformance,
    this.diagnosticApprentissage,
    this.confiancePredite,
    this.typePariConseille,
    this.tauxReussiteAuMoment,
    this.precisionIA,
    this.favoriIaNom,
    this.coteFavoriPmu,
    this.cotesPmuParNumero = const {},
  });

  String? get favoriIA {
    if (scoresIA.isEmpty) return null;
    return scoresIA.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  List<String> get topNIA {
    final sorted = scoresIA.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  Map<String, dynamic> toJson() => {
    'courseKey': courseKey,
    'nomCourse': nomCourse,
    'hippodrome': hippodrome,
    'discipline': discipline,
    'datePronostic': datePronostic.toIso8601String(),
    'scoresIA': scoresIA,
    'scoresCriteres': scoresCriteres.map((k, v) => MapEntry(k, v.toJson())),
    'varianceScores': varianceScores,
    'arriveeReelle': arriveeReelle,
    'dateResultat': dateResultat?.toIso8601String(),
    'resultatsReels': resultatsReels,
    'rangFavoriIaDansArrivee': rangFavoriIaDansArrivee,
    'nbTop3DansArriveeReelle': nbTop3DansArriveeReelle,
    'nbTop5DansArriveeReelle': nbTop5DansArriveeReelle,
    'scorePerformance': scorePerformance,
    'diagnosticApprentissage': diagnosticApprentissage,
    'confiancePredite': confiancePredite,
    'typePariConseille': typePariConseille,
    'tauxReussiteAuMoment': tauxReussiteAuMoment,
    'precisionIA': precisionIA,
    'favoriIaNom': favoriIaNom,
    'coteFavoriPmu': coteFavoriPmu,
    'cotesPmuParNumero': cotesPmuParNumero,
  };

  factory IaPronostic.fromJson(Map<String, dynamic> j) {
    final scMap = <String, ScoresCriteres>{};
    final scRaw = j['scoresCriteres'] as Map<String, dynamic>? ?? {};
    for (final entry in scRaw.entries) {
      try {
        scMap[entry.key] =
            ScoresCriteres.fromJson(entry.value as Map<String, dynamic>);
      } catch (_) {}
    }
    return IaPronostic(
      courseKey: j['courseKey'] as String,
      nomCourse: j['nomCourse'] as String,
      hippodrome: j['hippodrome'] as String? ?? '',
      discipline: j['discipline'] as String? ?? '',
      datePronostic: DateTime.parse(j['datePronostic'] as String),
      scoresIA: Map<String, double>.from(
        (j['scoresIA'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      ),
      scoresCriteres: scMap,
      varianceScores: (j['varianceScores'] as num?)?.toDouble(),
      arriveeReelle: (j['arriveeReelle'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt()).toList(),
      dateResultat: j['dateResultat'] != null
          ? DateTime.parse(j['dateResultat'] as String)
          : null,
      resultatsReels: j['resultatsReels'] as bool? ?? false,
      rangFavoriIaDansArrivee: j['rangFavoriIaDansArrivee'] as int?,
      nbTop3DansArriveeReelle: j['nbTop3DansArriveeReelle'] as int?,
      nbTop5DansArriveeReelle: j['nbTop5DansArriveeReelle'] as int?,
      scorePerformance: (j['scorePerformance'] as num?)?.toDouble(),
      diagnosticApprentissage: j['diagnosticApprentissage'] as String?,
      confiancePredite: (j['confiancePredite'] as num?)?.toDouble(),
      typePariConseille: j['typePariConseille'] as String?,
      tauxReussiteAuMoment: (j['tauxReussiteAuMoment'] as num?)?.toDouble(),
      precisionIA: (j['precisionIA'] as num?)?.toDouble(),
      favoriIaNom: j['favoriIaNom'] as String?,
      coteFavoriPmu: (j['coteFavoriPmu'] as num?)?.toDouble(),
      cotesPmuParNumero: (() {
        final raw = j['cotesPmuParNumero'] as Map<String, dynamic>?;
        if (raw == null) return <String, double>{};
        return raw.map((k, v) => MapEntry(k, (v as num).toDouble()));
      })(),
    );
  }
}

// ─── Poids adaptatifs (GLOBAUX + PAR DISCIPLINE) ──────────────────────────────

// ─── Poids des 3 indices de Pr\u00e9cision IA (appris par gradient apr\u00e8s chaque analyse) ─
//
//  Synth\u00e8se : Pr\u00e9cisionIA = poidsCriteres*scoreMulticrit + poidsConfiance*confianceIA
//                           + poidsReussite*tauxR\u00e9ussite
//
//  Base initiale : 40% / 35% / 25%
//  \u00c9volue dans [15%, 55%] apr\u00e8s chaque analyse journali\u00e8re (delta = 0.01/jour)
//  L'indice le plus pr\u00e9dictif gagne en poids, le moins pr\u00e9dictif en perd.
//  La somme reste toujours = 1.0
// ─────────────────────────────────────────────────────────────────────────────────────
class PoidsIndices {
  double poidsCriteres;   // Score multicrit\u00e8res (10 crit\u00e8res pond\u00e9r\u00e9s) — d\u00e9faut 40%
  double poidsConfiance;  // Confiance IA (variance/domination favori) — d\u00e9faut 35%
  double poidsReussite;   // Taux de r\u00e9ussite historique par type de pari — d\u00e9faut 25%

  static const double _min = 0.15; // borne min de chaque poids
  static const double _max = 0.55; // borne max de chaque poids

  PoidsIndices({
    this.poidsCriteres  = 0.40,
    this.poidsConfiance = 0.35,
    this.poidsReussite  = 0.25,
  });

  /// Calcule la Pr\u00e9cisionIA synth\u00e8se des 3 indices (0-100)
  double calculerPrecision({
    required double scoreCriteres,   // 0-100 : meilleur score IA dans la course
    required double confianceIA,     // 0-100 : confiance pr\u00e9dite
    required double tauxReussite,    // 0-100 : taux de r\u00e9ussite du type de pari conseill\u00e9
  }) {
    return (scoreCriteres * poidsCriteres +
            confianceIA   * poidsConfiance +
            tauxReussite  * poidsReussite).clamp(0.0, 100.0);
  }

  /// Mise \u00e0 jour apr\u00e8s une analyse : l'indice le plus pr\u00e9dictif gagne du poids.
  /// deltasCriteres/Confiance/Reussite : fraction de courses o\u00f9 l'indice \u00e9tait pr\u00e9dictif (0-1)
  void mettreAJourDepuisDeltas({
    required double deltasCriteres,
    required double deltasConfiance,
    required double deltasReussite,
  }) {
    const double lr = 0.01; // taux d'apprentissage doux (1% par jour)
    poidsCriteres  += lr * (deltasCriteres - 0.33);
    poidsConfiance += lr * (deltasConfiance - 0.33);
    poidsReussite  += lr * (deltasReussite  - 0.33);
    _normaliserEtClamper();
  }

  void _normaliserEtClamper() {
    poidsCriteres  = poidsCriteres.clamp(_min, _max);
    poidsConfiance = poidsConfiance.clamp(_min, _max);
    poidsReussite  = poidsReussite.clamp(_min, _max);
    final total = poidsCriteres + poidsConfiance + poidsReussite;
    if (total > 0) {
      poidsCriteres  /= total;
      poidsConfiance /= total;
      poidsReussite  /= total;
    }
  }

  Map<String, dynamic> toJson() => {
    'pc': poidsCriteres,
    'pco': poidsConfiance,
    'pr': poidsReussite,
  };

  factory PoidsIndices.fromJson(Map<String, dynamic> j) => PoidsIndices(
    poidsCriteres:  (j['pc']  as num?)?.toDouble() ?? 0.40,
    poidsConfiance: (j['pco'] as num?)?.toDouble() ?? 0.35,
    poidsReussite:  (j['pr']  as num?)?.toDouble() ?? 0.25,
  );

  String get resume =>
    'Crit\u00e8res:${(poidsCriteres*100).toStringAsFixed(0)}% '
    'Confiance:${(poidsConfiance*100).toStringAsFixed(0)}% '
    'R\u00e9ussite:${(poidsReussite*100).toStringAsFixed(0)}%';
}

// ─────────────────────────────────────────────────────────────────────────────

class IaPoidsAdaptatifs {
  double forme;
  double gains;
  double record;
  double cote;
  double constance;
  double victoires;
  double discipline;
  // ★ v4.1 : Poids adaptatifs pour les critères enrichis (ajustables par gradient)
  double distSpec;  // Forme distance spécifique (défaut 8%)
  double jockey;    // Score jockey/driver (défaut 7%)
  double repos;     // Fraîcheur physique (défaut 3%)
  // ★ v7.0 : Spécialité hippodrome
  double hippo;        // Score spécialité circuit (défaut 4%)
  // ★ v8.0 : Nouveaux critères Lot 1
  double entraineur;   // Score entraîneur (défaut 4%)
  double elo;          // Score ELO dynamique (défaut 5%)
  // ★ v9.0 : Nouveaux critères Lot 2
  double terrain;      // Score terrain (défaut 5%)
  double divergence;   // Divergence forme/cote (défaut 4%)
  double poidsRel;     // Poids porté relatif (défaut 3%)
  double progression;  // Progression carrière (défaut 3%)
  double mouvCote;     // ★ v9.92 R - Mouvement de cote (défaut 6%)
  double placeDepart;  // ★ v9.93 S - Place au départ/corde (défaut 3%)

  // ★ v3 : Poids spécifiques par discipline
  // Chaque discipline peut avoir ses propres pondérations apprises
  Map<String, Map<String, double>> poidsParDiscipline;

  // Compteur de mises à jour pour affichage
  int nbMisesAJour;

  // ★ v3 : Indice de calibration (mesure si les prédictions de confiance sont fiables)
  double calibrationScore; // 0-100, 50 = neutre, >50 = bien calibré

  // ★ v3.1 : Momentum du gradient (mémorise la tendance pour éviter les oscillations)
  Map<String, double> dernierGradient;

  // ★ v9.92 POINT 8 : Corrélations détectées entre critères (paire 'c1|c2' → r)
  // Stockées pour affichage dans IA Stats — pas de modification des poids
  Map<String, double> correlations;

  // ★ v5 : Poids des 3 indices de PrécisionIA (appris par gradient après chaque analyse)
  PoidsIndices poidsIndices;

  IaPoidsAdaptatifs({
    // ★ BL1-A19 — CE COMMENTAIRE ÉTAIT FAUX, IL EST CORRIGÉ PAR LA MESURE.
    //
    //   Il affirmait : « v8.0 : poids rééquilibrés — somme = 1.00 ✅ ».
    //   MESURE des valeurs réellement déclarées ci-dessous (19 critères) :
    //       0,25 + 0,13 + 0,10 + 0,08 + 0,09 + 0,04 + 0,02 = 0,71 (base)
    //     + 0,08 + 0,07 + 0,03 + 0,04 + 0,04 + 0,05 + 0,05 + 0,04
    //     + 0,03 + 0,03 + 0,06 + 0,03                     = 0,55 (enrichis)
    //     → SOMME DÉCLARÉE = 1,26, et non 1,00.
    //
    //   La somme ne devient 1,00000000 qu'APRÈS `clamp()` puis `normaliser()`,
    //   MESURÉ : base 0,71 / enrichis 0,55 → fraction enrichie 0,4365, écrêtée
    //   à `targetEnrichi = 0,40` (plafond) → base 0,60 / enrichis 0,40, soit
    //   une somme de 1,00000000 exactement. Répartition obtenue : forme 0,2113,
    //   gains 0,1099, record 0,0845…
    //
    //   ⚠️ CE N'EST PAS UN DÉFAUT DE CALCUL, C'EST UN COMMENTAIRE FAUX : les
    //      valeurs brutes ne sont pas normalisées « à la déclaration ». Un
    //      lecteur qui somme les littéraux obtient 1,26 et croit à un bug.
    //   ⚠️ AUCUN POIDS N'EST MODIFIÉ ICI : la correction est documentaire.
    //      L'arbitrage sur l'écrêtage à 0,40 et sur la somme brute reste
    //      une DÉCISION UTILISATEUR (BL1-A04/A06) : elle toucherait la
    //      formule, ce qui est interdit sans autorisation.
    this.forme      = 0.25,
    this.gains      = 0.13,
    this.record     = 0.10,
    this.cote       = 0.08,
    this.constance  = 0.09,
    this.victoires  = 0.04,
    this.discipline = 0.02,
    // ★ v4.1 : Critères enrichis désormais adaptatifs
    this.distSpec   = 0.08,  // Forme distance spécifique
    this.jockey     = 0.07,  // Impact jockey/driver
    this.repos      = 0.03,  // Fraîcheur physique
    this.hippo       = 0.04,  // ★ v7.0 : spécialité hippodrome
    this.entraineur  = 0.04,  // ★ v8.0 : entraîneur
    this.elo         = 0.05,  // ★ v8.0 : ELO dynamique
    // ★ v9.0 : Nouveaux critères Lot 2 — redistribués depuis forme/gains/record
    this.terrain     = 0.05,  // Conditions de terrain
    this.divergence  = 0.04,  // Coup préparé (divergence forme/cote)
    this.poidsRel    = 0.03,  // Poids porté relatif (galop)
    this.progression = 0.03,  // Progression de carrière
    this.mouvCote    = 0.06,  // ★ v9.92 : Mouvement de cote (signal informé)
    this.placeDepart = 0.03,  // ★ v9.93 : Place au départ (corde)
    // ★ BL1-A19 — CE COMMENTAIRE ÉTAIT FAUX LUI AUSSI, CORRIGÉ PAR LA MESURE.
    //   Il affirmait : « Total brut ≈ 1.07 → normaliser() ramène à 1.00 ».
    //   MESURE : total brut RÉEL = 1,26 (voir le commentaire en tête du
    //   constructeur). L'écart 1,07 → 1,26 n'est pas une coquille : c'est
    //   l'accumulation de critères ajoutés (terrain, divergence, poidsRel,
    //   progression, mouvCote, placeDepart) dont le total n'a jamais été
    //   réactualisé dans la documentation.
    //   ⚠️ Aucun poids n'est modifié : la correction est documentaire.
    Map<String, Map<String, double>>? poidsParDiscipline,
    this.nbMisesAJour = 0,
    this.calibrationScore = 50.0,
    Map<String, double>? dernierGradient,
    PoidsIndices? poidsIndices,
    Map<String, double>? correlations,
  }) : poidsParDiscipline = poidsParDiscipline ?? {},
       dernierGradient = dernierGradient ?? {},
       poidsIndices = poidsIndices ?? PoidsIndices(),
       correlations = correlations ?? {};

  /// Récupère les poids adaptés à une discipline donnée.
  /// Si < 3 courses pour cette discipline, retourne les poids globaux.
  Map<String, double> poidsEffectifsPourDiscipline(String disc) {
    final ppd = poidsParDiscipline[normaliseDiscipline(disc)];
    if (ppd == null || ppd.isEmpty) {
      // ★ v5.0 : fallback complet avec les 10 critères
      return {
        'forme': forme, 'gains': gains, 'record': record,
        'cote': cote, 'constance': constance,
        'victoires': victoires, 'discipline': discipline,
        'distSpec': distSpec, 'jockey': jockey, 'repos': repos,
        'hippo': hippo,
        'entraineur': entraineur, // ★ v8.0
        'elo': elo,               // ★ v8.0
        'terrain': terrain,       // ★ v9.0
        'divergence': divergence, // ★ v9.0
        'poidsRel': poidsRel,     // ★ v9.0
        'progression': progression, // ★ v9.0
    'mouvCote':    mouvCote,    // ★ v9.92
    'placeDepart': placeDepart, // ★ v9.93
      };
    }
    // Si la map discipline n'a pas toutes les clés (ancien format), compléter avec les globaux
    // ★ v9.95 audit : mouvCote (R) et placeDepart (S) ajoutés — 12 critères complétés
    final result = Map<String, double>.from(ppd);
    result['distSpec']   ??= distSpec;
    result['jockey']     ??= jockey;
    result['repos']      ??= repos;
    result['hippo']      ??= hippo;
    result['entraineur'] ??= entraineur; // ★ v8.0
    result['elo']        ??= elo;        // ★ v8.0
    result['terrain']    ??= terrain;    // ★ v9.0
    result['divergence'] ??= divergence; // ★ v9.0
    result['poidsRel']   ??= poidsRel;   // ★ v9.0
    result['progression']??= progression;// ★ v9.0
    result['mouvCote']   ??= mouvCote;   // ★ v9.92
    result['placeDepart']??= placeDepart;// ★ v9.93
    return result;
  }

  static String normaliseDiscipline(String d) {
    final lower = d.toLowerCase();
    if (lower.contains('trot') && lower.contains('att')) return 'trot_attele';
    if (lower.contains('trot') && lower.contains('mont')) return 'trot_monte';
    if (lower.contains('trot')) return 'trot_attele';
    // ★ v9.98 : course.type = "Attelé" ou "Monté" sans le mot "trot" → jamais matché avant
    if (lower.contains('att')) return 'trot_attele'; // "Attelé" → trot_attele
    if (lower.contains('mont')) return 'trot_monte';  // "Monté" → trot_monte
    if (lower.contains('plat')) return 'plat';
    if (lower.contains('haies') || lower.contains('obstacle') || lower.contains('steeple') || lower.contains('cross')) return 'obstacle';
    return 'global';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ★★ BL1-A22 (27/11/2026) — D-1 : MOTEUR DE CONTRAINTES UNIQUE ET IDEMPOTENT
  //
  //  CE QUI ÉTAIT FAUX AVANT (mesuré, voir test/audit/poids_plafonds_contrat_test.dart) :
  //    • `clamp()` appliquait les 19 bornes individuelles PUIS `normaliser()`,
  //      qui remettait à l'échelle chaque groupe. Le facteur d'échelle
  //      (target/total) pouvait donc SORTIR un poids de ses bornes : mesuré
  //      19/19 plafonds franchissables, et la sauvegarde réelle du 13/11/2026
  //      portait cote = 0,401813880733 > 0,40 et victoires = 0,150680205275
  //      > 0,15.
  //    • `clamp()` n'était pas idempotent : deux appels successifs SANS aucun
  //      apprentissage déplaçaient les poids (dérive mesurée 2,6189 % de la
  //      part enrichie avant convergence).
  //    • `clampDiscipline()` réappliquait des bornes DIFFÉRENTES de `clamp()`
  //      (son plafond `divergence` valait 0,10 au lieu de 0,08) puis divisait
  //      par le total, ce qui écrasait à nouveau les bornes : D-2.
  //
  //  CE QUI EST GARANTI MAINTENANT, quand les contraintes sont compatibles :
  //    C1  Σ des 19 poids = 1, à 1e-9 près.
  //    C2  19 planchers individuels respectés.
  //    C3  19 plafonds individuels respectés.
  //    C4  part enrichie dans [0,18 ; 0,40].
  //    C5  aucune valeur négative.
  //    C6  aucun NaN, aucune valeur infinie.
  //    C7  idempotence à 1e-12 (deux appels = un appel).
  //    C8  conservation d'une table déjà conforme, à 1e-12.
  //    C9  déterminisme (aucun aléatoire, aucun ordre d'itération dépendant).
  //    C10 aucune dérive sans nouvel apprentissage (= conséquence de C7).
  //
  //  MÉTHODE : « projection à budgets de groupe + remplissage par écumoire ».
  //  Justification du choix, et pourquoi pas un simple « clip puis renormalise
  //  en boucle » (qui ne converge pas toujours et dépend de l'ordre) :
  //   1. On CLIPPE d'abord (C2, C3, C5, C6) : opération locale, sans effet de
  //      bord, qui ne touche que les poids réellement hors bornes.
  //   2. On fixe le budget de chaque groupe (C4) : budget des enrichis = part
  //      courante ramenée dans [0,18 ; 0,40], budget de la base = 1 − part.
  //      Leur somme vaut 1 PAR CONSTRUCTION, donc C1 est structurel, pas
  //      numérique : il n'y a pas d'arrondi cumulé à corriger.
  //   3. Sur chaque groupe, on cherche λ tel que
  //         Σ_k clip(λ · w_k, plancher_k, plafond_k) = budget
  //      La fonction λ ↦ Σ est continue et CROISSANTE (somme de fonctions
  //      croissantes), donc STRICTEMENT monotone dès qu'un poids n'est pas
  //      saturé : la solution est UNIQUE. Existence garantie dès que
  //         Σ planchers du groupe ≤ budget ≤ Σ plafonds du groupe
  //      ce qui est vrai par construction des budgets. Recherche par
  //      dichotomie : convergence linéaire, 200 itérations suffisent très
  //      largement pour atteindre la précision machine.
  //   4. Ce remplissage est la projection euclidienne du vecteur sur
  //      l'intersection {bornes} ∩ {somme du groupe = budget} lorsque λ est
  //      le multiplicateur de Lagrange : il MINIMISE Σ (w_k − w_k_brut)²
  //      sous les contraintes. C'est ce qui donne la meilleure conservation
  //      possible des évolutions proposées par le gradient, à contraintes
  //      égales. C'est la métrique de conservation retenue : distance
  //      euclidienne, et non un ratio arbitraire.
  //   5. Un critère DÉJÀ à sa borne ne bouge pas, et ne peut pas « voler » de
  //      poids à ses voisins : il reste saturé, et le remplissage ne
  //      redistribue qu'entre les critères encore libres.
  //
  //  AUCUN BIAIS D'ORDRE : `normaliser()`, `clamp()` et `clampDiscipline()`
  //  n'utilisent plus de Map itérée pour décider quoi que ce soit. Les bornes
  //  sont lues via `bornesIndividuelles()`, qui retourne une Map littérale
  //  d'ordre fixe, et les sommes passent par `kClesOrdonnees` (liste figée).
  //  Deux exécutions donnent donc exactement le même résultat.
  //
  //  ⚠️ CE QUI N'EST PAS TOUCHÉ ICI : les 19 poids initiaux, les 19 planchers,
  //     les 19 plafonds, les contraintes collectives 0,18/0,40, le gradient
  //     descent, ses coefficients, son momentum, les formules de score,
  //     `_normaliserScores`, les seuils, la calibration, le TOP3 Learning,
  //     les calculs ELO et les mécanismes PMU. Cette réécriture ne concerne
  //     QUE l'application des contraintes aux pondérations.
  // ═══════════════════════════════════════════════════════════════════════════

  /// Les 19 clés, dans un ordre FIXE. Toute somme de poids passe par cette
  /// liste, jamais par une itération de Map (dont l'ordre n'est pas garanti).
  static const List<String> kClesOrdonnees = <String>[
    'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
    'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
    'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote',
    'placeDepart',
  ];

  /// Les 7 critères de BASE.
  static const List<String> kClesBase = <String>[
    'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  ];

  /// Les 12 critères ENRICHIS.
  static const List<String> kClesEnrichies = <String>[
    'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
    'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote',
    'placeDepart',
  ];

  /// Plancher collectif enrichi.
  static const double kPartEnrichieMin = 0.18;

  /// Plafond collectif enrichi.
  static const double kPartEnrichieMax = 0.40;

  /// Somme des poids après contrainte. Tolérance documentée du contrat C1.
  static const double kToleranceSomme = 1e-9;

  /// Tolérance d'idempotence / de conservation (C7, C8).
  static const double kToleranceIdempotence = 1e-12;

  /// Bornes individuelles des 19 critères — SOURCE UNIQUE.
  ///
  /// ⚠️ C'ÉTAIT LE CŒUR DE D-2 : `clamp()` et `clampDiscipline()` portaient
  ///    deux copies de ces bornes, et elles avaient DIVERGÉ (`divergence`
  ///    plafonné à 0,08 d'un côté et 0,10 de l'autre). Il n'y a plus qu'une
  ///    seule définition, ci-dessous, utilisée par les deux.
  ///
  /// Les 12 planchers enrichis valent 0,005 (correction §2 du 27/11/2026) ;
  /// les 7 planchers de base et les 19 plafonds sont ceux du commit de
  /// référence b3a0107 et ne sont PAS modifiés.
  static Map<String, List<double>> bornesIndividuelles() =>
      const <String, List<double>>{
        'forme':      <double>[0.05,  0.55],
        'gains':      <double>[0.04,  0.40],
        'record':     <double>[0.03,  0.35],
        'cote':       <double>[0.05,  0.40],
        'constance':  <double>[0.03,  0.25],
        'victoires':  <double>[0.01,  0.15],
        'discipline': <double>[0.01,  0.10],
        'distSpec':   <double>[0.005, 0.18],
        'jockey':     <double>[0.005, 0.15],
        'repos':      <double>[0.005, 0.08],
        'hippo':      <double>[0.005, 0.10],
        'entraineur': <double>[0.005, 0.08],
        'elo':        <double>[0.005, 0.10],
        'terrain':    <double>[0.005, 0.10],
        'divergence': <double>[0.005, 0.08],
        'poidsRel':   <double>[0.005, 0.07],
        'progression':<double>[0.005, 0.08],
        'mouvCote':   <double>[0.005, 0.12],
        'placeDepart':<double>[0.005, 0.07],
      };

  /// Remplissage par écumoire : trouve λ tel que
  /// `Σ_k clip(λ · w_k, lo_k, hi_k) = budget`, puis renvoie les w_k projetés.
  ///
  /// Renvoie `null` si le budget est hors du domaine réalisable du groupe
  /// (cas qui ne peut survenir que si l'appelant passe un budget incohérent).
  static Map<String, double>? _remplirGroupe(
    Map<String, double> brut,
    List<String> cles,
    Map<String, List<double>> bornes,
    double budget,
  ) {
    var sommePlanchers = 0.0;
    var sommePlafonds = 0.0;
    for (final k in cles) {
      sommePlanchers += bornes[k]![0];
      sommePlafonds += bornes[k]![1];
    }
    if (budget < sommePlanchers - 1e-12 || budget > sommePlafonds + 1e-12) {
      return null; // groupe infaisable : l'appelant garde l'ancienne table
    }

    double sommePour(double lambda) {
      var s = 0.0;
      for (final k in cles) {
        final v = lambda * (brut[k] ?? 0.0);
        s += v < bornes[k]![0]
            ? bornes[k]![0]
            : (v > bornes[k]![1] ? bornes[k]![1] : v);
      }
      return s;
    }

    // Encadrement de λ. `sommePour` est croissante et continue.
    var bas = 0.0;
    var haut = 1.0;
    var garde = 0;
    while (sommePour(haut) < budget && garde < 64) {
      haut *= 2.0;
      garde++;
    }
    for (var i = 0; i < 200; i++) {
      final milieu = (bas + haut) / 2.0;
      if (sommePour(milieu) < budget) {
        bas = milieu;
      } else {
        haut = milieu;
      }
    }
    final lambda = (bas + haut) / 2.0;

    final out = <String, double>{};
    for (final k in cles) {
      final v = lambda * (brut[k] ?? 0.0);
      out[k] = v < bornes[k]![0]
          ? bornes[k]![0]
          : (v > bornes[k]![1] ? bornes[k]![1] : v);
    }

    // Correction résiduelle EXACTE. Après dichotomie il peut subsister un
    // écart de quelques ulp. On le répartit UNIQUEMENT sur les critères qui
    // ne sont pas saturés — ceux-là seuls peuvent encore bouger sans violer
    // une borne. Proportionnellement à leur marge, pour ne pas créer de biais.
    final ecart = budget - _sommeListe(out, cles);
    if (ecart != 0.0) {
      final libres = <String>[];
      var margeTotale = 0.0;
      for (final k in cles) {
        final lo = bornes[k]![0];
        final hi = bornes[k]![1];
        final v = out[k]!;
        final marge = (v > lo && v < hi)
            ? (ecart > 0 ? hi - v : v - lo)
            : 0.0;
        if (marge > 0) {
          libres.add(k);
          margeTotale += marge;
        }
      }
      if (libres.isNotEmpty && margeTotale > 0) {
        final reste = ecart.abs() < margeTotale ? ecart : (ecart > 0 ? margeTotale : -margeTotale);
        for (final k in libres) {
          final lo = bornes[k]![0];
          final hi = bornes[k]![1];
          final v = out[k]!;
          final marge = (ecart > 0 ? hi - v : v - lo);
          final part = reste * (marge / margeTotale);
          final nv = v + part;
          out[k] = nv < lo ? lo : (nv > hi ? hi : nv);
        }
      }
    }
    return out;
  }

  static double _sommeListe(Map<String, double> m, List<String> cles) {
    var s = 0.0;
    for (final k in cles) {
      s += m[k] ?? 0.0;
    }
    return s;
  }

  /// Projection complète sur le domaine réalisable — CŒUR UNIQUE du contrat.
  ///
  /// C'est LA seule fonction qui applique les contraintes. `normaliser()`,
  /// `clamp()` et `clampDiscipline()` l'appellent toutes les trois : il n'y a
  /// donc plus deux mécanismes concurrents pouvant diverger (D-2).
  ///
  /// `brut` doit contenir les 19 clés. Les valeurs `null`, `NaN`, infinies ou
  /// négatives sont ramenées à leur plancher (C5, C6) — c'est le seul cas où
  /// une valeur d'entrée est remplacée, et il est impossible qu'une valeur
  /// valide le soit.
  static Map<String, double> projeter(Map<String, double> brut) {
    final bornes = bornesIndividuelles();
    _compteurProjections++;

    // 1) Clip sur les bornes individuelles (C2, C3, C5, C6).
    //    ★★ §3 : les valeurs écartées sont TRACÉES, jamais silencieuses.
    final w = <String, double>{};
    final anomalies = <String>[];
    for (final k in kClesOrdonnees) {
      final b = bornes[k]!;
      final v = brut[k];
      if (v == null) {
        // Clé absente : cas normal (map partielle ou ancien format), NON tracé.
        w[k] = b[0];
      } else if (v.isNaN) {
        w[k] = b[0];
        anomalies.add('$k: NaN → plancher ${b[0]}');
      } else if (v.isInfinite) {
        w[k] = b[0];
        anomalies.add('$k: infini ($v) → plancher ${b[0]}');
      } else if (v < b[0]) {
        w[k] = b[0];
        // Une valeur NÉGATIVE est une anomalie ; un simple dépassement de
        // plancher (v ≥ 0) est le fonctionnement normal de la contrainte.
        if (v < 0) anomalies.add('$k: NÉGATIF ($v) → plancher ${b[0]}');
      } else if (v > b[1]) {
        w[k] = b[1];
      } else {
        w[k] = v;
      }
    }
    if (anomalies.isNotEmpty) {
      dernieresAnomaliesProjection = anomalies;
      dernierNumeroProjectionAvecAnomalie = _compteurProjections;
    }

    // 2) Budget des enrichis : part courante ramenée dans [0,18 ; 0,40] (C4).
    final sommeEnrichie = _sommeListe(w, kClesEnrichies);
    final sommeBase = _sommeListe(w, kClesBase);
    final total = sommeEnrichie + sommeBase;
    double part;
    if (total <= 0) {
      part = kPartEnrichieMin; // table dégénérée : on retombe sur le plancher
    } else {
      part = sommeEnrichie / total;
      if (part < kPartEnrichieMin) part = kPartEnrichieMin;
      if (part > kPartEnrichieMax) part = kPartEnrichieMax;
    }

    // 3) Remplissage de chaque groupe sur son budget (C1 par construction).
    final enrichis = _remplirGroupe(w, kClesEnrichies, bornes, part);
    final base = _remplirGroupe(w, kClesBase, bornes, 1.0 - part);

    if (enrichis == null || base == null) {
      // Domaine infaisable : on rend les poids seulement clippés. Cela ne peut
      // arriver que si planchers et plafonds sont incohérents entre eux — état
      // qui n'existe pas dans la configuration de référence ci-dessus. On ne
      // fabrique pas de valeur arbitraire.
      return w;
    }

    final out = <String, double>{};
    for (final k in kClesOrdonnees) {
      out[k] = kClesBase.contains(k) ? base[k]! : enrichis[k]!;
    }
    return out;
  }

  /// Applique la projection à l'instance (C1 → C10).
  ///
  /// Remplace l'ancien couple « bornes puis échelle », qui ne garantissait
  /// ni C3 ni C7.
  void normaliser() {
    final brut = <String, double>{
      for (final k in kClesOrdonnees) k: getPoids(k),
    };
    final projetes = projeter(brut);
    _ecrireDepuisMap(projetes);
  }

  /// Applique les contraintes aux 19 poids GLOBAUX puis à chaque discipline.
  ///
  /// C7 (idempotence) est vérifiée par `test/audit/poids_projection_test.dart` :
  /// `clamp()` appelé deux fois de suite sans apprentissage ne change plus rien.
  void clamp() {
    normaliser();
    // Les tables par discipline passent par la MÊME projection : plus aucune
    // divergence de bornes possible entre le global et le par-discipline.
    for (final key in poidsParDiscipline.keys.toList()) {
      clampDiscipline(poidsParDiscipline[key]!);
    }
  }

  /// Écrit les 19 champs depuis une Map de 19 poids.
  void _ecrireDepuisMap(Map<String, double> m) {
    forme      = m['forme']!;
    gains      = m['gains']!;
    record     = m['record']!;
    cote       = m['cote']!;
    constance  = m['constance']!;
    victoires  = m['victoires']!;
    discipline = m['discipline']!;
    distSpec   = m['distSpec']!;
    jockey     = m['jockey']!;
    repos      = m['repos']!;
    hippo      = m['hippo']!;
    entraineur = m['entraineur']!;
    elo        = m['elo']!;
    terrain    = m['terrain']!;
    divergence = m['divergence']!;
    poidsRel   = m['poidsRel']!;
    progression= m['progression']!;
    mouvCote   = m['mouvCote']!;
    placeDepart= m['placeDepart']!;
  }

  /// Lit les 19 champs dans une Map (les clés absentes valent 0, donc leur
  /// plancher après projection).
  Map<String, double> versMap() => <String, double>{
    for (final k in kClesOrdonnees) k: getPoids(k),
  };

  /// ★ v90 : retourne le poids global d'un critère par clé (pour diagnostic)
  double getPoids(String key) {
    switch (key) {
      case 'forme':      return forme;
      case 'gains':      return gains;
      case 'record':     return record;
      case 'cote':       return cote;
      case 'constance':  return constance;
      case 'victoires':  return victoires;
      case 'discipline': return discipline;
      case 'distSpec':   return distSpec;
      case 'jockey':     return jockey;
      case 'repos':      return repos;
      case 'hippo':      return hippo;
      case 'entraineur': return entraineur; // ★ v8.0
      case 'elo':        return elo;        // ★ v8.0
      case 'terrain':    return terrain;    // ★ v9.0
      case 'divergence': return divergence; // ★ v9.0
      case 'poidsRel':   return poidsRel;   // ★ v9.0
      case 'progression':return progression;// ★ v9.0
      case 'mouvCote':   return mouvCote;   // ★ v9.93
      case 'placeDepart':return placeDepart;// ★ v9.93
      default:           return 0.0;
    }
  }

  /// Trace des anomalies de la DERNIÈRE projection (NaN, infini, négatif).
  ///
  /// ★★ BL1-A24 (27/11/2026) — §3 : `projeter()` ramène à leur plancher les
  /// valeurs `NaN`, infinies ou `null`. Ce comportement est NÉCESSAIRE (C5/C6 :
  /// aucune valeur invalide ne doit entrer dans le calcul des scores), mais il
  /// ne doit pas MASQUER une anomalie du mécanisme d'apprentissage. Sans cette
  /// trace, un gradient devenu instable produirait des poids silencieusement
  /// remplacés, et l'incident serait invisible.
  /// Cette liste est donc alimentée à chaque fois qu'une valeur d'entrée est
  /// écartée, et lisible par l'appelant. Elle ne modifie AUCUNE valeur.
  static List<String> dernieresAnomaliesProjection = <String>[];

  /// Numéro de la dernière projection ayant signalé au moins une anomalie.
  /// Sert de sentinelle bon marché : `0` = aucune anomalie depuis le démarrage.
  static int dernierNumeroProjectionAvecAnomalie = 0;
  static int _compteurProjections = 0;

  /// Applique la projection à une table de discipline (19 clés garanties).
  ///
  /// D-2 RÉSOLU ICI : cette méthode portait sa PROPRE copie des bornes, avec
  /// `divergence` plafonné à 0,10 au lieu de 0,08, puis divisait par le total
  /// (ce qui écrasait les bornes). Elle appelle désormais la même projection
  /// que `clamp()`. Les valeurs d'amorçage `?? …` qui figuraient ici ont
  /// disparu : `poidsEffectifsPourDiscipline()` garantit déjà les 19 clés, et
  /// une clé absente vaut 0, donc remonte à son plancher par la projection.
  static void clampDiscipline(Map<String, double> poids) {
    final projetes = projeter(poids);
    poids
      ..clear()
      ..addAll(projetes);
  }

  Map<String, dynamic> toJson() => {
    'forme': forme, 'gains': gains, 'record': record,
    'cote': cote, 'constance': constance,
    'victoires': victoires, 'discipline': discipline,
    'distSpec': distSpec, 'jockey': jockey, 'repos': repos,
    'hippo': hippo,
    'entraineur': entraineur, // ★ v8.0
    'elo': elo,               // ★ v8.0
    'terrain': terrain,       // ★ v9.0
    'divergence': divergence, // ★ v9.0
    'poidsRel': poidsRel,     // ★ v9.0
    'progression': progression, // ★ v9.0
    'mouvCote': mouvCote,       // ★ v9.92 — corrigé : était absent de toJson
    'placeDepart': placeDepart, // ★ v9.93 — corrigé : était absent de toJson
    'nbMisesAJour': nbMisesAJour,
    'calibrationScore': calibrationScore,
    'poidsParDiscipline': poidsParDiscipline,
    'dernierGradient': dernierGradient,
    'poidsIndices': poidsIndices.toJson(),
    'correlations': correlations,  // ★ v9.92
  };

  // ══════════════════════════════════════════════════════════════════════════
  //  ★★ BL1-A23 (27/11/2026) — D-3 : DÉSÉRIALISATION TOLÉRANTE ET TRAÇABLE
  //
  //  DÉFAUT MESURÉ AVANT : `fromJson` faisait `(j['forme'] as num?)`. Sur une
  //  valeur TEXTE, ce cast LÈVE `TypeError` (mesuré : test S1.4), et l'appelant
  //  `_load()` (`ia_memory_service.dart:2311`) n'avait AUCUN try/catch : un seul
  //  champ corrompu faisait échouer TOUT le chargement (poids, pronostics,
  //  seuils, archives…). Perte silencieuse de données parfaitement valides.
  //
  //  CE QUE FAIT LE LECTEUR CI-DESSOUS — les 8 cas sont DISTINGUÉS :
  //    (a) clé ABSENTE           → repli documenté (0,25 / 0,13 / 0,10 / …)
  //    (b) valeur `null`         → repli documenté (identique à (a))
  //    (c) `num` fini et ≥ 0     → valeur REPRISE TELLE QUELLE, sans arrondi
  //    (d) valeur TEXTE          → écartée + TRACÉE, repli pour ce SEUL champ
  //    (e) type incompatible     → écartée + TRACÉE, repli pour ce SEUL champ
  //    (f) valeur NÉGATIVE       → écartée + TRACÉE, repli pour ce SEUL champ
  //    (g) valeur NON FINIE      → écartée + TRACÉE, repli pour ce SEUL champ
  //    (h) numérique HORS BORNES (ex. poids appris 0,401813880733, ou 0,55)
  //        → ACCEPTÉE SANS DISCUSSION. Ce n'est PAS une corruption : `fromJson`
  //        ne contraint rien et ne doit rien contraindre, sinon il réécrirait
  //        l'histoire de l'apprentissage. La projection D-1 ne s'applique
  //        qu'aux moments légitimes, JAMAIS au chargement.
  //
  //  GARANTIES :
  //    • Aucune valeur valide perdue : chaque champ est lu ISOLÉMENT, l'échec
  //      d'un champ n'affecte jamais les 18 autres.
  //    • Aucune conversion arbitraire : une chaîne n'est pas « interprétée »,
  //      un négatif n'est pas « remis en positif ».
  //    • Aucun remplacement silencieux de la table entière par les poids initiaux.
  //    • Toute perte partielle est TRACÉE dans `dernieresAnomaliesDeserialisation`
  //      (lisible par l'appelant) ; rien n'est muet.
  // ══════════════════════════════════════════════════════════════════════════

  /// Trace des anomalies de la DERNIÈRE désérialisation (vide si aucune).
  /// Alimentée uniquement par `fromJson` ; jamais écrite ailleurs, jamais
  /// utilisée pour décider d'une valeur.
  static List<String> dernieresAnomaliesDeserialisation = <String>[];

  /// Lit un POIDS de façon tolérante. Rend la valeur authentique si elle est
  /// exploitable, sinon `repli`, en traçant le motif exact.
  static double _lirePoids(
    Map<String, dynamic> j,
    String cle,
    double repli,
    List<String> anomalies,
  ) {
    if (!j.containsKey(cle)) return repli;         // (a) clé absente
    final Object? v = j[cle];
    if (v == null) return repli;                   // (b) null
    if (v is num) {
      final double d = v.toDouble();
      if (d.isNaN || d.isInfinite) {               // (g) non fini
        anomalies.add('$cle: valeur non finie ($d) → repli $repli');
        return repli;
      }
      if (d < 0) {                                 // (f) négatif
        anomalies.add('$cle: valeur négative ($d) → repli $repli');
        return repli;
      }
      return d;                                    // (c) valide
                                                   // (h) hors bornes : assumé
    }
    // (d) texte  /  (e) type incompatible
    anomalies.add(
        '$cle: type ${v.runtimeType} non numérique (« $v ») → repli $repli');
    return repli;
  }

  /// Lit un NOMBRE flottant non pondéral (calibration). Même tolérance,
  /// mais une valeur négative est acceptée : ce n'est pas un poids.
  static double _lireDoubleBrut(
    Map<String, dynamic> j,
    String cle,
    double repli,
    List<String> anomalies,
  ) {
    if (!j.containsKey(cle)) return repli;
    final Object? v = j[cle];
    if (v == null) return repli;
    if (v is num) {
      final double d = v.toDouble();
      if (d.isNaN || d.isInfinite) {
        anomalies.add('$cle: valeur non finie ($d) → repli $repli');
        return repli;
      }
      return d;
    }
    anomalies.add(
        '$cle: type ${v.runtimeType} non numérique (« $v ») → repli $repli');
    return repli;
  }

  /// Lit un ENTIER (compteur). Tolérant, tracé.
  static int _lireEntier(
    Map<String, dynamic> j,
    String cle,
    List<String> anomalies,
  ) {
    if (!j.containsKey(cle)) return 0;
    final Object? v = j[cle];
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) {
      if (v is double && !v.isFinite) {
        anomalies.add('$cle: valeur non finie ($v) → 0');
        return 0;
      }
      final int i = v.toInt();
      anomalies.add('$cle: $v non entier → $i');
      return i;
    }
    anomalies.add('$cle: type ${v.runtimeType} non numérique (« $v ») → 0');
    return 0;
  }

  /// Lit une `Map<String, double>` (gradient, corrélations), clé par clé.
  /// Une clé illisible est écartée SEULE et tracée ; les autres survivent.
  static Map<String, double> _lireMapDoubles(
    Map<String, dynamic> j,
    String cle,
    List<String> anomalies,
  ) {
    final out = <String, double>{};
    final Object? raw = j[cle];
    if (raw == null) return out;
    if (raw is! Map) {
      anomalies.add('$cle: type ${raw.runtimeType} ignoré');
      return out;
    }
    for (final e in raw.entries) {
      final String k = e.key.toString();
      final Object? v = e.value;
      if (v is num) {
        final double d = v.toDouble();
        if (!d.isNaN && !d.isInfinite) {
          out[k] = d;
          continue;
        }
      }
      anomalies.add('$cle[$k]: valeur « $v » ignorée');
    }
    return out;
  }

  factory IaPoidsAdaptatifs.fromJson(Map<String, dynamic> j) {
    final anomalies = <String>[];

    // ── Poids PAR DISCIPLINE : lecture tolérante, clé par clé ───────────────
    //   AVANT : une seule valeur illisible faisait tomber toute l'entrée de
    //   discipline (le `catch (_) {}` entourait la boucle entière). Désormais
    //   seule la valeur fautive est écartée ; la discipline survit.
    final ppd = <String, Map<String, double>>{};
    final Object? rawPpd = j['poidsParDiscipline'];
    if (rawPpd is Map) {
      for (final entry in rawPpd.entries) {
        final String disc = entry.key.toString();
        final Object? val = entry.value;
        if (val is! Map) {
          anomalies.add(
              'poidsParDiscipline[$disc]: type ${val.runtimeType} ignoré');
          continue;
        }
        final table = <String, double>{};
        for (final e in val.entries) {
          final String k = e.key.toString();
          final Object? v = e.value;
          if (v is num) {
            final double d = v.toDouble();
            if (!d.isNaN && !d.isInfinite && d >= 0) {
              table[k] = d;
              continue;
            }
          }
          anomalies.add('poidsParDiscipline[$disc][$k]: valeur « $v » ignorée');
        }
        if (table.isNotEmpty) ppd[disc] = table;
      }
    } else if (rawPpd != null) {
      anomalies.add('poidsParDiscipline: type ${rawPpd.runtimeType} ignoré');
    }

    // ── PoidsIndices : isolé, ne doit jamais faire tomber le reste ─────────
    PoidsIndices? indices;
    final Object? rawIndices = j['poidsIndices'];
    if (rawIndices is Map<String, dynamic>) {
      try {
        indices = PoidsIndices.fromJson(rawIndices);
      } catch (e) {
        anomalies.add('poidsIndices: illisible ($e) → ignoré');
      }
    } else if (rawIndices != null) {
      anomalies.add('poidsIndices: type ${rawIndices.runtimeType} ignoré');
    }

    dernieresAnomaliesDeserialisation = anomalies;

    // ★ BL1-A20 (27/11/2026) — HARMONISATION DES TROIS REPLIS, CONSERVÉE.
    //   MESURE AVANT : les replis valaient forme 0,32 / gains 0,15 / record 0,12
    //   alors que le constructeur et `.defauts` valent 0,25 / 0,13 / 0,10.
    //   Trois divergences : +0,07 +0,02 +0,02 = 0,11 EXACTEMENT (1,37 - 1,26).
    //   MESURE APRÈS : `fromJson({})` = 1,260000000000, identique au constructeur.
    //   Ces constantes ne s'appliquent QUE si la clé est ABSENTE, `null`, ou si
    //   la valeur est inexploitable (texte, type incompatible, négatif, non fini)
    //   — cas désormais TRACÉS, voir BL1-A23 ci-dessus. Toute valeur numérique
    //   présente est reprise TELLE QUELLE, hors bornes comprises.
    //   ⚠️ `fromJson` n'appelle PAS `clamp()` — volontaire et inchangé : une
    //      table sauvegardée doit être restituée à l'identique.
    return IaPoidsAdaptatifs(
      forme:        _lirePoids(j, 'forme',        0.25, anomalies),
      gains:        _lirePoids(j, 'gains',        0.13, anomalies),
      record:       _lirePoids(j, 'record',       0.10, anomalies),
      cote:         _lirePoids(j, 'cote',         0.08, anomalies),
      constance:    _lirePoids(j, 'constance',    0.09, anomalies),
      victoires:    _lirePoids(j, 'victoires',    0.04, anomalies),
      discipline:   _lirePoids(j, 'discipline',   0.02, anomalies),
      distSpec:     _lirePoids(j, 'distSpec',     0.08, anomalies),
      jockey:       _lirePoids(j, 'jockey',       0.07, anomalies),
      repos:        _lirePoids(j, 'repos',        0.03, anomalies),
      hippo:        _lirePoids(j, 'hippo',        0.04, anomalies),
      entraineur:   _lirePoids(j, 'entraineur',   0.04, anomalies), // ★ v8.0
      elo:          _lirePoids(j, 'elo',          0.05, anomalies), // ★ v8.0
      terrain:      _lirePoids(j, 'terrain',      0.05, anomalies), // ★ v9.0
      divergence:   _lirePoids(j, 'divergence',   0.04, anomalies), // ★ v9.0
      poidsRel:     _lirePoids(j, 'poidsRel',     0.03, anomalies), // ★ v9.0
      progression:  _lirePoids(j, 'progression',  0.03, anomalies), // ★ v9.0
      mouvCote:     _lirePoids(j, 'mouvCote',     0.06, anomalies), // ★ v9.92
      placeDepart:  _lirePoids(j, 'placeDepart',  0.03, anomalies), // ★ v9.93
      nbMisesAJour: _lireEntier(j, 'nbMisesAJour', anomalies),
      calibrationScore: _lireDoubleBrut(j, 'calibrationScore', 50.0, anomalies),
      poidsParDiscipline: ppd,
      dernierGradient: _lireMapDoubles(j, 'dernierGradient', anomalies),
      poidsIndices: indices,
      correlations: _lireMapDoubles(j, 'correlations', anomalies), // ★ v9.92
    );
  }

  factory IaPoidsAdaptatifs.defaut() => IaPoidsAdaptatifs();

  // Poids par défaut pour comparaison
  //
  // ★ BLOC 1 — MESURE HONNÊTE DE LA SOMME (BL1-A04 / BL1-A06).
  //
  //   Somme de ces dix-neuf valeurs, MESURÉE par calcul et non estimée :
  //       0,32 + 0,15 + 0,12 + 0,08 + 0,09 + 0,04 + 0,02 + 0,08 + 0,07
  //     + 0,03 + 0,04 + 0,04 + 0,05 + 0,05 + 0,04 + 0,03 + 0,03 + 0,06
  //     + 0,03
  //     = 1,37  (et non 1,00)
  //
  //   ⚠️ CE QUE CELA CHANGE — ET CE QUE CELA NE CHANGE PAS. Il faut le dire
  //      exactement, car l'audit annonçait « la pondération relative change
  //      réellement » : c'est VRAI entre `defauts` et le constructeur, et FAUX
  //      à somme constante pour `defauts` seul.
  //
  //      • `defauts` est un REPLI. Le seul consommateur qui l'utilise pour
  //        calculer des poids passe par `clampDiscipline()` (appelée en fin de
  //        `_apprendreParDiscipline`), qui RECLIPPE les 19 valeurs puis les
  //        NORMALISE (`final total = poids.values.fold(...)`, division par le
  //        total). Mesuré : 0 valeur sur 19 est hors de ses bornes, et la
  //        somme normalisée vaut 1,0. Un facteur d'échelle commun s'annule
  //        donc entièrement. Forme effective : 0,32/1,37 = 0,233577.
  //      • `simulation_service.dart:200` utilise `defauts` comme repli d'un
  //        repli, puis divise par `totalPoids` (:209) — même neutralisation.
  //      • Ce qui n'est PAS neutralisé : les scores passés en REVUE (A→S) ne
  //        sont pas des poids mais des notes 0-100 ; les multiplier par un
  //        facteur commun n'a aucun effet sur leur classement relatif, mais le
  //        chemin de `ia_pronostic_engine.dart:328-347` n'appelle NI `clamp()`
  //        NI `normaliser()` : il multiplie directement par les 19 poids
  //        EFFECTIFS. MESURE de cette somme sur un état vierge : 1,2600000000
  //        (et 1,0000000000 seulement après un premier apprentissage). C'est
  //        donc tant que l'IA n'a jamais appris que l'échelle est dilatée de
  //        26 % — ce qui gonfle les scores absolus comparés aux seuils.
  //
  //   ★ BL1-A06 — ALIGNEMENT EXÉCUTÉ (décision utilisateur du présent tour).
  //
  //      Cette table contenait encore les valeurs d'AVANT la v8.0 pour les
  //      trois seuls critères qui ont bougé depuis : `forme` 0.32, `gains` 0.15,
  //      `record` 0.12. Le constructeur de la même classe, lui, porte depuis
  //      v8.0 : `forme` 0.25, `gains` 0.13, `record` 0.10 — et son en-tête
  //      d'origine (retrouvé dans `ddde819`) documente ce rééquilibrage
  //      volontaire (« forme 0.25 : Réduit de 0.32 → libère 7% vers les
  //      enrichis »). Cette table est donc un VESTIGE jamais mis à jour : elle
  //      n'a pas d'autre histoire que celle d'avoir été oubliée.
  //
  //      ALIGNEMENT SANS AUCUNE INCIDENCE, MESURÉE ET NON SUPPOSÉE :
  //        • Les 16 autres clés étaient DÉJÀ identiques au constructeur ; seules
  //          `forme`, `gains` et `record` changent.
  //        • Les SEULS deux consommateurs de cette table sont des REPLIS
  //          INATTEIGNABLES : `ia_memory_service.dart:4249` (`poidsDisc[c] ?? …`)
  //          où `poidsDisc` est construit avec les 19 clés — mesuré 0/19 clés
  //          absentes ; et `simulation_service.dart:200` (`poidsMap[nomLong] ?? …`)
  //          où `poidsMap` vient de `poidsEffectifsPourDiscipline()`, qui
  //          garantit elle aussi les 19 clés — mesuré 0/19 clés absentes.
  //        • `poidsEffectifsPourDiscipline()` construit son repli avec les
  //          CHAMPS de l'instance, jamais avec cette table.
  //        • Les deux consommateurs divisent ensuite par le total
  //          (`clampDiscipline()` / `totalPoids`), ce qui annulerait de toute
  //          façon tout facteur d'échelle commun.
  //
  //      ⇒ Aucun score, aucun poids appris, aucune décision ne change. La table
  //        redevient simplement la VRAIE valeur d'usine, et cesse de contredire
  //        le constructeur qu'elle est censée représenter.
  static const Map<String, double> defauts = {
    'forme': 0.25, 'gains': 0.13, 'record': 0.10,
    'cote': 0.08, 'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
    'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
    'entraineur': 0.04, 'elo': 0.05, // ★ v8.0
    'terrain': 0.05, 'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03, // ★ v9.0
    'mouvCote': 0.06,    // ★ v9.92
    'placeDepart': 0.03, // ★ v9.93
  };

  String get resume =>
    'Forme:${(forme*100).toStringAsFixed(0)}% '
    'Gains:${(gains*100).toStringAsFixed(0)}% '
    'Record:${(record*100).toStringAsFixed(0)}% '
    'Cote:${(cote*100).toStringAsFixed(0)}% '
    'Const:${(constance*100).toStringAsFixed(0)}% '
    'Vict:${(victoires*100).toStringAsFixed(0)}% '
    'Dist:${(distSpec*100).toStringAsFixed(0)}% '
    'Jockey:${(jockey*100).toStringAsFixed(0)}% '
    'Repos:${(repos*100).toStringAsFixed(0)}% '
    'Hippo:${(hippo*100).toStringAsFixed(0)}%';
}

// ─── Entrée du journal d'apprentissage ───────────────────────────────────────


// ══════════════════════════════════════════════════════════════════════════════
// CourseDetailRapport — Détail d'une course dans le rapport journalier ★ v9.6
// ══════════════════════════════════════════════════════════════════════════════
class CourseDetailRapport {
  final String courseKey;
  final String nomCourse;
  final String hippodrome;
  final String heure;
  final String discipline;
  final String typePariConseille;
  final String? favoriIaNumero;       // numéro du cheval favori IA (1er topNIA)
  final String? favoriIaNumero2;      // numéro du 2ème cheval IA (pour Couplé)
  final String? favoriIaNom;          // nom du cheval favori IA
  final double? scoreIA;              // score IA du favori
  final List<int> arriveeReelle;      // arrivée officielle PMU
  final int? rangFavoriIa;            // rang du favori IA dans l'arrivée (1=gagnant)
  final int nbTop3DansArrivee;        // nb de sélections IA dans le top3
  final int nbTop5DansArrivee;        // nb de sélections IA dans le top5
  final double scorePerformance;      // score de performance calculé (0-100)
  final String noteCourseFlavour;     // ✅ Excellent / 👍 Bon / ➖ Moyen / ⚠️ Faible

  const CourseDetailRapport({
    required this.courseKey,
    required this.nomCourse,
    required this.hippodrome,
    required this.heure,
    required this.discipline,
    required this.typePariConseille,
    this.favoriIaNumero,
    this.favoriIaNumero2,
    this.favoriIaNom,
    this.scoreIA,
    required this.arriveeReelle,
    this.rangFavoriIa,
    required this.nbTop3DansArrivee,
    required this.nbTop5DansArrivee,
    required this.scorePerformance,
    required this.noteCourseFlavour,
  });

  bool get favoriGagnant  => rangFavoriIa == 1;
  bool get favoriTop3     => rangFavoriIa != null && rangFavoriIa! <= 3;
  bool get favoriTop5     => rangFavoriIa != null && rangFavoriIa! <= 5;

  String get arriveeStr => arriveeReelle.take(5).map((n) => 'N°$n').join(' - ');

  Map<String, dynamic> toJson() => {
    'ck':   courseKey,
    'nom':  nomCourse,
    'hip':  hippodrome,
    'hre':  heure,
    'dis':  discipline,
    'tp':   typePariConseille,
    'fnum': favoriIaNumero,
    'fnum2': favoriIaNumero2,
    'fnom': favoriIaNom,
    'sIA':  scoreIA,
    'arr':  arriveeReelle,
    'rng':  rangFavoriIa,
    'top3': nbTop3DansArrivee,
    'top5': nbTop5DansArrivee,
    'sp':   scorePerformance,
    'note': noteCourseFlavour,
  };

  factory CourseDetailRapport.fromJson(Map<String, dynamic> j) =>
      CourseDetailRapport(
    courseKey:          j['ck']   as String? ?? '',
    nomCourse:          j['nom']  as String? ?? '',
    hippodrome:         j['hip']  as String? ?? '',
    heure:              j['hre']  as String? ?? '',
    discipline:         j['dis']  as String? ?? '',
    typePariConseille:  j['tp']   as String? ?? '',
    favoriIaNumero:     j['fnum'] as String?,
    favoriIaNumero2:    j['fnum2'] as String?,
    favoriIaNom:        j['fnom'] as String?,
    scoreIA:            (j['sIA'] as num?)?.toDouble(),
    arriveeReelle:      (j['arr'] as List<dynamic>? ?? [])
        .map((e) => (e as num).toInt()).toList(),
    rangFavoriIa:       j['rng']  as int?,
    nbTop3DansArrivee:  j['top3'] as int? ?? 0,
    nbTop5DansArrivee:  j['top5'] as int? ?? 0,
    scorePerformance:   (j['sp']  as num?)?.toDouble() ?? 0,
    noteCourseFlavour:  j['note'] as String? ?? '',
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// StatsTypePariJour — Stats par type de pari pour UN jour donné ★ v9.6
// Stocké dans RapportJournalier.parTypePari
// ══════════════════════════════════════════════════════════════════════════════
class StatsTypePariJour {
  final String typePari;
  final int nbPronostiques;   // nb de courses avec ce type conseillé par l'IA
  final int nbFavoriTop3;     // favori IA dans le top3
  final int nbFavoriGagnant;  // favori IA gagnant
  final double scoreMoyen;    // score IA moyen sur ce type

  const StatsTypePariJour({
    required this.typePari,
    required this.nbPronostiques,
    required this.nbFavoriTop3,
    required this.nbFavoriGagnant,
    required this.scoreMoyen,
  });

  double get tauxTop3     => nbPronostiques > 0 ? nbFavoriTop3    / nbPronostiques * 100 : 0;
  double get tauxGagnant  => nbPronostiques > 0 ? nbFavoriGagnant / nbPronostiques * 100 : 0;

  String get emoji {
    switch (typePari) {
      case 'Simple Gagnant': return '🥇';
      case 'Simple Placé':   return '🏅';
      case 'Couplé Gagnant': return '🔗';
      case 'Couplé Placé':   return '🔗';
      case 'Tiercé':         return '🥉';
      case 'Quarté+':        return '4️⃣';
      case 'Quinté+':        return '5️⃣';
      default:               return '🎰';
    }
  }

  Map<String, dynamic> toJson() => {
    'tp': typePari, 'nb': nbPronostiques,
    'ft3': nbFavoriTop3, 'fg': nbFavoriGagnant, 'sm': scoreMoyen,
  };

  factory StatsTypePariJour.fromJson(Map<String, dynamic> j) =>
      StatsTypePariJour(
    typePari:        j['tp']  as String? ?? '',
    nbPronostiques:  j['nb']  as int?    ?? 0,
    nbFavoriTop3:    j['ft3'] as int?    ?? 0,
    nbFavoriGagnant: j['fg']  as int?    ?? 0,
    scoreMoyen:      (j['sm'] as num?)?.toDouble() ?? 0,
  );
}

class JournalEntree {
  final DateTime date;
  final String nomCourse;
  final String discipline;
  final int nbCoursesAnalysees;
  final String diagnostic;          // explication lisible de ce qui a été appris
  final Map<String, double> avant;  // poids avant l'ajustement
  final Map<String, double> apres;  // poids après l'ajustement
  final double scorePerf;           // performance moyenne sur la fenêtre
  final String? methode;            // 'gradient', 'regles', 'discipline_gradient'

  const JournalEntree({
    required this.date,
    required this.nomCourse,
    this.discipline = '',
    required this.nbCoursesAnalysees,
    required this.diagnostic,
    required this.avant,
    required this.apres,
    required this.scorePerf,
    this.methode,
  });

  // Delta lisible pour chaque critère
  String get deltaPrincipal {
    double maxDelta = 0;
    String critere = '';
    apres.forEach((k, v) {
      final delta = (v - (avant[k] ?? v)).abs();
      if (delta > maxDelta) { maxDelta = delta; critere = k; }
    });
    if (critere.isEmpty || maxDelta < 0.005) return 'Aucun changement';
    final delta = (apres[critere]! - (avant[critere] ?? 0));
    final sign = delta > 0 ? '+' : '';
    final label = _labelCritere(critere);
    return '$label : $sign${(delta * 100).toStringAsFixed(1)}%';
  }

  static String _labelCritere(String k) {
    // ★ v9.95 audit : 19 critères A→S complets (terrain/divergence/poidsRel/progression/mouvCote/placeDepart manquaient)
    const labels = {
      'forme':       'Forme récente',
      'gains':       'Gains carrière',
      'record':      'Record/Vitesse',
      'cote':        'Cote marché',
      'constance':   'Régularité',
      'victoires':   'Victoires',
      'discipline':  'Spécialisation',
      'distSpec':    'Dist. spécialisée',
      'jockey':      'Jockey/Driver',
      'repos':       'Repos physique',
      'hippo':       'Spéc. Hippodrome',
      'entraineur':  'Entraîneur',       // ★ v8.0
      'elo':         'ELO dynamique',    // ★ v8.0
      'terrain':     'Terrain',          // ★ v9.0
      'divergence':  'Coup préparé',     // ★ v9.0
      'poidsRel':    'Poids porté',      // ★ v9.0
      'progression': 'Progression',      // ★ v9.0
      'mouvCote':    'Mouvement cote',   // ★ v9.92
      'placeDepart': 'Place départ',     // ★ v9.93
    };
    return labels[k] ?? k;
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'nomCourse': nomCourse,
    'discipline': discipline,
    'nbCoursesAnalysees': nbCoursesAnalysees,
    'diagnostic': diagnostic,
    'avant': avant,
    'apres': apres,
    'scorePerf': scorePerf,
    'methode': methode,
  };

  factory JournalEntree.fromJson(Map<String, dynamic> j) => JournalEntree(
    date: DateTime.parse(j['date'] as String),
    nomCourse: j['nomCourse'] as String,
    discipline: j['discipline'] as String? ?? '',
    nbCoursesAnalysees: j['nbCoursesAnalysees'] as int,
    diagnostic: j['diagnostic'] as String,
    avant: Map<String, double>.from(
      (j['avant'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()))
    ),
    apres: Map<String, double>.from(
      (j['apres'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()))
    ),
    scorePerf: (j['scorePerf'] as num?)?.toDouble() ?? 0.0,
    methode: j['methode'] as String?,
  );
}

// ─── Statistiques globales ────────────────────────────────────────────────────

class IaStats {
  final int totalCourses;
  final int coursesAvecResultat;
  final int favoriGagnant;
  final int favoriTop3;
  final int favoriTop5;
  final int nbTop3Correct2sur3;
  final int nbTop5Correct4sur5; // ★ v10.14 : seuil 4/5 (était 3/5)
  final double scoreMoyenPerformance;
  final Map<String, int> parDiscipline;
  final Map<String, double> tauxParDiscipline;

  // ★ v3 : Confiance calibrée
  final double calibrationScore;

  const IaStats({
    required this.totalCourses,
    required this.coursesAvecResultat,
    required this.favoriGagnant,
    required this.favoriTop3,
    required this.favoriTop5,
    required this.nbTop3Correct2sur3,
    required this.nbTop5Correct4sur5,
    required this.scoreMoyenPerformance,
    required this.parDiscipline,
    required this.tauxParDiscipline,
    this.calibrationScore = 50.0,
  });

  double get tauxFavoriGagnant =>
      coursesAvecResultat == 0 ? 0 : favoriGagnant / coursesAvecResultat * 100;
  double get tauxFavoriTop3 =>
      coursesAvecResultat == 0 ? 0 : favoriTop3 / coursesAvecResultat * 100;
  double get tauxFavoriTop5 =>
      coursesAvecResultat == 0 ? 0 : favoriTop5 / coursesAvecResultat * 100;
  double get tauxTop3Correct =>
      coursesAvecResultat == 0 ? 0 : nbTop3Correct2sur3 / coursesAvecResultat * 100;
  double get tauxTop5Correct =>
      coursesAvecResultat == 0 ? 0 : nbTop5Correct4sur5 / coursesAvecResultat * 100;
}

// ═══════════════════════════════════════════════════════════════════════════
//  SERVICE PRINCIPAL
// ═══════════════════════════════════════════════════════════════════════════


// ─── Stats par label IA (⚡ Coup préparé, 🥇 FAVORI IA, etc.) ─────────────────
//
//  Pour chaque label affiché par l'IA (ex: "⚡ Coup préparé possible"),
//  on suit combien de fois ce label a été donné et combien de fois le cheval
//  était effectivement dans le top 1 / top 3 / top 5 à l'arrivée.
//
//  Cela permet d'afficher dans l'UI :
//    "⚡ Coup préparé : 4/12 fois dans le top 3 (33%)"
//  Et à l'IA d'ajuster dynamiquement le poids du critère correspondant.
//
//  Cycle complet :
//    1. Au moment du pronostic  → labelIA de chaque cheval stocké dans IaPronostic
//    2. Après résultat réel     → IaMemoryService calcule si le cheval labellisé
//                                  est arrivé dans le top1/top3/top5
//    3. Gradient descent        → si le label discrimine bien → poids monte
//    4. Sauvegarde              → clé 'ia_stats_labels_v1' dans SharedPreferences
// ─────────────────────────────────────────────────────────────────────────────

class StatsParLabel {
  final String label;      // ex: "⚡ Coup préparé possible", "🥇 FAVORI IA"

  // ── Compteurs permanents ──────────────────────────────────────────────────
  int nbTotal;     // nb de fois où ce label a été attribué (avec résultat connu)
  int nbTop1;      // nb de fois → cheval arrivé 1er
  int nbTop3;      // nb de fois → cheval arrivé dans les 3 premiers
  int nbTop5;      // nb de fois → cheval arrivé dans les 5 premiers

  // ── Historique par jour (pour graphiques et filtres) ──────────────────────
  // Format : {'d': 'YYYY-MM-DD', 'nb': N, 't1': N, 't3': N, 't5': N}
  final List<Map<String, dynamic>> historique;

  StatsParLabel({
    required this.label,
    this.nbTotal = 0,
    this.nbTop1  = 0,
    this.nbTop3  = 0,
    this.nbTop5  = 0,
    List<Map<String, dynamic>>? historique,
  }) : historique = historique ?? [];

  // ── Taux calculés ─────────────────────────────────────────────────────────
  double get tauxTop1  => nbTotal > 0 ? nbTop1 / nbTotal * 100 : 0;
  double get tauxTop3  => nbTotal > 0 ? nbTop3 / nbTotal * 100 : 0;
  double get tauxTop5  => nbTotal > 0 ? nbTop5 / nbTotal * 100 : 0;

  /// Fiabilité : true si au moins 5 occurrences (sinon données insuffisantes)
  bool get estFiable => nbTotal >= 5;

  /// Score de performance du label (0-100) — utilisé pour le gradient
  /// Pondère top1 (50%), top3 (30%), top5 (20%)
  double get scorePerformanceLabel {
    if (nbTotal == 0) return 50.0;
    return (tauxTop1 * 0.50 + tauxTop3 * 0.30 + tauxTop5 * 0.20).clamp(0.0, 100.0);
  }

  /// Tendance sur les 7 derniers jours
  double? get tendance7j {
    if (historique.length < 4) return null;
    final sorted = [...historique]
      ..sort((a, b) => (b['d'] as String).compareTo(a['d'] as String));
    final recent = sorted.take(3).toList();
    final old    = sorted.skip(3).take(4).toList();
    double moyR = 0, moyO = 0;
    for (final e in recent) {
      final nb = e['nb'] as int? ?? 0;
      if (nb > 0) moyR += ((e['t3'] as int? ?? 0) / nb * 100);
    }
    for (final e in old) {
      final nb = e['nb'] as int? ?? 0;
      if (nb > 0) moyO += ((e['t3'] as int? ?? 0) / nb * 100);
    }
    moyR /= recent.length.clamp(1, 99);
    moyO /= old.length.clamp(1, 99);
    return moyR - moyO;
  }

  /// Enregistre une journée d'observations
  void ajouterJournee(DateTime date, int nb, int top1, int top3, int top5) {
    if (nb == 0) return;
    final ds = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
    // ★ v9.90 : fusion avec l'existant du jour au lieu d'écraser
    final existant = historique.firstWhere(
      (e) => e['d'] == ds,
      orElse: () => <String, dynamic>{},
    );
    final entry = {
      'd':  ds,
      'nb': nb    + (existant['nb'] as int? ?? 0),
      't1': top1  + (existant['t1'] as int? ?? 0),
      't3': top3  + (existant['t3'] as int? ?? 0),
      't5': top5  + (existant['t5'] as int? ?? 0),
    };
    historique.removeWhere((e) => e['d'] == ds);
    historique.add(entry);
    historique.sort((a, b) => (a['d'] as String).compareTo(b['d'] as String));
    // Recalculer les totaux
    nbTotal = 0; nbTop1 = 0; nbTop3 = 0; nbTop5 = 0;
    for (final e in historique) {
      nbTotal += e['nb']  as int? ?? 0;
      nbTop1  += e['t1']  as int? ?? 0;
      nbTop3  += e['t3']  as int? ?? 0;
      nbTop5  += e['t5']  as int? ?? 0;
    }
  }

  Map<String, dynamic> toJson() => {
    'lb': label,
    'nb': nbTotal,
    't1': nbTop1,
    't3': nbTop3,
    't5': nbTop5,
    'h':  historique,
  };

  factory StatsParLabel.fromJson(Map<String, dynamic> j) {
    final hist = ((j['h'] as List<dynamic>?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return StatsParLabel(
      label:   j['lb'] as String? ?? 'Inconnu',
      nbTotal: j['nb'] as int?    ?? 0,
      nbTop1:  j['t1'] as int?    ?? 0,
      nbTop3:  j['t3'] as int?    ?? 0,
      nbTop5:  j['t5'] as int?    ?? 0,
      historique: hist,
    );
  }

  /// Labels reconnus avec leur critère IA associé (pour le gradient)
  /// Permet d'identifier quel critère v9 a produit ce label
  static String? criterePourLabel(String label) {
    if (label.contains('Coup préparé'))          return 'divergence';
    if (label.contains('terrain'))               return 'terrain';
    if (label.contains('progression'))           return 'progression';
    if (label.contains('Poids'))                 return 'poidsRel';
    if (label.contains('FAVORI IA'))             return null; // label global
    if (label.contains('SÉLECTION'))             return null;
    return null;
  }

  /// Emoji pour l'affichage UI
  String get emoji {
    if (label.contains('Coup préparé'))  return '⚡';
    if (label.contains('FAVORI'))        return '🥇';
    if (label.contains('SÉLECTION'))     return '⭐';
    if (label.contains('2ème'))          return '🥈';
    if (label.contains('3ème'))          return '🥉';
    if (label.contains('surveiller'))    return '✅';
    if (label.contains('Outsider'))      return '⚠️';
    if (label.contains('terrain'))       return '🌿';
    if (label.contains('progression'))   return '📈';
    return '🏷️';
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  BilanSemaine — Regroupe les rapports journaliers d'une semaine (lun→dim)
//  ★ v9.91 : structure hiérarchique du journal IA
// ════════════════════════════════════════════════════════════════════════════
class BilanSemaine {
  final DateTime lundi;         // Premier jour de la semaine (lundi)
  final DateTime dimanche;      // Dernier jour (dimanche)
  final List<String> rapportsJson; // RapportJournalier sérialisés (JSON strings)

  // Stats agrégées calculées à la fermeture
  final int    totalCourses;
  final int    totalResultats;
  final int    totalGagnant;
  final int    totalTop3;
  final double scoreMoyen;
  final String meilleureDisc;
  final double meilleurTaux;

  const BilanSemaine({
    required this.lundi,
    required this.dimanche,
    required this.rapportsJson,
    this.totalCourses    = 0,
    this.totalResultats  = 0,
    this.totalGagnant    = 0,
    this.totalTop3       = 0,
    this.scoreMoyen      = 0,
    this.meilleureDisc   = '',
    this.meilleurTaux    = 0,
  });

  double get tauxGagnant => totalResultats > 0 ? totalGagnant / totalResultats * 100 : 0;
  double get tauxTop3    => totalResultats > 0 ? totalTop3    / totalResultats * 100 : 0;

  /// Libellé court : "Sem. 28 Avr – 4 Mai"
  String get libelle {
    const mois = ['','Jan','Fév','Mar','Avr','Mai','Juin','Juil','Aoû','Sep','Oct','Nov','Déc'];
    final d = '${lundi.day} ${mois[lundi.month]}';
    final f = '${dimanche.day} ${mois[dimanche.month]}';
    return 'Sem. $d – $f';
  }

  Map<String, dynamic> toJson() => {
    'lundi':    lundi.toIso8601String(),
    'dim':      dimanche.toIso8601String(),
    'rj':       rapportsJson,
    'tc':       totalCourses,
    'tr':       totalResultats,
    'tg':       totalGagnant,
    'tt3':      totalTop3,
    'sm':       scoreMoyen,
    'md':       meilleureDisc,
    'mt':       meilleurTaux,
  };

  factory BilanSemaine.fromJson(Map<String, dynamic> j) => BilanSemaine(
    lundi:          DateTime.parse(j['lundi'] as String),
    dimanche:       DateTime.parse(j['dim']   as String),
    rapportsJson:   ((j['rj'] as List<dynamic>?) ?? []).map((e) => e as String).toList(),
    totalCourses:   j['tc']  as int?    ?? 0,
    totalResultats: j['tr']  as int?    ?? 0,
    totalGagnant:   j['tg']  as int?    ?? 0,
    totalTop3:      j['tt3'] as int?    ?? 0,
    scoreMoyen:     (j['sm'] as num?)?.toDouble() ?? 0,
    meilleureDisc:  j['md']  as String? ?? '',
    meilleurTaux:   (j['mt'] as num?)?.toDouble() ?? 0,
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  BilanMois — Regroupe les BilanSemaine d'un mois calendaire
//  ★ v9.91 : structure hiérarchique du journal IA
// ════════════════════════════════════════════════════════════════════════════
class BilanMois {
  final int annee;
  final int mois;           // 1=Janvier … 12=Décembre
  final List<BilanSemaine> semaines;

  // Stats agrégées du mois
  final int    totalCourses;
  final int    totalResultats;
  final int    totalGagnant;
  final int    totalTop3;
  final double scoreMoyen;
  final String meilleureDisc;
  final double meilleurTaux;

  const BilanMois({
    required this.annee,
    required this.mois,
    required this.semaines,
    this.totalCourses    = 0,
    this.totalResultats  = 0,
    this.totalGagnant    = 0,
    this.totalTop3       = 0,
    this.scoreMoyen      = 0,
    this.meilleureDisc   = '',
    this.meilleurTaux    = 0,
  });

  double get tauxGagnant => totalResultats > 0 ? totalGagnant / totalResultats * 100 : 0;
  double get tauxTop3    => totalResultats > 0 ? totalTop3    / totalResultats * 100 : 0;

  /// Libellé : "Mai 2026"
  String get libelle {
    const moisNoms = ['','Janvier','Février','Mars','Avril','Mai','Juin',
                      'Juillet','Août','Septembre','Octobre','Novembre','Décembre'];
    return '${moisNoms[mois]} $annee';
  }

  Map<String, dynamic> toJson() => {
    'an':   annee,
    'mo':   mois,
    'sem':  semaines.map((s) => s.toJson()).toList(),
    'tc':   totalCourses,
    'tr':   totalResultats,
    'tg':   totalGagnant,
    'tt3':  totalTop3,
    'sm':   scoreMoyen,
    'md':   meilleureDisc,
    'mt':   meilleurTaux,
  };

  factory BilanMois.fromJson(Map<String, dynamic> j) {
    final semList = ((j['sem'] as List<dynamic>?) ?? [])
        .map((e) => BilanSemaine.fromJson(e as Map<String, dynamic>))
        .toList();
    return BilanMois(
      annee:          j['an']  as int? ?? 0,
      mois:           j['mo']  as int? ?? 0,
      semaines:       semList,
      totalCourses:   j['tc']  as int?    ?? 0,
      totalResultats: j['tr']  as int?    ?? 0,
      totalGagnant:   j['tg']  as int?    ?? 0,
      totalTop3:      j['tt3'] as int?    ?? 0,
      scoreMoyen:     (j['sm'] as num?)?.toDouble() ?? 0,
      meilleureDisc:  j['md']  as String? ?? '',
      meilleurTaux:   (j['mt'] as num?)?.toDouble() ?? 0,
    );
  }
}

// ─── Seuils de confiance adaptatifs ──────────────────────────────────────────
//
//  ★ DÉPLACÉ ICI LORS DE LA CORRECTION DU BLOC 1 (BL1-A06).
//
//  Ce fichier est le module de DONNÉES de l'IA (`ia_memory_models.dart`) ; il
//  ne contenait auparavant aucune implémentation de mécanisme. La classe était
//  déclarée dans `ia_memory_service.dart`, ce qui obligeait tout consommateur
//  qui ne veut QUE des seuils (par exemple `recommandation_pari_service.dart`)
//  à importer le service complet — donc ses singletons, `dart:io` et
//  `SharedPreferences`. Le déplacement supprime cette dépendance de fait et
//  n'altère AUCUNE valeur : les champs, les défauts, `ajusterSeuil`, `toJson`
//  et `fromJson` sont repris à l'identique.
//
//  Ces seuils remplacent les seuils hardcodés dans best_bet_screen.dart.
//  L'IA les ajuste automatiquement après chaque analyse de la journée :
//
//   • Si un type de pari a un mauvais taux de réussite → seuil monte
//     (l'IA sera plus exigeante avant de proposer ce pari)
//   • Si un type de pari a un bon taux de réussite → seuil peut descendre
//     (l'IA peut proposer ce pari un peu plus facilement)
//
//  Plages réelles (mesurées dans `ajusterSeuil`, par type — PAS « défaut ± 15 »
//  comme l'affirmait le commentaire d'origine) :
//   • Simple Gagnant   80 → [65, 92]
//   • Gagnant+Placé    50 → [40, 75]
//   • Simple Placé     65 → [50, 80]
//   • Couplé Gagnant   75 → [60, 88]
//   • Couplé Placé     60 → [45, 78]
//   • Tiercé           35 → [25, 55]
//   • Quarté+          80 → [65, 92]
//   • Quinté+           0 → non ajustable (course officielle → toujours)
//
//  ★ BL1-A15 : `seuilQuarte` et `seuilQuinte` sont appris, persistés et
//  affichés, mais n'ont AUCUN effet décisionnel — les branches Quarté/Quinté de
//  `cascadeRecommandation()` utilisent des constantes de SÉLECTION (60/50/40/35
//  et 75/60/55), pas ces seuils. Les activer serait une nouvelle règle métier
//  et NON une correction de raccordement : décision utilisateur indispensable.
// ─────────────────────────────────────────────────────────────────────────────
class SeuilsConfianceAdaptatifs {
  // ★ BL1-A19 — CE COMMENTAIRE ÉTAIT FAUX, CORRIGÉ PAR LA MESURE.
  //
  //   Il affirmait : « Seuils par défaut (identiques aux seuils codés dans
  //   best_bet_screen) ». MESURE : c'est FAUX pour `seuilGagnantPlace`, qui
  //   vaut 50,0 ici (l.1533) alors que `best_bet_screen` utilisait 80.
  //   L'écart est documentaire ET métier : il a déjà été traité comme
  //   BL1-A08 (décision métier hors audit). Il est rappelé ici parce qu'un
  //   lecteur qui croit à l'identité des deux sources se trompe.
  //
  //   ⚠️ AUCUNE VALEUR N'EST MODIFIÉE : la correction est documentaire.
  //      Remonter `seuilGagnantPlace` à 80 toucherait une règle de décision
  //      protégée (§3) : DÉCISION UTILISATEUR INDISPENSABLE.
  //
  // Correspondent au scoreConf minimum pour conseiller ce type de pari
  double seuilSimpleGagnant;   // défaut 80 (+ cote ≤ 8)
  double seuilGagnantPlace;    // défaut 50 (+ cote > 8) — PAS 80, contrairement à best_bet_screen
  double seuilSimplePlace;     // défaut 65
  double seuilCoupleGagnant;   // défaut 75 (+ équilibre)
  double seuilCouplePlace;     // défaut 60 (+ équilibre)
  double seuilTierce;          // défaut 35
  double seuilQuarte;          // défaut 80 (course Quarté officielle)
  double seuilQuinte;          // défaut 0  (course Quinté officielle → toujours)

  // ★ BL1-A15 — CORRIGÉ (documentation + affichage), MESURÉ.
  //
  //   `seuilQuarte` et `seuilQuinte` n'influencent AUCUNE décision de pari.
  //   Leurs SEULES lectures (vérifié par grep exhaustif après BL1-A18) :
  //     • `ia_performance_screen.dart:3183-3184` — AFFICHAGE
  //   (l'ancienne référence `ia_precision_widget.dart:756-757` n'existe plus :
  //    ce widget a été supprimé en BL1-A18 comme duplicate sans appelant.)
  //
  //   ⚠️ CE QUI A CHANGÉ CI-DESSOUS, ET CE QUI N'A PAS CHANGÉ :
  //     • `ajusterSeuil` MODIFIE réellement `seuilQuarte` (case présent,
  //       borné 65-92) — MESURÉ : 50 appels à +2.0 le saturent à 92.0.
  //     • `seuilQuinte` n'est JAMAIS modifié — MESURÉ : reste 0.0 après
  //       50 appels à +2.0 ET après 50 appels à -2.0, faute de `case` dans
  //       `ajusterSeuil` (`default: break`). Le `case 'Quinté+'` de
  //       `seuilCibleTaux` (`ia_memory_service.dart`) était donc MORT et a été
  //       retiré en BL1-A15 : il ne produisait qu'un `debugPrint`.
  //     • Les VALEURS par défaut (80.0 et 0.0), leur PERSISTANCE (`toJson` /
  //       `fromJson`, clés `qa` et `qi`) et leur AFFICHAGE sont CONSERVÉS à
  //       l'identique : une sauvegarde ancienne reste relisible.
  //
  //   CONSÉQUENCE RÉELLE, ET ELLE EST BÉNIGNE : le Quarté+ affiché ÉVOLUE avec
  //   l'apprentissage (mais ne filtre rien) ; le Quinté+ affiché est FIGÉ à 0.0
  //   et ne filtre rien non plus. Un lecteur doit le savoir, sinon il croira
  //   que le Quarté/Quinté est filtré par un seuil appris : c'est faux.
  //
  //   POURQUOI ON NE « CORRIGE » PAS DAVANTAGE : deux voies existent, toutes
  //   deux interdites ou hors périmètre.
  //     ① FAIRE PRODUIRE UN EFFET à ces seuils = créer une NOUVELLE règle
  //        métier (filtrer les paris Quarté+/Quinté+ sur un seuil appris).
  //        §3 protège les seuils adaptatifs : c'est une DÉCISION UTILISATEUR
  //        INDISPENSABLE, non prise.
  //     ② SUPPRIMER l'apprentissage du Quarté = retirer un mécanisme existant,
  //        ce que §3 interdit.
  //   On documente donc, sans toucher ni aux valeurs, ni à la persistance.

  SeuilsConfianceAdaptatifs({
    this.seuilSimpleGagnant  = 80.0,
    this.seuilGagnantPlace   = 50.0,
    this.seuilSimplePlace    = 65.0,
    this.seuilCoupleGagnant  = 75.0,
    this.seuilCouplePlace    = 60.0,
    this.seuilTierce         = 35.0,
    this.seuilQuarte         = 80.0,
    this.seuilQuinte         = 0.0,
  });

  /// Ajuste le seuil pour un type de pari.
  /// delta positif → seuil monte (plus sélectif)
  /// delta négatif → seuil descend (moins sélectif)
  void ajusterSeuil(String typePari, double delta) {
    // Limiter la variation par appel à ±2.0 points (stabilité)
    final d = delta.clamp(-2.0, 2.0);
    switch (typePari) {
      case 'Simple Gagnant':
        seuilSimpleGagnant = (seuilSimpleGagnant + d).clamp(65.0, 92.0);
        break;
      case 'Gagnant+Placé':
        seuilGagnantPlace  = (seuilGagnantPlace  + d).clamp(40.0, 75.0);
        break;
      case 'Simple Placé':
        seuilSimplePlace   = (seuilSimplePlace   + d).clamp(50.0, 80.0);
        break;
      case 'Couplé Gagnant':
        seuilCoupleGagnant = (seuilCoupleGagnant + d).clamp(60.0, 88.0);
        break;
      case 'Couplé Placé':
        seuilCouplePlace   = (seuilCouplePlace   + d).clamp(45.0, 78.0);
        break;
      case 'Tiercé':
        seuilTierce        = (seuilTierce        + d).clamp(25.0, 55.0);
        break;
      case 'Quarté+':
        seuilQuarte        = (seuilQuarte        + d).clamp(65.0, 92.0);
        break;
      // Quinté+ : toujours conseillé quand course officielle → pas de seuil à ajuster
      default:
        break;
    }
  }

  Map<String, dynamic> toJson() => {
    'sg':  seuilSimpleGagnant,
    'gp':  seuilGagnantPlace,
    'sp':  seuilSimplePlace,
    'cg':  seuilCoupleGagnant,
    'cp':  seuilCouplePlace,
    'ti':  seuilTierce,
    'qa':  seuilQuarte,
    'qi':  seuilQuinte,
  };

  factory SeuilsConfianceAdaptatifs.fromJson(Map<String, dynamic> j) {
    return SeuilsConfianceAdaptatifs(
      seuilSimpleGagnant : (j['sg'] as num?)?.toDouble() ?? 80.0,
      seuilGagnantPlace  : (j['gp'] as num?)?.toDouble() ?? 50.0,
      seuilSimplePlace   : (j['sp'] as num?)?.toDouble() ?? 65.0,
      seuilCoupleGagnant : (j['cg'] as num?)?.toDouble() ?? 75.0,
      seuilCouplePlace   : (j['cp'] as num?)?.toDouble() ?? 60.0,
      seuilTierce        : (j['ti'] as num?)?.toDouble() ?? 35.0,
      seuilQuarte        : (j['qa'] as num?)?.toDouble() ?? 80.0,
      seuilQuinte        : (j['qi'] as num?)?.toDouble() ??  0.0,
    );
  }
}
