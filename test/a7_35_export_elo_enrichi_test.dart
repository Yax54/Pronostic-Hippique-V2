// ═══════════════════════════════════════════════════════════════════════════
//  A7 / 3.3-C9 — `EloService.exporterPourBackupEnrichi()` : LES 4 STATUTS
//
//  OBJET DU LOT
//  ────────────
//  Éprouver la méthode ADDITIVE d'export enrichi, sans jamais toucher au
//  contrat historique de `exporterPourBackup()`. Les deux méthodes coexistent
//  volontairement : 12 assertions de test lisent `exporterPourBackup().length`
//  comme un NOMBRE DE CHEVAUX (v18_b5 l.160/188/216/263/272, v5
//  l.441/465/1036/1578, a7_ambiguite l.245/311/602), et deux mesurent
//  `isEmpty`. Toute métadonnée ajoutée en place les casserait.
//
//  CE QUE CE LOT NE FAIT **PAS** — À LIRE AVANT TOUTE INTERPRÉTATION
//  ─────────────────────────────────────────────────────────────────
//  • il ne modifie NI `backup_service.dart`, NI `elo_registre_v3.dart`,
//    NI `elo_empreinte.dart`, NI `_importerDepuisBackup()`,
//    NI `_ecrireTemoinImport()` ;
//  • il ne RACCORDE PAS `exporterPourBackupEnrichi()` à `BackupService` :
//    l'export réel de l'application reste, à ce stade, produit par
//    `exporterPourBackup()`. Aucun changement de comportement observable ;
//  • il n'ajoute AUCUNE clé SharedPreferences : le format enrichi vit DANS la
//    valeur de `elo_ratings_v2`, pas dans de nouvelles clés ;
//  • il ne touche NI les formules ELO, NI les coefficients K, NI les
//    mécanismes d'apprentissage, NI les critères A–Q ;
//  • il n'invente aucun registre, aucune empreinte, aucun historique.
//
//  LES 4 STATUTS ET CE QU'ILS ENGAGENT
//  ───────────────────────────────────
//  • `complet`              → registre présent, interprétable, cohérent.
//                             Groupe = ratings + `_elo_format` +
//                             `_elo_registre` VERBATIM + `_elo_ts` si dispo.
//  • `sansRegistre`         → absence RÉELLE, diagnostic établi.
//                             Groupe = ratings + `_elo_format` (+ `_elo_ts`),
//                             JAMAIS `_elo_registre`.
//  • `refuse`               → corrompu / incompatible / divergent.
//                             Groupe VIDE. Motif explicite.
//  • `diagnosticImpossible` → on n'a pas pu regarder. Groupe VIDE, et PAS
//                             D'HORODATAGE ISOLÉ.
//
//  LA QUESTION DE COHÉRENCE RAM / DISQUE
//  ─────────────────────────────────────
//  Le diagnostic décrit le DISQUE ; `exporterPourBackup()` sérialise la RAM.
//  Les assembler aveuglément produirait un groupe dont l'empreinte déclarée ne
//  décrit pas les ratings exportés. La source retenue est donc le DISQUE, et
//  toute divergence RAM/disque REFUSE l'export (tests `E5`).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/elo_registre_v3.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/utils/elo_empreinte.dart';

// ───────────────────────────────────────────────────────────────────────────
//  STORE INSTRUMENTÉ
//
//  Minimal : ce lot ne teste ni file d'attente, ni reset, ni suspension
//  d'écriture. Il lui faut seulement (a) semer un disque arbitraire,
//  (b) provoquer des échecs de LECTURE ciblés pour atteindre
//  `diagnosticImpossible`, (c) constater qu'AUCUNE écriture n'a lieu.
// ───────────────────────────────────────────────────────────────────────────

