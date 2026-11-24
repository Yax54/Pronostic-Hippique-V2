// ═══════════════════════════════════════════════════════════════════════════
//  COMPARAISON MONÉTAIRE — NORMALISATION AU CENTIME
//
//  ★ POURQUOI CE FICHIER (chantier 1/3, point 3)
//
//  La comparaison monétaire du moteur reposait uniquement sur une tolérance
//  flottante de `1e-9` euro. Or cette convention est PLUS STRICTE qu'une
//  comparaison au centime, et elle produit donc des verdicts faux :
//
//     • 75.001 € et 75.00 € sont, au centime, LE MÊME montant — le premier
//       n'est qu'un artefact d'arrondi de calcul. Avec `1e-9`, ils étaient
//       déclarés DIFFÉRENTS.
//     • 75.01 € et 75.00 € diffèrent d'un centime réel : ils doivent rester
//       DIFFÉRENTS. Avec `1e-9`, ils l'étaient — mais pour la mauvaise raison,
//       et le premier cas l'était aussi.
//
//  ⚠️ CE QUI EST PROUVÉ, ET CE QUI NE L'EST PAS (mesuré avant d'écrire).
//
//     PROUVÉ : le site d'appel ATTEIGNABLE compare un total PERSISTÉ (relu
//     depuis JSON, donc susceptible de porter une dérive de calcul) au total
//     exact d'un verdict, via `_verdictIdentique` /
//     `deciderEcritureVerdict`. Avec `1e-9`, une dérive d'un millième y était
//     lue comme « verdict différent ». Les tests P3/3.1 et P3/3.2 le mesurent
//     sur les VRAIS points d'entrée publics.
//
//     NON PROUVÉ, DONC NON AFFIRMÉ : qu'un gain officiel établi soit devenu
//     « indéterminé » en production à cause de cette convention. Le contrôle
//     de cohérence interne de `_totalDemontreComplet` est structurellement
//     inatteignable avec un écart (`VerdictGain._` privé, `total` recalculé
//     par le constructeur, aucun `fromJson` sur `VerdictGain`). Ce site reste
//     défensif.
//
//  La règle appliquée est donc : deux montants sont égaux s'ils donnent le
//  MÊME NOMBRE DE CENTIMES après arrondi au plus proche.
//
//  ── CE QUE CE FICHIER NE FAIT PAS ─────────────────────────────────────────
//   • Il n'ARRONDIT aucun montant stocké ou affiché : il ne sert qu'à
//     COMPARER. Un montant de 75,001 € reste 75,001 € en base ; c'est la
//     comparaison qui le rapproche de 75,00 €.
//   • Il ne confond jamais `null` et `0.0` : `null` signifie « non établi »,
//     `0.0` signifie « officiellement nul ». Les fonctions de ce fichier
//     prennent des `double` non nuls ; la distinction est portée par les
//     appelants ([memeMontantOuTousDeuxNuls] l'explicite).
// ═══════════════════════════════════════════════════════════════════════════

/// Nombre de centimes dans un euro.
const int kCentimesParEuro = 100;

/// Convertit un montant en euros en un nombre ENTIER de centimes.
///
/// L'arrondi est celui de `double.round()` : au plus proche, les demis vers
/// l'infini positif. Il est explicite et documenté, jamais implicite.
///
/// `75.001 → 7500` · `75.005 → 7501` · `75.01 → 7501` · `75.00 → 7500`
int centimesDe(double euros) => (euros * kCentimesParEuro).round();

/// Deux montants sont-ils ÉGAUX au centime ?
///
/// `75.001` et `75.00` ⇒ `true` (même nombre de centimes : 7500).
/// `75.01`  et `75.00` ⇒ `false` (7501 ≠ 7500).
///
/// ⚠️ Une valeur NON FINIE (`NaN`, `±Infinity`) n'est jamais déclarée égale :
///    on ne peut pas en déduire un nombre de centimes, et « égal par défaut »
///    serait une affirmation non démontrée. L'appelant doit avoir écarté ces
///    valeurs en amont ; ce garde est un filet, pas une politique.
bool memesCentimes(double a, double b) {
  if (!a.isFinite || !b.isFinite) return false;
  return centimesDe(a) == centimesDe(b);
}

/// Égalité monétaire au centime, qui PRÉSERVE la distinction `null` / `0.0`.
///
/// `null` = « montant non établi » ; `0.0` = « montant officiellement nul ».
/// Les deux ne sont JAMAIS équivalents : les confondre effacerait une
/// information métier (un remboursement non établi n'est pas un remboursement
/// nul).
bool memeMontantOuTousDeuxNuls(double? a, double? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return memesCentimes(a, b);
}
