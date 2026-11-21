// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 1 — RÉFÉRENTIEL CENTRAL DES TYPES DE PARIS PMU
//
//  CE FICHIER EST UNE FONDATION, PAS UN BRANCHEMENT.
//
//  Aucun écran, aucun service, aucun stockage, aucun calcul ne l'importe.
//  Il ne modifie donc AUCUN comportement. Il existe pour qu'il n'y ait plus,
//  à terme, plusieurs implémentations divergentes de la même correspondance
//  entre un libellé applicatif et un type de pari PMU (aujourd'hui réparties
//  entre `pmu_api_service.dart` (`_typePariApiFromLabel`),
//  `mes_paris_screen.dart` (mapping + `_filtrerRapportsParType`),
//  `paris_detail_screen.dart` (mapping dupliqué) et `alert_service.dart`,
//  cette dernière étant la seule exacte).
//
//  RÈGLE ABSOLUE : DEUX PARIS PMU DIFFÉRENTS NE SONT JAMAIS ASSIMILÉS.
//  Un type de pari = une entrée. Aucune entrée n'est un alias d'une autre.
//
//  PROVENANCE DES VALEURS — deux sources, et deux seulement :
//   (1) RÈGLEMENT PMU en vigueur (version du 05/07/2022), cité littéralement
//       et brièvement, sans renvoi de ligne ;
//   (2) MESURES sur les rapports définitifs réels de l'API v7
//       (`/rest/client/7/programme/{date}/R{n}/C{n}/rapports-definitifs`),
//       jeu de 206 courses et 3 742 rapports couvrant le 08 → 16 nov. 2026.
//
//  Ce qui n'est pas démontré par l'une de ces deux sources est marqué
//  NON RÉSOLU et rend `null`. Jamais une valeur plausible, jamais un défaut.
//
//  PÉRIMÈTRE — CET ENUM N'EST PAS EXHAUSTIF, ET LE DIT.
//  Il couvre les 13 paris réellement proposés par l'application ou
//  immédiatement nécessaires à sa mise en cohérence. Trois codes présents
//  dans les rapports définitifs mesurés n'y figurent délibérément pas, faute
//  d'être proposés par l'application et faute d'avoir été étudiés :
//    • `E_DEUX_SUR_QUATRE` (2sur4, mise de base 300) ;
//    • `E_SUPER_PICK5` (mise de base 200, libellés « … Désordre » et
//      « … Super Désordre » observés) ;
//    • `EB5` (36 rapports, mise de base 100).
//  Les ignorer ici est un choix de périmètre, pas une négation : ils devront
//  être ajoutés, avec la même exigence de preuve, avant toute interface qui
//  prétendrait lister les paris réellement disponibles sur une course.
//
//  ⚠️ CE FICHIER N'EST PAS `gain_ticket_calculator.dart`.
//     Ce dernier conserve son propre `TypePariJoue` et son `codeApiPourType`,
//     qui restent la source de vérité du sous-lot A validé et ne sont pas
//     modifiés ici. Le présent référentiel RECOUVRE ce sous-lot sans le
//     remplacer ; un test dédié vérifie que les deux tables de codes ne
//     peuvent pas diverger en silence.
// ═══════════════════════════════════════════════════════════════════════════

/// Type de pari PMU canonique.
///
/// Chaque valeur correspond à un pari réellement commercialisé par le PMU et
/// identifiable par un code API distinct, à l'exception des paris dont la
/// documentation ne permet pas de trancher (voir `exigeOrdreExactSaisie` et
/// `variantesPayables`, qui rendent `null` pour ceux-là).
enum TypePariPmu {
  // ── Paris mono-composante ───────────────────────────────────────────────
  /// « e-Simple Gagnant » — 1 cheval, doit être 1er.
  simpleGagnant,

  /// « e-Simple Placé » — 1 cheval, doit être dans les trois premiers.
  simplePlace,

  // ── Paris à deux chevaux ────────────────────────────────────────────────
  /// « e-Couplé Gagnant » — 2 chevaux aux 2 premières places, ordre indifférent.
  coupleGagnant,

