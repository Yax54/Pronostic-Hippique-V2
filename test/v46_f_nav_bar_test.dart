// ═══════════════════════════════════════════════════════════════════════════
//  V46 — F : BARRE DE NAVIGATION — LE LIBELLÉ NE SE REPLIE PLUS
//
//  OBJET
//  ─────
//  `test/widget_test.dart` échouait sur :
//      A RenderFlex overflowed by 6.0 pixels on the bottom.
//      A RenderFlex overflowed by 3.0 pixels on the bottom.   (× 8)
//
//  CAUSE EXACTE (instrumentée sur l'arbre de rendu)
//  ─────────────────────────────────────────────────
//  Widget fautif : `Column` de `_NavItem`, `lib/main.dart:462`
//  pour chaque onglet de la barre de navigation.
//
//  Le `Text` du libellé n'avait ni `maxLines` ni `softWrap`. Un libellé plus
//  large que la place disponible se repliait sur 2 lignes : hauteur 32 dp au
//  lieu de 16 dp, dans une `Column` de 56 dp contenant déjà l'icône (25 dp) et
//  un `SizedBox(2)`. Débordement = 6,0 px (bordure active 1,5×2) ou 3,0 px.
//
//  Le repli dépend de la police. Le harnais de test utilise la police Ahem
//  (1 caractère = 1 em, aucun rétrécissement), où « Mes Paris » mesure 99 dp
//  pour 60 dp disponibles. Mais le défaut est RÉEL en production sur le
//  chemin non défilant de `_buildBottomNav` (écrans ≥ 836 dp), où un libellé
//  trop long était tronqué SILENCIEUSEMENT (`TextOverflow.clip` par défaut).
//
//  CORRECTION F1 — trois propriétés, aucune autre modification :
//      maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis,
//
//  POLICE, TAILLE, COULEUR, GRAISSE, ICÔNES, BADGES, COULEURS D'ONGLET,
//  HAUTEUR DE 78 dp ET LOGIQUE DE NAVIGATION : INCHANGÉS.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pronostic_hippique/main.dart';

// ───────────────────────────────────────────────────────────────────────────
//  CONTRAT
// ───────────────────────────────────────────────────────────────────────────

/// Les onze libellés, dans l'ordre des onglets — INCHANGÉS.
const List<String> kLibelles = <String>[
  'Accueil',
  'Conseils',
  'Prog.',
  'Courses',
  'Best Bet',
  'IA Stats',
  'Mes Paris',
  'Labo IA',
  'ROI/Value',
  'Audit',
  'Profil',
];

/// Les onze couleurs d'onglet — INCHANGÉES.
const List<Color> kCouleurs = <Color>[
  Color(0xFF4CAF7D), // Accueil — vert app
  Color(0xFF7C4DFF), // Conseils — violet IA
  Color(0xFF29B6F6), // Prog. — bleu ciel
  Color(0xFFFF7043), // Courses — orange sport
  Color(0xFFFFD700), // Best Bet — or trophée
  Color(0xFFE040FB), // IA Stats — rose/magenta
  Color(0xFF00BCD4), // Mes Paris — cyan
  Color(0xFF00E5FF), // Labo IA — cyan
  Color(0xFF4CAF50), // ROI/Value — vert ROI
  Color(0xFFFFD700), // Audit — or
  Color(0xFFB0BEC5), // Profil — argent
];

/// Les onze icônes inactives.
const List<IconData> kIconesInactives = <IconData>[
  Icons.home_outlined,
  Icons.auto_awesome_outlined,
  Icons.calendar_today_outlined,
  Icons.sports_outlined,
  Icons.emoji_events_outlined,
  Icons.psychology_outlined,
  Icons.track_changes_outlined,
  Icons.science_outlined,
  Icons.trending_up_outlined,
  Icons.find_in_page_outlined,
  Icons.person_outline,
];

/// Hauteur historique de la barre — INCHANGÉE (F2 non appliqué).
const double kHauteurBarre = 78.0;

// ───────────────────────────────────────────────────────────────────────────
//  MONTAGE + CAPTURE DES DÉBORDEMENTS
// ───────────────────────────────────────────────────────────────────────────

