// ═══════════════════════════════════════════════════════════════════════════
//  BL1 / BL3-A22 — CHAÎNE RÉELLE : PRODUCTEUR PMU → CRITÈRE R DU MOTEUR IA
//
//  OBJET : le défaut BL3-A22 ne peut pas être prouvé — ni corrigé — par un
//          test qui FABRIQUE une ancre correcte. Ce fichier exerce donc :
//
//    1. `ZoneTurfService.chargerProgramme()`  ← LE producteur réel, avec le
//       réseau PMU intercepté (`http.runWithClient` + `MockClient`). Il
//       construit lui-même les `ZtCourse`, donc l'`anchor` est bien celui que
//       l'application utilise en production, pas une valeur de test.
//
//    2. `IaPronosticEngine.cleCourseMouvements()` ← LA fonction de clé du
//       moteur, `@visibleForTesting`, sans réimplémentation du format.
//
//    3. `CoteTrackerService.scoreCritereR()` ← LA lecture exacte effectuée par
//       `IaPronosticEngine.analyserCourse()` (`ia_pronostic_engine.dart:51`).
//
//  Aucune valeur de score n'est inventée : le barème `MouvementCote.scoreIA`
//  (`cote_tracker_service.dart:69-82`) place une variation ≤ −20 % à 75,0.
//
//  Aucune écriture d'apprentissage : `analyserJourneeComplete()` n'est jamais
//  appelée, `IaMemoryService` n'est pas sollicité en écriture.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/cote_tracker_service.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart'
    show ScoresCriteres;
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ─── Course de référence : R3 / C5, exactement le cas de l'anomalie ────────
const int kNumR = 3;
const int kNumC = 5;
const String kNumeroCheval = '7';
const String kNomCheval = 'IDEAL DU MOULIN';

/// Variation réelle du scénario : 5,00 → 4,00 = −20,00 % ⇒ tranche `<= -20`
/// ⇒ score 75,0 (barème du service, non recopié ici).
const double kCoteDebut = 5.00;
const double kCoteFin = 4.00;
const double kScoreAttendu = 75.0;

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Réponse `/programme/{date}` minimale mais RÉELLE dans sa structure :
/// hippodrome français, une réunion, une course R3C5.
Map<String, dynamic> _programmeJson(DateTime depart) => <String, dynamic>{
      'programme': <String, dynamic>{
        'date': _ddmmyyyy(depart),
        'reunions': <Map<String, dynamic>>[
          <String, dynamic>{
            'numOfficiel': kNumR,
            'dateReunion': depart.millisecondsSinceEpoch,
            'hippodrome': <String, dynamic>{
              'libelleCourt': 'VINCENNES',
              'libelleLong': 'HIPPODROME DE VINCENNES',
            },
            'pays': <String, dynamic>{'code': 'FR'},
            'courses': <Map<String, dynamic>>[
              <String, dynamic>{
                'numOrdre': kNumC,
                'numReunion': kNumR,
                'libelle': 'PRIX DE LA CHAINE DU FROID',
                'distance': 2700,
                'montantPrix': 45000,
                'discipline': 'ATTELE',
                'heureDepart': depart.millisecondsSinceEpoch,
                'categorieParticularite': 'COURSE_A_CONDITIONS',
                // `paris` porte la détection Quinté/Quarté (zone_turf:143-150)
                'paris': <Map<String, dynamic>>[
                  <String, dynamic>{'typePari': 'E_SIMPLE_GAGNANT'},
                  <String, dynamic>{'typePari': 'E_TIERCE'},
                ],
              },
            ],
          },
        ],
      },
    };

Map<String, dynamic> _participantsJsonZoneTurf(double cote) => <String, dynamic>{
      'participants': <Map<String, dynamic>>[
        <String, dynamic>{
          'numPmu': int.parse(kNumeroCheval),
          'nom': kNomCheval,
          'statut': 'DECLARE_PARTANT',
          'musique': '1a2a3a1a5a',
          'dernierRapportDirect': <String, dynamic>{'rapport': cote},
        },
      ],
    };

