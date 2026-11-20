// ═══════════════════════════════════════════════════════════════════════════
//  A-0 / P2 — VALIDATION FONCTIONNELLE DE LA RESTAURATION DEPUIS LE PROFIL
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE lib/.
//
//  ── CE QUE CE FICHIER EXÉCUTE RÉELLEMENT ──────────────────────────────────
//  Il monte la VÉRITABLE `ProfileBackupSection` (widget de production utilisé
//  par l'onglet Profil), appuie sur le VÉRITABLE bouton « Importer une
//  sauvegarde », confirme dans le VÉRITABLE dialogue « Importer ? », et laisse
//  courir la VRAIE méthode privée `_importer()` — qui contient la protection
//  P2 (`profile_profil_tab.dart:1652`).
//
//  Il ne teste PAS une copie de la logique : la boucle de synchronisation
//  `TrackedCourse → UserPrediction` exécutée est celle du fichier de
//  production, non réécrite ici.
//
//  ── POURQUOI L'INJECTION `OperationsSauvegarde` EST LÉGITIME ─────────────
//  `_importer()` commence par `_ops.importerFichier()`. En production, `_ops`
//  vaut `OperationsSauvegarde.reelles()`, c'est-à-dire un sélecteur de
//  fichier natif. Un test ne peut pas piloter un sélecteur natif.
//  `OperationsSauvegarde` est un POINT D'INJECTION PRÉEXISTANT, livré par le
//  Lot A7 (`profile_profil_tab.dart:1317-1347`) et déjà utilisé par le test
//  `a7_37_visibilite_avertissements_test.dart` : on réutilise ce mécanisme
//  existant au lieu d'en inventer un autre.
//
//  La simulation ne porte QUE sur le RETOUR de l'import (`ImportResult
//  succes: true`). Tout ce qui nous intéresse — le rechargement du provider,
//  le rechargement d'`AlertService`, et la boucle de synchronisation P2 —
//  est exécuté par la PRODUCTION.
//
//  ── Ce qui est vérifié ────────────────────────────────────────────────────
//    • un Gagnant+Placé présent sur une course restaurée et RÉSOLUE ne reçoit
//      ni `isCorrect` ni `montantMise` (protégé par P2) ;
//    • un Simple Gagnant sur la MÊME course restaurée reçoit bien les siens
//      (non-régression du même chemin, dans le même passage) ;
//    • la restauration elle-même n'est PAS cassée : le dialogue de succès
//      s'affiche, donc `result.succes` a bien été traité.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';
import 'package:pronostic_hippique/widgets/profile/profile_profil_tab.dart';

// ─────────────────────────── Constantes ────────────────────────────────────

const int kNumR = 1;
const int kNumC = 11;
const int kNumeroCheval = 7;

const String kNomCourse = 'PRIX A0 RESTAURATION';
const String kHippodrome = 'VINCENNES';

const double kMise = 20.0;
const double kCote = 18.00;
const double kGainFictif = (kCote * kMise) - kMise; // 340,00 €

/// Libellés EXACTS de la production : un renommage doit faire échouer ce test.
const String kBtnImporter = 'Importer une sauvegarde';
const String kBtnContinuer = 'Continuer';
const String kTitreErreur = 'Erreur';
const String kTitreSucces = 'Restauration réussie !';

const Map<String, double> _poidsDefaut = {
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
  'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
  'mouvCote': 0.06, 'placeDepart': 0.03,
};

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

// ─────────────────────────── Fixtures ──────────────────────────────────────

UserPrediction _pred(String typePari, {required String id}) => UserPrediction(
      id: id,
      dateStr: _ddmmyyyy(DateTime.now()),
      numReunion: kNumR,
      numCourse: kNumC,
      nomCourse: kNomCourse,
      hippodrome: kHippodrome,
      numeroCheval: kNumeroCheval,
      nomCheval: 'CHEVAL_$kNumeroCheval',
      cote: kCote,
      typePari: typePari,
      createdAt: DateTime.now(),
      scoreIA: 89.0,
      montantMise: kMise,
      numerosJoues: const <int>[kNumeroCheval],
    );

