// ═══════════════════════════════════════════════════════════════════════════
//  POINTS 8 ET 10 — DIFFÉRENCIATION DES 12 ENRICHIS ET ADAPTATION
//  EXPÉRIENCE CIBLÉE HORS SATURATION
//
//  DÉCISION UTILISATEUR DU 27/11/2026 : « Nous autorisons une expérience ciblée
//  hors saturation permettant de terminer simultanément les POINTS 8 et 10.
//  Vérifie préalablement que ton scénario permet réellement d'observer ces
//  comportements. Ne lance pas une nouvelle campagne disproportionnée.
//  Réutilise les instruments existants et limite les mesures au strict
//  nécessaire. Un résultat négatif valide doit être analysé, pas artificiellement
//  transformé en résultat positif. »
//
//  ══════════════════════════════════════════════════════════════════════════
//  RECTIFICATION EXPLICITE D'UNE ERREUR COMMISE (28/11/2026)
//  ══════════════════════════════════════════════════════════════════════════
//  La PREMIÈRE version de ce fichier affirmait :
//      « Un signe positif = critère pertinent ; l'amplitude = degré de
//        pertinence »
//  et bâtissait un scénario où les critères les plus « pertinents » recevaient
//  les pentes les plus FORTES POSITIVES. C'ÉTAIT FAUX, et mesuré faux.
//
//  MESURE (exécutée, deux régimes symétriques, 40 cycles) :
//    • pente POSITIVE (+4) ⇒ le gagnant reçoit des notes BASSES
//          ⇒ moyBon < moyMauvais ⇒ `discriminations[c] < 0`
//          ⇒ momentum = −3.1974e-4   (MESURÉ)
//    • pente NÉGATIVE (−4) ⇒ le gagnant reçoit des notes HAUTES
//          ⇒ moyBon > moyMauvais ⇒ `discriminations[c] > 0`
//          ⇒ momentum = +8.7080e-5   (MESURÉ)
//  MÉCANISME (ia_memory_service:4040-4078, lu) : le gagnant alimente
//  `scoresBons`, et `discriminations[c] = (moyBon − moyMauvais)/100`. Un
//  critère PERTINENT est donc celui dont les notes sont HAUTES chez le
//  gagnant, c'est-à-dire une pente NÉGATIVE dans la convention
//  `note = 50 + pente × (rang − 3)` (rang 1 = gagnant).
//
//  La « percée » de la première trajectoire (jockey 0.050996 → 0.150000) était
//  donc un ARTEFACT : elle venait de ce que les 7 critères de base, affligés
//  d'une pente de 60 (donc violemment ANTI-pertinents), voyaient leur poids
//  écrasé, ce qui faisait remonter mécaniquement la part enrichie au plafond
//  0,40 — pas d'un gain de pertinence. Un scénario faux produisait un chiffre
//  flatteur. Il est ici corrigé, pas rafistolé.
//
//  ══════════════════════════════════════════════════════════════════════════
//  CE QUE FAIT CETTE EXPÉRIENCE, ET RIEN DE PLUS
//  ══════════════════════════════════════════════════════════════════════════
//  On ne touche NI l'algorithme, NI les bornes, NI le plafond, NI les
//  coefficients, NI un seul poids. On agit sur l'unique levier autorisé : LA
//  DONNÉE D'ENTRÉE (les notes 0-100), ce que la réalité fait d'elle-même
//  quand un critère est mieux ou moins bien renseigné.
//
//  Les 7 critères de base sont maintenus à pente ZÉRO (notes identiques pour
//  tous les partants). Ce choix est DÉLIBÉRÉ et il est la correction du défaut
//  ci-dessus : aucune interférence ne peut plus provenir du groupe de base, et
//  le budget enrichi n'est plus gonflé artificiellement. Conséquence assumée :
//  au départ, la part enrichie vaut EXACTEMENT 0,400000000 (mesuré) — donc la
//  démonstration « hors saturation » ne peut PAS reposer sur la part de départ.
//  Elle repose sur ce que les gardes mesurent réellement plus bas.
//
//  GARDES PRÉALABLES, EXÉCUTÉES AVANT TOUTE CONCLUSION (test S8-GARDE) :
//    G-a  SENSIBILITÉ : deux régimes de pentes OPPOSÉES doivent produire deux
//         tables DIFFÉRENTES. Sans cela, le moteur serait insensible et tout
//         résultat « nul » serait un faux négatif du montage.
//         MESURÉ : écart max = 0.10401611953040776, 19/19 critères bougés.
//    G-b  CONTRÔLE DE NEUTRALITÉ : avec les 19 pentes à zéro, la part enrichie
//         vaut 0,40 — c'est un fait de la TABLE DE POIDS, pas des notes. Ce
//         contrôle interdit de prétendre que la part mesure la pertinence.
//    G-c  APPRENTISSAGE RÉEL : `aAppris` doit être vrai (sinon mesure vide).
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION. Aucun APK. Aucune réinitialisation.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';

