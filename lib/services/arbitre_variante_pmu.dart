// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-3 — COUCHE D'ARBITRAGE DE VARIANTE (solution A, validée)
//
//  CE FICHIER EST UNE COUCHE D'ARBITRAGE. IL N'EST BRANCHÉ NULLE PART.
//
//  ───────────────────────────────────────────────────────────────────────────
//  POURQUOI CETTE COUCHE EXISTE — MESURÉ, PAS SUPPOSÉ
//  ───────────────────────────────────────────────────────────────────────────
//
//  `resolveur_rapport_pmu.dart` refuse structurellement les libellés
//  GÉNÉRIQUES (« Tiercé », « Quarté+ », « Quinté+ ») : le PMU publie
//  « e-Tiercé Ordre » ET « e-Tiercé Désordre » avec la MÊME combinaison
//  `9-4-15` (R1C6_15112026, mesuré), donc `identifierRapportExact` trouve
//  DEUX candidats et rend `ambiguitePlusieursRapports`. C'est son
//  comportement CORRECT : trancher exige l'arrivée officielle, qui n'est pas
//  une donnée de ce module.
//
//  La répartition validée est donc stricte :
//
//    CETTE COUCHE décide la VARIANTE (Ordre ou Désordre) à partir de
//    l'arrivée officielle définitive, puis restreint les rapports candidats
//    à cette variante. Elle ne calcule AUCUN montant et ne lit JAMAIS un
//    dividende : elle ne peut donc pas sélectionner par montant.
//
//    LE RÉSOLVEUR (`resoudreRapportPmu`, INCHANGÉ) reçoit cette liste
//    restreinte et exerce toutes ses validations. Il reste l'autorité : s'il
//    refuse, aucun rapport n'est attribué et le refus est traduit tel quel.
//
//    LE MOTEUR B-3 calcule le montant UNIQUEMENT après acceptation.
//
//  ───────────────────────────────────────────────────────────────────────────
//  POURQUOI `bonusSeulement` EST UN STATUT À PART ENTIÈRE
//  ───────────────────────────────────────────────────────────────────────────
//
//  Un ticket Quinté+ de 5 chevaux qui ne sont PAS les 5 premiers n'est pas
//  perdant pour autant : il peut toucher un Bonus 4sur5 (4 chevaux du top5 +
//  1 cheval au-delà). Conclure « perdu » ici détruirait la catégorie Bonus.
//
//  Inversement, un ticket Tiercé hors du top3 EST perdant : mesuré, `E_TIERCE`
//  ne publie que « e-Tiercé Ordre » et « e-Tiercé Désordre » — aucun Bonus
//  (5/5 captures). Les deux situations ne peuvent donc pas partager un statut.
//
//  ───────────────────────────────────────────────────────────────────────────
//  EX ÆQUO — JAMAIS D'ORDRE INVENTÉ
//  ───────────────────────────────────────────────────────────────────────────
//
//  Les groupes d'arrivée (`List<List<int>>`, format validé au lot B-2 bis)
//  donnent, pour chaque rang, les chevaux qui l'occupent. Deux chevaux d'un
//  même groupe sont EX ÆQUO : leur ordre relatif n'existe pas.
//
//  Règle appliquée sans exception :
//    • si l'un des rangs COMPARÉS (0 … n-1) contient plus d'un cheval, la
//      variante n'est pas déterminable — on REFUSE ;
//    • si les groupes sont absents, on refuse aussi : `arriveeGroupes == null`
//      signifie « inconnu », JAMAIS « pas d'ex æquo ».
//
//  Mesuré (3 courses réelles) : R5C5 `[[2],[4],[5,7],[8],[3],[6]]`,
//  R6C5 `[[12],[1,7],[9],[2],[10],[8],[6],[13],[5]]`, R5C7 `[[4],[6],[1,5],[2]]`.
//
//  ───────────────────────────────────────────────────────────────────────────
//  INTERDITS RESPECTÉS
//  ───────────────────────────────────────────────────────────────────────────
//
//   • Aucune sélection par montant : aucun `reduce(MAX)`, aucun tri par
//     dividende, aucun repli sur « le premier rapport venu ». Le filtre est
//     une ÉGALITÉ de code et de variante.
//   • Aucun contrôle FINANCIER ici : la mise et les dividendes appartiennent
//     au moteur. Cette couche ne lit même pas `pourUnEuro`.
//   • Aucun montant inventé : toute insuffisance rend un refus motivé.
//  ═══════════════════════════════════════════════════════════════════════════

