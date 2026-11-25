// ═══════════════════════════════════════════════════════════════════════════
//  V5 — Sauvegarde / Restauration de la mémoire IA (BackupService)
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/.
//
//  Objet : vérifier le cycle réel
//      exporterDonnees()  →  fichier JSON sur disque
//      importerDepuisFichier()  →  _restaurerDepuisJson()  →  recharger()
//
//  Les 5 exigences de l'utilisateur :
//    1. Cycle complet export → fichier → restauration → rechargement  ... V5/T1
//    2. Conservation exacte (pronostics, scores IA, 19 critères, ELO,
//       poids, seuils, journal) ........................................ V5/T2
//    3. JSON-only → appareil gzip, et gzip → appareil JSON-only ........ V5/T3, V5/T4
//    4. Aucune donnée locale résiduelle prioritaire .................... V5/T5, V5/T6
//    5. Aucun apprentissage ni recalcul de pronostics .................. V5/T7
//
//  Le vrai code de production est exercé :
//    • exporterDonnees()        (public, backup_service.dart:586)
//    • importerDepuisFichier()  (public, backup_service.dart:679)
//    • _restaurerDepuisJson()   (privé, atteint via importerDepuisFichier)
//  Les deux dépendances de plateforme sont injectées :
//    • PathProviderPlatform.instance  → _FakePathProvider
//    • FilePicker.platform            → _FakeFilePicker
//  Aucune ré-implémentation de la logique de sauvegarde.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io'; // GZipCodec — même codec que ia_memory_service.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart'; // EloScore
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/models/pronostic_resultat_utilisateur.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/pronostic_resultats_repository.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Faux de plateforme
// ───────────────────────────────────────────────────────────────────────────

/// Injecte un répertoire temporaire réel (le vrai disque du sandbox).
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tmpPath);
  final String tmpPath;

  @override
  Future<String?> getTemporaryPath() async => tmpPath;
}

/// Injecte un fichier choisi sans passer par le sélecteur natif.
/// `FilePicker()` appelle `super(token: _token)` → la vérification
/// `PlatformInterface.verifyToken` du setter `FilePicker.platform` passe.
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this._result);

  final FilePickerResult? _result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      _result;
}

// ───────────────────────────────────────────────────────────────────────────
//  Outils de construction de données
// ───────────────────────────────────────────────────────────────────────────

String _cleElo(String nom, String discipline) {
  final nomNorm = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  return '$nomNorm|${EloService.normaliserDiscipline(discipline)}';
}

/// 19 critères avec des valeurs TOUTES distinctes et non neutres, afin
/// qu'une perte ou une substitution de champ soit immédiatement détectée.
ScoresCriteres _criteres({double decalage = 0.0}) => ScoresCriteres(
      forme: 61.5 + decalage,
      gains: 42.25 + decalage,
      record: 73.75 + decalage,
      cote: 28.5 + decalage,
      constance: 55.125 + decalage,
      victoires: 36.875 + decalage,
      discipline: 64.0 + decalage,
      distSpec: 47.5 + decalage,
      jockey: 58.25 + decalage,
      repos: 31.75 + decalage,
      hippo: 52.5 + decalage,
      entraineur: 44.625 + decalage,
      elo: 69.25 + decalage,
      terrain: 39.5 + decalage,
      divergence: 66.875 + decalage,
      poidsRel: 49.25 + decalage,
      progression: 57.125 + decalage,
      mouvCote: 34.5 + decalage,
      placeDepart: 62.25 + decalage,
    );

/// Les 19 clés courtes du JSON `ScoresCriteres` (ordre de toJson).
const List<String> kClesCourt = [
  'f', 'g', 'r', 'c', 'k', 'v', 'd', 'ds', 'j', 'rp',
  'hp', 'en', 'el', 'tr', 'dv', 'pr', 'pg', 'mc', 'pd',
];

/// Pronostic complet : scores IA, 19 critères par cheval, résultat réel.
IaPronostic _pronostic({
  required String courseKey,
  DateTime? date,
  bool avecResultat = false,
  int nbChevaux = 4,
}) {
  final scores = <String, double>{};
  final criteres = <String, ScoresCriteres>{};
  for (var i = 1; i <= nbChevaux; i++) {
    scores['$i'] = 92.0 - i * 7.5; // valeurs distinctes et stables
    criteres['$i'] = _criteres(decalage: i.toDouble());
  }
  return IaPronostic(
    courseKey: courseKey,
    nomCourse: 'Prix de Test $courseKey',
    hippodrome: 'VINCENNES',
    discipline: 'Trot Attelé',
    datePronostic: date ?? DateTime(2026, 3, 10, 15, 30),
    scoresIA: scores,
    scoresCriteres: criteres,
    varianceScores: 123.456789,
    arriveeReelle: avecResultat ? [2, 1, 3, 4] : null,
    dateResultat: avecResultat ? DateTime(2026, 3, 10, 17, 0) : null,
    resultatsReels: avecResultat,
    rangFavoriIaDansArrivee: avecResultat ? 2 : null,
    nbTop3DansArriveeReelle: avecResultat ? 3 : null,
    nbTop5DansArriveeReelle: avecResultat ? 4 : null,
    scorePerformance: avecResultat ? 71.875 : null,
    confiancePredite: 84.5,
    typePariConseille: avecResultat ? 'Quinté+' : 'Tiercé',
    tauxReussiteAuMoment: 38.25,
    precisionIA: 63.125,
    favoriIaNom: 'CHEVAL UN',
    coteFavoriPmu: 4.35,
    cotesPmuParNumero: const {'1': 4.35, '2': 7.8, '3': 12.4, '4': 21.0},
  );
}

Map<String, dynamic> _poidsPersonnalise() {
  final p = IaPoidsAdaptatifs.defaut();
  // Modification volontaire pour prouver que la restauration n'écrase pas
  // par les valeurs par défaut.
  p.nbMisesAJour = 137;
  p.calibrationScore = 68.3125;
  p.forme = 0.2711;
  p.gains = 0.1409;
  p.mouvCote = 0.0655;
  p.dernierGradient = {'forme': 0.0125, 'elo': -0.0075};
  p.poidsIndices = PoidsIndices(
      poidsCriteres: 0.4321, poidsConfiance: 0.3333, poidsReussite: 0.2346);
  p.correlations = {'forme|cote': 0.4125, 'elo|gains': -0.1875};
  p.poidsParDiscipline['TROT_ATTELE'] = {
    'forme': 0.30,
    'gains': 0.12,
    'record': 0.10,
    'cote': 0.08,
    'constance': 0.09,
    'victoires': 0.04,
    'discipline': 0.02,
    'distSpec': 0.08,
    'jockey': 0.07,
    'repos': 0.03,
    'hippo': 0.04,
    'entraineur': 0.04,
    'elo': 0.05,
    'terrain': 0.05,
    'divergence': 0.04,
    'poidsRel': 0.03,
    'progression': 0.03,
    'mouvCote': 0.06,
    'placeDepart': 0.03,
  };
  return p.toJson();
}

SeuilsConfianceAdaptatifs _seuilsPersonnalises() => SeuilsConfianceAdaptatifs(
      seuilSimpleGagnant: 83.5,
      seuilGagnantPlace: 44.25,
      seuilSimplePlace: 71.75,
      seuilCoupleGagnant: 79.5,
      seuilCouplePlace: 55.125,
      seuilTierce: 27.25,
      seuilQuarte: 86.875,
      seuilQuinte: 0.0,
    );

JournalEntree _journal(int i) => JournalEntree(
      date: DateTime(2026, 3, 10 + i, 20, 0),
      nomCourse: 'Prix Journal $i',
      discipline: 'Trot Attelé',
      nbCoursesAnalysees: 12 + i,
      diagnostic: 'Diagnostic $i — gradient appliqué',
      avant: {'forme': 0.25, 'elo': 0.05},
      apres: {'forme': 0.2500 + i * 0.001, 'elo': 0.05 - i * 0.001},
      scorePerf: 60.0 + i,
      methode: 'gradient',
    );

StatsPrecisionParType _precision(String type, int nb, int bons) {
  final s = StatsPrecisionParType(typePari: type);
  s.ajouterJournee(DateTime(2026, 3, 10), nb, bons, ordre: 1, desordre: 1);
  return s;
}

StatsParLabel _label(String lb, int nb, int t1, int t3, int t5) =>
    StatsParLabel(label: lb, nbTotal: nb, nbTop1: t1, nbTop3: t3, nbTop5: t5)
      ..historique.add({'d': '2026-03-10', 'nb': nb, 't1': t1, 't3': t3, 't5': t5});

/// Encode une liste de pronostics au format gzip+base64 — exactement comme
/// `IaMemoryService._save()` quand `_useCompression && length > 20`.
String _gzEncode(List<IaPronostic> pronostics) {
  final jsonStr = json.encode(pronostics.map((p) => p.toJson()).toList());
  final gzipped = GZipCodec().encode(utf8.encode(jsonStr));
  return base64Encode(gzipped);
}

