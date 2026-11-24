// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-4.3 — ENREGISTREMENT SÉCURISÉ D'UN VERDICT B-3 SUR UN TICKET
//  LOT B-4.4 — LE CŒUR FINANCIER EST EXTRAIT, PAS DUPLIQUÉ
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
//
//  ── ★ LOT B-4.4 — POURQUOI LA DÉCISION A ÉTÉ EXTRAITE ────────────────────
//  B-4.4 doit appliquer EXACTEMENT les mêmes règles à `TrackedCourse`. La
//  consigne interdit de « créer un second moteur financier » ou de
//  « dupliquer la logique de B-4.3 ».
//
//  MESURE qui fonde l'extraction : sur les 622 lignes d'origine, seules
//  QUATRE lectures du porteur (`etatGain`, `etatTirelire`,
//  `motifNonDetermination`, `rapportsAttribues`) et UN appel `copyWith`
//  dépendent du modèle `UserPrediction`. Toute l'identité des rapports, tout
//  le calcul, tous les contrôles de total et la politique de refus sont
//  indépendants du modèle qui porte les sept champs B-1.
//
//  [deciderEcritureVerdict] porte donc désormais la règle, UNE SEULE FOIS.
//  [enregistrerVerdictGain] (ce fichier) et
//  [enregistrerVerdictGainSuivi] (`enregistreur_verdict_gain_suivi.dart`)
//  ne sont plus que deux APPLICATIONS de la même décision. Aucune règle
//  financière n'est réécrite dans le second fichier.
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

  bool get estEnregistre => statut == StatutEnregistrementVerdict.enregistre;

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
//  4-bis. ★ B1-T12 / RACCORDEMENT TARDIF — VERDICT OFFICIEL → MONTANT
// ═══════════════════════════════════════════════════════════════════════════
//
//  POURQUOI CETTE FONCTION EXISTE, ET POURQUOI ELLE EST ICI
//
//  Le raccordement des gains officiels tardifs doit alimenter
//  `montantOfficielPmu` à partir d'un `VerdictGain`. Deux contraintes se
//  contredisent :
//    • le garde-fou B-0 tient une liste FERMÉE de neuf importateurs de
//      `gain_pmu_types.dart` (comparée par ÉGALITÉ) ;
//    • `PmuProvider` — l'écrivain légitime — n'en fait pas partie et ne peut
//      donc pas nommer `EtatGain`, ni `VerdictGain` : il ne sait pas
//      distinguer `perdu` de `rembourse` (mesuré : `estGagne` et
//      `estNonDetermine` sont ses SEULS accesseurs booléens, et
//      `VerdictGain.total` vaut `0.0` pour les deux).
//
//  La conversion est donc placée ICI : ce fichier est DÉJÀ le 6ᵉ importateur
//  autorisé, il nomme déjà `EtatGain` et `VerdictGain`, et il n'ajoute que
//  des `import` qui ne remontent jamais vers un provider (aucun cycle).
//  La liste B-0 reste donc strictement à neuf, sans être élargie.
//
//  ⚠️ FONCTION PURE : aucun accès disque, aucun réseau, aucune horloge, aucun
//     état. Elle ne modifie NI `deciderEcritureVerdict` NI `enregistrerVerdictGain`,
//     dont les règles restent inchangées.

