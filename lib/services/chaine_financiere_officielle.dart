// ═══════════════════════════════════════════════════════════════════════════
//  CHAÎNE FINANCIÈRE OFFICIELLE — LE POINT D'ENTRÉE UNIQUE
//
//  ★ CORRECTION BLOC 1 — périmètre financier (arbitrage utilisateur, points
//    4, 8 et 9).
//
//  ───────────────────────────────────────────────────────────────────────────
//  RÔLE
//  ───────────────────────────────────────────────────────────────────────────
//  Ce fichier est la SEULE porte par laquelle un outil de simulation
//  (backtesting, Martingale, Best Bet, ROI, Laboratoire IA) peut obtenir un
//  résultat financier. Il assemble trois briques qui existaient déjà, sans en
//  réécrire aucune :
//
//    ① `PmuApiService.fetchRapportsDefinitifs` + `ZoneTurfService` —
//       récupération officielle (réseau) ;
//    ② `ResultatOfficielRepository` — persistance PARTAGÉE par identité
//       complète (date + réunion + course) ;
//    ③ `resoudreGainTicketDepuisDonnees` (`resolution_gain_ticket_pmu.dart`) —
//       résolution PURE, documentée « n'écrit rien, n'appelle aucun service,
//       ne touche ni `isGagne` ni la persistance ».
//
//  ───────────────────────────────────────────────────────────────────────────
//  CE QUE CE FICHIER NE FAIT PAS — ET POURQUOI C'EST STRUCTUREL
//  ───────────────────────────────────────────────────────────────────────────
//   • AUCUN calcul de montant. Preuve par construction : il n'appelle ni
//     `RapportAttribue.calculer`, ni `totalDesMontantsRetour`, et n'écrit
//     aucune multiplication `mise × cote`. Tous les montants viennent du
//     `VerdictGain` du moteur unique.
//   • AUCUN apprentissage. Il n'importe pas `ia_memory_service.dart`. Il ne
//     peut donc ni appeler `enregistrerResultat`, ni `ajusterSeuil`, ni
//     `mettreAJourStatsTypes`, ni toucher un poids ou une calibration. Le
//     point 9 de l'arbitrage — « la récupération des rapports officiels à des
//     fins financières ne doit pas déclencher de nouvel apprentissage » — est
//     donc tenu par ABSENCE D'IMPORT, pas par convention.
//   • AUCUNE écriture dans les tickets réels (« Mes Paris »). Il n'importe ni
//     `alert_service`, ni `enregistreur_verdict_gain_pmu`, ni
//     `enregistreur_verdict_gain_suivi`, ni `service_gains_tardifs`. Aucune
//     notification de gain tardif ne peut donc partir d'ici.
//   • AUCUN second moteur : il n'existe, dans ce fichier, aucune règle de
//     correspondance pari/rapport. Cette décision appartient au moteur.
//   • AUCUNE requête réseau répétée : une entrée déjà persistée et EXPLOITABLE
//     est servie sans réseau. C'est la « récupération maîtrisée, sans requêtes
//     répétitives inutiles » du point 4.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import 'branchement_verdict_course.dart' show chargerResultatOfficielCourse;
import 'gain_calculator.dart' show RapportPmu;
import 'moteur_gain_pmu.dart' show MiseEngagee, VerdictGain;
import 'resolution_gain_ticket_pmu.dart'
    show
        ResultatOfficielCourse,
        TicketAGainResoudre,
        resoudreGainTicketDepuisDonnees;
import 'resultat_officiel_repository.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  1. STATUT D'UNE RÉSOLUTION — « non déterminé » est un état de PREMIÈRE CLASSE
// ═══════════════════════════════════════════════════════════════════════════

/// Pourquoi une résolution n'a pas pu être menée.
///
/// Chaque valeur nomme une cause MESURÉE. Aucune ne se traduit en perte.
enum CauseNonDetermination {
  /// L'identité de la course ne peut pas être établie (pas de date réelle,
  /// pas de numéro de réunion ou de course). Une clé `R1C3` sans date tombe
  /// ici : on ne suppose jamais que la course est celle d'aujourd'hui.
  identiteIndeterminable,

  /// Aucun résultat officiel n'est conservé ET le réseau n'a pas été autorisé.
  /// L'appelant a explicitement refusé une récupération : rien n'est inventé.
  resultatAbsentSansRecuperation,

  /// Le réseau a été autorisé, la récupération a été tentée, et elle n'a rien
  /// rendu d'exploitable (course non réglée, HTTP non 200, timeout, réseau).
  resultatIndisponible,

  /// Le résultat est conservé mais ne porte aucun rapport officiel.
  rapportsAbsents,

