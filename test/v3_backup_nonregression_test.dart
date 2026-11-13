// ═══════════════════════════════════════════════════════════════════════════
//  V3 — NON-RÉGRESSION D3 : Backup, sauvegarde et intégrité des données
//
//  ⚠️  FICHIER DE TEST uniquement. Aucune modification de lib/.
//
//  Vérifie que D3 (restauration des ELO dans l'isolate) et que les
//  fonctions de sauvegarde/restauration ne perdent ni ne corrompent :
//
//    T1  scoresCriteres survit à un cycle toJson -> fromJson
//    T2  scoresCriteres survit à la compression gzip+base64 (backup réel)
//    T3  Les 19 critères sont préservés, y compris 'elo'
//    T4  ELO : exporterPourBackup -> chargerDepuisMapIsolate (chemin D3)
//    T5  ELO : les ratings ne sont ni perdus ni modifiés par le transport
//    T6  Ancien pronostic : scoresCriteres vides ne deviennent pas remplis
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io'; // GZipCodec — même import que ia_memory_service.dart:34

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

String _cleElo(String nom, String discipline) {
  final nomNorm = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  return '$nomNorm|${EloService.normaliserDiscipline(discipline)}';
}

ScoresCriteres _scoresCriteresExemple({double elo = 63.5}) => ScoresCriteres(
      forme: 71.0,
      gains: 55.5,
      record: 48.0,
      cote: 62.0,
      constance: 66.5,
      victoires: 40.0,
      discipline: 52.0,
      distSpec: 58.0,
      jockey: 60.5,
      repos: 45.0,
      hippo: 50.0,
      entraineur: 49.5,
      elo: elo,
      terrain: 54.0,
      divergence: 57.5,
      poidsRel: 51.0,
      progression: 46.5,
      mouvCote: 50.0,
      placeDepart: 53.0,
    );

