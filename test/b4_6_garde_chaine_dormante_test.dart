// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 / SUJET 2 & 7 — GARDE CONTRE LA RÉACTIVATION DE LA CHAÎNE DIVERGENTE
//
//  ⚠️  Aucune fonction n'est supprimée : on INTERDIT seulement qu'elle
//  redevienne atteignable depuis la production sans que cela se voie.
//
//  Pourquoi cette garde existe (mesuré en B-4.6) :
//    • `_typePariApiFromLabel` rend `E_TRIO` pour « tiercé », alors que les
//      DEUX autorités vivantes (`codeApiPourType` du moteur et
//      `codeApiPourTypePmu` du référentiel) rendent `E_TIERCE` ;
//    • `fetchDividendePourPari` contient un repli `return matching.first`
//      qui rend un rapport ARBITRAIRE quand la combinaison ne correspond pas ;
//    • cette chaîne n'est atteignable que par `recupererDividendesPmuManquants`,
//      qui n'a AUCUN appelant en production.
//
//  La garde échoue si quelqu'un rebranche la chaîne : la décision redevient
//  alors explicite, ce qui est précisément le but.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source nette de commentaires de ligne, pour ne pas confondre une
/// DOCUMENTATION citant un nom avec un APPEL réel.
String _sourceSansCommentaires(String chemin) {
  final src = File(chemin).readAsStringSync();
  return src
      .split('\n')
      .where((l) {
        final t = l.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      })
      .join('\n');
}

void main() {
  group('B4.6-G — la chaîne divergente ne doit pas redevenir vivante', () {
    test('G-1 · `recupererDividendesPmuManquants` n\'a AUCUN appelant '
        'en production', () {
      const cheminGarde = 'test/b4_6_garde_chaine_dormante_test.dart';
      final fichiers = <File>[];
      for (final d in ['lib', 'test', 'integration_test']) {
        final dir = Directory(d);
        if (!dir.existsSync()) continue;
        fichiers.addAll(dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => f.path != cheminGarde));
      }

      final appels = <String>[];
      for (final f in fichiers) {
        final src = _sourceSansCommentaires(f.path);
        final lignes = src.split('\n');
        for (var i = 0; i < lignes.length; i++) {
          final l = lignes[i];
          if (!l.contains('recupererDividendesPmuManquants')) continue;
          // La DÉCLARATION n'est pas un appel.
          if (l.contains('Future<int> recupererDividendesPmuManquants')) {
            continue;
          }
          appels.add('${f.path}:${i + 1}: ${l.trim()}');
        }
      }

      // ignore: avoid_print
      print('G-1 appels de recupererDividendesPmuManquants : ${appels.length}');
      for (final a in appels) {
        // ignore: avoid_print
        print('    $a');
      }
      expect(appels, isEmpty,
          reason: 'réactiver cette chaîne exige une décision explicite : '
              'elle rend E_TRIO au lieu de E_TIERCE et peut renvoyer un '
              'rapport arbitraire via `matching.first`.');
    });

    test('G-2 · `fetchDividendePourPari` n\'est appelé que depuis la chaîne '
        'dormante', () {
      const chemin = 'lib/providers/pmu_provider.dart';
      final src = File(chemin).readAsStringSync();

      // On travaille sur les NUMÉROS DE LIGNE DU FICHIER RÉEL : on neutralise
      // les commentaires sur place (sans retirer de ligne) pour que les
      // numéros restent exacts.
      final lignes = src.split('\n').asMap().entries.map((e) {
        final t = e.value.trimLeft();
        final estCommentaire = t.startsWith('//');
        return (numero: e.key + 1, texte: estCommentaire ? '' : e.value);
      }).toList();

      final usages = lignes
          .where((l) => l.texte.contains('fetchDividendePourPari'))
          .map((l) => l.numero)
          .toList();
      // ignore: avoid_print
      print('G-2 usages de fetchDividendePourPari dans pmu_provider : $usages');
      expect(usages.length, 1,
          reason: 'un seul usage, dans recupererDividendesPmuManquants');

      final debut = src.indexOf('Future<int> recupererDividendesPmuManquants');
      final fin = src.indexOf('void _syncStatsTypesIA', debut);
      final corps = src.substring(debut, fin);
      expect(corps.contains('fetchDividendePourPari'), isTrue,
          reason: 'l\'unique usage est bien DANS la méthode dormante');
    });

    test('G-3 · `enregistrerDividendePmuTracked` n\'est appelé nulle part '
        'en production', () {
      final appels = <String>[];
      for (final d in ['lib/screens', 'lib/widgets', 'lib/providers']) {
        final dir = Directory(d);
        if (!dir.existsSync()) continue;
        for (final f in dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
          final lignes = _sourceSansCommentaires(f.path).split('\n');
          for (var i = 0; i < lignes.length; i++) {
            if (lignes[i].contains('enregistrerDividendePmuTracked')) {
              appels.add('${f.path}:${i + 1}');
            }
          }
        }
      }
      // ignore: avoid_print
      print('G-3 appels UI de enregistrerDividendePmuTracked : ${appels.length}');
      expect(appels, isEmpty);
    });

    test('G-4 · la fonction reste PRÉSENTE (rien n\'a été supprimé)', () {
      final src = File('lib/services/alert_service.dart').readAsStringSync();
      expect(src.contains('Future<void> enregistrerDividendePmuTracked'),
          isTrue,
          reason: 'B-4.6 n\'a supprimé aucune fonction : '
              'la garde est une interdiction d\'usage, pas une suppression');
      final prov = File('lib/providers/pmu_provider.dart').readAsStringSync();
      expect(prov.contains('Future<int> recupererDividendesPmuManquants'),
          isTrue);
    });
  });
}
