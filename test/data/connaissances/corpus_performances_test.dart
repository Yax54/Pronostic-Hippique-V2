/// Corpus local de performances : preuves MESURÉES sur moteur SQLite réel.
///
/// Consigne du présent tour :
/// > « Réalise les tests nécessaires du `CorpusPerformancesService`, puis
/// > raccorde immédiatement cette couche aux producteurs et consommateurs
/// > réels. »
///
/// ═══════════════════════════════════════════════════════════════════════════
///  CE QUI EST PROUVÉ ICI, ET CE QUI NE L'EST PAS
///
///  Prouvé : le corpus écrit, relit, ne duplique pas, accepte une correction
///  officielle, distingue « absent » de « zéro », et conserve distance/terrain.
///  Les mesures sont prises sur le moteur SQLite RÉEL via FFI (sqflite_common_ffi) :
///  même moteur, hôte différent.
///
///  NON prouvé ici : le comportement sur un appareil Android réel. C'est une
///  limite de mesure, pas une affirmation inverse.
/// ═══════════════════════════════════════════════════════════════════════════
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/depot_sqlite.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/pont_elo.dart';
import 'package:pronostic_hippique/data/connaissances/_core/depot.dart';
import 'package:pronostic_hippique/data/connaissances/_services/corpus_performances.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Une course passée du PMU, telle que le décodeur la produit.
PerformancePmu _pmu({
  required String nom,
  required String date,
  String hippodrome = 'PORNICHET',
  String discipline = 'PLAT',
  int? distance,
  int? place,
  String etatTerrain = 'Bon',
}) =>
    PerformancePmu(
      nomCheval: nom,
      dateIso: date,
      hippodrome: hippodrome,
      discipline: discipline,
      distance: distance,
      place: place,
      reductionKm: null,
      gains: null,
      chargeBrute: '{"source":"test"}',
      etatTerrain: etatTerrain,
    );

