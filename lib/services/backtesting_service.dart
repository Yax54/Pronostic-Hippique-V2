// ═══════════════════════════════════════════════════════════════════
//  BACKTESTING SERVICE — Pronostic Hippique v1.0 (Lot 3)
//
//  Simule ce qui se serait passé si vous aviez suivi l'IA
//  sur les N derniers jours avec une mise fixe.
//
//  Usage :
//    final result = await BacktestingService.instance.lancer(
//      mise: 10.0,
//      typePari: 'Simple Gagnant',
//      nbJours: 30,
//    );
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'ia_memory_service.dart';

// ─── Résultat d'une course simulée ───────────────────────────────────────────
class BacktestCourse {
  final String courseKey;
  final String nomCourse;
  final String hippodrome;
  final String discipline;
  final DateTime date;
  final double confianceIA;
  final String typePariConseille;

  // Résultat réel
  final List<int> arriveeReelle;
  final int? rangFavoriIA;   // rang du favori IA dans l'arrivée réelle (1 = gagné)

  // Calcul financier
  final double mise;
  final double gainNet;
  final bool gagne;

  const BacktestCourse({
    required this.courseKey,
    required this.nomCourse,
    required this.hippodrome,
    required this.discipline,
    required this.date,
    required this.confianceIA,
    required this.typePariConseille,
    required this.arriveeReelle,
    this.rangFavoriIA,
    required this.mise,
    required this.gainNet,
    required this.gagne,
  });
}

// ─── Résultat complet d'une simulation ───────────────────────────────────────
class BacktestResult {
  final List<BacktestCourse> courses;
  final double miseTotal;
  final double gainsTotal;
  final double gainNet;
  final int nbGagnes;
  final int nbPerdus;
  final int nbTotal;
  final double tauxReussite;     // %
  final double roi;              // Return on Investment %
  final double gainNetCumule;    // gain cumulé sur toute la période
  // Séries
  final int meilleureSerieGagnante;
  final int pireSeriesPerdantes;
  // Courbe gains cumulés (index = numéro de course, valeur = gain cumulé)
  final List<double> courbeGains;
  // Répartition par discipline
  final Map<String, StatDiscipline> parDiscipline;
  // Répartition par hippodrome (top 5)
  final Map<String, StatDiscipline> parHippodrome;
  // ★ v9.93 : Perte maximale consécutive (maxDrawdown)
  final double maxDrawdown;

  const BacktestResult({
    required this.courses,
    required this.miseTotal,
    required this.gainsTotal,
    required this.gainNet,
    required this.nbGagnes,
    required this.nbPerdus,
    required this.nbTotal,
    required this.tauxReussite,
    required this.roi,
    required this.gainNetCumule,
    required this.meilleureSerieGagnante,
    required this.pireSeriesPerdantes,
    required this.courbeGains,
    required this.parDiscipline,
    required this.parHippodrome,
    this.maxDrawdown = 0.0, // ★ v9.93
  });

  bool get estRentable => gainNet > 0;

  String get resumeTexte {
    final roiStr = roi >= 0 ? '+${roi.toStringAsFixed(0)}%' : '${roi.toStringAsFixed(0)}%';
    return '$nbGagnes gagnés / $nbTotal paris — ROI : $roiStr — '
        'Gain net : ${gainNet >= 0 ? "+" : ""}${gainNet.toStringAsFixed(0)} €';
  }
}

// ★ v9.82 : classe rendue publique (était _StatDiscipline) pour accès depuis ia_performance_screen
class StatDiscipline {
  int nbTotal = 0;
  int nbGagnes = 0;
  double gainNet = 0.0;
  double get taux => nbTotal > 0 ? nbGagnes / nbTotal * 100 : 0.0;
}

// ─── Service de backtesting ───────────────────────────────────────────────────
class BacktestingService {
  static final BacktestingService _instance = BacktestingService._();
  static BacktestingService get instance => _instance;
  BacktestingService._();

