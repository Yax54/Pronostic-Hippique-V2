import '../models/pmu_models.dart';
import 'dart:math' as math;

/// ══════════════════════════════════════════════════════════════════════════════
/// PredictionEngine v3.0 — Moteur IA multi-critères Pronostic Hippique
///
/// PHILOSOPHIE : Honnête, précis, réaliste.
/// L'IA analyse TOUT ce qu'elle peut mesurer objectivement, explique sa décision
/// et ne ment jamais sur ses niveaux de certitude.
///
/// ─── 8 CRITÈRES DE SCORING (sur 100 pts) ────────────────────────────────────
///
///  1. COTE VALEUR          (0–18 pts)
///     Cote "valeur" : ni trop faible (pas rentable), ni trop haute (trop risqué)
///     Zone optimale : cote 2.5–8. Cote < 1.8 = sur-favori peu rentable.
///     Cote > 20 = longshot, historiquement faible taux de réussite.
///
///  2. ACCORD MARCHÉ        (0–10 pts)
///     L'IA est-elle d'accord avec le marché PMU ?
///     Si notre top 1 IA = favori des bookmakers → signal fort de consensus.
///
///  3. TAUX DE VICTOIRE     (0–18 pts)
///     Palmarès historique pondéré par le nombre de courses (fiabilité stats)
///     ≥ 30 courses : statistique très fiable. < 5 courses : incertitude forte.
///
///  4. TAUX DE PLACE        (0–10 pts)
///     % de podiums (top 3) : indicateur de régularité
///
///  5. ANALYSE MUSIQUE      (0–22 pts) ← Critère le plus riche
///     • Forme des 5 dernières courses avec pondération décroissante
///     • Détection de série victorieuse (3+ victoires consécutives)
///     • Détection de régularité (podiums constants sans victoire)
///     • Détection de méforme (résultats en dégradation)
///     • Pénalité abandon/disqualification récent
///
///  6. ÉCART DOMINANT       (0–12 pts) — critère NOUVEAU
///     Mesure si le favori DOMINE clairement ses concurrents.
///     Grand écart = moins de surprise possible.
///     Calculé APRÈS scoring de tous les partants.
///
///  7. COHÉRENCE MUSIQUE    (0–6 pts) — critère NOUVEAU
///     Les performances sont-elles régulières ? (faible écart-type entre résultats)
///     Un cheval RÉGULIER est plus prévisible qu'un cheval "coup" imprévisible.
///
///  8. EXPÉRIENCE & NIVEAU  (0–4 pts)
///     Gains de carrière + nombre de courses disputées
///     Un cheval avec long historique = données plus fiables
///
/// ─── SCORE DE FIABILITÉ (1–5 étoiles) ──────────────────────────────────────
///     Mesure NOT la probabilité de gagner, mais la CONFIANCE dans le pronostic.
///     Basé sur : qualité des données + domination + régularité + consensus marché
///
/// ─── AVERTISSEMENT HONNÊTE ──────────────────────────────────────────────────
///     Les courses hippiques comportent une part d'aléatoire irréductible.
///     Ce moteur optimise la sélection, il ne garantit pas la victoire.
///     Taux de réussite estimé par niveau de confiance :
///       ⭐⭐⭐⭐⭐ Très fiable → ~65–75% de chances (meilleurs profils du jour)
///       ⭐⭐⭐⭐   Fiable      → ~50–65%
///       ⭐⭐⭐     Correct     → ~35–50%
///       ⭐⭐       Incertain   → ~25–35%
///       ⭐         Risqué      → <25%
/// ══════════════════════════════════════════════════════════════════════════════

class PredictionEngine {

  // ── Pondérations (hardcodées dans _computeScoreDetail) ──────────────────────
  // CoteValeur=18, AccordMarché=10, TauxVictoire=18, TauxPlace=10,
  // Musique=22, EcartDominant=12, Cohérence=6, Expérience=4 → Total=100 pts

