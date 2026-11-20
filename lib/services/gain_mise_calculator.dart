// ═══════════════════════════════════════════════════════════════════════════
//  SOUS-LOT B — ARITHMÉTIQUE DES MISES ET DES GAINS
//
//  Module VOLONTAIREMENT PUR : aucune I/O, aucun état, aucun widget.
//  Il répond à une question unique, vérifiable :
//
//      « Pour CE ticket, avec CES mises réellement engagées et CES rapports
//        réellement identifiés, quel est le retour brut, quelle est la mise
//        totale, quel est le bénéfice net ? »
//
//  Règles de conception (mandat §2, §3, §4-B) :
//
//   1. AUCUNE mise par défaut inventée : une mise absente n'est pas 10 €.
//      C'est `null`, et le calcul n'est pas fait.
//   2. AUCUN multiplicateur fictif : pas de ×2, ×2.5, ×3 de repli. Un rapport
//      absent ⇒ retour `null` et motif explicite.
//   3. MISE TOTALE = SOMME RÉELLE des composantes. Un « Gagnant+Placé » à
//      10 € saisis engage 10 € Gagnant + 10 € Placé = **20 €**, jamais 10 €.
//   4. RETOUR BRUT ≠ BÉNÉFICE NET. On ne les mélange jamais : retour brut =
//      ce que rend le billet, mise incluse ; bénéfice net = retour − mise.
//   5. Échec fermé : si une seule composante nécessaire est inconnue, le
//      retour complet est `null` — on n'affiche pas un montant partiel qui
//      ferait croire à un gain officiel.
// ═══════════════════════════════════════════════════════════════════════════

/// Une composante de mise d'un ticket : combien est engagé, et à quel rapport.
///
/// Un ticket « Gagnant+Placé » a DEUX composantes. Un Simple Gagnant en a une.
/// Un pari combiné (Tiercé…) en a une seule, dont la mise porte sur la
/// combinaison entière.
class ComposanteMise {
  /// Mise réellement engagée sur cette composante, en euros.
  ///
  /// ❗`null` signifie « non renseignée », PAS « zéro ». Une mise inconnue ne
  ///    peut pas être remplacée par une valeur par défaut.
  final double? mise;

  /// Rapport pour 1 € engagé, en euros. `null` si aucun rapport officiel n'a
  /// été identifié pour cette composante.
  final double? rapport;

  const ComposanteMise({required this.mise, required this.rapport});

  /// `true` si la composante est entièrement calculable.
  bool get complete => mise != null && mise! > 0 && rapport != null;

  /// Retour brut de cette composante. `null` si incomplète — jamais 0.
  double? get retourBrut => complete ? mise! * rapport! : null;

  @override
  String toString() => 'ComposanteMise(mise: $mise, rapport: $rapport)';
}

/// Résultat d'un calcul de gain, avec son motif quand il n'est pas calculable.
///
/// Un seul des deux états est possible : soit `calculable == true` et les
/// montants sont renseignés, soit `calculable == false` et AUCUN montant
/// n'est exposé. Il n'existe pas d'état « calculé à moitié ».
class ResultatGain {
  /// Mise totale réellement engagée, en euros. Toujours connue si au moins une
  /// composante a une mise.
  final double? miseTotale;

  /// Retour brut (mise incluse), en euros. `null` si non calculable.
  final double? retourBrut;

  /// Bénéfice net = retour brut − mise totale. `null` si non calculable.
  final double? beneficeNet;

  /// Motif lisible quand le calcul n'aboutit pas.
  final String motif;

  const ResultatGain._({
    required this.miseTotale,
    required this.retourBrut,
    required this.beneficeNet,
    required this.motif,
  });

  /// Construit un résultat calculable.
  factory ResultatGain.calculable({
    required double miseTotale,
    required double retourBrut,
  }) {
    return ResultatGain._(
      miseTotale: miseTotale,
      retourBrut: retourBrut,
      beneficeNet: retourBrut - miseTotale,
      motif: '',
    );
  }

  /// Construit un résultat non calculable, avec son motif.
  factory ResultatGain.nonCalculable(String motif, {double? miseTotale}) {
    return ResultatGain._(
      miseTotale: miseTotale,
      retourBrut: null,
      beneficeNet: null,
      motif: motif,
    );
  }

  bool get calculable => retourBrut != null;

  @override
  String toString() => calculable
      ? 'ResultatGain(mise: $miseTotale, retour: $retourBrut, '
          'net: $beneficeNet)'
      : 'ResultatGain(non calculable: $motif)';
}

