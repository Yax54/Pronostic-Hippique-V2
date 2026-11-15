// ═══════════════════════════════════════════════════════════════════════════
//  V48 — A2 : ARBITRAGE ACTIF / ARCHIVE PAR AUTORITÉ
//
//  DÉFAUT CORRIGÉ
//    Pour un même `courseKey`, la sélection entre la mémoire de travail et
//    l'archive était BINAIRE et AVEUGLE : `getPronostic(...) ?? versionRetenue(...)`
//    d'une part, `if (clesEnMemoire.contains(cle)) continue` d'autre part.
//    Une fiche ACTIVE non résolue (rang 0, la plus faible) masquait donc une
//    fiche ARCHIVÉE résolue complète (rang 2, la plus forte) :
//      • la victoire Premium était ignorée → série interrompue à tort ;
//      • la journée disparaissait du calendrier ;
//      • le bilan mensuel devenait incomplet.
//
//  RÈGLE APPLIQUÉE (lecture seule, `_versionLaPlusAutoritaire`)
//    0. dates différentes     → actif (garde de cohérence de mois) ;
//    1. archive absente       → actif (comportement historique) ;
//    2. actif absent          → archive ;
//    3. actif résolu, archive non → actif ;
//    4. actif non résolu, archive résolue → ARCHIVE ;
//    5. deux résolues         → `IaArchiveService.comparerAutorite` ;
//    6. deux non résolues     → actif ;
//    7. autorité égale        → actif.
//
//  CE QUE CES TESTS VERROUILLENT
//    • l'anomalie est corrigée sur les DEUX sites (A1 et E2) ;
//    • les six autres règles sont respectées ;
//    • aucune duplication de course, aucun double comptage ;
//    • aucune invention de résultat, aucune recombinaison de champs ;
//    • `_pronostics`, `_poids`, `_seuils` et l'archive sont INCHANGÉS ;
//    • `getPronostic()` reste strictement mémoire-active seule ;
//    • rien n'est réinjecté dans l'apprentissage.
//
//  MÉTHODE : store simulé identique à V16/V42 (blob `ia_pronostics_v2_gz` +
//  shards `ia_archive_v1_YYYY-MM` écrits à la main, hors API d'écriture).
//  Dates FIXES en mars 2024 : aucune dépendance à l'horloge pour le
//  calendrier. Les tests de série Premium utilisent, comme V42, des jours
//  relatifs à aujourd'hui, car `calculerStreakPremium` remonte depuis une
//  date de référence fournie.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/pronostic_resultats_repository.dart';
import 'package:pronostic_hippique/services/quasi_gros_paris_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  FAUX STORE (autonome, même principe que V16)
// ═══════════════════════════════════════════════════════════════════════════

class _FauxStore extends SharedPreferencesStorePlatform {
  _FauxStore({Map<String, Object>? data})
      : _data = <String, Object>{
          for (final e in (data ?? const <String, Object>{}).entries)
            (e.key.startsWith('flutter.') ? e.key : 'flutter.${e.key}'):
                e.value,
        };

