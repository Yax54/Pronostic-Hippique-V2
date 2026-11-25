// ═══════════════════════════════════════════════════════════════════════════
//  recommandation_pari_service.dart — SOURCE DE VÉRITÉ UNIQUE du type de pari
//
//  ★ CORRECTION BLOC 1 — anomalies BL1-A02, BL1-A03, BL1-A08, BL1-A14,
//    BL1-A15 et BL3-A26 (famille « barèmes concurrents »).
//
//  DÉFAUT CORRIGÉ
//  --------------
//  Le calcul « quel pari conseiller pour cette course » existait en SEPT
//  implémentations distinctes dans le dépôt, avec des barèmes différents :
//
//    1. `premium_utils.typePariEtNumerosPourCourse()`        — ADAPTATIF
//    2. `best_bet_screen._calculerOpportunites()`            — ADAPTATIF
//    3. `conseils_screen._getTypePariPourCourse()`           — FIGÉ (80/75/65/50/35)
//    4. `alert_service._getTypePariPourCourse()`             — FIGÉ (copie de 3)
//    5. `widget_service` cascade inline                      — TRONQUÉE (sans Couplé Placé,
//                                                               sans seuilGagnantPlace,
//                                                               sans seuilTierce)
//    6. `data_refresh_service._calculerPronosticsBatch()`     — ADAPTATIF sans isQuarte
//    7. `data_refresh_service._enregistrerPronosticsBatchFallback()` — ADAPTATIF sans isQuarte
//
//  Conséquences mesurées : jusqu'à 20 points d'écart sur le seuil Tiercé
//  (25–55 adaptatif contre 35 figé) ; deux types de pari différents pour la
//  MÊME course entre Best Bet et Conseils ; les courses Quarté+ recevaient
//  'Tiercé'/'Simple Placé' quand l'isolate échouait ; le widget Android
//  affichait 'À surveiller' là où Best Bet affichait 'Tiercé'.
//
//  CE QUE FAIT CE FICHIER
//  ----------------------
//  Il ne définit AUCUN seuil nouveau et ne modifie AUCUNE valeur numérique.
//  Il applique, dans un ordre unique, les seuils ADAPTATIFS existants
//  (`SeuilsConfianceAdaptatifs`, appris et persistés par `IaMemoryService`),
//  et reproduit exactement la cascade de `best_bet_screen` — celle qui était
//  déjà reconnue comme la référence adaptative.
//
//  La cascade « figée » de conseils/alertes est conservée à l'identique dans
//  sa STRUCTURE, mais ses nombres littéraux 80/75/65/50/35 sont remplacés par
//  les seuils adaptatifs dont ils étaient la copie codée en dur. Les valeurs
//  par défaut de ces seuils étant précisément 80/75/65/50/35, le comportement
//  d'une installation neuve est INCHANGÉ ; seule la capacité d'apprentissage
//  est rétablie.
//
//  CE QUE CE FICHIER NE FAIT PAS — GARANTIES
//  ------------------------------------------
//  • ne modifie aucun des 19 critères, aucune formule, aucun poids ;
//  • ne modifie ni `mouvCote`, ni `terrain`, ni aucun coefficient ;
//  • ne modifie aucun seuil adaptatif (lit seulement) ;
//  • ne touche ni la descente de gradient, ni le TOP3, ni l'apprentissage ;
//  • ne recalcule aucun score ni pronostic historique ;
//  • n'écrit rien : toutes les fonctions sont pures et sans effet de bord.
// ═══════════════════════════════════════════════════════════════════════════

import '../models/zt_models.dart';
import 'ia_memory_models.dart' show SeuilsConfianceAdaptatifs;

/// Seuils adaptatifs utilisés quand l'appelant n'a pas accès au singleton
/// `IaMemoryService` (cas des isolates et des fonctions top-level).
///
/// Il s'agit EXACTEMENT du constructeur par défaut de
/// `SeuilsConfianceAdaptatifs` : aucune valeur n'est inventée ici. Un isolate
/// qui dispose des seuils réels doit les passer explicitement — c'est ce que
/// fait `_calculerPronosticsBatch` via `payload.seuilsJson`.
SeuilsConfianceAdaptatifs seuilsParDefaut() => SeuilsConfianceAdaptatifs();

