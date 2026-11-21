// ═══════════════════════════════════════════════════════════════════════════
//  LOT G+P — DÉCISION DE VALIDATION MANUELLE D'UN TICKET « GAGNANT + PLACÉ »
//
//  Module VOLONTAIREMENT PUR : aucune I/O, aucun widget, aucun état.
//  Il répond à UNE question, et n'en pose aucune autre :
//
//      « Les dialogues de validation manuelle peuvent-ils écrire une mise et
//        un résultat financiers sur CE ticket, avec les données réellement
//        enregistrées sur ce ticket ? »
//
//  ── LE DÉFAUT CORRIGÉ (mesuré) ────────────────────────────────────────────
//  Les deux dialogues `predictions_screen._validerDialog` et
//  `profile_historique_tab._validerDialog` faisaient :
//
//      double mise = pred.montantMise > 0 ? pred.montantMise : 10.0;
//
//  Pour un `Gagnant+Placé`, `montantMise` vaut 0 pour tout ticket créé par
//  `race_detail_screen.dart:348-359` (le champ n'est pas passé) : la formule
//  ci-dessus engageait donc 10 € **inventés**, alors que le pari en engage
//  DEUX composantes (10 € Gagnant + 10 € Placé = 20 €) et que le modèle porte
//  déjà ces deux montants dans `miseGagnant` / `misePlace`.
//
//  ── LA RÈGLE APPLIQUÉE ────────────────────────────────────────────────────
//  Pour un Gagnant+Placé, la validation manuelle est refusée SAUF si les deux
//  composantes sont établies :
//
//    1. les deux mises existent et sont strictement positives ;
//    2. le type est bien un Gagnant+Placé (délégué à `estTypeGagnantPlace`,
//       Lot A-0, seule autorité sur ce libellé — jamais redéfini ici).
//
//  Si l'une des deux mises manque, on NE DEVINE PAS : on refuse, avec un
//  motif explicite. Une composante manquante n'est ni doublée, ni remplacée
//  par l'autre, ni complétée par 10 €.
//
//  ── CE QUE CE MODULE NE FAIT PAS ──────────────────────────────────────────
//    - il ne modifie AUCUNE formule financière : il n'en contient aucune.
//      La mise totale lui est fournie par `gain_mise_calculator.dart`
//      (calculateur B, `miseTotaleEngagee`), qui est l'autorité existante ;
//    - il ne lit ni ne calcule aucun dividende : la question du résultat
//      reste entièrement à l'appelant (voir point 6 du mandat — un dividende
//      ambigu ne doit jamais décider d'un gagnant/perdant) ;
//    - il ne touche ni la décision sportive du ticket, ni la garde A-0, ni
//      les apprentissages IA ;
//    - il n'écrit rien et ne migre rien : les tickets historiques restent
//      STRICTEMENT intacts.
//
//  ── RÉUTILISATION (exigence du mandat, point 2) ───────────────────────────
//   • `pmu_models.dart`      → champs `miseGagnant` / `misePlace` et getter
//                              dérivé `miseTotaleEngagee` ;
//   • `gain_mise_calculator.dart` → `miseTotaleEngagee(List<ComposanteMise>)`
//                              et `composantesDepuisTicket(...)` (calculateur B) ;
//   • `type_pari_utils.dart` → `estTypeGagnantPlace` (Lot A-0).
//  Aucun troisième calcul n'est créé.
// ═══════════════════════════════════════════════════════════════════════════

import '../models/pmu_models.dart';
import '../services/gain_mise_calculator.dart';
import 'type_pari_utils.dart';

/// Issue de la décision de validation manuelle.
///
/// Exactement deux états, jamais un troisième « à moitié valide » :
///  • [ValidationManuelleAutorisee] : la mise totale engagée est CONNUE ;
///  • [ValidationManuelleRefusee]  : elle ne l'est pas, et AUCUN montant n'est
///    exposé — l'appelant ne peut donc pas en inventer un par accident.
sealed class DecisionValidationManuelle {
  const DecisionValidationManuelle();

  /// `true` seulement pour [ValidationManuelleAutorisee].
  bool get autorisee => this is ValidationManuelleAutorisee;
}

/// Validation autorisée : [miseTotale] est la somme RÉELLE des composantes
/// (20 € pour un Gagnant+Placé à 10 € + 10 €, jamais 10 €).
final class ValidationManuelleAutorisee extends DecisionValidationManuelle {
  /// Mise réellement engagée, en euros. Toujours > 0.
  final double miseTotale;

