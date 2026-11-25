// ═══════════════════════════════════════════════════════════════════════════
//  V25 — B5c étape 5 : tests de mutation du garde et de l'ordre du reset
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/.
//
//  Deux mutations sont visées :
//
//   ── M11 : garde de `_addAlert` ──────────────────────────────────────────
//     Mutation : retirer `if (_resetEnCours) return;` de `_addAlert()`.
//
//     Les deux écritures SharedPreferences déclenchées par `_addAlert`
//     (`_save()` chemin 1 et `_sendNativeNotification()` chemin 2) passent par
//     `_ecrireProtege` : la barrière les refuse dans les deux cas. Elles ne
//     peuvent donc PAS discriminer. Le seul effet non rattrapé est l'appel
//     `MethodChannel.invokeMethod('showNotification')` (alert_service.dart:837),
//     exécuté AVANT toute barrière : il faut un faux canal pour l'observer.
//
//   ── M12 : ordre du reset ────────────────────────────────────────────────
//     Mutation : sortir la boucle `remove()` du callback passé à
//     `executerResetComplet()`, donc la placer HORS barrière.
//
//     Discriminant : le journal ORDONNÉ du store. Sous mutation, une écriture
//     déclenchée pendant l'effacement produit un `SET` strictement compris
//     entre le premier et le dernier `REM`. Code normal : jamais.
//
//  ⚠️ Ces tests prouvent des observations ciblées, pas le bon fonctionnement
//     global de l'application.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/backup_service.dart';

// ─── Store à suspension déterministe ───────────────────────────────────────

class StoreSuspensible extends SharedPreferencesStorePlatform {
  StoreSuspensible({Map<String, Object>? data})
      : _data = <String, Object>{
          for (final e in (data ?? const <String, Object>{}).entries)
            (e.key.startsWith('flutter.') ? e.key : 'flutter.${e.key}'):
                e.value,
        };

  final Map<String, Object> _data;

  /// Motifs d'écriture suspendus → completer de libération.
  final Map<String, Completer<void>> verrous = <String, Completer<void>>{};

  /// Journal ordonné des opérations : 'SET clé' / 'REM clé'.
  final List<String> journal = <String>[];

  int get nbBloquees => verrous.values.where((c) => !c.isCompleted).length;

  void suspendre(String motif) {
    verrous[motif] = Completer<void>();
  }

  void relacher(String motif) {
    final c = verrous.remove(motif);
    if (c != null && !c.isCompleted) c.complete();
  }

  void relacherTout() {
    for (final c in verrous.values) {
      if (!c.isCompleted) c.complete();
    }
    verrous.clear();
  }

  Future<void> _attendre(String key) async {
    for (final e in verrous.entries.toList()) {
      if (key.contains(e.key) && !e.value.isCompleted) {
        await e.value.future; // ← suspension DÉTERMINISTE
      }
    }
  }

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
    // ── Crochet de suspension sur la CRÉATION du cache SharedPreferences ──
    // `SharedPreferences.getInstance()` n'appelle `getAllWithParameters` que
    // lorsque son completer statique est vide (shared_preferences_legacy
    // .dart:80-97). Suspendre ici suspend donc `await getInstance()`, qui est
    // le SEUL point d'attente entre le contrôle 1 et le contrôle 2 de
    // `_ecrireProtege` (alert_service.dart:560-567).
    getAllAppels++;
    if (_getAllVerrou != null && !_getAllVerrou!.isCompleted) {
      await _getAllVerrou!.future; // ← suspension DÉTERMINISTE
    }
    final f = parameters.filter;
    final result = Map<String, Object>.from(_data);
    result.removeWhere((k, _) =>
        !k.startsWith(f.prefix) ||
        (f.allowList != null && !f.allowList!.contains(k)));
    return result;
  }

  /// Verrou sur la prochaine création du cache.
  Completer<void>? _getAllVerrou;

  /// Nombre d'appels à `getAllWithParameters` : témoin du franchissement du
  /// contrôle 1 (si 0, l'écriture a été refusée AVANT `getInstance`).
  int getAllAppels = 0;

  /// Suspend le prochain `getAll` (création du cache).
  void suspendreGetAll() {
    _getAllVerrou = Completer<void>();
  }

  void relacherGetAll() {
    final c = _getAllVerrou;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<bool> remove(String key) async {
    await _attendre(key);
    journal.add('REM $key');
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await _attendre(key);
    journal.add('SET $key');
    _data[key] = value;
    return true;
  }

  bool contient(String cle) => _data.containsKey('flutter.$cle');
}

