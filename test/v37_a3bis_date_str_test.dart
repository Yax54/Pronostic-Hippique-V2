// ═══════════════════════════════════════════════════════════════════════════
//  V37 — A-3-bis : conservation de `dateStr` à la traversée JSON
//
//  ⚠️  FICHIER DE TEST uniquement. La correction testée porte sur
//      `lib/models/zt_models.dart` : deux ajouts seulement —
//        • `ZtCourse.fromJson` lit `dateStr` (repli sur '')
//        • `ZtCourse.toJson` écrit `dateStr`
//
//  DÉFAUT CORRIGÉ (mesuré avant correction) :
//    `ZtCourse.toJson()` n'émettait pas `dateStr` et `ZtCourse.fromJson()`
//    ne le relisait pas. Un aller-retour JSON — celui du retour d'isolate
//    (`data_refresh_service.dart:146` puis `:965`) — remettait donc
//    `dateStr` à ''. Or `heureDateTime` (zt_models.dart:815-833) fabrique
//    alors `DateTime(2000, 1, 1, h, m)`. Cette date fictive devenait
//    `datePronostic` (ia_memory_service.dart:2418), et `_save()` la
//    détruisait immédiatement via `_purgerVieuxPronostics()` (l.1087),
//    qui ne sauvegarde RIEN dans l'archive.
//
//  CE QUE CE FICHIER VÉRIFIE — les huit points demandés :
//    1. aller-retour `ZtCourse` : `dateStr` et `heureDateTime` conservés
//    2. aller-retour `ZtReunion` : la course porte la date de la réunion
//    3. divergence course/réunion : la réunion reste PRIORITAIRE
//    4. absence de date : sentinel 2000-01-01, AUCUNE date inventée
//    5. rétro-compatibilité : JSON ancien SANS la clé → `''`, sans exception
//    6. lot de production (chemin isolate) : le pronostic SURVIT à `_save()`
//    7. lot de production : `courseKey` identique à la clé d'entrée
//    8. date réellement absente : comportement OBSERVÉ, documenté comme
//       anomalie résiduelle — et NON comme une solution validée
//
//  CE QUE CES TESTS N'EXAMINENT PAS (périmètre interdit) :
//    • gradient descent   • _poids / _seuils   • TOP 3 learning
//    • analyseJourneeComplete()   • discipline   • critères   • ELO
//    • la purge des 90 jours n'est NI modifiée NI étendue
//    • A-3 (`datePronostic: DateTime.now()`) n'est NI testé NI modifié
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  FIXTURES
// ═══════════════════════════════════════════════════════════════════════════

const String kDate = '15112026'; // 15/11/2026 (ddMMyyyy)

ZtPartant _partant(int numero) => ZtPartant(
      numero: '$numero',
      nom: 'Cheval$numero',
      driver: 'Driver$numero',
      entraineur: 'Entraineur$numero',
      proprietaire: 'Proprio$numero',
      gains: '100000',
      record: '1:12.5',
      musique: '1a2a3a',
      cote: '5.0',
      ageSexe: 'H5',
      musiqueDistanceSpecifique: '1a2a',
      poids: 0,
      placeDepartInt: 0,
      joursRepos: 14,
      hippodromeActuel: 'VINCENNES',
      statsJockeyCsv: '',
      statsHippodromeCsv: '',
      statutPmu: 'PARTANT',
      statsEntraineurCsv: '',
      eloRating: 1500,
    );

ZtCourse _course({String date = kDate, int numCourse = 3}) => ZtCourse(
      numCourse: numCourse,
      anchor: '1$numCourse',
      nom: 'PRIX_DE_TEST',
      heure: '14:30',
      distance: '2700m',
      prix: '50000',
      type: 'Trot Attelé',
      piste: 'Machefer',
      categorie: 'D',
      isQuinte: true,
      pronosticZt: const [1, 2, 3, 4, 5],
      partants: List.generate(6, (i) => _partant(i + 1)),
      dateStr: date,
    );

ZtReunion _reunion({String date = kDate, int numCourse = 3}) => ZtReunion(
      code: 'R1',
      lieu: 'VINCENNES',
      discipline: 'Trot',
      dateStr: date,
      courses: [_course(date: date, numCourse: numCourse)],
    );

/// Reproduit la construction de `courseKey` telle qu'elle est faite par
/// `_calculerPronosticsBatch` (data_refresh_service.dart:93) et par
/// `_enregistrerPronosticsBatchFallback` (l.1044).
String _cle(IaCourseLike c, int numR) {
  final dep = c.heureDateTime;
  final dj = dep.day.toString().padLeft(2, '0');
  final dm = dep.month.toString().padLeft(2, '0');
  return 'R${numR}C${c.numCourse}_$dj$dm${dep.year}';
}

