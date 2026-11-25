// ═══════════════════════════════════════════════════════════════════
//  BACKTESTING SERVICE — Pronostic Hippique v1.0 (Lot 3)
//
//  Simule ce qui se serait passé si vous aviez suivi l'IA
//  sur les N derniers jours avec une mise fixe.
//
//  Usage :
//    final result = await BacktestingService.instance.lancer(
//      mise: 10.0,
//      typePari: 'Simple Gagnant',
//      nbJours: 30,
//    );
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'finance_simulateur_officiel.dart';
import 'ia_memory_service.dart';

// ─── Résultat d'une course simulée ───────────────────────────────────────────
class BacktestCourse {
  final String courseKey;
  final String nomCourse;
  final String hippodrome;
  final String discipline;
  final DateTime date;
  final double confianceIA;
  final String typePariConseille;

  // Résultat réel
  final List<int> arriveeReelle;
  final int?
      rangFavoriIA; // rang du favori IA dans l'arrivée réelle (1 = gagné)

  // Calcul financier — ★ BLOC 1 : issu du MOTEUR OFFICIEL, jamais estimé.
  //   `sort == nonDeterminee` ⇒ `gainNet` et `gainsBruts` valent `null` ;
  //   ils ne valent JAMAIS 0,0 et la course n'entre dans aucun agrégat
  //   financier. C'est la différence entre « perdu » et « on ne sait pas ».
  final double mise;
  final double? gainNet;
  final bool? gagne;
  final SortPariSimule sort;
  final double? gainsBruts;
  final double? remboursements;
  final String? motifIndetermination;
  final List<int> numerosJoues;

  const BacktestCourse({
    required this.courseKey,
    required this.nomCourse,
    required this.hippodrome,
    required this.discipline,
    required this.date,
    required this.confianceIA,
    required this.typePariConseille,
    required this.arriveeReelle,
    this.rangFavoriIA,
    required this.mise,
    required this.gainNet,
    required this.gagne,
    required this.sort,
    this.gainsBruts,
    this.remboursements,
    this.motifIndetermination,
    this.numerosJoues = const <int>[],
  });

  bool get estDetermine => sort != SortPariSimule.nonDeterminee;

  /// ★ BLOC 1 (validation financière) — pari REMBOURSÉ : mise rendue,
  /// ni gain ni perte. Un tel pari est DÉTERMINÉ (on sait ce qui s'est
  /// passé) mais ne doit jamais être présenté comme gagné ou perdu.
  bool get estRembourse => sort == SortPariSimule.rembourse;
}

// ─── Résultat complet d'une simulation ───────────────────────────────────────
class BacktestResult {
  final List<BacktestCourse> courses;
  final double miseTotal;
  final double gainsTotal;
  final double gainNet;
  final int nbGagnes;
  final int nbPerdus;

  /// ★ BLOC 1 (validation financière) — paris REMBOURSÉS (mise rendue).
  ///
  /// Ce sont des paris dont le sort est ÉTABLI, mais qui ne sont NI gagnés
  /// NI perdus. Ils entrent donc dans [nbDetermines] et dans la couverture,
  /// sans jamais apparaître comme des pertes.
  final int nbRembourses;
  final int nbTotal;
  final double tauxReussite; // %
  final double roi; // Return on Investment %
  final double gainNetCumule; // gain cumulé sur toute la période
  // Séries
  final int meilleureSerieGagnante;
  final int pireSeriesPerdantes;
  // Courbe gains cumulés (index = numéro de course, valeur = gain cumulé)
  final List<double> courbeGains;
  // Répartition par discipline
  final Map<String, StatDiscipline> parDiscipline;
  // Répartition par hippodrome (top 5)
  final Map<String, StatDiscipline> parHippodrome;
  // ★ v9.93 : Perte maximale consécutive (maxDrawdown)
  final double maxDrawdown;
  // ★ v10.35 : Ventilation par type de pari (synergie avec vrais critères PMU)
  final Map<String, StatTypePari> parTypePari;

  // ★ BLOC 1 — PÉRIMÈTRE FINANCIER OFFICIEL
  //
  //  Ces champs existent pour qu'une statistique ne puisse JAMAIS présenter un
  //  résultat fictif comme mesuré, ni un indéterminé comme une perte.
  //
  /// Nombre de paris dont le sort financier est ÉTABLI par le moteur officiel.
  final int nbDetermines;

