// ═══════════════════════════════════════════════════════════════════════════
//  A4 — NON-RÉGRESSION DES POIDS ET SEUILS
//
//  ⚠️  FICHIER DE TEST uniquement. Aucune modification de lib/.
//      Aucun mécanisme de production n'est adapté pour faciliter ce test.
//
//  PHASE 2 — PREMIER TEST AUTORISÉ : A4-T8
//  Objet : un nouvel appel à `enregistrerResultat()` pour une course dont le
//  résultat est DÉJÀ enregistré ne doit déclencher aucun apprentissage et ne
//  doit modifier aucun état IA.
//
//  ── PÉRIMÈTRE DE PROTECTION (arbitrage utilisateur) ───────────────────────
//  Sont protégés et donc comparés, au sens strict :
//    • les 19 poids ;
//    • les poids par discipline ;
//    • la calibration ;
//    • les indices (`poidsIndices`) ;
//    • le dernier gradient ;
//    • le nombre de mises à jour ;
//    • les corrélations ;
//    • les 8 seuils ;
//    • les ELO.
//
//  ── POINT TECHNIQUE DÉCISIF : RENDRE LE TEST DISCRIMINANT ─────────────────
//  Le second appel est refusé par la garde `if (p.resultatsReels) return;`
//  (ia_memory_service.dart:3278), donc le code ne doit RIEN faire. Un test
//  qui se contenterait de constater « rien n'a bougé » pourrait passer pour
//  une mauvaise raison : si le gradient était atteint malgré la garde, il
//  sortirait silencieusement par `_apprendreReglesBase` → `if (nb < 3) return;`
//  (l.4237) dès qu'il y a moins de 3 résultats, et « rien n'aurait bougé »
//  quand même.
//
//  Le montage sème donc :
//    • 12 pronostics DÉJÀ RÉSOLUS, avec `scoresCriteres` complets, et des
//      `rangFavoriIaDansArrivee` tel que `tauxGagne > 0.38` (50 %) →
//      `_apprendreReglesBase` modifierait forme/cote/jockey si elle était
//      atteinte ;
//    • 2 pronostics NON résolus, dont la course cible du second appel.
//
//  Ainsi les trois sorties silencieuses sont neutralisées :
//    `avecScores.length < 3` → faux (12 ≥ 3)
//    `nbAvecResultat < 10`  → faux (12 ≥ 10)
//    `_apprendreReglesBase` : `nb < 3` → faux (12 ≥ 3)
//  Si la garde l.3278 tombait, `_poids` changerait et le test ÉCHOUERAIT.
//
//  ── PRÉCAUTIONS DE MONTAGE (leçons des tests v4/v5 et A6) ─────────────────
//    • `ia_precision_migrated_v3: true` est semé DÈS LE DÉPART. Sinon `_load()`
//      appellerait `_recalculerPrecisionParTypeDepuisPronostics()` (l.2363),
//      qui fait un `_save()` (l.5617) réécrivant `ia_poids_v3`/`ia_seuils_v1`.
//      Ce serait du bruit « niveau C » (sauvegarde de valeurs inchangées).
//    • Tout est préparé dans le CORPS du test, jamais dans un `setUp()` :
//      contrainte de zone FakeAsync documentée en A6 (les singletons
//      `static final` chaînent leurs écritures dans la zone du premier test).
//    • Aucun appel réseau : `enregistrerResultat` ne fait que lire
//      SharedPreferences, et le second appel retourne avant tout calcul.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart'; // EloScore
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Outils de données
// ───────────────────────────────────────────────────────────────────────────

/// `courseKey` au format accepté par `IaMemoryService.dateDepuisCourseKey` :
/// `R{nRéunion}C{nCourse}_YYYY-MM-DD`.
String _cleDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _courseKey(int numCourse, DateTime d) => 'R1C${numCourse}_${_cleDate(d)}';

/// Les 19 critères, dans l'ordre A→S (ia_memory_models.dart:11-33).
/// Documentaire : sert de référence de lecture, les scores sont construits
/// explicitement dans [_scores].
// ignore: unused_element
const List<String> _criteres = <String>[
  'forme', 'gains', 'record', 'cote', 'constance',
  'victoires', 'discipline', 'distSpec', 'jockey', 'repos',
  'hippo', 'entraineur', 'elo', 'terrain', 'divergence',
  'poidsRel', 'progression', 'mouvCote', 'placeDepart',
];