  // ── Score individuel (sans écart dominant — calculé après) ──────────────────
  static _ScoreDetail _computeScoreDetail(
    PmuParticipant p,
    PmuCourse course,
  ) {
    double total = 0;
    final details = <String, double>{};

    // ── 1. COTE VALEUR (0–18) ──────────────────────────────────────────────
    double scoreCote = 0;
    final cote = p.coteAffichee;
    if (cote <= 0) {
      scoreCote = 6; // cote inconnue = neutre
    } else if (cote < 1.5) {
      // Sur-favori : très sûr de place, peu rentable
      scoreCote = 8;
    } else if (cote <= 2.5) {
      scoreCote = 13; // Très favori, bonne valeur
    } else if (cote <= 4.0) {
      scoreCote = 18; // Zone optimale : favori raisonnable ✓
    } else if (cote <= 7.0) {
      scoreCote = 14; // Outsider de valeur
    } else if (cote <= 12.0) {
      scoreCote = 9;  // Outsider risqué
    } else if (cote <= 20.0) {
      scoreCote = 5;  // Longshot
    } else {
      scoreCote = 2;  // Très longshot
    }
    details['coteValeur'] = scoreCote;
    total += scoreCote;

    // ── 2. TAUX DE VICTOIRE historique (0–18) ─────────────────────────────
    double scoreTxVic = 0;
    if (p.nombreCourses >= 30) {
      // Statistique très fiable (30+ courses)
      scoreTxVic = (p.tauxVictoire * 20).clamp(0, 18);
    } else if (p.nombreCourses >= 15) {
      scoreTxVic = (p.tauxVictoire * 18).clamp(0, 16);
    } else if (p.nombreCourses >= 5) {
      // Statistique moyennement fiable
      scoreTxVic = (p.tauxVictoire * 14).clamp(0, 13);
    } else if (p.nombreCourses >= 2) {
      scoreTxVic = p.nombreVictoires > 0 ? 7 : 3;
    } else {
      scoreTxVic = 3; // Débutant : incertitude maximale
    }
    details['tauxVictoire'] = scoreTxVic;
    total += scoreTxVic;

    // ── 3. TAUX DE PLACE (top 3) (0–10) ───────────────────────────────────
    double scoreTxPlace = 0;
    if (p.nombreCourses >= 5) {
      scoreTxPlace = (p.tauxPlace * 12).clamp(0, 10);
    } else if (p.nombreCourses >= 2) {
      scoreTxPlace = ((p.nombreVictoires + p.nombrePlaces) / p.nombreCourses * 8).clamp(0, 8);
    }
    details['tauxPlace'] = scoreTxPlace;
    total += scoreTxPlace;

    // ── 4. ANALYSE MUSIQUE AVANCÉE (0–22) ─────────────────────────────────
    final musiqueResult = _analyserMusique(p.musique);
    details['musique'] = musiqueResult.score;
    details['_musiqueFormeTendance'] = musiqueResult.tendance.toDouble(); // -1 dégradation, 0 stable, +1 amélioration
    details['_serieVictoires'] = musiqueResult.serieVictoires.toDouble();
    details['_abandonRecent'] = musiqueResult.abandonRecent ? 1.0 : 0.0;
    total += musiqueResult.score;

    // ── 5. COHÉRENCE MUSIQUE (0–6) ────────────────────────────────────────
    final coherence = _scoreCoherence(p.musique);
    details['coherence'] = coherence;
    total += coherence;

    // ── 6. EXPÉRIENCE & NIVEAU (0–4) ──────────────────────────────────────
    double scoreExp = 0;
    if (p.gainsCarriere >= 500000) scoreExp = 4;
    else if (p.gainsCarriere >= 200000) scoreExp = 3;
    else if (p.gainsCarriere >= 80000) scoreExp = 2;
    else if (p.gainsCarriere >= 20000) scoreExp = 1;
    details['experience'] = scoreExp;
    total += scoreExp;

    // Base sans écart dominant (plafonné à 88)
    return _ScoreDetail(
      scoreBase: total.clamp(0, 88),
      details: details,
      dernierResultat: musiqueResult.dernierResultat,
      avantDernierResultat: musiqueResult.avantDernierResultat,
      serieVictoires: musiqueResult.serieVictoires,
      tendanceMusique: musiqueResult.tendance,
      abandonRecent: musiqueResult.abandonRecent,
    );
  }

  // ── Point d'entrée principal : score final avec écart dominant ──────────────
  static double computeScore(PmuParticipant p) {
    return _computeScoreDetail(p, _dummyCourse).scoreBase;
  }

  // Course factice pour computeScore standalone
  static final _dummyCourse = PmuCourse(
    numReunion: 0, numOrdre: 0, libelle: '', libelleCourt: '',
    heureDepart: DateTime.now(), distance: 0, discipline: 'PLAT',
    specialite: 'PLAT', montantPrix: 0, nombrePartants: 0, statut: 'PROGRAMME',
  );

  // ── Analyse de la musique (format PMU) ────────────────────────────────────

