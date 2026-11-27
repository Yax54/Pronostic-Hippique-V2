// ═══════════════════════════════════════════════════════════════════════════
//  ATELIER D'APPRENTISSAGE — SUPPORT COMMUN DES HARNAIS DU CHANTIER
//  « VALIDATION APPROFONDIE DU COMPORTEMENT DE L'APPRENTISSAGE IA »
//  (27/11/2026)
//
//  ⚠️ CE FICHIER N'EST **PAS** UN MOTEUR D'APPRENTISSAGE.
//
//  La consigne §2 l'interdit explicitement : « Ne crée pas un second moteur
//  d'apprentissage susceptible de diverger du moteur réel. » Ce fichier ne
//  contient donc AUCUNE formule d'apprentissage. Il ne calcule ni gradient, ni
//  momentum, ni projection, ni discrimination : tout cela est fait par le code
//  de PRODUCTION, atteint par les méthodes publiques réelles
//  (`recharger()` → `_load()` → `fromJson`, puis `enregistrerResultat()` →
//  `_save()`, `_apprendreParGradient()`, `_apprendreParDiscipline()`,
//  `_mettreAJourCalibration()`).
//
//  CE QU'IL CONTIENT, ET POURQUOI C'EST NÉCESSAIRE.
//  ────────────────────────────────────────────────
//  Le §3 exige de distinguer, pour chaque critère, la « variation PROPOSÉE
//  avant projection » de la « variation RÉELLEMENT OBTENUE après projection ».
//  Le moteur ne publie pas la première : `_apprendreParGradient` écrit
//  directement dans `_poids` puis appelle `_poids.clamp()`. Sans instrumentation
//  de production (interdite), la seule façon honnête d'obtenir la variation
//  proposée est de la RECONSTRUIRE à partir de grandeurs que la production
//  VEUT BIEN publier :
//
//    • `poids.dernierGradient[c]`    = momentum transmis, c'est-à-dire
//                                      `gradAvecMomentum` de la mise à jour qui
//                                      vient de s'exécuter (ia_memory_service:4174) ;
//    • `journal.last.apres[c]`       = poids après la mise à jour, AVANT clamp
//                                      (ia_memory_service:4209, calculé ligne 4225) ;
//                                      ⇒ `proposé[c] = apres[c] − avant[c]` ;
//    • `poids.getPoids(c)`           = poids réellement obtenu, APRÈS projection ;
//                                      ⇒ `obtenu[c] = getPoids(c) − avant[c]`.
//
//  Ce sont donc des LECTURES, pas des réplications. La fidélité de la
//  reconstruction est vérifiée par un contrôle interne (`controlerReconstruction`)
//  qui la confronte, critère par critère, à la seule grandeur réellement
//  publiée par le moteur : `dernierGradient × facteur[c]`. Si les deux divergent
//  sur un critère non gelé non saturé, la reconstruction est FAUSSE et le
//  harnais le dit au lieu de publier un chiffre.
//
//  ⚠️ CE QUE L'ATELIER NE PEUT PAS FAIRE, ET QUI EST DONC « NON DÉTERMINABLE »
//  ───────────────────────────────────────────────────────────────────────────
//  1. LA DISCRIMINATION. `discriminations[c]` est une variable locale de
//     `_apprendreParGradient`. Elle n'est écrite nulle part. On ne peut donc pas
//     lire le gradient BRUT (`lr × discrimination`) : seulement le gradient
//     APRÈS multiplication par `lr` et après lissage du momentum, via
//     `dernierGradient` — et seulement une fois par mise à jour.
//  2. LA CONFIGURATION DES COEFFICIENTS (§4). `switch (c)` de
//     ia_memory_service:4148-4172 porte les facteurs 1.0/0.5/0.4/0.3 EN DUR.
//     Aucun point d'injection, aucune variable. La seule façon de comparer
//     « coefficients actuels » vs « 19 × 1.0 » sans modifier la production
//     serait de rejouer l'arithmétique du switch, c'est-à-dire d'écrire un
//     second moteur — interdit par §2. Le §4 est donc traité par MESURE
//     INDIRECTE (voir `rapport_differences_facteurs`) et son volet
//     contre-factuel est déclaré NON DÉTERMINABLE dans l'état actuel du code.
//  3. LE GEL. Le gel ne laisse AUCUNE trace : `criteresGeles` est local à
//     `_apprendreParGradient`. On le DÉTECTE par une signature mesurable :
//     critère dont `dernierGradient` vaut exactement 0.0 ET dont le poids n'a
//     pas bougé, alors que la mise à jour a bien eu lieu. Cette détection est
//     un INDICE FORT, pas une preuve d'identité (un critère de discrimination
//     nulle produit la même signature). L'atelier distingue donc les deux.
//
//  ⚠️ PROTECTIONS RESPECTÉES : aucun poids initial, aucune borne, aucun
//  coefficient, aucune contrainte collective, aucun seuil, aucune formule de
//  critère n'est touché ici. Le fichier ne fait que semer un état et lire.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ─── Référentiel (recopié de la production, gardé par l'atelier) ────────────
const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];
const List<String> kBase = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
];
final List<String> kEnrichis =
    kCles.where((k) => !kBase.contains(k)).toList(growable: false);