  /// Le résultat est conservé mais ne porte aucune arrivée exploitable.
  arriveeAbsente,

  /// Le ticket lui-même ne peut pas être construit : libellé hors référentiel,
  /// taille de combinaison anormale, mise nulle ou négative.
  ticketNonConstructible,
}

/// Résultat d'une demande de résolution financière.
///
/// Un seul des deux champs [verdict] / [cause] est renseigné. Il est donc
/// STRUCTURELLEMENT impossible de lire un montant sur une résolution non
/// déterminée : `verdict` vaut `null`, et le montant n'existe pas.
class ResolutionFinanciere {
  /// Verdict du moteur officiel. `null` si et seulement si non déterminé.
  final VerdictGain? verdict;

  /// Cause de la non-détermination. `null` si et seulement si déterminé.
  final CauseNonDetermination? cause;

  /// Explication lisible, toujours renseignée.
  final String explication;

  /// `true` si l'entrée a été servie depuis le stockage sans réseau.
  final bool servieDepuisStockage;

  const ResolutionFinanciere._({
    required this.verdict,
    required this.cause,
    required this.explication,
    required this.servieDepuisStockage,
  });

  factory ResolutionFinanciere.determinee({
    required VerdictGain verdict,
    required bool servieDepuisStockage,
  }) =>
      ResolutionFinanciere._(
        verdict: verdict,
        cause: null,
        explication: verdict.explication.isEmpty
            ? verdict.etat.name
            : verdict.explication,
        servieDepuisStockage: servieDepuisStockage,
      );

  factory ResolutionFinanciere.nonDeterminee({
    required CauseNonDetermination cause,
    required String explication,
    bool servieDepuisStockage = false,
  }) =>
      ResolutionFinanciere._(
        verdict: null,
        cause: cause,
        explication: explication,
        servieDepuisStockage: servieDepuisStockage,
      );

  /// `true` si un verdict officiel a pu être rendu.
  bool get estDeterminee => verdict != null;

  /// `true` si la résolution est non déterminée. Aucun montant n'est lisible.
  bool get estNonDeterminee => verdict == null;

  /// `true` si le moteur a établi un GAIN.
  ///
  /// ⚠️ Une résolution non déterminée rend `false` ici, comme une perte. Les
  ///    appelants NE DOIVENT PAS s'en servir pour compter : ils doivent
  ///    tester [estDeterminee] d'abord. C'est la raison pour laquelle
  ///    [estPerdant] existe séparément.
  bool get estGagnant => verdict?.estGagne ?? false;

  /// `true` si le moteur a établi une PERTE (démontrée, pas supposée).
  bool get estPerdant => verdict?.etat.name == 'perdu';

  /// ★ CORRECTION BLOC 1 (validation financière) — LE QUATRIÈME ÉTAT.
  ///
  /// DÉFAUT MESURÉ PAR LECTURE DE `moteur_gain_pmu.dart` :
  ///   • `EtatGain` possède QUATRE valeurs : `nonDetermine`, `attribue`,
  ///     `perdu`, `rembourse` (gain_pmu_types.dart:88-99) ;
  ///   • `VerdictGain.estGagne` vaut `etat == EtatGain.attribue` (:540),
  ///     donc un verdict `rembourse` rend `estGagne == false` ;
  ///   • `estPerdant` ci-dessus vaut `etat.name == 'perdu'`, donc `false`
  ///     pour un `rembourse`, mais tout appelant qui raisonnait en binaire
  ///     (`estGagne ? gagné : perdu`) classait un REMBOURSEMENT INTÉGRAL en
  ///     PERTE. En Martingale, cela doublait la mise alors que le joueur
  ///     n'avait rien perdu : c'est précisément ce que le mandat interdit.
  ///
  /// Un remboursement n'est NI un gain NI une perte : c'est un état propre,
  /// qu'aucun consommateur ne doit confondre avec l'un ou l'autre.
  bool get estRembourse => verdict?.etat.name == 'rembourse';

  /// `true` dès qu'un montant est établi (gain, perte établie ou remboursement).
  ///
  /// C'est LE test à utiliser avant toute agrégation financière : il exclut
  /// uniquement `nonDetermine`, et laisse le détail à [estGagnant] /
  /// [estPerdant] / [estRembourse].
  bool get estResolue => estDeterminee;

  /// Montant reversé au joueur (gains + remboursements), en euros.
  /// `null` si non déterminé — JAMAIS 0.0.
  double? get montantReverse => verdict?.montantReverse;

  /// Gain brut (hors remboursements), en euros. `null` si non déterminé.
  double? get gain => verdict?.total;

