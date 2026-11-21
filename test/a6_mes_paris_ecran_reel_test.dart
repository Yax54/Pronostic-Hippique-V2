// ═══════════════════════════════════════════════════════════════════════════
//  A6 — TEST DE L'ÉCRAN RÉEL `MesPariScreen`
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE PRODUCTION.
//
//  OBJET : monter le VÉRITABLE écran `MesPariScreen` et vérifier dessus
//  l'affichage A6 des arrivées officielles avec ex æquo.
//
//  ── CONTRAINTE DE HARNAIS MESURÉE (à ne pas confondre avec un défaut) ────
//  Toute la préparation (données `SharedPreferences`, singletons, courses
//  suivies, arrivées L0) est exécutée DANS LE CORPS de chaque `testWidgets`,
//  jamais dans un `setUp()` enregistré.
//
//  Mesures :
//    • sonde X (tout dans le corps, zone FakeAsync)  → `succes=true` en 5 s ;
//    • sonde T0 (mêmes appels inlinés dans le corps) → `succes=true` en 6 s ;
//    • sonde V (`setUp()` enregistré + mêmes appels) → `enregistrer()` ne
//      rend JAMAIS la main ;
//    • sonde W1 (singleton instancié avant `testWidgets`) → idem, blocage.
//
//  Explication : `ArriveeOfficielleService` instancié hors de la zone
//  FakeAsync de `testWidgets` voit sa chaîne `_serialiser` / `_chaineEcriture`
//  créée dans une autre zone de test ; la `Future` rendue par `enregistrer()`
//  ne se termine alors plus. Aucune dépendance au frame n'a été trouvée dans
//  la chaîne (grep `userEndFrame|requestFrame|scheduleFrame` : aucune
//  occurrence) et `enregistrer()` n'écrit que dans `SharedPreferences`.
//  → AUCUN défaut de production n'est démontré. Contrainte de harnais.
//
//  ── Méthode de montage ───────────────────────────────────────────────────
//  `pumpWidget` + `pump()`, comme `v47_g_bulle_matinale_test.dart` (vert).
//  `tester.runAsync` n'est PAS utilisé : mesuré inutile (sonde X sans lui).
//
//  ── D'où vient `_arrivee`, la garde de l'affichage ───────────────────────
//  `mes_paris_screen.dart:1878` n'affiche l'arrivée que si `_arrivee` est
//  non nul. `_arrivee` est renseigné SYNCHRONIQUEMENT dans `initState`
//  (l.981-984) depuis `course.arriveeFinale` quand `course.isGagne != null`.
//  Aucun réseau n'est requis : la fixture porte `isGagne` + `arriveeFinale`,
//  comme une course déjà résolue.
//
//  ── Débordements PRÉEXISTANTS, hors composant A6 (mesurés, non masqués) ──
//  Le montage produit deux `RenderFlex` overflow étrangers au bloc A6 :
//    • `mes_paris_screen.dart:119` — `Row` du titre de l'`AppBar` (60 px) ;
//    • `mes_paris_screen.dart:1661` — `Row` « Mise + badge type de pari »
//      dans l'en-tête de carte (120 px).
//  Ils sont RECENSÉS et RAPPORTÉS séparément. Chaque test exige qu'AUCUN
//  débordement ne provienne du composant A6 (`Wrap`, `BadgeExAequo`,
//  `LigneArriveeExAequo`) — sans jamais absorber les autres.
//
//  ── « Mode compact » — limite honnête ────────────────────────────────────
//  `ArriveReelleWidget`, seul widget doté d'un paramètre `compact`, N'EST PAS
//  instancié par `mes_paris_screen.dart` (grep : aucune occurrence de
//  `ArriveReelleWidget` dans ce fichier ; « compact » n'y apparaît qu'en
//  commentaire, l.2239). Le mode compact est donc vérifié ici comme la
//  PRÉSENTATION COMPACTE du bloc A6 : une seule ligne à largeur normale
//  (hauteur d'une ligne à 400 dp), et repli (hauteur accrue) à 320 dp.
//
//  ── Ce qui n'est pas touché ─────────────────────────────────────────────
//  Gradient, poids, seuils, calibration, apprentissage IA, ELO, TOP3,
//  archives. Aucune police n'est réduite.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/main.dart' show NavigationNotifier;
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/screens/mes_paris_screen.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/ia_badges_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_personality_service.dart';
import 'package:pronostic_hippique/services/ia_user_prefs_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';
import 'package:pronostic_hippique/widgets/arrivee_officielle_groupes_widget.dart';

// ─────────────────────────── Outils ────────────────────────────────────────

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

const Map<String, double> _poidsDefaut = {
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
  'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
  'mouvCote': 0.06, 'placeDepart': 0.03,
};

Map<String, Object> _prefs({List<String>? tracked}) => <String, Object>{
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
      if (tracked != null) 'tracked_courses_v1': tracked,
    };

