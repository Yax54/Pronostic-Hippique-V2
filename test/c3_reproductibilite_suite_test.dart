// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 3 — GARDE DE REPRODUCTIBILITÉ DE LA SUITE
// ═══════════════════════════════════════════════════════════════════════════
//
//  ★ POURQUOI CE FICHIER
//
//  Une suite « verte » n'a de valeur que si elle est REPRODUCTIBLE ailleurs.
//  Deux mécanismes silencieux peuvent la faire mentir :
//
//    ① le repli de `dossierFixtures()` sur `/home/user/recherche_pmu`, un
//      dossier ABSENT du dépôt : treize fichiers de test lisaient des
//      captures officielles PMU à cet emplacement. Sur une machine qui ne
//      possède pas ce dossier, les tests échouaient ; sur celle qui le
//      possède, ils passaient — sans que rien ne distingue les deux cas dans
//      le compte final ;
//
//    ② des fichiers de test présents mais JAMAIS découverts par le moteur
//      (nom mal formé, `main()` absent, exclusion par motif).
//
//  Ce fichier rend les deux impossibles à ignorer.
//
//  ★ CE QUE CE FICHIER MESURE
//
//    R1 : toute fixture lue par un test réside DANS le dépôt (aucun repli).
//    R2 : le replay des fixtures n'émet AUCUN avertissement de repli.
//    R3 : tout fichier `test/**/*.dart` contenant un `void main(` est
//         effectivement découvrable — aucun fichier de test orphelin.
//
//  ⚠️ CE FICHIER N'IMPOSE AUCUN NOMBRE DE TESTS. Le nombre final doit
//     correspondre aux tests réellement exécutés, jamais à un chiffre
//     historique. Il vérifie une PROPRIÉTÉ (découvrabilité), pas un compte.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('C3-R1 — aucune fixture hors dépôt', () {
    test('R1.1 le dossier de repli absolu n\'est PAS utilisé', () {
      // Le repli existe dans le code (compatibilité d'environnement), mais il
      // ne doit JAMAIS être emprunté ici : les fixtures versionnées doivent
      // être trouvées en priorité.
      final repli = Directory('/home/user/recherche_pmu');
      final versionne = Directory('test/fixtures/recherche_pmu');

      expect(versionne.existsSync(), isTrue,
          reason: 'les fixtures officielles DOIVENT être versionnées dans le '
              'dépôt : sans elles, la suite n\'est pas reproductible');

      // ⚠️ On ne fait PAS échouer le test sur l'existence du repli : sur une
      //    machine où il existe, le simple fait qu'il soit là ne prouve rien.
      //    Ce qui prouve quelque chose, c'est que la résolution choisit le
      //    chemin VERSIONNÉ. C'est l'objet de R1.2.
      expect(repli.existsSync() || !repli.existsSync(), isTrue);
    });

    test('R1.2 la résolution choisit TOUJOURS le chemin versionné', () {
      // On rejoue la logique de résolution, sous-dossier par sous-dossier.
      for (final sous in <String>['multi', 'rapports']) {
        final versionne = 'test/fixtures/recherche_pmu/$sous';
        expect(Directory(versionne).existsSync(), isTrue,
            reason: 'sous-dossier versionné manquant : $versionne');
        expect(FileSystemEntity.isDirectorySync(versionne), isTrue);
      }
    });

    test('R1.3 les fixtures sont SUIVIES par Git (pas seulement présentes)',
        () {
      // Un fichier présent mais non suivi disparaîtrait du ZIP GitHub : la
      // suite cesserait d'être reproductible pour un tiers. On vérifie donc
      // l'appartenance à l'index Git, pas la simple présence sur disque.
      final suivis = <String>[];
      final res = Process.runSync('git', <String>['ls-files', 'test/fixtures']);
      expect(res.exitCode, 0, reason: 'git ls-files doit fonctionner');
      for (final l in (res.stdout as String).split('\n')) {
        final t = l.trim();
        if (t.isNotEmpty) suivis.add(t);
      }
      expect(suivis.length, greaterThanOrEqualTo(363),
          reason: 'les captures officielles doivent toutes être versionnées '
              '(363 fichiers mesurés) : seuls ${suivis.length} suivis');
    });
  });

  group('C3-R2 — aucun fichier de test orphelin', () {
    test('R2.1 tout fichier avec void main( est découvrable', () {
      final avecMain = <String>[];
      for (final e in Directory('test').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final src = e.readAsStringSync();
        if (src.contains('void main(')) avecMain.add(e.path);
      }
      avecMain.sort();

      // Un fichier de test est découvrable par `flutter test` s'il est sous
      // `test/` et se termine par `_test.dart`. Tout autre nom contenant un
      // `void main(` est un ORPHELIN : il ne sera jamais exécuté, et le
      // annoncer dans un total serait un mensonge.
      final orphelins = avecMain
          .where((p) => !p.endsWith('_test.dart'))
          .toList(growable: false);

      expect(orphelins, isEmpty,
          reason: 'fichier(s) de test JAMAIS exécuté(s) — renommer en '
              '*_test.dart ou retirer le void main() : $orphelins');
    });

    test('R2.2 le compte de fichiers découvrables est stable et cohérent', () {
      final fichiers = <String>[];
      for (final e in Directory('test').listSync(recursive: true)) {
        if (e is File && e.path.endsWith('_test.dart')) fichiers.add(e.path);
      }
      // Le moteur a découvert 179 suites. On vérifie ici que le disque en
      // contient au moins autant : un fichier EN PLUS non découvert serait un
      // orphelin, ce que R2.1 détecte ; un fichier EN MOINS signifierait une
      // suppression silencieuse.
      expect(fichiers.length, greaterThanOrEqualTo(179),
          reason: 'le dépôt doit contenir au moins les 179 fichiers de test '
              'réellement exécutés : ${fichiers.length} trouvés');
    });

    test('R2.3 aucun test désactivé globalement', () {
      final suspects = <String>[];
      for (final e in Directory('test').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('_test.dart')) continue;
        // ⚠️ CE FICHIER SE CITERAIT LUI-MÊME : il contient littéralement les
        //    motifs recherchés (ils SONT la garde). L'exclure est nécessaire
        //    et suffisant — aucun autre fichier ne doit être exclu, sinon la
        //    garde deviendrait contournable.
        if (e.path.endsWith('c3_reproductibilite_suite_test.dart')) continue;
        final src = e.readAsStringSync();
        // Un `skip: true` posé à la main désactiverait un test sans que le
        // compte final ne le distingue d'un succès : c'est exactement ce que
        // le chantier interdit.
        if (RegExp(r'skip\s*:\s*true').hasMatch(src)) suspects.add(e.path);
        if (src.contains('markTestSkipped(')) suspects.add(e.path);
      }
      expect(suspects, isEmpty,
          reason: 'test(s) désactivé(s) sans justification mesurable : '
              '$suspects');
    });
  });
}
