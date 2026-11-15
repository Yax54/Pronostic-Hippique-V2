// ═══════════════════════════════════════════════════════════════════════════
//  V10 — A6-S : vérification du VÉRITABLE CHEMIN DE PRODUCTION
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT.
//
//  Contrairement à V9 (qui reproduisait l'arithmétique), ces tests appellent
//  réellement `IaMemoryService.instance.analyseJourneeComplete()`.
//  L'API PMU est interceptée par `http.runWithClient()` + `MockClient` :
//  aucun appel réseau réel n'est émis, aucun accès à turfinfo.api.pmu.fr.
//
//  Correction testée : ia_memory_service.dart l.3236
//      final _refTemporelle = DateTime.now();
//      final diffMin = heureCourse.difference(_refTemporelle).inMinutes;
//  (avant : `heureCourse.difference(now)`)
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';

// ─────────────────────────── Outils ────────────────────────────────────────

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

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

/// Course d'un jour donné à une heure précise.
ZtCourse _course(int num, DateTime quand) => ZtCourse(
      numCourse: num,
      anchor: 'R1C$num',
      nom: 'PRIX_$num',
      heure: '${quand.hour.toString().padLeft(2, '0')}:'
          '${quand.minute.toString().padLeft(2, '0')}',
      distance: '2700',
      prix: '50000',
      type: 'Trot Attelé',
      piste: 'Sable',
      categorie: 'D',
      isQuinte: true,
      pronosticZt: const [1, 2, 3, 4, 5],
      partants: List.generate(8, (j) => _p(j + 1)),
      dateStr: _fmt(quand),
    );

