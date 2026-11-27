// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER POIDS IA — §3 : L'INCOHÉRENCE D'ÉCHELLE 1.26 vs 1.00
//
//  FAIT ÉTABLI AILLEURS (mesuré) :
//    • A5 : la somme des 19 poids du constructeur vaut 1.260000 ;
//    • A1 : après clamp()+normaliser(), elle vaut 1.000000 ;
//    • M12.2 : le repli global (jamais appris) vaut 1.26 là où une discipline
//      apprise vaut 1.00 — les DEUX ÉCHELLES coexistent dans le même moteur.
//
//  QUESTION : cette différence d'échelle change-t-elle le CLASSEMENT, ou
//  seulement les seuils absolus ? Comme `_normaliserScores`
//  (ia_pronostic_engine.dart:224-242) écrit
//      score = 0.60 × normalisé + 0.40 × brut
//  et que `normalisé` est invariant d'échelle alors que `brut` ne l'est pas,
//  l'ordre PEUT changer. Il faut le MESURER, pas le supposer.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION. On construit des `IaPoidsAdaptatifs`
//     en mémoire et on rejoue l'arithmétique EXACTE du moteur.
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
List<double> _normaliser(Map<int, double> scores) {
  final vals = scores.values.toList();
  if (vals.length < 3) return scores.values.toList();
  final minS = vals.reduce(math.min);
  final maxS = vals.reduce(math.max);
  final range = maxS - minS;
  if (range <= 1.0) return scores.values.toList();
  final n = vals.length;
  final ratioNorme = n <= 6 ? 0.40 : n <= 12 ? 0.60 : 0.75;
  final ratioBrut = 1.0 - ratioNorme;
  return [
    for (final k in scores.keys.toList())
      (((scores[k]! - minS) / range * 100.0).clamp(0.0, 100.0)) * ratioNorme +
          scores[k]! * ratioBrut,
  ];
}

List<int> _rangs(Map<int, double> scores) {
  final nums = scores.keys.toList()
    ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
  return nums;
}