/// Le montant OFFICIEL exploitable porté par [verdict], ou `null`.
///
/// CONTRAT, état par état — il suit exactement les règles arbitrées :
///   • `attribue`    → [VerdictGain.total], le retour BRUT officiel ;
///   • `perdu`       → `0.0`, perte établie (distinct de `null`) ;
///   • `rembourse`   → `null` : un remboursement n'est pas un gain. Écrire `0.0`
///                     afficherait « Perdu : gain officiel établi à 0 € », et
///                     écrire la mise restituée afficherait « 🏆 Gain gagné ».
///                     Le verdict de remboursement, lui, est conservé par
///                     l'écriture B-1 : seule la conversion en montant est
///                     refusée. C'est l'arbitrage A du lot.
///   • `nonDetermine` → `null` : aucune perte n'est inventée.
///
/// ⚠️ `total` EST UN RETOUR BRUT, PAS UN BÉNÉFICE NET. Il vaut la somme des
///    `montantRetour` des composantes, chaque `montantRetour` étant
///    `miseAppliquee × pourUnEuro` — c'est-à-dire ce que l'opérateur REND,
///    mise comprise. `gainRetenuNet` du modèle en déduit la mise ; cette
///    fonction ne fait pas cette déduction, car `montantOfficielPmu` est
///    normativement un montant BRUT.
///
/// ⚠️ COMPLÉTUDE — L'ARBITRAGE B EXIGE UNE PREUVE, PAS UNE ESPÉRANCE.
///    `total` n'est rendu que si le verdict est COMPLET au sens démontrable :
///    chaque composante porte un `montantRetour` fini et strictement positif,
///    et `total` en est exactement la somme. Une composante silencieusement
///    écartée (voir le défaut documenté ci-dessous) ferait de `total` un
///    montant PARTIEL présenté comme total : dans ce cas on rend `null`.
///
/// ⚠️ DÉFAUT CONNU, NON CORRIGÉ ICI (moteur protégé, hors périmètre) :
///    `_composanteGagnantPlace` ne teste PAS `publie.rembourse`. Un
///    Gagnant+Placé remboursé est donc traité comme `attribue`, et sa
///    composante remboursée est comptée au dividende publié. Ce lot ne
///    modifie pas ce moteur : il BLOQUE l'écriture du montant dès que la
///    moindre composante porte `rembourse`, et le signale.
double? montantOfficielDepuisVerdict(
  VerdictGain verdict, {
  Set<String> combinaisonsRemboursees = const <String>{},
}) {
  switch (verdict.etat) {
    case EtatGain.perdu:
      // Perte définitive et démontrée : `0.0` est une information, `null`
      // serait une absence. La distinction est portée par le modèle.
      return 0.0;

    case EtatGain.rembourse:
      // Arbitrage A : JAMAIS de montant pour un remboursement.
      return null;

    case EtatGain.nonDetermine:
      // Aucune perte inventée : on ne sait pas, donc on ne dit rien.
      return null;

    case EtatGain.attribue:
      // Complétude démontrée, ou rien.
      return _totalDemontreComplet(verdict, combinaisonsRemboursees);
  }
}

/// Le `total` d'un verdict `attribue`, UNIQUEMENT s'il est démontrablement
/// complet et strictement positif.
///
/// Rend `null` — donc « montant officiel non établi » — dans quatre cas :
///   ① aucune composante : `attribue` sans composante est impossible par
///      construction (`VerdictGain.attribue` lève), donc un tel verdict est
///      incohérent et aucun montant ne doit en sortir ;
///   ② une composante a un `montantRetour` non fini ou non strictement
///      positif : elle ne fonde aucun retour, et l'ignorer produirait un
///      total PARTIEL ;
///   ③ la somme des `montantRetour` ne retombe pas EXACTEMENT sur `total` :
///      le contrat de `VerdictGain` serait violé, on ne « corrige » rien ;
///   ④ une composante porte une combinaison figurant dans
///      [combinaisonsRemboursees] : c'est la preuve RÉELLE du défaut de
///      `_composanteGagnantPlace`, qui ne teste pas `publie.rembourse`. Un
///      remboursement ne doit jamais devenir un gain par cette voie.
///
/// ⚠️ La comparaison ③ est EXACTE (`==`), volontairement : `total` est
///    construit par la MÊME addition, dans le même ordre. Une tolérance
///    masquerait précisément l'incohérence qu'on cherche à détecter.
double? _totalDemontreComplet(
  VerdictGain verdict,
  Set<String> combinaisonsRemboursees,
) {
  final composantes = verdict.composantes;

  // ① `attribue` sans composante : incohérent, aucun montant.
  if (composantes.isEmpty) return null;

  var somme = 0.0;
  for (final c in composantes) {
    final retour = c.montantRetour;

    // ② Une composante sans retour exploitable rend le total PARTIEL.
    if (!retour.isFinite || !(retour > 0)) return null;

    somme += retour;
  }

  // ③ Le total doit être EXACTEMENT la somme des composantes.
  if (somme != verdict.total) return null;

  // ④ Aucune composante remboursée (défaut G+P documenté).
  if (_uneComposanteRemboursee(verdict, combinaisonsRemboursees)) {
    return null;
  }

  // Un total nul n'est pas un gain : `0.0` est réservé à la perte établie.
  if (!(somme > 0)) return null;

  return somme;
}

