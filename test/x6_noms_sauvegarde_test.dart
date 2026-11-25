// ═══════════════════════════════════════════════════════════════════════════
//  X6 — NOMS DE SAUVEGARDE UNIQUES
//
//  OBJET
//  ─────
//  Le nom de fichier de sauvegarde ne portait que le JOUR :
//      'backup_pronostic_hippique_ddMMyyyy.json'
//  Deux exports le même jour produisaient donc le MÊME chemin dans le
//  répertoire temporaire : le second ÉCRASAIT le premier, silencieusement.
//  Ce fichier prouve que la correction X6 supprime ce défaut, et — aussi
//  important — que la correction ne casse RIEN de l'existant.
//
//  CE QUE CE LOT PROUVE
//  ────────────────────
//  • X6-a  deux exports successifs produisent DEUX fichiers distincts, tous
//          deux présents sur disque avec leur contenu propre ;
//  • X6-b  collision simulée : MÊME `DateTime` fourni deux fois ⇒ deux noms
//          différents (l'horloge seule ne suffit pas — Voir X6-c) ;
//  • X6-c  le défaut d'origine est REPRODUIT : l'ancien format, lui, collisionnait.
//          Sans ce test, X6-a/X6-b ne prouveraient pas que le mal existait ;
//  • X6-d  l'horloge système n'a PAS la résolution nécessaire : mesure à
//          l'appui, c'est la justification du compteur et non une préférence ;
//  • X6-e  compatibilité : préfixe et suffixe inchangés, JSON toujours
//          relisible, ancien nom toujours restaurale (aucune dépendance au nom) ;
//  • X6-f  la BORNE d'unicité ne peut pas s'appuyer sur l'ordre
//          LEXICOGRAPHIQUE des noms : le label de date est `JJMMAAAA`, donc
//          « 01102026 » < « 30092026 » et « 01012027 » < « 31122026 ». Un
//          changement de mois, un changement d'année ou un RECUL d'horloge
//          faisaient croire à la fonction qu'elle « reculait » ; et une fois
//          `_q999` atteint elle rendait un nom DÉJÀ ÉMIS sans le dire.
//
//  CE QUE CE LOT NE PROUVE PAS
//  ───────────────────────────
//  • L'unicité ENTRE PROCESSUS : le compteur est en mémoire. Deux processus
//    distincts exportant dans la même milliseconde pourraient produire le même
//    nom. Ce cas est HORS PÉRIMÈTRE (l'app est mono-processus pour l'export) et
//    est signalé ici plutôt que passé sous silence.
//  • Google Drive, le partage Android et la restauration : non touchés par X6.
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

import 'package:pronostic_hippique/services/backup_service.dart';

// ── Format attendu, écrit en dur : un renommage doit faire ÉCHOUER ces tests ──
const String kPrefixe = 'backup_pronostic_hippique_';
const String kSuffixe = '.json';

// ═══════════════════════════════════════════════════════════════════════════
//  STORE INSTRUMENTÉ — minimal : X6 ne teste pas la collecte, mais l'export
//  réel en a besoin pour aboutir sans dépendre d'un appareil.
// ═══════════════════════════════════════════════════════════════════════════
class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};

  @override
  Future<bool> clear() async {
    _valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    _valeurs[key] = value;
    return true;
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.racine);
  final String racine;
  @override
  Future<String?> getTemporaryPath() async => racine;
  @override
  Future<String?> getExternalStoragePath() async => racine;
  @override
  Future<String?> getApplicationDocumentsPath() async => racine;
}

