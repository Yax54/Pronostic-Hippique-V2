// ═══════════════════════════════════════════════════════════════════════════
//  V11 — D2/H8 paliers 1, 2 et 3
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT.
//
//  Palier 1 : recreerPronosticsManquants() accepte une dateCible optionnelle
//             et REFUSE les dates passées (garde-fou règle 3).
//  Palier 2 : comptage et recréation partent de la même date.
//  Palier 3 : recalage de _dateAnalyse après minuit.
//
//  Les paliers 1 et 2 exercent le VÉRITABLE chemin de production du service.
//  Le palier 3 étant de l'état privé de widget, il est vérifié par
//  reproduction fidèle de la règle ET lecture du code de production.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';

// ─────────────────────────── Outils ────────────────────────────────────────

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String _j(int offset) => _fmt(DateTime.now().add(Duration(days: offset)));

ZtPartant _p(int n) => ZtPartant(
      numero: '$n',
      nom: 'CHEVAL_$n',
      driver: 'D$n',
      entraineur: 'E$n',
      proprietaire: 'P$n',
      gains: '${1000 * n}',
      record: '1\'10"0',
      musique: '1a2a3a4a5a',
      cote: '4.0',
      ageSexe: '5 M',
      poids: 57.0 + n,
      placeDepartInt: n,
      joursRepos: 10 + n,
      hippodromeActuel: 'VINCENNES',
      statsJockeyCsv: 'J|15|40|12',
      statsHippodromeCsv: 'V|20|45|15',
      statsEntraineurCsv: 'E|12|33|8',
      eloRating: 1500.0 + n * 10,
      eloNbCourses: 20,
      eloVariationMois: 5.0,
      statsTerrainCsv: 'bon|6|2|4',
      gainsDernierAn: n * 5000,
    );

ZtCourse _course(int num, String date) => ZtCourse(
      numCourse: num,
      anchor: 'R1C$num',
      nom: 'PRIX_$num',
      heure: '14:15',
      distance: '2700',
      prix: '50000',
      type: 'Trot Attelé',
      piste: 'Sable',
      categorie: 'D',
      isQuinte: true,
      pronosticZt: const [1, 2, 3, 4, 5],
      partants: List.generate(8, (j) => _p(j + 1)),
      dateStr: date,
    );

ZtReunion _reunion({
  String code = 'R1',
  int nbCourses = 2,
  required String date,
}) =>
    ZtReunion(
      code: code,
      lieu: 'VINCENNES',
      discipline: 'Trot',
      dateStr: date,
      courses: List.generate(nbCourses, (i) => _course(i + 1, date)),
    );

