// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-0 — SOCLE DE TYPES PURS POUR LES GAINS PMU
//
//  CE FICHIER EST UNE FONDATION, PAS UN BRANCHEMENT.
//
//  Aucun écran, aucun service, aucun stockage ne l'importe. Il ne modifie donc
//  AUCUN comportement existant. Il ne lit ni n'écrit rien : aucune I/O, aucun
//  état, aucun `SharedPreferences`, aucun `setState`, aucun `DateTime.now()`.
//  Tout y est fonctionnel et reproductible.
//
//  ───────────────────────────────────────────────────────────────────────────
//  POURQUOI CE FICHIER EXISTE
//  ───────────────────────────────────────────────────────────────────────────
//
//  Le défaut central du calcul de gain actuel n'est pas une formule fausse :
//  c'est un DÉFAUT DE REPRÉSENTATION. Un ticket ne stocke aujourd'hui qu'un
//  seul `dividendePmuReel` et qu'une seule mise agrégée, alors que le PMU paie
//  PAR RANG DE RAPPORT et PAR COMPOSANTE.
//
//  Mesures qui imposent cette conclusion (rejouables sur
//  /home/user/recherche_pmu/multi/, 313 captures réelles) :
//
//   • R1C6_15112026 publie, pour la MÊME combinaison `9-4-15-10-1`, DEUX
//     rapports au MÊME rang 1 :
//         « e-Quinté+ Ordre + Tirelire »  11 462 670
//         « e-Quinté+ Ordre »              6 462 670
//     Un seul champ scalaire ne peut pas représenter les deux, donc ne peut
//     pas exprimer « lequel est le rapport définitif » (règlement art. 7.1).
//
//   • Quinté+ publie QUATRE rangs simultanément (Ordre, Désordre, Bonus 4sur5,
//     Bonus 3) avec des combinaisons de tailles DIFFÉRENTES (5, 5, 4, 3).
//
//   • Gagnant+Placé est un ticket à DEUX composantes sans rapport PMU unique :
//     `resoudreRapportPmu` le refuse explicitement
//     (`MotifRefusPmu.ticketDeuxComposantes`). Il faut deux montants.
//
//  ───────────────────────────────────────────────────────────────────────────
//  R17 — UNITÉS HÉTÉROGÈNES : MESURÉ, ET RENDU IMPOSSIBLE À CONFONDRE
//  ───────────────────────────────────────────────────────────────────────────
//
//  `miseBase` vaut 100, 150, 200 ou 300 centimes selon le bloc, donc
//  `dividende` et `dividendePourUneMiseDeBase` ne sont PAS comparables entre
//  blocs. Mesuré sur les captures réelles :
//
//      E_SIMPLE_GAGNANT  miseBase=100  dividende/pourUnEuro = 1,0
//      E_TIERCE          miseBase=100                    = 1,0
//      E_QUARTE_PLUS     miseBase=150                    = 1,5
//      E_QUINTE_PLUS     miseBase=200                    = 2,0
//      E_MULTI           miseBase=300                    = 3,0
//
//  CONSÉQUENCE DE CONCEPTION : [RapportPublie] ne porte QUE `pourUnEuro`.
//  Ni `dividende`, ni `dividendePourUneMiseDeBase`, ni `miseBase` ne sont
//  exposés comme champs monétaires utilisables. Il n'existe donc aucun moyen
//  d'écrire un calcul qui mélange deux unités : elles ne sont pas là.
//  `miseBaseCentimes` est conservé pour l'AUDIT uniquement, et son nom dit
//  qu'il ne faut pas s'en servir pour calculer.
//
//  ───────────────────────────────────────────────────────────────────────────
//  CE QUE CE FICHIER NE FAIT PAS — VOLONTAIREMENT
//  ───────────────────────────────────────────────────────────────────────────
//
//  • Il ne décide d'AUCUN rang gagnant : c'est la couche de résolution (B-3).
//  • Il n'appelle PAS `resoudreRapportPmu` et ne le concurrence pas (B-3
//    expliquera l'articulation ; aucun second moteur de verdict ici).
//  • Il ne contient AUCUNE sélection par montant : aucun `reduce(MAX)`,
//    aucun `sort` par dividende, aucun `first` de repli. Structurellement,
//    un type qui ne connaît pas les autres rapports ne peut pas les classer.
//
//  ═══════════════════════════════════════════════════════════════════════════

