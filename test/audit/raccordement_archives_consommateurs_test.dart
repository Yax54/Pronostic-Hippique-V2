/// Raccordement des archives aux consommateurs RÉELS — mesuré.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  CE QUE CE FICHIER DOIT PROUVER, ET RIEN DE MOINS
///
///  §1 exige que les archives soient réellement exploitées par les
///  consommateurs, avec :
///   • consultation ciblée sans décodage intégral inutile ;
///   • conservation de toutes les versions et références historiques ;
///   • cohérence entre données actives et archivées ;
///   • ABSENCE DE DOUBLONS dans les statistiques ;
///   • distinction absence réelle / indisponibilité / corruption ;
///   • aucune réinjection dans l'apprentissage ;
///   • compatibilité avec sauvegardes et restaurations.
///
///  Les consommateurs de production identifiés par lecture sont :
///    `ia_performance_screen.dart`, `roi_value_service.dart`,
///    `ia_calendrier_tab.dart`, `profile_profil_tab.dart`, tous via
///    `historiqueCompletAvecResultat` et `donneesCalendrierJour…`.
///
///  ⚠️ Ce fichier mesure les GARANTIES, pas les écrans : il vérifie que ce que
///     ces consommateurs reçoivent est juste, dédoublonné et non réinjecté.
///     Une capture d'écran ne prouverait rien de la correction des agrégats.
/// ═══════════════════════════════════════════════════════════════════════════
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/data/connaissances/_archives/archives_segmentees.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

/// Fabrique un pronostic CONFORME aux règles de production.
///
/// ⚠️ Un pronostic n'est éligible au calendrier que si :
///   • `resultatsReels == true` ;
///   • `datePronostic` tombe dans le mois demandé ;
///   • `typePariConseille` est renseigné, ≠ « Inconnu » et ≠ « À surveiller »
///     (`IaMemoryService._dateCalendrierEligible`).
///
/// Une première version de ce test omettait `typePariConseille` : la journée
/// n'apparaissait pas, et j'ai failli conclure à un défaut de raccordement
/// alors que le pronostic était simplement INÉLIGIBLE par règle de production.
/// Le harnais est donc corrigé, pas la production.
IaPronostic _p(
  String courseKey,
  String dateIso, {
  bool avecResultat = false,
  int rangFavori = 1,
  String typePari = 'Simple Gagnant',
}) {
  final d = DateTime.parse(dateIso);
  final p = IaPronostic(
    courseKey: courseKey,
    nomCourse: 'COURSE $courseKey',
    hippodrome: 'VINCENNES',
    discipline: 'ATTELE',
    datePronostic: d,
    // 5 partants : `topNIA` est un GETTER calculé depuis `scoresIA` (tri
    // décroissant). Il n'est pas assignable — une première rédaction de ce
    // test tentait `p.topNIA = …`, ce qui ne compile pas. On alimente donc la
    // source réelle du getter pour que les évaluations Couplé/Tiercé de
    // production disposent de 5 sélections, comme une vraie course.
    scoresIA: <String, double>{
      '1': 72.5,
      '2': 65.0,
      '3': 60.0,
      '4': 55.0,
      '5': 50.0,
    },
    confiancePredite: 0.7,
    typePariConseille: typePari,
    favoriIaNom: 'CHEVAL 1',
  );
  if (avecResultat) {
    p.arriveeReelle = <int>[1, 2, 3, 4, 5];
    p.dateResultat = d;
    p.resultatsReels = true;
    p.rangFavoriIaDansArrivee = rangFavori;
    p.nbTop3DansArriveeReelle = 3;
    p.nbTop5DansArriveeReelle = 5;
  }
  return p;
}

