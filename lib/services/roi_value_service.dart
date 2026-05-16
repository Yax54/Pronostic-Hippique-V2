// ══════════════════════════════════════════════════════════════════════════════
//  roi_value_service.dart — Service ROI / Value Analytics
//  ★ v10.46 — Module 100% LECTURE SEULE
//
//  ⚠️ AUCUNE ÉCRITURE dans IaMemoryService, poids, pronostics ou SharedPreferences
//  Source de données : IaMemoryService.instance.pronosticsAvecResultat
//  Validation : IaMemoryService.instance.estBonConseil() (wrapper public existant)
//
//  Champs IaPronostic utilisés (vérifiés) :
//    courseKey, nomCourse, hippodrome, discipline, datePronostic
//    typePariConseille, confiancePredite, resultatsReels
//    coteFavoriPmu, cotesPmuParNumero (Map<String,double>)
//    arriveeReelle, rangFavoriIaDansArrivee
//    topNIA (getter), scoresIA (Map<String,double>)
//    scoresCriteres (Map<String,ScoresCriteres>) → .divergence
// ══════════════════════════════════════════════════════════════════════════════

import '../models/roi_value_models.dart';
import 'ia_memory_service.dart';
import 'ia_memory_models.dart';

class RoiValueService {
  RoiValueService._();
  static final RoiValueService instance = RoiValueService._();

  // ════════════════════════════════════════════════════════════════════════════
  //  FILTRAGE — applique discipline / période / typePari
  // ════════════════════════════════════════════════════════════════════════════