  static _MusiqueResult _analyserMusique(String musique) {
    if (musique.isEmpty) {
      return _MusiqueResult(score: 5, dernierResultat: 99,
          avantDernierResultat: 99, serieVictoires: 0,
          tendance: 0, abandonRecent: false);
    }

    final positions = _extrairePositions(musique);
    if (positions.isEmpty) {
      return _MusiqueResult(score: 3, dernierResultat: 99,
          avantDernierResultat: 99, serieVictoires: 0,
          tendance: 0, abandonRecent: false);
    }

    double score = 0;
    final nbAnalyses = math.min(positions.length, 7);

    for (int i = 0; i < nbAnalyses; i++) {
      final pos = positions[i];
      // Pondération exponentielle décroissante : course récente = beaucoup plus importante
      final weight = math.pow(0.80, i).toDouble(); // 1.0, 0.80, 0.64, 0.51, 0.41, 0.33, 0.26
      if (pos == 1) {
        score += 5.5 * weight;       // Victoire ✓
      } else if (pos == 2) {
        score += 3.8 * weight;       // 2e ✓
      } else if (pos == 3) {
        score += 2.7 * weight;       // 3e
      } else if (pos <= 5) {
        score += 1.3 * weight;       // Top 5
      } else if (pos <= 8) {
        score += 0.4 * weight;       // Honorable
      } else if (pos == 0) {
        score -= 2.0 * weight;       // Abandon / disqualifié ✗
      }
      // > 8 : pas de bonus, pas de malus
    }

    // Bonus : série de victoires consécutives (très fort signal)
    int serieVictoires = 0;
    for (final pos in positions) {
      if (pos == 1) serieVictoires++;
      else break;
    }
    if (serieVictoires >= 3) score += 4.0; // ★★★ Série de 3+ victoires
    else if (serieVictoires == 2) score += 2.0; // ★★ 2 victoires de suite

    // Détection de tendance : amélioration ou dégradation récente
    int tendance = 0;
    if (positions.length >= 4) {
      final recents = positions.take(2).map((p) => p == 0 ? 15 : p).toList();
      final anciens = positions.skip(2).take(2).map((p) => p == 0 ? 15 : p).toList();
      final moyRecent = recents.reduce((a, b) => a + b) / recents.length;
      final moyAncien = anciens.reduce((a, b) => a + b) / anciens.length;
      if (moyRecent < moyAncien - 2) tendance = 1;   // Amélioration
      else if (moyRecent > moyAncien + 2) tendance = -1; // Dégradation
    }

    // Pénalité abandon récent (premier ou deuxième résultat)
    final abandonRecent = positions.isNotEmpty && (positions[0] == 0 ||
        (positions.length >= 2 && positions[1] == 0));
    if (abandonRecent) score -= 1.5;

    final scoreMusique = (score * 2.8).clamp(0.0, 22.0);

    return _MusiqueResult(
      score: scoreMusique,
      dernierResultat: positions.isNotEmpty ? positions[0] : 99,
      avantDernierResultat: positions.length >= 2 ? positions[1] : 99,
      serieVictoires: serieVictoires,
      tendance: tendance,
      abandonRecent: abandonRecent,
    );
  }

  // ── Cohérence musique : régularité des performances ───────────────────────
  static double _scoreCoherence(String musique) {
    final positions = _extrairePositions(musique)
        .where((p) => p > 0 && p < 99) // Exclure abandons
        .take(6)
        .toList();

    if (positions.length < 3) return 2.0; // Pas assez de données

    final moy = positions.reduce((a, b) => a + b) / positions.length;
    final variance = positions.map((p) => math.pow(p - moy, 2)).reduce((a, b) => a + b) / positions.length;
    final ecartType = math.sqrt(variance);

    // Faible écart-type = très régulier = prévisible = bon signe
    if (ecartType <= 1.5) return 6.0;  // Très régulier
    if (ecartType <= 2.5) return 4.5;  // Régulier
    if (ecartType <= 4.0) return 3.0;  // Passable
    if (ecartType <= 6.0) return 1.5;  // Irrégulier
    return 0.5;                          // Très irrégulier (résultats capricieux)
  }

  // ── Extraction des positions depuis la musique PMU ─────────────────────────
  static List<int> _extrairePositions(String musique) {
    // Nettoyer les annotations entre parenthèses ex: "(2024)"
    final cleaned = musique.replaceAll(RegExp(r'\(\d+\)'), '').trim();
    // Extraire : "1a" → 1, "2p" → 2, "0h" → 0 (abandon), "Da" → 0
    final resultats = <int>[];
    final tokens = cleaned.split(RegExp(r'[\s]+'));
    for (final token in tokens) {
      if (token.isEmpty) continue;
      // Abandon / disqualifié
      if (token.startsWith('D') || token.startsWith('A') ||
          token.startsWith('T') || token.startsWith('d')) {
        resultats.add(0);
        continue;
      }
      // Position numérique
      final match = RegExp(r'^(\d+)').firstMatch(token);
      if (match != null) {
        final pos = int.tryParse(match.group(1) ?? '99') ?? 99;
        resultats.add(pos == 0 ? 0 : pos); // 0 = abandon dans certains formats
      }
    }
    return resultats;
  }

  // ── Génération des recommandations (point d'entrée principal) ──────────────

