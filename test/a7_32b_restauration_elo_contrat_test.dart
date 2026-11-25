// ═══════════════════════════════════════════════════════════════════════════
//  A7 — ÉTAPE 3.2 / LOT 1 : CONTRAT DE RESTAURATION DU VOLET ELO
//
//  CE QUI EST MESURÉ ICI
//  ─────────────────────
//  Avant le lot 1, `_restaurerDepuisJson()` consommait l'état rendu par
//  `EloService.importerDepuisBackup()` par un `await` MUET :
//    • `setString → false` et une exception étaient indiscernables ;
//    • le tampon « ELO restaure » s'imprimait même en cas de refus ;
//    • `ImportResult` n'exposait AUCUNE information ELO.
//
//  Après le lot 1 (C1), deux champs portent le verdict réel :
//    • `nbEloRestaures`   — ratings chargés en RAM (PAS une persistance) ;
//    • `avertissementElo` — non nul si la persistance n'est pas confirmée,
//      ou si l'écriture a été abandonnée par un reset.
//
//  ⚠️ CE QUE CES TESTS N'ASSERTENT JAMAIS
//  ──────────────────────────────────────
//  Un `avertissementElo` non nul ne dit PAS « le disque est resté
//  inchangé ». Aucune assertion ci-dessous ne prétend le contraire : on
//  vérifie l'ÉTAT RETOURNÉ, et l'on OBSERVE le disque pour information.
//
//  ⚠️ LIMITE DE DURABILITÉ PHYSIQUE
//  ────────────────────────────────
//  Le store est en mémoire. `SharedPreferences` Android n'appelle jamais
//  `.commit()` (7 `.apply()` mesurés). `setString → true` ne prouve donc
//  AUCUNE écriture physique : ces tests ne prétendent pas le contraire.
//
//  FORMULES / K-FACTORS / POIDS / SEUILS / TOP3 : aucun n'est touché.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';

const String kCleElo = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';

// ───────────────────────────────────────────────────────────────────────────
//  Store instrumenté
//    • `refus`  → `setValue` répond `false` sans écrire ;
//    • `levent` → `setValue` LÈVE une exception ;
//    • `verrouGetInstance` → suspend `getAllWithParameters`, c'est-à-dire
//      le SEUL `await` situé entre le contrôle 1 et le contrôle 2 de
//      `_sauvegarder()`. C'est ce qui rend le scénario « abandon par reset »
//      DÉTERMINISTE au lieu de reposer sur une course.
// ───────────────────────────────────────────────────────────────────────────
class _StoreR extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  final Set<String> refus = <String>{};
  final Set<String> levent = <String>{};

  Completer<void>? _verrouGetAll;
  Completer<void>? _entreeGetAll;

  /// Arme une suspension de la PROCHAINE `getAllWithParameters`.
  /// Retourne la future complétée dès que la suspension est ATTEINTE.
  Completer<void> armerSuspensionGetAll() {
    final entree = Completer<void>();
    _entreeGetAll = entree;
    _verrouGetAll = Completer<void>();
    return entree;
  }

  void libererGetAll() {
    final v = _verrouGetAll;
    _verrouGetAll = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  bool get suspensionArmee => _verrouGetAll != null;

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
    journal.add('GETALL');
    final verrou = _verrouGetAll;
    if (verrou != null) {
      final entree = _entreeGetAll;
      _entreeGetAll = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      await verrou.future;
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
    journal.add('SET $key');
    if (levent.contains(key)) {
      throw StateError('panne simulée sur $key');
    }
    if (refus.contains(key)) return false;
    _valeurs[key] = value;
    return true;
  }

  // Helpers — clé SANS le préfixe natif
  void poser(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
}

// ignore: library_private_types_in_public_api
late _StoreR _store;

/// Faux répertoire temporaire : `exporterDonnees()` doit écrire un vrai
/// fichier JSON que la restauration relira.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tmpPath);
  final String tmpPath;
  @override
  Future<String?> getTemporaryPath() async => tmpPath;
}

/// Injecte un fichier choisi sans passer par le sélecteur natif.
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this._result);
  final FilePickerResult? _result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      _result;
}

void _installerStore() {
  _store = _StoreR();
  SharedPreferencesStorePlatform.instance = _store;
  SharedPreferences.resetStatic();
  EloService.instance.viderMemoirePourResetComplet();
  SharedPreferences.resetStatic();
}

String _cleElo(String nom) => '${nom.toUpperCase()}|TROT_ATTELE';

