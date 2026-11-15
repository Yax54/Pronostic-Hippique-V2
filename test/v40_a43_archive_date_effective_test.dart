// ═══════════════════════════════════════════════════════════════════════════
//  A4-3 — LECTURE DES ARCHIVES PAR DATE EFFECTIVE
//
//  Objet : vérifier que `versionsDuMoisParDate()` retrouve un pronostic
//  archivé selon le mois de sa `datePronostic`, même lorsqu'il est
//  physiquement rangé dans un autre shard mensuel.
//
//  PÉRIMÈTRE INTERDIT (non modifié par A4-3, non testé ici comme modifiable) :
//   • M1 (`_purgerVieuxPronostics`) et la purge de 90 jours ;
//   • plafond `_maxPronostics` (600) ;
//   • règles de réussite, règles ⭐ Premium, règles 🔥 Gros Paris ;
//   • « Quasi gagnants » ;
//   • gradient descent, `_poids`, `_seuils`, TOP 3, ELO,
//     `analyseJourneeComplete()` ;
//   • dates historiques, shards physiques, règles d'autorité.
//
//  A4-4, A4-5 et la recherche ⭐ dans les archives ne sont PAS traités ici.
//
//  ⚠️ NEUTRALISATION DE M1 : le flag `ia_precision_migrated_v3` est posé à
//     `true` dans le store simulé. Sans lui, la migration one-shot déclenche
//     un `_save()` pendant `_load()`, donc la purge M1 (A4-1 non corrigée),
//     qui fausserait les mesures.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  OUTILS
// ───────────────────────────────────────────────────────────────────────────

const String kPronosticsKey = 'ia_pronostics_v2';
const String kFlagMigration = 'ia_precision_migrated_v3';
const String kShardPrefix = 'ia_archive_v1_';

/// Arrivée où les 5 premiers chevaux IA sont exactement placés → GAGNANT.
const List<int> arriveeGagnante = <int>[3, 7, 1, 5, 2];

/// Arrivée où AUCUN cheval IA ({3,7,1,5,2}) n'est placé → PERDANT.
const List<int> arriveePerdante = <int>[9, 8, 6, 4, 10];

const Map<String, double> scoresIA = <String, double>{
  '3': 92.0, '7': 84.0, '1': 76.0, '5': 68.0, '2': 60.0,
};

/// Pronostic synthétique.
IaPronostic prono({
  required String cle,
  required DateTime jour,
  bool resolu = true,
  bool gagnant = true,
  String typePari = 'Quinté+',
}) =>
    IaPronostic(
      courseKey: cle,
      nomCourse: 'Course audit ${cle.substring(cle.length - 2)}',
      hippodrome: 'Vincennes',
      discipline: 'Trot Attelé',
      datePronostic: jour,
      dateResultat: resolu ? jour : null,
      scoresIA: scoresIA,
      scoresCriteres: const <String, ScoresCriteres>{},
      resultatsReels: resolu,
      arriveeReelle: resolu
          ? (gagnant ? arriveeGagnante : arriveePerdante)
          : null,
      typePariConseille: typePari,
      confiancePredite: 71.0,
      varianceScores: 12.5,
      favoriIaNom: 'Cheval 3',
      coteFavoriPmu: 3.4,
      cotesPmuParNumero: const <String, double>{'3': 3.4, '7': 6.1},
    );

/// Encodage identique à `IaArchiveService._encoderVersions` :
/// base64(gzip(json)).
String encoderShard(List<IaPronostic> versions) {
  final jsonStr = json.encode(versions.map((p) => p.toJson()).toList());
  return base64Encode(GZipCodec().encode(utf8.encode(jsonStr)));
}

/// Démarre sur un store simulé contenant les shards fournis (mémoire vide).
Future<void> amorcerShards(Map<String, List<IaPronostic>> shards) async {
  final store = <String, Object>{
    'flutter.$kFlagMigration': true,
    'flutter.$kPronosticsKey': <String>[],
  };
  shards.forEach((mois, liste) {
    store['flutter.$kShardPrefix$mois'] = encoderShard(liste);
  });
  SharedPreferences.setMockInitialValues(store);
  SharedPreferences.resetStatic();
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
  await IaArchiveService.instance.charger();
}

