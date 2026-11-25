// ═══════════════════════════════════════════════════════════════════════════
//  V15 — E5 : CONSERVATION PERMANENTE DE L'HISTORIQUE PREMIUM
//
//  Objet : prouver que la purge temporelle à 90 jours retirée par E5 ne
//  détruit plus les entrées premium, à 90 / 180 / 365 / 730 jours, avec
//  redémarrage simulé et cycle complet sauvegarde → restauration.
//
//  Ce que ces tests N'EXAMINENT PAS (périmètre interdit, inchangé par E5) :
//   • règles d'attribution des étoiles (_estPremiumExactGagnantStrict)
//   • surbrillance or et cumul des séries (calculerStreakPremium)
//   • affichage du calendrier  • _pronostics (600)  • apprentissage IA
//   • gradient descent, _poids, _seuils, TOP 3, analyseJourneeComplete()
//
//  ⚠️ PORTÉE EXPLICITE : E5 protège les DONNÉES premium. Il ne rend PAS
//  visibles les étoiles antérieures à la fenêtre de _pronostics ; cette
//  partie relève de E2 et n'est pas testée ici.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// ★ A-3 (Option E′) : `models/zt_models.dart` n'est plus importé — seul S-1
//   construisait des ZtCourse/ZtPartant, remplacés par le semis historique.
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/pronostic_resultats_repository.dart';
import 'package:pronostic_hippique/services/quasi_gros_paris_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  FAUX DE PLATEFORME (autonomes — V15 ne dépend d'aucun autre fichier test)
// ═══════════════════════════════════════════════════════════════════════════

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.tmpPath);
  final String tmpPath;

  @override
  Future<String?> getTemporaryPath() async => tmpPath;
}

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

/// Store en mémoire, suffisant pour V15 (aucune simulation de panne requise).
class _FauxStore extends SharedPreferencesStorePlatform {
  _FauxStore({Map<String, Object>? data})
      : _data = Map<String, Object>.from(data ?? {});

  final Map<String, Object> _data;

  @override
  Future<bool> clear() async => clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final f = parameters.filter;
    for (final k in _data.keys
        .where((k) =>
            k.startsWith(f.prefix) &&
            (f.allowList == null || f.allowList!.contains(k)))
        .toList()) {
      _data.remove(k);
    }
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final f = parameters.filter;
    final result = Map<String, Object>.from(_data);
    result.removeWhere((k, _) =>
        !k.startsWith(f.prefix) ||
        (f.allowList != null && !f.allowList!.contains(k)));
    return result;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _data[key] = value;
    return true;
  }

  // ── Outils ──────────────────────────────────────────────────────────────
  bool contient(String key) => _data.containsKey('flutter.$key');
  Object? brut(String key) => _data['flutter.$key'];
  List<String> get cles =>
      _data.keys.map((k) => k.replaceFirst('flutter.', '')).toList();
}

// ═══════════════════════════════════════════════════════════════════════════
//  OUTILS
// ═══════════════════════════════════════════════════════════════════════════