  List<IaPronostic> _filtrer(RoiValueFilters f) {
    final all = IaMemoryService.instance.pronosticsAvecResultat;

    return all.where((p) {
      // ── Discipline ────────────────────────────────────────────────────────
      if (f.discipline != 'Toutes') {
        final disc = p.discipline.toLowerCase();
        final filtre = f.discipline.toLowerCase();
        // Mapping souple : 'trot' couvre 'trot attelé' et 'trot monté'
        if (filtre == 'trot') {
          if (!disc.contains('trot') && !disc.contains('att') && !disc.contains('mont')) {
            return false;
          }
        } else if (filtre == 'obstacle') {
          if (!disc.contains('haies') && !disc.contains('obstacle') &&
              !disc.contains('steeple') && !disc.contains('cross')) {
            return false;
          }
        } else {
          // 'Plat'
          if (!disc.contains(filtre)) return false;
        }
      }

      // ── Type de pari ──────────────────────────────────────────────────────
      if (f.typePari != 'Tous') {
        if ((p.typePariConseille ?? '') != f.typePari) return false;
      }

      // ── Période ───────────────────────────────────────────────────────────
      if (f.periode != 'complet') {
        final days = f.periode == '7j' ? 7 : 30;
        final limite = DateTime.now().subtract(Duration(days: days));
        if (p.datePronostic.isBefore(limite)) return false;
      }

      return true;
    }).toList();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  HELPERS — champs réels IaPronostic
  // ════════════════════════════════════════════════════════════════════════════

  /// Cote du favori IA : d'abord cotesPmuParNumero[favoriIa], sinon coteFavoriPmu.
  /// Retourne null si aucune cote fiable disponible.
  double? _coteFavori(IaPronostic p) {
    final favori = p.favoriIA; // numéro String du favori IA
    if (favori != null && p.cotesPmuParNumero.isNotEmpty) {
      final c = p.cotesPmuParNumero[favori];
      if (c != null && c > 1.0) return c;
    }
    final pmu = p.coteFavoriPmu;
    if (pmu != null && pmu > 1.0) return pmu;
    return null;
  }

  /// Score IA du favori (scoresIA[favoriIA], 0-100).
  double _scoreIaFavori(IaPronostic p) {
    final favori = p.favoriIA;
    if (favori == null) return 0.0;
    return p.scoresIA[favori] ?? 0.0;
  }

  /// Divergence forme/cote du favori IA (scoresCriteres[favoriIA].divergence, 0-100).
  /// 50 = neutre, >50 = IA plus optimiste que le marché.
  double _divergenceFavori(IaPronostic p) {
    final favori = p.favoriIA;
    if (favori == null) return 50.0;
    return p.scoresCriteres[favori]?.divergence ?? 50.0;
  }

  /// Label date lisible depuis datePronostic.
  String _dateLabel(IaPronostic p) {
    final d = p.datePronostic;
    return '${d.day.toString().padLeft(2, '0')}/'
           '${d.month.toString().padLeft(2, '0')}/'
           '${d.year}';
  }

  /// Validation métier stricte via le wrapper public existant.
  bool _estBon(IaPronostic p) =>
      IaMemoryService.instance.estBonConseil(p, p.typePariConseille ?? '');

  // ════════════════════════════════════════════════════════════════════════════
  //  ROI GLOBAL
  // ════════════════════════════════════════════════════════════════════════════

  RoiSummary calculerResume(RoiValueFilters filters) {
    final pronos = _filtrer(filters);

    int    nbParisRoi = 0;
    int    gagnants   = 0;
    int    perdants   = 0;
    int    outsiders  = 0;
    double mises      = 0;
    double retours    = 0;
    double sommeCoteG = 0;

    for (final p in pronos) {
      final cote = _coteFavori(p);
      if (cote == null) continue; // pas de cote = exclu du ROI

      nbParisRoi++;
      mises += 1.0;

      final gagne = _estBon(p);
      if (gagne) {
        gagnants++;
        retours    += cote;
        sommeCoteG += cote;
        if (cote >= 8.0) outsiders++;
      } else {
        perdants++;
      }
    }

    final gainNet = retours - mises;
    final roi     = mises == 0 ? 0.0 : (gainNet / mises) * 100.0;

    return RoiSummary(
      nbCourses:            pronos.length,
      nbParisRoi:           nbParisRoi,
      mises:                mises,
      retours:              retours,
      gainNet:              gainNet,
      roi:                  roi,
      gagnants:             gagnants,
      perdants:             perdants,
      tauxReussite:         nbParisRoi == 0 ? 0.0 : gagnants / nbParisRoi * 100.0,
      outsidersGagnants:    outsiders,
      coteMoyenneGagnants:  gagnants == 0 ? 0.0 : sommeCoteG / gagnants,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  ROI PAR DISCIPLINE
  // ════════════════════════════════════════════════════════════════════════════

  List<RoiByGroup> roiParDiscipline(RoiValueFilters base) {
    return ['Plat', 'Trot', 'Obstacle'].map((d) => RoiByGroup(
      label:   d,
      summary: calculerResume(base.copyWith(discipline: d)),
    )).toList();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  ROI PAR TYPE DE PARI
  // ════════════════════════════════════════════════════════════════════════════

  List<RoiByGroup> roiParTypePari(RoiValueFilters base) {
    const types = [
      'Simple Gagnant', 'Simple Placé',
      'Couplé Gagnant', 'Couplé Placé',
      'Tiercé', 'Quarté+', 'Quinté+',
    ];
    return types.map((t) => RoiByGroup(
      label:   t,
      summary: calculerResume(base.copyWith(typePari: t, discipline: 'Toutes')),
    )).toList();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  VALUE OPPORTUNITIES
  //  Critères : scoreIa >= 70 ET cote >= 5.0 ET divergence >= 60
  //  (divergence > 50 = IA plus optimiste que le marché)
  // ════════════════════════════════════════════════════════════════════════════

  List<ValueOpportunity> detecterValue(RoiValueFilters filters) {
    final pronos = _filtrer(filters);
    final out    = <ValueOpportunity>[];

    for (final p in pronos) {
      final cote = _coteFavori(p);
      if (cote == null || cote < 5.0) continue;

      final scoreIa    = _scoreIaFavori(p);
      final divergence = _divergenceFavori(p);

      // Score IA fort + cote intéressante + divergence positive (IA > marché)
      if (scoreIa < 70.0 || divergence < 60.0) continue;

      final favori = p.favoriIA ?? '-';
      final gagne  = _estBon(p);

      out.add(ValueOpportunity(
        date:        _dateLabel(p),
        discipline:  p.discipline,
        courseKey:   p.courseKey,
        courseNom:   p.nomCourse,
        typePari:    p.typePariConseille ?? 'Inconnu',
        favoriIa:    favori,
        scoreIa:     scoreIa,
        cote:        cote,
        divergence:  divergence,
        gagne:       gagne,
        retour:      gagne ? cote : 0.0,
        explication: gagne
            ? 'Value détectée et validée (${scoreIa.toStringAsFixed(0)}pts, cote ${cote.toStringAsFixed(1)})'
            : 'Value détectée, non validée (cote ${cote.toStringAsFixed(1)})',
      ));
    }

    out.sort((a, b) => b.divergence.compareTo(a.divergence));
    return out.take(50).toList();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  OUTSIDERS GAGNANTS
  //  Chevaux avec cotesPmuParNumero >= 8.0 arrivés dans le top 3 réel
  // ════════════════════════════════════════════════════════════════════════════

  List<OutsiderAnalyse> analyserOutsiders(RoiValueFilters filters) {
    final pronos = _filtrer(filters);
    final out    = <OutsiderAnalyse>[];

    for (final p in pronos) {
      final arrivee = p.arriveeReelle;
      if (arrivee == null || arrivee.isEmpty) continue;

      // Chercher dans cotesPmuParNumero les chevaux cote >= 8
      for (final entry in p.cotesPmuParNumero.entries) {
        final numero = entry.key;
        final cote   = entry.value;
        if (cote < 8.0) continue;

        final numeroInt = int.tryParse(numero);
        if (numeroInt == null) continue;

        // A-t-il fini dans le top 3 réel ?
        final rangReel = arrivee.indexOf(numeroInt) + 1;
        if (rangReel <= 0 || rangReel > 3) continue;

        // Quel était son rang IA ?
        final topIA   = p.topNIA;
        final rangIa  = topIA.indexOf(numero) + 1; // 0 si absent → +1 = 0 non trouvé
        final detecte = rangIa > 0 && rangIa <= 5;

        out.add(OutsiderAnalyse(
          date:        _dateLabel(p),
          discipline:  p.discipline,
          courseKey:   p.courseKey,
          courseNom:   p.nomCourse,
          numero:      numero,
          cote:        cote,
          rangIa:      rangIa, // 0 = absent du classement IA
          rangReel:    rangReel,
          detecteParIa: detecte,
          commentaire: detecte
              ? 'Outsider détecté par l\'IA (rang IA : $rangIa)'
              : rangIa == 0
                  ? 'Outsider non classé par l\'IA — raté'
                  : 'Outsider mal classé par l\'IA (rang IA : $rangIa)',
        ));
      }
    }

    out.sort((a, b) => b.cote.compareTo(a.cote));
    return out.take(50).toList();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  FAUX FAVORIS IA
  //  confiancePredite >= 80 ET pari perdant
  // ════════════════════════════════════════════════════════════════════════════

  List<FauxFavoriIa> detecterFauxFavoris(RoiValueFilters filters) {
    final pronos = _filtrer(filters);
    final out    = <FauxFavoriIa>[];

    for (final p in pronos) {
      final confiance = p.confiancePredite;
      if (confiance == null || confiance < 80.0) continue;

      final gagne = _estBon(p);
      if (gagne) continue; // seulement les perdants

      final favori = p.favoriIA ?? '-';
      final cote   = _coteFavori(p) ?? 0.0;

      out.add(FauxFavoriIa(
        date:            _dateLabel(p),
        discipline:      p.discipline,
        courseKey:       p.courseKey,
        courseNom:       p.nomCourse,
        typePari:        p.typePariConseille ?? 'Inconnu',
        favoriIa:        favori,
        confianceIa:     confiance,
        cote:            cote,
        raisonProbable:  _raisonFauxFavori(p, confiance),
      ));
    }

    out.sort((a, b) => b.confianceIa.compareTo(a.confianceIa));
    return out.take(50).toList();
  }

  String _raisonFauxFavori(IaPronostic p, double confiance) {
    final div = _divergenceFavori(p);
    final cote = _coteFavori(p);

    if (div < 40.0) return 'Faible divergence — pari défavorable au marché';
    if (cote != null && cote < 2.5) return 'Trop favori du marché — cote insuffisante';
    if (confiance >= 90.0) return 'Sur-confiance IA — signal d\'alarme';
    return 'Confiance élevée mais résultat non confirmé';
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  STATS RAPIDES — utilisées par le bandeau résumé
  // ════════════════════════════════════════════════════════════════════════════

  /// Nb total de pronostics avec résultat disponibles (sans filtre).
  int get nbPronosticsTotal =>
      IaMemoryService.instance.pronosticsAvecResultat.length;
}