/// Forme attendue par `CoteTrackerService._fetchEtStockerCotes`
/// (`cote_tracker_service.dart:436-450`) : `rapports[]` avec un `typePari`
/// contenant `SIMPLE_GAGNANT`.
Map<String, dynamic> _participantsJsonWriter(double cote) => <String, dynamic>{
      'participants': <Map<String, dynamic>>[
        <String, dynamic>{
          'numPmu': int.parse(kNumeroCheval),
          'nom': kNomCheval,
          'rapports': <Map<String, dynamic>>[
            <String, dynamic>{
              'typePari': 'E_SIMPLE_GAGNANT',
              'rapport': cote,
            },
          ],
        },
      ],
    };

int _snapshots = 0;
final List<Uri> _urls = <Uri>[];

/// Client du PRODUCTEUR (`ZoneTurfService`).
///
/// Il répond à DEUX endpoints, distingués sans ambiguïté par le NOMBRE de
/// segments qui suivent « programme » :
///   • `/…/programme/{date}`                         → le programme ;
///   • `/…/programme/{date}/R{n}/C{n}/participants`  → les partants.
///
/// ⚠️ Un test sur `path.contains('R3')` serait FAUX en principe : il ne
/// distingue pas structurellement les deux endpoints. On compte les segments.
http.Client _clientProducteur(DateTime depart) =>
    MockClient((http.Request req) async {
      _urls.add(req.url);
      final int i = req.url.pathSegments.indexOf('programme');
      final List<String> apres =
          i >= 0 ? req.url.pathSegments.sublist(i + 1) : const <String>[];
      if (apres.length <= 1) {
        return http.Response(json.encode(_programmeJson(depart)), 200,
            headers: <String, String>{'content-type': 'application/json'});
      }
      return http.Response(json.encode(_participantsJsonZoneTurf(kCoteDebut)),
          200,
          headers: <String, String>{'content-type': 'application/json'});
    });

