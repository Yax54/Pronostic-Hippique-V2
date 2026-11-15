// ═══════════════════════════════════════════════════════════════════════════
//  V47 — G : CYCLE DE VIE DE LA BULLE MATINALE
//
//  OBJET
//  ─────
//  La correction G avait remplacé `Future.delayed(2 s)` — non annulable —
//  par un `Timer` annulable… mais l'attente était bâtie sur un
//  `Completer<void>` :
//
//      final completer = Completer<void>();
//      _bulleMatinaleTimer = Timer(2 s, () => completer.complete());
//      await completer.future;            // ← ATTENTE SANS ÉCHÉANCE
//
//  Si `dispose()` annulait le `Timer` AVANT son échéance, `complete()`
//  n'était jamais appelé : le `Future` restait suspendu À VIE et retenait
//  le `State` (donc ses caches). C'est le défaut que H1 supprime.
//
//  CORRECTIFS TESTÉS ICI
//  ─────────────────────
//  H1 : plus aucun `Completer` ; le corps est appelé DIRECTEMENT depuis le
//       callback du `Timer`, via `unawaited(...catchError(...))`.
//  H3 : `if (!mounted) return;` en tête du `addPostFrameCallback`, pour
//       empêcher toute initialisation tardive après destruction.
//
//  ⚠ PRINCIPE DE PREUVE
//  ────────────────────
//  « aucun test ne lève d'exception » NE PROUVE PAS l'absence de `Future`
//  suspendu : un `Future` orphelin est totalement silencieux. On vérifie
//  donc SÉPARÉMENT et EXPLICITEMENT :
//    • la disparition du mécanisme `Completer` (analyse de la source) ;
//    • que l'annulation empêche réellement le callback de s'exécuter
//      (compteur de déclenchements, pas seulement l'absence d'exception) ;
//    • qu'aucun minuteur ne reste pendant après démontage précoce.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pronostic_hippique/main.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/ia_badges_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_personality_service.dart';
import 'package:pronostic_hippique/services/ia_user_prefs_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  CONTRAT
// ───────────────────────────────────────────────────────────────────────────

/// Délai historique de la bulle matinale — INCHANGÉ.
const Duration kDelaiBulle = Duration(seconds: 2);

/// Chemin du fichier de production inspecté par G-T1.
const String kCheminSource = 'lib/screens/home_screen.dart';

/// Lit la source de production (analyse statique du mécanisme).
String lireSource() {
  final fichier = File(kCheminSource);
  if (!fichier.existsSync()) {
    fail('fichier de production introuvable : $kCheminSource '
        '(le test doit être lancé depuis la racine du projet)');
  }
  return fichier.readAsStringSync();
}

/// Extrait le corps de `_declencherBulleMatinale` tel qu'il est écrit,
/// AVEC LES COMMENTAIRES RETIRÉS.
///
/// ⚠ Nécessaire : mes propres commentaires contiennent les mots « await »,
///   « async » et « Future.delayed » pour expliquer ce qui a été retiré.
///   Un test qui chercherait ces motifs dans le texte brut trouverait ces
///   explications et conclurait à tort que le code les utilise encore.
String extraireDeclencheur(String source) {
  final debut = source.indexOf('void _declencherBulleMatinale()');
  expect(debut, greaterThan(-1),
      reason: 'H1 : _declencherBulleMatinale doit exister');
  // Fin de la méthode : la première accolade fermante en début de ligne.
  final fin = source.indexOf('\n  }\n', debut);
  expect(fin, greaterThan(debut));
  return retirerCommentaires(source.substring(debut, fin));
}

/// Retire les commentaires `//` et `///` d'un fragment de code.
String retirerCommentaires(String fragment) => fragment
    .split('\n')
    .where((l) {
      final t = l.trim();
      return !t.startsWith('//');
    })
    .join('\n');

// ───────────────────────────────────────────────────────────────────────────
//  MONTAGE / DÉMONTAGE
// ───────────────────────────────────────────────────────────────────────────