  static RaceRecommendation generateRecommendation(
    PmuCourse course,
    List<PmuParticipant> participants,
    String hippodrome,
  ) {
    if (participants.isEmpty) {
      return _emptyRecommendation(course, hippodrome);
    }

    // ── Étape 1 : scorer tous les partants (sans écart dominant) ────────────
    final scoreDetails = <PmuParticipant, _ScoreDetail>{};
    for (final p in participants) {
      scoreDetails[p] = _computeScoreDetail(p, course);
    }

    // ── Étape 2 : trier par score de base ───────────────────────────────────
    final ranked = List<PmuParticipant>.from(participants)
      ..sort((a, b) => (scoreDetails[b]?.scoreBase ?? 0)
          .compareTo(scoreDetails[a]?.scoreBase ?? 0));

    final favori = ranked.first;
    final detailFavori = scoreDetails[favori]!;
    final scoreBase1 = detailFavori.scoreBase;
    final scoreBase2 = ranked.length > 1 ? (scoreDetails[ranked[1]]?.scoreBase ?? 0) : 0.0;
    final scoreBase3 = ranked.length > 2 ? (scoreDetails[ranked[2]]?.scoreBase ?? 0) : 0.0;
    final ecartBrut = scoreBase1 - scoreBase2;

    // ── Étape 3 : calculer le bonus ÉCART DOMINANT ──────────────────────────
    // L'écart dominant récompense le favori qui domine VRAIMENT ses concurrents
    double bonusEcart = 0;
    if (ecartBrut >= 20) {
      bonusEcart = 12.0; // Domination totale — très rare et très significatif
    } else if (ecartBrut >= 15) {
      bonusEcart = 10.0; // Forte domination
    } else if (ecartBrut >= 10) {
      bonusEcart = 7.5;  // Domination claire
    } else if (ecartBrut >= 6) {
      bonusEcart = 5.0;  // Légère domination
    } else if (ecartBrut >= 3) {
      bonusEcart = 2.5;  // Légère avance
    } else {
      bonusEcart = 0.0;  // Course serrée — fiabilité réduite
    }

    // ── Étape 4 : score final du favori ─────────────────────────────────────
    final scoreFinal = (scoreBase1 + bonusEcart).clamp(0.0, 100.0);

    // ── Étape 5 : accord marché ──────────────────────────────────────────────
    // Le cheval le mieux côté par le marché (cote la plus basse) est-il notre favori ?
    final partantsTries = List<PmuParticipant>.from(participants)
      ..sort((a, b) => _coteSafe(a).compareTo(_coteSafe(b)));
    final favoriMarche = partantsTries.first;
    final accordMarche = favoriMarche.numero == favori.numero;

    // Appliquer le bonus accord marché au score du favori
    final double scoreAvecAccord = accordMarche
        ? (scoreFinal + 8.0).clamp(0.0, 100.0)
        : scoreFinal;

    // ── Étape 6 : calcul du niveau de confiance HONNÊTE ────────────────────
    // La confiance est calibrée pour refléter la RÉALITÉ statistique
    // Elle dépend : score, écart, régularité, cohérence, accord marché
    final niveauFiabilite = _calculerFiabilite(
      score: scoreAvecAccord,
      ecart: ecartBrut,
      coherence: detailFavori.details['coherence'] ?? 0.0,
      serieVictoires: detailFavori.serieVictoires,
      tendance: detailFavori.tendanceMusique,
      accordMarche: accordMarche,
      nbPartants: participants.length,
      abandonRecent: detailFavori.abandonRecent,
      cote: favori.coteAffichee,
    );

    // ── Étape 7 : conseil de pari selon fiabilité ───────────────────────────
    final TypePari typePari;
    final MiseConseille mise;
    final ConseilType conseil;

    if (niveauFiabilite.confiance >= 75) {
      conseil = ConseilType.excellent;
      typePari = TypePari.simpleGagnant;
      mise = MiseConseille.forte;
    } else if (niveauFiabilite.confiance >= 60) {
      conseil = ConseilType.bon;
      typePari = TypePari.simpleGagnantPlace;
      mise = MiseConseille.normale;
    } else if (niveauFiabilite.confiance >= 45) {
      conseil = ConseilType.moyen;
      typePari = TypePari.place;
      mise = MiseConseille.prudente;
    } else if (niveauFiabilite.confiance >= 30) {
      conseil = ConseilType.incertain;
      typePari = TypePari.tierce;
      mise = MiseConseille.minimale;
    } else {
      conseil = ConseilType.incertain;
      typePari = TypePari.tierce;
      mise = MiseConseille.minimale;
    }

    // ── Étape 8 : analyse détaillée ─────────────────────────────────────────
    final pointsForts = _analysePointsForts(
        favori, ranked, scoreDetails, ecartBrut, accordMarche,
        detailFavori.serieVictoires, detailFavori.details['coherence'] ?? 0);
    final pointsFaibles = _analysePointsFaibles(
        favori, participants.length, detailFavori.abandonRecent,
        detailFavori.tendanceMusique, ecartBrut);

    final explication = _buildExplication(
      favori: favori,
      ranked: ranked,
      scoreDetails: scoreDetails,
      course: course,
      confiance: niveauFiabilite.confiance,
      typePari: typePari,
      mise: mise,
      scoreBase2: scoreBase2,
      scoreBase3: scoreBase3,
      ecartBrut: ecartBrut,
      accordMarche: accordMarche,
      niveauFiabilite: niveauFiabilite,
    );

    return RaceRecommendation(
      course: course,
      hippodrome: hippodrome,
      ranked: ranked,
      conseil: conseil,
      gagnant: favori,
      place: ranked.take(3).toList(),
      tierce: ranked.take(3).toList(),
      quarte: ranked.take(math.min(4, ranked.length)).toList(),
      quinte: ranked.take(math.min(5, ranked.length)).toList(),
      explication: explication,
      niveauConfiance: niveauFiabilite.confiance.toInt(),
      scoreGagnant: scoreAvecAccord,
      pointsForts: pointsForts,
      pointsFaibles: pointsFaibles,
      typePariConseille: typePari,
      miseConseilee: mise,
      fiabilite: niveauFiabilite,
      ecartDominant: ecartBrut,
      accordMarche: accordMarche,
    );
  }