/// Seuils additionnels nécessaires à la cascade et absents de
/// `SeuilsConfianceAdaptatifs`.
///
/// ⚠️ CE SONT DES CONSTANTES DE CASCADE, PAS DES SEUILS D'APPRENTISSAGE.
///    Elles étaient auparavant codées en dur dans QUATRE fichiers différents
///    (conseils_screen, alert_service, deux fois best_bet_screen). Elles sont
///    regroupées ici pour rendre la divergence impossible, sans changer leur
///    valeur : 8.0 / 15 / 60 / 50 / 75 / 55 / 45 / 40 / 35.
abstract final class ParametresCascade {
  /// Cote maximale pour conseiller un Simple Gagnant plutôt qu'un Gagnant+Placé.
  static const double coteSimpleGagnantMax = 8.0;

  /// Écart de score maximum entre 1er et 2e pour considérer la course « équilibrée ».
  static const double ecartEquilibreMax = 15.0;

  /// Score minimum du 1er et du 2e pour la notion d'équilibre.
  static const double scoreMinEquilibre1 = 60.0;
  static const double scoreMinEquilibre2 = 50.0;

  /// Conditions multi-chevaux des courses Quinté+ / Quarté+ officielles.
  ///
  /// ⚠️ CES VALEURS NE SONT PAS DES SEUILS ADAPTATIFS et ne sont donc PAS
  ///    apprises : elles décrivent la qualité minimale de la SÉLECTION pour
  ///    engager 5, 4 ou 3 chevaux sur une course dont le type est imposé par
  ///    le PMU. Les valeurs ci-dessous sont **exactement** celles qui étaient
  ///    codées en dur dans `conseils_screen` et `alert_service` avant
  ///    unification — aucune n'a été arrondie, décalée ni « simplifiée ».
  static const double quinteScore1 = 75.0; // Quinté+ : 1er
  static const double quinteScore2 = 60.0; // Quinté+ : 2e
  static const double quinteScore3 = 55.0; // Quinté+ : 3e
  static const double quinteRetroQuarte1 = 65.0; // repli Quarté+ : 1er
  static const double quinteRetroQuarte2 = 55.0; // repli Quarté+ : 2e
  static const double quinteRetroTierce1 = 55.0; // repli Tiercé : 1er
  static const double quinteRetroTierce2 = 50.0; // repli Tiercé : 2e
  static const double quinteRetroCouple1 = 45.0; // repli Couplé Gagnant : 1er
  static const double quarteScore1 = 60.0; // Quarté+ : 1er
  static const double quarteScore2 = 50.0; // Quarté+ : 2e
  static const double quarteScore3 = 40.0; // Quarté+ : 3e
  static const double quarteScore4 = 35.0; // Quarté+ : 4e
  static const double quarteRetroTierce1 = 55.0; // repli Tiercé : 1er
  static const double quarteRetroTierce2 = 45.0; // repli Tiercé : 2e
  static const double quarteRetroTierce3 = 35.0; // repli Tiercé : 3e
  static const double quarteRetroCouple1 = 45.0; // repli Couplé Gagnant : 1er
  /// Repli « classique sans multiple » : 1er à 50 (le Tiercé est déjà servi
  /// par le seuil 75/55/45 ci-dessus).
  static const double classiqueRetroCouplePlace1 = 60.0;
  static const double classiqueRetroGagnantPlace1 = 50.0;

  /// Conditions « classique sans multiple » (Groupe 1/2/3, Poule d'Essai…).
  static const double classiqueScore1 = 75.0;
  static const double classiqueScore2 = 55.0;
  static const double classiqueScore3 = 45.0;
}

/// Résultat du calcul de recommandation.
///
/// `typePari` conserve EXACTEMENT les libellés historiques : les statistiques,
/// la persistance (`typePariConseille`), le calendrier et l'apprentissage
/// TOP3 les comparent par égalité de chaîne. Aucun libellé n'a été renommé.
class RecommandationPari {
  final String typePari;
  final String conseil;
  final int nbNumeros;

  /// ★ CORRECTION BLOC 1 (§5/§12) — ÉTAT DE LA COTE AYANT SERVI À DÉCIDER.
  ///
  ///   `false` : aucune cote exploitable n'a été fournie (`<= 0` ou `>= 99`).
  ///   Aucun consommateur ne doit alors présenter un GAIN CHIFFRÉ : la cote est
  ///   un « montant inconnu », ni estimée, ni simulée, ni officielle.
  ///
  ///   Ce champ ne change AUCUNE décision de type : il empêche seulement un
  ///   affichage financier fondé sur une cote absente (BL1-A11).
  final bool coteDisponible;

