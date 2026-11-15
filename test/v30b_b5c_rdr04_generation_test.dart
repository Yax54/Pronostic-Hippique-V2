// ═══════════════════════════════════════════════════════════════════════════
//  B5c — R-DR-04 — VÉRIFICATION COMPLÉMENTAIRE (mutation M33)
//
//  OBJET : déterminer si la capture `generationAuDemarrage = _generationCache`
//  doit être placée AVANT `await _load()` ou si un placement APRÈS serait
//  équivalent. C'est exactement la mutation M33.
//
//  POURQUOI UN FICHIER SÉPARÉ : `_loaded` n'a AUCUN setter et ne repasse
//  jamais à `false` en dehors d'un reset ou de `recharger()` (interdit ici).
//  Il ne vaut `false` qu'UNE fois par processus, au tout début. Ce fichier
//  contient donc UN SEUL test, premier et unique, pour observer ce cas.
//
//  SCÉNARIO : `_load()` est retenu DANS `SharedPreferences.getInstance()`
//  (verrou `getAll` + `resetStatic()`). Un reset complet s'exécute PENDANT
//  cette suspension : il incrémente `_generationCache` (étape 1) puis attend
//  le chargement en vol (étape 3). À la libération, la méthode reprend APRÈS
//  la fin du reset : `_resetEnCours` est retombé à `false`.
//
//  ⇒ Seule la GÉNÉRATION capturée AVANT `_load()` peut révéler le reset.
//    Si la capture est faite APRÈS `_load()`, elle lit la valeur déjà
//    incrémentée et la garde laisse passer la mutation.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  Completer<void>? _verrouGetAll;
  Completer<void>? _entreeGetAll;

  @override
  Future<bool> clear() async {
    journal.add('CLEAR');
    _valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    journal.add('GETALL');
    final verrou = _verrouGetAll;
    if (verrou != null) {
      final entree = _entreeGetAll;
      _entreeGetAll = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      await verrou.future;
    }
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET $key');
    _valeurs[key] = value;
    return true;
  }

  Completer<void> armerSuspensionGetAll() {
    final entree = Completer<void>();
    _entreeGetAll = entree;
    _verrouGetAll = Completer<void>();
    return entree;
  }

  void libererGetAll() {
    final v = _verrouGetAll;
    _verrouGetAll = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void effacerDirect(String cle) {
    journal.add('REM flutter.$cle');
    _valeurs.remove('flutter.$cle');
  }

  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
}

// ignore: library_private_types_in_public_api
late _Store store;