  /// « e-Couplé Placé » — 2 chevaux parmi les trois premiers.
  couplePlace,

  /// « e-Couplé Ordre » — 2 chevaux aux 2 premières places, ordre exact.
  ///
  /// Le règlement précise que la liste officielle des partants peut imposer de
  /// désigner les deux premiers « dans l'ordre exact d'arrivée », le pari étant
  /// « alors dénommé e-Couplé Ordre ». Même pari nominal que le Couplé Gagnant,
  /// condition de paiement différente. Code API distinct, libellé distinct
  /// ⇒ jamais interchangeable.
  coupleOrdre,

  // ── Paris à trois chevaux — TROIS PARIS DISTINCTS ───────────────────────
  /// « e-Tiercé » — 3 chevaux, ordre imposé à la saisie.
  /// Code API `E_TIERCE`.
  tierce,

  /// « e-Trio » — 3 chevaux, sans ordre.
  /// Code API `E_TRIO`.
  ///
  /// ❗NE JAMAIS assimiler au Tiercé. Mesuré : `E_TIERCE` et `E_TRIO` ne
  ///   cohabitent sur AUCUNE des 206 courses (co-occurrence = 0). Ce sont
  ///   deux paris de deux circuits différents, jamais deux variantes d'un
  ///   même pari.
  trio,

  /// « e-Trio Ordre » — 3 chevaux, ordre imposé.
  /// Code API `E_TRIO_ORDRE`.
  ///
  /// ❗Paris réel, mais NON PROPOSÉ par l'application aujourd'hui. Déclaré ici
  ///   pour que l'étape ultérieure d'exposition des paris puisse l'ajouter
  ///   sans réintroduire d'assimilation avec `trio` ou `tierce` (mesuré :
  ///   co-occurrence `E_TRIO`+`E_TRIO_ORDRE` = 0, `E_TIERCE`+`E_TRIO_ORDRE` = 0).
  trioOrdre,

  // ── Paris à quatre chevaux — DEUX PARIS DISTINCTS ───────────────────────
  /// « e-Quarté Plus » — 4 chevaux, payable en Ordre, en Désordre ou en Bonus.
  /// Code API `E_QUARTE_PLUS`.
  ///
  /// Le règlement le déclare payable « si au moins trois des quatre chevaux
  /// choisis occupent les trois premières places » ; le rapport Ordre exige
  /// les quatre premiers dans l'ordre exact, le rapport Désordre lorsque
  /// l'ordre saisi diffère, et le rapport Bonus rémunère une combinaison de
  /// quatre chevaux dont trois seulement sont dans les trois premiers.
  quartePlus,

  /// « e-Super4 » — 4 chevaux, ordre d'arrivée exact exigé.
  /// Code API `E_SUPER_QUATRE`.
  ///
  /// ❗NE JAMAIS assimiler au Quarté+. Mécanique de paiement tout autre :
  ///   le Quarté+ paie à partir de trois chevaux sur quatre et admet le
  ///   Désordre, le Super4 n'a que l'ordre exact. Mesuré : co-occurrence
  ///   `E_QUARTE_PLUS`+`E_SUPER_QUATRE` = 0 sur les 206 courses.
  superQuatre,

  // ── Paris à cinq chevaux ────────────────────────────────────────────────
  /// « e-Quinté+ » — 5 chevaux, rapports Ordre / Désordre / Bonus.
  /// Code API `E_QUINTE_PLUS`.
  quintePlus,

  // ── Paris à jeu variable (4 à 7 chevaux désignés) ───────────────────────
  /// « e-MULTI » — désigner quatre, cinq, six ou sept chevaux, sans ordre.
  /// Code API `E_MULTI`.
  ///
  /// ❗NE JAMAIS assimiler au Quinté+. Mesuré : les deux coexistent sur les
  ///   9 courses Quinté+ de notre jeu de données, en publiant chacun leurs
  ///   propres rapports et leurs propres codes. Coexistence n'est pas
  ///   équivalence : la taille de jeu est libre (4 à 7) et la combinaison
  ///   gagnante ne compte que 4 chevaux, alors que le Quinté+ en exige 5.
  multi,