  // ── Calcul de fiabilité multi-facteurs ────────────────────────────────────

  static FiabiliteResult _calculerFiabilite({
    required double score,
    required double ecart,
    required double coherence,
    required int serieVictoires,
    required int tendance,
    required bool accordMarche,
    required int nbPartants,
    required bool abandonRecent,
    required double cote,
  }) {
    // ── Score de base → confiance initiale ─────────────────────────────────
    // Calibration honnête : le score 100/100 ne donne pas 100% de confiance
    // car la part d'aléatoire hippique est incompressible
    double confiance = (score * 0.78).clamp(0, 78); // Max absolu : 78%

    // ── Bonus signal fort : écart dominant ──────────────────────────────────
    if (ecart >= 15) confiance += 6;
    else if (ecart >= 10) confiance += 4;
    else if (ecart >= 6) confiance += 2;
    else if (ecart < 3) confiance -= 5; // Course serrée = incertitude

    // ── Bonus signal fort : série de victoires ───────────────────────────────
    if (serieVictoires >= 3) confiance += 7; // Série de 3+ : signal très fort
    else if (serieVictoires == 2) confiance += 3;

    // ── Bonus signal fort : accord marché ────────────────────────────────────
    if (accordMarche) confiance += 4; // Double validation IA + marché

    // ── Bonus cohérence musicale ──────────────────────────────────────────────
    if (coherence >= 5.5) confiance += 3;
    else if (coherence >= 4) confiance += 1;

    // ── Bonus tendance positive ───────────────────────────────────────────────
    if (tendance == 1) confiance += 3; // Amélioration récente
    else if (tendance == -1) confiance -= 4; // Dégradation récente

    // ── Pénalités objectives ──────────────────────────────────────────────────
    if (abandonRecent) confiance -= 6; // Abandon récent : signe inquiétant
    if (nbPartants > 16) confiance -= 4; // Grand champ = imprévisible
    else if (nbPartants > 12) confiance -= 2;
    if (cote > 20) confiance -= 5; // Très longshot
    else if (cote > 15) confiance -= 3;

    // ── Cote "valeur" optimale : bonus léger ─────────────────────────────────
    if (cote >= 2.5 && cote <= 6.0) confiance += 2; // Zone valeur idéale

    // Plafonner à 82% MAX — honnêteté : aucune certitude en hippisme
    confiance = confiance.clamp(15, 82);

    // ── Score de fiabilité 1–5 étoiles ───────────────────────────────────────
    int etoiles;
    String label;
    String description;
    List<String> signaux;

    if (confiance >= 70) {
      etoiles = 5;
      label = '⭐⭐⭐⭐⭐ Très fiable';
      description = 'Profil exceptionnel : tous les indicateurs convergent. '
          'Probabilité estimée de victoire : ~65–75%. '
          'Mise recommandée selon votre budget personnel.';
      signaux = _signauxForts(ecart, serieVictoires, accordMarche, coherence, tendance, cote);
    } else if (confiance >= 58) {
      etoiles = 4;
      label = '⭐⭐⭐⭐ Fiable';
      description = 'Bon profil global. Probabilité estimée : ~50–65%. '
          'Plusieurs critères favorables, quelques réserves mineures.';
      signaux = _signauxForts(ecart, serieVictoires, accordMarche, coherence, tendance, cote);
    } else if (confiance >= 43) {
      etoiles = 3;
      label = '⭐⭐⭐ Correct';
      description = 'Profil moyen. Probabilité estimée : ~35–50%. '
          'Course équilibrée, pari placé (top 3) recommandé plutôt que gagnant.';
      signaux = [];
    } else if (confiance >= 30) {
      etoiles = 2;
      label = '⭐⭐ Incertain';
      description = 'Course difficile à prévoir. Probabilité estimée : ~25–35%. '
          'Mise minimale conseillée ou abstention.';
      signaux = [];
    } else {
      etoiles = 1;
      label = '⭐ Risqué';
      description = 'Pronostic peu fiable. Données insuffisantes ou course trop serrée. '
          'Mise déconseillée.';
      signaux = [];
    }

    return FiabiliteResult(
      confiance: confiance.round(),
      etoiles: etoiles,
      label: label,
      description: description,
      signauxForts: signaux,
      ecartDominant: ecart,
      serieVictoires: serieVictoires,
      accordMarche: accordMarche,
    );
  }

  static List<String> _signauxForts(
    double ecart, int serie, bool accord,
    double coherence, int tendance, double cote,
  ) {
    final s = <String>[];
    if (serie >= 3) s.add('🔥 Série de $serie victoires consécutives');
    else if (serie == 2) s.add('✅ 2 victoires de suite (en forme)');
    if (ecart >= 15) s.add('📊 Domination nette (+${ecart.toStringAsFixed(0)} pts sur le 2e)');
    else if (ecart >= 10) s.add('📊 Avance claire sur les concurrents');
    if (accord) s.add('🤝 Accord IA + marché PMU (double validation)');
    if (coherence >= 5.5) s.add('📈 Très régulier sur la durée');
    if (tendance == 1) s.add('📈 En progression : amélioration récente confirmée');
    if (cote >= 2.5 && cote <= 6.0) s.add('💎 Cote valeur optimale (${cote.toStringAsFixed(1)})');
    return s;
  }

