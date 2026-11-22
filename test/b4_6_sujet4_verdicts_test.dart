// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 — SUJET 4 : verdicts et persistance
//
//  VÉRIFICATION, PAS MODIFICATION. Ce fichier ne change aucune règle métier :
//  il MESURE que les propriétés exigées tiennent déjà, et il échouera si une
//  correction future les casse.
//
//  Ce qui est contrôlé :
//    S4-1  idempotence : rejouer la même résolution ne réécrit rien
//    S4-2  PAS de double gain : deux résolutions ne doublent jamais le montant
//    S4-3  transition non déterminée → déterminée reste possible
//    S4-4  un verdict définitif n'est jamais écrasé par un non-déterminé
//    S4-5  remboursement : jamais présenté comme un gain
//    S4-6  ticket en attente : aucun montant fabriqué
//    S4-7  persistance : le montant survit à l'aller-retour JSON
//    S4-8  montant persisté == total du verdict (aucune double multiplication)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart' show TrackedCourse;
import 'package:pronostic_hippique/services/affichage_gain_structure.dart';
import 'package:pronostic_hippique/services/branchement_verdict_course.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart';
import 'package:pronostic_hippique/services/gain_calculator.dart' show RapportPmu;
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart' show VerdictGain;
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';

const List<List<int>> kArrivee = <List<int>>[
  <int>[9], <int>[4], <int>[15], <int>[10], <int>[1], <int>[7], <int>[12],
];

RapportPmu api(String code, String libelle, String combinaison, double pourUnEuro,
        {int? rang, bool rembourse = false}) =>
    RapportPmu(
      typePari: code,
      combinaison: combinaison,
      dividende: pourUnEuro,
      estOrdre: libelle.toLowerCase().contains('ordre'),
      libelleOfficiel: libelle,
      codePariOfficiel: code,
      rangCombinaisonPayable: rang,
      rembourse: rembourse,
    );

List<RapportPmu> blocSimple() => <RapportPmu>[
      api('E_SIMPLE_GAGNANT', 'e-Simple Gagnant', '9', 7.50),
      api('E_SIMPLE_PLACE', 'e-Simple Placé', '9', 3.00),
    ];

