import 'dart:math' as math;

import '../models/simulation_models.dart';
import '../services/ia_memory_service.dart';
import '../services/ia_memory_models.dart';
import '../widgets/ia/ia_tab_audit.dart'; // extension ScoresCriteresMap.toMap()

// ═══════════════════════════════════════════════════════════════════════════
//  SimulationService — Moteur du Laboratoire IA
//
//  RÈGLES ABSOLUES :
//   ✅ Lecture seule sur IaMemoryService
//   ❌ Aucune écriture dans IaMemoryService
//   ❌ Aucun apprentissage déclenché
//   ❌ Aucune modification des poids réels
//   ❌ Aucune sauvegarde de scores virtuels
//
//  ROI simulé :
//   1. coteFavoriPmu du pronostic si disponible (dividende officiel PMU)
//   2. sinon score cote brut converti approximativement
//   3. sinon exclu du calcul ROI
// ═══════════════════════════════════════════════════════════════════════════

class SimulationService {
  SimulationService._();
  static final SimulationService instance = SimulationService._();

  static const double _seuilSigma = 2.0; // σ min pour critère vivant

  // ── Critères vivants détectés sur l'historique ────────────────────────────
  /// Retourne les clés courtes ('f','g'...) des critères vivants (σ > seuil)
  List<String> critersVivants() {
    final pronostics = IaMemoryService.instance.pronostics;
    final Map<String, List<double>> vect = {
      for (final k in kCleCourtVersLong.keys) k: [],
    };
    for (final p in pronostics) {
      for (final sc in p.scoresCriteres.values) {
        final m = sc.toMap();
        for (final k in kCleCourtVersLong.keys) {
          final v = m[k];
          if (v != null) vect[k]!.add(v);
        }
      }
    }
    return kCleCourtVersLong.keys.where((k) {
      final vals = vect[k]!;
      return vals.length >= 10 && _sigma(vals) >= _seuilSigma;
    }).toList();
  }

  // ── Simuler ───────────────────────────────────────────────────────────────
  /// Lance une simulation complète et retourne le résultat.
  /// NE MODIFIE RIEN dans IaMemoryService.
  SimulationResultat simuler(SimulationParams params) {
    final svc        = IaMemoryService.instance;
    final poids      = svc.poids; // lecture seule
    final maintenant = DateTime.now();
    final il30j      = maintenant.subtract(const Duration(days: 30));
    final il7j       = maintenant.subtract(const Duration(days: 7));

    // 1. Filtrer pronostics avec résultats réels + discipline
    final tous = svc.pronostics
        .where((p) => p.resultatsReels &&
                      p.arriveeReelle != null &&
                      p.arriveeReelle!.isNotEmpty &&
                      _matchDisc(p.discipline, params.discipline))
        .toList();

    final p30j = tous.where((p) => p.datePronostic.isAfter(il30j)).toList();
    final p7j  = tous.where((p) => p.datePronostic.isAfter(il7j)).toList();

    // 2. Calculer les 6 blocs (avant/après × 3 périodes)
    final avant    = _calcBloc(tous,  poids, params, simu: false);
    final avt30j   = _calcBloc(p30j,  poids, params, simu: false);
    final avt7j    = _calcBloc(p7j,   poids, params, simu: false);
    final apres    = _calcBloc(tous,  poids, params, simu: true);
    final apr30j   = _calcBloc(p30j,  poids, params, simu: true);
    final apr7j    = _calcBloc(p7j,   poids, params, simu: true);

    return SimulationResultat(
      params:    params,
      avant:     avant,
      avant30j:  avt30j,
      avant7j:   avt7j,
      apres:     apres,
      apres30j:  apr30j,
      apres7j:   apr7j,
      calculeLe: maintenant,
    );
  }

  // ── Bloc de stats pour une liste de pronostics ────────────────────────────
  SimBloc _calcBloc(
    List<IaPronostic> pronostics,
    IaPoidsAdaptatifs poids,
    SimulationParams params, {
    required bool simu,
  }) {
    if (pronostics.isEmpty) return const SimBloc();

    int top1Total = 0, top3Total = 0, top5Total = 0;
    int nbRoi = 0;
    double retourTotal = 0.0;
    int outsiders = 0;
    double miseTotal = 0.0;

    for (final prono in pronostics) {
      final arrivee = prono.arriveeReelle!;
      final top3Real = arrivee.take(3).map((n) => n.toString()).toSet();
      final top5Real = arrivee.take(5).map((n) => n.toString()).toSet();
      final top1Real = arrivee.isNotEmpty ? arrivee.first.toString() : '';

      // Classement : réel (avant) ou simulé (après)
      final List<String> classement = simu
          ? _classerSimule(prono, poids, params)
          : _classerReel(prono);

      if (classement.isEmpty) continue;

      final favori = classement.first;

      // Top1 gagnant
      if (favori == top1Real) top1Total++;

      // Top3 : est-ce qu'au moins 1 des 3 premiers simulés est dans le Top3 réel ?
      final sim3 = classement.take(3).toSet();
      if (sim3.intersection(top3Real).isNotEmpty) top3Total++;

      // Top5
      final sim5 = classement.take(5).toSet();
      if (sim5.intersection(top5Real).isNotEmpty) top5Total++;

      // Outsiders : favori simulé a cote > 10 ET est dans Top3 réel
      final cote = _coteFavori(prono, favori);
      if (cote != null && cote > 10.0 && top3Real.contains(favori)) {
        outsiders++;
      }

      // ROI
      final dividende = _dividendePourNumero(prono, favori, simu: simu);
      if (dividende != null && dividende > 0) {
        miseTotal   += 1.0;
        nbRoi++;
        if (top1Real == favori) {
          // Pari gagnant : on reçoit le dividende pour 1€ misé
          retourTotal += dividende;
        }
        // Pari perdu : retourTotal += 0 (on a misé 1€ qu'on perd)
      }
    }

    final n = pronostics.length;
    final gainNet = retourTotal - miseTotal;
    final roi     = miseTotal > 0 ? (gainNet / miseTotal * 100) : 0.0;

    return SimBloc(
      nbCourses:    n,
      nbCoursesRoi: nbRoi,
      top1:  n > 0 ? top1Total / n * 100 : 0,
      top3:  n > 0 ? top3Total / n * 100 : 0,
      top5:  n > 0 ? top5Total / n * 100 : 0,
      roi:      roi,
      gainNet:  gainNet,
      outsiders: outsiders,
    );
  }