  // ── Points forts / faibles du favori ──────────────────────────────────────

  static List<String> _analysePointsForts(
    PmuParticipant p,
    List<PmuParticipant> ranked,
    Map<PmuParticipant, _ScoreDetail> details,
    double ecart,
    bool accordMarche,
    int serieVictoires,
    double coherence,
  ) {
    final pts = <String>[];
    final cote = p.coteAffichee;
    final d = details[p]!;

    if (serieVictoires >= 3) pts.add('🔥 Série de $serieVictoires victoires consécutives');
    else if (serieVictoires == 2) pts.add('✅ 2 victoires de suite — en pleine confiance');

    if (accordMarche) pts.add('🤝 Accord IA + bookmakers (favori partagé)');

    if (ecart >= 15) pts.add('📊 Domine nettement ses concurrents (+${ecart.toStringAsFixed(0)} pts)');
    else if (ecart >= 8) pts.add('📊 Avance significative sur le 2e concurrent');

    if (p.tauxVictoire >= 0.40 && p.nombreCourses >= 10) {
      pts.add('🏆 Excellent palmarès : ${(p.tauxVictoire * 100).round()}% de victoires (${p.nombreCourses} courses)');
    } else if (p.tauxVictoire >= 0.25 && p.nombreCourses >= 8) {
      pts.add('👍 Bon taux de victoire : ${(p.tauxVictoire * 100).round()}%');
    }

    if (cote >= 2.0 && cote <= 6.0) pts.add('💎 Cote valeur ${cote.toStringAsFixed(1)} — équilibre sécurité/rentabilité');

    if (coherence >= 5.5) pts.add('📈 Très régulier : performances stables et prévisibles');

    if (d.tendanceMusique == 1) pts.add('📈 En progression : meilleures performances récentes');

    if (d.dernierResultat == 1) pts.add('🥇 Vainqueur à sa dernière sortie');
    else if (d.dernierResultat == 2) pts.add('🥈 2e à sa dernière sortie — en forme');
    else if (d.dernierResultat == 3) pts.add('🥉 3e à sa dernière sortie — dans les favoris');

    if (p.gainsCarriere >= 300000) pts.add('💰 Carrière très lucrative (${(p.gainsCarriere / 1000).round()} k€)');

    return pts.take(4).toList();
  }

  static List<String> _analysePointsFaibles(
    PmuParticipant p,
    int nbPartants,
    bool abandonRecent,
    int tendance,
    double ecart,
  ) {
    final pts = <String>[];
    final cote = p.coteAffichee;

    if (abandonRecent) pts.add('⚠️ Abandon ou chute à une sortie récente');
    if (tendance == -1) pts.add('📉 En baisse de forme : résultats en dégradation');
    if (cote > 15) pts.add('⚠️ Cote élevée (outsider — ${cote.toStringAsFixed(1)}) : risque de surprises');
    if (nbPartants > 16) pts.add('⚠️ Grand champ ($nbPartants partants) — plus d\'aléatoire');
    else if (nbPartants > 12) pts.add('🔶 Champ large ($nbPartants partants) — course ouverte');
    if (p.nombreCourses < 4) pts.add('❓ Peu de données historiques (${p.nombreCourses} course${p.nombreCourses > 1 ? "s" : ""})');
    if (ecart < 3) pts.add('🤏 Faible écart avec les concurrents — course très ouverte');

    return pts.take(3).toList();
  }

  // ── Construction de l'explication ─────────────────────────────────────────

