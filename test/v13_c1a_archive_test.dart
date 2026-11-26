// ═══════════════════════════════════════════════════════════════════════════
//  V13 — C1-a / E1 : archive permanente des pronostics évincés
//
//  ⚠️  FICHIER DE TEST uniquement. Aucune modification de lib/ associée.
//
//  Ce que ce fichier démontre :
//   P-1 .. P-17 : persistance, échecs, exceptions, concurrence, redémarrage
//   C-1 .. C-9  : identité, versions, autorité, aucune règle de destruction
//   I-1 .. I-9  : dédoublonnage, aucune double comptabilisation
//   T-1 .. T-6  : INVARIANCE STRICTE de l'apprentissage
//
//  Ce que ces tests N'EXAMINENT PAS (périmètre interdit) :
//   • gradient descent    • _poids (modification)    • _seuils
//   • TOP 3 learning      • analyseJourneeComplete() interne
//   • calendrier, fiches, couleurs, étoiles
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  STOCKAGE FAUTIF — indispensable pour tester les échecs d'écriture
// ═══════════════════════════════════════════════════════════════════════════

/// Store en mémoire dont on peut rendre l'écriture défaillante.
///
/// Reproduit fidèlement le comportement de `InMemorySharedPreferencesStore`,
/// mais :
///  • `echouerEcritures` → `setValue` renvoie `false` **sans** écrire ;
///  • `leverException`   → `setValue` lève une exception ;
///  • `perdreCles`       → simule une perte physique (coupure d'alimentation,
///    corruption) : la clé est retirée silencieusement APRÈS un `true`.
///
/// ⚠️ Important : `SharedPreferences._setValue` met à jour son CACHE avant
/// d'appeler ce store (shared_preferences_legacy.dart:178-188). Un `false`
/// ici laisse donc le cache incohérent avec le disque — exactement la
/// situation réelle. C'est ce que P-11 vérifie.
class FauxStoreFautif extends SharedPreferencesStorePlatform {
  FauxStoreFautif({Map<String, Object>? data})
      : _data = Map<String, Object>.from(data ?? {});

  final Map<String, Object> _data;

  bool echouerEcritures = false;
  bool leverException = false;
  final Set<String> clesFautives = {}; // si non vide : seules ces clés échouent
  final Set<String> perduesApresEcriture = {};

  bool _estFautive(String key) =>
      clesFautives.isEmpty || clesFautives.any((k) => key.contains(k));

  @override
  Future<bool> clear() async => clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final f = parameters.filter;
    final keys = _data.keys
        .where((k) =>
            k.startsWith(f.prefix) &&
            (f.allowList == null || f.allowList!.contains(k)))
        .toList();
    for (final k in keys) {
      _data.remove(k);
    }
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final f = parameters.filter;
    final result = Map<String, Object>.from(_data);
    result.removeWhere((k, _) =>
        !k.startsWith(f.prefix) ||
        (f.allowList != null && !f.allowList!.contains(k)));
    return result;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (leverException && _estFautive(key)) {
      throw StateError('stockage indisponible (simulation)');
    }
    if (echouerEcritures && _estFautive(key)) {
      return false; // rien n'est écrit — mais le cache est déjà à jour
    }
    _data[key] = value;
    if (perduesApresEcriture.contains(key)) {
      // Durabilité ANNONCÉE true, durabilité CONSTATÉE false (panne physique).
      _data.remove(key);
      perduesApresEcriture.remove(key);
    }
    return true;
  }

  // ── Outils de test ──────────────────────────────────────────────────────
  Iterable<String> get cles => _data.keys;
  Object? brut(String key) => _data['flutter.$key'];
  void injecterCorruption(String key, String valeur) =>
      _data['flutter.$key'] = valeur;
  void perdreClePhysiquement(String key) => _data.remove('flutter.$key');
}

// ═══════════════════════════════════════════════════════════════════════════
//  OUTILS
// ═══════════════════════════════════════════════════════════════════════════