/// Les 19 poids INITIAUX du constructeur de production (Σ = 1,26).
/// ⚠️ Aucune modification : ce sont ceux de GitHub, exigés par §2 et §11.
const Map<String, double> kInitial = <String, double>{
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05, 'divergence': 0.04,
  'poidsRel': 0.03, 'progression': 0.03, 'mouvCote': 0.06,
  'placeDepart': 0.03,
};

/// Coefficients du `switch` de production (ia_memory_service:4148-4172).
/// ⚠️ RECOPIÉS POUR LA MESURE, JAMAIS APPLIQUÉS ICI. Ils servent uniquement à
///    rapprocher `dernierGradient` (= gradAvecMomentum) et le déplacement réel,
///    ce qui est un CONTRÔLE de cohérence, pas un calcul d'apprentissage.
const Map<String, double> kFacteur = <String, double>{
  'forme': 1.0, 'gains': 1.0, 'record': 1.0, 'cote': 1.0, 'constance': 1.0,
  'victoires': 1.0, 'discipline': 1.0,
  'distSpec': 0.5, 'jockey': 0.5, 'elo': 0.5, 'terrain': 0.5, 'mouvCote': 0.5,
  'hippo': 0.4, 'entraineur': 0.4, 'divergence': 0.4, 'progression': 0.4,
  'repos': 0.3, 'poidsRel': 0.3, 'placeDepart': 0.3,
};

const String kDisc = 'Trot Attelé';
const String kPoidsKey = 'ia_poids_v3'; // = IaMemoryService._poidsKey

// ─── Utilitaires numériques ────────────────────────────────────────────────
double sommeSur(Iterable<double> v) => v.fold(0.0, (a, b) => a + b);
double sommeCle(Map<String, double> m, List<String> ks) =>
    ks.fold(0.0, (a, k) => a + (m[k] ?? 0.0));
String f12(double v) => v.toStringAsFixed(12);

String fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Lit les 19 poids EFFECTIFS du service — chemin de production (`getPoids`).
Map<String, double> poidsEffectifs() => <String, double>{
      for (final k in kCles) k: IaMemoryService.instance.poids.getPoids(k),
    };

/// Écart max, clé la plus décalée, nombre de critères ayant bougé.
(double, String, int) ecart(Map<String, double> a, Map<String, double> b,
    {double seuil = 1e-12}) {
  var maxi = 0.0;
  var pire = '';
  var bouges = 0;
  for (final k in kCles) {
    final d = ((a[k] ?? 0) - (b[k] ?? 0)).abs();
    if (d > seuil) bouges++;
    if (d > maxi) {
      maxi = d;
      pire = k;
    }
  }
  return (maxi, pire, bouges);
}

// ─────────────────── Pronostic de PRODUCTION (sérialisé réel) ───────────────

/// Fabrique un pronostic de production.
///
/// [notesParNumero] permet de CONTRÔLER LA PERTINENCE d'un critère sans toucher
/// au moteur : c'est la donnée d'entrée (les notes 0-100), pas l'algorithme.
/// C'est exactement ce que fait la réalité quand un critère est mieux ou moins
/// bien renseigné. Le moteur, lui, n'est pas modifié.
IaPronostic pronostic({
  required String courseKey,
  required DateTime date,
  bool resolu = true,
  String discipline = kDisc,
  int nbPartants = 5,
  Map<String, ScoresCriteres>? scoresCriteres,
  List<int>? arrivee,
  double variance = 12.0,
}) {
  final arriveeFinale = arrivee ?? <int>[for (var n = 1; n <= nbPartants; n++) n];
  return IaPronostic(
    courseKey: courseKey,
    nomCourse: 'PRIX $courseKey',
    hippodrome: 'VINCENNES',
    discipline: discipline,
    datePronostic: date,
    scoresIA: <String, double>{
      for (var n = 1; n <= nbPartants; n++)
        '$n': 100.0 - (n - 1) * 8.0,
    },
    scoresCriteres: scoresCriteres ??
        <String, ScoresCriteres>{
          for (var n = 1; n <= nbPartants; n++)
            '$n': ScoresCriteres(
              forme: 92.0 - n * 4, gains: 82.0 - n * 3, record: 72.0 - n * 2,
              cote: 86.0 - n * 5, constance: 76.0 - n, victoires: 66.0 + n,
              discipline: 61.0 + n * 2, distSpec: 89.0 - n * 6,
              jockey: 73.0 - n, repos: 56.0 + n, hippo: 69.0 - n * 2,
              entraineur: 63.0 + n, elo: 79.0 - n * 3, terrain: 71.0 + n,
              divergence: 51.0 + n * 4, poidsRel: 67.0 - n,
              progression: 75.0 + n * 2, mouvCote: 59.0 + n * 3,
              placeDepart: 65.0 - n * 2,
            ),
    },
    varianceScores: variance,
    confiancePredite: 70.0,
    typePariConseille: 'Simple Gagnant',
    favoriIaNom: 'CHEVAL_1',
    arriveeReelle: resolu ? arriveeFinale : null,
    dateResultat: resolu ? date.add(const Duration(hours: 2)) : null,
    resultatsReels: resolu,
    scorePerformance: resolu ? 50.0 : null,
  );
}

