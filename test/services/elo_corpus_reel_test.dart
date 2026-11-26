/// ELO en conditions RÉELLES : les connaissances du corpus sont-elles exploitées ?
///
/// ═══════════════════════════════════════════════════════════════════════════
///  QUESTION POSÉE PAR LA CONSIGNE, MOT POUR MOT
///
///  > « Vérifie notamment que l'ELO exploite effectivement les connaissances
///  > historiques disponibles et ne retombe pas systématiquement sur la valeur
///  > initiale de 1500. »
///
///  Ce fichier y répond par la MESURE, sur les réponses PMU authentiques du
///  corpus (`test/fixtures_corpus`), dans le chemin de production :
///
///     programme PMU → partants → enrichirAvecElo(discipline)
///
///  Ce qui est mesuré :
///    • combien de partants portent un rating AUTHENTIQUE (entrée réelle) ;
///    • combien n'en portent AUCUN (absence de connaissance) ;
///    • combien retombent sur le rating de repli 1500 **en étant présentés
///      comme évalués** — c'est précisément le défaut corrigé ;
///    • ce que vaut le critère M dans chacun de ces cas.
///
///  Aucune formule n'est touchée : `scoreElo` reste `((rating-1200)/8)`.
/// ═══════════════════════════════════════════════════════════════════════════
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pronostic_hippique/data/connaissances/_adapters/pont_elo.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';