/// Course suivie DÉJÀ RÉSOLUE.
///
/// `isGagne` non nul + `arriveeFinale` non vide ⇒ `initState` renseigne
/// `_arrivee` de façon SYNCHRONE (`mes_paris_screen.dart:981-984`) : le bloc
/// d'arrivée s'affiche sans aucun appel réseau.
/// `heureDepart` à −60 min : au-delà du seuil de −5 min de la carte, et sous
/// la purge 24 h d'`AlertService._load()` (l.517-522).
TrackedCourse _suivi(DateTime dep, {int numCourse = 1}) => TrackedCourse(
      numReunion: 1,
      numCourse: numCourse,
      nomCourse: 'PRIX A6 ECRAN',
      hippodrome: 'VINCENNES',
      heureDepart: dep,
      numeroCheval: 7,
      nomCheval: 'CHEVAL_7',
      miseEngagee: 10.0,
      typePari: 'Simple Gagnant',
      cote: 5.0,
      isGagne: false,
      arriveeFinale: const <int>[7, 4, 2, 9, 1],
      messageResultat: 'Résultat officiel enregistré',
      storageKey: 'R1C${numCourse}_${_fmt(dep)}',
    );

/// Sème les arrivées L0 par les API PUBLIQUES — UN SEUL appel d'écriture.
///
/// ⚠️ CONTRAINTE DE HARNAIS MESURÉE (cause exacte du blocage à partir du 2ᵉ
///    test) : `ArriveeOfficielleService` est un `static final`
///    (`arrivee_officielle_service.dart:370-373`) et sa chaîne
///    `_chaineEcriture` est créée par le PREMIER appel d'écriture, donc dans
///    la zone FakeAsync du premier `testWidgets` qui écrit. Le framework FERME
///    cette zone à la fin du test ; tout `.then` ultérieur est alors planifié
///    dans une zone morte et la `Future` rendue par `enregistrer()` ne se
///    termine JAMAIS.
///
///    Constat : A6-E1 (aucune écriture L0) puis A6-E2 (1ʳᵉ écriture) passe en
///    1 s ; lancés ensemble, E2 ne termine plus. Les trois autres tests du
///    projet qui écrivent (`a6_2b1`, `a6_2b2`, `a6_2b3`) n'appellent
///    `enregistrer()` qu'UNE seule fois par processus — même contrainte.
///
///    Correctif : toutes les arrivées L0 dont le fichier a besoin sont semées
///    en UN appel `enregistrerGroupe`, effectué par le PREMIER test exécuté
///    ([_semerToutesLesArrivees], appelé une seule fois par processus).
// ── Les trois arrivées L0 dont ce fichier a besoin ────────────────────────
const List<List<int>> _gAucunExAequo = <List<int>>[
  <int>[7], <int>[4], <int>[2], <int>[9], <int>[1],
];
const List<List<int>> _gDeuxExAequo = <List<int>>[
  <int>[7], <int>[4], <int>[11, 9], <int>[6],
];
const List<List<int>> _gTroisExAequo = <List<int>>[
  <int>[7], <int>[4], <int>[11, 9, 12], <int>[6],
];

/// Clé L0 lue par l'écran : `TrackedCourse.key` = `R{nRéunion}C{nCourse}_date`.
String _cleCourse(int numCourse) =>
    'R1C${numCourse}_${_fmt(DateTime.now())}';

/// Une seule écriture pour tout le fichier, exécutée par le premier test.
bool _arriveesSemees = false;

/// Sème les trois arrivées en UN SEUL appel d'écriture.
///
/// Chaque scénario utilise un NUMÉRO DE COURSE différent (`numCourse: 1/2/3`)
/// pour que sa course suivie pointe sur sa propre clé L0 : c'est la clé que
/// l'écran lit (`_groupesExAequoAffiches` → `widget.course.key`).
Future<void> _semerToutesLesArrivees() async {
  if (_arriveesSemees) return;

  final groupes = <List<List<int>>>[
    _gAucunExAequo,
    _gDeuxExAequo,
    _gTroisExAequo,
  ];
  final aEcrire = <EntreeArrivee>[];

  for (var i = 0; i < groupes.length; i++) {
    final cle = _cleCourse(i + 1);
    final e = ArriveeOfficielleService.depuisJsonCourse(
      <String, dynamic>{
        'statut': kStatutArriveeDefinitiveComplete,
        'isArriveeDefinitive': true,
        'arriveeDefinitive': true,
        'nombreDeclaresPartants': 12,
        'ordreArrivee': groupes[i],
      },
      courseKey: cle,
    );
    expect(e, isNotNull, reason: 'TÉMOIN : fixture L0 acceptée ($cle)');
    aEcrire.add(e!);
  }

  final res =
      await ArriveeOfficielleService.instance.enregistrerGroupe(aEcrire);
  expect(res.succes, isTrue,
      reason: 'TÉMOIN : écriture L0 groupée confirmée (erreur=${res.erreur})');

  for (var i = 0; i < groupes.length; i++) {
    final cle = _cleCourse(i + 1);
    expect(ArriveeOfficielleService.instance.arrivee(cle), equals(groupes[i]),
        reason: 'TÉMOIN : L0 $cle rend exactement ce qui a été écrit');
  }
  _arriveesSemees = true;
}

