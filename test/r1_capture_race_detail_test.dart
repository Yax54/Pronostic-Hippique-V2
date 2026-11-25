// R1 — capture des numéros et du code PMU : contrat de l'ANCIEN écran
//      `race_detail_screen.dart`, SUPPRIMÉ en BL1-A18 (mesuré : 0 instanciation
//      externe, aucun test ne lisait le fichier).
//
// POURQUOI CE FICHIER DE TEST SUBSISTE : ses assertions ne portent PAS sur
// l'écran, mais sur les DEUX fonctions partagées qu'il utilisait et qui, elles,
// restent VIVANTES et utilisées par le parcours actif `showBetSheet` :
//   • `typePmuDepuisLibelleHistorique` / `codeApiPourTypePmu`
//     (`referentiel_paris_pmu.dart`) — source du code PMU officiel ;
//   • la construction de `UserPrediction` avec `numerosJoues` et
//     `codePmuOfficiel`, exactement comme le fait `bet_bottom_sheet.dart`.
// Le contrat financier préservé est donc celui du PARCOURS ACTIF. La
// suppression des seules références au fichier disparu n'affaiblit aucune
// assertion.
//
// Contexte d'origine, conservé : cet écran ne permettait de sélectionner
// QU'UN SEUL cheval, quel que soit le type de pari choisi. Il créait pourtant
// des tickets Simple, Couplé, Tiercé, Quarté+, Quinté+ et Gagnant+Placé.
//
// Ce fichier vérifie ce que la capture fait RÉELLEMENT, sans jamais supposer
// qu'une combinaison complète existe alors qu'un seul numéro a été saisi.
import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/referentiel_paris_pmu.dart';

/// Les sept types RÉELLEMENT proposés par l'ancien `race_detail_screen.dart`
/// (SUPPRIMÉ en BL1-A18 ; conservés ici comme contrat du parcours actif)
/// (mesuré ligne 474 : le Couplé Placé n'y figure pas, contrairement à
/// `bet_bottom_sheet.dart` qui en propose huit).
const List<String> kTypesRaceDetail = [
  'Simple Gagnant',
  'Simple Placé',
  'Gagnant+Placé',
  'Couplé Gagnant',
  'Tiercé',
  'Quarté+',
  'Quinté+',
];

/// Rejoue à l'identique la logique du getter `_codePmuDuTypeChoisi` de
/// `_RaceDetailScreenState` (privé, donc non appelable directement).
String? codePmuPour(String libelle) {
  final type = typePmuDepuisLibelleHistorique(libelle);
  if (type == null) return null;
  return codeApiPourTypePmu(type);
}

/// Rejoue à l'identique `_nbChevauxRequisPour`.
int nbChevauxRequisPour(String libelle) {
  switch (libelle) {
    case 'Couplé Gagnant':
    case 'Couplé Placé':
      return 2;
    case 'Tiercé':
      return 3;
    case 'Quarté+':
      return 4;
    case 'Quinté+':
      return 5;
    case 'Gagnant+Placé':
      return 1;
    default:
      return 1;
  }
}

/// Construit le ticket EXACTEMENT comme le faisait `race_detail_screen.dart`
/// (SUPPRIMÉ en BL1-A18)
/// (supprimé), c'est-à-dire comme le fait toujours `bet_bottom_sheet.dart`.
UserPrediction construireCommeRaceDetail({
  required String typePari,
  required int numeroCheval,
  String nomCheval = 'Cheval Test',
  double cote = 3.5,
}) {
  return UserPrediction(
    id: 'r1',
    dateStr: '2026-01-01',
    numReunion: 1,
    numCourse: 1,
    nomCourse: 'Prix de test',
    hippodrome: 'Vincennes',
    numeroCheval: numeroCheval,
    nomCheval: nomCheval,
    cote: cote,
    typePari: typePari,
    createdAt: DateTime(2026, 1, 1),
    // Ce que fait l'écran depuis R1 :
    numerosJoues: <int>[numeroCheval],
    codePmuOfficiel: codePmuPour(typePari),
    varianteChoisie: null,
    numerosDansOrdre: null,
    formulePari: null,
  );
}