const String _kPremiumKey = 'ia_premium_historique_v1';
const String _kSelectKey = 'premium_widgets_selection_jour_v1';
const String _kPronosticsKey = 'ia_pronostics_v2'; // ★ A-3 : semis historique résolu

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _ddmmyyyy(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Entrée premium minimale, telle que produite par les widgets du jour J.
PremiumPronosticDuJour _premium({
  required DateTime jour,
  int r = 1,
  int c = 1,
  String typePari = 'Quinté+',
  String sourceWidget = 'conseilJour',
  List<String> numeros = const ['3', '7', '1', '5', '2'],
}) =>
    PremiumPronosticDuJour(
      courseKey: 'R${r}C${c}_${_ddmmyyyy(jour)}',
      typePari: typePari,
      numeros: numeros,
      sourceWidget: sourceWidget,
    );

/// ★ A-3 (Option E′) — Pronostic historique DÉJÀ RÉSOLU, au format de
/// persistance (`IaPronostic.toJson()`), destiné à être semé dans
/// `ia_pronostics_v2` **avant** tout chargement du service.
///
/// POURQUOI CE SEMIS REMPLACE LA BOUCLE `enregistrerPronostic()` +
/// `enregistrerResultat()` :
///   • `enregistrerResultat()` appelle `_save()`, et `_save()` commence par
///     `_purgerVieuxPronostics()` (M1). Un pronostic daté de plus de
///     `_maxPronosticsAge` (90 j) et NON ENCORE résolu au moment de cette
///     sauvegarde est donc supprimé AVANT d'être résolu. Seuls 91 des 130
///     survivaient — la purge, jamais l'historique premium, était en cause.
///   • Le semis passe par le MÉCANISME NORMAL de chargement : `_load()` relit
///     `ia_pronostics_v2` ; aucun accès aux structures internes n'est forcé.
///   • M1 n'est PAS contournée ni modifiée : elle continue de purger en
///     production. Le semis décrit un appareil dont les 130 courses ont été
///     RÉSOLUES EN LEUR TEMPS ; leurs pronostics sont donc, de fait, résolus.
///
/// CHAMPS STRICTEMENT NÉCESSAIRES À `_estPremiumExactGagnantStrict()` :
///   `courseKey` (égalité), `typePariConseille` (branche « quinté »),
///   `arriveeReelle` (comparaison des 5 numéros), `resultatsReels` (résolu).
///   ⚠️ Cette fonction NE LIT AUCUNE COTE : ni `coteFavoriPmu`, ni
///      `cotesPmuParNumero` n'interviennent dans son verdict.
Map<String, dynamic> _pronosticResoluHistorique({
  required DateTime jour,
  required int r,
  required int c,
  List<int> arrivee = const [3, 7, 1, 5, 2],
  String typePari = 'Quinté+',
}) =>
    IaPronostic(
      courseKey: 'R${r}C${c}_${_ddmmyyyy(jour)}',
      nomCourse: 'Course historique $c',
      hippodrome: 'Vincennes',
      discipline: 'Trot Attelé',
      datePronostic: jour, // date RÉELLE du jour de course (J−i)
      dateResultat: jour,
      scoresIA: const <String, double>{
        '3': 92.0,
        '7': 84.0,
        '1': 76.0,
        '5': 68.0,
        '2': 60.0,
      },
      scoresCriteres: const <String, ScoresCriteres>{},
      resultatsReels: true,
      arriveeReelle: arrivee,
      typePariConseille: typePari,
    ).toJson();

/// Historique premium « vieux » injecté directement dans le stockage, comme
/// le ferait un appareil utilisé depuis des mois. Aucun pronostic associé :
/// E5 ne doit pas s'en soucier, il ne touche qu'à la conservation.
Map<String, Object> _stockageAvecHistoriqueAncien({
  required List<DateTime> jours,
  bool avecSelectionFigee = false,
}) {
  final entries = <String, dynamic>{};
  for (var i = 0; i < jours.length; i++) {
    entries[_ymd(jours[i])] = [
      _premium(jour: jours[i], r: i + 1, c: i + 1).toJson(),
    ];
  }
  final data = <String, Object>{
    'flutter.$_kPremiumKey': json.encode({'entries': entries}),
  };
  if (avecSelectionFigee) {
    data['flutter.$_kSelectKey'] = json.encode({
      for (final j in jours) _ymd(j): {'conseilJour': {'courseKey': 'R1C1'}}
    });
  }
  return data;
}

_FauxStore _installerStore({Map<String, Object>? data}) {
  final store = _FauxStore(data: data ?? <String, Object>{});
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  return store;
}

/// Redémarrage simulé : cache statique vidé, même store, RAM remise à zéro.
Future<void> _redemarrer(_FauxStore store) async {
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  await IaMemoryService.instance.recharger();
}

/// Jours de référence relatifs à l'horloge réelle (la purge utilisait
/// DateTime.now() : les tests doivent rester valables quel que soit le jour).
DateTime _ilYA(int jours) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).subtract(Duration(days: jours));
}

