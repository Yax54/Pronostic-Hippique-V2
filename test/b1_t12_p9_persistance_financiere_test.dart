// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 1/3 — OPÉRATION 9 : PERSISTANCE FINANCIÈRE DE BOUT EN BOUT
//
//  OBJET — « Vérifier la conservation durable des gains officiels, des
//           remboursements, des gains manuels, des décisions financières, des
//           montants avant décision et des autres données financières
//           nécessaires à la restitution exacte du ticket. Vérifier leur
//           conservation après sauvegarde, rechargement des données, redémarrage
//           simulé, export, import et restauration. Les rapports PMU doivent
//           être indisponibles pendant la vérification. »
//
//  ── CE QUI N'EST PAS REFAIT ICI, ET POURQUOI ──────────────────────────────
//  Les tests existants couvrent DÉJÀ, mesurément :
//    • `b1_t12_p1_montant_officiel_test.dart` R3 et R4 : écriture du gain
//      officiel ET du remboursement, en MÉMOIRE et SUR DISQUE, par le chemin
//      réel `appliquerVerdictGainPredictionSecurise(..., enregistrerMontantOfficiel: true)` ;
//    • `.../K9` (b1_t12_lot2c_ecriture_securisee_test.dart:1263) : redémarrage
//      des 7 champs du verdict + des 4 champs financiers ;
//    • `b1_champs_gain_persistes_test.dart` : forme JSON et aller-retour.
//
//  ── LES DEUX LACUNES RÉELLES, MESURÉES, COMBLÉES ICI ──────────────────────
//    P1. `remboursementPmu` n'apparaissait dans AUCUN test de persistance :
//        `grep -rln "remboursementPmu" test/` rendait exactement deux fichiers,
//        `b1_t12_p1_montant_officiel_test.dart` (écriture) et le test de
//        comparaison au centime — aucun test d'EXPORT / IMPORT / RESTAURATION.
//    P2. AUCUN test ne couvrait le cycle EXPORT → IMPORT → RESTAURATION des
//        champs financiers. La restauration est prouvée ici par la vraie API
//        publique (`exporterDonnees` puis `importerDepuisFichier`), avec
//        `SharedPreferences` réellement remis à zéro entre les deux, et avec un
//        réseau PMU COUPÉ.
//
//  ⚠️ AUCUNE SIMULATION DE PERSISTANCE N'EST PRÉSENTÉE COMME UN REDÉMARRAGE :
//     le redémarrage est simulé par `SharedPreferences.resetStatic()` + une
//     NOUVELLE instance de `PmuProvider`, exactement comme K9 — le disque reste
//     le faux support, ce qui est le seul moyen de relire ce qui a été écrit.
//     La restauration, elle, passe par le VRAI `BackupService`, qui écrit dans
//     un vrai `SharedPreferences` adossé au même faux support.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show Client;
import 'package:http/testing.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/decision_gain_pmu.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/providers/pmu_provider.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart'
    show EtatGain, EtatTirelire, RapportAttribue, RapportPublie;
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show VarianteRapport;

// ═══════════════════════════ Faux de plateforme ════════════════════════════

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

// ═══════════════════════════ Faux support de stockage ══════════════════════

class _Store extends SharedPreferencesStorePlatform {
  _Store({Map<String, Object>? data})
      : _data = Map<String, Object>.from(data ?? <String, Object>{});

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
    final r = Map<String, Object>.from(_data);
    r.removeWhere((k, _) =>
        !k.startsWith(f.prefix) ||
        (f.allowList != null && !f.allowList!.contains(k)));
    return r;
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

  // ── Lecture brute, sans passer par SharedPreferences ────────────────────
  List<String> predictionsBrutes() {
    final v = _data['flutter.user_predictions_v2'];
    if (v is List) return v.cast<String>();
    return const <String>[];
  }

  Map<String, dynamic>? predictionParId(String id) {
    for (final s in predictionsBrutes()) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      if (m['id'] == id) return m;
    }
    return null;
  }

  List<String> trackedBrutes() {
    final v = _data['flutter.tracked_courses_v1'];
    if (v is List) return v.cast<String>();
    return const <String>[];
  }

  Map<String, Object> get tout => Map<String, Object>.unmodifiable(_data);
}