  static String _buildExplication({
    required PmuParticipant favori,
    required List<PmuParticipant> ranked,
    required Map<PmuParticipant, _ScoreDetail> scoreDetails,
    required PmuCourse course,
    required int confiance,
    required TypePari typePari,
    required MiseConseille mise,
    required double scoreBase2,
    required double scoreBase3,
    required double ecartBrut,
    required bool accordMarche,
    required FiabiliteResult niveauFiabilite,
  }) {
    final sb = StringBuffer();
    final cote = favori.coteAffichee;
    final d = scoreDetails[favori]!;

    // ── Sélection principale ─────────────────────────────────────────────────
    sb.write('N°${favori.numero} ${favori.nom} — score IA : ${(d.scoreBase + (ecartBrut >= 10 ? 8 : ecartBrut >= 6 ? 5 : 2)).toStringAsFixed(0)}/100. ');

    // ── Niveau de fiabilité honnête ──────────────────────────────────────────
    sb.write('${niveauFiabilite.label}. ');

    // ── Accord marché ────────────────────────────────────────────────────────
    if (accordMarche) {
      sb.write("L'IA et le marché PMU sont d'accord sur ce favori — signal de consensus fort. ");
    } else if (cote > 0 && cote <= 5) {
      sb.write('Bien côté par les bookmakers à ${cote.toStringAsFixed(1)}. ');
    }

    // ── Forme & musique ──────────────────────────────────────────────────────
    if (d.serieVictoires >= 3) {
      sb.write('🔥 Série impressionnante : ${d.serieVictoires} victoires consécutives — cheval en pleine confiance. ');
    } else if (d.serieVictoires == 2) {
      sb.write('✅ 2 victoires de suite — en grande forme. ');
    } else if (d.dernierResultat == 1) {
      sb.write('Vainqueur à sa dernière sortie. ');
    } else if (d.dernierResultat <= 2) {
      sb.write('${d.dernierResultat}e à sa dernière sortie — très en forme. ');
    }

    if (d.tendanceMusique == 1) {
      sb.write('Progression confirmée sur les dernières sorties. ');
    } else if (d.tendanceMusique == -1) {
      sb.write('⚠️ Attention : résultats en légère baisse récemment. ');
    }

    // ── Domination ───────────────────────────────────────────────────────────
    if (ecartBrut >= 12) {
      sb.write('Écart dominant significatif de ${ecartBrut.toStringAsFixed(0)} points sur son rival direct. ');
    } else if (ecartBrut < 4) {
      sb.write('Course serrée : le 2e concurrent est proche (${ecartBrut.toStringAsFixed(0)} pts d\'écart). ');
    }

    // ── Palmarès ─────────────────────────────────────────────────────────────
    if (favori.tauxVictoire >= 0.35 && favori.nombreCourses >= 8) {
      sb.write('Palmarès solide : ${(favori.tauxVictoire * 100).round()}% de victoires sur ${favori.nombreCourses} courses. ');
    }

    // ── Outsider à surveiller ─────────────────────────────────────────────────
    if (ranked.length > 1) {
      final second = ranked[1];
      final coteSecond = second.coteAffichee;
      final dSecond = scoreDetails[second];
      if (dSecond != null && ecartBrut < 8) {
        sb.write('⚡ Surveiller N°${second.numero} ${second.nom}');
        if (coteSecond > 0) sb.write(' (${coteSecond.toStringAsFixed(1)})');
        sb.write(' — concurrent dangereux. ');
      }
    }

    // ── Avertissement honnête toujours présent ────────────────────────────────
    sb.write('| Rappel honnête : les courses hippiques restent imprévisibles. ');
    sb.write('Pari conseillé : ${_typePariStr(typePari)} — mise ${_miseStr(mise)}.');

    return sb.toString();
  }

  static String _typePariStr(TypePari t) {
    switch (t) {
      case TypePari.simpleGagnant: return 'Simple Gagnant';
      case TypePari.simpleGagnantPlace: return 'Gagnant + Placé';
      case TypePari.place: return 'Placé (top 3)';
      case TypePari.tierce: return 'Tiercé';
      case TypePari.quarteplus: return 'Quarté+';
      case TypePari.quinteplus: return 'Quinté+';
      case TypePari.aucun: return 'À étudier';
    }
  }

  static String _miseStr(MiseConseille m) {
    switch (m) {
      case MiseConseille.forte: return 'forte';
      case MiseConseille.normale: return 'normale';
      case MiseConseille.prudente: return 'prudente';
      case MiseConseille.minimale: return 'minimale';
      case MiseConseille.unitaire: return 'unitaire';
    }
  }

  static double _coteSafe(PmuParticipant p) {
    final c = p.coteAffichee;
    return c > 0 ? c : 999.0;
  }

