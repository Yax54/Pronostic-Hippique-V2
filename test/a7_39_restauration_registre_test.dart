// ═══════════════════════════════════════════════════════════════════════════
//  A7 / 3.3-C12 — A7-39 : RESTAURATION VERBATIM DU REGISTRE ENRICHI
//
//  OBJET DU LOT
//  ────────────
//  Une sauvegarde PORTANT `_elo_registre` doit restituer ce registre TEL QUEL
//  sur l'appareil cible, et SEULEMENT si quatre contrôles passent :
//    1. persistance des ratings confirmée (`etat == persistee`) ;
//    2. relecture EFFECTIVE du stockage (`reload()` puis décodage) ;
//    3. F3' — la RAM après mutation est ce que le disque vient de rendre ;
//    4. la RAM persistée est EXACTEMENT ce que le registre déclare.
//  Une sauvegarde SANS registre garde le chemin historique, inchangé.
//
//  CE QUE CE FICHIER NE PROUVE **PAS**
//  ──────────────────────────────────
//  • il ne prouve AUCUNE durabilité physique : le store est en mémoire ;
//  • il ne modifie ni ne mesure aucune formule ELO, aucun coefficient K,
//    aucun poids, aucun seuil, aucun apprentissage TOP3 ;
//  • il n'affirme rien sur les critères A–Q.
//
//  ⚠️ DEUX POINTS D'INTERPRÉTATION, ÉNONCÉS ICI UNE FOIS
//  ─────────────────────────────────────────────────────
//  (a) `protegeApres` vaut `false` après une restitution verbatim. Ce n'est
//      PAS un défaut : le registre restauré est celui de la sauvegarde, il ne
//      contient AUCUNE entrée constatant CET import (on n'en invente pas), et
//      il ne peut donc pas revendiquer une preuve de cette opération-là. Les
//      tests ci-dessous OBSERVENT cette valeur et la confrontent au diagnostic
//      réel relu depuis le disque, au lieu de la supposer.
//  (b) La protection qui COMPTE après restauration est celle du registre
//      restauré lui-même : `protegeContreDoubleApplication` recalculé sur la
//      chaîne relue. C'est elle que M1 et M7 vérifient, et c'est elle qui
//      prouve qu'aucune fausse sécurité n'est créée.
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
//  STORE INSTRUMENTÉ — même contrat que B1 / B2-a / B2-b / B2-d1 / B2-d2.
//  Trois capacités seulement sont nécessaires ici :
//    • suspension d'ÉCRITURE ciblée → prouver que la file et le reset
//      attendent réellement l'écriture du registre ;
//   · refus / exception par clé pour distinguer `refusee` de `echouee` ;
//  · panne de LECTURE pour obtenir `nonTentee` pour cause de persistance.
// ⚠️ Le registre est un FOURRE-TOUT : `leverProchainGetAll` ne peut PAS être
//    utilisé pour simuler une panne de lecture, car `_sauvegarder` en consomme
//    un avant `_empreinteRelueDepuisDisque`. La panne est donc indexée.
// ───────────────────────────────────────────────────────────────────────────

