// ═══════════════════════════════════════════════════════════════════════════
//  DIAGNOSTIC — POURQUOI LES CHAMPS ENRICHIS ÉTAIENT VIDES
//
//  Ce test mesure, endpoint par endpoint, ce que le HARNAIS sert réellement,
//  puis ce que le PRODUCTEUR en tire. Il ne juge pas la production : il
//  localise le défaut. État attendu après correction du harnais : l'historique
//  est présent et les champs enrichis sont renseignés.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/models/zt_models.dart';

import 'support/corpus_pmu_replay.dart';

Map<String, dynamic> _lire(String nom) => jsonDecode(
      File('$kCorpusDir/$nom').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('D0 — le corpus contient bien DEUX structures distinctes', () {
    final List<CorpusCourse> c = chargerManifeste();
    expect(c, isNotEmpty, reason: 'TÉMOIN : manifeste chargé');
    expect(c.length, greaterThanOrEqualTo(40));

    final CorpusCourse t = c.first;
    final Map<String, dynamic> parts = _lire('${t.key}_participants.json');
    final Map<String, dynamic> perf = _lire('${t.key}_perfdet.json');

    // La preuve du défaut du harnais précédent : les deux structures diffèrent.
    expect((parts['participants'] as List).first as Map, isA<Map>());
    expect(
      ((parts['participants'] as List).first as Map).containsKey('coursesCourues'),
      isFalse,
      reason: '`/participants` NE contient PAS `coursesCourues`',
    );
    expect(
      ((perf['participants'] as List).first as Map).containsKey('coursesCourues'),
      isTrue,
      reason: '`/performances-detaillees` contient `coursesCourues`',
    );
    expect((perf['participants'] as List).first as Map,
        isNot(contains('musique')),
        reason: '`/performances-detaillees` NE contient PAS `musique`');
  });

  for (final String disc in <String>[
    'ATTELE',
    'MONTE',
    'PLAT',
    'HAIE',
    'STEEPLECHASE',
    'CROSS',
  ]) {
    test('D1-$disc — le producteur alimente les champs enrichis', () async {
      final List<CorpusCourse> courses = corpusDe(disc);
      expect(courses, isNotEmpty, reason: 'TÉMOIN : corpus $disc non vide');

      final CorpusCourse c = courses.first;
      purgerProducteur();
      final List<ZtReunion> reunions = await rejouerCourse(c);
      expect(reunions, isNotEmpty, reason: 'TÉMOIN : programme produit');

      final ZtCourse course = reunions.first.courses.first;
      expect(course.partants, isNotEmpty, reason: 'TÉMOIN : partants produits');

      int repos = 0, terrain = 0, hippo = 0, dist = 0, pd = 0, poids = 0;
      double minPoids = 999, maxPoids = 0;
      for (final ZtPartant p in course.partants) {
        if (p.joursRepos > 0) repos++;
        if (p.statsTerrainCsv.isNotEmpty) terrain++;
        if (p.statsHippodromeCsv.isNotEmpty) hippo++;
        if (p.musiqueDistanceSpecifique.isNotEmpty) dist++;
        if (p.placeDepartInt > 0) pd++;
        if (p.poids > 0) {
          poids++;
          if (p.poids < minPoids) minPoids = p.poids;
          if (p.poids > maxPoids) maxPoids = p.poids;
        }
      }
      // ignore: avoid_print
      print('D1-$disc ${c.key} n=${course.partants.length} '
          'repos=$repos terrain=$terrain hippo=$hippo distSpec=$dist '
          'placeDepart=$pd poids=$poids'
          '${poids > 0 ? ' [${minPoids.toStringAsFixed(1)}..${maxPoids.toStringAsFixed(1)}]' : ''}');

      // TÉMOINS : l'historique a bien été consommé.
      expect(repos + terrain + hippo + dist, greaterThan(0),
          reason: 'Au moins UN champ issu de l\'historique doit être alimenté '
              'si le corpus est servi correctement.');
    });
  }
}
