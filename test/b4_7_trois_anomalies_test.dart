// ═══════════════════════════════════════════════════════════════════════════
//  B-4.7 — LES TROIS ANOMALIES SIGNALÉES PAR L'UTILISATEUR
//
//  Chaque test ci-dessous ÉCHOUE sur le code d'avant la correction et passe
//  après. Ils ne mesurent donc pas un comportement décoratif : ils épinglent
//  exactement les trois défauts arbitrés.
//
//  ── ANOMALIE 1 — un pari PERDANT reste « en attente » ────────────────────
//  Le moteur ne savait démontrer qu'un gain, par correspondance exacte. Une
//  combinaison ABSENTE d'un bloc pourtant COMPLET n'était pas une perte mais
//  un `blocJusteAbsent`. La preuve de complétude est établie par RECOUPEMENT
//  avec l'arrivée officielle (mesuré : 299/299 Simple Gagnant, 299/299 Simple
//  Placé, 192/192 Couplé Gagnant, 191/191 Couplé Placé, ZÉRO trou de rang sur
//  308 captures). Elle n'est JAMAIS supposée : si le bloc ne recoupe pas
//  l'arrivée, le verdict reste `nonDetermine`.
//
//  ── ANOMALIE 2 — un `nonDetermine` ne devient jamais définitif ──────────
//  La branche A refusait toute transition. Elle l'autorise désormais quand les
//  données DÉMONTRENT le verdict, en restant idempotente et sans jamais
//  réécrire un verdict définitif.
//
//  ── ANOMALIE 3 — Tiercé Désordre déclaré `blocJusteAbsent` ──────────────
//  La variante était déduite de l'ARRIVÉE. Or Ordre et Désordre publient la
//  MÊME combinaison (mesuré 20/20) : la variante se déduit du LIBELLÉ, donc
//  du pari réellement joué.
//
//  ⚠️ AUCUN MONTANT N'EST INVENTÉ : chaque dividende asserté provient d'une
//     capture réelle lue par le DÉCODEUR DE PRODUCTION.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/branchement_verdict_course.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart'
    show ResultatEnregistrementVerdict, StatutEnregistrementVerdict;
import 'package:pronostic_hippique/services/gain_calculator.dart'
    show RapportPmu;
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart' show VerdictGain;
import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';
import 'fixtures/fixture_paths.dart';

final String kDossier = dossierMulti;

List<RapportPmu> rapportsDe(String nom) =>
    PmuApiService.decoderRapportsDefinitifs(
      File('$kDossier/$nom').readAsStringSync(),
    );

/// R1C6 15112026 : arrivée 9-4-15-10-1-7-12.
/// Simple Gagnant 9 @ 7,50 € ; Simple Placé 9 @ 3,00 €, 4 @ 2,60 €, 15 @ 6,90 € ;
/// Couplé Gagnant 9-4 ; e-Tiercé Ordre 9-4-15 @ 477,40 € ;
/// e-Tiercé Désordre 9-4-15 @ 80,30 €.
const List<List<int>> kArriveeR1C6 = <List<int>>[
  <int>[9], <int>[4], <int>[15], <int>[10], <int>[1], <int>[7], <int>[12],
];

const String kCaptureR1C6 = 'R1C6_15112026.json';

/// Code PMU du bloc réellement joué, tel que l'application l'enregistre.
/// Mesuré : `tiercé`/`tiercéOrdre`/`tiercéDesordre` partagent `E_TIERCE`.
String? _codeDe(String type) {
  switch (type) {
    case 'Simple Gagnant':
      return 'E_SIMPLE_GAGNANT';
    case 'Simple Placé':
      return 'E_SIMPLE_PLACE';
    case 'Couplé Gagnant':
      return 'E_COUPLE_GAGNANT';
    case 'Couplé Placé':
      return 'E_COUPLE_PLACE';
    case 'Tiercé':
    case 'Tiercé Ordre':
    case 'Tiercé Désordre':
      return 'E_TIERCE';
    default:
      return null;
  }
}

/// Variante EXPLICITEMENT choisie à la saisie, quand le libellé l'impose.
String? _varianteDe(String type) {
  switch (type) {
    case 'Tiercé Ordre':
    case 'Couplé Ordre':
      return 'ordre';
    case 'Tiercé Désordre':
      return 'desordre';
    default:
      return null;
  }
}

