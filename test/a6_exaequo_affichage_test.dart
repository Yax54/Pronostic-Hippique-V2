// ═══════════════════════════════════════════════════════════════════════════
//  A6 — TESTS CIBLÉS : AFFICHAGE DES EX ÆQUO ET FIABILITÉ DES ARRIVÉES
//
//  Objet : verrouiller les deux exigences de l'affichage validé et les
//  garanties de fiabilité, SANS toucher aux mécanismes protégés.
//
//  Rappel des règles vérifiées ici :
//    • seuls les chevaux ex æquo sont mis en évidence (fond et bordure
//      jaune doré) ;
//    • leur rang officiel est affiché SOUS chacun des numéros concernés,
//      avec les positions SAUTÉES respectées ;
//    • l'encadré gris « Ex æquo » n'apparaît QUE s'il existe un ex æquo ;
//    • une arrivée SANS ex æquo conserve strictement l'affichage actuel :
//      aucun rang sous les numéros, aucun encadré.
//
//  Aucune assertion sur un mécanisme d'apprentissage : ces tests ne
//  déclenchent ni gradient, ni poids, ni seuils, ni ELO, ni TOP3.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/widgets/arrivee_officielle_groupes_widget.dart';

// ─── Harnais : monte le widget isolé ────────────────────────────────────────

