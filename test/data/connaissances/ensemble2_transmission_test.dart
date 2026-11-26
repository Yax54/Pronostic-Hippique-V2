/// ENSEMBLE 2 — preuve de TRANSMISSION vers le moteur IA et les isolates.
///
/// Le mandat exige : « Vérifie la transmission effective des données enrichies
/// dans tous les chemins de production concernés » et « Ne considère pas les
/// résultats obtenus sur Hippodrome et Repos comme une validation complète des
/// 19 critères ».
///
/// ═══════════════════════════════════════════════════════════════════════════
///  CE QUE CE TEST PROUVE, ET CE QU'IL NE PROUVE PAS
///
///  PROUVÉ : les données produites par le producteur enrichi (corpus local +
///  PMU) SURVIVENT au trajet réel vers l'isolate — `toJson()` → payload →
///  `ZtReunion.fromJson()` — et chaque champ transmis est mesuré un par un.
///  Si un champ était perdu au passage, il serait mesuré à zéro dans l'isolate
///  alors qu'il est renseigné dans le processus principal.
///
///  NON PROUVÉ : que les 19 critères produisent chacun une valeur
///  « réellement calculée » sur toutes les courses possibles. Un champ transmis
///  et non nul ne garantit pas qu'un critère l'exploite ; c'est une question
///  distincte, qui relève du moteur et non du transport.
/// ═══════════════════════════════════════════════════════════════════════════
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/pont_elo.dart';
import 'package:pronostic_hippique/data/connaissances/_services/corpus_performances.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/corpus_pmu_replay.dart';

/// Tous les champs d'un partant qui portent une connaissance issue de
/// l'historique. Liste EXPLICITE : un champ ajouté au modèle et non transmis
/// doit être visible comme une régression, pas passer inaperçu.
const Map<String, String> kChampsTransmis = <String, String>{
  'STATS_HIPPO': 'stats_hippo_csv',
  'STATS_TERRAIN': 'stats_terrain_csv',
  'MUSIQUE_DIST': 'musique_dist',
  'JOURS_REPOS': 'jours_repos',
  'HIPPO_ACTUEL': 'hippodrome_actuel',
  'STATS_JOCKEY': 'stats_jockey_csv',
  'STATS_ENTR': 'stats_entr_csv',
  'ELO_R': 'elo_r',
  'ELO_NB': 'elo_nb',
  'ELO_V': 'elo_v',
  'POIDS': 'poids',
  'MUSIQUE': 'musique',
};

/// Une course du corpus qui porte réellement un historique publié.
CorpusCourse premiereCourseAvecHistorique() {
  for (final c in chargerManifeste()) {
    final f = File('$kCorpusDir/${c.key}_perfdet.json');
    if (!f.existsSync()) continue;
    final contenu = f.readAsStringSync().trim();
    if (contenu.length > 10 && contenu != '{}') return c;
  }
  fail('aucune course du corpus ne porte d\'historique');
}

