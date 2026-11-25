// ═══════════════════════════════════════════════════════════════════════════
//  V16 — E2 : LE CALENDRIER LIT AUSSI L'ARCHIVE
//
//  Objet : prouver que `donneesCalendrierJour()` agrège désormais
//  MÉMOIRE DE TRAVAIL **puis** ARCHIVE, sans jamais :
//   • créer un doublon de course (dédoublonnage par courseKey) ;
//   • afficher une journée issue d'un pronostic NON RÉSOLU ;
//   • inventer une étoile (la règle hasBestBet est inchangée) ;
//   • réinjecter quoi que ce soit dans l'apprentissage.
//
//  ★ A2 (V48) : la sélection entre les deux sources n'est plus « mémoire
//  prioritaire à l'aveugle » mais un ARBITRAGE PAR AUTORITÉ
//  (`_versionLaPlusAutoritaire`, réutilisant `IaArchiveService.comparerAutorite`).
//  Pour un même `courseKey`, une fiche active NON RÉSOLUE ne masque plus une
//  fiche archivée RÉSOLUE. Le groupe B a été réécrit en conséquence ; son
//  objet — aucune fusion, aucun doublon, aucune écriture, aucune invention —
//  est strictement préservé.
//
//  Groupes :
//   A — la fusion apporte les journées absentes de la mémoire
//   B — arbitrage par autorité (A2) : plus de priorité aveugle
//   C — filtres conservés (non résolu, type invalide, hors mois)
//   D — paliers, taux, ordre/désordre, étoiles inchangés
//   E — une seule version par course (autorité)
//   F — lecture seule (aucune écriture, aucune réinjection)
//   G — dégénérescence exacte si l'archive n'est pas chargée
//   H — chargement asynchrone : notification, idempotence, échec, reprise
//   I — mois partiellement couvert
//   J — non-réinjection dans l'apprentissage
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/pronostic_resultats_repository.dart';
import 'package:pronostic_hippique/services/quasi_gros_paris_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  FAUX STORE (autonome)
// ═══════════════════════════════════════════════════════════════════════════

class _FauxStore extends SharedPreferencesStorePlatform {
  _FauxStore({Map<String, Object>? data})
      : _data = <String, Object>{
          for (final e in (data ?? const <String, Object>{}).entries)
            (e.key.startsWith('flutter.') ? e.key : 'flutter.${e.key}'):
                e.value,
        };

  final Map<String, Object> _data;

  /// Simule une panne de lecture/écriture : toute opération lève.
  bool panne = false;

  /// Nombre de lectures effectuées (pour prouver l'absence de relecture).
  int nbLectures = 0;

  @override
  Future<bool> clear() async => clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final f = parameters.filter;
    for (final k in _data.keys
        .where((k) =>
            k.startsWith(f.prefix) &&
            (f.allowList == null || f.allowList!.contains(k)))
        .toList()) {
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
    nbLectures++;
    if (panne) throw StateError('panne de lecture simulée');
    final f = parameters.filter;
    final result = Map<String, Object>.from(_data);
    result.removeWhere((k, _) =>
        !k.startsWith(f.prefix) ||
        (f.allowList != null && !f.allowList!.contains(k)));
    return result;
  }

  @override
  Future<bool> remove(String key) async {
    if (panne) throw StateError('panne de lecture simulée');
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (panne) throw StateError('panne de lecture simulée');
    _data[key] = value;
    return true;
  }

  bool contient(String key) => _data.containsKey('flutter.$key');
  Object? brut(String key) => _data['flutter.$key'];
}

// ═══════════════════════════════════════════════════════════════════════════
//  OUTILS
// ═══════════════════════════════════════════════════════════════════════════

const String _kPronosticsKey = 'ia_pronostics_v2_gz';
const String _kPoidsKey = 'ia_poids_v3';
const String _kSeuilsKey = 'ia_seuils_v1';

late _FauxStore _store;

