// ═══════════════════════════════════════════════════════════════════════════
//  A7 — CARACTÉRISATION DE LA SAUVEGARDE ELO (D1 / D2)
//
//  OBJET : constater et MESURER ce que la sauvegarde actuelle transporte
//  réellement en matière d'ELO. Ce fichier ne définit AUCUN contrat cible :
//  il photographie l'existant. Si une évolution change ces résultats, ces
//  tests DOIVENT échouer — c'est leur seule utilité.
//
//  ÉTAT CARACTÉRISÉ (démontré ici par EXÉCUTION, pas par lecture) :
//    • `exporterPourBackup()` rend UNIQUEMENT les ratings ;
//    • `elo_ratings_v2_ts` n'est PAS transporté ;
//    • `elo_registre_v3`      n'est PAS transporté ;
//    • les ratings sont donc exportés SANS leur témoin ni leur horodatage.
//
//  ⚠️ CE QUE CES TESTS NE DISENT PAS
//    Ils ne disent PAS qu'il faut changer le format. Ils établissent le fait.
//
//  ⚠️ LIMITE DE DURABILITÉ PHYSIQUE
//    Le store est en mémoire (`SharedPreferences` de test). `setString → true`
//    ne prouve aucune écriture physique. On n'affirme donc rien là-dessus.
//
//  FORMULES / K-FACTORS / POIDS / SEUILS / TOP3 / CRITÈRES A–Q : non touchés.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/elo_registre_v3.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/utils/elo_empreinte.dart';

const String kCleRatings = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
const String kCleRegistre = 'elo_registre_v3';

// Littéraux du format enrichi. ÉCRITS EN DUR, jamais importés : un renommage
// de constante du service doit être DÉTECTÉ par ces tests, pas suivi
// silencieusement.
const String kCleFormat = '_elo_format';
const String kFormatV2 = 'elo_v2';
const String kCleRegistreBrut = '_elo_registre';
const String kCleTsBrut = '_elo_ts';

// ───────────────────────────────────────────────────────────────────────────
//  Store minimal instrumenté : suffisant pour peupler disque + RAM.
// ───────────────────────────────────────────────────────────────────────────
class _StoreS extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

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
    _valeurs[key] = value;
    return true;
  }

  /// Pose une valeur en respectant le préfixe natif, comme le fait
  /// `SharedPreferences` lui-même.
  void poser(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;

  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');
  Object? lire(String cle) => _valeurs['flutter.$cle'];
}

// ignore: library_private_types_in_public_api
late _StoreS _store;

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tmpPath);
  final String tmpPath;
  @override
  Future<String?> getTemporaryPath() async => tmpPath;
}

void _installerStore() {
  _store = _StoreS();
  SharedPreferencesStorePlatform.instance = _store;
  SharedPreferences.resetStatic();
  EloService.instance.viderMemoirePourResetComplet();
  SharedPreferences.resetStatic();
}

/// Clé ELO composite, cohérente avec la normalisation de `EloService`.
String _cleElo(String nom, {String discipline = 'TROT_ATTELE'}) =>
    '${nom.toUpperCase()}|$discipline';

