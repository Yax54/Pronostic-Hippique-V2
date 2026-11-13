// ═══════════════════════════════════════════════════════════════════════════
//  V4 — D1 : « Recréer les pronostics » enregistre-t-il des critères ?
//
//  ⚠️  FICHIER DE TEST uniquement. Aucune modification de lib/.
//
//  Objet : vérifier AVANT toute modification de production que
//  recreerPronosticsManquants() produit des pronostics exploitables par
//  l'apprentissage, et que l'opération est sûre.
//
//  Les 5 exigences de l'utilisateur :
//    1. Confirmer le défaut ................ V4/T1, V4/T2
//    2. Ne toucher que les manquants ....... V4/T4, V4/T5
//    3. Classement recréé ≠ classement affiché (poids/ELO/données) ... V4/T6
//    4. Scores et critères du MÊME calcul .. V4/T3
//    5. Recréation auto / batch : pas d'écrasement mutuel ........... V4/T7
//
//  Ces tests décrivent le comportement ATTENDU (correct).
//  Sur le code actuel, ils doivent ÉCHOUER (le défaut est prouvé).
// ───────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io'; // GZipCodec — même import que ia_memory_service.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Outils
// ───────────────────────────────────────────────────────────────────────────

/// Clé ELO réelle, reconstruite exactement comme EloService._cle()
String _cleElo(String nom, String discipline) {
  final nomNorm = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  return '$nomNorm|${EloService.normaliserDiscipline(discipline)}';
}

/// Date du jour au format ddmmyyyy — format attendu par
/// recreerPronosticsManquants() pour accepter une course.
String _dateDuJour() {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}${n.year}';
}

/// courseKey tel que calculé par recreerPronosticsManquants() (l.4403)
String _courseKey(int numR, int numCourse) => 'R${numR}C${numCourse}_${_dateDuJour()}';

ZtPartant _partant({
  required String numero,
  required String nom,
  required String musique,
  required String cote,
  required String gains,
  required String record,
  int joursRepos = 21,
  String statsJockeyCsv = '',
  String statsHippodromeCsv = '',
  String statsEntraineurCsv = '',
  String statsTerrainCsv = '',
  String ageSexe = 'H5',
  int gainsDernierAn = 0,
  int placeDepartInt = 0,
  double poids = 0.0,
  double scoreIA = 0.0,
}) {
  return ZtPartant(
    numero: numero,
    nom: nom,
    driver: 'DRIVER $nom',
    entraineur: 'ENT $nom',
    proprietaire: 'PROP $nom',
    gains: gains,
    record: record,
    musique: musique,
    cote: cote,
    ageSexe: ageSexe,
    joursRepos: joursRepos,
    statsJockeyCsv: statsJockeyCsv,
    statsHippodromeCsv: statsHippodromeCsv,
    statsEntraineurCsv: statsEntraineurCsv,
    statsTerrainCsv: statsTerrainCsv,
    gainsDernierAn: gainsDernierAn,
    placeDepartInt: placeDepartInt,
    poids: poids,
    scoreIA: scoreIA,
  );
}