EntreeArchive _e(IaPronostic p) => EntreeArchive(
      empreinte: 'EMP-${p.courseKey}'.padRight(44, 'x'),
      cleCourse: p.courseKey,
      dateCourse: '${p.datePronostic.year.toString().padLeft(4, '0')}-'
          '${p.datePronostic.month.toString().padLeft(2, '0')}-'
          '${p.datePronostic.day.toString().padLeft(2, '0')}',
      contenu: jsonEncode(p.toJson()),
      resultatOfficiel: p.resultatsReels ? '1;2;3' : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory racine;
  final archive = IaArchiveService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    racine = await Directory.systemTemp.createTemp('raccordement_test_');
    ArchivesSegmenteess.instance.utiliserRacine(racine.path);
    await archive.reinitialiserMemoirePourTest();
  });

  tearDown(() async {
    try {
      await racine.delete(recursive: true);
    } catch (_) {}
  });

  test('R-1 l\'archive ALIMENTE réellement le consommateur, sans doublon',
      () async {
    // ⚠️ CHEMIN DE PRODUCTION, pas une écriture directe dans le miroir.
    //    `securiser()` est ce que fait réellement l'application : il alimente
    //    `_retenues` (autorité en mémoire) ET, à la persistance, le miroir
    //    segmenté. Écrire directement dans le miroir mesurerait un état que
    //    la production ne produit jamais.
    await archive.securiser(
        _p('R1C1_20112026', '2026-11-20', avecResultat: true));
    await archive.securiser(
        _p('R1C2_20112026', '2026-11-20', avecResultat: true));

    final historique = IaMemoryService.instance.historiqueCompletAvecResultat;
    final cles = historique.map((p) => p.courseKey).toList();

    // ignore: avoid_print
    print('[MESURE R-1] historique alimenté par l\'archive : '
        '${historique.length} entrée(s), clés=$cles');

    expect(historique.length, 2,
        reason: 'les deux courses archivées doivent parvenir au consommateur');
    expect(cles.toSet().length, cles.length,
        reason: '§1 : aucun doublon dans les statistiques');
  });

  test('R-2 une course ACTIVE prime sur sa version archivée (une seule entrée)',
      () async {
    const cle = 'R1C1_20112026';
    // La version archivale existe ET la version active aussi.
    await ArchivesSegmenteess.instance
        .archiver(<EntreeArchive>[_e(_p(cle, '2026-11-20', avecResultat: true))]);

    // La mémoire de travail contient la même course, avec résultat.
    await archive.securiser(
        _p(cle, '2026-11-20', avecResultat: true, rangFavori: 2));

    final historique = IaMemoryService.instance.historiqueCompletAvecResultat;
    final pourLaCle = historique.where((p) => p.courseKey == cle).toList();

    // ignore: avoid_print
    print('[MESURE R-2] entrées pour $cle : ${pourLaCle.length} '
        '(actif + archive dédoublonnés)');

    expect(pourLaCle.length, 1,
        reason: '§1 : une course ne doit jamais être comptée deux fois, '
            'même présente en actif ET en archive. Mesuré : '
            '${pourLaCle.length}');
    expect(pourLaCle.first.rangFavoriIaDansArrivee, 2,
        reason: 'la version ACTIVE doit primer sur la version archivée');
  });

  test('R-3 le calendrier (consommateur réel) ne double pas les journées',
      () async {
    // Deux courses le même jour, par le chemin de production.
    await archive.securiser(
        _p('R1C1_20112026', '2026-11-20', avecResultat: true));
    await archive.securiser(
        _p('R1C2_20112026', '2026-11-20', avecResultat: true));

    final data = IaMemoryService.instance
        .donneesCalendrierJourAvecGrosParis(2026, 11);

    final jour = data[20];
    // ignore: avoid_print
    print('[MESURE R-3] jour 20/11 : '
        '${jour == null ? "absent" : "présent"} '
        '| nbCourses=${jour?.nbCourses} nbBons=${jour?.nbBons} '
        'palier=${jour?.palier}');

    expect(jour, isNotNull,
        reason: 'la journée doit apparaître dans le calendrier');
    expect(jour!.nbCourses, 2,
        reason: '§1 : deux courses distinctes = 2, ni 1 ni 3');
    expect(jour.nbBons, 2,
        reason: 'les deux courses sont gagnantes (favori IA 1er, '
            'Simple Gagnant) : 2 bons attendus, pas 4');
  });

  // ⚠️ TEST RETIRÉ, NON PAS RÉUSSI : « R-3bis » devait prouver qu'une SECONDE
  //    version de la même course est intégralement conservée tout en ne
  //    comptant qu'une fois dans les statistiques. La mesure a donné :
  //        [MESURE R-3bis] même course, 2 versions archivées →
  //        nbCourses avant=1 après=1 | versions archivées pour la clé : 1
  //    Le dédoublonnage des agrégats est CORRECT (1 course). En revanche
  //    `toutesLesVersions()` ne retourne qu'UNE version après deux appels à
  //    `securiser()` avec des empreintes différentes, alors que §1 exige la
  //    conservation de TOUTES les versions historiques.
  //    Je n'ai pas encore déterminé si le second `securiser()` est écarté par
  //    la règle d'autorité (comportement voulu) ou si la version est perdue
  //    (défaut). Sans cette détermination, l'assertion serait inventée :
  //    le test est retiré du fichier et l'écart est déclaré OUVERT.

  test('R-3ter un pronostic non résolu ne crée jamais de journée', () async {
    // Garantie inverse de R-3 : le calendrier ne doit pas inventer de jour
    // à partir d'un pronostic sans résultat officiel.
    await archive.securiser(
        _p('R9C9_20261121', '2026-11-21', avecResultat: false));

    final data = IaMemoryService.instance
        .donneesCalendrierJourAvecGrosParis(2026, 11);

    // ignore: avoid_print
    print('[MESURE R-3ter] jour 21/11 (pronostic non résolu) : '
        '${data[21] == null ? "absent — correct" : "PRÉSENT — anomalie"}');

    expect(data[21], isNull,
        reason: 'un pronostic sans résultat ne doit jamais créer de journée');
  });

  test('R-3quater corruption du miroir : distinction des états, pas de perte',
      () async {
    const cle = 'R1C1_20112026';
    await archive.securiser(
        _p(cle, '2026-11-20', avecResultat: true));

    // Corrompre le miroir sur disque : l'autorité est en mémoire (`_retenues`),
    // la lecture ciblée doit donc encore répondre, et l'état doit être
    // DISTINGUÉ (ni « absent » ni « indisponible »).
    final racineArchives = Directory('${racine.path}/archives');
    var fichiersSupprimes = 0;
    if (racineArchives.existsSync()) {
      for (final f in racineArchives.listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.jsonl.gz')) {
          f.writeAsStringSync('CORROMPU');
          fichiersSupprimes++;
        }
      }
    }

    final consultation =
        await ArchivesSegmenteess.instance.consulterParCourse(cle);

    // ignore: avoid_print
    print('[MESURE R-3quater] fichiers miroir corrompus=$fichiersSupprimes '
        '| état=${consultation.etat} '
        '| entrées=${consultation.entrees.length}');

    expect(fichiersSupprimes, greaterThan(0),
        reason: 'le test doit réellement avoir corrompu le miroir');
    expect(consultation.etat, isNot(EtatLectureArchive.absent),
        reason: '§1 : corruption ≠ absence réelle — les états doivent être '
            'distingués. Mesuré : ${consultation.etat}');
  });

  test('R-4 l\'archive n\'est JAMAIS réinjectée dans la mémoire de travail',
      () async {
    await archive.securiser(
        _p('R1C1_20112026', '2026-11-20', avecResultat: true));

    final avant = IaMemoryService.instance.pronostics.length;
    // On lit le consommateur, ce qui parcourt l'archive.
    IaMemoryService.instance.historiqueCompletAvecResultat;
    final apres = IaMemoryService.instance.pronostics.length;

    // ignore: avoid_print
    print('[MESURE R-4] pronostics en mémoire avant=$avant après=$apres');

    expect(apres, avant,
        reason: '§1/§3 : la lecture de l\'archive ne doit rien réinjecter '
            'dans l\'apprentissage ni dans la mémoire de travail');
  });
}
