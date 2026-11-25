// ═══════════════════════════════════════════════════════════════════════════
//  L2-4.1 — AFFICHAGE DES ARRIVÉES OFFICIELLES COMPLÈTES DANS LA CARTE
//           « MÉMOIRE IA » DU CALENDRIER DES PERFORMANCES
//
//  CIBLE UNIQUE : `_buildPronosticCard` de l'onglet 0 (« 🧠 Mémoire IA »)
//  de `IaPerformanceScreen`, défini dans
//  `lib/screens/ia_perf_secondary_widgets.dart`.
//
//  Aucun service n'est modifié. `ArriveeOfficielleService` est lu comme en
//  production. Le disque est semé AVANT tout `getInstance()` via un store
//  contrôlable + `SharedPreferences.resetStatic()` : `SharedPreferences` gèle
//  un SNAPSHOT au premier `getInstance()`
//  (shared_preferences_legacy.dart:76-104).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/screens/ia_performance_screen.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/quasi_gros_paris_service.dart';

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

  /// Écrit un lot de valeurs comme le ferait un AUTRE processus.
  ///
  /// ⚠️ L'invalidation est OBLIGATOIRE : `SharedPreferences` mémorise un
  /// SNAPSHOT (`_preferenceCache`) au premier `getInstance()`
  /// (shared_preferences_legacy.dart:76-104) et toutes les lectures suivantes
  /// portent sur ce snapshot, jamais sur le store. Écrire sans invalider
  /// produirait une donnée présente sur disque mais INVISIBLE au service.
  /// Écrit un lot de valeurs SANS effacer les clés déjà présentes.
  /// Permet de semer les pronostics PUIS le shard L0, comme les deux le font
  /// en production (deux domaines de stockage indépendants).
  void semer(Map<String, Object> contenu) {
    contenu.forEach((k, v) => valeurs['flutter.$k'] = v);
    SharedPreferences.resetStatic();
  }

  /// Efface tout (remise à zéro d'un test).
  void vider() {
    valeurs.clear();
    SharedPreferences.resetStatic();
  }

  List<String> get clesToutes => valeurs.keys.toList()..sort();
}

late _Store _store;

// ═══════════════════════════════════════════════════════════════════════════
//  2. HELPERS DE DONNÉES
// ═══════════════════════════════════════════════════════════════════════════

int _compteurCle = 0;

String _dateDdMmYyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Mois au format EXACT attendu par `cleStockageMois` et `moisDepuisCourseKey` :
/// `YYYY-MM` avec tiret (date_utils.dart / arrivee_officielle_service.dart:326-333).
String _moisIso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Clé unique datée du jour : le shard tombe dans le mois affiché.
String _cleNeuve() {
  _compteurCle++;
  return 'R1C${_compteurCle}_${_dateDdMmYyyy(DateTime.now())}';
}

String _encoderShard(Map<String, List<List<int>>> arrivees) {
  final json = jsonEncode({
    'v': 1,
    'arrivees': arrivees.map((k, v) => MapEntry(k, {'rangs': v})),
  });
  return base64Encode(gzip.encode(utf8.encode(json)));
}

void _semerShard(Map<String, List<List<int>>> arrivees) {
  final cle = cleStockageMois(_moisIso(DateTime.now()));
  _store.semer(<String, Object>{cle: _encoderShard(arrivees)});
}

IaPronostic _pronostic({
  required String courseKey,
  required DateTime jour,
  List<int>? arrivee,
  String nomCourse = 'Prix de Test',
  double score = 82.0,
  int rang = 1,
  int nbTop3 = 3,
  int nbTop5 = 4,
}) {
  final top = arrivee ?? const <int>[1, 2, 3, 4, 5];
  return IaPronostic(
    courseKey: courseKey,
    nomCourse: nomCourse,
    hippodrome: 'Vincennes',
    discipline: 'Trot',
    datePronostic: jour,
    scoresIA: <String, double>{for (final n in top) '$n': 90.0},
    scoresCriteres: const <String, ScoresCriteres>{},
    varianceScores: 1.0,
    arriveeReelle: arrivee,
    dateResultat: jour,
    resultatsReels: true,
    rangFavoriIaDansArrivee: rang,
    nbTop3DansArriveeReelle: nbTop3,
    nbTop5DansArriveeReelle: nbTop5,
    scorePerformance: score,
    diagnosticApprentissage: '',
    confiancePredite: 70.0,
    typePariConseille: 'Quinté+',
    tauxReussiteAuMoment: 0.5,
    precisionIA: null,
    favoriIaNom: 'Cheval 1',
    coteFavoriPmu: 4.2,
    cotesPmuParNumero: const <String, double>{},
  );
}