/// Champ de 6 chevaux volontairement très hétérogènes :
/// ALPHA domine tout, FOXTROT est dernier partout.
/// Ainsi le recalcul produit un classement net, facile à vérifier.
List<ZtPartant> _champ(bool avecScoresStales) {
  // Les scoreIA « stales » simulent ce qui a été affiché avant :
  // ordre INVERSÉ du classement réel (FOXTROT 1er, ALPHA dernier).
  const stale = {
    'ALPHA':   44.0,
    'BRAVO':   55.0,
    'CHARLIE': 66.0,
    'DELTA':   77.0,
    'ECHO':    88.0,
    'FOXTROT': 99.0,
  };

  ZtPartant mk(
    String num,
    String nom,
    String musique,
    String cote,
    String gains,
    String record, {
    required int repos,
    required String jockey,
    required String hippo,
    required String entr,
    required String terrain,
    required String age,
    required int gainsAn,
    required int place,
  }) =>
      _partant(
        numero: num,
        nom: nom,
        musique: musique,
        cote: cote,
        gains: gains,
        record: record,
        joursRepos: repos,
        statsJockeyCsv: jockey,
        statsHippodromeCsv: hippo,
        statsEntraineurCsv: entr,
        statsTerrainCsv: terrain,
        ageSexe: age,
        gainsDernierAn: gainsAn,
        placeDepartInt: place,
        scoreIA: avecScoresStales ? (stale[nom] ?? 0.0) : 0.0,
      );

  return [
    mk('1', 'ALPHA',   '1a1a1a1a1a',   '2.1',  '150000', '1\'12"4',
        repos: 21, jockey: 'J1|20|45', hippo: '10|4|7',
        entr: 'E1|20|45|35|25|5', terrain: 'bon|8|4|6',
        age: 'H5', gainsAn: 80000, place: 2),
    mk('2', 'BRAVO',   '2a3a4a2a5a',   '4.5',  '90000',  '1\'13"2',
        repos: 14, jockey: 'J2|14|35', hippo: '8|2|4',
        entr: 'E2|14|38|28|12|4', terrain: 'bon|6|2|4',
        age: 'H6', gainsAn: 40000, place: 4),
    mk('3', 'CHARLIE', '5a6a7a8a9a',   '8.0',  '60000',  '1\'14"0',
        repos: 35, jockey: 'J3|9|28', hippo: '6|1|2',
        entr: 'E3|9|30|20|8|3', terrain: 'bon|5|1|2',
        age: 'H7', gainsAn: 20000, place: 6),
    mk('4', 'DELTA',   '6a7a8a9a1a',   '12.0', '30000',  '1\'15"5',
        repos: 7, jockey: 'J4|7|20', hippo: '4|0|1',
        entr: 'E4|7|22|15|5|2', terrain: 'bon|3|0|1',
        age: 'M4', gainsAn: 12000, place: 8),
    mk('5', 'ECHO',    '1a5a3a7a2a',   '15.0', '18000',  '1\'16"1',
        repos: 90, jockey: 'J5|5|15', hippo: '3|0|0',
        entr: 'E5|5|18|10|0|1', terrain: 'bon|2|0|0',
        age: 'H9', gainsAn: 5000, place: 10),
    mk('6', 'FOXTROT', '4a8a6a9a5a',   '25.0', '10000',  '1\'17"0',
        repos: 50, jockey: 'J6|3|10', hippo: '2|0|0',
        entr: 'E6|3|12|8|0|1', terrain: 'bon|1|0|0',
        age: 'H8', gainsAn: 3000, place: 12),
  ];
}

ZtCourse _course({required bool avecScoresStales, int numCourse = 1}) {
  return ZtCourse(
    numCourse: numCourse,
    anchor: '${numCourse}15',
    nom: 'PRIX DE TEST V4',
    heure: '14:30',
    distance: '2850m',
    prix: '50000',
    type: 'Trot Attelé',
    piste: 'bon',
    categorie: 'Course D',
    isQuinte: false,
    pronosticZt: const [1, 2, 3, 4, 5],
    partants: _champ(avecScoresStales),
    dateStr: _dateDuJour(),
  );
}

ZtReunion _reunion({required bool avecScoresStales, int numR = 1}) {
  return ZtReunion(
    code: 'R$numR',
    lieu: 'Vincennes',
    discipline: 'Trot',
    dateStr: _dateDuJour(),
    courses: [_course(avecScoresStales: avecScoresStales)],
  );
}

/// ELO très différenciés : ALPHA 1900 → FOXTROT 1200
Future<void> _installerElo() async {
  const disc = 'Trot Attelé';
  const ratings = {
    'ALPHA': 1900.0,
    'BRAVO': 1700.0,
    'CHARLIE': 1550.0,
    'DELTA': 1450.0,
    'ECHO': 1300.0,
    'FOXTROT': 1200.0,
  };
  await EloService.instance.importerDepuisBackup({
    for (final e in ratings.entries)
      _cleElo(e.key, disc):
          EloScore(nomCheval: e.key, rating: e.value, nbCourses: 10).toJson(),
  });
}

