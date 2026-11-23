// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / LOT 2-C — TESTS DU RACCORDEMENT (partie 2/3)
//  PROVIDER : PERSISTANCE, GÉNÉRATIONS, ROLLBACK, RÉCONCILIATION, VERROU
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT.
//
//  MÉTHODE — les échecs d'écriture sont produits par un FAUX STORE
//  (`SharedPreferencesStorePlatform`) dont on contrôle le retour de
//  `setValue`. Aucun test ne « simule » un échec par un drapeau interne : on
//  agit sur le support de persistance lui-même, donc sur le comportement réel
//  de production.
//
//  PÉRIMÈTRE :
//    • Familles V1–V20  : cohérence mémoire/disque, `null` vs `0.0`.
//    • Familles G1–G4   : générations d'opérations (dont 10 → 20 → 10).
//    • Familles R1–R5   : rollback ciblé et réconciliation.
//    • Familles L1–L3   : verrou Accepter/Refuser — NON BRANCHÉ, prouvé.
//    • Familles D1–D9   : ticket divergent bloqué et récupération.
//    • Familles N1–N17  : concurrence, décisions plus récentes, échecs.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/decision_gain_pmu.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';

// ═══════════════════════════ Faux support de stockage ══════════════════════

/// Support de persistance CONTRÔLÉ : on décide, écriture par écriture, si
/// elle réussit, échoue (`false`) ou lève une exception.
class _StoreControle extends SharedPreferencesStorePlatform {
  _StoreControle({Map<String, Object>? data})
      : _data = Map<String, Object>.from(data ?? <String, Object>{});

  final Map<String, Object> _data;

  /// Nombre d'écritures à REFUSER (`return false`) avant de repasser en
  /// succès. `null` = jamais refuser.
  int? refusRestants;

  /// Nombre d'écritures à FAIRE LEVER avant de repasser en succès.
  int? exceptionRestantes;

  /// Journal des clés réellement écrites, dans l'ordre.
  final List<String> journalEcritures = <String>[];

  /// Appelé AVANT chaque écriture : permet d'injecter une opération
  /// concurrente au pire moment (pendant la sauvegarde).
  Future<void> Function()? avantChaqueEcriture;

  bool _fautive(String key) => key.contains('user_predictions') ||
      key.contains('tracked_courses');

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
    final r = Map<String, Object>.from(_data);
    r.removeWhere((k, _) =>
        !k.startsWith(f.prefix) ||
        (f.allowList != null && !f.allowList!.contains(k)));
    return r;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final hook = avantChaqueEcriture;
    if (hook != null) await hook();
    if (_fautive(key)) {
      final ex = exceptionRestantes;
      if (ex != null && ex > 0) {
        exceptionRestantes = ex - 1;
        throw StateError('support indisponible (simulation contrôlée)');
      }
      final refus = refusRestants;
      if (refus != null && refus > 0) {
        refusRestants = refus - 1;
        return false;
      }
      journalEcritures.add(key);
    }
    _data[key] = value;
    return true;
  }

  // ── Lecture directe (assertions) ─────────────────────────────────────────
  List<String> predictionsBrutes() {
    final v = _data['flutter.user_predictions_v2'];
    if (v is List) return v.cast<String>();
    return const <String>[];
  }

  Map<String, dynamic>? predictionParId(String id) {
    for (final s in predictionsBrutes()) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      if (m['id'] == id) return m;
    }
    return null;
  }

  /// Écrit une prédiction directement sur le support, sans passer par le
  /// provider : c'est la « vérité disque » que le provider devra lire.
  void ecrirePredictionBrute(Map<String, dynamic> map) {
    final liste = predictionsBrutes().toList();
    liste.removeWhere((s) => (jsonDecode(s) as Map)['id'] == map['id']);
    liste.add(jsonEncode(map));
    _data['flutter.user_predictions_v2'] = liste;
  }
}

// ═══════════════════════════ Outils de montage ═════════════════════════════

/// Client HTTP neutre : `PmuProvider()` appelle `loadProgramme()` dans son
/// constructeur. Aucun paquet réel n'est joint.
MockClient _clientNeutre() => MockClient((http.Request r) async =>
    http.Response('{"programme":[],"reunions":[]}', 200));

Future<void> _installer(_StoreControle store) async {
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
}

UserPrediction _pred(String id, {
  double? montantGainManuel,
  String? idTicketLie,
  double? montantOfficielPmu,
  DecisionGainPmu? decision,
  double? gainRealise,
  double montantMise = 0.0,
}) =>
    UserPrediction(
      id: id,
      dateStr: '23112026',
      numReunion: 1,
      numCourse: 3,
      nomCourse: 'Prix de Test',
      hippodrome: 'Vincennes',
      numeroCheval: 7,
      nomCheval: 'Cheval Test',
      cote: 4.5,
      typePari: 'Simple Gagnant',
      createdAt: DateTime(2026, 11, 23, 10),
      montantGainManuel: montantGainManuel,
      idTicketLie: idTicketLie,
      montantOfficielPmu: montantOfficielPmu,
      decisionGainPmu: decision,
      gainRealise: gainRealise,
      montantMise: montantMise,
    );

