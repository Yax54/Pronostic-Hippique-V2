// ═══════════════════════════════════════════════════════════════════════════
//  A6 n° 2-b-2 — CHARGEMENT HISTORIQUE CONTRÔLÉ DANS P3
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT — AUCUNE MODIFICATION DE PRODUCTION.
//
//  OBJET : prouver que le chargement historique ajouté dans P3
//  (`IaMemoryService.relancerRecuperationPMU`) respecte TOUTES les bornes du
//  mandat, et qu'il ne change NI les décisions de récupération NI les
//  résultats enregistrés.
//
//  ── MOYEN D'OBSERVATION CHOISI ───────────────────────────────────────────
//  Le chargement est injecté par `sourceProgrammeHistorique` (nouveau point
//  d'injection de 2-b-2, `null` par défaut). Les tests y branchent un
//  ENREGISTREUR qui note chaque date reçue, puis délègue à un faux programme.
//
//  Ce choix est DÉLIBÉRÉ : il permet d'OBSERVER les dates demandées sans
//  aucun réseau, sans `MockClient`, et donc sans qu'une interception HTTP
//  puisse masquer un appel supplémentaire. Si P3 appelait le chargement deux
//  fois, l'enregistreur verrait deux entrées — ce que le réseau mocké ne
//  garantirait pas avec la même netteté.
//
//  ── CE QUI EST PROUVÉ, TEST PAR TEST ─────────────────────────────────────
//    C1-1  plusieurs courses le MÊME jour      → UN SEUL chargement
//    C1-2  plusieurs dates distinctes          → UNE SEULE date chargée
//    C1-3  date ancienne                       → chargée EN PREMIER (pas
//                                                d'exclusion systématique)
//    C1-4  L0 déjà disponible                  → AUCUN chargement
//    C1-5  échec réseau                        → réessai possible ensuite
//    C1-6  cache ZoneTurf                      → le faux programme peut être
//                                                « en panne » puis répondre :
//                                                aucun blocage définitif
//    C1-7  `_reunions`                         → inchangé
//    C1-8  arrivées + cotes enregistrées       → inchangées
//    C1-9  compteurs L0 avant/après            → cohérents
//    C1-10 point d'injection par défaut        → `null` = comportement
//                                                d'avant 2-b-2 (aucun appel)
//    C1-11 journées restantes                  → décrémente, aucune exclusion
//
//  ── PORTÉE, À NE PAS SURINTERPRÉTER ──────────────────────────────────────
//  Ces tests sont SIMULÉS : ils prouvent le FONCTIONNEMENT des règles, pas
//  un taux de couverture L0 réel des utilisateurs. Aucun taux n'est affirmé.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ─────────────────────────── Formatage ─────────────────────────────────────

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String _jour(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// ─────────────────── Faux programme historique ─────────────────────────────

/// Réunion minimale pour une date donnée. `partants` vide : `_appliquerScoresIA`
/// ne fait alors qu'un passage sans appeler ELO, et aucun partant n'existe
/// (aucun impact sur les calculs IA).
ZtReunion _reunion(String dateStr, {int courses = 1}) => ZtReunion(
      code: 'R1',
      lieu: 'VINCENNES',
      discipline: 'Trot Attelé',
      dateStr: dateStr,
      courses: <ZtCourse>[
        for (var i = 1; i <= courses; i++)
          ZtCourse(
            numCourse: i,
            anchor: '1$i',
            nom: 'PRIX TEST $i',
            heure: '14:00',
            distance: '2100m',
            prix: '30000',
            type: 'Trot Attelé',
            piste: 'Pelouse',
            categorie: '',
            isQuinte: false,
            isQuarte: false,
            pronosticZt: const <int>[],
            partants: const <ZtPartant>[],
            dateStr: dateStr,
          ),
      ],
    );

/// Enregistreur de dates : note CHAQUE appel reçu, dans l'ordre.
class _Enregistreur {
  final List<DateTime> appels = <DateTime>[];
  final List<String> jours = <String>[];

  /// Nombre de courses à renvoyer (0 = « échec réseau » simulé).
  int coursesParAppel = 1;

  /// Si vrai, chaque appel rend une liste VIDE (échec réseau simulé).
  bool enPanne = false;

  /// Si renseigné, alimente L0 AVANT de rendre, comme le fait réellement
  /// `ZoneTurfService._capturerArriveesOfficielles` (zone_turf_service.dart:239).
  Future<void> Function(DateTime date)? capturerL0;

  Future<List<ZtReunion>> appeler(DateTime date) async {
    appels.add(date);
    jours.add(_jour(date));
    if (enPanne) return <ZtReunion>[];
    if (capturerL0 != null) await capturerL0!(date);
    return <ZtReunion>[_reunion(_fmt(date), courses: coursesParAppel)];
  }
}

// ────────────────────────── État simulé ────────────────────────────────────

const Map<String, double> _poidsDefaut = <String, double>{
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
  'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
  'mouvCote': 0.06, 'placeDepart': 0.03,
};

const Map<String, double> _scores = <String, double>{
  '4': 95.0, '7': 88.0, '2': 70.0, '9': 60.0,
  '1': 55.0, '3': 40.0, '5': 30.0, '8': 20.0,
};

Map<String, Object> _prefs({List<String>? pronostics}) => <String, Object>{
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode(<String, dynamic>{
        ..._poidsDefaut,
        'nbMisesAJour': 0,
        'calibrationScore': 50.0,
      }),
      'ia_seuils_v1': json.encode(<String, dynamic>{}),
      'ia_precision_v2': json.encode(<String, dynamic>{}),
      'ia_stats_labels_v1': json.encode(<String, dynamic>{}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
      if (pronostics != null) 'ia_pronostics_v2': pronostics,
    };

IaPronostic _pronostic({required String cle, required DateTime date}) =>
    IaPronostic(
      courseKey: cle,
      nomCourse: 'PRIX A6',
      hippodrome: 'VINCENNES',
      discipline: 'Trot Attelé',
      datePronostic: date,
      scoresIA: _scores,
      scoresCriteres: const <String, ScoresCriteres>{},
      confiancePredite: 70.0,
      typePariConseille: 'Simple Gagnant',
      resultatsReels: false,
      arriveeReelle: null,
    );

Future<void> _reset({
  List<IaPronostic> pronostics = const <IaPronostic>[],
}) async {
  SharedPreferences.setMockInitialValues(
      _prefs(pronostics: pronostics.map((p) => json.encode(p.toJson())).toList()));
  SharedPreferences.resetStatic();
  ArriveeOfficielleService.instance.viderMemoireSeulement();
  ZoneTurfService.viderCachePourResetComplet();
  await IaMemoryService.instance.recharger();
  // Le point d'injection est un champ du SINGLETON : il survit d'un test à
  // l'autre. On le remet à `null` pour que chaque test décide explicitement.
  IaMemoryService.instance.sourceProgrammeHistorique = null;
}

Future<void> _semerL0(String cle, List<List<int>> rangs) async {
  final e = ArriveeOfficielleService.depuisJsonCourse(
    <String, dynamic>{
      'statut': kStatutArriveeDefinitiveComplete,
      'isArriveeDefinitive': true,
      'arriveeDefinitive': true,
      'nombreDeclaresPartants': 12,
      'ordreArrivee': rangs,
    },
    courseKey: cle,
  );
  expect(e, isNotNull, reason: 'TÉMOIN : fixture L0 acceptée');
  final res = await ArriveeOfficielleService.instance.enregistrer(e!);
  expect(res.succes, isTrue, reason: 'TÉMOIN : écriture L0 confirmée');
}

/// Réseau PMU simulé pour la boucle de récupération de P3.
String _corpsRapports() => json.encode(<Map<String, dynamic>>[
      <String, dynamic>{
        'typePari': 'E_SIMPLE_GAGNANT',
        'rapports': <Map<String, dynamic>>[
          <String, dynamic>{'combinaison': '7', 'dividendePourUnEuro': 350},
        ],
      },
      <String, dynamic>{
        'typePari': 'E_QUINTE_ORDRE',
        'rapports': <Map<String, dynamic>>[
          <String, dynamic>{'combinaison': '7-4-2-9-1', 'dividendePourUnEuro': 12000},
        ],
      },
    ]);

Future<T> _avecPmu<T>(Future<T> Function() action) {
  final client = MockClient((request) async {
    if (request.url.path.contains('rapports-definitifs')) {
      return http.Response(_corpsRapports(), 200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response('{}', 200,
        headers: {'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

/// Réseau PMU simulé où les RAPPORTS ne sont PAS ENCORE PUBLIÉS (HTTP 404).
///
/// Nécessaire dès qu'un test doit observer PLUSIEURS exécutions de P3 : si les
/// rapports répondaient 200, la première exécution résoudrait TOUTES les
/// courses (`enregistrerResultat`), `_pronostics.where((p) => !p.resultatsReels)`
/// deviendrait vide et les exécutions suivantes n'auraient plus rien à
/// sélectionner — elles mesureraient une absence de courses, pas la
/// progression du chargement historique. C'est aussi le cas RÉEL d'un
/// historique récent dont les résultats ne sont pas publiés.
Future<T> _avecPmuNonPublie<T>(Future<T> Function() action) {
  final client = MockClient((request) async {
    if (request.url.path.contains('rapports-definitifs')) {
      return http.Response('', 404);
    }
    return http.Response('{}', 200,
        headers: {'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

IaPronostic? _pronosticDe(String cle) {
  final l = IaMemoryService.instance.pronostics
      .where((p) => p.courseKey == cle)
      .toList();
  return l.isEmpty ? null : l.first;
}

void main() {
  group('A6 n° 2-b-2 — chargement historique contrôlé dans P3', () {
    // ═════════════════════════════════════════════════════════════════════
    //  C1-1 — PLUSIEURS COURSES LE MÊME JOUR → UN SEUL CHARGEMENT
    // ═════════════════════════════════════════════════════════════════════
    test('C1-1 trois courses le même jour → un seul chargement', () async {
      final dep = DateTime.now().subtract(const Duration(days: 3));
      final j = _fmt(dep);
      final cles = <String>['R1C1_$j', 'R1C2_$j', 'R1C3_$j'];

      await _reset(pronostics: [
        for (final c in cles) _pronostic(cle: c, date: dep),
      ]);

      final rec = _Enregistreur()..coursesParAppel = 3;
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      debugPrint('C1-1 appels=${rec.jours} tente=${rapport['historiqueTente']} '
          'journee=${rapport['journeeChargee']}');

      expect(rapport['total'], 3, reason: 'TÉMOIN : 3 courses sélectionnées');
      expect(rec.appels, hasLength(1),
          reason: 'trois courses d\'UNE MÊME journée doivent coûter UN SEUL '
              'chargement — pas trois');
      expect(rec.jours.single, _jour(dep),
          reason: 'la date demandée doit être celle de la journée');
      expect(rapport['historiqueTente'], isTrue);
      expect(rapport['journeeChargee'], _jour(dep));
      expect(rapport['coursesChargees'], 3);
    });

    // ═════════════════════════════════════════════════════════════════════
    //  C1-2 — PLUSIEURS DATES → UNE SEULE DATE CHARGÉE
    // ═════════════════════════════════════════════════════════════════════
    test('C1-2 trois dates distinctes → une seule date chargée', () async {
      final base = DateTime.now().subtract(const Duration(days: 10));
      final dates = <DateTime>[
        DateTime(base.year, base.month, base.day),
        DateTime(base.year, base.month, base.day - 2),
        DateTime(base.year, base.month, base.day - 4),
      ];

      await _reset(pronostics: [
        for (var i = 0; i < dates.length; i++)
          _pronostic(cle: 'R2C${i + 1}_${_fmt(dates[i])}', date: dates[i]),
      ]);

      final rec = _Enregistreur();
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      debugPrint('C1-2 appels=${rec.jours} journeesRestantes='
          '${rapport['journeesRestantes']}');

      expect(rapport['total'], 3, reason: 'TÉMOIN : 3 courses');
      expect(rec.appels, hasLength(1),
          reason: 'UNE SEULE date doit être chargée par exécution');
      expect(rapport['journeesRestantes'], 3,
          reason: 'les 3 journées étaient sans L0 au moment du calcul');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  C1-3 — DATE ANCIENNE NON SYSTÉMATIQUEMENT IGNORÉE
    // ═════════════════════════════════════════════════════════════════════
    test('C1-3 la date la plus ANCIENNE est chargée en premier', () async {
      // La plus ancienne est en TÊTE de `aRelancer` défavorable : P3 trie du
      // plus récent au plus ancien (l.1147). Si le chargement suivait l'ordre
      // de `aRelancer`, c'est la plus RÉCENTE qui serait chargée et les
      // vieilles journées ne seraient jamais atteintes.
      final recente = DateTime.now().subtract(const Duration(days: 5));
      final ancienne = DateTime(2024, 3, 12);

      await _reset(pronostics: [
        _pronostic(cle: 'R3C1_${_fmt(recente)}', date: recente),
        _pronostic(cle: 'R3C2_${_fmt(ancienne)}', date: ancienne),
      ]);

      final rec = _Enregistreur();
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      debugPrint('C1-3 appels=${rec.jours} (ancienne=${_jour(ancienne)}, '
          'recente=${_jour(recente)})');

      expect(rec.jours.single, _jour(ancienne),
          reason: 'la journée la PLUS ANCIENNE doit être chargée : sinon les '
              'vieilles courses resteraient éternellement ignorées');
      expect(rec.jours.single, isNot(_jour(recente)),
          reason: 'TÉMOIN INVERSE : ce n\'est pas la plus récente');
      expect(rapport['journeeChargee'], _jour(ancienne));
    });

    // ═════════════════════════════════════════════════════════════════════
    //  C1-4 — L0 DÉJÀ DISPONIBLE → AUCUN CHARGEMENT INUTILE
    // ═════════════════════════════════════════════════════════════════════
    test('C1-4 toutes les journées couvertes → aucun chargement', () async {
      final dep = DateTime.now().subtract(const Duration(days: 6));
      final j = _fmt(dep);
      final cles = <String>['R4C1_$j', 'R4C2_$j'];

      await _reset(pronostics: [
        for (final c in cles) _pronostic(cle: c, date: dep),
      ]);

      // L0 contient DÉJÀ les deux courses.
      await _semerL0(cles[0], <List<int>>[<int>[1]]);
      await _semerL0(cles[1], <List<int>>[<int>[2]]);

      final rec = _Enregistreur();
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      debugPrint('C1-4 appels=${rec.jours} tente=${rapport['historiqueTente']} '
          'l0Avant=${rapport['l0PresentAvant']}');

      expect(rec.appels, isEmpty,
          reason: 'une journée intégralement couverte ne doit PAS être '
              'rechargée : ce serait un coût réseau sans bénéfice');
      expect(rapport['historiqueTente'], isFalse);
      expect(rapport['journeeChargee'], isNull);
      expect(rapport['l0PresentAvant'], 2,
          reason: 'TÉMOIN : les 2 courses étaient bien couvertes avant');
    });

    test('C1-4b une SEULE journée sans L0 parmi deux → seule celle-là',
        () async {
      final couverte = DateTime.now().subtract(const Duration(days: 8));
      final vide = DateTime.now().subtract(const Duration(days: 9));

      await _reset(pronostics: [
        _pronostic(cle: 'R5C1_${_fmt(couverte)}', date: couverte),
        _pronostic(cle: 'R5C2_${_fmt(vide)}', date: vide),
      ]);
      await _semerL0('R5C1_${_fmt(couverte)}', <List<int>>[<int>[3]]);

      final rec = _Enregistreur();
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      await _avecPmu(() => IaMemoryService.instance.relancerRecuperationPMU());

      debugPrint('C1-4b appels=${rec.jours}');
      expect(rec.jours.single, _jour(vide),
          reason: 'seule la journée NON couverte doit être chargée');
      expect(rec.jours, isNot(contains(_jour(couverte))));
    });

    // ═════════════════════════════════════════════════════════════════════
    //  C1-5 — ÉCHEC RÉSEAU → NOUVEL ESSAI POSSIBLE
    // ═════════════════════════════════════════════════════════════════════
    test('C1-5 échec réseau puis 2e exécution → la même journée est retentée',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 7));
      final j = _fmt(dep);

      await _reset(pronostics: [_pronostic(cle: 'R6C1_$j', date: dep)]);

      final rec = _Enregistreur()..enPanne = true;
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      // ── Exécution 1 : le chargement échoue ──
      final r1 = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());
      debugPrint('C1-5 exec1 appels=${rec.jours} tente=${r1['historiqueTente']} '
          'l0Apres=${r1['l0PresentApres']}');

      expect(rec.appels, hasLength(1), reason: 'TÉMOIN : un chargement tenté');
      expect(r1['historiqueTente'], isTrue,
          reason: 'la tentative a bien eu lieu (elle a échoué)');
      expect(r1['l0PresentApres'], 0,
          reason: 'aucune couverture après un échec réseau');

      // Le pronostic reste NON résolu : P3 est idempotent sur ce plan.
      // ⚠️ ASSERTION ADAPTÉE — A6 n° 2-b-3.
      // ANCIENNE ASSERTION : `resultatsReels == true`, au motif que « la
      // récupération PMU (indépendante) a réussi ». Elle consacrait
      // l'enregistrement d'une arrivée reconstruite depuis les rapports PMU
      // alors que le chargement historique vient d'ÉCHOUER, donc que L0 est
      // vide — exactement ce que 2-b-3 interdit.
      // NOUVELLE ATTENTE : la course reste NON résolue. C'est la condition
      // même du test : si elle était marquée, l'exécution 2 n'aurait plus rien
      // à sélectionner et ne pourrait pas prouver le réessai.
      expect(_pronosticDe('R6C1_$j')!.resultatsReels, isFalse,
          reason: 'L0 est vide après échec du chargement : la course doit '
              'rester NON résolue, donc réessayable');
      expect(_pronosticDe('R6C1_$j')!.arriveeReelle, isNull,
          reason: 'aucune arrivée PMU ne doit être enregistrée en l\'absence '
              'de L0');

      // ── Exécution 2 : le réseau revient, sur une AUTRE course non résolue ──
      // (Celle de l'exécution 1 est désormais résolue ; on ajoute donc une
      //  nouvelle course non résolue sur la MÊME journée pour que P3
      //  sélectionne encore cette journée.)
      rec.appels.clear();
      rec.jours.clear();
      rec.enPanne = false;

      // Nouvelle mémoire : la course précédente est résolue, une autre reste.
      await _reset(pronostics: [
        _pronostic(cle: 'R6C2_$j', date: dep),
      ]);
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      final r2 = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());
      debugPrint('C1-5 exec2 appels=${rec.jours} l0Apres=${r2['l0PresentApres']}');

      expect(rec.appels, hasLength(1),
          reason: 'la MÊME journée doit être retentée : un échec réseau ne '
              'doit jamais être définitif');
      expect(rec.jours.single, _jour(dep));
    });

    // ═════════════════════════════════════════════════════════════════════
    //  C1-6 — CACHE ZONETURF : PAS DE BLOCAGE DÉFINITIF
    // ═════════════════════════════════════════════════════════════════════
    test('C1-6 échec sans mise en cache → la journée reste éligible', () async {
      final dep = DateTime.now().subtract(const Duration(days: 11));
      final j = _fmt(dep);
      await _reset(pronostics: [_pronostic(cle: 'R7C1_$j', date: dep)]);

      // On observe le VRAI service : un programme pour une date passée
      // inexistante échoue et rend une liste vide.
      //
      // La mesure qui compte est CELLE-CI : `chargerProgramme` n'écrit
      // `_cache[dateStr]` qu'APRÈS un succès (l.252-253), et ses `return []`
      // d'échec (l.94 et l.247) le précèdent. Un échec n'est donc JAMAIS
      // mémorisé : un second appel re-tentera réellement le réseau.
      final urls = <Uri>[];
      final client = MockClient((request) async {
        urls.add(request.url);
        // Panne totale : tout échoue.
        return http.Response('', 500);
      });

      final reunions = await http.runWithClient(
        () => DataRefreshService.instance
            .chargerPourDate(DateTime(dep.year, dep.month, dep.day)),
        () => client,
      );

      expect(reunions, isEmpty, reason: 'TÉMOIN : l\'échec rend une liste vide');
      expect(urls, isNotEmpty, reason: 'TÉMOIN : une requête a bien eu lieu');

      // Second appel : il doit RÉÉMETTRE une requête, preuve qu'aucun cache
      // d'échec ne bloque définitivement.
      urls.clear();
      await http.runWithClient(
        () => DataRefreshService.instance
            .chargerPourDate(DateTime(dep.year, dep.month, dep.day)),
        () => client,
      );
      expect(urls, isNotEmpty,
          reason: 'un échec ne doit pas être mémorisé : le second appel doit '
              're-tenter le réseau');

      // Et rien n'a touché `_reunions`.
      expect(DataRefreshService.instance.reunions, isEmpty,
          reason: '`chargerPourDate` ne doit jamais écrire `_reunions`');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  C1-7 — `_reunions` INCHANGÉ
    // ═════════════════════════════════════════════════════════════════════
    test('C1-7 _reunions de DataRefreshService reste inchangé', () async {
      final dep = DateTime.now().subtract(const Duration(days: 12));
      final j = _fmt(dep);
      await _reset(pronostics: [_pronostic(cle: 'R8C1_$j', date: dep)]);

      final avant = DataRefreshService.instance.reunions;
      final avantLongueur = avant.length;
      final avantIdentite = identical(
          avant, DataRefreshService.instance.reunions);

      final rec = _Enregistreur();
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      await _avecPmu(() => IaMemoryService.instance.relancerRecuperationPMU());

      final apres = DataRefreshService.instance.reunions;
      debugPrint('C1-7 avant=$avantLongueur apres=${apres.length} '
          'memeObjet=$avantIdentite');

      expect(rec.appels, hasLength(1), reason: 'TÉMOIN : chargement effectué');
      expect(apres.length, avantLongueur,
          reason: 'la liste de la journée courante ne doit pas changer de '
              'taille');
      expect(identical(avant, apres), isTrue,
          reason: 'la référence `_reunions` ne doit pas être réassignée : '
              'seule `data_refresh_service.dart:672` (dans `_doRefresh`) le '
              'fait');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  C1-8 — L'ARRIVÉE VIENT DE L0, LES COTES DU PMU
    //
    //  ⚠️ ASSERTION INVERSÉE — A6 n° 2-b-3.
    //
    //  ANCIENNE ATTENTE : « l'arrivée enregistrée reste celle des rapports
    //  PMU ». Correcte sous 2-b-2, où L0 n'était qu'une source de mesure.
    //
    //  NOUVELLE ATTENTE : après chargement historique, l'arrivée enregistrée
    //  est celle que L0 vient de fournir — et les COTES, elles, restent
    //  celles du PMU. Ce test prouve donc maintenant les DEUX moitiés de la
    //  règle 2-b-3 dans une seule mesure.
    //
    //  Le scénario est conservé à l'identique : L0 est alimenté PAR le
    //  chargement historique (`capturerL0`), avec une arrivée différente de
    //  celle des rapports.
    // ═════════════════════════════════════════════════════════════════════
    test('C1-8 l\'arrivée enregistrée vient de L0, les cotes du PMU',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 13));
      final j = _fmt(dep);
      final cle = 'R9C1_$j';
      await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);

      // Le chargement historique alimente L0 avec une arrivée VOLONTAIREMENT
      // différente de celle que les rapports PMU simulés fourniront.
      const arriveeL0 = <List<int>>[<int>[3], <int>[8], <int>[5]];
      final rec = _Enregistreur()
        ..capturerL0 = ((DateTime d) async {
          await _semerL0(cle, arriveeL0);
        });
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      final p = _pronosticDe(cle);
      expect(p, isNotNull, reason: 'TÉMOIN : le pronostic existe');
      debugPrint('C1-8 enregistree=${p!.arriveeReelle} '
          'cotes=${p.cotesPmuParNumero} l0=${ArriveeOfficielleService.instance.arrivee(cle)}');

      // TÉMOIN : le chargement a bien eu lieu ET L0 contient une arrivée
      // DIFFÉRENTE de celle du PMU. Sans ce témoin, l'assertion suivante
      // pourrait passer simplement parce que L0 était vide.
      expect(rapport['historiqueTente'], isTrue);
      expect(ArriveeOfficielleService.instance.arrivee(cle), equals(arriveeL0));

      // ══ PREUVE : l'arrivée enregistrée vient de L0 ══
      expect(p.arriveeReelle, equals(<int>[3, 8, 5]),
          reason: 'l\'arrivée enregistrée doit être celle de L0 : depuis '
              '2-b-3, c\'est la SEULE source autorisée pour P3');
      expect(p.arriveeReelle, isNot(equals(<int>[7, 4, 2, 9, 1])),
          reason: 'l\'arrivée reconstruite depuis les rapports PMU ne doit '
              'plus être enregistrée');

      // Cotes PMU : le Simple Gagnant donne 350/100 = 3.5 pour le n°7.
      expect(p.cotesPmuParNumero['7'], equals(3.5),
          reason: 'les cotes enregistrées doivent rester celles du PMU — '
              'l\'appel aux rapports est conservé pour cette raison');
      expect(rapport['enregistresDepuisL0'], 1,
          reason: 'l\'unique enregistrement vient de L0');
      expect(p.resultatsReels, isTrue, reason: 'TÉMOIN : résultat enregistré');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  C1-9 — COMPTEURS L0 AVANT/APRÈS COHÉRENTS
    // ═════════════════════════════════════════════════════════════════════
    test('C1-9 compteurs avant/après cohérents et mesure 2-b-1 préservée',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 14));
      final j = _fmt(dep);
      final dejaCouverte = DateTime.now().subtract(const Duration(days: 20));
      final aCharger = dep;

      await _reset(pronostics: [
        _pronostic(cle: 'R1C1_${_fmt(dejaCouverte)}', date: dejaCouverte),
        _pronostic(cle: 'R1C2_$j', date: aCharger),
      ]);
      await _semerL0('R1C1_${_fmt(dejaCouverte)}', <List<int>>[<int>[1]]);

      // Le chargement simulé alimente L0 de la journée à charger.
      final rec = _Enregistreur()
        ..capturerL0 = ((DateTime d) async {
          await _semerL0('R1C2_$j', <List<int>>[<int>[4]]);
        });
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      debugPrint('C1-9 avant=${rapport['l0PresentAvant']} '
          'apres=${rapport['l0PresentApres']} '
          'present=${rapport['l0Present']} absent=${rapport['l0Absent']}');

      expect(rec.jours.single, _jour(aCharger),
          reason: 'TÉMOIN : c\'est la journée NON couverte qui est chargée');
      expect(rapport['l0PresentAvant'], 1,
          reason: 'une seule course était couverte avant (la journée à '
              'charger ne l\'était pas)');
      expect(rapport['l0PresentApres'], 2,
          reason: 'le chargement a couvert la seconde course');
      expect(
        (rapport['l0PresentApres'] as int) - (rapport['l0PresentAvant'] as int),
        1,
          reason: 'le delta doit correspondre aux courses effectivement '
              'couvertes par le chargement',
      );

      // La mesure 2-b-1 reste cohérente : elle est prise APRÈS le chargement,
      // donc elle reflète l'état post-chargement.
      expect(rapport['l0Present'], 2,
          reason: 'la mesure 2-b-1 doit refléter l\'état après chargement');
      expect(
        (rapport['l0Present'] as int) + (rapport['l0Absent'] as int),
        rapport['total'],
        reason: 'l\'invariant de 2-b-1 doit rester vrai',
      );
    });

    // ═════════════════════════════════════════════════════════════════════
    //  C1-10 — POINT D'INJECTION À `null` : COMPORTEMENT D'AVANT 2-b-2
    // ═════════════════════════════════════════════════════════════════════
    test('C1-10 sourceProgrammeHistorique null → aucun chargement', () async {
      final dep = DateTime.now().subtract(const Duration(days: 15));
      final j = _fmt(dep);
      await _reset(pronostics: [_pronostic(cle: 'R2C1_$j', date: dep)]);

      // `_reset` remet la source à `null` : c'est l'état par défaut.
      expect(IaMemoryService.instance.sourceProgrammeHistorique, isNull,
          reason: 'TÉMOIN : point d\'injection nul par défaut');

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      debugPrint('C1-10 tente=${rapport['historiqueTente']} '
          'journee=${rapport['journeeChargee']} recuperes=${rapport['recuperes']}');

      expect(rapport['historiqueTente'], isFalse,
          reason: 'sans source, aucun chargement ne doit être tenté');
      expect(rapport['journeeChargee'], isNull);
      expect(rapport['coursesChargees'], 0);
      // ⚠️ ASSERTION ADAPTÉE — A6 n° 2-b-3.
      // ANCIENNE ASSERTION : `recuperes == 1`, « le comportement de
      // récupération d'avant 2-b-2 doit être strictement préservé ». Elle
      // consacrait l'enregistrement de l'arrivée reconstruite depuis les
      // rapports PMU, désormais interdit.
      // NOUVELLE ATTENTE : sans chargement, L0 reste vide ; la course est donc
      // DIFFÉRÉE. Ce que 2-b-2 doit réellement préserver ici, c'est
      // l'ABSENCE d'appel à la source historique — et cela reste asserté.
      expect(rapport['recuperes'], 0,
          reason: 'sans L0, aucun résultat ne peut être enregistré');
      expect(rapport['introuvables'], 1,
          reason: 'la course est DIFFÉRÉE, pas silencieusement ignorée');
      expect(rapport['enregistresDepuisL0'], 0);
      // TÉMOIN : la course reste réessayable.
      final p = _pronosticDe('R2C1_$j');
      expect(p, isNotNull, reason: 'TÉMOIN : le pronostic existe');
      expect(p!.resultatsReels, isFalse,
          reason: 'aucun marquage définitif : le prochain passage pourra '
              'enregistrer dès que L0 sera alimenté');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  C1-11 — JOURNÉES RESTANTES : AUCUNE EXCLUSION DÉFINITIVE
    // ═════════════════════════════════════════════════════════════════════
    test('C1-11 après chargement d\'une journée, les autres restent éligibles',
        () async {
      // Trois journées distinctes, du plus ancien au plus récent.
      //
      // ⚠️ Ces dates sont DÉLIBÉRÉMENT situées DANS la fenêtre des 90 jours :
      // la purge des 90 jours (`_purgerVieuxPronostics`, ia_memory_service.dart)
      // supprime les pronostics NON RÉSOLUS plus vieux que 90 jours, et elle
      // est déclenchée par `_save()` dès qu'un résultat est récupéré. Un test
      // construit sur des dates de 2024 mesurerait donc la purge, et non le
      // chargement historique — mesuré : `🧹 Purge : 2 pronostics supprimés`
      // puis `journeeChargee=null` à l'exécution 2. La présente version
      // respecte la contrainte du mandat : AUCUNE limite d'âge n'est ajoutée
      // à P3, la purge existante n'est pas modifiée, le test s'y conforme.
      final maintenant = DateTime.now();
      final d1 = DateTime(maintenant.year, maintenant.month, maintenant.day)
          .subtract(const Duration(days: 40));
      final d2 = d1.add(const Duration(days: 2));
      final d3 = d1.add(const Duration(days: 4));

      // TÉMOIN : les trois dates sont bien dans la fenêtre de rétention.
      for (final d in <DateTime>[d1, d2, d3]) {
        expect(maintenant.difference(d).inDays, lessThan(90),
            reason: 'TÉMOIN : $d doit rester dans la fenêtre des 90 jours, '
                'sinon ce test mesurerait la purge et non le chargement');
      }

      await _reset(pronostics: [
        _pronostic(cle: 'R3C1_${_fmt(d1)}', date: d1),
        _pronostic(cle: 'R3C2_${_fmt(d2)}', date: d2),
        _pronostic(cle: 'R3C3_${_fmt(d3)}', date: d3),
      ]);

      final rec = _Enregistreur()
        ..capturerL0 = ((DateTime d) async {
          // Couvre la journée chargée, comme le ferait la production.
          final jj = _fmt(d);
          for (final p in IaMemoryService.instance.pronostics) {
            if (p.courseKey.endsWith('_$jj')) {
              await _semerL0(p.courseKey, <List<int>>[<int>[6]]);
            }
          }
        });
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      // ── Exécution 1 : d1 (la plus ancienne) est chargée ──
      final r1 = await _avecPmuNonPublie(
          () => IaMemoryService.instance.relancerRecuperationPMU());
      debugPrint('C1-11 exec1 journee=${r1['journeeChargee']} '
          'restantes=${r1['journeesRestantes']}');

      expect(r1['journeeChargee'], _jour(d1),
          reason: 'la plus ancienne d\'abord');
      expect(r1['journeesRestantes'], 3,
          reason: 'TÉMOIN : 3 journées étaient sans L0 au calcul');

      // ── Exécution 2 : d1 est couverte, d2 devient la plus ancienne ──
      rec.appels.clear();
      rec.jours.clear();
      final r2 = await _avecPmuNonPublie(
          () => IaMemoryService.instance.relancerRecuperationPMU());
      debugPrint('C1-11 exec2 journee=${r2['journeeChargee']} '
          'restantes=${r2['journeesRestantes']}');

      expect(r2['journeeChargee'], _jour(d2),
          reason: 'après couverture de d1, c\'est d2 qui doit être chargée : '
              'aucune journée n\'est définitivement exclue');

      // ── Exécution 3 : d3 ──
      rec.appels.clear();
      rec.jours.clear();
      final r3 = await _avecPmuNonPublie(
          () => IaMemoryService.instance.relancerRecuperationPMU());
      debugPrint('C1-11 exec3 journee=${r3['journeeChargee']} '
          'restantes=${r3['journeesRestantes']}');

      expect(r3['journeeChargee'], _jour(d3),
          reason: 'la progression doit atteindre la dernière journée');

      // ── Exécution 4 : plus rien à charger ──
      rec.appels.clear();
      rec.jours.clear();
      final r4 = await _avecPmuNonPublie(
          () => IaMemoryService.instance.relancerRecuperationPMU());
      debugPrint('C1-11 exec4 tente=${r4['historiqueTente']}');

      expect(r4['historiqueTente'], isFalse,
          reason: 'toutes les journées couvertes : plus aucun chargement');
      expect(rec.appels, isEmpty);
    });
  });
}
