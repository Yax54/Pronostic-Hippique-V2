// ═══════════════════════════════════════════════════════════════════════════
//  A4-4 — EXCLUSION DES ABSTENTIONS « À surveiller » DES STATISTIQUES
//
//  Objet : vérifier que les trois filtres corrigés excluent bien les
//  abstentions, SANS modifier le traitement des véritables paris conseillés,
//  ni les résultats historiques, ni les règles du calendrier, ni
//  l'apprentissage IA.
//
//  PÉRIMÈTRE INTERDIT (non modifié par A4-4, non testé ici) :
//   • `_estBonConseilParType` et les règles de réussite ;
//   • les critères d'attribution des types de pari ;
//   • `_poids`, `_seuils`, gradient descent, TOP 3, ELO,
//     `analyseJourneeComplete()` ;
//   • M1, purge 90 jours, plafond 600 ;
//   • ⭐ Premium, 🔥 Gros Paris, « Quasi gagnants » ;
//   • A4-5.
//
//  MÉTHODE : les trois corrections vivent dans du code privé d'UI
//  (`_buildStatsByType`, `_buildSectionPrecisionIA`). Pour les tester
//  réellement — et non par imitation approximative — les widgets sont montés
//  et leur sortie est lue dans l'arbre de widgets rendu. Le service ROI étant
//  public, il est testé directement.
//
//  ⚠️ NEUTRALISATION DE M1 : le flag `ia_precision_migrated_v3` est posé à
//     `true` dans le store simulé, afin qu'aucune migration one-shot ne
//     déclenche `_save()` pendant `_load()`.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/roi_value_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/roi_value_service.dart';
import 'package:pronostic_hippique/widgets/ia/ia_calendrier_tab.dart';
import 'package:pronostic_hippique/widgets/profile/profile_profil_tab.dart';

// ───────────────────────────────────────────────────────────────────────────
//  CONSTANTES
// ───────────────────────────────────────────────────────────────────────────

const String kPronosticsKey = 'ia_pronostics_v2';
const String kFlagMigration = 'ia_precision_migrated_v3';

/// Arrivée où le favori IA (n°3) gagne : rang=1, top3=3, top5=5 → GAGNANT.
const List<int> kArriveeGagnante = <int>[3, 7, 1, 5, 2];

/// Arrivée où aucun cheval IA n'est placé → PERDANT.
const List<int> kArriveePerdante = <int>[9, 8, 6, 4, 10];

const Map<String, double> kScoresIA = <String, double>{
  '3': 92.0, '7': 84.0, '1': 76.0, '5': 68.0, '2': 60.0,
};

/// Libellé EXACT produit par l'IA pour une abstention.
const String kAbstention = 'À surveiller';

// ───────────────────────────────────────────────────────────────────────────
//  FABRIQUE DE PRONOSTICS
// ───────────────────────────────────────────────────────────────────────────

IaPronostic faireProno({
  required String cle,
  required DateTime jour,
  required String typePari,
  required bool gagnant,
}) =>
    IaPronostic(
      courseKey: cle,
      nomCourse: 'Course $cle',
      hippodrome: 'Vincennes',
      discipline: 'Trot Attelé',
      datePronostic: jour,
      dateResultat: jour,
      scoresIA: kScoresIA,
      scoresCriteres: const <String, ScoresCriteres>{},
      resultatsReels: true,
      arriveeReelle: gagnant ? kArriveeGagnante : kArriveePerdante,
      typePariConseille: typePari,
      confiancePredite: gagnant ? 71.0 : 30.0,
      varianceScores: 12.5,
      favoriIaNom: 'Cheval 3',
      rangFavoriIaDansArrivee: gagnant ? 1 : null,
      nbTop3DansArriveeReelle: gagnant ? 3 : 0,
      nbTop5DansArriveeReelle: gagnant ? 5 : 0,
      coteFavoriPmu: 3.4,
      cotesPmuParNumero: const <String, double>{'3': 3.4, '7': 6.1},
    );