Future<void> _monter(
  WidgetTester tester,
  List<List<int>> groupes, {
  Set<String> numerosIa = const <String>{},
  double fontSize = 14,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: LigneArriveeExAequo(
          groupes: groupes,
          fontSize: fontSize,
          numerosIa: numerosIa,
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
    final d = w.data;
    if (d != null) out.add(d);
  }
  return out;
}

int _nbTextes(WidgetTester tester, String valeur) =>
    _textes(tester).where((s) => s == valeur).length;

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  //  PARTIE 1 — PRÉDICATS PURS
  // ═══════════════════════════════════════════════════════════════════════

  group('A6 · prédicats purs', () {
    test('A6-1.1 arriveeAvecExAequo : détection exacte', () {
      expect(arriveeAvecExAequo(null), isFalse, reason: 'aucune donnée');
      expect(arriveeAvecExAequo(const <List<int>>[]), isFalse,
          reason: 'liste vide');
      expect(
        arriveeAvecExAequo(const <List<int>>[
          [7],
          [12],
          [8]
        ]),
        isFalse,
        reason: 'TÉMOIN : trois groupes de 1 → aucun ex æquo',
      );
      expect(
        arriveeAvecExAequo(const <List<int>>[
          [7, 12],
          [8]
        ]),
        isTrue,
        reason: 'groupe de 2 en tête',
      );
      expect(
        arriveeAvecExAequo(const <List<int>>[
          [7],
          [12],
          [11, 9],
          [6]
        ]),
        isTrue,
        reason: 'ex æquo au 3e rang',
      );
    });

    test('A6-1.2 rangsOfficiels : positions SAUTÉES respectées', () {
      // Groupe de 2 en tête → le suivant démarre au rang 3.
      expect(
        rangsOfficiels(const <List<int>>[
          [7, 12],
          [8],
          [6],
        ]),
        equals(<int>[1, 3, 4]),
        reason: 'un groupe de 2 occupe le rang 1 et consomme 2 places',
      );
      // Ex æquo au 3e rang → le suivant saute au rang 5.
      expect(
        rangsOfficiels(const <List<int>>[
          [7],
          [4],
          [11, 9],
          [6],
        ]),
        equals(<int>[1, 2, 3, 5]),
      );
      // Aucun ex æquo → rangs strictement consécutifs.
      expect(
        rangsOfficiels(const <List<int>>[
          [1],
          [2],
          [3]
        ]),
        equals(<int>[1, 2, 3]),
        reason: 'TÉMOIN : sans ex æquo, aucune position sautée',
      );
      // Groupe de 3 → consomme 3 places.
      expect(
        rangsOfficiels(const <List<int>>[
          [5, 8, 2],
          [1],
        ]),
        equals(<int>[1, 4]),
      );
    });

    test('A6-1.3 libelleRang : 1er puis Ne', () {
      expect(libelleRang(1), '1er');
      expect(libelleRang(2), '2e');
      expect(libelleRang(3), '3e');
      expect(libelleRang(11), '11e');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  PARTIE 2 — AFFICHAGE AVEC EX ÆQUO
  // ═══════════════════════════════════════════════════════════════════════

  group('A6 · affichage avec ex æquo', () {
    testWidgets('A6-2.1 tous les numéros sont affichés, dans l\'ordre L0',
        (tester) async {
      const groupes = <List<int>>[
        [7, 12],
        [8],
        [6],
      ];
      await _monter(tester, groupes);

      final textes = _textes(tester);
      for (final n in <int>[7, 12, 8, 6]) {
        expect(textes.where((s) => s == 'N°$n').length, greaterThanOrEqualTo(1),
            reason: 'N°$n doit être affiché');
      }
      // Ordre préservé : 7 avant 12, 12 avant 8, 8 avant 6.
      final i7 = textes.indexOf('N°7');
      final i12 = textes.indexOf('N°12');
      final i8 = textes.indexOf('N°8');
      final i6 = textes.indexOf('N°6');
      expect(i7, lessThan(i12), reason: 'le groupe [7,12] garde son ordre');
      expect(i12, lessThan(i8));
      expect(i8, lessThan(i6));
    });

    testWidgets('A6-2.2 rang officiel affiché SOUS chacun des ex æquo',
        (tester) async {
      // Trois chevaux ex æquo au premier rang → chacun porte « 1er ».
      const groupes = <List<int>>[
        [5, 8, 2],
        [1],
      ];
      await _monter(tester, groupes);

      expect(_nbTextes(tester, '1er'), 3,
          reason: 'un rang sous CHACUN des trois chevaux ex æquo');
      // ⚠️ SPÉCIFICATION RÉVISÉE (lot B-2 bis) : dès qu'un ex æquo existe,
      //    CHAQUE cheval porte son rang. N°1, seul au rang 4, porte donc
      //    « 4e » — c'est l'exigence validée, pas une régression.
      expect(_nbTextes(tester, '4e'), 1,
          reason: 'B-2 bis : N°1, seul au rang 4, porte « 4e »');
      // Seuls les ex æquo portent un encadré « Ex æquo ».
      expect(_nbTextes(tester, 'Ex æquo'), 3,
          reason: 'un encadré sous chacun des trois ex æquo, et sous eux seuls');
    });

    testWidgets('A6-2.3 ex æquo au 3e rang : « 3e » sous les concernés',
        (tester) async {
      const groupes = <List<int>>[
        [7],
        [4],
        [11, 9],
        [6],
      ];
      await _monter(tester, groupes);

      expect(_nbTextes(tester, '3e'), 2,
          reason: 'N°11 et N°9 sont tous deux 3e');
      // Le groupe suivant saute au rang 5 : aucun « 4e » ne doit apparaître.
      final textes = _textes(tester);
      expect(textes.where((s) => s == '4e'), isEmpty,
          reason: 'position sautée : le rang 4 n\'existe pas');
      // ⚠️ SPÉCIFICATION RÉVISÉE (lot B-2 bis) : dès qu'un ex æquo existe,
      //    CHAQUE cheval porte son rang officiel. N°7 est donc 1er, N°4 2e et
      //    N°6 5e — c'est l'exigence validée, pas une régression.
      expect(_nbTextes(tester, '1er'), 1,
          reason: 'B-2 bis : N°7, seul au rang 1, porte « 1er »');
      expect(_nbTextes(tester, '2e'), 1,
          reason: 'B-2 bis : N°4, seul au rang 2, porte « 2e »');
      expect(_nbTextes(tester, '5e'), 1,
          reason: 'B-2 bis : N°6, seul au rang 5, porte « 5e »');
    });

    testWidgets('A6-2.4 fond et bordure jaune doré sur les SEULS ex æquo',
        (tester) async {
      const groupes = <List<int>>[
        [7, 12],
        [8],
      ];
      await _monter(tester, groupes);

      // Les deux conteneurs des ex æquo portent une bordure dorée pleine.
      final decorations = <BoxDecoration>[];
      for (final e in find.byType(Container).evaluate()) {
        final c = e.widget as Container;
        final d = c.decoration;
        if (d is BoxDecoration) decorations.add(d);
      }
      final dorees = decorations.where((d) {
        final b = d.border;
        if (b is! Border) return false;
        return b.top.color == kCouleurExAequo;
      }).length;
      expect(dorees, 2,
          reason: 'exactement les 2 chevaux ex æquo sont mis en évidence');

      // Le cheval seul (N°8) n'est PAS doré.
      final neutres = decorations.where((d) {
        final b = d.border;
        if (b is! Border) return false;
        return b.top.color != kCouleurExAequo;
      }).length;
      expect(neutres, greaterThanOrEqualTo(1),
          reason: 'N°8 conserve sa présentation habituelle');
    });

    testWidgets('A6-2.5 encadré « Ex æquo » : libellé et isolement',
        (tester) async {
      // 1. Le libellé exact de l'encadré est bien « Ex æquo ».
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BadgeExAequo()),
        ),
      );
      await tester.pump();
      expect(_textes(tester), equals(<String>['Ex æquo']),
          reason: 'encadré gris portant exactement « Ex æquo »');

      // 2. ⚠️ SPÉCIFICATION RÉVISÉE (lot B-2 bis) : l'encadré « Ex æquo »
      //    appartient désormais à la LIGNE, et non au titre. Il est rendu
      //    SOUS chaque cheval ex æquo, et sous lui seul. Les encadrés placés
      //    auprès des titres ont été retirés des écrans : plus de doublon.
      await _monter(tester, const <List<int>>[
        [7, 12],
        [8],
      ]);
      expect(find.byType(BadgeExAequo), findsNWidgets(2),
          reason: 'B-2 bis : un encadré SOUS chacun des deux ex æquo');
      expect(_textes(tester).where((s) => s == 'Ex æquo').length, 2,
          reason: 'B-2 bis : exactement deux encadrés, pas un de plus');
    });

    testWidgets('A6-2.6 sélection IA conservée en vert, ex æquo en doré',
        (tester) async {
      const groupes = <List<int>>[
        [7, 12],
        [8],
      ];
      await _monter(tester, groupes, numerosIa: const <String>{'8', '12'});

      // N°12 est ex æquo ET dans la sélection IA : le doré PRIME.
      final textes = _textes(tester);
      expect(textes, contains('N°12'));

      final styles = <String, Color?>{};
      for (final e in find.byType(Text).evaluate()) {
        final w = e.widget as Text;
        if (w.data != null && w.data!.startsWith('N°')) {
          styles[e.widget.key?.toString() ?? w.data!] = w.style?.color;
        }
      }
      final couleur12 = styles['N°12'];
      expect(couleur12, kCouleurExAequo,
          reason: 'un ex æquo reste doré même s\'il est dans la sélection IA');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  PARTIE 3 — ABSENCE D'EX ÆQUO : AUCUN RANG, AUCUN ENCADRÉ
  // ═══════════════════════════════════════════════════════════════════════

  group('A6 · absence d\'ex æquo', () {
    testWidgets('A6-3.1 aucun rang affiché sous les numéros', (tester) async {
      await _monter(tester, const <List<int>>[
        [1],
        [2],
        [3],
        [4],
        [5],
      ]);

      final textes = _textes(tester);
      for (final n in <int>[1, 2, 3, 4, 5]) {
        expect(textes, contains('N°$n'));
      }
      // Aucun libellé de rang ne doit apparaître.
      for (final libelle in <String>['1er', '2e', '3e', '4e', '5e']) {
        expect(textes.where((s) => s == libelle), isEmpty,
            reason: 'sans ex æquo, AUCUN rang sous les numéros');
      }
      expect(_textes(tester).where((s) => s.contains('Ex æquo')), isEmpty,
          reason: 'aucun encadré « Ex æquo » sans ex æquo');
    });

    testWidgets('A6-3.2 aucun « = » et séparateur « · » conservé',
        (tester) async {
      await _monter(tester, const <List<int>>[
        [1],
        [2],
        [3],
      ]);
      final textes = _textes(tester);
      expect(textes.where((s) => s == '='), isEmpty,
          reason: 'aucun ex æquo → aucun séparateur d\'égalité');
      expect(_nbTextes(tester, '·'), 2,
          reason: '2 séparateurs pour 3 groupes');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  PARTIE 4 — FIABILITÉ : AUCUNE ÉCRITURE, AUCUN APPRENTISSAGE
  //
  //  Ces vérifications sont STRUCTURELLES (lecture du source) : elles
  //  prouvent que le rendu partagé ne peut pas atteindre les portes
  //  d'écriture de l'IA, sans exécuter un seul mécanisme protégé.
  // ═══════════════════════════════════════════════════════════════════════

  group('A6 · fiabilité structurelle du rendu', () {
    test('A6-4.1 le widget d\'affichage n\'importe aucun service', () {
      final src = _lire('lib/widgets/arrivee_officielle_groupes_widget.dart');
      expect(src.trim(), isNotEmpty, reason: 'TÉMOIN : fichier lu non vide');

      // Seul import autorisé : Flutter Material. Tout import de service
      // donnerait au rendu un moyen d'écrire ou d'apprendre.
      final imports = RegExp(r"^import\s+'([^']+)';", multiLine: true)
          .allMatches(src)
          .map((m) => m.group(1)!)
          .toList();
      expect(imports, equals(<String>['package:flutter/material.dart']),
          reason: 'le rendu ne dépend que de Material');
    });

    test('A6-4.2 aucune porte d\'écriture ou d\'apprentissage', () {
      final src = _codeSansCommentaires(
          _lire('lib/widgets/arrivee_officielle_groupes_widget.dart'));
      const interdits = <String>[
        'enregistrerResultat(',
        'enregistrerPronostic(',
        '_apprendreParGradient',
        '_mettreAJourCalibration',
        'fetchArriveeDirecte(',
        'relancerRecuperationPMU(',
        '_mettreAJourEloApresArrivee',
        'mettreAJourApresArrivee',
        'ArriveeOfficielleService',
      ];
      for (final i in interdits) {
        expect(i.allMatches(src).length, 0,
            reason: 'le rendu ne doit jamais contenir $i');
      }
    });

    test('A6-4.3 les services protégés sont inchangés sur les symboles clefs',
        () {
      // Ces fichiers NE DOIVENT PAS contenir d'identifiant A6 : la
      // correction A6 est une correction d'AFFICHAGE + un câblage déjà
      // existant, elle n'ajoute rien aux services protégés.
      const proteges = <String>[
        'lib/services/ia_memory_models.dart',
        'lib/services/arrivee_officielle_service.dart',
        'lib/services/zone_turf_service.dart',
        'lib/services/backup_service.dart',
      ];
      for (final f in proteges) {
        final src = _lire(f);
        expect(src.trim(), isNotEmpty, reason: 'TÉMOIN : $f lu non vide');
        expect('arrivee_officielle_groupes_widget'.allMatches(src).length, 0,
            reason: '$f ne doit pas importer le rendu');
        expect('BadgeExAequo'.allMatches(src).length, 0,
            reason: '$f ne doit porter aucun code d\'affichage');
      }
    });

    test('A6-4.4 les quatre bulles consomment le rendu partagé', () {
      // Exigence : « cohérent sur chaque bulle de pronostic concernée,
      // quelle que soit la nature de l'app ». Preuve : chaque composant de
      // rendu délègue au MÊME widget partagé et ne décide de l'afficher
      // qu'au moyen de la même fonction de détection.
      //
      // `ia_perf_screen_part.dart` est le fichier part() du groupe library
      // `ia_performance_screen` : les imports y sont portés par le parent.
      // Le calendrier IA n'utilise PAS ArriveReelleWidget : il possède son
      // propre rendu (`_buildGroupesArrivee`), traité au point 3 ci-dessous.
      const surfaces = <String>[
        'lib/screens/home_screen.dart',
        'lib/screens/races_screen.dart',
        'lib/screens/course_detail_screen.dart',
        'lib/screens/programme_screen.dart',
        'lib/screens/conseils_screen.dart',
        'lib/screens/best_bet_screen.dart',
      ];
      const composantsRendu = <String>[
        'lib/widgets/arrivee_reelle_widget.dart',
        'lib/screens/ia_perf_secondary_widgets.dart',
        'lib/screens/mes_paris_screen.dart',
      ];

      // 1. Chaque écran de pronostic monte le widget d'arrivée réelle.
      for (final f in surfaces) {
        final src = _lire(f);
        expect(src.trim(), isNotEmpty, reason: 'TÉMOIN : $f lu non vide');
        expect('ArriveReelleWidget'.allMatches(src).length,
            greaterThanOrEqualTo(1),
            reason: '$f affiche une bulle avec arrivée');
      }

      // 2. Chaque composant de rendu délègue à LigneArriveeExAequo.
      for (final f in composantsRendu) {
        final src = _lire(f);
        expect(src.trim(), isNotEmpty, reason: 'TÉMOIN : $f lu non vide');
        expect(src.contains('LigneArriveeExAequo'), isTrue,
            reason: '$f doit utiliser le rendu partagé');
      }

      // 3. dans TOUS ces fichiers, l'encadré et le rendu ex æquo sont
      //    conditionnés par la MÊME fonction : aucune décision divergente
      //    d'un écran à l'autre.
      for (final f in <String>[
        'lib/widgets/arrivee_reelle_widget.dart',
        'lib/widgets/ia/ia_calendrier_tab.dart',
        'lib/screens/ia_perf_secondary_widgets.dart',
        'lib/screens/mes_paris_screen.dart',
      ]) {
        final src = _lire(f);
        expect(src.contains('arriveeAvecExAequo'), isTrue,
            reason: '$f doit décider avec arriveeAvecExAequo');
      }
    });
  });
}

// ─── Utilitaires de lecture ─────────────────────────────────────────────────

String _lire(String chemin) {
  final f = File(chemin);
  if (!f.existsSync()) {
    // Les tests tournent avec la racine du projet comme répertoire courant.
    throw StateError('fichier introuvable : $chemin');
  }
  return f.readAsStringSync();
}

/// Retire les commentaires pour ne mesurer que le CODE réel.
String _codeSansCommentaires(String src) {
  final sansBloc = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return sansBloc
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');
}