/// PRÉPARATION COMPLÈTE — exécutée dans le CORPS de chaque `testWidgets`.
///
/// ⚠️ NE JAMAIS déplacer cet enchaînement dans un `setUp()` enregistré :
///    mesuré bloquant (`ArriveeOfficielleService.enregistrer()` ne rend plus
///    la main). Voir l'en-tête du fichier.
///
/// Isolation : `SharedPreferences.setMockInitialValues` remplace le store,
/// `AlertService.recharger()` fait `_trackedCourses.clear()` (l.502) puis
/// recharge les seules courses du scénario, et les `vider*PourResetComplet`
/// remettent les singletons à zéro. Aucun état ne traverse les scénarios.
Future<DateTime> _preparer({int numCourse = 1}) async {
  // ORDRE IMPOSÉ (mesuré) :
  //   1. le store mocké est posé AVANT tout appel qui pourrait lire le disque
  //      (`getInstance()` sans handler installé ne rend jamais la main) ;
  //   2. le semis L0 a lieu APRÈS la remise à zéro de `ArriveeOfficielleService`,
  //      sinon `viderMemoireSeulement()` effacerait `_shards` juste après
  //      l'écriture (`arrivee()` lit `_shards[mois]` puis `_enAttente`).
  SharedPreferences.setMockInitialValues(_prefs());
  ZoneTurfService.viderCachePourResetComplet();
  DataRefreshService.instance.viderMemoirePourResetComplet();
  // ⚠️ `viderMemoireSeulement()` efface `_shards` : il ne doit passer qu'UNE
  //    fois, AVANT le semis. Le rejouer ensuite détruirait les arrivées L0
  //    déjà écrites, et le semis ne les réécrirait pas (une seule écriture
  //    par processus — contrainte de zone FakeAsync documentée plus haut).
  //    Les trois courses (C1/C2/C3) restent en RAM ; chaque scénario lit la
  //    sienne par `course.key`, l'isolation est donc assurée par la CLÉ.
  if (!_arriveesSemees) {
    ArriveeOfficielleService.instance.viderMemoireSeulement();
  }
  await IaMemoryService.instance.recharger();
  await _semerToutesLesArrivees();

  // Données du scénario : une seule course suivie, déjà résolue.
  final dep = DateTime.now().subtract(const Duration(minutes: 60));
  SharedPreferences.setMockInitialValues(
    _prefs(tracked: [json.encode(_suivi(dep, numCourse: numCourse).toJson())]),
  );
  await AlertService.instance.recharger();
  expect(AlertService.instance.trackedCourses.length, 1,
      reason: 'TÉMOIN : la course suivie du scénario est bien chargée');
  return dep;
}

/// Erreurs de rendu collectées pendant le montage courant.
///
/// ⚠️ POURQUOI PAS `tester.takeException()` : il ne rend que le message
///    « A RenderFlex overflowed by N pixels », SANS le widget fautif. Il est
///    donc impossible de distinguer le composant A6 des deux débordements
///    préexistants (`AppBar` l.119, en-tête de carte l.1661). On collecte à
///    la source les `FlutterErrorDetails` complets, comme `monter()` de
///    `v47_g_bulle_matinale_test.dart`, ce qui donne l'ORIGINE exacte.
///    Aucune erreur n'est absorbée : elles sont toutes listées et rappor­tées.
List<String> _erreursRendu = <String>[];

/// Recense les erreurs de rendu collectées jusqu'ici (aucune n'est masquée).
List<String> _debordements(WidgetTester tester) => List<String>.from(_erreursRendu);

/// Vrai si la ligne désigne un débordement du COMPOSANT A6.
///
/// Reconnaissance par NOM DE WIDGET uniquement : jamais par numéro de ligne.
/// Une erreur dont le widget fautif appartient au composant A6 est donc
/// reconnue comme telle quel que soit son emplacement dans le fichier de
/// production (un simple décalage de lignes ne peut pas la reclasser).
bool _concerneBlocA6(String ligne) =>
    ligne.contains('BadgeExAequo') ||
    ligne.contains('LigneArriveeExAequo') ||
    ligne.contains('arrivee_officielle_groupes_widget');

