// ═══════════════════════════════════════════════════════════════════════════
//  BLOC 1 — BEST BET : ESTIMATION AVANT COURSE, HONNÊTE PAR CONSTRUCTION
//
//  RÔLE
//  ────────────────────────────────────────────────────────────────────────
//  Cette classe ne calcule AUCUN dividende. Elle décide seulement s'il est
//  LÉGITIME d'afficher un chiffre avant la course, et à quelle condition.
//
//  LE DÉFAUT CORRIGÉ (mesuré dans `best_bet_screen.dart` avant correction)
//  ────────────────────────────────────────────────────────────────────────
//   1. `_changerMise` : `(c > 0 && c < 99) ? c : 2.5` → une cote de 2.5 était
//      INVENTÉE quand aucune cote n'était publiée, puis multipliée par la mise
//      et présentée comme « Gain estimé ».
//   2. `_buildTopCard` / `_BetRow` :
//      `(2.0 + (100.0 - scoreConfiance) / 20.0).clamp(1.5, 8.0)` → une cote
//      était DÉDUITE DU SCORE IA, sans aucun rapport avec un quelconque
//      rapport publié par le PMU.
//   3. Dans les deux cas, le chiffre obtenu était `mise × cote` pour TOUS les
//      types de pari, y compris Couplé, Tiercé, Quarté+ et Quinté+.
//
//  POURQUOI C'EST FAUX (règle métier PMU, non négociable)
//  ────────────────────────────────────────────────────────────────────────
//  La `cote` d'un partant est la cote du pari SIMPLE GAGNANT. Ce n'est pas un
//  dividende. Un Couplé, un Tiercé, un Quarté+ ou un Quinté+ possèdent leur
//  PROPRE rapport, calculé sur leur propre masse de mises : il est
//  structurellement d'un autre ordre de grandeur et n'a aucun rapport
//  arithmétique avec la cote Gagnant. Utiliser la cote Gagnant comme
//  dividende d'un Quinté+ ne serait pas une approximation : ce serait un
//  chiffre faux présenté comme une prévision.
//
//  RÈGLE APPLIQUÉE ICI
//  ────────────────────────────────────────────────────────────────────────
//   • Simple Gagnant + cote réellement publiée (0 < cote < 99)
//       → estimation autorisée, EXPLICITEMENT étiquetée comme estimation
//         avant course, non garantie, et de nature « cote », pas « rapport ».
//   • Tout autre cas (aucune cote, Simple Placé, Couplé, Tiercé, Quarté+,
//     Quinté+, « À surveiller »)
//       → AUCUN chiffre. `montant` reste `null` et un motif est fourni.
//         `null` n'est jamais affiché « 0 € ».
//
//  APRÈS COURSE, cette classe n'a plus rien à dire : c'est
//  `FinanceSimulateurOfficiel` qui rend le gain, le remboursement et le net,
//  à partir des rapports officiels. Aucun second moteur n'existe ici.
// ═══════════════════════════════════════════════════════════════════════════

/// Nature d'un montant affiché par Best Bet.
///
/// La distinction n'est pas cosmétique : elle indique à l'utilisateur — et au
/// code appelant — si le chiffre est une prévision ou un versement officiel.
enum NatureMontantBestBet {
  /// Montant issu des rapports OFFICIELS après la course (source : moteur).
  officielApresCourse,

  /// Prévision avant course, fondée sur la seule cote Gagnant publiée.
  estimationAvantCourse,

  /// Aucun montant ne peut être affiché honnêtement.
  nonEstimable,
}

/// Résultat d'une demande d'estimation avant course.
class EstimationBestBet {
  /// Nature du montant. `nonEstimable` ⇒ [montant] vaut `null`.
  final NatureMontantBestBet nature;

  /// Montant en euros, ou `null` quand rien ne peut être affirmé.
  final double? montant;

  /// Cote réellement utilisée. `null` dès qu'aucune cote n'est employée.
  final double? coteUtilisee;

  /// Phrase affichable sous le montant. Toujours renseignée.
  final String mention;