Future<void> _laisserProgresser([int tours = 24]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<bool> _attendreQue(bool Function() condition, [int maxTours = 1200]) async {
  for (var i = 0; i < maxTours; i++) {
    if (condition()) return true;
    await Future<void>.delayed(Duration.zero);
  }
  return condition();
}

const String kCourseKey = 'R2C3_01012026';
const String kPronosticsKey = 'ia_pronostics_v2';

String _dateDuJour() {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

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
      ageSexe: '5 M',
      poids: 57.0 + num,
      placeDepartInt: num,
      joursRepos: 10 + num,
      hippodromeActuel: 'VINCENNES',
      statsJockeyCsv: 'JOCKEY_$num|15|40|12',
      statsHippodromeCsv: 'VINCENNES|20|45|15',
      statsEntraineurCsv: 'ENTR_$num|12|33|8',
      eloRating: 1500.0,
      eloNbCourses: 20,
      eloVariationMois: 5.0,
      statsTerrainCsv: 'bon|6|2|4',
      gainsDernierAn: num * 5000,
      scoreIA: 70.0 - num,
    );

final List<ZtPartant> kPartants = List.generate(6, (i) => _partant(i + 1));

ZtCourse _course(List<ZtPartant> partants) => ZtCourse(
      numCourse: 3,
      anchor: 'R2C3',
      nom: 'PRIX DE TEST M33',
      heure: '15:10',
      distance: '2100',
      prix: '50000',
      type: 'Trot Attelé',
      piste: 'Cendrée',
      categorie: 'Course D',
      isQuinte: false,
      pronosticZt: const <int>[],
      partants: partants,
    )..dateStr = _dateDuJour();

ScoresCriteres _criteres() => const ScoresCriteres(
      forme: 71, gains: 62, record: 55, cote: 48,
      constance: 60, victoires: 66, discipline: 58,
    );

Future<void> _invalider() {
  final p = kPartants;
  return IaMemoryService.instance.invaliderEtRecalculer(
    courseKey: kCourseKey,
    course: _course(p),
    partantsClasses: p,
    scoresCriteres: <String, ScoresCriteres>{
      for (final q in p) q.numero: _criteres()
    },
    confiance: 66.0,
    raisonInvalidation: 'M33',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
  });

  tearDown(() {
    store.libererGetAll();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R04-H / M33 — LA CAPTURE DOIT PRÉCÉDER `await _load()`
  //
  //  Précondition : ce test est le PREMIER et l'UNIQUE du fichier, donc
  //  `_loaded == false`. C'est la seule configuration où `_load()` lit
  //  réellement le disque et peut donc être suspendu.
  // ═══════════════════════════════════════════════════════════════════════
  test('R04-H — capture AVANT `_load()` : indispensable quand `_load()` suspend',
      () async {
    final mem = IaMemoryService.instance;

    // Garde de précondition : si `_loaded` valait `true`, `_load()` rendrait
    // la main sans jamais lire le disque et ce test ne mesurerait rien.
    // On n'utilise pas le Completer d'entrée : on attend la trace « GETALL »
    // dans le journal, ce qui est strictement équivalent et plus lisible.
    store.armerSuspensionGetAll();
    final genAvant = mem.generationCache;

    final recalcul = _invalider(); // non attendu : on veut le suspendre

    final suspendu = await _attendreQue(
        () => store.journal.contains('GETALL'));
    expect(suspendu, isTrue,
        reason: 'GARDE DE PRÉCONDITION : `_load()` LIT le disque, donc '
            '`_loaded` valait bien `false` au départ. Sinon ce test serait muet');
    await _laisserProgresser(4);

    expect(mem.pronostics.length, 0,
        reason: 'TÉMOIN : la mutation RAM n\'a pas encore eu lieu — la méthode '
            'est retenue dans `_load()`');

    // ── Reset complet PENDANT la suspension de `_load()` ─────────────────
    final reset = mem.executerResetComplet(() async {
      store.effacerDirect(kPronosticsKey);
      await Future<void>.delayed(Duration.zero);
    });
    await _laisserProgresser(8);

    debugPrint('R04-H pendant : gen=$genAvant→${mem.generationCache} '
        'RAM=${mem.pronostics.length} '
        'disque=${store.contient(kPronosticsKey)}');
    expect(mem.generationCache, genAvant + 1,
        reason: 'TÉMOIN : l\'incrément de génération a eu lieu (étape 1 du '
            'reset) AVANT que `_load()` ne rende la main');

    // ── Libération : `_load()` aboutit, le reset se termine ──────────────
    store.libererGetAll();
    await reset;
    await recalcul;
    await _laisserProgresser();

    debugPrint('R04-H après : RAM=${mem.pronostics.length} '
        'getPronostic=${mem.getPronostic(kCourseKey) != null} '
        'disque=${store.contient(kPronosticsKey)}');

    // ── ASSERTION DISCRIMINANTE DE M33 ───────────────────────────────────
    //
    //  Avec la capture AVANT `await _load()` : `generationAuDemarrage` vaut
    //  `genAvant`, la génération courante vaut `genAvant + 1` → la garde
    //  refuse → AUCUNE mutation → RAM vide.
    //
    //  Avec la capture APRÈS `await _load()` (mutation M33) : la valeur lue
    //  est déjà `genAvant + 1`, `_resetEnCours` est retombé à `false` (le
    //  reset est terminé) → les deux conditions passent → la mutation a lieu
    //  → RAM peuplée d'un pronostic que le disque n'a pas.
    expect(mem.pronostics.length, 0,
        reason: 'CORRECTION R-DR-04 : la capture faite AVANT `_load()` révèle '
            'le reset survenu pendant la suspension, donc la mutation RAM est '
            'refusée. Si la capture était faite après `_load()`, elle lirait '
            'la génération DÉJÀ incrémentée, la garde laisserait passer et un '
            'pronostic fantôme serait créé (mutation M33)');
    expect(mem.getPronostic(kCourseKey), isNull,
        reason: 'CORRECTION : aucun pronostic fantôme consultable');
    expect(store.contient(kPronosticsKey), isFalse,
        reason: 'CORRECTION : et rien sur le disque — cohérence préservée');
  });
}
