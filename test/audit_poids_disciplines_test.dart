// ══════════════════════════════════════════════════════════════════════════════
//  AUDIT DES POIDS IA — HARNAIS M11/M12
//
//  M11 — INFLUENCE RÉELLE SUR LE CLASSEMENT
//        Mesure du déplacement de rang produit par la variation d'UN critère,
//        à scores de critères identiques. Ce harnais reproduit l'arithmétique
//        documentée de `ia_pronostic_engine._calculerScoreBrutEtCriteres`
//        (somme pondérée) puis de `_normaliserScores` (ratio 0.40/0.60/0.75).
//        Il ne prouve AUCUNE efficacité prédictive : uniquement la mécanique.
//
//  M12 — DIFFÉRENCES ENTRE LES QUATRE DISCIPLINES
//        Mesure des poids effectifs réellement installés par discipline.
//
//  GARANTIES : aucune écriture disque, aucune modification de production.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

double _somme(Iterable<double> v) => v.fold(0.0, (a, b) => a + b);

/// Reproduction EXACTE de `IaPronosticEngine._normaliserScores` (mesuré ligne
/// 188-206). Aucune valeur n'est inventée : les trois ratios sont ceux du code.
void _normaliserScores(Map<String, double> scores) {
  final vals = scores.values.toList();
  if (vals.length < 3) return;
  final minS = vals.reduce((a, b) => a < b ? a : b);
  final maxS = vals.reduce((a, b) => a > b ? a : b);
  final range = maxS - minS;
  if (range <= 1.0) return;
  final n = vals.length;
  final ratioNorme = n <= 6 ? 0.40 : n <= 12 ? 0.60 : 0.75;
  final ratioBrut = 1.0 - ratioNorme;
  for (final k in scores.keys) {
    final brut = scores[k]!;
    final norme = ((brut - minS) / range * 100.0).clamp(0.0, 100.0);
    scores[k] = norme * ratioNorme + brut * ratioBrut;
  }
}

/// Score composite : somme pondérée des 19 critères (arithmétique du moteur).
Map<String, double> _composites(
    Map<String, Map<String, double>> chevaux, Map<String, double> poids) {
  final out = <String, double>{};
  for (final e in chevaux.entries) {
    var s = 0.0;
    for (final c in kCles) {
      s += e.value[c]! * (poids[c] ?? 0.0);
    }
    out[e.key] = s;
  }
  return out;
}