ZtReunion _reunion(String code, List<DateTime> departs) => ZtReunion(
      code: code,
      lieu: 'VINCENNES',
      discipline: 'Trot',
      dateStr: _fmt(departs.first),
      courses: [
        for (var i = 0; i < departs.length; i++)
          _course(i + 1, departs[i]),
      ],
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

/// Crée les pronostics par le chemin batch réel.
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

// ─────────────────────── Faux serveur PMU ──────────────────────────────────

/// Construit une réponse `rapports-definitifs` plausible.
/// `numGagnant` = cheval qui gagne. `null` → corps vide (résultat absent).
String _reponsePmu(int? numGagnant) {
  if (numGagnant == null) return '[]';
  return json.encode([
    {
      'typePari': 'E_SIMPLE_GAGNANT',
      'rapports': [
        {
          'combinaison': '$numGagnant',
          'dividendePourUnEuro': 350,
        },
      ],
    },
    {
      'typePari': 'E_SIMPLE_PLACE',
      'rapports': [
        {'combinaison': '$numGagnant'},
        {'combinaison': '${numGagnant == 1 ? 2 : 1}'},
        {'combinaison': '3'},
      ],
    },
    {
      'typePari': 'E_QUINTE_ORDRE',
      'rapports': [
        {
          'combinaison': '$numGagnant-'
              '${numGagnant == 1 ? 2 : 1}-3-4-5',
        },
      ],
    },
  ]);
}

/// Exécute `analyseJourneeComplete()` avec le réseau simulé.
///
/// `resultatDisponible` : si false, le faux PMU répond `[]` pour toutes les
/// courses → simule des résultats pas encore publiés.
Future<T> _avecPmuSimule<T>(
  Future<T> Function() action, {
  bool resultatDisponible = true,
  String? bodyForce,
  int? statusForce,
  List<Uri>? urlsVues,
}) {
  final client = MockClient((request) async {
    urlsVues?.add(request.url);
    if (statusForce != null) {
      return http.Response('', statusForce);
    }
    // Numéro de course dans l'URL pour varier le gagnant
    final m = RegExp(r'/C(\d+)/').firstMatch(request.url.path);
    final numC = m != null ? int.tryParse(m.group(1) ?? '0') ?? 0 : 0;
    final corps = bodyForce ??
        (resultatDisponible ? _reponsePmu(1 + (numC % 8)) : '[]');
    return http.Response(corps, 200,
        headers: {'content-type': 'application/json'});
  });

  return http.runWithClient(action, () => client);
}

// ─────────────────────────── Tests ─────────────────────────────────────────

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(_prefs());
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T1 (obligatoire 1) — Rattrapage d'une journée passée lancé le MATIN :
  //  les courses terminées doivent être éligibles.
  //
  //  On force le cas défavorable : journée J-2, courses à 14h15.
  //  Avec l'ancien code (`difference(now)`), si l'appui avait lieu avant
  //  14h15 ces courses étaient sautées. Ici l'appui est réel (maintenant),
  //  mais la journée est passée : les courses DOIVENT être analysées.
  // ═══════════════════════════════════════════════════════════════════════
  test('T1 — journée passée : les courses terminées sont analysées '
      '(vrai chemin de production)', () async {
    final j2 = DateTime.now().subtract(const Duration(days: 2));
    // 2 courses de J-2, départs 13h30 et 16h40
    final departs = [
      DateTime(j2.year, j2.month, j2.day, 13, 30),
      DateTime(j2.year, j2.month, j2.day, 16, 40),
    ];
    final reunion = _reunion('R1', departs);
    await _creerPronostics([reunion]);
    expect(IaMemoryService.instance.pronostics.length, 2);

    final urls = <Uri>[];
    final res = await _avecPmuSimule(
      () => IaMemoryService.instance.analyseJourneeComplete(date: j2),
      urlsVues: urls,
    );

    // ignore: avoid_print
    print('  [T1] succes=${res.succes} analysées=${res.nbCoursesAnalysees} '
        'nouveauxRésultats=${res.nbNouveauxResultats} '
        'futures=${res.nbCoursesFutures} sansRésultat=${res.nbSansResultat}');
    // ignore: avoid_print
    print('  [T1] requêtes PMU émises : ${urls.length}');
    for (final u in urls) {
      // ignore: avoid_print
      print('  [T1]   ${u.path}');
    }

    expect(res.succes, isTrue);
    expect(res.nbCoursesFutures, 0,
        reason: 'A6-S : aucune course de J-2 ne doit être vue « à venir » '
            'ou « en cours », même si l\'appui a lieu avant 14h15');
    expect(res.nbNouveauxResultats, 2,
        reason: 'les 2 courses terminées doivent être analysées');
    expect(urls.length, 2,
        reason: 'une requête PMU par course éligible');

    // L'URL doit porter la date de la COURSE, pas celle du jour
    for (final u in urls) {
      expect(u.path.contains(_fmt(j2)), isTrue,
          reason: 'l\'URL PMU doit cibler la date de la course (${_fmt(j2)})');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T2 (obligatoire 2) — Courses futures du jour : toujours exclues.
  //
  //  ★ Indépendance à l'heure d'exécution (correctif) : les deux départs sont
  //  placés à des HEURES FIXES (14h15 et 16h40) d'un jour civil GARANTI
  //  FUTUR — « demain », obtenu par arithmétique de CALENDRIER
  //  (`DateTime(y, m, d + 1)`) et non par ajout d'une durée absolue.
  //
  //  Pourquoi la version précédente (`DateTime.now()` + 3 h / + 5 h) était
  //  instable — deux contraintes de la PRODUCTION, non modifiables ici :
  //    1. `analyseJourneeComplete({date})` ne retient que les pronostics de
  //       la journée de `date` : `now = date ?? DateTime.now()` (l.3934),
  //       puis fenêtre [00h00(date) − 1 h, 00h00(date) + 24 h)
  //       (ia_memory_service.dart:3952-3953, filtre l.3967-3969).
  //    2. la classification « future » se fait sur l'HORLOGE RÉELLE
  //       (`_refTemporelle = DateTime.now()`, ia_memory_service.dart:4173),
  //       et NON sur le paramètre `date` — les deux références divergent.
  //  Entre 19h00 et 20h59 (heure locale), `now + 5 h` tombe le LENDEMAIN,
  //  donc HORS de la fenêtre (contrainte 1), tandis que `now + 3 h` y reste :
  //  la sélection ne contient qu'UNE course, `nbCoursesFutures` vaut 1 et le
  //  test échoue (`Expected: <2> / Actual: <1>`) sans aucune modification de
  //  production. Mesuré sur les 527 040 instants de 2024 (minute par minute),
  //  replis de sélection inclus (J-1…J-7, fenêtre 48 h, « tous sans
  //  résultat ») : 43 920 échecs de l'ancien montage, soit 8,33 % — les
  //  2 heures locales 19 et 20 sur 24. Hors de cette plage, l'ancien montage
  //  passait parfois PAR ACCIDENT (les deux courses hors fenêtre, donc
  //  rabattues par le repli « tous sans résultat ») : le test n'était pas
  //  seulement instable, il était non déterministe. À l'inverse, une date
  //  fixe arbitraire violerait la contrainte 2 dès que son heure serait
  //  passée.
  //
  //  Le montage retenu satisfait les deux contraintes PAR CONSTRUCTION :
  //    • tout instant du jour civil J+1 est STRICTEMENT postérieur à tout
  //      instant du jour civil J ⇒ les deux départs sont toujours futurs,
  //      quelle que soit l'heure d'exécution (contrainte 2) ;
  //    • les deux départs sont sur le MÊME jour civil J+1 et `date` porte ce
  //      même jour ⇒ ils sont dans la fenêtre analysée (contrainte 1).
  //  `DateTime(y, m, d + 1)` est une opération de CALENDRIER : le débordement
  //  de fin de mois/année est normalisé par Dart et aucun changement d'heure
  //  ne peut décaler le jour obtenu (contrairement à `add(Duration(days: 1))`,
  //  qui ajoute 24 h absolues).
  // ═══════════════════════════════════════════════════════════════════════
  test('T2 — courses futures du jour : exclues, aucune requête PMU', () async {
    final maintenant = DateTime.now();
    // Jour civil J+1, par arithmétique de calendrier.
    final jour = DateTime(
        maintenant.year, maintenant.month, maintenant.day + 1);
    final departs = [
      DateTime(jour.year, jour.month, jour.day, 14, 15),
      DateTime(jour.year, jour.month, jour.day, 16, 40),
    ];

    // ── Invariants du montage, vérifiés AVANT d'appeler la production ──
    expect(_fmt(departs[0]), _fmt(departs[1]),
        reason: 'les deux courses doivent partager le MÊME jour civil — '
            'c\'est la propriété que l\'ancien montage supposait à tort');
    for (final d in departs) {
      expect(d.isAfter(maintenant), isTrue,
          reason: 'chaque départ doit être STRICTEMENT futur par rapport à '
              'l\'horloge réelle, seule référence de la production ($d)');
    }

    final reunion = _reunion('R1', departs);
    await _creerPronostics([reunion]);
    expect(IaMemoryService.instance.pronostics.length, 2,
        reason: 'les deux pronostics doivent exister avant l\'analyse');

    final urls = <Uri>[];
    final res = await _avecPmuSimule(
      () => IaMemoryService.instance.analyseJourneeComplete(
          date: departs.first),
      urlsVues: urls,
    );

    // ignore: avoid_print
    print('  [T2] futures=${res.nbCoursesFutures} '
        'analysées=${res.nbCoursesAnalysees} '
        'sansRésultat=${res.nbSansResultat} '
        'requêtes=${urls.length}');

    expect(res.nbCoursesFutures, 2,
        reason: 'les 2 courses à venir doivent être classées futures');
    expect(res.nbCoursesAnalysees, 0,
        reason: 'aucune course ne doit être comptée comme analysée/traitée');
    expect(res.nbNouveauxResultats, 0);
    expect(res.nbSansResultat, 0,
        reason: 'aucune course ne doit être vue « passée sans résultat »');
    expect(urls, isEmpty,
        reason: 'aucune requête PMU ne doit être émise pour une course '
            'non courue — c\'est la protection que A6-S ne devait PAS casser');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T3 (obligatoire 3) — Courses terminées depuis moins de 30 min :
  //  toujours exclues (résultat PMU probablement pas publié).
  // ═══════════════════════════════════════════════════════════════════════
  test('T3 — course terminée depuis 10 min : exclue, garde-fou 30 min intact',
      () async {
    final t = DateTime.now();
    // Départ il y a 10 minutes → dans la zone -30
    final depart = t.subtract(const Duration(minutes: 10));
    final reunion = _reunion('R1', [
      DateTime(depart.year, depart.month, depart.day, depart.hour,
          depart.minute),
    ]);
    await _creerPronostics([reunion]);

    final urls = <Uri>[];
    final res = await _avecPmuSimule(
      () => IaMemoryService.instance.analyseJourneeComplete(date: t),
      urlsVues: urls,
    );

    // ignore: avoid_print
    print('  [T3] futures=${res.nbCoursesFutures} '
        'analysées=${res.nbCoursesAnalysees} requêtes=${urls.length}');

    expect(res.nbCoursesFutures, 1,
        reason: 'dans la fenêtre de 30 min → comptée comme non analysable');
    expect(urls, isEmpty,
        reason: 'le délai de 30 minutes doit rester actif après A6-S');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T4 (obligatoire 4) — Journée sans résultats disponibles :
  //  aucun apprentissage artificiel.
  //
  //  Le faux PMU répond `[]` → arrivée vide → nbSansResultat > 0 et
  //  nbNouveauxResultats == 0. Le gradient ne doit PAS être déclenché :
  //  _poids.nbMisesAJour doit rester inchangé.
  // ═══════════════════════════════════════════════════════════════════════
  test('T4 — résultats PMU indisponibles : aucun apprentissage artificiel',
      () async {
    final j1 = DateTime.now().subtract(const Duration(days: 1));
    final reunion = _reunion('R1', [
      DateTime(j1.year, j1.month, j1.day, 14, 15),
    ]);
    await _creerPronostics([reunion]);

    final misesAvant =
        IaMemoryService.instance.poids.nbMisesAJour;
    final journalAvant = IaMemoryService.instance.journal.length;

    final res = await _avecPmuSimule(
      () => IaMemoryService.instance.analyseJourneeComplete(date: j1),
      resultatDisponible: false, // PMU répond []
    );

    final misesApres =
        IaMemoryService.instance.poids.nbMisesAJour;
    final journalApres = IaMemoryService.instance.journal.length;

    // ignore: avoid_print
    print('  [T4] sansRésultat=${res.nbSansResultat} '
        'nouveaux=${res.nbNouveauxResultats} '
        'nbMisesAJour $misesAvant→$misesApres '
        'journal $journalAvant→$journalApres');

    expect(res.nbNouveauxResultats, 0);
    expect(res.nbSansResultat, 1,
        reason: 'la course est bien passée mais le résultat manque');
    expect(misesApres, misesAvant,
        reason: 'aucun apprentissage ne doit être déclenché sans nouveau '
            'résultat (garde l.3423)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T5 (obligatoire 5) — Analyse répétée : pas de doublons.
  //
  //  Deux passes successives sur la même journée. La 2e ne doit produire
  //  aucun nouveau résultat (resultatsReels déjà true) ni créer de
  //  pronostic (la méthode n'en crée jamais).
  // ═══════════════════════════════════════════════════════════════════════
  test('T5 — analyse répétée : pas de doublons ni de double comptage',
      () async {
    final j1 = DateTime.now().subtract(const Duration(days: 1));
    final reunion = _reunion('R1', [
      DateTime(j1.year, j1.month, j1.day, 14, 15),
      DateTime(j1.year, j1.month, j1.day, 15, 30),
    ]);
    await _creerPronostics([reunion]);
    final nbPronosticsAvant = IaMemoryService.instance.pronostics.length;

    final res1 = await _avecPmuSimule(
      () => IaMemoryService.instance.analyseJourneeComplete(date: j1));
    final res2 = await _avecPmuSimule(
      () => IaMemoryService.instance.analyseJourneeComplete(date: j1));

    final nbPronosticsApres = IaMemoryService.instance.pronostics.length;
    final nbResolus = IaMemoryService.instance.pronostics
        .where((p) => p.resultatsReels)
        .length;

    // ignore: avoid_print
    print('  [T5] passe1 nouveaux=${res1.nbNouveauxResultats} | '
        'passe2 nouveaux=${res2.nbNouveauxResultats}');
    // ignore: avoid_print
    print('  [T5] pronostics $nbPronosticsAvant→$nbPronosticsApres '
        '(résolus=$nbResolus sur 2)');

    expect(res1.nbNouveauxResultats, 2);
    expect(res2.nbNouveauxResultats, 0,
        reason: '2e passe : résultats déjà enregistrés → rien de nouveau');
    expect(nbPronosticsApres, nbPronosticsAvant,
        reason: 'la méthode ne crée jamais de pronostic');
    expect(nbResolus, 2, reason: 'exactement 2, pas 4');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T6 (obligatoire 6) — Mémoire et persistance.
  //
  //  Après analyse, les résultats doivent survivre à un rechargement
  //  (lecture disque). Vérifie aussi que les 19 critères sont présents.
  // ═══════════════════════════════════════════════════════════════════════
  test('T6 — les résultats persistent après rechargement depuis le disque',
      () async {
    final j1 = DateTime.now().subtract(const Duration(days: 1));
    final reunion = _reunion('R1', [
      DateTime(j1.year, j1.month, j1.day, 14, 15),
    ]);
    await _creerPronostics([reunion]);

    await _avecPmuSimule(
      () => IaMemoryService.instance.analyseJourneeComplete(date: j1));

    final avant = IaMemoryService.instance.pronostics.first;
    expect(avant.resultatsReels, isTrue);
    final arriveeAvant = avant.arriveeReelle;
    final nbCriteresAvant = avant.scoresCriteres.values
        .expand((s) => s.toJson().keys)
        .toSet()
        .length;

    // Rechargement complet depuis le disque
    await IaMemoryService.instance.recharger();

    final apres = IaMemoryService.instance.pronostics.first;
    final nbCriteresApres = apres.scoresCriteres.values
        .expand((s) => s.toJson().keys)
        .toSet()
        .length;

    // ignore: avoid_print
    print('  [T6] avant: resultatsReels=${avant.resultatsReels} '
        'arrivee=$arriveeAvant criteres=$nbCriteresAvant');
    // ignore: avoid_print
    print('  [T6] après: resultatsReels=${apres.resultatsReels} '
        'arrivee=${apres.arriveeReelle} criteres=$nbCriteresApres');

    expect(apres.resultatsReels, isTrue,
        reason: 'le résultat doit survivre au redémarrage');
    expect(apres.arriveeReelle, arriveeAvant);
    expect(nbCriteresApres, nbCriteresAvant,
        reason: 'les critères ne doivent pas être perdus');
    expect(nbCriteresApres, 19,
        reason: 'D1 : 19 critères attendus');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T7 — CONTRÔLE DIRECT DE A6-S : le même `date` produit le même
  //  résultat à toute heure, parce que la référence est l'horloge réelle.
  //
  //  On vérifie la NON-RÉGRESSION du correctif : une réunion de J-2 avec
  //  des départs très tardifs (22h, 23h) doit être analysée, alors que
  //  ces heures seraient « futures » par rapport à un appui matinal.
  // ═══════════════════════════════════════════════════════════════════════
  test('T7 — départs tardifs d\'une journée passée : analysés malgré '
      'l\'heure de l\'appui', () async {
    final j2 = DateTime.now().subtract(const Duration(days: 2));
    final reunion = _reunion('R1', [
      DateTime(j2.year, j2.month, j2.day, 22, 0),
      DateTime(j2.year, j2.month, j2.day, 23, 15),
    ]);
    await _creerPronostics([reunion]);

    final urls = <Uri>[];
    final res = await _avecPmuSimule(
      () => IaMemoryService.instance.analyseJourneeComplete(date: j2),
      urlsVues: urls,
    );

    // ignore: avoid_print
    print('  [T7] départs 22h00 et 23h15 de ${_fmt(j2)} → '
        'nouveaux=${res.nbNouveauxResultats} futures=${res.nbCoursesFutures} '
        'requêtes=${urls.length}');

    expect(res.nbCoursesFutures, 0,
        reason: 'A6-S : une course de J-2 à 23h15 est passée quelle que soit '
            'l\'heure de l\'appui. Avant le correctif, un appui avant 23h15 '
            'la classait « à venir »');
    expect(res.nbNouveauxResultats, 2);
    expect(urls.length, 2);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T8 — HTTP non-200 : pas d'apprentissage, pas de crash.
  // ═══════════════════════════════════════════════════════════════════════
  test('T8 — réponse PMU HTTP 500 : traitée proprement, sans apprentissage',
      () async {
    final j1 = DateTime.now().subtract(const Duration(days: 1));
    final reunion = _reunion('R1', [
      DateTime(j1.year, j1.month, j1.day, 14, 15),
    ]);
    await _creerPronostics([reunion]);
    final misesAvant = IaMemoryService.instance.poids.nbMisesAJour;

    final res = await _avecPmuSimule(
      () => IaMemoryService.instance.analyseJourneeComplete(date: j1),
      statusForce: 500,
    );

    // ignore: avoid_print
    print('  [T8] HTTP 500 → succes=${res.succes} '
        'sansRésultat=${res.nbSansResultat} '
        'nouveaux=${res.nbNouveauxResultats}');

    expect(res.succes, isTrue, reason: 'pas de crash');
    expect(res.nbNouveauxResultats, 0);
    expect(IaMemoryService.instance.poids.nbMisesAJour, misesAvant,
        reason: 'aucun apprentissage sur erreur réseau');
  });
}
