// ═══════════════════════════════════════════════════════════════════════════
//  Z3 — DIAGNOSTIC N5 / N6 : DIVERGENCE DES PÉRIODES STATISTIQUES
//
//  OBJET : comparer les périodes statistiques des composants RÉELLEMENT
//          utilisés par l'application :
//            • Aujourd'hui ;
//            • 7 jours calendaires (6 jours historiques + aujourd'hui) ;
//            • Période personnalisée incluant aujourd'hui ;
//            • bornes de journée et passage à minuit.
//
//  AUCUNE MODIFICATION DE `lib/`. `analyseJourneeComplete()` NON APPELÉE.
//  AUCUNE ÉCRITURE D'APPRENTISSAGE (aucun poids, seuil, ELO, gradient).
//
//  ── COMPOSANTS TESTÉS (vivants, atteignables) ─────────────────────────────
//    • `IaDialogDetailTypePari` (`ia_performance_dialogs.dart:73`) — PUBLIC.
//      VIVANT : importé par `ia_performance_screen.dart`, `ia_tab_conseils.dart`
//      et `ia_tab_stats.dart`. Son filtre 7 j est
//      `DateTime.now().subtract(const Duration(days: 7))` (`:120-126`).
//    • `StatsPrecisionParType.statsPourPeriode()` (`ia_memory_service.dart`
//      ~7420) — PUBLIC. C'est la FONCTION EXACTE appelée par le filtre
//      « Période personnalisée » de `ia_performance_screen._statsFiltre`
//      (`ia_performance_screen.dart:3891-3893`) et par son filtre 7 j
//      (`:3866-3867`).
//    • `IaMemoryService.precisionAujourdhuiDepuisPronostics` (`:683-731`) —
//      PUBLIC. C'est la SOURCE EXACTE du filtre « Aujourd'hui »
//      (`ia_performance_screen.dart:3888-3890`) et du volet « aujourd'hui »
//      du filtre 7 j (`:3869-3870`).
//
//  ── COMPOSANTS NON TESTÉS, ET POURQUOI ──────────────────────────────────
//    • `SectionPrecisionIA` (`ia_precision_widget.dart`) et
//      `_DialogDetailTypePari` (`ia_dialog_detail_type_pari.dart`) :
//      ces deux fichiers ont été SUPPRIMÉS en BL1-A18 après mesure
//      (0 importateur, 0 instanciation). Les homonymes VIVANTS sont
//      `_buildSectionPrecisionIA` (privé, dans `ia_performance_screen.dart`)
//      et `IaDialogDetailTypePari` (public, dans `ia_performance_dialogs.dart`).
//      Les tester ici n'aurait plus d'objet.
//    • `ia_performance_screen._statsFiltre` et `ia_calendrier_tab
//      ._estDansPeriodeStats` sont PRIVÉES. On mesure donc leurs DÉLÉGUÉS
//      PUBLICS exacts (voir ci-dessus) et on rapporte par LECTURE ce que les
//      deux écrans font de différent.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/widgets/ia/ia_performance_dialogs.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  CONSTANTES
// ═══════════════════════════════════════════════════════════════════════════

const String kTypePari = 'Gagnant+Placé';

/// Clé de persistance de la précision par type (`ia_memory_service.dart:101`).
const String kPrecisionKey = 'ia_precision_v2';

/// Clé de persistance des pronostics (`ia_memory_service.dart:96`).
const String kPronosticsKey = 'ia_pronostics_v2';

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _cleCourse(DateTime d, String suffixe) =>
    'R1C${suffixe}_${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}${d.year}';

// ═══════════════════════════════════════════════════════════════════════════
//  HELPERS DE SEMIS
// ═══════════════════════════════════════════════════════════════════════════

/// Pronostic RÉSOLU et BON pour `Gagnant+Placé` : `_estBonConseilParType`
/// (`ia_memory_service.dart:5558-5561`) exige `rang != null && rang <= 3`.
IaPronostic _pronostic({
  required DateTime datePronostic,
  required String suffixe,
  int rang = 2,
  String? typePari = kTypePari,
}) =>
    IaPronostic(
      courseKey: _cleCourse(datePronostic, suffixe),
      nomCourse: 'COURSE $suffixe',
      hippodrome: 'SAINT-CLOUD',
      discipline: 'Plat',
      datePronostic: datePronostic,
      scoresIA: const <String, double>{'16': 89.0, '7': 70.0, '2': 60.0},
      scoresCriteres: const <String, ScoresCriteres>{},
      varianceScores: 1.0,
      arriveeReelle: const <int>[7, 16, 2],
      dateResultat: datePronostic,
      resultatsReels: true,
      rangFavoriIaDansArrivee: rang,
      nbTop3DansArriveeReelle: 3,
      nbTop5DansArriveeReelle: 3,
      scorePerformance: 80.0,
      diagnosticApprentissage: '',
      confiancePredite: 70.0,
      typePariConseille: typePari,
      tauxReussiteAuMoment: null,
      precisionIA: null,
      favoriIaNom: 'SIM CARD',
      coteFavoriPmu: 18.0,
      cotesPmuParNumero: const <String, double>{'16': 18.0},
    );

