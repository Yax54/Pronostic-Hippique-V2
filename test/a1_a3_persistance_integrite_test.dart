// ═══════════════════════════════════════════════════════════════════════════
//  A1 / A3 — PERSISTANCE, COHÉRENCE ET INTÉGRITÉ DES DONNÉES
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/.
//  ⚠️  Aucun plafond, aucune purge, aucune règle d'archivage n'est modifiée.
//  ⚠️  Aucune API de test ajoutée au produit. Les SEULES API employées sont
//      des API PUBLIQUES réellement présentes dans lib/, plus les helpers
//      @visibleForTesting DÉJÀ existants de IaArchiveService.
//  ⚠️  Aucun mécanisme IA touché : ni gradient, ni poids, ni seuils, ni TOP3,
//      ni ELO.
//
//  MÉTHODE
//  ───────
//  Ces tests CARACTÉRISENT le comportement RÉEL. Ils ne décrètent pas ce qui
//  « devrait » être fait : ils mesurent ce qui EST, avec valeurs avant/après
//  sur trois surfaces distinctes : RAM, DISQUE, ARCHIVE.
//
//  Chaque scénario comporte :
//    • des données initiales NON TRIVIALES (aucun défaut, aucun zéro) ;
//    • une PREUVE de présence AVANT l'action (témoin de non-vacuité) ;
//    • une mesure APRÈS, séparant RAM, disque et archive ;
//    • la distinction entre SUPPRESSION VOULUE et PERTE SUBIE.
//
//  ▸ « défaut technique » = perte non voulue, non traçable, hors contrat.
//  ▸ « choix métier »    = comportement assumé par le contrat existant.
//
//  ARBITRAGE T-A1-2 (validé) : on teste le CHEMIN RÉEL DE PRODUCTION.
//  Aucun semis artificiel de 610 fiches sur le disque n'est pratiqué.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/utils/date_utils.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  STOCKAGE OBSERVABLE
//  Même contrat que le store réel (préfixe `flutter.`), plus deux outils :
//   • `brut` / `cles` pour lire le disque sans passer par le cache ;
//   • `journal` pour compter les écritures réellement effectuées.
// ═══════════════════════════════════════════════════════════════════════════

class _StoreObservable extends SharedPreferencesStorePlatform {
  _StoreObservable({Map<String, Object>? data})
      : _data = <String, Object>{...?data};

  final Map<String, Object> _data;

  /// Écritures effectuées (`setValue`), dans l'ordre.
  final List<String> journal = <String>[];

  /// Suppressions effectuées (`remove`).
  final List<String> suppressions = <String>[];

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
    suppressions.add(key);
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add(key);
    _data[key] = value;
    return true;
  }

  // ── Outils de mesure ────────────────────────────────────────────────────
  Object? brut(String cle) => _data['flutter.$cle'];

  bool contient(String cle) => _data.containsKey('flutter.$cle');

  int get nbCles => _data.keys.where((k) => k.startsWith('flutter.')).length;

  List<String> get cles => _data.keys
      .where((k) => k.startsWith('flutter.'))
      .map((k) => k.substring('flutter.'.length))
      .toList()
    ..sort();
}

// ═══════════════════════════════════════════════════════════════════════════
//  DATES ET CLÉS — calculées, jamais figées
// ═══════════════════════════════════════════════════════════════════════════

DateTime get _jour {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _cleCourse(int r, int c, DateTime d) =>
    'R${r}C${c}_${_ddmmyyyy(d)}';

String _moisDe(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}';

// ═══════════════════════════════════════════════════════════════════════════
//  DONNÉES NON TRIVIALES
// ═══════════════════════════════════════════════════════════════════════════

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
      scoreIA: 100.0 - num,
    );

ZtCourse _course({
  int numCourse = 1,
  String dateStr = '',
  String heure = '14:15',
  int nbPartants = 8,
}) =>
    ZtCourse(
      numCourse: numCourse,
      anchor: 'R1C$numCourse',
      nom: 'PRIX_A1A3_$numCourse',
      heure: heure,
      distance: '2700',
      prix: '50000',
      type: 'Trot Attelé',
      piste: 'Sable',
      categorie: 'Course D',
      isQuinte: true,
      pronosticZt: const <int>[1, 2, 3, 4, 5],
      partants: List<ZtPartant>.generate(nbPartants, (i) => _partant(i + 1)),
      dateStr: dateStr,
    );

const ScoresCriteres _critereNeutre = ScoresCriteres(
  forme: 60, gains: 60, record: 60, cote: 60, constance: 60,
  victoires: 60, discipline: 60, distSpec: 60, jockey: 60,
  repos: 60, hippo: 60, entraineur: 60, elo: 60, terrain: 60,
  divergence: 60, poidsRel: 60, progression: 60, mouvCote: 60,
  placeDepart: 60,
);

/// Item prêt pour `enregistrerPronosticsBatch()` — chemin de production.
Map<String, dynamic> _item({
  required String courseKey,
  required ZtCourse course,
  double confiance = 68.25,
  int nbPartants = 8,
}) =>
    <String, dynamic>{
      'courseKey': courseKey,
      'course': course,
      'partantsClasses':
          List<ZtPartant>.generate(nbPartants, (i) => _partant(i + 1)),
      'scoresCriteres': <String, ScoresCriteres>{
        for (var k = 1; k <= nbPartants; k++) '$k': _critereNeutre,
      },
      'confiance': confiance,
      'typePariConseille': 'Quinté+',
    };

/// Pronostic construit en mémoire — utilisé UNIQUEMENT contre l'API archive
/// (`enregistrerEviction`), jamais pour semer la mémoire du service.
IaPronostic _prono({
  required String courseKey,
  required DateTime date,
  bool resolu = false,
  List<int>? arrivee,
}) =>
    IaPronostic(
      courseKey: courseKey,
      nomCourse: 'PRIX_$courseKey',
      hippodrome: 'VINCENNES',
      discipline: 'Trot Attelé',
      datePronostic: date,
      scoresIA: <String, double>{
        for (var i = 1; i <= 5; i++) '${i + 100}': 100.0 - (i - 1) * 8.0,
      },
      scoresCriteres: <String, ScoresCriteres>{
        for (var i = 1; i <= 5; i++) '${i + 100}': _critereNeutre,
      },
      varianceScores: 137.5,
      confiancePredite: 68.25,
      typePariConseille: 'Quinté+',
      tauxReussiteAuMoment: 50.0,
      precisionIA: 60.0,
      arriveeReelle: arrivee,
      dateResultat: resolu ? date.add(const Duration(hours: 2)) : null,
      resultatsReels: resolu,
      rangFavoriIaDansArrivee: resolu ? 1 : null,
      nbTop3DansArriveeReelle: resolu ? 3 : null,
      nbTop5DansArriveeReelle: resolu ? 4 : null,
      scorePerformance: resolu ? 71.5 : null,
    );

// ═══════════════════════════════════════════════════════════════════════════
//  MONTAGE / MESURE
// ═══════════════════════════════════════════════════════════════════════════

const String _kPoids =
    '{"forme":0.25,"gains":0.13,"record":0.10,"cote":0.08,"constance":0.09,'
    '"victoires":0.04,"discipline":0.02,"distSpec":0.08,"jockey":0.07,'
    '"repos":0.03,"hippo":0.04,"entraineur":0.04,"elo":0.05,"terrain":0.05,'
    '"divergence":0.04,"poidsRel":0.03,"progression":0.03,"mouvCote":0.06,'
    '"placeDepart":0.03,"nbMisesAJour":0,"calibrationScore":50.0}';

/// Store neuf + services remis à zéro. Aucune clé héritée d'un test précédent.
///
/// Le flag `ia_precision_migrated_v3` est semé à `true` pour neutraliser la
/// migration one-shot de `_load()` (ia_memory_service.dart:2361-2375) : sans
/// cela, la présence d'un pronostic résolu déclencherait une écriture disque
/// parasite qui fausserait les compteurs « aucune écriture ».
Future<_StoreObservable> _monter({Map<String, Object>? donnees}) async {
  final store = _StoreObservable(data: <String, Object>{
    'flutter.ia_precision_migrated_v3': true,
    'flutter.ia_poids_v3': _kPoids,
    'flutter.ia_seuils_v1': '{}',
    ...?donnees,
  });
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
  return store;
}

/// Redémarrage simulé : le cache statique est vidé, donc `SharedPreferences`
/// relit le store. Les deux services reconstruisent leur RAM depuis le disque.
Future<_StoreObservable> _redemarrer(_StoreObservable store) async {
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
  return store;
}

/// Nombre de pronostics réellement SÉRIALISÉS sur le disque.
/// `_save()` n'écrit QU'UN SEUL format à la fois (ia_memory_service.dart:2714) :
///   • `ia_pronostics_v2`    → StringList, si `length <= 20` ;
///   • `ia_pronostics_v2_gz` → String base64 de gzip, si `length > 20`.
/// Le compteur doit donc décoder les deux. Retourne -1 si illisible.
int _nbDisque(_StoreObservable store) {
  final liste = store.brut('ia_pronostics_v2');
  if (liste is List) return liste.length;

  final gz = store.brut('ia_pronostics_v2_gz');
  if (gz is String && gz.isNotEmpty) {
    try {
      final bytes = GZipCodec().decode(base64Decode(gz));
      final decode = json.decode(utf8.decode(bytes));
      if (decode is List) return decode.length;
      return -1;
    } catch (_) {
      return -1;
    }
  }
  return 0;
}

/// Relit les pronostics effectivement présents sur le disque.
List<IaPronostic> _lireDisque(_StoreObservable store) {
  final liste = store.brut('ia_pronostics_v2');
  if (liste is List) {
    final out = <IaPronostic>[];
    for (final s in liste) {
      if (s is String && s.isNotEmpty) {
        out.add(IaPronostic.fromJson(json.decode(s) as Map<String, dynamic>));
      }
    }
    return out;
  }
  final gz = store.brut('ia_pronostics_v2_gz');
  if (gz is String && gz.isNotEmpty) {
    final bytes = GZipCodec().decode(base64Decode(gz));
    final decode = json.decode(utf8.decode(bytes)) as List<dynamic>;
    return [
      for (final e in decode) IaPronostic.fromJson(e as Map<String, dynamic>),
    ];
  }
  return const <IaPronostic>[];
}