import 'gain_ticket_calculator.dart' show VarianteRapport;

// ═══════════════════════════════════════════════════════════════════════════
//  1. ÉTATS — « non déterminé » est un état de PREMIÈRE CLASSE
// ═══════════════════════════════════════════════════════════════════════════

/// État du gain d'un ticket, tel qu'il doit être REPRÉSENTABLE.
///
/// La raison d'être de cet enum est négative : il existe pour que l'absence
/// d'information ne puisse PAS être confondue avec un gain nul, ni comblée par
/// un montant inventé.
///
/// Correspondance stricte avec l'affichage :
///  • [nonDetermine] → « Gain non déterminé » + motif, AUCUN montant ;
///  • [attribue]     → « Gain gagné » = somme des rapports attribués ;
///  • [perdu]        → « Perdu » = perte de la mise réellement engagée ;
///  • [rembourse]    → ticket remboursé par l'opérateur.
enum EtatGain {
  /// Le gain ne peut pas être établi. Un motif fermé est obligatoire.
  nonDetermine,

  /// Au moins un rapport officiel a été attribué au ticket.
  attribue,

  /// Le ticket est perdant — établi, pas supposé.
  perdu,

  /// Le pari est remboursé (champ `rembourse` du bloc PMU).
  rembourse;

  /// Sérialisation stable pour la persistance (B-1).
  String toJson() => name;

  /// Lecture tolérante : une valeur inconnue ou absente ne devine rien.
  static EtatGain? fromJson(dynamic valeur) {
    if (valeur is! String) return null;
    for (final e in EtatGain.values) {
      if (e.name == valeur) return e;
    }
    return null;
  }
}

/// État de la Tirelire, INDÉPENDANT du rapport Ordre.
///
/// Cette séparation est une exigence explicite : ne pas confondre
/// l'incertitude sur la Tirelire avec l'incertitude sur le rapport Ordre.
///
/// Mesure décisive (R1C6, règlement art. 7.1) : la Tirelire est un supplément
/// affecté au rapport « e-Quinté+ Ordre », qui devient le rapport brut commun
/// « définitif ». L'API publie les DEUX rapports séparément :
///      « e-Quinté+ Ordre + Tirelire »  11 462 670   ← le définitif
///      « e-Quinté+ Ordre »              6 462 670   ← avant supplément
/// Différence = 5 000 000 exactement, soit « par multiple entier de 1 000 €
/// net », conforme au texte. Il ne faut JAMAIS additionner les deux.
enum EtatTirelire {
  /// Le type de pari du ticket n'ouvre pas droit à la Tirelire (non-Quinté+),
  /// ou aucune Tirelire n'était proposée ce jour-là.
  sansObjet,

  /// Un rapport « + Tirelire » a été retenu comme rapport DÉFINITIF.
  incluse,

  /// Une Tirelire est proposée mais l'éligibilité n'est pas démontrable :
  /// aucun montant n'est attribué.
  nonDeterminee;

  String toJson() => name;

  static EtatTirelire? fromJson(dynamic valeur) {
    if (valeur is! String) return null;
    for (final e in EtatTirelire.values) {
      if (e.name == valeur) return e;
    }
    return null;
  }
}

/// Motif FERMÉ d'un gain non déterminé.
///
/// Un enum plutôt qu'une `String` libre : c'est ce qui rend les cas
/// énumérables par les tests, et ce qui interdit d'écrire un motif
/// « à peu près ». Chaque valeur nomme une cause MESURÉE.
enum MotifNonDetermination {
  /// Les quatre champs de capture ne permettent pas d'identifier le pari
  /// (`capturePariComplete == false`, R10).
  captureIncomplete,

  /// Le libellé du ticket n'est pas répertorié par le référentiel PMU.
  typeNonRepertorie,

  /// Le nombre de numéros joués ne correspond pas à la taille attendue
  /// (`tailleCombinaisonAttendue`). Aucune complétion n'est tentée.
  tailleCombinaisonAnormale,

  /// Aucun bloc API au code EXACT du pari joué (R19 : `E_TRIO`,
  /// `E_SUPER_QUATRE`, `E_MULTI` ne sont PAS le Tiercé/Quarté+/Quinté+).
  blocJusteAbsent,

