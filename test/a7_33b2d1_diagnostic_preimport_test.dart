// ═══════════════════════════════════════════════════════════════════════════
//  A7 / 3.3-B2-d1 — DIAGNOSTIC DE L'ÉTAT ELO **AVANT** UN IMPORT
//
//  OBJET DU LOT
//  ────────────
//  Établir, AVANT toute mutation provoquée par `importerDepuisBackup`, un
//  diagnostic FIABLE de l'état ELO : le registre `elo_registre_v3` est-il
//  cohérent avec les ratings RÉELLEMENT PERSISTÉS ? Le résultat est rendu
//  observable par `dernierDiagnosticPreImport`.
//
//  CE QUE CE LOT NE FAIT **PAS** — À LIRE AVANT TOUTE INTERPRÉTATION
//  ─────────────────────────────────────────────────────────────────
//  • il n'ÉCRIT pas `elo_registre_v3` : ni création, ni mise à jour, ni
//    suppression, ni migration, ni invalidation. Le groupe B2d1-4 le PROUVE en
//    comparant la valeur brute du registre avant/après l'import ;
//  • il ne RÉANCRE RIEN (aucun `copyWith`, aucun `encoder()`) ;
//  • il n'AUTORISE ni ne BLOQUE aucune opération : `autoriseApplication` et
//    `protegeContreDoubleApplication` sont exposés pour l'observation seule ;
//  • il ne touche NI les formules ELO, NI les coefficients K, NI les
//    mécanismes d'apprentissage, NI les critères A–Q, NI les backups ;
//  • il n'ajoute AUCUNE clé SharedPreferences (`_toutesLesCles` reste 108) ;
//  • il ne modifie AUCUN compteur historique : les groupes B2d1-4 et B2d1-5
//    vérifient `nbPersistees`, `nbRefuseesStockage`, `nbEchouees`,
//    `nbRefusParReset`, `nbRefusParGeneration`, `nbEcrituresEnCours` et
//    `nbEcrituresPersistantesEnCours`.
//
//  MESURE PRÉALABLE, IMPORTANTE POUR LA LECTURE DES ASSERTIONS
//  ───────────────────────────────────────────────────────────
//  `setUp()` appelle `EloService.init()` → `_charger()`, qui écrit
//  `elo_orphelins_purges_v1`. Toute assertion sur le CONTENU du journal du
//  store est donc bornée par un index relevé au début du test — jamais absolue.
//
//  `SharedPreferences.getString` lit le CACHE `_preferenceCache`, pas le store
//  (mesuré : `shared_preferences_legacy.dart` l.130). C'est la raison d'être du
//  `reload()` du service, et la raison pour laquelle ce fichier peut semer
//  directement dans le store : `reload()` rend le semis visible.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/elo_registre_v3.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/utils/elo_empreinte.dart';

// ───────────────────────────────────────────────────────────────────────────
//  STORE INSTRUMENTÉ — même contrat que B1 / B2-a / B2-b (copie assumée)
//
//  Deux suspensions DISTINCTES sont nécessaires ici :
//    • `setValue`  → écritures (hérité de B1 / B2-a / B2-b) ;
//    • `getAllWithParameters` → LECTURES. Indispensable à B2-d1 : `reload()`
//      passe par `getAllWithParameters` (mesuré, l.227-231 de
//      `shared_preferences_legacy.dart`), jamais par `setValue`. Suspendre une
//      lecture est le seul moyen de faire démarrer un reset PENDANT l'attente
//      introduite par le diagnostic.
// ───────────────────────────────────────────────────────────────────────────

