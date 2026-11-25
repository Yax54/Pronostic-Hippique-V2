// ═══════════════════════════════════════════════════════════════════════════
//  BLOC 1 — BL3-A23 (Terrain) et BL3-A24 (Catégorie) : CHAÎNE RÉELLE
//            PRODUCTEUR PMU → CRITÈRE IA
//
//  OBJET : les deux anomalies consistent en un LITTÉRAL écrit par le
//          producteur (`piste: 'Pelouse'`, `categorie: ''`), qui neutralise le
//          critère IA consommateur. Un test qui fabriquerait directement une
//          `ZtCourse` avec la bonne valeur ne prouverait RIEN : il ne
//          toucherait pas le producteur, qui est le lieu du défaut.
//
//  Ce fichier exerce donc :
//    1. `ZoneTurfService.chargerProgramme()`  ← LE producteur réel, réseau
//       PMU intercepté. C'est lui qui construit la `ZtCourse` : la valeur
//       testée est donc celle de PRODUCTION.
//    2. `ZtPartant.scoreTerrain(course.piste)` ← LE consommateur réel du
//       critère Terrain (`ia_pronostic_engine.dart:266`).
//    3. `IaPronosticEngine` complet via `analyserCourseAvecCriteres()` ← le
//       chemin utilisé par les trois producteurs de pronostics persistés.
//
//  Les formes JSON utilisées sont copiées des FIXTURES RÉELLES du dépôt
//  (`test/fixtures/recherche_pmu/multi/*.json`) : `typePiste`,
//  `penetrometre.intitule`, `categorieParticularite`. Aucune valeur inventée.
//
//  Aucune écriture d'apprentissage, aucun reset.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart'
    show ScoresCriteres;
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

const int kNumR = 4;
const int kNumC = 2;

String _ddmmyyyy(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Programme PMU minimal contenant UNE course dont la piste et la catégorie
/// sont EXACTEMENT celles des fixtures réelles.
///
/// `penetrometre` et `categorieParticularite` sont les deux clés réellement
/// présentes dans les réponses PMU du dépôt (vérifié : 224 courses lues).
Map<String, dynamic> _programmeJson({
  required DateTime depart,
  String? typePiste,
  String? penetrometreIntitule,
  String categorieParticularite = 'COURSE_A_CONDITIONS',
}) {
  final course = <String, dynamic>{
    'numOrdre': kNumC,
    'numReunion': kNumR,
    'libelle': 'PRIX DE VERIFICATION TERRAIN',
    'distance': 2700,
    'montantPrix': 45000,
    'discipline': 'ATTELE',
    'heureDepart': depart.millisecondsSinceEpoch,
    'categorieParticularite': categorieParticularite,
    'paris': <Map<String, dynamic>>[
      <String, dynamic>{'typePari': 'E_SIMPLE_GAGNANT'},
    ],
  };
  if (typePiste != null) course['typePiste'] = typePiste;
  if (penetrometreIntitule != null) {
    course['penetrometre'] = <String, dynamic>{
      'intitule': penetrometreIntitule,
      'valeurMesure': '3,6',
      'heureMesure': '2026-11-15T16:10',
      'commentaire': '',
    };
  }
  return <String, dynamic>{
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
          'courses': <Map<String, dynamic>>[course],
        },
      ],
    },
  };
}

/// Partant dont les stats terrain couvrent les CINQ clés du barème.
///
/// `statsTerrainCsv` est le format EXACT produit par
/// `ZoneTurfService._normaliserTerrainPmu` (`zone_turf_service.dart:769`) :
/// `terrain|nbCourses|nbVictoires|nbTop3` séparés par `;`.
/// Les valeurs sont volontairement franches pour que le score soit
/// identifiable sans ambiguïté (5 victoires sur 6 sur « souple »).
Map<String, dynamic> _participantsJson() => <String, dynamic>{
      'participants': <Map<String, dynamic>>[
        <String, dynamic>{
          'numPmu': 7,
          'nom': 'IDEAL DU MOULIN',
          'statut': 'DECLARE_PARTANT',
          'musique': '1a2a3a1a5a',
          'dernierRapportDirect': <String, dynamic>{'rapport': 5.0},
          // Record PERSONNEL, format API réel : `recordAbsolu.temps` en
          // SECONDES (le producteur convertit en "M'SS"). 141,0 s sur 2700 m
          // donne 19,1 m/s, très au-dessus du seuil 12,0 du barème de
          // `_scoreDisciplineCompatibilite` ⇒ score de base 85,0, donc la
          // branche « score >= 70 » de la modulation Groupe reste atteignable
          // et les modulations ×0,92 / ×1,06 sont observables.
          'recordAbsolu': <String, dynamic>{'temps': 141.0},
          // Le producteur lit `pm['performancesParTerrain']` (liste de maps
          // avec `etatTerrain`, `nbCourses`, `nbVictoires`, `nbPlaces`).
          'performancesParTerrain': <Map<String, dynamic>>[
            <String, dynamic>{
              'etatTerrain': 'bon',
              'nbCourses': 6,
              'nbVictoires': 1,
              'nbPlaces': 2,
            },
            <String, dynamic>{
              'etatTerrain': 'souple',
              'nbCourses': 6,
              'nbVictoires': 5,
              'nbPlaces': 6,
            },
            <String, dynamic>{
              'etatTerrain': 'lourd',
              'nbCourses': 4,
              'nbVictoires': 0,
              'nbPlaces': 1,
            },
          ],
        },
      ],
    };

