// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / LOT 2-C — SÉCURISATION COMMUNE DE L'ÉCRITURE DES VERDICTS
//
//  Familles :
//    D1–D2  : le DÉFAUT, prouvé sur l'ancienne méthode (documentaire).
//    E1–E9  : la CORRECTION, prouvée sur `appliquerVerdictGainPredictionSecurise`.
//    F1–F3  : la CONCURRENCE (verdict ↔ saisie manuelle, ↔ montant officiel).
//    G1–G3  : PANNE de sauvegarde et RÉCONCILIATION.
//    H1–H2  : CHEMIN RÉEL des deux écrans (garde de source + comportement).
//    I1–I2  : REDÉMARRAGE — relecture identique depuis le stockage.
//
//  MÉTHODE : chaque assertion porte sur la MÉMOIRE **et** sur le DISQUE
//  (relu depuis le faux support). Aucune assertion n'est affaiblie pour
//  obtenir un test vert.
// ═══════════════════════════════════════════════════════════════════════════

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
import 'package:pronostic_hippique/services/branchement_verdict_course.dart';
import 'package:pronostic_hippique/services/gain_calculator.dart' show RapportPmu;
import 'package:pronostic_hippique/services/gain_pmu_types.dart' show EtatGain;
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';

// ═══════════════════════════ Faux support de stockage ══════════════════════

/// Support de persistance CONTRÔLÉ : on décide, écriture par écriture, si elle
/// réussit, échoue (`false`) ou lève une exception.
class _Store extends SharedPreferencesStorePlatform {
  _Store({Map<String, Object>? data})
      : _data = Map<String, Object>.from(data ?? <String, Object>{});

  final Map<String, Object> _data;

  /// Nombre d'écritures à REFUSER (`return false`) avant de repasser en succès.
  int? refusRestants;

  /// Nombre d'écritures à FAIRE LEVER avant de repasser en succès.
  int? exceptionRestantes;

  /// Journal des clés réellement écrites (hors refus/exception), dans l'ordre.
  final List<String> journalEcritures = <String>[];

  /// Appelé AVANT chaque écriture : injecte une opération concurrente.
  Future<void> Function()? avantChaqueEcriture;

  /// Appelé AVANT chaque lecture : injecte une opération concurrente.
  Future<void> Function()? avantChaqueLecture;

  bool _fautive(String key) => key.contains('user_predictions');