// ═══════════════════════════ Outils de montage ═════════════════════════════

/// Réseau COUPÉ — c'est l'exigence explicite de l'opération 9 :
/// « Les rapports PMU doivent être indisponibles pendant la vérification de la
/// restitution des données déjà enregistrées. »
///
/// ⚠️ `http.runWithClient` attend une FABRIQUE (`Client Function()`), et non
///    une instance : passer `_clientCoupe()` directement ne compile pas.
///    Vérifié sur la signature de `package:http` 1.5.0.
Client _fabriqueCoupee() => MockClient((http.Request r) async {
      throw const SocketException('réseau coupé — exigence opération 9');
    });

Future<T> _sansReseau<T>(Future<T> Function() action) =>
    http.runWithClient(action, _fabriqueCoupee);

/// Rapport publié réaliste (R1C6 du 15/11/2026).
RapportPublie _pub({
  String code = 'E_SIMPLE_GAGNANT',
  String libelle = 'e-Simple Gagnant',
  VarianteRapport variante = VarianteRapport.sansVariante,
  String combinaison = '9',
  double pourUnEuro = 7.50,
  int rang = 1,
}) =>
    RapportPublie(
      codePmu: code,
      libelle: libelle,
      variante: variante,
      combinaison: combinaison,
      pourUnEuro: pourUnEuro,
      rang: rang,
      miseBaseCentimes: 100,
    );

RapportAttribue _attribue({double mise = 10.0}) =>
    RapportAttribue.calculer(rapport: _pub(), miseAppliquee: mise);

/// Ticket portant TOUS les champs financiers, y compris le remboursement.
UserPrediction _ticket({
  String id = 'p1',
  double? montantGainManuel,
  double? montantOfficielPmu,
  double? remboursementPmu,
  DecisionGainPmu? decision,
  double? manuelAvantDecision,
  EtatGain? etatGain,
  List<RapportAttribue>? rapportsAttribues,
  EtatTirelire? etatTirelire,
  double? dividendeGagnant,
  double? dividendePlace,
  int? miseBaseCentimes,
  double mise = 10.0,
  double? miseGagnant,
  double? misePlace,
  String typePari = 'Simple Gagnant',
}) =>
    UserPrediction(
      id: id,
      dateStr: '15112026',
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'Prix de Test',
      hippodrome: 'Vincennes',
      numeroCheval: 9,
      nomCheval: 'Cheval 9',
      cote: 5.0,
      typePari: typePari,
      createdAt: DateTime(2026, 11, 15, 14, 30),
      numerosJoues: const <int>[9],
      codePmuOfficiel: 'E_SIMPLE_GAGNANT',
      montantMise: mise,
      miseGagnant: miseGagnant,
      misePlace: misePlace,
      montantGainManuel: montantGainManuel,
      montantOfficielPmu: montantOfficielPmu,
      remboursementPmu: remboursementPmu,
      decisionGainPmu: decision,
      montantGainManuelAvantDecision: manuelAvantDecision,
      etatGain: etatGain,
      rapportsAttribues: rapportsAttribues,
      etatTirelire: etatTirelire,
      dividendeGagnant: dividendeGagnant,
      dividendePlace: dividendePlace,
      miseBaseCentimesUtilisee: miseBaseCentimes,
    );

/// Installe le support et charge le provider dessus.
Future<PmuProvider> _providerAvec(
    _Store store, List<UserPrediction> preds) async {
  await store.setValue('StringList', 'flutter.user_predictions_v2',
      preds.map((p) => jsonEncode(p.toJson())).toList());
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  final pmu = PmuProvider();
  await pmu.sauvegardeTerminee();
  await pmu.reloadPredictions();
  await pmu.sauvegardeTerminee();
  return pmu;
}

UserPrediction _enMemoire(PmuProvider pmu, String id) =>
    pmu.predictions.firstWhere((p) => p.id == id);

/// Redémarrage simulé : NOUVELLE instance sur le MÊME disque.
Future<PmuProvider> _redemarrer(_Store store) async {
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  final pmu = PmuProvider();
  await pmu.sauvegardeTerminee();
  await pmu.reloadPredictions();
  await pmu.sauvegardeTerminee();
  return pmu;
}

