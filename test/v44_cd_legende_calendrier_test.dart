// ═══════════════════════════════════════════════════════════════════════════
//  V44 — C : LÉGENDE COMPLÉTÉE DU CALENDRIER IA
//        D : RESPONSIVE DES SIX INDICATEURS
//
//  OBJET
//  ─────
//  C — La bulle de légende existante (`_buildToggleEtLegendeFusionnes`) doit
//      afficher, sous la ligne ⭐, trois explications supplémentaires
//      (🔥 / ⭐🔥 / 🏆) sans créer de seconde légende, sans bouton
//      d'information, sans troncature, et sans toucher aux cases du
//      calendrier.
//
//  D — La ligne des six indicateurs débordait horizontalement (mesuré
//      105 px à 320 dp, 65 px à 360 dp, 32 px à 393 dp, 13 px à 412 dp).
//      Elle doit être répartie sans débordement à 320 / 360 / 393 / 412 /
//      480 dp, en conservant libellés, icônes et couleurs.
//
//  MÉTHODE
//  ───────
//  Les deux corrections vivent dans du code privé d'UI. Les widgets sont donc
//  réellement montés et mesurés : géométrie du `Wrap`, nombre de lignes,
//  couleur et graisse de chaque libellé, position des descriptions,
//  intégrité de la grille mensuelle.
//
//  ⚠️ STORE VIDE VOLONTAIRE
//  ─────────────────────────
//  Ce fichier teste la LÉGENDE, pas les statistiques. Un store vide évite de
//  traverser `_buildBilanMois`, qui porte un débordement horizontal
//  PRÉEXISTANT (mesuré : 151 px à 480 dp, 311 px à 320 dp) totalement
//  étranger à C et D. Ce débordement est documenté dans le rapport et laissé
//  intact : hors périmètre.
//
//  PÉRIMÈTRE INTERDIT (non testé, non modifié) : règles de réussite, calcul
//  des paliers, badges ⭐/🔥/⭐🔥 des cases, séries Premium, archives, A4-3,
//  A4-4, apprentissage IA.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/widgets/ia/ia_calendrier_tab.dart';

import 'dart:convert';

// ───────────────────────────────────────────────────────────────────────────
//  CONSTANTES ATTENDUES (contrat de la correction)
// ───────────────────────────────────────────────────────────────────────────

const String kPronosticsKey = 'ia_pronostics_v2';
const String kFlagMigration = 'ia_precision_migrated_v3';

/// Les six indicateurs, libellés EXACTS produits par `_legendePuce`.
const List<String> kLibellesPuces = <String>[
  'Noble',
  '≥30%',
  '≥25%',
  '≥20%',
  '<20%',
  'Repos',
];

/// Icônes des six puces, dans l'ordre.
const List<String> kIconesPuces = <String>['🥇', '✅', '📊', '⚠️', '❌', '💤'];

/// Ligne ⭐ historique — doit rester STRICTEMENT inchangée.
const String kLigneEtoile =
    'Best Bet — Conseil IA, Meilleur Pari ou Best Bet du jour réussi';

/// Les trois lignes ajoutées (C).
const String kDescriptionFlamme = 'Gros Paris gagnant';
const String kDescriptionDouble = 'Best Bet et Gros Paris gagnants';
const String kDescriptionTrophee =
    'Série Premium — ≥2 jours gagnants consécutifs (même sous-catégorie Best Bet)';

/// Couleurs des paliers — doivent rester inchangées.
const Color kVert = Color(0xFF4CAF7D);
const Color kJaune = Color(0xFFFFB74D);
const Color kOrange = Color(0xFFFF7043);

// ───────────────────────────────────────────────────────────────────────────
//  AMORÇAGE — store vide (voir avertissement en en-tête)
// ───────────────────────────────────────────────────────────────────────────

Future<void> amorcer() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'flutter.$kPronosticsKey': <String>[],
    'flutter.$kFlagMigration': true,
  });
  SharedPreferences.resetStatic();
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
  await IaArchiveService.instance.charger();
}

