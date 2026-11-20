// ═══════════════════════════════════════════════════════════════════════════
//  Z2 — DIAGNOSTIC N1 : DIVERGENCE DES IDENTIFIANTS DE COURSE (`courseKey`)
//
//  OBJET : comparer les PRODUCTEURS et CONSOMMATEURS RÉELS de `courseKey`
//          pour R1 / C10 / 19-11-2026 (et pour la course du jour équivalente).
//
//  AUCUNE MODIFICATION DE `lib/`. AUCUN CALCUL IA MODIFIÉ. AUCUNE ÉCRITURE
//  D'APPRENTISSAGE. `analyseJourneeComplete()` n'est pas appelée.
//
//  MÉTHODE : on ne réimplémente aucun producteur. On pilote le code de
//  production :
//    • `buildCourseKey()` (`arrivee_reelle_widget.dart:26-34`) — publique ;
//    • le writer RÉEL `CoteTrackerService._pollCotesImminentes()`, atteint par
//      l'API publique `demarrer(reunions)` avec le réseau simulé
//      (`http.runWithClient` + `MockClient`) ;
//    • les lecteurs réels `mouvementsPourCourse()`, `mouvementPourPartant()`,
//      `scoreCritereR()`.
//
//  LIMITE DOCUMENTÉE : `IaPronosticEngine._buildCourseKey()` est PRIVÉE. Son
//  format est établi PAR LECTURE de `ia_pronostic_engine.dart:823-839` (le
//  code s'auto-documente : « On ne connaît pas numR ici → on utilise un
//  placeholder » → `return 'C${course.numCourse}_$day$month$year';`). Le test
//  ne prétend donc PAS avoir exécuté cette fonction : il mesure sa
//  CONSÉQUENCE, c'est-à-dire que les deux espaces de clés sont disjoints.
//  Aucune réflexion, aucun accès à un membre privé n'est utilisé.
//
//  Producteurs NON EXÉCUTÉS (documentés par lecture uniquement, cf. rapport) :
//    • `data_refresh_service.dart:95, 480, 512, 901, 1044` ;
//    • `ia_memory_service.dart:6170`.
//  Ils ne sont atteignables qu'en déclenchant un rafraîchissement complet ou
//  une recréation de pronostics, donc une écriture d'apprentissage : exclu.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/cote_tracker_service.dart';
import 'package:pronostic_hippique/widgets/arrivee_reelle_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  CONSTANTES DE LA COURSE DE RÉFÉRENCE
// ═══════════════════════════════════════════════════════════════════════════

const int kNumR = 1;
const int kNumC = 10;
const String kDateReference = '19112026'; // 19-11-2026 (format ddmmyyyy)
const String kNumeroCheval = '16';
const String kNomCheval = 'SIM CARD';

/// Cotes réelles du scénario : 4,20 → 3,36 = −20,00 % exactement.
/// Le barème de `MouvementCote.scoreIA` (`cote_tracker_service.dart:69-82`)
/// place −20 % dans la tranche `<= -20` → score 75,0.
const double kCoteDebut = 4.20;
const double kCoteFin = 3.36;
const double kVariationAttendue = -20.0;
const double kScoreAttendu = 75.0;

// ═══════════════════════════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════════════════════════

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

ZtPartant _partant16() => ZtPartant(
      numero: kNumeroCheval,
      nom: kNomCheval,
      driver: 'M. GUYON',
      entraineur: 'A. FABRE',
      proprietaire: 'Ecurie SIM CARD',
      gains: '50000',
      record: '1\'58"00',
      musique: '5p5p2p2p1p4p2p7p(25)0p',
      cote: '18,0',
      ageSexe: 'H5',
      poids: 56.0,
    );

/// Course R1C10 dont le départ est à +10 min : `estDansFenetre()`
/// (`cote_tracker_service.dart:354-359`) exige 0..30 min, et
/// `_pollCotesImminentes()` (`:370-385`) exige 0..35 min.
ZtCourse _courseR1C10({required String dateStr, required String heure}) => ZtCourse(
      numCourse: kNumC,
      anchor: 'R1C10',
      nom: 'PRIX DE BAD GODESBERG',
      heure: heure,
      distance: '2000',
      prix: '25900',
      type: 'Plat',
      piste: 'Gazon',
      categorie: 'Course à conditions',
      isQuinte: false,
      pronosticZt: const <int>[16],
      partants: <ZtPartant>[_partant16()],
      dateStr: dateStr,
    );

