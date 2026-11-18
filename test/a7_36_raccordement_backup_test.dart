// ═══════════════════════════════════════════════════════════════════════════
//  A7 / 3.3-C11 — RACCORDEMENT DE L'EXPORT ELO DANS `BackupService`
//
//  OBJET DU LOT
//  ────────────
//  Éprouver le parcours RÉEL `BackupService.instance.exporterDonnees()` :
//  lecture du JSON RÉELLEMENT ÉCRIT SUR DISQUE et inspection de l'objet
//  `ExportResult` rendu. Ce fichier ne teste NI `exporterPourBackupEnrichi()`
//  en isolation (c'est `a7_35`), NI le format en isolation (c'est `a7_34`).
//
//  CE QUE CE LOT PROUVE
//  ────────────────────
//  • les 4 statuts produisent les 4 comportements exigés :
//      `complet`              → groupe ELO enrichi, AUCUN avertissement ;
//      `sansRegistre`         → ratings exportés + avertissement explicite ;
//      `refuse`               → AUCUN groupe ELO écrit + avertissement ;
//      `diagnosticImpossible` → AUCUN groupe ELO écrit + avertissement ;
//  • les avertissements remontent de `_collecterDonnees()` à `ExportResult`
//    via `exporterDonnees()`, et sont REPROPAGÉS par
//    `telechargerSurTelephone()` ;
//  • un `ExportResult` construit SANS `avertissements` compile et vaut `[]` ;
//  • l'export NE MODIFIE PAS les données ELO (ni disque, ni RAM).
//
//  CE QUE CE LOT NE PROUVE **PAS**
//  ───────────────────────────────
//  • **L'aller-retour ELO n'est PAS opérationnel** : `_importerDepuisBackup()`
//    n'est pas raccordé au format enrichi. Ce fichier n'affirme rien là-dessus.
//  • **La visibilité utilisateur reste INCOMPLÈTE** : `profile_profil_tab.dart`
//    n'est pas modifié par ce lot. `_exporter()` affiche encore un « ✅ »
//    inconditionnel. Aucun test ici ne prétend le contraire.
//  • `partagerBackup()` rend un `bool`, pas un `ExportResult` : ce chemin ne
//    PEUT pas transporter les avertissements. Constaté, hors périmètre C11.
//
//  FORMULES / K-FACTORS / POIDS / SEUILS / TOP3 / CRITÈRES A–Q : non touchés.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/elo_registre_v3.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/utils/elo_empreinte.dart';

// ── Constantes de clés (écrites en dur : un renommage doit ÊTRE DÉTECTÉ) ────
const String kCleElo = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
const String kCleRegistre = 'elo_registre_v3';

// ── Littéraux du format enrichi (idem : écrits en dur, jamais importés) ─────
const String kCleFormat = '_elo_format';
const String kFormatV2 = 'elo_v2';
const String kCleRegistreBrut = '_elo_registre';
const String kCleTsBrut = '_elo_ts';

/// Empreinte de la map VIDE (`elo_empreinte.dart`).
const String kEmpreinteVide = '16ed60fcfaed47f4';

// ═══════════════════════════════════════════════════════════════════════════
//  STORE INSTRUMENTÉ
//
//  Il doit permettre trois choses que le store réel ne permet pas :
//    (a) SEMER un disque arbitraire (registre cohérent / divergent / …) ;
//    (b) faire ÉCHOUER un appel `getAll` DÉSIGNÉ, pour atteindre
//        `diagnosticImpossible` **à travers** `BackupService` ;
//    (c) CONSTATER qu'aucune écriture ELO n'a eu lieu pendant l'export.
// ═══════════════════════════════════════════════════════════════════════════
class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  /// Numéro d'appel (1-based) de `getAllWithParameters`, compté à vie.
  int getAllCount = 0;

  /// Indices d'appel `getAll` à faire ÉCHOUER (1-based).
  final Set<int> echecsGetAll = <int>{};

  /// Si vrai, TOUS les `getAll` échouent.
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
    getAllCount++;
    if (leverTousGetAll || echecsGetAll.contains(getAllCount)) {
      throw StateError('getAllWithParameters — échec PROVOQUÉ (appel $getAllCount)');
    }
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
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

  /// Copie PROFONDE des valeurs, pour comparer avant/après export.
  Map<String, Object> cliche() => Map<String, Object>.of(_valeurs);

  Set<String> clesEcritesDepuis(int index) => journal
      .skip(index)
      .where((e) => e.startsWith('SET-OK '))
      .map((e) => e.substring('SET-OK '.length))
      .toSet();

  bool aEcritDepuis(int index) =>
      journal.skip(index).any((e) => e.startsWith('SET-OK '));
}

