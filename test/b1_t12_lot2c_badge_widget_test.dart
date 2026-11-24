// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / LOT 2-C — BADGE « GAIN GAGNÉ » SUR L'ÉCRAN RÉEL (partie 4/4)
//
//  ⚠️ FICHIER DE TEST UNIQUEMENT. Aucune production n'est modifiée ici.
//
//  PÉRIMÈTRE — les six comportements exigés, mesurés sur `MesPariScreen`
//  RÉELLEMENT construit (pas un widget isolé, pas une fonction recopiée) :
//    W1 gain manuel durable, AUCUN verdict  ⇒ badge VISIBLE ;
//    W2 gain manuel de 0,0 €                ⇒ badge visible, « 0 € » ;
//    W3 aucun gain, aucun verdict           ⇒ AUCUN badge ;
//    W4 verdict officiel présent            ⇒ AUCUN doublon (exactement 1) ;
//    W5 décision officielle en attente      ⇒ le montant DÉCLARÉ est conservé ;
//    W6 mise à jour du montant              ⇒ le badge se rafraîchit.
//
//  MÉTHODE : on pilote l'écran par ses providers publics
//  (`PmuProvider`, `NavigationNotifier`, `DataRefreshService`) et par le
//  support `SharedPreferences` réel (faux store), jamais par un état interne.
//  Les occurrences sont COMPTÉES : « au moins un » ne prouverait pas
//  l'absence de doublon.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/main.dart' show NavigationNotifier;
import 'package:pronostic_hippique/models/decision_gain_pmu.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/screens/mes_paris_screen.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/gain_durable_vue.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart' show EtatGain;

/// ───────────────────────────────────────────────────────────────────────────
///  DATES RELATIVES — correction d'une CORRUPTION TEMPORELLE des fixtures.
///
///  DÉFAUT MESURÉ : ces fixtures portaient des dates FIGÉES
///  (`DateTime(2026, 11, 23, …)`). Or `AlertService._load()`
///  (alert_service.dart:696) purge toute course suivie dont
///  `now.difference(heureDepart).inHours > 24`. Le 24/11/2026 à 15:59, l'écart
///  valait ~26 h : la course était purgée AU CHARGEMENT, `_trackedCourses`
///  restait vide, et `enregistrerGainManuelDetaille` rendait
///  `ticketIntrouvable` au lieu de `complet`. Ce n'était donc PAS un défaut de
///  production : c'était le test qui datait d'hier et butait sur sa propre
///  règle de purge.
///
///  ⚠️ LES ASSERTIONS MÉTIER NE SONT PAS TOUCHÉES. Seules les dates changent,
///     et elles conservent l'ÉCART métier de 3 h 30 entre la création du
///     pronostic et le départ de la course.
/// ───────────────────────────────────────────────────────────────────────────
DateTime _jourRelatif(int h, int min) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, min);
}

/// Création du pronostic : même jour, 10 h 00.
DateTime get _creationRelative => _jourRelatif(10, 0);

/// Départ de la course : même jour, 13 h 30 (écart métier de 3 h 30 conservé).
DateTime get _departRelatif => _jourRelatif(13, 30);

const String kCle = 'R1C3_23112026_1000';

/// Faux support : accepte tout. Le refus n'est pas le sujet de ce fichier.
class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _d = <String, Object>{};

  @override
  Future<bool> clear() async => true;
  @override
  Future<bool> clearWithParameters(ClearParameters p) async {
    _d.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));
  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters p) async {
    final r = Map<String, Object>.from(_d);
    r.removeWhere((k, _) => !k.startsWith(p.filter.prefix));
    return r;
  }

  @override
  Future<bool> remove(String k) async {
    _d.remove(k);
    return true;
  }

  @override
  Future<bool> setValue(String t, String k, Object v) async {
    _d[k] = v;
    return true;
  }
}