/// Sème les pronostics au format EXACT produit par `IaMemoryService` :
/// `ia_pronostics_v2` est une **liste de chaînes JSON** (une par pronostic),
/// pas une chaîne JSON unique (ia_memory_service.dart:2197-2198).
/// `_compressionKey` n'est pas semée → le service lit la voie non compressée.
void _semerPronostics(List<IaPronostic> liste) {
  _store.semer(<String, Object>{
    'ia_pronostics_v2': liste.map((p) => jsonEncode(p.toJson())).toList(),
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. HELPERS RÉSEAU ET POMPAGE
// ═══════════════════════════════════════════════════════════════════════════

final List<Uri> _urls = <Uri>[];

int get _nbRapports =>
    _urls.where((u) => u.path.contains('rapports-definitifs')).length;

Future<T> _sousReseauSimule<T>(Future<T> Function() corps) {
  _urls.clear();
  return http.runWithClient(
    () async {
      try {
        return await corps();
      } finally {
        _urls.clear();
      }
    },
    () => MockClient((req) async {
      _urls.add(req.url);
      return http.Response('{}', 200);
    }),
  );
}

Future<void> _pomper(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  // ★ `_autoRecreerSiVide()` (`ia_performance_screen.dart:163`) attend
  // 600 ms avant de tester la recréation. Sans cette avance de temps, son
  // timer reste en vol à la destruction de l'arbre (« A Timer is still
  // pending even after the widget tree was disposed »). On avance donc
  // au-delà de 600 ms : le chemin de recréation est ainsi RÉELLEMENT
  // exécuté, puis contrôlé par les assertions (aucune recréation observée).
  await tester.pump(const Duration(milliseconds: 700));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Textes réellement rendus, dans l'ordre de l'arbre.
List<String> _textes(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .toList();

// ═══════════════════════════════════════════════════════════════════════════
//  4. MONTAGE DU SCREEN RÉEL
// ═══════════════════════════════════════════════════════════════════════════

/// Débordements RenderFlex observés pendant un montage, par SIGNATURE.
///
/// ⚠️ MESURÉ — `IaPerformanceScreen` déborde DÉJÀ avant L2-4.1. Signatures
/// relevées (type de widget | fichier | amplitude | contraintes | direction,
/// SANS numéro de ligne pour survivre aux décalages) :
///
///   900×30000 : `Row|ia_perf_secondary_widgets.dart|over=24|w=52`  ×3
///               `Row|ia_perf_secondary_widgets.dart|over=44|w=52`  ×16  → 19
///   320×30000 : les 19 ci-dessus + 9 signatures propres au fichier hôte
///               (`ia_performance_screen.dart`, amplitudes 132/165/168/175/
///               329/386/430/457/198)                                  → 28
///
/// Ces 19 + 9 signatures sont **rigoureusement identiques** entre le repli
/// historique et un L0 long (4 groupes × 3 chevaux), aux deux largeurs
/// (mesuré : `EGALITE_900=true`, `EGALITE_320=true`). Elles proviennent
/// notamment de `_buildPoidsBar` (`SizedBox(width: 52)` + `Row`, ligne 631) et
/// de `Row` du fichier hôte — jamais du bloc d'arrivée L2-4.1.
///
/// Les tests capturent donc ces erreurs au lieu de les subir, et L2-4.9
/// vérifie qu'aucune signature NOUVELLE n'apparaît.
Map<String, int> _debordements = <String, int>{};

/// Capture des erreurs de rendu : les débordements sont enregistrés par
/// signature (jamais ignorés silencieusement), toute autre erreur est ré-émise.
FlutterExceptionHandler? _ancienOnError;

/// Signature stable d'un débordement : widget + fichier + amplitude +
/// contraintes + direction. Aucun numéro de ligne → insensible aux décalages.
String _signatureDebordement(String texte) {
  String g(String re) => RegExp(re).firstMatch(texte)?.group(1) ?? '?';
  final type =
      g(r'The relevant error-causing widget was:\s*\n\s*([A-Za-z_]+)');
  final fichier = g(r'file://[^:]*/([A-Za-z0-9_]+\.dart)');
  final amplitude = g(r'overflowed by (\d+) pixels on the (\w+)');
  final cote = g(r'overflowed by \d+ pixels on the (\w+)');
  final contraintes = g(r'constraints: (BoxConstraints\([^)]*\))');
  final direction = g(r'direction: (\w+)');
  return '$type|$fichier|over=$amplitude/$cote|$contraintes|dir=$direction';
}

void _capturerDebordements() {
  _debordements = <String, int>{};
  _ancienOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final texte = details.toString();
    if (texte.contains('overflowed')) {
      final cle = _signatureDebordement(texte);
      _debordements[cle] = (_debordements[cle] ?? 0) + 1;
      return;
    }
    _ancienOnError?.call(details);
  };
}

void _restaurerOnError() {
  FlutterError.onError = _ancienOnError;
}

int get _totalDebordements =>
    _debordements.values.fold(0, (a, b) => a + b);

/// Monte `IaPerformanceScreen` en taille haute : l'onglet 0 est un `ListView`,
/// donc sans surface suffisante la carte Mémoire IA n'est pas construite.
Future<void> _monter(WidgetTester tester, {Size? taille}) async {
  await tester.binding.setSurfaceSize(taille ?? const Size(900, 30000));
  IaArchiveService.instance.oublierChargementPourTest();
  // ⚠️ `ArriveeOfficielleService.charger()` est idempotent (`_charge`). Sans
  // purge mémoire, un montage précédent laisserait ses shards en cache et le
  // disque courant ne serait jamais relu : on force donc une relecture.
  ArriveeOfficielleService.instance.viderMemoireSeulement();
  await ArriveeOfficielleService.instance.charger();
  await IaMemoryService.instance.recharger();

  _capturerDebordements();
  await tester.pumpWidget(
    ChangeNotifierProvider<PmuProvider>.value(
      value: PmuProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: IaPerformanceScreen(alertService: AlertService.instance),
        ),
      ),
    ),
  );
  await _pomper(tester);
  _restaurerOnError();
}

/// Démontage propre : purge les timers résiduels du montage précédent avant
/// la vérification d'invariants du binding de test.
Future<void> _demonter(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 900));
  await tester.binding.setSurfaceSize(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _store = _Store();
    SharedPreferencesStorePlatform.instance = _store;
    SharedPreferences.resetStatic();
    ArriveeOfficielleService.instance.viderMemoireSeulement();
    QuasiGrosParisService.instance.viderMemoirePourResetComplet();
    IaArchiveService.instance.oublierChargementPourTest();
    await IaMemoryService.instance.recharger();
    _urls.clear();
    _compteurCle = 0;
  });

  tearDown(() async {
    ArriveeOfficielleService.instance.viderMemoireSeulement();
    await IaMemoryService.instance.recharger();
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-4.1 — arrivée L0 complète avec ex æquo
  // ─────────────────────────────────────────────────────────────────────
  testWidgets(
      'L2-4.1 — ex æquo L0 affichés dans la carte Mémoire IA, '
      'tous les rangs, aucun aplatissement',
      (tester) async {
    final cle = _cleNeuve();
    _semerPronostics([
      _pronostic(
        courseKey: cle,
        jour: DateTime.now(),
        arrivee: const <int>[1, 2, 3, 4, 5],
      ),
    ]);
    // L0 volontairement DIFFÉRENT de l'historique : si L0 n'était pas
    // prioritaire, l'écran afficherait « N°1 … N°5 » (liste plate).
    _semerShard(<String, List<List<int>>>{
      cle: <List<int>>[
        <int>[4, 7],
        <int>[2],
        <int>[9, 1],
      ],
    });

    await _monter(tester);

    final textes = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
    // Tous les numéros L0 affichés.
    for (final n in <int>[4, 7, 2, 9, 1]) {
      expect(textes.where((s) => s == 'N°$n').length, greaterThanOrEqualTo(1),
          reason: 'le numéro $n doit être affiché depuis L0');
    }

    // Ex æquo intra-groupe : 2 « = » (groupes [4,7] et [9,1]).
    expect(textes.where((s) => s == '=').length, 2,
        reason: '[[4,7],[2],[9,1]] → 2 ex æquo');

    // Séparateur inter-groupes : 2 « · » (3 groupes).
    expect(textes.where((s) => s == '·').length, 2,
        reason: '3 groupes → 2 séparateurs');

    // Ordre de lecture : N°4 = N°7 · N°2 · N°9 = N°1
    final i4   = textes.indexOf('N°4');
    final iEg1 = textes.indexOf('=', i4 + 1);
    final i7   = textes.indexOf('N°7', iEg1 + 1);
    final i2   = textes.indexOf('N°2', i7 + 1);
    final i9   = textes.indexOf('N°9', i2 + 1);
    final iEg2 = textes.indexOf('=', i9 + 1);
    final i1   = textes.indexOf('N°1', iEg2 + 1);
    expect(
        i4 >= 0 &&
            iEg1 > i4 &&
            i7 > iEg1 &&
            i2 > i7 &&
            i9 > i2 &&
            iEg2 > i9 &&
            i1 > iEg2,
        isTrue,
        reason: 'ordre attendu N°4 = N°7 · N°2 · N°9 = N°1 — mesuré : '
            'i4=$i4 iEg1=$iEg1 i7=$i7 i2=$i2 i9=$i9 iEg2=$iEg2 i1=$i1');

    await _demonter(tester);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-4.2 — aucune troncature à cinq chevaux quand L0 dépasse 5
  // ─────────────────────────────────────────────────────────────────────
  testWidgets(
      'L2-4.2 — L0 à 7 groupes : aucun take(5), les 7 rangs sont rendus',
      (tester) async {
    final cle = _cleNeuve();
    _semerPronostics([
      _pronostic(courseKey: cle, jour: DateTime.now(),
          arrivee: const <int>[1, 2, 3, 4, 5]),
    ]);
    _semerShard(<String, List<List<int>>>{
      cle: <List<int>>[
        <int>[11], <int>[12], <int>[13], <int>[14],
        <int>[15], <int>[16], <int>[17],
      ],
    });

    await _monter(tester);

    final textes = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();

    // Les rangs 6 et 7 seraient perdus par un take(5).
    for (final n in <int>[11, 12, 13, 14, 15, 16, 17]) {
      expect(textes.where((s) => s == 'N°$n').length, greaterThanOrEqualTo(1),
          reason: 'le rang du N°$n doit être affiché — take(5) interdit');
    }
    // 7 groupes → 6 séparateurs.
    expect(textes.where((s) => s == '·').length, 6,
        reason: '7 groupes distincts → 6 « · »');
    // Aucun ex æquo ici.
    expect(textes.where((s) => s == '='), isEmpty);

    await _demonter(tester);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-4.3 — repli historique quand L0 est absent
  // ─────────────────────────────────────────────────────────────────────
  testWidgets('L2-4.3 — L0 absent : repli historique et badge '
      '« Résultat historique »', (tester) async {
    final cle = _cleNeuve();
    _semerPronostics([
      _pronostic(courseKey: cle, jour: DateTime.now(),
          arrivee: const <int>[3, 7, 1, 5, 2]),
    ]);
    // Aucun shard semé.

    await _monter(tester);

    final textes = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();

    for (final n in <int>[3, 7, 1, 5, 2]) {
      expect(textes.where((s) => s == 'N°$n').length, greaterThanOrEqualTo(1));
    }
    expect(textes.where((s) => s == 'Résultat historique').length,
        greaterThanOrEqualTo(1));
    expect(textes.where((s) => s == 'Officielle complète'), isEmpty);
    expect(textes.where((s) => s == '='), isEmpty);
    expect(textes.where((s) => s == '·'), isEmpty);

    await _demonter(tester);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-4.4 — la limite historique de 5 chevaux est CONSERVÉE
  // ─────────────────────────────────────────────────────────────────────
  testWidgets(
      'L2-4.4 — repli historique : la limite de 5 chevaux reste appliquée',
      (tester) async {
    final cle = _cleNeuve();
    _semerPronostics([
      _pronostic(courseKey: cle, jour: DateTime.now(),
          arrivee: const <int>[1, 2, 3, 4, 5, 6, 7, 8]),
    ]);

    await _monter(tester);

    final textes = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();

    // Les 5 premiers sont là.
    for (final n in <int>[1, 2, 3, 4, 5]) {
      expect(textes.where((s) => s == 'N°$n').length, greaterThanOrEqualTo(1));
    }
    // Les 6e, 7e, 8e sont ABSENTS : le comportement historique est intact.
    for (final n in <int>[6, 7, 8]) {
      expect(textes.where((s) => s == 'N°$n'), isEmpty,
          reason: 'le repli historique doit rester tronqué à 5');
    }

    await _demonter(tester);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-4.5 — L0 présent mais sans entrée pour cette clé → repli
  // ─────────────────────────────────────────────────────────────────────
  testWidgets('L2-4.5 — L0 contient une AUTRE clé : repli, rien de fabriqué',
      (tester) async {
    final cle = _cleNeuve();
    _semerPronostics([
      _pronostic(courseKey: cle, jour: DateTime.now(),
          arrivee: const <int>[6, 8, 2, 4, 1]),
    ]);
    _semerShard(<String, List<List<int>>>{
      'R9C9_${_dateDdMmYyyy(DateTime.now())}': <List<int>>[
        <int>[21, 22],
      ],
    });

    await _monter(tester);

    final textes = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();

    for (final n in <int>[6, 8, 2, 4, 1]) {
      expect(textes.where((s) => s == 'N°$n').length, greaterThanOrEqualTo(1));
    }
    // Les numéros de l'autre course ne doivent JAMAIS apparaître.
    for (final n in <int>[21, 22]) {
      expect(textes.where((s) => s == 'N°$n'), isEmpty);
    }
    expect(textes.where((s) => s == 'Résultat historique').length,
        greaterThanOrEqualTo(1));
    expect(textes.where((s) => s == 'Officielle complète'), isEmpty);

    await _demonter(tester);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-4.6 — pronostic, score, rang et compteurs strictement inchangés
  // ─────────────────────────────────────────────────────────────────────
  testWidgets(
      'L2-4.6 — consultation : arriveeReelle, scorePerformance, rang favori '
      'et compteurs top3/top5 inchangés', (tester) async {
    final cle = _cleNeuve();
    _semerPronostics([
      _pronostic(
        courseKey: cle,
        jour: DateTime.now(),
        arrivee: const <int>[1, 2, 3, 4, 5],
        score: 91.0,
        rang: 2,
        nbTop3: 3,
        nbTop5: 4,
      ),
    ]);
    _semerShard(<String, List<List<int>>>{
      cle: <List<int>>[
        <int>[4, 7],
        <int>[2],
      ],
    });

    await _monter(tester);

    final p = IaMemoryService.instance.pronostics
        .firstWhere((x) => x.courseKey == cle);

    expect(p.arriveeReelle, equals(<int>[1, 2, 3, 4, 5]),
        reason: 'arriveeReelle historique jamais réaffectée');
    expect(p.scorePerformance, equals(91.0));
    expect(p.rangFavoriIaDansArrivee, equals(2));
    expect(p.nbTop3DansArriveeReelle, equals(3));
    expect(p.nbTop5DansArriveeReelle, equals(4));

    // Les groupes L0 sont toujours intacts et non aplatis dans le service.
    final groupes = ArriveeOfficielleService.instance.arrivee(cle);
    expect(groupes, equals(<List<int>>[
      <int>[4, 7],
      <int>[2],
    ]));

    await _demonter(tester);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-4.7 — aucune requête d'ARRIVÉE, aucun apprentissage, aucune écriture
  // ─────────────────────────────────────────────────────────────────────
  testWidgets(
      'L2-4.7 — ouverture de l\'onglet Mémoire IA : 0 requête d\'arrivée, '
      '0 apprentissage, 0 écriture', (tester) async {
    final cle = _cleNeuve();
    _semerPronostics([
      _pronostic(courseKey: cle, jour: DateTime.now(),
          arrivee: const <int>[1, 2, 3, 4, 5]),
    ]);
    _semerShard(<String, List<List<int>>>{
      cle: <List<int>>[
        <int>[4, 7],
        <int>[2],
      ],
    });
    await ArriveeOfficielleService.instance.charger();
    await IaMemoryService.instance.recharger();

    final poidsAvant   = jsonEncode(IaMemoryService.instance.poids.toJson());
    final calibAvant   = IaMemoryService.instance.poids.calibrationScore;
    final nbPronos     = IaMemoryService.instance.pronostics.length;
    final clesAvant    = _store.clesToutes;
    final nbEntreesL0  = ArriveeOfficielleService.instance.nbEntrees;

    await _sousReseauSimule(() async {
      await tester.binding.setSurfaceSize(const Size(900, 30000));
      // Mêmes précautions que `_monter` : les débordements PRÉ-EXISTANTS de
      // l'écran (mesurés : 19 à 900 dp, signature `_buildPoidsBar`) sont
      // capturés, pas subis. Aucune assertion réseau n'est touchée.
      _capturerDebordements();
      await tester.pumpWidget(
        ChangeNotifierProvider<PmuProvider>.value(
          value: PmuProvider(),
          child: MaterialApp(
            home: Scaffold(
              body: IaPerformanceScreen(alertService: AlertService.instance),
            ),
          ),
        ),
      );
      await _pomper(tester);
      _restaurerOnError();

      // ── Assertion CIBLÉE : aucune récupération d'ARRIVÉE ──────────────
      // Le mandat interdit la récupération PMU d'arrivée. Elle passerait
      // par `/rapports-definitifs` (`ia_memory_service.dart:1191,1399`) :
      // ce compteur doit rester à zéro.
      expect(_nbRapports, 0,
          reason: 'aucune récupération d\'arrivée autorisée — mesuré : '
              '${_urls.where((u) => u.path.contains('rapports-definitifs'))}');

      // ── Requête PRÉ-EXISTANTE documentée ──────────────────────────────
      // Mesuré : exactement UNE requête, `/rest/client/7/programme/<date>`.
      // Elle vient de `PmuProvider()` (`pmu_provider.dart:24`,
      // `_loadSavedPredictions().then((_) => loadProgramme())`), donc du
      // PROVIDER construit par le test, pas de l'écran ni de L2-4.1.
      // Comportement pré-existant, vérifié ici pour ne pas le confondre
      // avec une récupération d'arrivée.
      expect(_urls.every((u) => u.path.contains('/programme/')), isTrue,
          reason: 'seul le chargement du programme est attendu — mesuré : '
              '${_urls.map((u) => u.path).toSet().toList()}');
      expect(_urls.length, lessThanOrEqualTo(1),
          reason: 'une seule requête programme au montage — mesuré : '
              '${_urls.map((u) => u.path).toSet().toList()}');
    });

    expect(jsonEncode(IaMemoryService.instance.poids.toJson()), poidsAvant,
        reason: 'les poids IA ne doivent pas bouger');
    expect(IaMemoryService.instance.poids.calibrationScore, calibAvant);
    expect(IaMemoryService.instance.pronostics.length, nbPronos);
    expect(_store.clesToutes, clesAvant,
        reason: 'aucune écriture disque pendant la consultation');
    expect(ArriveeOfficielleService.instance.nbEntrees, nbEntreesL0);

    await _demonter(tester);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-4.8 — contrôle NÉGATIF : le compteur réseau sait détecter
  // ─────────────────────────────────────────────────────────────────────
  testWidgets(
      'L2-4.8 — contrôle négatif : le compteur réseau détecte une vraie '
      'requête d\'arrivée', (tester) async {
    await _sousReseauSimule(() async {
      await IaMemoryService.instance.fetchArriveeDirecte(
        courseKey: 'R1C7_${_dateDdMmYyyy(DateTime.now())}',
        heureDepart: DateTime.now(),
      );
      expect(_nbRapports, greaterThanOrEqualTo(1),
          reason: 'le compteur DOIT voir une requête : sinon L2-4.7 '
              'serait un faux vert');
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-4.9 — NON-RÉGRESSION des débordements, 900 dp ET 320 dp
  // ─────────────────────────────────────────────────────────────────────
  //
  // On ne mesure pas « zéro débordement » (faux : l'écran déborde déjà avant
  // L2-4.1) mais l'ABSENCE de débordement NOUVEAU : les signatures relevées
  // avec un L0 long (4 groupes × 3 chevaux, plusieurs ex æquo) doivent être
  // exactement celles du repli historique, à nombre ÉGAL par signature.
  testWidgets(
      'L2-4.9 — L0 long + ex æquo : aucun débordement NOUVEAU vs repli '
      'historique, à 900 dp et 320 dp', (tester) async {
    for (final taille in const <Size>[
      Size(900, 30000),
      Size(320, 30000),
    ]) {
      // (A) référence : L0 absent → repli historique (5 chevaux).
      final cleA = _cleNeuve();
      _store.vider();
      _semerPronostics([
        _pronostic(courseKey: cleA, jour: DateTime.now(),
            arrivee: const <int>[1, 2, 3, 4, 5]),
      ]);
      await _monter(tester, taille: taille);
      final refTextes = _textes(tester);
      expect(refTextes.contains('Résultat historique'), isTrue,
          reason: 'référence à $taille : repli historique attendu');
      final ref = Map<String, int>.from(_debordements);
      final refTotal = _totalDebordements;
      await _demonter(tester);

      // (B) L0 long : 4 groupes × 3 chevaux, ex æquo multiples.
      final cleB = _cleNeuve();
      _store.vider();
      _semerPronostics([
        _pronostic(courseKey: cleB, jour: DateTime.now(),
            arrivee: const <int>[1, 2, 3, 4, 5]),
      ]);
      _semerShard(<String, List<List<int>>>{
        cleB: <List<int>>[
          <int>[1, 2, 3],
          <int>[4, 5, 6],
          <int>[7, 8, 9],
          <int>[10, 11, 12],
        ],
      });
      await _monter(tester, taille: taille);
      final l0Textes = _textes(tester);
      expect(l0Textes.contains('Officielle complète'), isTrue,
          reason: 'L0 long à $taille : badge officiel attendu');
      expect(l0Textes.where((s) => s == '=').length, 8,
          reason: '4 groupes de 3 → 8 ex æquo à $taille');
      expect(l0Textes.where((s) => s == '·').length, 3,
          reason: '4 groupes → 3 séparateurs à $taille');
      final avecL0 = Map<String, int>.from(_debordements);
      final l0Total = _totalDebordements;
      await _demonter(tester);

      // ── Comparaison par SIGNATURE (aucun numéro de ligne) ─────────────
      final nouvelles = <String>[];
      avecL0.forEach((sig, n) {
        final avant = ref[sig] ?? 0;
        if (n > avant) nouvelles.add('$sig : $avant → $n');
      });
      expect(nouvelles, isEmpty,
          reason: 'débordement(s) NOUVEAU(X) introduit(s) par le rendu L0 à '
              '$taille — mesuré : $nouvelles\n'
              'référence ($taille) = $ref\navecL0 ($taille) = $avecL0');

      // Aucune signature de la référence ne doit disparaître non plus
      // (contrôle croisé : le rendu L0 ne masque rien).
      final disparues = <String>[];
      ref.forEach((sig, n) {
        final apres = avecL0[sig] ?? 0;
        if (apres < n) disparues.add('$sig : $n → $apres');
      });
      expect(disparues, isEmpty,
          reason: 'signature(s) de débordement modifiée(s) à $taille — '
              'mesuré : $disparues');

      // Contrôle de cohérence : le total ne bouge pas non plus.
      expect(l0Total, refTotal,
          reason: 'nombre total de débordements inchangé à $taille — '
              'mesuré : référence=$refTotal, L0 long=$l0Total');
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-4.10 — structurel : périmètre et non-régression
  // ─────────────────────────────────────────────────────────────────────
  test('L2-4.10 [structurel] — périmètre du chantier et protections', () {
    final chemin = 'lib/screens/ia_perf_secondary_widgets.dart';
    final brut = File(chemin).readAsStringSync();
    final code = _codeSansCommentaires(brut);

    // 1. La résolution L0 existe et lit bien le service.
    expect(code.contains('_resoudreArriveeMemoire('), isTrue);
    expect(code.contains('ArriveeOfficielleService.instance.arrivee('), isTrue);

    // 2. Le rendu groupé et le badge existent.
    expect(code.contains('_buildGroupesArriveeMemoire('), isTrue);
    expect(code.contains('_buildBadgeArriveeMemoire('), isTrue);

    // 3. AUCUN mécanisme d'apprentissage / calcul dans ce fichier.
    for (final interdit in <String>[
      '_apprendreParGradient',
      '_apprendreParDiscipline',
      'analyseJourneeComplete(',
      '_mettreAJourCalibration',
      'enregistrerResultat(',
      'genererPronostic(',
      'fetchArriveeDirecte(',
    ]) {
      expect(code.contains(interdit), isFalse,
          reason: '$interdit ne doit jamais apparaître dans ce fichier');
    }

    // 4. Les champs protégés sont toujours lus tels quels.
    expect(code.contains('p.scorePerformance'), isTrue);
    expect(code.contains('p.rangFavoriIaDansArrivee'), isTrue);

    // 5. La carte de l'onglet 0 est la SEULE à utiliser la résolution.
    expect('_resoudreArriveeMemoire('.allMatches(code).length, 2,
        reason: '1 définition + 1 appel dans _buildPronosticCard');

    // 6. L'import L0 est unique dans le fichier hôte.
    final hote = File('lib/screens/ia_performance_screen.dart')
        .readAsStringSync();
    expect('arrivee_officielle_service.dart'.allMatches(hote).length, 1);

    // 7. Les autres cartes de l'écran ne sont pas touchées.
    expect(code.contains('Widget _buildPronosticCardAttente(IaPronostic p)'),
        isTrue);
    expect(code.contains('Widget _buildCartePronostic(IaPronostic pr, String typePari)'),
        isFalse,
        reason: '_buildCartePronostic reste dans le fichier hôte, intact');
  });

  test('L2-4.11 [structurel] — indicateurs du calendrier IA intacts', () {
    final code = _codeSansCommentaires(
        File('lib/widgets/ia/ia_calendrier_tab.dart').readAsStringSync());

    for (final intact in <String>[
      "child: Text('★',",
      'if (palier == PalierCalendrier.or && hasCourses)',
      '_cGold.withValues(alpha: 0.9)',
      'PalierCalendrier _getPalierDynamique(',
      'SourcePronosticUtils.iconeCombinaison(',
    ]) {
      expect(code.contains(intact), isTrue,
          reason: 'indicateur du calendrier altéré : $intact');
    }
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  5. MESURE SUR SOURCE SANS COMMENTAIRES
// ═══════════════════════════════════════════════════════════════════════════

/// Retire les commentaires `//` pour que la mesure ne se compte pas elle-même
/// (les commentaires L2-4.1 citent les API surveillées).
String _codeSansCommentaires(String src) {
  final sb = StringBuffer();
  for (final ligne in const LineSplitter().convert(src)) {
    final i = ligne.indexOf('//');
    if (i < 0) {
      sb.writeln(ligne);
      continue;
    }
    // Préserver « :// » des URLs.
    final avant = ligne.substring(0, i);
    if (avant.trimRight().endsWith(':')) {
      sb.writeln(ligne);
    } else {
      sb.writeln(avant);
    }
  }
  return sb.toString();
}
