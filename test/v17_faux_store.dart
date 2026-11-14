// ═══════════════════════════════════════════════════════════════════════════
//  V17 — HARNAIS PARTAGÉ (store en mémoire + constructeurs + constantes)
//
//  Fichier de TEST uniquement. Aucune dépendance vers lib/ modifiée.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io'; // GZipCodec

// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

// ─── Constantes de test ────────────────────────────────────────────────────

const String kPronosticsKey = 'ia_pronostics_v2_gz';
const String kPoidsKey = 'ia_poids_v3';
const String kSeuilsKey = 'ia_seuils_v1';

/// Mois de référence : passé stable → indépendant de l'horloge murale.
final DateTime moisRef = DateTime(2024, 3, 1);

DateTime jour(int j) => DateTime(moisRef.year, moisRef.month, j);

String cleCourse(int r, int c, DateTime d) =>
    'R${r}C${c}_${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}${d.year}';

// ─── Store en mémoire ──────────────────────────────────────────────────────

late FauxStore store;

class FauxStore extends SharedPreferencesStorePlatform {
  FauxStore({Map<String, Object>? data})
      : _data = <String, Object>{
          for (final e in (data ?? const <String, Object>{}).entries)
            (e.key.startsWith('flutter.') ? e.key : 'flutter.${e.key}'):
                e.value,
        };

  final Map<String, Object> _data;

  /// Panne simulée : toute lecture/écriture lève.
  bool panne = false;

  /// Nombre de lectures effectuées.
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

  /// Écriture directe, HORS service : sert à corrompre volontairement un shard.
  ///
  /// ⚠️ `SharedPreferences.getInstance()` met le contenu en CACHE STATIQUE :
  /// sans `resetStatic()`, la corruption resterait invisible au service, qui
  /// relirait l'ancienne photographie. On invalide donc le cache, exactement
  /// comme le ferait une modification du stockage réel entre deux sessions.
  void ecrire(String cle, String valeur) {
    _data['flutter.$cle'] = valeur;
    SharedPreferences.resetStatic();
  }

  bool contient(String cle) => _data.containsKey('flutter.$cle');
  Object? brut(String cle) => _data['flutter.$cle'];
  List<String> get cles =>
      _data.keys.map((k) => k.replaceFirst('flutter.', '')).toList();
}

FauxStore installerStore({Map<String, Object>? data}) {
  final s = FauxStore(data: data ?? prefsPoids());
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = s;
  store = s;
  return s;
}

// ─── Constructeurs ─────────────────────────────────────────────────────────

IaPronostic prono({
  required String courseKey,
  required DateTime date,
  String? typePari = 'Quinté+',
  bool resolu = true,
  List<int>? arrivee,
  int nbTop3 = 0,
  int nbTop5 = 0,
  int? rangFavori,
}) {
  return IaPronostic(
    courseKey: courseKey,
    nomCourse: 'PRIX $courseKey',
    hippodrome: 'VINCENNES',
    discipline: 'Trot Attelé',
    datePronostic: date,
    scoresIA: const {
      '1': 100.0, '2': 92.0, '3': 84.0, '4': 76.0, '5': 68.0,
    },
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

/// Gagnant Quinté+ : les 5 chevaux IA occupent les 5 premières places réelles.
IaPronostic pronoGagnant({
  required String courseKey,
  required DateTime date,
  String? typePari = 'Quinté+',
}) =>
    prono(
      courseKey: courseKey,
      date: date,
      typePari: typePari,
      arrivee: const [1, 2, 3, 4, 5],
      nbTop3: 3,
      nbTop5: 5,
      rangFavori: 1,
    );

/// Perdant : aucun cheval IA dans l'arrivée réelle.
IaPronostic pronoPerdant({
  required String courseKey,
  required DateTime date,
  String? typePari = 'Quinté+',
}) =>
    prono(
      courseKey: courseKey,
      date: date,
      typePari: typePari,
      arrivee: const [9, 10, 11, 12, 13],
    );

// ─── Prefs ─────────────────────────────────────────────────────────────────

Map<String, Object> prefsPoids() => <String, Object>{
      'ia_precision_migrated_v3': true,
      kPoidsKey: json.encode(<String, dynamic>{
        'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
        'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
        'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
        'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
        'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
        'mouvCote': 0.06, 'placeDepart': 0.03,
        'nbMisesAJour': 0, 'calibrationScore': 50.0,
      }),
      kSeuilsKey: json.encode(<String, dynamic>{}),
    };

/// Blob de travail peuplé directement (appareil déjà utilisé).
Map<String, Object> prefsAvecMemoire(List<IaPronostic> pronostics) {
  final prefs = prefsPoids();
  final jsonStr = json.encode(pronostics.map((p) => p.toJson()).toList());
  prefs[kPronosticsKey] =
      base64Encode(GZipCodec().encode(utf8.encode(jsonStr)));
  return prefs;
}

// ─── Actions ───────────────────────────────────────────────────────────────

Future<void> archiver(List<IaPronostic> lots) async {
  for (final p in lots) {
    IaArchiveService.instance.enregistrerEviction(p);
  }
  final ok = await IaArchiveService.instance.persisterEnAttente();
  if (!ok) throw StateError('archivage de préparation non confirmé');
}

// ─── Zone d'exécution de la chaîne d'écriture ──────────────────────────────

/// PRÉPARATION REQUISE POUR TOUT `testWidgets` QUI ÉCRIT DANS L'ARCHIVE.
///
///   ⚠️ Ceci ne contourne PAS un défaut de production : c'est un artefact du
///   harnais de test, explicité ici pour être auditable.
///
///   `IaArchiveService._writeChain` démarre à `Future.value()` et chaque
///   écriture s'y chaîne par `.then(...)` (sérialisation des écritures).
///   Une `Future` propage ses rappels DANS LA ZONE où elle a été CRÉÉE.
///   Si la chaîne a été créée dans le `setUp` (zone réelle), le `.then()`
///   exécuté depuis un `testWidgets` (zone `fakeAsync`) hérite de la zone
///   RÉELLE : sa microtâche n'est jamais drainée par `FakeAsync`, et
///   `persisterEnAttente()` / `securiser()` / `charger()` ne rendent jamais
///   la main. On observe alors un blocage du test, sans exception.
///
///   Recréer l'état RAM de l'archive À L'INTÉRIEUR du corps du `testWidgets`
///   réancre la chaîne dans la zone `fakeAsync` du test : le comportement
///   testé (écriture sérialisée incluse) redevient celui de la production.
///
/// Sans ce rappel, tous les tests `L-*` et `M-*` qui archivent se bloquent.
void preparerArchiveDansLaZoneDeTest() {
  IaArchiveService.instance.oublierChargementPourTest();
}

/// Enveloppe gzip+base64 contenant UNE entrée valide et UNE entrée corrompue.
String enveloppeAvecUneEntreeCorrompue(IaPronostic valide) {
  final jsonStr = json.encode(<dynamic>[
    valide.toJson(),
    <String, dynamic>{'courseKey': null, 'scoresIA': 'pas-une-map'},
  ]);
  return base64Encode(GZipCodec().encode(utf8.encode(jsonStr)));
}

/// Preuves statiques documentées (voir le commentaire de A1-1 dans le test).
const bool ancienLoadAvaitUnCatch = false; // try/finally sans catch (65edcab)
const bool nouveauLoadRethrow = true;      // catch + rethrow explicite (E2)