/// `StatsPrecisionParType` dont `historiqueComplet` contient EXACTEMENT les
/// jours demandés. Format d'entrée : `{'d': 'YYYY-MM-DD', 'nb','bon','ord','des'}`
/// (cf. `statsPourPeriode`, `ia_memory_service.dart` ~7420).
StatsPrecisionParType _stats({
  required Map<String, int> parJour, // 'YYYY-MM-DD' -> nb
  int bonsParJour = 0,
}) {
  final hist = parJour.entries
      .map((e) => <String, dynamic>{
            'd': e.key,
            'nb': e.value,
            'bon': bonsParJour,
            'ord': 0,
            'des': 0,
          })
      .toList()
    ..sort((a, b) => (a['d'] as String).compareTo(b['d'] as String));

  final nb = parJour.values.fold(0, (a, b) => a + b);
  final bons = bonsParJour * parJour.length;
  return StatsPrecisionParType(
    typePari: kTypePari,
    nbTotal: nb,
    nbBons: bons,
    nbTotalAll: nb,
    nbBonsAll: bons,
    historique: hist,
    historiqueComplet: hist,
  );
}

/// Sème le disque simulé, puis recharge `IaMemoryService` par son chemin
/// public de production. `setMockInitialValues` remplace le store ET remet
/// `_completer` à zéro (shared_preferences_legacy.dart:279-291) : un
/// `getInstance()` postérieur relit donc bien ce qui vient d'être semé.
Future<void> _semer({
  required StatsPrecisionParType? stats,
  required List<IaPronostic> pronostics,
}) async {
  final Map<String, Object> valeurs = <String, Object>{};
  if (stats != null) {
    valeurs[kPrecisionKey] = json.encode(<String, dynamic>{
      stats.typePari: stats.toJson(),
    });
  }
  valeurs[kPronosticsKey] =
      pronostics.map((p) => json.encode(p.toJson())).toList();

  // ★ MESURÉ : `_load()` (ia_memory_service.dart:2361-2375) exécute une
  //   migration one-shot « v9.95 » qui RECALCULE `_precisionParType` depuis
  //   les pronostics bruts dès que le flag `ia_precision_migrated_v3` est
  //   absent et qu'il existe au moins un pronostic résolu. Cette migration
  //   ÉCRASE donc la fixture `ia_precision_v2` semée, et écrit le flag.
  //
  //   Elle est PRÉ-EXISTANTE (aucune modification apportée ici) mais rendrait
  //   la mesure non déterministe. On la neutralise en posant le flag dans le
  //   semis : la fixture reste intacte, et aucun test ne dépend de son ordre
  //   d'exécution.
  valeurs['ia_precision_migrated_v3'] = true;

  SharedPreferences.setMockInitialValues(valeurs);
  await IaMemoryService.instance.recharger();
}

/// L'objet `StatsPrecisionParType` RÉELLEMENT chargé en mémoire par le
/// service pour `kTypePari` — et non la copie locale du fixture.
StatsPrecisionParType _statsChargee() {
  final list = IaMemoryService.instance.precisionParType
      .where((p) => p.typePari == kTypePari)
      .toList();
  expect(list, hasLength(1),
      reason: 'TÉMOIN : exactement une entrée « $kTypePari » doit être chargée '
          '— mesuré : ${IaMemoryService.instance.precisionParType.map((p) => p.typePari).toList()}');
  return list.single;
}

// ═══════════════════════════════════════════════════════════════════════════
//  MONTAGE DU DIALOGUE VIVANT
// ═══════════════════════════════════════════════════════════════════════════

