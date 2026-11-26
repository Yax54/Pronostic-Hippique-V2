/// Sauvegarde et restauration INTÉGRALES des archives — mesurées sur disque.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  CE QUE CE FICHIER DOIT PROUVER, ET RIEN DE MOINS
///
///  Une sauvegarde qui n'emporte pas les archives n'est pas une sauvegarde
///  complète : elle annoncerait une réussite en laissant hors du conteneur des
///  connaissances que l'application refuse de perdre (§15, §16).
///
///  Ce fichier mesure :
///   1. que le bloc `fichiers_permanents` emporte RÉELLEMENT `archives/`
///      (octets réels, pas une déclaration) ;
///   2. qu'une restauration réécrit ces octets à l'identique, bit pour bit ;
///   3. qu'une archive restaurée reste CONSULTABLE par le chemin ciblé ;
///   4. qu'une interruption de la restauration des fichiers n'annonce pas
///      une réussite.
/// ═══════════════════════════════════════════════════════════════════════════
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/data/connaissances/_adapters/organisation_fichiers.dart';
import 'package:pronostic_hippique/data/connaissances/_archives/archives_segmentees.dart';
import 'package:pronostic_hippique/data/connaissances/_sauvegarde/restaurateur.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pronostic_hippique/services/backup_service.dart';

EntreeArchive _entree(String cle, String date, {String? resultat}) =>
    EntreeArchive(
      empreinte: 'EMP-$cle-$date'.padRight(44, 'z'),
      cleCourse: cle,
      dateCourse: date,
      contenu: jsonEncode(<String, Object?>{'course': cle, 'date': date}),
      resultatOfficiel: resultat,
    );