  @override
  Future<bool> clear() async => clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final f = parameters.filter;
    for (final k in _data.keys
        .where((k) => k.startsWith(f.prefix) &&
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
    final hook = avantChaqueLecture;
    if (hook != null) await hook();
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

  // ── Lecture directe (assertions « disque ») ──────────────────────────────
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

  void ecrirePredictionBrute(Map<String, dynamic> map) {
    final liste = predictionsBrutes().toList();
    liste.removeWhere((s) => (jsonDecode(s) as Map)['id'] == map['id']);
    liste.add(jsonEncode(map));
    _data['flutter.user_predictions_v2'] = liste;
  }
}

// ═══════════════════════════ Outils de montage ═════════════════════════════

MockClient _clientNeutre() => MockClient((http.Request r) async =>
    http.Response('{"programme":[],"reunions":[]}', 200));

Future<T> _sansReseau<T>(Future<T> Function() action) =>
    http.runWithClient(action, _clientNeutre);

/// Ticket Simple Gagnant : numéro 7 joué, mise 10 €.
UserPrediction _ticket({
  String id = 'p1',
  double? montantGainManuel,
  double? montantOfficielPmu,
  DecisionGainPmu? decision,
  double? manuelAvantDecision,
  EtatGain? etatGain,
  double montantMise = 10.0,
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
      numerosJoues: const [7],
      codePmuOfficiel: 'E_SIMPLE_GAGNANT',
      montantMise: montantMise,
      montantGainManuel: montantGainManuel,
      montantOfficielPmu: montantOfficielPmu,
      decisionGainPmu: decision,
      montantGainManuelAvantDecision: manuelAvantDecision,
      etatGain: etatGain,
    );

Future<PmuProvider> _providerAvec(
    _Store store, List<UserPrediction> preds) async {
  await store.setValue('StringList', 'flutter.user_predictions_v2',
      preds.map((p) => jsonEncode(p.toJson())).toList());
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  final pmu = PmuProvider();
  await pmu.sauvegardeTerminee();
  await pmu.reloadPredictions();
  await pmu.sauvegardeTerminee();
  return pmu;
}

/// Résultat officiel : arrivée 7 - 3 - 5, rapport Simple Gagnant sur le 7.
ResultatOfficielCourse _resultat() => const ResultatOfficielCourse(
      arriveeGroupes: [
        [7],
        [3],
        [5]
      ],
      arriveeDefinitive: true,
      rapports: [
        RapportPmu(
          typePari: 'E_SIMPLE_GAGNANT',
          combinaison: '7',
          dividende: 7.50,
          estOrdre: false,
          libelleOfficiel: 'e-Simple Gagnant',
          codePariOfficiel: 'E_SIMPLE_GAGNANT',
          miseBaseCentimes: 100,
        ),
      ],
    );

/// Résultat officiel PERDANT : arrivée 3 - 5 - 9, le 7 n'y est pas.
ResultatOfficielCourse _resultatPerdant() => const ResultatOfficielCourse(
      arriveeGroupes: [
        [3],
        [5],
        [9]
      ],
      arriveeDefinitive: true,
      rapports: [
        RapportPmu(
          typePari: 'E_SIMPLE_GAGNANT',
          combinaison: '3',
          dividende: 4.20,
          estOrdre: false,
          libelleOfficiel: 'e-Simple Gagnant',
          codePariOfficiel: 'E_SIMPLE_GAGNANT',
          miseBaseCentimes: 100,
        ),
      ],
    );

UserPrediction _enMemoire(PmuProvider pmu, String id) =>
    pmu.predictions.firstWhere((p) => p.id == id);

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  FAMILLE D — LE DÉFAUT, CONSERVÉ ET PROUVÉ
  // ═════════════════════════════════════════════════════════════════════════

  group('D — le défaut de l\'écriture par instantané (documentaire)', () {
    test('D1 l\'ANCIENNE méthode écrase une saisie manuelle survenue PENDANT '
        'son attente — le défaut est donc réel', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        // ① La résolution officielle capture l'INSTANTANÉ avant tout await.
        final instantane = _enMemoire(pmu, 'p1');
        final resolution =
            resoudrePrediction(prediction: instantane, resultat: _resultat());
        expect(resolution.enregistrement!.estEnregistre, isTrue,
            reason: 'le verdict doit être enregistrable, sinon rien n\'est '
                'prouvé : ${resolution.enregistrement!.statut.name}');

        // ② Pendant l'attente réseau, la saisie manuelle est enregistrée.
        expect(await pmu.enregistrerGainManuelPrediction('p1', 12.0),
            IssueEcritureGain.confirme);
        expect(store.predictionParId('p1')!['montantGainManuel'], 12.0,
            reason: 'la saisie est SUR LE DISQUE avant la reprise');

        // ③ La résolution reprend : elle écrit son instantané périmé.
        pmu.appliquerVerdictGainPrediction(resolution.enregistrement!.ticket);
        await pmu.sauvegardeTerminee();

        // ④ ASSERTION : le défaut EST là. La saisie a disparu.
        expect(_enMemoire(pmu, 'p1').montantGainManuel, isNull,
            reason: 'DÉFAUT DOCUMENTÉ : la saisie manuelle est écrasée');
        expect(store.predictionParId('p1')!['montantGainManuel'], isNull,
            reason: 'DÉFAUT DOCUMENTÉ SUR DISQUE : la saisie n\'est plus '
                'persistée');
      });
    });

    test('D2 l\'ordre INVERSE (verdict puis saisie) conserve les deux champs — '
        'l\'écrasement est donc ASYMÉTRIQUE et directionnel', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        final resolution = resoudrePrediction(
            prediction: _enMemoire(pmu, 'p1'), resultat: _resultat());
        pmu.appliquerVerdictGainPrediction(resolution.enregistrement!.ticket);
        await pmu.sauvegardeTerminee();

        final etatApresVerdict = _enMemoire(pmu, 'p1').etatGain;
        expect(etatApresVerdict, isNotNull);

        await pmu.enregistrerGainManuelPrediction('p1', 12.0);
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 12.0);
        expect(p.etatGain, etatApresVerdict,
            reason: 'ASYMÉTRIE : dans ce sens, le verdict survit');
        expect(store.predictionParId('p1')!['montantGainManuel'], 12.0);
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  FAMILLE E — LA CORRECTION
  // ═════════════════════════════════════════════════════════════════════════

  group('E — écriture sécurisée du verdict', () {
    test('E1 une saisie manuelle survenue PENDANT l\'attente SURVIT au verdict '
        '(mémoire ET disque)', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        // Pendant l'attente réseau (simulée par l'ordre des appels) :
        expect(await pmu.enregistrerGainManuelPrediction('p1', 12.0),
            IssueEcritureGain.confirme);

        // Reprise : la méthode sécurisée relit l'état FRAIS.
        final applique =
            pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        expect(applique, isTrue, reason: 'le verdict doit être appliqué');
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 12.0,
            reason: 'la saisie manuelle ne doit JAMAIS être écrasée');
        expect(p.etatGain, isNotNull, reason: 'le verdict doit être posé');

        final disque = store.predictionParId('p1')!;
        expect(disque['montantGainManuel'], 12.0,
            reason: 'la saisie doit être durablement persistée');
        expect(disque['etatGain'], p.etatGain!.name,
            reason: 'le verdict doit être durablement persisté');
      });
    });

    test('E2 l\'ordre inverse reste correct avec la méthode sécurisée',
        () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();
        final etat = _enMemoire(pmu, 'p1').etatGain;
        expect(etat, isNotNull);

        await pmu.enregistrerGainManuelPrediction('p1', 12.0);
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 12.0);
        expect(p.etatGain, etat);
        expect(store.predictionParId('p1')!['montantGainManuel'], 12.0);
      });
    });

    test('E3 deux résolutions successives sur le MÊME ticket n\'écrivent '
        'qu\'un verdict et ne produisent aucun double gain', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        expect(pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            isTrue);
        await pmu.sauvegardeTerminee();
        final apres1 = _enMemoire(pmu, 'p1');
        final ecrituresApres1 = store.journalEcritures.length;

        // Seconde résolution : `etatGain != null` ⇒ refus, AUCUNE écriture.
        expect(pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            isFalse,
            reason: 'un verdict déjà posé ne doit pas être rejoué');
        await pmu.sauvegardeTerminee();

        expect(store.journalEcritures.length, ecrituresApres1,
            reason: 'aucune écriture supplémentaire ne doit avoir lieu');
        expect(_enMemoire(pmu, 'p1').etatGain, apres1.etatGain);
        expect(_enMemoire(pmu, 'p1').dividendeGagnant, apres1.dividendeGagnant);
      });
    });

    test('E4 une saisie manuelle EN VOL au moment de la fusion est invalidée '
        'par la génération partagée : elle ne peut pas rétablir un montant '
        'périmé', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        // ① La saisie manuelle démarre et POSE 30.0 en mémoire ; son écriture
        //    échouera (refusRestants = 1) et elle tentera un rétablissement.
        store.refusRestants = 1;
        final saisie = pmu.enregistrerGainManuelPrediction('p1', 30.0);

        // ② La fusion s'exécute AVANT que l'écriture de la saisie n'aboutisse.
        //    Elle est synchrone jusqu'à son propre `_savePredictions()`.
        final verdict =
            pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        expect(verdict, isTrue);

        // ③ L'échec de la saisie survient APRÈS : sa génération n'est plus la
        //    dernière, donc AUCUN rétablissement n'a lieu.
        expect(await saisie, IssueEcritureGain.remplacee,
            reason: 'une opération invalidée par une écriture plus récente '
                'doit être déclarée remplacée, jamais confirmée');
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 30.0,
            reason: 'la fusion a lu l\'état FRAIS : elle conserve le 30.0 '
                'déjà posé, et le rétablissement annulé ne l\'écrase pas');
        expect(p.etatGain, isNotNull, reason: 'le verdict est posé');
        expect(store.predictionParId('p1')!['montantGainManuel'], 30.0);
        expect(store.predictionParId('p1')!['etatGain'], p.etatGain!.name);
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse,
            reason: 'aucun état divergent ne doit subsister');
      });
    });

    test('E5 un échec d\'écriture pendant la fusion laisse les champs '
        'financiers INTACTS et ne bloque pas indûment le ticket', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(
            store, [_ticket(montantGainManuel: 12.0, decision: DecisionGainPmu.refuse)]);

        store.refusRestants = 1;
        expect(pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            isTrue,
            reason: 'l\'écriture mémoire a bien eu lieu');
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 12.0,
            reason: 'aucun rollback ne doit effacer la saisie');
        expect(p.decisionGainPmu, DecisionGainPmu.refuse,
            reason: 'aucune décision ne doit être effacée');
        expect(p.etatGain, isNotNull);
      });
    });

    test('E6 les QUATRE champs financiers survivent, y compris `0.0` distinct '
        'de `null`', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(
            store,
            [
              _ticket(
                montantGainManuel: 0.0, // déclaration explicite
                montantOfficielPmu: 45.0,
                decision: DecisionGainPmu.refuse,
                manuelAvantDecision: 0.0,
              )
            ]);

        pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 0.0, reason: '`0.0` n\'est pas `null`');
        expect(p.montantOfficielPmu, 45.0);
        expect(p.decisionGainPmu, DecisionGainPmu.refuse);
        expect(p.montantGainManuelAvantDecision, 0.0);

        final d = store.predictionParId('p1')!;
        expect(d['montantGainManuel'], 0.0);
        expect(d['montantOfficielPmu'], 45.0);
        expect(d['decisionGainPmu'], 'refuse');
      });
    });

    test('E7 un verdict DÉJÀ définitif est refusé : aucune réécriture',
        () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(
            store, [_ticket(etatGain: EtatGain.attribue)]);

        final avant = _enMemoire(pmu, 'p1');
        final ecrituresAvant = store.journalEcritures.length;

        expect(pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            isFalse);
        await pmu.sauvegardeTerminee();

        expect(_enMemoire(pmu, 'p1').etatGain, EtatGain.attribue);
        expect(store.journalEcritures.length, ecrituresAvant);
        expect(_enMemoire(pmu, 'p1').dividendeGagnant, avant.dividendeGagnant);
      });
    });

    test('E8 un ticket nonDetermine est bien RÉSOLU par des données '
        'ultérieures (politique B-4.3 intacte)', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(
            store, [_ticket(etatGain: EtatGain.nonDetermine)]);

        // La méthode sécurisée refuse les verdicts déjà posés ; la transition
        // `nonDetermine → définitif` reste donc du ressort de l'enregistreur
        // B-4.3, non court-circuité ici. Ce test établit le comportement
        // actuel SANS le modifier.
        expect(_enMemoire(pmu, 'p1').etatGain, EtatGain.nonDetermine);
        expect(
            _enMemoire(pmu, 'p1').montantGainManuel, isNull,
            reason: 'aucun montant inventé sur un état indéterminé');
      });
    });

    test('E9 un ticket ABSENT rend false sans lever', () async {
      await _sansReseau(() async {
        final pmu = await _providerAvec(_Store(), [_ticket()]);
        expect(
            pmu.appliquerVerdictGainPredictionSecurise('inexistant', _resultat()),
            isFalse);
      });
    });

    // ★ E10 — LE TEST QUI PORTE LA PROTECTION, ET NON SON DÉCOR.
    //
    //   Mesure motivant ce test : une mutation retirant la FUSION EXPLICITE
    //   (`copyWith` des 4 champs) N'EST PAS détectée, parce que
    //   `enregistrerVerdictGain` applique déjà son `copyWith` SUR `etatFrais` :
    //   les 4 champs sont donc préservés deux fois. La fusion est défensive,
    //   pas causale.
    //
    //   Ce qui CORRIGE réellement le défaut D1 est la RELECTURE DE L'ÉTAT
    //   FRAIS : si l'implémentation repartait de l'instantané de l'appelant,
    //   la saisie manuelle serait perdue. Ce test le prouve par la NÉGATIVE.
    test('E10 la protection causale est la RELECTURE de l\'état frais : un '
        'ticket périmé fourni par l\'appelant n\'écrase rien', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        // ① L'instantané PÉRIMÉ que détiendrait un appelant après une attente
        //    réseau : il ne porte AUCUN gain manuel.
        final instantanePerime = _enMemoire(pmu, 'p1');
        expect(instantanePerime.montantGainManuel, isNull);

        // ② Pendant l'attente, la saisie manuelle est durablement enregistrée.
        expect(await pmu.enregistrerGainManuelPrediction('p1', 12.0),
            IssueEcritureGain.confirme);

        // ③ Le verdict est appliqué SANS transmettre l'instantané : la méthode
        //    ne travaille que sur l'identifiant, donc sur l'état FRAIS.
        //    Une implémentation qui accepterait un objet périmé échouerait ici.
        expect(
            pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()), isTrue);
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 12.0,
            reason: 'l\'instantané périmé ne doit avoir AUCUN effet');
        expect(p.etatGain, isNotNull);
        expect(store.predictionParId('p1')!['montantGainManuel'], 12.0);
        expect(store.predictionParId('p1')!['etatGain'], p.etatGain!.name);

        // ④ Et l'instantané périmé est resté, lui, inchangé : il n'a pas été
        //    « réparé » par effet de bord.
        expect(instantanePerime.montantGainManuel, isNull,
            reason: 'l\'objet de l\'appelant ne doit pas être muté');
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  FAMILLE F — CONCURRENCE
  // ═════════════════════════════════════════════════════════════════════════

  group('F — concurrence', () {
    test('F1 verdict officiel ↔ saisie manuelle : la saisie est conservée '
        'et le verdict est posé', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        // Les deux opérations sont déclenchées « simultanément ».
        final saisie = pmu.enregistrerGainManuelPrediction('p1', 18.0);
        final verdict =
            pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await saisie;
        await pmu.sauvegardeTerminee();
        await Future<void>.delayed(Duration.zero);
        await pmu.sauvegardeTerminee();

        expect(verdict, isTrue);
        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 18.0,
            reason: 'la saisie manuelle ne doit pas être perdue');
        expect(p.etatGain, isNotNull);
        expect(store.predictionParId('p1')!['montantGainManuel'], 18.0);
      });
    });

    test('F2 verdict officiel ↔ MONTANT OFFICIEL TARDIF déjà écrit : le '
        'montant officiel et la décision survivent', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(
            store,
            [
              _ticket(
                montantGainManuel: 12.0,
                montantOfficielPmu: 99.0,
                decision: DecisionGainPmu.accepte,
                manuelAvantDecision: 12.0,
              )
            ]);

        pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantOfficielPmu, 99.0,
            reason: 'un montant officiel tardif ne doit pas être effacé');
        expect(p.decisionGainPmu, DecisionGainPmu.accepte,
            reason: 'une décision enregistrée ne doit pas être effacée');
        expect(p.montantGainManuel, 12.0);
        expect(p.etatGain, isNotNull);

        final d = store.predictionParId('p1')!;
        expect(d['montantOfficielPmu'], 99.0);
        expect(d['decisionGainPmu'], 'accepte');
      });
    });

    test('F3 deux verdicts concurrents sur deux tickets distincts ne se '
        'mélangent pas', () async {
      await _sansReseau(() async {
        final store = _Store();
        // Ticket 'p1' joue le 7 ; ticket 'p2' joue le 9 (absent de l'arrivée).
        final pmu = await _providerAvec(
            store, [_ticket(id: 'p1'), _ticket(id: 'p2').copyWith(numerosJoues: const [9])]);

        pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        pmu.appliquerVerdictGainPredictionSecurise('p2', _resultat());
        await pmu.sauvegardeTerminee();

        final p1 = _enMemoire(pmu, 'p1');
        final p2 = _enMemoire(pmu, 'p2');

        // ★ VALEURS MESURÉES SUR LE MOTEUR RÉEL (diagnostic temporaire) :
        //   un joueur dont la combinaison n'a AUCUN bloc publié reçoit
        //   `nonDetermine / blocJusteAbsent` — jamais `perdu`. Le moteur ne
        //   déclare pas perdant un cheval absent de l'arrivée quand le bloc
        //   de SA combinaison n'est pas publié.
        expect(p1.etatGain, EtatGain.attribue);
        expect(p2.etatGain, EtatGain.nonDetermine,
            reason: 'aucun bloc publié pour la combinaison 9');
        expect(p2.motifNonDetermination?.name, 'blocJusteAbsent');

        // Aucun mélange : chaque ticket garde sa propre combinaison.
        expect(p1.numerosJoues, const [7]);
        expect(p2.numerosJoues, const [9]);
        expect(p1.id, 'p1');
        expect(p2.id, 'p2');
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  FAMILLE G — PANNE DE SAUVEGARDE ET RÉCONCILIATION
  // ═════════════════════════════════════════════════════════════════════════

  group('G — panne de sauvegarde', () {
    test('G1 refus sans exception : la mémoire reste cohérente et le ticket '
        'n\'est pas déclaré divergent', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(
            store, [_ticket(montantGainManuel: 12.0)]);

        store.refusRestants = 1;
        pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();
        await Future<void>.delayed(Duration.zero);
        await pmu.sauvegardeTerminee();

        expect(_enMemoire(pmu, 'p1').montantGainManuel, 12.0);
        expect(_enMemoire(pmu, 'p1').etatGain, isNotNull);
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse,
            reason: 'un refus simple n\'est pas une divergence prouvée');
      });
    });

    test('G2 exception de sauvegarde : aucun champ financier n\'est perdu',
        () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(
            store, [_ticket(montantGainManuel: 12.0)]);

        store.exceptionRestantes = 1;
        pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();
        await Future<void>.delayed(Duration.zero);
        await pmu.sauvegardeTerminee();

        expect(_enMemoire(pmu, 'p1').montantGainManuel, 12.0,
            reason: 'une exception ne doit pas effacer la saisie');
        expect(_enMemoire(pmu, 'p1').etatGain, isNotNull);
      });
    });

    test('G3 `reconcilierEtatFinancier` reste fidèle après une fusion '
        'réussie', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(
            store, [_ticket(montantGainManuel: 12.0)]);

        pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();

        // Les trois champs financiers doivent concorder mémoire/disque.
        expect(await pmu.reconcilierEtatFinancier('p1'), isTrue,
            reason: 'la fusion doit laisser un état financier PROUVÉ');
        expect(pmu.nombreEtatsFinanciersDivergents, 0);
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  FAMILLE H — CHEMIN RÉEL DES DEUX ÉCRANS (garde de source)
  // ═════════════════════════════════════════════════════════════════════════

  group('H — les deux écrans réels utilisent la voie sécurisée', () {
    /// Compte les occurrences d'un motif dans un fichier, en ignorant les
    /// lignes de commentaire `//` — pour ne pas confondre une mention
    /// documentaire avec un appel réel.
    int _appelsReels(String chemin, String motif) {
      final src = File(chemin).readAsLinesSync();
      var n = 0;
      for (final l in src) {
        final t = l.trimLeft();
        if (t.startsWith('//')) continue;
        if (l.contains(motif)) n++;
      }
      return n;
    }

    test('H1 `mes_paris_screen.dart` appelle la voie sécurisée et n\'appelle '
        'PLUS l\'ancienne', () {
      const f = 'lib/screens/mes_paris_screen.dart';
      expect(_appelsReels(f, 'appliquerVerdictGainPredictionSecurise'), 1,
          reason: 'la voie sécurisée doit être empruntée');
      expect(_appelsReels(f, 'appliquerVerdictGainPrediction('), 0,
          reason: 'l\'ancienne voie dangereuse ne doit plus être appelée');
      expect(_appelsReels(f, 'resoudrePrediction('), 0,
          reason: 'aucune résolution sur instantané ne doit subsister');
    });

    test('H2 `paris_detail_screen.dart` appelle la voie sécurisée et n\'appelle '
        'PLUS l\'ancienne', () {
      const f = 'lib/screens/paris_detail_screen.dart';
      expect(_appelsReels(f, 'appliquerVerdictGainPredictionSecurise'), 1);
      expect(_appelsReels(f, 'appliquerVerdictGainPrediction('), 0);
      expect(_appelsReels(f, 'resoudrePrediction('), 0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  FAMILLE I — REDÉMARRAGE
  // ═════════════════════════════════════════════════════════════════════════

  group('I — après redémarrage', () {
    test('I1 une nouvelle instance relit EXACTEMENT les mêmes champs '
        'financiers et le verdict', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        await pmu.enregistrerGainManuelPrediction('p1', 12.0);
        pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();

        final avant = _enMemoire(pmu, 'p1');

        // « Redémarrage » : nouvelle instance, même support.
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = store;
        final pmu2 = PmuProvider();
        await pmu2.sauvegardeTerminee();
        await pmu2.reloadPredictions();
        await pmu2.sauvegardeTerminee();

        final apres = _enMemoire(pmu2, 'p1');
        expect(apres.montantGainManuel, avant.montantGainManuel);
        expect(apres.montantOfficielPmu, avant.montantOfficielPmu);
        expect(apres.decisionGainPmu, avant.decisionGainPmu);
        expect(apres.etatGain, avant.etatGain);
        expect(apres.montantGainManuel, 12.0,
            reason: 'la saisie manuelle survit au redémarrage');
      });
    });

    test('I2 `0.0` et `null` restent DISTINCTS après redémarrage', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(
            store, [_ticket(id: 'zero', montantGainManuel: 0.0), _ticket(id: 'nul')]);

        pmu.appliquerVerdictGainPredictionSecurise('zero', _resultat());
        pmu.appliquerVerdictGainPredictionSecurise('nul', _resultat());
        await pmu.sauvegardeTerminee();

        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = store;
        final pmu2 = PmuProvider();
        await pmu2.sauvegardeTerminee();
        await pmu2.reloadPredictions();
        await pmu2.sauvegardeTerminee();

        expect(_enMemoire(pmu2, 'zero').montantGainManuel, 0.0);
        expect(_enMemoire(pmu2, 'nul').montantGainManuel, isNull,
            reason: '`null` ne doit jamais devenir `0.0`');
      });
    });
  });
}