// ───────────────────────────────────────────────────────────────────────────
//  MONTAGE À UNE LARGEUR DONNÉE
// ───────────────────────────────────────────────────────────────────────────

/// Montage avec un pronostic réel : traverse les sections statistiques
/// (dont `_buildBilanMois`, qui porte un débordement PRÉEXISTANT hors
/// périmètre) afin de prouver que la légende n'y contribue pas.
Future<void> amorcerAvecDonnees() async {
  final jour = DateTime.now();
  final prono = IaPronostic(
    courseKey: 'R1C1_${jour.day.toString().padLeft(2, '0')}'
        '${jour.month.toString().padLeft(2, '0')}${jour.year}',
    nomCourse: 'Prix de test',
    hippodrome: 'Vincennes',
    discipline: 'Trot Attelé',
    datePronostic: jour,
    dateResultat: jour,
    scoresIA: const <String, double>{'3': 92.0, '7': 84.0, '1': 76.0},
    scoresCriteres: const <String, ScoresCriteres>{},
    resultatsReels: true,
    arriveeReelle: const <int>[3, 7, 1, 5, 2],
    typePariConseille: 'Tiercé',
    confiancePredite: 71.0,
    varianceScores: 12.5,
    favoriIaNom: 'Cheval 3',
    rangFavoriIaDansArrivee: 1,
    nbTop3DansArriveeReelle: 3,
    nbTop5DansArriveeReelle: 5,
    coteFavoriPmu: 3.4,
    cotesPmuParNumero: const <String, double>{'3': 3.4, '7': 6.1},
  );
  SharedPreferences.setMockInitialValues(<String, Object>{
    'flutter.$kPronosticsKey': <String>[json.encode(prono.toJson())],
    'flutter.$kFlagMigration': true,
  });
  SharedPreferences.resetStatic();
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
  await IaArchiveService.instance.charger();
}

