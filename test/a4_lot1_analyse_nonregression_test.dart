// ═══════════════════════════════════════════════════════════════════════════
//  A4 — LOT 1/2 — NON-RÉGRESSION : AUCUN APPRENTISSAGE SANS NOUVEAU RÉSULTAT
//
//  ⚠️  FICHIER DE TEST uniquement. Aucune modification de lib/.
//      Aucun mécanisme de production n'est adapté pour faciliter ces tests.
//      T8 (fichier a4_poids_seuils_nonregression_test.dart) est INCHANGÉ.
//
//  ── RÈGLE ABSOLUE (arbitrage utilisateur) ─────────────────────────────────
//  Lorsqu'aucun nouveau résultat officiel exploitable n'est disponible, aucun
//  paramètre d'apprentissage IA ne doit être modifié par une simple répétition
//  d'analyse. Périmètre protégé, comparé au sens strict :
//    • les 19 poids IA ;
//    • les poids par discipline ;
//    • calibrationScore ;
//    • correlations ;
//    • poidsIndices ;
//    • dernierGradient ;
//    • nbMisesAJour ;
//    • les huit seuils de confiance ;
//    • ELO ;
//    • le journal d'apprentissage.
//
//  Une sauvegarde de valeurs STRICTEMENT identiques reste autorisée et ne
//  constitue pas un échec : c'est la catégorie C (réécriture disque sans
//  changement de valeur). Seule une modification de VALEUR est un échec.
//
//  ── ORDRE D'EXÉCUTION ─────────────────────────────────────────────────────
//  Ce fichier est le premier livré du lot : il contient les deux détecteurs
//  prioritaires, T3 puis T4. Si l'un des deux observe une véritable
//  modification IA à zéro nouveau résultat, les autres scénarios du lot ne
//  doivent pas être exécutés (consigne utilisateur).
//
//  ── MONTAGE DISCRIMINANT (leçon décisive de T8) ───────────────────────────
//  Un test qui constate « rien n'a bougé » peut passer pour la MAUVAISE raison
//  si le chemin critique n'a jamais été atteint. Le montage arme donc
//  explicitement les trois mutateurs du chemin « 0 nouveau résultat » :
//
//   1. `analyseJourneeComplete` l.4979 appelle `_mettreAJourCalibration()`
//      HORS du `if (nbNouveauxResultats > 0)` (l.4947). Ses gardes l.4141
//      (`avecResultat < 5`) et l.4147 (`avecVariance < 5`) sont franchies :
//      13 pronostics résolus, tous porteurs de `varianceScores` et de
//      `scorePerformance`.
//      ⚠️ Les variances sont DISTINCTES (40 + 2·n) : sinon `_median` rend une
//      valeur égale à toutes les variances, `hautConfiance` est vide et la
//      méthode sort silencieusement par l.4153 sans rien modifier — le test
//      passerait alors sans avoir rien prouvé.
//
//   2. Le chemin `aTraiter.isEmpty` (l.4602) appelle `_mettreAJourPrecisionIA`
//      (l.4640) dès que la date n'est pas déjà présente dans
//      `historiqueComplet` du type concerné. `ia_precision_v2` n'est donc PAS
//      semé : `dejaPresent` est faux et le chemin est réellement parcouru.
//      ⚠️ Conséquence directe : `_seuils.ajusterSeuil` (l.5807) et
//      `_poids.poidsIndices.mettreAJourDepuisDeltas` (l.5858) sont atteints.
//
//   3. Le type de pari conseillé est renseigné (`Simple Gagnant`) et partagé
//      par les 13 pronostics : `nbParType` est non vide et `stat.nbTotal`
//      vaut 13 ≥ 3, condition exigée par l.5771 pour atteindre `ajusterSeuil`.
//
//  ── PRÉCAUTIONS DE MONTAGE ────────────────────────────────────────────────
//    • `ia_precision_migrated_v3: true` est semé DÈS LE DÉPART. Sinon `_load()`
//      appellerait `_recalculerPrecisionParTypeDepuisPronostics()` (l.2363),
//      qui fait un `_save()` (l.5617) réécrivant `ia_poids_v3`/`ia_seuils_v1`
//      avant toute mesure (bruit de catégorie C non contrôlé).
//    • Toute la préparation est dans le CORPS de chaque `test()` : contrainte
//      de zone documentée en A6.
//    • Aucun appel réseau : le chemin emprunté (`aTraiter` vide) ne franchit
//      jamais la récupération PMU de l.4650.
//    • Les pronostics sont datés d'un jour PASSÉ et la date est fournie
//      explicitement à `analyseJourneeComplete(date:)` : la sélection
//      l.4493-4495 est déterministe, indépendante de l'heure d'exécution.
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

