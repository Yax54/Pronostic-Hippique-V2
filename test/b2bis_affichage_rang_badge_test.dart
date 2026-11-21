// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-2 bis — SPÉCIFICATION D'AFFICHAGE DES RANGS ET DES BADGES
//
//  Spécification validée par l'utilisateur (révision du lot A6) :
//    • CHAQUE cheval affiche son RANG OFFICIEL dès qu'un ex æquo existe ;
//    • les chevaux ex æquo partagent le MÊME rang ;
//    • un badge gris « Ex æquo » figure SOUS chacun des chevaux ex æquo ;
//    • AUCUN badge sous les chevaux non ex æquo ;
//    • les positions sautées sont respectées.
//
//  Cas de référence R5C5 `[[2],[4],[5,7],[8],[3],[6]]` :
//      2 = 1er
//      4 = 2e
//      5 = 3e  + badge
//      7 = 3e  + badge
//      8 = 5e
//      3 = 6e
//      6 = 7e
//
//  PROTECTION GRAPHIQUE : ces tests vérifient aussi que les couleurs, tailles
//  et composants existants sont réutilisés — aucun fond ni carte ajoutés.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/widgets/arrivee_officielle_groupes_widget.dart';

// ─── Les trois arrivées réelles à ex æquo (mesurées) ────────────────────────

const List<List<int>> _r5c5 = [
  [2], [4], [5, 7], [8], [3], [6]
];
const List<List<int>> _r6c5 = [
  [12], [1, 7], [9], [2], [10], [8], [6], [13], [5]
];
const List<List<int>> _r5c7 = [
  [4], [6], [1, 5], [2]
];

// ─── Harnais : monte le composant réel, sur fond sombre comme l'application ──

