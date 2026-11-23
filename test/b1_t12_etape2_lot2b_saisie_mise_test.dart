// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / étape 2 — LOT 2-B : SAISIE MANUELLE DE LA MISE (remplace le Slider)
//
//  Ce que ce fichier prouve, et rien de plus :
//    A1  La règle de lecture accepte entier, virgule et point, et arrondit au
//        centime. Aucune borne haute n'est imposée.
//    A2  Les entrées inexploitables sont REFUSÉES : vide, nulle, négative,
//        illisible. Rien n'est deviné.
//    A3  AUCUN Slider ne subsiste dans le parcours de saisie de la mise.
//    A4  Une annulation ne peut pas modifier la mise précédente.
//    A5  La mise réellement ENGAGÉE est conservée sur la persistance réelle :
//        simple (une mise) et Gagnant+Placé (deux mises).
//    A6  Les montants rapides restent présents et écrivent la même mise.
//    A7  Aucune régression sur le LOT 2-A (saisie manuelle du gain).
//
//  ⚠️ CE QUE CE FICHIER NE TESTE PAS — ET NE PRÉTEND PAS TESTER :
//     • le clavier Android réel (apparition, type numérique, présence de la
//       virgule sur un clavier matériel/logiciel donné) ;
//     • la conservation de la position de défilement au retour de la fenêtre.
//       `showDialog` n'empile aucune route plein écran, ce qui rend le
//       comportement ATTENDU, mais un `flutter test` ne mesure pas le
//       défilement d'un vrai écran. Ces deux points relèvent d'une
//       vérification sur APK et sont déclarés NON VALIDÉS ici.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/pmu_models.dart' show UserPrediction;
import 'package:pronostic_hippique/providers/pmu_provider.dart' show PmuProvider;
import 'package:pronostic_hippique/utils/format_euros.dart' show fmtEuros;
import 'package:pronostic_hippique/widgets/paris/mise_manuelle_dialog.dart'
    show MiseManuelleDialog;
import 'package:pronostic_hippique/widgets/paris/gain_manuel_dialog.dart'
    show ResultatSaisieGain;

/// La règle testée est celle du CODE, pas une copie.
double? lire(String s) => MiseManuelleDialog.lireMontant(s);

String sourceBetSheet() =>
    File('lib/widgets/bet_bottom_sheet.dart').readAsStringSync();