/// Peuple SharedPreferences comme le ferait `IaMemoryService._save()`
/// (format non compressé : moins de 21 pronostics).
Map<String, Object> _prefsCompletes({
  required List<IaPronostic> pronostics,
  required Map<String, dynamic> poidsJson,
  required Map<String, dynamic> seuilsJson,
  required List<JournalEntree> journal,
  required Map<String, StatsPrecisionParType> precision,
  required Map<String, StatsParLabel> labels,
}) {
  return <String, Object>{
    // ★ flag de migration : sans lui, _load() recalculerait _precisionParType
    'ia_precision_migrated_v3': true,
    'ia_poids_v3': json.encode(poidsJson),
    'ia_seuils_v1': json.encode(seuilsJson),
    'ia_pronostics_v2':
        pronostics.map((p) => json.encode(p.toJson())).toList(),
    'ia_journal_v2': journal.map((j) => json.encode(j.toJson())).toList(),
    'ia_precision_v2':
        json.encode(precision.map((k, v) => MapEntry(k, v.toJson()))),
    'ia_stats_labels_v1':
        json.encode(labels.map((k, v) => MapEntry(k, v.toJson()))),
    'ia_stats_types_v1': <String>[
      json.encode({
        'tp': 'Quinté+',
        'nj': 21,
        'ng': 8,
        'np': 13,
        'gn': -3.5,
      }),
    ],
  };
}

/// Installe les ELO dans le service puis les persiste.
Future<void> _installerElo(Map<String, double> ratings) async {
  final payload = <String, dynamic>{};
  ratings.forEach((cle, rating) {
    final nom = cle.split('|').first;
    payload[cle] = EloScore(
      nomCheval: nom,
      rating: rating,
      nbCourses: 17,
      variationMois: 12.5,
    ).toJson();
  });
  await EloService.instance.importerDepuisBackup(payload);
}

/// Résultat utilisateur tel que produit par l'app (Gros Paris, programme,
/// suite IA classique). Aucun champ monétaire n'existe dans le modèle :
/// `PronosticResultatUtilisateur` ne contient ni montant ni mise.
PronosticResultatUtilisateur _resultat({
  required String courseKey,
  required String typePari,
  required String source,
  required DateTime date,
  required bool gagnant,
  bool ordreExact = false,
  int nbTrouves = 0,
  int nbRequis = 4,
  List<String> predictionIA = const ['1', '2', '3', '4', '5'],
  List<String> arrivee = const ['3', '1', '2', '5', '4'],
  bool utilisableStats = true,
  bool utilisableApprentissage = false,
}) =>
    PronosticResultatUtilisateur(
      courseKey: courseKey,
      dateCourse: date,
      typePari: typePari,
      predictionIA: predictionIA,
      arriveePMUComplete: arrivee,
      gagnant: gagnant,
      ordreExact: ordreExact,
      nbTrouves: nbTrouves,
      nbRequis: nbRequis,
      source: source,
      utilisableStatsUtilisateur: utilisableStats,
      utilisableApprentissage: utilisableApprentissage,
    );

const Map<String, double> kEloAttendus = {
  'ALPHA|TROT_ATTELE': 1922.5,
  'BRAVO|TROT_ATTELE': 1687.25,
  'CHARLIE|TROT_ATTELE': 1544.75,
};

/// Snapshot complet de l'état de la mémoire IA + ELO, pour prouver
/// qu'aucune écriture d'apprentissage n'a eu lieu.
Map<String, Object?> _snapshotMemoire() {
  final svc = IaMemoryService.instance;
  return {
    'poids': json.encode(svc.poids.toJson()),
    'seuils': json.encode(svc.seuilsConfiance.toJson()),
    'elo': json.encode(EloService.instance.exporterPourBackup()),
    'journal': svc.journal.length,
    'rapports': svc.rapports.length,
    'bilansSemaine': svc.bilansSemaine.length,
    'bilansMois': svc.bilansMois.length,
    'precision': svc.precisionParType.length,
    'labels': svc.statsParLabel.length,
    'pronostics': svc.pronostics.length,
    'avecResultat': svc.pronosticsAvecResultat.length,
    'nbMisesAJour': svc.poids.nbMisesAJour,
    'dernierGradient': json.encode(svc.poids.dernierGradient),
    'calibration': svc.poids.calibrationScore,
    'correlations': json.encode(svc.poids.correlations),
  };
}

// ───────────────────────────────────────────────────────────────────────────
//  Tests
// ───────────────────────────────────────────────────────────────────────────