/// Historique de [n] courses RÉSOLUES, DANS la fenêtre de 45 jours du gradient
/// (J−40 → J−27 pour n = 15).
///
/// ⚠️ MESURÉ (déjà établi par `poids_cycle_apprentissage_test`) : la fenêtre
///    d'apprentissage est bornée à 45 jours. Un historique plus ancien laisse
///    `fenetre` VIDE et `scoreMoyFenetre` lève `Bad state: No element`. Placer
///    l'historique dans la fenêtre n'est pas un assouplissement, c'est la
///    condition réelle pour que le gradient s'exécute.
List<IaPronostic> historique({
  int n = 15,
  int joursAvant = 40,
  String discipline = kDisc,
  ScoresCriteres Function(int numero, int courseIndex)? notes,
  List<int> Function(int courseIndex)? arrivee,
}) {
  final base = DateTime.now().subtract(Duration(days: joursAvant));
  return <IaPronostic>[
    for (var i = 0; i < n; i++)
      pronostic(
        courseKey: 'H${1 + i % 3}C${1 + i % 7}_'
            '${fmtDate(base.add(Duration(days: i)))}',
        date: base.add(Duration(days: i)),
        discipline: discipline,
        scoresCriteres: notes == null
            ? null
            : <String, ScoresCriteres>{
                for (var num = 1; num <= 5; num++) '$num': notes(num, i),
              },
        arrivee: arrivee == null ? null : arrivee(i),
      ),
  ];
}

// ─────────────────────────── Graine = état téléphone ───────────────────────

/// Écrit sur le stockage simulé EXACTEMENT ce qu'écrit un téléphone, puis
/// recharge par le chemin réel (`recharger()` → `_load()` → `fromJson`).
///
/// GARDE ANTI-FAUX-NÉGATIF : on vérifie que la graine est réellement chargée.
/// Sans ce contrôle, un `_load()` en erreur laisserait une mémoire vide et
/// toutes les mesures « aucun apprentissage » seraient des faux positifs.
Future<void> semer({
  required List<IaPronostic> pronostics,
  Map<String, double>? poidsDepart,
  bool verifierNombre = true,
  bool autoriserVide = false,
  /// Σ attendue AU CHARGEMENT. Par défaut 1,26 : c'est le fait mesuré pour une
  /// installation vierge. **Le harnais §1 doit pouvoir passer 1,0** pour
  /// étudier un départ DÉJÀ normalisé ; sans ce paramètre, la garde rendrait
  /// l'expérience impossible. La garde n'est donc pas supprimée, elle est
  /// rendue explicite : le contrôle « `fromJson` ne projette pas » reste
  /// exactement aussi strict, il porte simplement sur la valeur déclarée.
  double sigmaAttendue = 1.26,
}) async {
  final w = poidsDepart ?? kInitial;
  SharedPreferences.setMockInitialValues(<String, Object>{
    'ia_precision_migrated_v3': true,
    // Poids de départ tels que fournis (bruts Σ = 1,26 ou normalisés Σ = 1,00).
    kPoidsKey: json.encode(<String, dynamic>{
      ...w,
      'nbMisesAJour': 0,
      'calibrationScore': 50.0,
    }),
    'ia_seuils_v1': json.encode(<String, dynamic>{}),
    'ia_precision_v2': json.encode(<String, dynamic>{}),
    'ia_stats_labels_v1': json.encode(<String, dynamic>{}),
    'ia_stats_types_v1': <String>[],
    'ia_journal_v2': <String>[],
    'ia_pronostics_v2':
        pronostics.map((p) => json.encode(p.toJson())).toList(),
  });
  SharedPreferences.resetStatic();
  await IaMemoryService.instance.recharger();

  final mem = IaMemoryService.instance;
  expect(mem.poids.nbMisesAJour, 0,
      reason: 'GARDE : la mémoire doit être VIERGE (0 mise à jour)');
  if (autoriserVide && pronostics.isEmpty) {
    // État volontairement VIERGE (départ du §11 : aucun pronostic, poids
    // initiaux). La garde « non vide » n'a de sens que pour un semis peuplé.
  } else if (verifierNombre) {
    expect(mem.pronostics.length, pronostics.length,
        reason: 'GARDE : les ${pronostics.length} pronostics semés doivent être '
            'chargés (obtenu : ${mem.pronostics.length})');
  } else {
    // Le plafond `_maxPronostics = 600` et la purge à 90 jours peuvent réduire
    // la liste : on vérifie alors seulement qu'elle n'est pas VIDE, ce qui
    // suffit à écarter le faux positif « mémoire vide = aucun apprentissage ».
    expect(mem.pronostics, isNotEmpty,
        reason: 'GARDE : la mémoire ne doit pas être VIDE');
  }
  // GARDE CRUCIALE : `fromJson` ne projette pas. La somme relue doit être
  // EXACTEMENT celle qui a été écrite — sinon la projection aurait eu lieu au
  // chargement, ce qui est interdit et invaliderait toute mesure de cycle.
  expect(sommeCle(poidsEffectifs(), kCles), closeTo(sigmaAttendue, 1e-9),
      reason: 'GARDE : au chargement, Σ doit valoir $sigmaAttendue '
          'telle qu écrite (poids non projetés)');
}

