// ═══════════════════════════════════════════════════════════════════════════
//  BRANCHEMENT DU VERDICT OFFICIEL — LOT B-4.5
// ═══════════════════════════════════════════════════════════════════════════
//
//  Ce fichier est la COUTURE entre les tickets persistés et la chaîne de
//  décision B-3 / B-4.1 / B-4.3 / B-4.4. Il ne contient AUCUNE règle
//  financière : il ne calcule aucun montant, n'arbitre aucune variante et ne
//  sélectionne aucun rapport. Il ne fait que :
//
//    1. NORMALISER une date de ticket, en refusant tout ce qui n'est pas une
//       date calendaire réelle (`dateCourseDepuisDateStr`) ;
//    2. CHARGER le résultat officiel de la course par son identité exacte
//       (`numReunion`, `numCourse`, date) — sans aucun rapprochement entre
//       deux tickets (`chargerResultatOfficielCourse`) ;
//    3. CONSTRUIRE le `TicketAGainResoudre` de B-4.1 avec les numéros, l'ordre
//       RÉELLEMENT joué et les mises réellement engagées
//       (`construireTicketPrediction`, `construireTicketSuivi`) ;
//    4. REFUSER explicitement toute capture incomplète, sans jamais compléter
//       un numéro, un ordre ni une mise (`IssueConstructionTicket`) ;
//    5. APPLIQUER le verdict via les enregistreurs B-4.3 et B-4.4, qui restent
//       seuls juges de la politique d'écriture.
//
//  ⚠️ CE FICHIER N'EST PAS UN MOTEUR. Preuve par construction : il n'appelle
//     ni `RapportAttribue.calculer`, ni `totalDesMontantsRetour`, ni
//     `reduce(`, ni `sort(` sur des rapports. Aucun montant n'y est produit.
//     Tous les montants viennent du `VerdictGain` du moteur B-3.
//
//  ⚠️ AUCUN APPEL À L'APPRENTISSAGE IA. Ce fichier n'importe pas
//     `ia_memory_service.dart` et n'appelle ni `mettreAJourStatsTypes`, ni
//     `_syncStatsTypesIA`. Le branchement ne modifie donc aucune statistique
//     d'apprentissage : la propagation indirecte existante
//     (`PmuProvider.enregistrerDividendePmu` → `_syncStatsTypesIA`) reste le
//     SEUL chemin de synchronisation IA et n'est pas emprunté ici.
//
//  ⚠️ L'IDENTITÉ ENTRE `UserPrediction` ET `TrackedCourse` N'EST PAS REQUISE.
//     Chaque ticket est résolu avec ses propres données : deux paris sur la
//     même course reçoivent la MÊME arrivée officielle (c'est une propriété de
//     la course) mais chacune de leurs propres mises, numéros et ordre. Aucun
//     `firstWhere`, aucun appariement, aucune propagation.
// ═══════════════════════════════════════════════════════════════════════════

import '../models/pmu_models.dart';
import 'alert_service.dart';
import 'enregistreur_verdict_gain_pmu.dart';
import 'enregistreur_verdict_gain_suivi.dart';
import 'gain_calculator.dart' show RapportPmu;
import 'gain_pmu_types.dart';
import 'gain_ticket_calculator.dart' show TypePariJoue, tailleCombinaisonAttendue, typePariDepuisLibelle;
import 'moteur_gain_pmu.dart';
import 'pmu_api_service.dart';
import 'referentiel_paris_pmu.dart';
import 'resolution_gain_ticket_pmu.dart';
import 'zone_turf_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  1. NORMALISATION STRICTE DE LA DATE
// ═══════════════════════════════════════════════════════════════════════════

