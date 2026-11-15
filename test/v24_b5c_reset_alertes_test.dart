// ═══════════════════════════════════════════════════════════════════════════
//  V24 — B5c étape 5 : la réinitialisation complète sécurise-t-elle
//                      AlertService contre la résurrection par écriture tardive ?
//
//  ⚠️  FICHIER DE TEST uniquement. AUCUNE modification de lib/ autre que le
//      correctif B5c étape 5 lui-même.
//
//  Défaut d'origine (B5c étape 5) :
//    `reinitialiserComplet()` effaçait bien les 9 clés d'AlertService du
//    disque, MAIS le service possède HUIT chemins d'écriture SharedPreferences
//    et deux `Timer.periodic` actifs :
//      • le watchdog de 60 s appelait `_addAlert` → `_save()` sans aucune
//        action utilisateur, réécrivant les 6 clés avec les anciens paris ;
//      • `_config` n'était jamais rechargé quand sa clé manquait (`if` sans
//        `else`) : l'ancienne configuration restait en RAM et pilotait les
//        gates tout en étant réécrite sur le disque ;
//      • une écriture déjà engagée pouvait se terminer APRÈS l'effacement et
//        recréer les clés (fenêtre de concurrence).
//
//  ⚠️ Ces tests prouvent des observations ciblées, pas le bon fonctionnement
//     global de l'application.
//
//  Périmètre STRICT : aucun calcul, aucun filtre, aucun critère IA, aucun
//  seuil, aucune formule d'ID d'alerte, aucun timer.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/backup_service.dart';

// ─── Store à suspension déterministe ───────────────────────────────────────

/// Store en mémoire dont chaque écriture peut être SUSPENDUE à la demande.
///
/// Aucune dépendance au hasard du scheduling : le test décide exactement où
/// l'écriture est bloquée, puis la relâche quand il veut observer l'effet.
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
    final f = parameters.filter;
    final result = Map<String, Object>.from(_data);
    result.removeWhere((k, _) =>
        !k.startsWith(f.prefix) ||
        (f.allowList != null && !f.allowList!.contains(k)));
    return result;
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

late StoreSuspensible store;

void installerStore([Map<String, Object>? data]) {
  store = StoreSuspensible(data: data);
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
}

// ─── Constantes et fabriques de test ───────────────────────────────────────

const List<String> kClesAlertes = <String>[
  'alert_config_v2',
  'alert_history_v1',
  'tracked_courses_v1',
  'alert_sent_ids_v1',
  'alert_resultats_verifies_v1',
  'hippique_favorites_v1',
  'conseil_ia_notifies_v1',
  'conseil_ia_notifies_v1_date', // ★ R-12
  'conseil_ia_resume_date',
  'alert_cote_chute_notifies_v1',
  'flutter.hippique_pending_notifs', // ★ R-13
];

/// Alertes persistées au VRAI format de production : `AppAlert.toJson()`.
///
/// ⚠️ Piège vérifié : `_load()` décode avec `AlertType.values[j['type'] as int]`
///    (alert_service.dart:141). `type` doit donc être l'INDEX ENTIER de l'enum,
///    pas son nom. Un JSON non conforme lève une `TypeError` avalée
///    silencieusement par le `catch (_)` de `_load()` (alert_service.dart:517) :
///    le service reste vide et toute assertion post-reset devient vraie par
///    vacuité. C'est exactement le défaut qui avait invalidé V24-2/5/16.
List<String> alertesAnciennes() => <String>[
      json.encode(AppAlert(
        id: 'ANCIENNE_1',
        type: AlertType.courseImminente,
        titre: 'Ancienne 1',
        message: 'msg',
        timestamp: DateTime.parse('2020-01-01T00:00:00.000'),
      ).toJson()),
      json.encode(AppAlert(
        id: 'ANCIENNE_2',
        type: AlertType.courseImminente,
        titre: 'Ancienne 2',
        message: 'msg',
        timestamp: DateTime.parse('2020-01-02T00:00:00.000'),
      ).toJson()),
    ];

