// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 4-D — ADAPTATEUR PUR : RapportPmu ➜ RapportOfficiel
//
//  OBJET : rendre directement exploitables par le résolveur de rapports les
//  informations officielles conservées par `RapportPmu` depuis l'étape 4-C.
//
//  ── CE QUE FAIT CE FICHIER ───────────────────────────────────────────────
//  Il recopie, champ par champ, ce qu'un rapport PMU publié contient :
//
//      code du pari · libellé exact · combinaison · rang payable ·
//      dividende pour 1 € · remboursement
//
//  ── CE QU'IL NE FAIT PAS, VOLONTAIREMENT ─────────────────────────────────
//   • AUCUNE récupération réseau. Il ne connaît ni `http`, ni URL, ni cache.
//   • AUCUNE reconstitution. Si un champ manque, il le laisse manquer : le
//     résolveur en tirera un refus explicite, jamais une valeur plausible.
//   • AUCUNE sélection. Il ne choisit pas « le premier » ni « le plus élevé » :
//     il adapte la TOTALITÉ de la liste, dans l'ordre reçu.
//   • AUCUN usage de `estOrdre`. Voir `ETAPE 4-D / §6` plus bas : cette
//     heuristique est FAUSSE et ne doit servir à aucune décision.
//
//  ── POURQUOI CE FICHIER N'IMPORTE PAS LE RÉSOLVEUR ───────────────────────
//  La garde structurelle `etape4a_resolveur_rapport_test.dart` (E4A/7) exige
//  qu'AUCUN fichier de `lib/` — hormis le résolveur lui-même — ne cite le nom
//  de son fichier source. C'est une contrainte de NON-BRANCHEMENT, et elle
//  est respectée ici : cet adaptateur ne dépend que du contrat
//  `RapportOfficiel`, pas de l'implémentation du résolveur. Le branchement
//  effectif reste donc impossible tant qu'il n'est pas explicitement autorisé.
// ═══════════════════════════════════════════════════════════════════════════

import 'gain_calculator.dart' show RapportPmu;
import 'gain_ticket_calculator.dart'
    show RapportOfficiel, VarianteRapport, varianteDepuisLibelle;

/// Adapte **un** rapport PMU conservé vers le contrat du résolveur.
///
/// Correspondance stricte, sans transformation :
///
/// | `RapportPmu`            | `RapportOfficiel`     |
/// |-------------------------|-----------------------|
/// | `codePariOfficiel`      | `typePari`            |
/// | `libelleOfficiel`       | `libelle`             |
/// | `combinaison`           | `combinaison`         |
/// | `dividende`             | `rapportPourUnEuro`   |
/// | `rembourse`             | `rembourse`           |
///
/// ⚠️ **`libelle` n'est JAMAIS reconstitué.** Un rapport dont le libellé
/// officiel est vide est adapté avec un libellé vide : sa variante vaudra
/// `VarianteRapport.illisible` et le résolveur le REFUSERA. On ne fabrique
/// jamais « e-Tiercé Ordre » à partir de `estOrdre == true` — c'est
/// précisément ce que le mandat interdit au §6.
///
/// ⚠️ Le **rang payable** ne figure pas dans le contrat `RapportOfficiel`.
/// Il n'est donc pas transporté ici ; il est **contrôlé** par
/// [verifierCoherenceRang], qui le confronte au libellé. Le résolveur, lui,
/// discrimine par le libellé — jamais par le rang, jamais par `estOrdre`.
RapportOfficiel adaptateurRapportPmuVersOfficiel(RapportPmu rapport) {
  return RapportOfficiel(
    typePari: rapport.codePariOfficiel,
    libelle: rapport.libelleOfficiel,
    combinaison: rapport.combinaison,
    rapportPourUnEuro: rapport.dividende > 0 ? rapport.dividende : null,
    rembourse: rapport.rembourse,
  );
}

/// Adapte **toute** une liste, dans l'ordre reçu.
///
/// Aucun tri, aucun filtrage, aucune sélection : l'ordre publié par l'API est
/// conservé tel quel. C'est au résolveur de décider, et à lui seul.
List<RapportOfficiel> adaptateurRapportsPmu(List<RapportPmu> rapports) {
  final out = <RapportOfficiel>[];
  for (final r in rapports) {
    out.add(adaptateurRapportPmuVersOfficiel(r));
  }
  return List<RapportOfficiel>.unmodifiable(out);
}

/// Adapte les seuls rapports d'un code PMU donné.
///
/// Utilitaire de lecture : il **filtre par code**, il ne choisit pas un
/// rapport parmi ceux du code. Si le code demandé produit plusieurs rapports
/// (Ordre + Désordre, ou Bonus multiples), ils sont TOUS rendus.
List<RapportOfficiel> adaptateurRapportsPmuDuCode(
    List<RapportPmu> rapports, String codePariOfficiel) {
  return adaptateurRapportsPmu(
    rapports.where((r) => r.codePariOfficiel == codePariOfficiel).toList(),
  );
}