// ── Constructeurs ZT ────────────────────────────────────────────────────────
//  ★ A-3 (Option E′) : `_course()` et `_partant()` ont été RETIRÉS.
//  Seul S-1 les utilisait, via le couple enregistrerPronostic/enregistrerResultat
//  que le semis historique a remplacé. Les conserver produisait du code mort
//  (`unused_element`) ; les supprimer ne retire AUCUNE assertion.

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('v15_e5_');
    _installerStore();
    await IaArchiveService.instance.effacerTout();
    await PronosticResultatsRepository.instance
        .restaurerDepuisBackup({'pronosticResultats': []});
    await QuasiGrosParisService.instance
        .importerDepuisBackup({'signaux': [], 'quasiGagnants': []});
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  C — CONSERVATION APRÈS ENREGISTREMENT (le cœur de E5)
  //
  //  Avant E5, enregistrerPronosticsPremiumDuJour() purgeait tout ce qui
  //  avait plus de 90 jours, À CHAQUE appel. Ces tests reproduisent cet
  //  appel et vérifient que plus rien n'est détruit.
  // ═══════════════════════════════════════════════════════════════════════

  group('C — Conservation après enregistrement du jour', () {
    test('C-1 — 90 jours : entrée conservée (limite exacte d\'avant E5)',
        () async {
      final ancien = _ilYA(90);
      final store = _installerStore(data: _stockageAvecHistoriqueAncien(
        jours: [ancien],
      ));
      await IaMemoryService.instance.recharger();

      // Écriture du jour : c'est là qu'opérait la purge.
      await IaMemoryService.instance
          .enregistrerPronosticsPremiumDuJour([_premium(jour: DateTime.now())]);

      final svc = IaMemoryService.instance;
      expect(svc.premiumsPourDate(ancien.year, ancien.month, ancien.day).length,
          1,
          reason: 'l\'entrée à 90 jours ne doit plus être purgée');
      expect(svc.premiumsPourDate(DateTime.now().year, DateTime.now().month,
              DateTime.now().day).length,
          1,
          reason: 'l\'entrée du jour est bien écrite');
      expect(store.contient(_kPremiumKey), isTrue);
    });

    test('C-2 — 180 jours : entrée conservée', () async {
      final ancien = _ilYA(180);
      _installerStore(data: _stockageAvecHistoriqueAncien(jours: [ancien]));
      await IaMemoryService.instance.recharger();

      await IaMemoryService.instance
          .enregistrerPronosticsPremiumDuJour([_premium(jour: DateTime.now())]);

      expect(
          IaMemoryService.instance
              .premiumsPourDate(ancien.year, ancien.month, ancien.day)
              .length,
          1,
          reason: '180 jours > 90 : l\'entrée doit survivre');
    });

    test('C-3 — 365 jours : entrée conservée', () async {
      final ancien = _ilYA(365);
      _installerStore(data: _stockageAvecHistoriqueAncien(jours: [ancien]));
      await IaMemoryService.instance.recharger();

      await IaMemoryService.instance
          .enregistrerPronosticsPremiumDuJour([_premium(jour: DateTime.now())]);

      expect(
          IaMemoryService.instance
              .premiumsPourDate(ancien.year, ancien.month, ancien.day)
              .length,
          1,
          reason: '1 an : l\'entrée doit survivre');
    });

    test('C-4 — 730 jours : entrée conservée', () async {
      final ancien = _ilYA(730);
      _installerStore(data: _stockageAvecHistoriqueAncien(jours: [ancien]));
      await IaMemoryService.instance.recharger();

      await IaMemoryService.instance
          .enregistrerPronosticsPremiumDuJour([_premium(jour: DateTime.now())]);

      expect(
          IaMemoryService.instance
              .premiumsPourDate(ancien.year, ancien.month, ancien.day)
              .length,
          1,
          reason: '2 ans : l\'entrée doit survivre');
    });

    test('C-5 — 90/180/365/730 jours simultanés : les 4 survivent, contenu intact',
        () async {
      final jours = [_ilYA(90), _ilYA(180), _ilYA(365), _ilYA(730)];
      final store =
          _installerStore(data: _stockageAvecHistoriqueAncien(jours: jours));
      await IaMemoryService.instance.recharger();

      await IaMemoryService.instance
          .enregistrerPronosticsPremiumDuJour([_premium(jour: DateTime.now())]);

      final svc = IaMemoryService.instance;
      for (var i = 0; i < jours.length; i++) {
        final list = svc.premiumsPourDate(
            jours[i].year, jours[i].month, jours[i].day);
        expect(list.length, 1, reason: 'jour ${_ymd(jours[i])} conservé');
        // Le contenu doit être INTACT : ni tronqué, ni réécrit, ni inventé.
        expect(list.first.courseKey, 'R${i + 1}C${i + 1}_${_ddmmyyyy(jours[i])}');
        expect(list.first.typePari, 'Quinté+');
        expect(list.first.sourceWidget, 'conseilJour');
        expect(list.first.numeros, ['3', '7', '1', '5', '2']);
      }

      // Le stockage contient bien les 4 entrées anciennes + celle du jour.
      final brut = json.decode(store.brut(_kPremiumKey) as String)
          as Map<String, dynamic>;
      final entries = brut['entries'] as Map<String, dynamic>;
      expect(entries.length, 5,
          reason: '4 entrées anciennes + 1 du jour, aucune perte');
      for (final j in jours) {
        expect(entries.containsKey(_ymd(j)), isTrue,
            reason: '${_ymd(j)} encore sur le disque');
      }
    });

    test('C-6 — 40 enregistrements successifs ne détruisent rien', () async {
      // Avant E5, la purge s'exécutait à CHAQUE appel : 40 appels = 40 purges.
      final ancien = _ilYA(500);
      _installerStore(data: _stockageAvecHistoriqueAncien(jours: [ancien]));
      await IaMemoryService.instance.recharger();

      for (var i = 0; i < 40; i++) {
        await IaMemoryService.instance.enregistrerPronosticsPremiumDuJour([
          _premium(jour: DateTime.now(), r: i + 1, c: 1, typePari: 'Tiercé'),
        ]);
      }

      expect(
          IaMemoryService.instance
              .premiumsPourDate(ancien.year, ancien.month, ancien.day)
              .length,
          1,
          reason: 'aucun des 40 enregistrements ne doit purger l\'ancienne entrée');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  R — REDÉMARRAGE SIMULÉ
  // ═══════════════════════════════════════════════════════════════════════

  group('R — Survie au redémarrage simulé', () {
    test('R-1 — 90/180/365/730 jours survivent à 2 redémarrages', () async {
      final jours = [_ilYA(90), _ilYA(180), _ilYA(365), _ilYA(730)];
      final store =
          _installerStore(data: _stockageAvecHistoriqueAncien(jours: jours));
      // recharger() force un _load() réel : sans lui, _loaded=true (hérité du
      // setUp) ferait écrire les étoiles dans le store précédent, désormais
      // débranché — et le redémarrage suivant ne verrait que le seeding.
      await IaMemoryService.instance.recharger();
      expect(IaMemoryService.instance
              .premiumsPourDate(jours[0].year, jours[0].month, jours[0].day).length,
          1,
          reason: 'garde-fou : le seeding doit être chargé');

      await IaMemoryService.instance
          .enregistrerPronosticsPremiumDuJour([_premium(jour: DateTime.now())]);

      for (var cycle = 1; cycle <= 2; cycle++) {
        await _redemarrer(store);
        for (final j in jours) {
          expect(
              IaMemoryService.instance
                  .premiumsPourDate(j.year, j.month, j.day)
                  .length,
              1,
              reason: 'cycle $cycle : ${_ymd(j)} doit être rechargé du disque');
        }
      }
    });

    test('R-2 — une entrée ajoutée puis redémarrée est toujours là', () async {
      final store = _installerStore();
      final j = _ilYA(400);
      // Injection directe, comme un historique préexistant sur l'appareil.
      await IaMemoryService.instance.recharger();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kPremiumKey,
        json.encode({
          'entries': {
            _ymd(j): [_premium(jour: j).toJson()],
          }
        }),
      );
      await _redemarrer(store);

      expect(
          IaMemoryService.instance.premiumsPourDate(j.year, j.month, j.day).length,
          1,
          reason: '400 jours : rechargé sans purge');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B — CYCLE COMPLET SAUVEGARDE → RESTAURATION
  // ═══════════════════════════════════════════════════════════════════════

  group('B — Sauvegarde puis restauration', () {
    /// Exporte via l'API publique et renvoie le JSON décodé.
    Future<Map<String, dynamic>> exporter() async {
      PathProviderPlatform.instance = _FakePathProvider(tmpDir.path);
      final res = await BackupService.instance.exporterDonnees();
      expect(res.succes, isTrue, reason: 'exporterDonnees a échoué');
      final contenu = await File(res.filePath!).readAsString();
      return json.decode(contenu) as Map<String, dynamic>;
    }

    /// Restaure via l'API publique depuis un contenu JSON.
    Future<void> importer(Map<String, dynamic> contenu) async {
      final bytes = Uint8List.fromList(utf8.encode(json.encode(contenu)));
      FilePicker.platform = _FakeFilePicker(FilePickerResult([
        PlatformFile(
            name: 'backup_v15.json', size: bytes.length, bytes: bytes),
      ]));
      final res = await BackupService.instance.importerDepuisFichier();
      expect(res.succes, isTrue, reason: 'importerDepuisFichier a échoué');
    }

    test('B-1 — les 4 âges sont exportés puis restaurés à l\'identique',
        () async {
      final jours = [_ilYA(90), _ilYA(180), _ilYA(365), _ilYA(730)];
      _installerStore(data: _stockageAvecHistoriqueAncien(jours: jours));
      await IaMemoryService.instance.recharger();

      final contenu = await exporter();

      // Le fichier doit contenir la clé premium avec les 4 entrées.
      final ia = contenu['ia'] as Map<String, dynamic>;
      expect(ia.containsKey(_kPremiumKey), isTrue,
          reason: 'ia_premium_historique_v1 doit figurer dans la sauvegarde');
      final exporte = ia[_kPremiumKey] as Map<String, dynamic>;
      final entries = json.decode(exporte['value'] as String)
          as Map<String, dynamic>;
      final mapEntries = entries['entries'] as Map<String, dynamic>;
      expect(mapEntries.length, 4);
      for (final j in jours) {
        expect(mapEntries.containsKey(_ymd(j)), isTrue,
            reason: '${_ymd(j)} présent dans l\'export');
      }

      // Appareil vierge → restauration.
      final storeVierge = _installerStore();
      await IaMemoryService.instance.recharger();
      expect(IaMemoryService.instance.premiumsPourDate(
              jours[0].year, jours[0].month, jours[0].day).length,
          0,
          reason: 'garde-fou : l\'appareil vierge ne contient rien');

      await importer(contenu);
      await _redemarrer(storeVierge);

      for (final j in jours) {
        expect(
            IaMemoryService.instance.premiumsPourDate(j.year, j.month, j.day).length,
            1,
            reason: '${_ymd(j)} restauré après redémarrage');
      }
    });

    test('B-2 — ancien format de sauvegarde (sans archiveIA) conserve les étoiles',
        () async {
      // Sauvegarde fabriquée « à l'ancienne » : v9.0, aucune clé archiveIA,
      // la clé premium au format encapsulé {entries:{...}}.
      final jours = [_ilYA(120), _ilYA(600)];
      final ia = <String, dynamic>{};
      for (final j in jours) {
        ia[_kPremiumKey] = {
          'type': 'String',
          'value': json.encode({
            'entries': {
              _ymd(j): [_premium(jour: j).toJson()],
            }
          }),
        };
      }
      final ancien = <String, dynamic>{
        'appName': 'Pronostic Hippique', // sinon l'import est rejeté (fichier incompatible)
        'version': '9.0',
        'dateExport': DateTime.now().toIso8601String(),
        'ia': {
          ...ia,
          // Les deux mois doivent cohabiter : reconstruire l'entrée complète.
          _kPremiumKey: {
            'type': 'String',
            'value': json.encode({
              'entries': {
                for (final j in jours)
                  _ymd(j): [_premium(jour: j).toJson()],
              }
            }),
          },
        },
        'paris': <String, dynamic>{},
        'alertes': <String, dynamic>{},
        'profil': <String, dynamic>{},
      };

      final store = _installerStore();
      await IaMemoryService.instance.recharger();
      await importer(ancien);
      await _redemarrer(store);

      for (final j in jours) {
        expect(
            IaMemoryService.instance.premiumsPourDate(j.year, j.month, j.day).length,
            1,
            reason: '${_ymd(j)} restauré depuis une sauvegarde v9.0');
      }
    });

    test('B-3 — compatibilité du format PLAT {date: [...]}', () async {
      // resetPremiumPourDate gère explicitement un format plat historique.
      // On vérifie que la lecture le supporte aussi, donc qu'aucune étoile
      // ancienne au format plat n'est perdue au chargement.
      final j = _ilYA(200);
      final store = _installerStore(data: <String, Object>{
        'flutter.$_kPremiumKey': json.encode({
          _ymd(j): [_premium(jour: j).toJson()],
        }),
      });
      await IaMemoryService.instance.recharger();

      // Le parseur ne lit que 'entries' : un format plat donne 0 entrée,
      // donc 0 étoile fantôme — jamais d'invention (règle absolue du projet).
      expect(
          IaMemoryService.instance.premiumsPourDate(j.year, j.month, j.day).length,
          0,
          reason: 'format plat non interprété : aucune étoile inventée');
      expect(store.brut(_kPremiumKey), isNotNull,
          reason: 'la donnée d\'origine reste sur le disque, non détruite');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  N — AUCUNE INVENTATION, AUCUNE DESTRUCTION COLLATÉRALE
  // ═══════════════════════════════════════════════════════════════════════

  group('N — Ni invention, ni destruction collatérale', () {
    test('N-1 — une entrée disparue n\'est jamais reconstituée', () async {
      // L'utilisateur a perdu l'étoile du 1er janvier (purgée avant E5).
      final perdu = _ilYA(300);
      final conserve = _ilYA(95);
      _installerStore(data: _stockageAvecHistoriqueAncien(jours: [conserve]));
      await IaMemoryService.instance.recharger();

      await IaMemoryService.instance
          .enregistrerPronosticsPremiumDuJour([_premium(jour: DateTime.now())]);

      expect(
          IaMemoryService.instance
              .premiumsPourDate(perdu.year, perdu.month, perdu.day)
              .length,
          0,
          reason: 'E5 ne reconstitue JAMAIS une entrée absente');
      expect(
          IaMemoryService.instance
              .premiumsPourDate(conserve.year, conserve.month, conserve.day)
              .length,
          1,
          reason: 'mais l\'entrée encore présente est préservée');
    });

    test('N-2 — les poids et seuils ne sont pas touchés par E5', () async {
      _installerStore(data: _stockageAvecHistoriqueAncien(jours: [_ilYA(400)]));
      await IaMemoryService.instance.recharger();
      final poidsAvant =
          json.encode(IaMemoryService.instance.poids.toJson());
      final seuilsAvant =
          json.encode(IaMemoryService.instance.seuilsConfiance.toJson());

      await IaMemoryService.instance
          .enregistrerPronosticsPremiumDuJour([_premium(jour: DateTime.now())]);

      expect(json.encode(IaMemoryService.instance.poids.toJson()),
          poidsAvant,
          reason: 'les poids ne doivent pas bouger');
      expect(json.encode(IaMemoryService.instance.seuilsConfiance.toJson()),
          seuilsAvant,
          reason: 'les seuils ne doivent pas bouger');
    });

    test('N-3 — la mémoire de travail (600) n\'est pas alimentée par E5',
        () async {
      final store =
          _installerStore(data: _stockageAvecHistoriqueAncien(jours: [_ilYA(730)]));
      await IaMemoryService.instance.recharger();
      final nbAvant = IaMemoryService.instance.pronostics.length;

      await IaMemoryService.instance
          .enregistrerPronosticsPremiumDuJour([_premium(jour: DateTime.now())]);

      expect(IaMemoryService.instance.pronostics.length, nbAvant,
          reason: 'aucun pronostic créé par l\'enregistrement premium');
      expect(store.brut(_kPremiumKey), isNotNull);
    });

    test('N-4 — le reset manuel d\'une date reste opérant (non régressé)',
        () async {
      final j = _ilYA(365);
      final garde = _ilYA(730);
      _installerStore(data: _stockageAvecHistoriqueAncien(jours: [j, garde]));
      await IaMemoryService.instance.recharger();
      expect(
          IaMemoryService.instance.premiumsPourDate(j.year, j.month, j.day).length,
          1);

      await IaMemoryService.instance.resetPremiumPourDate(j);

      expect(
          IaMemoryService.instance.premiumsPourDate(j.year, j.month, j.day).length,
          0,
          reason: 'le reset ciblé volontaire fonctionne toujours');
      expect(
          IaMemoryService.instance
              .premiumsPourDate(garde.year, garde.month, garde.day)
              .length,
          1,
          reason: 'le reset ciblé ne touche pas les autres dates');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S — SÉRIES PREMIUM : BORNE INCHANGÉE (consigne 2)
  // ═══════════════════════════════════════════════════════════════════════

  group('S — calculerStreakPremium : borne et règles inchangées', () {
    test('S-1 — série de 130 jours : conservée, et plafonnée par la borne de 90',
        () async {
      // ★ A-3 (Option E′) — HISTORIQUE DÉJÀ RÉSOLU, semé puis CHARGÉ.
      //
      // AVANT A-3, ce test construisait les 130 pronostics par une boucle
      // `enregistrerPronostic()` + `enregistrerResultat()`. Ce chemin ne
      // fonctionnait QUE parce que `datePronostic` valait `DateTime.now()` :
      // depuis A-3, la date vient de la course, et le pronostic J−i (i > 90)
      // était purgé par M1 **avant** sa résolution, dans la `_save()` appelée
      // par `enregistrerResultat()`. 91 survivants sur 130.
      //
      // Le semis ci-dessous décrit ce qui existe réellement sur un appareil
      // utilisé depuis 130 jours : 130 pronostics RÉSOLUS, datés de leur
      // JOUR DE COURSE, persistés dans `ia_pronostics_v2`. Il passe par le
      // chargement normal (`recharger()` → `_load()`), sans forcer aucune
      // structure interne, et SANS toucher M1.
      //
      // 130 jours consécutifs gagnants — les numéros premium [3,7,1,5,2]
      // correspondent exactement à l'arrivée réelle déclarée.
      final jours = List.generate(130, (i) => _ilYA(i));

      final entries = <String, dynamic>{};
      final pronosticsSemes = <String>[];
      for (var i = 0; i < jours.length; i++) {
        // Entrée premium du jour, telle que produite par les widgets.
        entries[_ymd(jours[i])] = [
          _premium(jour: jours[i], r: 1, c: i + 1).toJson(),
        ];
        // Pronostic correspondant, DÉJÀ RÉSOLU, même courseKey.
        pronosticsSemes.add(json.encode(_pronosticResoluHistorique(
          jour: jours[i],
          r: 1,
          c: i + 1,
        )));
      }
      final store = _installerStore(data: <String, Object>{
        'flutter.$_kPremiumKey': json.encode({'entries': entries}),
        'flutter.$_kPronosticsKey': pronosticsSemes,
      });
      await IaMemoryService.instance.recharger();

      // ── GARDE-FOU : les 130 pronostics sont réellement chargés et résolus ─
      final nbGagnants = IaMemoryService.instance.pronostics
          .where((p) => p.resultatsReels)
          .length;
      expect(nbGagnants, 130,
          reason: 'garde-fou : les 130 courses doivent être résolues');

      await _redemarrer(store);

      // La série est bornée par _premiumHistoriqueMaxJours — valeur et usage
      // INCHANGÉS par E5.
      final streak = IaMemoryService.instance.calculerStreakPremium(
        sourceWidget: 'conseilJour',
        dateReference: jours.first,
      );
      expect(streak.jours, 90,
          reason: 'la borne de balayage _premiumHistoriqueMaxJours = 90 '
              'reste strictement inchangée par E5');

      // Ce qui change avec E5 : les 130 entrées premium sont TOUTES encore là,
      // y compris les 40 au-delà de la borne. La borne ne détruit rien.
      final svc = IaMemoryService.instance;
      for (final j in jours) {
        expect(svc.premiumsPourDate(j.year, j.month, j.day).length, 1,
            reason: '${_ymd(j)} conservé malgré la borne de série');
      }
      final brut = json.decode(store.brut(_kPremiumKey) as String)
          as Map<String, dynamic>;
      expect((brut['entries'] as Map<String, dynamic>).length, 130,
          reason: '130 entrées sur le disque : la borne de série ne purge pas');
    });
  });
}