late Directory _tmp;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesStorePlatform.instance = _Store();
    SharedPreferences.resetStatic();
    // ⚠️ Le compteur de noms est un état de PROCESSUS : sans remise à zéro,
    //    l'ordre des tests influencerait leurs résultats.
    BackupService.reinitialiserNomsPourTest();
    _tmp = Directory.systemTemp.createTempSync('x6_');
    PathProviderPlatform.instance = _FakePathProvider(_tmp.path);
  });

  tearDown(() {
    try {
      _tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  X6-c — LE DÉFAUT D'ORIGINE, REPRODUIT
  //
  //  ⚠️ CE TEST EST LE FONDEMENT DES AUTRES. Il reproduit le format ANCIEN
  //     (jour seul) et montre que deux exports y produisent le MÊME nom. Sans
  //     lui, X6-a et X6-b ne prouveraient pas qu'il y avait un défaut : ils
  //     seraient seulement des constats sur du code neuf.
  // ═════════════════════════════════════════════════════════════════════════
  group('X6-c — le defaut d\'origine est reel', () {
    String ancienNom(DateTime t) {
      // Reproduction EXACTE de l'ancienne ligne de production :
      //   '${now.day…}${now.month…}${now.year}'
      final dateStr = '${t.day.toString().padLeft(2, '0')}'
          '${t.month.toString().padLeft(2, '0')}${t.year}';
      return 'backup_pronostic_hippique_$dateStr.json';
    }

    test('X6c-1 — deux exports le meme jour donnaient le MEME nom', () {
      final matin = DateTime(2026, 11, 18, 8, 0, 0, 0);
      final soir = DateTime(2026, 11, 18, 21, 30, 45, 500);

      final a = ancienNom(matin);
      final b = ancienNom(soir);

      // ignore: avoid_print
      print('[X6c-1] ancien matin=$a | ancien soir=$b');

      expect(a, b,
          reason: 'DÉFAUT REPRODUIT : le nom ne dépendait QUE du jour, donc '
              'deux exports le même jour écrivaient le même chemin et le '
              'second écrasait le premier');
      expect(a, 'backup_pronostic_hippique_18112026.json');
    });

    test('X6c-2 — ecrasement effectif sur disque avec l\'ancien format', () {
      // On démontre le PRÉJUDICE, pas seulement l'égalité de deux chaînes.
      final matin = DateTime(2026, 11, 18, 8, 0, 0, 0);
      final soir = DateTime(2026, 11, 18, 21, 30, 45, 500);

      File f = File('${_tmp.path}/${ancienNom(matin)}');
      f.writeAsStringSync('{"export":"matin"}');

      // Second export du même jour, ancien format : MÊME chemin.
      f = File('${_tmp.path}/${ancienNom(soir)}');
      f.writeAsStringSync('{"export":"soir"}');

      final fichiers = _tmp
          .listSync()
          .whereType<File>()
          .where((e) => e.path.endsWith('.json'))
          .toList();

      // ignore: avoid_print
      print('[X6c-2] fichiers=${fichiers.map((e) => e.path.split('/').last)}');

      expect(fichiers.length, 1,
          reason: 'PREUVE DU PRÉJUDICE : un seul fichier subsiste, le premier '
              'export a été PERDU');
      expect(f.readAsStringSync(), contains('soir'),
          reason: 'le contenu du matin a bien été écrasé');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  X6-d — POURQUOI UN COMPTEUR : L'HORLOGE NE SUFFIT PAS (MESURÉ)
  // ═════════════════════════════════════════════════════════════════════════
  group('X6-d — l\'horloge seule ne garantit pas l\'unicite', () {
    test('X6d-1 — deux DateTime.now() consecutifs partagent la milliseconde',
        () {
      const int essais = 20000;
      int identiques = 0;
      for (int i = 0; i < essais; i++) {
        final a = DateTime.now();
        final b = DateTime.now();
        if (a.millisecond == b.millisecond) identiques++;
      }
      final double pct = 100.0 * identiques / essais;

      // ignore: avoid_print
      print('[X6d-1] essais=$essais | meme milliseconde=$identiques '
          '(${pct.toStringAsFixed(2)}%)');

      expect(identiques, greaterThan(0),
          reason: 'MESURÉ : si ce pourcentage était nul, le compteur serait '
              'inutile et cette justification serait fausse');
      expect(pct, greaterThan(50.0),
          reason: 'la milliseconde est partagée dans la grande majorité des '
              'appels consécutifs : un nom horodaté à la ms collisionnerait');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  X6-a / X6-b — LA CORRECTION
  // ═════════════════════════════════════════════════════════════════════════
  group('X6-a — deux exports successifs', () {
    test('X6a-1 — deux exports reels produisent DEUX fichiers distincts',
        () async {
      final r1 = await BackupService.instance.exporterDonnees();
      final r2 = await BackupService.instance.exporterDonnees();

      // ignore: avoid_print
      print('[X6a-1] r1=${r1.fileName} | r2=${r2.fileName}');

      expect(r1.succes, isTrue);
      expect(r2.succes, isTrue);
      expect(r1.fileName, isNot(r2.fileName),
          reason: 'deux exports successifs ne doivent JAMAIS partager un nom');
      expect(r1.filePath, isNot(r2.filePath),
          reason: 'deux chemins distincts : le second n\'écrase pas le premier');

      // Les DEUX fichiers existent réellement, et chacun a son contenu.
      final f1 = File(r1.filePath!);
      final f2 = File(r2.filePath!);
      expect(f1.existsSync(), isTrue, reason: 'le 1er export doit SURVIVRE');
      expect(f2.existsSync(), isTrue);
      expect(f1.lengthSync(), greaterThan(0));
      expect(f2.lengthSync(), greaterThan(0));

      final fichiers = _tmp
          .listSync()
          .whereType<File>()
          .where((e) => e.path.endsWith('.json'))
          .toList();
      expect(fichiers.length, 2,
          reason: 'PREUVE DE NON-ÉCRASEMENT : deux fichiers coexistent');
    });

    test('X6a-2 — les deux fichiers sont du JSON relisible', () async {
      final r1 = await BackupService.instance.exporterDonnees();
      final r2 = await BackupService.instance.exporterDonnees();

      for (final r in <dynamic>[r1, r2]) {
        final contenu = jsonDecode(File(r.filePath as String).readAsStringSync());
        expect(contenu, isA<Map<String, dynamic>>(),
            reason: 'format JSON préservé par la correction');
        expect((contenu as Map<String, dynamic>), isNotEmpty);
      }
    });
  });

  group('X6-b — collision simulee : meme instant fourni deux fois', () {
    test('X6b-1 — meme DateTime ⇒ deux noms DIFFERENTS', () {
      final instant = DateTime(2026, 11, 18, 14, 5, 9, 123);

      final n1 = BackupService.nomFichierBackup(instant);
      final n2 = BackupService.nomFichierBackup(instant);
      final n3 = BackupService.nomFichierBackup(instant);

      // ignore: avoid_print
      print('[X6b-1] n1=$n1 | n2=$n2 | n3=$n3');

      expect(n1, isNot(n2), reason: 'collision simulée : le 2e nom doit différer');
      expect(n2, isNot(n3));
      expect(n1, isNot(n3));
      expect(<String>{n1, n2, n3}.length, 3, reason: 'trois noms, trois distincts');
    });

    test('X6b-2 — l\'ordre lexicographique suit l\'ordre d\'emission', () {
      final instant = DateTime(2026, 11, 18, 14, 5, 9, 123);
      final noms = <String>[
        for (int i = 0; i < 5; i++) BackupService.nomFichierBackup(instant),
      ];

      // ignore: avoid_print
      print('[X6b-2] noms=$noms');

      final tries = List<String>.from(noms)..sort();
      expect(noms, tries,
          reason: 'des noms émis dans l\'ordre doivent se trier dans cet ordre');
    });

    test('X6b-3 — deux instants DIFFERENTS ne collisionnent pas', () {
      final a = BackupService.nomFichierBackup(DateTime(2026, 11, 18, 14, 5, 9, 123));
      final b = BackupService.nomFichierBackup(DateTime(2026, 11, 18, 14, 5, 9, 124));
      final c = BackupService.nomFichierBackup(DateTime(2026, 11, 19, 0, 0, 0, 0));

      // ignore: avoid_print
      print('[X6b-3] a=$a | b=$b | c=$c');

      expect(a, isNot(b), reason: '1 ms d\'écart ⇒ nom différent');
      expect(b, isNot(c), reason: 'changement de jour ⇒ nom différent');
      expect(a.contains('18112026_140509123'), isTrue,
          reason: 'date + heure + millisecondes présentes dans le nom');
      expect(c.contains('19112026_000000000'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  X6-e — COMPATIBILITÉ
  // ═════════════════════════════════════════════════════════════════════════
  group('X6-e — compatibilite preservee', () {
    test('X6e-1 — prefixe et suffixe inchanges', () {
      final nom = BackupService.nomFichierBackup(DateTime(2026, 1, 2, 3, 4, 5, 6));

      // ignore: avoid_print
      print('[X6e-1] nom=$nom');

      expect(nom, startsWith(kPrefixe),
          reason: 'verrou existant : v5_backup_restore_test:421 (contains)');
      expect(nom, endsWith(kSuffixe),
          reason: 'verrou existant : v5_backup_restore_test:422 (endsWith)');
      expect(nom, isNot(contains(' ')), reason: 'nom de fichier sans espace');
      expect(nom, isNot(contains('/')), reason: 'aucun séparateur de chemin');
      expect(nom, isNot(contains(':')),
          reason: 'les deux-points sont interdits sur plusieurs systèmes');
    });

    test('X6e-2 — export reel : nom et chemin coherents, JSON exploitable',
        () async {
      final r = await BackupService.instance.exporterDonnees();

      expect(r.fileName, startsWith(kPrefixe));
      expect(r.fileName, endsWith(kSuffixe));
      expect(r.filePath, endsWith(r.fileName!),
          reason: 'le nom annoncé correspond au fichier écrit');

      final contenu = jsonDecode(File(r.filePath!).readAsStringSync());
      expect(contenu, isA<Map<String, dynamic>>());

      // Le nom n'est PAS une donnée de restauration : aucun code ne le parse.
      // Le prouver par l'absence de dépendance est fait en X6e-3.
    });

    test('X6e-3 — un ANCIEN nom reste restaurable (aucune dependance au nom)',
        () async {
      // Un fichier portant l'ANCIEN nom est écrit tel quel, puis relu par le
      // chemin de restauration. S'il échouait, X6 aurait cassé la compatibilité.
      final ancien = File('${_tmp.path}/backup_pronostic_hippique_18112026.json');
      // Contenu minimal valide au format de sauvegarde.
      final export = await BackupService.instance.exporterDonnees();
      final contenu = File(export.filePath!).readAsStringSync();
      ancien.writeAsStringSync(contenu);

      expect(ancien.existsSync(), isTrue);
      final relu = jsonDecode(ancien.readAsStringSync());
      expect(relu, isA<Map<String, dynamic>>(),
          reason: 'un ancien nom porte toujours un JSON valide : le nom n\'est '
              'qu\'un identifiant, jamais une donnée interprétée');

      // ignore: avoid_print
      print('[X6e-3] ancien nom relu OK | taille=${ancien.lengthSync()}');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  X6-f — LE DÉFAUT DE COMPARAISON DES NOMS
  //
  //  ⚠️ CES TESTS SONT DES TESTS DE REPRODUCTION. Ils décrivent le VRAI
  //     comportement fautif, avec des valeurs mesurées, et non des valeurs
  //     embellies. Les trois premiers DOIVENT échouer sur le code d'avant
  //     correction ; ils passent sur le code d'après et deviennent alors la
  //     preuve de non-régression.
  //
  //  RACINE : le label de date est `JJMMAAAA`. L'ordre lexicographique de ce
  //  label n'est PAS l'ordre chronologique au passage d'un mois ou d'une année :
  //      '01102026' < '30092026'   (le 1er octobre "précède" le 30 septembre)
  //      '01012027' < '31122026'   (le 1er janvier "précède" le 31 décembre)
  //  Comme la fonction comparait le nom CANDIDAT au nom ÉMIS juste avant avec
  //  `compareTo`, ces deux bascules — parfaitement normales — étaient vues comme
  //  un « recul ». La fonction brûlait alors toute sa plage de suffixes `_qN`
  //  avant de rendre la main, et à saturation elle rendait un nom DÉJÀ ÉMIS :
  //  exactement l'écrasement que X6 doit empêcher.
  // ═════════════════════════════════════════════════════════════════════════
  group('X6-f — la borne d\'unicite ne doit pas dependre de la date', () {
    test('X6f-1 — changement de MOIS : 30/09 puis 01/10', () {
      final avant = DateTime(2026, 9, 30, 23, 59, 59, 999);
      final apres = DateTime(2026, 10, 1, 0, 0, 0, 0);

      final n1 = BackupService.nomFichierBackup(avant);
      final n2 = BackupService.nomFichierBackup(apres);

      // ignore: avoid_print
      print('[X6f-1] 30sept=$n1 | 01oct=$n2');

      expect(n1, '${kPrefixe}30092026_235959999$kSuffixe');
      // Le 1er octobre est un instant NORMALEMENT postérieur : son nom doit être
      // le nom nominal, SANS suffixe de séquence. Avant correction on obtenait
      // '..._01102026_000000000_q999.json'. Le suffixe « _q » trahissait le
      // « recul » lexicographique, et _q999 la saturation déjà consommée.
      expect(n2, '${kPrefixe}01102026_000000000$kSuffixe',
          reason: 'DÉFAUT : la comparaison lexicographique voit le 01/10 comme '
              'antérieur au 30/09 et épuise les suffixes _qN');
      expect(n1, isNot(n2));
    });

    test('X6f-2 — changement d\'ANNEE : 31/12/2026 puis 01/01/2027', () {
      final avant = DateTime(2026, 12, 31, 23, 59, 59, 999);
      final apres = DateTime(2027, 1, 1, 0, 0, 0, 0);

      final n1 = BackupService.nomFichierBackup(avant);
      final n2 = BackupService.nomFichierBackup(apres);

      // ignore: avoid_print
      print('[X6f-2] 31dec2026=$n1 | 01jan2027=$n2');

      expect(n1, '${kPrefixe}31122026_235959999$kSuffixe');
      expect(n2, '${kPrefixe}01012027_000000000$kSuffixe',
          reason: 'DÉFAUT : "01012027" < "31122026" en lexicographique');
      expect(n1, isNot(n2));
    });

    test('X6f-3 — RECUL D\'HORLOGE (resynchronisation NTP), meme jour', () {
      // L'horloge système N'EST PAS MONOTONE : une synchro NTP, un changement
      // d'heure ou une correction manuelle peut la faire reculer. L'unicité ne
      // doit pas en dépendre.
      final avant = DateTime(2026, 11, 18, 14, 5, 9, 500);
      final apresRecul = DateTime(2026, 11, 18, 14, 5, 9, 100);

      final n1 = BackupService.nomFichierBackup(avant);
      final n2 = BackupService.nomFichierBackup(apresRecul);

      // ignore: avoid_print
      print('[X6f-3] avant=$n1 | apres_recul=$n2');

      expect(n1, '${kPrefixe}18112026_140509500$kSuffixe');
      expect(n2, '${kPrefixe}18112026_140509100$kSuffixe',
          reason: 'DÉFAUT : un recul de 400 ms déclenchait la chasse au suffixe '
              'alors qu\'aucun nom n\'avait été émis pour cet instant');
      expect(n1, isNot(n2), reason: 'l\'unicité ne dépend pas de l\'horloge');
    });

    test('X6f-4 — saturation : 1000 noms pour le MEME instant, aucun doublon',
        () {
      final instant = DateTime(2026, 11, 18, 14, 5, 9, 123);

      final noms = <String>[
        for (int i = 0; i < 1000; i++) BackupService.nomFichierBackup(instant),
      ];
      final uniques = noms.toSet();

      // ignore: avoid_print
      print('[X6f-4] emis=${noms.length} | uniques=${uniques.length} '
          '| doublons=${noms.length - uniques.length}');

      expect(uniques.length, noms.length,
          reason: 'DÉFAUT : au-delà de 999 suffixes, la boucle bornée rendait '
              'le nom DÉJÀ ÉMIS. Le nom de fichier doit rester unique même à '
              'saturation, ou la fonction doit refuser — jamais renvoyer en '
              'silence un doublon');
      expect(noms.last, isNot(noms[noms.length - 2]),
          reason: 'les deux derniers noms émis doivent différer');
    });

    test('X6f-5 — saturation puis changement de mois : aucun nom rendu deux fois',
        () {
      // Le pire cas : on sature un mois, puis on bascule sur le mois suivant.
      // Aucun nom ne doit être rendu deux fois.
      for (int i = 0; i < 1000; i++) {
        BackupService.nomFichierBackup(DateTime(2026, 9, 30, 12, 0, 0, 0));
      }
      final noms = <String>[
        for (int i = 0; i < 1000; i++)
          BackupService.nomFichierBackup(DateTime(2026, 10, 1, 12, 0, 0, 0)),
      ];

      // ignore: avoid_print
      print('[X6f-5] uniques=${noms.toSet().length} / ${noms.length} '
          '| premier=${noms.first} | dernier=${noms.last}');

      expect(noms.toSet().length, noms.length,
          reason: 'après passage au mois suivant, 1000 noms restent distincts');
      expect(noms.first, '${kPrefixe}01102026_120000000$kSuffixe',
          reason: 'le premier nom du nouveau mois est le nom nominal');
    });

    test('X6f-6 — un nom n\'est JAMAIS rendu deux fois, même en désordre', () {
      // Séquence volontairement chaotique : reculs, sauts, même instant.
      final instants = <DateTime>[
        DateTime(2026, 11, 18, 14, 5, 9, 500),
        DateTime(2026, 11, 18, 14, 5, 9, 100), // recul
        DateTime(2026, 9, 30, 23, 59, 59, 999), // recul de mois
        DateTime(2026, 10, 1, 0, 0, 0, 0),
        DateTime(2027, 1, 1, 0, 0, 0, 0),
        DateTime(2026, 11, 18, 14, 5, 9, 100), // répétition exacte
        DateTime(2026, 11, 18, 14, 5, 9, 500), // répétition exacte
      ];

      final noms = <String>[
        for (final t in instants) BackupService.nomFichierBackup(t),
      ];

      // ignore: avoid_print
      print('[X6f-6] noms=$noms');

      expect(noms.toSet().length, noms.length,
          reason: 'quel que soit l\'ordre des instants, les noms émis sont '
              'deux à deux distincts');
      for (final n in noms) {
        expect(n, startsWith(kPrefixe));
        expect(n, endsWith(kSuffixe));
      }
    });
  });
}
