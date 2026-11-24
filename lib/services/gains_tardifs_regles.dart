// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — RÈGLES MÉTIER DES GAINS OFFICIELS TARDIFS (PUR, SANS I/O)
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ CE QUE CE FICHIER FAIT
//
//  Il décide QUE FAIRE d'un résultat officiel arrivé après coup, à partir de
//  TROIS faits déjà persistés :
//    ① le gain manuel déclaré par l'utilisateur (`null` = aucune déclaration,
//       `0.0` = déclaration EXPLICITE de 0 €) ;
//    ② le gain officiel PMU établi (`null` = non établi) ;
//    ③ le remboursement officiel (`null` = non établi), qui n'est JAMAIS un
//       gain.
//
//  ★ CE QU'IL NE FAIT PAS, ET C'EST DÉLIBÉRÉ
//    • Il n'écrit rien : aucun I/O, aucun `SharedPreferences`, aucun réseau.
//    • Il ne calcule AUCUN montant PMU : il compare des montants DÉJÀ établis
//      par le moteur financier validé au chantier 1/3.
//    • Il ne prend AUCUNE décision Accepter/Refuser : il dit seulement si une
//      décision est REQUISE.
//
//  ⚠️ POURQUOI AUCUN IMPORT DU SOCLE `gain_pmu_types` : la garde B-0 tient une
//     liste FERMÉE de neuf importateurs, comparée par ÉGALITÉ. Ce fichier n'a
//     aucune raison d'en être le dixième, et n'en a pas besoin : il ne manipule
//     que des `double?` et des `bool`.
//
//  ⚠️ LA COMPARAISON EST AU CENTIME, comme au chantier 1/3 : `75.001` et
//     `75.00` sont le MÊME montant, `75.01` et `75.00` ne le sont pas. La
//     primitive est REUTILISÉE, jamais réécrite.
// ═══════════════════════════════════════════════════════════════════════════

import '../utils/comparaison_monetaire.dart' show memesCentimes;

/// Ce que l'application doit faire d'un gain officiel arrivé APRÈS COUP.
///
/// ⚠️ CES QUATRE CAS SONT EXHAUSTIFS ET MUTUELLEMENT EXCLUSIFS. Les confondre
///    produirait exactement les deux fautes que le chantier interdit :
///      • appliquer l'officiel sans preuve de conflit (CAS A) ;
///      • inventer une décision utilisateur là où il n'y a rien à arbitrer
///        (CAS B).
enum CasGainTardif {
  /// Aucun gain officiel n'est ÉTABLI : il n'y a rien à appliquer.
  ///
  /// ⚠️ C'est le cas d'un verdict `nonDetermine`, d'une arrivée provisoire, ou
  ///    d'un résultat dont le montant n'est pas démontrablement complet. Un
  ///    REMBOURSEMENT seul tombe ici : un remboursement n'est pas un gain, et
  ///    on ne fabrique jamais une comparaison de gains avec lui.
  aucun,

  /// Résultat officiel établi, AUCUN gain manuel déclaré.
  ///
  /// L'officiel est appliqué SANS décision utilisateur et SANS notification
  /// spécifique de gain tardif : personne ne « choisit » un rapport PMU, et il
  /// n'existe aucun conflit à arbitrer.
  sansGainManuel,

  /// Gain manuel ET gain officiel IDENTIQUES au centime.
  ///
  /// L'officiel est enregistré, le manuel est conservé, et UNE notification
  /// informative est produite. Aucune décision n'est demandée : accepter ou
  /// refuser deux montants identiques n'a aucun effet financier.
  identique,

  /// Gain manuel ET gain officiel DIFFÉRENTS au centime (ou officiel établi
  /// à 0 € face à un gain manuel non nul).
  ///
  /// L'officiel est enregistré en RÉFÉRENCE, le manuel reste le montant RETENU
  /// tant qu'aucune décision n'est prise, et une décision est REQUISE.
  different,
}

/// Résultat de la règle : le cas, et de quoi l'expliquer sans le recalculer.
///
/// [notificationRequise] est `false` au CAS A — c'est l'exigence littérale
/// « ne pas produire de notification spécifique de gain tardif » quand aucun
/// gain manuel n'existe.
class DecisionGainTardif {
  final CasGainTardif cas;

  /// Gain manuel observé, tel que persisté (`null` = aucune déclaration).
  final double? gainManuel;

  /// Gain officiel établi (`null` = non établi).
  final double? gainOfficiel;

  const DecisionGainTardif._({
    required this.cas,
    required this.gainManuel,
    required this.gainOfficiel,
  });

  /// Une notification doit-elle être produite pour CE ticket ?
  bool get notificationRequise =>
      cas == CasGainTardif.identique || cas == CasGainTardif.different;