class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  /// Si vrai, le PROCHAIN `getAllWithParameters` lève (une seule fois).
  bool leverProchainGetAll = false;

  /// Si vrai, TOUS les `getAllWithParameters` lèvent.
  bool leverTousGetAll = false;

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
    if (leverProchainGetAll) {
      leverProchainGetAll = false;
      throw StateError('getAllWithParameters — échec PROVOQUÉ (une fois)');
    }
    if (leverTousGetAll) {
      throw StateError('getAllWithParameters — échec PROVOQUÉ (permanent)');
    }
    return Map<String, Object>.from(_valeurs);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _valeurs[key] = value;
    journal.add('SET-OK $key');
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    _valeurs.remove(key);
    return true;
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];

  Set<String> clesEcritesDepuis(int index) => journal
      .skip(index)
      .where((e) => e.startsWith('SET-OK '))
      .map((e) => e.substring('SET-OK '.length))
      .toSet();

  bool aEcritDepuis(int index) =>
      journal.skip(index).any((e) => e.startsWith('SET-OK '));
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
Future<void> _laisserProgresser([int tours = 16]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ── Constantes ──────────────────────────────────────────────────────────────

const String kCleElo = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
const String kCleRegistre = 'elo_registre_v3';

// Littéraux du format enrichi. Volontairement ÉCRITS EN DUR et non importés :
// un renommage de constante dans le service doit être DÉTECTÉ par ces tests,
// pas suivi silencieusement.
const String kCleFormat = '_elo_format';
const String kFormatV2 = 'elo_v2';
const String kCleRegistreBrut = '_elo_registre';
const String kCleTsBrut = '_elo_ts';

/// Empreinte de la map VIDE — documentée dans `elo_empreinte.dart`.
const String kEmpreinteVide = '16ed60fcfaed47f4';

// ── Constructeurs de données ────────────────────────────────────────────────

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

/// Registre LISIBLE et COHÉRENT avec [ratings], construit par le MODÈLE.
String _registreCoherent(Map<String, double> ratings) {
  final empreinte = _empreinteDe(ratings);
  return RegistreEloV3.vierge(empreinteRatings: empreinte).copyWith(
    empreinteRatings: empreinte,
    origine: OrigineRegistreElo.courante,
    entrees: const <EntreeRegistreElo>[],
  ).encoder();
}

/// Registre DIVERGENT : déclare l'empreinte d'une map VIDE, impossible à
/// confondre avec l'empreinte de ratings non vides. Divergence CONSTRUITE.
String _registreDivergent() =>
    RegistreEloV3.vierge(empreinteRatings: kEmpreinteVide).encoder();

/// Registre CORROMPU : JSON valide, champs obligatoires absents.
const String kRegistreCorrompu =
    '{"version":3,"operations":{"R1C1_20260417":{"etat":"temoin"}}}';

/// Registre INCOMPATIBLE : structure complète, `schema` étranger.
String _registreIncompatible() => jsonEncode(<String, dynamic>{
      'schema': 99,
      'version': 1,
      'horloge': 3,
      'empreinteRatings': kEmpreinteVide,
      'origine': 'courante',
      'entrees': <dynamic>[],
    });

/// Met la RAM en accord EXACT avec le disque : indispensable, car l'export
/// enrichi REFUSE un export si la RAM diverge du disque.
///
/// ⚠️ POURQUOI PAS `EloService.init()` SEUL — MESURÉ.
///    `EloService` est un singleton et `_charger()` commence par
///    `if (_charge) return;`. `_charge` vaut `true` dès le premier test et
///    n'est JAMAIS remis à `false` (`executerResetComplet` le laisse à `true`,
///    c'est documenté et voulu). Un `init()` dans un test suivant ne relit donc
///    RIEN : la RAM du test précédent restait en place, ce qui a produit un
///    premier jet de ce fichier où E2 lisait « RAM 3 ratings, disque 2 » —
///    l'empreinte de E1.
///
///    On reproduit donc explicitement ce que `_charger()` produit : on vide la
///    RAM, puis on la remplit depuis la valeur PERSISTÉE, avec le MÊME décodage
///    tolérant (`EloScore.fromJson` dans un `try/catch` par entrée). C'est
///    fidèle au service, déterministe, et indépendant de l'état du singleton.
Future<void> _accorderRamAuDisque() async {
  EloService.instance.viderMemoirePourResetComplet();
  final Object? brut = store.lire(kCleElo);
  if (brut is String && brut.isNotEmpty) {
    EloService.instance
        .chargerDepuisMapIsolate(jsonDecode(brut) as Map<String, dynamic>);
  }
  await _laisserProgresser();
}

/// Clés cheval d'un groupe exporté : tout sauf les marqueurs `_elo_`.
Set<String> _clesCheval(Map<String, dynamic> groupe) =>
    groupe.keys.where((k) => !k.startsWith('_elo_')).toSet();

void main() {
  // `EloService` est un singleton : `_charge` reste `true` d'un test à
  // l'autre. On réinstalle donc le store ET on force un rechargement réel
  // via `SharedPreferences.resetStatic()` + `EloService.init()`, comme le
  // fait déjà a7_33b2d2. Le vidage RAM explicite est indispensable quand un
  // test précédent a laissé des ratings en mémoire.
  setUp(() {
    _installerStore();
    // Aucun test ne doit hériter de la RAM du précédent : voir la note de
    // `_accorderRamAuDisque` sur `_charge` qui reste `true` à vie.
    EloService.instance.viderMemoirePourResetComplet();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E1 — STATUT `complet`
  //
  //  Registre PRÉSENT, interprétable, cohérent. Le groupe doit porter
  //  `_elo_format`, `_elo_registre` (VERBATIM) et `_elo_ts`, EN PLUS des clés
  //  historiques des chevaux — et AUCUN sous-objet `ratings`.
  // ═════════════════════════════════════════════════════════════════════════

  group('E1 — statut complet', () {
    const Map<String, double> kRatings = <String, double>{
      'ALPHA|TROT_ATTELE': 1912.5,
      'BRAVO|TROT_ATTELE': 1687.25,
      'CHARLIE|PLAT': 1544.75,
    };

    setUp(() async {
      _semerRatings(kRatings);
      _semerRegistre(_registreCoherent(kRatings));
      store.semer(kCleTs, 1794900000000);
      await _accorderRamAuDisque();
    });

    test('E1a — statut complet, aucun motif, exportable', () async {
      final r = await EloService.instance.exporterPourBackupEnrichi();
      // ignore: avoid_print
      print('[E1a] statut=${r.statut.name} motif=${r.motif} '
          'exportable=${r.exportable} clefs=${r.groupe.length}');

      expect(r.statut, StatutExportElo.complet);
      expect(r.motif, isNull,
          reason: 'un export autorisé ne porte pas de motif');
      expect(r.exportable, isTrue);
    });

    test('E1b — les ratings sont les clés HISTORIQUES, à plat', () async {
      final r = await EloService.instance.exporterPourBackupEnrichi();
      final cles = _clesCheval(r.groupe);
      // ignore: avoid_print
      print('[E1b] cles cheval=${cles.toList()..sort()}');

      expect(cles, kRatings.keys.toSet(),
          reason: 'aucune clé cheval ne doit être perdue ni inventée');

      // Chaque valeur est EXACTEMENT un EloScore.toJson() : 4 champs.
      for (final cle in cles) {
        final v = r.groupe[cle] as Map<String, dynamic>;
        expect(valueToJsonClefs(v), <String>{'nom', 'rating', 'nb', 'var'},
            reason: 'la forme d\'un rating exporté reste `EloScore.toJson()`');
      }
    });

    test('E1c — registre VERBATIM : identique à l\'octet près', () async {
      final r = await EloService.instance.exporterPourBackupEnrichi();
      final String surDisque = store.lire(kCleRegistre)! as String;
      final String exporte = r.groupe[kCleRegistreBrut] as String;

      expect(exporte, surDisque,
          reason: 'le registre est COPIÉ, jamais réencodé');
      expect(r.registreExporte, isTrue);
    });

    test(
        'E1c-bis — le registre exporté DÉCLARE l\'empreinte des ratings '
        'exportés (cohérence non circulaire)', () async {
      final r = await EloService.instance.exporterPourBackupEnrichi();

      // Reconstruction des EloScore depuis le GROUPE exporté, puis empreinte.
      final Map<String, EloScore> relus = <String, EloScore>{};
      _clesCheval(r.groupe).forEach((k) {
        relus[k] = EloScore.fromJson(r.groupe[k] as Map<String, dynamic>);
      });
      final empreinteExportee = empreinte64Ratings(relus);
      final registre =
          RegistreEloV3.decoder(r.groupe[kCleRegistreBrut] as String);

      // ignore: avoid_print
      print('[E1c-bis] empreinte exportee=$empreinteExportee '
          'empreinte registre=${registre.empreinteRatings}');

      expect(registre.empreinteRatings, empreinteExportee,
          reason: 'l\'empreinte déclarée doit décrire EXACTEMENT les ratings '
              'du groupe — sinon le groupe est incohérent');
    });

    test('E1d — horodatage présent et de type INT', () async {
      final r = await EloService.instance.exporterPourBackupEnrichi();
      expect(r.groupe[kCleTsBrut], 1794900000000);
      expect(r.groupe[kCleTsBrut], isA<int>());
    });

    test('E1e — marqueur de format présent et exact', () async {
      final r = await EloService.instance.exporterPourBackupEnrichi();
      expect(r.groupe[kCleFormat], kFormatV2);
    });

    test('E1f — AUCUN sous-objet `ratings`, et aucun cheval fantôme', () async {
      final r = await EloService.instance.exporterPourBackupEnrichi();
      // ignore: avoid_print
      print('[E1f] clefs=${(r.groupe.keys.toList()..sort())}');

      expect(r.groupe.containsKey('ratings'), isFalse,
          reason:
              'formellement interdit : mesuré destructeur au tour précédent');
      expect(_clesCheval(r.groupe).length, kRatings.length,
          reason: 'exactement 3 chevaux, ni 2 ni 5');
    });

    test('E1g — l\'export N\'ÉCRIT RIEN sur le disque', () async {
      final int avant = store.journal.length;
      await EloService.instance.exporterPourBackupEnrichi();
      await _laisserProgresser();

      expect(store.aEcritDepuis(avant), isFalse,
          reason: 'l\'export est en LECTURE SEULE');
      expect(store.aSupprimeDepuis(avant), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E2 — STATUT `sansRegistre`
  //
  //  Absence RÉELLE du registre, diagnostic ÉTABLI. On exporte les ratings
  //  sans registre — on n'en invente aucun, pas même un vierge.
  // ═════════════════════════════════════════════════════════════════════════

  group('E2 — statut sansRegistre', () {
    const Map<String, double> kRatings = <String, double>{
      'DELTA|TROT_ATTELE': 1777.0,
      'ECHO|TROT_ATTELE': 1666.5,
    };

    setUp(() async {
      _semerRatings(kRatings);
      // AUCUN registre semé : absence réelle, et NON un registre vide.
      store.semer(kCleTs, 1794900001000);
      await _accorderRamAuDisque();
    });

    test('E2a — statut sansRegistre, exportable, sans motif', () async {
      final r = await EloService.instance.exporterPourBackupEnrichi();
      // ignore: avoid_print
      print('[E2a] statut=${r.statut.name} motif=${r.motif} '
          'registreExporte=${r.registreExporte}');

      expect(r.statut, StatutExportElo.sansRegistre);
      expect(r.exportable, isTrue);
      expect(r.motif, isNull);
    });

    test('E2b — `_elo_registre` ABSENT : aucun registre inventé', () async {
      final r = await EloService.instance.exporterPourBackupEnrichi();
      expect(r.groupe.containsKey(kCleRegistreBrut), isFalse,
          reason: 'absence honnête : ni vierge, ni reconstruit, ni réparé');
      expect(r.registreExporte, isFalse);
    });

    test('E2c — les ratings et le format sont bien présents', () async {
      final r = await EloService.instance.exporterPourBackupEnrichi();
      expect(_clesCheval(r.groupe), kRatings.keys.toSet());
      expect(r.groupe[kCleFormat], kFormatV2);
    });

    test('E2d — horodatage présent car disponible', () async {
      final r = await EloService.instance.exporterPourBackupEnrichi();
      expect(r.groupe[kCleTsBrut], 1794900001000);
    });

    test(
        'E2e — horodatage ABSENT du disque : `_elo_ts` omis, export '
        'toujours autorisé', () async {
      final int avant = store.journal.length;
      expect(store.aEcritDepuis(avant), isFalse);
      // Aucun ts n'a été semé pour ce test : on retire celui du setUp.
      await SharedPreferences.getInstance();
      store.remove('flutter.$kCleTs');

      final r = await EloService.instance.exporterPourBackupEnrichi();
      // ignore: avoid_print
      print('[E2e] statut=${r.statut.name} ts=${r.groupe[kCleTsBrut]}');

      expect(r.statut, StatutExportElo.sansRegistre,
          reason: '`_elo_ts` est OPTIONNEL : son absence ne bloque rien');
      expect(r.groupe.containsKey(kCleTsBrut), isFalse,
          reason: 'on n\'écrit pas 0 à la place d\'une absence');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E3 — STATUT `refuse`
  //
  //  Trois causes distinctes, un seul statut, et dans les trois cas : AUCUN
  //  groupe exportable. Le motif doit dire LAQUELLE.
  // ═════════════════════════════════════════════════════════════════════════

  group('E3 — statut refuse', () {
    const Map<String, double> kRatings = <String, double>{
      'FOXTROT|PLAT': 1600.0,
    };

    Future<ResultatExportElo> executerAvecRegistre(String registre) async {
      _installerStore();
      EloService.instance.viderMemoirePourResetComplet();
      _semerRatings(kRatings);
      _semerRegistre(registre);
      store.semer(kCleTs, 1794900002000);
      await _accorderRamAuDisque();
      return EloService.instance.exporterPourBackupEnrichi();
    }

    test('E3a — registre DIVERGENT → refuse, groupe vide, motif explicite',
        () async {
      final r = await executerAvecRegistre(_registreDivergent());
      // ignore: avoid_print
      print('[E3a] statut=${r.statut.name} motif=${r.motif}');

      expect(r.statut, StatutExportElo.refuse);
      expect(r.exportable, isFalse);
      expect(r.groupe, isEmpty, reason: 'aucun groupe exportable');
      expect(r.motif, isNotNull);
      expect(r.motif, contains('divergent'));
    });

    test('E3b — registre CORROMPU → refuse, groupe vide', () async {
      final r = await executerAvecRegistre(kRegistreCorrompu);
      // ignore: avoid_print
      print('[E3b] statut=${r.statut.name} motif=${r.motif}');

      expect(r.statut, StatutExportElo.refuse);
      expect(r.groupe, isEmpty);
      expect(r.motif, contains('corrompu'));
    });

    test('E3c — registre INCOMPATIBLE → refuse, groupe vide', () async {
      final r = await executerAvecRegistre(_registreIncompatible());
      // ignore: avoid_print
      print('[E3c] statut=${r.statut.name} motif=${r.motif}');

      expect(r.statut, StatutExportElo.refuse);
      expect(r.groupe, isEmpty);
      expect(r.motif, contains('schemaIncompatible'));
    });

    test('E3d — un refus N\'ÉCRIT RIEN et ne répare RIEN sur le disque',
        () async {
      _installerStore();
      EloService.instance.viderMemoirePourResetComplet();
      _semerRatings(kRatings);
      final String registreDivergent = _registreDivergent();
      _semerRegistre(registreDivergent);
      await _accorderRamAuDisque();

      final int avant = store.journal.length;
      await EloService.instance.exporterPourBackupEnrichi();
      await _laisserProgresser();

      expect(store.aEcritDepuis(avant), isFalse,
          reason: 'aucune réparation automatique : le refus est un constat');
      expect(store.aSupprimeDepuis(avant), isFalse);
      expect(store.lire(kCleRegistre), registreDivergent,
          reason: 'le registre divergent est LAISSÉ INTACT');
    });

    test(
        'E3e — le refus n\'est JAMAIS converti en sauvegarde apparemment '
        'complète', () async {
      final r = await executerAvecRegistre(_registreDivergent());
      // Le piège à éviter : un groupe qui contiendrait les ratings mais pas le
      // registre, et un statut qui prétendrait que tout va bien.
      expect(r.groupe, isEmpty,
          reason: 'même les ratings sont retenus : partiels = trompeurs');
      expect(r.registreExporte, isFalse);
      expect(r.statut, isNot(StatutExportElo.complet));
      expect(r.statut, isNot(StatutExportElo.sansRegistre));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E4 — STATUT `diagnosticImpossible`
  //
  //  On n'a pas pu regarder. Groupe vide ET aucun horodatage isolé : exporter
  //  un horodatage seul laisserait croire à une lecture réussie.
  // ═════════════════════════════════════════════════════════════════════════

  group('E4 — statut diagnosticImpossible', () {
    test('E4a — lecture du store impossible → diagnosticImpossible', () async {
      _installerStore();
      _semerRatings(<String, double>{'GOLF|PLAT': 1500.0});
      store.semer(kCleRegistre,
          _registreCoherent(<String, double>{'GOLF|PLAT': 1500.0}));
      store.semer(kCleTs, 1794900003000);

      // Le diagnostic échoue dès `getInstance`/`reload` : on arme l'échec
      // AVANT tout rechargement du cache.
      store.leverTousGetAll = true;

      final r = await EloService.instance.exporterPourBackupEnrichi();
      // ignore: avoid_print
      print('[E4a] statut=${r.statut.name} motif=${r.motif}');

      expect(r.statut, StatutExportElo.diagnosticImpossible);
      expect(r.exportable, isFalse);
      expect(r.groupe, isEmpty);
      expect(r.motif, isNotNull);
    });

    test('E4b — aucun horodatage ISOLÉ dans le groupe', () async {
      _installerStore();
      _semerRatings(<String, double>{'HOTEL|PLAT': 1500.0});
      store.semer(kCleTs, 1794900003000);
      store.leverTousGetAll = true;

      final r = await EloService.instance.exporterPourBackupEnrichi();
      expect(r.groupe.containsKey(kCleTsBrut), isFalse,
          reason: 'un horodatage seul ferait croire à une lecture réussie');
      expect(r.groupe, isEmpty);
    });

    test('E4b-bis — le motif d\'établissement est REPRIS tel quel', () async {
      _installerStore();
      store.leverTousGetAll = true;
      final r = await EloService.instance.exporterPourBackupEnrichi();
      // ignore: avoid_print
      print('[E4b-bis] motif=${r.motif}');

      expect(r.motif, isNotNull);
      expect(r.motif!.isNotEmpty, isTrue,
          reason: 'un refus muet serait un silence, pas un diagnostic');
    });

    test('E4c — un diagnostic impossible N\'ÉCRIT RIEN', () async {
      _installerStore();
      _semerRatings(<String, double>{'INDIA|PLAT': 1500.0});
      await _accorderRamAuDisque();
      store.leverTousGetAll = true;

      final int avant = store.journal.length;
      await EloService.instance.exporterPourBackupEnrichi();
      await _laisserProgresser();

      expect(store.aEcritDepuis(avant), isFalse);
      expect(store.aSupprimeDepuis(avant), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E5 — COHÉRENCE RAM / DISQUE
  //
  //  Le point le plus délicat du lot. Le diagnostic décrit le DISQUE, l'export
  //  historique sérialise la RAM. L'export enrichi refuse d'assembler deux
  //  états divergents.
  // ═════════════════════════════════════════════════════════════════════════

  group('E5 — cohérence RAM/disque', () {
    test('E5a — RAM vide alors que le disque porte des ratings → refus',
        () async {
      _installerStore();
      const Map<String, double> kDisque = <String, double>{
        'JULIET|TROT_ATTELE': 1711.0,
        'KILO|TROT_ATTELE': 1622.0,
      };
      _semerRatings(kDisque);
      _semerRegistre(_registreCoherent(kDisque));

      // RAM NON chargée : `_charge` est déjà `true` (singleton), donc on ne
      // rappelle PAS `init()`. On force l'état « RAM vide, disque non vide ».
      EloService.instance.viderMemoirePourResetComplet();

      final r = await EloService.instance.exporterPourBackupEnrichi();
      // ignore: avoid_print
      print('[E5a] statut=${r.statut.name} motif=${r.motif}');

      expect(r.statut, StatutExportElo.refuse,
          reason: 'aucune source unique décrivable : le disque et la RAM ne '
              'disent pas la même chose');
      expect(r.groupe, isEmpty);
      expect(r.motif, contains('RAM'));
    });

    test('E5b — RAM en retard sur le disque → refus, jamais un mélange',
        () async {
      _installerStore();
      const Map<String, double> kDisque = <String, double>{
        'LIMA|PLAT': 1800.0,
        'MIKE|PLAT': 1650.0,
      };
      _semerRatings(kDisque);
      _semerRegistre(_registreCoherent(kDisque));

      // Le service n'a jamais vu ces ratings : sa RAM est vide, son disque
      // complet. On MESURE que le refus ne dépend pas d'un rechargement.
      EloService.instance.viderMemoirePourResetComplet();

      final r = await EloService.instance.exporterPourBackupEnrichi();
      expect(r.groupe, isEmpty,
          reason: 'on n\'assemble pas 0 rating RAM avec 2 ratings disque');
    });

    test('E5c — RAM accordée au disque → export AUTORISÉ (contrôle positif)',
        () async {
      _installerStore();
      const Map<String, double> kDisque = <String, double>{
        'NOVEMBER|PLAT': 1560.0,
      };
      _semerRatings(kDisque);
      _semerRegistre(_registreCoherent(kDisque));
      await _accorderRamAuDisque();

      final r = await EloService.instance.exporterPourBackupEnrichi();
      // ignore: avoid_print
      print('[E5c] statut=${r.statut.name} exportable=${r.exportable}');

      expect(r.exportable, isTrue,
          reason: 'contrôle positif : sans lui, E5a/E5b ne prouveraient rien');
      expect(r.statut, StatutExportElo.complet);
    });

    test('E5d — la source du groupe est le DISQUE, pas la RAM', () async {
      _installerStore();
      const Map<String, double> kDisque = <String, double>{
        'OSCAR|PLAT': 1777.5,
      };
      _semerRatings(kDisque);
      _semerRegistre(_registreCoherent(kDisque));
      await _accorderRamAuDisque();

      final r = await EloService.instance.exporterPourBackupEnrichi();

      // Les ratings exportés doivent être EXACTEMENT ceux dont l'empreinte a
      // servi au diagnostic — donc ceux du disque.
      final Map<String, EloScore> relus = <String, EloScore>{};
      _clesCheval(r.groupe).forEach((k) {
        relus[k] = EloScore.fromJson(r.groupe[k] as Map<String, dynamic>);
      });
      expect(empreinte64Ratings(relus), _empreinteDe(kDisque),
          reason: 'l\'empreinte des ratings exportés est celle du diagnostic');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E6 — NON-RÉGRESSION DU CONTRAT HISTORIQUE
  //
  //  `exporterPourBackup()` doit rester STRICTEMENT inchangée. Ces assertions
  //  doublent volontairement celles de v18_b5 / v5 / a7_ambiguite : elles
  //  échoueraient si l'enrichissement avait été fait EN PLACE.
  // ═════════════════════════════════════════════════════════════════════════

  group('E6 — non-régression du contrat historique', () {
    test('E6a — exporterPourBackup() ne contient AUCUN marqueur `_elo_`',
        () async {
      _installerStore();
      const Map<String, double> kRatings = <String, double>{
        'PAPA|PLAT': 1500.0,
        'QUEBEC|PLAT': 1600.0,
        'ROMEO|PLAT': 1700.0,
      };
      _semerRatings(kRatings);
      _semerRegistre(_registreCoherent(kRatings));
      store.semer(kCleTs, 1794900000000);
      await _accorderRamAuDisque();

      final historique = EloService.instance.exporterPourBackup();
      // ignore: avoid_print
      print('[E6a] exporterPourBackup().length=${historique.length} '
          'clefs=${historique.keys.toList()..sort()}');

      expect(historique.length, 3,
          reason: 'CONTRAT HISTORIQUE : 3 chevaux, pas 6');
      expect(historique.keys.any((k) => k.startsWith('_elo_')), isFalse,
          reason: 'aucune métadonnée dans le contrat historique');
    });

    test('E6b — exporterPourBackup() reste SYNCHRONE et vide sans ratings',
        () async {
      _installerStore();
      await _accorderRamAuDisque();
      EloService.instance.viderMemoirePourResetComplet();

      // Appel NON awaité et affecté directement : prouve le type de retour
      // `Map<String, dynamic>` et la synchronité.
      final Map<String, dynamic> vide =
          EloService.instance.exporterPourBackup();
      expect(vide, isEmpty,
          reason: 'assertion historique v5 l.441 / a7_ambiguite l.245');
    });

    test('E6c — les deux méthodes peuvent coexister sans se contaminer',
        () async {
      _installerStore();
      const Map<String, double> kRatings = <String, double>{
        'SIERRA|PLAT': 1616.0,
      };
      _semerRatings(kRatings);
      _semerRegistre(_registreCoherent(kRatings));
      await _accorderRamAuDisque();

      final enrichi = await EloService.instance.exporterPourBackupEnrichi();
      final historique = EloService.instance.exporterPourBackup();

      expect(enrichi.groupe.length, greaterThan(historique.length),
          reason: 'l\'enrichi porte les marqueurs en plus');
      expect(enrichi.groupe[kCleFormat], kFormatV2);
      expect(historique.containsKey(kCleFormat), isFalse,
          reason: 'l\'enrichi ne CONTAMINE pas l\'historique');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E7 — COMPATIBILITÉ AVEC L'IMPORTEUR HISTORIQUE
  //
  //  Le format enrichi doit rester lisible par le lecteur EXISTANT, qui ignore
  //  les métadonnées. On vérifie ici que les clés cheval survivent et que
  //  l'horodatage scalaire est bien écarté sans erreur.
  // ═════════════════════════════════════════════════════════════════════════

  group('E6/E7 — compatibilité avec le lecteur historique', () {
    test(
        'E7a — les clés cheval du groupe survivent à un rechargement par '
        '`chargerDepuisMapIsolate` (chemin data_refresh)', () async {
      _installerStore();
      const Map<String, double> kRatings = <String, double>{
        'TANGO|TROT_ATTELE': 1590.0,
        'UNIFORM|TROT_ATTELE': 1580.0,
      };
      _semerRatings(kRatings);
      _semerRegistre(_registreCoherent(kRatings));
      store.semer(kCleTs, 1794900000000);
      await _accorderRamAuDisque();

      final r = await EloService.instance.exporterPourBackupEnrichi();
      EloService.instance.viderMemoirePourResetComplet();
      EloService.instance.chargerDepuisMapIsolate(r.groupe);
      await _laisserProgresser();

      // ignore: avoid_print
      print('[E7a] ratings relus=${EloService.instance.nbChevauxSuivis}');

      expect(EloService.instance.nbChevauxSuivis, kRatings.length,
          reason: 'aucun cheval fantôme : les scalaires sont écartés par le '
              '`as Map` avant le cast');
    });
  });
}

/// Utilité locale : les clés d'un `EloScore.toJson()`.
Set<String> valueToJsonClefs(Map<String, dynamic> json) => json.keys.toSet();
