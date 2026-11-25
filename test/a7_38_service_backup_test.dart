// ═══════════════════════════════════════════════════════════════════════════
//  A7 / 3.3-C12 — LE SERVICE, MESURÉ SÉPARÉMENT
//
//  OBJET
//  ─────
//  Éprouver le parcours RÉEL de `BackupService.instance`, hors de toute zone
//  de test widget. Ce fichier ne monte AUCUN widget : c'est le pendant exact
//  de `a7_37_visibilite_avertissements_test.dart`, qui ne teste que la
//  décision d'AFFICHAGE avec des opérations simulées.
//
//  ⚠️ POURQUOI CETTE SÉPARATION EST MESURÉE, PAS ARBITRAIRE
//    Dans `testWidgets`, un `await` sur une E/S réelle ne reprend jamais :
//        [S6a] TERMINE en 94 ms                       (ici, en `test()`)
//        [S6b] enCharge revenu a false au pump #-1    (dans le widget)
//    Les deux fichiers couvrent donc deux choses différentes.
//
//  CE QUE CE LOT PROUVE
//  ────────────────────
//  • COLLECTE UNIQUE : `partagerBackupAvecResultat()` ne lit le store qu'UNE
//    fois (compteur `getAllWithParameters` instrumenté) ;
//  • le fichier annoncé EXISTE, n'est pas vide, et son contenu est du JSON ;
//  • les avertissements du service remontent dans `ExportResult` ;
//  • les TROIS états de `partageOuvert` : `null` (téléchargement),
//    `true` (menu sollicité sans exception), `false` (ouverture en échec,
//    fichier conservé) ;
//  • `partagerBackup()` et `sauvegarderSurDrive()` gardent leur contrat `bool`.
//
//  CE QUE CE LOT NE PROUVE PAS
//  ───────────────────────────
//  • Qu'un partage a été REÇU : `SharePlus.share` ne prouve aucune réception.
//    `partageOuvert == true` prouve que le menu a été SOLLICITÉ sans lever.
//  • L'aller-retour ELO : l'import enrichi n'est pas raccordé (hors périmètre).
//
//  FORMULES / K-FACTORS / POIDS / SEUILS / TOP3 / CRITÈRES A–Q : non touchés.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/elo_registre_v3.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/utils/elo_empreinte.dart';

// ── Clés écrites en dur : un renommage doit faire ÉCHOUER ces tests ─────────
const String kCleElo = 'elo_ratings_v2';
const String kCleRegistre = 'elo_registre_v3';