String _ddmmyyyy(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Mois de référence : passé stable, pour que le test ne dépende pas de
/// l'horloge murale.
final DateTime _moisRef = DateTime(2024, 3, 1);

DateTime _jour(int jour) => DateTime(_moisRef.year, _moisRef.month, jour);

String _cleCourse(int r, int c, DateTime d) => 'R${r}C${c}_${_ddmmyyyy(d)}';

/// Pronostic minimal maîtrisé : scores décroissants 1→5, arrivée configurable.
IaPronostic _prono({
  required String courseKey,
  required DateTime date,
  String? typePari = 'Quinté+',
  bool resolu = true,
  List<int>? arrivee,
  int nbTop3 = 0,
  int nbTop5 = 0,
  int? rangFavori,
  double decalage = 0.0,
}) {
  final scores = <String, double>{
    for (var i = 1; i <= 5; i++) '$i': 100.0 - (i - 1) * 8.0 + decalage,
  };
  return IaPronostic(
    courseKey: courseKey,
    nomCourse: 'PRIX $courseKey',
    hippodrome: 'VINCENNES',
    discipline: 'Trot Attelé',
    datePronostic: date,
    scoresIA: scores,
    scoresCriteres: const {},
    varianceScores: 12.0,
    confiancePredite: 70.0,
    typePariConseille: typePari,
    favoriIaNom: 'CHEVAL_1',
    arriveeReelle: resolu ? (arrivee ?? const [1, 2, 3, 4, 5]) : null,
    dateResultat: resolu ? date.add(const Duration(hours: 2)) : null,
    resultatsReels: resolu,
    rangFavoriIaDansArrivee: rangFavori,
    nbTop3DansArriveeReelle: nbTop3,
    nbTop5DansArriveeReelle: nbTop5,
    scorePerformance: 50.0,
  );
}

/// GAGNANT Quinté+ : les 5 chevaux IA (1..5) sont les 5 premiers réels.
IaPronostic _pronoGagnant({
  required String courseKey,
  required DateTime date,
  String? typePari = 'Quinté+',
}) =>
    _prono(
      courseKey: courseKey,
      date: date,
      typePari: typePari,
      arrivee: const [1, 2, 3, 4, 5],
      nbTop3: 3,
      nbTop5: 5,
      rangFavori: 1,
    );

/// PERDANT : l'arrivée réelle ne contient aucun cheval du top IA.
IaPronostic _pronoPerdant({
  required String courseKey,
  required DateTime date,
  String typePari = 'Quinté+',
}) =>
    _prono(
      courseKey: courseKey,
      date: date,
      typePari: typePari,
      arrivee: const [9, 10, 11, 12, 13],
      nbTop3: 0,
      nbTop5: 0,
      rangFavori: null,
    );

Map<String, Object> _prefsPoids() => <String, Object>{
      'ia_precision_migrated_v3': true,
      _kPoidsKey: json.encode(<String, dynamic>{
        'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
        'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
        'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
        'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
        'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
        'mouvCote': 0.06, 'placeDepart': 0.03,
        'nbMisesAJour': 0, 'calibrationScore': 50.0,
      }),
      _kSeuilsKey: json.encode(<String, dynamic>{}),
    };

/// Injecte directement des pronostics dans le blob de travail (comme un
/// appareil déjà utilisé), sans passer par l'API d'enregistrement.
Map<String, Object> _prefsAvecMemoire(List<IaPronostic> pronostics) {
  final prefs = _prefsPoids();
  final jsonStr = json.encode(pronostics.map((p) => p.toJson()).toList());
  prefs[_kPronosticsKey] =
      base64Encode(GZipCodec().encode(utf8.encode(jsonStr)));
  return prefs;
}

_FauxStore _installerStore({Map<String, Object>? data}) {
  final store = _FauxStore(data: data ?? _prefsPoids());
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  _store = store;
  return store;
}

/// Archive un lot de versions et attend la confirmation d'écriture.
Future<void> _archiver(List<IaPronostic> lots) async {
  for (final p in lots) {
    IaArchiveService.instance.enregistrerEviction(p);
  }
  final ok = await IaArchiveService.instance.persisterEnAttente();
  expect(ok, isTrue, reason: 'archivage de préparation non confirmé');
}

/// Instantané comparable du calendrier d'un mois :
/// jour → « nbCourses|nbBons|nbOrdre|nbDesordre|palier|hasBestBet|courseKeys ».
Map<int, String> _instantane(int annee, int mois) {
  final d = IaMemoryService.instance.donneesCalendrierJour(annee, mois);
  return d.map((j, v) => MapEntry(
        j,
        '${v.nbCourses}|${v.nbBons}|${v.nbOrdre}|${v.nbDesordre}|'
        '${v.palier}|${v.hasBestBet}|'
        '${v.pronostics.map((p) => p.courseKey).join(",")}',
      ));
}

/// Prépare un store avec N pronostics en mémoire de travail, archive vidée.
Future<void> _preparerMemoire(List<IaPronostic> pronostics) async {
  _installerStore(data: _prefsAvecMemoire(pronostics));
  IaArchiveService.instance.oublierChargementPourTest();
  await IaArchiveService.instance.viderPourTest();
  await IaMemoryService.instance.recharger();
}

void main() {
  setUp(() async {
    _installerStore();
    IaArchiveService.instance.oublierChargementPourTest();
    await IaArchiveService.instance.viderPourTest();
    await PronosticResultatsRepository.instance
        .restaurerDepuisBackup({'pronosticResultats': []});
    await QuasiGrosParisService.instance
        .importerDepuisBackup({'signaux': [], 'quasiGagnants': []});
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A — LA FUSION APPORTE LES JOURNÉES ABSENTES
  // ═══════════════════════════════════════════════════════════════════════

  group('A — apport de l\'archive', () {
    test('A-1 — jour uniquement dans l\'archive : il apparaît', () async {
      final jour = _jour(7);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d.containsKey(7), isTrue,
          reason: 'le jour 7 doit être alimenté par l\'archive seule');
      expect(d[7]!.nbCourses, 1);
      expect(d[7]!.pronostics.single.courseKey, _cleCourse(1, 1, jour));
    });

    test('A-2 — sans E2 (archive non chargée) le jour n\'apparaît pas',
        () async {
      final jour = _jour(7);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
      ]);
      // On oublie le chargement : archive vide du point de vue du service.
      IaArchiveService.instance.oublierChargementPourTest();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d.containsKey(7), isFalse,
          reason: 'sans archive chargée, aucune journée inventée');
    });

    test('A-3 — jours d\'archive et jours mémoire coexistent', () async {
      final jourMemoire = _jour(3);
      await _preparerMemoire([
        _pronoGagnant(
            courseKey: _cleCourse(1, 1, jourMemoire), date: jourMemoire),
      ]);

      final j1 = _jour(10), j2 = _jour(20);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, j1), date: j1),
        _pronoGagnant(courseKey: _cleCourse(1, 1, j2), date: j2),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d.keys.toSet(), containsAll(<int>[3, 10, 20]));
      expect(d.length, 3);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // ★ A2 — LA MÉMOIRE N'EST PLUS PRIORITAIRE À L'AVEUGLE
  //
  // Les trois tests de ce groupe verrouillaient la règle ANTÉRIEURE, où la
  // seule présence d'un `courseKey` dans `_pronostics` — même sous une forme
  // non résolue — excluait l'apport d'archive.
  //
  // Depuis A2, la sélection passe par `_versionLaPlusAutoritaire` : pour un
  // même `courseKey`, c'est la fiche la PLUS AUTORITAIRE qui est retenue
  // (règle 4 : actif non résolu + archive résolue → archive). Les
  // assertions sont donc réécrites pour décrire la NOUVELLE règle métier.
  //
  // Ce qui reste ABSOLUMENT interdit et est toujours vérifié ici :
  //   • aucun doublon de course ;
  //   • aucune fusion de champs entre les deux versions ;
  //   • aucune écriture dans `_pronostics` ;
  //   • aucune journée inventée sans résultat réel ;
  //   • les journées de mémoire pure restent strictement identiques.
  group('B — arbitrage par autorité (A2)', () {
    test('B-1 — deux fiches RÉSOLUES : la plus autoritaire gagne, sans doublon',
        () async {
      final jour = _jour(5);
      final cle = _cleCourse(1, 1, jour);
      // Actif : résolu mais PERDANT. Archive : résolue et GAGNANTE.
      await _preparerMemoire([_pronoPerdant(courseKey: cle, date: jour)]);

      await _archiver([_pronoGagnant(courseKey: cle, date: jour)]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      // Prérequis explicites : les deux versions sont résolues, donc la
      // règle 4 (actif non résolu) NE s'applique PAS ici — c'est bien
      // l'autorité (`comparerAutorite`) qui tranche.
      final active = IaMemoryService.instance.getPronostic(cle)!;
      final archive = IaArchiveService.instance.versionRetenue(cle)!;
      expect(active.resultatsReels, isTrue);
      expect(archive.resultatsReels, isTrue);
      expect(IaArchiveService.comparerAutorite(archive, active), greaterThan(0),
          reason: 'prérequis : l\'archive est plus autoritaire (plus complète)');

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d[5]!.nbCourses, 1, reason: 'aucun doublon');
      expect(d[5]!.pronostics.length, 1,
          reason: 'une seule entrée par course : jamais deux journées '
              'concurrentes');
      expect(d[5]!.pronostics.single.courseKey, cle);
      expect(d[5]!.nbBons, 1,
          reason: 'A2 : la version RÉSOLUE GAGNANTE et plus complète (archive) '
              'est retenue — la fiche active perdante n\'écrase plus une fiche '
              'plus autoritaire');
      expect(d[5]!.palier, PalierCalendrier.or);
    });

    test('B-2 — les journées mémoire restent IDENTIQUES après chargement',
        () async {
      final j1 = _jour(4), j2 = _jour(6);
      await _preparerMemoire([
        _pronoGagnant(courseKey: _cleCourse(1, 1, j1), date: j1),
        _pronoPerdant(courseKey: _cleCourse(1, 2, j1), date: j1),
        _pronoGagnant(courseKey: _cleCourse(2, 1, j2), date: j2),
      ]);

      final avant = _instantane(_moisRef.year, _moisRef.month);

      final autre = _jour(15);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(3, 1, autre), date: autre),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final apres = _instantane(_moisRef.year, _moisRef.month);
      for (final jour in avant.keys) {
        expect(apres[jour], avant[jour],
            reason: 'jour $jour : aucune course n\'étant présente dans les '
                'DEUX sources, l\'arbitrage A2 est sans effet — la mémoire '
                'ne doit pas bouger');
      }
      expect(apres.containsKey(15), isTrue);
    });

    test('B-3 — course mémoire NON RÉSOLUE : l\'archive RÉSOLUE est retenue',
        () async {
      final jour = _jour(8);
      final cle = _cleCourse(1, 1, jour);
      await _preparerMemoire([
        _prono(courseKey: cle, date: jour, resolu: false),
      ]);

      await _archiver([_pronoGagnant(courseKey: cle, date: jour)]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      // Prérequis : l'actif est bien non résolu (rang 0), l'archive résolue
      // complète (rang 2). C'est exactement le cas de la règle 4.
      expect(IaMemoryService.instance.getPronostic(cle)?.resultatsReels, isFalse);
      expect(
          IaArchiveService.rangDe(
              IaArchiveService.instance.versionRetenue(cle)!),
          2);

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d.containsKey(8), isTrue,
          reason: 'A2 : une fiche active NON RÉSOLUE ne masque plus une fiche '
              'archivée RÉSOLUE — la journée redevient visible');
      expect(d[8]!.nbCourses, 1, reason: 'aucun doublon');
      expect(d[8]!.nbBons, 1, reason: 'la victoire archivée est comptée');
      expect(d[8]!.pronostics.single.resultatsReels, isTrue,
          reason: 'la version retenue est la version résolue');

      // Non-régression : la mémoire active n'a PAS été modifiée par la lecture.
      expect(IaMemoryService.instance.getPronostic(cle)?.resultatsReels, isFalse,
          reason: 'aucune réinjection ni complétion sur place de la fiche '
              'active');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  C — FILTRES CONSERVÉS
  // ═══════════════════════════════════════════════════════════════════════

  group('C — filtres inchangés', () {
    test('C-1 — pronostic archivé NON RÉSOLU : aucune journée créée',
        () async {
      final jour = _jour(11);
      await _archiver([
        _prono(courseKey: _cleCourse(1, 1, jour), date: jour, resolu: false),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(_moisRef.year, _moisRef.month),
        isEmpty,
      );
    });

    test('C-2 — type de pari invalide : ignoré', () async {
      final jour = _jour(12);
      await _archiver([
        _pronoGagnant(
            courseKey: _cleCourse(1, 1, jour),
            date: jour,
            typePari: 'Inconnu'),
        _pronoGagnant(
            courseKey: _cleCourse(1, 2, jour),
            date: jour,
            typePari: 'À surveiller'),
        _pronoGagnant(
            courseKey: _cleCourse(1, 3, jour), date: jour, typePari: null),
        _pronoGagnant(
            courseKey: _cleCourse(1, 4, jour), date: jour, typePari: ''),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(_moisRef.year, _moisRef.month),
        isEmpty,
        reason: 'les 4 pronostics sont écartés par le filtre',
      );
    });

    test('C-3 — pronostic archivé hors du mois affiché : ignoré', () async {
      final dedans = _jour(13);
      final dehors = DateTime(2024, 4, 3);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, dedans), date: dedans),
        _pronoGagnant(courseKey: _cleCourse(1, 1, dehors), date: dehors),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d.keys.toSet(), <int>{13});
    });

    test('C-4 — mélange valide / invalide : seuls les valides comptent',
        () async {
      final jour = _jour(14);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
        _prono(courseKey: _cleCourse(1, 2, jour), date: jour, resolu: false),
        _pronoGagnant(
            courseKey: _cleCourse(1, 3, jour),
            date: jour,
            typePari: 'Inconnu'),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d[14]!.nbCourses, 1);
      expect(d[14]!.nbBons, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D — PALIERS, TAUX, ORDRE/DÉSORDRE, ÉTOILES INCHANGÉS
  // ═══════════════════════════════════════════════════════════════════════

  group('D — règles métier inchangées', () {
    test('D-1 — palier OR conservé pour une journée d\'archive', () async {
      final jour = _jour(16);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
        _pronoPerdant(courseKey: _cleCourse(1, 2, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d[16]!.palier, PalierCalendrier.or);
      expect(d[16]!.nbCourses, 2);
      expect(d[16]!.nbBons, 1);
      expect(d[16]!.taux, closeTo(0.5, 1e-9));
    });

    test('D-2 — palier ROUGE conservé pour une journée d\'archive', () async {
      final jour = _jour(17);
      await _archiver([
        _pronoPerdant(courseKey: _cleCourse(1, 1, jour), date: jour),
        _pronoPerdant(courseKey: _cleCourse(1, 2, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d[17]!.palier, PalierCalendrier.rouge);
      expect(d[17]!.nbBons, 0);
    });

    test('D-3 — ordre exact calculé de la même façon sur l\'archive',
        () async {
      final jour = _jour(18);
      await _archiver([
        _prono(
          courseKey: _cleCourse(1, 1, jour),
          date: jour,
          arrivee: const [1, 2, 3, 4, 5],
          nbTop3: 3,
          nbTop5: 5,
          rangFavori: 1,
        ),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d[18]!.nbOrdre, 1);
      expect(d[18]!.nbDesordre, 0);
    });

    test('D-4 — AUCUNE étoile inventée sans historique premium', () async {
      final jour = _jour(19);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d[19]!.hasBestBet, isFalse,
          reason: 'sans entrée premium pour ce jour, aucune étoile');
      expect(
        IaMemoryService.instance
            .premiumsPourDate(jour.year, jour.month, jour.day),
        isEmpty,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  E — UNE SEULE VERSION PAR COURSE (AUTORITÉ)
  // ═══════════════════════════════════════════════════════════════════════

  group('E — autorité de l\'archive', () {
    test('E-1 — deux versions archivées : la plus autoritaire est retenue',
        () async {
      final jour = _jour(21);
      final cle = _cleCourse(1, 1, jour);

      // v1 : résolu mais SANS arrivée → rang 1.
      final v1 = IaPronostic(
        courseKey: cle,
        nomCourse: 'PRIX',
        hippodrome: 'VINCENNES',
        discipline: 'Trot Attelé',
        datePronostic: jour,
        scoresIA: const {'1': 100, '2': 92, '3': 84, '4': 76, '5': 68},
        typePariConseille: 'Quinté+',
        arriveeReelle: null,
        resultatsReels: true,
        dateResultat: jour.add(const Duration(hours: 1)),
      );
      // v2 : résolu COMPLET → rang 2, donc plus autoritaire.
      final v2 = _pronoGagnant(courseKey: cle, date: jour);

      await _archiver([v1, v2]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d[21]!.nbCourses, 1, reason: 'une seule journée, une seule course');
      expect(d[21]!.pronostics.length, 1);
      expect(d[21]!.pronostics.single.arriveeReelle, isNotNull,
          reason: 'la version retenue doit être la version complète');
      expect(d[21]!.nbBons, 1);
    });

    test('E-2 — version retenue hors mois : aucune résurrection par la '
        'version écartée', () async {
      final mars = _jour(22);
      final avril = DateTime(2024, 4, 22);
      final cle = 'R1C1_PARTAGE';

      final faible = IaPronostic(
        courseKey: cle,
        nomCourse: 'PRIX',
        hippodrome: 'VINCENNES',
        discipline: 'Trot Attelé',
        datePronostic: mars,
        scoresIA: const {'1': 100, '2': 90, '3': 80, '4': 70, '5': 60},
        typePariConseille: 'Quinté+',
        resultatsReels: false,
      );
      final forte = _pronoGagnant(courseKey: cle, date: avril);

      await _archiver([faible, forte]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d.containsKey(22), isFalse,
          reason: 'la version retenue (avril) est hors mois : rien à afficher');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  F — LECTURE SEULE
  // ═══════════════════════════════════════════════════════════════════════

  group('F — l\'archive reste en lecture seule', () {
    test('F-1 — le calendrier n\'ajoute AUCUN pronostic à la mémoire',
        () async {
      final jour = _jour(23);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final avant = IaMemoryService.instance.pronostics.length;
      IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      final apres = IaMemoryService.instance.pronostics.length;

      expect(apres, avant);
      expect(apres, 0);
      expect(
        IaMemoryService.instance.pronostics
            .any((p) => p.courseKey == _cleCourse(1, 1, jour)),
        isFalse,
      );
    });

    test('F-2 — le nombre de versions archivées ne varie pas', () async {
      final jour = _jour(24);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final avant = IaArchiveService.instance.nbVersionsArchivees;
      IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(IaArchiveService.instance.nbVersionsArchivees, avant);
    });

    test('F-3 — le calendrier n\'écrit rien sur le stockage', () async {
      final jour = _jour(25);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final lecturesAvant = _store.nbLectures;
      IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(_store.nbLectures, lecturesAvant,
          reason: 'la fusion travaille exclusivement en RAM');
    });

    test('F-4 — appel répété : résultat identique (déterminisme)', () async {
      final jour = _jour(26);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
        _pronoPerdant(courseKey: _cleCourse(1, 2, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final a = _instantane(_moisRef.year, _moisRef.month);
      final b = _instantane(_moisRef.year, _moisRef.month);
      expect(b, a);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G — DÉGÉNÉRESCENCE SI L'ARCHIVE N'EST PAS CHARGÉE
  // ═══════════════════════════════════════════════════════════════════════

  group('G — sans archive chargée, comportement d\'avant E2', () {
    test('G-1 — archive non chargée : seules les journées mémoire existent',
        () async {
      final jMem = _jour(2);
      final jArch = _jour(27);
      await _preparerMemoire([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jMem), date: jMem),
      ]);

      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jArch), date: jArch),
      ]);
      // Volontairement : PAS de charger().
      IaArchiveService.instance.oublierChargementPourTest();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d.keys.toSet(), <int>{2});
    });

    test('G-2 — après chargement, la journée d\'archive apparaît', () async {
      final jArch = _jour(27);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jArch), date: jArch),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();

      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(_moisRef.year, _moisRef.month),
        isEmpty,
      );

      await IaArchiveService.instance.charger();

      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(_moisRef.year, _moisRef.month)
            .containsKey(27),
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  H — CHARGEMENT ASYNCHRONE (condition 6)
  // ═══════════════════════════════════════════════════════════════════════

  group('H — chargement asynchrone sécurisé', () {
    test('H-1 — notification APRÈS disponibilité réelle, une seule fois',
        () async {
      final jour = _jour(28);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();

      var notifications = 0;
      bool? dispoAuMomentDeLaNotification;
      void ecouteur() {
        notifications++;
        dispoAuMomentDeLaNotification =
            IaArchiveService.instance.archiveDisponible;
      }

      IaArchiveService.instance.addListener(ecouteur);
      try {
        await IaArchiveService.instance.charger();
      } finally {
        IaArchiveService.instance.removeListener(ecouteur);
      }

      expect(notifications, 1, reason: 'une seule notification par cycle');
      expect(dispoAuMomentDeLaNotification, isTrue,
          reason: 'la notification doit suivre la disponibilité réelle');
      expect(IaArchiveService.instance.archiveDisponible, isTrue);
      expect(IaArchiveService.instance.derniereErreurChargement, isNull);
    });

    test('H-2 — aucun chargement concurrent : trois appels simultanés',
        () async {
      final jour = _jour(29);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();

      var notifications = 0;
      void ecouteur() => notifications++;
      IaArchiveService.instance.addListener(ecouteur);
      try {
        await Future.wait([
          IaArchiveService.instance.charger(),
          IaArchiveService.instance.charger(),
          IaArchiveService.instance.charger(),
        ]);
      } finally {
        IaArchiveService.instance.removeListener(ecouteur);
      }

      expect(notifications, 1,
          reason: 'les appels concurrents partagent un seul cycle');
      expect(IaArchiveService.instance.archiveDisponible, isTrue);
      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d[29]!.nbCourses, 1);
    });

    test('H-3 — idempotence : un second charger() ne notifie plus', () async {
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      var notifications = 0;
      void ecouteur() => notifications++;
      IaArchiveService.instance.addListener(ecouteur);
      try {
        await IaArchiveService.instance.charger();
        await IaArchiveService.instance.charger();
      } finally {
        IaArchiveService.instance.removeListener(ecouteur);
      }
      expect(notifications, 0, reason: 'déjà chargée : aucun nouvel état');
    });

    test('H-4 — échec : notifié, état NON disponible, puis reprise réussie',
        () async {
      final jour = _jour(30);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      // SharedPreferences met l'instance en CACHE STATIQUE : sans ce reset,
      // activer la panne ne provoquerait aucune lecture réelle.
      SharedPreferences.resetStatic();

      _store.panne = true;
      var notifications = 0;
      bool? dispoEchec;
      void ecouteur() {
        notifications++;
        dispoEchec = IaArchiveService.instance.archiveDisponible;
      }

      IaArchiveService.instance.addListener(ecouteur);
      try {
        await IaArchiveService.instance.charger(); // ne doit pas lever
      } finally {
        IaArchiveService.instance.removeListener(ecouteur);
      }

      expect(notifications, 1, reason: 'l\'échec est signalé, pas silencieux');
      expect(dispoEchec, isFalse);
      expect(IaArchiveService.instance.archiveDisponible, isFalse);
      expect(IaArchiveService.instance.derniereErreurChargement, isNotNull);

      // L'affichage n'est pas figé : la mémoire seule reste visible.
      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(_moisRef.year, _moisRef.month),
        isEmpty,
      );

      // Nouvelle tentative après retour à la normale.
      _store.panne = false;
      await IaArchiveService.instance.charger();

      expect(IaArchiveService.instance.archiveDisponible, isTrue);
      expect(IaArchiveService.instance.derniereErreurChargement, isNull);
      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d[30]!.nbCourses, 1,
          reason: 'la reprise doit rendre l\'archive exploitable');
    });

    test('H-5 — l\'erreur est effacée par une reprise réussie', () async {
      IaArchiveService.instance.oublierChargementPourTest();
      SharedPreferences.resetStatic();
      _store.panne = true;
      await IaArchiveService.instance.charger();
      expect(IaArchiveService.instance.derniereErreurChargement, isNotNull);

      _store.panne = false;
      await IaArchiveService.instance.charger();
      expect(IaArchiveService.instance.derniereErreurChargement, isNull);
      expect(IaArchiveService.instance.archiveDisponible, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  I — MOIS PARTIELLEMENT COUVERT
  // ═══════════════════════════════════════════════════════════════════════

  group('I — mois partiellement couvert', () {
    test('I-1 — 3 jours mémoire + 2 jours archive = 5 jours', () async {
      final m1 = _jour(2), m2 = _jour(4), m3 = _jour(6);
      await _preparerMemoire([
        _pronoGagnant(courseKey: _cleCourse(1, 1, m1), date: m1),
        _pronoGagnant(courseKey: _cleCourse(1, 1, m2), date: m2),
        _pronoGagnant(courseKey: _cleCourse(1, 1, m3), date: m3),
      ]);

      final a1 = _jour(8), a2 = _jour(10);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(2, 1, a1), date: a1),
        _pronoGagnant(courseKey: _cleCourse(2, 1, a2), date: a2),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d.keys.toSet(), <int>{2, 4, 6, 8, 10});
      expect(d.length, 5);
    });

    test('I-2 — AUTRE course du même jour : ajoutée sans écraser la mémoire',
        () async {
      final jour = _jour(3);
      await _preparerMemoire([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
      ]);

      await _archiver([
        _pronoPerdant(courseKey: _cleCourse(1, 9, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d[3]!.nbCourses, 2);
      expect(d[3]!.nbBons, 1);
      expect(d[3]!.pronostics.map((p) => p.courseKey),
          contains(_cleCourse(1, 9, jour)));
    });

    test('I-3 — même courseKey sur le même jour : mémoire gagne, pas de '
        'doublon', () async {
      final jour = _jour(5);
      final cle = _cleCourse(1, 1, jour);
      await _preparerMemoire([
        _pronoGagnant(courseKey: cle, date: jour),
      ]);

      await _archiver([_pronoPerdant(courseKey: cle, date: jour)]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d[5]!.nbCourses, 1);
      expect(d[5]!.nbBons, 1, reason: 'version mémoire conservée');
    });

    test('I-4 — mois entièrement en mémoire : instantané inchangé', () async {
      final jours = [_jour(11), _jour(12), _jour(13)];
      await _preparerMemoire([
        for (final j in jours)
          _pronoGagnant(courseKey: _cleCourse(1, 1, j), date: j),
      ]);

      final avant = _instantane(_moisRef.year, _moisRef.month);
      await IaArchiveService.instance.charger();
      final apres = _instantane(_moisRef.year, _moisRef.month);
      expect(apres, avant);
    });

    test('I-5 — mois entièrement en archive : toutes les journées visibles',
        () async {
      final jours = [_jour(14), _jour(15), _jour(16)];
      await _archiver([
        for (final j in jours)
          _pronoGagnant(courseKey: _cleCourse(3, 1, j), date: j),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d.keys.toSet(), <int>{14, 15, 16});
    });

    test('I-6 — version retenue hors mois : aucune journée créée', () async {
      final dedans = _jour(17);
      final dehors = DateTime(2024, 5, 17);
      final cle = 'R9C9_PARTAGE';

      await _archiver([
        IaPronostic(
          courseKey: cle,
          nomCourse: 'PRIX',
          hippodrome: 'VINCENNES',
          discipline: 'Trot Attelé',
          datePronostic: dedans,
          scoresIA: const {'1': 100, '2': 90, '3': 80, '4': 70, '5': 60},
          typePariConseille: 'Quinté+',
          resultatsReels: false,
        ),
        _pronoGagnant(courseKey: cle, date: dehors),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final d = IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);
      expect(d.containsKey(17), isFalse);
    });

    test('I-7 — pronostic archivé non résolu : aucune journée', () async {
      final jour = _jour(18);
      await _archiver([
        _prono(courseKey: _cleCourse(5, 1, jour), date: jour, resolu: false),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();
      expect(
        IaMemoryService.instance
            .donneesCalendrierJour(_moisRef.year, _moisRef.month),
        isEmpty,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  J — NON-RÉINJECTION DANS L'APPRENTISSAGE
  // ═══════════════════════════════════════════════════════════════════════

  group('J — aucune réinjection dans l\'apprentissage', () {
    test('J-1 — poids et seuils strictement inchangés après lecture',
        () async {
      final jour = _jour(20);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jour), date: jour),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();

      final poidsAvant =
          json.encode(IaMemoryService.instance.poids.toJson());
      final seuilsAvant =
          json.encode(IaMemoryService.instance.seuilsConfiance.toJson());

      IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);

      expect(json.encode(IaMemoryService.instance.poids.toJson()), poidsAvant);
      expect(json.encode(IaMemoryService.instance.seuilsConfiance.toJson()),
          seuilsAvant);
    });

    test('J-2 — mémoire de travail strictement inchangée (contenu)',
        () async {
      final jourMem = _jour(21);
      await _preparerMemoire([
        _pronoGagnant(courseKey: _cleCourse(1, 1, jourMem), date: jourMem),
      ]);

      final avant = IaMemoryService.instance.pronostics
          .map((p) => json.encode(p.toJson()))
          .toList();

      final jourArch = _jour(22);
      await _archiver([
        _pronoGagnant(courseKey: _cleCourse(2, 1, jourArch), date: jourArch),
      ]);
      IaArchiveService.instance.oublierChargementPourTest();
      await IaArchiveService.instance.charger();
      IaMemoryService.instance.donneesCalendrierJour(
          _moisRef.year, _moisRef.month);

      final apres = IaMemoryService.instance.pronostics
          .map((p) => json.encode(p.toJson()))
          .toList();

      expect(apres, avant);
    });
  });
}
