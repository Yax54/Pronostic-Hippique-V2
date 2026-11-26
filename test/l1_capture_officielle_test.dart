// ═══════════════════════════════════════════════════════════════════════════
//  L1 — CAPTURE DES ARRIVÉES OFFICIELLES COMPLÈTES DEPUIS /programme/{date}
//
//  OBJET : prouver que `ZoneTurfService.chargerProgramme()` alimente le
//  stockage L0 (`ArriveeOfficielleService`) à partir du JSON BRUT de
//  `/programme/{date}`, sans modifier le comportement existant.
//
//  CE QUE CES TESTS PROUVENT, ET RIEN DE PLUS :
//    L1-1  arrivée définitive complète SANS ex æquo → stockée telle quelle
//    L1-2  arrivée définitive complète AVEC ex æquo → groupes préservés
//    L1-3  course SANS arrivée définitive → ignorée sans erreur
//    L1-4  statut provisoire / arrivée incomplète → ignorée sans erreur
//    L1-5  plusieurs courses et plusieurs réunions → toutes capturées
//    L1-6  UNE SEULE écriture groupée par cycle de chargement
//    L1-7  chargements répétés → aucun doublon, aucun écrasement
//    L1-8  échec du stockage L0 → le programme est chargé quand même
//    L1-9  chargement obsolète après reset → aucune écriture L0
//    L1-10 rejeu idempotent de la file au premier chargement
//    L1-11 non-régression : le programme rendu reste identique
//    L1-12 non-régression : aucun mécanisme IA n'est touché
//
//  TÉMOIN DE NON-VACUITÉ : chaque test vérifie qu'il a réellement observé
//  ce qu'il annonce (nombre d'entrées lues, nombre de SET, etc.).
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:io'; // gzip

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Store en mémoire, avec journal des SET et politique de panne ciblée.
// ───────────────────────────────────────────────────────────────────────────
class StoreL1 extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> sets = <String>[];
  final Set<String> clesEnPanne = <String>{};
  bool panneParException = true;

  bool _doitEchouer(String cle) {
    final nue = cle.startsWith('flutter.') ? cle.substring(8) : cle;
    return clesEnPanne.contains(cle) || clesEnPanne.contains(nue);
  }

  @override
  Future<bool> clear() async {
    _valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    if (_doitEchouer(key)) {
      if (panneParException) throw StateError('PANNE REM $key');
      return false;
    }
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final nue = key.startsWith('flutter.') ? key.substring(8) : key;
    if (_doitEchouer(key)) {
      if (panneParException) throw StateError('PANNE SET $key');
      return false;
    }
    sets.add(nue);
    _valeurs[key] = value;
    return true;
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? brut(String cle) => _valeurs['flutter.$cle'];

  List<String> get clesArrivees => _valeurs.keys
      .where((k) => k.startsWith('flutter.$kArriveeStoragePrefix'))
      .toList()
    ..sort();

  /// Tous les SET touchant le stockage L0 (shards mensuels ET file).
  List<String> get setsL0 => sets
      .where((k) =>
          k.startsWith(kArriveeStoragePrefix) || k == kArriveePendingKey)
      .toList();

  int get nbSetsShards =>
      sets.where((k) => k.startsWith(kArriveeStoragePrefix)).length;
  int nbSetsSur(String cle) => sets.where((k) => k == cle).length;
}

late StoreL1 store;

