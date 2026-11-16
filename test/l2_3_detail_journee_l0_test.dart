// ═══════════════════════════════════════════════════════════════════════════
//  L2-3 — AFFICHAGE DES ARRIVÉES OFFICIELLES COMPLÈTES DANS LE DÉTAIL DE
//         JOURNÉE DU CALENDRIER IA
//
//  PARCOURS RÉEL VÉRIFIÉ PAR LECTURE DE CODE (test L2-3.1) :
//
//    1. `IaCalendrierTab` — stateful, `ia_calendrier_tab.dart:126`
//    2. `_buildCalendrierMensuel` `:874` → `_buildGrille` `:913`
//       → `GestureDetector.onTap` `:944-946`, armé si
//         `!estGris && !estFut && dd != null && dd.nbCourses > 0`
//    3. `_ouvrirDetailJour(context, dd, moisRef)` `:2459-2470`
//       → `showModalBottomSheet`
//    4. `_DetailJourSheet` `:2583` — `StatelessWidget`
//    5. `_buildPronosticCard` `:2804+` — carte d'un pronostic gagnant,
//       appelée UNIQUEMENT depuis `_DetailJourSheet.build` `:2702`
//
//  L2-3 intervient EXCLUSIVEMENT au point 5.
//
//  Aucun service n'est modifié. `ArriveeOfficielleService` est lu comme en
//  production. Le disque est semé AVANT tout `getInstance()` via un store
//  contrôlable + `SharedPreferences.resetStatic()` — `SharedPreferences`
//  gèle un SNAPSHOT au premier `getInstance()`
//  (shared_preferences_legacy.dart:76-104), toute écriture postérieure est
//  invisible sans invalidation.
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
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/quasi_gros_paris_service.dart';
import 'package:pronostic_hippique/widgets/ia/ia_calendrier_tab.dart';

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

  void semer(String cle, Object valeur) {
    valeurs['flutter.$cle'] = valeur;
    SharedPreferences.resetStatic();
  }

  void retirer(String cle) {
    valeurs.remove('flutter.$cle');
    SharedPreferences.resetStatic();
  }

  List<String> get clesToutes => valeurs.keys
      .map((k) => k.startsWith('flutter.') ? k.substring(8) : k)
      .toList()
    ..sort();
}

late _Store _store;

// ═══════════════════════════════════════════════════════════════════════════
//  2. DATES ET CLÉS DE COURSE
// ═══════════════════════════════════════════════════════════════════════════

int _compteur = 0;

String get _dateDdMmYyyy {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

String get _moisIso {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}';
}

/// courseKey neuve, datée d'AUJOURD'HUI : le shard tombe dans le mois
/// affiché par défaut et le pronostic dans les agrégats du mois courant.
String _cleNeuve() {
  _compteur++;
  return 'R1C$_compteur' '_$_dateDdMmYyyy';
}

/// Encode un shard mensuel exactement comme `_encoderShard`
/// (arrivee_officielle_service.dart:983-996) :
/// base64(gzip(json)) de `{"v":1,"arrivees":{courseKey:{rangs:[...]}}}`.
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
    cleStockageMois(mois ?? _moisIso),
    _encoderShard(arrivees),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. PRONOSTIC SEMÉ — chemin public JSON → `recharger()`
// ═══════════════════════════════════════════════════════════════════════════

const String _kPronosticsKey = 'ia_pronostics_v2';
const String _kFlagMigration  = 'ia_precision_migrated_v3';

