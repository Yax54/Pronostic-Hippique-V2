// ═══════════════════════════════════════════════════════════════════════════
//  V45 — E : BILAN MENSUEL DU CALENDRIER — DISPOSITION RESPONSIVE
//
//  OBJET
//  ─────
//  La ligne des quatre statistiques de `_buildBilanMois()` débordait
//  horizontalement à TOUTES les largeurs de téléphone (mesuré sur l'écran
//  complet : 311 px à 320 dp, 271 px à 360 dp, 238 px à 393 dp, 219 px à
//  412 dp, 151 px à 480 dp).
//
//  Cause : les 4 `_statBox` sont des `Column` de largeur rigide et
//  `MainAxisAlignment.spaceAround` ne les réduit pas. Les libellés « jours
//  actifs » et « bons conseils » dépassent à eux seuls l'espace disponible.
//
//  Correction E2 : `LayoutBuilder` + `Expanded`.
//   • place suffisante (≥ 352 dp utiles) → 4 colonnes sur une ligne ;
//   • sinon → 2 lignes de 2 colonnes.
//  Aucune police réduite, aucun libellé tronqué, valeurs / couleurs /
//  séparateurs / calculs INCHANGÉS, `_statBox()` et `_divV()` NON MODIFIÉS.
//
//  MÉTHODE
//  ───────
//  Le calendrier complet est monté avec un store de deux pronostics gagnants,
//  afin que `_buildBilanMois` produise des valeurs réelles (1 jour actif,
//  2 courses, 2 bons conseils, 100 %) et soit réellement traversé. Les
//  débordements sont captés par `FlutterError.onError` — jamais ignorés —
//  puis filtrés sur leur nature.
//
//  ⚠ SCOPAGE : les libellés et les valeurs du bilan existent AUSSI ailleurs
//    dans le calendrier (« 100 % », « 2 »…). Toutes les assertions sont donc
//    restreintes à la `Column` retournée par `_buildBilanMois`.
//
//  PÉRIMÈTRE INTERDIT : règles de réussite, paliers, badges, séries Premium,
//  archives, apprentissage IA, A4-3, A4-4 — non testés, non modifiés.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/widgets/ia/ia_calendrier_tab.dart';

// ───────────────────────────────────────────────────────────────────────────
//  CONSTANTES DU CONTRAT
// ───────────────────────────────────────────────────────────────────────────

const String kPronosticsKey = 'ia_pronostics_v2';
const String kFlagMigration = 'ia_precision_migrated_v3';

/// Libellés des quatre statistiques — INCHANGÉS.
const List<String> kLibelles = <String>[
  'jours actifs',
  'courses',
  'bons conseils',
  'réussite',
];

/// Couleurs des valeurs — INCHANGÉES.
const Color kCouleurJours = Color(0xFF42A5F5);
const Color kCouleurBons = Color(0xFF4CAF7D); // _cGreen
const Color kCouleurTauxVert = Color(0xFF4CAF7D); // taux ≥ 30 % → _cGreen

/// Largeurs testées.
const List<double> kLargeurs = <double>[320, 360, 393, 412, 480];

/// Valeurs attendues du bilan pour le store amorcé : 1 / 2 / 2 / 100 %.
const List<String> kValeursAttendues = <String>['1', '2', '2', '100%'];

// ───────────────────────────────────────────────────────────────────────────
//  DONNÉES — store de référence
// ───────────────────────────────────────────────────────────────────────────

IaPronostic pronoJoueur({
  required DateTime jour,
  required int rang,
  required String hippodrome,
  required String typePari,
  required List<int> arrivee,
  required Map<String, double> scores,
}) =>
    IaPronostic(
      courseKey: 'R1C${rang}_${jour.day.toString().padLeft(2, '0')}'
          '${jour.month.toString().padLeft(2, '0')}${jour.year}',
      nomCourse: 'Prix de test $rang',
      hippodrome: hippodrome,
      discipline: 'Trot Attelé',
      datePronostic: jour,
      dateResultat: jour,
      scoresIA: scores,
      scoresCriteres: const <String, ScoresCriteres>{},
      resultatsReels: true,
      arriveeReelle: arrivee,
      typePariConseille: typePari,
      confiancePredite: 71.0,
      varianceScores: 12.5,
      favoriIaNom: 'Cheval ${arrivee.first}',
      rangFavoriIaDansArrivee: 1,
      nbTop3DansArriveeReelle: 3,
      nbTop5DansArriveeReelle: 5,
      coteFavoriPmu: 3.4,
      cotesPmuParNumero: <String, double>{'${arrivee.first}': 3.4},
    );

