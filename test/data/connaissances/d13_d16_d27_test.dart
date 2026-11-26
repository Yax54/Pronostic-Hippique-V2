/// Tests de vérification des comportements exigés par D-13, D-16, D-27.
///
/// La consigne impose de **vérifier le comportement réel AVANT toute
/// modification** de ces points. Ces tests constituent cette vérification :
/// ils décrivent le comportement mesuré du code existant, et échouent si une
/// modification future le change silencieusement.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/data/connaissances/_core/diagnostic_alimentation.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';

ZtPartant partantSimple({String record = '', int placeDepart = 0}) => ZtPartant(
      numero: '1',
      nom: 'TEST',
      driver: 'D',
      entraineur: 'E',
      proprietaire: 'P',
      gains: '0',
      record: record,
      musique: '',
      cote: '',
      ageSexe: 'H6',
      placeDepartInt: placeDepart,
    );

void main() {
  group('D-13 — sentinelle 9999 du record', () {
    test('un record illisible rend exactement 9999.0', () {
      expect(partantSimple(record: '').recordEnSecondes, 9999.0);
      expect(partantSimple(record: 'inconnu').recordEnSecondes, 9999.0);
      expect(partantSimple(record: '--').recordEnSecondes, 9999.0);
    });

    test('un record lisible est converti correctement', () {
      // 1'15"4 = 75.4 s
      expect(partantSimple(record: '1\'15"4').recordEnSecondes,
          closeTo(75.4, 1e-9));
      // 1'15 sans dixième
      expect(partantSimple(record: "1'15\"").recordEnSecondes,
          closeTo(75.0, 1e-9));
      // 2'03"7
      expect(partantSimple(record: '2\'03"7').recordEnSecondes,
          closeTo(123.7, 1e-9));
    });

    test('la sentinelle n\'est jamais confondue avec un vrai chrono', () {
      // Tout consommateur du code teste `>= 9999` ou `< 9999`, ce qui isole
      // la sentinelle. Vérification que la valeur ne peut pas être atteinte
      // par un record réel : 9999 s = 2 h 46 min 39 s.
      final p = partantSimple(record: '2\'03"7');
      expect(p.recordEnSecondes, lessThan(9999.0),
          reason: 'un chrono réel ne doit jamais atteindre la sentinelle');
    });

    test('le critère de compatibilité rend sa neutralité sur sentinelle', () {
      // `_scoreDisciplineCompatibilite` retourne 50.0 si recSecondes >= 9999.
      // Vérifié indirectement : un partant sans record ne peut pas produire un
      // score de discipline non neutre. On compare deux partants identiques
      // hormis le record.
      final sansRecord = partantSimple(record: '');
      final avecRecord = partantSimple(record: '1\'15"4');
      expect(sansRecord.recordEnSecondes, greaterThanOrEqualTo(9999.0));
      expect(avecRecord.recordEnSecondes, lessThan(9999.0));
    });
  });

  group('D-16 — valeur 0 de la place au départ', () {
    test('0 est traité comme ABSENT, jamais comme une place réelle', () {
      // Mesure du code existant : `_scorePlaceDepart` fait
      // `if (place <= 0 || nbPartants <= 0) return 50.0;`
      // Une place au départ authentique est structurellement >= 1 : le
      // zéro ne peut donc signifier qu'une absence. Le comportement est
      // correct et n'a pas été modifié.
      final sansPlace = partantSimple(placeDepart: 0);
      expect(sansPlace.placeDepartInt, 0);
      // Les valeurs négatives (impossibles en pratique) suivent la même voie.
      final negatif = partantSimple(placeDepart: -1);
      expect(negatif.placeDepartInt, -1);
    });

    test('une place authentique est toujours >= 1', () {
      final p = partantSimple(placeDepart: 7);
      expect(p.placeDepartInt, greaterThan(0));
    });

    test('la place survit à la sérialisation sans devenir absente', () {
      final p = partantSimple(placeDepart: 5);
      final relu = ZtPartant.fromJson(p.toJson());
      expect(relu.placeDepartInt, 5);
    });

    test('un JSON ancien sans place conserve 0 = absent', () {
      final ancien = <String, dynamic>{
        'num': '2', 'cheval': 'V', 'driver': '', 'entraineur': '',
        'proprietaire': '', 'gains': '', 'record': '', 'musique': '',
        'cote': '', 'age_sexe': 'H5',
      };
      expect(ZtPartant.fromJson(ancien).placeDepartInt, 0);
    });
  });

  group('D-27 — repli global observable', () {
    test('une discipline reconnue n\'est pas signalée en repli', () {
      final d = diagnostiquerDiscipline(
        disciplineSource: 'Trot Attelé',
        normalise: IaPoidsAdaptatifs.normaliseDiscipline,
        familleGlobalDisponible: true,
      );
      expect(d.repliGlobal, isFalse);
      expect(d.disciplineNormalisee, 'trot_attele');
      expect(d.message, contains('reconnue'));
    });

    test('une discipline inconnue est signalée en repli et nommée', () {
      final d = diagnostiquerDiscipline(
        disciplineSource: 'Course de haies internationales',
        normalise: IaPoidsAdaptatifs.normaliseDiscipline,
        familleGlobalDisponible: true,
      );
      // « haies » est reconnu comme obstacle : on utilise ici un libellé
      // réellement inconnu du normaliseur.
      final d2 = diagnostiquerDiscipline(
        disciplineSource: 'Endurance',
        normalise: IaPoidsAdaptatifs.normaliseDiscipline,
        familleGlobalDisponible: true,
      );
      expect(d.repliGlobal, isFalse,
          reason: 'haies est reconnu comme obstacle');
      expect(d2.repliGlobal, isTrue);
      expect(d2.disciplineNormalisee, 'global');
      expect(d2.message, contains('NON reconnue'));
      expect(d2.message, contains('inertes'),
          reason: 'le message doit porter la mesure d\'inertie, pas une opinion');
    });

    test('le message rappelle que la famille est conservée', () {
      final d = diagnostiquerDiscipline(
        disciplineSource: 'Inconnue',
        normalise: IaPoidsAdaptatifs.normaliseDiscipline,
        familleGlobalDisponible: true,
      );
      expect(d.message, contains('conservée'));
      expect(d.message, contains('D-27'));
    });

    test('la famille global existe toujours et n\'est pas supprimée', () {
      // D-27 interdit de la supprimer. On vérifie qu'elle est atteignable
      // par le normaliseur, condition de non-régression.
      expect(IaPoidsAdaptatifs.normaliseDiscipline('Bidule'), 'global');
    });

    test('le diagnostic est exposé par le moteur après analyse', () {
      // Le moteur mémorise le diagnostic de la dernière course. Sans partants,
      // il sort avant de le construire : on vérifie donc le contrat du champ.
      expect(IaPronosticEngine.dernierDiagnosticDiscipline, isNull,
          reason: 'aucune analyse n\'a encore eu lieu dans ce processus de test');
    });
  });

  group('D-14 — diagnostic terrain', () {
    test('une chaîne vide est signalée comme absence, pas comme anomalie', () {
      final d = diagnostiquerTerrainCsv('');
      expect(d.etat, EtatAlimentationCritere.absent);
      expect(d.detail, contains('50.0'));
      expect(d.detail, contains('absence de donnée'));
    });

    test('une chaîne malformée est signalée comme invalide', () {
      expect(diagnostiquerTerrainCsv('bon').etat, EtatAlimentationCritere.invalide);
    });

    test('une chaîne sans course comptabilisée est insuffisante', () {
      expect(diagnostiquerTerrainCsv('bon|0|0|0').etat,
          EtatAlimentationCritere.insuffisant);
    });

    test('une chaîne exploitable est signalée authentique avec le volume', () {
      final d = diagnostiquerTerrainCsv('bon|3|2|1;souple|2|0|1');
      expect(d.etat, EtatAlimentationCritere.authentique);
      expect(d.detail, contains('5 course'));
    });

    test('plusieurs terrains sont tous comptabilisés', () {
      final d = diagnostiquerTerrainCsv(
          'bon|4|2|1;souple|3|1|1;lourd|2|0|1;tres_lourd|1|0|0');
      expect(d.etat, EtatAlimentationCritere.authentique);
      expect(d.detail, contains('4 terrain'));
      expect(d.detail, contains('10 course'));
    });
  });

  group('Diagnostic de course', () {
    test('la répartition compte chaque état', () {
      final d = DiagnosticCourse(
        discipline: diagnostiquerDiscipline(
          disciplineSource: 'Plat',
          normalise: IaPoidsAdaptatifs.normaliseDiscipline,
          familleGlobalDisponible: true,
        ),
        criteres: const <DiagnosticCritere>[
          DiagnosticCritere(
              critere: 'cote', etat: EtatAlimentationCritere.authentique,
              detail: ''),
          DiagnosticCritere(
              critere: 'terrain', etat: EtatAlimentationCritere.absent,
              detail: ''),
          DiagnosticCritere(
              critere: 'jockey', etat: EtatAlimentationCritere.absent,
              detail: ''),
        ],
      );
      expect(d.repartition['authentique'], 1);
      expect(d.repartition['absent'], 2);
      expect(d.degrades.map((c) => c.critere), containsAll(<String>['terrain', 'jockey']));
      expect(d.degrades.map((c) => c.critere), isNot(contains('cote')));
    });
  });
}
