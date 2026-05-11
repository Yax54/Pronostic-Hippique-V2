// ═══════════════════════════════════════════════════════════════════
//  MODÈLES ZONE-TURF v8.0
//  Généré par Lot 1 — ELO + Entraîneur + Tendance + Forme 12 courses
// ═══════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════
//  MODÈLES ZONE-TURF — v8.0 (Lot 1 : ELO + Entraîneur + Tendance)
//
//  NOUVEAUTÉS v8.0 :
//   • EloScore : score ELO dynamique par cheval (remplace score statique)
//   • scoreEntraineur : taux de réussite de l'entraîneur (nouveau critère L)
//   • getTendance() : détecte ↑ hausse / ↓ baisse / → stable sur 12 courses
//   • eloRating / eloNbCourses dans ZtPartant
//   • IaCalibrationRegistry inchangé (compatibilité)
// ═══════════════════════════════════════════════════════════════════

// dart:math non utilisé directement dans ce fichier

// ─── Registre de calibration IA ─────────────────────────────────────────────
class IaCalibrationRegistry {
  static double _calibrationScore = 50.0;
  static void update(double score) {
    _calibrationScore = score.clamp(10.0, 90.0);
  }
  static double get value => _calibrationScore;
}

// ─── Résultat complet d'une course ──────────────────────────────────────────
class ResultatCourse {
  final List<int> arriveeOfficielle;
  final List<int> disqualifies;
  final Map<int, String> statutsPartants;
  const ResultatCourse({
    required this.arriveeOfficielle,
    this.disqualifies = const [],
    this.statutsPartants = const {},
  });
  bool get aDesDisqualifies => disqualifies.isNotEmpty;
  String get resumeDisq {
    if (disqualifies.isEmpty) return '';
    return 'DISQ : ${disqualifies.map((n) => 'N°$n').join(', ')}';
  }
}

// ─── Score ELO d'un cheval ───────────────────────────────────────────────────
// Stocké dans EloService, passé au ZtPartant lors du calcul IA
class EloScore {
  final String nomCheval;
  final double rating;       // Score ELO courant (défaut 1500)
  final int    nbCourses;    // Nombre de courses analysées
  final double variationMois; // Variation sur les 30 derniers jours (+/-)

  const EloScore({
    required this.nomCheval,
    this.rating       = 1500.0,
    this.nbCourses    = 0,
    this.variationMois = 0.0,
  });

  // Normalise le score ELO en score IA 0-100
  // ELO 1200 → 20 | 1500 → 50 | 1800 → 80 | 2000 → 100
  double get scoreNormalise {
    return ((rating - 1200.0) / 8.0).clamp(0.0, 100.0);
  }

  // Label de niveau
  String get niveau {
    if (rating >= 1800) return '⭐ Elite';
    if (rating >= 1650) return '🔥 Très bon';
    if (rating >= 1550) return '✅ Bon';
    if (rating >= 1450) return '📊 Moyen';
    return '⚠️ Faible';
  }

  Map<String, dynamic> toJson() => {
    'nom': nomCheval,
    'rating': rating,
    'nb': nbCourses,
    'var': variationMois,
  };

  factory EloScore.fromJson(Map<String, dynamic> j) => EloScore(
    nomCheval:    j['nom']    as String? ?? '',
    rating:       (j['rating'] as num?)?.toDouble() ?? 1500.0,
    nbCourses:    j['nb']     as int?    ?? 0,
    variationMois:(j['var']   as num?)?.toDouble() ?? 0.0,
  );
}

// ─── Tendance de forme ───────────────────────────────────────────────────────
enum TendanceForme { hausse, stable, baisse, insuffisant }

// ─── Partant ─────────────────────────────────────────────────────────────────
class ZtPartant {
  final String numero;
  final String nom;
  final String driver;
  final String entraineur;
  final String proprietaire;
  final String gains;
  final String record;
  final String musique;
  final String cote;
  final String ageSexe;

  // Champs enrichissement IA
  final String musiqueDistanceSpecifique;
  final double poids;
  final int    placeDepartInt;
  final int    joursRepos;
  final String hippodromeActuel;
  final String statsJockeyCsv;
  final String statsHippodromeCsv;
  final String statutPmu;

  // ★ v8.0 : Stats entraîneur — "nom|%vic|%plc|nbCourses30j"
  final String statsEntraineurCsv;

  // ★ v8.0 : ELO — rating ELO du cheval (0 = inconnu)
  final double eloRating;
  final int    eloNbCourses;
  final double eloVariationMois;

  // ★ v9.0 : Nouveaux critères amélioration IA
  // N — Terrain : "bon|3|2|1" = nb courses sur terrain bon|victoires|top3|top5
  //              Terrains : "bon", "souple", "lourd", "tres_lourd", "sable"
  //              Format : "terrain|nbC|nbV|nbTop3"
  final String statsTerrainCsv;
  // P — Poids porté total en kg (déjà dans poids, renommé pour clarté)
  // Q — Gains sur 12 derniers mois pour la progression (en euros)
  final int    gainsDernierAn;

  // Scores IA calculés
  late final double scoreIA;
  late final String labelIA;
  late final String explicationIA;
  late final int rang;

  ZtPartant({
    required this.numero,
    required this.nom,
    required this.driver,
    required this.entraineur,
    required this.proprietaire,
    required this.gains,
    required this.record,
    required this.musique,
    required this.cote,
    required this.ageSexe,
    this.musiqueDistanceSpecifique = '',
    this.poids = 0.0,
    this.placeDepartInt = 0,
    this.joursRepos = 0,
    this.hippodromeActuel = '',
    this.statsJockeyCsv = '',
    this.statsHippodromeCsv = '',
    this.statutPmu = 'PARTANT',
    this.statsEntraineurCsv = '',   // ★ v8.0
    this.eloRating = 0.0,           // ★ v8.0 : 0 = inconnu
    this.eloNbCourses = 0,          // ★ v8.0
    this.eloVariationMois = 0.0,    // ★ v8.0
    this.statsTerrainCsv = '',      // ★ v9.0 : terrain
    this.gainsDernierAn = 0,        // ★ v9.0 : progression
    double? scoreIA,
    String? labelIA,
    String? explicationIA,
    int? rang,
  }) {
    this.scoreIA       = scoreIA       ?? 0.0;
    this.labelIA       = labelIA       ?? '';
    this.explicationIA = explicationIA ?? '';
    this.rang          = rang          ?? 0;
  }

