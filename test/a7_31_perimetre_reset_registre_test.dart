// ═══════════════════════════════════════════════════════════════════════════
//  A7 — ÉTAPE 3.1 : `elo_registre_v3` DANS LE PÉRIMÈTRE DE RESET
//
//  ⚠️  FICHIER DE TEST uniquement. Aucune formule ELO, aucun coefficient K,
//      aucun mécanisme d'apprentissage, aucun poids, aucun seuil, aucun
//      TOP3 learning n'est touché ici.
//
//  ── CE QUI EST DÉMONTRÉ ─────────────────────────────────────────────────
//  3.1 ajoute `elo_registre_v3` à `BackupService._keysELO`, donc au périmètre
//  de `reinitialiserComplet()`. Ce fichier MESURE les trois points exigés,
//  sans jamais se contenter de lire la liste de clés :
//
//    ① Registre ABSENT au moment du reset.
//       → le reset doit réussir (une clé absente n'est pas un échec : le
//         contrat `remove()` du store rend `true` même si la clé n'existe
//         pas, vérifié dans `shared_preferences_platform_interface`
//         l.176-179). C'est le cas NORMAL des installations neuves.
//
//    ② Registre PRÉSENT et NON VIDE.
//       → il doit disparaître du disque, et les ratings doivent disparaître
//         AVEC lui. La paire « ratings + témoin » est le contrat de 3.1.
//
//    ③ Suppression du registre REFUSÉE par le stockage.
//       → l'échec doit rester SIGNALÉ (StateError nommant la clé) et les
//         suppressions déjà réussies ne doivent pas être annulées.
//
//  ── LIMITE DE MÉTHODE, MESURÉE ET DÉCLARÉE ──────────────────────────────
//  Ce fichier ne prouve RIEN sur la durabilité physique : le stockage de test
//  est en mémoire. `SharedPreferences` côté Android n'appelle jamais
//  `.commit()` (7 `.apply()` mesurés dans `SharedPreferencesPlugin.kt`), donc
//  un `true` de `remove()`/`setString()` n'est PAS une preuve d'écriture
//  physique. Aucune assertion ci-dessous ne prétend le contraire.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Clés de production telles qu'elles existent à l'étape 3.1.
//  Elles sont nommées ici EXPLICITEMENT : un test de reset doit vérifier des
//  noms réels, pas une constante réimportée depuis le code testé.
// ───────────────────────────────────────────────────────────────────────────
const String kCleRatings = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
const String kCleRegistre = 'elo_registre_v3';

// ───────────────────────────────────────────────────────────────────────────
//  Espion de stockage — même contrat que celui de la suite (a4_lot2),
//  augmenté d'une capacité d'échec ciblé sur UNE clé.
// ───────────────────────────────────────────────────────────────────────────
class _Espion extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};

  /// Écritures et suppressions réellement exécutées, dans l'ordre.
  final List<String> journal = <String>[];

  /// Clé dont le `remove` doit être REFUSÉ (`false`), ou `null`.
  String? cleRefusee;

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
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    if (cleRefusee != null && key == 'flutter.$cleRefusee') {
      // Refus RÉEL : la clé reste sur le disque, comme un stockage qui dit non.
      return false;
    }
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET $key');
    _valeurs[key] = value;
    return true;
  }

  // ── Helpers : clé NON préfixée, comme `prefs.setString(key, …)` ──────────
  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? brut(String cle) => _valeurs['flutter.$cle'];

  /// Nombre de `REM` visant une clé donnée (sans le préfixe natif).
  int nbRem(String cle) =>
      journal.where((e) => e == 'REM flutter.$cle').length;
}

late _Espion _store;

void _installerStore() {
  _store = _Espion();
  SharedPreferencesStorePlatform.instance = _store;
  SharedPreferences.resetStatic();
}

// ───────────────────────────────────────────────────────────────────────────
//  Jeu de données ELO minimal et NON TRIVIAL.
//  Les valeurs sont choisies pour être reconnaissables à l'œil dans un
//  message d'échec : si l'une réapparaît après un reset, c'est visible.
// ───────────────────────────────────────────────────────────────────────────
const Map<String, double> kRatingsTemoins = <String, double>{
  'A7 ALPHA|TROT_ATTELE': 1712.5,
  'A7 BRAVO|TROT_ATTELE': 1633.25,
  'A7 CHARLIE|PLAT': 1487.75,
};