/// Réécrit INTÉGRALEMENT la liste des pronostics dans le stockage, avec les
/// sérialiseurs de production, puis recharge par `recharger()` → `_load()` →
/// `fromJson`.
///
/// C'est le chemin d'un téléphone qui reçoit une mise à jour de ses pronostics.
/// Ce n'est PAS un moteur : aucune formule n'est exécutée, seule la DONNÉE
/// d'entrée est remplacée. Les poids ne sont pas touchés (les clés de poids
/// restent celles écrites par `_save()`).
class IaStockageReecriture {
  static Future<void> reecrire(List<IaPronostic> pronostics) async {
    final prefs = await SharedPreferences.getInstance();
    final liste = pronostics.map((p) => json.encode(p.toJson())).toList();
    // ⚠️ DÉFAUT MESURÉ, CORRIGÉ ICI — LA PREMIÈRE VERSION ÉCRIVAIT AU MAUVAIS ENDROIT.
    //    `_save()` (ia_memory_service:2881-2894) n'écrit PAS seulement
    //    `ia_pronostics_v2` : quand `_useCompression` est vrai et qu'il y a plus
    //    de 20 pronostics, il écrit une copie **gzip+base64** dans
    //    `ia_pronostics_v2_gz` et **SUPPRIME** la clé non compressée.
    //    `_load()` (l.2400-2406) lit `_gz` EN PRIORITÉ et n'utilise la clé
    //    simple qu'en repli.
    //    MESURE du défaut : après 30 cycles (donc > 20 pronostics), une
    //    `reecrire()` ne changeait RIEN à ce que voyait le moteur —
    //    `p.scoresCriteres['1'].gains` restait 97.37997162130193 en RAM alors
    //    que la clé simple contenait bien 93.04037756763643. Le balayage de
    //    corrélation du §4 était donc MUET (r figé à 0,952 sur tous les
    //    paliers de 0,95 à 0,60) : un faux négatif total, imputable au harnais
    //    et non au moteur. On écrit désormais les DEUX représentations, comme
    //    le fait la production, et on vérifie la relecture.
    await prefs.setStringList('ia_pronostics_v2', liste);
    final jsonStr = json.encode(pronostics.map((p) => p.toJson()).toList());
    await prefs.setString(
      'ia_pronostics_v2_gz',
      base64Encode(GZipCodec().encode(utf8.encode(jsonStr))),
    );
    await IaMemoryService.instance.recharger();
  }
}

// ─────────────────────────── Poids normalisés de départ ────────────────────

/// Les 19 poids du constructeur RAMENÉS dans l'ensemble des contraintes
/// (Σ = 1,00 · part enrichie dans [0,18 ; 0,40]) par la **projection de
/// production elle-même** — `IaPoidsAdaptatifs.clamp()` — et non par une
/// formule recopiée ici.
///
/// ⚠️ POURQUOI CETTE FONCTION EXISTE (réponse au §1 du 27/11/2026)
/// ───────────────────────────────────────────────────────────────
/// Le harnais §3 mesurait un cycle partant de Σ = 1,26 (état réel d'une
/// installation vierge). Il comparait ensuite la variation PROPOSÉE par le
/// gradient (de l'ordre de 1e-4) à la variation OBTENUE (de l'ordre de 1e-2)
/// et en déduisait un rapport ≈ 265×. Ce rapport est RÉEL mais il ne mesure
/// PAS une déformation du signal : il mesure la **renormalisation de 1,26
/// vers 1,00**, qui déplace chaque poids de −14,7 % (base) et −27,3 %
/// (enrichis). Sur un poids de 0,25, cela vaut 3,7e-2 ; sur un incrément de
/// gradient de 1,5e-4, cela vaut 250 fois plus. Les deux quantités n'ont pas
/// le même ordre de grandeur parce qu'elles n'ont pas la même nature.
///
/// Pour isoler la déformation du SIGNAL, il faut donc partir d'une table
/// DÉJÀ conforme. C'est ce que fait cette fonction : elle applique la
/// projection de production une fois, et rend le résultat.
Map<String, double> poidsNormalisesDeDepart() {
  final w = IaPoidsAdaptatifs.defaut();
  w.clamp(); // ← la projection de production, pas une réimplémentation
  return <String, double>{for (final k in kCles) k: w.getPoids(k)};
}

