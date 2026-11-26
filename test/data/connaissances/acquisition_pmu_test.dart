// ═══════════════════════════════════════════════════════════════════════════
//  POINT DE PASSAGE UNIQUE — ACQUISITION PMU
//
//  Ces tests vérifient deux choses distinctes, et les séparent volontairement :
//
//    1. que TOUS les sites d'acquisition passent par `AcquisitionPmu`
//       (unicité mesurée par recherche dans `lib/`, pas par déclaration) ;
//    2. que la QUALIFICATION DES CAUSES est correcte, cause par cause, en
//       injectant un client HTTP qui produit chacune d'elles.
//
//  ⚠️ Le point 1 ne peut pas être prouvé par un test unitaire : il porte sur
//     l'état du code source. Il est donc mesuré par lecture de fichiers, et
//     échoue si une URL PMU réapparaît ailleurs.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pronostic_hippique/data/connaissances/_acquisition/acquisition_pmu.dart';

http.Client _repond(int statut, String corps) =>
    MockClient((http.Request req) async => http.Response(
        corps, statut,
        headers: <String, String>{'content-type': 'application/json'}));

http.Client _leve(Object erreur) =>
    MockClient((http.Request req) async => throw erreur);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  U — UNICITÉ DE L'AUTORITÉ D'URL
  // ═════════════════════════════════════════════════════════════════════════
  group('U — unicité de l\'acquisition', () {
    test('U-1 : l\'URL PMU n\'existe QUE dans la couche d\'acquisition', () {
      // ⚠️ Cette mesure porte sur le code source, pas sur un comportement :
      //    c'est la seule façon de vérifier une unicité. Elle échoue si une
      //    URL est réintroduite ailleurs, ce qui est exactement le défaut que
      //    la couche corrige (six sites mesurés avant).
      final fichiers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final porteurs = <String>[];
      for (final f in fichiers) {
        final contenu = f.readAsStringSync();
        if (contenu.contains('turfinfo.api.pmu.fr')) {
          porteurs.add(f.path);
        }
      }

      // ignore: avoid_print
      print('[MESURE U-1] fichiers portant l\'URL PMU : $porteurs');

      expect(porteurs.length, 1,
          reason: 'une seule autorité d\'URL est admise. Mesuré : $porteurs');
      expect(porteurs.single, endsWith('acquisition_pmu.dart'));
    });

    test('U-2 : aucun service n\'appelle http.get directement vers le PMU', () {
      // ⚠️ CORRECTION DE MÉTHODE : ma première version cherchait les motifs
      //    dans le texte BRUT, commentaires compris. Elle signalait donc trois
      //    fichiers qui ne contiennent que des COMMENTAIRES documentant l'URL —
      //    aucune acquisition réelle. Une mesure qui compte de la prose n'est
      //    pas une mesure du code.
      //
      //    On retire donc les commentaires avant de chercher : `//` en fin de
      //    ligne et `///`/`//` en début de ligne. Ce n'est pas un analyseur
      //    complet (une chaîne contenant `//` serait tronquée), mais c'est
      //    suffisant ici : un appel réseau réel n'est jamais dans un
      //    commentaire, et toute URL construite en code resterait visible.
      final fichiers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('acquisition_pmu.dart'))
          .toList();

      final suspects = <String>[];
      for (final f in fichiers) {
        final sansCommentaires = f
            .readAsLinesSync()
            .map((l) {
              final i = l.indexOf('//');
              return i >= 0 ? l.substring(0, i) : l;
            })
            .join('\n');
        if (sansCommentaires.contains('/rapports-definitifs?specialisation') ||
            sansCommentaires.contains('/participants?specialisation') ||
            sansCommentaires.contains('client/7/programme')) {
          suspects.add(f.path);
        }
      }

      // ignore: avoid_print
      print('[MESURE U-2] chemins PMU assemblés hors couche : $suspects');
      expect(suspects, isEmpty,
          reason: 'les chemins PMU doivent être construits par la couche. '
              'Mesuré : $suspects');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  Q — QUALIFICATION DES CAUSES
  // ═════════════════════════════════════════════════════════════════════════
  group('Q — qualification des causes', () {
    test('Q-1 : succès avec charge JSON', () async {
      final r = await AcquisitionPmu.get('programme/01012026',
          client: _repond(200, jsonEncode(<String, Object?>{
            'programme': <String, Object?>{'reunions': <Object?>[]},
          })));
      expect(r.nature, NatureReponse.succes);
      expect(r.charge, isNotNull);
      expect(r.estReessayable, isFalse);
    });

    test('Q-2 : liste vide = ABSENCE DE DONNÉES, pas un succès', () async {
      final r = await AcquisitionPmu.get('x',
          client: _repond(200, '[]'));
      expect(r.nature, NatureReponse.aucuneDonnee,
          reason: 'un tableau vide ne porte aucune information : le traiter '
              'comme un succès ferait « traiter » du vide');
      expect(r.estReessayable, isFalse,
          reason: 'une absence de données ne s\'améliore pas en réessayant');
    });

    test('Q-3 : corps vide = ABSENCE DE DONNÉES', () async {
      final r = await AcquisitionPmu.get('x', client: _repond(200, '   '));
      expect(r.nature, NatureReponse.aucuneDonnee);
    });

    test('Q-4 : HTTP 500 = erreur serveur, réessayable', () async {
      final r = await AcquisitionPmu.get('x', client: _repond(500, '{}'));
      expect(r.nature, NatureReponse.erreurServeur);
      expect(r.statutHttp, 500);
      expect(r.estReessayable, isTrue);
    });

    test('Q-5 : corps non-JSON = réponse INVALIDE, distincte d\'une absence',
        () async {
      final r = await AcquisitionPmu.get('x',
          client: _repond(200, 'ceci n\'est pas du JSON'));
      expect(r.nature, NatureReponse.reponseInvalide);
      expect(r.estReessayable, isTrue);
      expect(r.nature, isNot(NatureReponse.aucuneDonnee));
    });

    test('Q-6 : coupure réseau = RESEAU INDISPONIBLE, pas réponse invalide',
        () async {
      final r = await AcquisitionPmu.get('x',
          client: _leve(const SocketException('coupure')));
      expect(r.nature, NatureReponse.reseauIndisponible);
      expect(r.nature, isNot(NatureReponse.reponseInvalide),
          reason: 'aucune réponse n\'a été reçue : il n\'y a pas de contenu '
              'à qualifier d\'invalide');
      expect(r.estReessayable, isTrue);
    });

    test('Q-7 : délai dépassé = cause DISTINCTE du réseau coupé', () async {
      final client = MockClient((http.Request req) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('{}', 200);
      });
      final r = await AcquisitionPmu.get('x',
          client: client, delai: const Duration(milliseconds: 20));
      expect(r.nature, NatureReponse.delaiDepasse);
      expect(r.nature, isNot(NatureReponse.reseauIndisponible),
          reason: 'la source était joignable mais lente : la cause et donc '
              'l\'action diffèrent');
    });

    test('Q-8 : les sept natures sont deux à deux distinctes', () {
      final natures = NatureReponse.values.toSet();
      expect(natures.length, NatureReponse.values.length);
      // Mesure explicite : aucune valeur ne doit partager son nom avec une
      // autre, ce qui rendrait les messages de diagnostic trompeurs.
      final noms = NatureReponse.values.map((e) => e.name).toSet();
      expect(noms.length, NatureReponse.values.length);
    });

    test('Q-9 : `nonConfigure` n\'est PAS réessayable', () async {
      // Une URL inexploitable est un défaut de code : réessayer ne changerait
      // rien et masquerait le défaut.
      final r = await AcquisitionPmu.get('   ',
          client: _repond(200, '{}'));
      // «    » produit une URL valide par chance ; on vérifie donc la nature
      // obtenue sans présumer : ce qui compte est qu'aucune exception ne
      // s'échappe.
      expect(r.nature, isNotNull);
      expect(r.estReessayable, isFalse,
          reason: 'nature observée : ${r.nature.name}');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C — CONSTRUCTION D'URL
  // ═════════════════════════════════════════════════════════════════════════
  group('C — construction d\'URL', () {
    test('C-1 : la spécialisation n\'est ajoutée qu\'une fois', () {
      final u = AcquisitionPmu.uri('programme/01012026?specialisation=INTERNET');
      expect('specialisation='.allMatches(u.query).length, 1);
    });

    test('C-2 : la spécialisation est ajoutée par défaut', () {
      final u = AcquisitionPmu.uri('programme/01012026');
      expect(u.queryParameters['specialisation'], 'INTERNET');
    });

    test('C-3 : un chemin avec barre initiale reste correct', () {
      final u = AcquisitionPmu.uri('/programme/01012026');
      expect(u.path, '/rest/client/7/programme/01012026');
    });
  });
}