  factory ZtPartant.fromJson(Map<String, dynamic> j) => ZtPartant(
    numero:                   j['num']?.toString()              ?? '?',
    nom:                      j['cheval']          as String?   ?? '?',
    driver:                   j['driver']          as String?   ?? '',
    entraineur:               j['entraineur']      as String?   ?? '',
    musiqueDistanceSpecifique:j['musique_dist']    as String?   ?? '',
    poids:                   (j['poids']   as num?)?.toDouble() ?? 0.0,
    placeDepartInt:           j['place_depart']    as int?      ?? 0,
    joursRepos:               j['jours_repos']     as int?      ?? 0,
    hippodromeActuel:         j['hippodrome_actuel'] as String? ?? '',
    statsJockeyCsv:           j['stats_jockey_csv']  as String? ?? '',
    statsHippodromeCsv:       j['stats_hippo_csv']   as String? ?? '',
    statutPmu:                j['statut_pmu']      as String?   ?? 'PARTANT',
    proprietaire:             j['proprietaire']    as String?   ?? '',
    gains:                    j['gains']           as String?   ?? '',
    record:                   j['record']          as String?   ?? '',
    musique:                  j['musique']         as String?   ?? '',
    cote:                     j['cote']            as String?   ?? '',
    ageSexe:                  j['age_sexe']        as String?   ?? '',
    statsEntraineurCsv:       j['stats_entr_csv']  as String?   ?? '',  // ★ v8.0
    eloRating:               (j['elo_r']  as num?)?.toDouble()  ?? 0.0, // ★ v8.0
    eloNbCourses:             j['elo_nb'] as int?               ?? 0,   // ★ v8.0
    eloVariationMois:        (j['elo_v']  as num?)?.toDouble()  ?? 0.0, // ★ v8.0
    statsTerrainCsv:          j['stats_terrain_csv'] as String? ?? '',  // ★ v9.0
    gainsDernierAn:           j['gains_an'] as int?             ?? 0,   // ★ v9.0
    scoreIA:                 (j['score_ia'] as num?)?.toDouble() ?? 0.0,
    labelIA:                  j['label_ia']        as String?   ?? '',
    explicationIA:            j['explication_ia']  as String?   ?? '',
    rang:                     j['rang']            as int?      ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'num': numero, 'cheval': nom, 'driver': driver,
    'entraineur': entraineur, 'proprietaire': proprietaire,
    'gains': gains, 'record': record, 'musique': musique,
    'cote': cote, 'age_sexe': ageSexe,
    'musique_dist': musiqueDistanceSpecifique,
    'poids': poids, 'place_depart': placeDepartInt,
    'jours_repos': joursRepos, 'hippodrome_actuel': hippodromeActuel,
    'stats_jockey_csv': statsJockeyCsv, 'stats_hippo_csv': statsHippodromeCsv,
    'statut_pmu': statutPmu,
    'stats_entr_csv': statsEntraineurCsv, // ★ v8.0
    'elo_r': eloRating,                   // ★ v8.0
    'elo_nb': eloNbCourses,               // ★ v8.0
    'elo_v': eloVariationMois,            // ★ v8.0
    'stats_terrain_csv': statsTerrainCsv, // ★ v9.0
    'gains_an': gainsDernierAn,           // ★ v9.0
    'score_ia': scoreIA, 'label_ia': labelIA,
    'explication_ia': explicationIA, 'rang': rang,
  };

  // ── Numéro entier ──────────────────────────────────────────────────
  int get numInt {
    try { return int.parse(numero); } catch (_) { return 999; }
  }

  // ── Gains en entier ───────────────────────────────────────────────
  int get gainsInt {
    final cleaned = gains.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(cleaned) ?? 0;
  }

  // ── Parseur musique unifié ─────────────────────────────────────────
  // ★ v9.92 : distinguer non-partant (0) des vrais abandons (A/D/B)
  static List<({int position, bool estPenalite, bool estNonPartant})> _parserMusique(String musique) {
    if (musique.isEmpty) return [];
    final tokenRegex = RegExp(
      r'(\()|(\))|([Aa][amhp])|([Dd][abmhp])|([Bb][amhp])|(0[amhp])|(1\d[amhp]|[2-9]\d[amhp]|[1-9][amhp])',
      caseSensitive: true,
    );
    bool inParentheses = false;
    final result = <({int position, bool estPenalite, bool estNonPartant})>[];
    for (final m in tokenRegex.allMatches(musique)) {
      if (m.group(1) != null) { inParentheses = true;  continue; }
      if (m.group(2) != null) { inParentheses = false; continue; }
      if (inParentheses) continue;
      if (m.group(6) != null) {
        // Non-partant : zéro pénalité (retrait admin, pas une contre-perf)
        result.add((position: 99, estPenalite: false, estNonPartant: true));
      } else if (m.group(3) != null || m.group(4) != null || m.group(5) != null) {
        // Arrêté, disqualifié, tombé : pénalité réelle
        result.add((position: 99, estPenalite: true, estNonPartant: false));
      } else if (m.group(7) != null) {
        final raw = m.group(7)!;
        final pos = int.tryParse(raw.substring(0, raw.length - 1)) ?? 99;
        result.add((position: pos, estPenalite: false, estNonPartant: false));
      }
    }
    return result;
  }

