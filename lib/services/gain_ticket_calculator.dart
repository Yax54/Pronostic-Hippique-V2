// ═══════════════════════════════════════════════════════════════════════════
//  SOUS-LOT A — IDENTIFICATION EXACTE TICKET ⇄ RAPPORT PMU
//
//  Ce fichier est VOLONTAIREMENT PUR : aucune I/O, aucun état, aucun
//  `SharedPreferences`, aucun `SetState`. Il ne décide de RIEN côté UI.
//  Il répond à une seule question, de façon vérifiable :
//
//      « Pour CE pari précis (type + combinaison + ordre), existe-t-il
//        un rapport officiel PMU qui lui corresponde EXACTEMENT ? »
//
//  Règles de conception (mandat §3 et §4-A) :
//
//   1. AUCUNE sélection par `reduce(MAX)` : le rapport le plus élevé d'une
//      course n'est JAMAIS celui du ticket par construction.
//   2. AUCUN repli `first` : un rapport n'est retenu que si son `typePari`
//      est CELUI du pari joué et si sa `combinaison` est identique.
//   3. `libelle` est la SEULE source fiable de la variante Ordre / Désordre /
//      Bonus / 1 NP. Le `typePari` ne les distingue pas : mesuré sur les
//      artefacts réels (50 fichiers, 839 rapports), `E_TIERCE` publie
//      « e-Tiercé Ordre » ET « e-Tiercé Désordre » avec la MÊME combinaison
//      `13-16-7` et deux dividendes différents (473520 / 61480).
//   4. Échec fermé : si l'identification est insuffisante, on rend un motif —
//      jamais un montant, jamais un rapport « approchant ».
//
//  MESURES DE RÉFÉRENCE (rejouables sur /home/user/recherche_pmu/rapports) :
//
//   • 839 rapports, 0 sans `dividendePourUnEuro` → le pour-un-euro est
//     TOUJOURS présent ; le repli existe mais n'est jamais déclenché.
//   • `dividendePourUnEuro = dividendePourUneMiseDeBase × 100 / miseBase`
//     vérifié exactement : Quarté+ 944220×100/150 = 629480 ;
//     Quinté+ 3116260×100/200 = 1558130 ; Bonus 4sur5 6500×100/200 = 3250.
//   • `miseBase` en centimes : 100 (Simple, Couplé, Tiercé, Trio, Super4),
//     150 (Quarté+), 200 (Quinté+, Super Pick5), 300 (Multi, Mini Multi,
//     2sur4).
//
//  CE QUI RESTE VOLONTAIREMENT HORS DE CE SOUS-LOT (documenté, non traité) :
//
//   • Les rapports **Bonus** (`e-Bonus`, `e-Bonus 4sur5`, `e-Bonus 3`)
//     publient une combinaison PLUS COURTE que le pari (3 numéros pour
//     « e-Bonus » du Quarté+, 4 pour « e-Bonus 4sur5 »). Une égalité de
//     combinaison ne peut donc pas les identifier : leur attribution relève
//     des règles officielles de paiement (§4-C), pas de l'identification.
//   • Les rapports **non-partants** (`… 1 NP`, combinaison `8-NP`) ne portent
//     pas une combinaison de chevaux : remboursement et report relèvent de
//     §4-C.
//   • L'**arbitrage Ordre/Désordre d'un pari générique** (« Tiercé »,
//     « Quarté+ », « Quinté+ » sans mention d'ordre) : les deux rapports
//     portent la MÊME combinaison, donc seule l'arrivée officielle permet de
//     savoir lequel est applicable. Le module refuse par ambiguïté explicite
//     plutôt que de choisir ; cet arbitrage appartient à §4-C.
// ═══════════════════════════════════════════════════════════════════════════