import 'gain_pmu_types.dart';
import 'gain_ticket_calculator.dart'
    show
        TypePariJoue,
        VarianteRapport,
        codeApiPourType,
        tailleCombinaisonAttendue;

/// L'état officiel de la course, réduit au strict nécessaire.
///
/// [arriveeGroupes] suit le format validé au lot B-2 bis (`List<List<int>>`) :
/// chaque sous-liste porte les chevaux d'un MÊME rang. `null` signifie
/// « groupes NON CONNUS » — jamais « pas d'ex æquo ».
class EtatCourseOfficiel {
  /// Groupes d'arrivée officiels, dans l'ordre. `null` = inconnu.
  final List<List<int>>? arriveeGroupes;

  /// `false` = l'API a explicitement dit que l'arrivée n'est pas définitive.
  /// `null` = l'API est muette (ni définitif, ni provisoire).
  final bool? arriveeDefinitive;

  /// Rapports officiels publiés pour cette course.
  final List<RapportPublie> rapports;

  const EtatCourseOfficiel({
    required this.arriveeGroupes,
    required this.rapports,
    this.arriveeDefinitive,
  });

  /// `true` si l'arrivée comporte un ex æquo CONNU.
  bool get aDesExAequoConnu =>
      arriveeGroupes?.any((g) => g.length > 1) ?? false;

  /// `true` si l'arrivée est explicitement provisoire.
  bool get estProvisoire => arriveeDefinitive == false;
}

/// État d'un arbitrage. Cinq cas, tous exclusifs, aucun « presque ».
enum StatutArbitrage {
  /// Une variante Ordre/Désordre/est établie : le résolveur doit être appelé
  /// sur [ArbitrageVariante.rapportsCompatibles].
  varianteEtablie,

  /// Le type ne publie pas de variantes concurrentes (Simple, Couplé) :
  /// la liste est transmise INTÉGRALEMENT au résolveur, sans restriction.
  sansRestriction,

  /// Les chevaux joués ne sont pas les premiers de l'arrivée, MAIS le type
  /// publie des Bonus : le moteur doit évaluer sa règle de Bonus avant de
  /// conclure. Aucun rapport Ordre/Désordre n'est transmissible.
  bonusSeulement,

  /// La perte est ÉTABLIE par comparaison à l'arrivée officielle définitive,
  /// et ce type ne comporte aucun Bonus.
  perdu,

  /// Donnée insuffisante ou ambiguë : [ArbitrageVariante.motif] est non nul.
  indetermine,
}

/// Verdict d'arbitrage, consommé par le moteur B-3.
class ArbitrageVariante {
  /// État de l'arbitrage.
  final StatutArbitrage statut;

  /// Variante déterminée ; `null` hors [StatutArbitrage.varianteEtablie].
  final VarianteRapport? variante;

  /// Motif fermé (B-0) quand [statut] vaut [StatutArbitrage.indetermine].
  final MotifNonDetermination? motif;

  /// Explication lisible.
  final String explication;

  /// Rapports restreints à la variante. Vide hors
  /// [StatutArbitrage.varianteEtablie] et [StatutArbitrage.sansRestriction].
  final List<RapportPublie> rapportsCompatibles;

  /// État de la Tirelire, décidé ici : l'art. 7.1 fait du rapport
  /// « + Tirelire » le rapport DÉFINITIF du rang Ordre.
  final EtatTirelire etatTirelire;

  /// Les `n` premiers chevaux officiels, dans l'ordre, quand les rangs
  /// comparés sont tous des singletons. `null` sinon.
  ///
  /// Indispensable au moteur pour les Bonus : leurs combinaisons publiées sont
  /// PLUS COURTES que le pari, donc `variantesIdentifiablesParCombinaison` les
  /// exclut délibérément et le résolveur ne peut pas les désigner.
  final List<int>? premiersOfficiels;

  const ArbitrageVariante._({
    required this.statut,
    required this.variante,
    required this.motif,
    required this.explication,
    required this.rapportsCompatibles,
    required this.etatTirelire,
    required this.premiersOfficiels,
  });