  final Map<String, Object> _data;

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
    _data[key] = value;
    return true;
  }

  /// Copie du contenu, préfixe retiré (lecture seule, pour les assertions).
  Map<String, Object> instantane() => <String, Object>{
        for (final e in _data.entries)
          if (e.key.startsWith('flutter.'))
            e.key.substring('flutter.'.length): e.value,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
//  CONSTANTES ET OUTILS
// ═══════════════════════════════════════════════════════════════════════════

const String _kPronosticsKey = 'ia_pronostics_v2_gz';
const String _kPoidsKey = 'ia_poids_v3';
const String _kSeuilsKey = 'ia_seuils_v1';
const String _kPremiumKey = 'ia_premium_historique_v1';
const String _kShardPrefix = 'ia_archive_v1_';
const String _kManifestKey = 'ia_archive_v1_manifest';

/// Mois de référence des tests calendrier : mars 2024, passé stable.
final DateTime _moisRef = DateTime(2024, 3, 1);

DateTime _jour(int jour) => DateTime(_moisRef.year, _moisRef.month, jour);

String _ddmmyyyy(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String _cleCourse(int r, int c, DateTime d) => 'R${r}C${c}_${_ddmmyyyy(d)}';

String _mois(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// Clé de date `YYYY-MM-DD` lue par `calculerStreakPremium`.
String _dk(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Arrivée où le favori IA (n°1) gagne → Tiercé {1,2,3} = GAGNANT.
const List<int> _kArriveeGagnante = <int>[1, 2, 3, 4, 5];

/// Arrivée où aucun cheval de la sélection IA n'est placé.
const List<int> _kArriveePerdante = <int>[9, 10, 11, 12, 13];

const Map<String, double> _kScoresIA = <String, double>{
  '1': 100.0, '2': 92.0, '3': 84.0, '4': 76.0, '5': 68.0,
};

const List<String> _kNumerosTierce = <String>['1', '2', '3'];

/// Fiche de pronostic paramétrable. `resolu == false` ⇒ rang 0.
IaPronostic _prono({
  required String courseKey,
  required DateTime date,
  bool resolu = true,
  List<int>? arrivee,
  String typePari = 'Tiercé',
  double confiance = 71.0,
  double variance = 12.5,
  String? favoriNom = 'Cheval 1',
  int? rangFavori = 1,
  int? nbTop3 = 3,
  int? nbTop5 = 5,
  double? scorePerf = 60.0,
  Map<String, double>? cotes,
  Map<String, ScoresCriteres>? criteres,
}) =>
    IaPronostic(
      courseKey: courseKey,
      nomCourse: 'Course $courseKey',
      hippodrome: 'Vincennes',
      discipline: 'Trot Attelé',
      datePronostic: date,
      dateResultat: resolu ? date.add(const Duration(hours: 2)) : null,
      scoresIA: _kScoresIA,
      scoresCriteres: criteres ?? const <String, ScoresCriteres>{},
      resultatsReels: resolu,
      arriveeReelle: resolu ? (arrivee ?? _kArriveeGagnante) : null,
      typePariConseille: typePari,
      confiancePredite: confiance,
      varianceScores: variance,
      favoriIaNom: favoriNom,
      rangFavoriIaDansArrivee: resolu ? rangFavori : null,
      nbTop3DansArriveeReelle: resolu ? nbTop3 : 0,
      nbTop5DansArriveeReelle: resolu ? nbTop5 : 0,
      scorePerformance: resolu ? scorePerf : null,
      coteFavoriPmu: (cotes ?? const <String, double>{'1': 3.4})['1'],
      cotesPmuParNumero: cotes ?? const <String, double>{'1': 3.4},
    );

/// Entrée d'historique premium (sélection Best Bet figée d'un jour).
Map<String, dynamic> _premiumJson({
  required String courseKey,
  String source = 'conseilJour',
  String typePari = 'Tiercé',
  List<String> numeros = _kNumerosTierce,
}) =>
    <String, dynamic>{
      'courseKey': courseKey,
      'typePari': typePari,
      'numeros': numeros,
      'sourceWidget': source,
    };

/// Encode des versions au format réel d'un shard : base64(gzip(json)).
String _encoderShard(List<IaPronostic> versions) {
  final jsonStr =
      json.encode(versions.map((p) => p.toJson()).toList(growable: false));
  return base64Encode(GZipCodec().encode(utf8.encode(jsonStr)));
}

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

/// Construit le contenu du store : mémoire active + archive + premium.
Map<String, Object> _construireStore({
  List<IaPronostic> enMemoire = const <IaPronostic>[],
  List<IaPronostic> enArchive = const <IaPronostic>[],
  Map<String, List<Map<String, dynamic>>> premiumParDate =
      const <String, List<Map<String, dynamic>>>{},
}) {
  final store = _prefsPoids();
  store[_kPronosticsKey] = base64Encode(GZipCodec().encode(
      utf8.encode(json.encode(enMemoire.map((p) => p.toJson()).toList()))));
  store[_kPremiumKey] = json.encode(<String, dynamic>{
    'entries': premiumParDate,
  });

  final parMois = <String, List<IaPronostic>>{};
  for (final p in enArchive) {
    parMois.putIfAbsent(_mois(p.datePronostic), () => <IaPronostic>[]).add(p);
  }
  final mois = <String>[];
  for (final e in parMois.entries) {
    store['$_kShardPrefix${e.key}'] = _encoderShard(e.value);
    mois.add(e.key);
  }
  if (mois.isNotEmpty) {
    store[_kManifestKey] = json.encode(<String, dynamic>{'mois': mois});
  }
  return store;
}

late _FauxStore _store;

/// Installe le store, recharge la mémoire IA, puis (si demandé) l'archive.
Future<void> _amorcer(
  Map<String, Object> store, {
  required bool chargerArchive,
}) async {
  _store = _FauxStore(data: store);
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = _store;
  IaArchiveService.instance.oublierChargementPourTest();
  await IaMemoryService.instance.recharger();
  if (chargerArchive) {
    await IaArchiveService.instance.charger();
  }
}

/// Série Premium pour une source et une date de référence.
int _serie(String source, DateTime dateReference) => IaMemoryService.instance
    .calculerStreakPremium(sourceWidget: source, dateReference: dateReference)
    .jours;

/// Calendrier du mois de référence.
Map<int, DonneeJourCalendrier> _calendrier() =>
    IaMemoryService.instance.donneesCalendrierJour(_moisRef.year, _moisRef.month);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  /// Jour J-n, sans dérive d'heure (même convention que V42).
  DateTime j(int n) => today.subtract(Duration(days: n));

  setUp(() async {
    await _amorcer(_construireStore(), chargerArchive: false);
    await PronosticResultatsRepository.instance
        .restaurerDepuisBackup({'pronosticResultats': []});
    await QuasiGrosParisService.instance
        .importerDepuisBackup({'signaux': [], 'quasiGagnants': []});
    await EloService.instance.reinitialiser();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  GROUPE A — LE DÉFAUT EST CORRIGÉ
  // ═══════════════════════════════════════════════════════════════════════

  group('A2-A — actif non résolu, archive résolue : l\'ARCHIVE gagne', () {
    test('A2-T1 — calendrier : la journée redevient visible', () async {
      final jour = _jour(8);
      final cle = _cleCourse(1, 1, jour);

      await _amorcer(
        _construireStore(
          // Mémoire : fiche NON résolue (rang 0), même courseKey.
          enMemoire: [_prono(courseKey: cle, date: jour, resolu: false)],
          // Archive : fiche RÉSOLUE et GAGNANTE (rang 2).
          enArchive: [_prono(courseKey: cle, date: jour)],
        ),
        chargerArchive: true,
      );

      // L'anomalie d'origine est bien présente côté mémoire active…
      expect(IaMemoryService.instance.getPronostic(cle)?.resultatsReels, isFalse,
          reason: 'la mémoire active contient bien la fiche non résolue');
      expect(IaArchiveService.instance.versionRetenue(cle)?.resultatsReels,
          isTrue, reason: 'l\'archive contient bien la fiche résolue');

      // …et la lecture arbitrée retient l'archive.
      final d = _calendrier();
      expect(d.containsKey(8), isTrue,
          reason: 'A2 : la journée doit être retrouvée via la fiche archivée');
      expect(d[8]!.nbCourses, 1, reason: 'une seule course, aucun doublon');
      expect(d[8]!.pronostics.length, 1);
      expect(d[8]!.pronostics.single.courseKey, cle);
      expect(d[8]!.pronostics.single.resultatsReels, isTrue,
          reason: 'la version retenue est la version RÉSOLUE');
      expect(d[8]!.nbBons, 1, reason: 'la victoire archivée est comptée');
    });

    test('A2-T2 — série Premium : la victoire est retrouvée', () async {
      final cle = _cleCourse(2, 1, j(1));

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: j(1), resolu: false)],
          enArchive: [_prono(courseKey: cle, date: j(1))],
          premiumParDate: {
            _dk(j(1)): [_premiumJson(courseKey: cle)],
          },
        ),
        chargerArchive: true,
      );

      expect(_serie('conseilJour', j(1)), 1,
          reason: 'A2 : la série ne doit plus retomber à 0 — la fiche '
              'archivée résolue porte la victoire');
    });

    test('A2-T3 — série Premium multi-jours : la continuité est préservée',
        () async {
      final cleJ1 = _cleCourse(3, 1, j(1));
      final cleJ2 = _cleCourse(3, 2, j(2));

      await _amorcer(
        _construireStore(
          enMemoire: [
            // J-1 : active NON résolue, archive résolue → la série doit tenir.
            _prono(courseKey: cleJ1, date: j(1), resolu: false),
            // J-2 : entièrement résolue en mémoire → référence.
            _prono(courseKey: cleJ2, date: j(2)),
          ],
          enArchive: [_prono(courseKey: cleJ1, date: j(1))],
          premiumParDate: {
            _dk(j(1)): [_premiumJson(courseKey: cleJ1)],
            _dk(j(2)): [_premiumJson(courseKey: cleJ2)],
          },
        ),
        chargerArchive: true,
      );

      expect(_serie('conseilJour', j(1)), 2,
          reason: 'A2 : 2 jours consécutifs malgré la fiche active non résolue '
              'au jour J-1 — la série n\'est plus interrompue à tort');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  GROUPE B — LES AUTRES RÈGLES SONT RESPECTÉES
  // ═══════════════════════════════════════════════════════════════════════

  group('A2-B — règles 3 à 7 de l\'arbitrage', () {
    test('A2-T4 — actif RÉSOLU, archive NON résolue : l\'ACTIF gagne',
        () async {
      final jour = _jour(9);
      final cle = _cleCourse(1, 2, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour)],
          enArchive: [_prono(courseKey: cle, date: jour, resolu: false)],
        ),
        chargerArchive: true,
      );

      final d = _calendrier();
      expect(d.containsKey(9), isTrue);
      expect(d[9]!.pronostics.single.resultatsReels, isTrue,
          reason: 'règle 3 : jamais de rétrogradation vers l\'archive');
      expect(d[9]!.nbBons, 1);
    });

    test('A2-T5 — deux versions RÉSOLUES : la plus COMPLÈTE gagne', () async {
      final jour = _jour(10);
      final cle = _cleCourse(1, 3, jour);

      // Version pauvre : résolue mais presque aucun champ renseigné.
      final pauvre = IaPronostic(
        courseKey: cle,
        nomCourse: 'Course $cle',
        hippodrome: 'Vincennes',
        discipline: 'Trot Attelé',
        datePronostic: jour,
        scoresIA: _kScoresIA,
        resultatsReels: true,
        arriveeReelle: _kArriveeGagnante,
        dateResultat: jour.add(const Duration(hours: 2)),
        typePariConseille: 'Tiercé',
      );
      // Version riche : tous les champs de complétude renseignés.
      final riche = _prono(courseKey: cle, date: jour);

      await _amorcer(
        _construireStore(enMemoire: [pauvre], enArchive: [riche]),
        chargerArchive: true,
      );

      // La complétude est l'arbitre (rang égal = 2 des deux côtés).
      expect(IaArchiveService.rangDe(pauvre), 2);
      expect(IaArchiveService.rangDe(riche), 2);
      expect(IaArchiveService.completudeDe(riche),
          greaterThan(IaArchiveService.completudeDe(pauvre)),
          reason: 'prérequis du test : la fiche archivée est plus complète');
      expect(IaArchiveService.comparerAutorite(riche, pauvre), greaterThan(0),
          reason: 'prérequis : l\'autorité désigne la fiche riche');

      final d = _calendrier();
      expect(d[10]!.nbCourses, 1);
      expect(d[10]!.pronostics.single.courseKey, cle);
      expect(d[10]!.pronostics.single.varianceScores, isNotNull,
          reason: 'la fiche retenue est la version complète (archive)');
      expect(d[10]!.pronostics.single.favoriIaNom, 'Cheval 1');
    });

    test('A2-T6 — autorité ÉGALE : priorité ACTIVE conservée', () async {
      final jour = _jour(11);
      final cle = _cleCourse(1, 4, jour);

      // Deux fiches dont l'EMPREINTE et l'AUTORITÉ sont strictement égales :
      // `nomCourse` n'entre ni dans `empreinteDe` ni dans `completudeDe`, il
      // sert donc de marqueur observable pour savoir QUELLE fiche est retenue.
      // (L'identité d'objet n'est pas utilisable : la fiche est désérialisée
      // depuis le blob JSON, ce n'est jamais la même instance.)
      IaPronostic marquee(IaPronostic p, String nom) => IaPronostic(
            courseKey: p.courseKey,
            nomCourse: nom,
            hippodrome: p.hippodrome,
            discipline: p.discipline,
            datePronostic: p.datePronostic,
            dateResultat: p.dateResultat,
            scoresIA: p.scoresIA,
            scoresCriteres: p.scoresCriteres,
            varianceScores: p.varianceScores,
            confiancePredite: p.confiancePredite,
            arriveeReelle: p.arriveeReelle,
            resultatsReels: p.resultatsReels,
            rangFavoriIaDansArrivee: p.rangFavoriIaDansArrivee,
            nbTop3DansArriveeReelle: p.nbTop3DansArriveeReelle,
            nbTop5DansArriveeReelle: p.nbTop5DansArriveeReelle,
            scorePerformance: p.scorePerformance,
            typePariConseille: p.typePariConseille,
            favoriIaNom: p.favoriIaNom,
            coteFavoriPmu: p.coteFavoriPmu,
            cotesPmuParNumero: p.cotesPmuParNumero,
          );

      final base = _prono(courseKey: cle, date: jour);
      final active = marquee(base, 'MARQUEUR_ACTIVE');
      final archive = marquee(base, 'MARQUEUR_ARCHIVE');

      expect(IaArchiveService.empreinteDe(active),
          IaArchiveService.empreinteDe(archive),
          reason: 'prérequis : empreintes identiques (nomCourse exclu)');
      expect(IaArchiveService.comparerAutorite(archive, active), 0,
          reason: 'prérequis : autorité strictement égale');
      expect(IaArchiveService.rangDe(archive) > 0, isTrue,
          reason: 'prérequis : les deux fiches sont résolues — on teste bien '
              'la règle 5/7, pas la règle 4');

      await _amorcer(
        _construireStore(enMemoire: [active], enArchive: [archive]),
        chargerArchive: true,
      );

      final d = _calendrier();
      expect(d[11]!.nbCourses, 1, reason: 'aucun doublon');
      expect(d[11]!.pronostics.length, 1);
      expect(d[11]!.pronostics.single.nomCourse, 'MARQUEUR_ACTIVE',
          reason: 'règle 7 : à autorité égale, la fiche ACTIVE est retenue');
    });

    test('A2-T7 — archive ABSENTE : comportement historique inchangé',
        () async {
      final jour = _jour(12);
      final cle = _cleCourse(1, 5, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour, resolu: false)],
        ),
        chargerArchive: true,
      );

      final d = _calendrier();
      expect(d.containsKey(12), isFalse,
          reason: 'règle 1 : sans archive, une fiche non résolue ne crée '
              'aucune journée (aucune invention)');
    });

    test('A2-T8 — deux fiches NON RÉSOLUES : aucune substitution', () async {
      final jour = _jour(13);
      final cle = _cleCourse(1, 6, jour);

      final active = _prono(courseKey: cle, date: jour, resolu: false);
      final archive = _prono(courseKey: cle, date: jour, resolu: false);

      await _amorcer(
        _construireStore(enMemoire: [active], enArchive: [archive]),
        chargerArchive: true,
      );

      expect(_calendrier().containsKey(13), isFalse,
          reason: 'règle 6 : deux fiches non résolues ne peuvent créer une '
              'journée');
      expect(IaMemoryService.instance.getPronostic(cle), isNotNull,
          reason: 'la fiche active reste en mémoire');
    });

    test('A2-T9 — archive NON CHARGÉE : dégénérescence exacte', () async {
      final jour = _jour(14);
      final cle = _cleCourse(1, 7, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour)],
          enArchive: [_prono(courseKey: cle, date: jour)],
        ),
        // Archive volontairement NON chargée.
        chargerArchive: false,
      );

      expect(IaArchiveService.instance.archiveDisponible, isFalse);
      final d = _calendrier();
      expect(d[14]!.nbCourses, 1, reason: 'la mémoire seule suffit');
      expect(d[14]!.nbBons, 1,
          reason: 'comportement identique à avant A2 quand l\'archive est '
              'indisponible');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  GROUPE C — UNICITÉ, PAS DE DOUBLE COMPTAGE
  // ═══════════════════════════════════════════════════════════════════════

  group('A2-C — unicité des courses par courseKey', () {
    test('A2-T10 — deux courses du même jour : aucune fusion', () async {
      final jour = _jour(15);
      final c1 = _cleCourse(2, 1, jour);
      final c2 = _cleCourse(2, 2, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: c1, date: jour, resolu: false)],
          enArchive: [
            _prono(courseKey: c1, date: jour),   // même course → arbitrée
            _prono(courseKey: c2, date: jour),   // course distincte
          ],
        ),
        chargerArchive: true,
      );

      final d = _calendrier();
      expect(d[15]!.nbCourses, 2,
          reason: 'deux courses distinctes, pas une de plus');
      expect(d[15]!.pronostics.map((p) => p.courseKey).toSet(), <String>{c1, c2});
      expect(d[15]!.pronostics.length, 2, reason: 'aucun doublon');
      expect(d[15]!.nbBons, 2, reason: 'les deux sont gagnantes');
    });

    test('A2-T11 — la course arbitrée n\'est jamais comptée deux fois',
        () async {
      final jour = _jour(16);
      final cle = _cleCourse(3, 1, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour, resolu: false)],
          enArchive: [
            _prono(courseKey: cle, date: jour),
            // Doublon volontaire dans le shard : le dédoublonnage doit tenir.
            _prono(courseKey: cle, date: jour),
          ],
        ),
        chargerArchive: true,
      );

      final d = _calendrier();
      expect(d[16]!.nbCourses, 1);
      expect(d[16]!.pronostics.length, 1);
      expect(d[16]!.nbBons, 1, reason: 'une seule victoire comptée');
      expect(d[16]!.taux, closeTo(1.0, 1e-9));
    });

    test('A2-T12 — la version substituée garde la DATE de sa course',
        () async {
      final jour = _jour(17);
      final cle = _cleCourse(4, 1, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour, resolu: false)],
          enArchive: [_prono(courseKey: cle, date: jour)],
        ),
        chargerArchive: true,
      );

      final d = _calendrier();
      expect(d[17]!.pronostics.single.datePronostic, jour,
          reason: 'la date vient de la FICHE, jamais du mois affiché');
      expect(d.containsKey(17), isTrue);
      expect(d.length, 1, reason: 'une seule journée alimentée');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  GROUPE D — LECTURE SEULE : RIEN N'EST MODIFIÉ
  // ═══════════════════════════════════════════════════════════════════════

  group('A2-D — lecture seule et apprentissage intact', () {
    test('A2-T13 — mémoire active strictement inchangée', () async {
      final jour = _jour(18);
      final cle = _cleCourse(5, 1, jour);
      final active = _prono(courseKey: cle, date: jour, resolu: false);

      await _amorcer(
        _construireStore(
          enMemoire: [active],
          enArchive: [_prono(courseKey: cle, date: jour)],
        ),
        chargerArchive: true,
      );

      final avant = IaMemoryService.instance.pronostics
          .map((p) => IaArchiveService.empreinteDe(p))
          .toList();
      final nbAvant = IaMemoryService.instance.pronostics.length;

      // Déclenche les deux sites A2.
      _calendrier();
      _serie('conseilJour', j(1));

      final apres = IaMemoryService.instance.pronostics
          .map((p) => IaArchiveService.empreinteDe(p))
          .toList();
      expect(apres, avant,
          reason: 'A2 ne réinjecte jamais l\'archive dans _pronostics');
      expect(IaMemoryService.instance.pronostics.length, nbAvant);
      expect(IaMemoryService.instance.getPronostic(cle)?.resultatsReels, isFalse,
          reason: 'la fiche active n\'est pas « complétée » sur place');
    });

    test('A2-T14 — poids et seuils strictement inchangés', () async {
      final jour = _jour(19);
      final cle = _cleCourse(5, 2, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour, resolu: false)],
          enArchive: [_prono(courseKey: cle, date: jour)],
        ),
        chargerArchive: true,
      );

      final poidsAvant = json.encode(IaMemoryService.instance.poids.toJson());
      final seuilsAvant = json.encode(IaMemoryService.instance.seuilsConfiance.toJson());

      _calendrier();
      _serie('conseilJour', j(1));
      _serie('meilleurPari', j(1));

      expect(json.encode(IaMemoryService.instance.poids.toJson()), poidsAvant,
          reason: 'aucun apprentissage déclenché par A2');
      expect(json.encode(IaMemoryService.instance.seuilsConfiance.toJson()),
          seuilsAvant,
          reason: 'les seuils ne bougent pas');
    });

    test('A2-T15 — archive strictement inchangée (aucune écriture)', () async {
      final jour = _jour(20);
      final cle = _cleCourse(5, 3, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour, resolu: false)],
          enArchive: [_prono(courseKey: cle, date: jour)],
        ),
        chargerArchive: true,
      );

      final nbVersionsAvant = IaArchiveService.instance.nbVersionsArchivees;
      final nbPredsAvant = IaArchiveService.instance.nbPredictionsDistinctes;
      final shardsAvant = Map<String, Object>.from(_store.instantane())
        ..removeWhere((k, _) => !k.startsWith(_kShardPrefix));

      _calendrier();
      _serie('conseilJour', j(1));

      expect(IaArchiveService.instance.nbVersionsArchivees, nbVersionsAvant,
          reason: 'aucune version ajoutée à l\'archive');
      expect(IaArchiveService.instance.nbPredictionsDistinctes, nbPredsAvant);
      final shardsApres = Map<String, Object>.from(_store.instantane())
        ..removeWhere((k, _) => !k.startsWith(_kShardPrefix));
      expect(shardsApres, shardsAvant,
          reason: 'aucun shard réécrit par une simple lecture');
    });

    test('A2-T16 — aucun résultat inventé : archive sans résultat → rien',
        () async {
      final jour = _jour(21);
      final cle = _cleCourse(5, 4, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour, resolu: false)],
          // Archive elle aussi non résolue : aucune arrivée n'existe nulle part.
          enArchive: [_prono(courseKey: cle, date: jour, resolu: false)],
        ),
        chargerArchive: true,
      );

      final d = _calendrier();
      expect(d.containsKey(21), isFalse,
          reason: 'sans résultat réel, aucune journée n\'est fabriquée');
      expect(IaArchiveService.instance.versionRetenue(cle)?.arriveeReelle,
          isNull,
          reason: 'aucune arrivée inventée dans l\'archive');
    });

    test('A2-T16b — prix du pari premium non satisfait : aucune victoire',
        () async {
      final cle = _cleCourse(5, 5, j(1));

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: j(1), resolu: false)],
          // Archive RÉSOLUE mais PERDANTE (aucun cheval IA dans l'arrivée).
          enArchive: [
            _prono(
              courseKey: cle,
              date: j(1),
              arrivee: _kArriveePerdante,
              rangFavori: null,
              nbTop3: 0,
              nbTop5: 0,
              scorePerf: 0.0,
            ),
          ],
          premiumParDate: {
            _dk(j(1)): [_premiumJson(courseKey: cle)],
          },
        ),
        chargerArchive: true,
      );

      expect(_serie('conseilJour', j(1)), 0,
          reason: 'A2 change la SOURCE, jamais la règle de victoire : une '
              'fiche résolue perdante ne produit aucune victoire');
    });

    test('A2-T17 — getPronostic reste mémoire-active seule', () async {
      final jour = _jour(22);
      final cle = _cleCourse(6, 1, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour, resolu: false)],
          enArchive: [_prono(courseKey: cle, date: jour)],
        ),
        chargerArchive: true,
      );

      expect(IaMemoryService.instance.getPronostic(cle)?.resultatsReels, isFalse,
          reason: 'getPronostic ne consulte JAMAIS l\'archive (contrat '
              'historique, utilisé par les gardes anti-recéation)');

      // Une course exclusivement archivée reste invisible de getPronostic.
      final cleArchive = _cleCourse(6, 2, jour);
      await _amorcer(
        _construireStore(
          enMemoire: const <IaPronostic>[],
          enArchive: [_prono(courseKey: cleArchive, date: jour)],
        ),
        chargerArchive: true,
      );
      expect(IaMemoryService.instance.getPronostic(cleArchive), isNull,
          reason: 'getPronostic ne voit que _pronostics');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  GROUPE E — COHÉRENCE DE DATE (GARDE CONSERVATRICE)
  // ═══════════════════════════════════════════════════════════════════════

  group('A2-E — garde de cohérence de date', () {
    test('A2-T18 — dates différentes : aucune substitution entre mois',
        () async {
      final jour = _jour(23);
      final cle = _cleCourse(7, 1, jour);
      final autreJour = DateTime(_moisRef.year, _moisRef.month, 28);

      // Fiche active NON résolue en mars, fiche archivée RÉSOLUE mais datée
      // d'un autre jour : la garde doit refuser la substitution.
      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour, resolu: false)],
          enArchive: [
            _prono(courseKey: cle, date: autreJour),
          ],
        ),
        chargerArchive: true,
      );

      final d = _calendrier();
      expect(d.containsKey(23), isFalse,
          reason: 'la garde empêche la substitution : la fiche active non '
              'résolue reste retenue, donc aucune journée');
      expect(d.containsKey(28), isFalse,
          reason: 'aucune journée déplacée sur la date de l\'archive');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  ★ R-1 — LA GARDE PORTE SUR LE JOUR CIVIL, JAMAIS SUR L'INSTANT.
    //
    //  Deux versions d'un MÊME `courseKey` partagent forcément le même jour
    //  (la clé encode `JJMMAAAA`) mais peuvent différer d'HEURE : une fiche
    //  héritée d'avant A-3 portait `DateTime.now()`, une fiche recréée sans
    //  `dateStr` porte minuit (sentinelle A-3-bis), le PMU peut corriger une
    //  heure de départ.
    //
    //  AVANT R-1, la comparaison d'INSTANT rejetait l'archive : la fiche
    //  active NON RÉSOLUE l'emportait et la correction A2 ne servait à rien.
    //  APRÈS R-1, l'arbitrage s'applique normalement : l'archive RÉSOLUE est
    //  retenue, la journée apparaît, la série Premium la retrouve.
    // ═════════════════════════════════════════════════════════════════════
    test('A2-T18b — même JOUR, heures différentes : l\'archive RÉSOLUE est '
        'arbitrée normalement (R-1)', () async {
      final jour = _jour(21);
      final cle = _cleCourse(6, 1, jour);

      // Actif : NON résolu, daté à 00h00 (minuit — fiche sans dateStr).
      final actif = _prono(
        courseKey: cle,
        date: DateTime(jour.year, jour.month, jour.day),
        resolu: false,
      );
      // Archive : RÉSOLUE, même jour, datée à 14h15 (heure de départ réelle).
      final archive = _prono(
        courseKey: cle,
        date: DateTime(jour.year, jour.month, jour.day, 14, 15),
      );

      // Prérequis : même courseKey, même JOUR, mais instants DIFFÉRENTS.
      expect(archive.courseKey, actif.courseKey);
      expect(archive.datePronostic, isNot(actif.datePronostic),
          reason: 'prérequis : les deux INSTANTS diffèrent (00h00 vs 14h15)');
      expect(archive.datePronostic.year, actif.datePronostic.year);
      expect(archive.datePronostic.month, actif.datePronostic.month);
      expect(archive.datePronostic.day, actif.datePronostic.day,
          reason: 'prérequis : le JOUR CIVIL est identique');
      // Prérequis : c'est bien la règle 4 qui doit s'appliquer.
      expect(actif.resultatsReels, isFalse);
      expect(IaArchiveService.rangDe(archive), 2);

      await _amorcer(
        _construireStore(
          enMemoire: [actif],
          enArchive: [archive],
          premiumParDate: {
            _dk(jour): [
              _premiumJson(courseKey: cle, source: 'conseilJour'),
            ],
          },
        ),
        chargerArchive: true,
      );

      // 1. Le calendrier affiche la journée, alimentée par la version résolue.
      final d = _calendrier();
      expect(d.containsKey(21), isTrue,
          reason: 'R-1 : une différence d\'HEURE ne bloque plus l\'arbitrage — '
              'la journée redevient visible');
      expect(d[21]!.nbCourses, 1, reason: 'aucun doublon');
      expect(d[21]!.pronostics.single.courseKey, cle);
      expect(d[21]!.pronostics.single.resultatsReels, isTrue,
          reason: 'la version retenue est la version ARCHIVÉE résolue');
      expect(d[21]!.pronostics.single.datePronostic.hour, 14,
          reason: 'c\'est bien la fiche archivée (14h15) qui est retenue, '
              'et non la fiche active de minuit');
      expect(d[21]!.nbBons, 1, reason: 'la victoire archivée est comptée');
      expect(d[21]!.palier, PalierCalendrier.or);

      // 2. La série Premium retrouve la victoire (même arbitrage, 2e site A2).
      expect(_serie('conseilJour', jour), 1,
          reason: 'R-1 : la série Premium retrouve la victoire archivée');

      // 3. Non-régression : aucune réinjection, aucune complétion sur place.
      expect(IaMemoryService.instance.getPronostic(cle)?.resultatsReels, isFalse,
          reason: 'la mémoire active reste strictement inchangée');
      expect(IaMemoryService.instance.getPronostic(cle)?.datePronostic.hour, 0,
          reason: 'la fiche active conserve sa propre date (00h00)');
    });

    test('A2-T18c — même INSTANT exact : l\'arbitrage reste identique (R-1)',
        () async {
      final jour = _jour(22);
      final cle = _cleCourse(6, 2, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour, resolu: false)],
          enArchive: [_prono(courseKey: cle, date: jour)],
        ),
        chargerArchive: true,
      );

      final d = _calendrier();
      expect(d.containsKey(22), isTrue,
          reason: 'cas nominal inchangé : règle 4, archive résolue retenue');
      expect(d[22]!.nbCourses, 1);
      expect(d[22]!.pronostics.single.resultatsReels, isTrue);
      expect(d[22]!.nbBons, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  GROUPE F — PRÉSERVATION DU COMPORTEMENT HISTORIQUE (NON-RÉGRESSION)
  // ═══════════════════════════════════════════════════════════════════════

  group('A2-F — non-régression des cas déjà couverts', () {
    test('A2-T19 — course uniquement en archive : inchangé', () async {
      final jour = _jour(24);
      final cle = _cleCourse(8, 1, jour);

      await _amorcer(
        _construireStore(
          enMemoire: const <IaPronostic>[],
          enArchive: [_prono(courseKey: cle, date: jour)],
        ),
        chargerArchive: true,
      );

      final d = _calendrier();
      expect(d[24]!.nbCourses, 1);
      expect(d[24]!.nbBons, 1);
      expect(d[24]!.pronostics.single.courseKey, cle);
    });

    test('A2-T20 — jour mémoire et jour archive : coexistent, sans mélange',
        () async {
      final jM = _jour(25);
      final jA = _jour(26);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: _cleCourse(9, 1, jM), date: jM)],
          enArchive: [_prono(courseKey: _cleCourse(9, 2, jA), date: jA)],
        ),
        chargerArchive: true,
      );

      final d = _calendrier();
      expect(d.keys.toSet(), <int>{25, 26});
      expect(d[25]!.pronostics.single.courseKey, _cleCourse(9, 1, jM));
      expect(d[26]!.pronostics.single.courseKey, _cleCourse(9, 2, jA));
    });

    test('A2-T21 — type de pari invalide : toujours filtré après arbitrage',
        () async {
      final jour = _jour(27);
      final cle = _cleCourse(9, 3, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour, resolu: false)],
          enArchive: [
            _prono(courseKey: cle, date: jour, typePari: 'À surveiller'),
          ],
        ),
        chargerArchive: true,
      );

      expect(_calendrier().containsKey(27), isFalse,
          reason: 'le filtre d\'éligibilité s\'applique APRÈS l\'arbitrage');
    });

    test('A2-T22 — série Premium avec archive non chargée : 0 (inchangé)',
        () async {
      final cle = _cleCourse(9, 4, j(1));

      await _amorcer(
        _construireStore(
          enMemoire: const <IaPronostic>[],
          enArchive: [_prono(courseKey: cle, date: j(1))],
          premiumParDate: {
            _dk(j(1)): [_premiumJson(courseKey: cle)],
          },
        ),
        chargerArchive: false,
      );

      expect(IaArchiveService.instance.archiveDisponible, isFalse);
      expect(_serie('conseilJour', j(1)), 0,
          reason: 'sans archive chargée, aucune victoire ne peut être lue');
    });

    test('A2-T23 — aucune étoile inventée par l\'arbitrage', () async {
      final jour = _jour(28);
      final cle = _cleCourse(9, 5, jour);

      await _amorcer(
        _construireStore(
          enMemoire: [_prono(courseKey: cle, date: jour, resolu: false)],
          enArchive: [_prono(courseKey: cle, date: jour)],
          // Aucun premium enregistré ce jour-là.
        ),
        chargerArchive: true,
      );

      final d = _calendrier();
      expect(d.containsKey(28), isTrue, reason: 'la journée est bien visible');
      expect(d[28]!.hasBestBet, isFalse,
          reason: 'sans historique premium, aucune étoile — A2 ne crée '
              'aucune donnée premium');
    });
  });
}