// ═══════════════════════════════════════════════════════════════════════════
//  STORE INSTRUMENTÉ
// ═══════════════════════════════════════════════════════════════════════════
class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};

  /// Nombre d'appels à `getAllWithParameters` — c'est la MESURE de la collecte.
  int getAllCount = 0;

  @override
  Future<bool> clear() async {
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
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _valeurs[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _valeurs.remove(key);
    return true;
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  Object? lire(String cle) => _valeurs['flutter.$cle'];
}

// Type volontairement privé : la mesure reste interne à ce fichier.
// ignore: library_private_types_in_public_api
late _Store store;

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

// ═══════════════════════════════════════════════════════════════════════════
//  PARTAGE NATIF SIMULÉ
//
//  `SharePlatform` (instance de base) délègue à `_instance` : poser une
//  sous-classe comme `_instance` suffit à intercepter l'appel de production.
// ═══════════════════════════════════════════════════════════════════════════
class _ShareEspion extends SharePlatform {
  int appels = 0;
  final List<String> fichiers = <String>[];

  /// Si non nul, l'appel LÈVE ce message (menu natif indisponible).
  String? erreur;

  void reinitialiser() {
    appels = 0;
    fichiers.clear();
    erreur = null;
  }

  @override
  Future<ShareResult> share(ShareParams params) async {
    appels++;
    final files = params.files;
    if (files != null) {
      for (final f in files) {
        fichiers.add(f.path);
      }
    }
    if (erreur != null) throw StateError(erreur!);
    return ShareResult('simule', ShareResultStatus.success);
  }
}

// ⚠️ UN SEUL espion pour tout le fichier — MESURÉ, PAS UN CHOIX ESTHÉTIQUE.
//   `SharePlus.instance` est un `static final` construit depuis
//   `SharePlatform.instance` AU PREMIER ACCÈS. Créer un espion neuf par test
//   laissait donc l'ancien capturé : mesuré, les tests H4b/H4c/H5b voyaient
//   `share.appels = 0` alors que le menu ÉTAIT sollicité (sur l'espion périmé).
// Type privé volontaire : le dispositif reste local à ce fichier.
// ignore: library_private_types_in_public_api
final _ShareEspion share = _ShareEspion();
Directory? _tmp;

void _installerStore() {
  store = _Store();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
  // `EloService._charge` reste vrai après un premier chargement : on force
  // une relecture disque pour que chaque test parte d'un état connu.
  EloService.instance.viderMemoirePourResetComplet();
  SharedPreferences.resetStatic();
}

Future<void> _laisserProgresser([int tours = 16]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, EloScore> _mapElo(Map<String, double> ratings) {
  final map = <String, EloScore>{};
  ratings.forEach((cle, rating) {
    map[cle] = EloScore(
      nomCheval: cle.contains('|') ? cle.split('|').first : cle,
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

String _registreCoherent(Map<String, double> ratings) {
  final empreinte = empreinte64Ratings(_mapElo(ratings));
  return RegistreEloV3.vierge(empreinteRatings: empreinte)
      .copyWith(empreinteRatings: empreinte, origine: OrigineRegistreElo.courante)
      .encoder();
}

void _semerRatings(Map<String, double> ratings) =>
    store.semer(kCleElo, jsonEncode(_payloadElo(ratings)));

Future<void> _accorderRamAuDisque() async {
  EloService.instance.viderMemoirePourResetComplet();
  final Object? brut = store.lire(kCleElo);
  if (brut is String && brut.isNotEmpty) {
    EloService.instance
        .chargerDepuisMapIsolate(jsonDecode(brut) as Map<String, dynamic>);
  }
  await _laisserProgresser();
}

/// Contenu JSON relu depuis le fichier RÉELLEMENT écrit.
Map<String, dynamic> _jsonDuFichier(ExportResult res) {
  final f = File(res.filePath!);
  expect(f.existsSync(), isTrue, reason: 'le fichier annoncé doit exister');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

/// Coût RÉEL d'UNE collecte, mesuré à cache CHAUD.
///
/// ⚠️ POURQUOI PAS UN COMPTE ABSOLU — MESURÉ
///   `SharedPreferences.getInstance()` met l'instance EN CACHE : le premier
///   appel lit le store, les suivants non. Mesuré : `exporterDonnees()` seul
///   donne 3 accès à cache froid et 2 à cache chaud. Un compteur brut ne
///   mesure donc pas « le nombre de collectes ».
///
/// ✅ On réchauffe le cache, puis on appelle [operation] DEUX fois. La 1re
///    passe peut encore amorcer `currentUser` ; la 2e s'exécute sur un cache
///    identique. L'écart entre les deux est le coût d'UNE collecte.
Future<int> _coutCollecte(Future<Object?> Function() operation) async {
  await operation(); // réchauffage
  final int c0 = store.getAllCount;
  await operation();
  final int c1 = store.getAllCount;
  return c1 - c0;
}

/// État de départ commun aux mesures de collecte (store semé + RAM accordée).
Future<void> _seedPourCollecte() async {
  _semerRatings(<String, double>{'C12 COLLECTE|PLAT': 1700.0});
  await _accorderRamAuDisque();
}

/// Raccourci lisible pour un export seul (une collecte).
Future<ExportResult> exporter() => BackupService.instance.exporterDonnees();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _installerStore();
    EloService.instance.viderMemoirePourResetComplet();
    share.reinitialiser();
    SharePlatform.instance = share;
    _tmp = Directory.systemTemp.createTempSync('a7_38_service_');
    PathProviderPlatform.instance = _FakePathProvider(_tmp!.path);
  });

  tearDown(() {
    try {
      _tmp?.deleteSync(recursive: true);
    } catch (_) {}
    _tmp = null;
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  H1 — COLLECTE UNIQUE
  // ═════════════════════════════════════════════════════════════════════════
  //  H1 — COLLECTE UNIQUE
  //
  //  Défaut mesuré en C12 : `_exporter()` faisait 2 collectes ; la 2e
  //  réécrivait le MÊME chemin (nom horodaté au jour), donc les avertissements
  //  du 1er résultat décrivaient un autre fichier que celui présenté.
  //
  //  Propriété vérifiée : partager et télécharger ont le MÊME coût de collecte
  //  qu'un exporterDonnees() seul — exactement ce que le bug violait.
  // ═════════════════════════════════════════════════════════════════════════
  group('H1 — collecte unique', () {
    test('H1a — le partage n\'ajoute AUCUNE collecte', () async {
      await _seedPourCollecte();

      final int coutExportSeul = await _coutCollecte(
          () => BackupService.instance.exporterDonnees());
      final int coutPartage = await _coutCollecte(
          () => BackupService.instance.partagerBackupAvecResultat());

      // ignore: avoid_print
      print('[H1a] coutExportSeul=$coutExportSeul | coutPartage=$coutPartage '
          '| share=${share.appels}');

      expect(coutPartage, coutExportSeul,
          reason: 'partager ne doit RIEN collecter de plus : au-delà, '
              'les avertissements décriraient un autre fichier');
      expect(coutPartage, greaterThan(0),
          reason: 'contrôle + : la mesure doit voir au moins une collecte');
      expect(share.appels, greaterThan(0),
          reason: 'contrôle + : le partage doit solliciter le menu natif');
    });

    test('H1b — le telechargement n\'ajoute AUCUNE collecte', () async {
      await _seedPourCollecte();

      final int coutExportSeul = await _coutCollecte(
          () => BackupService.instance.exporterDonnees());
      final int coutCopie = await _coutCollecte(
          () => BackupService.instance.telechargerSurTelephone());

      // ignore: avoid_print
      print('[H1b] coutExportSeul=$coutExportSeul | coutCopie=$coutCopie');

      expect(coutCopie, coutExportSeul,
          reason: 'telecharger ne doit RIEN collecter de plus');
      expect(coutCopie, greaterThan(0),
          reason: 'contrôle + : la mesure doit voir au moins une collecte');
    });

    test('H1c — controle + : la mesure VOIT bien une double collecte', () async {
      await _seedPourCollecte();

      // Reproduit VOLONTAIREMENT le motif fautif : une collecte en trop.
      final int coutDeuxFois = await _coutCollecte(() async {
        await exporter();
        await exporter();
        return null;
      });
      final int coutUneFois = await _coutCollecte(() => exporter());

      // ignore: avoid_print
      print('[H1c] coutUneFois=$coutUneFois | coutDeuxFois=$coutDeuxFois');

      expect(coutDeuxFois, greaterThan(coutUneFois),
          reason: 'si ce controle echoue, la mesure ne distingue pas 1 de 2 '
              'collectes : H1a et H1b ne prouveraient alors RIEN');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  H2 — LE FICHIER ANNONCÉ EXISTE VRAIMENT
  //  Un résultat qui annonce un chemin sans fichier derrière serait un mensonge.
  // ═════════════════════════════════════════════════════════════════════════
  group('H2 — fichier réellement produit', () {
    test('H2a — chemin existant, non vide, contenu JSON', () async {
      _semerRatings(<String, double>{'C12 GAMMA|TROT_ATTELE': 1801.0});
      await _accorderRamAuDisque();

      final ExportResult res =
          await BackupService.instance.telechargerSurTelephone();
      final File f = File(res.filePath!);

      // ignore: avoid_print
      print('[H2a] path=${res.filePath} | taille=${f.lengthSync()} '
          '| fileName=${res.fileName}');

      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(0));
      expect(res.tailleOctets, greaterThan(0));
      expect(res.fileName, isNotNull);
      expect(f.path, endsWith(res.fileName!),
          reason: 'le nom annoncé doit correspondre au fichier écrit');

      final Map<String, dynamic> contenu = _jsonDuFichier(res);
      expect(contenu, isNotEmpty,
          reason: 'le JSON produit doit être relisible');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  H3 — AVERTISSEMENTS DU SERVICE
  // ═════════════════════════════════════════════════════════════════════════
  group('H3 — avertissements', () {
    test('H3a — sans registre : succes=true MAIS complet=false', () async {
      // Ratings semés, AUCUN registre : statut `sansRegistre`.
      _semerRatings(<String, double>{'C12 DELTA|PLAT': 1550.0});
      await _accorderRamAuDisque();

      final ExportResult res =
          await BackupService.instance.partagerBackupAvecResultat();

      // ignore: avoid_print
      print('[H3a] succes=${res.succes} nbAvert=${res.avertissements.length} '
          'complet=${res.complet} | ${res.avertissements}');

      expect(res.succes, isTrue,
          reason: 'le fichier est bien créé : ce n\'est pas un échec');
      expect(res.avertissements, isNotEmpty,
          reason: 'un export partiel DOIT être signalé');
      expect(res.complet, isFalse,
          reason: '`complet` ne doit jamais être vrai avec un avertissement');
    });

    test('H3b — avec registre cohérent : aucun avertissement, complet=true',
        () async {
      const Map<String, double> kRatings = <String, double>{'C12 ECHO|PLAT': 1490.0};
      _semerRatings(kRatings);
      store.semer(kCleRegistre, _registreCoherent(kRatings));
      await _accorderRamAuDisque();

      final ExportResult res =
          await BackupService.instance.partagerBackupAvecResultat();

      // ignore: avoid_print
      print('[H3b] succes=${res.succes} nbAvert=${res.avertissements.length} '
          'complet=${res.complet}');
      expect(res.succes, isTrue);
      expect(res.avertissements, isEmpty);
      expect(res.complet, isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  H4 — LES TROIS ÉTATS DE `partageOuvert`
  //
  //  null  → aucun menu dans ce parcours (téléchargement) ;
  //  true  → menu sollicité SANS exception (ne prouve AUCUNE réception) ;
  //  false → l'ouverture a levé, le fichier reste disponible.
  // ═════════════════════════════════════════════════════════════════════════
  group('H4 — partageOuvert', () {
    test('H4a — téléchargement : partageOuvert == null', () async {
      _semerRatings(<String, double>{'C12 FOXTROT|PLAT': 1460.0});
      await _accorderRamAuDisque();

      final ExportResult res =
          await BackupService.instance.telechargerSurTelephone();

      // ignore: avoid_print
      print('[H4a] partageOuvert=${res.partageOuvert} | share=${share.appels}');
      expect(res.partageOuvert, isNull,
          reason: 'null = null parcours de partage, et non un échec');
      expect(share.appels, 0);
    });

    test('H4b — partage sollicité sans exception : partageOuvert == true',
        () async {
      _semerRatings(<String, double>{'C12 GOLF|PLAT': 1440.0});
      await _accorderRamAuDisque();

      final ExportResult res =
          await BackupService.instance.partagerBackupAvecResultat();

      // ignore: avoid_print
      print('[H4b] partageOuvert=${res.partageOuvert} | share=${share.appels}');
      expect(res.partageOuvert, isTrue);
      expect(share.appels, 1);
      expect(res.succes, isTrue);
    });

    test('H4c — ouverture en échec : partageOuvert == false, fichier conservé',
        () async {
      _semerRatings(<String, double>{'C12 HOTEL|PLAT': 1420.0});
      await _accorderRamAuDisque();
      share.erreur = 'menu natif indisponible';

      final ExportResult res =
          await BackupService.instance.partagerBackupAvecResultat();

      // ignore: avoid_print
      print('[H4c] succes=${res.succes} partageOuvert=${res.partageOuvert} '
          'nbAvert=${res.avertissements.length} | ${res.avertissements}');

      expect(res.succes, isTrue,
          reason: 'le fichier EXISTE : l\'échec du menu n\'annule pas le fichier');
      expect(res.partageOuvert, isFalse,
          reason: 'l\'ouverture a levé : elle ne doit pas être annoncée ouverte');
      expect(res.avertissements, isNotEmpty,
          reason: 'l\'utilisateur doit être averti que rien n\'a pu être envoyé');
      expect(File(res.filePath!).existsSync(), isTrue,
          reason: 'le fichier doit rester disponible sur l\'appareil');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  H5 — CONTRATS HISTORIQUES PRÉSERVÉS
  // ═════════════════════════════════════════════════════════════════════════
  group('H5 — contrat bool conservé', () {
    test('H5a — partagerBackup() rend toujours un bool', () async {
      _semerRatings(<String, double>{'C12 INDIA|PLAT': 1400.0});
      await _accorderRamAuDisque();

      final bool ok = await BackupService.instance.partagerBackup();
      // ignore: avoid_print
      print('[H5a] ok=$ok | share=${share.appels}');
      expect(ok, isTrue);
    });

    test('H5b — sauvegarderSurDrive() rend toujours un bool', () async {
      _semerRatings(<String, double>{'C12 JULIET|PLAT': 1380.0});
      await _accorderRamAuDisque();

      final bool ok = await BackupService.instance.sauvegarderSurDrive();
      // ignore: avoid_print
      print('[H5b] ok=$ok | share=${share.appels}');
      expect(ok, isTrue);
      expect(share.appels, 1,
          reason: 'sauvegarderSurDrive délègue à partagerBackup : 1 sollicitation');
    });
  });
}
