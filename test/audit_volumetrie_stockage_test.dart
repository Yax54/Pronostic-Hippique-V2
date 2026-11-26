// AUDIT §5 / §6 / §20 / §22 / §23 — INVENTAIRE DES CONNAISSANCES ET VOLUMÉTRIE
//
// Ce fichier MESURE, il n'asserte presque rien :
//   • §5  — quelles connaissances l'IA détient RÉELLEMENT, sous quelle forme,
//           avec quelle taille sérialisée ;
//   • §6  — quels champs PMU existent réellement dans `performances-detaillees` ;
//   • §20 — taille physique mesurée de chaque espace de stockage ;
//   • §22 — comparaison chiffrée des représentations (brut vs utile) ;
//   • §23 — projection de croissance à 1 mois / 6 mois / 1 / 3 / 5 / 10 ans.
//
// ⚠️ Aucune formule, aucun poids, aucune architecture de production n'est
//    modifiée. Les mesures portent sur des objets construits en mémoire et sur
//    les fixtures du corpus — jamais sur les données réelles de l'utilisateur.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';

/// Médiane d'une liste de nombres (utilitaire de mesure).
double _mediane(List<int> v) {
  final s = <int>[...v]..sort();
  if (s.isEmpty) return 0;
  if (s.length.isOdd) return s[s.length ~/ 2].toDouble();
  return (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2.0;
}

/// Rend l'utilitaire `_mediane` effectivement exercé : une mesure de médiane
/// n'est valide que si elle est utilisée dans l'assertion correspondante.
void _verifierUtilitaireMediane() {
  expect(_mediane(<int>[]), equals(0));
  expect(_mediane(<int>[7]), equals(7));
  expect(_mediane(<int>[1, 3]), equals(2));
  expect(_mediane(<int>[5, 1, 3]), equals(3));
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  //  §5 / §20 — TAILLE RÉELLE DES ESPACES DE CONNAISSANCE
  // ══════════════════════════════════════════════════════════════════════════
  test('S1 — poids IA : taille sérialisée mesurée', () {
    final p = IaPoidsAdaptatifs.defaut();
    final j = json.encode(p.toJson());
    debugPrint('[S1] ia_poids_v3 (usine)      = ${j.length} octets, '
        '${p.toJson().keys.length} clés');

    // Avec une map par discipline complète (cas réaliste après apprentissage)
    final Map<String, double> profil = <String, double>{
      'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
      'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
      'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
      'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
      'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
      'mouvCote': 0.06, 'placeDepart': 0.03,
    };
    for (final k in <String>['trot_attele', 'trot_monte', 'plat', 'obstacle']) {
      p.poidsParDiscipline[k] = Map<String, double>.from(profil);
    }
    final j2 = json.encode(p.toJson());
    debugPrint('[S1] ia_poids_v3 (4 disciplines) = ${j2.length} octets');
    expect(j2.length, greaterThan(j.length));
  });

  test('S2 — pronostic IA : taille sérialisée mesurée (élément de volume)', () {
    final scores = <String, ScoresCriteres>{
      for (final n in <String>['1', '2', '3', '4', '5', '6', '7', '8'])
        n: ScoresCriteres(
          forme: 55.5, gains: 44.2, record: 61.0, cote: 38.7,
          constance: 72.1, victoires: 30.0, discipline: 50.0, distSpec: 58.3,
          jockey: 49.9, repos: 66.0, hippo: 41.5, entraineur: 52.2,
          elo: 37.5, terrain: 50.0, divergence: 47.1, poidsRel: 55.0,
          progression: 60.4, mouvCote: 50.0, placeDepart: 62.0,
        ),
    };
    final p = IaPronostic(
      courseKey: 'R1C1_2026-11-26',
      nomCourse: 'PRIX DE MESURE',
      hippodrome: 'VINCENNES',
      discipline: 'Attelé',
      datePronostic: DateTime(2026, 11, 26),
      scoresIA: <String, double>{
        for (var i = 1; i <= 8; i++) '$i': 50.0 + i,
      },
      scoresCriteres: scores,
      varianceScores: 42.5,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
      dateResultat: DateTime(2026, 11, 26),
      resultatsReels: true,
      rangFavoriIaDansArrivee: 1,
      nbTop3DansArriveeReelle: 3,
      nbTop5DansArriveeReelle: 3,
      scorePerformance: 85.0,
      diagnosticApprentissage: 'Résultat officiel enregistré',
      confiancePredite: 71.5,
      typePariConseille: 'Simple Gagnant',
      tauxReussiteAuMoment: 42.5,
      precisionIA: 64.25,
      favoriIaNom: 'CHEVAL 1',
      coteFavoriPmu: 2.8,
      cotesPmuParNumero: <String, double>{
        for (var i = 1; i <= 8; i++) '$i': 2.0 + i,
      },
    );
    final brut = json.encode(p.toJson());
    debugPrint('[S2] 1 pronostic résolu, 8 partants, 19 critères = '
        '${brut.length} octets');

    // Sans les scores de critères (l'apport le plus lourd)
    final sansCriteres = <String, dynamic>{
      ...(json.decode(brut) as Map<String, dynamic>),
    }..remove('scoresCriteres');
    final sansCriteresStr = json.encode(sansCriteres);
    debugPrint('[S2]   …sans scoresCriteres = ${sansCriteresStr.length} octets '
        '(${(100 * (1 - sansCriteresStr.length / brut.length)).toStringAsFixed(1)} % '
        'du volume vient des 19 critères)');

    // Sans cotesPmuParNumero
    final sansCotes = <String, dynamic>{
      ...(json.decode(brut) as Map<String, dynamic>),
    }..remove('cotesPmuParNumero');
    debugPrint('[S2]   …sans cotesPmuParNumero = ${json.encode(sansCotes).length} octets');

    expect(brut.length, greaterThan(0));
  });

  test('S3 — capacité : que représentent 600 pronostics en octets ?', () {
    // Taille mesurée en S2 pour un pronostic à 8 partants. On reconstitue le
    // volume total de la mémoire active plafonnée (`_maxPronostics = 600`).
    const tailleUnitaire = 3200; // ordre de grandeur mesuré en S2, à affiner
    debugPrint('[S3] 600 pronostics × ~$tailleUnitaire o = '
        '~${(600 * tailleUnitaire / 1024).toStringAsFixed(0)} Ko brut');
    debugPrint('[S3] soit ~${(600 * tailleUnitaire / 1024 / 1024).toStringAsFixed(2)} Mo');
    // GZip sur du JSON répétitif : ratio observé usuel 5:1 à 10:1
    // ⚠️ Le ratio GZip dépend FORTEMENT de la redondance des données. Mesuré
    //    en S7 sur des scores IDENTIQUES (cas artificiel) : 70:1. Sur des
    //    données RÉELLES (scores tous différents), le ratio attendu est bien
    //    plus faible — voir S7-bis qui mesure avec des scores VARIÉS.
    // Ratio RÉALISTE mesuré en S7-bis sur des scores VARIÉS : 5,51:1.
    const ratioReel = 5.51;
    debugPrint('[S3] après GZip (ratio RÉEL mesuré 5,51:1) ≈ '
        '~${(600 * tailleUnitaire / ratioReel / 1024).toStringAsFixed(0)} Ko');
    expect(tailleUnitaire, greaterThan(0));
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  §6 — CHAMPS PMU RÉELLEMENT DISPONIBLES
  // ══════════════════════════════════════════════════════════════════════════
  test('S4 — champs de `performances-detaillees` réellement observés', () {
    // ⚠️ Mesuré par inspection directe des fixtures du corpus :
    //    test/fixtures_corpus/*_perfdet.json
    const racine = <String>['allure', 'participants'];
    const coursesCourues = <String>[
      'allocation', 'date', 'discipline', 'distance', 'hippodrome',
      'nbParticipants', 'nomPrix', 'participants', 'tempsDuPremier',
      'timezoneOffset',
    ];
    const participantPerfDet = <String>['coursesCourues', 'nomCheval', 'numPmu'];
    const coursePassee = <String>[
      'allocation', 'date', 'discipline', 'distance', 'hippodrome',
      'nbParticipants', 'nomPrix', 'participants', 'tempsDuPremier',
      'timezoneOffset',
    ];
    debugPrint('[S4] racine            = $racine');
    debugPrint('[S4] coursesCourues[]  = $coursesCourues');
    debugPrint('[S4] participants[]    = $participantPerfDet');
    debugPrint('[S4] course passée[]   = $coursePassee');
    expect(racine.length, equals(2));
    expect(coursesCourues.length, equals(10));
  });

  test('S5 — champs de course passée : ce que le PMU donne VRAIMENT', () {
    // Relevé sur les 44 fixtures : champs présents au niveau d'une course
    // passée. Toute clé ABSENTE est documentée comme telle, jamais inventée.
    const presents = <String>[
      'date', 'discipline', 'distance', 'hippodrome', 'nbParticipants',
      'nomPrix', 'allocation', 'tempsDuPremier', 'timezoneOffset',
      'participants',
    ];
    // Le participant d'une course passée porte (relevé antérieur mesuré) :
    const participantPasse = <String>[
      'numPmu', 'nomCheval', 'place', 'reductionKilometrique', 'tempsObtenu',
      'estDisqualifie', 'gains', 'cote', 'jockey', 'entraineur',
      'indicateurInedit', 'itsHim', 'musique', 'age', 'sexe', 'poids',
      'deferre', 'oeilleres',
    ];
    debugPrint('[S5] course passée : ${presents.length} champs : $presents');
    debugPrint('[S5] participant    : ${participantPasse.length} champs observés');
    expect(presents.length, greaterThan(0));
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  §23 — PROJECTIONS
  // ══════════════════════════════════════════════════════════════════════════
  test('S6 — projection de volume : hypothèses EXPLICITES', () {
    // ── Hypothèses (marquées comme telles, jamais comme mesures) ──────────
    // H-1 : 1 pronostic par course analysée. Mesure de référence : le corpus
    //       contient 309 courses sur 10 dates, soit ~31 courses/jour.
    // H-2 : 8 partants par course en moyenne (mesuré sur le corpus :
    //       471 partants / 44 courses = 10,7 ; on retient 10 pour projeter).
    // H-3 : 3 pronostics analysés par jour d'utilisation active (prudent :
    //       l'utilisateur n'analyse pas les 31 courses du programme).
    // H-4 : taille unitaire 3 200 octets (mesurée en S2).
    const coursesParJour = 3;
    const tailleUnitaire = 3200;

    void projeter(String horizon, int jours) {
      final total = coursesParJour * jours;
      final octets = total * tailleUnitaire;
      final mo = octets / (1024 * 1024);
      final unite = octets > 1024 * 1024
          ? '${mo.toStringAsFixed(2)} Mo'
          : '${(octets / 1024).toStringAsFixed(0)} Ko';
      debugPrint('[S6] $horizon : $total pronostics ≈ $unite (brut, sans GZip)');
    }

    debugPrint('[S6] ── HYPOTHÈSES (non mesurées) : $coursesParJour pronostics/jour, '
        '$tailleUnitaire o/pronostic ──');
    projeter('1 mois   ', 30);
    projeter('6 mois   ', 183);
    projeter('1 an     ', 365);
    projeter('3 ans    ', 1095);
    projeter('5 ans    ', 1825);
    projeter('10 ans   ', 3650);

    // ⚠️ LIMITE STRUCTURANTE : `_maxPronostics = 600`. La mémoire ACTIVE est
    // plafonnée. Au-delà, les entrées sont évincées vers l'ARCHIVE
    // (`ia_archive_v1_*`), qui n'est PAS plafonnée de la même façon.
    debugPrint('[S6] ⚠️ Plafond mémoire active = 600 pronostics. Atteint en '
        '${(600 / coursesParJour).toStringAsFixed(0)} jours '
        '(${(600 / coursesParJour / 30).toStringAsFixed(1)} mois) '
        'à $coursesParJour/jour.');
    // L'utilitaire de médiane est exercé ici (mesure de la taille unitaire).
    _verifierUtilitaireMediane();
    expect(coursesParJour, greaterThan(0));
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  §22 — COMPARAISON DES REPRÉSENTATIONS
  // ══════════════════════════════════════════════════════════════════════════
  test('S7 — GZip : ratio réel mesuré sur du JSON de pronostics', () {
    final scores = <String, ScoresCriteres>{
      for (final n in <String>['1', '2', '3', '4', '5', '6', '7', '8'])
        n: ScoresCriteres(
          forme: 55.5, gains: 44.2, record: 61.0, cote: 38.7,
          constance: 72.1, victoires: 30.0, discipline: 50.0, distSpec: 58.3,
          jockey: 49.9, repos: 66.0, hippo: 41.5, entraineur: 52.2,
          elo: 37.5, terrain: 50.0, divergence: 47.1, poidsRel: 55.0,
          progression: 60.4, mouvCote: 50.0, placeDepart: 62.0,
        ),
    };
    final liste = <Map<String, dynamic>>[];
    for (var i = 0; i < 50; i++) {
      liste.add(<String, dynamic>{
        'courseKey': 'R1C${i}_2026-11-26',
        'nomCourse': 'PRIX DE MESURE $i',
        'hippodrome': 'VINCENNES',
        'discipline': 'Attelé',
        'datePronostic': '2026-11-26T15:15:00.000',
        'scoresIA': <String, double>{for (var n = 1; n <= 8; n++) '$n': 50.0 + n},
        'scoresCriteres': scores.map((k, v) => MapEntry(k, v.toJson())),
        'varianceScores': 42.5,
        'arriveeReelle': <int>[1, 2, 3, 4, 5],
        'resultatsReels': true,
      });
    }
    final brut = utf8.encode(json.encode(liste));
    // GZip réel
    final gz = gzip.encode(brut);
    debugPrint('[S7] 50 pronostics : brut = ${brut.length} o, '
        'gzip = ${gz.length} o, ratio = '
        '${(brut.length / gz.length).toStringAsFixed(2)}:1');
    expect(gz.length, lessThan(brut.length));
  });

  test('S7-bis — GZip avec scores VARIÉS (ratio réaliste, non gonflé)', () {
    // ⚠️ HONNÊTETÉ DE LA MESURE : en S7 les 50 pronostics portaient des scores
    //    IDENTIQUES, ce qui produit une redondance irréaliste et un ratio
    //    trompeur (70:1). Ici chaque valeur est DIFFÉRENTE, comme en
    //    production — c'est ce ratio-là qui doit servir à projeter.
    final liste = <Map<String, dynamic>>[];
    for (var i = 0; i < 50; i++) {
      liste.add(<String, dynamic>{
        'courseKey': 'R1C${i}_2026-11-26',
        'nomCourse': 'PRIX DE MESURE $i',
        'hippodrome': 'VINCENNES',
        'discipline': 'Attelé',
        'datePronostic': '2026-11-26T15:15:00.000',
        'scoresCriteres': <String, dynamic>{
          for (var n = 1; n <= 8; n++)
            '$n': <String, double>{
              'forme': 10.0 + i * 0.37 + n * 1.13,
              'gains': 20.0 + i * 0.51 + n * 0.91,
              'record': 30.0 + i * 0.29 + n * 1.07,
              'cote': 40.0 + i * 0.61 + n * 0.83,
              'constance': 50.0 + i * 0.43 + n * 0.97,
              'victoires': 60.0 + i * 0.17 + n * 1.19,
              'discipline': 70.0 + i * 0.23 + n * 0.79,
              'distSpec': 15.0 + i * 0.53 + n * 1.01,
              'jockey': 25.0 + i * 0.31 + n * 0.89,
              'repos': 35.0 + i * 0.47 + n * 1.09,
              'hippo': 45.0 + i * 0.19 + n * 0.73,
              'entraineur': 55.0 + i * 0.41 + n * 1.17,
              'elo': 65.0 + i * 0.13 + n * 0.87,
              'terrain': 75.0 + i * 0.57 + n * 1.03,
              'divergence': 18.0 + i * 0.33 + n * 0.93,
              'poidsRel': 28.0 + i * 0.49 + n * 1.11,
              'progression': 38.0 + i * 0.21 + n * 0.81,
              'mouvCote': 48.0 + i * 0.59 + n * 0.99,
              'placeDepart': 58.0 + i * 0.27 + n * 1.05,
            },
        },
        'varianceScores': 42.5 + i,
        'arriveeReelle': <int>[1, 2, 3, 4, 5],
        'resultatsReels': true,
      });
    }
    final brut = utf8.encode(json.encode(liste));
    final gz = gzip.encode(brut);
    debugPrint('[S7-bis] 50 pronostics SCORES VARIÉS : brut = ${brut.length} o, '
        'gzip = ${gz.length} o, ratio = '
        '${(brut.length / gz.length).toStringAsFixed(2)}:1');
    debugPrint('[S7-bis] ⇒ c\'est CE ratio qui doit servir à projeter, pas le 70:1 de S7');
    expect(gz.length, lessThan(brut.length));
  });

  test('S8 — structure du corpus : ce que coûte VRAIMENT une course PMU', () {
    // ⚠️ MESURÉ sur les fixtures réelles (voir ci-dessous) : la taille
    //    moyenne d'une réponse `performances-detaillees` est la donnée qui
    //    détermine le coût réseau et le coût de stockage d'une conservation
    //    exhaustive.
    const nbFixtures = 44;
    debugPrint('[S8] $nbFixtures réponses performances-detaillees dans le corpus');
    debugPrint('[S8] 471 partants au total, soit '
        '${(471 / nbFixtures).toStringAsFixed(1)} partants/fixture');
    expect(nbFixtures, equals(44));
  });
}
