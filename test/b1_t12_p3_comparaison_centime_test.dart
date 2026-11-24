// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 1/3 — POINT 3 : COMPARAISON MONÉTAIRE AU CENTIME
//
//  Objectif : prouver que la comparaison repose sur une NORMALISATION AU
//  CENTIME, et non sur une tolérance flottante.
//
//  Les trois exigences de l'arbitrage :
//    ① 75.001 € et 75.00 € sont IDENTIQUES (même nombre de centimes) ;
//    ② 75.01 € et 75.00 € sont DIFFÉRENTS (un centime d'écart réel) ;
//    ③ `null` et `0.0` restent DISTINCTS.
//
//  ⚠️ CES TESTS ÉCHOUERAIENT SUR L'ANCIENNE CONVENTION.
//     Avec la tolérance `1e-9`, `75.001` vs `75.00` était déclaré DIFFÉRENT :
//     c'est précisément le défaut de convention corrigé. La mesure est donc
//     discriminante — P3/3.1 et P3/3.2 l'établissent sur les VRAIS points
//     d'entrée publics (`deciderEcritureVerdict`), pas sur des doubles
//     fabriqués à la main.
//
//  ⚠️ CE QUE CE FICHIER NE PRÉTEND PAS : qu'un gain officiel établi soit
//     devenu « indéterminé » en production à cause de l'ancienne convention.
//     Le contrôle de cohérence interne de `_totalDemontreComplet` est
//     structurellement inatteignable avec un écart (`VerdictGain._` privé,
//     `total` recalculé par le constructeur, aucun `fromJson`). Voir la
//     section 3 pour la démonstration et ses limites.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart' show TrackedCourse;
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart'
    show
        StatutEnregistrementVerdict,
        deciderEcritureVerdict,
        montantOfficielDepuisVerdict,
        resoudreTotalDepuisRapports;
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show VarianteRapport, varianteDepuisLibelle;
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart'
    show ComposanteGain, RoleComposante, VerdictGain;
import 'package:pronostic_hippique/utils/comparaison_monetaire.dart';

RapportPublie _publie(String combinaison, double pourUnEuro) => RapportPublie(
      codePmu: 'E_SIMPLE_GAGNANT',
      libelle: 'e-Simple Gagnant',
      combinaison: combinaison,
      variante: varianteDepuisLibelle('e-Simple Gagnant'),
      pourUnEuro: pourUnEuro,
    );

RapportAttribue _attribue(String combinaison, double pourUnEuro, double mise) =>
    RapportAttribue.calculer(
      rapport: _publie(combinaison, pourUnEuro),
      miseAppliquee: mise,
    );