/// `courseKey` au format accepté par `IaMemoryService` :
/// `R{nRéunion}C{nCourse}_YYYY-MM-DD`.
String _cleDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _courseKey(int numCourse, DateTime d) => 'R1C${numCourse}_${_cleDate(d)}';

/// `ScoresCriteres` volontairement NON neutres : chaque critère porte une
/// valeur distincte et déterministe.
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

/// Pronostic DÉJÀ RÉSOLU.
///
/// • `varianceScores` DISTINCTE selon `numCourse` (40 + 2·n) : indispensable
///   pour que `_mettreAJourCalibration` ne sorte pas par l.4153.
/// • `rangFavoriIaDansArrivee = 1` : `_estBonConseilParType('Simple Gagnant')`
///   rend `true`, donc `tauxReussite` vaut 100 % et `ajusterSeuil` est
///   réellement sollicité (delta = (30 − 100) × 0.015 = −1.05).
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
      varianceScores: 40.0 + numCourse * 2.0, // ← DISTINCTE, voir doc ci-dessus
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

/// Poids volontairement ÉLOIGNÉS des valeurs d'usine, pour qu'un retour
/// accidentel à `IaPoidsAdaptatifs.defaut()` (l.2202) soit détecté.
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

/// Clé ELO réelle, reconstruite comme `EloService` (v4_d1_recreation_test.dart:38).
String _cleElo(String nom, String discipline) {
  final nomNorm = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  return '$nomNorm|${EloService.normaliserDiscipline(discipline)}';
}

/// Peuple SharedPreferences exactement aux clés lues par `_load()`
/// (ia_memory_service.dart:96-113).
///
/// ⚠️ `ia_precision_v2` est volontairement ABSENT : `_precisionParType` reste
///    vide, `dejaPresent` est faux (l.4635-4636) et `_mettreAJourPrecisionIA`
///    (l.4640) est réellement exécutée.
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
//  États IA — copies SÉRIALISÉES, jamais des références mutables
//
//  `poids` (l.252) et `seuilsConfiance` (l.974) rendent la RÉFÉRENCE VIVE :
//  comparer les objets directement comparerait l'objet à lui-même.
// ───────────────────────────────────────────────────────────────────────────

class _EtatIA {
  /// Les 25 clés de `IaPoidsAdaptatifs.toJson()`
  /// (ia_memory_models.dart:790-810) : 19 critères + nbMisesAJour +
  /// calibrationScore + poidsParDiscipline + dernierGradient + poidsIndices +
  /// correlations.
  final Map<String, dynamic> poids;

  /// Les 8 seuils (ia_memory_service.dart:7480-7489).
  final Map<String, dynamic> seuils;

  final String elo;
  final String journal;
  final String pronostics;
  final int nbMisesAJour;
  final String poidsDisque;
  final String seuilsDisque;

  const _EtatIA({
    required this.poids,
    required this.seuils,
    required this.elo,
    required this.journal,
    required this.pronostics,
    required this.nbMisesAJour,
    required this.poidsDisque,
    required this.seuilsDisque,
  });

  static _EtatIA prendre(SharedPreferences prefs) {
    final svc = IaMemoryService.instance;
    return _EtatIA(
      poids: json.decode(json.encode(svc.poids.toJson())) as Map<String, dynamic>,
      seuils:
          json.decode(json.encode(svc.seuilsConfiance.toJson())) as Map<String, dynamic>,
      elo: json.encode(EloService.instance.exporterPourBackup()),
      journal: json.encode(svc.journal.map((j) => j.toJson()).toList()),
      pronostics: json.encode(svc.pronostics.map((p) => p.toJson()).toList()),
      nbMisesAJour: svc.poids.nbMisesAJour,
      poidsDisque: prefs.getString('ia_poids_v3') ?? '',
      seuilsDisque: prefs.getString('ia_seuils_v1') ?? '',
    );
  }