  // ── Score forme 0-100 ─────────────────────────────────────────────
  double get scoreForme {
    if (musique.isEmpty) return 30.0;
    final sorties = _parserMusique(musique);
    if (sorties.isEmpty) return 30.0;
    final recent = sorties.take(5).toList();
    final weights = [1.0, 0.78, 0.60, 0.46, 0.34];
    double total = 0; double totalWeight = 0;
    for (int i = 0; i < recent.length; i++) {
      final s = recent[i];
      final w = i < weights.length ? weights[i] : 0.15;
      if (s.estNonPartant) continue;  // ★ v9.92 : non-partant ignoré
      if (s.estPenalite) { totalWeight += w; continue; }
      final pos = s.position;
      double pts;
      if (pos == 1) pts = 100; else if (pos == 2) pts = 78;
      else if (pos == 3) pts = 60; else if (pos <= 5) pts = 35;
      else if (pos <= 8) pts = 18; else pts = 6;
      total += pts * w; totalWeight += w;
    }
    return (totalWeight > 0 ? total / totalWeight : 30.0).clamp(0.0, 100.0);
  }

  // ── Nombre victoires récentes ──────────────────────────────────────
  int get nbVictoiresRecentes {
    final sorties = _parserMusique(musique);
    return sorties.take(6).where((s) => !s.estPenalite && !s.estNonPartant && s.position == 1).length;
  }

  // ── Record en secondes ─────────────────────────────────────────────
  double get recordEnSecondes {
    // ★ v9.92 : supporte les dixièmes de seconde Trot ("1'15"4 ou 1'154)
    final m = RegExp(r"(\d+)'(\d{2})(?:[\x22\x27]?(\d))?").firstMatch(record);
    if (m == null) return 9999.0;
    final minutes  = double.parse(m.group(1)!);
    final secondes = double.parse(m.group(2)!);
    final dixieme  = m.group(3) != null ? double.parse(m.group(3)!) / 10.0 : 0.0;
    return minutes * 60 + secondes + dixieme;
  }

  // ── Cote décimale ─────────────────────────────────────────────────
  double get coteDecimale {
    if (cote.isEmpty) return 99.0;
    return double.tryParse(cote.replaceAll(',', '.')) ?? 99.0;
  }

  // ── copyWith ──────────────────────────────────────────────────────
  ZtPartant copyWith({
    double? scoreIA, String? labelIA, String? explicationIA, int? rang,
    String? musiqueDistanceSpecifique, int? joursRepos,
    String? hippodromeActuel, String? statsJockeyCsv,
    String? statsHippodromeCsv, String? statutPmu,
    String? statsEntraineurCsv,      // ★ v8.0
    double? eloRating,               // ★ v8.0
    int?    eloNbCourses,            // ★ v8.0
    double? eloVariationMois,        // ★ v8.0
    String? statsTerrainCsv,         // ★ v9.0
    int?    gainsDernierAn,          // ★ v9.0
  }) {
    return ZtPartant(
      numero: numero, nom: nom, driver: driver, entraineur: entraineur,
      proprietaire: proprietaire, gains: gains, record: record,
      musique: musique, cote: cote, ageSexe: ageSexe, poids: poids,
      placeDepartInt: placeDepartInt,
      musiqueDistanceSpecifique: musiqueDistanceSpecifique ?? this.musiqueDistanceSpecifique,
      joursRepos:       joursRepos       ?? this.joursRepos,
      hippodromeActuel: hippodromeActuel ?? this.hippodromeActuel,
      statsJockeyCsv:   statsJockeyCsv   ?? this.statsJockeyCsv,
      statsHippodromeCsv: statsHippodromeCsv ?? this.statsHippodromeCsv,
      statutPmu:        statutPmu        ?? this.statutPmu,
      statsEntraineurCsv: statsEntraineurCsv ?? this.statsEntraineurCsv,
      eloRating:        eloRating        ?? this.eloRating,
      eloNbCourses:     eloNbCourses     ?? this.eloNbCourses,
      eloVariationMois: eloVariationMois ?? this.eloVariationMois,
      statsTerrainCsv:  statsTerrainCsv  ?? this.statsTerrainCsv,  // ★ v9.0
      gainsDernierAn:   gainsDernierAn   ?? this.gainsDernierAn,   // ★ v9.0
      scoreIA:          scoreIA          ?? this.scoreIA,
      labelIA:          labelIA          ?? this.labelIA,
      explicationIA:    explicationIA    ?? this.explicationIA,
      rang:             rang             ?? this.rang,
    );
  }

  // ── estHorsCourse ─────────────────────────────────────────────────
  bool get estHorsCourse {
    final s = statutPmu.toUpperCase();
    return s == 'DISQUALIFIE' || s == 'NON_PARTANT' || s == 'ARRETE' ||
           s == 'TOMBE' || s == 'ABANDONNE' || s == 'DISTANCE' ||
           s == 'DISQUALIFIED' || s == 'RETRAIT';
  }

  // ── Score forme distance spécifique ──────────────────────────────
  double get scoreFormeDistanceSpecifique {
    final muse = musiqueDistanceSpecifique.isNotEmpty ? musiqueDistanceSpecifique : musique;
    if (muse.isEmpty) return 40.0;
    final sorties = _parserMusique(muse);
    if (sorties.isEmpty) return 40.0;
    final recent = sorties.take(5).toList();
    final weights = [1.0, 0.80, 0.62, 0.48, 0.35];
    double total = 0; double wTotal = 0;
    for (int i = 0; i < recent.length; i++) {
      final s = recent[i]; final w = i < weights.length ? weights[i] : 0.20;
      if (s.estNonPartant) continue;  // ★ v9.92
      if (s.estPenalite) { wTotal += w; continue; }
      final pos = s.position;
      double pts;
      if (pos == 1) pts = 100; else if (pos == 2) pts = 82;
      else if (pos == 3) pts = 66; else if (pos <= 5) pts = 50;
      else if (pos <= 8) pts = 33; else pts = 15;
      total += pts * w; wTotal += w;
    }
    final bonus = musiqueDistanceSpecifique.isNotEmpty ? 8.0 : 0.0;
    return ((wTotal > 0 ? total / wTotal : 40.0) + bonus).clamp(0.0, 100.0);
  }

