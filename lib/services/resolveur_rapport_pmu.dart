// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 4-A — RÉSOLVEUR PUR DU RAPPORT OFFICIEL EXACT
//
//  Ce fichier répond à UNE question et n'en pose aucune autre :
//
//      « Pour ce ticket précis (type de pari stocké + combinaison jouée),
//        quel rapport officiel PMU lui correspond EXACTEMENT — ou, à défaut,
//        pour quelle raison DÉMONTRÉE aucun rapport ne peut être retenu ? »
//
//  CE FICHIER N'EST PAS UN CALCULATEUR. Il ne calcule aucun gain, ne connaît
//  aucune mise, n'écrit rien, n'appelle aucun service, et n'est importé par
//  aucun écran (vérifiable : un test l'exige).
//
//  ───────────────────────────────────────────────────────────────────────────
//  RÉUTILISATION — AUCUN TROISIÈME CALCULATEUR
//  ───────────────────────────────────────────────────────────────────────────
//
//  Deux modules existent déjà et sont utilisés TELS QUELS, sans modification :
//
//   • `referentiel_paris_pmu.dart` (étape 1) — référentiel CENTRAL.
//       - `typePmuDepuisLibelleHistorique` : libellé stocké → type canonique ;
//       - `estTicketApplicatifHorsReferentielPmu` : cas « Gagnant+Placé » ;
//       - `codeApiPourTypePmu` : code API de référence ;
//       - `tailleCombinaisonGagnante` : taille de combinaison exigée.
//
//   • `gain_ticket_calculator.dart` (sous-lot A, validé) — moteur de décision.
//       - `RapportOfficiel`, `VarianteRapport` ;
//       - `typePariDepuisLibelle`, `codeApiPourType` ;
//       - `variantesIdentifiablesParCombinaison`, `exigeOrdreExact`,
//         `tailleCombinaisonAttendue` ;
//       - `identifierRapportExact` : **LA** décision de sélection ;
//       - `varianteDepuisLibelle` : variante déduite du seul `libelle`.
//
//  La DÉCISION de retenir ou non un rapport appartient intégralement à
//  `identifierRapportExact`. Ce fichier ne la refait jamais. Ce qu'il ajoute,
//  et qui n'existait nulle part :
//
//   1. l'entrée est le libellé **tel qu'il est stocké sur le ticket**, pas une
//      abstraction intermédiaire — parce que « Tiercé Ordre » et « Tiercé »
//      mènent au même type canonique mais pas au même rapport ;
//   2. un CONTRÔLE CROISÉ des deux tables de codes API : si le référentiel
//      central et le moteur A ne désignent pas le même code, on refuse ;
//   3. les PARTICULARITÉS des rapports (Bonus, Tirelire, non-partants,
//      combinaisons de taille anormale) sont écartées NOMMÉMENT, avec motif,
//      au lieu de disparaître en silence dans un filtre ;
//   4. le refus est un CODE fermé, pas seulement une phrase.
//
//  ───────────────────────────────────────────────────────────────────────────
//  POURQUOI `variantesPayables` DU RÉFÉRENTIEL N'EST PAS UTILISÉE ICI
//  ───────────────────────────────────────────────────────────────────────────
//
//  Choix explicite, pas un oubli. `variantesPayables(TypePariPmu.quartePlus)`
//  rend `{ordre, desordre, bonusQuarte}` et `(quintePlus)` rend
//  `{ordre, desordre, bonus4sur5, bonus3, tirelire}` : ce sont les variantes
//  réellement PUBLIÉES par l'API. Mais un Bonus n'est pas le rapport du ticket
//  — sa combinaison est plus courte (mesuré : 3 numéros pour « e-Bonus » du
//  Quarté+, contre 4 au pari). S'en servir pour SÉLECTIONNER ferait donc
//  entrer les Bonus dans la sélection.
//
//  Le résolveur s'appuie donc sur `variantesIdentifiablesParCombinaison` du
//  moteur A, qui exclut délibérément Bonus et non-partants. `variantesPayables`
//  reste ce qu'elle est : la liste de ce que l'API publie, pas de ce qui est
//  attribuable. La distinction entre les deux notions est le cœur du 4-A.
//
//  ───────────────────────────────────────────────────────────────────────────
//  INTERDITS RESPECTÉS (rendus impossibles, pas seulement évités)
//  ───────────────────────────────────────────────────────────────────────────
//
//   • Jamais `rapports.first` : aucun repli sur le premier rapport venu.
//   • Jamais `reduce(MAX)` : `EcartementRapport` ne transporte VOLONTAIREMENT
//     AUCUN montant. Sans montant exposé, un « maximum » est impossible à
//     écrire ici, même par accident.
//   • Jamais de valeur par défaut : un libellé vide, inconnu ou non couvert
//     rend un refus motivé, jamais « Simple Gagnant ».
//
//  ───────────────────────────────────────────────────────────────────────────
//  PORTÉE RÉELLE DES MOTIFS DE REFUS — MESURÉE PAR EXÉCUTION, PAS SUPPOSÉE
//  ───────────────────────────────────────────────────────────────────────────
//
//  Les 20 libellés de `kLibellesHistoriquesVersTypePmu` ont été passés un par
//  un dans les deux modules. Résultat mesuré (voir le test E4A/M5 qui le
//  rejoue) :
//
//   • 11 libellés donnent le MÊME code API dans les deux modules ⇒ résolubles :
//     simple gagnant, simple placé, couplé gagnant, couplé placé, couplé ordre,
//     couplé désordre, tiercé, tiercé ordre, tiercé désordre, quarté+, quinté+.
//
//   • 9 libellés sont reconnus par le référentiel mais PAS par le moteur A
//     (il rend `TypePariJoue.inconnu`) ⇒ motif `typeHorsMoteurA` :
//     « simple place », « couple gagnant », « couple place », « couple
//     desordre », « tierce », « quarté », « quarte+ », « quinte+ », « quinté ».
//     Ce sont des VARIANTES ORTHOGRAPHIQUES, effectivement présentes dans le
//     code (`gain_calculator.dart` écrit « Gagnant + Placé », `type_pari_utils`
//     recense plusieurs graphies). Elles ne sont pas des types de paris
//     différents : les refuser est conservateur et correct — on ne devine pas
//     qu'une graphie inconnue de A vaut un type qu'il connaît.
//
//   • Les types canoniques `trio`, `trioOrdre`, `superQuatre`, `multi`,
//     `miniMini` n'ont AUCUN libellé dans la table historique : ils ne sont
//     donc jamais atteints par cette entrée. Leur absence du moteur A reste
//     réelle, mais elle est traitée en amont, ici par `typeNonRepertorie`
//     pour tout libellé « Trio »/« Multi » non listé.
//
//  ───────────────────────────────────────────────────────────────────────────
//  PARTICULARITÉS — MESURÉ SUR LES RAPPORTS RÉELS
//  ───────────────────────────────────────────────────────────────────────────
//  Jeu de référence : 206 courses / 3 742 rapports, API v7
//  `rapports-definitifs`, 08 → 16 nov. 2026 (/tmp/scan_pmu).
//
//   • BONUS — combinaison plus COURTE que le pari, donc jamais identifiable
//     par égalité de combinaison. Mesuré : « e-Bonus » du Quarté+ → 3 numéros
//     (9/9 courses), « e-Bonus 3 » du Quinté+ → 3 (9/9), « e-Bonus 4sur5 » → 4
//     (45 rapports sur 9 courses). Écartés sous
//     `bonusCombinaisonPlusCourte`.
//
//   • TIRELIRE — mesuré sur 15112026_R1C6 :
//       « e-Quinté+ Ordre + Tirelire »  comb `9-4-15-10-1`  pe 11 462 670
//       « e-Quinté+ Ordre »             comb `9-4-15-10-1`  pe  6 462 670
//     Même combinaison. Le champ `rangCombinaisonPayable` vaut **1 pour les
//     deux** : ce n'est pas deux paiements alternatifs, c'est le même rapport
//     à deux stades de calcul. La garde de `identifierRapportExact` les met en
//     concurrence et refuse ; ce module ne tranche pas davantage.
//
//   • NON-PARTANTS — « … 1 NP ». Mesuré : 40 « e-Couplé Gagnant 1 NP »,
//     40 « e-Couplé Placé 1 NP » (rangs 4/5/6), 38 « e-Trio 1 NP »,
//     2 « e-Tiercé 1 NP ». Leur `numeros` est `null` : la combinaison contient
//     `NP`, ce n'est pas une suite de chevaux. Leurs rangs (2, 4, 5, 6)
//     montrent qu'ils s'AJOUTENT aux rapports principaux (rang 1).
//
//   • ANOMALIES DE TAILLE — mesuré, 5 rapports seulement sur 3 742 :
//       09112026_R2C5  E_TRIO       « e-Trio »       `6-5`  (2 au lieu de 3)
//       11112026_R2C3  E_TRIO       « e-Trio »       `7-9`  (2 au lieu de 3)
//       11112026_R3C4  E_TRIO       « e-Trio »       `4-6`  (2 au lieu de 3)
//       13112026_R2C2  E_TRIO       « e-Trio »       `5-8`  (2 au lieu de 3)
//       13112026_R4C1  E_TRIO_ORDRE « e-Trio Ordre » `3-7`  (2 au lieu de 3)
//     Écartés par le test de taille : une combinaison de 2 chevaux ne peut pas
//     être le rapport d'un pari à 3 chevaux.
//
//   • `rembourse` — clé de BLOC, pas de rapport, dans l'API : mesuré `false`
//     sur les 1 382 blocs. La garde existe, n'est jamais déclenchée.
//
//   • `dividendePourUnEuro` — présent sur 3 742/3 742 rapports. La garde
//     « dividende absent » existe, n'est jamais déclenchée sur ce jeu.
//
//  ───────────────────────────────────────────────────────────────────────────
//  LIMITES ASSUMÉES — CE QUE CE MODULE NE SAIT PAS FAIRE, ET DIT
//  ───────────────────────────────────────────────────────────────────────────
//
//   • TIERCÉ GÉNÉRIQUE — « Tiercé » n'impose aucune variante. Le PMU publie
//     « e-Tiercé Ordre » ET « e-Tiercé Désordre » avec la même combinaison
//     (mesuré 9/9 courses) : deux candidats ⇒ refus d'ambiguïté.
//     « Tiercé Ordre » et « Tiercé Désordre » sont résolubles, parce que le
//     libellé stocké porte la précision. C'est pourquoi l'entrée de ce module
//     est le LIBELLÉ et non le seul type canonique : le référentiel replie
//     légitimement les trois sur `TypePariPmu.tierce` — correct pour NOMMER le
//     pari, insuffisant pour CHOISIR le rapport.
//
//   • QUARTÉ+ ET QUINTÉ+ GÉNÉRIQUES — même situation : Ordre et Désordre
//     co-existent à combinaison égale (9/9 courses chacun) ⇒ refus. Trancher
//     exige l'arrivée officielle, donc §4-C.
//
//   • GAGNANT+PLACÉ — ticket applicatif à DEUX composantes, sans rapport PMU
//     unique. Refusé ici ; le dédoublement appartient à `identifierGagnantPlace`
//     du moteur A.
// ═══════════════════════════════════════════════════════════════════════════

