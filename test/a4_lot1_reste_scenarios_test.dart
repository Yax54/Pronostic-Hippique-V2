// ═══════════════════════════════════════════════════════════════════════════
//  A4 — LOT 1/2 — SCÉNARIOS RESTANTS : T1, T2, T5, T9, T10
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/.
//      Le correctif A4-T3 (ia_memory_service.dart) n'est ni touché ni testé
//      à nouveau ici : T3, T3-bis, T4 et T4b restent dans
//      `a4_lot1_analyse_nonregression_test.dart`, inchangé.
//      T8 reste dans `a4_poids_seuils_nonregression_test.dart`, inchangé.
//
//  ── RÈGLE ABSOLUE (arbitrage utilisateur) ─────────────────────────────────
//  À zéro nouveau résultat officiel exploitable, AUCUN paramètre
//  d'apprentissage IA ne doit être modifié par une simple répétition
//  d'analyse. Périmètre protégé, comparé au sens strict :
//    • les 19 poids IA ; • les poids par discipline ; • calibrationScore ;
//    • correlations ; • poidsIndices ; • dernierGradient ; • nbMisesAJour ;
//    • les huit seuils ; • ELO ; • le journal d'apprentissage.
//  Une réécriture de valeurs STRICTEMENT identiques (catégorie C) n'est PAS
//  un échec. Seule une modification de VALEUR en est un.
//
//  ── PRINCIPE DE MONTAGE (leçon de T8) ────────────────────────────────────
//  Chaque scénario commence par des TÉMOINS qui prouvent que le montage est
//  discriminant : si un témoin tombe, le test échoue bruyamment au lieu de
//  réussir pour la mauvaise raison.
//
//  ── PÉRIMÈTRE DES SNAPSHOTS ──────────────────────────────────────────────
//  `poids` (l.252) et `seuilsConfiance` (l.974) rendent la RÉFÉRENCE VIVE :
//  toute comparaison directe comparerait l'objet à lui-même. Les snapshots
//  passent donc par `toJson()` + `jsonEncode` (copie sérialisée).
//  T5 ajoute un snapshot du DISQUE COMPLET (toutes les clés, triées) pour
//  détecter toute écriture, y compris hors du périmètre IA.
//
//  ── CONTRAINTE DE HARNETSS ───────────────────────────────────────────────
//  Aucun `setUp()` : toute la préparation est dans le CORPS de chaque test.
//  Les singletons (`IaMemoryService`, `IaArchiveService`) conservent leur état
//  entre les tests d'un même fichier ; chaque test réinstalle donc
//  intégralement son store et recharge les deux services.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart'; // EloScore
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Outils de données — IDENTIQUES à a4_lot1_analyse_nonregression_test.dart
//  (dupliqués volontairement : un fichier de test ne peut pas importer le
//  `main()` d'un autre fichier de test)
// ───────────────────────────────────────────────────────────────────────────

String _cleDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _courseKey(int numCourse, DateTime d) =>
    'R1C${numCourse}_${_cleDate(d)}';

ScoresCriteres _scores(int graine) => ScoresCriteres(
      forme: 10.0 + graine * 1.0,
      gains: 20.0 + graine * 1.0,
      record: 30.0 + graine * 1.0,
      cote: 40.0 + graine * 1.0,
      constance: 50.0 + graine * 1.0,
      victoires: 60.0 + graine * 1.0,
      discipline: 70.0 + graine * 1.0,
      distSpec: 15.0 + graine * 1.0,
      jockey: 25.0 + graine * 1.0,
      repos: 35.0 + graine * 1.0,
      hippo: 45.0 + graine * 1.0,
      entraineur: 55.0 + graine * 1.0,
      elo: 65.0 + graine * 1.0,
      terrain: 75.0 + graine * 1.0,
      divergence: 18.0 + graine * 1.0,
      poidsRel: 28.0 + graine * 1.0,
      progression: 38.0 + graine * 1.0,
      mouvCote: 48.0 + graine * 1.0,
      placeDepart: 58.0 + graine * 1.0,
    );

/// Pronostic DÉJÀ RÉSOLU.
/// • `varianceScores` DISTINCTE (40 + 2·n) : sinon `_median` rend une valeur
///   égale à toutes, `hautConfiance` est vide et `_mettreAJourCalibration`
///   sort silencieusement par l.4153 sans rien prouver.
/// • `rangFavoriIaDansArrivee = 1` : `_estBonConseilParType('Simple Gagnant')`
///   rend `true`, donc `tauxReussite` = 100 % et `ajusterSeuil` réellement
///   sollicité quand l'apprentissage est actif.
IaPronostic _pronosticResolu(int numCourse, DateTime jour) => IaPronostic(
      courseKey: _courseKey(numCourse, jour),
      nomCourse: 'PRIX A4L1 N°$numCourse',
      hippodrome: 'Vincennes',
      discipline: 'Trot Attelé',
      datePronostic: jour,
      scoresIA: <String, double>{
        '1': 80.0 + numCourse,
        '2': 70.0 + numCourse,
        '3': 60.0 + numCourse,
      },
      scoresCriteres: <String, ScoresCriteres>{
        '1': _scores(1),
        '2': _scores(2),
        '3': _scores(3),
      },
      varianceScores: 40.0 + numCourse * 2.0,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
      dateResultat: jour,
      resultatsReels: true,
      rangFavoriIaDansArrivee: 1,
      nbTop3DansArriveeReelle: 3,
      nbTop5DansArriveeReelle: 3,
      scorePerformance: 85.0,
      diagnosticApprentissage: 'Résultat officiel enregistré',
      confiancePredite: 71.5,
      typePariConseille: 'Simple Gagnant',
      tauxReussiteAuMoment: 42.5,
      precisionIA: 64.25,
      favoriIaNom: 'CHEVAL 1',
      coteFavoriPmu: 2.8,
      cotesPmuParNumero: const <String, double>{'1': 2.8, '2': 5.4, '3': 9.1},
    );

/// Pronostic NON résolu.
IaPronostic _pronosticEnAttente(int numCourse, DateTime jour) => IaPronostic(
      courseKey: _courseKey(numCourse, jour),
      nomCourse: 'PRIX A4L1 N°$numCourse',
      hippodrome: 'Vincennes',
      discipline: 'Trot Attelé',
      datePronostic: jour,
      scoresIA: <String, double>{'1': 70.0, '2': 60.0, '3': 50.0},
      scoresCriteres: <String, ScoresCriteres>{
        '1': _scores(1),
        '2': _scores(2),
        '3': _scores(3),
      },
      varianceScores: 66.6666,
      resultatsReels: false,
      confiancePredite: 55.0,
      typePariConseille: 'Simple Gagnant',
      tauxReussiteAuMoment: 38.0,
      precisionIA: 51.0,
      favoriIaNom: 'CHEVAL 1',
      coteFavoriPmu: 4.2,
    );