  // ── Score hippodrome ──────────────────────────────────────────────
  double get scoreHippodrome {
    if (statsHippodromeCsv.isEmpty) return 50.0;
    final parts = statsHippodromeCsv.split('|');
    if (parts.length < 3) return 50.0;
    final nbCourses = int.tryParse(parts[0]) ?? 0;
    final nbVict    = int.tryParse(parts[1]) ?? 0;
    final nbTop3    = int.tryParse(parts[2]) ?? 0;
    if (nbCourses <= 0) return 50.0;
    if (nbCourses < 3)  return 55.0;
    final tauxVict = nbVict  / nbCourses;
    final tauxTop3 = nbTop3  / nbCourses;
    final scoreVict = (tauxVict * 200.0).clamp(0.0, 100.0);
    final scoreTop3 = (tauxTop3 * 125.0).clamp(0.0, 100.0);
    final score = scoreVict * 0.60 + scoreTop3 * 0.40;
    final bonusData = (nbCourses >= 10) ? 5.0 : (nbCourses >= 6 ? 2.0 : 0.0);
    return (score + bonusData).clamp(0.0, 100.0);
  }

  // ── Score repos ───────────────────────────────────────────────────
  double get scoreRepos {
    if (joursRepos <= 0) return 50.0;
    const ancres = [
      (j: 0,   s: 50.0), (j: 7,   s: 18.0), (j: 14,  s: 72.0),
      (j: 21,  s: 96.0), (j: 28,  s: 90.0), (j: 35,  s: 80.0),
      (j: 50,  s: 62.0), (j: 70,  s: 40.0), (j: 90,  s: 22.0),
      (j: 120, s: 10.0),
    ];
    final d = joursRepos.toDouble();
    if (d <= ancres.first.j) return ancres.first.s;
    if (d >= ancres.last.j)  return ancres.last.s;
    for (int i = 0; i < ancres.length - 1; i++) {
      final a = ancres[i]; final b = ancres[i + 1];
      if (d >= a.j && d <= b.j) {
        final t = (d - a.j) / (b.j - a.j);
        return (a.s + t * (b.s - a.s)).clamp(0.0, 100.0);
      }
    }
    return 10.0;
  }

  // ── Jockey taux victoire ──────────────────────────────────────────
  double get jockeyTauxVictoire {
    if (statsJockeyCsv.isEmpty) return -1;
    final parts = statsJockeyCsv.split('|');
    if (parts.length < 2) return -1;
    return double.tryParse(parts[1]) ?? -1;
  }

  // ── Jockey taux place ─────────────────────────────────────────────
  double get jockeyTauxPlace {
    if (statsJockeyCsv.isEmpty) return -1;
    final parts = statsJockeyCsv.split('|');
    if (parts.length < 3) return -1;
    return double.tryParse(parts[2]) ?? -1;
  }

  // ★ v8.0 ── Score entraîneur ───────────────────────────────────────
  // Format statsEntraineurCsv : "nom|%vic|%plc|nbCourses30j|%vic7j|nb7j"
  // ex: "FABRE A.|22|48|35|40|5" → 22% vic 30j, 48% plc, 35 courses,
  //     40% victoire sur les 7 derniers jours (5 courses) → en forme !
  // ★ v9.92 POINT 7 : forme court terme (7j) détectée et bonifiée
  double get scoreEntraineur {
    if (statsEntraineurCsv.isEmpty) return 50.0;
    final parts = statsEntraineurCsv.split('|');
    if (parts.length < 2) return 50.0;
    final tauxVic = double.tryParse(parts[1]) ?? -1;
    if (tauxVic < 0) return 50.0;
    final tauxPlc = parts.length >= 3 ? (double.tryParse(parts[2]) ?? 0.0) : 0.0;
    final nb30j   = parts.length >= 4 ? (int.tryParse(parts[3]) ?? 0) : 0;
    // ★ v9.92 : taux victoire 7 derniers jours (signal court terme)
    final tauxVic7j = parts.length >= 5 ? (double.tryParse(parts[4]) ?? -1.0) : -1.0;
    final nb7j      = parts.length >= 6 ? (int.tryParse(parts[5]) ?? 0) : 0;

    double score = 0.0;
    // Taux victoire 30j (contribution 55%)
    if (tauxVic >= 22)      score += 55.0;
    else if (tauxVic >= 18) score += 47.0;
    else if (tauxVic >= 15) score += 40.0;
    else if (tauxVic >= 12) score += 33.0;
    else if (tauxVic >= 10) score += 26.0;
    else if (tauxVic >= 7)  score += 18.0;
    else                     score += 10.0;
    // Taux placé (contribution 25%)
    if (tauxPlc >= 50)      score += 25.0;
    else if (tauxPlc >= 42) score += 21.0;
    else if (tauxPlc >= 35) score += 17.0;
    else if (tauxPlc >= 28) score += 13.0;
    else                     score += 7.0;
    // Bonus activité 30j (5%)
    if (nb30j >= 30)      score += 5.0;
    else if (nb30j >= 15) score += 3.0;
    else if (nb30j >= 5)  score += 1.0;
    // ★ v9.92 : Bonus forme court terme 7j (15% max)
    // Entraîneur avec ≥3 courses cette semaine et taux > historique → en forme
    if (tauxVic7j >= 0 && nb7j >= 3) {
      final surperformance = tauxVic7j - tauxVic; // écart vs historique
      if (surperformance >= 15)     score += 15.0; // très en forme
      else if (surperformance >= 8) score += 10.0; // en forme
      else if (surperformance >= 3) score += 5.0;  // légèrement en forme
      else if (surperformance <= -15) score -= 8.0; // en baisse de forme
    }
    return score.clamp(0.0, 100.0);
  }