  /// Une décision Accepter/Refuser doit-elle être demandée ?
  ///
  /// ⚠️ Vrai UNIQUEMENT au CAS C. Au CAS B, proposer une décision serait
  ///    simuler un arbitrage qui n'a pas lieu d'être.
  bool get decisionRequise => cas == CasGainTardif.different;

  /// Le résultat officiel doit-il être écrit par le chemin sécurisé ?
  bool get ecritureRequise => cas != CasGainTardif.aucun;

  /// Un gain manuel a-t-il été DÉCLARÉ ?
  ///
  /// ⚠️ `0.0` EST une déclaration : « j'ai gagné 0 € » est une information,
  ///    pas une absence. La condition est `!= null`, jamais `> 0`.
  bool get aUnGainManuel => gainManuel != null;

  @override
  String toString() => 'DecisionGainTardif(${cas.name}'
      ' | manuel=$gainManuel | officiel=$gainOfficiel)';
}

/// Applique la règle métier des gains tardifs — SANS écrire quoi que ce soit.
///
/// ORDRE DES DÉCISIONS, et pourquoi cet ordre :
///   ① Pas de gain officiel établi ⇒ [CasGainTardif.aucun]. On ne compare
///      RIEN : comparer un remboursement à un gain fabriquerait une
///      divergence qui n'existe pas.
///   ② Gain officiel établi, aucun gain manuel ⇒ [CasGainTardif.sansGainManuel].
///   ③ Les deux existent et sont égaux au centime ⇒ [CasGainTardif.identique].
///   ④ Les deux existent et diffèrent au centime ⇒ [CasGainTardif.different].
///
/// ⚠️ `gainOfficiel == null` N'EST PAS `0.0`. Un officiel à `0.0` est une
///    PERTE ÉTABLIE, et il fonde légitimement une divergence avec un gain
///    manuel non nul. Un officiel `null` est une absence d'information : elle
///    ne fonde rien du tout.
DecisionGainTardif deciderGainTardif({
  required double? gainManuel,
  required double? gainOfficiel,
}) {
  // ① Rien d'officiel à appliquer.
  if (gainOfficiel == null) {
    return DecisionGainTardif._(
      cas: CasGainTardif.aucun,
      gainManuel: gainManuel,
      gainOfficiel: null,
    );
  }

  // ② Aucun gain manuel déclaré : l'officiel s'applique silencieusement.
  //    `0.0` manuel N'ARRIVE PAS ICI : il est une déclaration (voir ③/④).
  if (gainManuel == null) {
    return DecisionGainTardif._(
      cas: CasGainTardif.sansGainManuel,
      gainManuel: null,
      gainOfficiel: gainOfficiel,
    );
  }

  // ③ / ④ Comparaison AU CENTIME, par la primitive partagée du chantier 1/3.
  final identiques = memesCentimes(gainManuel, gainOfficiel);
  return DecisionGainTardif._(
    cas: identiques ? CasGainTardif.identique : CasGainTardif.different,
    gainManuel: gainManuel,
    gainOfficiel: gainOfficiel,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  2. IDEMPOTENCE DES NOTIFICATIONS — clé STABLE, indépendante de l'historique
// ═══════════════════════════════════════════════════════════════════════════

/// Clé d'idempotence d'une notification de gain tardif.
///
/// L'identifiant du ticket durable (`UserPrediction.id`) est la SEULE clé
/// stable : il survit au redémarrage, à l'export/import, à la purge 24 h de
/// `tracked_courses_v1`, et à la purge de l'historique des alertes.
///
/// ⚠️ POURQUOI PAS LE MONTANT OFFICIEL DANS LA CLÉ : un montant officiel peut
///    être CORRIGÉ par l'opérateur. L'inclure créerait une seconde notification
///    pour le MÊME ticket — exactement le doublon interdit. La règle est « une
///    seule notification par ticket », pas « une par montant observé ».
///
/// ⚠️ POURQUOI PAS L'HISTORIQUE DES ALERTES : `alert_history_v1` est TEMPORAIRE
///    et purgé. Il ne peut donc pas constituer l'unique preuve qu'une
///    notification a déjà été produite. La preuve vit dans une clé DÉDIÉE et
///    PERSISTANTE (voir `gains_tardifs_notifies_v1`).
String cleIdempotenceNotification(String idTicket) => 'gt1:$idTicket';

/// Clé d'idempotence de la TRACE écrite, distincte de la notification.
///
/// Les deux sont séparées parce qu'elles peuvent échouer séparément : une
/// écriture financière réussie avec une notification échouée doit pouvoir
/// renotifier sans réécrire, et réciproquement. Les confondre rendrait l'un des
/// deux cas inexprimable.
String cleIdempotenceEcriture(String idTicket) => 'ge1:$idTicket';
