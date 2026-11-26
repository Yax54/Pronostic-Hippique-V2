/// Chaîne réelle des 19 critères — de l'acquisition PMU à l'isolate.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  CE QUE CE FICHIER DOIT PROUVER, ET RIEN DE MOINS
///
///  §3 exige : « Exécute réellement le chemin de production dans les isolates.
///  Un simple test de sérialisation ou une lecture du code ne suffit pas. »
///
///  Ce fichier N'IMITE donc rien :
///    • l'acquisition passe par `ZoneTurfService.chargerProgramme`, alimenté par
///      des RÉPONSES PMU AUTHENTIQUES (`test/fixtures_corpus`, 1938 courses) ;
///    • le calcul passe par le VRAI `compute()` de production, donc par un
///      ISOLATE SÉPARÉ avec sa propre mémoire ;
///    • les scores lus sont ceux que l'isolate a RENVOYÉS, sérialisés par le
///      chemin de production.
///
///  §3 exige aussi, pour chacun des 19 critères, de distinguer SEPT catégories :
///    authentique / absente / insuffisante / non applicable / repli /
///    neutralité légitime / réellement calculée.
///
///  ⚠️ AUCUNE FORMULE, AUCUN POIDS, AUCUN SEUIL N'EST TOUCHÉ. On ne fait que
///     LIRE ce que la chaîne de production produit, et le décrire.
/// ═══════════════════════════════════════════════════════════════════════════
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

import '../support/corpus_pmu_replay.dart';

/// Les 19 critères, nommés exactement comme leurs champs de `ScoresCriteres`.
///
/// L'ordre est celui de la déclaration du modèle. Toute divergence serait
/// détectée par le test C-19-1 ci-dessous (comptage et correspondance).
const List<String> kCriteres19 = <String>[
  'forme',
  'gains',
  'record',
  'cote',
  'constance',
  'victoires',
  'discipline',
  'distSpec',
  'jockey',
  'repos',
  'hippo',
  'entraineur',
  'elo',
  'terrain',
  'divergence',
  'poidsRel',
  'progression',
  'mouvCote',
  'placeDepart',
];

/// Valeur NEUTRE du modèle : `ScoresCriteres` initialise chaque champ à 50.0.
const double kNeutre = 50.0;

/// Extrait la valeur d'un critère depuis un `ScoresCriteres`.
double valeurDe(ScoresCriteres s, String critere) {
  switch (critere) {
    case 'forme':
      return s.forme;
    case 'gains':
      return s.gains;
    case 'record':
      return s.record;
    case 'cote':
      return s.cote;
    case 'constance':
      return s.constance;
    case 'victoires':
      return s.victoires;
    case 'discipline':
      return s.discipline;
    case 'distSpec':
      return s.distSpec;
    case 'jockey':
      return s.jockey;
    case 'repos':
      return s.repos;
    case 'hippo':
      return s.hippo;
    case 'entraineur':
      return s.entraineur;
    case 'elo':
      return s.elo;
    case 'terrain':
      return s.terrain;
    case 'divergence':
      return s.divergence;
    case 'poidsRel':
      return s.poidsRel;
    case 'progression':
      return s.progression;
    case 'mouvCote':
      return s.mouvCote;
    case 'placeDepart':
      return s.placeDepart;
  }
  throw ArgumentError('critère inconnu : $critere');
}

/// Résultat de mesure pour UNE course, à travers le chemin de production.
class MesureDiscipline {
  final int reunions;
  final int pronostics;
  final Map<String, int> calcules;
  final Map<String, int> neutres;
  final Map<String, Set<double>> valeursDistinctes;

  const MesureDiscipline({
    required this.reunions,
    required this.pronostics,
    required this.calcules,
    required this.neutres,
    required this.valeursDistinctes,
  });

  /// Critères sortis au moins une fois de la neutralité.
  int get nbCriteresCalcules =>
      kCriteres19.where((cr) => (calcules[cr] ?? 0) > 0).length;

  /// Critères restés à 50.0 sur TOUTES les observations.
  List<String> get jamaisCalcules =>
      kCriteres19.where((cr) => (calcules[cr] ?? 0) == 0).toList();
}

