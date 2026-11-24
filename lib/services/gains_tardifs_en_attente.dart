// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — DÉCISIONS FINANCIÈRES EN ATTENTE
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ CE QUE CE FICHIER FAIT — ET C'EST TOUT
//
//  Il RÉPOND À UNE QUESTION DE LECTURE : « quels tickets attendent une
//  décision Accepter/Refuser ? ». Il ne décide rien, n'écrit rien, ne notifie
//  rien. Aucune formule monétaire n'est ici : les montants affichés sont LUS
//  sur le ticket persisté, jamais recalculés.
//
//  ⚠️ LE CRITÈRE EST UN SEUL, ET IL EST EXPLICITE :
//       `montantOfficielPmu != null && decisionGainPmu == null`
//     c'est-à-dire : un résultat officiel existe, et aucune décision n'a été
//     enregistrée. C'est exactement la condition `demandeOuverte` déjà
//     utilisée par `mes_paris_screen.dart` (`_vueDurable`) — on ne crée donc
//     pas une seconde définition de « décision en attente ».
//
//  ⚠️ CE QUI N'EST **PAS** UNE DÉCISION EN ATTENTE :
//     • un ticket sans résultat officiel (il n'y a rien à accepter) ;
//     • un ticket `accepte` ou `refuse` (la décision est prise, et elle ne
//       doit JAMAIS être représentée — c'est l'exigence §8 : « Ne pas
//       présenter une nouvelle fois la même décision ») ;
//     • un ticket dont le résultat officiel est identique au gain manuel
//       déclaré : il n'y a aucun conflit à arbitrer. Sa notification est
//       informative (CAS B), pas une demande. Le proposer reviendrait à
//       demander d'accepter un montant identique, ce que le chantier interdit
//       explicitement.
//
//  ⚠️ AUCUNE DÉCISION N'EST PRISE ICI. Fermer la présentation ne clôt rien :
//     le ticket reste dans cette liste tant qu'aucune décision n'est écrite.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import '../models/pmu_models.dart' show UserPrediction;
import 'gains_tardifs_regles.dart' show CasGainTardif, deciderGainTardif;

/// Une décision en attente, telle qu'elle doit être PRÉSENTÉE.
///
/// Tous les montants sont des LECTURES du ticket persisté. Aucune valeur n'est
/// dérivée, arrondie ou normalisée ici : l'affichage fait foi sur la donnée.
@immutable
class DecisionEnAttente {
  /// Le ticket concerné — la vérité financière.
  final UserPrediction ticket;

  /// Gain déclaré par l'utilisateur. Peut valoir `0.0` : c'est une
  /// déclaration explicite, jamais une absence.
  final double? gainManuel;

  /// Gain établi officiellement. Non nul par construction de cette liste.
  final double? gainOfficiel;

  /// Remboursement officiel, quand il existe. JAMAIS incorporé au gain :
  /// c'est une nature différente, et les additionner rendrait « Gain gagné »
  /// faux.
  final double? remboursement;

  const DecisionEnAttente({
    required this.ticket,
    required this.gainManuel,
    required this.gainOfficiel,
    required this.remboursement,
  });

  /// Le gain effectivement retenu AUJOURD'HUI, avant décision.
  ///
  /// ⚠️ DÉLÉGUÉ AU MODÈLE, jamais recalculé : `gainRetenuBrut` porte les cinq
  ///    branches validées au chantier 1. En reproduire une ici créerait une
  ///    seconde vérité, donc une divergence possible.
  double? get gainRetenu => ticket.gainRetenuBrut;

  /// Identifiant du ticket, pour les actions Accepter/Refuser.
  String get id => ticket.id;

  /// Libellé de la course, pour l'affichage.
  String get libelleCourse =>
      'R${ticket.numReunion}C${ticket.numCourse} — ${ticket.nomCourse}';

  @override
  String toString() => 'DecisionEnAttente(${ticket.id} | '
      'manuel=$gainManuel | officiel=$gainOfficiel | '
      'remboursement=$remboursement)';
}

/// La règle de sélection, PURE et sans effet de bord.
///
/// Rend `true` si [ticket] attend une décision Accepter/Refuser. Les trois
/// exclusions sont nommées une par une, dans l'ordre, pour qu'aucune ne puisse
/// être perdue lors d'une relecture.
bool attendDecisionGain(UserPrediction ticket) {
  // ① Aucun résultat officiel : rien à accepter ni à refuser.
  if (ticket.montantOfficielPmu == null) return false;

  // ② Une décision est déjà enregistrée : elle fait foi et ne sera pas
  //    représentée. `null` seul signifie « pas encore décidé ».
  if (ticket.decisionGainPmu != null) return false;

  // ③ Officiel IDENTIQUE au manuel : aucun conflit. Comparaison au centime,
  //    via la MÊME fonction que le service et que l'enregistreur.
  final decision = deciderGainTardif(
    gainManuel: ticket.montantGainManuel,
    gainOfficiel: ticket.montantOfficielPmu,
  );
  if (decision.cas == CasGainTardif.identique) return false;

  // Un gain manuel de 0 € EST un gain manuel : `deciderGainTardif` distingue
  // déjà `sansGainManuel` (manuel null) de `different` (0 € vs 12 €). Rien à
  // ajouter ici — et surtout pas un test `> 0` qui ferait disparaître le cas.
  return decision.cas == CasGainTardif.different;
}

/// Les décisions en attente d'une liste de tickets, les plus récentes d'abord.
///
/// Aucun accès disque, aucun réseau, aucun `await` : une fonction pure sur une
/// liste, donc testable sans simulation.
List<DecisionEnAttente> decisionsEnAttente(
    Iterable<UserPrediction> predictions) {
  final out = <DecisionEnAttente>[];
  for (final p in predictions) {
    if (!attendDecisionGain(p)) continue;
    out.add(DecisionEnAttente(
      ticket: p,
      gainManuel: p.montantGainManuel,
      gainOfficiel: p.montantOfficielPmu,
      remboursement: p.remboursementPmu,
    ));
  }
  out.sort((a, b) => b.ticket.createdAt.compareTo(a.ticket.createdAt));
  return List<DecisionEnAttente>.unmodifiable(out);
}

/// Y a-t-il au moins une décision en attente ? Utilisé par l'indicateur de
/// notifications — une lecture, encore.
bool aDesDecisionsEnAttente(Iterable<UserPrediction> predictions) =>
    predictions.any(attendDecisionGain);
