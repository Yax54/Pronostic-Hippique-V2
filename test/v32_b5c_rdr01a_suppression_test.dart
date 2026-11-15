// ═══════════════════════════════════════════════════════════════════════════
//  B5c — R-DR-01-a — SUPPRESSION DES CLÉS CACHE DYNAMIQUES
//
//  OBJET : vérifier que `BackupService.reinitialiserComplet()` supprime
//  TOUTES les clés dont le nom commence par `cache_reunions_`, y compris
//  les `_ts` ORPHELINES, sans toucher aux clés étrangères au préfixe.
//
//  PÉRIMÈTRE STRICT : cette correction ne traite QUE le défaut de
//  suppression (R01-a). Les défauts de cache RAM (R01-b), de concurrence
//  d'écriture (R01-c) et de cache statique ZoneTurf (R01-d) NE SONT PAS
//  traités ici et restent démontrés par v31 / v31b (R01-H, R01-J, R01-N).
//
//  AUCUNE assertion de v31 / v31b n'est affaiblie par ce fichier.
// ═══════════════════════════════════════════════════════════════════════════
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/services/backup_service.dart';

// ── Store contrôlable ───────────────────────────────────────────────────────
class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  /// Clés dont le `remove` doit ÉCHOUER (retourner `false`).
  final Set<String> clesEnEchecRemove = <String>{};

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
    journal.add('GETALL');
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    if (clesEnEchecRemove.contains(key)) return false;
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET $key');
    _valeurs[key] = value;
    return true;
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;

  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');

  Object? lire(String cle) => _valeurs['flutter.$cle'];

  List<String> get cles => _valeurs.keys
      .map((k) => k.replaceFirst('flutter.', ''))
      .toList()
    ..sort();

  List<String> clesCache() =>
      cles.where((k) => k.startsWith('cache_reunions_')).toList();
}

// ignore: library_private_types_in_public_api
late _Store store;

const String kPrefixe = 'cache_reunions_';

String _dateOff(int jours) {
  final n = DateTime.now().add(Duration(days: jours));
  return '${n.day.toString().padLeft(2, '0')}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.year}';
}

String get kCacheAujourdhui => '$kPrefixe${_dateOff(0)}';
String get kTsAujourdhui => '${kCacheAujourdhui}_ts';
String get kCacheHier => '$kPrefixe${_dateOff(-1)}';
String get kTsHier => '${kCacheHier}_ts';
String get kCacheDemain => '$kPrefixe${_dateOff(1)}';
String get kTsDemain => '${kCacheDemain}_ts';

/// Clé totalement étrangère au préfixe ET absente des 107 clés fixes.
const String kCleEtrangere = 'mon_test_etranger_rdr01a';

/// Clé faisant partie des 107 (témoin : doit être supprimée aussi).
const String kCleFixe = 'alert_config_v2';