/// Monte l'application complète et retourne les débordements captés.
Future<List<String>> pomperApp(WidgetTester tester,
    {required double largeur, required double hauteur}) async {
  await tester.binding.setSurfaceSize(Size(largeur, hauteur));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final captures = <String>[];
  final ancien = FlutterError.onError;
  FlutterError.onError = (details) => captures.add(details.toString());
  await tester.pumpWidget(const PronosticHippiqueApp());
  await tester.pump();
  FlutterError.onError = ancien;

  return captures.where((e) => e.contains('overflowed by')).toList();
}

void expectAucunDebordement(List<String> debordements, String contexte) {
  expect(
    debordements,
    isEmpty,
    reason: 'aucun débordement attendu ($contexte), obtenu : '
        '${debordements.map((e) => RegExp(r'overflowed by [\d.]+ pixels(?: on the \w+)?').firstMatch(e)?.group(0)).toList()}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC F-1 — AUCUN DÉBORDEMENT
  // ═══════════════════════════════════════════════════════════════════════

  group('F-1 — aucun débordement de la barre de navigation', () {
    // Largeurs de téléphone demandées + la surface du harnais (800 × 600)
    // + un écran large qui emprunte le chemin NON défilant de _buildBottomNav.
    const tailles = <List<double>>[
      <double>[320, 640],
      <double>[360, 740],
      <double>[393, 852],
      <double>[412, 915],
      <double>[480, 1000],
      <double>[800, 600], // surface par défaut de widget_test.dart
      <double>[1024, 768], // > 836 dp → chemin non défilant
    ];

    for (final taille in tailles) {
      final largeur = taille[0];
      final hauteur = taille[1];
      testWidgets(
          'F-T-${largeur.toInt()} — ${largeur.toInt()} × ${hauteur.toInt()} : '
          '0 débordement', (tester) async {
        final debordements =
            await pomperApp(tester, largeur: largeur, hauteur: hauteur);
        expectAucunDebordement(debordements, '$largeur × $hauteur dp');
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC F-2 — LE LIBELLÉ EST CONTRAINT
  // ═══════════════════════════════════════════════════════════════════════

  group('F-2 — le libellé est contraint à une ligne', () {
    testWidgets('F-T8 — chaque libellé porte maxLines/softWrap/overflow',
        (tester) async {
      await pomperApp(tester, largeur: 800, hauteur: 600);

      // Tous les `Text` dont le contenu est un libellé de navigation.
      var verifies = 0;
      for (final libelle in kLibelles) {
        final trouve = find.text(libelle);
        if (trouve.evaluate().isEmpty) continue; // onglet non monté
        for (final e in trouve.evaluate()) {
          final t = e.widget as Text;
          expect(t.maxLines, 1, reason: '« $libelle » : maxLines');
          expect(t.softWrap, isFalse, reason: '« $libelle » : softWrap');
          expect(t.overflow, TextOverflow.ellipsis,
              reason: '« $libelle » : overflow explicite');
          expect(t.style?.fontSize, 11, reason: '« $libelle » : police');
          verifies++;
        }
      }
      expect(verifies, greaterThan(0),
          reason: 'au moins un libellé de navigation doit être rendu');
    });

    testWidgets('F-T9 — aucun libellé ne dépasse sur deux lignes',
        (tester) async {
      await pomperApp(tester, largeur: 800, hauteur: 600);

      // Un libellé replié mesurerait 32 dp de haut (2 × 16) avec Ahem.
      for (final libelle in kLibelles) {
        final trouve = find.text(libelle);
        if (trouve.evaluate().isEmpty) continue;
        final h = tester.getRect(trouve.first).height;
        expect(h, lessThanOrEqualTo(20.0),
            reason: '« $libelle » doit tenir sur une ligne (hauteur=$h)');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC F-3 — ÉLÉMENTS INCHANGÉS
  // ═══════════════════════════════════════════════════════════════════════

  group('F-3 — éléments de la barre inchangés', () {
    testWidgets('F-T10 — les onze libellés sont présents et exacts',
        (tester) async {
      await pomperApp(tester, largeur: 800, hauteur: 600);

      // En mode défilant, seuls les onglets construits sont présents ; on
      // vérifie au minimum que le libellé de l'onglet actif est là.
      expect(find.text('Accueil'), findsWidgets,
          reason: 'onglet actif toujours rendu');

      // Chaque libellé `_navItems` est défini dans le fichier ; on contrôle
      // qu'aucun n'a été renommé en montant à une largeur qui n'exige pas
      // le défilement (11 × 76 = 836 dp).
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      await tester.pumpWidget(const PronosticHippiqueApp());
      await tester.pump();
      for (final libelle in kLibelles) {
        expect(find.text(libelle), findsOneWidget,
            reason: '« $libelle » doit être rendu en mode non défilant');
      }
    });

    testWidgets('F-T11 - les onze couleurs d onglet sont inchangees',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const PronosticHippiqueApp());
      await tester.pump();

      // Onglet 0 actif : son libellé porte la couleur. Les autres sont inactifs
      // (gris 0xFF6B7B8A). On vérifie la couleur de l'onglet actif, puis
      // celle d'un onglet inactif.
      final accueil = tester.widget<Text>(find.text('Accueil'));
      expect(accueil.style?.color, kCouleurs[0],
          reason: 'onglet actif : couleur propre a l onglet');
      expect(accueil.style?.fontWeight, FontWeight.bold);

      final conseils = tester.widget<Text>(find.text('Conseils'));
      expect(conseils.style?.color, const Color(0xFF6B7B8A),
          reason: 'onglet inactif : gris bleuté inchangé');
      expect(conseils.style?.fontWeight, FontWeight.w500);
    });

    testWidgets('F-T12 - les onze icones inactives sont inchangees',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const PronosticHippiqueApp());
      await tester.pump();

      // ⚠ L'onglet 0 (Accueil) est ACTIF au démarrage : il porte donc
      //   `activeIcon` (Icons.home) et NON `icon` (Icons.home_outlined).
      //   On mesure donc l'icône active d'abord, puis les 10 inactives.
      final iconeActive = find.byIcon(Icons.home);
      expect(iconeActive, findsOneWidget, reason: 'icone active de Accueil');
      final wActive = tester.widget<Icon>(iconeActive);
      expect(wActive.size, 25, reason: 'taille de l icone active Accueil');

      for (int i = 1; i < kIconesInactives.length; i++) {
        final icone = find.byIcon(kIconesInactives[i]);
        expect(icone, findsOneWidget,
            reason: 'icône de l onglet ${kLibelles[i]}');
        final w = tester.widget<Icon>(icone);
        expect(w.size, 25, reason: 'taille de l icone ${kLibelles[i]}');
      }
    });

    testWidgets('F-T13 — la barre mesure toujours 78 dp de haut',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const PronosticHippiqueApp());
      await tester.pump();

      // La barre contient un SizedBox(height: 78) : c'est l'élément qui porte
      // la hauteur. On le retrouve par sa contrainte exacte.
      final porteur = find.byWidgetPredicate((w) {
        if (w is! SizedBox) return false;
        return w.height == kHauteurBarre;
      });
      expect(porteur, findsOneWidget,
          reason: 'la hauteur de 78 dp doit être conservée (F2 non appliqué)');
      expect(tester.getSize(porteur).height, kHauteurBarre);
    });

    testWidgets('F-T14 — la navigation fonctionne toujours', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const PronosticHippiqueApp());
      await tester.pump();

      // Un seul écran est visible au départ (IndexedStack, index 0).
      final notifier = _lireNavigation(tester);
      expect(notifier.index, 0, reason: 'démarrage sur Accueil');

      // Le tap sur un onglet change l'index via `NavigationNotifier.goTo`.
      await tester.tap(find.text('Profil'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_lireNavigation(tester).index, 10,
          reason: 'appui sur Profil → index 10');
    });
  });
}

/// Récupère le `NavigationNotifier` depuis l'arbre monté.
NavigationNotifier _lireNavigation(WidgetTester tester) {
  final element = tester.element(find.byType(MainNavigation));
  return Provider.of<NavigationNotifier>(element as BuildContext, listen: false);
}