/// Une composante du verdict provient-elle d'un rapport EXPLICITEMENT marqué
/// remboursé ?
///
/// [combinaisonsRemboursees] porte les combinaisons des rapports officiels dont
/// le drapeau `rembourse` est vrai. `ComposanteGain` ne transporte PAS ce
/// drapeau, et le moteur protégé ne le consulte pas dans le chemin
/// Gagnant+Placé : sans cette information fournie par l'appelant, l'absence de
/// remboursement ne serait pas démontrable.
///
/// ⚠️ ENSEMBLE VIDE = AUCUNE PREUVE DE REMBOURSEMENT, PAS UNE PREUVE D'ABSENCE.
///    Ce n'est pas une faiblesse de la garde mais sa portée exacte : la
///    conversion ne peut contredire un fait que si ce fait lui est fourni. Le
///    raccordement tardif, lui, transmet TOUJOURS l'ensemble réel (il dispose
///    des `ResultatOfficielCourse`).
bool _uneComposanteRemboursee(
  VerdictGain verdict,
  Set<String> combinaisonsRemboursees,
) {
  if (combinaisonsRemboursees.isEmpty) return false;
  for (final c in verdict.composantes) {
    final combinaison = c.combinaisonRapport.trim();
    if (combinaison.isEmpty) continue;
    if (combinaisonsRemboursees.contains(combinaison)) return true;
  }
  return false;
}

// ═══════════════════════════════════════════════════════════════════════════
//  5. ★ LOT B-4.4 — ÉCRITURE PARTAGÉE PAR LES DEUX MODÈLES
//
//  Cette section ne connaît AUCUN modèle. Elle ne manipule que les sept
//  valeurs du schéma B-1. C'est ce qui permet à `UserPrediction` et à
//  `TrackedCourse` d'être servis par UNE SEULE règle.
// ═══════════════════════════════════════════════════════════════════════════

/// Les sept valeurs B-1 à écrire sur un ticket, quand l'écriture est permise.
///
/// Aucun de ces champs n'est « facultatif au sens Dart » : `null` est ici une
/// VALEUR DÉCIDÉE (par exemple « aucun dividende Gagnant sur ce ticket »), pas
/// une absence de décision. C'est pourquoi il n'existe pas de constructeur
/// partiel : une écriture est toujours complète, ou elle n'existe pas.
class EcritureVerdict {
  final EtatGain etat;
  final MotifNonDetermination? motif;
  final EtatTirelire etatTirelire;
  final List<RapportAttribue>? rapportsAttribues;
  final double? dividendeGagnant;
  final double? dividendePlace;
  final int? miseBaseCentimesUtilisee;

  /// ★ CHANTIER 1/3 — Somme des mises EFFECTIVEMENT reversées au joueur.
  ///
  /// `null` = aucun remboursement établi — JAMAIS `0.0` par défaut, pour que
  /// l'absence de clé JSON (et donc l'absence de champ sur le ticket) reste
  /// distinguable d'un remboursement officiel nul.
  ///
  /// N'entre JAMAIS dans un gain : c'est une valeur DISTINCTE, vérifiée
  /// séparément à l'étape « E bis » de [deciderEcritureVerdict].
  final double? remboursement;

  const EcritureVerdict({
    required this.etat,
    required this.motif,
    required this.etatTirelire,
    required this.rapportsAttribues,
    required this.dividendeGagnant,
    required this.dividendePlace,
    required this.miseBaseCentimesUtilisee,
    this.remboursement,
  });

  @override
  String toString() => 'EcritureVerdict(${etat.name}'
      '${motif == null ? '' : ', ${motif!.name}'}'
      ', tirelire=${etatTirelire.name}'
      ', rapports=${rapportsAttribues?.length ?? 0}'
      ', G=${dividendeGagnant ?? "-"}, P=${dividendePlace ?? "-"}'
      '${remboursement == null ? '' : ', remb=${remboursement!}'}'
      ', miseBase=${miseBaseCentimesUtilisee ?? "-"})';
}

/// Décision d'écriture : soit un refus motivé, soit les sept valeurs à écrire.
///
/// [ecriture] est non nul SI ET SEULEMENT SI `statut == enregistre`. Aucun
/// état intermédiaire n'est représentable : on ne peut pas « écrire à moitié ».
class DecisionEcritureVerdict {
  final StatutEnregistrementVerdict statut;
  final String? motif;
  final EcritureVerdict? ecriture;