class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  String? cleSuspendue;
  Completer<void>? _entreeSuspendue;
  Completer<void>? _verrouSuspendu;

  /// Clés dont `setValue` doit rendre `false`.
  final Set<String> refuse = <String>{};

  /// Clés dont `setValue` doit LEVER.
  final Set<String> leve = <String>{};

  /// Indices (1-based, comptés en `GETALL`) des lectures qui doivent LEVER.
  final Set<int> getAllLeve = <int>{};

  int _compteurGetAll = 0;

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
    _compteurGetAll++;
    journal.add('GETALL#$_compteurGetAll');
    if (getAllLeve.contains(_compteurGetAll)) {
      journal.add('GETALL-LEVE#$_compteurGetAll');
      throw StateError('panne de lecture simulée #$_compteurGetAll');
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
    if (leve.contains(key)) {
      journal.add('SET-LEVE $key');
      throw StateError('panne de stockage simulée sur $key');
    }
    if (refuse.contains(key)) {
      journal.add('SET-REFUS $key');
      return false;
    }
    _valeurs[key] = value;
    journal.add('SET-OK $key');
    return true;
  }

  /// Arme une suspension d'écriture sur [cle] (forme AVEC préfixe `flutter.`).
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

  void desarmer() {
    cleSuspendue = null;
    _entreeSuspendue = null;
    final v = _verrouSuspendu;
    _verrouSuspendu = null;
    if (v != null && !v.isCompleted) v.complete();
    getAllLeve.clear();
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  Set<String> clesEcritesDepuis(int index) => journal
      .skip(index)
      .where((e) => e.startsWith('SET-OK '))
      .map((e) => e.substring('SET-OK '.length))
      .toSet();

  bool aSupprimeDepuis(int index) =>
      journal.skip(index).any((e) => e.startsWith('REM '));
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

// ── Constantes ──────────────────────────────────────────────────────────────

const String kCleElo = 'elo_ratings_v2';
const String kCleRegistre = 'elo_registre_v3';
const String kCleMarqueurRegistre = '_elo_registre';
const String kCleMarqueurFormat = '_elo_format';
const String kCleMarqueurTs = '_elo_ts';

// ───────────────────────────────────────────────────────────────────────────
//  HELPERS DE SEMIS — mêmes conventions que B2-d2.
//  `nbCourses = 20` et `variationMois = 5.0` sont FIXES : `canoniqueRatings`
//  ne hache que clé + rating + nbCourses + variationMois, donc les empreintes
//  attendues sont calculables sans supposition.
// ───────────────────────────────────────────────────────────────────────────

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

Map<String, dynamic> _payloadElo(Map<String, double> ratings) {
  final data = <String, dynamic>{};
  _mapElo(ratings).forEach((cle, score) => data[cle] = score.toJson());
  return data;
}

String _empreinteDe(Map<String, double> ratings) =>
    empreinte64Ratings(_mapElo(ratings));

void _semerRatings(Map<String, double> ratings) {
  store.semer(kCleElo, jsonEncode(_payloadElo(ratings)));
}

void _semerRegistre(String valeur) => store.semer(kCleRegistre, valeur);

/// Entrée `horsCourse` HÉRITÉE — utilisée pour prouver qu'aucune entrée n'est
/// ajoutée ni supprimée par la restitution.
Map<String, dynamic> _entreeHeritee({
  required int id,
  required String empreinteAvant,
  String empreinteApres = '',
}) =>
    <String, dynamic>{
      'id': id,
      'type': 'horsCourse',
      'etape': 'appliquee',
      'issue': 'persistee',
      'tsIntention': 1776000000000,
      'tsFinal': 1776000000001,
      'empreinteAvant': empreinteAvant,
      'empreinteApres': empreinteApres.isEmpty ? empreinteAvant : empreinteApres,
      'motif': 'importBackup',
      'nbChevauxAvant': 0,
      'nbChevauxApres': 0,
    };

/// Registre BRUT, écrit en JSON par le test (jamais par le modèle) : c'est ce
/// qui garantit que les octets attendus sont ceux qu'on a écrits.
String _registreBrut({
  required String empreinte,
  int horloge = 0,
  List<Map<String, dynamic>> entrees = const <Map<String, dynamic>>[],
  String origine = 'courante',
  int schema = 3,
  int version = 1,
}) =>
    jsonEncode(<String, dynamic>{
      'schema': schema,
      'version': version,
      'horloge': horloge,
      'empreinteRatings': empreinte,
      'origine': origine,
      'entrees': entrees,
    });

/// Payload ENRICHI : ratings + les trois marqueurs, dont le registre VERBATIM.
Map<String, dynamic> _payloadEnrichi({
  required Map<String, double> ratings,
  required String registre,
  int ts = 1776000000000,
}) {
  final data = _payloadElo(ratings);
  data[kCleMarqueurFormat] = 'elo_v2';
  data[kCleMarqueurRegistre] = registre;
  data[kCleMarqueurTs] = ts;
  return data;
}

/// Relit le registre DU DISQUE et le décode avec le MODÈLE — c'est la seule
/// façon de prouver la restitution autrement que par une égalité de chaînes.
RegistreEloV3? _registreRelu() {
  final brut = store.lire(kCleRegistre);
  if (brut is! String) return null;
  return RegistreEloV3.decoder(brut);
}

/// Diagnostic recalculé sur l'état RÉEL du disque, via la fonction du modèle.
///
/// ⚠️ Le nombre de ratings est FOURNI par l'appelant, exactement comme
///    `_etablirDiagnosticPreImport` le fait : `diagnostiquerRegistre` ne peut
///    pas déduire le cardinal d'une empreinte.
ResultatDiagnosticElo _diagnosticDisque({required int nombreRatings}) {
  final brut = store.lire(kCleElo);
  final persistes = <String, EloScore>{};
  if (brut is String && brut.isNotEmpty) {
    final decode = jsonDecode(brut);
    if (decode is Map<String, dynamic>) {
      decode.forEach((k, v) {
        try {
          persistes[k] = EloScore.fromJson(v as Map<String, dynamic>);
        } catch (_) {}
      });
    }
  }
  final reg = store.lire(kCleRegistre);
  return diagnostiquerRegistre(
    jsonRegistre: reg is String ? reg : null,
    empreinteDisque: empreinte64Ratings(persistes),
    nombreRatings: nombreRatings,
  );
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
  //  A. PORTIER DE RESTAURATION — appareil vierge, registre cohérent,
  //     registre divergent, et barrières de reset.
  // ═════════════════════════════════════════════════════════════════════════

  group('A7-39-A — portier de restitution', () {
    // ───────────────────────────────────────────────────────────────────────
    //  M1 — APPAREIL VIERGE : rien sur le disque, sauvegarde enrichie.
    //  Prouve que le portier séparé ne bloque PAS ce cas (ce que
    //  `_doitEcrireTemoin` ferait, puisqu'il refuse `registreAbsent`), et que
    //  le registre est restitué À L'OCTET.
    // ───────────────────────────────────────────────────────────────────────
    test('M1 — appareil vierge : registre restitue VERBATIM, chaine identique',
        () async {
      // Verrou de non-régression sur la raison d'être du portier séparé.
      expect(
        MotifNonEcritureTemoin.values,
        contains(MotifNonEcritureTemoin.registreAbsent),
        reason: 'le motif qui interdit l\'écriture sur registre absent existe '
            'toujours : si le chemin enrichi passait par `_doitEcrireTemoin`, '
            'ce test échouerait faute d\'écriture',
      );

      const importees = <String, double>{
        'A7Z ALPHA|TROT_ATTELE': 1832.5,
        'A7Z BRAVO|TROT_ATTELE': 1610.0,
      };
      final registre = _registreBrut(
        empreinte: _empreinteDe(importees),
        horloge: 3,
        origine: 'courante',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 1, empreinteAvant: 'aaaa1111aaaa1111'),
          _entreeHeritee(id: 2, empreinteAvant: 'bbbb2222bbbb2222'),
        ],
      );

      // Disque VIDE : ni ratings, ni registre.
      expect(store.contient(kCleElo), isFalse);
      expect(store.contient(kCleRegistre), isFalse);

      final index = store.journal.length;
      final etat = await EloService.instance
          .importerDepuisBackup(_payloadEnrichi(ratings: importees, registre: registre));
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[M1] etat=${etat.name} | $res');

      // ── 1. Ratings persistés ET restitués ────────────────────────────────
      expect(etat, EtatPersistanceElo.persistee);
      expect(res.etatRatings, EtatPersistanceElo.persistee);
      expect(res.empreinteApres, _empreinteDe(importees));
      expect(res.empreinteAvant, _empreinteDe(const <String, double>{}),
          reason: 'l\'image « avant » décrit le DISQUE, qui était vide');

      // ── 2. Registre écrit, À L'OCTET ────────────────────────────────────
      expect(store.contient(kCleRegistre), isTrue);
      expect(store.lire(kCleRegistre), registre,
          reason: 'restitution VERBATIM : aucune réécriture, aucun tri, '
              'aucune entrée ajoutée');

      // ── 3. Le MODÈLE relit ce que le test a écrit ───────────────────────
      final relu = _registreRelu()!;
      expect(relu.interpretable, isTrue);
      expect(relu.horloge, 3, reason: 'horloge NON avancée : aucun import greffé');
      expect(relu.entrees.length, 2, reason: 'aucune entrée `importBackup` ajoutée');
      expect(relu.entrees.map((e) => e.id), <int>[1, 2]);
      expect(relu.origine, OrigineRegistreElo.courante,
          reason: 'A-2 : `courante` préservée UNIQUEMENT sur le chemin enrichi');
      expect(relu.schema, 3);
      expect(relu.version, 1);

      // ── 4. Résultat publié : origine du registre, pas `historiqueInconnu` │
      expect(res.origineAppliquee, OrigineRegistreElo.courante);
      expect(res.issueTemoin, IssueEcritureElo.persistee);
      expect(res.motifNonEcriture, isNull);

      // ── 5. Protection RÉELLE, recalculée sur la chaîne relue ────────────
      final diag = _diagnosticDisque(nombreRatings: importees.length);
      expect(diag.coherence, DiagnosticCoherenceElo.coherent);
      expect(diag.protegeContreDoubleApplication, isTrue,
          reason: 'le registre restauré est cohérent ET d\'origine `courante` '
              '→ la protection anti-double-application est bien retrouvée');

      // (a) `protegeApres` EST LA PROTECTION RÉELLEMENT CONSTATÉE.
      //     A7-39 (correction finale) : le résultat publié porte le verdict du
      //     MODÈLE recalculé sur la chaîne de registre relue APRÈS écriture —
      //     et non plus le diagnostic pré-import de l'appareil, qui valait
      //     `registreAbsent` ici et rendait `false` à tort.
      expect(res.protegeApres, diag.protegeContreDoubleApplication,
          reason: '`protegeApres` doit COÏNCIDER avec le diagnostic réel après '
              'restauration, mesuré sur le disque relu');
      expect(res.protegeApres, isTrue,
          reason: 'registre restauré cohérent + origine `courante` ⇒ protection '
              'réellement constatée, donc publiée');

      // (a-bis) LE CHEMIN HISTORIQUE reste, lui, sur son contrat d'origine :
      //    il n'y a RIEN à constater là-bas, puisque le témoin forcé
      //    `historiqueInconnu` rend la protection nulle par construction. Le
      //    lot conserve donc cette branche intacte — voir M7/M9 ci-dessous.

      // ── 6. Aucune suppression opportuniste de l'ancien registre ──────────
      expect(store.aSupprimeDepuis(index), isFalse);
      // Aucune écriture PARASITE : seules les clés ELO attendues.
      final ecrites = store.clesEcritesDepuis(index);
      expect(
        ecrites,
        <String>{
          'flutter.$kCleElo',
          'flutter.elo_ratings_v2_ts',
          'flutter.$kCleRegistre',
        },
        reason: 'le chemin enrichi n\'écrit RIEN d\'autre',
      );
    });

    // ───────────────────────────────────────────────────────────────────────
    //  M2 — ANCIEN REGISTRE COHÉRENT SUR L'APPAREIL : il est REMPLACÉ par
    //  celui de la sauvegarde, sans ajout d'entrée, et la protection suit le
    //  registre RESTAURÉ (pas l'ancien).
    // ───────────────────────────────────────────────────────────────────────
    test('M2 — ancien registre coherent : remplace sans ajout, protection suit',
        () async {
      // État de l'appareil : 1 rating, registre cohérent avec 1 entrée.
      const ancien = <String, double>{'A7Z VIEUX|TROT_ATTELE': 1500.0};
      _semerRatings(ancien);
      final ancienRegistre = _registreBrut(
        empreinte: _empreinteDe(ancien),
        horloge: 7,
        origine: 'courante',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 1, empreinteAvant: '1111222233334444'),
        ],
      );
      _semerRegistre(ancienRegistre);
      EloService.instance.chargerDepuisMapIsolate(_payloadElo(ancien));

      // Sauvegarde : 2 ratings DIFFÉRENTS, registre cohérent avec eux.
      const importees = <String, double>{
        'A7Z NOUVEAU|TROT_ATTELE': 1700.0,
        'A7Z AUTRE|TROT_ATTELE': 1555.0,
      };
      final nouveauRegistre = _registreBrut(
        empreinte: _empreinteDe(importees),
        horloge: 11,
        origine: 'courante',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 1, empreinteAvant: '9999888877776666'),
          _entreeHeritee(id: 2, empreinteAvant: '5555444433332222'),
        ],
      );

      final index = store.journal.length;
      final etat = await EloService.instance.importerDepuisBackup(
          _payloadEnrichi(ratings: importees, registre: nouveauRegistre));
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[M2] etat=${etat.name} | $res');

      expect(etat, EtatPersistanceElo.persistee);
      expect(res.empreinteAvant, _empreinteDe(ancien),
          reason: 'le diagnostic décrit bien le disque AVANT import');
      expect(res.coherenceAvant, DiagnosticCoherenceElo.coherent);
      expect(res.empreinteApres, _empreinteDe(importees));

      expect(store.lire(kCleRegistre), nouveauRegistre,
          reason: 'le registre de la sauvegarde remplace l\'ancien, verbatim');

      final relu = _registreRelu()!;
      expect(relu.horloge, 11);
      expect(relu.entrees.length, 2,
          reason: 'ANCIEN=1 + 1 si le chemin historique avait tourné ; '
              '2 prouve que c\'est bien le registre importé');
      expect(relu.entrees.map((e) => e.id), <int>[1, 2]);
      expect(relu.origine, OrigineRegistreElo.courante,
          reason: 'PAS `historiqueInconnu` — discrimine les deux chemins');

      final diag = _diagnosticDisque(nombreRatings: importees.length);
      expect(diag.coherence, DiagnosticCoherenceElo.coherent);
      expect(diag.protegeContreDoubleApplication, isTrue);
      // La protection publiée suit le registre RESTAURÉ, pas l'ancien : les
      // deux coïncident ici parce que l'ancien registre était lui aussi
      // cohérent, mais la valeur doit venir de la constatation post-écriture.
      expect(res.protegeApres, diag.protegeContreDoubleApplication,
          reason: 'protection constatée sur le disque relu, pas déduite de '
              'l\'état antérieur de l\'appareil');
      expect(store.aSupprimeDepuis(index), isFalse);
    });

    // ───────────────────────────────────────────────────────────────────────
    //  M3 — c) REGISTRE DIVERGENT SUR L'APPAREIL : la restitution est permise
    //  (décidée AVANT mutation, donc elle ne dépend pas de l'état appareil),
    //  et elle RÉPARE la divergence sans jamais toucher aux ratings importés.
    // ───────────────────────────────────────────────────────────────────────
    test('M3 — registre divergent sur l\'appareil : restaure sans supprimer',
        () async {
      const ancien = <String, double>{'A7Z VIEUX|TROT_ATTELE': 1500.0};
      _semerRatings(ancien);
      // Registre divergent : empreinte NE décrivant PAS les ratings du disque.
      _semerRegistre(_registreBrut(
        empreinte: 'deadbeefdeadbeef',
        horloge: 4,
        origine: 'historiqueInconnu',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 1, empreinteAvant: 'aaaabbbbccccdddd'),
        ],
      ));
      EloService.instance.chargerDepuisMapIsolate(_payloadElo(ancien));

      const importees = <String, double>{'A7Z NOUVEAU|TROT_ATTELE': 1750.0};
      final nouveauRegistre = _registreBrut(
        empreinte: _empreinteDe(importees),
        horloge: 2,
        origine: 'courante',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 9, empreinteAvant: '1234123412341234'),
        ],
      );

      final index = store.journal.length;
      final etat = await EloService.instance.importerDepuisBackup(
          _payloadEnrichi(ratings: importees, registre: nouveauRegistre));
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[M3] etat=${etat.name} | $res');

      expect(etat, EtatPersistanceElo.persistee);
      expect(res.coherenceAvant, DiagnosticCoherenceElo.divergent,
          reason: 'l\'état de l\'appareil est bien constaté divergent');

      expect(store.lire(kCleRegistre), nouveauRegistre);
      final relu = _registreRelu()!;
      expect(relu.entrees.map((e) => e.id), <int>[9],
          reason: 'l\'entrée divergente de l\'appareil n\'est PAS conservée : '
              'on écrit le registre de la sauvegarde, rien de plus');
      expect(relu.origine, OrigineRegistreElo.courante);

      final diag = _diagnosticDisque(nombreRatings: importees.length);
      expect(diag.coherence, DiagnosticCoherenceElo.coherent,
          reason: 'la divergence est résorbée par la restitution');
      expect(diag.protegeContreDoubleApplication, isTrue);

      // M3 est le cas le plus parlant : l'appareil était DIVERGENT avant
      // l'import, donc le diagnostic PRÉ-import rendait une protection nulle.
      // Si `protegeApres` valait encore `true`, cela ne pourrait venir que de
      // la chaîne relue APRÈS écriture — c'est exactement ce qu'on vérifie.
      expect(res.coherenceAvant, DiagnosticCoherenceElo.divergent);
      expect(res.protegeApres, diag.protegeContreDoubleApplication,
          reason: 'la valeur publiée doit être CELLE du diagnostic réel après '
              'restauration, pas celle de l\'état antérieur de l\'appareil');
      expect(res.protegeApres, isTrue,
          reason: 'protection CONSTATÉE après restauration alors qu\'elle était '
              'absente avant : preuve que la valeur vient de la relecture');

      // Exigence 9 : jamais de suppression de l'ancien registre.
      expect(store.aSupprimeDepuis(index), isFalse);
      expect(store.contient(kCleRegistre), isTrue);
    });

    // ───────────────────────────────────────────────────────────────────────
    //  M6 — RESET CONCURRENT PENDANT L'ÉCRITURE DU REGISTRE.
    //  La file + le drain doivent attendre cette écriture : aucun registre ne
    //  doit être RECRÉÉ après l'effacement du reset.
    // ───────────────────────────────────────────────────────────────────────
    test('M6 — reset pendant l\'ecriture du registre : aucune resurrection',
        () async {
      const importees = <String, double>{'A7Z ALPHA|TROT_ATTELE': 1900.0};
      final registre = _registreBrut(
        empreinte: _empreinteDe(importees),
        horloge: 5,
        origine: 'courante',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 1, empreinteAvant: 'ffee0011ffee0011'),
        ],
      );

      // Suspension EXACTE de l'écriture du registre.
      final atteinte = store.armerSuspension('flutter.$kCleRegistre');

      final futur = EloService.instance
          .importerDepuisBackup(_payloadEnrichi(ratings: importees, registre: registre));

      await atteinte; // les ratings sont écrits, le registre est BLOQUÉ

      // Reset concurrent : la barrière est posée de façon SYNCHRONE.
      final reset = EloService.instance.executerResetComplet(() async {
        await store.clear();
      });

      await _laisserProgresser();
      store.libererSuspension();

      final etat = await futur;
      await reset;
      await _laisserProgresser();

      // ignore: avoid_print
      print('[M6] etat=${etat.name}');

      // Le contrat du drain : la clé effacée ne doit PAS réapparaître.
      expect(store.contient(kCleRegistre), isFalse,
          reason: 'l\'écriture suspendue est drainée AVANT l\'effacement, ou '
              'abandonnée par la génération : dans les deux cas, aucune '
              'résurrection de `elo_registre_v3`');
      expect(store.contient(kCleElo), isFalse);

      // Et le résultat ne revendique RIEN : ni protection, ni témoin persisté.
      final res = EloService.instance.dernierResultatImport;
      if (res != null) {
        expect(res.protegeApres, isFalse,
            reason: 'ni le registre ni les ratings ne survivent au reset : '
                'aucune protection ne peut être constatée');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B. CHEMINS NÉGATIFS — refus anticipé, persistance, relecture
  // ═════════════════════════════════════════════════════════════════════════

  group('A7-39-B — refus anticipés et preuves manquantes', () {
    /// Vérifie qu'un refus anticipé n'a touché NI les ratings, NI le registre,
    /// NI tenté la moindre écriture.
    Future<void> verifierRefusAnticipe({
      required String libelle,
      required Map<String, dynamic> payload,
      required MotifNonEcritureTemoin motifAttendu,
      String? registreAppareil,
    }) async {
      const ancien = <String, double>{'A7Z VIEUX|TROT_ATTELE': 1500.0};
      _semerRatings(ancien);
      if (registreAppareil != null) _semerRegistre(registreAppareil);
      EloService.instance.chargerDepuisMapIsolate(_payloadElo(ancien));

      final registreAvant = store.lire(kCleRegistre);
      final ratingsAvant = store.lire(kCleElo);
      final index = store.journal.length;

      final etat = await EloService.instance.importerDepuisBackup(payload);
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[$libelle] etat=${etat.name} | $res');

      expect(etat, EtatPersistanceElo.nonTentee,
          reason: 'une tentative refusée n\'est PAS un échec');
      expect(res.motifNonEcriture, motifAttendu);
      expect(res.issueTemoin, isNull);
      expect(res.empreinteApres, isNull,
          reason: 'aucune mutation : il n\'y a pas d\'« après »');
      expect(res.origineAppliquee, isNull);
      // AUCUNE PROTECTION PUBLIÉE — ni constatée, ni supposée. Sur un refus
      // anticipé rien n'a été écrit : il n'existe aucune preuve à publier.
      expect(res.protegeApres, isFalse,
          reason: 'un refus anticipé n\'a produit AUCUNE preuve : annoncer une '
              'protection ici serait une fausse sécurité');

      // RAM INTACTE — la même que celle d'avant l'appel.
      expect(EloService.instance.nbChevauxSuivis, ancien.length,
          reason: 'aucune mutation RAM sur un refus anticipé');

      // DISQUE INTACT — octet pour octet.
      expect(store.lire(kCleElo), ratingsAvant);
      expect(store.lire(kCleRegistre), registreAvant);

      // AUCUNE écriture, AUCUNE suppression.
      expect(store.clesEcritesDepuis(index), isEmpty,
          reason: 'le refus anticipé est INOFFENSIF : zéro écriture');
      expect(store.aSupprimeDepuis(index), isFalse);
    }

    test('M4a — registre illisible : refus anticipe, ratings intacts',
        () async {
      const importees = <String, double>{'A7Z NEW|TROT_ATTELE': 1700.0};
      final payload = _payloadEnrichi(ratings: importees, registre: 'pas-du-json{');
      await verifierRefusAnticipe(
        libelle: 'M6-1',
        payload: payload,
        motifAttendu: MotifNonEcritureTemoin.registreEnrichiIllisible,
        registreAppareil: _registreBrut(
          empreinte: _empreinteDe(const <String, double>{'A7Z VIEUX|TROT_ATTELE': 1500.0}),
          origine: 'courante',
        ),
      );
    });

    test('M4b — registre incoherent avec ses ratings : refus anticipe', () async {
      const importees = <String, double>{'A7Z NEW|TROT_ATTELE': 1700.0};
      // Le registre déclare une empreinte qui ne décrit PAS les ratings joints.
      final payload = _payloadEnrichi(
        ratings: importees,
        registre: _registreBrut(empreinte: 'ffff0000ffff0000', origine: 'courante'),
      );
      await verifierRefusAnticipe(
        libelle: 'M6-2',
        payload: payload,
        motifAttendu: MotifNonEcritureTemoin.registreEnrichiIncoherent,
      );
    });

    test('M4c — schema/version inconnus : refus anticipe', () async {
      const importees = <String, double>{'A7Z NEW|TROT_ATTELE': 1700.0};
      final payload = _payloadEnrichi(
        ratings: importees,
        registre: _registreBrut(
          empreinte: _empreinteDe(importees),
          schema: 4, // inconnu du code courant
          origine: 'courante',
        ),
      );
      await verifierRefusAnticipe(
        libelle: 'M6-3',
        payload: payload,
        motifAttendu: MotifNonEcritureTemoin.registreEnrichiIllisible,
      );
    });

    test('M4d — registre non textuel : refus anticipe', () async {
      const importees = <String, double>{'A7Z NEW|TROT_ATTELE': 1700.0};
      final payload = _payloadElo(importees);
      payload[kCleMarqueurFormat] = 'elo_v2';
      payload[kCleMarqueurRegistre] = 42; // ni chaîne ni null
      await verifierRefusAnticipe(
        libelle: 'M6-4',
        payload: payload,
        motifAttendu: MotifNonEcritureTemoin.registreEnrichiNonTextuel,
      );
    });

    // ───────────────────────────────────────────────────────────────────────
    //  M5a — PERSISTANCE DES RATINGS REFUSÉE : AUCUN registre écrit.
    //  Exigence 5 : ne jamais écrire le registre si la persistance n'est pas
    //  confirmée.
    // ───────────────────────────────────────────────────────────────────────
    test('M5a — persistance ratings refusee : aucun registre ecrit', () async {
      const importees = <String, double>{'A7Z ALPHA|TROT_ATTELE': 1800.0};
      final registre = _registreBrut(
        empreinte: _empreinteDe(importees),
        origine: 'courante',
      );

      store.refuse.add('flutter.$kCleElo'); // setString → false sur les ratings

      final index = store.journal.length;
      final etat = await EloService.instance
          .importerDepuisBackup(_payloadEnrichi(ratings: importees, registre: registre));
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[M5a] etat=${etat.name} | $res');

      expect(etat, EtatPersistanceElo.refusee);
      expect(store.contient(kCleRegistre), isFalse,
          reason: 'exigence 5 : pas de registre sans persistance confirmée');
      expect(store.clesEcritesDepuis(index).contains('flutter.$kCleRegistre'),
          isFalse);

      expect(res.issueTemoin, isNull);
      expect(
        res.motifNonEcriture,
        anyOf(
          MotifNonEcritureTemoin.ratingsNonPersistes,
          MotifNonEcritureTemoin.relectureNonConfirmee,
        ),
        reason: 'le motif doit dire la VRAIE raison, jamais un succès',
      );
      // Exigence 3 de la correction : une écriture NON CONFIRMÉE ne doit jamais
      // produire une protection annoncée. Aucune constatation n'a eu lieu
      // puisque le registre n'a pas été écrit.
      expect(res.protegeApres, isFalse,
          reason: 'registre non écrit ⇒ aucune protection constatable');
    });

    // ───────────────────────────────────────────────────────────────────────
    //  M5b — RELECTURE NON CONFIRMÉE : `setString` a dit `true`, mais le
    //  contenu relu n'existe pas. Exigence 6 : un booléen n'est pas une preuve
    //  de contenu, donc le registre n'est PAS écrit.
    // ───────────────────────────────────────────────────────────────────────
    test('M5b — relecture non confirmee : aucun registre ecrit', () async {
      const importees = <String, double>{'A7Z ALPHA|TROT_ATTELE': 1800.0};
      final registre = _registreBrut(
        empreinte: _empreinteDe(importees),
        origine: 'courante',
      );

      // La relecture du registre a lieu APRÈS `_sauvegarder`. On fait donc
      // lever une lecture TARDIVE : la 3e (1re = getInstance, 2e = reload du
      // diagnostic, 3e = reload de la relecture prouvante). La valeur exacte
      // est VÉRIFIÉE ci-dessous plutôt que supposée.
      store.getAllLeve.add(3);

      final etat = await EloService.instance
          .importerDepuisBackup(_payloadEnrichi(ratings: importees, registre: registre));
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[M5b] etat=${etat.name} | $res | journal=${store.journal}');

      expect(store.contient(kCleRegistre), isFalse,
          reason: 'exigence 6 : sans relecture prouvante, AUCUN registre');
      // Exigence 3 de la correction : relecture non confirmée ⇒ la constatation
      // de protection ne peut pas avoir lieu, et n'est donc pas revendiquée.
      expect(res.protegeApres, isFalse,
          reason: 'sans relecture confirmée, aucune protection n\'est constatée');
      expect(res.issueTemoin, isNull);
      expect(res.motifNonEcriture, isNotNull,
          reason: 'un non-écrit doit TOUJOURS être motivé');
      // Le motif doit rester dans la famille « preuve manquante ».
      expect(
        res.motifNonEcriture,
        anyOf(
          MotifNonEcritureTemoin.relectureNonConfirmee,
          MotifNonEcritureTemoin.ratingsNonPersistes,
          MotifNonEcritureTemoin.echoueeParException,
        ),
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C. CHEMIN HISTORIQUE — contrat A-2, sauvegarde SANS registre
  // ═════════════════════════════════════════════════════════════════════════

  group('A7-39-C — chemin historique preserve', () {
    test('M7 — sauvegarde sans registre : temoin ajoute, origine inconnue',
        () async {
      const ancien = <String, double>{'A7Z VIEUX|TROT_ATTELE': 1500.0};
      _semerRatings(ancien);
      _semerRegistre(_registreBrut(
        empreinte: _empreinteDe(ancien),
        horloge: 1,
        origine: 'courante',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 1, empreinteAvant: '0102030405060708'),
        ],
      ));
      EloService.instance.chargerDepuisMapIsolate(_payloadElo(ancien));

      const importees = <String, double>{'A7Z NEW|TROT_ATTELE': 1650.0};

      final index = store.journal.length;
      // PAYLOAD SANS `_elo_registre` — exactement le format historique.
      final etat = await EloService.instance
          .importerDepuisBackup(_payloadElo(importees));
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[M7] etat=${etat.name} | $res');

      expect(etat, EtatPersistanceElo.persistee);
      expect(res.issueTemoin, IssueEcritureElo.persistee);
      expect(res.motifNonEcriture, isNull);
      expect(res.origineAppliquee, OrigineRegistreElo.historiqueInconnu,
          reason: 'A-2 : une sauvegarde sans registre ne peut PAS prétendre '
              'connaître l\'historique');

      // Le registre de l'appareil a reçu UNE entrée de plus, d'origine forcée.
      final relu = _registreRelu()!;
      expect(relu.entrees.length, 2, reason: '1 héritée + 1 témoin d\'import');
      expect(relu.origine, OrigineRegistreElo.historiqueInconnu);
      expect(relu.horloge, 2, reason: 'horloge avancée par l\'allocation');
      expect(relu.empreinteRatings, _empreinteDe(importees));

      // Et la protection est BEL ET BIEN perdue — c'est honnête, pas cassé.
      final diag = _diagnosticDisque(nombreRatings: importees.length);
      expect(diag.coherence, DiagnosticCoherenceElo.coherent);
      expect(diag.protegeContreDoubleApplication, isFalse,
          reason: '`historiqueInconnu` ⇒ aucune protection revendiquable');
      // CHEMIN HISTORIQUE PRÉSERVÉ À L'IDENTIQUE : la constatation post-écriture
      // n'est PAS faite sur ce chemin (aucune relecture supplémentaire), et la
      // formule B2-d2 d'origine s'applique. Le résultat coïncide donc toujours
      // avec le diagnostic réel — ici `false` des deux côtés.
      expect(res.protegeApres, isFalse,
          reason: 'témoin `historiqueInconnu` ⇒ protection nulle, et la valeur '
              'publiée reste celle de la formule d\'origine');
      expect(res.protegeApres, diag.protegeContreDoubleApplication,
          reason: 'le contrat historique n\'est pas modifié : la valeur reste '
              'l\'image exacte du diagnostic');

      expect(store.contient(kCleRegistre), isTrue);
      expect(store.aSupprimeDepuis(index), isFalse);
    });

    test('M8 — sauvegarde sans registre ET appareil sans registre : aucun temoin',
        () async {
      const importees = <String, double>{'A7Z NEW|TROT_ATTELE': 1650.0};
      final index = store.journal.length;

      final etat = await EloService.instance
          .importerDepuisBackup(_payloadElo(importees));
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[M8] etat=${etat.name} | $res');

      expect(etat, EtatPersistanceElo.persistee);
      expect(res.motifNonEcriture, MotifNonEcritureTemoin.registreAbsent,
          reason: 'D5 : sur registre absent, on n\'écrit PAS de témoin');
      expect(res.issueTemoin, isNull);
      expect(store.contient(kCleRegistre), isFalse);
      // Aucun registre écrit ⇒ rien à relire ⇒ aucune protection constatable.
      expect(res.protegeApres, isFalse,
          reason: 'D5 : sans registre sur l\'appareil, rien n\'est écrit et '
              'rien ne peut être constaté');
      expect(store.aSupprimeDepuis(index), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  D. `protegeApres` — EXACTITUDE DU RÉSULTAT APRÈS CORRECTION
  //
  //  ── CE QUE CE GROUPE A ÉTABLI AVANT LA CORRECTION (constat archivé) ───────
  //  La formule B2-d2 (`etat == persistee && empreinte disque inchangée &&
  //  issueTemoin != persistee && diagnostic.protegeContreDoubleApplication`)
  //  lisait le verdict portant sur l'appareil AVANT import. Elle mesurait donc
  //  une INTENTION D'ÉCRIRE UN TÉMOIN, pas la protection après l'opération. Le
  //  chemin enrichi d'A7-39 en produisait deux conséquences mesurées :
  //     • M1/M10 : appareil vierge (`coherenceAvant == registreAbsent`) ⇒
  //       `false` publié alors que le registre restauré protège réellement ;
  //     • M9 : appareil déjà cohérent, mêmes ratings ⇒ `true` publié alors que
  //       RIEN n'a été écrit et qu'aucune protection n'a été créée.
  //
  //  ── CE QUE CE GROUPE VÉRIFIE MAINTENANT ───────────────────────────────────
  //  La correction autorisée publie, sur le chemin enrichi, le verdict du MODÈLE
  //  recalculé sur la chaîne de registre RÉELLEMENT RELUE après écriture. Les
  //  deux tests ci-dessous doivent donc désormais COÏNCIDER avec le diagnostic
  //  réel dans les deux sens — c'est la définition d'un résultat exact.
  // ═════════════════════════════════════════════════════════════════════════

  group('A7-39-D — protegeApres : exactitude après correction', () {
    // ───────────────────────────────────────────────────────────────────────
    //  M9 — AUCUNE ÉCRITURE, AUCUNE PROTECTION CRÉÉE, et pourtant une
    //  protection RÉELLE préexistante : le résultat doit dire la vérité sur
    //  l'état du registre, pas sur l'absence d'écriture.
    // ───────────────────────────────────────────────────────────────────────
    test('M9 — protegeApres reflete la protection REELLE, sans ecriture',
        () async {
      const memes = <String, double>{'A7Z IDEM|TROT_ATTELE': 1600.0};
      _semerRatings(memes);
      _semerRegistre(_registreBrut(
        empreinte: _empreinteDe(memes),
        horloge: 1,
        origine: 'courante',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 1, empreinteAvant: 'aaaabbbbccccdddd'),
        ],
      ));
      EloService.instance.chargerDepuisMapIsolate(_payloadElo(memes));

      final registreAvant = store.lire(kCleRegistre);
      final index = store.journal.length;

      // Import des MÊMES ratings : aucune empreinte ne change.
      final etat =
          await EloService.instance.importerDepuisBackup(_payloadElo(memes));
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[M9] etat=${etat.name} | $res');

      expect(etat, EtatPersistanceElo.persistee);
      // `aucunChangement` : rien n'a bougé, donc aucun témoin n'est écrit.
      expect(res.motifNonEcriture, MotifNonEcritureTemoin.aucunChangement);
      expect(res.issueTemoin, isNull);

      // La protection est réelle (elle préexistait) : la valeur publiée doit
      // donc être `true`, mais parce qu'elle est CONSTATÉE, pas par accident.
      expect(res.protegeApres, isTrue,
          reason: 'la protection existe réellement sur le disque : le résultat '
              'doit la refléter');

      // …alors que RIEN n'a été écrit et que le registre est identique.
      expect(store.lire(kCleRegistre), registreAvant,
          reason: 'aucune écriture du registre sur ce chemin');

      // Et la protection lue sur le disque est celle d'AVANT : `courante` et
      // aucun témoin écrit. Elle préexistait à l'appel, rien n'a été créé ici.
      final diag = _diagnosticDisque(nombreRatings: memes.length);
      expect(diag.protegeContreDoubleApplication, isTrue);

      // ⇒ Le résultat publié reflète EXACTEMENT ce que dit le disque : ici la
      //   valeur est `true`, mais elle l'est parce que la protection existe,
      //   non parce qu'une écriture a eu lieu. C'est la définition d'un
      //   résultat exact — et non plus un décalage entre intention et réalité.
      expect(res.protegeApres, diag.protegeContreDoubleApplication,
          reason: '`protegeApres` doit être l\'image de la protection réelle, '
              'même quand aucune écriture n\'a eu lieu');
      expect(store.clesEcritesDepuis(index).contains('flutter.$kCleRegistre'),
          isFalse);
    });

    // ───────────────────────────────────────────────────────────────────────
    //  M10 — RESTITUTION VERBATIM SUR APPAREIL VIERGE. Avant correction, ce
    //  test était le contre-exemple : `protegeApres` valait `false` alors que
    //  la protection était réellement retrouvée. Après correction, les deux
    //  valeurs doivent COÏNCIDER.
    // ───────────────────────────────────────────────────────────────────────
    test('M10 — restitution verbatim : protegeApres = protection REELLE',
        () async {
      const importees = <String, double>{'A7Z NEUF|TROT_ATTELE': 1888.0};
      final registre = _registreBrut(
        empreinte: _empreinteDe(importees),
        horloge: 6,
        origine: 'courante',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 1, empreinteAvant: '0101010101010101'),
        ],
      );

      final etat = await EloService.instance.importerDepuisBackup(
          _payloadEnrichi(ratings: importees, registre: registre));
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[M10] etat=${etat.name} | $res');

      // La protection RÉELLE, lue sur le disque et calculée par le MODÈLE :
      final diag = _diagnosticDisque(nombreRatings: importees.length);
      expect(diag.coherence, DiagnosticCoherenceElo.coherent);
      expect(diag.protegeContreDoubleApplication, isTrue,
          reason: 'PROTECTION RÉELLEMENT RETROUVÉE : registre cohérent + '
              'origine `courante`');

      // AVANT correction, ces deux valeurs DIVERGEAIENT : la formule lisait le
      // diagnostic PRÉ-import (`registreAbsent` sur appareil vierge) et rendait
      // `false`. Elles doivent désormais COÏNCIDER — c'est précisément ce que
      // la correction autorisée devait produire.
      expect(res.protegeApres, diag.protegeContreDoubleApplication,
          reason: 'le résultat d\'import doit être l\'image EXACTE de la '
              'protection constatée après restauration');
      expect(res.protegeApres, isTrue,
          reason: 'protection réelle après restitution ⇒ publiée telle quelle');
    });

    // ───────────────────────────────────────────────────────────────────────
    //  M11 — ÉCHEC DE LA RELECTURE FINALE, SUR UN APPAREIL DÉJÀ COHÉRENT ET
    //  PROTÉGÉ. C'est LE cas que la dernière vérification exige de reproduire.
    //
    //  AVANT CORRECTION, `protectionConstatee ?? protectionPreservee` faisait
    //  retomber ce `null` sur la formule B2-d2, laquelle lit encore le
    //  diagnostic PRÉ-import. L'appareil étant cohérent, protégé, avec une
    //  empreinte inchangée et aucun témoin tenté, cette formule rendait `true`
    //  — une protection REVENDIQUÉE alors que la constatation post-import
    //  n'avait jamais abouti. C'est la fausse sécurité à interdire.
    // ───────────────────────────────────────────────────────────────────────
    test('M11 — relecture finale en echec : aucune protection revendiquee',
        () async {
      // Appareil PROPRIÉTAIRE d'un registre COHÉRENT et PROTÉGÉ.
      const memes = <String, double>{'A7Z PROTEGE|TROT_ATTELE': 1720.0};
      _semerRatings(memes);
      final registreAppareil = _registreBrut(
        empreinte: _empreinteDe(memes),
        horloge: 8,
        origine: 'courante',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 1, empreinteAvant: 'aaaabbbbccccdddd'),
        ],
      );
      _semerRegistre(registreAppareil);
      EloService.instance.chargerDepuisMapIsolate(_payloadElo(memes));

      // La protection pré-import est RÉELLE — c'est la condition du piège.
      final avant = _diagnosticDisque(nombreRatings: memes.length);
      expect(avant.coherence, DiagnosticCoherenceElo.coherent);
      expect(avant.protegeContreDoubleApplication, isTrue);

      // Sauvegarde ENRICHIE portant un registre cohérent avec les mêmes
      // ratings : le chemin enrichi est bien celui qui sera pris.
      final registreSauvegarde = _registreBrut(
        empreinte: _empreinteDe(memes),
        horloge: 12,
        origine: 'courante',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 4, empreinteAvant: 'eeeeffff00001111'),
        ],
      );

      // ── Panne de la RELECTURE FINALE, et d'elle SEULE. ────────────────────
      // Indice MESURÉ, puis VÉRIFIÉ par le test lui-même : sur ce scénario le
      // journal est
      //   GETALL#1 (diagnostic getInstance) → GETALL#2 (diagnostic reload)
      //   → SET ratings, SET ts → GETALL#3 (relecture prouvante)
      //   → SET registre → GETALL#4 (CONSTATATION post-écriture)
      // La constatation est donc la PREMIÈRE lecture qui suit l'écriture du
      // registre. On l'arme, et l'assertion plus bas le confirme au lieu de le
      // supposer (un `SET-OK flutter.elo_registre_v3` doit précéder
      // `GETALL-LEVE#4`, et rien d'autre ne doit être levé).
      store.getAllLeve.add(4);

      final etat = await EloService.instance.importerDepuisBackup(
          _payloadEnrichi(ratings: memes, registre: registreSauvegarde));
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[M11] etat=${etat.name} | $res | journal=${store.journal}');

      // ── Preuve que la panne a bien visé la constatation, et elle seule ────
      final journal = store.journal;
      final idxRegistreEcrit =
          journal.lastIndexOf('SET-OK flutter.$kCleRegistre');
      final idxLeve = journal.indexOf('GETALL-LEVE#4');
      expect(idxRegistreEcrit, greaterThanOrEqualTo(0),
          reason: 'le registre doit avoir été écrit : l\'échec visé est celui '
              'de la constatation, pas celui de la restitution');
      expect(idxLeve, greaterThan(idxRegistreEcrit),
          reason: 'la lecture levée doit être POSTÉRIEURE à l\'écriture du '
              'registre : c\'est bien la constatation post-import qui échoue');
      expect(journal.where((e) => e.startsWith('GETALL-LEVE#')).length, 1,
          reason: 'une seule lecture échoue, celle de la constatation');

      expect(etat, EtatPersistanceElo.persistee);
      expect(res.motifNonEcriture, isNull,
          reason: 'l\'écriture du registre a bien eu lieu : le seul échec est '
              'celui de la constatation, pas celui de la restitution');

      // Le registre EST écrit : la restitution a réussi.
      expect(store.contient(kCleRegistre), isTrue);
      expect(store.lire(kCleRegistre), registreSauvegarde,
          reason: 'restitution verbatim confirmée malgré l\'échec de lecture');

      // ⚠️ ASSERTION CENTRALE : sans constatation post-import, AUCUNE
      // protection ne doit être revendiquée, même si l'appareil était protégé
      // avant et même si l'empreinte n'a pas changé.
      expect(res.protegeApres, isFalse,
          reason: 'CHEMIN ENRICHI : une protection non constatée ne doit '
              'JAMAIS être publiée, quel que soit l\'état antérieur de '
              'l\'appareil');

      // Et le registre réellement en place est, lui, bien protégé : la valeur
      // `false` décrit donc un DÉFAUT DE PREUVE, pas une absence de protection.
      final apres = _diagnosticDisque(nombreRatings: memes.length);
      expect(apres.protegeContreDoubleApplication, isTrue,
          reason: 'la protection existe sur le disque, mais elle n\'a pas été '
              'constatée dans le même souffle ⇒ non revendiquée');
    });

    // ───────────────────────────────────────────────────────────────────────
    //  M13 — LE SEUL CAS OÙ LE REPLI `??` PRODUISAIT RÉELLEMENT UN `true` FAUX.
    //
    //  Mesure préalable, à ne pas confondre avec M11 : `protectionPreservee`
    //  exige `issueTemoin != persistee`. Une relecture finale en échec laisse
    //  `issueTemoin == persistee` (l'écriture a réussi) et le repli rend donc
    //  `false` — M11 le vérifie et passe AVANT comme APRÈS correction.
    //
    //  Le repli ne devient dangereux que si l'ÉCRITURE DU REGISTRE elle-même
    //  n'aboutit pas (`issueTemoin == refusee`) ALORS QUE :
    //    • les ratings, eux, sont persistés (`etat == persistee`) ;
    //    • l'empreinte du disque est inchangée (import des mêmes ratings) ;
    //    • l'appareil possédait déjà un registre cohérent et protégé.
    //  Les quatre termes de `protectionPreservee` sont alors satisfaits et la
    //  formule rend `true`… sans qu'aucune constatation post-import ait eu lieu,
    //  et sans que la moindre écriture de registre soit confirmée. C'est la
    //  fausse sécurité. Ce test-ci DISCRIMINE : il échoue sur l'ancienne
    //  formule, il passe sur la formule corrigée.
    // ───────────────────────────────────────────────────────────────────────
    test('M13 — ecriture du registre refusee : aucune protection revendiquee',
        () async {
      const memes = <String, double>{'A7Z PROTEGE|TROT_ATTELE': 1720.0};
      _semerRatings(memes);
      final registreAppareil = _registreBrut(
        empreinte: _empreinteDe(memes),
        horloge: 8,
        origine: 'courante',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 1, empreinteAvant: 'aaaabbbbccccdddd'),
        ],
      );
      _semerRegistre(registreAppareil);
      EloService.instance.chargerDepuisMapIsolate(_payloadElo(memes));

      // L'appareil est PROTÉGÉ avant l'import : c'est la condition du piège.
      final avant = _diagnosticDisque(nombreRatings: memes.length);
      expect(avant.protegeContreDoubleApplication, isTrue);

      // Sauvegarde ENRICHIE cohérente avec des ratings IDENTIQUES : aucune
      // empreinte ne bouge, donc `empreintesIdentiques` sera vrai.
      final registreSauvegarde = _registreBrut(
        empreinte: _empreinteDe(memes),
        horloge: 12,
        origine: 'courante',
        entrees: <Map<String, dynamic>>[
          _entreeHeritee(id: 4, empreinteAvant: 'eeeeffff00001111'),
        ],
      );

      // ⚠️ SEUL le registre est refusé : les ratings sont bien persistés, donc
      //    `etat == persistee`. Rien n'est alors relisible pour constater quoi
      //    que ce soit.
      store.refuse.add('flutter.$kCleRegistre');

      final etat = await EloService.instance.importerDepuisBackup(
          _payloadEnrichi(ratings: memes, registre: registreSauvegarde));
      await _laisserProgresser();

      final res = EloService.instance.dernierResultatImport!;
      // ignore: avoid_print
      print('[M13] etat=${etat.name} | $res');

      // L'écriture a bien été TENTÉE puis refusée : ce n'est pas un non-écrit
      // silencieux, la distinction est publiée.
      expect(etat, EtatPersistanceElo.persistee,
          reason: 'les ratings sont persistés : c\'est le registre qui échoue');
      expect(res.issueTemoin, IssueEcritureElo.refusee,
          reason: 'le refus du registre doit être visible, jamais tu');
      expect(res.motifNonEcriture, isNotNull);

      // Le registre de l'appareil est resté INTACT — c'est précisément ce qui
      // rend l'ancienne formule concluante à tort.
      expect(store.lire(kCleRegistre), registreAppareil,
          reason: 'registre existant préservé, aucune réparation automatique');

      // ⚠️ ASSERTION DISCRIMINANTE : aucune protection n'a pu être CONSTATÉE
      // après l'import, donc aucune ne doit être publiée.
      expect(res.protegeApres, isFalse,
          reason: 'CHEMIN ENRICHI : aucune constatation post-import possible '
              '(écriture refusée) ⇒ AUCUNE protection revendiquée, même si '
              'l\'appareil était protégé avant et son empreinte inchangée');
    });
  });
}