  // ── Classement réel (scoresIA enregistrés) ────────────────────────────────
  List<String> _classerReel(IaPronostic prono) {
    final entries = prono.scoresIA.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).toList();
  }

  // ── Classement simulé (recalcul avec multiplicateurs) ────────────────────
  List<String> _classerSimule(
    IaPronostic prono,
    IaPoidsAdaptatifs poids,
    SimulationParams params,
  ) {
    if (prono.scoresCriteres.isEmpty) return _classerReel(prono);

    // Poids effectifs pour la discipline de ce pronostic
    final poidsMap = poids.poidsEffectifsPourDiscipline(prono.discipline);

    final scores = <String, double>{};

    for (final entry in prono.scoresCriteres.entries) {
      final numero = entry.key;
      final sc     = entry.value;
      final scMap  = sc.toMap(); // clés courtes : 'f','g','r'...

      double scoreVirtuel = 0.0;
      double totalPoids   = 0.0;

      for (final cleCourtCritere in kCleCourtVersLong.keys) {
        final valScore = scMap[cleCourtCritere] ?? 50.0;
        final nomLong  = kCleCourtVersLong[cleCourtCritere]!;
        final poidsCritere = poidsMap[nomLong] ?? IaPoidsAdaptatifs.defauts[nomLong] ?? 0.0;
        final mult         = params.mult(cleCourtCritere);

        scoreVirtuel += valScore * poidsCritere * mult;
        totalPoids   += poidsCritere * mult;
      }

      // Normaliser 0-100
      scores[numero] = totalPoids > 0
          ? (scoreVirtuel / totalPoids).clamp(0.0, 100.0)
          : 50.0;
    }

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  // ── Dividende pour le calcul ROI ──────────────────────────────────────────
  /// ★ v10.31 : Utilise cotesPmuParNumero[favoriNumero] si disponible,
  /// permettant au ROI simulé de fonctionner même quand le favori simulé
  /// est différent du favori IA réel enregistré.
  ///
  /// Priorité :
  ///   1. cotesPmuParNumero[favoriNumero]   → dividende PMU officiel par cheval
  ///   2. coteFavoriPmu (si même favori)    → fallback ancien comportement
  ///   3. null → exclure du ROI (aucune donnée fiable)
  double? _dividendePourNumero(
    IaPronostic prono,
    String favoriNumero,
    {required bool simu}
  ) {
    // Source 1 (★ v10.31) : cotesPmuParNumero — disponible pour TOUT cheval
    // Rempli depuis E_SIMPLE_GAGNANT (rList complet) lors de l'analyse journée
    final coteMap = prono.cotesPmuParNumero;
    if (coteMap.isNotEmpty) {
      final cote = coteMap[favoriNumero];
      if (cote != null && cote > 1.0 && cote < 1000) return cote;
    }

    // Source 2 : coteFavoriPmu scalaire (fallback — favori IA uniquement)
    // Compatible avec les pronostics antérieurs à v10.31
    final favoriReel = prono.favoriIA;
    if (favoriReel == favoriNumero && prono.coteFavoriPmu != null) {
      final d = prono.coteFavoriPmu!;
      if (d > 0 && d < 1000) return d;
    }

    // Aucune donnée fiable → exclure du ROI
    return null;
  }

  /// Retourne la cote décimale du favori (pour détection outsider)
  /// ★ v10.31 : utilise cotesPmuParNumero si disponible
  double? _coteFavori(IaPronostic prono, String numero) {
    final coteMap = prono.cotesPmuParNumero;
    if (coteMap.isNotEmpty) {
      final cote = coteMap[numero];
      if (cote != null && cote > 1.0) return cote;
    }
    if (prono.favoriIA == numero) return prono.coteFavoriPmu;
    return null;
  }

  // ── Filtre discipline ─────────────────────────────────────────────────────
  static bool _matchDisc(String discProno, String discFiltre) {
    if (discFiltre == 'Toutes') return true;
    final t = discProno.toLowerCase();
    switch (discFiltre) {
      case 'Plat':
        return t == 'plat';
      case 'Trot':
        return t.contains('att') || t.contains('mont') || t.contains('trot');
      case 'Obstacle':
        return t.contains('haies') || t.contains('steeple') || t.contains('obstacle');
      default:
        return true;
    }
  }

  // ── Écart-type ────────────────────────────────────────────────────────────
  static double _sigma(List<double> v) {
    if (v.length < 2) return 0.0;
    final m    = v.reduce((a, b) => a + b) / v.length;
    final vari = v.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / v.length;
    return math.sqrt(vari);
  }

}
