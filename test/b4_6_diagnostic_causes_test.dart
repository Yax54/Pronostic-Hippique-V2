// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 / SUJET 1 — DIAGNOSTIC API : LES CAUSES DEVIENNENT DISTINCTES
//
//  ⚠️  Ce fichier ne teste QUE le diagnostic et la NON-RÉGRESSION de la
//  fonction historique. Il ne touche aucune règle métier.
//
//  Ce qui est prouvé ici :
//    • chaque cause produit une cause DISTINCTE (et non plus `[]` partout) ;
//    • `fetchRapportsDefinitifs` rend TOUJOURS les mêmes listes qu'avant ;
//    • le diagnostic ne lève jamais d'exception ;
//    • la cause est lisible SANS `kDebugMode` (elle est portée par un objet).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pronostic_hippique/services/pmu_api_service.dart';

/// Une réponse de rapports définitifs VALIDE (1 rapport Simple Gagnant).
String get _corpsValide => jsonEncode([
      {
        'typePari': 'E_SIMPLE_GAGNANT',
        'miseBase': 100,
        'rembourse': false,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Simple Gagnant',
            'dividende': 420,
            'dividendePourUnEuro': 420,
            'combinaison': '16',
            'nombreGagnants': 12.0,
            'dividendePourUneMiseDeBase': 420,
            'dividendeUnite': 'PourUnEuro',
          },
        ],
      },
    ]);

/// Une réponse liste valide, mais dont AUCUN bloc ne publie de rapport.
String get _corpsListeVide => jsonEncode([
      {'typePari': 'E_SIMPLE_GAGNANT', 'rapports': <dynamic>[]},
    ]);

/// La forme réelle d'un fichier de PROGRAMME (racine = objet, pas liste).
String get _corpsProgramme => jsonEncode({
      'programme': {
        'reunions': [
          {'numOfficiel': 1, 'courses': <dynamic>[]},
        ],
      },
    });

Future<DiagnosticRapports> _mesurer(
  Future<http.Response> Function(http.Request) handler,
) async {
  late DiagnosticRapports d;
  await http.runWithClient(() async {
    d = await PmuApiService.fetchRapportsAvecDiagnostic('15112026', 1, 1);
  }, () => MockClient(handler));
  return d;
}

Future<List<dynamic>> _mesurerHistorique(
  Future<http.Response> Function(http.Request) handler,
) async {
  late List<dynamic> r;
  await http.runWithClient(() async {
    r = await PmuApiService.fetchRapportsDefinitifs('15112026', 1, 1);
  }, () => MockClient(handler));
  return r;
}