/// Vrai si la ligne désigne un débordement PRÉEXISTANT, hors A6.
///
/// Localisations mesurées sur le VRAI écran — SIX emplacements :
///   • `:119:28`  — `Row` du titre de l'`AppBar` (60 px) ;
///   • `:1515:18` — `Row` d'en-tête de carte (icône de statut), visible avec
///                  le texte ×2 (A6-E4) ;
///   • `:1661:25` — `Row` « Mise + badge type de pari », en-tête de carte ;
///   • `:1859:30` — `Row` du bloc gain (icône + montant), visible à 320 dp ;
///   • `:2454:14` — `Row` d'une pastille de statut, visible à 320 dp ;
///   • `:2597:14` — `Row` du badge « Confiance IA », visible à 320 dp.
///
/// Aucun de ces widgets n'appartient au composant A6
/// (`arrivee_officielle_groupes_widget.dart`). Ils sont signalés, jamais
/// absorbés. Le classement est protégé dans les deux sens :
///   • un débordement du fichier de production n'est retenu comme
///     « préexistant » que s'il ne désigne AUCUN widget du composant A6
///     (voir `_estPreexistant`, contrôle par nom) ;
///   • un débordement d'origine inconnue n'est ni « A6 » ni « préexistant » :
///     il tombe dans « autres » et fait ÉCHOUER le test.
const Set<String> _lignesPreexistantes = <String>{
  // ★ LOT A-0 puis LOT B-2 bis — décalage de numéros de ligne uniquement.
  //   Le Lot A-0 avait déjà décalé ces 6 widgets (119→120, 1515→1538, …).
  //   Le Lot B-2 bis ajoute 27 lignes dans `mes_paris_screen.dart` (5 blocs :
  //   2 lecture de `arriveeGroupes`/`arriveeDefinitive`, 2 transmissions
  //   `enregistrerResultatPari` étendues, 1 commentaire de règle). Les 6
  //   widgets préexistants n'ont PAS bougé : même `Row`, même rôle, même
  //   nombre de débordements. Seuls leurs numéros de ligne ont glissé.
  //   Correspondance vérifiée PAR COMPARAISON DU CONTENU des lignes
  //   (`git show HEAD:` vs fichier courant), et non par addition d'un
  //   décalage supposé : le site `120` est resté à 120 (offset 0), les cinq
  //   autres ont pris +27. Aucune hypothèse uniforme n'a été retenue.
  'mes_paris_screen.dart:120:',   // A-0: ex-119, inchangé — `title: const Row` de l'AppBar
  'mes_paris_screen.dart:1565:',  // B-2 bis: ex-1538 — `child: Row(children: [`
  'mes_paris_screen.dart:1711:',  // B-2 bis: ex-1684 — `Row` « Mise + badge type »
  'mes_paris_screen.dart:1909:',  // B-2 bis: ex-1882 — garde `miseEngagee`/`_isGagnant`
  'mes_paris_screen.dart:2504:',  // B-2 bis: ex-2477 — `],` du bloc « retour … € »
  'mes_paris_screen.dart:2647:',  // B-2 bis: ex-2620 — `),` du bloc « favoris »
};

/// Vrai si la ligne tombe sur une localisation PRÉEXISTANTE connue.
bool _surLignePreexistante(String ligne) => _lignesPreexistantes.any(ligne.contains);

/// Vrai si la ligne peut être classée « préexistante », c'est-à-dire si elle
/// tombe sur une localisation connue ET ne désigne AUCUN widget du composant
/// A6.
///
/// GARDE-FOU : le numéro de ligne seul ne suffit jamais à blanchir une erreur.
/// Si le composant A6 est déplacé (ajout de lignes en tête de
/// `mes_paris_screen.dart`), un débordement A6 pourrait tomber sur un numéro
/// préexistant ; le contrôle par nom le rejette alors du classement
/// « préexistant » et le test échoue. Sans ce garde-fou, un débordement A6
/// serait silencieusement excusé.
bool _estPreexistant(String ligne) =>
    _surLignePreexistante(ligne) && !_concerneBlocA6(ligne);

/// Vérification OBLIGATOIRE des débordements d'un scénario.
///
/// Aucune erreur de rendu n'est tolérée en silence :
///   • `_concerneBlocA6` → échec (le composant A6 ne doit jamais déborder) ;
///   • toute erreur ni « A6 » ni « préexistante » → échec (origine inconnue).
/// Seules les SIX localisations préexistantes de `mes_paris_screen.dart`,
/// antérieures à A6 et hors de son composant, sont rapportées sans échec.
void _verifierDebordements(String scenario, List<String> excs) {
  final a6 = excs.where(_concerneBlocA6).toList();
  final autres = excs
      .where((e) => !_concerneBlocA6(e) && !_estPreexistant(e))
      .toList();
  if (a6.isNotEmpty || autres.isNotEmpty) {
    fail('$scenario : débordement(s) non autorisé(s) — '
        'A6=${a6.length} origineInconnue=${autres.length}\n'
        '${a6.map((e) => '  [A6] $e').join('\n')}'
        '${autres.map((e) => '  [inconnu] $e').join('\n')}');
  }
}

/// Sérialise les débordements d'un scénario en un compte rendu lisible.
///
/// Les localisations sont extraites et IMPRIMÉES pour les trois catégories :
/// rien n'est tu. Un débordement « autre » (non attribué) est signalé
/// explicitement, jamais absorbé.
String _rapport(List<String> excs) {
  String locs(Iterable<String> l) {
    final out = <String>{};
    for (final e in l) {
      for (final m in RegExp(r'lib/[a-zA-Z0-9_/]+\.dart:(\d+):(\d+)')
          .allMatches(e)) {
        out.add(m.group(0)!.split('/').last);
      }
    }
    return out.isEmpty ? '(localisation non fournie)' : out.join(', ');
  }

  final a6 = excs.where(_concerneBlocA6).toList();
  final avant = excs.where(_estPreexistant).toList();
  final autres = excs
      .where((e) => !_concerneBlocA6(e) && !_estPreexistant(e))
      .toList();
  return 'A6=${a6.length} préexistants=${avant.length} '
      'autres=${autres.length}'
      '${a6.isEmpty ? '' : ' | A6→${locs(a6)}'}'
      '${avant.isEmpty ? '' : ' | préexistants→${locs(avant)}'}'
      '${autres.isEmpty ? '' : ' | autres→${locs(autres)}'}';
}