ZtReunion _reunionR1({required String dateStr, required ZtCourse course}) =>
    ZtReunion(
      code: 'R$kNumR',
      lieu: 'SAINT-CLOUD',
      discipline: 'Plat',
      dateStr: dateStr,
      courses: <ZtCourse>[course],
    );

/// Réseau simulé : deux réponses successives reproduisant la CHUTE de cote
/// 4,20 → 3,36. La première requête renvoie la cote d'ouverture, la seconde
/// la cote courante. Aucune autre URL n'est autorisée (assertion du témoin).
int _appelsReseau = 0;
final List<Uri> _urlsAppelees = <Uri>[];

http.Client _clientParticipants() => MockClient((http.Request req) async {
      _urlsAppelees.add(req.url);
      _appelsReseau++;
      final double cote = _appelsReseau == 1 ? kCoteDebut : kCoteFin;
      final corps = <String, dynamic>{
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
      return http.Response(json.encode(corps), 200,
          headers: <String, String>{'content-type': 'application/json'});
    });

/// Prépare un état PROPRE puis fait écrire les mouvements par le VRAI writer.
///
/// Indépendance vis-à-vis de l'ordre d'exécution : `viderCachePourResetComplet()`
/// est public et remet `_historique` / `_mouvements` à zéro avant chaque test.
///
/// Retourne (dateStr, heure, clé de production `R{numR}C{numC}_…`).
Future<({String dateStr, String heure, String cleProd})> _faireEcrireParLeWriterReel() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  SharedPreferences.resetStatic();
  await CoteTrackerService.instance.viderCachePourResetComplet();

  final String dateStr = _ddmmyyyy(DateTime.now());
  final ZtCourse course =
      _courseR1C10(dateStr: dateStr, heure: _hhmm(DateTime.now().add(const Duration(minutes: 10))));
  final ZtReunion reunion = _reunionR1(dateStr: dateStr, course: course);

  _appelsReseau = 0;
  _urlsAppelees.clear();

  await http.runWithClient(() async {
    // `demarrer()` déclenche un poll IMMÉDIAT (`cote_tracker_service.dart:152-166`).
    // Deux appels ⇒ deux snapshots ⇒ `_calculerMouvements()` produit une
    // variation (il exige `snaps.length >= 2`, `:471-477`).
    CoteTrackerService.instance.demarrer(<ZtReunion>[reunion]);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    CoteTrackerService.instance.demarrer(<ZtReunion>[reunion]);
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }, _clientParticipants);

  // Le timer périodique de 3 min doit être annulé : sinon il survivrait au test.
  CoteTrackerService.instance.arreter();

  return (dateStr: dateStr, heure: course.heure, cleProd: 'R${kNumR}C${kNumC}_$dateStr');
}

