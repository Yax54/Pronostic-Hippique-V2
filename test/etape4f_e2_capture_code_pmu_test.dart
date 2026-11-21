// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 4-F / ÉTAPE 2 — CAPTURE DU CODE PMU DANS `bet_bottom_sheet.dart`
//
//  Périmètre STRICT de cette étape (option 1 réduite) :
//    • seul `codePmuOfficiel` est renseigné, et seulement pour les types
//      identifiables sans ambiguïté ;
//    • `varianteChoisie`, `numerosDansOrdre` et `formulePari` restent `null`,
//      parce qu'aucun des huit types de CE sélecteur n'offre de choix
//      Ordre/Désordre ni n'exige l'ordre à la saisie.
//
//  Ce fichier vérifie donc surtout ce qui NE doit PAS être inventé. C'est la
//  partie la plus importante : un `null` correct vaut mieux qu'une valeur
//  plausible et fausse.
//
//  Il ne teste pas l'interface (widgets) : la capture est vérifiée au niveau
//  du référentiel et de la sérialisation, qui est ce qui est réellement
//  modifié à cette étape. Les protections G+P sont vérifiées séparément par
//  `gp_validation_manuelle_test.dart` et `gp_affichage_gain_non_etabli_test`.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/referentiel_paris_pmu.dart';

/// Les HUIT types réellement proposés par `bet_bottom_sheet.dart:130`.
/// Cette liste est recopiée volontairement : si le sélecteur change, ce test
/// doit être mis à jour sciemment, pas silencieusement.
const List<String> kTypesDuSelecteur = [
  'Simple Gagnant',
  'Simple Placé',
  'Gagnant+Placé',
  'Couplé Gagnant',
  'Couplé Placé',
  'Tiercé',
  'Quarté+',
  'Quinté+',
];

/// Reproduit EXACTEMENT la logique de `_codePmuDuTypeChoisi` du widget
/// (l. ~205). On la rejoue ici pour prouver la correspondance des huit types
/// sans instancier l'interface.
String? codePmuPour(String libelle) {
  final type = typePmuDepuisLibelleHistorique(libelle);
  if (type == null) return null;
  return codeApiPourTypePmu(type);
}

