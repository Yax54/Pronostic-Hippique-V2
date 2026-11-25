// ═══════════════════════════════════════════════════════════════════════════
//  BLOC 1 — PÉRIMÈTRE FINANCIER : SIMULATEUR OFFICIEL UNIQUE
//
//  RÔLE
//  ────────────────────────────────────────────────────────────────────────
//  Une SEULE couche de simulation financière pour Backtesting, Martingale,
//  Best Bet (après course) et, plus tard, ROI / Laboratoire IA (BLOC 2).
//
//  Elle ne calcule RIEN elle-même : elle délègue intégralement à
//  `chaine_financiere_officielle.dart`, qui délègue elle-même au moteur
//  officiel `resoudreGainTicketDepuisDonnees` → `resoudreGainTicket`.
//
//     producteur PMU → repository partagé → chaîne → MOTEUR OFFICIEL
//
//  Aucun second moteur financier n'est créé. Aucun multiplicateur, aucune
//  cote estimée, aucun dividende inventé n'existe dans ce fichier.
//
//  EFFETS DE BORD : AUCUN, par ABSENCE D'IMPORT.
//  Ce fichier n'importe ni `ia_memory_service.dart`, ni un enregistreur de
//  verdict, ni un service de notifications, ni un service « Mes Paris ».
//  Il ne peut donc pas écrire dans un ticket réel, ni déclencher une
//  notification de gain tardif, ni modifier une décision utilisateur, ni
//  déclencher un apprentissage. Ce n'est pas une convention : c'est une
//  propriété du graphe d'imports.
// ═══════════════════════════════════════════════════════════════════════════

import 'chaine_financiere_officielle.dart';
import 'resultat_officiel_repository.dart';

/// Sort du pari simulé. Trois états, jamais deux.
///
/// `nonDeterminee` n'est JAMAIS converti en perte, ni en gain nul : c'est
/// précisément ce que le mandat interdit (« ne jamais transformer une absence
/// de rapport en perte, en gain nul ou en dividende fictif »).
enum SortPariSimule {
  /// Pari gagnant : le moteur officiel a attribué un gain.
  gagne,

  /// Pari perdant : le moteur officiel a établi la perte sur preuve complète.
  perdu,

  /// Résultat officiel indisponible ou insuffisant. Ni gain ni perte.
  nonDeterminee,
}

/// Résultat financier d'UN pari simulé, tel que le moteur officiel l'a rendu.
///
/// ⚠️ Convention de signe, identique pour tous les consommateurs :
///   • [gain] est le GAIN BRUT rendu par le moteur (`VerdictGain.total`),
///     sans déduction de la mise et sans remboursement ;
///   • [remboursement] est séparé et n'est jamais fondu dans le gain ;
///   • [resultatNet] = gain + remboursement − mise. C'est la seule valeur
///     destinée à une addition de trésorerie.
///   • `null` signifie « indéterminé », jamais 0.
class ResultatFinancierSimule {
  final String courseKey;
  final String typePari;
  final List<int> numerosJoues;
  final double mise;

  final SortPariSimule sort;
  final double? gain;
  final double? remboursement;
  final double? resultatNet;

  /// Cause technique lorsque le sort est indéterminé (motif du moteur ou de
  /// la chaîne). `null` quand le sort est déterminé.
  final String? motifIndetermination;

  /// Vrai si le résultat a été servi depuis le stockage local, sans réseau.
  final bool servieDepuisStockage;

  const ResultatFinancierSimule({
    required this.courseKey,
    required this.typePari,
    required this.numerosJoues,
    required this.mise,
    required this.sort,
    this.gain,
    this.remboursement,
    this.resultatNet,
    this.motifIndetermination,
    this.servieDepuisStockage = false,
  });

  bool get estDetermine => sort != SortPariSimule.nonDeterminee;

  /// Indicateur destiné aux agrégations : ne compter que ce qui est établi.
  bool get compteDansLesStats => estDetermine;

  @override
  String toString() => 'ResultatFinancierSimule($courseKey | $typePari | '
      'n=$numerosJoues | mise=$mise | ${sort.name} | gain=$gain | '
      'remb=$remboursement | net=$resultatNet)';
}

/// Agrégat d'une série de paris simulés.
///
/// Il sépare STRICTEMENT ce que le mandat exige de distinguer :
/// mises, gains, remboursements, résultat net, et — à part — tout ce qui est
/// indéterminé. Un indéterminé n'est NI un gain NI une perte : il est compté,
/// affiché, et EXCLU du résultat net.
class BilanFinancierSimule {
  final int nbParis;
  final int nbGagnes;
  final int nbPerdus;
  final int nbNonDetermines;