/// `ScoresCriteres` volontairement NON neutres : chaque critère porte une
/// valeur distincte et déterministe, pour que toute modification d'un poids
/// se traduise par un écart mesurable dans `scoresCriteres`.
ScoresCriteres _scores(int graine) => ScoresCriteres(
      forme:       10.0 + graine * 1.0,
      gains:       20.0 + graine * 1.0,
      record:      30.0 + graine * 1.0,
      cote:        40.0 + graine * 1.0,
      constance:   50.0 + graine * 1.0,
      victoires:   60.0 + graine * 1.0,
      discipline:  70.0 + graine * 1.0,
      distSpec:    15.0 + graine * 1.0,
      jockey:      25.0 + graine * 1.0,
      repos:       35.0 + graine * 1.0,
      hippo:       45.0 + graine * 1.0,
      entraineur:  55.0 + graine * 1.0,
      elo:         65.0 + graine * 1.0,
      terrain:     75.0 + graine * 1.0,
      divergence:  18.0 + graine * 1.0,
      poidsRel:    28.0 + graine * 1.0,
      progression: 38.0 + graine * 1.0,
      mouvCote:    48.0 + graine * 1.0,
      placeDepart: 58.0 + graine * 1.0,
    );

/// Pronostic DÉJÀ RÉSOLU, avec scores de critères exploitables.
///
/// `rangFavoriIaDansArrivee = 1` pour tous ⇒ `tauxGagne = 1.0 > 0.38` :
/// si `_apprendreReglesBase` était atteinte, elle modifierait les poids
/// (l.4280-4282). C'est exactement ce que ce test doit interdire.
IaPronostic _pronosticResolu(int numCourse, DateTime jour) => IaPronostic(
      courseKey: _courseKey(numCourse, jour),
      nomCourse: 'PRIX A4 N°$numCourse',
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
      varianceScores: 66.6666,
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

/// Pronostic NON résolu : c'est la course CIBLE du second appel.
IaPronostic _pronosticNonResolu(int numCourse, DateTime jour) => IaPronostic(
      courseKey: _courseKey(numCourse, jour),
      nomCourse: 'PRIX A4 N°$numCourse',
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
      typePariConseille: 'Simple Placé',
      tauxReussiteAuMoment: 38.0,
      precisionIA: 51.0,
      favoriIaNom: 'CHEVAL 1',
      coteFavoriPmu: 4.2,
    );

/// Poids volontairement ÉLOIGNÉS des valeurs d'usine, pour qu'un retour
/// accidentel à `IaPoidsAdaptatifs.defaut()` (l.2202 / l.2107) soit détecté.
/// Modèle repris de v5_backup_restore_test.dart:163-198.
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

/// Seuils volontairement ÉLOIGNÉS des constantes de classe
/// (ia_memory_service.dart:7436-7443).
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

/// Journal d'apprentissage pré-existant : sa LONGUEUR et son CONTENU sont
/// comparés. Une entrée ajoutée prouverait qu'un chemin d'apprentissage
/// s'est exécuté (`_apprendreReglesBase` l.4355, `_apprendreParDiscipline`
/// l.4114, gradient l.1076).
List<JournalEntree> _journalInitial(DateTime jour) => <JournalEntree>[
      JournalEntree(
        date: jour,
        nomCourse: 'PRIX JOURNAL A4',
        discipline: 'Trot Attelé',
        nbCoursesAnalysees: 12,
        diagnostic: 'Entrée pré-existante — sert de référence de non-régression',
        avant: const <String, double>{'forme': 0.25, 'elo': 0.05},
        apres: const <String, double>{'forme': 0.2510, 'elo': 0.0490},
        scorePerf: 61.0,
        methode: 'gradient',
      ),
    ];

/// Clé ELO réelle, reconstruite comme `EloService` (v4_d1_recreation_test.dart:38).
String _cleElo(String nom, String discipline) {
  final nomNorm = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  return '$nomNorm|${EloService.normaliserDiscipline(discipline)}';
}

/// Peuple SharedPreferences exactement aux clés lues par `_load()`
/// (ia_memory_service.dart:96-113).
Map<String, Object> _prefs({
  required List<IaPronostic> pronostics,
  required DateTime jour,
}) =>
    <String, Object>{
      // ★ Sans ce flag, `_load()` déclencherait le recalcul + `_save()` l.5617.
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode(_poidsNonTriviaux()),
      'ia_seuils_v1': json.encode(_seuilsNonTriviaux().toJson()),
      'ia_pronostics_v2':
          pronostics.map((p) => json.encode(p.toJson())).toList(),
      'ia_journal_v2':
          _journalInitial(jour).map((j) => json.encode(j.toJson())).toList(),
    };

// ───────────────────────────────────────────────────────────────────────────
//  Snapshots — principe de v4_d1_recreation_test.dart:709-744
//
//  ⚠️ On sérialise. `poids` et `seuilsConfiance` rendent la RÉFÉRENCE VIVE
//     (ia_memory_service.dart:252 et 974) : comparer les objets directement
//     comparerait l'objet à lui-même et le test passerait toujours.
// ───────────────────────────────────────────────────────────────────────────

class _Snapshots {
  final String poids;
  final String seuils;
  final String elo;
  final String journal;
  final String pronostics;
  final int nbMisesAJour;
  final String poidsDisque;
  final String seuilsDisque;

  const _Snapshots({
    required this.poids,
    required this.seuils,
    required this.elo,
    required this.journal,
    required this.pronostics,
    required this.nbMisesAJour,
    required this.poidsDisque,
    required this.seuilsDisque,
  });

  static _Snapshots prendre(SharedPreferences prefs) {
    final svc = IaMemoryService.instance;
    return _Snapshots(
      poids: json.encode(svc.poids.toJson()),
      seuils: json.encode(svc.seuilsConfiance.toJson()),
      elo: json.encode(EloService.instance.exporterPourBackup()),
      journal: json.encode(svc.journal.map((j) => j.toJson()).toList()),
      pronostics: json.encode(svc.pronostics.map((p) => p.toJson()).toList()),
      nbMisesAJour: svc.poids.nbMisesAJour,
      poidsDisque: prefs.getString('ia_poids_v3') ?? '',
      seuilsDisque: prefs.getString('ia_seuils_v1') ?? '',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  TESTS
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Aucun `setUp()` enregistré : toute la préparation est dans le corps du
  // test (contrainte de zone FakeAsync documentée en A6).

  test('A4-T8 — second enregistrerResultat sur une course déjà résolue : '
      'aucun apprentissage, aucun état IA modifié', () async {
    final svc = IaMemoryService.instance;
    final jour = DateTime.now().subtract(const Duration(days: 1));

    // ── 1. Données initiales : 12 résolus + 2 non résolus ─────────────────
    final resolus = <IaPronostic>[
      for (var i = 1; i <= 12; i++) _pronosticResolu(i, jour),
    ];
    final cible = _pronosticNonResolu(13, jour);
    final prefsMap = _prefs(
      pronostics: <IaPronostic>[...resolus, cible],
      jour: jour,
    );
    SharedPreferences.setMockInitialValues(prefsMap);
    final prefs = await SharedPreferences.getInstance();

    // ── 2. ELO non triviaux ────────────────────────────────────────────────
    await EloService.instance.importerDepuisBackup(<String, dynamic>{
      for (final e in <String, double>{
        'CHEVAL 1': 1900.0,
        'CHEVAL 2': 1700.0,
        'CHEVAL 3': 1500.0,
      }.entries)
        _cleElo(e.key, 'Trot Attelé'):
            EloScore(nomCheval: e.key, rating: e.value, nbCourses: 10).toJson(),
    });

    // ── 3. Chargement ──────────────────────────────────────────────────────
    await svc.recharger();

    // ═══ TÉMOINS : le montage est réellement discriminant ═════════════════
    expect(svc.pronosticsAvecResultat.length, 12,
        reason: 'TÉMOIN : 12 pronostics résolus. Sans cela, le gradient '
            'sortirait par `nbAvecResultat < 10` (l.3676) et le test ne '
            'prouverait rien');
    expect(
        svc.pronosticsAvecResultat
            .where((p) => p.scoresCriteres.isNotEmpty)
            .length,
        12,
        reason: 'TÉMOIN : 12 pronostics avec scores de critères. Sans cela, '
            'le gradient sortirait par `avecScores.length < 3` (l.3676)');
    expect(svc.journal.length, 1,
        reason: 'TÉMOIN : le journal pré-existant est bien chargé');
    expect(svc.poids.nbMisesAJour, 137,
        reason: 'TÉMOIN : les poids non triviaux du disque sont chargés, pas '
            'les valeurs d\'usine');
    expect(svc.poids.calibrationScore, closeTo(68.3125, 1e-12),
        reason: 'TÉMOIN : la calibration du disque est préservée');
    expect(json.encode(svc.poids.correlations),
        json.encode(<String, double>{'forme|cote': 0.4125, 'elo|gains': -0.1875}),
        reason: 'TÉMOIN : les corrélations font partie du périmètre protégé');
    expect(svc.poids.poidsParDiscipline['TROT_ATTELE']?['forme'], 0.30,
        reason: 'TÉMOIN : les poids par discipline font partie du périmètre');
    expect(svc.poids.poidsIndices.poidsCriteres, closeTo(0.4321, 1e-12),
        reason: 'TÉMOIN : les indices font partie du périmètre');
    expect(svc.seuilsConfiance.seuilSimpleGagnant, 83.5,
        reason: 'TÉMOIN : les seuils non triviaux sont chargés');
    expect(EloService.instance.nbChevauxSuivis, 3,
        reason: 'TÉMOIN : les 3 ratings ELO sont chargés');
    expect(svc.getPronostic(_courseKey(13, jour))?.resultatsReels, isFalse,
        reason: 'TÉMOIN : la course cible n\'est PAS déjà résolue');

    // ── 4. Snapshots AVANT le second appel ────────────────────────────────
    final avant = _Snapshots.prendre(prefs);
    final cleCible = _courseKey(13, jour);

    // ── 5. PREMIER appel : enregistre le résultat de la course cible ───────
    await svc.enregistrerResultat(
      courseKey: cleCible,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
      cotesPmuParNumero: const <String, double>{
        '1': 4.2, '2': 6.1, '3': 11.0,
      },
    );

    final apresPremier = svc.getPronostic(cleCible)!;
    expect(apresPremier.resultatsReels, isTrue,
        reason: 'TÉMOIN : le premier appel a bien enregistré le résultat');
    expect(apresPremier.arriveeReelle, const <int>[1, 2, 3, 4, 5],
        reason: 'TÉMOIN : l\'arrivée enregistrée est exactement celle fournie');

    // ── 6. Snapshots de référence : APRÈS le premier appel ────────────────
    //      C'est l'état « résultat déjà enregistré » que le second appel
    //      doit laisser STRICTEMENT intact.
    final reference = _Snapshots.prendre(prefs);

    // Le premier appel a pu légitimement déclencher un apprentissage : on ne
    // l'exige pas, on le CONSTATE, sans jamais l'utiliser comme prétexte.
    // ignore: avoid_print
    print('  [A4-T8] après 1er appel : nbMisesAJour=${reference.nbMisesAJour} '
        '(avant=${avant.nbMisesAJour}) journal=${svc.journal.length} '
        '(avant=${json.decode(avant.journal).length})');

    // ── 7. SECOND appel : exactement la même course, même résultat ────────
    await svc.enregistrerResultat(
      courseKey: cleCible,
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
      cotesPmuParNumero: const <String, double>{
        '1': 4.2, '2': 6.1, '3': 11.0,
      },
    );

    // ── 8. Comparaison STRICTE avant/après le second appel ────────────────
    final apres = _Snapshots.prendre(prefs);

    expect(apres.poids, reference.poids,
        reason: 'A4-T8 : `poids.toJson()` COMPLET doit être identique — '
            '19 poids + poids par discipline + calibration + indices + '
            'dernier gradient + nbMisesAJour + corrélations');
    expect(apres.seuils, reference.seuils,
        reason: 'A4-T8 : `seuilsConfiance.toJson()` COMPLET doit être '
            'identique — les 8 seuils');
    expect(apres.elo, reference.elo,
        reason: 'A4-T8 : les ratings ELO ne doivent pas être réécrits');
    expect(apres.journal, reference.journal,
        reason: 'A4-T8 : le journal d\'apprentissage COMPLET doit être '
            'identique — aucune entrée ajoutée, aucune entrée modifiée');
    expect(apres.nbMisesAJour, reference.nbMisesAJour,
        reason: 'A4-T8 : `nbMisesAJour` ne doit pas s\'incrémenter');
    expect(apres.poidsDisque, reference.poidsDisque,
        reason: 'A4-T8 : `ia_poids_v3` sur disque ne doit pas changer de '
            'CONTENU (une simple réécriture à l\'identique est ici exclue, '
            'car le second appel sort avant tout `_save()`)');
    expect(apres.seuilsDisque, reference.seuilsDisque,
        reason: 'A4-T8 : `ia_seuils_v1` sur disque ne doit pas changer');

    // ── 9. Les pronostics eux-mêmes ne doivent pas bouger ─────────────────
    expect(apres.pronostics, reference.pronostics,
        reason: 'A4-T8 : aucun pronostic modifié — ni la course cible, ni '
            'les 12 courses résolues');
    expect(svc.pronosticsCount, 13,
        reason: 'A4-T8 : 12 pronostics résolus + la course cible = 13. '
            'Aucune course créée ni supprimée par le second appel');
    expect(svc.pronosticsAvecResultat.length, 13,
        reason: 'A4-T8 : 12 + la course cible = 13 résolus. Le second appel '
            'ne doit pas en ajouter un 14e');

    // ── 10. L'arrivée reste celle du premier appel, non altérée ───────────
    final final13 = svc.getPronostic(cleCible)!;
    expect(final13.arriveeReelle, const <int>[1, 2, 3, 4, 5],
        reason: 'A4-T8 : l\'arrivée officielle n\'est pas réécrite');
    expect(final13.dateResultat, apresPremier.dateResultat,
        reason: 'A4-T8 : la date de résultat n\'est pas rafraîchie');
    expect(final13.scorePerformance, apresPremier.scorePerformance,
        reason: 'A4-T8 : le score de performance n\'est pas recalculé');
    expect(final13.precisionIA, apresPremier.precisionIA,
        reason: 'A4-T8 : la précision du pronostic n\'est pas recalculée');
  });
}