  // ★ v8.0 ── Score ELO normalisé ────────────────────────────────────
  // 0 = pas de données ELO → retour neutre 50
  double get scoreElo {
    if (eloRating <= 0) return 50.0;
    return ((eloRating - 1200.0) / 8.0).clamp(0.0, 100.0);
  }

  // ★ v9.0 ── N. Score terrain ────────────────────────────────────────
  // Format statsTerrainCsv : "terrain|nbC|nbV|nbTop3"
  // Ex: "bon|8|3|6" → 8 courses sur terrain bon, 3 victoires, 6 top3
  // Retourne un score 0-100 basé sur les perf sur CE type de terrain
  double scoreTerrain(String terrainCourse) {
    if (statsTerrainCsv.isEmpty || terrainCourse.isEmpty) return 50.0;
    // Parser les entrées (plusieurs terrains séparés par ';')
    final entries = statsTerrainCsv.split(';');
    for (final entry in entries) {
      final parts = entry.split('|');
      if (parts.length < 4) continue;
      final terrainStocke = parts[0].toLowerCase().trim();
      final terrainNorm   = _normaliserTerrain(terrainCourse);
      if (terrainStocke != terrainNorm) continue;
      final nbC  = int.tryParse(parts[1]) ?? 0;
      final nbV  = int.tryParse(parts[2]) ?? 0;
      final nbT3 = int.tryParse(parts[3]) ?? 0;
      if (nbC <= 0) return 50.0;
      if (nbC < 2) return 55.0; // peu de données → légèrement positif
      final tauxVic  = nbV  / nbC;
      final tauxTop3 = nbT3 / nbC;
      final scoreVic  = (tauxVic  * 200.0).clamp(0.0, 100.0);
      final scoreTop3 = (tauxTop3 * 130.0).clamp(0.0, 100.0);
      final score = scoreVic * 0.55 + scoreTop3 * 0.45;
      final bonusData = nbC >= 8 ? 5.0 : (nbC >= 4 ? 2.0 : 0.0);
      return (score + bonusData).clamp(0.0, 100.0);
    }
    return 50.0; // terrain inconnu → neutre
  }

  static String _normaliserTerrain(String t) {
    final lower = t.toLowerCase();
    if (lower.contains('tres') && lower.contains('lourd')) return 'tres_lourd';
    if (lower.contains('lourd'))  return 'lourd';
    if (lower.contains('souple')) return 'souple';
    if (lower.contains('bon'))    return 'bon';
    if (lower.contains('sable'))  return 'sable';
    if (lower.contains('piste'))  return 'sable';
    return lower.replaceAll(' ', '_');
  }

  // ★ v9.0 ── O. Divergence forme/cote (détection coup préparé) ───────
  // Si scoreForme élevé MAIS cote élevée → cheval sous-coté → bonus
  // Si scoreForme faible ET cote faible → faux favori → malus
  double get scoreDivergenceFormeCote {
    final sf = scoreFormeLong;
    final c  = coteDecimale;
    if (c <= 0 || c >= 99) return 50.0;

    // ★ v9.90 : Seuil abaissé 5.0→2.5 — les favoris modérés (cote 2.5-5) peuvent
    // aussi être sous-cotés et c'est précisément là où le signal est le plus utile.
    if (c < 2.5) return 50.0;

    // Cote attendue approximative selon la forme (modèle log inversé)
    // scoreForme=80 → cote attendue ~3-4, scoreForme=40 → cote attendue ~10-15
    final coteAttendue = (100.0 / (sf.clamp(10.0, 90.0) / 10.0)).clamp(1.5, 50.0);
    final ratio = coteAttendue / c.clamp(2.5, 99.0); // ★ v9.90 : aligné avec seuil 2.5
    // ratio > 2 : cote réelle très supérieure à ce qu'on attend → sous-coté → bonus fort
    // ratio 1.3-2 : légèrement sous-coté → petit bonus
    // ratio 0.7-1.3 : cohérent → neutre
    // ratio < 0.7 : sur-coté (faux favori) → malus
    if (ratio >= 2.5) return 90.0;
    if (ratio >= 2.0) return 80.0;
    if (ratio >= 1.5) return 68.0;
    if (ratio >= 1.2) return 58.0;
    if (ratio >= 0.8) return 50.0;
    if (ratio >= 0.6) return 38.0;
    return 25.0; // faux favori clair
  }

  // ★ v9.0 ── P. Score poids porté ─────────────────────────────────────
  // Ne s'applique qu'au galop (plat + obstacles)
  // Compare le poids de ce cheval au poids moyen du champ
  // Poids plus léger = avantage
  double scorePoids(double poidsMoyenChamp) {
    if (poids <= 0 || poidsMoyenChamp <= 0) return 50.0;
    final delta = poidsMoyenChamp - poids; // positif = ce cheval est plus léger
    // Chaque kg de différence = ~2-3 longueurs en galop (règle empirique)
    if (delta >= 4.0)  return 85.0;
    if (delta >= 2.5)  return 73.0;
    if (delta >= 1.0)  return 62.0;
    if (delta >= -0.5) return 50.0;
    if (delta >= -2.0) return 38.0;
    if (delta >= -3.5) return 27.0;
    return 15.0;
  }

