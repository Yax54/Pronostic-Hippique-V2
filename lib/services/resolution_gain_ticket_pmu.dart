// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-4.1 — RÉSOLUTION PURE DU GAIN D'UN TICKET
//
//  RÔLE UNIQUE DE CE FICHIER
//  ────────────────────────────────────────────────────────────────────────
//  Transmettre au moteur B-3 les informations EXACTES d'un ticket, puis
//  rendre son `VerdictGain` **sans le réinterpréter**.
//
//  Ce fichier est une COUCHE DE PASSAGE. Il ne juge pas, il ne choisit pas,
//  il ne complète pas. Tout arbitrage appartient au moteur B-3, qui délègue
//  lui-même au résolveur du rapport officiel.
//
//  ═══════════════════════════════════════════════════════════════════════════
//  RÈGLE FONDAMENTALE (exigence utilisateur, rappelée dans chaque consigne)
//  ────────────────────────────────────────────────────────────────────────
//  Un gain doit TOUJOURS correspondre au pari réellement joué, JAMAIS au
//  dividende le plus élevé.
//
//  ⇒ AUCUNE SÉLECTION DE MONTANT DANS CE FICHIER.
//  ⇒ Aucun `reduce(...)`, aucun `sort` par montant, aucun `max`, aucun
//     « meilleur rapport ». La liste des rapports est transmise TELLE QUELLE
//     au moteur, qui l'arbitre par égalité de code ET de variante.
//  ⇒ Les fonctions de filtrage ci-dessous ne comparent QUE des codes, des
//     libellés et des variantes — jamais des montants.
//
//  ═══════════════════════════════════════════════════════════════════════════
//  PÉRIMÈTRE — CE QUE CE FICHIER NE FAIT PAS
//  ────────────────────────────────────────────────────────────────────────
//  • Aucune écriture : ni disque, ni `setState`, ni `notifyListeners`.
//  • Aucun import de `AlertService`, `PmuProvider`, ou d'un écran.
//  • Aucune modification des objets reçus (les listes rendues sont NEUVES).
//  • Ne remplace pas le résolveur : il le laisse travailler.
//  • Ne touche ni `isGagne`, ni la persistance, ni l'affichage.
//  • Neutralise RIEN : `reduce(MAX)` des écrans reste en place (lot suivant).
//
//  ═══════════════════════════════════════════════════════════════════════════
//  CE QUI EST REFUSÉ PLUTÔT QUE DEVINÉ
//  ────────────────────────────────────────────────────────────────────────
//  • Un rapport sans libellé officiel : sa variant est INDÉTERMINABLE
//    (`varianteDepuisLibelle('')` rend `illisible`). On ne le transmet donc
//    PAS au moteur — le transmettre reviendrait à lui proposer un candidat
//    dont on ignore ce qu'il paie, c'est-à-dire à le laisser trancher sur une
//    donnée qu'on n'a pas su lire.
//  • Un montant `dividendeUnite` non reconnu.
//  • Une mise absente ou non strictement positive.
//  • Une arrivée sans groupes d'ex æquo : le moteur prononce lui-même
//    `deadHeatSansGroupes`, on ne fabrique aucun ordre.
//
//  ═══════════════════════════════════════════════════════════════════════════

import 'arbitre_variante_pmu.dart';
import 'gain_calculator.dart' show RapportPmu;
import 'gain_pmu_types.dart';
import 'gain_ticket_calculator.dart' show VarianteRapport, varianteDepuisLibelle;
import 'moteur_gain_pmu.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  1. LE TICKET — ce qu'il engage, tel qu'il est enregistré
// ═══════════════════════════════════════════════════════════════════════════

/// Les informations RÉELLEMENT enregistrées sur un ticket, réduites au strict
/// nécessaire au calcul. Aucun champ n'est déduit d'un autre.
///
/// Ce n'est pas un modèle persisté : c'est un **paramètre d'appel**. Le
/// construire ne modifie aucun objet existant.
class TicketAGainResoudre {
  /// Libellé de type tel qu'enregistré (« Quinté+ », « Tiercé Ordre »…).
  final String libelleTypePari;

  /// Numéros réellement joués, dans l'ordre de saisie.
  final List<int> numerosJoues;

  /// Mise d'un ticket à UNE composante. `null` si absente.
  final double? miseSimple;

  /// Mise de la composante Gagnant d'un Gagnant+Placé. `null` si absente.
  final double? miseGagnant;

  /// Mise de la composante Placé d'un Gagnant+Placé. `null` si absente.
  final double? misePlace;

  const TicketAGainResoudre.ticketSimple({
    required this.libelleTypePari,
    required this.numerosJoues,
    required double mise,
  })  : miseSimple = mise,
        miseGagnant = null,
        misePlace = null;