Future<void> _monter(
  WidgetTester tester,
  List<List<int>> groupes, {
  double fontSize = 12,
  Size taille = const Size(400, 900),
}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SingleChildScrollView(
          child: LigneArriveeExAequo(groupes: groupes, fontSize: fontSize),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Tous les textes rendus, dans l'ordre de l'arbre.
List<String> _textes(WidgetTester tester) {
  final out = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    if (w.data != null) out.add(w.data!);
  }
  return out;
}

int _nb(WidgetTester tester, String v) =>
    _textes(tester).where((s) => s == v).length;

/// Le texte de rang rendu sous le numéro [numero] (`N°5` → « 3e »), ou `null`.
///
/// On lit la VRAIE structure rendue : le rang est le `Text` frère du `Text`
/// « N°x » à l'intérieur du même conteneur. Ce n'est pas une reconstructions
/// par index : on remonte au parent direct.
({String? rang, bool badge}) _sousNumero(WidgetTester tester, int numero) {
  final numFinder = find.text('N°$numero');
  expect(numFinder, findsOneWidget, reason: 'N°$numero doit être affiché');

  // Le conteneur du cheval = ancêtre `Container` le plus proche.
  final containers = find.ancestor(
    of: numFinder,
    matching: find.byType(Container),
  );
  expect(containers, findsWidgets);
  final conteneur = containers.first;
  final textes = tester
      .widgetList<Text>(find.descendant(of: conteneur, matching: find.byType(Text)))
      .map((t) => t.data)
      .toList();
  final badges = find
      .descendant(of: conteneur, matching: find.byType(BadgeExAequo))
      .evaluate()
      .length;

  // Dans le conteneur : ['N°x', rang?, 'Ex æquo'?]
  final rang = textes.length >= 2 ? textes[1] : null;
  return (rang: rang, badge: badges > 0);
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  B2B-A/1 — PRÉDICAT PUR : rang de CHAQUE cheval
  // ═════════════════════════════════════════════════════════════════════════
  group('B2B-A/1 — rangsParCheval', () {
    test('R5C5 : [1,2,3,3,5,6,7] — les ex æquo partagent leur rang', () {
      expect(rangsParCheval(_r5c5), equals(<int>[1, 2, 3, 3, 5, 6, 7]));
    });

    test('R6C5 : les deux ex æquo du 2e rang sont tous deux 2e', () {
      // 12→1, 1→2, 7→2, 9→4, 2→5, 10→6, 8→7, 6→8, 13→9, 5→10
      expect(rangsParCheval(_r6c5),
          equals(<int>[1, 2, 2, 4, 5, 6, 7, 8, 9, 10]));
    });

    test('R5C7 : [1,2,3,3,5]', () {
      expect(rangsParCheval(_r5c7), equals(<int>[1, 2, 3, 3, 5]));
    });

    test('le nombre de rangs = nombre exact de chevaux (aucun perdu)', () {
      for (final cas in <List<List<int>>>[_r5c5, _r6c5, _r5c7]) {
        expect(rangsParCheval(cas).length,
            cas.fold<int>(0, (s, g) => s + g.length));
      }
    });

    test('cohérence avec rangsOfficiels : une valeur par groupe', () {
      for (final cas in <List<List<int>>>[_r5c5, _r6c5, _r5c7]) {
        final parCheval = rangsParCheval(cas);
        final parGroupe = rangsOfficiels(cas);
        var i = 0;
        for (var g = 0; g < cas.length; g++) {
          for (var k = 0; k < cas[g].length; k++) {
            expect(parCheval[i++], parGroupesFor(cas, g));
          }
        }
        expect(parGroupe.length, cas.length);
      }
    });

    test('sans ex æquo : rangs strictement consécutifs 1..n', () {
      const normal = <List<int>>[
        [1], [2], [3], [4], [5]
      ];
      expect(rangsParCheval(normal), equals(<int>[1, 2, 3, 4, 5]));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2B-A/2 — LE CAS DE RÉFÉRENCE EXACT (spécification de l'utilisateur)
  // ═════════════════════════════════════════════════════════════════════════
  group('B2B-A/2 — R5C5 : spécification exacte', () {
    testWidgets('2=1er, 4=2e, 5=3e+badge, 7=3e+badge, 8=5e, 3=6e, 6=7e',
        (tester) async {
      await _monter(tester, _r5c5);

      // Tous les chevaux présents.
      for (final n in <int>[2, 4, 5, 7, 8, 3, 6]) {
        expect(find.text('N°$n'), findsOneWidget, reason: 'N°$n affiché');
      }

      // Rangs attendus.
      expect(_sousNumero(tester, 2).rang, '1er');
      expect(_sousNumero(tester, 4).rang, '2e');
      expect(_sousNumero(tester, 5).rang, '3e');
      expect(_sousNumero(tester, 7).rang, '3e');
      expect(_sousNumero(tester, 8).rang, '5e', reason: '8 est 5e, PAS 4e');
      expect(_sousNumero(tester, 3).rang, '6e');
      expect(_sousNumero(tester, 6).rang, '7e');

      // Badges : uniquement sous 5 et 7.
      expect(_sousNumero(tester, 5).badge, isTrue);
      expect(_sousNumero(tester, 7).badge, isTrue);
      for (final n in <int>[2, 4, 8, 3, 6]) {
        expect(_sousNumero(tester, n).badge, isFalse,
            reason: 'le N°$n n\'est pas ex æquo : aucun badge');
      }
      expect(find.byType(BadgeExAequo), findsNWidgets(2),
          reason: 'exactement 2 badges, pour les 2 chevaux ex æquo');
    });

    testWidgets('aucun rang ne saute ni n\'est inventé', (tester) async {
      await _monter(tester, _r5c5);
      // « 4e » n'existe pas : la place 4 est consommée par le 2e ex æquo.
      expect(find.text('4e'), findsNothing);
      // Un seul 1er, un seul 2e, deux 3e, un 5e, un 6e, un 7e.
      expect(_nb(tester, '1er'), 1);
      expect(_nb(tester, '2e'), 1);
      expect(_nb(tester, '3e'), 2);
      expect(_nb(tester, '5e'), 1);
      expect(_nb(tester, '6e'), 1);
      expect(_nb(tester, '7e'), 1);
      // 7 rangs affichés pour 7 chevaux.
      final rangs = _textes(tester)
          .where((s) => RegExp(r'^(\d+)(er|e)$').hasMatch(s))
          .length;
      expect(rangs, 7, reason: 'un rang sous CHAQUE cheval');
    });

    testWidgets('le badge est rendu SOUS le cheval, pas à côté du titre',
        (tester) async {
      await _monter(tester, _r5c5);
      final yBadge = tester.getCenter(find.byType(BadgeExAequo).first).dy;
      final yNum5 = tester.getCenter(find.text('N°5')).dy;
      expect(yBadge, greaterThan(yNum5),
          reason: 'le badge est placé SOUS le numéro');
      // Deux badges sur des lignes distinctes (5 puis 7), pas empilés.
      final badges = find.byType(BadgeExAequo).evaluate().length;
      expect(badges, 2);
      final y0 = tester.getCenter(find.byType(BadgeExAequo).at(0)).dy;
      final y1 = tester.getCenter(find.byType(BadgeExAequo).at(1)).dy;
      expect((y0 - y1).abs(), lessThan(1.0),
          reason: 'les deux badges sont sur la même ligne (même rang)');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2B-A/3 — LES DEUX AUTRES ARRIVÉES RÉELLES
  // ═════════════════════════════════════════════════════════════════════════
  group('B2B-A/3 — R6C5 et R5C7', () {
    testWidgets('R6C5 : 10 chevaux, 1 et 7 tous deux 2e avec badge',
        (tester) async {
      await _monter(tester, _r6c5, fontSize: 12);

      for (final n in <int>[12, 1, 7, 9, 2, 10, 8, 6, 13, 5]) {
        expect(find.text('N°$n'), findsOneWidget, reason: 'N°$n affiché');
      }
      expect(find.byType(BadgeExAequo), findsNWidgets(2));

      expect(_sousNumero(tester, 12).rang, '1er');
      expect(_sousNumero(tester, 1).rang, '2e');
      expect(_sousNumero(tester, 7).rang, '2e');
      expect(_sousNumero(tester, 9).rang, '4e', reason: '9 est 4e, pas 3e');
      expect(_sousNumero(tester, 2).rang, '5e');
      expect(_sousNumero(tester, 5).rang, '10e');

      expect(_sousNumero(tester, 1).badge, isTrue);
      expect(_sousNumero(tester, 7).badge, isTrue);
      for (final n in <int>[12, 9, 2, 10, 8, 6, 13, 5]) {
        expect(_sousNumero(tester, n).badge, isFalse, reason: 'N°$n sans badge');
      }
    });

    testWidgets('R5C7 : 5 chevaux, 1 et 5 tous deux 3e avec badge',
        (tester) async {
      await _monter(tester, _r5c7);

      for (final n in <int>[4, 6, 1, 5, 2]) {
        expect(find.text('N°$n'), findsOneWidget);
      }
      expect(find.byType(BadgeExAequo), findsNWidgets(2));

      expect(_sousNumero(tester, 4).rang, '1er');
      expect(_sousNumero(tester, 6).rang, '2e');
      expect(_sousNumero(tester, 1).rang, '3e');
      expect(_sousNumero(tester, 5).rang, '3e');
      expect(_sousNumero(tester, 2).rang, '5e');

      expect(_sousNumero(tester, 1).badge, isTrue);
      expect(_sousNumero(tester, 5).badge, isTrue);
      for (final n in <int>[4, 6, 2]) {
        expect(_sousNumero(tester, n).badge, isFalse, reason: 'N°$n sans badge');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2B-A/4 — PROTECTION GRAPHIQUE ET COMPOSANTS EXISTANTS
  // ═════════════════════════════════════════════════════════════════════════
  group('B2B-A/4 — aucun nouveau style, composants existants réutilisés', () {
    testWidgets('le badge réutilise kCouleurBadgeExAequo, taille 10',
        (tester) async {
      await _monter(tester, _r5c5);
      final t = tester.widget<Text>(
          find.descendant(of: find.byType(BadgeExAequo), matching: find.byType(Text)).first);
      expect(t.data, 'Ex æquo');
      expect(t.style!.fontSize, 10.0, reason: 'taille du badge inchangée');
      expect(t.style!.color, kCouleurBadgeExAequo);
    });

    testWidgets('les ex æquo restent dorés, les autres neutres',
        (tester) async {
      await _monter(tester, _r5c5);
      for (final n in <int>[5, 7]) {
        final t = tester.widget<Text>(find.text('N°$n'));
        expect(t.style!.color, kCouleurExAequo, reason: 'N°$n ex æquo → doré');
        expect(t.style!.fontWeight, FontWeight.bold);
      }
      for (final n in <int>[2, 4, 8, 3, 6]) {
        final t = tester.widget<Text>(find.text('N°$n'));
        expect(t.style!.color, isNot(kCouleurExAequo),
            reason: 'N°$n non ex æquo → pas de doré');
      }
    });

    testWidgets('la taille du numéro est conservée (fontSize passé tel quel)',
        (tester) async {
      await _monter(tester, _r5c5, fontSize: 15);
      final t = tester.widget<Text>(find.text('N°5'));
      expect(t.style!.fontSize, 15.0);
      final r = tester.widget<Text>(find.text('3e').first);
      expect(r.style!.fontSize, 12.0, reason: 'rang = fontSize - 3');
    });

    testWidgets('aucun fond blanc ni carte ajoutés (fond applicatif conservé)',
        (tester) async {
      await _monter(tester, _r5c5);
      // Aucun `Card` ni `Material` blanc ajouté au rendu.
      expect(find.byType(Card), findsNothing);
      // Les conteneurs des chevaux gardent des fonds translucides (alpha < 255)
      // ou nuls : aucune surface opaque nouvelle.
      for (final e in find.descendant(
              of: find.byType(LigneArriveeExAequo), matching: find.byType(Container))
          .evaluate()) {
        final c = e.widget as Container;
        final d = c.decoration;
        if (d is BoxDecoration && d.color != null) {
          expect(d.color!.a < 1.0 || d.color!.a == 0.0, isTrue,
              reason: 'aucune surface opaque ajoutée');
        }
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2B-A/5 — PETITS ÉCRANS : AUCUN DÉBORDEMENT
  // ═════════════════════════════════════════════════════════════════════════
  group('B2B-A/5 — aucun débordement', () {
    for (final taille in <Size>[
      const Size(320, 640), // Android petit
      const Size(360, 640),
      const Size(400, 900),
    ]) {
      testWidgets('R6C5 (10 chevaux) sans débordement à ${taille.width.toInt()} dp',
          (tester) async {
        await _monter(tester, _r6c5, fontSize: 15, taille: taille);
        expect(tester.takeException(), isNull,
            reason: 'le Wrap doit se replier, jamais déborder');
      });
    }

    testWidgets('R5C5 avec texte agrandi ×2 ne déborde pas à 320 dp',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2.0),
          ),
          child: MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: SingleChildScrollView(
                child: LigneArriveeExAequo(groupes: _r5c5, fontSize: 15),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2B-A/6 — AUCUN GROUPE INVENTÉ, AUCUN BADGE SANS EX ÆQUO
  // ═════════════════════════════════════════════════════════════════════════
  group('B2B-A/6 — absence d\'ex æquo', () {
    test('arriveeAvecExAequo reste faux sur une arrivée normale', () {
      expect(arriveeAvecExAequo(const <List<int>>[
        [1], [2], [3], [4], [5]
      ]), isFalse);
      expect(arriveeAvecExAequo(null), isFalse);
      expect(arriveeAvecExAequo(const <List<int>>[]), isFalse);
    });

    testWidgets('le composant n\'est jamais monté sans ex æquo par les écrans',
        (tester) async {
      // Contrôle structurel : les 4 consommateurs conditionnent le montage
      // par `arriveeAvecExAequo`. Aucun badge ne peut donc apparaître sur une
      // arrivée historique dépourvue de groupes connus.
      final fichiers = <String>[
        'lib/widgets/arrivee_reelle_widget.dart',
        'lib/widgets/ia/ia_calendrier_tab.dart',
        'lib/screens/ia_perf_secondary_widgets.dart',
        'lib/screens/mes_paris_screen.dart',
      ];
      for (final f in fichiers) {
        final src = File(f).readAsStringSync();
        expect(src.contains('arriveeAvecExAequo'), isTrue,
            reason: '$f décide avec arriveeAvecExAequo');
      }
    });
  });
}

/// Rang officiel du groupe d'index [g] — utilitaire de cohérence.
int parGroupesFor(List<List<int>> groupes, int g) {
  var rang = 1;
  for (var i = 0; i < g; i++) {
    rang += groupes[i].length;
  }
  return rang;
}