/// Poids volontairement ÉLOIGNÉS des valeurs d'usine : un retour accidentel à
/// `IaPoidsAdaptatifs.defaut()` (ia_memory_service.dart:2202) est détecté.
Map<String, dynamic> _poidsNonTriviaux() {
  final p = IaPoidsAdaptatifs.defaut();
  p.nbMisesAJour = 137;
  p.calibrationScore = 68.3125;
  p.forme = 0.2711;
  p.gains = 0.1409;
  p.mouvCote = 0.0655;
  p.placeDepart = 0.0311;
  p.dernierGradient = <String, double>{'forme': 0.0125, 'elo': -0.0075};
  p.poidsIndices = PoidsIndices(
      poidsCriteres: 0.4321, poidsConfiance: 0.3333, poidsReussite: 0.2346);
  p.correlations = <String, double>{'forme|cote': 0.4125, 'elo|gains': -0.1875};
  p.poidsParDiscipline['TROT_ATTELE'] = <String, double>{
    'forme': 0.30, 'gains': 0.12, 'record': 0.10, 'cote': 0.08,
    'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
    'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03,
    'hippo': 0.04, 'entraineur': 0.04, 'elo': 0.05,
    'terrain': 0.05, 'divergence': 0.04, 'poidsRel': 0.03,
    'progression': 0.03, 'mouvCote': 0.06, 'placeDepart': 0.03,
  };
  return p.toJson();
}

/// Seuils ÉLOIGNÉS des constantes de classe (ia_memory_service.dart:7545).
SeuilsConfianceAdaptatifs _seuilsNonTriviaux() => SeuilsConfianceAdaptatifs(
      seuilSimpleGagnant: 83.5,
      seuilGagnantPlace: 44.25,
      seuilSimplePlace: 71.75,
      seuilCoupleGagnant: 79.5,
      seuilCouplePlace: 55.125,
      seuilTierce: 27.25,
      seuilQuarte: 86.875,
      seuilQuinte: 0.0,
    );

/// Journal d'apprentissage pré-existant : LONGUEUR et CONTENU comparés.
List<JournalEntree> _journalInitial(DateTime jour) => <JournalEntree>[
      JournalEntree(
        date: jour,
        nomCourse: 'PRIX JOURNAL A4L1',
        discipline: 'Trot Attelé',
        nbCoursesAnalysees: 12,
        diagnostic: 'Entrée pré-existante — référence de non-régression',
        avant: const <String, double>{'forme': 0.25, 'elo': 0.05},
        apres: const <String, double>{'forme': 0.2510, 'elo': 0.0490},
        scorePerf: 61.0,
        methode: 'gradient',
      ),
    ];

String _cleElo(String nom, String discipline) {
  final nomNorm = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  return '$nomNorm|${EloService.normaliserDiscipline(discipline)}';
}

/// Peuple SharedPreferences aux clés lues par `_load()` (l.2214+).
/// `ia_precision_v2` est volontairement ABSENT.
Map<String, Object> _prefs({
  required List<IaPronostic> pronostics,
  required DateTime jour,
}) =>
    <String, Object>{
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode(_poidsNonTriviaux()),
      'ia_seuils_v1': json.encode(_seuilsNonTriviaux().toJson()),
      'ia_pronostics_v2':
          pronostics.map((p) => json.encode(p.toJson())).toList(),
      'ia_journal_v2':
          _journalInitial(jour).map((j) => json.encode(j.toJson())).toList(),
    };

// ───────────────────────────────────────────────────────────────────────────
//  Snapshots
// ───────────────────────────────────────────────────────────────────────────

/// Clés de persistance écrites par `IaMemoryService._save()` (l.2693-2758).
/// Distinctes des clés d'archive (`ia_archive_v1_*`) : en T9, l'écriture
/// d'archive est LÉGITIME, celle du service ne l'est pas.
const List<String> _clesService = <String>[
  'ia_poids_v3',
  'ia_seuils_v1',
  'ia_pronostics_v2',
  'ia_journal_v2',
  'ia_rapports_v1',
  'ia_bilans_semaine_v1',
  'ia_bilans_mois_v1',
  'ia_stats_types_v1',
  'ia_precision_v2',
  'ia_stats_labels_v1',
];

/// Instantané des SEULES clés du service (hors archive).
///
/// Indispensable à T9 : `_consignerResultatEnArchive` DOIT écrire dans
/// l'archive mais ne doit écrire AUCUNE clé du service (l.3397-3398 exige
/// l'absence de `_save()`). Un diff global ne saurait pas distinguer les deux.
String _disqueService(SharedPreferences prefs) {
  final map = <String, dynamic>{};
  for (final k in _clesService) {
    final v = prefs.get(k);
    if (v is List) {
      map[k] = List<String>.from(v.map((e) => e.toString()));
    } else {
      map[k] = v?.toString();
    }
  }
  return json.encode(map);
}

/// Instantané du DISQUE COMPLET : toutes les clés, triées, valeurs encodées.
String _disqueComplet(SharedPreferences prefs) {
  final cles = prefs.getKeys().toList()..sort();
  final map = <String, dynamic>{};
  for (final k in cles) {
    final v = prefs.get(k);
    if (v is List) {
      map[k] = List<String>.from(v.map((e) => e.toString()));
    } else {
      map[k] = v?.toString();
    }
  }
  return json.encode(map);
}

class _EtatIA {
  final Map<String, dynamic> poids;
  final Map<String, dynamic> seuils;
  final String elo;
  final String journal;
  final String pronostics;
  final int nbMisesAJour;
  final String poidsDisque;
  final String seuilsDisque;
  final String disqueComplet;
  final String disqueService;

  const _EtatIA({
    required this.poids,
    required this.seuils,
    required this.elo,
    required this.journal,
    required this.pronostics,
    required this.nbMisesAJour,
    required this.poidsDisque,
    required this.seuilsDisque,
    required this.disqueComplet,
    required this.disqueService,
  });

  static _EtatIA prendre(SharedPreferences prefs) {
    final svc = IaMemoryService.instance;
    return _EtatIA(
      poids: json.decode(json.encode(svc.poids.toJson())) as Map<String, dynamic>,
      seuils: json.decode(json.encode(svc.seuilsConfiance.toJson()))
          as Map<String, dynamic>,
      elo: json.encode(EloService.instance.exporterPourBackup()),
      journal: json.encode(svc.journal.map((j) => j.toJson()).toList()),
      pronostics: json.encode(svc.pronostics.map((p) => p.toJson()).toList()),
      nbMisesAJour: svc.poids.nbMisesAJour,
      poidsDisque: prefs.getString('ia_poids_v3') ?? '',
      seuilsDisque: prefs.getString('ia_seuils_v1') ?? '',
      disqueComplet: _disqueComplet(prefs),
      disqueService: _disqueService(prefs),
    );
  }

  /// Différentiel clé par clé sur le périmètre protégé.
  static List<String> differences(_EtatIA avant, _EtatIA apres) {
    final d = <String>[];
    for (final k in <String>{...avant.poids.keys, ...apres.poids.keys}) {
      final a = json.encode(avant.poids[k]);
      final b = json.encode(apres.poids[k]);
      if (a != b) d.add('poids.toJson()["$k"] : $a → $b');
    }
    for (final k in <String>{...avant.seuils.keys, ...apres.seuils.keys}) {
      final a = json.encode(avant.seuils[k]);
      final b = json.encode(apres.seuils[k]);
      if (a != b) d.add('seuilsConfiance.toJson()["$k"] : $a → $b');
    }
    if (avant.elo != apres.elo) d.add('ELO exporté : modifié');
    if (avant.journal != apres.journal) {
      d.add("journal d'apprentissage : ${avant.journal} → ${apres.journal}");
    }
    if (avant.nbMisesAJour != apres.nbMisesAJour) {
      d.add('nbMisesAJour : ${avant.nbMisesAJour} → ${apres.nbMisesAJour}');
    }
    if (avant.poidsDisque != apres.poidsDisque) {
      d.add('disque ia_poids_v3 : CONTENU modifié');
    }
    if (avant.seuilsDisque != apres.seuilsDisque) {
      d.add('disque ia_seuils_v1 : CONTENU modifié');
    }
    if (avant.pronostics != apres.pronostics) {
      d.add('pronostics : liste modifiée (double traitement ou recalcul)');
    }
    return d;
  }

