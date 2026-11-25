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

// ═══════════════════════════════════════════════════════════════════════════
//  LOT C1 — Reconnaissance de l'ÉTAT SANS PARI RECOMMANDÉ
//
//  ⚠️  PORTÉE STRICTEMENT LIMITÉE.
//      Ce prédicat ne normalise RIEN, ne convertit RIEN, ne réécrit RIEN.
//      Il répond à une seule question : ce libellé désigne-t-il un ticket
//      pour lequel AUCUN pari n'a été recommandé — donc un ticket sur lequel
//      aucune écriture financière n'a de sens ?
//
//  ── POURQUOI CE PRÉDICAT EXISTE ───────────────────────────────────────────
//  Deux valeurs de `UserPrediction.typePari` ne désignent pas un pari :
//
//    • `'À surveiller'` — abstention explicite de l'IA. Sens métier prouvé
//      par `conseils_screen.dart:1284` :
//        `typePari = 'À surveiller'; sousTitrePari = 'Scores insuffisants
//         — passer';`
//      L'application elle-même demande de NE PAS parier.
//
//    • `''` — type absent. Produit par `pmu_models.dart:630`
//      (`json['typePari'] as String? ?? ''`) sur un ticket restauré dont le
//      champ manque. Un type absent ne désigne aucun pari connu.
//
//  ── MESURES QUI FONDENT CES DEUX VALEURS (et excluent les autres) ─────────
//  • `grep -rn "typePari: 'À surveiller'\|typePari = 'À surveiller'" lib/`
//    → 0 écriture directe dans `UserPrediction` ; la valeur n'arrivait que par
//      l'ancien `race_detail_screen.dart:59` (`_betType = pred.typePari`),
//      **supprimé en BL1-A18** — la provenance est donc HISTORIQUE. La valeur
//      reste traitée parce que des tickets déjà enregistrés la portent, et
//      parce qu'une sauvegarde ancienne peut la restaurer ;
//  • `grep "UserPrediction(" -A 12 lib/ test/ | grep "À surveiller"`
//    → AUCUNE occurrence (aucun test n'exerce ce cas) ;
//  • `'Inconnu'` n'est JAMAIS écrit dans `UserPrediction` : c'est seulement
//    un défaut de LECTURE (`ia_memory_service.dart:5488`) et il désigne, lui,
//    un pari dont le type n'a pas pu être identifié — pas une abstention ;
//  • `'Placé'` n'apparaît qu'une fois dans tout `lib/`
//    (`ia_memory_service.dart:7259`, un emoji) : entrée d'affichage morte,
//    jamais une valeur écrite.
//
//  ── CE QUE CE FICHIER NE FAIT PAS ─────────────────────────────────────────
//    - il ne classe PAS `'Inconnu'` comme « sans pari » : un type inconnu
//      n'est pas une abstention, et le confondre reviendrait à effacer un
//      pari réel dont on ignore seulement l'étiquette ;
//    - il ne reconnaît PAS les libellés de `Gagnant + Placé`, traités
//      séparément par [estTypeGagnantPlace] (Lot A-0) ;
//    - il n'écrit rien, ne migre rien, ne supprime rien : les tickets
//      historiques restent STRICTEMENT intacts ;
//    - il ne décide d'aucune règle métier : les appelants décident du sort
//      de l'écriture financière, ce helper ne fait que nommer la catégorie.
//
//  Aucune dépendance : fichier pur, testable sans Flutter.
// ═══════════════════════════════════════════════════════════════════════════

/// Le libellé d'abstention produit par l'IA, avec son accent exact.
///
/// `À` = U+00C0. Une variante sans accent (`'A surveiller'`) ne correspond à
/// AUCUNE donnée réellement produite — mesuré par
/// `test/v41_a44_abstention_stats_test.dart:504`.
const String kLibelleSansPariRecommande = 'À surveiller';

/// Vrai si [typePari] désigne un ticket sur lequel **aucun pari n'a été
/// recommandé**, et qui ne peut donc porter ni mise, ni gain, ni perte.
///
/// Renvoie `true` pour :
///   • `'À surveiller'` (comparaison insensible à la casse et aux espaces) ;
///   • la chaîne vide ou composée uniquement d'espaces (type absent).
///
/// Renvoie `false` pour `null` — un ticket dont le champ est `null` n'existe
/// pas dans ce modèle (`fromJson` applique `?? ''`), et `null` ne doit pas
/// être silencieusement assimilé à une abstention par un appelant qui aurait
/// simplement oublié de renseigner l'argument.
///
/// Renvoie `false` pour TOUT autre libellé, y compris `'Inconnu'` : un type
/// inconnu n'est pas une abstention (voir l'en-tête ci-dessus).
///
/// Cette fonction est PURE : aucun effet de bord, aucun accès disque,
/// aucun accès réseau, aucune dépendance à l'heure courante.
bool estEtatSansPariRecommande(String? typePari) {
  if (typePari == null) return false;
  final normalise = typePari.trim();
  if (normalise.isEmpty) return true;
  return normalise.toLowerCase() == kLibelleSansPariRecommande.toLowerCase();
}