  // ★ v9.0 ── Q. Score progression de carrière ─────────────────────────
  // Basé sur l'âge + la dynamique des gains sur l'année passée
  // gainsDernierAn = gains des 12 derniers mois en euros
  double get scoreProgression {
    // Extraire l'âge depuis ageSexe (ex: "H4" = hongre 4 ans, "M3" = mâle 3 ans)
    final ageMatch = RegExp(r'\d+').firstMatch(ageSexe);
    final age = ageMatch != null ? int.tryParse(ageMatch.group(0)!) ?? 0 : 0;

    double score = 50.0;

    // 1. Bonus/malus âge — chevaux 3-5 ans sont en phase de progression
    if (age == 3)      score += 12.0; // jeune en plein développement
    else if (age == 4) score += 8.0;  // pic de progression
    else if (age == 5) score += 4.0;  // encore en hausse possible
    else if (age == 6) score += 0.0;  // stable
    else if (age == 7) score -= 3.0;  // légère décrue
    else if (age >= 8) score -= 8.0;  // déclin probable

    // 2. Gains dernière année vs gains totaux (ratio progression)
    final gainsTotal = gainsInt;
    if (gainsTotal > 0 && gainsDernierAn > 0) {
      // Si les gains de l'an dernier représentent une forte fraction des gains totaux
      // → le cheval progresse vite (a beaucoup gagné récemment)
      final ratioAnnee = gainsDernierAn / gainsTotal.toDouble();
      if (ratioAnnee >= 0.40)      score += 15.0; // 40%+ des gains en 1 an → très actif
      else if (ratioAnnee >= 0.25) score += 8.0;
      else if (ratioAnnee >= 0.15) score += 3.0;
      else if (ratioAnnee < 0.05)  score -= 5.0;  // peu actif récemment
    }

    // 3. Bonus tendance forme haussière (cohérence avec scoreFormeLong)
    if (tendanceForme == TendanceForme.hausse) score += 6.0;
    if (tendanceForme == TendanceForme.baisse) score -= 4.0;

    return score.clamp(0.0, 100.0);
  }

  // ★ v9.92 ── R. Score mouvement de cote ──────────────────────────────
  // Alimenté par CoteTrackerService en temps réel.
  // Valeur par défaut : 50.0 (neutre) = hors fenêtre ou pas encore de données.
  // Dans la fenêtre 30 min : remplacé par le vrai score basé sur la variation.
  // Stocké comme champ mutable car mis à jour en cours de course.
  double scoreMouvementCote = 50.0;

  // Label d'affichage pour l'UI
  // Retourne null si hors fenêtre (pas de données)
  String? get labelMouvementCote {
    if (scoreMouvementCote == 50.0) return null; // hors fenêtre
    if (scoreMouvementCote >= 85)  return 'effondrement';
    if (scoreMouvementCote >= 70)  return 'forte_baisse';
    if (scoreMouvementCote >= 58)  return 'baisse';
    if (scoreMouvementCote <= 20)  return 'forte_hausse';
    if (scoreMouvementCote <= 32)  return 'hausse';
    if (scoreMouvementCote <= 42)  return 'legere_hausse';
    return 'stable';
  }

  // ★ v8.0 ── Tendance forme sur 12 courses ─────────────────────────
  // Analyse les 12 dernières sorties pour détecter hausse/baisse/stable
  TendanceForme get tendanceForme {
    final sorties = _parserMusique(musique);
    final valid   = sorties.where((s) => !s.estPenalite && !s.estNonPartant).take(12).toList();  // ★ v9.92
    if (valid.length < 4) return TendanceForme.insuffisant;

    // Diviser en 2 moitiés : récente (0..n/2) vs ancienne (n/2..n)
    final mid     = valid.length ~/ 2;
    final recente = valid.sublist(0, mid);
    final ancienne= valid.sublist(mid);

    double moyRecente = recente.map((s) => s.position.toDouble()).reduce((a,b) => a+b) / recente.length;
    double moyAncienne= ancienne.map((s) => s.position.toDouble()).reduce((a,b) => a+b) / ancienne.length;

    // Position plus basse = meilleure → hausse si moyRecente < moyAncienne
    final delta = moyAncienne - moyRecente; // positif = amélioration
    if (delta >= 2.0)  return TendanceForme.hausse;
    if (delta <= -2.0) return TendanceForme.baisse;
    return TendanceForme.stable;
  }

  // Label de la tendance
  String get tendanceLabel {
    switch (tendanceForme) {
      case TendanceForme.hausse:      return '↑ En hausse';
      case TendanceForme.baisse:      return '↓ En baisse';
      case TendanceForme.stable:      return '→ Stable';
      case TendanceForme.insuffisant: return '— Données insuffisantes';
    }
  }

  // ★ v8.0 ── Score forme sur 12 courses (extended) ─────────────────
  // Remplace le calcul sur 8 courses par un calcul sur 12 avec pondération
  // exponentielle douce + bonus/malus tendance intégrés
  double get scoreFormeLong {
    if (musique.isEmpty) return 25.0;
    final sorties = _parserMusique(musique);
    if (sorties.isEmpty) return 28.0;

    // Prendre 12 sorties (au lieu de 8)
    final recent  = sorties.take(12).toList();
    // Poids exponentiels décroissants (somme ≈ 4.5)
    final weights = [1.0, 0.82, 0.66, 0.53, 0.42, 0.33,
                     0.26, 0.20, 0.15, 0.11, 0.08, 0.06];

    double total = 0; double weightTotal = 0; double totalPenalite = 0;

    for (int i = 0; i < recent.length; i++) {
      final s = recent[i];
      final weight = i < weights.length ? weights[i] : 0.04;
      // ★ v9.92 : non-partant = ignoré silencieusement (pas de pénalité, pas de pts)
      if (s.estNonPartant) continue;
      double pts;
      if (s.estPenalite) {
        pts = 0.0;
        totalPenalite += 15.0 * weight;
      } else {
        final pos = s.position;
        if (pos == 1)       pts = 100.0;
        else if (pos == 2)  pts = 78.0;
        else if (pos == 3)  pts = 60.0;
        else if (pos == 4)  pts = 46.0;
        else if (pos == 5)  pts = 35.0;
        else if (pos == 6)  pts = 26.0;
        else if (pos <= 8)  pts = 18.0;
        else if (pos <= 10) pts = 11.0;
        else if (pos <= 14) pts = 6.0;
        else                pts = 2.0;
      }
      total += pts * weight;
      weightTotal += weight;
    }

    double score = weightTotal > 0 ? total / weightTotal : 25.0;
    score -= totalPenalite;

    // Bonus tendance haussière
    switch (tendanceForme) {
      case TendanceForme.hausse: score += 8.0;  break;
      case TendanceForme.stable: score += 2.0;  break;
      case TendanceForme.baisse: score -= 5.0;  break;
      default: break;
    }

    // Bonus continuité top3
    final top3 = sorties.take(3);
    if (top3.every((s) => !s.estPenalite && !s.estNonPartant && s.position <= 3)) score += 10.0;
    else if (top3.every((s) => !s.estPenalite && !s.estNonPartant && s.position <= 5)) score += 5.0;

    return score.clamp(0.0, 100.0);
  }
}