/// Deux pronostics GAGNANTS aujourd'hui →
/// `jours actifs = 1`, `courses = 2`, `bons conseils = 2`, `réussite = 100 %`.
Future<void> amorcerBilan() async {
  final jour = DateTime.now();
  SharedPreferences.setMockInitialValues(<String, Object>{
    'flutter.$kPronosticsKey': <String>[
      json.encode(pronoJoueur(
        jour: jour,
        rang: 1,
        hippodrome: 'Vincennes',
        typePari: 'Tiercé',
        arrivee: const <int>[3, 7, 1, 5, 2],
        scores: const <String, double>{'3': 92.0, '7': 84.0, '1': 76.0},
      ).toJson()),
      json.encode(pronoJoueur(
        jour: jour,
        rang: 2,
        hippodrome: 'Enghien',
        typePari: 'Quarté+',
        arrivee: const <int>[5, 2, 9, 4, 1],
        scores: const <String, double>{'5': 88.0, '2': 80.0, '9': 72.0},
      ).toJson()),
    ],
    'flutter.$kFlagMigration': true,
  });
  SharedPreferences.resetStatic();
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
  await IaArchiveService.instance.charger();
}

// ───────────────────────────────────────────────────────────────────────────
//  MONTAGE + CAPTURE DES DÉBORDEMENTS
// ───────────────────────────────────────────────────────────────────────────

/// Monte le calendrier à [largeur] dp et retourne TOUS les débordements
/// captés pendant le montage (aucune erreur n'est ignorée silencieusement).
Future<List<String>> pomperEtCapturer(
    WidgetTester tester, double largeur) async {
  await tester.binding.setSurfaceSize(Size(largeur, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final captures = <String>[];
  final ancien = FlutterError.onError;
  FlutterError.onError = (details) => captures.add(details.toString());
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: IaCalendrierTab()),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  FlutterError.onError = ancien;

  return captures.where((e) => e.contains('overflowed by')).toList();
}

void expectAucunDebordement(List<String> debordements, double largeur) {
  expect(
    debordements,
    isEmpty,
    reason: 'aucun débordement attendu à $largeur dp, obtenu : '
        '${debordements.map((e) => RegExp(r'overflowed by [\d.]+ pixels').firstMatch(e)?.group(0)).toList()}',
  );
}

// ───────────────────────────────────────────────────────────────────────────
//  FINDERS SCOPÉS SUR LA ZONE « BILAN DU MOIS »
// ───────────────────────────────────────────────────────────────────────────

/// Colonne racine du bilan mensuel (contient le titre et la carte des stats).
final Finder zoneBilan = find
    .ancestor(of: find.text('📊 Bilan du mois'), matching: find.byType(Column))
    .first;

/// Les quatre valeurs du bilan : seuls `Text` 17 dp gras de cette zone.
Finder valeursDuBilan() => find.descendant(
      of: zoneBilan,
      matching: find.byWidgetPredicate((w) =>
          w is Text &&
          w.style?.fontSize == 17 &&
          w.style?.fontWeight == FontWeight.bold),
    );

/// Libellé restreint à la zone du bilan.
Finder libelleDuBilan(String libelle) =>
    find.descendant(of: zoneBilan, matching: find.text(libelle));

/// Les trois séparateurs `_divV()` de la zone du bilan (1 × 30 dp).
Finder separateursDuBilan(WidgetTester tester) => find.descendant(
      of: zoneBilan,
      matching: find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        // `_divV()` = Container(width: 1, height: 30, color: white@0.07)
        if (w.constraints?.maxWidth != 1.0) return false;
        if (w.constraints?.maxHeight != 30.0) return false;
        return w.color == Colors.white.withValues(alpha: 0.07);
      }),
    );