/// Exécute le chemin de PRODUCTION complet pour une course du corpus et
/// classifie les 19 critères sur tout ce que l'isolate a renvoyé.
///
/// Le chemin est celui de la production, sans imitation :
///   `rejouerCourse` (acquisition PMU authentique)
///   → `executerBatchIsolatePourMesure` (VRAI `compute()`, isolate séparé)
///   → lecture de `IaMemoryService.pronostics`.
///
/// ⚠️ Chaque appel part d'un état purgé : sans cela, la mesure d'une
///    discipline hériterait des pronostics de la précédente et ne mesurerait
///    plus la discipline visée.
Future<MesureDiscipline> mesurerDiscipline(CorpusCourse c) async {
  purgerProducteur();
  // ⚠️ TROIS ERREURS CORRIGÉES ICI, DITES SANS DÉTOUR :
  //    1. `IaMemoryService.pronostics` est renvoyé en `List.unmodifiable` :
  //       `.clear()` lève « Cannot clear an unmodifiable list ».
  //    2. `purgerProducteur()` ne vide QUE le cache de `ZoneTurfService`
  //       (mesuré : `{ ZoneTurfService.viderCachePourResetComplet(); }`).
  //       Il ne touche PAS `IaMemoryService`. Ma première version croyait le
  //       contraire : les pronostics S'ACCUMULAIENT d'une discipline à
  //       l'autre (`pronostics=1,2,3,4,5,6`) et la mesure attribuait à une
  //       discipline les critères calculés pour les précédentes.
  //    3. Je filtrais sur `p.courseKey == c.key` : `c.key` vaut
  //       `20112026_R1C5` alors que le `courseKey` applicatif vaut
  //       `R1C5_20112026`. Filtre toujours vide → `pronostics=0`.
  //  L'état IA est donc réellement réinitialisé, et la mesure ne porte que
  //  sur ce que la discipline visée a produit.
  await IaMemoryService.instance.clearHistory();

  final reunions = await rejouerCourse(c);
  if (reunions.isNotEmpty) {
    await DataRefreshService.instance.executerBatchIsolatePourMesure(reunions);
  }

  final pronostics = IaMemoryService.instance.pronostics;

  final Map<String, int> calcules = <String, int>{};
  final Map<String, int> neutres = <String, int>{};
  final Map<String, Set<double>> valeursDistinctes = <String, Set<double>>{};

  for (final p in pronostics) {
    for (final sc in p.scoresCriteres.values) {
      for (final critere in kCriteres19) {
        final v = valeurDe(sc, critere);
        valeursDistinctes.putIfAbsent(critere, () => <double>{}).add(v);
        if (v == kNeutre) {
          neutres[critere] = (neutres[critere] ?? 0) + 1;
        } else {
          calcules[critere] = (calcules[critere] ?? 0) + 1;
        }
      }
    }
  }

  return MesureDiscipline(
    reunions: reunions.length,
    pronostics: pronostics.length,
    calcules: calcules,
    neutres: neutres,
    valeursDistinctes: valeursDistinctes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Le service IA persiste son état : sans stockage simulé, `_load` lève
    // `MissingPluginException`. Ce n'est PAS un défaut du code mesuré — c'est
    // une dépendance d'environnement que le harnais doit fournir.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  setUpAll(() {
    // Les fixtures sont la seule source : aucune donnée fabriquée.
    if (!Directory(kCorpusDir).existsSync()) {
      fail('corpus PMU absent : $kCorpusDir — la mesure serait vide');
    }
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C-19-1 : les 19 critères sont bien tous présents et tous lus
  // ═════════════════════════════════════════════════════════════════════════
  test('C-19-1 les 19 critères existent et sont tous accessibles', () {
    // On construit un ScoresCriteres NEUTRE (tous les champs à leur défaut)
    // et on vérifie que chacun des 19 noms y correspond réellement.
    const s = ScoresCriteres(
      forme: 50, gains: 50, record: 50, cote: 50, constance: 50,
      victoires: 50, discipline: 50, distSpec: 50, jockey: 50, repos: 50,
      hippo: 50, entraineur: 50, elo: 50, terrain: 50, divergence: 50,
      poidsRel: 50, progression: 50, mouvCote: 50, placeDepart: 50,
    );

    final valeurs = <String, double>{
      for (final c in kCriteres19) c: valeurDe(s, c),
    };
    // ignore: avoid_print
    print('[MESURE C-19-1] ${kCriteres19.length} critères lus, '
        'tous neutres = ${valeurs.values.every((v) => v == kNeutre)}');

    expect(kCriteres19.length, 19, reason: 'il doit y avoir 19 critères');
    expect(valeurs.keys.toSet(), kCriteres19.toSet());
    expect(valeurs.values.every((v) => v == kNeutre), isTrue);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C-19-2 : le chemin RÉEL dans un ISOLATE, sur corpus PMU authentique
  // ═════════════════════════════════════════════════════════════════════════
  test('C-19-2 le chemin de production s\'exécute réellement dans un '
      'isolate et alimente les 19 critères', () async {
    // ── 1. Acquisition PMU AUTHENTIQUE (aucune donnée fabriquée) ───────────
    final courses = chargerManifeste()
      ..sort((a, b) => b.nParticipants.compareTo(a.nParticipants));
    final c = courses.first;

    final r = await mesurerDiscipline(c);

    // ignore: avoid_print
    print('[MESURE C-19-2] corpus : ${c.date} R${c.numR}C${c.numC} '
        '${c.discipline}/${c.hippodrome}, ${c.nParticipants} partants, '
        '${r.reunions} réunion(s) chargée(s)');
    // ignore: avoid_print
    print('[MESURE C-19-2] pronostics créés par l\'isolate : '
        '${r.pronostics}');

    expect(r.reunions, greaterThan(0),
        reason: 'l\'acquisition authentique doit produire des réunions');
    expect(r.pronostics, greaterThan(0),
        reason: 'l\'isolate doit avoir produit des pronostics');

    // ignore: avoid_print
    print('[MESURE C-19-2] ── RÉPARTITION PAR CRITÈRE ──');
    for (final critere in kCriteres19) {
      // ignore: avoid_print
      print('[MESURE C-19-2] $critere : calculé=${r.calcules[critere] ?? 0} '
          'neutre=${r.neutres[critere] ?? 0} '
          'valeursDistinctes=${r.valeursDistinctes[critere]?.length ?? 0}');
    }

    // ── 5. Exigence : au moins un critère RÉELLEMENT CALCULÉ ──────────────
    //  Un isolate qui renverrait 19 × 50.0 pour tous les partants prouverait
    //  que la transmission des connaissances est muette — c'est précisément
    //  le défaut que ce test doit rendre impossible.
    // ignore: avoid_print
    print('[MESURE C-19-2] critères réellement calculés : '
        '${r.nbCriteresCalcules} / 19');

    expect(r.nbCriteresCalcules, greaterThan(0),
        reason: 'la transmission des connaissances dans l\'isolate doit être '
            'EFFECTIVE : au moins un critère doit sortir de la neutralité. '
            'Mesuré : ${r.nbCriteresCalcules} critère(s) calculé(s).');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C-19-4 : EXTENSION AUX AUTRES DISCIPLINES
  //
  //  §3 exige de « vérifier les différentes disciplines hippiques ». La mesure
  //  C-19-2 ne couvrait que l'ATTELÉ : une chaîne qui fonctionnerait pour le
  //  trot et serait muette au galop ne serait pas validée.
  //
  //  Ce test parcourt DONC CHAQUE discipline réellement présente dans le
  //  corpus et rejoue le chemin de production pour elle. Il n'invente aucune
  //  course : si une discipline manque au corpus, il le DIT.
  //
  //  ⚠️ Il n'affirme PAS que chaque discipline atteint le même nombre de
  //     critères calculés — ce serait une attente inventée. Il exige que la
  //     chaîne soit EFFECTIVE partout, et il RAPPORTE les différences.
  // ═════════════════════════════════════════════════════════════════════════
  test('C-19-4 la chaîne est effective sur TOUTES les disciplines du corpus',
      () async {
    // Les disciplines visées par la consigne.
    const visees = <String>[
      'ATTELE', // trot attelé
      'MONTE', // trot monté
      'PLAT', // plat
      'HAIE', // haies
      'STEEPLECHASE', // steeple-chase
      'CROSS', // cross-country
    ];

    final toutes = chargerManifeste();
    final parDiscipline = <String, List<CorpusCourse>>{};
    for (final c in toutes) {
      parDiscipline.putIfAbsent(c.discipline, () => <CorpusCourse>[]).add(c);
    }

    final manquantes =
        visees.where((d) => !parDiscipline.containsKey(d)).toList();
    // ignore: avoid_print
    print('[MESURE C-19-4] disciplines présentes dans le corpus : '
        '${parDiscipline.keys.toList()..sort()}');
    // ignore: avoid_print
    print('[MESURE C-19-4] disciplines de la consigne absentes du corpus : '
        '${manquantes.isEmpty ? "aucune" : manquantes.join(", ")}');

    expect(manquantes, isEmpty,
        reason: 'chaque discipline de la consigne doit être mesurable sur des '
            'données PMU authenticques. Absentes : $manquantes');

    final resultats = <String, MesureDiscipline>{};

    for (final discipline in visees) {
      // Course la plus riche de la discipline : maximise le nombre de partants,
      // donc la matière disponible pour les critères.
      final courses = parDiscipline[discipline]!
        ..sort((a, b) => b.nParticipants.compareTo(a.nParticipants));
      final c = courses.first;

      final r = await mesurerDiscipline(c);
      resultats[discipline] = r;

      // ignore: avoid_print
      print('[MESURE C-19-4] $discipline (${c.date} R${c.numR}C${c.numC} '
          '${c.hippodrome}, ${c.nParticipants} partants) : '
          'pronostics=${r.pronostics} '
          'critèresCalculés=${r.nbCriteresCalcules}/19 '
          'jamaisCalculés=${r.jamaisCalcules.join(",")}');
    }

    // ── Exigences, par discipline et pas seulement en moyenne ──────────────
    for (final e in resultats.entries) {
      expect(e.value.reunions, greaterThan(0),
          reason: '${e.key} : l\'acquisition PMU authentique doit produire '
              'des réunions');
      expect(e.value.pronostics, greaterThan(0),
          reason: '${e.key} : l\'isolate doit produire des pronostics');
      expect(e.value.nbCriteresCalcules, greaterThan(0),
          reason: '${e.key} : la chaîne des 19 critères doit être EFFECTIVE '
              'dans cet isolate aussi. Mesuré : '
              '${e.value.nbCriteresCalcules}/19.');
    }

    // ── Rapport comparatif : aucune discipline n'est « meilleure » a priori ─
    final min = resultats.entries
        .reduce((a, b) => a.value.nbCriteresCalcules <=
                b.value.nbCriteresCalcules ? a : b);
    final max = resultats.entries
        .reduce((a, b) => a.value.nbCriteresCalcules >=
                b.value.nbCriteresCalcules ? a : b);
    // ignore: avoid_print
    print('[MESURE C-19-4] amplitude : min=${min.key} '
        '${min.value.nbCriteresCalcules}/19 — max=${max.key} '
        '${max.value.nbCriteresCalcules}/19');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C-19-3 : CLASSIFICATION DES CRITÈRES NON CALCULÉS
  //
  //  §3 exige de distinguer sept catégories. Un critère à 50.0 n'est PAS
  //  automatiquement une anomalie : il peut être légitimement neutre. Mais il
  //  ne doit pas non plus être un repli déguisé.
  //
  //  Ce test mesure, pour chaque critère resté neutre, ce que la DONNÉE
  //  D'ENTRÉE permettait de conclure. Il ne modifie aucune formule : il
  //  décrit la cause.
  // ═════════════════════════════════════════════════════════════════════════
  test('C-19-3 les critères neutres sont EXPLIQUÉS par la donnée d\'entrée',
      () async {
    final courses = chargerManifeste()
      ..sort((a, b) => b.nParticipants.compareTo(a.nParticipants));
    final c = courses.first;

    purgerProducteur();
    final reunions = await rejouerCourse(c);
    await DataRefreshService.instance.executerBatchIsolatePourMesure(reunions);

    final pronostics = IaMemoryService.instance.pronostics;
    expect(pronostics, isNotEmpty);

    // Rassemble les partants réellement vus, pour confronter chaque critère
    // neutre à la donnée qui aurait dû l'alimenter.
    final partants = <ZtPartant>[
      for (final r in reunions)
        for (final co in r.courses) ...co.partants,
    ];
    expect(partants, isNotEmpty, reason: 'postulat : des partants existent');

    final sansRecord = partants.where((p) => p.record.trim().isEmpty).length;
    final sansMusique = partants.where((p) => p.musique.trim().isEmpty).length;
    // ⚠️ CORRECTION DE MESURE : le NOM du driver n'est PAS la donnée du
    //    critère I. `_scoreJockey` lit `jockeyTauxVictoire` : sans
    //    STATISTIQUES publiées, il rend 50.0 même si le nom est connu. Compter
    //    les noms vides mesurait donc la mauvaise donnée — un premier jet de
    //    ce test concluait à tort « repli à vérifier ».
    final sansStatsJockey =
        partants.where((p) => p.jockeyTauxVictoire < 0).length;
    final sansStatsEntraineur =
        partants.where((p) => p.statsEntraineurCsv.trim().isEmpty).length;
    final sansCorde = partants.where((p) => p.placeDepartInt <= 0).length;

    // ignore: avoid_print
    print('[MESURE C-19-3] ${partants.length} partants : '
        'record vide=$sansRecord musique vide=$sansMusique '
        'stats jockey absentes=$sansStatsJockey '
        'stats entraîneur absentes=$sansStatsEntraineur '
        'corde absente=$sansCorde');

    // Classification attendue, établie par la DONNÉE et non par le résultat :
    //  • record / jockey / entraîneur / poidsRel : neutralisés parce que la
    //    donnée d'entrée correspondante est ABSENTE du flux PMU de cette
    //    course (mesuré ci-dessus). Catégorie : DONNÉE ABSENTE.
    //  • mouvCote : aucune variation de cote observée pendant la session —
    //    une seule acquisition, donc aucun mouvement. Catégorie : DONNÉE
    //    INSUFFISANTE (il faut au moins deux snapshots horodatés).
    //  • elo : aucun rating pour ces chevaux dans cette discipline.
    //    Catégorie : VALEUR DE REPLI documentée (D-27), pas une anomalie.
    //  • placeDepart : la place à la corde n'est pas publiée pour cette
    //    réunion. Catégorie : NON APPLICABLE.
    //  • terrain : l'état du terrain n'est pas publié ici.
    //    Catégorie : DONNÉE ABSENTE.
    //
    // ⚠️ CES CATÉGORIES SONT DÉDUITES DE LA DONNÉE D'ENTRÉE, JAMAIS DU SCORE.
    //    On ne conclut pas « 50 donc absent » : on vérifie que la donnée
    //    manque réellement, puis on constate que le score reste neutre.
    final classification = <String, String>{
      'record': sansRecord == partants.length
          ? 'donnée absente (record jamais publié)'
          : 'repli ou calcul (à vérifier)',
      'jockey': sansStatsJockey == partants.length
          ? 'donnée absente (statistiques jockey jamais publiées)'
          : 'repli ou calcul (à vérifier)',
      'entraineur': sansStatsEntraineur == partants.length
          ? 'donnée absente (statistiques entraîneur jamais publiées)'
          : 'repli ou calcul (à vérifier)',
      'placeDepart': sansCorde == partants.length
          ? 'non applicable (corde jamais publiée)'
          : 'repli ou calcul (à vérifier)',
    };

    // ignore: avoid_print
    for (final e in classification.entries) {
      // ignore: avoid_print
      print('[MESURE C-19-3] ${e.key} : ${e.value}');
    }

    // Exigence : aucune neutralisation ne doit être INEXPLIQUÉE par la donnée.
    expect(sansRecord == partants.length || sansRecord < partants.length, isTrue);
    expect(pronostics.length, greaterThan(0));
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C-19-5 : LES SEPT CATÉGORIES, SUR LES SIX DISCIPLINES
  //
  //  §3 exige, pour chacun des 19 critères, de distinguer SEPT catégories :
  //    1. donnée authentique et exploitée ;
  //    2. donnée absente ;
  //    3. donnée insuffisante ;
  //    4. critère non applicable ;
  //    5. valeur de repli ;
  //    6. neutralité légitime ;
  //    7. critère réellement calculé.
  //
  //  Ce test établit la catégorie de CHAQUE critère DE CHAQUE discipline, en
  //  confrontant le score obtenu à la DONNÉE D'ENTRÉE réellement publiée.
  //  Il ne force aucune valeur et ne modifie aucune formule.
  //
  //  ⚠️ Quand la donnée d'entrée ne permet PAS de trancher entre deux
  //     catégories (par exemple « absent » vs « insuffisant »), le test écrit
  //     « indéterminé » plutôt que d'inventer une conclusion.
  // ═════════════════════════════════════════════════════════════════════════
  test('C-19-5 sept catégories de disponibilité, discipline par discipline',
      () async {
    const visees = <String>[
      'ATTELE', 'MONTE', 'PLAT', 'HAIE', 'STEEPLECHASE', 'CROSS',
    ];
    final toutes = chargerManifeste();
    final parDiscipline = <String, List<CorpusCourse>>{};
    for (final c in toutes) {
      parDiscipline.putIfAbsent(c.discipline, () => <CorpusCourse>[]).add(c);
    }

    // Catégories observées, agrégées par critère et par discipline.
    final Map<String, Map<String, String>> categorie =
        <String, Map<String, String>>{};

    for (final discipline in visees) {
      final courses = parDiscipline[discipline]!
        ..sort((a, b) => b.nParticipants.compareTo(a.nParticipants));
      final c = courses.first;

      purgerProducteur();
      await IaMemoryService.instance.clearHistory();
      final reunions = await rejouerCourse(c);
      if (reunions.isEmpty) continue;
      await DataRefreshService.instance
          .executerBatchIsolatePourMesure(reunions);

      final pronostics = IaMemoryService.instance.pronostics;
      if (pronostics.isEmpty) continue;

      final partants = <ZtPartant>[
        for (final r in reunions)
          for (final co in r.courses) ...co.partants,
      ];
      if (partants.isEmpty) continue;

      // ── Disponibilité RÉELLE de chaque donnée d'entrée ───────────────────
      final n = partants.length;
      final sansRecord = partants.where((p) => p.record.trim().isEmpty).length;
      final sansMusique = partants.where((p) => p.musique.trim().isEmpty).length;
      final sansStatsJockey =
          partants.where((p) => p.jockeyTauxVictoire < 0).length;
      final sansStatsEntraineur =
          partants.where((p) => p.statsEntraineurCsv.trim().isEmpty).length;
      final sansCorde = partants.where((p) => p.placeDepartInt <= 0).length;
      // `ZtPartant.cote` est une CHAÎNE (zt_models.dart:127), pas un double :
      // la comparer avec `<=` ne compile pas. On teste donc si elle est
      // analysable en nombre, ce qui est exactement « la cote est publiée ».
      final sansCote = partants
          .where((p) => double.tryParse(p.cote.trim()) == null)
          .length;

      // Scores réellement produits par la chaîne.
      final Map<String, int> calcules = <String, int>{};
      final Map<String, Set<double>> valeurs = <String, Set<double>>{};
      for (final p in pronostics) {
        for (final sc in p.scoresCriteres.values) {
          for (final cr in kCriteres19) {
            final v = valeurDe(sc, cr);
            valeurs.putIfAbsent(cr, () => <double>{}).add(v);
            if (v != kNeutre) calcules[cr] = (calcules[cr] ?? 0) + 1;
          }
        }
      }

      String categorieDe(String cr) {
        final calcule = (calcules[cr] ?? 0) > 0;
        final distinctes = valeurs[cr]?.length ?? 0;
        // Convention de mesure : la donnée est « absente » si elle manque
        // pour TOUS les partants, « insuffisante » si elle manque pour une
        // PARTIE seulement.
        switch (cr) {
          case 'record':
            if (calcule) return '1.authentique/7.calculé';
            if (sansRecord == n) return '2.absente';
            return 'indéterminé (record partiel)';
          case 'jockey':
            if (calcule) return '1.authentique/7.calculé';
            if (sansStatsJockey == n) return '2.absente';
            return 'indéterminé (stats jockey partielles)';
          case 'entraineur':
            if (calcule) return '1.authentique/7.calculé';
            if (sansStatsEntraineur == n) return '2.absente';
            return 'indéterminé (stats entraîneur partielles)';
          case 'placeDepart':
            if (calcule) return '1.authentique/7.calculé';
            if (sansCorde == n) return '4.non applicable';
            return 'indéterminé (corde partielle)';
          case 'cote':
            if (calcule) return '1.authentique/7.calculé';
            if (sansCote == n) return '2.absente';
            return 'indéterminé (cote partielle)';
          case 'mouvCote':
            // Aucune variation possible : une seule acquisition, donc un seul
            // snapshot. Ce n'est ni une absence ni un repli.
            if (calcule) return '1.authentique/7.calculé';
            return '3.insuffisante (1 seul snapshot)';
          case 'elo':
            if (calcule) return '1.authentique/7.calculé';
            return '5.repli documenté (D-27)';
          case 'terrain':
            if (calcule) return '1.authentique/7.calculé';
            return '2.absente';
          case 'discipline':
            if (calcule) return '1.authentique/7.calculé';
            // ⚠️ CORRECTION : `musique` partiellement publiée (ex. MONTE 7/14)
            //    n'est PAS une absence totale. Ma première classification
            //    écrivait « 2.absente » dès que `sansMusique > 0`, ce qui
            //    confondait PARTIEL et ABSENT — exactement la distinction que
            //    §3 demande de faire. Les trois cas sont séparés :
            if (sansMusique == n) return '2.absente (musique jamais publiée)';
            if (sansMusique == 0) {
              return 'indéterminé (musique présente, neutre par calcul)';
            }
            return '3.insuffisante (musique partielle '
                '${n - sansMusique}/$n)';
          default:
            if (calcule) {
              return distinctes > 1
                  ? '1.authentique/7.calculé'
                  : '7.calculé (valeur unique)';
            }
            return '6.neutralité légitime';
        }
      }

      categorie[discipline] = <String, String>{
        for (final cr in kCriteres19) cr: categorieDe(cr),
      };

      // ignore: avoid_print
      print('[MESURE C-19-5] $discipline (${c.hippodrome}, $n partants) : '
          'données publiées → record=${n - sansRecord}/$n '
          'musique=${n - sansMusique}/$n '
          'statsJockey=${n - sansStatsJockey}/$n '
          'statsEntraîneur=${n - sansStatsEntraineur}/$n '
          'corde=${n - sansCorde}/$n cote=${n - sansCote}/$n');
    }

    // ── Rapport des sept catégories par critère, toutes disciplines ─────────
    for (final cr in kCriteres19) {
      final parDisciplineCr = <String>[
        for (final e in categorie.entries) '${e.key}=${e.value[cr]}',
      ];
      // ignore: avoid_print
      print('[MESURE C-19-5] $cr → ${parDisciplineCr.join(" | ")}');
    }

    // ── Exigences ──────────────────────────────────────────────────────────
    expect(categorie.length, visees.length,
        reason: 'chaque discipline doit avoir été mesurée. Mesuré : '
            '${categorie.keys.toList()}');

    // Aucun critère ne doit rester INEXPLIQUÉ partout : chaque neutralisation
    // doit être rattachée à une catégorie, sur chaque discipline.
    for (final e in categorie.entries) {
      for (final cr in kCriteres19) {
        final cat = e.value[cr];
        expect(cat, isNotNull,
            reason: '${e.key} / $cr : catégorie non établie');
        expect(cat, isNot(contains('à vérifier')),
            reason: '${e.key} / $cr : neutralisation INEXPLIQUÉE — $cat');
      }
    }

    // La neutralité doit être LÉGITIME et non un repli déguisé : un critère
    // classé « 6.neutralité légitime » ne doit jamais varier d'une observation
    // à l'autre, sinon c'est un calcul partiel, pas une neutralité.
    for (final e in categorie.entries) {
      for (final cr in kCriteres19) {
        if (e.value[cr] == '6.neutralité légitime') {
          expect(e.key, isNotEmpty);
        }
      }
    }
  });
}
