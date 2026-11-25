// ═══════════════════════════════════════════════════════════════════════════
//  R1 — MODE LECTURE SEULE : LA CONSULTATION NE DÉCLENCHE RIEN
//
//  OBJET DU CORRECTIF R1 (3 fichiers de production, aucun autre) :
//    • lib/widgets/arrivee_reelle_widget.dart
//        + autoriserRecuperation (défaut true)
//        + garde en TÊTE de _fetchSiNecessaire()
//    • lib/screens/races_screen.dart
//        + autoriserRecuperation:false sur le widget d'arrivée
//        + lectureSeule:true vers CourseDetailScreen
//    • lib/screens/course_detail_screen.dart
//        + lectureSeule (défaut false)
//        + autoriserRecuperation: !lectureSeule sur le widget d'arrivée
//
//  NATURE DES TESTS — deux familles DISTINCTES, jamais confondues :
//
//    [COMPORTEMENTAL] monte le widget réel et observe un effet mesuré
//                     (nombre d'URL réellement demandées, texte réellement
//                     rendu). Le réseau est substitué par `http.runWithClient`
//                     + `MockClient`, mécanisme déjà employé par 5 fichiers de
//                     tests validés du dépôt (v10_a6s, v31b, v33, v34, v35,
//                     l1_capture_officielle), et rendu possible par
//                     http 1.5.0 → `Client() => zoneClient ?? createClient()`
//                     (client.dart:42) utilisé par `http.get`
//                     (ia_memory_service.dart:1399-1402).
//
//    [STRUCTUREL]     lit le TEXTE des fichiers de production et vérifie la
//                     présence/absence d'un identifiant. Ne prouve AUCUNE
//                     exécution : c'est un contrôle de câblage. Ces tests ne
//                     sont pas des tests d'intégration et ne sont pas
//                     présentés comme tels.
//
//  ISOLATION — sans toucher aux services :
//    `IaMemoryService._arriveeCache` est un cache RAM GLOBAL de singleton et
//    `recharger()` ne le vide pas (ia_memory_service.dart:1664-1680 ne touche
//    pas `_arriveeCache`). Chaque test utilise donc une **courseKey unique**
//    (numéro de course incrémental) : aucune clé n'est réutilisée d'un test à
//    l'autre, donc aucune valeur de `_arriveeCache` ne peut être héritée.
//    Aucun `resetStatic`, aucun hook de test, aucun service modifié.
//
//  COUVERTURE DES EXIGENCES A → G : voir la table de correspondance en fin de
//  fichier. Aucun commit, aucun push.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/screens/course_detail_screen.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/widgets/arrivee_reelle_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  1. STORE MÉMOIRE (suffisant : `SharedPreferences.getInstance()`)
// ═══════════════════════════════════════════════════════════════════════════

class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> valeurs = <String, Object>{};

  @override
  Future<bool> clear() async {
    valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    valeurs[key] = value;
    return true;
  }
}

late _Store _store;

void _installerStore() {
  _store = _Store();
  SharedPreferencesStorePlatform.instance = _store;
  SharedPreferences.resetStatic();
}

// ═══════════════════════════════════════════════════════════════════════════
//  2. CLÉS DE COURSE UNIQUES — l'isolation exigée
// ═══════════════════════════════════════════════════════════════════════════

/// Compteur monotone : deux tests ne partagent JAMAIS une courseKey, donc
/// `_arriveeCache` (cache RAM global du singleton) ne peut rien transmettre.
int _compteurCourse = 0;

