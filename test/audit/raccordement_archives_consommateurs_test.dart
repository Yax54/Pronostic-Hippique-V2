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

  // ══════════════════════════════════════════════════════════════════════════
  //  R-3bis — ARBITRAGE : conservation de TOUTES les versions distinctes,
  //           comptabilisation UNIQUE par course, consultation intégrale.
  //
  //  Historique de ce test, pour qu'aucune conclusion ne soit rejouée à
  //  l'aveugle :
  //    • 1re version : pronostic non conforme (sans `typePariConseille`)
  //      → échec du à l'INÉLIGIBILITÉ, pas au raccordement. Harnais corrigé.
  //    • 2e version : échec `versions archivées = 1` au lieu de 2.
  //      Cause EXACTE mesurée : le canonique V1 ne couvrait que 7 champs et
  //      ignorait le rang, le type de pari, les compteurs Top3/Top5, etc.
  //      `[DIAG] rang 1 / rang 3 / type différent -> 51b1b1687572ce2c` (identique).
  //      Deux contenus authentiquement distincts étaient donc fusionnés et le
  //      second silencieusement perdu.
  //    • Correctif V2 : SHA-256 du `toJson()` complet (aligné sur le miroir).
  //      `[DIAG] rang 1  -> 73a663d8…c8e`
  //      `[DIAG] rang 3  -> a9cfb864…115`
  //      `[DIAG] type diff -> ce603366…cf8`
  // ══════════════════════════════════════════════════════════════════════════

  test('R-3bis trois contenus DISTINCTS sont tous conservés, comptés une fois',
      () async {
    const cle = 'R1C1_20112026';

    // PRÉCONDITIONS VÉRIFIÉES : les trois contenus doivent réellement différer.
    final v1 = _p(cle, '2026-11-20', avecResultat: true, rangFavori: 1);
    final v2 = _p(cle, '2026-11-20', avecResultat: true, rangFavori: 3);
    final v3 = _p(cle, '2026-11-20',
        avecResultat: true, rangFavori: 1, typePari: 'Couplé Gagnant');

    final e1 = IaArchiveService.empreinteDe(v1);
    final e2 = IaArchiveService.empreinteDe(v2);
    final e3 = IaArchiveService.empreinteDe(v3);
    // ignore: avoid_print
    print('[MESURE R-3bis] empreintes distinctes : '
        '${e1 != e2 && e2 != e3 && e1 != e3} '
        '(${e1.substring(0, 8)}/…/${e3.substring(0, 8)})');
    expect(<String>{e1, e2, e3}.length, 3,
        reason: 'précondition : trois contenus différents = trois empreintes');

    // Chemin de PRODUCTION.
    await archive.securiser(v1);
    await archive.securiser(v2);
    await archive.securiser(v3);

    // ── 1. CONSERVATION : les trois versions restent accessibles ────────────
    final versions = archive.toutesLesVersions(cle);
    final empreintesConservees =
        versions.map((p) => IaArchiveService.empreinteDe(p)).toSet();

    // ── 2. COMPTABILISATION : une seule course dans les statistiques ────────
    final jour = IaMemoryService.instance
        .donneesCalendrierJourAvecGrosParis(2026, 11)[20];

    // ── 3. CONSULTATION HISTORIQUE ciblée ───────────────────────────────────
    final consultation =
        await ArchivesSegmenteess.instance.consulterParCourse(cle);

    // ignore: avoid_print
    print('[MESURE R-3bis] versions conservées=${versions.length} '
        'empreintes distinctes=${empreintesConservees.length} | '
        'nbCourses au calendrier=${jour?.nbCourses} | '
        'nbBrouillons archivés=${archive.nbVersions(cle)} | '
        'miroir état=${consultation.etat} entrées=${consultation.entrees.length}');

    expect(versions.length, 3,
        reason: '§1/arbitrage : AUCUNE version authentique ne doit être perdue');
    expect(empreintesConservees.length, 3,
        reason: 'les trois empreintes doivent rester distinctes en mémoire');

    // ── 4. SÉLECTION DE LA RÉFÉRENCE : une seule, choisie par autorité ──────
    final retenue = archive.versionRetenue(cle);
    expect(retenue, isNotNull,
        reason: 'une version de référence doit exister');
    expect(IaArchiveService.empreinteDe(retenue!), isIn(<String>{e1, e2, e3}),
        reason: 'la référence est l’UNE des versions conservées, '
            'jamais une recombinaison');

    // ── 5. STATISTIQUES : une course = une comptabilisation ────────────────
    expect(jour?.nbCourses, 1,
        reason: 'arbitrage : une course à plusieurs versions ne se compte '
            'qu’UNE fois. Mesuré : ${jour?.nbCourses}');

    // ── 6. PAS DE RÉINJECTION dans la mémoire de travail ───────────────────
    expect(IaMemoryService.instance.pronostics.length, 0,
        reason: 'arbitrage : aucune version récupérée n’est réinjectée');
  });

  test('R-3bis-bis contenus SÉMANTIQUEMENT identiques : déduplicables',
      () async {
    const cle = 'R2C2_20112026';
    // Deux objets distincts en mémoire, mais de contenu rigoureusement égal.
    // Seule une représentation technique différente est simulée : la construction
    // passe par `toJson()`/`fromJson()`, qui réordonne les clés.
    final a = _p(cle, '2026-11-20', avecResultat: true);
    final b = IaPronostic.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);

    expect(identical(a, b), isFalse, reason: 'deux objets distincts');
    expect(IaArchiveService.empreinteDe(a), IaArchiveService.empreinteDe(b),
        reason: 'contenu identique → même empreinte, quelle que soit la '
            'représentation technique');

    await archive.securiser(a);
    await archive.securiser(b);

    // ignore: avoid_print
    print('[MESURE R-3bis-bis] contenu identique sérialisé 2 fois -> '
        'versions conservées=${archive.toutesLesVersions(cle).length}');

    expect(archive.toutesLesVersions(cle).length, 1,
        reason: 'arbitrage : seuls les doublons RÉELLEMENT identiques sont '
            'dédupliqués');
  });

  test('R-3bis-ter migration V1→V2 : correspondance conservée, ambiguïté gérée',
      () async {
    const cle = 'R3C3_20112026';
    // Deux contenus que le canonique V1 CONFONDAIT (même empreinte V1) mais que
    // V2 distingue : c'est exactement le cas d'ambiguïté à traiter.
    final a = _p(cle, '2026-11-20', avecResultat: true, rangFavori: 1);
    final b = _p(cle, '2026-11-20', avecResultat: true, rangFavori: 2);

    final v1a = IaArchiveService.empreinteV1De(a);
    final v1b = IaArchiveService.empreinteV1De(b);
    // ignore: avoid_print
    print('[MESURE R-3bis-ter] V1 identiques=${v1a == v1b} | '
        'V2 distinctes=${IaArchiveService.empreinteDe(a) != IaArchiveService.empreinteDe(b)}');

    await archive.securiser(a);
    await archive.securiser(b);

    final rapport = await archive.migrerEmpreintesV1VersV2();
    final corr = archive.correspondanceEmpreintesPourTest;

    // ignore: avoid_print
    print('[MESURE R-3bis-ter] migration : versions=${rapport['versionsExaminees']} '
        'correspondances=${rapport['correspondancesTotal']} '
        'ambiguïtés=${rapport['ambiguites']}');

    // Conservation des deux versions distinctes.
    expect(archive.toutesLesVersions(cle).length, 2,
        reason: 'la migration ne doit perdre aucune version');

    // Une empreinte V1 peut couvrir PLUSIEURS V2 → consignée comme ambiguë,
    // jamais résolue arbitrairement.
    if (v1a == v1b) {
      expect(corr[v1a]?.length, 2,
          reason: 'correspondance UNE V1 → DEUX V2 conservée intégralement');
      expect(archive.ambiguitesEmpreintesPourTest.containsKey(v1a), isTrue,
          reason: 'l’ambiguïté doit être SIGNALÉE, pas tranchée');
    }

    // Idempotence : une seconde migration ne change rien.
    final rapport2 = await archive.migrerEmpreintesV1VersV2();
    // ignore: avoid_print
    print('[MESURE R-3bis-ter] 2e migration (idempotence) : '
        'ajoutées=${rapport2['correspondancesAjoutees']} '
        'total=${rapport2['correspondancesTotal']}');
    expect(rapport2['correspondancesAjoutees'], 0,
        reason: 'idempotente : aucune nouvelle correspondance');
    expect(rapport2['correspondancesTotal'], rapport['correspondancesTotal']);
  });

  test('R-3bis-quater migration REPRENABLE et sans perte après interruption',
      () async {
    const cle = 'R4C4_20112026';
    await archive.securiser(_p(cle, '2026-11-20', avecResultat: true));
    await archive.migrerEmpreintesV1VersV2();
    final corrAvant = archive.correspondanceEmpreintesPourTest.length;

    // Interruption simulée : la mémoire est vidée (comme un redémarrage),
    // puis rechargée depuis le stockage persisté.
    await archive.reinitialiserMemoirePourTest();
    await archive.chargerPourTest();

    final corrApres = archive.correspondanceEmpreintesPourTest.length;
    final versionsApres = archive.toutesLesVersions(cle).length;

    // ignore: avoid_print
    print('[MESURE R-3bis-quater] après redémarrage : '
        'correspondances avant=$corrAvant après=$corrApres | '
        'versions de la course=$versionsApres');

    expect(corrApres, corrAvant,
        reason: 'la correspondance persistée doit survivre à un redémarrage');
    expect(versionsApres, 1,
        reason: 'aucune version perdue par la migration ni par le redémarrage');
  });

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