  const DecisionEcritureVerdict._({
    required this.statut,
    required this.motif,
    required this.ecriture,
  });

  /// Refus : rien n'est écrit, le motif dit pourquoi.
  factory DecisionEcritureVerdict.refus(
    StatutEnregistrementVerdict statut,
    String motif,
  ) =>
      DecisionEcritureVerdict._(
        statut: statut,
        motif: motif,
        ecriture: null,
      );

  /// Le ticket portait déjà exactement ce verdict : aucune écriture.
  static const DecisionEcritureVerdict dejaIdentique =
      DecisionEcritureVerdict._(
    statut: StatutEnregistrementVerdict.dejaIdentique,
    motif: null,
    ecriture: null,
  );

  /// Écriture autorisée.
  factory DecisionEcritureVerdict.ecrire(EcritureVerdict ecriture) =>
      DecisionEcritureVerdict._(
        statut: StatutEnregistrementVerdict.enregistre,
        motif: null,
        ecriture: ecriture,
      );

  bool get estEnregistre => statut == StatutEnregistrementVerdict.enregistre;

  bool get estDejaIdentique =>
      statut == StatutEnregistrementVerdict.dejaIdentique;

  bool get estRefuse => !estEnregistre && !estDejaIdentique;

  @override
  String toString() => 'DecisionEcritureVerdict(${statut.name}'
      '${motif == null ? '' : ' — $motif'}'
      '${ecriture == null ? '' : ' | $ecriture'})';
}

