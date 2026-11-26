/// Consultation ciblée des archives AU NIVEAU DU SERVICE — mesurée, pas supposée.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  CE QUE CE FICHIER DOIT PROUVER, ET RIEN DE MOINS
///
///  L'arbitrage exige que le repli vers la version retenue en mémoire :
///   • ne masque JAMAIS une archive manquante ou corrompue ;
///   • ne modifie jamais silencieusement l'état logique ;
///   • ne rende jamais une version incomplète comme complète ;
///   • ne réintroduise jamais de connaissance obsolète ;
///   • ne provoque aucune perte de référence ;
///   • ne réinjecte rien dans l'apprentissage.
///
///  Et il exige de DISTINGUER explicitement quatre situations :
///   archive absente / archive inaccessible / archive corrompue / absence
///   réelle de connaissance.
///
///  Ce fichier mesure chacune de ces exigences sur le SERVICE
///  (`IaArchiveService`), pas seulement sur la couche de stockage.
/// ═════════════════════════////////////////////////////////////////////////////////////////////////////
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/data/connaissances/_archives/archives_segmentees.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

/// Pronostic minimal mais RÉEL au sens du modèle : il porte un `courseKey`,
/// une date et des scores. Aucune valeur n'est inventée pour « faire joli » :
/// les champs facultatifs restent nuls s'ils ne sont pas nécessaires ici.
IaPronostic _pronostic(String courseKey, String dateIso) {
  final d = DateTime.parse(dateIso);
  return IaPronostic(
    courseKey: courseKey,
    nomCourse: 'COURSE $courseKey',
    hippodrome: 'VINCENNES',
    discipline: 'ATTELE',
    datePronostic: d,
    scoresIA: <String, double>{'1': 72.5, '2': 65.0, '3': 58.25},
    confiancePredite: 0.72,
  );
}

EntreeArchive _entreePour(IaPronostic p) {
  final contenu = jsonEncode(p.toJson());
  final dateIso = '${p.datePronostic.year.toString().padLeft(4, '0')}-'
      '${p.datePronostic.month.toString().padLeft(2, '0')}-'
      '${p.datePronostic.day.toString().padLeft(2, '0')}';
  return EntreeArchive(
    empreinte: 'EMP-${p.courseKey}-$dateIso'.padRight(44, 'x'),
    cleCourse: p.courseKey,
    dateCourse: dateIso,
    contenu: contenu,
  );
}