  /// Nombre de paris dont le résultat officiel est introuvable/insuffisant.
  /// Ils ne sont ni gagnants ni perdants : ils sont INCONNUS.
  final int nbNonDetermines;

  /// Somme des mises des paris DÉTERMINÉS uniquement (base du ROI).
  final double misesDeterminees;

  /// Somme des mises des paris indéterminés, tenue À PART.
  final double misesIndeterminees;

  /// Somme des remboursements officiels (jamais fondus dans le gain).
  final double remboursements;

  /// Couverture officielle en % : paris déterminés / paris simulés.
  final double couvertureOfficielle;

  /// Vrai si la couverture est trop faible pour que le ROI signifie quelque
  /// chose. Un ROI calculé sur 3 paris établis et 40 inconnus n'est pas un ROI.
  final bool couvertureInsuffisante;

  const BacktestResult({
    required this.courses,
    required this.miseTotal,
    required this.gainsTotal,
    required this.gainNet,
    required this.nbGagnes,
    required this.nbPerdus,
    this.nbRembourses = 0, // ★ BLOC 1 (validation financière)
    required this.nbTotal,
    required this.tauxReussite,
    required this.roi,
    required this.gainNetCumule,
    required this.meilleureSerieGagnante,
    required this.pireSeriesPerdantes,
    required this.courbeGains,
    required this.parDiscipline,
    required this.parHippodrome,
    this.maxDrawdown = 0.0, // ★ v9.93
    this.parTypePari = const {}, // ★ v10.35
    this.nbDetermines = 0, // ★ BLOC 1
    this.nbNonDetermines = 0, // ★ BLOC 1
    this.misesDeterminees = 0.0, // ★ BLOC 1
    this.misesIndeterminees = 0.0, // ★ BLOC 1
    this.remboursements = 0.0, // ★ BLOC 1
    this.couvertureOfficielle = 0.0, // ★ BLOC 1
    this.couvertureInsuffisante = false, // ★ BLOC 1
  });

  bool get estRentable => gainNet > 0;

  String get resumeTexte {
    final roiStr =
        roi >= 0 ? '+${roi.toStringAsFixed(0)}%' : '${roi.toStringAsFixed(0)}%';
    final base = '$nbGagnes gagnés / $nbTotal paris — ROI : $roiStr — '
        'Gain net : ${gainNet >= 0 ? "+" : ""}${gainNet.toStringAsFixed(0)} €';
    // ★ BLOC 1 : la couverture ET les indéterminés sont TOUJOURS annoncés.
    //   Sans eux, l'utilisateur lirait un ROI sur un sous-ensemble sans le
    //   savoir — exactement ce que le mandat interdit.
    final couv = 'Couverture officielle : '
        '${couvertureOfficielle.toStringAsFixed(0)} %';
    final inde = nbNonDetermines > 0
        ? ' — $nbNonDetermines pari(s) NON DÉTERMINÉ(S) '
            '(${misesIndeterminees.toStringAsFixed(0)} € non comptés)'
        : '';
    final alerte = couvertureInsuffisante
        ? ' ⚠️ Couverture insuffisante : ce ROI n\'est pas représentatif.'
        : '';
    return '$base — $couv$inde$alerte';
  }
}

// ★ v9.82 : classe rendue publique (était _StatDiscipline) pour accès depuis ia_performance_screen
class StatDiscipline {
  int nbTotal = 0;
  int nbGagnes = 0;
  double gainNet = 0.0;

  /// ★ BLOC 1 — paris dont le résultat officiel est INDISPONIBLE.
  /// Ils sont comptés pour que l'utilisateur voie l'échantillon réel, mais ils
  /// ne sont ni gagnés ni perdus et n'entrent dans aucun taux.
  int nbNonDetermines = 0;

  /// Taux calculé sur les paris DÉTERMINÉS seulement. `null` si aucun : un
  /// taux inconnu n'est pas 0 %.
  double? get taux {
    final determines = nbTotal - nbNonDetermines;
    return determines > 0 ? nbGagnes / determines * 100 : null;
  }
}