  static String rapport(String titre, _EtatIA avant, _EtatIA apres) {
    final d = differences(avant, apres);
    if (d.isEmpty) return '$titre : AUCUNE différence sur le périmètre protégé.';
    return '$titre : ${d.length} MODIFICATION(S) RÉELLE(S) —\n  ${d.join('\n  ')}';
  }
}

// ───────────────────────────────────────────────────────────────────────────
//  Montage commun
// ───────────────────────────────────────────────────────────────────────────

Future<SharedPreferences> _monter(
    List<IaPronostic> pronostics, DateTime jourCourse) async {
  SharedPreferences.setMockInitialValues(
    _prefs(pronostics: pronostics, jour: jourCourse),
  );
  final prefs = await SharedPreferences.getInstance();
  await EloService.instance.importerDepuisBackup(<String, dynamic>{
    for (final e in <String, double>{
      'CHEVAL 1': 1900.0,
      'CHEVAL 2': 1700.0,
      'CHEVAL 3': 1500.0,
    }.entries)
      _cleElo(e.key, 'Trot Attelé'):
          EloScore(nomCheval: e.key, rating: e.value, nbCourses: 10).toJson(),
  });
  await IaArchiveService.instance.viderPourTest();
  await IaMemoryService.instance.recharger();
  return prefs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  T1 — RECHARGEMENT DEPUIS DES POIDS ET SEUILS PERSISTÉS NON STANDARDS
  //
  //  Objectif : prouver que `recharger()` (l.2190) restaure EXACTEMENT ce qui
  //  est sur le disque, et ne substitue NI les valeurs d'usine de
  //  `IaPoidsAdaptatifs.defaut()` (l.2202) NI les constantes de
  //  `SeuilsConfianceAdaptatifs()` (l.2201).
  // ═════════════════════════════════════════════════════════════════════════
  test('A4-T1 — rechargement depuis des poids et seuils persistés non '
      'standards : aucune substitution par les valeurs d\'usine', () async {
    final svc = IaMemoryService.instance;
    final jour = DateTime.now().subtract(const Duration(days: 1));
    final jourCourse = DateTime(jour.year, jour.month, jour.day, 14, 30);

    final pronostics = <IaPronostic>[
      for (var i = 1; i <= 13; i++) _pronosticResolu(i, jourCourse),
    ];

    // Store installé, mais service PAS encore rechargé : on capture le disque
    // AVANT tout chargement, pour pouvoir prouver qu'il n'est pas réécrit.
    SharedPreferences.setMockInitialValues(
      _prefs(pronostics: pronostics, jour: jourCourse),
    );
    final prefs = await SharedPreferences.getInstance();
    await EloService.instance.importerDepuisBackup(<String, dynamic>{
      for (final e in <String, double>{
        'CHEVAL 1': 1900.0,
        'CHEVAL 2': 1700.0,
        'CHEVAL 3': 1500.0,
      }.entries)
        _cleElo(e.key, 'Trot Attelé'):
            EloScore(nomCheval: e.key, rating: e.value, nbCourses: 10).toJson(),
    });
    await IaArchiveService.instance.viderPourTest();

    final poidsDisqueAvant = prefs.getString('ia_poids_v3')!;
    final seuilsDisqueAvant = prefs.getString('ia_seuils_v1')!;
    final disqueAvant = _disqueComplet(prefs);
    final avantService = _disqueService(prefs);

    // ── TÉMOIN : le disque porte bien les valeurs non standards ────────────
    expect(json.decode(poidsDisqueAvant)['nbMisesAJour'], 137,
        reason: 'TÉMOIN : le disque contient nbMisesAJour=137');
    expect(json.decode(poidsDisqueAvant)['calibrationScore'], 68.3125,
        reason: 'TÉMOIN : le disque contient calibrationScore=68.3125');
    expect(json.decode(seuilsDisqueAvant)['sg'], 83.5,
        reason: 'TÉMOIN : le disque contient seuilSimpleGagnant=83.5');
    expect(
        json.decode(poidsDisqueAvant)['forme'],
        isNot(closeTo(IaPoidsAdaptatifs.defaut().forme, 1e-12)),
        reason: 'TÉMOIN DÉCISIF : la valeur du disque DIFFÈRE de la valeur '
            'd\'usine — sinon le test ne pourrait rien distinguer');

    // ── Rechargement réel ──────────────────────────────────────────────────
    await svc.recharger();

    // ── 1. Les 25 clés de `IaPoidsAdaptatifs.toJson()` sont restaurées ────
    //      à l'identique (19 critères + nbMisesAJour + calibrationScore +
    //      poidsParDiscipline + dernierGradient + poidsIndices + correlations)
    expect(json.encode(svc.poids.toJson()), poidsDisqueAvant,
        reason: 'A4-T1 : `_poids` doit être la copie EXACTE du disque. '
            'Écart = substitution par defaut() (l.2202) ou normalisation '
            'parasite au chargement');

    // ── 2. Contrôles explicites, critère par critère (lisibilité d'échec) ─
    expect(svc.poids.nbMisesAJour, 137,
        reason: 'A4-T1 : nbMisesAJour restauré');
    expect(svc.poids.calibrationScore, closeTo(68.3125, 1e-12),
        reason: 'A4-T1 : calibrationScore restauré');
    expect(svc.poids.forme, closeTo(0.2711, 1e-12),
        reason: 'A4-T1 : forme restaurée (usine = 0.25)');
    expect(svc.poids.gains, closeTo(0.1409, 1e-12),
        reason: 'A4-T1 : gains restauré (usine = 0.13)');
    expect(svc.poids.mouvCote, closeTo(0.0655, 1e-12),
        reason: 'A4-T1 : mouvCote restauré (usine = 0.06)');
    expect(svc.poids.placeDepart, closeTo(0.0311, 1e-12),
        reason: 'A4-T1 : placeDepart restauré (usine = 0.03)');
    expect(svc.poids.dernierGradient['forme'], closeTo(0.0125, 1e-12),
        reason: 'A4-T1 : dernierGradient restauré');
    expect(svc.poids.dernierGradient['elo'], closeTo(-0.0075, 1e-12),
        reason: 'A4-T1 : dernierGradient restauré (valeur négative)');
    expect(svc.poids.poidsIndices.poidsCriteres, closeTo(0.4321, 1e-12),
        reason: 'A4-T1 : poidsIndices restaurés');
    expect(svc.poids.poidsIndices.poidsReussite, closeTo(0.2346, 1e-12),
        reason: 'A4-T1 : poidsIndices restaurés');
    expect(json.encode(svc.poids.correlations),
        json.encode(<String, double>{'forme|cote': 0.4125, 'elo|gains': -0.1875}),
        reason: 'A4-T1 : correlations restaurées');
    expect(svc.poids.poidsParDiscipline['TROT_ATTELE']?['forme'], 0.30,
        reason: 'A4-T1 : poids par discipline restaurés');
    expect(svc.poids.poidsParDiscipline.length, 1,
        reason: 'A4-T1 : aucune discipline supplémentaire inventée');

    // ── 3. Les 8 seuils sont restaurés, pas les constantes de classe ──────
    expect(svc.seuilsConfiance.seuilSimpleGagnant, 83.5,
        reason: 'A4-T1 : seuil SG restauré (constante de classe = 80.0)');
    expect(svc.seuilsConfiance.seuilGagnantPlace, 44.25,
        reason: 'A4-T1 : seuil GP restauré (constante de classe = 50.0)');
    expect(svc.seuilsConfiance.seuilSimplePlace, 71.75,
        reason: 'A4-T1 : seuil SP restauré');
    expect(svc.seuilsConfiance.seuilCoupleGagnant, 79.5,
        reason: 'A4-T1 : seuil CG restauré');
    expect(svc.seuilsConfiance.seuilCouplePlace, 55.125,
        reason: 'A4-T1 : seuil CP restauré');
    expect(svc.seuilsConfiance.seuilTierce, 27.25,
        reason: 'A4-T1 : seuil TI restauré');
    expect(svc.seuilsConfiance.seuilQuarte, 86.875,
        reason: 'A4-T1 : seuil QA restauré');
    expect(svc.seuilsConfiance.seuilQuinte, 0.0,
        reason: 'A4-T1 : seuil QI restauré');
    expect(json.encode(svc.seuilsConfiance.toJson()), seuilsDisqueAvant,
        reason: 'A4-T1 : les 8 seuils doivent être la copie EXACTE du disque');

    // ── 4. Registre de calibration synchronisé au chargement (l.2351) ─────
    expect(IaCalibrationRegistry.value, closeTo(68.3125, 1e-12),
        reason: 'A4-T1 : `IaCalibrationRegistry` doit refléter la valeur '
            'chargée (synchronisation l.2351), pas rester à 50.0');

    // ── 5. Le chargement n'a RIEN réécrit sur le disque ───────────────────
    //      (catégorie C silencieuse évitée : le flag de migration est semé,
    //      donc `_recalculerPrecisionParTypeDepuisPronostics` n'est pas appelé)
    expect(prefs.getString('ia_poids_v3'), poidsDisqueAvant,
        reason: 'A4-T1 : ia_poids_v3 ne doit pas être réécrit au chargement');
    expect(prefs.getString('ia_seuils_v1'), seuilsDisqueAvant,
        reason: 'A4-T1 : ia_seuils_v1 ne doit pas être réécrit au chargement');
    expect(_disqueComplet(prefs), disqueAvant,
        reason: 'A4-T1 : AUCUNE écriture disque ne doit avoir lieu pendant '
            '`recharger()` (flag ia_precision_migrated_v3 semé)');
    expect(_EtatIA.prendre(prefs).disqueService, avantService,
        reason: 'A4-T1 : aucune des 10 clés du service ne doit être réécrite '
            'au chargement (catégorie C silencieuse évitée)');

    // ── 6. État mémoire connexe ───────────────────────────────────────────
    expect(svc.pronosticsCount, 13, reason: 'A4-T1 : pronostics rechargés');
    expect(svc.pronosticsAvecResultat.length, 13,
        reason: 'A4-T1 : les 13 résultats sont rechargés');
    expect(svc.journal.length, 1, reason: 'A4-T1 : journal rechargé');
    expect(EloService.instance.nbChevauxSuivis, 3,
        reason: 'A4-T1 : les 3 ratings ELO sont chargés');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T2 — DEUX RECHARGEMENTS SUCCESSIFS SANS DÉGRADATION
  //
  //  Objectif : un second `recharger()` ne doit RIEN perdre ni dégrader.
  //  Ce n'est pas seulement « e1 == e2 » (qui serait vrai aussi si les deux
  //  états étaient également faux) : les valeurs sont recontrôlées
  //  EXPLICITEMENT contre les valeurs du disque initial.
  // ═════════════════════════════════════════════════════════════════════════
  test('A4-T2 — deux rechargements successifs : aucune dégradation des '
      'paramètres IA', () async {
    final svc = IaMemoryService.instance;
    final jour = DateTime.now().subtract(const Duration(days: 1));
    final jourCourse = DateTime(jour.year, jour.month, jour.day, 14, 30);

    final pronostics = <IaPronostic>[
      for (var i = 1; i <= 13; i++) _pronosticResolu(i, jourCourse),
    ];
    final prefs = await _monter(pronostics, jourCourse);

    final poidsDisqueReference = prefs.getString('ia_poids_v3')!;
    final seuilsDisqueReference = prefs.getString('ia_seuils_v1')!;
    final disqueReference = _disqueComplet(prefs);

    // ── 1er rechargement (le montage en a déjà fait un : on en refait un) ──
    await svc.recharger();
    final e1 = _EtatIA.prendre(prefs);

    // ── 2e rechargement ───────────────────────────────────────────────────
    await svc.recharger();
    final e2 = _EtatIA.prendre(prefs);

    // ignore: avoid_print
    print('[A4-T2] e1 → e2 : ${_EtatIA.differences(e1, e2).length} '
        'différence(s)');

    // ── TÉMOINS : les deux états sont non triviaux et égaux au disque ─────
    expect(e1.nbMisesAJour, 137,
        reason: 'TÉMOIN : après le 1er rechargement, nbMisesAJour=137');
    expect(e2.nbMisesAJour, 137,
        reason: 'TÉMOIN : après le 2e rechargement, nbMisesAJour=137');
    expect(e1.poids['forme'], closeTo(0.2711, 1e-12),
        reason: 'TÉMOIN : forme non standard conservée après 1 rechargement');
    expect(e2.poids['forme'], closeTo(0.2711, 1e-12),
        reason: 'TÉMOIN : forme non standard conservée après 2 rechargements');
    expect(e2.poids['calibrationScore'], closeTo(68.3125, 1e-12),
        reason: 'TÉMOIN : calibrationScore conservée après 2 rechargements');
    expect(e2.seuils['sg'], 83.5,
        reason: 'TÉMOIN : seuil SG conservé après 2 rechargements');

    // ── Aucune dégradation entre les deux chargements ─────────────────────
    expect(_EtatIA.differences(e1, e2), isEmpty,
        reason: _EtatIA.rapport('A4-T2 : 1er → 2e rechargement', e1, e2));

    // ── Les deux états sont identiques au DISQUE de référence ─────────────
    expect(e2.poidsDisque, poidsDisqueReference,
        reason: 'A4-T2 : ia_poids_v3 doit rester byte-identique à la référence');
    expect(e2.seuilsDisque, seuilsDisqueReference,
        reason: 'A4-T2 : ia_seuils_v1 doit rester byte-identique à la référence');
    expect(_disqueComplet(prefs), disqueReference,
        reason: 'A4-T2 : deux chargements ne doivent produire AUCUNE écriture '
            'disque (ni valeur, ni clé ajoutée)');

    // ── Le journal n'a pas doublé (piège classique d\'un reload naïf) ────
    expect(json.decode(e2.journal).length, 1,
        reason: 'A4-T2 : le journal doit contenir EXACTEMENT 1 entrée, '
            'pas ${json.decode(e2.journal).length} (double insertion)');

    // ── Les pronostics n'ont pas été dupliqués ────────────────────────────
    expect(svc.pronosticsCount, 13,
        reason: 'A4-T2 : 13 pronostics, pas de duplication');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T5 — CONSULTATION DES STATISTIQUES : AUCUNE MUTATION, AUCUNE ÉCRITURE
  //
  //  Objectif : toutes les lectures de l'écran « IA Performance » et du
  //  calendrier sont PURES. Chaque lecteur est mesuré INDIVIDUELLEMENT pour
  //  attribuer précisément toute écriture imprévue.
  // ═════════════════════════════════════════════════════════════════════════
  test('A4-T5 — consultation des statistiques : aucune mutation IA ni '
      'écriture disque injustifiée', () async {
    final svc = IaMemoryService.instance;
    final jour = DateTime.now().subtract(const Duration(days: 1));
    final jourCourse = DateTime(jour.year, jour.month, jour.day, 14, 30);

    final pronostics = <IaPronostic>[
      for (var i = 1; i <= 13; i++) _pronosticResolu(i, jourCourse),
    ];
    final prefs = await _monter(pronostics, jourCourse);
    final cle1 = _courseKey(1, jourCourse);

    // ── TÉMOIN : le montage est riche, donc les lectures ont du contenu ───
    expect(svc.pronosticsAvecResultat.length, 13,
        reason: 'TÉMOIN : 13 pronostics résolus à consulter');
    expect(svc.poids.calibrationScore, closeTo(68.3125, 1e-12),
        reason: 'TÉMOIN : calibration non triviale à préserver');
    expect(svc.seuilsConfiance.seuilSimpleGagnant, 83.5,
        reason: 'TÉMOIN : seuils non triviaux à préserver');

    // Les 13 pronostics partagent le même type et la même discipline : les
    // agrégats sont donc non vides et exercés réellement.
    final stats0 = svc.calculerStats();
    expect(stats0.coursesAvecResultat, 13,
        reason: 'TÉMOIN : `calculerStats` voit bien 13 courses résolues');
    expect(stats0.favoriGagnant, 13,
        reason: 'TÉMOIN : 13 favoris IA gagnants (montage déterministe)');

    // ── Batterie de lecteurs, mesurés un par un ───────────────────────────
    final mutants = <String>[];
    void mesurer(String nom, void Function() lecture) {
      final eAvant = _EtatIA.prendre(prefs);
      lecture();
      final eApres = _EtatIA.prendre(prefs);
      final d = _EtatIA.differences(eAvant, eApres);
      if (d.isNotEmpty) mutants.add('$nom : ${d.join(' | ')}');
    }

    mesurer('calculerStats', () => svc.calculerStats());
    mesurer('statsParType', () => svc.statsParType);
    mesurer('precisionParType', () => svc.precisionParType);
    mesurer('precisionParTypeAvecGrosParis',
        () => svc.precisionParTypeAvecGrosParis);
    mesurer('statsParLabel', () => svc.statsParLabel);
    mesurer('seuilsConfiance', () => svc.seuilsConfiance.toJson());
    mesurer('getSeuilsAdaptatifs', () => svc.getSeuilsAdaptatifs().toJson());
    mesurer('poidsIndices', () => svc.poidsIndices.toJson());
    mesurer('poids', () => svc.poids.toJson());
    mesurer('pronosticsAvecResultat', () => svc.pronosticsAvecResultat.length);
    mesurer('pronosticsCount', () => svc.pronosticsCount);
    mesurer('journal', () => svc.journal.length);
    mesurer('rapports', () => svc.rapports.length);
    mesurer('dernierRapport', () => svc.dernierRapport?.toJson());
    mesurer('bilansSemaine', () => svc.bilansSemaine.length);
    mesurer('bilansMois', () => svc.bilansMois.length);
    mesurer('grosParisGagnants', () => svc.grosParisGagnants.length);
    mesurer('statsGrosParisGagnantsParType',
        () => svc.statsGrosParisGagnantsParType);
    mesurer('precisionAujourdhuiDepuisPronostics',
        () => svc.precisionAujourdhuiDepuisPronostics);
    mesurer('precisionParHippodromeAvecFiabilite',
        () => svc.precisionParHippodromeAvecFiabilite);
    mesurer('precisionHippodromeXDiscipline',
        () => svc.precisionHippodromeXDiscipline);
    mesurer('poidsEffectifsPour', () => svc.poidsEffectifsPour('Trot Attelé'));
    mesurer('disciplinesApprises', () => svc.disciplinesApprises);
    mesurer('donneesCalendrierJour',
        () => svc.donneesCalendrierJour(jourCourse.year, jourCourse.month));
    mesurer('nbPronosticsSansResultat', () => svc.nbPronosticsSansResultat);
    mesurer('arriveeConnue', () => svc.arriveeConnue(cle1));
    mesurer('getPronostic', () => svc.getPronostic(cle1)?.toJson());
    mesurer('serieChaudePourType',
        () => svc.serieChaudePourType('Simple Gagnant'));
    mesurer('estBonConseil', () {
      final p = svc.getPronostic(cle1);
      if (p != null) svc.estBonConseil(p, 'Simple Gagnant');
    });
    mesurer('diagnosticPronosticRepository',
        () => svc.diagnosticPronosticRepository());

    // ignore: avoid_print
    print('[A4-T5] lecteurs mesurés=30 mutants=${mutants.length}');
    for (final m in mutants) {
      // ignore: avoid_print
      print('  [A4-T5] MUTATION PAR $m');
    }

    expect(mutants, isEmpty,
        reason: 'A4-T5 : ${mutants.length} lecteur(s) ont muté l\'état —\n'
            '  ${mutants.join('\n  ')}');

    // ── Contrôle final : rien n'a bougé non plus globalement ─────────────
    expect(svc.pronosticsCount, 13);
    expect(svc.poids.calibrationScore, closeTo(68.3125, 1e-12),
        reason: 'A4-T5 : calibration intacte après 30 lectures');
    expect(svc.seuilsConfiance.seuilSimpleGagnant, 83.5,
        reason: 'A4-T5 : seuil SG intact après 30 lectures');
    expect(svc.journal.length, 1,
        reason: 'A4-T5 : le journal n\'a reçu AUCUNE entrée de consultation');

    // ── Les statistiques sont réelles, pas un fallback vide ──────────────
    expect(svc.statsParLabel, isNotNull);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T9 — RÉSULTAT D'UNE COURSE ABSENTE DE LA MÉMOIRE ACTIVE
  //
  //  Objectif : vérifier le VÉRITABLE chemin d'archivage de
  //  `enregistrerResultat` — la branche `idx < 0` (l.3256) qui appelle
  //  `_consignerResultatEnArchive` (l.3407) — et prouver qu'elle :
  //    • ne réinjecte JAMAIS la course dans `_pronostics` ;
  //    • n'apprend RIEN (poids, seuils, calibration, journal, ELO) ;
  //    • n'écrit AUCUNE clé du SERVICE ;
  //    • écrit RÉELLEMENT dans l'archive, et de façon durable (relecture
  //      depuis le stockage après vidage de la mémoire RAM).
  // ═════════════════════════════════════════════════════════════════════════
  test('A4-T9 — résultat d\'une course absente de la mémoire active : '
      'archivage réel, aucune réinjection, aucun apprentissage', () async {
    final svc = IaMemoryService.instance;
    final archive = IaArchiveService.instance;
    final jour = DateTime.now().subtract(const Duration(days: 1));
    final jourCourse = DateTime(jour.year, jour.month, jour.day, 14, 30);

    // La mémoire active contient 3 courses (1..3) ; la course 600 n'y est PAS.
    final pronostics = <IaPronostic>[
      for (var i = 1; i <= 3; i++) _pronosticResolu(i, jourCourse),
    ];
    final prefs = await _monter(pronostics, jourCourse);
    final cleAbsente = _courseKey(600, jourCourse);

    // ── TÉMOIN : la course 600 est absente de la mémoire active ───────────
    expect(svc.getPronostic(cleAbsente), isNull,
        reason: 'TÉMOIN DÉCISIF : la course 600 ne doit pas être en mémoire, '
            'sinon la branche `idx < 0` (l.3256) ne serait pas parcourue');
    expect(svc.pronosticsCount, 3, reason: 'TÉMOIN : 3 pronostics en mémoire');

    // ── La course 600 existe dans l'ARCHIVE, NON RÉSOLUE ─────────────────
    archive.enregistrerEviction(_pronosticEnAttente(600, jourCourse));
    final persiste1 = await archive.persisterEnAttente();
    expect(persiste1, isTrue,
        reason: 'TÉMOIN : l\'archive doit avoir persisté la version initiale');

    // ── Relecture depuis le stockage : on prouve le VRAI chemin disque ────
    await archive.reinitialiserMemoirePourTest();
    expect(archive.archiveDisponible, isTrue,
        reason: 'TÉMOIN : l\'archive est réellement relue depuis le stockage');
    expect(archive.nbShardsSurDisque, greaterThan(0),
        reason: 'TÉMOIN : au moins un shard persiste sur le disque');

    final archiveAvant = archive.versionRetenue(cleAbsente);
    expect(archiveAvant, isNotNull,
        reason: 'TÉMOIN : la course 600 est retrouvée par l\'archive');
    expect(archiveAvant!.resultatsReels, isFalse,
        reason: 'TÉMOIN : la version archivée n\'a pas encore de résultat');
    final nbVersionsAvant = archive.nbVersions(cleAbsente);
    final nbDistinctesAvant = archive.nbPredictionsDistinctes;
    final nbVersionsArchiveesAvant = archive.nbVersionsArchivees;

    // ── Snapshots AVANT ───────────────────────────────────────────────────
    final avant = _EtatIA.prendre(prefs);
    final poidsDisqueAvant = prefs.getString('ia_poids_v3');
    final seuilsDisqueAvant = prefs.getString('ia_seuils_v1');
    final journalDisqueAvant = prefs.getStringList('ia_journal_v2')?.toString();

    // ── Appel réel : résultat officiel pour une course HORS mémoire ───────
    await svc.enregistrerResultat(
      courseKey: cleAbsente,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
      cotesPmuParNumero: const <String, double>{'1': 2.2, '2': 5.0, '3': 9.0},
    );

    final apres = _EtatIA.prendre(prefs);
    final archiveApres = archive.versionRetenue(cleAbsente);

    // ignore: avoid_print
    print('[A4-T9] en mémoire : pronosticsCount=${svc.pronosticsCount} '
        'getPronostic(600)=${svc.getPronostic(cleAbsente)}');
    // ignore: avoid_print
    print('[A4-T9] archive 600 : resultatsReels='
        '${archiveAvant.resultatsReels} → ${archiveApres?.resultatsReels} '
        'nbVersions=$nbVersionsAvant → ${archive.nbVersions(cleAbsente)}');
    // ignore: avoid_print
    print('[A4-T9] différences mémoire=${_EtatIA.differences(avant, apres).length}');

    // ── 1. AUCUNE réinjection dans la mémoire active ──────────────────────
    expect(svc.getPronostic(cleAbsente), isNull,
        reason: 'A4-T9 : la course évincée ne doit JAMAIS revenir en mémoire');
    expect(svc.pronosticsCount, 3,
        reason: 'A4-T9 : la mémoire de travail reste à 3 pronostics');
    expect(svc.pronosticsAvecResultat.length, 3,
        reason: 'A4-T9 : l\'archive ne doit JAMAIS alimenter '
            '`pronosticsAvecResultat`');

    // ── 2. Le résultat est RÉELLEMENT consigné dans l'archive ────────────
    expect(archiveApres, isNotNull,
        reason: 'A4-T9 : la version archivée doit exister après l\'appel');
    expect(archiveApres!.resultatsReels, isTrue,
        reason: 'A4-T9 : le résultat doit être consigné (resultatsReels=true). '
            'Sinon le résultat officiel serait silencieusement perdu');
    expect(archiveApres.arriveeReelle, const <int>[1, 2, 3, 4, 5],
        reason: 'A4-T9 : l\'arrivée officielle doit être enregistrée telle quelle');
    expect(archiveApres.dateResultat, isNotNull,
        reason: 'A4-T9 : la date du résultat doit être renseignée');
    expect(archiveApres.scorePerformance, isNotNull,
        reason: 'A4-T9 : le score de performance doit être calculé');
    expect(archiveApres.scorePerformance, inInclusiveRange(0.0, 100.0),
        reason: 'A4-T9 : le score de performance doit rester borné 0-100');
    expect(archiveApres.rangFavoriIaDansArrivee, 1,
        reason: 'A4-T9 : le favori IA (n°1) est 1er de l\'arrivée fournie');
    expect(archiveApres.precisionIA, isNotNull,
        reason: 'A4-T9 : precisionIA doit être recalculée dans l\'archive');
    expect(archiveApres.diagnosticApprentissage, isNotNull,
        reason: 'A4-T9 : le diagnostic de course doit être généré');
    expect(archive.nbVersions(cleAbsente), greaterThan(nbVersionsAvant),
        reason: 'A4-T9 : une nouvelle VERSION doit être ajoutée à l\'archive '
            '($nbVersionsAvant → ${archive.nbVersions(cleAbsente)}), '
            'l\'ancienne non résolue restant comme historique');

    // ── 3. L'archive reste PERSISTANTE (relecture depuis le stockage) ────
    final disqueApres = _disqueComplet(prefs);
    final clesArchive =
        prefs.getKeys().where((k) => k.startsWith('ia_archive_v1_')).toList();
    expect(clesArchive, isNotEmpty,
        reason: 'A4-T9 : les shards d\'archive doivent exister sur le disque');
    expect(disqueApres, isNot(_disqueComplet(prefs).isEmpty ? '' : '∅'),
        reason: 'A4-T9 : le disque doit rester lisible');

    // ── 4. AUCUN apprentissage : les 10 éléments du périmètre sont intacts ─
    final diffs = _EtatIA.differences(avant, apres);
    expect(diffs, isEmpty,
        reason: _EtatIA.rapport(
            'A4-T9 : archivage d\'un résultat hors mémoire', avant, apres));

    // ── 5. AUCUNE écriture des clés du SERVICE (l.3397-3398 l\'exige) ────
    expect(apres.disqueService, avant.disqueService,
        reason: 'A4-T9 : AUCUNE des 10 clés du service ne doit être réécrite. '
            'Un diff global ne saurait pas distinguer une écriture d\'archive '
            '(légitime) d\'une écriture du service (interdite)');
    expect(prefs.getString('ia_poids_v3'), poidsDisqueAvant,
        reason: 'A4-T9 : `_consignerResultatEnArchive` ne doit PAS appeler '
            '`_save()` — ia_poids_v3 doit être inchangé');
    expect(prefs.getString('ia_seuils_v1'), seuilsDisqueAvant,
        reason: 'A4-T9 : ia_seuils_v1 doit être inchangé');
    expect(prefs.getStringList('ia_journal_v2')?.toString(), journalDisqueAvant,
        reason: 'A4-T9 : le journal ne doit recevoir aucune entrée');

    // ── 6. Compteurs du service inchangés ────────────────────────────────
    expect(svc.poids.nbMisesAJour, 137,
        reason: 'A4-T9 : nbMisesAJour ne doit PAS bouger');
    expect(svc.journal.length, 1,
        reason: 'A4-T9 : journal en mémoire inchangé');
    expect(archive.nbPredictionsDistinctes, nbDistinctesAvant,
        reason: 'A4-T9 : aucune nouvelle course distincte inventée');

    // ── 7. IDEMPOTENCE : un second appel identique ne crée rien ──────────
    final nbApres1 = archive.nbVersions(cleAbsente);
    await svc.enregistrerResultat(
      courseKey: cleAbsente,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
      cotesPmuParNumero: const <String, double>{'1': 2.2, '2': 5.0, '3': 9.0},
    );
    expect(archive.nbVersions(cleAbsente), nbApres1,
        reason: 'A4-T9 : un second appel identique ne doit PAS ajouter de '
            'version (garde `p.resultatsReels` l.3419) : '
            '$nbApres1 → ${archive.nbVersions(cleAbsente)}');
    expect(_EtatIA.differences(apres, _EtatIA.prendre(prefs)), isEmpty,
        reason: 'A4-T9 : le second appel ne doit rien muer non plus');

    // ── 8. Aucune version archivée en attente d'écriture ─────────────────
    expect(archive.nbEvictionsNonArchivees, 0,
        reason: 'A4-T9 : la file d\'évictions doit être vidée après persistance');
    expect(nbVersionsArchiveesAvant, greaterThan(0),
        reason: 'TÉMOIN : l\'archive contenait déjà des versions avant l\'appel');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T10 — DONNÉES INSUFFISANTES POUR LE GRADIENT PRINCIPAL
  //
  //  Deux comportements à DISTINGUER (arbitrage : « ne jamais déclarer
  //  l'apprentissage injustifié au seul motif que moins de 10 résultats
  //  existent ») :
  //    (a) aucune analyse nouvelle → RIEN ne doit bouger, et surtout le
  //        repli `_apprendreReglesBase` ne doit pas être déclenché ;
  //    (b) un VRAI nouveau résultat à 9 courses → le repli est LÉGITIME :
  //        il apprend (nbMisesAJour++, entrée journal `regles`).
  //
  //  Le seuil est `avecScores.length < 3 || nbAvecResultat < 10` (l.3676).
  //  Avec 8 puis 9 courses résolues, on est dans la branche « poids figés —
  //  apprentissage par règles de base uniquement ».
  // ═════════════════════════════════════════════════════════════════════════
  test('A4-T10a — moins de 10 résultats SANS nouveau résultat : aucune '
      'mutation, et le repli « règles de base » n\'est PAS déclenché',
      () async {
    final svc = IaMemoryService.instance;
    final jour = DateTime.now().subtract(const Duration(days: 1));
    final jourCourse = DateTime(jour.year, jour.month, jour.day, 14, 30);

    // 8 pronostics TOUS résolus : aTraiter est vide et nbAvecResultat = 8 < 10.
    final pronostics = <IaPronostic>[
      for (var i = 1; i <= 8; i++) _pronosticResolu(i, jourCourse),
    ];
    final prefs = await _monter(pronostics, jourCourse);

    // ── TÉMOINS : on est bien dans la zone « données insuffisantes » ──────
    expect(svc.pronosticsAvecResultat.length, 8,
        reason: 'TÉMOIN : 8 résultats < 10 ⇒ branche `_apprendreReglesBase`');
    expect(
        svc.pronosticsAvecResultat.where((p) => p.scoresCriteres.isNotEmpty).length,
        8,
        reason: 'TÉMOIN : les 8 portent des scoresCriteres, sinon '
            '`avecScores.length < 3` sortirait avant même le repli');
    expect(
        svc.pronosticsAvecResultat
            .map((p) => p.varianceScores!)
            .toSet()
            .length,
        8,
        reason: 'TÉMOIN : 8 variances DISTINCTES ⇒ `_mettreAJourCalibration` '
            'franchirait l.4143 et l.4149 — c\'est bien la garde '
            '`nbNouveauxResultats > 0` qui protège, pas un retour anticipé');
    expect(svc.poids.nbMisesAJour, 137, reason: 'TÉMOIN : poids non triviaux');
    expect(svc.journal.length, 1, reason: 'TÉMOIN : journal initial = 1 entrée');
    expect(prefs.getString('ia_precision_v2'), isNull,
        reason: 'TÉMOIN : chemin de réinjection l.4643 réellement parcouru');

    final avant = _EtatIA.prendre(prefs);
    final avantJournalMethodes =
        svc.journal.map((e) => e.methode).toList()..sort();
    final resultat = await svc.analyseJourneeComplete(date: jour);
    final apres = _EtatIA.prendre(prefs);
    final apresJournalMethodes =
        svc.journal.map((e) => e.methode).toList()..sort();

    // ignore: avoid_print
    print('[A4-T10a] succes=${resultat.succes} '
        'nbNouveauxResultats=${resultat.nbNouveauxResultats} '
        'nbCoursesAnalysees=${resultat.nbCoursesAnalysees} '
        'erreurs=${resultat.erreurs}');
    // ignore: avoid_print
    print('[A4-T10a] nbMisesAJour ${avant.nbMisesAJour} → ${apres.nbMisesAJour} '
        '| journal ${json.decode(avant.journal).length} → '
        '${json.decode(apres.journal).length}');

    // ── TÉMOIN : 0 nouveau résultat, l'analyse a bien abouti ─────────────
    expect(resultat.succes, isTrue,
        reason: 'TÉMOIN : l\'analyse doit aboutir sans exception masquée');
    expect(resultat.nbNouveauxResultats, 0,
        reason: 'TÉMOIN DÉCISIF : aucun nouveau résultat officiel');
    expect(resultat.nbCoursesAnalysees, 8,
        reason: 'TÉMOIN : les 8 courses déjà traitées sont comptées');
    expect(resultat.erreurs, isEmpty, reason: 'TÉMOIN : chemin nominal');

    // ── Aucune mutation IA (mémoire ET disque) ───────────────────────────
    expect(_EtatIA.differences(avant, apres), isEmpty,
        reason: _EtatIA.rapport(
            'A4-T10a : moins de 10 résultats, 0 nouveau résultat',
            avant,
            apres));

    // ── Le repli « règles de base » n'a PAS été déclenché ─────────────────
    expect(apres.nbMisesAJour, avant.nbMisesAJour,
        reason: 'A4-T10a : `_apprendreReglesBase` incrémente nbMisesAJour '
            '(l.4310). S\'il n\'a pas bougé, le repli n\'a pas tourné');
    expect(json.decode(apres.journal).length, json.decode(avant.journal).length,
        reason: 'A4-T10a : `_apprendreReglesBase` insère une entrée '
            '`methode: "regles"` (l.4358). Le journal doit être inchangé');

    // ⚠️ MESURE DES ENTRÉES NOUVELLES, pas de leur présence globale.
    //    La graine contient DÉJÀ une entrée `methode: "gradient"`
    //    (_journalInitial, l.199) : un `any(...) == isFalse` sur le journal
    //    complet serait faux par construction et ne mesurerait rien.
    //    On compare donc la MULTISET des méthodes avant/après.
    // ⚠️ MESURE DES ENTRÉES NOUVELLES, pas de leur présence globale.
    //    La graine contient DÉJÀ une entrée `methode: "gradient"`
    //    (_journalInitial, l.199) : un `any(...) == isFalse` sur le journal
    //    complet serait faux par construction et ne mesurerait rien.
    //    On compare donc la MULTISET des méthodes avant/après.
    expect(avantJournalMethodes, contains('gradient'),
        reason: 'TÉMOIN : la graine contient bien une entrée `gradient` — '
            'sans ce témoin, l\'assertion « aucune nouvelle entrée » '
            'pourrait passer sur un journal vide');

    final nouvellesMethodes = List<String>.from(avantJournalMethodes);
    for (final e in apresJournalMethodes) {
      nouvellesMethodes.remove(e); // retire une occurrence identique
    }
    // ignore: avoid_print
    print('[A4-T10a] méthodes avant=$avantJournalMethodes | entrées nouvelles='
        '$nouvellesMethodes');

    expect(nouvellesMethodes, isEmpty,
        reason: 'A4-T10a : AUCUNE entrée de journal ne doit être AJOUTÉE à '
            'zéro nouveau résultat. Entrées nouvelles mesurées : '
            '$nouvellesMethodes (gradient = l.3937, discipline_gradient = '
            'l.4123, regles = l.4358)');
  });

  test('A4-T10b — moins de 10 résultats AVEC un vrai nouveau résultat : '
      'le repli « règles de base » apprend LÉGITIMEMENT', () async {
    final svc = IaMemoryService.instance;
    final jour = DateTime.now().subtract(const Duration(days: 1));
    final jourCourse = DateTime(jour.year, jour.month, jour.day, 14, 30);

    // 8 résolus + 1 en attente = 9 après enregistrement : toujours < 10.
    final pronostics = <IaPronostic>[
      for (var i = 1; i <= 8; i++) _pronosticResolu(i, jourCourse),
      _pronosticEnAttente(9, jourCourse),
    ];
    final prefs = await _monter(pronostics, jourCourse);

    expect(svc.pronosticsAvecResultat.length, 8,
        reason: 'TÉMOIN : 8 résolus avant le forçage');
    final cleNeuf = _courseKey(9, jourCourse);
    expect(svc.getPronostic(cleNeuf)?.resultatsReels, isFalse,
        reason: 'TÉMOIN : la course 9 n\'a pas de résultat');

    final avant = _EtatIA.prendre(prefs);

    // ── VRAI nouveau résultat officiel (chemin l.3380-3382, inchangé) ────
    await svc.enregistrerResultat(
      courseKey: cleNeuf,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
      cotesPmuParNumero: const <String, double>{'1': 2.2, '2': 5.0, '3': 9.0},
    );

    final apres = _EtatIA.prendre(prefs);

    // ignore: avoid_print
    print('[A4-T10b] résolus=${svc.pronosticsAvecResultat.length} '
        'nbMisesAJour ${avant.nbMisesAJour} → ${apres.nbMisesAJour} '
        'journal ${json.decode(avant.journal).length} → '
        '${json.decode(apres.journal).length}');

    // ── TÉMOIN : on est bien resté sous le seuil de 10 ───────────────────
    expect(svc.pronosticsAvecResultat.length, 9,
        reason: 'TÉMOIN : 9 résultats < 10 ⇒ branche repli `_apprendreReglesBase`');

    // ── L'apprentissage a EU LIEU (9 < 10 n'est PAS une raison de ne rien
    //    apprendre — arbitrage T10) ────────────────────────────────────────
    expect(apres.nbMisesAJour, greaterThan(avant.nbMisesAJour),
        reason: 'A4-T10b : `_apprendreReglesBase` doit incrémenter '
            'nbMisesAJour (l.4310) : ${avant.nbMisesAJour} → '
            '${apres.nbMisesAJour}. Sinon le repli serait cassé');
    expect(json.decode(apres.journal).length,
        greaterThan(json.decode(avant.journal).length),
        reason: 'A4-T10b : une entrée de journal doit être ajoutée par le repli');
    expect(
        svc.journal.any((e) => e.methode == 'regles'),
        isTrue,
        reason: 'A4-T10b : l\'entrée doit porter `methode: "regles"` — '
            'preuve que c\'est bien le repli qui a appris '
            '(méthodes présentes : '
            '${svc.journal.map((e) => e.methode).toSet()})');

    // ── L'apprentissage est PERSISTÉ, pas seulement en mémoire ───────────
    expect(apres.poidsDisque, isNot(avant.poidsDisque),
        reason: 'A4-T10b : le nouvel état appris doit être écrit sur le disque '
            '(ia_poids_v3)');
    expect(apres.pronostics, isNot(avant.pronostics),
        reason: 'A4-T10b : le pronostic 9 doit être marqué résolu');

    // ── Le résultat est bien enregistré (pas d\'apprentissage à vide) ────
    final p9 = svc.getPronostic(cleNeuf);
    expect(p9?.resultatsReels, isTrue,
        reason: 'A4-T10b : la course 9 doit être résolue');
    expect(p9?.arriveeReelle, const <int>[1, 2, 3, 4, 5],
        reason: 'A4-T10b : l\'arrivée officielle est conservée');
    expect(p9?.rangFavoriIaDansArrivee, 1,
        reason: 'A4-T10b : le favori IA (n°1) est 1er de l\'arrivée');
    expect(p9?.scorePerformance, isNotNull,
        reason: 'A4-T10b : le score de performance est calculé');

    // ── Et la répétition d\'analyse, ensuite, ne doit plus rien changer ──
    final e1 = _EtatIA.prendre(prefs);
    final r = await svc.analyseJourneeComplete(date: jour);
    final e2 = _EtatIA.prendre(prefs);
    expect(r.nbNouveauxResultats, 0,
        reason: 'TÉMOIN : le résultat vient d\'être consommé, plus rien de neuf');
    expect(_EtatIA.differences(e1, e2), isEmpty,
        reason: _EtatIA.rapport(
            'A4-T10b : répétition après apprentissage légitime', e1, e2));
  });
}
