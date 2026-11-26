// ═══════════════════════════════════════════════════════════════════════════
//  AUDIT — ALIMENTATION RÉELLE DES 19 CRITÈRES SUR DONNÉES PMU AUTHENTIQUES
//
//  OBJET : mesurer, pour chaque critère, ce que le MOTEUR DE PRODUCTION
//          calcule réellement lorsqu'on lui injecte la réponse PMU
//          AUTHENTIQUE de l'endpoint `.../participants` (celle que
//          `ZoneTurfService._chargerPartants` interroge réellement).
//
//  MÉTHODE : aucun modèle fabriqué. On rejoue la chaîne de PRODUCTION :
//    1. `ZoneTurfService.chargerProgramme()`  — producteur réel, réseau
//       PMU intercepté par `MockClient` qui renvoie des JSON COPIÉS de
//       l'API PMU interrogée le 2026-11-26 (clés et valeurs verbatim).
//    2. `IaPronosticEngine.analyserCourseAvecCriteres()` — le moteur réel.
//    3. On lit `ScoresCriteres` (19 champs) tel que persisté.
//
//  Les fixtures `test/fixtures_audit_alimentation/*.json` sont des copies
//  INTÉGRALES de `participants` renvoyés par
//  `https://turfinfo.api.pmu.fr/rest/client/7/programme/26112026/R{n}/C{n}/participants?specialisation=INTERNET`
//  Aucune clé n'a été ajoutée, aucune valeur modifiée.
//
//  LECTURE DES RÉSULTATS :
//    • valeur constante == 50.0 sur TOUS les partants  ⇒ critère NEUTRE
//      (soit légitimement non applicable, soit non alimenté : à distinguer
//      par la présence ou l'absence de la donnée source, mesurée ici).
//    • variance > 0 ⇒ critère effectivement alimenté sur ce chemin.
//
//  Aucune écriture de production, aucun réglage, aucun reset.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

const int kNumR = 2;
const int kNumC = 1;