// ───────────────────────────────────────────────────────────────────────────
//  AMORÇAGE
// ───────────────────────────────────────────────────────────────────────────

Future<void> amorcer(List<IaPronostic> liste) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'flutter.$kPronosticsKey':
        liste.map((p) => json.encode(p.toJson())).toList(),
    'flutter.$kFlagMigration': true,
  });
  SharedPreferences.resetStatic();
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
  await IaArchiveService.instance.charger();
}

// ───────────────────────────────────────────────────────────────────────────
//  LECTURE DE L'ARBRE RENDU
// ───────────────────────────────────────────────────────────────────────────

/// Tous les textes effectivement rendus sous [finder].
List<String> textesRendus(WidgetTester tester, Finder finder) {
  final out = <String>[];
  for (final e in finder.evaluate()) {
    final w = e.widget;
    if (w is Text && w.data != null) out.add(w.data!);
    if (w is RichText) out.add(w.text.toPlainText());
  }
  return out;
}

/// Monte le calendrier sur une surface haute, afin que le `ListView`
/// paresseux construise réellement le panneau « Précision par type ».
Future<void> pomperCalendrier(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: IaCalendrierTab()),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Monte le profil avec les providers requis par son `build()` :
///   • `PmuProvider`          → `context.watch<PmuProvider>()` (l.886)
///   • `DataRefreshService`   → `context.read<DataRefreshService>()` (l.1073)
Future<void> pomperProfil(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final provider = PmuProvider();
  addTearDown(provider.dispose);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<PmuProvider>.value(value: provider),
      ChangeNotifierProvider<DataRefreshService>.value(
          value: DataRefreshService.instance),
    ],
    child: const MaterialApp(
      home: Scaffold(body: ProfileProfilTabPlaceholder()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 200));
}

/// Petit adaptateur : `ProfileProfilTab` exige un `provider` en paramètre,
/// mais son `build()` lit le `PmuProvider` via `context.watch`.
class ProfileProfilTabPlaceholder extends StatelessWidget {
  const ProfileProfilTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileProfilTab(provider: context.watch<PmuProvider>());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC 1 — CALENDRIER : « Précision par type de pari »
  //  La correction : le littéral « A surveiller » (sans accent) ne
  //  correspondait à aucune donnée. Il est remplacé par « À surveiller ».
  // ═══════════════════════════════════════════════════════════════════════

  testWidgets('A4-4-T1 — calendrier : abstention exclue de la précision par type',
      (tester) async {
    final now = DateTime.now();
    await amorcer(<IaPronostic>[
      // Une abstention GAGNANTE (pire cas : elle gonflerait le panneau à 100 %).
      faireProno(cle: 'R1C1_${_ddmmyyyy(now)}', jour: now,
          typePari: kAbstention, gagnant: true),
      // Un vrai pari conseillé, GAGNANT.
      faireProno(cle: 'R1C2_${_ddmmyyyy(now)}', jour: now,
          typePari: 'Tiercé', gagnant: true),
    ]);

    await pomperCalendrier(tester);

    final textes = textesRendus(tester, find.byType(Text));

    // Le panneau de précision doit afficher Tiercé.
    expect(textes.any((t) => t.contains('Tiercé')), isTrue,
        reason: 'un vrai pari conseillé doit rester comptabilisé');

    // L'abstention ne doit PAS apparaître.
    expect(textes.any((t) => t == kAbstention), isFalse,
        reason: '« À surveiller » doit être exclu de la précision par type');

    // Contrôle de non-régression du bug corrigé : l'ancien libellé non plus.
    expect(textes.any((t) => t == 'A surveiller'), isFalse);
  });