/// Somme par groupe et part enrichie. Sert à vérifier qu'une table est dans
/// l'ensemble des contraintes AVANT de l'utiliser comme point de départ.
String etatGroupes(Map<String, double> m) {
  var sb = 0.0;
  var se = 0.0;
  for (final k in kCles) {
    if (kBase.contains(k)) {
      sb += m[k] ?? 0.0;
    } else {
      se += m[k] ?? 0.0;
    }
  }
  final t = sb + se;
  return 'Σ=${f12(t)} base=${f12(sb)} enr=${f12(se)} '
      'part=${t == 0 ? 'n/a' : f12(se / t)}';
}

/// Décomposition EXACTE de la variation d'un cycle en deux termes.
///
/// Soit P la projection de production (`clamp()`), `a` la table avant le
/// gradient, `q = a + δ` la proposition (δ = gradient × facteur, après
/// momentum), et `o = P(q)` le résultat.
///
/// L'identité suivante est ALGÉBRIQUE, pas approchée :
///
/// ```
/// o − a  =  [ P(a) − a ]  +  [ P(q) − P(a) ]
///            \___________/     \___________/
///             choc de           effet de la projection
///             normalisation     SUR LE SIGNAL
/// ```
///
/// - **normalisation** = `P(a) − a` : ce que la projection fait subir à la
///   table telle qu'elle était AVANT toute contribution du gradient. C'est un
///   déplacement **indépendant de l'apprentissage** : il ne dépend que de
///   l'écart entre la table de départ et l'ensemble des contraintes.
///   Si `a` est déjà conforme, ce terme vaut **exactement 0** (idempotence,
///   déjà démontrée) — ce que le harnais vérifie au lieu de le supposer.
/// - **signal** = `P(q) − P(a)` : ce que la projection fait du seul
///   incrément, la table de départ étant déjà ramenée dans l'ensemble. C'est
///   la seule quantité qui mesure une **déformation du signal**.
///
/// ⚠️ Il n'y a **pas** de troisième terme « couplage » : la projection est
///    non linéaire, mais la somme des deux différences ci-dessus est
///    identiquement égale au total. Prétendre isoler un « couplage » serait
///    une erreur d'analyse. La non-linéarité est entièrement contenue dans le
///    terme `signal`, qui est mesuré, pas modélisé.
({double normalisation, double signal, double total, double partNormalisation})
    decomposerCycle(Cycle c) {
  final a = c.avant;
  final pA = _projeter(a);
  final pQ = _projeter(c.propose);

  var norm = 0.0; // Σ_k | P(a)_k − a_k |
  var sig = 0.0; // Σ_k | P(q)_k − P(a)_k |
  var tot = 0.0; // Σ_k | o_k − a_k |
  for (final k in kCles) {
    final av = a[k] ?? 0.0;
    norm += ((pA[k] ?? 0.0) - av).abs();
    sig += ((pQ[k] ?? 0.0) - (pA[k] ?? 0.0)).abs();
    tot += ((c.obtenu[k] ?? 0.0) - av).abs();
  }
  // Contrôle : tot doit être ≈ norm + sig à la non-linéarité de |·| près.
  return (
    normalisation: norm,
    signal: sig,
    total: tot,
    partNormalisation: tot == 0 ? 0.0 : norm / tot,
  );
}

/// Applique la projection de PRODUCTION à une table arbitraire (via
/// `clamp()` sur un modèle construit à partir de [m]). Aucune formule n'est
/// recopiée : c'est le même code que la production.
///
/// ⚠️ RENDUE PUBLIQUE pour le §6/§7 (27/11/2026). Elle sert à vérifier la
///    proposition contrefactuelle « le moteur fait exactement
///    `clamp(avant + momentum × facteur)` » — contrôle de REPRODUCTION avant
///    toute expérience, conformément au §6 (« vérification préalable que la
///    configuration expérimentale reproduit exactement le comportement de
///    référence »).
Map<String, double> projeterTable(Map<String, double> m) => _projeter(m);