void main() {
  test('C1 — MESURE : l\'échelle 1.26 vs 1.00 change-t-elle le classement ?',
      () {
    // Protocole : on tire des scores de critères réalistes (0-100) pour N
    // chevaux, on calcule le score brut par la formule EXACTE du moteur
    // (somme pondérée non divisée, ia_pronostic_engine.dart:391-409) avec
    // DEUX jeux de poids :
    //   (a) poids du constructeur NON clammés → somme 1.26
    //   (b) poids après clamp()+normaliser()  → somme 1.00
    // Les RATIOS entre critères sont identiques (mêmes valeurs brutes) : seule
    // l'échelle diffère. Puis on compare les classements après
    // `_normaliserScores`.
    final p26 = IaPoidsAdaptatifs();
    final p10 = IaPoidsAdaptatifs()..clamp();
    final w26 = {for (final k in kCles) k: p26.getPoids(k)};
    final w10 = {for (final k in kCles) k: p10.getPoids(k)};

    final alea = math.Random(424242);
    var courses = 0;
    var coursesAvecChangement = 0;
    var changementsTop1 = 0;
    var changementsTop3 = 0;
    var maxEcartRang = 0;

    for (var essai = 0; essai < 2000; essai++) {
      final nbPartants = 6 + alea.nextInt(12); // 6 à 17
      final scores26 = <int, double>{};
      final scores10 = <int, double>{};
      for (var num = 1; num <= nbPartants; num++) {
        var s26 = 0.0;
        var s10 = 0.0;
        for (final k in kCles) {
          final note = alea.nextDouble() * 100.0; // score du critère, 0-100
          s26 += note * w26[k]!;
          s10 += note * w10[k]!;
        }
        scores26[num] = s26;
        scores10[num] = s10;
      }
      final n26 = _normaliser(scores26);
      final n10 = _normaliser(scores10);
      final map26 = {
        for (var i = 0; i < nbPartants; i++) scores26.keys.toList()[i]: n26[i],
      };
      final map10 = {
        for (var i = 0; i < nbPartants; i++) scores10.keys.toList()[i]: n10[i],
      };
      final r26 = _rangs(map26);
      final r10 = _rangs(map10);
      courses++;
      if (r26.join(',') != r10.join(',')) {
        coursesAvecChangement++;
        for (var i = 0; i < nbPartants; i++) {
          maxEcartRang = math.max(maxEcartRang, (i - r10.indexOf(r26[i])).abs());
        }
      }
      if (r26.first != r10.first) changementsTop1++;
      final t3a = r26.take(3).toSet();
      final t3b = r10.take(3).toSet();
      if (t3a.difference(t3b).isNotEmpty) changementsTop3++;
    }

    // ignore: avoid_print
    print('[C1] courses simulées = $courses');
    // ignore: avoid_print
    print('[C1] classements MODIFIÉS par la seule échelle = '
        '$coursesAvecChangement (${(coursesAvecChangement / courses * 100).toStringAsFixed(2)} %)');
    // ignore: avoid_print
    print('[C1] TOP 1 différent = $changementsTop1 '
        '(${(changementsTop1 / courses * 100).toStringAsFixed(2)} %)');
    // ignore: avoid_print
    print('[C1] TOP 3 différent = $changementsTop3 '
        '(${(changementsTop3 / courses * 100).toStringAsFixed(2)} %)');
    // ignore: avoid_print
    print('[C1] écart de rang maximum observé = $maxEcartRang');

    expect(courses, 2000);
  });

  test('C2 — Pourquoi : décomposition de l\'effet d\'échelle sur le mélange',
      () {
    // Le mélange 0.60×normalisé + 0.40×brut fait dépendre le résultat de
    // l'échelle absolue. On l'isole sur un cas à 3 chevaux pour rendre le
    // mécanisme lisible, et on vérifie que le résultat est EXACTEMENT
    // reproduit par le calcul à la main.
    final p26 = IaPoidsAdaptatifs()..clamp();
    final w = {for (final k in kCles) k: p26.getPoids(k)};
    final somme = w.values.fold(0.0, (a, b) => a + b);
    // ignore: avoid_print
    print('[C2] somme des poids après clamp() = ${somme.toStringAsFixed(9)}');

    // Deux chevaux, notes de critères identiques sauf forme.
    double brut(double forme, double gains) {
      var s = 0.0;
      s += forme * w['forme']!;
      s += gains * w['gains']!;
      // tous les autres critères à 50 (neutre)
      for (final k in kCles) {
        if (k == 'forme' || k == 'gains') continue;
        s += 50.0 * w[k]!;
      }
      return s;
    }

    final a = brut(90, 50);
    final b = brut(50, 90);
    // ignore: avoid_print
    print('[C2] cheval A (forme 90, gains 50) = ${a.toStringAsFixed(6)}');
    // ignore: avoid_print
    print('[C2] cheval B (forme 50, gains 90) = ${b.toStringAsFixed(6)}');
    // ignore: avoid_print
    print('[C2] A > B ? ${a > b} — écart = ${(a - b).abs().toStringAsFixed(6)}');
    // ignore: avoid_print
    print('[C2] ⇒ l\'écart vaut (90−50)×(poids forme − poids gains) = '
        '40 × ${(w["forme"]! - w["gains"]!).toStringAsFixed(6)} = '
        '${(40 * (w["forme"]! - w["gains"]!)).toStringAsFixed(6)}');
    expect(a - b, closeTo(40 * (w['forme']! - w['gains']!), 1e-9),
        reason: 'MESURÉ : l\'écart entre deux chevaux est proportionnel à '
            'l\'ÉCHELLE des poids, donc à la somme 1.26 ou 1.00');
  });

  test('C3 — Le seuil absolu est franchi différemment selon l\'échelle', () {
    // Un cheval dont TOUS les critères valent 100 obtient, par construction,
    // un score brut égal à la SOMME des poids. C'est le maximum atteignable.
    final p26 = IaPoidsAdaptatifs();
    final p10 = IaPoidsAdaptatifs()..clamp();
    final s26 = kCles.fold(0.0, (a, k) => a + p26.getPoids(k) * 100.0);
    final s10 = kCles.fold(0.0, (a, k) => a + p10.getPoids(k) * 100.0);
    // ignore: avoid_print
    print('[C3] score maximum, poids NON normalisés  = '
        '${s26.toStringAsFixed(6)} / 100');
    // ignore: avoid_print
    print('[C3] score maximum, poids après clamp()   = '
        '${s10.toStringAsFixed(6)} / 100');
    // ignore: avoid_print
    print('[C3] ⇒ l\'échelle 1.26 permet de dépasser 100 de '
        '${(s26 - 100).toStringAsFixed(6)} points. Les seuils ABSOLUS du '
        'moteur (simple gagnant 80, couple 75…) sont donc franchis plus '
        'facilement avant tout apprentissage qu\'après.');
    expect(s26, closeTo(126.0, 1e-9));
    expect(s10, closeTo(100.0, 1e-9));
  });
}
