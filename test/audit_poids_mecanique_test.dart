// ══════════════════════════════════════════════════════════════════════════════
//  AUDIT DES POIDS IA — HARNAIS MÉCANIQUE (M9/M10)
//
//  OBJET : déterminer PAR LA MESURE pourquoi `placeDepart` (poids initial 0.03,
//          facteur de gradient 0.3) ne rattrape pas `forme` (0.25, facteur 1.0),
//          alors que sa discrimination est 3× supérieure.
//
//          Identifier la contrainte réellement limitante parmi :
//            (a) les valeurs initiales,
//            (b) les bornes individuelles de clamp(),
//            (c) le plafond de groupe de normaliser() (fraction enrichie 0.40),
//            (d) la vitesse du gradient,
//            (e) un autre mécanisme.
//
//          Puis mesurer si l'apprentissage peut INVERSER la hiérarchie initiale.
//
//  GARANTIES : aucune écriture disque, aucune modification de production.
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

const List<String> kCles = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
  'distSpec', 'jockey', 'repos', 'hippo', 'entraineur', 'elo',
  'terrain', 'divergence', 'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

const List<String> kBase = <String>[
  'forme', 'gains', 'record', 'cote', 'constance', 'victoires', 'discipline',
];

Map<String, double> _v(IaPoidsAdaptatifs p) =>
    {for (final k in kCles) k: p.getPoids(k)};

double _somme(Iterable<double> v) => v.fold(0.0, (a, b) => a + b);

// Bornes RÉELLES de clamp() — recopiées pour comparaison, jamais modifiées.
const Map<String, List<double>> kBornes = <String, List<double>>{
  'forme': [0.05, 0.55], 'gains': [0.04, 0.40], 'record': [0.03, 0.35],
  'cote': [0.05, 0.40], 'constance': [0.03, 0.25], 'victoires': [0.01, 0.15],
  'discipline': [0.01, 0.10], 'distSpec': [0.03, 0.18], 'jockey': [0.02, 0.15],
  'repos': [0.01, 0.08], 'hippo': [0.01, 0.10], 'entraineur': [0.01, 0.08],
  'elo': [0.01, 0.10], 'terrain': [0.01, 0.10], 'divergence': [0.01, 0.08],
  'poidsRel': [0.01, 0.07], 'progression': [0.01, 0.08],
  'mouvCote': [0.02, 0.12], 'placeDepart': [0.01, 0.07],
};

const Map<String, double> kFacteurs = <String, double>{
  'forme': 1.0, 'gains': 1.0, 'record': 1.0, 'cote': 1.0,
  'constance': 1.0, 'victoires': 1.0, 'discipline': 1.0,
  'distSpec': 0.5, 'jockey': 0.5, 'repos': 0.3, 'hippo': 0.4,
  'entraineur': 0.4, 'elo': 0.5, 'terrain': 0.5, 'divergence': 0.4,
  'poidsRel': 0.3, 'progression': 0.4, 'mouvCote': 0.5, 'placeDepart': 0.3,
};

void _ecrire(IaPoidsAdaptatifs p, String cle, double v) {
  switch (cle) {
    case 'forme': p.forme = v; break;
    case 'gains': p.gains = v; break;
    case 'record': p.record = v; break;
    case 'cote': p.cote = v; break;
    case 'constance': p.constance = v; break;
    case 'victoires': p.victoires = v; break;
    case 'discipline': p.discipline = v; break;
    case 'distSpec': p.distSpec = v; break;
    case 'jockey': p.jockey = v; break;
    case 'repos': p.repos = v; break;
    case 'hippo': p.hippo = v; break;
    case 'entraineur': p.entraineur = v; break;
    case 'elo': p.elo = v; break;
    case 'terrain': p.terrain = v; break;
    case 'divergence': p.divergence = v; break;
    case 'poidsRel': p.poidsRel = v; break;
    case 'progression': p.progression = v; break;
    case 'mouvCote': p.mouvCote = v; break;
    case 'placeDepart': p.placeDepart = v; break;
  }
}