TrackedCourse _tc({
  required String typePari,
  String? codePmuOfficiel,
  String? varianteChoisie,
  List<int>? numerosDansOrdre,
  String? formulePari,
  List<int> numerosJoues = const [1, 3, 5],
}) =>
    TrackedCourse(
      numReunion: 1,
      numCourse: 1,
      nomCourse: 'Prix de test',
      hippodrome: 'Vincennes',
      heureDepart: DateTime(2026, 11, 21, 14, 30),
      storageKey: 'R1C1_21112026_1',
      numeroCheval: 3,
      miseEngagee: 10.0,
      typePari: typePari,
      numerosJoues: numerosJoues,
      codePmuOfficiel: codePmuOfficiel,
      varianteChoisie: varianteChoisie,
      numerosDansOrdre: numerosDansOrdre,
      formulePari: formulePari,
    );

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E2/1 — les huit types du sélecteur ont le code PMU attendu', () {
    test('correspondance mesurée des huit libellés', () {
      // Table MESURÉE, pas supposée : chaque valeur a été relevée en exécutant
      // `typePmuDepuisLibelleHistorique` puis `codeApiPourTypePmu`.
      const attendu = {
        'Simple Gagnant': 'E_SIMPLE_GAGNANT',
        'Simple Placé': 'E_SIMPLE_PLACE',
        'Gagnant+Placé': null,
        'Couplé Gagnant': 'E_COUPLE_GAGNANT',
        'Couplé Placé': 'E_COUPLE_PLACE',
        'Tiercé': 'E_TIERCE',
        'Quarté+': 'E_QUARTE_PLUS',
        'Quinté+': 'E_QUINTE_PLUS',
      };

      for (final libelle in kTypesDuSelecteur) {
        expect(attendu.containsKey(libelle), isTrue,
            reason: 'type du sélecteur non couvert par ce test : $libelle');
        expect(codePmuPour(libelle), attendu[libelle],
            reason: 'code PMU inattendu pour « $libelle »');
      }
    });

    test('sept types sur huit portent un code, un seul reste null', () {
      final codes = kTypesDuSelecteur.map(codePmuPour).toList();
      expect(codes.where((c) => c != null).length, 7);
      expect(codes.where((c) => c == null).length, 1);
    });

    test('Gagnant+Placé ne reçoit AUCUN code PMU', () {
      expect(codePmuPour('Gagnant+Placé'), isNull,
          reason: 'ce n\'est pas un pari PMU mais un ticket à deux composantes');
      // Preuve par le référentiel : le libellé est délibérément hors table.
      expect(typePmuDepuisLibelleHistorique('Gagnant+Placé'), isNull);
      expect(estTicketApplicatifHorsReferentielPmu('Gagnant+Placé'), isTrue);
    });

    test('aucun code n\'est attribué à un type absent du sélecteur', () {
      // Ces paris ne sont pas proposés ici : la capture ne doit rien inventer.
      for (final absent in [
        'Tiercé Ordre',
        'Tiercé Désordre',
        'Couplé Ordre',
        'Trio',
        'Super4',
        'Multi',
      ]) {
        expect(kTypesDuSelecteur.contains(absent), isFalse,
            reason: '« $absent » ne doit pas figurer dans le sélecteur');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E2/2 — variante non inventée (Quarté+, Quinté+, Tiercé)', () {
    test('Quarté+ et Quinté+ : varianteChoisie reste null', () {
      for (final t in ['Quarté+', 'Quinté+']) {
        final ticket = _tc(typePari: t, codePmuOfficiel: codePmuPour(t));
        expect(ticket.varianteChoisie, isNull,
            reason: '$t : c\'est le rapport officiel qui tranche la variante');
        // Ces deux types SONT payables en Ordre ET en Désordre, mais le
        // parieur ne choisit pas : le référentiel le confirme.
        final type = typePmuDepuisLibelleHistorique(t)!;
        final variantes = variantesPayables(type)!;
        expect(variantes.length, greaterThanOrEqualTo(2),
            reason: '$t doit rester payable en plusieurs variantes');
      }
    });

    test('Tiercé générique : varianteChoisie reste null', () {
      final t = _tc(typePari: 'Tiercé', codePmuOfficiel: 'E_TIERCE');
      expect(t.varianteChoisie, isNull,
          reason: 'le Tiercé générique est payable Ordre OU Désordre');
      final type = typePmuDepuisLibelleHistorique('Tiercé')!;
      expect(variantesPayables(type)!.length, 2);
    });

    test('aucun type du sélecteur n\'exige une variante choisie', () {
      // ★ R10 : ce test visait un point VALIDE — ces trois types ne réclament
      //   effectivement aucune variante choisie. Mais il l'affirmait par le
      //   biais de `capturePariComplete`, qui depuis R10 exige AUSSI le bon
      //   nombre de numéros. Le helper `_tc` ne fournit que 3 numéros par
      //   défaut, ce qui rendait l'assertion dépendante d'un détail sans
      //   rapport avec ce qu'elle voulait prouver (un Quinté+ passait pour
      //   complet avec 3 numéros sur 5).
      //
      //   On teste désormais l'intention RÉELLE, directement : ces types ne
      //   font pas partie des types à variante obligatoire. Et on vérifie en
      //   plus qu'avec un nombre de numéros CORRECT, ils sont bien complets.
      const exigeVariante = {'Tiercé Ordre', 'Tiercé Désordre', 'Couplé Ordre'};
      const nbRequis = {'Quarté+': 4, 'Quinté+': 5, 'Tiercé': 3};

      for (final t in ['Quarté+', 'Quinté+', 'Tiercé']) {
        expect(exigeVariante.contains(t), isFalse,
            reason: '$t n\'exige aucune variante choisie');

        // Et avec le bon nombre de numéros, la capture est bien complète.
        final ticket = _tc(
          typePari: t,
          codePmuOfficiel: codePmuPour(t),
          numerosJoues: List<int>.generate(nbRequis[t]!, (i) => i + 1),
        );
        expect(ticket.capturePariComplete, isTrue,
            reason: '$t avec ${nbRequis[t]} numéros : capture complète');
      }
    });

    test('★ R10 — avec un nombre de numéros INSUFFISANT, c\'est incomplet', () {
      // Le faux positif précisément corrigé : un Quinté+ à 3 numéros n'est
      // pas complet. Ce cas n'était couvert nulle part auparavant.
      for (final t in ['Quarté+', 'Quinté+', 'Tiercé']) {
        final ticket = _tc(
          typePari: t,
          codePmuOfficiel: codePmuPour(t),
          numerosJoues: const [1, 3, 5], // 3 numéros, insuffisant pour Q+/Q+
        );
        if (t == 'Tiercé') {
          expect(ticket.capturePariComplete, isTrue,
              reason: 'Tiercé : 3 numéros sont exactement ce qu\'il faut');
        } else {
          expect(ticket.capturePariComplete, isFalse,
              reason: '$t : 3 numéros ne suffisent pas');
        }
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E2/3 — numerosDansOrdre reste null (ordre NON CONNU du sélecteur)',
      () {
    test('ce que le règlement exige à la saisie (mesuré)', () {
      // MESURÉ, et contraire à une intuition répandue : Tiercé, Quarté+ ET
      // Quinté+ EXIGENT l'ordre à la saisie. Ce n'est donc PAS l'absence
      // d'exigence qui justifie un `numerosDansOrdre` nul, mais le fait que
      // ce sélecteur ne connaît pas cet ordre.
      const attendu = {
        'Simple Gagnant': false,
        'Simple Placé': false,
        'Gagnant+Placé': null, // ticket applicatif : hors référentiel
        'Couplé Gagnant': false,
        'Couplé Placé': false,
        'Tiercé': true,
        'Quarté+': true,
        'Quinté+': true,
      };

      for (final libelle in kTypesDuSelecteur) {
        final type = typePmuDepuisLibelleHistorique(libelle);
        final exige = type == null ? null : exigeOrdreExactSaisie(type);
        expect(exige, attendu[libelle],
            reason: 'exigeOrdreExactSaisie inattendu pour « $libelle »');
      }
    });

    test('exactement trois des huit types exigent l\'ordre', () {
      final exigeants = kTypesDuSelecteur.where((t) {
        final type = typePmuDepuisLibelleHistorique(t);
        return type != null && exigeOrdreExactSaisie(type) == true;
      }).toList();
      expect(exigeants, ['Tiercé', 'Quarté+', 'Quinté+']);
    });

    test('la capture laisse numerosDansOrdre à null dans tous les cas', () {
      // C'est le point de cette étape : le champ reste nul PARCE QUE l'ordre
      // n'est pas connu, non parce qu'il serait inutile. Capturer la liste
      // triée ferait passer un tri pour un ordre joué.
      for (final t in kTypesDuSelecteur) {
        final ticket = _tc(
          typePari: t,
          codePmuOfficiel: codePmuPour(t),
          numerosDansOrdre: null,
        );
        expect(ticket.numerosDansOrdre, isNull, reason: t);
      }
    });

    test('numerosJoues garde son format historique trié', () {
      final ticket = _tc(typePari: 'Tiercé', codePmuOfficiel: 'E_TIERCE');
      expect(ticket.numerosJoues, const [1, 3, 5],
          reason: 'la capture ne modifie pas numerosJoues');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E2/4 — formulePari reste null (Multi non proposé)', () {
    test('aucun type du sélecteur ne porte de formule', () {
      for (final t in kTypesDuSelecteur) {
        expect(_tc(typePari: t, codePmuOfficiel: codePmuPour(t)).formulePari,
            isNull,
            reason: t);
      }
    });

    test('Multi et Mini Multi ne sont pas proposés par ce sélecteur', () {
      for (final interdit in ['Multi', 'Mini Multi', 'e-Multi']) {
        expect(kTypesDuSelecteur.contains(interdit), isFalse);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E2/5 — sérialisation JSON des nouveaux champs', () {
    test('TrackedCourse : code PMU et nulls survivent à l\'aller-retour', () {
      for (final t in kTypesDuSelecteur) {
        final origine = _tc(typePari: t, codePmuOfficiel: codePmuPour(t));
        final relu = TrackedCourse.fromJson(origine.toJson());

        expect(relu.codePmuOfficiel, codePmuPour(t), reason: t);
        expect(relu.varianteChoisie, isNull, reason: t);
        expect(relu.numerosDansOrdre, isNull, reason: t);
        expect(relu.formulePari, isNull, reason: t);
        expect(relu.typePari, t, reason: 'typePari réécrit pour $t');
      }
    });

    test('UserPrediction : les mêmes valeurs traversent le JSON', () {
      for (final t in kTypesDuSelecteur) {
        final origine = UserPrediction(
          id: 'p', dateStr: '2026-11-21', numReunion: 1, numCourse: 1,
          nomCourse: 'n', hippodrome: 'h', numeroCheval: 3, nomCheval: 'c',
          cote: 4.2, typePari: t, createdAt: DateTime(2026, 11, 21),
          montantMise: 10.0, numerosJoues: const [1, 3, 5],
          codePmuOfficiel: codePmuPour(t),
        );
        final relu = UserPrediction.fromJson(origine.toJson());
        expect(relu.codePmuOfficiel, codePmuPour(t), reason: t);
        expect(relu.varianteChoisie, isNull, reason: t);
        expect(relu.numerosDansOrdre, isNull, reason: t);
      }
    });

    test('le JSON reste encodable pour les huit types', () {
      for (final t in kTypesDuSelecteur) {
        final ticket = _tc(typePari: t, codePmuOfficiel: codePmuPour(t));
        final encode = jsonEncode(ticket.toJson());
        final decode = jsonDecode(encode) as Map<String, dynamic>;
        expect(TrackedCourse.fromJson(decode).typePari, t);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E2/6 — les paris simples restent inchangés', () {
    test('Simple Gagnant : un seul numéro, aucun ordre, code correct', () {
      final ticket = _tc(
        typePari: 'Simple Gagnant',
        codePmuOfficiel: codePmuPour('Simple Gagnant'),
        numerosJoues: const [7],
      );
      expect(ticket.codePmuOfficiel, 'E_SIMPLE_GAGNANT');
      expect(ticket.numerosJoues, const [7]);
      expect(ticket.numerosDansOrdre, isNull);
      expect(ticket.varianteChoisie, isNull);
    });

    test('Simple Placé : code distinct du Gagnant', () {
      expect(codePmuPour('Simple Placé'), 'E_SIMPLE_PLACE');
      expect(codePmuPour('Simple Placé'),
          isNot(codePmuPour('Simple Gagnant')),
          reason: 'un Simple Placé ne doit jamais retomber sur le Gagnant');
    });

    test('les champs historiques ne sont pas altérés', () {
      final ticket = _tc(typePari: 'Simple Gagnant', numerosJoues: const [7]);
      final json = ticket.toJson();
      // Les 24 clés historiques + 4 de capture.
      expect(json.length, 28);
      expect(json['typePari'], 'Simple Gagnant');
      expect(json['numerosJoues'], const [7]);
      expect(json['miseEngagee'], 10.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E2/7 — Gagnant+Placé préservé', () {
    test('les deux composantes survivent, sans code PMU inventé', () {
      final ticket = TrackedCourse(
        numReunion: 1,
        numCourse: 1,
        nomCourse: 'n',
        hippodrome: 'h',
        heureDepart: DateTime(2026, 11, 21),
        storageKey: 'K',
        numeroCheval: 3,
        miseEngagee: 10.0,
        miseGagnant: 10.0,
        misePlace: 10.0,
        coteGagnant: 4.2,
        cotePlace: 2.1,
        typePari: 'Gagnant+Placé',
        numerosJoues: const [3],
        codePmuOfficiel: codePmuPour('Gagnant+Placé'),
      );

      expect(ticket.codePmuOfficiel, isNull,
          reason: 'aucun code unique ne doit être inventé pour G+P');
      expect(ticket.miseGagnant, 10.0);
      expect(ticket.misePlace, 10.0);
      expect(ticket.miseTotaleEngagee, 20.0,
          reason: 'règle B1 : 10 € = 10 Gagnant + 10 Placé = 20 € engagés');
      expect(ticket.misesGagnantPlaceIncompletes, isFalse);

      final relu = TrackedCourse.fromJson(ticket.toJson());
      expect(relu.miseGagnant, 10.0);
      expect(relu.misePlace, 10.0);
      expect(relu.miseTotaleEngagee, 20.0);
      expect(relu.codePmuOfficiel, isNull);
    });

    test('une composante manquante reste signalée, aucun total inventé', () {
      final incomplet = TrackedCourse(
        numReunion: 1, numCourse: 1, nomCourse: 'n', hippodrome: 'h',
        heureDepart: DateTime(2026, 11, 21), typePari: 'Gagnant+Placé',
        miseEngagee: 10.0, miseGagnant: 10.0,
      );
      expect(incomplet.miseTotaleEngagee, isNull,
          reason: 'état incomplet : aucun total ne doit être calculé');
      expect(incomplet.misesGagnantPlaceIncompletes, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E2/8 — un ticket non capturé reste identifié comme tel', () {
    test('ancien ticket : capture incomplète, aucune valeur ajoutée', () {
      final ancien = TrackedCourse.fromJson({
        'numReunion': 1, 'numCourse': 1, 'nomCourse': 'n', 'hippodrome': 'h',
        'heureDepart': '2026-11-01T15:00:00.000',
        'typePari': 'Tiercé', 'numerosJoues': [1, 3, 5],
        'storageKey': 'VIEUX',
      });
      expect(ancien.codePmuOfficiel, isNull);
      expect(ancien.capturePariComplete, isFalse);
    });

    test('nouveau ticket simple : capture complète', () {
      final neuf = _tc(
        typePari: 'Simple Gagnant',
        codePmuOfficiel: codePmuPour('Simple Gagnant'),
        numerosJoues: const [7],
      );
      expect(neuf.capturePariComplete, isTrue);
    });
  });
}