// ─── Course ─────────────────────────────────────────────────────────────────
// NOTE : ZtCourse et ZtReunion restent IDENTIQUES à la V2 pour compatibilité.
// Seuls ZtPartant et les nouvelles classes sont modifiés.
// Copiez le reste de zt_models.dart de la V2 à partir de "class ZtCourse"
// sans modification.
class ZtCourse {
  final int numCourse;
  final String anchor;
  final String nom;
  final String heure;
  final String distance;
  final String prix;
  final String type;       // Plat, Haies, Attelé, Monté, Steeple
  final String piste;
  final String categorie;
  final bool isQuinte;
  final bool isQuarte; // ★ Quarté+ (14+ partants, pas Quinté)
  /// ★ v9.93 : Course classique sans Quarté/Quinté (Groupe 1/2/3, Poule d'Essai, etc.)
  /// → PMU ne publie que le Tiercé dans son API, Quarté et Quinté impossibles.
  /// Détection : (categorieSpeciale vide OU ne contient ni QUINTE ni QUARTE)
  ///             ET discipline Plat ET dotation >= 80 000 €
  ///             OU nom contient GROUPE, GROUP, POULE, ARC, JOCKEY CLUB, DIANE
  final bool isClassiqueSansMultiple;
  final List<int> pronosticZt;   // Pronostic officiel Zone-Turf
  List<ZtPartant> partants;
  /// Date de la course au format ddmmyyyy (renseigné par ZtReunion)
  String dateStr;

  ZtCourse({
    required this.numCourse,
    required this.anchor,
    required this.nom,
    required this.heure,
    required this.distance,
    required this.prix,
    required this.type,
    required this.piste,
    required this.categorie,
    required this.isQuinte,
    this.isQuarte = false,
    this.isClassiqueSansMultiple = false, // ★ v9.93
    required this.pronosticZt,
    required this.partants,
    this.dateStr = '',
  });

