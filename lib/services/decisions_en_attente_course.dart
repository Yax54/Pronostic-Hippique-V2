// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — SÉLECTION DES DÉCISIONS EN ATTENTE, PAR TICKET ET PAR COURSE
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ CE QUE CE FICHIER FAIT — ET C'EST TOUT
//
//  Il SÉLECTIONNE, pour un écran donné, les décisions Accepter/Refuser à
//  présenter. Il ne décide rien, n'écrit rien, ne notifie rien et ne calcule
//  AUCUN montant.
//
//  ⚠️ POURQUOI CE FICHIER EXISTE
//
//  `mes_paris_screen.dart` construisait sa décision en attente à la main, et
//  `paris_detail_screen.dart` n'en construisait aucune : la décision n'était
//  donc accessible QUE depuis la carte de suivi. Exiger « le même chemin
//  sécurisé, quel que soit l'emplacement » implique une SEULE construction,
//  partagée. C'est elle, ici.
//
//  ⚠️ LA RÈGLE MÉTIER N'EST PAS REDÉFINIE ICI
//
//  Les trois exclusions (pas d'officiel, déjà décidé, identique au manuel) sont
//  celles de `gains_tardifs_en_attente.attendDecisionGain`, et le montant retenu
//  est celui du modèle (`gainRetenuBrut`). Ce fichier n'ajoute aucune condition :
//  deux définitions de « décision en attente » divergeraient, et un écran
//  proposerait alors une décision que le service ne reconnaît pas — ou
//  l'inverse.
//
//  ⚠️ IDENTIFICATION DE LA COURSE — DEUX CHEMINS, DANS CET ORDRE
//    ① la LIAISON CERTAINE (`idTicketLie`), quand elle existe : elle désigne
//      UN ticket, et deux paris sur la même course restent indépendants ;
//    ② à défaut, la course est identifiée par ses QUATRE composantes
//      réunion + course + JOUR. Le jour est indispensable : rien n'interdit
//      deux courses de mêmes numéros à des dates différentes, et les confondre
//      présenterait la décision d'une course sur l'écran d'une autre.
//      Aucune heuristique d'heure n'est employée.
// ═══════════════════════════════════════════════════════════════════════════

import '../models/pmu_models.dart' show UserPrediction;
import 'gains_tardifs_en_attente.dart'
    show DecisionEnAttente, attendDecisionGain;

/// Construit la décision en attente d'UN ticket, ou `null`.
///
/// ⚠️ SOURCE UNIQUE DE CONSTRUCTION : `mes_paris_screen`, `paris_detail_screen`
///    et la présentation à l'ouverture passent tous par ici. Les montants sont
///    des LECTURES du ticket (`montantGainManuel`, `montantOfficielPmu`,
///    `remboursementPmu`) ; rien n'est dérivé, arrondi ni additionné.
DecisionEnAttente? decisionEnAttenteDuTicket(UserPrediction? ticket) {
  if (ticket == null) return null;
  if (!attendDecisionGain(ticket)) return null;
  return DecisionEnAttente(
    ticket: ticket,
    gainManuel: ticket.montantGainManuel,
    gainOfficiel: ticket.montantOfficielPmu,
    remboursement: ticket.remboursementPmu,
  );
}

/// Le jour d'une date, au format `jjmmaaaa` — celui de `UserPrediction.dateStr`.
///
/// Rend `null` si la date est antérieure à l'an 1 : un ticket sans date
/// exploitable n'est jamais rattaché à une course par ressemblance.
String? jourAuFormatTicket(DateTime? d) {
  if (d == null) return null;
  if (d.year < 1) return null;
  final jj = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$jj$mm${d.year}';
}

/// TOUTES les décisions en attente d'UNE course, quel que soit le pari.
///
/// [ticketLie] est le ticket de la liaison certaine, s'il existe ; il passe en
/// tête et n'est jamais dupliqué dans le reste de la liste.
///
/// ⚠️ AUCUN MONTANT N'EST CHOISI ICI : on ne retient QUE les tickets pour
///    lesquels `attendDecisionGain` est vrai, et le gain affiché reste celui que
///    le modèle rend. Aucune sélection de dividende, aucun maximum.
List<DecisionEnAttente> decisionsEnAttenteDeCourse(
  Iterable<UserPrediction> predictions, {
  required int numReunion,
  required int numCourse,
  DateTime? heureDepart,
  UserPrediction? ticketLie,
}) {
  final jour = jourAuFormatTicket(heureDepart);

  final out = <DecisionEnAttente>[];
  final vus = <String>{};

  // ① La liaison certaine d'abord — elle désigne CE ticket, sans ambiguïté.
  final liee = decisionEnAttenteDuTicket(ticketLie);
  if (liee != null) {
    out.add(liee);
    vus.add(liee.id);
  }

  // ② Puis les autres paris de la MÊME course et du MÊME jour.
  for (final p in predictions) {
    if (vus.contains(p.id)) continue;
    if (p.numReunion != numReunion) continue;
    if (p.numCourse != numCourse) continue;
    // Sans jour connu de la course, on ne rattache RIEN par ressemblance :
    // c'est ce qui empêche de confondre deux courses de dates différentes.
    if (jour == null) break;
    if (p.dateStr != jour) continue;

    final d = decisionEnAttenteDuTicket(p);
    if (d == null) continue;
    out.add(d);
    vus.add(d.id);
  }

  return List<DecisionEnAttente>.unmodifiable(out);
}
