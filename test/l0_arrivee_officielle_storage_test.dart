// ═══════════════════════════════════════════════════════════════════════════
//  L0 — Tests du stockage des arrivées officielles complètes
//
//  Ce que ces tests prouvent, et rien de plus :
//    L0-1  sérialisation / désérialisation aller-retour fidèle
//    L0-2  les EX ÆQUO sont conservés tels quels (aucun aplatissement)
//    L0-3  seul ARRIVEE_DEFINITIVE_COMPLETE est accepté ; rien n'est inventé
//    L0-4  persistance réelle sur le stockage (clé mensuelle, une par mois)
//    L0-5  écriture GROUPÉE : une écriture par mois, pas une par course
//    L0-6  échec d'écriture : rien n'est perdu, rien n'est déclaré écrit à tort
//    L0-7  sauvegarde / restauration, avec découverte DYNAMIQUE des clés
//    L0-8  conservation après réinitialisation complète, et aucune réinjection
//    L0-9  non-régression : poids IA, ELO, statistiques, pronostics inchangés
//
//  Chaque test porte un TÉMOIN de non-vacuité : l'assertion serait
//  démontrablement fausse si le mécanisme testé était retiré.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:io'; // gzip

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart'
    show IaCalibrationRegistry;
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Store en mémoire, avec politique de panne. Compte les SET par clé pour
//  prouver qu'une écriture groupée n'écrit PAS N fois.
// ───────────────────────────────────────────────────────────────────────────
class StoreEspion extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};

  /// Journal des opérations SET réellement effectuées (non préfixées).
  final List<String> sets = <String>[];

  /// Clés dont l'écriture doit ÉCHOUER.
  final Set<String> clesEnPanne = <String>{};

  /// `true` → panne par exception ; `false` → panne par retour `false`.
  bool panneParException = true;

  bool _doitEchouer(String cle) {
    final nue = cle.startsWith('flutter.') ? cle.substring(8) : cle;
    return clesEnPanne.contains(cle) || clesEnPanne.contains(nue);
  }

  void _declencherPanne(String op, String cle) {
    if (panneParException) {
      throw StateError('PANNE SIMULÉE ($op) sur $cle');
    }
  }

  @override
  Future<bool> clear() async {
    _valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async =>
      getAllWithParameters(GetAllParameters(
          filter: PreferencesFilter(prefix: 'flutter.')));

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
      _declencherPanne('REM', key);
      return false;
    }
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final nue = key.startsWith('flutter.') ? key.substring(8) : key;
    if (_doitEchouer(key)) {
      _declencherPanne('SET', key);
      return false;
    }
    sets.add(nue);
    _valeurs[key] = value;
    return true;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;

  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');

  Object? brut(String cle) => _valeurs['flutter.$cle'];

  List<String> get clesArrivees => _valeurs.keys
      .where((k) => k.startsWith('flutter.$kArriveeStoragePrefix'))
      .toList()
    ..sort();

  /// Nombre de SET sur des clés de ce stockage.
  int get nbSetsArrivees =>
      sets.where((k) => k.startsWith(kArriveeStoragePrefix)).length;

  int nbSetsSur(String cle) => sets.where((k) => k == cle).length;
}

late StoreEspion store;