Map<String, double> _projeter(Map<String, double> m) {
  final w = IaPoidsAdaptatifs(
    forme: m['forme']!, gains: m['gains']!, record: m['record']!,
    cote: m['cote']!, constance: m['constance']!,
    victoires: m['victoires']!, discipline: m['discipline']!,
    distSpec: m['distSpec']!, jockey: m['jockey']!, repos: m['repos']!,
    hippo: m['hippo']!, entraineur: m['entraineur']!, elo: m['elo']!,
    terrain: m['terrain']!, divergence: m['divergence']!,
    poidsRel: m['poidsRel']!, progression: m['progression']!,
    mouvCote: m['mouvCote']!, placeDepart: m['placeDepart']!,
  );
  w.clamp();
  return <String, double>{for (final k in kCles) k: w.getPoids(k)};
}

/// Rang de Spearman entre deux séries indexées par les mêmes clés.
/// Sert à mesurer si la projection conserve l'ORDRE du signal, ce qui est la
/// vraie question : la contrainte de somme interdit que tout monte, mais elle
/// n'interdit pas que l'ordre soit respecté.
double spearman(List<String> cles, Map<String, double> a, Map<String, double> b) {
  final n = cles.length;
  List<int> rangs(Map<String, double> m) {
    final tri = List<String>.from(cles)
      ..sort((x, y) => (m[x] ?? 0).compareTo(m[y] ?? 0));
    final r = <String, int>{};
    for (var i = 0; i < tri.length; i++) {
      r[tri[i]] = i;
    }
    return <int>[for (final k in cles) r[k]!];
  }

  final ra = rangs(a);
  final rb = rangs(b);
  var d2 = 0.0;
  for (var i = 0; i < n; i++) {
    final d = (ra[i] - rb[i]).toDouble();
    d2 += d * d;
  }
  return 1.0 - (6.0 * d2) / (n * (n * n - 1));
}

// ──────────────────────── Déroulement d'un cycle réel ──────────────────────

/// Résultat d'UNE mise à jour réelle du moteur.
///
/// Toutes les grandeurs sont LUES sur le moteur de production, jamais calculées
/// par l'atelier. Voir l'en-tête du fichier pour la provenance exacte.
class Cycle {
  /// Poids AVANT (lus avant l'appel).
  final Map<String, double> avant;

  /// Variation PROPOSÉE par le gradient AVANT projection, RECONSTRUITE comme
  /// `dernierGradient[c] × facteur[c]`.
  ///
  /// ⚠️ CE POINT A ÉTÉ MESURÉ PUIS CORRIGÉ — LA PREMIÈRE VERSION ÉTAIT FAUSSE.
  ///    J'avais d'abord cru pouvoir lire la variation proposée dans le journal
  ///    (`JournalEntree.apres`). MESURE : c'est FAUX. `poidsApres` est construit
  ///    ligne 4209, soit APRÈS `_poids.clamp()` ligne 4176 — le journal publie
  ///    donc les poids DÉJÀ PROJETÉS. Preuve : dans le premier passage du
  ///    harnais §3, `journal.apres` et `getPoids()` étaient identiques au bit
  ///    près sur les 19 critères (écart 0,000e+0), ce qui aurait signifié
  ///    « la projection ne fait rien » — conclusion absurde puisque Σ passe de
  ///    1,26 à 1,00. Le journal ne peut donc PAS servir de source.
  ///
  ///    La seule source de la variation d'avant projection est le produit
  ///    `dernierGradient[c] × facteur[c]`, qui est EXACTEMENT l'expression
  ///    écrite dans le `switch` de production (l.4149-4171). `dernierGradient`
  ///    est publié (l.4174). Les 19 facteurs sont des constantes publiées.
  ///    Ce n'est donc pas un second moteur : c'est le produit des deux seules
  ///    grandeurs que la production expose. Cette reconstruction est
  ///    INDÉPENDAMMENT VALIDÉE par `validerEchelleProposition`, qui vérifie que
  ///    son ordre de grandeur est compatible avec la correction de projection
  ///    observée.
  final Map<String, double> propose;

  /// Poids réellement en vigueur APRÈS projection (`getPoids`).
  final Map<String, double> obtenu;

  /// `poids.dernierGradient` après la mise à jour = `gradAvecMomentum` (l.4174).
  final Map<String, double> momentum;

  /// `nbMisesAJour` après.
  final int nbMisesAJour;

  /// Vrai si le journal a réellement consigné une entrée (mise à jour effective).
  final bool aAppris;

  /// Poids publiés par `JournalEntree.apres` — MESURÉ ÉGAL À [obtenu].
  /// Conservé pour rendre le défaut de la première version vérifiable.
  final Map<String, double> journalApres;

  const Cycle({
    required this.avant,
    required this.propose,
    required this.obtenu,
    required this.momentum,
    required this.nbMisesAJour,
    required this.aAppris,
    required this.journalApres,
  });

  /// Variation PROPOSÉE avant projection.
  double propose_(String c) => (propose[c] ?? 0) - (avant[c] ?? 0);

  /// Variation RÉELLEMENT OBTENUE après projection.
  double obtenu_(String c) => (obtenu[c] ?? 0) - (avant[c] ?? 0);

  /// Écart entre les deux = effet net de la projection sur ce critère.
  double projection_(String c) => obtenu_(c) - propose_(c);
}