void main() {
  late Directory racine;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    racine = await Directory.systemTemp.createTemp('ens2_isolate_');
    PontElo.instance.utiliserFabrique(databaseFactoryFfi);
    await PontElo.instance.ouvrir(racineForcee: racine.path);
    purgerProducteur();
  });

  tearDown(() async {
    purgerProducteur();
    await PontElo.instance.fermer();
    try {
      await racine.delete(recursive: true);
    } catch (_) {
      // best-effort
    }
  });

  test(
    'les données enrichies SURVIVENT au trajet vers l\'isolate (toJson → fromJson)',
    () async {
      final course = premiereCourseAvecHistorique();

      // 1) Acquisition réelle via le producteur, puis nouvelle analyse
      //    servie par le CORPUS LOCAL : c'est ce chemin qui alimente les
      //    champs enrichis, et donc celui qu'il faut transporter.
      await rejouerCourse(course);
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        if (await CorpusPerformancesService.instance.compter() > 0) break;
      }
      purgerProducteur();

      final reunions = await rejouerCourse(course);
      final partants = reunions.first.courses.first.partants;
      expect(partants, isNotEmpty);

      // 2) Le trajet EXACT de la production : toJson côté principal, puis
      //    fromJson côté isolate (c'est ce que fait `_BatchPayload`).
      final jsonPrincipal =
          partants.map((p) => p.toJson()).toList(growable: false);

      // On sérialise VRAIMENT, comme le fait `compute()` qui transmet par
      // message : une valeur non sérialisable serait perdue silencieusement.
      final encode = jsonEncode(jsonPrincipal);
      final decode = jsonDecode(encode) as List<dynamic>;
      final partantsIsolate = decode
          .map((e) => ZtPartant.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

      expect(partantsIsolate.length, partants.length,
          reason: 'aucun partant ne doit être perdu au transport');

      // 3) Mesure champ par champ : renseigné côté principal ⇒ renseigné
      //    côté isolate.
      final perdus = <String, int>{};
      final transmis = <String, int>{};
      for (var i = 0; i < partants.length; i++) {
        final av = partants[i];
        final ap = partantsIsolate[i];
        final paires = <String, List<Object?>>{
          'STATS_HIPPO': <Object?>[av.statsHippodromeCsv, ap.statsHippodromeCsv],
          'STATS_TERRAIN': <Object?>[av.statsTerrainCsv, ap.statsTerrainCsv],
          'MUSIQUE_DIST': <Object?>[
            av.musiqueDistanceSpecifique,
            ap.musiqueDistanceSpecifique
          ],
          'JOURS_REPOS': <Object?>[av.joursRepos, ap.joursRepos],
          'HIPPO_ACTUEL': <Object?>[av.hippodromeActuel, ap.hippodromeActuel],
          'STATS_JOCKEY': <Object?>[av.statsJockeyCsv, ap.statsJockeyCsv],
          'STATS_ENTR': <Object?>[av.statsEntraineurCsv, ap.statsEntraineurCsv],
          'ELO_R': <Object?>[av.eloRating, ap.eloRating],
          'ELO_NB': <Object?>[av.eloNbCourses, ap.eloNbCourses],
          'ELO_V': <Object?>[av.eloVariationMois, ap.eloVariationMois],
          'POIDS': <Object?>[av.poids, ap.poids],
          'MUSIQUE': <Object?>[av.musique, ap.musique],
        };

        paires.forEach((nom, valeurs) {
          final avant = valeurs[0];
          final apres = valeurs[1];
          final avantRenseigne = avant != null &&
              (avant is! String || avant.trim().isNotEmpty) &&
              (avant is! num || avant != 0);
          if (!avantRenseigne) return; // rien à transmettre, rien à mesurer
          transmis[nom] = (transmis[nom] ?? 0) + 1;
          if (apres != avant) perdus[nom] = (perdus[nom] ?? 0) + 1;
        });
      }

      // ignore: avoid_print
      print('[MESURE] transmission vers l\'isolate — '
          'champs renseignés et vérifiés : $transmis');
      // ignore: avoid_print
      print('[MESURE] champs PERDUS au transport : '
          '${perdus.isEmpty ? "aucun" : perdus}');

      expect(perdus, isEmpty,
          reason: 'tout champ renseigné dans le processus principal doit '
              'arriver intact dans l\'isolate');
      expect(transmis, isNotEmpty,
          reason: 'le corpus doit réellement alimenter des champs — sinon '
              'ce test ne prouverait rien');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'les données enrichies atteignent RÉELLEMENT le moteur de calcul',
    () async {
      final course = premiereCourseAvecHistorique();
      await rejouerCourse(course);
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        if (await CorpusPerformancesService.instance.compter() > 0) break;
      }
      purgerProducteur();

      final reunions = await rejouerCourse(course);
      final ztCourse = reunions.first.courses.first;
      expect(ztCourse.partants, isNotEmpty);

      // Le moteur produit ses critères. On ne vérifie PAS une formule (elles
      // sont protégées) : on vérifie que les DONNÉES D'ENTRÉE qu'il reçoit
      // portent bien la connaissance historique, et qu'il en produit un
      // résultat non vide.
      // `analyserCourseAvecCriteres` produit À LA FOIS le classement et les
      // scores par critère : c'est le chemin où l'on peut mesurer quels
      // critères ont RÉELLEMENT reçu une valeur, et lesquels restent neutres.
      final (pronostics, parCritere) =
          IaPronosticEngine.analyserCourseAvecCriteres(ztCourse);
      expect(pronostics, isNotEmpty,
          reason: 'le moteur doit produire un pronostic par partant');

      var avecRepos = 0;
      var avecHippo = 0;
      var scoresNonNuls = 0;
      for (final p in ztCourse.partants) {
        if (p.joursRepos > 0) avecRepos++;
        if (p.statsHippodromeCsv.trim().isNotEmpty) avecHippo++;
      }
      for (final pr in pronostics) {
        if (pr.scoreIA > 0) scoresNonNuls++;
      }

      // Quels critères ont une valeur NON NEUTRE (≠ 50) ? C'est la seule
      // mesure honnête de « réellement calculé » : un critère à 50 peut être
      // une vraie valeur ou un neutre, on ne le confond pas (règle §9).
      // On lit les champs TYPÉS (pas le toJson abrégé 'f','g',...) pour que
      // le compte rendu soit lisible : les 19 critères sont nommés.
      final criteresNonNeutres = <String>[];
      if (parCritere.isNotEmpty) {
        final c = parCritere.values.first;
        final etat = <String, double>{
          'A forme': c.forme,
          'B gains': c.gains,
          'C record': c.record,
          'D cote': c.cote,
          'E constance': c.constance,
          'F victoires': c.victoires,
          'G discipline': c.discipline,
          'H distSpec': c.distSpec,
          'I jockey': c.jockey,
          'J repos': c.repos,
          'K hippo': c.hippo,
          'L entraineur': c.entraineur,
          'M elo': c.elo,
          'N terrain': c.terrain,
          'O divergence': c.divergence,
          'P poidsRel': c.poidsRel,
          'Q progression': c.progression,
          'R mouvCote': c.mouvCote,
          'S placeDepart': c.placeDepart,
        };
        etat.forEach((nom, v) {
          if (v != 50.0) criteresNonNeutres.add(nom);
        });
        // ignore: avoid_print
        print('[MESURE] état des 19 critères (partant ${parCritere.keys.first}) : '
            '$etat');
      }

      // ignore: avoid_print
      print('[MESURE] entrée du moteur : ${ztCourse.partants.length} partant(s), '
          '$avecHippo avec hippodrome, $avecRepos avec repos — '
          '${pronostics.length} pronostic(s), $scoresNonNuls score(s) non nul(s)');
      // ignore: avoid_print
      print('[MESURE] critères à valeur NON NEUTRE (≠ 50) : '
          '${criteresNonNeutres.length} → $criteresNonNeutres');

      expect(avecHippo + avecRepos, greaterThan(0),
          reason: 'le moteur doit recevoir des données historiques réelles');
      expect(scoresNonNuls, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'un NETTOYAGE COMPLET DU CACHE ne rend pas les connaissances inaccessibles',
    () async {
      final course = premiereCourseAvecHistorique();

      // Acquisition + remplissage du corpus ET de la composition.
      await rejouerCourse(course);
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        if (await CorpusPerformancesService.instance.compter() > 0) break;
      }
      final avant = await CorpusPerformancesService.instance.compter();
      expect(avant, greaterThan(0));

      // ON VIDE LE CACHE, exactement comme le ferait un utilisateur ou une
      // maintenance : c'est la situation qui avait rendu le corpus muet quand
      // la composition vivait dans `cache/index_noms_partants.json`.
      purgerProducteur();
      final dossierCache = Directory('${racine.path}/cache');
      if (await dossierCache.exists()) {
        await dossierCache.delete(recursive: true);
      }

      // La connaissance doit rester CONSULTABLE : corpus ET composition.
      final apres = await CorpusPerformancesService.instance.compter();
      expect(apres, avant, reason: 'le corpus est en base, pas en cache');

      final composition =
          await CorpusPerformancesService.instance.chargerComposition(
        dateStr: course.date,
        numR: course.numR,
        numC: course.numC,
      );
      expect(composition, isNotEmpty,
          reason: 'la composition est en base (observations permanentes) : '
              'un nettoyage de cache ne peut pas la rendre inaccessible');

      // Et le repli doit toujours fonctionner, sans réseau.
      final nom = composition.values.first;
      final lues =
          await CorpusPerformancesService.instance.charger(nomBrut: nom);
      expect(lues, isNotEmpty);

      // ignore: avoid_print
      print('[MESURE] après suppression de cache/ : $apres performance(s), '
          '${composition.length} nom(s) de composition, '
          '${lues.length} performance(s) relue(s) pour "$nom"');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
