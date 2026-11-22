// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-4.3 — ENREGISTREMENT SÉCURISÉ D'UN VERDICT B-3 SUR UN TICKET
//
//  ── CE QUE CE FICHIER FAIT, ET RIEN DE PLUS ───────────────────────────────
//  Il reçoit un [UserPrediction] et un [VerdictGain], décide si l'écriture
//  est PERMISE, et rend soit un ticket mis à jour, soit un refus motivé.
//
//  ── CE QU'IL NE FAIT JAMAIS ──────────────────────────────────────────────
//  • il n'appelle PAS le moteur B-3 (`resoudreGainTicket`) : le verdict est
//    une ENTRÉE, jamais un calcul. `grep resoudreGainTicket` dans ce fichier
//    ne doit rien trouver hors commentaire ;
//  • il ne sélectionne AUCUN rapport par son montant : la correspondance se
//    fait par IDENTITÉ (code + libellé + variante + combinaison + pourUnEuro) ;
//  • il n'écrit rien sur disque, n'appelle aucun provider, aucun écran ;
//  • il ne modifie pas l'objet reçu (tout passe par `copyWith`) ;
//  • il ne touche ni `isGagne`, ni la persistance, ni les écrans.
//
//  ── LA RÈGLE FONDAMENTALE (consigne utilisateur, verbatim) ────────────────
//  « Le rapport affiché et le "Gain gagné" doivent obligatoirement
//    correspondre au pari réellement joué et au résultat officiel. Il ne faut
//    jamais sélectionner automatiquement le dividende le plus élevé. »
//
//  C'est pourquoi ce fichier REFUSE plutôt que d'approximer : dès qu'un
//  rapport attribué ne peut pas être relié à un rapport officiel réel, ou que
//  la somme des montants ne retombe pas exactement sur `verdict.total`,
//  l'enregistrement est refusé et le ticket reste intact.
// ═══════════════════════════════════════════════════════════════════════════

import '../models/pmu_models.dart';
import 'gain_pmu_types.dart';
import 'moteur_gain_pmu.dart';

/// Statut d'une tentative d'enregistrement de verdict.
///
/// Chaque valeur nomme un cas DISTINCT : aucun « presque enregistré ».
enum StatutEnregistrementVerdict {
  /// Le ticket n'avait aucun verdict : il a été écrit.
  enregistre,

  /// Le ticket portait déjà EXACTEMENT ce verdict : rien n'a changé.
  ///
  /// Le ticket rendu est alors l'original, non copié : une écriture inutile
  /// n'a pas eu lieu.
  dejaIdentique,

  /// Le ticket portait déjà un verdict DÉFINITIF différent : refus.
  refuseVerdictDefinitifExistant,

  /// Le ticket portait un `nonDetermine` et la politique interdit la
  /// transition automatique dans ce lot : refus.
  refuseTransitionNonDeterminee,

  /// Un rapport attribué ne correspond à AUCUN rapport officiel fourni.
  refuseRapportOfficielIntrouvable,

  /// Plusieurs rapports officiels correspondent au même rapport attribué :
  /// impossible de trancher, donc refus.
  refuseRapportOfficielAmbigu,

  /// La somme des `montantRetour` ne retombe pas exactement sur
  /// `verdict.total` : refus (aucun montant n'est « ajusté »).
  refuseTotalIncoherent,

  /// Le verdict porte un état sans rapport (perdu, rembourse, nonDetermine)
  /// alors que des rapports officiels ont été fournis pour l'attribution.
  refuseVerdictSansRapportAvecRapports,

  /// Le verdict a un état incohérent avec ses composantes.
  refuseVerdictIncoherent,
}

/// Résultat d'une tentative d'enregistrement.
///
/// [ticket] est TOUJOURS non nul : en cas de refus, c'est l'original, rendu
/// tel quel. Un appelant peut donc toujours l'utiliser sans le tester.
///
/// [persistanceComplete] dit la vérité sur ce qui a été conservé : il vaut
/// `false` quand une information du verdict n'a pas de place dans le schéma
/// B-1 (voir [informationsNonPersistees]).
class ResultatEnregistrementVerdict {
  final UserPrediction ticket;
  final StatutEnregistrementVerdict statut;

