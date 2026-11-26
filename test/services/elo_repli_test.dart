/// ELO : le repli de 1500 ne doit pas devenir une note de 37,5.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  LE DÉFAUT MESURÉ
///
///  `enrichirAvecElo` écrivait `eloRating = score.rating` sans condition.
///  `getScore()` rend `EloScore(rating: 1500)` quand aucun rating n'existe.
///  `ZtPartant.scoreElo` normalise `((rating - 1200) / 8)` :
///
///        1500 → 37,5
///
///  Un cheval dont on ne savait RIEN recevait donc 37,5 / 100 — une note
///  inférieure à la neutralité (50), présentée au moteur comme une évaluation.
///  Le repli ne se contentait pas d'être muet : il pénalisait.
///
///  Ce fichier mesure quatre situations distinctes, que §9 exige de ne pas
///  confondre :
///    1. donnée AUTHENTIQUE      → rating réel, note d'origine conservée ;
///    2. donnée ABSENTE          → aucune connaissance → neutralité 50,0 ;
///    3. VALEUR DE REPLI         → 1500 reste 37,5 si et seulement si elle est
///                                 un rating réellement attribué (nbCourses > 0) ;
///    4. NEUTRALITÉ LÉGITIME     → 50,0 atteint par absence, pas par calcul.
///
///  Aucune formule n'est modifiée par ce fichier : il CONSTATE.
/// ═══════════════════════════════════════════════════════════════════════════
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/zt_models.dart' show ZtPartant;

/// Partant minimal dont seul le nom et l'ELO nous intéressent.
ZtPartant _partant(String nom) => ZtPartant(
      numero: '1',
      nom: nom,
      driver: '',
      entraineur: '',
      proprietaire: '',
      gains: '0',
      record: '',
      musique: '',
      cote: '',
      ageSexe: '',
    );

/// Applique la normalisation du modèle, telle quelle, sans la réécrire.
double _noteElo(ZtPartant p) => p.scoreElo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ELO : repli, absent, authentique et neutre', () {
    test('la valeur de repli 1500 produisait bien 37,5 — arithmétique vérifiée',
        () {
      // On construit le partant avec le rating de repli, exactement comme le
      // faisait `enrichirAvecElo` avant correction.
      final p = _partant('INCONNU').copyWith(eloRating: 1500.0);
      final note = _noteElo(p);
      // ignore: avoid_print
      print('[MESURE] repli 1500 => scoreElo = $note '
          '(calcul: (1500-1200)/8 = ${(1500 - 1200) / 8})');
      expect(note, 37.5,
          reason: 'la signature arithmétique du repli doit être confirmée');
    });

    test('zéro rating signifie INCONNU et donne la neutralité, pas 37,5', () {
      final p = _partant('INCONNU').copyWith(eloRating: 0.0);
      final note = _noteElo(p);
      // ignore: avoid_print
      print('[MESURE] absent (eloRating=0) => scoreElo = $note');
      expect(note, 50.0,
          reason: 'l\'absence de connaissance doit rendre la neutralité 50,0');
      expect(p.eloRating, 0.0,
          reason: '0 est la convention documentée du modèle : inconnu');
    });

    test('un rating AUTHENTIQUE de 1500 garde exactement 37,5', () {
      // Le cas piège : un cheval qui a réellement un rating de 1500 après
      // plusieurs courses. La correction ne doit SURTOUT PAS le changer en 50.
      // C'est `nbCourses` qui distingue les deux situations, pas le rating.
      final reel = _partant('REEL').copyWith(
        eloRating: 1500.0,
        eloNbCourses: 12,
      );
      // ignore: avoid_print
      print('[MESURE] rating authentique 1500 sur 12 course(s) => '
          'scoreElo = ${_noteElo(reel)} (inchangé : la formule est intacte)');
      expect(_noteElo(reel), 37.5);
      expect(reel.eloNbCourses, 12);
    });

    test('les quatre situations sont numériquement distinctes', () {
      final absent = _partant('A').copyWith(eloRating: 0.0);
      final authentique = _partant('B').copyWith(
          eloRating: 1500.0, eloNbCourses: 12);
      final fort = _partant('C').copyWith(eloRating: 1800.0, eloNbCourses: 30);
      final faible = _partant('D').copyWith(eloRating: 1200.0, eloNbCourses: 5);

      final mesures = <String, double>{
        'absent': _noteElo(absent),
        'authentique_1500': _noteElo(authentique),
        'fort_1800': _noteElo(fort),
        'faible_1200': _noteElo(faible),
      };
      // ignore: avoid_print
      print('[MESURE] quatre situations : $mesures');

      expect(mesures['absent'], 50.0);
      expect(mesures['authentique_1500'], 37.5);
      expect(mesures['fort_1800'], 75.0);
      expect(mesures['faible_1200'], 0.0);

      // Absent et authentique-1500 donnent des notes DIFFÉRENTES : c'est
      // précisément ce que le défaut confondait.
      expect(mesures['absent'], isNot(mesures['authentique_1500']));
    });

    test('un rating absent ne peut plus être confondu avec un mauvais cheval',
        () {
      // Avant correction, ces deux partants avaient la MÊME note 37,5 : l'un
      // par absence totale de connaissance, l'autre par rating réel médiocre.
      final inconnu = _partant('INCONNU').copyWith(eloRating: 0.0);
      final mediocre = _partant('MEDIOCRE').copyWith(
          eloRating: 1500.0, eloNbCourses: 20);
      // ignore: avoid_print
      print('[MESURE] inconnu=${_noteElo(inconnu)} vs '
          'médiocre=${_noteElo(mediocre)} — avant correction : 37.5 / 37.5');
      expect(_noteElo(inconnu), isNot(_noteElo(mediocre)));
    });
  });
}