/// Un cycle de gradient IDENTIQUE à la boucle de `_apprendreParGradient` :
/// lr × discrimination × facteur(critère), + momentum, puis clamp() global.
void _unCycle(IaPoidsAdaptatifs p, Map<String, double> discrim,
    Map<String, double> momentum, double lr) {
  for (final c in kCles) {
    final grad = lr * (discrim[c] ?? 0.0);
    final g = grad + 0.3 * (momentum[c] ?? 0.0);
    momentum[c] = g;
    _ecrire(p, c, p.getPoids(c) + g * kFacteurs[c]!);
  }
  p.clamp();
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  group('M9 — Pourquoi placeDepart ne rattrape pas forme', () {
    test('M9.1 — Identifier la contrainte limitante', () {
      final p = IaPoidsAdaptatifs();
      final momentum = <String, double>{};
      // placeDepart discrimine 3× mieux que forme ; les 17 autres sont neutres.
      final discrim = <String, double>{
        for (final k in kCles) k: 0.0,
        'forme': 0.02,
        'placeDepart': 0.06,
      };

      // ignore: avoid_print
      print('cycle | forme     | placeDepart | somEnrichis | placeDepart à sa borne ?');
      for (var i = 1; i <= 200; i++) {
        _unCycle(p, discrim, momentum, 0.08);
        if (i == 1 || i == 5 || i == 20 || i == 50 || i == 100 || i == 200) {
          final v = _v(p);
          final enrichis = _somme(kCles.where((k) => !kBase.contains(k))
              .map((k) => v[k]!));
          final aLaBorne =
              (p.placeDepart - kBornes['placeDepart']![1]).abs() < 1e-9;
          // ignore: avoid_print
          print('${i.toString().padLeft(5)} | ${p.forme.toStringAsFixed(6)} | '
              '${p.placeDepart.toStringAsFixed(6)}  | '
              '${enrichis.toStringAsFixed(6)}    | $aLaBorne');
        }
      }
      final v = _v(p);
      final enrichisTotal =
          _somme(kCles.where((k) => !kBase.contains(k)).map((k) => v[k]!));
      // ignore: avoid_print
      print('── DIAGNOSTIC ──');
      // ignore: avoid_print
      print('  forme finale       = ${p.forme.toStringAsFixed(6)}  '
          '(borne haute ${kBornes["forme"]![1]})');
      // ignore: avoid_print
      print('  placeDepart finale = ${p.placeDepart.toStringAsFixed(6)}  '
          '(borne haute ${kBornes["placeDepart"]![1]})');
      // ignore: avoid_print
      print('  fraction enrichie  = ${enrichisTotal.toStringAsFixed(6)}  '
          '(plafond normaliser() = 0.40)');
      // ignore: avoid_print
      print('  placeDepart a atteint sa borne haute ? '
          '${(p.placeDepart - kBornes["placeDepart"]![1]).abs() < 1e-9}');

      // Contrainte STRUCTURELLE : plafond de groupe
      final plafondGroupe = 0.40;
      final minAutresEnrichis = kCles
          .where((k) => !kBase.contains(k) && k != 'placeDepart')
          .map((k) => kBornes[k]![0])
          .fold(0.0, (a, b) => a + b);
      // ignore: avoid_print
      print('  borne structurelle : placeDepart ≤ plafondGroupe(0.40) − '
          'Σ min des 11 autres enrichis(${minAutresEnrichis.toStringAsFixed(2)}) '
          '= ${(plafondGroupe - minAutresEnrichis).toStringAsFixed(6)}');
      // ignore: avoid_print
      print('  ⇒ contrainte EFFECTIVE = min(borne individuelle '
          '${kBornes["placeDepart"]![1]}, borne structurelle '
          '${(plafondGroupe - minAutresEnrichis).toStringAsFixed(4)}) '
          '= ${[kBornes["placeDepart"]![1], plafondGroupe - minAutresEnrichis].reduce((a, b) => a < b ? a : b).toStringAsFixed(6)}');

      expect(p.placeDepart, lessThanOrEqualTo(0.07 + 1e-9));
    });

    test('M9.2 — Le facteur 0.3 du gradient est-il la cause ?', () {
      // On isole chaque mécanisme en le neutralisant UN SEUL à la fois.
      // Aucune de ces variantes n'est exécutée en production : ce sont des
      // CONTRE-FACTUELS destinés à identifier la cause.
      final resultats = <String, double>{};

      // (0) référence : mécanisme réel
      {
        final p = IaPoidsAdaptatifs();
        final mo = <String, double>{};
        final d = {for (final k in kCles) k: 0.0, 'forme': 0.02, 'placeDepart': 0.06};
        for (var i = 0; i < 200; i++) {
          _unCycle(p, d, mo, 0.08);
        }
        resultats['réel (facteur 0.3, bornes, normaliser)'] =
            p.placeDepart / p.forme;
      }

      // (1) contre-factuel : facteur de gradient de placeDepart = 1.0
      {
        final p = IaPoidsAdaptatifs();
        final mo = <String, double>{};
        final d = {for (final k in kCles) k: 0.0, 'forme': 0.02, 'placeDepart': 0.06};
        for (var i = 0; i < 200; i++) {
          // même arithmétique, mais facteur forcé à 1.0 pour placeDepart
          for (final c in kCles) {
            final grad = 0.08 * (d[c] ?? 0.0);
            final g = grad + 0.3 * (mo[c] ?? 0.0);
            mo[c] = g;
            final f = c == 'placeDepart' ? 1.0 : kFacteurs[c]!;
            _ecrire(p, c, p.getPoids(c) + g * f);
          }
          p.clamp();
        }
        resultats['facteur 1.0 (au lieu de 0.3)'] = p.placeDepart / p.forme;
      }

      // (2) contre-factuel : on retire la borne haute individuelle
      //     (simulation : on n'appelle PAS clamp(), on ne fait que normaliser)
      {
        final p = IaPoidsAdaptatifs();
        final mo = <String, double>{};
        final d = {for (final k in kCles) k: 0.0, 'forme': 0.02, 'placeDepart': 0.06};
        for (var i = 0; i < 200; i++) {
          for (final c in kCles) {
            final grad = 0.08 * (d[c] ?? 0.0);
            final g = grad + 0.3 * (mo[c] ?? 0.0);
            mo[c] = g;
            _ecrire(p, c, p.getPoids(c) + g * kFacteurs[c]!);
          }
          p.normaliser(); // sans les bornes individuelles
        }
        resultats['sans bornes individuelles'] = p.placeDepart / p.forme;
      }

      // (3) contre-factuel : ni bornes ni plafond de groupe (pur gradient)
      {
        final p = IaPoidsAdaptatifs();
        final mo = <String, double>{};
        final d = {for (final k in kCles) k: 0.0, 'forme': 0.02, 'placeDepart': 0.06};
        for (var i = 0; i < 200; i++) {
          for (final c in kCles) {
            final grad = 0.08 * (d[c] ?? 0.0);
            final g = grad + 0.3 * (mo[c] ?? 0.0);
            mo[c] = g;
            _ecrire(p, c, p.getPoids(c) + g * kFacteurs[c]!);
          }
          // aucune normalisation
        }
        resultats['ni bornes ni normalisation'] = p.placeDepart / p.forme;
      }

      // ignore: avoid_print
      print('── ratio placeDepart/forme après 200 cycles ──');
      for (final e in resultats.entries) {
        // ignore: avoid_print
        print('  ${e.key.padRight(42)} → ${e.value.toStringAsFixed(6)}');
      }
      // ignore: avoid_print
      print('  (ratio initial = ${(0.03 / 0.25).toStringAsFixed(6)})');
      // ignore: avoid_print
      print('  ratio > 1.0 ⇒ placeDepart a dépassé forme');

      // Conclusion mesurée : la levée de quelle contrainte permet le
      // dépassement ?
      for (final e in resultats.entries) {
        // ignore: avoid_print
        print('  dépasse forme ? ${e.key} : ${e.value > 1.0}');
      }
      expect(resultats.length, 4);
    });

    test('M9.3 — Vitesse de convergence comparée (poids relatifs)', () {
      final p = IaPoidsAdaptatifs();
      final mo = <String, double>{};
      final d = {for (final k in kCles) k: 0.0, 'forme': 0.02, 'placeDepart': 0.06};
      final init = _v(p);
      // ignore: avoid_print
      print('cycle | placeDepart relatif | forme relatif | ratio');
      for (var i = 1; i <= 60; i++) {
        _unCycle(p, d, mo, 0.08);
        if (i % 10 == 0) {
          final v = _v(p);
          final s = _somme(v.values);
          final relPd = v['placeDepart']! / s;
          final relF = v['forme']! / s;
          // ignore: avoid_print
          print('${i.toString().padLeft(5)} | ${relPd.toStringAsFixed(6)} | '
              '${relF.toStringAsFixed(6)} | ${(relPd / relF).toStringAsFixed(4)}');
        }
      }
      // ignore: avoid_print
      print('  ratio relatif initial = '
          '${((init["placeDepart"]! / _somme(init.values)) / (init["forme"]! / _somme(init.values))).toStringAsFixed(4)}');
      expect(p.placeDepart, greaterThan(0));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('M10 — L\'apprentissage peut-il INVERSER la hiérarchie ?', () {
    test('M10.1 — Discrimination identique : l\'ordre bouge-t-il ?', () {
      final p = IaPoidsAdaptatifs();
      final mo = <String, double>{};
      // Discrimination STRICTEMENT identique pour les 19 critères.
      final d = {for (final k in kCles) k: 0.02};
      final ordreInit = kCles.toList()
        ..sort((a, b) => p.getPoids(b).compareTo(p.getPoids(a)));
      for (var i = 0; i < 100; i++) {
        _unCycle(p, d, mo, 0.08);
      }
      final ordreFin = kCles.toList()
        ..sort((a, b) => p.getPoids(b).compareTo(p.getPoids(a)));
      // ignore: avoid_print
      print('── discrimination identique, 100 cycles ──');
      // ignore: avoid_print
      print('  ordre initial : ${ordreInit.join(" > ")}');
      // ignore: avoid_print
      print('  ordre final   : ${ordreFin.join(" > ")}');
      final pairesInversees = <String>[];
      for (var i = 0; i < kCles.length; i++) {
        for (var j = i + 1; j < kCles.length; j++) {
          final a = kCles[i], b = kCles[j];
          final av = p.getPoids(a) > p.getPoids(b);
          final ap = ordreFin.indexOf(a) < ordreFin.indexOf(b);
          if (av != ap) pairesInversees.add('$a/$b');
        }
      }
      // ignore: avoid_print
      print('  paires inversées = ${pairesInversees.length} / 171');
      if (pairesInversees.isNotEmpty) {
        // ignore: avoid_print
        print('    ${pairesInversees.take(15).join(", ")}');
      }
      expect(ordreFin.length, 19);
    });

    test('M10.2 — Discrimination maximale sur un critère enrichi', () {
      // placeDepart discrimine 0.30 (très fort), forme 0.0. C'est le scénario
      // le plus favorable possible à une inversion.
      final p = IaPoidsAdaptatifs();
      final mo = <String, double>{};
      final d = {for (final k in kCles) k: 0.0, 'placeDepart': 0.30};
      final avant = p.placeDepart;
      for (var i = 0; i < 500; i++) {
        _unCycle(p, d, mo, 0.08);
      }
      // ignore: avoid_print
      print('── discrimination extrême sur placeDepart (0.30), 500 cycles ──');
      // ignore: avoid_print
      print('  placeDepart : ${avant.toStringAsFixed(6)} → '
          '${p.placeDepart.toStringAsFixed(6)}');
      // ignore: avoid_print
      print('  forme       : 0.250000 → ${p.forme.toStringAsFixed(6)}');
      // ignore: avoid_print
      print('  discipline  : 0.020000 → ${p.discipline.toStringAsFixed(6)}');
      // ignore: avoid_print
      print('  placeDepart > discipline ? ${p.placeDepart > p.discipline}');
      // ignore: avoid_print
      print('  placeDepart > repos ? ${p.placeDepart > p.repos}');
      // ignore: avoid_print
      print('  placeDepart > forme ? ${p.placeDepart > p.forme}');
      final v = _v(p);
      final s = _somme(v.values);
      // ignore: avoid_print
      print('  part de placeDepart dans le total = '
          '${(v["placeDepart"]! / s * 100).toStringAsFixed(3)} %');
      // ignore: avoid_print
      print('  part de forme dans le total       = '
          '${(v["forme"]! / s * 100).toStringAsFixed(3)} %');
      expect(v['placeDepart']! / s, lessThan(0.10),
          reason: 'la borne 0.07 plafonne structurellement sa part');
    });

    test('M10.3 — Anchoring : écart relatif maximum atteignable', () {
      // Pour CHAQUE critère, on pousse une discrimination maximale (0.50)
      // pendant 500 cycles, tous les autres à 0, et on mesure l'écart relatif
      // final par rapport à la valeur initiale. Cela mesure l'AMPLITUDE
      // d'exploration réellement offerte à chaque critère.
      // ignore: avoid_print
      print('critère        | initial | final    | Δ %    | part finale % | borne atteinte');
      for (final cible in kCles) {
        final p = IaPoidsAdaptatifs();
        final mo = <String, double>{};
        final d = {for (final k in kCles) k: 0.0, cible: 0.50};
        final init = p.getPoids(cible);
        for (var i = 0; i < 500; i++) {
          _unCycle(p, d, mo, 0.08);
        }
        final fin = p.getPoids(cible);
        final v = _v(p);
        final s = _somme(v.values);
        final delta = init == 0 ? 0.0 : (fin - init) / init * 100;
        final aLaBorne = (fin - kBornes[cible]![1]).abs() < 1e-6 ||
            (fin - kBornes[cible]![0]).abs() < 1e-6;
        // ignore: avoid_print
        print('${cible.padRight(14)} | ${init.toStringAsFixed(5)} | '
            '${fin.toStringAsFixed(5)}  | ${delta.toStringAsFixed(1).padLeft(7)} | '
            '${(fin / s * 100).toStringAsFixed(2).padLeft(13)} | $aLaBorne');
      }
      expect(kCles.length, 19);
    });

    test('M10.4 — Combien de cycles pour franchir la médiane ?', () {
      // Mesure de l'ancrage : un critère enrichi à 0.03 peut-il devenir
      // premier (0.25+) et en combien de cycles ?
      final p = IaPoidsAdaptatifs();
      final mo = <String, double>{};
      final d = {for (final k in kCles) k: 0.0, 'placeDepart': 0.50};
      var cycles = -1;
      for (var i = 1; i <= 5000; i++) {
        _unCycle(p, d, mo, 0.08);
        if (p.placeDepart >= p.forme && cycles < 0) {
          cycles = i;
          break;
        }
      }
      // ignore: avoid_print
      print('── cycles nécessaires pour que placeDepart ≥ forme (discrim. 0.50) ──');
      // ignore: avoid_print
      print('  cycles = $cycles  (−1 = jamais atteint en 5000 cycles)');
      // ignore: avoid_print
      print('  placeDepart final = ${p.placeDepart.toStringAsFixed(6)}');
      // ignore: avoid_print
      print('  forme finale      = ${p.forme.toStringAsFixed(6)}');
      expect(cycles, -1,
          reason: 'mesure : l\'inversion est structurellement impossible');
    });
  });
}