  /// Motif lisible du refus ; `null` quand l'opération a réussi.
  final String? motif;

  /// `true` seulement si TOUTES les informations du verdict ont été écrites.
  final bool persistanceComplete;

  /// Informations du verdict qu'aucun champ B-1 ne peut porter.
  final List<String> informationsNonPersistees;

  const ResultatEnregistrementVerdict._({
    required this.ticket,
    required this.statut,
    required this.motif,
    required this.persistanceComplete,
    required this.informationsNonPersistees,
  });

  bool get estEnregistre =>
      statut == StatutEnregistrementVerdict.enregistre;

  bool get estRefuse =>
      statut == StatutEnregistrementVerdict.refuseVerdictDefinitifExistant ||
      statut == StatutEnregistrementVerdict.refuseTransitionNonDeterminee ||
      statut == StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable ||
      statut == StatutEnregistrementVerdict.refuseRapportOfficielAmbigu ||
      statut == StatutEnregistrementVerdict.refuseTotalIncoherent ||
      statut ==
          StatutEnregistrementVerdict.refuseVerdictSansRapportAvecRapports ||
      statut == StatutEnregistrementVerdict.refuseVerdictIncoherent;

  /// `true` si le ticket n'a pas été touché (refus ou verdict identique).
  bool get ticketInchange => !estEnregistre;