/// Monte le VÉRITABLE `MesPariScreen` sur l'onglet Suivi, exécute [corps],
/// puis DÉMONTE (ce qui annule les `Timer.periodic` de l'écran et de la
/// carte). Aucun `runAsync` : montage `pumpWidget` + `pump`, comme `v47`.
///
/// GARANTIE DE RESTAURATION : la capture des `FlutterErrorDetails` et le
/// démontage sont enveloppés dans un `try/finally`. `FlutterError.onError`
/// est donc rendu à son état d'origine MÊME SI `pumpWidget`, `pump` ou
/// [corps] lève une exception (assertion en échec, `fail()` explicite,
/// exception de rendu). Sans ce `finally`, un échec laissait le handler de
/// test actif et provoquait le second message trompeur
/// « A test overrode FlutterError.onError… », qui remplaçait la défaillance
/// réelle.
Future<T> _pendantEcran<T>(
  WidgetTester tester, {
  required double largeurDp,
  required double hauteurDp,
  double echelleTexte = 1.0,
  required Future<T> Function() corps,
}) async {
  // ⚠️ `setSurfaceSize` lève `'inTest': is not true` hors widget test
  //     global ; on passe par `tester.view`, avec remise à zéro garantie.
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(largeurDp, hauteurDp);
  addTearDown(tester.view.reset);

  // Collecte à la source des `FlutterErrorDetails` COMPLETS (message +
  // widget fautif). Rien n'est absorbé : la liste est rendue au test.
  //
  // ⚠️ `FlutterError.onError` est RESTAURÉ dès la fin de la fenêtre de
  //    rendu, EXACTEMENT comme `monter()` de
  //    `v47_g_bulle_matinale_test.dart`. Le laisser actif pendant les
  //    `expect()` provoque :
  //    « A test overrode FlutterError.onError but either failed to return it
  //      to its original state… » (mesuré sur A6-E2), qui masque l'échec
  //    réel. Les erreurs de rendu ne surviennent qu'au montage et au premier
  //    pump : la fenêtre d'interception couvre donc tout le rendu utile.
  _erreursRendu = <String>[];
  final ancienOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    // `details.toString()` contient la localisation du widget fautif
    // (« Row Row:file:///...mes_paris_screen.dart:119:28 »), ce que
    // `exceptionAsString()` seul ne fournit pas.
    _erreursRendu.add(details.toString().replaceAll('\n', ' '));
  };

  try {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => PmuProvider()),
          ChangeNotifierProvider<NavigationNotifier>(
              create: (_) => NavigationNotifier()),
          ChangeNotifierProvider.value(value: DataRefreshService.instance),
          ChangeNotifierProvider.value(value: AlertService.instance),
          ChangeNotifierProvider.value(value: IaPersonalityService.instance),
          ChangeNotifierProvider.value(value: IaUserPrefsService.instance),
          ChangeNotifierProvider.value(value: IaBadgesService.instance),
          ChangeNotifierProvider.value(value: IaMemoryService.instance),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(largeurDp, hauteurDp),
              textScaler: TextScaler.linear(echelleTexte),
            ),
            // initialTab: 1 = onglet « Suivi », celui qui porte les cartes.
            child: const MesPariScreen(initialTab: 1),
          ),
        ),
      ),
    );
    await tester.pump();
  } finally {
    // Restauration AVANT toute assertion, et garantie même en cas d'échec.
    FlutterError.onError = ancienOnError;
  }

  try {
    final resultat = await corps();
    return resultat;
  } finally {
    // Démontage garanti : les `Timer.periodic` de l'écran et de la carte
    // sont annulés même si [corps] a échoué, ce qui évite de laisser des
    // timers actifs pour le scénario suivant.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }
}

/// Texte du bloc « Arrivée officielle : … » rendu par l'écran.
///
/// Aucune exception n'est absorbée : on ne lit que le `Text` effectivement
/// construit. `null` si le bloc n'est pas rendu — ce qui fait échouer
/// l'assertion appelante plutôt que de la contourner.
String? _texteHistorique(WidgetTester tester) {
  for (final t in tester.widgetList<Text>(find.byType(Text))) {
    final d = t.data;
    if (d != null && d.startsWith('Arrivée officielle :') && d.contains('N°')) {
      return d;
    }
  }
  return null;
}