UserPrediction _pred({
  double? montantGainManuel,
  double? montantOfficielPmu,
  DecisionGainPmu? decision,
  EtatGain? etatGain,
}) {
  final base = UserPrediction(
    id: 'p1',
    dateStr: '23112026',
    numReunion: 1,
    numCourse: 3,
    nomCourse: 'Prix de Test',
    hippodrome: 'Vincennes',
    numeroCheval: 7,
    nomCheval: 'Cheval Test',
    cote: 4.5,
    typePari: 'Simple Gagnant',
    createdAt: _creationRelative,
    montantGainManuel: montantGainManuel,
    idTicketLie: kCle,
    montantOfficielPmu: montantOfficielPmu,
    decisionGainPmu: decision,
  );
  if (etatGain == null) return base;
  return UserPrediction.fromJson(base.toJson()..['etatGain'] = etatGain.name);
}

TrackedCourse _tc({double? montantGainManuel, bool historique = false}) =>
    TrackedCourse(
      numReunion: 1,
      numCourse: 3,
      nomCourse: 'Prix de Test',
      hippodrome: 'Vincennes',
      heureDepart: _departRelatif,
      storageKey: kCle,
      montantGainManuel: montantGainManuel,
      idTicketLie: 'p1',
      typePari: 'Simple Gagnant',
      numerosJoues: const <int>[7],
      miseEngagee: 10.0,
      cote: 4.5,
      // ⚠️ Un ticket HISTORIQUE porte un verdict (`isGagne`) ET un
      //    `messageResultat`. Sans le message, `_titreResultat` reste nul et
      //    le bandeau historique n'est PAS construit : le test ne mesurerait
      //    alors pas le doublon. Les deux champs sont donc posés ENSEMBLE.
      isGagne: historique ? true : null,
      messageResultat: historique ? 'Arrivée : N°7' : null,
    );

/// Monte l'écran réel « Mes Paris » sur l'onglet Suivi.
Future<PmuProvider> _monter(
  WidgetTester tester, {
  UserPrediction? pred,
  double? montantSuivi,
  bool historique = false,
}) async {
  final store = _Store();
  await store.setValue('StringList', 'flutter.user_predictions_v2',
      pred == null
          ? <String>[]
          : <String>[jsonEncode(pred.toJson())]);
  await store.setValue('StringList', 'flutter.tracked_courses_v1',
      <String>[
        jsonEncode(
            _tc(montantGainManuel: montantSuivi, historique: historique)
                .toJson())
      ]);
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  await AlertService.instance.recharger();
  await (await SharedPreferences.getInstance()).reload();

  final pmu = PmuProvider();
  await pmu.reloadPredictions();
  await pmu.sauvegardeTerminee();
  AlertService.instance.setPmuProvider(pmu);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<PmuProvider>.value(value: pmu),
      ChangeNotifierProvider<NavigationNotifier>(
          create: (_) => NavigationNotifier()),
      ChangeNotifierProvider<DataRefreshService>.value(
          value: DataRefreshService.instance),
    ],
    child: const MaterialApp(home: MesPariScreen(initialTab: 1)),
  ));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  return pmu;
}

/// Occurrences du libellé « Gain gagné » RÉELLEMENT rendues à l'écran.
///
/// On lit tous les `Text` construits : c'est une mesure de RENDU, pas une
/// lecture de source. `findRichText` couvre le cas d'un libellé encapsulé.
int _nbGainGagne() =>
    find.textContaining('Gain gagné', findRichText: true).evaluate().length;

