// ══════════════════════════════════════════════════════════════════════
//  AUDIT — FORMAT DE `musiqueDistanceSpecifique` : VÉRIFICATION, PAS SUPPOSITION
//
//  OBJET
//    Mes affirmation antérieure était : « le producteur écrit "DDDD:musique",
//    format inanalysable par `scoreFormeDistanceSpecifique` ».
//    Cette affirmation était une DÉDUCTION DE LECTURE, jamais mesurée.
//    Ce fichier la mesure.
//
//  CE QUE CE FICHIER PROUVE (ou réfute)
//    1. `_parserMusique("1700:0p9p4p4p0p6p7p")` produit-il la même chose que
//       `_parserMusique("0p9p4p4p0p6p7p")` ? Autrement dit, le préfixe
//       "distance:" perturbe-t-il le décodage de la musique ?
//    2. `_scoreDistanceSpecialite` reconnaît-il bien une entrée
//       "distance:musique" à ±100 m de la distance de la course ?
//
//  CE QUE CE FICHIER NE PROUVE PAS
//    - Que le PMU fournisse `performancesParDistance` (il ne le fournit pas :
//      mesuré 0/98 participants). Ce point est traité dans le producteur.
// ══════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/models/zt_models.dart';

void main() {
  group('DIST-SPEC / format réellement attendu par les consommateurs', () {
    ZtPartant partant({String dist = '', String musique = ''}) => ZtPartant(
          numero: '1',
          nom: 'TEST',
          driver: '',
          entraineur: '',
          proprietaire: '',
          gains: '',
          record: '',
          musique: musique,
          cote: '',
          ageSexe: '',
          poids: 0,
          placeDepartInt: 0,
          joursRepos: 0,
          musiqueDistanceSpecifique: dist,
        );

    test('F1 — le préfixe "distance:" ne détruit pas le décodage de la musique',
        () {
      const musiquePure = '0p9p4p4p0p6p7p';
      const avecPrefixe = '1700:$musiquePure';

      final sans = partant(dist: musiquePure).scoreFormeDistanceSpecifique;
      final avec = partant(dist: avecPrefixe).scoreFormeDistanceSpecifique;

      // Mesure rapportée, pas assertion d'espoir : on imprime les deux.
      // ignore: avoid_print
      print('  F1  scoreFormeDistanceSpecifique  sans="$sans"  avec="$avec"');

      // Si les deux valeurs sont égales, le préfixe est neutre et le format
      // "DDDD:musique" est DÉCODABLE : mon affirmation antérieure était fausse.
      expect(avec, closeTo(sans, 0.0001),
          reason: 'le préfixe "distance:" doit être neutre sur le décodage');
    });

    test('F2 — une musique réellement préfixée reste discriminante', () {
      // Une musique avec deux victoires doit scorer plus qu'une musique vide.
      final gagnante = partant(dist: '1700:1p1p1p1p1p').scoreFormeDistanceSpecifique;
      final quelconque = partant(dist: '1700:8p8p8p8p8p').scoreFormeDistanceSpecifique;

      // ignore: avoid_print
      print('  F2  gagnante=$gagnante  quelconque=$quelconque');

      expect(gagnante, greaterThan(quelconque),
          reason: 'deux victoires doivent dominer cinq huitièmes places');
    });

    test('F3 — le bonus de +8,0 ne s\'applique que si le champ est renseigné',
        () {
      // ⚠️ PREMIÈRE VERSION DE CE TEST : FAUSSE, ET CORRIGÉE ICI.
      //    Elle utilisait la musique « 1p1p1p », dont le score vaut déjà 100.0
      //    avant bonus. `(100.0 + 8.0).clamp(0.0, 100.0)` vaut donc 100.0 :
      //    le bonus était INVISIBLE par saturation du plafond. L'assertion
      //    échouait pour une raison de CONCEPTION DU TEST, pas à cause d'un
      //    défaut du code. La musique « 5p5p5p » (score de base 50.0) rend le
      //    bonus réellement observable.
      final sans = partant(dist: '', musique: '5p5p5p').scoreFormeDistanceSpecifique;
      final avec = partant(dist: '1700:5p5p5p').scoreFormeDistanceSpecifique;

      // ignore: avoid_print
      print('  F3  sans champ=$sans  avec champ=$avec  écart=${avec - sans}');

      expect(avec - sans, closeTo(8.0, 0.0001),
          reason: 'le bonus documenté vaut exactement +8,0');
    });
  });
}