  /// Remboursements, en euros. `null` si non déterminé.
  double? get remboursement => verdict?.remboursement;

  @override
  String toString() => estDeterminee
      ? 'ResolutionFinanciere(${verdict!.etat.name} '
          '| reverse=${montantReverse!.toStringAsFixed(2)} € '
          '| stockage=$servieDepuisStockage)'
      : 'ResolutionFinanciere(nonDetermine / ${cause!.name} '
          '| $explication)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  2. RÉCUPÉRATION OFFICIELLE MAÎTRISÉE
// ═══════════════════════════════════════════════════════════════════════════

/// Obtient le résultat officiel d'une course, en privilégiant le stockage.
///
/// Ordre STRICT des tentatives :
///   ① entrée persistée et EXPLOITABLE → rendue telle quelle, ZÉRO réseau ;
///   ② entrée persistée mais incomplète ET `autoriserReseau` → une seule
///      tentative réseau, puis ENRICHISSEMENT de l'entrée existante (jamais
///      écrasement d'une arrivée divergente : le repository signale le
///      conflit) ;
///   ③ rien en stockage ET `autoriserReseau` → une tentative réseau, puis
///      persistance si le résultat est exploitable ;
///   ④ sinon → `null`, avec la cause.
///
/// Ce que cette fonction ne fait pas : elle ne boucle pas, ne réessaie pas,
/// ne planifie aucun rafraîchissement en arrière-plan. Un appel = au plus un
/// échange réseau. C'est ce qui interdit les « requêtes répétitives inutiles »
/// du point 4.
Future<RecuperationOfficielle> obtenirResultatOfficiel({
  required IdentiteCoursePmu identite,
  bool autoriserReseau = false,
}) async {
  if (!identite.estValide) {
    return RecuperationOfficielle.absente(
      CauseNonDetermination.identiteIndeterminable,
      'identité de course invalide : date, réunion et course sont requises',
    );
  }

  final repo = ResultatOfficielRepository.instance;
  await repo.charger();

  final locale = repo.entreePourIdentite(identite);
  if (locale != null && locale.estExploitable) {
    return RecuperationOfficielle.disponible(
      _versResultatOfficiel(locale),
      servieDepuisStockage: true,
    );
  }

  if (!autoriserReseau) {
    return RecuperationOfficielle.absente(
      locale == null
          ? CauseNonDetermination.resultatAbsentSansRecuperation
          : CauseNonDetermination.rapportsAbsents,
      locale == null
          ? 'aucun résultat officiel conservé pour ${identite.courseKey} '
              'et récupération réseau non autorisée'
          : 'résultat conservé pour ${identite.courseKey} mais incomplet '
              '(rapports ou arrivée manquants) et récupération non autorisée',
      servieDepuisStockage: locale != null,
    );
  }

  // ── Une seule tentative réseau ─────────────────────────────────────────
  ResultatOfficielCourse? reseau;
  try {
    reseau = await chargerResultatOfficielCourse(
      date: identite.date,
      numReunion: identite.numReunion,
      numCourse: identite.numCourse,
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[ChaineFinanciere] récupération ${identite.courseKey}: $e');
    }
    reseau = null;
  }

  if (reseau == null) {
    return RecuperationOfficielle.absente(
      CauseNonDetermination.resultatIndisponible,
      'le PMU n\'a rendu aucun résultat exploitable pour '
      '${identite.courseKey} (course non réglée, HTTP, timeout ou réseau)',
      servieDepuisStockage: locale != null,
    );
  }

  // ── Persistance : on ne jette PAS ce qui vient d'être récupéré ──────────
  final entree = EntreeResultatOfficiel(
    identite: identite,
    arriveeGroupes: reseau.arriveeGroupes,
    arriveeDefinitive: reseau.arriveeDefinitive,
    rapports: List<RapportPmu>.unmodifiable(reseau.rapports),
    statutsPartants: reseau.statutsPartants,
    dateRecuperation: DateTime.now(),
  );
  final ecriture = await repo.enregistrer(entree: entree);
  if (kDebugMode) {
    debugPrint('[ChaineFinanciere] ${identite.courseKey} → $ecriture');
  }

  // ⚠️ On rend le résultat RÉSEAU même si l'écriture a échoué : une panne de
  //    stockage ne doit pas priver d'un fait officiel déjà obtenu. L'échec est
  //    signalé par `ecriture`, jamais masqué.
  if (reseau.rapports.isEmpty || !reseau.aDesGroupes) {
    return RecuperationOfficielle.absente(
      reseau.rapports.isEmpty
          ? CauseNonDetermination.rapportsAbsents
          : CauseNonDetermination.arriveeAbsente,
      'résultat récupéré pour ${identite.courseKey} mais '
      '${reseau.rapports.isEmpty ? "sans rapport officiel" : "sans arrivée exploitable"}',
      servieDepuisStockage: false,
      statutEcriture: ecriture.statut,
    );
  }

  return RecuperationOfficielle.disponible(
    reseau,
    servieDepuisStockage: false,
    statutEcriture: ecriture.statut,
  );
}

/// Traduit une entrée persistée vers le contrat de la chaîne officielle.
///
/// Conversion PURE : aucun champ n'est complété. `null` reste `null`, donc le
/// moteur prononcera ses motifs fermés au lieu de recevoir une valeur inventée.
ResultatOfficielCourse _versResultatOfficiel(EntreeResultatOfficiel e) =>
    ResultatOfficielCourse(
      arriveeGroupes: e.arriveeGroupes,
      arriveeDefinitive: e.arriveeDefinitive,
      rapports: List<RapportPmu>.unmodifiable(e.rapports),
      statutsPartants: e.statutsPartants,
    );

/// Résultat d'une demande de récupération : soit une donnée, soit une cause.
class RecuperationOfficielle {
  /// Donnée officielle, `null` si absente.
  final ResultatOfficielCourse? resultat;

