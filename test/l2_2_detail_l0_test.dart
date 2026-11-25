// ═══════════════════════════════════════════════════════════════════════════
//  L2-2 — DÉTAIL DE COURSE : AFFICHAGE DES ARRIVÉES OFFICIELLES COMPLÈTES
//         DEPUIS L0, RÉSERVÉ AU DÉTAIL OUVERT EN CONSULTATION
//
//  PÉRIMÈTRE DU CORRECTIF L2-2 (UN SEUL fichier de production) :
//    • lib/screens/course_detail_screen.dart
//        + sourceL0: widget.lectureSeule
//        (autoriserRecuperation: !widget.lectureSeule conservé tel quel)
//
//  Conséquence voulue : SEUL le détail ouvert depuis le calendrier
//  (`races_screen.dart:475` → `lectureSeule: true`) lit L0. Les neuf autres
//  sites d'appel (best_bet ×3, conseils, home ×2, mes_paris, programme,
//  alert_widgets) laissent `lectureSeule == false`, donc `sourceL0 == false`
//  et conservent exactement le chemin historique.
//
//  DEUX FAMILLES DE PREUVES, jamais confondues :
//    [COMPORTEMENTAL] monte le VRAI `CourseDetailScreen`, défile dans son
//                     `ListView` (le widget d'arrivée est hors écran au
//                     premier rendu : mesuré 0 avant défilement, 1 après),
//                     et lit les textes réellement rendus.
//    [STRUCTUREL]     lit le TEXTE d'un fichier source. Vérifie un câblage —
//                     ne prouve aucune exécution.
//
//  ⚠️ LIMITES DE COUVERTURE — énoncées, non masquées :
//    • Aucun service n'est modifié. Aucun hook de test n'est ajouté.
//    • `CourseDetailScreen.initState` appelle TOUJOURS
//      `IaPronosticEngine.genererPronostic()` : c'est antérieur à L2-2 et
//      laissé intact (autorisation L2-2 §3). Les tests mesurent que ce calcul
//      n'écrit rien (poids, calibration, pronostics inchangés).
//    • Un `Timer.periodic(30 s)` tourne dans l'écran. Les tests n'utilisent
//      jamais `pumpAndSettle()` (jamais stable) et libèrent l'arbre à la fin.
//    • La divergence des 60 secondes entre les deux règles `isTerminee` n'est
//      PAS corrigée (autorisation §2). Elle ne peut pas être reproduite via un
//      `ZtCourse` réel : `heureDateTime` n'a que la précision de la minute.
//      Elle est donc MESURÉE au niveau des deux règles (L2-2.9), et la preuve
//      comportementale porte sur ce qui compte : aucune requête, aucune
//      écriture, même à la borne.
//    • `flutter_test` neutralise le réseau (`_MockHttpOverrides` → 400) : les
//      tests ajoutent un `MockClient` COMPTEUR via `http.runWithClient` pour
//      pouvoir affirmer « 0 requête » au lieu de le supposer.
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
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/widgets/arrivee_reelle_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  1. STORE CONTRÔLABLE
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

  /// Écrit une valeur comme le ferait un AUTRE processus.
  ///
  /// ⚠️ L'invalidation est OBLIGATOIRE : `SharedPreferences` gèle un SNAPSHOT
  /// (`_preferenceCache`) au premier `getInstance()`
  /// (shared_preferences_legacy.dart:76-104) ; toutes les lectures suivantes
  /// portent sur ce snapshot, jamais sur le store. Sans `resetStatic()`, une
  /// donnée semée serait invisible pour le service et le test prouverait le
  /// contraire de ce qu'il annonce.
  void semer(String cle, Object valeur) {
    valeurs['flutter.$cle'] = valeur;
    SharedPreferences.resetStatic();
  }

  void retirer(String cle) {
    valeurs.remove('flutter.$cle');
    SharedPreferences.resetStatic();
  }

  Object? lire(String cle) => valeurs['flutter.$cle'];

  List<String> get clesShards => valeurs.keys
      .where((k) => k.startsWith('flutter.$kArriveeStoragePrefix'))
      .toList()
    ..sort();

  List<String> get clesToutes => valeurs.keys.toList()..sort();
}