// Type privé volontaire : le dispositif reste local à ce fichier.
// ignore: library_private_types_in_public_api
late _Store store;

/// `path_provider` factice : le répertoire temporaire ET le stockage externe
/// pointent sur un dossier réel, ce qui permet de LIRE le fichier produit.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.racine);
  final String racine;

  @override
  Future<String?> getTemporaryPath() async => racine;

  @override
  Future<String?> getExternalStoragePath() async => racine;

  @override
  Future<String?> getApplicationDocumentsPath() async => racine;
}

Directory? _tmp;

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

// ── Constructeurs de données (mêmes conventions que a7_35) ──────────────────

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

/// Registre DIVERGENT : déclare l'empreinte de la map VIDE.
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

/// Met la RAM en accord EXACT avec le disque.
///
/// ⚠️ POURQUOI PAS `EloService.init()` SEUL — MESURÉ (a7_35).
///    `EloService` est un singleton ; `_charger()` commence par
///    `if (_charge) return;` et `_charge` reste `true` à vie (y compris après
///    `executerResetComplet`, documenté V29-C). Un `init()` ultérieur ne relit
///    donc RIEN. On reproduit explicitement l'effet de `_charger()` : vidage
///    RAM puis remplissage depuis la valeur PERSISTÉE, avec le même décodage
///    tolérant. Fidèle au service, déterministe, indépendant du singleton.
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