/// Pronostic GAGNANT.
///
/// Règle Tiercé (`_estBonConseilParType`, ia_memory_service.dart:4884) :
/// `top3 >= 2`. On fixe `nbTop3DansArriveeReelle: 3` → le pronostic entre
/// dans `bons` et sa carte est rendue dans le détail de journée.
IaPronostic _pronostic({
  required String courseKey,
  required DateTime jour,
  required List<int> arrivee,
}) =>
    IaPronostic(
      courseKey: courseKey,
      nomCourse: 'Course $courseKey',
      hippodrome: 'Vincennes',
      discipline: 'Trot Attelé',
      datePronostic: jour,
      scoresIA: <String, double>{
        for (var i = 0; i < arrivee.length && i < 5; i++)
          '${arrivee[i]}': 90.0 - i * 5,
      },
      arriveeReelle: arrivee,
      dateResultat: jour,
      resultatsReels: true,
      rangFavoriIaDansArrivee: 1,
      nbTop3DansArriveeReelle: 3,
      nbTop5DansArriveeReelle: 5,
      scorePerformance: 88.0,
      confiancePredite: 71.0,
      typePariConseille: 'Tiercé',
      favoriIaNom: 'Cheval ${arrivee.first}',
      coteFavoriPmu: 3.4,
      cotesPmuParNumero: <String, double>{'${arrivee.first}': 3.4},
    );

void _semerPronostics(List<IaPronostic> pronostics) {
  _store.semer(
    _kPronosticsKey,
    pronostics.map((p) => json.encode(p.toJson())).toList(),
  );
  _store.semer(_kFlagMigration, true);
}

// ═══════════════════════════════════════════════════════════════════════════
//  4. RÉSEAU SIMULÉ + COMPTEUR
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
//  5. MONTAGE + OUVERTURE RÉELLE DU DÉTAIL
//
//  ⚠️ PIÈGE MESURÉ : le calendrier est une `ListView`. Tant qu'elle n'est pas
//  assez haute, la grille mensuelle n'est pas construite et AUCUNE case
//  n'existe — un `pumpWidget` seul ne prouverait rien. On rend donc la
//  surface haute, puis on VÉRIFIE que la case du jour existe ET qu'elle est
//  réellement cliquable avant de l'utiliser.
//
//  ⚠️ `pumpAndSettle` est proscrit : des timers périodiques et un flash de
//  800 ms peuvent empêcher la convergence. On pompe un nombre fixe de trames.
// ═══════════════════════════════════════════════════════════════════════════

Future<void> _pomper(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// La cellule du jour dans la grille mensuelle.
///
/// Ancrée sur l'`AnimatedContainer` de `_buildCase` (`:998-1001`), identifié
/// par son unique descendant `Text('<jour>')`. Ce couple (type + texte exact)
/// n'existe nulle part ailleurs dans le calendrier.
Finder _celluleDuJour(WidgetTester tester, int jour) {
  final cellules = find.byWidgetPredicate(
    (w) => w is AnimatedContainer,
    description: 'cellule de la grille mensuelle',
  );
  for (final el in cellules.evaluate()) {
    final f = find.byWidget(el.widget);
    final t = find.descendant(of: f, matching: find.text('$jour'));
    if (t.evaluate().length == 1) return f;
  }
  fail('aucune cellule pour le jour $jour : la grille mensuelle n\'est pas '
      'construite, ou son contenu diffère de ce que ce test suppose');
}

/// Monte le calendrier avec les données déjà semées.
///
/// `recharger()` est appelé APRÈS le semis pour que la mémoire IA relise le
/// disque fraîchement invalidé — `setUp` seul ne suffirait pas puisque les
/// clés y sont encore absentes.
Future<void> _monter(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await IaMemoryService.instance.recharger();

  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: IaCalendrierTab()),
  ));
  await _pomper(tester);
}

/// Monte, tape la case du jour, et vérifie que le détail est RÉELLEMENT monté
/// et rendu. Sans la garde `find.text('Arrivée réelle')`, toutes les
/// assertions suivantes porteraient sur du vide.
Future<void> _ouvrirDetail(WidgetTester tester) async {
  await _monter(tester);

  final jour = DateTime.now().day;
  final cellule = _celluleDuJour(tester, jour);

  // Non-vacuité 1 : la case doit être ARMÉE.
  final gestes = find.ancestor(
    of: cellule,
    matching: find.byType(GestureDetector),
  );
  final armes = gestes
      .evaluate()
      .where((e) => (e.widget as GestureDetector).onTap != null)
      .length;
  expect(armes, greaterThanOrEqualTo(1),
      reason: 'la case du jour $jour doit être cliquable (palier non gris, '
          'non future, nbCourses > 0) — sinon le clic ne testerait rien');

  await tester.tap(cellule);
  await _pomper(tester);

  // Non-vacuité 2 : le bottom sheet doit être monté ET son contenu construit.
  expect(find.text('Arrivée réelle'), findsWidgets,
      reason: 'le détail de journée doit être ouvert et sa carte rendue : '
          'sans cela le test n\'aurait rien mesuré');
}

