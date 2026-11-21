// ═══════════════════════════════════════════════════════════════════════════
//  L2-1 — CALENDRIER DES COURSES : AFFICHAGE DES ARRIVÉES OFFICIELLES
//         COMPLÈTES DEPUIS L0, EX ÆQUO PRÉSERVÉS
//
//  PÉRIMÈTRE DU CORRECTIF L2-1 (3 fichiers de production, aucun autre) :
//    • lib/main.dart
//        + import du service L0
//        + await ArriveeOfficielleService.instance.charger()  AVANT runApp()
//    • lib/widgets/arrivee_reelle_widget.dart
//        + paramètre sourceL0 (défaut false)
//        + lecture L0 prioritaire, repli sur IaMemoryService.arriveeConnue()
//        + rendu GROUPÉ des ex æquo (jamais d'aplatissement pour l'affichage)
//        + badge de provenance « Officielle complète » / « Résultat historique »
//    • lib/screens/races_screen.dart
//        + sourceL0: true sur le widget du calendrier
//
//  DEUX FAMILLES DE TESTS, jamais confondues :
//    [COMPORTEMENTAL] monte le widget réel et observe le texte réellement rendu,
//                     ou lit le disque réellement écrit. Mesure, pas lecture.
//    [STRUCTUREL]     lit le TEXTE d'un fichier source. Vérifie un câblage —
//                     ne prouve aucune exécution. Jamais présenté comme
//                     un test d'intégration.
//
//  ISOLATION L0 :
//    `ArriveeOfficielleService` est un singleton avec état RAM
//    (`_shards`, `_enAttente`, `_charge`). `viderMemoireSeulement()`
//    (arrivee_officielle_service.dart:1287-1296) remet ces champs à zéro
//    SANS toucher au disque : c'est le mécanisme d'isolation officiel du
//    service, déjà utilisé par l1_capture_officielle_test.dart. Aucun hook
//    n'est ajouté, aucun service n'est modifié.
//    Chaque test utilise en outre une courseKey UNIQUE.
//
//  Ce fichier ne fait aucun commit, aucun push.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';
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
  /// ⚠️ POURQUOI L'INVALIDATION EST OBLIGATOIRE : `SharedPreferences`
  /// mémorise un SNAPSHOT (`_preferenceCache`) au premier `getInstance()`
  /// (shared_preferences_legacy.dart:76-104) et toutes les lectures suivantes
  /// (`getString`, `getKeys`) portent sur ce snapshot, jamais sur le store.
  /// Écrire dans `valeurs` sans invalider produirait une donnée présente dans
  /// le store mais INVISIBLE pour le service : les tests passeraient à côté
  /// du sujet en croyant l'avoir préparé.
  void semer(String cle, Object valeur) {
    valeurs['flutter.$cle'] = valeur;
    SharedPreferences.resetStatic();
  }

  /// Retire une valeur (même invalidation que [semer]).
  void retirer(String cle) {
    valeurs.remove('flutter.$cle');
    SharedPreferences.resetStatic();
  }

  bool contient(String cle) => valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => valeurs['flutter.$cle'];

  /// Toutes les clés de stockage L0 présentes (`kArriveeStoragePrefix`).
  List<String> get clesShards => valeurs.keys
      .where((k) => k.startsWith('flutter.$kArriveeStoragePrefix'))
      .toList()
    ..sort();

  bool get aFileEnAttente => valeurs.containsKey('flutter.$kArriveePendingKey');
}

late _Store _store;

void _installerStore() {
  _store = _Store();
  SharedPreferencesStorePlatform.instance = _store;
  SharedPreferences.resetStatic();
}

// ═══════════════════════════════════════════════════════════════════════════
//  2. COURSES UNIQUES + SEMIS DE SHARD
// ═══════════════════════════════════════════════════════════════════════════

int _compteur = 0;

/// Date au format `ddMMyyyy` — celui des `courseKey` L0 et des pronostics.
String get _dateDdMmYyyy {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

/// Mois `YYYY-MM` correspondant — celui des clés de shard.
String get _moisIso {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}';
}

/// courseKey neuve, au format `R{n}C{n}_ddMMyyyy`.
String _cleNeuve() {
  _compteur++;
  return 'R1C$_compteur' '_$_dateDdMmYyyy';
}

/// Encode un shard mensuel exactement comme la production
/// (`_encoderShard`, arrivee_officielle_service.dart:983-996) :
/// base64(gzip(json)) de `{"v":1,"arrivees":{courseKey:{rangs:[...]}}}`.
String _encoderShard(Map<String, List<List<int>>> arrivees) {
  final payload = <String, dynamic>{
    'v': 1,
    'arrivees': <String, dynamic>{
      for (final e in arrivees.entries) e.key: <String, dynamic>{'rangs': e.value},
    },
  };
  return base64Encode(gzip.encode(utf8.encode(jsonEncode(payload))));
}

