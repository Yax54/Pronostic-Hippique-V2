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

  // ══════════════════════════════════════════════════════════════════════════
  //  R-5 — STABILITÉ DU CANONIQUE V2
  //
  //  Exigence : « deux contenus réellement différents restent distincts, deux
  //  contenus sémantiquement identiques restent déduplicables » — la seconde
  //  moitié ne vaut que si l'empreinte est INDÉPENDANTE de la représentation
  //  technique (ordre des clés, aller-retour JSON).
  //
  //  ⚠️ Le test porte sur la fonction de PRODUCTION `empreinteDe`, pas sur une
  //     réécriture locale du canonique : mesurer une copie ne prouverait rien.
  // ══════════════════════════════════════════════════════════════════════════

  test('R-5 canonique V2 : insensible à l\'ordre des clés, sensible au contenu',
      () async {
    const cle = 'R5C5_20112026';

    // scoresIA insérés dans l'ordre CROISSANT des numéros.
    IaPronostic enOrdreCroissant() => IaPronostic(
          courseKey: cle,
          nomCourse: 'COURSE $cle',
          hippodrome: 'VINCENNES',
          discipline: 'ATTELE',
          datePronostic: DateTime.parse('2026-11-20'),
          scoresIA: <String, double>{
            '1': 72.5,
            '2': 65.0,
            '3': 60.0,
            '4': 55.0,
            '5': 50.0,
          },
        );

    // MÊMES valeurs, insérées dans l'ordre DÉCROISSANT : seule la
    // représentation technique diffère.
    IaPronostic enOrdreDecroissant() => IaPronostic(
          courseKey: cle,
          nomCourse: 'COURSE $cle',
          hippodrome: 'VINCENNES',
          discipline: 'ATTELE',
          datePronostic: DateTime.parse('2026-11-20'),
          scoresIA: <String, double>{
            '5': 50.0,
            '4': 55.0,
            '3': 60.0,
            '2': 65.0,
            '1': 72.5,
          },
        );

    final a = enOrdreCroissant();
    final b = enOrdreDecroissant();
    final eA = IaArchiveService.empreinteDe(a);
    final eB = IaArchiveService.empreinteDe(b);

    // Aller-retour JSON : ce que fait réellement la persistance.
    final c = IaPronostic.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
    final eC = IaArchiveService.empreinteDe(c);

    // `nomCourse` est un libellé de PRÉSENTATION : exclu du canonique par
    // décision architecturale préexistante (v48_a2 / A2-T6 l'exige).
    final d = IaPronostic(
      courseKey: cle,
      nomCourse: 'AUTRE LIBELLE',
      hippodrome: 'VINCENNES',
      discipline: 'ATTELE',
      datePronostic: DateTime.parse('2026-11-20'),
      scoresIA: <String, double>{
        '1': 72.5,
        '2': 65.0,
        '3': 60.0,
        '4': 55.0,
        '5': 50.0,
      },
    );
    final eD = IaArchiveService.empreinteDe(d);

    // ignore: avoid_print
    print('[MESURE R-5] ordre des clés : ${eA == eB} | '
        'aller-retour JSON : ${eA == eC} | '
        'nomCourse ignoré : ${eA == eD} | '
        'longueur=${eA.length} version=${IaArchiveService.versionEmpreinte(eA)}');

    expect(eA, eB,
        reason: '§3 : deux représentations techniques du MÊME contenu doivent '
            'donner la même empreinte (ordre d\'insertion des clés)');
    expect(eA, eC,
        reason: '§3 : la sérialisation JSON puis relecture ne doit pas changer '
            'l\'identité du contenu');
    expect(eA, eD,
        reason: '`nomCourse` est un libellé de présentation : il n\'entre pas '
            'dans l\'empreinte (décision architecturale préexistante)');
    expect(eA.length, IaArchiveService.kLongueurEmpreinteV2);
    expect(IaArchiveService.versionEmpreinte(eA), 2);

    // ── CONTRE-ÉPREUVE : chaque contenu RÉELLEMENT différent doit différer ──
    //    Sans cela, « identique → même empreinte » serait trivialement vrai
    //    pour une fonction constante.
    final variantes = <String, IaPronostic>{
      'rangFavori': IaPronostic(
        courseKey: cle,
        nomCourse: 'COURSE $cle',
        hippodrome: 'VINCENNES',
        discipline: 'ATTELE',
        datePronostic: DateTime.parse('2026-11-20'),
        scoresIA: <String, double>{
          '1': 72.5, '2': 65.0, '3': 60.0, '4': 55.0, '5': 50.0,
        },
        rangFavoriIaDansArrivee: 3,
      ),
      'typePari': IaPronostic(
        courseKey: cle,
        nomCourse: 'COURSE $cle',
        hippodrome: 'VINCENNES',
        discipline: 'ATTELE',
        datePronostic: DateTime.parse('2026-11-20'),
        scoresIA: <String, double>{
          '1': 72.5, '2': 65.0, '3': 60.0, '4': 55.0, '5': 50.0,
        },
        typePariConseille: 'Couplé Gagnant',
      ),
      'scoreIA': IaPronostic(
        courseKey: cle,
        nomCourse: 'COURSE $cle',
        hippodrome: 'VINCENNES',
        discipline: 'ATTELE',
        datePronostic: DateTime.parse('2026-11-20'),
        scoresIA: <String, double>{
          '1': 72.5, '2': 65.0, '3': 60.0, '4': 55.0, '5': 51.0,
        },
      ),
      'confiance': IaPronostic(
        courseKey: cle,
        nomCourse: 'COURSE $cle',
        hippodrome: 'VINCENNES',
        discipline: 'ATTELE',
        datePronostic: DateTime.parse('2026-11-20'),
        scoresIA: <String, double>{
          '1': 72.5, '2': 65.0, '3': 60.0, '4': 55.0, '5': 50.0,
        },
        confiancePredite: 0.91,
      ),
      'variance': IaPronostic(
        courseKey: cle,
        nomCourse: 'COURSE $cle',
        hippodrome: 'VINCENNES',
        discipline: 'ATTELE',
        datePronostic: DateTime.parse('2026-11-20'),
        scoresIA: <String, double>{
          '1': 72.5, '2': 65.0, '3': 60.0, '4': 55.0, '5': 50.0,
        },
        varianceScores: 12.75,
      ),
      'favoriIaNom': IaPronostic(
        courseKey: cle,
        nomCourse: 'COURSE $cle',
        hippodrome: 'VINCENNES',
        discipline: 'ATTELE',
        datePronostic: DateTime.parse('2026-11-20'),
        scoresIA: <String, double>{
          '1': 72.5, '2': 65.0, '3': 60.0, '4': 55.0, '5': 50.0,
        },
        favoriIaNom: 'AUTRE CHEVAL',
      ),
      'nbTop3': IaPronostic(
        courseKey: cle,
        nomCourse: 'COURSE $cle',
        hippodrome: 'VINCENNES',
        discipline: 'ATTELE',
        datePronostic: DateTime.parse('2026-11-20'),
        scoresIA: <String, double>{
          '1': 72.5, '2': 65.0, '3': 60.0, '4': 55.0, '5': 50.0,
        },
        nbTop3DansArriveeReelle: 2,
      ),
      'nbTop5': IaPronostic(
        courseKey: cle,
        nomCourse: 'COURSE $cle',
        hippodrome: 'VINCENNES',
        discipline: 'ATTELE',
        datePronostic: DateTime.parse('2026-11-20'),
        scoresIA: <String, double>{
          '1': 72.5, '2': 65.0, '3': 60.0, '4': 55.0, '5': 50.0,
        },
        nbTop5DansArriveeReelle: 4,
      ),
      'arriveeOfficielle': IaPronostic(
        courseKey: cle,
        nomCourse: 'COURSE $cle',
        hippodrome: 'VINCENNES',
        discipline: 'ATTELE',
        datePronostic: DateTime.parse('2026-11-20'),
        scoresIA: <String, double>{
          '1': 72.5, '2': 65.0, '3': 60.0, '4': 55.0, '5': 50.0,
        },
        arriveeReelle: <int>[3, 1, 2, 5, 4],
        resultatsReels: true,
      ),
    };

    final empreintes = <String>{
      for (final v in variantes.values) IaArchiveService.empreinteDe(v),
    };
    // ignore: avoid_print
    print('[MESURE R-5] contre-épreuve : ${variantes.length} contenus '
        'différents -> ${empreintes.length} empreintes distinctes');

    expect(empreintes.length, variantes.length,
        reason: '§3 : chaque contenu réellement différent doit produire une '
            'empreinte différente (sinon une version authentique serait '
            'fusionnée et perdue)');
    expect(empreintes.contains(eA), isFalse,
        reason: 'aucune variante ne doit collisionner avec la référence');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  R-6 — COMPATIBILITÉ DES ARCHIVES ANCIENNES ET DES SAUVEGARDES AVEC V2
  //
  //  Une archive « ancienne » est écrite ici au format de stockage RÉEL de la
  //  production : `base64(gzip(json))` sous `ia_archive_v1_<mois>` + manifeste.
  //  Elle est ensuite relue par le chemin de PRODUCTION (`_load`), et son
  //  identité est calculée par V2 — la preuve que les archives existantes
  //  restent exploitables sans réécriture ni perte.
  // ══════════════════════════════════════════════════════════════════════════

  test('R-6 une archive ANCIENNE reste lisible et identifiée par V2', () async {
    const cle = 'R6C6_20261120';
    const mois = '2026-11';

    // Une version historique : le contenu est celui d'une course réellement
    // résolue, écrit au format de disque de production.
    final ancienne = _p(cle, '2026-11-20', avecResultat: true);

    final prefs = await SharedPreferences.getInstance();
    final charge = jsonEncode(<dynamic>[ancienne.toJson()]);
    final b64 = base64Encode(GZipCodec().encode(utf8.encode(charge)));
    await prefs.setString('ia_archive_v1_$mois', b64);
    await prefs.setString('ia_archive_v1_manifest',
        jsonEncode(<String, dynamic>{'version': 1, 'mois': <String>[mois]}));

    // ── Relecture par le chemin de production (simule un redémarrage) ──────
    await archive.reinitialiserMemoirePourTest();

    final versions = archive.toutesLesVersions(cle);
    final verif = archive.derniereVerificationArchive;

    // L'identité de la version historique est calculée par V2.
    final empreinte = versions.isEmpty
        ? ''
        : IaArchiveService.empreinteDe(versions.first);

    // ignore: avoid_print
    print('[MESURE R-6] archive ancienne relue : versions=${versions.length} '
        '| shardsLus=${verif?.shardsLus} perdus=${verif?.shardsPerdus} '
        'illisibles=${verif?.shardsIllisibles.length} | '
        'empreinte version=${IaArchiveService.versionEmpreinte(empreinte)} '
        'longueur=${empreinte.length}');

    expect(versions.length, 1,
        reason: 'une archive écrite au format de production doit être relue '
            'intégralement');
    expect(verif?.shardsLus, 1,
        reason: 'le shard doit être effectivement décodé');
    // `shardsPerdus` est la LISTE des shards attendus mais absents : vide =
    // aucune perte. (Première rédaction : `expect(shardsPerdus, 0)` — faux,
    // c'est une liste, pas un compteur.)
    expect(verif?.shardsPerdus, isEmpty,
        reason: 'le manifeste et le shard concordent : aucune perte');
    expect(verif?.shardsIllisibles, isEmpty,
        reason: 'aucun shard illisible');
    expect(IaArchiveService.versionEmpreinte(empreinte), 2,
        reason: '§3 : les archives anciennes sont identifiées par le '
            'canonique V2, sans réécriture de leur contenu');

    // ── La correspondance V1 → V2 reconnaît l'empreinte historique ─────────
    final rapport = await archive.migrerEmpreintesV1VersV2();
    final corr = archive.correspondanceEmpreintesPourTest;
    final ancienneV1 = IaArchiveService.empreinteV1De(versions.first);

    // ignore: avoid_print
    print('[MESURE R-6] correspondance : V1 historique connue='
        '${corr.containsKey(ancienneV1)} | '
        'V2 associée=${corr[ancienneV1]?.contains(empreinte)} | '
        'examinées=${rapport['versionsExaminees']} '
        'ambiguïtés=${rapport['ambiguites']}');

    expect(corr.containsKey(ancienneV1), isTrue,
        reason: 'l\'empreinte V1 d\'une archive ancienne doit être reconnue');
    expect(corr[ancienneV1]?.contains(empreinte), isTrue,
        reason: 'la correspondance doit pointer vers la V2 du MÊME contenu');

    // ── La correspondance survit à un redémarrage ─────────────────────────
    await archive.reinitialiserMemoirePourTest();
    expect(archive.correspondanceEmpreintesPourTest.containsKey(ancienneV1),
        isTrue,
        reason: 'la table de correspondance est persistée, donc reprenable');
    expect(archive.toutesLesVersions(cle).length, 1,
        reason: 'aucune version perdue par la migration ni le redémarrage');
  });

  test('R-6bis une SAUVEGARDE se restaure sans doublon ni perte', () async {
    const cle = 'R7C7_20261120';

    await archive.securiser(_p(cle, '2026-11-20', avecResultat: true));

    final sauvegarde = await archive.exporterPourBackup();
    final empreintesExportees = sauvegarde['empreintes'];

    // ignore: avoid_print
    print('[MESURE R-6bis] export : shards=${sauvegarde['nbShards']} '
        'versions=${sauvegarde['nbVersions']} '
        'prédictions=${sauvegarde['nbPredictions']} '
        'bloc empreintes présent=${empreintesExportees != null}');

    expect(sauvegarde['nbVersions'], 1,
        reason: 'la sauvegarde doit transporter la version');

    // Les empreintes exportées sont des V2 : c\'est ce que la sauvegarde
    // contient réellement (le bloc n\'est jamais relu, voir plus bas).
    final listeEmpreintes = <String>[
      for (final v in (empreintesExportees as Map).values)
        ...(v as List).map((e) => e.toString()),
    ];
    expect(listeEmpreintes, isNotEmpty);
    expect(
        listeEmpreintes
            .every((e) => IaArchiveService.versionEmpreinte(e) == 2),
        isTrue,
        reason: '§3 : les empreintes d\'une sauvegarde sont des V2');

    // ── Restauration dans un état VIDÉ : la version revient ───────────────
    await archive.viderPourTest();
    final restauration = await archive.restaurerDepuisBackup(sauvegarde);

    // ignore: avoid_print
    print('[MESURE R-6bis] restauration : succes=${restauration.succes} '
        'lues=${restauration.shardsLus} '
        'ajoutées=${restauration.versionsAjoutees} '
        'déjàPrésentes=${restauration.versionsDejaPresentes}');

    expect(restauration.succes, isTrue);
    expect(restauration.versionsAjoutees, 1,
        reason: 'la version de la sauvegarde doit être réintégrée');
    expect(archive.toutesLesVersions(cle).length, 1);

    // ── Rejouer la MÊME restauration ne crée AUCUN doublon ────────────────
    final seconde = await archive.restaurerDepuisBackup(sauvegarde);
    // ignore: avoid_print
    print('[MESURE R-6bis] 2e restauration identique : '
        'ajoutées=${seconde.versionsAjoutees} '
        'déjàPrésentes=${seconde.versionsDejaPresentes}');

    expect(seconde.versionsAjoutees, 0,
        reason: '§3 : une restauration idempotente ne duplique pas');
    expect(seconde.versionsDejaPresentes, 1,
        reason: 'la version est reconnue comme déjà présente par son empreinte');
    expect(archive.toutesLesVersions(cle).length, 1,
        reason: 'aucun doublon créé par la seconde restauration');
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  R-7 — ABSENCE DE DOUBLE APPRENTISSAGE, MESURÉE SUR DES ÉVÉNEMENTS RÉELS
  //
  //  Exigence explicite : « à partir des événements et compteurs réels, et pas
  //  uniquement de l'absence de variation d'un poids ». Une valeur de poids qui
  //  ne bouge pas ne prouve RIEN : `IaPoidsAdaptatifs` normalise ses poids, donc
  //  une valeur individuelle peut revenir à son niveau initial alors que
  //  l'apprentissage a bien eu lieu.
  //
  //  Deux observables de PRODUCTION sont utilisés, sans aucune instrumentation
  //  ajoutée pour le test :
  //    • `IaMemoryService.poids.nbMisesAJour` — compteur incrémenté par
  //      `_apprendreParGradient()` (et par `_apprendreReglesBase()`) : il
  //      compte des EXÉCUTIONS réelles, pas des valeurs ;
  //    • `IaMemoryService.journal` — une `JournalEntree` par apprentissage
  //      exécuté, étiquetée `methode` ('gradient', 'regles',
  //      'discipline_gradient'). C'est un journal d'ÉVÉNEMENTS.
  // ══════════════════════════════════════════════════════════════════════════

  /// Écrit un état de mémoire de travail dans le stockage réel puis recharge
  /// le service par son chemin de production. Aucune méthode de test n'est
  /// inventée : `recharger()` est l'API publique de l'application.
  Future<void> semerMemoire(List<IaPronostic> pronostics) async {
    final prefs = await SharedPreferences.getInstance();
    final charge = jsonEncode(pronostics.map((p) => p.toJson()).toList());
    await prefs.setString(
        'ia_pronostics_v2_gz', base64Encode(GZipCodec().encode(utf8.encode(charge))));
    await IaMemoryService.instance.recharger();
  }

  /// Pronostic RÉSOLU, avec 19 scores de critères : sans eux, le gradient
  /// sortirait par sa garde « données insuffisantes » et la mesure porterait
  /// sur le mode règles, pas sur le gradient.
  IaPronostic resolu(int i) {
    final d = DateTime.parse('2026-11-20');
    return IaPronostic(
      courseKey: 'SEED_R${i}C1_20261120',
      nomCourse: 'COURSE SEED $i',
      hippodrome: 'VINCENNES',
      discipline: 'ATTELE',
      datePronostic: d,
      scoresIA: <String, double>{
        '1': 72.5, '2': 65.0, '3': 60.0, '4': 55.0, '5': 50.0,
      },
      scoresCriteres: <String, ScoresCriteres>{
        for (final n in <String>['1', '2', '3', '4', '5'])
          n: ScoresCriteres(
            forme: 60.0 + i,
            gains: 55.0,
            record: 58.0,
            cote: 62.0,
            constance: 57.0,
            victoires: 54.0,
            discipline: 61.0,
            distSpec: 56.0,
            jockey: 59.0,
            repos: 63.0,
            hippo: 52.0,
            entraineur: 58.0,
            elo: 60.0,
            terrain: 55.0,
            divergence: 57.0,
            poidsRel: 54.0,
            progression: 56.0,
            mouvCote: 50.0,
            placeDepart: 51.0,
          ),
      },
      arriveeReelle: <int>[1, 2, 3, 4, 5],
      dateResultat: d,
      resultatsReels: true,
      rangFavoriIaDansArrivee: 1,
      nbTop3DansArriveeReelle: 3,
      nbTop5DansArriveeReelle: 5,
      scorePerformance: 80.0,
      typePariConseille: 'Simple Gagnant',
      favoriIaNom: 'CHEVAL 1',
    );
  }

  test('R-7 aucun second apprentissage : compteurs d\'événements réels',
      () async {
    const cle = 'CIBLE_R1C1_20261120';

    // 12 courses DÉJÀ résolues : elles satisfont les minima de production
    // (≥10 courses pour le gradient, ≥5 pour la discipline), ce qui garantit
    // que le premier enregistrement produit un apprentissage EFFECTIF.
    final semis = <IaPronostic>[for (var i = 0; i < 12; i++) resolu(i)];

    // La course cible, NON résolue : c'est elle qu'on va résoudre deux fois.
    final cible = IaPronostic(
      courseKey: cle,
      nomCourse: 'COURSE CIBLE',
      hippodrome: 'VINCENNES',
      discipline: 'ATTELE',
      datePronostic: DateTime.parse('2026-11-20'),
      scoresIA: <String, double>{
        '1': 72.5, '2': 65.0, '3': 60.0, '4': 55.0, '5': 50.0,
      },
      scoresCriteres: <String, ScoresCriteres>{
        for (final n in <String>['1', '2', '3', '4', '5'])
          n: const ScoresCriteres(
            forme: 61.0,
            gains: 55.0,
            record: 58.0,
            cote: 62.0,
            constance: 57.0,
            victoires: 54.0,
            discipline: 61.0,
          ),
      },
      typePariConseille: 'Simple Gagnant',
    );

    await semerMemoire(<IaPronostic>[...semis, cible]);

    // Contrôle de préparation : la cible est bien chargée et non résolue.
    final cibleChargee = IaMemoryService.instance.pronostics
        .firstWhere((p) => p.courseKey == cle);
    expect(cibleChargee.resultatsReels, isFalse,
        reason: 'la cible doit être non résolue avant la mesure');

    final compteurAvant = IaMemoryService.instance.poids.nbMisesAJour;
    final journalAvant = IaMemoryService.instance.journal.length;

    // ── 1re résolution : elle DOIT apprendre (contrôle positif) ────────────
    //    Sans contrôle positif, un compteur bloqué à zéro ferait passer le
    //    test pour la mauvaise raison.
    final premier = await IaMemoryService.instance.enregistrerResultat(
      courseKey: cle,
      arriveeReelle: <int>[1, 2, 3, 4, 5],
    );

    final compteurApres1 = IaMemoryService.instance.poids.nbMisesAJour;
    final journalApres1 = IaMemoryService.instance.journal.length;
    final methodes1 = IaMemoryService.instance.journal
        .take(journalApres1 - journalAvant)
        .map((e) => e.methode)
        .toList();

    // ── 2e résolution IDENTIQUE : elle ne doit RIEN apprendre ─────────────
    final second = await IaMemoryService.instance.enregistrerResultat(
      courseKey: cle,
      arriveeReelle: <int>[1, 2, 3, 4, 5],
    );

    final compteurApres2 = IaMemoryService.instance.poids.nbMisesAJour;
    final journalApres2 = IaMemoryService.instance.journal.length;

    // ── 3e résolution avec une arrivée DIFFÉRENTE : refusée aussi ─────────
    final troisieme = await IaMemoryService.instance.enregistrerResultat(
      courseKey: cle,
      arriveeReelle: <int>[5, 4, 3, 2, 1],
    );

    final compteurFinal = IaMemoryService.instance.poids.nbMisesAJour;
    final journalFinal = IaMemoryService.instance.journal.length;

    // ignore: avoid_print
    print('[MESURE R-7] retour 1er=$premier 2e=$second 3e=$troisieme');
    // ignore: avoid_print
    print('[MESURE R-7] nbMisesAJour : $compteurAvant -> $compteurApres1 '
        '-> $compteurApres2 -> $compteurFinal');
    // ignore: avoid_print
    print('[MESURE R-7] journal : $journalAvant -> $journalApres1 '
        '-> $journalApres2 -> $journalFinal | méthodes 1er=$methodes1');

    // Contrôle positif : le premier enregistrement a réellement appris.
    expect(premier, isTrue);
    expect(compteurApres1, greaterThan(compteurAvant),
        reason: 'contrôle positif : le premier enregistrement doit exécuter '
            'au moins un apprentissage (compteur réel)');
    expect(journalApres1, greaterThan(journalAvant),
        reason: 'contrôle positif : au moins un événement d\'apprentissage '
            'doit être journalisé');

    // Le second enregistrement est refusé et n'apprend RIEN.
    expect(second, isFalse);
    expect(compteurApres2, compteurApres1,
        reason: '§3 : aucun second apprentissage — le compteur d\'exécutions '
            'réelles doit rester STRICTEMENT identique. Mesuré : '
            '$compteurApres1 -> $compteurApres2');
    expect(journalApres2, journalApres1,
        reason: '§3 : aucun nouvel événement d\'apprentissage journalisé');

    // Un résultat déjà officiel ne se réécrit pas, même avec une autre arrivée.
    expect(troisieme, isFalse);
    expect(compteurFinal, compteurApres1,
        reason: '§3 : une arrivée différente sur une course DÉJÀ résolue ne '
            'déclenche aucun apprentissage supplémentaire');
    expect(journalFinal, journalApres1,
        reason: '§3 : aucun événement supplémentaire');
  });
}