  factory ArbitrageVariante.varianteEtablie({
    required VarianteRapport variante,
    required List<RapportPublie> rapportsCompatibles,
    required String explication,
    EtatTirelire etatTirelire = EtatTirelire.sansObjet,
    List<int>? premiersOfficiels,
  }) =>
      ArbitrageVariante._(
        statut: StatutArbitrage.varianteEtablie,
        variante: variante,
        motif: null,
        explication: explication,
        rapportsCompatibles:
            List<RapportPublie>.unmodifiable(rapportsCompatibles),
        etatTirelire: etatTirelire,
        premiersOfficiels: premiersOfficiels == null
            ? null
            : List<int>.unmodifiable(premiersOfficiels),
      );

  factory ArbitrageVariante.sansRestriction({
    required List<RapportPublie> rapports,
    required String explication,
  }) =>
      ArbitrageVariante._(
        statut: StatutArbitrage.sansRestriction,
        variante: null,
        motif: null,
        explication: explication,
        rapportsCompatibles: List<RapportPublie>.unmodifiable(rapports),
        etatTirelire: EtatTirelire.sansObjet,
        premiersOfficiels: null,
      );

  factory ArbitrageVariante.bonusSeulement({
    required List<int> premiersOfficiels,
    required String explication,
  }) =>
      ArbitrageVariante._(
        statut: StatutArbitrage.bonusSeulement,
        variante: null,
        motif: null,
        explication: explication,
        rapportsCompatibles: const <RapportPublie>[],
        etatTirelire: EtatTirelire.sansObjet,
        premiersOfficiels: List<int>.unmodifiable(premiersOfficiels),
      );

  factory ArbitrageVariante.perdu({required String explication}) =>
      ArbitrageVariante._(
        statut: StatutArbitrage.perdu,
        variante: null,
        motif: null,
        explication: explication,
        rapportsCompatibles: const <RapportPublie>[],
        etatTirelire: EtatTirelire.sansObjet,
        premiersOfficiels: null,
      );

  factory ArbitrageVariante.indetermine({
    required MotifNonDetermination motif,
    required String explication,
    EtatTirelire etatTirelire = EtatTirelire.sansObjet,
  }) =>
      ArbitrageVariante._(
        statut: StatutArbitrage.indetermine,
        variante: null,
        motif: motif,
        explication: explication,
        rapportsCompatibles: const <RapportPublie>[],
        etatTirelire: etatTirelire,
        premiersOfficiels: null,
      );

  /// `true` si le résolveur doit être appelé.
  bool get estDeterminee => statut == StatutArbitrage.varianteEtablie;

  /// `true` si le moteur doit évaluer une règle de Bonus.
  bool get doitEvaluerBonus =>
      statut == StatutArbitrage.bonusSeulement ||
      (statut == StatutArbitrage.varianteEtablie &&
          variante == VarianteRapport.tirelire);

  @override
  String toString() => 'ArbitrageVariante(${statut.name}'
      '${variante != null ? " / ${variante!.name}" : ""}'
      '${motif != null ? " / ${motif!.name}" : ""}'
      ' | ${rapportsCompatibles.length} compatible(s)'
      '${premiersOfficiels != null ? " | top=${premiersOfficiels!.join("-")}" : ""})';
}

/// Types dont la variante dépend de l'ARRIVÉE officielle.
///
/// Mesuré : ce sont exactement les types pour lesquels le PMU publie un
/// rapport Ordre ET un rapport Désordre portant la MÊME combinaison.
bool _exigeArbitrageArrivee(TypePariJoue type) {
  switch (type) {
    case TypePariJoue.tierce:
    case TypePariJoue.tierceOrdre:
    case TypePariJoue.tierceDesordre:
    case TypePariJoue.quarte:
    case TypePariJoue.quinte:
      return true;
    case TypePariJoue.simpleGagnant:
    case TypePariJoue.simplePlace:
    case TypePariJoue.gagnantPlace:
    case TypePariJoue.coupleGagnant:
    case TypePariJoue.couplePlace:
    case TypePariJoue.coupleOrdre:
    case TypePariJoue.coupleDesordre:
    case TypePariJoue.inconnu:
      return false;
  }
}