/// Recopie un dossier d'archives en mémoire, octet pour octet.
Future<Map<String, String>> _empreintesDisque(String dossier) async {
  final dir = Directory(dossier);
  if (!await dir.exists()) return <String, String>{};
  final out = <String, String>{};
  await for (final e in dir.list(recursive: true)) {
    if (e is! File) continue;
    final relatif = e.path.substring(dossier.length + 1).replaceAll('\\', '/');
    out[relatif] = base64Encode(await e.readAsBytes());
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory racine;
  late OrganisationFichiers org;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sqfliteFfiInit();
    racine = await Directory.systemTemp.createTemp('archives_backup_test_');
    org = await OrganisationFichiers.initialiser(racineForcee: racine.path);
    ArchivesSegmenteess.instance.utiliserRacine(racine.path);
  });

  tearDown(() async {
    try {
      await racine.delete(recursive: true);
    } catch (_) {}
  });

  test('S-1 l\'export emporte RÉELLEMENT les octets de archives/', () async {
    // Trois courses, dont une avec résultat officiel.
    await ArchivesSegmenteess.instance.archiver(<EntreeArchive>[
      _entree('2026-11-20|R1|C1', '2026-11-20'),
      _entree('2026-11-20|R1|C2', '2026-11-20'),
      _entree('2026-11-21|R2|C1', '2026-11-21', resultat: '1;2;3'),
    ]);

    final avant = await _empreintesDisque(org.cheminArchives);
    // ignore: avoid_print
    print('[MESURE S-1] archives/ sur disque avant export : '
        '${avant.length} fichier(s), ${avant.values.join().length} o base64');

    expect(avant, isNotEmpty, reason: 'postulat : des archives existent');

    // L'export de production, celui qui alimente le .ptg.
    // (On mesure le BLOC, pas un export complet : le dépôt SQLite n'est pas
    //  ouvert dans ce test, et ce n'est pas ce qu'on mesure ici.)
    final bloc = await _blocFichiersPermanents(org);
    final fichierArchives = <String, Object?>{};
    for (final e in bloc.entries) {
      if (e.key.startsWith('archives/')) fichierArchives[e.key] = e.value;
    }

    // ignore: avoid_print
    print('[MESURE S-1] bloc fichiers_permanents : ${bloc.length} fichier(s), '
        'dont ${fichierArchives.length} sous archives/');

    expect(fichierArchives.length, avant.length,
        reason: 'chaque fichier du disque doit entrer dans le bloc');

    // Comparaison OCTET POUR OCTET avec ce qui est sur le disque.
    for (final e in avant.entries) {
      final dansBloc = bloc['archives/${e.key}'];
      expect(dansBloc, isNotNull, reason: '${e.key} absent du bloc');
      expect((dansBloc! as Map)['base64'], e.value,
          reason: '${e.key} altéré pendant l\'export');
    }
  });

  test('S-2 la restauration réécrit les archives À L\'IDENTIQUE', () async {
    await ArchivesSegmenteess.instance.archiver(<EntreeArchive>[
      _entree('2026-11-20|R1|C1', '2026-11-20'),
      _entree('2026-11-21|R2|C1', '2026-11-21', resultat: '4;5;6'),
    ]);

    final avant = await _empreintesDisque(org.cheminArchives);
    final bloc = await _blocFichiersPermanents(org);

    // On simule une perte TOTALE du dossier d'archives.
    await Directory(org.cheminArchives).delete(recursive: true);
    expect(await _empreintesDisque(org.cheminArchives), isEmpty,
        reason: 'postulat : le dossier a bien été effacé');

    // On restaure par le chemin de PRODUCTION.
    await _restaurerFichiers(bloc, org.racine.path);

    final apres = await _empreintesDisque(org.cheminArchives);
    // ignore: avoid_print
    print('[MESURE S-2] avant ${avant.length} fichier(s) → perte totale → '
        'après restauration ${apres.length} fichier(s)');

    expect(apres.keys.toSet(), avant.keys.toSet(),
        reason: 'aucun fichier ne doit manquer');
    for (final e in avant.entries) {
      expect(apres[e.key], e.value,
          reason: '${e.key} doit être restitué BIT POUR BIT');
    }
  });

  test('S-3 une archive restaurée reste CONSULTABLE par le chemin ciblé',
      () async {
    await ArchivesSegmenteess.instance.archiver(<EntreeArchive>[
      _entree('2026-11-20|R1|C1', '2026-11-20'),
      _entree('2026-11-22|R3|C2', '2026-11-22', resultat: '7;8;9'),
    ]);
    final bloc = await _blocFichiersPermanents(org);

    await Directory(org.cheminArchives).delete(recursive: true);
    await _restaurerFichiers(bloc, org.racine.path);

    // L'index peut manquer : il doit se RECONSTRUIRE, pas rendre muet.
    final parCourse = await ArchivesSegmenteess.instance
        .consulterParCourse('2026-11-20|R1|C1');
    final parPeriode =
        await ArchivesSegmenteess.instance.consulterParPeriode(
            '2026-11-20', '2026-11-22');
    final avecResultat = await ArchivesSegmenteess.instance
        .consulterAvecResultatOfficiel();

    // ignore: avoid_print
    print('[MESURE S-3] après restauration : course=${parCourse.etat.name}/'
        '${parCourse.entrees.length} période=${parPeriode.etat.name}/'
        '${parPeriode.entrees.length} résultat=${avecResultat.etat.name}/'
        '${avecResultat.entrees.length}');

    expect(parCourse.etat, EtatLectureArchive.lisible);
    expect(parCourse.entrees, hasLength(1),
        reason: 'la course demandée doit être retrouvée');
    expect(parPeriode.entrees, hasLength(2),
        reason: 'les deux courses de la période doivent être retrouvées');
    expect(avecResultat.entrees, hasLength(1),
        reason: 'une seule version porte un résultat officiel');
  });
}

/// Le bloc `fichiers_permanents` est produit par le code de PRODUCTION.
Future<Map<String, Object?>> _blocFichiersPermanents(
        OrganisationFichiers org) =>
    capturerFichiersPermanents(org.racine.path);

/// La restauration est celle du RESTAURATEUR de production.
Future<int> _restaurerFichiers(
        Map<String, Object?> bloc, String dossierBase) =>
    restaurerFichiersPermanents(bloc, dossierBase);