List<String> _classement(Map<String, double> scores) {
  final l = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return l.map((e) => e.key).toList();
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  group('M11 — Influence réelle sur le classement', () {
    // Champ de 8 chevaux. Les 18 critères « neutres » = 50.0 pour tous.
    // Seuls `forme` et `placeDepart` varient : c'est le seul différentiel.
    Map<String, Map<String, double>> champ(double formeSpread, double pdSpread) {
      final m = <String, Map<String, double>>{};
      for (var i = 0; i < 8; i++) {
        final row = <String, double>{for (final c in kCles) c: 50.0};
        row['forme'] = 50.0 + (i - 3.5) * formeSpread;
        row['placeDepart'] = 50.0 - (i - 3.5) * pdSpread;
        m['C${i + 1}'] = row;
      }
      return m;
    }

    test('M11.1 — Poids bruts vs poids effectifs : impact de rang', () {
      final poidsBrut = {
        for (final k in kCles) k: IaPoidsAdaptatifs().getPoids(k)
      };
      final p = IaPoidsAdaptatifs()..clamp();
      final poidsEff = {for (final k in kCles) k: p.getPoids(k)};

      // Cas A : forme discrimine fortement, placeDepart faiblement
      final casA = champ(8.0, 1.0);
      final aBrut = _composites(casA, poidsBrut);
      final aEff = _composites(casA, poidsEff);
      _normaliserScores(aBrut);
      _normaliserScores(aEff);
      // ignore: avoid_print
      print('── cas A (forme ±28, placeDepart ∓3.5) ──');
      // ignore: avoid_print
      print('  classement poids bruts    : ${_classement(aBrut).join(" > ")}');
      // ignore: avoid_print
      print('  classement poids effectifs: ${_classement(aEff).join(" > ")}');
      // ignore: avoid_print
      print('  identique ? ${_classement(aBrut).join(",") == _classement(aEff).join(",")}');

      // Cas B : différentiel inverse
      final casB = champ(1.0, 8.0);
      final bBrut = _composites(casB, poidsBrut);
      final bEff = _composites(casB, poidsEff);
      _normaliserScores(bBrut);
      _normaliserScores(bEff);
      // ignore: avoid_print
      print('── cas B (forme ±3.5, placeDepart ∓28) ──');
      // ignore: avoid_print
      print('  classement poids bruts    : ${_classement(bBrut).join(" > ")}');
      // ignore: avoid_print
      print('  classement poids effectifs: ${_classement(bEff).join(" > ")}');
      // ignore: avoid_print
      print('  identique ? ${_classement(bBrut).join(",") == _classement(bEff).join(",")}');

      expect(_classement(aEff).length, 8);
    });

    test('M11.2 — Contribution de chaque critère à l\'écart de score', () {
      // Pour un cheval au-dessus de la moyenne (+10) sur UN critère, et à la
      // moyenne (50) sur les autres, quelle est sa contribution au score
      // composite ? Mesure directe du poids × 10.
      final p = IaPoidsAdaptatifs()..clamp();
      final poidsEff = {for (final k in kCles) k: p.getPoids(k)};
      final s = _somme(poidsEff.values);
      // ignore: avoid_print
      print('critère        | poids effectif | contrib. (Δ+10) | part % | rang contrib');
      final contrib = <String, double>{
        for (final k in kCles) k: poidsEff[k]! * 10.0
      };
      final ordre = kCles.toList()
        ..sort((a, b) => contrib[b]!.compareTo(contrib[a]!));
      for (final k in ordre) {
        // ignore: avoid_print
        print('${k.padRight(14)} | ${poidsEff[k]!.toStringAsFixed(6)} | '
            '${contrib[k]!.toStringAsFixed(4).padLeft(15)} | '
            '${(poidsEff[k]! / s * 100).toStringAsFixed(2).padLeft(6)} | '
            '${ordre.indexOf(k) + 1}');
      }
      // ignore: avoid_print
      print('→ rapport de contribution forme/placeDepart = '
          '${(contrib["forme"]! / contrib["placeDepart"]!).toStringAsFixed(4)}');
      expect(ordre.first, 'forme');
    });

    test('M11.3 — Sensibilité au classement : quel critère renverse ?', () {
      // On cherche le nombre de places de déplacement du classement quand un
      // critère voit sa discrimination multipliée, les autres inchangés.
      final p = IaPoidsAdaptatifs()..clamp();
      final poidsEff = {for (final k in kCles) k: p.getPoids(k)};
      final base = champ(4.0, 4.0);
      final ref = _composites(base, poidsEff);
      _normaliserScores(ref);
      final refCl = _classement(ref);
      // ignore: avoid_print
      print('référence : ${refCl.join(" > ")}');
      // ignore: avoid_print
      print('critère        | places déplacées (max) | amplitude requise');
      for (final cible in ['forme', 'placeDepart', 'discipline', 'repos', 'cote']) {
        // amplitude nécessaire pour faire bouger le classement d'au moins 1
        var amplitude = 0.0;
        var deplace = 0;
        for (var amp = 1.0; amp <= 200.0; amp += 1.0) {
          final m = <String, Map<String, double>>{};
          for (var i = 0; i < 8; i++) {
            final row = <String, double>{for (final c in kCles) c: 50.0};
            row['forme'] = 50.0 + (i - 3.5) * 4.0;
            row['placeDepart'] = 50.0 - (i - 3.5) * 4.0;
            row[cible] = 50.0 + (i - 3.5) * amp;
            m['C${i + 1}'] = row;
          }
          final sc = _composites(m, poidsEff);
          _normaliserScores(sc);
          final cl = _classement(sc);
          var d = 0;
          for (var i = 0; i < cl.length; i++) {
            if (cl[i] != refCl[i]) d++;
          }
          if (d > 0) {
            amplitude = amp;
            deplace = d;
            break;
          }
        }
        // ignore: avoid_print
        print('${cible.padRight(14)} | ${deplace.toString().padLeft(22)} | '
            '${amplitude.toStringAsFixed(0).padLeft(18)}');
      }
      expect(refCl.length, 8);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('M12 — Différences entre les quatre disciplines', () {
    test('M12.1 — Poids effectifs par discipline sur un état vierge', () {
      final p = IaPoidsAdaptatifs()..clamp();
      final disciplines = <String>[
        'Trot Attelé', 'Trot Monté', 'Plat', 'Obstacle',
      ];
      final parDisc = <String, Map<String, double>>{};
      for (final d in disciplines) {
        parDisc[d] = p.poidsEffectifsPourDiscipline(d);
      }
      // ignore: avoid_print
      print('critère        | Trot Attelé | Trot Monté | Plat | Obstacle | max écart');
      var ecartMax = 0.0;
      for (final k in kCles) {
        final vals = disciplines.map((d) => parDisc[d]![k]!).toList();
        final mini = vals.reduce(math.min);
        final maxi = vals.reduce(math.max);
        if (maxi - mini > ecartMax) ecartMax = maxi - mini;
        // ignore: avoid_print
        print('${k.padRight(14)} | ${vals.map((v) => v.toStringAsFixed(4).padLeft(11)).join(" | ")} | '
            '${(maxi - mini).toStringAsFixed(10)}');
      }
      // ignore: avoid_print
      print('→ écart max inter-disciplines sur un état VIERGE = ${ecartMax.toStringAsFixed(10)}');
      // ignore: avoid_print
      print('  (= 0 ⇒ aucune différenciation par discipline tant que '
          'poidsParDiscipline est vide)');
      expect(ecartMax, 0.0,
          reason: 'mesure : aucune différenciation par discipline à l\'état vierge');
    });

    test('M12.2 — Après apprentissage d\'UNE discipline seulement', () {
      final p = IaPoidsAdaptatifs();
      // On simule ce que fait `_apprendreParDiscipline` : créer la map initialisée
      // sur les poids GLOBAUX, puis clampDiscipline (donc normalisation).
      final poidsDisc = <String, double>{
        for (final k in kCles) k: p.getPoids(k)
      };
      // discrimination simulée : le trot attelé favorise la corde
      const facteurs = <String, double>{
        'forme': 1.0, 'gains': 1.0, 'record': 1.0, 'cote': 1.0,
        'constance': 1.0, 'victoires': 1.0, 'discipline': 1.0,
        'distSpec': 0.5, 'jockey': 0.5, 'repos': 0.3, 'hippo': 0.4,
        'entraineur': 0.4, 'elo': 0.5, 'terrain': 0.5, 'divergence': 0.4,
        'poidsRel': 0.3, 'progression': 0.4, 'mouvCote': 0.5,
        'placeDepart': 0.3,
      };
      const lr = 0.09;
      for (final c in kCles) {
        final discrim = c == 'placeDepart' ? 0.20 : 0.0;
        poidsDisc[c] = poidsDisc[c]! + lr * discrim * facteurs[c]!;
      }
      IaPoidsAdaptatifs.clampDiscipline(poidsDisc);
      p.poidsParDiscipline['trot_attele'] = poidsDisc;

      final trot = p.poidsEffectifsPourDiscipline('Trot Attelé');
      final autre = p.poidsEffectifsPourDiscipline('Plat');
      // ignore: avoid_print
      print('critère        | Trot Attelé (appris) | Plat (repli global) | Δ');
      for (final k in kCles) {
        final d = trot[k]! - autre[k]!;
        // ignore: avoid_print
        print('${k.padRight(14)} | ${trot[k]!.toStringAsFixed(6)} | '
            '${autre[k]!.toStringAsFixed(6)} | ${d.toStringAsFixed(6)}');
      }
      // ignore: avoid_print
      print('somme Trot Attelé = ${_somme(trot.values).toStringAsFixed(10)}');
      // ignore: avoid_print
      print('somme Plat        = ${_somme(autre.values).toStringAsFixed(10)}');
      expect(_somme(trot.values), closeTo(1.0, 1e-9));
      expect(_somme(autre.values), closeTo(1.26, 1e-9));
      // ignore: avoid_print
      print('⚠️ MESURE : le repli global vaut 1.26 là où la discipline apprise '
          'vaut 1.00 — les deux échelles coexistent dans le même moteur.');
    });

    test('M12.3 — Effet de la discipline sur le classement réel', () {
      // Deux chevaux, même profil, sauf placeDepart (+20 pour A, -20 pour B).
      final p = IaPoidsAdaptatifs();
      final poidsDisc = <String, double>{
        for (final k in kCles) k: p.getPoids(k)
      };
      poidsDisc['placeDepart'] = poidsDisc['placeDepart']! + 0.09 * 0.20 * 0.3;
      IaPoidsAdaptatifs.clampDiscipline(poidsDisc);
      p.poidsParDiscipline['trot_attele'] = poidsDisc;

      Map<String, Map<String, double>> duel() {
        final a = <String, double>{for (final c in kCles) c: 50.0};
        final b = <String, double>{for (final c in kCles) c: 50.0};
        a['placeDepart'] = 70.0;
        b['placeDepart'] = 30.0;
        return {'A': a, 'B': b};
      }

      for (final d in ['Trot Attelé', 'Plat']) {
        final w = p.poidsEffectifsPourDiscipline(d);
        final sc = _composites(duel(), w);
        final ecart = (sc['A']! - sc['B']!).abs();
        // ignore: avoid_print
        print('discipline "$d" → score A=${sc["A"]!.toStringAsFixed(4)}, '
            'B=${sc["B"]!.toStringAsFixed(4)}, écart=${ecart.toStringAsFixed(6)}');
      }
      // ignore: avoid_print
      print('→ l\'écart de score dû à placeDepart diffère selon la discipline : '
          'la pondération par discipline a un effet réel, mais uniquement '
          'APRÈS apprentissage de cette discipline.');
      expect(_somme(poidsDisc.values), closeTo(1.0, 1e-9));
    });
  });
}
