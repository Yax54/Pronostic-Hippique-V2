// ═══════════════════════════════════════════════════════════════════════════
//  LOT A-0 — VALIDATION FONCTIONNELLE DE LA VOIE 3 (AlertService)
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE lib/.
//
//  ── CE QUI EST EXERCÉ, ET PAR QUEL POINT D'ENTRÉE RÉEL ────────────────────
//  Le déclencheur est celui de la PRODUCTION, sans attente de 60 secondes :
//
//      AlertService.init()                    (public)
//        → _instance._load()                  (rechargement SharedPreferences)
//        → _instance._startWatchdog()         (privé, alert_service.dart:1569)
//            → _checkAlerts()                 ← APPEL IMMÉDIAT, l.1577
//                → _fetchResultatAuto(tc, k)  ← voie 3, l.1831 → l.2041
//                    → _addAlert(...)                       l.2650
//                    → garde LOT A-0 (P3)                   l.2701
//                    → PmuProvider.validatePrediction(...)  l.2730
//
//  Aucune méthode privée n'est appelée depuis le test : `init()` est public,
//  et `_checkAlerts()` est atteint par le chemin réel du watchdog. C'est
//  exactement le mécanisme déjà utilisé par `a6_partants_p4_p5_test.dart`
//  (`_ouvrirAlertes()`), qui sert de référence et n'est pas modifié.
//
//  ── POURQUOI `.timeout` N'EST PAS UN PROBLÈME ICI ─────────────────────────
//  Ce fichier utilise `test()` (et non `testWidgets`) : l'horloge est RÉELLE,
//  donc les `Future.delayed` et les `.timeout(15 s)` de la production
//  progressent normalement. Aucun `tester.pump` n'est nécessaire.
//
//  ── RÉSEAU ────────────────────────────────────────────────────────────────
//  `http.runWithClient(action, () => MockClient(...))` : la production appelle
//  `package:http` `http.get` (alert_service.dart:2056). Aucun appel réel.
//
//  ── CE QUI EST VÉRIFIÉ ────────────────────────────────────────────────────
//   T-P3   : G+P + Simple Gagnant sur la MÊME course → le G+P ne reçoit AUCUNE
//            écriture financière (isCorrect null, gainRealise null), le Simple
//            Gagnant est écrit normalement (340,00 € pour 20 € à ×18,00).
//   T-P3b  : course ne contenant QUE des G+P → rien n'est écrit, et le chemin
//            a bien été exécuté (témoin : alerte de résultat produite).
//   T-P3c  : NON-RÉGRESSION — un Tiercé dans l'ordre sur une autre course est
//            toujours écrit avec son gain réel (250,00 € pour 10 € à ×25,00).
//            Le Tiercé ne relève pas de la garde A-0.
//
//  ── CE QUI N'EST PAS TOUCHÉ ───────────────────────────────────────────────
//  Gradient, poids, seuils, calibration, ELO, TOP3 learning, règles PMU,
//  calculs financiers. On ne fait que LIRE les effets observables.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ─────────────────────────── Constantes de scénario ─────────────────────────

/// Arrivée officielle servie par le faux serveur : 7 gagnant, 4 et 2 placés.
const List<int> kArrivee = <int>[7, 4, 2, 9, 1];

/// Mise engagée sur la course suivie (colonne `TrackedCourse.miseEngagee`).
const double kMise = 20.0;

/// Cote Simple Gagnant réellement publiée (×18,00).
const double kCoteGagnant = 18.00;

/// Gain attendu pour un Simple Gagnant : 20 × 18,00 − 20 = 340,00 €.
const double kGainSimple = kMise * kCoteGagnant - kMise; // 340.0

/// Gain attendu pour un Tiercé dans l'ordre : 10 × 25,00 = 250,00 €.
/// (la production ne retranche pas la mise sur les paris combinés — l.2433)
const double kGainTierce = 10.0 * 25.0; // 250.0

// ───────────────────────── Faux serveur PMU (aucun réseau) ──────────────────

/// Bloc `{typePari, rapports[]}` au format RÉEL de l'API (dividende en centimes).
Map<String, dynamic> _bloc(String type, List<String> combinaisons, int centimes) =>
    <String, dynamic>{
      'typePari': type,
      'rapports': <Map<String, dynamic>>[
        for (final c in combinaisons)
          {'combinaison': c, 'dividendePourUnEuro': centimes},
      ],
    };