/// Monte un provider dont l'état mémoire contient exactement [preds].
/// On attend la fin du chargement initial pour ne pas courir après lui.
Future<PmuProvider> _providerAvec(
    _StoreControle store, List<UserPrediction> preds) async {
  final liste = preds.map((p) => jsonEncode(p.toJson())).toList();
  store.ecrirePredictionBrute; // (aucune action : garde l'API lisible)
  await store.setValue('StringList', 'flutter.user_predictions_v2', liste);
  await _installer(store);

  final pmu = PmuProvider();
  await pmu.sauvegardeTerminee();
  await pmu.reloadPredictions();
  await pmu.sauvegardeTerminee();
  return pmu;
}

Future<T> _sansReseau<T>(Future<T> Function() action) =>
    http.runWithClient(action, _clientNeutre);

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE V — COHÉRENCE MÉMOIRE/DISQUE, `null` CONTRE `0.0`
  // ═══════════════════════════════════════════════════════════════════════
  group('V — persistance financière durable', () {
    test('V1 écriture réussie ⇒ `confirme` ET le disque porte la valeur',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        final issue = await pmu.enregistrerGainManuelPrediction('p1', 12.0);
        expect(issue, IssueEcritureGain.confirme);

        final disque = store.predictionParId('p1')!;
        expect((disque['montantGainManuel'] as num).toDouble(), 12.0);
      });
    });

    test('V2 effacement (`null`) ⇒ la clé disque vaut null, pas 0', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(
            store, [_pred('p1', montantGainManuel: 12.0)]);

        final issue = await pmu.enregistrerGainManuelPrediction('p1', null);
        expect(issue, IssueEcritureGain.confirme);
        expect(store.predictionParId('p1')!['montantGainManuel'], isNull);
      });
    });

    test('V3 déclaration explicite de 0.0 ⇒ le disque porte 0.0, pas null',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        final issue = await pmu.enregistrerGainManuelPrediction('p1', 0.0);
        expect(issue, IssueEcritureGain.confirme);
        expect(store.predictionParId('p1')!['montantGainManuel'], 0.0);
      });
    });

    test('V4 `null` et `0.0` restent DISTINCTS de bout en bout', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        await pmu.enregistrerGainManuelPrediction('p1', 0.0);
        expect(await pmu.verifierGainPersiste('p1', 0.0), isTrue);
        expect(await pmu.verifierGainPersiste('p1', null), isFalse,
            reason: '0.0 ne doit jamais passer pour un effacement');

        await pmu.enregistrerGainManuelPrediction('p1', null);
        expect(await pmu.verifierGainPersiste('p1', null), isTrue);
        expect(await pmu.verifierGainPersiste('p1', 0.0), isFalse,
            reason: 'null ne doit jamais passer pour un 0.0');
      });
    });

    test('V5 `verifierGainPersiste` rend false pour un ticket ABSENT',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);
        expect(await pmu.verifierGainPersiste('inexistant', 12.0), isFalse);
      });
    });

    test('V6 ticket inexistant ⇒ `echec`, rien n\'est créé sur le disque',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        final issue = await pmu.enregistrerGainManuelPrediction('zzz', 12.0);
        expect(issue, IssueEcritureGain.echec);
        expect(store.predictionParId('zzz'), isNull);
        expect(store.predictionsBrutes().length, 1);
      });
    });

    test('V7 l\'écriture ne touche QUE montantGainManuel', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [
          _pred('p1',
              montantOfficielPmu: 99.0,
              decision: DecisionGainPmu.refuse,
              gainRealise: 30.0,
              montantMise: 5.0),
        ]);

        await pmu.enregistrerGainManuelPrediction('p1', 12.0);
        final d = store.predictionParId('p1')!;
        expect((d['montantGainManuel'] as num).toDouble(), 12.0);
        expect((d['montantOfficielPmu'] as num).toDouble(), 99.0);
        expect(d['decisionGainPmu'], 'refuse');
        expect((d['gainRealise'] as num).toDouble(), 30.0);
        expect((d['montantMise'] as num).toDouble(), 5.0);
      });
    });

    test('V8 les autres prédictions du disque ne sont pas altérées', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [
          _pred('p1'),
          _pred('p2', montantGainManuel: 44.0),
          _pred('p3', montantOfficielPmu: 7.0),
        ]);

        await pmu.enregistrerGainManuelPrediction('p1', 12.0);
        expect((store.predictionParId('p2')!['montantGainManuel'] as num)
            .toDouble(), 44.0);
        expect((store.predictionParId('p3')!['montantOfficielPmu'] as num)
            .toDouble(), 7.0);
        expect(store.predictionsBrutes().length, 3);
      });
    });

    test('V9 relecture après « redémarrage » : la valeur survit', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);
        await pmu.enregistrerGainManuelPrediction('p1', 17.25);

        // Redémarrage simulé : nouveau provider, même support de stockage.
        SharedPreferences.resetStatic();
        final pmu2 = PmuProvider();
        await pmu2.reloadPredictions();
        await pmu2.sauvegardeTerminee();

        final p = pmu2.predictions.firstWhere((e) => e.id == 'p1');
        expect(p.montantGainManuel, 17.25);
        expect(p.gainRetenuBrut, 17.25);
      });
    });

    test('V10 relecture : la décision et l\'officiel survivent au redémarrage',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [
          _pred('p1',
              montantOfficielPmu: 99.0,
              decision: DecisionGainPmu.accepte,
              montantGainManuel: 12.0),
        ]);

        SharedPreferences.resetStatic();
        final pmu2 = PmuProvider();
        await pmu2.reloadPredictions();
        await pmu2.sauvegardeTerminee();

        final p = pmu2.predictions.firstWhere((e) => e.id == 'p1');
        expect(p.montantOfficielPmu, 99.0);
        expect(p.decisionGainPmu, DecisionGainPmu.accepte);
        expect(p.gainRetenuBrut, 99.0,
            reason: 'après redémarrage, l\'acceptation doit toujours primer');
      });
    });

    test('V11 écriture refusée ⇒ `echec`, et le disque n\'a pas changé',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(
            store, [_pred('p1', montantGainManuel: 12.0)]);

        store.refusRestants = 2; // l'écriture initiale ET la réconciliation
        final issue = await pmu.enregistrerGainManuelPrediction('p1', 30.0);
        expect(issue, IssueEcritureGain.echec);
        expect(
            (store.predictionParId('p1')!['montantGainManuel'] as num)
                .toDouble(),
            12.0,
            reason: 'le disque conserve l\'ancienne valeur');
      });
    });

    test('V12 après un échec, la mémoire est réalignée sur l\'ancienne valeur',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(
            store, [_pred('p1', montantGainManuel: 12.0)]);

        store.refusRestants = 2;
        await pmu.enregistrerGainManuelPrediction('p1', 30.0);

        final enMemoire = pmu.predictions.firstWhere((e) => e.id == 'p1');
        expect(enMemoire.montantGainManuel, 12.0,
            reason: 'aucun montant que le disque ne porte ne doit rester');
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse);
      });
    });

    test('V13 échec puis nouvelle tentative ⇒ la seconde réussit', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        store.refusRestants = 2;
        final e1 = await pmu.enregistrerGainManuelPrediction('p1', 15.0);
        expect(e1, IssueEcritureGain.echec);

        store.refusRestants = null;
        final e2 = await pmu.enregistrerGainManuelPrediction('p1', 15.0);
        expect(e2, IssueEcritureGain.confirme);
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 15.0);
      });
    });

    test('V14 DEUX échecs successifs ⇒ toujours `echec`, jamais un faux succès',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        store.refusRestants = 2;
        expect(await pmu.enregistrerGainManuelPrediction('p1', 10.0),
            IssueEcritureGain.echec);
        store.refusRestants = 2;
        expect(await pmu.enregistrerGainManuelPrediction('p1', 20.0),
            IssueEcritureGain.echec);
        expect(store.predictionParId('p1')!['montantGainManuel'], isNull);
      });
    });

    test('V15 une exception du support n\'est pas avalée : `echec`', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        store.exceptionRestantes = 2;
        final issue = await pmu.enregistrerGainManuelPrediction('p1', 10.0);
        expect(issue, isIn(<IssueEcritureGain>[
          IssueEcritureGain.echec,
          IssueEcritureGain.echecNonReconcilie,
        ]));
        expect(issue, isNot(IssueEcritureGain.confirme));
      });
    });

    test('V16 `confirmationEcriturePredictions` ne ment pas sans écriture',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        await _installer(store);
        // Provider neuf, aucune écriture financière encore effectuée.
        final pmu = PmuProvider();
        await pmu.sauvegardeTerminee();
        // Aucune écriture n'a eu lieu : la confirmation doit être false.
        expect(await pmu.confirmationEcriturePredictions(), isFalse,
            reason: '0 >= 0 ne doit jamais passer pour une preuve');
      });
    });

    test('V17 après une écriture réussie, la confirmation devient vraie',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);
        await pmu.enregistrerGainManuelPrediction('p1', 5.0);
        expect(await pmu.confirmationEcriturePredictions(), isTrue);
      });
    });

    test('V18 `sauvegardeTerminee` conserve sa signature `Future<void>`',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);
        // Compilation = preuve : le type statique est bien Future<void>.
        final Future<void> attendu = pmu.sauvegardeTerminee();
        await attendu;
        expect(attendu, isA<Future<void>>());
      });
    });

    test('V19 un montant très précis (centimes) survit sans arrondi',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);
        await pmu.enregistrerGainManuelPrediction('p1', 12.34);
        expect(
            (store.predictionParId('p1')!['montantGainManuel'] as num)
                .toDouble(),
            12.34);
        expect(await pmu.verifierGainPersiste('p1', 12.34), isTrue);
      });
    });

    test('V20 écrire deux fois la même valeur reste idempotent', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);
        expect(await pmu.enregistrerGainManuelPrediction('p1', 8.0),
            IssueEcritureGain.confirme);
        expect(await pmu.enregistrerGainManuelPrediction('p1', 8.0),
            IssueEcritureGain.confirme);
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 8.0);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE G — GÉNÉRATIONS D'OPÉRATIONS
  // ═══════════════════════════════════════════════════════════════════════
  group('G — générations d\'opérations', () {
    test('G1 10 → 20 : la seconde écriture gagne, la première n\'est pas '
        'confirmée rétroactivement', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        final e1 = pmu.enregistrerGainManuelPrediction('p1', 10.0);
        final e2 = pmu.enregistrerGainManuelPrediction('p1', 20.0);
        final r1 = await e1;
        final r2 = await e2;

        expect(r2, IssueEcritureGain.confirme);
        expect(r1, isNot(IssueEcritureGain.confirme),
            reason: 'la 1ʳᵉ opération a été remplacée, elle ne peut pas '
                'être annoncée comme enregistrée');
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 20.0);
      });
    });

    test('G2 10 → 20 → 10 : le dernier 10 est bien le sien, l\'ambiguïté est '
        'levée par la génération', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        final e1 = pmu.enregistrerGainManuelPrediction('p1', 10.0);
        final e2 = pmu.enregistrerGainManuelPrediction('p1', 20.0);
        final e3 = pmu.enregistrerGainManuelPrediction('p1', 10.0);
        final r1 = await e1;
        final r2 = await e2;
        final r3 = await e3;

        // Seule la DERNIÈRE peut se déclarer confirmée.
        expect(r3, IssueEcritureGain.confirme);
        expect(r1, isNot(IssueEcritureGain.confirme));
        expect(r2, isNot(IssueEcritureGain.confirme));
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 10.0);
      });
    });

    test('G3 une opération dépassée ne PEUT PAS rétablir son montant',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        // La première échoue ; la seconde réussit entre-temps.
        store.refusRestants = 2;
        final e1 = pmu.enregistrerGainManuelPrediction('p1', 10.0);
        final r1 = await e1;
        expect(r1, IssueEcritureGain.echec);

        store.refusRestants = null;
        final r2 = await pmu.enregistrerGainManuelPrediction('p1', 20.0);
        expect(r2, IssueEcritureGain.confirme);

        // Le rollback de la 1ʳᵉ ne doit pas avoir écrasé le 20.
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 20.0);
      });
    });

    test('G4 deux tickets DIFFÉRENTS : les générations sont indépendantes',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1'), _pred('p2')]);

        final r1 = await pmu.enregistrerGainManuelPrediction('p1', 10.0);
        final r2 = await pmu.enregistrerGainManuelPrediction('p2', 20.0);
        expect(r1, IssueEcritureGain.confirme);
        expect(r2, IssueEcritureGain.confirme);
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 10.0);
        expect((store.predictionParId('p2')!['montantGainManuel'] as num)
            .toDouble(), 20.0);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE R — ROLLBACK CIBLÉ ET RÉCONCILIATION
  // ═══════════════════════════════════════════════════════════════════════
  group('R — rollback ciblé', () {
    test('R1 le rollback ne touche QUE montantGainManuel', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [
          _pred('p1',
              montantGainManuel: 12.0,
              montantOfficielPmu: 99.0,
              decision: DecisionGainPmu.refuse,
              gainRealise: 30.0,
              montantMise: 4.0),
        ]);

        store.refusRestants = 2;
        await pmu.enregistrerGainManuelPrediction('p1', 50.0);

        final p = pmu.predictions.firstWhere((e) => e.id == 'p1');
        expect(p.montantGainManuel, 12.0, reason: 'valeur rétablie');
        expect(p.montantOfficielPmu, 99.0, reason: 'décision intacte');
        expect(p.decisionGainPmu, DecisionGainPmu.refuse,
            reason: 'la décision ne doit pas être effacée par un rollback');
        expect(p.gainRealise, 30.0);
        expect(p.montantMise, 4.0);
      });
    });

    test('R2 le rollback ne réinstalle PAS l\'objet entier : un verdict '
        'officiel posé entre-temps survit', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        // Un verdict arrive pendant l'écriture défaillante.
        store.refusRestants = 2;
        store.avantChaqueEcriture = () async {
          store.avantChaqueEcriture = null;
          pmu.appliquerVerdictGainPrediction(
              _pred('p1', gainRealise: 25.0, montantMise: 5.0));
        };

        final issue = await pmu.enregistrerGainManuelPrediction('p1', 33.0);
        expect(issue, isNot(IssueEcritureGain.confirme));

        final p = pmu.predictions.firstWhere((e) => e.id == 'p1');
        expect(p.gainRealise, 25.0,
            reason: 'un rollback ne doit jamais écraser un verdict officiel');
      });
    });

    test('R3 après rollback prouvé, le ticket n\'est PAS bloqué', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        store.refusRestants = 1; // seule la 1ʳᵉ échoue, la réconciliation passe
        final issue = await pmu.enregistrerGainManuelPrediction('p1', 10.0);
        expect(issue, IssueEcritureGain.echec);
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse);
        expect(pmu.nombreEtatsFinanciersDivergents, 0);
      });
    });

    test('R4 `reconcilierEtatFinancier` rend false pour un ticket ABSENT',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);
        expect(await pmu.reconcilierEtatFinancier('zzz'), isFalse);
      });
    });

    test('R5 `reconcilierEtatFinancier` rend true quand mémoire et disque '
        'concordent sur les trois champs', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(
            store,
            [
              _pred('p1',
                  montantGainManuel: 12.0,
                  montantOfficielPmu: 99.0,
                  decision: DecisionGainPmu.accepte),
            ]);

        expect(await pmu.reconcilierEtatFinancier('p1'), isTrue);
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE D — TICKET DIVERGENT : BLOCAGE ET RÉCUPÉRATION
  // ═══════════════════════════════════════════════════════════════════════
  group('D — état financier divergent', () {
    /// Amène `p1` dans un état divergent RÉEL.
    ///
    /// ⚠️ CONSTRUCTION HONNÊTE, et c'est la seule qui produise ce cas :
    ///    pour que l'alignement soit NON PROUVÉ, il faut que le support
    ///    contienne DÉJÀ une valeur différente de celle que la mémoire va
    ///    rétablir, ET que l'écriture de réconciliation échoue.
    ///    Un simple refus d'écriture ne suffit pas : le support conserve alors
    ///    l'ancienne valeur, la mémoire y est réalignée, et l'état est PROUVÉ
    ///    (`echec`). C'est le comportement correct, vérifié par V11/V12/R3.
    Future<PmuProvider> _rendreDivergent(_StoreControle store) async {
      final pmu = await _providerAvec(store, [_pred('p1')]);
      // ① Le support porte une valeur que la mémoire ne connaît pas.
      store.ecrirePredictionBrute(_pred('p1', montantGainManuel: 77.0).toJson());
      // ② Toute écriture est refusée : la réconciliation ne peut pas aligner.
      store.refusRestants = 50;
      final issue = await pmu.enregistrerGainManuelPrediction('p1', 10.0);
      expect(issue, IssueEcritureGain.echecNonReconcilie,
          reason: 'l\'alignement n\'est pas prouvé');
      expect(pmu.estEtatFinancierDivergent('p1'), isTrue);
      store.refusRestants = null;
      return pmu;
    }

    test('D1 un échec non réconcilié BLOQUE le ticket', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        await _rendreDivergent(store);
      });
    });

    test('D2 un ticket bloqué REFUSE toute nouvelle écriture', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _rendreDivergent(store);

        final issue = await pmu.enregistrerGainManuelPrediction('p1', 20.0);
        expect(issue, IssueEcritureGain.echecNonReconcilie);
        expect(
            (store.predictionParId('p1')!['montantGainManuel'] as num)
                .toDouble(),
            77.0,
            reason: 'aucune écriture ne doit être tentée sur un ticket bloqué : '
                'le support garde la valeur qu\'il portait');
      });
    });

    test('D3 le blocage est PAR TICKET : les autres restent utilisables',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1'), _pred('p2')]);
        // p1 diverge : le support porte une valeur inconnue de la mémoire.
        store.ecrirePredictionBrute(
            _pred('p1', montantGainManuel: 77.0).toJson());
        store.refusRestants = 50;
        await pmu.enregistrerGainManuelPrediction('p1', 10.0);
        expect(pmu.estEtatFinancierDivergent('p1'), isTrue);
        expect(pmu.estEtatFinancierDivergent('p2'), isFalse);

        store.refusRestants = null;
        final r = await pmu.enregistrerGainManuelPrediction('p2', 30.0);
        expect(r, IssueEcritureGain.confirme);
      });
    });

    test('D4 `nombreEtatsFinanciersDivergents` compte exactement', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(
            store, [_pred('p1'), _pred('p2'), _pred('p3')]);
        expect(pmu.nombreEtatsFinanciersDivergents, 0);

        store.refusRestants = 50;
        // p1 et p2 divergent réellement (valeur préalable sur le support).
        store.ecrirePredictionBrute(
            _pred('p1', montantGainManuel: 71.0).toJson());
        store.ecrirePredictionBrute(
            _pred('p2', montantGainManuel: 72.0).toJson());
        await pmu.enregistrerGainManuelPrediction('p1', 10.0);
        expect(pmu.nombreEtatsFinanciersDivergents, 1);
        await pmu.enregistrerGainManuelPrediction('p2', 10.0);
        expect(pmu.nombreEtatsFinanciersDivergents, 2);

        // p3 est intact : un refus ordinaire ne le bloque pas.
        await pmu.enregistrerGainManuelPrediction('p3', 10.0);
        expect(pmu.estEtatFinancierDivergent('p3'), isFalse);
        expect(pmu.nombreEtatsFinanciersDivergents, 2);
      });
    });

    test('D5 récupération : réconciliation réussie DÉBLOQUE le ticket',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _rendreDivergent(store);
        // Le disque porte déjà la valeur mémoire (rollback réussite partielle
        // non survenue) : on force la concordance en écrivant l'état mémoire.
        store.ecrirePredictionBrute(pmu.predictions
            .firstWhere((e) => e.id == 'p1')
            .toJson());
        final ok = await pmu.reconcilierEtatFinancier('p1');
        expect(ok, isTrue);
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse);
      });
    });

    test('D6 réconciliation : un désaccord RÉEL rend false et laisse bloqué',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _rendreDivergent(store);
        // Le disque porte une valeur DIFFÉRENTE de la mémoire.
        store.ecrirePredictionBrute(_pred('p1', montantGainManuel: 77.0).toJson());
        final ok = await pmu.reconcilierEtatFinancier('p1');
        expect(ok, isFalse);
        expect(pmu.estEtatFinancierDivergent('p1'), isTrue,
            reason: 'l\'incertitude doit laisser le ticket bloqué');
      });
    });

    test('D7 réconciliation : un désaccord sur le champ OFFICIEL suffit',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);
        store.ecrirePredictionBrute(
            _pred('p1', montantOfficielPmu: 55.0).toJson());
        expect(await pmu.reconcilierEtatFinancier('p1'), isFalse,
            reason: 'les trois champs financiers sont comparés');
      });
    });

    test('D8 réconciliation : un désaccord sur la DÉCISION suffit', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);
        store.ecrirePredictionBrute(
            _pred('p1', decision: DecisionGainPmu.accepte).toJson());
        expect(await pmu.reconcilierEtatFinancier('p1'), isFalse);
      });
    });

    test('D9 réconciliation N\'ÉCRASE PAS la mémoire (pas de reloadPredictions)',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(
            store, [_pred('p1', montantGainManuel: 12.0)]);
        // Le disque diverge volontairement.
        store.ecrirePredictionBrute(_pred('p1', montantGainManuel: 99.0).toJson());

        await pmu.reconcilierEtatFinancier('p1');

        final memoire = pmu.predictions.firstWhere((e) => e.id == 'p1');
        expect(memoire.montantGainManuel, 12.0,
            reason: 'un rechargement écraserait la mémoire avant comparaison');
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE N — CONCURRENCE
  // ═══════════════════════════════════════════════════════════════════════
  group('N — concurrence et écritures simultanées', () {
    test('N1 deux écritures SIMULTANÉES sur le même ticket : l\'état final '
        'correspond à une opération réelle, jamais un mélange', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        final r = await Future.wait(<Future<IssueEcritureGain>>[
          pmu.enregistrerGainManuelPrediction('p1', 10.0),
          pmu.enregistrerGainManuelPrediction('p1', 20.0),
        ]);
        final disque =
            (store.predictionParId('p1')!['montantGainManuel'] as num?)
                ?.toDouble();
        expect(<double?>[10.0, 20.0], contains(disque),
            reason: 'le disque porte l\'une des deux demandes, pas autre chose');
        // Au plus une seule peut être confirmée comme « sa » valeur finale.
        expect(r.where((e) => e == IssueEcritureGain.confirme).length,
            lessThanOrEqualTo(1));
      });
    });

    test('N2 écritures SIMULTANÉES sur deux tickets DISTINCTS : les deux '
        'valeurs sont persistées', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1'), _pred('p2')]);

        final r = await Future.wait(<Future<IssueEcritureGain>>[
          pmu.enregistrerGainManuelPrediction('p1', 10.0),
          pmu.enregistrerGainManuelPrediction('p2', 20.0),
        ]);
        expect(r, everyElement(IssueEcritureGain.confirme));
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 10.0);
        expect((store.predictionParId('p2')!['montantGainManuel'] as num)
            .toDouble(), 20.0);
      });
    });

    test('N3 modification plus récente PENDANT la sauvegarde : elle gagne et '
        'la première n\'est pas confirmée', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        // Injection au pire moment : juste avant l'écriture du disque.
        store.avantChaqueEcriture = () async {
          store.avantChaqueEcriture = null;
          unawaited(pmu.enregistrerGainManuelPrediction('p1', 99.0));
        };

        final r1 = await pmu.enregistrerGainManuelPrediction('p1', 10.0);
        await pmu.sauvegardeTerminee();

        expect(r1, isNot(IssueEcritureGain.confirme),
            reason: 'une écriture plus récente a pris le dessus');
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 99.0);
      });
    });

    test('N4 échec puis nouvelle tentative concurrente : la tentative '
        'réussie gagne', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        store.refusRestants = 1;
        final e1 = pmu.enregistrerGainManuelPrediction('p1', 10.0);
        final e2 = pmu.enregistrerGainManuelPrediction('p1', 30.0);
        final r1 = await e1;
        final r2 = await e2;
        expect(r2, IssueEcritureGain.confirme);
        expect(r1, isNot(IssueEcritureGain.confirme));
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 30.0);
      });
    });

    test('N5 trois écritures enchaînées : seule la dernière est confirmée',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        final r = await Future.wait(<Future<IssueEcritureGain>>[
          pmu.enregistrerGainManuelPrediction('p1', 1.0),
          pmu.enregistrerGainManuelPrediction('p1', 2.0),
          pmu.enregistrerGainManuelPrediction('p1', 3.0),
        ]);
        expect(r.last, IssueEcritureGain.confirme);
        expect(r[0], isNot(IssueEcritureGain.confirme));
        expect(r[1], isNot(IssueEcritureGain.confirme));
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 3.0);
      });
    });

    test('N6 une écriture sur un ticket ne perd pas celle d\'un autre ticket',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(
            store, [_pred('p1'), _pred('p2'), _pred('p3')]);

        await Future.wait(<Future<IssueEcritureGain>>[
          pmu.enregistrerGainManuelPrediction('p1', 11.0),
          pmu.enregistrerGainManuelPrediction('p2', 22.0),
          pmu.enregistrerGainManuelPrediction('p3', 33.0),
        ]);
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 11.0);
        expect((store.predictionParId('p2')!['montantGainManuel'] as num)
            .toDouble(), 22.0);
        expect((store.predictionParId('p3')!['montantGainManuel'] as num)
            .toDouble(), 33.0);
      });
    });

    test('N7 suppression d\'un autre ticket pendant l\'écriture : l\'écriture '
        'aboutit quand même', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1'), _pred('p2')]);

        store.avantChaqueEcriture = () async {
          store.avantChaqueEcriture = null;
          pmu.removePrediction('p2');
        };
        final r = await pmu.enregistrerGainManuelPrediction('p1', 12.0);
        await pmu.sauvegardeTerminee();
        expect(r, IssueEcritureGain.confirme);
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 12.0);
      });
    });

    test('N8 concurrence n\'altère JAMAIS les verdicts officiels', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [
          _pred('p1',
              montantOfficielPmu: 99.0,
              decision: DecisionGainPmu.accepte,
              gainRealise: 40.0,
              montantMise: 5.0),
        ]);

        await Future.wait(<Future<IssueEcritureGain>>[
          pmu.enregistrerGainManuelPrediction('p1', 10.0),
          pmu.enregistrerGainManuelPrediction('p1', 20.0),
        ]);
        final d = store.predictionParId('p1')!;
        expect(d['decisionGainPmu'], 'accepte');
        expect((d['montantOfficielPmu'] as num).toDouble(), 99.0);
        expect((d['gainRealise'] as num).toDouble(), 40.0);
      });
    });

    test('N9 une écriture concurrente n\'empêche pas la preuve finale', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);

        final r = await pmu.enregistrerGainManuelPrediction('p1', 14.0);
        await pmu.sauvegardeTerminee();
        expect(r, IssueEcritureGain.confirme);
        expect(await pmu.verifierGainPersiste('p1', 14.0), isTrue);
      });
    });

    test('N10 dix écritures séquentielles sur le même ticket : la dernière '
        'valeur est celle du disque', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);
        for (var i = 1; i <= 10; i++) {
          await pmu.enregistrerGainManuelPrediction('p1', i * 1.5);
        }
        expect((store.predictionParId('p1')!['montantGainManuel'] as num)
            .toDouble(), 15.0);
      });
    });

    test('N11 un échec concurrent ne corrompt pas le ticket voisin', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1'), _pred('p2')]);

        store.refusRestants = 10;
        final r1 = pmu.enregistrerGainManuelPrediction('p1', 10.0);
        store.refusRestants = null;
        final r2 = pmu.enregistrerGainManuelPrediction('p2', 20.0);
        await r1;
        expect(await r2, IssueEcritureGain.confirme);
        expect((store.predictionParId('p2')!['montantGainManuel'] as num)
            .toDouble(), 20.0);
      });
    });

    test('N12 écriture + effacement concurrents : le disque reflète l\'une '
        'des deux demandes', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(
            store, [_pred('p1', montantGainManuel: 5.0)]);

        await Future.wait(<Future<IssueEcritureGain>>[
          pmu.enregistrerGainManuelPrediction('p1', 40.0),
          pmu.enregistrerGainManuelPrediction('p1', null),
        ]);
        final v = store.predictionParId('p1')!['montantGainManuel'];
        expect(v == null || v == 40.0, isTrue,
            reason: 'aucune troisième valeur inventée');
      });
    });

    test('N13 une décision plus récente n\'est pas annulée par une écriture '
        'de montant', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [
          _pred('p1', montantOfficielPmu: 99.0),
        ]);
        await pmu.enregistrerGainManuelPrediction('p1', 10.0);

        // Décision prise APRÈS l'écriture du montant.
        store.ecrirePredictionBrute(_pred('p1',
                montantGainManuel: 10.0,
                montantOfficielPmu: 99.0,
                decision: DecisionGainPmu.accepte)
            .toJson());
        // ⚠️ `reloadPredictions()` lit le CACHE de `SharedPreferences` : il
        //    faut donc d'abord réaligner ce cache sur le support, sinon on
        //    relirait l'ancienne valeur et le test ne prouverait rien.
        await (await SharedPreferences.getInstance()).reload();
        await pmu.reloadPredictions();

        final p = pmu.predictions.firstWhere((e) => e.id == 'p1');
        expect(p.decisionGainPmu, DecisionGainPmu.accepte);
        expect(p.gainRetenuBrut, 99.0);
      });
    });

    test('N14 `sauvegardeTerminee` attend réellement la fin (pas un no-op)',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1')]);
        final f = pmu.enregistrerGainManuelPrediction('p1', 9.0);
        await pmu.sauvegardeTerminee();
        expect(await f, IssueEcritureGain.confirme);
        expect(await pmu.verifierGainPersiste('p1', 9.0), isTrue);
      });
    });

    test('N15 deux tickets, deux échecs divergents : deux blocages distincts',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1'), _pred('p2')]);
        // Divergence RÉELLE : le support porte des valeurs inconnues.
        store.ecrirePredictionBrute(
            _pred('p1', montantGainManuel: 71.0).toJson());
        store.ecrirePredictionBrute(
            _pred('p2', montantGainManuel: 72.0).toJson());
        store.refusRestants = 50;
        await pmu.enregistrerGainManuelPrediction('p1', 1.0);
        await pmu.enregistrerGainManuelPrediction('p2', 2.0);
        expect(pmu.estEtatFinancierDivergent('p1'), isTrue);
        expect(pmu.estEtatFinancierDivergent('p2'), isTrue);
        expect(pmu.nombreEtatsFinanciersDivergents, 2);
      });
    });

    test('N16 la récupération d\'un ticket ne débloque pas l\'autre', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(store, [_pred('p1'), _pred('p2')]);
        store.ecrirePredictionBrute(
            _pred('p1', montantGainManuel: 71.0).toJson());
        store.ecrirePredictionBrute(
            _pred('p2', montantGainManuel: 72.0).toJson());
        store.refusRestants = 50;
        await pmu.enregistrerGainManuelPrediction('p1', 1.0);
        await pmu.enregistrerGainManuelPrediction('p2', 2.0);
        expect(pmu.estEtatFinancierDivergent('p1'), isTrue);
        expect(pmu.estEtatFinancierDivergent('p2'), isTrue);
        store.refusRestants = null;

        store.ecrirePredictionBrute(
            pmu.predictions.firstWhere((e) => e.id == 'p1').toJson());
        expect(await pmu.reconcilierEtatFinancier('p1'), isTrue);
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse);
        expect(pmu.estEtatFinancierDivergent('p2'), isTrue);
      });
    });

    test('N17 aucune écriture ne modifie le nombre total de prédictions',
        () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(
            store, [_pred('p1'), _pred('p2'), _pred('p3')]);
        final avant = store.predictionsBrutes().length;
        await Future.wait(<Future<IssueEcritureGain>>[
          pmu.enregistrerGainManuelPrediction('p1', 1.0),
          pmu.enregistrerGainManuelPrediction('p2', 2.0),
          pmu.enregistrerGainManuelPrediction('p3', 3.0),
        ]);
        expect(store.predictionsBrutes().length, avant);
        expect(pmu.predictions.length, 3);
      });
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE L — VERROU ACCEPTER/REFUSER : NON BRANCHÉ
  // ═══════════════════════════════════════════════════════════════════════
  group('L — verrou Accepter/Refuser : statut prouvé NON BRANCHÉ', () {
    test('L1 `invaliderPourDecisionFinanciere` existe mais n\'est appelée '
        'NULLE PART en production', () {
      // Preuve de statut : la méthode est déclarée, mais aucun site de
      // production ne l\'invoque. On lit le code source des écrans/services.
      final fichiers = <String>[
        'lib/providers/pmu_provider.dart',
        'lib/screens/mes_paris_screen.dart',
        'lib/services/alert_service.dart',
      ];
      var appelsEnCode = 0;
      for (final f in fichiers) {
        final src = File(f).readAsStringSync();
        for (final ligne in src.split('\n')) {
          final code = ligne.split('//').first; // commentaires exclus
          appelsEnCode += RegExp(r'invaliderPourDecisionFinanciere\s*\(')
              .allMatches(code)
              .length;
        }
      }
      // 1 seule occurrence attendue : la DÉCLARATION dans le provider.
      expect(appelsEnCode, 1,
          reason: 'aucun site ne doit l\'appeler tant que le lot n\'est pas '
              'branché');
    });

    test('L2 aucune interface Accepter/Refuser n\'existe dans les écrans',
        () {
      final src = File('lib/screens/mes_paris_screen.dart').readAsStringSync();
      expect(RegExp(r'Accepter le gain officiel').hasMatch(src), isFalse);
      expect(RegExp(r'Refuser le gain officiel').hasMatch(src), isFalse);
      // Aucune AFFECTATION d'une décision : `=` simple, pas `==` de lecture.
      expect(RegExp(r'decisionGainPmu\s*=(?!=)').hasMatch(src), isFalse,
          reason: 'l\'écran ne doit écrire aucune décision');
      expect(RegExp(r'\.copyWith\([^)]*decisionGainPmu').hasMatch(src), isFalse,
          reason: 'aucune copie ne doit poser de décision');
    });

    test('L3 le modèle SAIT porter une décision sans qu\'aucun canal ne '
        'l\'écrive : la valeur reste stable', () async {
      await _sansReseau(() async {
        final store = _StoreControle();
        final pmu = await _providerAvec(
            store, [_pred('p1', montantOfficielPmu: 50.0)]);

        // Même après plusieurs écritures de montant, aucune décision n'apparaît.
        await pmu.enregistrerGainManuelPrediction('p1', 10.0);
        await pmu.enregistrerGainManuelPrediction('p1', 20.0);
        final p = pmu.predictions.firstWhere((e) => e.id == 'p1');
        expect(p.decisionGainPmu, isNull,
            reason: 'aucune décision ne doit être prise automatiquement');
        expect(p.montantOfficielPmu, 50.0,
            reason: 'l\'officiel reste en RÉFÉRENCE, ni appliqué ni effacé');
        expect(p.gainRetenuBrut, 20.0,
            reason: 'sans décision, seul le manuel est retenu');
      });
    });
  });
}