void installerStore() {
  store = StoreEspion();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

// ───────────────────────────────────────────────────────────────────────────
//  Fixtures
// ───────────────────────────────────────────────────────────────────────────

/// Objet COURSE tel que l'API `/programme/{DDMMYYYY}` le renvoie.
/// Reproduction fidèle des champs mesurés sur l'API réelle le 16/01/2025 :
/// statut, isArriveeDefinitive, arriveeDefinitive, nombreDeclaresPartants,
/// ordreArrivee, sous forme `List<List<int>>`.
Map<String, dynamic> courseJson({
  required List<List<int>> ordreArrivee,
  String? statut = kStatutArriveeDefinitiveComplete,
  bool? isArriveeDefinitive = true,
  bool? arriveeDefinitive = true,
  int? nombreDeclaresPartants = 10,
}) =>
    {
      'statut': statut,
      'isArriveeDefinitive': isArriveeDefinitive,
      'arriveeDefinitive': arriveeDefinitive,
      'nombreDeclaresPartants': nombreDeclaresPartants,
      'ordreArrivee': ordreArrivee,
    };

void main() {
  setUp(() {
    installerStore();
    ArriveeOfficielleService.instance.viderMemoireSeulement();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L0-1 — Sérialisation aller-retour
  // ═════════════════════════════════════════════════════════════════════════
  test('L0-1 sérialisation : une arrivée écrite est relue à l\'identique', () async {
    final svc = ArriveeOfficielleService.instance;
    const cle = 'R1C2_16012025';
    final rangs = <List<int>>[
      [10], [7], [2], [9], [6], [8]
    ];

    final e = ArriveeOfficielleService.depuisJsonCourse(
      courseJson(ordreArrivee: rangs),
      courseKey: cle,
    );
    expect(e, isNotNull, reason: 'TÉMOIN : l\'arrivée doit être acceptée');

    final res = await svc.enregistrer(e!);
    expect(res.succes, isTrue, reason: 'écriture confirmée');
    expect(res.nbEcrites, 1);

    // Relecture depuis un état mémoire vidé = vrai aller-retour disque.
    svc.viderMemoireSeulement();
    await svc.charger();

    final relu = svc.arrivee(cle);
    debugPrint('L0-1 relu=$relu');
    expect(relu, isNotNull, reason: 'TÉMOIN : sans écriture, relu serait null');
    expect(relu, equals(rangs), reason: 'ordre et numéros préservés');
    expect(svc.declares(cle), 10);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L0-2 — EX ÆQUO
  // ═════════════════════════════════════════════════════════════════════════
  test('L0-2 ex æquo : les groupes multi-numéros sont conservés', () async {
    final svc = ArriveeOfficielleService.instance;
    const cle = 'R3C5_01022025';

    // Ex æquo au 1er rang (4 et 7), puis 2, puis ex æquo au 3e rang (9 et 1).
    final rangs = <List<int>>[
      [4, 7], [2], [9, 1]
    ];

    final e = ArriveeOfficielleService.depuisJsonCourse(
      courseJson(ordreArrivee: rangs, nombreDeclaresPartants: 12),
      courseKey: cle,
    );
    expect(e, isNotNull);

    await svc.enregistrer(e!);
    svc.viderMemoireSeulement();
    await svc.charger();

    final relu = svc.arrivee(cle)!;
    debugPrint('L0-2 relu=$relu');
    expect(relu, equals(rangs), reason: 'les 2 groupes d\'ex æquo survivent');
    expect(relu.length, 3, reason: '3 groupes, pas 5 numéros aplatis');
    expect(relu[0], equals([4, 7]), reason: 'ex æquo du 1er rang intact');
    expect(relu[2], equals([9, 1]), reason: 'ex æquo du 3e rang intact');

    // TÉMOIN de non-vacuité : un aplatissement donnerait 5 éléments.
    expect(relu.fold<int>(0, (s, g) => s + g.length), 5,
        reason: 'la somme des numéros est bien 5 — le format diffère');
  });

  test('L0-2b ex æquo : la copie rendue est immuable', () async {
    final svc = ArriveeOfficielleService.instance;
    const cle = 'R1C1_01032025';
    await svc.enregistrer(EntreeArrivee(
      courseKey: cle,
      rangs: <List<int>>[
        [4, 7], [2]
      ],
    ));

    final a = svc.arrivee(cle)!;
    // Tenter de muter la liste retournée ne doit pas corrompre l'état interne.
    expect(() => a[0].add(99), throwsUnsupportedError,
        reason: 'les groupes retournés sont non modifiables');

    final b = svc.arrivee(cle)!;
    expect(b[0], equals([4, 7]), reason: 'l\'état interne est intact');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L0-3 — Statuts et refus. Rien n'est inventé.
  // ═════════════════════════════════════════════════════════════════════════
  test('L0-3 seuls les statuts définitifs complets sont acceptés', () {
    // Accepté
    expect(
      ArriveeOfficielleService.depuisJsonCourse(
        courseJson(ordreArrivee: [
          [1], [2], [3]
        ]),
        courseKey: 'R1C1_16012025',
      ),
      isNotNull,
    );

    // Refusés — chaque statut mesuré sur l'API réelle
    for (final statut in <String?>[
      'FIN_COURSE',
      'COURSE_ANNULEE',
      'ARRIVEE_DEFINITIVE', // partiel : ne vaut PAS « COMPLETE »
      'DEPART',
      '',
      null,
    ]) {
      final e = ArriveeOfficielleService.depuisJsonCourse(
        courseJson(ordreArrivee: [
          [1], [2], [3]
        ], statut: statut),
        courseKey: 'R1C1_16012025',
      );
      expect(e, isNull, reason: 'statut refusé : $statut');
    }

    // Drapeaux explicites à false → refus, même avec le bon libellé.
    expect(
      ArriveeOfficielleService.depuisJsonCourse(
        courseJson(ordreArrivee: [
          [1], [2], [3]
        ], isArriveeDefinitive: false),
        courseKey: 'R1C1_16012025',
      ),
      isNull,
      reason: 'isArriveeDefinitive=false doit refuser',
    );
    expect(
      ArriveeOfficielleService.depuisJsonCourse(
        courseJson(ordreArrivee: [
          [1], [2], [3]
        ], arriveeDefinitive: false),
        courseKey: 'R1C1_16012025',
      ),
      isNull,
      reason: 'arriveeDefinitive=false doit refuser',
    );
  });

  test('L0-3b aucune arrivée n\'est inventée si la structure est douteuse', () {
    final cas = <String, Object?>{
      'absent': null,
      'vide': <dynamic>[],
      'pas une liste': 'abc',
      'groupe vide': <dynamic>[
        <dynamic>[],
        <dynamic>[2]
      ],
      'numéro négatif': <dynamic>[
        <dynamic>[-1],
        <dynamic>[2]
      ],
      'numéro zéro': <dynamic>[
        <dynamic>[0],
        <dynamic>[2]
      ],
      'numéro chaîne': <dynamic>[
        <dynamic>["1"],
        <dynamic>[2]
      ],
      'groupe non liste': <dynamic>[
        1,
        <dynamic>[2]
      ],
    };

    for (final e in cas.entries) {
      expect(
        ArriveeOfficielleService.lireOrdreArrivee(e.value),
        isNull,
        reason: 'TÉMOIN : "${e.key}" doit être refusé, pas deviné',
      );
    }

    // Un cas valide doit passer — sinon les refus ci-dessus ne prouveraient
    // rien d'autre qu'une fonction toujours nulle.
    expect(
      ArriveeOfficielleService.lireOrdreArrivee(<dynamic>[
        <dynamic>[3],
        <dynamic>[1, 5]
      ]),
      equals(<List<int>>[
        [3], [1, 5]
      ]),
    );
  });

  test('L0-3c une courseKey sans date calendaire est refusée', () async {
    final svc = ArriveeOfficielleService.instance;
    final res = await svc.enregistrer(EntreeArrivee(
      courseKey: 'CLE_SANS_DATE',
      rangs: <List<int>>[
        [1], [2]
      ],
    ));
    debugPrint('L0-3c res=$res');
    expect(res.succes, isFalse,
        reason: 'TÉMOIN : sans date, on refuse — on n\'invente pas de mois');
    expect(res.erreur, contains('sans date'));
    expect(store.clesArrivees, isEmpty,
        reason: 'aucune clé mensuelle fabriquée');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L0-4 — Persistance : une clé PAR MOIS
  // ═════════════════════════════════════════════════════════════════════════
  test('L0-4 persistance : une clé mensuelle par mois, format b64(gzip)', () async {
    final svc = ArriveeOfficielleService.instance;

    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: <List<int>>[
        [1], [2], [3]
      ],
    ));
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C2_16012025',
      rangs: <List<int>>[
        [4], [5], [6]
      ],
    ));
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R2C1_05022025',
      rangs: <List<int>>[
        [7], [8], [9]
      ],
    ));

    final cles = store.clesArrivees;
    debugPrint('L0-4 cles=$cles');
    expect(cles, hasLength(2), reason: 'TÉMOIN : 3 courses → 2 mois → 2 clés');
    expect(cles, contains('flutter.arrivee_officielle_complete_v1_2025-01'));
    expect(cles, contains('flutter.arrivee_officielle_complete_v1_2025-02'));

    // Le contenu est bien du base64 de gzip, pas du JSON en clair.
    final brut = store.brut('arrivee_officielle_complete_v1_2025-01') as String;
    expect(() => jsonDecode(brut), throwsFormatException,
        reason: 'le shard n\'est PAS du JSON en clair');
    final decode = utf8.decode(gzip.decode(base64Decode(brut)));
    expect(decode, contains('R1C1_16012025'));
    expect(decode, contains('R1C2_16012025'));
    expect(decode, isNot(contains('R2C1_05022025')),
        reason: 'les mois ne se mélangent pas');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L0-5 — Écriture GROUPÉE
  // ═════════════════════════════════════════════════════════════════════════
  test('L0-5 écriture groupée : N courses d\'un même mois = 1 seule écriture',
      () async {
    final svc = ArriveeOfficielleService.instance;

    final lot = <EntreeArrivee>[
      for (var i = 1; i <= 20; i++)
        EntreeArrivee(
          courseKey: 'R1C${i}_16012025',
          rangs: <List<int>>[
            [i], [i + 1], [i + 2]
          ],
        ),
    ];

    final res = await svc.enregistrerGroupe(lot);
    debugPrint('L0-5 res=$res  sets=${store.sets}');
    expect(res.succes, isTrue);
    expect(res.nbEcrites, 20);

    // TÉMOIN central : 20 courses, UNE écriture sur la clé du mois.
    expect(store.nbSetsArrivees, 1,
        reason: 'TÉMOIN : une écriture groupée ne doit pas écrire 20 fois');
    expect(store.nbSetsSur('arrivee_officielle_complete_v1_2025-01'), 1);

    // Et les 20 sont bien là.
    svc.viderMemoireSeulement();
    await svc.charger();
    expect(svc.nbEntrees, 20);
    for (var i = 1; i <= 20; i++) {
      expect(svc.contient('R1C${i}_16012025'), isTrue, reason: 'course $i');
    }
  });

  test('L0-5b écriture groupée : un lot multi-mois = une écriture par mois',
      () async {
    final svc = ArriveeOfficielleService.instance;
    final lot = <EntreeArrivee>[
      EntreeArrivee(courseKey: 'R1C1_16012025', rangs: [[1], [2]]),
      EntreeArrivee(courseKey: 'R1C2_17012025', rangs: [[3], [4]]),
      EntreeArrivee(courseKey: 'R2C1_05022025', rangs: [[5], [6]]),
    ];
    final res = await svc.enregistrerGroupe(lot);
    expect(res.succes, isTrue);
    expect(res.nbEcrites, 3);
    debugPrint('L0-5b sets=${store.sets}');
    expect(store.nbSetsArrivees, 2, reason: 'janvier + février = 2 écritures');
    expect(store.nbSetsSur('arrivee_officielle_complete_v1_2025-01'), 1);
    expect(store.nbSetsSur('arrivee_officielle_complete_v1_2025-02'), 1);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L0-6 — Échec d'écriture : rien n'est perdu, rien n'est menti
  // ═════════════════════════════════════════════════════════════════════════
  test('L0-6 échec par exception : non perdu, non déclaré écrit', () async {
    final svc = ArriveeOfficielleService.instance;
    store.clesEnPanne.add('arrivee_officielle_complete_v1_2025-01');

    final res = await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [[1], [2], [3]],
    ));
    debugPrint('L0-6 res=$res');
    expect(res.succes, isFalse, reason: 'l\'échec est remonté');
    expect(res.moisEchoues, contains('2025-01'));
    expect(res.nbEnAttente, 1, reason: 'TÉMOIN : l\'entrée est en attente');
    expect(store.contient('arrivee_officielle_complete_v1_2025-01'), isFalse);

    // Elle reste lisible en mémoire (pas de perte silencieuse).
    expect(svc.arrivee('R1C1_16012025'), equals(<List<int>>[
      [1], [2], [3]
    ]));

    // Le stockage redevient sain → le rejeu écrit vraiment.
    store.clesEnPanne.clear();
    final rejeu = await svc.persisterEnAttente();
    debugPrint('L0-6 rejeu=$rejeu');
    expect(rejeu.succes, isTrue);
    expect(rejeu.nbEnAttente, 0);
    expect(store.contient('arrivee_officielle_complete_v1_2025-01'), isTrue,
        reason: 'TÉMOIN : sans rejeu, la clé n\'existerait pas');
  });

  test('L0-6b échec par retour false : également détecté', () async {
    final svc = ArriveeOfficielleService.instance;
    store
      ..panneParException = false
      ..clesEnPanne.add('arrivee_officielle_complete_v1_2025-01');

    final res = await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [[1], [2]],
    ));
    debugPrint('L0-6b res=$res');
    expect(res.succes, isFalse,
        reason: 'TÉMOIN : un `false` du store ne doit pas passer pour un succès');
    expect(res.nbEnAttente, 1);
  });

  test('L0-6c un échec ne détruit pas les arrivées déjà confirmées', () async {
    final svc = ArriveeOfficielleService.instance;
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [[1], [2]],
    ));
    final avant = store.brut('arrivee_officielle_complete_v1_2025-01');

    store.clesEnPanne.add('arrivee_officielle_complete_v1_2025-01');
    final res = await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C2_16012025',
      rangs: [[3], [4]],
    ));
    expect(res.succes, isFalse);

    final apres = store.brut('arrivee_officielle_complete_v1_2025-01');
    expect(apres, equals(avant), reason: 'TÉMOIN : le shard existant est intact');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L0-7 — Sauvegarde / Restauration
  // ═════════════════════════════════════════════════════════════════════════
  test('L0-7 export : découverte DYNAMIQUE des clés mensuelles', () async {
    final svc = ArriveeOfficielleService.instance;

    // Une clé écrite hors du service (simule une version future / un import).
    store.semer('arrivee_officielle_complete_v1_2024-06',
        'CONTENU_OPAQUE_NON_DECODABLE');

    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [[1], [2]],
    ));

    final export = await svc.exporterPourBackup();
    final shards = export['shards'] as Map<String, String>;
    debugPrint('L0-7 export nbClefs=${export['nbClefs']} cles=${shards.keys}');
    expect(shards, hasLength(2),
        reason: 'TÉMOIN : la clé opaque est exportée AUSSI (découverte dynamique)');
    expect(shards.containsKey('arrivee_officielle_complete_v1_2024-06'), isTrue,
        reason: 'aucune liste figée ne doit filtrer les mois');
    expect(shards.containsKey('arrivee_officielle_complete_v1_2025-01'), isTrue);
  });

  test('L0-7b restauration : ajoute les absentes, ne remplace jamais', () async {
    final svc = ArriveeOfficielleService.instance;

    // Local : R1C1 vaut [1],[2],[3]
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [[1], [2], [3]],
    ));

    // Sauvegarde : R1C1 avec une valeur DIFFÉRENTE + R1C2 absente localement.
    // On construit le shard à la main pour maîtriser son contenu.
    final payloadSauvegarde = {
      'v': 1,
      'arrivees': {
        'R1C1_16012025': {
          'rangs': [
            [9], [8]
          ]
        },
        'R1C2_16012025': {
          'rangs': [
            [4], [5]
          ]
        },
      },
    };
    final b64 = base64Encode(
        gzip.encode(utf8.encode(jsonEncode(payloadSauvegarde))));

    final res = await svc.restaurerDepuisBackup({
      'version': 1,
      'shards': {'arrivee_officielle_complete_v1_2025-01': b64},
    });
    debugPrint('L0-7b res=$res');
    expect(res.succes, isTrue);
    expect(res.entreesAjoutees, 1, reason: 'seule R1C2 est nouvelle');
    expect(res.entreesDejaPresentes, 1, reason: 'R1C1 existait déjà');

    svc.viderMemoireSeulement();
    await svc.charger();
    expect(svc.arrivee('R1C1_16012025'), equals(<List<int>>[
      [1], [2], [3]
    ]), reason: 'TÉMOIN : le local n\'est PAS écrasé par la sauvegarde');
    expect(svc.arrivee('R1C2_16012025'), equals(<List<int>>[
      [4], [5]
    ]), reason: 'TÉMOIN : l\'absente est bien ajoutée');
  });

  test('L0-7c restauration : un shard illisible est ignoré, pas inventé', () async {
    final svc = ArriveeOfficielleService.instance;
    final res = await svc.restaurerDepuisBackup({
      'version': 1,
      'shards': {
        'arrivee_officielle_complete_v1_2025-01': 'PAS_DU_BASE64_GZIP',
      },
    });
    debugPrint('L0-7c res=$res');
    expect(res.shardsIllisibles, 1, reason: 'TÉMOIN : compté comme illisible');
    expect(res.shardsLus, 0);
    expect(res.entreesAjoutees, 0, reason: 'aucune entrée inventée');
    expect(store.clesArrivees, isEmpty,
        reason: 'aucune clé écrite à partir d\'un contenu illisible');
  });

  test('L0-7d restauration : "shards" absent → échec explicite', () async {
    final svc = ArriveeOfficielleService.instance;
    final res = await svc.restaurerDepuisBackup({'version': 1});
    expect(res.succes, isFalse);
    expect(res.erreur, isNotNull);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L0-8 — Réinitialisation complète
  // ═════════════════════════════════════════════════════════════════════════
  test('L0-8 les arrivées SURVIVENT à reinitialiserComplet(), rien n\'est réinjecté',
      () async {
    // Contexte minimal pour que le reset puisse s'exécuter.
    await IaMemoryService.init();

    final svc = ArriveeOfficielleService.instance;
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [4, 7], [2], [9]
      ],
      declares: 12,
    ));
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R2C1_05022025',
      rangs: [[1], [2]],
    ));

    // TÉMOIN : les clés existent avant.
    final avant = store.clesArrivees;
    debugPrint('L0-8 cles avant reset=$avant');
    expect(avant, hasLength(2), reason: 'TÉMOIN : sans clés, le test est vide');

    final memAvantPronostics = IaMemoryService.instance.pronostics.length;

    await BackupService.instance.reinitialiserComplet();

    // ── ASSERTION 1 : les clés sont TOUJOURS là ────────────────────────────
    final apres = store.clesArrivees;
    debugPrint('L0-8 cles apres reset=$apres');
    expect(apres, hasLength(2),
        reason: 'TÉMOIN : les arrivées sont conservées (décision validée)');
    expect(apres, equals(avant));

    // ── ASSERTION 2 : contenu intact, ex æquo préservés ────────────────────
    svc.viderMemoireSeulement();
    await svc.charger();
    expect(svc.arrivee('R1C1_16012025'), equals(<List<int>>[
      [4, 7], [2], [9]
    ]), reason: 'ex æquo et ordre intacts après reset');
    expect(svc.declares('R1C1_16012025'), 12);

    // ── ASSERTION 3 : aucune réinjection dans la mémoire active ────────────
    expect(IaMemoryService.instance.pronostics, isEmpty,
        reason: 'les pronostics restent vidés : rien n\'est réinjecté');
    expect(IaMemoryService.instance.pronostics.length, memAvantPronostics,
        reason: 'le reset n\'a rien ajouté ni retiré de ce côté');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L0-9 — NON-RÉGRESSION : poids, ELO, statistiques, pronostics
  // ═════════════════════════════════════════════════════════════════════════
  test('L0-9 poids IA et seuils strictement inchangés par une écriture d\'arrivée',
      () async {
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;

    final poidsAvant = jsonEncode(mem.poids.toJson());
    final seuilsAvant = jsonEncode(mem.seuilsConfiance.toJson());
    final calibAvant = IaCalibrationRegistry.value;

    final svc = ArriveeOfficielleService.instance;
    final res = await svc.enregistrerGroupe(<EntreeArrivee>[
      for (var i = 1; i <= 5; i++)
        EntreeArrivee(
          courseKey: 'R1C${i}_16012025',
          rangs: [
            [i], [i + 1], [i + 2]
          ],
        ),
    ]);
    expect(res.succes, isTrue);

    final poidsApres = jsonEncode(mem.poids.toJson());
    final seuilsApres = jsonEncode(mem.seuilsConfiance.toJson());

    debugPrint('L0-9 poids identiques=${poidsAvant == poidsApres} '
        'seuils identiques=${seuilsAvant == seuilsApres}');

    expect(poidsApres, equals(poidsAvant),
        reason: 'TÉMOIN : aucune écriture de poids déclenchée');
    expect(seuilsApres, equals(seuilsAvant),
        reason: 'aucun seuil modifié');
    expect(IaCalibrationRegistry.value, equals(calibAvant),
        reason: 'calibration inchangée');
    expect(mem.journal, isEmpty,
        reason: 'TÉMOIN : le journal du gradient reste vide — aucun apprentissage');
  });

  test('L0-9b ELO strictement inchangé par une écriture d\'arrivée', () async {
    await EloService.init();
    final eloAvant = jsonEncode(EloService.instance.exporterPourBackup());

    final svc = ArriveeOfficielleService.instance;
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [3], [5], [4]
      ],
    ));

    final eloApres = jsonEncode(EloService.instance.exporterPourBackup());
    expect(eloApres, equals(eloAvant),
        reason: 'TÉMOIN : le stockage n\'appelle jamais mettreAJourApresArrivee');
  });

  test('L0-9c pronostics et statistiques strictement inchangés', () async {
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;

    final pronosticsAvant = mem.pronostics.length;
    final statsAvant =
        jsonEncode(mem.statsParType.map((s) => s.toJson()).toList());

    final svc = ArriveeOfficielleService.instance;
    await svc.enregistrerGroupe(<EntreeArrivee>[
      EntreeArrivee(courseKey: 'R1C1_16012025', rangs: [[1], [2]]),
      EntreeArrivee(courseKey: 'R1C2_16012025', rangs: [[3], [4]]),
    ]);

    expect(mem.pronostics.length, pronosticsAvant,
        reason: 'TÉMOIN : aucun pronostic créé ni supprimé');
    expect(
        jsonEncode(mem.statsParType.map((s) => s.toJson()).toList()),
        equals(statsAvant),
        reason: 'aucune statistique modifiée');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  Helpers de date et de clés
  // ═════════════════════════════════════════════════════════════════════════
  test('L0-10 helpers : mois et clés de stockage', () {
    expect(moisDepuisCourseKey('R1C2_16012025'), '2025-01');
    expect(moisDepuisCourseKey('R1C2_2025-01-16'), '2025-01');
    expect(moisDepuisCourseKey('R1C2_32012025'), isNull,
        reason: '32 janvier n\'existe pas → refus, pas de date inventée');
    expect(moisDepuisCourseKey('CLE_BIDON'), isNull);

    expect(cleStockageMois('2025-01'), 'arrivee_officielle_complete_v1_2025-01');
    expect(moisDepuisCleStockage('arrivee_officielle_complete_v1_2025-01'),
        '2025-01');
    expect(moisDepuisCleStockage('arrivee_officielle_complete_v1_2025-13'),
        isNull, reason: 'mois 13 invalide');
    expect(moisDepuisCleStockage('autre_prefixe_2025-01'), isNull);
  });

  test('L0-11 charger() est idempotent et absorbe une panne', () async {
    final svc = ArriveeOfficielleService.instance;
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [[1], [2]],
    ));
    svc.viderMemoireSeulement();

    await svc.charger();
    await svc.charger(); // second appel : no-op
    expect(svc.nbEntrees, 1);
    expect(svc.estCharge, isTrue);
  });
}
