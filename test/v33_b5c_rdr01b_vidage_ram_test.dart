// ═══════════════════════════════════════════════════════════════════════════
//  B5c — R-DR-01-b — VIDAGE DES CACHES RAM
//
//  OBJET : vérifier que `BackupService.reinitialiserComplet()` vide
//    • DataRefreshService : _reunions, _partantsParCourse, _nonPartantsNotifies,
//                           _lastRefresh, _lastError
//    • ZoneTurfService    : _cache, _cacheTime
//
//  PÉRIMÈTRE : R01-b uniquement. R01-c (écritures concurrentes) n'est PAS
//  traité ici ; R01-J et R01-K de v31b continuent de le démontrer.
//
//  OBSERVABILITÉ : `_partantsParCourse` et `_nonPartantsNotifies` sont PRIVÉS
//  et sans getter. Ils sont observés par leur SEUL effet observable de
//  production : la notification « Non-partant(s) » déposée dans
//  `AlertService._alerts` (data_refresh_service l.467) — précisément le
//  comportement conditionné par ces deux champs (l.422-447).
// ═══════════════════════════════════════════════════════════════════════════
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
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ── Store contrôlable ───────────────────────────────────────────────────────
class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

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

/// Nombre de notifications « Non-partant » déposées par AlertService.
/// C'est l'effet observable de `_partantsParCourse` + `_nonPartantsNotifies`.
int _nbAlertesNonPartant() => AlertService.instance.alerts
    .where((a) => a.titre.contains('Non-partant'))
    .length;