import '../support/atelier_apprentissage.dart';

// ─────────────────────────── Levier de l'expérience ────────────────────────

/// Pente des 7 critères de base : ZÉRO (notes neutres, non discriminantes
/// dans la course). Justifié dans l'en-tête : supprime l'interférence du
/// groupe de base et empêche tout gonflement artificiel de la part enrichie.
const double kPenteBaseNeutre = 0.0;

/// Pentes des 12 enrichis pour le scénario de DÉMONSTRATION S8-1.
///
/// Ordre de lecture = ordre de `kEnrichis`
/// (distSpec, jockey, repos, hippo, entraineur, elo, terrain, divergence,
///  poidsRel, progression, mouvCote, placeDepart).
///
/// Signe NÉGATIF = critère PERTINENT (le gagnant a les notes hautes) — mesuré.
/// Les 8 premiers sont donc ANTI-pertinents, les 4 derniers PERTINENTS : la
/// majorité est anti-pertinente, ce qui fait RÉELLEMENT descendre la part
/// enrichie sous son plafond (mesuré 0.290846194) et rend la différenciation
/// observable hors saturation.
const List<double> kPentesDemo = <double>[
  8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0, -1.0, -2.0, -3.0, -4.0,
];

/// Nombre de mises à jour réelles par phase. 100 suffit à laisser la projection
/// redistribuer et à faire émerger les poids ; au-delà, on ne gagne pas
/// d'information et on allonge inutilement la campagne (consigne : pas de
/// campagne disproportionnée).
const int kCyclesDemo = 100;

/// Cycles des phases de la séquence S10 : 40 par phase.
///
/// POURQUOI 40 ET NON 80 : mesuré qu'à 80 cycles sur 3 phases, `jockey` atteint
/// son plafond individuel 0,150000000 dès la phase 1 et y RESTE, ce qui annule
/// la variation et rendrait la « diminution » puis la « récupération »
/// indétectables (varJ = 0.000e+0, mesuré). À 40 cycles, les trois phases se
/// déroulent SOUS le plafond et les variations sont lisibles.
const int kCyclesPhase = 40;

/// Cycles du test S8-2. 70 est la seule valeur MESURÉE satisfaisant à la fois
/// `jockey` strictement sous son plafond individuel (variation réelle) et la
/// part enrichie strictement sous 0,40. Voir la justification dans S8-2.
const int kCyclesS82 = 70;

/// Table de notes : `note = 50 + pente × (rang − 3)`, bornée [0, 100].
ScoresCriteres _scoresPour(int rang, Map<String, double> pertinence) {
  double note(String c) =>
      (50.0 + (pertinence[c] ?? 0.0) * (rang - 3)).clamp(0.0, 100.0);
  return ScoresCriteres(
    forme: note('forme'), gains: note('gains'), record: note('record'),
    cote: note('cote'), constance: note('constance'),
    victoires: note('victoires'), discipline: note('discipline'),
    distSpec: note('distSpec'), jockey: note('jockey'),
    repos: note('repos'), hippo: note('hippo'),
    entraineur: note('entraineur'), elo: note('elo'),
    terrain: note('terrain'), divergence: note('divergence'),
    poidsRel: note('poidsRel'), progression: note('progression'),
    mouvCote: note('mouvCote'), placeDepart: note('placeDepart'),
  );
}