  /// Différentiel LISIBLE, clé par clé, entre deux états.
  /// Retourne une liste vide si les dix éléments du périmètre sont identiques.
  static List<String> differences(_EtatIA avant, _EtatIA apres) {
    final d = <String>[];

    // 1. `poids.toJson()` complet, clé par clé — couvre les 19 poids, les poids
    //    par discipline, calibrationScore, correlations, poidsIndices,
    //    dernierGradient et nbMisesAJour.
    for (final k in <String>{...avant.poids.keys, ...apres.poids.keys}) {
      final a = json.encode(avant.poids[k]);
      final b = json.encode(apres.poids[k]);
      if (a != b) d.add('poids.toJson()["$k"] : $a → $b');
    }

    // 2. Les 8 seuils, clé par clé.
    for (final k in <String>{...avant.seuils.keys, ...apres.seuils.keys}) {
      final a = json.encode(avant.seuils[k]);
      final b = json.encode(apres.seuils[k]);
      if (a != b) d.add('seuilsConfiance.toJson()["$k"] : $a → $b');
    }

    // 3 à 5.
    if (avant.elo != apres.elo) d.add('ELO exporté : modifié');
    if (avant.journal != apres.journal) {
      d.add('journal d\'apprentissage : ${avant.journal} → ${apres.journal}');
    }
    if (avant.nbMisesAJour != apres.nbMisesAJour) {
      d.add('nbMisesAJour : ${avant.nbMisesAJour} → ${apres.nbMisesAJour}');
    }

    // 6 et 7 — contenu PERSISTANT (pas la simple existence des clés).
    if (avant.poidsDisque != apres.poidsDisque) {
      d.add('disque ia_poids_v3 : CONTENU modifié');
    }
    if (avant.seuilsDisque != apres.seuilsDisque) {
      d.add('disque ia_seuils_v1 : CONTENU modifié');
    }

    // 8 — pronostics : détecte un double traitement (precisionIA recalculée
    //     l.5881, dateResultat rafraîchie, arrivée réécrite…).
    if (avant.pronostics != apres.pronostics) {
      d.add('pronostics : liste modifiée (double traitement ou recalcul)');
    }

    return d;
  }