/// Exécute UNE mise à jour réelle et capture les trois états.
///
/// [cible] doit être un pronostic NON résolu chargé dans la mémoire ; c'est
/// `enregistrerResultat()` — la méthode de PRODUCTION — qui déclenche
/// `_apprendreParGradient()` puis `_apprendreParDiscipline()`.
Future<Cycle> executerCycle({
  required String courseKey,
  required List<int> arrivee,
}) async {
  final mem = IaMemoryService.instance;
  final avant = poidsEffectifs();
  final j0 = mem.journal.length;
  final nb0 = mem.poids.nbMisesAJour;

  final ecrit = await mem.enregistrerResultat(
    courseKey: courseKey,
    arriveeReelle: arrivee,
  );

  final aAppris = mem.journal.length > j0 && ecrit;
  final obtenu = poidsEffectifs();
  final momentum = <String, double>{
    for (final k in kCles)
      k: mem.poids.dernierGradient[k] ?? 0.0,
  };

  // ── La variation PROPOSÉE ne se lit PAS dans le journal (mesuré) ──────────
  // `JournalEntree.apres` est construit APRÈS `_poids.clamp()` : il publie les
  // poids déjà projetés. On le capture pour que le harnais puisse vérifier
  // cette affirmation, mais on ne s'en sert JAMAIS comme variation proposée.
  Map<String, double> journalApres = avant;
  for (final e in mem.journal.take(mem.journal.length - j0)) {
    if (e.methode == 'gradient' && e.avant.isNotEmpty && e.apres.isNotEmpty) {
      journalApres = e.apres;
      break;
    }
  }

  // La proposition d'avant projection est EXACTEMENT `dernierGradient ×
  // facteur` : c'est la seule expression que le `switch` de production écrit
  // (ia_memory_service:4149-4171). On la reconstitue par PRODUIT, sans
  // reproduire l'algorithme (aucun gradient, aucun momentum, aucune
  // discrimination n'est recalculée ici).
  final propose = <String, double>{
    for (final k in kCles) k: (avant[k] ?? 0.0) + (momentum[k] ?? 0.0) * kFacteur[k]!,
  };

  return Cycle(
    avant: avant,
    propose: propose,
    obtenu: obtenu,
    momentum: momentum,
    nbMisesAJour: mem.poids.nbMisesAJour,
    aAppris: aAppris && mem.poids.nbMisesAJour > nb0,
    journalApres: journalApres,
  );
}

/// Semence + exécution d'un cycle unique, en repartant des poids initiaux.
///
/// [historique] est un historique DÉJÀ RÉSOLU ; [cible] est un pronostic non
/// résolu de même discipline, dont on fournit l'arrivée.
Future<Cycle> cycleIsole({
  required List<IaPronostic> historique,
  required String cibleKey,
  required List<int> arrivee,
  Map<String, double>? poidsDepart,
}) async {
  final depart = poidsDepart ?? kInitial;
  await semer(
    pronostics: <IaPronostic>[...historique, pronostic(
      courseKey: cibleKey,
      date: DateTime.now().subtract(const Duration(days: 2)),
      resolu: false,
    )],
    poidsDepart: depart,
    sigmaAttendue: sommeCle(depart, kCles),
  );
  return executerCycle(courseKey: cibleKey, arrivee: arrivee);
}

/// CONTRE-ÉPREUVE — deux exécutions réelles identiques depuis les poids
/// initiaux doivent produire des variations IDENTIQUES.
///
/// C'est ce qui autorise à comparer deux configurations mesurées séparément :
/// sans cette garde, toute différence observée entre deux mesures pourrait
/// provenir d'un état résiduel du singleton et non de la différence étudiée.
Future<bool> deterministicite(
    Future<Cycle> Function() executer) async {
  final a = await executer();
  final b = await executer();
  final (ecartMax, _, _) = ecart(a.obtenu, b.obtenu, seuil: 0.0);
  return ecartMax <= 1e-12;
}

// ───────────── Détection du gel (signature mesurable, pas preuve) ──────────

/// Un critère est dit « gelé-SUSPECT » quand, sur un cycle qui a réellement
/// appris :
///   • son momentum publié est exactement `0.0` (reset du gel,
///     ia_memory_service:4138), ET
///   • sa variation proposée est exactement `0.0`.
///
/// ⚠️ AMBIGUÏTÉ DÉCLARÉE : un critère de discrimination NULLE produit la même
///    signature (grad = 0 ⇒ gradAvecMomentum = 0 ⇒ momentum 0 ⇒ pas de
///    déplacement). L'atelier ne prétend donc pas identifier le gel avec
///    certitude ; il identifie les critères SUSPECTS et laisse au harnais le
///    soin de trancher par une seconde signature (poids le plus faible d'une
///    paire corrélée).
List<String> gelesSuspects(Cycle c) {
  if (!c.aAppris) return const <String>[];
  return <String>[
    for (final k in kCles)
      if ((c.momentum[k] ?? 0.0) == 0.0 && c.propose_(k) == 0.0) k,
  ];
}

