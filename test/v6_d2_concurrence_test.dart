// ═══════════════════════════════════════════════════════════════════════════
//  V6 — D2 : concurrence entre l'enregistrement automatique des pronostics
//  (DataRefreshService) et leur recréation depuis l'écran IA
//  (ia_performance_screen::_autoRecreerSiVide / _recreerPronostics)
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/.
//
//  Chaque test porte le numéro de l'hypothèse de diagnostic qu'il vérifie.
//  Un test ROUGE = défaut reproduit (comportement observé ≠ attendu).
//  Un test VERT   = hypothèse infirmée sur ce point.
//
//  Ce que ces tests N'EXAMINENT PAS (périmètre interdit) :
//    • gradient descent   • _poids   • _seuils
//    • TOP 3 learning     • analyseJourneeComplete()
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Outils
// ───────────────────────────────────────────────────────────────────────────

/// Date du jour au format `ddmmyyyy` (format utilisé par DataRefreshService,
/// recreerPronosticsManquants et _calculerManquants).
String _dateDuJour() {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

/// Date relative au format `ddmmyyyy` (hier, etc.) — reste dans la fenêtre
/// de purge de 90 jours de `_purgerVieuxPronostics()`, pour ne pas confondre
/// « filtre de date » et « purge ».
String _dateRelative(int jours) {
  final d = DateTime.now().subtract(Duration(days: jours));
  return '${d.day.toString().padLeft(2, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.year}';
}

String _courseKey(String r, int c, [String? date]) =>
    'R${r}C${c}_${date ?? _dateDuJour()}';

/// Partant minimal mais NON neutre : valeurs distinctes par numéro, pour que
/// deux calculs successifs produisent des scores non triviaux.
ZtPartant _partant(int num, {double cote = 4.0}) => ZtPartant(
      numero: '$num',
      nom: 'CHEVAL_$num',
      driver: 'DRIVER_$num',
      entraineur: 'ENTR_$num',
      proprietaire: 'PROP_$num',
      gains: '${num * 10000}',
      record: '1\'1${num % 10}"0',
      musique: '1a2a3a4a5a',
      cote: '$cote',
      ageSexe: '${4 + num % 6} M',
      poids: 57.0 + num,
      placeDepartInt: num,
      joursRepos: 10 + num,
      hippodromeActuel: 'VINCENNES',
      statsJockeyCsv: 'JOCKEY_$num|15|40|12',
      statsHippodromeCsv: 'VINCENNES|20|45|15',
      statsEntraineurCsv: 'ENTR_$num|12|33|8',
      eloRating: 1500.0 + num * 10,
      eloNbCourses: 20,
      eloVariationMois: 5.0,
      statsTerrainCsv: 'bon|6|2|4',
      gainsDernierAn: num * 5000,
    );

ZtCourse _course({
  int numCourse = 1,
  int nbPartants = 8,
  String date = '',
  bool isQuinte = true,
}) =>
    ZtCourse(
      numCourse: numCourse,
      anchor: 'R1C$numCourse',
      nom: 'PRIX_TEST_$numCourse',
      heure: '14:15',
      distance: '2700',
      prix: '50000',
      type: 'Trot Attelé',
      piste: 'Sable',
      categorie: 'Course D',
      isQuinte: isQuinte,
      pronosticZt: const [1, 2, 3, 4, 5],
      partants: List.generate(nbPartants, (i) => _partant(i + 1)),
      dateStr: date,
    );

ZtReunion _reunion({
  String code = 'R1',
  int nbCourses = 1,
  int nbPartants = 8,
  String? date,
  bool isQuinte = true,
}) {
  final d = date ?? _dateDuJour();
  return ZtReunion(
    code: code,
    lieu: 'VINCENNES',
    discipline: 'Trot',
    dateStr: d,
    courses: List.generate(
      nbCourses,
      (i) => _course(
          numCourse: i + 1, nbPartants: nbPartants, date: d, isQuinte: isQuinte),
    ),
  );
}

/// Prefs exploitables par `_load()` (poids par défaut JSON valide).
Map<String, Object> _prefsVides() => <String, Object>{
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

/// Entrée JSON d'un ancien pronostic persisté — sert de témoin.
String _temoin(String courseKey, {DateTime? date}) => json.encode({
      'courseKey': courseKey,
      'nomCourse': 'TEMOIN',
      'hippodrome': 'PARIS',
      'discipline': 'Trot Attelé',
      'datePronostic': (date ?? DateTime(2026, 1, 1)).toIso8601String(),
      'scoresIA': {'1': 80.0, '2': 60.0},
      'scoresCriteres': {},
      'resultatsReels': false,
    });

// ───────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(_prefsVides());
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D2/H1 — `recreerPronosticsManquants()` ne fait PAS `await _load()`
  //
  //  Tous les autres écrivains commencent par `await _load()` :
  //    • enregistrerPronostic()        l.1700  ✅
  //    • enregistrerPronosticsBatch()  l.1775  ✅
  //    • invaliderEtRecalculer()       l.1875  ✅
  //    • recreerPronosticsManquants()  l.4388  ❌ AUCUN
  //
  //  Or `recharger()` (appelé par la restauration de sauvegarde,
  //  backup_service.dart:1111) fait :
  //       _loaded = false;  _pronostics.clear();  ... await _load();
  //  Pendant cet `await`, `_pronostics` est VIDE et `_loaded` est false.
  //
  //  Si la recréation part dans cette fenêtre, elle travaille sur une liste
  //  vide puis `_save()` écrit son propre contenu — soit en perdant ce que
  //  `_load()` vient de relire, soit en écrasant le disque.
  //
  //  Attendu : la recréation doit être auto-suffisante (comme ses sœurs)
  //  et ne jamais produire un état incohérent, même en concurrence avec
  //  un rechargement.
  // ═══════════════════════════════════════════════════════════════════════
  test('V6/D2-H1 — recreerPronosticsManquants() lancé pendant un recharger() '
      'ne doit ni perdre ni dupliquer', () async {
    // ── Disque : 2 témoins RÉCENTS (évite la purge > 90 jours de _save) ──
    final aujourdhui = DateTime.now();
    SharedPreferences.setMockInitialValues({
      ..._prefsVides(),
      'ia_pronostics_v2': [
        _temoin('RTEM1_01012026', date: aujourdhui),
        _temoin('RTEM2_01012026', date: aujourdhui),
      ],
    });

    await IaMemoryService.instance.recharger();
    expect(IaMemoryService.instance.pronostics.length, 2,
        reason: 'pré-requis : les 2 témoins sont chargés');

    // ── Concurrence : recharger() (restauration) + recréation (écran IA) ──
    final rechargement = IaMemoryService.instance.recharger();
    final creation = IaMemoryService.instance
        .recreerPronosticsManquants([_reunion(nbCourses: 2)]);

    final nbAnnonce = await creation;
    await rechargement;

    final apres = IaMemoryService.instance.pronostics;
    final cles = apres.map((p) => p.courseKey).toList();
    final uniques = cles.toSet();

    final prefs = await SharedPreferences.getInstance();
    final disque = prefs.getStringList('ia_pronostics_v2') ?? const [];
    final clesDisque = disque
        .map((s) => (json.decode(s) as Map<String, dynamic>)['courseKey'])
        .toList();

    // ignore: avoid_print
    print('  [D2/H1] mémoire après concurrence : $cles');
    // ignore: avoid_print
    print('  [D2/H1] disque après concurrence : $clesDisque');

    final d = _dateDuJour();
    final attendues = {'R1C1_$d', 'R1C2_$d'};
    final retrouvees = attendues.intersection(uniques);

    // ignore: avoid_print
    print('  [D2/H1] nbCrees ANNONCÉ à l\'UI = $nbAnnonce, '
        'réellement persistés = ${retrouvees.length}/2');

    // ── Les témoins ne doivent pas disparaître ──────────────────────────
    expect(cles.contains('RTEM1_01012026'), isTrue,
        reason: 'un rechargement concurrent ne doit pas faire perdre les '
            'pronostics déjà persistés');

    // ── ★ Le défaut : les créations doivent survivre ────────────────────
    expect(retrouvees, attendues,
        reason: 'les $nbAnnonce pronostics annoncés comme créés doivent '
            'réellement être en mémoire ; sinon l\'UI affiche '
            '« ✅ $nbAnnonce pronostic(s) recréé(s) » alors que rien n\'a '
            'été persisté');

    // ── Aucun doublon ───────────────────────────────────────────────────
    expect(cles.length, uniques.length,
        reason: 'aucune courseKey ne doit apparaître deux fois');

    // ── Mémoire et disque alignés ───────────────────────────────────────
    expect(clesDisque.toSet(), uniques,
        reason: 'le disque doit refléter l\'état mémoire réel');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D2/H1b — OBSERVATION : `_save()` purge les pronostics > 90 jours
  //
  //  Ce n'est pas un défaut de D2 mais un effet de bord PARTAGÉ par tous les
  //  chemins d'écriture : `_purgerVieuxPronostics()` (l.903) est appelé au
  //  début de chaque `_save()`. Une recréation déclenche donc une purge.
  //
  //  Test documentaire : il décrit le comportement RÉEL, pour qu'il soit
  //  visible dans le diagnostic et non découvert en production.
  // ═══════════════════════════════════════════════════════════════════════
  test('V6/D2-H1b — observation : une recréation déclenche la purge '
      '> 90 jours via _save()', () async {
    final vieux = DateTime.now().subtract(const Duration(days: 120));
    SharedPreferences.setMockInitialValues({
      ..._prefsVides(),
      'ia_pronostics_v2': [
        _temoin('RVIEUX_01012026', date: vieux),
        _temoin('RRECENT_01012026', date: DateTime.now()),
      ],
    });

    await IaMemoryService.instance.recharger();
    expect(IaMemoryService.instance.pronostics.length, 2);

    await IaMemoryService.instance
        .recreerPronosticsManquants([_reunion(nbCourses: 1)]);

    final cles = IaMemoryService.instance.pronostics
        .map((p) => p.courseKey)
        .toList();

    // ignore: avoid_print
    print('  [D2/H1b] après recréation : $cles');

    // Comportement attendu d'après le code actuel (purge > 90 j sans résultat)
    expect(cles.contains('RVIEUX_01012026'), isFalse,
        reason: 'observation : le pronostic de 120 jours est purgé par _save()');
    expect(cles.contains('RRECENT_01012026'), isTrue,
        reason: 'observation : le pronostic récent est conservé');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D2/H8 — Le chemin AUTO (`enregistrerPronosticsBatch`) n'a AUCUN filtre
  //  de date, contrairement à la recréation depuis l'écran IA.
  //
  //  • recreerPronosticsManquants()  filtre `'$dj$dm${dep.year}' != todayStr`
  //    → ignore les courses des autres jours.
  //  • enregistrerPronosticsBatch()  ne filtre RIEN.
  //
  //  Conséquence : un refresh automatique remplit la mémoire avec des
  //  courses d'autres jours. `_calculerManquants()` (écran IA) ne compte
  //  qu'une seule date → l'écran peut afficher « tout est en mémoire »
  //  tandis que la mémoire contient surtout des courses étrangères.
  // ═══════════════════════════════════════════════════════════════════════
  test('V6/D2/H8 — le chemin auto accepte les courses d\'autres jours, la '
      'recréation non', () async {
    // ── Chemin AUTO : batch avec une course d'HIER ───────────────────────
    //  (hier = hors « aujourd'hui » mais dans la fenêtre de 90 jours, donc
    //   aucune purge ne vient fausser la mesure)
    final hier = _dateRelative(1);
    final reunionEtrangere = _reunion(code: 'R2', nbCourses: 1, date: hier);
    final courseEtrangere = reunionEtrangere.courses.first;
    final keyEtrangere = _courseKey('2', courseEtrangere.numCourse, hier);

    final (pcE, scE) =
        IaPronosticEngine.analyserCourseAvecCriteres(courseEtrangere);
    await IaMemoryService.instance.enregistrerPronosticsBatch([
      {
        'courseKey': keyEtrangere,
        'course': courseEtrangere,
        'partantsClasses': pcE,
        'scoresCriteres': scE,
        'confiance': courseEtrangere.confianceIA,
        'typePariConseille': 'Quinté+',
      },
    ]);

    final accepteParAuto = IaMemoryService.instance.getPronostic(keyEtrangere);
    // ignore: avoid_print
    print('  [D2/H8] batch auto a accepté $keyEtrangere : '
        '${accepteParAuto != null}');

    // ── Chemin ÉCRAN : même course, jour étranger ───────────────────────
    SharedPreferences.setMockInitialValues(_prefsVides());
    await IaMemoryService.instance.recharger();
    await IaMemoryService.instance.recreerPronosticsManquants(
        [_reunion(code: 'R2', nbCourses: 1, date: hier)]);
    final refuseParEcran = IaMemoryService.instance.getPronostic(keyEtrangere);

    // ignore: avoid_print
    print('  [D2/H8] recreerPronosticsManquants a créé $keyEtrangere : '
        '${refuseParEcran != null}');

    // ── Le désalignement est le défaut : les deux doivent s'accorder ─────
    expect(accepteParAuto != null, refuseParEcran != null,
        reason: 'les deux chemins doivent appliquer la MÊME règle de date. '
            'Actuellement le batch auto accepte tout tandis que la recréation '
            'ne traite que le jour courant → la mémoire et le compteur de '
            'l\'écran IA divergent.');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D2/H9 — Scénario de production : refresh auto et ouverture de l'écran
  //  IA la même seconde.
  //
  //  Le batch auto est lancé via `Future.microtask(...)` SANS être attendu
  //  (data_refresh_service.dart:646) et `_loading` retombe à false avant
  //  qu'il ne finisse (finally l.559). Une recréation peut donc se dérouler
  //  en même temps que l'enregistrement du batch.
  //
  //  On reproduit l'ordonnancement réel et on vérifie l'état final.
  // ═══════════════════════════════════════════════════════════════════════
  test('V6/D2/H9 — batch auto et recréation simultanés : état final cohérent',
      () async {
    final reunion = _reunion(nbCourses: 3);
    final course0 = reunion.courses.first;
    final key0 = _courseKey('1', course0.numCourse);
    final (pc, sc) = IaPronosticEngine.analyserCourseAvecCriteres(course0);

    // Ordonnancement fidèle au code : microtask non attendue + recréation
    final batch = Future.microtask(() async {
      // filtre d'entrée du batch : ne traite que les courses absentes
      if (IaMemoryService.instance.getPronostic(key0) != null) return;
      await IaMemoryService.instance.enregistrerPronosticsBatch([
        {
          'courseKey': key0,
          'course': course0,
          'partantsClasses': pc,
          'scoresCriteres': sc,
          'confiance': course0.confianceIA,
          'typePariConseille': 'Quinté+',
        },
      ]);
    });

    final recre =
        IaMemoryService.instance.recreerPronosticsManquants([reunion]);

    await Future.wait([batch, recre]);

    final apres = IaMemoryService.instance.pronostics;
    final cles = apres.map((p) => p.courseKey).toList();
    final uniques = cles.toSet();

    final prefs = await SharedPreferences.getInstance();
    final disque = prefs.getStringList('ia_pronostics_v2') ?? const [];
    final clesDisque = disque
        .map((s) => (json.decode(s) as Map<String, dynamic>)['courseKey'])
        .toList();

    // ignore: avoid_print
    print('  [D2/H9] mémoire=${cles.length} (uniques=${uniques.length}) '
        '→ $cles');
    // ignore: avoid_print
    print('  [D2/H9] disque=${clesDisque.length} → $clesDisque');

    expect(cles.length, uniques.length,
        reason: 'aucun doublon malgré la concurrence');
    expect(clesDisque.toSet(), uniques,
        reason: 'le disque doit refléter la mémoire');
    expect(uniques.length, 3,
        reason: 'les 3 courses doivent être présentes, quel que soit le '
            'chemin qui a gagné la course');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D2/H2 — Deux `recreerPronosticsManquants()` concurrents
  //
  //  Le garde `_recreationEnCours` est un champ d'ÉCRAN : il ne protège que
  //  le bouton. `_autoRecreerSiVide()` (postFrameCallback) et un appui
  //  manuel, ou deux ouvertures d'écran, peuvent appeler la méthode en
  //  parallèle sans aucun verrou côté service.
  //
  //  Attendu : 2 appels simultanés == 1 appel (pas de doublon).
  // ═══════════════════════════════════════════════════════════════════════
  test('V6/D2-H2 — deux recreerPronosticsManquants() concurrents ne créent '
      'pas de doublon', () async {
    final reunions = [_reunion(nbCourses: 3)];

    // ── Référence séquentielle ───────────────────────────────────────────
    await IaMemoryService.instance.recreerPronosticsManquants(reunions);
    final nbReference = IaMemoryService.instance.pronostics.length;
    expect(nbReference, 3, reason: 'pré-requis : 3 courses à créer');

    // ── État vierge, puis deux appels réellement simultanés ──────────────
    SharedPreferences.setMockInitialValues(_prefsVides());
    await IaMemoryService.instance.recharger();
    expect(IaMemoryService.instance.pronostics, isEmpty);

    await Future.wait([
      IaMemoryService.instance.recreerPronosticsManquants(reunions),
      IaMemoryService.instance.recreerPronosticsManquants(reunions),
    ]);

    final apres = IaMemoryService.instance.pronostics;
    final cles = apres.map((p) => p.courseKey).toList();
    final uniques = cles.toSet();

    // ignore: avoid_print
    print('  [D2/H2] référence (1 appel)=$nbReference — '
        'après 2 appels concurrents=${apres.length} (uniques=${uniques.length})');

    expect(apres.length, uniques.length,
        reason: 'aucune courseKey ne doit apparaître deux fois');
    expect(apres.length, nbReference,
        reason: '2 appels concurrents ne doivent pas créer plus qu\'un seul');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D2/H3 — Cohérence scoresIA ↔ scoresCriteres (post-D1)
  //
  //  D1 a supprimé le raccourci qui laissait `scoresCriteres = {}`.
  //  On vérifie que TOUS les chemins tiennent cette promesse.
  // ═══════════════════════════════════════════════════════════════════════
  test('V6/D2-H3 — scoresIA et scoresCriteres restent alignés', () async {
    await IaMemoryService.instance
        .recreerPronosticsManquants([_reunion(nbCourses: 4)]);

    final pronostics = IaMemoryService.instance.pronostics;
    expect(pronostics.length, 4);

    for (final p in pronostics) {
      // ignore: avoid_print
      print('  [D2/H3] ${p.courseKey} : scoresIA=${p.scoresIA.length}, '
          'scoresCriteres=${p.scoresCriteres.length}');

      expect(p.scoresCriteres.isNotEmpty, isTrue,
          reason: '${p.courseKey} : scoresCriteres vide malgré D1');
      expect(p.scoresCriteres.length, p.scoresIA.length,
          reason: '${p.courseKey} : un ScoresCriteres par partant scoré');
      expect(p.scoresCriteres.keys.toSet(), p.scoresIA.keys.toSet(),
          reason: '${p.courseKey} : numéros identiques des deux côtés');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D2/H4 — Le filtre de date diffère entre les deux chemins
  //
  //  • recreerPronosticsManquants() : filtre sur DateTime.now()   (l.4408)
  //  • _enregistrerPronosticsBatchIsolate() : AUCUN filtre de date (l.658)
  //  • _calculerManquants() : filtre sur _dateAnalyse (modifiable par l'UI)
  //
  //  Attendu : recreerPronosticsManquants ne travaille que sur aujourd'hui.
  // ═══════════════════════════════════════════════════════════════════════
  test('V6/D2-H4 — recreerPronosticsManquants() ne crée que le jour en cours',
      () async {
    final aujourdhui = _reunion(code: 'R1', nbCourses: 2);
    final autreJour = _reunion(code: 'R2', nbCourses: 2, date: '01012026');

    await IaMemoryService.instance
        .recreerPronosticsManquants([aujourdhui, autreJour]);

    final cles = IaMemoryService.instance.pronostics
        .map((p) => p.courseKey)
        .toList();

    // ignore: avoid_print
    print('  [D2/H4] clés créées : $cles');

    expect(cles.where((k) => k.endsWith('01012026')), isEmpty,
        reason: 'les courses du 01/01/2026 ne doivent pas être créées ici');
    expect(cles.length, 2,
        reason: 'seules les 2 courses du jour doivent être créées');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D2/H5 — Cohérence mémoire ↔ disque après recréation + batch
  // ═══════════════════════════════════════════════════════════════════════
  test('V6/D2-H5 — mémoire et disque restent cohérents après recréation puis '
      'enregistrement batch', () async {
    final reunions = [_reunion(nbCourses: 2)];
    await IaMemoryService.instance.recreerPronosticsManquants(reunions);
    expect(IaMemoryService.instance.pronostics.length, 2);

    // Le batch est reconstruit pour une course DÉJÀ présente
    final course = reunions.first.courses.first;
    final key = _courseKey('1', course.numCourse);
    final (partantsClasses, scoresCriteres) =
        IaPronosticEngine.analyserCourseAvecCriteres(course);

    await IaMemoryService.instance.enregistrerPronosticsBatch([
      {
        'courseKey': key,
        'course': course,
        'partantsClasses': partantsClasses,
        'scoresCriteres': scoresCriteres,
        'confiance': course.confianceIA,
        'typePariConseille': 'Quinté+',
      },
    ]);

    final memoire = IaMemoryService.instance.pronostics;
    final prefs = await SharedPreferences.getInstance();
    final disque = prefs.getStringList('ia_pronostics_v2') ?? const [];

    final clesMemoire = memoire.map((p) => p.courseKey).toList();
    final clesDisque = disque
        .map((s) => (json.decode(s) as Map<String, dynamic>)['courseKey'])
        .toList();

    // ignore: avoid_print
    print('  [D2/H5] mémoire=$clesMemoire');
    // ignore: avoid_print
    print('  [D2/H5] disque=$clesDisque');

    expect(clesMemoire.toSet().length, clesMemoire.length,
        reason: 'aucun doublon en mémoire');
    expect(clesDisque.toSet(), clesMemoire.toSet(),
        reason: 'le disque doit refléter exactement la mémoire');
    expect(memoire.length, 2,
        reason: 'l\'anti-doublon de enregistrerPronosticsBatch doit empêcher '
            'la recréation d\'une course déjà présente');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D2/H6 — Un pronostic existant n'est jamais écrasé par une recréation
  // ═══════════════════════════════════════════════════════════════════════
  test('V6/D2-H6 — une recréation n\'écrase pas un pronostic existant',
      () async {
    final reunions = [_reunion(nbCourses: 1)];
    final course = reunions.first.courses.first;
    final key = _courseKey('1', course.numCourse);

    await IaMemoryService.instance.recreerPronosticsManquants(reunions);
    final original = IaMemoryService.instance.getPronostic(key);
    expect(original, isNotNull);

    final fige = json.encode(original!.toJson());
    final favoriAvant = original.favoriIaNom;
    final scoresAvant = json.encode(original.scoresIA);

    final nb2 =
        await IaMemoryService.instance.recreerPronosticsManquants(reunions);
    final apres = IaMemoryService.instance.getPronostic(key)!;

    // ignore: avoid_print
    print('  [D2/H6] 2e passage : nbCrees=$nb2 — inchangé : '
        '${json.encode(apres.toJson()) == fige}');

    expect(nb2, 0, reason: 'aucun pronostic ne doit être recréé');
    expect(json.encode(apres.toJson()), fige,
        reason: 'le pronostic existant doit rester identique (aucun écrasement)');
    expect(apres.favoriIaNom, favoriAvant);
    expect(json.encode(apres.scoresIA), scoresAvant);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D2/H7 — Persistance après redémarrage
  // ═══════════════════════════════════════════════════════════════════════
  test('V6/D2-H7 — les pronostics recréés survivent à un redémarrage',
      () async {
    await IaMemoryService.instance
        .recreerPronosticsManquants([_reunion(nbCourses: 2)]);

    final avant = IaMemoryService.instance.pronostics;
    expect(avant.length, 2);
    final attendu = avant.map((p) => json.encode(p.toJson())).toList();

    // Redémarrage : RAM vidée, disque conservé
    await IaMemoryService.instance.recharger();

    final apres = IaMemoryService.instance.pronostics;
    final obtenu = apres.map((p) => json.encode(p.toJson())).toList();

    // ignore: avoid_print
    print('  [D2/H7] avant=${avant.length} après=${apres.length} '
        'identiques=${json.encode(obtenu) == json.encode(attendu)}');

    expect(apres.length, 2);
    expect(json.encode(obtenu), json.encode(attendu),
        reason: 'rechargement à l\'identique, 19 critères compris');
    for (final p in apres) {
      expect(p.scoresCriteres.isNotEmpty, isTrue,
          reason: '${p.courseKey} : les critères doivent survivre au restart');
    }
  });
}