  /// Lance une simulation sur l'historique IaMemoryService.
  ///
  /// [mise]        : mise fixe par course (ex: 10.0 €)
  /// [typePari]    : 'Simple Gagnant', 'Simple Placé', 'Conseil IA' (utilise le type conseillé)
  /// [nbJours]     : nombre de jours à simuler (7, 14, 30, 60, 90)
  /// [confianceMin]: seuil minimum de confiance pour parier (0-100)
  /// [discipline]  : ★ v10.20 — filtre sur une discipline (null = toutes)
  /// [hippodrome]  : ★ v10.20 — filtre sur un hippodrome (null = tous)
  Future<BacktestResult> lancer({
    required double mise,
    String typePari = 'Conseil IA',
    int nbJours = 30,
    double confianceMin = 0.0,
    String? discipline,    // ★ v10.20
    String? hippodrome,    // ★ v10.20
  }) async {
    final pronostics = IaMemoryService.instance.pronostics;
    final limiteDate = DateTime.now().subtract(Duration(days: nbJours));

    // Filtrer les pronostics avec résultats réels, dans la période
    // ★ v10.20 : + filtre discipline / hippodrome optionnel
    final avecResultats = pronostics.where((p) =>
      p.resultatsReels &&
      p.arriveeReelle != null &&
      p.arriveeReelle!.isNotEmpty &&
      p.datePronostic.isAfter(limiteDate) &&
      (discipline == null || p.discipline == discipline) &&
      (hippodrome == null || p.hippodrome == hippodrome)
    ).toList()
    ..sort((a, b) => a.datePronostic.compareTo(b.datePronostic));

    if (avecResultats.isEmpty) {
      return BacktestResult(
        courses: [],
        miseTotal: 0, gainsTotal: 0, gainNet: 0,
        nbGagnes: 0, nbPerdus: 0, nbTotal: 0,
        tauxReussite: 0, roi: 0, gainNetCumule: 0,
        meilleureSerieGagnante: 0, pireSeriesPerdantes: 0,
        courbeGains: [],
        parDiscipline: {}, parHippodrome: {},
      );
    }

    final List<BacktestCourse> courses = [];
    double gainCumule = 0.0;
    final List<double> courbeGains = [];
    final Map<String, StatDiscipline> parDisc  = {};
    final Map<String, StatDiscipline> parHippo = {};

    int serieGagnante = 0; int maxSerieGagnante = 0;
    int seriePerdante = 0; int maxSeriePerdante = 0;
    int nbGagnes = 0;

    for (final p in avecResultats) {
      // Filtrer par confiance minimum
      final confiance = p.confiancePredite ?? 50.0;
      if (confiance < confianceMin) continue;

      final arrivee = p.arriveeReelle!;

      // Trouver le favori IA (le cheval avec le meilleur score dans scoresIA)
      String? numFavori;
      double maxScore = -1;
      p.scoresIA.forEach((num, score) {
        if (score > maxScore) {
          maxScore  = score;
          numFavori = num;
        }
      });
      if (numFavori == null) continue;

      final numFavoriInt = int.tryParse(numFavori!);
      if (numFavoriInt == null) continue;

      // Position du favori IA dans l'arrivée réelle
      final rang = arrivee.indexOf(numFavoriInt) + 1; // 0 si absent
      final rangReel = rang > 0 ? rang : null;

      // Déterminer le type de pari effectif
      final typeEffectif = typePari == 'Conseil IA'
          ? (p.typePariConseille ?? 'Simple Gagnant')
          : typePari;

      // Calculer si gagné et le gain
      // ★ v9.84 : transmettre la cote PMU réelle pour un calcul de gain réaliste
      final (gagne, gainNetCourse) = _calculerResultat(
        typeEffectif:  typeEffectif,
        rangFavori:    rangReel,
        scoresIA:      p.scoresIA,
        arrivee:       arrivee,
        mise:          mise,
        coteFavoriPmu: p.coteFavoriPmu,   // null → fallback cote fixe
      );

      gainCumule += gainNetCourse;
      courbeGains.add(gainCumule);

      if (gagne) {
        nbGagnes++;
        serieGagnante++;
        seriePerdante = 0;
        if (serieGagnante > maxSerieGagnante) maxSerieGagnante = serieGagnante;
      } else {
        seriePerdante++;
        serieGagnante = 0;
        if (seriePerdante > maxSeriePerdante) maxSeriePerdante = seriePerdante;
      }

      // Stats par discipline
      final disc = p.discipline.isNotEmpty ? p.discipline : 'Inconnu';
      parDisc.putIfAbsent(disc, () => StatDiscipline());
      parDisc[disc]!.nbTotal++;
      if (gagne) parDisc[disc]!.nbGagnes++;
      parDisc[disc]!.gainNet += gainNetCourse;

      // Stats par hippodrome
      final hippo = p.hippodrome.isNotEmpty ? p.hippodrome : 'Inconnu';
      parHippo.putIfAbsent(hippo, () => StatDiscipline());
      parHippo[hippo]!.nbTotal++;
      if (gagne) parHippo[hippo]!.nbGagnes++;
      parHippo[hippo]!.gainNet += gainNetCourse;

      courses.add(BacktestCourse(
        courseKey:          p.courseKey,
        nomCourse:          p.nomCourse,
        hippodrome:         p.hippodrome,
        discipline:         p.discipline,
        date:               p.datePronostic,
        confianceIA:        confiance,
        typePariConseille:  typeEffectif,
        arriveeReelle:      arrivee,
        rangFavoriIA:       rangReel,
        mise:               mise,
        gainNet:            gainNetCourse,
        gagne:              gagne,
      ));
    }

    // ★ v9.93 : Calculer le maxDrawdown (perte maximale consécutive sur la courbe des gains)
    double maxDrawdown = 0.0;
    if (courbeGains.isNotEmpty) {
      double peak = courbeGains.first;
      for (final g in courbeGains) {
        if (g > peak) peak = g;
        final drawdown = peak - g;
        if (drawdown > maxDrawdown) maxDrawdown = drawdown;
      }
    }

    final nbTotal    = courses.length;
    final nbPerdus   = nbTotal - nbGagnes;
    final miseTotal  = mise * nbTotal;
    final gainsTotal = courses.where((c) => c.gagne).fold(0.0, (s, c) => s + c.gainNet + mise);
    final gainNet    = gainCumule;
    final taux       = nbTotal > 0 ? nbGagnes / nbTotal * 100 : 0.0;
    final roi        = miseTotal > 0 ? (gainNet / miseTotal) * 100 : 0.0;

    // Top 5 hippodromes seulement
    final topHippos = Map.fromEntries(
      (parHippo.entries.toList()
        ..sort((a, b) => b.value.nbTotal.compareTo(a.value.nbTotal)))
        .take(5),
    );

    debugPrint('[Backtesting] ✅ $nbTotal courses simulées sur $nbJours jours '
        '— Gain net : ${gainNet.toStringAsFixed(0)} € — ROI : ${roi.toStringAsFixed(0)}%');

    return BacktestResult(
      courses:                courses,
      miseTotal:              miseTotal,
      gainsTotal:             gainsTotal,
      gainNet:                gainNet,
      nbGagnes:               nbGagnes,
      nbPerdus:               nbPerdus,
      nbTotal:                nbTotal,
      tauxReussite:           taux,
      roi:                    roi,
      gainNetCumule:          gainCumule,
      meilleureSerieGagnante: maxSerieGagnante,
      pireSeriesPerdantes:    maxSeriePerdante,
      courbeGains:            courbeGains,
      parDiscipline:          parDisc,
      parHippodrome:          topHippos,
      maxDrawdown:            maxDrawdown, // ★ v9.93
    );
  }