Map<String, dynamic> _payloadElo() {
  final out = <String, dynamic>{};
  kRatingsTemoins.forEach((nomDisc, rating) {
    final nom = nomDisc.split('|').first;
    out[nomDisc] = EloScore(
      nomCheval: nom,
      rating: rating,
      nbCourses: 7,
      variationMois: 3.5,
    ).toJson();
  });
  return out;
}

/// Registre non vide, de forme réaliste pour l'étape 3.1 (aucune sémantique
/// d'acquittement n'existe encore : on ne teste ici que la PERSISTANCE et la
/// SUPPRESSION de la clé).
Map<String, dynamic> _registreNonVide() => <String, dynamic>{
      'version': 3,
      'operations': <String, dynamic>{
        'R1C1_20260417': <String, dynamic>{
          'etat': 'temoin-3.1',
          'chevaux': <String>['A7 ALPHA', 'A7 BRAVO'],
        },
      },
    };

/// Remet le service ELO dans un état vierge de processus, sans écrire.
void _viderEloRam() =>
    EloService.instance.viderMemoirePourResetComplet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _installerStore();
    // Le singleton survit d'un test à l'autre : on jette sa RAM ET on
    // s'assure qu'aucune écriture n'est en vol avant de semer.
    _viderEloRam();
    SharedPreferences.resetStatic();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A7-31-0 — LA CLÉ APPARTIENT BIEN AU PÉRIMÈTRE
  //
  //  Ce test ne vérifie PAS un comportement observable par l'utilisateur :
  //  il vérifie que la liste de reset CONTIENT le nom exact de la clé.
  //  C'est volontairement le SEUL test « structurel » du fichier — les
  //  suivants mesurent des effets sur le disque, pas des listes.
  // ═════════════════════════════════════════════════════════════════════════
  test('A7-31-0 — `elo_registre_v3` est dans le périmètre de reset', () async {
    // On sème le registre, on lance le reset, et on regarde le JOURNAL des
    // suppressions réellement demandées au stockage. Si la clé n'était pas
    // dans `_keysELO`, aucun `REM` ne la viserait.
    _store.semer(kCleRegistre, jsonEncode(_registreNonVide()));

    await BackupService.instance.reinitialiserComplet();

    final remRegistre = _store.nbRem(kCleRegistre);
    final remRatings = _store.nbRem(kCleRatings);

    // ignore: avoid_print
    print('[A7-31-0] REM $kCleRatings=$remRatings | '
        'REM $kCleRegistre=$remRegistre | '
        'dans le journal=${_store.journal.contains('REM flutter.$kCleRegistre')}');

    expect(remRegistre, greaterThanOrEqualTo(1),
        reason: 'le reset doit demander la suppression de `$kCleRegistre` — '
            'sans cela, le témoin survivrait aux ratings qu\'il décrit');
    expect(remRatings, greaterThanOrEqualTo(1),
        reason: 'le reset doit aussi demander la suppression de `$kCleRatings`');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A7-31-1 — REGISTRE ABSENT AU MOMENT DU RESET
  //
  //  Cas normal d'une installation neuve, et cas d'un second reset
  //  consécutif. Le store rend `true` sur une clé absente : le reset doit
  //  donc RÉUSSIR et ne signaler AUCUN échec.
  // ═════════════════════════════════════════════════════════════════════════
  test('A7-31-1 — registre absent : le reset réussit sans signaler d\'échec',
      () async {
    // Ratings présents, registre JAMAIS semé.
    await EloService.instance.importerDepuisBackup(_payloadElo());
    expect(_store.contient(kCleRatings), isTrue,
        reason: 'témoin de non-vacuité : les ratings doivent être sur le disque '
            'AVANT le reset');
    expect(_store.contient(kCleRegistre), isFalse,
        reason: 'témoin : le registre doit bien être ABSENT dans ce scénario');

    Object? erreur;
    try {
      await BackupService.instance.reinitialiserComplet();
    } catch (e) {
      erreur = e;
    }

    // ignore: avoid_print
    print('[A7-31-1] erreur=${erreur == null ? 'aucune' : erreur.runtimeType} | '
        'ratingsApres=${_store.contient(kCleRatings)} | '
        'registreApres=${_store.contient(kCleRegistre)}');

    expect(erreur, isNull,
        reason: 'une clé ABSENTE n\'est pas un échec : le reset doit réussir '
            'normalement. Erreur observée : $erreur');
    expect(_store.contient(kCleRatings), isFalse,
        reason: 'les ratings doivent avoir disparu');
    expect(_store.contient(kCleTs), isFalse,
        reason: '`$kCleTs` fait partie du même périmètre');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A7-31-2 — REGISTRE PRÉSENT ET NON VIDE
  //
  //  Le cœur de 3.1 : les deux disparaissent ENSEMBLE. On vérifie aussi que
  //  le contenu réel des ratings est effacé, et pas seulement la clé.
  // ═════════════════════════════════════════════════════════════════════════
  test('A7-31-2 — registre non vide : registre ET ratings disparaissent',
      () async {
    await EloService.instance.importerDepuisBackup(_payloadElo());
    await SharedPreferences.getInstance()
        .then((p) => p.setString(kCleRegistre, jsonEncode(_registreNonVide())));
    SharedPreferences.resetStatic();

    final prefsAvant = await SharedPreferences.getInstance();
    expect(prefsAvant.getString(kCleRegistre), isNotNull,
        reason: 'témoin de non-vacuité : le registre doit être présent AVANT');
    expect(prefsAvant.getString(kCleRatings), isNotNull,
        reason: 'témoin de non-vacuité : les ratings doivent être présents');
    expect(EloService.instance.nbChevauxSuivis, kRatingsTemoins.length,
        reason: 'témoin : ${kRatingsTemoins.length} ratings attendus en RAM');

    await BackupService.instance.reinitialiserComplet();

    final prefs = await SharedPreferences.getInstance();
    final registreApres = prefs.getString(kCleRegistre);
    final ratingsApres = prefs.getString(kCleRatings);

    // ignore: avoid_print
    print('[A7-31-2] registreApres=${registreApres ?? "absent"} | '
        'ratingsApres=${ratingsApres ?? "absent"} | '
        'RAM=${EloService.instance.nbChevauxSuivis}');

    expect(registreApres, isNull,
        reason: 'le registre doit avoir disparu en même temps que les ratings');
    expect(ratingsApres, isNull,
        reason: 'les ratings doivent être effacés');
    expect(EloService.instance.nbChevauxSuivis, 0,
        reason: 'la RAM ELO doit être vidée par le reset');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A7-31-3 — SUPPRESSION DU REGISTRE REFUSÉE
  //
  //  Le stockage dit NON. Exigences : l'échec est SIGNALÉ (StateError), la
  //  clé est NOMMÉE, et les suppressions déjà réussies ne sont pas annulées.
  //  On vérifie aussi que le refus ne dégénère pas en succès silencieux.
  // ═════════════════════════════════════════════════════════════════════════
  test('A7-31-3 — suppression du registre refusée : échec signalé et nommé',
      () async {
    await EloService.instance.importerDepuisBackup(_payloadElo());
    await SharedPreferences.getInstance()
        .then((p) => p.setString(kCleRegistre, jsonEncode(_registreNonVide())));
    SharedPreferences.resetStatic();

    expect(_store.contient(kCleRegistre), isTrue,
        reason: 'témoin de non-vacuité : le registre doit être présent');

    // Le stockage refuse UNIQUEMENT la suppression du registre.
    _store.cleRefusee = kCleRegistre;

    Object? erreur;
    try {
      await BackupService.instance.reinitialiserComplet();
    } catch (e) {
      erreur = e;
    }

    // ignore: avoid_print
    print('[A7-31-3] erreur=${erreur?.runtimeType} | '
        'nommeLaCle=${erreur.toString().contains(kCleRegistre)} | '
        'registreToujoursLa=${_store.contient(kCleRegistre)} | '
        'ratingsEffaces=${!_store.contient(kCleRatings)}');

    expect(erreur, isA<StateError>(),
        reason: 'un refus réel doit lever une StateError, jamais un succès muet');
    expect(erreur.toString(), contains(kCleRegistre),
        reason: 'le message doit NOMMER la clé refusée — un diagnostic sans le '
            'nom ne permet pas de reprendre l\'opération');
    expect(_store.contient(kCleRegistre), isTrue,
        reason: 'la clé refusée doit rester sur le disque : le refus est réel');
    // Contrat historique : les suppressions déjà faites ne sont PAS annulées.
    expect(_store.contient(kCleRatings), isFalse,
        reason: 'les suppressions réussies avant le refus ne doivent pas être '
            'annulées (contrat « les suppressions déjà réussies ne sont PAS '
            'annulées »)');
  });
}