Map<String, dynamic> _payloadElo() => <String, dynamic>{
      for (final n in <String>['A7R ALPHA', 'A7R BRAVO'])
        _cleElo(n): <String, dynamic>{
          'nom': n, 'rating': 1600.0, 'nb': 12, 'var': 2.5,
        },
    };

/// Sème un état ELO minimal (RAM + disque cohérents) SANS passer par le
/// chemin de restauration, pour ne pas polluer les compteurs mesurés.
Future<void> _semerElo(String nomProfil) async {
  // `importerDepuisBackup` écrit : on l'utilise pour peupler RAM + disque,
  // puis on réécrit le disque avec l'état RAM pour que « disque = RAM ».
  final payload = _payloadElo();
  await EloService.instance.importerDepuisBackup(payload);
  _store.poser(kCleElo, jsonEncode(EloService.instance.exporterPourBackup()));
  // Un groupe non-ELO, pour prouver que son sort est INDÉPENDANT.
  _store.poser('profil_nom', nomProfil);
}

/// Lance la restauration par la VRAIE API publique, sur un fichier réel.
Future<ImportResult> _restaurerDepuis(Map<String, dynamic> contenu) async {
  final tmp = Directory.systemTemp.createTempSync('a7_32b_');
  PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  final f = File('${tmp.path}/backup_test.json');
  f.writeAsStringSync(json.encode(contenu));
  final octets = Uint8List.fromList(f.readAsBytesSync());

  FilePicker.platform = _FakeFilePicker(FilePickerResult([
    PlatformFile(name: 'backup_test.json', size: octets.length, bytes: octets),
  ]));
  final res = await BackupService.instance.importerDepuisFichier();
  try {
    tmp.deleteSync(recursive: true);
  } catch (_) {}
  return res;
}