// ─────────────────────────────── Tests ────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ⚠️ AUCUN `setUp()` enregistré ici : voir la contrainte de harnais en
  //    tête de fichier. Toute la préparation est dans les corps de test.

  // ═══════════════════════════════════════════════════════════════════════
  //  A6-E1 — ARRIVÉE SANS EX ÆQUO : texte historique, aucun badge, aucun rang
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('A6-E1 — sans ex æquo : texte historique, ni badge ni rang',
      (tester) async {
    await _preparer(numCourse: 1);

    final res = await _pendantEcran<(String?, List<String>)>(tester,
        largeurDp: 400, hauteurDp: 900, corps: () async {
      // ── TÉMOINS : c'est bien le VRAI écran, sur le bon onglet ──────────
      expect(find.text('Mes Paris & Alertes'), findsWidgets,
          reason: 'TÉMOIN : le VÉRITABLE MesPariScreen est monté');
      expect(find.text('Suivi'), findsWidgets,
          reason: 'TÉMOIN : l\'onglet Suivi est présent');
      expect(find.text('CHEVAL_7'), findsWidgets,
          reason: 'TÉMOIN : la carte de la course suivie est rendue');

      // ── Texte historique attendu tel quel ─────────────────────────────
      expect(find.textContaining('Arrivée officielle :'), findsWidgets,
          reason: 'A6 : sans ex æquo, l\'écran conserve son texte '
              'historique « Arrivée officielle : N°7 - N°4 - … »');

      // ── Aucun rendu ex æquo ───────────────────────────────────────────
      expect(find.byType(BadgeExAequo), findsNothing,
          reason: 'A6 : le badge n\'apparaît QUE sur un ex æquo réel');
      expect(find.byType(LigneArriveeExAequo), findsNothing,
          reason: 'A6 : `LigneArriveeExAequo` n\'est instancié que sur ex æquo');
      expect(find.text('Ex æquo'), findsNothing);
      for (final rang in ['1er', '2e', '3e', '4e', '5e']) {
        expect(find.text(rang), findsNothing,
            reason: 'A6 : aucun rang ne doit s\'afficher sur une arrivée '
                'plate');
      }
      return (_texteHistorique(tester), _debordements(tester));
    });

    final (texte, excs) = res;
    debugPrint('A6-E1 texte historique = "$texte"');
    debugPrint('A6-E1 débordements : ${_rapport(excs)}');

    expect(texte, isNotNull,
        reason: 'A6-E1 : le bloc d\'arrivée doit être rendu');
    expect(texte, contains('N°7'),
        reason: 'A6-E1 : le texte historique porte l\'arrivée officielle');
    expect(texte, isNot(contains('·')),
        reason: 'A6-E1 : pas de séparateur de groupes sur une arrivée plate');
    // Échoue sur A6 ET sur toute erreur d\'origine inconnue.
    _verifierDebordements('A6-E1', excs);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6-E2 — ARRIVÉE AVEC EX ÆQUO : badge gris + numéros dorés + rangs
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('A6-E2 — ex æquo : badge gris, numéros dorés, rangs officiels',
      (tester) async {
    await _preparer(numCourse: 2);

    final excs = await _pendantEcran<List<String>>(tester,
        largeurDp: 400, hauteurDp: 900, corps: () async {
      // ── Badge gris : UN PAR CHEVAL EX ÆQUO (spécification B-2 bis) ─────
      // [[7],[4],[11,9],[6]] compte DEUX ex æquo → deux encadrés, un sous
      // chacun d'eux, et aucun sous N°7 / N°4 / N°6.
      expect(find.byType(BadgeExAequo), findsNWidgets(2),
          reason: 'A6 : un encadré sous CHACUN des deux ex æquo');
      final badge = tester.widget<Text>(find.descendant(
          of: find.byType(BadgeExAequo).first, matching: find.byType(Text)));
      expect(badge.data, 'Ex æquo');
      expect(badge.style!.fontSize, 10.0,
          reason: 'A6 : taille du badge INCHANGÉE (10)');
      expect(badge.style!.color, kCouleurBadgeExAequo,
          reason: 'A6 : le badge est bien GRIS (kCouleurBadgeExAequo)');

      // ── Rendu groupé utilisé ───────────────────────────────────────────
      expect(find.byType(LigneArriveeExAequo), findsOneWidget,
          reason: 'A6 : le rendu groupé est utilisé');

      for (final n in [7, 4, 11, 9, 6]) {
        expect(find.text('N°$n'), findsWidgets,
            reason: 'A6 : le numéro N°$n est affiché');
      }

      // ── Numéros dorés, taille conservée ────────────────────────────────
      for (final n in [11, 9]) {
        final t = tester.widget<Text>(find.text('N°$n').first);
        expect(t.style!.color, kCouleurExAequo,
            reason: 'A6 : N°$n est un ex æquo → doré (kCouleurExAequo)');
        expect(t.style!.fontSize, 12.0,
            reason: 'A6 : taille du numéro INCHANGÉE (12)');
        expect(t.style!.fontWeight, FontWeight.bold,
            reason: 'A6 : les ex æquo restent en gras');
      }

      // ── Rangs officiels : positions sautées respectées ────────────────
      // ⚠️ RÈGLE DE PRODUCTION (mesurée, `_buildNumero` l.229-234) :
      //    le rang n'est rendu QUE sous les chevaux EX ÆQUO
      //    (`if (exAequo)` où `exAequo = groupe.length > 1`). Les groupes
      //    simples ([7], [4], [6]) n'affichent donc AUCUN rang — c'est le
      //    comportement documenté, pas une omission.
      //    `rangsOfficiels([[7],[4],[11,9],[6]])` = [1, 2, 3, 5] : le groupe
      //    [11,9] porte le rang 3, et le rang 5 existe dans le calcul mais
      //    n'est PAS affiché puisque [6] est seul.
      expect(find.text('3e'), findsNWidgets(2),
          reason: 'A6 : les DEUX chevaux du groupe [11,9] portent le rang 3e');
      // ⚠️ SPÉCIFICATION RÉVISÉE (lot B-2 bis) : dès qu'un ex æquo existe,
      //    CHAQUE cheval porte son rang officiel. N°7 (rang 1), N°4 (rang 2)
      //    et N°6 (rang 5) affichent donc leur rang — c'est l'exigence
      //    validée, pas une régression.
      expect(find.text('1er'), findsOneWidget,
          reason: 'B-2 bis : N°7, seul au rang 1, porte « 1er »');
      expect(find.text('2e'), findsOneWidget,
          reason: 'B-2 bis : N°4, seul au rang 2, porte « 2e »');
      expect(find.text('5e'), findsOneWidget,
          reason: 'B-2 bis : N°6, seul au rang 5, porte « 5e » (position sautée)');
      expect(find.text('4e'), findsNothing,
          reason: 'A6 : le rang 4 n\'existe pas — [[7],[4],[11,9],[6]] saute '
              'de 3 à 5, la position 4 est consommée par le second ex æquo');

      final rang = tester.widget<Text>(find.text('3e').first);
      expect(rang.style!.fontSize, 9.0,
          reason: 'A6 : rang = fontSize - 3 = 9, taille conservée');

      return _debordements(tester);
    });

    debugPrint('A6-E2 débordements : ${_rapport(excs)}');
    // Échoue sur A6 ET sur toute erreur d\'origine inconnue.
    _verifierDebordements('A6-E2', excs);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6-E3 — 320 dp : aucun débordement DU COMPOSANT A6
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('A6-E3 — 320 dp avec ex æquo : le composant A6 ne déborde pas',
      (tester) async {
    await _preparer(numCourse: 3);

    final excs = await _pendantEcran<List<String>>(tester,
        largeurDp: 320, hauteurDp: 900, corps: () async {
      // [[7],[4],[11,9,12],[6]] compte TROIS ex æquo → trois encadrés.
      expect(find.byType(BadgeExAequo), findsNWidgets(3),
          reason: 'B-2 bis : un encadré sous chacun des trois ex æquo');
      expect(find.text('Ex æquo'), findsNWidgets(3),
          reason: 'A6 : les badges ne sont pas rognés à 320 dp');
      expect(find.byType(LigneArriveeExAequo), findsOneWidget);
      return _debordements(tester);
    });

    debugPrint('A6-E3 320dp débordements : ${_rapport(excs)}');
    // Échoue sur A6 ET sur toute erreur d\'origine inconnue. Le message de
    // _verifierDebordements rappelle la règle : à 320 dp c'est le `Wrap` qui
    // replie, jamais la police qui diminue.
    _verifierDebordements('A6-E3', excs);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6-E4 — 320 dp AVEC texte ×2 : aucun débordement DU COMPOSANT A6
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('A6-E4 — 320 dp + texte ×2 : le composant A6 ne déborde pas',
      (tester) async {
    await _preparer(numCourse: 2);

    final excs = await _pendantEcran<List<String>>(tester,
        largeurDp: 320,
        // ⚠️ HAUTEUR MESURÉE, pas arbitraire : à 320×900 AVEC texte ×2, la
        //    fenêtre des cartes se réduit à une hauteur nulle et le
        //    `ListView` paresseux ne construit AUCUN enfant. Constat mesuré :
        //    `carte=0 badge=0 ligne=0 titre=0`. Ce n'est pas un défaut A6 mais
        //    une absence de rendu : il faut de la hauteur pour que la carte
        //    entre dans la fenêtre. À 1600 dp : `carte=1 badge=1 ligne=1`.
        //    Le débordement horizontal, lui, reste mesuré à largeur 320.
        hauteurDp: 1600,
        echelleTexte: 2.0,
        corps: () async {
      // [[7],[4],[11,9],[6]] : DEUX ex æquo (spécification B-2 bis).
      expect(find.byType(BadgeExAequo), findsNWidgets(2));
      expect(find.text('Ex æquo'), findsNWidgets(2),
          reason: 'A6 : les badges restent entiers avec texte agrandi');
      expect(find.byType(LigneArriveeExAequo), findsOneWidget);

      // Les tailles DÉCLARÉES ne changent pas avec l'échelle de texte :
      // le grossissement est appliqué par le moteur (accessibilité), pas
      // par une valeur différente dans le style.
      final numero = tester.widget<Text>(find.text('N°7').first);
      expect(numero.style!.fontSize, 12.0,
          reason: 'A6 : la taille déclarée reste 12 avec texte ×2 — aucune '
              'réduction pour « faire tenir »');
      return _debordements(tester);
    });

    debugPrint('A6-E4 320dp ×2 débordements : ${_rapport(excs)}');
    // Échoue sur A6 ET sur toute erreur d\'origine inconnue. Rappel de la
    // règle : avec texte ×2 c\'est la mise en page qui s\'adapte.
    _verifierDebordements('A6-E4', excs);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6-E5 — TAILLES CONSERVÉES, aucun contournement
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets(
      'A6-E5 — tailles conservées : 12 / 10 / 12 / 9, sans contournement',
      (tester) async {
    await _preparer(numCourse: 2);

    final excs = await _pendantEcran<List<String>>(tester,
        largeurDp: 320, hauteurDp: 900, corps: () async {
      // Titre « Arrivée officielle : » → 12
      final titre = tester.widget<Text>(find.text('Arrivée officielle :'));
      expect(titre.style!.fontSize, 12.0,
          reason: 'A6 : titre à 12 — taille d\'origine conservée');

      // Badge « Ex æquo » → 10 (le premier ; il y en a un par ex æquo)
      final badge = tester.widget<Text>(find.descendant(
          of: find.byType(BadgeExAequo).first, matching: find.byType(Text)));
      expect(badge.style!.fontSize, 10.0);

      // Numéros → 12
      final numero = tester.widget<Text>(find.text('N°7').first);
      expect(numero.style!.fontSize, 12.0);

      // Rang → 9
      final rang = tester.widget<Text>(find.text('3e').first);
      expect(rang.style!.fontSize, 9.0);

      // Aucune réduction déguisée DANS le composant A6.
      expect(
          find.descendant(
              of: find.byType(LigneArriveeExAequo),
              matching: find.byType(FittedBox)),
          findsNothing,
          reason: 'A6 : aucune réduction déguisée par FittedBox');
      expect(
          find.descendant(
              of: find.byType(BadgeExAequo).first,
              matching: find.byType(FittedBox)),
          findsNothing);

      for (final el in tester.widgetList<Text>(find.descendant(
          of: find.byType(LigneArriveeExAequo), matching: find.byType(Text)))) {
        expect(el.overflow, isNot(TextOverflow.ellipsis),
            reason: 'A6 : aucun « … » sur « ${el.data} » — le texte doit '
                'passer à la ligne, jamais être tronqué');
        expect(el.softWrap, isNot(false),
            reason: 'A6 : le retour à la ligne automatique est autorisé');
      }
      return _debordements(tester);
    });

    debugPrint('A6-E5 débordements : ${_rapport(excs)}');
    // Échoue sur A6 ET sur toute erreur d\'origine inconnue.
    _verifierDebordements('A6-E5', excs);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A6-E6 — Présentation COMPACTE (une ligne) puis repli à 320 dp
  // ═══════════════════════════════════════════════════════════════════════
  testWidgets('A6-E6 — présentation compacte à 600 dp, repli à 320 dp',
      (tester) async {
    Future<double> hauteurA(double largeur) async {
      await _preparer(numCourse: 3);
      return _pendantEcran<double>(tester,
          largeurDp: largeur, hauteurDp: 900, corps: () async {
        final h = tester.getSize(find.byType(LigneArriveeExAequo)).height;
        // Échoue sur A6 ET sur toute erreur d\'origine inconnue.
        _verifierDebordements('A6-E6', _debordements(tester));
        return h;
      });
    }

    // Largeurs MESURÉES : à 600 dp le bloc tient sur UNE ligne (32 dp),
    // à 400 dp comme à 320 dp il occupe DEUX lignes (68 dp). La transition
    // se situe donc entre 600 et 400 dp — c'est la preuve que l'adaptation
    // se fait par la mise en page (repli), pas par une réduction de police.
    final hLarge = await hauteurA(600);
    final hEtroit = await hauteurA(320);

    debugPrint('A6-E6 hauteur 600dp=$hLarge 320dp=$hEtroit '
        'gain=${(hEtroit - hLarge).toStringAsFixed(1)}');

    // ⚠️ SEUILS RELATIFS, pas un nombre magique. Le lot B-2 bis affiche
    //    désormais le rang sous CHAQUE cheval ET un encadré sous chaque
    //    ex æquo : la hauteur d'une ligne a donc légitimement augmenté
    //    (mesurée : 90 dp à 600 dp au lieu de 32 dp). Le seuil de 40 dp, qui
    //    ne valait que pour l'ancienne présentation, est remplacé par la
    //    comparaison « une ligne < deux lignes », qui n'encode aucune taille
    //    et restera vraie si les styles évoluent.
    //
    //    Présentation COMPACTE = une seule ligne : sa hauteur doit rester
    //    INFÉRIEURE à celle du rendu replié à 320 dp. C'est exactement ce que
    //    la spécification demande (repli par la mise en page, jamais par une
    //    réduction de police).
    expect(hLarge, lessThan(hEtroit),
        reason: 'A6 : à 600 dp le bloc tient sur UNE ligne ($hLarge), à '
            '320 dp il se replie ($hEtroit)');

    // ── Repli à 320 dp : la hauteur AUGMENTE ───────────────────────────
    expect(hEtroit, greaterThan(hLarge),
        reason: 'A6 : à 320 dp la ligne se replie et sa HAUTEUR augmente. '
            'C\'est la preuve mesurable que l\'adaptation se fait par la mise '
            'en page et non par une réduction de caractères.');
  });
}