/// Course restaurée DÉJÀ RÉSOLUE et GAGNANTE : condition d'atteinte de la
/// boucle de synchronisation (`if (tc.isGagne == null) continue;`, l.1637).
TrackedCourse _suiviGagne(DateTime dep) => TrackedCourse(
      numReunion: kNumR,
      numCourse: kNumC,
      nomCourse: kNomCourse,
      hippodrome: kHippodrome,
      heureDepart: dep,
      nomCheval: 'CHEVAL_$kNumeroCheval',
      numeroCheval: kNumeroCheval,
      miseEngagee: kMise,
      typePari: 'Gagnant+Placé',
      numerosJoues: const <int>[kNumeroCheval],
      cote: kCote,
      scoreIA: 89.0,
      isGagne: true,
      arriveeFinale: const <int>[7, 4, 2, 9, 1],
      messageResultat: 'Résultat restauré',
      storageKey: 'R${kNumR}C${kNumC}_${_ddmmyyyy(dep)}',
    );

Map<String, Object> _prefs({
  required List<UserPrediction> preds,
  required TrackedCourse suivi,
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
      // ⚠️ Le disque contient DÉJÀ les données « restaurées » : `_importer()`
      //    fait `provider.reloadPredictions()` puis `AlertService.recharger()`,
      //    qui relisent CE store. C'est la production qui les relit, pas nous.
      'user_predictions_v2': preds.map((p) => json.encode(p.toJson())).toList(),
      'tracked_courses_v1': <String>[json.encode(suivi.toJson())],
    };

// ─────────────────────────── Opérations simulées ───────────────────────────

/// Retour d'import RÉUSSI. Seul le RETOUR est simulé ; tout le reste
/// (rechargements, boucle de synchronisation) est exécuté par la production.
ImportResult _importReussi() => ImportResult(
      succes: true,
      nbClesRestaurees: 12,
      nbParis: 2,
      nbPronosticsIA: 0,
      nbAlertes: 0,
      dateBackup: DateTime(2026, 11, 20, 14, 30),
      version: 'test-a0',
    );

/// Toute opération non sollicitée LÈVE : un appel inattendu devient un échec
/// bruyant, jamais un silence (même règle qu'`a7_37`).
OperationsSauvegarde _ops({required Future<ImportResult> Function() importer}) =>
    OperationsSauvegarde(
      partagerAvecResultat: () async =>
          throw StateError('partagerAvecResultat NON ATTENDU'),
      telecharger: () async => throw StateError('telecharger NON ATTENDU'),
      sauvegarderDrive: () async =>
          throw StateError('sauvegarderDrive NON ATTENDU'),
      importerFichier: importer,
    );

// ─────────────────────────── Montage ───────────────────────────────────────

List<String> _debordements = <String>[];

Future<void> _monterProfil(
  WidgetTester tester,
  PmuProvider pmu,
  OperationsSauvegarde operations,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1000, 2600);
  addTearDown(tester.view.reset);

  _debordements = <String>[];
  final ancien = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final String t = details.toString();
    if (t.contains('overflowed')) {
      _debordements.add(t.replaceAll('\n', ' '));
      return; // PRÉEXISTANT, hors A-0 : compté et rapporté.
    }
    ancien?.call(details);
  };

  try {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChangeNotifierProvider<PmuProvider>.value(
              value: pmu,
              child: ProfileBackupSection(
                provider: pmu,
                operations: operations,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  } finally {
    FlutterError.onError = ancien;
  }
}

Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Pompe BORNÉE jusqu'à la présence d'un widget (jamais de boucle ouverte).
Future<void> _pomperPresence(WidgetTester tester, Finder cible,
    {int maxTours = 80}) async {
  for (var i = 0; i < maxTours; i++) {
    if (cible.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _preparer({
  required List<UserPrediction> preds,
  required TrackedCourse suivi,
}) async {
  SharedPreferences.setMockInitialValues(_prefs(preds: preds, suivi: suivi));
  ZoneTurfService.viderCachePourResetComplet();
  DataRefreshService.instance.viderMemoirePourResetComplet();
  IaArchiveService.instance.oublierChargementPourTest();
  await IaMemoryService.instance.recharger();
  await AlertService.instance.recharger();
}

// ─────────────────────────── Tests ────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  T-P2 — RESTAURATION : le G+P ne reçoit rien, le Simple reçoit tout.
  //
  //  Les DEUX paris sont sur la MÊME course restaurée, résolue et gagnante.
  //  La boucle de production `predictions.where(...)` (l.1640) les trouve
  //  tous les deux : c'est donc un vrai témoin de non-régression, dans le
  //  même passage, avec le même `TrackedCourse`.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('T-P2 — après restauration, le G+P reste en attente tandis que '
      'le Simple Gagnant est synchronisé (bouton et dialogue réels)',
      (tester) async {
    final dep = DateTime.now().subtract(const Duration(minutes: 90));
    final predGP = _pred('Gagnant+Placé', id: 'p_gp');
    final predSG = _pred('Simple Gagnant', id: 'p_sg');

    await _preparer(
      preds: <UserPrediction>[predGP, predSG],
      suivi: _suiviGagne(dep),
    );

    // ── TÉMOINS sur l'état de départ ─────────────────────────────────────
    expect(AlertService.instance.trackedCourses.length, 1,
        reason: 'TÉMOIN : le suivi restauré est chargé');
    expect(AlertService.instance.trackedCourses.values.first.isGagne, isTrue,
        reason: 'TÉMOIN : le suivi est RÉSOLU et GAGNANT → la boucle P2 '
            'est atteignable (garde `isGagne == null` non franchie)');

    final pmu = PmuProvider();
    await pmu.reloadPredictions();
    expect(pmu.predictions.length, 2,
        reason: 'TÉMOIN : les deux paris restaurés sont en mémoire');
    expect(pmu.predictions.every((p) => p.isCorrect == null), isTrue,
        reason: 'TÉMOIN : tous deux en attente AVANT la synchronisation');

    await _monterProfil(tester, pmu, _ops(importer: () async => _importReussi()));

    // ── Appui sur le VRAI bouton « Importer une sauvegarde » ─────────────
    final Finder btn = find.text(kBtnImporter);
    expect(btn, findsOneWidget,
        reason: 'TÉMOIN : la section de sauvegarde est montée');
    await tester.ensureVisible(btn);
    await tester.pump();
    await tester.tap(btn);
    await _pomperPresence(tester, find.byType(AlertDialog));

    // ── Confirmation dans le VRAI dialogue « Importer ? » ────────────────
    final Finder continuer = find.text(kBtnContinuer);
    expect(continuer, findsOneWidget,
        reason: 'TÉMOIN : le dialogue d\'avertissement est bien ouvert');
    await tester.tap(continuer);
    // Laisse la chaîne asynchrone de `_importer()` se dérouler : import,
    // reloadPredictions, recharger AlertService, boucle P2, puis dialogue.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final apresGP = pmu.predictions.firstWhere((p) => p.id == 'p_gp');
    final apresSG = pmu.predictions.firstWhere((p) => p.id == 'p_sg');

    // ignore: avoid_print
    print('─── MESURE T-P2 (voie 2 — restauration Profil) ───────────────');
    // ignore: avoid_print
    print('  G+P          : isCorrect=${apresGP.isCorrect} '
        'mise=${apresGP.montantMise} gainNet=${apresGP.gainNet}');
    // ignore: avoid_print
    print('  Simple Gagnant: isCorrect=${apresSG.isCorrect} '
        'mise=${apresSG.montantMise} gainNet=${apresSG.gainNet}');
    // ignore: avoid_print
    print('  dialogues après import : ${find.byType(AlertDialog).evaluate().length}');
    // ignore: avoid_print
    print('  débordements préexistants mesurés : ${_debordements.length}');
    // ignore: avoid_print
    print('──────────────────────────────────────────────────────────────');

    // ══ ASSERTION 0 : la restauration elle-même a bien abouti ════════════
    // Sans ce témoin, un échec de harnais (import jamais appelé) ferait
    // passer les assertions suivantes pour de mauvaises raisons.
    expect(find.text(kTitreSucces), findsWidgets,
        reason: 'TÉMOIN : la restauration a RÉELLEMENT été traitée '
            '(dialogue de succès affiché). Son absence signifierait que la '
            'boucle P2 n\'a jamais été atteinte.');

    // ══ ASSERTION 1 : le G+P n'a subi AUCUNE écriture ════════════════════
    expect(apresGP.isCorrect, isNull,
        reason: 'P2 — le Gagnant+Placé doit rester « en attente » après '
            'restauration. Obtenu isCorrect=${apresGP.isCorrect}');
    expect(apresGP.montantMise, kMise,
        reason: 'P2 — la mise du G+P ne doit pas être réécrite : le G+P '
            'engage DEUX mises, en écrire une seule est un gain faux. '
            'Obtenu ${apresGP.montantMise}');
    expect(apresGP.gainRealise, isNull,
        reason: 'P2 — aucun gainRealise écrit pour un G+P');
    expect(apresGP.gainNet, 0.0, reason: 'P2 — gainNet nul');
    expect(apresGP.gainNet, isNot(closeTo(kGainFictif, 1e-6)),
        reason: 'P2 — le gain FICTIF de ${kGainFictif.toStringAsFixed(2)} € '
            'ne doit pas apparaître');

    // ══ ASSERTION 2 : NON-RÉGRESSION — le Simple est bien synchronisé ════
    // Même course, même `TrackedCourse`, même passage : la différence entre
    // les deux paris ne peut venir QUE de la garde A-0.
    expect(apresSG.isCorrect, isTrue,
        reason: 'NON-RÉGRESSION — un Simple Gagnant restauré et gagnant doit '
            'être marqué gagnant. Obtenu isCorrect=${apresSG.isCorrect}');
    expect(apresSG.montantMise, kMise,
        reason: 'NON-RÉGRESSION — la mise du Simple est bien celle du suivi');
    expect(apresSG.gainRealise, isNotNull,
        reason: 'NON-RÉGRESSION — le gain du Simple est calculé');
    expect(apresSG.gainNet, closeTo((kCote * kMise) - kMise, 1e-9),
        reason: 'NON-RÉGRESSION — gain = (18,00 × 20) − 20 = 340,00 €');

    await _demonter(tester);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  T-P2b — PERTE : un G+P PERDANT ne doit pas non plus être écrit.
  //
  //  P2 neutralise TOUTE écriture automatique pour ce type, pas seulement
  //  les gains. Ce scénario vérifie qu'aucun `isCorrect = false` n'est posé
  //  sur un G+P : la composante financière reste entièrement au Lot B.
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('T-P2b — un G+P perdant restauré n\'est pas écrit non plus',
      (tester) async {
    final dep = DateTime.now().subtract(const Duration(minutes: 90));
    final predGP = _pred('Gagnant+Placé', id: 'p_gp_perdu');

    // Course restaurée RÉSOLUE mais PERDANTE.
    final suiviPerdu = TrackedCourse(
      numReunion: kNumR,
      numCourse: kNumC,
      nomCourse: kNomCourse,
      hippodrome: kHippodrome,
      heureDepart: dep,
      nomCheval: 'CHEVAL_$kNumeroCheval',
      numeroCheval: kNumeroCheval,
      miseEngagee: kMise,
      typePari: 'Gagnant+Placé',
      numerosJoues: const <int>[kNumeroCheval],
      cote: kCote,
      scoreIA: 89.0,
      isGagne: false,
      arriveeFinale: const <int>[4, 2, 9, 1, 3],
      messageResultat: 'Non placé',
      storageKey: 'R${kNumR}C${kNumC}_${_ddmmyyyy(dep)}',
    );

    await _preparer(preds: <UserPrediction>[predGP], suivi: suiviPerdu);
    expect(AlertService.instance.trackedCourses.values.first.isGagne, isFalse,
        reason: 'TÉMOIN : le suivi restauré est RÉSOLU et PERDANT');

    final pmu = PmuProvider();
    await pmu.reloadPredictions();

    await _monterProfil(
        tester, pmu, _ops(importer: () async => _importReussi()));

    await tester.tap(find.text(kBtnImporter));
    await _pomperPresence(tester, find.byType(AlertDialog));
    await tester.tap(find.text(kBtnContinuer));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final apres = pmu.predictions.single;
    // ignore: avoid_print
    print('─── MESURE T-P2b (G+P PERDANT restauré) : '
        'isCorrect=${apres.isCorrect} gainNet=${apres.gainNet}');

    expect(apres.isCorrect, isNull,
        reason: 'P2 — même PERDANT, un G+P ne reçoit aucune écriture '
            'automatique (deux composantes). Obtenu ${apres.isCorrect}');
    expect(apres.gainRealise, isNull, reason: 'P2 — aucun gainRealise');
    expect(apres.gainNet, 0.0,
        reason: 'P2 — aucune perte fictive de −20,00 € non plus');

    await _demonter(tester);
  });
}
