// ═══════════════════════════════════════════════════════════════════════════
//  A6 — TESTS CIBLÉS : LISIBILITÉ ET PETITS ÉCRANS
//
//  Objet : verrouiller la RÈGLE ABSOLUE DE LISIBILITÉ (§1 du mandat A6) et
//  les exigences de §3 et §7 :
//
//    • aucun débordement (RenderFlex) sur un écran de 320 dp ;
//    • aucune réduction de taille de police pour « gagner de la place » ;
//    • aucune utilisation de `FittedBox`, `Transform.scale` ou équivalent ;
//    • aucune troncature par points de suspension ;
//    • les tailles d'accessibilité (textScaler) sont RESPECTÉES, jamais
//      neutralisées ;
//    • le repli se fait par retour à la ligne (`Wrap`), et le composant
//      GRANDIT en hauteur.
//
//  Le bloc mesuré est la composition EXACTE du bloc « Arrivée officielle » de
//  `mes_paris_screen.dart` (l.1885-1913) : un `Wrap` contenant le titre et le
//  badge, puis `LigneArriveeExAequo(fontSize: 12)`. Il est monté isolément
//  parce que `MesPariScreen` exige quatre providers, `AlertService.init()` et
//  lance des requêtes réseau dans `initState` : le monter entier mesurerait
//  surtout ce bruit. La fidélité de la composition est vérifiée
//  STRUCTURELLEMENT en fin de fichier (A6-L5), sur le fichier source réel.
//
//  Aucun mécanisme protégé n'est sollicité : ni gradient, ni poids, ni seuils,
//  ni ELO, ni TOP3. Aucun service n'est instancié.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/widgets/arrivee_officielle_groupes_widget.dart';

// ─── Données d'essai ────────────────────────────────────────────────────────

/// Arrivée officielle avec DEUX ex æquo et des positions SAUTÉES :
/// 7 et 12 premiers ex æquo (rang 1), 8 troisième (rang 3), 6 quatrième
/// (rang 4). C'est la forme réellement mesurée sur l'API PMU.
const List<List<int>> _g2ExAequo = <List<int>>[
  <int>[7, 12],
  <int>[8],
  <int>[6],
];

/// Ex æquo de TROIS chevaux en tête, puis deux rangs simples.
const List<List<int>> _g3ExAequo = <List<int>>[
  <int>[7, 12, 15],
  <int>[8],
  <int>[6],
];

/// Arrivée SANS ex æquo : l'affichage doit rester strictement historique.
const List<List<int>> _gPlat = <List<int>>[
  <int>[7],
  <int>[4],
  <int>[2],
  <int>[9],
  <int>[1],
];

// ─── Harnais ────────────────────────────────────────────────────────────────

/// Composition EXACTE du bloc « Arrivée officielle » de Mes Paris
/// (`mes_paris_screen.dart:1898-1911`).
Widget _blocMesParis(List<List<int>> groupes) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 2,
          children: const <Widget>[
            Text('Arrivée officielle :',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            BadgeExAequo(),
          ],
        ),
        const SizedBox(height: 4),
        LigneArriveeExAequo(groupes: groupes, fontSize: 12),
      ],
    );

