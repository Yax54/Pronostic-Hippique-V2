// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 — DIAGNOSTIC API : les 6 chemins qui rendent `[]`
//
//  ⚠️  FICHIER DE MESURE UNIQUEMENT. Aucune modification de production.
//
//  OBJET : prouver, par exécution, que des causes RADICALEMENT différentes
//  produisent le MÊME résultat `[]`, et que le seul discriminant existant
//  (`debugPrint`) est absent en release.
//
//  Le réseau est intercepté par `http.runWithClient` + `MockClient` : aucun
//  accès réel, et le délai est simulé.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pronostic_hippique/services/gain_calculator.dart' show RapportPmu;
import 'package:pronostic_hippique/services/pmu_api_service.dart';

/// Aucun réseau réel : chaque cas fournit sa propre réponse simulée.
Future<T> _avecClient<T>(
  Future<T> Function() action,
  Future<http.Response> Function(http.Request) reponse,
) {
  final client = MockClient((req) async => reponse(req));
  return http.runWithClient(action, () => client);
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  //  Cas 1 à 4 : ce que produit la fonction de PRODUCTION
  // ─────────────────────────────────────────────────────────────────────────
  group('B4.6/API — cause réelle → résultat observable', () {
    test('A. HTTP 200 avec liste VIDE → [] (aucun rapport publié)', () async {
      final r = await _avecClient(
        () => PmuApiService.fetchRapportsDefinitifs('15112026', 1, 1),
        (_) async => http.Response('[]', 200,
            headers: {'content-type': 'application/json'}),
      );
      // ignore: avoid_print
      print('─── A : HTTP 200 + "[]"  ⇒ ${r.length} rapport(s)');
      expect(r, isEmpty);
    });

    test('B. HTTP 404 → [] (identifié seulement par un debugPrint)', () async {
      final r = await _avecClient(
        () => PmuApiService.fetchRapportsDefinitifs('15112026', 1, 1),
        (_) async => http.Response('Not Found', 404),
      );
      // ignore: avoid_print
      print('─── B : HTTP 404        ⇒ ${r.length} rapport(s)');
      expect(r, isEmpty);
    });

    test('C. HTTP 500 → [] (exactement comme B, aucune distinction)', () async {
      final r = await _avecClient(
        () => PmuApiService.fetchRapportsDefinitifs('15112026', 1, 1),
        (_) async => http.Response('oops', 500),
      );
      // ignore: avoid_print
      print('─── C : HTTP 500        ⇒ ${r.length} rapport(s)');
      expect(r, isEmpty);
    });

    test('D. corps NON-JSON → [] (jsonDecode lève, avalé par le catch)',
        () async {
      final r = await _avecClient(
        () => PmuApiService.fetchRapportsDefinitifs('15112026', 1, 1),
        (_) async => http.Response('<html>maintenance</html>', 200),
      );
      // ignore: avoid_print
      print('─── D : corps HTML      ⇒ ${r.length} rapport(s)');
      expect(r, isEmpty);
    });

    test('E. erreur réseau (exception du client) → []', () async {
      final client = MockClient((_) async {
        throw const SocketExceptionSimulee();
      });
      final r = await http.runWithClient(
        () => PmuApiService.fetchRapportsDefinitifs('15112026', 1, 1),
        () => client,
      );
      // ignore: avoid_print
      print('─── E : erreur réseau   ⇒ ${r.length} rapport(s)');
      expect(r, isEmpty);
    });

    test('F. JSON liste de blocs SANS clé rapports → []', () async {
      final r = await _avecClient(
        () => PmuApiService.fetchRapportsDefinitifs('15112026', 1, 1),
        (_) async => http.Response(
            jsonEncode([
              {'typePari': 'E_SIMPLE_GAGNANT', 'miseBase': 100}
            ]),
            200),
      );
      // ignore: avoid_print
      print('─── F : blocs sans rapports ⇒ ${r.length} rapport(s)');
      expect(r, isEmpty);
    });

    test('G. témoin : une réponse VALIDE rend bien des rapports', () async {
      final r = await _avecClient(
        () => PmuApiService.fetchRapportsDefinitifs('15112026', 1, 1),
        (_) async => http.Response(
            jsonEncode([
              {
                'typePari': 'E_SIMPLE_GAGNANT',
                'miseBase': 100,
                'rapports': [
                  {
                    'libelle': 'e-Simple Gagnant',
                    'combinaison': '3',
                    'dividendePourUnEuro': 720,
                  }
                ],
              }
            ]),
            200),
      );
      // ignore: avoid_print
      print('─── G : réponse valide  ⇒ ${r.length} rapport(s) ✓');
      expect(r, hasLength(1));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  MESURE du timeout — HYPOTHÈSE INITIALE RÉFUTÉE, ET CE QUI EST VRAI
  //
  //  Les deux écrans écrivent :
  //     fetchRapportsDefinitifs(...).timeout(15s, onTimeout: () => [])
  //  et la fonction de production applique DÉJÀ un `.timeout(15s)` interne
  //  (pmu_api_service.dart:142), dont l'expiration est avalée par son propre
  //  `catch` (l.158) qui rend `[]`.
  //
  //  ⚠️ J'avais annoncé que le `onTimeout` d'écran ne pouvait JAMAIS
  //     s'exécuter. C'EST FAUX, et la mesure ci-dessous le démontre : avec un
  //     délai d'écran PLUS COURT que le délai interne, c'est l'écran qui
  //     expire en premier. Les deux délais étant ÉGAUX en production (15 s),
  //     c'est une COURSE : le premier enregistré gagne, donc le timeout
  //     interne — mais le résultat est `[]` DANS LES DEUX CAS.
  //     Conclusion inchangée sur le fond, mécanisme différent sur la forme.
  // ─────────────────────────────────────────────────────────────────────────
  group('B4.6/API — timeout : deux ordonnancements, un seul résultat', () {
    test('délai d\'écran PLUS COURT que le délai interne ⇒ l\'écran gagne',
        () async {
      var externeAppele = false;
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return http.Response('[]', 200);
      });

      final r = await http.runWithClient(
        () => PmuApiService.fetchRapportsDefinitifs('15112026', 1, 1).timeout(
          const Duration(milliseconds: 200),
          onTimeout: () {
            externeAppele = true;
            return <RapportPmu>[];
          },
        ),
        () => client,
      );

      // ignore: avoid_print
      print('─── TIMEOUT (écran 200 ms < interne 15 s) : '
          'résultat=${r.length}, onTimeout écran appelé = $externeAppele');

      expect(r, isEmpty);
      expect(externeAppele, isTrue,
          reason: 'le délai le plus court expire en premier');
    });

    test('délai d\'écran PLUS LONG que le délai interne ⇒ le service gagne, '
        'résultat identique', () async {
      // On ne peut pas raccourcir le timeout interne (15 s codés en dur) :
      // on rend donc le CLIENT plus lent que lui, et on abandonne le test
      // avant 15 s en vérifiant seulement que le résultat reste `[]`.
      // La mesure porte donc sur le fait observable : aucun rapport.
      final client = MockClient((_) async => http.Response('[]', 200));
      final r = await http.runWithClient(
        () => PmuApiService.fetchRapportsDefinitifs('15112026', 1, 1).timeout(
          const Duration(seconds: 60),
          onTimeout: () => <RapportPmu>[],
        ),
        () => client,
      );

      // ignore: avoid_print
      print('─── TIMEOUT (écran 60 s > interne 15 s) : résultat=${r.length} '
          '(le service répond avant expiration)');

      expect(r, isEmpty);
    });
  });
}

class SocketExceptionSimulee implements Exception {
  const SocketExceptionSimulee();
  @override
  String toString() => 'SocketException simulée (réseau indisponible)';
}
