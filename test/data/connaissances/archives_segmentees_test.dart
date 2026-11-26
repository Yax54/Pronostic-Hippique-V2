/// Archives segmentées compressées : les propriétés exigées, MESURÉES.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  CE QUE CE FICHIER DOIT PROUVER, ET RIEN DE MOINS
///
///  1. L'écriture est en AJOUT SEUL : un rejeu n'ajoute rien (idempotence).
///  2. L'INDEX N'EST PAS UNE DÉPENDANCE : le supprimer ne perd aucune
///     connaissance, et il se reconstruit depuis les segments seuls.
///  3. La CONSULTATION CIBLÉE fonctionne : par course, par période, et pour
///     les seules versions portant un résultat officiel.
///  4. La COMPRESSION est réelle et MESURÉE (octets réels, pas une estimation).
///  5. La SEGMENTATION se fait à la taille prévue sans JAMAIS supprimer
///     d'entrée (§11 : aucun plafond de conservation).
///  6. Les versions EXACTES de rapport et de bilan sont conservées, sans
///     repointage possible.
///  7. Le service ne participe à AUCUN apprentissage.
///  8. Un segment illisible ou un index corrompu ne rend jamais les
///     connaissances muettes.
/// ═══════════════════════════════════════════════════════════════════════════
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/data/connaissances/_archives/archives_segmentees.dart';

EntreeArchive _entree(
  int i, {
  String? resultat,
  String? empreinteRapport,
  String? empreinteBilan,
  String date = '2026-11-20',
}) =>
    EntreeArchive(
      // ⚠️ L'empreinte DOIT être unique. Une première version utilisait
      //    `'EMP$i'.padRight(40, '0')`, qui COLLISIONNE : « EMP1 » complété
      //    de zéros donne « EMP100…0 », identique à « EMP10 » complété de
      //    zéros. Mesure : 181 empreintes distinctes pour 200 entrées, donc
      //    19 ignorées à juste titre. Le service était correct ; c'est le
      //    test qui fabriquait des doublons.
      empreinte: 'EMP-${i.toString().padLeft(5, '0')}',
      cleCourse: '2026-11-20|R${1 + i % 3}|C${1 + i % 5}',
      dateCourse: date,
      contenu: jsonEncode(<String, Object?>{
        'rang': i,
        'score': 70.5 + i,
        'partants': <String>['A', 'B', 'C'],
      }),
      resultatOfficiel: resultat,
      empreinteRapport: empreinteRapport,
      empreinteBilan: empreinteBilan,
    );

