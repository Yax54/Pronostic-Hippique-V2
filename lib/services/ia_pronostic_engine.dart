// ═══════════════════════════════════════════════════════════════════
//  MOTEUR IA DE PRONOSTICS — Pronostic Hippique v8.0 (Lot 1)
//
//  NOUVEAUTÉS v8.0 :
//   ★ Critère M — ELO dynamique par cheval (5%)
//      Intégré via EloService, le score ELO remplace partiellement
//      le score forme pour les chevaux avec historique riche
//   ★ Critère L — Score entraîneur (4%)
//      Taux de victoire/place de l'entraîneur sur 30 jours
//   ★ scoreFormeLong() — Analyse 12 courses (au lieu de 8)
//      + bonus tendance ↑↓→ intégré dans le calcul
//   ★ Seuils de confiance adaptatifs par hippodrome
//      Via IaMemoryService.seuilsConfiancePourHippodrome()
//   ★ Compression des données : ScoresCriteres v8 inclut elo + entraineur
//   ★ Toutes les signatures publiques conservées (compatibilité V2)
// ═══════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import '../models/zt_models.dart';
import 'ia_memory_service.dart';
import 'ia_memory_models.dart';
import 'elo_service.dart';
import 'cote_tracker_service.dart'; // ★ v9.92

class IaPronosticEngine {

  // ══════════════════════════════════════════════════════════════════
  // POINT D'ENTRÉE PRINCIPAL
  // ══════════════════════════════════════════════════════════════════
  static List<ZtPartant> analyserCourse(ZtCourse course,
      {IaPoidsAdaptatifs? poidsOverride}) {
    final partants = course.partants;
    if (partants.isEmpty) return [];

    final poidsGlobaux   = poidsOverride ?? IaMemoryService.instance.poids;
    final poidsEffectifs = poidsGlobaux.poidsEffectifsPourDiscipline(course.type);

    // ★ v9.92 : enrichir avec ELO par discipline
    final partantsEnrichis = EloService.instance.enrichirAvecElo(partants,
        discipline: course.type);

    // ★ v9.92 : alimenter scoreMouvementCote depuis CoteTrackerService
    // Dans la fenêtre 30 min → score basé sur le mouvement réel
    // Hors fenêtre → 50.0 (neutre, critère inactif)
    final courseKey = _buildCourseKey(course);
    final dansFenetre = CoteTrackerService.instance.estDansFenetre(course);
    for (final p in partantsEnrichis) {
      if (dansFenetre) {
        final score = CoteTrackerService.instance
            .scoreCritereR(courseKey, p.numero);
        p.scoreMouvementCote = score ?? 50.0;
      } else {
        p.scoreMouvementCote = 50.0; // hors fenêtre = neutre
      }
    }

    final scores  = <String, double>{};
    final criteres = <String, ScoresCriteres>{};

    for (final p in partantsEnrichis) {
      final (score, sc) = _calculerScoreBrutEtCriteres(
          p, course, poids: poidsGlobaux, poidsEffectifs: poidsEffectifs);
      scores[p.numero]   = score;
      criteres[p.numero] = sc;
    }

    // ★ v9.90 : extrait dans _normaliserScores() — évite la duplication
    _normaliserScores(scores);

    final sorted = [...partantsEnrichis];
    sorted.sort((a, b) => (scores[b.numero] ?? 0).compareTo(scores[a.numero] ?? 0));

    final result = <ZtPartant>[];
    for (int i = 0; i < sorted.length; i++) {
      final p          = sorted[i];
      final scoreAff   = (scores[p.numero] ?? 0).clamp(0.0, 100.0);
      final rang       = i + 1;
      result.add(p.copyWith(
        scoreIA:       scoreAff,
        labelIA:       _determinerLabel(rang, scoreAff, i, sorted.length),
        explicationIA: _genererExplication(p, rang, scoreAff, course),
        rang:          rang,
      ));
    }
    return result;
  }

  /// Retourne les scores de critères (déprécié — préférer analyserCourseAvecCriteres)
  static Map<String, ScoresCriteres> extraireScoresCriteres(ZtCourse course) {
    final partants       = course.partants;
    if (partants.isEmpty) return {};
    final poidsGlobaux   = IaMemoryService.instance.poids;
    final poidsEffectifs = poidsGlobaux.poidsEffectifsPourDiscipline(course.type);
    final partantsE      = EloService.instance.enrichirAvecElo(partants,
        discipline: course.type); // ★ v9.92
    final result         = <String, ScoresCriteres>{};
    for (final p in partantsE) {
      final (_, sc) = _calculerScoreBrutEtCriteres(
          p, course, poids: poidsGlobaux, poidsEffectifs: poidsEffectifs);
      result[p.numero] = sc;
    }
    return result;
  }

