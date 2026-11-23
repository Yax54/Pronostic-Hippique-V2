// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / LOT 2-C — TYPE DE DÉCISION, DANS LA COUCHE MODÈLE
// ═══════════════════════════════════════════════════════════════════════════
//
//  ⚠️ POURQUOI ICI, ET PAS DANS UN SERVICE.
//
//  `pmu_models.dart` porte la décision et doit donc connaître ce type. Si le
//  type vivait dans un service important `pmu_models.dart`, l'import serait
//  circulaire (service → modèle → service). Il vit donc dans `lib/models/`,
//  couche dont `pmu_models.dart` fait déjà partie : AUCUN import ajouté de
//  service à modèle, aucun cycle.
//
//  Ce fichier n'importe RIEN. Il ne calcule RIEN. Il ne contient aucune règle
//  métier, aucun montant, aucune formule : seulement le nom des deux décisions
//  possibles.
// ═══════════════════════════════════════════════════════════════════════════

/// Décision de l'utilisateur sur un gain officiel PMU arrivé après coup.
///
/// `null` sur `UserPrediction.decisionGainPmu` = AUCUNE DÉCISION PRISE.
/// Ce n'est jamais un refus : le refus est une décision explicite, distincte
/// de l'absence de décision. Confondre les deux appliquerait un montant que
/// l'utilisateur n'a jamais validé, ou retirerait une décision qu'il n'a
/// jamais prise.
enum DecisionGainPmu {
  /// Le gain officiel fait foi. Le montant manuel est conservé en trace
  /// (`montantGainManuelAvantDecision`) mais ne participe plus au montant
  /// retenu.
  accepte,

  /// Le montant manuel fait foi. Le gain officiel reste en RÉFÉRENCE :
  /// il n'est ni effacé, ni appliqué.
  refuse,
}