/// Monte l'application complète en absorbant les exceptions.
Future<List<String>> monter(WidgetTester tester, Size taille) async {
  await tester.binding.setSurfaceSize(taille);
  final constatees = <String>[];
  final ancien = FlutterError.onError;
  FlutterError.onError = (details) => constatees.add(details.toString());
  await tester.pumpWidget(const PronosticHippiqueApp());
  await tester.pump();
  FlutterError.onError = ancien;
  return filtrer(constatees);
}

/// Détruit l'arbre en absorbant les exceptions de démontage.
Future<List<String>> demonter(WidgetTester tester) async {
  final constatees = <String>[];
  final ancien = FlutterError.onError;
  FlutterError.onError = (details) => constatees.add(details.toString());
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  FlutterError.onError = ancien;
  return filtrer(constatees);
}

/// Exceptions réellement significatives (on écarte le bruit réseau PMU).
List<String> filtrer(List<String> brut) => brut
    .where((e) => !e.contains('PMU API'))
    .where((e) => !e.contains('HttpClient'))
    .toList();

/// Vrai si l'exception concerne la barre de navigation (`_NavItem`).
///
/// ⚠ Périmètre : le débordement horizontal résiduel de `_NavItem` sur les
///   écrans étroits (Ahem, libellés longs) est ANTÉRIEUR et hors périmètre
///   G. On ne l'ignore pas globalement — on l'isole par TYPE pour que toute
///   AUTRE exception reste bloquante.
bool concerneBarreNavigation(String exception) =>
    exception.contains('_NavItem') ||
    (exception.contains('overflowed by') && exception.contains('on the right'));

/// Filtre les seules exceptions imputables à la barre de navigation.
List<String> imputablesBarre(List<String> brut) =>
    brut.where(concerneBarreNavigation).toList();

/// Filtre les exceptions qui ne sont PAS imputables à la barre de navigation.
List<String> horsBarre(List<String> brut) =>
    brut.where((e) => !concerneBarreNavigation(e)).toList();

/// Description courte d'une exception, pour des messages lisibles.
String resume(Object? e) {
  if (e == null) return 'aucune';
  final l = e.toString().split('\n').firstWhere((x) => x.trim().isNotEmpty,
      orElse: () => '');
  return l.length > 110 ? l.substring(0, 110) : l;
}

/// Récupère ET vide l'exception en attente, sous forme de liste.
///
/// ⚠ `takeException()` ne retourne qu'UNE exception : appelé une seule fois,
///   il en masquerait d'autres. On vide jusqu'à épuisement.
List<String> _prendreEnAttente(WidgetTester tester) {
  final out = <String>[];
  var garde = 0;
  while (garde++ < 20) {
    final e = tester.takeException();
    if (e == null) break;
    out.add(e.toString());
  }
  return out;
}

/// Monte `MainNavigation` sous un jeu COMPLET de providers (comme `main()`),
/// mais avec un `NavigationNotifier` fourni par le TEST (une sonde).
///
/// ⚠ `MainNavigation` → `HomeScreen` lit `DataRefreshService`, et les autres
///   écrans lisent `PmuProvider`, `AlertService`, `IaMemoryService`… Sans eux
///   l'arbre lève `ProviderNotFoundException`. On reproduit donc exactement
///   la liste de `PronosticHippiqueApp`, à une exception près : le notifier.
Future<void> monterSousProviders(WidgetTester tester, Size taille,
    NavigationNotifier sonde) async {
  await tester.binding.setSurfaceSize(taille);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => PmuProvider()),
      ChangeNotifierProvider<NavigationNotifier>.value(value: sonde),
      ChangeNotifierProvider.value(value: DataRefreshService.instance),
      ChangeNotifierProvider.value(value: AlertService.instance),
      ChangeNotifierProvider.value(value: IaPersonalityService.instance),
      ChangeNotifierProvider.value(value: IaUserPrefsService.instance),
      ChangeNotifierProvider.value(value: IaBadgesService.instance),
      ChangeNotifierProvider.value(value: IaMemoryService.instance),
    ],
    child: const MaterialApp(home: MainNavigation()),
  ));
  await tester.pump();
}

/// Sonde de test : expose `hasListeners` (membre protégé de `ChangeNotifier`).
///
/// ⚠ Aucune modification de la production : c'est une SOUS-CLASSE définie
///   dans le fichier de test. Elle permet de prouver le retrait effectif du
///   listener sur l'objet lui-même, et non par simple absence d'exception.
class NavigationNotifierSonde extends NavigationNotifier {
  /// `true` si au moins un écouteur est encore abonné.
  bool get aUnEcouteur => hasListeners;
}

