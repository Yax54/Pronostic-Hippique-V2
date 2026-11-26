/// ENSEMBLE 2 — preuve de raccordement sur RÉPONSES PMU RÉELLES.
///
/// Consigne : « Ne te limite pas à lire le code ou à créer de nouvelles classes
/// isolées. Réalise le raccordement fonctionnel complet. » Un test qui injecte
/// son propre JSON ne prouve pas qu'un raccordement fonctionne : il prouve
/// qu'une fonction accepte une entrée. Ici, la chaîne de PRODUCTION est rejouée
/// (`ZoneTurfService.chargerProgramme`) et alimentée par le corpus authentique
/// de `test/fixtures_corpus/` (réponses PMU copiées intégralement).
///
/// ═══════════════════════════════════════════════════════════════════════════
///  CE QUI EST MESURÉ ICI
///
///  1. Le PMU répond → les performances du corpus `performances` sont ÉCRITES
///     (avant ce chantier : jamais écrites).
///  2. Le corpus est relu par le consommateur réel (`_histosDepuisCorpus` via
///     `_chargerPerformancesDetaillees`) quand le PMU est indisponible.
///  3. Une coupure réseau ne DÉTRUIT pas la connaissance déjà acquise.
///  4. Aucune valeur absente n'est transformée en zéro.
///
///  NON MESURÉ ICI : le comportement sur appareil Android réel, et le coût
///  réseau réel (le client est simulé sur le corpus). Le moteur SQLite, lui,
///  est le vrai (FFI).
/// ═══════════════════════════════════════════════════════════════════════════
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/pont_elo.dart';
import 'package:pronostic_hippique/data/connaissances/_services/corpus_performances.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/corpus_pmu_replay.dart';