/// Alias minimal pour garder `_cle` lisible sans importer un type abstrait.
typedef IaCourseLike = ZtCourse;

/// Chaîne de production complète, à l'identique :
///   réunion → toJson (payload l.949) → fromJson (isolate l.87)
///   → course.toJson (retour l.146) → ZtCourse.fromJson (l.965)
ZtCourse _traverserIsolate(ZtReunion reunion) {
  final payload = reunion.toJson(); // data_refresh_service.dart:949
  final reunionIsolate = ZtReunion.fromJson(payload); // isolate, l.87
  final courseJson = reunionIsolate.courses.first.toJson(); // l.146
  return ZtCourse.fromJson(courseJson); // l.965
}

Map<String, dynamic> _itemBatch(ZtCourse course, String courseKey) {
  final (partants, criteres) =
      IaPronosticEngine.analyserCourseAvecCriteres(course);
  return {
    'courseKey': courseKey,
    'course': course,
    'partantsClasses': partants,
    'scoresCriteres': criteres,
    'confiance': course.confianceIA,
    'typePariConseille': 'Quinté+',
  };
}

// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ─────────────────────────────────────────────────────────────────────
  //  1. Aller-retour ZtCourse : dateStr ET heureDateTime conservés
  // ─────────────────────────────────────────────────────────────────────
  test('1 — aller-retour ZtCourse : dateStr et heureDateTime conservés',
      () {
    final origine = _course();
    expect(origine.dateStr, kDate);
    expect(origine.heureDateTime, DateTime(2026, 11, 15, 14, 30),
        reason: 'pré-condition : la date réelle est bien portée par l\'origine');

    final json = origine.toJson();
    expect(json.containsKey('dateStr'), isTrue,
        reason: 'A-3-bis : toJson() DOIT émettre la clé dateStr');
    expect(json['dateStr'], kDate,
        reason: 'la valeur émise est la date réelle, pas une valeur dérivée');

    final retour = ZtCourse.fromJson(json);

    expect(retour.dateStr, origine.dateStr,
        reason: 'A-3-bis : dateStr doit survivre à l\'aller-retour');
    expect(retour.heureDateTime, origine.heureDateTime,
        reason: 'la conséquence métier : heureDateTime n\'est plus 2000-01-01');
    expect(retour.heureDateTime.year, 2026);
    expect(retour.heureDateTime.month, 11);
    expect(retour.heureDateTime.day, 15);
    expect(retour.heureDateTime.hour, 14);
    expect(retour.heureDateTime.minute, 30);

    // Les autres champs restent strictement inchangés (aucune régression).
    expect(retour.numCourse, origine.numCourse);
    expect(retour.nom, origine.nom);
    expect(retour.heure, origine.heure);
    expect(retour.distance, origine.distance);
    expect(retour.prix, origine.prix);
    expect(retour.type, origine.type);
    expect(retour.piste, origine.piste);
    expect(retour.isQuinte, origine.isQuinte);
    expect(retour.pronosticZt, origine.pronosticZt);
    expect(retour.partants.length, origine.partants.length);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  2. Aller-retour ZtReunion : la course porte la date de la réunion
  // ─────────────────────────────────────────────────────────────────────
  test('2 — aller-retour ZtReunion : la course porte la date de la réunion',
      () {
    final reunion = _reunion();
    final json = reunion.toJson();

    expect(json['date'], kDate);
    final courseJson =
        (json['courses'] as List<dynamic>).first as Map<String, dynamic>;
    expect(courseJson['dateStr'], kDate,
        reason: 'A-3-bis : la clé est au niveau COURSE, distincte de '
            'la clé « date » de la réunion');

    final retour = ZtReunion.fromJson(json);

    expect(retour.dateStr, kDate);
    expect(retour.courses.single.dateStr, kDate);
    expect(retour.courses.single.heureDateTime, DateTime(2026, 11, 15, 14, 30));
    expect(_cle(retour.courses.single, 1), 'R1C3_15112026');
  });

  // ─────────────────────────────────────────────────────────────────────
  //  3. Divergence course / réunion : la RÉUNION reste prioritaire
  //     (comportement de zt_models.dart:933, préservé tel quel)
  // ─────────────────────────────────────────────────────────────────────
  test('3 — divergence : la date de la réunion reste prioritaire', () {
    final course = _course(date: '01012026'); // la course ment
    final reunion = ZtReunion(
      code: 'R1',
      lieu: 'VINCENNES',
      discipline: 'Trot',
      dateStr: kDate, // la réunion porte la vérité
      courses: [course],
    );

    final retour = ZtReunion.fromJson(reunion.toJson());

    expect(retour.courses.single.dateStr, kDate,
        reason: 'la propagation de ZtReunion.fromJson (l.933) s\'exécute '
            'APRÈS ZtCourse.fromJson : elle écrase la valeur de la course. '
            'A-3-bis ne change pas cette priorité.');
    expect(retour.courses.single.heureDateTime, DateTime(2026, 11, 15, 14, 30));
  });

  // ─────────────────────────────────────────────────────────────────────
  //  4. Absence de date : sentinel 2000-01-01, AUCUNE date inventée
  // ─────────────────────────────────────────────────────────────────────
  test('4 — date absente : sentinel 2000-01-01, aucune date inventée', () {
    final sansDate = _course(date: '');
    expect(sansDate.dateStr, '');

    final json = sansDate.toJson();
    expect(json['dateStr'], '',
        reason: 'une absence est émise comme absence, jamais comme une date');

    final retour = ZtCourse.fromJson(json);
    expect(retour.dateStr, '');
    expect(retour.heureDateTime, DateTime(2000, 1, 1, 14, 30),
        reason: 'règle « ne rien écrire plutôt que deviner » : le sentinel '
            'reste le signal d\'absence, il n\'est pas converti en date réelle');
    expect(retour.heureDateTime.year, 2000,
        reason: 'aucune invention : l\'année reste 2000, pas 2026');
  });

  // ─────────────────────────────────────────────────────────────────────
  //  5. Rétro-compatibilité : JSON ancien SANS la clé « dateStr »
  // ─────────────────────────────────────────────────────────────────────
  test('5 — rétro-compatibilité : JSON ancien sans clé dateStr', () {
    final json = _course().toJson();
    json.remove('dateStr'); // état exact d'un cache écrit avant A-3-bis
    expect(json.containsKey('dateStr'), isFalse);

    late ZtCourse retour;
    expect(
      () => retour = ZtCourse.fromJson(json),
      returnsNormally,
      reason: 'un JSON d\'avant A-3-bis ne doit jamais faire lever fromJson',
    );

    expect(retour.dateStr, '',
        reason: 'repli documenté sur la chaîne vide — aucune date inventée');
    expect(retour.heureDateTime, DateTime(2000, 1, 1, 14, 30),
        reason: 'dégradation connue et inchangée pour les entrées anciennes : '
            'le sentinel, pas une date fausse');

    // Le reste du contenu ancien est intact : aucune régression de parsing.
    expect(retour.nom, 'PRIX_DE_TEST');
    expect(retour.isQuinte, isTrue);
    expect(retour.partants.length, 6);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  6. Lot de PRODUCTION (chemin isolate) : le pronostic SURVIT
  // ─────────────────────────────────────────────────────────────────────
  test('6 — lot de production : le pronostic survit à _save()', () async {
    await IaMemoryService.instance.recharger();

    final origine = _course();
    final cle = _cle(origine, 1);
    expect(cle, 'R1C3_15112026',
        reason: 'pré-condition : la clé d\'entrée porte la date réelle');

    // Traversée RÉELLE de l'isolate (sérialisation + désérialisation).
    final courseRetour = _traverserIsolate(_reunion());
    expect(courseRetour.dateStr, kDate,
        reason: 'A-3-bis : dateStr survit au retour d\'isolate');
    expect(courseRetour.heureDateTime, DateTime(2026, 11, 15, 14, 30));

    final avant = IaMemoryService.instance.pronostics.length;
    expect(avant, 0);

    await IaMemoryService.instance
        .enregistrerPronosticsBatch([_itemBatch(courseRetour, cle)]);

    final apres = IaMemoryService.instance.pronostics;
    expect(apres, hasLength(1),
        reason: 'A-3-bis : le pronostic ne doit PLUS être purgé par M1 — '
            'avant correction, la chaîne complète donnait 0 pronostic');
    expect(apres.single.courseKey, cle);
    expect(apres.single.datePronostic, DateTime(2026, 11, 15, 14, 30),
        reason: 'datePronostic porte la date RÉELLE de la course');
    expect(apres.single.datePronostic, isNot(DateTime(2000, 1, 1, 14, 30)),
        reason: 'le sentinel 2000 ne doit plus jamais atteindre la mémoire');

    // Le pronostic est bien retrouvable par la clé réelle.
    expect(IaMemoryService.instance.getPronostic(cle), isNotNull);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  7. Lot de production : courseKey identique à la clé d'entrée
  //     (avant correction : R1C3_01012000)
  // ─────────────────────────────────────────────────────────────────────
  test('7 — lot de production : courseKey identique à la clé d\'entrée',
      () async {
    await IaMemoryService.instance.recharger();

    final cleAvant = _cle(_course(), 1);
    final cleApres = _cle(_traverserIsolate(_reunion()), 1);

    expect(cleAvant, 'R1C3_15112026');
    expect(cleApres, cleAvant,
        reason: 'A-3-bis : la clé construite dans l\'isolate ne doit plus '
            'diverger vers R1C3_01012000');
    expect(cleApres.contains('01012000'), isFalse,
        reason: 'aucune date fictive ne doit subsister dans la clé');

    await IaMemoryService.instance
        .enregistrerPronosticsBatch([_itemBatch(_traverserIsolate(_reunion()), cleAvant)]);

    expect(IaMemoryService.instance.pronostics.single.courseKey, cleAvant,
        reason: 'un résultat officiel cherché par R1C3_15112026 doit trouver '
            'le pronostic — avant correction il ne le trouvait jamais');

    // Le filtre anti-doublon de production retrouve désormais l'entrée.
    expect(IaMemoryService.instance.getPronostic(cleAvant), isNotNull,
        reason: 'data_refresh_service.dart:900 (getPronostic != null) '
            'recalculait sinon la même course à chaque cycle de 15 min');
  });

  // ─────────────────────────────────────────────────────────────────────
  //  8. Date RÉELLEMENT absente : comportement OBSERVÉ
  //
  //  ⚠️ Ce test ne valide AUCUNE solution. Il CONSTATE le comportement
  //  actuel et l'inscrit comme anomalie résiduelle, hors périmètre A-3-bis.
  //
  //  Constat : une course dont `dateStr` est vide produit
  //  `heureDateTime = 2000-01-01`, donc une `datePronostic` antérieure à
  //  J-90 ; `_purgerVieuxPronostics()` la retire au `_save()` suivant, et
  //  cette purge N'ARCHIVE PAS (elle n'appelle jamais `enregistrerEviction`).
  //  La donnée est donc PERDUE, pas déplacée.
  //
  //  Ce n'est pas un comportement souhaitable. C'est l'état réel du code,
  //  tel qu'il est, et A-3-bis ne prétend pas le corriger.
  // ─────────────────────────────────────────────────────────────────────
  test('8 — date réellement absente : comportement observé (anomalie)',
      () async {
    await IaMemoryService.instance.recharger();

    final sansDate = _traverserIsolate(
      ZtReunion(
        code: 'R1',
        lieu: 'VINCENNES',
        discipline: 'Trot',
        dateStr: '', // aucune date connue
        courses: [_course(date: '')],
      ),
    );

    // ── Constat 1 : le sentinel est produit, aucune date n'est inventée ──
    expect(sansDate.dateStr, '');
    expect(sansDate.heureDateTime, DateTime(2000, 1, 1, 14, 30),
        reason: 'OBSERVATION : date absente ⇒ sentinel 2000-01-01. '
            'Aucune date réelle n\'est devinée (« ne rien écrire plutôt '
            'que de deviner »).');

    // La clé construite porte alors la date fictive.
    final cleFictive = _cle(sansDate, 1);
    expect(cleFictive, 'R1C3_01012000',
        reason: 'OBSERVATION : la clé hérite du sentinel');

    // ── Constat 2 : la purge M1 détruit l'entrée, sans archiver ──────────
    final archiveAvant = IaArchiveService.instance.nbVersionsArchivees;

    await IaMemoryService.instance
        .enregistrerPronosticsBatch([_itemBatch(sansDate, cleFictive)]);

    final apres = IaMemoryService.instance.pronostics;
    expect(apres, isEmpty,
        reason: 'OBSERVATION : 2000-01-01 < J-90 ⇒ '
            '_purgerVieuxPronostics() retire le pronostic au _save()');

    final archiveApres = IaArchiveService.instance.nbVersionsArchivees;
    expect(archiveApres, archiveAvant,
        reason: 'OBSERVATION DÉCISIVE : la purge d\'âge n\'appelle JAMAIS '
            'enregistrerEviction / _securiserExcedentAvantEcriture. '
            'Elle ne déplace pas la donnée : elle la PERD.');

    // ── Constat 3 : ce n'est PAS traité par A-3-bis ──────────────────────
    // Aucune assertion ci-dessus ne présente cette perte comme acceptable.
    // Le présent test est documentaire : il fixe l'état réel pour qu'une
    // correction ultérieure soit mesurable. Étendre A-3-bis à ce sujet
    // (archivage avant purge, refus d'écriture, autre date de repli)
    // est explicitement HORS PÉRIMÈTRE et exige une décision séparée.
  });
}