/// Corps `/rapports-definitifs` :
///  • `E_SIMPLE_GAGNANT` → gagnant officiel « 7 » + cote ×18,00 ;
///  • `E_SIMPLE_PLACE`   → places « 7 », « 4 », « 2 » (pas un classement) ;
///  • `E_QUINTE_PLUS`    → combinaison ORDONNÉE 7-4-2-9-1.
///
/// ⚠️ Le rapport ORDONNÉ est INDISPENSABLE : sans lui `deciderArriveeOfficielle`
///    ne produit aucune arrivée (`decision.disponible == false`) et
///    `alert_service.dart:2253-2257` sort AVANT tout point d'écriture — le test
///    passerait alors sans rien prouver.
String _corpsRapports({bool avecTierce = false}) => json.encode(<dynamic>[
      _bloc('E_SIMPLE_GAGNANT', <String>['7'], (kCoteGagnant * 100).round()),
      _bloc('E_SIMPLE_PLACE', <String>['7', '4', '2'], 420),
      _bloc('E_QUINTE_PLUS', <String>[kArrivee.join('-')], 12000),
      if (avecTierce) _bloc('E_TIERCE', <String>[kArrivee.join('-')], 2500),
    ]);

/// True si l'URL demandée est celle des rapports définitifs.
/// Le chemin `/programme/.../participants` contient « programme » : l'ordre des
/// tests est donc significatif (rapports d'abord).
MockClient _client({bool avecTierce = false}) => MockClient((http.Request r) async {
      final String p = r.url.path;
      const Map<String, String> json = {'content-type': 'application/json'};
      if (p.contains('rapports-definitifs')) {
        return http.Response(_corpsRapports(avecTierce: avecTierce), 200, headers: json);
      }
      if (p.contains('participants')) {
        return http.Response('{"participants":[]}', 200, headers: json);
      }
      if (p.contains('programme')) {
        return http.Response('{"programme":{"reunions":[]}}', 200, headers: json);
      }
      return http.Response('{}', 200, headers: json);
    });

// ───────────────────────────── État simulé ─────────────────────────────────

const Map<String, double> _poidsDefaut = {
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
  'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
  'mouvCote': 0.06, 'placeDepart': 0.03,
};