void main() {
  late SqfliteFfiFixture fixture;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    fixture = await SqfliteFfiFixture.creer();
  });

  tearDown(() async {
    await fixture.fermer();
  });

  group('Écriture et lecture réelles', () {
    test('les performances écrites sont relues à l\'identique', () async {
      final service = CorpusPerformancesService.instance;
      final crees = await service.enregistrer(
        dateStr: '13112026',
        numR: 6,
        numC: 6,
        source: 'pmu_performances_detaillees',
        parNumero: <String, List<PerformancePmu>>{
          '5': <PerformancePmu>[
            _pmu(
              nom: 'VIKTOR RAPIDE',
              date: '2026-11-14',
              distance: 1700,
              place: 3,
            ),
            _pmu(
              nom: 'VIKTOR RAPIDE',
              date: '2026-10-02',
              distance: 1600,
              place: 1,
            ),
          ],
        },
      );

      expect(crees, 2, reason: 'deux participations distinctes');

      final lues = await service.charger(nomBrut: 'VIKTOR RAPIDE');
      expect(lues.length, 2);

      // Tri décroissant sur la date : la plus récente d'abord.
      expect(lues.first.datePerf, '2026-11-14');
      expect(lues.first.place, 3);
      expect(lues.first.distanceMetres, 1700,
          reason: 'la distance doit survivre à l\'aller-retour SQLite');
      expect(lues.first.etatTerrain, 'Bon');
      expect(lues.last.place, 1);

      // ignore: avoid_print
      print('[MESURE] corpus : 2 performances écrites puis relues, '
          'distance=${lues.first.distanceMetres} m, '
          'terrain="${lues.first.etatTerrain}", place=${lues.first.place}');
    });

    test('« non publié » reste null et n\'est jamais transformé en 0', () async {
      final service = CorpusPerformancesService.instance;
      await service.enregistrer(
        dateStr: '13112026',
        numR: 1,
        numC: 1,
        source: 'pmu_performances_detaillees',
        parNumero: <String, List<PerformancePmu>>{
          '1': <PerformancePmu>[
            _pmu(
              nom: 'SANS PLACE',
              date: '2026-09-01',
              distance: 0, // le PMU n'a rien publié
              place: null,
              etatTerrain: '',
            ),
          ],
        },
      );

      final lues = await service.charger(nomBrut: 'SANS PLACE');
      expect(lues.length, 1);
      expect(lues.first.place, isNull,
          reason: '§9 : absent ≠ 0 (0 signifierait « dernier »)');
      expect(lues.first.distanceMetres, isNull,
          reason: 'distance 0 envoyée par le PMU = non publiée');
      expect(lues.first.etatTerrain, '');

      // ignore: avoid_print
      print('[MESURE] valeurs absentes conservées absentes : '
          'place=${lues.first.place}, distance=${lues.first.distanceMetres}');
    });
  });

  group('Idempotence et correction officielle', () {
    test('réingérer la même course n\'écrit AUCUNE ligne nouvelle', () async {
      final service = CorpusPerformancesService.instance;
      final lot = <String, List<PerformancePmu>>{
        '5': <PerformancePmu>[
          _pmu(nom: 'READY CASH', date: '2026-05-01', distance: 2000),
          _pmu(nom: 'READY CASH', date: '2026-06-01', distance: 2400),
        ],
      };

      final premier = await service.enregistrer(
        dateStr: '13112026',
        numR: 2,
        numC: 3,
        source: 'pmu_performances_detaillees',
        parNumero: lot,
      );
      expect(premier, 2);

      final avant = await service.compter();

      final rejeu = await service.enregistrer(
        dateStr: '13112026',
        numR: 2,
        numC: 3,
        source: 'pmu_performances_detaillees',
        parNumero: lot,
      );

      final apres = await service.compter();
      expect(rejeu, 0, reason: 'un rejeu ne crée aucune connaissance');
      expect(apres, avant, reason: 'la base ne doit pas grossir');

      // ignore: avoid_print
      print('[MESURE] idempotence : 1er passage=$premier nouvelle(s), '
          'rejeu=$rejeu, total $avant → $apres');
    });

    test(
      'IDEMPOTENCE SANS id_cheval NULLE (le piège SQLite NULL != NULL)',
      () async {
        // `id_cheval` est nullable dans le schéma. En SQLite, deux NULL ne sont
        // PAS égaux : la contrainte UNIQUE ne protégerait donc pas l'idempotence.
        // C'est la CLÉ PRIMAIRE `id` qui la porte. Ce test le prouve.
        final depot = fixture.depot;
        final p = PerformanceStockee(
          id: 'cle-fixe-sans-id-cheval',
          nomChevalBrut: 'ORPHELIN',
          source: 'pmu',
          datePerf: '2026-01-01',
          hippodrome: 'VINCENNES',
          place: 2,
        );

        await depot.insererPerformance(p);
        await depot.insererPerformance(p);

        final n = await depot.compterPerformances();
        expect(n, 1,
            reason: 'malgré id_cheval NULL, la clé primaire empêche le doublon');

        // ignore: avoid_print
        print('[MESURE] id_cheval=NULL : 2 insertions → $n ligne(s) '
            '(CLÉ PRIMAIRE, pas UNIQUE)');
      },
    );

    test(
      'une réponse PARTIELLE ne dégrade pas les champs déjà authentiques',
      () async {
        // DÉFAUT MESURÉ AVANT CORRECTION : `ConflictAlgorithm.replace` produisait
        // {place:1, gains:null, musique:null} — les gains et la musique déjà
        // connus étaient EFFACÉS par une republication qui ne les portait pas.
        final depot = fixture.depot;
        const idPerf = 'perf-partielle';
        await depot.insererPerformance(const PerformanceStockee(
          id: idPerf,
          idCheval: 'ch_p',
          nomChevalBrut: 'PARTIEL',
          source: 'pmu_performances_detaillees',
          datePerf: '2026-04-04',
          hippodrome: 'CHANTILLY',
          place: 5,
          gains: 12500.0,
          musique: '1p 3p 2p',
        ));

        // Republication PARTIELLE : le PMU ne renvoie que la place corrigée.
        await depot.insererPerformance(const PerformanceStockee(
          id: idPerf,
          idCheval: 'ch_p',
          nomChevalBrut: 'PARTIEL',
          source: 'pmu_performances_detaillees',
          datePerf: '2026-04-04',
          hippodrome: 'CHANTILLY',
          place: 1, // seule information publiée
        ));

        final lues = await depot.performancesDuCheval('ch_p');
        expect(lues.length, 1);
        expect(lues.first.place, 1, reason: 'la correction officielle prime');
        expect(lues.first.gains, 12500.0,
            reason: 'un champ non republié ne doit PAS être effacé');
        expect(lues.first.musique, '1p 3p 2p',
            reason: 'un champ non republié ne doit PAS être effacé');

        // ignore: avoid_print
        print('[MESURE] réponse partielle : place corrigée 5 → 1, '
            'gains=${lues.first.gains}, musique="${lues.first.musique}" '
            'CONSERVÉS');
      },
    );

    test(
      'la correction officielle laisse une TRACE des anciennes valeurs',
      () async {
        final depot = fixture.depot;
        const idPerf = 'perf-tracee';
        await depot.insererPerformance(const PerformanceStockee(
          id: idPerf,
          idCheval: 'ch_t',
          nomChevalBrut: 'TRACE',
          source: 'pmu_performances_detaillees',
          datePerf: '2026-02-02',
          hippodrome: 'CAGNES',
          place: 7,
        ));
        await depot.insererPerformance(const PerformanceStockee(
          id: idPerf,
          idCheval: 'ch_t',
          nomChevalBrut: 'TRACE',
          source: 'pmu_performances_detaillees',
          datePerf: '2026-02-02',
          hippodrome: 'CAGNES',
          place: 2,
        ));

        final journal = await depot.journalDeLOperation('performance_corrigee');
        expect(journal, isNotEmpty,
            reason: 'une correction doit être traçable, pas silencieuse');
        final detail = '${journal.first['detail']}';
        expect(detail, contains('"avant"'));
        expect(detail, contains('"apres"'));

        // ignore: avoid_print
        print('[MESURE] traçabilité : ${journal.length} entrée(s) de journal, '
            'detail=${detail.length} caractères');
      },
    );

    test(
      'un rejeu IDENTIQUE n\'écrit rien (détection du changement utile)',
      () async {
        final depot = fixture.depot;
        const p = PerformanceStockee(
          id: 'perf-identique',
          idCheval: 'ch_i',
          nomChevalBrut: 'IDENTIQUE',
          source: 'pmu_performances_detaillees',
          datePerf: '2026-01-01',
          hippodrome: 'PAU',
          place: 3,
          gains: 900.0,
        );
        final premiere = await depot.insererPerformance(p);
        final seconde = await depot.insererPerformance(p);
        expect(premiere, isTrue);
        expect(seconde, isFalse,
            reason: 'aucun changement utile ⇒ aucune écriture');

        // ignore: avoid_print
        print('[MESURE] changement utile : 1re écriture=$premiere, '
            'rejeu identique=$seconde (0 écriture)');
      },
    );

    test(
      'une CORRECTION OFFICIELLE écrase l\'ancienne place (ignore l\'aurait figée)',
      () async {
        final depot = fixture.depot;
        final base = PerformanceStockee(
          id: 'perf-corrigee',
          idCheval: 'ch_abc',
          nomChevalBrut: 'ENQUETE',
          source: 'pmu_performances_detaillees',
          datePerf: '2026-03-03',
          hippodrome: 'DEAUVILLE',
          place: 5,
        );
        await depot.insererPerformance(base);

        final corrigee = PerformanceStockee(
          id: 'perf-corrigee', // même participation
          idCheval: 'ch_abc',
          nomChevalBrut: 'ENQUETE',
          source: 'pmu_performances_detaillees',
          datePerf: '2026-03-03',
          hippodrome: 'DEAUVILLE',
          place: 1, // le PMU a corrigé après enquête
        );
        await depot.insererPerformance(corrigee);

        final lignes = await depot.performancesDuCheval('ch_abc');
        expect(lignes.length, 1, reason: 'toujours une seule participation');
        expect(lignes.first.place, 1,
            reason: 'la valeur officielle corrigée doit être retenue');

        // ignore: avoid_print
        print('[MESURE] correction officielle : place 5 → 1, '
            '${lignes.length} ligne conservée');
      },
    );
  });

  group('Distinction insuffisant / vide (§9)', () {
    test('estSuffisant refuse un corpus trop court', () async {
      final service = CorpusPerformancesService.instance;
      await service.enregistrer(
        dateStr: '13112026',
        numR: 3,
        numC: 4,
        source: 'pmu_performances_detaillees',
        parNumero: <String, List<PerformancePmu>>{
          '2': <PerformancePmu>[
            _pmu(nom: 'PEU DE COURSES', date: '2026-07-01'),
          ],
        },
      );

      expect(await service.estSuffisant(nomBrut: 'PEU DE COURSES', minimum: 5),
          isFalse);
      expect(await service.estSuffisant(nomBrut: 'PEU DE COURSES', minimum: 1),
          isTrue);
      expect(await service.estSuffisant(nomBrut: 'INCONNU AU CORPUS', minimum: 1),
          isFalse);
    });

    test('une réponse PMU vide n\'efface RIEN de ce qui est connu', () async {
      final service = CorpusPerformancesService.instance;
      await service.enregistrer(
        dateStr: '13112026',
        numR: 4,
        numC: 4,
        source: 'pmu_performances_detaillees',
        parNumero: <String, List<PerformancePmu>>{
          '7': <PerformancePmu>[
            _pmu(nom: 'CONSERVÉ', date: '2026-08-08', place: 2),
            _pmu(nom: 'CONSERVÉ', date: '2026-09-09', place: 4),
          ],
        },
      );
      final avant = await service.compter();

      // Le PMU ne répond rien (indisponible) : le producteur appelle avec vide.
      final ecrits = await service.enregistrer(
        dateStr: '13112026',
        numR: 4,
        numC: 5,
        source: 'pmu_performances_detaillees',
        parNumero: const <String, List<PerformancePmu>>{},
      );

      expect(ecrits, 0);
      expect(await service.compter(), avant, reason: 'aucune perte');

      final lues = await service.charger(nomBrut: 'CONSERVÉ');
      expect(lues.length, 2, reason: 'la connaissance antérieure survit');

      // ignore: avoid_print
      print('[MESURE] réponse PMU vide : $avant ligne(s) avant, '
          '${await service.compter()} après');
    });
  });
}