  @override
  String toString() => 'ResultatEnregistrementVerdict(${statut.name}'
      '${motif == null ? '' : ' — $motif'}'
      ' | persistanceComplete=$persistanceComplete)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  1. TOLÉRANCE MONÉTAIRE — la règle réellement employée par B-3
// ═══════════════════════════════════════════════════════════════════════════

/// Tolérance de comparaison monétaire, en euros.
///
/// POURQUOI 1e-9 ET PAS `==` : `VerdictGain.attribue` additionne des `double`
/// dans l'ordre de la liste (`total += c.montantRetour`). Refaire la même
/// somme sur la même liste dans le même ordre donne exactement le même
/// `double` — mais un enregistreur ne peut pas parier là-dessus, car il reçoit
/// une liste qui peut avoir été filtrée. On accepte donc l'erreur d'arrondi
/// d'un `double` IEEE-754 sur des montants de l'ordre de 10⁵ €, soit ~1e-9 €
/// (un milliardième d'euro), sans jamais tolérer un centime d'écart.
///
/// ⚠️ Ce n'est PAS un « arrondi » : un écart d'un centime (0,01 €) est
/// 10 millions de fois plus grand que cette tolérance, donc il est REFUSÉ.
const double _toleranceEuros = 1e-9;

bool _memeMontant(double a, double b) => (a - b).abs() <= _toleranceEuros;

// ═══════════════════════════════════════════════════════════════════════════
//  2. IDENTITÉ D'UN RAPPORT — jamais une comparaison de montants
// ═══════════════════════════════════════════════════════════════════════════

/// Deux rapports publiés désignent-ils le MÊME rapport officiel ?
///
/// Critères, dans l'ordre de `_retrouverPublie` (moteur, l.1176-1178) :
/// `codePmu` + `libelle` + `combinaison`, PUIS `variante`, `rang`,
/// `pourUnEuro` et `rembourse` — les quatre contrôles supplémentaires exigés
/// par la consigne §1.
///
/// ⚠️ Le montant est comparé pour CONFIRMER l'identité, jamais pour CHOISIR.
///    Un rapport plus élevé ne gagne aucun arbitrage : s'il y a deux
///    candidats, l'appelant doit refuser (voir [StatutEnregistrementVerdict.
///    refuseRapportOfficielAmbigu]).
bool _memeRapportOfficiel(RapportPublie a, RapportPublie b) {
  if (a.codePmu != b.codePmu) return false;
  if (a.libelle != b.libelle) return false;
  if (a.combinaison != b.combinaison) return false;
  if (a.variante != b.variante) return false;
  if (a.rang != b.rang) return false;
  if (a.rembourse != b.rembourse) return false;
  final pa = a.pourUnEuro;
  final pb = b.pourUnEuro;
  if (pa == null || pb == null) return pa == pb;
  return _memeMontant(pa, pb);
}

/// Une composante du verdict désigne-t-elle ce rapport officiel ?
///
/// `ComposanteGain` porte quatre champs d'identité : `libelleRapport`,
/// `combinaisonRapport`, `categorie` (variante) et `pourUnEuro`. Elle ne porte
/// NI code PMU, NI rang, NI rembourse — ces trois informations n'existent que
/// sur le [RapportPublie].
///
/// La correspondance est donc démontrée sur les quatre champs disponibles, ce
/// qui suffit à garantir « aucune confusion » : deux variantes distinctes ne
/// partagent jamais (libellé, combinaison, catégorie), et le montant ajoute
/// une confirmation supplémentaire. Le code PMU du rapport retenu est ensuite
/// CONSERVÉ tel quel dans le [RapportAttribue] écrit.
bool _composanteCorrespondARapport(
  ComposanteGain c,
  RapportPublie officiel,
) {
  if (officiel.libelle != c.libelleRapport) return false;
  if (officiel.combinaison != c.combinaisonRapport) return false;
  if (officiel.variante != c.categorie) return false;
  final montant = officiel.pourUnEuro;
  if (montant == null) return false;
  return _memeMontant(montant, c.pourUnEuro);
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. TABLE DE CORRESPONDANCE VerdictGain → champs B-1
// ═══════════════════════════════════════════════════════════════════════════
//
//  ┌──────────────────────────────┬─────────────────────────────────────────┐
//  │ VerdictGain                  │ Champ B-1 persisté                      │
//  ├──────────────────────────────┼─────────────────────────────────────────┤
//  │ etat                         │ etatGain                                │
//  │ motif                        │ motifNonDetermination                   │
//  │ etatTirelire                 │ etatTirelire                            │
//  │ composantes[gagnant].pourUnEuro → dividendeGagnant     (DIVIDENDE)     │
//  │ composantes[place].pourUnEuro   → dividendePlace       (DIVIDENDE)     │
//  │ composantes → rapport officiel identifié              → rapportsAttribues│
//  │ rapport officiel.miseBaseCentimes                     → miseBaseCentimesUtilisee│
//  │ Σ composantes[].montantRetour                         → (reconstruit)  │
//  │ explication                                           → ✗ NON PERSISTÉ │
//  │ gainGagnant / gainPlace / total                       → ✗ aucun scalaire│
//  └──────────────────────────────┴─────────────────────────────────────────┘
//
//  ⚠️ `dividendeGagnant` reçoit `pourUnEuro` (dividende pour 1 €), JAMAIS
//     `verdict.gainGagnant` (qui est `mise × pourUnEuro`, un GAIN REMPORTÉ).
//     Confondre les deux était l'erreur identifiée à l'audit B-4.3.
//
//  ⚠️ `total` n'a PAS de champ : il se reconstitue par
//     `rapportsAttribues.fold(montantRetour)`, d'où le contrôle d'égalité
//     effectué avant écriture. C'est ce qui garantit qu'aucune information
//     financière n'est perdue — voir [resoudreTotalDepuisRapports].
// ═══════════════════════════════════════════════════════════════════════════

/// Reconstitue le gain total d'un ticket depuis ses rapports attribués.
///
/// C'est la formule EXACTE de `VerdictGain.attribue` (moteur, l.443-446) :
/// `total = Σ composantes[].montantRetour`. Elle est réécrite ici — et non
/// appelée — parce que le schéma B-1 ne stocke pas `total` : sans elle, un
/// ticket relu ne saurait plus quel gain il a produit.
///
/// Rend `null` si la liste est `null` (ticket jamais résolu). Rend `0.0` pour
/// une liste VIDE — cas distinct : « résolu, aucun rapport », donc aucun gain.
double? resoudreTotalDepuisRapports(List<RapportAttribue>? rapports) {
  if (rapports == null) return null;
  var total = 0.0;
  for (final r in rapports) {
    total += r.montantRetour;
  }
  return total;
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. POLITIQUE D'ENREGISTREMENT
// ═══════════════════════════════════════════════════════════════════════════
//
//  ┌──────────────────────┬────────────────────────────────────────────────┐
//  │ État existant         │ Action                                         │
//  ├──────────────────────┼────────────────────────────────────────────────┤
//  │ null                 │ écrire                                         │
//  │ attribue/perdu/rembourse │ comparer : identique ⇒ rien ; sinon REFUS   │
//  │ nonDetermine          │ comparer : identique ⇒ rien ; sinon REFUS      │
//  └──────────────────────┴────────────────────────────────────────────────┘
//
//  ⚠️ La transition `nonDetermine → définitif` est REFUSÉE, volontairement
//     (consigne §5) : elle exige une règle distinguant arrivée provisoire,
//     donnée manquante et ambiguïté réglementaire. Ce lot ne la décide pas.
// ═══════════════════════════════════════════════════════════════════════════

bool _verdictEstDefinitif(EtatGain e) =>
    e == EtatGain.attribue || e == EtatGain.perdu || e == EtatGain.rembourse;

// ═══════════════════════════════════════════════════════════════════════════
//  5. ENREGISTREUR PRINCIPAL
// ═══════════════════════════════════════════════════════════════════════════

/// Enregistre un [verdict] sur [ticket], avec une ÉVENTUELLE trace des
/// rapports officiels réellement utilisés.
///
/// PARAMÈTRES
///   • [ticket]  — le ticket à enrichir. Jamais modifié.
///   • [verdict] — le verdict produit par B-3. Jamais recalculé.
///   • [rapportsOfficiels] — les `RapportPublie` COMPLETS qui ont servi à la
///     résolution. Servent à DEUX choses, et à deux seulement : identifier
///     chaque rapport attribué, et lire sa `miseBaseCentimes` officielle.
///     Ils sont ignorés (et leur présence est contrôlée) pour un verdict qui
///     ne comporte aucune composante.
///   • [miseBaseCentimesOfficielle] — mise de base officielle du bloc, quand
///     elle est connue indépendamment des rapports. Utilisée seulement si
///     aucun rapport attribué ne porte déjà cette information.
///
/// RÈGLE DE REFUS : dès qu'une composante du verdict ne peut pas être reliée
/// à un rapport officiel fourni de façon NON AMBIGUË, l'enregistrement est
/// refusé et [ticket] est rendu tel quel.
ResultatEnregistrementVerdict enregistrerVerdictGain({
  required UserPrediction ticket,
  required VerdictGain verdict,
  List<RapportPublie> rapportsOfficiels = const <RapportPublie>[],
  int? miseBaseCentimesOfficielle,
}) {
  // ── A. Politique : que faire du verdict DÉJÀ présent ? ───────────────────
  final existant = ticket.etatGain;
  if (existant != null) {
    final identique = _verdictIdentique(ticket, verdict);
    if (identique) {
      return ResultatEnregistrementVerdict._(
        ticket: ticket, // l'original, non copié : rien n'a changé
        statut: StatutEnregistrementVerdict.dejaIdentique,
        motif: null,
        persistanceComplete: true,
        informationsNonPersistees: const <String>[],
      );
    }
    if (_verdictEstDefinitif(existant)) {
      return ResultatEnregistrementVerdict._(
        ticket: ticket,
        statut: StatutEnregistrementVerdict.refuseVerdictDefinitifExistant,
        motif: 'Un verdict définitif (${existant.name}) est déjà enregistré. '
            'Il n\'est jamais réécrit : le ticket reste inchangé.',
        persistanceComplete: false,
        informationsNonPersistees: const <String>[],
      );
    }
    // existant == nonDetermine et verdict différent.
    return ResultatEnregistrementVerdict._(
      ticket: ticket,
      statut: StatutEnregistrementVerdict.refuseTransitionNonDeterminee,
      motif: 'Le ticket porte déjà une indétermination '
          '(${ticket.motifNonDetermination?.name ?? "motif non conservé"}). '
          'La transition automatique vers un verdict définitif n\'est pas '
          'décidée dans ce lot : le ticket reste inchangé.',
      persistanceComplete: false,
      informationsNonPersistees: const <String>[],
    );
  }

  // ── B. Cohérence interne du verdict ──────────────────────────────────────
  final incoherence = _verifierCoherenceVerdict(verdict);
  if (incoherence != null) {
    return ResultatEnregistrementVerdict._(
      ticket: ticket,
      statut: StatutEnregistrementVerdict.refuseVerdictIncoherent,
      motif: incoherence,
      persistanceComplete: false,
      informationsNonPersistees: const <String>[],
    );
  }

  // ── C. Verdicts SANS composante : aucune attribution à écrire ────────────
  if (verdict.composantes.isEmpty) {
    if (rapportsOfficiels.isNotEmpty) {
      return ResultatEnregistrementVerdict._(
        ticket: ticket,
        statut:
            StatutEnregistrementVerdict.refuseVerdictSansRapportAvecRapports,
        motif: 'Le verdict « ${verdict.etat.name} » ne comporte AUCUNE '
            'composante, mais ${rapportsOfficiels.length} rapport(s) officiel(s) '
            'ont été fournis pour l\'attribution. Cette combinaison est '
            'contradictoire : aucun rapport n\'est écrit, le ticket reste '
            'inchangé.',
        persistanceComplete: false,
        informationsNonPersistees: const <String>[],
      );
    }
    // Écriture légitime : état + motif + tirelire. `rapportsAttribues` reste
    // `null` (JAMAIS `[]`) — voir la documentation de `_lireRapportsAttribues`.
    return ResultatEnregistrementVerdict._(
      ticket: ticket.copyWith(
        etatGain: verdict.etat,
        motifNonDetermination: verdict.motif,
        etatTirelire: verdict.etatTirelire,
        dividendeGagnant: null,
        dividendePlace: null,
        rapportsAttribues: null,
        miseBaseCentimesUtilisee: miseBaseCentimesOfficielle,
      ),
      statut: StatutEnregistrementVerdict.enregistre,
      motif: null,
      persistanceComplete: false,
      informationsNonPersistees: const <String>['explication'],
    );
  }

  // ── D. Verdict AVEC composantes : chaque composante doit être identifiée ─
  final attribues = <RapportAttribue>[];

  for (final composante in verdict.composantes) {
    // Filtrage : identité démontrée par [memeRapportOfficiel] — code PMU,
    // libellé, variante, combinaison, rang, rembourse et montant, exactement
    // les critères exigés. `ComposanteGain` ne porte PAS de code PMU : le code
    // est donc repris du rapport officiel retenu, jamais inventé.
    final candidats = <RapportPublie>[];
    for (final officiel in rapportsOfficiels) {
      if (!_composanteCorrespondARapport(composante, officiel)) continue;
      // Le MÊME rapport fourni deux fois n'est pas une ambiguïté : c'est un
      // doublon. [memeRapportOfficiel] compare l'identité complète (code,
      // libellé, variante, combinaison, rang, rembourse, montant) — le
      // montant confirme, il ne départage jamais.
      var dejaVu = false;
      for (final c in candidats) {
        if (_memeRapportOfficiel(c, officiel)) {
          dejaVu = true;
          break;
        }
      }
      if (!dejaVu) candidats.add(officiel);
    }

    if (candidats.isEmpty) {
      return ResultatEnregistrementVerdict._(
        ticket: ticket,
        statut: StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable,
        motif: 'Le rapport attribué « ${composante.libelleRapport} » '
            '(${composante.combinaisonRapport}, ${composante.categorie.name}, '
            '×${composante.pourUnEuro}) ne correspond à AUCUN rapport officiel '
            'fourni. Aucun rapport n\'est inventé : le ticket reste inchangé.',
        persistanceComplete: false,
        informationsNonPersistees: const <String>[],
      );
    }
    if (candidats.length > 1) {
      return ResultatEnregistrementVerdict._(
        ticket: ticket,
        statut: StatutEnregistrementVerdict.refuseRapportOfficielAmbigu,
        motif: '${candidats.length} rapports officiels correspondent au même '
            'rapport attribué « ${composante.libelleRapport} » '
            '(${composante.combinaisonRapport}). Impossible de trancher sans '
            'deviner, et le montant le plus élevé ne départage JAMAIS : le '
            'ticket reste inchangé.',
        persistanceComplete: false,
        informationsNonPersistees: const <String>[],
      );
    }

    // Un seul candidat : identité démontrée. On construit la preuve.
    final retenu = candidats.single;
    final RapportAttribue attribue;
    try {
      attribue = RapportAttribue.calculer(
        rapport: retenu,
        miseAppliquee: composante.mise,
      );
    } on ArgumentError {
      return ResultatEnregistrementVerdict._(
        ticket: ticket,
        statut: StatutEnregistrementVerdict.refuseVerdictIncoherent,
        motif: 'La mise de la composante « ${composante.libelleRapport} » '
            'vaut ${composante.mise} : une mise nulle ou négative ne fonde '
            'aucun gain. Le ticket reste inchangé.',
        persistanceComplete: false,
        informationsNonPersistees: const <String>[],
      );
    } on StateError catch (e) {
      return ResultatEnregistrementVerdict._(
        ticket: ticket,
        statut: StatutEnregistrementVerdict.refuseVerdictIncoherent,
        motif: 'Le rapport officiel « ${retenu.libelle} » ne porte pas de '
            'montant exploitable : $e',
        persistanceComplete: false,
        informationsNonPersistees: const <String>[],
      );
    }

    // ── Contrôle d'exactitude : le montant recalculé doit être CELUI du
    //    verdict, au milliardième d'euro près. Aucun montant n'est ajusté.
    if (!_memeMontant(attribue.montantRetour, composante.montantRetour)) {
      return ResultatEnregistrementVerdict._(
        ticket: ticket,
        statut: StatutEnregistrementVerdict.refuseTotalIncoherent,
        motif: 'Le montant retour de la composante « '
            '${composante.libelleRapport} » vaut ${composante.montantRetour} '
            'dans le verdict, mais '
            '${composante.mise} × ${retenu.pourUnEuro} = '
            '${attribue.montantRetour} d\'après le rapport officiel. '
            'Aucun montant n\'est corrigé : le ticket reste inchangé.',
        persistanceComplete: false,
        informationsNonPersistees: const <String>[],
      );
    }

    attribues.add(attribue);
  }

  // ── E. Contrôle FINAL : la somme doit retomber sur `verdict.total` ───────
  final totalReconstitue = resoudreTotalDepuisRapports(attribues)!;
  if (!_memeMontant(totalReconstitue, verdict.total)) {
    return ResultatEnregistrementVerdict._(
      ticket: ticket,
      statut: StatutEnregistrementVerdict.refuseTotalIncoherent,
      motif: 'La somme des montants retour des rapports officiels '
          '(${totalReconstitue.toStringAsFixed(6)} €) ne correspond pas au '
          'total du verdict (${verdict.total.toStringAsFixed(6)} €). '
          'Aucun total n\'est reconstruit de force : le ticket reste inchangé.',
      persistanceComplete: false,
      informationsNonPersistees: const <String>[],
    );
  }

  // ── F. Dividendes : `pourUnEuro` uniquement, JAMAIS gainGagnant/gainPlace ─
  double? dividendeGagnant;
  double? dividendePlace;
  for (final c in verdict.composantes) {
    switch (c.role) {
      case RoleComposante.gagnant:
        dividendeGagnant = c.pourUnEuro;
        break;
      case RoleComposante.place:
        dividendePlace = c.pourUnEuro;
        break;
      case RoleComposante.unique:
        // Un ticket à une seule composante n'a ni « Gagnant » ni « Placé » :
        // laisser les deux à `null` évite d'inventer une ventilation.
        break;
    }
  }

  // ── G. Mise de base : officielle et vérifiée, sinon `null` ───────────────
  int? miseBase;
  for (final a in attribues) {
    final m = a.rapport.miseBaseCentimes;
    if (m == null) continue;
    if (miseBase == null) {
      miseBase = m;
    } else if (miseBase != m) {
      // Deux rapports attribués portent deux mises de base différentes : on
      // n'en choisit AUCUNE, on ne peut pas en inventer une moyenne.
      miseBase = null;
      break;
    }
  }
  miseBase ??= miseBaseCentimesOfficielle;

  // ── H. Écriture ──────────────────────────────────────────────────────────
  return ResultatEnregistrementVerdict._(
    ticket: ticket.copyWith(
      etatGain: verdict.etat,
      motifNonDetermination: verdict.motif,
      etatTirelire: verdict.etatTirelire,
      rapportsAttribues: attribues,
      dividendeGagnant: dividendeGagnant,
      dividendePlace: dividendePlace,
      miseBaseCentimesUtilisee: miseBase,
    ),
    statut: StatutEnregistrementVerdict.enregistre,
    motif: null,
    // ⚠️ `explication` n'a AUCUN champ B-1 : on ne prétend pas une
    //    persistance complète. `total`, lui, se reconstitue exactement.
    persistanceComplete: false,
    informationsNonPersistees: const <String>['explication'],
  );
}

// ───────────────────────────────────────────────────────────────────────────
//  Vérifications internes
// ───────────────────────────────────────────────────────────────────────────

/// Le verdict déjà enregistré sur [ticket] est-il IDENTIQUE à [verdict] ?
///
/// « Identique » se juge sur ce qui est RÉELLEMENT persisté : état, motif,
/// tirelire, dividendes de composante, rapports attribués. Pas sur
/// `explication`, qui n'est pas conservée. Pas sur `total`, qui se reconstitue.
bool _verdictIdentique(UserPrediction ticket, VerdictGain verdict) {
  if (ticket.etatGain != verdict.etat) return false;
  if (ticket.etatTirelire != null &&
      ticket.etatTirelire != verdict.etatTirelire) {
    return false;
  }
  if (ticket.etatGain == EtatGain.nonDetermine) {
    return ticket.motifNonDetermination == verdict.motif;
  }
  if (verdict.etat != EtatGain.attribue) {
    // perdu / rembourse : l'état suffit, aucun montant.
    return true;
  }
  // Attribué : comparer les montants RÉELLEMENT stockés.
  final stocke = resoudreTotalDepuisRapports(ticket.rapportsAttribues);
  if (stocke == null) return false;
  return _memeMontant(stocke, verdict.total);
}

/// Contrôle de cohérence interne du verdict — sans le recalculer.
///
/// On ne vérifie QUE ce qui doit être vrai par construction :
///   • `attribue` ⇒ au moins une composante ET un total strictement positif ;
///   • `perdu` / `rembourse` ⇒ aucune composante ET un total nul ;
///   • `nonDetermine` ⇒ un motif NON NUL (un motif absent rendrait la
///     non-détermination intraçable) ET un total nul.
String? _verifierCoherenceVerdict(VerdictGain v) {
  switch (v.etat) {
    case EtatGain.attribue:
      if (v.composantes.isEmpty) {
        return 'Verdict « attribue » sans aucune composante : un gain sans '
            'preuve n\'est pas enregistrable.';
      }
      if (v.total <= 0) {
        return 'Verdict « attribue » avec un total non positif (${v.total}) : '
            'aucun montant exploitable, donc aucun enregistrement.';
      }
      var somme = 0.0;
      for (final c in v.composantes) {
        somme += c.montantRetour;
      }
      if (!_memeMontant(somme, v.total)) {
        return 'Le total du verdict (${v.total}) n\'égale pas la somme de ses '
            'composantes ($somme) : le verdict est incohérent.';
      }
      return null;

    case EtatGain.perdu:
    case EtatGain.rembourse:
      if (v.composantes.isNotEmpty) {
        return 'Verdict « ${v.etat.name} » avec '
            '${v.composantes.length} composante(s) : contradiction. '
            'Aucun montant ne peut accompagner une perte ou un remboursement.';
      }
      if (v.total != 0.0) {
        return 'Verdict « ${v.etat.name} » avec un total non nul (${v.total}) : '
            'contradiction.';
      }
      return null;

    case EtatGain.nonDetermine:
      if (v.motif == null) {
        return 'Verdict « nonDetermine » SANS motif : l\'indétermination '
            'serait intraçable après enregistrement. Refus.';
      }
      if (v.total != 0.0) {
        return 'Verdict « nonDetermine » avec un total non nul (${v.total}) : '
            'contradiction.';
      }
      return null;
  }
}