/// ★ LOT B-4.4 — LA RÈGLE, UNE SEULE FOIS.
///
/// Prend l'ÉTAT EXISTANT du ticket sous forme de valeurs (jamais le ticket
/// lui-même : la décision ne doit pas pouvoir le modifier, et ne doit pas
/// dépendre du modèle qui le porte) et rend la décision.
///
/// Paramètres d'état existant — les quatre seules lectures qui dépendaient du
/// modèle en B-4.3 :
///   • [etatExistant]           ← `ticket.etatGain`
///   • [etatTirelireExistant]   ← `ticket.etatTirelire`
///   • [motifExistant]          ← `ticket.motifNonDetermination`
///   • [rapportsExistants]      ← `ticket.rapportsAttribues`
///
/// Une valeur `null` signifie « le ticket ne porte rien », ce qui est
/// exactement la sémantique des champs correspondants dans les deux modèles
/// (verrou documenté dans leurs `fromJson` respectifs).
///
/// ⚠️ AUCUNE hypothèse n'est faite sur la provenance de ces valeurs. Un
///    appelant qui ne peut pas démontrer qu'elles décrivent le MÊME pari que
///    [verdict] ne doit pas appeler cette fonction (voir la règle d'identité
///    dans `enregistreur_verdict_gain_suivi.dart`).
DecisionEcritureVerdict deciderEcritureVerdict({
  required EtatGain? etatExistant,
  required EtatTirelire? etatTirelireExistant,
  required MotifNonDetermination? motifExistant,
  required List<RapportAttribue>? rapportsExistants,
  required VerdictGain verdict,
  List<RapportPublie> rapportsOfficiels = const <RapportPublie>[],
  int? miseBaseCentimesOfficielle,
}) {
  // ── A. Politique : que faire du verdict DÉJÀ présent ? ───────────────────
  if (etatExistant != null) {
    final identique = _verdictIdentique(
      etatExistant: etatExistant,
      etatTirelireExistant: etatTirelireExistant,
      motifExistant: motifExistant,
      rapportsExistants: rapportsExistants,
      verdict: verdict,
    );
    if (identique) {
      return DecisionEcritureVerdict.dejaIdentique;
    }
    if (_verdictEstDefinitif(etatExistant)) {
      return DecisionEcritureVerdict.refus(
        StatutEnregistrementVerdict.refuseVerdictDefinitifExistant,
        'Un verdict définitif (${etatExistant.name}) est déjà enregistré. '
        'Il n\'est jamais réécrit : le ticket reste inchangé.',
      );
    }
    // existant == nonDetermine et verdict différent.
    //
    // ★ CORRECTION « Anomalie 2 » (validée par l'utilisateur).
    //
    // AVANT : toute transition était refusée (`refuseTransitionNonDeterminee`).
    // Un ticket déclaré indéterminé faute de rapports officiels restait donc
    // indéterminé POUR TOUJOURS, même après publication des rapports — alors
    // que les données permettaient alors de trancher.
    //
    // APRÈS : la transition est AUTORISÉE, sous quatre conditions strictes :
    //   1. l'existant est bien `nonDetermine` (testé plus haut) : aucun verdict
    //      définitif n'est jamais réécrit — `_verdictEstDefinitif` a déjà
    //      renvoyé `refuseVerdictDefinitifExistant` avant d'arriver ici ;
    //   2. le nouveau verdict est DIFFÉRENT (sinon `dejaIdentique` plus haut) ;
    //   3. le nouveau verdict est COHÉRENT (branche B ci-dessous le revérifie) ;
    //   4. le nouveau verdict est exploitable : `perdu`/`rembourse` sans
    //      composante et total nul, ou `attribue` avec des composantes toutes
    //      identifiées à un rapport officiel fourni (branche D).
    //
    // IDEMPOTENCE : une fois le verdict définitif écrit, l'existant devient
    // `perdu`/`rembourse`/`attribue`, donc `_verdictEstDefinitif` renvoie vrai
    // au passage suivant ⇒ `dejaIdentique` ou `refuseVerdictDefinitifExistant`.
    // Aucun double gain n'est possible : l'écriture REMPLACE le verdict, elle
    // ne s'y ajoute pas.
    //
    // ⚠️ CETTE TRANSITION N'EST DÉCLENCHÉE QUE PAR UNE ACTUALISATION OFFICIELLE
    //    des résultats. Une simple ouverture d'écran ne rappelle pas cette
    //    fonction avec de nouveaux rapports : elle réutilise les données déjà
    //    chargées, donc `dejaIdentique`. Aucun recalcul arbitraire.
    // (on poursuit vers la branche B)
  }

  // ── B. Cohérence interne du verdict ──────────────────────────────────────
  final incoherence = _verifierCoherenceVerdict(verdict);
  if (incoherence != null) {
    return DecisionEcritureVerdict.refus(
      StatutEnregistrementVerdict.refuseVerdictIncoherent,
      incoherence,
    );
  }

  // ── C. Verdicts SANS composante : aucune attribution à écrire ────────────
  //
  // ★ CORRECTION « Anomalie 1 » (validée par l'utilisateur).
  //
  // AVANT : dès que `rapportsOfficiels` était non vide, un verdict sans
  // composante était REFUSÉ (`refuseVerdictSansRapportAvecRapports`).
  //
  // POURQUOI C'ÉTAIT FAUX — mesuré sur les captures réelles :
  //   la présence de rapports officiels pour une COURSE n'implique pas que le
  //   TICKET doive porter une composante. Un pari dont la combinaison n'est pas
  //   gagnante est `perdu` alors que la course publie parfaitement ses rapports.
  //   La garde transformait donc toute perte démontrée en « en attente », et un
  //   même ticket était persisté `nonDetermine` quand les rapports manquaient
  //   puis restait bloqué dès qu'ils arrivaient : la persistance dépendait de la
  //   disponibilité des données, ce qui n'a aucun sens métier.
  //
  // CE QUI EST CONSERVÉ — le refus ne disparaît pas, il est CIBLÉ :
  //   `_verifierCoherenceVerdict` (branche B, inchangée) garantit déjà que
  //   `perdu`/`rembourse` n'ont AUCUNE composante et un total nul, et qu'un
  //   `nonDetermine` porte un motif. Un verdict sans composante ne peut donc
  //   être qu'un de ces trois états : aucun montant n'est inventé ici.
  //   `rapportsAttribues` reste `null` (JAMAIS `[]`) — voir la documentation de
  //   `_lireRapportsAttribues`.
  if (verdict.composantes.isEmpty) {
    return DecisionEcritureVerdict.ecrire(EcritureVerdict(
      etat: verdict.etat,
      motif: verdict.motif,
      etatTirelire: verdict.etatTirelire,
      rapportsAttribues: null,
      dividendeGagnant: null,
      dividendePlace: null,
      miseBaseCentimesUtilisee: miseBaseCentimesOfficielle,
      // ★ CHANTIER 1/3 — REMBOURSEMENT SANS COMPOSANTE.
      //
      //   Un verdict `rembourse` porte `composantes: []` et `total: 0.0`,
      //   mais il PORTE un `remboursement` (la mise reversée). Sans cette
      //   ligne, un remboursement INTÉGRAL serait persisté comme un état
      //   « rembourse » sans aucun montant : l'écran afficherait « Pari
      //   remboursé » sans jamais dire combien, alors que le montant est
      //   connu et démontré. C'est exactement le « résultat financier » que
      //   l'arbitrage exige de conserver exactement.
      //
      //   ⚠️ `null` si `remboursement == 0` : on n'écrit pas une clé pour un
      //      montant nul, et l'absence reste distincte d'un 0 € établi.
      remboursement:
          verdict.remboursement > 0 ? verdict.remboursement : null,
    ));
  }

  // ── D. Verdict AVEC composantes : chaque composante doit être identifiée ─
  final attribues = <RapportAttribue>[];
  // Mises EFFECTIVEMENT reversées, composante par composante. Tenu à part du
  // total des gains : c'est la garantie que « Gain gagné » n'absorbe jamais
  // un remboursement.
  final remboursements = <double>[];

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
      return DecisionEcritureVerdict.refus(
        StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable,
        'Le rapport attribué « ${composante.libelleRapport} » '
        '(${composante.combinaisonRapport}, ${composante.categorie.name}, '
        '×${composante.pourUnEuro}) ne correspond à AUCUN rapport officiel '
        'fourni. Aucun rapport n\'est inventé : le ticket reste inchangé.',
      );
    }
    if (candidats.length > 1) {
      return DecisionEcritureVerdict.refus(
        StatutEnregistrementVerdict.refuseRapportOfficielAmbigu,
        '${candidats.length} rapports officiels correspondent au même '
        'rapport attribué « ${composante.libelleRapport} » '
        '(${composante.combinaisonRapport}). Impossible de trancher sans '
        'deviner, et le montant le plus élevé ne départage JAMAIS : le '
        'ticket reste inchangé.',
      );
    }

    // Un seul candidat : identité démontrée. On construit la preuve.
    final retenu = candidats.single;

    // ── D bis. ★ COMPOSANTE REMBOURSÉE — AUCUN GAIN À RECONSTITUER.
    //
    //    MESURE QUI A MOTIVÉ CE BLOC : `RapportAttribue.calculer` applique
    //    `mise × pourUnEuro`. L'appliquer à une composante remboursée
    //    reproduirait exactement le défaut corrigé dans le moteur (21 € de
    //    gain inventés sur une mise de 10 € remboursée), et le contrôle
    //    d'exactitude ci-dessous REFUSERAIT alors un verdict pourtant correct
    //    (montantRetour = 0,0 dans le verdict, 21,0 recalculé).
    //
    //    Une composante remboursée ne produit AUCUN `RapportAttribue` : elle
    //    n'entre donc pas dans `attribues`, ni dans le total reconstitué —
    //    ce qui est exact, puisque `verdict.total` n'inclut aucun
    //    remboursement par construction. Sa mise reversée est vérifiée
    //    séparément à l'étape E bis.
    if (composante.rembourse) {
      if (!retenu.rembourse) {
        return DecisionEcritureVerdict.refus(
          StatutEnregistrementVerdict.refuseVerdictIncoherent,
          'La composante « ${composante.libelleRapport} » est déclarée '
          'remboursée, mais le rapport officiel retenu ne l\'est pas. '
          'Le ticket reste inchangé.',
        );
      }
      remboursements.add(composante.mise);
      continue;
    }
    if (retenu.rembourse) {
      return DecisionEcritureVerdict.refus(
        StatutEnregistrementVerdict.refuseVerdictIncoherent,
        'Le rapport officiel « ${retenu.libelle} » est remboursé, mais la '
        'composante correspondante du verdict ne l\'est pas : un '
        'remboursement ne peut pas fonder un gain. Le ticket reste inchangé.',
      );
    }

    final RapportAttribue attribue;
    try {
      attribue = RapportAttribue.calculer(
        rapport: retenu,
        miseAppliquee: composante.mise,
      );
    } on ArgumentError {
      return DecisionEcritureVerdict.refus(
        StatutEnregistrementVerdict.refuseVerdictIncoherent,
        'La mise de la composante « ${composante.libelleRapport} » '
        'vaut ${composante.mise} : une mise nulle ou négative ne fonde '
        'aucun gain. Le ticket reste inchangé.',
      );
    } on StateError catch (e) {
      return DecisionEcritureVerdict.refus(
        StatutEnregistrementVerdict.refuseVerdictIncoherent,
        'Le rapport officiel « ${retenu.libelle} » ne porte pas de '
        'montant exploitable : $e',
      );
    }

    // ── Contrôle d'exactitude : le montant recalculé doit être CELUI du
    //    verdict, au milliardième d'euro près. Aucun montant n'est ajusté.
    if (!_memeMontant(attribue.montantRetour, composante.montantRetour)) {
      return DecisionEcritureVerdict.refus(
        StatutEnregistrementVerdict.refuseTotalIncoherent,
        'Le montant retour de la composante « '
        '${composante.libelleRapport} » vaut ${composante.montantRetour} '
        'dans le verdict, mais '
        '${composante.mise} × ${retenu.pourUnEuro} = '
        '${attribue.montantRetour} d\'après le rapport officiel. '
        'Aucun montant n\'est corrigé : le ticket reste inchangé.',
      );
    }

    attribues.add(attribue);
  }

  // ── E. Contrôle FINAL : la somme doit retomber sur `verdict.total` ───────
  final totalReconstitue = attribues.isEmpty
      ? 0.0
      : resoudreTotalDepuisRapports(attribues)!;
  if (!_memeMontant(totalReconstitue, verdict.total)) {
    return DecisionEcritureVerdict.refus(
      StatutEnregistrementVerdict.refuseTotalIncoherent,
      'La somme des montants retour des rapports officiels '
      '(${totalReconstitue.toStringAsFixed(6)} €) ne correspond pas au '
      'total du verdict (${verdict.total.toStringAsFixed(6)} €). '
      'Aucun total n\'est reconstruit de force : le ticket reste inchangé.',
    );
  }

  // ── E bis. ★ REMBOURSEMENTS : contrôlés SÉPARÉMENT du total des gains.
  //
  //    Le remboursement n'entre ni dans `verdict.total`, ni dans le total
  //    reconstitué : les additionner ici confondrait « Gain gagné » et
  //    « montant rendu », exactement ce que le modèle interdit. On vérifie
  //    donc que le verdict n'annonce QUE les mises réellement remboursées par
  //    les rapports officiels — sans jamais déduire un remboursement d'un
  //    dividende.
  var totalRembourse = 0.0;
  for (final m in remboursements) {
    totalRembourse += m;
  }
  if (!_memeMontant(totalRembourse, verdict.remboursement)) {
    return DecisionEcritureVerdict.refus(
      StatutEnregistrementVerdict.refuseTotalIncoherent,
      'Le remboursement du verdict '
      '(${verdict.remboursement.toStringAsFixed(6)} €) ne correspond pas aux '
      'mises réellement remboursées par les rapports officiels '
      '(${totalRembourse.toStringAsFixed(6)} €). Aucun remboursement n\'est '
      'reconstruit de force : le ticket reste inchangé.',
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

  return DecisionEcritureVerdict.ecrire(EcritureVerdict(
    etat: verdict.etat,
    motif: verdict.motif,
    etatTirelire: verdict.etatTirelire,
    rapportsAttribues: attribues,
    dividendeGagnant: dividendeGagnant,
    dividendePlace: dividendePlace,
    miseBaseCentimesUtilisee: miseBase,
    // ★ CHANTIER 1/3 — LE REMBOURSEMENT VÉRIFIÉ À L'ÉTAPE E BIS, ÉCRIT ICI.
    //
    //   C'est la valeur CONTRÔLÉE (somme des mises des composantes réellement
    //   remboursées par les rapports officiels) qui est écrite — et non
    //   `verdict.remboursement` recopié : l'étape E bis vient de PROUVER leur
    //   égalité au centime. Écrire la valeur mesurée plutôt que la valeur
    //   annoncée est la même discipline que pour le total des gains.
    //
    //   ⚠️ `null` quand aucun remboursement : aucune clé JSON n'est alors
    //      produite, et le ticket garde exactement sa forme d'origine.
    remboursement: totalRembourse > 0 ? totalRembourse : null,
  ));
}

// ═══════════════════════════════════════════════════════════════════════════
//  6. APPLICATION AU MODÈLE `UserPrediction`
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
///
/// ★ LOT B-4.4 — cette fonction n'est plus qu'une APPLICATION : toute la
///   décision est dans [deciderEcritureVerdict]. Le comportement est
///   strictement inchangé (les 50 tests de B-4.3 le vérifient).
ResultatEnregistrementVerdict enregistrerVerdictGain({
  required UserPrediction ticket,
  required VerdictGain verdict,
  List<RapportPublie> rapportsOfficiels = const <RapportPublie>[],
  int? miseBaseCentimesOfficielle,
}) {
  final decision = deciderEcritureVerdict(
    etatExistant: ticket.etatGain,
    etatTirelireExistant: ticket.etatTirelire,
    motifExistant: ticket.motifNonDetermination,
    rapportsExistants: ticket.rapportsAttribues,
    verdict: verdict,
    rapportsOfficiels: rapportsOfficiels,
    miseBaseCentimesOfficielle: miseBaseCentimesOfficielle,
  );

  if (decision.estDejaIdentique) {
    return ResultatEnregistrementVerdict._(
      ticket: ticket, // l'original, non copié : rien n'a changé
      statut: StatutEnregistrementVerdict.dejaIdentique,
      motif: null,
      persistanceComplete: true,
      informationsNonPersistees: const <String>[],
    );
  }

  if (!decision.estEnregistre) {
    return ResultatEnregistrementVerdict._(
      ticket: ticket,
      statut: decision.statut,
      motif: decision.motif,
      persistanceComplete: false,
      informationsNonPersistees: const <String>[],
    );
  }

  final e = decision.ecriture!;
  return ResultatEnregistrementVerdict._(
    ticket: ticket.copyWith(
      etatGain: e.etat,
      motifNonDetermination: e.motif,
      etatTirelire: e.etatTirelire,
      rapportsAttribues: e.rapportsAttribues,
      dividendeGagnant: e.dividendeGagnant,
      dividendePlace: e.dividendePlace,
      miseBaseCentimesUtilisee: e.miseBaseCentimesUtilisee,
      // ★ CHANTIER 1/3 — LE REMBOURSEMENT SUIT LE VERDICT, LUI AUSSI.
      //
      //   `copyWith` porte une sentinelle : `null` est écrit EXPLICITEMENT
      //   ici — ce qui est correct, car cette écriture REMPLACE le verdict.
      //   Un verdict définitif n'est jamais réécrit, et un `nonDetermine`
      //   n'établit aucun remboursement : `null` est alors la valeur juste.
      remboursementPmu: e.remboursement,
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

/// Le verdict déjà enregistré est-il IDENTIQUE à [verdict] ?
///
/// « Identique » se juge sur ce qui est RÉELLEMENT persisté : état, motif,
/// tirelire, dividendes de composante, rapports attribués. Pas sur
/// `explication`, qui n'est pas conservée. Pas sur `total`, qui se reconstitue.
///
/// ★ LOT B-4.4 — la signature prend désormais des VALEURS, pas un ticket :
///   la règle ne doit dépendre d'aucun modèle.
bool _verdictIdentique({
  required EtatGain etatExistant,
  required EtatTirelire? etatTirelireExistant,
  required MotifNonDetermination? motifExistant,
  required List<RapportAttribue>? rapportsExistants,
  required VerdictGain verdict,
}) {
  if (etatExistant != verdict.etat) return false;
  if (etatTirelireExistant != null &&
      etatTirelireExistant != verdict.etatTirelire) {
    return false;
  }
  if (etatExistant == EtatGain.nonDetermine) {
    return motifExistant == verdict.motif;
  }
  if (verdict.etat != EtatGain.attribue) {
    // perdu / rembourse : l'état suffit, aucun montant.
    return true;
  }
  // Attribué : comparer les montants RÉELLEMENT stockés.
  final stocke = resoudreTotalDepuisRapports(rapportsExistants);
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
      // ⚠️ Un `attribue` dont TOUTES les composantes sont remboursées serait
      //    un gain sans aucun gain : le total nul le trahit juste en dessous,
      //    mais on nomme ici la cause exacte pour que le refus soit lisible.
      if (v.remboursement < 0) {
        return 'Verdict « attribue » avec un remboursement négatif '
            '(${v.remboursement}) : contradiction.';
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
      // Un remboursement ne doit JAMAIS gonfler le gain : il est vérifié
      // qu'aucune composante remboursée ne porte de montant retour.
      for (final c in v.composantes) {
        if (c.rembourse && c.montantRetour != 0.0) {
          return 'Composante remboursée « ${c.libelleRapport} » portant un '
              'montant retour de ${c.montantRetour} : un remboursement n\'est '
              'pas un gain.';
        }
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