bool _renduIntegralement(WidgetTester tester, Finder f) =>
    !tester.renderObject<RenderParagraph>(f).didExceedMaxLines;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(amorcerBilan);

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC E-1 — AUCUN DÉBORDEMENT AUX CINQ LARGEURS
  // ═══════════════════════════════════════════════════════════════════════

  group('E-1 — aucun débordement du bilan mensuel', () {
    for (final largeur in kLargeurs) {
      testWidgets('E-T${largeur.toInt()} — $largeur dp : 0 débordement',
          (tester) async {
        final debordements = await pomperEtCapturer(tester, largeur);
        expectAucunDebordement(debordements, largeur);
        expect(tester.takeException(), isNull,
            reason: 'aucune autre erreur de layout à $largeur dp');
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC E-2 — CONTENU INCHANGÉ
  // ═══════════════════════════════════════════════════════════════════════

  group('E-2 — contenu du bilan inchangé', () {
    testWidgets('E-T6 — les quatre libellés restent présents et exacts',
        (tester) async {
      await pomperEtCapturer(tester, 393);
      for (final libelle in kLibelles) {
        expect(libelleDuBilan(libelle), findsOneWidget,
            reason: '« $libelle » doit apparaître une fois dans le bilan');
      }
    });

    testWidgets('E-T7 — les quatre valeurs restent exactes', (tester) async {
      await pomperEtCapturer(tester, 393);

      final valeurs = valeursDuBilan();
      expect(valeurs, findsNWidgets(4),
          reason: 'exactement 4 valeurs de statistique');

      final textes = valeurs
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .toList(growable: false);
      expect(textes, kValeursAttendues,
          reason: 'jours actifs=1, courses=2, bons conseils=2, réussite=100 %');
    });

    testWidgets('E-T8 — les couleurs et tailles des valeurs sont inchangées',
        (tester) async {
      await pomperEtCapturer(tester, 480);

      final valeurs = valeursDuBilan().evaluate().toList();
      expect(valeurs, hasLength(4));

      // Ordre de la zone : jours actifs, courses, bons conseils, réussite.
      final couleursAttendues = <Color>[
        kCouleurJours, // const Color(0xFF42A5F5)
        Colors.white54, // courses
        kCouleurBons, // bons conseils (_cGreen)
        kCouleurTauxVert, // réussite : 100 % ≥ 30 % → _cGreen
      ];

      for (int i = 0; i < 4; i++) {
        final t = valeurs[i].widget as Text;
        expect(t.style?.color, couleursAttendues[i],
            reason: 'couleur de la statistique #$i');
        expect(t.style?.fontSize, 17, reason: 'taille de la statistique #$i');
        expect(t.style?.fontWeight, FontWeight.bold,
            reason: 'graisse de la statistique #$i');
      }

      // Libellés : 14 dp, blanc 38 — inchangés.
      for (final libelle in kLibelles) {
        final t = tester.widget<Text>(libelleDuBilan(libelle));
        expect(t.style?.color, Colors.white38, reason: libelle);
        expect(t.style?.fontSize, 14, reason: libelle);
      }
    });

    testWidgets('E-T9 — les trois séparateurs `_divV` sont toujours présents',
        (tester) async {
      await pomperEtCapturer(tester, 480);
      expect(separateursDuBilan(tester), findsNWidgets(3),
          reason: '3 séparateurs verticaux sur la disposition à 4 colonnes');
    });

    testWidgets('E-T10 — l\'ordre de la page est préservé', (tester) async {
      await pomperEtCapturer(tester, 393);

      // Ordre du build : header → légende → grille mensuelle → bilan → …
      expect(find.text('📊 Bilan du mois'), findsOneWidget);
      expect(libelleDuBilan('jours actifs'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);

      final rectBilan = tester.getRect(find.text('📊 Bilan du mois'));
      final rectGrille = tester.getRect(find.text('L'));
      expect(rectGrille.bottom, lessThan(rectBilan.top),
          reason: 'la grille mensuelle précède le bilan du mois');
    });

    testWidgets('E-T11 — la grille mensuelle (7 colonnes) reste intacte',
        (tester) async {
      await pomperEtCapturer(tester, 393);

      expect(find.text('L'), findsOneWidget);
      expect(find.text('M'), findsNWidgets(2));
      expect(find.text('J'), findsOneWidget);
      expect(find.text('V'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);

      final now = DateTime.now();
      final dernierJour = DateTime(now.year, now.month + 1, 0).day;
      expect(find.text('$dernierJour'), findsWidgets,
          reason: 'dernier jour du mois toujours affiché');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC E-3 — DISPOSITION RESPONSIVE
  // ═══════════════════════════════════════════════════════════════════════

  group('E-3 — disposition responsive', () {
    /// Nombre de lignes distinctes des quatre statistiques.
    ///
    /// On mesure le haut des **valeurs** (premier enfant de chaque `_statBox`) :
    /// deux boîtes d'une même ligne partagent la même ordonnée, alors que
    /// mesurer les libellés serait faux — leur haut dépend de la hauteur
    /// variable de la valeur qui les précède.
    /// Mesure le CENTRE VERTICAL de chaque `_statBox` (la `Column` ancêtre de
    /// chaque valeur). On ne peut pas utiliser le haut des valeurs : les boîtes
    /// d'une même ligne sont centrées verticalement les unes par rapport aux
    /// autres, donc leurs valeurs n'ont pas la même ordonnée quand les
    /// libellés n'occupent pas le même nombre de lignes.
    int lignesDesStats(WidgetTester tester) {
      final centres = <double>[];
      for (final e in valeursDuBilan().evaluate()) {
        final colonne = find
            .ancestor(
              of: find.byWidget(e.widget),
              matching: find.byType(Column),
            )
            .evaluate()
            .first;
        final box = colonne.renderObject! as RenderBox;
        final centre =
            box.localToGlobal(Offset(0, box.size.height / 2)).dy;
        if (!centres.any((c) => (c - centre).abs() < 1.0)) centres.add(centre);
      }
      return centres.length;
    }

    testWidgets('E-T12 — 320 dp : deux lignes de deux statistiques',
        (tester) async {
      await pomperEtCapturer(tester, 320);
      expect(lignesDesStats(tester), 2,
          reason: '320 dp : disposition 2 × 2');
    });

    testWidgets('E-T13 — 480 dp : une seule ligne de quatre statistiques',
        (tester) async {
      await pomperEtCapturer(tester, 480);
      expect(lignesDesStats(tester), 1,
          reason: '480 dp : 4 colonnes sur une ligne');
    });

    testWidgets('E-T14 — aucun libellé tronqué, même à 320 dp',
        (tester) async {
      await pomperEtCapturer(tester, 320);

      for (final libelle in kLibelles) {
        final finder = libelleDuBilan(libelle);
        expect(_renduIntegralement(tester, finder), isTrue,
            reason: '« $libelle » doit être rendu intégralement à 320 dp');

        final t = tester.widget<Text>(finder);
        expect(t.maxLines, isNull,
            reason: 'aucune limite de lignes imposée à « $libelle »');
        expect(t.overflow, isNot(TextOverflow.ellipsis),
            reason: '« $libelle » ne doit pas être coupé');
      }
    });

    testWidgets('E-T15 — aucune police ni taille réduite à 320 dp',
        (tester) async {
      await pomperEtCapturer(tester, 320);

      for (final e in valeursDuBilan().evaluate()) {
        final t = e.widget as Text;
        expect(t.style?.fontSize, 17, reason: 'valeur « ${t.data} »');
        expect(t.style?.fontWeight, FontWeight.bold);
      }
      for (final libelle in kLibelles) {
        final t = tester.widget<Text>(libelleDuBilan(libelle));
        expect(t.style?.fontSize, 14,
            reason: '$libelle : police alignée sur l\'origine');
      }
    });

    // Un test PAR largeur : ré-amorcer le store au sein d'un même test
    // laisserait pendants les `Future.delayed(800 ms)` de `_onMemChange`.
    for (final largeur in kLargeurs) {
      testWidgets(
          'E-T16-${largeur.toInt()} — $largeur dp : les quatre blocs restent '
          'dans la largeur écran', (tester) async {
        final debordements = await pomperEtCapturer(tester, largeur);
        expectAucunDebordement(debordements, largeur);

        for (final e in valeursDuBilan().evaluate()) {
          final box = e.renderObject! as RenderBox;
          final pos = box.localToGlobal(Offset.zero);
          expect(pos.dx, greaterThanOrEqualTo(-0.5),
              reason: 'valeur déborde à gauche à $largeur dp');
          expect(pos.dx + box.size.width, lessThanOrEqualTo(largeur + 0.5),
              reason: 'valeur déborde à droite à $largeur dp');
        }

        // Les libellés aussi.
        for (final libelle in kLibelles) {
          final box =
              tester.renderObject<RenderBox>(libelleDuBilan(libelle));
          final pos = box.localToGlobal(Offset.zero);
          expect(pos.dx, greaterThanOrEqualTo(-0.5),
              reason: '$libelle déborde à gauche à $largeur dp');
          expect(pos.dx + box.size.width, lessThanOrEqualTo(largeur + 0.5),
              reason: '$libelle déborde à droite à $largeur dp');
        }
      });
    }
  });
}
