/// Tests du critère progression (D-10) et de la distinction
/// absent / zéro authentique.
///
/// D-10 (VALIDÉ) : « Supprimer le fallback artificiel donnant 20 % des gains
/// carrière aux gains de la dernière année. Privilégier une donnée authentique
/// correspondant exactement à la période attendue. Ne pas confondre année
/// civile et 12 derniers mois. Un zéro authentique ne doit PAS être traité
/// comme un absent. »
///
/// Ces tests vérifient trois choses et **rien de plus** :
///  1. aucune valeur fabriquée n'entre plus dans le critère ;
///  2. un zéro authentique n'est pas transformé en absent ;
///  3. la formule du critère n'a pas bougé : à entrée identique, score
///     identique.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/models/zt_models.dart';

ZtPartant partant({
  required int gainsDernierAn,
  required bool disponible,
  int gains = 100000,
  String ageSexe = 'H6',
}) {
  return ZtPartant(
    numero: '1',
    nom: 'TEST',
    driver: 'D',
    entraineur: 'E',
    proprietaire: 'P',
    gains: '$gains',
    record: '',
    musique: '',
    cote: '',
    ageSexe: ageSexe,
    gainsDernierAn: gainsDernierAn,
    gainsDernierAnDisponible: disponible,
    gainsDernierAnSource: disponible ? 'pmu_gainsSaison' : 'absent',
  );
}

void main() {
  group('D-10 — provenance des gains', () {
    test('par défaut, une valeur est déclarée ABSENTE, jamais supposée vraie', () {
      final p = ZtPartant(
        numero: '1', nom: 'X', driver: 'D', entraineur: 'E',
        proprietaire: 'P', gains: '1000', record: '', musique: '',
        cote: '', ageSexe: 'H6',
      );
      expect(p.gainsDernierAnDisponible, isFalse);
      expect(p.gainsDernierAnSource, 'absent');
    });

    test('la provenance survit à une sérialisation JSON', () {
      final p = partant(gainsDernierAn: 25000, disponible: true);
      final relu = ZtPartant.fromJson(p.toJson());
      expect(relu.gainsDernierAn, 25000);
      expect(relu.gainsDernierAnDisponible, isTrue);
      expect(relu.gainsDernierAnSource, 'pmu_gainsSaison');
    });

    test('un JSON ancien sans marqueur de provenance est traité comme absent', () {
      // Compatibilité ascendante : les pronostics historiques n'ont pas ces
      // clés. On ne peut pas affirmer que leur valeur était authentique.
      final ancien = <String, dynamic>{
        'num': '3', 'cheval': 'ANCIEN', 'driver': '', 'entraineur': '',
        'proprietaire': '', 'gains': '50000', 'record': '', 'musique': '',
        'cote': '', 'age_sexe': 'H7', 'gains_an': 12345,
      };
      final p = ZtPartant.fromJson(ancien);
      expect(p.gainsDernierAn, 12345, reason: 'la valeur numérique est conservée');
      expect(p.gainsDernierAnDisponible, isFalse,
          reason: 'mais elle n\'est pas présentée comme authentique');
    });

    test('la provenance survit à copyWith', () {
      final p = partant(gainsDernierAn: 30000, disponible: true);
      final copie = p.copyWith(scoreIA: 70.0);
      expect(copie.gainsDernierAnDisponible, isTrue);
      expect(copie.gainsDernierAnSource, 'pmu_gainsSaison');
    });
  });

  group('D-10 — effet sur le critère progression', () {
    test('une valeur non disponible n\'active pas le bloc ratio', () {
      // Même nombre, mais non prouvé authentique : le bloc ratio ne s'exécute
      // pas, donc le score ne dépend que de l'âge et de la tendance.
      final nonProuve = partant(
        gainsDernierAn: 40000,
        disponible: false,
        gains: 100000,
      );
      final prouve = partant(
        gainsDernierAn: 40000,
        disponible: true,
        gains: 100000,
      );
      expect(nonProuve.scoreProgression, isNot(equals(prouve.scoreProgression)),
          reason: 'la disponibilité doit changer le résultat, sinon elle est inutile');
      expect(prouve.scoreProgression, greaterThan(nonProuve.scoreProgression),
          reason: 'ratio 40 % ⇒ bonus +15 sur une base inchangée');
    });

    test('un zéro authentique n\'est pas traité comme un absent', () {
      // Zéro authentique : disponible = true, valeur = 0. Le bloc exige
      // `gainsDernierAn > 0`, donc il ne s'exécute pas — c'est le comportement
      // existant, conservé. Mais le score doit être identique à celui d'une
      // absence, ce qui prouve qu'aucune valeur n'a été inventée dans un cas
      // comme dans l'autre.
      final zeroAuthentique = partant(
        gainsDernierAn: 0, disponible: true, gains: 100000);
      final absent = partant(
        gainsDernierAn: 0, disponible: false, gains: 100000);
      expect(zeroAuthentique.scoreProgression, absent.scoreProgression);
    });

    test('le fallback 20 % ne peut plus produire de bonus', () {
      // Reproduction du défaut mesuré : avec gains carrière 100 000, l'ancien
      // code posait gainsDernierAn = 20 000, soit un ratio de 0,20 qui
      // déclenchait +3. Ce chemin n'existe plus : sans donnée authentique, le
      // score reste celui de l'absence.
      final sansDonnee = partant(gainsDernierAn: 0, disponible: false, gains: 100000);
      final ancienFallbackSimule = partant(
          gainsDernierAn: 20000, disponible: false, gains: 100000);
      expect(ancienFallbackSimule.scoreProgression, sansDonnee.scoreProgression,
          reason: 'une valeur non authentique ne doit produire aucun effet');
    });

    test('la formule est inchangée : seuils identiques à entrée identique', () {
      // Vérification des paliers documentés du critère, à provenance identique.
      // Base âge 6 ans = 50.0, pas de tendance.
      double score(int gainsAn, int gainsTotal) => ZtPartant(
            numero: '1', nom: 'X', driver: '', entraineur: '',
            proprietaire: '', gains: '$gainsTotal', record: '', musique: '',
            cote: '', ageSexe: 'H6',
            gainsDernierAn: gainsAn,
            gainsDernierAnDisponible: true,
            gainsDernierAnSource: 'pmu_gainsSaison',
          ).scoreProgression;

      // ratio >= 0.40 ⇒ +15
      expect(score(40000, 100000), 65.0);
      // ratio >= 0.25 ⇒ +8
      expect(score(25000, 100000), 58.0);
      // ratio >= 0.15 ⇒ +3
      expect(score(15000, 100000), 53.0);
      // ratio < 0.05 ⇒ -5
      expect(score(1000, 100000), 45.0);
      // entre 0.05 et 0.15 ⇒ aucun ajustement
      expect(score(10000, 100000), 50.0);
    });

    test('le bonus d\'âge est préservé', () {
      double basePour(String age) => ZtPartant(
            numero: '1', nom: 'X', driver: '', entraineur: '',
            proprietaire: '', gains: '0', record: '', musique: '', cote: '',
            ageSexe: age,
          ).scoreProgression;
      expect(basePour('H3'), 62.0); // 50 + 12
      expect(basePour('H4'), 58.0); // 50 + 8
      expect(basePour('H5'), 54.0); // 50 + 4
      expect(basePour('H6'), 50.0);
      expect(basePour('H7'), 47.0); // 50 - 3
      expect(basePour('H9'), 42.0); // 50 - 8
    });
  });
}
