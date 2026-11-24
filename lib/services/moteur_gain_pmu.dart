// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-3 — MOTEUR PUR DE RÉSOLUTION DES GAINS PMU
//
//  CE FICHIER EST UN MOTEUR. IL N'EST BRANCHÉ NULLE PART.
//
//  Aucun écran, aucun provider, aucun service de persistance ne l'importe.
//  Il ne modifie donc AUCUN comportement existant. Aucune I/O, aucun
//  `SharedPreferences`, aucun `setState`, aucun `DateTime.now()`.
//
//  ───────────────────────────────────────────────────────────────────────────
//  ARCHITECTURE VALIDÉE (solution A) — TROIS RESPONSABILITÉS SÉPARÉES
//  ───────────────────────────────────────────────────────────────────────────
//
//  1. `arbitre_variante_pmu.dart` — décide la VARIANTE (Ordre/Désordre) à
//     partir de l'arrivée officielle définitive, puis restreint les rapports
//     candidats. Il ne lit AUCUN dividende.
//
//  2. `resolveur_rapport_pmu.dart` — INCHANGÉ. Reçoit la liste restreinte et
//     exerce toutes ses validations. S'il refuse, aucun rapport n'est attribué
//     et le refus est traduit tel quel. Jamais forcé.
//
//  3. CE FICHIER — calcule le montant UNIQUEMENT après acceptation du
//     résolveur, et traite les domaines qu'il ne couvre pas : Bonus 4sur5 /
//     Bonus 3 / Bonus Quarté+, Gagnant+Placé à deux composantes.
//
//  ───────────────────────────────────────────────────────────────────────────
//  DÉMONSTRATION DE DÉLÉGATION — MESURÉE, PAS AFFIRMÉE
//  ───────────────────────────────────────────────────────────────────────────
//
//  Sonde exécutée sur le bloc réel `E_QUINTE_PLUS` de R1C6_15112026 :
//
//    liste COMPLÈTE (Ordre + Désordre + Tirelire)      → refus ambiguiteTirelire
//    restreinte à ORDRE seul                            → ACCEPTÉ
//    restreinte à DÉSORDRE seul                         → ACCEPTÉ
//    restreinte à TIRELIRE seule                        → refus ambiguiteTirelire
//    Tiercé restreint à ORDRE seul                      → ACCEPTÉ
//
//  ⇒ le filtrage de l'arbitre rend effectivement Ordre/Désordre payable par
//    le résolveur. La délégation est donc RÉELLE, pas décorative.
//
//  ⚠️ CAS REFUSÉ, NON CONTOURNÉ : la TIRELIRE. `identifierRapportExact`
//     porte un garde inconditionnel qui refuse tout rapport de variante
//     `tirelire`, au motif que « son statut de rapport définitif n'est pas
//     démontré course par course ». L'arbitre, lui, le démontre (art. 7.1 +
//     égalité de combinaison), mais le résolveur ne peut pas le savoir.
//     Conformément à la consigne, ce cas est ARRÊTÉ et rendu en
//     `nonDetermine(tirelireNonDeterminee)` avec la cause exacte — il n'est ni
//     contourné, ni payé au mauvais rapport. Arbitrage utilisateur requis.
//
//  ───────────────────────────────────────────────────────────────────────────
//  R22 — RÈGLE D'ÉLIGIBILITÉ DES BONUS (celle des 5 courses mesurées)
//  ───────────────────────────────────────────────────────────────────────────
//
//  `top5` = les 5 premiers de l'arrivée officielle, dans l'ordre. Contrôle de
//  cohérence : la combinaison du rapport « e-Quinté+ Ordre » publié doit être
//  IDENTIQUE. Mesuré 5/5. En cas de désaccord ⇒ `rapportAmbigu`, jamais un
//  choix silencieux entre deux références.
//
//      ① ORDRE        si T == top5 (ensemble) ET ordre(T) == top5
//      ② DÉSORDRE     si T == top5 (ensemble) ET ordre(T) != top5
//      ③ BONUS 4sur5  si ∃ comb4 publiée ⊆ T ET |T ∖ top5| ≥ 1
//      ④ BONUS 3      si ∃ comb3 publiée ⊆ T ET |T ∖ top4| ≥ 2
//
//  Premier rang satisfait, dans cet ordre. Sinon perdant.
//
//  ⚠️ GARDE-FOU DÉCISIF : un Bonus n'est JAMAIS attribué sur la seule présence
//     d'une sous-combinaison publiée. Il faut en plus que le ticket contienne
//     au moins un cheval HORS du top5 (4sur5) ou deux hors du top4 (Bonus 3).
//     C'est ce qui empêche un ticket « top5 dans le désordre » — qui relève du
//     DÉSORDRE — de toucher aussi un Bonus.
//
//  ───────────────────────────────────────────────────────────────────────────
//  QUARTÉ+ — BONUS MESURÉ
//  ───────────────────────────────────────────────────────────────────────────
//
//  Mesuré 5/5 : la combinaison du « e-Bonus » du Quarté+ est EXACTEMENT le
//  top3 (sous-ensemble strict du top4). Règle appliquée : `comb3 publiée ⊆ T`
//  ET `|T ∖ top3| ≥ 1`. Sur un ticket de 4 chevaux contenant le top3, la
//  seconde condition est automatiquement vraie.
//
//  ⚠️ DIVERGENCE R22 DÉCLARÉE : le règlement (art. 1 c/d) décrit le Bonus
//     comme « 4 chevaux aux 4 premières places ET 1 cheval à un rang SUPÉRIEUR
//     au cinquième ». Sur les 5 captures Quinté+ réelles, TOUTES les
//     combinaisons Bonus publiées sont des sous-ensembles du top5 : la
//     condition « rang supérieur au cinquième » est inapplicable telle quelle
//     sur ces données. La règle ci-dessus est celle qui reproduit les 5 cas
//     mesurés. Elle est conservée à l'identique, sans invention.
//
//  ───────────────────────────────────────────────────────────────────────────
//  EXCLUSIVITÉ DES CATÉGORIES — DÉMONTRÉE PAR CARDINALITÉ, PAS PAR PRIORITÉ
//  ───────────────────────────────────────────────────────────────────────────
//
//    • ORDRE / DÉSORDRE exigent T == top5 (5 chevaux) ;
//    • BONUS 4sur5 exige |T ∖ top5| ≥ 1, donc T ≠ top5 : mutuellement exclusif
//      par construction ;
//    • BONUS 3 n'est évalué qu'en repli, et son garde |T ∖ top4| ≥ 2 exclut
//      tout ticket entièrement dans le top4.
//  Aucune règle de priorité n'est inventée : l'exclusivité découle des cardinaux.
//
//  ───────────────────────────────────────────────────────────────────────────
//  GAGNANT + PLACÉ — DEUX COMPOSANTES, DEUX MISES, JAMAIS DÉDOUBLÉES
//  ───────────────────────────────────────────────────────────────────────────
//
//  Gain Gagnant = miseGagnant × dividendePourUnEuro(E_SIMPLE_GAGNANT)
//  Gain Placé   = misePlace   × dividendePourUnEuro(E_SIMPLE_PLACE)
//
//  Chaque composante ne porte QUE sa propre mise. Une composante perdante vaut
//  zéro et n'entre pas dans `composantes`. La mise totale du ticket n'est
//  jamais utilisée pour calculer : elle n'existe que comme somme de bilan.
//
//  ───────────────────────────────────────────────────────────────────────────
//  UNITÉ — POINT SIGNALÉ, NON « CORRIGÉ » SILENCIEUSEMENT
//  ───────────────────────────────────────────────────────────────────────────
//
//  Mesuré : le champ brut `dividendePourUnEuro` de l'API est en CENTIMES de
//  retour par euro (R1C6 : `E_SIMPLE_GAGNANT` pe=750 ⇒ 7,50 € pour 1 €).
//  `RapportOfficiel.depuisJson` divise par 100 et rend des EUROS.
//  `RapportPublie.pourUnEuro` est donc alimenté en EUROS par
//  `rapportPublieDepuisJson`, qui délègue à cette autorité et ne renormalise
//  jamais. La documentation B-0 (« en euros ») est donc exacte POUR LA VALEUR
//  QUI LUI EST FOURNIE, mais pas pour le champ brut de l'API : ce point est
//  signalé sans modifier le B-0 validé.
//
//  ★ AUDIT CLÔTURÉ (lot B-3, décision utilisateur) — `dividendeUnite`
//  ─────────────────────────────────────────────────────────────────────────
//  Le champ de bloc `dividendeUnite` prend DEUX valeurs réelles dans les
//  captures : `PourUnEuro` (1 602 blocs) et `PourUneMiseDeBase` (289 blocs).
//  Il n'est PAS lu directement par la chaîne B-3 : `_lirePourUnEuro` ne
//  consulte que `dividendePourUnEuro`, avec repli sur
//  `dividendePourUneMiseDeBase ÷ miseBaseCentimes`.
//
//  Cet audit a mesuré, sur 4 684 rapports réels, que les deux conventions sont
//  ÉQUIVALENTES après la conversion appliquée :
//    • `PourUnEuro`          : dividende = dividendePourUnEuro
//                              = dividendePourUneMiseDeBase (miseBase = 100)
//    • `PourUneMiseDeBase`   : dividende = dividendePourUneMiseDeBase
//                              = dividendePourUnEuro × miseBase / 100
//  Contrôle : `pbd = pe × miseBase/100` est vérifié sur 4 684 / 4 684 rapports.
//  L'unique écart d'un centime concerne la Tirelire et s'explique par le fait
//  que le supplément est un MULTIPLE ENTIER de 1 000 € (art. 7.1), donc non
//  divisible exactement par `miseBase/100`. Ce n'est pas une erreur.
//
//  ⚠️ AUCUNE ERREUR N'EST DÉMONTRÉE. Les conversions actuelles sont CONSERVÉES.
//  Angle mort résiduel, documenté et NON corrigé (aucune preuve d'erreur) :
//  la correction repose sur la présence de `dividendePourUnEuro` dans tous les
//  rapports mesurés ; `dividendeUnite` n'est jamais consulté pour choisir la
//  branche. Si l'API changeait de convention sans changer de nom de champ, ce
//  choix ne serait pas piloté par la donnée déclarée.
//
//  ───────────────────────────────────────────────────────────────────────────
//  INTERDITS RESPECTÉS (rendus impossibles, pas seulement évités)
//  ───────────────────────────────────────────────────────────────────────────
//
//   • Aucun `reduce(MAX)`, aucun `sort` par dividende, aucun `first` de repli :
//     la sélection est une ÉGALITÉ de code et de variante, jamais un classement.
//   • Aucun montant inventé : données insuffisantes ⇒ `nonDetermine` + motif
//     FERMÉ de `MotifNonDetermination` (B-0).
//   • Aucune arrivée provisoire exploitée ⇒ `arriveeNonDefinitive`.
//   • Aucun groupe d'ex æquo inventé ⇒ `deadHeatSansGroupes`.
//   • L'option Max est HORS PÉRIMÈTRE (0 occurrence dans le règlement).
//  ═══════════════════════════════════════════════════════════════════════════