  /// Somme des mises RÉELLEMENT engagées sur des paris DÉTERMINÉS.
  /// Les mises des paris indéterminés sont comptées séparément : les inclure
  /// ici reviendrait à les traiter comme des pertes.
  final double misesEngagees;
  final double misesIndeterminees;

  final double gainsBruts;
  final double remboursements;
  final double resultatNet;

  const BilanFinancierSimule({
    required this.nbParis,
    required this.nbGagnes,
    required this.nbPerdus,
    required this.nbNonDetermines,
    required this.misesEngagees,
    required this.misesIndeterminees,
    required this.gainsBruts,
    required this.remboursements,
    required this.resultatNet,
  });

  const BilanFinancierSimule.vide()
      : nbParis = 0,
        nbGagnes = 0,
        nbPerdus = 0,
        nbNonDetermines = 0,
        misesEngagees = 0,
        misesIndeterminees = 0,
        gainsBruts = 0,
        remboursements = 0,
        resultatNet = 0;

  /// Couverture officielle : part des paris dont le sort est ÉTABLI.
  ///
  /// C'est l'indicateur qui empêche de présenter un ROI flatteur calculé sur
  /// trois courses déterminées et cinquante indéterminées.
  double get couvertureOfficielle =>
      nbParis == 0 ? 0.0 : (nbGagnes + nbPerdus) / nbParis * 100.0;

  /// ROI calculé UNIQUEMENT sur les paris déterminés. `null` si aucun.
  ///
  /// `null` ≠ 0 : un ROI inconnu n'est pas un ROI nul.
  double? get roi =>
      misesEngagees <= 0 ? null : resultatNet / misesEngagees * 100.0;

  /// Vrai si la couverture est insuffisante pour conclure quoi que ce soit.
  /// Seuil volontairement GROSSIER et DÉCLARÉ : en dessous de 50 % de paris
  /// établis, aucun ROI ne doit être présenté comme représentatif.
  bool get couvertureInsuffisante => couvertureOfficielle < 50.0;

  static BilanFinancierSimule depuis(List<ResultatFinancierSimule> paris) {
    var nbG = 0, nbP = 0, nbN = 0;
    var mises = 0.0, misesInd = 0.0, gains = 0.0, rembs = 0.0, net = 0.0;
    for (final p in paris) {
      switch (p.sort) {
        case SortPariSimule.gagne:
          nbG++;
          mises += p.mise;
          gains += p.gain ?? 0.0;
          rembs += p.remboursement ?? 0.0;
          net += p.resultatNet ?? 0.0;
        case SortPariSimule.perdu:
          nbP++;
          mises += p.mise;
          net += p.resultatNet ?? 0.0;
        case SortPariSimule.nonDeterminee:
          nbN++;
          // ⚠️ La mise part dans un compteur SÉPARÉ : elle n'est ni perdue
          //    ni engagée « pour de vrai » dans le bilan.
          misesInd += p.mise;
      }
    }
    return BilanFinancierSimule(
      nbParis: paris.length,
      nbGagnes: nbG,
      nbPerdus: nbP,
      nbNonDetermines: nbN,
      misesEngagees: mises,
      misesIndeterminees: misesInd,
      gainsBruts: gains,
      remboursements: rembs,
      resultatNet: net,
    );
  }
}

/// Point d'entrée UNIQUE de toute simulation financière.
///
/// Aucune méthode de cette classe ne calcule un dividende : toutes délèguent
/// à `resoudrePariSimule`, qui délègue au moteur officiel.
class FinanceSimulateurOfficiel {
  const FinanceSimulateurOfficiel._();