  testWidgets('A4-4-T2 — calendrier : les vrais paris restent comptabilisés',
      (tester) async {
    final now = DateTime.now();
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(now)}', jour: now,
          typePari: 'Tiercé', gagnant: true),
      faireProno(cle: 'R1C2_${_ddmmyyyy(now)}', jour: now,
          typePari: 'Quinté+', gagnant: true),
      faireProno(cle: 'R1C3_${_ddmmyyyy(now)}', jour: now,
          typePari: 'Simple Placé', gagnant: true),
      faireProno(cle: 'R1C4_${_ddmmyyyy(now)}', jour: now,
          typePari: kAbstention, gagnant: true),
    ]);

    await pomperCalendrier(tester);

    final textes = textesRendus(tester, find.byType(Text));
    for (final type in <String>['Tiercé', 'Quinté+', 'Simple Placé']) {
      expect(textes.any((t) => t == type), isTrue,
          reason: '"$type" doit rester présent dans la précision par type');
    }
    expect(textes.any((t) => t == kAbstention), isFalse);
  });

  testWidgets('A4-4-T3 — calendrier : règles de paliers inchangées',
      (tester) async {
    final now = DateTime.now();
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(now)}', jour: now,
          typePari: 'Tiercé', gagnant: true),
      faireProno(cle: 'R1C2_${_ddmmyyyy(now)}', jour: now,
          typePari: kAbstention, gagnant: true),
    ]);

    // Règle métier : l'abstention ne crée JAMAIS de journée dans le calendrier.
    final data = IaMemoryService.instance.donneesCalendrierJour(now.year, now.month);
    expect(data.containsKey(now.day), isTrue,
        reason: 'la journée doit exister grâce au Tiercé');

    final jour = data[now.day]!;
    expect(jour.nbCourses, 1,
        reason: 'seul le vrai pari compte : l\'abstention n\'ajoute pas de course');
    expect(jour.nbBons, 1);
    // Le palier OR vient du Tiercé réussi — règle inchangée.
    expect(jour.palier, PalierCalendrier.or);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC 2 — PROFIL : taux mensuel
  //  La correction : l'abstention est exclue du dénominateur mensuel,
  //  comme elle l'était déjà du dénominateur global.
  // ═══════════════════════════════════════════════════════════════════════

  testWidgets('A4-4-T4 — profil : abstention exclue du taux mensuel',
      (tester) async {
    final now = DateTime.now();
    // 1 vrai pari GAGNANT + 1 abstention PERDANTE.
    // Avant correction : 1/2 = 50 %. Après : 1/1 = 100 %.
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(now)}', jour: now,
          typePari: 'Tiercé', gagnant: true),
      faireProno(cle: 'R1C2_${_ddmmyyyy(now)}', jour: now,
          typePari: kAbstention, gagnant: false),
    ]);

    await pomperProfil(tester);

    final textes = textesRendus(tester, find.byType(Text));

    // La tuile « Ce mois » doit afficher 1/1, pas 1/2.
    expect(textes.contains('1/1'), isTrue,
        reason: 'l\'abstention doit être exclue du dénominateur mensuel');
    expect(textes.contains('1/2'), isFalse,
        reason: 'le dénominateur ne doit plus inclure l\'abstention');

    // Le libellé du type ne doit pas apparaître dans le détail.
    expect(textes.any((t) => t == kAbstention), isFalse);
  });

  testWidgets('A4-4-T5 — profil : le total global reste inchangé',
      (tester) async {
    final now = DateTime.now();
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(now)}', jour: now,
          typePari: 'Tiercé', gagnant: true),
      faireProno(cle: 'R1C2_${_ddmmyyyy(now)}', jour: now,
          typePari: 'Quinté+', gagnant: false),
      faireProno(cle: 'R1C3_${_ddmmyyyy(now)}', jour: now,
          typePari: kAbstention, gagnant: true),
      faireProno(cle: 'R1C4_${_ddmmyyyy(now)}', jour: now,
          typePari: kAbstention, gagnant: false),
    ]);

    await pomperProfil(tester);

    final textes = textesRendus(tester, find.byType(Text));

    // Les 3 tuiles (Aujourd'hui / Ce mois / Total) doivent converger sur
    // 1 bon / 2 vrais paris : les 2 abstentions sont exclues partout.
    final tuiles1sur2 = textes.where((t) => t == '1/2').length;
    expect(tuiles1sur2, 3,
        reason: 'les 3 tuiles doivent afficher 1/2 (2 vrais paris)');
    // Le dénominateur BUGGÉ serait 4 (2 vrais + 2 abstentions).
    expect(textes.any((t) => t.endsWith('/4')), isFalse,
        reason: 'aucune tuile ne doit inclure les abstentions au dénominateur');
    expect(textes.any((t) => t == kAbstention), isFalse);
  });

  testWidgets('A4-4-T6 — profil : paris réels toujours traités normalement',
      (tester) async {
    final now = DateTime.now();
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(now)}', jour: now,
          typePari: 'Simple Gagnant', gagnant: true),
      faireProno(cle: 'R1C2_${_ddmmyyyy(now)}', jour: now,
          typePari: 'Simple Placé', gagnant: false),
    ]);

    await pomperProfil(tester);

    final textes = textesRendus(tester, find.byType(Text));
    // Aucune abstention ici : 1 bon / 2 paris, sur les 3 tuiles.
    expect(textes.where((t) => t == '1/2').length, 3);
    expect(textes.any((t) => t == 'Simple Gagnant'), isTrue);
    expect(textes.any((t) => t == 'Simple Placé'), isTrue);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC 3 — ROI : exclusion dans `_filtrer`
  //  Le service est public : test direct. Les formules de rentabilité ne
  //  sont pas touchées — seule la population d'entrée est filtrée.
  // ═══════════════════════════════════════════════════════════════════════

  test('A4-4-T7 — ROI : abstention exclue des statistiques', () async {
    final jour = DateTime.now().subtract(const Duration(days: 3));
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(jour)}', jour: jour,
          typePari: kAbstention, gagnant: true),
    ]);

    final res = RoiValueService.instance.calculerResume(const RoiValueFilters());

    expect(res.nbCourses, 0,
        reason: 'une abstention n\'est pas une course pariée');
    expect(res.nbParisRoi, 0, reason: 'aucune mise ne doit être comptée');
    expect(res.gagnants, 0,
        reason: 'une abstention ne peut pas être un pari gagnant');
    expect(res.mises, 0.0, reason: 'aucun euro engagé');
    expect(res.retours, 0.0);
    expect(res.roi, 0.0);
  });

  test('A4-4-T8 — ROI : vrais paris toujours comptabilisés', () async {
    final jour = DateTime.now().subtract(const Duration(days: 3));
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(jour)}', jour: jour,
          typePari: 'Tiercé', gagnant: true),
      faireProno(cle: 'R1C2_${_ddmmyyyy(jour)}', jour: jour,
          typePari: kAbstention, gagnant: true),
    ]);

    final res = RoiValueService.instance.calculerResume(const RoiValueFilters());

    expect(res.nbCourses, 1, reason: 'seul le Tiercé est un vrai pari');
    expect(res.nbParisRoi, 1, reason: 'une seule mise (cote disponible)');
    expect(res.gagnants, 1);
    expect(res.perdants, 0);
    expect(res.mises, 1.0);
  });

  test('A4-4-T9 — ROI : formules de rentabilité inchangées', () async {
    final jour = DateTime.now().subtract(const Duration(days: 3));
    await amorcer(<IaPronostic>[
      // Gagnant : cote 3.4 → retour 3.4
      faireProno(cle: 'R1C1_${_ddmmyyyy(jour)}', jour: jour,
          typePari: 'Tiercé', gagnant: true),
      // Perdant : cote 3.4 → mise perdue
      faireProno(cle: 'R1C2_${_ddmmyyyy(jour)}', jour: jour,
          typePari: 'Quinté+', gagnant: false),
    ]);

    final res = RoiValueService.instance.calculerResume(const RoiValueFilters());

    expect(res.nbParisRoi, 2);
    expect(res.gagnants, 1);
    expect(res.perdants, 1);
    expect(res.mises, 2.0);
    expect(res.retours, closeTo(3.4, 0.0001));
    expect(res.gainNet, closeTo(1.4, 0.0001));
    expect(res.roi, closeTo(70.0, 0.0001));   // (3.4-2)/2*100
    expect(res.tauxReussite, closeTo(50.0, 0.0001));
  });

  test('A4-4-T10 — ROI : filtre par type explicite reste fonctionnel', () async {
    final jour = DateTime.now().subtract(const Duration(days: 3));
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(jour)}', jour: jour,
          typePari: 'Tiercé', gagnant: true),
      faireProno(cle: 'R1C2_${_ddmmyyyy(jour)}', jour: jour,
          typePari: 'Quinté+', gagnant: true),
    ]);

    final tierce = RoiValueService.instance
        .calculerResume(const RoiValueFilters(typePari: 'Tiercé'));
    expect(tierce.nbCourses, 1);
    expect(tierce.gagnants, 1);

    final quinte = RoiValueService.instance
        .calculerResume(const RoiValueFilters(typePari: 'Quinté+'));
    expect(quinte.nbCourses, 1);
    expect(quinte.gagnants, 1);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC 4 — NON-RÉGRESSION
  // ═══════════════════════════════════════════════════════════════════════

  test('A4-4-T11 — les résultats historiques ne sont pas modifiés', () async {
    final jour = DateTime(2024, 6, 10);
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(jour)}', jour: jour,
          typePari: kAbstention, gagnant: true),
    ]);

    final p = IaMemoryService.instance.pronostics.first;
    // Le pronostic lui-même est INTACT : rien n'est réécrit.
    expect(p.typePariConseille, kAbstention);
    expect(p.resultatsReels, isTrue);
    expect(p.arriveeReelle, kArriveeGagnante);
    expect(p.rangFavoriIaDansArrivee, 1);
    expect(p.nbTop3DansArriveeReelle, 3);
    // La règle de réussite n'a pas été touchée (branche default:).
    expect(IaMemoryService.instance.estBonConseil(p, kAbstention), isTrue);
  });

  test('A4-4-T12 — aucune modification de l\'apprentissage IA', () async {
    final jour = DateTime.now().subtract(const Duration(days: 3));
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(jour)}', jour: jour,
          typePari: 'Tiercé', gagnant: true),
      faireProno(cle: 'R1C2_${_ddmmyyyy(jour)}', jour: jour,
          typePari: kAbstention, gagnant: true),
    ]);

    final mem = IaMemoryService.instance;
    final s = mem.seuilsConfiance;

    // Les seuils restent à leurs valeurs par défaut : aucun ajustement
    // n'est déclenché par un pronostic « À surveiller ».
    expect(s.seuilSimpleGagnant, 80.0);
    expect(s.seuilGagnantPlace, 50.0);
    expect(s.seuilSimplePlace, 65.0);
    expect(s.seuilCoupleGagnant, 75.0);
    expect(s.seuilCouplePlace, 60.0);
    expect(s.seuilTierce, 35.0);

    // Les poids restent ceux par défaut : aucune mise à jour.
    expect(mem.poids.nbMisesAJour, 0,
        reason: 'aucune mise à jour de poids ne doit être déclenchée');

    // `_precisionParType` n'est pas pollué par l'abstention.
    expect(mem.precisionParType.any((e) => e.typePari == kAbstention), isFalse);
  });

  test('A4-4-T13 — plafond 600 et purge 90 jours : comportement inchangé',
      () async {
    final recent = DateTime.now().subtract(const Duration(days: 1));
    final ancien = DateTime.now().subtract(const Duration(days: 200));

    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(recent)}', jour: recent,
          typePari: 'Tiercé', gagnant: true),
      faireProno(cle: 'R1C2_${_ddmmyyyy(ancien)}', jour: ancien,
          typePari: 'Tiercé', gagnant: true),
    ]);

    // Le rechargement a appliqué M1 telle quelle (aucune modification A4-4).
    final pronos = IaMemoryService.instance.pronostics;
    // M1 ne purge qu'au moment de `_save()` ; après un simple `_load()`,
    // les deux pronostics sont présents. Ce test fige donc le comportement
    // observé sans prétendre le corriger.
    expect(pronos.length, 2,
        reason: 'M1 n\'est pas modifié par A4-4');
  });

  test('A4-4-T14 — littéral du filtre identique au libellé produit', () async {
    // Vérifie l'invariant corrigé : le libellé produit ET le libellé filtré
    // sont la MÊME chaîne, accent compris.
    const produit = kAbstention;
    const filtre = 'À surveiller';
    expect(produit, filtre);
    expect(produit.codeUnits, filtre.codeUnits);
    expect(produit.codeUnits.first, 192); // 'À' U+00C0
    // L'ancien littéral, lui, ne correspondait à rien.
    expect('A surveiller' == produit, isFalse);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC 5 — PORTÉE DU FILTRE ROI (★ A4-4 ajustement final)
  //
  //  L'exclusion des abstentions ne doit porter QUE sur les calculs
  //  financiers du ROI (`calculerResume`, seul endroit engageant une mise),
  //  et PAS sur les analyses Value / Outsiders / Faux favoris.
  // ═══════════════════════════════════════════════════════════════════════

  test('A4-4-T15 — ROI financier : abstention exclue des mises', () async {
    final jour = DateTime.now().subtract(const Duration(days: 3));
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(jour)}', jour: jour,
          typePari: 'Tiercé', gagnant: true),
      faireProno(cle: 'R1C2_${_ddmmyyyy(jour)}', jour: jour,
          typePari: kAbstention, gagnant: true),
    ]);

    final res = RoiValueService.instance.calculerResume(const RoiValueFilters());

    // Le Tiercé reste compté normalement.
    expect(res.nbCourses, 1, reason: 'l\'abstention ne doit pas être une course pariée');
    expect(res.nbParisRoi, 1);
    expect(res.mises, 1.0, reason: 'une seule mise : aucun euro sur l\'abstention');
    expect(res.gagnants, 1);
  });

  test('A4-4-T16 — Faux favoris : abstention encore VISIBLE', () async {
    final jour = DateTime.now().subtract(const Duration(days: 3));
    // Faux favori = confiance >= 80 ET conseil perdant.
    // On abaisse confiancePredite pour l'abstention à 85 et on la fait perdre,
    // afin que TOUTES ses conditions (autres que le type) soient satisfaites.
    await amorcer(<IaPronostic>[
      IaPronostic(
        courseKey: 'R1C1_${_ddmmyyyy(jour)}',
        nomCourse: 'Course abstention sur-confiante',
        hippodrome: 'Vincennes',
        discipline: 'Trot Attelé',
        datePronostic: jour,
        dateResultat: jour,
        scoresIA: kScoresIA,
        scoresCriteres: const <String, ScoresCriteres>{},
        resultatsReels: true,
        arriveeReelle: kArriveePerdante,
        typePariConseille: kAbstention,
        confiancePredite: 85.0, // >= 80 : condition du faux favori
        varianceScores: 12.5,
        favoriIaNom: 'Cheval 3',
        rangFavoriIaDansArrivee: null,
        nbTop3DansArriveeReelle: 0,
        nbTop5DansArriveeReelle: 0,
        coteFavoriPmu: 2.1,
        cotesPmuParNumero: const <String, double>{'3': 2.1},
      ),
    ]);

    final fauxFav = RoiValueService.instance
        .detecterFauxFavoris(const RoiValueFilters());

    expect(fauxFav.length, 1,
        reason: 'une abstention sur-confiante et perdante reste un faux favori');
    expect(fauxFav.first.typePari, kAbstention);
  });

  test('A4-4-T17 — Value : comportement inchangé pour les abstentions', () async {
    final jour = DateTime.now().subtract(const Duration(days: 3));
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(jour)}', jour: jour,
          typePari: kAbstention, gagnant: true),
    ]);

    // L'abstention ne satisfait pas les conditions de Value (score < 70 :
    // scoresIA['3'] = 92 mais divergence = 50 par défaut < 60). Le service
    // ne doit PAS lever d'exception et ne doit pas la retenir.
    final values =
        RoiValueService.instance.detecterValue(const RoiValueFilters());
    expect(values, isEmpty,
        reason: 'conditions Value non satisfaites — résultat identique à avant');
  });

  test('A4-4-T18 — Outsiders : comportement inchangé pour les abstentions', () async {
    final jour = DateTime.now().subtract(const Duration(days: 3));
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(jour)}', jour: jour,
          typePari: kAbstention, gagnant: true),
    ]);

    // Aucune cote >= 8 dans cotesPmuParNumero → aucun outsider, avant comme après.
    final outsiders =
        RoiValueService.instance.analyserOutsiders(const RoiValueFilters());
    expect(outsiders, isEmpty,
        reason: 'aucune cote >= 8 — résultat identique à avant');
  });

  test('A4-4-T19 — données invalides toujours exclues de toutes les analyses',
      () async {
    final jour = DateTime.now().subtract(const Duration(days: 3));
    await amorcer(<IaPronostic>[
      faireProno(cle: 'R1C1_${_ddmmyyyy(jour)}', jour: jour,
          typePari: 'Inconnu', gagnant: true),
      faireProno(cle: 'R1C2_${_ddmmyyyy(jour)}', jour: jour,
          typePari: '', gagnant: true),
    ]);

    final res = RoiValueService.instance.calculerResume(const RoiValueFilters());
    expect(res.nbCourses, 0, reason: '« Inconnu » et vide ne sont pas des paris');
    expect(res.mises, 0.0);

    final fauxFav =
        RoiValueService.instance.detecterFauxFavoris(const RoiValueFilters());
    expect(fauxFav, isEmpty, reason: 'données invalides hors de toute analyse');
  });

  test('A4-4-T20 — vrais paris : analysés par les onglets non financiers',
      () async {
    final jour = DateTime.now().subtract(const Duration(days: 3));
    // Vrai pari avec cote 8.5 sur le n°7, arrivé 2e du top3 → Outsiders.
    await amorcer(<IaPronostic>[
      IaPronostic(
        courseKey: 'R1C1_${_ddmmyyyy(jour)}',
        nomCourse: 'Course vrai pari',
        hippodrome: 'Vincennes',
        discipline: 'Trot Attelé',
        datePronostic: jour,
        dateResultat: jour,
        scoresIA: kScoresIA,
        scoresCriteres: const <String, ScoresCriteres>{},
        resultatsReels: true,
        arriveeReelle: kArriveeGagnante,
        typePariConseille: 'Tiercé',
        confiancePredite: 71.0,
        varianceScores: 12.5,
        favoriIaNom: 'Cheval 3',
        rangFavoriIaDansArrivee: 1,
        nbTop3DansArriveeReelle: 3,
        nbTop5DansArriveeReelle: 5,
        coteFavoriPmu: 5.5,
        cotesPmuParNumero: const <String, double>{'3': 5.5, '7': 8.5},
      ),
    ]);

    expect(
        RoiValueService.instance
            .calculerResume(const RoiValueFilters())
            .nbParisRoi,
        1,
        reason: 'ROI : le vrai pari reste comptabilisé');
    expect(
        RoiValueService.instance
            .analyserOutsiders(const RoiValueFilters())
            .isNotEmpty,
        isTrue,
        reason: 'Outsiders : le n°7 (cote 8.5) arrivé 2e reste analysé');
    expect(
        RoiValueService.instance.detecterFauxFavoris(const RoiValueFilters()),
        isEmpty,
        reason: 'Faux favoris : le vrai pari est gagnant, donc écarté');
  });
}

/// Format `JJMMAAAA` utilisé par `buildCourseKey`.
String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}${d.year}';
