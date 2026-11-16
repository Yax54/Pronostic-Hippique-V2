// ═══════════════════════════════════════════════════════════════════════════
//  L0 — CORRECTIFS : conflits de restauration + file d'attente durable
//
//  Ce que ces tests prouvent, et rien de plus :
//    C1-1  une arrivée identique est un DOUBLON, pas un conflit
//    C1-2  une arrivée divergente est un CONFLIT signalé, local conservé
//    C1-3  un conflit ne résout rien : ni écriture, ni fusion, ni suppression
//    C1-4  le local n'est jamais écrasé, y compris après redémarrage
//    C1-5  l'ex æquo compte : [4,7] et [7,4] sont différents
//    C2-1  la file d'attente survit à un redémarrage
//    C2-2  l'export de la file porte `courseKey` (réimportable)
//    C2-3  l'ordre d'écriture est file → shard → nettoyage
//    C2-4  le rejeu est idempotent (aucun doublon, aucun écrasement)
//    C2-5  compatibilité : un export SANS `courseKey` reste lisible
//    C2-6  un échec de shard laisse l'entrée dans la file durable
//    C2-7  la file survit à reinitialiserComplet()
//    C2-8  la file est exportée même écrite par une session précédente
//    C2-9  une file illisible est conservée intacte
//    NR    non-régression : poids, seuils, ELO, stats, pronostics
//
//  Chaque test porte un TÉMOIN de non-vacuité.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:io'; // gzip

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart'
    show IaCalibrationRegistry;
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Store en mémoire avec politique de panne et journal des SET.
// ───────────────────────────────────────────────────────────────────────────
class StoreEspion extends SharedPreferencesStorePlatform {
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

  int get nbSetsArrivees =>
      sets.where((k) => k.startsWith(kArriveeStoragePrefix)).length;
  int nbSetsSur(String cle) => sets.where((k) => k == cle).length;
  bool get contientFile => contient(kArriveePendingKey);
}

late StoreEspion store;