/// Ratings de référence, non triviaux : deux chevaux, valeurs distinctes.
Map<String, dynamic> _payloadRatings() => <String, dynamic>{
      for (final n in <String>['SAUV ALPHA', 'A7 SAVE BRAVO'])
        _cleElo(n): const EloScore(
          nomCheval: '',
          rating: 0,
          nbCourses: 0,
          variationMois: 0,
        ).toJson()
          ..addAll(<String, dynamic>{
            'nom': n,
            'rating': n.contains('ALPHA') ? 1637.5 : 1488.25,
            'nb': n.contains('ALPHA') ? 17 : 4,
            'var': n.contains('ALPHA') ? 12.5 : -3.75,
          }),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_installerStore);

  // ═════════════════════════════════════════════════════════════════════════
  //  D1a — `exporterPourBackup()` ne transporte QUE les ratings
  // ═════════════════════════════════════════════════════════════════════════
  test('D1a — exporterPourBackup : ratings seuls, ni registre ni horodatage',
      () async {
    // ── Préparation : des ratings RÉELS en RAM ──────────────────────────────
    await EloService.instance.importerDepuisBackup(_payloadRatings());
    expect(EloService.instance.nbChevauxSuivis, 2,
        reason: 'les deux ratings doivent être chargés');

    // ── L'horodatage existe sur le disque ───────────────────────────────────
    _store.poser(kCleTs, 1794900000000);
    expect(_store.contient(kCleTs), isTrue,
        reason: 'préparation : le timestamp doit être présent avant l\'export');

    // ── Un registre VALIDE contenant au moins UNE entrée ────────────────────
    final String registreValide =
        RegistreEloV3.vierge(empreinteRatings: empreinte64Ratings(
          <String, EloScore>{
            for (final n in <String>['SAUV ALPHA', 'A7 SAVE BRAVO'])
              _cleElo(n): EloScore(nomCheval: n, rating: 1600.0),
          },
        )).copyWith(
          entrees: <EntreeRegistreElo>[
            EntreeRegistreElo(
              id: 1,
              type: TypeEntreeRegistre.course,
              cle: 'R1C1_01112026',
              numR: 1,
              numC: 1,
              date: '2026-11-01',
              discipline: 'TROT_ATTELE',
              etape: EtapeEntreeRegistre.appliquee,
              issue: IssueEcritureElo.persistee,
              tsIntention: 1794900000000,
              tsFinal: 1794900001000,
              empreinteAvant: empreinte64Ratings(const <String, EloScore>{}),
              empreinteApres: empreinte64Ratings(
                <String, EloScore>{
                  _cleElo('SAUV ALPHA'): EloScore(
                      nomCheval: 'SAUV ALPHA', rating: 1637.5),
                },
              ),
            ),
          ],
        ).encoder();

    _store.poser(kCleRegistre, registreValide);
    expect(_store.contient(kCleRegistre), isTrue,
        reason: 'préparation : le registre doit être présent avant l\'export');

    // ── MESURE ──────────────────────────────────────────────────────────────
    final Map<String, dynamic> exporte = EloService.instance.exporterPourBackup();

    // ignore: avoid_print
    print('[D1a] clefs exportees=${exporte.keys.toList()} | '
        'nb=${exporte.length} | '
        'contient registre=${exporte.containsKey(kCleRegistre)} | '
        'contient ts=${exporte.containsKey(kCleTs)} | '
        'registre disque present=${_store.contient(kCleRegistre)} | '
        'ts disque present=${_store.contient(kCleTs)}');

    // ── ASSERTIONS DE CARACTÉRISATION ───────────────────────────────────────
    expect(exporte.length, 2,
        reason: 'un Map plat : une entrée par cheval, aucune métadonnée');

    expect(exporte.containsKey(_cleElo('SAUV ALPHA')), isTrue,
        reason: 'le rating ALPHA doit être transporté, sous sa clé composite');
    expect(exporte.containsKey(_cleElo('A7 SAVE BRAVO')), isTrue,
        reason: 'le rating BRAVO doit être transporté');

    // ★ CŒUR DE D1/D2 — les deux clés sœurs ne sont PAS transportées.
    expect(exporte.containsKey(kCleRegistre), isFalse,
        reason: 'D1 : le registre n\'est JAMAIS exporté');
    expect(exporte.containsKey(kCleTs), isFalse,
        reason: 'D2 : l\'horodatage n\'est JAMAIS exporté');

    // Le registre et le timestamp existent POURTANT sur le disque : l'absence
    // dans l'export n'est donc pas due à leur absence du store.
    expect(_store.contient(kCleRegistre), isTrue);
    expect(_store.contient(kCleTs), isTrue);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  D1b — le JSON de sauvegarde COMPLET, via le VRAI parcours d'export
  //
  //  ⚠️ CE TEST A ÉTÉ CORRIGÉ AU LOT 3.3-C11 (arbitrage OPTION B).
  //
  //  Son décor initial semait un registre dont l'empreinte déclarée était
  //  celle de la map VIDE, alors que DEUX ratings étaient persistés. C'était
  //  un registre DIVERGENT, donc un `refuse` légitime : l'export enrichi
  //  n'écrivait aucun groupe, et l'assertion « `elo_service` présent »
  //  échouait. La prémisse du test (« l'export transporte les ratings sans
  //  témoin ») était périmée par conception, PAS le code en défaut.
  //
  //  Le décor est désormais COHÉRENT, et l'assertion renforcée porte sur le
  //  contrat réellement attendu d'un export complet : groupe enrichi présent,
  //  marqueurs présents, ET empreinte déclarée par le registre exporté égale
  //  à l'empreinte RECALCULÉE depuis les ratings exportés.
  //
  //  D1a et D1c ne sont PAS touchés : ils caractérisent `exporterPourBackup()`,
  //  strictement inchangée, et doivent continuer de la photographier.
  // ═════════════════════════════════════════════════════════════════════════
  test('D1b — exporterDonnees : groupe ELO enrichi et cohérent, sans les 2 '
      'clés sœurs à la racine', () async {
    // ── Préparation des ratings ─────────────────────────────────────────────
    await EloService.instance.importerDepuisBackup(_payloadRatings());

    // ── Préparation du registre : empreinte calculée sur CES ratings ────────
    //
    // On relit les ratings RÉELLEMENT PERSISTÉS et on décode chacun avec le
    // MÊME `EloScore.fromJson` que le service : l'empreinte sème donc
    // exactement ce que `_etablirDiagnosticPreImport()` recalculera, ce qui
    // évite de recopier à la main une convention de décodage — et donc de
    // réintroduire une divergence par construction.
    final Object? ratingsBruts = _store.lire(kCleRatings);
    expect(ratingsBruts is String && ratingsBruts.isNotEmpty, isTrue,
        reason: 'préparation : les ratings doivent être PERSISTÉS sur le '
            'disque, sinon le diagnostic porte sur une map vide');

    final Map<String, EloScore> persistes = <String, EloScore>{};
    (jsonDecode(ratingsBruts as String) as Map<String, dynamic>)
        .forEach((cle, valeur) {
      persistes[cle] = EloScore.fromJson(valeur as Map<String, dynamic>);
    });
    expect(persistes.keys, _payloadRatings().keys.toSet(),
        reason: 'les deux chevaux doivent être relus, sans perte ni ajout');

    final String empreintePersistee = empreinte64Ratings(persistes);

    final RegistreEloV3 registre =
        RegistreEloV3.vierge(empreinteRatings: empreintePersistee)
            .copyWith(
              empreinteRatings: empreintePersistee,
              origine: OrigineRegistreElo.courante,
              entrees: const <EntreeRegistreElo>[],
            );

    // Contrôles de PRÉPARATION : schéma et version attendus, registre
    // interprétable, et empreinte EFFECTIVEMENT égale à celle des ratings.
    expect(registre.schema, kSchemaRegistreElo);
    expect(registre.version, kVersionRegistreElo);
    expect(registre.interpretable, isTrue,
        reason: 'un registre non interprétable serait refusé, pas exporté');
    expect(registre.empreinteRatings, empreintePersistee,
        reason: 'sans cette égalité, le décor redeviendrait DIVERGENT');

    _store.poser(kCleRegistre, registre.encoder());
    _store.poser(kCleTs, 1794900000000);

    expect(_store.contient(kCleRegistre), isTrue);
    expect(_store.contient(kCleTs), isTrue);

    // ── Le VRAI parcours d'export ───────────────────────────────────────────
    final tmp = Directory.systemTemp.createTempSync('a7_33_save_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);

    final ExportResult res = await BackupService.instance.exporterDonnees();

    // ── Relecture du fichier RÉELLEMENT écrit ───────────────────────────────
    expect(res.succes, isTrue, reason: 'l\'export doit réussir');
    expect(res.filePath, isNotNull);
    final File fichier = File(res.filePath!);
    expect(fichier.existsSync(), isTrue,
        reason: 'le fichier annoncé doit exister sur le disque');

    final Map<String, dynamic> json =
        jsonDecode(fichier.readAsStringSync()) as Map<String, dynamic>;

    final Object? elo = json['elo_service'];
    final Map<String, dynamic> groupe =
        elo is Map<String, dynamic> ? elo : <String, dynamic>{};

    Set<String> clesCheval(Map<String, dynamic> m) =>
        m.keys.where((k) => !k.startsWith('_elo_')).toSet();

    // ignore: avoid_print
    print('[D1b] succes=${res.succes} complet=${res.complet} '
        'avertissements=${res.avertissements} | '
        'racine=${json.keys.toList()} | '
        'elo_service present=${json.containsKey('elo_service')} | '
        'clefs elo=${groupe.keys.toList()..sort()} | '
        'racine contient registre=${json.containsKey(kCleRegistre)} | '
        'racine contient ts=${json.containsKey(kCleTs)}');

    // ── Contrat de l'ExportResult ──────────────────────────────────────────
    expect(res.complet, isTrue,
        reason: 'un export sans groupe omis doit être annoncé COMPLET');
    expect(res.avertissements, isEmpty,
        reason: 'aucun avertissement sur un export complet');

    // ── Contrat du fichier ─────────────────────────────────────────────────
    expect(json.containsKey('elo_service'), isTrue,
        reason: 'le volet ELO doit exister : un refus n\'écrit AUCUN groupe');

    // 1. Marqueur de format
    expect(groupe[kCleFormat], kFormatV2,
        reason: 'le groupe enrichi doit se déclarer `elo_v2`');

    // 2. Registre VERBATIM (chaîne persistée, jamais réencodée)
    expect(groupe.containsKey(kCleRegistreBrut), isTrue,
        reason: 'un export COMPLET transporte le registre');
    expect(groupe[kCleRegistreBrut], _store.lire(kCleRegistre),
        reason: 'le registre exporté est la chaîne PERSISTÉE, à l\'octet près');

    // 3. Horodatage (semé ⇒ présent, et de type int)
    expect(groupe.containsKey(kCleTsBrut), isTrue,
        reason: 'l\'horodatage a été semé : il doit être transporté');
    expect(groupe[kCleTsBrut], 1794900000000);
    expect(groupe[kCleTsBrut], isA<int>(),
        reason: 'un horodatage non entier ferait croire à une lecture erronée');

    // 4. Les deux ratings historiques, à leur clé composite, sans fantôme
    expect(clesCheval(groupe), _payloadRatings().keys.toSet(),
        reason: 'exactement les deux chevaux : aucune perte, aucun fantôme');
    for (final entree in _payloadRatings().entries) {
      final Map<String, dynamic> exporte =
          groupe[entree.key] as Map<String, dynamic>;
      expect(exporte['rating'], (entree.value as Map)['rating']);
      expect(exporte['nom'], (entree.value as Map)['nom']);
      expect(exporte['nb'], (entree.value as Map)['nb']);
      expect(exporte['var'], (entree.value as Map)['var']);
    }

    // 5. ★ COHÉRENCE : l'empreinte déclarée par le registre EXPORTÉ doit être
    //    recalculable depuis les ratings EXPORTÉS. C'est l'assertion qui
    //    interdit qu'un groupe soit produit avec un témoin qui ne décrit pas
    //    les ratings qu'il accompagne.
    final Map<String, EloScore> relusExport = <String, EloScore>{};
    clesCheval(groupe).forEach((cle) {
      relusExport[cle] =
          EloScore.fromJson(groupe[cle] as Map<String, dynamic>);
    });
    final String empreinteExportee = empreinte64Ratings(relusExport);
    final RegistreEloV3 registreExporte =
        RegistreEloV3.decoder(groupe[kCleRegistreBrut] as String);

    // ignore: avoid_print
    print('[D1b] empreinte recalculee=$empreinteExportee | '
        'empreinte declaree=${registreExporte.empreinteRatings} | '
        'egales=${empreinteExportee == registreExporte.empreinteRatings}');

    expect(empreinteExportee, empreintePersistee,
        reason: 'les ratings exportés sont ceux dont l\'empreinte a servi');
    expect(registreExporte.empreinteRatings, empreinteExportee,
        reason: 'le témoin exporté DOIT décrire les ratings exportés');

    // ── Les deux clés sœurs ne sont PAS à la racine (contrat historique) ───
    expect(json.containsKey(kCleRegistre), isFalse,
        reason: 'le registre vit DANS `elo_service`, pas à la racine');
    expect(json.containsKey(kCleTs), isFalse,
        reason: 'l\'horodatage vit DANS `elo_service`, pas à la racine');

    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  D1c — preuve par CONTRE-ÉPREUVE : les ratings, eux, SONT bien exportés
  //        et relus à l'identique. Sans cela, D1a/D1b pourraient n'être que
  //        l'effet d'un export VIDE.
  // ═════════════════════════════════════════════════════════════════════════
  test('D1c — contre-épreuve : les ratings exportés sont relus à l\'identique',
      () async {
    await EloService.instance.importerDepuisBackup(_payloadRatings());
    final Map<String, dynamic> avant = EloService.instance.exporterPourBackup();

    // L'export est bien NON VIDE et porte les valeurs attendues.
    expect(avant, isNotEmpty, reason: 'l\'export ne doit pas être vide');
    final Map<String, dynamic> alpha =
        avant[_cleElo('SAUV ALPHA')] as Map<String, dynamic>;
    expect(alpha['rating'], 1637.5);
    expect(alpha['nb'], 17);
    expect(alpha['var'], 12.5);

    // Un aller-retour par le chemin d'import réel doit rendre le même état.
    await EloService.instance.importerDepuisBackup(avant);
    final Map<String, dynamic> apres = EloService.instance.exporterPourBackup();

    // ignore: avoid_print
    print('[D1c] avant=${avant.length} clefs | apres=${apres.length} clefs | '
        'identiques=${jsonEncode(avant) == jsonEncode(apres)}');

    expect(jsonEncode(apres), jsonEncode(avant),
        reason: 'les ratings font l\'aller-retour SANS PERTE — eux, oui');
  });
}