/// Occurrences de « Gain déclaré » (état 0 € déclaré).
int _nbGainDeclare() =>
    find.textContaining('Gain déclaré', findRichText: true).evaluate().length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('W — badge « Gain gagné » sur l\'écran réel', () {
    testWidgets('W1 gain manuel durable SANS verdict ⇒ badge VISIBLE',
        (tester) async {
      // ⚠️ PRÉMISSE VÉRIFIÉE, PAS SUPPOSÉE : `mountantGainManuel = 12.0`,
      //    `etatGain` absent, `isGagne` absent ⇒ aucun verdict.
      await _monter(tester, pred: _pred(montantGainManuel: 12.0));

      expect(_nbGainGagne(), 1,
          reason: 'le montant déclaré doit être affiché MÊME sans verdict');
      // Le montant lui-même est présent, pas seulement le mot.
      expect(find.textContaining('12'), findsWidgets);
      // Et la mention « déclaré » : un montant manuel n'est JAMAIS présenté
      // comme un gain officiel PMU.
      expect(find.textContaining('montant déclaré'), findsWidgets);
      expect(find.textContaining('gain officiel PMU'), findsNothing,
          reason: 'un montant manuel ne doit jamais être présenté comme '
              'un gain officiel');
    });

    testWidgets('W2 gain manuel de 0,0 € ⇒ badge VISIBLE, « 0 € », distinct '
        'de l\'absence', (tester) async {
      // 0,0 € EST une information : le pari est traité et le gain est nul.
      // Ce n'est PAS « inconnu ». La règle de présence du montant est donc
      // respectée : le badge existe.
      await _monter(tester, pred: _pred(montantGainManuel: 0.0));

      expect(_nbGainDeclare(), 1,
          reason: '0,0 € déclaré ⇒ un badge « Gain déclaré : 0 € »');
      expect(find.textContaining('Gain déclaré : 0 €'), findsWidgets);
      // Il n'est SURTOUT PAS présenté comme « Gain gagné » : un gain nul
      // n'est pas un gain.
      expect(_nbGainGagne(), 0,
          reason: '0,0 € n\'est pas un gain : le libellé « Gain gagné » '
              'serait une affirmation fausse');
    });

    testWidgets('W3 aucun gain, aucun verdict ⇒ AUCUN badge', (tester) async {
      await _monter(tester, pred: _pred());

      expect(_nbGainGagne(), 0);
      expect(_nbGainDeclare(), 0);
      // La carte, elle, est bien rendue : l'absence de badge n'est pas
      // l'absence de carte.
      expect(find.textContaining('Prix de Test'), findsWidgets);
    });

    testWidgets('W4 verdict officiel présent ⇒ AUCUN doublon (exactement 1)',
        (tester) async {
      // Gain DÉCLARÉ (12) ET verdict officiel ACCEPTÉ (45,0). La priorité
      // exige que l'officiel gagne, et surtout : UN SEUL badge.
      await _monter(
        tester,
        pred: _pred(
          montantGainManuel: 12.0,
          montantOfficielPmu: 45.0,
          decision: DecisionGainPmu.accepte,
        ),
        montantSuivi: 12.0,
      );

      expect(_nbGainGagne(), 1,
          reason: 'un seul badge, jamais un badge historique PLUS un badge '
              'durable pour le même ticket');
      // Le montant affiché est l'OFFICIEL, pas le déclaré.
      expect(find.textContaining('45'), findsWidgets);
      expect(find.textContaining('gain officiel PMU'), findsWidgets);
    });

    testWidgets('W5 décision officielle en attente ⇒ le montant DÉCLARÉ est '
        'conservé', (tester) async {
      // Un officiel est CONNU (99,0) mais AUCUNE décision n'est prise.
      // Règle : l'officiel ne remplace jamais le manuel sans acceptation.
      await _monter(
        tester,
        pred: _pred(montantGainManuel: 12.0, montantOfficielPmu: 99.0),
      );

      expect(find.textContaining('décision PMU en attente'), findsWidgets,
          reason: 'l\'écran doit annoncer qu\'une décision est attendue');
      // Le montant affiché reste 12, JAMAIS 99.
      expect(find.textContaining('12 €'), findsWidgets,
          reason: 'le montant déclaré doit être conservé');
      expect(find.textContaining('99 €'), findsNothing,
          reason: 'l\'officiel ne doit PAS s\'imposer sans acceptation');
    });

    testWidgets('W6 mise à jour du montant ⇒ le badge se rafraîchit',
        (tester) async {
      final pmu = await _monter(tester, pred: _pred(montantGainManuel: 12.0));
      expect(find.textContaining('12 €'), findsWidgets);

      // Mise à jour par l'API PUBLIQUE du provider (celle qu'utilise l'écran).
      await pmu.enregistrerGainManuelPrediction('p1', 25.0);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('25 €'), findsWidgets,
          reason: 'le badge doit suivre la valeur durable');
      expect(find.textContaining('12 €'), findsNothing,
          reason: 'l\'ancienne valeur ne doit pas subsister');
      expect(_nbGainGagne(), 1, reason: 'toujours un seul badge');

      // Cas d'annulation : le montant disparaît ⇒ plus aucun badge.
      await pmu.enregistrerGainManuelPrediction('p1', null);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      expect(_nbGainGagne(), 0);
      expect(_nbGainDeclare(), 0);
    });
    testWidgets('W7 ticket HISTORIQUE (verdict ET message) + gain durable ⇒ '
        'UN SEUL badge, jamais deux', (tester) async {
      // ⚠️ CE TEST COMBLE UNE LACUNE MESURÉE PAR MUTATION.
      //
      //    La mutation M6 (retrait de `!_porteBadgeHistorique`) SURVIVAIT à
      //    toute la suite : aucun test ne plaçait simultanément un ticket
      //    HISTORIQUE (`isGagne` + `messageResultat`, donc le bandeau de
      //    verdict est réellement construit) et un gain durable. Mesure du
      //    mutant : « Gain gagné » = **2**, « 45 » = **2** — deux badges, deux
      //    fois le même montant.
      //
      //    Ce test reproduit EXACTEMENT cette configuration. Il tombe sur le
      //    mutant et passe sur le code correct.
      await _monter(
        tester,
        pred: _pred(
          montantGainManuel: 12.0,
          montantOfficielPmu: 45.0,
          decision: DecisionGainPmu.accepte,
        ),
        montantSuivi: 12.0,
        historique: true,
      );

      // Le bandeau historique est bien construit : sans cela, le test ne
      // mesurerait pas le doublon (prémisse vérifiée, pas supposée).
      expect(find.textContaining('Arrivée : N°7'), findsWidgets,
          reason: 'le ticket doit être HISTORIQUE, sinon le bandeau de '
              'verdict n\'existe pas et le doublon est indétectable');

      expect(find.textContaining('Gain gagné', findRichText: true)
          .evaluate().length, 1,
          reason: 'un ticket historique PLUS un gain durable ne doit produire '
              'QU\'UN badge (mutation M6 = 2)');
      expect(find.textContaining('45', findRichText: true).evaluate().length,
          1,
          reason: 'le montant ne doit pas être affiché deux fois');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  FAMILLE X — LA PRIORITÉ EST BIEN CELLE DE `vueDurable`, PAS UNE COPIE.
  //
  //  Ces tests protègent le badge d'une divergence future : si l'écran se
  //  mettait à décider par lui-même, ces assertions tomberaient.
  // ═══════════════════════════════════════════════════════════════════════
  group('X — cohérence de la source unique', () {
    test('X1 verdict officiel sur le MODÈLE ⇒ vue nulle ⇒ pas de badge',
        () async {
      final p = _pred(montantGainManuel: 12.0, etatGain: EtatGain.attribue);
      expect(p.etatGain, EtatGain.attribue);
      expect(
          vueDurable(p, verdictOfficielPresent: p.etatGain != null), isNull);
    });

    test('X2 aucun montant, aucune décision ⇒ vue nulle', () async {
      expect(
          vueDurable(_pred(),
              verdictOfficielPresent: false),
          isNull);
    });

    test('X3 0,0 déclaré ⇒ vue NON nulle, montant 0,0 (pas null)', () async {
      final v = vueDurable(_pred(montantGainManuel: 0.0),
          verdictOfficielPresent: false);
      expect(v, isNotNull);
      expect(v!.montant, 0.0);
      expect(v.estOfficiel, isFalse);
    });

    test('X4 accepté ⇒ officiel ; refusé ⇒ manuel. JAMAIS l\'inverse',
        () async {
      final accepte = vueDurable(
          _pred(
              montantGainManuel: 12.0,
              montantOfficielPmu: 45.0,
              decision: DecisionGainPmu.accepte),
          verdictOfficielPresent: false);
      expect(accepte!.montant, 45.0);
      expect(accepte.estOfficiel, isTrue);

      final refuse = vueDurable(
          _pred(
              montantGainManuel: 12.0,
              montantOfficielPmu: 45.0,
              decision: DecisionGainPmu.refuse),
          verdictOfficielPresent: false);
      expect(refuse!.montant, 12.0);
      expect(refuse.estOfficiel, isFalse);
    });
  });
}