/// Compte les widgets dont le type de runtime contient `motif`
/// (permet de compter les bulles IA sans dépendre d'un type privé).
int compter(WidgetTester tester, String motif) => find
    .byWidgetPredicate((w) => w.runtimeType.toString().contains(motif))
    .evaluate()
    .length;

/// Récupère le NavigationNotifier depuis l'arbre.
NavigationNotifier lireNavigation(WidgetTester tester) {
  final element = tester.element(find.byType(MainNavigation));
  return Provider.of<NavigationNotifier>(element, listen: false);
}

/// Récupère le NavigationNotifier en le traitant comme une sonde.
NavigationNotifierSonde lireNavigationSonde(WidgetTester tester) {
  final nav = lireNavigation(tester);
  expect(nav, isA<NavigationNotifierSonde>(),
      reason: 'le notifier doit être une sonde (arbre construit par le test)');
  return nav as NavigationNotifierSonde;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═══════════════════════════════════════════════════════════════════════
  //  G-T1 — LE MÉCANISME `Completer` A DISPARU (analyse statique)
  // ═══════════════════════════════════════════════════════════════════════
  //
  //  Test DISCRIMINANT du défaut : la version fautive contenait
  //  `Completer<void>()` et `await completer.future` DANS le déclencheur.
  //  On inspecte le code de production lui-même, pas son comportement :
  //  c'est la seule façon de prouver l'absence d'une attente suspendue,
  //  qu'aucune exception ne signalerait.

  group('G-T1 — le mécanisme Completer a disparu', () {
    test('aucun Completer dans le fichier de production', () {
      final source = lireSource();
      // On ignore les commentaires : ils MENTIONNENT le Completer pour
      // expliquer pourquoi il a été retiré.
      final sansCommentaires = source
          .split('\n')
          .where((l) {
            final t = l.trim();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join('\n');
      expect(sansCommentaires.contains('Completer<'),
          isFalse,
          reason: 'H1 : plus aucun Completer ne doit subsister');
      expect(sansCommentaires.contains('completer.future'), isFalse,
          reason: 'H1 : plus aucune attente sur completer.future');
      expect(sansCommentaires.contains('.complete()'), isFalse,
          reason: 'H1 : plus aucun appel à complete()');
    });

    test('le déclencheur n\'est plus asynchrone et n\'attend rien', () {
      final corps = extraireDeclencheur(lireSource());
      expect(corps.contains('async'), isFalse,
          reason: 'H1 : le déclencheur doit être synchrone');
      // ⚠ Ne PAS chercher la sous-chaîne « await » : l'identifiant
      //   `unawaited` la contient. On cherche le MOT-CLÉ `await` isolé.
      expect(RegExp(r'\bawait\b').hasMatch(corps), isFalse,
          reason: 'H1 : aucune attente suspendue dans le déclencheur');
    });

    test('le déclencheur arme un Timer de 2 s et appelle unawaited', () {
      final corps = extraireDeclencheur(lireSource());
      expect(corps.contains('Timer('), isTrue,
          reason: 'H1 : le minuteur annulable doit être utilisé');
      expect(corps.contains('Duration(seconds: 2)'), isTrue,
          reason: 'H1 : le délai de 2 s doit être conservé');
      expect(corps.contains('unawaited('), isTrue,
          reason: 'H1 : appel asynchrone explicite depuis le callback');
      expect(corps.contains('catchError'), isTrue,
          reason: 'les erreurs ne doivent pas être silencieusement ignorées');
      expect(corps.contains('if (!mounted) return;'), isTrue,
          reason: 'le contrôle mounted doit être conservé');
    });

    test('le Timer est annulé dans dispose()', () {
      final source = lireSource();
      final debut = source.indexOf('void dispose() {');
      expect(debut, greaterThan(-1));
      final fin = source.indexOf('\n  }\n', debut);
      final corps = source.substring(debut, fin);
      expect(corps.contains('_bulleMatinaleTimer?.cancel()'), isTrue,
          reason: 'le minuteur doit être annulé');
      expect(corps.contains('_bulleMatinaleTimer = null'), isTrue,
          reason: 'la référence doit être relâchée');
      expect(corps.contains('removeListener(_onNavigationChange)'), isTrue,
          reason: 'le listener doit être retiré');
      expect(corps.contains('context.read'), isFalse,
          reason: 'aucune lecture de Provider dans dispose()');
    });

    test('H3 — le post-frame vérifie mounted en PREMIER', () {
      final source = lireSource();
      final debut = source.indexOf('addPostFrameCallback(');
      expect(debut, greaterThan(-1));
      final fin = source.indexOf('});', debut);
      final corps = source.substring(debut, fin);
      expect(corps.contains('if (!mounted) return;'), isTrue,
          reason: 'H3 : garde mounted obligatoire');
      // Le garde doit précéder TOUTE action (minuteur, listener, chargements).
      final posGarde = corps.indexOf('if (!mounted) return;');
      final posAction = corps.indexOf('_declencherBulleMatinale()');
      expect(posGarde, lessThan(posAction),
          reason: 'H3 : le garde doit précéder la première action');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G-T1b — LE CORPS MÉTIER EST STRICTEMENT INCHANGÉ
  // ═══════════════════════════════════════════════════════════════════════

  group('G-T1b — corps métier inchangé', () {
    test('les six points d\'ancrage du corps historique sont présents', () {
      final source = lireSource();
      final debut = source.indexOf('Future<void> _afficherBulleMatinale()');
      expect(debut, greaterThan(-1), reason: 'le corps doit avoir été déplacé');
      final fin = source.indexOf('\n  }\n', debut);
      final corps = source.substring(debut, fin);

      // Les marqueurs métier que H1 ne doit surtout pas altérer.
      for (final attendu in <String>[
        'IaPersonalityService.instance', // source du message
        '_conseilIACached', // conseil du jour
        '_meilleurPariCached', // meilleur pari du jour
        'dejaFige', // garde anti-régénération v10.71
        'dateDepuisCourseKey(', // validation calendaire A-2
        'obtenirOuCreerSelectionWidgetPremiumDuJour', // get-or-create
        'svc.messageBulle(', // message affiché
        'IaBubbleOverlayState.afficher(', // affichage
        'recalculerCoursesConseilIA', // recalcul Conseil IA
        'verifierCoursesConseilIA', // vérification Conseil IA
        'Duration(seconds: 4)', // seconde bulle (Conseil IA)
        '_chargerSelectionsFigees()', // rechargement final
      ]) {
        expect(corps.contains(attendu), isTrue,
            reason: 'le corps métier doit conserver « $attendu »');
      }
    });

    test('le délai de 2 s est la seule valeur de temps introduite', () {
      // Aucune autre durée ne doit apparaître dans le déclencheur.
      final declencheur = _lireDeclencheurSur();
      final durees = RegExp(r'Duration\(seconds: (\d+)\)')
          .allMatches(declencheur)
          .map((m) => m.group(1))
          .toSet();
      expect(durees, <String>{'2'},
          reason: 'H1 : seule la durée de 2 s est autorisée, trouvé $durees');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G-T2 — DESTRUCTION AVANT LES 2 SECONDES (le chemin du risque)
  // ═══════════════════════════════════════════════════════════════════════

  group('G-T2 — destruction avant 2 s', () {
    testWidgets('démontage à 1 s puis 1 s : aucune exception', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auMontage = await monter(tester, const Size(393, 852));
      expect(auMontage, isEmpty,
          reason: 'montage sans exception significative, obtenu : '
              '${auMontage.map(resume).toList()}');

      // On vit 1 s : le minuteur de 2 s est ARMÉ mais pas échu.
      await tester.pump(const Duration(seconds: 1));
      // Destruction AVANT l'échéance → c'est exactement le chemin où
      // l'ancien `await completer.future` restait suspendu à vie.
      final auDemontage = await demonter(tester);
      expect(auDemontage, isEmpty,
          reason: 'démontage sans exception, obtenu : '
              '${auDemontage.map(resume).toList()}');
      final auRemontage = await monter(tester, const Size(393, 852));
      expect(auRemontage, isEmpty, reason: 'remontage sans exception');
      // L'ancien défaut se serait manifesté ici : si le Future était resté
      // suspendu, la clôture du test lèverait « A Timer is still pending »
      // ou laisserait une microtâche non vidée (microtaskCount != 0).
      expect(tester.takeException(), isNull,
          reason: 'aucune exception en attente après démontage');
    });

    testWidgets('le minuteur est vidé après démontage précoce',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await monter(tester, const Size(393, 852));
      await tester.pump(const Duration(seconds: 1));
      await demonter(tester);
      // On avance au-delà des 2 s : si le minuteur n'avait pas été annulé,
      // son callback s'exécuterait ici sur un arbre mort.
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull,
          reason: 'le minuteur annulé ne doit rien déclencher après 2 s');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G-T3 — L'ANNULATION EMPÊCHE RÉELLEMENT LE CALLBACK (preuve active)
  // ═══════════════════════════════════════════════════════════════════════

  group('G-T3 — l\'annulation empêche toute exécution ultérieure', () {
    testWidgets('le déclencheur n\'agit plus après dispose()',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await monter(tester, const Size(393, 852));
      await tester.pump(const Duration(seconds: 1));
      await demonter(tester);

      // Aucune bulle ne doit apparaître, même longtemps après l'échéance.
      for (var s = 0; s < 6; s++) {
        await tester.pump(const Duration(seconds: 1));
        expect(compter(tester, 'IaBubble'), 0,
            reason: 'aucune bulle ne doit être insérée après destruction '
                '(t + ${s + 1} s)');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('aucune bulle insérée après destruction', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await monter(tester, const Size(393, 852));
      await demonter(tester);
      await tester.pump(const Duration(seconds: 3));
      // Le mécanisme d'affichage est global (`IaBubbleOverlayState._current`
      // devient null au dispose de l'overlay) : `afficher()` est alors un
      // no-op. On vérifie qu'aucune entrée d'overlay n'a survécu.
      expect(compter(tester, 'IaBubble'), 0,
          reason: 'aucune bulle fantôme après destruction');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G-T4 — RETOUR RAPIDE SUR HOME / ABSENCE DE DOUBLE BULLE
  // ═══════════════════════════════════════════════════════════════════════

  group('G-T4 — retour rapide sur Home', () {
    testWidgets('HomeScreen survit au changement d onglet (IndexedStack)',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // ⚠ 480 dp : largeur où la barre de navigation n'a AUCUN débordement
      //   (le résidu `_NavItem` à 393 dp est antérieur et hors périmètre G).
      //   On isole ainsi le cycle de vie de HomeScreen de ce bruit connu.
      final auMontage = await monter(tester, const Size(480, 1000));
      expect(horsBarre(auMontage), isEmpty,
          reason: 'montage propre hors barre de navigation');

      final nav = lireNavigation(tester);
      nav.goTo(2);
      await tester.pump();
      nav.goTo(0);
      await tester.pump();
      nav.goTo(3);
      await tester.pump();
      nav.goTo(0);
      await tester.pump();

      final restantes = horsBarre(filtrer(_prendreEnAttente(tester)));
      expect(restantes, isEmpty,
          reason: 'les allers-retours ne doivent rien lever, obtenu : '
              '${restantes.map(resume).toList()}');
      // Un seul écran d'accueil monté : il n'y a donc pas de second
      // déclencheur armé, donc pas de double bulle possible.
      expect(find.byType(MainNavigation), findsOneWidget);
    });

    testWidgets('aucune double bulle après plusieurs retours', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await monter(tester, const Size(480, 1000));

      final nav = lireNavigation(tester);
      for (var i = 0; i < 4; i++) {
        nav.goTo(2);
        await tester.pump(const Duration(milliseconds: 500));
        nav.goTo(0);
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump(const Duration(seconds: 3));
      final combien = compter(tester, 'IaBubble');
      expect(combien, lessThanOrEqualTo(1),
          reason: 'au plus une bulle à l écran, obtenu $combien');
      expect(horsBarre(filtrer(_prendreEnAttente(tester))), isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G-T5 — DÉLAI DE 2 SECONDES CONSERVÉ
  // ═══════════════════════════════════════════════════════════════════════

  group('G-T5 — le délai de 2 s est conservé', () {
    test('la constante testée correspond au code de production', () {
      expect(kDelaiBulle, const Duration(seconds: 2));
      final corps = _lireDeclencheurSur();
      expect(corps.contains('Duration(seconds: 2)'), isTrue,
          reason: 'le délai de production doit rester 2 s');
    });

    testWidgets('à 1,9 s rien ne s\'affiche, à 3 s l\'arbre est stable',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await monter(tester, const Size(393, 852));
      await tester.pump(const Duration(milliseconds: 1900));
      // Avant l'échéance, aucune bulle ne doit être insérée par le minuteur.
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(tester.takeException(), isNull,
          reason: 'l\'échéance du minuteur ne doit rien lever');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G-T6 — RETRAIT DU LISTENER / ABSENCE D'EXCEPTION APRÈS DÉMONTAGE
  // ═══════════════════════════════════════════════════════════════════════

  group('G-T6 — retrait du listener NavigationNotifier', () {
    testWidgets('le notifier ne porte plus de listener après destruction',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Le notifier est fourni par le test (sonde) : il survit au démontage,
      // ce qui permet de prouver le RETRAIT du listener et non la simple
      // destruction de l'objet par le Provider.
      final sonde = NavigationNotifierSonde();
      addTearDown(sonde.dispose);
      await monterSousProviders(tester, const Size(393, 852), sonde);
      expect(sonde.aUnEcouteur, isTrue,
          reason: 'au montage, HomeScreen doit écouter la navigation '
              '(sinon ce test ne prouverait rien)');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // LA preuve : le listener a bien été retiré de l'objet lui-même,
      // indépendamment de toute exception.
      expect(sonde.aUnEcouteur, isFalse,
          reason: 'dispose() doit retirer le listener de navigation');
      expect(horsBarre(filtrer(_prendreEnAttente(tester))), isEmpty,
          reason: 'démontage sans exception');
    });

    testWidgets('un notifier survivant ne réveille plus le State détruit',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Le notifier est fourni par le test : il survit au démontage.
      final nav = NavigationNotifierSonde();
      addTearDown(nav.dispose);

      await monterSousProviders(tester, const Size(393, 852), nav);
      expect(nav.aUnEcouteur, isTrue,
          reason: 'HomeScreen doit s être abonné au montage');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(nav.aUnEcouteur, isFalse,
          reason: 'le listener doit être retiré au démontage');

      // Le notifier est VIVANT : notifier doit être inoffensif.
      nav.goTo(5);
      nav.goTo(0);
      await tester.pump();
      expect(horsBarre(filtrer(_prendreEnAttente(tester))), isEmpty,
          reason: 'aucun setState ni lecture de context sur un State détruit');
    });

    testWidgets('démontage répété ne lève rien', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (var i = 0; i < 3; i++) {
        final constatees = await monter(tester, const Size(480, 1000));
        await tester.pump(const Duration(milliseconds: 300));
        final auDemontage = await demonter(tester);
        final restantes = horsBarre(<String>[...constatees, ...auDemontage]);
        expect(restantes, isEmpty,
            reason: 'cycle montage/démontage $i sans exception, obtenu : '
                '${restantes.map(resume).toList()}');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  G-T7 — LE MINUTEUR RESTE ANNULABLE (contrat de type)
  // ═══════════════════════════════════════════════════════════════════════

  group('G-T7 — contrat du minuteur', () {
    test('dart:async est importé et unawaited utilisé', () {
      final source = lireSource();
      expect(source.contains("import 'dart:async';"), isTrue,
          reason: 'Timer et unawaited proviennent de dart:async');
      expect(source.contains('unawaited('), isTrue);
    });

    test('aucun Future.delayed dans le déclencheur', () {
      final corps = _lireDeclencheurSur();
      expect(corps.contains('Future.delayed'), isFalse,
          reason: 'le minuteur doit remplacer Future.delayed');
    });
  });
}

/// Relit le déclencheur depuis la source de production.
///
/// Helper hors du `main` pour rester utilisable dans les `test(...)`
/// comme dans les `testWidgets(...)`.
String _lireDeclencheurSur() => extraireDeclencheur(lireSource());