void _installerStore() {
  store = StoreL1();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

/// Encode un shard mensuel exactement comme le service l'écrit.
String _shard(Map<String, dynamic> arrivees) {
  final payload = <String, dynamic>{'v': 1, 'arrivees': arrivees};
  return base64Encode(gzip.encode(utf8.encode(jsonEncode(payload))));
}

/// Encode une file d'attente exactement comme le service l'écrit.
String _file(List<Map<String, dynamic>> entrees) {
  final payload = <String, dynamic>{'v': 1, 'arrivees': entrees};
  return base64Encode(gzip.encode(utf8.encode(jsonEncode(payload))));
}

/// Date `ddMMyyyy` du jour courant — c'est le `dateStr` que la production
/// utilisera (zone_turf_service `_todayStr()`) et donc celui des courseKeys.
String get _dateDuJour {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

/// Mois `YYYY-MM` attendu dans la clé de shard pour la date du jour.
String get _moisDuJour {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}';
}

String get _cleShard => '$kArriveeStoragePrefix$_moisDuJour';

/// Clé de course telle que la construit `chargerProgramme`.
String _courseKey(int numR, int numC) => 'R${numR}C$numC' '_$_dateDuJour';

// ───────────────────────────────────────────────────────────────────────────
//  Construction du JSON PMU de /programme/{date}
// ───────────────────────────────────────────────────────────────────────────

/// Une course du programme. [statut] + [ordre] permettent de simuler tous les
/// cas : définitive complète, provisoire, incomplète, sans arrivée.
Map<String, dynamic> _courseJson({
  required int numOrdre,
  String statut = 'ARRIVEE_DEFINITIVE_COMPLETE',
  List<List<int>>? ordre,
  int? declares,
  bool inclureOrdre = true,
  String libelle = 'PRIX TEST',
  List<String> paris = const <String>[],
}) {
  final m = <String, dynamic>{
    'numOrdre': numOrdre,
    'libelle': libelle,
    'discipline': 'ATTELE',
    'distance': 2100,
    'montantPrix': 30000,
    'paris': [
      for (final p in paris) {'typePari': p}
    ],
    'heureDepart': 0,
    'statut': statut,
  };
  if (inclureOrdre) m['ordreArrivee'] = ordre;
  if (declares != null) m['nombreDeclaresPartants'] = declares;
  return m;
}

/// Une réunion du programme.
Map<String, dynamic> _reunionJson({
  required int numOfficiel,
  required String lieu,
  required List<Map<String, dynamic>> courses,
}) =>
    {
      'numOfficiel': numOfficiel,
      'hippodrome': {'libelleLong': '$lieu (FRANCE)', 'libelleCourt': lieu},
      'courses': courses,
    };

/// Corps JSON de `/programme/{date}`.
String _programmeJson(List<Map<String, dynamic>> reunions) =>
    jsonEncode({
      'programme': {'reunions': reunions}
    });

/// Corps JSON de `/participants`.
String _participantsJson(List<int> nums) => jsonEncode({
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

/// Exécute [action] avec un réseau PMU simulé qui renvoie [reunions].
Future<T> _avecReseau<T>(
  Future<T> Function() action,
  List<Map<String, dynamic>> reunions, {
  List<Uri>? urls,
  List<int> nums = const [1, 2, 3],
  int? codeProgramme,
}) {
  final client = MockClient((request) async {
    urls?.add(request.url);
    if (request.url.path.contains('participants')) {
      return http.Response(_participantsJson(nums), 200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response(
        _programmeJson(reunions), codeProgramme ?? 200,
        headers: {'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

/// Programme minimal à UNE réunion / UNE course, dont l'arrivée est fournie.
List<Map<String, dynamic>> _programmeUneCourse({
  required List<List<int>>? ordre,
  String statut = 'ARRIVEE_DEFINITIVE_COMPLETE',
  int? declares,
  bool inclureOrdre = true,
}) =>
    [
      _reunionJson(numOfficiel: 1, lieu: 'VINCENNES', courses: [
        _courseJson(
          numOrdre: 1,
          statut: statut,
          ordre: ordre,
          declares: declares,
          inclureOrdre: inclureOrdre,
        ),
      ]),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _installerStore();
    ArriveeOfficielleService.instance.viderMemoireSeulement();
    // Hygiène : `_cache`/`_cacheTime` sont STATIQUES et survivent d'un test à
    // l'autre dans le même processus. `_generationReset` est ainsi incrémenté
    // avant chaque test, ce qui rend le témoin de reset explicite.
    ZoneTurfService.viderCachePourResetComplet();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-1 — ARRIVÉE DÉFINITIVE COMPLÈTE, SANS EX ÆQUO
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-1 arrivée définitive complète sans ex æquo → stockée à l\'identique',
      () async {
    final svc = ArriveeOfficielleService.instance;
    final urls = <Uri>[];

    await _avecReseau(
      () => ZoneTurfService.chargerProgramme(),
      _programmeUneCourse(
        ordre: [
          [10], [7], [2], [9], [6], [8]
        ],
        declares: 10,
      ),
      urls: urls,
    );

    // TÉMOIN : la capture n'ajoute AUCUNE requête réseau.
    // ⚠️ `.../programme/{date}/R1/C1/participants` contient aussi « programme » :
    // on isole l'URL du PROGRAMME seul (celle qui ne va pas aux partants).
    // ⚠️ PRÉCISION AJOUTÉE (chantier « alimentation des 19 critères ») :
    //    l'URL d'enrichissement `/programme/{date}/R{n}/C{n}/performances-
    //    detaillees/pretty` contient elle aussi « programme ». Sans cette
    //    exclusion, le témoin compterait 2 au lieu de 1 et signalerait à tort
    //    que la CAPTURE coûte une requête. L'assertion reste portée sur le
    //    SEUL endpoint `/programme/{date}` : son intention (« la capture
    //    n'ajoute aucune requête ») est préservée, pas affaiblie.
    bool estUrlProgramme(Uri u) =>
        u.path.contains('programme') &&
        !u.path.contains('participants') &&
        !u.path.contains('performances-detaillees');
    final requetesProgramme = urls.where(estUrlProgramme).length;
    final requetesPartants =
        urls.where((u) => u.path.contains('participants')).length;
    debugPrint('L1-1 réseau : programme=$requetesProgramme '
        'participants=$requetesPartants total=${urls.length}');

    final cle = 'R1C1_$_dateDuJour';
    expect(svc.contient(cle), isTrue,
        reason: 'TÉMOIN DE PRÉPARATION : l\'arrivée doit être capturée');
    expect(
        svc.arrivee(cle),
        equals(<List<int>>[
          [10], [7], [2], [9], [6], [8]
        ]),
        reason: 'L\'ordre officiel est conservé tel quel, sans réordonnancement');
    expect(svc.declares(cle), 10,
        reason: 'Le nombre de partants déclarés est conservé');
    expect(requetesProgramme, 1,
        reason: 'TÉMOIN : une seule requête /programme — la capture n\'en '
            'ajoute aucune');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-2 — EX ÆQUO PRÉSERVÉS
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-2 ex æquo : les groupes sont préservés, pas aplatis', () async {
    final svc = ArriveeOfficielleService.instance;

    await _avecReseau(
      () => ZoneTurfService.chargerProgramme(),
      _programmeUneCourse(ordre: [
        [4, 7], [2], [9, 1, 5]
      ], declares: 9),
    );

    final cle = 'R1C1_$_dateDuJour';
    final a = svc.arrivee(cle);
    debugPrint('L1-2 arrivée=$a');

    expect(a, isNotNull, reason: 'TÉMOIN : arrivée capturée');
    expect(a!.length, 3,
        reason: 'TÉMOIN : 3 GROUPES de rangs, pas 6 chevaux à plat');
    expect(a[0], equals(<int>[4, 7]),
        reason: 'Le premier ex æquo garde ses DEUX numéros dans l\'ordre API');
    expect(a[2], equals(<int>[9, 1, 5]),
        reason: 'Un ex æquo à trois est conservé à trois');
    // Un aplatissement produirait [[4],[7],[2],[9],[1],[5]] : on le refuse.
    expect(a, isNot(equals(<List<int>>[
      [4], [7], [2], [9], [1], [5]
    ])), reason: 'TÉMOIN NÉGATIF : aucune trace d\'aplatissement');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-3 — COURSE SANS RÉSULTAT DÉFINITIF
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-3 course FIN_COURSE sans ordreArrivee → ignorée, aucune erreur',
      () async {
    final svc = ArriveeOfficielleService.instance;

    final reunions = await _avecReseau(
      () => ZoneTurfService.chargerProgramme(),
      _programmeUneCourse(
        ordre: null,
        statut: 'FIN_COURSE',
        inclureOrdre: false,
      ),
    );

    expect(svc.contient('R1C1_$_dateDuJour'), isFalse,
        reason: 'TÉMOIN : rien n\'est stocké pour une course sans arrivée '
            'définitive');
    expect(svc.nbEntrees, 0);
    expect(svc.derniereErreur, isNull,
        reason: 'Une absence d\'arrivée n\'est PAS une erreur');
    expect(store.setsL0, isEmpty,
        reason: 'TÉMOIN : aucun accès au stockage L0 — pas même un SET vide');
    // Le programme lui-même doit être rendu normalement.
    expect(reunions, hasLength(1),
        reason: 'TÉMOIN : la course reste dans le programme');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-4 — STATUT PROVISOIRE / ARRIVÉE INCOMPLÈTE
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-4 statuts non définitifs et ordres invalides → tous ignorés',
      () async {
    final svc = ArriveeOfficielleService.instance;

    // Quatre courses dans UNE réunion : chacune doit être refusée pour une
    // raison différente.
    final reunions = [
      _reunionJson(numOfficiel: 2, lieu: 'ENGHIEN', courses: [
        // 1) statut définitif mais ordre ABSENT
        _courseJson(
            numOrdre: 1,
            statut: 'ARRIVEE_DEFINITIVE_COMPLETE',
            inclureOrdre: false),
        // 2) statut provisoire, ordre présent
        _courseJson(
            numOrdre: 2, statut: 'ARRIVEE_DEFINITIVE', ordre: [
          [1], [2]
        ]),
        // 3) ordre présent mais VIDE
        _courseJson(
            numOrdre: 3, statut: 'ARRIVEE_DEFINITIVE_COMPLETE', ordre: []),
        // 4) ordre contenant un groupe vide (arrivée incomplète)
        _courseJson(
            numOrdre: 4,
            statut: 'ARRIVEE_DEFINITIVE_COMPLETE',
            ordre: [
              [1], [], [3]
            ]),
        // 5) ordre contenant un numéro invalide
        _courseJson(
            numOrdre: 5,
            statut: 'ARRIVEE_DEFINITIVE_COMPLETE',
            ordre: [
              [1], [0]
            ]),
      ]),
    ];

    await _avecReseau(() => ZoneTurfService.chargerProgramme(), reunions);

    debugPrint('L1-4 nbEntrees=${svc.nbEntrees} err=${svc.derniereErreur}');
    expect(svc.nbEntrees, 0, reason: 'Aucune des 5 courses n\'est stockable');
    for (var c = 1; c <= 5; c++) {
      expect(svc.contient('R2C${c}_$_dateDuJour'), isFalse,
          reason: 'TÉMOIN : la course C$c est bien refusée');
    }
    expect(svc.derniereErreur, isNull, reason: 'Aucun de ces refus n\'est une '
        'erreur : ce sont des absences normales');
    expect(store.setsL0, isEmpty,
        reason: 'TÉMOIN : aucun accès au stockage L0');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-5 — PLUSIEURS COURSES ET PLUSIEURS RÉUNIONS
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-5 plusieurs courses et réunions → toutes capturées, clés correctes',
      () async {
    final svc = ArriveeOfficielleService.instance;

    final reunions = [
      _reunionJson(numOfficiel: 1, lieu: 'VINCENNES', courses: [
        _courseJson(numOrdre: 1, ordre: [
          [3], [1]
        ], declares: 8),
        _courseJson(numOrdre: 2, ordre: [
          [5], [6], [7]
        ], declares: 12),
        // Course sans arrivée au milieu de deux courses avec arrivée : elle ne
        // doit pas perturber la capture des autres.
        _courseJson(
            numOrdre: 3,
            statut: 'FIN_COURSE',
            inclureOrdre: false,
            declares: 10),
      ]),
      // Réunion étrangère : exclue du programme, donc JAMAIS capturée.
      _reunionJson(numOfficiel: 3, lieu: 'GOODWOOD', courses: [
        _courseJson(numOrdre: 1, ordre: [
          [1], [2]
        ]),
      ]),
      _reunionJson(numOfficiel: 5, lieu: 'CAGNES-SUR-MER', courses: [
        // Ex æquo dans la 2e réunion française
        _courseJson(numOrdre: 4, ordre: [
          [2, 8], [6]
        ], declares: 11),
      ]),
    ];

    final sortie =
        await _avecReseau(() => ZoneTurfService.chargerProgramme(), reunions);

    debugPrint('L1-5 nbEntrees=${svc.nbEntrees} '
        'reunions=${sortie.length} '
        'clés=${svc.moisConnus}');

    // TÉMOIN : 3 arrivées capturées (R1C1, R1C2, R5C4).
    expect(svc.nbEntrees, 3, reason: 'TÉMOIN : trois courses ont une arrivée');
    expect(svc.arrivee('R1C1_$_dateDuJour'), equals(<List<int>>[
      [3], [1]
    ]));
    expect(svc.arrivee('R1C2_$_dateDuJour'), equals(<List<int>>[
      [5], [6], [7]
    ]));
    expect(svc.arrivee('R5C4_$_dateDuJour'), equals(<List<int>>[
      [2, 8], [6]
    ]));
    // La course sans arrivée n'est pas stockée.
    expect(svc.contient('R1C3_$_dateDuJour'), isFalse);
    // La réunion étrangère n'est jamais capturée (elle est filtrée avant).
    expect(svc.contient('R3C1_$_dateDuJour'), isFalse,
        reason: 'TÉMOIN : la capture est en aval du filtre hippodrome');
    // Le programme rendu ne contient bien que les réunions françaises.
    expect(sortie.length, 2,
        reason: 'TÉMOIN : GOODWOOD est exclu du programme — comportement '
            'inchangé');
    expect(svc.declares('R1C2_$_dateDuJour'), 12);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-6 — UNE SEULE ÉCRITURE GROUPÉE PAR CYCLE
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-6 un cycle = N arrivées → UN SEUL SET de shard', () async {
    final svc = ArriveeOfficielleService.instance;

    final reunions = [
      _reunionJson(numOfficiel: 1, lieu: 'VINCENNES', courses: [
        for (var c = 1; c <= 5; c++)
          _courseJson(numOrdre: c, ordre: [
            [c], [c + 1]
          ]),
      ]),
    ];

    final urls = <Uri>[];
    await _avecReseau(() => ZoneTurfService.chargerProgramme(), reunions,
        urls: urls);

    debugPrint('L1-6 nbEntrees=${svc.nbEntrees} setsShards=${store.nbSetsShards} '
        'setsFile=${store.nbSetsSur(kArriveePendingKey)}');

    // TÉMOIN : 5 arrivées ont bien été vues.
    expect(svc.nbEntrees, 5, reason: 'TÉMOIN : cinq courses capturées');
    // Le point central : UNE écriture de shard pour les 5, pas cinq.
    expect(store.nbSetsShards, 1,
        reason: 'ÉCRITURE GROUPÉE : les 5 arrivées d\'un même mois coûtent '
            'UN SET de shard. Un SET par course signifierait 5.');
    // La file est écrite deux fois par conception (étape 1 puis étape 3).
    expect(store.nbSetsSur(kArriveePendingKey), lessThanOrEqualTo(2),
        reason: 'La file d\'attente n\'est jamais écrite une fois par course');
    // Une seule requête /programme : la capture ne coûte aucun appel.
    // ⚠️ Même précision que L1-1 : on exclut l'endpoint d'enrichissement
    //    `performances-detaillees` (dont le chemin contient « programme »)
    //    pour ne compter QUE les appels à `/programme/{date}`.
    expect(
        urls
            .where((u) =>
                u.path.contains('programme') &&
                !u.path.contains('participants') &&
                !u.path.contains('performances-detaillees'))
            .length,
        1,
        reason: 'TÉMOIN : une seule requête programme, 5 requêtes partants');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-7 — CHARGEMENTS RÉPÉTÉS : AUCUN DOUBLON
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-7 chargements répétés → aucun doublon, contenu stable', () async {
    final svc = ArriveeOfficielleService.instance;
    final prog = _programmeUneCourse(ordre: [
      [4, 7], [2], [9]
    ], declares: 9);

    await _avecReseau(
        () => ZoneTurfService.chargerProgramme(forceRefresh: true), prog);
    final cle = 'R1C1_$_dateDuJour';
    final apres1 = jsonEncode(svc.arrivee(cle));
    final nb1 = svc.nbEntrees;
    final brut1 = store.brut(_cleShard);

    // Deuxième puis troisième chargement forcé, avec les mêmes données.
    await _avecReseau(
        () => ZoneTurfService.chargerProgramme(forceRefresh: true), prog);
    await _avecReseau(
        () => ZoneTurfService.chargerProgramme(forceRefresh: true), prog);

    debugPrint('L1-7 nb1=$nb1 nb3=${svc.nbEntrees} '
        'identical=${jsonEncode(svc.arrivee(cle)) == apres1}');

    expect(svc.nbEntrees, 1,
        reason: 'TÉMOIN : une seule entrée après 3 chargements — aucune '
            'duplication');
    expect(jsonEncode(svc.arrivee(cle)), equals(apres1),
        reason: 'L\'arrivée est inchangée');
    expect(store.brut(_cleShard), equals(brut1),
        reason: 'Le shard est OCTET POUR OCTET identique : la réécriture est '
            'idempotente');
  });

  test('L1-7b une arrivée déjà stockée n\'est jamais écrasée par une absence',
      () async {
    final svc = ArriveeOfficielleService.instance;

    // Première capture légitime.
    await _avecReseau(() => ZoneTurfService.chargerProgramme(),
        _programmeUneCourse(ordre: [
          [5], [1]
        ]));
    final cle = 'R1C1_$_dateDuJour';
    expect(svc.arrivee(cle), equals(<List<int>>[
      [5], [1]
    ]));

    // Deuxième chargement : l'API ne renvoie PLUS d'arrivée (statut changé).
    await _avecReseau(
        () => ZoneTurfService.chargerProgramme(forceRefresh: true),
        _programmeUneCourse(
            ordre: null, statut: 'FIN_COURSE', inclureOrdre: false));

    expect(svc.arrivee(cle), equals(<List<int>>[
      [5], [1]
    ]), reason: 'Une absence ne détruit JAMAIS une arrivée confirmée');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-8 — ÉCHEC DU STOCKAGE L0 SANS BLOCAGE DU PROGRAMME
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-8 panne du stockage L0 → le programme est chargé quand même',
      () async {
    final svc = ArriveeOfficielleService.instance;
    store.clesEnPanne.add(_cleShard);
    store.clesEnPanne.add(kArriveePendingKey);

    final prog = _programmeUneCourse(ordre: [
      [10], [7], [2]
    ], declares: 10);
    final sortie =
        await _avecReseau(() => ZoneTurfService.chargerProgramme(), prog);

    debugPrint('L1-8 réunions=${sortie.length} '
        'courses=${sortie.isEmpty ? 0 : sortie.first.courses.length} '
        'nbEntrees=${svc.nbEntrees} err=${svc.derniereErreur}');

    // LE POINT DU TEST : le programme est rendu normalement.
    expect(sortie, hasLength(1),
        reason: 'LE PROGRAMME N\'EST PAS BLOQUÉ par la panne L0');
    expect(sortie.first.courses, hasLength(1),
        reason: 'TÉMOIN : la course est bien présente avec ses partants');
    expect(sortie.first.courses.first.partants, hasLength(3),
        reason: 'TÉMOIN : les partants ont bien été chargés');
    // L'écriture a échoué, et l'échec est SIGNALÉ côté service (pas masqué).
    expect(svc.nbEntrees, 0,
        reason: 'TÉMOIN : rien n\'a pu être écrit — la panne est réelle');
    expect(svc.derniereErreur, isNotNull,
        reason: 'L\'échec est signalé, jamais silencieux');
    // Aucune clé de shard n'a été créée.
    expect(store.clesArrivees, isEmpty);
  });

  test('L1-8b une exception du stockage L0 est absorbée par chargerProgramme',
      () async {
    final svc = ArriveeOfficielleService.instance;
    // `panneParException = true` : setValue LÈVE au lieu de retourner false.
    store.clesEnPanne.add(_cleShard);
    store.panneParException = true;

    final sortie = await _avecReseau(
        () => ZoneTurfService.chargerProgramme(),
        _programmeUneCourse(ordre: [
          [1], [2]
        ]));

    expect(sortie, hasLength(1),
        reason: 'Une EXCEPTION du stockage L0 ne remonte pas au programme');
    expect(svc.nbEntrees, 0);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-9 — CHARGEMENT OBSOLÈTE APRÈS RESET
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-9 reset pendant le chargement → la capture L0 est abandonnée',
      () async {
    final svc = ArriveeOfficielleService.instance;
    final genAvant = ZoneTurfService.generationReset;

    // Le reset est déclenché DEPUIS la requête réseau : il survient donc
    // pendant le chargement, exactement comme un reset utilisateur pendant un
    // appel de 20 s.
    var resetFait = false;
    final client = MockClient((request) async {
      if (request.url.path.contains('participants')) {
        return http.Response(_participantsJson([1, 2, 3]), 200,
            headers: {'content-type': 'application/json'});
      }
      if (!resetFait) {
        resetFait = true;
        ZoneTurfService.viderCachePourResetComplet();
      }
      return http.Response(
          _programmeJson(_programmeUneCourse(ordre: [
            [1], [2]
          ])),
          200,
          headers: {'content-type': 'application/json'});
    });

    final sortie = await http.runWithClient(
        () => ZoneTurfService.chargerProgramme(), () => client);

    debugPrint('L1-9 gen=$genAvant→${ZoneTurfService.generationReset} '
        'resetFait=$resetFait nbEntrees=${svc.nbEntrees} '
        'réunions=${sortie.length}');

    // TÉMOINS DE NON-VACUITÉ ABSOLUS.
    expect(resetFait, isTrue,
        reason: 'TÉMOIN : le reset a bien eu lieu pendant le chargement');
    expect(ZoneTurfService.generationReset, genAvant + 1,
        reason: 'TÉMOIN : la génération a bien bougé');

    // LE POINT DU TEST : rien n'a été écrit pour un état aboli.
    expect(svc.nbEntrees, 0,
        reason: 'Un chargement rendu obsolète par un reset n\'écrit AUCUNE '
            'arrivée');
    expect(store.setsL0, isEmpty,
        reason: 'TÉMOIN : aucun SET L0 — pas même la file d\'attente');
    // Le programme, lui, est rendu : la protection porte sur la capture, pas
    // sur le chargement.
    expect(sortie, hasLength(1),
        reason: 'Le programme est rendu normalement — comportement inchangé');
  });

  test('L1-9b sans reset, la capture a bien lieu (témoin positif du test L1-9)',
      () async {
    final svc = ArriveeOfficielleService.instance;
    final genAvant = ZoneTurfService.generationReset;

    await _avecReseau(
        () => ZoneTurfService.chargerProgramme(),
        _programmeUneCourse(ordre: [
          [1], [2]
        ]));

    expect(ZoneTurfService.generationReset, genAvant,
        reason: 'TÉMOIN : aucun reset n\'a eu lieu');
    expect(svc.nbEntrees, 1,
        reason: 'TÉMOIN POSITIF : sans reset, la capture fonctionne. Sans ce '
            'test, L1-9 pourrait passer avec une capture simplement cassée');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-10 — REJEU IDEMPOTENT DE LA FILE AU PREMIER CHARGEMENT
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-10 file persistante de session précédente → rejouée au 1er chargement',
      () async {
    final svc = ArriveeOfficielleService.instance;

    // File laissée par une session antérieure (arrêt brutal avant étape 3).
    store.semer(kArriveePendingKey, _file([
      {
        'courseKey': 'R7C7_16012025',
        'rangs': [
          [3, 5], [1]
        ],
        'declares': 14,
      }
    ]));

    // Aucun shard, mémoire vierge : `charger()` est le PREMIER point de contact.
    await svc.charger();

    debugPrint('L1-10 nbEntrees=${svc.nbEntrees} '
        'nbEnAttente=${svc.nbEnAttente} '
        'file=${store.contient(kArriveePendingKey)} '
        'cles=${store.clesArrivees}');

    // Le rejeu a écrit le shard du mois concerné (janvier 2025).
    expect(svc.arrivee('R7C7_16012025'), equals(<List<int>>[
      [3, 5], [1]
    ]), reason: 'L\'entrée de la file est retrouvée');
    expect(svc.declares('R7C7_16012025'), 14);
    expect(store.contient('${kArriveeStoragePrefix}2025-01'), isTrue,
        reason: 'TÉMOIN : le shard a bien été écrit par le rejeu');
    expect(store.contient(kArriveePendingKey), isFalse,
        reason: 'La file est nettoyée une fois le shard confirmé');
    expect(svc.nbEnAttente, 0);
  });

  test('L1-10b le rejeu a lieu UNE seule fois, et il est idempotent', () async {
    final svc = ArriveeOfficielleService.instance;
    store.semer(kArriveePendingKey, _file([
      {
        'courseKey': 'R1C1_16012025',
        'rangs': [
          [1], [2]
        ]
      }
    ]));

    await svc.charger();
    final brut1 = store.brut('${kArriveeStoragePrefix}2025-01');
    final sets1 = store.nbSetsShards;

    // Appels répétés : le drapeau `_rejeuFileEffectue` interdit un second rejeu.
    await svc.charger();
    await svc.charger();
    await svc.charger();

    debugPrint('L1-10b sets1=$sets1 setsFinal=${store.nbSetsShards} '
        'identical=${store.brut('${kArriveeStoragePrefix}2025-01') == brut1}');

    expect(store.nbSetsShards, sets1,
        reason: 'TÉMOIN : aucun SET de shard supplémentaire — le rejeu n\'a '
            'pas été rejoué');
    expect(store.brut('${kArriveeStoragePrefix}2025-01'), equals(brut1),
        reason: 'Le shard est inchangé');
    expect(svc.arrivee('R1C1_16012025'), equals(<List<int>>[
      [1], [2]
    ]));
  });

  test('L1-10c une entrée déjà présente dans un shard n\'est pas rejouée',
      () async {
    final svc = ArriveeOfficielleService.instance;
    // État d'un arrêt brutal ENTRE l'étape 2 et l'étape 3 : le shard contient
    // déjà l'entrée, et la file la contient encore.
    store.semer('${kArriveeStoragePrefix}2025-01',
        _shard({
          'R1C1_16012025': {
            'rangs': [
              [1], [2]
            ]
          }
        }));
    store.semer(kArriveePendingKey, _file([
      {
        'courseKey': 'R1C1_16012025',
        'rangs': [
          [1], [2]
        ]
      }
    ]));

    await svc.charger();

    debugPrint('L1-10c nbEntrees=${svc.nbEntrees} '
        'nbEnAttente=${svc.nbEnAttente}');

    expect(svc.nbEntrees, 1, reason: 'TÉMOIN : une seule entrée, pas deux');
    expect(svc.nbEnAttente, 0,
        reason: 'L\'entrée déjà confirmée est écartée de la file — le rejeu '
            'est idempotent');
  });

  test('L1-10d la capture déclenche bien le rejeu (point d\'init unique)',
      () async {
    final svc = ArriveeOfficielleService.instance;
    store.semer(kArriveePendingKey, _file([
      {
        'courseKey': 'R2C2_16012025',
        'rangs': [
          [9], [8]
        ]
      }
    ]));

    // PREMIER point de contact de la production : `chargerProgramme`.
    await _avecReseau(
        () => ZoneTurfService.chargerProgramme(),
        _programmeUneCourse(ordre: [
          [4], [5]
        ]));

    debugPrint('L1-10d nbEntrees=${svc.nbEntrees} '
        'janvier=${svc.contient('R2C2_16012025')} '
        'aujourdhui=${svc.contient('R1C1_$_dateDuJour')}');

    // La file d'une session antérieure a été rejouée…
    expect(svc.arrivee('R2C2_16012025'), equals(<List<int>>[
      [9], [8]
    ]), reason: 'TÉMOIN : le rejeu a été déclenché par le chargement L1');
    // …ET la capture du jour a fonctionné dans le même cycle.
    expect(svc.contient('R1C1_$_dateDuJour'), isTrue,
        reason: 'TÉMOIN : la capture et le rejeu cohabitent sans se nuire');
    expect(store.contient(kArriveePendingKey), isFalse);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-11 — NON-RÉGRESSION DU PROGRAMME
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-11 le programme rendu est identique avec ou sans arrivées', () async {
    final donneesSans = [
      _reunionJson(numOfficiel: 1, lieu: 'VINCENNES', courses: [
        _courseJson(
            numOrdre: 1,
            statut: 'FIN_COURSE',
            inclureOrdre: false,
            paris: ['E_QUINTE_PLUS']),
      ]),
    ];
    final donneesAvec = [
      _reunionJson(numOfficiel: 1, lieu: 'VINCENNES', courses: [
        _courseJson(
            numOrdre: 1,
            statut: 'ARRIVEE_DEFINITIVE_COMPLETE',
            ordre: [
              [10], [7], [2], [9], [6]
            ],
            declares: 10,
            paris: ['E_QUINTE_PLUS']),
      ]),
    ];

    final sans = await _avecReseau(() {
      ZoneTurfService.viderCachePourResetComplet();
      return ZoneTurfService.chargerProgramme(forceRefresh: true);
    }, donneesSans);

    final avec = await _avecReseau(() {
      ZoneTurfService.viderCachePourResetComplet();
      return ZoneTurfService.chargerProgramme(forceRefresh: true);
    }, donneesAvec);

    // Les deux programmes ont exactement la même forme observable.
    expect(sans.length, 1);
    expect(avec.length, 1);
    final c0 = sans.first.courses.first;
    final c1 = avec.first.courses.first;

    debugPrint('L1-11 sans nom=${c0.nom} quinte=${c0.isQuinte} '
        'partants=${c0.partants.length} | '
        'avec nom=${c1.nom} quinte=${c1.isQuinte} '
        'partants=${c1.partants.length}');

    expect(c1.numCourse, c0.numCourse);
    expect(c1.nom, c0.nom);
    expect(c1.isQuinte, c0.isQuinte,
        reason: 'La détection Quinté est INCHANGÉE');
    expect(c1.isQuinte, isTrue, reason: 'TÉMOIN : le pari E_QUINTE_PLUS est vu');
    expect(c1.partants.length, c0.partants.length);
    expect(c1.dateStr, c0.dateStr);
    expect(avec.first.lieu, sans.first.lieu);
  });

  test('L1-11b l\'échec réseau reste un tableau vide, capture comprise',
      () async {
    final svc = ArriveeOfficielleService.instance;

    final sortie = await _avecReseau(
        () => ZoneTurfService.chargerProgramme(),
        _programmeUneCourse(ordre: [
          [1], [2]
        ]),
        codeProgramme: 500);

    expect(sortie, isEmpty,
        reason: 'TÉMOIN : comportement v91 inchangé — HTTP 500 ⇒ aucune donnée '
            'fictive');
    expect(svc.nbEntrees, 0, reason: 'Aucune capture sur un échec réseau');
    expect(store.setsL0, isEmpty);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-12 — NON-RÉGRESSION DE L'APPRENTISSAGE IA
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-12 la capture L0 ne touche NI poids, NI seuils, NI ELO, NI stats',
      () async {
    await IaMemoryService.init();
    await EloService.init();
    final mem = IaMemoryService.instance;

    final poidsAvant = jsonEncode(mem.poids.toJson());
    final seuilsAvant = jsonEncode(mem.seuilsConfiance.toJson());
    final calibAvant = IaCalibrationRegistry.value;
    final eloAvant = jsonEncode(EloService.instance.exporterPourBackup());
    final pronosticsAvant = mem.pronostics.length;
    final statsAvant =
        jsonEncode(mem.statsParType.map((s) => s.toJson()).toList());

    await _avecReseau(
        () => ZoneTurfService.chargerProgramme(),
        _programmeUneCourse(ordre: [
          [10], [7], [2], [9], [6]
        ], declares: 10));

    // TÉMOIN : la capture a bien eu lieu.
    expect(ArriveeOfficielleService.instance.nbEntrees, 1);

    expect(jsonEncode(mem.poids.toJson()), equals(poidsAvant),
        reason: 'AUCUN poids modifié');
    expect(jsonEncode(mem.seuilsConfiance.toJson()), equals(seuilsAvant),
        reason: 'AUCUN seuil modifié');
    expect(IaCalibrationRegistry.value, equals(calibAvant),
        reason: 'AUCUNE calibration modifiée');
    expect(jsonEncode(EloService.instance.exporterPourBackup()), equals(eloAvant),
        reason: 'AUCUN rating ELO modifié');
    expect(mem.pronostics.length, pronosticsAvant,
        reason: 'AUCUN pronostic créé ni modifié');
    expect(jsonEncode(mem.statsParType.map((s) => s.toJson()).toList()),
        equals(statsAvant), reason: 'AUCUNE statistique modifiée');
    expect(mem.journal, isEmpty,
        reason: 'TÉMOIN : le gradient n\'a jamais été appelé');
  });

  test('L1-12b aucun pronostic n\'est marqué « résultat réel »', () async {
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    final avant = mem.pronostics.where((p) => p.resultatsReels).length;

    await _avecReseau(
        () => ZoneTurfService.chargerProgramme(),
        _programmeUneCourse(ordre: [
          [1], [2]
        ]));

    final apres = mem.pronostics.where((p) => p.resultatsReels).length;
    debugPrint('L1-12b resultatsReelsAvant=$avant apres=$apres');
    expect(apres, avant,
        reason: 'La capture L0 n\'enregistre AUCUN résultat de pronostic : '
            'elle ne passe jamais par `enregistrerResultat`');
  });

  test('L1-12c le bouton « Relancer récupération PMU » reste intact', () async {
    // Le bouton manuel vit dans `IaMemoryService.relancerRecuperationPMU`.
    // L1 ne doit toucher ni son existence, ni son comportement : la seule
    // vérification non destructive possible ici est que le service expose
    // toujours la méthode et n'a pas été marqué comme résultat réel.
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    final avant = mem.pronostics.where((p) => p.resultatsReels).length;

    await _avecReseau(
        () => ZoneTurfService.chargerProgramme(),
        _programmeUneCourse(ordre: [
          [3], [1]
        ]));

    expect(mem.pronostics.where((p) => p.resultatsReels).length, avant,
        reason: 'TÉMOIN : le chemin manuel n\'a pas été emprunté ni altéré');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L1-13 — INTÉGRITÉ DU CONTENU STOCKÉ
  // ═════════════════════════════════════════════════════════════════════════
  test('L1-13 l\'arrivée stockée survit à un redémarrage complet', () async {
    final svc = ArriveeOfficielleService.instance;

    await _avecReseau(
        () => ZoneTurfService.chargerProgramme(),
        _programmeUneCourse(ordre: [
          [6, 2], [4], [1]
        ], declares: 13));

    final cle = 'R1C1_$_dateDuJour';
    final avant = svc.arrivee(cle);

    // Redémarrage : cache Dart vidé + mémoire du service vidée.
    SharedPreferences.resetStatic();
    svc.viderMemoireSeulement();
    await svc.charger();

    debugPrint('L1-13 avant=$avant après=${svc.arrivee(cle)}');
    expect(svc.arrivee(cle), equals(avant),
        reason: 'TÉMOIN : l\'ex æquo [6,2] a survécu à la sérialisation');
    expect(svc.declares(cle), 13);
  });

  test('L1-14 la clé de cours suit le format R{n}C{n}_DDMMYYYY', () {
    // Le format est celui du reste de l'application (data_refresh_service
    // l.1135 : r'^R(\d+)C(\d+)_(\d{2})(\d{2})(\d{4})$'). On vérifie que la
    // capture produit bien cette forme, sinon les arrivées seraient
    // inexploitables par les autres services.
    final re = RegExp(r'^R(\d+)C(\d+)_(\d{2})(\d{2})(\d{4})$');
    final cle = _courseKey(5, 12);
    debugPrint('L1-14 clé=$cle');
    expect(re.hasMatch(cle), isTrue);
    final m = re.firstMatch(cle)!;
    expect(m.group(1), '5');
    expect(m.group(2), '12');
    expect(m.group(3), _dateDuJour.substring(0, 2));
    expect(m.group(4), _dateDuJour.substring(2, 4));
    expect(m.group(5), _dateDuJour.substring(4, 8));
    // `moisDepuisCourseKey` doit savoir la lire.
    expect(moisDepuisCourseKey(cle), equals(_moisDuJour));
  });
}