  /// Le ticket est gagnant mais plusieurs rapports candidats existent sans
  /// critère de sélection réglementaire. Refus explicite plutôt que choix.
  rapportAmbigu,

  /// Arrivée ex æquo sans frontières de groupes persistées : la répartition
  /// des places ne peut pas être établie sans l'inventer.
  deadHeatSansGroupes,

  /// L'API indique elle-même que l'arrivée n'est pas définitive.
  arriveeNonDefinitive,

  /// Rapport officiel présent mais sans montant exploitable
  /// (`pourUnEuro` absent). Jamais remplacé par une valeur plausible.
  montantAbsent,

  /// Tirelire proposée mais éligibilité non démontrable : aucun montant.
  tirelireNonDeterminee,

  /// La combinaison Bonus publiée par l'API ne satisfait PAS les conditions
  /// réglementaires (règlement e-QUINTÉ+, art. 1 c et d), alors que la règle
  /// mesurée sur les captures la rendrait payable. Divergence documentée et
  /// NON tranchée : ni attribution, ni perte déclarée.
  ///
  /// ★ LOT B-3, décision utilisateur (option 3) : « Lorsqu'une combinaison
  /// Bonus publiée par l'API ne satisfait pas les conditions réglementaires
  /// étudiées : retourner nonDetermine, fournir un motif explicite
  /// d'ambiguïté réglementaire, ne pas attribuer de montant, ne pas déclarer
  /// le ticket perdant, ne pas sélectionner une autre catégorie par défaut. »
  ambiguiteReglementaireBonus;

  String toJson() => name;