  /// Calcule si le pari est gagné et le gain net selon le type de pari.
  ///
  /// ★ v9.84 : [coteFavoriPmu] est la cote PMU réelle du favori IA capturée
  /// au moment du pronostic. Si null (pronostics antérieurs), on utilise les
  /// cotes fixes historiques comme fallback.
  ///
  /// Cotes placé PMU : environ cote_gagnant / 4 (plancher 1.1)
  (bool, double) _calculerResultat({
    required String typeEffectif,
    required int? rangFavori,
    required Map<String, double> scoresIA,
    required List<int> arrivee,
    required double mise,
    double? coteFavoriPmu,        // ★ v9.84 : cote réelle ou null
  }) {
    if (rangFavori == null) return (false, -mise);

    // ★ v9.84 : Cote gagnant réelle avec fallback sur cote moyenne PMU (4.5)
    final coteGagnant = (coteFavoriPmu != null && coteFavoriPmu > 1.0)
        ? coteFavoriPmu
        : 4.5;
    // Cote placé PMU ≈ cote_gagnant / 4, plancher 1.10
    final cotePlaceEstimee = (coteGagnant / 4.0).clamp(1.10, 20.0);

    switch (typeEffectif) {
      case 'Simple Gagnant':
        if (rangFavori == 1) {
          // ★ v9.84 : cote réelle si disponible, sinon 4.5 (cote moyenne PMU)
          return (true, mise * coteGagnant - mise);
        }
        return (false, -mise);

      case 'Simple Placé':
        if (rangFavori <= 3) {
          // ★ v9.84 : cote placé réelle estimée ou 1.8
          return (true, mise * cotePlaceEstimee - mise);
        }
        return (false, -mise);

      case 'Gagnant+Placé':
        // ★ v9.84 : mise répartie 50/50 sur Gagnant + Placé
        if (rangFavori == 1) return (true, mise * coteGagnant + mise * cotePlaceEstimee - mise * 2);
        if (rangFavori <= 3) return (false, mise * cotePlaceEstimee - mise * 2); // récupère le placé
        return (false, -mise * 2);

      case 'Couplé Gagnant':
        // Les 2 meilleurs scores IA couvrent les 2 premiers de l'arrivée
        // ★ v9.82 fix : top2Arrivee.every(...) au lieu de top2IA.toSet().containsAll(...)
        final top2IA = _getTopNIA(scoresIA, 2);
        final top2Arrivee = arrivee.take(2).toSet();
        if (top2IA.length >= 2 && top2Arrivee.every((n) => top2IA.contains(n))) {
          return (true, mise * 8.0 - mise);
        }
        return (false, -mise);

      case 'Couplé Placé':
        final top2IA = _getTopNIA(scoresIA, 2);
        final top3Arrivee = arrivee.take(3).toSet();
        if (top2IA.length >= 2 && top2IA.every((n) => top3Arrivee.contains(n))) {
          return (true, mise * 4.0 - mise);
        }
        return (false, -mise);

      case 'Tiercé':
        // ★ v9.82 fix : listEquals() au lieu de toString() pour comparer l'ordre
        final top3IA = _getTopNIA(scoresIA, 3);
        final top3Arrivee = arrivee.take(3).toSet();
        if (top3IA.length >= 3) {
          final nbBons = top3IA.where((n) => top3Arrivee.contains(n)).length;
          if (nbBons == 3 && listEquals(top3IA, arrivee.take(3).toList())) {
            return (true, mise * 50.0 - mise); // tiercé ordre exact
          }
          if (nbBons == 3) return (true, mise * 20.0 - mise); // désordre
        }
        return (false, -mise);

      case 'Quarté+':
        // Les 4 meilleurs scores IA dans le top 4 (désordre)
        final top4IA = _getTopNIA(scoresIA, 4);
        final top4Arrivee = arrivee.take(4).toSet();
        if (top4IA.length >= 4) {
          final nbBons = top4IA.where((n) => top4Arrivee.contains(n)).length;
          if (nbBons == 4) return (true, mise * 40.0 - mise); // 4/4 désordre
          if (nbBons == 3) return (true, mise * 5.0 - mise);  // bonus 3/4
        }
        return (false, -mise);

      case 'Quinté+':
        final top5IA = _getTopNIA(scoresIA, 5);
        final top5Arrivee = arrivee.take(5).toSet();
        if (top5IA.length >= 5) {
          final nbBons = top5IA.where((n) => top5Arrivee.contains(n)).length;
          if (nbBons == 5) return (true, mise * 100.0 - mise);
          if (nbBons == 4) return (true, mise * 8.0 - mise); // bonus 4/5
        }
        return (false, -mise);

      default: // Conseil IA → Simple Gagnant par défaut
        if (rangFavori == 1) return (true, mise * coteGagnant - mise);
        return (false, -mise);
    }
  }

  /// Retourne les N numéros avec les meilleurs scores IA
  List<int> _getTopNIA(Map<String, double> scoresIA, int n) {
    final sorted = scoresIA.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(n)
        .map((e) => int.tryParse(e.key))
        .whereType<int>()
        .toList();
  }

  /// Résumé rapide : combien de courses avec résultats disponibles
  int get nbCoursesDisponibles =>
      IaMemoryService.instance.pronostics
          .where((p) => p.resultatsReels && p.arriveeReelle != null)
          .length;

  /// Plage de dates disponible
  ({DateTime? debut, DateTime? fin}) get plageDisponible {
    final avecResultats = IaMemoryService.instance.pronostics
        .where((p) => p.resultatsReels)
        .map((p) => p.datePronostic)
        .toList();
    if (avecResultats.isEmpty) return (debut: null, fin: null);
    avecResultats.sort();
    return (debut: avecResultats.first, fin: avecResultats.last);
  }
}