/// Traduit la date d'un ticket en [DateTime], ou `null` si elle n'est pas une
/// date calendaire RÉELLE.
///
/// MESURE, ET RAISON D'ÊTRE : les tickets ne portent pas tous la même forme.
///   • `bet_bottom_sheet.dart` écrit `'${year}-${mm}-${dd}'` → `2026-11-22` ;
///   • l'ancien `race_detail_screen.dart` écrivait `provider.dateStr` (format
///     PMU) → `22112026` — ce fichier est **supprimé en BL1-A18** (mesuré :
///     0 instanciation externe), mais des tickets AINSI DATÉS existent déjà
///     chez l'utilisateur : la compatibilité de lecture reste nécessaire.
///
/// Or `ZoneTurfService` et `PmuApiService` attendent **`ddmmyyyy` sur huit
/// caractères**. Un ticket créé par `bet_bottom_sheet` transmettait donc une
/// date inutilisable au chemin automatique de récupération des dividendes.
///
/// Deux formes sont acceptées, et deux seulement. Tout le reste rend `null` :
/// aucune date « du jour » n'est substituée, aucun zérage n'est tenté.
///
/// La validité calendaire est vérifiée par RELECTURE : une date construite par
/// [DateTime] normalise silencieusement les débordements (`2026-02-31` devient
/// le 3 mars), donc on ne fait confiance au constructeur que si les trois
/// composantes relues sont identiques aux trois composantes demandées.
DateTime? dateCourseDepuisDateStr(String? dateStr) {
  if (dateStr == null) return null;
  final s = dateStr.trim();
  if (s.isEmpty) return null;

  int? jour;
  int? mois;
  int? annee;

  if (s.length == 8 && _estEntierementNumerique(s)) {
    // ddmmyyyy
    jour = int.tryParse(s.substring(0, 2));
    mois = int.tryParse(s.substring(2, 4));
    annee = int.tryParse(s.substring(4, 8));
  } else if (s.length == 10 && s[4] == '-' && s[7] == '-') {
    // yyyy-MM-dd
    annee = int.tryParse(s.substring(0, 4));
    mois = int.tryParse(s.substring(5, 7));
    jour = int.tryParse(s.substring(8, 10));
  } else {
    return null;
  }

  if (jour == null || mois == null || annee == null) return null;
  if (annee < 1900 || annee > 2200) return null;
  if (mois < 1 || mois > 12) return null;
  if (jour < 1 || jour > 31) return null;

  final construit = DateTime(annee, mois, jour);
  // Relecture : toute composante réécrite par le constructeur = date inventée.
  if (construit.year != annee ||
      construit.month != mois ||
      construit.day != jour) {
    return null;
  }
  return construit;
}

bool _estEntierementNumerique(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return false;
  }
  return true;
}

/// Forme `ddmmyyyy` exigée par `ZoneTurfService` et `PmuApiService`.
String dateApiDepuisDateTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

// ═══════════════════════════════════════════════════════════════════════════
//  2. RÉSULTAT OFFICIEL DE LA COURSE — par identité exacte
// ═══════════════════════════════════════════════════════════════════════════

/// Assemble le [ResultatOfficielCourse] attendu par B-4.1.
///
/// PURE : elle ne fait que transporter. Les groupes d'arrivée sont transmis
/// TELS QUELS — `null` reste `null` (le moteur prononcera
/// `deadHeatSansGroupes`), et aucun groupe n'est déduit de la liste plate.
/// `arriveeDefinitive` `null` signifie « l'API est muette » : ce silence n'est
/// jamais traduit en « définitif ».
ResultatOfficielCourse construireResultatOfficiel({
  required List<List<int>>? arriveeGroupes,
  required bool? arriveeDefinitive,
  required List<RapportPmu> rapports,
  Map<int, String>? statutsPartants,
}) =>
    ResultatOfficielCourse(
      arriveeGroupes: arriveeGroupes,
      arriveeDefinitive: arriveeDefinitive,
      rapports: List<RapportPmu>.unmodifiable(rapports),
      // ★ CHANTIER 1/3 : statuts officiels transmis TELS QUELS. `null` reste
      //   `null` — l'information est indisponible, et le moteur ne prononcera
      //   aucune perte fondée sur une absence de rapport. Aucune table n'est
      //   fabriquée ici : ce serait inventer une participation.
      statutsPartants: statutsPartants,
    );