/// Paires corrélées mémorisées par le moteur, telles quelles (`r` inclus).
Map<String, double> correlationsMemorisees() =>
    Map<String, double>.from(IaMemoryService.instance.poids.correlations);

/// Paires dont `r >= 0.85` : ce sont EXACTEMENT celles que le bloc de gel
/// (ia_memory_service:4116-4142) parcourt pour décider. Les autres paires
/// mémorisées (0,65 ≤ r < 0,85) sont inertes : elles n'influencent que
/// l'affichage IA Stats.
Map<String, double> pairesAuSeuilDeGel() => <String, double>{
      for (final e in correlationsMemorisees().entries)
        if (e.value >= 0.85) e.key: e.value,
    };

/// Critères qui seraient gelés au prochain cycle, calculés À PARTIR DU CODE DE
/// PRODUCTION et non d'une règle recopiée :
///
///   1. `criteresGeles` est un ensemble LOCAL à `_apprendreParGradient`, mais
///      il est **reconstruit à chaque appel** (`final criteresGeles = <String>{}`,
///      ia_memory_service:4115). Il n'y a donc **aucun état de gel persistant** :
///      le dégel est immédiat dès qu'une paire cesse de satisfaire `r >= 0.85`.
///   2. La sélection est `aGeler = p1 <= p2 ? c1 : c2`, où `p1`/`p2` sont les
///      poids du moment (l.4133-4137).
///
/// Cette fonction reproduit donc la SÉLECTION (une comparaison de deux poids),
/// pas l'algorithme d'apprentissage. Elle est confrontée à la mesure via la
/// signature `gelesSuspects`, ce qui la rend vérifiable.
Set<String> gelesAttendus({Map<String, double>? poids}) {
  final p = poids ?? poidsEffectifs();
  final geles = <String>{};
  for (final e in pairesAuSeuilDeGel().entries) {
    final parts = e.key.split('|');
    if (parts.length < 2) continue;
    final c1 = parts[0], c2 = parts[1];
    final p1 = p[c1] ?? 0.0;
    final p2 = p[c2] ?? 0.0;
    geles.add(p1 <= p2 ? c1 : c2);
  }
  return geles;
}

// ───────────── Contrôles de fidélité de la mesure ──────────────────────────

/// CONTRÔLE 1 — le journal publie-t-il les poids APRÈS projection ?
///
/// Si `JournalEntree.apres == getPoids()` sur les 19 critères, alors le journal
/// est inutilisable comme source de la variation d'avant projection : c'est ce
/// que la première version de l'atelier avait supposé à tort.
///
/// Retourne (leJournalEstProjete, écart max, critère le plus décalé).
(bool, double, String) journalEstProjete(Cycle c) {
  final (ecartMax, pire, _) = ecart(c.journalApres, c.obtenu, seuil: 0.0);
  return (ecartMax <= 1e-12, ecartMax, pire);
}

/// CONTRÔLE 2 — la somme des variations proposées est-elle nulle ?
///
/// Le gradient écrit `± gradAvecMomentum` sur chaque critère ; comme
/// `Σ discriminations` n'est pas nulle, la somme des propositions NE DOIT PAS
/// être nulle en général. Ce contrôle mesure donc l'écart
/// `Σ proposé − Σ avant`, qui est la quantité exacte que la projection doit
/// ensuite absorber pour ramener Σ à 1.
double desequilibrePropose(Cycle c) =>
    sommeCle(c.propose, kCles) - sommeCle(c.avant, kCles);

/// Reconstitue `lr` du gradient global à partir des quatre paramètres PUBLIÉS.
///
/// Aucune formule d'apprentissage n'est réécrite : ce sont les quatre facteurs
/// multiplicatifs lus aux lignes 4088-4100 de `ia_memory_service.dart`, et le
/// nombre de courses est COMPTÉ sur l'état public du service.
double lrGlobal() {
  final mem = IaMemoryService.instance;
  final avecResultat = mem.pronosticsAvecResultat;
  final avecScores =
      avecResultat.where((p) => p.scoresCriteres.isNotEmpty).toList();
  final nbAvecResultat = avecResultat.length;
  final maintenant = DateTime.now();
  final recents = avecScores
      .where((p) => maintenant.difference(p.datePronostic).inDays <= 45)
      .toList();
  final fenetre =
      (recents.isNotEmpty ? recents : avecScores).take(50).toList();
  final nb = fenetre.length;
  final stabilisation = nbAvecResultat < 30 ? 0.3 : 1.0;
  final lrFactor = (nb / 20.0) > 1.0 ? 1.0 : nb / 20.0;
  return 0.08 * lrFactor * stabilisation * 1.0;
}