/// Sème un shard mensuel contenant [arrivees]. Ne passe PAS par le service :
/// c'est le disque qui est préparé, comme après une exécution réelle.
void _semerShard(Map<String, List<List<int>>> arrivees, {String? mois}) {
  _store.semer(
    '$kArriveeStoragePrefix${mois ?? _moisIso}',
    _encoderShard(arrivees),
  );
}

/// Heure de départ 3 h dans le passé → `isTerminee` vrai partout.
DateTime get _heurePassee => DateTime.now().subtract(const Duration(hours: 3));

/// Vide l'état IA (pronostics) : RAM **et** les deux clés de stockage.
///
/// POURQUOI CE N'EST PAS REDONDANT AVEC `setUp` : `IaMemoryService` est un
/// singleton dont l'état survit d'un test à l'autre, et `recharger()` relit
/// le disque sans effacer les clés (`ia_memory_service.dart:1664-1680`).
/// Un store neuf ne suffit donc pas : `_pronostics` reste peuplé du test
/// précédent tant que `recharger()` n'est pas rappelé APRÈS la remise à zéro
/// des clés. On force ici les deux.
Future<void> _viderIa() async {
  _store.retirer('ia_pronostics_v2');
  _store.retirer('ia_pronostics_v2_gz');
  await IaMemoryService.instance.recharger();
}

/// Même chose pour L0 : mémoire seule, disque intact.
void _viderL0() => ArriveeOfficielleService.instance.viderMemoireSeulement();

// ═══════════════════════════════════════════════════════════════════════════
//  3. RÉSEAU SIMULÉ + COMPTEUR
// ═══════════════════════════════════════════════════════════════════════════

final List<Uri> _urls = <Uri>[];
int get _nbRapports =>
    _urls.where((u) => u.path.contains('rapports-definitifs')).length;

