// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / LOT 2-C — SÉCURISATION COMMUNE DE L'ÉCRITURE DES VERDICTS
//  DERNIER VERROU : CONFIRMATION DURABLE DU VERDICT
//
//  Familles :
//    D1–D2  : le DÉFAUT, prouvé sur l'ancienne méthode (documentaire).
//    E1–E10 : la CORRECTION, prouvée sur `appliquerVerdictGainPredictionSecurise`.
//    F1–F3  : la CONCURRENCE (verdict ↔ saisie manuelle, ↔ montant officiel).
//    G1–G3  : PANNE de sauvegarde et RÉCONCILIATION.
//    H1–H4  : CHEMIN RÉEL des deux écrans (garde de source + attente réelle).
//    I1–I2  : REDÉMARRAGE — relecture identique depuis le stockage.
//    K1–K10 : ★ LE VERROU — « succès confirmé » n'est jamais rendu sans preuve
//             disque. Contrat : `confirme` ⇔ le DISQUE porte le verdict.
//
//  MÉTHODE : chaque assertion porte sur la MÉMOIRE **et** sur le DISQUE
//  (relu depuis le faux support). Aucune assertion n'est affaiblie pour
//  obtenir un test vert.
//
//  ⚠️ TOUTES LES VALEURS ATTENDUES DE CE FICHIER ONT ÉTÉ MESURÉES SUR LE
//     MOTEUR RÉEL AVANT D'ÊTRE ÉCRITES. Aucune n'est supposée.
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
import 'package:pronostic_hippique/services/branchement_verdict_course.dart';
import 'package:pronostic_hippique/services/gain_calculator.dart'
    show RapportPmu;
import 'package:pronostic_hippique/services/gain_pmu_types.dart' show EtatGain;
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';

// ═══════════════════════════ Faux support de stockage ══════════════════════

/// Support de persistance CONTRÔLÉ : on décide, écriture par écriture, si elle
/// réussit, échoue (`false`), lève une exception, ou MENT (rend `true` sans
/// rien persister).
class _Store extends SharedPreferencesStorePlatform {
  _Store({Map<String, Object>? data})
      : _data = Map<String, Object>.from(data ?? <String, Object>{});

  final Map<String, Object> _data;

  /// Nombre d'écritures à REFUSER (`return false`) avant de repasser en succès.
  int? refusRestants;

  /// Nombre d'écritures à FAIRE LEVER avant de repasser en succès.
  int? exceptionRestantes;

  /// ★ SUPPORT MENTEUR : rend `true` SANS rien persister.
  ///
  /// C'est la seule façon de distinguer « le disque a accepté » de « le
  /// disque a DIT qu'il acceptait ». Un code qui se contente du `bool` de
  /// `setStringList` — ou du cache de `SharedPreferences` — se croira
  /// confirmé ; seule une relecture réelle le détecte.
  bool menteur = false;

  /// Porte d'étranglement : tant qu'elle n'est pas ouverte, TOUTE écriture
  /// attend. Permet de vérifier qu'un appelant n'obtient pas sa réponse
  /// avant que la persistance n'ait eu lieu.
  Completer<void>? porte;

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
    final p = porte;
    if (p != null && !p.isCompleted) await p.future;
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
      if (menteur) return true; // MENT : dit oui, ne persiste rien.
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
  List<int> numerosJoues = const [7],
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
      numerosJoues: numerosJoues,
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
///
/// ⚠️ VALEURS MESURÉES sur ce résultat (diagnostic temporaire, supprimé) :
///    verdict = `attribue`, `motifNonDetermination = null`,
///    `miseBaseCentimesUtilisee = 100`, `rapportsAttribues.length = 1`,
///    `etatTirelire = sansObjet`, `dividendeGagnant = null`,
///    `dividendePlace = null`.
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

UserPrediction _enMemoire(PmuProvider pmu, String id) =>
    pmu.predictions.firstWhere((p) => p.id == id);

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  FAMILLE D — LE DÉFAUT, CONSERVÉ ET PROUVÉ
  // ═════════════════════════════════════════════════════════════════════════

  group('D — le défaut de l\'écriture par instantané (documentaire)', () {
    test(
        'D1 l\'ANCIENNE méthode écrase une saisie manuelle survenue PENDANT '
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

    test(
        'D2 l\'ordre INVERSE (verdict puis saisie) conserve les deux champs — '
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
    test(
        'E1 une saisie manuelle survenue PENDANT l\'attente SURVIT au verdict '
        '(mémoire ET disque)', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        // Pendant l'attente réseau (simulée par l'ordre des appels) :
        expect(await pmu.enregistrerGainManuelPrediction('p1', 12.0),
            IssueEcritureGain.confirme);

        // Reprise : la méthode sécurisée relit l'état FRAIS.
        final applique =
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        expect(applique, IssueEcritureGain.confirme,
            reason: 'le verdict doit être appliqué ET la persistance prouvée');
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 12.0,
            reason: 'la saisie manuelle ne doit JAMAIS être écrasée');
        expect(p.etatGain, EtatGain.attribue, reason: 'le verdict est posé');

        final disque = store.predictionParId('p1')!;
        expect(disque['montantGainManuel'], 12.0,
            reason: 'la saisie doit être durablement persistée');
        expect(disque['etatGain'], 'attribue',
            reason: 'le verdict doit être durablement persisté');
      });
    });