import 'gain_ticket_calculator.dart';
import 'referentiel_paris_pmu.dart';

// ───────────────────────────────────────────────────────────────────────────
//  MOTIFS DE REFUS — LISTE FERMÉE
// ───────────────────────────────────────────────────────────────────────────

/// Raison **démontrée** pour laquelle aucun rapport n'a été retenu.
///
/// Liste fermée : aucun motif « autre », qui servirait de fourre-tout et
/// masquerait un cas non analysé. Tout nouveau cas doit être nommé ici.
enum MotifRefusPmu {
  /// Le libellé stocké n'est pas répertorié : donnée inconnue, vide, ou
  /// corrompue. Ce n'est PAS un type par défaut.
  typeNonRepertorie,

  /// Le libellé désigne un ticket applicatif à deux composantes
  /// (« Gagnant+Placé »), sans rapport PMU unique.
  ticketDeuxComposantes,

  /// Le référentiel central reconnaît ce pari, mais le moteur A ne le couvre
  /// pas. Mesuré : 9 des 20 libellés historiques (variantes orthographiques).
  /// Le résoudre exigerait un troisième moteur : refus assumé, pas contourné.
  typeHorsMoteurA,

  /// Le moteur A ne publie aucun code API unique pour ce type
  /// (`gagnantPlace` : deux composantes).
  typeSansCodeUniqueMoteurA,