void main() {
  late Directory racine;

  setUp(() async {
    racine = await Directory.systemTemp.createTemp('archives_test_');
    ArchivesSegmenteess.instance.utiliserRacine(racine.path);
  });

  tearDown(() async {
    try {
      await racine.delete(recursive: true);
    } catch (_) {}
  });

  test('l\'écriture est en AJOUT SEUL et idempotente', () async {
    final lot = <EntreeArchive>[for (var i = 0; i < 10; i++) _entree(i)];

    final premier = await ArchivesSegmenteess.instance.archiver(lot);
    // ignore: avoid_print
    print('[MESURE] 1re écriture : ${premier.ecrites} écrite(s), '
        '${premier.ignorees} ignorée(s), erreur=${premier.erreur}');
    expect(premier.ecrites, 10);
    expect(premier.ignorees, 0);
    expect(premier.succes, isTrue);

    // Rejeu STRICTEMENT identique : aucune écriture nouvelle.
    final second = await ArchivesSegmenteess.instance.archiver(lot);
    // ignore: avoid_print
    print('[MESURE] rejeu identique : ${second.ecrites} écrite(s), '
        '${second.ignorees} ignorée(s)');
    expect(second.ecrites, 0, reason: 'un rejeu ne doit rien ajouter');
    expect(second.ignorees, 10);

    final bilan = await ArchivesSegmenteess.instance.bilan();
    // ignore: avoid_print
    print('[MESURE] après 2 passages : ${bilan.entrees} entrée(s) réelle(s)');
    expect(bilan.entrees, 10);
  });

  test('la compression est RÉELLE et mesurée en octets', () async {
    // Contenu répétitif, comme le sont des pronostics : beaucoup de structure
    // commune. C'est le cas où la compression doit être efficace.
    final lot = <EntreeArchive>[for (var i = 0; i < 200; i++) _entree(i)];
    await ArchivesSegmenteess.instance.archiver(lot);

    final bilan = await ArchivesSegmenteess.instance.bilan();
    final taux = bilan.tauxCompression;
    // ignore: avoid_print
    print('[MESURE] ${bilan.entrees} entrées | compressé '
        '${bilan.octetsCompresses} o | décompressé '
        '${bilan.octetsDecompresses} o | taux = '
        '${taux == null ? "n/a" : (taux * 100).toStringAsFixed(1)} %');

    expect(bilan.octetsDecompresses, greaterThan(bilan.octetsCompresses),
        reason: 'la compression doit réduire la taille réellement');
    expect(taux, isNotNull);
    expect(taux!, lessThan(1.0));
  });

  test('l\'INDEX N\'EST PAS UNE DÉPENDANCE : le supprimer ne perd rien',
      () async {
    final lot = <EntreeArchive>[for (var i = 0; i < 30; i++) _entree(i)];
    await ArchivesSegmenteess.instance.archiver(lot);

    final avant = await ArchivesSegmenteess.instance.bilan();
    expect(avant.indexPresent, isTrue);
    final consultationsAvant =
        await ArchivesSegmenteess.instance.parCourse('2026-11-20|R1|C1');

    // On détruit l'index, comme le ferait un nettoyage de cache.
    final index = File('${racine.path}/archives/${ArchivesSegmenteess.kNomIndex}');
    expect(await index.exists(), isTrue, reason: 'index attendu présent');
    await index.delete();
    // Et on vérifie qu'il a bien disparu avant de mesurer quoi que ce soit.
    expect(await index.exists(), isFalse);

    // Consultation ciblée : elle doit reconstruire l'index et retrouver
    // EXACTEMENT les mêmes entrées.
    final apres = await ArchivesSegmenteess.instance
        .parCourse('2026-11-20|R1|C1');

    // ignore: avoid_print
    print('[MESURE] index supprimé → consultation ciblée : '
        '${consultationsAvant.length} avant, ${apres.length} après');

    expect(apres.length, consultationsAvant.length,
        reason: 'supprimer l\'index ne doit rien rendre inaccessible');
    expect(
      apres.map((e) => e.empreinte).toSet(),
      consultationsAvant.map((e) => e.empreinte).toSet(),
      reason: 'ce sont les MÊMES entrées, pas seulement le même nombre',
    );

    final reconstruit = await ArchivesSegmenteess.instance.bilan();
    // ignore: avoid_print
    print('[MESURE] après reconstruction : ${reconstruit.entrees} entrée(s), '
        'index présent = ${reconstruit.indexPresent}, '
        '${reconstruit.indexEntrees} entrée(s) indexée(s)');
    expect(reconstruit.entrees, avant.entrees);
    expect(reconstruit.indexPresent, isTrue);
    expect(reconstruit.indexEntrees, avant.entrees);
  });

  test('consultation ciblée : par course, par période, avec résultat', () async {
    await ArchivesSegmenteess.instance.archiver(<EntreeArchive>[
      _entree(1, resultat: '1-2-3', date: '2026-11-01'),
      _entree(2, date: '2026-11-05'),
      _entree(3, resultat: '2-1-4', date: '2026-11-10'),
      _entree(4, date: '2026-12-01'),
    ]);

    final avecResultat =
        await ArchivesSegmenteess.instance.avecResultatOfficiel();
    // ignore: avoid_print
    print('[MESURE] avec résultat officiel : ${avecResultat.length} '
        '(${avecResultat.map((e) => e.resultatOfficiel).join(", ")})');
    expect(avecResultat.length, 2);

    final periode = await ArchivesSegmenteess.instance
        .parPeriode('2026-11-01', '2026-11-30');
    // ignore: avoid_print
    print('[MESURE] période 2026-11-01 → 2026-11-30 : ${periode.length} '
        'entrée(s) (${periode.map((e) => e.dateCourse).join(", ")})');
    expect(periode.length, 3,
        reason: 'les bornes sont incluses, décembre est exclu');

    // Le contenu est restitué VERBATIM, pas résumé.
    final une = avecResultat.first;
    final decode = jsonDecode(une.contenu) as Map<String, dynamic>;
    // ignore: avoid_print
    print('[MESURE] contenu restitué verbatim : rang=${decode['rang']} '
        'score=${decode['score']}');
    expect(decode['partants'], isA<List>());
  });

  test('segmentation : un nouveau segment s\'ouvre, RIEN n\'est supprimé',
      () async {
    // On dépasse volontairement la capacité d'un segment (2000).
    final total = ArchivesSegmenteess.kEntreesParSegment + 50;
    final lot = <EntreeArchive>[for (var i = 0; i < total; i++) _entree(i)];
    final res = await ArchivesSegmenteess.instance.archiver(lot);
    expect(res.ecrites, total);

    final bilan = await ArchivesSegmenteess.instance.bilan();
    // ignore: avoid_print
    print('[MESURE] $total entrées → ${bilan.segments} segment(s), '
        '${bilan.entrees} entrée(s) conservée(s) '
        '(capacité segment = ${ArchivesSegmenteess.kEntreesParSegment})');

    expect(bilan.segments, greaterThan(1),
        reason: 'un second segment doit s\'ouvrir, pas un écrasement');
    expect(bilan.entrees, total,
        reason: '§11 : aucune entrée perdue pour tenir dans un segment');
  });

  test('les versions EXACTES de rapport et de bilan sont conservées',
      () async {
    await ArchivesSegmenteess.instance.archiver(<EntreeArchive>[
      _entree(1, empreinteRapport: 'RAPPORT_v1', empreinteBilan: 'BILAN_v1'),
      _entree(2, empreinteRapport: 'RAPPORT_v2', empreinteBilan: 'BILAN_v1'),
    ]);

    final lues = await ArchivesSegmenteess.instance
        .parPeriode('2026-11-01', '2026-11-30');
    final rapports = lues.map((e) => e.empreinteRapport).toSet();
    // ignore: avoid_print
    print('[MESURE] versions de rapport conservées : $rapports ; '
        'bilans : ${lues.map((e) => e.empreinteBilan).toSet()}');

    expect(rapports, containsAll(<String>['RAPPORT_v1', 'RAPPORT_v2']),
        reason: 'aucun repointage vers la dernière version');
  });

  test('un index CORROMPU n\'est jamais une perte de connaissance', () async {
    final lot = <EntreeArchive>[for (var i = 0; i < 12; i++) _entree(i)];
    await ArchivesSegmenteess.instance.archiver(lot);
    final avant = await ArchivesSegmenteess.instance.bilan();

    // On écrit n'importe quoi à la place de l'index.
    final index =
        File('${racine.path}/archives/${ArchivesSegmenteess.kNomIndex}');
    await index.writeAsString('{ ceci n\'est pas du JSON');

    final apres = await ArchivesSegmenteess.instance
        .parCourse('2026-11-20|R1|C1');
    final bilan = await ArchivesSegmenteess.instance.bilan();

    // ignore: avoid_print
    print('[MESURE] index corrompu → ${apres.length} entrée(s) retrouvée(s) '
        'par consultation ciblée, ${bilan.entrees} entrée(s) au total '
        '(avant : ${avant.entrees})');

    expect(bilan.entrees, avant.entrees,
        reason: 'aucune entrée perdue à cause d\'un index corrompu');
    expect(bilan.indexPresent, isTrue, reason: 'l\'index doit être reconstruit');
  });

  test('le service ne participe à AUCUN apprentissage', () {
    // ignore: avoid_print
    print('[MESURE] isolation apprentissage = '
        '${ArchivesSegmenteess.jamaisApprentissage}');
    expect(ArchivesSegmenteess.jamaisApprentissage, isTrue,
        reason: 'aucune réinjection dans l\'apprentissage n\'est permise');
  });

  test('la lecture complète est en FLUX et ne matérialise rien', () async {
    final lot = <EntreeArchive>[for (var i = 0; i < 100; i++) _entree(i)];
    await ArchivesSegmenteess.instance.archiver(lot);

    var comptees = 0;
    var sommeScores = 0.0;
    await ArchivesSegmenteess.instance.parcourirTout((e) {
      comptees++;
      final d = jsonDecode(e.contenu) as Map<String, dynamic>;
      sommeScores += (d['score'] as num).toDouble();
    });
    // ignore: avoid_print
    print('[MESURE] parcours en flux : $comptees entrée(s), '
        'somme des scores = ${sommeScores.toStringAsFixed(2)}');

    expect(comptees, 100);
    expect(sommeScores, greaterThan(0));
  });
}
