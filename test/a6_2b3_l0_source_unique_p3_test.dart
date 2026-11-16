// ═══════════════════════════════════════════════════════════════════════════
//  A6 n° 2-b-3 — L0 COMME SOURCE UNIQUE D'ARRIVÉE DANS P3
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT.
//
//  OBJET : prouver que `IaMemoryService.relancerRecuperationPMU()` (P3)
//  n'enregistre plus AUCUN résultat qui ne provienne pas de L0
//  (`ArriveeOfficielleService`), et que les deux reports (L0 absent, ex æquo)
//  ne laissent aucune trace définitive.
//
//  ── CE QUI EST PROUVÉ, TEST PAR TEST ─────────────────────────────────────
//    D1-1   journée PARTIELLEMENT couverte     → chargement TENTÉ (règle 2-b-3)
//    D1-2   L0 présent, sans ex æquo           → ordre officiel L0 enregistré
//    D1-3   L0 absent                          → rien d'enregistré, réessai OK
//    D1-4   L0 avec ex æquo                    → rien d'enregistré, cas signalé
//    D1-4b  ex æquo + course saine le même jour→ le refus reste CIBLÉ
//    D1-5   plusieurs courses du même jour     → UN SEUL chargement
//    D1-6   cotes PMU                          → préservées ET arrivée = L0
//    D1-7   résultat déjà enregistré           → jamais réécrit
//    D1-8   rattrapage J-7 et plus ancien      → aucune exclusion définitive
//    D1-9   P1, P2, P4, P5                     → inchangés (mesuré)
//
//  ── MOYEN D'OBSERVATION ──────────────────────────────────────────────────
//  Le chargement historique est injecté par `sourceProgrammeHistorique`
//  (point d'injection 2-b-2, `null` par défaut) : les tests y branchent un
//  ENREGISTREUR de dates, ce qui rend visible tout chargement supplémentaire
//  sans dépendre d'une interception réseau.
//
//  ── PORTÉE, À NE PAS SURINTERPRÉTER ──────────────────────────────────────
//  Ces tests sont SIMULÉS : ils prouvent le FONCTIONNEMENT des règles, pas un
//  taux de couverture L0 réel des utilisateurs. Aucun taux n'est affirmé.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
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

  /// Si vrai, chaque appel rend une liste VIDE (échec réseau simulé).
  bool enPanne = false;

  /// Alimente L0 AVANT de rendre, comme `_capturerArriveesOfficielles`
  /// (zone_turf_service.dart:239-243) le fait réellement en production.
  Future<void> Function(DateTime date)? capturerL0;

  Future<List<ZtReunion>> appeler(DateTime date) async {
    appels.add(date);
    jours.add(_jour(date));
    if (enPanne) return <ZtReunion>[];
    if (capturerL0 != null) await capturerL0!(date);
    return <ZtReunion>[_reunion(_fmt(date))];
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

// Liste des PARTANTS analysés, telle que la produit la production :
// `partantsClasses` est construit depuis `course.partants` COMPLET
// (`data_refresh_service.dart:978`), donc `scoresIA` couvre TOUS les partants.
// A6 §5 s'appuie sur cette liste pour vérifier l'appartenance d'un numéro
// d'arrivée. La fixture doit donc être aussi complète que la production,
// sinon elle simulerait une course à 7 partants dont l'arrivée contient un
// 8e cheval — un cas qui n'existe pas en production.
const Map<String, double> _scores = <String, double>{
  '4': 95.0, '7': 88.0, '2': 70.0, '9': 60.0,
  '1': 55.0, '3': 40.0, '5': 30.0, '8': 20.0,
  '6': 15.0,
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

IaPronostic _pronostic({
  required String cle,
  required DateTime date,
  bool resolu = false,
  List<int>? arrivee,
}) =>
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
      resultatsReels: resolu,
      arriveeReelle: arrivee,
      dateResultat: resolu ? date : null,
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
  // TÉMOIN DE LECTURE : l'entrée est visible AVANT de lancer P3.
  expect(ArriveeOfficielleService.instance.arrivee(cle), equals(rangs),
      reason: 'TÉMOIN : L0 rend bien ce qui vient d\'être écrit');
}

/// Rapports PMU simulés. Le Simple Gagnant porte 350 centimes → cote 3.5.
String _corpsRapports({String gagnant = '7', String quinte = '7-4-2-9-1'}) =>
    json.encode(<Map<String, dynamic>>[
      <String, dynamic>{
        'typePari': 'E_SIMPLE_GAGNANT',
        'rapports': <Map<String, dynamic>>[
          <String, dynamic>{
            'combinaison': gagnant,
            'dividendePourUnEuro': 350,
          },
        ],
      },
      <String, dynamic>{
        'typePari': 'E_QUINTE_ORDRE',
        'rapports': <Map<String, dynamic>>[
          <String, dynamic>{
            'combinaison': quinte,
            'dividendePourUnEuro': 12000,
          },
        ],
      },
    ]);

Future<T> _avecPmu<T>(Future<T> Function() action, {String? corps}) {
  final client = MockClient((request) async {
    if (request.url.path.contains('rapports-definitifs')) {
      return http.Response(corps ?? _corpsRapports(), 200,
          headers: {'content-type': 'application/json'});
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
  group('A6 n° 2-b-3 — L0 source unique dans P3', () {
    // ═════════════════════════════════════════════════════════════════════
    //  D1-1 — JOURNÉE PARTIELLEMENT COUVERTE → CHARGEMENT TENTÉ
    //
    //  C'est la RÈGLE 1 du mandat : « une journée est candidate au chargement
    //  dès qu'au moins une course non résolue ne possède pas d'arrivée L0 ».
    //  L'ancienne condition (`couvertes == 0`) rendait cette journée
    //  définitivement inéligible.
    // ═════════════════════════════════════════════════════════════════════
    test('D1-1 journée partiellement couverte → le chargement est tenté',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 3));
      final j = _fmt(dep);
      final couverte = 'R1C1_$j';
      final nonCouverte = 'R1C2_$j';

      await _reset(pronostics: [
        _pronostic(cle: couverte, date: dep),
        _pronostic(cle: nonCouverte, date: dep),
      ]);

      // UNE seule des deux courses est dans L0 : couverture PARTIELLE.
      await _semerL0(couverte, <List<int>>[
        <int>[1]
      ]);

      // TÉMOIN DE CAUSE : la partialité existe réellement.
      expect(ArriveeOfficielleService.instance.arrivee(couverte), isNotNull,
          reason: 'TÉMOIN : la 1re course est couverte');
      expect(ArriveeOfficielleService.instance.arrivee(nonCouverte), isNull,
          reason: 'TÉMOIN : la 2e ne l\'est pas — la journée est partielle');

      final rec = _Enregistreur();
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      debugPrint('D1-1 tente=${rapport['historiqueTente']} '
          'journee=${rapport['journeeChargee']} appels=${rec.jours}');

      // L'ANCIENNE règle aurait laissé `historiqueTente` à false : la journée
      // avait au moins une course couverte.
      expect(rapport['historiqueTente'], isTrue,
          reason: 'une journée PARTIELLEMENT couverte doit désormais être '
              'chargée : sinon ses courses sans L0 ne seraient jamais résolues');
      expect(rapport['journeeChargee'], _jour(dep),
          reason: 'c\'est bien la journée partielle qui doit être chargée');
      expect(rec.jours, hasLength(1),
          reason: 'UN SEUL chargement, même pour une journée partielle');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  D1-2 — L0 PRÉSENT SANS EX ÆQUO → ORDRE OFFICIEL ENREGISTRÉ
    //
    //  L0 porte VOLONTAIREMENT un ordre différent de celui des rapports PMU :
    //  c'est la seule façon de prouver que l'arrivée enregistrée vient de L0
    //  et non d'une reconstruction PMU.
    // ═════════════════════════════════════════════════════════════════════
    test('D1-2 L0 présent sans ex æquo → l\'ordre officiel L0 est enregistré',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 4));
      final cle = 'R2C1_${_fmt(dep)}';

      await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);

      // L0 : 1 - 9 - 2 - 4 - 7   (PMU simulé : 7 - 4 - 2 - 9 - 1)
      const arriveeL0 = <List<int>>[
        <int>[1], <int>[9], <int>[2], <int>[4], <int>[7]
      ];
      await _semerL0(cle, arriveeL0);

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      final p = _pronosticDe(cle);
      expect(p, isNotNull, reason: 'TÉMOIN : le pronostic existe toujours');
      debugPrint('D1-2 enregistree=${p!.arriveeReelle} '
          'resultatsReels=${p.resultatsReels} '
          'recuperes=${rapport['recuperes']} '
          'depuisL0=${rapport['enregistresDepuisL0']}');

      expect(rapport['recuperes'], 1, reason: 'un résultat a été enregistré');
      expect(rapport['enregistresDepuisL0'], 1,
          reason: 'il l\'a été DEPUIS L0 — c\'est la seule source autorisée');

      expect(p.arriveeReelle, equals(<int>[1, 9, 2, 4, 7]),
          reason: 'l\'ordre enregistré est celui de L0, aplati sans perte '
              '(aucun groupe d\'ex æquo ici)');
      expect(p.arriveeReelle, isNot(equals(<int>[7, 4, 2, 9, 1])),
          reason: 'PREUVE DÉCISIVE : l\'ordre des rapports PMU ne doit plus '
              'être utilisé comme arrivée');
      expect(p.resultatsReels, isTrue, reason: 'TÉMOIN : résultat marqué réel');

      // L0 n'a pas été altéré par la lecture.
      expect(ArriveeOfficielleService.instance.arrivee(cle), equals(arriveeL0),
          reason: 'L0 est lu, jamais réécrit');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  D1-3 — L0 ABSENT → RIEN N'EST ENREGISTRÉ, RÉESSAI POSSIBLE
    //
    //  Les rapports PMU répondent 200 avec une arrivée complète : c'est le
    //  piège exact que le mandat interdit de suivre.
    // ═════════════════════════════════════════════════════════════════════
    test('D1-3 L0 absent → aucun résultat enregistré, réessai possible',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 5));
      final cle = 'R3C1_${_fmt(dep)}';

      await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);

      // TÉMOIN DE CAUSE : L0 est vide pour cette course…
      expect(ArriveeOfficielleService.instance.arrivee(cle), isNull,
          reason: 'TÉMOIN : aucune arrivée officielle disponible');
      // …alors que le PMU simulé en fournit une complète.

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      final p = _pronosticDe(cle);
      debugPrint('D1-3 enregistree=${p?.arriveeReelle} '
          'resultatsReels=${p?.resultatsReels} '
          'recuperes=${rapport['recuperes']} '
          'introuvables=${rapport['introuvables']}');

      expect(p!.arriveeReelle, isNull,
          reason: 'AUCUNE arrivée reconstruite depuis les rapports PMU ne doit '
              'être enregistrée lorsque L0 est absent');
      expect(p.resultatsReels, isFalse,
          reason: 'le pronostic n\'est PAS marqué résolu — il reste réessayable');
      expect(p.dateResultat, isNull,
          reason: 'aucune date de résultat ne doit être posée');
      expect(p.scorePerformance, isNull,
          reason: 'aucun score ne doit être calculé sur une arrivée inventée');
      expect(rapport['recuperes'], 0,
          reason: 'rien n\'a été enregistré');
      expect(rapport['introuvables'], 1,
          reason: 'la course est comptée comme DIFFÉRÉE');

      final details = rapport['details'] as List<String>;
      expect(details.where((d) => d.contains('arrivée officielle L0 absente')),
          hasLength(1),
          reason: 'le report doit être journalisé explicitement');

      // ── RÉESSAI : L0 est alimenté, la course doit être reprise ──────────
      await _semerL0(cle, <List<int>>[
        <int>[3], <int>[6], <int>[8]
      ]);
      final rec = _Enregistreur()..enPanne = true; // aucun chargement utile
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      final r2 = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      final p2 = _pronosticDe(cle);
      debugPrint('D1-3 reessai enregistree=${p2?.arriveeReelle} '
          'recuperes=${r2['recuperes']}');

      expect(p2!.arriveeReelle, equals(<int>[3, 6, 8]),
          reason: 'le réessai doit aboutir dès que L0 est disponible : le '
              'premier échec n\'a laissé AUCUN marquage définitif');
      expect(p2.resultatsReels, isTrue);
    });

    // ═════════════════════════════════════════════════════════════════════
    //  D1-4 — EX ÆQUO → RIEN N'EST ENREGISTRÉ, LE CAS EST SIGNALÉ
    //
    //  Sécurité verbatim du mandat : « Ne pas aplatir silencieusement une
    //  arrivée contenant des ex æquo pour déclencher un apprentissage
    //  incorrect. »
    // ═════════════════════════════════════════════════════════════════════
    test('D1-4 ex æquo dans L0 → aucun enregistrement, aucun apprentissage',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 6));
      final cle = 'R4C1_${_fmt(dep)}';

      await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);

      // Groupe [7, 4] : deux chevaux ex æquo à la 1re place.
      const arriveeL0 = <List<int>>[
        <int>[7, 4], <int>[2], <int>[9]
      ];
      await _semerL0(cle, arriveeL0);

      final apprentissagesAvant =
          IaMemoryService.instance.poids.nbMisesAJour;
      final poidsAvant = <double>[
        IaMemoryService.instance.poids.forme,
        IaMemoryService.instance.poids.cote,
        IaMemoryService.instance.poids.elo,
        IaMemoryService.instance.poids.divergence,
      ];

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      final p = _pronosticDe(cle);
      final details = rapport['details'] as List<String>;
      debugPrint('D1-4 enregistree=${p?.arriveeReelle} '
          'exAequoDifferes=${rapport['exAequoDifferes']} '
          'recuperes=${rapport['recuperes']}');

      // ── AUCUN ENREGISTREMENT ────────────────────────────────────────────
      expect(p!.arriveeReelle, isNull,
          reason: 'une arrivée avec ex æquo ne doit PAS être aplatie en liste '
              'plate : elle n\'est pas enregistrée du tout');
      expect(p.resultatsReels, isFalse,
          reason: 'aucun marquage définitif : la course reste réessayable');
      expect(rapport['recuperes'], 0, reason: 'aucun résultat enregistré');
      expect(rapport['exAequoDifferes'], 1,
          reason: 'le refus est COMPTÉ dans son propre compteur');

      // ── AUCUN APPRENTISSAGE ─────────────────────────────────────────────
      final apprentissagesApres =
          IaMemoryService.instance.poids.nbMisesAJour;
      final poidsApres = <double>[
        IaMemoryService.instance.poids.forme,
        IaMemoryService.instance.poids.cote,
        IaMemoryService.instance.poids.elo,
        IaMemoryService.instance.poids.divergence,
      ];
      expect(apprentissagesApres, apprentissagesAvant,
          reason: 'aucune mise à jour de poids ne doit être déclenchée');
      expect(poidsApres, equals(poidsAvant),
          reason: 'les poids doivent être strictement inchangés');

      // ── SIGNALEMENT EXPLICITE ───────────────────────────────────────────
      // Le diagnostic des ex æquo est inséré en tête pendant la boucle, puis
      // les deux synthèses (2-b-1, 2-b-3) le repoussent : on le cible donc par
      // son libellé propre, pas par sa position.
      final aequoLines =
          details.where((d) => d.contains('REFUSÉ')).toList();
      expect(aequoLines, isNotEmpty,
          reason: 'le cas doit être SIGNALÉ dans le diagnostic');
      expect(aequoLines.first, contains('[7,4]'),
          reason: 'le signalement doit nommer le groupe d\'ex æquo');
      expect(aequoLines.first, contains('REFUSÉ'),
          reason: 'le signalement doit dire que l\'enregistrement a été refusé');
      // La ligne de synthèse « source des résultats » porte le compteur.
      // Elle n'est PAS en tête : la mesure L0 de 2-b-1 y reste, comme avant.
      final synthese = details
          .where((d) => d.contains('Source des résultats'))
          .toList();
      expect(synthese, hasLength(1),
          reason: 'la synthèse « source des résultats » doit être présente '
              'une seule fois');
      expect(synthese.first, contains('1 ex æquo différé(s)'),
          reason: 'elle doit exposer le compteur d\'ex æquo');
      expect(synthese.first, contains('0 enregistré(s) depuis L0'),
          reason: 'et le nombre d\'enregistrements effectifs');
      // ── L0 INTACT ───────────────────────────────────────────────────────
      expect(ArriveeOfficielleService.instance.arrivee(cle), equals(arriveeL0),
          reason: 'L0 ne doit pas être modifié : le mandat l\'interdit');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  D1-4b — LE REFUS EX ÆQUO EST CIBLÉ, PAS GLOBAL
    //
    //  Sans ce témoin inverse, D1-4 pourrait passer avec un code qui refuse
    //  TOUT. On prouve ici qu'une course sans ex æquo, le MÊME jour, est bien
    //  enregistrée.
    // ═════════════════════════════════════════════════════════════════════
    test('D1-4b ex æquo sur une course, saine sur une autre → refus CIBLÉ',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 7));
      final j = _fmt(dep);
      final avecExAequo = 'R5C1_$j';
      final sansExAequo = 'R5C2_$j';

      await _reset(pronostics: [
        _pronostic(cle: avecExAequo, date: dep),
        _pronostic(cle: sansExAequo, date: dep),
      ]);

      await _semerL0(avecExAequo, <List<int>>[
        <int>[7, 4], <int>[2]
      ]);
      await _semerL0(sansExAequo, <List<int>>[
        <int>[5], <int>[3], <int>[8]
      ]);

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      final pa = _pronosticDe(avecExAequo);
      final ps = _pronosticDe(sansExAequo);
      debugPrint('D1-4b exAequo=${pa?.arriveeReelle} '
          'saine=${ps?.arriveeReelle} '
          'exAequoDifferes=${rapport['exAequoDifferes']} '
          'recuperes=${rapport['recuperes']}');

      expect(pa!.arriveeReelle, isNull,
          reason: 'la course avec ex æquo est différée');
      expect(pa.resultatsReels, isFalse);
      expect(ps!.arriveeReelle, equals(<int>[5, 3, 8]),
          reason: 'la course SANS ex æquo est enregistrée normalement : le '
              'refus ne doit pas être global');
      expect(ps.resultatsReels, isTrue);
      expect(rapport['recuperes'], 1, reason: 'exactement un enregistrement');
      expect(rapport['exAequoDifferes'], 1,
          reason: 'exactement un report pour ex æquo');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  D1-5 — PLUSIEURS COURSES DU MÊME JOUR → UN SEUL CHARGEMENT
    // ═════════════════════════════════════════════════════════════════════
    test('D1-5 plusieurs courses sans L0 le même jour → un seul chargement',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 8));
      final j = _fmt(dep);
      final cles = <String>['R6C1_$j', 'R6C2_$j', 'R6C3_$j'];

      await _reset(pronostics: [
        for (final c in cles) _pronostic(cle: c, date: dep),
      ]);

      final rec = _Enregistreur();
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      debugPrint('D1-5 appels=${rec.jours} tente=${rapport['historiqueTente']}');

      expect(rapport['total'], 3, reason: 'TÉMOIN : 3 courses sélectionnées');
      expect(rec.appels, hasLength(1),
          reason: 'trois courses d\'UNE MÊME journée coûtent UN SEUL '
              'chargement — jamais trois');
      expect(rec.jours.single, _jour(dep),
          reason: 'la date demandée est celle de la journée');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  D1-6 — COTES PMU PRÉSERVÉES, ARRIVÉE ISSUE DE L0
    //
    //  Le mandat exige de CONSERVER les appels HTTP pour les cotes. Ce test
    //  prouve les deux moitiés de la règle en une seule mesure.
    // ═════════════════════════════════════════════════════════════════════
    test('D1-6 cotes PMU conservées alors que l\'arrivée vient de L0',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 9));
      final cle = 'R7C1_${_fmt(dep)}';

      await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);

      // L0 et PMU DIVERGENT dans l'ordre ET dans le gagnant : cote 3.5 pour
      // le n°7 côté PMU, alors que L0 place le n°1 en tête.
      await _semerL0(cle, <List<int>>[
        <int>[1], <int>[9], <int>[2], <int>[4], <int>[7]
      ]);

      final urls = <Uri>[];
      final client = MockClient((request) async {
        urls.add(request.url);
        if (request.url.path.contains('rapports-definitifs')) {
          return http.Response(_corpsRapports(), 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200,
            headers: {'content-type': 'application/json'});
      });
      final rapport = await http.runWithClient(
          () => IaMemoryService.instance.relancerRecuperationPMU(),
          () => client);

      final p = _pronosticDe(cle);
      debugPrint('D1-6 arrivee=${p!.arriveeReelle} '
          'cotes=${p.cotesPmuParNumero} urls=${urls.length} '
          'recuperes=${rapport['recuperes']}');

      // ── L'APPEL HTTP AUX RAPPORTS EST CONSERVÉ ──────────────────────────
      expect(urls.where((u) => u.path.contains('rapports-definitifs')),
          hasLength(1),
          reason: 'l\'appel aux rapports PMU doit être conservé : il porte '
              'les cotes');

      // ── LES COTES SONT PRÉSERVÉES ───────────────────────────────────────
      expect(p.cotesPmuParNumero['7'], equals(3.5),
          reason: 'la cote du n°7 (350/100) doit être enregistrée');
      expect(p.cotesPmuParNumero, isNotEmpty,
          reason: 'les cotes PMU ne doivent pas être perdues');

      // ── L'ARRIVÉE, ELLE, VIENT DE L0 ────────────────────────────────────
      expect(p.arriveeReelle, equals(<int>[1, 9, 2, 4, 7]),
          reason: 'l\'arrivée vient de L0, pas des rapports');
      expect(rapport['enregistresDepuisL0'], 1);
    });

    // ═════════════════════════════════════════════════════════════════════
    //  D1-7 — RÉSULTAT DÉJÀ ENREGISTRÉ → JAMAIS RÉÉCRIT
    // ═════════════════════════════════════════════════════════════════════
    test('D1-7 un résultat déjà enregistré n\'est jamais réécrit', () async {
      final dep = DateTime.now().subtract(const Duration(days: 10));
      final j = _fmt(dep);
      final dejaResolu = 'R8C1_$j';
      final nonResolu = 'R8C2_$j';

      await _reset(pronostics: [
        _pronostic(
            cle: dejaResolu,
            date: dep,
            resolu: true,
            arrivee: const <int>[5, 6, 3]),
        _pronostic(cle: nonResolu, date: dep),
      ]);

      // L0 propose une arrivée DIFFÉRENTE pour la course déjà résolue.
      await _semerL0(dejaResolu, <List<int>>[
        <int>[1], <int>[2], <int>[3]
      ]);
      await _semerL0(nonResolu, <List<int>>[
        <int>[9], <int>[8], <int>[7]
      ]);

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      final pd = _pronosticDe(dejaResolu);
      final pn = _pronosticDe(nonResolu);
      debugPrint('D1-7 dejaResolu=${pd?.arriveeReelle} '
          'nonResolu=${pn?.arriveeReelle} total=${rapport['total']}');

      expect(pd!.arriveeReelle, equals(<int>[5, 6, 3]),
          reason: 'un résultat déjà enregistré ne doit JAMAIS être écrasé, '
              'même si L0 propose autre chose');
      expect(rapport['total'], 1,
          reason: 'TÉMOIN : la course déjà résolue n\'est même pas '
              'sélectionnée par P3');
      expect(pn!.arriveeReelle, equals(<int>[9, 8, 7]),
          reason: 'TÉMOIN INVERSE : la course non résolue, elle, est bien '
              'enregistrée — le test ne mesure pas une inaction globale');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  D1-8 — RATTRAPAGE HISTORIQUE : J-7 ET DATES PLUS ANCIENNES
    // ═════════════════════════════════════════════════════════════════════
    test('D1-8 J-7 et journées plus anciennes restent rattrapables', () async {
      // Dates DANS la fenêtre de rétention de 90 jours : la purge
      // (`_purgerVieuxPronostics`, l.1128) n'est pas modifiée et ne doit pas
      // fausser la mesure.
      final maintenant = DateTime.now();
      final aujourdHui =
          DateTime(maintenant.year, maintenant.month, maintenant.day);
      final d7 = aujourdHui.subtract(const Duration(days: 7));
      final d20 = aujourdHui.subtract(const Duration(days: 20));
      final d40 = aujourdHui.subtract(const Duration(days: 40));

      for (final d in <DateTime>[d7, d20, d40]) {
        expect(maintenant.difference(d).inDays, lessThan(90),
            reason: 'TÉMOIN : $d doit rester dans la fenêtre des 90 jours');
      }

      await _reset(pronostics: [
        _pronostic(cle: 'R9C1_${_fmt(d7)}', date: d7),
        _pronostic(cle: 'R9C2_${_fmt(d20)}', date: d20),
        _pronostic(cle: 'R9C3_${_fmt(d40)}', date: d40),
      ]);

      final rec = _Enregistreur()
        ..capturerL0 = ((DateTime d) async {
          final jj = _fmt(d);
          for (final p in IaMemoryService.instance.pronostics) {
            if (p.courseKey.endsWith('_$jj')) {
              await _semerL0(p.courseKey, <List<int>>[
                <int>[6], <int>[5], <int>[4]
              ]);
            }
          }
        });
      IaMemoryService.instance.sourceProgrammeHistorique = rec.appeler;

      // ── Exécution 1 : la plus ancienne (J-40) ────────────────────────────
      final r1 = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());
      debugPrint('D1-8 exec1 journee=${r1['journeeChargee']} '
          'restantes=${r1['journeesRestantes']}');
      expect(r1['journeeChargee'], _jour(d40),
          reason: 'la journée la plus ancienne d\'abord');
      expect(_pronosticDe('R9C1_${_fmt(d7)}')!.resultatsReels, isFalse,
          reason: 'TÉMOIN : la journée J-7 n\'a pas encore été traitée');

      // ── Exécution 2 : J-20 ───────────────────────────────────────────────
      rec.appels.clear();
      rec.jours.clear();
      final r2 = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());
      debugPrint('D1-8 exec2 journee=${r2['journeeChargee']} '
          'restantes=${r2['journeesRestantes']}');
      expect(r2['journeeChargee'], _jour(d20),
          reason: 'après couverture de J-40, c\'est J-20 qui doit être chargée');

      // ── Exécution 3 : J-7 enfin atteint ──────────────────────────────────
      rec.appels.clear();
      rec.jours.clear();
      final r3 = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());
      debugPrint('D1-8 exec3 journee=${r3['journeeChargee']} '
          'restantes=${r3['journeesRestantes']}');
      expect(r3['journeeChargee'], _jour(d7),
          reason: 'J-7 doit FINIR par être rattrapée : aucune exclusion '
              'définitive');

      // ── Les trois courses sont désormais résolues depuis L0 ──────────────
      for (final cle in <String>[
        'R9C1_${_fmt(d7)}',
        'R9C2_${_fmt(d20)}',
        'R9C3_${_fmt(d40)}',
      ]) {
        final p = _pronosticDe(cle);
        expect(p, isNotNull, reason: 'TÉMOIN : $cle est toujours présent');
        expect(p!.arriveeReelle, equals(<int>[6, 5, 4]),
            reason: '$cle doit être résolue par L0');
        expect(p.resultatsReels, isTrue);
      }
    });

    // ═════════════════════════════════════════════════════════════════════
    //  D1-9 — P1 ET P2 PRIVILÉGIENT L0 (MIS À JOUR A6)
    //
    //  ⚠️ ATTENTE HISTORIQUE RENVERSÉE, SUR ARBITRAGE EXPLICITE.
    //  Cette section vérifiait auparavant l'INVERSE : « P1 et P2 reconstruisent
    //  toujours depuis les rapports PMU, jamais depuis L0 ». C'était exact
    //  avant A6, et c'est désormais faux : le mandat A6 impose « L0
    //  prioritaire » sur les cinq chemins (P1, P2, P3, P4, P5) et interdit
    //  d'écraser une égalité officielle connue par un classement PMU aplati.
    //
    //  Ce qui est vérifié ici, et qui n'existait dans aucun test :
    //   • L0 est bien la source RETENUE, alors qu'un ordre PMU différent est
    //     disponible dans les mêmes rapports (donc le repli PMU n'est pas
    //     utilisé quand L0 existe) ;
    //   • l'ordre PMU concurrent n'est PAS enregistré (témoin négatif).
    //
    //  Aucun test n'est supprimé, aucune assertion n'est neutralisée : la
    //  raison de chaque assertion est explicitée.
    // ═════════════════════════════════════════════════════════════════════
    test('D1-9 P2 privilégie l\'arrivée officielle L0 (repli PMU non utilisé)',
        () async {
      final dep = DateTime.now().subtract(const Duration(minutes: 90));
      final cle = 'R1C901_${_fmt(dep)}';

      await _reset();

      // L0 propose un ordre volontairement différent du PMU simulé
      // (le PMU des tests rend 7-4-2-9-1).
      await _semerL0(cle, <List<int>>[
        <int>[1], <int>[9], <int>[2]
      ]);

      final arrivee = await _avecPmu<
          List<int>?>(
          () => IaMemoryService.instance
              .fetchArriveeDirecte(courseKey: cle, heureDepart: dep));

      debugPrint('D1-9 P2 arrivee=$arrivee '
          'l0=${ArriveeOfficielleService.instance.arrivee(cle)}');

      expect(arrivee, isNotNull,
          reason: 'TÉMOIN : P2 a bien produit un résultat');
      expect(arrivee, equals(<int>[1, 9, 2]),
          reason: 'A6 §4 : L0 est PRIORITAIRE. P2 doit rendre l\'arrivée '
              'officielle L0 (1-9-2) et non le classement reconstruit '
              'depuis les rapports PMU (7-4-2-9-1)');
      expect(arrivee, isNot(equals(<int>[7, 4, 2, 9, 1])),
          reason: 'A6 §4 : le repli PMU ne doit PAS être utilisé quand L0 '
              'existe — sinon une égalité officielle connue pourrait être '
              'écrasée par un classement plat');
    });

    test('D1-9b P1 analyseJourneeComplete privilégie l\'arrivée officielle L0',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 11));
      final cle = 'R1C902_${_fmt(dep)}';

      await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);

      await _semerL0(cle, <List<int>>[
        <int>[1], <int>[9], <int>[2]
      ]);

      await _avecPmu(
          () => IaMemoryService.instance.analyseJourneeComplete(date: dep));

      final p = _pronosticDe(cle);
      debugPrint('D1-9b P1 arrivee=${p?.arriveeReelle} '
          'l0=${ArriveeOfficielleService.instance.arrivee(cle)}');

      expect(p!.arriveeReelle, equals(<int>[1, 9, 2]),
          reason: 'A6 §4 : P1 doit enregistrer l\'arrivée officielle L0 '
              '(1-9-2), et non le classement reconstruit depuis les '
              'rapports PMU (7-4-2-9-1)');
      expect(p.arriveeReelle, isNot(equals(<int>[7, 4, 2, 9, 1])),
          reason: 'A6 §4 : P1 ne doit pas utiliser le repli PMU quand L0 '
              'existe');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  D1-10 — INVARIANT : tout enregistrement vient de L0
    // ═════════════════════════════════════════════════════════════════════
    test('D1-10 enregistresDepuisL0 égale toujours recuperes', () async {
      final dep = DateTime.now().subtract(const Duration(days: 12));
      final j = _fmt(dep);

      await _reset(pronostics: [
        _pronostic(cle: 'R2C1_$j', date: dep),
        _pronostic(cle: 'R2C2_$j', date: dep),
        _pronostic(cle: 'R2C3_$j', date: dep),
      ]);

      await _semerL0('R2C1_$j', <List<int>>[<int>[1]]);          // exploitable
      await _semerL0('R2C2_$j', <List<int>>[<int>[2, 3], <int>[4]]); // ex æquo
      // R2C3 : pas de L0 → différée

      final rapport = await _avecPmu(
          () => IaMemoryService.instance.relancerRecuperationPMU());

      debugPrint('D1-10 recuperes=${rapport['recuperes']} '
          'depuisL0=${rapport['enregistresDepuisL0']} '
          'exAequo=${rapport['exAequoDifferes']} '
          'introuvables=${rapport['introuvables']} '
          'total=${rapport['total']}');

      expect(rapport['total'], 3);
      expect(rapport['recuperes'], 1, reason: 'une seule course exploitable');
      expect(rapport['enregistresDepuisL0'], rapport['recuperes'],
          reason: 'INVARIANT : il n\'existe plus aucun autre chemin '
              'd\'enregistrement dans P3');
      expect(rapport['exAequoDifferes'], 1);
      expect(rapport['introuvables'], 1);
      expect(
        (rapport['recuperes'] as int) +
            (rapport['exAequoDifferes'] as int) +
            (rapport['introuvables'] as int),
        rapport['total'],
        reason: 'CHAQUE course sélectionnée tombe dans exactement une des '
            'trois catégories : enregistrée, ex æquo différé, L0 absent',
      );
    });
  });
}