/// Contenu de sauvegarde minimal mais RÉEL : sceau, version, un groupe
/// non-ELO (`profil`), et le volet ELO.
Map<String, dynamic> _backupAvecElo({bool avecElo = true}) => <String, dynamic>{
      'appName': 'Pronostic Hippique',
      'version': '9.1',
      'dateBackup': '2026-01-15T10:00:00.000',
      'profil': <String, dynamic>{
        'profil_nom': <String, dynamic>{'type': 'String', 'value': 'PROFIL LOCAL'},
      },
      if (avecElo)
        'elo_service': <String, dynamic>{
          for (final n in <String>['A7R ALPHA', 'A7R BRAVO'])
            _cleElo(n): <String, dynamic>{
              'nom': n, 'rating': 1600.0, 'nb': 12, 'var': 2.5,
            },
        },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_installerStore);

  // ═════════════════════════════════════════════════════════════════════════
  //  R1 — PERSISTANCE CONFIRMÉE : aucun avertissement
  // ═════════════════════════════════════════════════════════════════════════
  test('R1 — persistance ELO confirmée : succes=true, avertissementElo=null',
      () async {
    await _semerElo('PROFIL AVANT');

    final res = await _restaurerDepuis(_backupAvecElo());

    // ignore: avoid_print
    print('[R1] succes=${res.succes} | nbElo=${res.nbEloRestaures} | '
        'avertissement=${res.avertissementElo} | '
        'nbCles=${res.nbClesRestaurees} | disque=${_store.contient(kCleElo)}');

    expect(res.succes, isTrue,
        reason: 'la restauration générale doit réussir');
    expect(res.nbEloRestaures, 2,
        reason: 'deux ratings sont chargés en RAM');
    expect(res.avertissementElo, isNull,
        reason: 'persistance confirmée ⇒ aucun avertissement ELO');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  R2 — `setString` REFUSE : avertissement, `succes` INTACT,
  //       autres groupes INTACTS, `nbClesRestaurees` INTACT
  // ═════════════════════════════════════════════════════════════════════════
  test('R2 — setString refuse : avertissement, succes et autres groupes intacts',
      () async {
    // Mesure de référence, store sain, MÊME sauvegarde.
    final reference = await _restaurerDepuis(_backupAvecElo());
    final nbClesRef = reference.nbClesRestaurees;
    final nbProfilRef = reference.nbProfil;

    // Même sauvegarde, mais le stockage refuse la clé ELO.
    _installerStore();
    _store.refus.add('flutter.$kCleElo');

    final res = await _restaurerDepuis(_backupAvecElo());

    // ignore: avoid_print
    print('[R2] succes=${res.succes} | nbElo=${res.nbEloRestaures} | '
        'avertissement=${res.avertissementElo} | '
        'nbCles=${res.nbClesRestaurees}(ref=$nbClesRef) | '
        'nbProfil=${res.nbProfil}(ref=$nbProfilRef) | '
        'disqueElo=${_store.contient(kCleElo)}');

    expect(res.succes, isTrue,
        reason: 'UN ÉCHEC ELO NE DOIT JAMAIS DEVENIR UN ÉCHEC TOTAL');
    expect(res.avertissementElo, isNotNull,
        reason: 'le refus doit être SIGNALÉ, plus jamais tu');
    expect(res.avertissementElo, contains('refusee'),
        reason: 'l\'état doit être nommé : refusee');
    expect(res.avertissementElo, contains('PAS confirmée'),
        reason: 'le message doit dire NON CONFIRMÉE');
    expect(res.avertissementElo, contains('inchangé'),
        reason: 'le message doit explicitement écarter « disque inchangé »');
    expect(res.nbClesRestaurees, nbClesRef,
        reason: '`nbClesRestaurees` ne doit PAS bouger : l\'ELO n\'y entre pas');
    expect(res.nbProfil, nbProfilRef,
        reason: 'les autres groupes doivent être restaurés à l\'identique');
    expect(res.nbEloRestaures, 2,
        reason: 'les ratings SONT chargés en RAM même si le disque refuse : '
            'le nombre compte la RAM, pas la persistance');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  R3 — `setString` LÈVE : avertissement, `succes` INTACT
  // ═════════════════════════════════════════════════════════════════════════
  test('R3 — setString leve : avertissement=echouee, succes intact', () async {
    _store.levent.add('flutter.$kCleElo');

    final res = await _restaurerDepuis(_backupAvecElo());

    // ignore: avoid_print
    print('[R3] succes=${res.succes} | avertissement=${res.avertissementElo} | '
        'derniereErreur=${EloService.instance.derniereErreurEcriture.runtimeType}');

    expect(res.succes, isTrue,
        reason: 'une exception ELO ne doit pas faire échouer la restauration');
    expect(res.avertissementElo, contains('echouee'),
        reason: 'l\'état doit être nommé : echouee');
    expect(EloService.instance.derniereErreurEcriture, isA<StateError>(),
        reason: 'l\'exception doit rester CONSERVÉE côté service');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  R4 — CHARGE ELO MALFORMÉE : le `catch` reste utile
  // ═════════════════════════════════════════════════════════════════════════
  test('R4 — charge elo_service malformee : avertissement, aucune exception',
      () async {
    final contenu = _backupAvecElo();
    contenu['elo_service'] = 'ceci-n-est-pas-un-objet';

    final res = await _restaurerDepuis(contenu);

    // ignore: avoid_print
    print('[R4] succes=${res.succes} | nbElo=${res.nbEloRestaures} | '
        'avertissement=${res.avertissementElo}');

    expect(res.succes, isTrue,
        reason: 'un volet ELO illisible ne doit pas faire échouer le reste');
    expect(res.avertissementElo, isNotNull,
        reason: 'la charge illisible doit être SIGNALÉE');
    expect(res.avertissementElo, contains('illisible'));
    expect(res.nbEloRestaures, 0,
        reason: 'aucun rating n\'a pu être chargé');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  R5 — ABANDON PAR RESET : l'écriture ELO est refusée par une barrière
  //
  //  Dispositif DÉTERMINISTE, et non une course : `executerResetComplet()`
  //  pose `_resetEnCours = true` de façon SYNCHRONE (l.590) puis attend le
  //  callback d'effacement fourni par le test. On suspend CE callback, ce
  //  qui maintient la barrière fermée aussi longtemps qu'on le veut, et l'on
  //  lance la restauration DANS cet intervalle : le CONTRÔLE 1 de
  //  `_sauvegarder()` la refuse alors de façon certaine.
  //
  //  ⚠️ Tentative écartée, mesurée pendant la mise au point : suspendre
  //  `SharedPreferences.getInstance()` ne produit AUCUN abandon, car le
  //  cache statique est déjà chaud après la première lecture du fichier —
  //  `_sauvegarder()` ne rappelle alors pas le store. Mesuré : la
  //  restauration réussissait avec `persistee` et `avertissementElo = null`.
  // ═════════════════════════════════════════════════════════════════════════
  test('R5 — abandon par reset : avertissement ABANDONNÉE, succes intact',
      () async {
    final refusResetAvant = EloService.instance.nbRefusParReset;
    var entreEffacement = 0;

    // Reset retenu dans son corps d'effacement, barrière FERMÉE.
    final entreeReset = Completer<void>();
    final verrouReset = Completer<void>();
    final futureReset = EloService.instance.executerResetComplet(() async {
      if (!entreeReset.isCompleted) entreeReset.complete();
      await verrouReset.future;
      entreEffacement++;
    });
    await entreeReset.future;
    expect(entreeReset.isCompleted, isTrue,
        reason: 'TÉMOIN : le reset est entré dans son corps d\'effacement');

    // Le registre des écritures est un témoin NEUTRE ici : il ne voit que
    // `_executerSauvegarde`, jamais la barrière elle-même.
    final registrePendant = EloService.instance.nbEcrituresEnCours;

    // Restauration lancée PENDANT que la barrière est tenue.
    final res = await _restaurerDepuis(_backupAvecElo());

    final deltaRefusReset =
        EloService.instance.nbRefusParReset - refusResetAvant;

    // ignore: avoid_print
    print('[R5] succes=${res.succes} | nbElo=${res.nbEloRestaures} | '
        'avertissement=${res.avertissementElo} | '
        'deltaRefusReset=$deltaRefusReset | '
        'entreEffacement=$entreEffacement | '
        'disqueElo=${_store.contient(kCleElo)} | '
        'registrePendant=$registrePendant');

    expect(res.succes, isTrue,
        reason: 'un abandon ELO ne doit pas faire échouer la restauration');
    expect(res.avertissementElo, isNotNull,
        reason: 'l\'abandon doit être SIGNALÉ');
    expect(res.avertissementElo, contains('ABANDONNÉE'),
        reason: 'le message doit nommer l\'abandon');
    expect(deltaRefusReset, 1,
        reason: 'PREUVE : c\'est bien le CONTRÔLE 1 (`_resetEnCours`) qui a '
            'refusé l\'écriture, et lui seul');
    expect(res.nbEloRestaures, 2,
        reason: 'les ratings sont lus et placés en RAM ; c\'est la '
            'PERSISTANCE qui est abandonnée, pas le chargement');
    expect(_store.contient(kCleElo), isFalse,
        reason: 'aucune écriture ELO n\'a été tentée : la clé est absente '
            'du stockage (elle n\'a jamais existé, le reset est en cours)');

    // Clôture : libération du reset, qui termine son `finally`.
    verrouReset.complete();
    await futureReset;
    expect(entreEffacement, 1, reason: 'TÉMOIN : le reset est allé au bout');
    expect(EloService.instance.nbEcrituresEnCours, 0,
        reason: 'le registre doit être vide après le reset');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  R6 — COMPATIBILITÉ HISTORIQUE : sauvegarde SANS volet ELO
  // ═════════════════════════════════════════════════════════════════════════
  test('R6 — sauvegarde sans elo_service : aucun avertissement, nbElo=0',
      () async {
    final res = await _restaurerDepuis(_backupAvecElo(avecElo: false));

    // ignore: avoid_print
    print('[R6] succes=${res.succes} | nbElo=${res.nbEloRestaures} | '
        'avertissement=${res.avertissementElo} | '
        'nbProfil=${res.nbProfil}');

    expect(res.succes, isTrue);
    expect(res.nbEloRestaures, 0,
        reason: 'aucun volet ELO ⇒ aucun rating chargé');
    expect(res.avertissementElo, isNull,
        reason: 'ABSENCE de volet ELO n\'est pas un échec : aucun '
            'avertissement ne doit apparaître (compatibilité historique)');
    expect(res.nbProfil, greaterThanOrEqualTo(1),
        reason: 'les autres groupes sont restaurés normalement');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  R7 — NON-RÉGRESSION DE `ImportResult` : les 6 constructeurs existants
  //       restent valides, et les nouveaux champs ont des défauts sûrs.
  // ═════════════════════════════════════════════════════════════════════════
  test('R7 — ImportResult : defauts surs, constructeurs existants intacts',
      () async {
    // Forme utilisée par les sites d'échec (l.985/996/1002/1011/1328).
    final echec = ImportResult(succes: false, erreur: 'x');
    expect(echec.nbEloRestaures, 0);
    expect(echec.avertissementElo, isNull);
    expect(echec.succes, isFalse);

    // Forme utilisée par le site de succès (l.1371), SANS les nouveaux
    // champs : doit compiler et rester valide.
    final success = ImportResult(succes: true, nbClesRestaurees: 42);
    expect(success.nbClesRestaurees, 42);
    expect(success.nbEloRestaures, 0);
    expect(success.avertissementElo, isNull);
    expect(success.resumeRestauration, contains('42'));

    // ignore: avoid_print
    print('[R7] echec.{nbElo,avert}={${echec.nbEloRestaures},'
        '${echec.avertissementElo}} | '
        'succes.nbCles=${success.nbClesRestaurees} | '
        'resume="${success.resumeRestauration}"');
  });
}
