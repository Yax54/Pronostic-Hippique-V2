// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 2/3 — FONCTIONNEL 2/4 : DÉCISIONS RÉELLES SUR `PmuProvider`
// ═══════════════════════════════════════════════════════════════════════════
//
//  Ce fichier exerce les TRANSITIONS FINANCIÈRES RÉELLES
//  (`accepterGainOfficiel` / `refuserGainOfficiel`) sur l'instance de
//  production de `PmuProvider`, avec un `SharedPreferences` simulé. Il prouve :
//    • l'effet financier réel (gain retenu, décision persistée) ;
//    • la persistance effective sur le support ;
//    • le refus d'une décision sans objet ;
//    • qu'une erreur de sauvegarde n'est JAMAIS annoncée comme enregistrée ;
//    • la survie au REDÉMARRAGE (relecture par une seconde instance).
//
//  ⚠️ Aucune assertion métier n'est affaiblie : les `expect` portent sur des
//     montants et des états, jamais sur des « pas d'exception ».
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pronostic_hippique/models/decision_gain_pmu.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';

/// Clé de persistance réelle des tickets durables.
const _cle = 'user_predictions_v2';

/// Construit un ticket minimal mais COMPLET, tel que le provider le persiste.
UserPrediction _ticket({
  required String id,
  double? gainManuel,
  double? gainOfficiel,
  double? remboursement,
  DecisionGainPmu? decision,
  double mise = 20.0,
  String dateStr = '23032026',
  int numReunion = 1,
  int numCourse = 3,
}) =>
    UserPrediction(
      id: id,
      dateStr: dateStr,
      numReunion: numReunion,
      numCourse: numCourse,
      nomCourse: 'Prix de test',
      hippodrome: 'Vincennes',
      numeroCheval: 5,
      nomCheval: 'Cheval Test',
      cote: 3.5,
      typePari: 'Simple Gagnant',
      createdAt: DateTime(2026, 3, 23, 14, 30),
      montantMise: mise,
      montantGainManuel: gainManuel,
      montantOfficielPmu: gainOfficiel,
      remboursementPmu: remboursement,
      decisionGainPmu: decision,
    );

/// Amorce le support persistant avec [tickets] puis construit le provider.
///
/// ⚠️ `UserPrediction.toJson` est utilisé TEL QUEL : on n'écrit pas un JSON à
///    la main, qui pourrait diverger du format réellement lu.
Future<PmuProvider> _providerAvec(List<UserPrediction> tickets) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    _cle: tickets.map((t) => jsonEncode(t.toJson())).toList(),
  });
  return PmuProvider();
}