// ───────────────────────────────────────────────────────────────────────────
//  CONTRÔLE CROISÉ DU RANG PAYABLE
//
//  Le rang est une information officielle : il ne doit être ni perdu, ni
//  ignoré. Il n'entre pas dans le contrat du résolveur, mais il permet de
//  VÉRIFIER que le libellé dit la même chose que la grille de paiement.
//  Une incohérence est un refus explicite, jamais un choix arbitraire.
//
//  Table établie sur les réponses RÉELLES mesurées (18/11/2026) :
//
//    E_TIERCE        rang 1 → Ordre           rang 2 → Désordre
//    E_QUARTE_PLUS   rang 1 → Ordre           rang 2 → Désordre   rang 3 → Bonus
//    E_QUINTE_PLUS   rang 1 → Ordre           rang 2 → Désordre
//                    rang 3 → Bonus 4sur5     rang 4 → Bonus 3
//    E_MULTI         rang 1 → en 4   rang 2 → en 5   rang 3 → en 6   rang 4 → en 7
//
//  Les autres paris (Simple, Couplé, Trio, 2sur4…) n'ont pas de variante
//  indexée par le rang : pour eux, aucun contrôle n'est affirmé.
// ───────────────────────────────────────────────────────────────────────────

/// Désaccord constaté entre le rang payable et le libellé officiel.
class IncoherenceRang {
  /// Rang publié, `null` si l'API ne l'a pas fourni.
  final int? rang;

  /// Libellé officiel tel que publié.
  final String libelle;

  /// Variante déduite du seul libellé officiel.
  final VarianteRapport variante;

  /// Explication en clair, jamais vide.
  final String explication;

  const IncoherenceRang({
    required this.rang,
    required this.libelle,
    required this.variante,
    required this.explication,
  });

  @override
  String toString() => 'IncoherenceRang(rang $rang | "$libelle" | '
      '$variante) : $explication';
}

/// Vérifie que le [RapportPmu.rangCombinaisonPayable] officiel est cohérent
/// avec le [RapportPmu.libelleOfficiel].
///
/// Rend `null` si :
///  • le code du pari n'a pas de variantes indexées par le rang ;
///  • le rang n'a pas été publié (on n'affirme alors rien) ;
///  • le rang et le libellé concordent.
///
/// Rend une [IncoherenceRang] motivée sinon. Ne rend JAMAIS un choix : une
/// incohérence ne devient ni « ordre » ni « désordre » par défaut.
IncoherenceRang? verifierCoherenceRang(RapportPmu rapport) {
  final rang = rapport.rangCombinaisonPayable;
  // Sans rang publié, aucune affirmation n'est possible.
  if (rang == null) return null;

  final libelle = rapport.libelleOfficiel;
  final reel = varianteDepuisLibelle(libelle);

  if (reel == VarianteRapport.illisible) {
    return IncoherenceRang(
      rang: rang,
      libelle: libelle,
      variante: reel,
      explication:
          'Le libellé officiel est vide ou absent : le rang $rang ne peut être '
          'rattaché à aucune variante. Aucune reconstitution n\'est tentée.',
    );
  }

  final attendu = _rangAttendu(rapport.codePariOfficiel, reel);
  // Code sans variante indexée par le rang : rien à affirmer.
  if (attendu == null) return null;

  if (attendu != rang) {
    return IncoherenceRang(
      rang: rang,
      libelle: libelle,
      variante: reel,
      explication:
          'Le libellé « $libelle » implique le rang $attendu, mais l\'API '
          'publie le rang $rang pour ce rapport. Le désaccord est signalé : '
          'aucun des deux n\'est retenu par préférence.',
    );
  }
  return null;
}

/// Rang attendu pour une variante, selon le code PMU officiel.
/// `null` si le code n'a pas de variantes indexées par le rang.
int? _rangAttendu(String codePariOfficiel, VarianteRapport variante) {
  switch (codePariOfficiel) {
    case 'E_TIERCE':
      if (variante == VarianteRapport.ordre) return 1;
      if (variante == VarianteRapport.desordre) return 2;
      return null;
    case 'E_QUARTE_PLUS':
      if (variante == VarianteRapport.ordre) return 1;
      if (variante == VarianteRapport.desordre) return 2;
      if (variante == VarianteRapport.bonusQuarte) return 3;
      return null;
    case 'E_QUINTE_PLUS':
      if (variante == VarianteRapport.ordre) return 1;
      if (variante == VarianteRapport.desordre) return 2;
      if (variante == VarianteRapport.bonus4sur5) return 3;
      if (variante == VarianteRapport.bonus3) return 4;
      return null;
    default:
      // Simple, Couplé, Trio, 2sur4, Multi : pas de grille indexée par rang.
      return null;
  }
}

/// Classification du libellé, **identique** à celle du moteur A.
///
/// On ne duplique pas la règle : on appelle `varianteDepuisLibelle`, la
/// fonction même qu'utilise `RapportOfficiel.variante`. Une divergence entre
/// les deux serait un défaut, pas une variante.