  /// « e-Mini MULTI » — désigner quatre, cinq ou six chevaux, sans ordre.
  /// Code API `E_MINI_MULTI`.
  ///
  /// ❗NE JAMAIS assimiler ni au Quinté+ ni au MULTI. Mesuré : co-occurrence
  ///   `E_MULTI`+`E_MINI_MULTI` = 0 sur les 206 courses. Deux paris distincts,
  ///   pas une déclinaison l'un de l'autre.
  miniMulti,
}

// ───────────────────────────────────────────────────────────────────────────
//  CODES API OFFICIELS
// ───────────────────────────────────────────────────────────────────────────

/// Code API **unique** du pari, ou `null` si le pari n'est pas identifiable
/// par un seul code.
///
/// Aucun code n'est déduit par ressemblance de nom, aucune traduction n'est
/// supposée. Les 13 codes rendus ci-dessous ont TOUS été observés tels quels
/// dans les rapports définitifs réels (206 courses, 3 742 rapports), avec les
/// libellés suivants :
///  • `E_SIMPLE_GAGNANT` → « e-Simple Gagnant »
///  • `E_SIMPLE_PLACE` → « e-Simple Placé »
///  • `E_COUPLE_GAGNANT` → « e-Couplé Gagnant » (+ « 1 NP »)
///  • `E_COUPLE_PLACE` → « e-Couplé Placé » (+ « 1 NP »)
///  • `E_COUPLE_ORDRE` → « e-Couplé Ordre »
///  • `E_TIERCE` → « e-Tiercé Ordre », « e-Tiercé Désordre », « e-Tiercé 1 NP »
///  • `E_TRIO` → « e-Trio » (+ « 1 NP »)
///  • `E_TRIO_ORDRE` → « e-Trio Ordre » (+ « 1 NP »)
///  • `E_QUARTE_PLUS` → « e-Quarté+ Ordre », « e-Quarté+ Désordre », « e-Bonus »
///  • `E_SUPER_QUATRE` → « e-Super4 » (+ « 1 NP »)
///  • `E_QUINTE_PLUS` → « e-Quinté+ Ordre », « e-Quinté+ Désordre »,
///    « e-Bonus 4sur5 », « e-Bonus 3 », « e-Quinté+ Ordre + Tirelire »
///  • `E_MULTI` → « e-Multi en 4 » à « e-Multi en 7 »
///  • `E_MINI_MULTI` → « e-Mini Multi en 4 » à « e-Mini Multi en 6 »
String? codeApiPourTypePmu(TypePariPmu type) {
  switch (type) {
    case TypePariPmu.simpleGagnant:
      return 'E_SIMPLE_GAGNANT';
    case TypePariPmu.simplePlace:
      return 'E_SIMPLE_PLACE';
    case TypePariPmu.coupleGagnant:
      return 'E_COUPLE_GAGNANT';
    case TypePariPmu.couplePlace:
      return 'E_COUPLE_PLACE';
    case TypePariPmu.coupleOrdre:
      return 'E_COUPLE_ORDRE';
    case TypePariPmu.tierce:
      return 'E_TIERCE';
    case TypePariPmu.trio:
      return 'E_TRIO';
    case TypePariPmu.trioOrdre:
      return 'E_TRIO_ORDRE';
    case TypePariPmu.quartePlus:
      return 'E_QUARTE_PLUS';
    case TypePariPmu.superQuatre:
      return 'E_SUPER_QUATRE';
    case TypePariPmu.quintePlus:
      return 'E_QUINTE_PLUS';
    case TypePariPmu.multi:
      return 'E_MULTI';
    case TypePariPmu.miniMulti:
      return 'E_MINI_MULTI';
  }
}

// ───────────────────────────────────────────────────────────────────────────
//  TAILLES DE COMBINAISON
// ───────────────────────────────────────────────────────────────────────────