  /// Les deux modules désignent des codes API différents : l'une des tables a
  /// dérivé. On refuse plutôt que de choisir laquelle croire.
  divergenceCodesApi,

  /// Aucun numéro joué n'est enregistré : rien à comparer.
  aucunNumeroJoue,

  /// Le nombre de numéros joués ne correspond pas à la taille de combinaison
  /// exigée par le pari.
  tailleCombinaisonIncoherente,

  /// Aucun rapport du bon code et de la bonne variante ne porte la
  /// combinaison jouée.
  aucunRapportExact,

  /// Plusieurs rapports correspondent exactement : le choix dépend de
  /// l'arrivée officielle, qui n'est pas une donnée de ce module.
  ambiguitePlusieursRapports,

  /// Conflit e-Tirelire : le rapport « … + Tirelire » et le rapport sans
  /// supplément portent la même combinaison, ou la Tirelire est publiée seule
  /// sans que son statut définitif soit démontré.
  ambiguiteTirelire,

  /// Le rapport exact existe mais son dividende pour 1 € est absent : aucun
  /// montant ne peut être établi.
  dividendePourUnEuroAbsent,

  /// Le rapport exact est marqué remboursé par l'API : l'attribution relève du
  /// remboursement, pas du calcul de gain. Jamais observé sur le jeu mesuré,
  /// garde conservée par prudence.
  rapportRembourse,
}

// ───────────────────────────────────────────────────────────────────────────
//  PARTICULARITÉS — POURQUOI UN RAPPORT CANDIDAT A ÉTÉ ÉCARTÉ
// ───────────────────────────────────────────────────────────────────────────

/// Raison d'écartement d'un rapport qui était CANDIDAT pour ce ticket.
///
/// Ces rapports sont nommés au lieu d'être filtrés en silence : un Bonus ou un
/// non-partant qui disparaît sans explication est exactement ce qui rend un
/// gain impossible à auditer.
enum MotifEcartementPmu {
  /// Bonus : combinaison plus courte que celle du pari.
  bonusCombinaisonPlusCourte,

  /// Non-partant : combinaison contenant `NP`, pas une suite de chevaux.
  nonPartantCombinaisonNonChevaux,

  /// e-Tirelire : même combinaison que le rapport principal.
  tirelireMemeCombinaison,

  /// Combinaison de taille inattendue pour ce code API (anomalie mesurée).
  tailleCombinaisonAnormale,

  /// Combinaison lisible mais différente de celle jouée.
  combinaisonDifferente,

  /// Variante de libellé non payable pour ce pari (ex. Désordre là où seul
  /// l'ordre est payable).
  varianteNonPayable,
}