void main() {
  // ───────────────────────────────────────────────────────────────────────
  group('R1/1 — les sept types du référentiel restent proposés', () {
    test('il y a exactement sept types', () {
      expect(kTypesRaceDetail.length, 7);
    });

    test('les sept libellés sont connus du référentiel, sauf Gagnant+Placé', () {
      for (final t in kTypesRaceDetail) {
        if (t == 'Gagnant+Placé') {
          expect(typePmuDepuisLibelleHistorique(t), isNull,
              reason: 'G+P est un ticket applicatif, hors référentiel PMU');
        } else {
          expect(typePmuDepuisLibelleHistorique(t), isNotNull,
              reason: '$t doit être reconnu par le référentiel');
        }
      }
    });

    test('le Couplé Placé, absent de cet écran, est bien hors de la liste', () {
      expect(kTypesRaceDetail.contains('Couplé Placé'), isFalse);
      // …mais il EST reconnu par le référentiel : l'écart est bien un écart
      // d'interface, pas une lacune du référentiel.
      expect(typePmuDepuisLibelleHistorique('Couplé Placé'), isNotNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R1/2 — les codes PMU réellement attribués', () {
    test('correspondance mesurée des sept types', () {
      const attendu = {
        'Simple Gagnant': 'E_SIMPLE_GAGNANT',
        'Simple Placé': 'E_SIMPLE_PLACE',
        'Gagnant+Placé': null,
        'Couplé Gagnant': 'E_COUPLE_GAGNANT',
        'Tiercé': 'E_TIERCE',
        'Quarté+': 'E_QUARTE_PLUS',
        'Quinté+': 'E_QUINTE_PLUS',
      };
      for (final t in kTypesRaceDetail) {
        expect(codePmuPour(t), attendu[t], reason: 'code de « $t »');
      }
    });

    test('six types sur sept portent un code, un seul reste null', () {
      final codes = kTypesRaceDetail.map(codePmuPour).toList();
      expect(codes.where((c) => c != null).length, 6);
      expect(codes.where((c) => c == null).length, 1);
    });

    test('Gagnant+Placé ne reçoit AUCUN code PMU inventé', () {
      expect(codePmuPour('Gagnant+Placé'), isNull);
      final gp = construireCommeRaceDetail(
          typePari: 'Gagnant+Placé', numeroCheval: 5);
      expect(gp.codePmuOfficiel, isNull);
    });

    test('aucun code PMU inventé pour un libellé inconnu', () {
      expect(codePmuPour('Pari Inventé'), isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R1/3 — numéros réellement enregistrés', () {
    test('un seul numéro est enregistré, quel que soit le type', () {
      for (final t in kTypesRaceDetail) {
        final p = construireCommeRaceDetail(typePari: t, numeroCheval: 7);
        expect(p.numerosJoues, [7],
            reason: '$t : l\'écran ne connaît qu\'un cheval');
      }
    });

    test('numerosJoues n\'est plus vide (défaut corrigé)', () {
      final p = construireCommeRaceDetail(
          typePari: 'Simple Gagnant', numeroCheval: 3);
      expect(p.numerosJoues, isNotEmpty);
      expect(p.numerosJoues.length, 1);
    });

    test('aucun cheval inventé pour compléter une combinaison', () {
      // Le cas le plus tentant : un Quinté+ exige 5 chevaux. On vérifie
      // qu'AUCUN n'est fabriqué pour « faire bonne figure ».
      final p = construireCommeRaceDetail(typePari: 'Quinté+', numeroCheval: 9);
      expect(p.numerosJoues.length, 1);
      expect(p.numerosJoues, [9]);
      expect(nbChevauxRequisPour('Quinté+'), 5);
      expect(p.numerosJoues.length, lessThan(nbChevauxRequisPour('Quinté+')),
          reason: 'la combinaison est incomplète, et elle doit le rester');
    });

    test('numeroCheval reste cohérent avec numerosJoues', () {
      final p = construireCommeRaceDetail(typePari: 'Tiercé', numeroCheval: 12);
      expect(p.numeroCheval, 12);
      expect(p.numerosJoues, contains(p.numeroCheval));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R1/4 — les trois champs facultatifs restent null', () {
    test('varianteChoisie, numerosDansOrdre, formulePari sont null', () {
      for (final t in kTypesRaceDetail) {
        final p = construireCommeRaceDetail(typePari: t, numeroCheval: 4);
        expect(p.varianteChoisie, isNull, reason: '$t : aucune variante saisie');
        expect(p.numerosDansOrdre, isNull, reason: '$t : ordre inconnu');
        expect(p.formulePari, isNull, reason: '$t : aucune formule');
      }
    });

    test('aucune variante déduite d\'un libellé générique', () {
      // « Tiercé » est payable Ordre ET Désordre : le référentiel le dit.
      // L'écran ne doit donc surtout pas trancher à la place du parieur.
      final p = construireCommeRaceDetail(typePari: 'Tiercé', numeroCheval: 2);
      expect(p.varianteChoisie, isNull);
      final type = typePmuDepuisLibelleHistorique('Tiercé')!;
      expect(variantesPayables(type)!.length, 2,
          reason: 'deux variantes payables : le choix appartient au parieur');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R1/5 — montant jamais inventé', () {
    test('montantMise reste au défaut du modèle (0.0)', () {
      final p = construireCommeRaceDetail(
          typePari: 'Simple Gagnant', numeroCheval: 1);
      expect(p.montantMise, 0.0,
          reason: 'cet écran ne saisit aucune mise : elle n\'est pas inventée');
    });

    test('les composantes G+P restent null (aucune mise fabriquée)', () {
      final p = construireCommeRaceDetail(
          typePari: 'Gagnant+Placé', numeroCheval: 6);
      expect(p.miseGagnant, isNull);
      expect(p.misePlace, isNull);
      expect(p.coteGagnant, isNull);
      expect(p.cotePlace, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R1/6 — sérialisation JSON', () {
    test('les numéros et le code PMU survivent à l\'aller-retour', () {
      final p = construireCommeRaceDetail(typePari: 'Tiercé', numeroCheval: 8);
      final relu = UserPrediction.fromJson(p.toJson());
      expect(relu.numerosJoues, [8]);
      expect(relu.codePmuOfficiel, 'E_TIERCE');
      expect(relu.varianteChoisie, isNull);
      expect(relu.numerosDansOrdre, isNull);
      expect(relu.formulePari, isNull);
    });

    test('Gagnant+Placé sérialise un code null sans erreur', () {
      final p = construireCommeRaceDetail(
          typePari: 'Gagnant+Placé', numeroCheval: 3);
      final map = p.toJson();
      expect(map.containsKey('codePmuOfficiel'), isTrue);
      expect(map['codePmuOfficiel'], isNull);
      final relu = UserPrediction.fromJson(map);
      expect(relu.codePmuOfficiel, isNull);
      expect(relu.numerosJoues, [3]);
    });

    test('le JSON reste encodable pour les sept types', () {
      for (final t in kTypesRaceDetail) {
        final p = construireCommeRaceDetail(typePari: t, numeroCheval: 1);
        expect(() => p.toJson(), returnsNormally);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R1/7 — informations historiques préservées', () {
    test('les champs d\'origine sont tous renseignés', () {
      final p = construireCommeRaceDetail(
          typePari: 'Simple Placé', numeroCheval: 11, nomCheval: 'Idéal');
      expect(p.numeroCheval, 11);
      expect(p.nomCheval, 'Idéal');
      expect(p.cote, 3.5);
      expect(p.typePari, 'Simple Placé');
      expect(p.nomCourse, 'Prix de test');
      expect(p.hippodrome, 'Vincennes');
    });

    test('typePari n\'est pas normalisé (le libellé reste tel quel)', () {
      final p = construireCommeRaceDetail(typePari: 'Quinté+', numeroCheval: 1);
      expect(p.typePari, 'Quinté+');
    });
  });
}