/// Client distinguant les DEUX endpoints par le NOMBRE de segments qui suivent
/// « programme » (même méthode que le test B1-A22 : un test sur
/// `path.contains('R4')` ne distinguerait pas structurellement les endpoints).
http.Client _client(Map<String, dynamic> programme) =>
    MockClient((http.Request req) async {
      final int i = req.url.pathSegments.indexOf('programme');
      final List<String> apres =
          i >= 0 ? req.url.pathSegments.sublist(i + 1) : const <String>[];
      final Map<String, dynamic> body =
          apres.length <= 1 ? programme : _participantsJson();
      return http.Response(json.encode(body), 200,
          headers: <String, String>{'content-type': 'application/json'});
    });

/// Exécute le PRODUCTEUR RÉEL et rend la course qu'il a construite.
Future<ZtCourse> _produireCourse(Map<String, dynamic> programme) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final DateTime depart = DateTime.now().add(const Duration(minutes: 15));
  List<ZtReunion> reunions = const <ZtReunion>[];
  await http.runWithClient(() async {
    reunions = await ZoneTurfService.chargerProgramme(
      forceRefresh: true,
      date: depart,
    );
  }, () => _client(programme));
  expect(reunions, isNotEmpty,
      reason: 'TÉMOIN : le programme simulé doit produire une réunion');
  expect(reunions.first.courses, hasLength(1),
      reason: 'TÉMOIN : une course doit être produite');
  return reunions.first.courses.first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final DateTime depart = DateTime.now().add(const Duration(minutes: 15));

  // ─────────────────────────────────────────────────────────────────────────
  //  BL3-A23-1 — LA PISTE PRODUITE N'EST PLUS LE LITTÉRAL « Pelouse »
  // ─────────────────────────────────────────────────────────────────────────
  test('BL3-A23-1 — `penetrometre.intitule` prime : « Souple » → piste souple',
      () async {
    final ZtCourse course = await _produireCourse(_programmeJson(
      depart: depart,
      typePiste: 'HERBE',
      penetrometreIntitule: 'Souple',
    ));

    // ignore: avoid_print
    print('─── MESURE BL3-A23-1 ───────────────────────────────────────');
    // ignore: avoid_print
    print('  typePiste PMU = « HERBE », penetrometre.intitule = « Souple »');
    // ignore: avoid_print
    print('  course.piste PRODUITE = « ${course.piste} »');
    // ignore: avoid_print
    print('  ATTENDU : « souple » (ancien défaut : « Pelouse »)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(course.piste, 'souple',
        reason: 'BL3-A23 : l\'état mesuré du terrain doit primer sur la '
            'nature du sol. « Pelouse » est le littéral fautif.');
    expect(course.piste, isNot('Pelouse'));
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  BL3-A23-2 — LE CRITÈRE TERRAIN CESSE D'ÊTRE NEUTRE (comparaison réelle)
  // ─────────────────────────────────────────────────────────────────────────
  test('BL3-A23-2 — scoreTerrain() distingue les terrains avec la piste produite',
      () async {
    // Avec « Souple » mesuré : le partant a 5 victoires sur 6 sur souple.
    final ZtCourse souple = await _produireCourse(_programmeJson(
      depart: depart,
      typePiste: 'HERBE',
      penetrometreIntitule: 'Souple',
    ));
    // Avec « Bon » mesuré : le même partant n'a que 1 victoire sur 6.
    final ZtCourse bon = await _produireCourse(_programmeJson(
      depart: depart,
      typePiste: 'HERBE',
      penetrometreIntitule: 'Bon',
    ));

    expect(souple.partants, isNotEmpty, reason: 'TÉMOIN : partants produits');
    expect(souple.partants.first.statsTerrainCsv, isNotEmpty,
        reason: 'TÉMOIN : les stats terrain doivent être extraites du PMU');

    final double scoreSouple = souple.partants.first.scoreTerrain(souple.piste);
    final double scoreBon = bon.partants.first.scoreTerrain(bon.piste);
    // Contre-épreuve : le littéral fautif d'origine.
    final double scorePelouse =
        souple.partants.first.scoreTerrain('Pelouse');

    // ignore: avoid_print
    print('─── MESURE BL3-A23-2 (critère Terrain) ─────────────────────');
    // ignore: avoid_print
    print('  statsTerrainCsv = « ${souple.partants.first.statsTerrainCsv} »');
    // ignore: avoid_print
    print('  scoreTerrain("${souple.piste}")  = ${scoreSouple.toStringAsFixed(2)}');
    // ignore: avoid_print
    print('  scoreTerrain("${bon.piste}")     = ${scoreBon.toStringAsFixed(2)}');
    // ignore: avoid_print
    print('  scoreTerrain("Pelouse") [DÉFAUT] = ${scorePelouse.toStringAsFixed(2)}');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    // Le défaut d'origine : TOUJOURS 50.0, quelle que soit la donnée.
    expect(scorePelouse, 50.0,
        reason: 'CONTRE-ÉPREUVE : avec le littéral « Pelouse », la clé '
            'normalisée ne correspond à aucune entrée ⇒ 50.0 systématique.');

    // La correction : deux états de terrain différents produisent deux scores
    // différents, et ni l'un ni l'autre n'est le neutre.
    expect(scoreSouple, isNot(50.0),
        reason: 'BL3-A23 : le critère Terrain doit s\'activer sur la piste '
            'réellement produite');
    expect(scoreBon, isNot(50.0));
    expect(scoreSouple, greaterThan(scoreBon),
        reason: '5 victoires sur 6 en souple doit dominer 1 victoire sur 6 en bon');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  BL3-A23-3 — ABSENCE DE DONNÉE : NEUTRE, JAMAIS UNE VALEUR INVENTÉE
  // ─────────────────────────────────────────────────────────────────────────
  test('BL3-A23-3 — sans typePiste ni penetrometre, la piste reste VIDE', () async {
    final ZtCourse course = await _produireCourse(_programmeJson(
      depart: depart,
      // Ni typePiste, ni penetrometre : 146 courses des fixtures sont dans ce cas.
    ));

    // ignore: avoid_print
    print('─── MESURE BL3-A23-3 (donnée absente) ──────────────────────');
    // ignore: avoid_print
    print('  auncun typePiste, aucun penetrometre');
    // ignore: avoid_print
    print('  course.piste = «${course.piste}» (longueur ${course.piste.length})');
    // ignore: avoid_print
    print('  scoreTerrain = ${course.partants.first.scoreTerrain(course.piste)}');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(course.piste, isEmpty,
        reason: 'L\'absence de donnée doit produire une chaîne VIDE, pas un '
            'repli inventé (« Pelouse » ou « bon »).');
    expect(course.partants.first.scoreTerrain(course.piste), 50.0,
        reason: 'Donnée absente ⇒ neutre explicite (branche '
            '`terrainCourse.isEmpty` de scoreTerrain).');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  BL3-A23-4 — `typePiste` seul : vraie donnée, pas une constante
  // ─────────────────────────────────────────────────────────────────────────
  test('BL3-A23-4 — `typePiste` seul est exploité et normalisé', () async {
    final ZtCourse course = await _produireCourse(_programmeJson(
      depart: depart,
      typePiste: 'GAZON',
    ));

    // ignore: avoid_print
    print('─── MESURE BL3-A23-4 ───────────────────────────────────────');
    // ignore: avoid_print
    print('  typePiste PMU = « GAZON », aucun penetrometre');
    // ignore: avoid_print
    print('  course.piste = « ${course.piste} »');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    // 'GAZON' n'est pas une clé du barème et `_normaliserTerrainPmu`
    // (`zone_turf_service.dart:769`) ne contient PAS de règle pour lui : sa
    // branche de repli rend `'gazon'`. Ce n'est donc PAS converti en `'bon'`
    // ici, et c'est le comportement honnête : la valeur réelle est transmise
    // telle quelle, normalisée ; c'est le BARÈME de `scoreTerrain` qui,
    // ne trouvant aucune entrée correspondante, rend 50.0 (neutre). Aucune
    // donnée n'est inventée pour forcer une correspondance.
    expect(course.piste, 'gazon',
        reason: 'BL3-A23 : `typePiste` réel est transmis après normalisation ; '
            'il n\'est pas remplacé par un repli inventé.');
    expect(course.piste, isNot('Pelouse'));
    // Conséquence mesurée : neutre, parce qu'aucune entrée `gazon` n'existe
    // dans `statsTerrainCsv`. C'est un neutre de BARÈME, pas une invention.
    expect(course.partants.first.scoreTerrain(course.piste), 50.0);
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  BL3-A24-1 — LA CATÉGORIE PRODUITE N'EST PLUS VIDE
  // ─────────────────────────────────────────────────────────────────────────
  test('BL3-A24-1 — `categorieParticularite` alimente course.categorie',
      () async {
    final ZtCourse handicap = await _produireCourse(_programmeJson(
      depart: depart,
      categorieParticularite: 'HANDICAP',
    ));
    final ZtCourse conditions = await _produireCourse(_programmeJson(
      depart: depart,
      categorieParticularite: 'COURSE_A_CONDITIONS',
    ));

    // ignore: avoid_print
    print('─── MESURE BL3-A24-1 ───────────────────────────────────────');
    // ignore: avoid_print
    print('  PMU « HANDICAP »           → course.categorie = « ${handicap.categorie} »');
    // ignore: avoid_print
    print('  PMU « COURSE_A_CONDITIONS » → course.categorie = « ${conditions.categorie} »');
    // ignore: avoid_print
    print('  ATTENDU : « handicap » / « course_a_conditions » (défaut : « »)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(handicap.categorie, 'handicap');
    expect(conditions.categorie, 'course_a_conditions');
    expect(handicap.categorie, isNot(''),
        reason: 'BL3-A24 : le littéral vide rendait les 3 branches de '
            '_scoreDisciplineCompatibilite inatteignables');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  BL3-A24-2 — LA SENTINELLE « INCONNU » NE DEVIENT PAS UNE CATÉGORIE
  // ─────────────────────────────────────────────────────────────────────────
  test('BL3-A24-2 — `categorieParticularite == "INCONNU"` reste vide', () async {
    // 'INCONNU' est mesuré 54 fois sur 224 courses dans les fixtures PMU :
    // ce n'est PAS une catégorie, c'est la sentinelle d'absence de l'API.
    final ZtCourse course = await _produireCourse(_programmeJson(
      depart: depart,
      categorieParticularite: 'INCONNU',
    ));

    // ignore: avoid_print
    print('─── MESURE BL3-A24-2 (sentinelle) ──────────────────────────');
    // ignore: avoid_print
    print('  PMU « INCONNU » → course.categorie = «${course.categorie}»');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(course.categorie, isEmpty,
        reason: 'La sentinelle d\'absence ne doit pas être promue catégorie : '
            'sinon on appliquerait une modulation sur une donnée inexistante.');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  BL3-A24-3 — LE CHEMIN PERSISTANT VOIT ENFIN LA MODULATION
  // ─────────────────────────────────────────────────────────────────────────
  test('BL3-A24-3 — analyserCourseAvecCriteres() applique la modulation catégorie',
      () async {
    // Le consommateur modifie `_scoreDisciplineCompatibilite` : ×0,92 en
    // handicap, ×0,88 en réclam, ×1,06 si score ≥ 70 en conditions.
    // On compare donc le MÊME cheval dans DEUX catégories produites par le
    // producteur réel, et l'on exige des scores différents : la preuve que la
    // valeur n'est plus une constante.
    final ZtCourse handicap = await _produireCourse(_programmeJson(
      depart: depart,
      categorieParticularite: 'HANDICAP',
    ));
    final ZtCourse inconnu = await _produireCourse(_programmeJson(
      depart: depart,
      categorieParticularite: 'INCONNU',
    ));

    final (_, Map<String, ScoresCriteres> scHandicapMap) =
        IaPronosticEngine.analyserCourseAvecCriteres(handicap);
    final (_, Map<String, ScoresCriteres> scInconnuMap) =
        IaPronosticEngine.analyserCourseAvecCriteres(inconnu);

    final String num = handicap.partants.first.numero;
    final ScoresCriteres scHandicap = scHandicapMap[num]!;
    final ScoresCriteres scInconnu = scInconnuMap[num]!;

    // ignore: avoid_print
    print('─── MESURE BL3-A24-3 (critère discipline) ──────────────────');
    // ignore: avoid_print
    print('  catégorie « ${handicap.categorie} » → discipline = '
        '${scHandicap.discipline.toStringAsFixed(4)}');
    // ignore: avoid_print
    print('  catégorie «${inconnu.categorie}»  → discipline = '
        '${scInconnu.discipline.toStringAsFixed(4)}');
    // ignore: avoid_print
    print('  numéro comparé = $num');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(scHandicap.discipline, isNot(scInconnu.discipline),
        reason: 'BL3-A24 : la modulation Handicap (×0,92) doit s\'appliquer '
            'dès lors que la catégorie est réellement produite.');
  });
}