/// Nombre de chevaux qu'exige la combinaison GAGNANTE du pari.
///
/// `null` réservé aux cas où la taille ne serait pas établie. **Aucune valeur
/// de cette fonction n'est `null`** : chacune est mesurée.
///
/// CAS PARTICULIER MESURÉ — Multi et Mini Multi : la mention « en 5 » du
/// libellé ne désigne pas une combinaison de 5 chevaux, mais un JEU de
/// 5 chevaux dont la combinaison gagnante reste de **4** chevaux.
/// Mesure croisée libellé × longueur de combinaison sur les 3 742 rapports :
///  • `E_MULTI` : « en 4 », « en 5 », « en 6 », « en 7 » → longueur 4 pour
///    les quatre libellés (chacun 62 rapports, soit 248 au total) ;
///  • `E_MINI_MULTI` : « en 4 », « en 5 », « en 6 » → longueur 4 pour les
///    trois libellés (chacun 88 rapports, soit 264 au total).
/// On rend donc 4, jamais la taille annoncée par le libellé.
int? tailleCombinaisonGagnante(TypePariPmu type) {
  switch (type) {
    case TypePariPmu.simpleGagnant:
    case TypePariPmu.simplePlace:
      return 1;
    case TypePariPmu.coupleGagnant:
    case TypePariPmu.couplePlace:
    case TypePariPmu.coupleOrdre:
      return 2;
    case TypePariPmu.tierce:
    case TypePariPmu.trio:
    case TypePariPmu.trioOrdre:
      return 3;
    case TypePariPmu.quartePlus:
    case TypePariPmu.superQuatre:
      return 4;
    case TypePariPmu.quintePlus:
      return 5;
    case TypePariPmu.multi:
    case TypePariPmu.miniMulti:
      // MESURÉ : combinaison gagnante toujours de 4 chevaux, quelle que soit
      // la taille du jeu annoncée par le libellé. Voir la documentation
      // ci-dessus pour le détail des 512 rapports concernés.
      return 4;
  }
}

/// Nombre de chevaux que le parieur doit DÉSIGNER — notion distincte de
/// [tailleCombinaisonGagnante] pour le Multi et le Mini Multi.
///
/// Rend une plage `(min, max)` **fermée**, ou `null` si la plage n'est pas
/// établie. Aucune valeur rendue n'est `null`.
///
/// Sources, citées littéralement :
///  • Multi : « désigner quatre, cinq, six ou sept chevaux » ⇒ (4, 7).
///    Mesuré : libellés « en 4 » à « en 7 ».
///  • Mini Multi : « désigner quatre, cinq ou six chevaux » ⇒ (4, 6).
///    Mesuré : libellés « en 4 » à « en 6 ».
({int min, int max})? tailleJeu(TypePariPmu type) {
  switch (type) {
    case TypePariPmu.simpleGagnant:
    case TypePariPmu.simplePlace:
      return (min: 1, max: 1);
    case TypePariPmu.coupleGagnant:
    case TypePariPmu.couplePlace:
    case TypePariPmu.coupleOrdre:
      return (min: 2, max: 2);
    case TypePariPmu.tierce:
    case TypePariPmu.trio:
    case TypePariPmu.trioOrdre:
      return (min: 3, max: 3);
    case TypePariPmu.quartePlus:
    case TypePariPmu.superQuatre:
      return (min: 4, max: 4);
    case TypePariPmu.quintePlus:
      return (min: 5, max: 5);
    case TypePariPmu.multi:
      return (min: 4, max: 7);
    case TypePariPmu.miniMulti:
      return (min: 4, max: 6);
  }
}

// ───────────────────────────────────────────────────────────────────────────
//  EXIGENCE D'ORDRE À LA SAISIE, AVEC SES CAS NON RÉSOLUS
// ───────────────────────────────────────────────────────────────────────────