// ═══════════════════════════════════════════════════════════════════════════
//  6. LECTURE D'ÉCRAN
// ═══════════════════════════════════════════════════════════════════════════

List<String> _textes(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

int _nbTextesEgaUX(WidgetTester tester, String valeur) =>
    _textes(tester).where((s) => s == valeur).length;

// ═══════════════════════════════════════════════════════════════════════════
//  7. LECTURE DE SOURCE — tests STRUCTURELS uniquement
//
//  ⚠️ La mesure sur texte BRUT est FAUSSE : la documentation ajoutée par
//  L2-3 cite elle-même `ArriveeOfficielleService.instance.arrivee(...)`.
//  On retire donc les commentaires avant toute mesure — défaut déjà mesuré
//  en L2-1 (`runApp(` à l'offset 3015 = commentaire, réel à 4835).
// ═══════════════════════════════════════════════════════════════════════════

String _lire(String chemin) {
  final f = File(chemin);
  expect(f.existsSync(), isTrue, reason: 'fichier introuvable : $chemin');
  return f.readAsStringSync();
}

String _codeSansCommentaires(String src) {
  final out = StringBuffer();
  for (final ligne in src.split('\n')) {
    if (ligne.trimLeft().startsWith('//')) continue;
    var coupe = -1;
    for (var i = 0; i + 1 < ligne.length; i++) {
      if (ligne[i] == '/' && ligne[i + 1] == '/') {
        if (i > 0 && ligne[i - 1] == ':') continue; // épargne `://`
        coupe = i;
        break;
      }
    }
    out.writeln(coupe >= 0 ? ligne.substring(0, coupe) : ligne);
  }
  return out.toString();
}

const String _cheminCalendrier = 'lib/widgets/ia/ia_calendrier_tab.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  TESTS
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _store = _Store();
    SharedPreferencesStorePlatform.instance = _store;
    SharedPreferences.resetStatic();
    _urls.clear();

    ArriveeOfficielleService.instance.viderMemoireSeulement();
    QuasiGrosParisService.instance.viderMemoirePourResetComplet();
    IaArchiveService.instance.oublierChargementPourTest();
    await IaMemoryService.instance.recharger();
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-3.1 — PARCOURS RÉEL : les 5 maillons, mesurés sur source NUE
  // ─────────────────────────────────────────────────────────────────────
  test('L2-3.1 [structurel] chaîne calendrier → case → ouvrir → sheet → carte',
      () {
    final code = _codeSansCommentaires(_lire(_cheminCalendrier));

    // 1. Le widget du calendrier.
    expect(code.contains('class IaCalendrierTab extends StatefulWidget'), isTrue);

    // 2. La grille et son gestionnaire de clic.
    expect(code.contains('Widget _buildGrille('), isTrue,
        reason: 'la grille mensuelle est le conteneur des cases');
    expect(code.contains('() => _ouvrirDetailJour(context, dd, moisRef)'), isTrue,
        reason: 'le clic sur une case doit appeler _ouvrirDetailJour');
    expect(
        code.contains(
            'onTap: (!estGris && !estFut && dd != null && dd.nbCourses > 0)'),
        isTrue,
        reason: 'la condition d\'armement du tap doit rester celle du code lu');

    // 3. La méthode qui ouvre le détail.
    expect(code.contains('void _ouvrirDetailJour('), isTrue);
    expect(code.contains('_DetailJourSheet(dd: dd, moisRef: moisRef)'), isTrue);

    // 4. La classe exacte réellement ouverte.
    expect(code.contains('class _DetailJourSheet extends StatelessWidget'), isTrue);

    // 5. La méthode qui affiche pronostics et arrivées.
    expect(code.contains('Widget _buildPronosticCard('), isTrue);
    expect(
        code.contains('_buildPronosticCard(context, p, premiumsDuJour, dateRef)'),
        isTrue,
        reason: '_buildPronosticCard doit être appelée depuis _DetailJourSheet');

    // Aucun AUTRE appelant : la carte n'existe que dans le détail de journée.
    expect(RegExp(r'_buildPronosticCard\(').allMatches(code).length, 2,
        reason: 'exactement 1 définition + 1 appel — tout appel supplémentaire '
            'élargirait le périmètre L2-3');
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-3.2 — EX ÆQUO L0 RENDUS DANS LE DÉTAIL DE JOURNÉE
  // ─────────────────────────────────────────────────────────────────────
  testWidgets('L2-3.2 [widget] ex æquo L0 → « = » et « · », badge '
      '« Officielle complète »', (tester) async {
    final cle = _cleNeuve();
    // Historique VOLONTAIREMENT différent de L0 : si L0 n'était pas
    // prioritaire, le rendu afficherait « N°1 - N°2 - N°3 - N°4 - N°5 ».
    _semerPronostics([
      _pronostic(courseKey: cle, jour: DateTime.now(),
          arrivee: const <int>[1, 2, 3, 4, 5]),
    ]);
    _semerShard(<String, List<List<int>>>{
      cle: <List<int>>[
        <int>[4, 7],
        <int>[2],
        <int>[9, 1],
      ],
    });
    await ArriveeOfficielleService.instance.charger();
    await _ouvrirDetail(tester);

    final textes = _textes(tester);

    // Les numéros L0 sont rendus, chacun dans son badge.
    for (final n in <int>[4, 7, 2, 9, 1]) {
      expect(textes.where((s) => s == 'N°$n').length, greaterThanOrEqualTo(1),
          reason: 'le numéro $n doit être affiché depuis L0');
    }

    // Ex æquo intra-groupe : exactement 2 « = » (groupes [4,7] et [9,1]).
    expect(_nbTextesEgaUX(tester, '='), 2,
        reason: 'un « = » par groupe de plusieurs chevaux : '
            '[[4,7],[2],[9,1]] → 2 ex æquo');

    // Séparateur inter-groupes : exactement 2 « · » (3 groupes).
    expect(_nbTextesEgaUX(tester, '·'), 2,
        reason: 'un « · » entre 3 groupes → 2 séparateurs');

    // Ordre de lecture réel : N°4 = N°7 · N°2 · N°9 = N°1.
    // Le « = » du groupe [9,1] est rendu ENTRE N°9 et N°1 : i9 < iEg2 < i1.
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

    // Badge de provenance : L0 → « Officielle complète », jamais l'autre.
    expect(textes.where((s) => s == 'Officielle complète').length,
        greaterThanOrEqualTo(1));
    expect(textes.where((s) => s == 'Résultat historique'), isEmpty);

    // Le rendu plat historique ne doit PAS apparaître : L0 est la SEULE
    // source d'affichage quand il existe.
    expect(textes.where((s) => s == 'N°1 - N°2 - N°3 - N°4 - N°5'), isEmpty,
        reason: 'la liste plate ne doit jamais être rendue quand L0 existe');
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-3.3 — REPLI HISTORIQUE QUAND L0 EST ABSENT
  // ─────────────────────────────────────────────────────────────────────
  testWidgets('L2-3.3 [widget] L0 absent → liste plate historique, badge '
      '« Résultat historique »', (tester) async {
    final cle = _cleNeuve();
    _semerPronostics([
      _pronostic(courseKey: cle, jour: DateTime.now(),
          arrivee: const <int>[3, 7, 1, 5, 2]),
    ]);
    // AUCUN shard L0 pour cette clé.
    await ArriveeOfficielleService.instance.charger();
    await _ouvrirDetail(tester);

    final textes = _textes(tester);

    expect(textes.where((s) => s == 'Officielle complète'), isEmpty,
        reason: 'sans L0, le badge officiel ne doit jamais apparaître');
    expect(textes.where((s) => s == 'Résultat historique').length,
        greaterThanOrEqualTo(1),
        reason: 'le repli doit être annoncé explicitement');

    // Rendu plat historique STRICTEMENT identique à l'existant.
    expect(textes.where((s) => s == 'N°3 - N°7 - N°1 - N°5 - N°2').length,
        greaterThanOrEqualTo(1),
        reason: 'le texte plat d\'origine doit être restitué à l\'identique');

    // Aucun séparateur de groupe : il n'y a pas de groupes.
    expect(_nbTextesEgaUX(tester, '='), 0);
    expect(_nbTextesEgaUX(tester, '·'), 0);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-3.4 — L0 EXISTE MAIS SANS CETTE COURSE → repli, rien d'inventé
  // ─────────────────────────────────────────────────────────────────────
  testWidgets('L2-3.4 [widget] L0 sans entrée pour la clé → repli, '
      'aucun groupe fabriqué', (tester) async {
    final cle = _cleNeuve();
    final autre = _cleNeuve();
    _semerPronostics([
      _pronostic(courseKey: cle, jour: DateTime.now(),
          arrivee: const <int>[6, 8, 2, 4, 1]),
    ]);
    // L0 contient une AUTRE course : la clé cherchée reste absente.
    _semerShard(<String, List<List<int>>>{
      autre: <List<int>>[<int>[1], <int>[2]],
    });
    await ArriveeOfficielleService.instance.charger();
    await _ouvrirDetail(tester);

    final textes = _textes(tester);
    expect(textes.where((s) => s == 'Résultat historique').length,
        greaterThanOrEqualTo(1));
    expect(textes.where((s) => s == 'Officielle complète'), isEmpty);
    expect(textes.where((s) => s == 'N°6 - N°8 - N°2 - N°4 - N°1').length,
        greaterThanOrEqualTo(1),
        reason: 'repli strict sur la liste plate, aucune invention');
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-3.5 — PRONOSTICS ET RÉSULTATS HISTORIQUES NON MODIFIÉS
  // ─────────────────────────────────────────────────────────────────────
  testWidgets('L2-3.5 [widget] consultation : arriveeReelle du pronostic '
      'strictement inchangée malgré la présence de groupes L0', (tester) async {
    final cle = _cleNeuve();
    _semerPronostics([
      _pronostic(courseKey: cle, jour: DateTime.now(),
          arrivee: const <int>[1, 2, 3, 4, 5]),
    ]);
    _semerShard(<String, List<List<int>>>{
      cle: <List<int>>[<int>[4, 7], <int>[2]],
    });
    await ArriveeOfficielleService.instance.charger();
    await _ouvrirDetail(tester);

    final p = IaMemoryService.instance.pronostics
        .firstWhere((x) => x.courseKey == cle);

    expect(p.arriveeReelle, const <int>[1, 2, 3, 4, 5],
        reason: 'arriveeReelle ne doit JAMAIS être remplacée ni aplatie vers '
            'les groupes L0');
    expect(p.nbTop3DansArriveeReelle, 3,
        reason: 'les métriques historiques restent celles du pronostic');

    // L0 conservé intact : les groupes lus ne sont ni modifiés ni vidés.
    final l0 = ArriveeOfficielleService.instance.arrivee(cle);
    expect(l0, isNotNull);
    expect(l0!.map((g) => g.toList()).toList(), <List<int>>[
      <int>[4, 7],
      <int>[2],
    ]);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-3.6 — ZÉRO RÉSEAU, ZÉRO APPRENTISSAGE PENDANT LA CONSULTATION
  // ─────────────────────────────────────────────────────────────────────
  testWidgets('L2-3.6 [widget] ouverture du détail : 0 requête réseau, '
      '0 apprentissage, 0 écriture', (tester) async {
    final cle = _cleNeuve();
    _semerPronostics([
      _pronostic(courseKey: cle, jour: DateTime.now(),
          arrivee: const <int>[3, 7, 1, 5, 2]),
    ]);
    _semerShard(<String, List<List<int>>>{
      cle: <List<int>>[<int>[3, 7], <int>[1]],
    });
    await ArriveeOfficielleService.instance.charger();
    await IaMemoryService.instance.recharger();

    final mem = IaMemoryService.instance;
    final poidsAvant  = jsonEncode(mem.poids.toJson());
    final calibAvant  = mem.poids.calibrationScore;
    final nbPronosAv  = mem.pronostics.length;
    final clefsAvant  = _store.clesToutes;
    _urls.clear();

    await _sousReseauSimule(() => _ouvrirDetail(tester));

    final poidsApres = jsonEncode(IaMemoryService.instance.poids.toJson());

    expect(_urls, isEmpty,
        reason: 'l\'ouverture du détail ne doit émettre AUCUNE requête — '
            'mesuré : ${_urls.map((u) => u.toString()).toList()}');
    expect(_nbRapports, 0);
    expect(poidsApres, poidsAvant, reason: 'poids adaptatifs inchangés');
    expect(IaMemoryService.instance.poids.calibrationScore, calibAvant);
    expect(IaMemoryService.instance.pronostics.length, nbPronosAv);
    expect(_store.clesToutes, clefsAvant,
        reason: 'aucune clé de stockage créée ni supprimée par la consultation');
    expect(ArriveeOfficielleService.instance.nbEntrees, 1,
        reason: 'L0 n\'a rien écrit : une seule entrée, celle semée');
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-3.7 — CONTRÔLE NÉGATIF : le compteur réseau sait compter
  //
  //  Indispensable : sans lui, L2-3.6 pourrait passer parce que le réseau est
  //  inerte pour tout le monde, et non parce que la consultation l'interdit.
  // ─────────────────────────────────────────────────────────────────────
  testWidgets('L2-3.7 [widget] contrôle négatif : le compteur réseau '
      'détecte bien une requête réelle', (tester) async {
    final cle = _cleNeuve();
    _semerPronostics([
      _pronostic(courseKey: cle, jour: DateTime.now(),
          arrivee: const <int>[3, 7, 1, 5, 2]),
    ]);
    await ArriveeOfficielleService.instance.charger();
    await _monter(tester);
    _urls.clear();

    await _sousReseauSimule(() async {
      await IaMemoryService.instance.fetchArriveeDirecte(
        courseKey: cle,
        heureDepart: DateTime.now(),
      );
    });

    expect(_nbRapports, greaterThanOrEqualTo(1),
        reason: 'le compteur doit voir les requêtes réelles : sans cela, '
            '« 0 requête » en consultation ne prouverait rien');
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-3.8 — LES QUATRE INDICATEURS DU CALENDRIER PRINCIPAL INCHANGÉS
  // ─────────────────────────────────────────────────────────────────────
  test('L2-3.8 [structurel] flamme / étoile / trophée / aura dorée : '
      'conditions, calculs et couleurs intactes', () {
    final code = _codeSansCommentaires(_lire(_cheminCalendrier));

    // Flamme + étoile : badge de source, source unique inchangée.
    expect(code.contains('SourcePronosticUtils.iconeCombinaison('), isTrue,
        reason: 'flamme et étoile gardent leur source unique');
    expect(code.contains('final hasBestBet = hasCourses && (dd.hasBestBet);'),
        isTrue);
    expect(code.contains('svc.calculerStatsGrosParisJour(jourDt).aDesGagnants'),
        isTrue);

    // Trophée : ★ du palier OR.
    expect(code.contains('if (palier == PalierCalendrier.or && hasCourses)'),
        isTrue);
    expect(code.contains("child: Text('★',"), isTrue);

    // Aura dorée : bordure de la case du jour.
    expect(code.contains('_cGold.withValues(alpha: 0.9)'), isTrue,
        reason: 'la bordure dorée de la case du jour doit rester inchangée');
    expect(code.contains('? _cGold'), isTrue);

    // Paliers : règle d'OR immuable et seuils dynamiques intacts.
    expect(
        code.contains(
            'if (dd.palier == PalierCalendrier.or) return PalierCalendrier.or;'),
        isTrue);
    expect(code.contains('PalierCalendrier _getPalierDynamique('), isTrue);
    expect(code.contains('_seuilVert') &&
        code.contains('_seuilJaune') &&
        code.contains('_seuilOrange'), isTrue);

    // L2-3 n'a ajouté AUCUN accès L0 dans ces quatre mécanismes :
    // un seul point de lecture L0 dans tout le fichier, dans le détail.
    expect(
        RegExp(r'ArriveeOfficielleService\.instance\.').allMatches(code).length,
        1,
        reason: 'un SEUL point de lecture L0 dans tout le fichier');
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-3.9 — CARTES GROS PARIS ET QUASI GAGNANTS INCHANGÉES
  // ─────────────────────────────────────────────────────────────────────
  test('L2-3.9 [structurel] cartes Gros Paris et Quasi gagnants : '
      'sources d\'arrivée plate inchangées', () {
    final code = _codeSansCommentaires(_lire(_cheminCalendrier));

    // Les quatre sites hors périmètre lisent TOUJOURS la liste plate.
    expect(code.contains('final arriveeComplete = g.arriveePMUComplete'), isTrue,
        reason: 'carte Gros Paris garde sa source');
    expect(code.contains('final arriveeComplete = qg.arriveeReelle'), isTrue,
        reason: 'carte Quasi garde sa source');
    expect(code.contains('arriveePMU:   qg.arriveeReelle'), isTrue,
        reason: 'comparerCourseIA continue de recevoir la liste plate');
    expect(code.contains('qg.arriveeReelle.isEmpty ?'),
        isTrue,
        reason: 'la fiche Quasi garde son rendu plat');

    // _buildArriveeDetail et _buildGroupesArrivee n'existent QUE dans la
    // carte du détail : 1 définition + 1 appel chacune.
    expect(RegExp(r'_buildArriveeDetail\(').allMatches(code).length, 2,
        reason: '1 définition + 1 appel, dans la carte du détail uniquement');
    expect(RegExp(r'_buildGroupesArrivee\(').allMatches(code).length, 2,
        reason: '1 définition + 1 appel, dans la carte du détail uniquement');

    // Les compteurs et statuts restent calculés ailleurs, sur la liste plate.
    expect(code.contains('nbTrouves') || code.contains('qg.nbTrouves'), isTrue);
  });

  // ─────────────────────────────────────────────────────────────────────
  //  L2-3.10 — PÉRIMÈTRE : aucun mécanisme IA touché dans ce fichier
  // ─────────────────────────────────────────────────────────────────────
  test('L2-3.10 [structurel] import L0 unique, aucun mécanisme IA appelé', () {
    final code = _codeSansCommentaires(_lire(_cheminCalendrier));

    expect(
        RegExp(r"import '\.\./\.\./services/arrivee_officielle_service\.dart';")
            .allMatches(code)
            .length,
        1);

    for (final interdit in <String>[
      'enregistrerResultat(',
      'genererPronostic(',
      'fetchArriveeDirecte(',
      '_apprendreParGradient',
      '_apprendreParDiscipline',
      'analyseJourneeComplete(',
      '_mettreAJourCalibration',
      'arriveeConnue(',
    ]) {
      expect(code.contains(interdit), isFalse,
          reason: '« $interdit » ne doit jamais apparaître dans le calendrier');
    }

    // Les deux resets premium existants restent les SEULES écritures, et
    // restent inchangés (derrière confirmation utilisateur).
    expect(RegExp(r'resetPremiumPourDate\(').allMatches(code).length, 1);
    expect(RegExp(r'resetToutesEtoilesPremium\(').allMatches(code).length, 1);
  });
}