// ═══════════════════════════════════════════════════════════════════════════
//  TESTS
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ───────────────────────────────────────────────────────────────────────
  //  Z2-A — LE PRODUCTEUR PUBLIC PRODUIT `R{numR}C{numC}_{ddmmyyyy}`
  //         ET LE WRITER RÉEL ÉCRIT DANS CET ESPACE-LÀ
  //  Attendu : VERT. Ce test VERROUILLE le format de production par MESURE :
  //  il interdit de « corriger » N1 en alignant le writer sur le moteur.
  // ───────────────────────────────────────────────────────────────────────
  test('Z2-A / N1 — les producteurs réels écrivent sous « R{nR}C{nC}_date »', () async {
    // ── Producteur 1 : fonction publique réellement utilisée par l'UI ────
    final String cleUi = buildCourseKey(
      reunionCode: 'R$kNumR',
      numCourse: kNumC,
      dateStr: kDateReference,
    );

    // ── Producteur 2 : le WRITER de CoteTrackerService, via `demarrer()` ──
    final ({String dateStr, String heure, String cleProd}) mesure =
        await _faireEcrireParLeWriterReel();

    final String cleMoteur = 'C${kNumC}_${mesure.dateStr}'; // cf. `_buildCourseKey`
    final List<MouvementCote> sousCleProd =
        CoteTrackerService.instance.mouvementsPourCourse(mesure.cleProd);
    final List<MouvementCote> sousCleMoteur =
        CoteTrackerService.instance.mouvementsPourCourse(cleMoteur);

    // ignore: avoid_print
    print('─── MESURE Z2-A / N1 (producteurs) ─────────────────────────');
    // ignore: avoid_print
    print('  buildCourseKey("R$kNumR", $kNumC, "$kDateReference") -> « $cleUi »');
    // ignore: avoid_print
    print('  writer réel (demarrer x2)   : « ${mesure.cleProd} »');
    // ignore: avoid_print
    print('  clé du moteur IA (par lecture) : « $cleMoteur »');
    // ignore: avoid_print
    print('  mouvements sous la clé de production : ${sousCleProd.length}');
    // ignore: avoid_print
    print('  mouvements sous la clé du moteur     : ${sousCleMoteur.length}');
    // ignore: avoid_print
    print('  requêtes réseau émises : ${_urlsAppelees.map((u) => u.path).toSet()}');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    // TÉMOIN — le réseau simulé a bien été sollicité, et 2 fois.
    expect(_appelsReseau, 2,
        reason: 'TÉMOIN : deux polls réels doivent produire deux snapshots');
    expect(_urlsAppelees.every((u) => u.path.contains('/participants')), isTrue,
        reason: 'TÉMOIN : seul l\'endpoint participants est attendu — mesuré : '
            '${_urlsAppelees.map((u) => u.path).toList()}');

    // ASSERTION 1 — format exact du producteur public.
    expect(cleUi, 'R${kNumR}C${kNumC}_$kDateReference',
        reason: 'buildCourseKey() doit produire R{numR}C{numCourse}_{ddmmyyyy}');

    // ASSERTION 2 — le writer réel écrit dans le MÊME espace.
    expect(sousCleProd, hasLength(1),
        reason: 'le writer de production doit ranger la course sous « ${mesure.cleProd} »');
    expect(sousCleProd.single.numero, kNumeroCheval);
    expect(sousCleProd.single.variationPct, closeTo(kVariationAttendue, 0.01),
        reason: 'variation mesurée : ${sousCleProd.single.variationPct}');

    // ASSERTION 3 — et NULLEMENT dans l'espace du moteur.
    expect(sousCleMoteur, isEmpty,
        reason: 'le writer n\'écrit JAMAIS sous « $cleMoteur »');
  });

  // ───────────────────────────────────────────────────────────────────────
  //  Z2-B — L'ESPACE DE CLÉS INTERROGÉ PAR LE MOTEUR EST DISJOINT
  //  Attendu : ROUGE (N1).
  // ───────────────────────────────────────────────────────────────────────
  test('Z2-B / N1 — un mouvement réel de production est invisible sous la clé du moteur', () async {
    final ({String dateStr, String heure, String cleProd}) mesure =
        await _faireEcrireParLeWriterReel();
    final String cleMoteur = 'C${kNumC}_${mesure.dateStr}';

    // TÉMOIN 1 — la donnée EXISTE et est lisible sous la clé de production.
    final MouvementCote? vuSousCleProd =
        CoteTrackerService.instance.mouvementPourPartant(mesure.cleProd, kNumeroCheval);
    expect(vuSousCleProd, isNotNull,
        reason: 'TÉMOIN : la donnée doit être présente sous « ${mesure.cleProd} »');
    expect(vuSousCleProd!.variationPct, closeTo(kVariationAttendue, 0.01));

    // TÉMOIN 2 — la course est bien dans la fenêtre des 30 min
    // (`scoreCritereR` renvoie null hors champ de la map, pas hors fenêtre ;
    //  la fenêtre est vérifiée ici explicitement).
    final ZtCourse course =
        _courseR1C10(dateStr: mesure.dateStr, heure: mesure.heure);
    expect(CoteTrackerService.instance.estDansFenetre(course), isTrue,
        reason: 'TÉMOIN : le critère R doit être ACTIF pour cette course '
            '(départ ${mesure.heure}, fenêtre 0-30 min)');

    // MESURE — ce que voit le moteur, avec la clé qu'il construit lui-même.
    final MouvementCote? vuSousCleMoteur =
        CoteTrackerService.instance.mouvementPourPartant(cleMoteur, kNumeroCheval);
    final double? scoreMoteur =
        CoteTrackerService.instance.scoreCritereR(cleMoteur, kNumeroCheval);

    // ignore: avoid_print
    print('─── MESURE Z2-B / N1 (conséquences) ────────────────────────');
    // ignore: avoid_print
    print('  clé lue par la production : « ${mesure.cleProd} » -> '
        'variation ${vuSousCleProd.variationPct} %, score ${vuSousCleProd.scoreIA}');
    // ignore: avoid_print
    print('  clé lue par le moteur IA  : « $cleMoteur » -> ${vuSousCleMoteur ?? "NULL"}');
    // ignore: avoid_print
    print('  scoreCritereR(clé moteur) : ${scoreMoteur ?? "NULL"}');
    // ignore: avoid_print
    print('  ATTENDU : 75.0  (le mouvement −20 % est réel et dans la fenêtre)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    // ASSERTION MÉTIER — le moteur doit voir le mouvement réel de production.
    expect(scoreMoteur, isNotNull,
        reason: 'N1 (ia_pronostic_engine.dart:823-839 vs cote_tracker_service.dart:391) — '
            'le moteur interroge « $cleMoteur » alors que la production écrit sous '
            '« ${mesure.cleProd} ». `mouvementPourPartant()` ne trouve aucune entrée et '
            'renvoie null : le critère R (6 % du score) reste neutralisé à 50.0 alors '
            'qu\'un mouvement de ${vuSousCleProd.variationPct.toStringAsFixed(0)} % '
            'est réellement disponible.');
  });

  // ───────────────────────────────────────────────────────────────────────
  //  Z2-C — CONTRÔLE DE NON-ARTIFICIALITÉ
  //  Attendu : VERT. Quand la clé CONCORDE, la lecture fonctionne et le score
  //  vaut exactement la tranche du barème. Cela prouve que l'échec de Z2-B
  //  provient de la divergence d'identifiant, et non d'un harnais défaillant.
  // ───────────────────────────────────────────────────────────────────────
  test('Z2-C / N1 — contrôle : avec la clé de production, le score est lu à 75.0', () async {
    final ({String dateStr, String heure, String cleProd}) mesure =
        await _faireEcrireParLeWriterReel();

    final double? scoreProd =
        CoteTrackerService.instance.scoreCritereR(mesure.cleProd, kNumeroCheval);

    // ignore: avoid_print
    print('─── MESURE Z2-C / N1 (contrôle) ────────────────────────────');
    // ignore: avoid_print
    print('  scoreCritereR("${mesure.cleProd}", "$kNumeroCheval") = ${scoreProd ?? "NULL"}');
    // ignore: avoid_print
    print('  attendu : 75.0  (variation −20 % → tranche « <= -20 »)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(scoreProd, kScoreAttendu,
        reason: 'CONTRÔLE : le harnais sait lire un mouvement quand la clé '
            'concorde. Donc le null de Z2-B vient bien de la DIVERGENCE '
            'd\'identifiant, pas d\'un défaut de montage du test.');
  });

  // ───────────────────────────────────────────────────────────────────────
  //  Z2-D — CONSTAT COMPLÉMENTAIRE (distinct de N1, non corrigé ici)
  //  `ZtPartant.copyWith()` (`zt_models.dart:312-346`) ne transporte PAS
  //  `scoreMouvementCote`. Or `analyserCourse()` retourne des `copyWith`.
  //  Conséquence : même avec un identifiant aligné, le critère R ne
  //  parviendrait pas aux partants rendus. Ce test le MESURE, pour que la
  //  future correction de N1 ne soit pas présentée comme suffisante.
  // ───────────────────────────────────────────────────────────────────────
  test('Z2-D / N1 — copyWith() perd scoreMouvementCote (mécanisme distinct)', () {
    final ZtPartant original = _partant16();
    original.scoreMouvementCote = kScoreAttendu;

    final ZtPartant copie = original.copyWith(scoreIA: 88.0);

    // TÉMOIN : le champ est bien mutable et vaut 75.0 sur l'original.
    expect(original.scoreMouvementCote, kScoreAttendu);

    // ignore: avoid_print
    print('─── MESURE Z2-D / N1 (mécanisme complémentaire) ────────────');
    // ignore: avoid_print
    print('  original.scoreMouvementCote  = ${original.scoreMouvementCote}');
    // ignore: avoid_print
    print('  copie.scoreMouvementCote     = ${copie.scoreMouvementCote}');
    // ignore: avoid_print
    print('  ATTENDU : 75.0 conservé par copyWith()');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(copie.scoreMouvementCote, kScoreAttendu,
        reason: 'Z2-D (zt_models.dart:312-346) — `copyWith()` ne recopie pas '
            '`scoreMouvementCote` : la valeur retombe à la valeur par défaut '
            '${copie.scoreMouvementCote}. Tout partant retourné par '
            '`analyserCourse()` (qui termine par `copyWith`) perd donc le score '
            'du critère R, indépendamment de N1. CONSTAT SÉPARÉ, NON CORRIGÉ.');
  });
}