  /// `true` si le ticket porte DEUX composantes distinctes (Gagnant+Placé).
  final bool deuxComposantes;

  const ValidationManuelleAutorisee({
    required this.miseTotale,
    required this.deuxComposantes,
  });

  @override
  String toString() => 'ValidationManuelleAutorisee(mise: $miseTotale, '
      'deuxComposantes: $deuxComposantes)';
}

/// Validation refusée, avec un motif lisible destiné à l'utilisateur.
///
/// ❗Aucun montant n'est porté : il n'y a rien à afficher puisqu'il n'y a
///   rien de connu. C'est ce qui rend l'invention d'une mise structurellement
///   impossible côté appelant.
final class ValidationManuelleRefusee extends DecisionValidationManuelle {
  /// Motif affichable tel quel.
  final String motif;

  const ValidationManuelleRefusee(this.motif);

  @override
  String toString() => 'ValidationManuelleRefusee($motif)';
}

/// Décide si un ticket peut recevoir une validation financière manuelle.
///
/// ── COMPORTEMENT, PAR CAS ─────────────────────────────────────────────────
//  • **Pas un Gagnant+Placé** : la mise engagée est `montantMise`.
///   Si elle est nulle ou absente, la validation est REFUSÉE — c'est le
///   remplacement par 10 € qui est supprimé, pas la règle métier.
///  • **Gagnant+Placé, deux mises présentes et > 0** : autorisée, mise totale
///   = somme réelle des deux (calculateur B).
///  • **Gagnant+Placé, une seule mise** : refusée, motif nommant la composante
///   manquante.
///  • **Gagnant+Placé, aucune mise** : refusée, motif explicite.
///
/// Cette fonction est PURE : aucun effet de bord, aucun accès disque, aucun
/// accès réseau, aucune dépendance à l'heure courante.
DecisionValidationManuelle deciderValidationManuelle(UserPrediction pred) {
  final estGagnantPlace = estTypeGagnantPlace(pred.typePari);

  if (!estGagnantPlace) {
    // ── Pari mono-composante ────────────────────────────────────────────────
    final mise = pred.montantMise;
    if (mise <= 0) {
      return const ValidationManuelleRefusee(
        'Aucune mise n\'est enregistrée sur ce ticket : la validation '
        'financière est impossible. Aucun montant ne sera inventé.',
      );
    }
    return ValidationManuelleAutorisee(
      miseTotale: mise,
      deuxComposantes: false,
    );
  }

  // ── Gagnant + Placé : les DEUX composantes doivent être établies ─────────
  final miseG = pred.miseGagnant;
  final miseP = pred.misePlace;

  if (miseG == null && miseP == null) {
    return const ValidationManuelleRefusee(
      'Ce ticket Gagnant + Placé ne porte aucune des deux mises '
      '(Gagnant et Placé) : la mise réellement engagée est inconnue. '
      'Aucun montant ne sera inventé ni déduit.',
    );
  }

  if (miseG == null) {
    return const ValidationManuelleRefusee(
      'La mise Gagnant de ce ticket Gagnant + Placé n\'est pas enregistrée : '
      'la mise réellement engagée est inconnue. '
      'Aucun montant ne sera inventé ni déduit.',
    );
  }

  if (miseP == null) {
    return const ValidationManuelleRefusee(
      'La mise Placé de ce ticket Gagnant + Placé n\'est pas enregistrée : '
      'la mise réellement engagée est inconnue. '
      'Aucun montant ne sera inventé ni déduit.',
    );
  }

  // Les deux composantes existent — mais une mise à 0 n'engage rien.
  if (miseG <= 0 || miseP <= 0) {
    return const ValidationManuelleRefusee(
      'Une des deux mises de ce ticket Gagnant + Placé est nulle : '
      'la mise réellement engagée ne peut pas être établie. '
      'Aucun montant ne sera inventé.',
    );
  }

  // ── Mise totale : déléguée au calculateur B, jamais recalculée ici ───────
  final composantes = composantesDepuisTicket(
    estGagnantPlace: true,
    miseEngagee: pred.montantMise,
    miseGagnant: miseG,
    misePlace: miseP,
    rapport: null, // aucun rapport officiel n'est identifié à ce stade
  );
  final total = miseTotaleEngagee(composantes);

  if (total == null || total <= 0) {
    return const ValidationManuelleRefusee(
      'La mise totale engagée de ce ticket Gagnant + Placé n\'est pas '
      'calculable. Aucun montant ne sera inventé.',
    );
  }

  return ValidationManuelleAutorisee(
    miseTotale: total,
    deuxComposantes: true,
  );
}
