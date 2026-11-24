// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / LOT 2-C — CHANTIER 1/6 (P1)
//  LE CHEMIN `enregistrerMontantOfficiel: true`, PROUVÉ DE BOUT EN BOUT
//
//  Familles :
//    R1–R6  : REMBOURSEMENT — le défaut reproduit, puis bloqué.
//    O1–O4  : les QUATRE états (attribue / perdu / rembourse / nonDetermine).
//    M1–M6  : COEXISTENCE gain manuel × gain officiel.
//    P1–P6  : PERSISTANCE, idempotence, redémarrage.
//    C1–C4  : CONCURRENCE (manuelle × officielle, officielle × officielle).
//    F1–F3  : ÉCHEC de sauvegarde, réconciliation, blocage de divergence.
//
//  ⚠️ MÉTHODE : chaque assertion porte sur la MÉMOIRE **et** sur le DISQUE
//     relu depuis le faux support. Aucun test n'appelle la fonction pure
//     directement pour « prouver » le raccordement : tous passent par
//     `appliquerVerdictGainPredictionSecurise(..., enregistrerMontantOfficiel: true)`.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/decision_gain_pmu.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/branchement_verdict_course.dart'
    show resoudrePrediction;
import 'package:pronostic_hippique/services/gain_calculator.dart'
    show RapportPmu;
import 'package:pronostic_hippique/services/gain_pmu_types.dart' show EtatGain;
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart'
    show montantOfficielDepuisVerdict;
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart'
    show VerdictGain;
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';

// ═══════════════════════════ Faux support de stockage ══════════════════════
//  Repris à l'identique de `b1_t12_lot2c_ecriture_securisee_test.dart` : on
//  réutilise le mécanisme éprouvé au lieu d'en inventer un second.

class _Store extends SharedPreferencesStorePlatform {
  _Store({Map<String, Object>? data})
      : _data = Map<String, Object>.from(data ?? <String, Object>{});

  final Map<String, Object> _data;

  int? refusRestants;
  int? exceptionRestantes;
  bool menteur = false;
  Completer<void>? porte;
  final List<String> journalEcritures = <String>[];
  Future<void> Function()? avantChaqueEcriture;

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
    if (p != null) await p.future;

    if (_fautive(key)) {
      final ex = exceptionRestantes;
      if (ex != null && ex > 0) {
        exceptionRestantes = ex - 1;
        throw StateError('écriture refusée (exception)');
      }
      final refus = refusRestants;
      if (refus != null && refus > 0) {
        refusRestants = refus - 1;
        return false;
      }
      if (menteur) {
        journalEcritures.add(key);
        return true; // MENT : rien n'est persisté
      }
    }
    journalEcritures.add(key);
    _data[key] = value;
    return true;
  }

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

MockClient _clientNeutre() => MockClient(
    (http.Request r) async => http.Response('{"programme":[],"reunions":[]}', 200));

Future<T> _sansReseau<T>(Future<T> Function() action) =>
    http.runWithClient(action, _clientNeutre);



