// ═══════════════════════════════════════════════════════════════════════════
//  A6 n° 2-b-1 — MESURE DE COUVERTURE L0 DANS P3
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT — AUCUNE MODIFICATION DE PRODUCTION.
//
//  OBJET : prouver que la lecture non intrusive de L0 ajoutée dans
//  `IaMemoryService.relancerRecuperationPMU()` (P3) COMPTE correctement, et
//  qu'elle ne change RIEN au comportement de récupération.
//
//  ── AVERTISSEMENT DE PORTÉE, EXIGÉ PAR LE MANDAT ─────────────────────────
//  Ces tests sont SIMULÉS. Ils prouvent le FONCTIONNEMENT des compteurs :
//  « si L0 contient cette course, le compteur augmente ; sinon, l'autre ».
//  Ils NE MESURENT PAS le taux de couverture L0 réel des utilisateurs, et
//  aucun taux réel n'est affirmé nulle part dans ce fichier. Un taux réel
//  ne s'obtient que par une exécution sur des données réelles.
//
//  ── CE QUI EST PROUVÉ, TEST PAR TEST ─────────────────────────────────────
//    B1-1  L0 contient la course      → `l0Present` +1, `l0Absent` 0
//    B1-2  L0 ne contient pas         → `l0Absent` +1, `l0Present` 0
//    B1-3  plusieurs courses mêlées   → compteurs EXACTS, sans double
//                                       comptage, invariant vérifié
//    B1-4  date incohérente           → comptée et JOURNALISÉE, mais la
//                                       date utilisée dans l'URL reste
//                                       celle de `datePronostic` (aucune
//                                       correction automatique)
//    B1-5  L0 présente une arrivée    → l'arrivée ENREGISTRÉE est celle des
//          DIFFÉRENTE de celle du PMU    rapports PMU : L0 n'est jamais
//                                       substituée (arguments d'
//                                       `enregistrerResultat()` inchangés)
//    B1-6  branche vide               → les nouvelles clés existent et
//                                       valent 0 (compatibilité)
//
//  ── MÉTHODE ──────────────────────────────────────────────────────────────
//  Aucun parseur n'est recopié : les tests passent par le POINT D'ENTRÉE
//  PUBLIC de production `relancerRecuperationPMU()`. Le réseau est intercepté
//  par `http.runWithClient()` + `MockClient` : aucun appel réel vers
//  turfinfo.api.pmu.fr. Aucun gradient n'est appelé directement, aucune
//  pondération n'est lue ni écrite.
//
//  ── ISOLATION ────────────────────────────────────────────────────────────
//  `IaMemoryService` et `ArriveeOfficielleService` sont des SINGLETONS.
//  Trois précautions, toutes fondées sur des mécanismes EXISTANTS :
//    1. `SharedPreferences.setMockInitialValues(...)` + `resetStatic()`
//       réécrivent le magasin vu par les deux services ;
//    2. `IaMemoryService.instance.recharger()` (l.1795) remet `_loaded=false`
//       puis relit le disque : aucun pronostic d'un autre fichier ne survit ;
//    3. `ArriveeOfficielleService.instance.viderMemoireSeulement()`
//       (arrivee_officielle_service.dart:1286-1296, `@visibleForTesting`)
//       vide `_shards`/`_enAttente` : aucune arrivée héritée ne subsiste.
//  Les `courseKey` sont de plus UNIQUES par test : `_arriveeCache`
//  (ia_memory_service.dart) n'est pas vidable sans hook et pourrait sinon
//  répondre à la place du parseur.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ─────────────────────────── Formatage ─────────────────────────────────────

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

// ─────────────────────── Faux serveur PMU ──────────────────────────────────

/// Corps au format RÉEL de l'API : racine = **List** de blocs.
///
/// Seuls `E_SIMPLE_GAGNANT` et `E_QUINTE_ORDRE` sont émis : le premier fournit
/// le gagnant, le second la combinaison ordonnée complète. P3 dédoublonne
/// (l.1246), l'arrivée retenue est donc exactement [7,4,2,9,1].
String _corpsPmu({String gagnant = '7', String quinte = '7-4-2-9-1'}) =>
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