/// Monte le bloc à une largeur donnée, avec un facteur d'échelle de texte
/// donné. `physicalSize` est exprimé en pixels physiques : à
/// `devicePixelRatio = 1`, il vaut exactement la taille logique en dp.
Future<void> _monter(
  WidgetTester tester,
  List<List<int>> groupes, {
  double largeurDp = 320,
  double hauteurDp = 2000,
  double echelleTexte = 1.0,
}) async {
  // ⚠️ `setSurfaceSize` n'est utilisable QUE dans un test widget : il lève
  // `'inTest': is not true` s'il est appelé depuis un `tearDown` global ou
  // depuis un `test()` simple. On fixe donc la géométrie par la vue, et la
  // remise à zéro est enregistrée DANS la zone du test courant.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(largeurDp, hauteurDp);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(largeurDp, hauteurDp),
          textScaler: TextScaler.linear(echelleTexte),
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _blocMesParis(groupes),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Textes réellement rendus, dans l'ordre de l'arbre.
List<String> _textes(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .toList();

/// Taille de police DÉCLARÉE de chaque `Text` (avant mise à l'échelle
/// d'accessibilité), avec son contenu, pour vérifier qu'aucune n'a été
/// réduite pour tenir dans la largeur.
List<({String texte, double? taille})> _tailles(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => (
          texte: t.data ?? '',
          taille: t.style?.fontSize,
        ))
    .toList();

/// Hauteur rendue du bloc, pour prouver que le composant GRANDIT au lieu de
/// comprimer le texte.
double _hauteurBloc(WidgetTester tester) => tester
    .getSize(find
        .descendant(
          of: find.byType(Column).first,
          matching: find.byType(Wrap),
        )
        .first)
    .height;

// ═══════════════════════════════════════════════════════════════════════════
//  TESTS
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ⚠️ AUCUN `tearDown` global ici : `binding.setSurfaceSize(null)` et
  // `platformDispatcher.clearAllTestValues()` lèvent `'inTest': is not true`
  // hors d'un test widget. La remise à zéro est enregistrée par `_monter`
  // via `addTearDown(tester.view.reset)`, donc dans la zone du test courant.

  // ─────────────────────────────────────────────────────────────────────────
  //  A6-L1 — AUCUN DÉBORDEMENT À 320 dp, AVEC EX ÆQUO
  //
  //  Mesure directe de l'exigence §3 : le bloc de Mes Paris ne doit pas
  //  déborder sur un écran de 320 dp. `takeException()` remonte toute erreur
  //  de rendu : un `RenderFlex overflowed` y apparaît.
  // ─────────────────────────────────────────────────────────────────────────
  testWidgets('A6-L1 Mes Paris 320 dp — aucun débordement avec ex æquo',
      (tester) async {
    await _monter(tester, _g2ExAequo, largeurDp: 320);

    final erreur = tester.takeException();
    debugPrint('A6-L1 largeur=320dp exception=${erreur ?? "aucune"}');
    expect(erreur, isNull,
        reason: 'A6 §3 : le bloc « Arrivée officielle » de Mes Paris doit '
            'occuper 320 dp sans débordement. Toute erreur de rendu ici est '
            'un `RenderFlex overflowed`, donc une régression de lisibilité');

    // Témoin : le contenu est bien rendu, pas vide par accident.
    expect(_textes(tester), contains('Arrivée officielle :'));
    expect(_textes(tester), contains('Ex æquo'));
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  A6-L2 — AUCUN DÉBORDEMENT À 320 dp AVEC TEXTE AGRANDI ×2
  //
  //  §1 interdit de contourner les réglages d'accessibilité. Un utilisateur à
  //  ×2 est le cas qui casse un `Row` : le test le mesure.
  // ─────────────────────────────────────────────────────────────────────────
  testWidgets('A6-L2 Mes Paris 320 dp — aucun débordement, texte ×2',
      (tester) async {
    await _monter(tester, _g2ExAequo, largeurDp: 320, echelleTexte: 2.0);

    final erreur = tester.takeException();
    debugPrint('A6-L2 largeur=320dp échelle=2.0 exception=${erreur ?? "aucune"}');
    expect(erreur, isNull,
        reason: 'A6 §1 : le réglage d\'accessibilité ×2 doit être RESPECTÉ, '
            'et l\'affichage doit s\'y adapter par retour à la ligne, sans '
            'déborder et sans réduire la police');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  A6-L3 — AUCUNE RÉDUCTION DE POLICE (règle absolue §1)
  //
  //  Trois mesures qui, ensemble, interdisent la triche :
  //    (a) les tailles DÉCLARÉES sont celles d'avant (12 pour le titre et
  //        l'arrivée, 10 pour le badge) — rien n'a été rabaissé ;
  //    (b) aucun `FittedBox` n'est présent dans l'arbre ;
  //    (c) aucun `Transform` d'échelle n'est présent (un `Transform.scale`
  //        réduirait visuellement la police sans toucher `fontSize`).
  // ─────────────────────────────────────────────────────────────────────────
  testWidgets('A6-L3 aucune réduction de police, aucun FittedBox, '
      'aucune mise à l\'échelle', (tester) async {
    await _monter(tester, _g2ExAequo, largeurDp: 320, echelleTexte: 1.0);

    final tailles = _tailles(tester);
    debugPrint('A6-L3 tailles mesurées=$tailles');

    // (a) Tailles déclarées : le titre et l'arrivée à 12, le badge à 10.
    final titre = tailles.firstWhere((t) => t.texte == 'Arrivée officielle :');
    expect(titre.taille, 12.0,
        reason: 'A6 §1 : la taille du titre « Arrivée officielle : » ne doit '
            'jamais être réduite (12 avant A6, 12 après)');

    final badge = tailles.firstWhere((t) => t.texte == 'Ex æquo');
    expect(badge.taille, 10.0,
        reason: 'A6 §1 : la taille du badge « Ex æquo » reste 10');

    for (final t in tailles.where((t) => t.texte.startsWith('N°'))) {
      expect(t.taille, 12.0,
          reason: 'A6 §1 : chaque numéro de cheval est rendu à 12, comme '
              'l\'arrivée historique de Mes Paris — jamais moins pour tenir '
              'dans la largeur');
    }

    // (b) Aucun FittedBox dans l'arbre.
    expect(find.byType(FittedBox), findsNothing,
        reason: 'A6 §1 : `FittedBox` est explicitement interdit — il réduit '
            'la police pour la faire tenir');

    // (c) Aucune mise à l'échelle du texte — vérifié sur la SOURCE du widget
    //     partagé, et non sur l'arbre : `MaterialApp` et `Scaffold` insèrent
    //     leurs propres `Transform` (transitions, encre), qui n'ont rien à
    //     voir avec la lisibilité et feraient échouer un comptage global.
    final sourceWidget = File(
            'lib/widgets/arrivee_officielle_groupes_widget.dart')
        .readAsStringSync();
    final codeWidget = sourceWidget
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    debugPrint('A6-L3 Transform.scale dans le widget partagé='
        '${codeWidget.contains('Transform.scale')} | '
        'FittedBox=${codeWidget.contains('FittedBox')}');

    expect(codeWidget.contains('FittedBox'), isFalse,
        reason: 'A6 §1 : le rendu partagé ne doit contenir aucun `FittedBox`');
    expect(codeWidget.contains('Transform.scale'), isFalse,
        reason: 'A6 §1 : le rendu partagé ne doit contenir aucun '
            '`Transform.scale` — il réduirait visuellement la police sans '
            'toucher `fontSize`, ce qui contournerait la règle');
    expect(codeWidget.contains('TextOverflow.ellipsis'), isFalse,
        reason: 'A6 §1 : aucune troncature par points de suspension dans le '
            'rendu partagé');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  A6-L4 — LE COMPOSANT GRANDIT AU LIEU DE COMPRIMER
  //
  //  §1 : « C'est l'affichage qui doit s'adapter à la place disponible ».
  //  On mesure donc que la hauteur du `Wrap` AUGMENTE quand la largeur
  //  diminue : c'est la signature d'un retour à la ligne réel.
  // ─────────────────────────────────────────────────────────────────────────
  testWidgets('A6-L4 le Wrap grandit quand la largeur diminue '
      '(retour à la ligne réel)', (tester) async {
    await _monter(tester, _g3ExAequo, largeurDp: 900);
    final hLarge = _hauteurBloc(tester);

    await _monter(tester, _g3ExAequo, largeurDp: 320);
    final hEtroit = _hauteurBloc(tester);

    debugPrint('A6-L4 hauteur 900dp=$hLarge | hauteur 320dp=$hEtroit | '
        'gain=${hEtroit - hLarge}');

    expect(hEtroit, greaterThan(hLarge),
        reason: 'A6 §1 : sur 320 dp, l\'arrivée doit passer à la ligne et '
            'OCCUPER PLUS DE HAUTEUR. Une hauteur identique signifierait que '
            'rien ne se replie — donc que le texte a été comprimé');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  A6-L5 — L'ÉCHELLE D'ACCESSIBILITÉ EST RESPECTÉE
  //
  //  §1 interdit de « désactiver ou contourner les réglages
  //  d'accessibilité ». On vérifie que la taille RENDUE augmente avec
  //  `textScaler` : c'est la preuve que le réglage n'est pas neutralisé.
  // ─────────────────────────────────────────────────────────────────────────
  testWidgets('A6-L5 l\'échelle de texte est appliquée, jamais neutralisée',
      (tester) async {
    await _monter(tester, _g2ExAequo, largeurDp: 320, echelleTexte: 1.0);
    final taille1 = tester.getSize(find.text('Arrivée officielle :'));

    await _monter(tester, _g2ExAequo, largeurDp: 320, echelleTexte: 2.0);
    final taille2 = tester.getSize(find.text('Arrivée officielle :'));

    debugPrint('A6-L5 hauteur titre ×1=${taille1.height} | '
        '×2=${taille2.height}');

    expect(taille2.height, greaterThan(taille1.height),
        reason: 'A6 §1 : à ×2, le texte doit être rendu PLUS GRAND. Une '
            'hauteur inchangée prouverait que le réglage d\'accessibilité a '
            'été neutralisé, ce qui est explicitement interdit');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  A6-L6 — AUCUNE TRONCATURE PAR POINTS DE SUSPENSION
  //
  //  §1 interdit de « remplacer un texte lisible par des points de
  //  suspension ». On vérifie que chaque numéro officiel est rendu ENTIER,
  //  y compris le 12 sur 320 dp (le cas qui avait débordé).
  // ─────────────────────────────────────────────────────────────────────────
  testWidgets('A6-L6 les numéros sont rendus entiers, sans « … »',
      (tester) async {
    await _monter(tester, _g2ExAequo, largeurDp: 320, echelleTexte: 1.5);

    final textes = _textes(tester);
    debugPrint('A6-L6 textes=$textes');

    for (final numero in <String>['N°7', 'N°12', 'N°8', 'N°6']) {
      expect(textes, contains(numero),
          reason: 'A6 §1 : « $numero » doit être rendu ENTIER sur 320 dp, '
              'même à ×1,5. Un texte remplacé par des points de suspension '
              'est explicitement interdit');
    }

    for (final t in textes) {
      expect(t.contains('…'), isFalse,
          reason: 'A6 §1 : aucun texte ne doit être tronqué par « … » — '
              'trouvé « $t »');
      expect(t.contains('...'), isFalse,
          reason: 'A6 §1 : aucun texte ne doit être tronqué par « ... » — '
              'trouvé « $t »');
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  A6-L7 — SANS EX ÆQUO, AUCUN RANG N'EST AJOUTÉ
  //
  //  §2 : « Pas d'ex æquo : affichage strictement historique. » Le widget
  //  partagé ne doit produire AUCUN libellé de rang (1er, 2e, …) quand les
  //  groupes sont tous d'un seul cheval.
  //
  //  ⚠️ Le badge est rendu ici par le HARNAIS (il reproduit le bloc de Mes
  //  Paris, où il est conditionnel à `_groupesExAequoAffiches() != null`).
  //  Ce n'est donc pas le widget partagé qui décide de l'afficher : le test
  //  ne peut pas conclure sur le badge à partir de ce montage. Il conclut sur
  //  ce qui appartient bien au widget partagé : l'ABSENCE DE RANG.
  // ─────────────────────────────────────────────────────────────────────────
  testWidgets('A6-L7 sans ex æquo, aucun libellé de rang parasite',
      (tester) async {
    await _monter(tester, _gPlat, largeurDp: 320);

    final textes = _textes(tester);
    debugPrint('A6-L7 textes=$textes');

    expect(textes, contains('N°7'));
    expect(textes, contains('N°1'));

    for (final rang in <String>['1er', '2e', '3e', '4e', '5e']) {
      expect(textes, isNot(contains(rang)),
          reason: 'A6 §2 : sans ex æquo, aucun rang ne doit être affiché sous '
              'les numéros — l\'affichage reste strictement historique. '
              'Trouvé « $rang »');
    }
    // Témoin : les groupes plats ne doivent pas être signalés comme ex æquo
    // PAR LE WIDGET PARTAGÉ.
    expect(arriveeAvecExAequo(_gPlat), isFalse,
        reason: 'A6 §2 : `arriveeAvecExAequo` doit rendre faux sur une '
            'arrivée plate — c\'est ce prédicat qui conditionne le badge dans '
            'les quatre surfaces');
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  A6-L8 — LE BLOC MES PARIS EST BIEN CELUI MESURÉ (contrôle structurel)
  //
  //  Les tests ci-dessus mesurent une reproduction du bloc. Ce test vérifie,
  //  sur le fichier SOURCE réel, que `mes_paris_screen.dart` contient bien
  //  cette composition : `Wrap` (et non `Row`) pour le titre + le badge, et
  //  `LigneArriveeExAequo` avec `fontSize: 12`. Sans cela, les mesures
  //  porteraient sur un code qui n'est pas celui de l'application.
  // ─────────────────────────────────────────────────────────────────────────
  test('A6-L8 mes_paris_screen utilise Wrap + LigneArriveeExAequo (source)',
      () {
    final source =
        File('lib/screens/mes_paris_screen.dart').readAsStringSync();

    // Commentaires retirés : un commentaire qui MENTIONNE `Row` ne doit pas
    // faire échouer le test, et un commentaire qui mentionne `Wrap` ne doit
    // pas le faire réussir.
    final code = source
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    final bloc = code.substring(
      code.indexOf('Arrivée officielle :'),
    );
    final extrait = bloc.length > 1400 ? bloc.substring(0, 1400) : bloc;
    debugPrint('A6-L8 extrait du bloc mesuré:\n$extrait');

    expect(bloc.contains('Wrap('), isTrue,
        reason: 'A6 §3 : le titre et le badge de Mes Paris doivent être dans '
            'un `Wrap` — un `Row` ne peut pas se replier et déborde sur '
            '320 dp (mesure A6-L1/L2)');
    expect(bloc.contains('LigneArriveeExAequo'), isTrue,
        reason: 'A6 §6 : Mes Paris doit utiliser le rendu partagé, seul '
            'garant de la présentation validée');
    expect(bloc.contains('fontSize: 12'), isTrue,
        reason: 'A6 §1 : la taille de 12 dp de l\'arrivée de Mes Paris est '
            'conservée — aucune réduction pour gagner de la place');
    expect(bloc.contains('FittedBox'), isFalse,
        reason: 'A6 §1 : `FittedBox` est interdit dans le bloc d\'arrivée');
  });
}