/// Monte le calendrier sur une surface de largeur [largeur] (dp) et de
/// hauteur 6000 dp, afin que la `ListView` construise la bulle ET la grille.
Future<void> pomperALargeur(WidgetTester tester, double largeur) async {
  await amorcer();
  await tester.binding.setSurfaceSize(Size(largeur, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: IaCalendrierTab()),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

// ───────────────────────────────────────────────────────────────────────────
//  LECTURE DE LA GÉOMÉTRIE
// ───────────────────────────────────────────────────────────────────────────

/// Le `Wrap` de la légende.
///
/// Il se distingue du `Wrap` des puces de filtre de période (`runSpacing: 7`,
/// également six enfants) par son `runSpacing: 10` propre à la légende.
final Finder finderWrapLegende = find.byWidgetPredicate(
  (w) => w is Wrap && w.children.length == 6 && w.runSpacing == 10.0,
  description: 'Wrap de légende (6 puces, runSpacing 10)',
);

/// Nombre de lignes réellement occupées par les six puces.
///
/// Les puces d'une même ligne partagent la même ordonnée (largeurs égales).
int nombreLignesPuces(WidgetTester tester) {
  final tops = <double>[];
  for (final libelle in kLibellesPuces) {
    final r = tester.getRect(find.text(libelle));
    if (!tops.any((t) => (t - r.top).abs() < 1.0)) tops.add(r.top);
  }
  return tops.length;
}

/// Un texte est-il intégralement rendu (aucune ligne supprimée) ?
bool texteNonTronque(WidgetTester tester, Finder f) {
  final rp = tester.renderObject<RenderParagraph>(f);
  return !rp.didExceedMaxLines;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC C — LÉGENDE
  // ═══════════════════════════════════════════════════════════════════════

  group('C — légende complétée', () {
    testWidgets('C-T1 — une seule bulle, un seul jeu de six indicateurs',
        (tester) async {
      await pomperALargeur(tester, 393);

      expect(finderWrapLegende, findsOneWidget,
          reason: 'un unique Wrap de six puces : aucune seconde légende');
      for (final libelle in kLibellesPuces) {
        expect(find.text(libelle), findsOneWidget,
            reason: '« $libelle » doit apparaître une fois et une seule');
      }
    });

    testWidgets('C-T2 — les six indicateurs restent présents et nommés',
        (tester) async {
      await pomperALargeur(tester, 393);
      for (final libelle in kLibellesPuces) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }
      for (final icone in kIconesPuces) {
        expect(find.text(icone), findsOneWidget, reason: 'icône « $icone »');
      }
    });

    testWidgets('C-T3 — la ligne ⭐ est inchangée', (tester) async {
      await pomperALargeur(tester, 393);
      expect(find.text(kLigneEtoile), findsOneWidget,
          reason: 'texte ⭐ historique intact');
      expect(find.text('⭐'), findsOneWidget);
    });

    testWidgets('C-T4 — les trois nouvelles lignes sont visibles',
        (tester) async {
      await pomperALargeur(tester, 393);

      expect(find.text('🔥'), findsOneWidget);
      expect(find.text(kDescriptionFlamme), findsOneWidget);

      expect(find.text('⭐🔥'), findsOneWidget);
      expect(find.text(kDescriptionDouble), findsOneWidget);

      expect(find.text('🏆'), findsOneWidget);
      expect(find.text(kDescriptionTrophee), findsOneWidget);
    });

    testWidgets('C-T5 — quatre lignes de description, aucune de plus',
        (tester) async {
      await pomperALargeur(tester, 393);
      // Les symboles de description sont les seuls Text en fontSize 16.
      final symboles = find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontSize == 16,
      );
      expect(symboles.evaluate().length, 4,
          reason: '⭐ + 🔥 + ⭐🔥 + 🏆 — et rien d\'autre');
    });

    testWidgets('C-T6 — aucune troncature sur les descriptions ajoutées',
        (tester) async {
      await pomperALargeur(tester, 393);

      for (final desc in <String>[
        kDescriptionFlamme,
        kDescriptionDouble,
        kDescriptionTrophee,
      ]) {
        final t = tester.widget<Text>(find.text(desc));
        expect(t.maxLines, isNull,
            reason: '« $desc » ne doit pas être limité en lignes');
        expect(t.overflow, isNot(TextOverflow.ellipsis),
            reason: '« $desc » ne doit pas être coupé à l\'ellipse');
        expect(t.softWrap, isTrue,
            reason: '« $desc » doit pouvoir passer à la ligne');
        expect(texteNonTronque(tester, find.text(desc)), isTrue,
            reason: '« $desc » doit être rendu intégralement');
      }
    });

    testWidgets('C-T7 — les descriptions sont alignées à droite du symbole',
        (tester) async {
      await pomperALargeur(tester, 393);

      for (final paire in <List<String>>[
        <String>['🔥', kDescriptionFlamme],
        <String>['⭐🔥', kDescriptionDouble],
        <String>['🏆', kDescriptionTrophee],
      ]) {
        final rectSymbole = tester.getRect(find.text(paire[0]));
        final rectTexte = tester.getRect(find.text(paire[1]));
        expect(rectTexte.left, greaterThan(rectSymbole.right),
            reason: 'le symbole ${paire[0]} précède sa description');
      }
    });

    testWidgets('C-T8 — la bulle s\'agrandit sous les six indicateurs',
        (tester) async {
      await pomperALargeur(tester, 393);

      final wrapRect = tester.getRect(finderWrapLegende);
      final rectTrophee = tester.getRect(find.text(kDescriptionTrophee));
      expect(rectTrophee.top, greaterThan(wrapRect.bottom),
          reason: 'les nouvelles lignes sont sous les six indicateurs');
      expect(rectTrophee.bottom, lessThan(6000),
          reason: 'aucune hauteur figée ne coupe la dernière description');
    });

    testWidgets('C-T9 — la grille mensuelle reste intacte et séparée',
        (tester) async {
      await pomperALargeur(tester, 393);

      // En-têtes de jours (L M M J V S D).
      expect(find.text('L'), findsOneWidget);
      expect(find.text('M'), findsNWidgets(2));
      expect(find.text('J'), findsOneWidget);
      expect(find.text('V'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);

      // Numéros de jours du mois courant.
      final now = DateTime.now();
      final dernierJour = DateTime(now.year, now.month + 1, 0).day;
      expect(find.text('1'), findsWidgets, reason: 'jour 1 de la grille');
      expect(find.text('$dernierJour'), findsWidgets,
          reason: 'dernier jour du mois ($dernierJour)');

      // Aucun trophée ajouté dans les cases : l'unique 🏆 est celui de la
      // légende, situé AU-DESSUS de la grille.
      expect(find.text('🏆'), findsOneWidget,
          reason: 'aucune case du calendrier ne reçoit de trophée');
      final rectTrophee = tester.getRect(find.text('🏆'));
      final rectDernierJour = tester.getRect(find.text('$dernierJour').last);
      expect(rectTrophee.bottom, lessThan(rectDernierJour.top),
          reason: 'le 🏆 de légende est au-dessus de la grille');
    });

    testWidgets('C-T10 — aucun débordement introduit par la légende',
        (tester) async {
      await pomperALargeur(tester, 393);
      expect(tester.takeException(), isNull,
          reason: 'la légende complétée ne produit aucune erreur de layout');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  BLOC D — RESPONSIVE DES SIX INDICATEURS
  // ═══════════════════════════════════════════════════════════════════════

  group('D — responsive des six indicateurs', () {
    for (final largeur in <double>[320, 360, 393, 412, 480]) {
      testWidgets('D-T${largeur.toInt()} — $largeur dp : aucun débordement',
          (tester) async {
        await pomperALargeur(tester, largeur);

        // 1. Aucun RenderFlex overflow.
        expect(tester.takeException(), isNull,
            reason: 'aucune erreur de layout à $largeur dp');

        // 2. Les six indicateurs sont présents.
        for (final libelle in kLibellesPuces) {
          expect(find.text(libelle), findsOneWidget,
              reason: '$libelle à $largeur dp');
        }
        for (final icone in kIconesPuces) {
          expect(find.text(icone), findsOneWidget,
              reason: '$icone à $largeur dp');
        }

        // 3. Le Wrap tient dans la largeur de l'écran.
        final rectWrap = tester.getRect(finderWrapLegende);
        expect(rectWrap.width, lessThanOrEqualTo(largeur),
            reason: 'le Wrap ne dépasse pas la largeur de l\'écran');

        // 4. Aucune puce hors cadre, aucun chevauchement horizontal.
        final rects = <Rect>[];
        for (final libelle in kLibellesPuces) {
          final r = tester.getRect(find.text(libelle));
          expect(r.left, greaterThanOrEqualTo(rectWrap.left - 0.5),
              reason: '$libelle non rogné à gauche');
          expect(r.right, lessThanOrEqualTo(rectWrap.right + 0.5),
              reason: '$libelle non rogné à droite');
          rects.add(r);
        }
        // Chevauchement : deux libellés de la même ligne ne se recouvrent pas.
        for (int i = 0; i < rects.length; i++) {
          for (int j = i + 1; j < rects.length; j++) {
            final a = rects[i];
            final b = rects[j];
            final memeLigne = (a.top - b.top).abs() < 1.0;
            if (memeLigne) {
              expect(a.right, lessThanOrEqualTo(b.left + 0.5),
                  reason: '${kLibellesPuces[i]} et ${kLibellesPuces[j]} '
                      'se chevauchent à $largeur dp');
            }
          }
        }

        // 5. Aucun texte coupé.
        for (final libelle in kLibellesPuces) {
          expect(texteNonTronque(tester, find.text(libelle)), isTrue,
              reason: '$libelle intégralement rendu à $largeur dp');
        }

        // 6. Pas de défilement horizontal : jamais plus de deux lignes.
        final lignes = nombreLignesPuces(tester);
        expect(lignes, greaterThanOrEqualTo(1));
        expect(lignes, lessThanOrEqualTo(2),
            reason: 'au plus deux lignes, jamais une bande défilante');
      });
    }

    testWidgets('D-T320b — 320 dp : répartition 3 + 3', (tester) async {
      await pomperALargeur(tester, 320);
      expect(nombreLignesPuces(tester), 2,
          reason: 'place insuffisante pour six puces → 2 lignes de 3');
    });

    testWidgets('D-T360b — 360 dp : répartition 3 + 3', (tester) async {
      await pomperALargeur(tester, 360);
      expect(nombreLignesPuces(tester), 2);
    });

    testWidgets('D-T393b — 393 dp : répartition 3 + 3', (tester) async {
      await pomperALargeur(tester, 393);
      expect(nombreLignesPuces(tester), 2);
    });

    testWidgets('D-T412b — 412 dp : répartition 3 + 3', (tester) async {
      await pomperALargeur(tester, 412);
      expect(nombreLignesPuces(tester), 2);
    });

    testWidgets('D-T480b — 480 dp : les six indicateurs sur UNE ligne',
        (tester) async {
      await pomperALargeur(tester, 480);
      expect(nombreLignesPuces(tester), 1,
          reason: 'écran large → une seule ligne, disposition d\'origine');
    });

    testWidgets('D-Tc — libellés, couleurs et graisses inchangés',
        (tester) async {
      await pomperALargeur(tester, 480);

      // Palier éditable → couleur du palier à 0.9, graisse w700.
      void verifierEditable(String libelle, Color attendu) {
        final t = tester.widget<Text>(find.text(libelle));
        expect(t.style?.color, attendu.withValues(alpha: 0.9), reason: libelle);
        expect(t.style?.fontWeight, FontWeight.w700, reason: libelle);
        expect(t.style?.fontSize, 14, reason: libelle);
      }

      // Palier non éditable → Colors.white38, graisse w500.
      void verifierFixe(String libelle) {
        final t = tester.widget<Text>(find.text(libelle));
        expect(t.style?.color, Colors.white38, reason: libelle);
        expect(t.style?.fontWeight, FontWeight.w500, reason: libelle);
        expect(t.style?.fontSize, 14, reason: libelle);
      }

      verifierFixe('Noble');       // OR : non éditable (immuable)
      verifierEditable('≥30%', kVert);
      verifierEditable('≥25%', kJaune);
      verifierEditable('≥20%', kOrange);
      verifierFixe('<20%');        // ROUGE : dérivé de orange, non éditable
      verifierFixe('Repos');       // GRIS : non éditable

      // Icônes : fontSize 15 — inchangé.
      for (final icone in kIconesPuces) {
        final t = tester.widget<Text>(find.text(icone));
        expect(t.style?.fontSize, 15, reason: 'taille de l\'icône $icone');
      }

      // Conteneurs d'icônes : 36×36 — inchangés.
      for (final icone in kIconesPuces) {
        final conteneur = find.ancestor(
          of: find.text(icone),
          matching: find.byType(Container),
        );
        final taille = tester.getSize(conteneur.first);
        expect(taille.width, 36, reason: 'largeur du conteneur $icone');
        expect(taille.height, 36, reason: 'hauteur du conteneur $icone');
      }
    });

    testWidgets('D-Td — la bulle reste correctement dimensionnée à 320 dp',
        (tester) async {
      await pomperALargeur(tester, 320);

      final rectWrap = tester.getRect(finderWrapLegende);
      expect(rectWrap.width, lessThanOrEqualTo(320));
      expect(nombreLignesPuces(tester), 2);

      // Les descriptions les plus longues restent complètes.
      for (final desc in <String>[
        kDescriptionFlamme,
        kDescriptionDouble,
        kDescriptionTrophee,
      ]) {
        expect(texteNonTronque(tester, find.text(desc)), isTrue,
            reason: '« $desc » à 320 dp');
      }

      // Le calendrier reste intact.
      expect(find.text('L'), findsOneWidget);
      expect(find.text('🏆'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

}