  /// Cause de l'absence, `null` si présente.
  final CauseNonDetermination? cause;

  /// Explication lisible.
  final String explication;

  /// `true` si la donnée a été servie depuis le stockage (aucun réseau).
  final bool servieDepuisStockage;

  /// Ce que le repository a répondu à l'écriture de rafraîchissement, quand
  /// une écriture a eu lieu. `null` si aucune écriture n'a été tentée.
  final StatutEcritureResultat? statutEcriture;

  const RecuperationOfficielle._({
    required this.resultat,
    required this.cause,
    required this.explication,
    required this.servieDepuisStockage,
    this.statutEcriture,
  });

  factory RecuperationOfficielle.disponible(
    ResultatOfficielCourse resultat, {
    required bool servieDepuisStockage,
    StatutEcritureResultat? statutEcriture,
  }) =>
      RecuperationOfficielle._(
        resultat: resultat,
        cause: null,
        explication: 'résultat officiel disponible',
        servieDepuisStockage: servieDepuisStockage,
        statutEcriture: statutEcriture,
      );

  factory RecuperationOfficielle.absente(
    CauseNonDetermination cause,
    String explication, {
    bool servieDepuisStockage = false,
    StatutEcritureResultat? statutEcriture,
  }) =>
      RecuperationOfficielle._(
        resultat: null,
        cause: cause,
        explication: explication,
        servieDepuisStockage: servieDepuisStockage,
        statutEcriture: statutEcriture,
      );