  /// Simule UN pari sur UNE course, à partir de son `courseKey` de production
  /// (`'R1C5_01072025'`, format produit par `buildCourseKey`).
  ///
  /// [autoriserReseau] : `true` permet au maximum UN échange réseau, et
  /// seulement si le repository partagé ne porte pas déjà un résultat
  /// exploitable. Les appels suivants sur la même course sont servis depuis le
  /// stockage — c'est ce qui rend une boucle de backtesting supportable.
  static Future<ResultatFinancierSimule> simulerPari({
    required String courseKey,
    required String typePari,
    required List<int> numerosJoues,
    required double mise,
    bool autoriserReseau = true,
  }) async {
    if (mise <= 0) {
      return ResultatFinancierSimule(
        courseKey: courseKey,
        typePari: typePari,
        numerosJoues: numerosJoues,
        mise: mise,
        sort: SortPariSimule.nonDeterminee,
        motifIndetermination: 'mise invalide ($mise) : '
            'aucune résolution financière possible',
      );
    }
    if (numerosJoues.isEmpty) {
      return ResultatFinancierSimule(
        courseKey: courseKey,
        typePari: typePari,
        numerosJoues: numerosJoues,
        mise: mise,
        sort: SortPariSimule.nonDeterminee,
        motifIndetermination: 'aucun numéro joué',
      );
    }

    final identite = IdentiteCoursePmu.depuisCourseKey(courseKey);
    if (identite == null || !identite.estValide) {
      return ResultatFinancierSimule(
        courseKey: courseKey,
        typePari: typePari,
        numerosJoues: numerosJoues,
        mise: mise,
        sort: SortPariSimule.nonDeterminee,
        motifIndetermination:
            'identité de course indéterminable depuis « $courseKey »',
      );
    }

    final resolution = await resoudrePariSimule(
      identite: identite,
      libelleTypePari: typePari,
      numerosJoues: numerosJoues,
      mise: mise,
      autoriserReseau: autoriserReseau,
    );

    if (resolution.estNonDeterminee) {
      return ResultatFinancierSimule(
        courseKey: courseKey,
        typePari: typePari,
        numerosJoues: numerosJoues,
        mise: mise,
        sort: SortPariSimule.nonDeterminee,
        motifIndetermination: resolution.explication,
        servieDepuisStockage: resolution.servieDepuisStockage,
      );
    }

    // Ici, le moteur a tranché. On transporte SES chiffres, sans retouche.
    final gain = resolution.gain; // brut, sans mise ni remboursement
    final remb = resolution.remboursement ?? 0.0;
    final net = (gain ?? 0.0) + remb - mise;

    return ResultatFinancierSimule(
      courseKey: courseKey,
      typePari: typePari,
      numerosJoues: numerosJoues,
      mise: mise,
      sort: resolution.estGagnant ? SortPariSimule.gagne : SortPariSimule.perdu,
      gain: gain,
      remboursement: remb,
      resultatNet: net,
      servieDepuisStockage: resolution.servieDepuisStockage,
    );
  }

  /// Simule un pari Gagnant + Placé sur une MÊME course, avec deux mises
  /// DISTINCTES.
  ///
  /// Le moteur refuse une mise agrégée (C6) : ce paramétrage est repris tel
  /// quel, sans le contourner.
  static Future<ResultatFinancierSimule> simulerGagnantPlace({
    required String courseKey,
    required int numero,
    required double miseGagnant,
    required double misePlace,
    bool autoriserReseau = true,
  }) async {
    final miseTotale = miseGagnant + misePlace;
    final identite = IdentiteCoursePmu.depuisCourseKey(courseKey);
    if (identite == null || !identite.estValide) {
      return ResultatFinancierSimule(
        courseKey: courseKey,
        typePari: 'Gagnant+Placé',
        numerosJoues: <int>[numero],
        mise: miseTotale,
        sort: SortPariSimule.nonDeterminee,
        motifIndetermination:
            'identité de course indéterminable depuis « $courseKey »',
      );
    }

    final resolution = await resoudrePariGagnantPlace(
      identite: identite,
      libelleTypePari: 'Gagnant+Placé',
      numerosJoues: <int>[numero],
      miseGagnant: miseGagnant,
      misePlace: misePlace,
      autoriserReseau: autoriserReseau,
    );

    if (resolution.estNonDeterminee) {
      return ResultatFinancierSimule(
        courseKey: courseKey,
        typePari: 'Gagnant+Placé',
        numerosJoues: <int>[numero],
        mise: miseTotale,
        sort: SortPariSimule.nonDeterminee,
        motifIndetermination: resolution.explication,
        servieDepuisStockage: resolution.servieDepuisStockage,
      );
    }

    final gain = resolution.gain;
    final remb = resolution.remboursement ?? 0.0;
    final net = (gain ?? 0.0) + remb - miseTotale;

    return ResultatFinancierSimule(
      courseKey: courseKey,
      typePari: 'Gagnant+Placé',
      numerosJoues: <int>[numero],
      mise: miseTotale,
      sort: resolution.estGagnant ? SortPariSimule.gagne : SortPariSimule.perdu,
      gain: gain,
      remboursement: remb,
      resultatNet: net,
      servieDepuisStockage: resolution.servieDepuisStockage,
    );
  }

  /// Nombre de numéros attendus pour un type de pari.
  ///
  /// Aligné sur `tailleCombinaisonAttendue` du moteur : on ne devine pas.
  static int nbNumerosPourType(String typePari) {
    switch (typePari) {
      case 'Couplé Gagnant':
      case 'Couplé Placé':
        return 2;
      case 'Tiercé':
        return 3;
      case 'Quarté+':
        return 4;
      case 'Quinté+':
        return 5;
      default:
        return 1;
    }
  }
}
