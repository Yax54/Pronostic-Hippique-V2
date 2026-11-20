// ═══════════════════════════════════════════════════════════════════════════
//  A-0 / T7 — Helper « Gagnant + Placé » : reconnaissance exacte
//
//  ⚠️  Ces tests vérifient UNIQUEMENT la fonction pure `estTypeGagnantPlace`.
//      Ils ne prétendent pas que le Lot A-0 couvre tous les cas de figure :
//      ils garantissent que la catégorie « Gagnant + Placé » est reconnue
//      sur les 3 libellés réels et qu'elle ne déborde sur AUCUN autre type.
//
//  Le risque visé est précis : une garde trop large désactiverait à tort les
//  écritures financières de paris parfaitement calculables (Simple Gagnant,
//  Simple Placé, Couplé, Tiercé, Quarté+, Quinté+). Ce fichier prouve le
//  contraire, libellé par libellé.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/utils/type_pari_utils.dart';

void main() {
  group('A-0 / T7 — reconnaissance des libellés Gagnant+Placé', () {
    test('T7a — les 3 libellés réels du code sont reconnus', () {
      // Mesurés dans lib/ :
      //   'Gagnant+Placé'   → bet_bottom_sheet.dart:128, mes_paris_screen.dart:2675
      //   'Gagnant + Placé' → gain_calculator.dart:457
      //   'Gagnant+Place'   → tolérance historique
      expect(estTypeGagnantPlace('Gagnant+Placé'), isTrue);
      expect(estTypeGagnantPlace('Gagnant + Placé'), isTrue);
      expect(estTypeGagnantPlace('Gagnant+Place'), isTrue);
    });

    test('T7b — insensible à la casse et aux espaces de bord', () {
      expect(estTypeGagnantPlace('GAGNANT+PLACÉ'), isTrue);
      expect(estTypeGagnantPlace('gagnant+placé'), isTrue);
      expect(estTypeGagnantPlace('  Gagnant+Placé  '), isTrue);
      expect(estTypeGagnantPlace('Gagnant +placé'), isFalse,
          reason: 'une espace mal placée n\'est pas un libellé réel du code');
    });

    test('T7c — les paris MONO-composante ne sont JAMAIS neutralisés', () {
      // Régression critique : ces types doivent continuer d'être écrits
      // exactement comme avant le Lot A-0.
      const monoComposante = [
        'Simple Gagnant',
        'Simple Placé',
        'Placé',
        'Couplé Gagnant',
        'Couplé Placé',
        'Tiercé',
        'Quarté+',
        'Quinté+',
      ];
      for (final t in monoComposante) {
        expect(estTypeGagnantPlace(t), isFalse, reason: 'ne doit pas matcher: $t');
      }
    });

    test('T7d — les 12 libellés de mes_paris_screen ne débordent pas', () {
      // Liste réelle : mes_paris_screen.dart:2674-2687 (12 entrées).
      const douze = [
        'Simple Gagnant',
        'Simple Placé',
        'Gagnant+Placé',
        'Couplé Gagnant',
        'Couplé Placé',
        'Couplé Ordre',
        'Couplé Désordre',
        'Tiercé',
        'Tiercé Ordre',
        'Tiercé Désordre',
        'Quarté+',
        'Quinté+',
      ];
      final reconnus = douze.where(estTypeGagnantPlace).toList();
      expect(reconnus, ['Gagnant+Placé'],
          reason: 'un seul des 12 libellés doit être reconnu G+P');
    });

    test('T7e — null et chaîne vide ne matchent pas', () {
      expect(estTypeGagnantPlace(null), isFalse);
      expect(estTypeGagnantPlace(''), isFalse);
      expect(estTypeGagnantPlace('   '), isFalse);
    });

    test('T7f — la fonction est PURE (appel répété = même résultat)', () {
      expect(estTypeGagnantPlace('Gagnant+Placé'), isTrue);
      expect(estTypeGagnantPlace('Gagnant+Placé'), isTrue);
      expect(estTypeGagnantPlace('Simple Gagnant'), isFalse);
      expect(estTypeGagnantPlace('Simple Gagnant'), isFalse);
    });

    test('T7g — le jeu de libellés exposé est exactement de 3 entrées', () {
      expect(kLibellesGagnantPlace.length, 3);
      expect(kLibellesGagnantPlace.contains('gagnant+placé'), isTrue);
      expect(kLibellesGagnantPlace.contains('gagnant + placé'), isTrue);
      expect(kLibellesGagnantPlace.contains('gagnant+place'), isTrue);
    });
  });
}
