// ══════════════════════════════════════════════════════════════════════════════
//  roi_value_models.dart — Modèles de données ROI / Value Analytics
//  ★ v10.46 — Module 100% lecture seule
//  Source : IaPronostic (champs réels vérifiés)
// ══════════════════════════════════════════════════════════════════════════════

// ─── Filtres globaux ──────────────────────────────────────────────────────────

class RoiValueFilters {
  final String discipline; // 'Toutes' | 'Plat' | 'Trot' | 'Obstacle'
  final String periode;    // 'complet' | '30j' | '7j'
  final String typePari;   // 'Tous' | 'Simple Gagnant' | etc.

  const RoiValueFilters({
    this.discipline = 'Toutes',
    this.periode    = 'complet',
    this.typePari   = 'Tous',
  });

  RoiValueFilters copyWith({
    String? discipline,
    String? periode,
    String? typePari,
  }) => RoiValueFilters(
    discipline: discipline ?? this.discipline,
    periode:    periode    ?? this.periode,
    typePari:   typePari   ?? this.typePari,
  );
}

// ─── Résumé ROI global ou par groupe ─────────────────────────────────────────

class RoiSummary {
  final int    nbCourses;           // nb pronostics avec résultat dans le filtre
  final int    nbParisRoi;          // nb avec cote disponible (base ROI)
  final double mises;               // toujours = nbParisRoi × 1 €
  final double retours;             // somme des cotes gagnantes
  final double gainNet;             // retours - mises
  final double roi;                 // gainNet / mises × 100
  final int    gagnants;            // paris validés par _estBonConseilParType
  final int    perdants;
  final double tauxReussite;        // gagnants / nbParisRoi × 100
  final int    outsidersGagnants;   // gagnants avec coteFavoriPmu >= 8.0
  final double coteMoyenneGagnants; // moyenne des cotes gagnantes

  const RoiSummary({
    required this.nbCourses,
    required this.nbParisRoi,
    required this.mises,
    required this.retours,
    required this.gainNet,
    required this.roi,
    required this.gagnants,
    required this.perdants,
    required this.tauxReussite,
    required this.outsidersGagnants,
    required this.coteMoyenneGagnants,
  });

  static const RoiSummary vide = RoiSummary(
    nbCourses: 0, nbParisRoi: 0, mises: 0, retours: 0,
    gainNet: 0, roi: 0, gagnants: 0, perdants: 0,
    tauxReussite: 0, outsidersGagnants: 0, coteMoyenneGagnants: 0,
  );
}

// ─── ROI par groupe (discipline ou type de pari) ──────────────────────────────

class RoiByGroup {
  final String     label;
  final RoiSummary summary;

  const RoiByGroup({required this.label, required this.summary});
}

// ─── Value Opportunity ────────────────────────────────────────────────────────
// IA optimiste vs marché : score IA élevé + cote >= 5 + divergence forme/cote

class ValueOpportunity {
  final String   date;         // datePronostic formatée
  final String   discipline;
  final String   courseKey;
  final String   courseNom;    // nomCourse
  final String   typePari;     // typePariConseille
  final String   favoriIa;     // numéro du favori IA (topNIA[0])
  final double   scoreIa;      // score du favori IA (scoresIA[favoriIa])
  final double   cote;         // coteFavoriPmu ou cotesPmuParNumero[favoriIa]
  final double   divergence;   // scoresCriteres[favoriIa].divergence (0-100)
  final bool     gagne;        // estBonConseil
  final double   retour;       // cote si gagné, 0 sinon
  final String   explication;

  const ValueOpportunity({
    required this.date,
    required this.discipline,
    required this.courseKey,
    required this.courseNom,
    required this.typePari,
    required this.favoriIa,
    required this.scoreIa,
    required this.cote,
    required this.divergence,
    required this.gagne,
    required this.retour,
    required this.explication,
  });
}

// ─── Faux favori IA ───────────────────────────────────────────────────────────
// confiancePredite >= 80 mais pari perdant

class FauxFavoriIa {
  final String   date;
  final String   discipline;
  final String   courseKey;
  final String   courseNom;
  final String   typePari;
  final String   favoriIa;      // numéro String (topNIA[0])
  final double   confianceIa;   // confiancePredite
  final double   cote;          // coteFavoriPmu si dispo, 0 sinon
  final String   raisonProbable;

  const FauxFavoriIa({
    required this.date,
    required this.discipline,
    required this.courseKey,
    required this.courseNom,
    required this.typePari,
    required this.favoriIa,
    required this.confianceIa,
    required this.cote,
    required this.raisonProbable,
  });
}

// ─── Outsider analysé ─────────────────────────────────────────────────────────
// Cheval avec cote >= 8 qui arrive dans le top 3 réel

class OutsiderAnalyse {
  final String date;
  final String discipline;
  final String courseKey;
  final String courseNom;
  final String numero;      // String pour cohérence avec cotesPmuParNumero
  final double cote;
  final int    rangIa;      // position dans topNIA (1-based), 0 si absent
  final int    rangReel;    // position dans arriveeReelle (1-based)
  final bool   detecteParIa; // rangIa > 0 && rangIa <= 5
  final String commentaire;

  const OutsiderAnalyse({
    required this.date,
    required this.discipline,
    required this.courseKey,
    required this.courseNom,
    required this.numero,
    required this.cote,
    required this.rangIa,
    required this.rangReel,
    required this.detecteParIa,
    required this.commentaire,
  });
}