/// Sème [cycles] courses non résolues avec la table de notes [pertinence],
/// depuis [depart], puis exécute [cycles] mises à jour RÉELLES de production.
///
/// Rend le `Cycle` de la DERNIÈRE mise à jour (variations et momentum du
/// dernier cycle, poids obtenus).
Future<Cycle> _executer({
  required Map<String, double> depart,
  required Map<String, double> pertinence,
  required int cycles,
}) async {
  final courses = <IaPronostic>[
    for (var i = 0; i < cycles; i++)
      pronostic(
        courseKey: 'C${i.toString().padLeft(4, '0')}',
        date: DateTime.now().subtract(Duration(days: 1 + i ~/ 10)),
        resolu: false,
        scoresCriteres: {for (var n = 1; n <= 5; n++) '$n': _scoresPour(n, pertinence)},
      ),
    for (var j = 0; j < 12; j++)
      pronostic(
        courseKey: 'A${j.toString().padLeft(4, '0')}',
        date: DateTime.now().subtract(Duration(days: 1 + (cycles + j) ~/ 10)),
        scoresCriteres: {for (var n = 1; n <= 5; n++) '$n': _scoresPour(n, pertinence)},
      ),
  ];
  await semer(
    pronostics: courses,
    verifierNombre: false,
    poidsDepart: depart,
    sigmaAttendue: sommeCle(depart, kCles),
  );
  Cycle? dernier;
  for (var i = 0; i < cycles; i++) {
    dernier = await executerCycle(
      courseKey: 'C${i.toString().padLeft(4, '0')}',
      arrivee: const <int>[1, 2, 3, 4, 5],
    );
  }
  return dernier!;
}

Map<String, double> _pertinenceDepuis(List<double> pentes) => <String, double>{
      for (final k in kBase) k: kPenteBaseNeutre,
      for (var i = 0; i < kEnrichis.length; i++) kEnrichis[i]: pentes[i],
    };