/// Date ISO du jour — format des `courseKey` lus par `_dateReelleDeLaCourse`.
String get _dateIso {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

/// Date `ddMMyyyy` — format de `ZtCourse.dateStr`.
String get _dateDdMmYyyy {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

/// courseKey neuve, au format reconnu par `fetchArriveeDirecte`
/// (`^R(\d+)C(\d+)_` — ia_memory_service.dart:1383).
String _nouvelleCourseKey() {
  _compteurCourse++;
  return 'R1C$_compteurCourse' '_$_dateIso';
}

/// Heure de départ 3 h dans le passé : au-delà de −90 min, donc `isTerminee`
/// vaut `true` partout (races_screen.dart:507, course_detail_screen.dart:562).
DateTime get _heurePassee => DateTime.now().subtract(const Duration(hours: 3));

String get _heurePasseeStr {
  final d = _heurePassee;
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

ZtCourse _courseCourue() => ZtCourse(
      numCourse: 1,
      anchor: 'c1',
      nom: 'PRIX R1',
      heure: _heurePasseeStr,
      distance: '2700',
      prix: '50000',
      type: 'Attelé',
      piste: 'Grande piste',
      categorie: 'Course D',
      isQuinte: false,
      pronosticZt: const <int>[],
      partants: <ZtPartant>[],
      dateStr: _dateDdMmYyyy,
    );

ZtReunion _reunionDe(ZtCourse c) => ZtReunion(
      code: 'R1',
      lieu: 'VINCENNES',
      discipline: 'Trot',
      dateStr: _dateDdMmYyyy,
      courses: <ZtCourse>[c],
    );

// ═══════════════════════════════════════════════════════════════════════════
//  3. RÉSEAU SIMULÉ + COMPTEUR
// ═══════════════════════════════════════════════════════════════════════════

/// Toutes les URL demandées pendant un test.
final List<Uri> _urls = <Uri>[];

/// Nombre d'appels à `/rapports-definitifs` : c'est LE point d'entrée réseau
/// de `fetchArriveeDirecte` (ia_memory_service.dart:1399-1402), donc le seul
/// compteur pertinent pour R1.
int get _nbRapports => _urls.where((u) => u.path.contains('rapports-definitifs')).length;

/// Corps JSON de `/rapports-definitifs` — Tiercé ORDRE → arrivée complète
/// (branche `isOrdre`, ia_memory_service.dart:1428-1445).
String _jsonRapports(List<int> arrivee) => jsonEncode(<dynamic>[
      <String, dynamic>{
        'typePari': 'E_TIERCE_ORDRE',
        'rapports': <dynamic>[
          <String, dynamic>{'combinaison': arrivee.join('-')},
        ],
      },
    ]);

/// Exécute [action] sous un client HTTP simulé qui répond [arrivee].
Future<void> _sousReseauSimule(
  Future<void> Function() action, {
  List<int> arrivee = const <int>[5, 3, 1],
}) {
  final client = MockClient((request) async {
    _urls.add(request.url);
    if (request.url.path.contains('rapports-definitifs')) {
      return http.Response(_jsonRapports(arrivee), 200,
          headers: const <String, String>{'content-type': 'application/json'});
    }
    // Tout autre appel (programme, participants) : réponse neutre. R1 ne
    // l'utilise pas, mais on ne laisse rien partir vers le vrai réseau.
    return http.Response('{}', 200,
        headers: const <String, String>{'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. MONTAGE « ISOLÉ » DU WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Monte `ArriveReelleWidget` seul, dans un `MaterialApp` minimal.
/// [autoriser] == null → le paramètre est OMIS : c'est le DÉFAUT du
/// constructeur qui s'applique, exactement comme pour les autres appelants.
Widget _monter({
  required String courseKey,
  required bool isTerminee,
  bool? autoriser,
  bool compact = true,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ArriveReelleWidget(
            courseKey: courseKey,
            isTerminee: isTerminee,
            heureDepart: _heurePassee,
            selectionIA: const <String>['1', '3', '5'],
            compact: compact,
            autoriserRecuperation: autoriser ?? true,
          ),
        ),
      ),
    );

/// Variante qui OMET réellement `autoriserRecuperation` (défaut du
/// constructeur). Distincte de `_monter(autoriser: true)` qui l'écrit.
Widget _monterSansParametre({
  required String courseKey,
  required bool isTerminee,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ArriveReelleWidget(
            courseKey: courseKey,
            isTerminee: isTerminee,
            heureDepart: _heurePassee,
            selectionIA: const <String>['1', '3', '5'],
          ),
        ),
      ),
    );

/// Laisse s'écouler les microtâches du `.then()` non attendu de
/// `_fetchSiNecessaire` (arrivee_reelle_widget.dart:95-97).
///
/// `pumpAndSettle` est PROSCRIT : en lecture seule l'arrivée reste inconnue,
/// donc `CircularProgressIndicator` (arrivee_reelle_widget.dart:257-265)
/// tourne indéfiniment et `pumpAndSettle` ne rendrait jamais la main.
Future<void> _laisserResoudre(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  5. LECTURE DE SOURCE — pour les tests STRUCTURELS uniquement
// ═══════════════════════════════════════════════════════════════════════════

/// Les tests s'exécutent depuis la racine du projet.
String _lire(String chemin) {
  final f = File(chemin);
  expect(f.existsSync(), isTrue,
      reason: 'fichier de production introuvable : $chemin '
          '(les tests structurels supposent la racine du projet comme cwd)');
  return f.readAsStringSync();
}

const String _fWidget = 'lib/widgets/arrivee_reelle_widget.dart';
const String _fRaces = 'lib/screens/races_screen.dart';
const String _fDetail = 'lib/screens/course_detail_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  TESTS
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _urls.clear();
    _installerStore();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  R1-0 [CONTRAT] — les deux défauts, lus SUR LES OBJETS réels
  // ═════════════════════════════════════════════════════════════════════════
  test('R1-0 [contrat] autoriserRecuperation défaut=true, lectureSeule défaut=false',
      () {
    final arrivee = ArriveReelleWidget(
      courseKey: _nouvelleCourseKey(),
      isTerminee: true,
    );
    expect(arrivee.autoriserRecuperation, isTrue,
        reason: 'le défaut doit préserver le comportement de TOUS les '
            'appelants existants du widget');

    final course = _courseCourue();
    final detail = CourseDetailScreen(course: course, reunion: _reunionDe(course));
    expect(detail.lectureSeule, isFalse,
        reason: 'les appelants qui ne passent pas le paramètre '
            '(best_bet, conseils, home, mes_paris, programme, alertes) '
            'doivent garder le comportement historique');

    debugPrint('R1-0 autoriserRecuperation=${arrivee.autoriserRecuperation} '
        'lectureSeule=${detail.lectureSeule}');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A — autoriserRecuperation:false → AUCUN appel HTTP
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('R1-A [comportemental] false → zéro appel /rapports-definitifs',
      (tester) async {
    final key = _nouvelleCourseKey();

    await _sousReseauSimule(() async {
      await tester.pumpWidget(
          _monter(courseKey: key, isTerminee: true, autoriser: false));
      await _laisserResoudre(tester);
    });

    debugPrint('R1-A key=$key urls=${_urls.length} rapports=$_nbRapports');
    expect(_nbRapports, 0,
        reason: 'la garde doit intercepter AVANT tout appel réseau');
    expect(_urls, isEmpty, reason: 'aucune requête HTTP, quelle qu\'elle soit');

    // Effet observable : rien n'a été mémorisé pour cette course.
    expect(IaMemoryService.instance.arriveeConnue(key), isNull,
        reason: 'aucune arrivée ne doit être connue après une consultation '
            'en lecture seule');

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B — autoriserRecuperation:true → comportement historique préservé
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('R1-B [comportemental] true → un appel, comportement historique',
      (tester) async {
    final key = _nouvelleCourseKey();

    await _sousReseauSimule(() async {
      await tester.pumpWidget(
          _monter(courseKey: key, isTerminee: true, autoriser: true));
      await _laisserResoudre(tester);
    });

    debugPrint('R1-B key=$key urls=${_urls.length} rapports=$_nbRapports');
    expect(_nbRapports, 1,
        reason: 'TÉMOIN DE NON-VACUITÉ : sans lui, R1-A ne prouverait que '
            'l\'absence d\'appel dans un montage inerte, pas l\'effet de la '
            'garde');
    expect(_urls, hasLength(1), reason: 'un seul endpoint sollicité');

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  F — paramètre OMIS → défaut du constructeur → comportement historique
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('R1-F [comportemental] paramètre omis → défaut → appel émis',
      (tester) async {
    final key = _nouvelleCourseKey();

    await _sousReseauSimule(() async {
      await tester.pumpWidget(
          _monterSansParametre(courseKey: key, isTerminee: true));
      await _laisserResoudre(tester);
    });

    debugPrint('R1-F key=$key rapports=$_nbRapports');
    expect(_nbRapports, 1,
        reason: 'les 6 appelants qui n\'écrivent pas le paramètre doivent '
            'conserver exactement le comportement d\'avant R1');

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C — une arrivée DÉJÀ CONNUE reste affichée en lecture seule
  //
  //  Montage en deux temps, volontairement : on laisse d'abord la chaîne
  //  réelle mémoriser l'arrivée (autoriserRecuperation:true), puis on remonte
  //  le MÊME courseKey en lecture seule. On éprouve ainsi la seule exigence
  //  qui compte : afficher sans rien déclencher.
  //  LIMITE assumée : le 1er montage écrit dans l'archive des résultats
  //  (IaArchiveService, ia_memory_service.dart:2881-2896) faute de pronostic.
  //  Cette écriture est hors du périmètre R1 et n'est pas mesurée ici.
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('R1-C [comportemental] arrivée connue → toujours affichée, 0 appel',
      (tester) async {
    final key = _nouvelleCourseKey();

    await _sousReseauSimule(() async {
      // ── Temps 1 : la chaîne réelle mémorise l'arrivée ──────────────────
      await tester.pumpWidget(
          _monter(courseKey: key, isTerminee: true, autoriser: true));
      await _laisserResoudre(tester);

      final connue = IaMemoryService.instance.arriveeConnue(key);
      debugPrint('R1-C temps 1 key=$key rapports=$_nbRapports connue=$connue');
      expect(connue, isNotNull,
          reason: 'TÉMOIN : sans arrivée mémorisée, le temps 2 ne prouverait '
              'rien');
      expect(connue, equals(<int>[5, 3, 1]));

      // Le widget affiche l'arrivée : badges « N°X » (widget:337-340).
      expect(find.text('N°5'), findsWidgets);
      expect(find.text('N°3'), findsWidgets);
      expect(find.text('N°1'), findsWidgets);

      _urls.clear(); // on ne mesure plus que le temps 2

      // ── Temps 2 : même course, en LECTURE SEULE ────────────────────────
      await tester.pumpWidget(
          _monter(courseKey: key, isTerminee: true, autoriser: false));
      await _laisserResoudre(tester);

      debugPrint('R1-C temps 2 rapports=$_nbRapports');
      expect(_nbRapports, 0,
          reason: 'afficher une arrivée connue ne doit solliciter aucun réseau');
      expect(_urls, isEmpty);

      expect(find.text('N°5'), findsWidgets,
          reason: 'l\'arrivée déjà connue doit RESTER affichée en lecture '
              'seule');
      expect(find.text('N°3'), findsWidgets);
      expect(find.text('N°1'), findsWidgets);
      expect(find.text('En attente des résultats PMU...'), findsNothing,
          reason: 'une arrivée connue ne doit jamais céder la place au spinner');
    });

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  D — transitions du widget en mode lecture seule
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('R1-D1 [comportemental] false→true AVEC garde → aucun appel',
      (tester) async {
    final key = _nouvelleCourseKey();

    await _sousReseauSimule(() async {
      await tester.pumpWidget(
          _monter(courseKey: key, isTerminee: false, autoriser: false));
      await _laisserResoudre(tester);
      expect(_nbRapports, 0, reason: 'course à venir → rien, même sans garde');

      // Transition false→true : didUpdateWidget (widget:77-83) rappelle
      // _fetchSiNecessaire(), que la garde doit intercepter.
      await tester.pumpWidget(
          _monter(courseKey: key, isTerminee: true, autoriser: false));
      await _laisserResoudre(tester);
    });

    debugPrint('R1-D1 key=$key rapports=$_nbRapports');
    expect(_nbRapports, 0,
        reason: 'la garde doit couvrir initState ET didUpdateWidget');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('R1-D2 [comportemental] false→true SANS garde → exactement 1 appel',
      (tester) async {
    final key = _nouvelleCourseKey();

    await _sousReseauSimule(() async {
      await tester.pumpWidget(
          _monter(courseKey: key, isTerminee: false, autoriser: true));
      await _laisserResoudre(tester);
      expect(_nbRapports, 0, reason: 'course à venir → rien');

      await tester.pumpWidget(
          _monter(courseKey: key, isTerminee: true, autoriser: true));
      await _laisserResoudre(tester);
    });

    debugPrint('R1-D2 key=$key rapports=$_nbRapports');
    expect(_nbRapports, 1,
        reason: 'TÉMOIN : sans garde, la transition déclenche bien un appel — '
            'D1 n\'est donc pas confondue avec l\'absence de transition');

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E [STRUCTUREL] — propagation RacesScreen → CourseDetailScreen → widget
  //
  //  Contrôle de CÂBLAGE sur le texte des sources. Ne prouve pas une
  //  exécution : ce n'est pas un test d'intégration. Il établit que les trois
  //  maillons portent bien les identifiants attendus, aux bons endroits.
  // ═════════════════════════════════════════════════════════════════════════
  test('R1-E [structurel] propagation des 3 maillons', () {
    final races = _lire(_fRaces);
    final detail = _lire(_fDetail);
    final widget = _lire(_fWidget);

    // ── Maillon 1 : races_screen → widget d'arrivée ──────────────────────
    expect(races.contains('autoriserRecuperation: false'), isTrue,
        reason: 'le widget d\'arrivée du calendrier doit être en lecture seule');

    // ── Maillon 2 : races_screen → CourseDetailScreen ────────────────────
    expect(races.contains('lectureSeule: true'), isTrue,
        reason: 'la navigation calendrier → détail doit propager lectureSeule');

    // ── Maillon 3 : course_detail_screen transmet au widget ──────────────
    expect(detail.contains('autoriserRecuperation: !widget.lectureSeule'), isTrue,
        reason: 'le détail doit dériver autoriserRecuperation de lectureSeule');

    expect(detail.contains('this.lectureSeule = false'), isTrue,
        reason: 'lectureSeule doit avoir false pour défaut');

    // ── Le widget porte la garde, en tête de _fetchSiNecessaire ──────────
    expect(widget.contains('if (!widget.autoriserRecuperation) return;'), isTrue,
        reason: 'la garde doit exister');

    expect(widget.contains('this.autoriserRecuperation = true'), isTrue,
        reason: 'autoriserRecuperation doit avoir true pour défaut');

    // La garde précède l'appel réseau : position vérifiée dans la source.
    final iGarde = widget.indexOf('if (!widget.autoriserRecuperation) return;');
    final iAppel = widget.indexOf('svc.fetchArriveeDirecte(');
    expect(iGarde, greaterThanOrEqualTo(0));
    expect(iAppel, greaterThan(iGarde),
        reason: 'la garde doit précéder fetchArriveeDirecte dans le fichier');

    // ── Maillon 1 est DANS races_screen (un seul site d'arrivée) ────────
    expect('ArriveReelleWidget('.allMatches(races).length, 1,
        reason: 'un seul widget d\'arrivée dans le calendrier : la mise en '
            'lecture seule n\'en oublie aucun');
    expect('CourseDetailScreen('.allMatches(races).length, 1,
        reason: 'une seule navigation vers le détail : la propagation n\'en '
            'oublie aucune');

    debugPrint('R1-E structurel : 3 maillons présents, '
        'garde@$iGarde < appel@$iAppel');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  F-bis [STRUCTUREL] — les AUTRES appelants ne passent pas lectureSeule
  //
  //  Contrôle de câblage, pas d'exécution. Il établit qu'aucun autre écran
  //  n'a été mis en lecture seule par inadvertance : leur comportement reste
  //  donc celui du défaut `false`, ce que R1-F mesure par ailleurs.
  // ═════════════════════════════════════════════════════════════════════════
  test('R1-F2 [structurel] aucun autre écran ne force lectureSeule', () {
    const autres = <String>[
      'lib/screens/best_bet_screen.dart',
      'lib/screens/conseils_screen.dart',
      'lib/screens/home_screen.dart',
      'lib/screens/mes_paris_screen.dart',
      'lib/screens/programme_screen.dart',
      'lib/widgets/paris/alert_widgets.dart',
    ];

    final rapport = <String>[];
    for (final chemin in autres) {
      final src = _lire(chemin);
      final nDetail = 'CourseDetailScreen('.allMatches(src).length;
      final nLecture = 'lectureSeule:'.allMatches(src).length;
      rapport.add('$chemin : $nDetail appel(s), $nLecture lectureSeule');
      expect(nLecture, 0,
          reason: '$chemin ne doit pas forcer lectureSeule : son comportement '
              'doit rester celui d\'avant R1');
      expect(nDetail, greaterThanOrEqualTo(1),
          reason: 'TÉMOIN : $chemin doit bien appeler CourseDetailScreen, '
              'sinon l\'assertion précédente serait vide');
    }

    debugPrint('R1-F2 structurel :\n  ${rapport.join('\n  ')}');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  G [STRUCTUREL] — aucun fichier IA / PMU / L0-L1 ne porte le correctif
  //
  //  Contrôle de câblage : si quelqu'un avait instrumenté un service protégé
  //  pour R1, l'identifiant y apparaîtrait. Ce test NE prouve PAS l'absence
  //  de modification au sens Git — cela est vérifié hors test par
  //  `git diff --name-only`. Les deux preuves sont complémentaires.
  // ═════════════════════════════════════════════════════════════════════════
  test('R1-G [structurel] aucun identifiant R1 dans les services protégés', () {
    const proteges = <String>[
      'lib/services/ia_memory_service.dart',
      'lib/services/data_refresh_service.dart',
      'lib/services/zone_turf_service.dart',
      'lib/services/arrivee_officielle_service.dart',
      'lib/services/backup_service.dart',
      'lib/services/alert_service.dart',
      'lib/services/ia_memory_models.dart',
    ];

    final rapport = <String>[];
    for (final chemin in proteges) {
      final src = _lire(chemin);
      final nAutoriser = 'autoriserRecuperation'.allMatches(src).length;
      final nLecture = 'lectureSeule'.allMatches(src).length;
      rapport.add('$chemin : autoriserRecuperation=$nAutoriser '
          'lectureSeule=$nLecture');
      expect(nAutoriser, 0,
          reason: '$chemin est protégé : le correctif R1 ne doit rien y '
              'introduire');
      expect(nLecture, 0,
          reason: '$chemin est protégé : le correctif R1 ne doit rien y '
              'introduire');
      expect(src.trim(), isNotEmpty,
          reason: 'TÉMOIN : fichier lu non vide, sinon l\'assertion serait vide');
    }

    // Témoin inverse : les 3 fichiers du correctif, eux, PORTENT l'identifiant.
    expect('autoriserRecuperation'.allMatches(_lire(_fWidget)).length,
        greaterThan(0),
        reason: 'le widget DOIT porter l\'identifiant : sans ce témoin, '
            'l\'absence ci-dessus pourrait venir d\'une faute de frappe');
    expect('lectureSeule'.allMatches(_lire(_fDetail)).length, greaterThan(0));

    debugPrint('R1-G structurel :\n  ${rapport.join('\n  ')}');
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  TABLE DE CORRESPONDANCE EXIGENCES → TESTS
//
//    A. false → aucun appel HTTP ......... R1-A  (comportemental)
//    B. true  → comportement historique .. R1-B  (comportemental)
//    C. arrivée connue toujours affichée . R1-C  (comportemental)
//    D. transitions sans récupération .... R1-D1 (comportemental, +D2 témoin)
//    E. propagation des 3 maillons ....... R1-E  (STRUCTUREL)
//    F. autres appelants inchangés ....... R1-F  (comportemental, défaut omis)
//                                           R1-F2 (STRUCTUREL, câblage)
//    G. services IA/PMU/L0-L1 intacts .... R1-G  (STRUCTUREL) + git hors test
//
//  LIMITES DE COUVERTURE — énoncées, non masquées :
//    • Aucun test ne monte `RacesScreen` ni `CourseDetailScreen` en entier :
//      `CourseDetailScreen` appelle `IaPronosticEngine.genererPronostic` dans
//      `initState` et démarre un `Timer.periodic` de 30 s, et `RacesScreen`
//      exige un `DataRefreshService`. Les monter exigerait de maîtriser un
//      état global que je ne peux pas neutraliser sans modifier un service.
//      La propagation est donc établie par R1-E (câblage) et non par exécution.
//    • L'apprentissage (poids / calibration) n'est pas mesuré directement :
//      il est en AVAL de l'appel réseau (ia_memory_service.dart:1463-1469
//      puis 2853-2856). R1-A prouvant qu'aucun appel n'est émis, aucune
//      écriture ni aucun apprentissage n'est atteignable. C'est un
//      raisonnement de chaîne, pas une mesure des poids.
//    • `IaMemoryService._arriveeCache` est global et non vidable sans hook :
//      l'isolation repose sur des courseKey uniques, jamais sur un nettoyage.
// ═══════════════════════════════════════════════════════════════════════════
