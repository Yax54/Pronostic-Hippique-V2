// ══════════════════════════════════════════════════════════════════════════════
//  AUDIT DES POIDS IA — HARNAIS M13
//
//  Comparaison ÉQUITABLE des deux jeux de poids candidats, tous deux passés
//  dans le MÊME pipeline de production (`clamp()` → bornes → `normaliser()`).
//  C'est la seule comparaison qui isole l'effet des VALEURS INITIALES, sans
//  modifier quoi que ce soit : on construit deux instances en mémoire.
//
//  Ce harnais ne mesure AUCUNE efficacité prédictive. Il mesure la structure
//  des pondérations obtenues.
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

/// Jeu HISTORIQUE (famille #3, celle que l'utilisateur a confirmée comme étant
/// son choix hippique d'origine). Injecté via le constructeur pour être soumis
/// EXACTEMENT au même traitement que le jeu actuel.
IaPoidsAdaptatifs _historique() => IaPoidsAdaptatifs(
      forme: 0.32, gains: 0.15, record: 0.12,
      cote: 0.08, constance: 0.09, victoires: 0.04, discipline: 0.02,
      distSpec: 0.08, jockey: 0.07, repos: 0.03, hippo: 0.04,
      entraineur: 0.04, elo: 0.05, terrain: 0.05, divergence: 0.04,
      poidsRel: 0.03, progression: 0.03, mouvCote: 0.06, placeDepart: 0.03,
    );

void main() {
  group('M13 — Jeu actuel vs jeu historique, même pipeline', () {
    test('M13.1 — Poids effectifs après clamp() (état vierge)', () {
      final actuel = IaPoidsAdaptatifs()..clamp();
      final histo = _historique()..clamp();
      final a = _v(actuel);
      final h = _v(histo);

      // ignore: avoid_print
      print('critère        | BRUT actuel | EFF actuel | BRUT histo | EFF histo | Δ effectif');
      for (final k in kCles) {
        final brutA = IaPoidsAdaptatifs().getPoids(k);
        final brutH = _historique().getPoids(k);
        final d = h[k]! - a[k]!;
        // ignore: avoid_print
        print('${k.padRight(14)} | ${brutA.toStringAsFixed(4)} | '
            '${a[k]!.toStringAsFixed(6)} | ${brutH.toStringAsFixed(4)} | '
            '${h[k]!.toStringAsFixed(6)} | ${d.toStringAsFixed(6)}');
      }
      // ignore: avoid_print
      print('somme actuel = ${_somme(a.values).toStringAsFixed(10)}');
      // ignore: avoid_print
      print('somme histo  = ${_somme(h.values).toStringAsFixed(10)}');
      expect(_somme(a.values), closeTo(1.0, 1e-9));
      expect(_somme(h.values), closeTo(1.0, 1e-9));
    });

    test('M13.2 — Répartition base/enrichis après normalisation', () {
      final actuel = IaPoidsAdaptatifs()..clamp();
      final histo = _historique()..clamp();
      final a = _v(actuel);
      final h = _v(histo);
      final baseA = _somme(kBase.map((k) => a[k]!));
      final baseH = _somme(kBase.map((k) => h[k]!));
      // ignore: avoid_print
      print('── répartition après normaliser() ──');
      // ignore: avoid_print
      print('  base (7)    actuel = ${baseA.toStringAsFixed(6)}  '
          'histo = ${baseH.toStringAsFixed(6)}');
      // ignore: avoid_print
      print('  enrichis    actuel = ${(1 - baseA).toStringAsFixed(6)}  '
          'histo = ${(1 - baseH).toStringAsFixed(6)}');
      // ignore: avoid_print
      print('  ⚠️ Les deux jeux convergent vers la MÊME répartition de groupe '
          'car `normaliser()` écrête la fraction enrichie à [0.18, 0.40].');
      expect(baseA, closeTo(0.60, 1e-9));
      expect(baseH, closeTo(0.60, 1e-9));
    });

    test('M13.3 — Écart relatif intra-groupe : ce qui change RÉELLEMENT', () {
      // Puisque la répartition de groupe est identique, seule la répartition
      // INTERNE change. On mesure cet écart en points de pourcentage.
      final actuel = IaPoidsAdaptatifs()..clamp();
      final histo = _historique()..clamp();
      final a = _v(actuel);
      final h = _v(histo);
      // ignore: avoid_print
      print('critère        | EFF actuel % | EFF histo % | Δ points | Δ relatif %');
      var ecartMax = 0.0;
      var critMax = '';
      for (final k in kCles) {
        final pa = a[k]! * 100;
        final ph = h[k]! * 100;
        final dp = ph - pa;
        final dr = pa == 0 ? 0.0 : dp / pa * 100;
        if (dp.abs() > ecartMax) {
          ecartMax = dp.abs();
          critMax = k;
        }
        // ignore: avoid_print
        print('${k.padRight(14)} | ${pa.toStringAsFixed(3).padLeft(12)} | '
            '${ph.toStringAsFixed(3).padLeft(11)} | ${dp.toStringAsFixed(3).padLeft(8)} | '
            '${dr.toStringAsFixed(1).padLeft(11)}');
      }
      // ignore: avoid_print
      print('→ écart max = ${ecartMax.toStringAsFixed(4)} pt sur "$critMax"');
      expect(ecartMax, greaterThan(0.0),
          reason: 'les deux jeux doivent produire des répartitions différentes');
    });

    test('M13.4 — Hiérarchie : l\'ordre des critères change-t-il ?', () {
      final actuel = IaPoidsAdaptatifs()..clamp();
      final histo = _historique()..clamp();
      final a = _v(actuel);
      final h = _v(histo);
      final ordreA = kCles.toList()..sort((x, y) => a[y]!.compareTo(a[x]!));
      final ordreH = kCles.toList()..sort((x, y) => h[y]!.compareTo(h[x]!));
      // ignore: avoid_print
      final paires = <String>[];
      for (var i = 0; i < kCles.length; i++) {
        for (var j = i + 1; j < kCles.length; j++) {
          final x = kCles[i], y = kCles[j];
          if ((a[x]! > a[y]!) != (h[x]! > h[y]!)) paires.add('$x/$y');
        }
      }
      // ignore: avoid_print
      print('ordre actuel : ${ordreA.join(" > ")}');
      // ignore: avoid_print
      print('ordre histo  : ${ordreH.join(" > ")}');
      // ignore: avoid_print
      print('→ paires inversées = ${paires.length} / 171');
      if (paires.isNotEmpty) {
        // ignore: avoid_print
        print('  ${paires.join(", ")}');
      }
      expect(ordreA.length, 19);
    });
  });
}
