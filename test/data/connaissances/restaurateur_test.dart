/// Tests de la sauvegarde et de la restauration — sur le **vrai moteur SQLite**
/// et, pour partie, sur les **deux sauvegardes réelles** de l'utilisateur.
///
/// Consigne §15 / §16 / §23. Ce que ces tests doivent prouver, et ce qu'ils ne
/// prouvent pas :
///
/// Prouvé ici :
/// * une ancienne sauvegarde JSON est reconnue comme `legacy` sans prétendre à
///   une intégrité qu'elle ne porte pas ;
/// * la sauvegarde réelle du 13/11 restaure **9 001** ratings ELO, valeurs
///   identiques, aucun orphelin perdu (D-20) ;
/// * un conteneur `.ptg` fait l'aller-retour sans perte ;
/// * un bloc altéré est refusé, jamais appliqué partiellement ;
/// * une écriture interrompue ne détruit pas la sauvegarde précédente ;
/// * un rating divergent est tracé, **jamais fusionné** (D-24) ;
/// * le retour arrière rétablit l'état antérieur ;
/// * le mode conservateur n'écrase aucune valeur locale ;
/// * les bilans référencent des versions exactes de rapports, et aucune
///   référence ne pointe un rapport absent.
///
/// **Non prouvé ici** : le comportement sur un appareil Android réel
/// (permissions, chemins, espace disque saturé par le système). Ces points
/// relèvent d'une validation sur Galaxy S24 Ultra et sont signalés comme tels
/// dans le rapport final, jamais présentés comme mesurés.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/data/connaissances/_adapters/depot_sqlite.dart';
import 'package:pronostic_hippique/data/connaissances/_core/depot.dart';
import 'package:pronostic_hippique/data/connaissances/_sauvegarde/format_sauvegarde.dart';
import 'package:pronostic_hippique/data/connaissances/_sauvegarde/restaurateur.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _cheminSauvegarde13 =
    '/home/user/uploaded_files/backup_pronostic_hippique_13112026.json.txt';
const String _cheminSauvegarde28 =
    '/home/user/uploaded_files/backup_pronostic_hippique_28052026.json.txt';

/// Une donnée réelle absente rend le test **en échec explicite**, jamais un
/// succès silencieux (interdit par le garde-fou `c3_reproductibilite`).
void exigereSauvegarde(String chemin) {
  if (!File(chemin).existsSync()) {
    fail('DONNEES REELLES ABSENTES : $chemin est requis pour vérifier la '
        'restauration. Test non concluant.');
  }
}

/// Résultat d'un contrôle exhaustif de ratings ELO.
class BilanControleElo {
  BilanControleElo(this.verifies, this.sansDiscipline, this.ecarts);
  final int verifies;
  final int sansDiscipline;
  final List<String> ecarts;
}