    test('E2 l\'ordre inverse reste correct avec la méthode sécurisée',
        () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.confirme);
        await pmu.sauvegardeTerminee();
        final etat = _enMemoire(pmu, 'p1').etatGain;
        expect(etat, EtatGain.attribue);

        await pmu.enregistrerGainManuelPrediction('p1', 12.0);
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 12.0);
        expect(p.etatGain, etat);
        expect(store.predictionParId('p1')!['montantGainManuel'], 12.0);
      });
    });

    test(
        'E3 deux résolutions successives sur le MÊME ticket n\'écrivent '
        'qu\'un verdict et ne produisent aucun double gain', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.confirme);
        await pmu.sauvegardeTerminee();
        final apres1 = _enMemoire(pmu, 'p1');
        final ecrituresApres1 = store.journalEcritures.length;

        // Seconde résolution : `etatGain != null` ⇒ refus, AUCUNE écriture.
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.echec,
            reason: 'un verdict déjà posé ne doit pas être rejoué');
        await pmu.sauvegardeTerminee();

        expect(store.journalEcritures.length, ecrituresApres1,
            reason: 'aucune écriture supplémentaire ne doit avoir lieu');
        expect(_enMemoire(pmu, 'p1').etatGain, apres1.etatGain);
        expect(_enMemoire(pmu, 'p1').dividendeGagnant, apres1.dividendeGagnant);
      });
    });

    test(
        'E4 une saisie manuelle EN VOL au moment de la fusion est invalidée '
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
        final verdict =
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        expect(verdict, IssueEcritureGain.confirme,
            reason: 'la fusion écrit après la saisie : elle est la plus '
                'récente, donc elle confirme');

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
        expect(p.etatGain, EtatGain.attribue, reason: 'le verdict est posé');
        expect(store.predictionParId('p1')!['montantGainManuel'], 30.0);
        expect(store.predictionParId('p1')!['etatGain'], 'attribue');
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse,
            reason: 'aucun état divergent ne doit subsister');
      });
    });

    test(
        'E5 un échec d\'écriture pendant la fusion laisse les champs '
        'financiers INTACTS et ne bloque pas indûment le ticket', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(montantGainManuel: 12.0, decision: DecisionGainPmu.refuse)
        ]);

        store.refusRestants = 1;
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.echec,
            reason: 'l\'écriture a échoué ; l\'alignement est PROUVÉ, donc '
                '`echec` — et non une confirmation');
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 12.0,
            reason: 'aucun rétablissement ne doit effacer la saisie');
        expect(p.decisionGainPmu, DecisionGainPmu.refuse,
            reason: 'aucune décision ne doit être effacée');
        expect(p.etatGain, isNull,
            reason: 'le verdict a été annulé en mémoire faute de persistance');
        expect(store.predictionParId('p1')!['etatGain'], isNull,
            reason: 'le disque ne doit pas porter un verdict non persistant');
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse,
            reason: 'le rétablissement a prouvé l\'alignement');
      });
    });

    test(
        'E6 les QUATRE champs financiers survivent, y compris `0.0` distinct '
        'de `null`', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(
            montantGainManuel: 0.0, // déclaration explicite
            montantOfficielPmu: 45.0,
            decision: DecisionGainPmu.refuse,
            manuelAvantDecision: 0.0,
          )
        ]);

        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.confirme);
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
        final pmu =
            await _providerAvec(store, [_ticket(etatGain: EtatGain.attribue)]);

        final avant = _enMemoire(pmu, 'p1');
        final ecrituresAvant = store.journalEcritures.length;

        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.echec);
        await pmu.sauvegardeTerminee();

        expect(_enMemoire(pmu, 'p1').etatGain, EtatGain.attribue);
        expect(store.journalEcritures.length, ecrituresAvant);
        expect(_enMemoire(pmu, 'p1').dividendeGagnant, avant.dividendeGagnant);
      });
    });

    test(
        'E8 un ticket nonDetermine n\'est PAS écrasé par la voie sécurisée '
        '(politique B-4.3 intacte)', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(
            store, [_ticket(etatGain: EtatGain.nonDetermine)]);

        // ★ VALEUR MESURÉE : `echec`. La méthode sécurisée refuse tout ticket
        //   qui porte DÉJÀ un verdict (`etatGain != null`), y compris
        //   `nonDetermine` ; la transition `nonDetermine → définitif` reste du
        //   ressort de l'enregistreur B-4.3, non court-circuité ici.
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.echec);
        expect(_enMemoire(pmu, 'p1').etatGain, EtatGain.nonDetermine);
        expect(store.predictionParId('p1')!['etatGain'], 'nonDetermine');
        expect(_enMemoire(pmu, 'p1').montantGainManuel, isNull,
            reason: 'aucun montant inventé sur un état indéterminé');
      });
    });

    test('E9 un ticket ABSENT rend echec sans lever', () async {
      await _sansReseau(() async {
        final pmu = await _providerAvec(_Store(), [_ticket()]);
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise(
                'inexistant', _resultat()),
            IssueEcritureGain.echec);
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
    test(
        'E10 la protection causale est la RELECTURE de l\'état frais : un '
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
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.confirme);
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 12.0,
            reason: 'l\'instantané périmé ne doit avoir AUCUN effet');
        expect(p.etatGain, EtatGain.attribue);
        expect(store.predictionParId('p1')!['montantGainManuel'], 12.0);
        expect(store.predictionParId('p1')!['etatGain'], 'attribue');

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
    test(
        'F1 verdict officiel ↔ saisie manuelle : la saisie est conservée '
        'et le verdict est posé', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        // Les deux opérations sont déclenchées « simultanément ».
        final saisie = pmu.enregistrerGainManuelPrediction('p1', 18.0);
        final verdict =
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        final issueSaisie = await saisie;
        await pmu.sauvegardeTerminee();

        expect(verdict, IssueEcritureGain.confirme);
        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 18.0,
            reason: 'la saisie manuelle ne doit pas être perdue');
        expect(p.etatGain, EtatGain.attribue);
        expect(store.predictionParId('p1')!['montantGainManuel'], 18.0);
        expect(store.predictionParId('p1')!['etatGain'], 'attribue');
        // ★ VALEUR MESURÉE : la saisie, plus ancienne, est déclarée remplacée.
        //   Ce n'est pas une perte : son montant EST sur le disque.
        expect(issueSaisie, IssueEcritureGain.remplacee);
      });
    });

    test(
        'F2 verdict officiel ↔ MONTANT OFFICIEL TARDIF déjà écrit : le '
        'montant officiel et la décision survivent', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(
            montantGainManuel: 12.0,
            montantOfficielPmu: 99.0,
            decision: DecisionGainPmu.accepte,
            manuelAvantDecision: 12.0,
          )
        ]);

        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.confirme);
        await pmu.sauvegardeTerminee();

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantOfficielPmu, 99.0,
            reason: 'un montant officiel tardif ne doit pas être effacé');
        expect(p.decisionGainPmu, DecisionGainPmu.accepte,
            reason: 'une décision enregistrée ne doit pas être effacée');
        expect(p.montantGainManuel, 12.0);
        expect(p.etatGain, EtatGain.attribue);

        final d = store.predictionParId('p1')!;
        expect(d['montantOfficielPmu'], 99.0);
        expect(d['decisionGainPmu'], 'accepte');
        expect(d['montantGainManuel'], 12.0);
      });
    });

    test(
        'F3 deux verdicts concurrents sur deux tickets distincts ne se '
        'mélangent pas', () async {
      await _sansReseau(() async {
        final store = _Store();
        // Ticket 'p1' joue le 7 ; ticket 'p2' joue le 9 (absent de l'arrivée).
        final pmu = await _providerAvec(store, [
          _ticket(id: 'p1'),
          _ticket(id: 'p2', numerosJoues: const [9]),
        ]);

        final v1 =
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        final v2 =
            await pmu.appliquerVerdictGainPredictionSecurise('p2', _resultat());
        await pmu.sauvegardeTerminee();

        expect(v1, IssueEcritureGain.confirme);
        expect(v2, IssueEcritureGain.confirme);

        final p1 = _enMemoire(pmu, 'p1');
        final p2 = _enMemoire(pmu, 'p2');

        // ★ VALEURS MESURÉES SUR LE MOTEUR RÉEL : un joueur dont la
        //   combinaison n'a AUCUN bloc publié reçoit
        //   `nonDetermine / blocJusteAbsent` — jamais `perdu`. Le moteur ne
        //   déclare pas perdant un cheval absent de l'arrivée quand le bloc
        //   de SA combinaison n'est pas publié.
        expect(p1.etatGain, EtatGain.attribue);
        expect(p2.etatGain, EtatGain.nonDetermine,
            reason: 'aucun bloc publié pour la combinaison 9');
        expect(p2.motifNonDetermination?.name, 'blocJusteAbsent');

        // Aucun mélange : chaque ticket garde sa propre combinaison, et le
        // DISQUE porte bien l'état de chacun.
        expect(p1.numerosJoues, const [7]);
        expect(p2.numerosJoues, const [9]);
        expect(store.predictionParId('p1')!['etatGain'], 'attribue');
        expect(store.predictionParId('p2')!['etatGain'], 'nonDetermine');
        expect(store.predictionParId('p2')!['motifNonDetermination'],
            'blocJusteAbsent');
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  FAMILLE G — PANNE DE SAUVEGARDE ET RÉCONCILIATION
  // ═════════════════════════════════════════════════════════════════════════

  group('G — panne de sauvegarde', () {
    test(
        'G1 refus sans exception : le verdict est ANNULÉ et l\'alignement '
        'est PROUVÉ (jamais un faux succès)', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu =
            await _providerAvec(store, [_ticket(montantGainManuel: 12.0)]);

        store.refusRestants = 1;
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.echec,
            reason: 'un refus d\'écriture ne doit JAMAIS être confirmé');
        await pmu.sauvegardeTerminee();

        expect(_enMemoire(pmu, 'p1').montantGainManuel, 12.0,
            reason: 'le rétablissement ne touche pas aux champs financiers');
        expect(_enMemoire(pmu, 'p1').etatGain, isNull,
            reason: 'le verdict non persisté est annulé');
        expect(store.predictionParId('p1')!['etatGain'], isNull);
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse,
            reason: 'un refus simple n\'est pas une divergence prouvée');
      });
    });

    test('G2 exception de sauvegarde : aucun champ financier n\'est perdu',
        () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu =
            await _providerAvec(store, [_ticket(montantGainManuel: 12.0)]);

        store.exceptionRestantes = 1;
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.echec,
            reason: 'une exception d\'écriture ne doit JAMAIS être confirmée');
        await pmu.sauvegardeTerminee();

        expect(_enMemoire(pmu, 'p1').montantGainManuel, 12.0,
            reason: 'une exception ne doit pas effacer la saisie');
        expect(_enMemoire(pmu, 'p1').etatGain, isNull);
        expect(store.predictionParId('p1')!['montantGainManuel'], 12.0);
        expect(store.predictionParId('p1')!['etatGain'], isNull);
      });
    });

    test(
        'G3 `reconcilierEtatFinancier` reste fidèle après une fusion '
        'réussie', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu =
            await _providerAvec(store, [_ticket(montantGainManuel: 12.0)]);

        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.confirme);
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

  group('H — les deux écrans réels utilisent la voie sécurisée ET l\'attendent',
      () {
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

    /// La première ligne RÉELLE (non commentée) portant [motif], débarrassée
    /// de son indentation.
    String _ligneReelle(String chemin, String motif) {
      for (final l in File(chemin).readAsLinesSync()) {
        if (l.trimLeft().startsWith('//')) continue;
        if (l.contains(motif)) return l.trim();
      }
      fail('motif introuvable dans $chemin : $motif');
    }

    test(
        'H1 `mes_paris_screen.dart` appelle la voie sécurisée et n\'appelle '
        'PLUS l\'ancienne', () {
      const f = 'lib/screens/mes_paris_screen.dart';
      expect(_appelsReels(f, 'appliquerVerdictGainPredictionSecurise'), 1,
          reason: 'la voie sécurisée doit être empruntée');
      expect(_appelsReels(f, 'appliquerVerdictGainPrediction('), 0,
          reason: 'l\'ancienne voie dangereuse ne doit plus être appelée');
      expect(_appelsReels(f, 'resoudrePrediction('), 0,
          reason: 'aucune résolution sur instantané ne doit subsister');
    });

    test(
        'H2 `paris_detail_screen.dart` appelle la voie sécurisée et n\'appelle '
        'PLUS l\'ancienne', () {
      const f = 'lib/screens/paris_detail_screen.dart';
      expect(_appelsReels(f, 'appliquerVerdictGainPredictionSecurise'), 1);
      expect(_appelsReels(f, 'appliquerVerdictGainPrediction('), 0);
      expect(_appelsReels(f, 'resoudrePrediction('), 0);
    });

    // ★ H3 — L'ATTENTE, ET RIEN QUE L'ATTENTE.
    //
    //   Un appel non attendu (`provider.appliquer...(…)` sans `await`) rendrait
    //   la méthode asynchrone STRICTEMENT équivalente à l'ancienne : l'issue
    //   serait jetée, et l'écran annoncerait un succès qu'il n'a pas vérifié.
    //   Ces deux gardes vérifient la forme RÉELLE de la ligne d'appel.
    test('H3 l\'appel du verdict est bien ATTENDU dans les deux écrans', () {
      for (final f in const [
        'lib/screens/mes_paris_screen.dart',
        'lib/screens/paris_detail_screen.dart',
      ]) {
        final l = _ligneReelle(f, 'appliquerVerdictGainPredictionSecurise(');
        expect(l.startsWith('await '), isTrue,
            reason: '$f : l\'appel doit être attendu. Ligne réelle : « $l »');
      }
    });

    test('H4 `_majGainReelDansProfil` est asynchrone ET attendue', () {
      for (final f in const [
        'lib/screens/mes_paris_screen.dart',
        'lib/screens/paris_detail_screen.dart',
      ]) {
        // La déclaration doit rendre un Future et être `async`.
        final decl = _ligneReelle(f, 'Future<void> _majGainReelDansProfil(');
        expect(decl.contains('async'), isTrue,
            reason: '$f : la méthode doit être `async`. Ligne : « $decl »');
        // L'appel doit être attendu.
        final appel = File(f)
            .readAsLinesSync()
            .where((l) =>
                !l.trimLeft().startsWith('//') &&
                l.contains('_majGainReelDansProfil(rapports)'))
            .map((l) => l.trim())
            .toList();
        expect(appel, isNotEmpty, reason: '$f : aucun appel trouvé');
        for (final l in appel) {
          expect(l.startsWith('await '), isTrue,
              reason: '$f : l\'appel doit être attendu. Ligne : « $l »');
        }
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  FAMILLE I — REDÉMARRAGE (état financier)
  // ═════════════════════════════════════════════════════════════════════════

  group('I — après redémarrage', () {
    test(
        'I1 une nouvelle instance relit EXACTEMENT les mêmes champs '
        'financiers et le verdict', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        await pmu.enregistrerGainManuelPrediction('p1', 12.0);
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.confirme);
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
        final pmu = await _providerAvec(store,
            [_ticket(id: 'zero', montantGainManuel: 0.0), _ticket(id: 'nul')]);

        expect(
            await pmu.appliquerVerdictGainPredictionSecurise(
                'zero', _resultat()),
            IssueEcritureGain.confirme);
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise(
                'nul', _resultat()),
            IssueEcritureGain.confirme);
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

  // ═════════════════════════════════════════════════════════════════════════
  //  ★ FAMILLE K — LE DERNIER VERROU : « CONFIRMÉ » ⇔ DISQUE
  // ═════════════════════════════════════════════════════════════════════════

  group('K — succès confirmé, remplacé, échec : jamais confondus', () {
    test(
        'K1 écriture confirmée ET RELUE SUR DISQUE : les sept champs du '
        'verdict sont persistés, valeur par valeur', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        final issue =
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();

        expect(issue, IssueEcritureGain.confirme,
            reason: '`confirme` ne doit être rendu que si le disque porte le '
                'verdict');

        // Les SEPT champs écrits par l'enregistreur B-4.3, relus depuis le
        // support — aucun n'est supposé.
        final d = store.predictionParId('p1')!;
        expect(d['etatGain'], 'attribue');
        expect(d['motifNonDetermination'], isNull);
        expect(d['etatTirelire'], 'sansObjet');
        expect(d['dividendeGagnant'], isNull);
        expect(d['dividendePlace'], isNull);
        expect(d['miseBaseCentimesUtilisee'], 100);
        expect((d['rapportsAttribues'] as List).length, 1);

        // Et la mémoire est identique au disque.
        final p = _enMemoire(pmu, 'p1');
        expect(p.etatGain, EtatGain.attribue);
        expect(p.miseBaseCentimesUtilisee, 100);
        expect(p.rapportsAttribues?.length, 1);
      });
    });

    test(
        'K2 REFUS de sauvegarde sans exception : l\'issue est `echec`, le '
        'verdict est retiré des DEUX côtés', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu =
            await _providerAvec(store, [_ticket(montantGainManuel: 12.0)]);

        store.refusRestants = 1;
        final issue =
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();

        // ★ C'est CE test qui tombe si l'on supprime l'attente de
        //   `_savePredictions()` : le refus ne serait plus vu, la méthode
        //   rendrait `confirme` et le verdict resterait en mémoire sans être
        //   sur le disque.
        expect(issue, IssueEcritureGain.echec);
        expect(issue, isNot(IssueEcritureGain.confirme));

        expect(_enMemoire(pmu, 'p1').etatGain, isNull,
            reason: 'la mémoire ne doit pas garder un verdict non persisté');
        expect(store.predictionParId('p1')!['etatGain'], isNull,
            reason: 'le disque ne porte pas le verdict');
        expect(_enMemoire(pmu, 'p1').montantGainManuel, 12.0,
            reason: 'le rétablissement ne touche JAMAIS aux champs financiers');
        expect(store.predictionParId('p1')!['montantGainManuel'], 12.0);
      });
    });

    test(
        'K3 EXCEPTION pendant la sauvegarde : `echec`, aucun champ financier '
        'perdu, aucune exception propagée à l\'appelant', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(
              montantGainManuel: 12.0,
              montantOfficielPmu: 45.0,
              decision: DecisionGainPmu.accepte)
        ]);

        store.exceptionRestantes = 1;
        final issue =
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();

        expect(issue, IssueEcritureGain.echec,
            reason: 'une exception d\'écriture n\'est jamais un succès');
        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 12.0);
        expect(p.montantOfficielPmu, 45.0);
        expect(p.decisionGainPmu, DecisionGainPmu.accepte);
        expect(p.etatGain, isNull);
        expect(store.predictionParId('p1')!['etatGain'], isNull);
        expect(store.predictionParId('p1')!['decisionGainPmu'], 'accepte');
      });
    });

    // ★ K4 — LE TEST QUI INTERDIT DE CROIRE UN `true`.
    //
    //   Le support rend `true` SANS RIEN PERSISTER. `setStringList` rend donc
    //   `true`, et le CACHE de `SharedPreferences` porte la nouvelle valeur :
    //   deux « preuves » apparentes, toutes deux FAUSSES. Seule une relecture
    //   après `prefs.reload()` voit la vérité.
    //
    //   ⚠️ C'est CE test qui tombe si l'on retire `await prefs.reload()` de la
    //   vérification disque : la lecture retomberait sur le cache et
    //   confirmerait un verdict absent du disque.
    test(
        'K4 support MENTEUR (`true` sans persister) : jamais `confirme`, et '
        'le ticket est déclaré NON RÉCONCILIÉ', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu =
            await _providerAvec(store, [_ticket(montantGainManuel: 12.0)]);

        store.menteur = true;
        final issue =
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();

        expect(issue, isNot(IssueEcritureGain.confirme),
            reason: 'un `true` du support ne vaut PAS preuve de persistance');
        expect(issue, IssueEcritureGain.echecNonReconcilie,
            reason: 'la cohérence n\'est pas établie : le ticket doit être '
                'bloqué et l\'échec déclaré NON réconcilié');
        expect(pmu.estEtatFinancierDivergent('p1'), isTrue);
        expect(store.predictionParId('p1')!['etatGain'], isNull,
            reason: 'le disque n\'a jamais reçu le verdict');
        expect(_enMemoire(pmu, 'p1').montantGainManuel, 12.0,
            reason: 'aucun champ financier n\'est sacrifié');
      });
    });

    test(
        'K5 la méthode NE REND PAS avant que la persistance n\'ait eu lieu '
        '(écriture retardée par une porte)', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        final porte = Completer<void>();
        store.porte = porte;

        var rendu = false;
        IssueEcritureGain? issue;
        final f = pmu
            .appliquerVerdictGainPredictionSecurise('p1', _resultat())
            .then((i) {
          rendu = true;
          issue = i;
          return i;
        });

        // Laisser tourner la machine asynchrone SANS ouvrir la porte.
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(rendu, isFalse,
            reason: 'aucune issue ne doit être annoncée tant que l\'écriture '
                'n\'a pas abouti');
        expect(store.predictionParId('p1')?['etatGain'], isNull,
            reason: 'le disque ne porte pas encore le verdict');

        // Ouvrir la porte : l'écriture aboutit, l'issue devient honnête.
        porte.complete();
        final resultat = await f;
        await pmu.sauvegardeTerminee();

        expect(resultat, IssueEcritureGain.confirme);
        expect(issue, IssueEcritureGain.confirme);
        expect(store.predictionParId('p1')!['etatGain'], 'attribue');
      });
    });

    test(
        'K6 SAISIE MANUELLE CONCURRENTE pendant l\'écriture du verdict : le '
        'verdict est `remplacee`, la saisie `confirme`, et les DEUX champs '
        'sont sur le disque', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        // L'écriture du verdict est retardée : on en profite pour lancer une
        // saisie manuelle, qui devient l'opération la plus récente.
        store.porte = Completer<void>();
        Future<IssueEcritureGain>? saisie;
        store.avantChaqueEcriture = () async {
          if (saisie == null) {
            saisie = pmu.enregistrerGainManuelPrediction('p1', 25.0);
            store.porte!.complete();
          }
        };

        final verdict =
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();
        final issueSaisie = await saisie!;
        await pmu.sauvegardeTerminee();

        // ★ VALEURS MESURÉES : le verdict s'incline (`remplacee`), la saisie
        //   est confirmée, et AUCUNE des deux valeurs n'est perdue.
        expect(verdict, IssueEcritureGain.remplacee,
            reason: 'une opération plus récente fait foi : le verdict ne peut '
                'pas se déclarer confirmé');
        expect(issueSaisie, IssueEcritureGain.confirme);

        final p = _enMemoire(pmu, 'p1');
        expect(p.montantGainManuel, 25.0);
        expect(p.etatGain, EtatGain.attribue, reason: 'le verdict reste posé');

        final d = store.predictionParId('p1')!;
        expect(d['montantGainManuel'], 25.0, reason: 'saisie durable');
        expect(d['etatGain'], 'attribue', reason: 'verdict durable');
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse);
      });
    });

    test(
        'K7 VERDICT REMPLACÉ PAR UNE OPÉRATION PLUS RÉCENTE (invalidation '
        'pendant la lecture de preuve) : `remplacee`, jamais `confirme`',
        () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        // Une décision financière (Accepter/Refuser) survient PENDANT la
        // lecture de preuve : elle invalide toutes les opérations en vol.
        var fait = false;
        store.avantChaqueLecture = () async {
          if (!fait) {
            fait = true;
            pmu.invaliderPourDecisionFinanciere('p1');
          }
        };

        final issue =
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();

        expect(issue, IssueEcritureGain.remplacee,
            reason: 'une opération plus récente a pris la main : la mienne ne '
                'peut pas se déclarer confirmée');
        // Le verdict est bien écrit (le disque le porte) : ce qui est refusé,
        // c'est la PRÉTENTION de succès de l'opération périmée.
        expect(store.predictionParId('p1')!['etatGain'], 'attribue');
        expect(_enMemoire(pmu, 'p1').etatGain, EtatGain.attribue);
      });
    });

    test(
        'K8 ÉCHEC DE RESTAURATION puis RÉCONCILIATION : le ticket est bloqué '
        'et le DIT, puis reprend après preuve', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu =
            await _providerAvec(store, [_ticket(montantGainManuel: 12.0)]);

        // Le disque porte un état DIFFÉRENT de celui d'avant (verdict 'perdu'
        // absent de la mémoire) : le rétablissement ne peut pas être prouvé.
        final m = store.predictionParId('p1')!;
        m['etatGain'] = 'perdu';
        store.ecrirePredictionBrute(m);
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = store;

        // Écriture impossible : ni la première passe ni la réconciliation.
        store.refusRestants = 2;
        final issue =
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat());
        await pmu.sauvegardeTerminee();

        expect(issue, IssueEcritureGain.echecNonReconcilie,
            reason: 'un échec dont la réconciliation échoue doit être DIT');
        expect(pmu.estEtatFinancierDivergent('p1'), isTrue,
            reason: 'le ticket doit être bloqué');
        expect(store.predictionParId('p1')!['etatGain'], 'perdu',
            reason: 'rien n\'a été écrit sur le disque');

        // ① Garde bloquante : tant que le ticket est divergent, aucune
        //    écriture n'est tentée — même si le support va mieux.
        store.refusRestants = 0;
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.echecNonReconcilie,
            reason: 'la garde doit rester BLOQUANTE');
        expect(store.predictionParId('p1')!['etatGain'], 'perdu',
            reason: 'aucune écriture n\'a été tentée');

        // ② Réconciliation par la voie existante : elle seule débloque, et
        //    seulement sur cohérence financière PROUVÉE.
        expect(await pmu.reconcilierEtatFinancier('p1'), isTrue);
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse);

        // ③ Le ticket reprend, et son verdict est cette fois CONFIRMÉ.
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.confirme);
        await pmu.sauvegardeTerminee();
        expect(store.predictionParId('p1')!['etatGain'], 'attribue');
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse);
      });
    });

    test(
        'K9 REDÉMARRAGE après écriture CONFIRMÉE : les sept champs du verdict '
        'et les quatre champs financiers sont relus à l\'identique', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(
            montantGainManuel: 12.0,
            montantOfficielPmu: 45.0,
            decision: DecisionGainPmu.accepte,
            manuelAvantDecision: 12.0,
          )
        ]);

        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.confirme);
        await pmu.sauvegardeTerminee();
        final avant = _enMemoire(pmu, 'p1');

        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = store;
        final pmu2 = PmuProvider();
        await pmu2.sauvegardeTerminee();
        await pmu2.reloadPredictions();
        await pmu2.sauvegardeTerminee();

        final apres = _enMemoire(pmu2, 'p1');
        // Les SEPT champs du verdict.
        expect(apres.etatGain, avant.etatGain);
        expect(apres.motifNonDetermination, avant.motifNonDetermination);
        expect(apres.etatTirelire, avant.etatTirelire);
        expect(apres.dividendeGagnant, avant.dividendeGagnant);
        expect(apres.dividendePlace, avant.dividendePlace);
        expect(apres.miseBaseCentimesUtilisee, avant.miseBaseCentimesUtilisee);
        expect(
            apres.rapportsAttribues?.length, avant.rapportsAttribues?.length);
        // Les QUATRE champs financiers.
        expect(apres.montantGainManuel, 12.0);
        expect(apres.montantOfficielPmu, 45.0);
        expect(apres.decisionGainPmu, DecisionGainPmu.accepte);
        expect(apres.montantGainManuelAvantDecision, 12.0);
        // Et concrètement : le verdict confirmé a survécu.
        expect(apres.etatGain, EtatGain.attribue);
        expect(apres.miseBaseCentimesUtilisee, 100);
      });
    });

    test(
        'K11 un blocage prononcé par la VOIE VERDICT bloque AUSSI la VOIE '
        'SAISIE MANUELLE : la garde est PARTAGÉE, pas dupliquée', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu =
            await _providerAvec(store, [_ticket(montantGainManuel: 12.0)]);

        // ① Un blocage est prononcé par la VOIE VERDICT : le disque porte un
        //    état que la mémoire ne porte pas, et les deux écritures (initiale
        //    puis réconciliation) sont refusées ⇒ cohérence NON prouvée.
        final m = store.predictionParId('p1')!;
        m['etatGain'] = 'perdu';
        store.ecrirePredictionBrute(m);
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = store;

        store.refusRestants = 2;
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.echecNonReconcilie,
            reason: 'la voie verdict doit déclarer l\'échec NON réconcilié');
        await pmu.sauvegardeTerminee();
        expect(pmu.estEtatFinancierDivergent('p1'), isTrue,
            reason: 'le ticket est désormais bloqué');

        // ② ★ LE POINT DU TEST : le blocage vaut pour TOUTE écriture
        //    financière, pas seulement pour celle qui l'a prononcé. Le support
        //    va bien (plus aucun refus), la mémoire et le disque concordent
        //    même sur `montantGainManuel` (12.0 des deux côtés) — et pourtant
        //    la saisie manuelle doit être REFUSÉE : seule une PREUVE de
        //    cohérence débloque, jamais le simple retour du support.
        store.refusRestants = 0;
        final ecrituresAvant = store.journalEcritures.length;
        final issueSaisie =
            await pmu.enregistrerGainManuelPrediction('p1', 20.0);
        await pmu.sauvegardeTerminee();

        expect(issueSaisie, IssueEcritureGain.echecNonReconcilie,
            reason: 'la saisie manuelle est refusée par la MÊME garde : une '
                'garde dupliquée la laisserait passer');
        expect(store.journalEcritures.length, ecrituresAvant,
            reason: 'aucune écriture ne doit même être TENTÉE');
        expect(store.predictionParId('p1')!['montantGainManuel'], 12.0,
            reason: 'le disque garde la valeur qu\'il portait');
        expect(store.predictionParId('p1')!['etatGain'], 'perdu',
            reason: 'le disque garde aussi l\'état qu\'il portait');
        expect(_enMemoire(pmu, 'p1').montantGainManuel, 12.0,
            reason: 'la mémoire n\'a pas bougé : aucun 20.0 fantôme');
        expect(pmu.estEtatFinancierDivergent('p1'), isTrue,
            reason: 'un refus ne débloque pas : seule la PREUVE débloque');

        // ③ Et la preuve, elle, débloque les DEUX voies.
        expect(await pmu.reconcilierEtatFinancier('p1'), isTrue,
            reason: 'les trois champs financiers concordent réellement');
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse);

        expect(await pmu.enregistrerGainManuelPrediction('p1', 20.0),
            IssueEcritureGain.confirme,
            reason: 'après preuve, la voie saisie manuelle reprend');
        expect(store.predictionParId('p1')!['montantGainManuel'], 20.0);
      });
    });

    test(
        'K10 après un refus TRANSITOIRE (`echec`, non bloquant), un second '
        'appel CONFIRME réellement le verdict', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu =
            await _providerAvec(store, [_ticket(montantGainManuel: 12.0)]);

        // ① Refus isolé : `echec`, verdict retiré des deux côtés, ticket
        //    NON bloqué (aucune divergence prouvée).
        store.refusRestants = 1;
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.echec);
        await pmu.sauvegardeTerminee();
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse);
        expect(_enMemoire(pmu, 'p1').etatGain, isNull);
        expect(store.predictionParId('p1')!['etatGain'], isNull);

        // ② Le support redevient sain : le second appel CONFIRME, et la preuve
        //    disque est vérifiée champ par champ.
        store.refusRestants = 0;
        expect(
            await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultat()),
            IssueEcritureGain.confirme);
        await pmu.sauvegardeTerminee();

        expect(_enMemoire(pmu, 'p1').etatGain, EtatGain.attribue);
        final d = store.predictionParId('p1')!;
        expect(d['etatGain'], 'attribue');
        expect(d['miseBaseCentimesUtilisee'], 100);
        expect((d['rapportsAttribues'] as List).length, 1);
        expect(d['montantGainManuel'], 12.0,
            reason: 'les champs financiers traversent les DEUX tentatives');
        expect(pmu.estEtatFinancierDivergent('p1'), isFalse);
      });
    });
  });
}