/// Ordre des numéros triés par score décroissant
List<String> _ordre(Map<String, double> scores) {
  final e = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return e.map((x) => x.key).toList();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Remise à zéro complète du singleton (pronostics + poids + seuils)
    await IaMemoryService.instance.recharger();
    await _installerElo();
  });

  // ══════════════════════════════════════════════════════════════════════
  //  EXIGENCE 1 — CONFIRMER LE DÉFAUT
  // ══════════════════════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────────────────────
  // V4/T1 — LE DÉFAUT
  //
  // Course dont les scoreIA sont déjà renseignés (≥ 3 partants à score > 0),
  // c'est-à-dire exactement la situation réelle quand l'utilisateur clique
  // sur « Recréer les pronostics » après avoir consulté les courses.
  //
  // Aujourd'hui : le raccourci « Cas 1 » trie les partants et laisse
  // scoresCriteres = {} → pronostic inexploitable par _apprendreParGradient()
  // (l.2201 : .where((p) => p.scoresCriteres.isNotEmpty)).
  // ─────────────────────────────────────────────────────────────────────
  test('V4/T1 — un pronostic recréé contient des critères non vides', () async {
    final svc = IaMemoryService.instance;
    final reunion = _reunion(avecScoresStales: true);

    final nb = await svc.recreerPronosticsManquants([reunion]);
    expect(nb, 1, reason: 'Un pronostic doit être créé');

    final p = svc.getPronostic(_courseKey(1, 1));
    expect(p, isNotNull);

    expect(
      p!.scoresCriteres,
      isNotEmpty,
      reason: 'DÉFAUT D1 : les critères enregistrés sont vides → '
          'ce pronostic ne sera JAMAIS exploité par l\'apprentissage',
    );
  });

  // ─────────────────────────────────────────────────────────────────────
  // V4/T2 — Le défaut en détail : 19 critères + ELO réel (pas 37.5 figé)
  // ─────────────────────────────────────────────────────────────────────
  test('V4/T2 — les 19 critères sont présents, avec un ELO réel', () async {
    final svc = IaMemoryService.instance;
    await svc.recreerPronosticsManquants([_reunion(avecScoresStales: true)]);

    final p = svc.getPronostic(_courseKey(1, 1))!;
    expect(p.scoresCriteres.length, 6,
        reason: 'Six partants → six jeux de critères');

    const dixNeuf = [
      'forme', 'gains', 'record', 'cote', 'constance', 'victoires',
      'discipline', 'distSpec', 'jockey', 'repos', 'hippo', 'entraineur',
      'elo', 'terrain', 'divergence', 'poidsRel', 'progression',
      'mouvCote', 'placeDepart',
    ];
    expect(dixNeuf.length, 19);

    final sc1 = p.scoresCriteres['1']!;
    for (final c in dixNeuf) {
      final v = sc1.valeurPourCritere(c);
      expect(v >= 0.0 && v <= 100.0, isTrue,
          reason: 'Critère "$c" hors bornes : $v');
    }

    // ELO : doit refléter les ratings installés, pas la constante 37.5
    final eloAlpha = p.scoresCriteres['1']!.elo;
    expect(eloAlpha, closeTo(87.5, 0.01),
        reason: 'ALPHA rating 1900 → (1900-1200)/8 = 87.5');

    final elos = p.scoresCriteres.values.map((s) => s.elo).toSet();
    expect(elos.length, greaterThan(1),
        reason: 'DÉFAUT D3/D1 : ELO identique pour tous = critère M mort');

    expect(p.scoresCriteres['6']!.elo, closeTo(0.0, 0.01),
        reason: 'FOXTROT rating 1200 → 0.0');
  });

  // ══════════════════════════════════════════════════════════════════════
  //  EXIGENCE 4 — SCORES ET CRITÈRES ISSUS DU MÊME CALCUL
  // ══════════════════════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────────────────────
  // V4/T3 — Les clés de scoresIA et de scoresCriteres sont identiques,
  // et les deux proviennent d'un seul et même appel au moteur.
  // On vérifie par reproductibilité : le pronostic enregistré doit être
  // strictement égal à un appel frais analyserCourseAvecCriteres().
  // ─────────────────────────────────────────────────────────────────────
  test('V4/T3 — scores et critères proviennent du même calcul', () async {
    final svc = IaMemoryService.instance;
    final course = _course(avecScoresStales: true);

    await svc.recreerPronosticsManquants([
      ZtReunion(
        code: 'R1', lieu: 'Vincennes', discipline: 'Trot',
        dateStr: _dateDuJour(), courses: [course],
      ),
    ]);

    final p = svc.getPronostic(_courseKey(1, 1))!;

    // (a) mêmes chevaux des deux côtés
    expect(
      p.scoresCriteres.keys.toSet(),
      equals(p.scoresIA.keys.toSet()),
      reason: 'Chaque score enregistré doit avoir ses critères, et réciproquement',
    );
    expect(p.scoresIA.length, 6);

    // (b) référence : le même moteur, les mêmes poids, la même course
    final (partantsRef, criteresRef) =
        IaPronosticEngine.analyserCourseAvecCriteres(
      _course(avecScoresStales: true),
      poidsOverride: svc.poids,
    );

    // (c) scores identiques à la référence
    final scoresRef = {for (final pp in partantsRef) pp.numero: pp.scoreIA};
    expect(p.scoresIA.length, scoresRef.length);
    for (final num in scoresRef.keys) {
      expect(p.scoresIA[num], closeTo(scoresRef[num]!, 1e-9),
          reason: 'Score du cheval $num différent du calcul de référence');
    }

    // (d) critères identiques à la référence (même passe)
    for (final num in criteresRef.keys) {
      final enr = p.scoresCriteres[num]!;
      final ref = criteresRef[num]!;
      expect(enr.forme, closeTo(ref.forme, 1e-9));
      expect(enr.elo, closeTo(ref.elo, 1e-9));
      expect(enr.mouvCote, closeTo(ref.mouvCote, 1e-9));
      expect(enr.placeDepart, closeTo(ref.placeDepart, 1e-9));
    }
  });

  // ══════════════════════════════════════════════════════════════════════
  //  EXIGENCE 2 — SEULS LES MANQUANTS SONT TRAITÉS
  // ══════════════════════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────────────────────
  // V4/T4 — Idempotence : deux appels successifs → un seul pronostic
  // ─────────────────────────────────────────────────────────────────────
  test('V4/T4 — deux recréations successives ne créent qu\'un pronostic',
      () async {
    final svc = IaMemoryService.instance;
    final reunion = _reunion(avecScoresStales: true);

    final nb1 = await svc.recreerPronosticsManquants([reunion]);
    final nb2 = await svc.recreerPronosticsManquants([reunion]);

    expect(nb1, 1, reason: 'Premier appel : 1 création');
    expect(nb2, 0, reason: 'Second appel : la course existe déjà → 0 création');

    final occurrences = svc.pronostics
        .where((p) => p.courseKey == _courseKey(1, 1))
        .length;
    expect(occurrences, 1, reason: 'Aucun doublon en mémoire');
  });

  // ─────────────────────────────────────────────────────────────────────
  // V4/T5 — Un pronostic DÉJÀ en mémoire n'est jamais modifié.
  // La vérification porte sur le CONTENU, pas seulement sur le nombre.
  // C'est le garde-fou l.4406 : if (_pronostics.any(...)) continue;
  // ─────────────────────────────────────────────────────────────────────
  test('V4/T5 — un pronostic déjà enregistré est laissé intact', () async {
    final svc = IaMemoryService.instance;
    final key = _courseKey(1, 1);

    // 1) On enregistre un pronostic « historique » repérable
    final course = _course(avecScoresStales: false);
    final (partants, criteres) =
        IaPronosticEngine.analyserCourseAvecCriteres(course,
            poidsOverride: svc.poids);
    await svc.enregistrerPronostic(
      courseKey: key,
      course: course,
      partantsClasses: partants,
      scoresCriteresMap: criteres,
      confiancePredite: 78.0,
      typePariConseille: 'Quinté+', // marqueur
    );

    final avant = svc.getPronostic(key)!;
    final scoresAvant = Map<String, double>.from(avant.scoresIA);
    final criteresAvant = Map<String, ScoresCriteres>.from(avant.scoresCriteres);
    final typeAvant = avant.typePariConseille;

    // 2) On tente une recréation sur la MÊME course
    final nb = await svc.recreerPronosticsManquants([_reunion(avecScoresStales: true)]);
    expect(nb, 0, reason: 'Pronostic existant → rien à créer');

    // 3) Le contenu doit être strictement inchangé
    final apres = svc.getPronostic(key)!;
    expect(apres.typePariConseille, typeAvant,
        reason: 'Le marqueur ne doit pas avoir été réécrit');
    expect(apres.scoresIA.length, scoresAvant.length);
    for (final num in scoresAvant.keys) {
      expect(apres.scoresIA[num], closeTo(scoresAvant[num]!, 1e-12),
          reason: 'Score du cheval $num modifié par une recréation');
    }
    expect(apres.scoresCriteres.length, criteresAvant.length);
    for (final num in criteresAvant.keys) {
      expect(apres.scoresCriteres[num]!.elo,
          closeTo(criteresAvant[num]!.elo, 1e-12),
          reason: 'Critères du cheval $num modifiés');
    }

    // 4) Toujours un seul pronostic pour cette course
    expect(svc.pronostics.where((p) => p.courseKey == key).length, 1);
  });

  // ─────────────────────────────────────────────────────────────────────
  // V4/T8 — Isolation : sur 3 courses, seule la manquante est créée ;
  // les deux déjà enregistrées gardent leur contenu au bit près.
  // ─────────────────────────────────────────────────────────────────────
  test('V4/T8 — seule la course manquante est traitée, les autres intactes',
      () async {
    final svc = IaMemoryService.instance;

    // Trois courses dans la même réunion
    final reunion = ZtReunion(
      code: 'R1',
      lieu: 'Vincennes',
      discipline: 'Trot',
      dateStr: _dateDuJour(),
      courses: [
        _course(avecScoresStales: false, numCourse: 1),
        _course(avecScoresStales: false, numCourse: 2),
        _course(avecScoresStales: false, numCourse: 3),
      ],
    );

    // On enregistre C1 et C3 avec un marqueur distinctif
    for (final nc in [1, 3]) {
      final c = _course(avecScoresStales: false, numCourse: nc);
      final (partants, criteres) =
          IaPronosticEngine.analyserCourseAvecCriteres(c, poidsOverride: svc.poids);
      await svc.enregistrerPronostic(
        courseKey: _courseKey(1, nc),
        course: c,
        partantsClasses: partants,
        scoresCriteresMap: criteres,
        confiancePredite: 60.0 + nc,
        typePariConseille: 'Marqueur$nc',
      );
    }

    final c1Avant = svc.getPronostic(_courseKey(1, 1))!;
    final c3Avant = svc.getPronostic(_courseKey(1, 3))!;

    // Recréation : seule C2 doit être créée
    final nb = await svc.recreerPronosticsManquants([reunion]);
    expect(nb, 1, reason: 'Une seule course manquante → une seule création');

    // Les deux existantes sont intactes
    final c1Apres = svc.getPronostic(_courseKey(1, 1))!;
    final c3Apres = svc.getPronostic(_courseKey(1, 3))!;
    expect(c1Apres.typePariConseille, 'Marqueur1');
    expect(c3Apres.typePariConseille, 'Marqueur3');
    expect(c1Apres.confiancePredite, closeTo(c1Avant.confiancePredite!, 1e-12));
    expect(c3Apres.confiancePredite, closeTo(c3Avant.confiancePredite!, 1e-12));

    // C2 créée
    expect(svc.getPronostic(_courseKey(1, 2)), isNotNull);
    expect(svc.pronostics.where((p) => p.courseKey.startsWith('R1C')).length, 3);
  });

  // ══════════════════════════════════════════════════════════════════════
  //  EXIGENCE 3 — LE CLASSEMENT PEUT CHANGER
  //
  //  Nuance imposée : D1 n'est PAS une « récupération des critères
  //  d'origine ». C'est un RECALCUL. Si les ELO / poids / données ont
  //  évolué depuis l'affichage, l'ordre recréé peut différer de l'ordre
  //  affiché. Ce test le prouve et l'assume.
  // ══════════════════════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────────────────────
  // V4/T6 — Le pronostic recréé reflète le calcul ACTUEL, pas l'ordre
  // périmé des scoreIA encore présents sur les partants.
  // ─────────────────────────────────────────────────────────────────────
  test('V4/T6 — le classement recréé reflète les ELO actuels, pas l\'affiché',
      () async {
    final svc = IaMemoryService.instance;

    // Ordre « affiché » (stale) présent sur les partants : FOXTROT 1er
    final stale = <String, double>{
      for (final p in _champ(true)) p.numero: p.scoreIA,
    };
    final ordreAffiche = _ordre(stale);
    expect(ordreAffiche.first, '6', reason: 'Référence : FOXTROT affiché 1er');

    // Recalcul de référence avec les ELO ACTUELS
    final (partantsRef, _) = IaPronosticEngine.analyserCourseAvecCriteres(
        _course(avecScoresStales: false), poidsOverride: svc.poids);
    final ordreActuel =
        partantsRef.map((p) => p.numero).toList(); // déjà trié par le moteur

    // Prémisse : les deux ordres DIFFÈRENT bien (sinon le test ne prouve rien)
    expect(ordreActuel, isNot(equals(ordreAffiche)),
        reason: 'Prémisse : le classement recalculé diffère de l\'affiché');
    expect(ordreActuel.first, '1',
        reason: 'ALPHA (ELO 1900) doit dominer après recalcul');

    // La recréation doit produire l'ordre ACTUEL
    await svc.recreerPronosticsManquants([_reunion(avecScoresStales: true)]);
    final recree = svc.getPronostic(_courseKey(1, 1))!;

    expect(
      _ordre(recree.scoresIA),
      equals(ordreActuel),
      reason: 'D1 : le pronostic recréé doit refléter le calcul actuel. '
          'Aujourd\'hui il conserve l\'ordre périmé ($ordreAffiche) '
          '→ classement recréé ≠ classement affiché, sans critères.',
    );
    expect(recree.scoresCriteres['1']!.elo, closeTo(87.5, 0.01));
  });

  // ══════════════════════════════════════════════════════════════════════
  //  EXIGENCE 5 — RECRÉATION AUTO  vs  ENREGISTREMENT BATCH
  //
  //  Les deux chemins écrivent dans _pronostics. Ils doivent être
  //  mutuellement non destructifs : le garde-fou est identique
  //  (anti-doublon sur courseKey) de part et d'autre :
  //    - recreerPronosticsManquants        l.4406
  //    - enregistrerPronosticsBatch         l.1787
  //    - _enregistrerPronosticsBatchIsolate l.666 (filtre en amont)
  // ══════════════════════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────────────────────
  // V4/T7a — Batch d'abord, puis recréation : la recréation n'écrase rien
  // ─────────────────────────────────────────────────────────────────────
  test('V4/T7a — batch puis recréation : le batch n\'est pas écrasé', () async {
    final svc = IaMemoryService.instance;
    final key = _courseKey(1, 1);
    final course = _course(avecScoresStales: false);

    // Le batch enregistre avec un marqueur
    final (partants, criteres) =
        IaPronosticEngine.analyserCourseAvecCriteres(course,
            poidsOverride: svc.poids);
    await svc.enregistrerPronosticsBatch([
      {
        'courseKey': key,
        'course': course,
        'partantsClasses': partants,
        'scoresCriteres': criteres,
        'confiance': 71.0,
        'typePariConseille': 'Tiercé', // marqueur batch
      },
    ]);

    expect(svc.getPronostic(key), isNotNull);
    final avant = svc.getPronostic(key)!;
    expect(avant.typePariConseille, 'Tiercé');

    // La recréation passe derrière : elle doit s'abstenir
    final nb = await svc.recreerPronosticsManquants([_reunion(avecScoresStales: true)]);
    expect(nb, 0, reason: 'La course existe déjà → la recréation ne crée rien');

    final apres = svc.getPronostic(key)!;
    expect(apres.typePariConseille, 'Tiercé',
        reason: 'Le marqueur du batch doit survivre');
    expect(svc.pronostics.where((p) => p.courseKey == key).length, 1,
        reason: 'Pas de doublon');
  });

  // ─────────────────────────────────────────────────────────────────────
  // V4/T7b — Recréation d'abord, puis batch : le batch n'écrase rien
  // ─────────────────────────────────────────────────────────────────────
  test('V4/T7b — recréation puis batch : la recréation n\'est pas écrasée',
      () async {
    final svc = IaMemoryService.instance;
    final key = _courseKey(1, 1);

    final nb = await svc.recreerPronosticsManquants([_reunion(avecScoresStales: true)]);
    expect(nb, 1);
    final avant = svc.getPronostic(key)!;
    final scoresAvant = Map<String, double>.from(avant.scoresIA);
    final criteresAvant =
        Map<String, ScoresCriteres>.from(avant.scoresCriteres);

    // Le batch arrive derrière avec des valeurs différentes
    final course = _course(avecScoresStales: false);
    final (partants, criteres) =
        IaPronosticEngine.analyserCourseAvecCriteres(course,
            poidsOverride: svc.poids);
    await svc.enregistrerPronosticsBatch([
      {
        'courseKey': key,
        'course': course,
        'partantsClasses': partants,
        'scoresCriteres': criteres,
        'confiance': 71.0,
        'typePariConseille': 'Tiercé', // marqueur batch
      },
    ]);

    final apres = svc.getPronostic(key)!;
    expect(apres.typePariConseille, isNot('Tiercé'),
        reason: 'Le batch doit être ignoré : la course existe déjà');
    expect(apres.scoresIA.length, scoresAvant.length);
    for (final num in scoresAvant.keys) {
      expect(apres.scoresIA[num], closeTo(scoresAvant[num]!, 1e-12),
          reason: 'Score $num écrasé par le batch');
    }
    expect(apres.scoresCriteres.length, criteresAvant.length);
    expect(svc.pronostics.where((p) => p.courseKey == key).length, 1,
        reason: 'Pas de doublon');
  });

  // ─────────────────────────────────────────────────────────────────────
  // V4/T7c — Concurrence réelle : recréation et batch lancés ensemble.
  // On vérifie qu'il en résulte UN pronostic cohérent : ses clés de scores
  // et de critères concordent (signature d'un calcul atomique), et il n'y
  // a aucun doublon. Lequel des deux gagne est sans importance ici ;
  // ce qui compte est l'absence d'écrasement partiel / d'état hybride.
  // ─────────────────────────────────────────────────────────────────────
  test('V4/T7c — recréation et batch simultanés : état final cohérent',
      () async {
    final svc = IaMemoryService.instance;
    final key = _courseKey(1, 1);
    final course = _course(avecScoresStales: false);
    final (partants, criteres) =
        IaPronosticEngine.analyserCourseAvecCriteres(course,
            poidsOverride: svc.poids);

    await Future.wait([
      svc.recreerPronosticsManquants([_reunion(avecScoresStales: true)]),
      svc.enregistrerPronosticsBatch([
        {
          'courseKey': key,
          'course': course,
          'partantsClasses': partants,
          'scoresCriteres': criteres,
          'confiance': 71.0,
          'typePariConseille': 'Tiercé',
        },
      ]),
    ]);

    final occurrences =
        svc.pronostics.where((p) => p.courseKey == key).toList();
    expect(occurrences.length, 1,
        reason: 'Un seul pronostic malgré deux écrivains concurrents');

    final final_ = occurrences.first;
    // Cohérence : aucun état hybride (scores d'un calcul, critères de l'autre)
    expect(final_.scoresCriteres.keys.toSet(), equals(final_.scoresIA.keys.toSet()),
        reason: 'Scores et critères doivent être du même calcul');
    if (final_.scoresCriteres.isNotEmpty) {
      final (pRef, cRef) = IaPronosticEngine.analyserCourseAvecCriteres(
          _course(avecScoresStales: false), poidsOverride: svc.poids);
      final scoresRef = {for (final x in pRef) x.numero: x.scoreIA};
      for (final num in scoresRef.keys) {
        expect(final_.scoresIA[num], closeTo(scoresRef[num]!, 1e-9),
            reason: 'Score $num incohérent avec les critères enregistrés');
        expect(final_.scoresCriteres[num]!.elo,
            closeTo(cRef[num]!.elo, 1e-9),
            reason: 'ELO $num incohérent');
      }
    }
  });

  // ══════════════════════════════════════════════════════════════════════
  //  EXIGENCE 6 — LA RECRÉATION N'APPREND RIEN
  //
  //  « Recréer les pronostics » doit uniquement calculer et enregistrer
  //  le pronostic et ses 19 critères. Aucun apprentissage, aucune
  //  modification des poids, des ELO, des seuils, aucun résultat fictif.
  // ══════════════════════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────────────────────
  // V4/T9 — Non-régression : poids, ELO, seuils et compteurs d'apprentissage
  // sont strictement identiques avant et après une recréation.
  //
  // Le seul mécanisme autorisé à changer est la LISTE des pronostics.
  // Tout écart sur les poids / ELO / seuils / journal / rapports signifie
  // qu'un chemin d'apprentissage a été déclenché par erreur.
  // ─────────────────────────────────────────────────────────────────────
  test('V4/T9 — la recréation ne déclenche aucun apprentissage', () async {
    final svc = IaMemoryService.instance;

    // ── Instantané AVANT ────────────────────────────────────────────────
    final poidsAvant     = jsonEncode(svc.poids.toJson());
    final eloAvant       = jsonEncode(EloService.instance.exporterPourBackup());
    final seuilsAvant    = jsonEncode(svc.seuilsConfiance.toJson());
    final journalAvant   = svc.journal.length;
    final rapportsAvant  = svc.rapports.length;
    final precisionAvant = svc.precisionParType.length;
    final bilansAvant    = svc.bilansSemaine.length;
    final nbMAJAvant     = svc.poids.nbMisesAJour;
    final calibAvant     = svc.poids.calibrationScore;
    final gradAvant      = jsonEncode(svc.poids.dernierGradient);
    final corrAvant      = jsonEncode(svc.poids.correlations);

    expect(nbMAJAvant, 0, reason: 'Référence : aucun apprentissage au départ');

    // ── Recréation ──────────────────────────────────────────────────────
    final nb = await svc.recreerPronosticsManquants([
      _reunion(avecScoresStales: true),
    ]);
    expect(nb, 1, reason: 'Un pronostic doit bien être créé');

    // ── Instantané APRÈS ────────────────────────────────────────────────
    expect(jsonEncode(svc.poids.toJson()), poidsAvant,
        reason: 'Les 19 poids IA ne doivent pas bouger');
    expect(svc.poids.nbMisesAJour, nbMAJAvant,
        reason: 'Le compteur d\'apprentissage ne doit pas s\'incrémenter');
    expect(svc.poids.calibrationScore, closeTo(calibAvant, 1e-12),
        reason: 'La calibration ne doit pas être recalculée');
    expect(jsonEncode(svc.poids.dernierGradient), gradAvant,
        reason: 'Aucun gradient ne doit être calculé');
    expect(jsonEncode(svc.poids.correlations), corrAvant,
        reason: 'Aucune corrélation ne doit être recalculée');

    expect(jsonEncode(EloService.instance.exporterPourBackup()), eloAvant,
        reason: 'Les ratings ELO ne doivent pas être réécrits');
    expect(jsonEncode(svc.seuilsConfiance.toJson()), seuilsAvant,
        reason: 'Les seuils de confiance ne doivent pas être ajustés');

    expect(svc.journal.length, journalAvant,
        reason: 'Aucune entrée de journal d\'apprentissage ne doit être ajoutée');
    expect(svc.rapports.length, rapportsAvant,
        reason: 'Aucun rapport journalier ne doit être créé');
    expect(svc.precisionParType.length, precisionAvant,
        reason: 'La précision par type de pari ne doit pas être mise à jour');
    expect(svc.bilansSemaine.length, bilansAvant);

    // ── Aucun résultat fictif ───────────────────────────────────────────
    final p = svc.getPronostic(_courseKey(1, 1))!;
    expect(p.resultatsReels, isFalse,
        reason: 'Aucun résultat réel ne doit être inventé');
    expect(p.arriveeReelle, isNull,
        reason: 'Aucune arrivée ne doit être inventée');
    expect(p.dateResultat, isNull);

    // ── Le pronostic, lui, est bien renseigné ───────────────────────────
    expect(p.scoresCriteres.length, 6);
    expect(p.scoresIA.length, 6);
    expect(p.typePariConseille, isNotNull);
  });

  // ══════════════════════════════════════════════════════════════════════
  //  EXIGENCE 7 — LES CRITÈRES SURVIVENT AU REDÉMARRAGE
  // ══════════════════════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────────────────────
  // V4/T10 — Un pronostic recréé conserve ses 19 critères après
  // fermeture / redémarrage de l'application.
  //
  // Simule un redémarrage : recharger() vide la RAM puis relit
  // SharedPreferences, exactement comme au lancement de l'app.
  // Vérifie aussi le contenu réellement écrit dans SharedPreferences
  // (chemin _save : liste JSON si ≤ 20 pronostics, gzip au-delà).
  // ─────────────────────────────────────────────────────────────────────
  test('V4/T10 — les critères survivent à un redémarrage', () async {
    final svc = IaMemoryService.instance;
    final key = _courseKey(1, 1);

    await svc.recreerPronosticsManquants([_reunion(avecScoresStales: true)]);
    final avant = svc.getPronostic(key)!;
    expect(avant.scoresCriteres.length, 6);
    final eloAvant = {
      for (final e in avant.scoresCriteres.entries) e.key: e.value.elo,
    };

    // ── Écriture réellement présente dans SharedPreferences ? ───────────
    final prefs = await SharedPreferences.getInstance();
    final brute = prefs.getStringList('ia_pronostics_v2');
    final gz    = prefs.getString('ia_pronostics_v2_gz');
    expect(brute != null || gz != null, isTrue,
        reason: 'La sauvegarde doit avoir écrit les pronostics');

    // Relecture indépendante de la RAM, depuis le stockage seul
    List<dynamic> decode = const [];
    if (gz != null && gz.isNotEmpty) {
      decode = jsonDecode(utf8.decode(GZipCodec().decode(base64Decode(gz))))
          as List<dynamic>;
    } else {
      decode = (brute ?? [])
          .map((s) => jsonDecode(s) as dynamic)
          .toList();
    }
    final sur = decode
        .map((e) => IaPronostic.fromJson(e as Map<String, dynamic>))
        .firstWhere((x) => x.courseKey == key);
    expect(sur.scoresCriteres.length, 6,
        reason: 'Les critères doivent être physiquement présents sur le disque');
    expect(sur.scoresCriteres['1']!.elo, closeTo(87.5, 0.01));

    // ── Redémarrage simulé ──────────────────────────────────────────────
    await svc.recharger();

    final apres = svc.getPronostic(key);
    expect(apres, isNotNull, reason: 'Le pronostic doit être rechargé');
    expect(apres!.scoresCriteres.length, 6,
        reason: 'Les 19 critères doivent survivre au redémarrage');
    for (final num in eloAvant.keys) {
      expect(apres.scoresCriteres[num], isNotNull,
          reason: 'Critères du cheval $num perdus au redémarrage');
      expect(apres.scoresCriteres[num]!.elo, closeTo(eloAvant[num]!, 1e-9),
          reason: 'ELO du cheval $num altéré au redémarrage');
    }
    expect(apres.scoresCriteres['1']!.forme,
        closeTo(avant.scoresCriteres['1']!.forme, 1e-9));
    expect(apres.scoresCriteres.keys.toSet(),
        equals(apres.scoresIA.keys.toSet()),
        reason: 'Scores et critères doivent rester cohérents après rechargement');
  });
}