// ─── Stats par type de pari ─────────────────────────────────────────────────
// ★ v10.35 : Ventilation par type de pari — même structure que StatDiscipline
//            + Kelly optimal calculé depuis le taux de réussite réel
class StatTypePari {
  int nbTotal = 0;
  int nbGagnes = 0;
  double gainNet = 0.0;
  double miseTotal = 0.0;
  int maxSerie = 0; // série perdante max pour ce type
  int _serieCourante = 0;

  /// ★ BLOC 1 — paris de ce type dont le résultat officiel est INDISPONIBLE.
  int nbNonDetermines = 0;

  /// ★ BLOC 1 (validation financière) — paris REMBOURSÉS de ce type.
  /// Mise rendue : ni gain ni perte, aucune série brisée.
  int nbRembourses = 0;

  /// Nombre de paris réellement établis pour ce type.
  ///
  /// ⚠️ `nbTotal` ne compte QUE les paris déterminés (voir [ajouterPari] et
  ///    [ajouterPariRembourse]) : un indéterminé ne dilue donc pas le taux,
  ///    et un remboursement non plus.
  int get nbDetermines => nbTotal;

  /// Taux sur les paris DÉTERMINÉS. `null` si aucun : inconnu ≠ 0 %.
  double? get taux => nbTotal > 0 ? nbGagnes / nbTotal * 100 : null;
  double? get roi => miseTotal > 0 ? (gainNet / miseTotal) * 100 : null;

  /// Kelly fraction = (p*b - q) / b
  /// p = proba de gain, b = cote nette moyenne, q = 1 - p
  /// Si taux < 10% → Kelly = 0 (ne pas jouer ce type)
  ///
  /// ★ BLOC 1 : `nbTotal` ne compte QUE les paris déterminés (voir
  /// `ajouterPari`), donc `p` n'est plus dilué par des indéterminés.
  double kellyFraction({double coteNetteMoyenne = 3.5}) {
    if (nbTotal < 5) return 0.0; // pas assez de données
    final p = nbGagnes / nbTotal;
    final q = 1.0 - p;
    final b = coteNetteMoyenne;
    final k = (p * b - q) / b;
    return k.clamp(0.0, 0.25); // jamais plus de 25% de la bankroll
  }

  void ajouterPari(bool gagne, double gain, double mise) {
    nbTotal++;
    miseTotal += mise;
    gainNet += gain;
    if (gagne) {
      nbGagnes++;
      _serieCourante = 0;
    } else {
      _serieCourante++;
      if (_serieCourante > maxSerie) maxSerie = _serieCourante;
    }
  }

  /// ★ BLOC 1 (validation financière) — enregistre un pari REMBOURSÉ.
  ///
  /// Il compte dans l'échantillon ([nbTotal], [miseTotal]) parce que sa mise a
  /// bien été engagée puis rendue, mais il n'est NI gagné NI perdu :
  ///   • `nbGagnes` inchangé → il ne gonfle pas le taux de réussite ;
  ///   • `_serieCourante` inchangée → il ne brise aucune série, ni ne
  ///     l'allonge. Le compter comme perte ferait apparaître une série
  ///     perdante là où l'utilisateur a récupéré son argent.
  void ajouterPariRembourse(double remboursement, double mise) {
    nbTotal++;
    miseTotal += mise;
    // Le net d'un remboursement intégral est exactement nul ; on transporte
    // néanmoins la valeur rendue par le moteur plutôt que de la supposer.
    gainNet += remboursement - mise;
    nbRembourses++;
  }
}

// ─── Service de backtesting ───────────────────────────────────────────────────
class BacktestingService {
  static final BacktestingService _instance = BacktestingService._();
  static BacktestingService get instance => _instance;
  BacktestingService._();