  static MotifNonDetermination? fromJson(dynamic valeur) {
    if (valeur is! String) return null;
    for (final e in MotifNonDetermination.values) {
      if (e.name == valeur) return e;
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  2. RAPPORT PUBLIÉ — le RÉEL, tel que l'API l'a servi
// ═══════════════════════════════════════════════════════════════════════════

/// Un rapport OFFICIEL publié, conservé tel quel.
///
/// C'est la couche « ce qui existe », strictement distincte de « ce à quoi le
/// ticket a droit » et de « ce qui lui est attribué ». Plusieurs rapports
/// publiés ne signifient jamais plusieurs gains cumulables : l'éligibilité est
/// décidée ailleurs (B-3), et ces objets ne portent aucune notion de rang
/// gagnant.
///
/// Aucune méthode de ce type ne compare deux rapports entre eux par montant :
/// il n'y a ni `compareTo` sur [pourUnEuro], ni `operator >`.
class RapportPublie {
  /// Code API du bloc parent (`E_QUINTE_PLUS`, `E_TIERCE`, …).
  final String codePmu;

  /// Libellé officiel complet (`« e-Quinté+ Ordre + Tirelire »`, …).
  ///
  /// C'est la SEULE source fiable de la variante : mesuré, un `E_TIERCE`
  /// publie « e-Tiercé Ordre » ET « e-Tiercé Désordre » avec la MÊME
  /// combinaison et deux dividendes différents.
  final String libelle;

  /// Variante déduite du libellé (délégation à `gain_ticket_calculator`,
  /// 0 import, donc aucun risque de cycle).
  final VarianteRapport variante;

  /// Combinaison publiée (`« 9-4-15-10-1 »`). Peut contenir `NP`.
  final String combinaison;

  /// Rapport pour **1 € engagé**, en euros. LA SEULE valeur monétaire.
  /// `null` si l'API ne l'a pas fourni — jamais comblé (motif
  /// [MotifNonDetermination.montantAbsent]).
  final double? pourUnEuro;

  /// `rangCombinaisonPayable` publié, conservé sans interprétation.
  final int? rang;

  /// `miseBase` du BLOC, en centimes. **AUDIT UNIQUEMENT — ne pas calculer
  /// avec.** Voir la note R17 en tête de fichier : les mises de base diffèrent
  /// selon le bloc, donc s'en servir pour diviser serait une erreur d'unité.
  final int? miseBaseCentimes;

  /// `true` si l'API a explicitement marqué ce rapport comme remboursé.
  final bool rembourse;

  const RapportPublie({
    required this.codePmu,
    required this.libelle,
    required this.combinaison,
    required this.pourUnEuro,
    this.variante = VarianteRapport.illisible,
    this.rang,
    this.miseBaseCentimes,
    this.rembourse = false,
  });

  /// `true` si le montant est exploitable. Un montant nul ou négatif n'est
  /// PAS un montant : il ne peut pas fonder un gain.
  bool get aUnMontantExploitable => pourUnEuro != null && pourUnEuro! > 0;

  /// Numéros de la combinaison, dans l'ordre publié, ou `null` si illisible.
  ///
  /// Une combinaison contenant `NP` (non-partant) n'est PAS une combinaison de
  /// chevaux : elle rend `null`, comme dans `RapportOfficiel`.
  List<int>? get numeros {
    final brut = combinaison.trim();
    if (brut.isEmpty) return null;
    final out = <int>[];
    for (final part in brut.split('-')) {
      final t = part.trim();
      if (t.isEmpty) return null;
      if (t.toUpperCase() == 'NP') return null;
      final n = int.tryParse(t);
      if (n == null) return null;
      out.add(n);
    }
    return out;
  }

  /// Sérialisation. `pourUnEuro` est écrit tel quel : c'est un double en euros.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'codePmu': codePmu,
        'libelle': libelle,
        'variante': variante.name,
        'combinaison': combinaison,
        'pourUnEuro': pourUnEuro,
        'rang': rang,
        'miseBaseCentimes': miseBaseCentimes,
        'rembourse': rembourse,
      };

  /// Lecture TOLÉRANTE : champ absent ⇒ valeur par défaut sûre, jamais une
  /// supposition sur le contenu. `pourUnEuro` absent reste `null`.
  static RapportPublie fromJson(Map<String, dynamic> j) {
    return RapportPublie(
      codePmu: (j['codePmu'] as String?) ?? '',
      libelle: (j['libelle'] as String?) ?? '',
      variante: _varianteDepuisNom(j['variante'] as String?),
      combinaison: (j['combinaison'] as String?) ?? '',
      pourUnEuro: (j['pourUnEuro'] as num?)?.toDouble(),
      rang: (j['rang'] as num?)?.toInt(),
      miseBaseCentimes: (j['miseBaseCentimes'] as num?)?.toInt(),
      rembourse: j['rembourse'] == true,
    );
  }

  static VarianteRapport _varianteDepuisNom(String? nom) {
    if (nom == null) return VarianteRapport.illisible;
    for (final v in VarianteRapport.values) {
      if (v.name == nom) return v;
    }
    return VarianteRapport.illisible;
  }

  @override
  bool operator ==(Object other) =>
      other is RapportPublie &&
      other.codePmu == codePmu &&
      other.libelle == libelle &&
      other.variante == variante &&
      other.combinaison == combinaison &&
      other.pourUnEuro == pourUnEuro &&
      other.rang == rang &&
      other.miseBaseCentimes == miseBaseCentimes &&
      other.rembourse == rembourse;

  @override
  int get hashCode => Object.hash(codePmu, libelle, variante, combinaison,
      pourUnEuro, rang, miseBaseCentimes, rembourse);

  @override
  String toString() => 'RapportPublie($codePmu | "$libelle" | $combinaison '
      '| ${pourUnEuro ?? "?"} €/€ | rang $rang)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. RAPPORT ATTRIBUÉ — ce que le ticket a RÉELLEMENT gagné
// ═══════════════════════════════════════════════════════════════════════════

/// Un rapport RETENU pour un ticket, avec la mise qui lui est appliquée et le
/// montant qui en résulte.
///
/// Le montant est CALCULÉ UNE FOIS puis STOCKÉ : ce n'est pas un getter
/// recalculable. Deux raisons :
///
///  1. un getter `mise * pourUnEuro` pourrait voir l'un de ses deux termes
///     changer sans que le montant affiché suive — désynchronisation
///     silencieuse impossible ici ;
///  2. l'audit d'un gain doit pouvoir relire le montant EXACT qui a été
///     enregistré, pas le recalculer avec un code qui aura peut-être évolué.
///
/// [RapportAttribue.calculer] est le SEUL constructeur public : il est donc
/// impossible de fabriquer un attribué dont le montant ne serait pas le
/// produit de sa mise par son rapport.
class RapportAttribue {
  /// La preuve : le rapport officiel retenu.
  final RapportPublie rapport;

  /// Mise RÉELLEMENT engagée sur ce rapport.
  ///
  /// Pour Gagnant+Placé, c'est `miseGagnant` ou `misePlace` — jamais la mise
  /// totale du ticket. C'est ce qui interdit tout double comptage : deux
  /// [RapportAttribue] ne peuvent pas porter la même mise, puisqu'ils portent
  /// deux mises distinctes du modèle.
  final double miseAppliquee;

  /// Montant de retour, en euros, calculé à la construction.
  final double montantRetour;

  const RapportAttribue._({
    required this.rapport,
    required this.miseAppliquee,
    required this.montantRetour,
  });

  /// Construit un rapport attribué à partir de sa mise et de son rapport
  /// officiel. `montantRetour = miseAppliquee × rapport.pourUnEuro`.
  ///
  /// [miseAppliquee] doit être strictement positive : une mise nulle ou
  /// négative ne fonde aucun gain. Une [ArgumentError] est levée plutôt que de
  /// produire silencieusement un montant nul qui passerait pour « perdu ».
  factory RapportAttribue.calculer({
    required RapportPublie rapport,
    required double miseAppliquee,
  }) {
    if (!(miseAppliquee > 0)) {
      throw ArgumentError.value(miseAppliquee, 'miseAppliquee',
          'une mise nulle ou négative ne peut fonder aucun gain');
    }
    final montant = rapport.pourUnEuro;
    if (montant == null) {
      throw StateError(
        'RapportAttribue.calculer : « ${rapport.libelle} » ne porte aucun '
        'pourUnEuro. Aucun montant ne doit être inventé — utiliser '
        'MotifNonDetermination.montantAbsent en amont.',
      );
    }
    if (!(montant > 0)) {
      throw StateError(
        'RapportAttribue.calculer : « ${rapport.libelle} » porte un montant '
        'non exploitable ($montant).',
      );
    }
    return RapportAttribue._(
      rapport: rapport,
      miseAppliquee: miseAppliquee,
      montantRetour: miseAppliquee * montant,
    );
  }

  /// Variante du rapport retenu — raccourci de lecture pour l'affichage.
  /// C'est ce champ, et non l'heuristique historique `RapportPmu.estOrdre`,
  /// qui doit distinguer Ordre de Désordre (R16).
  VarianteRapport get variante => rapport.variante;

  /// `true` si ce rapport est un rapport dans l'ordre exact.
  bool get estOrdre => rapport.variante == VarianteRapport.ordre;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'rapport': rapport.toJson(),
        'miseAppliquee': miseAppliquee,
        'montantRetour': montantRetour,
      };

  static RapportAttribue fromJson(Map<String, dynamic> j) {
    final sous = j['rapport'];
    if (sous is! Map) {
      throw const FormatException(
          'RapportAttribue.fromJson : clé « rapport » illisible');
    }
    return RapportAttribue._(
      rapport: RapportPublie.fromJson(Map<String, dynamic>.from(sous)),
      miseAppliquee: (j['miseAppliquee'] as num?)?.toDouble() ?? 0.0,
      montantRetour: (j['montantRetour'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RapportAttribue &&
      other.rapport == rapport &&
      other.miseAppliquee == miseAppliquee &&
      other.montantRetour == montantRetour;

  @override
  int get hashCode => Object.hash(rapport, miseAppliquee, montantRetour);

  @override
  String toString() => 'RapportAttribue("${rapport.libelle}" '
      '${rapport.combinaison} | mise $miseAppliquee € '
      '| retour $montantRetour €)';
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. UTILITAIRE PUR — borne d'audit, sans décision
// ═══════════════════════════════════════════════════════════════════════════

/// Somme des montants de retour d'une liste de rapports attribués.
///
/// Fournie ici parce qu'elle n'a besoin d'aucune règle : c'est une addition.
/// Elle ne décide pas QUELS rapports sont attribués (B-3) et ne filtre rien.
/// Un ticket Gagnant+Placé y trouve naturellement la somme de ses deux
/// composantes ; un ticket à rapport unique y trouve ce rapport.
double totalDesMontantsRetour(List<RapportAttribue> attribues) {
  var total = 0.0;
  for (final a in attribues) {
    total += a.montantRetour;
  }
  return total;
}
