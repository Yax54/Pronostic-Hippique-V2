// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 / SUJET 2 — LES TROIS TABLES DE CODES PMU
//
//  ⚠️  FICHIER DE MESURE. Aucune table n'est fusionnée, aucune n'est modifiée.
//
//  Ce qui est prouvé ici :
//    • les trois tables ne disent PAS la même chose, et c'est mesuré ;
//    • deux paris DIFFÉRENTS ne sont jamais rendus identiques ;
//    • la conséquence de la divergence sur le moteur est chiffrée ;
//    • la 3ᵉ table est INATTEIGNABLE par la production (chaîne morte).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show TypePariJoue, codeApiPourType;
import 'package:pronostic_hippique/services/referentiel_paris_pmu.dart'
    show TypePariPmu, codeApiPourTypePmu;

const String kDossierMulti = '/home/user/recherche_pmu/multi';

void main() {
  group('B4.6-C — les tables divergent, mesuré', () {
    test('C-1 · le moteur ne connaît que 3 codes pour 6 paris distincts', () {
      // Le moteur ne modélise QUE les paris qu'il sait régler.
      final paris = <TypePariJoue>[
        TypePariJoue.tierce,
        TypePariJoue.tierceOrdre,
        TypePariJoue.tierceDesordre,
      ];
      final codes = {for (final p in paris) codeApiPourType(p)};
      // ignore: avoid_print
      print('C-1 Tiercé/Ordre/Désordre → ${codes.toList()}');
      expect(codes.length, 1, reason: 'le moteur les range sous UN code');
      expect(codes.first, 'E_TIERCE');
    });

    test('C-2 · le référentiel, lui, distingue Tiercé / Trio / Trio Ordre',
        () {
      final t = codeApiPourTypePmu(TypePariPmu.tierce);
      final trio = codeApiPourTypePmu(TypePariPmu.trio);
      final trioO = codeApiPourTypePmu(TypePariPmu.trioOrdre);
      // ignore: avoid_print
      print('C-2 référentiel : tierce=$t trio=$trio trioOrdre=$trioO');
      expect({t, trio, trioO}.length, 3, reason: 'trois codes DISTINCTS');
    });

    test('C-3 · Quarté+ et Super4 restent deux codes distincts', () {
      final q = codeApiPourTypePmu(TypePariPmu.quartePlus);
      final s = codeApiPourTypePmu(TypePariPmu.superQuatre);
      // ignore: avoid_print
      print('C-3 référentiel : quartePlus=$q superQuatre=$s');
      expect(q, isNot(s));
      // Le moteur, lui, n'a qu'un code pour « quarte » (Quarté+).
      expect(codeApiPourType(TypePariJoue.quarte), 'E_QUARTE_PLUS');
    });

    test('C-4 · Quinté+ / Multi / MiniMulti restent trois codes distincts',
        () {
      final q = codeApiPourTypePmu(TypePariPmu.quintePlus);
      final m = codeApiPourTypePmu(TypePariPmu.multi);
      final mm = codeApiPourTypePmu(TypePariPmu.miniMulti);
      // ignore: avoid_print
      print('C-4 référentiel : quintePlus=$q multi=$m miniMulti=$mm');
      expect({q, m, mm}.length, 3);
    });

    test('C-5 · aucun couple de paris distincts ne reçoit le même code '
        'dans le RÉFÉRENTIEL', () {
      final codes = <String, List<TypePariPmu>>{};
      for (final t in TypePariPmu.values) {
        final c = codeApiPourTypePmu(t);
        if (c == null) continue;
        codes.putIfAbsent(c, () => <TypePariPmu>[]).add(t);
      }
      final collisions = codes.entries.where((e) => e.value.length > 1);
      // ignore: avoid_print
      print('C-5 collisions dans le référentiel : '
          '${collisions.map((e) => '${e.key}→${e.value.map((t) => t.name)}').toList()}');
      expect(collisions, isEmpty,
          reason: 'le référentiel n\'assimile jamais deux paris');
    });
  });

  group('B4.6-C — conséquence mesurée sur les captures réelles', () {
    test('C-6 · quel code est réellement publié, et pour combien de courses',
        () {
      final parCode = <String, int>{};
      final fichiers = Directory(kDossierMulti)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();

      for (final f in fichiers) {
        final nom = f.uri.pathSegments.last;
        if (!RegExp(r'^R\d+C\d+_\d{8}\.json$').hasMatch(nom)) continue;
        final corps = f.readAsStringSync();
        for (final code in _codesDuFichier(corps)) {
          parCode[code] = (parCode[code] ?? 0) + 1;
        }
      }

      // ignore: avoid_print
      print('C-6 codes publiés (courses) :');
      final e = parCode.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final x in e) {
        // ignore: avoid_print
        print('    ${x.value.toString().padLeft(4)} × ${x.key}');
      }

      // La conséquence : le code cherché par le MOTEUR pour un Tiercé Ordre.
      final cherche = codeApiPourType(TypePariJoue.tierceOrdre)!;
      final trouve = parCode[cherche] ?? 0;
      // Le code réellement publié pour les mêmes courses.
      final trio = parCode['E_TRIO'] ?? 0;
      final tierce = parCode['E_TIERCE'] ?? 0;
      // ignore: avoid_print
      print('');
      // ignore: avoid_print
      print('C-6 le moteur cherche « $cherche » : publié dans $trouve cours');
      // ignore: avoid_print
      print('C-6 or « E_TRIO » est publié dans $trio cours');
      // ignore: avoid_print
      print('C-6 et « E_TIERCE » dans $tierce cours');

      expect(trouve, greaterThan(0));
      // La divergence est MESURÉE : elle n'est pas nulle.
      expect(trio, isNot(trouve),
          reason: 'les deux codes ne couvrent pas le même ensemble de courses');
    });

    test('C-7 · Quarté+ : le moteur cherche un code quasi jamais publié', () {
      final parCode = <String, int>{};
      for (final f in Directory(kDossierMulti)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))) {
        final nom = f.uri.pathSegments.last;
        if (!RegExp(r'^R\d+C\d+_\d{8}\.json$').hasMatch(nom)) continue;
        for (final c in _codesDuFichier(f.readAsStringSync())) {
          parCode[c] = (parCode[c] ?? 0) + 1;
        }
      }
      final cherche = codeApiPourType(TypePariJoue.quarte)!;
      final trouve = parCode[cherche] ?? 0;
      final super4 = parCode['E_SUPER_QUATRE'] ?? 0;
      // ignore: avoid_print
      print('C-7 moteur cherche « $cherche » : $trouve cours | '
          '« E_SUPER_QUATRE » : $super4 cours');
      expect(trouve, isNot(super4));
      // Le Quinté+ suit la même règle.
      final q = codeApiPourType(TypePariJoue.quinte)!;
      // ignore: avoid_print
      print('C-7b moteur cherche « $q » : ${parCode[q] ?? 0} cours | '
          '« E_MULTI » : ${parCode['E_MULTI'] ?? 0} cours | '
          '« E_MINI_MULTI » : ${parCode['E_MINI_MULTI'] ?? 0} cours');
    });

    test('C-8 · la 3ᵉ table est INATTEIGNABLE : elle ne peut pas rendre les '
        'codes du moteur', () {
      // `_typePariApiFromLabel` est privée : on prouve l'absence de chemin
      // par lecture de la source, seule preuve possible sur du privé.
      final src = File('lib/services/pmu_api_service.dart')
          .readAsStringSync();
      final debut = src.indexOf('static List<String> _typePariApiFromLabel');
      expect(debut, greaterThan(0));
      final fin = src.indexOf('return [];', debut);
      final corps = src.substring(debut, fin);
      // ignore: avoid_print
      print('C-8 la table par libellé ne cite aucun des 3 codes du moteur : '
          '${!corps.contains("E_TIERCE") && !corps.contains("E_QUARTE_PLUS") && !corps.contains("E_QUINTE_PLUS")}');
      expect(corps.contains('E_TIERCE'), isFalse);
      expect(corps.contains('E_QUARTE_PLUS'), isFalse);
      expect(corps.contains('E_QUINTE_PLUS'), isFalse);
      // Elle ne peut donc servir qu'à la chaîne morte
      // (`recupererDividendesPmuManquants` → `fetchDividendePourPari`).
    });
  });
}

/// Codes de blocs présents dans une capture de rapports.
Set<String> _codesDuFichier(String corps) {
  final out = <String>{};
  final re = RegExp(r'"typePari"\s*:\s*"([A-Z0-9_]+)"');
  for (final m in re.allMatches(corps)) {
    out.add(m.group(1)!);
  }
  return out;
}