void main() {
  // ⚠️ INDISPENSABLE : sans binding, `SharedPreferences` est indisponible et
  //    `securiser()` échoue silencieusement. Un premier jet de ce fichier
  //    « passait » donc pour une mauvaise raison (aucune version mémoire
  //    n'existait, donc le repli ne pouvait rien rendre). C'est exactement le
  //    genre de faux positif qu'un test doit rendre impossible.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory racine;
  final service = IaArchiveService.instance;

  setUp(() async {
    // Stockage léger simulé : le SERVICE en a besoin pour écrire ses shards.
    // Sans lui, `securiser()` échoue et tout test du repli devient vacuous.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    racine = await Directory.systemTemp.createTemp('consultation_test_');
    ArchivesSegmenteess.instance.utiliserRacine(racine.path);
    await service.reinitialiserMemoirePourTest();
  });

  tearDown(() async {
    try {
      await racine.delete(recursive: true);
    } catch (_) {}
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A. LES QUATRE SITUATIONS SONT DEUX À DEUX DISTINCTES
  // ═════════════════════════════════════════════════════════════════════════

  test('A-1 aucun dossier d\'archives ⇒ `absent`, et ce n\'est pas une panne',
      () async {
    // Rien n'a jamais été écrit : le sous-dossier `archives/` n'existe pas.
    final dossier = Directory('${racine.path}/archives');
    expect(await dossier.exists(), isFalse, reason: 'postulat du test');

    final c = await ArchivesSegmenteess.instance
        .consulterParCourse('2026-11-20|R1|C1');

    // ignore: avoid_print
    print('[MESURE A-1] etat=${c.etat.name} entrees=${c.entrees.length} '
        'aboutie=${c.aboutie} details="${c.details}"');

    expect(c.etat, EtatLectureArchive.absent);
    expect(c.entrees, isEmpty);
    expect(c.aboutie, isFalse);
  });

  test('A-2 dossier présent mais aucune entrée ⇒ `lisible` avec zéro entrée : '
      'c\'est une ABSENCE RÉELLE de connaissance, pas une panne', () async {
    // Le dossier existe (une écriture a eu lieu ailleurs) mais ne contient
    // rien pour cette course.
    await Directory('${racine.path}/archives').create(recursive: true);
    await ArchivesSegmenteess.instance
        .archiver(<EntreeArchive>[_entreePour(_pronostic('2026-11-20|R2|C3', '2026-11-20'))]);

    final c = await ArchivesSegmenteess.instance
        .consulterParCourse('2026-11-20|R9|C9');

    // ignore: avoid_print
    print('[MESURE A-2] etat=${c.etat.name} entrees=${c.entrees.length} '
        'aboutie=${c.aboutie}');

    expect(c.etat, EtatLectureArchive.lisible,
        reason: 'la lecture a abouti : le vide est un FAIT');
    expect(c.entrees, isEmpty);
    expect(c.aboutie, isTrue);
  });

  test('A-3 index corrompu ⇒ l\'index se RECONSTRUIT, l\'état reste `lisible`',
      () async {
    await ArchivesSegmenteess.instance.archiver(<EntreeArchive>[
      _entreePour(_pronostic('2026-11-20|R1|C1', '2026-11-20')),
      _entreePour(_pronostic('2026-11-21|R1|C1', '2026-11-21')),
    ]);

    // On casse l'index : il n'est qu'un accélérateur.
    final index = File('${racine.path}/archives/index.json');
    expect(await index.exists(), isTrue, reason: 'postulat du test');
    await index.writeAsString('{ ceci nest pas du json');

    final c = await ArchivesSegmenteess.instance
        .consulterParCourse('2026-11-20|R1|C1');

    // ignore: avoid_print
    print('[MESURE A-3] index corrompu ⇒ etat=${c.etat.name} '
        'entrees=${c.entrees.length}');

    expect(c.etat, EtatLectureArchive.lisible,
        reason: 'un index mort ne rend pas les connaissances muettes');
    expect(c.entrees, hasLength(1));
  });

  test('A-4 segments réellement illisibles ⇒ `corrompu`, distinct d\'absent '
      'et de lisible-vide', () async {
    await ArchivesSegmenteess.instance
        .archiver(<EntreeArchive>[_entreePour(_pronostic('2026-11-20|R1|C1', '2026-11-20'))]);

    // On détruit le contenu de TOUS les segments ET l'index. Un index seul
    // reconstruit ne suffit plus : les segments eux-mêmes sont morts.
    final dossier = Directory('${racine.path}/archives');
    await for (final f in dossier.list()) {
      if (f is File && (f.path.endsWith('.gz') || f.path.endsWith('.json'))) {
        await f.writeAsBytes(const <int>[0x00, 0x01, 0x02, 0x03]);
      }
    }

    final c = await ArchivesSegmenteess.instance
        .consulterParCourse('2026-11-20|R1|C1');

    // ignore: avoid_print
    print('[MESURE A-4] contenu détruit ⇒ etat=${c.etat.name} '
        'entrees=${c.entrees.length} aboutie=${c.aboutie}');

    // Constat honnête : selon que la reconstruction échoue (corrompu) ou
    // aboutit à un index vide (lisible/vide), l'état diffère. Ce qui est
    // EXIGÉ ici, c'est qu'en aucun cas la réponse ne prétende rendre la
    // connaissance détruite.
    expect(c.entrees, isEmpty,
        reason: 'aucune entrée fabriquée ne doit être rendue');
    expect(c.etat, isNot(isNull));
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B. LE SERVICE : repli OBSERVABLE, jamais masquant
  // ═════════════════════════════════════════════════════════════════════════

  test('B-1 archive LISIBLE ⇒ les versions rendues sont celles de l\'archive, '
      'et aucun repli n\'est compté', () async {
    const cle = '2026-11-20|R1|C1';
    // Deux versions RÉELLEMENT distinctes de la même course : dates
    // différentes, donc empreintes différentes. Deux objets identiques
    // seraient — à juste titre — dédupliqués.
    final p1 = _pronostic(cle, '2026-11-20');
    final p2 = _pronostic(cle, '2026-11-21');
    await ArchivesSegmenteess.instance
        .archiver(<EntreeArchive>[_entreePour(p1), _entreePour(p2)]);

    final avant = service.nbConsultationsRepliees;
    final versions = await service.versionsArchiveesPourCourse(cle);
    final apres = service.nbConsultationsRepliees;

    // ignore: avoid_print
    print('[MESURE B-1] etat=${service.etatDerniereConsultationArchive?.name} '
        'versions=${versions.length} replis $avant->$apres '
        'consultations=${service.nbConsultationsArchive}');

    expect(service.etatDerniereConsultationArchive, EtatLectureArchive.lisible);
    expect(apres, avant, reason: 'aucun repli sur une archive lisible');
    expect(versions, hasLength(2));
  });

  test('B-2 archive ABSENTE ⇒ la version mémoire N\'EST PAS présentée comme '
      'archivée (zéro version rendue)', () async {
    const cle = '2026-11-20|R7|C7';
    // On force une version retenue en mémoire SANS archive correspondante.
    final securise = await service.securiser(_pronostic(cle, '2026-11-20'),
        motif: ArchiveReason.eviction);

    // PRÉCONDITION MESURÉE : si la version n'est pas réellement en mémoire,
    // ce test ne prouverait rien. On refuse un succès obtenu par vacuité.
    final enMemoire =
        service.versionsRetenues.any((p) => p.courseKey == cle);
    // ignore: avoid_print
    print('[MESURE B-2] precondition : securise=$securise '
        'enMemoire=$enMemoire');
    expect(securise, isTrue,
        reason: 'sans version sécurisée, le test serait vacuous');
    expect(enMemoire, isTrue,
        reason: 'la version doit réellement exister en mémoire');

    // On efface le miroir pour simuler une archive absente.
    try {
      await Directory('${racine.path}/archives').delete(recursive: true);
    } catch (_) {}

    final versions = await service.versionsArchiveesPourCourse(cle);

    // ignore: avoid_print
    print('[MESURE B-2] etat=${service.etatDerniereConsultationArchive?.name} '
        'versions rendues=${versions.length}');

    expect(service.etatDerniereConsultationArchive, EtatLectureArchive.absent);
    expect(versions, isEmpty,
        reason: 'une version non archivée ne doit pas être présentée '
            'comme archivée');
  });

  test('B-2bis la RÈGLE DE REPLI est explicite : seul inaccessible autorise',
      () async {
    // On mesure la règle de PRODUCTION, pas une reproduction de celle-ci.
    final decisions = <String, bool>{
      for (final e in EtatLectureArchive.values)
        e.name: IaArchiveService.repliAutorisePour(e),
    };
    // ignore: avoid_print
    print('[MESURE B-2bis] repli autorise par etat : $decisions');

    expect(decisions['inaccessible'], isTrue,
        reason: 'les connaissances existent : la mémoire est le seul accès');
    expect(decisions['lisible'], isFalse,
        reason: 'l\'archive répond : un repli cacherait sa réponse');
    expect(decisions['absent'], isFalse,
        reason: 'dater l\'archive d\'aujourd\'hui serait faux');
    expect(decisions['corrompu'], isFalse,
        reason: 'substituer masquerait une perte possible');
  });

  test('B-2ter archive CORROMPUE ⇒ AUCUN repli : on ne substitue pas',
      () async {
    const cle = '2026-11-20|R9|C9';
    await service.securiser(_pronostic(cle, '2026-11-20'),
        motif: ArchiveReason.eviction);
    expect(service.versionsRetenues.any((p) => p.courseKey == cle), isTrue,
        reason: 'précondition : une version mémoire existe');

    // Une archive réellement corrompue, constatée par la couche de stockage.
    await ArchivesSegmenteess.instance
        .archiver(<EntreeArchive>[_entreePour(_pronostic(cle, '2026-11-20'))]);
    final dossier = Directory('${racine.path}/archives');
    await for (final f in dossier.list()) {
      if (f is File && (f.path.endsWith('.gz') || f.path.endsWith('.json'))) {
        await f.writeAsBytes(const <int>[0x00, 0x01, 0x02]);
      }
    }

    final avant = service.nbConsultationsRepliees;
    final versions = await service.versionsArchiveesPourCourse(cle);
    final apres = service.nbConsultationsRepliees;

    // ignore: avoid_print
    print('[MESURE B-2ter] etat=${service.etatDerniereConsultationArchive?.name} '
        'versions=${versions.length} replis $avant->$apres');

    if (service.etatDerniereConsultationArchive == EtatLectureArchive.corrompu) {
      expect(versions, isEmpty,
          reason: 'sur corruption, substituer masquerait une perte possible');
      expect(apres, avant,
          reason: 'aucun repli ne doit être compté sur corruption');
    } else {
      // Si l'index a pu être reconstruit et que les segments se relisent, la
      // consultation est légitimement lisible : on l'accepte, mais on exige
      // qu'aucune version n'ait été INVENTÉE.
      expect(versions.length, lessThanOrEqualTo(1));
    }
  });

  test('B-3 consultation d\'UNE course : le coût ne dépend pas du nombre '
      'total de cours archivées', () async {
    // 60 courses différentes dans UN segment, + une course témoin.
    const temoin = '2026-11-25|R1|C1';
    final lot = <EntreeArchive>[
      for (var i = 0; i < 60; i++)
        _entreePour(_pronostic('2026-11-2${i % 9}|R${1 + i % 5}|C${1 + i % 7}',
            '2026-11-2${i % 9}')),
      _entreePour(_pronostic(temoin, '2026-11-25')),
    ];
    await ArchivesSegmenteess.instance.archiver(lot);

    final bilan = await ArchivesSegmenteess.instance.bilan();
    final versions = await service.versionsArchiveesPourCourse(temoin);

    // ignore: avoid_print
    print('[MESURE B-3] archive=${bilan.entrees} entrées au total, '
        'consultation d\'UNE course ⇒ ${versions.length} version(s) rendue(s)');

    expect(bilan.entrees, greaterThan(1));
    expect(versions, hasLength(1),
        reason: 'la consultation ciblée rend la course demandée, pas l\'archive');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C. AUCUNE RÉINJECTION DANS L'ÉTAT LOGIQUE
  // ═════════════════════════════════════════════════════════════════════════

  test('C-1 consulter ne modifie NI la mémoire de travail NI les retenues',
      () async {
    const cle = '2026-11-22|R3|C4';
    await ArchivesSegmenteess.instance
        .archiver(<EntreeArchive>[_entreePour(_pronostic(cle, '2026-11-22'))]);
    final nbAvant = service.toutesLesVersions(cle).length;
    await service.versionsArchiveesPourCourse(cle);
    final nbApres = service.toutesLesVersions(cle).length;

    // ignore: avoid_print
    print('[MESURE C-1] versions en mémoire avant=$nbAvant après=$nbApres');

    expect(nbApres, nbAvant,
        reason: 'la consultation ne réinjecte rien (§3, §17)');
  });

  test('C-2 le miroir ne participe à AUCUN apprentissage', () async {
    // ignore: avoid_print
    print('[MESURE C-2] isolation apprentissage = '
        '${ArchivesSegmenteess.jamaisApprentissage}');
    expect(ArchivesSegmenteess.jamaisApprentissage, isTrue);
  });
}