/// Ce type publie-t-il des rapports Bonus ? Mesuré sur les captures réelles.
///
///   • `E_TIERCE`      → AUCUN Bonus (5/5 : seulement Ordre + Désordre) ;
///   • `E_QUARTE_PLUS` → « e-Bonus » (5/5), combinaison = exactement le top3 ;
///   • `E_QUINTE_PLUS` → 5 × « e-Bonus 4sur5 » + 1 × « e-Bonus 3 » (5/5).
bool typePublieDesBonus(TypePariJoue type) {
  switch (type) {
    case TypePariJoue.quarte:
    case TypePariJoue.quinte:
      return true;
    case TypePariJoue.simpleGagnant:
    case TypePariJoue.simplePlace:
    case TypePariJoue.gagnantPlace:
    case TypePariJoue.coupleGagnant:
    case TypePariJoue.couplePlace:
    case TypePariJoue.coupleOrdre:
    case TypePariJoue.coupleDesordre:
    case TypePariJoue.tierce:
    case TypePariJoue.tierceOrdre:
    case TypePariJoue.tierceDesordre:
    case TypePariJoue.inconnu:
      return false;
  }
}

/// Détermine la variante applicable et restreint les rapports candidats.
///
/// Ne lit AUCUN montant : le filtre porte sur le code API et la variante.
ArbitrageVariante arbitrerVariante({
  required TypePariJoue type,
  required List<int> numerosJoues,
  required EtatCourseOfficiel etat,
}) {
  // ── 1. Arrivée explicitement provisoire : aucun arbitrage possible ────────
  if (etat.estProvisoire) {
    return ArbitrageVariante.indetermine(
      motif: MotifNonDetermination.arriveeNonDefinitive,
      explication: 'L\'API indique explicitement que l\'arrivée n\'est pas '
          'définitive. La variante Ordre/Désordre ne peut pas être établie sur '
          'une arrivée provisoire, et aucun gain n\'est calculé.',
    );
  }

  final taille = tailleCombinaisonAttendue(type);
  if (taille == null) {
    return ArbitrageVariante.indetermine(
      motif: MotifNonDetermination.typeNonRepertorie,
      explication: 'Aucune taille de combinaison n\'est définie pour $type : '
          'aucun arbitrage n\'est tenté.',
    );
  }

  // ── 2. Types sans notion d'ordre : aucune restriction ────────────────────
  if (!_exigeArbitrageArrivee(type)) {
    return ArbitrageVariante.sansRestriction(
      rapports: etat.rapports,
      explication: 'Ce type de pari ne publie pas de variantes Ordre/Désordre '
          'concurrentes : la liste est transmise SANS restriction au résolveur, '
          'qui exerce seul ses validations.',
    );
  }

  final code = codeApiPourType(type);
  if (code == null) {
    return ArbitrageVariante.indetermine(
      motif: MotifNonDetermination.typeNonRepertorie,
      explication: 'Aucun code API n\'est publié pour $type.',
    );
  }

  // ── 3. Les groupes d'arrivée sont INDISPENSABLES ici ─────────────────────
  final groupes = etat.arriveeGroupes;
  if (groupes == null || groupes.isEmpty) {
    return ArbitrageVariante.indetermine(
      motif: MotifNonDetermination.deadHeatSansGroupes,
      explication: 'Les frontières de groupes de l\'arrivée officielle ne sont '
          'pas connues (`arriveeGroupes == null`). Or elles sont INDISPENSABLES '
          'pour distinguer Ordre et Désordre : un ordre ne serait établi qu\'en '
          'inventant la place des chevaux ex æquo. Aucun montant n\'est attribué.',
    );
  }

  // ── 4. Rangs comparés : tous des singletons, sinon on refuse ─────────────
  if (groupes.length < taille) {
    return ArbitrageVariante.indetermine(
      motif: MotifNonDetermination.deadHeatSansGroupes,
      explication: 'L\'arrivée officielle ne comporte que ${groupes.length} '
          'rang(s) alors que $type en compare $taille : la comparaison serait '
          'partielle, donc non concluante.',
    );
  }
  for (var i = 0; i < taille; i++) {
    if (groupes[i].length != 1) {
      return ArbitrageVariante.indetermine(
        motif: MotifNonDetermination.deadHeatSansGroupes,
        explication: 'Le rang ${i + 1} est un EX ÆQUO (${groupes[i].join(", ")}) '
            'et il est l\'un des rangs comparés pour $type : l\'ordre relatif de '
            'ces chevaux n\'existe pas. La variante Ordre/Désordre ne peut pas '
            'être tranchée, et aucun ordre n\'est inventé entre chevaux de même '
            'rang.',
      );
    }
  }

  // ── 5. Comparaison STRICTE avec l'arrivée officielle ─────────────────────
  final premiersOfficiels = <int>[
    for (var i = 0; i < taille; i++) groupes[i].single,
  ];

  final joues = numerosJoues.toSet();
  final officiels = premiersOfficiels.toSet();
  final memeEnsemble = joues.length == officiels.length &&
      joues.containsAll(officiels);

  // ── 6. Chevaux joués ≠ premiers officiels ────────────────────────────────
  if (!memeEnsemble) {
    if (typePublieDesBonus(type)) {
      // Un Bonus reste possible : le moteur doit appliquer sa règle. On ne
      // conclut PAS à la perte, et on ne transmet AUCUN rapport Ordre/Désordre.
      return ArbitrageVariante.bonusSeulement(
        premiersOfficiels: premiersOfficiels,
        explication: 'Les chevaux joués (${numerosJoues.join("-")}) ne sont pas '
            'les $taille premiers de l\'arrivée officielle '
            '(${premiersOfficiels.join("-")}). Ce type publiant des Bonus, la '
            'perte n\'est PAS prononcée ici : la règle de Bonus est évaluée par '
            'le moteur. Aucun rapport Ordre/Désordre n\'est transmissible.',
      );
    }
    return ArbitrageVariante.perdu(
      explication: 'Les chevaux joués (${numerosJoues.join("-")}) ne sont pas '
          'les $taille premiers de l\'arrivée officielle définitive '
          '(${premiersOfficiels.join("-")}), et $type ne comporte AUCUN Bonus '
          '(mesuré : E_TIERCE ne publie qu\'Ordre et Désordre). La perte est '
          'ÉTABLIE par comparaison, pas supposée.',
    );
  }

  // ── 7. Ensemble identique : Ordre ou Désordre, puis Tirelire ─────────────
  final memeOrdre = _memeOrdre(numerosJoues, premiersOfficiels);

  if (memeOrdre) {
    final tirelire = etat.rapports.where((r) {
      if (r.codePmu != code) return false;
      if (r.variante != VarianteRapport.tirelire) return false;
      return _memeEnsemble(r.numeros, numerosJoues);
    }).toList();

    if (tirelire.isNotEmpty) {
      // Règlement art. 7.1 : le « + Tirelire » constitue le rapport Ordre
      // DÉFINITIF MAJORÉ du supplément. Ce n'est pas un rapport concurrent de
      // l'Ordre simple, c'est ce même rapport une fois augmenté.
      //
      // ⇒ Les deux lignes publiées ne doivent JAMAIS être additionnées :
      //   cela compterait deux fois la part « rapport Ordre ».
      //
      // (Formulation antérieure « REMPLACE le rapport Ordre simple » retirée :
      //  le texte réglementaire dit « sont alors AUGMENTÉS du quotient »,
      //  art. 7.1, et le règlement PDV ANJ art. 129 dit « sont alors AJOUTÉS
      //  au quotient ». Il y a majoration, non substitution.)
      return ArbitrageVariante.varianteEtablie(
        variante: VarianteRapport.tirelire,
        rapportsCompatibles: tirelire,
        etatTirelire: EtatTirelire.incluse,
        premiersOfficiels: premiersOfficiels,
        explication: 'Arrivée dans l\'ordre exact ET rapport « + Tirelire » '
            'publié pour cette combinaison : règlement art. 7.1, ce rapport '
            'constitue le rapport Ordre DÉFINITIF MAJORÉ du supplément '
            'Tirelire. Les deux lignes publiées ne doivent jamais être '
            'additionnées, car cela compterait deux fois le rapport Ordre.',
      );
    }
  }

  // ── 8. Variante DÉCLARÉE par le ticket, prioritaire sur l'arrivée ────────
  // ★ CORRECTION « Anomalie 3 » (validée par l'utilisateur).
  //
  // MESURE QUI A MOTIVÉ CE BLOC (308 captures datées) :
  //   • le bloc « e-Tiercé Ordre » et le bloc « e-Tiercé Désordre » publient
  //     la MÊME combinaison (20/20 paires Ordre/Désordre mesurées) ;
  //   • la variante ne peut donc PAS se déduire de la combinaison publiée :
  //     elle se déduit du LIBELLÉ, et le libellé est déterminé par le pari
  //     réellement joué, pas par l'arrivée.
  //
  // DÉFAUTS CORRIGÉS (les deux venaient de la déduction par l'arrivée seule) :
  //   1. « Tiercé Désordre » joué, arrivée dans l'ordre exact ⇒ l'arrivée
  //      établissait `ordre`, la restriction écartait le rapport Désordre
  //      réellement publié, et un ticket GAGNANT était déclaré
  //      `blocJusteAbsent`. Le Désordre est payable quel que soit l'ordre
  //      d'arrivée : la variante déclarée doit primer.
  //   2. SYMÉTRIQUE : « Tiercé Ordre » joué, arrivée dans un ordre différent
  //      ⇒ l'arrivée établissait `desordre` et le ticket PERDANT était payé
  //      au dividende Désordre — un faux gain silencieux. L'Ordre exige
  //      l'ordre exact : la perte est établie.
  //
  // CE QUI N'EST PAS CHANGÉ : `tierce`/`quarte`/`quinte` sans mention d'ordre
  // n'ont AUCUNE variante déclarée et continuent de suivre l'arrivée ; aucun
  // repli vers une autre variante n'est introduit ; aucun montant n'est lu ici.
  final varianteDeclaree = _varianteDeclareeParType(type);

  if (varianteDeclaree == VarianteRapport.ordre && !memeOrdre) {
    return ArbitrageVariante.perdu(
      explication: 'Le ticket est un « $type », qui exige l\'ORDRE EXACT de '
          'l\'arrivée. Or les chevaux joués (${numerosJoues.join("-")}) forment '
          'le bon ensemble mais dans un ordre différent de l\'arrivée officielle '
          'définitive (${premiersOfficiels.join("-")}). La variante Désordre '
          'n\'est PAS substituée : le pari Ordre est perdu, et lui attribuer le '
          'rapport Désordre serait payer une variante qui n\'a pas été jouée.',
    );
  }

  final variante = varianteDeclaree ??
      (memeOrdre ? VarianteRapport.ordre : VarianteRapport.desordre);

  // ── 9. Restriction à la variante établie — AUCUN critère de montant ──────
  final compatibles = etat.rapports
      .where((r) => r.codePmu == code && r.variante == variante)
      .toList();

  if (compatibles.isEmpty) {
    return ArbitrageVariante.indetermine(
      motif: MotifNonDetermination.blocJusteAbsent,
      explication: 'La variante « ${variante.name} » '
          '${varianteDeclaree != null ? "est celle du pari joué" : "est établie par l arrivée"} '
          'mais aucun rapport publié de code $code ne la porte. Aucun repli sur '
          'une autre variante n\'est fait : ce serait payer le mauvais rapport.',
    );
  }

  return ArbitrageVariante.varianteEtablie(
    variante: variante,
    rapportsCompatibles: compatibles,
    premiersOfficiels: premiersOfficiels,
    explication: 'Arrivée officielle définitive comparée : le ticket est '
        '${memeOrdre ? "dans l'ordre exact" : "dans un ordre différent"}. '
        'Variante « ${variante.name} » retenue sur cette seule base, sans aucun '
        'examen des montants.',
  );
}