/// Variante officielle d'un rapport PMU, déduite du `libelle` renvoyé par
/// l'API — JAMAIS du `typePari`, qui ne la porte pas.
///
/// Mesuré sur 839 rapports réels :
///  • `E_SIMPLE_GAGNANT` → « e-Simple Gagnant »            ⇒ [sansVariante]
///  • `E_SIMPLE_PLACE`   → « e-Simple Placé »              ⇒ [sansVariante]
///  • `E_COUPLE_GAGNANT` → « e-Couplé Gagnant »            ⇒ [sansVariante]
///  • `E_COUPLE_PLACE`   → « e-Couplé Placé »              ⇒ [sansVariante]
///  • `E_COUPLE_ORDRE`   → « e-Couplé Ordre »              ⇒ [ordre]
///  • `E_TIERCE`         → « e-Tiercé Ordre » / « Désordre » ⇒ [ordre] / [desordre]
///  • `E_QUARTE_PLUS`    → « e-Quarté+ Ordre/Désordre », « e-Bonus »
///  • `E_QUINTE_PLUS`    → « e-Quinté+ Ordre/Désordre »,
///                         « e-Bonus 4sur5 », « e-Bonus 3 »
///  • tout pari         → « … 1 NP » / « … 2 NP »         ⇒ [nonPartant]
///
/// ⚠️ L'ancienne heuristique `combinaison.contains('NP') ⇒ désordre`
///    (pmu_api_service.dart) classait « e-Couplé Placé 1 NP » comme un
///    désordre : c'est FAUX, c'est un rapport de non-partant.
enum VarianteRapport {
  /// Rapport dans l'ordre exact (« … Ordre »).
  ordre,

  /// Rapport dans le désordre (« … Désordre »).
  desordre,

  /// Rapport « Bonus » du Quarté+ (« e-Bonus »).
  bonusQuarte,

  /// Rapport « Bonus 4 chevaux sur 5 » du Quinté+ (« e-Bonus 4sur5 »).
  bonus4sur5,

  /// Rapport « Bonus 3 chevaux sur 5 » du Quinté+ (« e-Bonus 3 »).
  bonus3,

  /// Rapport consécutif à un cheval non-partant (« … 1 NP », « … 2 NP »).
  nonPartant,

  /// Libelle reconnu, sans notion d'ordre (Simple, Couplé Gagnant/Placé…).
  sansVariante,

  /// Libelle vide ou absent : on ne suppose RIEN.
  illisible,
}

/// Un rapport officiel PMU, tel que publié, avec ses champs de référence.
class RapportOfficiel {
  /// Code API du type de pari (`E_SIMPLE_PLACE`, `E_TIERCE`, …).
  final String typePari;

  /// Libellé officiel complet (`« e-Tiercé Ordre »`, `« e-Bonus 4sur5 »`, …).
  final String libelle;

  /// Combinaison officielle telle que publiée (`« 8 »`, `« 8-3 »`, `« 8-NP »`).
  final String combinaison;

  /// Rapport **pour 1 € engagé**, en euros. `null` si l'API ne l'a pas fourni
  /// (jamais observé sur 839 rapports, mais on ne l'invente pas).
  final double? rapportPourUnEuro;

  /// `true` si l'API a explicitement marqué ce rapport comme remboursé.
  final bool rembourse;

  const RapportOfficiel({
    required this.typePari,
    required this.libelle,
    required this.combinaison,
    required this.rapportPourUnEuro,
    this.rembourse = false,
  });

  /// Variante officielle, déduite **du libelle uniquement**.
  VarianteRapport get variante => varianteDepuisLibelle(libelle);

  /// Numéros de la combinaison, dans l'ordre publié. `null` si illisible.
  ///
  /// Une combinaison contenant `NP` n'est PAS une combinaison de chevaux :
  /// elle ne peut jamais correspondre à un ticket de chevaux.
  List<int>? get numeros {
    if (combinaison.isEmpty) return null;
    final out = <int>[];
    for (final part in combinaison.split('-')) {
      final t = part.trim();
      if (t.isEmpty) return null;
      if (t.toUpperCase() == 'NP') return null; // rapport de non-partant
      final n = int.tryParse(t);
      if (n == null || n <= 0) return null;
      out.add(n);
    }
    return out.isEmpty ? null : out;
  }

  /// `true` si ce rapport porte une combinaison de chevaux comparable.
  bool get estComparable => numeros != null;