/// `true` si le pari exige de préciser l'ordre d'arrivée **à la saisie**.
///
/// Cette notion décrit la SAISIE, pas la condition de PAIEMENT. Les deux sont
/// volontairement séparées : un Quarté+ exige un ordre à la saisie (`true`)
/// tout en étant payable en Désordre (voir [variantesPayables]). Confondre les
/// deux est précisément l'erreur qui produit un rapport Ordre appliqué à un
/// pari Désordre.
///
/// `null` = **NON RÉSOLU** : la source consultée ne permet pas de trancher,
/// on ne devine pas.
///
/// Tout ce qui est non nul est adossé au règlement :
///  • Tiercé : « préciser leur ordre de classement » ⇒ `true`.
///  • Trio : « sans avoir à préciser leur ordre d'arrivée » ⇒ `false`.
///  • Trio Ordre : « préciser leur ordre de classement » ⇒ `true`.
///  • Super4 : « en précisant leur ordre d'arrivée » ⇒ `true`.
///  • Quarté Plus : « préciser leur ordre de classement » ⇒ `true`
///    (paiement en Désordre possible, cf. [variantesPayables]).
///  • Quinté+ : ordre exigé à la saisie, rapports Ordre ET Désordre
///    effectivement observés ⇒ `true`.
///  • Couplé Gagnant : ordre indifférent ⇒ `false`.
///  • Couplé Ordre : ordre exact exigé ⇒ `true`.
///  • Couplé Placé : « deux des trois premières places », aucun ordre
///    ⇒ `false`.
///  • Simple Gagnant / Simple Placé : un seul cheval, la notion d'ordre est
///    sans objet ⇒ `false`, et non « non résolu ».
///
/// NON RÉSOLU, et assumé comme tel :
///  • **Multi** et **Mini Multi** ⇒ `null`. Les deux articles déclarent le pari
///    « sans avoir à préciser leur ordre d'arrivée », ce qui plaiderait pour
///    `false`. Mais leur phrase de paiement est amputée d'un mot — elle
///    énonce « si les quatre ou quatre des chevaux choisis occupent les quatre
///    premières places » — et cette coquille, présente dans les deux articles,
///    interdit de tenir le texte pour fiable sur ce point. Aucun rapport
///    observé ne permet de trancher. On laisse non résolu.
bool? exigeOrdreExactSaisie(TypePariPmu type) {
  switch (type) {
    case TypePariPmu.simpleGagnant:
    case TypePariPmu.simplePlace:
    case TypePariPmu.coupleGagnant:
    case TypePariPmu.couplePlace:
    case TypePariPmu.trio:
      return false;
    case TypePariPmu.coupleOrdre:
    case TypePariPmu.tierce:
    case TypePariPmu.trioOrdre:
    case TypePariPmu.quartePlus:
    case TypePariPmu.superQuatre:
    case TypePariPmu.quintePlus:
      return true;
    case TypePariPmu.multi:
    case TypePariPmu.miniMulti:
      // NON RÉSOLU — voir la justification ci-dessus.
      return null;
  }
}

// ───────────────────────────────────────────────────────────────────────────
//  VARIANTES DE RAPPORT ADMISES
// ───────────────────────────────────────────────────────────────────────────

/// Variante d'un rapport, déduite du `libelle` rendu par l'API.
///
/// Nomenclature volontairement **indépendante** de celle du sous-lot A, afin
/// que les deux modules ne se verrouillent pas mutuellement : le sous-lot A
/// reste tel qu'il a été validé, ce référentiel est libre de couvrir des paris
/// que A ne traite pas encore.
enum VariantePmu {
  /// « … Ordre ».
  ordre,

  /// « … Désordre ».
  desordre,

  /// Rapport sans notion d'ordre : « e-Simple Gagnant », « e-Trio »,
  /// « e-Multi en 5 », « e-Super4 », « e-Bonus »…
  sansVariante,

  /// « e-Bonus » du Quarté+.
  bonusQuarte,

  /// « e-Bonus 4sur5 » du Quinté+.
  bonus4sur5,

  /// « e-Bonus 3 » du Quinté+.
  bonus3,

  /// « … 1 NP », « … 2 NP » — cheval non partant.
  nonPartant,

  /// « e-Quinté+ Ordre + Tirelire » — supplément e-Tirelire.
  tirelire,

  /// Libellé vide ou absent : on ne suppose rien.
  illisible,
}

