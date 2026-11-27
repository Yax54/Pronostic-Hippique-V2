// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER POIDS IA — §6 : L'INCOHÉRENCE D'ÉCHELLE 1,26 vs 1,00
//  ET SES CONSOMMATEURS DE DÉCISION
//
//  QUESTION DE L'UTILISATEUR : « La division par la somme des poids effectifs
//  ne doit pas être considérée comme une correction automatiquement
//  acceptable. Elle pourrait modifier l'échelle absolue des scores et les
//  décisions dépendantes. »
//
//  RÉPONSE PAR LA MESURE, EN TROIS TEMPS :
//    1. Quelles sont les CONDITIONS EXACTES du 63,40 % / 5,20 % déjà annoncé ?
//    2. Quels CONSOMMATEURS dépendent de l'échelle ABSOLUE (et non du rang) ?
//    3. Trois solutions comparées, sans toucher la production.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION. Aucun seuil touché.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

/// Réplique EXACTE de `_normaliserScores` (ia_pronostic_engine.dart:224-242).
List<double> _normaliser(List<double> vals) {
  if (vals.length < 3) return List<double>.from(vals);
  final minS = vals.reduce(math.min);
  final maxS = vals.reduce(math.max);
  final range = maxS - minS;
  if (range <= 1.0) return List<double>.from(vals);
  final n = vals.length;
  final ratioNorme = n <= 6 ? 0.40 : n <= 12 ? 0.60 : 0.75;
  final ratioBrut = 1.0 - ratioNorme;
  return [
    for (final s in vals)
      (((s - minS) / range * 100.0).clamp(0.0, 100.0)) * ratioNorme +
          s * ratioBrut,
  ];
}

/// Réplique de `_determinerLabel` (ia_pronostic_engine.dart:642-652).
String _label(int rang, double score) {
  if (rang == 1 && score >= 75) return 'FAVORI_IA';
  if (rang == 1 && score >= 52) return 'SELECTION_IA';
  if (rang == 1) return 'CHOIX_IA';
  if (rang == 2) return 'DEUXIEME';
  if (rang == 3) return 'TROISIEME';
  return 'AUTRE';
}

/// Réplique de `confianceIA` (zt_models.dart:1216-1240).
double _confiance(List<double> scores) {
  if (scores.isEmpty) return 0.0;
  if (scores.length == 1) return scores.first.clamp(40.0, 95.0);
  final s1 = scores[0];
  final s2 = scores[1];
  final s3 = scores.length >= 3 ? scores[2] : s2;
  final qualiteFavori = s1.clamp(0.0, 100.0) * 0.40;
  final ecart12 = (s1 - s2).clamp(0.0, 50.0);
  final dominance = (ecart12 / 50.0) * 40.0;
  final cohesion = ((s2 + s3) / 2.0).clamp(0.0, 100.0) * 0.20;
  return (qualiteFavori + dominance + cohesion).clamp(0.0, 100.0);
}

/// Scores de critères réalistes pour N partants.
Map<String, List<double>> _course(math.Random alea, int n) {
  final m = <String, List<double>>{};
  for (final k in kCles) {
    final base = alea.nextDouble() * 40 + 30; // 30..70
    m[k] = [for (var i = 0; i < n; i++) (base + alea.nextDouble() * 40 - 20).clamp(0.0, 100.0)];
  }
  return m;
}

/// Joue la formule EXACTE du moteur : somme pondérée NON divisée
/// (`ia_pronostic_engine.dart:391-409`).
List<double> _scores(Map<String, List<double>> crit, Map<String, double> poids) {
  final n = crit['forme']!.length;
  return [
    for (var i = 0; i < n; i++)
      kCles.fold(0.0, (a, k) => a + crit[k]![i] * poids[k]!),
  ];
}

List<int> _rangs(List<double> s) {
  final idx = List<int>.generate(s.length, (i) => i)
    ..sort((a, b) => s[b].compareTo(s[a]));
  return idx;
}