void installerStore() {
  store = StoreEspion();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

/// Simule un redémarrage : cache Dart vidé + mémoire du service vidée.
Future<void> redemarrer(ArriveeOfficielleService svc) async {
  SharedPreferences.resetStatic();
  svc.viderMemoireSeulement();
  await svc.charger();
}

/// Construit un shard mensuel encodé comme le service les écrit.
String shard(Map<String, dynamic> arrivees, {String mois = '2025-01'}) {
  final payload = <String, dynamic>{'v': 1, 'arrivees': arrivees};
  return base64Encode(gzip.encode(utf8.encode(jsonEncode(payload))));
}

/// Construit une file d'attente encodée comme le service l'écrit.
String fileEncodee(List<Map<String, dynamic>> entrees) {
  final payload = <String, dynamic>{'v': 1, 'arrivees': entrees};
  return base64Encode(gzip.encode(utf8.encode(jsonEncode(payload))));
}

void main() {
  setUp(() {
    installerStore();
    ArriveeOfficielleService.instance.viderMemoireSeulement();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  CORRECTIF 1 — CONFLITS
  // ═════════════════════════════════════════════════════════════════════════

  test('C1-1 arrivée IDENTIQUE : doublon, aucun conflit signalé', () async {
    final svc = ArriveeOfficielleService.instance;
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [4], [7], [2]
      ],
    ));

    final r = await svc.restaurerDepuisBackup({
      'version': 1,
      'shards': {
        'arrivee_officielle_complete_v1_2025-01': shard({
          'R1C1_16012025': {
            'rangs': [
              [4], [7], [2]
            ]
          },
        }),
      },
    });

    debugPrint('C1-1 r=$r');
    expect(r.entreesDejaPresentes, 1, reason: 'TÉMOIN : doublon compté');
    expect(r.conflits, isEmpty,
        reason: 'TÉMOIN : une arrivée identique n\'est PAS un conflit');
    expect(r.aDesConflits, isFalse);
    expect(r.entreesAjoutees, 0);
  });

  test('C1-2 arrivée DIVERGENTE : conflit signalé, local conservé', () async {
    final svc = ArriveeOfficielleService.instance;
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2], [3]
      ],
    ));

    final r = await svc.restaurerDepuisBackup({
      'version': 1,
      'shards': {
        'arrivee_officielle_complete_v1_2025-01': shard({
          'R1C1_16012025': {
            'rangs': [
              [9], [8], [7]
            ]
          },
        }),
      },
    });

    debugPrint('C1-2 r=$r');
    expect(r.aDesConflits, isTrue, reason: 'TÉMOIN : le conflit est signalé');
    expect(r.conflits, equals(<String>['R1C1_16012025']),
        reason: 'TÉMOIN : la courseKey du conflit est nommée');
    expect(r.entreesAjoutees, 0, reason: 'aucune écriture de la divergence');
  });

  test('C1-3 un conflit ne modifie RIEN sur le disque', () async {
    final svc = ArriveeOfficielleService.instance;
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2], [3]
      ],
    ));
    final avant = store.brut('arrivee_officielle_complete_v1_2025-01');
    final setsAvant = store.nbSetsArrivees;

    await svc.restaurerDepuisBackup({
      'version': 1,
      'shards': {
        'arrivee_officielle_complete_v1_2025-01': shard({
          'R1C1_16012025': {
            'rangs': [
              [9], [8], [7]
            ]
          },
        }),
      },
    });

    expect(store.brut('arrivee_officielle_complete_v1_2025-01'), equals(avant),
        reason: 'TÉMOIN : le shard est octet pour octet identique');
    expect(store.nbSetsArrivees, setsAvant,
        reason: 'TÉMOIN : aucun SET supplémentaire — pas de réécriture');
  });

  test('C1-4 après redémarrage, le local est toujours celui d\'origine',
      () async {
    final svc = ArriveeOfficielleService.instance;
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2], [3]
      ],
    ));
    await svc.restaurerDepuisBackup({
      'version': 1,
      'shards': {
        'arrivee_officielle_complete_v1_2025-01': shard({
          'R1C1_16012025': {
            'rangs': [
              [9], [8], [7]
            ]
          },
        }),
      },
    });

    await redemarrer(svc);
    expect(svc.arrivee('R1C1_16012025'), equals(<List<int>>[
      [1], [2], [3]
    ]), reason: 'TÉMOIN : la sauvegarde n\'a jamais écrasé le local');
  });

  test('C1-5 quantification : doublons et conflits enfin séparés', () async {
    final svc = ArriveeOfficielleService.instance;
    // 5 courses locales.
    for (var i = 1; i <= 5; i++) {
      await svc.enregistrer(EntreeArrivee(
        courseKey: 'R1C${i}_16012025',
        rangs: [
          [i], [i + 10]
        ],
      ));
    }

    // Sauvegarde : 2 divergentes (C1,C2), 1 identique (C3), 2 absentes (C6,C7).
    final r = await svc.restaurerDepuisBackup({
      'version': 1,
      'shards': {
        'arrivee_officielle_complete_v1_2025-01': shard({
          'R1C1_16012025': {
            'rangs': [
              [91], [92]
            ]
          },
          'R1C2_16012025': {
            'rangs': [
              [93], [94]
            ]
          },
          'R1C3_16012025': {
            'rangs': [
              [3], [13]
            ]
          },
          'R1C6_16012025': {
            'rangs': [
              [6], [16]
            ]
          },
          'R1C7_16012025': {
            'rangs': [
              [7], [17]
            ]
          },
        }),
      },
    });

    debugPrint('C1-5 r=$r conflits=${r.conflits}');
    expect(r.entreesAjoutees, 2, reason: 'C6 et C7 ajoutées');
    expect(r.conflits, equals(<String>['R1C1_16012025', 'R1C2_16012025']),
        reason: 'TÉMOIN : les 2 divergentes sont NOMMÉES');
    expect(r.entreesDejaPresentes, 3,
        reason: '1 doublon réel (C3) + 2 conflits, tous « déjà présents »');
    expect(r.conflits.length, lessThan(r.entreesDejaPresentes),
        reason: 'TÉMOIN : avant correctif, les 3 étaient indistinguables');
  });

  test('C1-6 l\'ordre d\'un ex æquo compte : [4,7] ≠ [7,4]', () {
    expect(
      ArriveeOfficielleService.memeArrivee(<List<int>>[
        [4, 7], [2]
      ], <List<int>>[
        [4, 7], [2]
      ]),
      isTrue,
    );
    expect(
      ArriveeOfficielleService.memeArrivee(<List<int>>[
        [4, 7]
      ], <List<int>>[
        [7, 4]
      ]),
      isFalse,
      reason: 'TÉMOIN : l\'ordre publié est un fait, non normalisé',
    );
    expect(
      ArriveeOfficielleService.memeArrivee(<List<int>>[
        [1], [2]
      ], <List<int>>[
        [1], [2], [3]
      ]),
      isFalse,
      reason: 'nombre de groupes différent → divergent',
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  CORRECTIF 2 — FILE D'ATTENTE DURABLE
  // ═════════════════════════════════════════════════════════════════════════

  test('C2-1 la file d\'attente survit à un redémarrage', () async {
    final svc = ArriveeOfficielleService.instance;
    // Échec programmé : l'entrée ne peut pas atteindre son shard.
    store.clesEnPanne.add('arrivee_officielle_complete_v1_2025-01');

    final res = await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2]
      ],
    ));
    debugPrint('C2-1 res=$res  file=${store.contientFile}');
    expect(res.succes, isFalse);
    expect(res.nbEnAttente, 1);
    expect(store.contientFile, isTrue,
        reason: 'TÉMOIN : la file existe sur le DISQUE, pas seulement en RAM');

    // Redémarrage : c'est ici que l'ancienne version perdait tout.
    await redemarrer(svc);

    debugPrint('C2-1 apres redemarrage nbEnAttente=${svc.nbEnAttente}');
    expect(svc.nbEnAttente, 1,
        reason: 'TÉMOIN : avant correctif, la file était vide après restart');
    expect(svc.clesEnAttente, equals(<String>['R1C1_16012025']));
    expect(svc.arrivee('R1C1_16012025'), equals(<List<int>>[
      [1], [2]
    ]), reason: 'l\'arrivée reste lisible depuis la file');
  });

  test('C2-1b rejeu après redémarrage : l\'entrée atteint enfin son shard',
      () async {
    final svc = ArriveeOfficielleService.instance;
    store.clesEnPanne.add('arrivee_officielle_complete_v1_2025-01');
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2]
      ],
    ));

    await redemarrer(svc);
    expect(svc.nbEnAttente, 1, reason: 'témoin : file reprise');

    // Le stockage redevient sain.
    store.clesEnPanne.clear();
    final rejeu = await svc.persisterEnAttente();
    debugPrint('C2-1b rejeu=$rejeu');
    expect(rejeu.succes, isTrue);
    expect(rejeu.nbEnAttente, 0);
    expect(store.contient('arrivee_officielle_complete_v1_2025-01'), isTrue,
        reason: 'TÉMOIN : le shard a bien été écrit');
    expect(store.contientFile, isFalse,
        reason: 'TÉMOIN : la file est nettoyée quand elle est vide');

    await redemarrer(svc);
    expect(svc.arrivee('R1C1_16012025'), equals(<List<int>>[
      [1], [2]
    ]), reason: 'la donnée est bien dans le shard, pas dans la file');
    expect(svc.nbEnAttente, 0);
  });

  test('C2-2 l\'export de la file porte courseKey (réimportable)', () async {
    final svc = ArriveeOfficielleService.instance;
    store.clesEnPanne.add('arrivee_officielle_complete_v1_2025-01');
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2]
      ],
      declares: 9,
    ));

    final export = await svc.exporterPourBackup();
    final file = export['enAttente'] as List;
    debugPrint('C2-2 enAttente=$file');
    expect(file, hasLength(1));
    final item = file.first as Map<String, dynamic>;
    expect(item['courseKey'], 'R1C1_16012025',
        reason: 'TÉMOIN : avant correctif, courseKey était ABSENTE');
    expect(item['rangs'], equals([
      [1], [2]
    ]));
    expect(item['declares'], 9);
  });

  test('C2-3 ordre imposé : file écrite AVANT le shard, nettoyée APRÈS',
      () async {
    final svc = ArriveeOfficielleService.instance;
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2]
      ],
    ));

    final idxFile1 = store.sets.indexOf(kArriveePendingKey);
    final idxShard = store.sets.indexWhere((k) =>
        k == 'arrivee_officielle_complete_v1_2025-01');
    debugPrint('C2-3 sets=${store.sets}');
    expect(idxFile1, isNonNegative,
        reason: 'TÉMOIN : la file est bien écrite');
    expect(idxShard, isNonNegative);
    expect(idxFile1, lessThan(idxShard),
        reason: 'TÉMOIN : file ÉCRITE avant le shard (secours en place)');
    // Le nettoyage (remove) vient après : la clé n'est plus là.
    expect(store.contientFile, isFalse,
        reason: 'la file est nettoyée en dernier, quand tout est écrit');
  });

  test('C2-4 rejeu idempotent : rejouer 3 fois ne change rien', () async {
    final svc = ArriveeOfficielleService.instance;
    store.clesEnPanne.add('arrivee_officielle_complete_v1_2025-01');
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2]
      ],
    ));
    await redemarrer(svc);
    store.clesEnPanne.clear();

    final r1 = await svc.persisterEnAttente();
    final brut1 = store.brut('arrivee_officielle_complete_v1_2025-01');
    final r2 = await svc.persisterEnAttente();
    final brut2 = store.brut('arrivee_officielle_complete_v1_2025-01');
    final r3 = await svc.persisterEnAttente();

    debugPrint('C2-4 r1=$r1 r2=$r2 r3=$r3');
    expect(r1.succes, isTrue);
    expect(r2.succes, isTrue, reason: 'rejouer une file vide est un no-op');
    expect(r3.succes, isTrue);
    expect(brut2, equals(brut1),
        reason: 'TÉMOIN : les octets du shard sont IDENTIQUES après rejeu');
    expect(svc.nbEnAttente, 0);
  });

  test('C2-4b rejeu idempotent : une entrée déjà écrite ne revient pas en file',
      () async {
    final svc = ArriveeOfficielleService.instance;
    // Situation simulée : arrêt brutal ENTRE l'étape 2 (shard écrit) et
    // l'étape 3 (file nettoyée). La file contient donc une entrée déjà écrite.
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2]
      ],
    ));
    store.semer(kArriveePendingKey, fileEncodee([
      {
        'courseKey': 'R1C1_16012025',
        'rangs': [
          [1], [2]
        ]
      }
    ]));

    await redemarrer(svc);
    debugPrint('C2-4b nbEnAttente=${svc.nbEnAttente}');
    expect(svc.nbEnAttente, 0,
        reason: 'TÉMOIN : une entrée déjà dans un shard n\'est PAS rejouée');
    expect(svc.arrivee('R1C1_16012025'), equals(<List<int>>[
      [1], [2]
    ]));
  });

  test('C2-5 compatibilité : un export SANS courseKey reste lisible', () async {
    final svc = ArriveeOfficielleService.instance;
    // Format d'export ANTÉRIEUR au correctif 2 : aucune courseKey.
    final r = await svc.restaurerDepuisBackup({
      'version': 1,
      'shards': {
        'arrivee_officielle_complete_v1_2025-01': shard({
          'R1C1_16012025': {
            'rangs': [
              [5], [6]
            ]
          },
        }),
      },
      'enAttente': [
        {
          'rangs': [
            [3], [4]
          ],
          'declares': 9
        }
      ],
    });

    debugPrint('C2-5 r=$r');
    expect(r.succes, isTrue, reason: 'TÉMOIN : la sauvegarde reste acceptée');
    expect(svc.arrivee('R1C1_16012025'), equals(<List<int>>[
      [5], [6]
    ]), reason: 'le shard est restauré normalement');
    // L'entrée de file sans courseKey n'est PAS devinée : elle est ignorée.
    expect(svc.nbEnAttente, 0,
        reason: 'TÉMOIN : pas de courseKey → non rejouable, jamais inventée');
  });

  test('C2-6 un échec de shard laisse l\'entrée dans la file durable', () async {
    final svc = ArriveeOfficielleService.instance;
    store.clesEnPanne.add('arrivee_officielle_complete_v1_2025-01');

    final res = await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2]
      ],
    ));
    expect(res.succes, isFalse);
    expect(res.nbEnAttente, 1);

    // La file est sur le DISQUE, pas seulement en RAM.
    final brut = store.brut(kArriveePendingKey);
    expect(brut, isNotNull,
        reason: 'TÉMOIN : sans persistance de file, cette clé serait absente');
    final decode = utf8.decode(gzip.decode(base64Decode(brut! as String)));
    expect(decode, contains('R1C1_16012025'));
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C2-7 — FILE D'ATTENTE × reinitialiserComplet() × REJEU AUTOMATIQUE (L1)
  //
  //  HISTORIQUE DE CETTE ASSERTION : la version d'origine terminait par
  //  `expect(svc.nbEnAttente, 1)` après redémarrage. Elle décrivait l'ANCIEN
  //  comportement — une file chargée mais JAMAIS rejouée automatiquement.
  //  L1 ajoute le rejeu au premier chargement : la file est désormais
  //  transférée dans son shard puis vidée. L'assertion mesurait donc
  //  l'ABSENCE du rejeu, pas la survie de la file.
  //
  //  CAUSE DE L'ÉCHEC, MESURÉE (sonde de causalité, 16/11) :
  //    avant reset        : file=true  nbEnAttente=1 shards=[2025-01]
  //    juste après reset  : file=true  nbEnAttente=1 shards=[2025-01] intacts
  //    après redémarrage  : file=false nbEnAttente=0 shards=[2025-01,2025-02]
  //    intégrité          : janvier=[[1],[2]] février=[[3],[4]] total=2
  //   2e redémarrage      : total=2, setsShards inchangé, février identique
  //   BILAN              : perteDeDonnee=false, janvier octet pour octet
  //                        identique avant/après
  //  → L'échec ne traduit AUCUNE perte : le rejeu a écrit l'entrée puis
  //    nettoyé la file, exactement comme spécifié en L1.
  //
  //  CETTE VERSION N'AFFAIBLIT RIEN : elle conserve les deux garanties
  //  d'origine (file et shards préservés par le reset) et ajoute cinq
  //  vérifications que l'ancienne version ne pouvait pas faire :
  //    1. file conservée immédiatement après reinitialiserComplet()
  //    2. rejeu automatique au redémarrage → entrée transférée dans son shard
  //    3. arrivées intégralement conservées, EX ÆQUO COMPRIS
  //    4. file vidée UNIQUEMENT après un rejeu réussi
  //    5. nouveau redémarrage → ni doublon, ni écriture inutile
  //    6. les autres shards déjà présents restent intacts
  // ═════════════════════════════════════════════════════════════════════════
  test('C2-7 file d\'attente : survit au reset, puis rejouée sans perte',
      () async {
    const kJan = 'arrivee_officielle_complete_v1_2025-01';
    const kFev = 'arrivee_officielle_complete_v1_2025-02';

    await IaMemoryService.init();
    final svc = ArriveeOfficielleService.instance;

    // Une arrivée écrite normalement + une arrivée bloquée en file.
    // L'arrivée bloquée porte un EX ÆQUO : c'est lui qui doit traverser le
    // rejeu intact (point 3).
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2]
      ],
    ));
    store.clesEnPanne.add(kFev);
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R2C1_05022025',
      rangs: [
        [3, 5], [4]
      ],
      declares: 11,
    ));

    // ── TÉMOINS DE PRÉPARATION ───────────────────────────────────────────
    expect(store.contientFile, isTrue, reason: 'témoin : file peuplée');
    expect(svc.nbEnAttente, 1, reason: 'témoin : 1 entrée en attente en RAM');
    expect(store.clesArrivees, equals(<String>['flutter.$kJan']),
        reason: 'témoin : seule janvier a pu être écrite (février en panne)');
    final clesAvant = store.clesArrivees;
    final brutJanAvant = store.brut(kJan);
    final setsAvantReset = store.nbSetsArrivees;

    // ══ POINT 1 + POINT 6 — après reinitialiserComplet() ═════════════════
    await BackupService.instance.reinitialiserComplet();

    debugPrint('C2-7 après reset : file=${store.contientFile} '
        'cles=${store.clesArrivees} RAM.nbEnAttente=${svc.nbEnAttente} '
        'sets=${store.nbSetsArrivees}');

    expect(store.clesArrivees, equals(clesAvant),
        reason: 'POINT 6 : les shards mensuels sont conservés par le reset');
    expect(store.contientFile, isTrue,
        reason: 'POINT 1 / TÉMOIN CRITIQUE : la file survit au reset — '
            'sinon des arrivées non écrites seraient perdues');
    expect(svc.nbEnAttente, 1,
        reason: 'POINT 1 : la RAM n\'est pas vidée de la file par le reset');
    expect(store.nbSetsArrivees, setsAvantReset,
        reason: 'TÉMOIN : le reset n\'écrit AUCUN shard');

    // ══ POINT 4 — un rejeu qui ÉCHOUE ne vide PAS la file ════════════════
    // Février est toujours en panne : le rejeu automatique du redémarrage
    // doit échouer, et l'entrée doit RESTER dans la file.
    await redemarrer(svc);

    debugPrint('C2-7 rejeu en échec : file=${store.contientFile} '
        'RAM.nbEnAttente=${svc.nbEnAttente} '
        'fevrier=${store.contient(kFev)}');

    expect(store.contient(kFev), isFalse,
        reason: 'TÉMOIN : la panne est réelle, le shard n\'a pas été écrit');
    expect(store.contientFile, isTrue,
        reason: 'POINT 4 : la file est vidée UNIQUEMENT après un rejeu '
            'RÉUSSI. Un rejeu en échec la laisse intacte — aucune donnée '
            'n\'est abandonnée');
    expect(svc.nbEnAttente, 1,
        reason: 'POINT 4 : l\'entrée reste en attente après un échec');
    expect(svc.arrivee('R2C1_05022025'), equals(<List<int>>[
      [3, 5], [4]
    ]), reason: 'POINT 3 : l\'entrée est toujours lisible, ex æquo compris');

    // ══ POINT 2 + POINT 3 — rejeu RÉUSSI au redémarrage suivant ══════════
    store.clesEnPanne.clear();
    await redemarrer(svc);

    debugPrint('C2-7 rejeu réussi : file=${store.contientFile} '
        'RAM.nbEnAttente=${svc.nbEnAttente} '
        'cles=${store.clesArrivees} total=${svc.nbEntrees}');

    expect(store.contient(kFev), isTrue,
        reason: 'POINT 2 : le rejeu a transféré l\'entrée dans son shard '
            'mensuel');
    expect(store.contientFile, isFalse,
        reason: 'POINT 2 : la file est nettoyée une fois le shard confirmé');
    expect(svc.nbEnAttente, 0,
        reason: 'POINT 2 : plus rien en attente');
    expect(svc.arrivee('R2C1_05022025'), equals(<List<int>>[
      [3, 5], [4]
    ]), reason: 'POINT 3 : l\'ex æquo [3,5] a traversé la sérialisation '
        'intact — il n\'a pas été aplati en [3],[5]');
    expect(svc.declares('R2C1_05022025'), 11,
        reason: 'POINT 3 : les métadonnées suivent l\'arrivée');
    expect(svc.nbEntrees, 2, reason: 'POINT 3 : les deux arrivées coexistent');

    // ══ POINT 6 — les shards antérieurs sont intacts ═════════════════════
    expect(store.clesArrivees, equals(<String>['flutter.$kJan', 'flutter.$kFev']));
    expect(svc.arrivee('R1C1_16012025'), equals(<List<int>>[
      [1], [2]
    ]), reason: 'POINT 6 : janvier n\'a pas été altéré par le rejeu');
    expect(store.brut(kJan), equals(brutJanAvant),
        reason: 'POINT 6 : le shard de janvier est octet pour octet '
            'identique à avant le reset — le rejeu n\'y a pas touché');

    // ══ POINT 5 — un nouveau redémarrage ne change RIEN ══════════════════
    final setsAvant2e = store.nbSetsArrivees;
    final brutFevAvant = store.brut(kFev);
    await redemarrer(svc);

    debugPrint('C2-7 2e redémarrage : total=${svc.nbEntrees} '
        'sets=$setsAvant2e→${store.nbSetsArrivees} '
        'fevrierInchangé=${store.brut(kFev) == brutFevAvant}');

    expect(svc.nbEntrees, 2,
        reason: 'POINT 5 : aucun doublon — toujours 2 entrées, pas 3 ni 4');
    expect(store.nbSetsArrivees, setsAvant2e,
        reason: 'POINT 5 : aucune écriture INUTILE — la file étant vide, '
            'le rejeu ne s\'exécute pas du tout');
    expect(store.brut(kFev), equals(brutFevAvant),
        reason: 'POINT 5 : le shard de février est inchangé');
    expect(store.contientFile, isFalse,
        reason: 'POINT 5 : aucune file fantôme recréée');
  });

  test('C2-8 la file est exportée même écrite par une session précédente',
      () async {
    final svc = ArriveeOfficielleService.instance;
    // File laissée par une session antérieure, jamais chargée en mémoire.
    store.semer(kArriveePendingKey, fileEncodee([
      {
        'courseKey': 'R1C9_16012025',
        'rangs': [
          [7], [8]
        ]
      }
    ]));

    final export = await svc.exporterPourBackup();
    final file = export['enAttente'] as List;
    debugPrint('C2-8 enAttente=$file');
    expect(file, hasLength(1),
        reason: 'TÉMOIN : sans lecture du disque, la file serait vide');
    expect((file.first as Map)['courseKey'], 'R1C9_16012025');
  });

  test('C2-8b aller-retour complet : export → restauration sur base vide',
      () async {
    final svc = ArriveeOfficielleService.instance;
    store.clesEnPanne.add('arrivee_officielle_complete_v1_2025-01');
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2]
      ],
      declares: 8,
    ));

    final export = await svc.exporterPourBackup();
    expect((export['enAttente'] as List), hasLength(1),
        reason: 'témoin : la file non écrite est dans l\'export');

    // Nouvelle installation : stockage vidé.
    installerStore();
    svc.viderMemoireSeulement();

    final r = await svc.restaurerDepuisBackup(export);
    debugPrint('C2-8b r=$r');
    expect(r.succes, isTrue,
        reason: 'TÉMOIN : la file exportée est réimportable');
    expect(svc.arrivee('R1C1_16012025'), equals(<List<int>>[
      [1], [2]
    ]), reason: 'la donnée a bien traversé la sauvegarde');
    expect(svc.declares('R1C1_16012025'), 8);
  });

  test('C2-9 une file illisible est conservée intacte', () async {
    final svc = ArriveeOfficielleService.instance;
    store.semer(kArriveePendingKey, 'PAS_DU_BASE64_GZIP');

    await svc.charger();
    debugPrint('C2-9 err=${svc.derniereErreur}');
    expect(svc.nbEnAttente, 0, reason: 'rien n\'est deviné');
    expect(store.brut(kArriveePendingKey), 'PAS_DU_BASE64_GZIP',
        reason: 'TÉMOIN : la clé n\'est ni écrasée ni supprimée');
  });

  test('C2-10 une entrée en file est prioritaire sur le shard pour arriver()',
      () async {
    final svc = ArriveeOfficielleService.instance;
    store.semer(kArriveePendingKey, fileEncodee([
      {
        'courseKey': 'R1C1_16012025',
        'rangs': [
          [3], [4]
        ]
      }
    ]));
    await svc.charger();
    expect(svc.arrivee('R1C1_16012025'), equals(<List<int>>[
      [3], [4]
    ]));
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  NON-RÉGRESSION
  // ═════════════════════════════════════════════════════════════════════════

  test('NR-1 poids, seuils, calibration et journal strictement inchangés',
      () async {
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    final poidsAvant = jsonEncode(mem.poids.toJson());
    final seuilsAvant = jsonEncode(mem.seuilsConfiance.toJson());
    final calibAvant = IaCalibrationRegistry.value;

    store.clesEnPanne.add('arrivee_officielle_complete_v1_2025-01');
    final svc = ArriveeOfficielleService.instance;
    await svc.enregistrerGroupe(<EntreeArrivee>[
      for (var i = 1; i <= 5; i++)
        EntreeArrivee(
          courseKey: 'R1C${i}_16012025',
          rangs: [
            [i], [i + 1], [i + 2]
          ],
        ),
    ]);
    store.clesEnPanne.clear();
    await svc.persisterEnAttente();

    expect(jsonEncode(mem.poids.toJson()), equals(poidsAvant),
        reason: 'TÉMOIN : aucun poids modifié');
    expect(jsonEncode(mem.seuilsConfiance.toJson()), equals(seuilsAvant),
        reason: 'aucun seuil modifié');
    expect(IaCalibrationRegistry.value, equals(calibAvant));
    expect(mem.journal, isEmpty,
        reason: 'TÉMOIN : le gradient n\'a jamais été appelé');
  });

  test('NR-2 ELO, pronostics et statistiques strictement inchangés', () async {
    await IaMemoryService.init();
    await EloService.init();
    final mem = IaMemoryService.instance;
    final eloAvant = jsonEncode(EloService.instance.exporterPourBackup());
    final pronosticsAvant = mem.pronostics.length;
    final statsAvant =
        jsonEncode(mem.statsParType.map((s) => s.toJson()).toList());

    store.clesEnPanne.add('arrivee_officielle_complete_v1_2025-01');
    final svc = ArriveeOfficielleService.instance;
    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2]
      ],
    ));
    store.clesEnPanne.clear();
    await svc.persisterEnAttente();

    expect(jsonEncode(EloService.instance.exporterPourBackup()), equals(eloAvant),
        reason: 'TÉMOIN : ELO jamais recalculé');
    expect(mem.pronostics.length, pronosticsAvant);
    expect(jsonEncode(mem.statsParType.map((s) => s.toJson()).toList()),
        equals(statsAvant));
  });

  test('NR-3 la clé de file n\'est PAS un shard mensuel', () {
    expect(kArriveePendingKey.startsWith(kArriveeStoragePrefix), isFalse,
        reason: 'TÉMOIN : sinon la découverte dynamique la prendrait pour un mois');
    expect(moisDepuisCleStockage(kArriveePendingKey), isNull);
  });

  test('NR-4 la clé de file n\'est pas dans les listes de reset', () async {
    final svc = ArriveeOfficielleService.instance;
    store.semer(kArriveePendingKey, fileEncodee([
      {
        'courseKey': 'R1C1_16012025',
        'rangs': [
          [1], [2]
        ]
      }
    ]));

    // Les clés découvertes comme shards excluent la file.
    final cles = await svc.enumererClesSurStockage();
    expect(cles, isEmpty, reason: 'TÉMOIN : la file n\'est pas un shard');
  });

  test('NR-5 l\'export ne réinjecte rien dans l\'apprentissage', () async {
    await IaMemoryService.init();
    final mem = IaMemoryService.instance;
    final svc = ArriveeOfficielleService.instance;

    await svc.enregistrer(EntreeArrivee(
      courseKey: 'R1C1_16012025',
      rangs: [
        [1], [2]
      ],
    ));
    final export = await svc.exporterPourBackup();
    expect(export['shards'], isNotEmpty);

    expect(mem.pronostics, isEmpty,
        reason: 'TÉMOIN : exporter ne crée aucun pronostic');
    expect(mem.journal, isEmpty, reason: 'aucun apprentissage déclenché');
  });
}