  const EstimationBestBet._({
    required this.nature,
    required this.montant,
    required this.coteUtilisee,
    required this.mention,
  });

  /// Aucun chiffre : [motif] explique pourquoi, en clair, à l'utilisateur.
  factory EstimationBestBet.nonEstimable(String motif) => EstimationBestBet._(
        nature: NatureMontantBestBet.nonEstimable,
        montant: null,
        coteUtilisee: null,
        mention: motif,
      );

  /// `true` si un montant est affichable.
  bool get aUnMontant => montant != null;

  /// `true` si le montant est une prévision (et non un versement officiel).
  bool get estUneEstimation =>
      nature == NatureMontantBestBet.estimationAvantCourse;

  /// Le seul type de pari pour lequel une cote publiée existe réellement.
  static const String typePariAvecCote = 'Simple Gagnant';

  /// Est-il légitime d'utiliser la cote d'un partant pour ce type de pari ?
  ///
  /// `true` UNIQUEMENT pour le Simple Gagnant. Toute autre réponse positive
  /// reviendrait à fabriquer un dividende.
  static bool coteUtilisablePour(String typePari) =>
      typePari.trim() == typePariAvecCote;

  /// Explique, en clair, pourquoi un type de pari n'a pas d'estimation.
  static String motifAbsenceEstimation(String typePari) {
    final t = typePari.trim();
    if (t == 'À surveiller' || t.isEmpty) {
      return 'Aucun pari conseillé sur cette course : pas de montant à estimer';
    }
    if (t == 'Simple Placé') {
      return 'Aucune cote Placé publiée : le gain ne peut pas être estimé '
          'avant la course';
    }
    if (t == 'Gagnant+Placé') {
      return 'Deux composantes distinctes (Gagnant et Placé) : le PMU ne '
          'publie pas de rapport combiné avant la course';
    }
    if (t == 'Couplé Gagnant' ||
        t == 'Couplé Placé' ||
        t == 'Couplé Ordre' ||
        t == 'Couplé Désordre') {
      return 'Le rapport de ce couplé dépend de sa propre masse de mises : '
          'la cote Gagnant ne le donne pas';
    }
    if (t == 'Tiercé' ||
        t == 'Tiercé Ordre' ||
        t == 'Tiercé Désordre' ||
        t == 'Quarté+' ||
        t == 'Quinté+') {
      return 'Le PMU ne publie aucun rapport avant course pour ce type : '
          'le gain ne peut pas être estimé';
    }
    return 'Type de pari non reconnu par le moteur officiel : '
        'aucun montant ne peut être estimé';
  }

  /// Décide de l'affichage avant course.
  ///
  /// [typePari]     : libellé exact produit par `cascadeRecommandation`.
  /// [mise]         : mise que l'utilisateur envisage.
  /// [coteGagnant]  : `ZtPartant.coteDecimale` (99.0 = cote absente).
  static EstimationBestBet avantCourse({
    required String typePari,
    required double mise,
    required double coteGagnant,
  }) {
    if (!coteUtilisablePour(typePari)) {
      return EstimationBestBet.nonEstimable(motifAbsenceEstimation(typePari));
    }
    // La sentinelle mesurée de `ZtPartant.coteDecimale` est 99.0 quand la cote
    // est vide. Elle n'est jamais convertie en cote « plausible ».
    if (!(coteGagnant > 0) || coteGagnant >= 99) {
      return EstimationBestBet.nonEstimable(
        'Aucune cote Gagnant publiée pour ce partant : '
        'le gain ne peut pas être estimé',
      );
    }
    if (!(mise > 0)) {
      return EstimationBestBet.nonEstimable(
        'Mise nulle ou négative : aucune estimation',
      );
    }
    return EstimationBestBet._(
      nature: NatureMontantBestBet.estimationAvantCourse,
      montant: mise * coteGagnant,
      coteUtilisee: coteGagnant,
      mention: 'Estimation avant course (cote Gagnant '
          '×${coteGagnant.toStringAsFixed(1)}) — non garantie',
    );
  }
}