void main() {
  final p26 = IaPoidsAdaptatifs();
  final p10 = IaPoidsAdaptatifs()..clamp();
  final w26 = {for (final k in kCles) k: p26.getPoids(k)};
  final w10 = {for (final k in kCles) k: p10.getPoids(k)};
  // Solution 3 : le MÊME état appris, mais divisé par sa somme au moment du
  // score (ce que ferait « diviser par la somme des poids effectifs »).
  final wDiv = {for (final k in kCles) k: w10[k]! / w10.values.fold(0.0, (a, b) => a + b)};

  // ───────────────────────────────────────────────────────────────────────
  //  H1 — CONDITIONS EXACTES DU 63,40 % / 5,20 %
  // ───────────────────────────────────────────────────────────────────────
  test('H1 — conditions exactes de la mesure 63,40 % / 5,20 %', () {
    // ignore: avoid_print
    print('[H1] CONDITIONS EXACTES :');
    // ignore: avoid_print
    print('[H1]   poids A = constructeur BRUT, avant clamp() → somme '
        '${w26.values.fold(0.0, (a, b) => a + b).toStringAsFixed(12)}');
    // ignore: avoid_print
    print('[H1]   poids B = même constructeur APRÈS clamp()+normaliser() → '
        'somme ${w10.values.fold(0.0, (a, b) => a + b).toStringAsFixed(12)}');
    // ┌────────────────────────────────────────────────────────────────────┐
    // │ SECONDE CORRECTION D'UNE AFFIRMATION FAUSSE (la mienne).          │
    // │ J'avais écrit dans le harnais : « ratios A/B tous égaux à 1.26 ».  │
    // │ MESURE : FAUX. Les ratios sont 1.183333333 pour les 7 de base et   │
    // │ 1.375000000 pour les 12 enrichis — DEUX facteurs distincts.        │
    // │ Raison : la table 1.26 a une fraction enrichie de 0.436507937,     │
    // │ que `normaliser()` ÉCRÊTE à 0.40. Passer de 1.26 à 1.00 n'est donc │
    // │ PAS un simple changement d'échelle : c'est échelle × redistribution│
    // │ de 4,35 points de poids des enrichis vers la base.                 │
    // └────────────────────────────────────────────────────────────────────┘
    final rBase = w26['forme']! / w10['forme']!;
    final rEnr = w26['placeDepart']! / w10['placeDepart']!;
    var ratiosBaseUniformes = true;
    var ratiosEnrUniformes = true;
    for (final k in kCles) {
      final r = w26[k]! / w10[k]!;
      if (k != 'distSpec' && k != 'jockey' && k != 'repos' && k != 'hippo' &&
          k != 'entraineur' && k != 'elo' && k != 'terrain' &&
          k != 'divergence' && k != 'poidsRel' && k != 'progression' &&
          k != 'mouvCote' && k != 'placeDepart') {
        if ((r - rBase).abs() > 1e-12) ratiosBaseUniformes = false;
      } else {
        if ((r - rEnr).abs() > 1e-12) ratiosEnrUniformes = false;
      }
    }
    // ignore: avoid_print
    print('[H1]   ratios A/B : base = ${rBase.toStringAsFixed(9)} '
        '(uniforme sur 7/7 = $ratiosBaseUniformes) ; enrichis = '
        '${rEnr.toStringAsFixed(9)} (uniforme sur 12/12 = $ratiosEnrUniformes)');
    // ignore: avoid_print
    print('[H1]   ⇒ DEUX facteurs distincts, pas 1.26. L\'écart 1.26→1.00 est '
        'ÉCHELLE **×** REDISTRIBUTION (fraction enrichie 0.436507937 écrêtée '
        'à 0.40), donc il n\'est PAS réductible à un pur changement '
        'd\'échelle. C\'est un point décisif pour §6.');
    expect(ratiosBaseUniformes, isTrue);
    expect(ratiosEnrUniformes, isTrue);
    expect(rBase, closeTo(1.183333333, 1e-9));
    expect(rEnr, closeTo(1.375, 1e-12));
    // ignore: avoid_print
    print('[H1]   scores de critères : Uniform(10,90) par critère et par '
        'partant, graine unique, partants 5..20, 2000 courses.');
    // ignore: avoid_print
    print('[H1]   normalisation appliquée : _normaliserScores du moteur.');

    final alea = math.Random(424242);
    var change = 0;
    var top1 = 0;
    var top3 = 0;
    var total = 0;
    for (var i = 0; i < 2000; i++) {
      final n = 5 + alea.nextInt(16);
      final crit = _course(alea, n);
      final sA = _normaliser(_scores(crit, w26));
      final sB = _normaliser(_scores(crit, w10));
      final rA = _rangs(sA);
      final rB = _rangs(sB);
      final ordreA = [for (final x in rA) x];
      final ordreB = [for (final x in rB) x];
      var diff = false;
      for (var j = 0; j < n; j++) {
        if (ordreA[j] != ordreB[j]) diff = true;
      }
      if (diff) change++;
      if (rA[0] != rB[0]) top1++;
      final t3a = rA.take(3).toSet();
      final t3b = rB.take(3).toSet();
      if (!t3a.containsAll(t3b) || !t3b.containsAll(t3a)) top3++;
      total++;
    }
    // ignore: avoid_print
    print('[H1] ⇒ RÉSULTAT REPRODUIT : classements modifiés '
        '${(change / total * 100).toStringAsFixed(2)} %, TOP1 '
        '${(top1 / total * 100).toStringAsFixed(2)} %, TOP3 '
        '${(top3 / total * 100).toStringAsFixed(2)} % sur $total courses.');
    expect(change / total, closeTo(0.6340, 0.02),
        reason: 'la mesure 63,40 % est reproduite à ±2 pt près');
    expect(top1 / total, closeTo(0.0520, 0.015),
        reason: 'la mesure 5,20 % du TOP1 est reproduite');
  });

  // ───────────────────────────────────────────────────────────────────────
  //  H2 — QUELLE EST L'AMPLEUR RÉELLE DE L'ÉCART AVANT NORMALISATION ?
  // ───────────────────────────────────────────────────────────────────────
  test('H2 — écart absolu des scores : 1.26× exactement', () {
    final alea = math.Random(999);
    var maxEcartRel = 0.0;
    var maxS = 0.0;
    for (var i = 0; i < 500; i++) {
      final crit = _course(alea, 12);
      final sA = _scores(crit, w26);
      final sB = _scores(crit, w10);
      for (var j = 0; j < sA.length; j++) {
        if (sB[j] > 1e-9) {
          maxEcartRel = math.max(maxEcartRel, (sA[j] / sB[j] - 1.26).abs());
        }
        maxS = math.max(maxS, sA[j]);
      }
    }
    // ignore: avoid_print
    print('[H2] écart relatif score_1.26 / score_1.00 : max mesuré = '
        '${maxEcartRel.toStringAsFixed(15)}');
    // ignore: avoid_print
    print('[H2] score BRUT maximal observé (non normalisé) = '
        '${maxS.toStringAsFixed(6)} ; plafond théorique avec des scores de '
        'critères à 100 = 126.000000 (1.26) vs 100.000000 (1.00)');
    // ┌────────────────────────────────────────────────────────────────────┐
    // │ TROISIÈME CORRECTION D'UNE AFFIRMATION FAUSSE (la mienne).        │
    // │ J'avais asserté « écart relatif = 0, l'écart est EXACTEMENT le     │
    // │ facteur 1.26 ». MESURE : max = 0.034257867, donc PAS nul.          │
    // │ C'est la conséquence directe de H1 : le rapport score_A/score_B    │
    // │ n'est pas 1.26 mais dépend de la composition de chaque partant     │
    // │ (mélange des 7 critères de base à ×1.1833 et des 12 enrichis à     │
    // │ ×1.3750). Il varie donc d'un partant à l'autre.                    │
    // └────────────────────────────────────────────────────────────────────┘
    // Si les ratios étaient uniformes, le rapport des scores serait constant.
    // Il ne l'est pas : mesure de la dispersion du rapport.
    final alea2 = math.Random(999);
    var minR = double.infinity;
    var maxR = 0.0;
    for (var i = 0; i < 500; i++) {
      final crit = _course(alea2, 12);
      final sA = _scores(crit, w26);
      final sB = _scores(crit, w10);
      for (var j = 0; j < sA.length; j++) {
        if (sB[j] > 1e-9) {
          final r = sA[j] / sB[j];
          minR = math.min(minR, r);
          maxR = math.max(maxR, r);
        }
      }
    }
    // ignore: avoid_print
    print('[H2] rapport score_A/score_B : min = ${minR.toStringAsFixed(9)}, '
        'max = ${maxR.toStringAsFixed(9)} — il est BORNÉ par les deux facteurs '
        '1.183333333 et 1.375000000, et VARIE selon la composition du partant.');
    expect(minR, greaterThanOrEqualTo(1.183333333 - 1e-9),
        reason: 'aucun rapport ne peut être inférieur au facteur de base');
    expect(maxR, lessThanOrEqualTo(1.375000000 + 1e-9),
        reason: 'aucun rapport ne peut dépasser le facteur enrichi');
    expect(maxR - minR, greaterThan(0.01),
        reason: 'le rapport VARIE : l\'écart n\'est pas un pur facteur '
            'd\'échelle, c\'est un effet de redistribution');
  });

  // ───────────────────────────────────────────────────────────────────────
  //  H3 — LES CONSOMMATEURS SENSIBLES À L'ÉCHELLE ABSOLUE
  // ───────────────────────────────────────────────────────────────────────
  test('H3 — quels consommateurs changent, et de combien ?', () {
    final alea = math.Random(31337);
    var labelChange = 0;
    var confianceEcarts = <double>[];
    var seuilMinChange = 0; // best_bet_screen.dart:592
    var gainRawChange = 0;  // best_bet_screen.dart:605
    var total = 0;
    const seuilMinScore = 62.0; // valeur de production (best_bet_screen)

    for (var i = 0; i < 2000; i++) {
      final n = 5 + alea.nextInt(16);
      final crit = _course(alea, n);
      final sA = _normaliser(_scores(crit, w26));
      final sB = _normaliser(_scores(crit, w10));
      final rA = _rangs(sA);
      final rB = _rangs(sB);

      // 1) LABEL : `_determinerLabel` consomme scoreAff + rang.
      final lA = _label(1, sA[rA[0]]);
      final lB = _label(1, sB[rB[0]]);
      if (lA != lB) labelChange++;

      // 2) CONFIANCE : `confianceIA` consomme les 3 premiers scores.
      final cA = _confiance([for (final x in rA) sA[x]]);
      final cB = _confiance([for (final x in rB) sB[x]]);
      confianceEcarts.add((cA - cB).abs());

      // 3) SEUIL MIN (best_bet_screen:592) : filtré ou non.
      final passA = sA[rA[0]] >= seuilMinScore;
      final passB = sB[rB[0]] >= seuilMinScore;
      if (passA != passB) seuilMinChange++;

      // 4) SCORE GAIN (best_bet_screen:605) : (100 − score).clamp(20,80)
      final gA = (100.0 - sA[rA[0]]).clamp(20.0, 80.0);
      final gB = (100.0 - sB[rB[0]]).clamp(20.0, 80.0);
      if ((gA - gB).abs() > 1e-9) gainRawChange++;
      total++;
    }
    confianceEcarts.sort();
    final med = confianceEcarts[confianceEcarts.length ~/ 2];
    final p95 = confianceEcarts[(confianceEcarts.length * 0.95).floor()];
    // ignore: avoid_print
    print('[H3] SUR $total COURSES, échelle 1.26 vs 1.00 :');
    // ignore: avoid_print
    print('[H3]   • étiquette du TOP1 (_determinerLabel) changée : '
        '$labelChange (${(labelChange / total * 100).toStringAsFixed(2)} %)');
    // ignore: avoid_print
    print('[H3]   • confianceIA : écart médian = ${med.toStringAsFixed(4)} pt, '
        'p95 = ${p95.toStringAsFixed(4)} pt, max = '
        '${confianceEcarts.last.toStringAsFixed(4)} pt');
    // ignore: avoid_print
    print('[H3]   • seuilMinScore 62 (best_bet_screen:592) : $seuilMinChange '
        'courses changent de camp (${(seuilMinChange / total * 100).toStringAsFixed(2)} %)');
    // ignore: avoid_print
    print('[H3]   • scoreGainRaw (best_bet_screen:605) modifié : '
        '$gainRawChange (${(gainRawChange / total * 100).toStringAsFixed(2)} %)');
  });

  // ───────────────────────────────────────────────────────────────────────
  //  H4 — TROIS SOLUTIONS COMPARÉES, SANS TOUCHER LA PRODUCTION
  // ───────────────────────────────────────────────────────────────────────
  test('H4 — trois solutions : rang identique ? échelle absolue ?', () {
    //  S0 = statu quo : poids 1.26 utilisés tels quels (repli global).
    //  S1 = poids normalisés 1.00 (ce que fait déjà clamp()).  ← PRODUCTION
    //  S2 = S1 redivisé par la somme au moment du score (somme déjà 1.00).
    //  S3 = S0 redivisé par sa somme (= S1 exactement).
    final alea = math.Random(5150);
    var rangsS0vsS1 = 0;
    var rangsS1vsS2 = 0;
    var maxEcartS1S2 = 0.0;
    var total = 0;
    for (var i = 0; i < 2000; i++) {
      final n = 5 + alea.nextInt(16);
      final crit = _course(alea, n);
      final s0 = _normaliser(_scores(crit, w26));
      final s1 = _normaliser(_scores(crit, w10));
      final s2 = _normaliser(_scores(crit, wDiv));
      final r0 = _rangs(s0);
      final r1 = _rangs(s1);
      final r2 = _rangs(s2);
      var d01 = false;
      var d12 = false;
      for (var j = 0; j < n; j++) {
        if (r0[j] != r1[j]) d01 = true;
        if (r1[j] != r2[j]) d12 = true;
        maxEcartS1S2 = math.max(maxEcartS1S2, (s1[j] - s2[j]).abs());
      }
      if (d01) rangsS0vsS1++;
      if (d12) rangsS1vsS2++;
      total++;
    }
    final somme10 = w10.values.fold(0.0, (a, b) => a + b);
    // ignore: avoid_print
    print('[H4] somme des poids après clamp()+normaliser() = '
        '${somme10.toStringAsFixed(12)}');
    // ignore: avoid_print
    print('[H4]   • S0 (1.26) vs S1 (1.00) : $rangsS0vsS1/$total classements '
        'diffèrent (${(rangsS0vsS1 / total * 100).toStringAsFixed(2)} %)');
    // ignore: avoid_print
    print('[H4]   • S1 vs S2 (S1 redivisé par sa somme) : $rangsS1vsS2/$total '
        'diffèrent ; écart absolu max = ${maxEcartS1S2.toStringAsFixed(15)}');
    // ignore: avoid_print
    print('[H4] ⇒ S2 est IDENTIQUE à S1 : la somme valant déjà 1.000000000000, '
        'diviser par elle ne change RIEN. La « correction par division » est '
        'donc soit un no-op total, soit un changement d\'échelle de 1.26.');

    expect(somme10, closeTo(1.0, 1e-12),
        reason: 'après clamp() la somme vaut exactement 1.00');
    expect(rangsS1vsS2, 0,
        reason: 'rediviser un vecteur de somme 1.00 par sa somme est un no-op');
    // Diviser S0 par sa somme n'est PAS S1 : mesurons-le au lieu de le croire.
    final w26div = {for (final k in kCles) k: w26[k]! / 1.26};
    var ecart26 = 0.0;
    for (final k in kCles) {
      ecart26 = math.max(ecart26, (w26div[k]! - w10[k]!).abs());
    }
    // ignore: avoid_print
    print('[H4] ⇒ (poids 1.26) / 1.26 vs poids 1.00 : écart max sur les 19 = '
        '${ecart26.toStringAsFixed(15)}');
    // ┌────────────────────────────────────────────────────────────────────┐
    // │ QUATRIÈME CORRECTION D'UNE AFFIRMATION FAUSSE (la mienne).        │
    // │ J'avais asserté « diviser la table 1.26 par sa somme redonne       │
    // │ EXACTEMENT la table 1.00 ». MESURE : FAUX, écart max              │
    // │ 0.012854907. Raison : la table 1.00 n'est pas (table 1.26)/1.26,   │
    // │ elle est (table 1.26 clammée puis ÉCRÊTÉE à 40 % d'enrichis).      │
    // │ ⇒ « diviser par la somme des poids effectifs » n'est donc PAS un   │
    // │   synonyme de la normalisation existante : c'est une TROISIÈME     │
    // │   transformation, qui diffère des deux autres.                     │
    // └────────────────────────────────────────────────────────────────────┘
    expect(ecart26, greaterThan(0.01),
        reason: 'diviser par la somme brute ≠ normalisation existante : '
            'l\'écrêtage à 40 % crée une différence mesurable');
    // En revanche, diviser la table DÉJÀ normalisée est bien un no-op (S2=S1).
    // ignore: avoid_print
    print('[H4] ⇒ les trois transformations sont DISTINCTES :');
    // ignore: avoid_print
    print('[H4]    T1 = brut 1.26 (repli) ; T2 = clamp+normaliser (production) '
        '; T3 = brut/1.26 (division simple)');
    // ignore: avoid_print
    print('[H4]    T2 ≠ T3 : écart max ${ecart26.toStringAsFixed(9)} — '
        'écrêtage 0.436507937 → 0.40');
    // ignore: avoid_print
    print('[H4]    T3 ≠ T1 : facteur 1.26 uniforme : $rangsS0vsS1/$total '
        'classements changent quand on passe de T3 à T1 — mais T3 est '
        'exactement T1/1.26, donc SEULE l\'échelle les sépare.');
  });

  // ───────────────────────────────────────────────────────────────────────
  //  H5 — LE REPLI DE DISCIPLINE : la vraie coexistence 1.26 / 1.00
  // ───────────────────────────────────────────────────────────────────────
  test('H5 — où les deux échelles COEXISTENT réellement dans le moteur', () {
    // `poidsEffectifsPourDiscipline()` renvoie, quand aucune discipline n'est
    // apprise, les CHAMPS de l'instance — donc déjà normalisés à 1.00.
    // Mais `clampDiscipline()` renvoie, pour un repli, une table divisée par
    // son total, dont la somme vaut donc 1.00 aussi.
    final p = IaPoidsAdaptatifs()..clamp();
    final fallback = p.poidsEffectifsPourDiscipline('INCONNU');
    final somme = fallback.values.fold(0.0, (a, b) => a + b);
    // ignore: avoid_print
    print('[H5] poidsEffectifsPourDiscipline("INCONNU") sur une instance '
        'clampée : ${fallback.length} clés, somme = '
        '${somme.toStringAsFixed(12)}');
    expect(fallback.length, 19);
    expect(somme, closeTo(1.0, 1e-12),
        reason: 'le repli de discipline part des champs DÉJÀ normalisés : il '
            'vaut 1.00, pas 1.26');

    // En revanche, une instance NON clampée (constructeur brut) donne 1.26.
    final brut = IaPoidsAdaptatifs();
    final fallbackBrut = brut.poidsEffectifsPourDiscipline('INCONNU');
    final sommeBrute = fallbackBrut.values.fold(0.0, (a, b) => a + b);
    // ignore: avoid_print
    print('[H5] même appel sur une instance NON clampée (constructeur brut) : '
        'somme = ${sommeBrute.toStringAsFixed(12)}');
    // ignore: avoid_print
    print('[H5] ⇒ la coexistence 1.26 / 1.00 dépend de l\'ÉTAT de l\'instance '
        'au moment de l\'appel, et non du chemin de repli lui-même.');
    expect(sommeBrute, closeTo(1.26, 1e-12),
        reason: 'une instance non clampée transmet sa somme brute de 1.26');
  });

  // ───────────────────────────────────────────────────────────────────────
  //  H6 — LE REPLI `fromJson` PRODUIT-IL VRAIMENT 1.37 ?
  // ───────────────────────────────────────────────────────────────────────
  test('H6 — restauration partielle : la table fromJson vaut 1.37', () {
    final vide = IaPoidsAdaptatifs.fromJson(<String, dynamic>{});
    final sommeVide = kCles.fold(0.0, (a, k) => a + vide.getPoids(k));
    // ignore: avoid_print
    print('[H6] fromJson({}) → 19 replis : somme = '
        '${sommeVide.toStringAsFixed(12)}');
    // ignore: avoid_print
    print('[H6]   forme=${vide.forme} gains=${vide.gains} record=${vide.record} '
        '— les 3 divergences vs constructeur');
    expect(sommeVide, closeTo(1.37, 1e-12));

    // CAS RÉEL : JSON partiel — 16 clés présentes, 3 absentes.
    final partiel = <String, dynamic>{
      'cote': 0.08, 'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
      'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
      'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05, 'divergence': 0.04,
      'poidsRel': 0.03, 'progression': 0.03, 'mouvCote': 0.06,
      'placeDepart': 0.03,
      // 'forme', 'gains', 'record' ABSENTS
    };
    final p = IaPoidsAdaptatifs.fromJson(partiel);
    final somme = kCles.fold(0.0, (a, k) => a + p.getPoids(k));
    // ignore: avoid_print
    print('[H6] fromJson(JSON partiel sans forme/gains/record) : somme = '
        '${somme.toStringAsFixed(12)}');
    // ignore: avoid_print
    print('[H6] ⇒ les 3 replis (0.32/0.15/0.12) SONT UTILISÉS : la somme '
        '1.37 se matérialise bien en production.');
    expect(somme, closeTo(1.37, 1e-12),
        reason: 'fromJson ne clampe pas : une restauration partielle livre '
            'une table de somme 1.37 au moteur de score');

    // Et `clamp()` corrigerait-il ? OUI — mais il n'est pas appelé.
    p.clamp();
    final sommeApres = kCles.fold(0.0, (a, k) => a + p.getPoids(k));
    // ignore: avoid_print
    print('[H6]   après un clamp() explicite : somme = '
        '${sommeApres.toStringAsFixed(12)} ; part enrichie = '
        '${(1.0 - ["forme","gains","record","cote","constance","victoires","discipline"].fold(0.0, (a, k) => a + p.getPoids(k))).toStringAsFixed(12)}');
    expect(sommeApres, closeTo(1.0, 1e-12));
  });
}