IaPronostic _pronosticExemple({
  required String courseKey,
  Map<String, ScoresCriteres>? criteres,
  bool resultatsReels = false,
}) {
  return IaPronostic(
    courseKey: courseKey,
    nomCourse: 'PRIX DE TEST',
    hippodrome: 'Vincennes',
    discipline: 'Trot Attelé',
    datePronostic: DateTime(2026, 5, 21, 14, 30),
    scoresIA: const {'1': 82.5, '2': 71.0, '3': 60.25},
    scoresCriteres: criteres ??
        {
          '1': _scoresCriteresExemple(elo: 63.5),
          '2': _scoresCriteresExemple(elo: 37.5),
          '3': _scoresCriteresExemple(elo: 12.0),
        },
    varianceScores: 124.5,
    confiancePredite: 78.0,
    typePariConseille: 'Couplé Gagnant',
    precisionIA: 66.0,
    favoriIaNom: 'CHEVAL A',
    resultatsReels: resultatsReels,
    arriveeReelle: resultatsReels ? const [1, 2, 3] : null,
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EloService.instance.reinitialiser();
  });

  // ═════════════════════════════════════════════════════════════════════
  // T1 — Sérialisation JSON : scoresCriteres conservé à l'identique.
  //      C'est le cœur du backup (ia_pronostics_v2 / _v2_gz).
  // ═════════════════════════════════════════════════════════════════════
  test('V3/T1 — scoresCriteres survit à toJson → fromJson', () {
    final original = _pronosticExemple(courseKey: 'R1C1_21052026');
    final json = original.toJson();
    final restaure = IaPronostic.fromJson(json);

    expect(restaure.courseKey, original.courseKey);
    expect(restaure.scoresIA, original.scoresIA);
    expect(restaure.scoresCriteres.length, original.scoresCriteres.length,
        reason: 'Aucun partant ne doit être perdu');

    for (final numero in original.scoresCriteres.keys) {
      final a = original.scoresCriteres[numero]!;
      final b = restaure.scoresCriteres[numero]!;
      expect(b.forme, closeTo(a.forme, 1e-9));
      expect(b.elo, closeTo(a.elo, 1e-9), reason: 'Le critère M doit survivre');
      expect(b.mouvCote, closeTo(a.mouvCote, 1e-9));
      expect(b.placeDepart, closeTo(a.placeDepart, 1e-9));
    }
  });

  // ═════════════════════════════════════════════════════════════════════
  // T2 — Compression gzip+base64 : c'est le chemin RÉEL de _save()
  //      quand _useCompression && length > 20 (ia_pronostics_v2_gz).
  // ═════════════════════════════════════════════════════════════════════
  test('V3/T2 — scoresCriteres survit à la compression gzip+base64', () {
    final pronostics = List.generate(
      25,
      (i) => _pronosticExemple(courseKey: 'R1C${i + 1}_21052026'),
    );

    // Reproduit exactement ia_memory_service._save() (l.1651-1656)
    final jsonStr = json.encode(pronostics.map((p) => p.toJson()).toList());
    final gzipped = GZipCodec().encode(utf8.encode(jsonStr));
    final b64 = base64Encode(gzipped);

    // Reproduit le chemin de lecture
    final raw = base64Decode(b64);
    final decoded = utf8.decode(GZipCodec().decode(raw));
    final list = (jsonDecode(decoded) as List<dynamic>)
        .map((e) => IaPronostic.fromJson(e as Map<String, dynamic>))
        .toList();

    expect(list.length, 25, reason: 'Aucun pronostic perdu à la compression');
    for (final p in list) {
      expect(p.scoresCriteres.length, 3,
          reason: 'Les critères survivent au cycle gzip pour ${p.courseKey}');
      expect(p.scoresCriteres['1']!.elo, closeTo(63.5, 1e-9));
    }
  });

  // ═════════════════════════════════════════════════════════════════════
  // T3 — Les 19 critères sont tous préservés, aucun n'est oublié.
  //      Détecte toute régression si un champ est ajouté à ScoresCriteres
  //      sans être ajouté à toJson/fromJson (comme mouvCote l'avait été).
  // ═════════════════════════════════════════════════════════════════════
  test('V3/T3 — les 19 critères sont tous sérialisés', () {
    final sc = _scoresCriteresExemple();
    final restaure = ScoresCriteres.fromJson(sc.toJson());

    const attendus = {
      'forme': 71.0, 'gains': 55.5, 'record': 48.0, 'cote': 62.0,
      'constance': 66.5, 'victoires': 40.0, 'discipline': 52.0,
      'distSpec': 58.0, 'jockey': 60.5, 'repos': 45.0, 'hippo': 50.0,
      'entraineur': 49.5, 'elo': 63.5, 'terrain': 54.0,
      'divergence': 57.5, 'poidsRel': 51.0, 'progression': 46.5,
      'mouvCote': 50.0, 'placeDepart': 53.0,
    };

    expect(attendus.length, 19, reason: 'Référence : 19 critères A→S');

    attendus.forEach((critere, valeurAttendue) {
      final obtenue = restaure.valeurPourCritere(critere);
      expect(obtenue, closeTo(valeurAttendue, 1e-9),
          reason: 'Le critère "$critere" doit être préservé à l\'identique');
    });
  });

  // ═════════════════════════════════════════════════════════════════════
  // T4 — Chaîne D3 : exporterPourBackup -> chargerDepuisMapIsolate.
  //      Vérifie que la méthode AJOUTÉE par D3 reconstruit exactement
  //      l'état exporté (c'est ce que fait l'isolate Android).
  // ═════════════════════════════════════════════════════════════════════
  test('V3/T4 — exporterPourBackup → chargerDepuisMapIsolate : identique',
      () async {
    const disc = 'Trot Attelé';
    await EloService.instance.importerDepuisBackup({
      _cleElo('CHEVAL A', disc):
          const EloScore(nomCheval: 'CHEVAL A', rating: 1800.0, nbCourses: 12)
              .toJson(),
      _cleElo('CHEVAL B', disc):
          const EloScore(nomCheval: 'CHEVAL B', rating: 1234.5, nbCourses: 3)
              .toJson(),
    });

    final exporte = EloService.instance.exporterPourBackup();
    expect(exporte.length, 2);

    // Simule l'isolate : instance réinitialisée
    await EloService.instance.reinitialiser();
    expect(EloService.instance.getScore('CHEVAL A', discipline: disc).rating,
        closeTo(1500.0, 0.01), reason: 'État neutre avant restauration');

    // Restauration D3
    EloService.instance.chargerDepuisMapIsolate(exporte);

    expect(EloService.instance.getScore('CHEVAL A', discipline: disc).rating,
        closeTo(1800.0, 0.01));
    expect(EloService.instance.getScore('CHEVAL B', discipline: disc).rating,
        closeTo(1234.5, 0.01),
        reason: 'Les décimales doivent être conservées');

    // Second export = identique au premier (aller-retour stable)
    final reExporte = EloService.instance.exporterPourBackup();
    expect(jsonEncode(reExporte), jsonEncode(exporte),
        reason: 'Aller-retour strictement stable');
  });

  // ═════════════════════════════════════════════════════════════════════
  // T5 — chargerDepuisMapIsolate n'ALTÈRE pas les ratings.
  //      Rappel de la règle : D3 ne touche aucune formule ELO.
  // ═════════════════════════════════════════════════════════════════════
  test('V3/T5 — chargerDepuisMapIsolate ne modifie aucun rating', () {
    const disc = 'Trot Attelé';
    final source = {
      _cleElo('CHEVAL A', disc): const EloScore(
              nomCheval: 'CHEVAL A',
              rating: 1800.0,
              nbCourses: 12,
              variationMois: 45.5)
          .toJson(),
    };

    EloService.instance.chargerDepuisMapIsolate(source);

    final score = EloService.instance.getScore('CHEVAL A', discipline: disc);
    expect(score.rating, closeTo(1800.0, 1e-9), reason: 'Rating intact');
    expect(score.nbCourses, 12, reason: 'nbCourses intact');
    expect(score.variationMois, closeTo(45.5, 1e-9),
        reason: 'variationMois intact');

    // Le format JSON ne doit pas avoir été réécrit différemment
    expect(jsonEncode(EloService.instance.exporterPourBackup()), jsonEncode(source),
        reason: 'Aucune transformation appliquée aux valeurs');
  });

  // ═════════════════════════════════════════════════════════════════════
  // T6 — Aucun remplissage rétroactif.
  //      Un pronostic ancien à scoresCriteres vides DOIT rester vide.
  //      C'est la garantie qu'on ne "reconstruit" pas les 559 anciennes
  //      courses avec les poids actuels (corruption refusée).
  // ═════════════════════════════════════════════════════════════════════
  test('V3/T6 — un ancien pronostic sans critères reste sans critères', () {
    final ancien = _pronosticExemple(
      courseKey: 'R1C1_01012026',
      criteres: const {}, // ← les 559 anciennes courses
      resultatsReels: true,
    );
    // Aller-retour backup : ne doit rien inventer
    final restaure = IaPronostic.fromJson(ancien.toJson());
    expect(restaure.scoresCriteres, isEmpty,
        reason: 'Aucun critère ne doit être fabriqué rétroactivement');
    expect(restaure.resultatsReels, isTrue,
        reason: 'Le résultat réel doit être conservé');
    expect(restaure.arriveeReelle, const [1, 2, 3]);
  });
}
