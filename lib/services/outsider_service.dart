// ═══════════════════════════════════════════════════════════════════════════
//  OUTSIDER SERVICE — v9.92
//
//  Détecte les "outsiders systématiques" : chevaux que le marché PMU
//  sous-estime régulièrement malgré un bon palmarès objectif.
//
//  Critères de détection :
//    ELO > 1600 (bon niveau prouvé) +
//    Cote moyenne > 8 (systématiquement sous-estimé par le marché) +
//    Taux Top3 > 45% sur les dernières courses
//
//  Ces chevaux sont statistiquement les plus rentables à long terme
//  car leur cote élevée compense largement leur probabilité réelle.
// ═══════════════════════════════════════════════════════════════════════════

import '../models/zt_models.dart';
import 'elo_service.dart';

class OutsiderScore {
  final String  nomCheval;
  final String  discipline;
  final double  eloRating;
  final double  coteMoyenne;
  final double  tauxTop3;
  final int     nbCourses;
  final double  scoreOpportunite; // 0-100 — plus élevé = plus intéressant

  const OutsiderScore({
    required this.nomCheval,
    required this.discipline,
    required this.eloRating,
    required this.coteMoyenne,
    required this.tauxTop3,
    required this.nbCourses,
    required this.scoreOpportunite,
  });

  String get label {
    if (scoreOpportunite >= 80) return '💎 Outsider d\'or';
    if (scoreOpportunite >= 65) return '⭐ Outsider fiable';
    return '🔍 À surveiller';
  }
}

class OutsiderService {
  static final OutsiderService _instance = OutsiderService._();
  static OutsiderService get instance => _instance;
  OutsiderService._();

  static const double _seuilElo     = 1600.0;
  static const double _seuilCote    = 8.0;
  static const double _seuilTop3    = 0.45; // 45%
  static const int    _nbCoursesMin = 5;

  /// Détecte les outsiders systématiques parmi les partants d'une course.
  /// Retourne la liste des partants correspondant aux critères, triée par score.
  List<OutsiderScore> detecterDansCourse(ZtCourse course) {
    final results = <OutsiderScore>[];

    for (final p in course.partants) {
      final elo  = p.eloRating > 0 ? p.eloRating
          : EloService.instance.getRating(p.nom, discipline: course.type);
      if (elo < _seuilElo) continue;

      final cote = p.coteDecimale;
      if (cote <= 0 || cote < _seuilCote) continue;

      // Calculer le taux Top3 depuis la musique
      final top3 = _tauxTop3DepuisMusique(p.musique);
      if (top3.taux < _seuilTop3) continue;
      if (top3.nb < _nbCoursesMin) continue;

      // Score d'opportunité : pondère ELO, cote et taux Top3
      final scoreElo   = ((elo - 1600) / 400).clamp(0.0, 1.0) * 40;  // 0-40 pts
      final scoreCote  = ((cote - 8.0) / 12.0).clamp(0.0, 1.0) * 30; // 0-30 pts
      final scoreTop3  = ((top3.taux - 0.45) / 0.35).clamp(0.0, 1.0) * 30; // 0-30 pts
      final total      = scoreElo + scoreCote + scoreTop3;

      results.add(OutsiderScore(
        nomCheval:        p.nom,
        discipline:       course.type,
        eloRating:        elo,
        coteMoyenne:      cote,
        tauxTop3:         top3.taux,
        nbCourses:        top3.nb,
        scoreOpportunite: total.clamp(0.0, 100.0),
      ));
    }

    results.sort((a, b) => b.scoreOpportunite.compareTo(a.scoreOpportunite));
    return results;
  }

  /// Calcule le taux top3 depuis la musique PMU
  ({double taux, int nb}) _tauxTop3DepuisMusique(String musique) {
    if (musique.isEmpty) return (taux: 0.0, nb: 0);
    final tokenRegex = RegExp(
      r'(\()' r'|(\))' r'|([Aa][amhp])' r'|([Dd][abmhp])' r'|([Bb][amhp])' r'|(0[amhp])' r'|(1\d[amhp]|[2-9]\d[amhp]|[1-9][amhp])',
      caseSensitive: true,
    );
    bool inParen = false;
    int nb = 0, top3 = 0;
    for (final m in tokenRegex.allMatches(musique)) {
      if (m.group(1) != null) { inParen = true;  continue; }
      if (m.group(2) != null) { inParen = false; continue; }
      if (inParen) continue;
      if (m.group(6) != null) continue; // non-partant ignoré
      if (m.group(3) != null || m.group(4) != null || m.group(5) != null) {
        nb++; // abandon/disq comptabilisé comme course
      } else if (m.group(7) != null) {
        final raw = m.group(7)!;
        final pos = int.tryParse(raw.substring(0, raw.length - 1)) ?? 99;
        nb++;
        if (pos <= 3) top3++;
      }
    }
    if (nb == 0) return (taux: 0.0, nb: 0);
    return (taux: top3 / nb, nb: nb);
  }
}