  /// Construit depuis un objet `rapports[]` brut de l'API.
  ///
  /// Le rapport est normalisé en **euros pour 1 €** :
  ///  • priorité à `dividendePourUnEuro` (centimes → euros) ;
  ///  • à défaut, reconstitution EXACTE via `dividendePourUneMiseDeBase` et
  ///    `miseBase` — jamais depuis `dividende` seul, dont l'unité varie
  ///    (×3 sur un Multi, ×2 sur un Quinté+, ×1,5 sur un Quarté+).
  ///
  /// Retourne `null` si le rapport n'a ni libelle ni combinaison : on ne
  /// fabrique pas de rapport anonyme.
  static RapportOfficiel? depuisJson(
    Map<String, dynamic> json, {
    required String typePari,
    required int? miseBaseCentimes,
  }) {
    final libelle = (json['libelle'] as String?)?.trim() ?? '';
    final combinaison = (json['combinaison'] as String?)?.trim() ?? '';
    if (libelle.isEmpty && combinaison.isEmpty) return null;

    return RapportOfficiel(
      typePari: typePari,
      libelle: libelle,
      combinaison: combinaison,
      rapportPourUnEuro: _lirePourUnEuro(json, miseBaseCentimes),
      rembourse: json['rembourse'] == true,
    );
  }

  /// Lit le rapport **pour 1 €** en euros, sans jamais changer d'unité.
  static double? _lirePourUnEuro(
    Map<String, dynamic> json,
    int? miseBaseCentimes,
  ) {
    final pe = json['dividendePourUnEuro'];
    if (pe is num) return pe.toDouble() / 100.0;

    // Repli EXACT : l'unité « mise de base » est ramenée au pour-un-euro.
    final mb = json['dividendePourUneMiseDeBase'];
    if (mb is num && miseBaseCentimes != null && miseBaseCentimes > 0) {
      return mb.toDouble() / miseBaseCentimes;
    }
    return null;
  }

  @override
  String toString() =>
      'RapportOfficiel($typePari | "$libelle" | "$combinaison" | '
      '×$rapportPourUnEuro)';
}

/// Type de pari réellement joué, tel qu'enregistré dans
/// `TrackedCourse.typePari`.
///
/// Les libellés sources sont ceux réellement proposés par l'application
/// (`mes_paris_screen.dart` `_typesPariDisponibles` — 12 entrées — et
/// `bet_bottom_sheet.dart` `_typesPari` — 8 entrées).
enum TypePariJoue {
  simpleGagnant,
  simplePlace,
  gagnantPlace,
  coupleGagnant,
  couplePlace,
  coupleOrdre,
  coupleDesordre,
  tierce,
  tierceOrdre,
  tierceDesordre,
  quarte,
  quinte,
  inconnu,
}

/// Traduit un libellé applicatif en type de pari canonique.
///
/// Rend [TypePariJoue.inconnu] pour tout libellé non répertorié : un type
/// inconnu ne doit produire AUCUN calcul financier.
TypePariJoue typePariDepuisLibelle(String typePari) {
  switch (typePari.trim()) {
    case 'Simple Gagnant':
      return TypePariJoue.simpleGagnant;
    case 'Simple Placé':
      return TypePariJoue.simplePlace;
    case 'Gagnant+Placé':
      return TypePariJoue.gagnantPlace;
    case 'Couplé Gagnant':
      return TypePariJoue.coupleGagnant;
    case 'Couplé Placé':
      return TypePariJoue.couplePlace;
    case 'Couplé Ordre':
      return TypePariJoue.coupleOrdre;
    case 'Couplé Désordre':
      return TypePariJoue.coupleDesordre;
    case 'Tiercé':
      return TypePariJoue.tierce;
    case 'Tiercé Ordre':
      return TypePariJoue.tierceOrdre;
    case 'Tiercé Désordre':
      return TypePariJoue.tierceDesordre;
    case 'Quarté+':
      return TypePariJoue.quarte;
    case 'Quinté+':
      return TypePariJoue.quinte;
    default:
      return TypePariJoue.inconnu;
  }
}

/// Nombre de chevaux qu'exige la combinaison d'un type de pari. `null` si le
/// type est inconnu — on ne devine pas.
int? tailleCombinaisonAttendue(TypePariJoue type) {
  switch (type) {
    case TypePariJoue.simpleGagnant:
    case TypePariJoue.simplePlace:
    case TypePariJoue.gagnantPlace:
      return 1;
    case TypePariJoue.coupleGagnant:
    case TypePariJoue.couplePlace:
    case TypePariJoue.coupleOrdre:
    case TypePariJoue.coupleDesordre:
      return 2;
    case TypePariJoue.tierce:
    case TypePariJoue.tierceOrdre:
    case TypePariJoue.tierceDesordre:
      return 3;
    case TypePariJoue.quarte:
      return 4;
    case TypePariJoue.quinte:
      return 5;
    case TypePariJoue.inconnu:
      return null;
  }
}