/// Variante d'un rapport, déduite **du libellé uniquement**.
///
/// Le `typePari` de l'API ne porte JAMAIS cette information : mesuré,
/// `E_TIERCE` publie « e-Tiercé Ordre » et « e-Tiercé Désordre » avec la MÊME
/// combinaison. Toute heuristique qui déduit l'ordre du type de pari est donc
/// fausse par construction, et toute heuristique qui déduit le désordre d'une
/// présence de « NP » dans la combinaison l'est aussi : un rapport
/// « e-Couplé Placé 1 NP » est un rapport de non-partant, pas un désordre.
///
/// L'ordre des tests ci-dessous est significatif :
///  1. non-partant d'abord — il prime sur toute autre qualification ;
///  2. Bonus ensuite — « e-Bonus » ne contient ni « ordre » ni « désordre » ;
///  3. Tirelire avant « ordre » — « e-Quinté+ Ordre + Tirelire » contient
///     « ordre » et serait sinon confondu avec le rapport Ordre simple ;
///  4. « désordre » avant « ordre », par sûreté.
VariantePmu varianteDepuisLibellePmu(String libelle) {
  final l = libelle.toLowerCase().trim();
  if (l.isEmpty) return VariantePmu.illisible;

  if (RegExp(r'\b[12]\s*np\b').hasMatch(l)) return VariantePmu.nonPartant;

  if (l.contains('bonus 4sur5') || l.contains('bonus 4 sur 5')) {
    return VariantePmu.bonus4sur5;
  }
  if (l.contains('bonus 3')) return VariantePmu.bonus3;
  if (l.contains('bonus')) return VariantePmu.bonusQuarte;

  if (l.contains('tirelire')) return VariantePmu.tirelire;

  if (l.contains('désordre') || l.contains('desordre')) {
    return VariantePmu.desordre;
  }
  if (l.contains('ordre')) return VariantePmu.ordre;

  return VariantePmu.sansVariante;
}

/// Variantes qu'un rapport peut porter pour rémunérer [type].
///
/// `null` = **NON RÉSOLU** : la source ne permet pas d'établir la liste, on ne
/// l'invente pas.
///
/// ÉTABLI (liste exhaustive des libellés réellement observés par type) :
///  • Simple Gagnant / Simple Placé : un seul libellé ⇒ `{sansVariante}`.
///  • Couplé Gagnant / Couplé Placé : un seul libellé ⇒ `{sansVariante}`.
///  • Couplé Ordre : un seul libellé ⇒ `{ordre}`.
///  • Trio : « e-Trio » ⇒ `{sansVariante}`.
///  • Trio Ordre : « e-Trio Ordre » ⇒ `{ordre}`.
///  • Super4 : « e-Super4 » ⇒ `{sansVariante}`. Le Super4 n'a pas de rapport
///    Désordre : l'ordre exact est la seule condition de paiement.
///  • Tiercé : « e-Tiercé Ordre » + « e-Tiercé Désordre »
///    ⇒ `{ordre, desordre}`.
///  • Quarté+ : « e-Quarté+ Ordre » + « e-Quarté+ Désordre » + « e-Bonus »
///    ⇒ `{ordre, desordre, bonusQuarte}`.
///  • Quinté+ : « e-Quinté+ Ordre » + « e-Quinté+ Désordre » +
///    « e-Bonus 4sur5 » + « e-Bonus 3 » + « e-Quinté+ Ordre + Tirelire »
///    ⇒ `{ordre, desordre, bonus4sur5, bonus3, tirelire}`.
///
/// NON RÉSOLU :
///  • **Multi** et **Mini Multi** ⇒ `null`. Leurs quatre et trois libellés
///    respectifs sont tous classés `sansVariante` par [varianteDepuisLibellePmu],
///    mais leur condition de paiement (combinaison de 4 chevaux parmi les
///    quatre premiers, avec une taille de jeu variable) n'est pas exprimable
///    comme une simple variante de rapport : elle relève du calcul de gain et
///    non de l'identification. Rendre `{sansVariante}` ici laisserait croire
///    que le paiement est résolu. On refuse explicitement.
///
/// NUANCE MESURÉE, à ne pas perdre de vue pour le calcul de gain : les rapports
/// Bonus ne portent pas la taille de combinaison du pari principal. Mesuré :
/// « e-Bonus » du Quarté+ a une combinaison de 3 chevaux (et non 4) ;
/// « e-Bonus 3 » du Quinté+ en a 3, « e-Bonus 4sur5 » en a 4 (et non 5).
Set<VariantePmu>? variantesPayables(TypePariPmu type) {
  switch (type) {
    case TypePariPmu.simpleGagnant:
    case TypePariPmu.simplePlace:
    case TypePariPmu.coupleGagnant:
    case TypePariPmu.couplePlace:
    case TypePariPmu.trio:
    case TypePariPmu.superQuatre:
      return const {VariantePmu.sansVariante};
    case TypePariPmu.coupleOrdre:
    case TypePariPmu.trioOrdre:
      return const {VariantePmu.ordre};
    case TypePariPmu.tierce:
      return const {VariantePmu.ordre, VariantePmu.desordre};
    case TypePariPmu.quartePlus:
      return const {
        VariantePmu.ordre,
        VariantePmu.desordre,
        VariantePmu.bonusQuarte,
      };
    case TypePariPmu.quintePlus:
      return const {
        VariantePmu.ordre,
        VariantePmu.desordre,
        VariantePmu.bonus4sur5,
        VariantePmu.bonus3,
        VariantePmu.tirelire,
      };
    case TypePariPmu.multi:
    case TypePariPmu.miniMulti:
      // NON RÉSOLU — voir la justification ci-dessus.
      return null;
  }
}