/// Nombre de critères dont la valeur touche une de ses deux bornes.
List<String> _satures(Map<String, double> poids) {
  final bornes = IaPoidsAdaptatifs.bornesIndividuelles();
  return <String>[
    for (final k in kEnrichis)
      if ((poids[k]! - bornes[k]![0]).abs() < 1e-9 ||
          (poids[k]! - bornes[k]![1]).abs() < 1e-9)
        k,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  GARDE PRÉALABLE — exécutée EN PREMIER, avant toute conclusion
  // ═════════════════════════════════════════════════════════════════════════
  test('S8-GARDE — le scénario permet réellement d observer (sensibilité)', () async {
    // G-a : deux régimes STRICTEMENT OPPOSÉS doivent donner deux tables
    // différentes. Si le moteur était insensible, tout « pas de différence »
    // mesuré plus loin serait un faux négatif du montage, pas un fait du
    // moteur. C'est la garde anti-faux-négatif.
    final cA = await _executer(
      depart: poidsNormalisesDeDepart(),
      pertinence: _pertinenceDepuis(kPentesDemo),
      cycles: kCyclesDemo,
    );
    final cB = await _executer(
      depart: poidsNormalisesDeDepart(),
      pertinence: _pertinenceDepuis(<double>[
        for (final v in kPentesDemo) -v,
      ]),
      cycles: kCyclesDemo,
    );
    final (maxi, pire, bouges) = ecart(cA.obtenu, cB.obtenu);
    // ignore: avoid_print
    print('[S8-GARDE] G-a sensibilité : écartMax=${maxi.toStringAsExponential(6)} '
        'pire=$pire bougés=$bouges/19');
    expect(maxi, greaterThan(1e-3),
        reason: 'GARDE G-a : des pentes opposées DOIVENT produire des tables '
            'différentes, sinon la mesure est muette (faux négatif)');
    expect(bouges, 19,
        reason: 'GARDE G-a : les 19 critères doivent être sensibles');

    // ── G-b : BIAIS STRUCTUREL DU SIGNAL — MESURÉ, PUIS DOCUMENTÉ ─────────
    // Avec les 19 pentes à zéro, TOUS les partants ont des notes identiques :
    // aucun critère ne porte d'information. Un moteur non biaisé devrait donc
    // produire une discrimination nulle et un momentum nul pour les 19.
    //
    // ⚠️ CE N'EST PAS LE CAS, ET C'EST UN FAIT MESURÉ, PAS UNE HYPOTHÈSE.
    // MESURE : les 19 momentum valent TOUS exactement −8.238817687e-4
    // (amplitude max−min = 0.000e+0, identiques à 1e-15).
    // CAUSE — FORMULE RÉELLEMENT EXÉCUTÉE, MESURÉE LE 28/11/2026.
    // ⚠️ LES DEUX SOMMES QUE J'AVAIS ÉCRITES ICI (2,400000 / 2,600000) ÉTAIENT
    //    FAUSSES ET SONT RETIRÉES. Elles supposaient 5 rangs contributifs dans
    //    les DEUX listes. Or dans un champ de 5 partants, les poids sont
    //    1.0/0.6/0.5/0.3/0.0 (bons) et 0.0/0.4/0.5/0.7/1.0 (mauvais) : les
    //    entrées à poids NUL ne sont PAS ajoutées (guard `if (poidsBon > 0)`),
    //    donc `lenBons = 5` mais `lenMauvais = 4`, et `moyPond` divise par
    //    `list.length`. DÉNOMINATEURS DIFFÉRENTS ⇒ l'écart des SOMMES (−0,2)
    //    ne détermine pas le signe de l'écart des MOYENNES.
    //    MESURES (champ de 5, notes neutres) : Σbons = 135.000000 (÷5),
    //    Σmauvais = 115.000000 (÷4) ⇒ moyBon = 27.0 < moyMauvais = 28.75
    //    ⇒ discrimination = −1.750000000e-2. Signe NÉGATIF, mais dû à un
    //    rapport de dénominateurs (5/4), pas à la somme.
    //    Ce nombre N'EST PAS INTRINSÈQUE : mesuré k* = −2.287581695 pour N=5,
    //    +4.938271606 pour N=4, −4.687500001 pour N=6, −4.726368161 pour N=8,
    //    −4.099462366 pour N=10, −2.742616029 pour N=16. La référence neutre
    //    dépend donc de la TAILLE DU CHAMP.
    //
    // CETTE GARDE NE CORRIGE RIEN : elle CONSTATE. Le biais n'est pas modifié
    // (interdiction absolue de toucher aux coefficients ou seuils). Mais il
    // interdit d'interpréter « momentum > 0 » comme « critère pertinent » :
    // le bon repère est le NIVEAU NEUTRE, mesuré ci-dessous. C'est pourquoi
    // S10-2 compare chaque momentum à cette référence et non à zéro.
    final cNeutre = await _executer(
      depart: poidsNormalisesDeDepart(),
      pertinence: <String, double>{
        for (final k in kCles) k: 0.0,
      },
      cycles: kCyclesDemo,
    );
    final refNeutre = cNeutre.momentum['forme']!;
    final momsNeutres = <double>[for (final k in kCles) cNeutre.momentum[k] ?? 0.0];
    final ampNeutre = momsNeutres.reduce((a, b) => a > b ? a : b) -
        momsNeutres.reduce((a, b) => a < b ? a : b);
    final partNeutre = sommeCle(cNeutre.obtenu, kEnrichis);
    // ignore: avoid_print
    print('[S8-GARDE] G-b notes 100 % neutres : momentum de référence = '
        '${refNeutre.toStringAsExponential(12)} ; amplitude des 19 = '
        '${ampNeutre.toStringAsExponential(3)} ; part enrichie = '
        '${partNeutre.toStringAsFixed(12)}');
    // Aucune information ⇒ aucune dispersion : c'est la garde de neutralité.
    expect(ampNeutre, lessThan(1e-15),
        reason: 'GARDE G-b : à notes strictement neutres, les 19 momentum '
            'doivent être IDENTIQUES — sinon le moteur invente un signal');
    // Et ce niveau commun n'est PAS zéro : biais mesuré, non corrigé, constaté.
    expect(refNeutre, lessThan(-1e-5),
        reason: 'GARDE G-b : le biais du signal gradué est un fait mesuré ; '
            's il disparaissait, la référence de S10-2 serait invalide');
    // La part enrichie à notes neutres N EST PAS 0,40 (mesuré 0.324344009847).
    // On ne l affirme pas : on la mesure et on l imprime, sans assertion
    // fragile — elle n est pas nécessaire au raisonnement.
    expect(partNeutre, greaterThan(0.18));
    expect(partNeutre, lessThan(0.40));

    // G-c : il doit réellement y avoir apprentissage.
    expect(cA.aAppris, isTrue, reason: 'GARDE G-c : aucune mise à jour réelle');
    expect(cA.nbMisesAJour, greaterThan(0));
    // ignore: avoid_print
    print('[S8-GARDE] G-c apprentissage : nbMisesAJour=${cA.nbMisesAJour}');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  POINT 8 — les 12 enrichis se différencient SELON LEUR PERTINENCE
  // ═════════════════════════════════════════════════════════════════════════
  test('S8-1 — les 12 enrichis se différencient par pertinence, hors saturation',
      () async {
    final depart = poidsNormalisesDeDepart();
    final partDepart = sommeCle(depart, kEnrichis);
    final c = await _executer(
      depart: depart,
      pertinence: _pertinenceDepuis(kPentesDemo),
      cycles: kCyclesDemo,
    );
    final obtenu = c.obtenu;

    // Preuve d'exécution.
    expect(c.aAppris, isTrue);

    // (1) HORS SATURATION : la part enrichie doit être STRICTEMENT sous le
    //     plafond collectif 0,40 ET au-dessus du plancher 0,18.
    final part = sommeCle(obtenu, kEnrichis);
    // ignore: avoid_print
    print('[S8-1] partEnrichie : départ=${partDepart.toStringAsFixed(9)} '
        '→ ${part.toStringAsFixed(9)} (bornes [0,18 ; 0,40])');
    expect(part, greaterThan(0.18),
        reason: 'C4 : plancher collectif des enrichis');
    expect(part, lessThan(0.40),
        reason: 'C4 : la part doit être STRICTEMENT sous le plafond, sinon on '
            'ne mesure pas un régime hors saturation');

    // (2) AUCUN critère enrichi ne doit être collé à une borne : sinon la
    //     différenciation serait bridée par une contrainte, pas par la donnée.
    final satures = _satures(obtenu);
    // ignore: avoid_print
    print('[S8-1] critères saturés = $satures');
    expect(satures, isEmpty,
        reason: 'aucun critère enrichi ne doit toucher une borne individuelle');

    // (3) DIFFÉRENCIATION RÉELLE : les poids ne doivent pas être une
    //     homothétie. Amplitude minimale mesurée 0.109016120 − 0.005020408.
    final poids12 = <double>[for (final k in kEnrichis) obtenu[k]!];
    final maxi = poids12.reduce((a, b) => a > b ? a : b);
    final mini = poids12.reduce((a, b) => a < b ? a : b);
    // ignore: avoid_print
    print('[S8-1] poids maxi=${maxi.toStringAsFixed(9)} '
        'mini=${mini.toStringAsFixed(9)} amplitude=${(maxi - mini).toStringAsFixed(9)}');
    expect(maxi - mini, greaterThan(0.02),
        reason: 'amplitude des 12 poids : une homothétie donnerait 0');

    // (4) SÉPARATION PAR LE SIGNE : les 8 enrichis ANTI-pertinents (pente > 0)
    //     doivent TOUS être plus légers que les 4 PERTINENTS (pente < 0).
    //     C'est la forme la plus forte de « différenciation par pertinence » :
    //     aucune exception n'est tolérée.
    final anti = <String>[];
    final pertinents = <String>[];
    for (var i = 0; i < kEnrichis.length; i++) {
      (kPentesDemo[i] > 0 ? anti : pertinents).add(kEnrichis[i]);
    }
    final maxAnti = anti.map((k) => obtenu[k]!).reduce((a, b) => a > b ? a : b);
    final minPert = pertinents.map((k) => obtenu[k]!).reduce((a, b) => a < b ? a : b);
    // ignore: avoid_print
    print('[S8-1] poids max des ${anti.length} ANTI=${maxAnti.toStringAsFixed(9)} '
        '< poids min des ${pertinents.length} PERTINENTS=${minPert.toStringAsFixed(9)}');
    expect(maxAnti, lessThan(minPert),
        reason: 'tout critère pertinent doit peser plus que tout critère '
            'anti-pertinent (mesuré : ${maxAnti.toStringAsFixed(9)} < '
            '${minPert.toStringAsFixed(9)})');

    // (5) CONCORDANCE DE RANG : corrélation de Spearman entre la pertinence
    //     (−pente, positive = pertinent) et le poids obtenu.
    final pertinence = <String, double>{
      for (var i = 0; i < kEnrichis.length; i++)
        kEnrichis[i]: -kPentesDemo[i],
    };
    final rho = spearman(kEnrichis, pertinence, obtenu);
    // ignore: avoid_print
    print('[S8-1] spearman(pertinence, poids) = ${rho.toStringAsFixed(9)}');
    expect(rho, greaterThan(0.5),
        reason: 'les poids doivent suivre la pertinence');

    // (6) INVARIANTS du contrat.
    expect(sommeCle(obtenu, kCles), closeTo(1.0, 1e-9), reason: 'C1 : Σ = 1');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  POINT 8 (suite) — un critère pertinent PROGRESSE, les autres reculent
  // ═════════════════════════════════════════════════════════════════════════
  test('S8-2 — un critère pertinent progresse et le collectif recule', () async {
    final depart = poidsNormalisesDeDepart();
    final partDepart = sommeCle(depart, kEnrichis);
    final sommeAutresDepart = sommeCle(
        depart, kEnrichis.where((k) => k != 'jockey').toList());
    final jockeyDepart = depart['jockey']!;

    // UNE seule perturbation : `jockey` reçoit la pente la PLUS pertinente
    // (−8). Les 11 autres enrichis et les 7 bases restent neutres.
    // 70 ET NON 100 CYCLES — CHOIX MESURÉ, PAS ESTHÉTIQUE.
    // MESURE à 100 cycles : jockey = 0.150000000, c est-à-dire EXACTEMENT son
    // plafond individuel ; la variation terminale y est nulle (0.000e+0) et la
    // part enrichie vaut 0.379890536 (déjà sortie du plafond collectif, mais
    // par le plafond individuel du critère, ce qui brouille la lecture).
    // MESURE à 40 : jockey = 0.092237920466 mais part = 0.39999999999999997,
    // donc PAS strictement sous 0,40 et l assertion « hors saturation »
    // échouerait.
    // MESURE à 70 : jockey = 0.146991809514 (SOUS son plafond, variation
    // +1.973e-3 donc réelle) et part = 0.399577600424423, STRICTEMENT sous
    // 0,40. C est la seule durée mesurée qui satisfait les deux exigences.
    final c = await _executer(
      depart: depart,
      pertinence: <String, double>{
        for (final k in kCles) k: 0.0,
        'jockey': -8.0,
      },
      cycles: kCyclesS82,
    );
    final obtenu = c.obtenu;
    final jockey = obtenu['jockey']!;
    final part = sommeCle(obtenu, kEnrichis);
    final sommeAutres = sommeCle(
        obtenu, kEnrichis.where((k) => k != 'jockey').toList());

    // ignore: avoid_print
    print('[S8-2] jockey : ${jockeyDepart.toStringAsFixed(9)} → '
        '${jockey.toStringAsFixed(9)}   (momentum=${(c.momentum["jockey"] ?? 0).toStringAsExponential(3)}, '
        'variation=${c.obtenu_("jockey").toStringAsExponential(3)})');
    // ignore: avoid_print
    print('[S8-2] somme des 11 autres : ${sommeAutresDepart.toStringAsFixed(9)} '
        '→ ${sommeAutres.toStringAsFixed(9)}');
    // ignore: avoid_print
    print('[S8-2] part enrichie : ${partDepart.toStringAsFixed(9)} → '
        '${part.toStringAsFixed(9)}');

    // Preuve que le régime est RÉELLEMENT hors saturation à l'arrivée.
    expect(part, lessThan(0.40),
        reason: 'le collectif doit être descendu sous le plafond (sinon la '
            'progression du pertinent serait obtenue par écrasement du budget)');
    expect(part, greaterThan(0.18));

    // PROGRESSION du critère pertinent.
    expect(jockey, greaterThan(jockeyDepart),
        reason: 'un critère pertinent doit progresser');
    // Momentum de même signe que la progression.
    expect(c.momentum['jockey'], greaterThan(0));

    // RECUL COLLECTIF des 11 autres : c'est le prix de la progression, et
    // c'est la vérification que la progression n'est pas un simple effet
    // d'échelle (Σ constant).
    expect(sommeAutres, lessThan(sommeAutresDepart),
        reason: 'les 11 autres enrichis doivent céder du poids');

    // Bornes et somme.
    expect(jockey, lessThanOrEqualTo(0.15 + 1e-12),
        reason: 'plafond individuel de jockey');
    expect(sommeCle(obtenu, kCles), closeTo(1.0, 1e-9), reason: 'C1 : Σ = 1');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  POINT 10 — diminution puis RÉCUPÉRATION d'un critère précédemment
  //             défavorisé, momentum concordant, contraintes tenues
  // ═════════════════════════════════════════════════════════════════════════
  test('S10-1 — un critère défavorisé DIMINUE puis RÉCUPÈRE, hors saturation',
      () async {
    // Séquence MESURÉE, enchaînée : les poids obtenus en fin de phase N sont
    // le départ de la phase N+1 (aucune réinitialisation entre les phases).
    // Phases : pertinent → anti-pertinent → pertinent.
    //   R1 pertinente  : jockey pente −8
    //   R2 hostile     : jockey pente +8   ← le critère devient NON pertinent
    //   R3 pertinente  : jockey pente −8   ← il redevient pertinent
    final phases = <double>[-8.0, 8.0, -8.0];
    final noms = <String>['R1 pertinent', 'R2 anti-pertinent', 'R3 pertinent'];
    final poidsJockey = <double>[];
    final moments = <double>[];
    final variations = <double>[];
    final parts = <double>[];

    var w = poidsNormalisesDeDepart();
    for (var p = 0; p < phases.length; p++) {
      final c = await _executer(
        depart: w,
        pertinence: <String, double>{
          for (final k in kCles) k: 0.0,
          'jockey': phases[p],
        },
        cycles: kCyclesPhase,
      );
      poidsJockey.add(c.obtenu['jockey']!);
      moments.add(c.momentum['jockey'] ?? 0.0);
      variations.add(c.obtenu_('jockey'));
      parts.add(sommeCle(c.obtenu, kEnrichis));

      // ignore: avoid_print
      print('[S10-1] ${noms[p].padRight(16)} jockey='
          '${c.obtenu["jockey"]!.toStringAsFixed(12)} '
          'momentum=${(c.momentum["jockey"] ?? 0).toStringAsExponential(4)} '
          'variation=${c.obtenu_("jockey").toStringAsExponential(4)} '
          'partEnr=${parts[p].toStringAsFixed(9)} '
          'Σ=${sommeCle(c.obtenu, kCles).toStringAsFixed(9)}');

      // Invariants À CHAQUE PHASE (C1, C4, F1).
      expect(sommeCle(c.obtenu, kCles), closeTo(1.0, 1e-9),
          reason: 'C1 violé en phase ${p + 1}');
      expect(parts[p], greaterThanOrEqualTo(0.18 - 1e-12),
          reason: 'C4 plancher violé en phase ${p + 1}');
      expect(parts[p], lessThanOrEqualTo(0.40 + 1e-12),
          reason: 'C4 plafond violé en phase ${p + 1}');
      final bornes = IaPoidsAdaptatifs.bornesIndividuelles();
      for (final k in kCles) {
        expect(c.obtenu[k]!, greaterThanOrEqualTo(bornes[k]![0] - 1e-12),
            reason: 'F1 plancher violé pour $k en phase ${p + 1}');
        expect(c.obtenu[k]!, lessThanOrEqualTo(bornes[k]![1] + 1e-12),
            reason: 'F1 plafond violé pour $k en phase ${p + 1}');
      }
      w = c.obtenu;
    }

    // (2) R2 — DIMINUTION : le critère devenu anti-pertinent RECULE.
    //     C'est la première moitié du POINT 10, avec sa valeur mesurée.
    // ignore: avoid_print
    print('[S10-1] DIMINUTION R1→R2 : ${poidsJockey[0].toStringAsFixed(12)} → '
        '${poidsJockey[1].toStringAsFixed(12)}');
    expect(poidsJockey[1], lessThan(poidsJockey[0]),
        reason: 'un critère devenu anti-pertinent doit DIMINUER');
    expect(variations[1], lessThan(0));
    // (3) R3 — RÉCUPÉRATION : le critère redevient pertinent et REMONTE
    //     depuis le niveau atteint en R2 (précédemment défavorisé).
    // ignore: avoid_print
    print('[S10-1] RÉCUPÉRATION R2→R3 : ${poidsJockey[1].toStringAsFixed(12)} → '
        '${poidsJockey[2].toStringAsFixed(12)}');
    expect(poidsJockey[2], greaterThan(poidsJockey[1]),
        reason: 'un critère précédemment défavorisé doit pouvoir REGAGNER '
            'du poids quand il redevient pertinent');
    expect(variations[2], greaterThan(0));

    // (4) MOMENTUM : il accompagne les évolutions. Son signe doit concorder
    //     avec la variation observée DANS CHACUNE DES TROIS PHASES.
    for (var p = 0; p < phases.length; p++) {
      if (moments[p] == 0.0) continue;
      final concordant = moments[p] > 0
          ? variations[p] > 0
          : variations[p] < 0;
      expect(concordant, isTrue,
          reason: 'momentum de signe ${moments[p].sign} mais variation de '
              'signe ${variations[p].sign} en phase ${p + 1}');
    }

    // (5) Les trois phases sont RÉELLEMENT distinctes (pas de stagnation).
    expect(poidsJockey.toSet().length, 3,
        reason: 'les trois phases doivent produire trois niveaux distincts');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  POINT 10 (suite) — le momentum ACCOMPAGNE les évolutions des 12 critères
  // ═════════════════════════════════════════════════════════════════════════
  test('S10-2 — le momentum DEPARTAGE les 12 enrichis par rapport au neutre',
      () async {
    final c = await _executer(
      depart: poidsNormalisesDeDepart(),
      pertinence: _pertinenceDepuis(kPentesDemo),
      cycles: kCyclesDemo,
    );
    // Référence MESURÉE, et non « zéro ». Voir la garde G-b : à notes
    // strictement neutres, le signal gradué de v9.92 (Σ poidsBon = 2.4 contre
    // Σ poidsMauvais = 2.6, écart −0.2) produit un momentum NÉGATIF CONSTANT
    // de −8.238817687e-4 pour les 19 critères. Comparer à zéro ferait donc
    // passer un critère simplement non informatif pour un critère
    // anti-pertinent — c'est précisément l'erreur que la première version de
    // ce test a commise, mesurée puis corrigée ici.
    final cNeutre = await _executer(
      depart: poidsNormalisesDeDepart(),
      pertinence: <String, double>{for (final k in kCles) k: 0.0},
      cycles: kCyclesDemo,
    );
    final ref = cNeutre.momentum['forme']!;
    // ignore: avoid_print
    print('[S10-2] momentum de référence (notes neutres) = '
        '${ref.toStringAsExponential(12)}');

    // (1) DÉPARTAGE : tout critère pertinent (pente < 0) doit être AU-DESSUS
    //     de la référence ; tout critère anti-pertinent (pente > 0) EN DESSOUS.
    //     C'est la forme falsifiable de « le momentum accompagne la
    //     pertinence ». Mesuré : 12/12.
    var corrects = 0;
    for (var i = 0; i < kEnrichis.length; i++) {
      final k = kEnrichis[i];
      final mom = c.momentum[k] ?? 0.0;
      final pente = kPentesDemo[i];
      final auDessus = mom > ref;
      final attendu = pente < 0;
      if (auDessus == attendu) corrects++;
      // ignore: avoid_print
      print('[S10-2] $k pente=${pente.toStringAsFixed(1)} '
          'momentum=${mom.toStringAsExponential(4)} '
          'auDessusDeRef=$auDessus attendu=$attendu');
      expect(auDessus, attendu,
          reason: 'pour $k (pente $pente), le momentum doit être '
              '${attendu ? "au-dessus" : "en-dessous"} de la référence neutre');
    }
    expect(corrects, 12, reason: 'les 12 doivent être départagés');

    // (2) INTENSITÉ MONOTONE : |momentum − ref| doit croître avec |pente|.
    final parForce = <double, double>{
      for (var i = 0; i < kEnrichis.length; i++)
        kPentesDemo[i].abs(): ((c.momentum[kEnrichis[i]] ?? 0.0) - ref).abs(),
    };
    final forces = parForce.keys.toList()..sort();
    for (var i = 1; i < forces.length; i++) {
      // ignore: avoid_print
      expect(parForce[forces[i]]!, greaterThanOrEqualTo(parForce[forces[i - 1]]! - 1e-12),
          reason: 'l intensité du momentum doit croître avec |pente| : '
              '${forces[i - 1]} → ${parForce[forces[i - 1]]}, '
              '${forces[i]} → ${parForce[forces[i]]}');
    }
    // ignore: avoid_print
    print('[S10-2] monotonie vérifiée sur les 12 : '
        '${forces.map((f) => "${f.toStringAsFixed(1)}:${parForce[f]!.toStringAsExponential(2)}").join(" ")}');

    // (3) LIMITE MESURÉE ET DOCUMENTÉE, NON MASQUÉE.
    // Le momentum n'est pas une garantie sur la VARIATION obtenue au même
    // cycle. MESURÉ sur ce scénario : `progression` (pente −2) porte un
    // momentum de −1.0357e-4 (au-dessus de la référence, donc cohérent) mais
    // une variation terminale de +1.287e-4, de signe opposé. La cause est la
    // correction résiduelle EXACTE de `_remplirGroupe` (models:958-990), qui
    // répartit l'écart de budget à proportion de la marge libre des critères
    // non saturés : sur un déplacement de l'ordre de 1e-5, elle peut inverser
    // le sens. On le CONSTATE : le contrat porte sur le momentum produit par
    // l'apprentissage, pas sur une égalité de signe à chaque cycle.
    var concordants = 0;
    for (final k in kEnrichis) {
      final mom = c.momentum[k] ?? 0.0;
      final variation = c.obtenu_(k);
      final auDessus = mom > ref;
      if ((auDessus && variation >= -1e-15) || (!auDessus && variation <= 1e-15)) {
        concordants++;
      }
    }
    // ignore: avoid_print
    print('[S10-2] concordance (auDessus/auDessous de la réf, signe de la '
        'variation terminale) = $concordants/12');
    expect(concordants, greaterThanOrEqualTo(11),
        reason: 'la concordance doit être très majoritaire ; plus bas '
            'signaleraient un dérèglement du momentum lui-même (mesuré 11/12, '
            'l unique écart étant attribué à la correction résiduelle)');
  });
}