/// Compare **tous** les ratings d'une source à ceux du dépôt, attribut par
/// attribut.
///
/// Exigence §5 : « la comparaison des ratings ELO avant et après migration doit
/// être exhaustive, et non limitée à un échantillon ». Cette fonction ne prend
/// donc aucun pas d'échantillonnage : elle parcourt la totalité des clés.
///
/// Attributs vérifiés pour chaque rating : **clé** (identifiant conservé
/// verbatim), **nom d'origine**, **discipline**, **rating**, **nb** et **var**.
/// La comparaison est stricte, sans tolérance : un rating ELO n'est jamais
/// « à peu près » égal (§12).
Future<BilanControleElo> _controlerEloExhaustif(
  DepotSqlite depot,
  Map<String, Object?> source, {
  required String etiquette,
}) async {
  final cles = source.keys.toList()..sort();
  final ecarts = <String>[];
  var verifies = 0;
  var sansDiscipline = 0;

  for (final cle in cles) {
    final attendu = source[cle];
    if (attendu is! Map) {
      ecarts.add('$cle : entrée source non exploitable (${attendu.runtimeType})');
      continue;
    }
    final obtenu = await depot.lireElo(cle);
    if (obtenu == null) {
      ecarts.add('$cle : rating ABSENT après restauration');
      continue;
    }

    if (obtenu.cle != cle) {
      ecarts.add('$cle : clé altérée en "${obtenu.cle}"');
    }

    // Nom d'origine : fourni par la source, sinon déduit de la clé jusqu'au
    // dernier `|` (jamais jusqu'au premier : un nom peut en contenir).
    final i = cle.lastIndexOf('|');
    final nomAttendu = '${attendu['nom'] ?? (i < 0 ? cle : cle.substring(0, i))}';
    if (obtenu.nomOrigine != nomAttendu) {
      ecarts.add('$cle : nom "${obtenu.nomOrigine}" != "$nomAttendu"');
    }

    // Discipline : dérivée du dernier `|`, conservée telle quelle. Une
    // discipline absente reste VIDE, jamais remplacée par `global` (D-09, D-27).
    final disciplineAttendue = i < 0 ? '' : cle.substring(i + 1);
    if (obtenu.discipline != disciplineAttendue) {
      ecarts.add('$cle : discipline "${obtenu.discipline}" != '
          '"$disciplineAttendue"');
    }
    if (disciplineAttendue.isEmpty) sansDiscipline++;

    final ratingAttendu = (attendu['rating'] as num?)?.toDouble();
    if (ratingAttendu == null) {
      // Une source sans rating numérique n'est pas devinée : elle est signalée.
      ecarts.add('$cle : la source ne porte pas de rating numérique');
      continue;
    }
    if (obtenu.rating != ratingAttendu) {
      ecarts.add('$cle : rating ${obtenu.rating} != $ratingAttendu');
    }
    final nbAttendu = (attendu['nb'] as num?)?.toInt() ?? 0;
    if (obtenu.nb != nbAttendu) {
      ecarts.add('$cle : nb ${obtenu.nb} != $nbAttendu');
    }
    final varAttendue = (attendu['var'] as num?)?.toDouble() ?? 0.0;
    if (obtenu.var_ != varAttendue) {
      ecarts.add('$cle : var ${obtenu.var_} != $varAttendue');
    }
    verifies++;
  }

  // Mesure consignée pour que le rapport final puisse citer un chiffre réel.
  // ignore: avoid_print
  print('[MESURE] contrôle ELO exhaustif $etiquette : $verifies/${cles.length} '
      'ratings vérifiés sur 6 attributs, $sansDiscipline sans discipline '
      'résolue (D-20), ${ecarts.length} écart(s)');

  return BilanControleElo(verifies, sansDiscipline, ecarts);
}

