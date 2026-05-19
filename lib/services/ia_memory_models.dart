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
    // v8.0 : poids rééquilibrés — somme = 1.00 ✅
    // Base (75%) : forme 0.25 + gains 0.13 + record 0.10 + cote 0.08
    //              + constance 0.09 + victoires 0.04 + discipline 0.02 = 0.71
    // Enrichis (29%) : distSpec 0.08 + jockey 0.07 + repos 0.03 + hippo 0.04
    //                  + entraineur 0.04 + elo 0.05 = 0.31 → normaliser() → ~0.29
    this.forme      = 0.25,  // Réduit de 0.32 → libère 7% vers les enrichis
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
    // Total brut ≈ 1.07 → normaliser() ramène à 1.00 exactement
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

  void normaliser() {
    // ★ v7.1 : 7 poids de base (75–82%) + 6 critères enrichis (18–25%) — v8.0
    // La répartition cible est flexible : [0.75, 0.82] pour la base
    // Cela permet à l'IA d'apprendre que certains critères enrichis
    // (ex. jockey ou distSpec) sont plus importants que prévu.
    final totalBase = forme + gains + record + cote + constance + victoires + discipline;
    final totalEnrichi = distSpec + jockey + repos + hippo + entraineur + elo
                       + terrain + divergence + poidsRel + progression
                       + mouvCote + placeDepart; // ★ v9.93 : 19 critères complets
    final totalAll = totalBase + totalEnrichi;

    if (totalAll > 0) {
      // Calcul de la fraction enrichie apprise (clampée à [0.18, 0.40])
      final fractionEnrichi = totalEnrichi / totalAll;
      final targetEnrichi = fractionEnrichi.clamp(0.18, 0.40); // ★ v9.90 : plafond relevé 0.25→0.40
      final targetBase = 1.0 - targetEnrichi;

      if (totalBase > 0) {
        final facteurBase = targetBase / totalBase;
        forme      *= facteurBase;
        gains      *= facteurBase;
        record     *= facteurBase;
        cote       *= facteurBase;
        constance  *= facteurBase;
        victoires  *= facteurBase;
        discipline *= facteurBase;
      }
      if (totalEnrichi > 0) {
        final facteurE = targetEnrichi / totalEnrichi;
        distSpec   *= facteurE;
        jockey     *= facteurE;
        repos      *= facteurE;
        hippo      *= facteurE;
        entraineur *= facteurE; // ★ v8.0 — manquait dans v7.1
        elo        *= facteurE; // ★ v8.0 — manquait dans v7.1
        terrain    *= facteurE; // ★ v9.0
        divergence *= facteurE; // ★ v9.0
        poidsRel   *= facteurE; // ★ v9.0
        progression*= facteurE; // ★ v9.0
        mouvCote   *= facteurE; // ★ v9.93 — manquait
        placeDepart*= facteurE; // ★ v9.93 — manquait
      }
    }
  }

  void clamp() {
    forme      = forme.clamp(0.05, 0.55);
    gains      = gains.clamp(0.04, 0.40);
    record     = record.clamp(0.03, 0.35);
    cote       = cote.clamp(0.05, 0.40);
    constance  = constance.clamp(0.03, 0.25);
    victoires  = victoires.clamp(0.01, 0.15);
    discipline = discipline.clamp(0.01, 0.10);
    // Critères enrichis avec limites plus resserrées
    distSpec   = distSpec.clamp(0.03, 0.18);
    jockey     = jockey.clamp(0.02, 0.15);
    repos      = repos.clamp(0.01, 0.08);
    hippo        = hippo.clamp(0.01, 0.10);
    entraineur   = entraineur.clamp(0.01, 0.08); // ★ v8.0
    elo          = elo.clamp(0.01, 0.10);         // ★ v8.0
    terrain      = terrain.clamp(0.01, 0.10);     // ★ v9.0
    divergence   = divergence.clamp(0.01, 0.08);  // ★ v9.0
    poidsRel     = poidsRel.clamp(0.01, 0.07);    // ★ v9.0
    progression  = progression.clamp(0.01, 0.08); // ★ v9.0
    mouvCote     = mouvCote.clamp(0.02, 0.12);    // ★ v9.93
    placeDepart  = placeDepart.clamp(0.01, 0.07); // ★ v9.93
    normaliser();
    // Normaliser aussi les poids par discipline
    for (final key in poidsParDiscipline.keys) {
      clampDiscipline(poidsParDiscipline[key]!);
    }
  }

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

  static void clampDiscipline(Map<String, double> poids) {
    poids['forme']      = (poids['forme']     ?? 0.38).clamp(0.05, 0.55);
    poids['gains']      = (poids['gains']     ?? 0.18).clamp(0.04, 0.40);
    poids['record']     = (poids['record']    ?? 0.14).clamp(0.03, 0.35);
    poids['cote']       = (poids['cote']      ?? 0.13).clamp(0.05, 0.40);
    poids['constance']  = (poids['constance'] ?? 0.09).clamp(0.03, 0.25);
    poids['victoires']  = (poids['victoires'] ?? 0.05).clamp(0.01, 0.15);
    poids['discipline'] = (poids['discipline']?? 0.03).clamp(0.01, 0.10);
    // ★ v5.0 : critères enrichis inclus dans le clamp discipline
    poids['distSpec']   = (poids['distSpec']  ?? 0.08).clamp(0.03, 0.18);
    poids['jockey']     = (poids['jockey']    ?? 0.07).clamp(0.02, 0.15);
    poids['repos']      = (poids['repos']     ?? 0.03).clamp(0.01, 0.08);
    poids['hippo']      = (poids['hippo']     ?? 0.04).clamp(0.01, 0.10); // ★ v7.0
    poids['entraineur'] = (poids['entraineur']?? 0.04).clamp(0.01, 0.08); // ★ v8.0
    poids['elo']        = (poids['elo']       ?? 0.05).clamp(0.01, 0.10); // ★ v8.0
    poids['terrain']    = (poids['terrain']   ?? 0.05).clamp(0.01, 0.10); // ★ v9.0
    poids['divergence'] = (poids['divergence']?? 0.04).clamp(0.01, 0.08); // ★ v9.0
    poids['poidsRel']   = (poids['poidsRel']  ?? 0.03).clamp(0.01, 0.07); // ★ v9.0
    poids['progression']= (poids['progression']??0.03).clamp(0.01, 0.08); // ★ v9.0
    poids['mouvCote']   = (poids['mouvCote']   ??0.06).clamp(0.02, 0.12); // ★ v9.93
    poids['placeDepart']= (poids['placeDepart']??0.03).clamp(0.01, 0.07); // ★ v9.93
    // Normaliser sur les 19 critères
    final total = poids.values.fold(0.0, (a, b) => a + b);
    if (total > 0) {
      for (final k in poids.keys) {
        poids[k] = poids[k]! / total;
      }
    }
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

  factory IaPoidsAdaptatifs.fromJson(Map<String, dynamic> j) {
    final ppd = <String, Map<String, double>>{};
    final rawPpd = j['poidsParDiscipline'] as Map<String, dynamic>? ?? {};
    for (final entry in rawPpd.entries) {
      try {
        final inner = entry.value as Map<String, dynamic>;
        ppd[entry.key] = inner.map((k, v) => MapEntry(k, (v as num).toDouble()));
      } catch (_) {}
    }
    return IaPoidsAdaptatifs(
      forme:        (j['forme']       as num?)?.toDouble() ?? 0.32,
      gains:        (j['gains']       as num?)?.toDouble() ?? 0.15,
      record:       (j['record']      as num?)?.toDouble() ?? 0.12,
      cote:         (j['cote']        as num?)?.toDouble() ?? 0.08,
      constance:    (j['constance']   as num?)?.toDouble() ?? 0.09,
      victoires:    (j['victoires']   as num?)?.toDouble() ?? 0.04,
      discipline:   (j['discipline']  as num?)?.toDouble() ?? 0.02,
      distSpec:     (j['distSpec']    as num?)?.toDouble() ?? 0.08,
      jockey:       (j['jockey']      as num?)?.toDouble() ?? 0.07,
      repos:        (j['repos']       as num?)?.toDouble() ?? 0.03,
      hippo:        (j['hippo']       as num?)?.toDouble() ?? 0.04,
      entraineur:   (j['entraineur']   as num?)?.toDouble() ?? 0.04, // ★ v8.0
      elo:          (j['elo']          as num?)?.toDouble() ?? 0.05, // ★ v8.0
      terrain:      (j['terrain']      as num?)?.toDouble() ?? 0.05, // ★ v9.0
      divergence:   (j['divergence']   as num?)?.toDouble() ?? 0.04, // ★ v9.0
      poidsRel:     (j['poidsRel']     as num?)?.toDouble() ?? 0.03, // ★ v9.0
      progression:  (j['progression']  as num?)?.toDouble() ?? 0.03, // ★ v9.0
      mouvCote:     (j['mouvCote']     as num?)?.toDouble() ?? 0.06, // ★ v9.92
      placeDepart:  (j['placeDepart']  as num?)?.toDouble() ?? 0.03, // ★ v9.93
      nbMisesAJour: (j['nbMisesAJour'] as int?) ?? 0,
      calibrationScore: (j['calibrationScore'] as num?)?.toDouble() ?? 50.0,
      poidsParDiscipline: ppd,
      dernierGradient: (j['dernierGradient'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0.0)),
      poidsIndices: j['poidsIndices'] != null
          ? PoidsIndices.fromJson(j['poidsIndices'] as Map<String, dynamic>)
          : null,
      correlations: (j['correlations'] as Map<String, dynamic>? ?? {}) // ★ v9.92
          .map((k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0.0)),
    );
  }

  factory IaPoidsAdaptatifs.defaut() => IaPoidsAdaptatifs();

  // Poids par défaut pour comparaison
  static const Map<String, double> defauts = {
    'forme': 0.32, 'gains': 0.15, 'record': 0.12,
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