/// Un rapport écarté, avec sa raison.
///
/// ⚠️ NE PORTE VOLONTAIREMENT AUCUN MONTANT. Exposer les dividendes des
///    candidats écartés rendrait possible un `reduce(MAX)` « pour voir », qui
///    est précisément ce que ce module doit rendre impossible à écrire.
class EcartementRapport {
  /// Libellé officiel du rapport écarté.
  final String libelle;

  /// Combinaison publiée du rapport écarté.
  final String combinaison;

  /// Code API du rapport écarté.
  final String codeApi;

  /// Raison de l'écartement.
  final MotifEcartementPmu motif;

  const EcartementRapport({
    required this.libelle,
    required this.combinaison,
    required this.codeApi,
    required this.motif,
  });

  @override
  String toString() =>
      'EcartementRapport("$libelle" | "$combinaison" | $codeApi | $motif)';
}

// ───────────────────────────────────────────────────────────────────────────
//  RÉSULTAT
// ───────────────────────────────────────────────────────────────────────────

/// Résultat d'une résolution : **soit** un rapport, **soit** un motif.
///
/// Aucun état intermédiaire. Un montant partiel, un rapport « approchant » ou
/// un `null` muet sont impossibles par construction : si [trouve] est faux,
/// [motifRefus] est non nul et [explication] est renseignée.
class ResolutionRapportPmu {
  /// Rapport exactement identifié, ou `null`.
  final RapportOfficiel? rapport;

  /// Motif fermé du refus, ou `null` en cas de succès.
  final MotifRefusPmu? motifRefus;

  /// Explication lisible, toujours renseignée (vide en cas de succès).
  final String explication;

  /// Type canonique reconnu par le référentiel central, si reconnu.
  final TypePariPmu? typeCanonique;

  /// Code API retenu après contrôle croisé des deux modules, si établi.
  final String? codeApi;

  /// Rapports candidats écartés, avec leur motif. Jamais `null`.
  final List<EcartementRapport> ecartes;

  /// Succès : un rapport EXACT a été retenu.
  const ResolutionRapportPmu.trouve(
    RapportOfficiel rapportRetenu, {
    required TypePariPmu type,
    required String codeApiRetenu,
    required List<EcartementRapport> ecartesInventories,
  }) : rapport = rapportRetenu,
       motifRefus = null,
       explication = '',
       typeCanonique = type,
       codeApi = codeApiRetenu,
       ecartes = ecartesInventories;

  /// Refus : aucun rapport, un motif fermé, une explication.
  const ResolutionRapportPmu.refus(
    MotifRefusPmu motif, {
    required String explicationRefus,
    TypePariPmu? typeCanoniqueRefus,
    String? codeApiRefus,
    List<EcartementRapport> ecartesInventories = const <EcartementRapport>[],
  }) : rapport = null,
       motifRefus = motif,
       explication = explicationRefus,
       typeCanonique = typeCanoniqueRefus,
       codeApi = codeApiRefus,
       ecartes = ecartesInventories;

  /// `true` seulement si un rapport EXACT a été retenu.
  bool get trouve => rapport != null;

  /// `true` si le refus est motivé (toujours vrai quand [trouve] est faux).
  bool get refuse => motifRefus != null;

  @override
  String toString() => trouve
      ? 'ResolutionRapportPmu.trouve($rapport)'
      : 'ResolutionRapportPmu.refus($motifRefus : $explication)';
}

// ───────────────────────────────────────────────────────────────────────────
//  RÉSOLUTION
// ───────────────────────────────────────────────────────────────────────────