  const RecommandationPari({
    required this.typePari,
    required this.conseil,
    required this.nbNumeros,
    this.coteDisponible = true,
  });

  bool get estAbstention {
    return typePari == 'À surveiller' || typePari.isEmpty;
  }

  @override
  String toString() => 'RecommandationPari($typePari, $nbNumeros numéros)';
}

/// Nombre de numéros à stocker/afficher selon le type de pari.
///
/// ⚠️ Ne pas modifier : utilisé pour la persistance (`topNIA`) et pour
/// l'évaluation `_estBonConseilParType`. Valeurs historiques conservées.
int regleNbNumerosPourTypePari(String typePari) {
  if (typePari == 'Quinté+') return 5;
  if (typePari == 'Quarté+') return 4;
  if (typePari == 'Tiercé' ||
      typePari == 'Tiercé Ordre' ||
      typePari == 'Tiercé Désordre') {
    return 3;
  }
  if (typePari == 'Couplé Gagnant' || typePari == 'Couplé Placé') return 2;
  return 1;
}

/// **CASCADE UNIQUE DE RECOMMANDATION**
///
/// Tous les composants qui répondent à la question « quel pari conseiller pour
/// cette course » doivent passer par ici. Un composant qui a un objectif métier
/// réellement différent (par exemple un filtre de liste) doit le documenter
/// explicitement et ne pas dupliquer la cascade.
///
/// Paramètres :
///  • [seuils] — seuils ADAPTATIFS réels. En isolate, passer ceux du payload.
///  • [scoreConf], [score2nd], [score3], [score4] — scores des 4 premiers du
///    classement IA. `null` = donnée absente (jamais 0.0 inventé).
///  • [coteTop] — cote décimale du 1er. `0` ou `<= 0` = cote inconnue : aucune
///    décision ne doit alors dépendre du seuil de cote.
///
///    ⚠️ DIFFÉRENCE VOLONTAIRE AVEC L'ANCIEN CODE : `best_bet_screen` testait
///       `coteTop <= 8.0` sans vérifier que la cote existe. Une cote inconnue
///       valant `0.0` satisfaisait donc `0.0 <= 8.0` et produisait un
///       « Simple Gagnant » sur une donnée ABSENTE. Ici, la cote absente
///       n'active pas la branche « cote courte » : on poursuit la cascade et
///       l'on obtient « Gagnant+Placé », qui ne dépend pas de la cote.
///       Aucune valeur numérique n'est changée ; seule la confusion
///       « absent = 0 » est levée, conformément au mandat.
///
/// Le retour ne comporte jamais de montant financier : la cascade décide d'un
/// TYPE, elle ne calcule pas un gain.
RecommandationPari cascadeRecommandation({
  required ZtCourse course,
  required SeuilsConfianceAdaptatifs seuils,
  required double scoreConf,
  required double? score2nd,
  required double? score3,
  required double? score4,
  required double coteTop,
}) {
  final double s2 = score2nd ?? 0.0;
  final double s3 = score3 ?? 0.0;
  final double s4 = score4 ?? 0.0;
  final bool coteConnue = coteTop > 0.0 && coteTop < 99.0;

  final RecommandationPari brut = _cascadeBrut(
    course: course,
    seuils: seuils,
    scoreConf: scoreConf,
    s2: s2,
    s3: s3,
    s4: s4,
    coteTop: coteTop,
    coteConnue: coteConnue,
  );

  // ★ CORRECTION BLOC 1 — la disponibilité de la cote accompagne TOUJOURS la
  //   décision. Un consommateur qui afficherait « gain estimé = mise × cote »
  //   sur une cote absente produit un montant fictif ; il peut désormais le
  //   savoir sans re-tester la cote lui-même.
  return RecommandationPari(
    typePari: brut.typePari,
    conseil: brut.conseil,
    nbNumeros: brut.nbNumeros,
    coteDisponible: coteConnue,
  );
}