void main() {
  late Directory tmpDir;

  setUp(() async {
    // Garde-fou : les clés ELO écrites en dur dans ce fichier doivent être
    // exactement celles produites par la normalisation réelle du service.
    expect(_cleElo('Alpha', 'Trot Attelé'), 'ALPHA|TROT_ATTELE');
    expect(_cleElo('Bravo', 'Trot Attelé'), 'BRAVO|TROT_ATTELE');
    expect(_cleElo('Charlie', 'Trot Attelé'), 'CHARLIE|TROT_ATTELE');

    tmpDir = await Directory.systemTemp.createTemp('v5_backup_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
    SharedPreferences.setMockInitialValues({});
    // Le repository est un singleton : `_charge` et `_items` survivent d'un
    // test à l'autre. On le vide par son API publique, puis on retire la clé
    // du disque pour repartir d'un appareil réellement vierge.
    await PronosticResultatsRepository.instance
        .restaurerDepuisBackup({'pronosticResultats': []});
    final prefsInit = await SharedPreferences.getInstance();
    await prefsInit.remove(PronosticResultatsRepository.storageKey);
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
    await _installerElo(kEloAttendus);
    await IaMemoryService.instance.recharger();
  });

  tearDown(() async {
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T1 — Cycle complet : export → fichier JSON → restauration → reload
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T1 — cycle complet export → fichier → restauration → rechargement', () async {
    final pronostics = [
      _pronostic(courseKey: 'R1C1_10032026', avecResultat: true),
      _pronostic(courseKey: 'R2C3_10032026'),
    ];

    SharedPreferences.setMockInitialValues(_prefsCompletes(
      pronostics: pronostics,
      poidsJson: _poidsPersonnalise(),
      seuilsJson: _seuilsPersonnalises().toJson(),
      journal: [_journal(0), _journal(1)],
      precision: {
        'Quinté+': _precision('Quinté+', 9, 4),
        'Tiercé': _precision('Tiercé', 6, 3),
      },
      labels: {'🥇 FAVORI IA': _label('🥇 FAVORI IA', 9, 4, 7, 8)},
    ));
    await _installerElo(kEloAttendus);
    await IaMemoryService.instance.recharger();

    expect(IaMemoryService.instance.pronostics.length, 2,
        reason: 'état de départ non chargé — le test serait muet');

    final export = await BackupService.instance.exporterDonnees();
    expect(export.succes, isTrue, reason: 'exporterDonnees a échoué');
    expect(export.filePath, isNotNull);
    expect(export.tailleOctets, greaterThan(0));

    final fichier = File(export.filePath!);
    expect(await fichier.exists(), isTrue,
        reason: 'le fichier JSON doit exister sur le disque');
    expect(export.fileName, contains('backup_pronostic_hippique_'));
    expect(export.fileName, endsWith('.json'));

    final contenu = json.decode(await fichier.readAsString()) as Map<String, dynamic>;
    expect(contenu['appName'], 'Pronostic Hippique');
    expect(contenu['version'], isNotNull);
    expect(contenu['dateBackup'], isNotNull);
    for (final groupe in [
      'ia', 'configIA', 'paris', 'alertes', 'profil', 'widget',
      'laboIA', 'auditCache', 'grosParis', 'elo_service', 'cote',
    ]) {
      expect(contenu.containsKey(groupe), isTrue,
          reason: 'groupe "$groupe" absent du JSON exporté');
    }

    // ── Appareil vierge : on efface tout ────────────────────────────────
    SharedPreferences.setMockInitialValues({});
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
    expect(IaMemoryService.instance.pronostics, isEmpty);
    expect(EloService.instance.exporterPourBackup(), isEmpty);

    // ── Restauration par la vraie API publique ──────────────────────────
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(
        name: export.fileName!,
        size: export.tailleOctets,
        bytes: Uint8List.fromList(await fichier.readAsBytes()),
      ),
    ]));

    final import = await BackupService.instance.importerDepuisFichier();
    expect(import.succes, isTrue,
        reason: 'import échoué : ${import.erreur}');
    expect(import.nbPronosticsIA, 2);

    // ── rechargement de la mémoire IA ───────────────────────────────────
    expect(IaMemoryService.instance.pronostics.length, 2,
        reason: 'la mémoire IA doit être rechargée par _restaurerDepuisJson');
    expect(
      IaMemoryService.instance.pronostics.map((p) => p.courseKey).toList(),
      ['R1C1_10032026', 'R2C3_10032026'],
      reason: 'ordre et contenu des pronostics restaurés',
    );
    expect(EloService.instance.exporterPourBackup().length, 3,
        reason: 'les 3 ratings ELO doivent être restaurés');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T2 — Conservation EXACTE (pronostics, scores, 19 critères,
  //          ELO, poids, seuils, journal)
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T2 — conservation exacte de toutes les données IA et ELO', () async {
    final pronosticsSource = [
      _pronostic(courseKey: 'R1C1_10032026', avecResultat: true),
      _pronostic(courseKey: 'R3C5_10032026'),
    ];
    final poidsJson = _poidsPersonnalise();
    final seuilsJson = _seuilsPersonnalises().toJson();
    final journalSource = [_journal(0), _journal(1), _journal(2)];

    SharedPreferences.setMockInitialValues(_prefsCompletes(
      pronostics: pronosticsSource,
      poidsJson: poidsJson,
      seuilsJson: seuilsJson,
      journal: journalSource,
      precision: {
        'Quinté+': _precision('Quinté+', 9, 4),
        'Tiercé': _precision('Tiercé', 6, 3),
        'Simple Gagnant': _precision('Simple Gagnant', 4, 2),
      },
      labels: {
        '🥇 FAVORI IA': _label('🥇 FAVORI IA', 9, 4, 7, 8),
        '⚡ Coup préparé possible': _label('⚡ Coup préparé possible', 5, 1, 3, 4),
      },
    ));
    await _installerElo(kEloAttendus);
    await IaMemoryService.instance.recharger();

    final export = await BackupService.instance.exporterDonnees();
    expect(export.succes, isTrue);
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(
        name: export.fileName!,
        size: export.tailleOctets,
        bytes: Uint8List.fromList(await File(export.filePath!).readAsBytes()),
      ),
    ]));

    SharedPreferences.setMockInitialValues({});
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();

    final import = await BackupService.instance.importerDepuisFichier();
    expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

    final svc = IaMemoryService.instance;
    final restaures = svc.pronostics;
    expect(restaures.length, 2);

    for (var i = 0; i < pronosticsSource.length; i++) {
      final src = pronosticsSource[i];
      final dst = restaures[i];

      // ── Identité du pronostic ────────────────────────────────────────
      expect(dst.courseKey, src.courseKey, reason: 'courseKey #$i');
      expect(dst.nomCourse, src.nomCourse, reason: 'nomCourse #$i');
      expect(dst.hippodrome, src.hippodrome, reason: 'hippodrome #$i');
      expect(dst.discipline, src.discipline, reason: 'discipline #$i');
      expect(dst.datePronostic.toIso8601String(),
          src.datePronostic.toIso8601String(), reason: 'datePronostic #$i');

      // ── Scores IA (numéro → score, au bit près) ──────────────────────
      expect(dst.scoresIA.keys.toSet(), src.scoresIA.keys.toSet(),
          reason: 'clés scoresIA #$i');
      for (final num in src.scoresIA.keys) {
        expect(dst.scoresIA[num], src.scoresIA[num],
            reason: 'scoresIA["$num"] #$i');
      }

      // ── Les 19 critères, champ par champ ─────────────────────────────
      expect(dst.scoresCriteres.length, src.scoresCriteres.length,
          reason: 'nb chevaux avec critères #$i');
      for (final num in src.scoresCriteres.keys) {
        final a = src.scoresCriteres[num]!;
        final b = dst.scoresCriteres[num]!;
        expect(kClesCourt.length, 19, reason: 'le contrat est bien 19 critères');
        // comparaison exhaustive via le JSON canonique des 19 clés
        expect(json.encode(b.toJson()), json.encode(a.toJson()),
            reason: 'les 19 critères du cheval $num (#$i) doivent être identiques');
        // contrôle explicite champ par champ (détecte une clé oubliée)
        expect(b.forme, a.forme);
        expect(b.gains, a.gains);
        expect(b.record, a.record);
        expect(b.cote, a.cote);
        expect(b.constance, a.constance);
        expect(b.victoires, a.victoires);
        expect(b.discipline, a.discipline);
        expect(b.distSpec, a.distSpec);
        expect(b.jockey, a.jockey);
        expect(b.repos, a.repos);
        expect(b.hippo, a.hippo);
        expect(b.entraineur, a.entraineur);
        expect(b.elo, a.elo);
        expect(b.terrain, a.terrain);
        expect(b.divergence, a.divergence);
        expect(b.poidsRel, a.poidsRel);
        expect(b.progression, a.progression);
        expect(b.mouvCote, a.mouvCote);
        expect(b.placeDepart, a.placeDepart);
      }

      // ── Métriques et résultat réel ───────────────────────────────────
      expect(dst.varianceScores, src.varianceScores);
      expect(dst.resultatsReels, src.resultatsReels);
      expect(dst.arriveeReelle, src.arriveeReelle);
      expect(dst.dateResultat?.toIso8601String(),
          src.dateResultat?.toIso8601String());
      expect(dst.rangFavoriIaDansArrivee, src.rangFavoriIaDansArrivee);
      expect(dst.nbTop3DansArriveeReelle, src.nbTop3DansArriveeReelle);
      expect(dst.nbTop5DansArriveeReelle, src.nbTop5DansArriveeReelle);
      expect(dst.scorePerformance, src.scorePerformance);
      expect(dst.confiancePredite, src.confiancePredite);
      expect(dst.typePariConseille, src.typePariConseille);
      expect(dst.tauxReussiteAuMoment, src.tauxReussiteAuMoment);
      expect(dst.precisionIA, src.precisionIA);
      expect(dst.favoriIaNom, src.favoriIaNom);
      expect(dst.coteFavoriPmu, src.coteFavoriPmu);
      expect(dst.cotesPmuParNumero, src.cotesPmuParNumero);
    }

    // ── ELO : les 3 ratings, au bit près ────────────────────────────────
    final elo = EloService.instance.exporterPourBackup();
    expect(elo.length, kEloAttendus.length,
        reason: 'le nombre de ratings ELO doit être conservé');
    kEloAttendus.forEach((cle, rating) {
      expect(elo.containsKey(cle), isTrue, reason: 'rating "$cle" manquant');
      final score = EloService.instance.getScore(
        cle.split('|').first,
        discipline: 'Trot Attelé',
      );
      expect(score.rating, rating, reason: 'rating "$cle"');
      expect(score.nbCourses, 17, reason: 'nbCourses "$cle"');
      expect(score.variationMois, 12.5, reason: 'variationMois "$cle"');
    });

    // ── Poids adaptatifs : JSON canonique identique ─────────────────────
    expect(json.encode(svc.poids.toJson()), json.encode(poidsJson),
        reason: 'les poids adaptatifs doivent être identiques au bit près');
    expect(svc.poids.nbMisesAJour, 137);
    expect(svc.poids.calibrationScore, 68.3125);
    expect(svc.poids.dernierGradient, {'forme': 0.0125, 'elo': -0.0075});
    expect(svc.poids.correlations, {'forme|cote': 0.4125, 'elo|gains': -0.1875});
    expect(svc.poids.poidsIndices.poidsCriteres, 0.4321);
    expect(svc.poids.poidsParDiscipline['TROT_ATTELE']?['forme'], 0.30);

    // ── Seuils adaptatifs : JSON canonique identique ────────────────────
    expect(json.encode(svc.seuilsConfiance.toJson()), json.encode(seuilsJson),
        reason: 'les seuils doivent être identiques au bit près');
    expect(svc.seuilsConfiance.seuilSimpleGagnant, 83.5);
    expect(svc.seuilsConfiance.seuilTierce, 27.25);
    expect(svc.seuilsConfiance.seuilQuarte, 86.875);

    // ── Journal d'apprentissage ─────────────────────────────────────────
    expect(svc.journal.length, 3, reason: 'journal : 3 entrées attendues');
    final journalRestitue = svc.journal.reversed.toList(); // ordre de stockage
    for (var i = 0; i < journalSource.length; i++) {
      expect(json.encode(journalRestitue[i].toJson()),
          json.encode(journalSource[i].toJson()),
          reason: 'entrée de journal #$i identique');
    }

    // ── Précision par type et stats par label ───────────────────────────
    expect(svc.precisionParType.length, 3, reason: '3 types de pari');
    final q = svc.precisionParType.firstWhere((p) => p.typePari == 'Quinté+');
    expect(q.nbTotal, 9);
    expect(q.nbBons, 4);
    expect(svc.statsParLabel.length, 2, reason: '2 labels IA');
    final fav = svc.statsParLabel.firstWhere((l) => l.label == '🥇 FAVORI IA');
    expect(fav.nbTotal, 9);
    expect(fav.nbTop1, 4);
    expect(fav.nbTop3, 7);
    expect(fav.nbTop5, 8);
    expect(svc.statsParType.length, 1, reason: 'stats par type de pari');
    expect(svc.statsParType.first.nbJoues, 21);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  Outils pour T3 → T7
  // ═══════════════════════════════════════════════════════════════════════

  /// Prefs représentant un appareil dont les pronostics sont stockés en
  /// gzip+base64 (clé `ia_pronostics_v2_gz`), format actuel de `_save()`.
  Map<String, Object> prefsGzip(List<IaPronostic> pronostics) => <String, Object>{
        'ia_precision_migrated_v3': true,
        'ia_poids_v3': json.encode(_poidsPersonnalise()),
        'ia_seuils_v1': json.encode(_seuilsPersonnalises().toJson()),
        'ia_pronostics_v2_gz': _gzEncode(pronostics),
        'ia_journal_v2': [_journal(0)].map((j) => json.encode(j.toJson())).toList(),
        'ia_precision_v2': json.encode({}),
        'ia_stats_labels_v1': json.encode({}),
        'ia_stats_types_v1': <String>[],
      };

  /// Prefs « ancien format » : pronostics en StringList JSON, pas de gzip.
  Map<String, Object> prefsJson(List<IaPronostic> pronostics) => <String, Object>{
        'ia_precision_migrated_v3': true,
        'ia_poids_v3': json.encode(_poidsPersonnalise()),
        'ia_seuils_v1': json.encode(_seuilsPersonnalises().toJson()),
        'ia_pronostics_v2':
            pronostics.map((p) => json.encode(p.toJson())).toList(),
        'ia_journal_v2': [_journal(0)].map((j) => json.encode(j.toJson())).toList(),
        'ia_precision_v2': json.encode({}),
        'ia_stats_labels_v1': json.encode({}),
        'ia_stats_types_v1': <String>[],
      };

  /// Exporte l'état courant en fichier, prêt à être réimporté.
  Future<(ExportResult, Uint8List)> exporterVersMemoire() async {
    final export = await BackupService.instance.exporterDonnees();
    expect(export.succes, isTrue, reason: 'export échoué : ${export.erreur}');
    final bytes = await File(export.filePath!).readAsBytes();
    return (export, bytes);
  }

  /// Importer en passant par la VRAIE API publique (FilePicker injecté).
  Future<ImportResult> restaurerDepuis(ExportResult export, Uint8List bytes) {
    FilePicker.platform = _FakeFilePicker(FilePickerResult([
      PlatformFile(name: export.fileName!, size: bytes.length, bytes: bytes),
    ]));
    return BackupService.instance.importerDepuisFichier();
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T3 — Ancien backup JSON restauré sur un appareil déjà en gzip
  //
  //  Comportement ATTENDU : après restauration, la mémoire IA doit exposer
  //  les 5 pronostics du backup. Ce test doit donc être ROUGE si le résidu
  //  gzip local conserve la priorité de lecture (ia_memory_service.dart:1325).
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T3 — backup JSON-only restauré sur un appareil qui a déjà du gzip',
      () async {
    // ── Appareil SOURCE : 5 pronostics en JSON (format ancien) ────────────
    final pronosticsBackup = List.generate(
      5,
      (i) => _pronostic(courseKey: 'RSRC${i}_10032026'),
    );
    SharedPreferences.setMockInitialValues(prefsJson(pronosticsBackup));
    await _installerElo(kEloAttendus);
    await IaMemoryService.instance.recharger();

    final (export, bytes) = await exporterVersMemoire();

    // Le fichier exporté est bien au format JSON-only
    final contenu = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    final ia = contenu['ia'] as Map<String, dynamic>;
    expect(ia.containsKey('ia_pronostics_v2'), isTrue,
        reason: 'version JSON doit contenir ia_pronostics_v2');
    expect(ia.containsKey('ia_pronostics_v2_gz'), isFalse,
        reason: 'version JSON ne doit PAS contenir la clé gzip');

    // ── Appareil CIBLE : 25 pronostics LOCAUX déjà en gzip ────────────────
    final pronosticsLocaux = List.generate(
      25,
      (i) => _pronostic(courseKey: 'RLOC${i}_10032026'),
    );
    SharedPreferences.setMockInitialValues(prefsGzip(pronosticsLocaux));
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
    expect(IaMemoryService.instance.pronostics.length, 25,
        reason: 'les 25 pronostics locaux gzip doivent être chargés');

    // ── Restauration de l'ancien backup ───────────────────────────────────
    final import = await restaurerDepuis(export, bytes);
    expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

    final prefs = await SharedPreferences.getInstance();
    final gzRestant = prefs.getString('ia_pronostics_v2_gz');
    final jsonRestaure = prefs.getStringList('ia_pronostics_v2');
    final enMemoire = IaMemoryService.instance.pronostics;

    // Diagnostic (toujours affiché pour le rapport)
    // ignore: avoid_print
    print('  [T3] gz local présent après restauration : ${gzRestant != null}');
    // ignore: avoid_print
    print('  [T3] ia_pronostics_v2 restauré : ${jsonRestaure?.length} entrées');
    // ignore: avoid_print
    print('  [T3] mémoire IA après restauration : ${enMemoire.length} pronostics '
        '(RSRC=${enMemoire.where((p) => p.courseKey.startsWith('RSRC')).length}, '
        'RLOC=${enMemoire.where((p) => p.courseKey.startsWith('RLOC')).length})');
    // ignore: avoid_print
    print('  [T3] ImportResult.nbPronosticsIA annoncé à l\'UI : '
        '${import.nbPronosticsIA}');

    // Le backup a bien été écrit sur le disque
    expect(jsonRestaure, isNotNull);
    expect(jsonRestaure!.length, 5,
        reason: 'les 5 pronostics du backup sont écrits dans ia_pronostics_v2');

    // ★ EXIGENCE 4 — LA MÉMOIRE DOIT EXPOSER LES DONNÉES RESTAURÉES
    expect(enMemoire.length, 5,
        reason: 'la mémoire IA doit afficher les 5 pronostics RESTAURÉS, '
            'pas les 25 pronostics locaux');
    expect(enMemoire.every((p) => p.courseKey.startsWith('RSRC')), isTrue,
        reason: 'aucun pronostic local (RLOC) ne doit subsister en mémoire');

    // ★ Le compte annoncé à l'utilisateur doit être exact
    expect(import.nbPronosticsIA, 5,
        reason: 'nbPronosticsIA doit refléter le backup, pas le résidu local');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T4 — Backup gzip restauré sur un appareil JSON-only
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T4 — backup gzip restauré sur un appareil JSON-only', () async {
    // ── Appareil SOURCE : 25 pronostics → _save() écrit en gzip ───────────
    final pronosticsBackup = List.generate(
      25,
      (i) => _pronostic(courseKey: 'RSRC${i}_10032026'),
    );
    SharedPreferences.setMockInitialValues(prefsGzip(pronosticsBackup));
    await _installerElo(kEloAttendus);
    await IaMemoryService.instance.recharger();

    final (export, bytes) = await exporterVersMemoire();
    final contenu = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    final ia = contenu['ia'] as Map<String, dynamic>;
    expect(ia.containsKey('ia_pronostics_v2_gz'), isTrue,
        reason: 'la source en gzip doit exporter la clé gzip');
    expect(ia.containsKey('ia_pronostics_v2'), isFalse,
        reason: 'la source en gzip ne doit pas avoir la clé JSON');

    // ── Appareil CIBLE : 4 pronostics locaux en JSON ──────────────────────
    final pronosticsLocaux = List.generate(
      4,
      (i) => _pronostic(courseKey: 'RLOC${i}_10032026'),
    );
    SharedPreferences.setMockInitialValues(prefsJson(pronosticsLocaux));
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
    expect(IaMemoryService.instance.pronostics.length, 4);

    final import = await restaurerDepuis(export, bytes);
    expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

    final prefs = await SharedPreferences.getInstance();
    final enMemoire = IaMemoryService.instance.pronostics;
    final residuJson = prefs.getStringList('ia_pronostics_v2');

    // ignore: avoid_print
    print('  [T4] gz restauré présent : '
        '${prefs.getString('ia_pronostics_v2_gz') != null}');
    // ignore: avoid_print
    print('  [T4] résidu ia_pronostics_v2 local : ${residuJson?.length} entrées');
    // ignore: avoid_print
    print('  [T4] mémoire IA après restauration : ${enMemoire.length} pronostics '
        '(RSRC=${enMemoire.where((p) => p.courseKey.startsWith('RSRC')).length}, '
        'RLOC=${enMemoire.where((p) => p.courseKey.startsWith('RLOC')).length})');

    // ★ EXIGENCE 4 (sens strict) — les données RESTAURÉES gagnent la lecture
    expect(prefs.getString('ia_pronostics_v2_gz'), isNotNull,
        reason: 'la clé gzip doit avoir été restaurée');
    expect(enMemoire.length, 25,
        reason: 'les 25 pronostics du backup gzip doivent être chargés');
    expect(enMemoire.every((p) => p.courseKey.startsWith('RSRC')), isTrue,
        reason: 'aucun pronostic local (RLOC) ne doit apparaître en mémoire');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T4b — Résidu du format opposé non purgé : risque de résurrection
  //
  //  Ce n'est pas une violation de l'exigence 4 (les données restaurées
  //  gagnent bien la lecture), mais un risque réel : si la clé gzip venait
  //  à manquer ou à être corrompue, le fallback de _load() (l.1338)
  //  ressusciterait les pronostics d'un AUTRE état de l'appareil.
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T4b — résidu du format opposé non purgé (risque de fallback)',
      () async {
    // Source gzip
    SharedPreferences.setMockInitialValues(prefsGzip(
      List.generate(25, (i) => _pronostic(courseKey: 'RSRC${i}_10032026')),
    ));
    await IaMemoryService.instance.recharger();
    final (export, bytes) = await exporterVersMemoire();

    // Cible JSON
    SharedPreferences.setMockInitialValues(prefsJson(
      List.generate(4, (i) => _pronostic(courseKey: 'RLOC${i}_10032026')),
    ));
    await IaMemoryService.instance.recharger();

    final import = await restaurerDepuis(export, bytes);
    expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

    final prefs = await SharedPreferences.getInstance();
    final residu = prefs.getStringList('ia_pronostics_v2');

    // ignore: avoid_print
    print('  [T4b] résidu ia_pronostics_v2 après restauration gzip : '
        '${residu?.length} entrées (attendu : absent)');

    expect(residu, isNull,
        reason: 'la clé ia_pronostics_v2 (format non compressé) doit être '
            'purgée quand le backup restaure ia_pronostics_v2_gz. Sinon, '
            '4 pronostics périmés peuvent réapparaître via le fallback '
            'de _load() (ia_memory_service.dart:1338)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T3b — Le nombre de pronostics ANNONCÉ à l'utilisateur
  //
  //  `_restaurerDepuisJson` (backup_service.dart:855-870) estime le nombre
  //  de pronostics restaurés par `gz.length / 130` sur ce qui reste dans
  //  SharedPreferences APRÈS restauration — pas sur le contenu du backup.
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T3b — nbPronosticsIA annoncé doit refléter le backup, pas le résidu',
      () async {
    // Source : 5 pronostics JSON → le backup contient exactement 5 pronostics
    final pronosticsBackup = List.generate(
      5,
      (i) => _pronostic(courseKey: 'RSRC${i}_10032026'),
    );
    SharedPreferences.setMockInitialValues(prefsJson(pronosticsBackup));
    await IaMemoryService.instance.recharger();
    final (export, bytes) = await exporterVersMemoire();

    // Cible : 25 pronostics locaux en gzip
    SharedPreferences.setMockInitialValues(prefsGzip(
      List.generate(25, (i) => _pronostic(courseKey: 'RLOC${i}_10032026')),
    ));
    await IaMemoryService.instance.recharger();

    final import = await restaurerDepuis(export, bytes);
    expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

    final prefs = await SharedPreferences.getInstance();
    final gz = prefs.getString('ia_pronostics_v2_gz') ?? '';
    final annonce = import.nbPronosticsIA;

    // ignore: avoid_print
    print('  [T3b] pronostics réellement dans le backup : 5');
    // ignore: avoid_print
    print('  [T3b] gz résiduel local : ${gz.length} caractères '
        '→ estimation ${(gz.length / 130).round()}');
    // ignore: avoid_print
    print('  [T3b] ImportResult.nbPronosticsIA annoncé : $annonce');

    expect(annonce, 5,
        reason: 'le nombre de pronostics restaurés affiché à l\'utilisateur '
            'doit être celui du backup (5), pas l\'estimation du résidu gzip '
            'local (${(gz.length / 130).round()})');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T5 — Autres résidus locaux : clés absentes du backup
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T5 — clés locales absentes du backup : jamais purgées', () async {
    // Appareil cible : possède des rapports, bilans et un figeage premium
    // que le backup ne contient PAS.
    SharedPreferences.setMockInitialValues({
      ...prefsJson([_pronostic(courseKey: 'RLOC_10032026')]),
      'ia_rapports_v1': <String>[
        json.encode({
          'date': DateTime(2026, 3, 1).toIso8601String(),
          'nb': 1,
          'nbR': 1,
          'nbP': 1,
          'fg': 1,
          'ft3': 1,
          'ft5': 1,
          't3c': 1,
          't5c': 1,
          'sm': 60.0,
          'disc': <Map<String, dynamic>>[],
          'mpu': 1,
          'poids': <String, double>{},
          'nbE': 0,
        }),
      ],
      'premium_widgets_selection_jour_v1': json.encode({'2026-03-01': {}}),
      'ia_bilans_semaine_v1': <String>[],
    });
    await IaMemoryService.instance.recharger();
    expect(IaMemoryService.instance.rapports.length, 1,
        reason: 'état de départ : 1 rapport local');

    // Backup vide de rapports (appareil source sans rapport)
    SharedPreferences.setMockInitialValues(prefsJson([
      _pronostic(courseKey: 'RSRC_10032026'),
    ]));
    await IaMemoryService.instance.recharger();
    final (export, bytes) = await exporterVersMemoire();
    final contenu = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect((contenu['ia'] as Map<String, dynamic>).containsKey('ia_rapports_v1'),
        isFalse,
        reason: 'le backup ne contient pas ia_rapports_v1');

    // Retour sur l'appareil cible
    SharedPreferences.setMockInitialValues({
      ...prefsJson([_pronostic(courseKey: 'RLOC_10032026')]),
      'ia_rapports_v1': <String>[
        json.encode({
          'date': DateTime(2026, 3, 1).toIso8601String(),
          'nb': 1,
          'nbR': 1,
          'nbP': 1,
          'fg': 1,
          'ft3': 1,
          'ft5': 1,
          't3c': 1,
          't5c': 1,
          'sm': 60.0,
          'disc': <Map<String, dynamic>>[],
          'mpu': 1,
          'poids': <String, double>{},
          'nbE': 0,
        }),
      ],
      'premium_widgets_selection_jour_v1': json.encode({'2026-03-01': {}}),
    });
    await IaMemoryService.instance.recharger();

    final import = await restaurerDepuis(export, bytes);
    expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

    final prefs = await SharedPreferences.getInstance();

    // ★ Les données locales non présentes dans le backup survivent
    expect(prefs.getStringList('ia_rapports_v1'), isNotNull,
        reason: 'ia_rapports_v1 local doit survivre (absent du backup)');
    expect(IaMemoryService.instance.rapports.length, 1,
        reason: 'le rapport local reste affiché après restauration');
    expect(prefs.getString('premium_widgets_selection_jour_v1'), isNotNull,
        reason: 'le figeage premium local survit');

    // En revanche, les clés PRÉSENTES dans le backup sont bien écrasées
    expect(IaMemoryService.instance.pronostics.length, 1);
    expect(IaMemoryService.instance.pronostics.first.courseKey, 'RSRC_10032026',
        reason: 'la clé présente dans le backup est bien écrasée');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T6 — Poids / seuils / ELO : écrasés, jamais fusionnés avec le local
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T6 — poids, seuils et ELO restauration = écrasement, pas fusion',
      () async {
    // Appareil SOURCE avec poids/seuils/ELO de référence
    SharedPreferences.setMockInitialValues(
        prefsJson([_pronostic(courseKey: 'RSRC_10032026')]));
    await _installerElo(kEloAttendus);
    await IaMemoryService.instance.recharger();
    final (export, bytes) = await exporterVersMemoire();

    // Appareil CIBLE avec des valeurs LOCALES différentes
    final poidsLocal = IaPoidsAdaptatifs.defaut();
    poidsLocal.nbMisesAJour = 999;
    poidsLocal.calibrationScore = 11.0;
    poidsLocal.forme = 0.50;
    SharedPreferences.setMockInitialValues({
      ...prefsJson([_pronostic(courseKey: 'RLOC_10032026')]),
      'ia_poids_v3': json.encode(poidsLocal.toJson()),
      'ia_seuils_v1': json.encode(SeuilsConfianceAdaptatifs(
        seuilSimpleGagnant: 91.0,
        seuilGagnantPlace: 74.0,
      ).toJson()),
    });
    await EloService.instance.importerDepuisBackup({
      'LOCAL|TROT_ATTELE':
          const EloScore(nomCheval: 'LOCAL', rating: 2100.0).toJson(),
      'AUTRE|PLAT':
          const EloScore(nomCheval: 'AUTRE', rating: 2450.0).toJson(),
    });
    await IaMemoryService.instance.recharger();
    expect(IaMemoryService.instance.poids.nbMisesAJour, 999,
        reason: 'état de départ : poids locaux chargés');
    expect(EloService.instance.exporterPourBackup().length, 2);

    final import = await restaurerDepuis(export, bytes);
    expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

    // ★ Poids : écrasés (137), pas fusionnés avec 999
    expect(IaMemoryService.instance.poids.nbMisesAJour, 137,
        reason: 'les poids restaurés remplacent intégralement les locaux');
    expect(IaMemoryService.instance.poids.calibrationScore, 68.3125);
    expect(IaMemoryService.instance.poids.forme, 0.2711,
        reason: 'le poids forme local (0.50) ne doit pas subsister');

    // ★ Seuils : écrasés (83.5), pas 91.0
    expect(IaMemoryService.instance.seuilsConfiance.seuilSimpleGagnant, 83.5,
        reason: 'les seuils restaurés remplacent intégralement les locaux');

    // ★ ELO : importerDepuisBackup() fait clear() puis écrit → 3, pas 2+3
    final elo = EloService.instance.exporterPourBackup();
    expect(elo.length, kEloAttendus.length,
        reason: 'les ELO locaux doivent être remplacés, pas additionnés');
    expect(elo.containsKey('LOCAL|TROT_ATTELE'), isFalse,
        reason: 'l\'ELO local doit disparaître');
    expect(elo.containsKey('AUTRE|PLAT'), isFalse,
        reason: 'l\'ELO local doit disparaître');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T7 — La restauration ne déclenche AUCUN apprentissage
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T7 — la restauration ne déclenche aucun apprentissage ni recalcul',
      () async {
    // Appareil SOURCE avec un état d'apprentissage bien identifiable
    SharedPreferences.setMockInitialValues(_prefsCompletes(
      pronostics: [
        _pronostic(courseKey: 'RSRC1_10032026', avecResultat: true),
        _pronostic(courseKey: 'RSRC2_10032026', avecResultat: true),
      ],
      poidsJson: _poidsPersonnalise(),
      seuilsJson: _seuilsPersonnalises().toJson(),
      journal: [_journal(0), _journal(1)],
      precision: {'Quinté+': _precision('Quinté+', 9, 4)},
      labels: {'🥇 FAVORI IA': _label('🥇 FAVORI IA', 9, 4, 7, 8)},
    ));
    await _installerElo(kEloAttendus);
    await IaMemoryService.instance.recharger();
    final (export, bytes) = await exporterVersMemoire();

    // Appareil CIBLE vierge
    SharedPreferences.setMockInitialValues({});
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();

    // Référence AVANT restauration
    final avant = _snapshotMemoire();

    final import = await restaurerDepuis(export, bytes);
    expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

    final apres = _snapshotMemoire();

    // ── Après restauration, l'état doit être EXACTEMENT celui du backup ──
    final poidsAttendu = json.encode(_poidsPersonnalise());
    final seuilsAttendus = json.encode(_seuilsPersonnalises().toJson());

    expect(apres['poids'], poidsAttendu,
        reason: 'les poids restaurés sont ceux du backup, sans dérive');
    expect(apres['seuils'], seuilsAttendus,
        reason: 'les seuils restaurés sont ceux du backup, sans dérive');
    expect(apres['nbMisesAJour'], 137,
        reason: 'aucune mise à jour de poids ne doit être comptée');
    expect(apres['calibration'], 68.3125,
        reason: 'aucune recalibration ne doit avoir lieu');
    expect(apres['dernierGradient'], json.encode({'forme': 0.0125, 'elo': -0.0075}),
        reason: 'aucun gradient ne doit avoir été calculé');
    expect(apres['correlations'], json.encode({'forme|cote': 0.4125, 'elo|gains': -0.1875}),
        reason: 'aucune corrélation ne doit avoir été recalculée');

    // ── Aucune entrée de journal supplémentaire ──────────────────────────
    expect(apres['journal'], 2,
        reason: 'le journal contient exactement les entrées du backup');
    expect(apres['rapports'], 0,
        reason: 'aucun rapport journalier ne doit être créé');
    expect(apres['bilansSemaine'], 0);
    expect(apres['bilansMois'], 0);

    // ── Les pronostics ne sont ni recalculés ni rejoués ──────────────────
    expect(apres['pronostics'], 2);
    expect(apres['avecResultat'], 2);
    final restaures = IaMemoryService.instance.pronostics;
    for (final p in restaures) {
      expect(p.courseKey.startsWith('RSRC'), isTrue,
          reason: 'aucun pronostic local ne doit apparaître');
      expect(p.scoresCriteres.length, 4,
          reason: 'les 19 critères restent ceux du backup, pas recalculés');
      // scoreIA du cheval 1 = 92.0 - 7.5 = 84.5 (valeur figée du backup)
      expect(p.scoresIA['1'], 84.5,
          reason: 'le score IA du backup n\'est pas recalculé');
      expect(p.scoresCriteres['1']!.forme, 62.5,
          reason: 'le critère forme du backup n\'est pas recalculé');
      expect(p.resultatsReels, isTrue,
          reason: 'aucun résultat ne doit être effacé ou rejoué');
    }

    // ── Symétrie : la référence "avant" doit différer, sinon le test est muet
    expect(avant['poids'], isNot(poidsAttendu),
        reason: 'l\'appareil cible doit bien être parti d\'un état différent');
    expect(avant['pronostics'], 0);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T8 — Effet de bord : flag de migration de précision absent
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T8 — flag ia_precision_migrated_v3 absent : recalcul de précision',
      () async {
    // Backup réel, puis suppression du flag dans le fichier exporté
    SharedPreferences.setMockInitialValues(_prefsCompletes(
      pronostics: [_pronostic(courseKey: 'RSRC_10032026', avecResultat: true)],
      poidsJson: _poidsPersonnalise(),
      seuilsJson: _seuilsPersonnalises().toJson(),
      journal: [_journal(0)],
      precision: {'Quinté+': _precision('Quinté+', 9, 4)},
      labels: {'🥇 FAVORI IA': _label('🥇 FAVORI IA', 9, 4, 7, 8)},
    ));
    await _installerElo(kEloAttendus);
    await IaMemoryService.instance.recharger();
    final (export, _) = await exporterVersMemoire();

    final contenu = json.decode(await File(export.filePath!).readAsString())
        as Map<String, dynamic>;
    final configIA = contenu['configIA'] as Map<String, dynamic>;
    final flagPresent = configIA.containsKey('ia_precision_migrated_v3');
    expect(flagPresent, isTrue,
        reason: 'le flag fait partie du backup — il sera restauré');

    // Vérification statique du déclencheur (ia_memory_service.dart:1453-1459)
    // if (!flagMigration && _pronostics.any((p) => p.resultatsReels))
    //   → _recalculerPrecisionParTypeDepuisPronostics() puis _save()
    //
    // Le flag étant présent ET restauré à true, la branche ne s'exécute pas :
    // c'est prouvé par V5/T7 (précision et poids inchangés).
    final poidsAvant = json.encode(IaMemoryService.instance.poids.toJson());
    final seuilsAvant = json.encode(IaMemoryService.instance.seuilsConfiance.toJson());

    final import = await restaurerDepuis(
        export, await File(export.filePath!).readAsBytes());
    expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('ia_precision_migrated_v3'), isTrue,
        reason: 'le flag doit être restauré à true');
    expect(json.encode(IaMemoryService.instance.poids.toJson()), poidsAvant,
        reason: 'aucune écriture de poids pendant la restauration');
    expect(json.encode(IaMemoryService.instance.seuilsConfiance.toJson()),
        seuilsAvant,
        reason: 'aucune écriture de seuils pendant la restauration');

    // ★ DÉFAUT POTENTIEL DOCUMENTÉ : si un backup ancien ne contient PAS le
    // flag, _load() exécute _recalculerPrecisionParTypeDepuisPronostics()
    // (qui appelle _save()). Ce n'est pas un apprentissage de gradient
    // (aucun _poids / _seuils modifié) mais c'est une écriture de données.
    expect(configIA.containsKey('ia_narrative_memory_v1'), isFalse,
        reason: 'les clés narratives absentes sont retirées (compat v10.65)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T9 — B4 : `pronostic_resultats_repository_v2` est réellement exporté
  //
  //  Avant B4, la clé figurait dans `_keysGrosParis` (backup_service.dart:315)
  //  mais AUCUNE boucle `_lireEntree()` ne la parcourait : les résultats
  //  gagnants/perdants, l'ordre exact, les numéros trouvés et les dates
  //  étaient donc perdus à la restauration.
  //
  //  Périmètre volontairement réduit à CETTE seule clé :
  //    • `home_best_bet_snapshot_v2` / `..._date_v2` → clés mortes, jamais
  //      écrites par l'app (0 occurrence hors déclaration) → hors sujet.
  //    • les 4 flags `ia_migration_*_done` → flags one-shot, recalculables,
  //      pas des données utilisateur → hors sujet.
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T9 — B4 : pronostic_resultats_repository_v2 est exportée', () async {
    SharedPreferences.setMockInitialValues(
        prefsJson([_pronostic(courseKey: 'RSRC_10032026')]));
    await IaMemoryService.instance.recharger();

    // 3 résultats réels dans le repository (2 gagnants, 1 perdant)
    final repo = PronosticResultatsRepository.instance;
    await repo.ajouterOuRemplacer(_resultat(
      courseKey: 'R1C1_10032026',
      typePari: 'Quinté+',
      source: 'grosParisSurveiller',
      date: DateTime(2026, 3, 10, 13, 45),
      gagnant: true,
      ordreExact: true,
      nbTrouves: 5,
      nbRequis: 5,
      utilisableStats: false,
    ));
    await repo.ajouterOuRemplacer(_resultat(
      courseKey: 'R2C4_10032026',
      typePari: 'Tiercé',
      source: 'grosParisSurveiller',
      date: DateTime(2026, 3, 11, 15, 20),
      gagnant: true,
      nbTrouves: 3,
      nbRequis: 3,
    ));
    await repo.ajouterOuRemplacer(_resultat(
      courseKey: 'R3C2_10032026',
      typePari: 'Quarté+',
      source: 'programme',
      date: DateTime(2026, 3, 12, 12, 5),
      gagnant: false,
      nbTrouves: 1,
      nbRequis: 4,
      utilisableApprentissage: true,
    ));
    expect(repo.tous.length, 3);

    final (_, bytes) = await exporterVersMemoire();
    final contenu = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;

    // La clé n'est PAS dans un groupe de type SharedPreferences (elle est
    // sérialisée par le repository, comme EloService) : on la cherche donc
    // là où B4 l'a placée.
    expect(contenu.containsKey('resultatsGrosParis'), isTrue,
        reason: 'B4 : les résultats utilisateur doivent figurer dans le backup');

    // Et AUCUNE autre clé de _keysGrosParis n'a été ajoutée : le périmètre
    // de la correction reste strictement celui demandé.
    final toutesCles = <String>{};
    for (final groupe in contenu.values) {
      if (groupe is Map) {
        for (final k in groupe.keys) {
          if (k is String) toutesCles.add(k);
        }
      }
    }
    for (final interdite in [
      'home_best_bet_snapshot_v2',
      'home_best_bet_snapshot_date_v2',
      'ia_migration_gros_paris_desordre_v1_done',
      'ia_migration_gros_paris_stats_v2_done',
      'ia_migration_gros_paris_types_derives_v1_done',
      'ia_migration_suite_ia_classique_v1_done',
    ]) {
      expect(toutesCles.contains(interdite), isFalse,
          reason: 'B4 ne doit pas ressusciter la clé morte/flag "$interdite"');
    }

    final bloc = contenu['resultatsGrosParis'] as Map<String, dynamic>;
    expect(bloc['nbResultats'], 3);
    expect(bloc['nbGagnants'], 2);
    expect((bloc['pronosticResultats'] as List).length, 3);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T13 — Cycle complet EXPORT → RESTAURATION → RECHARGEMENT
  //            sur les résultats Gros Paris, avec intégrité exacte
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T13 — cycle complet des résultats Gros Paris, intégrité exacte',
      () async {
    final dateGagnant = DateTime(2026, 3, 10, 13, 45, 12);
    final datePerdant = DateTime(2026, 3, 11, 16, 0, 0);

    final source = [
      _resultat(
        courseKey: 'R1C1_10032026',
        typePari: 'Quinté+',
        source: 'grosParisSurveiller',
        date: dateGagnant,
        gagnant: true,
        ordreExact: true,
        nbTrouves: 5,
        nbRequis: 5,
        predictionIA: const ['7', '12', '3', '9', '1'],
        arrivee: const ['7', '12', '3', '9', '1'],
        utilisableStats: false,
      ),
      _resultat(
        courseKey: 'R4C2_11032026',
        typePari: 'Quarté+',
        source: 'grosParisSurveiller',
        date: datePerdant,
        gagnant: false,
        nbTrouves: 2,
        nbRequis: 4,
        predictionIA: const ['5', '8', '2', '14', '6'],
        arrivee: const ['8', '14', '5', '1', '2'],
      ),
    ];

    SharedPreferences.setMockInitialValues(
        prefsJson([_pronostic(courseKey: 'RSRC_10032026')]));
    await _installerElo(kEloAttendus);
    await IaMemoryService.instance.recharger();
    for (final r in source) {
      await PronosticResultatsRepository.instance.ajouterOuRemplacer(r);
    }
    expect(PronosticResultatsRepository.instance.tous.length, 2);

    // ── Captures AVANT export ───────────────────────────────────────────
    final avant = PronosticResultatsRepository.instance
        .exporterPourBackup()['pronosticResultats'] as List;

    final (export, bytes) = await exporterVersMemoire();

    // ── Appareil vierge, y compris le repository ────────────────────────
    SharedPreferences.setMockInitialValues({});
    await PronosticResultatsRepository.instance
        .restaurerDepuisBackup({'pronosticResultats': []});
    expect(PronosticResultatsRepository.instance.tous, isEmpty);

    // ── Restauration par la vraie API ───────────────────────────────────
    final import = await restaurerDepuis(export, bytes);
    expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

    final apres = PronosticResultatsRepository.instance;
    expect(apres.tous.length, 2, reason: 'les 2 résultats doivent revenir');

    // ── Intégrité champ par champ, sans doublon ─────────────────────────
    final quint = apres.tous
        .firstWhere((e) => e.courseKey == 'R1C1_10032026' && e.typePari == 'Quinté+');
    expect(quint.gagnant, isTrue);
    expect(quint.ordreExact, isTrue);
    expect(quint.nbTrouves, 5);
    expect(quint.nbRequis, 5);
    expect(quint.source, 'grosParisSurveiller');
    expect(quint.dateCourse, dateGagnant,
        reason: 'la date doit être conservée à la seconde près');
    expect(quint.predictionIA, const ['7', '12', '3', '9', '1']);
    expect(quint.arriveePMUComplete, const ['7', '12', '3', '9', '1']);
    expect(quint.utilisableStatsUtilisateur, isFalse);
    expect(quint.utilisableApprentissage, isFalse,
        reason: 'grosParisSurveiller ne doit JAMAIS alimenter le gradient');

    final quarte = apres.tous
        .firstWhere((e) => e.courseKey == 'R4C2_11032026' && e.typePari == 'Quarté+');
    expect(quarte.gagnant, isFalse, reason: 'un perdant doit le rester');
    expect(quarte.ordreExact, isFalse);
    expect(quarte.nbTrouves, 2);
    expect(quarte.nbRequis, 4);
    expect(quarte.dateCourse, datePerdant);
    expect(quarte.predictionIA, const ['5', '8', '2', '14', '6']);
    expect(quarte.arriveePMUComplete, const ['8', '14', '5', '1', '2']);

    // ── Aucun doublon : comparaison octet à octet avec l'état d'origine ──
    final apresBrut = apres.exporterPourBackup()['pronosticResultats'] as List;
    expect(json.encode(apresBrut), json.encode(avant),
        reason: 'sérialisation identique = ni perte, ni doublon, ni recalcul');

    // ── Idempotence du dédoublonnage (clé courseKey|typePari|source) ────
    final dedoublonnes =
        PronosticResultatsRepository.dedoublonnerParCourseTypeSource(
            apres.tous);
    expect(dedoublonnes.length, 2,
        reason: 'le dédoublonnage ne doit rien supprimer sur des clés uniques');

    // ── Rechargement depuis le disque (persistance réelle) ──────────────
    final brutDisque = (await SharedPreferences.getInstance())
        .getString(PronosticResultatsRepository.storageKey);
    expect(brutDisque, isNotNull);
    final relu = json.decode(brutDisque!) as List;
    expect(relu.length, 2);
    expect(json.encode(relu), json.encode(avant));

    // ── Aucune retombée sur l'apprentissage ─────────────────────────────
    // 137 = nbMisesAJour du jeu de poids personnalisé chargé en début de test
    expect(IaMemoryService.instance.poids.nbMisesAJour, 137,
        reason: 'restaurer des résultats ne doit déclencher aucun gradient');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T14 — Rétrocompat : ancienne sauvegarde SANS resultatsGrosParis
  //
  //  Exigence utilisateur : « une sauvegarde qui ne contient pas
  //  pronostic_resultats_repository_v2 doit toujours pouvoir être restaurée
  //  sans erreur ».
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T14 — ancien backup sans resultatsGrosParis : restauration OK et '
      'résultats locaux préservés', () async {
    // ── Appareil SOURCE : backup d'avant B4 ─────────────────────────────
    SharedPreferences.setMockInitialValues(
        prefsJson([_pronostic(courseKey: 'RSRC_10032026')]));
    await IaMemoryService.instance.recharger();
    final (export, bytes) = await exporterVersMemoire();

    // On simule le VIEUX format : la clé n'existe pas dans le fichier
    final contenu = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    contenu.remove('resultatsGrosParis');
    expect(contenu.containsKey('resultatsGrosParis'), isFalse);
    final bytesAnciens = Uint8List.fromList(utf8.encode(json.encode(contenu)));

    // ── Appareil CIBLE : 2 résultats locaux déjà présents ───────────────
    SharedPreferences.setMockInitialValues({});
    await PronosticResultatsRepository.instance
        .restaurerDepuisBackup({'pronosticResultats': []});
    await PronosticResultatsRepository.instance
        .ajouterOuRemplacer(_resultat(
      courseKey: 'RLOC_15032026',
      typePari: 'Quinté+',
      source: 'grosParisSurveiller',
      date: DateTime(2026, 3, 15),
      gagnant: true,
      nbTrouves: 5,
      nbRequis: 5,
    ));
    await PronosticResultatsRepository.instance
        .ajouterOuRemplacer(_resultat(
      courseKey: 'RLOC_16032026',
      typePari: 'Tiercé',
      source: 'programme',
      date: DateTime(2026, 3, 16),
      gagnant: false,
      nbTrouves: 1,
      nbRequis: 3,
    ));
    final locauxAvant = json.encode(
        PronosticResultatsRepository.instance.tous.map((e) => e.toJson()).toList());

    // ── Restauration de l'ANCIEN backup : ne doit pas lever d'exception ─
    final import = await restaurerDepuis(export, bytesAnciens);
    expect(import.succes, isTrue,
        reason: 'un ancien backup doit rester restaurable : ${import.erreur}');

    // ── Les résultats LOCAUX sont intacts (ni écrasés, ni effacés) ──────
    final apres = PronosticResultatsRepository.instance;
    expect(apres.tous.length, 2,
        reason: "l'absence de la clé ne doit RIEN toucher en local");
    expect(
        json.encode(apres.tous.map((e) => e.toJson()).toList()), locauxAvant,
        reason: 'préservation exacte, aucune modification');
    expect(apres.tous.map((e) => e.courseKey).toSet(),
        {'RLOC_15032026', 'RLOC_16032026'});
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T15 — L'exportation SEULE ne modifie aucune donnée locale
  //
  //  Exigence utilisateur : « l'ajout de cette clé au backup ne doit
  //  provoquer aucun recalcul ni modification des statistiques » et
  //  « confirmer que l'exportation seule ne modifie aucune donnée locale ».
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T15 — exporterDonnees() ne modifie rien en local (octet à octet)',
      () async {
    SharedPreferences.setMockInitialValues(
        prefsJson([_pronostic(courseKey: 'RSRC_10032026', avecResultat: true)]));
    await _installerElo(kEloAttendus);
    await IaMemoryService.instance.recharger();
    for (final r in [
      _resultat(
        courseKey: 'R1C1_10032026',
        typePari: 'Quinté+',
        source: 'grosParisSurveiller',
        date: DateTime(2026, 3, 10),
        gagnant: true,
        nbTrouves: 5,
        nbRequis: 5,
      ),
      _resultat(
        courseKey: 'R2C3_10032026',
        typePari: 'Tiercé',
        source: 'programme',
        date: DateTime(2026, 3, 11),
        gagnant: false,
        nbTrouves: 1,
        nbRequis: 3,
        utilisableApprentissage: true,
      ),
    ]) {
      await PronosticResultatsRepository.instance.ajouterOuRemplacer(r);
    }

    final prefsAvant = await SharedPreferences.getInstance();

    // Snapshot AVANT : disque + état en mémoire
    final disqueAvant =
        prefsAvant.getString(PronosticResultatsRepository.storageKey);
    final memoireAvant = json.encode(PronosticResultatsRepository.instance
        .tous
        .map((e) => e.toJson())
        .toList());
    final snapshotAvant = _snapshotMemoire();
    final nbResultatsAvant =
        PronosticResultatsRepository.instance.exporterPourBackup()['nbResultats'];
    final nbGagnantsAvant =
        PronosticResultatsRepository.instance.exporterPourBackup()['nbGagnants'];

    expect(disqueAvant, isNotNull, reason: 'état de départ non persisté');

    // ── Exportation, deux fois (pour écarter un effet de bord cumulatif) ─
    final export1 = await BackupService.instance.exporterDonnees();
    expect(export1.succes, isTrue);
    final export2 = await BackupService.instance.exporterDonnees();
    expect(export2.succes, isTrue);

    // Snapshot APRÈS
    final prefsApres = await SharedPreferences.getInstance();
    final disqueApres =
        prefsApres.getString(PronosticResultatsRepository.storageKey);
    final memoireApres = json.encode(PronosticResultatsRepository.instance
        .tous
        .map((e) => e.toJson())
        .toList());

    expect(disqueApres, disqueAvant,
        reason: 'la clé pronostic_resultats_repository_v2 doit être inchangée');
    expect(memoireApres, memoireAvant,
        reason: 'aucune réécriture en mémoire (ordre et contenu identiques)');
    expect(_snapshotMemoire(), snapshotAvant,
        reason: 'aucun poids, seuil, journal, ELO ou statistique ne bouge');

    final blocApres =
        PronosticResultatsRepository.instance.exporterPourBackup();
    expect(blocApres['nbResultats'], nbResultatsAvant);
    expect(blocApres['nbGagnants'], nbGagnantsAvant);

    // Et le contenu exporté correspond exactement à ce qui est en local
    final contenuFichier =
        json.decode(await File(export1.filePath!).readAsString())
            as Map<String, dynamic>;
    final blocFichier = contenuFichier['resultatsGrosParis'] as Map<String, dynamic>;
    expect(json.encode(blocFichier),
        json.encode(PronosticResultatsRepository.instance.exporterPourBackup()),
        reason: "le backup reflète l'état local à l'identique");
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T10 — reinitialiserComplet() efface-t-elle les ELO ?
  //
  //  `_toutesLesCles` (backup_service.dart:327) réunit 9 groupes et
  //  N'INCLUT PAS `_keysELO`. Les ratings ELO survivent donc à une
  //  réinitialisation complète, alors qu'ils sont sauvegardés dans le
  //  backup via `data['elo_service']`.
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T10 — reinitialiserComplet() doit aussi effacer les ELO', () async {
    SharedPreferences.setMockInitialValues(
        prefsJson([_pronostic(courseKey: 'RSRC_10032026')]));
    await _installerElo(kEloAttendus);
    await IaMemoryService.instance.recharger();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('ia_precision_migrated_v3'), isTrue);
    expect(IaMemoryService.instance.pronostics.length, 1);
    expect(EloService.instance.exporterPourBackup().length, 3);

    await BackupService.instance.reinitialiserComplet();
    await IaMemoryService.instance.recharger();

    // Ce que la réinitialisation fait bien
    expect(IaMemoryService.instance.pronostics, isEmpty,
        reason: 'les pronostics doivent être effacés');
    expect(prefs.getString('ia_poids_v3'), isNull,
        reason: 'les poids doivent être effacés');
    expect(prefs.getString('ia_seuils_v1'), isNull,
        reason: 'les seuils doivent être effacés');

    // ★ Ce qu'elle rate : les clés ELO restent sur le disque
    final prefsApres = await SharedPreferences.getInstance();
    final eloDisque = prefsApres.getString('elo_ratings_v2');
    final tsDisque = prefsApres.getInt('elo_ratings_v2_ts');

    // ignore: avoid_print
    print('  [T10] elo_ratings_v2 encore présent après reset complet : '
        '${eloDisque != null} (${eloDisque?.length ?? 0} caractères)');
    // ignore: avoid_print
    print('  [T10] elo_ratings_v2_ts présent : ${tsDisque != null}');

    expect(eloDisque, isNull,
        reason: 'reinitialiserComplet() doit effacer elo_ratings_v2 '
            '(_keysELO absent de _toutesLesCles, backup_service.dart:327)');
    expect(tsDisque, isNull,
        reason: 'reinitialiserComplet() doit effacer elo_ratings_v2_ts');

    // ★ Conséquence : un ELO réinitialisé en mémoire mais pas sur le disque
    // réapparaît au prochain _charger().
    await EloService.instance.reinitialiser();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T11 — Backup contenant LES DEUX formats de pronostics
  //
  //  _save() ne laisse jamais coexister les deux clés, mais un backup peut
  //  en contenir deux (fusion de fichiers, ancienne version, édition
  //  manuelle). Après restauration, il ne doit pas y avoir d'ambiguïté :
  //  une seule version doit survivre, et la mémoire IA doit la refléter.
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T11 — backup contenant les deux formats : une seule version survit',
      () async {
    // Appareil source : pronostics JSON que l'on va doubler d'un gzip
    // contenant un jeu DIFFÉRENT, pour rendre la priorité observable.
    final jsonSource = List.generate(
      3,
      (i) => _pronostic(courseKey: 'RJSON${i}_10032026'),
    );
    final gzSource = List.generate(
      7,
      (i) => _pronostic(courseKey: 'RGZ${i}_10032026'),
    );
    SharedPreferences.setMockInitialValues(prefsJson(jsonSource));
    await IaMemoryService.instance.recharger();
    final (export, bytes) = await exporterVersMemoire();

    // Fabrication d'un backup hybride : on ajoute la clé gzip au JSON exporté
    final contenu = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    final ia = contenu['ia'] as Map<String, dynamic>;
    ia['ia_pronostics_v2_gz'] = {'type': 'String', 'value': _gzEncode(gzSource)};
    final hybrides = utf8.encode(json.encode(contenu));

    // ignore: avoid_print
    print('  [T11] backup hybride : json=${(ia['ia_pronostics_v2'] as Map)['value']}'
        .replaceAll(RegExp(r'\[.*\]'), '[3 pronostics RJSON]'));
    // ignore: avoid_print
    print('  [T11] backup hybride : gz présent = '
        '${ia.containsKey('ia_pronostics_v2_gz')} (7 pronostics RGZ)');

    // Appareil cible vierge
    SharedPreferences.setMockInitialValues({});
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();

    final import = await restaurerDepuis(export, hybrides);
    expect(import.succes, isTrue, reason: 'import échoué : ${import.erreur}');

    final prefs = await SharedPreferences.getInstance();
    final gzApres = prefs.getString('ia_pronostics_v2_gz');
    final jsonApres = prefs.getStringList('ia_pronostics_v2');
    final enMemoire = IaMemoryService.instance.pronostics;

    final nbGz = enMemoire.where((p) => p.courseKey.startsWith('RGZ')).length;
    final nbJson = enMemoire.where((p) => p.courseKey.startsWith('RJSON')).length;

    // ignore: avoid_print
    print('  [T11] après restauration : gz=${gzApres != null}, '
        'json=${jsonApres?.length ?? 0}');
    // ignore: avoid_print
    print('  [T11] mémoire IA : ${enMemoire.length} pronostics '
        '(RGZ=$nbGz, RJSON=$nbJson)');

    // ★ Aucune ambiguïté : les deux clés ne doivent pas coexister
    final coexistence = gzApres != null && jsonApres != null;
    expect(coexistence, isFalse,
        reason: 'un backup hybride ne doit pas laisser DEUX jeux de pronostics '
            'coexister sur le disque : le contenu rechargé dépendrait alors '
            'de l\'ordre de lecture de _load(), pas du backup');

    // ★ La mémoire doit refléter exactement une seule version, sans mélange
    expect(nbGz == 0 || nbJson == 0, isTrue,
        reason: 'la mémoire IA ne doit pas mélanger les deux formats '
            '(RGZ=$nbGz, RJSON=$nbJson)');
    expect(enMemoire.length, anyOf(3, 7),
        reason: 'la mémoire doit contenir 3 (JSON) ou 7 (gzip) pronostics, '
            'pas un total mélangé — observé ${enMemoire.length}');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V5/T12 — Restauration invalide : les données locales sont préservées
  //
  //  Condition imposée : « Ne jamais supprimer les données locales si la
  //  restauration échoue avant validation. »
  // ═══════════════════════════════════════════════════════════════════════
  test('V5/T12 — un backup invalide ne doit rien effacer en local', () async {
    // Appareil cible avec une mémoire locale bien vivante, en gzip
    SharedPreferences.setMockInitialValues(prefsGzip(
      List.generate(25, (i) => _pronostic(courseKey: 'RLOC${i}_10032026')),
    ));
    await _installerElo(kEloAttendus);
    await IaMemoryService.instance.recharger();
    expect(IaMemoryService.instance.pronostics.length, 25);

    final avant = _snapshotMemoire();

    // Trois fichiers invalides : mauvais appName, JSON tronqué, fichier vide
    for (final (nom, contenu) in <(String, String)>[
      ('mauvais appName', json.encode({'appName': 'Autre App', 'version': '9.0'})),
      ('JSON tronqué', '{"appName": "Pronostic Hippique", "ia": {'),
      ('vide', ''),
    ]) {
      final bytes = utf8.encode(contenu);
      FilePicker.platform = _FakeFilePicker(FilePickerResult([
        PlatformFile(name: 'faux.json', size: bytes.length, bytes: bytes),
      ]));

      final import = await BackupService.instance.importerDepuisFichier();
      // ignore: avoid_print
      print('  [T12] backup "$nom" → succes=${import.succes}, '
          'erreur=${import.erreur}');

      expect(import.succes, isFalse,
          reason: 'un backup "$nom" doit être rejeté');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ia_pronostics_v2_gz'), isNotNull,
          reason: 'après un rejet ("$nom"), les pronostics locaux gzip '
              'doivent être intacts');
      expect(IaMemoryService.instance.pronostics.length, 25,
          reason: 'après un rejet ("$nom"), la mémoire IA ne doit pas changer');
      expect(_snapshotMemoire()['elo'], avant['elo'],
          reason: 'après un rejet ("$nom"), les ELO doivent être intacts');
    }
  });
}