  /// ★ v7.1+ Calcul unique — partants classés + ScoresCriteres en UNE SEULE PASSE
  static (List<ZtPartant>, Map<String, ScoresCriteres>) analyserCourseAvecCriteres(
    ZtCourse course, {IaPoidsAdaptatifs? poidsOverride}) {
    final partants = course.partants;
    if (partants.isEmpty) return ([], {});

    final poidsGlobaux   = poidsOverride ?? IaMemoryService.instance.poids;
    final poidsEffectifs = poidsGlobaux.poidsEffectifsPourDiscipline(course.type);

    // ★ v9.92 : enrichir avec ELO par discipline
    final partantsE = EloService.instance.enrichirAvecElo(partants,
        discipline: course.type);

    final scores  = <String, double>{};
    final criteres = <String, ScoresCriteres>{};

    for (final p in partantsE) {
      final (score, sc) = _calculerScoreBrutEtCriteres(
          p, course, poids: poidsGlobaux, poidsEffectifs: poidsEffectifs);
      scores[p.numero]   = score;
      criteres[p.numero] = sc;
    }

    // ★ v9.90 : extrait dans _normaliserScores() — évite la duplication
    _normaliserScores(scores);

    final sorted = [...partantsE];
    sorted.sort((a, b) => (scores[b.numero] ?? 0).compareTo(scores[a.numero] ?? 0));

    final result = <ZtPartant>[];
    for (int i = 0; i < sorted.length; i++) {
      final p        = sorted[i];
      final scoreAff = (scores[p.numero] ?? 0).clamp(0.0, 100.0);
      final rang     = i + 1;
      result.add(p.copyWith(
        scoreIA:       scoreAff,
        labelIA:       _determinerLabel(rang, scoreAff, i, sorted.length),
        explicationIA: _genererExplication(p, rang, scoreAff, course),
        rang:          rang,
      ));
    }
    return (result, criteres);
  }