const String kJson = '[{"code":"R1","lieu":"VINCENNES",'
    '"discipline":"Trot","date":"01012026","courses":[]}]';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  A — PLUSIEURS DATES PRÉSENTES AVANT LE RESET → TOUTES SUPPRIMÉES
  // ═══════════════════════════════════════════════════════════════════════
  test('R01a-A — plusieurs dates en cache : toutes supprimées', () async {
    store.semer(kCacheHier, kJson);
    store.semer(kTsHier, 1000);
    store.semer(kCacheAujourdhui, kJson);
    store.semer(kTsAujourdhui, 2000);
    store.semer(kCacheDemain, kJson);
    store.semer(kTsDemain, 3000);

    final avant = store.clesCache();
    debugPrint('R01a-A avant : $avant');
    expect(avant.length, 6,
        reason: 'TÉMOIN : trois dates × deux clés sont présentes');

    await BackupService.instance.reinitialiserComplet();

    final apres = store.clesCache();
    debugPrint('R01a-A apres : $apres');

    expect(apres, isEmpty,
        reason: 'CORRECTION R01-a : TOUTES les dates sont balayées. Une liste '
            'fixe ne pouvait en nommer aucune — c\'est pourquoi le balayage '
            'lit les clés réellement présentes');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B — CLÉS cache ET _ts → TOUTES SUPPRIMÉES  (discriminant M34 / M35)
  // ═══════════════════════════════════════════════════════════════════════
  test('R01a-B — la paire cache + _ts est supprimée (M34, M35)', () async {
    store.semer(kCacheAujourdhui, kJson);
    store.semer(kTsAujourdhui, 1234);

    await BackupService.instance.reinitialiserComplet();

    debugPrint('R01a-B apres : ${store.clesCache()}');

    // ── ASSERTION DISCRIMINANTE DE M34 ───────────────────────────────────
    //  M34 = suppression du balayage dynamique entier → cette assertion
    //  échoue (les deux clés subsistent).
    expect(store.contient(kCacheAujourdhui), isFalse,
        reason: 'CORRECTION R01-a / DISCRIMINANT M34 : la clé JSON est '
            'supprimée. Sans le balayage, elle survit au reset');

    // ── ASSERTION DISCRIMINANTE DE M35 ───────────────────────────────────
    //  M35 = on ne supprime que les clés sans suffixe `_ts` → cette
    //  assertion échoue (le `_ts` subsiste).
    expect(store.contient(kTsAujourdhui), isFalse,
        reason: 'CORRECTION R01-a / DISCRIMINANT M35 : la clé `_ts` est '
            'supprimée elle aussi. `startsWith(prefixe)` la couvre '
            'naturellement, puisqu\'elle commence par le préfixe');
    expect(store.clesCache(), isEmpty);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  C — CLÉ _ts ORPHELINE → SUPPRIMÉE  (discriminant M35)
  // ═════════════════════════════════════════════════════＝＝══════════════
  test('R01a-C — une clé _ts orpheline est supprimée (M35)', () async {
    // Une `_ts` sans JSON : état réel laissé par un `setString` en échec
    // (comportement mesuré en V31b R01-L, où `setInt` est exécuté quand
    // même après l'échec de `setString`).
    store.semer(kTsAujourdhui, 999);

    expect(store.contient(kCacheAujourdhui), isFalse, reason: 'TÉMOIN : pas de JSON');
    expect(store.contient(kTsAujourdhui), isTrue, reason: 'TÉMOIN : _ts orpheline');

    await BackupService.instance.reinitialiserComplet();

    debugPrint('R01a-C apres : ${store.clesCache()}');

    expect(store.contient(kTsAujourdhui), isFalse,
        reason: 'CORRECTION R01-a / DISCRIMINANT M35 : l\'orpheline est '
            'supprimée. Le filtre porte sur le PRÉFIXE, pas sur la présence '
            'd\'une clé JSON appariée — une `_ts` seule est donc bien vue');
    expect(store.clesCache(), isEmpty);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  D — CLÉS ÉTRANGÈRES AU PRÉFIXE → PRÉSERVÉES
  //      (sauf celles déjà prévues par les 107 suppressions)
  // ═══════════════════════════════════════════════════════════════════════
  test('R01a-D — les clés hors préfixe sont préservées', () async {
    store.semer(kCleEtrangere, 'a conserver');
    store.semer(kCleFixe, 'sera supprimee car dans les 107');
    store.semer(kCacheAujourdhui, kJson);
    store.semer('ia_archive_v1_preservee', 'archive E3/E4');

    await BackupService.instance.reinitialiserComplet();

    debugPrint('R01a-D restant : ${store.cles}');

    expect(store.contient(kCleEtrangere), isTrue,
        reason: 'NON-RÉGRESSION : une clé hors préfixe n\'est PAS touchée par '
            'le balayage. Le filtre `startsWith` est strict');
    expect(store.contient('ia_archive_v1_preservee'), isTrue,
        reason: 'NON-RÉGRESSION : les archives E3/E4 restent hors du '
            'périmètre du reset (décision validée)');
    expect(store.contient(kCleFixe), isFalse,
        reason: 'TÉMOIN : une clé des 107 est bien supprimée — la boucle '
            'fixe fonctionne toujours');
    expect(store.contient(kCacheAujourdhui), isFalse,
        reason: 'CORRECTION : le cache est supprimé');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  E — ÉCHEC SIMULÉ D'UNE SUPPRESSION DYNAMIQUE → ENREGISTRÉ
  // ═══════════════════════════════════════════════════════════════════════
  test('R01a-E — un échec de suppression dynamique est enregistré', () async {
    store.semer(kCacheAujourdhui, kJson);
    store.semer(kTsAujourdhui, 111);
    store.clesEnEchecRemove.add('flutter.$kCacheAujourdhui');

    Object? erreur;
    try {
      await BackupService.instance.reinitialiserComplet();
    } catch (e) {
      erreur = e;
    }

    debugPrint('R01a-E erreur : $erreur');
    debugPrint('R01a-E restant : ${store.cles}');

    expect(erreur, isA<StateError>(),
        reason: 'CORRECTION : un `remove` qui rend `false` est enregistré dans '
            'le MÊME accumulateur `echecs` que la boucle fixe, donc le '
            'diagnostic `StateError` est levé — rien n\'est avalé');
    expect(erreur.toString(), contains(kCacheAujourdhui),
        reason: 'CORRECTION : la clé dynamique en échec est NOMMÉE dans le '
            'message, comme les clés fixes le sont déjà');

    expect(store.contient(kCacheAujourdhui), isTrue,
        reason: 'FAIT : la clé en échec subsiste (le store a refusé)');
    expect(store.contient(kTsAujourdhui), isFalse,
        reason: 'FAIT : les autres clés dynamiques sont bien supprimées — '
            'un reset partiellement effectué n\'est PAS une transaction '
            'annulée (logique existante conservée)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  F — NOUVELLE ÉCRITURE LÉGITIME APRÈS RESET → TOUJOURS POSSIBLE
  // ═══════════════════════════════════════════════════════════════════════
  test('R01a-F — une écriture légitime après reset reste possible', () async {
    store.semer(kCacheAujourdhui, kJson);
    store.semer(kTsAujourdhui, 555);

    await BackupService.instance.reinitialiserComplet();
    expect(store.clesCache(), isEmpty, reason: 'TÉMOIN : reset effectif');

    // Écriture normale, comme le fait `_sauvegarderCacheLocal` (l.329-330).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kCacheAujourdhui, kJson);
    await prefs.setInt(kTsAujourdhui, 777);

    debugPrint('R01a-F apres ecriture : ${store.clesCache()}');

    expect(store.contient(kCacheAujourdhui), isTrue,
        reason: 'NON-RÉGRESSION : le service peut réécrire son cache après un '
            'reset. Le balayage ne gèle rien — il ne s\'exécute qu\'une fois, '
            'pendant le reset');
    expect(store.contient(kTsAujourdhui), isTrue);
    expect(store.lire(kTsAujourdhui), 777);
  });
}