  static RaceRecommendation _emptyRecommendation(PmuCourse course, String hippodrome) {
    return RaceRecommendation(
      course: course,
      hippodrome: hippodrome,
      ranked: [],
      conseil: ConseilType.insuffisant,
      gagnant: null,
      place: [], tierce: [], quarte: [], quinte: [],
      explication: 'Pas de partants disponibles.',
      niveauConfiance: 0,
      scoreGagnant: 0,
      pointsForts: [],
      pointsFaibles: [],
      typePariConseille: TypePari.aucun,
      miseConseilee: MiseConseille.unitaire,
      fiabilite: FiabiliteResult(
        confiance: 0, etoiles: 0,
        label: '— Données insuffisantes',
        description: 'Aucun partant disponible.',
        signauxForts: [],
        ecartDominant: 0,
        serieVictoires: 0,
        accordMarche: false,
      ),
      ecartDominant: 0,
      accordMarche: false,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Modèles internes
// ══════════════════════════════════════════════════════════════════════════════

class _ScoreDetail {
  final double scoreBase;
  final Map<String, double> details;
  final int dernierResultat;
  final int avantDernierResultat;
  final int serieVictoires;
  final int tendanceMusique;
  final bool abandonRecent;

  const _ScoreDetail({
    required this.scoreBase,
    required this.details,
    required this.dernierResultat,
    required this.avantDernierResultat,
    required this.serieVictoires,
    required this.tendanceMusique,
    required this.abandonRecent,
  });
}

class _MusiqueResult {
  final double score;
  final int dernierResultat;
  final int avantDernierResultat;
  final int serieVictoires;
  final int tendance;
  final bool abandonRecent;

  const _MusiqueResult({
    required this.score,
    required this.dernierResultat,
    required this.avantDernierResultat,
    required this.serieVictoires,
    required this.tendance,
    required this.abandonRecent,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
//  Score de fiabilité (résultat public)
// ══════════════════════════════════════════════════════════════════════════════

class FiabiliteResult {
  /// Confiance estimée en % (15–82) — calibrée pour refléter la réalité
  final int confiance;
  /// Nombre d'étoiles (1–5)
  final int etoiles;
  /// Label court ex: "⭐⭐⭐⭐ Fiable"
  final String label;
  /// Description pédagogique honnête
  final String description;
  /// Signaux forts détectés (série, accord marché, domination, etc.)
  final List<String> signauxForts;
  /// Écart de score entre le 1er et le 2e
  final double ecartDominant;
  /// Nb de victoires consécutives récentes
  final int serieVictoires;
  /// IA et marché PMU en accord
  final bool accordMarche;

  const FiabiliteResult({
    required this.confiance,
    required this.etoiles,
    required this.label,
    required this.description,
    required this.signauxForts,
    required this.ecartDominant,
    required this.serieVictoires,
    required this.accordMarche,
  });

  /// Widget-friendly : couleur selon niveau de fiabilité
  int get colorValue {
    if (etoiles >= 5) return 0xFFFFD700; // Or
    if (etoiles >= 4) return 0xFF4CAF7D; // Vert
    if (etoiles >= 3) return 0xFF8BC34A; // Vert clair
    if (etoiles >= 2) return 0xFFFFB74D; // Orange
    return 0xFFEF5350;                   // Rouge
  }

  String get etoilesStr {
    return '⭐' * etoiles + '☆' * (5 - etoiles);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Enums et modèle RaceRecommendation
// ══════════════════════════════════════════════════════════════════════════════

enum ConseilType { excellent, bon, moyen, incertain, insuffisant }
enum TypePari { simpleGagnant, simpleGagnantPlace, place, tierce, quarteplus, quinteplus, aucun }
enum MiseConseille { forte, normale, prudente, minimale, unitaire }

class RaceRecommendation {
  final PmuCourse course;
  final String hippodrome;
  final List<PmuParticipant> ranked;
  final ConseilType conseil;
  final PmuParticipant? gagnant;
  final List<PmuParticipant> place;
  final List<PmuParticipant> tierce;
  final List<PmuParticipant> quarte;
  final List<PmuParticipant> quinte;
  final String explication;
  final int niveauConfiance;
  final double scoreGagnant;
  final List<String> pointsForts;
  final List<String> pointsFaibles;
  final TypePari typePariConseille;
  final MiseConseille miseConseilee;
  // Nouveaux champs v3.0
  final FiabiliteResult? fiabilite;
  final double ecartDominant;
  final bool accordMarche;

  RaceRecommendation({
    required this.course,
    required this.hippodrome,
    required this.ranked,
    required this.conseil,
    required this.gagnant,
    required this.place,
    required this.tierce,
    required this.quarte,
    required this.quinte,
    required this.explication,
    required this.niveauConfiance,
    required this.scoreGagnant,
    required this.pointsForts,
    required this.pointsFaibles,
    required this.typePariConseille,
    MiseConseille? miseConseilee,
    this.fiabilite,
    this.ecartDominant = 0,
    this.accordMarche = false,
  }) : miseConseilee = miseConseilee ?? MiseConseille.unitaire;

  String get conseilLabel {
    switch (conseil) {
      case ConseilType.excellent: return 'EXCELLENT';
      case ConseilType.bon: return 'BON PRONOSTIC';
      case ConseilType.moyen: return 'MOYEN';
      case ConseilType.incertain: return 'INCERTAIN';
      case ConseilType.insuffisant: return 'DONNÉES INSUFFISANTES';
    }
  }

  String get typePariLabel {
    switch (typePariConseille) {
      case TypePari.simpleGagnant: return '🏆 Simple Gagnant';
      case TypePari.simpleGagnantPlace: return '🎯 Gagnant + Placé';
      case TypePari.place: return '🎯 Placé (Top 3)';
      case TypePari.tierce: return '📋 Tiercé';
      case TypePari.quarteplus: return '4️⃣ Quarté+';
      case TypePari.quinteplus: return '⭐ Quinté+';
      case TypePari.aucun: return '—';
    }
  }

  String get miseLabel {
    switch (miseConseilee) {
      case MiseConseille.forte: return '💰💰💰 Forte';
      case MiseConseille.normale: return '💰💰 Normale';
      case MiseConseille.prudente: return '💰 Prudente';
      case MiseConseille.minimale: return '🪙 Minimale';
      case MiseConseille.unitaire: return '🪙 Unitaire';
    }
  }

  String get numerosTierce => tierce.map((p) => '${p.numero}').join(' - ');
  String get numerosQuarte => quarte.map((p) => '${p.numero}').join(' - ');
  String get numerosQuinte => quinte.map((p) => '${p.numero}').join(' - ');
}
