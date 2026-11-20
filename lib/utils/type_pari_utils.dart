// ═══════════════════════════════════════════════════════════════════════════
//  LOT A-0 — Reconnaissance du type de pari « Gagnant + Placé »
//
//  ⚠️  PORTÉE STRICTEMENT LIMITÉE.
//      Ce fichier ne normalise RIEN, ne convertit RIEN, ne fusionne RIEN.
//      Il répond uniquement à une question binaire : ce libellé désigne-t-il
//      un pari Gagnant + Placé ?
//
//  ── POURQUOI CE FICHIER EXISTE ────────────────────────────────────────────
//  Le pari « Gagnant + Placé » engage DEUX composantes financières distinctes
//  (une mise Gagnant + une mise Placé). Tant que le Lot B n'a pas traité les
//  deux composantes, aucune des écritures financières automatiques existantes
//  ne peut produire un gain G+P exact :
//
//    - `bet_bottom_sheet.dart:249` enregistre la cote GAGNANT comme cote du
//      pari, alors que le gain G+P dépend aussi de la cote PLACÉ ;
//    - `mes_paris_screen.dart:1309` / `paris_detail_screen.dart:676`
//      sélectionnent le dividende par `reduce(MAX)`, qui ne peut pas
//      attribuer le bon dividende à la bonne composante ;
//    - `alert_service.dart:2133` lit la cote Placé sur `rList.first`, donc
//      sur le mauvais cheval (l'ordre de `E_SIMPLE_PLACE` n'est pas le
//      classement officiel — voir `arrivee_pmu_ordonnee.dart:13-16`).
//
//  Le Lot A-0 empêche donc ces écritures de produire un gain G+P faux, SANS
//  toucher au calcul PMU. Il sera levé par le Lot B.
//
//  ── LES LIBELLÉS RECONNUS SONT MESURÉS, PAS SUPPOSÉS ─────────────────────
//  Trois libellés existent réellement dans le code :
//    'Gagnant+Placé'    → `bet_bottom_sheet.dart:128` (liste `_typesPari`),
//                         `mes_paris_screen.dart:2675`
//    'Gagnant + Placé'  → `gain_calculator.dart:457`
//    'Gagnant+Place'    → tolérance historique d'affichage
//
//  La comparaison est insensible à la casse et aux espaces de bord, comme le
//  font déjà les sites appelants (`typePari.toLowerCase()`).
//
//  ── CE QUE CE FICHIER NE FAIT PAS ─────────────────────────────────────────
//    - il ne reconnaît PAS les 11 autres libellés de `lib/` ;
//    - il ne supprime ni n'altère aucune information sportive ;
//    - il ne décide d'aucune règle métier : les appelants décident du sort
//      de l'écriture financière, ce helper ne fait que nommer la catégorie.
//
//  Aucune dépendance : fichier pur, testable sans Flutter.
// ═══════════════════════════════════════════════════════════════════════════

/// Les trois libellés réellement présents dans le code pour le pari
/// Gagnant + Placé, déjà normalisés (minuscules, sans espace de bord).
///
/// `grep -rn "Gagnant+Placé\|Gagnant + Placé\|Gagnant+Place" lib/`
/// → `bet_bottom_sheet.dart`, `mes_paris_screen.dart`, `gain_calculator.dart`
/// et les sites d'affichage qui recopient ces libellés.
const Set<String> kLibellesGagnantPlace = <String>{
  'gagnant+placé',
  'gagnant + placé',
  'gagnant+place',
};

/// Vrai si [typePari] désigne un pari **Gagnant + Placé**, c'est-à-dire un
/// pari à DEUX composantes financières dont le gain ne peut pas être calculé
/// de façon exacte tant que le Lot B n'a pas traité les deux composantes.
///
/// Renvoie `false` pour `null`, pour la chaîne vide et pour tout autre type
/// de pari — en particulier `'Simple Gagnant'` et `'Simple Placé'`, qui sont
/// des paris MONO-composante et restent traités normalement.
///
/// Cette fonction est PURE : aucun effet de bord, aucun accès disque,
/// aucun accès réseau, aucune dépendance à l'heure courante.
bool estTypeGagnantPlace(String? typePari) {
  if (typePari == null) return false;
  final normalise = typePari.trim().toLowerCase();
  if (normalise.isEmpty) return false;
  return kLibellesGagnantPlace.contains(normalise);
}