/// Code API **unique** du pari joué.
///
/// Un seul code, et non un ensemble : accepter plusieurs codes a été mesuré
/// comme créant de fausses ambiguïtés. `E_COUPLE_ORDRE` ne publie qu'un
/// libelle (« e-Couplé Ordre ») alors que `E_COUPLE_GAGNANT` publie souvent
/// la même combinaison : accepter les deux rendait tout Couplé Ordre ambigu.
///
/// ❗`simplePlace` et `simpleGagnant` renvoient des codes DISTINCTS et il n'y
///    a AUCUN paramètre de composante ici : un paramètre booléen par défaut
///    `false` faisait retomber un Simple Placé joué seul sur le rapport
///    Gagnant — exactement le défaut que ce sous-lot doit rendre impossible.
///    Le dédoublement du Gagnant+Placé est fait par [identifierGagnantPlace].
///
/// `E_TRIO`, `E_TRIO_ORDRE`, `E_SUPER_QUATRE`, `E_MULTI`, `E_MINI_MULTI`,
/// `E_DEUX_SUR_QUATRE`, `E_SUPER_PICK5` sont des paris DIFFÉRENTS : ils ne
/// sont jamais retenus, pour ne pas attribuer le rapport d'un autre pari.
String? codeApiPourType(TypePariJoue type) {
  switch (type) {
    case TypePariJoue.simpleGagnant:
      return 'E_SIMPLE_GAGNANT';
    case TypePariJoue.simplePlace:
      return 'E_SIMPLE_PLACE';
    case TypePariJoue.gagnantPlace:
      // Ticket à DEUX composantes : pas de code unique. Le dédoublement
      // explicite est fait par `identifierGagnantPlace()`, qui appelle
      // `identifierRapportExact` avec `simpleGagnant` puis `simplePlace`.
      return null;
    case TypePariJoue.coupleGagnant:
    case TypePariJoue.coupleDesordre:
      // Le PMU ne publie pas de « Couplé Désordre » distinct : le Couplé
      // Gagnant EST le couplé sans ordre.
      return 'E_COUPLE_GAGNANT';
    case TypePariJoue.couplePlace:
      return 'E_COUPLE_PLACE';
    case TypePariJoue.coupleOrdre:
      return 'E_COUPLE_ORDRE';
    case TypePariJoue.tierce:
    case TypePariJoue.tierceOrdre:
    case TypePariJoue.tierceDesordre:
      return 'E_TIERCE';
    case TypePariJoue.quarte:
      return 'E_QUARTE_PLUS';
    case TypePariJoue.quinte:
      return 'E_QUINTE_PLUS';
    case TypePariJoue.inconnu:
      return null;
  }
}

/// Variantes de `libelle` qu'un rapport doit porter pour rémunérer le pari
/// joué — **uniquement celles identifiables par égalité de combinaison**.
///
/// Les Bonus et les non-partants sont volontairement ABSENTS : leurs
/// combinaisons ne sont pas de même taille que celle du ticket, donc une
/// égalité de combinaison ne peut pas les désigner sans risque. Leur
/// attribution relève de §4-C.
Set<VarianteRapport> variantesIdentifiablesParCombinaison(TypePariJoue type) {
  switch (type) {
    case TypePariJoue.simpleGagnant:
    case TypePariJoue.simplePlace:
    case TypePariJoue.gagnantPlace:
      // Ces libelles ne portent aucune notion d'ordre (« e-Simple Gagnant »).
      return const {VarianteRapport.sansVariante};
    case TypePariJoue.coupleGagnant:
    case TypePariJoue.couplePlace:
    case TypePariJoue.coupleDesordre:
      return const {VarianteRapport.sansVariante};
    case TypePariJoue.coupleOrdre:
      return const {VarianteRapport.ordre};
    case TypePariJoue.tierceOrdre:
      return const {VarianteRapport.ordre};
    case TypePariJoue.tierceDesordre:
      return const {VarianteRapport.desordre};
    case TypePariJoue.tierce:
    case TypePariJoue.quarte:
    case TypePariJoue.quinte:
      // Pari générique : les deux variantes portent la même combinaison.
      return const {VarianteRapport.ordre, VarianteRapport.desordre};
    case TypePariJoue.inconnu:
      return const <VarianteRapport>{};
  }
}