/// Cache de préférences minimal : mêmes clés que les harnais existants.
Map<String, Object> _prefs({
  List<Map<String, dynamic>> predictions = const <Map<String, dynamic>>[],
  List<TrackedCourse> tracked = const <TrackedCourse>[],
}) =>
    <String, Object>{
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode({
        ..._poidsDefaut,
        'nbMisesAJour': 0,
        'calibrationScore': 50.0,
      }),
      'ia_seuils_v1': json.encode({}),
      'ia_precision_v2': json.encode({}),
      'ia_stats_labels_v1': json.encode({}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
      'user_predictions_v2':
          predictions.map((p) => json.encode(p)).toList(growable: false),
      'tracked_courses_v1':
          tracked.map((t) => json.encode(t.toJson())).toList(growable: false),
    };

/// `UserPrediction` sérialisée — mêmes clés que `UserPrediction.fromJson`.
Map<String, dynamic> _predJson({
  required String id,
  required int numR,
  required int numC,
  required String typePari,
  required double cote,
  double mise = kMise,
  int numeroCheval = 7,
  List<int> numerosJoues = const <int>[],
}) =>
    <String, dynamic>{
      'id': id,
      'dateStr': '20/11/2026',
      'numReunion': numR,
      'numCourse': numC,
      'nomCourse': 'PRIX A0 P3 R$numR C$numC',
      'hippodrome': 'VINCENNES',
      'numeroCheval': numeroCheval,
      'nomCheval': 'CHEVAL_$numeroCheval',
      'cote': cote,
      'typePari': typePari,
      'createdAt': DateTime(2026, 11, 20, 12, 0).toIso8601String(),
      'isCorrect': null,
      'scoreIA': 70.0,
      'montantMise': mise,
      'gainRealise': null,
      'numerosJoues': numerosJoues,
      'dividendePmuReel': null,
      'combinaisonPmu': null,
    };

/// Course suivie, départ à −40 min.
///
/// ⚠️ −40 min est MESURÉ, pas arbitraire : `diffMin <= −10` déclenche
///    `_fetchResultatAuto` (l.1820) tandis que `diffMin > −35` n'est plus vrai,
///    donc `_detecterDisqPendantCourse` (l.1833) n'ajoute pas de second chemin
///    réseau. Un seul appel HTTP, celui du résultat.
TrackedCourse _suivi({
  required int numR,
  required int numC,
  required String storageKey,
  required DateTime heureDepart,
  String typePari = 'Simple Gagnant',
  List<int> numerosJoues = const <int>[],
  double mise = kMise,
  double cote = kCoteGagnant,
}) =>
    TrackedCourse(
      numReunion: numR,
      numCourse: numC,
      nomCourse: 'PRIX A0 P3 R$numR C$numC',
      hippodrome: 'VINCENNES',
      heureDepart: heureDepart,
      numeroCheval: 7,
      nomCheval: 'CHEVAL_7',
      miseEngagee: mise,
      typePari: typePari,
      numerosJoues: numerosJoues,
      cote: cote,
      // ⚠️ Clé UNIQUE par scénario : `_resultatsVerifies` est un `Set` du
      //    singleton jamais vidé par `_load()`. Une clé réutilisée ferait
      //    sauter silencieusement le scénario suivant.
      storageKey: storageKey,
    );

/// Remise à zéro complète, comme dans `a6_partants_p4_p5_test.dart`.
Future<void> _reset({
  List<Map<String, dynamic>> predictions = const <Map<String, dynamic>>[],
  List<TrackedCourse> tracked = const <TrackedCourse>[],
}) async {
  SharedPreferences.setMockInitialValues(_prefs(
    predictions: predictions,
    tracked: tracked,
  ));
  SharedPreferences.resetStatic();
  ZoneTurfService.viderCachePourResetComplet();
  await EloService.instance.reinitialiser();
  await ArriveeOfficielleService.instance.charger();
  await IaMemoryService.instance.recharger();
}

/// Laisse progresser l'horloge RÉELLE jusqu'à ce que [c] soit vraie.
Future<bool> _attendreQue(bool Function() c, {int ms = 5000}) async {
  var ecoule = 0;
  while (ecoule < ms) {
    if (c()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    ecoule += 10;
  }
  return c();
}

/// Ouvre les alertes par le point d'entrée PUBLIC de production.
///
/// `init()` déclenche `_checkAlerts()` immédiatement (l.1577) : aucune attente
/// de 60 secondes n'est nécessaire.
Future<void> _ouvrirAlertes(PmuProvider pmu) async {
  AlertService.instance.setPmuProvider(pmu);
  await AlertService.init();
}

/// Ferme proprement le scénario : purge les courses suivies.
///
/// ⚠️ MESURÉ — `dispose()` NE DOIT PAS être appelé entre deux scénarios.
///    `AlertService` est un singleton (`AlertService._()` +
///    `static final _instance`), et `ChangeNotifier.dispose()` est
///    IRRÉVERSIBLE : toute utilisation ultérieure lève
///    « A AlertService was used after being disposed » sur le
///    `notifyListeners()` de `_checkAlerts()` (alert_service.dart:766→
///    `retirerSuivi`). Un `dispose()` par test casse donc tous les tests
///    suivants — mesuré : T-P3b et T-P3c échouaient pour ce seul motif.
///
///    Le démontage est donc limité à ce qui suffit à désarmer le réseau :
///    vider le suivi. Le `Timer.periodic` de 60 s reste armé, mais
///    `_startWatchdog()` l'annule et le recrée à chaque `init()` ; et un tick
///    sans course suivie n'émet aucune requête. La libération finale du
///    singleton a lieu une seule fois, dans `tearDownAll`.
Future<void> _fermerAlertes() async {
  for (final k in AlertService.instance.trackedCourses.keys.toList()) {
    await AlertService.instance.retirerSuivi(k);
  }
}

/// Récupère une prédiction par identifiant (`PmuProvider` les expose inversées).
UserPrediction _pred(PmuProvider p, String id) =>
    p.predictions.firstWhere((UserPrediction x) => x.id == id);

/// Affichage compact d'une valeur nullable pour la mesure imprimée.
String _v(Object? o) => o == null ? 'null' : o.toString();

void main() {
  // Libération UNIQUE du singleton, après le dernier scénario.
  tearDownAll(() {
    AlertService.instance.dispose();
  });
  // ═══════════════════════════════════════════════════════════════════════
  //  T-P3 — G+P et Simple Gagnant sur la MÊME course, un seul passage.
  //
  //  La garde P3 (alert_service.dart:2701) filtre par `pred.typePari` à
  //  l'intérieur de la boucle `matched`, qui contient TOUTES les prédictions
  //  de la course encore en attente. Les deux types sont donc bien vus par la
  //  même exécution : la différence observée ne peut venir que de la garde.
  // ═══════════════════════════════════════════════════════════════════════
  test('T-P3 — le G+P ne reçoit aucune écriture, le Simple Gagnant est écrit '
      'normalement (même course, même passage)', () async {
    final DateTime dep = DateTime.now().subtract(const Duration(minutes: 40));
    final String sk = 'R1C1_${dep.day}${dep.month}${dep.year}_a0p3a';

    await _reset(
      predictions: <Map<String, dynamic>>[
        _predJson(id: 'gp1', numR: 1, numC: 1, typePari: 'Gagnant+Placé', cote: kCoteGagnant),
        _predJson(id: 'sg1', numR: 1, numC: 1, typePari: 'Simple Gagnant', cote: kCoteGagnant),
      ],
      tracked: <TrackedCourse>[
        // La colonne suivie est un G+P : c'est le cas réel décrit au mandat.
        _suivi(numR: 1, numC: 1, storageKey: sk, heureDepart: dep,
            typePari: 'Gagnant+Placé'),
      ],
    );

    final PmuProvider pmu = PmuProvider();
    await pmu.reloadPredictions();
    expect(pmu.predictions.length, 2, reason: 'TÉMOIN : deux paris chargés');

    try {
      await http.runWithClient(
        () async {
          await _ouvrirAlertes(pmu);
          // Le watchdog évalue immédiatement ; _fetchResultatAuto est asynchrone
          // et non attendu par l'appelant. On attend une écriture RÉELLE.
          await _attendreQue(() => _pred(pmu, 'sg1').isCorrect != null);
        },
        () => _client(),
      );
    } finally {
      await _fermerAlertes();
    }

    final UserPrediction gp = _pred(pmu, 'gp1');
    final UserPrediction sg = _pred(pmu, 'sg1');

    // ignore: avoid_print
    print('─── MESURE T-P3 (voie 3 — AlertService) ──────────────────────');
    // ignore: avoid_print
    print('  G+P           : isCorrect=${_v(gp.isCorrect)} '
        'mise=${gp.montantMise} gainRealise=${_v(gp.gainRealise)} '
        'gainNet=${gp.gainNet}');
    // ignore: avoid_print
    print('  Simple Gagnant: isCorrect=${_v(sg.isCorrect)} '
        'mise=${sg.montantMise} gainRealise=${_v(sg.gainRealise)} '
        'gainNet=${sg.gainNet}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    // ── G+P : AUCUNE écriture financière ────────────────────────────────
    expect(gp.isCorrect, isNull,
        reason: 'P3 : le G+P ne doit pas être marqué gagnant');
    expect(gp.gainRealise, isNull,
        reason: 'P3 : aucun gain ne doit être réalisé sur un G+P');
    expect(gp.gainNet, 0.0,
        reason: 'P3 : le gain net G+P reste nul (aucune écriture fictive)');
    expect(gp.gainNet, isNot(closeTo(kGainSimple, 1e-9)),
        reason: 'P3 : le gain du Simple Gagnant ne doit pas fuiter sur le G+P');
    expect(gp.montantMise, kMise,
        reason: 'P3 : la mise du G+P n\'est pas réécrite');

    // ── Simple Gagnant : comportement NORMAL conservé ───────────────────
    expect(sg.isCorrect, isTrue,
        reason: 'TÉMOIN : le Simple Gagnant est bien validé gagnant');
    expect(sg.gainRealise, closeTo(kGainSimple, 1e-9),
        reason: 'Simple Gagnant : 20 € × 18,00 − 20 = 340,00 €');
    expect(sg.montantMise, kMise,
        reason: 'Simple Gagnant : la mise n\'est pas altérée');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T-P3b — course ne contenant QUE des G+P.
  //
  //  Vérifie la neutralisation QUAND TOUTES les entrées sont G+P : la boucle
  //  `matched` n'est pas vide (elle est parcourue), mais chaque itération est
  //  écartée. Le témoin de non-vacuité est l'alerte de résultat, produite
  //  AVANT la garde (l.2650 < l.2701) : elle prouve que la voie 3 est allée
  //  jusqu'au bout du chemin financier.
  // ═══════════════════════════════════════════════════════════════════════
  test('T-P3b — une course ne contenant QUE des G+P n\'écrit rien, '
      'et le chemin a bien été exécuté (témoin : alerte de résultat)', () async {
    final DateTime dep = DateTime.now().subtract(const Duration(minutes: 40));
    final String sk = 'R2C1_${dep.day}${dep.month}${dep.year}_a0p3b';

    await _reset(
      predictions: <Map<String, dynamic>>[
        _predJson(id: 'gp2', numR: 2, numC: 1, typePari: 'Gagnant+Placé', cote: kCoteGagnant),
      ],
      tracked: <TrackedCourse>[
        _suivi(numR: 2, numC: 1, storageKey: sk, heureDepart: dep,
            typePari: 'Gagnant+Placé'),
      ],
    );

    final PmuProvider pmu = PmuProvider();
    await pmu.reloadPredictions();

    var alerteResultat = false;
    try {
      await http.runWithClient(
        () async {
          await _ouvrirAlertes(pmu);
          // Témoin : l'alerte de résultat est produite AVANT la garde A-0.
          alerteResultat = await _attendreQue(
            () => AlertService.instance.alerts
                .any((AppAlert a) => a.id.contains('_resultat')),
          );
        },
        () => _client(),
      );
    } finally {
      await _fermerAlertes();
    }

    final UserPrediction gp = _pred(pmu, 'gp2');

    // ignore: avoid_print
    print('─── MESURE T-P3b (course 100 % G+P) ─────────────────────────');
    // ignore: avoid_print
    print('  alerte de résultat produite : $alerteResultat');
    // ignore: avoid_print
    print('  G+P : isCorrect=${_v(gp.isCorrect)} '
        'gainRealise=${_v(gp.gainRealise)} gainNet=${gp.gainNet}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(alerteResultat, isTrue,
        reason: 'TÉMOIN : la voie 3 a bien atteint le bloc de résultat');
    expect(gp.isCorrect, isNull, reason: 'P3 : aucun G+P marqué gagnant');
    expect(gp.gainRealise, isNull, reason: 'P3 : aucun gain G+P écrit');
    expect(gp.gainNet, 0.0, reason: 'P3 : gain net G+P nul');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T-P3c — NON-RÉGRESSION d'un autre type de pari.
  //
  //  Le Tiercé n'est pas concerné par la garde A-0 : il doit conserver
  //  exactement son comportement d'avant, gain réel inclus.
  // ═══════════════════════════════════════════════════════════════════════
  test('T-P3c — non-régression : un Tiercé dans l\'ordre reste écrit avec son '
      'gain réel', () async {
    final DateTime dep = DateTime.now().subtract(const Duration(minutes: 40));
    final String sk = 'R3C1_${dep.day}${dep.month}${dep.year}_a0p3c';

    await _reset(
      predictions: <Map<String, dynamic>>[
        _predJson(
          id: 'tc3',
          numR: 3,
          numC: 1,
          typePari: 'Tiercé',
          cote: 0.0,
          mise: 10.0,
          numerosJoues: <int>[7, 4, 2],
        ),
      ],
      tracked: <TrackedCourse>[
        _suivi(numR: 3, numC: 1, storageKey: sk, heureDepart: dep,
            typePari: 'Tiercé', numerosJoues: <int>[7, 4, 2],
            mise: 10.0, cote: 0.0),
      ],
    );

    final PmuProvider pmu = PmuProvider();
    await pmu.reloadPredictions();

    try {
      await http.runWithClient(
        () async {
          await _ouvrirAlertes(pmu);
          await _attendreQue(() => _pred(pmu, 'tc3').isCorrect != null);
        },
        () => _client(avecTierce: true),
      );
    } finally {
      await _fermerAlertes();
    }

    final UserPrediction tc = _pred(pmu, 'tc3');

    // ignore: avoid_print
    print('─── MESURE T-P3c (non-régression Tiercé) ────────────────────');
    // ignore: avoid_print
    print('  Tiercé : isCorrect=${_v(tc.isCorrect)} '
        'mise=${tc.montantMise} gainRealise=${_v(tc.gainRealise)} '
        'gainNet=${tc.gainNet}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    expect(tc.isCorrect, isTrue,
        reason: 'Non-régression : un Tiercé ordre gagnant reste validé');
    expect(tc.gainRealise, closeTo(kGainTierce, 1e-9),
        reason: 'Non-régression : 10 € × 25,00 = 250,00 € (comportementinaltéré)');
    expect(tc.montantMise, 10.0, reason: 'Non-régression : mise inchangée');
  });
}