/// Résout le rapport officiel correspondant **exactement** au ticket.
///
/// Entrée : le libellé de type **tel qu'il est stocké sur le ticket**, les
/// numéros joués dans l'ordre saisi, et les rapports officiels de la course.
///
/// Sortie : un rapport exact, ou un refus motivé par un [MotifRefusPmu].
/// Ne rend JAMAIS `null`.
///
/// Déroulé, dans l'ordre :
///  1. reconnaît le libellé via le RÉFÉRENTIEL central ; refuse les cas hors
///     référentiel (deux composantes, non répertorié) ;
///  2. reconnaît le même libellé via le MOTEUR A ; refuse ce qu'il ne couvre
///     pas au lieu d'improviser ;
///  3. CONTRÔLE CROISÉ des deux codes API — refuse toute divergence ;
///  4. valide les numéros joués contre la taille de combinaison exigée ;
///  5. inventorie les particularités (Bonus, Tirelire, non-partants,
///     anomalies de taille) en les nommant ;
///  6. DÉLÈGUE la décision de sélection à [identifierRapportExact] ;
///  7. traduit le verdict en résultat fermé, et classe le refus.
ResolutionRapportPmu resoudreRapportPmu({
  required String libelleTypePari,
  required List<int> numerosJoues,
  required List<RapportOfficiel> rapports,
}) {
  // ── 1. Référentiel central ────────────────────────────────────────────────
  final typeCanonique = typePmuDepuisLibelleHistorique(libelleTypePari);

  if (typeCanonique == null) {
    if (estTicketApplicatifHorsReferentielPmu(libelleTypePari)) {
      return const ResolutionRapportPmu.refus(
        MotifRefusPmu.ticketDeuxComposantes,
        explicationRefus:
            '« Gagnant+Placé » est un ticket applicatif à deux composantes '
            '(un Simple Gagnant ET un Simple Placé), sans rapport PMU unique. '
            'Le dédoublement appartient à identifierGagnantPlace() du moteur A ; '
            'aucun rapport unique ne peut être retenu ici.',
      );
    }
    return ResolutionRapportPmu.refus(
      MotifRefusPmu.typeNonRepertorie,
      explicationRefus:
          'Le libellé de type de pari « $libelleTypePari » n\'est pas '
          'répertorié par le référentiel central. Aucun type par défaut n\'est '
          'substitué : aucune identification n\'est possible.',
    );
  }

  // ── 2. Moteur A ───────────────────────────────────────────────────────────
  final typeJoue = typePariDepuisLibelle(libelleTypePari);

  if (typeJoue == TypePariJoue.inconnu) {
    return ResolutionRapportPmu.refus(
      MotifRefusPmu.typeHorsMoteurA,
      typeCanoniqueRefus: typeCanonique,
      explicationRefus:
          'Le pari « $libelleTypePari » est reconnu par le référentiel central '
          '(→ $typeCanonique) mais le moteur d\'identification A ne le '
          'reconnaît pas. Le résoudre exigerait un troisième moteur, ce que '
          'l\'étape 4-A interdit : refus explicite plutôt qu\'improvisation. '
          'Aucune équivalence de graphie n\'est supposée.',
    );
  }

  final codeMoteurA = codeApiPourType(typeJoue);
  if (codeMoteurA == null) {
    return ResolutionRapportPmu.refus(
      MotifRefusPmu.typeSansCodeUniqueMoteurA,
      typeCanoniqueRefus: typeCanonique,
      explicationRefus:
          'Le moteur A ne publie aucun code API unique pour « '
          '$libelleTypePari » ($typeJoue) : ce ticket a plusieurs composantes '
          'et ne peut pas être identifié par un rapport unique.',
    );
  }

  // ── 3. Contrôle croisé des deux modules ───────────────────────────────────
  final codeReferentiel = codeApiPourTypePmu(typeCanonique);
  if (codeReferentiel == null || codeReferentiel != codeMoteurA) {
    return ResolutionRapportPmu.refus(
      MotifRefusPmu.divergenceCodesApi,
      typeCanoniqueRefus: typeCanonique,
      codeApiRefus: codeMoteurA,
      explicationRefus:
          'Contrôle croisé en échec : le référentiel central désigne '
          '« ${codeReferentiel ?? "aucun code"} » et le moteur A '
          '« $codeMoteurA » pour le même libellé « $libelleTypePari ». '
          'L\'une des deux tables a dérivé : on refuse de choisir laquelle '
          'croire plutôt que de risquer un rapport erroné.',
    );
  }

  // ── 4. Numéros joués ──────────────────────────────────────────────────────
  if (numerosJoues.isEmpty) {
    return ResolutionRapportPmu.refus(
      MotifRefusPmu.aucunNumeroJoue,
      typeCanoniqueRefus: typeCanonique,
      codeApiRefus: codeMoteurA,
      explicationRefus:
          'Aucun numéro joué n\'est enregistré pour ce ticket : il n\'y a rien '
          'à comparer à un rapport officiel, donc aucun rapport ne peut être '
          'retenu.',
    );
  }

  final tailleExigee = tailleCombinaisonGagnante(typeCanonique);
  if (tailleExigee != null && numerosJoues.length != tailleExigee) {
    return ResolutionRapportPmu.refus(
      MotifRefusPmu.tailleCombinaisonIncoherente,
      typeCanoniqueRefus: typeCanonique,
      codeApiRefus: codeMoteurA,
      explicationRefus:
          'Un « $libelleTypePari » exige une combinaison de $tailleExigee '
          'chevaux, mais ${numerosJoues.length} numéro(s) sont enregistrés. '
          'La combinaison jouée ne peut pas correspondre au pari.',
    );
  }

  // ── 5. Particularités des rapports ────────────────────────────────────────
  final inventaire = _inventorierParticularites(
    codeApi: codeMoteurA,
    typeJoue: typeJoue,
    tailleExigee: tailleExigee,
    numerosJoues: numerosJoues,
    rapports: rapports,
  );

  // ── 6. Décision : intégralement déléguée au moteur A ──────────────────────
  final identification = identifierRapportExact(
    typeJoue: typeJoue,
    numerosJoues: numerosJoues,
    rapports: rapports,
  );

  // ── 7. Traduction du verdict ──────────────────────────────────────────────
  if (!identification.trouve) {
    final nbCandidats = _nombreCandidatsExacts(
      typeJoue: typeJoue,
      numerosJoues: numerosJoues,
      rapports: rapports,
    );
    final motif = _classerRefus(
      inventaire: inventaire,
      rapportsCandidats: nbCandidats,
    );
    return ResolutionRapportPmu.refus(
      motif,
      typeCanoniqueRefus: typeCanonique,
      codeApiRefus: codeMoteurA,
      ecartesInventories: inventaire.ecartes,
      explicationRefus: _expliquerRefus(
        motif: motif,
        libelle: libelleTypePari,
        codeApi: codeMoteurA,
        numerosJoues: numerosJoues,
        inventaire: inventaire,
        moteurA: identification.motif,
      ),
    );
  }

  // ── 8. Garde-fous finaux sur le rapport RETENU ────────────────────────────
  // Le moteur A exclut déjà Bonus, non-partants et Tirelire par ses variantes
  // payables. On ré-atteste ces trois propriétés ici pour qu'elles restent
  // vraies même si A évoluait : un rapport Bonus retenu un jour par A ne doit
  // pas devenir silencieusement un gain dans l'application.
  final retenu = identification.rapport!;

  switch (varianteDepuisLibelle(retenu.libelle)) {
    case VarianteRapport.bonusQuarte:
    case VarianteRapport.bonus4sur5:
    case VarianteRapport.bonus3:
      return ResolutionRapportPmu.refus(
        MotifRefusPmu.aucunRapportExact,
        typeCanoniqueRefus: typeCanonique,
        codeApiRefus: codeMoteurA,
        ecartesInventories: inventaire.ecartes,
        explicationRefus:
            'Le moteur A a retenu un rapport Bonus (« ${retenu.libelle} »), '
            'dont la combinaison est plus courte que celle du pari : ce n\'est '
            'pas le rapport du ticket. Refus par précaution.',
      );
    case VarianteRapport.nonPartant:
      return ResolutionRapportPmu.refus(
        MotifRefusPmu.aucunRapportExact,
        typeCanoniqueRefus: typeCanonique,
        codeApiRefus: codeMoteurA,
        ecartesInventories: inventaire.ecartes,
        explicationRefus:
            'Le moteur A a retenu un rapport de non-partant '
            '(« ${retenu.libelle} »), dont la combinaison n\'est pas une suite '
            'de chevaux. Refus par précaution.',
      );
    case VarianteRapport.tirelire:
      return ResolutionRapportPmu.refus(
        MotifRefusPmu.ambiguiteTirelire,
        typeCanoniqueRefus: typeCanonique,
        codeApiRefus: codeMoteurA,
        ecartesInventories: inventaire.ecartes,
        explicationRefus:
            'Le moteur A a retenu un rapport e-Tirelire (« ${retenu.libelle} ») '
            'dont le statut de rapport définitif n\'est pas démontré pour cette '
            'course. Refus par précaution.',
      );
    case VarianteRapport.illisible:
      return ResolutionRapportPmu.refus(
        MotifRefusPmu.aucunRapportExact,
        typeCanoniqueRefus: typeCanonique,
        codeApiRefus: codeMoteurA,
        ecartesInventories: inventaire.ecartes,
        explicationRefus:
            'Le rapport retenu porte un libellé illisible : sa variante ne peut '
            'pas être attestée. Refus par précaution.',
      );
    case VarianteRapport.ordre:
    case VarianteRapport.desordre:
    case VarianteRapport.sansVariante:
      break;
  }

  if (retenu.rapportPourUnEuro == null) {
    return ResolutionRapportPmu.refus(
      MotifRefusPmu.dividendePourUnEuroAbsent,
      typeCanoniqueRefus: typeCanonique,
      codeApiRefus: codeMoteurA,
      ecartesInventories: inventaire.ecartes,
      explicationRefus:
          'Le rapport « ${retenu.libelle} » (${retenu.combinaison}) existe mais '
          'son dividende pour 1 € est absent : aucun montant ne peut être '
          'établi. Aucune reconstitution approximative n\'est tentée.',
    );
  }

  if (retenu.rembourse) {
    return ResolutionRapportPmu.refus(
      MotifRefusPmu.rapportRembourse,
      typeCanoniqueRefus: typeCanonique,
      codeApiRefus: codeMoteurA,
      ecartesInventories: inventaire.ecartes,
      explicationRefus:
          'Le rapport « ${retenu.libelle} » (${retenu.combinaison}) est marqué '
          'remboursé par l\'API : l\'attribution relève du remboursement et non '
          'du calcul de gain. Refus explicite.',
    );
  }

  return ResolutionRapportPmu.trouve(
    retenu,
    type: typeCanonique,
    codeApiRetenu: codeMoteurA,
    ecartesInventories: inventaire.ecartes,
  );
}