/// `true` si le pari impose l'ordre exact des chevaux.
bool exigeOrdreExact(TypePariJoue type) {
  switch (type) {
    case TypePariJoue.coupleOrdre:
    case TypePariJoue.tierceOrdre:
      return true;
    case TypePariJoue.simpleGagnant:
    case TypePariJoue.simplePlace:
    case TypePariJoue.gagnantPlace:
    case TypePariJoue.coupleGagnant:
    case TypePariJoue.couplePlace:
    case TypePariJoue.coupleDesordre:
    case TypePariJoue.tierce:
    case TypePariJoue.tierceDesordre:
    case TypePariJoue.quarte:
    case TypePariJoue.quinte:
    case TypePariJoue.inconnu:
      return false;
  }
}

/// Résultat d'une identification : **soit** un rapport, **soit** un motif.
///
/// Aucun état intermédiaire, aucun montant partiel : c'est ce qui garantit
/// qu'on ne peut pas « presque » identifier un rapport.
class IdentificationRapport {
  /// Rapport retenu, ou `null` si aucun ne correspond exactement.
  final RapportOfficiel? rapport;

  /// Motif lisible quand `rapport == null`.
  final String motif;

  const IdentificationRapport.trouve(RapportOfficiel r)
      : rapport = r,
        motif = '';

  const IdentificationRapport.absent(String m)
      : rapport = null,
        motif = m;

  bool get trouve => rapport != null;
}

/// Sélectionne le rapport **exact** d'un ticket, pour UN type joué.
///
/// Critères, tous obligatoires :
///  1. `typePari` **égal** au code unique du pari joué ;
///  2. `libelle` de variante ∈ [variantesIdentifiablesParCombinaison] ;
///  3. longueur de combinaison == [tailleCombinaisonAttendue] ;
///  4. combinaison **identique** à celle du ticket, dans l'ordre du ticket si
///     [exigeOrdreExact], dans n'importe quel ordre sinon.
///
/// ❗Un type joué ⇒ UN code API. Il n'y a pas de paramètre de composante :
///    [TypePariJoue.simpleGagnant] et [TypePariJoue.simplePlace] sont deux
///    entrées distinctes, et [TypePariJoue.gagnantPlace] est refusé ici
///    (deux composantes ⇒ [identifierGagnantPlace]).
///
/// ❗Aucun repli : si deux rapports correspondent, on rend
///    [IdentificationRapport.absent] — mieux vaut ne rien afficher que
///    d'afficher le mauvais montant.
IdentificationRapport identifierRapportExact({
  required TypePariJoue typeJoue,
  required List<int> numerosJoues,
  required List<RapportOfficiel> rapports,
}) {
  if (typeJoue == TypePariJoue.inconnu) {
    return const IdentificationRapport.absent(
      'Type de pari non répertorié : aucun rapport ne peut être identifié.',
    );
  }
  if (typeJoue == TypePariJoue.gagnantPlace) {
    return const IdentificationRapport.absent(
      'Gagnant+Placé est un ticket à deux composantes (Gagnant ET Placé), '
      'chacune avec sa mise et son rapport : utiliser identifierGagnantPlace(), '
      'ou identifier les composantes comme Simple Gagnant et Simple Placé.',
    );
  }
  if (numerosJoues.isEmpty) {
    return const IdentificationRapport.absent(
      'Aucun numéro joué enregistré pour ce ticket.',
    );
  }

  final code = codeApiPourType(typeJoue);
  if (code == null) {
    return const IdentificationRapport.absent(
      'Aucun code API de pari ne correspond à ce type joué.',
    );
  }
  final variantes = variantesIdentifiablesParCombinaison(typeJoue);
  final exigeOrdre = exigeOrdreExact(typeJoue);
  final taille = tailleCombinaisonAttendue(typeJoue);

  final candidats = <RapportOfficiel>[];
  for (final r in rapports) {
    if (r.typePari != code) continue;
    if (!variantes.contains(r.variante)) continue;
    if (!r.estComparable) continue; // combinaison « … -NP » : pas un cheval
    final nums = r.numeros!;
    if (taille != null && nums.length != taille) continue;
    if (!_memeCombinaison(nums, numerosJoues, exigeOrdre)) continue;
    candidats.add(r);
  }

  if (candidats.isEmpty) {
    return IdentificationRapport.absent(
      'Aucun rapport officiel ne correspond à la combinaison jouée '
      '(${numerosJoues.join('-')}) pour $code.',
    );
  }
  if (candidats.length > 1) {
    final libelles = candidats.map((c) => c.libelle).join(' / ');
    return IdentificationRapport.absent(
      'Plusieurs rapports correspondent à la même combinaison '
      '($candidats.length : $libelles) : identification ambiguë, aucun montant '
      'calculé. L\'arbitrage Ordre/Désordre dépend de l\'arrivée officielle.',
    );
  }
  final retenu = candidats.single;
  if (retenu.rapportPourUnEuro == null) {
    return const IdentificationRapport.absent(
      'Le rapport officiel existe mais son dividende pour 1 € est absent : '
      'aucun montant ne peut être calculé.',
    );
  }
  return IdentificationRapport.trouve(retenu);
}