/// Une course du corpus qui a RÉELLEMENT un historique publié.
CorpusCourse premiereCourseAvecHistorique() {
  final manifeste = chargerManifeste();
  for (final c in manifeste) {
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
    racine = await Directory.systemTemp.createTemp('ens2_e2e_');
    PontElo.instance.utiliserFabrique(databaseFactoryFfi);
    final ok = await PontElo.instance.ouvrir(racineForcee: racine.path);
    expect(ok, isTrue, reason: 'le dépôt structuré doit s\'ouvrir');
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

  group('Raccordement producteur → corpus', () {
    test(
      'le PMU répond : les performances sont RÉELLEMENT écrites en base',
      () async {
        final course = premiereCourseAvecHistorique();
        final avant = await CorpusPerformancesService.instance.compter();
        expect(avant, 0, reason: 'base de test vierge avant le rejeu');

        await rejouerCourse(course);

        // L'écriture est lancée en tâche de fond (unawaited) : on laisse la
        // boucle d'événements la terminer, sans boucle d'attente arbitraire.
        var apres = 0;
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          apres = await CorpusPerformancesService.instance.compter();
          if (apres > 0) break;
        }

        expect(apres, greaterThan(0),
            reason: 'la table performances doit cesser d\'être morte');

        // ignore: avoid_print
        print('[MESURE] raccordement producteur : course ${course.key} '
            '(${course.hippodrome}, ${course.discipline}) → '
            '$apres performance(s) écrite(s) en base');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'rejouer la MÊME course n\'ajoute rien (idempotence réelle)',
      () async {
        final course = premiereCourseAvecHistorique();
        await rejouerCourse(course);
        var total = 0;
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          total = await CorpusPerformancesService.instance.compter();
          if (total > 0) break;
        }
        expect(total, greaterThan(0));

        // Deuxième rejeu, en forçant le contournement du cache mémoire : le
        // PMU republie exactement les mêmes courses.
        purgerProducteur();
        await rejouerCourse(course);
        await Future<void>.delayed(const Duration(milliseconds: 300));

        final apres = await CorpusPerformancesService.instance.compter();
        expect(apres, total,
            reason: 'un second passage ne doit créer aucune connaissance');

        // ignore: avoid_print
        print('[MESURE] idempotence sur données réelles : '
            '$total puis $apres ligne(s)');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('Repli local quand le PMU est indisponible', () {
    test(
      'PMU coupé : l\'historique est reconstitué depuis le corpus',
      () async {
        final course = premiereCourseAvecHistorique();

        // 1) Première analyse : le PMU répond, le corpus se remplit.
        await rejouerCourse(course);
        var total = 0;
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          total = await CorpusPerformancesService.instance.compter();
          if (total > 0) break;
        }
        expect(total, greaterThan(0), reason: 'socle de connaissance acquis');

        // 2) Seconde analyse : le PMU est TOTALEMENT indisponible.
        purgerProducteur();
        await http.runWithClient(
          () async {
            await ZoneTurfService.chargerProgramme(
              forceRefresh: true,
              date: course.dateReelle,
            );
          },
          // Tout échoue, comme une coupure réseau réelle.
          () => MockClient((http.Request req) async {
            throw const SocketException('réseau indisponible (test)');
          }),
        );

        // 3) Le corpus doit être resté identique : rien n'a été détruit.
        final apres = await CorpusPerformancesService.instance.compter();
        expect(apres, total,
            reason: 'une coupure réseau ne doit rien effacer');

        // 4) Et il doit être LISIBLE : on interroge un nom réellement présent.
        final unNom = _unNomDuCorpus(course);
        expect(unNom, isNotEmpty, reason: 'le corpus nomme bien ses chevaux');
        final lues =
            await CorpusPerformancesService.instance.charger(nomBrut: unNom);
        expect(lues, isNotEmpty,
            reason: 'le corpus doit rester consultable hors ligne');

        // ignore: avoid_print
        print('[MESURE] repli hors ligne : $apres ligne(s) conservée(s), '
            '${lues.length} relue(s) pour "$unNom"');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'aucune place publiée ne devient 0 en base (absent ≠ dernier)',
      () async {
        final course = premiereCourseAvecHistorique();
        await rejouerCourse(course);
        for (var i = 0; i < 60; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          if (await CorpusPerformancesService.instance.compter() > 0) break;
        }

        final total = await CorpusPerformancesService.instance.compter();
        expect(total, greaterThan(0));

        // Le producteur écrivait 0 pour « non publié ». En base, la valeur
        // doit être NULL ; relue par le corpus, elle doit être null (et non 0),
        // et une distance relue doit être strictement positive.
        var lues = 0;
        var distancesNulles = 0;
        var distancesPositives = 0;
        for (final nom in _nomsDuCorpus(course, limite: 6)) {
          for (final p in await CorpusPerformancesService.instance
              .charger(nomBrut: nom)) {
            lues++;
            if (p.distanceMetres == null) {
              distancesNulles++;
            } else {
              expect(p.distanceMetres, greaterThan(0),
                  reason: 'une distance de 0 m n\'existe pas : '
                      'ce serait une valeur fabriquée');
              distancesPositives++;
            }
          }
        }
        expect(lues, greaterThan(0));

        // ignore: avoid_print
        print('[MESURE] valeurs absentes : $total ligne(s) en base, '
            '$lues relues — $distancesNulles sans distance (null), '
            '$distancesPositives avec distance réelle');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  mainSuiteAlimentationDesCriteres();
}

/// Nom d'un cheval réellement présent dans la réponse PMU de la course.
///
/// On lit le fichier de corpus, PAS la base : ouvrir une seconde connexion
/// SQLite sur le même fichier fermerait le handle utilisé par la production
/// (sqflite met en cache une base par chemin). C'était le défaut du harnais
/// précédent, qui produisait un `database_closed` trompeur.
String _unNomDuCorpus(CorpusCourse course) {
  final f = File('$kCorpusDir/${course.key}_perfdet.json');
  if (!f.existsSync()) return '';
  final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final parts = data['participants'];
  if (parts is! List) return '';
  for (final p in parts) {
    if (p is! Map) continue;
    final nom = p['nomCheval'];
    final cc = p['coursesCourues'];
    if (nom is String && nom.trim().isNotEmpty && cc is List && cc.isNotEmpty) {
      return nom;
    }
  }
  return '';
}

/// Noms distincts réellement présents dans la réponse PMU (au plus [limite]).
List<String> _nomsDuCorpus(CorpusCourse course, {int limite = 6}) {
  final f = File('$kCorpusDir/${course.key}_perfdet.json');
  if (!f.existsSync()) return const <String>[];
  final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final parts = data['participants'];
  if (parts is! List) return const <String>[];
  final noms = <String>[];
  for (final p in parts) {
    if (p is! Map) continue;
    final nom = p['nomCheval'];
    final cc = p['coursesCourues'];
    if (nom is String && nom.trim().isNotEmpty && cc is List && cc.isNotEmpty) {
      if (!noms.contains(nom)) noms.add(nom);
      if (noms.length >= limite) break;
    }
  }
  return noms;
}

/// MAILLON SUIVANT DE LA CHAÎNE : le corpus doit RÉELLEMENT alimenter les
/// critères qui dépendent de l'historique.
///
/// Ces deux critères sont mesurables sans ambiguïté :
///   • `statsHippodromeCsv`  (« nbCourses|nbVict|nbTop3 ») — vient de
///     l'historique détaillé, pas de la musique ;
///   • `joursRepos`          — vient de la date de la dernière course connue.
///
/// Ils sont nuls quand l'historique est vide. S'ils sont renseignés alors que
/// le PMU est COUPÉ, la preuve est faite que le corpus local alimente bien les
/// critères, et non seulement qu'il stocke.
void mainSuiteAlimentationDesCriteres() {
  group('Alimentation réelle des critères', () {
    test(
      'PMU coupé : hippodrome et jours de repos restent alimentés par le corpus',
      () async {
        final course = premiereCourseAvecHistorique();

        // 1) Acquisition : le PMU répond normalement.
        await rejouerCourse(course);
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          if (await CorpusPerformancesService.instance.compter() > 0) break;
        }
        expect(await CorpusPerformancesService.instance.compter(),
            greaterThan(0));

        // 2) Analyse avec SEUL `performances-detaillees` indisponible.
        //
        //    Ce scénario est le vrai : le programme et les partants viennent
        //    d'endpoints distincts, qui peuvent répondre alors que l'historique
        //    détaillé échoue (c'est précisément le cas observé en production,
        //    avec un endpoint qui renvoie 420 ou tombe en délai). Simuler une
        //    coupure TOTALE ne prouverait rien sur le corpus : sans programme,
        //    il n'y a aucun partant à alimenter.
        purgerProducteur();
        late List<ZtReunion> reunions;
        await http.runWithClient(
          () async {
            reunions = await ZoneTurfService.chargerProgramme(
              forceRefresh: true,
              date: course.dateReelle,
            );
          },
          () => MockClient((http.Request req) async {
            if (req.url.path.contains('performances-detaillees')) {
              // L'historique détaillé est indisponible ; tout le reste répond
              // avec les données PMU authentiques du corpus.
              return http.Response('', 420);
            }
            if (req.url.path.contains('participants')) {
              return http.Response(
                File('$kCorpusDir/${course.key}_participants.json')
                    .readAsStringSync(),
                200,
                headers: const <String, String>{
                  'content-type': 'application/json'
                },
              );
            }
            return http.Response(
              jsonEncode(programmeReconstruit(course)),
              200,
              headers: const <String, String>{
                'content-type': 'application/json'
              },
            );
          }),
        );

        // 3) Mesure sur les partants réellement produits.
        final partants = reunions.isEmpty
            ? const <ZtPartant>[]
            : reunions.first.courses.first.partants;
        expect(partants, isNotEmpty,
            reason: 'le programme doit rester servi sans réseau');

        var avecHippodrome = 0;
        var avecRepos = 0;
        for (final p in partants) {
          if (p.statsHippodromeCsv.trim().isNotEmpty) avecHippodrome++;
          if (p.joursRepos > 0) avecRepos++;
        }

        // ignore: avoid_print
        print('[MESURE] alimentation des critères hors ligne : '
            '${partants.length} partant(s), '
            '$avecHippodrome avec statistique hippodrome, '
            '$avecRepos avec jours de repos');

        // Le critère hippodrome exige des courses sur le MÊME hippodrome :
        // sa présence n'est pas garantie sur toutes les courses, mais elle ne
        // peut provenir que de l'historique.
        expect(avecHippodrome + avecRepos, greaterThan(0),
            reason: 'sans le corpus, ces deux critères seraient à zéro : '
                'aucune alimentation historique hors ligne');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