  bool get estDisponible => resultat != null;
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. RÉSOLUTION D'UN PARI — sans effet de bord, par construction
// ═══════════════════════════════════════════════════════════════════════════

/// Résout le gain d'un pari SIMULÉ contre les rapports officiels.
///
/// **SANS EFFET DE BORD.** Cette fonction :
///   • ne crée aucun ticket, n'écrit dans aucune prédiction ;
///   • n'appelle aucun enregistreur de verdict ;
///   • ne déclenche aucune notification de gain tardif ;
///   • n'appelle aucun service d'apprentissage.
///
/// Elle est donc utilisable sans risque par le backtesting, la Martingale, le
/// Best Bet post-course, le ROI et — au BLOC 2 — le Laboratoire IA.
///
/// [mise] est la mise d'un ticket à UNE composante. Les mises Gagnant+Placé
/// passent par [resoudrePariGagnantPlace], qui refuse une mise fusionnée.
Future<ResolutionFinanciere> resoudrePariSimule({
  required IdentiteCoursePmu identite,
  required String libelleTypePari,
  required List<int> numerosJoues,
  required double mise,
  bool autoriserReseau = false,
}) async {
  return _resoudre(
    identite: identite,
    libelleTypePari: libelleTypePari,
    numerosJoues: numerosJoues,
    autoriserReseau: autoriserReseau,
    construireTicket: () {
      if (!(mise > 0)) {
        return ResultatConstructionTicket.refus(
          'mise nulle ou négative : aucun gain ne peut être fondé dessus',
        );
      }
      if (numerosJoues.isEmpty) {
        return ResultatConstructionTicket.refus(
          'aucun numéro joué',
        );
      }
      return ResultatConstructionTicket.ok(
        TicketAGainResoudre.ticketSimple(
          libelleTypePari: libelleTypePari,
          numerosJoues: numerosJoues,
          mise: mise,
        ),
      );
    },
  );
}

/// Variante Gagnant+Placé : DEUX mises distinctes, jamais une mise agrégée.
///
/// Le moteur refuse explicitement une mise fusionnée pour ce pari
/// (`MotifRefusPmu.ticketDeuxComposantes`) : une mise unique ne permet pas de
/// savoir quelle part revient au Gagnant et quelle part au Placé. Les deux
/// mises sont donc exigées, et chacune doit être strictement positive.
Future<ResolutionFinanciere> resoudrePariGagnantPlace({
  required IdentiteCoursePmu identite,
  required String libelleTypePari,
  required List<int> numerosJoues,
  required double miseGagnant,
  required double misePlace,
  bool autoriserReseau = false,
}) async {
  return _resoudre(
    identite: identite,
    libelleTypePari: libelleTypePari,
    numerosJoues: numerosJoues,
    autoriserReseau: autoriserReseau,
    construireTicket: () {
      if (!(miseGagnant > 0) || !(misePlace > 0)) {
        return ResultatConstructionTicket.refus(
          'Gagnant+Placé exige DEUX mises strictement positives : '
          'une mise agrégée ne permet pas de répartir le gain',
        );
      }
      return ResultatConstructionTicket.ok(
        TicketAGainResoudre.gagnantPlace(
          libelleTypePari: libelleTypePari,
          numerosJoues: numerosJoues,
          miseGagnant: miseGagnant,
          misePlace: misePlace,
        ),
      );
    },
  );
}

/// Squellette commune : récupérer, puis résoudre. Aucune règle financière.
Future<ResolutionFinanciere> _resoudre({
  required IdentiteCoursePmu identite,
  required String libelleTypePari,
  required List<int> numerosJoues,
  required bool autoriserReseau,
  required ResultatConstructionTicket Function() construireTicket,
}) async {
  final ticket = construireTicket();
  if (!ticket.estExploitable) {
    return ResolutionFinanciere.nonDeterminee(
      cause: CauseNonDetermination.ticketNonConstructible,
      explication: ticket.motif!,
    );
  }

  final recup = await obtenirResultatOfficiel(
    identite: identite,
    autoriserReseau: autoriserReseau,
  );
  if (!recup.estDisponible) {
    return ResolutionFinanciere.nonDeterminee(
      cause: recup.cause!,
      explication: recup.explication,
      servieDepuisStockage: recup.servieDepuisStockage,
    );
  }
  final resultat = recup.resultat!;

  // Le moteur officiel rend toujours un verdict (jamais `null`). Si ce verdict
  // est lui-même « non déterminé », son motif FERMÉ est conservé : la
  // résolution reste non déterminée, mais la CAUSE est celle du moteur, ce qui
  // est plus précis que la nôtre.
  final verdict = resoudreGainTicketDepuisDonnees(
    ticket: ticket.ticket!,
    resultat: resultat,
  );

  if (verdict.estNonDetermine) {
    return ResolutionFinanciere.nonDeterminee(
      cause: CauseNonDetermination.rapportsAbsents,
      explication: 'moteur officiel : ${verdict.motif?.name} — '
          '${verdict.explication}',
      servieDepuisStockage: recup.servieDepuisStockage,
    );
  }

  return ResolutionFinanciere.determinee(
    verdict: verdict,
    servieDepuisStockage: recup.servieDepuisStockage,
  );
}

/// Résultat d'une tentative de construction de ticket. Refus motivé ou ticket.
class ResultatConstructionTicket {
  final TicketAGainResoudre? ticket;
  final String? motif;

  const ResultatConstructionTicket.ok(TicketAGainResoudre this.ticket)
      : motif = null;

  const ResultatConstructionTicket.refus(this.motif) : ticket = null;

  bool get estExploitable => ticket != null;
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. MISE ENGAGÉE D'UN PARI SIMULÉ — un seul endroit
// ═══════════════════════════════════════════════════════════════════════════

/// Rend la [MiseEngagee] d'un pari simulé à une composante.
///
/// Exposé parce que les outils de simulation ont besoin de connaître la mise
/// TOTALE réellement engagée (pour un ROI, par exemple) sans la recalculer
/// chacun de leur côté — ce serait un second moteur financier.
MiseEngagee miseEngageeSimple(double mise) => MiseEngagee(miseSimple: mise);

/// Rend la [MiseEngagee] d'un Gagnant+Placé simulé.
MiseEngagee miseEngageeGagnantPlace({
  required double miseGagnant,
  required double misePlace,
}) =>
    MiseEngagee(miseGagnant: miseGagnant, misePlace: misePlace);