  factory ZtCourse.fromJson(Map<String, dynamic> j) => ZtCourse(
    numCourse: j['num'] as int? ?? 0,
    anchor: j['anchor'] as String? ?? '',
    nom: j['nom'] as String? ?? '',
    heure: j['heure'] as String? ?? '?',
    distance: j['distance'] as String? ?? '?',
    prix: j['prix'] as String? ?? '?',
    type: j['type'] as String? ?? '',
    piste: j['piste'] as String? ?? '',
    categorie: j['categorie'] as String? ?? '',
    isQuinte: j['is_quinte'] as bool? ?? false,
    isQuarte: j['is_quarte'] as bool? ?? false,
    isClassiqueSansMultiple: j['is_classique_sans_multiple'] as bool? ?? false, // ★ v9.93
    pronosticZt: (j['pronostic_zt'] as List<dynamic>? ?? []).map((e) => e as int).toList(),
    partants: (j['partants'] as List<dynamic>? ?? [])
        .map((p) => ZtPartant.fromJson(p as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'num': numCourse,
    'anchor': anchor,
    'nom': nom,
    'heure': heure,
    'distance': distance,
    'prix': prix,
    'type': type,
    'piste': piste,
    'categorie': categorie,
    'is_quinte': isQuinte,
    'is_quarte': isQuarte,
    'is_classique_sans_multiple': isClassiqueSansMultiple, // ★ v9.93
    'pronostic_zt': pronosticZt,
    'partants': partants.map((p) => p.toJson()).toList(),
  };

  // Heure en DateTime — utilise dateStr (ddmmyyyy) si disponible.
  // ⚠️ Si dateStr est absent, retourne null plutôt qu'aujourd'hui
  // pour éviter que des courses d'hier soient traitées comme "futures".
  DateTime get heureDateTime {
    try {
      final parts = heure.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      if (dateStr.length == 8) {
        final day   = int.parse(dateStr.substring(0, 2));
        final month = int.parse(dateStr.substring(2, 4));
        final year  = int.parse(dateStr.substring(4, 8));
        return DateTime(year, month, day, h, m);
      }
      // dateStr absent : on NE suppose PAS que c'est aujourd'hui
      // → retourner une date dans le passé lointain pour que le filtre
      //   "course future" ne la rejette jamais
      return DateTime(2000, 1, 1, h, m);
    } catch (_) {
      return DateTime(2000, 1, 1);
    }
  }

  // Dotation en entier
  int get dotationInt {
    final cleaned = prix.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(cleaned) ?? 0;
  }

  // Icône selon type de course
  String get typeIcon {
    final t = type.toLowerCase();
    if (t.contains('plat')) return '🏇';
    if (t.contains('haies') || t.contains('obstacle')) return '🚧';
    if (t.contains('steeple') || t.contains('cross')) return '🏔️';
    if (t.contains('attelé') || t.contains('attele')) return '🎠';
    if (t.contains('monté') || t.contains('monte')) return '🧑‍🦯';
    if (t.contains('trot')) return '🎠';
    return '🏇';
  }

  // Partants triés par rang IA
  List<ZtPartant> get partantsParRangIA {
    final sorted = [...partants];
    sorted.sort((a, b) => a.rang.compareTo(b.rang));
    return sorted;
  }

  /// Pronostic PMU officiel : partants triés par cote croissante (favoris en tête)
  /// Retourne les numéros des 5 premiers favoris selon les cotes PMU
  List<int> get pronosticPMU {
    final avecCote = partants
        .where((p) => p.coteDecimale > 0)
        .toList()
      ..sort((a, b) => a.coteDecimale.compareTo(b.coteDecimale));
    return avecCote.take(5).map((p) => int.tryParse(p.numero) ?? 0)
        .where((n) => n > 0).toList();
  }

  /// Confiance globale IA de la course — formule enrichie v6.0
  /// Combine 3 dimensions : qualité absolue du favori + écart + régularité du top3
  /// + ajustement par calibrationScore de IaMemoryService (évite sur-estimation)
  double get confianceIA {
    final sorted = partantsParRangIA;
    if (sorted.isEmpty) return 0.0;
    if (sorted.length == 1) return sorted.first.scoreIA.clamp(40.0, 95.0);

    final score1 = sorted.first.scoreIA;
    final score2 = sorted[1].scoreIA;
    final score3 = sorted.length >= 3 ? sorted[2].scoreIA : score2;

    // A. Qualité absolue du favori (40% du calcul) — un favori à 40/100 ne peut pas être "HAUTE"
    final qualiteFavori = score1.clamp(0.0, 100.0) * 0.40;

    // B. Écart de domination entre 1er et 2ème (40% du calcul)
    final ecart12 = (score1 - score2).clamp(0.0, 50.0);
    final dominance = (ecart12 / 50.0) * 40.0; // 0→0%, 50→40%

    // C. Régularité du top3 — récompense un podium cohérent (20% du calcul)
    final cohesionTop3 = ((score2 + score3) / 2.0).clamp(0.0, 100.0) * 0.20;

    // Score brut [0, 100]
    final scoreBrut = qualiteFavori + dominance + cohesionTop3;

    // Mise à l'échelle finale : [0,100] → [40,95]
    double confiance = (40.0 + scoreBrut * 0.55).clamp(40.0, 95.0);

    // ★ v6.0 : Ajustement par calibrationScore (via IaCalibrationRegistry)
    // calibrationScore = 50 (neutre), < 50 = sur-estimé → réduire confiance
    // calibrationScore > 50 = bien calibré → légère hausse possible
    // Formule : facteur = calibration / 50, appliqué en [0.85, 1.10]
    final calib = IaCalibrationRegistry.value;
    final facteurCalib = (calib / 50.0).clamp(0.85, 1.10);
    confiance = (confiance * facteurCalib).clamp(40.0, 95.0);

    return score1 > 0 ? confiance : 0.0;
  }
}

// ─── Réunion ─────────────────────────────────────────────────────────────────
class ZtReunion {
  final String code;       // R1, R2, R3, R4
  final String lieu;       // Chantilly, Vincennes...
  final String discipline; // Plat, Trot, Obstacle
  final String dateStr;    // ddmmyyyy
  final List<ZtCourse> courses;

  ZtReunion({
    required this.code,
    required this.lieu,
    required this.discipline,
    required this.dateStr,
    required this.courses,
  });

  factory ZtReunion.fromJson(Map<String, dynamic> j) {
    final date = j['date'] as String? ?? '';
    final courses = (j['courses'] as List<dynamic>? ?? [])
        .map((c) {
          final course = ZtCourse.fromJson(c as Map<String, dynamic>);
          // Propager la date de la réunion aux courses pour heureDateTime
          if (date.isNotEmpty) course.dateStr = date;
          return course;
        })
        .toList();
    return ZtReunion(
      code: j['code'] as String? ?? '',
      lieu: j['lieu'] as String? ?? '',
      discipline: j['discipline'] as String? ?? '',
      dateStr: date,
      courses: courses,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'lieu': lieu,
    'discipline': discipline,
    'date': dateStr,
    'courses': courses.map((c) => c.toJson()).toList(),
  };

  // Icône hippodrome selon type
  String get disciplineIcon {
    final d = discipline.toLowerCase();
    if (d.contains('trot')) return '🎠';
    if (d.contains('obstacle') || d.contains('haies') || d.contains('steeple')) return '🚧';
    return '🏇';
  }

  // Couleur selon discipline
  int get disciplineColor {
    final d = discipline.toLowerCase();
    if (d.contains('trot')) return 0xFF7B68EE;   // violet
    if (d.contains('obstacle')) return 0xFFE67E22; // orange
    return 0xFF2E7D52; // vert plat
  }

  // Nombre total de partants
  int get totalPartants =>
      courses.fold(0, (acc, c) => acc + c.partants.length);

  // Course Quinté si elle existe
  ZtCourse? get quinteOrNull {
    try { return courses.firstWhere((c) => c.isQuinte); }
    catch (_) { return null; }
  }
}

// ─── Pronostic IA complet ────────────────────────────────────────────────────
class PronosticIA {
  final String numCourse;
  final String nomCourse;
  final String heure;
  final String hippodrome;
  final List<ZtPartant> top5;         // Top 5 chevaux triés par score IA
  final String selection;             // "3-7-1-5-12"
  final double confianceGlobale;      // 0-100
  final String analyseTextuelle;
  final String conseil;               // type de pari recommandé

  PronosticIA({
    required this.numCourse,
    required this.nomCourse,
    required this.heure,
    required this.hippodrome,
    required this.top5,
    required this.selection,
    required this.confianceGlobale,
    required this.analyseTextuelle,
    required this.conseil,
  });
}