String _ddmmyyyy(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Les 19 critères, dans l'ordre de `ScoresCriteres`.
const List<String> kCriteres = <String>[
  'forme', 'gains', 'record', 'cote', 'constance',
  'victoires', 'discipline', 'distSpec', 'jockey', 'repos',
  'hippo', 'entraineur', 'elo', 'terrain', 'divergence',
  'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

Map<String, double> _versMap(ScoresCriteres s) => <String, double>{
      'forme': s.forme, 'gains': s.gains, 'record': s.record,
      'cote': s.cote, 'constance': s.constance, 'victoires': s.victoires,
      'discipline': s.discipline, 'distSpec': s.distSpec,
      'jockey': s.jockey, 'repos': s.repos, 'hippo': s.hippo,
      'entraineur': s.entraineur, 'elo': s.elo, 'terrain': s.terrain,
      'divergence': s.divergence, 'poidsRel': s.poidsRel,
      'progression': s.progression, 'mouvCote': s.mouvCote,
      'placeDepart': s.placeDepart,
    };

/// Charge les participants AUTHENTIQUES du fichier demandé.
Map<String, dynamic> _participantsAuthentiques(String fichier) {
  final File f = File('test/fixtures_audit_alimentation/$fichier.json');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

/// Programme PMU minimal : UNE course, discipline réelle, distance réelle.
///
/// Seules les clés réellement lues par `ZoneTurfService.chargerProgramme`
/// sont fournies ; les parties participant viennent d'un fichier AUTHENTIQUE.
Map<String, dynamic> _programmeJson({
  required DateTime depart,
  required String discipline,
  required String specialite,
  required int distance,
  String categorie = 'COURSE_A_CONDITIONS',
}) =>
    <String, dynamic>{
      'programme': <String, dynamic>{
        'date': _ddmmyyyy(depart),
        'reunions': <Map<String, dynamic>>[
          <String, dynamic>{
            'numOfficiel': kNumR,
            'dateReunion': depart.millisecondsSinceEpoch,
            'hippodrome': <String, dynamic>{
              'libelleCourt': 'VINCENNES',
              'libelleLong': 'HIPPODROME DE VINCENNES',
            },
            'pays': <String, dynamic>{'code': 'FR'},
            'courses': <Map<String, dynamic>>[
              <String, dynamic>{
                'numOrdre': kNumC,
                'numReunion': kNumR,
                'libelle': 'AUDIT ALIMENTATION',
                'distance': distance,
                'montantPrix': 40000,
                'discipline': discipline,
                'specialite': specialite,
                'heureDepart': depart.millisecondsSinceEpoch,
                'categorieParticularite': categorie,
                'typePiste': 'HERBE',
                'paris': <Map<String, dynamic>>[
                  <String, dynamic>{'typePari': 'E_SIMPLE_GAGNANT'},
                ],
              },
            ],
          },
        ],
      },
    };

http.Client _client(Map<String, dynamic> programme, Map<String, dynamic> parts) =>
    MockClient((http.Request req) async {
      final int i = req.url.pathSegments.indexOf('programme');
      final List<String> apres =
          i >= 0 ? req.url.pathSegments.sublist(i + 1) : const <String>[];
      final Map<String, dynamic> body = apres.length <= 1 ? programme : parts;
      return http.Response(json.encode(body), 200,
          headers: <String, String>{'content-type': 'application/json'});
    });

/// Rejoue le producteur réel puis le moteur réel sur une discipline.
Future<({ZtCourse course, Map<String, ScoresCriteres> scores})> _mesurer({
  required String fichier,
  required String discipline,
  required String specialite,
  required int distance,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final DateTime depart = DateTime.now().add(const Duration(minutes: 15));
  final Map<String, dynamic> parts = _participantsAuthentiques(fichier);

  late List<ZtReunion> reunions;
  await http.runWithClient(() async {
    reunions = await ZoneTurfService.chargerProgramme(
      forceRefresh: true,
      date: depart,
    );
  }, () => _client(
        _programmeJson(
          depart: depart,
          discipline: discipline,
          specialite: specialite,
          distance: distance,
        ),
        parts,
      ));

  expect(reunions, isNotEmpty, reason: 'TÉMOIN : programme produit');
  final ZtCourse course = reunions.first.courses.first;
  expect(course.partants, isNotEmpty, reason: 'TÉMOIN : partants produits');

  final (_, Map<String, ScoresCriteres> scores) =
      IaPronosticEngine.analyserCourseAvecCriteres(course);
  return (course: course, scores: scores);
}

/// Imprime et retourne le tableau des 19 critères : min, max, nb de valeurs.
Map<String, ({double min, double max, int distinct})> _tableau(
  Map<String, ScoresCriteres> scores,
) {
  final Map<String, ({double min, double max, int distinct})> out = {};
  for (final String c in kCriteres) {
    final List<double> vals =
        scores.values.map((ScoresCriteres s) => _versMap(s)[c]!).toList();
    final double mn = vals.reduce((a, b) => a < b ? a : b);
    final double mx = vals.reduce((a, b) => a > b ? a : b);
    out[c] = (min: mn, max: mx, distinct: vals.toSet().length);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── A1 — TROT ATTELÉ ────────────────────────────────────────────────────
  test('A1 — 19 critères mesurés sur participants PMU TROT ATTELE', () async {
    final r = await _mesurer(
        fichier: 'trot_attele',
        discipline: 'ATTELE',
        specialite: 'TROT_ATTELE',
        distance: 2100);
    final t = _tableau(r.scores);

    // ignore: avoid_print
    print('\n═══ A1 — TROT ATTELE : ${r.scores.length} partants ═══');
    for (final String c in kCriteres) {
      final e = t[c]!;
      final String flag = e.distinct == 1 ? 'CONSTANT' : 'variable';
      // ignore: avoid_print
      print('  ${c.padRight(12)} min=${e.min.toStringAsFixed(2).padLeft(7)} '
          'max=${e.max.toStringAsFixed(2).padLeft(7)} '
          'distinct=${e.distinct.toString().padLeft(3)}  $flag');
    }

    expect(r.scores, isNotEmpty);
  });

  // ── A2 — TROT MONTÉ ────────────────────────────────────────────────────
  test('A2 — 19 critères mesurés sur participants PMU TROT MONTE', () async {
    final r = await _mesurer(
        fichier: 'trot_monte',
        discipline: 'MONTE',
        specialite: 'TROT_MONTE',
        distance: 2200);
    final t = _tableau(r.scores);

    // ignore: avoid_print
    print('\n═══ A2 — TROT MONTE : ${r.scores.length} partants ═══');
    for (final String c in kCriteres) {
      final e = t[c]!;
      final String flag = e.distinct == 1 ? 'CONSTANT' : 'variable';
      // ignore: avoid_print
      print('  ${c.padRight(12)} min=${e.min.toStringAsFixed(2).padLeft(7)} '
          'max=${e.max.toStringAsFixed(2).padLeft(7)} '
          'distinct=${e.distinct.toString().padLeft(3)}  $flag');
    }

    expect(r.scores, isNotEmpty);
  });

  // ── A3 — PLAT ──────────────────────────────────────────────────────────
  test('A3 — 19 critères mesurés sur participants PMU PLAT', () async {
    final r = await _mesurer(
        fichier: 'plat',
        discipline: 'PLAT',
        specialite: 'PLAT',
        distance: 1600);
    final t = _tableau(r.scores);

    // ignore: avoid_print
    print('\n═══ A3 — PLAT : ${r.scores.length} partants ═══');
    for (final String c in kCriteres) {
      final e = t[c]!;
      final String flag = e.distinct == 1 ? 'CONSTANT' : 'variable';
      // ignore: avoid_print
      print('  ${c.padRight(12)} min=${e.min.toStringAsFixed(2).padLeft(7)} '
          'max=${e.max.toStringAsFixed(2).padLeft(7)} '
          'distinct=${e.distinct.toString().padLeft(3)}  $flag');
    }

    expect(r.scores, isNotEmpty);
  });

  // ── A4 — OBSTACLE ──────────────────────────────────────────────────────
  test('A4 — 19 critères mesurés sur participants PMU OBSTACLE', () async {
    final r = await _mesurer(
        fichier: 'obstacle',
        discipline: 'OBSTACLE',
        specialite: 'HAIES',
        distance: 4500);
    final t = _tableau(r.scores);

    // ignore: avoid_print
    print('\n═══ A4 — OBSTACLE : ${r.scores.length} partants ═══');
    for (final String c in kCriteres) {
      final e = t[c]!;
      final String flag = e.distinct == 1 ? 'CONSTANT' : 'variable';
      // ignore: avoid_print
      print('  ${c.padRight(12)} min=${e.min.toStringAsFixed(2).padLeft(7)} '
          'max=${e.max.toStringAsFixed(2).padLeft(7)} '
          'distinct=${e.distinct.toString().padLeft(3)}  $flag');
    }

    expect(r.scores, isNotEmpty);
  });

  // ── A5 — CHAÎNE CHAMP PAR CHAMP : ce que le producteur a réellement rempli
  test('A5 — état des champs enrichis chez le producteur (4 disciplines)',
      () async {
    final Map<String, ({String discipline, int n, int repos, int pd,
        int terrain, int jockey, int hippo, int entr, int elo})> res = {};

    for (final (String fichier, String disc, String spec, int dist) in <
        (String, String, String, int)>[
      ('trot_attele', 'ATTELE', 'TROT_ATTELE', 2100),
      ('trot_monte', 'MONTE', 'TROT_MONTE', 2200),
      ('plat', 'PLAT', 'PLAT', 1600),
      ('obstacle', 'OBSTACLE', 'HAIES', 4500),
    ]) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final DateTime depart = DateTime.now().add(const Duration(minutes: 15));
      final Map<String, dynamic> parts = _participantsAuthentiques(fichier);
      late List<ZtReunion> reunions;
      await http.runWithClient(() async {
        reunions = await ZoneTurfService.chargerProgramme(
            forceRefresh: true, date: depart);
      }, () => _client(
            _programmeJson(
                depart: depart,
                discipline: disc,
                specialite: spec,
                distance: dist),
            parts,
          ));
      final List<ZtPartant> ps = reunions.first.courses.first.partants;
      res[fichier] = (
        discipline: disc,
        n: ps.length,
        repos: ps.where((p) => p.joursRepos > 0).length,
        pd: ps.where((p) => p.placeDepartInt > 0).length,
        terrain: ps.where((p) => p.statsTerrainCsv.isNotEmpty).length,
        jockey: ps.where((p) => p.statsJockeyCsv.isNotEmpty).length,
        hippo: ps.where((p) => p.statsHippodromeCsv.isNotEmpty).length,
        entr: ps.where((p) => p.statsEntraineurCsv.isNotEmpty).length,
        elo: ps.where((p) => p.eloRating > 0).length,
      );
    }

    // ignore: avoid_print
    print('\n═══ A5 — CHAMPS ENRICHIS PRODUITS (source: PMU /participants) ═══');
    // ignore: avoid_print
    print('  discipline   n   joursRepos  placeDepart  terrain  jockey  '
        'hippodrome  entraineur  elo');
    for (final String k in res.keys) {
      final e = res[k]!;
      // ignore: avoid_print
      print('  ${e.discipline.padRight(10)} ${e.n.toString().padLeft(3)}   '
          '${e.repos.toString().padLeft(9)}  ${e.pd.toString().padLeft(10)}  '
          '${e.terrain.toString().padLeft(7)}  ${e.jockey.toString().padLeft(6)}  '
          '${e.hippo.toString().padLeft(10)}  ${e.entr.toString().padLeft(10)}  '
          '${e.elo.toString().padLeft(3)}');
    }

    // MESURE DURE : `statsEntraineurCsv` n'est rempli par AUCUN chemin.
    for (final String k in res.keys) {
      expect(res[k]!.entr, 0,
          reason: 'statsEntraineurCsv doit rester vide : aucun producteur.');
    }
  });
}