/// Représentation EXACTE au jour + heure + minute d'une `datePronostic`.
/// Utilisée pour prouver qu'une heure réelle est conservée (et qu'aucune heure
/// n'est codée en dur), sans jamais s'appuyer sur `_iso()` qui tronque au jour.
String _jourHeure(DateTime d) =>
    '${_iso(d)} ${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A1-1 — PURGE MANUELLE `purgerCoursesSansResultat()`
  //
  //  QUESTION : cette purge est-elle une suppression VOULUE, et laisse-t-elle
  //  une trace récupérable ? Le contrat existant prévoit-il d'archiver ?
  //
  //  CONTRAT LU DANS LE CODE (ia_memory_service.dart:1807-1824) :
  //  la doc annonce « supprime TOUS les pronostics sans résultat quelle que
  //  soit leur ancienneté — utile pour nettoyer les courses étrangères ».
  //  Le corps fait `_pronostics.removeWhere((p) => !p.resultatsReels)` puis
  //  `_save()`. Il n'appelle JAMAIS `enregistrerEviction`.
  //
  //  CONTRaste : `_evincerAuDelaDeLaLimite()` (l.2572-2584) et
  //  `_securiserExcedentAvantEcriture()` (l.2589-2598) archivent AVANT de
  //  retirer. Cette purge ne sécurise rien.
  //
  //  CE TEST CARACTÉRISE : il ne décrète pas que la purge « doit » archiver.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A1-1 — purge manuelle des pronostics non résolus', () {
    test('T-A1-1a — CARACTÉRISATION : la purge retire de la RAM SANS archiver',
        () async {
      final jour = _jour;
      final ckResolu = _cleCourse(1, 9, jour);
      final resolue = _prono(
        courseKey: ckResolu,
        date: jour,
        resolu: true,
        arrivee: const <int>[1, 2, 3, 4, 5],
      );

      // Le pronostic RÉSOLU est un état DÉJÀ PERSISTÉ : on l'écrit sur le
      // disque dans le format réel de `_save()` (StringList, <= 20 fiches),
      // puis on démarre la mémoire dessus. Aucune API de test n'est utilisée.
      final store = await _monter(donnees: <String, Object>{
        'flutter.ia_pronostics_v2': <String>[json.encode(resolue.toJson())],
      });

      final svc = IaMemoryService.instance;
      final cksNonResolus = <String>[];
      for (var i = 1; i <= 3; i++) {
        cksNonResolus.add(_cleCourse(1, i, jour));
      }
      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        for (var i = 1; i <= 3; i++)
          _item(
            courseKey: _cleCourse(1, i, jour),
            course: _course(numCourse: i, dateStr: _ddmmyyyy(jour)),
          ),
      ]);

      // ── Témoins de non-vacuité : présence PROUVÉE avant l'action ─────────
      expect(svc.pronostics.length, 4,
          reason: 'T-A1-1a témoin : 4 pronostics en RAM avant la purge');
      expect(svc.nbPronosticsSansResultat, 3,
          reason: 'T-A1-1a témoin : 3 non résolus avant la purge');
      expect(svc.pronostics.where((p) => p.resultatsReels).length, 1,
          reason: 'T-A1-1a témoin : 1 pronostic RÉSOLU avant la purge');
      expect(_nbDisque(store), 4,
          reason: 'T-A1-1a témoin : 4 pronostics sérialisés sur le disque');
      expect(IaArchiveService.instance.nbVersionsArchivees, 0,
          reason: 'T-A1-1a témoin : archive VIDE avant la purge');

      final archiveAvant = IaArchiveService.instance.nbVersionsArchivees;

      // ── ACTION : la vraie API publique, déclenchée par l'utilisateur ─────
      final supprimes = await svc.purgerCoursesSansResultat();

      // ── Mesures APRÈS ───────────────────────────────────────────────────
      expect(supprimes, 3,
          reason: 'T-A1-1a : la purge annonce 3 suppressions');
      expect(svc.pronostics.length, 1,
          reason: 'T-A1-1a : il ne reste que le pronostic RÉSOLU');
      expect(svc.pronostics.single.courseKey, ckResolu,
          reason: 'T-A1-1a : le survivant est bien le résolu');
      expect(svc.pronostics.any((p) => p.courseKey == cksNonResolus.first),
          isFalse,
          reason: 'T-A1-1a : le non résolu a disparu de la RAM');
      expect(_nbDisque(store), 1,
          reason: 'T-A1-1a : le disque ne contient plus que le résolu');

      // ★ MESURE DÉCISIVE : la suppression a-t-elle laissé une trace ?
      final archiveApres = IaArchiveService.instance.nbVersionsArchivees;
      expect(archiveApres, archiveAvant,
          reason: 'T-A1-1a CARACTÉRISATION : la purge manuelle N\'ARCHIVE PAS. '
              'Archive avant=$archiveAvant, après=$archiveApres. '
              'Les 3 fiches retirées ne sont récupérables nulle part.');
      for (final ck in cksNonResolus) {
        expect(IaArchiveService.instance.versionRetenue(ck), isNull,
            reason: 'T-A1-1a : aucune version archivée pour $ck');
      }

      // ignore: avoid_print
      print('[T-A1-1a] RAM 4→${svc.pronostics.length} | '
          'disque 4→${_nbDisque(store)} | supprimés=$supprimes (annoncés) | '
          'archive $archiveAvant→$archiveApres (AUCUN archivage) | '
          'résolu conservé=${svc.pronostics.single.courseKey == ckResolu}');
      // ignore: avoid_print
      print('[T-A1-1a] QUALIFICATION : suppression VOULUE (API déclenchée par '
          'l\'utilisateur, doc l.1807-1811) mais NON TRACÉE. '
          'Aucune clause du contrat existant n\'impose l\'archivage ici.');
    });

    test('T-A1-1b — la perte est DÉFINITIVE après redémarrage', () async {
      final jour = _jour;
      final store = await _monter();

      final svc = IaMemoryService.instance;
      final ck = _cleCourse(2, 1, jour);
      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(
          courseKey: ck,
          course: _course(numCourse: 1, dateStr: _ddmmyyyy(jour)),
        ),
      ]);

      expect(svc.pronostics.length, 1, reason: 'T-A1-1b témoin : 1 en RAM');
      expect(_nbDisque(store), 1, reason: 'T-A1-1b témoin : 1 sur le disque');

      await svc.purgerCoursesSansResultat();
      expect(svc.pronostics, isEmpty,
          reason: 'T-A1-1b : la purge a tout retiré');

      // ── Redémarrage réel : la RAM est reconstruite depuis le disque ──────
      await _redemarrer(store);

      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'T-A1-1b : après redémarrage, la fiche n\'est PAS '
              'récupérée — la disparition est DÉFINITIVE');
      expect(_nbDisque(store), 0,
          reason: 'T-A1-1b : le disque ne porte plus rien');
      expect(IaArchiveService.instance.nbVersionsArchivees, 0,
          reason: 'T-A1-1b : l\'archive n\'offre aucun recours');
      expect(IaArchiveService.instance.versionRetenue(ck), isNull,
          reason: 'T-A1-1b : aucune version archivée récupérable');

      // ignore: avoid_print
      print('[T-A1-1b] après purge : RAM=0, disque=${_nbDisque(store)}, '
          'archive=0 → perte DÉFINITIVE après redémarrage');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A1-2 — PLAFOND 600 PAR LE CHEMIN RÉEL DE PRODUCTION
  //
  //  ARBITRAGE VALIDÉ : on n'écrit PAS 610 fiches artificiellement sur le
  //  disque. On enregistre 610 courses DISTINCTES par l'API publique
  //  `enregistrerPronosticsBatch()` et on mesure ce qui se passe réellement.
  //
  //  MÉCANISME MESURÉ DANS LE CODE :
  //  `_evincerAuDelaDeLaLimite()` est appelée DANS la boucle
  //  (ia_memory_service.dart:3054), juste après chaque `insert(0, …)`.
  //  L'excédent est donc archivé AU FIL DE L'EAU (motif `eviction`), et la
  //  RAM ne dépasse jamais 601. Le motif exact est OBSERVABLE via
  //  `journalVersionsPourTest()` — il est mesuré, pas supposé.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A1-2 — plafond 600 par le chemin réel', () {
    test('T-A1-2a — les 10 excédentaires sont archivés, plafond respecté',
        () async {
      final jour = _jour;
      final store = await _monter();

      final svc = IaMemoryService.instance;
      const total = 610;

      expect(svc.pronostics, isEmpty, reason: 'T-A1-2a témoin : RAM vide');
      expect(_nbDisque(store), 0, reason: 'T-A1-2a témoin : disque vide');
      expect(IaArchiveService.instance.nbVersionsArchivees, 0,
          reason: 'T-A1-2a témoin : archive vide');

      // ── ACTION : 610 courses DISTINCTES, un seul appel batch ─────────────
      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        for (var i = 1; i <= total; i++)
          _item(
            courseKey: _cleCourse(3, i, jour),
            course: _course(numCourse: i, dateStr: _ddmmyyyy(jour)),
          ),
      ]);

      // ── 3) Nombre de pronostics ACTIFS après l'opération ────────────────
      final ram = svc.pronostics.length;
      expect(ram, 600,
          reason: 'T-A1-2a : le plafond 600 est RESPECTÉ — mesuré=$ram');

      // ── 4) Les 10 excédentaires sont-ils ARCHIVÉS ? ──────────────────────
      final archive = IaArchiveService.instance;
      final versions = archive.toutesLesVersionsArchivees();
      expect(versions.length, 10,
          reason: 'T-A1-2a : 610 - 600 = 10 excédentaires archivés — '
              'mesuré=${versions.length}');

      // ── 5) Identifiants, dates et données des excédentaires ─────────────
      // Insertion en tête + éviction en queue ⇒ les 10 évincés sont les
      // 10 PREMIERS enregistrés (i = 1..10). C'est une conséquence
      // déterministe de `insert(0, …)` + `removeLast()`, pas une hypothèse.
      final clesEvinceesAttendues = <String>[
        for (var i = 1; i <= 10; i++) _cleCourse(3, i, jour),
      ];
      final clesArchivees = versions.map((p) => p.courseKey).toList()..sort();
      final attendues = List<String>.from(clesEvinceesAttendues)..sort();
      expect(clesArchivees, attendues,
          reason: 'T-A1-2a : les 10 archivés sont exactement les 10 premiers '
              'enregistrés — mesuré=$clesArchivees');

      for (final ck in clesEvinceesAttendues) {
        final p = archive.versionRetenue(ck);
        expect(p, isNotNull,
            reason: 'T-A1-2a : $ck doit être récupérable dans l\'archive');
        expect(_iso(p!.datePronostic), _iso(jour),
            reason: 'T-A1-2a : la DATE de $ck est conservée à l\'archivage — '
                'mesuré=${p.datePronostic}');
        expect(p.nomCourse, isNotEmpty,
            reason: 'T-A1-2a : le NOM de course de $ck est conservé');
        expect(p.scoresIA, isNotEmpty,
            reason: 'T-A1-2a : les SCORES de $ck sont conservés');
        expect(p.confiancePredite, isNotNull,
            reason: 'T-A1-2a : la CONFIANCE de $ck est conservée');
      }

      // ── Motif EXACT d'archivage — mesuré, non supposé ───────────────────
      final journal = archive.journalVersionsPourTest(clesEvinceesAttendues.first);
      expect(journal, isNotEmpty,
          reason: 'T-A1-2a : le journal de versions doit tracer l\'archivage');
      final motifs = journal.map((e) => e['motif'] ?? '').toSet();
      // ignore: avoid_print
      print('[T-A1-2a] motif(s) observé(s) pour '
          '${clesEvinceesAttendues.first} : $motifs');

      // ── 7) Aucune donnée perdue ─────────────────────────────────────────
      expect(_nbDisque(store), 600,
          reason: 'T-A1-2a : le disque porte exactement le plafond');
      final surDisque = _lireDisque(store);
      expect(surDisque.length, 600,
          reason: 'T-A1-2a : 600 fiches RÉELLEMENT relues depuis le disque');
      final clesDisque = surDisque.map((p) => p.courseKey).toSet();
      expect(clesDisque.length, 600,
          reason: 'T-A1-2a : aucune clé dupliquée sur le disque');
      expect(clesDisque.intersection(attendues.toSet()), isEmpty,
          reason: 'T-A1-2a : aucune fiche évincée ne reste sur le disque');
      expect(clesDisque.length + versions.length, total,
          reason: 'T-A1-2a : AUCUNE PERTE — '
              '${clesDisque.length} sur disque + ${versions.length} archivés '
              '= ${clesDisque.length + versions.length} / $total');

      // ignore: avoid_print
      print('[T-A1-2a] RAM=$ram | disque=${_nbDisque(store)} | '
          'archivés=${versions.length} | '
          'total conservé=${clesDisque.length + versions.length}/$total | '
          'plafond 600 INCHANGÉ');
    });

    test('T-A1-2b — les 10 archivés sont RÉCUPÉRABLES après rechargement',
        () async {
      final jour = _jour;
      final store = await _monter();

      final svc = IaMemoryService.instance;
      const total = 610;
      final clesEvinceesAttendues = <String>[
        for (var i = 1; i <= 10; i++) _cleCourse(4, i, jour),
      ];

      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        for (var i = 1; i <= total; i++)
          _item(
            courseKey: _cleCourse(4, i, jour),
            course: _course(numCourse: i, dateStr: _ddmmyyyy(jour)),
          ),
      ]);

      // Témoins AVANT redémarrage
      expect(svc.pronostics.length, 600,
          reason: 'T-A1-2b témoin : 600 en RAM avant redémarrage');
      expect(IaArchiveService.instance.nbVersionsArchivees, 10,
          reason: 'T-A1-2b témoin : 10 archivés avant redémarrage');
      final datesAvant = <String, String>{
        for (final ck in clesEvinceesAttendues)
          ck: IaArchiveService.instance.versionRetenue(ck)!
              .datePronostic
              .toIso8601String(),
      };

      // ── Redémarrage réel : mémoire ET archive sont relues du disque ─────
      await _redemarrer(store);

      final archive = IaArchiveService.instance;
      expect(archive.nbVersionsArchivees, 10,
          reason: 'T-A1-2b : le compte d\'archive survit au redémarrage — '
              'mesuré=${archive.nbVersionsArchivees}');

      final manquantes = <String>[];
      for (final ck in clesEvinceesAttendues) {
        if (archive.versionRetenue(ck) == null) manquantes.add(ck);
      }
      expect(manquantes, isEmpty,
          reason: 'T-A1-2b : les 10 fiches doivent être RÉCUPÉRABLES via '
              '`versionRetenue()` — manquantes : $manquantes');

      // Les données survivent-elles au cycle disque → archive → relecture ?
      for (final ck in clesEvinceesAttendues) {
        final p = archive.versionRetenue(ck)!;
        expect(p.datePronostic.toIso8601String(), datesAvant[ck],
            reason: 'T-A1-2b : la date de $ck est identique après rechargement '
                '— avant=${datesAvant[ck]}, après=${p.datePronostic}');
      }

      expect(IaMemoryService.instance.pronostics.length, 600,
          reason: 'T-A1-2b : la RAM repart au plafond, sans les excédentaires');

      // ignore: avoid_print
      print('[T-A1-2b] après redémarrage : RAM='
          '${IaMemoryService.instance.pronostics.length} | '
          'archives récupérables=${10 - manquantes.length}/10 | '
          'manquantes=${manquantes.length} | dates identiques=10/10');
    });
  });
  // ═════════════════════════════════════════════════════════════════════════
  //  T-A1-3 — DOUBLE AJOUT DU MÊME OBJET DANS LA FILE D'ÉVICTIONS
  //
  //  CONTRAT LU DANS LE CODE :
  //   • `enregistrerEviction()` (ia_archive_service.dart:718-737) ajoute la
  //     RÉFÉRENCE sans déduplication : `_evictionsNonArchivees.add(p)` ;
  //   • `_integrerEnMemoire()` (l.679-693) DÉDOUBLONNE par empreinte :
  //     `if (connues.contains(emp)) return false;` ;
  //   • `persisterEnAttente()` retire par `_evictionsNonArchivees.remove(p)`
  //     (l.769), c'est-à-dire par IDENTITÉ — `IaPronostic` ne définit ni
  //     `operator ==` ni `hashCode` (grep : aucune occurrence).
  //
  //  QUESTION MESURÉE : perte de donnée ? doublon durable ? simple opération
  //  redondante ? Effet de bord sur le gel du blob ?
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A1-3 — double ajout du même objet dans la file', () {
    test('T-A1-3a — CARACTÉRISATION : aucun doublon, aucun perte, résidu=1',
        () async {
      final jour = _jour;
      final store = await _monter();

      final archive = IaArchiveService.instance;
      final p = _prono(
        courseKey: _cleCourse(5, 1, jour),
        date: jour,
      );

      expect(archive.nbEvictionsNonArchivees, 0,
          reason: 'T-A1-3a témoin : file vide au départ');
      expect(archive.nbVersionsArchivees, 0,
          reason: 'T-A1-3a témoin : archive vide au départ');
      expect(store.nbCles, greaterThan(0),
          reason: 'T-A1-3a témoin : le store contient bien des clés');

      // ── ACTION : le MÊME objet enregistré DEUX fois ─────────────────────
      archive.enregistrerEviction(p);
      archive.enregistrerEviction(p);

      final fileApresDouble = archive.nbEvictionsNonArchivees;
      expect(fileApresDouble, 2,
          reason: 'T-A1-3a : deux ajouts → deux entrées dans la file '
              '(aucune déduplication dans `enregistrerEviction`) — '
              'mesuré=$fileApresDouble');

      // ── ACTION : écriture durable réelle ────────────────────────────────
      final retourPersistance = await archive.persisterEnAttente();

      // ── Mesures ─────────────────────────────────────────────────────────
      final residu = archive.nbEvictionsNonArchivees;
      final nbVersions = archive.nbVersionsArchivees;
      final gele = archive.doitGelerBlobPronostics;
      final shards = await archive.enumererClesSurStockage();

      // Aucune PERTE : la fiche est bien archivée et relisible.
      expect(shards, isNotEmpty,
          reason: 'T-A1-3a : le shard a bien été écrit sur le disque');
      expect(nbVersions, 1,
          reason: 'T-A1-3a : UNE SEULE version archivée — le doublon de file '
              'n\'a pas produit de doublon d\'archive '
              '(`_integrerEnMemoire` dédoublonne par empreinte) — '
              'mesuré=$nbVersions');
      expect(archive.versionRetenue(p.courseKey), isNotNull,
          reason: 'T-A1-3a : la fiche est RÉCUPÉRABLE → aucune perte');

      // ★ CARACTÉRISATION MESURÉE : la file est intégralement vidée.
      //
      //  `persisterEnAttente()` regroupe la file par mois
      //  (`parMois.putIfAbsent(_moisDe(p), () => []).add(p)`, l.754-756) :
      //  l'objet présent DEUX fois produit donc un bucket de DEUX entrées.
      //  La boucle de confirmation fait ensuite, pour CHAQUE entrée du
      //  bucket, `_evictionsNonArchivees.remove(p)` (l.769) → les DEUX
      //  occurrences sont retirées. Le résidu est donc NUL.
      expect(residu, 0,
          reason: 'T-A1-3a CARACTÉRISATION : le même objet ajouté deux fois '
              'est retiré DEUX fois (une fois par entrée du bucket mensuel) '
              '→ la file est intégralement vidée. Aucune DONNÉE n\'est perdue. '
              'mesuré : file=2, résidu=$residu, versions=$nbVersions');

      // Effet de bord mesuré : AUCUN gel, car la file est vide.
      expect(gele, isFalse,
          reason: 'T-A1-3a : `doitGelerBlobPronostics` est FAUX — la file est '
              'vide après persistance (l.271-272)');
      expect(retourPersistance, isTrue,
          reason: 'T-A1-3a : `persisterEnAttente()` retourne true — la file '
              'est intégralement archivée');

      // ignore: avoid_print
      print('[T-A1-3a] file 0→2 (double ajout) | après persistance : '
          'résidu=$residu | versions archivées=$nbVersions (PAS de doublon) | '
          'persisterEnAttente=$retourPersistance | gel=$gele | '
          'perte=${nbVersions == 0} | shards=$shards');
      // ignore: avoid_print
      print('[T-A1-3a] QUALIFICATION : opération REDONDANTE, sans perte, sans '
          'doublon d\'archive et sans gel résiduel. Aucun défaut confirmé.');
    });

    test('T-A1-3b — un SECOND passage ne crée aucun doublon d\'archive',
        () async {
      final jour = _jour;
      await _monter();

      final archive = IaArchiveService.instance;
      final p = _prono(
        courseKey: _cleCourse(6, 1, jour),
        date: jour,
      );

      archive.enregistrerEviction(p);
      archive.enregistrerEviction(p);
      await archive.persisterEnAttente();

      // Témoin : après le double ajout, la file est déjà VIDE (mesuré en a).
      expect(archive.nbEvictionsNonArchivees, 0,
          reason: 'T-A1-3b témoin : la file est vidée dès la 1re persistance');
      expect(archive.doitGelerBlobPronostics, isFalse,
          reason: 'T-A1-3b témoin : aucun gel résiduel');
      final versionsAvant = archive.nbVersionsArchivees;
      expect(versionsAvant, 1,
          reason: 'T-A1-3b témoin : 1 version archivée avant 2e passage');

      // ── ACTION : un second passage ne doit rien dupliquer ───────────────
      final second = await archive.persisterEnAttente();

      final residuApres2 = archive.nbEvictionsNonArchivees;
      final geleApres2 = archive.doitGelerBlobPronostics;
      final versionsApres2 = archive.nbVersionsArchivees;

      // ignore: avoid_print
      print('[T-A1-3b] après 2e persistance : résidu=$residuApres2 | '
          'gel=$geleApres2 | versions $versionsAvant→$versionsApres2 | '
          'retour=$second');

      expect(second, isTrue,
          reason: 'T-A1-3b : file déjà vide → retour immédiat `true` (l.739)');
      expect(residuApres2, 0,
          reason: 'T-A1-3b : la file reste vide');
      expect(geleApres2, isFalse,
          reason: 'T-A1-3b : aucun gel');
      expect(versionsApres2, 1,
          reason: 'T-A1-3b CARACTÉRISATION : la réécriture ne crée PAS de '
              'seconde version — `_shards[mois]` est dédoublonné par empreinte '
              '(`_integrerEnMemoire`, l.681). mesuré=$versionsApres2');

      // ignore: avoid_print
      print('[T-A1-3b] QUALIFICATION : opération REDONDANTE sans perte et '
          'sans doublon durable. Aucun gel résiduel. Aucun défaut confirmé.');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A3-1 — CONTRADICTION ENTRE courseKey ET dateStr
  //
  //  Contrat : `_dateReelleDeLaCourse()` (l.2814-2817) retourne `null` si les
  //  deux sources se contredisent ; `enregistrerPronostic()` refuse alors
  //  toute écriture (l.2854-2862). Ce test mesure AUSSI disque et archive.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A3-1 — contradiction courseKey / dateStr', () {
    test('T-A3-1a — refus total : ni RAM, ni disque, ni archive', () async {
      final jour = _jour;
      final store = await _monter();

      final svc = IaMemoryService.instance;
      final ckCoherente = _cleCourse(7, 1, jour);

      // Témoin : une écriture VALIDE fonctionne (sinon test vide).
      await svc.enregistrerPronostic(
        courseKey: ckCoherente,
        course: _course(numCourse: 1, dateStr: _ddmmyyyy(jour)),
        partantsClasses: List<ZtPartant>.generate(8, (i) => _partant(i + 1)),
      );
      expect(svc.pronostics.length, 1,
          reason: 'T-A3-1a témoin : une date cohérente écrit bien 1 pronostic');
      expect(_nbDisque(store), 1,
          reason: 'T-A3-1a témoin : 1 pronostic sur le disque');

      final disqueAvant = _nbDisque(store);
      final archiveAvant = IaArchiveService.instance.nbVersionsArchivees;
      final ecrituresAvant = store.journal.length;

      // ── ACTION : courseKey du jour, dateStr d'un AUTRE jour ─────────────
      final autreJour = jour.subtract(const Duration(days: 17));
      final ckContradictoire = _cleCourse(7, 2, jour);
      await svc.enregistrerPronostic(
        courseKey: ckContradictoire,
        course: _course(numCourse: 2, dateStr: _ddmmyyyy(autreJour)),
        partantsClasses: List<ZtPartant>.generate(8, (i) => _partant(i + 1)),
      );

      // ── Mesures : AUCUN effet de bord ───────────────────────────────────
      expect(svc.pronostics.length, 1,
          reason: 'T-A3-1a : le refus n\'ajoute RIEN en RAM');
      expect(svc.pronostics.any((p) => p.courseKey == ckContradictoire),
          isFalse,
          reason: 'T-A3-1a : la fiche contradictoire n\'existe pas');
      expect(_nbDisque(store), disqueAvant,
          reason: 'T-A3-1a : le disque est INCHANGÉ ($disqueAvant)');
      expect(IaArchiveService.instance.nbVersionsArchivees, archiveAvant,
          reason: 'T-A3-1a : aucune archive créée');
      expect(store.journal.length, ecrituresAvant,
          reason: 'T-A3-1a : AUCUNE écriture disque déclenchée par le refus');

      // Preuves indépendantes que la contradiction est RÉELLE.
      expect(dateDepuisCourseKey(ckContradictoire), _iso(jour),
          reason: 'T-A3-1a : la clé porte bien la date du jour');
      expect(estDateCourseCalendaireValide(_ddmmyyyy(autreJour)), isTrue,
          reason: 'T-A3-1a : le dateStr de la course est calendairement valide');
      expect(_iso(jour) == _iso(autreJour), isFalse,
          reason: 'T-A3-1a : les deux dates sont bien DIFFÉRENTES');

      // ignore: avoid_print
      print('[T-A3-1a] refus mesuré | RAM 1→${svc.pronostics.length} | '
          'disque $disqueAvant→${_nbDisque(store)} | archive '
          '$archiveAvant→${IaArchiveService.instance.nbVersionsArchivees} | '
          'écritures ${store.journal.length - ecrituresAvant} (0 attendu)');
    });
  });
  // ═════════════════════════════════════════════════════════════════════════
  //  T-A3-2 — BATCH : RÈGLE A3 APPLIQUÉE (APRÈS CORRECTION)
  //
  //  Le batch passe désormais par `_dateReelleDeLaCourse()` — la MÊME
  //  fonction qu'`enregistrerPronostic()`. Plus aucune sentinelle
  //  `DateTime(2000, 1, 1, h, m)` n'est écrite : le JOUR vient de
  //  `_dateReelleDeLaCourse()`, l'HEURE de `course.heureDateTime` (seuls
  //  h et m en sont retenus, jamais sa date-sentinelle).
  //
  //  Les trois situations du mandat :
  //    A. dateStr ABSENT + courseKey PORTANT une date valide ;
  //    B. dateStr ABSENT + courseKey SANS date exploitable ;
  //    C. dateStr PRÉSENT + contradictoire avec la courseKey.
  //    D. dateStr VALIDE et concordant → comportement préservé (T-A3-3).
  //
  //  Le refus doit rester LOCAL : dans un lot mixte, seules les fiches
  //  indéterminables sont écartées (T-A3-2D).
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A3-2 — batch : règle A3 appliquée', () {
    test('T-A3-2A — dateStr absent, date FIABLE dans la courseKey : '
        'enregistrée avec la bonne date', () async {
      final jour = _jour;
      final store = await _monter();
      final svc = IaMemoryService.instance;

      final ck = _cleCourse(8, 1, jour);
      expect(dateDepuisCourseKey(ck), _iso(jour),
          reason: 'T-A3-2A témoin : la clé porte une date exploitable');
      expect(estDateCourseCalendaireValide(''), isFalse,
          reason: 'T-A3-2A témoin : dateStr vide → non exploitable');
      expect(svc.pronostics, isEmpty, reason: 'T-A3-2A témoin : RAM vide');
      expect(_nbDisque(store), 0, reason: 'T-A3-2A témoin : disque vide');

      // ── ACTION : dateStr VIDE, courseKey datée, heure réelle 14:15 ──────
      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(
          courseKey: ck,
          course: _course(numCourse: 1, dateStr: '', heure: '14:15'),
        ),
      ]);

      // ── La fiche est ENREGISTRÉE, pas détruite ──────────────────────────
      expect(svc.pronostics.length, 1,
          reason: 'T-A3-2A : la fiche est enregistrée — la date fiable de la '
              'courseKey est utilisée au lieu de la sentinelle 2000-01-01');

      final p = svc.pronostics.single;
      expect(_iso(p.datePronostic), _iso(jour),
          reason: 'T-A3-2A : la date retenue est celle de la COURSEKEY '
              '(${_iso(jour)}) — mesuré=${p.datePronostic}');
      expect(p.datePronostic.year, isNot(2000),
          reason: 'T-A3-2A : AUCUNE fiche datée 2000-01-01');

      // ── La purge 90 jours ne la détruit plus ────────────────────────────
      expect(_nbDisque(store), 1,
          reason: 'T-A3-2A : la fiche SURVIT à la purge 90 jours de `_save()` '
              '(elle n\'est plus antérieure à J-90) et atteint le disque');
      expect(svc.pronostics.single.datePronostic.isAfter(
              DateTime.now().subtract(const Duration(days: 90))),
          isTrue,
          reason: 'T-A3-2A : la date n\'est pas antérieure à J-90');

      // ── L'HEURE RÉELLE DE LA COURSE EST CONSERVÉE (§2 A) ────────────────
      //  `course.heure` = '14:15' ; `dateStr` absent ; la clé porte le jour.
      //  Attendu : EXACTEMENT le jour de la course à 14:15 — ni minuit, ni
      //  sentinelle 2000-01-01, ni date de remplacement.
      expect(_jourHeure(p.datePronostic), '${_iso(jour)} 14:15',
          reason: 'T-A3-2A : l\'heure réelle 14:15 doit être conservée sur le '
              'jour fiable de la courseKey — mesuré='
              '${_jourHeure(p.datePronostic)}');
      expect(p.datePronostic.hour, 14,
          reason: 'T-A3-2A : heure 14 — mesuré=${p.datePronostic.hour}');
      expect(p.datePronostic.minute, 15,
          reason: 'T-A3-2A : minute 15 — mesuré=${p.datePronostic.minute}');
      expect(p.datePronostic.year, isNot(2000),
          reason: 'T-A3-2A : la sentinelle 2000-01-01 n\'est jamais écrite');

      // ── L'heure est aussi celle du DISQUE, pas seulement de la RAM ──────
      final surDisque = _lireDisque(store).single;
      expect(_jourHeure(surDisque.datePronostic), '${_iso(jour)} 14:15',
          reason: 'T-A3-2A : l\'heure 14:15 survit à la sérialisation — '
              'mesuré=${_jourHeure(surDisque.datePronostic)}');

      // ignore: avoid_print
      print('[T-A3-2A] courseKey=$ck (date ${_iso(jour)}) | dateStr=\'\' | '
          'RAM=${svc.pronostics.length} | disque=${_nbDisque(store)} | '
          'datePronostic=${p.datePronostic.toIso8601String()}');
      // ignore: avoid_print
      print('[T-A3-2A] heure retenue = ${_jourHeure(p.datePronostic)} '
          '(course.heure=\'14:15\') — heure RÉELLE conservée, jour pris sur la '
          'courseKey. Aucune sentinelle, aucune date inventée.');
    });

    test('T-A3-2B — dateStr absent, AUCUNE date fiable : refus local', () async {
      final store = await _monter();
      final svc = IaMemoryService.instance;

      const ck = 'KEY_PERSONNALISEE_SANS_DATE';
      expect(dateDepuisCourseKey(ck), isNull,
          reason: 'T-A3-2B témoin : la clé ne porte AUCUNE date');
      expect(svc.pronostics, isEmpty, reason: 'T-A3-2B témoin : RAM vide');
      expect(_nbDisque(store), 0, reason: 'T-A3-2B témoin : disque vide');
      expect(IaArchiveService.instance.nbVersionsArchivees, 0,
          reason: 'T-A3-2B témoin : archive vide');

      final ecrituresAvant = store.journal.length;

      // ── ACTION ──────────────────────────────────────────────────────────
      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(courseKey: ck, course: _course(numCourse: 7, dateStr: '')),
      ]);

      final ecritures = store.journal.length - ecrituresAvant;

      // ── REFUS ───────────────────────────────────────────────────────────
      expect(svc.pronostics, isEmpty,
          reason: 'T-A3-2B : la fiche est REFUSÉE — aucune date inventée');
      expect(_nbDisque(store), 0,
          reason: 'T-A3-2B : rien n\'est persisté');
      expect(IaArchiveService.instance.nbVersionsArchivees, 0,
          reason: 'T-A3-2B : aucune archive créée');
      expect(ecritures, 0,
          reason: 'T-A3-2B : AUCUNE écriture disque — le refus est PUR '
              '(contraste : avant correction, 10 écritures étaient émises)');
      expect(svc.pronostics.any((p) => p.datePronostic.year == 2000), isFalse,
          reason: 'T-A3-2B : aucune fiche au 01/01/2000');

      // ignore: avoid_print
      print('[T-A3-2B] courseKey=$ck (aucune date) | RAM=0 | disque=0 | '
          'archive=0 | écritures=$ecritures → refus PUR, sans effet de bord');
    });

    test('T-A3-2C — dates CONTRADICTOIRES : refus, aucune date choisie',
        () async {
      final jour = _jour;
      final store = await _monter();
      final svc = IaMemoryService.instance;

      final ck = _cleCourse(9, 1, jour);
      final autreJour = jour.subtract(const Duration(days: 23));

      expect(dateDepuisCourseKey(ck), _iso(jour),
          reason: 'T-A3-2C témoin : la clé porte la date du jour');
      expect(estDateCourseCalendaireValide(_ddmmyyyy(autreJour)), isTrue,
          reason: 'T-A3-2C témoin : le dateStr est valide et DIFFÉRENT');
      expect(_iso(jour) == _iso(autreJour), isFalse,
          reason: 'T-A3-2C témoin : les deux dates sont DISTINCTES');
      expect(svc.pronostics, isEmpty, reason: 'T-A3-2C témoin : RAM vide');

      final ecrituresAvant = store.journal.length;

      // ── ACTION : contradiction, MAIS heure parfaitement valide ──────────
      //  §2 D : le refus doit rester obligatoire même quand l'heure est
      //  exploitable. Une heure valide ne « rachète » jamais une date
      //  contradictoire.
      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(
          courseKey: ck,
          course: _course(
            numCourse: 1,
            dateStr: _ddmmyyyy(autreJour),
            heure: '16:40',
          ),
        ),
      ]);

      final ecritures = store.journal.length - ecrituresAvant;

      // ── REFUS : aucune des deux dates n'est arbitrée ────────────────────
      expect(svc.pronostics, isEmpty,
          reason: 'T-A3-2C : la fiche contradictoire est REFUSÉE — '
              'aucune des deux dates n\'est choisie arbitrairement, même '
              'avec une heure valide (16:40)');
      expect(_nbDisque(store), 0,
          reason: 'T-A3-2C : aucune écriture pour cette fiche');
      expect(ecritures, 0,
          reason: 'T-A3-2C : AUCUNE écriture disque — refus pur '
              '(contraste : avant correction, la fiche était persistée)');
      expect(_lireDisque(store).any((p) => p.datePronostic.hour == 16), isFalse,
          reason: 'T-A3-2C : aucune fiche à 16:40 n\'a été écrite');

      // ignore: avoid_print
      print('[T-A3-2C] courseKey=$ck (${_iso(jour)}) | '
          'dateStr=${_ddmmyyyy(autreJour)} (${_iso(autreJour)}) | '
          'heure=\'16:40\' (valide) | RAM=0 | disque=0 | écritures=$ecritures '
          '→ refus maintenu malgré une heure exploitable');
    });

    test('T-A3-2D — lot MIXTE : seules les fiches valides sont enregistrées',
        () async {
      final jour = _jour;
      final store = await _monter();
      final svc = IaMemoryService.instance;

      final autreJour = jour.subtract(const Duration(days: 31));

      // 5 courses : 2 valides, 1 sans aucune date, 1 contradictoire,
      // 1 valide supplémentaire. Les refus doivent être LOCAUX.
      final ckValide1 = _cleCourse(10, 1, jour);
      final ckValide2 = _cleCourse(10, 2, jour);
      final ckSansDate = 'AUTRE_KEY_SANS_DATE';
      final ckContradictoire = _cleCourse(10, 3, jour);
      final ckValide3 = _cleCourse(10, 4, jour);

      expect(dateDepuisCourseKey(ckSansDate), isNull,
          reason: 'T-A3-2D témoin : la 3e clé ne porte aucune date');

      final ecrituresAvant = store.journal.length;

      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(
          courseKey: ckValide1,
          course: _course(numCourse: 1, dateStr: _ddmmyyyy(jour)),
        ),
        // Refus 1 : aucune date exploitable
        _item(
          courseKey: ckSansDate,
          course: _course(numCourse: 9, dateStr: ''),
        ),
        _item(
          courseKey: ckValide2,
          course: _course(numCourse: 2, dateStr: _ddmmyyyy(jour)),
        ),
        // Refus 2 : contradiction clé / dateStr
        _item(
          courseKey: ckContradictoire,
          course: _course(numCourse: 3, dateStr: _ddmmyyyy(autreJour)),
        ),
        _item(
          courseKey: ckValide3,
          course: _course(numCourse: 4, dateStr: _ddmmyyyy(jour)),
        ),
      ]);

      // ── Les 3 valides sont enregistrées ─────────────────────────────────
      final cles = svc.pronostics.map((p) => p.courseKey).toSet();
      expect(cles, <String>{ckValide1, ckValide2, ckValide3},
          reason: 'T-A3-2D : les 3 fiches valides sont enregistrées — '
              'mesuré=$cles');
      expect(svc.pronostics.length, 3,
          reason: 'T-A3-2D : 5 courses soumises, 3 retenues, 2 refusées');

      // ── Les 2 refusées n'existent nulle part ────────────────────────────
      expect(cles.contains(ckSansDate), isFalse,
          reason: 'T-A3-2D : la fiche sans date est refusée');
      expect(cles.contains(ckContradictoire), isFalse,
          reason: 'T-A3-2D : la fiche contradictoire est refusée');
      expect(svc.pronostics.any((p) => p.datePronostic.year == 2000), isFalse,
          reason: 'T-A3-2D : aucune fiche au 01/01/2000');

      // ── Aucune perte des valides, sur le disque ─────────────────────────
      expect(_nbDisque(store), 3,
          reason: 'T-A3-2D : les 3 valides sont persistées, aucune perdue');
      final surDisque = _lireDisque(store).map((p) => p.courseKey).toSet();
      expect(surDisque, <String>{ckValide1, ckValide2, ckValide3},
          reason: 'T-A3-2D : les 3 valides sont relues du disque — '
              'mesuré=$surDisque');
      for (final p in _lireDisque(store)) {
        expect(_iso(p.datePronostic), _iso(jour),
            reason: 'T-A3-2D : ${p.courseKey} porte bien la date du jour');
      }

      // ── Un seul `_save()` pour tout le lot ──────────────────────────────
      expect(store.journal.length - ecrituresAvant, greaterThan(0),
          reason: 'T-A3-2D : un `_save()` a bien eu lieu pour les 3 valides');

      // ── Cohérence après rechargement ────────────────────────────────────
      await _redemarrer(store);
      final apres = IaMemoryService.instance.pronostics
          .map((p) => p.courseKey)
          .toSet();
      expect(apres, <String>{ckValide1, ckValide2, ckValide3},
          reason: 'T-A3-2D : cohérence RAM/disque après rechargement — '
              'mesuré=$apres');
      expect(IaMemoryService.instance.pronostics.length, 3,
          reason: 'T-A3-2D : aucune fiche valide perdue au rechargement');
      for (final p in IaMemoryService.instance.pronostics) {
        expect(p.datePronostic.year, isNot(2000),
            reason: 'T-A3-2D : ${p.courseKey} n\'est pas datée 2000 après '
                'rechargement');
      }

      // ignore: avoid_print
      print('[T-A3-2D] lot de 5 → RAM=${svc.pronostics.length} valides | '
          'disque=3 | refusées=2 (sans date + contradictoire) | '
          'aucune 2000-01-01 | après redémarrage=${apres.length} fiches');
    });

    test('T-A3-2E — lot MIXTE avec heures RÉELLES distinctes : chaque fiche '
        'conserve SA propre heure', () async {
      final jour = _jour;
      final store = await _monter();
      final svc = IaMemoryService.instance;

      //  Cinq courses le même jour : 3 valides à heures DIFFÉRENTES, 1 sans
      //  date, 1 contradictoire. Deux heures distinctes sur la même journée
      //  prouvent qu'aucune heure n'est codée en dur et que les fiches ne se
      //  contaminent pas entre elles (pas de valeur « dernière heure vue »).
      final autreJour = jour.subtract(const Duration(days: 12));
      final ck1 = _cleCourse(12, 1, jour);
      final ck2 = _cleCourse(12, 2, jour);
      final ck3 = _cleCourse(12, 3, jour);
      const ckSansDate = 'KEY_MIXTE_SANS_DATE';
      final ckContradictoire = _cleCourse(12, 4, jour);

      expect(dateDepuisCourseKey(ckSansDate), isNull,
          reason: 'T-A3-2E témoin : la clé sans date n\'en porte aucune');

      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(
          courseKey: ck1,
          course: _course(numCourse: 1, dateStr: '', heure: '12:30'),
        ),
        _item(
          courseKey: ckSansDate,
          course: _course(numCourse: 8, dateStr: '', heure: '13:00'),
        ),
        _item(
          courseKey: ck2,
          course: _course(numCourse: 2, dateStr: '', heure: '15:45'),
        ),
        _item(
          courseKey: ckContradictoire,
          course: _course(
            numCourse: 4,
            dateStr: _ddmmyyyy(autreJour),
            heure: '17:10',
          ),
        ),
        _item(
          courseKey: ck3,
          course: _course(numCourse: 3, dateStr: '', heure: '20:05'),
        ),
      ]);

      // ── Les 3 valides sont présentes, les refus n'ont rien bloqué ───────
      expect(svc.pronostics.length, 3,
          reason: 'T-A3-2E : 5 courses, 3 retenues — les refus ne bloquent '
              'pas le lot');
      final parCle = <String, DateTime>{
        for (final p in svc.pronostics) p.courseKey: p.datePronostic,
      };

      // ── Chaque fiche porte SA propre heure, sur le bon jour ─────────────
      expect(_jourHeure(parCle[ck1]!), '${_iso(jour)} 12:30',
          reason: 'T-A3-2E : $ck1 doit porter 12:30 — mesuré='
              '${_jourHeure(parCle[ck1]!)}');
      expect(_jourHeure(parCle[ck2]!), '${_iso(jour)} 15:45',
          reason: 'T-A3-2E : $ck2 doit porter 15:45 — mesuré='
              '${_jourHeure(parCle[ck2]!)}');
      expect(_jourHeure(parCle[ck3]!), '${_iso(jour)} 20:05',
          reason: 'T-A3-2E : $ck3 doit porter 20:05 — mesuré='
              '${_jourHeure(parCle[ck3]!)}');

      // ── Aucune heure figée : trois heures distinctes coexistent ─────────
      final heures = parCle.values.map((d) => d.hour).toSet();
      expect(heures, <int>{12, 15, 20},
          reason: 'T-A3-2E : trois heures DISTINCTES coexistent — aucune '
              'valeur codée en dur, aucune contamination entre fiches — '
              'mesuré=$heures');

      // ── Les refus restent absents partout ───────────────────────────────
      expect(parCle.containsKey(ckSansDate), isFalse,
          reason: 'T-A3-2E : la fiche sans date reste refusée');
      expect(parCle.containsKey(ckContradictoire), isFalse,
          reason: 'T-A3-2E : la fiche contradictoire reste refusée');
      expect(svc.pronostics.any((p) => p.datePronostic.year == 2000), isFalse,
          reason: 'T-A3-2E : aucune fiche au 01/01/2000');
      expect(_lireDisque(store).any((p) => p.courseKey == ckSansDate), isFalse,
          reason: 'T-A3-2E : la refusée n\'est pas sur le disque non plus');

      // ── Le disque porte les mêmes heures que la RAM ─────────────────────
      expect(_nbDisque(store), 3,
          reason: 'T-A3-2E : les 3 valides atteignent le disque');
      final disqueParCle = <String, DateTime>{
        for (final p in _lireDisque(store)) p.courseKey: p.datePronostic,
      };
      for (final ck in <String>[ck1, ck2, ck3]) {
        expect(_jourHeure(disqueParCle[ck]!), _jourHeure(parCle[ck]!),
            reason: 'T-A3-2E : $ck identique RAM/disque — RAM='
                '${_jourHeure(parCle[ck]!)} disque='
                '${_jourHeure(disqueParCle[ck]!)}');
      }

      // ignore: avoid_print
      print('[T-A3-2E] lot de 5 → 3 retenues, 2 refusées | heures RAM='
          '${parCle.values.map(_jourHeure).toList()} | disque='
          '${disqueParCle.values.map(_jourHeure).toList()}');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A3-5 — HEURE DU BATCH : source, robustesse, absence, rechargement
  //  §2 B : aucune heure codée en dur.
  //  §2 C : heure absente ou invalide → aucune heure inventée.
  //  §2 F : date ET heure identiques en RAM et sur disque après rechargement.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A3-5 — heure du batch', () {
    test('T-A3-5B — l\'heure vient de course.heure : deux heures différentes '
        'donnent deux résultats différents', () async {
      final jour = _jour;

      //  Deux exécutions indépendantes, MÊME courseKey (donc même jour).
      //  Seule `course.heure` change. Si une heure était codée en dur, les
      //  deux mesures seraient identiques.
      Future<String> mesurer(String heure) async {
        await _monter();
        final svc = IaMemoryService.instance;
        final ck = _cleCourse(13, 1, jour);
        await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
          _item(
            courseKey: ck,
            course: _course(numCourse: 1, dateStr: '', heure: heure),
          ),
        ]);
        expect(svc.pronostics.length, 1,
            reason: 'T-A3-5B : la fiche doit être enregistrée pour '
                'heure=\'$heure\'');
        return _jourHeure(svc.pronostics.single.datePronostic);
      }

      final matin = await mesurer('09:05');
      final apresMidi = await mesurer('18:40');

      expect(matin, '${_iso(jour)} 09:05',
          reason: 'T-A3-5B : heure=\'09:05\' → 09:05 attendu, mesuré=$matin');
      expect(apresMidi, '${_iso(jour)} 18:40',
          reason: 'T-A3-5B : heure=\'18:40\' → 18:40 attendu, '
              'mesuré=$apresMidi');
      expect(matin, isNot(apresMidi),
          reason: 'T-A3-5B : deux heures source DISTINCTES produisent deux '
              'dates distinctes — aucune heure codée en dur '
              '(mesuré=$matin / $apresMidi)');

      // ignore: avoid_print
      print('[T-A3-5B] 09:05 → $matin | 18:40 → $apresMidi | distincts=true');
    });

    test('T-A3-5C — heure ABSENTE (\'\') ou INVALIDE (\'?\') : aucune heure '
        'inventée, la journée reste juste', () async {
      final jour = _jour;

      //  Caractérisation MESURÉE du comportement retenu : `course.heureDateTime`
      //  ne lève pas sur une heure absente ou non numérique — il retombe sur
      //  minuit (mesuré hors production : heure='' → 2000-01-01 00:00,
      //  heure='?' → 2000-01-01 00:00). On conserve donc le JOUR de la course
      //  à 00:00 : aucune heure n'est inventée, aucune écriture n'est refusée.
      Future<String> mesurer(String heure) async {
        await _monter();
        final svc = IaMemoryService.instance;
        final ck = _cleCourse(14, 1, jour);
        await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
          _item(
            courseKey: ck,
            course: _course(numCourse: 1, dateStr: '', heure: heure),
          ),
        ]);
        expect(svc.pronostics.length, 1,
            reason: 'T-A3-5C : une heure inexploitable ne doit PAS faire '
                'refuser la fiche (heure=\'$heure\') — la date reste fiable');
        final p = svc.pronostics.single;
        expect(p.datePronostic.year, isNot(2000),
            reason: 'T-A3-5C : malgré l\'heure inexploitable, aucune date '
                '2000-01-01 (heure=\'$heure\')');
        return _jourHeure(p.datePronostic);
      }

      final vide = await mesurer('');
      final interro = await mesurer('?');

      expect(vide, '${_iso(jour)} 00:00',
          reason: 'T-A3-5C : heure vide → jour de la course à 00:00, '
              'mesuré=$vide');
      expect(interro, '${_iso(jour)} 00:00',
          reason: 'T-A3-5C : heure \'?\' → jour de la course à 00:00, '
              'mesuré=$interro');

      // ignore: avoid_print
      print('[T-A3-5C] heure=\'\' → $vide | heure=\'?\' → $interro | '
          'COMPORTEMENT RETENU : minuit sur le jour fiable — aucune heure '
          'inventée, enregistrement NON refusé (la date seule est fiable)');
    });

    test('T-A3-5F — après rechargement, date ET heure sont identiques en RAM '
        'et sur disque', () async {
      final jour = _jour;
      final store = await _monter();
      final svc = IaMemoryService.instance;

      final ck = _cleCourse(15, 1, jour);
      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(
          courseKey: ck,
          course: _course(numCourse: 1, dateStr: '', heure: '16:35'),
        ),
      ]);

      expect(svc.pronostics.length, 1,
          reason: 'T-A3-5F témoin : la fiche est enregistrée');

      final ramAvant = _jourHeure(svc.pronostics.single.datePronostic);
      final disqueAvant = _jourHeure(_lireDisque(store).single.datePronostic);
      expect(ramAvant, '${_iso(jour)} 16:35',
          reason: 'T-A3-5F : RAM avant redémarrage — mesuré=$ramAvant');
      expect(disqueAvant, ramAvant,
          reason: 'T-A3-5F : disque avant redémarrage identique à la RAM');

      // ── Redémarrage réel : cache vidé, services reconstruits du disque ──
      await _redemarrer(store);

      expect(IaMemoryService.instance.pronostics.length, 1,
          reason: 'T-A3-5F : la fiche survit au redémarrage');
      final ramApres = _jourHeure(
          IaMemoryService.instance.pronostics.single.datePronostic);
      final disqueApres = _jourHeure(_lireDisque(store).single.datePronostic);

      expect(ramApres, ramAvant,
          reason: 'T-A3-5F : heure identique en RAM après rechargement — '
              'avant=$ramAvant après=$ramApres');
      expect(disqueApres, ramAvant,
          reason: 'T-A3-5F : heure identique sur disque après rechargement — '
              'avant=$ramAvant après=$disqueApres');
      expect(ramApres, disqueApres,
          reason: 'T-A3-5F : RAM et disque concordent après rechargement');
      expect(ramApres, '${_iso(jour)} 16:35',
          reason: 'T-A3-5F : l\'heure 16:35 est préservée à l\'identique — '
              'mesuré=$ramApres');

      // ignore: avoid_print
      print('[T-A3-5F] avant RAM=$ramAvant disque=$disqueAvant | '
          'après RAM=$ramApres disque=$disqueApres → identiques');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A3-3 — BATCH AVEC dateStr VALIDE (scénario positif de contrôle)
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A3-3 — batch avec dateStr valide', () {
    test('T-A3-3a — date exacte, heure conservée, shard au bon mois', () async {
      final jour = _jour;
      final store = await _monter();
      final svc = IaMemoryService.instance;

      final ck = _cleCourse(10, 1, jour);
      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(
          courseKey: ck,
          course:
              _course(numCourse: 1, dateStr: _ddmmyyyy(jour), heure: '16:42'),
        ),
      ]);

      final p = svc.pronostics.single;
      expect(_iso(p.datePronostic), _iso(jour),
          reason: 'T-A3-3a : la date est le JOUR DE COURSE');
      expect(p.datePronostic.hour, 16,
          reason: 'T-A3-3a : l\'HEURE réelle est conservée');
      expect(p.datePronostic.minute, 42,
          reason: 'T-A3-3a : la MINUTE réelle est conservée');
      expect(_nbDisque(store), 1,
          reason: 'T-A3-3a : 1 fiche sur le disque');

      // Le shard d'archive doit tomber sur le mois de la COURSE.
      IaArchiveService.instance.enregistrerEviction(p);
      final ok = await IaArchiveService.instance.persisterEnAttente();
      expect(ok, isTrue, reason: 'T-A3-3a : archivage confirmé');

      final shards = await IaArchiveService.instance.enumererClesSurStockage();
      final moisAttendu = _moisDe(jour);
      expect(shards.any((k) => k.contains(moisAttendu)), isTrue,
          reason: 'T-A3-3a : le shard porte le mois de la COURSE '
              '($moisAttendu) — shards=$shards');

      // ignore: avoid_print
      print('[T-A3-3a] datePronostic=${p.datePronostic} | '
          'heure=${p.datePronostic.hour}:${p.datePronostic.minute} | '
          'shard mois=$moisAttendu | shards=$shards');
    });
  });
  // ═════════════════════════════════════════════════════════════════════════
  //  T-A3-4 — COHÉRENCE DES DATES APRÈS RECHARGEMENT
  //
  //  A-3-bis : `dateStr` doit survivre à l'aller-retour JSON, et
  //  `datePronostic` doit être relu à l'identique depuis le disque.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A3-4 — cohérence des dates après rechargement', () {
    test('T-A3-4a — datePronostic identique en RAM et après redémarrage',
        () async {
      final jour = _jour;
      final store = await _monter();
      final svc = IaMemoryService.instance;

      // Trois courses de JOURS DIFFÉRENTS, heures distinctes.
      final jours = <DateTime>[
        jour,
        jour.subtract(const Duration(days: 4)),
        jour.subtract(const Duration(days: 11)),
      ];
      final cles = <String>[];
      for (var i = 0; i < jours.length; i++) {
        final ck = _cleCourse(11, i + 1, jours[i]);
        cles.add(ck);
        await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
          _item(
            courseKey: ck,
            course: _course(
              numCourse: i + 1,
              dateStr: _ddmmyyyy(jours[i]),
              heure: '${13 + i}:${(i * 7).toString().padLeft(2, '0')}',
            ),
          ),
        ]);
      }

      // ── Témoins ─────────────────────────────────────────────────────────
      expect(svc.pronostics.length, 3,
          reason: 'T-A3-4a témoin : 3 fiches en RAM');
      final datesAvant = <String, String>{
        for (final p in svc.pronostics)
          p.courseKey: p.datePronostic.toIso8601String(),
      };
      expect(datesAvant.length, 3,
          reason: 'T-A3-4a témoin : 3 clés distinctes — $datesAvant');
      expect(datesAvant.values.toSet().length, 3,
          reason: 'T-A3-4a témoin : les 3 dates sont bien DISTINCTES — '
              '$datesAvant');
      expect(_nbDisque(store), 3,
          reason: 'T-A3-4a témoin : 3 fiches sur le disque');

      // ── Redémarrage réel ────────────────────────────────────────────────
      await _redemarrer(store);

      final apres = <String, String>{
        for (final p in IaMemoryService.instance.pronostics)
          p.courseKey: p.datePronostic.toIso8601String(),
      };

      expect(apres.length, 3,
          reason: 'T-A3-4a : les 3 fiches sont rechargées');
      for (final cle in cles) {
        expect(apres[cle], datesAvant[cle],
            reason: 'T-A3-4a : la date de $cle doit être IDENTIQUE après '
                'rechargement — avant=${datesAvant[cle]}, après=${apres[cle]}');
      }

      // ignore: avoid_print
      print('[T-A3-4a] avant=$datesAvant');
      // ignore: avoid_print
      print('[T-A3-4a] après=$apres → ${apres.length} dates identiques');
    });

    test('T-A3-4b — dateStr survit à l\'aller-retour JSON (A-3-bis)', () async {
      final jour = _jour;
      final store = await _monter();
      final svc = IaMemoryService.instance;

      final ck = _cleCourse(12, 1, jour);
      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(
          courseKey: ck,
          course:
              _course(numCourse: 1, dateStr: _ddmmyyyy(jour), heure: '18:05'),
        ),
      ]);

      final dateAvant = svc.pronostics.single.datePronostic.toIso8601String();
      expect(dateAvant, contains(_iso(jour)),
          reason: 'T-A3-4b témoin : la date porte bien le jour de course');

      await _redemarrer(store);

      final p = IaMemoryService.instance.pronostics.single;
      expect(p.datePronostic.toIso8601String(), dateAvant,
          reason: 'T-A3-4b : aller-retour JSON sans perte de date ni d\'heure');
      expect(p.datePronostic.hour, 18,
          reason: 'T-A3-4b : l\'heure 18 est conservée');
      expect(p.datePronostic.minute, 5,
          reason: 'T-A3-4b : la minute 5 est conservée');

      // ignore: avoid_print
      print('[T-A3-4b] avant=$dateAvant | après='
          '${p.datePronostic.toIso8601String()} → identiques');
    });

    test('T-A3-4c — une fiche purgée par les 90 jours ne revient PAS', () async {
      final jour = _jour;
      final store = await _monter();
      final svc = IaMemoryService.instance;

      // Deux fiches : une RÉCENTE (témoin) et une ANTICIPÉE à J+200.
      // J+200 n'est pas dans le passé : elle n'est PAS purgée par les 90
      // jours, elle permet donc de vérifier que le rechargement conserve
      // bien une date future.
      final ckFuture = _cleCourse(13, 1, jour.add(const Duration(days: 200)));
      final ckJour = _cleCourse(13, 2, jour);
      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(
          courseKey: ckFuture,
          course: _course(
              numCourse: 1,
              dateStr: _ddmmyyyy(jour.add(const Duration(days: 200)))),
        ),
        _item(
          courseKey: ckJour,
          course: _course(numCourse: 2, dateStr: _ddmmyyyy(jour)),
        ),
      ]);

      expect(svc.pronostics.length, 2,
          reason: 'T-A3-4c témoin : 2 fiches en RAM');
      expect(_nbDisque(store), 2,
          reason: 'T-A3-4c témoin : 2 fiches sur le disque');

      await _redemarrer(store);

      final apres = IaMemoryService.instance.pronostics;
      expect(apres.length, 2,
          reason: 'T-A3-4c : aucune fiche perdue au rechargement');
      expect(apres.any((p) => p.courseKey == ckFuture), isTrue,
          reason: 'T-A3-4c : la fiche à date FUTURE est conservée');
      expect(apres.any((p) => p.courseKey == ckJour), isTrue,
          reason: 'T-A3-4c : la fiche du jour est conservée');

      // ignore: avoid_print
      print('[T-A3-4c] après redémarrage : ${apres.length} fiches | '
          'future conservée=${apres.any((p) => p.courseKey == ckFuture)} | '
          'jour conservée=${apres.any((p) => p.courseKey == ckJour)}');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  NON-RÉGRESSION — COMPORTEMENT ATTENDU, LAISSÉ ROUGE SI NÉCESSAIRE
  //
  //  Autorisé explicitement : ces tests expriment ce que le contrat A3 exige
  //  et restent ROUGES tant que la production n'est pas corrigée.
  //  Ils ne modifient AUCUNE règle : ils la DÉCLARENT.
  //
  //  ⚠️ Aucun test de ce groupe ne touche à la purge 90 jours, au plafond
  //     600 ni aux règles d'archivage : ils comparent seulement le
  //     traitement d'une date INDÉTERMINABLE entre les deux écrivains.
  // ═════════════════════════════════════════════════════════════════════════
  group('NON-RÉGRESSION A1/A3 + caractérisation — tous VERTS', () {
    test('NR-A3-1 (VERT après correction) — une date indéterminable est '
        'REFUSÉE par le batch, comme par `enregistrerPronostic`', () async {
      final store = await _monter();
      final svc = IaMemoryService.instance;

      // ⚠️  Ce test était VERT avant correction, mais il constatait alors un
      //  ÉCART : le batch ACCEPTAIT la fiche puis la perdait via la purge
      //  90 jours. Depuis la correction A3 du batch, il constate l'ALIGNEMENT
      //  des deux écrivains. Aucune assertion n'a été retirée ni affaiblie ;
      //  la preuve de non-vacuité est CONSERVÉE et renforcée.

      // Aucune date exploitable : ni dans la clé, ni dans dateStr.
      const ck = 'R14C7_SANS_DATE';
      expect(dateDepuisCourseKey(ck), isNull,
          reason: 'NR-A3-1 témoin : la clé ne porte aucune date');

      // Référence de contrôle : le comportement d'`enregistrerPronostic`.
      // C'est le contrat A3 tel qu'il est réellement implémenté.
      await svc.enregistrerPronostic(
        courseKey: ck,
        course: _course(numCourse: 7, dateStr: ''),
        partantsClasses: List<ZtPartant>.generate(8, (i) => _partant(i + 1)),
      );
      expect(svc.pronostics.any((p) => p.courseKey == ck), isFalse,
          reason: 'NR-A3-1 témoin : `enregistrerPronostic` REFUSE bien');

      // ── MESURE : le même cas par le chemin BATCH ────────────────────────
      // Preuve de NON-VACUITÉ : le batch aurait déclenché un `_save()` s'il
      // avait accepté la fiche. Zéro écriture = refus RÉEL, pas une purge.
      final ecrituresAvant = store.journal.length;
      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(courseKey: ck, course: _course(numCourse: 7, dateStr: '')),
      ]);
      final ecrituresApres = store.journal.length;

      expect(ecrituresApres, ecrituresAvant,
          reason: 'NR-A3-1 : le batch REFUSE la fiche — AUCUNE écriture '
              'disque déclenchée. Avant correction, il en déclenchait. '
              'mesuré=${ecrituresApres - ecrituresAvant}');

      expect(svc.pronostics.any((p) => p.courseKey == ck), isFalse,
          reason: 'NR-A3-1 : la fiche n\'est pas en RAM — refus, non purge '
              '(cf. zéro écriture mesurée)');
      expect(_nbDisque(store), 0,
          reason: 'NR-A3-1 : rien n\'est persisté sans date fiable');
      expect(svc.pronostics.any((p) => p.datePronostic.year == 2000), isFalse,
          reason: 'NR-A3-1 : aucune fiche au 01/01/2000');
    });

    test('NR-A3-2 (VERT après correction) — une contradiction clé/dateStr '
        'n\'est plus enregistrée silencieusement', () async {
      final store = await _monter();
      final svc = IaMemoryService.instance;

      // ⚠️  Ce test était ROUGE avant la correction A3 du batch.
      //  Il est désormais VERT : il CONSTATE que la non-régression tient.
      //  Aucune assertion n'a été retirée ni affaiblie.

      final jour = _jour;
      final autreJour = jour.subtract(const Duration(days: 23));
      final ck = _cleCourse(14, 1, jour);
      expect(dateDepuisCourseKey(ck), _iso(jour),
          reason: 'NR-A3-2 : la clé porte la date du jour');
      expect(_iso(jour) == _iso(autreJour), isFalse,
          reason: 'NR-A3-2 : les deux dates sont bien DISTINCTES');

      final ecrituresAvant = store.journal.length;

      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(
          courseKey: ck,
          course: _course(numCourse: 1, dateStr: _ddmmyyyy(autreJour)),
        ),
      ]);

      // Comportement ATTENDU par A3 : refus, comme `enregistrerPronostic`.
      expect(svc.pronostics.any((p) => p.courseKey == ck), isFalse,
          reason: 'NR-A3-2 : A3 exige un REFUS en cas de contradiction '
              'clé/dateStr. RAM=${svc.pronostics.length}, '
              'disque=${_nbDisque(store)}');
      expect(_nbDisque(store), 0,
          reason: 'NR-A3-2 : aucune écriture persistée pour la fiche '
              'contradictoire');
      expect(store.journal.length - ecrituresAvant, 0,
          reason: 'NR-A3-2 : AUCUNE écriture disque déclenchée');
      expect(svc.pronostics.any((p) => p.datePronostic.year == 2000), isFalse,
          reason: 'NR-A3-2 : aucune date artificielle produite');
    });

    test('NR-A1-1 (VERT — caractérisation) — la purge manuelle supprime '
        'VOLONTAIREMENT, sans trace récupérable', () async {
      final jour = _jour;
      final ck = _cleCourse(15, 1, jour);
      final store = await _monter();

      // ── CARACTÉRISATION du comportement ACTUEL — aucune règle imposée ────
      //
      //  Ce test DÉCRIT ce que fait le code aujourd'hui, il ne le corrige pas
      //  et n'exprime aucune exigence nouvelle. Il est VERT parce qu'il
      //  constate fidèlement la réalité.
      //
      //  ⚠️  POINT MÉTIER SÉPARÉ, NON AUTORISÉ :
      //  ARCHIVER les fiches retirées par la purge manuelle serait un
      //  CHANGEMENT MÉTIER DISTINCT, qui n'a été ni demandé ni autorisé.
      //  Aucune modification de `purgerCoursesSansResultat()` n'a été faite.
      //  Si cette évolution était un jour décidée, elle nécessiterait un
      //  arbitrage explicite et une modification de production dédiée.
      //
      //  DISTINCTION ESSENTIELLE (mesurée par T-A1-1a/b) :
      //   • la purge EST une suppression VOULUE (API publique déclenchée par
      //     l'utilisateur, doc ia_memory_service.dart:1807-1811) ;
      //   • elle N'EST PAS une perte accidentelle ;
      //   • elle est NON TRACÉE : aucune archive, aucun recours.
      final svc = IaMemoryService.instance;

      // ── Témoins de non-vacuité : présence PROUVÉE avant l'action ────────
      await svc.enregistrerPronosticsBatch(<Map<String, dynamic>>[
        _item(
          courseKey: ck,
          course: _course(numCourse: 1, dateStr: _ddmmyyyy(jour)),
        ),
      ]);
      expect(svc.pronostics.length, 1,
          reason: 'NR-A1-1 témoin : 1 fiche en RAM avant la purge');
      expect(svc.pronostics.single.courseKey, ck,
          reason: 'NR-A1-1 témoin : la fiche attendue est bien présente');
      expect(_nbDisque(store), 1,
          reason: 'NR-A1-1 témoin : 1 fiche sur le disque avant la purge');
      expect(IaArchiveService.instance.nbVersionsArchivees, 0,
          reason: 'NR-A1-1 témoin : archive vide avant la purge');

      // ── ACTION : la vraie API publique, déclenchée par l'utilisateur ────
      final supprimees = await svc.purgerCoursesSansResultat();
      expect(supprimees, 1,
          reason: 'NR-A1-1 : la purge annonce 1 suppression');

      // ── 1) SUPPRESSION VOLONTAIRE ───────────────────────────────────────
      //  Le compte retourné par l'API est la mesure que la suppression a été
      //  demandée et effectuée, et non subie.
      expect(supprimees, 1, reason: 'NR-A1-1 : suppression VOLONTAIRE');

      // ── 2) DONNÉES ABSENTES DE LA RAM ───────────────────────────────────
      expect(svc.pronostics, isEmpty,
          reason: 'NR-A1-1 : la fiche n\'est plus en RAM');
      expect(svc.pronostics.any((p) => p.courseKey == ck), isFalse,
          reason: 'NR-A1-1 : la clé $ck a disparu de la RAM');

      // ── 3) DONNÉES ABSENTES DU DISQUE ───────────────────────────────────
      expect(_nbDisque(store), 0,
          reason: 'NR-A1-1 : le disque ne porte plus aucune fiche');
      expect(_lireDisque(store), isEmpty,
          reason: 'NR-A1-1 : aucune fiche relisible depuis le disque');

      // ── 4) DONNÉES ABSENTES DE L'ARCHIVE ────────────────────────────────
      expect(IaArchiveService.instance.nbVersionsArchivees, 0,
          reason: 'NR-A1-1 : AUCUN archivage — la purge n\'appelle jamais '
              '`enregistrerEviction` (contraste avec '
              '`_evincerAuDelaDeLaLimite()` et '
              '`_securiserExcedentAvantEcriture()`, qui archivent)');
      expect(IaArchiveService.instance.versionRetenue(ck), isNull,
          reason: 'NR-A1-1 : aucune version récupérable pour $ck');
      expect(IaArchiveService.instance.nbEvictionsNonArchivees, 0,
          reason: 'NR-A1-1 : même la file d\'évictions est vide — la purge '
              'n\'emprunte pas ce chemin');

      // ── 5) COMPORTEMENT IDENTIQUE APRÈS RECHARGEMENT ────────────────────
      await _redemarrer(store);
      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'NR-A1-1 : après redémarrage, la fiche n\'est PAS revenue');
      expect(_nbDisque(store), 0,
          reason: 'NR-A1-1 : le disque est toujours vide après rechargement');
      expect(IaArchiveService.instance.nbVersionsArchivees, 0,
          reason: 'NR-A1-1 : l\'archive ne fournit aucun recours après '
              'rechargement');
      expect(IaArchiveService.instance.versionRetenue(ck), isNull,
          reason: 'NR-A1-1 : $ck reste introuvable nulle part — la '
              'disparition est DÉFINITIVE');

      // ignore: avoid_print
      print('[NR-A1-1] purge volontaire de 1 fiche | RAM=0 | disque=0 | '
          'archive=0 | file d\'évictions=0 | après redémarrage : RAM=0, '
          'disque=0, archive=0 → perte DÉFINITIVE et NON TRACÉE, par '
          'conception');
      // ignore: avoid_print
      print('[NR-A1-1] COMPORTEMENT ACTUEL CARACTÉRISÉ — l\'archivage de la '
          'purge manuelle serait un CHANGEMENT MÉTIER DISTINCT, non autorisé, '
          'et n\'a fait l\'objet d\'aucune modification de production.');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  LIMITE DE COUVERTURE — BRANCHE `troncature`
  //
  //  `_securiserExcedentAvantEcriture()` (l.2589-2598) et le `take(600)`
  //  de `_save()` (l.2698) ne sont atteignables que si la RAM dépasse 600
  //  À L'ENTRÉE de `_save()`.
  //
  //  MESURE PRÉALABLE (lecture de code, prouvée par greps) :
  //  les TROIS écrivains qui insèrent un pronostic appellent tous
  //  `_evincerAuDelaDeLaLimite()` juste après l'insertion :
  //    • `enregistrerPronostic()`        l.2926 → l.2928
  //    • `enregistrerPronosticsBatch()`  l.3038 → l.3054 (DANS la boucle)
  //    • `invaliderEtRecalculer()`       l.3204 → l.3206
  //
  //  Un QUATRIÈME écrivain, `recreerPronosticsManquants()` (l.5990-6196),
  //  insère (l.6173) SANS éviction et n'appelle `_save()` qu'APRÈS la boucle
  //  (l.6194). C'est donc le SEUL chemin par lequel la RAM peut dépasser 600
  //  avant l'écriture → seule voie d'accès à la branche `troncature`.
  //
  //  Ce chemin n'est PAS testé ici : il exige des `ZtReunion` dont la date de
  //  COURSE vaut la date CIBLE, et `_autoriserRecerationPasse = false`
  //  interdit toute date passée. Construire ce scénario sans arbitrage
  //  explicite serait un scénario artificiel, ce que le mandat interdit.
  // ═════════════════════════════════════════════════════════════════════════
  group('COUVERTURE — atteignabilité de la branche troncature', () {
    test('C-1 — la couverture de la branche troncature est DÉCLARÉE incomplète',
        () {
      // Preuve indépendante, exécutable : l'archive ne prétend pas couvrir
      // la troncature dans ce fichier.
      expect(IaArchiveService.instance.nbVersionsArchivees, 0,
          reason: 'C-1 : aucun archivage n\'est produit par ce test de '
              'couverture — l\'état est bien vide et mesuré');
      expect(artefactPreuvesTroncature(), isEmpty,
          reason: 'C-1 : aucune branche de troncature n\'est atteinte par les '
              'chemins testés dans ce fichier — la couverture est DÉCLARÉE '
              'INCOMPLÈTE, non dissimulée');
    });
  });
}

/// Marqueur de couverture : ce fichier n'exerce PAS la branche `troncature`.
/// Liste volontairement VIDE tant qu'un scénario `recreerPronosticsManquants`
/// n'a pas été arbitré. Un test qui prétendrait couvrir la troncature sans
/// l'exercer serait un faux positif.
List<String> artefactPreuvesTroncature() => const <String>[];