UserPrediction pred(
  String type,
  List<int> numeros, {
  double mise = 10,
  double? miseGagnant,
  double? misePlace,
  List<int>? ordre,
  String id = 'p1',
}) =>
    UserPrediction(
      id: id,
      dateStr: '15112026',
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'Course test',
      hippodrome: 'TEST',
      numeroCheval: numeros.first,
      nomCheval: 'Cheval',
      cote: 5.0,
      typePari: type,
      createdAt: DateTime(2026, 11, 15),
      numerosJoues: numeros,
      montantMise: mise,
      codePmuOfficiel: _codeDe(type),
      miseGagnant: miseGagnant,
      misePlace: misePlace,
      // L'ordre réellement joué est TOUJOURS transmis : c'est ce que fait la
      // saisie. Aucun repli n'est fait sur la liste triée.
      numerosDansOrdre: ordre ?? numeros,
      varianteChoisie: _varianteDe(type),
    );

ResultatOfficielCourse resultat(
  List<RapportPmu> rapports, {
  List<List<int>>? groupes,
  bool? definitive = true,
}) =>
    construireResultatOfficiel(
      arriveeGroupes: groupes,
      arriveeDefinitive: definitive,
      rapports: rapports,
    );

// ── Accès sûrs aux résultats de résolution ────────────────────────────────
VerdictGain vDe(ResolutionTicketPrediction r) => r.verdict!;
ResultatEnregistrementVerdict eDe(ResolutionTicketPrediction r) =>
    r.enregistrement!;
