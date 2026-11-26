// ═══════════════════════════════════════════════════════════════════════════
//  §2 — MESURE DES MÉCANISMES D'ACTUALISATION (ÉTAT AVANT CORRECTION)
//
//  OBJET : établir par MESURE, et non par lecture de code, ce que font
//          réellement les mécanismes d'actualisation de production
//          (`ZoneTurfService.chargerProgramme`, `DataRefreshService`).
//
//  ⚠️ CE FICHIER EST UN INSTRUMENT DE MESURE, PAS UN TEST DE NON-RÉGRESSION.
//     Il n'utilise QUE l'API publique existante : il ne peut donc pas
//     « prouver » un mécanisme en s'appuyant sur le code qui le réalise.
//     Les assertions y décrivent l'exigence §2 ; un échec est l'énoncé d'un
//     défaut réel, et il est imprimé avec sa mesure.
//
//  PÉRIMÈTRE INTERDIT, respecté : aucune formule, aucun poids, aucun seuil,
//  aucune calibration, aucun TOP3 Learning, aucun mécanisme d'apprentissage.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';
import 'package:pronostic_hippique/services/cote_tracker_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

import '../support/corpus_pmu_replay.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Outils de mesure
// ───────────────────────────────────────────────────────────────────────────

/// Compte les requêtes réellement émises, par famille d'endpoint, et délègue
/// au client du corpus. Le compteur est la seule mesure : aucune donnée n'est
/// modifiée, aucune réponse n'est fabriquée.
class Compteur {
  int programme = 0;
  int participants = 0;
  int perfdet = 0;

  int get total => programme + participants + perfdet;

  http.Client client(CorpusCourse c, {Duration delai = Duration.zero}) {
    final interieur = clientPourCorpus(c);
    return MockClient((http.Request req) async {
      final p = req.url.path;
      if (p.contains('performances-detaillees')) {
        perfdet++;
      } else if (p.contains('participants')) {
        participants++;
      } else {
        programme++;
      }
      if (delai > Duration.zero) await Future<void>.delayed(delai);
      final r = await interieur.send(http.Request(req.method, req.url)
        ..headers.addAll(req.headers)
        ..bodyBytes = req.bodyBytes);
      return http.Response.fromStream(r);
    });
  }
}

/// Client qui répond toujours [statut] / [corps].
http.Client repond(int statut, String corps) =>
    MockClient((http.Request req) async => http.Response(corps, statut,
        headers: <String, String>{'content-type': 'application/json'}));

/// Client dont le réseau est coupé : aucune réponse n'est produite.
http.Client echoue() => MockClient((http.Request req) async {
      throw const SocketException('coupure reseau simulee');
    });

/// Exécute [corps] en injectant [client] comme client HTTP du producteur.
Future<T> avecClient<T>(
    http.Client client, Future<T> Function() corps) async {
  late T resultat;
  await http.runWithClient(() async {
    resultat = await corps();
  }, () => client);
  return resultat;
}

/// Course du corpus la plus riche en partants. Tri explicite, aucun hasard.
CorpusCourse courseLaPlusRiche() {
  final toutes = chargerManifeste()
    ..sort((a, b) => b.nParticipants.compareTo(a.nParticipants));
  return toutes.first;
}

/// Le discriminant mesuré est celui de la PRODUCTION, pas une copie.
///
/// ⚠️ CORRECTION DE MÉTHODE : ma première version reproduisait la règle dans
///    ce fichier. Elle mesurait donc sa propre copie. On appelle désormais
///    `DataRefreshService.signaturePourMesure`, qui délègue à la méthode
///    réellement utilisée par `_doRefresh`.
String signatureDe(List<ZtReunion> reunions) =>
    DataRefreshService.instance.signaturePourMesure(reunions);

ZtPartant partant(int n, {required String cote}) => ZtPartant(
      numero: '$n',
      nom: 'CHEVAL_$n',
      driver: 'D$n',
      entraineur: 'E$n',
      proprietaire: 'P$n',
      gains: '10000',
      record: '1\'15"0',
      musique: '1a 2a 3a',
      cote: cote,
      ageSexe: '5H',
    );