  // ══════════════════════════════════════════════════════════════════
  // NORMALISATION MIN/MAX — ★ v9.90 : méthode extraite (était dupliquée)
  // ★ v9.92 POINT 6 : ratio dynamique selon le nombre de partants
  //
  // Petit champ (≤6)  : 40% normalisé + 60% brut
  //   → la normalisation amplifierait trop de petits écarts
  // Champ moyen (7-12): 60% normalisé + 40% brut (comportement précédent)
  // Grand champ (13+) : 75% normalisé + 25% brut
  //   → beaucoup de partants = les écarts bruts sont moins lisibles
  // ══════════════════════════════════════════════════════════════════
  static void _normaliserScores(Map<String, double> scores) {
    final vals = scores.values.toList();
    if (vals.length < 3) return;
    final minS  = vals.reduce((a, b) => a < b ? a : b);
    final maxS  = vals.reduce((a, b) => a > b ? a : b);
    final range = maxS - minS;
    if (range <= 1.0) return;

    // ★ v9.92 : ratio dynamique
    final n = vals.length;
    final ratioNorme = n <= 6 ? 0.40 : n <= 12 ? 0.60 : 0.75;
    final ratioBrut  = 1.0 - ratioNorme;

    for (final k in scores.keys) {
      final brut  = scores[k]!;
      final norme = ((brut - minS) / range * 100.0).clamp(0.0, 100.0);
      scores[k]   = norme * ratioNorme + brut * ratioBrut;
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // CALCUL DU SCORE BRUT — v9.93 (19 critères)
  // ══════════════════════════════════════════════════════════════════
  static (double, ScoresCriteres) _calculerScoreBrutEtCriteres(
      ZtPartant p, ZtCourse course,
      {IaPoidsAdaptatifs? poids, Map<String, double>? poidsEffectifs}) {

    final w  = poids ?? IaPoidsAdaptatifs.defaut();
    final pe = poidsEffectifs ?? {
      'forme': w.forme, 'gains': w.gains, 'record': w.record,
      'cote': w.cote, 'constance': w.constance,
      'victoires': w.victoires, 'discipline': w.discipline,
      'distSpec': w.distSpec, 'jockey': w.jockey,
      'repos': w.repos, 'hippo': w.hippo,
    };

    // ── A. FORME RÉCENTE — ★ v8.0 : utilise scoreFormeLong (12 courses + tendance)
    final scoreForme = p.scoreFormeLong;

    // ── B. GAINS CARRIÈRE
    final scoreGains = _scoreGains(p.gains, course);

    // ── C. RECORD / TEMPS
    final scoreRecord = _scoreRecord(p.record, course);

    // ── D. COTE MARCHÉ
    final scoreCote = _scoreCote(p.cote);

    // ── E. CONSTANCE / RÉGULARITÉ
    final scoreConstance = _scoreConstance(p.musique);

    // ── F. VICTOIRES RÉCENTES
    final scoreVictoires = (p.nbVictoiresRecentes * 22.0).clamp(0.0, 100.0);

    // ── G. DISCIPLINE
    final scoreDiscipline = _scoreDisciplineCompatibilite(p, course);

    // ── H. DISTANCE SPÉCIALITÉ
    final scoreDistSpec = _scoreDistanceSpecialite(p, course);

    // ── I. JOCKEY / DRIVER
    final scoreJockey = _scoreJockey(p);

    // ── J. FRAÎCHEUR PHYSIQUE
    final scoreRepos = p.scoreRepos;

    // ── K. HIPPODROME
    final scoreHippo = p.scoreHippodrome;

    // ★ v8.0 ── L. ENTRAÎNEUR (nouveau, 4%)
    final scoreEntraineur = p.scoreEntraineur;

    // ★ v8.0 ── M. SCORE ELO DYNAMIQUE (nouveau, 5%)
    // Neutre (50) si pas de données ELO
    final scoreElo = p.scoreElo;

    // ★ v9.0 ── N. SCORE TERRAIN ──────────────────────────────────────
    // Perf du cheval sur le type de terrain de la course
    final scoreTerrain = p.scoreTerrain(course.piste);

    // ★ v9.0 ── O. DIVERGENCE FORME/COTE (coup préparé) ───────────────
    // Bonus si cheval sous-coté par rapport à sa forme réelle
    final scoreDivergence = p.scoreDivergenceFormeCote;

    // ★ v9.0 ── P. POIDS PORTÉ RELATIF ───────────────────────────────
    // Ne s'applique qu'au galop (plat + obstacles)
    final isGalopCourse = course.type.toLowerCase().contains('plat') ||
                          course.type.toLowerCase().contains('haie') ||
                          course.type.toLowerCase().contains('steeple');
    final poidsMoyen = isGalopCourse && course.partants.isNotEmpty
        ? course.partants
              .where((pp) => pp.poids > 0)
              .map((pp) => pp.poids)
              .fold(0.0, (a, b) => a + b) /
            course.partants.where((pp) => pp.poids > 0).length.clamp(1, 999)
        : 0.0;
    final scorePoids = isGalopCourse ? p.scorePoids(poidsMoyen) : 50.0;

    // ★ v9.0 ── Q. PROGRESSION DE CARRIÈRE ───────────────────────────
    final scoreProgression = p.scoreProgression;

    // ★ v9.92 ── R. MOUVEMENT DE COTE (signal argent informé) ─────────
    // Dans la fenêtre 30 min → score basé sur le mouvement réel
    // Hors fenêtre → score neutre 50 (critère inactif)
    final scoreMouvCote = p.scoreMouvementCote; // 0-100, 50 = neutre/hors fenêtre

    // ★ v9.93 ── S. PLACE AU DÉPART / CORDE ───────────────────────────
    // En Trot sur longues distances : positions 1-6 favorisées.
    // En Galop sur petites pistes : positions centrales favorisées.
    // Neutre (50) si discipline non concernée ou données manquantes.
    final scorePlaceDepart = _scorePlaceDepart(
        p.placeDepartInt, course.partants.length,
        course.type, course.distance);

    // ── PONDÉRATION TOTALE — 19 critères ★ v9.93
    final wEntr       = pe['entraineur']  ?? w.getPoids('entraineur');
    final wElo        = pe['elo']         ?? w.getPoids('elo');
    final wTerr       = pe['terrain']     ?? w.getPoids('terrain');
    final wDiv        = pe['divergence']  ?? w.getPoids('divergence');
    final wPoid       = pe['poidsRel']    ?? w.getPoids('poidsRel');
    final wProg       = pe['progression'] ?? w.getPoids('progression');
    final wMouvCote   = pe['mouvCote']    ?? w.getPoids('mouvCote');
    final wPlaceDepart= pe['placeDepart'] ?? w.getPoids('placeDepart'); // ★ v9.93

    // ── Poids fallback — 19 critères, somme ≈ 1.00
    final score = scoreForme      * (pe['forme']      ?? 0.21)
                + scoreGains      * (pe['gains']      ?? 0.10)
                + scoreRecord     * (pe['record']     ?? 0.08)
                + scoreCote       * (pe['cote']       ?? 0.06)
                + scoreConstance  * (pe['constance']  ?? 0.08)
                + scoreVictoires  * (pe['victoires']  ?? 0.04)
                + scoreDiscipline * (pe['discipline'] ?? 0.02)
                + scoreDistSpec   * (pe['distSpec']   ?? w.distSpec)
                + scoreJockey     * (pe['jockey']     ?? w.jockey)
                + scoreRepos      * (pe['repos']      ?? w.repos)
                + scoreHippo      * (pe['hippo']      ?? w.hippo)
                + scoreEntraineur * (wEntr       > 0 ? wEntr       : 0.03)
                + scoreElo        * (wElo        > 0 ? wElo        : 0.04)
                + scoreTerrain    * (wTerr       > 0 ? wTerr       : 0.05)
                + scoreDivergence * (wDiv        > 0 ? wDiv        : 0.04)
                + scorePoids      * (wPoid       > 0 ? wPoid       : 0.02)
                + scoreProgression* (wProg       > 0 ? wProg       : 0.02)
                + scoreMouvCote   * (wMouvCote   > 0 ? wMouvCote   : 0.06)
                + scorePlaceDepart* (wPlaceDepart> 0 ? wPlaceDepart: 0.03); // ★ v9.93

    final criteres = ScoresCriteres(
      forme:       scoreForme,
      gains:       scoreGains,
      record:      scoreRecord,
      cote:        scoreCote,
      constance:   scoreConstance,
      victoires:   scoreVictoires,
      discipline:  scoreDiscipline,
      distSpec:    scoreDistSpec,
      jockey:      scoreJockey,
      repos:       scoreRepos,
      hippo:       scoreHippo,
      entraineur:  scoreEntraineur,
      elo:         scoreElo,
      terrain:     scoreTerrain,
      divergence:  scoreDivergence,
      poidsRel:    scorePoids,
      progression: scoreProgression,
      mouvCote:    scoreMouvCote,
      placeDepart: scorePlaceDepart, // ★ v9.93
    );

    return (score, criteres);
  }

  // ══════════════════════════════════════════════════════════════════
  // CRITÈRES INDIVIDUELS — inchangés sauf _scoreMusiqueRecente (supprimé,
  // remplacé par p.scoreFormeLong dans le partant)
  // ══════════════════════════════════════════════════════════════════

  static double _scoreDisciplineCompatibilite(ZtPartant p, ZtCourse course) {
    final recSecondes = p.recordEnSecondes;
    if (recSecondes >= 9999) return 50.0;
    final distStr = course.distance.replaceAll(RegExp(r'[^\d]'), '');
    final dist    = int.tryParse(distStr) ?? 0;
    if (dist == 0) return 50.0;
    final vitesse = dist / recSecondes;

    double score;
    if (vitesse >= 12.0) score = 85.0;
    else if (vitesse >= 10.5) score = 70.0;
    else if (vitesse >= 9.0)  score = 55.0;
    else score = 40.0;

    // ★ v9.93 POINT 2 : Ajustement selon la catégorie de course
    // Un cheval habitué aux courses de "Conditions" peut être déstabilisé
    // en "Handicap" où les poids sont redistribués selon le palmarès.
    // En "Réclamer" (claiming), les chevaux sont souvent en fin de cycle.
    final cat = course.categorie.toLowerCase();
    if (cat.contains('handicap')) {
      // En Handicap : les poids sont équilibrés → réduction de l'avantage vitesse
      score = (score * 0.92).clamp(0.0, 100.0);
    } else if (cat.contains('reclam') || cat.contains('claim')) {
      // Course réclameur : signal négatif sur la qualité du champ
      score = (score * 0.88).clamp(0.0, 100.0);
    } else if (cat.contains('condition') || cat.contains('listed') ||
               cat.contains('groupe') || cat.contains('group')) {
      // Course de conditions ou de Groupe : champ plus fort → signal positif
      // si le cheval est compétitif (score déjà élevé)
      if (score >= 70) score = (score * 1.06).clamp(0.0, 100.0);
    }

    return score;
  }

  static double _scoreDistanceSpecialite(ZtPartant p, ZtCourse course) {
    final distStr   = course.distance.replaceAll(RegExp(r'[^\d]'), '');
    final distCourse = int.tryParse(distStr) ?? 0;
    if (p.musiqueDistanceSpecifique.isNotEmpty && distCourse > 0) {
      final entries = p.musiqueDistanceSpecifique.split(',');
      final musiquesDist = <String>[];
      for (final entry in entries) {
        final parts = entry.split(':');
        if (parts.length == 2) {
          final dist = int.tryParse(parts[0]) ?? 0;
          if (dist > 0 && (dist - distCourse).abs() <= 100) {
            musiquesDist.add(parts[1]);
          }
        }
      }
      if (musiquesDist.isNotEmpty) return p.scoreFormeDistanceSpecifique;
    }
    if (distCourse > 0 && p.recordEnSecondes < 9999) {
      final vitesse    = distCourse / p.recordEnSecondes;
      final isGalop    = course.type.toLowerCase().contains('plat') ||
                         course.type.toLowerCase().contains('haie') ||
                         course.type.toLowerCase().contains('steeple');
      final vitesseMin = isGalop ? 13.0 : 8.5;
      if (vitesse >= vitesseMin) return (p.scoreForme * 1.15).clamp(0.0, 100.0);
    }
    return p.scoreForme * 0.90;
  }

  static double _scoreJockey(ZtPartant p) {
    final tauxVic = p.jockeyTauxVictoire;
    final tauxPlc = p.jockeyTauxPlace;
    if (tauxVic < 0) return 50.0;
    double score = 0.0;
    if (tauxVic >= 22)      score += 60.0;
    else if (tauxVic >= 18) score += 52.0;
    else if (tauxVic >= 15) score += 44.0;
    else if (tauxVic >= 12) score += 37.0;
    else if (tauxVic >= 10) score += 30.0;
    else if (tauxVic >= 7)  score += 22.0;
    else                     score += 14.0;
    if (tauxPlc >= 50)      score += 40.0;
    else if (tauxPlc >= 42) score += 33.0;
    else if (tauxPlc >= 35) score += 27.0;
    else if (tauxPlc >= 28) score += 20.0;
    else                     score += 12.0;
    return score.clamp(0.0, 100.0);
  }

  static double _scoreGains(String gains, ZtCourse course) {
    final gainsCourse = course.partants
        .map((p) => p.gainsInt).where((g) => g > 0).toList();
    if (gainsCourse.isEmpty) return 50.0;
    final maxGains = gainsCourse.reduce((a, b) => a > b ? a : b);
    final myGains  = _parseGains(gains);
    if (maxGains == 0) return 50.0;
    return ((myGains / maxGains) * 100.0).clamp(0.0, 100.0);
  }

  static int _parseGains(String gains) {
    final cleaned = gains.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(cleaned) ?? 0;
  }

  static double _scoreRecord(String record, ZtCourse course) {
    if (record.isEmpty) return 50.0;
    final records = course.partants
        .map((p) => p.recordEnSecondes).where((r) => r < 9999.0).toList();
    if (records.isEmpty) return 50.0;
    final myRecord    = _parseRecord(record);
    if (myRecord >= 9999.0) return 50.0;
    final bestRecord  = records.reduce((a, b) => a < b ? a : b);
    final worstRecord = records.reduce((a, b) => a > b ? a : b);
    final range       = worstRecord - bestRecord;
    if (range == 0) return 50.0;
    return ((worstRecord - myRecord) / range * 100).clamp(0.0, 100.0);
  }

  static double _parseRecord(String record) {
    // ★ v9.92 : dixièmes de seconde Trot ("1'15"4 ou 1'154)
    final m = RegExp(r"(\d+)'(\d{2})(?:[\x22\x27]?(\d))?").firstMatch(record);
    if (m == null) return 9999.0;
    final minutes  = double.parse(m.group(1)!);
    final secondes = double.parse(m.group(2)!);
    final dixieme  = m.group(3) != null ? double.parse(m.group(3)!) / 10.0 : 0.0;
    return minutes * 60 + secondes + dixieme;
  }

  static double _scoreCote(String cote) {
    if (cote.isEmpty) return 50.0;
    final c = double.tryParse(cote.replaceAll(',', '.')) ?? 99.0;
    if (c <= 0) return 50.0;
    return (95.0 - 28.0 * math.log(c.clamp(1.0, 999.0))).clamp(10.0, 95.0);
  }

  static double _scoreConstance(String musique) {
    if (musique.isEmpty) return 25.0;
    // Réutilise _extrairePositions interne
    final positions = _extrairePositions(musique);
    if (positions.isEmpty) return 25.0;
    final recent = positions.take(6).toList();
    int top5Count = 0; int top3Count = 0; int abandonCount = 0;
    for (final pos in recent) {
      if (pos == 99) { abandonCount++; continue; }
      if (pos <= 5) top5Count++;
      if (pos <= 3) top3Count++;
    }
    final ratioTop5   = top5Count    / recent.length;
    final ratioTop3   = top3Count    / recent.length;
    final ratioAbandon = abandonCount / recent.length;
    return ((ratioTop5 * 60.0 + ratioTop3 * 40.0) - ratioAbandon * 30.0)
        .clamp(0.0, 100.0);
  }

  static List<int> _extrairePositions(String musique) {
    if (musique.isEmpty) return [];
    final tokenRegex = RegExp(
      r'(?:\(|\))|([Aa][amhp])|([Dd][abmhp])|([Bb][amhp])|(0[amhp])|(1\d[amhp]|[2-9]\d[amhp]|[1-9][amhp])',
    );
    final result = <int>[];
    for (final m in tokenRegex.allMatches(musique)) {
      if (m.group(4) != null) {
        // ★ v9.92 : non-partant (0x) → ignoré silencieusement (pas de pénalité)
        continue;
      } else if (m.group(1) != null || m.group(2) != null || m.group(3) != null) {
        result.add(99); // arrêté/disq/tombé → pénalité
      } else if (m.group(5) != null) {
        final raw = m.group(5)!;
        result.add(int.tryParse(raw.substring(0, raw.length - 1)) ?? 99);
      }
    }
    return result;
  }

  // ══════════════════════════════════════════════════════════════════
  // LABELS ET EXPLICATIONS — inchangés + ajouts v8.0
  // ══════════════════════════════════════════════════════════════════

  static String _determinerLabel(int rang, double score, int index, int total) {
    // ★ v9.2 : seuils +5 pts après normalisation min/max
    if (rang == 1 && score >= 75) return '🥇 FAVORI IA';
    if (rang == 1 && score >= 52) return '⭐ SÉLECTION IA';
    if (rang == 1)                return '🎯 CHOIX IA';
    if (rang == 2)                return '🥈 2ème choix';
    if (rang == 3)                return '🥉 3ème choix';
    if (rang <= 5)                return '✅ À surveiller';
    if (rang > total - 2)         return '⚠️ Outsider';
    return '📊 Dans le lot';
  }

  static String _genererExplication(ZtPartant p, int rang, double score, ZtCourse course) {
    final raisons = <String>[];

    // Forme (v8.0 : avec tendance)
    final scoreForme = p.scoreFormeLong;
    if (scoreForme >= 75) {
      final tendance = p.tendanceLabel;
      raisons.add('Excellente forme récente $tendance');
    } else if (scoreForme >= 55) {
      raisons.add('Bonne forme (${_resumeMusique(p.musique)})');
    } else if (scoreForme <= 25) {
      raisons.add('Forme en baisse récemment');
    }

    // ELO v8.0
    if (p.eloRating > 0) {
      final elo = EloScore(nomCheval: p.nom, rating: p.eloRating,
          nbCourses: p.eloNbCourses, variationMois: p.eloVariationMois);
      if (p.eloRating >= 1700) raisons.add('ELO très élevé (${p.eloRating.round()}) — ${elo.niveau}');
      else if (p.eloRating >= 1600) raisons.add('Bon ELO (${p.eloRating.round()}) — ${elo.niveau}');
      if (p.eloVariationMois > 50) raisons.add('ELO en forte progression (+${p.eloVariationMois.round()} ce mois)');
    }

    // Entraîneur v8.0
    final scoreEntr = p.scoreEntraineur;
    if (scoreEntr >= 75 && p.entraineur.isNotEmpty) {
      raisons.add('Top entraîneur ${p.entraineur}');
    } else if (scoreEntr >= 60 && p.entraineur.isNotEmpty) {
      raisons.add('Bon entraîneur ${p.entraineur}');
    }

    // Victoires
    final nbV = p.nbVictoiresRecentes;
    if (nbV >= 3) raisons.add('$nbV victoires récentes');
    else if (nbV == 2) raisons.add('2 victoires récentes');
    else if (nbV == 1) raisons.add('1 victoire récente');

    // Gains
    final gains = p.gainsInt;
    if (gains >= 100000) raisons.add('Très bons gains de carrière (${_formatGains(gains)})');
    else if (gains >= 50000) raisons.add('Bons gains (${_formatGains(gains)})');

    // Record
    if (p.record.isNotEmpty) {
      final rec     = p.recordEnSecondes;
      final records = course.partants.map((pp) => pp.recordEnSecondes)
          .where((r) => r < 9999).toList();
      if (records.isNotEmpty && rec < 9999) {
        records.sort();
        if (rec == records.first) raisons.add('Meilleur record du champ (${p.record})');
        else if (records.length > 2 && rec <= records[2]) raisons.add('Bon record (${p.record})');
      }
    }

    // Cote
    if (p.cote.isNotEmpty) {
      final c = double.tryParse(p.cote.replaceAll(',', '.')) ?? 99.0;
      if (c <= 3.0) raisons.add('Grand favori du marché (×${p.cote})');
      else if (c <= 5.0) raisons.add('Favori (×${p.cote})');
      else if (c >= 10.0 && rang <= 3) raisons.add('Outsider à surveiller (×${p.cote})');
    }

    // Jockey
    final tauxVic = p.jockeyTauxVictoire;
    if (tauxVic >= 0 && p.driver.isNotEmpty) {
      if (tauxVic >= 18) raisons.add('Top jockey ${p.driver} (${tauxVic.round()}% vic)');
      else if (tauxVic >= 12) raisons.add('Bon jockey ${p.driver}');
    }

    // Repos
    final repos = p.joursRepos;
    if (repos >= 14 && repos <= 35) raisons.add('Fraîcheur optimale (${repos}j)');
    else if (repos > 55) raisons.add('Longue absence (${repos}j)');
    else if (repos >= 1 && repos <= 6) raisons.add('Course récente (${repos}j) — possible fatigue');

    // Distance spécialité
    final scoreDistSpec = _scoreDistanceSpecialite(p, course);
    if (scoreDistSpec >= 78 && p.musiqueDistanceSpecifique.isNotEmpty) {
      raisons.add('Spécialiste de la distance');
    }

    // ★ v9.0 — Terrain
    final sT = p.scoreTerrain(course.piste);
    if (sT >= 75 && course.piste.isNotEmpty) {
      raisons.add('Excellent sur terrain ${course.piste}');
    } else if (sT <= 30 && course.piste.isNotEmpty) {
      raisons.add('Mauvais résultats sur terrain ${course.piste}');
    }

    // ★ v9.0 — Coup préparé (divergence forme/cote)
    final sDiv = p.scoreDivergenceFormeCote;
    if (sDiv >= 80) {
      raisons.add('⚡ Coup préparé possible — sous-coté (×${p.cote})');
    } else if (sDiv <= 30) {
      raisons.add('Faux favori — cote trop basse vs forme réelle');
    }

    // ★ v9.0 — Progression
    final sProg = p.scoreProgression;
    if (sProg >= 72) {
      final ageMatch = RegExp(r'\d+').firstMatch(p.ageSexe);
      final age = ageMatch != null ? ageMatch.group(0) : '';
      raisons.add('Cheval en progression ($age ans, tendance haussière)');
    }

    if (raisons.isEmpty) {
      return rang <= 3 ? 'Profil intéressant sur critères multiples' : 'Critères limités — outsider';
    }
    return raisons.join(' • ');
  }

  static String _resumeMusique(String musique) {
    final positions = RegExp(r'\b(\d+)[amph]\b').allMatches(musique).toList();
    final recent    = positions.take(5).map((m) => m.group(1)!).toList();
    if (recent.isEmpty) return 'pas de données';
    return recent.join('-');
  }

  static String _formatGains(int gains) {
    if (gains >= 1000000) return '${(gains / 1000000).toStringAsFixed(1)}M€';
    if (gains >= 1000)    return '${(gains / 1000).toStringAsFixed(0)}k€';
    return '${gains}€';
  }

  // ══════════════════════════════════════════════════════════════════
  // GÉNÉRATION DU PRONOSTIC COMPLET
  // ══════════════════════════════════════════════════════════════════
  static PronosticIA genererPronostic(ZtCourse course, String hippodrome) {
    final partantsScores = analyserCourse(course);
    final sorted = [...partantsScores]..sort((a, b) => a.rang.compareTo(b.rang));
    final top5   = sorted.take(5).toList();
    final selection = top5.map((p) => p.numero).join(' - ');

    double confiance = 40.0;
    if (sorted.isNotEmpty) {
      final s1 = sorted[0].scoreIA;
      final s2 = sorted.length >= 2 ? sorted[1].scoreIA : s1;
      final s3 = sorted.length >= 3 ? sorted[2].scoreIA : s2;
      final qualiteFavori = s1.clamp(0.0, 100.0) * 0.40;
      final dominance     = ((s1 - s2).clamp(0.0, 50.0) / 50.0) * 40.0;
      final cohesionTop3  = ((s2 + s3) / 2.0).clamp(0.0, 100.0) * 0.20;
      final scoreBrut     = qualiteFavori + dominance + cohesionTop3;
      confiance = (40.0 + scoreBrut * 0.55).clamp(40.0, 95.0);

      // ★ v9.2 : Ajustement de confiance par variance réelle du champ
      // Si tous les scores sont serrés (champ homogène) → confiance réduite
      // Si les scores sont bien dispersés (favori dominant) → confiance préservée
      if (sorted.length >= 4) {
        final allScores = sorted.map((p) => p.scoreIA).toList();
        final mean = allScores.reduce((a, b) => a + b) / allScores.length;
        final variance = allScores
            .map((s) => (s - mean) * (s - mean))
            .reduce((a, b) => a + b) / allScores.length;
        // variance élevée (>150) = champ bien dispersé = confiance ok
        // variance faible  (<50)  = champ très serré   = malus confiance
        final facteurVariance = (variance / 150.0).clamp(0.70, 1.05);
        confiance = (confiance * facteurVariance).clamp(40.0, 95.0);
      }

      // ★ v8.0 : ajustement par calibration ET par seuils hippodrome
      final calib = IaCalibrationRegistry.value;
      final facteurCalib = (calib / 50.0).clamp(0.85, 1.10);
      confiance = (confiance * facteurCalib).clamp(40.0, 95.0);
    }

    final conseil = _determinerConseil(course, sorted);
    final analyse = _genererAnalyseTextuelle(course, sorted, hippodrome);

    return PronosticIA(
      numCourse: course.numCourse.toString(),
      nomCourse: course.nom,
      heure: course.heure,
      hippodrome: hippodrome,
      top5: top5,
      selection: selection,
      confianceGlobale: confiance,
      analyseTextuelle: analyse,
      conseil: conseil,
    );
  }

  static String determinerConseilPublic(ZtCourse course) {
    return _determinerConseil(course, course.partantsParRangIA);
  }

  static String _determinerConseil(ZtCourse course, List<ZtPartant> sorted) {
    final nbPartants = course.partants.length;
    final score1  = sorted.isNotEmpty         ? sorted[0].scoreIA : 0.0;
    final score2  = sorted.length >= 2        ? sorted[1].scoreIA : 0.0;
    final score3  = sorted.length >= 3        ? sorted[2].scoreIA : 0.0;
    final score4  = sorted.length >= 4        ? sorted[3].scoreIA : 0.0;
    final ecart12 = score1 - score2;

    if (course.isQuinte) {
      // ★ v9.2 : seuils +5 pts après normalisation min/max
      if (score1 >= 80 && score2 >= 65 && score3 >= 58)
        return 'Quinté+ : jouer les 5 numéros sélectionnés — IA confiante';
      if (score1 >= 70 && score2 >= 58)
        return 'Quarté+ conseillé — confiance suffisante sur le top 4 (Quinté+ risqué)';
      if (score1 >= 60 && score2 >= 52)
        return 'Tiercé dans l\'ordre — confiance limitée, éviter le Quinté+';
      if (score1 >= 48)
        return 'Couplé gagnant N°${sorted[0].numero}–N°${sorted[1].numero} — confiance trop faible pour le Quinté+';
      return 'À surveiller — scores IA insuffisants, passer cette course';
    }

    if (score1 >= 80 && ecart12 >= 30)
      return 'Simple gagnant — favori IA très dominant (N°${sorted[0].numero})';
    if (score1 >= 70 && score2 >= 62 && score3 >= 57 && score4 >= 52 && nbPartants >= 10)
      return 'Quarté+ conseillé — 4 candidats fiables (N°${sorted[0].numero}, ${sorted[1].numero}, ${sorted[2].numero}, ${sorted[3].numero})';
    if (score1 >= 65 && score2 >= 58 && score3 >= 57)
      return nbPartants <= 8
          ? 'Tiercé dans l\'ordre — 3 candidats fiables'
          : 'Tiercé ou Quarté+ dans l\'ordre — 3 candidats fiables';
    if (score1 >= 65 && score2 >= 52)
      return 'Couplé gagnant N°${sorted[0].numero}–N°${sorted[1].numero} — 3ᵉ place incertaine (${score3.toStringAsFixed(0)}/100)';
    if (score1 >= 65)
      return 'Simple gagnant N°${sorted[0].numero} — reste du tiercé peu fiable';
    if (nbPartants <= 8) return 'Simple gagnant ou couplé — scores IA limités';
    return 'Couplé gagnant — tiercé déconseillé (scores trop proches)';
  }

  static String _genererAnalyseTextuelle(
      ZtCourse course, List<ZtPartant> sorted, String hippodrome) {
    if (sorted.isEmpty) return 'Analyse indisponible — pas de partants.';
    final leader = sorted[0];
    final type   = course.type.isNotEmpty ? course.type : 'course';
    final buffer = StringBuffer();
    buffer.write('📍 $hippodrome | ${course.heure} | $type | ${course.distance}\n\n');
    buffer.write('🏆 Notre sélection IA: ');
    buffer.write(sorted.take(5).map((p) => '${p.numero}·${p.nom}').join(', '));
    buffer.write('\n\n');
    buffer.write('🎯 ${leader.nom} (N°${leader.numero}) est notre favori IA — ');
    buffer.write(leader.explicationIA);
    buffer.write('.\n\n');
    if (sorted.length >= 2) {
      final second = sorted[1];
      buffer.write('💡 ${second.nom} (N°${second.numero}) à surveiller — ');
      buffer.write(second.explicationIA);
      buffer.write('.\n');
    }
    return buffer.toString();
  }

  // ══════════════════════════════════════════════════════════════════
  // UTILITAIRES
  // ══════════════════════════════════════════════════════════════════
  // ★ v9.93 ── S. PLACE AU DÉPART / CORDE ─────────────────────────────────
  // Disponible dès la publication des partants (veille ou matin J).
  //
  // Calibration réaliste basée sur statistiques PMU :
  //   Trot longue distance : +8 à +12% pour les 3 premières places
  //   Trot courte distance : +5 à +8% pour les 4 premières places
  //   Galop courte piste   : impact faible (+3 à +5%)
  //
  // Score centré sur 50 — plage réduite (38-65) pour ne pas
  // distordre les critères plus discriminants (Forme, ELO, etc.).
  static double _scorePlaceDepart(int place, int nbPartants, String type, String distance) {
    if (place <= 0 || nbPartants <= 0) return 50.0;
    final isTrot  = type.toLowerCase().contains('trot') ||
                    type.toLowerCase().contains('attele') ||
                    type.toLowerCase().contains('monte');
    final distM   = int.tryParse(distance.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    if (isTrot) {
      if (distM >= 2200) {
        // Longue distance — avantage première ligne documenté (~+10%)
        if (place <= 3)  return 65.0;
        if (place <= 6)  return 55.0;
        if (place <= 9)  return 47.0;
        return 38.0;
      } else {
        // Courte/moyenne distance — avantage moins marqué (~+6%)
        if (place <= 2)  return 62.0;
        if (place <= 4)  return 55.0;
        if (place <= 6)  return 50.0;
        if (place <= 9)  return 45.0;
        return 40.0;
      }
    } else if (distM > 0 && distM <= 1400) {
      // Galop courte distance — impact corde faible (~+4%)
      final ratio = place / nbPartants;
      if (ratio <= 0.20) return 58.0;
      if (ratio <= 0.40) return 54.0;
      if (ratio <= 0.70) return 48.0;
      return 43.0;
    }
    return 50.0; // Galop longue distance ou type non concerné
  }


  static String _buildCourseKey(ZtCourse course) {
    // Format attendu par CoteTrackerService : "RNCN_DDMMYYYY"
    // On utilise dateStr du cours s'il est disponible
    if (course.dateStr.length == 8) {
      // dateStr = DDMMYYYY
      final day   = course.dateStr.substring(0, 2);
      final month = course.dateStr.substring(2, 4);
      final year  = course.dateStr.substring(4, 8);
      // On ne connaît pas numR ici → on utilise un placeholder
      // CoteTrackerService construit ses clés sans numR dans les mouvements
      return 'C${course.numCourse}_$day$month$year';
    }
    final now = DateTime.now();
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    return 'C${course.numCourse}_$d$m${now.year}';
  }

  static int scoreColor(double score) {
    if (score >= 80) return 0xFF00C853;
    if (score >= 65) return 0xFF64DD17;
    if (score >= 50) return 0xFFFFD600;
    if (score >= 35) return 0xFFFF6D00;
    return 0xFFD50000;
  }

  static int labelColor(String label) {
    if (label.contains('FAVORI'))    return 0xFFFFD700;
    if (label.contains('SÉLECTION')) return 0xFF4CAF50;
    if (label.contains('2ème'))      return 0xFF90CAF9;
    if (label.contains('3ème'))      return 0xFFCE93D8;
    if (label.contains('surveiller')) return 0xFF80DEEA;
    if (label.contains('Outsider'))  return 0xFFFF8A65;
    return 0xFFB0BEC5;
  }
}