/// Relit le ticket [id] SUR LE SUPPORT (pas en mémoire).
Future<UserPrediction?> _depuisDisque(String id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  for (final s in prefs.getStringList(_cle) ?? const <String>[]) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    if (m['id'] == id) return UserPrediction.fromJson(m);
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F2/1 — ACCEPTATION : le gain officiel devient le gain retenu', () {
    test('F2/1.1 accepter remplace le manuel par l\'officiel, sur le DISQUE', () async {
      final t = _ticket(id: 'a1', gainManuel: 20.0, gainOfficiel: 75.0);
      final p = await _providerAvec([t]);
      await p.reloadPredictions();

      // Avant décision : le manuel est retenu (CAS C).
      expect(p.predictions.first.gainRetenuBrut, 20.0);

      final issue = await p.accepterGainOfficiel('a1');
      expect(issue, IssueEcritureGain.confirme);

      // Après décision : l'officiel est retenu.
      expect(p.predictions.first.gainRetenuBrut, 75.0);
      expect(p.predictions.first.decisionGainPmu, DecisionGainPmu.accepte);

      // Et le DISQUE porte la décision, pas seulement la mémoire.
      final disque = await _depuisDisque('a1');
      expect(disque, isNotNull);
      expect(disque!.decisionGainPmu, DecisionGainPmu.accepte);
      // Le montant manuel est CONSERVÉ : c'est la traçabilité.
      expect(disque.montantGainManuel, 20.0);
      // La donnée officielle est conservée.
      expect(disque.montantOfficielPmu, 75.0);
      // La trace d'avant-décision est mémorisée.
      expect(disque.montantGainManuelAvantDecision, 20.0);
    });

    test('F2/1.2 accepter un officiel de 0 € donne bien 0 € retenu (perte établie)',
        () async {
      final t = _ticket(id: 'a2', gainManuel: 15.0, gainOfficiel: 0.0);
      final p = await _providerAvec([t]);
      await p.reloadPredictions();

      expect(await p.accepterGainOfficiel('a2'), IssueEcritureGain.confirme);
      // 0 € est un montant RETENU, distinct de « non déterminé » (null).
      expect(p.predictions.first.gainRetenuBrut, 0.0);
    });

    test('F2/1.3 accepter deux fois le même sens est idempotent et confirmé',
        () async {
      final t = _ticket(id: 'a3', gainManuel: 20.0, gainOfficiel: 75.0);
      final p = await _providerAvec([t]);
      await p.reloadPredictions();

      expect(await p.accepterGainOfficiel('a3'), IssueEcritureGain.confirme);
      // Second appel : rien à réécrire, mais la confirmation doit rester vraie
      // (le disque porte bien `accepte`).
      expect(await p.accepterGainOfficiel('a3'), IssueEcritureGain.confirme);
      expect(p.predictions.first.decisionGainPmu, DecisionGainPmu.accepte);
    });
  });

  group('F2/2 — REFUS : le manuel reste retenu, l\'officiel reste en trace', () {
    test('F2/2.1 refuser conserve le manuel et garde le montant officiel', () async {
      final t = _ticket(id: 'b1', gainManuel: 20.0, gainOfficiel: 75.0);
      final p = await _providerAvec([t]);
      await p.reloadPredictions();

      expect(await p.refuserGainOfficiel('b1'), IssueEcritureGain.confirme);
      expect(p.predictions.first.gainRetenuBrut, 20.0);

      final disque = await _depuisDisque('b1');
      expect(disque!.decisionGainPmu, DecisionGainPmu.refuse);
      // ⚠️ Le résultat officiel N'EST PAS EFFACÉ : c'est la trace.
      expect(disque.montantOfficielPmu, 75.0);
      expect(disque.montantGainManuel, 20.0);
    });

    test('F2/2.2 un refus ne peut pas être confondu avec « aucune décision »',
        () async {
      final t = _ticket(id: 'b2', gainManuel: 20.0, gainOfficiel: 75.0);
      final p = await _providerAvec([t]);
      await p.reloadPredictions();

      await p.refuserGainOfficiel('b2');
      // `refuse` n'est PAS `null` : la décision a bien été enregistrée.
      expect(p.predictions.first.decisionGainPmu, isNotNull);
      expect(p.predictions.first.decisionGainPmu, DecisionGainPmu.refuse);
    });

    test('F2/2.3 accepter puis refuser : la dernière décision fait foi', () async {
      final t = _ticket(id: 'b3', gainManuel: 20.0, gainOfficiel: 75.0);
      final p = await _providerAvec([t]);
      await p.reloadPredictions();

      await p.accepterGainOfficiel('b3');
      expect(p.predictions.first.gainRetenuBrut, 75.0);
      await p.refuserGainOfficiel('b3');
      // Le refus reprend le manuel : l'effet financier est réel, pas cosmétique.
      expect(p.predictions.first.gainRetenuBrut, 20.0);
      final disque = await _depuisDisque('b3');
      expect(disque!.decisionGainPmu, DecisionGainPmu.refuse);
      // La trace d'avant-décision n'est pas écrasée par la seconde décision.
      expect(disque.montantGainManuelAvantDecision, 20.0);
    });
  });

  group('F2/3 — DÉCISION SANS OBJET : rien n\'est écrit', () {
    test('F2/3.1 accepter sans montant officiel ⇒ echec, aucune décision', () async {
      final t = _ticket(id: 'c1', gainManuel: 20.0);
      final p = await _providerAvec([t]);
      await p.reloadPredictions();

      expect(await p.accepterGainOfficiel('c1'), IssueEcritureGain.echec);
      expect(p.predictions.first.decisionGainPmu, isNull);
    });

    test('F2/3.2 décider un ticket inexistant ⇒ echec', () async {
      final p = await _providerAvec([_ticket(id: 'c2', gainOfficiel: 10.0)]);
      await p.reloadPredictions();
      expect(await p.accepterGainOfficiel('inconnu'), IssueEcritureGain.echec);
    });
  });

  group('F2/4 — REDÉMARRAGE : la décision survit', () {
    test('F2/4.1 une acceptation persiste après une NOUVELLE instance', () async {
      final t = _ticket(id: 'd1', gainManuel: 20.0, gainOfficiel: 75.0);
      final p1 = await _providerAvec([t]);
      await p1.reloadPredictions();
      expect(await p1.accepterGainOfficiel('d1'), IssueEcritureGain.confirme);

      // Seconde instance : elle relit le MÊME support simulé.
      final p2 = PmuProvider();
      await p2.reloadPredictions();
      final relu = p2.predictions.firstWhere((x) => x.id == 'd1');
      expect(relu.decisionGainPmu, DecisionGainPmu.accepte);
      expect(relu.gainRetenuBrut, 75.0);
    });

    test('F2/4.2 une décision EN ATTENTE survit au redémarrage', () async {
      final t = _ticket(id: 'd2', gainManuel: 20.0, gainOfficiel: 75.0);
      final p1 = await _providerAvec([t]);
      await p1.reloadPredictions();

      // Aucune décision prise : l'état doit rester « en attente ».
      final p2 = PmuProvider();
      await p2.reloadPredictions();
      final relu = p2.predictions.firstWhere((x) => x.id == 'd2');
      expect(relu.decisionGainPmu, isNull);
      expect(relu.montantOfficielPmu, 75.0);
      expect(relu.montantGainManuel, 20.0);
    });
  });

  group('F2/5 — ÉCHEC DE SAUVEGARDE : jamais annoncé comme enregistré', () {
    test('F2/5.1 un support qui REFUSE l\'écriture ne rend pas `confirme`',
        () async {
      final t = _ticket(id: 'e1', gainManuel: 20.0, gainOfficiel: 75.0);
      final p = await _providerAvec([t]);
      await p.reloadPredictions();
      expect(p.predictions.length, 1, reason: 'le ticket doit être chargé');

      // ⚠️ Le support simulé de plateforme ne sait pas refuser une écriture :
      //    on arme donc le point d'injection, qui imite exactement son refus.
      p.refuserProchaineEcriturePourTest();

      final issue = await p.accepterGainOfficiel('e1');
      expect(issue, isNot(IssueEcritureGain.confirme),
          reason: 'Une erreur de sauvegarde ne doit jamais être présentée '
              'comme une décision définitivement enregistrée.');

      // Le disque ne doit pas porter la décision.
      final disque = await _depuisDisque('e1');
      expect(disque!.decisionGainPmu, isNull);
    });

    test('F2/5.2 après un échec, une reprise RÉUSSIE confirme la décision',
        () async {
      final t = _ticket(id: 'e2', gainManuel: 20.0, gainOfficiel: 75.0);
      final p = await _providerAvec([t]);
      await p.reloadPredictions();

      p.refuserProchaineEcriturePourTest();
      expect(await p.accepterGainOfficiel('e2'), isNot(IssueEcritureGain.confirme));

      // Le support redevient disponible : la décision doit pouvoir aboutir.
      // ⚠️ La mémoire a été remise dans son état d'avant : la reprise n'est
      //    donc pas un « coup de chance », elle réécrit réellement.
      final reprise = await p.accepterGainOfficiel('e2');
      expect(reprise, IssueEcritureGain.confirme);
      final disque = await _depuisDisque('e2');
      expect(disque!.decisionGainPmu, DecisionGainPmu.accepte);
    });
  });
}