bool _memeOrdre(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Variante EXPLICITEMENT déclarée par le type de pari joué, ou `null`.
///
/// ★ CORRECTION « Anomalie 3 ». `null` signifie « le type ne déclare aucune
/// variante » : l'arbitrage retombe alors sur la déduction par l'arrivée,
/// exactement comme avant cette correction.
///
/// SEULS les types dont le LIBELLÉ nomme la variante sont concernés. Un ticket
/// « Tiercé » (sans mention d'ordre) n'en déclare aucune : il reste payé selon
/// l'arrivée, ce qui est la règle historique et n'est pas modifié ici.
///
/// Le Couplé Ordre déclare `ordre` pour la même raison : son libellé impose
/// l'ordre, et lui attribuer un rapport Désordre serait payer une variante
/// qui n'a pas été jouée.
VarianteRapport? _varianteDeclareeParType(TypePariJoue type) {
  switch (type) {
    case TypePariJoue.tierceOrdre:
    case TypePariJoue.coupleOrdre:
      return VarianteRapport.ordre;
    case TypePariJoue.tierceDesordre:
      return VarianteRapport.desordre;
    // Types sans variante déclarée : `tierce`, `quarte`, `quinte` (payés selon
    // l'arrivée), et tous les types sans notion d'ordre (jamais arbitrés ici,
    // ils sortent avant par `_exigeArbitrageArrivee`).
    default:
      return null;
  }
}

bool _memeEnsemble(List<int>? a, List<int>? b) {
  if (a == null || b == null || a.length != b.length) return false;
  final sa = a.toSet();
  final sb = b.toSet();
  return sa.length == sb.length && sa.containsAll(sb);
}
