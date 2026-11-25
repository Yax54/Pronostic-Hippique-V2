// ═══════════════════════════════════════════════════════════════════════════
//  B5c — R-DR-01-c — BARRIÈRE DE RESET DU CYCLE DE RAFRAÎCHISSEMENT
//
//  OBJET : garantir qu'après une réinitialisation complète, AUCUN
//  rafraîchissement commencé avant ou pendant celle-ci ne puisse réintroduire
//  d'anciennes réunions, d'anciens caches, ni relancer d'effets secondaires.
//
//  Tous les scénarios passent par le VRAI chemin de production
//  (`DataRefreshService.refresh()` → `ZoneTurfService.chargerProgramme()` →
//  parseur réel) avec un réseau PMU simulé par `runWithClient` + `MockClient`.
//
//  PÉRIMÈTRE : R-DR-01-c uniquement. Ne touche ni aux calculs IA, ni aux
//  poids, ni aux seuils, ni au TOP3.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ── Store contrôlable avec suspensions et échecs ciblés ────────────────────
class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  /// Clés dont `setValue` doit ÉCHOUER (retourner `false`).
  final Set<String> clesEnEchecSet = <String>{};

  // Suspension de `setValue` sur une clé donnée.
  String? _cleSuspendue;
  Completer<void>? _entreeSet;
  Completer<void>? _verrouSet;

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
    // Suspension optionnelle d'une LECTURE préfs. Elle sert à retenir un
    // chemin du service qui n'écrit pas (donc absent de tout registre de
    // drainage) : `IaMemoryService._load()` et les `getInstance()` internes.
    final entree = _entreeGetAll;
    if (entree != null) {
      _entreeGetAll = null;
      nbSuspensionsGetAll++;
      final verrou = _verrouGetAll;
      if (!entree.isCompleted) entree.complete();
      if (verrou != null) await verrou.future;
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
    if (clesEnEchecSet.contains(key)) return false;
    if (_cleSuspendue != null && key == _cleSuspendue) {
      final entree = _entreeSet;
      _entreeSet = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      await _verrouSet!.future;
    }
    _valeurs[key] = value;
    return true;
  }

  /// Suspend le prochain `setValue` sur [cle] (nom SANS préfixe `flutter.`).
  Completer<void> armerSuspensionSet(String cle) {
    final entree = Completer<void>();
    _entreeSet = entree;
    _verrouSet = Completer<void>();
    _cleSuspendue = 'flutter.$cle';
    return entree;
  }

  void libererSet() {
    final v = _verrouSet;
    _verrouSet = null;
    _cleSuspendue = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  // Suspension de la PROCHAINE lecture préfs et compteur d'activations.
  Completer<void>? _entreeGetAll;
  Completer<void>? _verrouGetAll;

  /// Nombre de fois où la suspension de lecture a réellement été activée.
  int nbSuspensionsGetAll = 0;

  /// Suspend la prochaine lecture préfs. Renvoie le `Completer` qui sera
  /// complété quand la lecture sera atteinte (sert de témoin de couverture).
  Completer<void> armerSuspensionGetAll() {
    final entree = Completer<void>();
    _entreeGetAll = entree;
    _verrouGetAll = Completer<void>();
    return entree;
  }

  void libererGetAll() {
    final v = _verrouGetAll;
    _verrouGetAll = null;
    _entreeGetAll = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  List<String> clesCache() => _valeurs.keys
      .where((k) => k.startsWith('flutter.cache_reunions_'))
      .map((k) => k.replaceFirst('flutter.', ''))
      .toList()
    ..sort();
}

// ignore: library_private_types_in_public_api
late _Store store;

Future<void> _laisserProgresser([int tours = 60]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<bool> _attendreQue(bool Function() c, [int max = 3000]) async {
  for (var i = 0; i < max; i++) {
    if (c()) return true;
    await Future<void>.delayed(Duration.zero);
  }
  return c();
}

String get _dateDuJour {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

String get kCache => 'cache_reunions_$_dateDuJour';
String get kTs => '${kCache}_ts';

int _nbAlertesNonPartant() =>
    AlertService.instance.alerts.where((a) => a.titre.contains('Non-partant')).length;

// ── Scénario mutable : réunion / partants modifiables entre deux appels ────
class _Scenario {
  String lieu;
  List<int> nums;

  /// Si non nul, le chargement du PROGRAMME est suspendu sur ce verrou.
  Completer<void>? verrouProgramme;
  Completer<void>? entreeProgramme;

  _Scenario({
    this.lieu = 'VINCENNES',
    required this.nums,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  ★ CORRECTIF HORAIRE — cohérence `dateStr` / `heure` du départ fictif
//
//  CONTRAT DE PRODUCTION (non modifiable ici) : `ZoneTurfService` assemble
//  `ZtCourse.heure` et `ZtCourse.dateStr` depuis DEUX sources distinctes :
//    • `dateStr` = jour de la REQUÊTE, `_todayStr()` (zone_turf_service.dart:46,
//      :980-983) → c'est le jour du chemin d'URL `.../programme/<ddMMyyyy>` ;
//    • `heure`   = heure LOCALE du timestamp `heureDepart` (l.148-152).
//  `ZtCourse.heureDateTime` recolle ensuite les deux : `DateTime(<jour de
//  dateStr>, <h>, <m>)` (zt_models.dart:845-847).
//
//  DÉFAUT CORRIGÉ : le mock datait le départ à `DateTime.now() + 3 h`. Dès que
//  cette somme franchit minuit (donc dès 21h00 locale), l'HEURE appartient au
//  lendemain mais le JOUR reste celui de `dateStr` ⇒ `heureDateTime` recule au
//  lieu d'avancer :
//      `diffMin = heureDateTime.difference(now)` devient très NÉGATIF,
//      `_detecterNonPartants` sort de sa fenêtre utile
//      (`diffMin < -30 || diffMin > 240`, data_refresh_service.dart:503-505)
//      et fait `continue` : la course n'est plus examinée du tout, donc
//      `reAnalyserCourse` n'est jamais appelé et AUCUNE écriture IA
//      (`_save()` → `ia_poids_v3`, ia_memory_service.dart:2152/2167) n'a lieu.
//  Mesuré : 65 880 échecs sur 527 040 instants (12,50 %), heures locales 21-23.
//  C'est exactement ce que R01c-H mesure via son TÉMOIN 2.
//
//  POURQUOI PAS SEULEMENT « PLAFONNER À 23h59 » : le jour du mock et le
//  `dateStr` de production viennent de DEUX `DateTime.now()` distincts (l'un
//  dans `_doRefresh`, l'autre dans le mock, séparés par l'appel réseau). Près
//  de minuit, ces deux lectures peuvent tomber de part et d'autre du passage
//  de jour → le mock daterait le départ d'un jour et la production le
//  recollerait au jour précédent. Le plafonnement seul réduirait la fenêtre
//  d'échec sans supprimer la course temporelle.
//
//  SOLUTION RETENUE — le jour N'EST PLUS DEVINÉ, IL EST LU DANS L'URL :
//  `_jourDemande()` extrait le `ddMMyyyy` du chemin réellement demandé, qui EST
//  le `dateStr` que la production va utiliser. La cohérence jour/heure devient
//  vraie PAR CONSTRUCTION et non par coïncidence d'horloge.
// ═══════════════════════════════════════════════════════════════════════════

/// Jour civil porté par l'URL réellement demandée (`.../programme/<ddMMyyyy>`).
/// C'est exactement le `dateStr` que `ZoneTurfService` recollera à l'heure du
/// timestamp (zone_turf_service.dart:46 puis :148).
DateTime _jourDemande(Uri url) {
  final segs = url.pathSegments;
  final i = segs.indexOf('programme');
  if (i >= 0 && i + 1 < segs.length) {
    final s = segs[i + 1];
    if (s.length == 8) {
      final d = int.tryParse(s.substring(0, 2));
      final m = int.tryParse(s.substring(2, 4));
      final y = int.tryParse(s.substring(4, 8));
      if (d != null && m != null && y != null) return DateTime(y, m, d);
    }
  }
  // Repli : jour courant (comportement antérieur) — jamais atteint tant que
  // l'URL garde la forme `.../programme/<ddMMyyyy>`, ce que la production
  // garantit (zone_turf_service.dart:64-65).
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Dernier instant « sûr » de [jour] : 23h59, ou l'heure la plus tardive qui
/// retombe bien sur le MÊME jour civil. La boucle couvre les rares fuseaux
/// dont la transition DST tombe à minuit et rend 23h59 inexistant (Dart
/// normaliserait alors vers le jour suivant, ce qui casserait l'ancrage).
DateTime _finDeJour(DateTime jour) {
  for (var h = 23; h >= 12; h--) {
    final t = DateTime(jour.year, jour.month, jour.day, h, 59);
    if (t.year == jour.year && t.month == jour.month && t.day == jour.day) {
      return t;
    }
  }
  return DateTime(jour.year, jour.month, jour.day, 12, 0);
}

/// Départ fictif « proche », TOUJOURS cohérent avec le contrat `dateStr`+`heure`.
/// Garantit `heureDateTime.difference(now).inMinutes ∈ [0, 180]` :
///   • `now + 3 h` tant que cette somme reste dans le jour demandé (⇒ +180 min) ;
///   • sinon écrêtage à `_finDeJour(jour)` (⇒ 0…180 min, jamais de minuit
///     franchi, donc jamais de `heureDateTime` dans le passé).
DateTime _departFictif(Uri url) {
  final now = DateTime.now();
  final jour = _jourDemande(url); // jour du dateStr de production
  final plus3 = now.add(const Duration(hours: 3));
  if (plus3.year == jour.year &&
      plus3.month == jour.month &&
      plus3.day == jour.day) {
    return plus3;
  }
  return _finDeJour(jour);
}

String _programme({
  required String lieu,
  required int numOfficiel,
  required Uri url,
}) {
  final depart = _departFictif(url).millisecondsSinceEpoch;
  assert(() {
    // L'ancrage doit survivre à l'aller-retour epoch → local que fait la
    // production (`DateTime.fromMillisecondsSinceEpoch(ts).toLocal()`, l.149).
    final relu = DateTime.fromMillisecondsSinceEpoch(depart).toLocal();
    final jour = _jourDemande(url);
    return relu.year == jour.year &&
        relu.month == jour.month &&
        relu.day == jour.day;
  }(), 'départ fictif hors du jour civil du dateStr demandé');
  return jsonEncode({
    'programme': {
      'reunions': [
        {
          'numOfficiel': numOfficiel,
          'hippodrome': {'libelleLong': '$lieu (FRANCE)', 'libelleCourt': lieu},
          'courses': [
            {
              'numOrdre': 1,
              'libelle': 'PRIX R01-c',
              'discipline': 'ATTELE',
              'distance': 2100,
              'montantPrix': 30000,
              'paris': <Map<String, dynamic>>[],
              'heureDepart': depart,
            },
          ],
        },
      ],
    },
  });
}

String _participants(List<int> nums) => jsonEncode({
      'participants': [
        for (final n in nums)
          {
            'numPmu': n,
            'nom': 'CHEVAL_$n',
            'statut': 'PARTANT',
            'age': 5,
            'sexe': 'M',
          },
      ],
    });

/// Exécute [action] avec un réseau PMU simulé suivant [s].
///
/// [urls] reçoit chaque URL réellement demandée : c'est la preuve que le
/// parseur de production a tourné et que le réseau a été sollicité.
Future<T> _avecScenario<T>(
  Future<T> Function() action,
  _Scenario s, {
  List<Uri>? urls,
}) {
  final client = MockClient((request) async {
    urls?.add(request.url);
    if (request.url.path.contains('participants')) {
      return http.Response(_participants(s.nums), 200,
          headers: {'content-type': 'application/json'});
    }
    // Suspension optionnelle sur le chargement du PROGRAMME.
    final verrou = s.verrouProgramme;
    if (verrou != null) {
      final entree = s.entreeProgramme;
      s.entreeProgramme = null;
      s.verrouProgramme = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      await verrou.future;
    }
    return http.Response(
        _programme(lieu: s.lieu, numOfficiel: 1, url: request.url),
        200,
        headers: {'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    // Hygiène de test : caches STATIQUES et SINGLETON partagés entre tests du
    // même processus. Ce n'est pas la purge de production mesurée ici.
    ZoneTurfService.viderCachePourResetComplet();
    DataRefreshService.instance.viderMemoirePourResetComplet();
  });

  tearDown(() {
    store.libererSet();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A — RESET PENDANT LE CHARGEMENT RÉSEAU
  //
  //  C'est le scénario central de cette correction. Avant R01-c, le
  //  rafraîchissement REPRENAIT après le reset : `_reunions = reunions`
  //  (l.520) repeuplait la RAM vidée par R01-b et `_sauvegarderCacheLocal`
  //  recréait les clés supprimées par R01-a.
  // ═══════════════════════════════════════════════════════════════════════
  test('R01c-A — reset pendant le chargement réseau : rien ne ressuscite',
      () async {
    final s = _Scenario(lieu: 'ANCIENNE-VILLE', nums: [1, 2, 3]);
    final verrou = Completer<void>();
    s.verrouProgramme = verrou;
    s.entreeProgramme = Completer<void>();
    final urls = <Uri>[];

    // Le rafraîchissement est ENGAGÉ et suspendu dans le chargement réseau.
    final refresh = _avecScenario(
        () => DataRefreshService.instance.refresh(), s, urls: urls);

    final suspendu = await _attendreQue(
        () => urls.any((u) => u.path.contains('/programme/')));
    expect(suspendu, isTrue,
        reason: 'GARDE DE PRÉCONDITION : la requête programme est partie — le '
            'rafraîchissement est bien EN VOL');
    expect(DataRefreshService.instance.reunions, isEmpty,
        reason: 'TÉMOIN : la RAM est encore vide, la réponse n\'est pas arrivée');

    // Reset complet PENDANT le chargement.
    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();
    debugPrint('R01c-A après reset : cles=${store.clesCache()} '
        'generation=${DataRefreshService.instance.generationCache}');

    expect(store.clesCache(), isEmpty,
        reason: 'TÉMOIN : R01-a a bien effacé les clés de cache');

    // Libération : la réponse réseau arrive APRÈS le reset.
    verrou.complete();
    await refresh;
    await _laisserProgresser(200);

    debugPrint('R01c-A après reprise : '
        'RAM=${DataRefreshService.instance.reunions.length} '
        'cles=${store.clesCache()} '
        'lastRefresh=${DataRefreshService.instance.lastRefresh} '
        'lastError=${DataRefreshService.instance.lastError}');

    // ── ASSERTIONS DISCRIMINANTES ─────────────────────────────────────────
    expect(DataRefreshService.instance.reunions, isEmpty,
        reason: 'CORRECTION R01-c : la reprise APRÈS le reset ne réécrit plus '
            '`_reunions`. Avant, la ligne `_reunions = reunions` repeuplait la '
            'RAM que R-DR-01-b venait de vider — le reset était annulé');
    expect(DataRefreshService.instance.reunions
        .any((r) => r.lieu == 'ANCIENNE-VILLE'), isFalse,
        reason: 'CORRECTION R01-c : la réunion d\'avant le reset n\'est servie '
            'sous aucune forme');
    expect(store.clesCache(), isEmpty,
        reason: 'CORRECTION R01-c : AUCUNE clé de cache n\'est recréée après '
            'le reset. Avant, `_sauvegarderCacheLocal` (l.531, appelée en '
            '`.ignore()`) reconstituait la paire JSON + `_ts`');
    expect(DataRefreshService.instance.lastRefresh, isNull,
        reason: 'CORRECTION R01-c : `_lastRefresh` n\'est pas réécrit par une '
            'reprise obsolète');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B — RESET ENTRE LES DEUX ÉCRITURES DU CACHE
  //
  //  V31b R01-K démontrait le défaut : `_ts` orpheline après un reset
  //  pourtant terminé. L'ordre d'écriture inversé (`_ts` d'abord) et le
  //  contrôle entre les deux écritures le suppriment.
  // ═══════════════════════════════════════════════════════════════════════
  test('R01c-B — reset entre les deux écritures : aucune clé orpheline',
      () async {
    final s = _Scenario(nums: [1, 2]);
    // On suspend l'écriture du JSON : le `_ts` est déjà posé.
    store.armerSuspensionSet(kCache);
    final marque = store.journal.length;

    final refresh = _avecScenario(
        () => DataRefreshService.instance.refresh(), s);

    final suspendu = await _attendreQue(
        () => store.journal.contains('SET flutter.$kCache'));
    expect(suspendu, isTrue,
        reason: 'GARDE DE PRÉCONDITION : l\'écriture du JSON est suspendue — '
            'le `_ts` a donc déjà été écrit');

    expect(store.contient(kTs), isTrue,
        reason: 'FAIT : la clé `_ts` est posée AVANT le JSON (ordre inversé)');
    expect(store.contient(kCache), isFalse,
        reason: 'FAIT : le JSON n\'est pas encore écrit');

    // ── Reset PENDANT cette fenêtre ───────────────────────────────────────
    //  Il est lancé SANS être attendu : son drain attend précisément cette
    //  écriture suspendue, c'est le comportement voulu. L'attendre ici
    //  produirait un interblocage du TEST (pas de la production).
    final reset = BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    // TÉMOIN : le drain retient bien le reset — la barrière est fermée.
    expect(DataRefreshService.instance.resetEnCours, isTrue,
        reason: 'TÉMOIN : le reset est bloqué dans le drain, sur l\'écriture '
            'du cache — c\'est la preuve que le registre la VOIT');

    // Libération de l'écriture : elle se termine, le drain peut conclure.
    store.libererSet();
    await refresh;
    await reset;
    await _laisserProgresser(200);

    final finales = store.clesCache();
    final journal = store.journal.sublist(marque);
    debugPrint('R01c-B final : cles=$finales');

    expect(finales, isEmpty,
        reason: 'CORRECTION R01-c : après un reset terminé, AUCUNE clé du cache '
            'ne survit — ni le JSON, ni la `_ts`. Le drain garantit que '
            'l\'écriture est TERMINÉE avant le balayage de R01-a, qui la voit '
            'donc et la supprime');
    expect(store.contient(kTs), isFalse,
        reason: 'CORRECTION R01-c : la clé d\'horodatage orpheline est éliminée '
            '— défaut mesuré V31b R01-K, désormais impossible');
    expect(DataRefreshService.instance.reunions, isEmpty,
        reason: 'CORRECTION R01-c : la RAM non plus n\'a pas été repeuplée — '
            'le vidage du `finally` est postérieur au drain');

    // Le retrait explicite de la `_ts` a bien eu lieu (trace d\'exécution).
    expect(journal, contains('REM flutter.$kTs'),
        reason: 'CORRECTION R01-c : la clé `_ts` laissée par l\'interruption a '
            'été explicitement retirée par le contrôle entre les deux '
            'écritures, sans attendre le balayage');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  C — ÉCHEC DE L'ÉCRITURE DU JSON : pas de `_ts` orphelin
  // ═══════════════════════════════════════════════════════════════════════
  test('R01c-C — échec de setString : le _ts est retiré, aucune clé partielle',
      () async {
    final s = _Scenario(nums: [1, 2]);
    store.clesEnEchecSet.add('flutter.$kCache');

    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _laisserProgresser(200);

    debugPrint('R01c-C : cache=${store.contient(kCache)} '
        'ts=${store.contient(kTs)} '
        'erreur=${DataRefreshService.instance.derniereErreurCache}');

    expect(store.contient(kCache), isFalse,
        reason: 'FAIT : l\'écriture du JSON a été refusée par le stockage');
    expect(store.contient(kTs), isFalse,
        reason: 'CORRECTION R01-c : le `_ts` déjà posé est RETIRÉ quand le JSON '
            'échoue. Avant, la paire restait désynchronisée : une clé '
            'd\'horodatage sans contenu');
    expect(DataRefreshService.instance.derniereErreurCache, isNotNull,
        reason: 'CORRECTION R01-c : l\'échec n\'est plus SILENCIEUX — le retour '
            'de `setString` est contrôlé et mémorisé');
    expect(DataRefreshService.instance.reunions.length, 1,
        reason: 'NON-RÉGRESSION : l\'échec d\'écriture n\'empêche pas le '
            'rafraîchissement légitime de servir les données en RAM');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D — ÉCHEC DE L'ÉCRITURE DE L'HORODATAGE : le JSON n'est pas écrit
  // ═══════════════════════════════════════════════════════════════════════
  test('R01c-D — échec de setInt : le JSON n\'est pas écrit', () async {
    final s = _Scenario(nums: [1, 2]);
    store.clesEnEchecSet.add('flutter.$kTs');

    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _laisserProgresser(200);

    debugPrint('R01c-D : cache=${store.contient(kCache)} '
        'ts=${store.contient(kTs)} '
        'erreur=${DataRefreshService.instance.derniereErreurCache}');

    expect(store.contient(kTs), isFalse, reason: 'FAIT : setInt a été refusé');
    expect(store.contient(kCache), isFalse,
        reason: 'CORRECTION R01-c : le JSON n\'est PAS écrit quand '
            'l\'horodatage a échoué. Sans cela on créerait un JSON relu SANS '
            'contrôle de péremption (`timestampMs == null` → `_lastRefresh = '
            'null`, l.350-352)');
    expect(DataRefreshService.instance.derniereErreurCache, isNotNull,
        reason: 'CORRECTION R01-c : l\'échec est contrôlé et mémorisé');
    expect(store.clesCache(), isEmpty,
        reason: 'CORRECTION R01-c : aucune clé partielle n\'est laissée');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  E — AUCUN EFFET SECONDAIRE OBSOLÈTE
  // ═══════════════════════════════════════════════════════════════════════
  test('R01c-E — reset pendant le chargement : aucun pronostic ni alerte '
      'obsolète', () async {
    final s = _Scenario(lieu: 'OBSOLETE', nums: [1, 2, 3]);
    final verrou = Completer<void>();
    s.verrouProgramme = verrou;
    s.entreeProgramme = Completer<void>();
    final urls = <Uri>[];
    final pronosticsAvant = IaMemoryService.instance.pronostics.length;
    final alertesAvant = AlertService.instance.alerts.length;

    final refresh = _avecScenario(
        () => DataRefreshService.instance.refresh(), s, urls: urls);
    await _attendreQue(() => urls.any((u) => u.path.contains('/programme/')));

    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    verrou.complete();
    await refresh;
    await _laisserProgresser(300);

    debugPrint('R01c-E : pronostics=${IaMemoryService.instance.pronostics.length} '
        '(avant reset=$pronosticsAvant) '
        'alertes=${AlertService.instance.alerts.length} '
        '(avant=$alertesAvant) RAM=${DataRefreshService.instance.reunions.length}');

    expect(IaMemoryService.instance.pronostics.length, 0,
        reason: 'CORRECTION R01-c : aucun pronostic n\'est créé par un '
            'rafraîchissement obsolète. La microtâche `_enregistrerPronosticsAuto` '
            'est refusée AVANT le calcul, en plus du rejet à l\'engagement de '
            'R-DR-02 qui reste en place');
    expect(AlertService.instance.alerts.length, 0,
        reason: 'CORRECTION R01-c : aucune alerte n\'est déposée par le '
            'rafraîchissement obsolète (non-partants, conseils IA)');
    expect(_nbAlertesNonPartant(), 0,
        reason: 'CORRECTION R01-c : notamment aucun non-partant fantôme');
    expect(DataRefreshService.instance.reunions, isEmpty,
        reason: 'CORRECTION R01-c : la RAM reste vide');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  F — NON-RÉGRESSION : un rafraîchissement LÉGITIME après reset fonctionne
  // ═══════════════════════════════════════════════════════════════════════
  test('R01c-F — le rafraîchissement APRÈS le reset fonctionne normalement',
      () async {
    // 1. Un rafraîchissement, puis un reset.
    final s1 = _Scenario(lieu: 'AVANT', nums: [1, 2]);
    await _avecScenario(() => DataRefreshService.instance.refresh(), s1);
    await _attendreQue(() => store.contient(kTs));

    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();
    expect(DataRefreshService.instance.reunions, isEmpty, reason: 'TÉMOIN');
    expect(store.clesCache(), isEmpty, reason: 'TÉMOIN');

    // 2. Un rafraîchissement LÉGITIME, APRÈS le reset.
    final s2 = _Scenario(lieu: 'APRES', nums: [5, 6, 7]);
    final urls = <Uri>[];
    await _avecScenario(() => DataRefreshService.instance.refresh(), s2,
        urls: urls);
    await _attendreQue(() => store.contient(kTs));
    await _laisserProgresser(200);

    debugPrint('R01c-F : RAM=${DataRefreshService.instance.reunions.length} '
        'lieu=${DataRefreshService.instance.reunions.isNotEmpty ? DataRefreshService.instance.reunions.first.lieu : "-"} '
        'cles=${store.clesCache()} '
        'appelsRéseau=${urls.length} '
        'lastRefresh=${DataRefreshService.instance.lastRefresh} '
        'erreurCache=${DataRefreshService.instance.derniereErreurCache}');

    // ── La barrière NE DOIT PAS geler le service après le reset ────────────
    expect(DataRefreshService.instance.reunions.length, 1,
        reason: 'NON-RÉGRESSION : la barrière est ROUVERTE — un '
            'rafraîchissement postérieur au reset est accepté');
    expect(DataRefreshService.instance.reunions.first.lieu, 'APRES',
        reason: 'NON-RÉGRESSION : ce sont bien les données FRAÎCHES qui sont '
            'servies, et pas l\'état antérieur au reset');
    expect(store.clesCache(), containsAll(<String>[kCache, kTs]),
        reason: 'NON-RÉGRESSION : la paire de cache est réécrite normalement '
            'après le reset — la protection ne bloque pas les écritures '
            'légitimes');
    expect(DataRefreshService.instance.derniereErreurCache, isNull,
        reason: 'NON-RÉGRESSION : aucune erreur d\'écriture enregistrée');
    expect(DataRefreshService.instance.lastRefresh, isNotNull,
        reason: 'NON-RÉGRESSION : `_lastRefresh` est renseigné par le '
            'rafraîchissement légitime');
    expect(DataRefreshService.instance.lastError, isNull,
        reason: 'NON-RÉGRESSION : aucune erreur remontée');
    expect(DataRefreshService.instance.resetEnCours, isFalse,
        reason: 'NON-RÉGRESSION : la barrière temporelle est bien rouverte');
  });

  test('R01c-G — un refresh né pendant le reset ne démarre rien', () async {
    final s = _Scenario(lieu: 'PENDANT', nums: [1, 2]);

    // Pour que la barrière reste fermée de façon DÉTERMINISTE, on retient le
    // reset dans son drain : le premier refresh est suspendu sur l'écriture du
    // JSON du cache. Sans cela, le reset se termine en quelques microtâches et
    // la fenêtre « pendant le reset » ne serait pas observable.
    store.armerSuspensionSet(kCache);
    final premier = _avecScenario(
        () => DataRefreshService.instance.refresh(), s);
    await _attendreQue(() => store.journal.contains('SET flutter.$kCache'));

    final reset = BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    expect(DataRefreshService.instance.resetEnCours, isTrue,
        reason: 'GARDE DE PRÉCONDITION : la barrière est fermée pendant le '
            'reset — sinon ce scénario ne prouve rien');

    // Tentative de refresh PENDANT le reset : doit être refusée net.
    final urls = <Uri>[];
    await _avecScenario(
        () => DataRefreshService.instance.refresh(), s, urls: urls);
    await _laisserProgresser();

    debugPrint('R01c-G : appelsRéseauPendantReset=${urls.length} '
        'RAM=${DataRefreshService.instance.reunions.length}');

    expect(urls, isEmpty,
        reason: 'CORRECTION R01-c : un rafraîchissement né pendant le reset est '
            'REFUSÉ AVANT tout appel réseau — `_resetEnCours` est contrôlé avant '
            'la pose de `_loading` et avant `chargerProgramme()`');
    //  ⚠️ On n'assert PAS `reunions.isEmpty` ICI : le PREMIER refresh a déjà
    //  exécuté `_reunions = reunions` avant d'être suspendu sur l'écriture du
    //  cache — sa génération était encore valide à cet instant, c'est
    //  légitime. Ce qui compte est l'état À LA FIN du reset, vérifié plus bas.

    // Libération : l'écriture se termine, le drain et le reset concluent.
    store.libererSet();
    await premier;
    await reset;
    await _laisserProgresser(50);

    debugPrint('R01c-G final : RAM=${DataRefreshService.instance.reunions.length} '
        'cles=${store.clesCache()}');

    expect(DataRefreshService.instance.reunions, isEmpty,
        reason: 'CORRECTION R01-c : le reset se termine sur une RAM vide, et le '
            'premier refresh — pourtant parti AVANT — n\'a rien réintroduit');
    expect(store.clesCache(), isEmpty,
        reason: 'CORRECTION R01-c : et sur un disque sans clé de cache');
    expect(DataRefreshService.instance.resetEnCours, isFalse,
        reason: 'NON-RÉGRESSION : la barrière est rouverte après le reset');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  H — CARACTÉRISATION DU POINT DE REPRISE N°2 (M39)
  //
  //  ⚠️ CE TEST N'EST PAS UN DISCRIMINANT DE M39. Il documente, PREUVES EN
  //  MAIN, pourquoi M39 est une MUTATION ÉQUIVALENTE dans l'architecture
  //  actuelle. Il n'a pas été écrit pour rendre la suite verte : ses
  //  assertions portent sur des FAITS MESURÉS, et l'une d'elles échouerait si
  //  l'ordre des barrières venait à changer (cf. assertion A3 plus bas).
  //
  //  ── ORDRE RÉEL DES BARRIÈRES (backup_service.dart l.1483-1510) ────────
  //    AlertService → IaMemoryService → EloService → DataRefreshService
  //  Chacune, dans cet ordre : ferme sa barrière, incrémente SA génération,
  //  draine SES écritures, exécute le callback, vide sa RAM en `finally`.
  //
  //  ── POURQUOI LA GARDE DU POINT N°2 NE PEUT PAS ÊTRE ATTEINTE « ARMÉE » ─
  //  1. `DataRefreshService._generationCache` n'est incrémenté qu'à l'entrée
  //     du callback de SA barrière, donc APRÈS que :
  //       • `IaMemoryService` ait drainé toutes ses écritures, ET
  //       • `_loadCompleter` d'IaMemory ait été résolu (étape 3, l.1515-1522).
  //  2. Or la chaîne suspendante du cycle est
  //       `_detecterNonPartants` → `reAnalyserCourse` → `invaliderEtRecalculer`
  //       → `_load()` / `_save()`.
  //     `_save()` engage une écriture ENREGISTRÉE au registre d'IaMemory :
  //     elle est donc drainée par (1), et le reset NE PEUT PAS progresser
  //     tant qu'elle est suspendue. Mesuré ci-dessous : au retour du refresh,
  //     `generationCache == 0`.
  //  3. `_load()`, lui, ne suspend pas : `_loaded == true` après le premier
  //     rafraîchissement (mesuré), et `SharedPreferences.getInstance()` est
  //     servi par sa future mise en cache (la suspension armée sur
  //     `getAllWithParameters` n'est JAMAIS activée — c'est l'objet de
  //     l'assertion A1).
  //  4. Entre la fin du dernier `await` drainable et le point de reprise n°2
  //     (`_doRefresh` l.664), il n'existe AUCUN `await` : `reAnalyserCourse`
  //     l.806 est son seul `await`, et rien ne le sépare de l.836.
  //  ⇒ Quand la reprise s'exécute, `_resetEnCours` est encore `false` et
  //    `_generationCache` inchangé : `_estObsolete(...)` rend `false` dans
  //    TOUS les cas. Retirer la garde ne change donc aucun observable.
  //
  //  CONSÉQUENCE HONNÊTE : M39 n'est pas « survécue par manque de test » au
  //  sens d'un trou de couverture qu'un test habile comblerait ; elle est
  //  équivalente TANT QUE l'ordre des barrières reste celui décidé (et il
  //  reste inchangé, conformément à la décision de ne pas les déplacer).
  //  A1/A2/A3 ci-dessous VERROUILLENT cette analyse : si `DataRefresh` était
  //  déplacé en position externe, A3 tomberait immédiatement.
  // ═══════════════════════════════════════════════════════════════════════
  test('R01c-H — point de reprise n°2 : caractérisation (M39 équivalente)',
      () async {
    // ── 1 : premier refresh — RAM + cache disque peuplés ─────────────────
    final s = _Scenario(lieu: 'NONPARTANTS', nums: [1, 2, 3]);
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    final cacheEcrit = await _attendreQue(() => store.clesCache().length >= 2);
    expect(cacheEcrit, isTrue, reason: 'TÉMOIN 1 : cache disque du refresh n°1');
    expect(DataRefreshService.instance.reunions.length, 1,
        reason: 'TÉMOIN 1 : RAM peuplée par le refresh n°1');
    await _laisserProgresser(150); // laisse retomber l'isolate du refresh n°1

    // ── 2 : refresh n°2 — le n°3 disparaît → `_detecterNonPartants` ──────
    s.nums = [1, 2];
    // ⚠️ `_generationCache` est MONOTONE et CUMULATIF entre les tests de ce
    // fichier (il n'est jamais remis à zéro). On capture donc sa valeur de
    // référence avant le refresh n°2, au lieu de supposer qu'elle vaut 0.
    final generationAvant = DataRefreshService.instance.generationCache;
    final marque = store.journal.length;
    store.armerSuspensionSet('ia_poids_v3'); // 1re écriture de `_save()`
    final urls2 = <Uri>[];
    final refresh2 = _avecScenario(
        () => DataRefreshService.instance.refresh(), s, urls: urls2);

    final ecritureAtteinte = await _attendreQue(() => store.journal
        .sublist(marque)
        .contains('SET flutter.ia_poids_v3'));
    expect(ecritureAtteinte, isTrue,
        reason: 'TÉMOIN 2 : le refresh n°2 est retenu sur une ÉCRITURE IA, '
            'donc APRÈS le déclenchement de `_detecterNonPartants`');
    expect(urls2.where((u) => u.path.contains('participants')).isNotEmpty, isTrue,
        reason: 'TÉMOIN 2 : la détection de non-partants a bien été lancée');
    expect(store.nbSuspensionsGetAll, 0,
        reason: 'A1 : la suspension armée sur une LECTURE préfs n\'a jamais été '
            'activée — `getInstance()` est servi par sa future mise en cache, '
            'donc `_load()` ne constitue PAS un point de suspension');

    // ── 3 : reset engagé pendant que le refresh n°2 est suspendu ─────────
    final reset = BackupService.instance.reinitialiserComplet();
    final iaEngage = await _attendreQue(
        () => IaMemoryService.instance.nbEcrituresEnCours > 0);
    expect(iaEngage, isTrue,
        reason: 'A2 : l\'écriture IA est ENGAGÉE au registre d\'IaMemory — '
            'c\'est elle qui va retenir le drain du reset');

    // ── 4 : libération et reprise ────────────────────────────────────────
    store.libererSet();
    await refresh2;

    //  MESURES DÉCISIVES, prises AVANT `await reset` : le `finally` du reset
    //  n'a pas encore vidé la RAM, donc ces valeurs décrivent l'état au moment
    //  EXACT de la reprise du refresh n°2.
    debugPrint('R01c-H reprise : generation=${DataRefreshService.instance.generationCache} '
        'resetEnCours=${DataRefreshService.instance.resetEnCours} '
        'lastRefresh=${DataRefreshService.instance.lastRefresh}');

    expect(DataRefreshService.instance.generationCache, generationAvant,
        reason: 'A3 — VERROU DE L\'ANALYSE : à l\'instant de la reprise, la '
            'génération de DataRefresh est INCHANGÉE ($generationAvant). Sa '
            'barrière n\'a donc pas encore été armée (elle est la plus '
            'INTERNE). Si elle était déplacée en position externe, cette '
            'assertion tomberait et M39 deviendrait discriminable');
    expect(DataRefreshService.instance.resetEnCours, isFalse,
        reason: 'A3 : la barrière de DataRefresh n\'est pas fermée à la '
            'reprise — `_estObsolete(...)` rend donc `false`, ce qui rend la '
            'garde du point n°2 inobservable (M39 ≡ mutation équivalente)');

    await reset;
    await _laisserProgresser(200);

    debugPrint('R01c-H final : RAM=${DataRefreshService.instance.reunions.length} '
        'cles=${store.clesCache()} '
        'generation=${DataRefreshService.instance.generationCache}');

    // ── 5 : invariants de fin de reset, sur le chemin réel ──────────────
    expect(DataRefreshService.instance.reunions, isEmpty,
        reason: 'INVARIANT R01-c : RAM vide après le reset');
    expect(DataRefreshService.instance.reunions.any((r) => r.lieu == 'NONPARTANTS'),
        isFalse, reason: 'INVARIANT R01-c : aucune réunion d\'AVANT le reset');
    expect(store.clesCache(), isEmpty,
        reason: 'INVARIANT R01-a/c : disque vide, aucune clé recréée');
    expect(DataRefreshService.instance.lastRefresh, isNull,
        reason: 'INVARIANT R01-b : `_lastRefresh` remis à null par le reset');
    expect(DataRefreshService.instance.generationCache, greaterThan(0),
        reason: 'INVARIANT : la génération a bien été incrémentée par le reset');
    expect(DataRefreshService.instance.resetEnCours, isFalse,
        reason: 'INVARIANT : barrière rouverte après le reset');
  });
}