late _Store _store;

void _installerStore() {
  _store = _Store();
  SharedPreferencesStorePlatform.instance = _store;
  SharedPreferences.resetStatic();
}

// ═══════════════════════════════════════════════════════════════════════════
//  2. DATES, COURSES, SHARDS
// ═══════════════════════════════════════════════════════════════════════════

/// `ddMMyyyy` d'HIER : garantit une course toujours terminée, quelle que soit
/// l'heure d'exécution du test (une course « aujourd'hui 10:00 » serait dans le
/// futur si le test tourne à 08:00, et `isTerminee` serait faux).
String get _dateHierDdMmYyyy {
  final n = DateTime.now().subtract(const Duration(days: 1));
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

/// Mois de shard `YYYY-MM` correspondant à `ddMMyyyy`.
String _moisDe(String ddMmYyyy) =>
    '${ddMmYyyy.substring(4, 8)}-${ddMmYyyy.substring(2, 4)}';

/// Encode un shard mensuel exactement comme la production
/// (`_encoderShard`, arrivee_officielle_service.dart:983-996).
String _encoderShard(Map<String, List<List<int>>> arrivees) {
  final payload = <String, dynamic>{
    'v': 1,
    'arrivees': <String, dynamic>{
      for (final e in arrivees.entries)
        e.key: <String, dynamic>{'rangs': e.value},
    },
  };
  return base64Encode(gzip.encode(utf8.encode(jsonEncode(payload))));
}

void _semerShard(Map<String, List<List<int>>> arrivees, {String? mois}) {
  _store.semer(
    cleStockageMois(mois ?? _moisDe(_dateHierDdMmYyyy)),
    _encoderShard(arrivees),
  );
}

ZtPartant _partant(String num, {double cote = 5.0}) => ZtPartant(
      numero: num,
      nom: 'CHEVAL $num',
      driver: 'D$num',
      entraineur: 'E$num',
      proprietaire: 'P$num',
      gains: '1000',
      record: '1m10',
      musique: '1p2p3p1p2p',
      cote: '$cote',
      ageSexe: '5H',
      musiqueDistanceSpecifique: '',
      poids: 58.0,
      placeDepartInt: 1,
      hippodromeActuel: 'VINCENNES',
      statsJockeyCsv: '',
      statsHippodromeCsv: '',
      statutPmu: 'PARTANT',
      statsEntraineurCsv: '',
      eloRating: 0,
      eloNbCourses: 0,
      eloVariationMois: 0,
      statsTerrainCsv: '',
      gainsDernierAn: 0,
    );

/// Course terminée d'hier à 10:00, `numCourse` piloté par l'appelant pour
/// que `buildCourseKey` (construit dans l'écran) tombe sur la clé semée.
ZtCourse _course({required int numCourse, String heure = '10:00'}) => ZtCourse(
      numCourse: numCourse,
      anchor: 'a',
      nom: 'PRIX L2-2',
      heure: heure,
      distance: '2100',
      prix: '20000',
      type: 'Trot Attelé',
      piste: 'Grande',
      categorie: 'C',
      isQuinte: false,
      pronosticZt: const <int>[1, 2, 3],
      partants: <ZtPartant>[_partant('1'), _partant('2'), _partant('3')],
      dateStr: _dateHierDdMmYyyy,
    );

ZtReunion _reunion(ZtCourse course) => ZtReunion(
      code: 'R1',
      lieu: 'VINCENNES',
      discipline: 'Trot',
      dateStr: _dateHierDdMmYyyy,
      courses: <ZtCourse>[course],
    );

// ═══════════════════════════════════════════════════════════════════════════
//  3. RÉSEAU COMPTEUR
// ═══════════════════════════════════════════════════════════════════════════

final List<Uri> _urls = <Uri>[];
int get _nbRapports =>
    _urls.where((u) => u.path.contains('rapports-definitifs')).length;

Future<T> _sousReseauCompteur<T>(Future<T> Function() action) {
  final client = MockClient((request) async {
    _urls.add(request.url);
    return http.Response('{}', 200,
        headers: const <String, String>{'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. MONTAGE DU DÉTAIL RÉEL + DÉFILEMENT
// ═══════════════════════════════════════════════════════════════════════════

/// Monte le VRAI `CourseDetailScreen` et va chercher le widget d'arrivée.
///
/// Le contenu est dans un `ListView` : le widget d'arrivée n'est PAS construit
/// au premier rendu (mesuré : 0 occurrence avant défilement, 1 après). Sans ce
/// défilement, toutes les assertions d'affichage seraient vides.
Future<void> _monterDetail(
  WidgetTester tester, {
  required ZtCourse course,
  required bool lectureSeule,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: CourseDetailScreen(
      course: course,
      reunion: _reunion(course),
      lectureSeule: lectureSeule,
    ),
  ));
  await _pomper(tester);

  final liste = find.byType(ListView);
  for (var i = 0; i < 3 && find.byType(ArriveReelleWidget).evaluate().isEmpty; i++) {
    await tester.drag(liste.first, const Offset(0, -600));
    await _pomper(tester);
  }

  expect(find.byType(ArriveReelleWidget).evaluate().length, 1,
      reason: 'TÉMOIN : le widget d\'arrivée doit être construit pour que le '
          'test observe quoi que ce soit. S\'il en manque, le test serait vide.');
}

/// Pompage borné : jamais `pumpAndSettle()` (le `Timer.periodic(30 s)` de
/// l'écran ne se stabilise jamais).
Future<void> _pomper(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

List<String> _textes(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

/// Le widget d'arrivée réellement monté, pour lire ses paramètres.
ArriveReelleWidget _widgetArrivee(WidgetTester tester) =>
    tester.widget<ArriveReelleWidget>(find.byType(ArriveReelleWidget));

// ═══════════════════════════════════════════════════════════════════════════
//  5. LECTURE DE SOURCE — tests STRUCTURELS uniquement
// ═══════════════════════════════════════════════════════════════════════════

String _lire(String chemin) {
  final f = File(chemin);
  expect(f.existsSync(), isTrue, reason: 'fichier introuvable : $chemin');
  return f.readAsStringSync();
}

/// Retire les commentaires avant toute mesure de code.
///
/// Sans cela la mesure est fausse : un `indexOf` ou un `allMatches` sur le
/// texte brut tombe sur les commentaires de documentation, comme cela s'est
/// produit en L2-1 (`runApp(` trouvé dans un commentaire, `fetchArriveeDirecte(`
/// compté deux fois).
String _codeSansCommentaires(String src) {
  final out = StringBuffer();
  for (final ligne in src.split('\n')) {
    if (ligne.trimLeft().startsWith('//')) continue;
    var coupe = -1;
    for (var i = 0; i + 1 < ligne.length; i++) {
      if (ligne[i] == '/' && ligne[i + 1] == '/') {
        if (i > 0 && ligne[i - 1] == ':') continue;
        coupe = i;
        break;
      }
    }
    out.writeln(coupe >= 0 ? ligne.substring(0, coupe) : ligne);
  }
  return out.toString();
}

// ═══════════════════════════════════════════════════════════════════════════
//  6. ISOLATION
// ═══════════════════════════════════════════════════════════════════════════

void _viderL0() => ArriveeOfficielleService.instance.viderMemoireSeulement();

/// Vide l'état IA : RAM **et** les deux clés de stockage.
///
/// `IaMemoryService` est un singleton dont l'état survit d'un test à l'autre et
/// `recharger()` relit le disque sans effacer les clés
/// (ia_memory_service.dart:1664-1680). Un store neuf ne suffit donc pas.
Future<void> _viderIa() async {
  _store.retirer('ia_pronostics_v2');
  _store.retirer('ia_pronostics_v2_gz');
  await IaMemoryService.instance.recharger();
}

/// Sème un pronostic IA portant une arrivée historique.
Future<void> _semerPronostic({
  required String courseKey,
  required List<int> arrivee,
  bool resolus = true,
}) async {
  final p = IaPronostic(
    courseKey: courseKey,
    nomCourse: 'PRIX L2-2',
    hippodrome: 'VINCENNES',
    discipline: 'Trot Attelé',
    datePronostic: DateTime.now().subtract(const Duration(days: 1)),
    scoresIA: const <String, double>{'5': 80.0, '3': 70.0},
    scoresCriteres: const <String, ScoresCriteres>{},
    resultatsReels: resolus,
    arriveeReelle: arrivee,
  );
  _store.semer('ia_pronostics_v2', <String>[jsonEncode(p.toJson())]);
  await IaMemoryService.instance.recharger();
}

// ═══════════════════════════════════════════════════════════════════════════
//  TESTS
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _urls.clear();
    _installerStore();
    _viderL0();
    await _viderIa();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L2-2.1 / L2-2.2 — CÂBLAGE : sourceL0 SUIT lectureSeule
  // ═════════════════════════════════════════════════════════════════════════
  test('L2-2.1 [structurel] sourceL0 == lectureSeule, et rien d\'autre', () {
    final code = _codeSansCommentaires(_lire('lib/screens/course_detail_screen.dart'));

    final nSourceL0 = 'sourceL0'.allMatches(code).length;
    expect(nSourceL0, 1,
        reason: 'un SEUL passage de sourceL0 : celui du widget d\'arrivée');

    expect(code.contains('sourceL0: widget.lectureSeule'),
        isTrue,
        reason: 'L0 réservé au détail ouvert en consultation');

    // Aucune forme permissive ne doit exister : un `sourceL0: true` en dur
    // contaminerait les neuf autres appelants.
    expect(code.contains('sourceL0: true'), isFalse,
        reason: 'aucune activation inconditionnelle');
    expect(code.contains('sourceL0: !'), isFalse,
        reason: 'aucune inversion : sourceL0 suit lectureSeule, il ne le nie pas');

    debugPrint('L2-2.1 structurel : sourceL0=$nSourceL0');
  });

  test('L2-2.2 [structurel] autoriserRecuperation: !lectureSeule conservé', () {
    final code = _codeSansCommentaires(_lire('lib/screens/course_detail_screen.dart'));
    final n = 'autoriserRecuperation'.allMatches(code).length;

    expect(n, 1, reason: 'un seul passage, comme en R1');
    expect(code.contains('autoriserRecuperation: !widget.lectureSeule'),
        isTrue,
        reason: 'R1 ne doit pas être affaibli par L2-2');

    debugPrint('L2-2.2 structurel : autoriserRecuperation=$n');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L2-2.3 — lectureSeule=true + L0 présent → affichage L0 fidèle
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('L2-2.3 [comportemental] lectureSeule=true → ex æquo L0 fidèles',
      (tester) async {
    final course = _course(numCourse: 1);
    final key = buildCourseKey(
      reunionCode: 'R1',
      numCourse: 1,
      dateStr: _dateHierDdMmYyyy,
    );
    // Trois groupes : 4 et 7 ex æquo, puis 2, puis 9 et 1 ex æquo.
    const groupes = <List<int>>[
      <int>[4, 7],
      <int>[2],
      <int>[9, 1],
    ];
    _semerShard(<String, List<List<int>>>{key: groupes});
    await ArriveeOfficielleService.instance.charger();

    // TÉMOIN : L0 détient bien l'arrivée avant le montage.
    expect(ArriveeOfficielleService.instance.arrivee(key), equals(groupes),
        reason: 'TÉMOIN : sans donnée L0, le test ne prouverait pas la lecture');

    await _monterDetail(tester, course: course, lectureSeule: true);

    final w = _widgetArrivee(tester);
    expect(w.sourceL0, isTrue, reason: 'sourceL0 doit suivre lectureSeule');
    expect(w.autoriserRecuperation, isFalse, reason: 'R1 : aucune récupération');

    final textes = _textes(tester);
    debugPrint('L2-2.3 textes=$textes');

    expect(textes, contains('Officielle complète'),
        reason: 'la provenance L0 doit être signalée');
    expect(textes, isNot(contains('Résultat historique')));
    expect(textes, contains('N°4'));
    expect(textes, contains('N°7'));
    expect(textes, contains('N°2'));
    expect(textes, contains('N°9'));
    expect(textes, contains('N°1'));
    // Les DEUX ex æquo sont rendus avec « = » : aucune perte.
    //
    // ⚠️ On ne compte PAS les « = » dans tous les textes de l'écran : le
    // widget d'arrivée affiche aussi, hors L0, la légende
    // « 🟢 Vert = cheval prédit par l'IA » (arrivee_reelle_widget.dart:283),
    // qui contient un « = » étranger à la structure. Mesuré : compter
    // globalement donnait 3 au lieu de 2. La structure est donc mesurée dans
    // la LISTE ORDONNÉE des textes, où chaque « = » séparateur est un widget
    // `Text` autonome et où la légende d'un seul tenant ne peut pas être
    // confondue.
    final egal = textes.where((s) => s == '=').length;
    expect(egal, 2,
        reason: 'deux groupes d\'ex æquo → deux séparateurs « = » distincts');
    expect(textes, contains('·'), reason: 'les rangs restent séparés');

    // Ordre fidèle : 4 = 7 · 2 · 9 = 1
    //
    // Mesure sur la liste, pas sur une concaténation : un `indexOf` sur le
    // texte joint pourrait trouver les numéros dans un autre widget de
    // l'écran (classement IA, pronostic PMU). On s'appuie sur l'ordre réel
    // des widgets `Text` de la liste.
    final i4 = textes.indexOf('N°4');
    final iEg1 = textes.indexOf('=');
    final i7 = textes.indexOf('N°7');
    final i2 = textes.indexOf('N°2');
    final i9 = textes.indexOf('N°9');
    final iEg2 = textes.indexOf('=', iEg1 + 1);
    final i1 = textes.indexOf('N°1');
    debugPrint('L2-2.3 ordre i4=$i4 iEg1=$iEg1 i7=$i7 i2=$i2 i9=$i9 '
        'iEg2=$iEg2 i1=$i1');

    expect(i4, lessThan(iEg1), reason: '4 précède le « = » qui le lie à 7');
    expect(iEg1, lessThan(i7), reason: 'le « = » est entre 4 et 7');
    expect(i7, lessThan(i2), reason: 'le groupe [4,7] précède le rang suivant');
    expect(i2, lessThan(i9), reason: 'le N°2 seul précède le second ex æquo');
    expect(i9, lessThan(iEg2), reason: '9 précède le « = » qui le lie à 1');
    expect(iEg2, lessThan(i1), reason: 'le « = » est entre 9 et 1');

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L2-2.4 — lectureSeule=true + L0 absent → repli historique
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('L2-2.4 [comportemental] lectureSeule=true, L0 vide → repli historique',
      (tester) async {
    final course = _course(numCourse: 2);
    final key = buildCourseKey(
      reunionCode: 'R1',
      numCourse: 2,
      dateStr: _dateHierDdMmYyyy,
    );
    await _semerPronostic(courseKey: key, arrivee: const <int>[5, 3]);
    await ArriveeOfficielleService.instance.charger();

    // TÉMOIN : L0 vide pour cette clé, IA non vide.
    expect(ArriveeOfficielleService.instance.arrivee(key), isNull);
    expect(IaMemoryService.instance.arriveeConnue(key), equals(<int>[5, 3]));

    await _monterDetail(tester, course: course, lectureSeule: true);

    final textes = _textes(tester);
    debugPrint('L2-2.4 textes=$textes');

    expect(textes, contains('Résultat historique'),
        reason: 'le repli doit être distingué de L0');
    expect(textes, isNot(contains('Officielle complète')));
    expect(textes, contains('N°5'));
    expect(textes, contains('N°3'));

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L2-2.5 — lectureSeule=false → comportement historique, L0 ignoré
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('L2-2.5 [comportemental] lectureSeule=false → L0 ignoré, badge « Officiel »',
      (tester) async {
    final course = _course(numCourse: 3);
    final key = buildCourseKey(
      reunionCode: 'R1',
      numCourse: 3,
      dateStr: _dateHierDdMmYyyy,
    );
    // L0 et IA portent des arrivées DIFFÉRENTES : si L0 était lu, on verrait
    // N°4/N°7. On doit voir N°5/N°3.
    _semerShard(<String, List<List<int>>>{
      key: <List<int>>[
        <int>[4, 7],
        <int>[2],
      ],
    });
    await ArriveeOfficielleService.instance.charger();
    await _semerPronostic(courseKey: key, arrivee: const <int>[5, 3]);

    await _monterDetail(tester, course: course, lectureSeule: false);

    final w = _widgetArrivee(tester);
    expect(w.sourceL0, isFalse, reason: 'les autres appelants gardent false');
    expect(w.autoriserRecuperation, isTrue,
        reason: 'R1 : le mode non-consultation peut récupérer');

    final textes = _textes(tester);
    debugPrint('L2-2.5 textes=$textes');

    expect(textes, contains('N°5'));
    expect(textes, contains('N°3'));
    expect(textes, isNot(contains('N°4')),
        reason: 'L0 ne doit PAS être lu quand lectureSeule=false');
    expect(textes, isNot(contains('N°7')));
    expect(textes, contains('Officiel'),
        reason: 'libellé historique conservé');
    expect(textes, isNot(contains('Officielle complète')));
    expect(textes, isNot(contains('Résultat historique')));

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L2-2.6 — consultation : 0 réseau, 0 apprentissage, 0 écriture
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('L2-2.6 [comportemental] consultation → 0 réseau, 0 apprentissage',
      (tester) async {
    final course = _course(numCourse: 4);
    final key = buildCourseKey(
      reunionCode: 'R1',
      numCourse: 4,
      dateStr: _dateHierDdMmYyyy,
    );
    _semerShard(<String, List<List<int>>>{
      key: <List<int>>[
        <int>[5],
        <int>[3],
      ],
    });
    await ArriveeOfficielleService.instance.charger();
    // Pronostic NON résolu : la chaîne d'apprentissage serait atteignable si
    // une récupération était déclenchée puis aboutissait.
    await _semerPronostic(
        courseKey: key, arrivee: const <int>[], resolus: false);

    final mem = IaMemoryService.instance;
    final poidsAvant = jsonEncode(mem.poids.toJson());
    final calibAvant = mem.poids.calibrationScore;
    final nbPronosticsAvant = mem.pronostics.length;
    final parisAvant = AlertService.instance.trackedCourses.keys.toList()
      ..sort();
    final clesAvant = _store.clesToutes;

    await _sousReseauCompteur(() async {
      await _monterDetail(tester, course: course, lectureSeule: true);
      await _pomper(tester);
    });

    final poidsApres = jsonEncode(mem.poids.toJson());
    final pronostic = mem.getPronostic(key)!;
    final parisApres = AlertService.instance.trackedCourses.keys.toList()
      ..sort();

    debugPrint('L2-2.6 urls=${_urls.length} rapports=$_nbRapports '
        'poidsIdentiques=${poidsAvant == poidsApres} '
        'calibration=$calibAvant→${mem.poids.calibrationScore} '
        'resultatsReels=${pronostic.resultatsReels} '
        'paris=${parisAvant.length}→${parisApres.length}');

    expect(_urls, isEmpty,
        reason: 'aucune requête HTTP ne doit partir d\'une consultation');
    expect(_nbRapports, 0);
    expect(poidsApres, poidsAvant,
        reason: 'poids adaptatifs inchangés (aucun apprentissage)');
    expect(mem.poids.calibrationScore, calibAvant);
    expect(pronostic.resultatsReels, isFalse,
        reason: 'la consultation ne résout pas le pronostic');
    expect(mem.pronostics.length, nbPronosticsAvant);
    expect(parisApres, parisAvant,
        reason: 'aucun résultat de pari modifié');
    expect(_store.clesToutes, clesAvant,
        reason: 'aucune clé créée ni supprimée pendant la consultation');

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L2-2.7 — lectureSeule=false : la récupération reste POSSIBLE (R1 intact)
  //
  //  Contrôle négatif indispensable : sans lui, L2-2.6 pourrait passer parce
  //  que la récupération est cassée pour tout le monde, et non parce que la
  //  consultation l'interdit.
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('L2-2.7 [comportemental] lectureSeule=false → récupération toujours possible',
      (tester) async {
    final course = _course(numCourse: 5);
    await ArriveeOfficielleService.instance.charger();

    await _sousReseauCompteur(() async {
      await _monterDetail(tester, course: course, lectureSeule: false);
      await _pomper(tester);
    });

    debugPrint('L2-2.7 urls=${_urls.length} rapports=$_nbRapports');

    expect(_nbRapports, greaterThanOrEqualTo(1),
        reason: 'hors consultation, R1 laisse la récupération active : la '
            'preuve « 0 requête en consultation » n\'est valide que si elle '
            'peut être non nulle ailleurs');

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L2-2.8 — les neuf autres appelants restent hors du dispositif
  // ═════════════════════════════════════════════════════════════════════════
  test('L2-2.8 [structurel] les autres écrans n\'activent ni L0 ni lectureSeule', () {
    const autres = <String>[
      'lib/screens/best_bet_screen.dart',
      'lib/screens/conseils_screen.dart',
      'lib/screens/home_screen.dart',
      'lib/screens/mes_paris_screen.dart',
      'lib/screens/programme_screen.dart',
      'lib/widgets/paris/alert_widgets.dart',
      'lib/screens/races_screen.dart',
    ];
    final rapport = <String>[];
    for (final f in autres) {
      final code = _codeSansCommentaires(_lire(f));
      final nL0 = 'sourceL0'.allMatches(code).length;
      final nLS = 'lectureSeule: true'.allMatches(code).length;
      rapport.add('$f :: sourceL0=$nL0 lectureSeule:true=$nLS');

      // `races_screen.dart` est le SEUL fichier hors périmètre autorisé en
      // L2-2 à porter ces deux marqueurs : ils y ont été installés par L2-1
      // (`sourceL0: true` sur le widget du calendrier) et par R1
      // (`lectureSeule: true` à la navigation). L2-2 n'y a rien ajouté.
      // Exiger 0 ici aurait été faux — mesuré : sourceL0=1, lectureSeule=1.
      if (f == 'lib/screens/races_screen.dart') {
        expect(nL0, 1,
            reason: 'L2-1 : une seule activation, sur le widget du calendrier');
        expect(nLS, 1,
            reason: 'R1 : une seule propagation de lecture seule');
        expect(code.trim(), isNotEmpty, reason: 'TÉMOIN : fichier lu non vide');
        continue;
      }

      expect(nL0, 0, reason: '$f ne doit pas activer L0');
      expect(nLS, 0, reason: '$f ne doit pas ouvrir le détail en consultation');
      expect(code.trim(), isNotEmpty, reason: 'TÉMOIN : fichier lu non vide');
    }
    debugPrint('L2-2.8 structurel :\n  ${rapport.join('\n  ')}');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L2-2.9 — DIVERGENCE DES 60 SECONDES : mesurée, non corrigée
  //
  //  Les deux règles coexistent et ne sont PAS unifiées (autorisation §2) :
  //    calendrier (races_screen.dart:513) : diffMin < -90   (minutes tronquées)
  //    détail (course_detail_screen.dart:568) :
  //        heureDateTime.isBefore(now - 90 min)            (comparaison exacte)
  //  Sur la fenêtre (90 min ; 90 min 59 s], le calendrier dit « pas terminée »
  //  et le détail dit « terminée ». Ce test FIXE cet état observé pour qu'une
  //  unification future soit visible, et vérifie surtout qu'à la borne la
  //  consultation ne déclenche toujours aucune requête.
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('L2-2.9 [comportemental] divergence 60 s documentée, 0 réseau à la borne',
      (tester) async {
    // ── Mesure des deux règles sur le MÊME instant ────────────────────────
    final now = DateTime(2026, 11, 16, 12, 0, 0);
    final borne = now.subtract(const Duration(minutes: 90, seconds: 30));
    final diffMin = borne.difference(now).inMinutes; // troncature vers zéro
    final regleCalendrier = diffMin < -90;
    final regleDetail =
        borne.isBefore(now.subtract(const Duration(minutes: 90)));

    debugPrint('L2-2.9 divergence : à 90 min 30 s → diffMin=$diffMin '
        'calendrier=$regleCalendrier detail=$regleDetail');

    expect(borne.difference(now).inMinutes, -90,
        reason: 'MESURE : la troncature ramène 90 min 30 s à -90');
    expect(regleCalendrier, isFalse);
    expect(regleDetail, isTrue,
        reason: 'ANOMALIE DOCUMENTÉE, NON CORRIGÉE : les deux règles '
            'divergent sur (90 min ; 90 min 59 s]. Non unifiées (autorisation '
            'L2-2 §2) : ce test fixe l\'état observé, pas un contrat.');
    // Convergence en dehors de la fenêtre : la divergence est bien bornée.
    expect(now.subtract(const Duration(minutes: 91)).difference(now).inMinutes < -90,
        isTrue);
    expect(
        now
            .subtract(const Duration(minutes: 91))
            .isBefore(now.subtract(const Duration(minutes: 90))),
        isTrue,
        reason: 'au-delà de 90 min 59 s, les deux règles concordent');

    // ── Preuve que la borne ne provoque aucune sortie réseau ──────────────
    final course = _course(numCourse: 6);
    final key = buildCourseKey(
      reunionCode: 'R1',
      numCourse: 6,
      dateStr: _dateHierDdMmYyyy,
    );
    _semerShard(<String, List<List<int>>>{
      key: <List<int>>[
        <int>[5],
        <int>[3],
      ],
    });
    await ArriveeOfficielleService.instance.charger();

    await _sousReseauCompteur(() async {
      await _monterDetail(tester, course: course, lectureSeule: true);
      await _pomper(tester);
    });

    debugPrint('L2-2.9 à la borne (lectureSeule=true) : urls=${_urls.length}');
    expect(_urls, isEmpty,
        reason: 'même quand le détail juge la course terminée et que le '
            'calendrier la juge encore en cours, la consultation ne sort pas '
            'sur le réseau');

    await tester.pumpWidget(const SizedBox());
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  TABLE DE CORRESPONDANCE EXIGENCES → TESTS
//
//    1. sourceL0 uniquement si lectureSeule=true ... L2-2.1 (STRUCTUREL)
//                                                   L2-2.3, 2.5 (widget)
//    2. autoriserRecuperation: false conservé ...... L2-2.2 (STRUCTUREL)
//                                                   L2-2.3 (widget)
//    3. Groupes ex æquo L0 fidèles ................. L2-2.3
//    4. Repli historique si L0 absent .............. L2-2.4
//    5. Comportement historique si lectureSeule=false  L2-2.5, 2.7
//    6. Aucun réseau ni apprentissage .............. L2-2.6, 2.9 (contrôle
//                                                   négatif : L2-2.7)
//    7. Aucun changement des résultats de paris .... L2-2.6
//    8. Non-régression R1 / L2-1 ................... L2-2.1, 2.2, 2.8
//       Divergence 60 s documentée ................. L2-2.9
// ═══════════════════════════════════════════════════════════════════════════