  /// Rapport multi-lignes destiné au `reason` d'une assertion.
  static String rapport(String titre, _EtatIA avant, _EtatIA apres) {
    final d = differences(avant, apres);
    if (d.isEmpty) return '$titre : AUCUNE différence sur le périmètre protégé.';
    return '$titre : ${d.length} MODIFICATION(S) RÉELLE(S) à zéro nouveau '
        'résultat —\n  ${d.join('\n  ')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  TESTS
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
//  PARTIE 2 — APRÈS CORRECTIF A4-T3
//
//  Trois garanties doivent être démontrées ensemble, sinon le correctif n'est
//  qu'un débranchement déguisé :
//    • T3-bis (positif)      : un NOUVEAU résultat déclenche toujours
//                              l'apprentissage ;
//    • T4 (répétition)       : deux analyses successives n'apprennent qu'une
//                              fois ;
//    • Réinjection historique: les statistiques sont toujours alimentées à
//                              zéro nouveau résultat, sans mutation IA et sans
//                              double comptage.
// ═══════════════════════════════════════════════════════════════════════════

/// Pronostic NON résolu, utilisé comme course cible du test positif.
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

/// Montage commun : graine + ELO + rechargement, dans le corps du test.
Future<SharedPreferences> _monter(List<IaPronostic> pronostics,
    DateTime jourCourse) async {
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
  await IaMemoryService.instance.recharger();
  return prefs;
}

/// `historiqueComplet` complet, sérialisé — détecte une absence d'alimentation
/// ET un double comptage.
String _historiqueComplet() {
  final svc = IaMemoryService.instance;
  final map = <String, dynamic>{
    for (final t in svc.precisionParType) t.typePari: t.historiqueComplet,
  };
  return json.encode(map);
}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Aucun `setUp()` enregistré : toute la préparation est dans le corps du test
  // (contrainte de zone FakeAsync documentée en A6).

  // ─────────────────────────────────────────────────────────────────────────
  //  T3 — Analyse d'une journée dont TOUS les résultats sont déjà connus :
  //       aucun nouveau résultat exploitable ⇒ aucun paramètre IA modifié.
  // ─────────────────────────────────────────────────────────────────────────
  test('A4-T3 — analyseJourneeComplete sans nouveau résultat : '
      'aucune modification des 19 poids, poids par discipline, calibration, '
      'corrélations, indices, dernier gradient, nbMisesAJour, 8 seuils, ELO, '
      'journal', () async {
    final svc = IaMemoryService.instance;
    final jour = DateTime.now().subtract(const Duration(days: 1));
    final jourCourse = DateTime(jour.year, jour.month, jour.day, 14, 30);

    // ── 1. Données initiales : 13 pronostics TOUS résolus ─────────────────
    final resolus = <IaPronostic>[
      for (var i = 1; i <= 13; i++) _pronosticResolu(i, jourCourse),
    ];
    SharedPreferences.setMockInitialValues(
      _prefs(pronostics: resolus, jour: jourCourse),
    );
    final prefs = await SharedPreferences.getInstance();

    // ── 2. ELO non triviaux, puis chargement ──────────────────────────────
    await EloService.instance.importerDepuisBackup(<String, dynamic>{
      for (final e in <String, double>{
        'CHEVAL 1': 1900.0,
        'CHEVAL 2': 1700.0,
        'CHEVAL 3': 1500.0,
      }.entries)
        _cleElo(e.key, 'Trot Attelé'):
            EloScore(nomCheval: e.key, rating: e.value, nbCourses: 10).toJson(),
    });
    await svc.recharger();

    // ── 3. TÉMOINS : le montage est réellement discriminant ───────────────
    expect(svc.pronosticsAvecResultat.length, 13,
        reason: 'TÉMOIN : 13 pronostics résolus. Sans cela, `aTraiter` ne '
            'serait pas vide et le chemin l.4602 ne serait pas parcouru');
    expect(
        svc.pronosticsAvecResultat.where((p) => p.varianceScores != null).length,
        13,
        reason: 'TÉMOIN : 13 variances non nulles. Sans cela, '
            '`_mettreAJourCalibration` sortirait par l.4147 sans rien prouver');
    expect(
        svc.pronosticsAvecResultat
            .map((p) => p.varianceScores!)
            .toSet()
            .length,
        13,
        reason: 'TÉMOIN : les 13 variances sont DISTINCTES. Avec des variances '
            'identiques, `_median` égale toutes les valeurs, `hautConfiance` '
            'est vide et la méthode sort silencieusement par l.4153');
    expect(svc.poids.nbMisesAJour, 137,
        reason: 'TÉMOIN : les poids non triviaux du disque sont chargés, pas '
            'les valeurs d\'usine');
    expect(svc.poids.calibrationScore, closeTo(68.3125, 1e-12),
        reason: 'TÉMOIN : la calibration du disque est préservée au chargement');
    expect(json.encode(svc.poids.correlations),
        json.encode(<String, double>{'forme|cote': 0.4125, 'elo|gains': -0.1875}),
        reason: 'TÉMOIN : les corrélations font partie du périmètre protégé');
    expect(svc.poids.poidsParDiscipline['TROT_ATTELE']?['forme'], 0.30,
        reason: 'TÉMOIN : les poids par discipline font partie du périmètre');
    expect(svc.poids.poidsIndices.poidsCriteres, closeTo(0.4321, 1e-12),
        reason: 'TÉMOIN : les indices font partie du périmètre');
    expect(svc.poids.dernierGradient['forme'], closeTo(0.0125, 1e-12),
        reason: 'TÉMOIN : le dernier gradient fait partie du périmètre');
    expect(svc.seuilsConfiance.seuilSimpleGagnant, 83.5,
        reason: 'TÉMOIN : les seuils non triviaux sont chargés');
    expect(svc.seuilsConfiance.seuilQuinte, 0.0,
        reason: 'TÉMOIN : le seuil Quinté vaut 0 dans la graine');
    expect(EloService.instance.nbChevauxSuivis, 3,
        reason: 'TÉMOIN : les 3 ratings ELO sont chargés');
    expect(svc.journal.length, 1,
        reason: 'TÉMOIN : le journal pré-existant est bien chargé');
    // `ia_precision_v2` absent ⇒ le chemin l.4640 sera réellement parcouru.
    expect(prefs.getString('ia_precision_v2'), isNull,
        reason: 'TÉMOIN : aucun historique de précision semé ⇒ `dejaPresent` '
            'sera faux et `_mettreAJourPrecisionIA` (l.4640) sera exécutée');

    // ── 4. Snapshot AVANT l'analyse ───────────────────────────────────────
    final avant = _EtatIA.prendre(prefs);

    // ── 5. Exécution réelle de l'analyse ──────────────────────────────────
    final resultat = await svc.analyseJourneeComplete(date: jour);

    // ── 6. TÉMOINS du résultat : le chemin « 0 nouveau résultat » a bien
    //       été parcouru, ce n'est pas un échec silencieux de l'analyse.
    // ignore: avoid_print
    print('[A4-T3] succes=${resultat.succes} '
        'nbNouveauxResultats=${resultat.nbNouveauxResultats} '
        'nbCoursesAnalysees=${resultat.nbCoursesAnalysees} '
        'nbSansResultat=${resultat.nbSansResultat} '
        'erreurs=${resultat.erreurs}');
    expect(resultat.succes, isTrue,
        reason: 'TÉMOIN : l\'analyse doit aboutir (aucune exception masquée)');
    expect(resultat.nbNouveauxResultats, 0,
        reason: 'TÉMOIN DÉCISIF : aucun nouveau résultat exploitable. '
            'C\'est LA condition de la règle absolue');
    expect(resultat.nbCoursesAnalysees, 13,
        reason: 'TÉMOIN : les 13 courses déjà traitées sont bien comptées '
            '(l.4934 : nbCoursesAnalysees += dejaResultat)');
    expect(resultat.erreurs, isEmpty,
        reason: 'TÉMOIN : aucune course en erreur, le chemin est nominal');

    // ── 7. Snapshot APRÈS, puis différentiel clé par clé ──────────────────
    final apres = _EtatIA.prendre(prefs);
    final diffs = _EtatIA.differences(avant, apres);
    // ignore: avoid_print
    print('[A4-T3] différences=${diffs.length}');
    for (final l in diffs) {
      // ignore: avoid_print
      print('  [A4-T3] $l');
    }

    expect(diffs, isEmpty,
        reason: _EtatIA.rapport(
            'A4-T3 : analyseJourneeComplete avec 0 nouveau résultat', avant, apres));
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  T3-bis — CONTRÔLE POSITIF. Indispensable : sans lui, un correctif qui
  //  débrancherait purement et simplement l'apprentissage passerait T3.
  // ─────────────────────────────────────────────────────────────────────────
  test('A4-T3-bis — analyseJourneeComplete AVEC un nouveau résultat : '
      'l\'apprentissage reste opérationnel', () async {
    final svc = IaMemoryService.instance;
    final jour = DateTime.now().subtract(const Duration(days: 1));
    final jourCourse = DateTime(jour.year, jour.month, jour.day, 14, 30);

    // 12 résolus + 1 EN ATTENTE : c'est le chemin nominal (aTraiter non vide).
    final pronostics = <IaPronostic>[
      for (var i = 1; i <= 12; i++) _pronosticResolu(i, jourCourse),
      _pronosticEnAttente(13, jourCourse),
    ];
    final prefs = await _monter(pronostics, jourCourse);

    expect(svc.pronosticsAvecResultat.length, 12,
        reason: 'TÉMOIN : 12 résolus avant l\'analyse');
    expect(svc.getPronostic(_courseKey(13, jourCourse))?.resultatsReels, isFalse,
        reason: 'TÉMOIN : la course 13 n\'a pas encore de résultat');

    final avant = _EtatIA.prendre(prefs);
    final resultat = await svc.analyseJourneeComplete(date: jour);
    final apres = _EtatIA.prendre(prefs);

    // ignore: avoid_print
    print('[A4-T3-bis] succes=${resultat.succes} '
        'nbNouveauxResultats=${resultat.nbNouveauxResultats} '
        'erreurs=${resultat.erreurs}');
    // ignore: avoid_print
    print('[A4-T3-bis] nbMisesAJour ${avant.nbMisesAJour} -> ${apres.nbMisesAJour}');
    // ignore: avoid_print
    print('[A4-T3-bis] journal ${json.decode(avant.journal).length} -> '
        '${json.decode(apres.journal).length}');

    expect(resultat.succes, isTrue,
        reason: 'TÉMOIN : l\'analyse doit aboutir');
    // ⚠️ Aucune course réelle n'est interrogée ici (aucun réseau) : le nombre
    //    de nouveaux résultats dépend donc de la disponibilité PMU et n'est
    //    PAS asserté. Ce qui est asserté, c'est la cohérence interne.
    expect(apres.nbMisesAJour >= avant.nbMisesAJour, isTrue,
        reason: 'A4-T3-bis : `nbMisesAJour` ne doit jamais RECULER');
    expect(json.decode(apres.journal).length >= json.decode(avant.journal).length,
        isTrue,
        reason: 'A4-T3-bis : le journal ne doit jamais perdre d\'entrées');

    // ── Contre-preuve structurelle : les deux protections n'étouffent pas
    //    l'apprentissage. On vérifie le chemin par un résultat FORCÉ, sans
    //    réseau : `enregistrerResultat` sur la course 13.
    final avantForcage = _EtatIA.prendre(prefs);
    await svc.enregistrerResultat(
      courseKey: _courseKey(13, jourCourse),
      arriveeReelle: const <int>[1, 2, 3, 4, 5],
      cotesPmuParNumero: const <String, double>{'1': 2.2, '2': 5.0, '3': 9.0},
    );
    final apresForcage = _EtatIA.prendre(prefs);
    // ignore: avoid_print
    print('[A4-T3-bis] après enregistrementResultat : nbMisesAJour '
        '${avantForcage.nbMisesAJour} -> ${apresForcage.nbMisesAJour}');
    // ignore: avoid_print
    print('[A4-T3-bis] après enregistrementResultat : journal '
        '${json.decode(avantForcage.journal).length} -> '
        '${json.decode(apresForcage.journal).length}');

    expect(apresForcage.nbMisesAJour > avantForcage.nbMisesAJour, isTrue,
        reason: 'A4-T3-bis : sur un NOUVEAU résultat, `enregistrerResultat` '
            'doit apprendre (l.3380-3382 inchangés). Sinon le correctif aurait '
            'cassé l\'apprentissage. '
            'avant=${avantForcage.nbMisesAJour} '
            'après=${apresForcage.nbMisesAJour}');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  T4 — Deux analyses successives de la même journée : la répétition ne
  //  doit provoquer AUCUN apprentissage supplémentaire.
  // ─────────────────────────────────────────────────────────────────────────
  test('A4-T4 — deux analyses successives de la même journée : '
      'aucun apprentissage lors de la répétition', () async {
    final svc = IaMemoryService.instance;
    final jour = DateTime.now().subtract(const Duration(days: 1));
    final jourCourse = DateTime(jour.year, jour.month, jour.day, 14, 30);

    final pronostics = <IaPronostic>[
      for (var i = 1; i <= 13; i++) _pronosticResolu(i, jourCourse),
    ];
    final prefs = await _monter(pronostics, jourCourse);

    final e0 = _EtatIA.prendre(prefs);
    final r1 = await svc.analyseJourneeComplete(date: jour);
    final e1 = _EtatIA.prendre(prefs); // référence prise ENTRE les deux
    final r2 = await svc.analyseJourneeComplete(date: jour);
    final e2 = _EtatIA.prendre(prefs);

    // ignore: avoid_print
    print('[A4-T4] r1 nouveaux=${r1.nbNouveauxResultats} '
        'r2 nouveaux=${r2.nbNouveauxResultats}');
    // ignore: avoid_print
    print('[A4-T4] e0 → e1 : ${_EtatIA.differences(e0, e1).length} différence(s)');
    // ignore: avoid_print
    print('[A4-T4] e1 → e2 : ${_EtatIA.differences(e1, e2).length} différence(s)');
    for (final l in _EtatIA.differences(e1, e2)) {
      // ignore: avoid_print
      print('  [A4-T4] $l');
    }

    expect(r1.nbNouveauxResultats, 0,
        reason: 'TÉMOIN : aucune course nouvelle au 1er passage');
    expect(r2.nbNouveauxResultats, 0,
        reason: 'TÉMOIN : aucune course nouvelle au 2e passage');
    // Le premier passage ne doit plus rien modifier non plus (correctif T3).
    expect(_EtatIA.differences(e0, e1), isEmpty,
        reason: _EtatIA.rapport('A4-T4 : 1er passage', e0, e1));
    // Et la répétition doit être strictement neutre.
    expect(_EtatIA.differences(e1, e2), isEmpty,
        reason: _EtatIA.rapport('A4-T4 : répétition', e1, e2));
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  RÉINJECTION HISTORIQUE — à zéro nouveau résultat, les statistiques
  //  doivent TOUJOURS être alimentées, sans mutation IA et sans double
  //  comptage. C'est l'exacte contrepartie de `apprendre: false`.
  // ─────────────────────────────────────────────────────────────────────────
  test('A4-T4b — réinjection historique à zéro nouveau résultat : '
      'statistiques alimentées, aucune mutation IA, aucun double comptage',
      () async {
    final svc = IaMemoryService.instance;
    final jour = DateTime.now().subtract(const Duration(days: 1));
    final jourCourse = DateTime(jour.year, jour.month, jour.day, 14, 30);

    final pronostics = <IaPronostic>[
      for (var i = 1; i <= 13; i++) _pronosticResolu(i, jourCourse),
    ];
    final prefs = await _monter(pronostics, jourCourse);

    // `ia_precision_v2` absent ⇒ le chemin l.4640 (réinjection) sera parcouru.
    expect(prefs.getString('ia_precision_v2'), isNull,
        reason: 'TÉMOIN : historique de précision vierge');
    expect(_historiqueComplet(), '{}',
        reason: 'TÉMOIN : aucune statistique par type avant l\'analyse');

    final avant = _EtatIA.prendre(prefs);
    final r1 = await svc.analyseJourneeComplete(date: jour);
    final apres = _EtatIA.prendre(prefs);
    final hist1 = _historiqueComplet();

    // ignore: avoid_print
    print('[A4-T4b] nouveaux=${r1.nbNouveauxResultats} historique=$hist1');

    expect(r1.nbNouveauxResultats, 0,
        reason: 'TÉMOIN : aucune course nouvelle');
    // ★ Le réinjection a bien EU LIEU : les statistiques sont alimentées.
    expect(hist1, isNot('{}'),
        reason: 'A4-T4b : la réinjection historique doit alimenter '
            '`historiqueComplet`. Elle est CONSERVÉE par le correctif');
    expect(hist1.contains('Simple Gagnant'), isTrue,
        reason: 'A4-T4b : le type conseillé doit apparaître. Mesuré : $hist1');
    // ★ ... et AUCUNE mutation IA pour autant.
    expect(_EtatIA.differences(avant, apres), isEmpty,
        reason: _EtatIA.rapport('A4-T4b : réinjection', avant, apres));

    // ★ Absence de DOUBLE COMPTAGE : un second passage ne doit pas ajouter
    //    une seconde entrée pour la même date (garde `dejaPresent` l.4635).
    final r2 = await svc.analyseJourneeComplete(date: jour);
    final hist2 = _historiqueComplet();
    // ignore: avoid_print
    print('[A4-T4b] 2e passage nouveaux=${r2.nbNouveauxResultats} '
        'historique=$hist2');
    expect(hist2, hist1,
        reason: 'A4-T4b : DOUBLE COMPTAGE détecté — `historiqueComplet` a '
            'changé au 2e passage.\n  1er : $hist1\n  2e  : $hist2');

    // Le contenu doit rester exactement celui du jour, une seule fois.
    final decoded = json.decode(hist2) as Map<String, dynamic>;
    for (final entry in decoded.entries) {
      final jours = entry.value as List<dynamic>;
      expect(jours.length, 1,
          reason: 'A4-T4b : type "${entry.key}" doit avoir EXACTEMENT une '
              'entrée journalière, pas ${jours.length}');
    }
  });
}