Future<T> _sousReseauSimule<T>(Future<T> Function() action) {
  final client = MockClient((request) async {
    _urls.add(request.url);
    return http.Response('{}', 200,
        headers: const <String, String>{'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. MONTAGE DU WIDGET
// ═══════════════════════════════════════════════════════════════════════════

Widget _monter({
  required String courseKey,
  required bool isTerminee,
  bool sourceL0 = true,
  bool compact = true,
  List<String> selectionIA = const <String>[],
  bool? autoriser,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ArriveReelleWidget(
            courseKey: courseKey,
            isTerminee: isTerminee,
            heureDepart: _heurePassee,
            selectionIA: selectionIA,
            compact: compact,
            autoriserRecuperation: autoriser ?? false,
            sourceL0: sourceL0,
          ),
        ),
      ),
    );

Future<void> _laisserResoudre(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Tous les textes rendus à l'écran, dans l'ordre de l'arbre.
List<String> _textes(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

// ═══════════════════════════════════════════════════════════════════════════
//  5. LECTURE DE SOURCE — tests STRUCTURELS uniquement
// ═══════════════════════════════════════════════════════════════════════════

String _lire(String chemin) {
  final f = File(chemin);
  expect(f.existsSync(), isTrue, reason: 'fichier introuvable : $chemin');
  return f.readAsStringSync();
}

/// Retire les commentaires d'un source avant toute mesure de code.
///
/// ⚠️ SANS CELA LA MESURE EST FAUSSE : `main.dart` contient dans un
/// commentaire la phrase « chargée AVANT `runApp()` » et le widget contient
/// `fetchArriveeDirecte()` dans son en-tête de documentation. Un `indexOf` ou
/// un `allMatches` sur le texte brut tombait donc sur des COMMENTAIRES, pas
/// sur des appels — mesuré : `runApp(` trouvé à l'offset 3015 (commentaire)
/// alors que l'appel réel est à 4835.
///
/// Coupe les lignes entièrement commentées et les fins de ligne `//`, en
/// épargnant le `//` d'une URL (`://`) : aucune ligne mesurée n'en contient,
/// la garde évite seulement une coupure abusive.
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
//  TESTS
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _urls.clear();
    _installerStore(); // store neuf + resetStatic → aucun snapshot hérité
    // Isolation officielle du service L0 : RAM remise à zéro, disque intact.
    _viderL0();
    // Isolation de l'IA : clés retirées du store neuf PUIS rechargement, sinon
    // les pronostics du test précédent survivraient dans le singleton.
    await _viderIa();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  EXIGENCE 1 — INITIALISATION L0 AVANT LE PREMIER AFFICHAGE
  //
  //  Deux preuves complémentaires :
  //    1a [STRUCTUREL] l'appel est présent dans main.dart, avant runApp()
  //    1b [COMPORTEMENTAL] sans charger(), arrivee() rend null alors que le
  //       shard est sur le disque ; après charger(), elle le rend
  // ═════════════════════════════════════════════════════════════════════════
  test('L2-1.1a [structurel] main.dart charge L0 avant runApp()', () {
    final src = _lire('lib/main.dart');
    // Mesure sur le CODE, jamais sur les commentaires : `main.dart` parle de
    // `runApp()` dans un commentaire situé AVANT l'appel réel.
    final code = _codeSansCommentaires(src);

    final iCharger =
        code.indexOf('ArriveeOfficielleService.instance.charger()');
    final iRunApp = code.indexOf('runApp(');

    expect(iCharger, greaterThanOrEqualTo(0),
        reason: 'main.dart doit initialiser L0 (appel réel, hors commentaire)');
    expect(iRunApp, greaterThanOrEqualTo(0),
        reason: 'l\'appel runApp() doit exister hors commentaire');
    expect(iCharger, lessThan(iRunApp),
        reason: 'charger() doit précéder runApp() : sans cela le premier '
            'rendu du calendrier aurait un service non chargé');
    expect(src.contains("import 'services/arrivee_officielle_service.dart';"),
        isTrue,
        reason: 'l\'import est la condition d\'existence de l\'appel');

    debugPrint('L2-1.1a structurel : charger@$iCharger < runApp@$iRunApp');
  });

  test('L2-1.1b [comportemental] sans charger() → null ; après → arrivée', () async {
    final key = _cleNeuve();
    // Le shard est sur le disque AVANT tout appel au service.
    _semerShard(<String, List<List<int>>>{
      key: <List<int>>[
        <int>[4, 7],
        <int>[2],
      ],
    });

    final svc = ArriveeOfficielleService.instance;

    // ── TÉMOIN : service non chargé → arrivee() ne voit rien ──────────────
    expect(svc.estCharge, isFalse,
        reason: 'TÉMOIN : sans cette précondition, le test ne prouverait pas '
            'la nécessité de l\'initialisation');
    expect(svc.arrivee(key), isNull,
        reason: 'arrivee() lit la RAM seule et ne charge jamais le disque : '
            'c\'est précisément pourquoi main.dart doit appeler charger()');

    // ── Initialisation (ce que fait main.dart) ────────────────────────────
    await svc.charger();

    debugPrint('L2-1.1b key=$key estCharge=${svc.estCharge} '
        'arrivee=${svc.arrivee(key)}');

    expect(svc.estCharge, isTrue);
    expect(svc.arrivee(key), isNotNull,
        reason: 'après charger(), l\'arrivée stockée doit être lisible');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  EXIGENCE 2 — RELECTURE CORRECTE DES ARRIVÉES STOCKÉES
  // ═════════════════════════════════════════════════════════════════════════
  test('L2-1.2 [comportemental] relecture disque → mémoire, contenu exact',
      () async {
    final k1 = _cleNeuve();
    final k2 = _cleNeuve();
    _semerShard(<String, List<List<int>>>{
      k1: <List<int>>[
        <int>[1],
        <int>[2],
        <int>[3],
      ],
      k2: <List<int>>[
        <int>[9],
        <int>[8],
      ],
    });

    final svc = ArriveeOfficielleService.instance;
    await svc.charger();

    debugPrint('L2-1.2 k1=${svc.arrivee(k1)} k2=${svc.arrivee(k2)} '
        'nbEntrees=${svc.nbEntrees}');

    expect(svc.arrivee(k1), equals(<List<int>>[
      <int>[1],
      <int>[2],
      <int>[3],
    ]));
    expect(svc.arrivee(k2), equals(<List<int>>[
      <int>[9],
      <int>[8],
    ]));
    expect(svc.nbEntrees, 2, reason: 'les deux entrées du même shard');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  EXIGENCE 3 — CONSERVATION DES EX ÆQUO
  // ═════════════════════════════════════════════════════════════════════════
  test('L2-1.3 [comportemental] ex æquo à plusieurs rangs conservés', () async {
    final key = _cleNeuve();
    // Trois chevaux au 1er rang, puis 1 au 2e, puis 2 au 3e.
    const groupes = <List<int>>[
      <int>[4, 7, 11],
      <int>[2],
      <int>[9, 1],
    ];
    _semerShard(<String, List<List<int>>>{key: groupes});

    final svc = ArriveeOfficielleService.instance;
    await svc.charger();
    final relu = svc.arrivee(key);

    debugPrint('L2-1.3 relu=$relu');
    expect(relu, equals(groupes),
        reason: 'les 3 groupes doivent survivre à l\'aller-retour disque');
    expect(relu![0], equals(<int>[4, 7, 11]),
        reason: 'aucun numéro du groupe d\'ex æquo ne doit être perdu');
    expect(relu[0].length, 3, reason: 'les 3 ex æquo sont présents');
    expect(relu[2], equals(<int>[9, 1]));

    // Témoin d'anti-aplatissement : la structure imbriquée est intacte.
    expect(relu, isNot(equals(<dynamic>[4, 7, 11, 2, 9, 1])),
        reason: 'une liste plate serait une perte de fidélité');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  EXIGENCE 4 — AFFICHAGE DISTINCT DES SOURCES L0 ET HISTORIQUE
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('L2-1.4a [comportemental] source L0 → badge « Officielle complète »',
      (tester) async {
    final key = _cleNeuve();
    _semerShard(<String, List<List<int>>>{
      key: <List<int>>[
        <int>[5],
        <int>[3],
      ],
    });
    await ArriveeOfficielleService.instance.charger();

    await tester.pumpWidget(_monter(courseKey: key, isTerminee: true));
    await _laisserResoudre(tester);

    final textes = _textes(tester);
    debugPrint('L2-1.4a textes=$textes');

    expect(textes, contains('Officielle complète'),
        reason: 'une arrivée issue de L0 doit être signalée comme telle');
    expect(textes, isNot(contains('Résultat historique')),
        reason: 'les deux sources ne doivent jamais être confondues');
    expect(textes, contains('N°5'));
    expect(textes, contains('N°3'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('L2-1.4b [comportemental] repli IA → badge « Résultat historique »',
      (tester) async {
    final key = _cleNeuve();
    // L0 ne possède RIEN pour cette clé ; seul un pronostic IA existe.
    await IaMemoryService.instance.recharger();
    final p = IaPronostic(
      courseKey: key,
      nomCourse: 'PRIX TEST',
      hippodrome: 'VINCENNES',
      discipline: 'Trot Attelé',
      datePronostic: _heurePassee,
      scoresIA: const <String, double>{'5': 80.0, '3': 70.0},
      scoresCriteres: const <String, ScoresCriteres>{},
      resultatsReels: true,
      arriveeReelle: const <int>[5, 3],
    );
    _store.semer('ia_pronostics_v2', <String>[jsonEncode(p.toJson())]);
    await IaMemoryService.instance.recharger();

    // TÉMOIN : L0 est bien vide pour cette clé.
    expect(ArriveeOfficielleService.instance.arrivee(key), isNull,
        reason: 'TÉMOIN : sans L0 vide, le repli ne serait pas exercé');

    await tester.pumpWidget(_monter(courseKey: key, isTerminee: true));
    await _laisserResoudre(tester);

    final textes = _textes(tester);
    debugPrint('L2-1.4b textes=$textes');

    expect(textes, contains('Résultat historique'),
        reason: 'une arrivée issue du repli IA doit être distinguée de L0');
    expect(textes, isNot(contains('Officielle complète')));
    expect(textes, contains('N°5'));
    expect(textes, contains('N°3'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('L2-1.4c [comportemental] ex æquo rendus avec « = » entre numéros',
      (tester) async {
    final key = _cleNeuve();
    _semerShard(<String, List<List<int>>>{
      key: <List<int>>[
        <int>[4, 7],
        <int>[2],
      ],
    });
    await ArriveeOfficielleService.instance.charger();

    await tester.pumpWidget(_monter(courseKey: key, isTerminee: true));
    await _laisserResoudre(tester);

    final textes = _textes(tester);
    debugPrint('L2-1.4c textes=$textes');

    // Rendu attendu : N°4 = N°7 · N°2
    expect(textes, contains('N°4'));
    expect(textes, contains('N°7'));
    expect(textes, contains('N°2'));
    expect(textes, contains('='),
        reason: 'le « = » est le marqueur visuel de l\'ex æquo entre 4 et 7');
    expect(textes, contains('·'),
        reason: 'le « · » sépare deux rangs distincts');

    // L'ordre des numéros suit la structure groupée, pas un aplatissement.
    final i4 = textes.indexOf('N°4');
    final iEg = textes.indexOf('=');
    final i7 = textes.indexOf('N°7');
    final i2 = textes.indexOf('N°2');
    debugPrint('L2-1.4c ordre i4=$i4 iEg=$iEg i7=$i7 i2=$i2');
    expect(i4, lessThan(iEg));
    expect(iEg, lessThan(i7));
    expect(i7, lessThan(i2));

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  EXIGENCE 5 — REPLI FONCTIONNEL QUAND L0 N'A PAS L'ARRIVÉE
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('L2-1.5 [comportemental] L0 vide + IA vide → état d\'attente',
      (tester) async {
    final key = _cleNeuve();
    await IaMemoryService.instance.recharger();
    await ArriveeOfficielleService.instance.charger();

    expect(ArriveeOfficielleService.instance.arrivee(key), isNull,
        reason: 'TÉMOIN : L0 vide');
    expect(IaMemoryService.instance.arriveeConnue(key), isNull,
        reason: 'TÉMOIN : IA vide');

    await tester.pumpWidget(_monter(courseKey: key, isTerminee: true));
    await _laisserResoudre(tester);

    final textes = _textes(tester);
    debugPrint('L2-1.5 textes=$textes');

    expect(textes, contains('En attente des résultats PMU...'),
        reason: 'sans source, le widget doit rester en attente — jamais '
            'inventer une arrivée');
    // Aucun badge de provenance : il n'y a pas de provenance.
    expect(textes, isNot(contains('Officielle complète')));
    expect(textes, isNot(contains('Résultat historique')));

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  EXIGENCE 6 — AUCUN APPEL RÉSEAU NI APPRENTISSAGE DEPUIS LE CALENDRIER
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('L2-1.6 [comportemental] sourceL0 + lecture seule → 0 réseau, 0 apprentissage',
      (tester) async {
    final key = _cleNeuve();
    _semerShard(<String, List<List<int>>>{
      key: <List<int>>[
        <int>[5],
        <int>[3],
      ],
    });
    await ArriveeOfficielleService.instance.charger();

    await IaMemoryService.instance.recharger();
    // Pronostic NON résolu : la chaîne d'apprentissage serait atteignable.
    final p = IaPronostic(
      courseKey: key,
      nomCourse: 'PRIX TEST',
      hippodrome: 'VINCENNES',
      discipline: 'Trot Attelé',
      datePronostic: _heurePassee,
      scoresIA: const <String, double>{'5': 80.0, '3': 70.0},
      scoresCriteres: const <String, ScoresCriteres>{},
    );
    _store.semer('ia_pronostics_v2', <String>[jsonEncode(p.toJson())]);
    await IaMemoryService.instance.recharger();

    final mem = IaMemoryService.instance;
    final poidsAvant = jsonEncode(mem.poids.toJson());
    final calibAvant = mem.poids.calibrationScore;
    final nbPronosticsAvant = mem.pronostics.length;
    final clesAvant =
        (await _store.getAllWithParameters(
                GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.'))))
            .keys
            .toList()
          ..sort();

    await _sousReseauSimule(() async {
      await tester.pumpWidget(_monter(
        courseKey: key,
        isTerminee: true,
        sourceL0: true,
        autoriser: false, // ce que fait races_screen depuis R1
      ));
      await _laisserResoudre(tester);
    });

    final poidsApres = jsonEncode(mem.poids.toJson());
    final pronostic = mem.getPronostic(key)!;
    final clesApres =
        (await _store.getAllWithParameters(
                GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.'))))
            .keys
            .toList()
          ..sort();

    debugPrint('L2-1.6 urls=${_urls.length} rapports=$_nbRapports '
        'poidsIdentiques=${poidsAvant == poidsApres} '
        'calibration=$calibAvant→${mem.poids.calibrationScore} '
        'resultatsReels=${pronostic.resultatsReels}');

    expect(_nbRapports, 0, reason: 'aucun appel réseau depuis le calendrier');
    expect(_urls, isEmpty, reason: 'aucune requête HTTP quelle qu\'elle soit');
    expect(poidsApres, poidsAvant,
        reason: '_apprendreParGradient/Discipline/Calibration inchangés');
    expect(mem.poids.calibrationScore, calibAvant);
    expect(pronostic.resultatsReels, isFalse,
        reason: 'la consultation ne résout pas le pronostic');
    expect(pronostic.arriveeReelle, isNull);
    expect(mem.pronostics.length, nbPronosticsAvant);
    expect(clesApres, clesAvant,
        reason: 'aucune clé créée ni supprimée : ni écriture IA ni écriture L0');

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  EXIGENCE 7 — COMPORTEMENT INCHANGÉ QUAND sourceL0 = false
  // ═════════════════════════════════════════════════════════════════════════
  testWidgets('L2-1.7a [comportemental] sourceL0=false → L0 ignoré, badge « Officiel »',
      (tester) async {
    final key = _cleNeuve();
    // L0 contient une arrivée différente de l'IA : si L0 était lu, on verrait
    // N°4/N°7 ; on doit voir N°5/N°3 (chemin historique).
    _semerShard(<String, List<List<int>>>{
      key: <List<int>>[
        <int>[4, 7],
        <int>[2],
      ],
    });
    await ArriveeOfficielleService.instance.charger();

    await IaMemoryService.instance.recharger();
    final p = IaPronostic(
      courseKey: key,
      nomCourse: 'PRIX TEST',
      hippodrome: 'VINCENNES',
      discipline: 'Trot Attelé',
      datePronostic: _heurePassee,
      scoresIA: const <String, double>{'5': 80.0},
      scoresCriteres: const <String, ScoresCriteres>{},
      resultatsReels: true,
      arriveeReelle: const <int>[5, 3],
    );
    _store.semer('ia_pronostics_v2', <String>[jsonEncode(p.toJson())]);
    await IaMemoryService.instance.recharger();

    await tester.pumpWidget(
        _monter(courseKey: key, isTerminee: true, compact: false, sourceL0: false));
    await _laisserResoudre(tester);

    final textes = _textes(tester);
    debugPrint('L2-1.7a textes=$textes');

    expect(textes, contains('N°5'));
    expect(textes, contains('N°3'));
    expect(textes, isNot(contains('N°4')),
        reason: 'L0 ne doit PAS être lu quand sourceL0=false');
    expect(textes, isNot(contains('N°7')));
    expect(textes, contains('Officiel'),
        reason: 'le libellé historique du mode complet est préservé');
    expect(textes, isNot(contains('Officielle complète')),
        reason: 'aucun badge de provenance en mode historique');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('L2-1.7b [comportemental] sourceL0=false compact → rendu identique',
      (tester) async {
    final key = _cleNeuve();
    await IaMemoryService.instance.recharger();
    final p = IaPronostic(
      courseKey: key,
      nomCourse: 'PRIX TEST',
      hippodrome: 'VINCENNES',
      discipline: 'Trot Attelé',
      datePronostic: _heurePassee,
      scoresIA: const <String, double>{'5': 80.0},
      scoresCriteres: const <String, ScoresCriteres>{},
      resultatsReels: true,
      arriveeReelle: const <int>[5, 3, 1],
    );
    _store.semer('ia_pronostics_v2', <String>[jsonEncode(p.toJson())]);
    await IaMemoryService.instance.recharger();

    await tester.pumpWidget(
        _monter(courseKey: key, isTerminee: true, sourceL0: false));
    await _laisserResoudre(tester);

    final textes = _textes(tester);
    debugPrint('L2-1.7b textes=$textes');

    // Libellés d'avant L2-1, à l'identique.
    expect(textes, contains('Arrivée réelle :'));
    expect(textes, contains('N°5'));
    expect(textes, contains('N°3'));
    expect(textes, contains('N°1'));
    expect(textes, isNot(contains('Officielle complète')));
    expect(textes, isNot(contains('Résultat historique')));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('L2-1.7c [comportemental] sourceL0=false → course à venir inchangée',
      (tester) async {
    final key = _cleNeuve();
    await tester.pumpWidget(
        _monter(courseKey: key, isTerminee: false, sourceL0: false));
    await _laisserResoudre(tester);

    final textes = _textes(tester);
    debugPrint('L2-1.7c textes=$textes');
    expect(textes, contains('Course à venir'));

    await tester.pumpWidget(const SizedBox());
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  EXIGENCE 8 — AUCUN CHANGEMENT DES POIDS, SEUILS, PRONOSTICS, RÉSULTATS
  //
  //  Preuve par les sources : L2-1 n'introduit aucune écriture. Les 3 fichiers
  //  touchés sont vérifiés un par un.
  // ═════════════════════════════════════════════════════════════════════════
  test('L2-1.8 [structurel] les 3 fichiers L2-1 n\'écrivent rien dans l\'IA', () {
    const fichiers = <String>[
      'lib/main.dart',
      'lib/widgets/arrivee_reelle_widget.dart',
      'lib/screens/races_screen.dart',
    ];
    // Aucune de ces API ne doit apparaître : ce sont les seules portes
    // d'écriture/apprentissage de l'IA.
    const interdits = <String>[
      'enregistrerResultat(',
      'enregistrerPronostic(',
      '_apprendreParGradient',
      '_mettreAJourCalibration',
      'fetchArriveeDirecte(',
      'relancerRecuperationPMU(',
      '_mettreAJourEloApresArrivee',
    ];

    final rapport = <String>[];
    for (final f in fichiers) {
      // Mesure sur le CODE : l'en-tête du widget cite `fetchArriveeDirecte()`
      // dans sa documentation v9.6, ce qui faussait le comptage (mesuré : 2
      // au lieu de 1 appel réel).
      final src = _codeSansCommentaires(_lire(f));
      for (final i in interdits) {
        final n = i.allMatches(src).length;
        rapport.add('$f :: $i = $n');
        if (f == 'lib/widgets/arrivee_reelle_widget.dart' &&
            i == 'fetchArriveeDirecte(') {
          // Exception DOCUMENTÉE : ce widget contenait déjà cet appel AVANT
          // L2-1 (mécanisme v9.6, neutralisé par R1 via autoriserRecuperation).
          // L2-1 n'en ajoute aucun : on vérifie donc qu'il n'y en a QU'UN.
          expect(n, 1,
              reason: 'l\'unique appel préexistant de v9.6, neutralisé par R1 ; '
                  'L2-1 ne doit pas en ajouter');
          continue;
        }
        expect(n, 0, reason: '$f ne doit pas introduire $i');
      }
    }
    debugPrint('L2-1.8 structurel :\n  ${rapport.join('\n  ')}');
  });

  test('L2-1.8b [structurel] les services IA/PMU/L0-L1 restent intacts', () {
    const proteges = <String>[
      'lib/services/ia_memory_service.dart',
      'lib/services/data_refresh_service.dart',
      'lib/services/arrivee_officielle_service.dart',
      'lib/services/zone_turf_service.dart',
      'lib/services/backup_service.dart',
      'lib/services/alert_service.dart',
      'lib/services/ia_memory_models.dart',
    ];
    final rapport = <String>[];
    for (final f in proteges) {
      final src = _lire(f);
      final nL0 = 'sourceL0'.allMatches(src).length;
      rapport.add('$f :: sourceL0=$nL0');
      expect(nL0, 0, reason: '$f est protégé : L2-1 ne doit rien y introduire');
      expect(src.trim(), isNotEmpty, reason: 'TÉMOIN : fichier lu non vide');
    }
    debugPrint('L2-1.8b structurel :\n  ${rapport.join('\n  ')}');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  EXIGENCE 9 — NON-RÉGRESSION DU REJEU DES ENTRÉES EN ATTENTE
  // ═════════════════════════════════════════════════════════════════════════
  test('L2-1.9 [comportemental] charger() rejoue la file et la vide', () async {
    final key = _cleNeuve();
    // File d'attente persistée, sans shard correspondant : état exact d'un
    // arrêt brutal entre l'étape 2 et l'étape 3 de l'ordre d'écriture.
    //
    // FORMAT RÉEL, lu dans `_decoderFile` (arrivee_officielle_service.dart:896) :
    //   base64(gzip(json)) de {'v':1, 'arrivees': [ {courseKey, rangs}, … ]}
    // `arrivees` est une LISTE (et non une map) : c'est la seule forme qui
    // porte `courseKey`, donc la seule rejouable. Encoder autre chose ferait
    // de ce test une preuve vide.
    final payloadFile = <String, dynamic>{
      'v': kArriveePendingVersion,
      'arrivees': <dynamic>[
        <String, dynamic>{
          'courseKey': key,
          'rangs': <List<int>>[
            <int>[6],
            <int>[2],
          ],
        },
      ],
    };
    _store.semer(
      kArriveePendingKey,
      base64Encode(gzip.encode(utf8.encode(jsonEncode(payloadFile)))),
    );

    // TÉMOIN DE FORMAT : on relit ce qu'on vient d'écrire avec le MÊME schéma
    // que le décodeur de production (base64 → gzip → JSON, `arrivees` = liste
    // d'objets portant `courseKey`). On ne prétend pas appeler `_decoderFile`
    // (privé) : la preuve réelle du bon format est le résultat du test —
    // si le format était faux, la file serait jugée illisible, `nbEntrees`
    // resterait à 0 et les assertions ci-dessous échoueraient.
    final relu = json.decode(utf8.decode(
        gzip.decode(base64Decode(_store.lire(kArriveePendingKey) as String))));
    expect(relu['v'], kArriveePendingVersion);
    expect(relu['arrivees'], isA<List<dynamic>>());
    expect((relu['arrivees'] as List<dynamic>).single['courseKey'], key);

    final svc = ArriveeOfficielleService.instance;
    expect(svc.nbEnAttente, 0, reason: 'TÉMOIN : RAM vide avant chargement');

    await svc.charger();

    debugPrint('L2-1.9 après charger : nbEnAttente=${svc.nbEnAttente} '
        'nbEntrees=${svc.nbEntrees} file=${_store.aFileEnAttente} '
        'shards=${_store.clesShards}');

    // Le rejeu a bien eu lieu : l'entrée est maintenant dans un shard.
    expect(svc.nbEntrees, 1,
        reason: 'le rejeu doit ranger l\'entrée en attente dans son shard');
    expect(svc.arrivee(key), equals(<List<int>>[
      <int>[6],
      <int>[2],
    ]));
    expect(_store.clesShards, hasLength(1),
        reason: 'un shard mensuel a été écrit par le rejeu');
    expect(svc.nbEnAttente, 0,
        reason: 'le rejeu réussi vide la file');
    expect(_store.aFileEnAttente, isFalse,
        reason: 'la file persistée est supprimée une fois vidée');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  CARACTÉRISATION DE L'ANOMALIE — CORRIGÉE PAR LE LOT B-2 bis
  //
  //  ⚠️ CE TEST DOCUMENTAIT UN DÉFAUT ; IL VÉRIFIE DÉSORMAIS SA CORRECTION.
  //
  //  `ZoneTurfService.chargerResultatsCourseComplet` construisait
  //  `Map<int,int> rangParNumero` et affectait `rangParNumero[rangInt] = num`.
  //  Deux chevaux au MÊME rang partageaient la même clé : le second écrasait
  //  le premier, et l'arrivée retournée PERDAIT un ex æquo.
  //
  //  Le lot B-2 bis remplace cette Map par `Map<int,List<int>> rangsGroupes`,
  //  dont l'affectation est un AJOUT (`putIfAbsent(...).add(num)`). Le cheval
  //  ex æquo n'est plus perdu.
  //
  //  Double emploi volontaire de ce test :
  //    1. il atteste l'état CORRIGÉ ([4,7,2] — les 3 chevaux, aucun perdu) ;
  //    2. il ÉCHOUERAIT si l'écrasement était réintroduit : l'ancien code
  //       rendait `[7,2]`, et les assertions ci-dessous l'excluent
  //       explicitement (`isNot(equals(<int>[7, 2]))`, `contains(4)`).
  //  C'est donc à la fois une preuve de correction et un garde-fou de
  //  non-régression sur ce chemin précis.
  // ═════════════════════════════════════════════════════════════════════════
  test('L2-X [corrigé par B-2 bis] les ex æquo ne sont plus écrasés par Map',
      () async {
    final client = MockClient((request) async {
      if (request.url.path.contains('participants')) {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'participants': <dynamic>[
              // 4 et 7 ex æquo au rang 1 ; 2 au rang 2.
              <String, dynamic>{
                'numPmu': 4,
                'statut': 'PARTANT',
                'ordreArrivee': 1,
              },
              <String, dynamic>{
                'numPmu': 7,
                'statut': 'PARTANT',
                'ordreArrivee': 1,
              },
              <String, dynamic>{
                'numPmu': 2,
                'statut': 'PARTANT',
                'ordreArrivee': 2,
              },
            ],
          }),
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });

    final resultat = await http.runWithClient(
      () => ZoneTurfService.chargerResultatsCourseComplet(
        heureDepart: _heurePassee,
        numReunion: 1,
        numCourse: 1,
      ),
      () => client,
    );

    debugPrint('L2-X ÉTAT CORRIGÉ : arrivée retournée = '
        '${resultat?.arriveeOfficielle} (attendu : [4, 7, 2], 4 conservé)');

    expect(resultat, isNotNull);
    // ÉTAT CORRIGÉ : les DEUX ex æquo du rang 1 sont restitués, puis le rang 2.
    expect(resultat!.arriveeOfficielle, equals(<int>[4, 7, 2]),
        reason: 'le N°4 et le N°7 sont ex æquo au rang 1 : les deux doivent '
            'figurer, dans l\'ordre publié par l\'API, suivis du N°2 (rang 2). '
            'La Map<int,int> qui écrasait l\'un des deux a été remplacée par '
            'Map<int,List<int>> au lot B-2 bis.');
    expect(resultat.arriveeOfficielle, hasLength(3),
        reason: '3 chevaux classés, 3 chevaux restitués');
    expect(resultat.arriveeOfficielle, contains(4),
        reason: 'GARDE-FOU : le N°4 ne doit plus jamais être perdu');
    expect(resultat.arriveeOfficielle, isNot(equals(<int>[7, 2])),
        reason: 'GARDE-FOU : [7, 2] est l\'ancien résultat fautif. S\'il '
            'réapparaît, l\'écrasement a été réintroduit.');
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  TABLE DE CORRESPONDANCE EXIGENCES → TESTS
//
//    1. Init L0 avant premier affichage ... L2-1.1a (STRUCTUREL)
//                                            L2-1.1b (comportemental)
//    2. Relecture des arrivées stockées .... L2-1.2
//    3. Ex æquo conservés ................. L2-1.3
//    4. Sources L0 / historique distinctes  L2-1.4a, 4b, 4c
//    5. Repli si L0 vide .................. L2-1.5
//    6. Aucun réseau ni apprentissage ..... L2-1.6
//    7. Autres écrans inchangés ........... L2-1.7a, 7b, 7c
//    8. Poids/seuils/pronostics intacts ... L2-1.8 (STRUCTUREL), 8b
//    9. Rejeu en attente non régressé ..... L2-1.9
//    +  Anomalie ex æquo des paris ........ L2-X (caractérisation)
//
//  LIMITES DE COUVERTURE — énoncées, non masquées :
//    • Aucun test n'exécute `main()` : l'initialisation est prouvée par
//      L2-1.1a (position dans la source) + L2-1.1b (nécessité mesurée).
//      Ce n'est pas un test d'intégration du démarrage.
//    • `races_screen` n'est pas monté (il exige `DataRefreshService`).
//      Le branchement `sourceL0: true` est vérifié par lecture de source
//      dans L2-1.8 : je n'ai pas ajouté de test structurel dédié à cette
//      ligne, la preuve est ici une simple recherche de chaîne.
//    • Les ex æquo ne sont prouvés QUE sur le chemin L0. Le chemin des paris
//      (zone_turf_service) les détruit — c'est L2-X, anomalie documentée.
// ═══════════════════════════════════════════════════════════════════════════