// ───────────────────────────────────────────────────────────────────────────
//  LIBELLÉS HISTORIQUES DE L'APPLICATION — LECTURE SEULE
// ───────────────────────────────────────────────────────────────────────────

/// Correspondance **en lecture seule** entre les libellés réellement
/// enregistrés par l'application et le type canonique.
///
/// ⚠️ CETTE TABLE NE CONVERTIT RIEN. Elle sert uniquement à RECONNAÎTRE un
///    libellé déjà stocké. Aucune valeur historique n'est réécrite, aucun
///    ticket n'est migré, aucun libellé n'est substitué à l'affichage.
///
/// Les libellés sources sont relevés dans le code, pas supposés :
///  • `bet_bottom_sheet.dart` (`_typesPari`) — 8 entrées ;
///  • `mes_paris_screen.dart` (`_typesPariDisponibles`) — 12 entrées ;
///  • `roi_value_screen.dart` (`_typesPari`) — 8 entrées, dont « Tous » qui est
///    un filtre et non un pari : volontairement absent de cette table.
///
/// Les variantes d'orthographe réellement présentes dans le code sont
/// conservées, notamment celles recensées par `type_pari_utils.dart`
/// (« Gagnant+Placé », « Gagnant + Placé », « Gagnant+Place »).
const Map<String, TypePariPmu> kLibellesHistoriquesVersTypePmu = {
  // ── Simple ──────────────────────────────────────────────────────────────
  'simple gagnant': TypePariPmu.simpleGagnant,
  'simple placé': TypePariPmu.simplePlace,
  'simple place': TypePariPmu.simplePlace,
  // « Gagnant+Placé » n'est PAS un pari PMU : c'est un ticket applicatif à
  // DEUX composantes (un Simple Gagnant + un Simple Placé). Il n'a donc aucune
  // entrée canonique et reste volontairement absent de cette table. Le mapper
  // sur l'un des deux serait exactement l'assimilation interdite. Voir
  // [estTicketApplicatifHorsReferentielPmu].
  // ── Couplé ──────────────────────────────────────────────────────────────
  'couplé gagnant': TypePariPmu.coupleGagnant,
  'couple gagnant': TypePariPmu.coupleGagnant,
  'couplé placé': TypePariPmu.couplePlace,
  'couple place': TypePariPmu.couplePlace,
  'couplé ordre': TypePariPmu.coupleOrdre,
  // « Couplé Désordre » : libellé applicatif SANS équivalent API distinct. Le
  // PMU ne publie pas de code « Couplé Désordre » — le Couplé Gagnant EST le
  // couplé sans ordre. Le rattacher à `coupleGagnant` est donc exact et non
  // une assimilation. Mesuré : `E_COUPLE_GAGNANT` et `E_COUPLE_ORDRE` ne
  // cohabitent sur aucune course, et aucun libellé « Couplé Désordre »
  // n'existe côté API.
  'couplé désordre': TypePariPmu.coupleGagnant,
  'couple desordre': TypePariPmu.coupleGagnant,
  // ── Trois chevaux ───────────────────────────────────────────────────────
  // « Tiercé » (générique) est ambigu : le PMU impose l'ordre à la saisie mais
  // publie AUSSI un rapport Désordre. On le rattache à `tierce`, dont
  // [variantesPayables] couvre précisément les deux variantes.
  'tiercé': TypePariPmu.tierce,
  'tierce': TypePariPmu.tierce,
  'tiercé ordre': TypePariPmu.tierce,
  'tiercé désordre': TypePariPmu.tierce,
  // ── Quatre et cinq chevaux ──────────────────────────────────────────────
  'quarté+': TypePariPmu.quartePlus,
  'quarté': TypePariPmu.quartePlus,
  'quarte+': TypePariPmu.quartePlus,
  'quinte+': TypePariPmu.quintePlus,
  'quinté+': TypePariPmu.quintePlus,
  'quinté': TypePariPmu.quintePlus,
};