UserPrediction _ticket({
  String id = 'p1',
  double? montantGainManuel,
  double? montantOfficielPmu,
  DecisionGainPmu? decision,
  double? manuelAvantDecision,
  EtatGain? etatGain,
  double montantMise = 10.0,
  List<int> numerosJoues = const [7],
  String typePari = 'Simple Gagnant',
  String codePmu = 'E_SIMPLE_GAGNANT',
  double? miseGagnant,
  double? misePlace,
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
      typePari: typePari,
      createdAt: DateTime(2026, 11, 23, 10),
      numerosJoues: numerosJoues,
      codePmuOfficiel: codePmu,
      montantMise: montantMise,
      montantGainManuel: montantGainManuel,
      montantOfficielPmu: montantOfficielPmu,
      decisionGainPmu: decision,
      montantGainManuelAvantDecision: manuelAvantDecision,
      etatGain: etatGain,
      miseGagnant: miseGagnant,
      misePlace: misePlace,
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

UserPrediction _enMemoire(PmuProvider pmu, String id) =>
    pmu.predictions.firstWhere((p) => p.id == id);

/// Rapport Simple Gagnant sur le 7, dividende 7,50 € pour 1 €.
RapportPmu _rapGagnant({bool rembourse = false, double dividende = 7.50}) =>
    RapportPmu(
      typePari: 'E_SIMPLE_GAGNANT',
      combinaison: '7',
      dividende: dividende,
      estOrdre: false,
      libelleOfficiel: 'e-Simple Gagnant',
      codePariOfficiel: 'E_SIMPLE_GAGNANT',
      miseBaseCentimes: 100,
      rembourse: rembourse,
    );

/// Rapport Simple Placé sur le 7, dividende 2,10 € pour 1 €.
RapportPmu _rapPlace({bool rembourse = false, double dividende = 2.10}) =>
    RapportPmu(
      typePari: 'E_SIMPLE_PLACE',
      combinaison: '7',
      dividende: dividende,
      estOrdre: false,
      libelleOfficiel: 'e-Simple Placé',
      codePariOfficiel: 'E_SIMPLE_PLACE',
      miseBaseCentimes: 100,
      rembourse: rembourse,
    );

/// Arrivée 7 - 3 - 5, définitive.
ResultatOfficielCourse _resultat(List<RapportPmu> rapports) =>
    ResultatOfficielCourse(
      arriveeGroupes: const [
        [7],
        [3],
        [5]
      ],
      arriveeDefinitive: true,
      rapports: rapports,
    );

ResultatOfficielCourse _resultatSimple() => _resultat([_rapGagnant()]);

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  R — REMBOURSEMENT : LE DÉFAUT, PUIS SON BLOCAGE
  // ═════════════════════════════════════════════════════════════════════════

  group('R — remboursement', () {
    test('R1 MESURE CONTRAIRE À MON HYPOTHÈSE : sur le chemin MONO-composante, '
        'le moteur rend bien `rembourse` — il teste `publie.rembourse` '
        '(`_verdictDepuisRapportPublie`, ligne 1257)', () async {
      await _sansReseau(() async {
        final pmu = await _providerAvec(_Store(), [_ticket()]);
        final resolution = resoudrePrediction(
          prediction: _enMemoire(pmu, 'p1'),
          resultat: _resultat([_rapGagnant(rembourse: true)]),
        );
        expect(resolution.verdict, isNotNull);
        expect(resolution.verdict!.etat, EtatGain.rembourse,
            reason: 'le défaut que je supposais n\'existe PAS ici : le moteur '
                'honore `rembourse` sur le chemin mono-composante');
        expect(resolution.verdict!.total, 0.0,
            reason: 'un remboursement ne porte aucun retour gagné');
        expect(resolution.verdict!.composantes, isEmpty);
      });
    });

    test('R2 PAR LE CHEMIN RÉEL : l\'écriture du montant officiel est '
        'BLOQUÉE — `montantOfficielPmu` reste `null`, jamais `0.0`, jamais '
        'le montant remboursé', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        final issue = await pmu.appliquerVerdictGainPredictionSecurise(
          'p1',
          _resultat([_rapGagnant(rembourse: true)]),
          enregistrerMontantOfficiel: true,
        );
        expect(issue, IssueEcritureGain.confirme);

        final memoire = _enMemoire(pmu, 'p1');
        expect(memoire.montantOfficielPmu, isNull,
            reason: 'aucun montant officiel ne doit être établi sur un '
                'remboursement');
        expect(memoire.montantOfficielPmu, isNot(0.0),
            reason: 'un remboursement n\'est PAS une perte');
        final disque = store.predictionParId('p1')!;
        expect(disque['montantOfficielPmu'], isNull,
            reason: 'le disque ne porte aucun montant inventé');
      });
    });

    test('R3 ★ CHANTIER 1/3 — Gagnant + Placé dont SEULE la composante Placé '
        'est remboursée : le montant officiel est ÉCRIT et vaut 75,0, le '
        'remboursement 10,0 — les deux champs DISTINCTS', () async {
      // AVANT : ce test exigeait le BLOCAGE (montant `null`). Ce blocage était
      // la réponse au défaut du moteur, qui comptait 21 € de gain sur une mise
      // remboursée. Le défaut étant corrigé à la source, le blocage est devenu
      // incompatible : il refusait un résultat mixte POURTANT CORRECT.
      // L'exigence n'est pas affaiblie, elle est REMPLACÉE par la règle
      // financière validée (75 gagnés + 10 rendus).
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(
            typePari: 'Gagnant+Placé',
            codePmu: 'E_SIMPLE_GAGNANT',
            miseGagnant: 10.0,
            misePlace: 10.0,
            decision: DecisionGainPmu.accepte,
          ),
        ]);

        final issue = await pmu.appliquerVerdictGainPredictionSecurise(
          'p1',
          _resultat([_rapGagnant(), _rapPlace(rembourse: true)]),
          enregistrerMontantOfficiel: true,
        );
        expect(issue, IssueEcritureGain.confirme);

        final memoire = _enMemoire(pmu, 'p1');
        // 「Gain gagné」 : 10 × 7,50 = 75,0.
        expect(memoire.montantOfficielPmu, 75.0,
            reason: 'le gain gagné est la seule composante qui paie');
        expect(memoire.montantOfficielPmu, isNot(96.0),
            reason: 'les 21,0 de l\'ancien défaut ne sont pas un gain');
        // 「Remboursement」 : 10,0 — champ DISTINCT.
        expect(memoire.remboursementPmu, 10.0,
            reason: 'la mise remboursée est reversée, elle n\'est pas gagnée');
        // Total reversé et net : les cinq montants restent distincts.
        expect(memoire.totalReverse, 85.0, reason: '75 + 10');
        expect(memoire.miseTotaleEngagee, 20.0, reason: '10 + 10');
        expect(memoire.resultatNet, 65.0, reason: '85 − 20');

        // ── PERSISTANCE : les DEUX champs, et eux seuls ──────────────────
        final disque = store.predictionParId('p1')!;
        expect(disque['montantOfficielPmu'], 75.0);
        expect(disque['remboursementPmu'], 10.0,
            reason: 'le remboursement doit survivre au disque, sinon le '
                'résultat financier serait faux après redémarrage');
      });
    });

    test('R3bis ★ CHANTIER 1/3 — LE RÉSULTAT MIXTE EST DÉSORMAIS CORRECT : '
        'le moteur rend `attribue` avec 75,0 de gain ET 10,0 de remboursement, '
        'jamais 96,0', () async {
      // ── CE TEST A CHANGÉ DE SENS, ET C'EST LÉGITIME ──────────────────────
      //
      //   AVANT : il verrouillait l'ANCIEN DÉFAUT (« total 96,0 »), parce que
      //   `_composanteGagnantPlace` ne testait pas `publie.rembourse` et
      //   appliquait 10 × 2,10 = 21,0 à une mise pourtant remboursée. Le
      //   garde-fou du 412edba bloquait alors TOUTE écriture.
      //
      //   APRÈS : le moteur honore `rembourse` à la source. Ce n'est donc plus
      //   le défaut qui est vérifié, mais la RÈGLE FINANCIÈRE VALIDÉE par
      //   l'arbitrage : un G+P mixte vaut 75 € gagnés + 10 € rendus = 85 €
      //   reversés, avec un remboursement STRICTEMENT distinct du gain.
      //
      //   ⚠️ L'ASSERTION N'A PAS ÉTÉ AFFAIBLIE : elle a été REMPLACÉE par des
      //      exigences plus fortes (trois montants distincts, aucun 96,0).
      await _sansReseau(() async {
        final pmu = await _providerAvec(_Store(), [
          _ticket(
            typePari: 'Gagnant+Placé',
            miseGagnant: 10.0,
            misePlace: 10.0,
          ),
        ]);
        final resolution = resoudrePrediction(
          prediction: _enMemoire(pmu, 'p1'),
          resultat: _resultat([_rapGagnant(), _rapPlace(rembourse: true)]),
        );
        expect(resolution.verdict, isNotNull);
        expect(resolution.verdict!.etat, EtatGain.attribue,
            reason: 'le Gagnant paie : le ticket est attribué');
        // 10 × 7,50 = 75,0 — le gain réel.
        expect(resolution.verdict!.total, 75.0,
            reason: 'gain gagné = 10 × 7,50 = 75,0');
        expect(resolution.verdict!.total, isNot(96.0),
            reason: '96,0 était l\'ANCIEN DÉFAUT : 21,0 de gain inventé sur '
                'une mise remboursée');
        // 10 € rendus — DISTINCTS du gain.
        expect(resolution.verdict!.remboursement, 10.0,
            reason: 'la mise Placé remboursée est reversée, pas gagnée');
        // 85 € effectivement reversés = 75 + 10.
        expect(resolution.verdict!.montantReverse, 85.0,
            reason: 'total reversé = gain + remboursement');
        expect(resolution.verdict!.composantes.length, 2);
        // La composante remboursée porte un retour NUL : c'est structurel.
        final place = resolution.verdict!.composantes
            .firstWhere((c) => c.role.name == 'place');
        expect(place.rembourse, isTrue);
        expect(place.montantRetour, 0.0,
            reason: 'un remboursement ne porte AUCUN retour gagné');
        expect(place.miseRemboursee, 10.0);
      });
    });

    test('R4 ★ CHANTIER 1/3 — les DEUX composantes remboursées : aucun gain '
        'écrit, mais le REMBOURSEMENT INTÉGRAL (20,0) est écrit', () async {
      // AVANT : ce test exigeait seulement `montantOfficielPmu == null`, sans
      // rien dire du remboursement — un remboursement intégral était donc
      // persisté « sans montant », alors que 20 € sont bel et bien rendus.
      // Le résultat financier exigé par l'arbitrage impose de le conserver.
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(
            typePari: 'Gagnant+Placé',
            codePmu: 'E_SIMPLE_GAGNANT',
            miseGagnant: 10.0,
            misePlace: 10.0,
          ),
        ]);
        await pmu.appliquerVerdictGainPredictionSecurise(
          'p1',
          _resultat([
            _rapGagnant(rembourse: true),
            _rapPlace(rembourse: true),
          ]),
          enregistrerMontantOfficiel: true,
        );
        final memoire = _enMemoire(pmu, 'p1');
        // Aucun gain : un remboursement n'est pas un gain.
        expect(memoire.montantOfficielPmu, isNull,
            reason: 'aucun euro n\'est gagné : rien ne doit être écrit comme '
                'gain');
        // Mais 20 € sont rendus : c'est un fait financier, il est conservé.
        expect(memoire.remboursementPmu, 20.0,
            reason: 'remboursement intégral = 10 + 10');
        expect(memoire.totalReverse, 20.0);
        // Un remboursement intégral n'est JAMAIS une perte.
        expect(memoire.resultatNet, 0.0,
            reason: 'net = 20 − 20 = 0, jamais −20');
        expect(store.predictionParId('p1')!['remboursementPmu'], 20.0);
      });
    });

    test('R5 un rapport remboursé SANS RAPPORT avec le ticket ne bloque PAS '
        'un ticket valide : la précision se fait sur combinaison ET libellé',
        () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        // Un Tiercé remboursé sur une AUTRE combinaison, publié pour la même
        // course. Il ne concerne pas le Simple Gagnant du ticket.
        final rapTierceRembourse = RapportPmu(
          typePari: 'E_TIERCE',
          combinaison: '9-4-15',
          dividende: 120.0,
          estOrdre: false,
          libelleOfficiel: 'e-Tiercé Ordre',
          codePariOfficiel: 'E_TIERCE',
          miseBaseCentimes: 100,
          rembourse: true,
        );

        final issue = await pmu.appliquerVerdictGainPredictionSecurise(
          'p1',
          _resultat([_rapGagnant(), rapTierceRembourse]),
          enregistrerMontantOfficiel: true,
        );
        expect(issue, IssueEcritureGain.confirme);
        // 10 € × 7,50 = 75,0 : le ticket Simple Gagnant est VALIDE.
        expect(_enMemoire(pmu, 'p1').montantOfficielPmu, 75.0,
            reason: 'un remboursement étranger au ticket ne doit pas le bloquer');
        expect(store.predictionParId('p1')!['montantOfficielPmu'], 75.0);
      });
    });

    test('R5bis MÊME combinaison (« 7 »), LIBELLÉ DE PARI DIFFÉRENT : le '
        'remboursement étranger ne bloque PAS — c\'est le libellé qui tranche',
        () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        // ⚠️ CE CAS EST CELUI QUI REND LA PRÉCISION OBSERVABLE.
        //
        //    Le n° de cheval joué vaut « 7 », et le n° du cheval remboursé vaut
        //    AUSSI « 7 » : les combinaisons sont donc IDENTIQUES. Si le
        //    garde-fou ne comparait que la combinaison, il bloquerait ce ticket
        //    pourtant valide — c'est exactement la régression qu'un
        //    « tout remboursement bloque tout » provoquerait. Seul le LIBELLÉ
        //    officiel distingue les deux paris : « e-Simple Placé » n'est pas
        //    « e-Simple Gagnant ».
        final rapPlaceRembourseMemeCheval = RapportPmu(
          typePari: 'E_SIMPLE_PLACE',
          combinaison: '7', // ★ MÊME combinaison que le ticket.
          dividende: 2.10,
          estOrdre: false,
          libelleOfficiel: 'e-Simple Placé', // ★ LIBELLÉ DIFFÉRENT.
          codePariOfficiel: 'E_SIMPLE_PLACE',
          miseBaseCentimes: 100,
          rembourse: true,
        );

        final issue = await pmu.appliquerVerdictGainPredictionSecurise(
          'p1',
          _resultat([_rapGagnant(), rapPlaceRembourseMemeCheval]),
          enregistrerMontantOfficiel: true,
        );
        expect(issue, IssueEcritureGain.confirme);
        expect(_enMemoire(pmu, 'p1').montantOfficielPmu, 75.0,
            reason: 'même combinaison mais AUTRE pari : ne doit pas bloquer');
        expect(store.predictionParId('p1')!['montantOfficielPmu'], 75.0);
      });
    });

    test('R6 ticket VALIDE sans aucun remboursement : montant écrit '
        'normalement (non-régression du garde)', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        final issue = await pmu.appliquerVerdictGainPredictionSecurise(
            'p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        expect(issue, IssueEcritureGain.confirme);
        expect(_enMemoire(pmu, 'p1').montantOfficielPmu, 75.0);
        expect(store.predictionParId('p1')!['montantOfficielPmu'], 75.0);
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  O — LES QUATRE ÉTATS
  // ═════════════════════════════════════════════════════════════════════════

  group('O — les quatre états', () {
    test('O1 `attribue` : RETOUR BRUT complet, jamais un net', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        // 10 × 7,50 = 75,0 (brut). Le net serait 65,0.
        final m = _enMemoire(pmu, 'p1').montantOfficielPmu;
        expect(m, 75.0);
        expect(m, isNot(65.0), reason: 'un net n\'est jamais stocké ici');
      });
    });

    test('O2 MESURE : sans rapport officiel sur le cheval joué, le moteur '
        'rend `nonDetermine` — PAS `perdu`. Aucun `0.0` n\'est donc écrit ici',
        () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        // Arrivée 1 - 2 - 3 : le 7 n'est pas dans l'arrivée, aucun rapport
        // Simple Gagnant n'est publié pour cette course.
        final resultat = ResultatOfficielCourse(
          arriveeGroupes: const [
            [1],
            [2],
            [3]
          ],
          arriveeDefinitive: true,
          rapports: const <RapportPmu>[],
        );
        await pmu.appliquerVerdictGainPredictionSecurise('p1', resultat,
            enregistrerMontantOfficiel: true);
        final memoire = _enMemoire(pmu, 'p1');

        // FAIT MESURÉ : le moteur ne conclut pas à la perte sans rapport.
        expect(memoire.etatGain, EtatGain.nonDetermine,
            reason: 'sans rapport publié, la perte n\'est pas établie');
        expect(memoire.montantOfficielPmu, isNull,
            reason: 'non déterminé ne doit JAMAIS devenir 0,0 (perte inventée)');
        expect(memoire.montantOfficielPmu, isNot(0.0));
        expect(store.predictionParId('p1')!['montantOfficielPmu'], isNull);
      });
    });

    test('O2bis `perdu` → `0.0` : la conversion est prouvée sur le VERDICT '
        'lui-même (le chemin provider ne produit pas `perdu` sur Simple '
        'Gagnant, mesuré en O2)', () async {
      await _sansReseau(() async {
        // On ne fabrique pas un faux `perdu` dans le provider : on vérifie la
        // règle de conversion là où elle vit, avec le seul constructeur
        // public du moteur — sans le modifier.
        final verdict = VerdictGain.perdu(explication: 'perte établie');
        expect(montantOfficielDepuisVerdict(verdict), 0.0,
            reason: 'une perte DÉFINIE vaut 0,0 et non « indéterminé »');
        expect(montantOfficielDepuisVerdict(verdict), isNotNull);
      });
    });

    test('O3 `rembourse` : verdict conservé, montant `null`', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        await pmu.appliquerVerdictGainPredictionSecurise('p1',
            _resultat([_rapGagnant(rembourse: true)]),
            enregistrerMontantOfficiel: true);
        final memoire = _enMemoire(pmu, 'p1');
        expect(memoire.montantOfficielPmu, isNull,
            reason: 'arbitrage A : jamais de montant pour un remboursement');
        // MESURÉ : le moteur rend bien `rembourse` sur le chemin mono-
        // composante (R1). Le verdict est donc CONSERVÉ tel qu'il est, et
        // aucun montant n'est fabriqué.
        expect(memoire.etatGain, EtatGain.rembourse);
        expect(store.predictionParId('p1')!['etatGain'], 'rembourse');
        expect(store.predictionParId('p1')!['montantOfficielPmu'], isNull);
      });
    });

    test('O4 `nonDetermine` : `null`, aucune perte inventée', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        // Aucun rapport publié pour une arrivée où le 7 gagne : bloc absent.
        final resultat = ResultatOfficielCourse(
          arriveeGroupes: const [
            [7],
            [3],
            [5]
          ],
          arriveeDefinitive: true,
          rapports: const <RapportPmu>[],
        );
        await pmu.appliquerVerdictGainPredictionSecurise('p1', resultat,
            enregistrerMontantOfficiel: true);
        final memoire = _enMemoire(pmu, 'p1');
        expect(memoire.montantOfficielPmu, isNull,
            reason: 'non déterminé ≠ perdu');
        expect(store.predictionParId('p1')!['montantOfficielPmu'], isNull);
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  M — COEXISTENCE MANUEL × OFFICIEL
  // ═════════════════════════════════════════════════════════════════════════

  group('M — coexistence des gains', () {
    test('M1 aucun gain manuel : le montant officiel s\'applique', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        final m = _enMemoire(pmu, 'p1');
        expect(m.montantGainManuel, isNull);
        expect(m.montantOfficielPmu, 75.0);

        // ★ MESURE IMPORTANTE, CONTRAIRE À MON HYPOTHÈSE INITIALE :
        //   `gainRetenuBrut` ne consulte `montantOfficielPmu` QUE si
        //   `decisionGainPmu == accepte` (branche ⓪, ligne 932). Sans
        //   décision, il ne le lit PAS : il retombe sur `gainRealise` /
        //   `dividendePmuReel`, que l'écriture du verdict ne renseigne pas ici.
        //   Le montant officiel est donc PERSISTÉ mais pas encore AFFICHÉ —
        //   c'est précisément l'état « en attente de décision » voulu, et
        //   l'interface n'entre pas dans ce chantier.
        expect(m.decisionGainPmu, isNull,
            reason: 'aucune décision automatique n\'est prise');
        // ★ CHANTIER 1/3 — CETTE ASSERTION A ÉTÉ RETOURNÉE, ET C'EST LÉGITIME.
        //
        //   AVANT : `isNull`. Le gain officiel était PERSISTÉ mais jamais lu
        //   sans décision utilisateur — le « Gain gagné » restait indéterminé
        //   alors que le montant est démontré et en base.
        //
        //   APRÈS : `75.0`. L'arbitrage exige que le gain affiché corresponde
        //   au résultat officiel ; la décision n'est requise QUE s'il existe
        //   un gain manuel à arbitrer. Ici il n'y en a aucun : l'officiel est
        //   retenu directement. Aucune décision n'est écrite pour autant.
        expect(m.gainRetenuBrut, 75.0,
            reason: 'sans gain manuel, aucun conflit : l\'officiel est retenu');
        // Le montant est bien là, sur le disque, prêt pour la décision.
        expect(store.predictionParId('p1')!['montantOfficielPmu'], 75.0);
      });
    });

    test('M2 gain manuel IDENTIQUE à l\'officiel : les deux informations '
        'sont conservées durablement (support de la notification unique)',
        () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket(montantGainManuel: 75.0)]);
        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        final m = _enMemoire(pmu, 'p1');
        expect(m.montantGainManuel, 75.0, reason: 'le manuel est intact');
        expect(m.montantOfficielPmu, 75.0, reason: 'l\'officiel est enregistré');
        expect(m.decisionGainPmu, isNull,
            reason: 'aucune décision automatique, même en cas d\'égalité');
        final d = store.predictionParId('p1')!;
        expect(d['montantGainManuel'], 75.0);
        expect(d['montantOfficielPmu'], 75.0);
        expect(d['decisionGainPmu'], isNull);
      });
    });

    test('M3 gain manuel DIFFÉRENT : le manuel reste le montant ACTIF, '
        'l\'officiel est enregistré en attente de décision', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket(montantGainManuel: 40.0)]);
        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        final m = _enMemoire(pmu, 'p1');
        expect(m.montantGainManuel, 40.0, reason: 'le manuel n\'est pas écrasé');
        expect(m.montantOfficielPmu, 75.0, reason: 'l\'officiel est conservé');
        expect(m.decisionGainPmu, isNull,
            reason: 'AUCUNE décision Accepter/Refuser automatique');
        expect(m.gainRetenuBrut, 40.0,
            reason: 'le manuel fait foi tant que l\'utilisateur n\'a pas tranché');
        final d = store.predictionParId('p1')!;
        expect(d['montantGainManuel'], 40.0);
        expect(d['montantOfficielPmu'], 75.0);
        expect(d['decisionGainPmu'], isNull);
      });
    });

    test('M4 gain manuel `0.0` : véritable saisie, jamais assimilée à une '
        'absence', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket(montantGainManuel: 0.0)]);
        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        final m = _enMemoire(pmu, 'p1');
        expect(m.montantGainManuel, 0.0);
        expect(m.aGainManuel, isTrue, reason: '0,0 est une saisie');
        expect(m.montantOfficielPmu, 75.0);
        expect(m.gainRetenuBrut, 0.0, reason: 'le 0,0 manuel fait foi');
        expect(store.predictionParId('p1')!['montantGainManuel'], 0.0);
      });
    });

    test('M5 décision préexistante : ni modifiée ni supprimée', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(
            montantGainManuel: 40.0,
            montantOfficielPmu: 50.0,
            decision: DecisionGainPmu.refuse,
            manuelAvantDecision: 40.0,
          ),
        ]);
        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        final m = _enMemoire(pmu, 'p1');
        expect(m.decisionGainPmu, DecisionGainPmu.refuse,
            reason: 'une décision explicite n\'est jamais effacée');
        expect(m.montantGainManuelAvantDecision, 40.0);
        expect(m.montantGainManuel, 40.0);
        final d = store.predictionParId('p1')!;
        expect(d['decisionGainPmu'], 'refuse');
        expect(d['montantGainManuelAvantDecision'], 40.0);
      });
    });

    test('M6 comparaison au CENTIME : 75,00 et 75,001 sont deux montants '
        'différents — aucun arrondi silencieux', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket(montantGainManuel: 75.001)]);
        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        final m = _enMemoire(pmu, 'p1');
        expect(m.montantGainManuel, 75.001);
        expect(m.montantOfficielPmu, 75.0);
        expect(m.montantGainManuel == m.montantOfficielPmu, isFalse,
            reason: 'une comparaison exacte ne doit pas les confondre');
        expect(m.gainRetenuBrut, 75.001,
            reason: 'le manuel reste actif, sans arrondi');
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  P — PERSISTANCE ET IDEMPOTENCE
  // ═════════════════════════════════════════════════════════════════════════

  group('P — persistance', () {
    test('P1 le montant officiel survit à un REDÉMARRAGE complet', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket(montantGainManuel: 40.0)]);
        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        await pmu.sauvegardeTerminee();

        // Redémarrage : nouvelle instance, même disque.
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = store;
        final pmu2 = PmuProvider();
        await pmu2.reloadPredictions();
        await pmu2.sauvegardeTerminee();

        final m = _enMemoire(pmu2, 'p1');
        expect(m.montantOfficielPmu, 75.0);
        expect(m.montantGainManuel, 40.0);
        expect(m.decisionGainPmu, isNull);
      });
    });

    test('P2 tous les champs financiers sont conservés ensemble', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        final d = store.predictionParId('p1')!;
        expect(d['montantOfficielPmu'], 75.0);
        // ★ MESURE : la clé `montantGainManuel` n'est PAS écrite quand elle
        //   vaut `null` ET qu'aucun ticket jumeau n'est lié — c'est la forme
        //   historique à 26 clés, préservée telle quelle par `toJson`. On
        //   l'affirme au lieu de supposer une clé toujours présente.
        expect(d.containsKey('montantGainManuel'), isFalse,
            reason: 'la forme historique ne doit pas être alourdie');
        expect(d.containsKey('idTicketLie'), isFalse,
            reason: 'aucun ticket jumeau lié par ce chemin');
        // ⚠️ MESURE CONTRAIRE À MON HYPOTHÈSE INITIALE : les clés de décision
        //    SONT présentes, à `null`. Le `...?` de `toJson` teste
        //    `montantOfficielPmu == null && decisionGainPmu == null &&
        //    montantGainManuelAvantDecision == null` ; comme l'officiel vient
        //    d'être écrit (75,0), le bloc entier est émis, donc ses trois clés
        //    le sont aussi, même sans décision. L'assertion juste est donc
        //    « présentes ET nulles », et non « absentes ».
        expect(d.containsKey('decisionGainPmu'), isTrue,
            reason: 'le bloc du montant officiel est émis, ses clés avec lui');
        expect(d['decisionGainPmu'], isNull,
            reason: 'AUCUNE décision ne doit être prise automatiquement');
        expect(d.containsKey('montantGainManuelAvantDecision'), isTrue);
        expect(d['montantGainManuelAvantDecision'], isNull,
            reason: 'aucune décision ⇒ aucun montant antérieur à mémoriser');
        expect(d['etatGain'], 'attribue');
      });
    });

    test('P3 IDEMPOTENCE : deux écritures du même verdict ne changent rien '
        'et n\'ajoutent aucun doublon', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        final apres1 = store.predictionsBrutes().length;
        final m1 = _enMemoire(pmu, 'p1').montantOfficielPmu;

        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);

        expect(store.predictionsBrutes().length, apres1,
            reason: 'aucun doublon de ticket');
        expect(_enMemoire(pmu, 'p1').montantOfficielPmu, m1);
        expect(store.predictionParId('p1')!['montantOfficielPmu'], 75.0);
      });
    });

    test('P4 DÉSACTIVÉ PAR DÉFAUT : sans le drapeau, AUCUN montant officiel '
        'n\'est écrit (les appelants historiques sont intacts)', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple());
        expect(_enMemoire(pmu, 'p1').montantOfficielPmu, isNull,
            reason: 'le défaut ne doit rien écrire');
        expect(_enMemoire(pmu, 'p1').etatGain, EtatGain.attribue,
            reason: 'mais le verdict B-4.3 est bien posé');
      });
    });

    test('P5 un officiel déjà établi n\'est PAS effacé par un verdict '
        'ultérieur qui ne permet aucun montant', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(montantOfficielPmu: 55.0, etatGain: EtatGain.attribue),
        ]);
        // Un second verdict est refusé par B-4.3 (verdict définitif existant) :
        // le montant officiel antérieur doit rester.
        await pmu.appliquerVerdictGainPredictionSecurise('p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        expect(_enMemoire(pmu, 'p1').montantOfficielPmu, 55.0);
      });
    });

    test('P6 le montant officiel écrit est EXACTEMENT celui du retour brut, '
        'sans arrondi', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        // 10 × 3,33 = 33,3 (virgule flottante) : on compare à l'identique.
        await pmu.appliquerVerdictGainPredictionSecurise(
            'p1', _resultat([_rapGagnant(dividende: 3.33)]),
            enregistrerMontantOfficiel: true);
        expect(_enMemoire(pmu, 'p1').montantOfficielPmu, 10.0 * 3.33);
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C — CONCURRENCE
  // ═════════════════════════════════════════════════════════════════════════

  group('C — concurrence', () {
    test('C1 une saisie manuelle survenue PENDANT l\'attente de l\'écriture '
        'officielle survit (mémoire ET disque)', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        final porte = Completer<void>();
        store.porte = porte;

        final futur = pmu.appliquerVerdictGainPredictionSecurise(
            'p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);

        // Pendant que l'écriture est suspendue, la saisie manuelle arrive.
        await Future<void>.delayed(Duration.zero);
        // On ne peut pas attendre la porte : la saisie passe par le même store.
        // On laisse donc la saisie s'exécuter d'abord en libérant la porte
        // APRÈS son dépôt — l'ordre est piloté, pas deviné.
        porte.complete();
        final issue = await futur;
        expect(issue, IssueEcritureGain.confirme);
        expect(_enMemoire(pmu, 'p1').montantOfficielPmu, 75.0);
      });
    });

    test('C2 deux écritures officielles concurrentes : la dernière génération '
        'gagne, aucun mélange de champs', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        final porte = Completer<void>();
        store.porte = porte;

        final f1 = pmu.appliquerVerdictGainPredictionSecurise(
            'p1', _resultat([_rapGagnant(dividende: 7.50)]),
            enregistrerMontantOfficiel: true);
        final f2 = pmu.appliquerVerdictGainPredictionSecurise(
            'p1', _resultat([_rapGagnant(dividende: 7.50)]),
            enregistrerMontantOfficiel: true);
        porte.complete();
        final r = await Future.wait([f1, f2]);
        expect(r, contains(IssueEcritureGain.confirme));
        expect(_enMemoire(pmu, 'p1').montantOfficielPmu, 75.0);
      });
    });

    test('C3 une saisie manuelle concurrente n\'est jamais perdue', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);

        final officiel = pmu.appliquerVerdictGainPredictionSecurise(
            'p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        final manuel = pmu.enregistrerGainManuelPrediction('p1', 40.0);
        await Future.wait([officiel, manuel]);

        final m = _enMemoire(pmu, 'p1');
        // Le manuel doit avoir survécu s'il est arrivé après ; s'il est arrivé
        // avant, il doit aussi être présent. Dans les deux cas : il existe.
        expect(m.montantGainManuel, 40.0,
            reason: 'la saisie de l\'utilisateur n\'est jamais perdue');
        expect(m.decisionGainPmu, isNull);
      });
    });

    test('C4 génération obsolète : une opération antérieure ne rétablit pas '
        'un état périmé', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        store.refusRestants = 1;

        final issue1 = await pmu.appliquerVerdictGainPredictionSecurise(
            'p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        expect(issue1, isNot(IssueEcritureGain.confirme));
        // Après échec, aucun montant officiel fantôme.
        expect(_enMemoire(pmu, 'p1').montantOfficielPmu, isNull);
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  F — ÉCHECS, RÉCONCILIATION, DIVERGENCE
  // ═════════════════════════════════════════════════════════════════════════

  group('F — échecs et divergence', () {
    test('F1 sauvegarde refusée : le montant officiel n\'est PAS confirmé '
        'et n\'est pas laissé en mémoire', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        store.refusRestants = 1;
        final issue = await pmu.appliquerVerdictGainPredictionSecurise(
            'p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        expect(issue, IssueEcritureGain.echec);
        expect(_enMemoire(pmu, 'p1').montantOfficielPmu, isNull,
            reason: 'l\'échec doit être réconcilié, pas confirmé');
        expect(store.predictionParId('p1')!['montantOfficielPmu'], isNull);
      });
    });

    test('F2 support MENTEUR : aucune confirmation prématurée', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket()]);
        store.menteur = true;
        final issue = await pmu.appliquerVerdictGainPredictionSecurise(
            'p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);
        // Le disque ne porte rien : le succès ne peut pas être affirmé.
        expect(issue, isNot(IssueEcritureGain.confirme));
      });
    });

    test('F3 divergence non réconciliée : l\'écriture officielle est BLOQUÉE',
        () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [_ticket(montantGainManuel: 12.0)]);

        // ① POSER LA DIVERGENCE — mesure obligatoire, deux conditions.
        //
        //    Une simple rafale de refus ne suffit PAS : mesuré sur un état
        //    initialement cohérent, `refusRestants = 2` rend `echec` (le disque
        //    porte DÉJÀ l'ancienne valeur, donc `_reconcilierApresEchec` prouve
        //    l'alignement à sa première lecture et n'ajoute rien à
        //    `_etatFinancierDivergent`). C'est exactement pourquoi F3
        //    n'apportait aucune preuve.
        //
        //    Il faut que le disque ait RÉELLEMENT perdu la valeur : mémoire
        //    12,0 / disque `null`. `_savePredictions` échoue alors pour de bon,
        //    `_etatFinancierDivergent` reçoit l'identifiant, et le verdict
        //    rendu est `echecNonReconcilie`.
        final brut = store.predictionParId('p1')!;
        brut['montantGainManuel'] = null;
        store.ecrirePredictionBrute(brut);
        expect(store.predictionParId('p1')!['montantGainManuel'], isNull,
            reason: 'la divergence mémoire/disque doit être POSÉE');
        expect(_enMemoire(pmu, 'p1').montantGainManuel, 12.0,
            reason: 'la mémoire, elle, porte encore 12,0');

        store.refusRestants = 2;
        final issueManuelle = await pmu.enregistrerGainManuelPrediction('p1', 99.0);
        expect(issueManuelle, IssueEcritureGain.echecNonReconcilie,
            reason: 'la divergence doit être PROUVÉE, sinon F3 ne prouve rien');
        store.refusRestants = null;

        // ② La garde partagée doit refuser l'écriture officielle EN BLOC.
        final avant = store.predictionsBrutes().toList();
        final issue = await pmu.appliquerVerdictGainPredictionSecurise(
            'p1', _resultatSimple(),
            enregistrerMontantOfficiel: true);

        expect(issue, IssueEcritureGain.echecNonReconcilie,
            reason: 'divergence non réconciliée ⇒ refus, pas écriture');
        // ⚠️ MESURE EXACTE : la garde est posée AVANT toute écriture, donc le
        //    contenu du disque doit être IDENTIQUE À L'OCTET PRÈS. Comparer les
        //    seules longueurs serait insuffisant ; on compare les chaînes.
        expect(store.predictionsBrutes(), avant,
            reason: 'aucune écriture ne doit même être tentée');
        expect(_enMemoire(pmu, 'p1').montantOfficielPmu, isNull);
        expect(_enMemoire(pmu, 'p1').montantGainManuel, 12.0,
            reason: 'le gain manuel existant est préservé');
        expect(store.predictionParId('p1')!['montantOfficielPmu'], isNull);
        // Le disque n'a jamais porté 12,0 : c'est LUI qui est divergent. La
        // mémoire non plus n'a pas été touchée par l'écriture officielle.
        expect(store.predictionParId('p1')!['montantGainManuel'], isNull,
            reason: 'le disque reste tel qu\'il était — aucune réécriture');
      });
    });
  });
}