/// Identification **séparée** des deux composantes d'un « Gagnant+Placé ».
///
/// Un Gagnant+Placé n'est pas un rapport : c'est un ticket à deux composantes,
/// chacune avec sa mise et son rapport. Les identifier ensemble reviendrait à
/// confondre le rapport Gagnant et le rapport Placé, qui ne sont jamais égaux.
class IdentificationGagnantPlace {
  final IdentificationRapport gagnant;
  final IdentificationRapport place;

  const IdentificationGagnantPlace({required this.gagnant, required this.place});

  /// `true` seulement si LES DEUX composantes sont identifiées.
  bool get complet => gagnant.trouve && place.trouve;
}

IdentificationGagnantPlace identifierGagnantPlace({
  required List<int> numerosJoues,
  required List<RapportOfficiel> rapports,
}) {
  return IdentificationGagnantPlace(
    // La composante Gagnant du ticket est identifiée EXACTEMENT comme un
    // Simple Gagnant, la composante Placé EXACTEMENT comme un Simple Placé :
    // ce sont les mêmes codes API (`E_SIMPLE_GAGNANT` / `E_SIMPLE_PLACE`).
    gagnant: identifierRapportExact(
      typeJoue: TypePariJoue.simpleGagnant,
      numerosJoues: numerosJoues,
      rapports: rapports,
    ),
    place: identifierRapportExact(
      typeJoue: TypePariJoue.simplePlace,
      numerosJoues: numerosJoues,
      rapports: rapports,
    ),
  );
}

/// Compare deux combinaisons de numéros.
bool _memeCombinaison(List<int> rapport, List<int> joues, bool exigeOrdre) {
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

/// Déduit la variante d'un rapport depuis son **libelle officiel**.
///
/// L'ordre des tests est significatif :
///  • les non-partants d'abord — « e-Couplé Placé 1 NP » contient « Placé » et
///    l'ancien test `contains('NP') ⇒ désordre` le classait à tort ;
///  • les Bonus avant les variantes principales — « e-Bonus » ne contient ni
///    « ordre » ni « désordre », mais « e-Quinté+ … » pourrait piéger ;
///  • « désordre » avant « ordre » par sûreté (aucun libelle mesuré ne
///    contient les deux, mais l'ordre de test doit être déterministe).
VarianteRapport varianteDepuisLibelle(String libelle) {
  final l = libelle.toLowerCase().trim();
  if (l.isEmpty) return VarianteRapport.illisible;

  // 1. Rapports de non-partant : « … 1 NP », « … 2 NP ».
  if (RegExp(r'\b[12]\s*np\b').hasMatch(l)) return VarianteRapport.nonPartant;

  // 2. Bonus spécifiques.
  if (l.contains('bonus 4sur5') || l.contains('bonus 4 sur 5')) {
    return VarianteRapport.bonus4sur5;
  }
  if (l.contains('bonus 3')) return VarianteRapport.bonus3;
  if (l.contains('bonus')) return VarianteRapport.bonusQuarte;

  // 3. Variantes principales.
  if (l.contains('désordre') || l.contains('desordre')) {
    return VarianteRapport.desordre;
  }
  if (l.contains('ordre')) return VarianteRapport.ordre;

  // 4. Libelle reconnu mais sans notion d'ordre (Simple, Couplé Gagnant…).
  return VarianteRapport.sansVariante;
}