/// Reconnaît un libellé historique. Rend `null` si le libellé n'est pas
/// répertorié — et non un type par défaut, qui masquerait une donnée inconnue
/// derrière une valeur plausible.
///
/// Pure : aucun effet de bord, aucune écriture, aucun accès disque.
TypePariPmu? typePmuDepuisLibelleHistorique(String? libelle) {
  if (libelle == null) return null;
  final n = libelle.trim().toLowerCase();
  if (n.isEmpty) return null;
  return kLibellesHistoriquesVersTypePmu[n];
}

/// Un libellé historique désigne-t-il un ticket **applicatif** sans équivalent
/// PMU unique (le « Gagnant+Placé » à deux composantes) ?
///
/// Sert à distinguer deux situations que rien ne doit confondre :
///  • libellé inconnu ⇒ donnée corrompue ou non répertoriée ;
///  • libellé connu mais hors référentiel PMU ⇒ cas normal, à traiter par le
///    module A (identification conjointe des deux composantes).
bool estTicketApplicatifHorsReferentielPmu(String? libelle) {
  if (libelle == null) return false;
  final n = libelle.trim().toLowerCase();
  return n == 'gagnant+placé' || n == 'gagnant + placé' || n == 'gagnant+place';
}

// ───────────────────────────────────────────────────────────────────────────
//  NON-ASSIMILATION — INVARIANT VÉRIFIABLE
// ───────────────────────────────────────────────────────────────────────────

/// Les couples de paris qui ne doivent JAMAIS partager un code API.
///
/// Exposé comme donnée pour qu'un test parcoure l'invariant au lieu de le
/// recopier à la main : si un jour une entrée de [codeApiPourTypePmu] est
/// modifiée pour faire converger deux paris, ce test tombe.
///
/// Chaque couple est justifié soit par deux codes observés distincts, soit par
/// deux conditions de paiement incompatibles, soit par une co-occurrence nulle
/// sur les 206 courses mesurées.
const List<(TypePariPmu, TypePariPmu)> kCouplesNonAssimilables = [
  // Trois paris à trois chevaux, trois circuits distincts.
  (TypePariPmu.tierce, TypePariPmu.trio),
  (TypePariPmu.tierce, TypePariPmu.trioOrdre),
  (TypePariPmu.trio, TypePariPmu.trioOrdre),
  // Quatre chevaux : paiement à 3 sur 4 vs ordre exact obligatoire.
  (TypePariPmu.quartePlus, TypePariPmu.superQuatre),
  // Cinq chevaux contre jeu variable : coexistent, jamais équivalents.
  (TypePariPmu.quintePlus, TypePariPmu.multi),
  (TypePariPmu.quintePlus, TypePariPmu.miniMulti),
  (TypePariPmu.multi, TypePariPmu.miniMulti),
  // Couplé : un pari de même nom, deux conditions de paiement.
  (TypePariPmu.coupleGagnant, TypePariPmu.coupleOrdre),
  (TypePariPmu.couplePlace, TypePariPmu.coupleOrdre),
];