late Directory _tmpDir;

void main() {
  setUpAll(() {
    _tmpDir = Directory.systemTemp.createTempSync('b1_t12_p9_');
    PathProviderPlatform.instance = _FakePathProvider(_tmpDir.path);
  });

  tearDownAll(() {
    if (_tmpDir.existsSync()) _tmpDir.deleteSync(recursive: true);
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  P9/A — LES CINQ CHAMPS FINANCIERS SURVIVENT À UN REDÉMARRAGE
  //
  //  ⚠️ K9 couvre les 7 champs du verdict + 4 champs financiers, mais PAS
  //     `remboursementPmu`. C'est la lacune P1.
  // ═════════════════════════════════════════════════════════════════════════
  group('P9/A — redémarrage : remboursement inclus', () {
    test('P9/A.1 les SIX champs financiers survivent à un redémarrage, '
        '`remboursementPmu` compris', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(
            montantGainManuel: 40.0,
            montantOfficielPmu: 75.0,
            remboursementPmu: 10.0,
            decision: DecisionGainPmu.accepte,
            manuelAvantDecision: 40.0,
            etatGain: EtatGain.attribue,
            rapportsAttribues: <RapportAttribue>[_attribue()],
            etatTirelire: EtatTirelire.sansObjet,
            dividendeGagnant: 7.50,
            miseBaseCentimes: 100,
            miseGagnant: 10.0,
            misePlace: 10.0,
          ),
        ]);
        await pmu.sauvegardeTerminee();

        // Redémarrage : nouvelle instance, même disque.
        final pmu2 = await _redemarrer(store);
        final m = _enMemoire(pmu2, 'p1');

        expect(m.montantGainManuel, 40.0);
        expect(m.montantOfficielPmu, 75.0);
        expect(m.remboursementPmu, 10.0,
            reason: '★ LACUNE P1 : le remboursement doit survivre au '
                'redémarrage, sinon le résultat financier serait faux');
        expect(m.decisionGainPmu, DecisionGainPmu.accepte);
        expect(m.montantGainManuelAvantDecision, 40.0);
        expect(m.etatGain, EtatGain.attribue);
        // Contrôle de cohérence financière APRÈS redémarrage.
        expect(m.totalReverse, 85.0, reason: '75 + 10');
        expect(m.miseTotaleEngagee, 20.0, reason: '10 + 10');
        expect(m.resultatNet, 65.0, reason: '85 − 20');
      });
    });

    test('P9/A.2 un remboursement établi à `0.0` survit et reste DISTINCT '
        'd\'une absence', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(montantOfficielPmu: 0.0, remboursementPmu: 0.0,
              etatGain: EtatGain.perdu),
        ]);
        await pmu.sauvegardeTerminee();

        // Le disque porte la clé, avec 0.0 — pas une absence.
        final disque = store.predictionParId('p1')!;
        expect(disque.containsKey('remboursementPmu'), isTrue,
            reason: '`0.0` est une information officielle : elle s\'écrit');
        expect(disque['remboursementPmu'], 0.0);

        final pmu2 = await _redemarrer(store);
        final m = _enMemoire(pmu2, 'p1');
        expect(m.remboursementPmu, 0.0);
        expect(m.remboursementPmu, isNotNull,
            reason: 'un remboursement officiel NUL n\'est pas une absence');
        expect(m.aUnRemboursementEtabli, isFalse,
            reason: 'mais il n\'est pas « établi et positif » pour autant');
      });
    });

    test('P9/A.3 un ticket SANS remboursement reste `null` après redémarrage '
        '— l\'absence n\'est jamais convertie en 0 €', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(montantOfficielPmu: 75.0, etatGain: EtatGain.attribue),
        ]);
        await pmu.sauvegardeTerminee();

        final disque = store.predictionParId('p1')!;
        expect(disque.containsKey('remboursementPmu'), isFalse,
            reason: 'aucune clé ⇒ aucun remboursement établi');

        final pmu2 = await _redemarrer(store);
        final m = _enMemoire(pmu2, 'p1');
        expect(m.remboursementPmu, isNull,
            reason: 'l\'absence ne doit JAMAIS devenir un 0 € officiel');
        expect(m.remboursementRetenu, isNull);
        // Le gain officiel, lui, est bien là.
        expect(m.montantOfficielPmu, 75.0);
        expect(m.totalReverse, 75.0);
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  P9/B — EXPORT → IMPORT → RESTAURATION, réseau COUPÉ
  //
  //  ★ LACUNE P2 : aucun test n'existait. La restauration passe par la VRAIE
  //    API publique du BackupService.
  // ═════════════════════════════════════════════════════════════════════════
  group('P9/B — export / import / restauration, réseau PMU coupé', () {
    test('P9/B.1 les six champs financiers survivent à l\'export puis à la '
        'restauration, sans aucun accès PMU', () async {
      await _sansReseau(() async {
        // ── Phase 1 : l'appareil porte les données financières ─────────────
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(
            montantGainManuel: 40.0,
            montantOfficielPmu: 75.0,
            remboursementPmu: 10.0,
            decision: DecisionGainPmu.accepte,
            manuelAvantDecision: 40.0,
            etatGain: EtatGain.attribue,
            rapportsAttribues: <RapportAttribue>[_attribue()],
            etatTirelire: EtatTirelire.sansObjet,
            dividendeGagnant: 7.50,
            miseBaseCentimes: 100,
            miseGagnant: 10.0,
            misePlace: 10.0,
          ),
        ]);
        await pmu.sauvegardeTerminee();

        // Témoin de non-vacuité AVANT export.
        expect(_enMemoire(pmu, 'p1').remboursementPmu, 10.0);

        // ── Phase 2 : EXPORT réel ───────────────────────────────────────────
        final export = await BackupService.instance.exporterDonnees();
        expect(export.succes, isTrue,
            reason: 'export doit réussir (${export.erreur ?? "sans erreur"})');
        final fichier = File(export.filePath!);
        expect(await fichier.exists(), isTrue);
        final contenu =
            json.decode(await fichier.readAsString()) as Map<String, dynamic>;
        expect(contenu['appName'], 'Pronostic Hippique');

        // Le remboursement est bien DANS le fichier exporté (lecture directe).
        final paris = contenu['paris'] as Map<String, dynamic>;
        final envelopes = paris['user_predictions_v2'] as Map<String, dynamic>;
        final liste = (envelopes['value'] as List).cast<String>();
        final dansFichier =
            liste.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
        final p1Fichier = dansFichier.firstWhere((m) => m['id'] == 'p1');
        expect(p1Fichier['montantOfficielPmu'], 75.0);
        expect(p1Fichier['remboursementPmu'], 10.0,
            reason: '★ le remboursement doit voyager dans le fichier');
        expect(p1Fichier['montantGainManuel'], 40.0);
        expect(p1Fichier['decisionGainPmu'], 'accepte');
        expect(p1Fichier['montantGainManuelAvantDecision'], 40.0);

        // ── Phase 3 : l'appareil est VIDÉ — plus aucune donnée locale ──────
        final storeVide = _Store();
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = storeVide;
        final vide = await SharedPreferences.getInstance();
        await vide.reload();
        expect(vide.getStringList('user_predictions_v2'), isNull,
            reason: 'témoin : l\'appareil doit être réellement vide');

        // ── Phase 4 : RESTAURATION par la vraie API publique ───────────────
        // ⚠️ Le réseau est COUPÉ par `_sansReseau` : si la restauration
        //    dépendait d'un accès PMU, ce test échouerait.
        FilePicker.platform = _FakeFilePicker(FilePickerResult([
          PlatformFile(
            name: export.fileName!,
            size: export.tailleOctets,
            bytes: Uint8List.fromList(await fichier.readAsBytes()),
          ),
        ]));

        final import = await BackupService.instance.importerDepuisFichier();
        expect(import.succes, isTrue,
            reason: 'restauration doit réussir (${import.erreur ?? "sans erreur"})');
        expect(import.nbParis, 1,
            reason: 'la sauvegarde contient exactement un pari');

        // ── Phase 5 : relecture par le PROVIDER, toujours sans réseau ──────
        final pmu2 = await _redemarrer(storeVide);
        final m = _enMemoire(pmu2, 'p1');

        expect(m.montantOfficielPmu, 75.0, reason: 'gain officiel restauré');
        expect(m.remboursementPmu, 10.0, reason: 'remboursement restauré');
        expect(m.montantGainManuel, 40.0, reason: 'gain manuel restauré');
        expect(m.decisionGainPmu, DecisionGainPmu.accepte,
            reason: 'décision restaurée');
        expect(m.montantGainManuelAvantDecision, 40.0,
            reason: 'montant avant décision restauré');
        // Les champs du verdict aussi.
        expect(m.etatGain, EtatGain.attribue);
        expect(m.dividendeGagnant, 7.50);
        expect(m.miseBaseCentimesUtilisee, 100);
        // Et les montants DÉRIVÉS sont exacts après restauration.
        expect(m.totalReverse, 85.0, reason: '75 + 10');
        expect(m.resultatNet, 65.0, reason: '85 − 20');
      });
    });

    test('P9/B.2 un remboursement intégral (20 € sur 20 €) restauré donne un '
        'net de 0 €, jamais −20 € ni +20 €', () async {
      await _sansReseau(() async {
        final store = _Store();
        final pmu = await _providerAvec(store, [
          _ticket(
            typePari: 'Gagnant+Placé',
            // Aucun gain : 20 € rendus, c'est tout.
            montantOfficielPmu: null,
            remboursementPmu: 20.0,
            etatGain: EtatGain.rembourse,
            miseGagnant: 10.0,
            misePlace: 10.0,
          ),
        ]);
        await pmu.sauvegardeTerminee();

        final export = await BackupService.instance.exporterDonnees();
        expect(export.succes, isTrue);
        final fichier = File(export.filePath!);

        final storeVide = _Store();
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = storeVide;

        FilePicker.platform = _FakeFilePicker(FilePickerResult([
          PlatformFile(
            name: export.fileName!,
            size: export.tailleOctets,
            bytes: Uint8List.fromList(await fichier.readAsBytes()),
          ),
        ]));
        expect((await BackupService.instance.importerDepuisFichier()).succes,
            isTrue);

        final pmu2 = await _redemarrer(storeVide);
        final m = _enMemoire(pmu2, 'p1');

        expect(m.remboursementPmu, 20.0);
        expect(m.montantOfficielPmu, isNull,
            reason: 'un remboursement n\'est JAMAIS un gain');
        expect(m.miseTotaleEngagee, 20.0);
        expect(m.totalReverse, 20.0);
        expect(m.resultatNet, 0.0,
            reason: 'un remboursement intégral n\'est ni une perte ni un gain');
      });
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  P9/C — tracked_courses_v1 : durée de vie normale, purge 24 h, et
  //         NON-PERTE des données durables de user_predictions_v2.
  //
  //  ⚠️ Le suivi temporaire NE DOIT PAS devenir un stockage permanent : la
  //     purge est donc VÉRIFIÉE, pas contournée.
  // ═════════════════════════════════════════════════════════════════════════
  group('P9/C — tracked_courses_v1', () {
    TrackedCourse suivi({
      required String storageKey,
      required DateTime heureDepart,
      double? remboursementPmu,
      double? montantGainManuel,
    }) =>
        TrackedCourse(
          numReunion: 1,
          numCourse: 6,
          nomCourse: 'Prix de Test',
          hippodrome: 'Vincennes',
          heureDepart: heureDepart,
          storageKey: storageKey,
          nomCheval: 'Cheval 9',
          numeroCheval: 9,
          miseEngagee: 20.0,
          typePari: 'Gagnant+Placé',
          numerosJoues: const <int>[9],
          codePmuOfficiel: 'E_SIMPLE_GAGNANT',
          etatGain: EtatGain.attribue,
          rapportsAttribues: <RapportAttribue>[_attribue()],
          montantGainManuel: montantGainManuel,
          remboursementPmu: remboursementPmu,
        );

    test('P9/C.1 une course suivie RÉCENTE conserve ses champs financiers '
        'après rechargement', () async {
      final store = _Store();
      final recent = DateTime.now().subtract(const Duration(hours: 1));
      final cle = 'R1C6_'
          '${recent.day.toString().padLeft(2, '0')}'
          '${recent.month.toString().padLeft(2, '0')}'
          '${recent.year}';

      await store.setValue(
        'StringList',
        'flutter.tracked_courses_v1',
        <String>[
          jsonEncode(suivi(
            storageKey: cle,
            heureDepart: recent,
            remboursementPmu: 10.0,
            montantGainManuel: 12.0,
          ).toJson()),
        ],
      );

      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = store;
      await AlertService.instance.recharger();

      final suivis = AlertService.instance.trackedCourses;
      expect(suivis.containsKey(cle), isTrue,
          reason: 'une course de moins de 24 h ne doit PAS être purgée');
      final tc = suivis[cle]!;
      expect(tc.remboursementPmu, 10.0,
          reason: '★ le remboursement survit à la durée de vie normale');
      expect(tc.montantGainManuel, 12.0);
      expect(tc.etatGain, EtatGain.attribue);
      expect(tc.rapportsAttribues?.single.montantRetour, 75.0);
    });

    test('P9/C.2 la purge à 24 heures est CONSERVÉE : une course plus ancienne '
        'disparaît, avec ses champs financiers', () async {
      final store = _Store();
      final ancienne = DateTime.now().subtract(const Duration(hours: 30));
      final cle = 'R1C6_'
          '${ancienne.day.toString().padLeft(2, '0')}'
          '${ancienne.month.toString().padLeft(2, '0')}'
          '${ancienne.year}';

      await store.setValue(
        'StringList',
        'flutter.tracked_courses_v1',
        <String>[
          jsonEncode(suivi(
            storageKey: cle,
            heureDepart: ancienne,
            remboursementPmu: 10.0,
          ).toJson()),
        ],
      );

      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = store;
      await AlertService.instance.recharger();

      expect(AlertService.instance.trackedCourses.containsKey(cle), isFalse,
          reason: 'la purge > 24 h doit rester en vigueur : le suivi '
              'temporaire n\'est PAS un stockage permanent');
    });

    test('★ P9/C.3 la purge de tracked_courses_v1 n\'efface AUCUNE donnée '
        'financière durable de user_predictions_v2', () async {
      // C'est l'exigence explicite : « Démontrer que cette purge n'efface pas
      // les données financières durables de user_predictions_v2. »
      final store = _Store();
      final ancienne = DateTime.now().subtract(const Duration(hours: 30));
      final cle = 'R1C6_'
          '${ancienne.day.toString().padLeft(2, '0')}'
          '${ancienne.month.toString().padLeft(2, '0')}'
          '${ancienne.year}';

      // Les deux structures coexistent sur le MÊME support.
      final pmu = await _providerAvec(store, [
        _ticket(
          montantOfficielPmu: 75.0,
          remboursementPmu: 10.0,
          montantGainManuel: 40.0,
          decision: DecisionGainPmu.accepte,
          manuelAvantDecision: 40.0,
          etatGain: EtatGain.attribue,
          miseGagnant: 10.0,
          misePlace: 10.0,
        ),
      ]);
      await pmu.sauvegardeTerminee();
      await store.setValue(
        'StringList',
        'flutter.tracked_courses_v1',
        <String>[
          jsonEncode(suivi(storageKey: cle, heureDepart: ancienne).toJson()),
        ],
      );

      // La purge s'exécute.
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = store;
      await AlertService.instance.recharger();
      expect(AlertService.instance.trackedCourses.containsKey(cle), isFalse,
          reason: 'témoin : la purge a bien eu lieu');

      // Le durable est INTACT — lu directement sur le disque.
      final d = store.predictionParId('p1')!;
      expect(d['montantOfficielPmu'], 75.0);
      expect(d['remboursementPmu'], 10.0);
      expect(d['montantGainManuel'], 40.0);
      expect(d['decisionGainPmu'], 'accepte');
      expect(d['montantGainManuelAvantDecision'], 40.0);

      // Et après redémarrage du provider, les valeurs sont toujours là.
      final pmu2 = await _redemarrer(store);
      final m = _enMemoire(pmu2, 'p1');
      expect(m.montantOfficielPmu, 75.0);
      expect(m.remboursementPmu, 10.0);
      expect(m.totalReverse, 85.0);
      expect(m.resultatNet, 65.0);
    });
  });
}