/// Monte `IaDialogDetailTypePari` — le dialogue RÉEL — avec le filtre demandé.
///
/// `buildCarte` est un STUB qui rend la `courseKey` du pronostic : il permet
/// de compter EXACTEMENT les pronostics retenus par le filtre sans dépendre
/// d'une mise en page complexe. `chipStat` est également un stub.
Future<void> _monterDialogue(
  WidgetTester tester, {
  required StatsPrecisionParType stats,
  required String? filtre,
  DateTime? debut,
  DateTime? fin,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: IaDialogDetailTypePari(
          stats: stats,
          filtreInitial: filtre,
          filtreDebutInitial: debut,
          filtreFinInitial: fin,
          buildCarte: (pr, type) =>
              Text('CARTE::${pr.courseKey}', key: ValueKey<String>(pr.courseKey)),
          chipStat: (txt, coul) => Text('CHIP::$txt'),
          green: const Color(0xFF4CAF7D),
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
  await tester.binding.setSurfaceSize(null);
}

// ═══════════════════════════════════════════════════════════════════════════
//  TESTS
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ───────────────────────────────────────────────────────────────────────
  //  Z3-A — « AUJOURD'HUI » ET « PÉRIODE PERSONNALISÉE INCLUANT AUJOURD'HUI »
  //         NE LISENT PAS LA MÊME SOURCE
  //  Attendu : ROUGE (N6).
  //
  //  Le filtre « Aujourd'hui » lit `precisionAujourdhuiDepuisPronostics`
  //  (pronostics bruts, temps réel). Le filtre « Période personnalisée »
  //  délègue à `statsPourPeriode`, qui lit `historiqueComplet` — alimenté
  //  UNIQUEMENT par `analyseJourneeComplete()`, donc VIDE pour aujourd'hui
  //  tant que l'analyse du soir n'a pas eu lieu (le code le dit lui-même,
  //  `ia_performance_screen.dart:3887`).
  //
  //  Conséquence mesurable : sur la MÊME journée, l'un affiche N, l'autre 0.
  // ───────────────────────────────────────────────────────────────────────
  test('Z3-A / N6 — même jour, « Aujourd\'hui » et « Période » ne donnent pas le même total',
      () async {
    final DateTime now = DateTime.now();
    final DateTime debutJour = DateTime(now.year, now.month, now.day);

    // Deux pronostics RÉSOLUS et BONS aujourd'hui, de type `Gagnant+Placé`.
    final pronostics = <IaPronostic>[
      _pronostic(datePronostic: debutJour.add(const Duration(hours: 14)), suffixe: 'A'),
      _pronostic(datePronostic: debutJour.add(const Duration(hours: 15)), suffixe: 'B'),
    ];

    // `historiqueComplet` NE contient PAS aujourd'hui : c'est l'état réel
    // d'une application consultée dans la journée, avant l'analyse du soir.
    final stats = _stats(parJour: <String, int>{
      _iso(DateTime(now.year, now.month, now.day - 2)): 4,
      _iso(DateTime(now.year, now.month, now.day - 1)): 3,
    });

    await _semer(stats: stats, pronostics: pronostics);

    // DÉLÉGUÉ PUBLIC EXACT du filtre « Aujourd'hui » (ia_performance_screen.dart).
    // ★ LOT Z3-A : l'écran lit désormais `statsJourUnique(auj, auj)`, qui agrège
    //   `precisionAujourdhuiDepuisPronostics` ET `historiqueComplet`. On mesure
    //   donc la MÊME fonction que l'écran, au lieu de l'une de ses deux sources.
    final DateTime aujJ =
        DateTime(now.year, now.month, now.day);
    final Map<String, int> auj =
        _statsChargee().statsJourUnique(aujJ, aujJ);

    // DÉLÉGUÉ PUBLIC EXACT du filtre « Période personnalisée » quand la
    // plage inclut aujourd'hui (ia_performance_screen.dart).
    // ★ LOT Z3-A : l'écran décompose [début .. hier] (statsPourPeriode) +
    //   aujourd'hui (statsJourUnique). Pour une plage réduite à aujourd'hui,
    //   le volet « passé » est vide : on mesure donc `statsJourUnique`.
    // ⚠ On interroge l'objet RÉELLEMENT CHARGÉ par le service, pas la copie
    //   du fixture : c'est lui que l'écran reçoit via `precisionParType`.
    final Map<String, int> periodeAuj =
        _statsChargee().statsJourUnique(debutJour, debutJour);

    // ignore: avoid_print
    print('─── MESURE Z3-A / N6 (« aujourd\'hui » vs « période ») ─────');
    // ignore: avoid_print
    print('  TÉMOIN pronostics chargés        : ${IaMemoryService.instance.pronostics.length}');
    // ignore: avoid_print
    print('  TÉMOIN stats chargées            : ${IaMemoryService.instance.precisionParType.length}');
    // ignore: avoid_print
    print('  source « Aujourd\'hui » (pronostics) : nb=${auj['nb']} bons=${auj['bons']}');
    // ignore: avoid_print
    print('  source « Période » (historiqueComplet) : nb=${periodeAuj['nb']} bons=${periodeAuj['bons']}');
    // ignore: avoid_print
    print('  jours de historiqueComplet : ${_statsChargee().historiqueComplet.map((e) => e['d']).toList()}');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    // TÉMOINS — le harnais a bien chargé les deux sources.
    expect(IaMemoryService.instance.pronostics, hasLength(2),
        reason: 'TÉMOIN : les pronostics doivent être chargés depuis le disque simulé');
    expect(IaMemoryService.instance.precisionParType, isNotEmpty,
        reason: 'TÉMOIN : les stats par type doivent être chargées');

    // ASSERTION 1 — « Aujourd'hui » voit réellement les 2 pronostics.
    expect(auj['nb'], 2,
        reason: 'le filtre Aujourd\'hui doit compter les 2 pronostics résolus du jour');

    // ASSERTION 2 — le total obtenu doit être le MÊME que par « Période »
    //               restreinte à aujourd'hui. C'est la cohérence attendue par
    //               l'utilisateur qui compare deux filtres sur la même journée.
    expect(periodeAuj['nb'], auj['nb'],
        reason: 'N6 — sur la MÊME journée, « Aujourd\'hui » lit '
            '`precisionAujourdhuiDepuisPronostics` (nb=${auj['nb']}) tandis que '
            '« Période personnalisée incluant aujourd\'hui » délègue à '
            '`statsPourPeriode` sur `historiqueComplet` (nb=${periodeAuj['nb']}) : '
            '`historiqueComplet` n\'est alimenté que par `analyseJourneeComplete()` '
            '(ia_performance_screen.dart:3887), donc il est vide pour aujourd\'hui '
            'tant que l\'analyse du soir n\'a pas eu lieu. Les deux filtres '
            'affichent des totaux différents pour la même journée.');
  });

  // ───────────────────────────────────────────────────────────────────────
  //  Z3-B — « 7 JOURS » DU DIALOGUE VIVANT DÉBORDE D'UN JOUR CALENDAIRE
  //  Attendu : ROUGE (N5).
  //
  //  Le dialogue vivant filtre avec `DateTime.now() - 7 jours`, soit 7×24 h
  //  (`ia_performance_dialogs.dart:120-126`). Une course datée d'il y a
  //  7 jours calendaires mais plus tard dans la journée tombe donc DANS la
  //  fenêtre. La définition attendue est « 6 jours historiques + aujourd'hui »
  //  = 7 DATES : `d-6`, `d-5`, `d-4`, `d-3`, `d-2`, `d-1`, `d`.
  // ───────────────────────────────────────────────────────────────────────
  testWidgets('Z3-B / N5 — le filtre « 7 jrs » du dialogue vivant inclut d-7 (8 dates)',
      (tester) async {
    final DateTime now = DateTime.now();
    final DateTime debutJour = DateTime(now.year, now.month, now.day);

    // Course à d-7, à 23 h 59 : hors des 7 dates attendues (d-6 .. d).
    final DateTime dateD7 = DateTime(now.year, now.month, now.day - 7, 23, 59, 59);
    // Course à d-6, à 12 h : dans les 7 dates attendues.
    final DateTime dateD6 = DateTime(now.year, now.month, now.day - 6, 12, 0, 0);

    final p7 = _pronostic(datePronostic: dateD7, suffixe: 'D7');
    final p6 = _pronostic(datePronostic: dateD6, suffixe: 'D6');
    final stats = _stats(parJour: <String, int>{_iso(dateD6): 1});

    await _semer(stats: stats, pronostics: <IaPronostic>[p7, p6]);

    await _monterDialogue(tester, stats: stats, filtre: '7j');

    final bool d7Present = find
        .byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(p7.courseKey))
        .evaluate()
        .isNotEmpty;
    final bool d6Present = find
        .byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(p6.courseKey))
        .evaluate()
        .isNotEmpty;

    // ignore: avoid_print
    print('─── MESURE Z3-B / N5 (« 7 jrs » du dialogue vivant) ────────');
    // ignore: avoid_print
    print('  aujourd\'hui = ${_iso(debutJour)}');
    // ignore: avoid_print
    print('  pronostic d-7 (${_iso(dateD7)} 23:59:59) rendu ? $d7Present');
    // ignore: avoid_print
    print('  pronostic d-6 (${_iso(dateD6)} 12:00:00) rendu ? $d6Present');
    // ignore: avoid_print
    print('  fenêtre attendue : d-6 .. d  (7 DATES)');
    // ignore: avoid_print
    print('  fenêtre du code  : DateTime.now() - Duration(days: 7)  (7x24 h)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    // TÉMOIN — le montage rend bien les cartes des pronostics retenus.
    expect(d6Present, isTrue,
        reason: 'TÉMOIN : le pronostic de d-6 doit être rendu — sans cela le '
            'harnais ne prouve rien');

    // ASSERTION — d-7 doit être EXCLU de « 7 derniers jours ».
    expect(d7Present, isFalse,
        reason: 'N5 (ia_performance_dialogs.dart:120-126) — le filtre « 7 jrs » '
            'utilise `DateTime.now().subtract(const Duration(days: 7))`, soit '
            '7x24 h et non 7 dates. Le pronostic daté du ${_iso(dateD7)} '
            '23:59:59 (il y a 7 jours calendaires) est donc INCLUS alors que '
            '« 7 derniers jours » doit signifier d-6 .. d.');

    await _demonter(tester);
  });

  // ───────────────────────────────────────────────────────────────────────
  //  Z3-C — « 7 JOURS » VU PAR LE DÉLÉGUÉ PUBLIC DE `ia_performance_screen`
  //  Attendu : VERT. Ce contrôle VERROUILLE la fenêtre correcte
  //  (d-6 .. d-1 pour la partie historique) et interdit de « corriger » N5
  //  en cassant le seul consommateur qui est déjà juste.
  // ───────────────────────────────────────────────────────────────────────
  test('Z3-C / N5 — contrôle : la fenêtre historique de « 7 j » couvre bien d-6 .. d-1',
      () async {
    final DateTime now = DateTime.now();
    final DateTime debutJour = DateTime(now.year, now.month, now.day);
    final DateTime debutHist = debutJour.subtract(const Duration(days: 6));
    final DateTime finHist = DateTime(now.year, now.month, now.day - 1, 23, 59, 59, 999);

    final stats = _stats(parJour: <String, int>{
      _iso(DateTime(now.year, now.month, now.day - 8)): 100, // hors fenêtre
      _iso(DateTime(now.year, now.month, now.day - 7)): 100, // hors fenêtre
      _iso(debutHist): 1, // d-6 : PREMIER jour inclus
      _iso(DateTime(now.year, now.month, now.day - 3)): 1,
      _iso(DateTime(now.year, now.month, now.day - 1)): 1, // d-1 : DERNIER inclus
      _iso(debutJour): 100, // aujourd'hui : HORS de la partie historique
    });

    final Map<String, int> res = stats.statsPourPeriode(debutHist, finHist);

    // ignore: avoid_print
    print('─── MESURE Z3-C / N5 (contrôle de la fenêtre historique) ────');
    // ignore: avoid_print
    print('  borne début = ${_iso(debutHist)}  borne fin = ${_iso(finHist)}');
    // ignore: avoid_print
    print('  statsPourPeriode -> nb=${res['nb']} bons=${res['bons']}');
    // ignore: avoid_print
    print('  attendu nb=3  (d-6 + d-3 + d-1 ; d-7, d-8 et aujourd\'hui exclus)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(res['nb'], 3,
        reason: 'CONTRÔLE : la fenêtre d-6 .. d-1 doit retenir exactement les '
            '3 jours semés dans cet intervalle, et exclure d-7, d-8 ainsi '
            'qu\'aujourd\'hui (traité séparément en temps réel).');
  });

  // ───────────────────────────────────────────────────────────────────────
  //  Z3-D — BORNE DE MINUIT : COMPORTEMENT EXACT DE « AUJOURD'HUI »
  //  Attendu : VERT. Ce n'est PAS un rouge : le débordement de 3 minutes est
  //  DÉLIBÉRÉ et commenté dans le code (`ia_memory_service.dart:691-693`,
  //  « Fenêtre élargie à -3 minutes … pour couvrir les courses finissant
  //  entre 23h57 et minuit »). Le test FIXE la borne mesurée pour servir de
  //  non-régression, et rend l'arbitrage explicite.
  // ───────────────────────────────────────────────────────────────────────
  test('Z3-D / N6 — passage à minuit : un pronostic de la veille 23:58 est compté aujourd\'hui',
      () async {
    final DateTime now = DateTime.now();
    final DateTime debutJour = DateTime(now.year, now.month, now.day);

    // Trois pronostics autour de la borne `debutJour - 3 min`.
    final DateTime veille2358 = debutJour.subtract(const Duration(minutes: 2));
    final DateTime veille2356 = debutJour.subtract(const Duration(minutes: 4));
    final DateTime matin0005 = debutJour.add(const Duration(minutes: 5));

    await _semer(
      stats: null,
      pronostics: <IaPronostic>[
        _pronostic(datePronostic: veille2358, suffixe: 'V58'), // dans la fenêtre
        _pronostic(datePronostic: veille2356, suffixe: 'V56'), // hors fenêtre
        _pronostic(datePronostic: matin0005, suffixe: 'M05'), // dans la fenêtre
      ],
    );

    final Map<String, Map<String, int>> res =
        IaMemoryService.instance.precisionAujourdhuiDepuisPronostics;
    final Map<String, int> auj = res[kTypePari] ??
        <String, int>{'nb': 0, 'bons': 0, 'ordre': 0, 'desordre': 0};

    // ignore: avoid_print
    print('─── MESURE Z3-D / N6 (borne de minuit de « Aujourd\'hui ») ─');
    // ignore: avoid_print
    print('  debutJour = $debutJour');
    // ignore: avoid_print
    print('  fenêtre réelle = debutJour - 3 min  ..  debutJour + 24 h');
    // ignore: avoid_print
    print('  veille 23:58 (debutJour - 2 min) -> compté ? ${veille2358.isAfter(debutJour.subtract(const Duration(minutes: 3)))}');
    // ignore: avoid_print
    print('  veille 23:56 (debutJour - 4 min) -> compté ? ${veille2356.isAfter(debutJour.subtract(const Duration(minutes: 3)))}');
    // ignore: avoid_print
    print('  total retenu pour « Aujourd\'hui » : nb=${auj['nb']} bons=${auj['bons']}');
    // ignore: avoid_print
    print('  attendu nb=2  (23:58 + 00:05 ; 23:56 exclu)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(auj['nb'], 2,
        reason: 'COMPORTEMENT MESURÉ — `precisionAujourdhuiDepuisPronostics` '
            '(ia_memory_service.dart:683-731) élargit la journée de 3 minutes '
            'vers le passé : le pronostic de la veille à 23:58 est compté dans '
            '« Aujourd\'hui », celui de 23:56 ne l\'est pas. Ce débordement est '
            'DÉLIBÉRÉ et commenté dans le code ; il est ici FIGÉ pour '
            'non-régression, sans jugement de valeur.');
  });

  // ───────────────────────────────────────────────────────────────────────
  //  Z3-E — PÉRIODE PERSONNALISÉE : BORNES DE JOURNÉE INCLUSIVES
  //  Attendu : VERT. Vérifie que `statsPourPeriode` compare des DATES (minuit
  //  à minuit), donc que la borne de fin est bien INCLUSIVE.
  // ───────────────────────────────────────────────────────────────────────
  test('Z3-E / N6 — la période personnalisée est inclusive aux deux bornes', () {
    final DateTime d = DateTime(2026, 11, 19);

    final stats = _stats(parJour: <String, int>{
      '2026-11-18': 100, // veille : exclu
      '2026-11-19': 7, // borne début ET fin
      '2026-11-20': 100, // lendemain : exclu
    });

    final Map<String, int> res = stats.statsPourPeriode(d, d);

    // ignore: avoid_print
    print('─── MESURE Z3-E / N6 (bornes inclusives d\'une période) ─────');
    // ignore: avoid_print
    print('  statsPourPeriode(2026-11-19, 2026-11-19) -> nb=${res['nb']}');
    // ignore: avoid_print
    print('  attendu nb=7  (une seule journée, bornes inclusives)');
    // ignore: avoid_print
    print('─────────────────────────────────────────────────────────────');

    expect(res['nb'], 7,
        reason: 'CONTRÔLE : les deux bornes doivent être inclusives '
            '(`d.isBefore(debut) || d.isAfter(fin)` → exclusion hors bornes '
            'seulement).');
  });
}