import 'arbitre_variante_pmu.dart';
import 'gain_pmu_types.dart';
import 'gain_ticket_calculator.dart'
    show
        IdentificationGagnantPlace,
        RapportOfficiel,
        TypePariJoue,
        VarianteRapport,
        codeApiPourType,
        identifierGagnantPlace,
        tailleCombinaisonAttendue,
        typePariDepuisLibelle,
        varianteDepuisLibelle;
import 'resolveur_rapport_pmu.dart'
    show MotifRefusPmu, ResolutionRapportPmu, resoudreRapportPmu;

// ═══════════════════════════════════════════════════════════════════════════
//  1. ENTRÉE — le ticket, tel qu'il est
// ═══════════════════════════════════════════════════════════════════════════

/// Ce que le ticket ENGAGE réellement, composante par composante.
///
/// [miseGagnant] et [misePlace] sont distinctes et facultatives : un Simple
/// Gagnant n'a que la première, un Simple Placé que la seconde, un
/// Gagnant+Placé les deux. Un ticket à une seule composante utilise
/// [miseSimple] ; aucun montant n'est jamais dédoublé.
class MiseEngagee {
  /// Mise d'un ticket à UNE composante (Simple, Couplé, Tiercé, Quarté+…).
  final double? miseSimple;

  /// Mise de la composante Gagnant d'un ticket à deux composantes.
  final double? miseGagnant;

  /// Mise de la composante Placé d'un ticket à deux composantes.
  final double? misePlace;

  const MiseEngagee({this.miseSimple, this.miseGagnant, this.misePlace});

  /// Mise d'une composante simple.
  const MiseEngagee.simple(double mise) : this(miseSimple: mise);

  /// Mise d'un ticket Gagnant+Placé : deux mises DISTINCTES.
  const MiseEngagee.gagnantPlace({
    required double gagnant,
    required double place,
  }) : this(miseGagnant: gagnant, misePlace: place);

  /// Somme réellement engagée. Jamais utilisée pour calculer un gain : c'est
  /// une donnée de bilan, jamais un opérande de multiplication.
  double get total {
    var t = 0.0;
    if (miseSimple != null) t += miseSimple!;
    if (miseGagnant != null) t += miseGagnant!;
    if (misePlace != null) t += misePlace!;
    return t;
  }

  /// `true` si au moins une mise positive est engagée.
  bool get aUneMisePositive =>
      (miseSimple ?? 0) > 0 || (miseGagnant ?? 0) > 0 || (misePlace ?? 0) > 0;
}

// ═══════════════════════════════════════════════════════════════════════════
//  2. SORTIE — un rôle explicite par composante, jamais déduit d'un libellé
// ═══════════════════════════════════════════════════════════════════════════

/// Rôle d'une composante dans le ticket. Porté par la DONNÉE, pas deviné.
enum RoleComposante {
  /// Ticket à une seule composante.
  unique,

  /// Composante Gagnant d'un ticket à deux composantes.
  gagnant,

  /// Composante Placé d'un ticket à deux composantes.
  place,
}

/// Une composante payée, avec la mise qui lui est PROPRE.
///
/// [mise] n'est jamais la mise totale du ticket : c'est la mise de CETTE
/// composante. C'est la garantie structurelle contre le double comptage.
class ComposanteGain {
  /// Libellé officiel du rapport retenu (traçabilité d'audit).
  final String libelleRapport;

  /// Combinaison officielle du rapport retenu.
  final String combinaisonRapport;

  /// Catégorie attribuée (Ordre, Désordre, Bonus 4sur5, Bonus 3, Bonus…).
  final VarianteRapport categorie;

  /// Rôle de la composante. Explicite : aucun test sur le libellé.
  final RoleComposante role;

  /// Mise de CETTE composante, en euros.
  final double mise;

  /// Rapport pour 1 € engagé, en euros.
  final double pourUnEuro;

  /// Retour de cette composante : `mise × pourUnEuro`, calculé une seule fois.
  ///
  /// ⚠️ POUR UNE COMPOSANTE REMBOURSÉE, ce champ vaut **0,0** et non
  ///    `mise × pourUnEuro` : un remboursement n'est pas un gain. Le montant
  ///    effectivement reversé se lit alors dans [miseRemboursee].
  final double montantRetour;

  /// `true` si le rapport officiel de cette composante est marqué remboursé
  /// par l'opérateur (non-partant, annulation, remboursement réglementaire).
  ///
  /// ★ MESURE QUI A MOTIVÉ CE CHAMP : un Gagnant+Placé dont la composante
  ///   Placé est remboursée rendait `attribue` avec `pourUnEuro = 2,10`
  ///   appliqué à la mise — soit 21,0 € comptés comme un GAIN, alors que
  ///   l'opérateur n'a publié aucun gain sur cette composante. Le remboursement
  ///   intégral d'une mise de 10 € doit rendre 10 €, sans jamais appliquer le
  ///   coefficient du rapport.
  ///
  /// ⚠️ Un remboursement n'est NI un gain NI une perte : il est conservé
  ///    distinct du gain jusqu'à l'affichage.
  final bool rembourse;

  /// Mise EFFECTIVEMENT reversée au joueur sur cette composante.
  ///
  /// Vaut [mise] si [rembourse], `0.0` sinon — un gain n'est pas un
  /// remboursement, et réciproquement. Aucune valeur n'est déduite d'un
  /// dividende : le remboursement réglementaire porte sur la mise engagée.
  double get miseRemboursee => rembourse ? mise : 0.0;

  /// Montant total reversé au joueur pour cette composante :
  /// gain + remboursement. Distinct de [montantRetour], qui ne compte QUE
  /// le gain gagné.
  double get montantReverse => montantRetour + miseRemboursee;

  const ComposanteGain({
    required this.libelleRapport,
    required this.combinaisonRapport,
    required this.categorie,
    required this.mise,
    required this.pourUnEuro,
    required this.montantRetour,
    this.role = RoleComposante.unique,
    this.rembourse = false,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'libelleRapport': libelleRapport,
        'combinaisonRapport': combinaisonRapport,
        'categorie': categorie.name,
        'role': role.name,
        'mise': mise,
        'pourUnEuro': pourUnEuro,
        'montantRetour': montantRetour,
        // ⚠️ CLÉ AJOUTÉE — ABSENTE = `false`. Les enregistrements historiques
        //    ne portent pas cette clé et restent donc lus comme « non
        //    remboursé », ce qui est exact pour tout verdict antérieur (aucun
        //    d'eux ne représentait de remboursement partiel).
        if (rembourse) 'rembourse': true,
      };

  static ComposanteGain? fromJson(Map<String, dynamic> j) {
    final variante = _varianteDepuisNom(j['categorie'] as String?);
    if (variante == null) return null;
    return ComposanteGain(
      libelleRapport: (j['libelleRapport'] as String?) ?? '',
      combinaisonRapport: (j['combinaisonRapport'] as String?) ?? '',
      categorie: variante,
      role: _roleDepuisNom(j['role'] as String?),
      mise: (j['mise'] as num?)?.toDouble() ?? 0.0,
      pourUnEuro: (j['pourUnEuro'] as num?)?.toDouble() ?? 0.0,
      montantRetour: (j['montantRetour'] as num?)?.toDouble() ?? 0.0,
      // Lecture tolérante : seule la valeur booléenne `true` active le
      // remboursement. `null` ou absent ⇒ `false`.
      rembourse: j['rembourse'] == true,
    );
  }

  static VarianteRapport? _varianteDepuisNom(String? nom) {
    if (nom == null) return null;
    for (final v in VarianteRapport.values) {
      if (v.name == nom) return v;
    }
    return null;
  }

  static RoleComposante _roleDepuisNom(String? nom) {
    if (nom == null) return RoleComposante.unique;
    for (final r in RoleComposante.values) {
      if (r.name == nom) return r;
    }
    return RoleComposante.unique;
  }

  @override
  String toString() => 'ComposanteGain(${categorie.name}/${role.name} "'
      '$libelleRapport" $combinaisonRapport | $mise € × $pourUnEuro '
      '= $montantRetour €${rembourse ? " | REMBOURSÉ $mise €" : ""})';
}

/// Verdict COMPLET d'un ticket.
///
/// Les montants sont préparés pour les lots suivants (B-4 enregistrement,
/// B-5 affichage) : [gainGagnant], [gainPlace] et [total] sont DISTINCTS.
/// Aucun de ces trois champs n'est un getter recalculable.
class VerdictGain {
  /// État du gain. `nonDetermine` n'est jamais un montant nul déguisé.
  final EtatGain etat;

  /// Motif fermé quand [etat] vaut `nonDetermine` ; `null` sinon.
  final MotifNonDetermination? motif;

  /// Explication lisible, toujours renseignée en cas de non-détermination.
  final String explication;