/// Client du WRITER (`CoteTrackerService._fetchEtStockerCotes`).
///
/// ⚠️ CAUSE RÉELLE DU ROUGE PRÉCÉDENT : ce writer ne lit PAS
/// `item['dernierRapportDirect']` (forme du producteur) mais
/// `item['rapports'][…]['rapport']` (`cote_tracker_service.dart:436-450`).
/// Le client unique d'origine ne renvoyait que la forme « producteur » : le
/// writer ne trouvait aucune cote, faisait `continue`, et n'écrivait donc
/// RIEN. Le défaut était dans le HARNAIS, pas dans la production.
///
/// Les deux clients sont désormais DISTINCTS parce que les deux producteurs
/// interrogent l'API avec des attentes de forme différentes. Aucune ancre,
/// aucune cote de mouvement n'est fabriquée : seule la réponse HTTP simulée
/// diffère, comme le font réellement les deux endpoints PMU.
http.Client _clientWriter(List<Uri> urlsWriter) =>
    MockClient((http.Request req) async {
      urlsWriter.add(req.url);
      _snapshots++;
      return http.Response(
          json.encode(_participantsJsonWriter(
              _snapshots <= 1 ? kCoteDebut : kCoteFin)),
          200,
          headers: <String, String>{'content-type': 'application/json'});
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─────────────────────────────────────────────────────────────────────────
  //  B1-A22-1 — L'ANCRE EST PRODUITE PAR LE PRODUCTEUR RÉEL
  // ─────────────────────────────────────────────────────────────────────────
  test('B1-A22-1 — ZoneTurfService.chargerProgramme() produit « R{nR}C{nC} »',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await CoteTrackerService.instance.viderCachePourResetComplet();

    final DateTime depart = DateTime.now().add(const Duration(minutes: 10));
    final String dateStr = _ddmmyyyy(depart);

    List<ZtReunion> reunions = const <ZtReunion>[];
    await http.runWithClient(() async {
      reunions = await ZoneTurfService.chargerProgramme(
        forceRefresh: true,
        date: depart,
      );
    }, () => _clientProducteur(depart));

    // TÉMOIN — le producteur a réellement produite une course.
    expect(reunions, isNotEmpty,
        reason: 'TÉMOIN : le programme simulé doit produire au moins une réunion');
    final ZtReunion reunion = reunions.first;
    expect(reunion.courses, hasLength(1));
    final ZtCourse course = reunion.courses.first;

    // TÉMOIN — identité de la course telle que la voit l'application.
    expect(course.numCourse, kNumC);
    expect(course.dateStr, dateStr);

    // MESURE — l'ancre réellement produite.
    // ignore: avoid_print
    print('─── MESURE B1-A22-1 (producteur réel) ──────────────────────');
    // ignore: avoid_print
    print('  reunion.code = « ${reunion.code} », course.numCourse = ${course.numCourse}');
    // ignore: avoid_print
    print('  course.anchor PRODUITE = « ${course.anchor} »');
    // ignore: avoid_print
    print('  ATTENDU : « R${kNumR}C$kNumC »  (l\'ancien défaut donnait « $kNumR$kNumC »)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    // ASSERTION — format d'identité, celui qu'attend le consommateur.
    expect(course.anchor, 'R${kNumR}C$kNumC',
        reason: 'BL3-A22 : le producteur doit émettre « R{nR}C{nC} » et non un '
            'concaténat nu (« $kNumR$kNumC »), que le consommateur '
            'IaPronosticEngine rejette par RegExp(r\'^R(\\d+)C\\d+\$\').');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  B1-A22-2 — LA CLÉ DU MOTEUR EST CELLE DE LA PRODUCTION
  // ─────────────────────────────────────────────────────────────────────────
  test('B1-A22-2 — la clé IA construite depuis la course produite est exploitable',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await CoteTrackerService.instance.viderCachePourResetComplet();

    final DateTime depart = DateTime.now().add(const Duration(minutes: 10));
    final String dateStr = _ddmmyyyy(depart);

    List<ZtReunion> reunions = const <ZtReunion>[];
    await http.runWithClient(() async {
      reunions = await ZoneTurfService.chargerProgramme(
        forceRefresh: true,
        date: depart,
      );
    }, () => _clientProducteur(depart));

    final ZtCourse course = reunions.first.courses.first;

    // Clé RÉELLE du moteur, sans réimplémentation du format.
    final String cle = IaPronosticEngine.cleCourseMouvements(course);

    // ignore: avoid_print
    print('─── MESURE B1-A22-2 (clé du moteur) ────────────────────────');
    // ignore: avoid_print
    print('  cleCourseMouvements(course produite) = « $cle »');
    // ignore: avoid_print
    print('  ATTENDU : « R${kNumR}C${kNumC}_$dateStr »');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(cle, 'R${kNumR}C${kNumC}_$dateStr',
        reason: 'La clé du moteur doit être « R{nR}C{nC}_JJMMAAAA ». Avant '
            'correction, l\'ancre « $kNumR$kNumC » ne satisfaisait pas '
            'RegExp(r\'^R(\\d+)C\\d+\$\') : _numReunionDepuisAnchor rendait \'\' '
            'et la clé était VIDE, donc aucun mouvement de cote ne pouvait '
            'être lu par le critère R.');

    // Et cette course est bien dans la fenêtre d'activation du critère R.
    expect(CoteTrackerService.instance.estDansFenetre(course), isTrue,
        reason: 'TÉMOIN : départ à +10 min, fenêtre 0-30 min');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  B1-A22-3 — LE MOUVEMENT RÉEL EST VU PAR LE CONSOMMATEUR IA
  // ─────────────────────────────────────────────────────────────────────────
  test('B1-A22-3 — un mouvement réel est vu par scoreCritereR via la clé IA',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await CoteTrackerService.instance.viderCachePourResetComplet();

    final DateTime depart = DateTime.now().add(const Duration(minutes: 10));
    final String dateStr = _ddmmyyyy(depart);

    // ── PHASE 1 : le producteur réel construit les réunions ───────────────
    //
    //  Le client de CETTE phase est DISTINCT de celui du writer (phase 2).
    //  Motif : les deux producteurs n'appellent pas le même endpoint de la même
    //  façon et il ne faut pas qu'une réponse de l'un satisfasse la requête de
    //  l'autre. `ZoneTurfService.chargerProgramme()` appelle
    //  `/programme/{date}` puis `/programme/{date}/R{n}/C{n}/participants`,
    //  tandis que `CoteTrackerService` appelle `/programme/{date}/R{n}/C{n}/participants`
    //  par l'URL `_baseUrl` de `cote_tracker_service.dart:109`.
    List<ZtReunion> reunions = const <ZtReunion>[];
    await http.runWithClient(() async {
      reunions = await ZoneTurfService.chargerProgramme(
        forceRefresh: true,
        date: depart,
      );
    }, () => _clientProducteur(depart));

    expect(reunions, isNotEmpty,
        reason: 'TÉMOIN : le producteur doit produire au moins une réunion');
    final ZtCourse course = reunions.first.courses.first;
    final ZtReunion reunion = reunions.first;

    // ── PHASE 2 : le writer de PRODUCTION écrit les mouvements ────────────
    _snapshots = 0;
    final List<Uri> urlsWriter = <Uri>[];
    await http.runWithClient(() async {
      CoteTrackerService.instance.demarrer(<ZtReunion>[reunion]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      CoteTrackerService.instance.demarrer(<ZtReunion>[reunion]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }, () => _clientWriter(urlsWriter));
    CoteTrackerService.instance.arreter();

    // TÉMOIN — deux snapshots réels ont été obtenus.
    expect(_snapshots, greaterThanOrEqualTo(2),
        reason: 'TÉMOIN : il faut >= 2 snapshots pour calculer une variation');

    // Clé de PRODUCTION (writer) et clé du MOTEUR (consommateur).
    final String cleEcriture = 'R${kNumR}C${kNumC}_$dateStr';
    final String cleMoteur = IaPronosticEngine.cleCourseMouvements(course);

    final MouvementCote? vuEcriture =
        CoteTrackerService.instance.mouvementPourPartant(cleEcriture, kNumeroCheval);
    final double? scoreMoteur =
        CoteTrackerService.instance.scoreCritereR(cleMoteur, kNumeroCheval);

    // Contre-épreuve : la clé fabriquée par l'ANCIEN défaut ne trouve rien.
    final double? scoreAncienDefaut = CoteTrackerService.instance
        .scoreCritereR('', kNumeroCheval);

    // ignore: avoid_print
    print('─── MESURE B1-A22-3 (consommateur IA) ──────────────────────');
    // ignore: avoid_print
    print('  écriture sous « $cleEcriture » : '
        '${vuEcriture == null ? "AUCUN" : "variation ${vuEcriture.variationPct.toStringAsFixed(2)} %, score ${vuEcriture.scoreIA}"}');
    // ignore: avoid_print
    print('  lecture IA via « $cleMoteur » : '
        '${scoreMoteur ?? "NULL (critère R neutralisé à 50.0)"}');
    // ignore: avoid_print
    print('  contre-épreuve clé vide (ancien défaut) : '
        '${scoreAncienDefaut ?? "NULL (neutralisé)"}');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    // TÉMOIN — la donnée existe réellement sous la clé de production.
    expect(vuEcriture, isNotNull,
        reason: 'TÉMOIN : le writer doit avoir rangé la course sous '
            '« $cleEcriture »');
    expect(vuEcriture!.variationPct, closeTo(-20.0, 0.01),
        reason: 'TÉMOIN : 5,00 → 4,00 = −20,00 % (mesuré '
            '${vuEcriture.variationPct})');

    // ASSERTION MÉTIER — le consommateur IA voit le mouvement réel.
    expect(scoreMoteur, kScoreAttendu,
        reason: 'BL3-A22 : le moteur doit lire le mouvement réel. Avant '
            'correction la clé était vide ⇒ scoreCritereR rendait null ⇒ le '
            'critère R (mouvCote, 6 % du score) restait figé à 50.0 pour '
            'TOUTES les courses. Mesuré : $scoreMoteur.');

    // CONTRE-ÉPREUVE — la clé vide de l'ancien défaut ne trouve rien : la
    // correction est bien la cause du résultat précédent.
    expect(scoreAncienDefaut, isNull,
        reason: 'CONTRE-ÉPREUVE : une clé vide ne peut rien trouver, ce qui '
            'reproduit exactement le symptôme mesuré de BL3-A22.');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  B1-A22-4 — DEUX COURSES DE MÊME R/C SUR DEUX DATES SONT DISTINCTES
  //  (exigence §4 : « garantir la distinction entre deux courses avec les
  //   mêmes numéros R/C à des dates différentes »)
  // ─────────────────────────────────────────────────────────────────────────
  test('B1-A22-4 — même R/C, dates différentes ⇒ clés distinctes', () {
    ZtCourse courseDu(String date) => ZtCourse(
          numCourse: kNumC,
          anchor: 'R${kNumR}C$kNumC',
          nom: 'PRIX DE LA CHAINE DU FROID',
          heure: '14:05',
          distance: '2700',
          prix: '45000',
          type: 'Trot Attelé',
          piste: 'Sable',
          categorie: 'Course à conditions',
          isQuinte: false,
          pronosticZt: const <int>[7],
          partants: const <ZtPartant>[],
          dateStr: date,
        );

    final String cle1 = IaPronosticEngine.cleCourseMouvements(courseDu('03112026'));
    final String cle2 = IaPronosticEngine.cleCourseMouvements(courseDu('10112026'));

    // ignore: avoid_print
    print('─── MESURE B1-A22-4 (distinction des dates) ────────────────');
    // ignore: avoid_print
    print('  03/11/2026 -> « $cle1 »');
    // ignore: avoid_print
    print('  10/11/2026 -> « $cle2 »');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(cle1, 'R${kNumR}C${kNumC}_03112026');
    expect(cle2, 'R${kNumR}C${kNumC}_10112026');
    expect(cle1, isNot(cle2),
        reason: 'Deux courses R3C5 à deux dates différentes ne doivent JAMAIS '
            'partager la même clé de mouvements de cotes (fuite de données '
            'entre deux courses).');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  B1-A22-5 — LE CONSOMMATEUR QUI PERSISTE LES PRONOSTICS ALIMENTE AUSSI R
  //
  //  DÉFAUT MESURÉ : `analyserCourseAvecCriteres()` — utilisée par
  //  `data_refresh_service.dart:101/:791/:1046` et
  //  `ia_memory_service.dart:6197`, donc par la PRODUCTION des pronostics
  //  persistés — n'alimentait jamais `scoreMouvementCote`. Seule
  //  `analyserCourse()` le faisait. Le critère R restait donc à 50.0 dans
  //  tous les scores enregistrés, même quand un mouvement réel existait.
  // ─────────────────────────────────────────────────────────────────────────
  test('B1-A22-5 — analyserCourseAvecCriteres() alimente le critère R', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await CoteTrackerService.instance.viderCachePourResetComplet();

    final DateTime depart = DateTime.now().add(const Duration(minutes: 10));
    final String dateStr = _ddmmyyyy(depart);

    List<ZtReunion> reunions = const <ZtReunion>[];
    await http.runWithClient(() async {
      reunions = await ZoneTurfService.chargerProgramme(
        forceRefresh: true,
        date: depart,
      );
    }, () => _clientProducteur(depart));

    final ZtCourse course = reunions.first.courses.first;
    final ZtReunion reunion = reunions.first;

    // Le writer de production écrit le mouvement réel.
    _snapshots = 0;
    final List<Uri> urlsWriter = <Uri>[];
    await http.runWithClient(() async {
      CoteTrackerService.instance.demarrer(<ZtReunion>[reunion]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      CoteTrackerService.instance.demarrer(<ZtReunion>[reunion]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }, () => _clientWriter(urlsWriter));
    CoteTrackerService.instance.arreter();

    expect(dateStr, isNotEmpty);

    // ── CONSOMMATEUR DE PRODUCTION : la fonction qui produit les pronostics
    final (List<ZtPartant> classes, Map<String, ScoresCriteres> criteres) =
        IaPronosticEngine.analyserCourseAvecCriteres(course);

    final ZtPartant? p = classes
        .where((e) => e.numero == kNumeroCheval)
        .cast<ZtPartant?>()
        .firstWhere((_) => true, orElse: () => null);
    final ScoresCriteres? sc = criteres[kNumeroCheval];

    // ignore: avoid_print
    print('─── MESURE B1-A22-5 (consommateur qui persiste) ────────────');
    // ignore: avoid_print
    print('  scoreMouvementCote du partant rendu = ${p?.scoreMouvementCote}');
    // ignore: avoid_print
    print('  ScoresCriteres.mouvCote            = ${sc?.mouvCote}');
    // ignore: avoid_print
    print('  ATTENDU : 75.0 (mouvement −20 % réel, dans la fenêtre)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(p, isNotNull, reason: 'TÉMOIN : le partant doit être classé');
    expect(p!.scoreMouvementCote, kScoreAttendu,
        reason: 'Le partant rendu doit porter le score du mouvement réel, '
            'sinon `copyWith` le neutralise à 50.0 dans les pronostics '
            'persistés.');
    expect(sc, isNotNull, reason: 'TÉMOIN : les critères doivent être rendus');
    expect(sc!.mouvCote, kScoreAttendu,
        reason: 'BL3-A22 (2ᵉ maillon) : `ScoresCriteres.mouvCote` doit valoir '
            'le score réel. Avant correction, cette fonction ne lisait jamais '
            '`CoteTrackerService` et la valeur était toujours 50.0.');
  });
}