String _dateDuJour() {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

String _courseKey(int r, int c, [String? date]) =>
    'R${r}C${c}_${date ?? _dateDuJour()}';

ZtPartant _partant(int num) => ZtPartant(
      numero: '$num',
      nom: 'CHEVAL_$num',
      driver: 'DRIVER_$num',
      entraineur: 'ENTR_$num',
      proprietaire: 'PROP_$num',
      gains: '${num * 10000}',
      record: '1\'1${num % 10}"0',
      musique: '1a2a3a4a5a',
      cote: '4.0',
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

ZtCourse _course({int numCourse = 1, int nbPartants = 8, String date = ''}) =>
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
      isQuinte: true,
      pronosticZt: const [1, 2, 3, 4, 5],
      partants: List.generate(nbPartants, (i) => _partant(i + 1)),
      dateStr: date,
    );

/// Pronostic minimal mais COMPLET, directement injectable.
/// `date` permet de répartir sur plusieurs mois (plusieurs shards).
IaPronostic _prono({
  required String courseKey,
  DateTime? date,
  bool resolu = false,
  List<int>? arrivee,
  DateTime? dateResultat,
  int favoriNum = 1,
  Map<String, ScoresCriteres>? criteres,
  double? confiance,
  double? variance,
  double? scorePerformance,
  int? rangFavori,
  Map<String, double> cotes = const {},
  String? favoriNom,
}) {
  return IaPronostic(
    courseKey: courseKey,
    nomCourse: 'PRIX $courseKey',
    hippodrome: 'VINCENNES',
    discipline: 'Trot Attelé',
    datePronostic: date ?? DateTime.now(),
    scoresIA: {
      for (var i = 1; i <= 5; i++) '$i': 100.0 - (i - 1) * 8.0 + favoriNum * 0.01,
    },
    scoresCriteres: criteres ??
        {
          for (var i = 1; i <= 5; i++)
            '$i': const ScoresCriteres(
              forme: 60, gains: 60, record: 60, cote: 60, constance: 60,
              victoires: 60, discipline: 60, distSpec: 60, jockey: 60,
              repos: 60, hippo: 60, entraineur: 60, elo: 60, terrain: 60,
              divergence: 60, poidsRel: 60, progression: 60, mouvCote: 60,
              placeDepart: 60,
            ),
        },
    varianceScores: variance,
    confiancePredite: confiance,
    typePariConseille: 'Quinté+',
    tauxReussiteAuMoment: 50.0,
    precisionIA: 60.0,
    favoriIaNom: favoriNom,
    arriveeReelle: arrivee,
    dateResultat: dateResultat,
    resultatsReels: resolu,
    rangFavoriIaDansArrivee: rangFavori,
    nbTop3DansArriveeReelle: resolu ? 2 : null,
    nbTop5DansArriveeReelle: resolu ? 4 : null,
    scorePerformance: scorePerformance,
    cotesPmuParNumero: cotes,
  );
}

/// Items prêts pour `enregistrerPronosticsBatch()` — chemin réel de
/// production (un seul `_save()` pour N courses), indispensable pour tester
/// de gros volumes sans coût quadratique.
List<Map<String, dynamic>> _itemsBatch(int debut, int fin, {int r = 1}) {
  final d = _dateDuJour();
  return [
    for (var i = debut; i < fin; i++)
      {
        'courseKey': _courseKey(r, i + 1, d),
        'course': _course(numCourse: i + 1, date: d),
        'partantsClasses': List.generate(8, (k) => _partant(k + 1)),
        'scoresCriteres': {
          for (var k = 1; k <= 8; k++)
            '$k': const ScoresCriteres(
              forme: 60, gains: 60, record: 60, cote: 60, constance: 60,
              victoires: 60, discipline: 60, distSpec: 60, jockey: 60,
              repos: 60, hippo: 60, entraineur: 60, elo: 60, terrain: 60,
              divergence: 60, poidsRel: 60, progression: 60, mouvCote: 60,
              placeDepart: 60,
            ),
        },
        'confiance': 65.0,
        'typePariConseille': 'Quinté+',
      },
  ];
}

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

/// Remet le singleton IaMemoryService dans un état de démarrage propre.
Future<void> _resetIaMemory() async {
  await IaMemoryService.instance.recharger();
}

/// Redémarrage simulé : vide le cache statique de SharedPreferences (donc
/// relit le store) et remet à zéro l'état RAM des deux services.
Future<void> _redemarrer(FauxStoreFautif store) async {
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await _resetIaMemory();
}

FauxStoreFautif _installerStoreFautif({Map<String, Object>? data}) {
  final store = FauxStoreFautif(data: data ?? _prefsVides());
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _installerStoreFautif();
    await IaArchiveService.instance.viderPourTest();
    await _resetIaMemory();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T — INVARIANCE STRICTE DE L'APPRENTISSAGE
  // ═════════════════════════════════════════════════════════════════════════

  group('T — Invariance de l\'apprentissage', () {
    test('T1a — calibrationScore inchangé avec 600 pronostics (archive ON)', () async {
      final svc = IaMemoryService.instance;
      for (var i = 0; i < 600; i++) {
        final p = _prono(
          courseKey: _courseKey(1, i + 1),
          resolu: true,
          arrivee: [1, 2, 3, 4, 5],
          dateResultat: DateTime.now(),
          rangFavori: 1,
        );
        IaArchiveService.instance.enregistrerEviction(p);
      }
      final avant = svc.poids.calibrationScore;
      await IaArchiveService.instance.persisterEnAttente();
      final apres = svc.poids.calibrationScore;
      expect(apres, avant,
          reason: 'calibrationScore ne doit jamais être modifié par l\'archive');
    });

    test('T2 — poids identiques caractère par caractère (archive ON vs OFF)', () async {
      final svc = IaMemoryService.instance;
      final ref = json.encode(svc.poids.toJson());

      for (var i = 0; i < 300; i++) {
        IaArchiveService.instance.enregistrerEviction(
            _prono(courseKey: _courseKey(1, i + 1), resolu: true,
                arrivee: [1, 2, 3, 4, 5], dateResultat: DateTime.now()));
      }
      await IaArchiveService.instance.persisterEnAttente();

      expect(json.encode(svc.poids.toJson()), ref,
          reason: '_poids doit rester strictement identique');
    });

    test('T4 — _pronostics ne dépasse jamais 600, même en échec d\'écriture', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();
      await _resetIaMemory();
      store.echouerEcritures = true;
      store.clesFautives.add('ia_archive_v1_');

      final svc = IaMemoryService.instance;
      // 605 pronostics : 600 tiennent, 5 doivent être évincés.
      // Chemin réel de production : enregistrement batch (un seul _save).
      await svc.enregistrerPronosticsBatch(_itemsBatch(0, 605));
      expect(svc.pronostics.length, 600,
          reason: 'la mémoire de travail doit rester strictement à 600');
      expect(IaArchiveService.instance.nbEvictionsNonArchivees, 5,
          reason: 'les 5 évictions non archivées sont conservées, sans abandon');
      expect(IaArchiveService.instance.etatArchive, isNot(EtatArchive.sain));
    });

    test('T5 — pronosticsAvecResultat ne lit que _pronostics', () async {
      final svc = IaMemoryService.instance;
      for (var i = 0; i < 10; i++) {
        IaArchiveService.instance.enregistrerEviction(
            _prono(courseKey: _courseKey(1, i + 1), resolu: true,
                arrivee: [1, 2, 3, 4, 5], dateResultat: DateTime.now()));
      }
      await IaArchiveService.instance.persisterEnAttente();

      expect(svc.pronosticsAvecResultat, isEmpty,
          reason: 'l\'archive ne doit JAMAIS alimenter pronosticsAvecResultat');
      expect(IaArchiveService.instance.nbVersionsArchivees, 10);
    });

    test('T6 — IaMemoryPronosticsAccessor pointe toujours sur _pronostics', () async {
      final svc = IaMemoryService.instance;
      await svc.enregistrerPronostic(
        courseKey: _courseKey(1, 1),
        course: _course(numCourse: 1),
        partantsClasses: List.generate(8, (k) => _partant(k + 1)),
        confiancePredite: 65.0,
      );
      // 5 pronostics archivés ne doivent pas apparaître via l'accessor.
      for (var i = 0; i < 5; i++) {
        IaArchiveService.instance.enregistrerEviction(
            _prono(courseKey: _courseKey(9, i + 1), resolu: true,
                arrivee: [1, 2, 3, 4, 5], dateResultat: DateTime.now()));
      }
      await IaArchiveService.instance.persisterEnAttente();

      expect(svc.pronostics.length, 1);
      expect(svc.pronosticsCount, 1);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  P — PERSISTANCE, ÉCHECS, EXCEPTIONS, CONCURRENCE, REDÉMARRAGE
  // ═════════════════════════════════════════════════════════════════════════

  group('P — Persistance et gestion des échecs', () {
    test('P-1 — échec d\'écriture : aucune destruction, file conservée', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();
      store.echouerEcritures = true;
      store.clesFautives.add('ia_archive_v1_');

      final archive = IaArchiveService.instance;
      final p = _prono(courseKey: _courseKey(1, 1));

      final ok = await archive.securiser(p, motif: ArchiveReason.eviction);

      expect(ok, isFalse);
      expect(archive.nbEvictionsNonArchivees, 1,
          reason: 'l\'objet doit rester dans la file, intact');
      expect(archive.fileEchecPourTest.first.courseKey, p.courseKey);
      expect(archive.dernierArchivageConfirme, isFalse);
      expect(archive.etatArchive, EtatArchive.degrade);
      expect(archive.doitGelerBlobPronostics, isTrue,
          reason: 'le blob doit être gelé pour préserver la dernière copie disque');
    });

    test('P-2 — après redémarrage, un NON-persisté n\'est PAS récupéré', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();
      store.echouerEcritures = true;
      store.clesFautives.add('ia_archive_v1_');

      final archive = IaArchiveService.instance;
      await archive.securiser(_prono(courseKey: _courseKey(1, 1)));
      expect(archive.nbEvictionsNonArchivees, 1);

      // Redémarrage avec stockage TOUJOURS défaillant.
      await _redemarrer(store);

      expect(IaArchiveService.instance.nbEvictionsNonArchivees, 0,
          reason: 'la file RAM ne survit pas à un redémarrage');
      expect(IaArchiveService.instance.toutesLesVersionsArchivees(), isEmpty,
          reason: 'AUCUNE récupération possible : rien n\'a jamais été écrit');
    });

    test('P-2b — le seul cas récupéré : écriture CONFIRMÉE puis redémarrage', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();

      final ok = await IaArchiveService.instance
          .securiser(_prono(courseKey: _courseKey(1, 1)));
      expect(ok, isTrue);

      await _redemarrer(store);

      final versions = IaArchiveService.instance.toutesLesVersionsArchivees();
      expect(versions.length, 1, reason: 'un seul exemplaire');
      expect(versions.first.courseKey, _courseKey(1, 1));
    });

    test('P-7 — échec d\'archive : le blob pronostics n\'est JAMAIS réécrit', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();
      await _resetIaMemory();

      final svc = IaMemoryService.instance;
      // 25 pronostics pour forcer _useCompression (> 20).
      await svc.enregistrerPronosticsBatch(_itemsBatch(0, 25));
      final blobAvant = store.brut('ia_pronostics_v2_gz');
      expect(blobAvant, isNotNull, reason: 'un blob doit exister avant la panne');
      final poidsAvant = store.brut('ia_poids_v3') as String;

      // Panne ciblée : SEULES les clés d'archive échouent.
      store.echouerEcritures = true;
      store.clesFautives.clear();
      store.clesFautives.add('ia_archive_v1_');

      // Saturer pour déclencher des évictions (615 de plus → 40 évictions).
      await svc.enregistrerPronosticsBatch(_itemsBatch(25, 640, r: 2));

      expect(IaArchiveService.instance.nbEvictionsNonArchivees, greaterThan(0));
      expect(store.brut('ia_pronostics_v2_gz'), blobAvant,
          reason: 'le blob doit être GELÉ : octet pour octet identique');
      expect(store.brut('ia_poids_v3'), poidsAvant,
          reason: 'les poids sont écrits normalement, jamais impactés');
      expect(svc.pronostics.length, lessThanOrEqualTo(600));
    });

    test('P-8 — blob corrompu : l\'archive reste lisible (aucune perte totale)', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();

      await IaArchiveService.instance
          .securiser(_prono(courseKey: _courseKey(1, 1)));
      store.injecterCorruption('ia_pronostics_v2_gz', 'corrompu!!!');

      await _redemarrer(store);

      expect(IaArchiveService.instance.toutesLesVersionsArchivees().length, 1,
          reason: 'l\'archive constitue une seconde copie indépendante');
    });

    test('P-9 — 2000 pronostics : 2000 identités conservées, 600 en mémoire', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();
      await _resetIaMemory();

      final svc = IaMemoryService.instance;
      // Chemin réel de production : 2000 courses en lots (un _save par lot).
      for (var debut = 0; debut < 2000; debut += 400) {
        await svc.enregistrerPronosticsBatch(
            _itemsBatch(debut, (debut + 400).clamp(0, 2000), r: 3));
      }

      // Mémoire de travail : 600 exactement.
      expect(svc.pronostics.length, 600);

      // Total conservé = mémoire persistée (600) ∪ archive (doit couvrir 1400).
      final clesMemoire = svc.pronostics.map((p) => p.courseKey).toSet();
      final clesArchive = IaArchiveService.instance
          .toutesLesVersionsArchivees()
          .map((p) => p.courseKey)
          .toSet();

      final total = {...clesMemoire, ...clesArchive};
      expect(total.length, 2000,
          reason: '2000 identités DISTINCTES conservées au total');
      expect(clesMemoire.intersection(clesArchive), isEmpty,
          reason: 'aucun doublon mémoire/archive');

      // Après redémarrage : les 2000 identités sont toujours présentes.
      await _redemarrer(store);
      final clesApres = {
        ...IaMemoryService.instance.pronostics.map((p) => p.courseKey),
        ...IaArchiveService.instance
            .toutesLesVersionsArchivees()
            .map((p) => p.courseKey),
      };
      expect(clesApres.length, 2000,
          reason: '2000 identités après redémarrage, sans doublon');
    });

    test('P-10 — shard écrit, manifeste absent : reconstruit par énumération', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();

      await IaArchiveService.instance
          .securiser(_prono(courseKey: _courseKey(1, 1)));
      store.perdreClePhysiquement('ia_archive_v1_manifest');

      await _redemarrer(store);

      final v = IaArchiveService.instance.derniereVerificationArchive;
      expect(v, isNotNull);
      expect(v!.manifesteReconstruit, isTrue,
          reason: 'le manifeste doit être reconstruit depuis les clés réelles');
      expect(IaArchiveService.instance.toutesLesVersionsArchivees().length, 1);
    });

    test('P-11 — le booléen seul fait foi, jamais une relecture', () async {
      // Le cache de SharedPreferences est mis à jour AVANT le store.
      // Après un false, getString renvoie donc la NOUVELLE valeur alors que
      // le disque contient l'ANCIENNE. Le service ne doit pas s'y tromper.
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();
      store.echouerEcritures = true;
      store.clesFautives.add('ia_archive_v1_');

      final archive = IaArchiveService.instance;
      final p = _prono(courseKey: _courseKey(1, 1));
      archive.enregistrerEviction(p);
      await archive.persisterEnAttente();
      // Le cache contient la "valeur" écrite, mais le stockage non.
      final prefs = await SharedPreferences.getInstance();
      final cacheMois = '${p.datePronostic.year}-'
          '${p.datePronostic.month.toString().padLeft(2, '0')}';
      expect(prefs.getString('ia_archive_v1_$cacheMois'), isNotNull,
          reason: 'le cache est bien pollué par setString (phénomène réel)');
      expect(store.brut('ia_archive_v1_$cacheMois'), isNull,
          reason: 'mais le stockage réel est vide');

      // Conclusion du service : fondée sur le bool, pas sur la relecture.
      expect(archive.dernierArchivageConfirme, isFalse,
          reason: 'le service ne doit JAMAIS conclure au succès sur une relecture');
      expect(archive.nbEvictionsNonArchivees, 1);
    });

    test('P-12 — rejeu : aucun doublon (empreinte)', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();

      final archive = IaArchiveService.instance;
      final p = _prono(courseKey: _courseKey(1, 1));
      await archive.securiser(p);
      await archive.securiser(p); // même objet, même contenu
      await archive.securiser(p);

      expect(archive.nbVersionsArchivees, 1, reason: 'une seule version');
      await _redemarrer(store);
      expect(IaArchiveService.instance.toutesLesVersionsArchivees().length, 1);
    });

    test('P-13 — concurrence : 3 évictions simultanées, aucun entrelacement', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();
      final poidsAvant = store.brut('ia_poids_v3');

      final archive = IaArchiveService.instance;
      await Future.wait([
        archive.securiser(_prono(courseKey: _courseKey(1, 1))),
        archive.securiser(_prono(courseKey: _courseKey(1, 2))),
        archive.securiser(_prono(courseKey: _courseKey(1, 3))),
      ]);

      expect(archive.nbVersionsArchivees, 3);
      expect(archive.nbEvictionsNonArchivees, 0);
      expect(store.brut('ia_poids_v3'), poidsAvant,
          reason: 'la concurrence ne touche jamais les poids');

      await _redemarrer(store);
      expect(IaArchiveService.instance.toutesLesVersionsArchivees().length, 3);
    });

    test('P-14 — 5000 échecs successifs : AUCUN abandon, aucune perte', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();
      store.echouerEcritures = true;
      store.clesFautives.add('ia_archive_v1_');

      final archive = IaArchiveService.instance;
      // 5000 évictions : enregistrement synchrone en file, puis tentatives
      // d'écriture (c'est exactement ce que fait _save à chaque cycle).
      for (var i = 0; i < 5000; i++) {
        archive.enregistrerEviction(_prono(courseKey: _courseKey(4, i + 1)));
      }
      // 5 cycles consécutifs en échec → état « panne » (5 = seuil défini).
      for (var cycle = 0; cycle < 5; cycle++) {
        await archive.persisterEnAttente();
        // À chaque cycle, la file ne doit JAMAIS diminuer.
        expect(archive.nbEvictionsNonArchivees, 5000,
            reason: 'aucun abandon, à aucun cycle');
      }

      expect(archive.nbEvictionsNonArchivees, 5000,
          reason: 'AUCUN plafond, AUCUN abandon');
      expect(archive.alerteMemoireArchive, isTrue,
          reason: 'au-delà de 100, une alerte est levée (signal, pas action)');
      expect(archive.etatArchive, EtatArchive.panne);

      // Stockage rétabli → les 5000 sont archivées.
      store.echouerEcritures = false;
      await archive.persisterEnAttente();

      expect(archive.nbEvictionsNonArchivees, 0);
      expect(archive.nbVersionsArchivees, 5000,
          reason: 'aucune perte : 5000 versions archivées');
      expect(archive.etatArchive, EtatArchive.sain);
    });

    test('P-14b — aucune décision cachée : la file ne décroît que par archivage', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();
      store.echouerEcritures = true;
      store.clesFautives.add('ia_archive_v1_');

      final archive = IaArchiveService.instance;
      for (var i = 0; i < 20; i++) {
        final avant = archive.nbEvictionsNonArchivees;
        archive.enregistrerEviction(_prono(courseKey: _courseKey(5, i + 1)));
        await archive.persisterEnAttente();
        expect(archive.nbEvictionsNonArchivees, avant + 1,
            reason: 'chaque échec ajoute exactement 1 entrée : jamais de retrait');
      }
    });

    test('P-15 — bool true ≠ garantie physique : perte constatée au redémarrage', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();

      final p = _prono(courseKey: _courseKey(1, 1));
      final mois = '${p.datePronostic.year}-'
          '${p.datePronostic.month.toString().padLeft(2, '0')}';
      // Durabilité ANNONCÉE true, puis perte physique du shard.
      store.perduesApresEcriture.add('flutter.ia_archive_v1_$mois');

      final ok = await IaArchiveService.instance.securiser(p);
      expect(ok, isTrue, reason: 'durabilité ANNONCÉE : true');
      expect(IaArchiveService.instance.dernierArchivageConfirme, isTrue);

      await _redemarrer(store);

      final v = IaArchiveService.instance.derniereVerificationArchive;
      expect(v, isNotNull);
      expect(v!.shardsPerdus, isNotEmpty,
          reason: 'durabilité CONSTATÉE : la perte est détectée et signalée');
      expect(IaArchiveService.instance.toutesLesVersionsArchivees(), isEmpty,
          reason: 'aucune reconstitution par heuristique');
    });

    test('P-16 — corruption partielle : seul le shard atteint est signalé', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();

      final ancien = DateTime.now().subtract(const Duration(days: 40));
      await IaArchiveService.instance
          .securiser(_prono(courseKey: _courseKey(1, 1), date: ancien));
      await IaArchiveService.instance
          .securiser(_prono(courseKey: _courseKey(1, 2)));

      final moisAncien = '${ancien.year}-'
          '${ancien.month.toString().padLeft(2, '0')}';
      store.injecterCorruption('ia_archive_v1_$moisAncien', '@@@invalide@@@');

      await _redemarrer(store);

      final v = IaArchiveService.instance.derniereVerificationArchive!;
      expect(v.shardsIllisibles, contains('ia_archive_v1_$moisAncien'));
      expect(IaArchiveService.instance.toutesLesVersionsArchivees().length, 1,
          reason: 'le shard intact reste intact, aucun mélange');
    });

    test('P-17 — lever du gel après rétablissement du stockage', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();
      await _resetIaMemory();
      store.echouerEcritures = true;
      store.clesFautives.add('ia_archive_v1_');

      final archive = IaArchiveService.instance;
      final evince = _prono(courseKey: _courseKey(1, 1));
      archive.enregistrerEviction(evince);
      await archive.persisterEnAttente();
      expect(archive.doitGelerBlobPronostics, isTrue);

      // Stockage rétabli.
      store.echouerEcritures = false;
      await IaMemoryService.instance.recharger();
      await IaMemoryService.instance.enregistrerPronostic(
        courseKey: _courseKey(7, 1),
        course: _course(numCourse: 1),
        partantsClasses: List.generate(8, (k) => _partant(k + 1)),
        confiancePredite: 65.0,
      );

      expect(archive.doitGelerBlobPronostics, isFalse,
          reason: 'la file est vidée : le blob est réécrit normalement');
      expect(archive.nbVersionsArchivees, greaterThanOrEqualTo(1));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C / I — IDENTITÉ, VERSIONS, AUTORITÉ, DÉDOUBLONNAGE
  // ═════════════════════════════════════════════════════════════════════════

  group('C/I — Identité et versions', () {
    test('I-1 — éviction puis troncature du même objet = UNE seule version', () async {
      final archive = IaArchiveService.instance;
      final p = _prono(courseKey: _courseKey(1, 1));

      await archive.securiser(p, motif: ArchiveReason.eviction);
      await archive.securiser(p, motif: ArchiveReason.troncature);

      expect(archive.nbVersionsArchivees, 1,
          reason: 'le motif technique ne crée JAMAIS de doublon');
      expect(archive.nbVersions(p.courseKey), 1);
    });

    test('I-2 — non résolu puis résolu : la version résolue est retenue', () async {
      final archive = IaArchiveService.instance;
      final key = _courseKey(1, 1);
      final date = DateTime.now();

      await archive.securiser(_prono(courseKey: key, date: date));
      final resolu = _prono(
          courseKey: key, date: date, resolu: true,
          arrivee: [1, 2, 3, 4, 5], dateResultat: DateTime.now());
      await archive.securiser(resolu);

      expect(archive.nbVersions(key), 2, reason: 'deux versions distinctes');
      final retenue = archive.versionRetenue(key)!;
      expect(retenue.resultatsReels, isTrue,
          reason: 'la version retenue doit être la résolue');
      expect(IaArchiveService.rangDe(retenue), 2);
    });

    test('I-3 — jamais une fiche complète remplacée par une incomplète', () async {
      final archive = IaArchiveService.instance;
      final key = _courseKey(1, 1);
      final date = DateTime.now();

      // Version 1 : complète.
      final complete = _prono(
        courseKey: key, date: date, resolu: true,
        arrivee: [1, 2, 3, 4, 5], dateResultat: DateTime.now(),
        confiance: 72.0, variance: 15.0, scorePerformance: 88.0,
        rangFavori: 1, cotes: {'1': 2.1}, favoriNom: 'CHEVAL_1',
      );
      await archive.securiser(complete);

      // Version 2 : même rang, mais fiche appauvrie.
      final pauvre = _prono(
        courseKey: key, date: date, resolu: true,
        arrivee: [1, 2, 3, 4, 5], dateResultat: DateTime.now(),
      );
      await archive.securiser(pauvre);

      final retenue = archive.versionRetenue(key)!;
      expect(IaArchiveService.completudeDe(retenue),
          IaArchiveService.completudeDe(complete),
          reason: 'la plus complète doit rester retenue');
      expect(retenue.confiancePredite, 72.0,
          reason: 'aucun champ ne doit être perdu ou recombiné');
      expect(archive.nbVersions(key), 2,
          reason: 'les deux versions restent conservées');
    });

    test('I-4 — 3 versions d\'un même courseKey : 1 seule prédiction comptée', () async {
      final archive = IaArchiveService.instance;
      final key = _courseKey(1, 1);
      final date = DateTime.now();

      for (var i = 0; i < 3; i++) {
        await archive.securiser(_prono(
          courseKey: key, date: date, favoriNum: i, resolu: i == 2,
          arrivee: i == 2 ? [1, 2, 3, 4, 5] : null,
          dateResultat: i == 2 ? DateTime.now() : null,
        ));
      }

      expect(archive.nbVersions(key), 3, reason: '3 versions conservées');
      expect(archive.nbPredictionsDistinctes, 1,
          reason: 'UNE seule prédiction (courseKey) → aucun double comptage');
      expect(archive.toutesLesVersionsArchivees().length, 3);
    });

    test('I-5 — datePronostic différents : versions distinctes, 1 seule retenue', () async {
      final archive = IaArchiveService.instance;
      final key = _courseKey(1, 1);

      await archive.securiser(_prono(courseKey: key, date: DateTime(2025, 1, 1)));
      await archive.securiser(_prono(courseKey: key, date: DateTime(2025, 1, 2)));

      expect(archive.nbVersions(key), 2);
      expect(archive.nbPredictionsDistinctes, 1);
      expect(archive.versionsDuMois('2025-01').length, 2);
    });

    test('I-6 — restauration dans l\'ordre inverse : même version retenue', () async {
      final key = _courseKey(1, 1);
      final date = DateTime.now();

      final a = _prono(courseKey: key, date: date, favoriNum: 1, resolu: true,
          arrivee: [1, 2, 3, 4, 5], dateResultat: DateTime(2025, 6, 1));
      final b = _prono(courseKey: key, date: date, favoriNum: 2, resolu: true,
          arrivee: [2, 1, 3, 4, 5], dateResultat: DateTime(2025, 6, 2));

      final archive = IaArchiveService.instance;
      await archive.securiser(a);
      await archive.securiser(b);
      final retenueOrdre1 = archive.versionRetenue(key)!;

      // Redémarrage : relecture depuis le disque (ordre d'itération différent).
      final store = SharedPreferencesStorePlatform.instance as FauxStoreFautif;
      await _redemarrer(store);
      final retenueOrdre2 = IaArchiveService.instance.versionRetenue(key)!;

      expect(IaArchiveService.empreinteDe(retenueOrdre2),
          IaArchiveService.empreinteDe(retenueOrdre1),
          reason: 'ordre d\'autorité total : la relecture désigne la même version');
      expect(retenueOrdre2.dateResultat, DateTime(2025, 6, 2),
          reason: 'la plus récente des deux versions résolues est retenue');
    });

    test('I-7 — aucun champ recombiné entre deux versions', () async {
      final archive = IaArchiveService.instance;
      final key = _courseKey(1, 1);
      final date = DateTime.now();

      final v1 = _prono(courseKey: key, date: date, resolu: true,
          arrivee: [1, 2, 3, 4, 5], dateResultat: DateTime(2025, 6, 1),
          confiance: 70.0);
      final v2 = _prono(courseKey: key, date: date, resolu: true,
          arrivee: [1, 2, 3, 4, 5], dateResultat: DateTime(2025, 6, 2),
          variance: 20.0);

      await archive.securiser(v1);
      await archive.securiser(v2);

      final retenue = archive.versionRetenue(key)!;
      // La retenue est v2 ENTIÈRE : confiance null (celle de v2), variance 20.
      expect(retenue.varianceScores, 20.0);
      expect(retenue.confiancePredite, isNull,
          reason: 'aucune recombinaison : la confiance de v1 ne doit pas migrer');
    });

    test('I-8 — motif différent, contenu identique : empreinte identique', () async {
      final p = _prono(courseKey: _courseKey(1, 1), resolu: true,
          arrivee: [1, 2, 3, 4, 5], dateResultat: DateTime(2025, 6, 1));
      final e1 = IaArchiveService.empreinteDe(p);
      final e2 = IaArchiveService.empreinteDe(p);
      expect(e1, e2, reason: 'empreinte déterministe et stable');
      // Le motif n'est pas un paramètre de l'empreinte (signature statique).
      //
      // ⚠️ MISE EN CONFORMITÉ V2 (et non affaiblissement) : l'assertion
      //    précédente était `e1.length == 16` avec le motif « FNV-1a 64 bits ».
      //    Elle décrivait le canonique V1, qui ne couvrait que 7 champs et
      //    faisait perdre des versions authentiquement distinctes (R-3bis
      //    mesuré : rang 1, rang 3 et type de pari différent produisaient tous
      //    `51b1b1687572ce2c`). Le canonique courant est V2 = SHA-256 du
      //    `toJson()` complet, soit 64 caractères hexadécimaux.
      //    L'intention du test — « l'empreinte est déterministe et le motif
      //    n'y entre pas » — est intégralement préservée ; seule la longueur
      //    attendue change, parce que le canonique a changé.
      expect(e1.length, IaArchiveService.kLongueurEmpreinteV2,
          reason: 'canonique V2 = SHA-256 en hexadécimal');
      expect(IaArchiveService.versionEmpreinte(e1), 2);
      // V1 reste calculable, à l'identique, pour la compatibilité historique.
      final v1 = IaArchiveService.empreinteV1De(p);
      expect(v1.length, IaArchiveService.kLongueurEmpreinteV1,
          reason: 'le canonique V1 historique est conservé sans modification');
      expect(IaArchiveService.versionEmpreinte(v1), 1);
    });

    test('I-9 — 10 versions d\'un courseKey sur le mois : 1 prédiction', () async {
      final archive = IaArchiveService.instance;
      final key = _courseKey(1, 1);
      final date = DateTime(2025, 3, 15);

      for (var i = 0; i < 10; i++) {
        await archive.securiser(_prono(
          courseKey: key, date: date, favoriNum: i,
          resolu: i == 9, arrivee: i == 9 ? [1, 2, 3, 4, 5] : null,
          dateResultat: i == 9 ? DateTime(2025, 3, 16) : null,
        ));
      }

      expect(archive.versionsDuMois('2025-03').length, 10);
      expect(archive.nbPredictionsDistinctes, 1,
          reason: 'le calendrier ne comptera jamais cette course deux fois');
    });

    test('C-1 — non résolu puis résolu : aucun écrasement destructif', () async {
      final archive = IaArchiveService.instance;
      final key = _courseKey(1, 1);
      final date = DateTime.now();

      await archive.securiser(_prono(courseKey: key, date: date));
      await archive.securiser(_prono(courseKey: key, date: date, resolu: true,
          arrivee: [1, 2, 3, 4, 5], dateResultat: DateTime.now()));

      expect(archive.nbVersions(key), 2,
          reason: 'la version non résolue est conservée, jamais détruite');
      expect(archive.versionRetenue(key)!.resultatsReels, isTrue);
    });

    test('C-7 — complétude : la version la plus riche gagne', () async {
      final key = _courseKey(1, 1);
      final date = DateTime.now();

      final riche = _prono(courseKey: key, date: date, resolu: true,
          arrivee: [1, 2, 3, 4, 5], dateResultat: DateTime(2025, 6, 1),
          confiance: 70.0, variance: 10.0, scorePerformance: 90.0,
          rangFavori: 1, cotes: {'1': 2.0}, favoriNom: 'CHEVAL_1');

      expect(IaArchiveService.completudeDe(riche), 9);
      expect(IaArchiveService.rangDe(riche), 2);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  S — SÉCURISATION AVANT ÉVICTION (exigence explicite)
  // ═════════════════════════════════════════════════════════════════════════

  group('S — La référence est sécurisée AVANT le retrait', () {
    test('S-1 — enregistrerEviction est synchrone et sans effet de bord', () async {
      final archive = IaArchiveService.instance;
      final p = _prono(courseKey: _courseKey(1, 1));

      // Aucun await : la référence doit être en file IMMÉDIATEMENT.
      archive.enregistrerEviction(p);
      expect(archive.nbEvictionsNonArchivees, 1,
          reason: 'sécurisation synchrone, avant toute éviction');
      expect(archive.fileEchecPourTest.first, same(p),
          reason: 'c\'est bien LA MÊME référence, pas une copie');
    });

    test('S-2 — un pronostic jamais persisté peut être perdu (assumé)', () async {
      final store = _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();
      await _resetIaMemory();
      store.echouerEcritures = true;
      store.clesFautives.add('ia_archive_v1_');

      final svc = IaMemoryService.instance;
      // Créé puis évincé sans qu'aucun _save n'ait jamais réussi à l'écrire.
      // bloc isolé
      {
        final p = _prono(courseKey: _courseKey(8, 1));
        IaArchiveService.instance.enregistrerEviction(p);
      }
      await IaArchiveService.instance.persisterEnAttente();
      expect(IaArchiveService.instance.nbEvictionsNonArchivees, 1);

      await _redemarrer(store);

      // Constat honnête : ni en mémoire, ni en archive.
      final enMemoire =
          svc.pronostics.any((p) => p.courseKey == _courseKey(8, 1));
      final enArchive = IaArchiveService.instance
          .toutesLesVersionsArchivees()
          .any((p) => p.courseKey == _courseKey(8, 1));
      expect(enMemoire, isFalse);
      expect(enArchive, isFalse,
          reason: 'aucune récupération promise pour un jamais-persisté');
    });

    test('S-3 — le motif troncature couvre la tranche excédentaire de _save', () async {
      _installerStoreFautif();
      await IaArchiveService.instance.viderPourTest();
      await _resetIaMemory();

      final svc = IaMemoryService.instance;
      // 250 pronostics par le chemin batch réel (< 600 → aucune éviction).
      await svc.enregistrerPronosticsBatch(_itemsBatch(0, 250, r: 6));
      expect(svc.pronostics.length, lessThanOrEqualTo(600));
      // Aucune éviction inutile : 250 < 600.
      expect(IaArchiveService.instance.toutesLesVersionsArchivees(), isEmpty);
    });
  });
}