/// Exécute [action] avec un réseau PMU simulé, en capturant les URL demandées.
Future<T> _avecPmu<T>(
  Future<T> Function() action, {
  required List<Uri> urls,
  String? corps,
}) {
  final client = MockClient((request) async {
    urls.add(request.url);
    if (request.url.path.contains('rapports-definitifs')) {
      return http.Response(corps ?? _corpsPmu(), 200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response('{}', 200,
        headers: {'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
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

/// Scores IA : favori = « 4 ».
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

/// Pronostic passé (donc sélectionnable par P3 : `diff <= -30`) et NON résolu.
IaPronostic _pronostic({
  required String cle,
  required DateTime date,
  String nom = 'PRIX A6',
}) =>
    IaPronostic(
      courseKey: cle,
      nomCourse: nom,
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

/// Repart d'un état SIMULÉ vierge pour les DEUX singletons.
Future<void> _reset({
  List<IaPronostic> pronostics = const <IaPronostic>[],
}) async {
  SharedPreferences.setMockInitialValues(
      _prefs(pronostics: pronostics.map((p) => json.encode(p.toJson())).toList()));
  SharedPreferences.resetStatic();
  ArriveeOfficielleService.instance.viderMemoireSeulement();
  await IaMemoryService.instance.recharger();
}

/// Écrit une arrivée officielle dans L0 par le chemin d'écriture réel.
///
/// `enregistrer()` → `enregistrerGroupe()` → `_ecrireMois()`, qui renseigne
/// `_shards[mois]` : l'entrée est ensuite lisible par `arrivee()` sans aucun
/// rechargement. Le succès est ASSERTÉ pour que le test ne puisse pas passer
/// sur une écriture refusée (ce qui rendrait la mesure vide).
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
  expect(e, isNotNull, reason: 'TÉMOIN : la fixture L0 doit être acceptée');
  final res = await ArriveeOfficielleService.instance.enregistrer(e!);
  expect(res.succes, isTrue, reason: 'TÉMOIN : l\'écriture L0 doit réussir');
  // TÉMOIN DE LECTURE : l'entrée est bien visible AVANT de lancer P3.
  expect(ArriveeOfficielleService.instance.arrivee(cle), equals(rangs),
      reason: 'TÉMOIN : L0 doit rendre ce qui vient d\'être écrit');
}

IaPronostic? _pronosticDe(String cle) {
  final l = IaMemoryService.instance.pronostics
      .where((p) => p.courseKey == cle)
      .toList();
  return l.isEmpty ? null : l.first;
}

void main() {
  group('A6 n° 2-b-1 — mesure L0 dans P3', () {
    // ═════════════════════════════════════════════════════════════════════
    //  B1-1 — L0 CONTIENT la course : `l0Present` augmente
    // ═════════════════════════════════════════════════════════════════════
    test('B1-1 L0 présente → l0Present=1, l0Absent=0', () async {
      final dep = DateTime.now().subtract(const Duration(days: 2));
      final cle = 'R1C1_${_fmt(dep)}';

      await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);

      // L0 est alimenté AVANT l'appel : c'est la situation mesurée.
      await _semerL0(cle, <List<int>>[
        <int>[4, 7], <int>[2]
      ]);

      final urls = <Uri>[];
      final rapport = await _avecPmu(
        () => IaMemoryService.instance.relancerRecuperationPMU(),
        urls: urls,
      );

      debugPrint('B1-1 rapport l0Present=${rapport['l0Present']} '
          'l0Absent=${rapport['l0Absent']} '
          'incoherencesDate=${rapport['incoherencesDate']} '
          'total=${rapport['total']}');

      expect(rapport['total'], 1, reason: 'TÉMOIN : une course sélectionnée');
      expect(rapport['l0Present'], 1,
          reason: 'L0 contenant la course, le compteur PRÉSENT doit valoir 1');
      expect(rapport['l0Absent'], 0,
          reason: 'le compteur ABSENT ne doit pas bouger');
      expect(rapport['incoherencesDate'], 0,
          reason: 'clé et datePronostic concordent : aucune incohérence');
      expect(urls, isNotEmpty,
          reason: 'TÉMOIN : P3 a bien émis sa requête (mesure non vide)');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  B1-2 — L0 NE CONTIENT PAS la course : `l0Absent` augmente
    // ═════════════════════════════════════════════════════════════════════
    test('B1-2 L0 absente → l0Absent=1, l0Present=0', () async {
      final dep = DateTime.now().subtract(const Duration(days: 2));
      final cle = 'R2C1_${_fmt(dep)}';

      await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);

      // TÉMOIN DE NON-VACUITÉ : L0 est VIDE mais on prouve qu'il est
      // interrogeable. Sans ce témoin, `l0Absent=1` pourrait simplement
      // signifier « service jamais chargé », et ne rien démontrer.
      expect(ArriveeOfficielleService.instance.nbEntrees, 0,
          reason: 'TÉMOIN : L0 est réellement vide avant la mesure');
      expect(ArriveeOfficielleService.instance.arrivee(cle), isNull,
          reason: 'TÉMOIN : la clé rend bien null sur un L0 vide');
      final urls = <Uri>[];
      final rapport = await _avecPmu(
        () => IaMemoryService.instance.relancerRecuperationPMU(),
        urls: urls,
      );

      debugPrint('B1-2 rapport l0Present=${rapport['l0Present']} '
          'l0Absent=${rapport['l0Absent']} total=${rapport['total']}');

      expect(rapport['total'], 1, reason: 'TÉMOIN : une course sélectionnée');
      expect(rapport['l0Absent'], 1,
          reason: 'L0 ne contenant pas la course, ABSENT doit valoir 1');
      expect(rapport['l0Present'], 0,
          reason: 'le compteur PRÉSENT ne doit pas bouger');
      // ⚠️ ASSERTION ADAPTÉE — A6 n° 2-b-3.
      // ANCIENNE ASSERTION : `recuperes == 1`, au motif que « la récupération
      // PMU a bien eu lieu ». Elle supposait que P3 enregistrait l'arrivée
      // reconstruite depuis les rapports PMU — comportement que 2-b-3 interdit
      // explicitement (« ne jamais enregistrer une arrivée reconstruite depuis
      // les rapports PMU lorsque L0 est absent »).
      // NOUVELLE ATTENTE : la course est DIFFÉRÉE, donc `recuperes == 0` et
      // `introuvables == 1`. Le pronostic doit rester non résolu, pour être
      // réessayable.
      expect(rapport['recuperes'], 0,
          reason: 'L0 absente : AUCUN résultat ne doit être enregistré');
      expect(rapport['introuvables'], 1,
          reason: 'la course doit être comptée comme DIFFÉRÉE, pas silencieusement '
              'ignorée');
      expect(rapport['enregistresDepuisL0'], 0,
          reason: 'aucun enregistrement, donc aucun enregistrement depuis L0');
      final p = _pronosticDe(cle);
      expect(p!.resultatsReels, isFalse,
          reason: 'le pronostic doit rester NON résolu — aucun marquage '
              'définitif, donc réessai possible');
      expect(p.arriveeReelle, isNull,
          reason: 'aucune arrivée PMU ne doit être enregistrée en l\'absence '
              'de L0');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  B1-3 — PLUSIEURS COURSES : compteurs exacts, aucun double comptage
    // ═════════════════════════════════════════════════════════════════════
    test('B1-3 plusieurs courses → compteurs exacts, sans double comptage',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 3));
      final j = _fmt(dep);

      // 3 courses dans L0, 2 hors de L0 → attendu 3 / 2, total 5.
      final dansL0 = <String>['R1C1_$j', 'R1C2_$j', 'R2C1_$j'];
      final horsL0 = <String>['R2C2_$j', 'R3C1_$j'];

      await _reset(pronostics: [
        for (final c in dansL0) _pronostic(cle: c, date: dep),
        for (final c in horsL0) _pronostic(cle: c, date: dep),
      ]);

      // Arrivées DISTINCTES, pour qu'aucune ne puisse être confondue.
      await _semerL0(dansL0[0], <List<int>>[
        <int>[1]
      ]);
      await _semerL0(dansL0[1], <List<int>>[
        <int>[2], <int>[3]
      ]);
      await _semerL0(dansL0[2], <List<int>>[
        <int>[5]
      ]);

      expect(ArriveeOfficielleService.instance.nbEntrees, 3,
          reason: 'TÉMOIN : L0 contient exactement 3 entrées');

      final urls = <Uri>[];
      final rapport = await _avecPmu(
        () => IaMemoryService.instance.relancerRecuperationPMU(),
        urls: urls,
      );

      debugPrint('B1-3 rapport total=${rapport['total']} '
          'l0Present=${rapport['l0Present']} '
          'l0Absent=${rapport['l0Absent']} '
          'incoherencesDate=${rapport['incoherencesDate']}');

      expect(rapport['total'], 5, reason: 'TÉMOIN : 5 courses sélectionnées');
      expect(rapport['l0Present'], 3,
          reason: 'exactement 3 courses sont dans L0 — un double comptage '
              'donnerait 6, un oubli donnerait moins de 3');
      expect(rapport['l0Absent'], 2,
          reason: 'exactement 2 courses sont hors de L0');

      // INVARIANT : chaque course sélectionnée est comptée UNE ET UNE SEULE
      // fois. C'est la formulation directe de « sans double comptage ».
      expect(
        (rapport['l0Present'] as int) + (rapport['l0Absent'] as int),
        rapport['total'],
        reason: 'l0Present + l0Absent doit égaler total : toute course est '
            'comptée exactement une fois',
      );

      // ⚠️ ASSERTION ADAPTÉE — A6 n° 2-b-3.
      // ANCIENNE ASSERTION : `recuperes == 5`, « les 5 courses ont bien été
      // récupérées via PMU ». Elle consacrait l'enregistrement d'arrivées
      // reconstruites depuis les rapports pour les 2 courses HORS de L0 —
      // désormais interdit.
      // NOUVELLE ATTENTE : seules les 3 courses couvertes par L0 sont
      // enregistrées ; les 2 autres sont DIFFÉRÉES. Le total des trois
      // catégories doit recomposer exactement les 5 courses sélectionnées.
      expect(rapport['recuperes'], 3,
          reason: 'seules les 3 courses présentes dans L0 peuvent être '
              'enregistrées');
      expect(rapport['enregistresDepuisL0'], 3,
          reason: 'ces 3 enregistrements viennent tous de L0');
      expect(rapport['introuvables'], 2,
          reason: 'les 2 courses hors de L0 sont DIFFÉRÉES, pas inventées');
      expect(
        (rapport['recuperes'] as int) + (rapport['introuvables'] as int),
        rapport['total'],
        reason: 'chaque course sélectionnée est soit enregistrée, soit '
            'différée — aucune n\'est perdue',
      );
      // Les 2 courses hors L0 restent non résolues : réessai possible.
      for (final c in horsL0) {
        final p = _pronosticDe(c);
        expect(p, isNotNull, reason: 'TÉMOIN : $c existe toujours');
        expect(p!.resultatsReels, isFalse,
            reason: '$c, sans L0, ne doit pas être marquée résolue');
        expect(p.arriveeReelle, isNull,
            reason: '$c ne doit recevoir aucune arrivée reconstruite');
      }
    });

    // ═════════════════════════════════════════════════════════════════════
    //  B1-4 — DATE INCOHÉRENTE : signalée, JAMAIS corrigée
    // ═════════════════════════════════════════════════════════════════════
    test('B1-4 date incohérente → diagnostic seul, date de l\'URL inchangée',
        () async {
      // La clé porte le 01/01/2025, `datePronostic` porte le 15/01/2025.
      final datePronostic = DateTime(2025, 1, 15, 14, 0);
      const cle = 'R5C2_01012025';
      // La date doit être PASSÉE pour que P3 sélectionne la course.
      expect(datePronostic.isBefore(DateTime.now()), isTrue,
          reason: 'TÉMOIN : la course est bien passée');

      await _reset(pronostics: [_pronostic(cle: cle, date: datePronostic)]);

      // TÉMOIN DE CAUSE : les deux dates diffèrent réellement.
      expect(_fmt(datePronostic), isNot(equals('01012025')),
          reason: 'TÉMOIN : l\'incohérence existe bien dans la fixture');

      final urls = <Uri>[];
      final rapport = await _avecPmu(
        () => IaMemoryService.instance.relancerRecuperationPMU(),
        urls: urls,
      );

      debugPrint('B1-4 rapport incoherencesDate=${rapport['incoherencesDate']} '
          'urls=${urls.map((u) => u.path).toList()}');

      expect(rapport['incoherencesDate'], 1,
          reason: 'l\'incohérence doit être COMPTÉE');

      final details = rapport['details'] as List<String>;
      final lignesAlerte = details.where((d) => d.contains('NON corrigé'));
      expect(lignesAlerte, hasLength(1),
          reason: 'l\'incohérence doit être JOURNALISÉE, une fois');
      expect(lignesAlerte.first, contains('R5C2_01012025'),
          reason: 'la ligne doit nommer la course concernée');
      expect(lignesAlerte.first, contains('2025-01-15'),
          reason: 'la ligne doit porter la date de datePronostic');
      expect(lignesAlerte.first, contains('2025-01-01'),
          reason: 'la ligne doit porter la date lue dans la clé');

      // ══ PREUVE D'ABSENCE DE CORRECTION AUTOMATIQUE ══
      // P3 construit sa date d'URL depuis `datePronostic` (et non depuis la
      // clé). Si une « correction » avait été introduite, l'URL porterait
      // 01012025. Elle doit porter 15012025.
      expect(urls, hasLength(1), reason: 'TÉMOIN : une seule requête');
      expect(urls.single.path, contains('/programme/15012025/'),
          reason: 'la date utilisée doit rester celle de datePronostic : '
              'aucune correction automatique n\'est autorisée');
      expect(urls.single.path, isNot(contains('/programme/01012025/')),
          reason: 'la date de la clé ne doit JAMAIS être substituée');

      // Et la ligne de synthèse rend compte du compteur.
      expect(details.first, contains('1 incohérence(s) de date'),
          reason: 'la synthèse L0 doit exposer le compteur d\'incohérences');
    });

    test('B1-4b date cohérente → aucune incohérence signalée', () async {
      final dep = DateTime.now().subtract(const Duration(days: 4));
      final cle = 'R6C3_${_fmt(dep)}';

      await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);

      final urls = <Uri>[];
      final rapport = await _avecPmu(
        () => IaMemoryService.instance.relancerRecuperationPMU(),
        urls: urls,
      );

      debugPrint('B1-4b incoherencesDate=${rapport['incoherencesDate']}');

      expect(rapport['incoherencesDate'], 0,
          reason: 'TÉMOIN INVERSE : une clé cohérente ne produit aucune '
              'incohérence — sans cela, le compteur de B1-4 pourrait être '
              'toujours incrémenté et ne rien mesurer');
      final details = rapport['details'] as List<String>;
      expect(details.where((d) => d.contains('NON corrigé')), isEmpty);
    });

    // ═════════════════════════════════════════════════════════════════════
    //  B1-5 — L0 DIFFÉRENTE DU PMU : L0 EST la source de l'arrivée
    //
    //  ⚠️ ASSERTION INVERSÉE — A6 n° 2-b-3.
    //
    //  ANCIENNE ATTENTE : « l'arrivée enregistrée reste celle du PMU ».
    //  Elle était correcte sous 2-b-1, où la mesure L0 était purement
    //  descriptive et où P3 enregistrait la reconstruction PMU.
    //
    //  NOUVELLE ATTENTE : l'arrivée enregistrée est celle de L0. C'est
    //  l'exact objet de 2-b-3 (« utiliser exclusivement les arrivées
    //  officielles L0 »). Le scénario — L0 et PMU volontairement divergents —
    //  est CONSERVÉ à l'identique : il est même devenu plus discriminant,
    //  puisqu'il prouve maintenant que la divergence tourne dans le bon sens.
    // ═════════════════════════════════════════════════════════════════════
    test('B1-5 L0 divergente du PMU → l\'arrivée enregistrée est celle de L0',
        () async {
      final dep = DateTime.now().subtract(const Duration(days: 5));
      final cle = 'R7C4_${_fmt(dep)}';

      await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);

      // L0 porte une arrivée VOLONTAIREMENT DIFFÉRENTE de celle du PMU.
      const arriveeL0 = <List<int>>[
        <int>[3], <int>[8], <int>[5]
      ];
      await _semerL0(cle, arriveeL0);

      final urls = <Uri>[];
      final rapport = await _avecPmu(
        () => IaMemoryService.instance.relancerRecuperationPMU(),
        urls: urls,
        corps: _corpsPmu(gagnant: '7', quinte: '7-4-2-9-1'),
      );

      expect(rapport['l0Present'], 1,
          reason: 'TÉMOIN : L0 contient bien la course (mesure active)');
      expect(rapport['recuperes'], 1,
          reason: 'TÉMOIN : L0 fournit une arrivée exploitable et elle est '
              'retenue');
      expect(urls, isNotEmpty,
          reason: 'TÉMOIN : l\'appel aux rapports PMU est CONSERVÉ — il porte '
              'les cotes');

      final p = _pronosticDe(cle);
      expect(p, isNotNull, reason: 'TÉMOIN : le pronostic existe toujours');
      debugPrint('B1-5 arriveeEnregistree=${p!.arriveeReelle} '
          'l0=${ArriveeOfficielleService.instance.arrivee(cle)}');

      // ══ PREUVE DÉCISIVE : le résultat enregistré vient de L0 ══
      expect(p.arriveeReelle, equals(<int>[3, 8, 5]),
          reason: 'l\'arrivée enregistrée doit être celle de L0 : c\'est la '
              'seule source autorisée par A6 n° 2-b-3');
      expect(p.arriveeReelle, isNot(equals(<int>[7, 4, 2, 9, 1])),
          reason: 'l\'arrivée reconstruite depuis les rapports PMU ne doit '
              'plus être enregistrée');

      // Le résultat est bien marqué comme réel.
      expect(p.resultatsReels, isTrue,
          reason: 'TÉMOIN : le résultat a bien été enregistré');

      // L0 reste INTACT après l'appel : la lecture est pure.
      expect(ArriveeOfficielleService.instance.arrivee(cle), equals(arriveeL0),
          reason: 'L0 ne doit pas être altéré par la lecture');
    });

    // ═════════════════════════════════════════════════════════════════════
    //  B1-6 — BRANCHE VIDE : les nouvelles clés existent et valent 0
    // ═════════════════════════════════════════════════════════════════════
    test('B1-6 aucune course à relancer → clés L0 présentes et à 0', () async {
      await _reset(); // aucun pronostic : P3 sort par la branche vide

      final urls = <Uri>[];
      final rapport = await _avecPmu(
        () => IaMemoryService.instance.relancerRecuperationPMU(),
        urls: urls,
      );

      debugPrint('B1-6 rapport total=${rapport['total']} '
          'l0Present=${rapport['l0Present']} '
          'l0Absent=${rapport['l0Absent']} '
          'message=${rapport['message']}');

      expect(rapport['total'], 0, reason: 'TÉMOIN : branche vide empruntée');
      expect(urls, isEmpty, reason: 'TÉMOIN : aucune requête réseau');

      // Compatibilité : un appelant qui lit les clés les trouve TOUJOURS.
      expect(rapport.containsKey('l0Present'), isTrue);
      expect(rapport.containsKey('l0Absent'), isTrue);
      expect(rapport.containsKey('incoherencesDate'), isTrue);
      expect(rapport['l0Present'], 0);
      expect(rapport['l0Absent'], 0);
      expect(rapport['incoherencesDate'], 0);

      // Les six clés historiques sont intactes et de même type.
      expect(rapport['recuperes'], 0);
      expect(rapport['introuvables'], 0);
      expect(rapport['erreurs'], 0);
      expect(rapport['details'], isA<List<String>>());
      expect(rapport['message'], isA<String>());
    });
  });
}