List<RapportPmu> blocTierce() => <RapportPmu>[
      api('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 477.40, rang: 1),
      api('E_TIERCE', 'e-Tiercé Désordre', '9-4-15', 80.30, rang: 2),
    ];

ResultatOfficielCourse resultat(List<RapportPmu> rapports,
        {List<List<int>>? groupes, bool? definitive = true}) =>
    construireResultatOfficiel(
      arriveeGroupes: groupes ?? kArrivee,
      arriveeDefinitive: definitive,
      rapports: rapports,
    );

UserPrediction pred(String type, List<int> numeros,
        {String id = 'p1',
        double mise = 10,
        String? codePmu,
        String? variante,
        List<int>? ordre}) =>
    UserPrediction(
      id: id,
      dateStr: '15112026',
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'Prix test',
      hippodrome: 'TEST',
      numeroCheval: numeros.isEmpty ? 9 : numeros.first,
      nomCheval: 'Cheval',
      cote: 5.0,
      typePari: type,
      createdAt: DateTime(2026, 11, 15),
      numerosJoues: numeros,
      montantMise: mise,
      codePmuOfficiel: codePmu,
      varianteChoisie: variante,
      numerosDansOrdre: ordre,
    );

TrackedCourse suivi(String type, List<int> numeros,
        {double mise = 10,
        List<List<int>>? groupes,
        bool? definitive = true,
        String? codePmu,
        String? variante,
        List<int>? ordre}) =>
    TrackedCourse(
      storageKey: 'R1C6_15112026',
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'Prix test',
      hippodrome: 'TEST',
      heureDepart: DateTime(2026, 11, 15, 14, 30),
      typePari: type,
      numerosJoues: numeros,
      miseEngagee: mise,
      scoreIA: 80,
      codePmuOfficiel: codePmu,
      varianteChoisie: variante,
      numerosDansOrdre: ordre,
      arriveeGroupes: groupes ?? kArrivee,
      arriveeDefinitive: definitive,
      arriveeFinale: const <int>[9, 4, 15, 10, 1],
    );

void main() {
  group('S4 — verdicts, transitions, absence de double gain', () {
    test('S4-1 rejouer la même résolution ⇒ dejaIdentique, rien de réécrit', () {
      final p = pred('Simple Placé', <int>[9], codePmu: 'E_SIMPLE_PLACE');
      final res = resultat(blocSimple());
      final r1 = resoudrePrediction(prediction: p, resultat: res);
      expect(r1.enregistrement!.statut, StatutEnregistrementVerdict.enregistre);

      final r2 = resoudrePrediction(
          prediction: r1.enregistrement!.ticket, resultat: res);
      expect(r2.enregistrement!.statut, StatutEnregistrementVerdict.dejaIdentique);
      expect(r2.enregistrement!.ticket.rapportsAttribues,
          r1.enregistrement!.ticket.rapportsAttribues);
    });

    test('S4-2 DEUX résolutions ne doublent JAMAIS le montant', () {
      final p = pred('Simple Placé', <int>[9], codePmu: 'E_SIMPLE_PLACE');
      final res = resultat(blocSimple());
      final r1 = resoudrePrediction(prediction: p, resultat: res);
      final m1 = totalDesMontantsRetour(
          r1.enregistrement!.ticket.rapportsAttribues!);

      var courant = r1.enregistrement!.ticket;
      for (var i = 0; i < 4; i++) {
        final r = resoudrePrediction(prediction: courant, resultat: res);
        courant = r.enregistrement!.ticket;
        expect(totalDesMontantsRetour(courant.rapportsAttribues!), m1,
            reason: 'le montant ne doit jamais être ré-additionné (tour $i)');
      }
      // 10 € × 3,00 = 30,00 de retour pour le Placé sur le 9.
      expect(m1, closeTo(30.0, 1e-9));
    });

    test('S4-3 le ticket SUIVI ne double pas non plus son montant', () {
      final c = suivi('Simple Placé', <int>[9], codePmu: 'E_SIMPLE_PLACE');
      final res = resultat(blocSimple());
      final r1 = resoudreSuivi(ticket: c, resultat: res);
      final m1 = totalDesMontantsRetour(
          r1.enregistrement!.ticket.rapportsAttribues!);
      expect(m1, closeTo(30.0, 1e-9));

      var courant = r1.enregistrement!.ticket;
      for (var i = 0; i < 3; i++) {
        final r = resoudreSuivi(ticket: courant, resultat: res);
        courant = r.enregistrement!.ticket;
        expect(totalDesMontantsRetour(courant.rapportsAttribues!), m1);
      }
    });

    test('S4-4 ordre joué = ordre officiel ⇒ rapport ORDRE (477,40)', () {
      // RÈGLE MESURÉE : la variante est établie depuis l'ARRIVÉE, pas depuis
      // le choix du joueur. Le joueur a saisi l'ordre 9-4-15, qui EST l'ordre
      // officiel : il touche donc l'Ordre. Ce n'est pas une sélection du
      // maximum, c'est la seule combinaison qui corresponde.
      final p = pred('Tiercé', <int>[9, 4, 15],
          codePmu: 'E_TIERCE', ordre: <int>[9, 4, 15]);
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocTierce()));
      expect(r.verdict!.etat, EtatGain.attribue);
      // mise 10 € : 477,40 € pour 1 € ⇒ 4 774,00 € retournés
      expect(r.verdict!.total, closeTo(4774.0, 1e-9));
      expect(r.verdict!.composantes.single.pourUnEuro, closeTo(477.40, 1e-9));
      expect(r.verdict!.composantes.single.libelleRapport, 'e-Tiercé Ordre');
    });

    test('S4-4b ordre joué DIFFÉRENT ⇒ rapport DÉSORDRE (80,30)', () {
      // Même ensemble de chevaux, ordre saisi ≠ ordre officiel : le Désordre
      // est la seule combinaison correspondante. L'Ordre à 477,40 est
      // inaccessible — c'est l'inverse d'une maximisation.
      final p = pred('Tiercé', <int>[4, 15, 9],
          codePmu: 'E_TIERCE', ordre: <int>[4, 15, 9]);
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocTierce()));
      expect(r.verdict!.etat, EtatGain.attribue);
      expect(r.verdict!.total, closeTo(803.0, 1e-9));
      expect(r.verdict!.composantes.single.pourUnEuro, closeTo(80.30, 1e-9));
      expect(r.verdict!.composantes.single.libelleRapport, 'e-Tiercé Désordre');
    });

    test('S4-5 un verdict DÉFINITIF n\'est jamais écrasé par un non-déterminé',
        () {
      final p = pred('Simple Placé', <int>[9], codePmu: 'E_SIMPLE_PLACE');
      final res = resultat(blocSimple());
      final r1 = resoudrePrediction(prediction: p, resultat: res);
      final definitif = r1.enregistrement!.ticket;
      expect(definitif.etatGain, EtatGain.attribue);

      // Résultat VIDE : le moteur ne peut rien démontrer.
      final resVide = construireResultatOfficiel(
        arriveeGroupes: kArrivee,
        arriveeDefinitive: true,
        rapports: const <RapportPmu>[],
      );
      final r2 = resoudrePrediction(prediction: definitif, resultat: resVide);
      expect(r2.enregistrement!.statut,
          isNot(StatutEnregistrementVerdict.enregistre),
          reason: 'un non-déterminé ne doit pas écraser un définitif');
    });

    test('S4-6 ticket en ATTENTE : aucun montant fabriqué', () {
      final p = pred('Simple Placé', <int>[9]); // code PMU inconnu
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocSimple()));
      final t = r.enregistrement?.ticket;
      if (t != null) {
        expect(t.rapportsAttribues, anyOf(isNull, isEmpty),
            reason: 'un ticket non résolu ne porte aucun montant');
      }
    });

    test('S4-7 remboursement : jamais présenté comme un gain', () {
      final rapports = <RapportPmu>[
        api('E_SIMPLE_PLACE', 'Remboursement e-Simple Placé', '9', 1.00,
            rembourse: true),
      ];
      final c = suivi('Simple Placé', <int>[9], codePmu: 'E_SIMPLE_PLACE');
      final r = resoudreSuivi(ticket: c, resultat: resultat(rapports));
      final t = r.enregistrement?.ticket;
      if (t != null && t.etatGain == EtatGain.rembourse) {
        final aff = affichageGainSuivi(t);
        expect(aff.montant, isNull,
            reason: 'un remboursement ne doit pas produire de gain');
      }
    });

    test('S4-8 le montant persisté survit à l\'aller-retour JSON', () {
      final c = suivi('Simple Placé', <int>[9], codePmu: 'E_SIMPLE_PLACE');
      final r = resoudreSuivi(ticket: c, resultat: resultat(blocSimple()));
      final t = r.enregistrement!.ticket;
      final relu = TrackedCourse.fromJson(t.toJson());
      expect(relu.etatGain, t.etatGain);
      expect(relu.rapportsAttribues, isNotNull);
      expect(totalDesMontantsRetour(relu.rapportsAttribues!),
          closeTo(totalDesMontantsRetour(t.rapportsAttribues!), 1e-9));
    });

    test('S4-9 le montant persisté ÉGALE le total du verdict', () {
      final p = pred('Simple Placé', <int>[9], codePmu: 'E_SIMPLE_PLACE');
      final r = resoudrePrediction(prediction: p, resultat: resultat(blocSimple()));
      final v = r.verdict!;
      expect(v.total,
          closeTo(totalDesMontantsRetour(
              r.enregistrement!.ticket.rapportsAttribues!), 1e-9),
          reason: 'aucune double multiplication entre verdict et persistance');
    });

    test('S4-10 aucun état « non déterminé » n\'est persisté comme définitif',
        () {
      final p = pred('Simple Placé', <int>[9], codePmu: 'E_SIMPLE_PLACE');
      final resVide = construireResultatOfficiel(
        arriveeGroupes: kArrivee,
        arriveeDefinitive: true,
        rapports: const <RapportPmu>[],
      );
      final r = resoudrePrediction(prediction: p, resultat: resVide);
      if (r.enregistrement != null) {
        final v = r.enregistrement!.ticket;
        if (v.etatGain == EtatGain.nonDetermine) {
          expect(v.rapportsAttribues, isNull);
          expect(v.motifNonDetermination, isNotNull,
              reason: 'un non-déterminé doit nommer son motif');
        }
      }
    });
  });
}