// ───────────────────────────────────────────────────────────────────────────
//  INVENTAIRE DES PARTICULARITÉS
// ───────────────────────────────────────────────────────────────────────────

/// Résultat de l'inventaire des particularités d'un lot de rapports.
class _Inventaire {
  /// Rapports candidats écartés, nommément.
  final List<EcartementRapport> ecartes;

  /// Au moins un rapport Bonus de ce code API était présent.
  final bool bonusPresent;

  /// Au moins un rapport e-Tirelire de ce code API était présent.
  final bool tirelirePresente;

  /// Au moins un rapport de non-partant de ce code API était présent.
  final bool nonPartantPresent;

  const _Inventaire({
    required this.ecartes,
    required this.bonusPresent,
    required this.tirelirePresente,
    required this.nonPartantPresent,
  });
}

/// Inventorie les rapports du code API du pari, en nommant chaque écartement.
///
/// Ne retient AUCUNE décision : la sélection reste celle du moteur A. Les
/// rapports d'un AUTRE code API ne sont pas inventoriés — ils ne concernent
/// pas ce ticket, et les lister noierait le motif réel.
_Inventaire _inventorierParticularites({
  required String codeApi,
  required TypePariJoue typeJoue,
  required int? tailleExigee,
  required List<int> numerosJoues,
  required List<RapportOfficiel> rapports,
}) {
  final variantesPayables = variantesIdentifiablesParCombinaison(typeJoue);
  final exigeOrdre = exigeOrdreExact(typeJoue);
  final ecartes = <EcartementRapport>[];
  var bonus = false;
  var tirelire = false;
  var nonPartant = false;

  for (final r in rapports) {
    if (r.typePari != codeApi) continue;

    final variante = r.variante;

    if (variante == VarianteRapport.nonPartant) {
      nonPartant = true;
      ecartes.add(
        EcartementRapport(
          libelle: r.libelle,
          combinaison: r.combinaison,
          codeApi: r.typePari,
          motif: MotifEcartementPmu.nonPartantCombinaisonNonChevaux,
        ),
      );
      continue;
    }
    if (variante == VarianteRapport.bonusQuarte ||
        variante == VarianteRapport.bonus4sur5 ||
        variante == VarianteRapport.bonus3) {
      bonus = true;
      ecartes.add(
        EcartementRapport(
          libelle: r.libelle,
          combinaison: r.combinaison,
          codeApi: r.typePari,
          motif: MotifEcartementPmu.bonusCombinaisonPlusCourte,
        ),
      );
      continue;
    }
    if (variante == VarianteRapport.tirelire) {
      // ⚠️ PIÈGE CORRIGÉ ICI : le conflit e-Tirelire ne se produit QUE si la
      //    Tirelire porte la MÊME combinaison que le rapport principal. Une
      //    Tirelire publiée sur une autre combinaison ne concurrence rien.
      //    La marquer « présente » globalement provoquait un refus non motivé
      //    (sur-refus) : un refus injustifié est aussi fautif qu'un gain
      //    inventé. On compare donc la combinaison avant de conclure.
      final numsTirelire = r.numeros;
      final memeCombinaison = numsTirelire != null &&
          _memeCombinaisonIci(numsTirelire, numerosJoues, exigeOrdre);
      if (memeCombinaison) {
        tirelire = true;
        ecartes.add(
          EcartementRapport(
            libelle: r.libelle,
            combinaison: r.combinaison,
            codeApi: r.typePari,
            motif: MotifEcartementPmu.tirelireMemeCombinaison,
          ),
        );
      } else {
        ecartes.add(
          EcartementRapport(
            libelle: r.libelle,
            combinaison: r.combinaison,
            codeApi: r.typePari,
            motif: numsTirelire == null
                ? MotifEcartementPmu.nonPartantCombinaisonNonChevaux
                : MotifEcartementPmu.combinaisonDifferente,
          ),
        );
      }
      continue;
    }

    if (!variantesPayables.contains(variante)) {
      ecartes.add(
        EcartementRapport(
          libelle: r.libelle,
          combinaison: r.combinaison,
          codeApi: r.typePari,
          motif: MotifEcartementPmu.varianteNonPayable,
        ),
      );
      continue;
    }

    final nums = r.numeros;
    if (nums == null) {
      ecartes.add(
        EcartementRapport(
          libelle: r.libelle,
          combinaison: r.combinaison,
          codeApi: r.typePari,
          motif: MotifEcartementPmu.nonPartantCombinaisonNonChevaux,
        ),
      );
      continue;
    }
    if (tailleExigee != null && nums.length != tailleExigee) {
      ecartes.add(
        EcartementRapport(
          libelle: r.libelle,
          combinaison: r.combinaison,
          codeApi: r.typePari,
          motif: MotifEcartementPmu.tailleCombinaisonAnormale,
        ),
      );
      continue;
    }
    if (!_memeCombinaisonIci(nums, numerosJoues, exigeOrdre)) {
      ecartes.add(
        EcartementRapport(
          libelle: r.libelle,
          combinaison: r.combinaison,
          codeApi: r.typePari,
          motif: MotifEcartementPmu.combinaisonDifferente,
        ),
      );
      continue;
    }
    // Ce rapport porte la combinaison jouée : il n'est PAS écarté.
  }

  return _Inventaire(
    ecartes: List<EcartementRapport>.unmodifiable(ecartes),
    bonusPresent: bonus,
    tirelirePresente: tirelire,
    nonPartantPresent: nonPartant,
  );
}