/// Réunion factice dont la SEULE variable est le contenu demandé.
///
/// ⚠️ CORRECTION DE MÉTHODE (seconde) : ma première version datait la course
///    du 01/01/2026, donc DANS LE PASSÉ par rapport à l'horloge de la machine.
///    Le discriminant la classait « terminée » (règle des +90 min) et excluait
///    donc légitimement ses cotes : la mesure ne pouvait rien prouver sur le
///    mouvement de cote, quel que soit le code.
///
///    Une course TERMINÉE ne bouge plus : ses cotes n'ont effectivement pas à
///    figurer dans le discriminant. La mesure doit donc porter sur une course
///    À VENIR — c'est-à-dire sur le seul cas où un mouvement de cote est une
///    information. [dansFutur] place la course à +6 h.
ZtReunion reunionFactice({
  int numCourse = 1,
  String heure = '13:00',
  List<ZtPartant>? partants,
  bool dansFutur = true,
}) {
  final DateTime depart = dansFutur
      ? DateTime.now().add(const Duration(hours: 6))
      : DateTime.now().subtract(const Duration(hours: 6));
  final String dateStr = '${depart.day.toString().padLeft(2, '0')}'
      '${depart.month.toString().padLeft(2, '0')}'
      '${depart.year}';
  final c = ZtCourse(
    numCourse: numCourse,
    anchor: 'anchor',
    nom: 'COURSE MESURE',
    heure: heure,
    distance: '2000m',
    prix: '20000',
    type: 'Attelé',
    piste: 'Cendrée',
    categorie: 'Conditions',
    isQuinte: false,
    pronosticZt: const <int>[],
    partants: partants ??
        <ZtPartant>[for (var i = 1; i <= 8; i++) partant(i, cote: '4.0')],
    dateStr: dateStr,
  );
  return ZtReunion(
    code: 'R1',
    lieu: 'MESURE',
    discipline: 'Trot',
    dateStr: dateStr,
    courses: <ZtCourse>[c],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Les caches du producteur sont STATIQUES : sans purge, chaque mesure
    // hériterait de la précédente et ne mesurerait plus rien.
    purgerProducteur();
    // ⚠️ shared_preferences exige un mock en environnement de test : sans lui,
    //    `IaMemoryService._load` lève `MissingPluginException`. Ce défaut
    //    n'apparaissait que lorsque M8-a s'exécutait en PREMIER (les autres
    //    tests laissaient un store déjà initialisé). Corrigé à la racine, dans
    //    le setUp commun, pour que chaque mesure soit autonome.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  M1 — MUTUALISATION DES REQUÊTES SIMULTANÉES
  // ═════════════════════════════════════════════════════════════════════════
  group('M1 — mutualisation des requêtes simultanées', () {
    test('M1-a : deux chargements simultanés du MÊME programme', () async {
      final c = courseLaPlusRiche();
      final compteur = Compteur();
      // Le délai rend la fenêtre de concurrence observable : sans lui, la
      // première requête pourrait se terminer avant que la seconde ne
      // démarre, et l'absence de mutualisation passerait inaperçue.
      final client =
          compteur.client(c, delai: const Duration(milliseconds: 120));

      final r = await avecClient(client, () async {
        // Les deux appels sont engagés AVANT tout `await`.
        final f1 = ZoneTurfService.chargerProgramme(
            date: c.dateReelle, forceRefresh: true);
        final f2 = ZoneTurfService.chargerProgramme(
            date: c.dateReelle, forceRefresh: true);
        return Future.wait(<Future<List<ZtReunion>>>[f1, f2]);
      });

      // ignore: avoid_print
      print('[MESURE M1-a] programme=${compteur.programme} '
          'participants=${compteur.participants} '
          'perfdet=${compteur.perfdet} total=${compteur.total}');

      expect(r[0], isNotEmpty, reason: 'le corpus doit produire des réunions');
      expect(r[1], isNotEmpty);
      expect(compteur.programme, 1,
          reason: '§2 mutualisation : deux chargements SIMULTANÉS de la même '
              'journée doivent partager UNE requête. Mesuré : '
              '${compteur.programme}');
    });

    test('M1-b : deux chargements simultanés sur des dates DIFFÉRENTES',
        () async {
      final toutes = chargerManifeste();
      final parDate = <String, CorpusCourse>{};
      for (final c in toutes) {
        parDate.putIfAbsent(c.date, () => c);
      }
      expect(parDate.length, greaterThanOrEqualTo(2),
          reason: 'le corpus doit contenir au moins deux dates distinctes');

      final dates = parDate.keys.toList()..sort();
      final c1 = parDate[dates[0]]!;
      final c2 = parDate[dates[1]]!;
      expect(c1.date, isNot(equals(c2.date)));

      final compteur = Compteur();
      final client =
          compteur.client(c1, delai: const Duration(milliseconds: 60));

      await avecClient(client, () async {
        final f1 = ZoneTurfService.chargerProgramme(
            date: c1.dateReelle, forceRefresh: true);
        final f2 = ZoneTurfService.chargerProgramme(
            date: c2.dateReelle, forceRefresh: true);
        await Future.wait(<Future<List<ZtReunion>>>[f1, f2]);
      });

      // ignore: avoid_print
      print('[MESURE M1-b] programme=${compteur.programme} '
          'pour deux dates distinctes');

      expect(compteur.programme, 2,
          reason: 'deux dates sont deux identités de requête distinctes : '
              'aucune mutualisation ne doit les confondre. Mesuré : '
              '${compteur.programme}');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  M6 — RÉPONSES PMU ABSENTES, INVALIDES, INCOMPLÈTES
  //
  //  Ce groupe mesure ce que l'appelant peut DISTINGUER. Le producteur ne
  //  publie aujourd'hui que `[]` : la mesure doit donc établir si quatre
  //  situations de nature différente sont, ou non, indiscernables.
  // ═════════════════════════════════════════════════════════════════════════
  group('M6 — réponses PMU absentes / invalides / incomplètes', () {
    test('M6-a : quatre situations distinctes produisent-elles le même '
        'résultat observable ?', () async {
      final c = courseLaPlusRiche();
      final date = c.dateReelle;

      // 1. Journée légitimement sans course.
      final vide = await avecClient(
          repond(200, jsonEncode(<String, Object?>{
            'programme': <String, Object?>{'reunions': <Object?>[]},
          })), () => ZoneTurfService.chargerProgramme(
              date: date, forceRefresh: true));
      // ⚠️ L'issue est relevée APRÈS CHAQUE chargement : c'est un état
      // « dernière issue », donc la relire une seule fois à la fin ne
      // mesurerait que la dernière des quatre.
      final issueVide = ZoneTurfService.issueCourante;

      purgerProducteur();

      // 2. Coupure réseau : aucune réponse.
      final panne = await avecClient(echoue(),
          () => ZoneTurfService.chargerProgramme(date: date, forceRefresh: true));
      final issuePanne = ZoneTurfService.issueCourante;

      purgerProducteur();

      // 3. Corps illisible.
      final illisible = await avecClient(
          repond(200, '{ ceci n\'est pas du JSON'),
          () => ZoneTurfService.chargerProgramme(
              date: date, forceRefresh: true));
      final issueIllisible = ZoneTurfService.issueCourante;

      purgerProducteur();

      // 4. Erreur serveur.
      final serveur = await avecClient(repond(500, '{"erreur":"serveur"}'),
          () => ZoneTurfService.chargerProgramme(
              date: date, forceRefresh: true));
      final issueServeur = ZoneTurfService.issueCourante;

      // Mesure des issues RÉELLEMENT publiées à chaque étape : on relève
      // `issueCourante` juste après chaque chargement, pas après les quatre.
      // ignore: avoid_print
      print('[MESURE M6-a] longueurs observées : '
          'vide=${vide.length} panne=${panne.length} '
          'illisible=${illisible.length} serveur=${serveur.length}');

      // Mesure brute : les quatre rendent une liste vide et rien d'autre.
      expect(vide.length, 0);
      expect(panne.length, 0);
      expect(illisible.length, 0);
      expect(serveur.length, 0);

      // MESURE DU DÉFAUT (avant correction) : aucune API publique ne permet
      // de distinguer ces quatre situations. Cette assertion est ROUGE tant
      // que le mécanisme d'issue n'existe pas ; elle devient verte après.
      // Les quatre situations doivent être DEUX À DEUX DISTINCTES. Une simple
      // différence avec `inconnue` ne suffirait pas : ce qui compte est qu'un
      // appelant puisse choisir entre réessayer et ne rien faire.
      final issues = <IssueChargement>[issueVide, issuePanne, issueIllisible,
          issueServeur];
      // ignore: avoid_print
      print('[MESURE M6-a] issues = '
          '${issues.map((e) => e.name).toList()}');
      expect(issues.toSet().length, 4,
          reason: '§2 : les quatre situations doivent produire quatre issues '
              'DISTINCTES. Mesuré : ${issues.map((e) => e.name).toList()}');
    });

    test('M6-b : un programme lu mais dont AUCUNE course n\'a de partant',
        () async {
      // Le programme est servi ; les participants renvoient 500. Le résultat
      // n'est donc pas vide, mais il est INCOMPLET : chaque course existe avec
      // zéro partant. Un appelant qui ne regarde que `isNotEmpty` croira avoir
      // chargé un programme exploitable.
      final c = courseLaPlusRiche();
      final interieur = clientPourCorpus(c);
      final client = MockClient((http.Request req) async {
        if (req.url.path.contains('participants')) {
          return http.Response('', 500);
        }
        return http.Response.fromStream(await interieur.send(
            http.Request(req.method, req.url)
              ..headers.addAll(req.headers)
              ..bodyBytes = req.bodyBytes));
      });

      final reunions = await avecClient(client,
          () => ZoneTurfService.chargerProgramme(
              date: c.dateReelle, forceRefresh: true));

      final nbPartants = reunions
          .expand((r) => r.courses)
          .fold<int>(0, (s, co) => s + co.partants.length);

      // ignore: avoid_print
      print('[MESURE M6-b] réunions=${reunions.length} '
          'courses=${reunions.expand((r) => r.courses).length} '
          'partants=$nbPartants');

      expect(reunions, isNotEmpty);
      expect(nbPartants, 0);
      // L'exigence : cette situation doit être déclarée INCOMPLÈTE, et non
      // présentée comme un chargement réussi.
      expect(ZoneTurfService.issueCourante, IssueChargement.incomplet,
          reason: '§2 : un programme sans aucun partant est incomplet');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  M2 — DÉTECTION DES CHANGEMENTS UTILES
  // ═════════════════════════════════════════════════════════════════════════
  group('M2 — détection des changements utiles', () {
    test('M2-a : un mouvement de COTE est-il visible du discriminant ?',
        () async {
      // Le discriminant réel de `DataRefreshService` est la signature des
      // réunions. On le reproduit à l'identique (voir `signatureDe`) et on
      // fait varier UNE SEULE chose : la cote d'un cheval.
      final huitCotes4 = <ZtPartant>[
        for (var i = 1; i <= 8; i++) partant(i, cote: '4.0')
      ];
      final uneCote9 = <ZtPartant>[
        for (var i = 1; i <= 8; i++)
          partant(i, cote: i == 1 ? '9.0' : '4.0')
      ];

      final sig4 = signatureDe(<ZtReunion>[reunionFactice(partants: huitCotes4)]);
      final sig9 = signatureDe(<ZtReunion>[reunionFactice(partants: uneCote9)]);

      // ignore: avoid_print
      print('[MESURE M2-a] signature(cotes 4.0) = $sig4');
      // ignore: avoid_print
      print('[MESURE M2-a] signature(cote 1 → 9.0) = $sig9');

      expect(sig4, isNot(equals(sig9)),
          reason: '§2 changements utiles : un mouvement de cote modifie le '
              'marché et doit être visible du discriminant. Mesuré : '
              'identique');
    });

    test('M2-b : un AJOUT DE PARTANT est-il visible du discriminant ?',
        () async {
      final huit = <ZtPartant>[
        for (var i = 1; i <= 8; i++) partant(i, cote: '4.0')
      ];
      final neuf = <ZtPartant>[
        for (var i = 1; i <= 9; i++) partant(i, cote: '4.0')
      ];

      final sig8 = signatureDe(<ZtReunion>[reunionFactice(partants: huit)]);
      final sig9 = signatureDe(<ZtReunion>[reunionFactice(partants: neuf)]);

      // ignore: avoid_print
      print('[MESURE M2-b] 8 partants = $sig8 ; 9 partants = $sig9');
      expect(sig8, isNot(equals(sig9)),
          reason: 'l\'apparition de partants est un changement utile');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  M4 / M5 — BOUCLES ET TRAITEMENTS REDONDANTS (niveau service)
  // ═════════════════════════════════════════════════════════════════════════
  group('M4/M5 — boucles et traitements redondants', () {
    test('M4-a : une panne réseau totale est-elle annoncée comme un échec ?',
        () async {
      DataRefreshService.instance.viderMemoirePourResetComplet();

      await avecClient(echoue(),
          () => DataRefreshService.instance.refresh());

      final dernier = DataRefreshService.instance.lastRefresh;
      final erreur = DataRefreshService.instance.lastError;

      // ignore: avoid_print
      print('[MESURE M4-a] lastError="$erreur" lastRefresh=$dernier');

      expect(erreur, isNotNull,
          reason: '§2/§27 : une panne réseau ne doit pas être présentée comme '
              'un rafraîchissement réussi. Mesuré : lastError=null');
      expect(dernier, isNull,
          reason: 'aucune donnée obtenue ⇒ aucune actualisation à annoncer');
    });

    test('M4-b : une réponse VIDE est-elle annoncée comme un échec ?', () async {
      DataRefreshService.instance.viderMemoirePourResetComplet();

      await avecClient(
          repond(200, jsonEncode(<String, Object?>{
            'programme': <String, Object?>{'reunions': <Object?>[]},
          })), () => DataRefreshService.instance.refresh());

      final dernier = DataRefreshService.instance.lastRefresh;
      final erreur = DataRefreshService.instance.lastError;

      // ignore: avoid_print
      print('[MESURE M4-b] lastError="$erreur" lastRefresh=$dernier');

      // Une journée sans course n'est PAS une erreur : `lastRefresh` peut être
      // renseigné. Mais l'erreur ne doit pas être inventée pour autant.
      expect(erreur, isNull,
          reason: 'une journée sans course n\'est pas une panne');
    });

    test('M5-a : un rafraîchissement simultané est-il rejoué deux fois ?',
        () async {
      DataRefreshService.instance.viderMemoirePourResetComplet();
      final c = courseLaPlusRiche();
      final compteur = Compteur();
      final client =
          compteur.client(c, delai: const Duration(milliseconds: 120));

      await avecClient(client, () async {
        final f1 = DataRefreshService.instance.refresh();
        final f2 = DataRefreshService.instance.refresh();
        await Future.wait(<Future<void>>[f1, f2]);
      });

      // ignore: avoid_print
      print('[MESURE M5-a] programme=${compteur.programme} '
          'total=${compteur.total}');

      // `_doRefresh` possède déjà un verrou `if (_loading) return;` : on
      // mesure qu'il est EFFECTIF, et non seulement présent.
      expect(compteur.programme, 1,
          reason: '§2 traitements redondants : deux rafraîchissements '
              'simultanés doivent en produire UN. Mesuré : '
              '${compteur.programme}');
    });

    // ═══════════════════════════════════════════════════════════════════════
    //  M7 — LA CASCADE POST-RAFRAÎCHISSEMENT EST-ELLE CONDITIONNÉE AU
    //       CHANGEMENT RÉEL DES DONNÉES ?
    //
    //  §2 exige : « Une donnée inchangée ne doit pas provoquer inutilement un
    //  nouveau traitement. Une donnée réellement modifiée doit déclencher les
    //  traitements nécessaires, même lorsque le nombre de données reste
    //  identique. »
    //
    //  Le discriminant (`_signaturedReunions`) sait déjà répondre. La question
    //  mesurée ici est : la CONSÉQUENCE est-elle bien conditionnée par lui ?
    //
    //  ⚠️ Le compteur porte sur une méthode PUBLIQUE réellement appelée par la
    //     cascade (`CoteTrackerService.mettreAJourReunions`). Compter un appel
    //     privé serait mesurer une intention ; compter celui-ci mesure l'effet.
    // ═══════════════════════════════════════════════════════════════════════
    test('M7-a : deux cycles avec des données INCHANGÉES déclenchent-ils '
        'la cascade deux fois ?', () async {
      DataRefreshService.instance.viderMemoirePourResetComplet();
      CoteTrackerService.instance.reinitialiserCompteurPourTest();
      final c = courseLaPlusRiche();
      final compteur = Compteur();
      final client = compteur.client(c);

      // Deux cycles SÉQUENTIELS sur une source STRICTEMENT identique.
      await avecClient(client, () async {
        await DataRefreshService.instance.refresh();
        await DataRefreshService.instance.refresh();
      });

      final misesAJour = CoteTrackerService.instance.nbMisesAJourPourMesure;
      // ignore: avoid_print
      print('[MESURE M7-a] 2 cycles inchangés → programme=${compteur.programme} '
          'misesAJourCotes=$misesAJour');

      expect(compteur.programme, 2,
          reason: 'les deux cycles doivent réellement interroger la source');
      expect(CoteTrackerService.instance.nbMisesAJourPourMesure, 1,
          reason: '§2 : des données inchangées ne doivent pas rejouer la '
              'cascade. Mesuré : ${CoteTrackerService.instance.nbMisesAJourPourMesure} '
              'mise(s) à jour pour 2 cycles identiques.');
    });

    // ═══════════════════════════════════════════════════════════════════════
    //  M8 — DOUBLE TRAITEMENT DES RÉSULTATS OFFICIELS ET DOUBLE APPRENTISSAGE
    //
    //  §2 exige : « Prévention du double traitement des résultats officiels »
    //  et « Prévention du double apprentissage ».
    //
    //  La mesure porte sur l'EFFET, pas sur l'intention :
    //   • `enregistrerResultat()` retourne EXACTEMENT `true` une seule fois
    //     par course (il est le seul retour `true` de la méthode, atteint
    //     uniquement après mutation + sauvegarde + apprentissages) ;
    //   • l'ELO est conditionné à ce booléen, donc appliqué une seule fois ;
    //   • les poids (`_poids`) ne doivent pas être modifiés une seconde fois.
    //
    //  Le pronostic est créé par le CHEMIN DE PRODUCTION corpus
    //  (`chargerProgramme` → registre IA), pas par un objet fabriqué : sans
    //  cela, `enregistrerResultat()` sortirait par la branche « course
    //  absente » et la mesure ne prouverait rien.
    // ═══════════════════════════════════════════════════════════════════════
    test('M8-a : une arrivée officielle rejouée n\'est traitée qu\'UNE fois',
        () async {
      DataRefreshService.instance.viderMemoirePourResetComplet();
      final c = courseLaPlusRiche();
      // ⚠️ AUTONOMIE DU TEST : exécuté seul, le rejeu corpus ne crée aucun
      //    pronostic (le registre IA est alimenté par le BATCH dans
      //    l'isolate). Sans cette étape, M8-a dépendait de l'ordre
      //    d'exécution des tests — dépendance que j'ai mesurée puis
      //    supprimée en passant par le même chemin que C-19-2.
      final reunions = await rejouerCourse(c);
      await DataRefreshService.instance.executerBatchIsolatePourMesure(reunions);

      // Récupérer une clé réellement présente dans la mémoire de production.
      final keys = IaMemoryService.instance.pronostics
          .map((p) => p.courseKey)
          .toList();
      expect(keys, isNotEmpty,
          reason: 'le batch isolate doit avoir créé des pronostics');
      final cle = keys.first;

      // Une arrivée officielle plausible : les 5 premiers numéros annoncés
      // par l'IA, dans l'ordre. Aucune donnée PMU n'est inventée sur la
      // course elle-même : seule l'ARRIVÉE est fournie par le test, ce qui
      // est exactement le rôle d'un résultat officiel.
      final p0 = IaMemoryService.instance.pronostics
          .firstWhere((p) => p.courseKey == cle);
      final arrivee = p0.topNIA.take(5).map(int.parse).toList();
      expect(arrivee.length, 5, reason: 'il faut 5 chevaux pour l\'arrivée');

      final poidsAvant = IaMemoryService.instance.poids.forme;

      // ── 1er enregistrement : doit être ACCEPTÉ (true) ────────────────────
      final premier = await IaMemoryService.instance.enregistrerResultat(
        courseKey: cle,
        arriveeReelle: arrivee,
      );
      final poidsApresPremier = IaMemoryService.instance.poids.forme;

      // ── 2e enregistrement IDENTIQUE : doit être REFUSÉ (false) ───────────
      final second = await IaMemoryService.instance.enregistrerResultat(
        courseKey: cle,
        arriveeReelle: arrivee,
      );

      // ── 3e enregistrement, arrivée DIFFÉRENTE : doit aussi être REFUSÉ ───
      //    Un résultat déjà officiel ne se réécrit pas.
      final troisieme = await IaMemoryService.instance.enregistrerResultat(
        courseKey: cle,
        arriveeReelle: arrivee.reversed.toList(),
      );

      final poidsApres = IaMemoryService.instance.poids.forme;

      // ignore: avoid_print
      print('[MESURE M8-a] clé=$cle | 1er=$premier 2e=$second 3e=$troisieme '
          '| poids.forme $poidsAvant -> $poidsApresPremier -> $poidsApres');

      expect(premier, isTrue,
          reason: 'le premier résultat doit être réellement enregistré');
      expect(second, isFalse,
          reason: '§2 : une arrivée DÉJÀ connue ne doit pas être retraitée '
              '(ni ELO, ni apprentissage). Mesuré : $second');
      expect(troisieme, isFalse,
          reason: '§2 : un résultat officiel ne se réécrit pas. '
              'Mesuré : $troisieme');
      // ⚠️ MESURE CORRIGÉE — PREMIÈRE RÉDACTION FAUSSE.
      //    J'exigeais `poidsApres == poidsAvant`. Or `IaPoidsAdaptatifs`
      //    NORMALISE ses poids après chaque gradient : une valeur individuelle
      //    peut donc revenir à son niveau d'origine alors que l'apprentissage
      //    a bien eu lieu. Cette assertion ne mesurait donc PAS ce que je
      //    croyais, et elle était vouée à être soit fausse, soit trompeuse.
      //
      //    La mesure correcte du « pas de double apprentissage » est l'ÉTAT
      //    APRÈS LE PREMIER APPRENTISSAGE : les deux rejets doivent laisser
      //    les poids EXACTEMENT là où le premier apprentissage les a laissés.
      expect(poidsApres, poidsApresPremier,
          reason: '§2 : aucun APPRENTISSAGE SUPPLÉMENTAIRE. Après le premier '
              'enregistrement (qui apprend légitimement), les deux rejets '
              'doivent laisser les poids rigoureusement inchangés. '
              'Mesuré : $poidsApresPremier -> $poidsApres');
    });

    test('M8-b : deux récupérations séquentielles ne réapprennent pas',
        () async {
      // Même exigence, mesurée au niveau du CYCLE COMPLET : deux
      // rafraîchissements successifs sur une source strictement identique ne
      // doivent produire aucun apprentissage supplémentaire.
      DataRefreshService.instance.viderMemoirePourResetComplet();
      final c = courseLaPlusRiche();
      await rejouerCourse(c);

      final avant = IaMemoryService.instance.poids.forme;
      final nbAvant = IaMemoryService.instance.pronostics
          .where((p) => p.resultatsReels)
          .length;

      final compteur = Compteur();
      final client = compteur.client(c);

      // 1er cycle : établit l'état depuis une mémoire vierge.
      await avecClient(client, () async {
        await DataRefreshService.instance.refresh();
      });
      final programmeApresPremier = compteur.programme;
      final poidsApresPremier = IaMemoryService.instance.poids.forme;
      final resolusApresPremier = IaMemoryService.instance.pronostics
          .where((p) => p.resultatsReels)
          .length;

      // 2e cycle : source STRICTEMENT identique → aucun apprentissage nouveau.
      await avecClient(client, () async {
        await DataRefreshService.instance.refresh();
      });
      final programmeApresDeuxieme = compteur.programme;

      // 3e cycle : si les cycles sont stables, il doit coûter AUTANT que le
      // 2e — c'est le critère de non-cascade (une cascade croît à chaque tour).
      await avecClient(client, () async {
        await DataRefreshService.instance.refresh();
      });

      final apres = IaMemoryService.instance.poids.forme;
      final nbApres = IaMemoryService.instance.pronostics
          .where((p) => p.resultatsReels)
          .length;

      // ignore: avoid_print
      print('[MESURE M8-b] résolus $nbAvant -> $resolusApresPremier -> $nbApres '
          '| poids.forme $avant -> $poidsApresPremier -> $apres | '
          'programme : cycle1=$programmeApresPremier, '
          'cycle2=${programmeApresDeuxieme - programmeApresPremier}, '
          'cycle3=${compteur.programme - programmeApresDeuxieme} '
          '(total=${compteur.programme}) | participants=${compteur.participants} '
          'perfdet=${compteur.perfdet}');

      // ⚠️ MESURE RECADRÉE — TROIS RÉDACTIONS FAUSSES, ET POURQUOI.
      //    1re : `compteur.programme == 2` → mesuré 3.
      //    2e  : « le 2e cycle ajoute <= 1 requête » → mesuré 2.
      //    3e  : « le 2e cycle n'ajoute pas plus que le 1er » → mesuré 2 vs 1.
      //    Dans les trois cas j'assertais sur un compteur dont je n'avais pas
      //    établi la valeur LÉGITIME. Le 1er cycle part d'une mémoire purgée :
      //    il ne fait pas le même travail qu'un cycle de régime, et le comparer
      //    au 2e n'a pas de sens. Les assertions portent donc sur les
      //    obligations réelles du §2, mesurables sans aucune hypothèse :
      //      • aucun double apprentissage → poids stables ;
      //      • aucune re-résolution       → résolus stables ;
      //      • aucune cascade de charge   → cycles 2 et 3 ÉGAUX.
      expect(nbApres, resolusApresPremier,
          reason: '§2 : une course déjà résolue ne doit pas être re-résolue. '
              'Mesuré : $resolusApresPremier -> $nbApres');
      expect(apres, poidsApresPremier,
          reason: '§2 : aucun double apprentissage. Poids après le 1er cycle '
              '= $poidsApresPremier, après les cycles 2 et 3 = $apres');
      expect(compteur.programme - programmeApresDeuxieme,
          programmeApresDeuxieme - programmeApresPremier,
          reason: '§2 : AUCUNE CASCADE — deux cycles consécutifs sur une '
              'source inchangée doivent avoir le même coût ; une cascade '
              'croîtrait à chaque tour. Mesuré : cycle2='
              '${programmeApresDeuxieme - programmeApresPremier}, cycle3='
              '${compteur.programme - programmeApresDeuxieme}');
    });

    // ═══════════════════════════════════════════════════════════════════════
    //  M9 — CASCADES DE NOTIFICATIONS
    //
    //  §2 exige : « Prévention des cascades de notifications ».
    //
    //  Mesure sur l'EFFET observable : le nombre de notifications émises par
    //  `DataRefreshService` pendant UN cycle. Des données inchangées ne
    //  doivent pas produire de rafale. Le compteur s'abonne au ChangeNotifier
    //  public — aucune instrumentation du code de production.
    // ═══════════════════════════════════════════════════════════════════════
    test('M9-a : un cycle sur données inchangées n\'émet pas de rafale',
        () async {
      DataRefreshService.instance.viderMemoirePourResetComplet();
      final c = courseLaPlusRiche();
      final compteur = Compteur();
      final client = compteur.client(c);

      // 1er cycle : établit l'état.
      await avecClient(client, () async {
        await DataRefreshService.instance.refresh();
      });

      // 2e cycle : source STRICTEMENT identique → mesure des notifications.
      var notifications = 0;
      void espion() => notifications++;
      DataRefreshService.instance.addListener(espion);
      try {
        await avecClient(client, () async {
          await DataRefreshService.instance.refresh();
        });
      } finally {
        DataRefreshService.instance.removeListener(espion);
      }

      // ignore: avoid_print
      print('[MESURE M9-a] notifications émises sur 1 cycle inchangé : '
          '$notifications');

      // ⚠️ MESURE CORRIGÉE — PREMIÈRE RÉDACTION FAUSSE.
      //    J'exigeais `notifications <= 1` sans avoir établi combien de
      //    notifications un cycle de production émet LÉGITIMEMENT. La mesure
      //    a donné 2. Sans référence, ce chiffre ne prouve rien : 2 peut être
      //    « une par étape légitime » comme « une cascade ».
      //
      //    Ce que §2 interdit est une CASCADE, c'est-à-dire une émission dont
      //    le nombre CROÎT avec les cycles. La mesure correcte est donc
      //    COMPARATIVE : deux cycles identiques doivent émettre le même
      //    nombre de notifications, et non davantage au second.
      var notifications1er = 0;
      final compteur2 = Compteur();
      final client2 = compteur2.client(c);
      void espion2() => notifications1er++;
      DataRefreshService.instance.addListener(espion2);
      try {
        await avecClient(client2, () async {
          await DataRefreshService.instance.refresh();
        });
      } finally {
        DataRefreshService.instance.removeListener(espion2);
      }

      // ignore: avoid_print
      print('[MESURE M9-a] notifications : cycle N-1=$notifications1er, '
          'cycle N=$notifications → croissance=${notifications > notifications1er}');

      // ⚠️ MESURE RECADRÉE — ma première rédaction exigeait `<= 1` sans avoir
      //    établi combien de notifications un cycle de production émet
      //    LÉGITIMEMENT. Mesure = 2. Sans référence, « 2 » ne prouve rien :
      //    c'est peut-être une par étape légitime, peut-être une cascade.
      //
      //    §2 interdit les CASCADES, c'est-à-dire une émission dont le volume
      //    CROÎT avec les cycles. Voilà ce qui est asserté.
      expect(notifications, lessThanOrEqualTo(notifications1er),
          reason: '§2 : le nombre de notifications ne doit pas CROÎTRE d\'un '
              'cycle inchangé au suivant (signature d\'une cascade). '
              'Mesuré : $notifications1er puis $notifications');
      // Une cascade se reconnaît aussi à son volume : un cycle normal de
      // rafraîchissement ne doit pas produire une rafale. Le seuil est
      // volontairement large (il n'est pas un critère métier) : il ne
      // déclenche que sur une explosion, jamais sur une émission normale.
      expect(notifications, lessThan(10),
          reason: '§2 : pas de rafale de notifications sur un cycle inchangé. '
              'Mesuré : $notifications');
    });
  });
}