/// Extrait la portion de source entre deux marqueurs. Rend une erreur de test
/// explicite si un marqueur a disparu, plutôt qu'une chaîne vide silencieuse.
String corpsDe(String src, String debut, String fin) {
  final i = src.indexOf(debut);
  final j = src.indexOf(fin);
  expect(i, greaterThanOrEqualTo(0),
      reason: 'marqueur de début introuvable : $debut');
  expect(j, greaterThan(i),
      reason: 'marqueur de fin introuvable ou placé avant le début : $fin');
  return src.substring(i, j);
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  A1 — LECTURE D'UN MONTANT
  // ═════════════════════════════════════════════════════════════════════════
  group('A1 — lecture d\'un montant saisi', () {
    test('A1.1 un entier est accepté tel quel', () {
      expect(lire('10'), 10.0);
      expect(lire('1'), 1.0, reason: 'aucune borne basse métier à 2 €');
      expect(lire('500'), 500.0, reason: 'aucune borne haute métier à 200 €');
      expect(lire('10'), lire('10.00'), reason: 'même montant, deux écritures');
    });

    test('A1.2 virgule et point désignent le MÊME montant', () {
      expect(lire('10,50'), 10.5);
      expect(lire('10.50'), 10.5);
      expect(lire('10,50'), lire('10.50'),
          reason: 'virgule et point ne doivent jamais diverger');
      expect(lire('7,5'), 7.5);
      expect(lire('0,99'), 0.99);
    });

    test('A1.3 arrondi au centime, sans invention de chiffre', () {
      expect(lire('12,505'), 12.51);
      expect(lire('12,504'), 12.50);
      expect(lire('3,8'), 3.8);
      expect(lire('10,1'), 10.1);
    });

    test('A1.4 les espaces autour de la saisie sont ignorés', () {
      expect(lire('  25  '), 25.0);
      expect(lire('\t12,50\n'), 12.5);
    });

    test('A1.5 le texte de pré-remplissage ne produit jamais « 10.0 »', () {
      expect(MiseManuelleDialog.texteInitial(10.0), '10');
      expect(MiseManuelleDialog.texteInitial(10.5), '10.50');
      expect(MiseManuelleDialog.texteInitial(2.0), '2');
      expect(MiseManuelleDialog.texteInitial(0.99), '0.99');
      expect(MiseManuelleDialog.texteInitial(10.0).contains('.'), isFalse);
    });

    test('A1.6 l\'affichage de la mise ne la ramène JAMAIS à l\'euro', () {
      // Défaut mesuré avant ce lot : `_mise.toStringAsFixed(0)` affichait
      // 10,50 € sous la forme « 11 € » — un montant qui n'a jamais été engagé.
      expect('${fmtEuros(10.5)} €', '10.50 €');
      expect('${fmtEuros(10.0)} €', '10 €');
      expect('${fmtEuros(2.5)} €', '2.50 €');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A2 — ENTRÉES REFUSÉES
  // ═════════════════════════════════════════════════════════════════════════
  group('A2 — entrées refusées : rien n\'est deviné', () {
    test('A2.1 vide et blancs sont refusés', () {
      expect(lire(''), isNull);
      expect(lire('   '), isNull);
      expect(lire('\n\t'), isNull);
    });

    test('A2.2 zéro est refusé : une mise doit être strictement positive', () {
      expect(lire('0'), isNull);
      expect(lire('0,00'), isNull);
      expect(lire('0.0'), isNull);
    });

    test('A2.3 négatif est refusé', () {
      expect(lire('-5'), isNull);
      expect(lire('-0,01'), isNull);
      // Le formateur du champ n'autorise pas « - » : cette entrée ne peut
      // venir que d'un collage — elle est refusée tout de même.
      expect(lire('-10,50'), isNull);
    });

    test('A2.4 saisies illisibles refusées', () {
      expect(lire('abc'), isNull);
      expect(lire('10,5,3'), isNull, reason: 'deux séparateurs');
      expect(lire('10.5.3'), isNull, reason: 'deux séparateurs');
      expect(lire('€10'), isNull);
      expect(lire('10 €'), isNull);
      expect(lire(','), isNull);
      expect(lire('1,2,3,4'), isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A3 — AUCUN SLIDER DANS LE PARCOURS DE SAISIE
  // ═════════════════════════════════════════════════════════════════════════
  group('A3 — absence totale de Slider dans ce parcours', () {
    test('A3.1 le fichier ne construit plus aucun widget Slider', () {
      final src = sourceBetSheet();
      // Mesure sur la SOURCE, pas sur mes souvenirs.
      expect('Slider('.allMatches(src).length, 0,
          reason: 'aucune CONSTRUCTION de Slider ne doit subsister');
      expect('SliderTheme'.allMatches(src).length, 0,
          reason: 'SliderTheme n\'avait de sens qu\'autour du Slider');
      expect('min: 2, max: 200'.allMatches(src).length, 1,
          reason: 'l\'ancienne configuration ne survit QUE dans un commentaire '
              'd\'explication (1 occurrence attendue, texte seulement)');
    });

    test('A3.2 la méthode _buildMiseSelector n\'en contient aucune trace', () {
      final corps = corpsDe(
        sourceBetSheet(),
        'Widget _buildMiseSelector()',
        '// ── Aperçu du gain',
      );
      expect(corps.contains('Slider('), isFalse);
      expect(corps.contains('SliderTheme'), isFalse);
      expect(corps.contains('onChanged: (v) => setState(() => _mise'),
          isFalse,
          reason: 'le Slider était le seul à écrire _mise par onChanged');
    });

    test('A3.3 la saisie passe par la fenêtre dédiée, ouverte au toucher', () {
      final src = sourceBetSheet();
      expect(src.contains('_ouvrirSaisieMise'), isTrue);
      expect(src.contains('MiseManuelleDialog(montantActuel: _mise)'), isTrue);
      expect(src.contains('Toucher pour saisir le montant'), isTrue,
          reason: 'l\'affordance doit être visible');
      // Le montant affiché doit être TAPABLE (opaque = toute la surface).
      final corps = corpsDe(src, 'GestureDetector(', 'Toucher pour saisir');
      expect(corps.contains('HitTestBehavior.opaque'), isTrue);
      expect(corps.contains('onTap: _ouvrirSaisieMise'), isTrue);
    });

    test('A3.4 les montants rapides sont TOUS conservés', () {
      final src = sourceBetSheet();
      expect(src.contains('2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0'), isTrue,
          reason: 'les sept montants rapides doivent rester disponibles');
      final corps = corpsDe(
          src, 'Widget _buildMiseSelector()', '// ── Aperçu du gain');
      expect(corps.contains('Wrap('), isTrue);
      expect(corps.contains('setState(() => _mise = v)'), isTrue,
          reason: 'un montant rapide écrit directement la mise');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A4 — ANNULATION
  // ═════════════════════════════════════════════════════════════════════════
  group('A4 — annuler ne modifie pas la mise précédente', () {
    test('A4.1 la fenêtre rend null en cas d\'annulation', () {
      // `Navigator.pop(context)` = null : contrat de la fenêtre.
      final src = File('lib/widgets/paris/mise_manuelle_dialog.dart')
          .readAsStringSync();
      expect(src.contains('onPressed: () => Navigator.pop(context)'), isTrue,
          reason: '« Annuler » doit rendre null, pas un montant');
      expect(src.contains('child:\n              const Text(\'Annuler\'') ||
              src.contains("const Text('Annuler'"), isTrue);
    });

    test('A4.2 l\'appelant n\'écrit QUE si la valeur est non nulle', () {
      final corps = corpsDe(
        sourceBetSheet(),
        'Future<void> _ouvrirSaisieMise()',
        'Widget _buildMiseSelector()',
      );
      expect(corps.contains('if (saisie == null || !mounted) return;'), isTrue,
          reason: 'annulation = retour immédiat, aucune écriture');
      // L'écriture doit être APRÈS la garde, jamais avant.
      final garde = corps.indexOf('if (saisie == null || !mounted) return;');
      final ecriture = corps.indexOf('setState(() => _mise = saisie);');
      expect(garde, greaterThanOrEqualTo(0));
      expect(ecriture, greaterThan(garde),
          reason: 'setState ne doit jamais précéder la garde d\'annulation');
    });

    test('A4.3 le montant courant est rappelé pendant la saisie', () {
      final src = File('lib/widgets/paris/mise_manuelle_dialog.dart')
          .readAsStringSync();
      expect(src.contains('Mise actuelle :'), isTrue,
          reason: 'annuler doit être un choix conscient, pas une perte muette');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A5 — MONTANT RÉELLEMENT ENGAGÉ, PERSISTÉ
  // ═════════════════════════════════════════════════════════════════════════
  group('A5 — la mise engagée survit à la persistance réelle', () {
    UserPrediction pred({
      required String id,
      required String typePari,
      required double mise,
      double? miseGagnant,
      double? misePlace,
    }) =>
        UserPrediction(
          id: id,
          dateStr: '2026-11-25',
          numReunion: 3,
          numCourse: 7,
          nomCourse: 'PRIX DE LA MISE',
          hippodrome: 'VINCENNES',
          numeroCheval: 5,
          nomCheval: 'CHEVAL 5',
          cote: 4.0,
          typePari: typePari,
          createdAt: DateTime(2026, 11, 25, 10),
          montantMise: mise,
          numerosJoues: const [5],
          miseGagnant: miseGagnant,
          misePlace: misePlace,
        );

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('A5.1 une mise décimale simple survit à l\'écriture puis à la relecture',
        () async {
      final p = PmuProvider();
      const id = 'lot2b-A51';
      // `addPrediction` rend `void` — mesuré — l'identifiant est donc celui
      // qu'on fournit, et c'est LUI qu'on recherche sur le disque.
      p.addPrediction(pred(
        id: id,
        typePari: 'Simple Gagnant',
        mise: lire('10,50')!,
      ));
      await p.sauvegardeTerminee();

      // On relit le DISQUE, pas la mémoire.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('user_predictions_v2') ?? const <String>[];
      expect(raw, isNotEmpty, reason: 'l\'écriture doit avoir eu lieu');

      final relu = raw
          .map((s) => UserPrediction.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .firstWhere((x) => x.id == id);
      expect(relu.montantMise, 10.5,
          reason: 'le montant engagé doit être EXACTEMENT celui saisi');
      expect(relu.montantMise, isNot(11.0),
          reason: 'l\'ancien affichage arrondissait à 11 € — la donnée, non');
    });

    test('A5.2 Gagnant+Placé : les DEUX composantes gardent la même mise',
        () async {
      final p = PmuProvider();
      const id = 'lot2b-A52';
      final m = lire('10,50')!;
      p.addPrediction(pred(
        id: id,
        typePari: 'Gagnant+Placé',
        mise: m,
        miseGagnant: m,
        misePlace: m,
      ));
      await p.sauvegardeTerminee();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('user_predictions_v2') ?? const <String>[];
      final relu = raw
          .map((s) => UserPrediction.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .firstWhere((x) => x.id == id);

      expect(relu.miseGagnant, 10.5);
      expect(relu.misePlace, 10.5);
      expect(relu.miseTotaleEngagee, 21.0,
          reason: 'deux composantes à 10,50 € = 21 € réellement engagés');
      expect(relu.miseTotaleEngagee, isNot(22.0),
          reason: 'un arrondi à 11 € aurait inventé 22 €');
    });

    test('A5.3 les sites d\'écriture du widget portent la mise EXACTE', () {
      // Vérification structurelle : la persistance ne doit jamais réintroduire
      // un arrondi sur le montant engagé.
      final src = sourceBetSheet();
      expect(src.contains('montantMise: _mise,'), isTrue);
      expect(src.contains('miseEngagee: _mise,'), isTrue);
      expect(src.contains('miseGagnant: estGP ? _mise : null,'), isTrue);
      expect(src.contains('misePlace: estGP ? _mise : null,'), isTrue);
      expect(src.contains('miseGagnant: estGagnantPlace ? _mise : null,'), isTrue);
      expect(src.contains('misePlace: estGagnantPlace ? _mise : null,'), isTrue);
      // Aucun de ces sites ne doit arrondir.
      expect(src.contains('montantMise: _mise.roundToDouble()'), isFalse);
      expect(src.contains('montantMise: _mise.toStringAsFixed'), isFalse);
    });

    test('A5.4 Gagnant+Placé engage bien le DOUBLE en affichage', () {
      final src = sourceBetSheet();
      final corps = corpsDe(
          src, 'double get _miseReelle {', 'List<double> _getCotes3()');
      expect(corps.contains("== 'Gagnant+Placé'"), isTrue);
      expect(corps.contains('return _mise * 2;'), isTrue,
          reason: 'la mise réelle d\'un G+P est le double de la mise saisie');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A6 — LA FENÊTRE ELLE-MÊME
  // ═════════════════════════════════════════════════════════════════════════
  group('A6 — réglages du champ de saisie', () {
    test('A6.1 clavier numérique avec séparateur décimal', () {
      final src = File('lib/widgets/paris/mise_manuelle_dialog.dart')
          .readAsStringSync();
      expect(src.contains('numberWithOptions(decimal: true)'), isTrue,
          reason: 'c\'est ce réglage qui fait apparaître la virgule');
    });

    test('A6.2 le formateur autorise chiffres, virgule et point', () {
      final src = File('lib/widgets/paris/mise_manuelle_dialog.dart')
          .readAsStringSync();
      expect(src.contains("RegExp(r'[0-9.,]')"), isTrue,
          reason: 'un formateur trop strict empêcherait de TAPER la virgule');
    });

    test('A6.3 la fenêtre rend un double? et n\'écrit rien elle-même', () {
      final src = File('lib/widgets/paris/mise_manuelle_dialog.dart')
          .readAsStringSync();
      expect(src.contains('showDialog'), isFalse,
          reason: 'la fenêtre ne s\'ouvre pas elle-même');
      expect(src.contains('SharedPreferences'), isFalse,
          reason: 'la fenêtre ne persiste rien : l\'appelant décide');
      expect(src.contains('Navigator.pop(context, v)'), isTrue);
    });

    test('A6.4 le bouton OK valide, le bouton Annuler annule', () {
      final src = File('lib/widgets/paris/mise_manuelle_dialog.dart')
          .readAsStringSync();
      expect(src.contains("child: const Text('OK')"), isTrue);
      expect(src.contains('onPressed: _valider'), isTrue);
    });

    test('A6.5 erreur affichée, jamais une valeur inventée', () {
      final src = File('lib/widgets/paris/mise_manuelle_dialog.dart')
          .readAsStringSync();
      expect(src.contains('Montant invalide'), isTrue);
      expect(src.contains('errorText: _erreur'), isTrue,
          reason: 'l\'erreur doit être VISIBLE, pas seulement journalisée');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A7 — NON-RÉGRESSION DU LOT 2-A
  // ═════════════════════════════════════════════════════════════════════════
  group('A7 — le lot 2-A (gain manuel) reste intact', () {
    test('A7.1 les trois sorties du gain manuel sont inchangées', () {
      expect(ResultatSaisieGain.annule.valide, isFalse);
      expect(ResultatSaisieGain.annule.montant, isNull);
      expect(ResultatSaisieGain.efface.valide, isTrue);
      expect(ResultatSaisieGain.efface.montant, isNull);
      const zero = ResultatSaisieGain.valideAvec(0.0);
      expect(zero.montant, 0.0);
      expect(zero.montant, isNotNull);
    });

    test('A7.2 la fenêtre du gain manuel est toujours branchée', () {
      final src = File('lib/screens/mes_paris_screen.dart').readAsStringSync();
      expect(src.contains('gain_manuel_dialog.dart'), isTrue);
      expect(src.contains('_ouvrirSaisieGainManuel'), isTrue);
    });

    test('A7.3 les deux fenêtres partagent la MÊME règle de virgule', () {
      final mise = File('lib/widgets/paris/mise_manuelle_dialog.dart')
          .readAsStringSync();
      final gain = File('lib/widgets/paris/gain_manuel_dialog.dart')
          .readAsStringSync();
      expect(mise.contains("replaceAll(',', '.')"), isTrue);
      expect(gain.contains("replaceAll(',', '.')"), isTrue);
    });
  });
}