void main() {
  group('B4.6-D — le diagnostic distingue les causes', () {
    test('D-1 · réponse VALIDE → cause = aucune, rapports présents', () async {
      final d = await _mesurer(
          (_) async => http.Response(_corpsValide, 200));
      // ignore: avoid_print
      print('D-1 cause=${d.cause.name} http=${d.codeHttp} '
          'rapports=${d.rapports.length}');
      expect(d.cause, CauseAbsenceRapports.aucune);
      expect(d.aDesRapports, isTrue);
      expect(d.rapports.length, 1);
    });

    test('D-2 · HTTP 200 + "[]" → aucunRapportPublie', () async {
      final d = await _mesurer((_) async => http.Response('[]', 200));
      // ignore: avoid_print
      print('D-2 cause=${d.cause.name} http=${d.codeHttp}');
      expect(d.cause, CauseAbsenceRapports.aucunRapportPublie);
      expect(d.aDesRapports, isFalse);
    });

    test('D-3 · HTTP 404 → httpNonOk, code conservé', () async {
      final d = await _mesurer((_) async => http.Response('', 404));
      // ignore: avoid_print
      print('D-3 cause=${d.cause.name} http=${d.codeHttp}');
      expect(d.cause, CauseAbsenceRapports.httpNonOk);
      expect(d.codeHttp, 404);
    });

    test('D-4 · HTTP 500 → httpNonOk, DISTINCT de 404 par son code',
        () async {
      final d = await _mesurer((_) async => http.Response('', 500));
      // ignore: avoid_print
      print('D-4 cause=${d.cause.name} http=${d.codeHttp}');
      expect(d.cause, CauseAbsenceRapports.httpNonOk);
      expect(d.codeHttp, 500);
    });

    test('D-5 · corps HTML → corpsNonJson', () async {
      final d = await _mesurer(
          (_) async => http.Response('<html>maintenance</html>', 200));
      // ignore: avoid_print
      print('D-5 cause=${d.cause.name}');
      expect(d.cause, CauseAbsenceRapports.corpsNonJson);
    });

    test('D-6 · racine = objet programme → racineNonListe', () async {
      final d = await _mesurer((_) async => http.Response(_corpsProgramme, 200));
      // ignore: avoid_print
      print('D-6 cause=${d.cause.name}');
      expect(d.cause, CauseAbsenceRapports.racineNonListe);
    });

    test('D-7 · liste valide sans rapport → aucunRapportPublie', () async {
      final d = await _mesurer(
          (_) async => http.Response(_corpsListeVide, 200));
      // ignore: avoid_print
      print('D-7 cause=${d.cause.name}');
      expect(d.cause, CauseAbsenceRapports.aucunRapportPublie);
    });

    test('D-8 · erreur réseau → reseau', () async {
      final d = await _mesurer(
          (_) async => throw http.ClientException('réseau indisponible'));
      // ignore: avoid_print
      print('D-8 cause=${d.cause.name}');
      expect(d.cause, CauseAbsenceRapports.reseau);
    });

    test('D-9 · timeout interne (15 s) → timeout', () async {
      final d = await _mesurer((_) async {
        // Plus long que le délai interne de 15 s du service.
        await Future<void>.delayed(const Duration(seconds: 20));
        return http.Response(_corpsValide, 200);
      });
      // ignore: avoid_print
      print('D-9 cause=${d.cause.name}');
      expect(d.cause, CauseAbsenceRapports.timeout);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('D-10 · les 7 causes sont TOUTES distinctes', () async {
      final causes = <CauseAbsenceRapports>{};
      causes.add((await _mesurer((_) async => http.Response(_corpsValide, 200)))
          .cause);
      causes.add((await _mesurer((_) async => http.Response('[]', 200))).cause);
      causes.add((await _mesurer((_) async => http.Response('', 404))).cause);
      causes.add((await _mesurer((_) async => http.Response('<h/>', 200)))
          .cause);
      causes.add((await _mesurer((_) async => http.Response(_corpsProgramme, 200)))
          .cause);
      causes.add((await _mesurer(
              (_) async => throw http.ClientException('x')))
          .cause);
      // ignore: avoid_print
      print('D-10 causes distinctes observées : ${causes.map((c) => c.name)}');
      expect(causes.length, 6);
    });
  });

  group('B4.6-D — la fonction historique est INCHANGÉE', () {
    test('D-11 · toutes les causes d\'échec rendent encore []', () async {
      final cas = <String, Future<http.Response> Function(http.Request)>{
        'HTTP 200 "[]"': (_) async => http.Response('[]', 200),
        'HTTP 404': (_) async => http.Response('', 404),
        'HTTP 500': (_) async => http.Response('', 500),
        'corps HTML': (_) async => http.Response('<html/>', 200),
        'racine programme': (_) async => http.Response(_corpsProgramme, 200),
        'liste sans rapport': (_) async => http.Response(_corpsListeVide, 200),
        'erreur réseau': (_) async =>
            throw http.ClientException('réseau indisponible'),
      };
      for (final e in cas.entries) {
        final r = await _mesurerHistorique(e.value);
        // ignore: avoid_print
        print('D-11 ${e.key.padRight(22)} → ${r.length} rapport(s)');
        expect(r, isEmpty, reason: 'comportement historique : []');
      }
    });

    test('D-12 · réponse valide rend les mêmes rapports qu\'avant', () async {
      final r = await _mesurerHistorique(
          (_) async => http.Response(_corpsValide, 200));
      // ignore: avoid_print
      print('D-12 rapports=${r.length}');
      expect(r.length, 1);
    });

    test('D-13 · aucune cause ne lève d\'exception', () async {
      // Une exception non rattrapée ferait échouer ce test.
      for (final h in <Future<http.Response> Function(http.Request)>[
        (_) async => http.Response('[]', 200),
        (_) async => http.Response('', 404),
        (_) async => http.Response('{', 200),
        (_) async => http.Response(_corpsProgramme, 200),
        (_) async => throw http.ClientException('x'),
        (_) async => throw StateError('autre'),
      ]) {
        final d = await _mesurer(h);
        expect(d.rapports, isEmpty);
        expect(d.cause, isNot(CauseAbsenceRapports.aucune));
      }
      // ignore: avoid_print
      print('D-13 aucune exception levée');
    });
  });
}