/// Lit le fichier de sauvegarde RÉELLEMENT écrit sur disque.
Map<String, dynamic> _jsonDuDisque(ExportResult res) {
  expect(res.filePath, isNotNull, reason: 'un export réussi a un filePath');
  final File f = File(res.filePath!);
  expect(f.existsSync(), isTrue,
      reason: 'le fichier annoncé doit exister sur le disque');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _installerStore();
    // Aucun test ne doit hériter de la RAM du précédent (cf. _accorderRamAuDisque).
    EloService.instance.viderMemoirePourResetComplet();
    _tmp = Directory.systemTemp.createTempSync('a7_36_backup_');
    PathProviderPlatform.instance = _FakePathProvider(_tmp!.path);
  });

  tearDown(() {
    try {
      _tmp?.deleteSync(recursive: true);
    } catch (_) {}
    _tmp = null;
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  F1 — STATUT `complet` À TRAVERS LE VRAI PARCOURS
  // ═════════════════════════════════════════════════════════════════════════
  group('F1 — complet via BackupService.exporterDonnees()', () {
    const Map<String, double> kRatings = <String, double>{
      'C11 ALPHA|TROT_ATTELE': 1874.5,
      'C11 BRAVO|TROT_ATTELE': 1622.0,
      'C11 CHARLIE|PLAT': 1501.25,
    };

    setUp(() async {
      _semerRatings(kRatings);
      _semerRegistre(_registreCoherent(kRatings));
      store.semer(kCleTs, 1794900500000);
      await _accorderRamAuDisque();
    });

    test('F1a — succès, AUCUN avertissement, `complet` vrai', () async {
      final ExportResult res = await BackupService.instance.exporterDonnees();
      // ignore: avoid_print
      print('[F1a] succes=${res.succes} avertissements=${res.avertissements} '
          'complet=${res.complet} taille=${res.tailleOctets}');

      expect(res.succes, isTrue);
      expect(res.avertissements, isEmpty,
          reason: 'un export `complet` ne porte AUCUN avertissement');
      expect(res.complet, isTrue);
      expect(res.erreur, isNull);
    });

    test('F1b — le fichier sur disque porte le groupe ELO enrichi', () async {
      final ExportResult res = await BackupService.instance.exporterDonnees();
      final Map<String, dynamic> json = _jsonDuDisque(res);

      final Object? elo = json['elo_service'];
      expect(elo, isA<Map<String, dynamic>>(),
          reason: 'le volet ELO doit être écrit quand le statut est complet');

      final Map<String, dynamic> groupe = elo! as Map<String, dynamic>;
      // ignore: avoid_print
      print('[F1b] clefs elo=${groupe.keys.toList()..sort()}');

      expect(_clesCheval(groupe), kRatings.keys.toSet(),
          reason: 'aucun cheval perdu, aucun cheval inventé');
      expect(groupe[kCleFormat], kFormatV2);
      expect(groupe[kCleRegistreBrut], store.lire(kCleRegistre),
          reason: 'registre VERBATIM : identique à la chaîne persistée');
      expect(groupe[kCleTsBrut], 1794900500000);
      expect(groupe[kCleTsBrut], isA<int>());
      expect(groupe.containsKey('ratings'), isFalse,
          reason: 'jamais de sous-objet `ratings` (destructeur, mesuré)');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  F2 — STATUT `sansRegistre`
  // ═════════════════════════════════════════════════════════════════════════
  group('F2 — sansRegistre via BackupService.exporterDonnees()', () {
    const Map<String, double> kRatings = <String, double>{
      'C11 DELTA|PLAT': 1400.0,
    };

    setUp(() async {
      // AUCUN registre n'est semé : absence RÉELLE.
      _semerRatings(kRatings);
      store.semer(kCleTs, 1794900600000);
      await _accorderRamAuDisque();
    });

    test('F2a — succès MAIS un avertissement explicite sur le registre',
        () async {
      final ExportResult res = await BackupService.instance.exporterDonnees();
      // ignore: avoid_print
      print('[F2a] succes=${res.succes} nbAvert=${res.avertissements.length} '
          'complet=${res.complet}');
      for (final a in res.avertissements) {
        // ignore: avoid_print
        print('[F2a] avertissement : $a');
      }

      expect(res.succes, isTrue, reason: 'l\'export reste un succès');
      expect(res.avertissements, hasLength(1));
      expect(res.complet, isFalse,
          reason: 'un export partiel ne doit JAMAIS être annoncé complet');
      expect(res.erreur, isNull,
          reason: 'un avertissement n\'est PAS une erreur');

      final String msg = res.avertissements.single;
      expect(msg, contains('SANS le registre'));
      expect(msg, contains('registre absent'));
    });

    test('F2b — les ratings SONT exportés, le registre JAMAIS inventé',
        () async {
      final ExportResult res = await BackupService.instance.exporterDonnees();
      final Map<String, dynamic> json = _jsonDuDisque(res);
      final Map<String, dynamic> groupe =
          json['elo_service']! as Map<String, dynamic>;

      // ignore: avoid_print
      print('[F2b] clefs elo=${groupe.keys.toList()..sort()} | '
          'registre present=${groupe.containsKey(kCleRegistreBrut)}');

      expect(_clesCheval(groupe), kRatings.keys.toSet(),
          reason: 'les ratings doivent être présents malgré l\'avertissement');
      expect(groupe[kCleFormat], kFormatV2);
      expect(groupe.containsKey(kCleRegistreBrut), isFalse,
          reason: 'aucun registre inventé, aucun registre vierge fabriqué');
      expect(store.contient(kCleRegistre), isFalse,
          reason: 'l\'export n\'a pas non plus créé de registre sur le disque');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  F3 — STATUT `refuse` : AUCUN groupe ELO, avertissement explicite
  // ═════════════════════════════════════════════════════════════════════════
  group('F3 — refuse via BackupService.exporterDonnees()', () {
    const Map<String, double> kRatings = <String, double>{
      'C11 ECHO|TROT_ATTELE': 1550.0,
    };

    Future<void> verifierRefus(String registre, String libelle) async {
      _semerRatings(kRatings);
      _semerRegistre(registre);
      await _accorderRamAuDisque();

      final ExportResult res = await BackupService.instance.exporterDonnees();
      final Map<String, dynamic> json = _jsonDuDisque(res);

      // ignore: avoid_print
      print('[F3-$libelle] succes=${res.succes} '
          'nbAvert=${res.avertissements.length} complet=${res.complet} | '
          'elo_service present=${json.containsKey('elo_service')} | '
          'avertissement=${res.avertissements.isEmpty ? "(aucun)" : res.avertissements.single}');

      expect(res.succes, isTrue,
          reason: 'un refus ELO ne fait pas échouer le fichier ($libelle)');
      expect(res.avertissements, hasLength(1));
      expect(res.complet, isFalse);

      // ★ CŒUR DU LOT : pas de groupe ELO, et surtout PAS de groupe VIDE.
      expect(json.containsKey('elo_service'), isFalse,
          reason: 'un groupe vide masquerait le refus et écraserait les '
              'ratings à la restauration ($libelle)');

      final String msg = res.avertissements.single;
      expect(msg, contains('ELO NON SAUVEGARDÉ'));
      expect(msg, contains('ne figurent PAS'));
    }

    test('F3a — registre DIVERGENT → refus, avertissement', () async {
      await verifierRefus(_registreDivergent(), 'divergent');
    });

    test('F3b — registre CORROMPU → refus, avertissement', () async {
      await verifierRefus(kRegistreCorrompu, 'corrompu');
    });

    test('F3c — registre INCOMPATIBLE → refus, avertissement', () async {
      await verifierRefus(_registreIncompatible(), 'incompatible');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  F4 — STATUT `diagnosticImpossible` À TRAVERS `BackupService`
  //
  //  On fait échouer un appel `getAll` DÉSIGNÉ. L'appel n°1 est consommé par
  //  le `SharedPreferences.getInstance()` de `_collecterDonnees()` lui-même ;
  //  l'appel suivant par le diagnostic ELO. Le numéro exact est MESURÉ et
  //  imprimé ci-dessous : si l'ordre des lectures change un jour, ce test
  //  échouera BRUYAMMENT au lieu de passer silencieusement à côté du cas.
  //
  //  ⚠️ POURQUOI CE CAS N'EST PAS UN ÉCHEC GLOBAL — MESURÉ DANS LE CODE :
  //     `_etablirDiagnosticPreImport()` (elo_service.dart l.2792-2803) et
  //     `_lireInstantaneDisque()` (l.2665-2694) encapsulent TOUTES leurs
  //     lectures dans des `try`, et rendent un diagnostic NON ÉTABLI + motif.
  //     Une indisponibilité du store devient donc un `diagnosticImpossible`
  //     AVEC avertissement, jamais une exception. C'est le comportement exigé.
  // ═════════════════════════════════════════════════════════════════════════
  group('F4 — diagnosticImpossible via BackupService.exporterDonnees()', () {
    test('F4a — store illisible au diagnostic → avertissement, pas de groupe',
        () async {
      _semerRatings(<String, double>{'C11 FOXTROT|PLAT': 1499.0});
      store.semer(kCleRegistre, _registreCoherent(
          <String, double>{'C11 FOXTROT|PLAT': 1499.0}));
      store.semer(kCleTs, 1794900700000);
      await _accorderRamAuDisque();

      // Mesure du nombre d'appels `getAll` d'un export nominal, pour situer
      // l'appel à faire échouer.
      store.getAllCount = 0;
      final int avant = store.getAllCount;
      store.echecsGetAll.add(2); // 1 = instance de collecte, 2 = diagnostic ELO

      final ExportResult res = await BackupService.instance.exporterDonnees();
      // ignore: avoid_print
      print('[F4a] getAllCount=${store.getAllCount} (base=$avant) | '
          'succes=${res.succes} nbAvert=${res.avertissements.length} | '
          'avertissement=${res.avertissements.isEmpty ? "(aucun)" : res.avertissements.single}');

      final Map<String, dynamic> json = _jsonDuDisque(res);

      expect(res.succes, isTrue,
          reason: 'l\'indisponibilité du diagnostic ne doit pas casser le '
              'fichier : `_etablirDiagnosticPreImport` la capture');
      expect(res.avertissements, hasLength(1));
      expect(res.complet, isFalse);
      expect(json.containsKey('elo_service'), isFalse,
          reason: 'aucun groupe ELO écrit quand le diagnostic est impossible');
      expect(res.avertissements.single, contains('ELO NON SAUVEGARDÉ'));
      expect(res.avertissements.single, contains('illisible'));
    });

    test('F4b — le refus n\'est JAMAIS un silence : motif non vide', () async {
      _semerRatings(<String, double>{'C11 GOLF|PLAT': 1488.0});
      await _accorderRamAuDisque();
      store.echecsGetAll.add(2);

      final ExportResult res = await BackupService.instance.exporterDonnees();
      expect(res.avertissements.single.trim(), isNotEmpty);
      expect(res.avertissements.single, isNot(contains('motif non renseigné')),
          reason: 'le motif d\'établissement doit être REPRIS, pas perdu');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  F5 — ÉCHEC GLOBAL : une exception n'est PAS convertie en avertissement
  //
  //  Arbitrage 3 du lot : le comportement historique est conservé. On le
  //  mesure ici : store totalement illisible ⇒ `succes == false`,
  //  `erreur` renseignée, `avertissements` VIDE (aucune requalification),
  //  et AUCUN fichier produit.
  // ═════════════════════════════════════════════════════════════════════════
  group('F5 — échec global préservé', () {
    test('F5a — exception à la collecte → succes=false, aucun avertissement',
        () async {
      _semerRatings(<String, double>{'C11 HOTEL|PLAT': 1477.0});
      await _accorderRamAuDisque();
      store.leverTousGetAll = true;

      final ExportResult res = await BackupService.instance.exporterDonnees();
      // ignore: avoid_print
      print('[F5a] succes=${res.succes} erreur=${res.erreur} '
          'avertissements=${res.avertissements} complet=${res.complet} '
          'filePath=${res.filePath}');

      expect(res.succes, isFalse);
      expect(res.erreur, isNotNull);
      expect(res.avertissements, isEmpty,
          reason: 'une exception ne doit pas être requalifiée en avertissement');
      expect(res.complet, isFalse);
      expect(res.filePath, isNull, reason: 'aucun fichier ne doit être produit');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  F6 — COMPATIBILITÉ DES CONSTRUCTEURS HISTORIQUES
  //
  //  Aucun appelant existant ne doit changer une ligne : `avertissements` est
  //  optionnel, de valeur par défaut la liste vide.
  // ═════════════════════════════════════════════════════════════════════════
  group('F6 — compatibilité historique de ExportResult', () {
    test('F6a — constructeur historique : avertissements vide, complet vrai',
        () {
      final ExportResult r = ExportResult(
        succes: true,
        filePath: '/tmp/x.json',
        fileName: 'x.json',
        tailleOctets: 12,
      );
      // ignore: avoid_print
      print('[F6a] avertissements=${r.avertissements} complet=${r.complet}');

      expect(r.avertissements, isEmpty);
      expect(r.complet, isTrue);
      expect(r.succes, isTrue);
    });

    test('F6b — échec historique : complet faux même sans avertissement', () {
      final ExportResult r = ExportResult(succes: false, erreur: 'boum');
      expect(r.avertissements, isEmpty);
      expect(r.complet, isFalse);
      expect(r.erreur, 'boum');
    });

    test('F6c — succès avec avertissement : complet faux', () {
      final ExportResult r = ExportResult(
          succes: true, avertissements: const <String>['attention']);
      expect(r.succes, isTrue);
      expect(r.complet, isFalse);
    });

    test('F6d — la liste par défaut est PARTAGÉE et donc non mutable', () {
      final ExportResult a = ExportResult(succes: true);
      final ExportResult b = ExportResult(succes: true);
      expect(identical(a.avertissements, b.avertissements), isTrue);
      expect(() => a.avertissements.add('x'), throwsUnsupportedError,
          reason: 'une constante non modifiable ne peut pas être polluée');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  F7 — L'EXPORT NE MODIFIE AUCUNE DONNÉE ELO
  // ═════════════════════════════════════════════════════════════════════════
  group('F7 — export sans mutation des données ELO', () {
    const Map<String, double> kRatings = <String, double>{
      'C11 INDIA|TROT_ATTELE': 1700.0,
      'C11 JULIET|PLAT': 1310.5,
    };

    test('F7a — disque identique avant/après, aucune écriture ELO', () async {
      _semerRatings(kRatings);
      _semerRegistre(_registreCoherent(kRatings));
      store.semer(kCleTs, 1794900800000);
      await _accorderRamAuDisque();

      final Map<String, Object> avant = store.cliche();
      final int j = store.journal.length;

      final ExportResult res = await BackupService.instance.exporterDonnees();
      await _laisserProgresser();

      final Map<String, Object> apres = store.cliche();
      final Set<String> ecrites = store.clesEcritesDepuis(j);

      // ignore: avoid_print
      print('[F7a] succes=${res.succes} | cles ecrites=${ecrites.toList()} | '
          'disque identique=${jsonEncode(avant) == jsonEncode(apres)}');

      expect(res.succes, isTrue);
      expect(ecrites, isEmpty,
          reason: 'un EXPORT lit, il n\'écrit rien sur le disque');
      expect(jsonEncode(apres), jsonEncode(avant),
          reason: 'les 3 clés ELO doivent être inchangées à l\'octet près');
    });

    test('F7b — la RAM ELO est inchangée par l\'export', () async {
      _semerRatings(kRatings);
      _semerRegistre(_registreCoherent(kRatings));
      await _accorderRamAuDisque();

      final int nbAvant = EloService.instance.nbChevauxSuivis;
      final Map<String, dynamic> ramAvant =
          EloService.instance.exporterPourBackup();

      await BackupService.instance.exporterDonnees();

      final int nbApres = EloService.instance.nbChevauxSuivis;
      final Map<String, dynamic> ramApres =
          EloService.instance.exporterPourBackup();

      // ignore: avoid_print
      print('[F7b] chevaux avant=$nbAvant apres=$nbApres | '
          'RAM identique=${jsonEncode(ramAvant) == jsonEncode(ramApres)}');

      expect(nbApres, nbAvant);
      expect(jsonEncode(ramApres), jsonEncode(ramAvant),
          reason: 'aucun rating RAM ne doit bouger pendant un export');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  F8 — PROPAGATION DANS `telechargerSurTelephone()`
  //
  //  Cette méthode construit un `ExportResult` NEUF après copie du fichier :
  //  sans propagation explicite, les avertissements seraient perdus et le
  //  fichier copié serait annoncé complet.
  // ═════════════════════════════════════════════════════════════════════════
  group('F8 — propagation dans telechargerSurTelephone()', () {
    test('F8a — l\'avertissement `sansRegistre` survit à la copie', () async {
      _semerRatings(<String, double>{'C11 KILO|PLAT': 1433.0});
      await _accorderRamAuDisque();

      final ExportResult res =
          await BackupService.instance.telechargerSurTelephone();
      // ignore: avoid_print
      print('[F8a] succes=${res.succes} nbAvert=${res.avertissements.length} '
          'complet=${res.complet} path=${res.filePath}');

      expect(res.succes, isTrue);
      expect(res.avertissements, hasLength(1),
          reason: 'la copie doit REPROPAGER l\'avertissement, pas le perdre');
      expect(res.complet, isFalse,
          reason: 'le fichier copié ne doit pas être annoncé complet');
      expect(File(res.filePath!).existsSync(), isTrue,
          reason: 'la copie doit avoir eu lieu');
    });

    test('F8b — un export complet reste complet après copie (contrôle +)',
        () async {
      _semerRatings(<String, double>{'C11 LIMA|PLAT': 1444.0});
      _semerRegistre(_registreCoherent(<String, double>{'C11 LIMA|PLAT': 1444.0}));
      await _accorderRamAuDisque();

      final ExportResult res =
          await BackupService.instance.telechargerSurTelephone();
      expect(res.succes, isTrue);
      expect(res.avertissements, isEmpty);
      expect(res.complet, isTrue);
    });
  });
}