Map<String, Object> _prefs() => <String, Object>{
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode({
        'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
        'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
        'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
        'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
        'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
        'mouvCote': 0.06, 'placeDepart': 0.03,
        'nbMisesAJour': 0, 'calibrationScore': 50.0,
      }),
      'ia_seuils_v1': json.encode({}),
      'ia_precision_v2': json.encode({}),
      'ia_stats_labels_v1': json.encode({}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
    };

/// Crée des pronostics via le chemin batch réel (aucun filtre de date).
Future<void> _creerPronostics(List<ZtReunion> reunions) async {
  final batch = <Map<String, dynamic>>[];
  for (final r in reunions) {
    final m = RegExp(r'R(\d+)').firstMatch(r.code);
    final numR = m != null ? int.tryParse(m.group(1) ?? '1') ?? 1 : 1;
    for (final c in r.courses) {
      final key = 'R${numR}C${c.numCourse}_${_fmt(c.heureDateTime)}';
      if (IaMemoryService.instance.getPronostic(key) != null) continue;
      final (pc, sc) = IaPronosticEngine.analyserCourseAvecCriteres(c);
      batch.add({
        'courseKey': key, 'course': c, 'partantsClasses': pc,
        'scoresCriteres': sc, 'confiance': c.confianceIA,
        'typePariConseille': 'Quinté+',
      });
    }
  }
  await IaMemoryService.instance.enregistrerPronosticsBatch(batch);
}

List<String> _cles() =>
    IaMemoryService.instance.pronostics.map((p) => p.courseKey).toList();

/// Reproduit `_calculerManquants()` (ia_performance_screen.dart).
(int, int) _compterManquants(List<ZtReunion> reunions, DateTime date) {
  final dateStr = _fmt(date);
  int total = 0;
  int manquants = 0;
  for (final reunion in reunions) {
    final m = RegExp(r'R(\d+)').firstMatch(reunion.code);
    final numR = m != null ? int.tryParse(m.group(1) ?? '1') ?? 1 : 1;
    for (final course in reunion.courses) {
      if (course.partants.isEmpty) continue;
      final dep = course.heureDateTime;
      if (_fmt(dep) != dateStr) continue;
      total++;
      final key = 'R${numR}C${course.numCourse}_${_fmt(dep)}';
      if (IaMemoryService.instance.getPronostic(key) == null) manquants++;
    }
  }
  return (total, manquants);
}

/// Reproduit exactement la règle insérée dans `_loadStats()` (palier 3).
DateTime recaler(DateTime dateAnalyse, bool automatique, DateTime horloge) {
  if (!automatique) return dateAnalyse;
  if (horloge.year != dateAnalyse.year ||
      horloge.month != dateAnalyse.month ||
      horloge.day != dateAnalyse.day) {
    return horloge;
  }
  return dateAnalyse;
}

// ─────────────────────────── Tests ─────────────────────────────────────────

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(_prefs());
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
  });

  // ═══════════════ PALIER 1 — dateCible optionnelle ══════════════════════

  test('H8/1a — dateCible explicite (aujourd\'hui) recrée la journée visée',
      () async {
    final auj = DateTime.now();
    final nb = await IaMemoryService.instance.recreerPronosticsManquants(
        [_reunion(nbCourses: 2, date: _fmt(auj))],
        dateCible: auj);

    // ignore: avoid_print
    print('  [H8/1a] dateCible=${_fmt(auj)} → nbCrees=$nb clés=${_cles()}');

    expect(nb, 2);
    expect(_cles().length, 2);
    for (final k in _cles()) {
      expect(k.endsWith(_fmt(auj)), isTrue);
    }
  });

  test('H8/1b — SANS dateCible : comportement historique inchangé', () async {
    final nb = await IaMemoryService.instance.recreerPronosticsManquants(
        [_reunion(nbCourses: 2, date: _fmt(DateTime.now()))]);

    // ignore: avoid_print
    print('  [H8/1b] sans dateCible → nbCrees=$nb');
    expect(nb, 2, reason: 'défaut DateTime.now() = ancien comportement');
  });

  test('H8/1c — dateCible = DATE PASSÉE : refus, aucune écriture', () async {
    final passe = DateTime.now().subtract(const Duration(days: 3));
    final nb = await IaMemoryService.instance.recreerPronosticsManquants(
        [_reunion(nbCourses: 2, date: _fmt(passe))],
        dateCible: passe);

    // ignore: avoid_print
    print('  [H8/1c] dateCible=${_fmt(passe)} (passée) → nbCrees=$nb '
        'clés=${_cles()}');

    expect(nb, 0, reason: 'garde-fou règle 3 : aucune fabrication rétroactive');
    expect(_cles(), isEmpty);
  });

  test('H8/1d — dateCible = DEMAIN : autorisée (programme anticipé)', () async {
    final demain = DateTime.now().add(const Duration(days: 1));
    final nb = await IaMemoryService.instance.recreerPronosticsManquants(
        [_reunion(nbCourses: 2, date: _fmt(demain))],
        dateCible: demain);

    // ignore: avoid_print
    print('  [H8/1d] dateCible=${_fmt(demain)} (demain) → nbCrees=$nb');

    expect(nb, 2, reason: 'le garde-fou ne bloque que le PASSÉ');
    for (final k in _cles()) {
      expect(k.endsWith(_fmt(demain)), isTrue);
    }
  });

  test('H8/1e — le refus d\'une date passée ne touche aucun pronostic existant',
      () async {
    await _creerPronostics([
      _reunion(code: 'R1', nbCourses: 1, date: _j(-1)),
      _reunion(code: 'R2', nbCourses: 1, date: _j(1)),
    ]);
    final avant = _cles().toSet();
    expect(avant.length, 2);

    final nb = await IaMemoryService.instance.recreerPronosticsManquants(
      [_reunion(code: 'R3', nbCourses: 3, date: _j(-5))],
      dateCible: DateTime.now().subtract(const Duration(days: 5)),
    );
    final apres = _cles().toSet();

    // ignore: avoid_print
    print('  [H8/1e] refus → nbCrees=$nb ; avant=$avant après=$apres');

    expect(nb, 0);
    expect(apres, avant, reason: 'règle 4 : rien ne doit disparaître');
  });

  // ═══════════ PALIER 2 — comptage et recréation alignés ═════════════════

  test('H8/2a — après recréation, le comptage de la MÊME date tombe à 0',
      () async {
    final auj = DateTime.now();
    final reunion = _reunion(nbCourses: 3, date: _fmt(auj));

    final (totalAvant, manquantsAvant) = _compterManquants([reunion], auj);
    expect(totalAvant, 3);
    expect(manquantsAvant, 3);

    final nb = await IaMemoryService.instance
        .recreerPronosticsManquants([reunion], dateCible: auj);
    final (totalApres, manquantsApres) = _compterManquants([reunion], auj);

    // ignore: avoid_print
    print('  [H8/2a] avant: total=$totalAvant manquants=$manquantsAvant | '
        'créés=$nb | après: total=$totalApres manquants=$manquantsApres');

    expect(nb, 3);
    expect(manquantsApres, 0,
        reason: 'DÉFAUT H8 corrigé : le compteur de la date affichée '
            'descend réellement à 0');
  });

  test('H8/2b — divergence : compter sur une date et recréer sur une autre '
      'laisse le compteur bloqué', () async {
    final hier = DateTime.now().subtract(const Duration(days: 1));
    final auj = DateTime.now();
    final reunions = [
      _reunion(code: 'R1', nbCourses: 2, date: _fmt(hier)),
      _reunion(code: 'R2', nbCourses: 2, date: _fmt(auj)),
    ];

    final (_, manquantsHier) = _compterManquants(reunions, hier);
    expect(manquantsHier, 2);

    // Ancien comportement : pas de dateCible → recrée AUJOURD'HUI
    final nb = await IaMemoryService.instance.recreerPronosticsManquants(reunions);
    final (_, manquantsHierApres) = _compterManquants(reunions, hier);

    // ignore: avoid_print
    print('  [H8/2b] sans dateCible : créés=$nb ; manquants sur hier '
        '$manquantsHier → $manquantsHierApres (compteur bloqué)');

    expect(nb, 2, reason: 'crée bien 2, mais sur AUJOURD\'HUI');
    expect(manquantsHierApres, 2,
        reason: 'symptôme « N manquants, 0 recréé sur la date affichée »');

    // Nouveau comportement : dateCible = hier → refusé (date passée)
    final nbCible = await IaMemoryService.instance
        .recreerPronosticsManquants(reunions, dateCible: hier);
    // ignore: avoid_print
    print('  [H8/2b] avec dateCible=hier : créés=$nbCible (refus attendu)');
    expect(nbCible, 0, reason: 'garde-fou règle 3');
  });

  // ═══════════ Préservation des chemins existants ════════════════════════

  test('H8/3a — l\'enregistrement auto accepte toujours hier, aujourd\'hui, '
      'demain', () async {
    await _creerPronostics([
      _reunion(code: 'R1', nbCourses: 1, date: _j(-1)),
      _reunion(code: 'R2', nbCourses: 1, date: _j(0)),
      _reunion(code: 'R3', nbCourses: 1, date: _j(1)),
    ]);
    final cles = _cles();
    // ignore: avoid_print
    print('  [H8/3a] batch auto → $cles');

    expect(cles.length, 3, reason: 'règle 1 : les 3 journées acceptées');
    expect(cles.any((k) => k.endsWith(_j(-1))), isTrue);
    expect(cles.any((k) => k.endsWith(_j(0))), isTrue);
    expect(cles.any((k) => k.endsWith(_j(1))), isTrue);
  });

  test('H8/3b — une recréation ne supprime aucun pronostic d\'une autre date',
      () async {
    await _creerPronostics([
      _reunion(code: 'R1', nbCourses: 1, date: _j(-2)),
      _reunion(code: 'R2', nbCourses: 1, date: _j(2)),
    ]);
    final avant = _cles().toSet();

    await IaMemoryService.instance.recreerPronosticsManquants(
        [_reunion(code: 'R3', nbCourses: 2, date: _j(0))],
        dateCible: DateTime.now());
    final apres = _cles().toSet();

    // ignore: avoid_print
    print('  [H8/3b] avant=$avant après=$apres');

    expect(avant.difference(apres), isEmpty, reason: 'aucune suppression');
    expect(apres.length, 4);
  });

  test('H8/3c — persistance et absence de doublon après redémarrage', () async {
    final auj = DateTime.now();
    await IaMemoryService.instance.recreerPronosticsManquants(
        [_reunion(nbCourses: 2, date: _fmt(auj))], dateCible: auj);
    expect(_cles().length, 2);

    await IaMemoryService.instance.recharger();
    expect(_cles().length, 2, reason: 'restaurés depuis le disque');

    final nb2 = await IaMemoryService.instance.recreerPronosticsManquants(
        [_reunion(nbCourses: 2, date: _fmt(auj))], dateCible: auj);

    // ignore: avoid_print
    print('  [H8/3c] après redémarrage : ${_cles().length} ; '
        '2e recréation → nb=$nb2');
    expect(nb2, 0);
    expect(_cles().length, 2);
  });

  // ═════════════ PALIER 3 — recalage après minuit ════════════════════════

  test('H8/4a — minuit : la date d\'analyse se réaligne sur le nouveau jour',
      () {
    final avantMinuit = DateTime(2026, 11, 13, 23, 58);
    final apresMinuit = DateTime(2026, 11, 14, 0, 2);

    final avant = recaler(avantMinuit, true, avantMinuit);
    final apres = recaler(avantMinuit, true, apresMinuit);

    // ignore: avoid_print
    print('  [H8/4a] 23h58 → ${_fmt(avant)} | après recalage à 00h02 → '
        '${_fmt(apres)}');

    expect(_fmt(avant), '13112026', reason: 'aucun changement avant minuit');
    expect(_fmt(apres), '14112026',
        reason: 'DÉFAUT corrigé : la date ne reste plus figée sur la veille');
  });

  test('H8/4b — une date choisie explicitement n\'est jamais réalignée', () {
    final choisie = DateTime(2026, 11, 10, 9, 0);
    final horloge = DateTime(2026, 11, 14, 0, 2);

    final apres = recaler(choisie, false, horloge);
    // ignore: avoid_print
    print('  [H8/4b] choisie=${_fmt(choisie)} automatique=false → '
        '${_fmt(apres)}');

    expect(_fmt(apres), '10112026',
        reason: 'un choix utilisateur ne doit pas être écrasé par l\'horloge');
  });

  test('H8/4c — la règle existe bien dans le code de production', () {
    final src = File('lib/screens/ia_performance_screen.dart').readAsStringSync();

    expect(src.contains('bool _dateAnalyseAutomatique = true;'), isTrue,
        reason: '_dateAnalyseAutomatique doit exister');

    final iLoadStats = src.indexOf('void _loadStats()');
    expect(iLoadStats, greaterThan(-1));
    final blocLoadStats = src.substring(
        iLoadStats, (iLoadStats + 1400).clamp(0, src.length));
    expect(blocLoadStats.contains('_dateAnalyseAutomatique'), isTrue,
        reason: 'le recalage doit être dans _loadStats()');
    expect(blocLoadStats.contains('_dateAnalyse = n;'), isTrue,
        reason: 'la date doit être réassignée');

    final iChoisir = src.indexOf('Future<void> _choisirDateAnalyse()');
    expect(iChoisir, greaterThan(-1));
    final blocChoisir = src.substring(
        iChoisir, (iChoisir + 1600).clamp(0, src.length));
    expect(blocChoisir.contains('_dateAnalyseAutomatique = false;'), isTrue,
        reason: 'un choix explicite doit désactiver le recalage');

    final iRecreer = src.indexOf('Future<void> _recreerPronostics()');
    expect(iRecreer, greaterThan(-1));
    final blocRecreer = src.substring(
        iRecreer, (iRecreer + 1800).clamp(0, src.length));
    expect(blocRecreer.contains('dateCible: _dateAnalyse'), isTrue,
        reason: 'palier 2 : la recréation doit viser la date affichée');

    // ignore: avoid_print
    print('  [H8/4c] drapeau + recalage + choix explicite + palier 2 : '
        'tous présents dans le code de production');
  });

  test('H8/4d — après recalage, comptage et recréation visent la même date',
      () async {
    final auj = recaler(
        DateTime.now().subtract(const Duration(days: 1)),
        true,
        DateTime.now());

    final reunion = _reunion(nbCourses: 2, date: _fmt(auj));
    final (_, manquantsAvant) = _compterManquants([reunion], auj);
    final nb = await IaMemoryService.instance
        .recreerPronosticsManquants([reunion], dateCible: auj);
    final (_, manquantsApres) = _compterManquants([reunion], auj);

    // ignore: avoid_print
    print('  [H8/4d] date recalée=${_fmt(auj)} | manquants '
        '$manquantsAvant→$manquantsApres | créés=$nb');

    expect(manquantsAvant, 2);
    expect(nb, 2);
    expect(manquantsApres, 0,
        reason: 'règle 2 : comptage et recréation alignés → convergence');
  });
}