/// Mise totale **réellement engagée** d'un ensemble de composantes.
///
/// Rend `null` si aucune mise n'est renseignée. Rend `null` aussi si une
/// composante attendue a une mise inconnue : on ne peut pas annoncer un total
/// en laissant croire qu'il est complet.
double? miseTotaleEngagee(List<ComposanteMise> composantes) {
  if (composantes.isEmpty) return null;
  var total = 0.0;
  var auMoinsUne = false;
  for (final c in composantes) {
    if (c.mise == null) return null; // composante incomplète ⇒ total inconnu
    total += c.mise!;
    auMoinsUne = true;
  }
  return auMoinsUne ? total : null;
}

/// Calcul du gain d'un ticket à partir de ses composantes.
///
/// Le retour brut n'est rendu que si **toutes** les composantes nécessaires
/// sont complètes. Sinon le résultat est non calculable, avec un motif qui
/// distingue les deux causes :
///  • mise non renseignée → « Mises non renseignées » (l'utilisateur peut agir),
///  • rapport non identifié → « En attente du rapport officiel » (il faut
///    attendre la publication).
///
/// ❗Aucune multiplication par 2, 2.5 ou 3 n'est jamais appliquée ici.
ResultatGain calculerGain({
  required List<ComposanteMise> composantes,
}) {
  if (composantes.isEmpty) {
    return ResultatGain.nonCalculable(
      'Aucune composante de mise enregistrée pour ce ticket.',
    );
  }

  final total = miseTotaleEngagee(composantes);
  if (total == null) {
    final manquantes = composantes.where((c) => c.mise == null).length;
    return ResultatGain.nonCalculable(
      manquantes == composantes.length
          ? 'Mises non renseignées : aucun montant ne peut être calculé.'
          : 'Une des mises engagées est non renseignée : le total engagé est '
              'inconnu, aucun montant ne peut être calculé.',
    );
  }

  var retour = 0.0;
  for (final c in composantes) {
    final r = c.retourBrut;
    if (r == null) {
      return ResultatGain.nonCalculable(
        'En attente du rapport officiel : le rapport de la combinaison jouée '
        'n\'a pas été identifié, aucun montant ne peut être calculé.',
        miseTotale: total,
      );
    }
    retour += r;
  }

  return ResultatGain.calculable(miseTotale: total, retourBrut: retour);
}

/// Construit les composantes d'un ticket depuis ses champs `TrackedCourse`.
///
/// Gère les trois cas réels de l'application :
///  • **Gagnant + Placé** : deux composantes, avec les mises DISTINCTES
///    `miseGagnant` / `misePlace` — jamais `miseEngagee` divisée par deux ;
///  • **Simple Gagnant / Simple Placé / combiné** : une composante, mise
///    `miseEngagee`, rapport unique ;
///  • **Gagnant + Placé incomplet** (une seule des deux mises) : on rend les
///    deux composantes, dont une avec `mise: null`, ce qui rend le total
///    inconnu — plutôt que de faire comme si le ticket n'engageait qu'une mise.
///
/// `rapport` est le rapport pour 1 € déjà identifié (voir
/// `gain_ticket_calculator.dart`). `null` ⇒ « en attente du rapport officiel ».
List<ComposanteMise> composantesDepuisTicket({
  required bool estGagnantPlace,
  required double? miseEngagee,
  required double? miseGagnant,
  required double? misePlace,
  required double? rapport,
  double? rapportGagnant,
  double? rapportPlace,
}) {
  if (estGagnantPlace) {
    return [
      ComposanteMise(
        mise: miseGagnant,
        rapport: rapportGagnant ?? rapport,
      ),
      ComposanteMise(
        mise: misePlace,
        rapport: rapportPlace ?? rapport,
      ),
    ];
  }
  return [
    ComposanteMise(mise: miseEngagee, rapport: rapport),
  ];
}

/// Gain **potentiel** : ce que le ticket rendrait si la combinaison jouée était
/// effectivement payée au rapport connu.
///
/// ❗Ce n'est PAS un gain gagné. Il est calculable AVANT la course (à partir
///    des cotes) comme APRÈS (à partir des rapports), et doit être libellé
///    « Gain potentiel » — jamais « gain réel » ni « gain officiel ».
ResultatGain calculerGainPotentiel({
  required List<ComposanteMise> composantes,
}) =>
    calculerGain(composantes: composantes);