/// Compte les rapports portant exactement la combinaison jouée pour ce pari —
/// **pour classer le motif de refus uniquement**.
///
/// ⚠️ Ce compte NE DÉCIDE RIEN. La décision appartient à
///    [identifierRapportExact] ; ce nombre sert seulement à distinguer
///    « aucun candidat » de « plusieurs candidats ». Le test E4A/M4 vérifie
///    que ce compte ne peut pas contredire le verdict du moteur A.
int _nombreCandidatsExacts({
  required TypePariJoue typeJoue,
  required List<int> numerosJoues,
  required List<RapportOfficiel> rapports,
}) {
  final code = codeApiPourType(typeJoue);
  if (code == null) return 0;
  final variantes = variantesIdentifiablesParCombinaison(typeJoue);
  final exigeOrdre = exigeOrdreExact(typeJoue);
  final taille = tailleCombinaisonAttendue(typeJoue);

  var n = 0;
  for (final r in rapports) {
    if (r.typePari != code) continue;
    if (!variantes.contains(r.variante)) continue;
    final nums = r.numeros;
    if (nums == null) continue;
    if (taille != null && nums.length != taille) continue;
    if (!_memeCombinaisonIci(nums, numerosJoues, exigeOrdre)) continue;
    n++;
  }
  return n;
}