  /// Lance une simulation sur l'historique IaMemoryService.
  ///
  /// [mise]        : mise fixe par course (ex: 10.0 €)
  /// [typePari]    : 'Simple Gagnant', 'Simple Placé', 'Conseil IA' (utilise le type conseillé)
  /// [nbJours]     : nombre de jours à simuler (7, 14, 30, 60, 90)
  /// [confianceMin]: seuil minimum de confiance pour parier (0-100)
  /// [discipline]  : ★ v10.20 — filtre sur une discipline (null = toutes)
  /// [hippodrome]  : ★ v10.20 — filtre sur un hippodrome (null = tous)
  Future<BacktestResult> lancer({
    required double mise,
    String typePari = 'Conseil IA',
    int nbJours = 30,
    double confianceMin = 0.0,
    String? discipline, // ★ v10.20
    String? hippodrome, // ★ v10.20
  }) async {
    final pronostics = IaMemoryService.instance.pronostics;
    final limiteDate = DateTime.now().subtract(Duration(days: nbJours));

    // Filtrer les pronostics avec résultats réels, dans la période
    // ★ v10.20 : + filtre discipline / hippodrome optionnel
    final avecResultats = pronostics
        .where((p) =>
            p.resultatsReels &&
            p.arriveeReelle != null &&
            p.arriveeReelle!.isNotEmpty &&
            p.datePronostic.isAfter(limiteDate) &&
            (discipline == null || p.discipline == discipline) &&
            (hippodrome == null || p.hippodrome == hippodrome))
        .toList()
      ..sort((a, b) => a.datePronostic.compareTo(b.datePronostic));

    if (avecResultats.isEmpty) {
      return BacktestResult(
        courses: [],
        miseTotal: 0,
        gainsTotal: 0,
        gainNet: 0,
        nbGagnes: 0,
        nbPerdus: 0,
        nbTotal: 0,
        tauxReussite: 0,
        roi: 0,
        gainNetCumule: 0,
        meilleureSerieGagnante: 0,
        pireSeriesPerdantes: 0,
        courbeGains: [],
        parDiscipline: {},
        parHippodrome: {},
        parTypePari: {},
      );
    }

    // ★ BLOC 1 — PÉRIMÈTRE FINANCIER : plus aucun calcul local.
    //
    //   Chaque pari est résolu par `FinanceSimulateurOfficiel.simulerPari`,
    //   qui délègue au moteur officiel. Ce service ne fait plus que :
    //     • CHOISIR les numéros à jouer (règle IA : top N des scores) ;
    //     • CHOISIR le type de pari ;
    //     • ADDITIONNER ce que le moteur rend.
    //
    //   ⚠️ Choix anti-triche : la sélection n'utilise QUE `scoresIA`, donc
    //      uniquement ce que l'IA savait AVANT la course. `arriveeReelle`
    //      n'intervient que pour l'AFFICHAGE du rang constaté, jamais dans la
    //      décision ni dans le calcul financier.
    final List<BacktestCourse> courses = [];
    final List<double> courbeGains = [];
    final Map<String, StatDiscipline> parDisc = {};
    final Map<String, StatDiscipline> parHippo = {};

    int serieGagnante = 0;
    int maxSerieGagnante = 0;
    int seriePerdante = 0;
    int maxSeriePerdante = 0;
    int nbGagnes = 0;
    int nbPerdus = 0;
    // ★ BLOC 1 (validation financière) : paris REMBOURSÉS — mise rendue,
    //   ni gain ni perte. Compteur propre, jamais fondu dans `nbPerdus`.
    int nbRembourses = 0;
    int nbNonDetermines = 0;
    double gainCumule = 0.0;
    double misesDeterminees = 0.0;
    double misesIndeterminees = 0.0;
    double remboursementsTotal = 0.0;
    double gainsBrutsTotal = 0.0;

    for (final p in avecResultats) {
      final confiance = p.confiancePredite ?? 50.0;
      if (confiance < confianceMin) continue;

      final arrivee = p.arriveeReelle!;

      // Type de pari effectif — règle HISTORIQUE conservée telle quelle.
      final typeEffectif = typePari == 'Conseil IA'
          ? (p.typePariConseille ?? 'Simple Gagnant')
          : typePari;

      // Numéros joués : top N des scores IA, N dépendant du type. Aucune
      // information post-course n'entre ici.
      final nbNum = FinanceSimulateurOfficiel.nbNumerosPourType(typeEffectif);
      final numerosJoues = _getTopNIA(p.scoresIA, nbNum);
      if (numerosJoues.isEmpty) continue;

      // Rang constaté du premier numéro joué : AFFICHAGE uniquement.
      final rang = arrivee.indexOf(numerosJoues.first) + 1;
      final rangReel = rang > 0 ? rang : null;

      // ── RÉSOLUTION OFFICIELLE ──────────────────────────────────────────
      final ResultatFinancierSimule sim;
      if (typeEffectif == 'Gagnant+Placé') {
        // Mise historique : une mise sur chaque composante (le gain était
        // auparavant calculé sur `mise * cote - mise * 2`). On ne change pas
        // cette règle de mise, on change seulement QUI calcule le gain.
        sim = await FinanceSimulateurOfficiel.simulerGagnantPlace(
          courseKey: p.courseKey,
          numero: numerosJoues.first,
          miseGagnant: mise,
          misePlace: mise,
        );
      } else {
        sim = await FinanceSimulateurOfficiel.simulerPari(
          courseKey: p.courseKey,
          typePari: typeEffectif,
          numerosJoues: numerosJoues,
          mise: mise,
        );
      }

      final gagne = sim.sort == SortPariSimule.gagne;
      final rembourse = sim.sort == SortPariSimule.rembourse;
      final estDetermine = sim.estDetermine;

      if (estDetermine) {
        misesDeterminees += sim.mise;
        gainsBrutsTotal += sim.gain ?? 0.0;
        remboursementsTotal += sim.remboursement ?? 0.0;
        gainCumule += sim.resultatNet ?? 0.0;
        courbeGains.add(gainCumule);
        if (gagne) {
          nbGagnes++;
          serieGagnante++;
          seriePerdante = 0;
          if (serieGagnante > maxSerieGagnante) {
            maxSerieGagnante = serieGagnante;
          }
        } else if (rembourse) {
          // ★ CORRECTION BLOC 1 (validation financière) — REMBOURSEMENT.
          //
          //   DÉFAUT CORRIGÉ : `sim.sort` pouvait valoir `rembourse` (mise
          //   rendue) et tombait dans la branche `else` → compté PERDU et
          //   brisait une série gagnante. Un remboursement n'est pas une
          //   perte : le net vaut 0 (remb − mise), donc il n'entre pas dans
          //   le résultat, et il ne doit casser AUCUNE série — sinon une
          //   série gagnante serait interrompue par une annulation.
          nbRembourses++;
          // Séries INCHANGÉES : ni incrément, ni remise à zéro.
        } else {
          nbPerdus++;
          seriePerdante++;
          serieGagnante = 0;
          if (seriePerdante > maxSeriePerdante) {
            maxSeriePerdante = seriePerdante;
          }
        }
      } else {
        // ⚠️ NON DÉTERMINÉ : la mise n'entre PAS dans `misesDeterminees`, la
        //    course n'entre NI dans la courbe NI dans le résultat net, et elle
        //    ne compte NI comme gain NI comme perte.
        //
        //    ★ CORRECTION BLOC 1 (validation financière) — ELLE INTERROMPT
        //    AUSSI LES DEUX SÉRIES.
        //
        //    DÉFAUT MESURÉ (test `5.1`, ROUGE) : laisser les compteurs de série
        //    intacts (« neutre ») RELIE deux séries à travers l'inconnu. Trois
        //    gains, une course sans résultat, deux gains → on annonçait
        //    « 5 gains consécutifs ». C'est faux : la 4ᵉ course n'a pas de
        //    résultat, on ne sait pas ce qui s'y est passé.
        //
        //    La règle correcte n'est donc pas « neutre » mais « SÉPARATEUR » :
        //    un indéterminé clôt le segment courant sans rien y ajouter. Les
        //    séries mesurées ne valent alors que DANS un segment continu de
        //    courses connues — ce qui est la seule chose démontrable.
        //
        //    Différence avec un remboursement : celui-ci est CONNU (on sait que
        //    la mise est rendue), il n'interrompt donc rien ; l'indéterminé,
        //    lui, est une ignorance, et une ignorance ne peut pas servir de
        //    pont.
        nbNonDetermines++;
        misesIndeterminees += sim.mise;
        serieGagnante = 0;
        seriePerdante = 0;
      }

      // Ventilations : les indéterminés y sont comptés SÉPARÉMENT.
      final disc = p.discipline.isNotEmpty ? p.discipline : 'Inconnu';
      parDisc.putIfAbsent(disc, () => StatDiscipline());
      parDisc[disc]!.nbTotal++;
      if (gagne) parDisc[disc]!.nbGagnes++;
      if (estDetermine) parDisc[disc]!.gainNet += sim.resultatNet ?? 0.0;
      // ★ CORRECTION BLOC 1 : ce compteur était incrémenté INCONDITIONNELLEMENT
      //   (donc pour toutes les courses), ce qui rendait « non déterminés »
      //   égal au nombre total de paris et faussait toute couverture par
      //   discipline. Il ne doit compter QUE les indéterminés.
      if (!estDetermine) parDisc[disc]!.nbNonDetermines++;

      final hippo = p.hippodrome.isNotEmpty ? p.hippodrome : 'Inconnu';
      parHippo.putIfAbsent(hippo, () => StatDiscipline());
      parHippo[hippo]!.nbTotal++;
      if (gagne) parHippo[hippo]!.nbGagnes++;
      if (estDetermine) parHippo[hippo]!.gainNet += sim.resultatNet ?? 0.0;
      if (!estDetermine) parHippo[hippo]!.nbNonDetermines++;

      courses.add(BacktestCourse(
        courseKey: p.courseKey,
        nomCourse: p.nomCourse,
        hippodrome: p.hippodrome,
        discipline: p.discipline,
        date: p.datePronostic,
        confianceIA: confiance,
        typePariConseille: typeEffectif,
        arriveeReelle: arrivee,
        rangFavoriIA: rangReel,
        mise: sim.mise,
        gainNet: estDetermine ? sim.resultatNet : null,
        gagne: estDetermine ? gagne : null,
        sort: sim.sort,
        gainsBruts: estDetermine ? sim.gain : null,
        remboursements: estDetermine ? sim.remboursement : null,
        motifIndetermination: sim.motifIndetermination,
        numerosJoues: numerosJoues,
      ));
    }

    // ── VENTILATION PAR TYPE : reconstruite depuis `courses` ────────────────
    //  Elle est calculée APRÈS la boucle, à partir des résultats officiels
    //  déjà obtenus : aucune deuxième résolution, aucun second moteur.
    final Map<String, StatTypePari> parType = {};
    for (final c in courses) {
      parType.putIfAbsent(c.typePariConseille, () => StatTypePari());
      final st = parType[c.typePariConseille]!;
      if (c.estDetermine) {
        if (c.sort == SortPariSimule.rembourse) {
          st.ajouterPariRembourse(c.remboursements ?? 0.0, c.mise);
        } else {
          st.ajouterPari(c.gagne ?? false, c.gainNet ?? 0.0, c.mise);
        }
      } else {
        st.nbNonDetermines++;
      }
    }

    // ★ v9.93 : Calculer le maxDrawdown (perte maximale consécutive sur la courbe des gains)
    double maxDrawdown = 0.0;
    if (courbeGains.isNotEmpty) {
      double peak = courbeGains.first;
      for (final g in courbeGains) {
        if (g > peak) peak = g;
        final drawdown = peak - g;
        if (drawdown > maxDrawdown) maxDrawdown = drawdown;
      }
    }

    // ★ BLOC 1 — AGRÉGATS OFFICIELS.
    //   `nbPerdus` n'est plus « total − gagnés » : ce serait compter les
    //   indéterminés comme des pertes. Il vient du moteur, pas d'une soustraction.
    final nbTotal = courses.length;
    // ★ BLOC 1 (validation financière) : un REMBOURSEMENT est un sort ÉTABLI.
    //   L'oublier ici ferait baisser artificiellement la couverture officielle
    //   et laisserait croire à des données manquantes là où le PMU a répondu.
    final nbDetermines = nbGagnes + nbPerdus + nbRembourses;
    final miseTotal = misesDeterminees;
    final gainsTotal = gainsBrutsTotal;
    final gainNet = gainCumule;
    final taux = nbDetermines > 0 ? nbGagnes / nbDetermines * 100 : 0.0;
    final roi = misesDeterminees > 0 ? (gainNet / misesDeterminees) * 100 : 0.0;
    final couverture = nbTotal > 0 ? nbDetermines / nbTotal * 100 : 0.0;
    final couvertureInsuffisante = nbTotal > 0 && couverture < 50.0;

    // Top 5 hippodromes seulement
    final topHippos = Map.fromEntries(
      (parHippo.entries.toList()
            ..sort((a, b) => b.value.nbTotal.compareTo(a.value.nbTotal)))
          .take(5),
    );

    debugPrint('[Backtesting] ✅ $nbTotal paris simulés sur $nbJours jours '
        '— déterminés : $nbDetermines ($nbGagnes gagnés / $nbPerdus perdus), '
        'non déterminés : $nbNonDetermines — couverture : '
        '${couverture.toStringAsFixed(0)} % — Gain net officiel : '
        '${gainNet.toStringAsFixed(0)} € — ROI officiel : '
        '${roi.toStringAsFixed(0)} %');

    return BacktestResult(
      courses: courses,
      miseTotal: miseTotal,
      gainsTotal: gainsTotal,
      gainNet: gainNet,
      nbGagnes: nbGagnes,
      nbPerdus: nbPerdus,
      nbRembourses: nbRembourses,
      nbTotal: nbTotal,
      tauxReussite: taux,
      roi: roi,
      gainNetCumule: gainCumule,
      meilleureSerieGagnante: maxSerieGagnante,
      pireSeriesPerdantes: maxSeriePerdante,
      courbeGains: courbeGains,
      parDiscipline: parDisc,
      parHippodrome: topHippos,
      maxDrawdown: maxDrawdown, // ★ v9.93
      parTypePari: parType, // ★ v10.35
      // ★ BLOC 1
      nbDetermines: nbDetermines,
      nbNonDetermines: nbNonDetermines,
      misesDeterminees: misesDeterminees,
      misesIndeterminees: misesIndeterminees,
      remboursements: remboursementsTotal,
      couvertureOfficielle: couverture,
      couvertureInsuffisante: couvertureInsuffisante,
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  ★ BLOC 1 — SUPPRESSION DU CALCULATEUR FICTIF
  //
  //  Ce qui a été RETIRÉ ici, et pourquoi (mesuré, pas supposé) :
  //
  //    • repli `4.5` quand la cote PMU manquait  → dividende inventé ;
  //    • `cotePlaceEstimee = coteGagnant / 4`     → cote placé inventée ;
  //    • Couplé Gagnant  × 8.0                    → multiplicateur inventé ;
  //    • Couplé Placé    × 4.0                    → multiplicateur inventé ;
  //    • Tiercé ordre    × 50.0 / désordre × 20.0 → multiplicateurs inventés ;
  //    • Quarté+ 4/4     × 40.0 / bonus × 5.0     → multiplicateurs inventés ;
  //    • Quinté+ 5/5     × 100.0 / bonus × 8.0    → multiplicateurs inventés.
  //
  //  Aucun de ces nombres n'a jamais été publié par le PMU. Ils produisaient
  //  des ROI et des courbes de gains entièrement fictifs, présentés comme des
  //  mesures.
  //
  //  REMPLACEMENT : `FinanceSimulateurOfficiel.simulerPari`, qui délègue au
  //  moteur officiel via la chaîne commune. Aucun second moteur financier.
  // ═════════════════════════════════════════════════════════════════════════

  /// Retourne les N numéros avec les meilleurs scores IA
  List<int> _getTopNIA(Map<String, double> scoresIA, int n) {
    final sorted = scoresIA.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(n)
        .map((e) => int.tryParse(e.key))
        .whereType<int>()
        .toList();
  }

  /// Résumé rapide : combien de courses avec résultats disponibles
  int get nbCoursesDisponibles => IaMemoryService.instance.pronostics
      .where((p) => p.resultatsReels && p.arriveeReelle != null)
      .length;

  /// Plage de dates disponible
  ({DateTime? debut, DateTime? fin}) get plageDisponible {
    final avecResultats = IaMemoryService.instance.pronostics
        .where((p) => p.resultatsReels)
        .map((p) => p.datePronostic)
        .toList();
    if (avecResultats.isEmpty) return (debut: null, fin: null);
    avecResultats.sort();
    return (debut: avecResultats.first, fin: avecResultats.last);
  }
}