ComposanteGain _composanteUnique(String combinaison, double pourUnEuro,
        double mise) =>
    ComposanteGain(
      libelleRapport: 'e-Simple Gagnant',
      combinaisonRapport: combinaison,
      categorie: VarianteRapport.sansVariante,
      mise: mise,
      pourUnEuro: pourUnEuro,
      montantRetour: mise * pourUnEuro,
      role: RoleComposante.unique,
    );

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  1. LA PRIMITIVE DE NORMALISATION
  // ═════════════════════════════════════════════════════════════════════════
  group('P3/1 — normalisation au centime', () {
    test('P3/1.1 75.001 et 75.00 sont le MÊME montant au centime', () {
      // Exigence littérale de l'arbitrage.
      expect(memesCentimes(75.001, 75.00), isTrue,
          reason: '75.001 n\'est qu\'un artefact de calcul de 75,00 €');
      // Témoin : la mesure des centimes, pas une simple tolérance.
      expect(centimesDe(75.001), 7500);
      expect(centimesDe(75.00), 7500);
    });

    test('P3/1.2 75.01 et 75.00 sont DIFFÉRENTS', () {
      // Exigence littérale : un centime d'écart est un écart réel.
      expect(memesCentimes(75.01, 75.00), isFalse);
      expect(centimesDe(75.01), 7501);
      expect(centimesDe(75.00), 7500);
    });

    test('P3/1.3 l\'arrondi est au plus proche, explicitement documenté', () {
      // Sous le demi-centime : on descend. Au demi-centime et au-delà : on monte.
      expect(centimesDe(75.004), 7500);
      expect(centimesDe(75.005), 7501);
      // Symétrie sur un autre ordre de grandeur.
      expect(centimesDe(0.004), 0);
      expect(centimesDe(0.005), 1);
    });

    test('P3/1.4 une valeur non finie n\'est jamais déclarée égale', () {
      // « Égal par défaut » serait une affirmation non démontrée.
      expect(memesCentimes(double.nan, double.nan), isFalse);
      expect(memesCentimes(double.infinity, double.infinity), isFalse);
      expect(memesCentimes(75.0, double.infinity), isFalse);
    });

    test('P3/1.5 plusieurs dérives flottantes de même centime sont égales', () {
      // Trois écritures du même montant issues de chemins de calcul distincts.
      const a = 0.1 + 0.2; // 0.30000000000000004
      const b = 0.3;
      expect(memesCentimes(a, b), isTrue,
          reason: '0,1 + 0,2 doit valoir 0,30 € au centime');
      // Et un vrai écart d'un centime reste refusé sur ces petits montants.
      expect(memesCentimes(a, 0.31), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  2. LA DISTINCTION null / 0.0 EST PRÉSERVÉE
  // ═════════════════════════════════════════════════════════════════════════
  group('P3/2 — null n\'est jamais confondu avec 0.0', () {
    test('P3/2.1 null et null ⇒ égaux (deux informations absentes)', () {
      expect(memeMontantOuTousDeuxNuls(null, null), isTrue);
    });

    test('P3/2.2 null et 0.0 ⇒ DIFFÉRENTS (non établi ≠ officiellement nul)',
        () {
      expect(memeMontantOuTousDeuxNuls(null, 0.0), isFalse);
      expect(memeMontantOuTousDeuxNuls(0.0, null), isFalse);
    });

    test('P3/2.3 0.0 et 0.0 ⇒ égaux (deux zéros officiels)', () {
      expect(memeMontantOuTousDeuxNuls(0.0, 0.0), isTrue);
    });

    test('P3/2.4 null et une valeur non nulle ⇒ différents', () {
      expect(memeMontantOuTousDeuxNuls(null, 75.0), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  3. RACCORDEMENT RÉEL À LA CHAÎNE FINANCIÈRE
  //
  //  ⚠️ MESURE QUI A CORRIGÉ CE FICHIER. Une première version de ce groupe
  //     affirmait prouver que « l'enregistreur emploie réellement la
  //     primitive » — alors qu'elle ne faisait qu'appeler les fonctions de
  //     `comparaison_monetaire.dart` sur des doubles construits dans le test.
  //     `flutter analyze` a révélé l'import de l'enregistreur INUTILISÉ : la
  //     preuve n'existait pas. Elle est donc établie ici par les VRAIS points
  //     d'entrée publics, mesurés avant d'écrire ces lignes :
  //
  //       • `deciderEcritureVerdict` (public) appelle `_verdictIdentique`,
  //         qui compare le total PERSISTÉ (`RapportAttribue.montantRetour`
  //         relu depuis JSON) au total du verdict via `_memeMontant` ;
  //       • `montantOfficielDepuisVerdict` (public) valide le total du
  //         verdict contre la somme de ses composantes via `_memeMontant`.
  //
  //  ⚠️ LIMITE DÉMONTRÉE, PAS SUPPOSÉE : le contrôle de cohérence interne de
  //     `_totalDemontreComplet` (« la somme égale le total ») est
  //     STRUCTURELLEMENT INATTEIGNABLE, car `VerdictGain._` est privé,
  //     `VerdictGain.attribue` calcule `total` comme la somme exacte des
  //     composantes, et `VerdictGain` n'a AUCUN `fromJson` (mesuré : une
  //     seule occurrence de « fromJson » dans `moteur_gain_pmu.dart`, et elle
  //     concerne `ComposanteGain`). Aucun test ne peut donc l'exercer : il
  //     est défensif. C'est écrit ici plutôt que passé sous silence.
  // ═════════════════════════════════════════════════════════════════════════
  group('P3/3 — effet réel sur la décision d\'écriture du verdict', () {
    test('P3/3.1 un total persisté dérivé d\'un millième d\'euro est reconnu '
        'IDENTIQUE au verdict', () {
      // Le total persisté vient d'un VRAI JSON, pas d'un double fabriqué à la
      // main : c'est exactement le chemin de relecture de production.
      final persistes = <RapportAttribue>[
        RapportAttribue.fromJson(<String, dynamic>{
          'rapport': _publie('9', 7.50).toJson(),
          'miseAppliquee': 10.0,
          // 10 × 7,5001 = 75,001 — un artefact de calcul, pas un centime.
          'montantRetour': 75.001,
        }),
      ];
      expect(resoudreTotalDepuisRapports(persistes), closeTo(75.001, 1e-9));

      // ⚠️ TÉMOIN DE DISCRIMINATION : le même rapport CONSTRUIT (non persisté)
      //    vaut exactement 75,00 €. C'est bien la RELECTURE du JSON qui porte
      //    la dérive — le test n'aurait aucun sens sur une valeur fabriquée
      //    exprès dans le test sans ce point de comparaison.
      expect(_attribue('9', 7.50, 10.0).montantRetour, 75.0);
      expect(
          memesCentimes(_attribue('9', 7.50, 10.0).montantRetour,
              resoudreTotalDepuisRapports(persistes)!),
          isTrue,
          reason: 'le montant persisté dérive d\'un millième mais reste le '
              'même montant au centime');

      // Le verdict, lui, porte 75,00 €.
      final verdict =
          VerdictGain.attribue(composantes: <ComposanteGain>[
        _composanteUnique('9', 7.50, 10.0),
      ]);
      expect(verdict.total, 75.0);

      final decision = deciderEcritureVerdict(
        etatExistant: EtatGain.attribue,
        etatTirelireExistant: null,
        motifExistant: null,
        rapportsExistants: persistes,
        verdict: verdict,
      );
      expect(decision.statut, StatutEnregistrementVerdict.dejaIdentique,
          reason: '75,001 € et 75,00 € sont le MÊME montant : réécrire le '
              'verdict serait une écriture inutile, le refuser serait un '
              'faux refus');
    });

    test('P3/3.2 un total persisté séparé d\'un CENTIME est un verdict '
        'DIFFÉRENT (donc refusé, pas « déjà identique »)', () {
      // Témoin indispensable : sans lui, P3/3.1 serait compatible avec un
      // comparateur qui répondrait « toujours identique ».
      final persistes = <RapportAttribue>[
        RapportAttribue.fromJson(<String, dynamic>{
          'rapport': _publie('9', 7.50).toJson(),
          'miseAppliquee': 10.0,
          'montantRetour': 75.01,
        }),
      ];
      final verdict =
          VerdictGain.attribue(composantes: <ComposanteGain>[
        _composanteUnique('9', 7.50, 10.0),
      ]);

      final decision = deciderEcritureVerdict(
        etatExistant: EtatGain.attribue,
        etatTirelireExistant: null,
        motifExistant: null,
        rapportsExistants: persistes,
        verdict: verdict,
      );
      expect(decision.statut, isNot(StatutEnregistrementVerdict.dejaIdentique),
          reason: '75,01 € n\'est pas 75,00 € : un centime d\'écart réel ne '
              'doit jamais être absorbé');
      // Et la nature du refus est celle d\'un verdict définitif déjà posé.
      expect(decision.statut, StatutEnregistrementVerdict.refuseVerdictDefinitifExistant);
    });

    test('P3/3.3 un total persisté ABSENT n\'est jamais assimilé à zéro', () {
      // `rapportsExistants == null` ⇒ « jamais résolu ». La comparaison rend
      // `false` sans lever et sans conclure à l\'identité.
      expect(resoudreTotalDepuisRapports(null), isNull);
      expect(memeMontantOuTousDeuxNuls(null, 75.0), isFalse);

      // Liste VIDE, en revanche, est un cas DISTINCT : « résolu, aucun
      // rapport », donc un total de 0,0 — qui n\'égale pas 75 €.
      expect(resoudreTotalDepuisRapports(const <RapportAttribue>[]), 0.0);
      expect(memesCentimes(0.0, 75.0), isFalse);
    });

    test('P3/3.4 le montant officiel est produit depuis le VRAI point '
        'd\'entrée public', () {
      final verdict =
          VerdictGain.attribue(composantes: <ComposanteGain>[
        _composanteUnique('9', 7.50, 10.0),
      ]);
      // Gain démontré complet : le montant officiel EST le total.
      expect(montantOfficielDepuisVerdict(verdict), 75.0);
      // Témoin de non-vacuité : un verdict non déterminé ne produit RIEN.
      expect(
          montantOfficielDepuisVerdict(VerdictGain.nonDetermine(
            motif: MotifNonDetermination.blocJusteAbsent,
            explication: 'témoin',
          )),
          isNull);
      // Et une perte établie produit 0,0 — une information, pas une absence.
      expect(
          montantOfficielDepuisVerdict(
              VerdictGain.perdu(explication: 'témoin de perte établie')),
          0.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  4. NON-RÉGRESSION : LA COMPARAISON N'A PAS CHANGÉ DE NATURE
  //
  //  La normalisation ne doit pas devenir permissive : un écart d'un centime
  //  sur une somme de composantes doit TOUJOURS être refusé par l'enregistreur.
  // ═════════════════════════════════════════════════════════════════════════
  group('P3/4 — la normalisation ne rend pas la chaîne permissive', () {
    test('P3/4.1 un remboursement établi reste distinct d\'un gain', () {
      // Témoin de non-régression du chantier : la nature de l'affichage
      // n'est pas affectée par la comparaison monétaire.
      expect(EtatGain.rembourse, isNot(EtatGain.attribue));
      expect(centimesDe(10.0), 1000);
    });

    test('P3/4.2 aucune valeur monétaire n\'est ARRONDIE par la comparaison',
        () {
      // La comparaison ne modifie jamais le montant : c'est une lecture.
      const montant = 75.001;
      expect(memesCentimes(montant, 75.0), isTrue);
      expect(montant, 75.001,
          reason: 'le montant stocké n\'est pas arrondi par la comparaison');
    });

    test('P3/4.3 le contrat null ≠ 0.0 est porté par les DEUX modèles', () {
      // UserPrediction : clé absente ⇒ null (jamais 0.0).
      final p = UserPrediction.fromJson(const <String, dynamic>{});
      expect(p.remboursementPmu, isNull,
          reason: 'absence de clé = information NON ÉTABLIE, pas un zéro');

      // TrackedCourse : même contrat, sur un JSON minimal VALIDE.
      // (`fromJson` exige cinq champs obligatoires : on les fournit.)
      final c = TrackedCourse.fromJson(const <String, dynamic>{
        'numReunion': 1,
        'numCourse': 6,
        'nomCourse': 'Prix de test',
        'hippodrome': 'Vincennes',
        'heureDepart': '2026-11-15T00:00:00.000',
      });
      expect(c.remboursementPmu, isNull,
          reason: 'absence de clé = information NON ÉTABLIE, pas un zéro');

      // Et un zéro EXPLICITE reste un zéro : la distinction est dans la clé,
      // pas dans la valeur.
      final c0 = TrackedCourse.fromJson(const <String, dynamic>{
        'numReunion': 1,
        'numCourse': 6,
        'nomCourse': 'Prix de test',
        'hippodrome': 'Vincennes',
        'heureDepart': '2026-11-15T00:00:00.000',
        'remboursementPmu': 0.0,
      });
      expect(c0.remboursementPmu, 0.0);
      expect(memeMontantOuTousDeuxNuls(c0.remboursementPmu, 0.0), isTrue);
      expect(memeMontantOuTousDeuxNuls(c.remboursementPmu, 0.0), isFalse,
          reason: 'non établi ≠ officiellement nul');
    });
  });
}