  /// État de la Tirelire, INDÉPENDANT du rapport Ordre.
  final EtatTirelire etatTirelire;

  /// Composantes réellement payées. Vide si perdant ou non déterminé.
  final List<ComposanteGain> composantes;

  /// Gain de la composante Gagnant, 0 si absente ou perdante.
  final double gainGagnant;

  /// Gain de la composante Placé, 0 si absente ou perdante.
  final double gainPlace;

  /// Gain total = somme des composantes. Jamais mise + gain.
  ///
  /// ⚠️ N'INCLUT AUCUN REMBOURSEMENT. C'est le « Gain gagné » de l'interface,
  ///    strictement distinct de [montantReverse]. Un remboursement n'est pas
  ///    un gain : les additionner ici rendrait « Gain gagné » faux.
  final double total;

  /// Somme des mises EFFECTIVEMENT reversées au joueur (remboursements).
  ///
  /// Distinct de [total] par construction. `0.0` quand aucun remboursement.
  /// Ce champ n'est JAMAIS versé dans `montantOfficielPmu`, dont la
  /// signification historique est « gain gagné brut officiel ».
  final double remboursement;

  /// Total effectivement reversé au joueur : gains + remboursements.
  ///
  /// C'est l'assiette du BÉNÉFICE NET : `montantReverse − mises engagées`.
  double get montantReverse => total + remboursement;

  /// `true` si au moins une composante a été remboursée.
  bool get aUnRemboursement => remboursement > 0;

  const VerdictGain._({
    required this.etat,
    required this.motif,
    required this.explication,
    required this.etatTirelire,
    required this.composantes,
    required this.gainGagnant,
    required this.gainPlace,
    required this.total,
    required this.remboursement,
  });

  /// Aucun gain établi : un motif FERMÉ est obligatoire.
  factory VerdictGain.nonDetermine({
    required MotifNonDetermination motif,
    required String explication,
    EtatTirelire etatTirelire = EtatTirelire.sansObjet,
  }) {
    return VerdictGain._(
      etat: EtatGain.nonDetermine,
      motif: motif,
      explication: explication,
      etatTirelire: etatTirelire,
      composantes: const <ComposanteGain>[],
      gainGagnant: 0.0,
      gainPlace: 0.0,
      total: 0.0,
      remboursement: 0.0,
    );
  }

  /// Pari perdant, établi (pas supposé).
  factory VerdictGain.perdu({
    required String explication,
    EtatTirelire etatTirelire = EtatTirelire.sansObjet,
  }) {
    return VerdictGain._(
      etat: EtatGain.perdu,
      motif: null,
      explication: explication,
      etatTirelire: etatTirelire,
      composantes: const <ComposanteGain>[],
      gainGagnant: 0.0,
      gainPlace: 0.0,
      total: 0.0,
      remboursement: 0.0,
    );
  }

  /// Pari remboursé par l'opérateur.
  ///
  /// [remboursement] porte la somme EFFECTIVEMENT reversée quand elle est
  /// connue (remboursement intégral des mises engagées). Un remboursement
  /// n'est ni un gain ni une perte : [total] reste donc `0.0`.
  factory VerdictGain.rembourse({
    required String explication,
    EtatTirelire etatTirelire = EtatTirelire.sansObjet,
    double remboursement = 0.0,
  }) {
    return VerdictGain._(
      etat: EtatGain.rembourse,
      motif: null,
      explication: explication,
      etatTirelire: etatTirelire,
      composantes: const <ComposanteGain>[],
      gainGagnant: 0.0,
      gainPlace: 0.0,
      total: 0.0,
      remboursement: remboursement,
    );
  }

  /// Gain attribué, construit à partir des composantes payées.
  ///
  /// [composantes] doit être non vide : un « gain attribué » sans composante
  /// serait un montant sans preuve.
  ///
  /// ⚠️ Les composantes REMBOURSÉES sont acceptées : elles portent
  ///    `montantRetour = 0,0` (donc n'entrent pas dans [total]) et leur mise
  ///    est accumulée dans [remboursement]. Un ticket Gagnant+Placé dont le
  ///    Placé est remboursé est ainsi `attribue` sur son seul gain, avec le
  ///    remboursement conservé à part — conformément à la règle « un
  ///    remboursement n'est ni un gain ni une perte ».
  factory VerdictGain.attribue({
    required List<ComposanteGain> composantes,
    EtatTirelire etatTirelire = EtatTirelire.sansObjet,
    String explication = '',
  }) {
    if (composantes.isEmpty) {
      throw ArgumentError.value(composantes, 'composantes',
          'un gain attribué exige au moins une composante justifiée');
    }
    var gagnant = 0.0;
    var place = 0.0;
    var total = 0.0;
    var rembourse = 0.0;
    for (final c in composantes) {
      // Un remboursement n'entre JAMAIS dans le gain : `montantRetour` vaut
      // déjà 0,0 pour une composante remboursée, et l'assertion ci-dessous
      // rend la règle structurelle plutôt que conventionnelle.
      assert(!c.rembourse || c.montantRetour == 0.0,
          'une composante remboursée ne peut porter aucun montantRetour');
      total += c.montantRetour;
      rembourse += c.miseRemboursee;
      switch (c.role) {
        case RoleComposante.gagnant:
          gagnant += c.montantRetour;
          break;
        case RoleComposante.place:
          place += c.montantRetour;
          break;
        case RoleComposante.unique:
          break;
      }
    }
    return VerdictGain._(
      etat: EtatGain.attribue,
      motif: null,
      explication: explication,
      etatTirelire: etatTirelire,
      composantes: List<ComposanteGain>.unmodifiable(composantes),
      gainGagnant: gagnant,
      gainPlace: place,
      total: total,
      remboursement: rembourse,
    );
  }

  /// `true` seulement si un gain a été établi.
  bool get estGagne => etat == EtatGain.attribue;

  /// `true` si le gain est indéterminable — aucun montant exploitable.
  bool get estNonDetermine => etat == EtatGain.nonDetermine;

  /// Mise TOTALE réellement engagée sur ce verdict (donnée de bilan).
  double get miseEngageeDesComposantes {
    var m = 0.0;
    for (final c in composantes) {
      m += c.mise;
    }
    return m;
  }