/// Course suivie persistée. Clé avec date valide (regex R\d+C\d+_\d{8}) et
/// départ à +2 h : survit au filtre de purge de `_load()`.
String courseAncienneJson(int index) => json.encode(<String, dynamic>{
      'numReunion': 1,
      'numCourse': index + 1,
      'nomCourse': 'ANCIENNE_COURSE_$index',
      'hippodrome': 'VINCENNES',
      'heureDepart':
          DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
      'addedAt': DateTime.now().toIso8601String(),
      'typePari': 'Simple Gagnant',
      'miseEngagee': null,
      'numerosJoues': <int>[],
      'scoreIA': 0.0,
      'cote': 0.0,
      'storageKey': 'R1C${index + 1}_01012030_1000',
    });

/// Réunion factice portant une course nommée, utilisée pour alimenter le
/// cache `_coursesMatchingConseils` via `recalculerCoursesConseilIA`.
///
/// ⚠️ Aucune logique métier n'est testée ici : on se sert uniquement du
///    cache comme d'un support pour l'instantané S1.
ZtReunion reunionAvecCourse(String nomCourse, {int numCourse = 1}) {
  return ZtReunion(
    code: 'R1',
    lieu: 'VINCENNES',
    discipline: 'Trot',
    dateStr: '01012030',
    courses: <ZtCourse>[
      ZtCourse(
        numCourse: numCourse,
        anchor: 'c$numCourse',
        nom: nomCourse,
        heure: '14:00',
        distance: '2700',
        prix: '50000',
        type: 'Attelé',
        piste: 'Grande piste',
        categorie: 'Course D',
        isQuinte: false,
        pronosticZt: const <int>[],
        partants: <ZtPartant>[
          ZtPartant(
            numero: '1',
            nom: 'CHEVAL_A',
            driver: 'D',
            entraineur: 'E',
            proprietaire: 'P',
            gains: '1000',
            record: '1\'12',
            musique: '1a2a',
            cote: '3.5',
            ageSexe: '5H',
            scoreIA: 80.0,
          ),
        ],
      ),
    ],
  );
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

void main() {
  final svc = AlertService.instance;

  setUp(() {
    installerStore(<String, Object>{});
  });

  tearDown(() {
    store.relacherTout();
  });

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<SharedPreferences> p() => SharedPreferences.getInstance();

  Future<void> installerEtatAncien({
    int nbCourses = 2,
    bool rappelActif = false,
    List<String>? notifies,
  }) async {
    final prefs = await p();
    await prefs.setString(
      'alert_config_v2',
      json.encode(<String, dynamic>{
        'activerCourseImminente': true,
        'activerCourseCommence': true,
        'activerCourseEnCours': false,
        'activerResultats': true,
        'activerRappelMise': true,
        'minutesAvantDepart': 15,
        'vibrationsActivees': true,
        'sonsActives': true,
        'scopeToutes': true,
        'scopeFavoris': false,
        'scopeSuivies': false,
        'activerConseilIA': true,
        'activerCoteChute': true,
        'activerDerniereChance': true,
        'activerRappelQuotidien': rappelActif,
        'rappelHeure': rappelActif ? DateTime.now().hour : 9,
        'rappelMinute': rappelActif ? DateTime.now().minute : 0,
      }),
    );
    await prefs.setStringList('alert_history_v1', alertesAnciennes());
    await prefs.setStringList(
      'tracked_courses_v1',
      List<String>.generate(nbCourses, courseAncienneJson),
    );
    await prefs.setStringList('alert_sent_ids_v1', <String>['ANCIEN_ID_1']);
    await prefs.setStringList(
        'alert_resultats_verifies_v1', <String>['ANCIEN_RES_1']);
    await prefs.setStringList(
        'alert_cote_chute_notifies_v1', <String>['ANCIEN_COTE_1']);
    await prefs.setStringList(
        'conseil_ia_notifies_v1', notifies ?? <String>['ANCIEN_NE_1']);
    await prefs.setString('conseil_ia_notifies_v1_date', '20200101');
    await prefs.setString('conseil_ia_resume_date', '20200101');
    await prefs.setString('hippique_favorites_v1', '[]');
    await prefs.setString(
        'flutter.hippique_pending_notifs', '["999|ANCIENNE|msg|1"]');

    await svc.recharger();
  }

  Future<bool> presente(String cle) async => (await p()).containsKey(cle);

  Future<List<String>> liste(String cle) async =>
      (await p()).getStringList(cle) ?? <String>[];

  /// Laisse tourner les microtâches jusqu'à ce que [cond] soit vraie.
  Future<void> jusqua(bool Function() cond, {int tours = 40}) async {
    for (var i = 0; i < tours && !cond(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-1 — Le reset efface les 11 clés d'AlertService (dont R-12, R-13)
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-1 — reinitialiserComplet() efface les 11 clés d\'AlertService',
      () async {
    await installerEtatAncien();
    for (final k in kClesAlertes) {
      expect(await presente(k), isTrue, reason: '$k doit exister avant reset');
    }

    await BackupService.instance.reinitialiserComplet();

    for (final k in kClesAlertes) {
      expect(await presente(k), isFalse,
          reason: '$k doit être effacée par le reset complet');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-2 — Après reset, la RAM d'AlertService est vide
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-2 — reinitialiserComplet() vide la RAM (alertes + paris + compteurs)',
      () async {
    await installerEtatAncien();

    // ── Assertions de NON-VACUITÉ (exigées) ────────────────────────────────
    // Sans elles, les `isEmpty` post-reset seraient vraies même si `_load()`
    // n'avait rien chargé (JSON non conforme → exception avalée l.517).
    expect(svc.alerts, isNotEmpty,
        reason: 'les 2 anciennes alertes doivent être RÉELLEMENT en RAM');
    expect(svc.alerts.length, 2);
    expect(svc.alerts.map((a) => a.id).toSet(), {'ANCIENNE_1', 'ANCIENNE_2'},
        reason: 'les identifiants chargés doivent être ceux du disque');
    expect(svc.trackedCourses, isNotEmpty,
        reason: 'les anciens paris doivent être RÉELLEMENT en RAM');
    expect(svc.trackedCourses.length, 2);
    expect(svc.trackedCourses.values.every(
            (tc) => tc.nomCourse.startsWith('ANCIENNE_COURSE_')),
        isTrue,
        reason: 'les paris chargés doivent être ceux du disque');
    expect(svc.unreadCount, 2);

    await BackupService.instance.reinitialiserComplet();

    expect(svc.alerts, isEmpty, reason: 'aucune alerte ne doit rester en RAM');
    expect(svc.trackedCourses, isEmpty,
        reason: 'aucun pari suivi ne doit rester en RAM');
    expect(svc.unreadCount, 0);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-3 — Après reset, la configuration est revenue au défaut
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-3 — reinitialiserComplet() remet _config à AlertConfig.defaut',
      () async {
    await installerEtatAncien(rappelActif: true);
    expect(svc.config.activerRappelQuotidien, isTrue,
        reason: 'config ancienne attendue avant reset');

    await BackupService.instance.reinitialiserComplet();

    expect(svc.config.activerRappelQuotidien, isFalse,
        reason: 'activerRappelQuotidien doit revenir à false (défaut)');
    expect(svc.config.activerDerniereChance, isTrue);
    expect(svc.config.activerCourseImminente, isTrue);
    expect(svc.config.minutesAvantDepart, 15);
    expect(svc.config.scopeToutes, isTrue);
    expect(svc.config.scopeFavoris, isFalse);
    expect(svc.config.scopeSuivies, isFalse);
    expect(svc.config.rappelHeure, 9);
    expect(svc.config.rappelMinute, 0);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-4 — Aucun ancien rappel quotidien ne peut plus se déclencher
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-4 — après reset, activerRappelQuotidien == false neutralise '
      'tout rappel', () async {
    await installerEtatAncien(rappelActif: true);
    expect(svc.config.activerRappelQuotidien, isTrue);
    expect(svc.config.rappelHeure, DateTime.now().hour);

    await BackupService.instance.reinitialiserComplet();

    expect(svc.config.activerRappelQuotidien, isFalse);
    expect(svc.config.rappelHeure, AlertConfig.defaut.rappelHeure);
    expect(await presente('conseil_ia_resume_date'), isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-5 — Aucune ancienne alerte / aucun ancien pari ne ressuscite
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-5 — après reset + nouvelles écritures, aucun ancien pari ni '
      'ancienne alerte ne réapparaît', () async {
    await installerEtatAncien();

    // ── Assertions de NON-VACUITÉ : l'état ancien doit être RÉELLEMENT chargé,
    //    sinon la « non-résurrection » serait vraie sur une collection vide. ──
    expect((await liste('tracked_courses_v1')).length, 2);
    expect((await liste('alert_history_v1')).length, 2,
        reason: 'les 2 anciennes alertes doivent être écrites sur le disque');
    expect(svc.alerts.length, 2,
        reason: 'et RÉELLEMENT chargées en RAM avant le reset');
    expect(svc.trackedCourses.length, 2,
        reason: 'les 2 anciens paris doivent être chargés en RAM avant le reset');

    await BackupService.instance.reinitialiserComplet();

    // Après reset, l'état doit être VIDÉ — et non « vide au départ ».
    expect(svc.alerts, isEmpty);
    expect(svc.trackedCourses, isEmpty);

    // Écritures légitimes post-reset, via le chemin de production.
    await svc.ajouterSuivi(nouvelleCourse('NOUVELLE_COURSE_2', numCourse: 8));
    await jusqua(() => svc.nbEcrituresEnCours == 0);

    final tracked = await liste('tracked_courses_v1');
    final alertes = await liste('alert_history_v1');

    expect(tracked.length, 1, reason: 'seule la nouvelle course est écrite');
    expect(tracked.first, contains('NOUVELLE_COURSE_2'));
    expect(tracked.any((s) => s.contains('ANCIENNE_COURSE')), isFalse,
        reason: 'aucune ancienne course ne doit revenir');

    // ⚠️ NON-VACUITÉ : `ajouterSuivi` émet une alerte de confirmation
    //    (`rappelMise`, id '<baseKey>_added_<date>'). Sa PRÉSENCE prouve que
    //    `alert_history_v1` est bien réécrite et relue ; l'ABSENCE des deux
    //    anciennes prouve alors une vraie non-résurrection, et non une liste
    //    restée vide faute de contenu.
    expect(alertes, isNotEmpty,
        reason: 'la confirmation de pari doit avoir repeuplé le disque');
    expect(alertes.length, 1,
        reason: 'une seule alerte légitime : la confirmation de pari');
    expect(alertes.first, contains('_added_'),
        reason: "il s'agit bien de l'alerte de confirmation");
    expect(alertes.any((s) => s.contains('ANCIENNE_1')), isFalse,
        reason: 'aucune ancienne alerte ne doit revenir');
    expect(alertes.any((s) => s.contains('ANCIENNE_2')), isFalse,
        reason: 'aucune ancienne alerte ne doit revenir');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-6 — CONCURRENCE (chemin 1, _save) : écriture suspendue puis reset
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-6 — une écriture _save suspendue ne réécrit rien après le reset',
      () async {
    await installerEtatAncien();

    // Suspension déterministe : la 1re écriture de _save (config) bloque.
    store.suspendre('alert_config_v2');

    // Écriture engagée, non attendue : elle franchit les contrôles puis se
    // suspend DANS prefs.setString.
    final ecriture = svc.ajouterSuivi(nouvelleCourse('EN_VOL'));
    await jusqua(() => store.nbBloquees > 0);
    expect(store.nbBloquees, greaterThan(0),
        reason: 'l\'écriture doit être réellement suspendue');
    expect(svc.nbEcrituresEnCours, greaterThan(0),
        reason: 'l\'écriture suspendue doit être dans le registre');

    // Le reset démarre : il doit être BLOQUÉ sur le drain.
    var resetTermine = false;
    final reset = BackupService.instance
        .reinitialiserComplet()
        .whenComplete(() => resetTermine = true);

    await jusqua(() => false, tours: 10);
    expect(resetTermine, isFalse,
        reason: 'le reset doit attendre la fin du drain, pas continuer');

    // Libération : l'écriture se termine, le drain se vide, le reset efface.
    store.relacher('alert_config_v2');
    await ecriture;
    await reset;

    expect(await presente('tracked_courses_v1'), isFalse,
        reason: 'tracked_courses_v1 doit rester effacée après le drain');
    expect(await presente('alert_history_v1'), isFalse);
    expect(await presente('alert_config_v2'), isFalse);
    expect(svc.trackedCourses, isEmpty);
    expect(svc.nbEcrituresEnCours, 0);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-7 — CONCURRENCE (chemin 3, favoris)
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-7 — une écriture de favoris suspendue ne survit pas au reset',
      () async {
    await installerEtatAncien(nbCourses: 1);
    await (await p()).setString('hippique_favorites_v1',
        '[{"numR":1,"numC":1,"dejaParI":false}]');
    await svc.recharger();

    store.suspendre('hippique_favorites_v1');

    final ecriture = svc.ajouterFavoriPourWorker(
      numR: 2,
      numC: 2,
      nomCourse: 'FAVORI_EN_VOL',
      hippodrome: 'VINCENNES',
      scoreIA: 70.0,
    );
    await jusqua(() => store.nbBloquees > 0);
    expect(store.nbBloquees, greaterThan(0));

    var resetTermine = false;
    final reset = BackupService.instance
        .reinitialiserComplet()
        .whenComplete(() => resetTermine = true);
    await jusqua(() => false, tours: 10);
    expect(resetTermine, isFalse,
        reason: 'le reset doit attendre cette écriture (registre unifié)');

    store.relacher('hippique_favorites_v1');
    await ecriture;
    await reset;

    expect(await presente('hippique_favorites_v1'), isFalse,
        reason: 'la clé favoris doit rester effacée');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-8 — CONCURRENCE (chemin 6, conseil IA notifiés)
  //
  //  Le cache est alimenté via `recalculerCoursesConseilIA` de façon à ce que
  //  la boucle de `verifierNouvellesCoursesConseilIA` itère réellement et
  //  déclenche `_sauvegarderConseilIANotifies` (chemin n°6).
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-8 — une écriture conseil_ia_notifies suspendue ne survit pas '
      'au reset', () async {
    await installerEtatAncien(nbCourses: 1);
    // `conseils_filtres_actifs` absent → défaut true, aucun critère → toutes.
    await svc.recalculerCoursesConseilIA(
        <ZtReunion>[reunionAvecCourse('PRIX_CONSEIL_1')]);
    expect(svc.coursesConseilIA, isNotEmpty,
        reason: 'le cache conseil IA doit être peuplé pour ce scénario');

    store.suspendre('conseil_ia_notifies_v1');

    final ecriture = svc.verifierNouvellesCoursesConseilIA(
        <ZtReunion>[reunionAvecCourse('PRIX_CONSEIL_1')]);
    await jusqua(() => store.nbBloquees > 0);
    expect(store.nbBloquees, greaterThan(0),
        reason: 'l\'écriture n°6 doit être suspendue');

    var resetTermine = false;
    final reset = BackupService.instance
        .reinitialiserComplet()
        .whenComplete(() => resetTermine = true);
    await jusqua(() => false, tours: 10);
    expect(resetTermine, isFalse,
        reason: 'le reset doit attendre l\'écriture n°6 (registre unifié)');

    store.relacherTout();
    await ecriture;
    await reset;

    expect(await presente('conseil_ia_notifies_v1'), isFalse,
        reason: 'conseil_ia_notifies_v1 doit rester effacée');
    expect(await presente('conseil_ia_notifies_v1_date'), isFalse,
        reason: 'conseil_ia_notifies_v1_date (R-12) doit rester effacée');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-9 — CONCURRENCE (chemin 8, conseil_ia_resume_date)
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-9 — après reset, conseil_ia_resume_date n\'est jamais '
      'l\'ancienne valeur', () async {
    await installerEtatAncien(nbCourses: 1);
    await svc.recalculerCoursesConseilIA(
        <ZtReunion>[reunionAvecCourse('PRIX_CONSEIL_9')]);

    store.suspendre('conseil_ia_resume_date');

    final ecriture = svc.verifierCoursesConseilIA(
        <ZtReunion>[reunionAvecCourse('PRIX_CONSEIL_9')]);
    await jusqua(() => store.nbBloquees > 0);
    expect(store.nbBloquees, greaterThan(0),
        reason: 'l\'écriture n°8 doit être suspendue');

    var resetTermine = false;
    final reset = BackupService.instance
        .reinitialiserComplet()
        .whenComplete(() => resetTermine = true);
    await jusqua(() => false, tours: 10);
    expect(resetTermine, isFalse,
        reason: 'le reset doit attendre l\'écriture n°8');

    store.relacherTout();
    await ecriture;
    await reset;

    final v = (await p()).getString('conseil_ia_resume_date');
    expect(v, isNot('20200101'),
        reason: 'l\'ancienne date ne doit jamais revenir');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-10 — CONCURRENCE (chemin 2, file native)
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-10 — aucune notification native ne subsiste après le reset',
      () async {
    await installerEtatAncien(nbCourses: 1);

    store.suspendre('hippique_pending_notifs');

    // Déclenche _addAlert → _sendNativeNotification (écriture n°2).
    svc.ajouterAlertNonPartant(
      alertId: 'NON_PARTANT_TEST',
      courseKey: 'R1C1_01012030',
      nomCourse: 'COURSE_TEST',
      hippodrome: 'VINCENNES',
      numsStr: '5',
    );
    await jusqua(() => store.nbBloquees > 0);

    final reset = BackupService.instance.reinitialiserComplet();
    await jusqua(() => false, tours: 10);

    store.relacherTout();
    await reset;

    expect(await presente('flutter.hippique_pending_notifs'), isFalse,
        reason: 'la file native doit rester effacée (R-13)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-11 — Aucune écriture ne s'intercale dans la boucle de suppression
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-11 — aucune écriture ne s\'intercale entre le 1er et le dernier '
      'remove du reset', () async {
    await installerEtatAncien();

    // On suspend la clé 'alert_config_v2' : la boucle de suppression s'y
    // figera DÉTERMINISTIQUEMENT, après avoir déjà journalisé plusieurs REM.
    store.suspendre('alert_config_v2');
    store.journal.clear();

    final reset = BackupService.instance.reinitialiserComplet();
    await jusqua(() => store.journal.any((e) => e.startsWith('REM')), tours: 40);
    expect(store.journal.any((e) => e.startsWith('REM')), isTrue,
        reason: 'la boucle d\'effacement doit avoir commencé');
    expect(store.journal.any((e) => e.startsWith('SET')), isFalse,
        reason: 'aucune écriture ne doit précéder la boucle de suppression');

    // Pendant que la boucle est bloquée, on déclenche — via les chemins de
    // PRODUCTION uniquement — des écritures qui DOIVENT être refusées par la
    // barrière. ⚠️ Aucune écriture directe sur SharedPreferences ici : une
    // telle écriture sortirait par construction de la barrière et rendrait
    // l'assertion suivante auto-contredite.
    await svc.ajouterSuivi(nouvelleCourse('INTERCALE'));
    await svc.ajouterFavoriPourWorker(
      numR: 6,
      numC: 6,
      nomCourse: 'FAVORI_INTERCALE',
      hippodrome: 'VINCENNES',
      scoreIA: 60.0,
    );
    await svc.marquerFavoriCommeParI(6, 6);
    await svc.nettoyerFavorisObsoletes();
    await jusqua(() => false, tours: 8);

    // Vérification EFFECTIVE d'absence d'écriture issue d'AlertService :
    //   1) le registre n'a jamais reçu d'écriture pendant la barrière ;
    //   2) aucune alerte n'a été émise (donc `_addAlert` est neutralisé) ;
    //   3) les deux paris refusés ne sont pas en RAM.
    expect(svc.nbEcrituresEnCours, 0,
        reason: 'aucune écriture d\'AlertService ne doit être engagée '
            'pendant la barrière');
    expect(svc.alerts, isEmpty,
        reason: 'aucune alerte ne doit être émise pendant la barrière');
    expect(svc.trackedCourses, isEmpty,
        reason: 'aucun pari fantôme ne doit rester en RAM');
    final journalPendantBarriere = List<String>.from(store.journal);
    expect(journalPendantBarriere.any((e) => e.startsWith('SET')), isFalse,
        reason: 'aucune écriture issue d\'AlertService ne doit s\'intercaler '
            'dans la boucle de suppression : $journalPendantBarriere');

    store.relacher('alert_config_v2');
    await reset;

    final indexPremierRemove = store.journal.indexWhere((e) => e.startsWith('REM'));
    expect(indexPremierRemove, greaterThanOrEqualTo(0));
    final apres = store.journal.sublist(indexPremierRemove);
    // Le dernier REM est l'effacement légitime ; aucun SET ne doit s'y mêler.
    expect(apres.any((e) => e.startsWith('SET')), isFalse,
        reason: 'aucune écriture ne doit avoir lieu pendant la boucle '
            'de suppression : $apres');

    // Et les clés refusées restent effacées.
    expect(await presente('tracked_courses_v1'), isFalse);
    expect(await presente('hippique_favorites_v1'), isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-12 — Atomicité des 2 écritures de _resetConseilIANotifiesIfNewDay
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-12 — les 2 écritures de _resetConseilIANotifiesIfNewDay sont '
      'atomiques face au reset', () async {
    await installerEtatAncien(nbCourses: 1);
    expect((await p()).getString('conseil_ia_notifies_v1_date'), '20200101');
    await svc.recalculerCoursesConseilIA(
        <ZtReunion>[reunionAvecCourse('PRIX_ATOMIQUE')]);

    store.suspendre('conseil_ia_notifies_v1_date');

    final ecriture = svc.verifierCoursesConseilIA(
        <ZtReunion>[reunionAvecCourse('PRIX_ATOMIQUE')]);
    await jusqua(() => store.nbBloquees > 0);
    expect(store.nbBloquees, greaterThan(0));

    final reset = BackupService.instance.reinitialiserComplet();
    await jusqua(() => false, tours: 10);

    store.relacherTout();
    await ecriture;
    await reset;

    // Jamais une seule des deux clés.
    final d = await presente('conseil_ia_notifies_v1_date');
    final l = await presente('conseil_ia_notifies_v1');
    expect(d, isFalse,
        reason: 'R-12 : la date ne doit pas subsister après le reset');
    expect(l, isFalse, reason: 'la liste ne doit pas subsister');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-13 — L'instantané S1 est capturé depuis le cache d'entrée
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-13 — les courses déjà connues au reset ne produisent aucune '
      'alerte au premier passage (S1)', () async {
    await installerEtatAncien(nbCourses: 1);
    await svc.recalculerCoursesConseilIA(<ZtReunion>[
      reunionAvecCourse('PRIX_CONNU_1', numCourse: 1),
      reunionAvecCourse('PRIX_CONNU_2', numCourse: 2),
    ]);
    expect(svc.coursesConseilIA.length, 2);

    await BackupService.instance.reinitialiserComplet();

    // Le cache RAM survit au reset (il est recalculé par le refresh suivant) :
    // on rejoue exactement les mêmes courses, comme le ferait le refresh.
    await svc.recalculerCoursesConseilIA(<ZtReunion>[
      reunionAvecCourse('PRIX_CONNU_1', numCourse: 1),
      reunionAvecCourse('PRIX_CONNU_2', numCourse: 2),
    ]);
    await svc.verifierNouvellesCoursesConseilIA(<ZtReunion>[]);
    await jusqua(() => svc.nbEcrituresEnCours == 0);

    final alertesIA =
        svc.alerts.where((a) => a.type == AlertType.conseilIA).toList();
    expect(alertesIA, isEmpty,
        reason: 'les 2 courses déjà connues doivent être tues (S1)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-14 — Une course réellement nouvelle est bien notifiée
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-14 — une course réellement nouvelle est notifiée après le reset',
      () async {
    await installerEtatAncien(nbCourses: 1);
    await svc.recalculerCoursesConseilIA(<ZtReunion>[
      reunionAvecCourse('PRIX_CONNU_1', numCourse: 1),
    ]);

    await BackupService.instance.reinitialiserComplet();

    // Mêmes 2 courses connues + 1 réellement nouvelle.
    await svc.recalculerCoursesConseilIA(<ZtReunion>[
      reunionAvecCourse('PRIX_CONNU_1', numCourse: 1),
      reunionAvecCourse('PRIX_NEUVE_3', numCourse: 3),
    ]);
    await svc.verifierNouvellesCoursesConseilIA(<ZtReunion>[]);
    await jusqua(() => svc.nbEcrituresEnCours == 0);

    final alertesIA =
        svc.alerts.where((a) => a.type == AlertType.conseilIA).toList();
    expect(alertesIA.length, 1,
        reason: 'seule la course nouvelle doit être notifiée');
    expect(alertesIA.single.message, contains('PRIX_NEUVE_3'));
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-15 — L'instantané est consommé une seule fois par clé
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-15 — l\'instantané est consommé une seule fois (pas de re-rafale)',
      () async {
    await installerEtatAncien(nbCourses: 1);
    await svc.recalculerCoursesConseilIA(<ZtReunion>[
      reunionAvecCourse('PRIX_CONNU_1', numCourse: 1),
    ]);

    await BackupService.instance.reinitialiserComplet();
    await svc.recalculerCoursesConseilIA(<ZtReunion>[
      reunionAvecCourse('PRIX_CONNU_1', numCourse: 1),
    ]);

    await svc.verifierNouvellesCoursesConseilIA(<ZtReunion>[]);
    await jusqua(() => svc.nbEcrituresEnCours == 0);
    final apres1 = svc.alerts.where((a) => a.type == AlertType.conseilIA).length;
    expect(apres1, 0);

    // 2e passage : la clé est dans `_conseilIANotifies`, plus dans l'instantané.
    await svc.verifierNouvellesCoursesConseilIA(<ZtReunion>[]);
    await jusqua(() => svc.nbEcrituresEnCours == 0);
    final apres2 = svc.alerts.where((a) => a.type == AlertType.conseilIA).length;
    expect(apres2, 0, reason: 'aucune re-rafale au 2e passage');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-16 — Non-régression : reinitialiserIA / reinitialiserParis
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-16 — reinitialiserIA() et reinitialiserParis() préservent '
      'AlertService', () async {
    await installerEtatAncien();
    final nbAvant = svc.alerts.length;
    expect(nbAvant, greaterThan(0));

    await BackupService.instance.reinitialiserIA();
    expect(svc.alerts.length, nbAvant,
        reason: 'reinitialiserIA ne doit PAS vider AlertService');
    expect(await presente('tracked_courses_v1'), isTrue,
        reason: 'reinitialiserIA ne doit PAS toucher tracked_courses_v1');

    await BackupService.instance.reinitialiserParis();
    expect(await presente('alert_history_v1'), isTrue,
        reason: 'reinitialiserParis ne doit PAS toucher alert_history_v1');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-17 — R-12 + R-13 via reinitialiserAlertes()
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-17 — reinitialiserAlertes() efface R-12 et R-13', () async {
    await installerEtatAncien();
    expect(await presente('conseil_ia_notifies_v1_date'), isTrue);
    expect(await presente('flutter.hippique_pending_notifs'), isTrue);

    await BackupService.instance.reinitialiserAlertes();

    expect(await presente('conseil_ia_notifies_v1_date'), isFalse,
        reason: 'R-12 : la date marqueur doit être effacée');
    expect(await presente('flutter.hippique_pending_notifs'), isFalse,
        reason: 'R-13 : la file native doit être effacée');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  V24-18 — Le registre est correctement vidé après chaque écriture
  // ═══════════════════════════════════════════════════════════════════════
  test('V24-18 — le registre ne conserve aucune écriture terminée', () async {
    await installerEtatAncien(nbCourses: 1);

    // ⚠️ Un passage transitoire à 0 n'est PAS la preuve que tout est terminé :
    //    `_addAlert` appelle `_sendNativeNotification()` SANS `await`
    //    (alert_service.dart:837). Entre la fin de `_save()` et l'enregistrement
    //    de la file native, le registre vaut légitimement 0. Une synchronisation
    //    sur `nbEcrituresEnCours == 0` sortirait donc trop tôt.
    //    → Synchronisation sur le JOURNAL : on attend explicitement le `SET`
    //      de la file native, dernière écriture du cycle.
    expect(svc.nbEcrituresEnCours, 0,
        reason: 'registre vide avant toute écriture');
    store.journal.clear();

    await svc.ajouterSuivi(nouvelleCourse('REGISTRE'));

    // Attente déterministe de la DERNIÈRE écriture du cycle : la file native.
    await jusqua(
      () => store.journal.contains('SET flutter.flutter.hippique_pending_notifs'),
      tours: 80,
    );
    expect(
      store.journal.contains('SET flutter.flutter.hippique_pending_notifs'),
      isTrue,
      reason: 'la file native doit avoir été écrite (dernière écriture du cycle)',
    );

    // Maintenant seulement, le registre doit s'être vidé — `whenComplete` du
    // dernier `_executerEcriture` s'exécute en microtâche APRÈS la complétion.
    await jusqua(() => svc.nbEcrituresEnCours == 0, tours: 40);
    expect(svc.nbEcrituresEnCours, 0,
        reason: 'le registre doit être vidé après la fin de l\'écriture');
    expect(svc.derniereErreurEcriture, isNull,
        reason: 'aucune écriture ne doit avoir échoué');
    expect(await presente('tracked_courses_v1'), isTrue);
    expect(store.journal.contains('SET flutter.tracked_courses_v1'), isTrue,
        reason: 'toutes les écritures du cycle doivent être passées');
  });
}