UserPrediction tDe(ResolutionTicketPrediction r) => r.enregistrement!.ticket;

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  ANOMALIE 1 — LA PERTE DÉMONTRÉE CESSE D'ÊTRE UNE ATTENTE
  // ═════════════════════════════════════════════════════════════════════════
  group('A1 — pari réellement perdant', () {
    test('A1/1 Simple Gagnant sur un cheval qui n\'est PAS le gagnant '
        '⇒ perdu, et la perte est PERSISTÉE', () {
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6);
      // Le 15 est 3e de l'arrivée : son bloc Simple Gagnant (9) est complet
      // et le recoupement prouve que 15 ne peut pas être le gagnant.
      final res = resoudrePrediction(
        prediction: pred('Simple Gagnant', <int>[15]),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.perdu);
      expect(vDe(res).motif, isNull);
      expect(vDe(res).total, 0.0);
      expect(eDe(res).estEnregistre, isTrue,
          reason: 'avant correction : refuseVerdictSansRapportAvecRapports');
      expect(tDe(res).etatGain, EtatGain.perdu);
    });

    test('A1/2 Simple Placé sur un cheval hors des rangs payables ⇒ perdu', () {
      // Arrivée 9-4-15 : les rangs payables sont 9, 4, 15. Le 12 est 7e.
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6);
      final res = resoudrePrediction(
        prediction: pred('Simple Placé', <int>[12]),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.perdu);
      expect(eDe(res).estEnregistre, isTrue);
    });

    test('A1/3 Couplé Gagnant sur une paire qui n\'est pas celle de tête '
        '⇒ perdu', () {
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6);
      final res = resoudrePrediction(
        prediction: pred('Couplé Gagnant', <int>[1, 2]),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.perdu);
    });

    test('A1/4 Tiercé sur une combinaison quelconque ⇒ perdu (déjà établi '
        'par l\'arbitre, témoin de non-régression)', () {
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6);
      final res = resoudrePrediction(
        prediction: pred('Tiercé', <int>[1, 2, 3]),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.perdu);
      expect(eDe(res).estEnregistre, isTrue);
    });

    test('A1/5 SÉCURITÉ : sans arrivée officielle, la perte n\'est PAS '
        'prononcée — on ne transforme pas une donnée absente en défaite', () {
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: null);
      final res = resoudrePrediction(
        prediction: pred('Simple Gagnant', <int>[15]),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.nonDetermine,
          reason: 'aucune arrivée ⇒ aucune preuve de complétude possible');
    });

    test('A1/6 SÉCURITÉ : arrivée explicitement PROVISOIRE ⇒ jamais perdu',
        () {
      final r = resultat(
        rapportsDe(kCaptureR1C6),
        groupes: kArriveeR1C6,
        definitive: false,
      );
      final res = resoudrePrediction(
        prediction: pred('Simple Gagnant', <int>[15]),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.nonDetermine);
      expect(vDe(res).motif, MotifNonDetermination.arriveeNonDefinitive);
    });

    test('A1/7 SÉCURITÉ : le GAGNANT reste payé au bon dividende '
        '(aucune régression du gain)', () {
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6);
      final res = resoudrePrediction(
        prediction: pred('Simple Gagnant', <int>[9], mise: 10),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.attribue);
      // Simple Gagnant 9 publié à 7,50 € pour 1 € ⇒ 10 × 7,50 = 75,00 €.
      expect(vDe(res).total, closeTo(75.0, 0.001));
    });

    test('A1/8 Gagnant+Placé : les DEUX composantes restent indépendantes '
        '(gagnant payé, placé payé), mises réelles respectées', () {
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6);
      final res = resoudrePrediction(
        prediction: pred(
          'Gagnant+Placé',
          <int>[9],
          miseGagnant: 5,
          misePlace: 5,
        ),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.attribue);
      // 5 × 7,50 (gagnant) + 5 × 3,00 (placé) = 37,50 + 15,00 = 52,50 €.
      expect(vDe(res).gainGagnant, closeTo(37.5, 0.001));
      expect(vDe(res).gainPlace, closeTo(15.0, 0.001));
      expect(vDe(res).total, closeTo(52.5, 0.001));
    });

    test('A1/9 Gagnant+Placé dont aucune composante n\'est identifiable ⇒ '
        'indéterminé, JAMAIS perdu par défaut', () {
      // MESURE : `_resoudreGagnantPlace` ne conclut à `perdu` que si AU MOINS
      // une composante a été identifiée. Ici le cheval 12 n'a ni Simple Gagnant
      // ni Simple Placé : les DEUX identifications échouent, donc aucune des
      // deux composantes n'est démontrée perdante — le moteur rend
      // `nonDetermine(blocJusteAbsent)`, ce qui est l'état honnête.
      //
      // Ce test ÉPINGLE ce comportement : il ne doit pas devenir `perdu` sans
      // preuve, et l'anomalie 1 ne le change pas (Gagnant+Placé reste hors du
      // périmètre de la preuve par recoupement, qui exige un bloc à variante
      // unique).
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6);
      final res = resoudrePrediction(
        prediction: pred(
          'Gagnant+Placé',
          <int>[12],
          miseGagnant: 5,
          misePlace: 5,
        ),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.nonDetermine);
      expect(vDe(res).motif, MotifNonDetermination.blocJusteAbsent);
      expect(vDe(res).total, 0.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  ANOMALIE 3 — VARIANTE DÉCLARÉE PAR LE PARI, PAS PAR L'ARRIVÉE
  // ═════════════════════════════════════════════════════════════════════════
  group('A3 — Tiercé Désordre', () {
    test('A3/1 Tiercé Désordre dont la combinaison correspond à l\'arrivée '
        'DANS L\'ORDRE EXACT ⇒ payé au rapport DÉSORDRE publié', () {
      // Arrivée 9-4-15. Le ticket Désordre joue 9-4-15 : il est gagnant
      // Désordre. Avant correction, l'arrivée imposait « ordre » et le ticket
      // était déclaré blocJusteAbsent.
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6);
      final res = resoudrePrediction(
        prediction: pred('Tiercé Désordre', <int>[9, 4, 15], mise: 10),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.attribue);
      // e-Tiercé Désordre 9-4-15 publié à 80,30 € pour 1 € ⇒ 803,00 €.
      expect(vDe(res).total, closeTo(803.0, 0.001));
    });

    test('A3/2 Tiercé Désordre joué dans un ordre quelconque gagnant ⇒ '
        'toujours payé Désordre', () {
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6);
      final res = resoudrePrediction(
        prediction: pred('Tiercé Désordre', <int>[15, 9, 4], mise: 10),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.attribue);
      expect(vDe(res).total, closeTo(803.0, 0.001));
    });

    test('A3/3 SÉCURITÉ SYMÉTRIQUE : Tiercé ORDRE joué sur une combinaison '
        'dans un ordre différent ⇒ PERDU, jamais payé au dividende Désordre',
        () {
      // Avant correction, l'arrivée établissait « desordre » et le ticket
      // PERDANT recevait le rapport Désordre : un faux gain silencieux.
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6);
      final res = resoudrePrediction(
        prediction: pred('Tiercé Ordre', <int>[4, 9, 15], mise: 10),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.perdu);
      expect(vDe(res).total, 0.0);
    });

    test('A3/4 Tiercé Ordre joué dans l\'ordre exact ⇒ payé Ordre', () {
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6);
      final res = resoudrePrediction(
        prediction: pred('Tiercé Ordre', <int>[9, 4, 15], mise: 10),
        resultat: r,
      );

      expect(vDe(res).etat, EtatGain.attribue);
      // e-Tiercé Ordre 9-4-15 publié à 477,40 € ⇒ 4 774,00 €.
      expect(vDe(res).total, closeTo(4774.0, 0.001));
    });

    test('A3/5 NON-RÉGRESSION : un « Tiercé » sans mention d\'ordre continue '
        'd\'être payé selon l\'ARRIVÉE (comportement historique conservé)', () {
      // Arrivée dans l'ordre exact ⇒ variante ordre, dividende Ordre.
      final r = resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6);
      final exact = resoudrePrediction(
        prediction: pred('Tiercé', <int>[9, 4, 15], mise: 10),
        resultat: r,
      );
      expect(vDe(exact).etat, EtatGain.attribue);
      expect(vDe(exact).total, closeTo(4774.0, 0.001));

      // Même combinaison dans un autre ordre ⇒ variante desordre.
      final autre = resoudrePrediction(
        prediction: pred('Tiercé', <int>[15, 4, 9], mise: 10),
        resultat: r,
      );
      expect(vDe(autre).etat, EtatGain.attribue);
      expect(vDe(autre).total, closeTo(803.0, 0.001));
    });

    test('A3/6 SÉCURITÉ : ex æquo au rang comparé ⇒ indéterminé, jamais payé '
        'avec l\'Ordre ni avec une autre variante', () {
      // WOLVEGA [[4],[6],[1,5],[2]] : les rangs 1 et 2 sont des singletons,
      // MAIS le rang 3 est un ex æquo. Pour un Tiercé (taille 3), le rang 3
      // est l'un des rangs comparés ⇒ l'ordre relatif n'existe pas.
      //
      // MESURE : le motif rendu est `deadHeatSansGroupes`, PAS
      // `blocJusteAbsent` — la garde d'ex æquo intervient AVANT la recherche
      // du rapport. C'est le comportement correct et il est épinglé ici.
      const arrivee = <List<int>>[
        <int>[4], <int>[6], <int>[1, 5], <int>[2],
      ];
      final r = resultat(rapportsDe('R5C7_20112026.json'), groupes: arrivee);

      for (final type in <String>['Tiercé Désordre', 'Tiercé Ordre', 'Tiercé']) {
        final res = resoudrePrediction(
          prediction: pred(type, <int>[4, 6, 1], mise: 10),
          resultat: r,
        );
        expect(vDe(res).etat, EtatGain.nonDetermine, reason: type);
        expect(vDe(res).motif, MotifNonDetermination.deadHeatSansGroupes,
            reason: type);
        // Aucun montant d'une autre variante n'est substitué.
        expect(vDe(res).total, 0.0, reason: type);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  ANOMALIE 2 — LA TRANSITION VERS UN VERDICT DÉFINITIF
  // ═════════════════════════════════════════════════════════════════════════
  group('A2 — transition nonDetermine → définitif', () {
    test('A2/1 un ticket indéterminé faute de rapports reçoit son verdict '
        'définitif quand les rapports arrivent', () {
      // 1er passage : aucun rapport publié ⇒ indétermination persistée.
      final sansRapports = resoudrePrediction(
        prediction: pred('Simple Gagnant', <int>[9], mise: 10),
        resultat: resultat(const <RapportPmu>[], groupes: kArriveeR1C6),
      );
      expect(tDe(sansRapports).etatGain, EtatGain.nonDetermine);

      // 2e passage : les rapports officiels sont publiés ⇒ verdict définitif.
      final avecRapports = resoudrePrediction(
        prediction: tDe(sansRapports),
        resultat: resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6),
      );

      expect(vDe(avecRapports).etat, EtatGain.attribue);
      expect(eDe(avecRapports).estEnregistre, isTrue,
          reason: 'avant correction : refuseTransitionNonDeterminee');
      expect(tDe(avecRapports).etatGain, EtatGain.attribue);
      expect(vDe(avecRapports).total, closeTo(75.0, 0.001));
    });

    test('A2/2 la transition est IDEMPOTENTE : un second passage ne '
        'réécrit rien et n\'ajoute aucun gain', () {
      final passe1 = resoudrePrediction(
        prediction: pred('Simple Gagnant', <int>[9], mise: 10),
        resultat: resultat(const <RapportPmu>[], groupes: kArriveeR1C6),
      );
      final passe2 = resoudrePrediction(
        prediction: tDe(passe1),
        resultat: resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6),
      );
      final passe3 = resoudrePrediction(
        prediction: tDe(passe2),
        resultat: resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6),
      );

      expect(eDe(passe3).statut, StatutEnregistrementVerdict.dejaIdentique);
      expect(tDe(passe3).etatGain, EtatGain.attribue);
      // Pas de double gain : le total reste celui d'un seul règlement.
      expect(vDe(passe3).total, closeTo(75.0, 0.001));
    });

    test('A2/3 un verdict DÉFINITIF déjà validé n\'est JAMAIS écrasé', () {
      final initial = resoudrePrediction(
        prediction: pred('Simple Gagnant', <int>[9], mise: 10),
        resultat: resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6),
      );
      expect(tDe(initial).etatGain, EtatGain.attribue);

      // Les rapports changent : le verdict définitif doit tenir bon.
      final apres = resoudrePrediction(
        prediction: tDe(initial),
        resultat: resultat(
          rapportsDe('R5C7_20112026.json'),
          groupes: kArriveeR1C6,
        ),
      );

      expect(eDe(apres).statut,
          StatutEnregistrementVerdict.refuseVerdictDefinitifExistant);
      expect(tDe(apres).etatGain, EtatGain.attribue);
      expect(tDe(apres).rapportsAttribues, tDe(initial).rapportsAttribues);
    });

    test('A2/4 une indétermination dont les données ne démontrent RIEN reste '
        'indéterminée (aucune transition forcée)', () {
      final sansArrivee = resoudrePrediction(
        prediction: pred('Simple Gagnant', <int>[15], mise: 10),
        resultat: resultat(rapportsDe(kCaptureR1C6), groupes: null),
      );
      expect(tDe(sansArrivee).etatGain, EtatGain.nonDetermine);

      // Nouvelle actualisation, mais toujours sans arrivée officielle.
      final encore = resoudrePrediction(
        prediction: tDe(sansArrivee),
        resultat: resultat(rapportsDe(kCaptureR1C6), groupes: null),
      );
      expect(tDe(encore).etatGain, EtatGain.nonDetermine);
      expect(eDe(encore).statut, StatutEnregistrementVerdict.dejaIdentique);
    });

    test('A2/5 la transition ne fabrique pas de gain : un ticket indéterminé '
        'devenu PERDANT s\'enregistre comme perdu, sans montant', () {
      final sansArrivee = resoudrePrediction(
        prediction: pred('Simple Gagnant', <int>[15], mise: 10),
        resultat: resultat(rapportsDe(kCaptureR1C6), groupes: null),
      );
      expect(tDe(sansArrivee).etatGain, EtatGain.nonDetermine);

      final avecArrivee = resoudrePrediction(
        prediction: tDe(sansArrivee),
        resultat: resultat(rapportsDe(kCaptureR1C6), groupes: kArriveeR1C6),
      );

      expect(tDe(avecArrivee).etatGain, EtatGain.perdu);
      expect(vDe(avecArrivee).total, 0.0);
      expect(tDe(avecArrivee).rapportsAttribues, isNull);
    });
  });
}