/// Comparaison de combinaisons — reprise locale, volontairement minuscule.
///
/// ❗`_memeCombinaison` du moteur A est PRIVÉ (préfixe `_`). Plutôt que de
///   modifier le sous-lot A validé pour l'exposer, on reproduit ici les huit
///   lignes du test d'égalité. Ce n'est pas un troisième calcul de gain : c'est
///   la même comparaison, utilisée uniquement pour l'inventaire et le classement
///   des motifs. La SÉLECTION, elle, reste celle de A.
bool _memeCombinaisonIci(List<int> rapport, List<int> joues, bool exigeOrdre) {
  if (rapport.length != joues.length) return false;
  if (exigeOrdre) {
    for (var i = 0; i < rapport.length; i++) {
      if (rapport[i] != joues[i]) return false;
    }
    return true;
  }
  final a = List<int>.from(rapport)..sort();
  final b = List<int>.from(joues)..sort();
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ───────────────────────────────────────────────────────────────────────────
//  CLASSEMENT ET EXPLICATION DU REFUS
// ───────────────────────────────────────────────────────────────────────────

/// Choisit le motif fermé du refus à partir des faits inventoriés.
///
/// L'ordre est significatif : le conflit e-Tirelire prime, parce que dans ce
/// cas deux rapports portent la même combinaison et que le motif « plusieurs
/// rapports » serait exact mais moins précis.
MotifRefusPmu _classerRefus({
  required _Inventaire inventaire,
  required int rapportsCandidats,
}) {
  if (inventaire.tirelirePresente) return MotifRefusPmu.ambiguiteTirelire;
  if (rapportsCandidats > 1) return MotifRefusPmu.ambiguitePlusieursRapports;
  return MotifRefusPmu.aucunRapportExact;
}

/// Compose l'explication du refus : elle nomme la cause ET les particularités.
String _expliquerRefus({
  required MotifRefusPmu motif,
  required String libelle,
  required String codeApi,
  required List<int> numerosJoues,
  required _Inventaire inventaire,
  required String moteurA,
}) {
  final combinee = numerosJoues.join('-');
  final details = <String>[
    if (inventaire.tirelirePresente)
      'un rapport e-Tirelire est publié pour $codeApi et concurrence le '
          'rapport principal avec la même combinaison',
    if (inventaire.bonusPresent)
      'des rapports Bonus sont publiés mais leur combinaison est plus courte '
          'que celle du pari, donc non identifiables par égalité',
    if (inventaire.nonPartantPresent)
      'des rapports de non-partant sont publiés mais leur combinaison n\'est '
          'pas une suite de chevaux',
  ];
  final suffixe = details.isEmpty
      ? ''
      : ' Particularités constatées : ${details.join(' ; ')}.';

  switch (motif) {
    case MotifRefusPmu.ambiguiteTirelire:
      return 'Conflit e-Tirelire pour « $libelle » ($codeApi, combinaison '
          '$combinee) : le rapport « + Tirelire » et le rapport sans '
          'supplément ne sont pas deux paiements alternatifs mais le même '
          'rapport à deux stades de calcul, et le statut définitif n\'est pas '
          'démontré course par course. Aucun montant n\'est retenu plutôt '
          'que d\'en choisir un.$suffixe';

    case MotifRefusPmu.ambiguitePlusieursRapports:
      return 'Plusieurs rapports portent exactement la combinaison $combinee '
          'pour « $libelle » ($codeApi) : le choix entre Ordre et Désordre — '
          'ou entre deux états d\'un même rapport — dépend de l\'arrivée '
          'officielle, qui n\'est pas une donnée de ce module. Aucun montant '
          'n\'est retenu.$suffixe';

    case MotifRefusPmu.typeNonRepertorie:
    case MotifRefusPmu.ticketDeuxComposantes:
    case MotifRefusPmu.typeHorsMoteurA:
    case MotifRefusPmu.typeSansCodeUniqueMoteurA:
    case MotifRefusPmu.divergenceCodesApi:
    case MotifRefusPmu.aucunNumeroJoue:
    case MotifRefusPmu.tailleCombinaisonIncoherente:
    case MotifRefusPmu.aucunRapportExact:
    case MotifRefusPmu.dividendePourUnEuroAbsent:
    case MotifRefusPmu.rapportRembourse:
      return 'Aucun rapport officiel ne correspond exactement à « $libelle » '
          '($codeApi) avec la combinaison $combinee. Motif du moteur A : '
          '$moteurA$suffixe';
  }
}