// ── Scénario mutable : permet de changer de réunion / de partants entre deux
//    appels réseau, sans reconstruire le MockClient.
class _Scenario {
  int numOfficiel;
  String lieu;
  List<int> nums;
  _Scenario({this.numOfficiel = 1, this.lieu = 'VINCENNES', required this.nums});
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
//      et fait `continue` : la course n'est plus examinée du tout.
//  Mesuré : 65 880 échecs sur 527 040 instants (12,50 %), heures locales 21-23.
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

/// Programme PMU : UNE réunion, UNE course, [nums] partants.
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
              'libelle': 'PRIX R01-b',
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

/// Exécute [action] avec un réseau PMU simulé qui suit [s] (état mutable).
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
    return http.Response(
        _programme(
            lieu: s.lieu, numOfficiel: s.numOfficiel, url: request.url),
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
    // ── HYGIÈNE DE TEST, PAS LA CORRECTION ──────────────────────────────
    //  `_cache`/`_cacheTime` de ZoneTurfService sont STATIQUES et `_reunions`
    //  de DataRefreshService est un SINGLETON : ils survivent d'un test à
    //  l'autre dans le même processus. On repart donc d'un état connu. Ce
    //  n'est pas la purge de production testée ici — celle-ci est mesurée
    //  après `BackupService.reinitialiserComplet()`.
    ZoneTurfService.viderCachePourResetComplet();
    DataRefreshService.instance.viderMemoirePourResetComplet();
  });

  // Pas de `tearDownAll` avec `dispose()` : `DataRefreshService.init()` n'est
  // jamais appelé dans ce fichier, donc aucun timer périodique n'est créé ;
  // et disposer le singleton casserait `notifyListeners()` pour tout appel
  // de `_doRefresh` encore en vol.

  // ═══════════════════════════════════════════════════════════════════════
  //  A — RÉUNIONS EN RAM AVANT RESET → ABSENTES APRÈS
  // ═══════════════════════════════════════════════════════════════════════
  test('R01b-A — _reunions est vidé par le reset', () async {
    final s = _Scenario(nums: [1, 2, 3]);
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _attendreQue(() => store.contient(kTs));

    final avant = DataRefreshService.instance.reunions;
    debugPrint('R01b-A avant : RAM=${avant.length} '
        'lieu=${avant.isNotEmpty ? avant.first.lieu : "-"} '
        'lastRefresh=${DataRefreshService.instance.lastRefresh}');
    expect(avant.length, 1, reason: 'TÉMOIN : la RAM est peuplée avant le reset');
    expect(DataRefreshService.instance.lastRefresh, isNotNull,
        reason: 'TÉMOIN : `_lastRefresh` est renseigné');

    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    debugPrint('R01b-A apres : '
        'RAM=${DataRefreshService.instance.reunions.length} '
        'lastRefresh=${DataRefreshService.instance.lastRefresh} '
        'lastError=${DataRefreshService.instance.lastError}');

    expect(DataRefreshService.instance.reunions, isEmpty,
        reason: 'CORRECTION R01-b : `_reunions` est vidé. Avant, il contenait '
            'encore la réunion d\'AVANT le reset (mesuré V31 R01-H : '
            'lieu=RAM-SURVIT) et l\'UI la servait telle quelle '
            '(home_screen.dart l.46 lit `DataRefreshService.instance.reunions`)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  C — _lastRefresh → null, ET _lastError → null
  // ═══════════════════════════════════════════════════════════════════════
  test('R01b-C — _lastRefresh et _lastError remis à null', () async {
    final s = _Scenario(nums: [1, 2]);
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _attendreQue(() => store.contient(kTs));

    expect(DataRefreshService.instance.lastRefresh, isNotNull, reason: 'TÉMOIN');

    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    debugPrint('R01b-C : lastRefresh=${DataRefreshService.instance.lastRefresh} '
        'lastError=${DataRefreshService.instance.lastError}');

    expect(DataRefreshService.instance.lastRefresh, isNull,
        reason: 'CORRECTION R01-b : `_lastRefresh` est remis à null — sinon '
            '`lastRefreshLabel` (l.187-192) afficherait « Il y a X min » pour '
            'un état qui n\'existe plus');
    expect(DataRefreshService.instance.lastError, isNull,
        reason: 'CORRECTION R01-b : `_lastError` est remis à null. L\'UI '
            'l\'affiche directement (home_screen l.2306, programme_screen '
            'l.73/91/117/126) : une erreur ANTÉRIEURE au reset resterait '
            'affichée sans cause — même famille de faux signalement que '
            'R-DR-04-G');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B — _nonPartantsNotifies → VIDÉ  (discriminant M36)
  //
  //  Scénario en 5 temps, tout par le CHEMIN DE PRODUCTION :
  //    1. refresh [1,2,3]  → première photo, aucune comparaison possible
  //    2. refresh [1,2]    → n°3 disparu → ALERTE + `_nonPartantsNotifies`
  //                          reçoit « R1C1_<date>_3 »  (anti-doublon armé)
  //    3. reset complet    → doit vider `_nonPartantsNotifies`
  //    4. refresh [1,2,3]  → re-mémorise {1,2,3}
  //    5. refresh [1,2]    → n°3 disparu À NOUVEAU
  //         • si `_nonPartantsNotifies` a été VIDÉ → nouvelle alerte (delta 1)
  //         • s'il a SURVÉCU (mutation M36) → l.444 `continue` sur doublon
  //           → delta 0 → ce test ÉCHOUE
  //
  //  Le temps 2 est indispensable : il prouve que le canal d'observation
  //  (l'alerte) fonctionne. Sans lui, une absence d'alerte au temps 5 ne
  //  distinguerait pas « doublon filtré » de « alerte jamais émise ».
  // ═══════════════════════════════════════════════════════════════════════
  test('R01b-B — _nonPartantsNotifies est vidé (la même alerte peut être '
      'réémise après reset)', () async {
    final s = _Scenario(nums: [1, 2, 3]);

    // 1. Première photo.
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _attendreQue(() => store.contient(kTs));
    expect(DataRefreshService.instance.reunions.length, 1, reason: 'TÉMOIN 1');

    // 2. n°3 disparaît → alerte, anti-doublon armé.
    //    ⚠️ `AlertService.executerResetComplet()` vide `_alerts` (l.2790) :
    //    `_nbAlertesNonPartant()` est un NIVEAU, il retombe à 0 au reset. On
    //    ne compare donc jamais un niveau d'avant-reset à un niveau
    //    d'après-reset. Chaque delta est mesuré AUTOUR du refresh concerné,
    //    dont on sait qu'il est le seul à pouvoir émettre.
    final avantEtape2 = _nbAlertesNonPartant();
    s.nums = [1, 2];
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _laisserProgresser();

    final apresEtape2 = _nbAlertesNonPartant();
    debugPrint('R01b-B étape 2 : alertes non-partant = '
        '${apresEtape2 - avantEtape2} (attendu 1)');
    expect(apresEtape2 - avantEtape2, 1,
        reason: 'TÉMOIN DE CANAL : la détection de non-partant produit bien une '
            'notification observable, et `_nonPartantsNotifies` contient '
            'désormais « R1C1_<date>_3 »');

    // 3. Reset complet.
    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();
    expect(DataRefreshService.instance.reunions, isEmpty, reason: 'TÉMOIN 3');
    expect(_nbAlertesNonPartant(), 0,
        reason: 'TÉMOIN 3 : le reset de `AlertService` a bien vidé `_alerts` — '
            'd\'où la mesure en DELTA et non en niveau');

    // 4. Re-mémorisation.
    s.nums = [1, 2, 3];
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _laisserProgresser();

    // 5. n°3 disparaît À NOUVEAU — mesure du seul delta de cette étape.
    final avantEtape5 = _nbAlertesNonPartant();
    s.nums = [1, 2];
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _laisserProgresser();

    final apresEtape5 = _nbAlertesNonPartant();
    debugPrint('R01b-B étape 5 : alertes non-partant = '
        '${apresEtape5 - avantEtape5} (attendu 1)');

    expect(apresEtape5 - avantEtape5, 1,
        reason: 'CORRECTION R01-b / DISCRIMINANT M36 : après un reset complet, '
            'la même notification de non-partant DOIT pouvoir être réémise — '
            'c\'est le sens d\'une remise à zéro. Si `_nonPartantsNotifies` '
            'survivait, la ligne 440-442 filtrerait le doublon et AUCUNE '
            'alerte ne serait déposée : ce test échouerait');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B2 — _partantsParCourse → VIDÉ
  //
  //  Isoler ce champ demande un scénario où la PREMIÈRE photo post-reset ne
  //  concerne PAS la course dont l'ancienne photo a survécu — sinon
  //  `_initialiserEtatPartants` (l.371-388) réécrit l'entrée et masque tout.
  //
  //    1. refresh R1 [1,2,3] → `_partantsParCourse['R1C1_<date>'] = {1,2,3}`
  //    2. reset              → doit vider la map
  //    3. refresh R2 [7,8]   → la map ne doit plus contenir que la clé de R2
  //    4. refresh R1 [1,2]   → `_reunions` (= [R2]) est non vide et la
  //                            signature change → `_detecterNonPartants` EST
  //                            appelé sur R1 :
  //         • map VIDÉE   → `numsAnciens == null` (l.425) → mémorisation,
  //                          AUCUNE alerte                    → delta 0
  //         • map SURVÉCUE → {1,2,3} vs {1,2} → n°3 « disparu »
  //                          → ALERTE FANTÔME                  → delta 1
  // ═══════════════════════════════════════════════════════════════════════
  test('R01b-B2 — _partantsParCourse est vidé (aucune alerte fantôme issue '
      'd\'une photo antérieure au reset)', () async {
    final s = _Scenario(numOfficiel: 1, lieu: 'VINCENNES', nums: [1, 2, 3]);

    // 1. Photo de R1.
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _attendreQue(() => store.contient(kTs));
    expect(DataRefreshService.instance.reunions.length, 1, reason: 'TÉMOIN 1');
    expect(DataRefreshService.instance.reunions.first.code, 'R1',
        reason: 'TÉMOIN 1 : la photo est bien celle de R1');

    // 2. Reset complet.
    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();
    expect(DataRefreshService.instance.reunions, isEmpty, reason: 'TÉMOIN 2');

    // 3. Autre réunion : la clé de R1 n'est PAS réécrite ici.
    s.numOfficiel = 2;
    s.lieu = 'CAGNES';
    s.nums = [7, 8];
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _laisserProgresser();
    expect(DataRefreshService.instance.reunions.first.code, 'R2',
        reason: 'TÉMOIN 3 : la RAM ne contient plus que R2');

    // 4. Retour sur R1, amputé du n°3.
    //    Mesure en DELTA autour de CE seul refresh : `AlertService` vide
    //    `_alerts` au reset (l.2790), un niveau absolu ne serait pas comparable.
    final avantEtape4 = _nbAlertesNonPartant();
    s.numOfficiel = 1;
    s.lieu = 'VINCENNES';
    s.nums = [1, 2];
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _laisserProgresser();

    final delta = _nbAlertesNonPartant() - avantEtape4;
    debugPrint('R01b-B2 : alertes non-partant = $delta (attendu 0) '
        'RAM=${DataRefreshService.instance.reunions.length}');

    expect(delta, 0,
        reason: 'CORRECTION R01-b : `_partantsParCourse` est vidé par le reset. '
            'La première photo post-reset de R1 est donc ABSENTE de la map '
            '(l.425 : `numsAnciens == null` → simple mémorisation). Si la map '
            'avait survécu, la comparaison {1,2,3} → {1,2} aurait déclaré le '
            'n°3 non-partant et émis une alerte FANTÔME, sur une course dont '
            'l\'historique a pourtant été effacé');
    expect(DataRefreshService.instance.reunions.first.code, 'R1',
        reason: 'TÉMOIN 4 : le refresh a bien eu lieu et a bien été retenu');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D — CACHE STATIQUE ZONETURF → VIDÉ  (discriminant M37)
  // ═══════════════════════════════════════════════════════════════════════
  test('R01b-D — le cache statique ZoneTurf est vidé par le reset', () async {
    final s = _Scenario(nums: [1, 2]);

    // `refresh()` → `_doRefresh(force: true)` → `chargerProgramme(forceRefresh:
    // true)` : le cache statique est PEUPLÉ au passage (l.196-197).
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _attendreQue(() => store.contient(kTs));

    // Témoin de préparation : un appel SANS forceRefresh ne doit PAS aller au
    // réseau tant que le cache statique est chaud.
    final urlsTemoin = <Uri>[];
    await _avecScenario(() => ZoneTurfService.chargerProgramme(), s,
        urls: urlsTemoin);
    debugPrint('R01b-D témoin : appelsRéseau=${urlsTemoin.length}');
    expect(urlsTemoin, isEmpty,
        reason: 'TÉMOIN DE PRÉPARATION : le cache statique est peuplé — un '
            'appel sans forceRefresh est servi depuis `_cache[dateStr]` '
            '(zone_turf_service l.52-58)');

    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    // APRÈS reset : cache vide → même appel SANS forceRefresh doit aller au
    // réseau.
    final urls = <Uri>[];
    await _avecScenario(() => ZoneTurfService.chargerProgramme(), s, urls: urls);
    debugPrint('R01b-D apres reset : appelsRéseau=${urls.length}');

    expect(urls, isNotEmpty,
        reason: 'CORRECTION R01-b / DISCRIMINANT M37 : le cache statique de '
            'ZoneTurfService est vidé, donc un `chargerProgramme()` SANS '
            'forceRefresh repart légitimement au réseau. Si la purge était '
            'absente (M37), `_cache` servirait encore les réunions d\'AVANT le '
            'reset sans aucun appel — mesuré V31b R01-N '
            '(`reunions=1 appelsRéseau=0`)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  E — PREMIER CHARGEMENT APRÈS RESET → NE RESTITUE PAS L'ANCIEN CACHE
  // ═══════════════════════════════════════════════════════════════════════
  test('R01b-E — un chargement en échec après reset ne ressuscite rien',
      () async {
    final s = _Scenario(nums: [1, 2]);
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _attendreQue(() => store.contient(kTs));
    expect(DataRefreshService.instance.reunions.length, 1, reason: 'TÉMOIN RAM');

    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();

    // API injoignable : rien ne doit être « ressuscité » depuis la RAM ni
    // depuis le cache statique.
    final urls = <Uri>[];
    final client = MockClient((request) async {
      urls.add(request.url);
      return http.Response('', 500);
    });
    await http.runWithClient(
        () => DataRefreshService.instance.refresh(), () => client);
    await _laisserProgresser();

    debugPrint('R01b-E : RAM=${DataRefreshService.instance.reunions.length} '
        'appelsRéseau=${urls.length} '
        'lastError=${DataRefreshService.instance.lastError}');

    expect(urls, isNotEmpty,
        reason: 'TÉMOIN : le réseau a bien été sollicité — le cache statique '
            'n\'a pas court-circuité l\'appel');
    expect(DataRefreshService.instance.reunions, isEmpty,
        reason: 'CORRECTION R01-b : après un reset puis un échec réseau, '
            'AUCUNE réunion antérieure n\'est restituée — ni depuis `_reunions`, '
            'ni depuis `ZoneTurfService._cache`. L\'application n\'invente rien');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  F — NOUVEAU CHARGEMENT LÉGITIME APRÈS RESET → FONCTIONNE
  // ═══════════════════════════════════════════════════════════════════════
  test('R01b-F — un chargement légitime après reset fonctionne', () async {
    final s = _Scenario(nums: [1, 2]);
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _attendreQue(() => store.contient(kTs));

    await BackupService.instance.reinitialiserComplet();
    await _laisserProgresser();
    expect(DataRefreshService.instance.reunions, isEmpty, reason: 'TÉMOIN');
    expect(store.clesCache(), isEmpty, reason: 'TÉMOIN : disque effacé');

    s.nums = [1, 2, 3, 4];
    await _avecScenario(() => DataRefreshService.instance.refresh(), s);
    await _attendreQue(() => store.contient(kTs));
    await _laisserProgresser();

    debugPrint('R01b-F : RAM=${DataRefreshService.instance.reunions.length} '
        'disque=${store.clesCache()} '
        'lastError=${DataRefreshService.instance.lastError}');

    expect(DataRefreshService.instance.reunions.length, 1,
        reason: 'NON-RÉGRESSION : le service reste pleinement opérationnel '
            'après un reset — le vidage ne gèle rien');
    expect(store.clesCache(), isNotEmpty,
        reason: 'NON-RÉGRESSION : le cache disque est réécrit normalement');
    expect(store.contient(kTs), isTrue,
        reason: 'NON-RÉGRESSION : la paire disque est reconstituée');
    expect(DataRefreshService.instance.lastError, isNull,
        reason: 'NON-RÉGRESSION : aucun message d\'erreur résiduel');
    expect(DataRefreshService.instance.lastRefresh, isNotNull,
        reason: 'NON-RÉGRESSION : `_lastRefresh` est de nouveau renseigné');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G — AUCUN EFFET DE BORD DES SEULES MÉTHODES DE VIDAGE
  // ═══════════════════════════════════════════════════════════════════════
  test('R01b-G — les méthodes de vidage seules n\'ont aucun effet de bord',
      () async {
    final s = _Scenario(nums: [1, 2]);
    final urls = <Uri>[];
    await _avecScenario(() => DataRefreshService.instance.refresh(), s,
        urls: urls);
    await _attendreQue(() => store.contient(kTs));

    // On laisse TOUT le travail asynchrone différé se terminer (les
    // `_enregistrerPronosticsAuto`, `_recupererResultatsAuto`, sauvegardes
    // d'AlertService…) avant de prendre la marque : sinon une écriture
    // antérieure, encore en vol, serait imputée à tort au vidage.
    await _laisserProgresser(400);

    final marque = store.journal.length;
    final appelsAvant = urls.length;
    final reunionsAvant = DataRefreshService.instance.reunions.length;
    final disqueAvant = store.clesCache();

    // Appel DIRECT des deux méthodes, hors de tout reset.
    DataRefreshService.instance.viderMemoirePourResetComplet();
    ZoneTurfService.viderCachePourResetComplet();
    await _laisserProgresser(400);

    final journal = store.journal.sublist(marque);
    debugPrint('R01b-G journal=$journal '
        'RAM=${DataRefreshService.instance.reunions.length} '
        '(avant=$reunionsAvant) appelsRéseau=${urls.length - appelsAvant}');

    expect(journal, isEmpty,
        reason: 'CORRECTION R01-b : le vidage n\'écrit RIEN sur le disque — ni '
            '`SET` (qui recréerait les clés que R01-a supprime), ni `REM`, ni '
            '`CLEAR`. Les deux méthodes sont purement RAM');
    expect(urls.length - appelsAvant, 0,
        reason: 'CORRECTION R01-b : le vidage ne déclenche AUCUNE récupération '
            'réseau — ni `_doRefresh()`, ni `ZoneTurfService.chargerProgramme()` '
            'ne sont appelés');
    expect(DataRefreshService.instance.reunions, isEmpty,
        reason: 'FAIT : la RAM est bien vidée');
    expect(disqueAvant, isNotEmpty,
        reason: 'TÉMOIN : le disque contenait bien les clés avant le vidage');
    expect(store.clesCache(), disqueAvant,
        reason: 'FAIT : le cache DISQUE n\'est pas touché par le vidage RAM — '
            'c\'est le rôle de R01-a, pas de R01-b');
    expect(DataRefreshService.instance.lastRefresh, isNull,
        reason: 'FAIT : `_lastRefresh` remis à null sans notification');
  });
}