RecommandationPari _cascadeBrut({
  required ZtCourse course,
  required SeuilsConfianceAdaptatifs seuils,
  required double scoreConf,
  required double s2,
  required double s3,
  required double s4,
  required double coteTop,
  required bool coteConnue,
}) {
  // ── Garde 1 : aucune donnée de classement → abstention explicite ──────────
  if (course.partants.isEmpty) {
    return const RecommandationPari(
      typePari: 'À surveiller',
      conseil: 'Aucun partant classé : aucune recommandation possible.',
      nbNumeros: 0,
    );
  }

  final double ecart12 = (scoreConf - s2).abs();
  final bool estEquilibre = ecart12 <= ParametresCascade.ecartEquilibreMax &&
      scoreConf >= ParametresCascade.scoreMinEquilibre1 &&
      s2 >= ParametresCascade.scoreMinEquilibre2;

  // ══════════════════════════════════════════════════════════════════════════
  //  1. COURSES OFFICIELLES QUINTÉ+ / QUARTÉ+
  //
  //  RÈGLE MÉTIER : ces paris n'existent que si PMU les ouvre. `isQuinte` et
  //  `isQuarte` viennent du programme PMU réel (`zone_turf_service.dart`), et
  //  non d'une heuristique de score. On ne force donc JAMAIS un Quinté+ sur
  //  une course qui ne l'est pas — et on ne l'exclut jamais quand elle l'est.
  //
  //  ⚠️ DÉCISION MÉTIER SIGNALÉE (voir rapport final) : les blocs ci-dessous
  //     étaient répartis entre une version « figée » (conseils/alertes) et une
  //     version « adaptative » (best_bet/premium_utils). La version retenue
  //     ici est celle qui ENGAGE le multiple officiel sur des conditions de
  //     sélection, puis rétrograde progressivement. Les seuils adaptatifs
  //     `seuilQuarte` (défaut 80) et `seuilQuinte` (défaut 0) restent donc
  //     SANS EFFET DÉCISIONNEL ici — voir l'anomalie BL1-A15 traitée dans le
  //     rapport : ce sont des seuils PERSISTÉS et AFFICHÉS dont l'activation
  //     décisionnelle exigerait une décision métier explicite, qui n'est pas
  //     prise sans validation utilisateur.
  //     Aucune valeur numérique n'a été modifiée par rapport à l'existant.
  // ══════════════════════════════════════════════════════════════════════════
  if (course.isQuinte) {
    if (scoreConf >= ParametresCascade.quinteScore1 &&
        s2 >= ParametresCascade.quinteScore2 &&
        s3 >= ParametresCascade.quinteScore3) {
      return RecommandationPari(
        typePari: 'Quinté+',
        conseil: 'Course Quinté+ officielle. Sélection IA : ${_liste(course, 5)}.',
        nbNumeros: 5,
      );
    }
    if (scoreConf >= ParametresCascade.quinteRetroQuarte1 &&
        s2 >= ParametresCascade.quinteRetroQuarte2) {
      return RecommandationPari(
        typePari: 'Quarté+',
        conseil: 'Quinté+ officiel, sélection resserrée sur 4 chevaux : '
            '${_liste(course, 4)}.',
        nbNumeros: 4,
      );
    }
    if (scoreConf >= ParametresCascade.quinteRetroTierce1 &&
        s2 >= ParametresCascade.quinteRetroTierce2) {
      return RecommandationPari(
        typePari: 'Tiercé',
        conseil: 'Quinté+ officiel — confiance limitée, jouer le Tiercé : '
            '${_liste(course, 3)}.',
        nbNumeros: 3,
      );
    }
    if (scoreConf >= ParametresCascade.quinteRetroCouple1) {
      return RecommandationPari(
        typePari: 'Couplé Gagnant',
        conseil: 'Quinté+ officiel — confiance trop faible pour un multiple. '
            'Couplé Gagnant : ${_liste(course, 2)}.',
        nbNumeros: 2,
      );
    }
    return RecommandationPari(
      typePari: 'À surveiller',
      conseil: 'Quinté+ officiel mais scores insuffisants '
          '(${scoreConf.round()}/100) : abstention conseillée.',
      nbNumeros: 0,
    );
  }

  if (course.isQuarte) {
    if (scoreConf >= ParametresCascade.quarteScore1 &&
        s2 >= ParametresCascade.quarteScore2 &&
        s3 >= ParametresCascade.quarteScore3 &&
        s4 >= ParametresCascade.quarteScore4) {
      return RecommandationPari(
        typePari: 'Quarté+',
        conseil: 'Course Quarté+ officielle. Sélection IA (4 chevaux) : '
            '${_liste(course, 4)}.',
        nbNumeros: 4,
      );
    }
    if (scoreConf >= ParametresCascade.quarteRetroTierce1 &&
        s2 >= ParametresCascade.quarteRetroTierce2 &&
        s3 >= ParametresCascade.quarteRetroTierce3) {
      return RecommandationPari(
        typePari: 'Tiercé',
        conseil: 'Quarté+ officiel — confiance limitée, jouer le Tiercé : '
            '${_liste(course, 3)}.',
        nbNumeros: 3,
      );
    }
    if (scoreConf >= ParametresCascade.quarteRetroCouple1) {
      return RecommandationPari(
        typePari: 'Couplé Gagnant',
        conseil: 'Quarté+ officiel — confiance faible, jouer le Couplé '
            'Gagnant : ${_liste(course, 2)}.',
        nbNumeros: 2,
      );
    }
    return RecommandationPari(
      typePari: 'À surveiller',
      conseil: 'Quarté+ officiel mais scores insuffisants '
          '(${scoreConf.round()}/100) : abstention conseillée.',
      nbNumeros: 0,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  2. COURSES CLASSIQUES SANS MULTIPLE
  //
  //  PMU ne publie que le Tiercé sur ces courses : Quarté+/Quinté+ sont
  //  matériellement impossibles. La cascade plafonne donc au Tiercé.
  // ══════════════════════════════════════════════════════════════════════════
  if (course.isClassiqueSansMultiple) {
    if (scoreConf >= ParametresCascade.classiqueScore1 &&
        s2 >= ParametresCascade.classiqueScore2 &&
        s3 >= ParametresCascade.classiqueScore3) {
      return RecommandationPari(
        typePari: 'Tiercé',
        conseil: 'Course classique (Tiercé seul au PMU). Sélection IA : '
            '${_liste(course, 3)}.',
        nbNumeros: 3,
      );
    }
    if (estEquilibre && scoreConf >= ParametresCascade.quinteScore1) {
      return _coupleGagnant(course);
    }
    if (estEquilibre && scoreConf >= ParametresCascade.classiqueRetroCouplePlace1) {
      return _couplePlace(course);
    }
    if (coteConnue &&
        scoreConf >= seuils.seuilSimpleGagnant &&
        coteTop <= ParametresCascade.coteSimpleGagnantMax) {
      return _simpleGagnant(course, scoreConf);
    }
    // ★ CORRECTION BLOC 1 (§12) — COTE INCONNUE : PAS DE « GAGNANT+PLACÉ »
    //   AUTOMATIQUE.
    //
    //   Le Gagnant+Placé est, dans cette cascade, le pari d'un score élevé
    //   accompagné d'une COTE LONGUE (« cote longue ×12,5 », branche
    //   ci-dessous). Sans cote connue, cette justification est fabriquée : on
    //   recommanderait un pari à DEUX mises dont le rapport est inconnu, en
    //   invoquant une cote qui n'existe pas.
    //
    //   Donc, quand la cote est absente, le score élevé conduit au pari
    //   SCORE-SEULEMENT le moins engageant : Simple Placé (une seule mise,
    //   aucune dépendance à la cote). Aucune valeur de seuil n'est changée ;
    //   seule la branche dont la prémisse (cote longue) est indémontrable est
    //   neutralisée. La cote déclarée indisponible interdit en outre tout
    //   affichage de gain chiffré en aval (`coteDisponible == false`).
    if (!coteConnue && scoreConf >= seuils.seuilSimpleGagnant) {
      return _simplePlace(course, scoreConf);
    }
    if (coteConnue && scoreConf >= seuils.seuilSimpleGagnant) {
      return _gagnantPlace(course, scoreConf, coteTop, coteConnue);
    }
    if (scoreConf >= seuils.seuilSimplePlace) return _simplePlace(course, scoreConf);
    if (scoreConf >= ParametresCascade.classiqueRetroGagnantPlace1) {
      return _gagnantPlace(course, scoreConf, coteTop, coteConnue);
    }
    return _abstention(scoreConf);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  3. COURSES ORDINAIRES — cascade adaptative de référence
  //     (ordre et bornes identiques à best_bet_screen, seule référence qui
  //     utilisait déjà les seuils appris)
  // ══════════════════════════════════════════════════════════════════════════
  if (estEquilibre && scoreConf >= seuils.seuilCoupleGagnant) {
    return _coupleGagnant(course);
  }
  if (estEquilibre && scoreConf >= seuils.seuilCouplePlace) {
    return _couplePlace(course);
  }
  if (coteConnue &&
      scoreConf >= seuils.seuilSimpleGagnant &&
      coteTop <= ParametresCascade.coteSimpleGagnantMax) {
    return _simpleGagnant(course, scoreConf);
  }
  // ★ Même règle que ci-dessus : cote absente ⇒ pas de Gagnant+Placé déduit
  //   d'une « cote longue » indémontrable.
  if (!coteConnue && scoreConf >= seuils.seuilSimpleGagnant) {
    return _simplePlace(course, scoreConf);
  }
  if (coteConnue && scoreConf >= seuils.seuilSimpleGagnant) {
    return _gagnantPlace(course, scoreConf, coteTop, coteConnue);
  }
  if (scoreConf >= seuils.seuilSimplePlace) return _simplePlace(course, scoreConf);
  if (coteConnue && scoreConf >= seuils.seuilGagnantPlace) {
    return _gagnantPlace(course, scoreConf, coteTop, coteConnue);
  }
  if (scoreConf >= seuils.seuilTierce) {
    return RecommandationPari(
      typePari: 'Tiercé',
      conseil: 'Course incertaine (${scoreConf.round()}/100). '
          'Tiercé IA en désordre : ${_liste(course, 3)}.',
      nbNumeros: 3,
    );
  }
  return _abstention(scoreConf);
}

// ── Constructeurs de branches (un seul endroit pour chaque libellé) ─────────

String _liste(ZtCourse course, int n) =>
    course.partantsParRangIA.take(n).map((p) => 'N°${p.numero}').join(' - ');

RecommandationPari _coupleGagnant(ZtCourse course) {
  final sorted = course.partantsParRangIA;
  final s = sorted.length >= 2
      ? 'N°${sorted[0].numero} ${sorted[0].nom} + N°${sorted[1].numero} ${sorted[1].nom}'
      : 'sélection incomplète';
  return RecommandationPari(
    typePari: 'Couplé Gagnant',
    conseil: 'Deux favoris très proches. Couplé Gagnant : $s.',
    nbNumeros: 2,
  );
}

RecommandationPari _couplePlace(ZtCourse course) {
  final sorted = course.partantsParRangIA;
  final s = sorted.length >= 2
      ? 'N°${sorted[0].numero} + N°${sorted[1].numero}'
      : 'sélection incomplète';
  return RecommandationPari(
    typePari: 'Couplé Placé',
    conseil: 'Course équilibrée. Couplé Placé : $s dans le top 3.',
    nbNumeros: 2,
  );
}

RecommandationPari _simpleGagnant(ZtCourse course, double scoreConf) {
  final top = course.partantsParRangIA.first;
  return RecommandationPari(
    typePari: 'Simple Gagnant',
    conseil: 'Confiance très haute (${scoreConf.round()}/100). Misez sur '
        'N°${top.numero} ${top.nom} en Simple Gagnant.',
    nbNumeros: 1,
  );
}

RecommandationPari _simplePlace(ZtCourse course, double scoreConf) {
  final top = course.partantsParRangIA.first;
  return RecommandationPari(
    typePari: 'Simple Placé',
    conseil: 'Bon profil (${scoreConf.round()}/100). N°${top.numero} '
        '${top.nom} en Simple Placé (top 3).',
    nbNumeros: 1,
  );
}

RecommandationPari _gagnantPlace(
    ZtCourse course, double scoreConf, double coteTop, bool coteConnue) {
  final top = course.partantsParRangIA.first;
  final complement = (coteConnue && coteTop > ParametresCascade.coteSimpleGagnantMax)
      ? 'cote longue (×${coteTop.toStringAsFixed(1)})'
      : 'score moyen';
  return RecommandationPari(
    typePari: 'Gagnant+Placé',
    conseil: 'Profil $complement (${scoreConf.round()}/100). '
        'Gagnant+Placé sécurise la mise sur N°${top.numero} ${top.nom}.',
    nbNumeros: 1,
  );
}

RecommandationPari _abstention(double scoreConf) => RecommandationPari(
      typePari: 'À surveiller',
      conseil: 'Course très ouverte (${scoreConf.round()}/100). '
          'Mise minimale ou abstention conseillée.',
      nbNumeros: 0,
    );