/// Redémarrage dur : vide l'état RAM, relit le store tel qu'il est.
Future<void> redemarrer() async {
  final prefs = await SharedPreferences.getInstance();
  final snapshot = <String, Object>{};
  for (final k in prefs.getKeys()) {
    final v = prefs.get(k);
    if (v is String) snapshot['flutter.$k'] = v;
    if (v is List<String>) snapshot['flutter.$k'] = v;
    if (v is bool) snapshot['flutter.$k'] = v;
  }
  SharedPreferences.setMockInitialValues(snapshot);
  SharedPreferences.resetStatic();
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
  await IaArchiveService.instance.charger();
}

/// Empreintes distinctes d'une liste, pour mesurer les doublons.
Set<String> empreintesDe(List<IaPronostic> liste) =>
    liste.map((p) => IaArchiveService.empreinteDe(p)).toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════ A4-3-1 · rangement CORRECT ═════════════════════════
  test('A4-3-1 — archive rangée dans le bon mois : lisible', () async {
    await amorcerShards(<String, List<IaPronostic>>{
      '2024-06': <IaPronostic>[
        prono(cle: 'R1C1_15062024', jour: DateTime(2024, 6, 15)),
      ],
    });
    final a = IaArchiveService.instance;
    final parDate = a.versionsDuMoisParDate('2024-06');
    final parShard = a.versionsDuMois('2024-06');

    expect(parDate, hasLength(1));
    expect(parDate.first.courseKey, 'R1C1_15062024');
    // Équivalence stricte avec l'ancien comportement.
    expect(
      parDate.map((p) => p.courseKey).toSet(),
      parShard.map((p) => p.courseKey).toSet(),
    );
    // ignore: avoid_print
    print('A4-3-1 parDate=${parDate.length} parShard=${parShard.length} '
        '→ équivalence true');
  });

  // ═════════════════════ A4-3-2 · rangement ERRONÉ ══════════════════════════
  test('A4-3-2 — archive rangée dans un mauvais mois : retrouvée', () async {
    // datePronostic = juin 2024, shard physique = 2024-03
    await amorcerShards(<String, List<IaPronostic>>{
      '2024-03': <IaPronostic>[
        prono(cle: 'R1C2_15062024', jour: DateTime(2024, 6, 15)),
      ],
    });
    final a = IaArchiveService.instance;

    // Ancien comportement : invisible des deux mois.
    expect(a.versionsDuMois('2024-06'), isEmpty,
        reason: 'aucune version rangée dans le shard 2024-06');
    // Nouveau comportement : retrouvée par date.
    final moisReel = a.versionsDuMoisParDate('2024-06');
    expect(moisReel, hasLength(1));
    expect(moisReel.first.courseKey, 'R1C2_15062024');
    expect(moisReel.first.datePronostic, DateTime(2024, 6, 15));
    // Et toujours invisible du mois du shard : la date ne change pas.
    expect(a.versionsDuMoisParDate('2024-03'), isEmpty,
        reason: 'la date effective est juin, pas mars');

    // ignore: avoid_print
    print('A4-3-2 shard=2024-03 date=2024-06 | parDate(2024-06)=1 '
        'parDate(2024-03)=0 parShard(2024-06)=0');
  });

  // ═════════════════════ A4-3-3 · GAGNANT / PERDANT ═════════════════════════
  test('A4-3-3 — gagnant et perdant mal rangés : réussites correctes',
      () async {
    await amorcerShards(<String, List<IaPronostic>>{
      '2024-01': <IaPronostic>[
        prono(
            cle: 'R1C3_15062024',
            jour: DateTime(2024, 6, 15),
            gagnant: true),
      ],
      '2024-02': <IaPronostic>[
        prono(
            cle: 'R2C4_16062024',
            jour: DateTime(2024, 6, 16),
            gagnant: false),
      ],
    });
    final svc = IaMemoryService.instance;
    final data = svc.donneesCalendrierJour(2024, 6);

    // Jour 15 : gagnant → présent, 1 course, 1 bon.
    expect(data[15], isNotNull, reason: 'jour gagnant rétabli');
    expect(data[15]!.nbCourses, 1);
    expect(data[15]!.nbBons, 1);

    // Jour 16 : perdant → présent, 1 course, 0 bon (aucune fausse victoire).
    expect(data[16], isNotNull, reason: 'jour perdant rétabli');
    expect(data[16]!.nbCourses, 1);
    expect(data[16]!.nbBons, 0);

    // ignore: avoid_print
    print('A4-3-3 gagnant j15: nbCourses=${data[15]!.nbCourses} '
        'nbBons=${data[15]!.nbBons} | perdant j16: '
        'nbCourses=${data[16]!.nbCourses} nbBons=${data[16]!.nbBons}');
  });

  // ═════════════════════ A4-3-4 · versions multiples ════════════════════════
  test('A4-3-4 — plusieurs versions d\'une course, shards différents',
      () async {
    const cle = 'R1C5_15062024';
    // v1 : non résolue, shard 2024-01
    // v2 : résolue gagnante, shard 2024-04
    // v3 : résolue, arrivée différente, shard 2024-06
    final v1 = prono(cle: cle, jour: DateTime(2024, 6, 15), resolu: false);
    final v2 = prono(cle: cle, jour: DateTime(2024, 6, 15), gagnant: true);
    final v3 = IaPronostic(
      courseKey: cle,
      nomCourse: 'v3',
      hippodrome: 'Vincennes',
      discipline: 'Trot Attelé',
      datePronostic: DateTime(2024, 6, 15),
      dateResultat: DateTime(2024, 6, 15),
      scoresIA: scoresIA,
      scoresCriteres: const <String, ScoresCriteres>{},
      resultatsReels: true,
      arriveeReelle: const <int>[7, 3, 1, 5, 2],
      typePariConseille: 'Quinté+',
      favoriIaNom: 'Cheval 3',
    );

    await amorcerShards(<String, List<IaPronostic>>{
      '2024-01': <IaPronostic>[v1],
      '2024-04': <IaPronostic>[v2],
      '2024-06': <IaPronostic>[v3],
    });
    final a = IaArchiveService.instance;

    expect(a.toutesLesVersions(cle), hasLength(3),
        reason: 'les 3 versions sont bien archivées');
    final parDate = a.versionsDuMoisParDate('2024-06');

    // Une seule entrée, pas trois.
    expect(parDate, hasLength(1));
    expect(parDate.first.courseKey, cle);
    // ignore: avoid_print
    print('A4-3-4 versions archivées=3 | parDate(2024-06)=${parDate.length} '
        '| rang retenu=${IaArchiveService.rangDe(parDate.first)}');
  });

  // ═════════════════════ A4-3-5 · AUTORITÉ ══════════════════════════════════
  test('A4-3-5 — la version la plus autoritaire est retenue', () async {
    const cle = 'R1C6_15062024';
    final nonResolue =
        prono(cle: cle, jour: DateTime(2024, 6, 15), resolu: false);
    final resolue = prono(cle: cle, jour: DateTime(2024, 6, 15), gagnant: true);

    await amorcerShards(<String, List<IaPronostic>>{
      '2024-01': <IaPronostic>[nonResolue],
      '2024-04': <IaPronostic>[resolue],
    });
    final a = IaArchiveService.instance;
    final retenue = a.versionRetenue(cle)!;
    final parDate = a.versionsDuMoisParDate('2024-06');

    expect(parDate, hasLength(1));
    // La version retournée EST la version retenue par l'autorité.
    expect(IaArchiveService.empreinteDe(parDate.first),
        IaArchiveService.empreinteDe(retenue));
    expect(parDate.first.resultatsReels, isTrue,
        reason: 'la version résolue est plus autoritaire que la non résolue');
    expect(IaArchiveService.rangDe(parDate.first), 2);
    // ignore: avoid_print
    print('A4-3-5 retenue rang=${IaArchiveService.rangDe(parDate.first)} '
        'résolue=${parDate.first.resultatsReels}');
  });

  // ═════════════════════ A4-3-6 · AUCUN DOUBLON ═════════════════════════════
  test('A4-3-6 — aucun doublon, même empreinte dans deux shards', () async {
    final p = prono(cle: 'R1C7_15062024', jour: DateTime(2024, 6, 15));
    await amorcerShards(<String, List<IaPronostic>>{
      '2024-01': <IaPronostic>[p],
      '2024-06': <IaPronostic>[p], // même empreinte, rejouée
    });
    final a = IaArchiveService.instance;
    final parDate = a.versionsDuMoisParDate('2024-06');

    expect(parDate, hasLength(1), reason: 'une seule entrée malgré 2 shards');
    expect(empreintesDe(parDate), hasLength(1));
    expect(parDate.map((p) => p.courseKey).toSet(), hasLength(1));

    // Le calendrier ne compte qu'une course.
    final data = IaMemoryService.instance.donneesCalendrierJour(2024, 6);
    expect(data[15]!.nbCourses, 1);

    // ignore: avoid_print
    print('A4-3-6 parDate=${parDate.length} '
        'empreintes=${empreintesDe(parDate).length} '
        'calendrier nbCourses=${data[15]!.nbCourses}');
  });

  // ═════════════════════ A4-3-7 · MÉMOIRE PRIORITAIRE ══════════════════════
  test('A4-3-7 — la mémoire active reste prioritaire', () async {
    const cle = 'R1C8_15062024';
    final enMemoire = prono(cle: cle, jour: DateTime(2024, 6, 15), gagnant: true);
    final enArchive =
        prono(cle: cle, jour: DateTime(2024, 6, 15), gagnant: false);

    final store = <String, Object>{
      'flutter.$kFlagMigration': true,
      'flutter.$kPronosticsKey': <String>[json.encode(enMemoire.toJson())],
      'flutter.${kShardPrefix}2024-02':
          encoderShard(<IaPronostic>[enArchive]),
    };
    SharedPreferences.setMockInitialValues(store);
    SharedPreferences.resetStatic();
    await IaArchiveService.instance.reinitialiserMemoirePourTest();
    await IaMemoryService.instance.recharger();
    await IaArchiveService.instance.charger();

    final data = IaMemoryService.instance.donneesCalendrierJour(2024, 6);
    expect(data[15], isNotNull);
    // Une seule course : l'archive ne s'ajoute pas à la mémoire.
    expect(data[15]!.nbCourses, 1);
    // Le pronostic retenu est celui de la MÉMOIRE (gagnant → 1 bon).
    expect(data[15]!.pronostics.first.resultatsReels, isTrue);
    expect(data[15]!.nbBons, 1);

    // ignore: avoid_print
    print('A4-3-7 nbCourses=${data[15]!.nbCourses} '
        'nbBons=${data[15]!.nbBons} (mémoire prioritaire)');
  });

  // ═════════════════════ A4-3-8 · REDÉMARRAGE ═══════════════════════════════
  test('A4-3-8 — persistance après redémarrage', () async {
    await amorcerShards(<String, List<IaPronostic>>{
      '2024-03': <IaPronostic>[
        prono(cle: 'R1C9_15062024', jour: DateTime(2024, 6, 15)),
      ],
    });
    expect(
        IaArchiveService.instance.versionsDuMoisParDate('2024-06'), hasLength(1));

    await redemarrer();

    final apres = IaArchiveService.instance.versionsDuMoisParDate('2024-06');
    expect(apres, hasLength(1), reason: 'index reconstruit au chargement');
    expect(apres.first.courseKey, 'R1C9_15062024');
    expect(apres.first.datePronostic, DateTime(2024, 6, 15));

    final data = IaMemoryService.instance.donneesCalendrierJour(2024, 6);
    expect(data[15], isNotNull);

    // ignore: avoid_print
    print('A4-3-8 après redémarrage parDate=${apres.length} '
        'jour15=${data.containsKey(15)}');
  });

  // ═════════════════════ A4-3-9 · RÉINITIALISATION ══════════════════════════
  test('A4-3-9 — cohérence de l\'index après réinitialisation', () async {
    await amorcerShards(<String, List<IaPronostic>>{
      '2024-03': <IaPronostic>[
        prono(cle: 'R1C10_15062024', jour: DateTime(2024, 6, 15)),
      ],
    });
    expect(
        IaArchiveService.instance.versionsDuMoisParDate('2024-06'), hasLength(1));

    // Étape 1 — vidage PUR de l'état RAM (sans relecture) :
    // l'index doit disparaître avec les shards, aucun orphelin.
    IaArchiveService.instance.oublierChargementPourTest();
    expect(IaArchiveService.instance.versionsDuMoisParDate('2024-06'), isEmpty,
        reason: 'aucun index orphelin après vidage');
    expect(IaArchiveService.instance.versionsDuMois('2024-03'), isEmpty);
    expect(IaArchiveService.instance.moisConnus, isEmpty);

    // Étape 2 — rechargement : l'index est reconstruit à l'identique.
    await IaArchiveService.instance.charger();
    expect(
        IaArchiveService.instance.versionsDuMoisParDate('2024-06'), hasLength(1),
        reason: 'index reconstruit après rechargement');

    // Étape 3 — réinitialisation complète (vidage + relecture) :
    // toujours 1, jamais 2 (pas de double indexation).
    await IaArchiveService.instance.reinitialiserMemoirePourTest();
    final apresReinit =
        IaArchiveService.instance.versionsDuMoisParDate('2024-06');
    expect(apresReinit, hasLength(1),
        reason: 'aucune double indexation après réinitialisation');

    // ignore: avoid_print
    print('A4-3-9 vidage → 0 | rechargement → 1 | réinit → ${apresReinit.length}');
  });

  // ═════════════════════ A4-3-10 · EFFACEMENT TOTAL ═════════════════════════
  test('A4-3-10 — cohérence de l\'index après effacement total', () async {
    await amorcerShards(<String, List<IaPronostic>>{
      '2024-03': <IaPronostic>[
        prono(cle: 'R1C11_15062024', jour: DateTime(2024, 6, 15)),
      ],
    });
    final a = IaArchiveService.instance;
    expect(a.versionsDuMoisParDate('2024-06'), hasLength(1));

    await a.effacerTout();

    expect(a.versionsDuMoisParDate('2024-06'), isEmpty);
    expect(a.toutesLesVersionsArchivees(), isEmpty);
    expect(a.moisConnus, isEmpty);
    expect(a.nbVersionsArchivees, 0);

    // ignore: avoid_print
    print('A4-3-10 après effacerTout : parDate=${a.versionsDuMoisParDate('2024-06').length} '
        'mois=${a.moisConnus}');
  });

  // ═════════════════════ A4-3-11 · RESTAURATION ═════════════════════════════
  test('A4-3-11 — cohérence de l\'index après restauration', () async {
    await amorcerShards(<String, List<IaPronostic>>{
      '2024-06': <IaPronostic>[
        prono(cle: 'R1C12_15062024', jour: DateTime(2024, 6, 15)),
      ],
    });
    final a = IaArchiveService.instance;
    expect(a.versionsDuMoisParDate('2024-06'), hasLength(1));

    // Sauvegarde : une version supplémentaire, datée de juin, rangée en mars.
    final importee = prono(cle: 'R1C13_16062024', jour: DateTime(2024, 6, 16));
    final backup = <String, dynamic>{
      'shards': <String, dynamic>{
        '2024-03': encoderShard(<IaPronostic>[importee]),
      },
    };
    final res = await a.restaurerDepuisBackup(backup);
    expect(res.succes, isTrue);

    final apres = a.versionsDuMoisParDate('2024-06');
    expect(apres, hasLength(2), reason: 'la version importée est indexée');
    expect(apres.map((p) => p.courseKey).toSet(),
        <String>{'R1C12_15062024', 'R1C13_16062024'});
    expect(empreintesDe(apres), hasLength(2));

    // ignore: avoid_print
    print('A4-3-11 restauration → parDate(2024-06)=${apres.length} '
        'clés=${apres.map((p) => p.courseKey).toList()..sort()}');
  });

  // ═════════════════════ A4-3-12 · ÉQUIVALENCE ══════════════════════════════
  test('A4-3-12 — équivalence avec l\'ancien comportement (24 mois)',
      () async {
    // Archive correctement rangée : chaque version dans le shard de sa date.
    final shards = <String, List<IaPronostic>>{};
    for (int m = 1; m <= 12; m++) {
      final mois = '2023-${m.toString().padLeft(2, '0')}';
      shards[mois] = <IaPronostic>[
        for (int d = 1; d <= 5; d++)
          prono(
            cle: 'R${d}C${m}_${d.toString().padLeft(2, '0')}'
                '${m.toString().padLeft(2, '0')}2023',
            jour: DateTime(2023, m, d),
          ),
      ];
    }
    for (int m = 1; m <= 12; m++) {
      final mois = '2024-${m.toString().padLeft(2, '0')}';
      shards[mois] = <IaPronostic>[
        for (int d = 1; d <= 5; d++)
          prono(
            cle: 'R${d}C${m + 20}_${d.toString().padLeft(2, '0')}'
                '${m.toString().padLeft(2, '0')}2024',
            jour: DateTime(2024, m, d),
          ),
      ];
    }
    await amorcerShards(shards);
    final a = IaArchiveService.instance;

    var identiques = 0;
    for (final mois in a.moisConnus) {
      final parDate = a.versionsDuMoisParDate(mois)
          .map((p) => IaArchiveService.empreinteDe(p))
          .toSet();
      final parShard = a.versionsDuMois(mois)
          .map((p) => IaArchiveService.empreinteDe(p))
          .toSet();
      expect(parDate, parShard, reason: 'mois $mois non équivalent');
      identiques++;
    }
    expect(identiques, 24);

    // ignore: avoid_print
    print('A4-3-12 équivalence stricte sur $identiques mois');
  });

  // ═════════════════════ A4-3-13 · AUCUNE DATE MODIFIÉE ════════════════════
  test('A4-3-13 — aucune date ni aucun shard physique modifiés', () async {
    final origine = DateTime(2024, 6, 15);
    await amorcerShards(<String, List<IaPronostic>>{
      '2024-03': <IaPronostic>[prono(cle: 'R1C14_15062024', jour: origine)],
    });
    final a = IaArchiveService.instance;

    final avant = a
        .toutesLesVersionsArchivees()
        .map((p) => '${p.courseKey}|${p.datePronostic.toIso8601String()}')
        .toList();
    final moisAvant = List<String>.from(a.moisConnus);

    for (int i = 0; i < 50; i++) {
      a.versionsDuMoisParDate('2024-06');
      a.versionsDuMoisParDate('2024-03');
    }

    final apres = a
        .toutesLesVersionsArchivees()
        .map((p) => '${p.courseKey}|${p.datePronostic.toIso8601String()}')
        .toList();

    expect(apres, avant, reason: 'dates et clés strictement inchangées');
    expect(a.moisConnus, moisAvant, reason: 'shards physiques inchangés');
    expect(a.moisConnus, <String>['2024-03'],
        reason: 'le rangement n\'est pas réparé');

    // ignore: avoid_print
    print('A4-3-13 dates inchangées | shards=${a.moisConnus}');
  });

  // ═════════════════════ A4-3-14 · MÉCANISMES IA INTACTS ════════════════════
  test('A4-3-14 — poids et seuils strictement inchangés', () async {
    await amorcerShards(<String, List<IaPronostic>>{
      '2024-03': <IaPronostic>[
        prono(cle: 'R1C15_15062024', jour: DateTime(2024, 6, 15)),
      ],
    });
    final svc = IaMemoryService.instance;
    final poidsAvant = json.encode(svc.poids.toJson());
    final seuilsAvant = json.encode(svc.seuilsConfiance.toJson());

    // Lectures répétées + calcul du calendrier.
    for (int i = 0; i < 20; i++) {
      svc.donneesCalendrierJour(2024, 6);
    }

    final poidsApres = json.encode(svc.poids.toJson());
    final seuilsApres = json.encode(svc.seuilsConfiance.toJson());
    expect(poidsApres, poidsAvant, reason: 'poids INCHANGÉS');
    expect(seuilsApres, seuilsAvant, reason: 'seuils INCHANGÉS');

    // ignore: avoid_print
    print('A4-3-14 poids identiques=true seuils identiques=true');
  });

  // ═════════════════════ A4-3-15 · FILTRE MÉTIER INTACT ═════════════════════
  test('A4-3-15 — filtre métier du calendrier inchangé', () async {
    await amorcerShards(<String, List<IaPronostic>>{
      '2024-03': <IaPronostic>[
        // Type vide → jamais compté dans le calendrier.
        prono(
            cle: 'R1C16_15062024',
            jour: DateTime(2024, 6, 15),
            typePari: ''),
        // « À surveiller » → jamais compté (A4-4 non traitée).
        prono(
            cle: 'R2C17_16062024',
            jour: DateTime(2024, 6, 16),
            typePari: 'À surveiller'),
        // Type valide → compté.
        prono(cle: 'R3C18_17062024', jour: DateTime(2024, 6, 17)),
      ],
    });
    final data = IaMemoryService.instance.donneesCalendrierJour(2024, 6);

    expect(data.containsKey(15), isFalse, reason: 'type vide exclu');
    expect(data.containsKey(16), isFalse, reason: 'À surveiller exclu');
    expect(data.containsKey(17), isTrue, reason: 'type valide compté');

    // Les 3 versions existent bien dans l'index par date.
    expect(
        IaArchiveService.instance.versionsDuMoisParDate('2024-06'), hasLength(3),
        reason: 'l\'index ne filtre pas : le filtre métier reste en aval');

    // ignore: avoid_print
    print('A4-3-15 jours calendrier=${data.keys.toList()..sort()} '
        '| index=3 (filtre en aval non modifié)');
  });
}