  const TicketAGainResoudre.gagnantPlace({
    required this.libelleTypePari,
    required this.numerosJoues,
    this.miseGagnant,
    this.misePlace,
  }) : miseSimple = null;

  /// Traduit les mises du ticket en [MiseEngagee] du moteur.
  ///
  /// Aucune mise n'est inventée : ce qui est `null` reste `null`, et le moteur
  /// prononce `montantAbsent` s'il n'a rien d'exploitable.
  MiseEngagee get miseEngagee => MiseEngagee(
        miseSimple: miseSimple,
        miseGagnant: miseGagnant,
        misePlace: misePlace,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
//  2. LE RÉSULTAT OFFICIEL — arrivée structurée + rapports publiés
// ═══════════════════════════════════════════════════════════════════════════

/// Le résultat officiel d'une course, tel qu'il est connu au moment du calcul.
///
/// ⚠️ [arriveeGroupes] est la SEULE arrivée exploitable : une liste plate ne
/// peut pas représenter un ex æquo. `null` signifie « groupes inconnus », et
/// le moteur en tire `deadHeatSansGroupes` — on ne fabrique AUCUN groupe.
///
/// ⚠️ [arriveeDefinitive] `null` signifie « l'API est muette ». On ne traduit
/// jamais ce silence par « définitif ».
class ResultatOfficielCourse {
  /// Groupes d'arrivée officiels, ex æquo préservés. `null` = inconnus.
  final List<List<int>>? arriveeGroupes;

  /// `false` = l'API dit explicitement « provisoire ». `null` = muette.
  final bool? arriveeDefinitive;

  /// Rapports officiels publiés pour cette course, TELLS QUELS.
  final List<RapportPmu> rapports;

  const ResultatOfficielCourse({
    required this.arriveeGroupes,
    required this.arriveeDefinitive,
    required this.rapports,
  });

  /// `true` si l'API a explicitement dit que l'arrivée n'est pas définitive.
  bool get estProvisoire => arriveeDefinitive == false;

  /// `true` si les frontières de groupes sont connues et exploitables.
  bool get aDesGroupes =>
      arriveeGroupes != null &&
      arriveeGroupes!.isNotEmpty &&
      arriveeGroupes!.every((g) => g.isNotEmpty);
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. CONVERSION — un rapport API vers un rapport publié, sans jugement
// ═══════════════════════════════════════════════════════════════════════════

/// Convertit UN [RapportPmu] en [RapportPublie], ou `null` si sa variante est
/// INDÉTERMINABLE.
///
/// Le refus explicite porte sur un seul point : un rapport privé de libellé
/// officiel n'a pas de variante déductible. `varianteDepuisLibelle` rend alors
/// `VarianteRapport.illisible`, et un rapport illisible ne peut désigner ni un
/// Ordre, ni un Désordre, ni un Bonus. Le transmettre au moteur reviendrait à
/// lui demander de trancher sur une donnée qu'on n'a pas su lire.
///
/// ⚠️ `pourUnEuro` est repris **tel quel** depuis [RapportPmu.dividende], qui
/// est déjà exprimé en euros pour un euro engagé (mesuré : la normalisation
/// `/100` est faite à la lecture de l'API, une seule fois). Aucune conversion
/// supplémentaire n'est appliquée ici — ce serait une double division.
RapportPublie? rapportPublieDepuisApi(RapportPmu r) {
  final libelle = r.libelleOfficiel.trim();
  final combinaison = r.combinaison.trim();
  if (combinaison.isEmpty) return null;

  final variante = varianteDepuisLibelle(libelle);
  if (variante == VarianteRapport.illisible) return null;

  // Code du BLOC : `codePariOfficiel` quand il est renseigné (c'est le
  // rattachement au bloc d'origine), sinon `typePari` qui porte la même
  // valeur dans l'API mesurée. Aucun code n'est inventé s'il manque.
  final codeBloc =
      r.codePariOfficiel.isNotEmpty ? r.codePariOfficiel : r.typePari;
  if (codeBloc.isEmpty) return null;

  // Un montant nul ou négatif n'est PAS un montant (cf. `aUnMontantExploitable`).
  // On le conserve tel quel : c'est le moteur qui prononcera `montantAbsent`,
  // avec son motif fermé. On ne filtre donc PAS sur le montant ici — filtrer
  // reviendrait à décider à sa place.
  return RapportPublie(
    codePmu: codeBloc,
    libelle: libelle,
    combinaison: combinaison,
    variante: variante,
    pourUnEuro: r.dividende,
    rang: r.rangCombinaisonPayable,
    miseBaseCentimes: r.miseBaseCentimes,
    rembourse: r.rembourse,
  );
}

/// Convertit une liste de rapports API en liste de rapports publiés.
///
/// Les éléments à variante indéterminable sont ÉCARTÉS (voir
/// [rapportPublieDepuisApi]) et NOMMÉS dans [ecartes] pour rester auditables.
/// La liste rendue est NEUVE : l'entrée n'est pas modifiée.
ListeRapportsPublies convertirRapportsApi(List<RapportPmu> rapports) {
  final publies = <RapportPublie>[];
  final ecartes = <String>[];
  for (final r in rapports) {
    final p = rapportPublieDepuisApi(r);
    if (p == null) {
      ecartes.add(
        'code="${r.typePari}" libelle="${r.libelleOfficiel}" '
        'combinaison="${r.combinaison}"',
      );
    } else {
      publies.add(p);
    }
  }
  return ListeRapportsPublies(publies, ecartes);
}

/// Résultat d'une conversion : les rapports exploitables, et la trace de ceux
/// qui ne l'étaient pas. Les deux listes sont NEUVES et non modifiables.
class ListeRapportsPublies {
  final List<RapportPublie> rapports;
  final List<String> ecartes;

  ListeRapportsPublies(List<RapportPublie> rapports, List<String> ecartes)
      : rapports = List<RapportPublie>.unmodifiable(rapports),
        ecartes = List<String>.unmodifiable(ecartes);

  int get nbEcartes => ecartes.length;
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. FONCTION PRINCIPALE — pure, sans écriture, sans effet de bord
// ═══════════════════════════════════════════════════════════════════════════

/// Résout le gain d'un ticket contre le résultat officiel d'une course.
///
/// **PURE.** Elle lit ses arguments, appelle le moteur B-3, et rend son
/// verdict. Elle n'écrit rien, ne modifie aucun objet reçu, n'appelle aucun
/// service, et ne touche ni `isGagne` ni la persistance.
///
/// Aucun montant n'est sélectionné ici : la liste des rapports est transmise
/// INTÉGRALEMENT au moteur, qui arbitre par égalité de code ET de variante et
/// délègue au résolveur du rapport officiel. Il n'existe, dans cette fonction,
/// aucune comparaison de montants.
VerdictGain resoudreGainTicketDepuisDonnees({
  required TicketAGainResoudre ticket,
  required ResultatOfficielCourse resultat,
}) {
  final conversion = convertirRapportsApi(resultat.rapports);

  final etat = EtatCourseOfficiel(
    arriveeGroupes: resultat.arriveeGroupes,
    arriveeDefinitive: resultat.arriveeDefinitive,
    // `unmodifiable` : le moteur ne peut pas modifier notre liste, et nous ne
    // pouvons pas modifier la sienne. Aucune référence partagée mutable.
    rapports: List<RapportPublie>.unmodifiable(conversion.rapports),
  );

  return resoudreGainTicket(
    libelleTypePari: ticket.libelleTypePari,
    numerosJoues: List<int>.unmodifiable(ticket.numerosJoues),
    mise: ticket.miseEngagee,
    etat: etat,
  );
}

/// Variante lisible : rend le verdict ET la trace des rapports écartés.
///
/// Utile aux tests et aux diagnostics : permet de prouver qu'un refus vient
/// d'un rapport illisible et non d'une décision silencieuse. Le verdict rendu
/// est **exactement** celui de [resoudreGainTicketDepuisDonnees] — même
/// chemin de calcul, aucune divergence possible.
class ResolutionGainAvecTrace {
  final VerdictGain verdict;
  final ListeRapportsPublies conversion;

  ResolutionGainAvecTrace(this.verdict, this.conversion);

  bool get aDesRapportsEcartes => conversion.nbEcartes > 0;
}

ResolutionGainAvecTrace resoudreGainTicketDepuisDonneesAvecTrace({
  required TicketAGainResoudre ticket,
  required ResultatOfficielCourse resultat,
}) {
  final conversion = convertirRapportsApi(resultat.rapports);
  final etat = EtatCourseOfficiel(
    arriveeGroupes: resultat.arriveeGroupes,
    arriveeDefinitive: resultat.arriveeDefinitive,
    rapports: List<RapportPublie>.unmodifiable(conversion.rapports),
  );
  final verdict = resoudreGainTicket(
    libelleTypePari: ticket.libelleTypePari,
    numerosJoues: List<int>.unmodifiable(ticket.numerosJoues),
    mise: ticket.miseEngagee,
    etat: etat,
  );
  return ResolutionGainAvecTrace(verdict, conversion);
}