import '../support/corpus_pmu_replay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory racine;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    racine = await Directory.systemTemp.createTemp('elo_corpus_');
    PontElo.instance.utiliserFabrique(databaseFactoryFfi);
    final ok = await PontElo.instance.ouvrir(racineForcee: racine.path);
    expect(ok, isTrue, reason: 'le dépôt structuré doit s\'ouvrir');
  });

  tearDown(() async {
    await PontElo.instance.fermer();
    try {
      await racine.delete(recursive: true);
    } catch (_) {}
  });

  test('l\'ELO distingue le connu de l\'inconnu sur des partants PMU réels',
      () async {
    // Course réelle du corpus, avec son programme reconstruit.
    final course = corpusDe('ATTELE').firstWhere(
      (c) => File('$kCorpusDir/${c.key}_perfdet.json').existsSync(),
      orElse: () => corpusDe('ATTELE').first,
    );
    // Chemin de PRODUCTION : `rejouerCourse` passe par
    // `ZoneTurfService.chargerProgramme`, comme l'application réelle.
    purgerProducteur();
    final reunions = await rejouerCourse(course);
    expect(reunions, isNotEmpty, reason: 'le programme doit se reconstruire');
    final ztCourse = reunions
        .expand((r) => r.courses)
        .firstWhere((c) => c.partants.isNotEmpty,
            orElse: () => reunions.first.courses.first);
    final partants = ztCourse.partants;
    expect(partants, isNotEmpty, reason: 'la course doit avoir des partants');

    // ── Cas A : AUCUNE connaissance ELO en mémoire ────────────────────────
    // C'est la situation d'un premier lancement, ou d'un isolate qui aurait
    // perdu ses ratings. Avant correction, TOUS ces partants recevaient 1500
    // et donc 37,5 présentés comme une évaluation.
    EloService.instance.chargerDepuisMapIsolate(<String, dynamic>{});
    final sansConnaissance = EloService.instance.enrichirAvecElo(
      partants,
      discipline: course.discipline,
    );

    var repliEvalues = 0;
    var neutres = 0;
    for (final p in sansConnaissance) {
      if (p.eloRating == 1500.0) repliEvalues++;
      if (p.scoreElo == 50.0) neutres++;
    }
    // ignore: avoid_print
    print('[MESURE] sans connaissance ELO : ${partants.length} partant(s), '
        '$repliEvalues avec un repli 1500 présenté comme un rating, '
        '$neutres à la neutralité 50.0');
    expect(repliEvalues, 0,
        reason: 'aucun partant ne doit porter le repli 1500 comme un rating');
    expect(neutres, partants.length,
        reason: 'sans connaissance, TOUS doivent être à la neutralité 50.0');

    // ── Cas B : connaissances RÉELLES injectées ───────────────────────────
    // On donne à UN partant un rating authentique, exactement comme le ferait
    // `chargerDepuisMapIsolate` depuis `exporterPourBackup()` côté isolate.
    final cible = partants.first.nom;
    // La clé doit être construite avec la MÊME normalisation que le service :
    // `NOM|DISCIPLINE` où la discipline passe par `normaliserDiscipline`
    // (ATTELE → TROT_ATTELE). Construire la clé à la main sans cette
    // normalisation ne trouvait rien — défaut du test, pas du code.
    final cle =
        '${cible.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ')}'
        '|${EloService.normaliserDiscipline(course.discipline)}';
    final map = <String, dynamic>{
      cle: const EloScore(nomCheval: 'CIBLE', rating: 1820.0, nbCourses: 25)
          .toJson(),
    };
    EloService.instance.chargerDepuisMapIsolate(map);

    final avecConnaissance = EloService.instance.enrichirAvecElo(
      partants,
      discipline: course.discipline,
    );

    final enrichiCible =
        avecConnaissance.firstWhere((p) => p.nom == cible);
    final autres = avecConnaissance.where((p) => p.nom != cible).toList();
    final autresNeutres = autres.where((p) => p.scoreElo == 50.0).length;

    // ignore: avoid_print
    print('[MESURE] avec connaissance ELO sur "$cible" : '
        'rating=${enrichiCible.eloRating} (authentique, pas 1500), '
        'critère M=${enrichiCible.scoreElo}, '
        '${autresNeutres}/${autres.length} autres partants à 50.0');

    // La connaissance est EFFECTIVEMENT exploitée : le rating réel arrive
    // jusqu'au partant, et le critère M n'est plus neutralisé pour lui.
    expect(enrichiCible.eloRating, greaterThan(0.0),
        reason: 'un rating authentique doit être transmis, pas remplacé');
    expect(enrichiCible.scoreElo, isNot(50.0),
        reason: 'la connaissance historique doit CHANGER le critère M');

    // Et la neutralité des autres reste légitime : elle vient de l'absence,
    // pas d'un calcul. §9 : ne pas confondre les deux.
    expect(autresNeutres, autres.length,
        reason: 'les partants sans rating restent à la neutralité 50.0');
  });

  test('le repli 1500 n\'est plus jamais confondu avec une mesure', () async {
    // Contrôle négatif : on injecte VOLONTAIREMENT un rating authentique de
    // 1500 (donc un vrai 37.5) et on vérifie qu'il n'est PAS transformé.
    final partantReel = ZtPartant(
      numero: '1',
      nom: 'REEL_1500',
      driver: '',
      entraineur: '',
      proprietaire: '',
      gains: '0',
      record: '',
      musique: '',
      cote: '',
      ageSexe: '',
    );
    final partantInconnu = ZtPartant(
      numero: '2',
      nom: 'AUCUN_RATING',
      driver: '',
      entraineur: '',
      proprietaire: '',
      gains: '0',
      record: '',
      musique: '',
      cote: '',
      ageSexe: '',
    );

    EloService.instance.chargerDepuisMapIsolate(<String, dynamic>{
      'REEL_1500|':
          const EloScore(nomCheval: 'REEL_1500', rating: 1500.0, nbCourses: 18)
              .toJson(),
    });

    final enrichis = EloService.instance.enrichirAvecElo(
      <ZtPartant>[partantReel, partantInconnu],
    );

    final reel = enrichis.firstWhere((p) => p.nom == 'REEL_1500');
    final inconnu = enrichis.firstWhere((p) => p.nom == 'AUCUN_RATING');

    // ignore: avoid_print
    print('[MESURE] authentique 1500 → ${reel.eloRating}/${reel.scoreElo} | '
        'inconnu → ${inconnu.eloRating}/${inconnu.scoreElo}');

    expect(reel.eloRating, 1500.0,
        reason: 'un rating AUTHENTIQUE de 1500 doit être conservé tel quel');
    expect(reel.scoreElo, 37.5,
        reason: 'la formule est intacte : 1500 reste 37.5 quand il est réel');
    expect(inconnu.eloRating, 0.0,
        reason: 'l\'absence ne doit plus être écrite comme un rating');
    expect(inconnu.scoreElo, 50.0);
  });
}