  @override
  String toString() => 'VerdictGain(${etat.name}'
      '${motif != null ? " / ${motif!.name}" : ""}'
      ' | tirelire=${etatTirelire.name}'
      ' | composantes=${composantes.length}'
      ' | gagnant=$gainGagnant place=$gainPlace total=$total'
      '${remboursement > 0 ? " rembourse=$remboursement" : ""})';
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. CONVERSIONS — délégation aux autorités, aucune conversion réécrite
// ═══════════════════════════════════════════════════════════════════════════

/// Projette un [RapportPublie] vers le type attendu par le résolveur.
RapportOfficiel versRapportOfficiel(RapportPublie r) => RapportOfficiel(
      typePari: r.codePmu,
      libelle: r.libelle,
      combinaison: r.combinaison,
      rapportPourUnEuro: r.pourUnEuro,
      rembourse: r.rembourse,
    );

/// Construit un [RapportPublie] depuis un objet `rapports[]` brut de l'API.
///
/// Délègue la normalisation à `RapportOfficiel.depuisJson` (centimes → euros
/// pour 1 €) : aucune conversion d'unité n'est réécrite ici.
RapportPublie? rapportPublieDepuisJson(
  Map<String, dynamic> json, {
  required String codePmu,
  required int? miseBaseCentimes,
}) {
  final officiel = RapportOfficiel.depuisJson(
    json,
    typePari: codePmu,
    miseBaseCentimes: miseBaseCentimes,
  );
  if (officiel == null) return null;
  return RapportPublie(
    codePmu: codePmu,
    libelle: officiel.libelle,
    combinaison: officiel.combinaison,
    variante: varianteDepuisLibelle(officiel.libelle),
    pourUnEuro: officiel.rapportPourUnEuro,
    rang: (json['rangCombinaisonPayable'] as num?)?.toInt(),
    miseBaseCentimes: miseBaseCentimes,
    rembourse: officiel.rembourse,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. LE MOTEUR — point d'entrée unique
// ═══════════════════════════════════════════════════════════════════════════

/// Résout le gain d'un ticket contre l'état officiel d'une course.
///
/// Ne rend JAMAIS `null` : soit un gain attribué, soit un état de non-gain
/// EXPLICITEMENT motivé. Aucun montant n'est jamais inventé.
VerdictGain resoudreGainTicket({
  required String libelleTypePari,
  required List<int> numerosJoues,
  required MiseEngagee mise,
  required EtatCourseOfficiel etat,
}) {
  final type = typePariDepuisLibelle(libelleTypePari);

  // ── 0. Libellé non répertorié : aucun calcul financier ────────────────────
  if (type == TypePariJoue.inconnu) {
    return VerdictGain.nonDetermine(
      motif: MotifNonDetermination.typeNonRepertorie,
      explication: 'Le libellé « $libelleTypePari » n\'est pas répertorié. '
          'Aucun type par défaut n\'est substitué : aucun calcul n\'est fait.',
    );
  }

  // ── 1. Mise exploitable ───────────────────────────────────────────────────
  if (!mise.aUneMisePositive) {
    return VerdictGain.nonDetermine(
      motif: MotifNonDetermination.montantAbsent,
      explication: 'Aucune mise positive n\'est engagée : un gain ne peut pas '
          'être fondé sur une mise nulle.',
    );
  }

  // ── 2. Arrivée explicitement provisoire : refus AVANT tout calcul ─────────
  if (etat.estProvisoire) {
    return VerdictGain.nonDetermine(
      motif: MotifNonDetermination.arriveeNonDefinitive,
      explication: 'L\'API indique explicitement que l\'arrivée n\'est pas '
          'définitive. Aucun gain n\'est calculé sur une arrivée provisoire, et '
          'aucune arrivée provisoire n\'est tenue pour définitive.',
    );
  }

  // ── 3. Gagnant+Placé : DEUX composantes, DEUX mises ───────────────────────
  if (type == TypePariJoue.gagnantPlace) {
    return _resoudreGagnantPlace(
      numerosJoues: numerosJoues,
      mise: mise,
      etat: etat,
    );
  }

  // ── 4. Contrôle de taille : aucun complément inventé ──────────────────────
  final tailleAttendue = tailleCombinaisonAttendue(type);
  if (tailleAttendue == null || numerosJoues.length != tailleAttendue) {
    return VerdictGain.nonDetermine(
      motif: MotifNonDetermination.tailleCombinaisonAnormale,
      explication: 'Le ticket porte ${numerosJoues.length} numéro(s) alors que '
          '$libelleTypePari en exige ${tailleAttendue ?? "?"}. '
          'Aucune complétion n\'est tentée.',
    );
  }

  // ── 4 bis. Mise de la composante UNIQUE ───────────────────────────────────
  // Tout type autre que Gagnant+Placé n'a qu'UNE composante : sa mise est
  // `miseSimple`. Si elle manque, aucun montant ne peut être calculé — et
  // surtout, on ne se rabat JAMAIS sur `total` (qui pourrait inclure une mise
  // d'une autre composante) ni sur une mise de Gagnant/Placé résiduelle.
  final miseUnique = mise.miseSimple;
  if (miseUnique == null || !(miseUnique > 0)) {
    return VerdictGain.nonDetermine(
      motif: MotifNonDetermination.montantAbsent,
      explication: 'Ce pari ($libelleTypePari) est à UNE composante mais aucune '
          'mise simple positive n\'est engagée. Aucun repli sur une mise de '
          'Gagnant/Placé ni sur la mise totale n\'est fait : le gain serait '
          'calculé sur une mise qui n\'a pas été jouée.',
    );
  }

  // ── 5. ARBITRAGE de la variante par l'arrivée officielle ──────────────────
  final arbitrage = arbitrerVariante(
    type: type,
    numerosJoues: numerosJoues,
    etat: etat,
  );

  switch (arbitrage.statut) {
    case StatutArbitrage.indetermine:
      return VerdictGain.nonDetermine(
        motif: arbitrage.motif ?? MotifNonDetermination.rapportAmbigu,
        explication: arbitrage.explication,
      );
    case StatutArbitrage.perdu:
      return VerdictGain.perdu(explication: arbitrage.explication);
    case StatutArbitrage.bonusSeulement:
      return _evaluerBonus(
        type: type,
        numerosJoues: numerosJoues,
        mise: miseUnique,
        premiersOfficiels: arbitrage.premiersOfficiels!,
        rapports: etat.rapports,
        explicationArbitrage: arbitrage.explication,
      );
    case StatutArbitrage.sansRestriction:
    case StatutArbitrage.varianteEtablie:
      break;
  }

  // ── 6. Tirelire : refus DÉCLARÉ du résolveur, non contourné ───────────────
  if (arbitrage.variante == VarianteRapport.tirelire) {
    return VerdictGain.nonDetermine(
      motif: MotifNonDetermination.tirelireNonDeterminee,
      etatTirelire: arbitrage.etatTirelire,
      explication: 'L\'arbitre a établi que « e-Quinté+ Ordre + Tirelire » '
          'constitue le rapport Ordre DÉFINITIF MAJORÉ du supplément '
          '(règlement art. 7.1). Mais '
          '`identifierRapportExact` refuse structurellement tout rapport de '
          'variante « tirelire » (garde inconditionnel : « son statut de rapport '
          'définitif n\'est pas démontré course par course ») et rend '
          '`ambiguiteTirelire`. Le refus n\'est PAS contourné : ni le rapport '
          'Ordre simple (qui n\'est pas le définitif et serait un mauvais '
          'montant), ni une somme des deux (qui compterait deux fois la part '
          'Ordre) ne sont substitués.',
    );
  }

  // ── 6 bis. ★ CORRECTION « Anomalie 1 » — PERTE DÉMONTRÉE PAR RECOUPEMENT ──
  //
  // MESURE QUI A MOTIVÉ CE BLOC (308 captures datées, 5 `prog_*.json`) :
  //   • 299/299 blocs `E_SIMPLE_GAGNANT` publient EXACTEMENT le 1er cheval de
  //     l'arrivée officielle ;
  //   • 299/299 blocs `E_SIMPLE_PLACE` publient EXACTEMENT les N premiers
  //     chevaux de l'arrivée, où N est le nombre de lignes du bloc (2 lignes
  //     quand ≤ 7 partants déclarés, 3 au-delà, 4 en cas d'ex æquo au 3e rang) ;
  //   • 192/192 `E_COUPLE_GAGNANT` et 191/191 `E_COUPLE_PLACE` idem ;
  //   • ZÉRO trou de rang : les rangs publiés sont toujours 1..N sans saut.
  //
  // PREUVE DE COMPLÉTUDE UTILISÉE ICI — elle n'est JAMAIS supposée :
  //   le bloc est réputé complet SI ET SEULEMENT SI l'ensemble de ses
  //   combinaisons recoupe EXACTEMENT les N premiers chevaux de l'arrivée
  //   officielle définitive, N = nombre de lignes publiées, et si ses rangs
  //   sont contigus de 1 à N. Les deux sources sont officielles et
  //   indépendantes : leur concordance EST la preuve.
  //
  //   Si le recoupement échoue (bloc partiel, tronqué, ou arrivée
  //   incohérente), on NE conclut PAS à la perte : le verdict reste
  //   `nonDetermine`. Une absence de rapport n'est donc jamais transformée en
  //   défaite, conformément à la règle validée.
  //
  // PÉRIMÈTRE VOLONTAIREMENT RESTREINT : seuls les types dont la mesure a
  // montré un recoupement parfait et sans ambiguïté sont couverts. `E_TRIO`,
  // `E_TIERCE` et `E_QUARTE_PLUS` ont leurs propres règles (Bonus, variantes)
  // et ne sont pas concernés — ils passent par l'arbitre plus haut.
  if (_blocEstDemontreComplet(
    type: type,
    numerosJoues: numerosJoues,
    etat: etat,
  )) {
    // Le bloc est complet et la combinaison jouée n'y figure pas (sinon le
    // résolveur aurait rendu un rapport). La perte est donc ÉTABLIE.
    return VerdictGain.perdu(
      explication: 'Le bloc officiel de $libelleTypePari est DÉMONTRÉ complet : '
          'ses ${_nbLignesBloc(type: type, etat: etat)} ligne(s) recoupent '
          'exactement l\'arrivée officielle définitive, avec des rangs contigus. '
          'La combinaison jouée (${numerosJoues.join("-")}) n\'y figure pas : la '
          'perte est établie par recoupement de deux sources officielles, sans '
          'aucune attribution de montant.',
    );
  }

  // ── 7. DÉLÉGATION AU RÉSOLVEUR sur la liste restreinte ────────────────────
  final resolution = resoudreRapportPmu(
    libelleTypePari: libelleTypePari,
    numerosJoues: numerosJoues,
    rapports: arbitrage.rapportsCompatibles.map(versRapportOfficiel).toList(),
  );

  if (resolution.refuse) {
    return _depuisRefusResolveur(
      resolution,
      arbitrage.etatTirelire,
      arbitrage.rapportsCompatibles,
      numerosJoues,
      miseUnique,
    );
  }

  final officiel = resolution.rapport!;
  final publie = _retrouverPublie(arbitrage.rapportsCompatibles, officiel);
  if (publie == null) {
    return VerdictGain.nonDetermine(
      motif: MotifNonDetermination.rapportAmbigu,
      etatTirelire: arbitrage.etatTirelire,
      explication: 'Le rapport retenu par le résolveur n\'a pas pu être '
          'retrouvé dans la liste restreinte : aucun montant n\'est attribué.',
    );
  }
  return _verdictDepuisRapportPublie(
    publie: publie,
    mise: miseUnique,
    role: RoleComposante.unique,
    etatTirelire: arbitrage.etatTirelire,
    explicationArbitrage: arbitrage.explication,
  );
}

// ───────────────────────────────────────────────────────────────────────────
//  Bonus — Quarté+ et Quinté+ (R22 + CONFORMITÉ RÉGLEMENTAIRE)
//
//  ★ LOT B-3 — DÉCISION UTILISATEUR (option 3), ajoutée après mesure.
//
//  MESURE QUI A MOTIVÉ CE CONTRÔLE (5 courses réelles) :
//    • 25 combinaisons « e-Bonus 4sur5 » publiées ;
//    •  5 seulement satisfont l'art. 1 c) — 4 chevaux classés aux QUATRE
//       premières places + 1 cheval de rang SUPÉRIEUR AU CINQUIÈME ;
//    • 20 ne le satisfont PAS : elles comportent 3 chevaux du top4 et le
//       5e cheval du top5 (rang 5), ce qui, à la lettre de l'art. 1 c),
//       relève du Bonus 3 (3 du top3 + 2 chevaux de rang > 4).
//
//  Comparaison exhaustive sur 126 puis 252 tickets : 16 puis 20 divergences,
//  TOUTES dans le sens « le moteur attribuait un Bonus que le règlement ne
//  prévoit pas ». Aucun faux négatif n'a été trouvé : la règle mesurée n'est
//  pas plus stricte que le règlement, elle est PLUS PERMISSIVE.
//
//  RÈGLE APPLIQUÉE ICI (et rien de plus) : lorsqu'une combinaison publiée
//  serait payable par la règle mesurée MAIS n'est pas conforme au texte, on ne
//  tranche pas. On rend `nonDetermine(ambiguiteReglementaireBonus)`.
//
//  ⚠️ CE N'EST PAS UNE NOUVELLE RÈGLE RÉGLEMENTAIRE GÉNÉRALE.
//     C'est un REFUS DE TRANCHER, exactement circonscrit aux cas où les deux
//     références se contredisent. Aucune condition réglementaire n'est
//     promue en règle de calcul ; aucune catégorie de repli n'est choisie.
// ───────────────────────────────────────────────────────────────────────────

/// Conformité d'une combinaison Bonus 4sur5 PUBLIÉE à l'art. 1 c).
///
/// Le texte exige « quatre chevaux classés aux quatre premières places [...] et
/// un cheval classé à un rang supérieur au cinquième ». La combinaison publiée
/// ne porte QUE les quatre premiers : elle doit donc être **exactement** le
/// top4. Si elle contient le 5e cheval classé (ou tout autre), elle décrit un
/// Bonus 3 déguisé, et le texte ne la prévoit pas comme Bonus 4sur5.
bool _bonus4ConformeReglement(List<int> comb, List<int> top5) {
  if (comb.length != 4 || top5.length < 4) return false;
  final top4 = top5.take(4).toSet();
  return comb.toSet().length == 4 && comb.toSet().difference(top4).isEmpty;
}

/// Conformité d'une combinaison Bonus 3 PUBLIÉE à l'art. 1 d).
///
/// Le texte exige « trois chevaux classés aux trois premières places [...] et
/// deux chevaux classés tous deux à des rangs supérieurs au quatrième ». La
/// combinaison publiée doit donc être **exactement** le top3 — les rangs 4 et 5
/// sont exclus.
bool _bonus3ConformeReglement(List<int> comb, List<int> top5) {
  if (comb.length != 3 || top5.length < 3) return false;
  final top3 = top5.take(3).toSet();
  return comb.toSet().length == 3 && comb.toSet().difference(top3).isEmpty;
}

VerdictGain _evaluerBonus({
  required TypePariJoue type,
  required List<int> numerosJoues,
  required double mise,
  required List<int> premiersOfficiels,
  required List<RapportPublie> rapports,
  required String explicationArbitrage,
}) {
  final code = type == TypePariJoue.quinte ? 'E_QUINTE_PLUS' : 'E_QUARTE_PLUS';
  final joues = numerosJoues.toSet();

  // ── Cohérence top officiel ↔ rapport Ordre publié : jamais tranchée en silence
  final rapportOrdre = _rapportOrdrePublie(rapports, code);
  if (rapportOrdre != null) {
    final nums = rapportOrdre.numeros;
    if (nums != null && !_memeOrdre(nums, premiersOfficiels)) {
      return VerdictGain.nonDetermine(
        motif: MotifNonDetermination.rapportAmbigu,
        explication: 'Deux références d\'arrivée DIVERGENT : l\'arrivée '
            'officielle donne ${premiersOfficiels.join("-")} et le rapport '
            '« ${rapportOrdre.libelle} » donne ${nums.join("-")}. Aucune des '
            'deux n\'est choisie silencieusement : aucun Bonus n\'est attribué.',
      );
    }
  }

  // ── Quinté+ : BONUS 4sur5 puis BONUS 3 (règle R22 ③④) ────────────────────
  if (type == TypePariJoue.quinte && premiersOfficiels.length >= 5) {
    final top5 = premiersOfficiels.take(5).toList();
    final top5s = top5.toSet();
    final top4s = top5.take(4).toSet();

    // ③ BONUS 4sur5 — comb4 publiée ⊆ T **ET** |T ∖ top5| ≥ 1
    final horsTop5 = joues.difference(top5s);
    final bonus4 = rapports
        .where((r) =>
            r.codePmu == code && r.variante == VarianteRapport.bonus4sur5)
        .toList();
    if (bonus4.isEmpty) {
      return VerdictGain.nonDetermine(
        motif: MotifNonDetermination.blocJusteAbsent,
        explication: 'Aucun rapport « e-Bonus 4sur5 » publié pour cette course : '
            'la règle de Bonus ne peut pas être évaluée sans inventer un rapport.',
      );
    }
    if (horsTop5.isNotEmpty) {
      for (final b in bonus4) {
        final comb = b.numeros;
        if (comb == null || comb.length != 4) continue;
        if (!comb.every(joues.contains)) continue;

        // ── CONFORMITÉ RÉGLEMENTAIRE (art. 1 c) : on ne tranche pas ─────────
        if (!_bonus4ConformeReglement(comb, top5)) {
          return VerdictGain.nonDetermine(
            motif: MotifNonDetermination.ambiguiteReglementaireBonus,
            explication: 'La combinaison « ${b.combinaison} » publiée comme '
                '« e-Bonus 4sur5 » serait payable par la règle mesurée sur les '
                'captures, mais elle ne satisfait PAS l\'art. 1 c) du règlement '
                'e-QUINTÉ+ : celui-ci exige quatre chevaux classés aux QUATRE '
                'premières places ET un cheval de rang SUPÉRIEUR AU CINQUIÈME, '
                'or cette combinaison n\'est pas exactement le top4 officiel '
                '(${top5.take(4).join("-")}). Aucune attribution, aucune '
                'déclaration de perte, aucun repli sur une autre catégorie.',
          );
        }

        return _verdictDepuisRapportPublie(
          publie: b,
          mise: mise,
          role: RoleComposante.unique,
          etatTirelire: EtatTirelire.sansObjet,
          explicationArbitrage: explicationArbitrage,
          complement: 'Garde-fou |T ∖ top5| = ${horsTop5.length} ≥ 1 et '
              'combinaison conforme à l\'art. 1 c) : le ticket contient bien '
              'un cheval hors du top5.',
        );
      }
    }

    // ④ BONUS 3 — comb3 publiée ⊆ T **ET** |T ∖ top4| ≥ 2
    final horsTop4 = joues.difference(top4s);
    final bonus3 = rapports
        .where((r) => r.codePmu == code && r.variante == VarianteRapport.bonus3)
        .toList();
    if (bonus3.isEmpty) {
      return VerdictGain.nonDetermine(
        motif: MotifNonDetermination.blocJusteAbsent,
        explication: 'Aucun rapport « e-Bonus 3 » publié pour cette course : la '
            'règle de Bonus ne peut pas être évaluée sans inventer un rapport.',
      );
    }
    if (horsTop4.length >= 2) {
      for (final b in bonus3) {
        final comb = b.numeros;
        if (comb == null || comb.length != 3) continue;
        if (!comb.every(joues.contains)) continue;

        // ── CONFORMITÉ RÉGLEMENTAIRE (art. 1 d) : on ne tranche pas ─────────
        if (!_bonus3ConformeReglement(comb, top5)) {
          return VerdictGain.nonDetermine(
            motif: MotifNonDetermination.ambiguiteReglementaireBonus,
            explication: 'La combinaison « ${b.combinaison} » publiée comme '
                '« e-Bonus 3 » serait payable par la règle mesurée, mais elle '
                'n\'est pas exactement le top3 officiel '
                '(${top5.take(3).join("-")}), alors que l\'art. 1 d) du '
                'règlement e-QUINTÉ+ l\'exige (trois chevaux du top3 + deux '
                'chevaux de rang > 4). Aucune attribution, aucune perte '
                'déclarée, aucun repli sur une autre catégorie.',
          );
        }

        return _verdictDepuisRapportPublie(
          publie: b,
          mise: mise,
          role: RoleComposante.unique,
          etatTirelire: EtatTirelire.sansObjet,
          explicationArbitrage: explicationArbitrage,
          complement: 'Garde-fou |T ∖ top4| = ${horsTop4.length} ≥ 2 et '
              'combinaison conforme à l\'art. 1 d) : le ticket contient bien '
              'deux chevaux hors du top4.',
        );
      }
    }
    return VerdictGain.perdu(
      explication: 'Aucune combinaison Bonus publiée n\'est incluse dans le '
          'ticket, ou les garde-fous de cardinalité ne sont pas satisfaits. '
          'La perte est ÉTABLIE, pas supposée.',
    );
  }

  // ── Quarté+ : BONUS (comb3 publiée ⊆ T) ───────────────────────────────────
  if (type == TypePariJoue.quarte && premiersOfficiels.length >= 4) {
    final top3s = premiersOfficiels.take(3).toSet();
    final bonus = rapports
        .where((r) =>
            r.codePmu == code && r.variante == VarianteRapport.bonusQuarte)
        .toList();
    if (bonus.isEmpty) {
      return VerdictGain.nonDetermine(
        motif: MotifNonDetermination.blocJusteAbsent,
        explication: 'Aucun rapport « e-Bonus » publié pour ce Quarté+ : la '
            'règle de Bonus ne peut pas être évaluée sans inventer un rapport.',
      );
    }
    final horsTop3 = joues.difference(top3s);
    if (horsTop3.isNotEmpty) {
      for (final b in bonus) {
        final comb = b.numeros;
        if (comb == null || comb.length != 3) continue;
        if (!comb.every(joues.contains)) continue;

        // ── CONFORMITÉ RÉGLEMENTAIRE (Quarté+ art. 1) ──────────────────────
        // Le Bonus Quarté+ exige « trois chevaux classés aux trois premières
        // places + un cheval classé au-delà du quatrième ». Mesuré : sur les
        // 5 courses Quarté+, la combinaison publiée est EXACTEMENT le top3
        // (5/5). On refuse donc de trancher si elle ne l'est pas.
        final top3Officiel = premiersOfficiels.take(3).toSet();
        if (!(comb.toSet().length == 3 &&
            comb.toSet().difference(top3Officiel).isEmpty)) {
          return VerdictGain.nonDetermine(
            motif: MotifNonDetermination.ambiguiteReglementaireBonus,
            explication: 'La combinaison « ${b.combinaison} » publiée comme '
                '« e-Bonus » Quarté+ serait payable par la règle mesurée, mais '
                'elle n\'est pas exactement le top3 officiel '
                '(${premiersOfficiels.take(3).join("-")}). Divergence non '
                'tranchée : aucune attribution, aucune perte déclarée.',
          );
        }

        return _verdictDepuisRapportPublie(
          publie: b,
          mise: mise,
          role: RoleComposante.unique,
          etatTirelire: EtatTirelire.sansObjet,
          explicationArbitrage: explicationArbitrage,
          complement: 'Garde-fou |T ∖ top3| = ${horsTop3.length} ≥ 1 et '
              'combinaison conforme au top3 officiel.',
        );
      }
    }
    return VerdictGain.perdu(
      explication: 'Aucune combinaison « e-Bonus » publiée n\'est incluse dans '
          'le ticket. La perte est ÉTABLIE, pas supposée.',
    );
  }

  return VerdictGain.nonDetermine(
    motif: MotifNonDetermination.rapportAmbigu,
    explication: 'La règle de Bonus n\'est pas applicable à cet état : arrivée '
        'officielle trop courte. Aucun montant n\'est attribué.',
  );
}

// ───────────────────────────────────────────────────────────────────────────
//  ★ CORRECTION « Anomalie 1 » — PREUVE DE COMPLÉTUDE PAR RECOUPEMENT
//
//  Ces trois fonctions ne manipulent AUCUN montant : elles ne lisent que des
//  combinaisons et des rangs. Elles ne peuvent donc pas fabriquer un gain.
// ───────────────────────────────────────────────────────────────────────────

/// Lignes du bloc du type, pour cette course.
List<RapportPublie> _lignesBloc({
  required TypePariJoue type,
  required EtatCourseOfficiel etat,
}) {
  final code = codeApiPourType(type);
  if (code == null) return const <RapportPublie>[];
  return etat.rapports.where((r) => r.codePmu == code).toList();
}

int _nbLignesBloc({
  required TypePariJoue type,
  required EtatCourseOfficiel etat,
}) =>
    _lignesBloc(type: type, etat: etat).length;

/// Cheveux de l'arrivée officielle, groupes APLATIS dans l'ordre, ex æquo
/// préservés dans leur ordre de publication.
///
/// Aucun groupe n'est inventé : un groupe vide rend la liste inexploitable.
List<int>? _arriveeAplatie(EtatCourseOfficiel etat) {
  final g = etat.arriveeGroupes;
  if (g == null || g.isEmpty) return null;
  final out = <int>[];
  for (final groupe in g) {
    if (groupe.isEmpty) return null;
    out.addAll(groupe);
  }
  return out;
}

/// `true` si la perte du ticket est DÉMONTRÉE par recoupement.
///
/// Preuve exigée, dans cet ordre :
///   1. arrivée officielle définitive et exploitable, groupes connus ;
///   2. le type fait partie du périmètre mesuré (aucun Bonus, aucune variante
///      concurrente à arbitrer) ;
///   3. le bloc du type EXISTE et n'est pas vide ;
///   4. ses rangs sont CONTIGUS de 1 à N (aucune ligne manquante) ;
///   5. ses combinaisons recoupent EXACTEMENT les N premiers chevaux de
///      l'arrivée — c'est la preuve que le bloc est complet ;
///   6. la combinaison jouée n'y figure pas.
///
/// Si l'une des conditions 1 à 5 échoue, on rend `false` : la perte n'est PAS
/// établie et le verdict restera `nonDetermine`. Jamais de perte supposée.
bool _blocEstDemontreComplet({
  required TypePariJoue type,
  required List<int> numerosJoues,
  required EtatCourseOfficiel etat,
}) {
  // 1. Périmètre : uniquement les types mesurés sans ambiguïté.
  if (!_dansPerimetrePerteDemontree(type)) return false;

  // Arrivée définitive impérativement requise. `null` = API muette ⇒ refus.
  if (etat.arriveeDefinitive != true) return false;

  final arrivee = _arriveeAplatie(etat);
  if (arrivee == null) return false;

  // 3. Le bloc doit exister.
  final lignes = _lignesBloc(type: type, etat: etat);
  if (lignes.isEmpty) return false;

  // 3 bis. ★ PREMIER UNIQUE, SANS EX ÆQUO À LA PREMIÈRE PLACE.
  //
  //   L'arbitrage l'exige explicitement pour fonder une perte Simple Gagnant
  //   sur une seule ligne. Avec un ex æquo à la 1re place, « l'ensemble des
  //   chevaux classés premiers » est concerné : un bloc d'UNE ligne ne peut
  //   alors pas être déclaré complet, puisqu'il devrait en publier autant que
  //   de premiers ex æquo. On refuse donc l'exemption dans ce cas, sans jamais
  //   prononcer de perte.
  final premierGroupe = etat.arriveeGroupes!.first;
  final premierUnique = premierGroupe.length == 1;
  if (type == TypePariJoue.simpleGagnant && !premierUnique) return false;

  // 4. Rangs contigus 1..R.
  //
  // ⚠️ Plusieurs lignes peuvent partager un même rang (mesuré : un Couplé
  //    Placé publie C(k,2) paires réparties sur 3 rangs, un 2sur4 sur 1 ou 2
  //    rangs). On n'exige donc PAS `rangs.length == n`, mais que les rangs
  //    distincts forment une suite CONTIGUË à partir de 1 : un rang manquant
  //    trahit un bloc tronqué.
  final rangs = <int>{};
  for (final l in lignes) {
    final r = l.rang;
    // ★ EXEMPTION MESURÉE — SIMPLE GAGNANT À UNE SEULE LIGNE.
    //
    //   MESURE QUI A MOTIVÉ CETTE EXEMPTION : le bloc Simple Gagnant d'une
    //   arrivée normale ne publie QU'UNE ligne pour UN cheval, et le
    //   recoupement exact de cette ligne avec le 1er cheval de l'arrivée
    //   définitive EST la preuve de complétude — il ne peut pas exister de
    //   seconde ligne. Exiger en plus un `rang` explicite faisait échouer la
    //   démonstration sur des blocs corrects (mesuré : `B3/6.5`, où le cheval
    //   4 est 2e et où seul le bloc Placé porte des rapports). L'arbitrage
    //   énumère les conditions exigées — arrivée définitive, premier unique,
    //   rapport définitif du 1er cheval, absence de remboursement — et le rang
    //   n'en fait pas partie pour ce cas.
    //
    //   L'EXEMPTION EST STRICTEMENT BORNÉE : un seul type, une seule ligne.
    //   Dès qu'il y a plusieurs lignes (Simple Placé, Couplé…), le rang reste
    //   exigé, car c'est lui qui distingue un bloc complet d'un bloc tronqué.
    if (r == null) {
      if (type == TypePariJoue.simpleGagnant && lignes.length == 1) continue;
      return false;
    }
    if (r < 1) return false;
    rangs.add(r);
  }
  final n = lignes.length;
  if (rangs.isNotEmpty) {
    final rMax = rangs.reduce((a, b) => a > b ? a : b);
    if (rMax > n) return false;
    for (var i = 1; i <= rMax; i++) {
      if (!rangs.contains(i)) return false;
    }
  }

  // 5. Recoupement EXACT avec l'arrivée aplatie.
  //
  // ⚠️ PIÈGE CORRIGÉ ICI : le nombre de LIGNES d'un bloc n'est pas le nombre
  //    de CHEVAUX qu'il couvre. Un Couplé Gagnant a UNE ligne pour DEUX
  //    chevaux, un Couplé Placé a C(K,2) lignes pour K chevaux. Confondre les
  //    deux faisait échouer la preuve sur le Couplé Gagnant (mesuré).
  //
  //    On déduit donc K — le nombre de chevaux couverts — de l'ENSEMBLE des
  //    numéros publiés, puis on EXIGE que le bloc contienne exactement le
  //    nombre de lignes que la règle PMU impose pour K chevaux. Un bloc
  //    partiel (quelques paires d'un Couplé Placé, par exemple) est ainsi
  //    détecté et la perte n'est PAS prononcée.
  final publies = <int>{};
  for (final l in lignes) {
    final numeros = l.numeros;
    if (numeros == null || numeros.isEmpty) return false;
    publies.addAll(numeros);
  }
  final k = publies.length;
  if (k == 0 || k > arrivee.length) return false;

  final attendu = <int>{};
  for (var i = 0; i < k; i++) {
    attendu.add(arrivee[i]);
  }
  if (publies.length != attendu.length) return false;
  if (!publies.containsAll(attendu)) return false;

  // Nombre de lignes imposé par la règle PMU pour K chevaux couverts.
  final lignesAttendues = _lignesAttenduesPour(type, k);
  if (lignesAttendues == null || lignesAttendues != n) return false;

  // 6. La combinaison jouée ne figure dans aucun rapport du bloc.
  //    (Les types du périmètre n'ont qu'une variante : l'égalité d'ENSEMBLE
  //    suffit, et elle est plus stricte que l'égalité de chaîne.)
  final joues = numerosJoues.toSet();
  for (final l in lignes) {
    final numeros = l.numeros;
    if (numeros == null) continue;
    if (numeros.length == joues.length && numeros.toSet().containsAll(joues)) {
      return false; // présent ⇒ ce n'est pas une perte
    }
  }
  return true;
}

/// Nombre de lignes qu'un bloc COMPLET doit publier pour [k] chevaux couverts.
///
/// Mesuré sur 308 captures : Simple Gagnant = 1 ligne quel que soit k (k=1) ;
/// Simple Placé = k lignes (une par cheval payable) ; Couplé Gagnant = 1 ligne
/// pour k=2 ; Couplé Placé = C(k,2) paires. `null` = type hors périmètre.
int? _lignesAttenduesPour(TypePariJoue type, int k) {
  switch (type) {
    case TypePariJoue.simpleGagnant:
      return k == 1 ? 1 : null;
    case TypePariJoue.simplePlace:
      return k;
    case TypePariJoue.coupleGagnant:
    case TypePariJoue.coupleOrdre:
      return k == 2 ? 1 : null;
    case TypePariJoue.couplePlace:
      // C(k,2) : toutes les paires des k chevaux payables.
      return k < 2 ? null : (k * (k - 1)) ~/ 2;
    default:
      return null;
  }
}

/// Types dont la perte peut être démontrée par recoupement.
///
/// EXCLUS volontairement :
///   • `tierce`/`quarte`/`quinte` : arbitrés sur l'arrivée, avec Bonus ;
///   • `tierceOrdre`/`tierceDesordre`/`coupleOrdre` : variante déclarée,
///     traités par l'arbitre qui prononce déjà la perte ;
///   • `gagnantPlace` : deux composantes, traité séparément ;
///   • `inconnu` : aucun calcul.
bool _dansPerimetrePerteDemontree(TypePariJoue type) {
  switch (type) {
    case TypePariJoue.simpleGagnant:
    case TypePariJoue.simplePlace:
    case TypePariJoue.coupleGagnant:
    case TypePariJoue.couplePlace:
      return true;
    default:
      return false;
  }
}

/// Rapport Ordre publié d'un bloc, ou `null`. Aucun choix par montant.
RapportPublie? _rapportOrdrePublie(List<RapportPublie> rapports, String code) {  for (final r in rapports) {
    if (r.codePmu == code && r.variante == VarianteRapport.ordre) return r;
  }
  return null;
}

// ───────────────────────────────────────────────────────────────────────────
//  Gagnant+Placé — deux composantes, deux mises
// ───────────────────────────────────────────────────────────────────────────

VerdictGain _resoudreGagnantPlace({
  required List<int> numerosJoues,
  required MiseEngagee mise,
  required EtatCourseOfficiel etat,
}) {
  final miseG = mise.miseGagnant ?? 0.0;
  final miseP = mise.misePlace ?? 0.0;
  if (!(miseG > 0) && !(miseP > 0)) {
    return VerdictGain.nonDetermine(
      motif: MotifNonDetermination.montantAbsent,
      explication: 'Gagnant+Placé sans mise positive sur aucune de ses deux '
          'composantes : aucun gain ne peut être fondé.',
    );
  }

  // `identifierGagnantPlace` est l'autorité du dédoublement : appelée telle
  // quelle, elle identifie chaque composante comme un Simple Gagnant / Placé.
  final IdentificationGagnantPlace id = identifierGagnantPlace(
    numerosJoues: numerosJoues,
    rapports: etat.rapports.map(versRapportOfficiel).toList(),
  );

  final composantes = <ComposanteGain>[];

  if (miseG > 0) {
    final c = _composanteGagnantPlace(
      officiel: id.gagnant.rapport,
      rapports: etat.rapports,
      mise: miseG,
      role: RoleComposante.gagnant,
    );
    if (c != null) composantes.add(c);
  }
  if (miseP > 0) {
    final c = _composanteGagnantPlace(
      officiel: id.place.rapport,
      rapports: etat.rapports,
      mise: miseP,
      role: RoleComposante.place,
    );
    if (c != null) composantes.add(c);
  }

  if (composantes.isEmpty) {
    // Aucune composante identifiée : distinguer « perdu » de « indéterminable »
    // exige de savoir ce qui manque. Si un rapport existe mais sans montant,
    // c'est une non-détermination ; s'il n'existe aucun rapport candidat,
    // la perte est établie par les rapports eux-mêmes.
    final gagnantIdentifie = miseG > 0 && id.gagnant.rapport == null;
    final placeIdentifiee = miseP > 0 && id.place.rapport == null;
    if (gagnantIdentifie && placeIdentifiee) {
      return VerdictGain.nonDetermine(
        motif: MotifNonDetermination.blocJusteAbsent,
        explication: 'Aucun rapport Simple Gagnant ni Simple Placé n\'a pu être '
            'identifié pour ce cheval. Aucun montant n\'est attribué.',
      );
    }
    return VerdictGain.perdu(
      explication: 'Aucune des deux composantes (Gagnant, Placé) n\'est '
          'gagnante pour ce cheval.',
    );
  }

  // ── ★ CONTRÔLE D'ÉTABLISSEMENT — UNE COMPOSANTE ABSENTE N'EST PAS PERDANTE.
  //
  //   MESURE QUI A MOTIVÉ CE BLOC : `[O]` — Gagnant gagnant (7,50) et AUCUN
  //   rapport Simple Placé publié — rendait `attribue` avec `total = 75,0`,
  //   c'est-à-dire un résultat présenté comme COMPLET alors que le sort de la
  //   composante Placé (10 € d'une mise totale de 20 €) n'était pas établi.
  //   L'arbitrage est explicite : « Une composante absente n'est pas
  //   automatiquement perdante ».
  //
  //   RÈGLE APPLIQUÉE — pour chaque composante ENGAGÉE (mise > 0), son sort
  //   doit être CONNU, c'est-à-dire :
  //     • avoir produit une composante (gain, ou remboursement) ; ou
  //     • être PERDANTE de façon démontrée : aucun rapport ne correspond au
  //       cheval joué ET le bloc de ce type est DÉMONTRÉ COMPLET — c'est la
  //       même preuve par recoupement que celle utilisée pour la perte du
  //       chemin mono-composante, jamais une simple absence.
  //   Si le sort d'une composante engagée n'est ni gagné, ni remboursé, ni
  //   perdu démontré, le ticket n'est PAS complet : `nonDetermine`.
  //   On ne fabrique ni une perte (interdit) ni un total partiel présenté
  //   comme définitif (mesuré ci-dessus).
  final sortGagnantConnu = _sortComposanteConnu(
    mise: miseG,
    composantes: composantes,
    role: RoleComposante.gagnant,
    idRapport: id.gagnant.rapport,
    type: TypePariJoue.simpleGagnant,
    numerosJoues: numerosJoues,
    etat: etat,
  );
  final sortPlaceConnu = _sortComposanteConnu(
    mise: miseP,
    composantes: composantes,
    role: RoleComposante.place,
    idRapport: id.place.rapport,
    type: TypePariJoue.simplePlace,
    numerosJoues: numerosJoues,
    etat: etat,
  );
  if (!sortGagnantConnu || !sortPlaceConnu) {
    return VerdictGain.nonDetermine(
      motif: MotifNonDetermination.blocJusteAbsent,
      explication: 'Le sort d\'une composante engagée de ce Gagnant+Placé '
          'n\'est pas établi : ni gagnée, ni remboursée, ni démontrée '
          'perdante${!sortGagnantConnu ? " (composante Gagnant)" : ""}'
          '${!sortPlaceConnu ? " (composante Placé)" : ""}. Aucun total '
          'partiel n\'est présenté comme définitif, et aucune perte n\'est '
          'inventée.',
    );
  }

  // Toutes les composantes engagées sont remboursées (aucun gain) : le ticket
  // est intégralement remboursé, et le montant rendu est la somme des mises.
  //
  // ⚠️ MESURE QUI A MOTIVÉ CE TEST SUR `totalRembourse` ET NON SUR LE SEUL
  //    `totalGain == 0` : un Gagnant+Placé dont les DEUX composantes sont
  //    PERDUES a aussi un gain total nul. Conclure au remboursement dans ce
  //    cas afficherait « remboursé » sur une perte certaine — l'inverse exact
  //    de la règle. Le remboursement n'est donc prononcé que si une mise est
  //    RÉELLEMENT rendue.
  final totalGain = composantes.fold<double>(0.0, (s, c) => s + c.montantRetour);
  final totalRembourse =
      composantes.fold<double>(0.0, (s, c) => s + c.miseRemboursee);
  if (totalGain == 0.0) {
    if (totalRembourse > 0) {
      return VerdictGain.rembourse(
        remboursement: totalRembourse,
        explication: 'Les composantes engagées de ce Gagnant+Placé sont '
            'remboursées par l\'opérateur : '
            '${totalRembourse.toStringAsFixed(2)} € sont rendus, aucun gain '
            'n\'est établi.',
      );
    }
    // Aucun gain, aucun remboursement, et le sort de chaque composante
    // engagée est établi : la perte est DÉMONTRÉE, pas supposée.
    return VerdictGain.perdu(
      explication: 'Le sort de chaque composante engagée de ce Gagnant+Placé '
          'est établi et aucune n\'est gagnante ni remboursée : la perte est '
          'démontrée par les rapports officiels.',
    );
  }

  return VerdictGain.attribue(
    composantes: composantes,
    explication: totalRembourse > 0
        ? 'Gain officiel établi sur les composantes gagnantes ; '
            '${totalRembourse.toStringAsFixed(2)} € de mise remboursée, '
            'conservés distincts du gain.'
        : '',
  );
}

/// Le sort d'une composante ENGAGÉE est-il établi ?
///
/// Trois cas seulement sont probants :
///   ① la composante a produit une entrée (gain ou remboursement) ;
///   ② la composante est PERDANTE de façon démontrée : aucun rapport ne
///      correspond au cheval joué pour ce type, ET le bloc officiel de ce type
///      est démontré complet par recoupement avec l'arrivée définitive
///      (même preuve que `_blocEstDemontreComplet`, réutilisée telle quelle) ;
///   ③ aucune mise n'est engagée sur cette composante : son sort est sans
///      objet, il n'y a rien à établir.
///
/// ⚠️ `idRapport == null` seul n'est JAMAIS une preuve de perte : c'est
///    exactement l'erreur que l'arbitrage interdit (« Ne jamais transformer
///    une simple absence de rapport en perte certaine »). On exige donc, en
///    plus, la démonstration de complétude du bloc.
bool _sortComposanteConnu({
  required double mise,
  required List<ComposanteGain> composantes,
  required RoleComposante role,
  required RapportOfficiel? idRapport,
  required TypePariJoue type,
  required List<int> numerosJoues,
  required EtatCourseOfficiel etat,
}) {
  if (!(mise > 0)) return true; // composante non engagée : rien à établir.
  for (final c in composantes) {
    if (c.role == role) return true; // ① gain ou remboursement établi.
  }
  // ② Aucun rapport identifié pour ce cheval. La perte n'est retenue que si
  //    elle est DÉMONTRÉE par recoupement du bloc officiel avec l'arrivée
  //    définitive — jamais par la seule absence de rapport.
  if (idRapport == null) {
    return _blocEstDemontreComplet(
      type: type,
      numerosJoues: numerosJoues,
      etat: etat,
    );
  }
  // ③ Un rapport EXISTE pour ce cheval, mais aucune composante n'en est née :
  //    son montant n'est pas exploitable. Le sort n'est donc PAS établi — ni
  //    gain, ni remboursement, ni perte prouvée.
  return false;
}

/// Une composante Gagnant ou Placé du ticket Gagnant+Placé.
///
/// ★ CORRECTION À LA SOURCE — LE REMBOURSEMENT EST ENFIN HONORÉ ICI.
///
/// MESURE QUI A MOTIVÉ CETTE CORRECTION : rapports `[gagnant 7,50 ;
/// placé 2,10 marqué `rembourse`]`, mises 10/10 rendaient `attribue` avec
/// `total = 96,0` et DEUX composantes, dont `« e-Simple Placé » 10 × 2,10 =
/// 21,0`. Le coefficient du rapport était donc appliqué à une composante que
/// l'opérateur rembourse : 21 € de GAIN inventés. Or un remboursement
/// intégral d'une mise de 10 € rend 10 €, il ne « gagne » pas 21 €.
///
/// RÈGLE APPLIQUÉE (règlement PMU, remboursements et non-partants) :
///   • composante remboursée ⇒ `montantRetour = 0,0` (aucun gain),
///     `miseRemboursee = mise` (la mise est rendue), `rembourse = true` ;
///   • le coefficient `pourUnEuro` n'est JAMAIS appliqué à une composante
///     remboursée — il est conservé pour l'audit, pas pour le calcul.
///
/// Le gain et le remboursement restent ainsi DISTINCTS jusque dans
/// `VerdictGain` (`.total` vs `.remboursement`), donc jusqu'à l'affichage.
ComposanteGain? _composanteGagnantPlace({
  required RapportOfficiel? officiel,
  required List<RapportPublie> rapports,
  required double mise,
  required RoleComposante role,
}) {
  if (officiel == null) return null;
  final publie = _retrouverPublie(rapports, officiel);
  if (publie == null) return null;

  // ① Le rapport existe et l'opérateur le rembourse : la composante est
  //    ÉTABLIE (son sort est connu) et elle rend sa mise, sans aucun gain.
  //    On ne teste pas `aUnMontantExploitable` : un remboursement ne dépend
  //    d'aucun dividende, et exiger un montant ferait perdre le
  //    remboursement au profit d'une non-détermination — donc d'une perte
  //    potentiellement affichée à tort.
  if (publie.rembourse) {
    return ComposanteGain(
      libelleRapport: publie.libelle,
      combinaisonRapport: publie.combinaison,
      categorie: publie.variante,
      role: role,
      mise: mise,
      pourUnEuro: publie.pourUnEuro ?? 0.0,
      montantRetour: 0.0,
      rembourse: true,
    );
  }

  // ② Composante non remboursée : il faut un montant exploitable pour fonder
  //    un gain. Sans montant, son sort n'est PAS établi — on ne fabrique rien.
  if (!publie.aUnMontantExploitable) return null;
  return ComposanteGain(
    libelleRapport: publie.libelle,
    combinaisonRapport: publie.combinaison,
    categorie: publie.variante,
    role: role,
    mise: mise,
    pourUnEuro: publie.pourUnEuro!,
    montantRetour: mise * publie.pourUnEuro!,
  );
}

// ───────────────────────────────────────────────────────────────────────────
//  Fabriques de verdict, partagées
// ───────────────────────────────────────────────────────────────────────────

VerdictGain _verdictDepuisRapportPublie({
  required RapportPublie publie,
  required double mise,
  required RoleComposante role,
  required EtatTirelire etatTirelire,
  required String explicationArbitrage,
  String? complement,
}) {
  if (publie.rembourse) {
    // ★ Un remboursement rend la MISE ENGAGÉE : `remboursement` porte ce
    //   montant pour que l'interface puisse l'afficher, tandis que `total`
    //   reste `0.0` — un remboursement n'est pas un gain.
    return VerdictGain.rembourse(
      explication: 'Le rapport « ${publie.libelle} » est explicitement marqué '
          'remboursé par l\'opérateur.',
      etatTirelire: etatTirelire,
      remboursement: mise,
    );
  }
  if (!publie.aUnMontantExploitable) {
    return VerdictGain.nonDetermine(
      motif: MotifNonDetermination.montantAbsent,
      etatTirelire: etatTirelire,
      explication: 'Le rapport « ${publie.libelle} » ne porte aucun montant '
          'exploitable (`pourUnEuro`). Aucune valeur plausible n\'est substituée.',
    );
  }
  return VerdictGain.attribue(
    composantes: <ComposanteGain>[
      ComposanteGain(
        libelleRapport: publie.libelle,
        combinaisonRapport: publie.combinaison,
        categorie: publie.variante,
        role: role,
        mise: mise,
        pourUnEuro: publie.pourUnEuro!,
        montantRetour: mise * publie.pourUnEuro!,
      ),
    ],
    etatTirelire: etatTirelire,
  );
}

VerdictGain _depuisRefusResolveur(
  ResolutionRapportPmu resolution,
  EtatTirelire etatTirelire,
  List<RapportPublie> rapportsCompatibles,
  List<int> numerosJoues,
  double mise,
) {
  final motif = resolution.motifRefus!;

  // ── Raffinement du motif quand le résolveur est structurellement aveugle ───
  //
  // `_classerRefus` ne rend QUE `ambiguiteTirelire`, `ambiguitePlusieursRapports`
  // ou `aucunRapportExact` : il ne distingue pas « rapport absent » de
  // « rapport présent mais sans montant ». Or cette distinction change l'état
  // affiché. On la rétablit ici en relisant les rapports DÉJÀ restreints par
  // l'arbitre — sans jamais inventer : si le rapport exact est présent avec un
  // montant exploitable, le motif d'origine est conservé tel quel.
  MotifNonDetermination cible;
  switch (motif) {
    case MotifRefusPmu.typeNonRepertorie:
    case MotifRefusPmu.ticketDeuxComposantes:
    case MotifRefusPmu.typeHorsMoteurA:
    case MotifRefusPmu.typeSansCodeUniqueMoteurA:
    case MotifRefusPmu.divergenceCodesApi:
      cible = MotifNonDetermination.typeNonRepertorie;
      break;
    case MotifRefusPmu.aucunNumeroJoue:
    case MotifRefusPmu.tailleCombinaisonIncoherente:
      cible = MotifNonDetermination.tailleCombinaisonAnormale;
      break;
    case MotifRefusPmu.ambiguitePlusieursRapports:
      cible = MotifNonDetermination.rapportAmbigu;
      break;
    case MotifRefusPmu.ambiguiteTirelire:
      cible = MotifNonDetermination.tirelireNonDeterminee;
      break;
    case MotifRefusPmu.dividendePourUnEuroAbsent:
      cible = MotifNonDetermination.montantAbsent;
      break;
    case MotifRefusPmu.rapportRembourse:
      // Le résolveur refuse de payer ET de rembourser : il délègue le
      // remboursement. Le rapport exact est publié et marqué remboursé, donc
      // l'état correct est `rembourse`, pas `montantAbsent`.
      final rembourse = _rapportExact(rapportsCompatibles, numerosJoues);
      if (rembourse != null && rembourse.rembourse) {
        return VerdictGain.rembourse(
          etatTirelire: etatTirelire,
          remboursement: mise,
          explication: 'Le rapport « ${rembourse.libelle} » est marqué '
              'remboursé par l\'opérateur (le résolveur délègue explicitement '
              'le remboursement, il ne le refuse pas). État « remboursé », '
              'aucun gain calculé.',
        );
      }
      cible = MotifNonDetermination.montantAbsent;
      break;
    case MotifRefusPmu.aucunRapportExact:
      // Le résolveur ne distingue pas « aucun rapport » de « rapport sans
      // montant » : il rend `aucunRapportExact` dans les deux cas.
      final exact = _rapportExact(rapportsCompatibles, numerosJoues);
      if (exact != null && !exact.aUnMontantExploitable) {
        cible = MotifNonDetermination.montantAbsent;
      } else {
        cible = MotifNonDetermination.blocJusteAbsent;
      }
      break;
  }
  return VerdictGain.nonDetermine(
    motif: cible,
    etatTirelire: etatTirelire,
    explication: 'Refus du résolveur (${motif.name}) : ${resolution.explication}',
  );
}

/// Rapport publié portant EXACTEMENT la combinaison jouée, ou `null`.
///
/// Sert uniquement à RAFFINER un motif de refus déjà prononcé : jamais à
/// attribuer un gain. Aucun choix par montant — l'égalité de combinaison et
/// l'unicité sont exigées.
RapportPublie? _rapportExact(
  List<RapportPublie> rapports,
  List<int> numerosJoues,
) {
  final candidats = <RapportPublie>[];
  for (final r in rapports) {
    final nums = r.numeros;
    if (nums == null) continue;
    if (nums.length != numerosJoues.length) continue;
    if (!_memeOrdre(nums, numerosJoues) &&
        !_memeEnsemble(nums, numerosJoues)) {
      continue;
    }
    candidats.add(r);
  }
  return candidats.length == 1 ? candidats.single : null;
}

bool _memeEnsemble(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  final sa = a.toSet();
  final sb = b.toSet();
  return sa.length == sb.length && sa.containsAll(sb);
}

/// Retrouve le `RapportPublie` correspondant à un `RapportOfficiel` retenu.
///
/// Correspondance sur (code, libellé, combinaison) — JAMAIS sur le montant.
RapportPublie? _retrouverPublie(
  List<RapportPublie> rapports,
  RapportOfficiel officiel,
) {
  for (final r in rapports) {
    if (r.codePmu == officiel.typePari &&
        r.libelle == officiel.libelle &&
        r.combinaison == officiel.combinaison) {
      return r;
    }
  }
  return null;
}

bool _memeOrdre(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