class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  String? cleSuspendue;
  Completer<void>? _entreeSuspendue;
  Completer<void>? _verrouSuspendu;

  /// Numéro d'appel de `getAllWithParameters` à suspendre (1 = le premier).
  int? _suspendreAuGetAll;
  int _getAllAppels = 0;
  Completer<void>? _entreeGetAll;
  Completer<void>? _verrouGetAll;

  @override
  Future<bool> clear() async {
    journal.add('CLEAR');
    _valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    _getAllAppels++;
    journal.add('GETALL $_getAllAppels');

    if (_suspendreAuGetAll != null && _getAllAppels == _suspendreAuGetAll) {
      final entree = _entreeGetAll;
      _entreeGetAll = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      final verrou = _verrouGetAll;
      if (verrou != null) await verrou.future;
    }

    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET-ENTREE $key');
    // ÉGALITÉ STRICTE — jamais `contains`.
    if (cleSuspendue != null && key == cleSuspendue) {
      final entree = _entreeSuspendue;
      _entreeSuspendue = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      final verrou = _verrouSuspendu;
      if (verrou != null) await verrou.future;
    }
    _valeurs[key] = value;
    journal.add('SET-OK $key');
    return true;
  }

  // ── Suspension d'ÉCRITURE (héritée) ──────────────────────────────────────
  Future<void> armerSuspension(String cle) {
    final entree = Completer<void>();
    _entreeSuspendue = entree;
    cleSuspendue = cle;
    _verrouSuspendu = Completer<void>();
    return entree.future;
  }

  void libererSuspension() {
    final v = _verrouSuspendu;
    _verrouSuspendu = null;
    cleSuspendue = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  // ── Suspension de LECTURE (nouvelle en B2-d1) ────────────────────────────
  /// Suspend le `n`-ième appel à `getAllWithParameters`.
  Future<void> armerSuspensionLecture(int numero) {
    final entree = Completer<void>();
    _entreeGetAll = entree;
    _suspendreAuGetAll = numero;
    _verrouGetAll = Completer<void>();
    return entree.future;
  }

  void libererSuspensionLecture() {
    final v = _verrouGetAll;
    _verrouGetAll = null;
    _suspendreAuGetAll = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void desarmer() {
    cleSuspendue = null;
    _entreeSuspendue = null;
    final v = _verrouSuspendu;
    _verrouSuspendu = null;
    if (v != null && !v.isCompleted) v.complete();

    _suspendreAuGetAll = null;
    _entreeGetAll = null;
    final vg = _verrouGetAll;
    _verrouGetAll = null;
    if (vg != null && !vg.isCompleted) vg.complete();
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  Set<String> clesEcritesDepuis(int index) => journal
      .skip(index)
      .where((e) => e.startsWith('SET-OK '))
      .map((e) => e.substring('SET-OK '.length))
      .toSet();
}

// Type privé volontaire : le dispositif reste local à ce fichier.
// ignore: library_private_types_in_public_api
late _Store store;

void _installerStore() {
  store = _Store();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

/// Vidage BORNÉ de la boucle d'événements (nombre de tours, jamais une durée).
Future<void> _laisserProgresser([int tours = 24]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ── Constantes partagées avec les tests B1 / B2-a / B2-b ────────────────────

const String kCleElo = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
const String kCleRegistre = 'elo_registre_v3';

/// Empreinte de la map VIDE — documentée dans `elo_empreinte.dart`.
const String kEmpreinteVide = '16ed60fcfaed47f4';

// ───────────────────────────────────────────────────────────────────────────
//  HELPERS DE SEMIS
// ───────────────────────────────────────────────────────────────────────────

/// Map d'`EloScore` de référence, à partir de `clé -> rating`.
///
/// `nbCourses = 20` et `variationMois = 5.0` sont FIXES : l'empreinte ne
/// dépend que de la clé, du rating, de `nbCourses` et de `variationMois`
/// (`canoniqueRatings`). Les figer rend les empreintes attendues calculables.
Map<String, EloScore> _mapElo(Map<String, double> ratings) {
  final map = <String, EloScore>{};
  ratings.forEach((cle, rating) {
    final nom = cle.contains('|') ? cle.split('|').first : cle;
    map[cle] = EloScore(
      nomCheval: nom,
      rating: rating,
      nbCourses: 20,
      variationMois: 5.0,
    );
  });
  return map;
}

/// Charge utile d'import, exactement au format attendu par
/// `importerDepuisBackup` (une map `clé -> EloScore.toJson()`).
Map<String, dynamic> _payloadElo(Map<String, double> ratings) {
  final data = <String, dynamic>{};
  _mapElo(ratings).forEach((cle, score) => data[cle] = score.toJson());
  return data;
}

/// Empreinte attendue pour un semis `clé -> rating`.
String _empreinteDe(Map<String, double> ratings) =>
    empreinte64Ratings(_mapElo(ratings));

/// Enregistre des ratings SUR LE DISQUE (via le store), sans passer par le
/// service : c'est le seul moyen de représenter un état persistant ANTÉRIEUR
/// à l'import, que la RAM ne connaît pas forcément.
void _semerRatings(Map<String, double> ratings) {
  final data = _payloadElo(ratings);
  store.semer(kCleElo, jsonEncode(data));
}

/// Semis d'un registre LISIBLE et COHÉRENT avec les ratings semés.
///
/// Construit par le MODÈLE lui-même (`RegistreEloV3.vierge` puis
/// `copyWith`), jamais par une main humaine : une chaîne écrite à la main
/// pourrait ne pas respecter les invariants et produirait un `corrompu`.
String _registreCoherent(Map<String, double> ratings) {
  final empreinte = _empreinteDe(ratings);
  final registre = RegistreEloV3.vierge(empreinteRatings: empreinte).copyWith(
    empreinteRatings: empreinte,
    origine: OrigineRegistreElo.courante,
    entrees: const <EntreeRegistreElo>[],
  );
  return registre.encoder();
}

/// Semis d'un registre LISIBLE mais DIVERGENT : il déclare l'empreinte d'une
/// map VIDE, qui ne peut pas être l'empreinte de ratings non vides.
///
/// La divergence est donc CONSTRUITE, jamais espérée : aucune dépendance au
/// hasard de l'empreinte.
String _registreDivergent() =>
    RegistreEloV3.vierge(empreinteRatings: kEmpreinteVide).encoder();

/// Registre CORROMPU : JSON valide, mais champs obligatoires ABSENTS.
/// `RegistreEloV3.decoder` lève `FormatException` → diagnostic `corrompu`.
const String kRegistreCorrompu =
    '{"version":3,"operations":{"R1C1_20260417":{"etat":"temoin"}}}';

/// Registre INCOMPATIBLE : structure complète, mais `schema` étranger.
/// `interpretable` refuse → diagnostic `schemaIncompatible`.
String _registreIncompatible() {
  final json = <String, dynamic>{
    'schema': 99,
    'version': 1,
    'horloge': 3,
    'empreinteRatings': kEmpreinteVide,
    'origine': 'courante',
    'entrees': <dynamic>[],
  };
  return jsonEncode(json);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _installerStore();
    await EloService.init();
    EloService.instance.viderMemoirePourResetComplet();
  });

  tearDown(() {
    store.desarmer();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d1-1 — REGISTRE ABSENT
  //
  //  Le diagnostic doit distinguer un PREMIER USAGE d'un HISTORIQUE INCONNU,
  //  et cela dépend du nombre de ratings PERSISTÉS — pas de la RAM.
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d1-1 — registre absent', () {
    test('1a — aucun rating persisté : registreAbsent + origine courante',
        () async {
      final elo = EloService.instance;

      expect(store.contient(kCleRegistre), isFalse,
          reason: 'témoin : le registre doit être ABSENT dans ce scénario');
      expect(store.contient(kCleElo), isFalse,
          reason: 'témoin : aucun rating sur le disque');

      final etat = await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'ALPHA|PLAT': 1500.0}));

      final diag = elo.dernierDiagnosticPreImport!;
      // ignore: avoid_print
      print('[B2d1-1a] $diag | etat=${etat.name}');

      expect(diag.etabli, isTrue, reason: 'le diagnostic doit être établi');
      expect(diag.coherence, DiagnosticCoherenceElo.registreAbsent);
      expect(diag.origine, OrigineRegistreElo.courante,
          reason: '0 rating persisté ⇒ premier usage, PAS « historique inconnu »');
      expect(diag.nombrePersistee, 0);
      expect(diag.empreintePersistee, kEmpreinteVide,
          reason: 'l\'empreinte d\'une map vide est mesurée, pas supposée');
      expect(diag.autoriseApplication, isTrue);
      expect(diag.protegeContreDoubleApplication, isFalse,
          reason: 'aucun registre ne protège quoi que ce soit');
    });

    test('1b — des ratings persistés SANS registre : historiqueInconnu',
        () async {
      _semerRatings(<String, double>{'BRAVO|PLAT': 1620.0});
      final elo = EloService.instance;

      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'CHARLIE|PLAT': 1480.0}));

      final diag = elo.dernierDiagnosticPreImport!;
      // ignore: avoid_print
      print('[B2d1-1b] $diag');

      expect(diag.coherence, DiagnosticCoherenceElo.registreAbsent);
      expect(diag.nombrePersistee, 1,
          reason: 'le disque faisait foi, PAS la RAM (vidée en setUp)');
      expect(diag.empreintePersistee,
          _empreinteDe(<String, double>{'BRAVO|PLAT': 1620.0}));
      expect(diag.origine, OrigineRegistreElo.historiqueInconnu,
          reason: 'ratings présents + registre absent ⇒ historique INCONNU');
      expect(diag.autoriseApplication, isTrue,
          reason: 'le modèle autorise — sans prétendre protéger');
      expect(diag.protegeContreDoubleApplication, isFalse,
          reason: 'JAMAIS présenté comme protégé');
    });

    test('1c — aucun registre n\'est créé sur le disque', () async {
      final index = store.journal.length;

      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'DELTA|PLAT': 1510.0}));
      await _laisserProgresser();

      expect(store.contient(kCleRegistre), isFalse,
          reason: 'B2-d1 ne crée AUCUN registre : il ne fait que lire');
      expect(store.clesEcritesDepuis(index),
          <String>{'flutter.$kCleElo', 'flutter.$kCleTs'},
          reason: 'seules les deux clés ELO historiques sont écrites');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d1-2 — REGISTRE LISIBLE : COHÉRENT OU DIVERGENT
  //
  //  C'est le cœur du lot : la cohérence est un fait DATÉ, évalué AVANT la
  //  mutation. Les deux cas sont distingués sans ambiguïté.
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d1-2 — registre lisible', () {
    test('2a — registre cohérent avant import : coherence == coherent',
        () async {
      final ratings = <String, double>{'ECHO|PLAT': 1700.0, 'FOXTROT|PLAT': 1400.0};
      _semerRatings(ratings);
      store.semer(kCleRegistre, _registreCoherent(ratings));
      final empreinteAvant = _empreinteDe(ratings);

      final elo = EloService.instance;
      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'GOLF|PLAT': 1550.0}));
      final diag = elo.dernierDiagnosticPreImport!;
      // ignore: avoid_print
      print('[B2d1-2a] $diag');

      expect(diag.etabli, isTrue);
      expect(diag.coherence, DiagnosticCoherenceElo.coherent,
          reason: 'le registre déclare EXACTEMENT l\'empreinte persistée');
      expect(diag.empreintePersistee, empreinteAvant);
      expect(diag.nombrePersistee, 2);
      expect(diag.origine, OrigineRegistreElo.courante);
      expect(diag.protegeContreDoubleApplication, isTrue,
          reason: 'cohérent + courante = le seul cas réellement protégé');
    });

    test('2b — registre divergent AVANT import : coherence == divergent',
        () async {
      final ratings = <String, double>{'HOTEL|PLAT': 1650.0};
      _semerRatings(ratings);
      // Empreinte déclarée = celle d'une map VIDE, qui ne peut pas être celle
      // des ratings semés : la divergence est CONSTRUITE, pas espérée.
      final registre = RegistreEloV3.vierge(empreinteRatings: kEmpreinteVide);
      store.semer(kCleRegistre, registre.encoder());

      final elo = EloService.instance;
      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'INDIA|PLAT': 1520.0}));
      final diag = elo.dernierDiagnosticPreImport!;
      // ignore: avoid_print
      print('[B2d1-2b] $diag');

      expect(diag.coherence, DiagnosticCoherenceElo.divergent,
          reason: 'l\'empreinte déclarée n\'est pas celle des ratings persistés');
      expect(diag.resultat!.empreinteRegistre, kEmpreinteVide);
      expect(diag.empreintePersistee, isNot(kEmpreinteVide));
      expect(diag.autoriseApplication, isFalse,
          reason: 'divergent est FAIL-CLOSED dans le modèle');
      expect(diag.protegeContreDoubleApplication, isFalse);
    });

    test('2c — un registre divergent n\'est NI modifié NI supprimé', () async {
      _semerRatings(<String, double>{'JULIET|PLAT': 1600.0});
      final registre = RegistreEloV3.vierge(empreinteRatings: kEmpreinteVide);
      final brutAvant = registre.encoder();
      store.semer(kCleRegistre, brutAvant);
      final index = store.journal.length;

      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'KILO|PLAT': 1490.0}));
      await _laisserProgresser();

      expect(store.lire(kCleRegistre), brutAvant,
          reason: 'la valeur brute du registre doit être IDENTIQUE, octet pour '
              'octet — B2-d1 ne réancre RIEN');
      expect(store.clesEcritesDepuis(index),
          <String>{'flutter.$kCleElo', 'flutter.$kCleTs'},
          reason: 'aucune écriture de registre');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d1-3 — REGISTRE ILLISIBLE : CORROMPU OU INCOMPATIBLE
  //
  //  Deux diagnostics DISTINCTS : la cause n'est pas la même, et le contrat du
  //  modèle n'autorise aucune des deux formes à être détruite.
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d1-3 — registre illisible', () {
    test('3a — registre corrompu : diagnostic corrompu, valeur intacte',
        () async {
      _semerRatings(<String, double>{'LIMA|PLAT': 1580.0});
      store.semer(kCleRegistre, kRegistreCorrompu);

      final elo = EloService.instance;
      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'MIKE|PLAT': 1530.0}));
      final diag = elo.dernierDiagnosticPreImport!;
      // ignore: avoid_print
      print('[B2d1-3a] $diag');

      expect(diag.etabli, isTrue,
          reason: 'un registre corrompu est un VERDICT, pas un échec '
              'd\'établissement du diagnostic');
      expect(diag.coherence, DiagnosticCoherenceElo.corrompu);
      expect(diag.resultat!.empreinteRegistre, isNull,
          reason: 'aucune empreinte n\'est lisible dans un registre corrompu');
      expect(diag.autoriseApplication, isFalse);
      expect(store.lire(kCleRegistre), kRegistreCorrompu,
          reason: 'contrat du modèle : « Le registre n\'est pas supprimé »');
    });

    test('3b — registre incompatible : diagnostic schemaIncompatible',
        () async {
      _semerRatings(<String, double>{'NOVEMBER|PLAT': 1610.0});
      final brutAvant = _registreIncompatible();
      store.semer(kCleRegistre, brutAvant);

      final elo = EloService.instance;
      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'OSCAR|PLAT': 1470.0}));
      final diag = elo.dernierDiagnosticPreImport!;
      // ignore: avoid_print
      print('[B2d1-3b] $diag');

      expect(diag.coherence, DiagnosticCoherenceElo.schemaIncompatible,
          reason: 'schema 99 ≠ kSchemaRegistreElo : refusé par `interpretable`');
      expect(diag.empreinteRegistre, kEmpreinteVide,
          reason: 'l\'empreinte EST lisible — c\'est le SCHÉMA qui est refusé. '
              'Un schéma inconnu ne produit jamais `coherent`.');
      expect(diag.autoriseApplication, isFalse);
      expect(store.lire(kCleRegistre), brutAvant,
          reason: 'ni supprimé, ni migré, ni réinterprété');
    });

    test('3c — un registre de version inconnue est refusé comme un schéma',
        () async {
      final json = <String, dynamic>{
        'schema': 3,
        'version': 2, // forme connue, sémantique inconnue
        'horloge': 0,
        'empreinteRatings': kEmpreinteVide,
        'origine': 'courante',
        'entrees': <dynamic>[],
      };
      _semerRatings(<String, double>{'PAPA|PLAT': 1560.0});
      store.semer(kCleRegistre, jsonEncode(json));

      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'QUEBEC|PLAT': 1440.0}));
      final diag = EloService.instance.dernierDiagnosticPreImport!;

      expect(diag.coherence, DiagnosticCoherenceElo.schemaIncompatible,
          reason: '`interpretable` exige schema == 3 ET version == 1');
    });

    test('3d — une chaîne vide est corrompue, pas absente', () async {
      _semerRatings(<String, double>{'ROMEO|PLAT': 1590.0});
      store.semer(kCleRegistre, '   ');

      await EloService.instance.importerDepuisBackup(
          _payloadElo(<String, double>{'SIERRA|PLAT': 1420.0}));
      final diag = EloService.instance.dernierDiagnosticPreImport!;

      expect(diag.coherence, DiagnosticCoherenceElo.corrompu,
          reason: 'une valeur PRÉSENTE mais blanche n\'est pas une absence');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d1-4 — RAM NON CHARGÉE, RAM DIFFÉRENTE DU DISQUE
  //
  //  Exigence 2 du mandat : « vérifier leur cohérence sans supposer que
  //  _ratings est chargé ou identique au disque ». Le disque FAIT FOI.
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d1-4 — le disque fait foi, jamais la RAM', () {
    test('4a — RAM vide, disque peuplé : le diagnostic décrit le DISQUE',
        () async {
      final ratings = <String, double>{'TANGO|PLAT': 1740.0};
      _semerRatings(ratings);
      store.semer(kCleRegistre, _registreCoherent(ratings));

      final elo = EloService.instance;
      expect(elo.nbChevauxSuivis, 0,
          reason: 'témoin : la RAM est VIDE (vidée en setUp)');

      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'UNIFORM|PLAT': 1500.0}));
      final diag = elo.dernierDiagnosticPreImport!;
      // ignore: avoid_print
      print('[B2d1-4a] $diag');

      expect(diag.coherence, DiagnosticCoherenceElo.coherent,
          reason: 'la cohérence est évaluée sur le DISQUE. Diagnostiquer '
              'contre une RAM vide aurait rendu `divergent` à tort.');
      expect(diag.nombrePersistee, 1);
      expect(diag.nombreRam, 0);
      expect(diag.ramIdentiqueAuDisque, isFalse,
          reason: 'la RAM ne reflète PAS le disque, et cela doit être visible');
    });

    test('4b — RAM différente du disque : le disque l\'emporte encore',
        () async {
      // ★ Correction B2-d2 : la RAM est peuplée SANS PASSER PAR LE SERVICE
      //   (`chargerDepuisMapIsolate` est une lecture pure : aucun effet disque,
      //   aucun témoin). L'intention du test — « RAM ≠ disque, le disque fait
      //   foi » — est préservée à l'identique, et elle n'est plus polluée par
      //   une écriture de registre effectuée par un premier import.
      _semerRatings(<String, double>{'VICTOR|PLAT': 1680.0});
      store.semer(kCleRegistre,
          _registreCoherent(<String, double>{'VICTOR|PLAT': 1680.0}));

      final elo = EloService.instance;
      elo.chargerDepuisMapIsolate(
          _payloadElo(<String, double>{'WHISKY|PLAT': 1300.0}));

      // Témoin : la RAM contient bien WHISKY, le disque bien VICTOR.
      expect(elo.nbChevauxSuivis, 1);
      expect(store.lire(kCleRegistre),
          _registreCoherent(<String, double>{'VICTOR|PLAT': 1680.0}),
          reason: 'témoin : la RAM a été peuplée sans toucher au registre');

      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'XRAY|PLAT': 1510.0}));
      final diag = elo.dernierDiagnosticPreImport!;
      // ignore: avoid_print
      print('[B2d1-4b] $diag');

      expect(diag.coherence, DiagnosticCoherenceElo.coherent,
          reason: 'le disque est cohérent avec le registre ; la RAM contenait '
              'WHISKY et ne devait PAS être utilisée');
      expect(diag.empreintePersistee,
          _empreinteDe(<String, double>{'VICTOR|PLAT': 1680.0}));
      expect(diag.ramIdentiqueAuDisque, isFalse);
      expect(diag.nombrePersistee, 1);
      expect(diag.nombreRam, 1,
          reason: 'même cardinal, contenu différent : `ramIdentiqueAuDisque` '
              'compare les EMPREINTES, pas seulement les tailles');
    });

    test('4c — `_prefsKey` non textuelle : diagnostic NON ÉTABLI, explicite',
        () async {
      // Type inattendu : le diagnostic doit le DIRE, pas lever.
      store.semer(kCleElo, 42);

      final elo = EloService.instance;
      final etat = await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'YANKEE|PLAT': 1550.0}));
      final diag = elo.dernierDiagnosticPreImport!;
      // ignore: avoid_print
      print('[B2d1-4c] $diag');

      expect(diag.etabli, isFalse);
      expect(diag.etablissementImpossible, contains('n\'est pas une chaîne'));
      expect(diag.coherence, isNull,
          reason: 'un diagnostic non établi n\'a AUCUNE cohérence — '
              'surtout pas `coherent` par défaut');
      expect(diag.autoriseApplication, isNull);
      expect(diag.protegeContreDoubleApplication, isNull);
      // L'import reste HISTORIQUE : il écrase la valeur illisible.
      expect(etat, EtatPersistanceElo.persistee);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d1-5 — RESET PENDANT UNE LECTURE ASYNCHRONE
  //
  //  Deux attentes sont introduites. Le contrôle G #2 doit couvrir la fenêtre
  //  ouverte par ces attentes : abandon AVANT mutation, aucune écriture.
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d1-5 — reset pendant la lecture du diagnostic', () {
    test('5a — reset pendant `reload()` : abandon, RAM intacte, 0 écriture',
        () async {
      _semerRatings(<String, double>{'ZULU|PLAT': 1650.0});
      final elo = EloService.instance;
      elo.viderMemoirePourResetComplet();

      // Le diagnostic est le PREMIER à appeler `getAllWithParameters` dans ce
      // test : on suspend ce 1er appel. `setUp` a déjà consommé son propre
      // `_charger()`, donc le compteur repart de zéro ici.
      final entree = store.armerSuspensionLecture(1);
      final index = store.journal.length;
      final abandonsAvant = elo.nbAbandonsFileParGeneration;

      final future = elo.importerDepuisBackup(
          _payloadElo(<String, double>{'ANCHOR|PLAT': 1550.0}));
      await entree;

      // Reset PENDANT l'attente de lecture.
      var resetExecute = false;
      final reset = elo.executerResetComplet(() async {
        resetExecute = true;
      });

      store.libererSuspensionLecture();
      final etat = await future;
      await reset;
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2d1-5a] etat=${etat.name} | resetExecute=$resetExecute | '
          'abandons=${elo.nbAbandonsFileParGeneration - abandonsAvant} | '
          'écrites=${store.clesEcritesDepuis(index)}');

      expect(etat, EtatPersistanceElo.abandonneeParReset,
          reason: 'le contrôle G #2 doit refuser AVANT la mutation');
      expect(resetExecute, isTrue, reason: 'témoin : le reset a bien couru');
      expect(elo.nbAbandonsFileParGeneration, abandonsAvant + 1,
          reason: 'l\'abandon est COMPTÉ, jamais silencieux');
      expect(store.clesEcritesDepuis(index), isEmpty,
          reason: 'aucune écriture : l\'opération est morte avant la persistance');
      expect(elo.dernierDiagnosticPreImport, isNull,
          reason: 'une opération abandonnée ne publie AUCUN diagnostic — sinon '
              'un test croirait qu\'un état a été établi');
    });

    test('5b — reset APRÈS publication : le diagnostic reste observable et honnête',
        () async {
      final ratings = <String, double>{'BRAVO2|PLAT': 1600.0};
      _semerRatings(ratings);
      store.semer(kCleRegistre, _registreCoherent(ratings));

      final elo = EloService.instance;
      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'CHARLIE2|PLAT': 1490.0}));

      final diag = elo.dernierDiagnosticPreImport!;
      expect(diag.coherence, DiagnosticCoherenceElo.coherent);

      await elo.executerResetComplet(() async {});
      await _laisserProgresser();

      expect(elo.dernierDiagnosticPreImport, same(diag),
          reason: 'le reset ne touche pas ce champ : B2-d1 ne modifie pas le '
              'reset. Le diagnostic est un fait DATÉ, pas un état courant.');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d1-6 — AUCUNE MUTATION, AUCUN COMPTEUR TOUCHÉ
  //
  //  Exigence 5 du mandat : observer sans agir. Ce groupe le PROUVE.
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d1-6 — le diagnostic n\'agit pas', () {
    test('6a — aucun compteur de persistance n\'est modifié par le diagnostic',
        () async {
      _semerRatings(<String, double>{'DELTA2|PLAT': 1570.0});
      store.semer(kCleRegistre, kRegistreCorrompu);
      final elo = EloService.instance;

      final persistees = elo.nbPersistees;
      final refusees = elo.nbRefuseesStockage;
      final echouees = elo.nbEchouees;
      final refusReset = elo.nbRefusParReset;
      final refusGen = elo.nbRefusParGeneration;

      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'ECHO2|PLAT': 1520.0}));
      await _laisserProgresser();

      expect(elo.nbPersistees, persistees + 1,
          reason: 'l\'import persiste, comme avant ce lot : +1 et rien d\'autre');
      expect(elo.nbRefuseesStockage, refusees);
      expect(elo.nbEchouees, echouees);
      expect(elo.nbRefusParReset, refusReset);
      expect(elo.nbRefusParGeneration, refusGen,
          reason: 'le diagnostic n\'entre PAS dans `_sauvegarder` : il ne peut '
              'pas provoquer de refus par génération');
    });

    test('6b — aucun ensemble d\'écritures en cours n\'est alimenté',
        () async {
      _semerRatings(<String, double>{'FOXTROT2|PLAT': 1620.0});
      final elo = EloService.instance;

      final entree = store.armerSuspension('flutter.$kCleElo');
      final future = elo.importerDepuisBackup(
          _payloadElo(<String, double>{'GOLF2|PLAT': 1510.0}));
      await entree;

      // ignore: avoid_print
      print('[B2d1-6b] historiques=${elo.nbEcrituresEnCours} | '
          'persistentes=${elo.nbEcrituresPersistantesEnCours}');

      expect(elo.nbEcrituresPersistantesEnCours, elo.nbEcrituresEnCours,
          reason: 'B2-d1 n\'ajoute AUCUNE écriture : les deux ensembles '
              'portent EXACTEMENT le même cardinal (contrat de B2-a)');
      expect(elo.nbEcrituresEnCours, 1);

      store.libererSuspension();
      await future;
      await _laisserProgresser();

      expect(elo.nbEcrituresEnCours, 0);
      expect(elo.nbEcrituresPersistantesEnCours, 0);
    });

    test('6c — le registre n\'est NI supprimé NI écrasé (B2-d2 : ajout seul)',
        () async {
      // ★ Correction B2-d2 : ce test portait l'invariant de B2-d1 « aucune
      //   écriture du registre ». B2-d2 écrit légitimement le témoin quand le
      //   registre est COHÉRENT. L'invariant est donc dédoublé, sans être
      //   affaibli :
      //     • aucune SUPPRESSION, dans TOUS les scénarios (universel) ;
      //     • aucune ÉCRITURE, dans tous les scénarios SAUF `coherent` ;
      //     • pour `coherent`, l'écriture a lieu et les anciennes entrées
      //       survivent (append-only, vérifié par B2d2 sur le même mécanisme).
      final scenarios = <String, String?>{
        'absent': null,
        'coherent': _registreCoherent(<String, double>{'HOTEL2|PLAT': 1600.0}),
        'corrompu': kRegistreCorrompu,
        'incompatible': _registreIncompatible(),
      };

      for (final e in scenarios.entries) {
        _installerStore();
        await EloService.init();
        EloService.instance.viderMemoirePourResetComplet();

        _semerRatings(<String, double>{'HOTEL2|PLAT': 1600.0});
        final valeur = e.value;
        if (valeur != null) store.semer(kCleRegistre, valeur);

        final index = store.journal.length;
        await EloService.instance.importerDepuisBackup(
            _payloadElo(<String, double>{'JULIET2|PLAT': 1490.0}));
        await _laisserProgresser();

        final ecrites = store.clesEcritesDepuis(index);
        // ignore: avoid_print
        print('[B2d1-6c/${e.key}] écrites=$ecrites | '
            'lire=${store.lire(kCleRegistre)}');

        // ── UNIVERSEL : jamais de suppression du registre. ────────────────
        expect(store.journal.skip(index).any((l) => l == 'REM $kCleRegistre'),
            isFalse,
            reason: 'scénario ${e.key} : aucune suppression du registre');

        if (e.key == 'coherent') {
          // ── B2-d2 : écriture attendue (append-only), ancienne valeur
          //    remplacée par un registre qui la CONTIENT.
          expect(ecrites.contains('flutter.$kCleRegistre'), isTrue,
              reason: 'registre cohérent ⇒ le témoin DOIT être écrit');
          final nouveau = store.lire(kCleRegistre) as String;
          final relu = RegistreEloV3.decoder(nouveau);
          expect(relu.origine, OrigineRegistreElo.historiqueInconnu,
              reason: 'jamais `courante` après un import');
          expect(relu.entrees, hasLength(1),
              reason: 'une entrée `horsCourse` ajoutée, rien de supprimé');
          expect(relu.entrees.single.motif, MotifHorsCourse.importBackup);
        } else {
          // ── Tous les autres : AUCUNE écriture, valeur brute INCHANGÉE. ──
          expect(ecrites.contains('flutter.$kCleRegistre'), isFalse,
              reason: 'scénario ${e.key} : aucune écriture du registre');
          expect(store.lire(kCleRegistre), valeur,
              reason: 'scénario ${e.key} : la valeur brute est INCHANGÉE');
        }
      }
    });

    test('6d — le comportement de l\'import est identique à B1', () async {
      final payload = _payloadElo(<String, double>{
        'KILO2|PLAT': 1700.0,
        'LIMA2|PLAT': 1300.0,
      });

      final elo = EloService.instance;
      final etat = await elo.importerDepuisBackup(payload);

      expect(etat, EtatPersistanceElo.persistee);
      expect(elo.nbChevauxSuivis, 2);
      expect(store.contient(kCleElo), isTrue);
      expect(store.contient(kCleTs), isTrue);
      expect(elo.exporterPourBackup().keys.toSet(), payload.keys.toSet(),
          reason: 'les ratings importés sont EXACTEMENT ceux de la charge utile');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2d1-7 — LE DIAGNOSTIC EST DATÉ, PAS UN ÉTAT COURANT
  //
  //  Le point le plus subtil du lot : ce que le diagnostic décrit est l'état
  //  AVANT la mutation. Après l'import, le registre est devenu DIVERGENT sur
  //  le disque — et c'est NORMAL, puisque B2-d1 n'écrit rien.
  // ═════════════════════════════════════════════════════════════════════════

  group('B2d1-7 — cohérence datée', () {
    test('7a — après import, le registre coexistait avec un état qui n\'existe plus',
        () async {
      final ratings = <String, double>{'MIKE2|PLAT': 1660.0};
      _semerRatings(ratings);
      final registre = _registreCoherent(ratings);
      store.semer(kCleRegistre, registre);

      final elo = EloService.instance;
      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'NOVEMBER2|PLAT': 1450.0}));

      final pre = elo.dernierDiagnosticPreImport!;
      expect(pre.coherence, DiagnosticCoherenceElo.coherent,
          reason: 'AVANT l\'import, le registre était cohérent');

      // Relecture du MÊME registre contre les ratings MAINTENANT sur le disque.
      final empreinteApres = empreinte64Ratings(
          elo.exporterPourBackup().map((k, v) => MapEntry(k, EloScore.fromJson(v))));
      final diagnosticApres = diagnostiquerRegistre(
        jsonRegistre: registre,
        empreinteDisque: empreinteApres,
        nombreRatings: elo.nbChevauxSuivis,
      );

      // ignore: avoid_print
      print('[B2d1-7a] avant=${pre.coherence} | après=${diagnosticApres.coherence}');

      expect(diagnosticApres.coherence, DiagnosticCoherenceElo.divergent,
          reason: 'APRÈS l\'import, le registre décrit un état révolu. C\'est '
              'précisément pourquoi le diagnostic doit être PRIS AVANT : '
              'évalué après, il serait `divergent` par construction et la '
              'branche de réancrage deviendrait inatteignable.');
      expect(pre.coherence, isNot(diagnosticApres.coherence),
          reason: 'la cohérence est DATÉE : même registre, deux verdicts');
    });

    test('7b — deux imports successifs produisent deux diagnostics distincts',
        () async {
      final elo = EloService.instance;

      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'OSCAR2|PLAT': 1500.0}));
      final premier = elo.dernierDiagnosticPreImport!;

      store.semer(kCleRegistre, _registreDivergent());
      await elo.importerDepuisBackup(
          _payloadElo(<String, double>{'PAPA2|PLAT': 1540.0}));
      final second = elo.dernierDiagnosticPreImport!;

      // ignore: avoid_print
      print('[B2d1-7b] premier=$premier | second=$second');

      expect(identical(premier, second), isFalse,
          reason: 'le champ est REMPLACÉ à chaque import');
      expect(premier.coherence, DiagnosticCoherenceElo.registreAbsent);
      expect(second.coherence, DiagnosticCoherenceElo.divergent,
          reason: 'le registre semé entre les deux imports est divergent');
    });
  });
}