// ─── Canal natif instrumenté ───────────────────────────────────────────────

/// Nom EXACT du canal utilisé par `_sendNativeNotification`
/// (alert_service.dart:836).
const String kCanalNotifications = 'com.racepredictor.predict/permissions';

late StoreSuspensible store;
late List<String> appelsNatifs;

void installerStore() {
  store = StoreSuspensible();
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
}

void installerCanal() {
  appelsNatifs = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel(kCanalNotifications),
    (MethodCall call) async {
      appelsNatifs.add(call.method);
      return null;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final svc = AlertService.instance;

  setUp(() {
    installerStore();
    installerCanal();
  });

  tearDown(() {
    store.relacherTout();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(kCanalNotifications), null);
  });

  Future<SharedPreferences> p() => SharedPreferences.getInstance();

  Future<void> jusqua(bool Function() cond, {int tours = 60}) async {
    for (var i = 0; i < tours && !cond(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// État ancien minimal : la config à défaut suffit (`scopeToutes == true`
  /// laisse passer `ajouterAlertNonPartant`). On pose en plus une clé témoin
  /// pour que la boucle `remove()` ait de quoi s'exécuter.
  Future<void> installerEtatAncien() async {
    final prefs = await p();
    await prefs.setStringList('alert_history_v1', <String>['ANCIENNE_1']);
    await prefs.setStringList(
        'tracked_courses_v1', <String>['ANCIEN_PARIS']);
    await prefs.setStringList(
        'conseil_ia_notifies_v1', <String>['ANCIENNE_COURSE']);
    await svc.recharger();
  }

  TrackedCourse nouvelleCourse(String nom, {int numCourse = 9}) => TrackedCourse(
        numReunion: 9,
        numCourse: numCourse,
        nomCourse: nom,
        hippodrome: 'DEAUVILLE',
        heureDepart: DateTime.now().add(const Duration(hours: 5)),
        addedAt: DateTime.now(),
        typePari: 'Simple Gagnant',
        numerosJoues: const <int>[3],
        scoreIA: 55.0,
        cote: 6.0,
      );

  // ═══════════════════════════════════════════════════════════════════════
  //  V25-M11 — Aucune notification native pendant la barrière de reset
  // ═══════════════════════════════════════════════════════════════════════
  test('V25-M11 — aucune notification native n\'est émise pendant la '
      'barrière de reset', () async {
    await installerEtatAncien();

    // ══ TÉMOIN DE NON-VACUITÉ (obligatoire) ══════════════════════════════
    // Sans lui, `expect(appelsNatifs, isEmpty)` serait vrai même si le faux
    // canal n'était pas câblé : le test passerait pour la mauvaise raison.
    // On prouve donc d'abord que HORS reset, l'émission EST observée.
    svc.ajouterAlertNonPartant(
      alertId: 'TEMOIN_HORS_RESET',
      courseKey: 'R1C1_01012030',
      nomCourse: 'COURSE_TEMOIN',
      hippodrome: 'VINCENNES',
      numsStr: '7',
    );
    await jusqua(() => appelsNatifs.isNotEmpty);
    expect(appelsNatifs, contains('showNotification'),
        reason: 'le canal instrumenté doit voir les appels hors reset — '
            'sinon l\'assertion finale serait vraie par vacuité. '
            'Observé : $appelsNatifs');
    expect(svc.alerts.any((a) => a.id == 'TEMOIN_HORS_RESET'), isTrue,
        reason: 'hors reset, l\'alerte doit bien être ajoutée en RAM');
    await jusqua(() => svc.nbEcrituresEnCours == 0);

    // On repart d'un état propre pour mesurer la SEULE fenêtre de reset.
    appelsNatifs.clear();
    store.journal.clear();
    await BackupService.instance.reinitialiserAlertes();
    await svc.recharger();
    appelsNatifs.clear();
    store.journal.clear();
    expect(svc.alerts, isEmpty, reason: 'état de départ propre');
    expect(appelsNatifs, isEmpty, reason: 'compteur natif remis à zéro');

    // Suspension DÉTERMINISTE : la boucle `remove()` se fige sur cette clé,
    // ce qui garantit que `_resetEnCours == true` au moment de l'appel.
    store.suspendre('alert_history_v1');
    store.journal.clear();

    final reset = BackupService.instance.reinitialiserComplet();
    await jusqua(() => store.journal.any((e) => e.startsWith('REM')));
    expect(store.journal.any((e) => e.startsWith('REM')), isTrue,
        reason: 'la boucle d\'effacement doit avoir commencé');

    // Tentative d'alerte PENDANT la barrière. `ajouterAlertNonPartant` passe
    // le filtre de périmètre (config par défaut : scopeToutes == true) puis
    // appelle `_addAlert`.
    svc.ajouterAlertNonPartant(
      alertId: 'BLOQUE_M11',
      courseKey: 'R1C1_01012030',
      nomCourse: 'COURSE_BLOQUEE',
      hippodrome: 'VINCENNES',
      numsStr: '5',
    );
    await jusqua(() => false, tours: 10);

    // ── Assertion 1 : aucune trace en RAM ────────────────────────────────
    expect(svc.alerts.any((a) => a.id == 'BLOQUE_M11'), isFalse,
        reason: 'aucune alerte ne doit être ajoutée en RAM pendant le reset');

    // ── Assertion 2 : aucune écriture SharedPreferences ──────────────────
    expect(
        store.journal
            .any((e) => e.startsWith('SET') && e.contains('hippique_pending')),
        isFalse,
        reason: 'la file de notifications ne doit pas être écrite');

    // ── Assertion 3 : AUCUN appel natif ──────────────────────────────────
    // ⚠️ C'est la seule assertion qui discrimine la mutation M11 : les deux
    //    écritures SharedPreferences sont de toute façon refusées par
    //    `_ecrireProtege`. `invokeMethod` s'exécute AVANT la barrière, donc
    //    sans le garde de `_addAlert`, un appel natif est observé.
    expect(appelsNatifs, isEmpty,
        reason: 'aucun invokeMethod pendant la barrière — observé : '
            '$appelsNatifs');

    store.relacher('alert_history_v1');
    await reset;
    expect(appelsNatifs, isEmpty,
        reason: 'aucun appel natif différé après le reset');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V25-M12 — Aucune écriture ne s'intercale dans l'effacement
  // ═══════════════════════════════════════════════════════════════════════
  test('V25-M12 — l\'effacement s\'exécute sous barrière : aucune écriture '
      'ne s\'y intercale', () async {
    await installerEtatAncien();
    expect((await p()).getStringList('tracked_courses_v1'), isNotNull);

    // ══ TÉMOIN DE NON-VACUITÉ (obligatoire) ══════════════════════════════
    // Sans lui, `expect(intercalees, isEmpty)` serait vrai même si le journal
    // ne contenait aucun SET : le test passerait pour la mauvaise raison.
    // On prouve donc d'abord que HORS reset, les SET sont bien journalisés.
    store.journal.clear();
    await svc.ajouterSuivi(nouvelleCourse('TEMOIN_HORS_RESET'));
    await jusqua(() => svc.nbEcrituresEnCours == 0);
    await jusqua(() => false, tours: 5);
    final temoins = store.journal.where((e) => e.startsWith('SET')).toList();
    expect(temoins, isNotEmpty,
        reason: 'hors reset, les SET doivent être journalisés — sinon '
            'l\'assertion finale serait vraie par vacuité. Observé : '
            '$temoins');
    expect(temoins.any((e) => e.contains('tracked_courses_v1')), isTrue,
        reason: 'le SET de la clé visée doit être visible');

    // On repart d'un état propre pour mesurer la SEULE fenêtre de reset.
    await BackupService.instance.reinitialiserAlertes();
    await svc.recharger();
    store.journal.clear();

    store.suspendre('alert_history_v1');
    store.journal.clear();

    final reset = BackupService.instance.reinitialiserComplet();
    await jusqua(() => store.journal.any((e) => e.startsWith('REM')));
    expect(store.journal.any((e) => e.startsWith('REM')), isTrue,
        reason: 'la boucle d\'effacement doit avoir commencé');

    // Tentative d'écriture pendant l'effacement, via les chemins de
    // PRODUCTION (aucune écriture directe sur SharedPreferences).
    await svc.ajouterSuivi(nouvelleCourse('INTERCALE_M12'));
    await svc.ajouterFavoriPourWorker(
      numR: 7,
      numC: 7,
      nomCourse: 'FAVORI_M12',
      hippodrome: 'VINCENNES',
      scoreIA: 61.0,
    );
    await jusqua(() => false, tours: 10);

    store.relacher('alert_history_v1');
    await reset;

    // ── Discriminant : ordre dans le journal ─────────────────────────────
    // Si l'effacement est sous barrière, aucun SET ne peut être journalisé
    // entre le premier et le dernier REM : les écritures sont refusées.
    final premier = store.journal.indexWhere((e) => e.startsWith('REM'));
    expect(premier, greaterThanOrEqualTo(0));
    final effacement = store.journal.sublist(premier);
    final intercalees =
        effacement.where((e) => e.startsWith('SET')).toList();

    expect(intercalees, isEmpty,
        reason: 'aucune écriture ne doit s\'intercaler dans l\'effacement. '
            'Intercalées : $intercalees');

    // Contrôle de cohérence : les clés visées restent effacées et les
    // tentatives n'ont pas laissé d'état fantôme en RAM.
    expect((await p()).containsKey('tracked_courses_v1'), isFalse,
        reason: 'la clé doit rester effacée');
    expect(svc.trackedCourses, isEmpty,
        reason: 'aucun pari fantôme ne doit rester en RAM');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V25-M3 — Le contrôle de GÉNÉRATION, isolé de `_resetEnCours`
  // ═══════════════════════════════════════════════════════════════════════
  //
  //  Difficulté : le contrôle 1 (`if (_resetEnCours) return false`, l.560)
  //  masque le contrôle 2. Pour isoler la génération, il faut que l'écriture
  //  reprenne APRÈS la FIN du reset, donc quand `_resetEnCours == false`.
  //
  //  Deux obstacles levés :
  //
  //  1. `reinitialiserComplet()` commence par `await getInstance()`
  //     (backup_service.dart:1410). Si l'écriture est suspendue dans la
  //     création du cache, le reset se suspend sur la MÊME future
  //     (`_completer!.future`, shared_preferences_legacy.dart:97) et ne peut
  //     pas incrémenter la génération : entrelacement impossible par cette
  //     voie. → On appelle donc `executerResetComplet()` DIRECTEMENT (méthode
  //     publique), avec un callback VIDE : aucun `getInstance`, le reset se
  //     termine intégralement.
  //
  //  2. Il faut suspendre l'écriture entre le contrôle 1 et le contrôle 2.
  //     Le seul point d'attente y est `await SharedPreferences.getInstance()`
  //     (l.563). On le suspend via le store : quand le completer statique est
  //     vide, `getInstance()` appelle `getAllWithParameters`
  //     (shared_preferences_legacy.dart:80-97), et c'est là qu'on bloque.
  test('V25-M3 — une écriture suspendue avant le reset est refusée par le '
      'contrôle de génération, sans que _resetEnCours soit en cause', () async {
    await installerEtatAncien();
    await jusqua(() => svc.nbEcrituresEnCours == 0);

    // ══ TÉMOIN 1 : le crochet getAll est bien câblé ══════════════════════
    // Sans ce témoin, un `setup` défaillant ferait passer le test pour la
    // mauvaise raison (aucune suspension = aucune fenêtre = refus trivial).
    SharedPreferences.resetStatic();
    await SharedPreferences.getInstance();
    final appelsAvant = store.getAllAppels;
    SharedPreferences.resetStatic();
    await SharedPreferences.getInstance();
    expect(store.getAllAppels, greaterThan(appelsAvant),
        reason: 'resetStatic() doit provoquer un nouvel appel à getAll — '
            'sinon le crochet de suspension serait inopérant');

    // ══ TÉMOIN 2 : HORS reset, ce même type d'écriture aboutit ═══════════
    // Prouve que la génération est le SEUL discriminant, et pas un défaut de
    // configuration du store.
    store.journal.clear();
    await svc.ajouterFavoriPourWorker(
      numR: 5,
      numC: 5,
      nomCourse: 'TEMOIN_M3',
      hippodrome: 'VINCENNES',
      scoreIA: 58.0,
    );
    await jusqua(() => svc.nbEcrituresEnCours == 0);
    await jusqua(() => false, tours: 5);
    expect(store.journal.any((e) => e.startsWith('SET')), isTrue,
        reason: 'hors reset, l\'écriture doit aboutir — journal : '
            '${store.journal}');

    // ══ MISE EN PLACE DE LA FENÊTRE ══════════════════════════════════════
    // On vide le cache puis on suspend la PROCHAINE création.
    SharedPreferences.resetStatic();
    store.suspendreGetAll();
    store.journal.clear();
    final appelsAvantSuspension = store.getAllAppels;

    // 1. Écriture lancée SANS await : elle franchit le contrôle 1
    //    (_resetEnCours == false à cet instant), copie la génération
    //    courante, puis se suspend dans `getInstance()`.
    final ecriture = svc.ajouterFavoriPourWorker(
      numR: 7,
      numC: 7,
      nomCourse: 'ECRITURE_SUSPENDUE_M3',
      hippodrome: 'VINCENNES',
      scoreIA: 60.0,
    );

    // 2. TÉMOIN 3 : l'écriture a bien atteint le crochet, donc le contrôle 1
    //    a été FRANCHI (sinon `getAll` n'aurait pas été appelé).
    await jusqua(() => store.getAllAppels > appelsAvantSuspension, tours: 20);
    expect(store.getAllAppels, greaterThan(appelsAvantSuspension),
        reason: 'le contrôle 1 doit avoir été franchi (getAll appelé) — '
            'sinon le test ne mesure pas la génération mais le contrôle 1');
    expect(svc.nbEcrituresEnCours, 0,
        reason: 'l\'écriture n\'est PAS encore au registre : elle est entre '
            'le contrôle 1 et le contrôle 2, exactement dans la fenêtre visée');

    // 3. Reset lancé SANS await, callback VIDE. Aucun `getInstance`, donc le
    //    reset ne dépend pas de la future sur laquelle l'écriture est bloquée.
    var resetTermine = false;
    final reset = svc
        .executerResetComplet(() async {})
        .whenComplete(() => resetTermine = true);

    await jusqua(() => resetTermine, tours: 40);

    // ══ TÉMOIN 4 : le reset est ENTIÈREMENT terminé AVANT la reprise ═════
    expect(resetTermine, isTrue,
        reason: 'le reset doit être terminé avant la reprise de l\'écriture');
    // `_resetEnCours` est donc retombé : le contrôle 1 ne peut plus être le
    // discriminant. C'est la condition expresse de la mission.
    expect(svc.trackedCourses, isEmpty,
        reason: 'l\'état RAM doit avoir été vidé par le reset');
    expect(svc.config.activerRappelQuotidien, isFalse,
        reason: 'la config doit être revenue au défaut : le reset a bien '
            'exécuté son corps complet');

    // 4. REPRISE : l'écriture sort de `getInstance()` et atteint le
    //    contrôle 2, avec une génération périmée et `_resetEnCours == false`.
    store.relacherGetAll();
    await ecriture;
    await jusqua(() => false, tours: 10);

    // ══ ASSERTION : refusée, et aucune écriture sur le disque ════════════
    expect(store.journal.where((e) => e.startsWith('SET')), isEmpty,
        reason: 'le contrôle de génération doit refuser l\'écriture. '
            'Journal : ${store.journal}');
    expect(svc.derniereErreurEcriture, isNull,
        reason: 'le refus doit être silencieux, pas une exception');
    expect(svc.trackedCourses, isEmpty,
        reason: 'aucun état fantôme ne doit être réintroduit');

    await reset;
  });
}