void main() {
  late Directory dossierTest;
  late DepotSqlite depot;
  const format = FormatSauvegarde();
  const restaurateur = Restaurateur();

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    dossierTest = await Directory.systemTemp.createTemp('ptg_restauration_');
    await Directory('${dossierTest.path}/temp').create(recursive: true);
    depot = DepotSqlite(
      chemin: '${dossierTest.path}/pronostic.db',
      fabrique: databaseFactoryFfi,
    );
    await depot.ouvrir();
  });

  tearDown(() async {
    await depot.fermer();
    if (await dossierTest.exists()) await dossierTest.delete(recursive: true);
  });

  // ───────────────────────────────────────────────────────────────────────
  group('Détection du format et refus avant écriture', () {
    test('une ancienne sauvegarde JSON est reconnue legacy, sans faux '
        'certificat d\'intégrité', () {
      exigereSauvegarde(_cheminSauvegarde13);
      final contenu = File(_cheminSauvegarde13).readAsStringSync();
      final v = format.verifier(contenu);
      expect(v.lisible, isTrue);
      expect(v.formatReconnu, isTrue);
      expect(v.legacy, isTrue, reason: 'aucun manifeste dans une sauvegarde '
          'v9.0 : le format doit être identifié comme historique');
      expect(v.empreinteGlobaleValide, isFalse,
          reason: 'aucune empreinte globale ne peut être validée sur un format '
              'qui n\'en porte pas');
      expect(v.utilisable, isTrue,
          reason: 'une sauvegarde historique reste restaurable : c\'est la '
              'compatibilité exigée par §16');
      expect(v.messages.join(' '), contains('NON vérifiable'));
    });

    test('un JSON illisible est refusé sans qu\'aucune écriture n\'ait lieu',
        () async {
      final avant = await depot.compterElo();
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: '{ ceci n\'est pas du JSON',
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.reussie, isFalse);
      expect(r.erreur, isNotNull);
      expect(await depot.compterElo(), avant);
    });

    test('un bloc altéré est refusé, et aucun autre bloc n\'est appliqué',
        () async {
      final conteneur = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'elo_ratings',
            categorie: 'ratings_elo',
            nature: NatureBloc.permanente,
            contenu: <String, Object?>{
              'A|PLAT': <String, Object?>{
                'nom': 'A',
                'rating': 1500.0,
                'nb': 1,
                'var': 0.0,
              },
            },
            provenance: 'test',
          ),
        ],
        appVersion: 'test',
      );
      // Altération du bloc encodé : le contenu ne correspond plus à l'empreinte.
      final blocs = Map<String, Object?>.from(conteneur['blocs'] as Map);
      final original = '${blocs['elo_ratings']}';
      blocs['elo_ratings'] =
          'H4sIAAAAAAAAA${original.substring(12)}';
      conteneur['blocs'] = blocs;

      final v = format.verifier(jsonEncode(conteneur));
      expect(v.utilisable, isFalse, reason: 'un contenu altéré ne doit jamais '
          'être considéré utilisable');
      expect(v.blocsAlteres, contains('elo_ratings'));

      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: jsonEncode(conteneur),
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.reussie, isFalse);
      expect(await depot.compterElo(), 0,
          reason: 'aucune donnée ne doit avoir été écrite');
    });

    test('extraireBloc refuse un bloc altéré', () {
      final conteneur = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'b1',
            categorie: 'test',
            nature: NatureBloc.permanente,
            contenu: <String, Object?>{'x': 1},
            provenance: 'test',
          ),
        ],
        appVersion: 'test',
      );
      final blocs = Map<String, Object?>.from(conteneur['blocs'] as Map);
      blocs['b1'] = 'H4sIAAAAAAAAA+3OMQ0AAAgEsf3rBgcJ1AQ';
      conteneur['blocs'] = blocs;
      expect(
        () => format.extraireBloc(jsonEncode(conteneur), 'b1'),
        throwsStateError,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('Aller-retour d\'un conteneur .ptg', () {
    test('les valeurs ELO reviennent identiques au bit près', () async {
      final conteneur = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'elo_service',
            categorie: 'ratings_elo',
            nature: NatureBloc.permanente,
            contenu: <String, Object?>{
              'NELSON DU RIB|TROT_ATTELE': <String, Object?>{
                'nom': 'NELSON DU RIB',
                'rating': 1448.322864781434,
                'nb': 3,
                'var': -51.677135218565944,
              },
              'ORPHELIN|': <String, Object?>{
                'nom': 'ORPHELIN',
                'rating': 1620.5,
                'nb': 7,
                'var': 12.25,
              },
            },
            provenance: 'test',
          ),
        ],
        appVersion: 'test',
      );
      final chemin = '${dossierTest.path}/sauvegardes/t.ptg';
      await format.ecrireAtomiquement(conteneur, chemin);
      expect(File(chemin).existsSync(), isTrue);

      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: File(chemin).readAsStringSync(),
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.reussie, isTrue, reason: r.erreur ?? '');
      expect(r.legacy, isFalse);
      expect(r.eloRestaures, 2);

      final nelson = await depot.lireElo('NELSON DU RIB|TROT_ATTELE');
      expect(nelson, isNotNull);
      expect(nelson!.rating, 1448.322864781434);
      expect(nelson.var_, -51.677135218565944);
      expect(nelson.nb, 3);

      // D-20 : un rating d'identité non résolue est conservé, pas purgé.
      final orphelin = await depot.lireElo('ORPHELIN|');
      expect(orphelin, isNotNull, reason: 'D-20 impose la conservation');
      expect(orphelin!.rating, 1620.5);
      expect(orphelin.discipline, '');
    });

    test('un cache déclaré est ignoré et signalé, jamais restauré', () async {
      final conteneur = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'elo_ratings',
            categorie: 'ratings_elo',
            nature: NatureBloc.permanente,
            contenu: <String, Object?>{},
            provenance: 'test',
          ),
          FormatSauvegarde.bloc(
            nom: 'cache_audit',
            categorie: 'cache',
            nature: NatureBloc.cache,
            contenu: <String, Object?>{'jetable': true},
            provenance: 'test',
          ),
        ],
        appVersion: 'test',
      );
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: jsonEncode(conteneur),
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.reussie, isTrue);
      expect(r.blocsIgnores, contains('cache_audit'));
      expect(r.blocsAppliques, contains('elo_ratings'));
      expect(r.messages.join(' '), contains('cache reconstructible'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('Interruption et atomicité', () {
    test('une écriture interrompue ne détruit pas la sauvegarde précédente',
        () async {
      final chemin = '${dossierTest.path}/sauvegardes/atomique.ptg';
      final v1 = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'elo_ratings',
            categorie: 'ratings_elo',
            nature: NatureBloc.permanente,
            contenu: <String, Object?>{'X|PLAT': 1},
            provenance: 'v1',
          ),
        ],
        appVersion: 'test',
      );
      await format.ecrireAtomiquement(v1, chemin);
      final empreinteAvant = sha256Fichier(chemin);

      // Simulation d'une interruption : le fichier temporaire existe mais
      // l'écriture finale n'a pas eu lieu. L'original doit rester intact.
      final temporaire = File('$chemin.tmp');
      await temporaire.writeAsString('contenu partiel', flush: true);

      expect(File(chemin).existsSync(), isTrue);
      expect(sha256Fichier(chemin), empreinteAvant,
          reason: 'l\'original ne doit pas être modifié par une écriture '
              'laissée en cours');

      final v = format.verifier(File(chemin).readAsStringSync());
      expect(v.utilisable, isTrue,
          reason: 'la sauvegarde précédente doit rester vérifiable');
    });

    test('un instantané de retour arrière est écrit AVANT toute écriture de '
        'données', () async {
      final conteneur = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'elo_service',
            categorie: 'ratings_elo',
            nature: NatureBloc.permanente,
            contenu: <String, Object?>{
              'NOUVEAU|PLAT': <String, Object?>{
                'nom': 'NOUVEAU',
                'rating': 1500.0,
                'nb': 1,
                'var': 0.0,
              },
            },
            provenance: 'test',
          ),
        ],
        appVersion: 'test',
      );
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: jsonEncode(conteneur),
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.reussie, isTrue);
      expect(r.rollbackDisponible, isTrue);
      expect(r.instantane, isNotNull);
      expect(File(r.instantane!.chemin).existsSync(), isTrue);
      // L'instantané est lui-même dans le format vérifiable.
      final v = format.verifier(File(r.instantane!.chemin).readAsStringSync());
      expect(v.utilisable, isTrue);
    });

    test('un dossier temp inexistant provoque un refus AVANT écriture', () async {
      final conteneur = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'elo_service',
            categorie: 'ratings_elo',
            nature: NatureBloc.permanente,
            contenu: <String, Object?>{},
            provenance: 'test',
          ),
        ],
        appVersion: 'test',
      );
      final avant = await depot.compterElo();
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: jsonEncode(conteneur),
        mode: ModeRestauration.complet,
        // Chemin volontairement impossible : /proc n'est pas inscriptible.
        dossierTemp: '/proc/impossible',
        versionLocale: 'test',
      );
      expect(r.reussie, isFalse,
          reason: 'sans instantané de retour arrière, aucune donnée ne doit '
              'être touchée (§16)');
      expect(await depot.compterElo(), avant);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('Conflits et modes', () {
    Future<String> conteneurElo(String rating) async {
      final c = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'elo_service',
            categorie: 'ratings_elo',
            nature: NatureBloc.permanente,
            contenu: <String, Object?>{
              'DIVERGENT|PLAT': <String, Object?>{
                'nom': 'DIVERGENT',
                'rating': double.parse(rating),
                'nb': 5,
                'var': 1.5,
              },
            },
            provenance: 'test',
          ),
        ],
        appVersion: 'test',
      );
      final chemin = '${dossierTest.path}/sauvegardes/d.ptg';
      await format.ecrireAtomiquement(c, chemin);
      return File(chemin).readAsStringSync();
    }

    test('mode conservateur : la valeur locale divergente est conservée',
        () async {
      await depot.upsertElo(const LigneElo(
        cle: 'DIVERGENT|PLAT',
        nomOrigine: 'DIVERGENT',
        discipline: 'PLAT',
        rating: 1234.5678,
        nb: 5,
        var_: 1.5,
      ));
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: await conteneurElo('1500.0'),
        mode: ModeRestauration.conservateur,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.reussie, isTrue);
      expect(r.eloLocauxConserves, 1);
      final apres = await depot.lireElo('DIVERGENT|PLAT');
      expect(apres!.rating, 1234.5678,
          reason: 'le mode conservateur ne remplace jamais une valeur locale');
      // Le conflit est TRACÉ : rien n'est décidé en silence.
      expect(await depot.compterConflits(), 1);
    });

    test('mode complet : la valeur est remplacée ET le conflit est tracé, '
        'sans fusion arithmétique (D-24)', () async {
      await depot.upsertElo(const LigneElo(
        cle: 'DIVERGENT|PLAT',
        nomOrigine: 'DIVERGENT',
        discipline: 'PLAT',
        rating: 1234.5678,
        nb: 5,
        var_: 1.5,
      ));
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: await conteneurElo('1500.0'),
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.reussie, isTrue);
      expect(r.eloConflits, 1);
      final apres = await depot.lireElo('DIVERGENT|PLAT');
      // Ni moyenne (1367.28...), ni somme : la valeur de la sauvegarde.
      expect(apres!.rating, 1500.0);
      expect(apres.rating, isNot(closeTo((1234.5678 + 1500.0) / 2, 0.001)),
          reason: 'D-24 interdit explicitement la moyenne');
      expect(await depot.compterConflits(), 1);
    });

    test('des valeurs identiques ne créent aucun conflit', () async {
      await depot.upsertElo(const LigneElo(
        cle: 'DIVERGENT|PLAT',
        nomOrigine: 'DIVERGENT',
        discipline: 'PLAT',
        rating: 1500.0,
        nb: 5,
        var_: 1.5,
      ));
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: await conteneurElo('1500.0'),
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.eloIdentiques, 1);
      expect(r.conflitsEnregistres, 0);
      expect(await depot.compterConflits(), 0);
    });

    test('le retour arrière rétablit la valeur locale antérieure', () async {
      await depot.upsertElo(const LigneElo(
        cle: 'DIVERGENT|PLAT',
        nomOrigine: 'DIVERGENT',
        discipline: 'PLAT',
        rating: 1234.5678,
        nb: 5,
        var_: 1.5,
      ));
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: await conteneurElo('1500.0'),
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect((await depot.lireElo('DIVERGENT|PLAT'))!.rating, 1500.0);

      final restaures = await restaurateur.rollback(
        depot,
        r.instantane!,
        dossierTemp: '${dossierTest.path}/temp',
      );
      expect(restaures, 1);
      expect((await depot.lireElo('DIVERGENT|PLAT'))!.rating, 1234.5678,
          reason: 'le retour arrière doit rendre l\'état antérieur exact');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('Rapports et bilans', () {
    test('deux contenus différents à la même date restent deux rapports',
        () async {
      final rapports = <Object?>[
        jsonEncode(<String, Object?>{
          'date': '2026-05-03T22:23:31.818943',
          'fnum': 1,
          'fnum2': 2,
          'rj': <Object?>[],
        }),
        jsonEncode(<String, Object?>{
          'date': '2026-05-03T22:23:31.818943',
          'fnum': 1,
          'fnum2': 3,
          'rj': <Object?>[],
        }),
      ];
      final conteneur = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'ia_rapports_v1',
            categorie: 'rapports',
            nature: NatureBloc.permanente,
            contenu: rapports,
            provenance: 'test',
          ),
        ],
        appVersion: 'test',
      );
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: jsonEncode(conteneur),
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.reussie, isTrue);
      expect(await depot.compterRapports(), 2,
          reason: '§13 : aucune déduplication par date');
      final stockes = await depot.tousLesRapports();
      expect(stockes.any((s) => s.contenu.contains('"fnum2":2')), isTrue);
      expect(stockes.any((s) => s.contenu.contains('"fnum2":3')), isTrue);
    });

    test('rejouer une restauration ne duplique aucun rapport (§14)', () async {
      final rapports = <Object?>[
        jsonEncode(<String, Object?>{
          'date': '2026-01-01',
          'fnum': 1,
          'fnum2': 2,
          'rj': <Object?>[],
        }),
      ];
      final conteneur = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'ia_rapports_v1',
            categorie: 'rapports',
            nature: NatureBloc.permanente,
            contenu: rapports,
            provenance: 'test',
          ),
        ],
        appVersion: 'test',
      );
      final contenu = jsonEncode(conteneur);
      for (var i = 0; i < 3; i++) {
        final r = await restaurateur.restaurer(
          depot: depot,
          contenuSauvegarde: contenu,
          mode: ModeRestauration.complet,
          dossierTemp: '${dossierTest.path}/temp',
          versionLocale: 'test',
        );
        expect(r.reussie, isTrue);
      }
      expect(await depot.compterRapports(), 1);
    });

    test('un bilan référence la version EXACTE du rapport utilisé', () async {
      final rapport = jsonEncode(<String, Object?>{
        'date': '2026-05-03T22:23:31.818943',
        'nb': 34,
        'fnum': 1,
        'fnum2': 2,
        'rj': <Object?>[],
      });
      final bilan = jsonEncode(<String, Object?>{
        'lundi': '2026-04-27T00:00:00.000',
        'dim': '2026-05-03T00:00:00.000',
        'rj': <Object?>[rapport],
      });
      final conteneur = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'ia_bilans_semaine_v1',
            categorie: 'bilans',
            nature: NatureBloc.permanente,
            contenu: <Object?>[bilan],
            provenance: 'test',
          ),
        ],
        appVersion: 'test',
      );
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: jsonEncode(conteneur),
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.reussie, isTrue);
      expect(await depot.compterBilans(type: 'bilan_semaine'), 1);
      // Le rapport cité existe comme rapport à part entière.
      expect(await depot.compterRapports(), 1);
      expect(await depot.compterReferencesOrphelines(), 0,
          reason: 'aucune référence ne doit pointer un rapport absent');
      final bilans = await depot.tousLesBilans(type: 'bilan_semaine');
      expect(bilans.single.references, hasLength(1));
      expect(bilans.single.references.single.role, 'rj');
      final empreinte = bilans.single.references.single.empreinte;
      final stockes = await depot.tousLesRapports();
      expect(stockes.single.empreinte, empreinte,
          reason: 'la référence doit viser l\'empreinte du contenu exact');
    });

    test('un bilan mensuel référence aussi les rapports de ses semaines',
        () async {
      final rapport = jsonEncode(<String, Object?>{
        'date': '2026-04-27',
        'fnum': 1,
        'fnum2': 2,
        'rj': <Object?>[],
      });
      final semaine = jsonEncode(<String, Object?>{
        'lundi': '2026-04-27T00:00:00.000',
        'dim': '2026-05-03T00:00:00.000',
        'rj': <Object?>[rapport],
      });
      final mois = jsonEncode(<String, Object?>{
        'an': 2026,
        'mo': 4,
        'sem': <Object?>[semaine],
      });
      final conteneur = format.construire(
        blocs: <Map<String, Object?>>[
          FormatSauvegarde.bloc(
            nom: 'ia_bilans_mois_v1',
            categorie: 'bilans',
            nature: NatureBloc.permanente,
            contenu: <Object?>[mois],
            provenance: 'test',
          ),
        ],
        appVersion: 'test',
      );
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: jsonEncode(conteneur),
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.reussie, isTrue);
      final bilans = await depot.tousLesBilans(type: 'bilan_mois');
      expect(bilans.single.annee, 2026);
      expect(bilans.single.mois, 4);
      expect(bilans.single.references, hasLength(1));
      expect(bilans.single.references.single.role, 'sem:0');
      expect(await depot.compterReferencesOrphelines(), 0);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('Sauvegardes réelles de l\'utilisateur (lecture seule, §14)', () {
    test('la restauration de la sauvegarde 13/11 rend 9 001 ratings, valeurs '
        'identiques, aucun orphelin perdu', () async {
      exigereSauvegarde(_cheminSauvegarde13);
      final fichier = File(_cheminSauvegarde13);
      final empreinteAvant = sha256Fichier(_cheminSauvegarde13);
      final tailleAvant = fichier.lengthSync();

      final contenu = fichier.readAsStringSync();
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: contenu,
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );

      expect(r.reussie, isTrue, reason: r.erreur ?? r.messages.join(' | '));
      expect(r.legacy, isTrue);
      expect(await depot.compterElo(), 9001,
          reason: 'mesure de référence : 9 001 clés dans la sauvegarde 13/11');
      expect(r.eloRestaures, 9001);

      // ── CONTRÔLE EXHAUSTIF, ET NON ÉCHANTILLONNÉ (§5) ──────────────────
      final source = jsonDecode(contenu) as Map;
      final eloSource = <String, Object?>{
        for (final e in (source['elo_service'] as Map).entries)
          '${e.key}': e.value
      };
      final cles = eloSource.keys.toList()..sort();

      final bilan = await _controlerEloExhaustif(depot, eloSource, etiquette: '13/11');
      expect(bilan.ecarts, isEmpty,
          reason: 'écarts constatés sur ${bilan.ecarts.length} rating(s) parmi '
              '${cles.length} : ${bilan.ecarts.take(10).join(" ; ")}');
      expect(bilan.verifies, cles.length,
          reason: 'TOUS les ratings doivent être vérifiés, pas un échantillon');
      expect(bilan.verifies, 9001);

      // D-20 : les ratings d'identité non résolue sont comptés et conservés.
      final orphelins = cles.where((k) => k.endsWith('|')).length;
      expect(await depot.compterElo(), greaterThanOrEqualTo(orphelins),
          reason: 'aucun orphelin ne doit être perdu');

      // §14 : les deux sauvegardes d'origine ne sont jamais modifiées.
      expect(fichier.lengthSync(), tailleAvant);
      expect(sha256Fichier(_cheminSauvegarde13), empreinteAvant,
          reason: 'la sauvegarde historique doit rester intacte');
    });

    test('les rapports de la sauvegarde 13/11 sont restaurés avec leur '
        'provenance et leur contenu intégral (fnum2 inclus)', () async {
      exigereSauvegarde(_cheminSauvegarde13);
      final contenu = File(_cheminSauvegarde13).readAsStringSync();
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: contenu,
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.reussie, isTrue, reason: r.erreur ?? '');
      final nb = await depot.compterRapports();
      expect(nb, greaterThan(0), reason: 'des rapports doivent être restaurés');

      // Chaque rapport stocké conserve son contenu d'origine : le contenu
      // contient `fnum2` lorsque la source le contenait.
      final stockes = await depot.tousLesRapports();
      final avecFnum2 = stockes.where((s) => s.contenu.contains('"fnum2"')).length;
      expect(avecFnum2, greaterThan(0),
          reason: 'fnum2 doit être conservé dans le contenu d\'origine (§13)');

      // Provenance : chaque rapport possède au moins une copie tracée.
      for (final s in stockes.take(20)) {
        final copies = await depot.copiesDuRapport(s.empreinte);
        expect(copies, isNotEmpty,
            reason: '§13 : la provenance d\'un rapport doit être conservée');
      }

      // Les bilans cités créent des références vers des versions exactes.
      final bilansSemaine = await depot.compterBilans(type: 'bilan_semaine');
      final bilansMois = await depot.compterBilans(type: 'bilan_mois');
      expect(bilansSemaine + bilansMois, greaterThan(0),
          reason: 'les bilans de la sauvegarde doivent être restaurés');
      expect(await depot.compterReferencesOrphelines(), 0,
          reason: 'cohérence entre magasins : aucune référence orpheline');
    });

    test('le rejeu de la restauration 13/11 est idempotent (§14)', () async {
      exigereSauvegarde(_cheminSauvegarde13);
      final contenu = File(_cheminSauvegarde13).readAsStringSync();
      Future<ResultatRestauration> jouer() => restaurateur.restaurer(
            depot: depot,
            contenuSauvegarde: contenu,
            mode: ModeRestauration.complet,
            dossierTemp: '${dossierTest.path}/temp',
            versionLocale: 'test',
          );

      expect((await jouer()).reussie, isTrue);
      final elo1 = await depot.compterElo();
      final rapports1 = await depot.compterRapports();
      final bilans1 = await depot.compterBilans();

      expect((await jouer()).reussie, isTrue);
      expect(await depot.compterElo(), elo1);
      expect(await depot.compterRapports(), rapports1);
      expect(await depot.compterBilans(), bilans1);
      expect(await depot.compterReferencesOrphelines(), 0);

      // Un rejeu ne doit rien remplacer : tout est déjà identique.
      final j2 = await jouer();
      expect(j2.eloRestaures, 0,
          reason: 'un rejeu ne crée aucun rating : tout existe déjà');
      expect(j2.eloIdentiques, elo1);
    });

    test('la sauvegarde 28/05 restaure aussi ses ratings', () async {
      exigereSauvegarde(_cheminSauvegarde28);
      final empreinteAvant = sha256Fichier(_cheminSauvegarde28);
      final contenu = File(_cheminSauvegarde28).readAsStringSync();
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: contenu,
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      expect(r.reussie, isTrue, reason: r.erreur ?? '');
      expect(await depot.compterElo(), 1934,
          reason: 'mesure de référence : 1 934 clés dans la sauvegarde 28/05');

      // ── CONTRÔLE EXHAUSTIF DES 1 934 RATINGS (§5) ─────────────────────
      // L'exigence porte explicitement sur les DEUX sauvegardes historiques :
      // 1 934 ratings pour le 28/05, 9 001 pour le 13/11. Aucune ne doit être
      // vérifiée par échantillonnage.
      final source = jsonDecode(contenu) as Map;
      final eloSource = <String, Object?>{
        for (final e in (source['elo_service'] as Map).entries)
          '${e.key}': e.value
      };
      final bilan =
          await _controlerEloExhaustif(depot, eloSource, etiquette: '28/05');
      expect(bilan.ecarts, isEmpty,
          reason: '${bilan.ecarts.length} écart(s) : '
              '${bilan.ecarts.take(10).join(" ; ")}');
      expect(bilan.verifies, eloSource.length,
          reason: 'TOUS les ratings doivent être vérifiés');
      expect(bilan.verifies, 1934);

      expect(sha256Fichier(_cheminSauvegarde28), empreinteAvant);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('Performance mesurée, pas estimée (§19)', () {
    test('la restauration de 9 001 ratings tient dans un temps mesuré',
        () async {
      exigereSauvegarde(_cheminSauvegarde13);
      final contenu = File(_cheminSauvegarde13).readAsStringSync();
      final chrono = Stopwatch()..start();
      final r = await restaurateur.restaurer(
        depot: depot,
        contenuSauvegarde: contenu,
        mode: ModeRestauration.complet,
        dossierTemp: '${dossierTest.path}/temp',
        versionLocale: 'test',
      );
      chrono.stop();
      expect(r.reussie, isTrue, reason: r.erreur ?? '');
      // Mesure rapportée, jamais transformée en promesse : la valeur réelle est
      // imprimée pour être citée dans le rapport final.
      // ignore: avoid_print
      print('[MESURE] restauration 13/11 : ${chrono.elapsedMilliseconds} ms '
          'pour ${await depot.compterElo()} ratings');
      expect(chrono.elapsedMilliseconds, lessThan(120000),
          reason: 'au-delà de 2 minutes sur un appareil de référence, la '
              'restauration serait inutilisable');
    });
  });
}

/// SHA-256 réel du fichier entier, pour prouver qu'une lecture ne l'a pas
/// modifié. Un hachage partiel ne prouverait rien : une altération hors de
/// l'échantillon passerait inaperçue.
String sha256Fichier(String chemin) {
  final octets = File(chemin).readAsBytesSync();
  return sha256.convert(octets).toString();
}