/// Petit harnais : une base SQLite réelle, sur disque temporaire, ouverte par
/// le CHEMIN DE PRODUCTION (`PontElo.ouvrir`) avec une racine isolée.
///
/// Ce choix est délibéré : le test exerce le même code que l'application, et
/// n'installe aucun faux dépôt. Seuls l'hôte (bureau au lieu d'Android) et la
/// racine (dossier temporaire) diffèrent. §14 : les données réelles de
/// l'utilisateur ne sont jamais touchées.
class SqfliteFfiFixture {
  SqfliteFfiFixture._(this._dir, this.depot);

  final Directory _dir;
  final DepotSqlite depot;

  static Future<SqfliteFfiFixture> creer() async {
    final dir = await Directory.systemTemp.createTemp('corpus_perf_test_');
    PontElo.instance.utiliserFabrique(databaseFactoryFfi);
    final ok = await PontElo.instance.ouvrir(racineForcee: dir.path);
    if (!ok || PontElo.instance.depotPourSauvegarde == null) {
      throw StateError('dépôt de test non ouvert');
    }
    return SqfliteFfiFixture._(dir, PontElo.instance.depotPourSauvegarde!);
  }

  Future<void> fermer() async {
    await PontElo.instance.fermer();
    try {
      await _dir.delete(recursive: true);
    } catch (_) {
      // Nettoyage best-effort : un échec ne doit pas faire échouer un test.
    }
  }
}