/// Charge le résultat officiel de LA course désignée par `numReunion`,
/// `numCourse` et `date`.
///
/// L'identité est portée par l'URL elle-même (mesuré : `ZoneTurfService`
/// compose `/programme/$dateStr/R$rPad/C$cPad/participants`,
/// `PmuApiService` compose `/programme/$date/R$numR/C$numC/rapports-definitifs`).
/// Aucun rapprochement n'est fait sur le contenu : la réponse *est* celle de
/// cette course.
///
/// Rend `null` — et non un résultat vide — dans TROIS cas, pour que l'appelant
/// puisse refuser explicitement sans jamais calculer sur des données absentes :
///   • l'arrivée n'a pas pu être chargée (HTTP ≠ 200, timeout, réseau) ;
///   • aucun rapport n'a été publié (course non réglée) ;
///   • la date fournie est invalide (impossible ici : `date` est un [DateTime]).
Future<ResultatOfficielCourse?> chargerResultatOfficielCourse({
  required DateTime date,
  required int numReunion,
  required int numCourse,
}) async {
  final dateApi = dateApiDepuisDateTime(date);

  final resultat = await ZoneTurfService.chargerResultatsCourseComplet(
    heureDepart: date,
    numReunion: numReunion,
    numCourse: numCourse,
  );
  if (resultat == null) return null;

  final rapports = await PmuApiService.fetchRapportsDefinitifs(
      dateApi, numReunion, numCourse);
  if (rapports.isEmpty) return null;

  return construireResultatOfficiel(
    arriveeGroupes: resultat.arriveeGroupes,
    arriveeDefinitive: resultat.arriveeDefinitive,
    rapports: rapports,
    // ★ CHANTIER 1/3 : MÊME réponse réseau que l'arrivée
    //   (`ZoneTurfService.chargerResultatsCourseComplet`), donc la
    //   correspondance avec CETTE course est portée par l'URL, sans
    //   rapprochement de contenu. C'est la source PRIORITAIRE retenue par
    //   l'arbitrage. Rien n'est re-téléchargé : aucune nouvelle chaîne.
    statutsPartants: resultat.statutsPartants,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. CONSTRUCTION DU TICKET POUR B-4.1 — refus explicites
// ═══════════════════════════════════════════════════════════════════════════

/// Raison fermée d'un refus de construction. Aucun de ces cas ne produit un
/// ticket « partiel » : ils produisent un refus, et le ticket reste non résolu.
enum IssueConstructionTicket {
  /// Le libellé `typePari` n'est pas répertorié : aucun calcul n'est mené.
  typeNonRepertorie,

  /// Aucun code PMU exploitable (`codePmuOfficiel` absent ou vide).
  codePmuAbsent,

  /// Le nombre de numéros joués ne correspond pas à la taille réglementaire.
  tailleCombinaisonAnormale,

  /// Le libellé impose une variante et aucune n'a été réellement choisie.
  varianteAbsente,

  /// Le libellé impose l'ordre à la saisie et l'ordre joué n'est pas conservé.
  ordreAbsent,

  /// L'ordre conservé ne désigne pas exactement les mêmes chevaux.
  ordreIncoherent,

  /// Aucune mise strictement positive n'est engagée.
  miseAbsente,

  /// Gagnant+Placé dont une seule des deux mises est renseignée.
  miseIncomplete,
}

/// Résultat d'une tentative de construction : soit un ticket exploitable, soit
/// un refus motivé. Jamais les deux, jamais aucun.
class ConstructionTicket {
  final TicketAGainResoudre? ticket;
  final IssueConstructionTicket? issue;

  const ConstructionTicket._({this.ticket, this.issue});

  factory ConstructionTicket.ok(TicketAGainResoudre t) =>
      ConstructionTicket._(ticket: t);

  factory ConstructionTicket.refus(IssueConstructionTicket issue) =>
      ConstructionTicket._(issue: issue);

  bool get estExploitable => ticket != null;
}

bool _memeEnsemble(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  final sa = a.toSet();
  final sb = b.toSet();
  return sa.length == sb.length && sa.containsAll(sb);
}

/// Vrai si le libellé porte une variante que le parieur DOIT avoir choisie.
/// Miroir exact de `capturePariComplete` (pmu_models.dart:633) : ces trois
/// libellés ne sont pas produits par `bet_bottom_sheet`, et aucun chemin de
/// production ne renseigne `varianteChoisie`. Les tickets qui les portent sont
/// donc refusés, ce qui est l'état honnête : on ne devine pas la variante.
bool _exigeVariante(String typePari) =>
    typePari == 'Tiercé Ordre' ||
    typePari == 'Tiercé Désordre' ||
    typePari == 'Couplé Ordre';

/// Applique la seule règle d'ordre autorisée : si le libellé impose l'ordre à
/// la SAISIE, le ticket n'est exploitable QUE si `numerosDansOrdre` est présent
/// et désigne exactement les mêmes chevaux.
///
/// ⚠️ AUCUN REPLI sur `numerosJoues`. C'est le cœur de la décision n°3 : une
///    liste triée ne peut pas fonder un calcul Ordre/Désordre.
///
/// L'autorité interrogée est `exigeOrdreExactSaisie` du référentiel — la même
/// que `bet_bottom_sheet` utilise pour décider de capturer l'ordre. Aucune
/// liste de types n'est recopiée ici.
List<int>? _numerosDansOrdreReel({
  required String typePari,
  required TypePariJoue type,
  required List<int> numerosJoues,
  required List<int>? numerosDansOrdre,
}) {
  final typePmu = typePmuDepuisLibelleHistorique(typePari);
  if (typePmu == null) {
    // Type applicatif hors référentiel PMU : il n'impose aucun ordre.
    return numerosJoues;
  }
  final exige = exigeOrdreExactSaisie(typePmu);
  if (exige == null) {
    // Le référentiel déclare la question NON RÉSOLUE (Multi / Mini Multi).
    // On ne tranche pas : pas d'ordre exigé, donc la liste jouée est utilisée
    // telle quelle — et ces libellés ne sont pas produits par l'application.
    return numerosJoues;
  }
  if (!exige) return numerosJoues;

  if (numerosDansOrdre == null) return null;
  if (numerosDansOrdre.length != numerosJoues.length) return null;
  if (!_memeEnsemble(numerosDansOrdre, numerosJoues)) return null;
  return List<int>.unmodifiable(numerosDansOrdre);
}

/// Construit le ticket B-4.1 d'un `UserPrediction`.
///
/// N'ÉCRIT RIEN et ne modifie pas la prédiction. Toute donnée absente produit
/// un refus motivé, jamais un complément inventé.
ConstructionTicket construireTicketPrediction(UserPrediction p) {
  final type = typePariDepuisLibelle(p.typePari);
  if (type == TypePariJoue.inconnu) {
    return ConstructionTicket.refus(IssueConstructionTicket.typeNonRepertorie);
  }

  // ── 1. Numéros : taille réglementaire exacte ──────────────────────────────
  if (p.numerosJoues.isEmpty) {
    return ConstructionTicket.refus(
        IssueConstructionTicket.tailleCombinaisonAnormale);
  }
  final attendu = tailleCombinaisonAttendue(type);
  if (attendu == null || p.numerosJoues.length != attendu) {
    return ConstructionTicket.refus(
        IssueConstructionTicket.tailleCombinaisonAnormale);
  }

  // ── 2. Gagnant+Placé : DEUX mises distinctes, jamais une mise agrégée ────
  if (type == TypePariJoue.gagnantPlace) {
    final g = p.miseGagnant;
    final pl = p.misePlace;
    if (g == null || pl == null) {
      return ConstructionTicket.refus(IssueConstructionTicket.miseIncomplete);
    }
    if (!(g > 0) || !(pl > 0)) {
      return ConstructionTicket.refus(IssueConstructionTicket.miseIncomplete);
    }
    final numeros = _numerosDansOrdreReel(
      typePari: p.typePari,
      type: type,
      numerosJoues: p.numerosJoues,
      numerosDansOrdre: p.numerosDansOrdre,
    );
    if (numeros == null) {
      return ConstructionTicket.refus(IssueConstructionTicket.ordreIncoherent);
    }
    return ConstructionTicket.ok(TicketAGainResoudre.gagnantPlace(
      libelleTypePari: p.typePari,
      numerosJoues: numeros,
      miseGagnant: g,
      misePlace: pl,
    ));
  }

  // ── 3. Mise réellement engagée, strictement positive ─────────────────────
  if (!(p.montantMise > 0)) {
    return ConstructionTicket.refus(IssueConstructionTicket.miseAbsente);
  }

  // ── 4. Code PMU du pari réellement joué ──────────────────────────────────
  final code = p.codePmuOfficiel;
  if (code == null || code.trim().isEmpty) {
    return ConstructionTicket.refus(IssueConstructionTicket.codePmuAbsent);
  }

  // ── 5. Variante réellement choisie quand le libellé l'impose ─────────────
  if (_exigeVariante(p.typePari) && p.varianteChoisie == null) {
    return ConstructionTicket.refus(IssueConstructionTicket.varianteAbsente);
  }

  // ── 6. Ordre réellement joué, sans aucun repli sur la liste triée ────────
  final typePmu = typePmuDepuisLibelleHistorique(p.typePari);
  final exigeOrdre = typePmu == null ? false : exigeOrdreExactSaisie(typePmu);
  final numeros = _numerosDansOrdreReel(
    typePari: p.typePari,
    type: type,
    numerosJoues: p.numerosJoues,
    numerosDansOrdre: p.numerosDansOrdre,
  );
  if (numeros == null) {
    // Distingue « ordre absent » de « ordre incohérent » pour l'audit.
    return ConstructionTicket.refus(exigeOrdre == true && p.numerosDansOrdre == null
        ? IssueConstructionTicket.ordreAbsent
        : IssueConstructionTicket.ordreIncoherent);
  }

  return ConstructionTicket.ok(TicketAGainResoudre.ticketSimple(
    libelleTypePari: p.typePari,
    numerosJoues: numeros,
    mise: p.montantMise,
  ));
}

/// Construit le ticket B-4.1 d'un `TrackedCourse`.
///
/// MÊME politique que [construireTicketPrediction], appliquée au modèle suivi.
/// Les mises viennent de `miseEngagee` / `miseGagnant` / `misePlace` — jamais
/// de `miseTotaleEngagee`, qui est une donnée de bilan et non un opérande.
ConstructionTicket construireTicketSuivi(TrackedCourse c) {
  final type = typePariDepuisLibelle(c.typePari);
  if (type == TypePariJoue.inconnu) {
    return ConstructionTicket.refus(IssueConstructionTicket.typeNonRepertorie);
  }

  if (c.numerosJoues.isEmpty) {
    return ConstructionTicket.refus(
        IssueConstructionTicket.tailleCombinaisonAnormale);
  }
  final attendu = tailleCombinaisonAttendue(type);
  if (attendu == null || c.numerosJoues.length != attendu) {
    return ConstructionTicket.refus(
        IssueConstructionTicket.tailleCombinaisonAnormale);
  }

  if (type == TypePariJoue.gagnantPlace) {
    final g = c.miseGagnant;
    final pl = c.misePlace;
    if (g == null || pl == null) {
      return ConstructionTicket.refus(IssueConstructionTicket.miseIncomplete);
    }
    if (!(g > 0) || !(pl > 0)) {
      return ConstructionTicket.refus(IssueConstructionTicket.miseIncomplete);
    }
    final numeros = _numerosDansOrdreReel(
      typePari: c.typePari,
      type: type,
      numerosJoues: c.numerosJoues,
      numerosDansOrdre: c.numerosDansOrdre,
    );
    if (numeros == null) {
      return ConstructionTicket.refus(IssueConstructionTicket.ordreIncoherent);
    }
    return ConstructionTicket.ok(TicketAGainResoudre.gagnantPlace(
      libelleTypePari: c.typePari,
      numerosJoues: numeros,
      miseGagnant: g,
      misePlace: pl,
    ));
  }

  final mise = c.miseEngagee;
  if (mise == null || !(mise > 0)) {
    return ConstructionTicket.refus(IssueConstructionTicket.miseAbsente);
  }

  final code = c.codePmuOfficiel;
  if (code == null || code.trim().isEmpty) {
    return ConstructionTicket.refus(IssueConstructionTicket.codePmuAbsent);
  }

  if (_exigeVariante(c.typePari) && c.varianteChoisie == null) {
    return ConstructionTicket.refus(IssueConstructionTicket.varianteAbsente);
  }

  final typePmu = typePmuDepuisLibelleHistorique(c.typePari);
  final exigeOrdre = typePmu == null ? false : exigeOrdreExactSaisie(typePmu);
  final numeros = _numerosDansOrdreReel(
    typePari: c.typePari,
    type: type,
    numerosJoues: c.numerosJoues,
    numerosDansOrdre: c.numerosDansOrdre,
  );
  if (numeros == null) {
    return ConstructionTicket.refus(exigeOrdre == true && c.numerosDansOrdre == null
        ? IssueConstructionTicket.ordreAbsent
        : IssueConstructionTicket.ordreIncoherent);
  }

  return ConstructionTicket.ok(TicketAGainResoudre.ticketSimple(
    libelleTypePari: c.typePari,
    numerosJoues: numeros,
    mise: mise,
  ));
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. APPLICATION DU VERDICT — délégation totale aux enregistreurs
// ═══════════════════════════════════════════════════════════════════════════

/// Enregistre le verdict d'un `UserPrediction` via l'enregistreur B-4.3.
///
/// Ce n'est qu'un PASSAGE : la politique d'écriture (refus, idempotence,
/// protection du verdict définitif, refus de transition `nonDetermine →
/// définitif`) appartient entièrement à B-4.3 et n'est pas reproduite ici.
///
/// ⚠️ Ne touche NI `isGagne`, NI `dividendePmuReel`, NI `messageResultat`,
///    NI `isCorrect`, NI `gainRealise` : l'enregistreur ne les écrit pas, et
///    ce fichier ne les écrit pas non plus. Aucune synchronisation IA n'est
///    donc déclenchée (elle n'est déclenchée que par
///    `PmuProvider.enregistrerDividendePmu`, qui n'est pas appelé ici).
ResultatEnregistrementVerdict appliquerVerdictPrediction({
  required UserPrediction ticket,
  required VerdictGain verdict,
  required ResultatOfficielCourse resultat,
}) =>
    enregistrerVerdictGain(
      ticket: ticket,
      verdict: verdict,
      rapportsOfficiels: _rapportsPublies(resultat),
      miseBaseCentimesOfficielle:
          _miseBasePubliee(_rapportsPublies(resultat), ticket.codePmuOfficiel),
    );

/// Enregistre le verdict d'un `TrackedCourse` via l'enregistreur B-4.4.
///
/// MÊME délégation : toute la décision est dans B-4.4.
ResultatEnregistrementVerdictSuivi appliquerVerdictSuivi({
  required TrackedCourse ticket,
  required VerdictGain verdict,
  required ResultatOfficielCourse resultat,
}) =>
    enregistrerVerdictGainSuivi(
      ticket: ticket,
      verdict: verdict,
      rapportsOfficiels: _rapportsPublies(resultat),
      miseBaseCentimesOfficielle:
          _miseBasePubliee(_rapportsPublies(resultat), ticket.codePmuOfficiel),
    );

/// Convertit les rapports API en rapports publiés, en ÉCARTANT ceux dont la
/// variante est indéterminable (le convertisseur B-4.1 en est l'autorité).
List<RapportPublie> _rapportsPublies(ResultatOfficielCourse resultat) {
  final publies = <RapportPublie>[];
  for (final r in resultat.rapports) {
    final p = rapportPublieDepuisApi(r);
    if (p != null) publies.add(p);
  }
  return List<RapportPublie>.unmodifiable(publies);
}

/// `miseBase` du rapport officiel : celle PUBLIÉE par le bloc du code joué.
///
/// Aucune valeur de repli n'est inventée : si le bloc ne publie pas de
/// `miseBase`, ou si deux blocs du même code en publient des différentes, la
/// fonction rend `null` et l'enregistreur appliquera sa propre politique.
int? _miseBasePubliee(List<RapportPublie> rapports, String? codePmu) {
  if (codePmu == null || codePmu.isEmpty) return null;
  final valeurs = <int>{};
  for (final r in rapports) {
    if (r.codePmu != codePmu) continue;
    final mb = r.miseBaseCentimes;
    if (mb != null) valeurs.add(mb);
  }
  if (valeurs.length != 1) return null;
  return valeurs.first;
}

/// Chaîne complète pour un `UserPrediction` : construire → résoudre → décider.
///
/// PURE au sens où elle n'écrit rien sur disque : elle rend le résultat de
/// l'enregistreur, que l'appelant applique (`PmuProvider`). Si la construction
/// est refusée ou si le résultat officiel manque, elle rend un refus explicite
/// — jamais un verdict inventé.
class ResolutionTicketPrediction {
  final IssueConstructionTicket? issue;
  final VerdictGain? verdict;
  final ResultatEnregistrementVerdict? enregistrement;

  const ResolutionTicketPrediction._({
    this.issue,
    this.verdict,
    this.enregistrement,
  });

  factory ResolutionTicketPrediction.refus(IssueConstructionTicket issue) =>
      ResolutionTicketPrediction._(issue: issue);

  factory ResolutionTicketPrediction.resolu(
          VerdictGain verdict, ResultatEnregistrementVerdict enregistrement) =>
      ResolutionTicketPrediction._(
          verdict: verdict, enregistrement: enregistrement);

  bool get aUneIssue => issue != null;
}

ResolutionTicketPrediction resoudrePrediction({
  required UserPrediction prediction,
  required ResultatOfficielCourse resultat,
}) {
  final construit = construireTicketPrediction(prediction);
  if (!construit.estExploitable) {
    return ResolutionTicketPrediction.refus(construit.issue!);
  }
  final verdict =
      resoudreGainTicketDepuisDonnees(ticket: construit.ticket!, resultat: resultat);
  final enregistrement = appliquerVerdictPrediction(
    ticket: prediction,
    verdict: verdict,
    resultat: resultat,
  );
  return ResolutionTicketPrediction.resolu(verdict, enregistrement);
}

/// Chaîne complète pour un `TrackedCourse`.
class ResolutionTicketSuivi {
  final IssueConstructionTicket? issue;
  final VerdictGain? verdict;
  final ResultatEnregistrementVerdictSuivi? enregistrement;

  const ResolutionTicketSuivi._({
    this.issue,
    this.verdict,
    this.enregistrement,
  });

  factory ResolutionTicketSuivi.refus(IssueConstructionTicket issue) =>
      ResolutionTicketSuivi._(issue: issue);

  factory ResolutionTicketSuivi.resolu(
          VerdictGain verdict, ResultatEnregistrementVerdictSuivi enregistrement) =>
      ResolutionTicketSuivi._(
          verdict: verdict, enregistrement: enregistrement);

  bool get aUneIssue => issue != null;
}

ResolutionTicketSuivi resoudreSuivi({
  required TrackedCourse ticket,
  required ResultatOfficielCourse resultat,
}) {
  final construit = construireTicketSuivi(ticket);
  if (!construit.estExploitable) {
    return ResolutionTicketSuivi.refus(construit.issue!);
  }
  final verdict =
      resoudreGainTicketDepuisDonnees(ticket: construit.ticket!, resultat: resultat);
  final enregistrement = appliquerVerdictSuivi(
    ticket: ticket,
    verdict: verdict,
    resultat: resultat,
  );
  return ResolutionTicketSuivi.resolu(verdict, enregistrement);
}

// ═══════════════════════════════════════════════════════════════════════════
//  5. UNE COURSE ENTIÈRE — N tickets, MÊME arrivée, données PROPRES
// ═══════════════════════════════════════════════════════════════════════════
//
//  POURQUOI CETTE SECTION EXISTE (défaut mesuré, et sa correction)
//
//  Les deux écrans écrivaient le dividende d'UN SEUL pari par course :
//  `PmuProvider.getPredictionForCourse` est un `firstWhere`
//  (pmu_provider.dart:546) — il rend le PREMIER pari de la course et lui seul.
//  Sur une course où l'utilisateur a joué un Simple Gagnant ET un Tiercé, le
//  second pari n'était donc jamais résolu : ni son gain, ni sa perte.
//
//  La correction ne consiste PAS à choisir un pari « représentatif ». Chaque
//  ticket est résolu SÉPARÉMENT avec :
//    • la MÊME arrivée officielle (propriété de la course, partagée) ;
//    • SES PROPRES numéros, ordre, variante et mise (propriété du ticket).
//  Aucun `firstWhere`, aucun appariement entre deux paris, aucune propagation
//  d'un montant d'un pari vers un autre.
//
//  ⚠️ CES DEUX FONCTIONS N'ÉCRIVENT RIEN. Elles rendent des listes de
//     resolution ; l'application au stockage reste le geste de l'appelant.

/// Résolutions de TOUS les paris de profil d'une course, dans l'ordre de la
/// liste fournie. Un refus est rendu comme un refus — jamais écarté en silence.
List<ResolutionTicketPrediction> resoudrePredictionsDeCourse({
  required List<UserPrediction> predictions,
  required ResultatOfficielCourse resultat,
}) =>
    List<ResolutionTicketPrediction>.unmodifiable(<ResolutionTicketPrediction>[
      for (final p in predictions)
        resoudrePrediction(prediction: p, resultat: resultat),
    ]);

/// Même chose pour un ticket suivi. Le résultat officiel est celui de SA course.
ResolutionTicketSuivi resoudreSuiviDeCourse({
  required TrackedCourse ticket,
  required ResultatOfficielCourse resultat,
}) =>
    resoudreSuivi(ticket: ticket, resultat: resultat);

/// Résultat officiel reconstruit à partir de ce qu'un `TrackedCourse` porte
/// DÉJÀ en base, sans aucun accès réseau.
///
/// CE QUI EST UTILISÉ (mesuré, tous persistés) :
///   • `arriveeGroupes`  — groupes officiels EXACTS, `null` si l'API n'en a pas
///     fourni ; jamais déduits de `arriveeFinale` (qui est une liste plate) ;
///   • `arriveeDefinitive` — `null` = l'API est restée muette.
///
/// CE QUI DOIT ÊTRE FOURNI : les rapports. Le ticket suivi ne les persiste pas.
///
/// Rend `null` si les groupes d'arrivée sont absents : une liste plate ne peut
/// pas fonder un calcul d'ordre ni d'ex æquo, et le moteur prononcerait
/// `deadHeatSansGroupes` sur une donnée qu'on aurait pu charger. On refuse donc
/// explicitement de construire, plutôt que de produire un faux indéterminé.
ResultatOfficielCourse? resultatOfficielDepuisSuivi(
  TrackedCourse ticket, {
  required List<RapportPmu> rapports,
}) {
  if (ticket.arriveeGroupes == null) return null;
  if (rapports.isEmpty) return null;
  return construireResultatOfficiel(
    arriveeGroupes: ticket.arriveeGroupes,
    arriveeDefinitive: ticket.arriveeDefinitive,
    rapports: rapports,
  );
}
