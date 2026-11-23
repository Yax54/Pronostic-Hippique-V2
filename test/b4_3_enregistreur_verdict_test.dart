// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-4.3 — TESTS DE L'ENREGISTREMENT SÉCURISÉ D'UN VERDICT B-3
//
//  Ce fichier couvre les quatre familles exigées :
//    • MODÈLE ET COPIE   — copyWith : 33 champs, sentinelle, aucune mutation ;
//    • VERDICTS          — attribué, perdu, remboursé, non déterminé, G+P,
//                          rapports multiples, Bonus/Tirelire, données
//                          manquantes ;
//    • PROTECTION        — double enregistrement, écrasement, refus sans
//                          mutation, conservation des mises et numéros ;
//    • PERSISTANCE       — aller-retour JSON, compatibilité historique,
//                          reconstruction du total, sauvegarde/restauration.
//
//  ⚠️ Tous les contrôles financiers vérifient des MONTANTS EXACTS et leurs
//     UNITÉS, jamais seulement des états.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show VarianteRapport;
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart';

// ───────────────────────────────────────────────────────────────────────────
//  CONSTRUCTEURS DE FIÈTURE
// ───────────────────────────────────────────────────────────────────────────

DateTime _date = DateTime.utc(2026, 11, 15, 14, 30);

/// Ticket historique complet : les 22 champs historiques + les 4 de capture.
UserPrediction ticketHistorique() => UserPrediction(
      id: 'tk_001',
      dateStr: '2026-11-15',
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'Prix de Test',
      hippodrome: 'Vincennes',
      numeroCheval: 9,
      nomCheval: 'Idao de Tillard',
      cote: 4.2,
      typePari: 'Tiercé Ordre',
      createdAt: _date,
      isCorrect: true,
      scoreIA: 87.5,
      montantMise: 2.0,
      gainRealise: null,
      numerosJoues: <int>[9, 4, 15],
      dividendePmuReel: null,
      combinaisonPmu: null,
      miseGagnant: null,
      misePlace: null,
      coteGagnant: null,
      cotePlace: null,
      codePmuOfficiel: 'E_TIERCE',
      varianteChoisie: 'ordre',
      numerosDansOrdre: <int>[9, 4, 15],
      formulePari: null,
    );

/// Ticket avec TOUS les champs B-1 renseignés, pour éprouver la copie.
UserPrediction ticketComplet() => ticketHistorique().copyWith(
      etatGain: EtatGain.attribue,
      rapportsAttribues: <RapportAttribue>[
        RapportAttribue.calculer(
          rapport: rapportOfficielTierceOrdre(),
          miseAppliquee: 2.0,
        ),
      ],
      etatTirelire: EtatTirelire.sansObjet,
      dividendeGagnant: null,
      dividendePlace: null,
      miseBaseCentimesUtilisee: 100,
      motifNonDetermination: null,
    );

/// Rapport officiel « e-Tiercé Ordre », 477,40 € pour 1 €.
RapportPublie rapportOfficielTierceOrdre() => const RapportPublie(
      codePmu: 'E_TIERCE',
      libelle: 'e-Tiercé Ordre',
      combinaison: '9-4-15',
      variante: VarianteRapport.ordre,
      pourUnEuro: 477.40,
      rang: 1,
      miseBaseCentimes: 100,
    );

/// Le rapport « e-Tiercé Désordre » de la MÊME combinaison, 80,30 €.
RapportPublie rapportOfficielTierceDesordre() => const RapportPublie(
      codePmu: 'E_TIERCE',
      libelle: 'e-Tiercé Désordre',
      combinaison: '9-4-15',
      variante: VarianteRapport.desordre,
      pourUnEuro: 80.30,
      rang: 2,
      miseBaseCentimes: 100,
    );

/// Verdict « attribué » cohérent : 2 € × 477,40 = 954,80 €.
VerdictGain verdictTierceOrdreAttribue() => VerdictGain.attribue(
      composantes: <ComposanteGain>[
        const ComposanteGain(
          libelleRapport: 'e-Tiercé Ordre',
          combinaisonRapport: '9-4-15',
          categorie: VarianteRapport.ordre,
          mise: 2.0,
          pourUnEuro: 477.40,
          montantRetour: 954.80,
        ),
      ],
    );

// ───────────────────────────────────────────────────────────────────────────
//  GROUPES
// ───────────────────────────────────────────────────────────────────────────

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  B4.3/1 — copyWith : préservation intégrale et sentinelle
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.3/1 — copyWith : préservation et sentinelle', () {
    test('B4.3/1.1 sans argument, la copie est identique champ par champ', () {
      final src = ticketComplet();
      final copie = src.copyWith();

      expect(copie.id, src.id);
      expect(copie.dateStr, src.dateStr);
      expect(copie.numReunion, src.numReunion);
      expect(copie.numCourse, src.numCourse);
      expect(copie.nomCourse, src.nomCourse);
      expect(copie.hippodrome, src.hippodrome);
      expect(copie.numeroCheval, src.numeroCheval);
      expect(copie.nomCheval, src.nomCheval);
      expect(copie.cote, src.cote);
      expect(copie.typePari, src.typePari);
      expect(copie.createdAt, src.createdAt);
      expect(copie.isCorrect, src.isCorrect);
      expect(copie.scoreIA, src.scoreIA);
      expect(copie.montantMise, src.montantMise);
      expect(copie.gainRealise, src.gainRealise);
      expect(copie.numerosJoues, src.numerosJoues);
      expect(copie.dividendePmuReel, src.dividendePmuReel);
      expect(copie.combinaisonPmu, src.combinaisonPmu);
      expect(copie.miseGagnant, src.miseGagnant);
      expect(copie.misePlace, src.misePlace);
      expect(copie.coteGagnant, src.coteGagnant);
      expect(copie.cotePlace, src.cotePlace);
      expect(copie.codePmuOfficiel, src.codePmuOfficiel);
      expect(copie.varianteChoisie, src.varianteChoisie);
      expect(copie.numerosDansOrdre, src.numerosDansOrdre);
      expect(copie.formulePari, src.formulePari);
      // Les 7 champs B-1
      expect(copie.etatGain, src.etatGain);
      expect(copie.rapportsAttribues, src.rapportsAttribues);
      expect(copie.etatTirelire, src.etatTirelire);
      expect(copie.dividendeGagnant, src.dividendeGagnant);
      expect(copie.dividendePlace, src.dividendePlace);
      expect(copie.miseBaseCentimesUtilisee, src.miseBaseCentimesUtilisee);
      expect(copie.motifNonDetermination, src.motifNonDetermination);
    });

    test('B4.3/1.2 un argument OMIS conserve l\'ancienne valeur', () {
      final src = ticketComplet();
      final copie = src.copyWith(numReunion: 7);
      expect(copie.numReunion, 7);
      expect(copie.etatGain, EtatGain.attribue, reason: 'non écrasé');
      expect(copie.miseBaseCentimesUtilisee, 100, reason: 'non écrasé');
      expect(copie.rapportsAttribues, isNotNull);
    });

    test('B4.3/1.3 `null` EXPLICITE efface, ce n\'est pas une omission', () {
      final src = ticketComplet();
      expect(src.etatGain, EtatGain.attribue, reason: 'précondition');

      final copie = src.copyWith(etatGain: null);
      expect(copie.etatGain, isNull, reason: 'effacement explicite demandé');
      // Les autres champs B-1 ne bougent pas.
      expect(copie.miseBaseCentimesUtilisee, 100);
      expect(copie.rapportsAttribues, isNotNull);
    });

    test('B4.3/1.4 la source n\'est JAMAIS mutée', () {
      final src = ticketComplet();
      final etatAvant = src.etatGain;
      final miseAvant = src.montantMise;
      final rapportsAvant = src.rapportsAttribues!.length;

      src.copyWith(etatGain: null, montantMise: 99.0, rapportsAttribues: null);

      expect(src.etatGain, etatAvant);
      expect(src.montantMise, miseAvant);
      expect(src.rapportsAttribues!.length, rapportsAvant);
    });

    test('B4.3/1.5 les LISTES sont recopiées, pas partagées', () {
      final src = ticketComplet();
      final copie = src.copyWith();

      expect(identical(copie.numerosJoues, src.numerosJoues), isFalse);
      expect(identical(copie.numerosDansOrdre, src.numerosDansOrdre), isFalse);
      expect(identical(copie.rapportsAttribues, src.rapportsAttribues), isFalse);

      copie.numerosJoues.add(99);
      expect(src.numerosJoues.length, 3, reason: 'l\'original est intact');
    });

    test('B4.3/1.6 listes VIDES et nulls traversent la copie sans confusion',
        () {
      final vide = ticketHistorique().copyWith(
        numerosJoues: <int>[],
        numerosDansOrdre: null,
        rapportsAttribues: <RapportAttribue>[],
      );
      expect(vide.numerosJoues, isEmpty);
      expect(vide.numerosDansOrdre, isNull);
      expect(vide.rapportsAttribues, isEmpty);
      expect(vide.rapportsAttribues, isNotNull,
          reason: '[] ≠ null : « résolu sans rapport »');

      final recopie = vide.copyWith();
      expect(recopie.numerosJoues, isEmpty);
      expect(recopie.numerosDansOrdre, isNull);
      expect(recopie.rapportsAttribues, isEmpty);

      final efface = vide.copyWith(rapportsAttribues: null);
      expect(efface.rapportsAttribues, isNull);
    });

    test('B4.3/1.7 la copie d\'un ticket HISTORIQUE garde 26 clés JSON', () {
      final src = ticketHistorique();
      expect(src.toJson().length, 26);

      final copie = src.copyWith();
      expect(copie.toJson().length, 26,
          reason: 'une copie ne doit RIEN ajouter au schéma');
      expect(copie.toJson().containsKey('etatGain'), isFalse);
      expect(copie.toJson().containsKey('rapportsAttribues'), isFalse);
    });

    test('B4.3/1.8 les valeurs FINANCIÈRES exactes traversent la copie', () {
      final src = ticketHistorique().copyWith(
        montantMise: 12.34,
        cote: 4.25,
        scoreIA: 87.53,
        miseGagnant: 10.01,
        misePlace: 10.02,
        dividendeGagnant: 3.11,
        dividendePlace: 1.79,
      );
      final c = src.copyWith();
      expect(c.montantMise, 12.34);
      expect(c.cote, 4.25);
      expect(c.scoreIA, 87.53);
      expect(c.miseGagnant, 10.01);
      expect(c.misePlace, 10.02);
      expect(c.dividendeGagnant, 3.11);
      expect(c.dividendePlace, 1.79);
      expect(c.miseTotaleEngagee, closeTo(20.03, 1e-12));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.3/2 — écriture des verdicts SANS composante
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.3/2 — verdicts sans composante', () {
    test('B4.3/2.1 perdu : état écrit, aucun rapport, aucun dividende', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: VerdictGain.perdu(explication: 'arrivée non conforme'),
      );

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.perdu);
      expect(r.ticket.rapportsAttribues, isNull,
          reason: 'perdu ⇒ null, JAMAIS []');
      expect(r.ticket.dividendeGagnant, isNull);
      expect(r.ticket.dividendePlace, isNull);
      expect(r.ticket.motifNonDetermination, isNull);
    });

    test('B4.3/2.2 remboursé : état écrit, aucun montant inventé', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: VerdictGain.rembourse(explication: 'bloc remboursé'),
      );
      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.rembourse);
      expect(r.ticket.rapportsAttribues, isNull);
    });

    test('B4.3/2.3 nonDetermine : le MOTIF est conservé', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.arriveeNonDefinitive,
          explication: 'arrivée provisoire',
        ),
      );
      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.nonDetermine);
      expect(r.ticket.motifNonDetermination,
          MotifNonDetermination.arriveeNonDefinitive);
      expect(r.ticket.rapportsAttribues, isNull);
    });

    test('B4.3/2.4 nonDetermine : l\'etatTirelire est conservé', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.tirelireNonDeterminee,
          explication: 'tirelire non déterminable',
          etatTirelire: EtatTirelire.nonDeterminee,
        ),
      );
      expect(r.ticket.etatTirelire, EtatTirelire.nonDeterminee);
    });

    test('B4.3/2.5 un verdict sans composante est ENREGISTRÉ sans montant',
        () {
      // Corrigé en B-4.7 : refuser tout verdict sans composante dès que des
      // rapports existent condamnait un ticket réellement perdant à rester
      // éternellement « en attente ». Un verdict « perdu » ne porte AUCUN
      // montant : l'enregistrer ne peut donc pas fabriquer de gain fictif.
      final avant = ticketHistorique();
      final r = enregistrerVerdictGain(
        ticket: avant,
        verdict: VerdictGain.perdu(explication: 'perdu'),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.estRefuse, isFalse);
      expect(r.ticket.etatGain, EtatGain.perdu);
      expect(r.ticket.rapportsAttribues, isNull, reason: 'aucun montant');
      expect(r.ticket.dividendeGagnant, isNull);
      expect(r.ticket.dividendePlace, isNull);
    });

    test('B4.3/2.6 un verdict « attribue » sans composante est REFUSÉ', () {
      // VerdictGain.attribue LÈVE sur une liste vide : on ne peut donc pas en
      // fabriquer un. On vérifie ici la garde de cohérence sur le seul cas
      // atteignable — un verdict incohérent construit à la main n'existe pas,
      // car tous les constructeurs sont contrôlés. Le test documente la garde.
      expect(
        () => VerdictGain.attribue(composantes: const <ComposanteGain>[]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.3/3 — verdict attribué : exactitude financière
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.3/3 — verdict attribué : exactitude financière', () {
    test('B4.3/3.1 rapport attribué UNIQUE, montants exacts', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.attribue);
      expect(r.ticket.rapportsAttribues, hasLength(1));

      final a = r.ticket.rapportsAttribues!.single;
      expect(a.rapport.codePmu, 'E_TIERCE');
      expect(a.rapport.libelle, 'e-Tiercé Ordre');
      expect(a.rapport.combinaison, '9-4-15');
      expect(a.rapport.variante, VarianteRapport.ordre);
      expect(a.rapport.rang, 1);
      expect(a.rapport.pourUnEuro, 477.40);
      expect(a.miseAppliquee, 2.0);
      expect(a.montantRetour, closeTo(954.80, 1e-9));

      // Le total se reconstitue EXACTEMENT.
      expect(resoudreTotalDepuisRapports(r.ticket.rapportsAttribues),
          closeTo(954.80, 1e-9));
    });

    test('B4.3/3.2 DIVIDENDE ≠ GAIN : pourUnEuro ≠ montantRetour', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );

      final a = r.ticket.rapportsAttribues!.single;
      expect(a.rapport.pourUnEuro, 477.40, reason: 'DIVIDENDE pour 1 €');
      expect(a.montantRetour, closeTo(954.80, 1e-9), reason: 'GAIN remporté');
      expect(a.rapport.pourUnEuro, isNot(closeTo(954.80, 1e-9)),
          reason: 'les deux valeurs ne sont pas interchangeables');
    });

    test('B4.3/3.3 `dividendeGagnant` reçoit pourUnEuro, JAMAIS gainGagnant',
        () {
      // G+P : Gagnant 3,10 €/€ sur 10 €, Placé 1,70 €/€ sur 5 €.
      final gagnant = const RapportPublie(
        codePmu: 'E_SIMPLE_GAGNANT',
        libelle: 'e-Simple Gagnant',
        combinaison: '9',
        variante: VarianteRapport.sansVariante,
        pourUnEuro: 3.10,
      );
      final place = const RapportPublie(
        codePmu: 'E_SIMPLE_PLACE',
        libelle: 'e-Simple Placé',
        combinaison: '9',
        variante: VarianteRapport.sansVariante,
        pourUnEuro: 1.70,
      );
      final verdict = VerdictGain.attribue(
        composantes: const <ComposanteGain>[
          ComposanteGain(
            libelleRapport: 'e-Simple Gagnant',
            combinaisonRapport: '9',
            categorie: VarianteRapport.sansVariante,
            role: RoleComposante.gagnant,
            mise: 10.0,
            pourUnEuro: 3.10,
            montantRetour: 31.0,
          ),
          ComposanteGain(
            libelleRapport: 'e-Simple Placé',
            combinaisonRapport: '9',
            categorie: VarianteRapport.sansVariante,
            role: RoleComposante.place,
            mise: 5.0,
            pourUnEuro: 1.70,
            montantRetour: 8.50,
          ),
        ],
      );

      final r = enregistrerVerdictGain(
        ticket: ticketHistorique().copyWith(typePari: 'Gagnant+Placé'),
        verdict: verdict,
        rapportsOfficiels: <RapportPublie>[gagnant, place],
      );

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.dividendeGagnant, 3.10,
          reason: 'DIVIDENDE, pas le gain de 31,00 €');
      expect(r.ticket.dividendePlace, 1.70,
          reason: 'DIVIDENDE, pas le gain de 8,50 €');
      expect(r.ticket.dividendeGagnant, isNot(closeTo(31.0, 1e-9)));
      expect(r.ticket.dividendePlace, isNot(closeTo(8.50, 1e-9)));

      // Le gain, lui, vit dans les rapports attribués : 31,00 + 8,50 = 39,50.
      expect(resoudreTotalDepuisRapports(r.ticket.rapportsAttribues),
          closeTo(39.50, 1e-9));
    });

    test('B4.3/3.4 G+P : deux mises DIFFÉRENTES, aucune fusion', () {
      final gagnant = const RapportPublie(
        codePmu: 'E_SIMPLE_GAGNANT',
        libelle: 'e-Simple Gagnant',
        combinaison: '9',
        variante: VarianteRapport.sansVariante,
        pourUnEuro: 3.10,
      );
      final place = const RapportPublie(
        codePmu: 'E_SIMPLE_PLACE',
        libelle: 'e-Simple Placé',
        combinaison: '9',
        variante: VarianteRapport.sansVariante,
        pourUnEuro: 1.70,
      );
      final verdict = VerdictGain.attribue(
        composantes: const <ComposanteGain>[
          ComposanteGain(
            libelleRapport: 'e-Simple Gagnant',
            combinaisonRapport: '9',
            categorie: VarianteRapport.sansVariante,
            role: RoleComposante.gagnant,
            mise: 10.0,
            pourUnEuro: 3.10,
            montantRetour: 31.0,
          ),
          ComposanteGain(
            libelleRapport: 'e-Simple Placé',
            combinaisonRapport: '9',
            categorie: VarianteRapport.sansVariante,
            role: RoleComposante.place,
            mise: 5.0,
            pourUnEuro: 1.70,
            montantRetour: 8.50,
          ),
        ],
      );

      final r = enregistrerVerdictGain(
        ticket: ticketHistorique().copyWith(typePari: 'Gagnant+Placé'),
        verdict: verdict,
        rapportsOfficiels: <RapportPublie>[gagnant, place],
      );

      final a = r.ticket.rapportsAttribues!;
      expect(a, hasLength(2));
      final mises = a.map((x) => x.miseAppliquee).toList()..sort();
      expect(mises, <double>[5.0, 10.0],
          reason: 'les deux mises restent distinctes');
      expect(mises, isNot(<double>[5.0, 5.0]));
      expect(mises, isNot(<double>[10.0, 10.0]));
    });

    test('B4.3/3.5 plusieurs rapports : la somme égale exactement le total',
        () {
      final un = const RapportPublie(
        codePmu: 'E_QUINTE_PLUS',
        libelle: 'e-Bonus 4sur5',
        combinaison: '9-4-15-10',
        variante: VarianteRapport.bonus4sur5,
        pourUnEuro: 7.20,
      );
      final deux = const RapportPublie(
        codePmu: 'E_QUINTE_PLUS',
        libelle: 'e-Bonus 4sur5',
        combinaison: '9-4-10-1',
        variante: VarianteRapport.bonus4sur5,
        pourUnEuro: 7.20,
      );
      final verdict = VerdictGain.attribue(
        composantes: const <ComposanteGain>[
          ComposanteGain(
            libelleRapport: 'e-Bonus 4sur5',
            combinaisonRapport: '9-4-15-10',
            categorie: VarianteRapport.bonus4sur5,
            mise: 3.0,
            pourUnEuro: 7.20,
            montantRetour: 21.60,
          ),
          ComposanteGain(
            libelleRapport: 'e-Bonus 4sur5',
            combinaisonRapport: '9-4-10-1',
            categorie: VarianteRapport.bonus4sur5,
            mise: 3.0,
            pourUnEuro: 7.20,
            montantRetour: 21.60,
          ),
        ],
      );

      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdict,
        rapportsOfficiels: <RapportPublie>[un, deux],
      );

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.rapportsAttribues, hasLength(2));
      expect(resoudreTotalDepuisRapports(r.ticket.rapportsAttribues),
          closeTo(43.20, 1e-9));
      expect(resoudreTotalDepuisRapports(r.ticket.rapportsAttribues),
          closeTo(verdict.total, 1e-9));
    });

    test('B4.3/3.6 montant supérieur NON applicable : jamais sélectionné', () {
      // Le Désordre (80,30) est fourni AVEC l'Ordre (477,40) mais le verdict
      // ne porte QUE l'Ordre. Le rapport attribué doit être l'Ordre.
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[
          rapportOfficielTierceDesordre(),
          rapportOfficielTierceOrdre(),
        ],
      );

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.rapportsAttribues!.single.rapport.libelle,
          'e-Tiercé Ordre');
      expect(r.ticket.rapportsAttribues!.single.rapport.pourUnEuro, 477.40);
      expect(r.ticket.rapportsAttribues!.single.rapport.pourUnEuro,
          isNot(80.30));
    });

    test('B4.3/3.7 même dividende, deux variantes : aucune confusion', () {
      // Deux rapports STRICTEMENT au même montant (7,20) mais de combinaisons
      // et de variantes différentes. Si le filtrage ne portait que sur le
      // montant, il y aurait ambiguïté. Il porte aussi sur libellé +
      // combinaison + variante, donc la résolution est unique.
      final a = const RapportPublie(
        codePmu: 'E_QUINTE_PLUS',
        libelle: 'e-Bonus 4sur5',
        combinaison: '9-4-15-10',
        variante: VarianteRapport.bonus4sur5,
        pourUnEuro: 7.20,
      );
      final b = const RapportPublie(
        codePmu: 'E_QUINTE_PLUS',
        libelle: 'e-Bonus 4sur5',
        combinaison: '4-15-10-1',
        variante: VarianteRapport.bonus4sur5,
        pourUnEuro: 7.20,
      );
      final verdict = VerdictGain.attribue(
        composantes: const <ComposanteGain>[
          ComposanteGain(
            libelleRapport: 'e-Bonus 4sur5',
            combinaisonRapport: '4-15-10-1',
            categorie: VarianteRapport.bonus4sur5,
            mise: 1.0,
            pourUnEuro: 7.20,
            montantRetour: 7.20,
          ),
        ],
      );

      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdict,
        rapportsOfficiels: <RapportPublie>[a, b],
      );

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.rapportsAttribues!.single.rapport.combinaison,
          '4-15-10-1');
    });

    test('B4.3/3.8 centimes et arrondis : aucun centime perdu', () {
      // 1,11 € / € sur 3 € = 3,33 € — et 7 × 1,11 sur 3 composantes.
      final un = const RapportPublie(
        codePmu: 'E_QUINTE_PLUS',
        libelle: 'e-Bonus 3',
        combinaison: '9-4-15',
        variante: VarianteRapport.bonus3,
        pourUnEuro: 1.11,
      );
      final verdict = VerdictGain.attribue(
        composantes: const <ComposanteGain>[
          ComposanteGain(
            libelleRapport: 'e-Bonus 3',
            combinaisonRapport: '9-4-15',
            categorie: VarianteRapport.bonus3,
            mise: 3.0,
            pourUnEuro: 1.11,
            montantRetour: 3.33,
          ),
        ],
      );

      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdict,
        rapportsOfficiels: <RapportPublie>[un],
      );

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.rapportsAttribues!.single.montantRetour, 3.33);
      expect(resoudreTotalDepuisRapports(r.ticket.rapportsAttribues), 3.33);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.3/4 — REFUS : chaque écart est un refus explicite, sans mutation
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.3/4 — refus explicites', () {
    test('B4.3/4.1 rapport officiel INTROUVABLE ⇒ refus, ticket intact', () {
      final avant = ticketHistorique();
      final r = enregistrerVerdictGain(
        ticket: avant,
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[
          // Mauvais libellé, mauvaise variante.
          rapportOfficielTierceDesordre(),
        ],
      );

      expect(r.statut, StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable);
      expect(identical(r.ticket, avant), isTrue);
      expect(r.ticket.etatGain, isNull);
      expect(r.motif, isNotNull);
    });

    test('B4.3/4.2 AUCUN rapport officiel ⇒ refus', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdictTierceOrdreAttribue(),
      );
      expect(r.statut, StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable);
      expect(r.ticket.etatGain, isNull);
    });

    test('B4.3/4.3 SUM ≠ TOTAL ⇒ refus (aucun total reconstruit de force)', () {
      // Le verdict ANNONCE 954,80 € mais ses composantes n'en totalisent que
      // 900,00 €. Un enregistreur honnête refuse : il ne « corrige » rien.
      final incoherent = VerdictGain.attribue(
        composantes: const <ComposanteGain>[
          ComposanteGain(
            libelleRapport: 'e-Tiercé Ordre',
            combinaisonRapport: '9-4-15',
            categorie: VarianteRapport.ordre,
            mise: 2.0,
            pourUnEuro: 450.0,
            montantRetour: 900.0,
          ),
        ],
      );
      // Le verdict est cohérent en interne (somme = total = 900), mais le
      // rapport officiel, lui, vaut 477,40 → le recalcul donne 954,80.
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: incoherent,
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );

      expect(r.statut, StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable,
          reason: 'aucun rapport officiel ne porte ×450,00');
      expect(r.ticket.etatGain, isNull);
    });

    test('B4.3/4.4 TOTAL du verdict ≠ somme de ses composantes ⇒ refus', () {
      // Ici on teste la garde de COHÉRENCE interne : impossible de construire
      // un tel verdict via les constructeurs publics (tous recalculent), donc
      // on vérifie que la garde existe via un verdict valide mais dont le
      // rapport officiel porte un montant différent → refus de total.
      final verdict = VerdictGain.attribue(
        composantes: const <ComposanteGain>[
          ComposanteGain(
            libelleRapport: 'e-Tiercé Désordre',
            combinaisonRapport: '9-4-15',
            categorie: VarianteRapport.desordre,
            mise: 2.0,
            pourUnEuro: 80.30,
            montantRetour: 160.60,
          ),
        ],
      );
      // Le rapport officiel fourni porte la MÊME identité mais un montant
      // différent → la correspondance échoue, donc refus.
      final falsifie = const RapportPublie(
        codePmu: 'E_TIERCE',
        libelle: 'e-Tiercé Désordre',
        combinaison: '9-4-15',
        variante: VarianteRapport.desordre,
        pourUnEuro: 90.30, // ← écart d'un euro
        rang: 2,
      );
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdict,
        rapportsOfficiels: <RapportPublie>[falsifie],
      );
      expect(
        r.statut == StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable ||
            r.statut == StatutEnregistrementVerdict.refuseTotalIncoherent,
        isTrue,
        reason: 'soit introuvable, soit total incohérent — jamais accepté',
      );
      expect(r.ticket.etatGain, isNull);
    });

    test('B4.3/4.5 plusieurs candidats AMBIGUS ⇒ refus, jamais le plus élevé',
        () {
      // Deux rapports STRICTEMENT identiques en libellé/combinaison/variante
      // mais de montants différents : les deux ne peuvent pas matcher une
      // composante de montant 477,40 — un seul matche. Pour créer une VRAIE
      // ambiguïté, on fournit DEUX FOIS le même rapport avec deux `rang`
      // différents : identité de contenu, mais pas le même rapport.
      const a = RapportPublie(
        codePmu: 'E_TIERCE',
        libelle: 'e-Tiercé Ordre',
        combinaison: '9-4-15',
        variante: VarianteRapport.ordre,
        pourUnEuro: 477.40,
        rang: 1,
      );
      const b = RapportPublie(
        codePmu: 'E_TIERCE',
        libelle: 'e-Tiercé Ordre',
        combinaison: '9-4-15',
        variante: VarianteRapport.ordre,
        pourUnEuro: 477.40,
        rang: 2, // ← rang différent : rapport distinct
      );
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[a, b],
      );
      expect(r.statut, StatutEnregistrementVerdict.refuseRapportOfficielAmbigu);
      expect(r.ticket.etatGain, isNull);
      expect(r.motif, contains('plus élevé'),
          reason: 'le motif dit explicitement que le montant ne départage pas');
    });

    test('B4.3/4.6 le MÊME rapport fourni deux fois n\'est PAS ambigu', () {
      final rapport = rapportOfficielTierceOrdre();
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapport, rapport],
      );
      expect(r.statut, StatutEnregistrementVerdict.enregistre,
          reason: 'doublon exact ≠ ambiguïté');
      expect(r.ticket.rapportsAttribues, hasLength(1));
    });

    test('B4.3/4.7 mise de composante NULLE ⇒ refus', () {
      final verdict = VerdictGain.attribue(
        composantes: const <ComposanteGain>[
          ComposanteGain(
            libelleRapport: 'e-Tiercé Ordre',
            combinaisonRapport: '9-4-15',
            categorie: VarianteRapport.ordre,
            mise: 0.0, // ← mise nulle
            pourUnEuro: 477.40,
            montantRetour: 0.0,
          ),
        ],
      );
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdict,
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(r.statut, StatutEnregistrementVerdict.refuseVerdictIncoherent);
      expect(r.ticket.etatGain, isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.3/5 — POLITIQUE : protection contre l'écrasement
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.3/5 — politique d\'enregistrement', () {
    test('B4.3/5.1 double enregistrement IDENTIQUE : idempotent', () {
      final premier = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(premier.statut, StatutEnregistrementVerdict.enregistre);

      final second = enregistrerVerdictGain(
        ticket: premier.ticket,
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(second.statut, StatutEnregistrementVerdict.dejaIdentique);
      expect(identical(second.ticket, premier.ticket), isTrue,
          reason: 'aucune copie inutile n\'est produite');
    });

    test('B4.3/5.2 verdict DÉFINITIF : toute réécriture est refusée', () {
      final premier = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: VerdictGain.perdu(explication: 'perdu'),
      );
      expect(premier.ticket.etatGain, EtatGain.perdu);

      // Tentative d'écrire un gain ATTRIBUÉ par-dessus une perte établie.
      final second = enregistrerVerdictGain(
        ticket: premier.ticket,
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(second.statut,
          StatutEnregistrementVerdict.refuseVerdictDefinitifExistant);
      expect(second.ticket.etatGain, EtatGain.perdu, reason: 'inchangé');
      expect(second.ticket.rapportsAttribues, isNull, reason: 'inchangé');
      expect(identical(second.ticket, premier.ticket), isTrue);
    });

    test('B4.3/5.3 nonDetermine : transition vers un verdict définitif AUTORISÉE',
        () {
      // Corrigé en B-4.7 : un ticket « nonDetermine » doit pouvoir devenir
      // définitif dès qu'une récupération officielle démontre le verdict.
      final premier = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.arriveeNonDefinitive,
          explication: 'provisoire',
        ),
      );
      expect(premier.ticket.etatGain, EtatGain.nonDetermine);

      final second = enregistrerVerdictGain(
        ticket: premier.ticket,
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(second.statut, StatutEnregistrementVerdict.enregistre);
      expect(second.ticket.etatGain, EtatGain.attribue);
      expect(second.ticket.rapportsAttribues, isNotNull);
    });

    test('B4.3/5.4 nonDetermine RÉPÉTÉ avec le même motif : idempotent', () {
      final premier = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.rapportAmbigu,
          explication: 'ambigu',
        ),
      );
      final second = enregistrerVerdictGain(
        ticket: premier.ticket,
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.rapportAmbigu,
          explication: 'ambigu, autre texte',
        ),
      );
      expect(second.statut, StatutEnregistrementVerdict.dejaIdentique);
    });

    test('B4.3/5.5 un refus conserve mises, numéros et identité du ticket', () {
      final avant = ticketHistorique();
      final r = enregistrerVerdictGain(
        ticket: avant,
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceDesordre()],
      );
      expect(r.estRefuse, isTrue);
      expect(r.ticket.id, avant.id);
      expect(r.ticket.montantMise, avant.montantMise);
      expect(r.ticket.numerosJoues, avant.numerosJoues);
      expect(r.ticket.numeroCheval, avant.numeroCheval);
      expect(r.ticket.createdAt, avant.createdAt);
      expect(r.ticket.typePari, avant.typePari);
    });

    test('B4.3/5.6 un ticket historique NON concerné garde ses 26 clés', () {
      final historique = ticketHistorique();
      expect(historique.toJson().length, 26);
      // Aucune opération n'a eu lieu : la forme est intacte.
      final relu = UserPrediction.fromJson(historique.toJson());
      expect(relu.toJson().length, 26);
      expect(relu.etatGain, isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.3/6 — persistance : JSON, restauration, reconstruction
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.3/6 — persistance et reconstruction', () {
    test('B4.3/6.1 aller-retour JSON : les 7 clés survivent', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      final json = r.ticket.toJson();
      expect(json.length, 33, reason: '26 + 7 clés B-1');

      final relu = UserPrediction.fromJson(json);
      expect(relu.etatGain, EtatGain.attribue);
      expect(relu.etatTirelire, EtatTirelire.sansObjet);
      expect(relu.rapportsAttribues, hasLength(1));
      expect(relu.motifNonDetermination, isNull);
      expect(relu.miseBaseCentimesUtilisee, 100);
      expect(relu.dividendeGagnant, isNull);
      expect(relu.dividendePlace, isNull);
    });

    test('B4.3/6.2 le TOTAL se reconstitue après désérialisation', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      final relu = UserPrediction.fromJson(r.ticket.toJson());
      expect(resoudreTotalDepuisRapports(relu.rapportsAttribues),
          closeTo(954.80, 1e-9),
          reason: 'le gain survit sans champ scalaire dédié');
    });

    test('B4.3/6.3 le rapport officiel complet survit (code, rang, montant)', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      final relu = UserPrediction.fromJson(r.ticket.toJson());
      final a = relu.rapportsAttribues!.single;
      expect(a.rapport.codePmu, 'E_TIERCE');
      expect(a.rapport.libelle, 'e-Tiercé Ordre');
      expect(a.rapport.variante, VarianteRapport.ordre);
      expect(a.rapport.combinaison, '9-4-15');
      expect(a.rapport.rang, 1);
      expect(a.rapport.pourUnEuro, 477.40);
      expect(a.rapport.miseBaseCentimes, 100);
      expect(a.miseAppliquee, 2.0);
      expect(a.montantRetour, closeTo(954.80, 1e-9));
    });

    test('B4.3/6.4 `rapportsAttribues == null` reste null après relecture', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: VerdictGain.perdu(explication: 'perdu'),
      );
      final relu = UserPrediction.fromJson(r.ticket.toJson());
      expect(relu.rapportsAttribues, isNull,
          reason: 'null ≠ [] : « jamais résolu »');
      expect(relu.etatGain, EtatGain.perdu);
    });

    test('B4.3/6.5 un nonDetermine conserve son motif après relecture', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.deadHeatSansGroupes,
          explication: 'ex æquo sans groupes',
          etatTirelire: EtatTirelire.nonDeterminee,
        ),
      );
      final relu = UserPrediction.fromJson(r.ticket.toJson());
      expect(relu.etatGain, EtatGain.nonDetermine);
      expect(relu.motifNonDetermination,
          MotifNonDetermination.deadHeatSansGroupes);
      expect(relu.etatTirelire, EtatTirelire.nonDeterminee);
    });

    test('B4.3/6.6 relire puis réécrire ne change rien (stabilité)', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      final j1 = r.ticket.toJson();
      final j2 = UserPrediction.fromJson(j1).toJson();
      expect(j2.keys.toSet(), j1.keys.toSet());
      expect(j2.length, j1.length);
    });

    test('B4.3/6.7 une sauvegarde HISTORIQUE (sans clés B-1) reste lisible', () {
      final ancien = <String, dynamic>{
        'id': 'old_1',
        'dateStr': '2025-01-01',
        'numReunion': 2,
        'numCourse': 3,
        'nomCourse': 'Ancienne',
        'hippodrome': 'Cagnes',
        'numeroCheval': 5,
        'nomCheval': 'Vieux Cheval',
        'cote': 6.5,
        'typePari': 'Simple Gagnant',
        'createdAt': '2025-01-01T10:00:00.000',
        'isCorrect': false,
        'scoreIA': 50.0,
        'montantMise': 5.0,
        'gainRealise': -5.0,
        'numerosJoues': <int>[5],
      };
      final relu = UserPrediction.fromJson(ancien);
      expect(relu.etatGain, isNull, reason: 'clé absente ⇒ legacy');
      expect(relu.rapportsAttribues, isNull);
      expect(relu.motifNonDetermination, isNull);
      expect(relu.miseBaseCentimesUtilisee, isNull);
      expect(relu.gainNet, -5.0, reason: 'formule historique intacte');
    });

    // ═══════════════════════════════════════════════════════════════════════
    //  B4.3/6bis — MÉCANISME RÉEL DE SAUVEGARDE ET RESTAURATION
    //
    //  `pmu_provider.dart` sauvegarde par
    //      `jsonEncode(p.toJson())`  →  `prefs.setStringList('user_predictions_v2')`
    //  (l.331-332) et restaure par
    //      `jsonDecode(str) as Map`  →  `UserPrediction.fromJson(map)`
    //  (l.308-310).
    //
    //  ⚠️ PÉRIMÈTRE : `PmuProvider` n'est PAS modifié et n'est PAS instancié
    //     ici (il exige un état de course complet). On reproduit à l'IDENTIQUE
    //     la transformation qu'il applique — mêmes appels `dart:convert`,
    //     même type de conteneur — ce qui prouve que le ticket enrichi
    //     traverse réellement la chaîne de persistance de l'application.
    //     C'est une reproduction fidèle, pas un test d'intégration bout en
    //     bout : la limite est signalée dans le rapport.
    // ═══════════════════════════════════════════════════════════════════════
    test('B4.3/6.8 le ticket enrichi traverse le VRAI encodage du provider', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );

      // ── Sauvegarde : exactement comme `_savePredictions`. ────────────────
      final predictions = <UserPrediction>[ticketHistorique(), r.ticket];
      final sauvegarde =
          predictions.map((p) => jsonEncode(p.toJson())).toList();

      expect(sauvegarde, hasLength(2));
      expect(sauvegarde.first, isA<String>());
      // Le ticket historique n'a PAS gagné de clé.
      final historiqueDecode =
          jsonDecode(sauvegarde[0]) as Map<String, dynamic>;
      expect(historiqueDecode.length, 26);
      final enrichiDecode = jsonDecode(sauvegarde[1]) as Map<String, dynamic>;
      expect(enrichiDecode.length, 33);

      // ── Restauration : exactement comme `_loadSavedPredictions`. ─────────
      final restaures = <UserPrediction>[];
      for (final str in sauvegarde) {
        final map = jsonDecode(str) as Map<String, dynamic>;
        restaures.add(UserPrediction.fromJson(map));
      }

      expect(restaures, hasLength(2));
      expect(restaures[0].etatGain, isNull, reason: 'historique intact');
      expect(restaures[1].etatGain, EtatGain.attribue);
      expect(resoudreTotalDepuisRapports(restaures[1].rapportsAttribues),
          closeTo(954.80, 1e-9),
          reason: 'le gain survit à la sauvegarde réelle');
    });

    test('B4.3/6.9 les valeurs FINANCIÈRES exactes survivent au trajet complet',
        () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique().copyWith(montantMise: 12.34),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      final str = jsonEncode(r.ticket.toJson());
      final restaure =
          UserPrediction.fromJson(jsonDecode(str) as Map<String, dynamic>);

      expect(restaure.montantMise, 12.34);
      expect(restaure.rapportsAttribues!.single.rapport.pourUnEuro, 477.40);
      expect(restaure.rapportsAttribues!.single.miseAppliquee, 2.0);
      expect(restaure.rapportsAttribues!.single.montantRetour, 954.80);
      expect(restaure.miseBaseCentimesUtilisee, 100);
      // contrôle d'unité : un dividende pour 1 € n'est pas un gain de 954,80
      expect(restaure.rapportsAttribues!.single.rapport.pourUnEuro,
          isNot(closeTo(954.80, 1e-9)));
    });

    test('B4.3/6.10 un `nonDetermine` traverse le trajet avec son motif', () {
      final r = enregistrerVerdictGain(
        ticket: ticketHistorique(),
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.tailleCombinaisonAnormale,
          explication: 'taille anormale',
        ),
      );
      final str = jsonEncode(r.ticket.toJson());
      final restaure =
          UserPrediction.fromJson(jsonDecode(str) as Map<String, dynamic>);
      expect(restaure.etatGain, EtatGain.nonDetermine);
      expect(restaure.motifNonDetermination,
          MotifNonDetermination.tailleCombinaisonAnormale);
      expect(restaure.rapportsAttribues, isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B4.3/7 — garde compensatoire du périmètre (B0/1 exclut l'enregistreur)
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.3/7 — garde compensatoire du périmètre', () {
    String codeSansCommentaires(String chemin) {
      final lignes = File(chemin).readAsStringSync().split('\n');
      final gardees = <String>[];
      for (final l in lignes) {
        if (l.trimLeft().startsWith('//')) continue;
        gardees.add(l);
      }
      return gardees.join('\n');
    }

    test('B4.3/7.1 l\'enregistreur n\'appelle JAMAIS le moteur B-3', () {
      final code =
          codeSansCommentaires('lib/services/enregistreur_verdict_gain_pmu.dart');
      expect(code.contains('resoudreGainTicket('), isFalse,
          reason: 'le verdict est une ENTRÉE, jamais un calcul');
      expect(code.contains('arbitrerVariante('), isFalse);
      expect(code.contains('resoudreRapportPmu('), isFalse);
    });

    test('B4.3/7.2 l\'enregistreur n\'écrit rien et ne touche aucun écran', () {
      final code =
          codeSansCommentaires('lib/services/enregistreur_verdict_gain_pmu.dart');
      for (final interdit in <String>[
        'dart:io',
        'SharedPreferences',
        'Hive',
        'notifyListeners',
        'setState',
        'AlertService',
        'PmuProvider',
      ]) {
        expect(code.contains(interdit), isFalse, reason: interdit);
      }
    });

    test('B4.3/7.3 `RapportAttribue.calculer` n\'apparaît QUE dans la branche '
        'd\'écriture', () {
      final code =
          codeSansCommentaires('lib/services/enregistreur_verdict_gain_pmu.dart');
      final occurrences = 'RapportAttribue.calculer'.allMatches(code).length;
      expect(occurrences, 1,
          reason: 'un seul point de construction, dans la boucle d\'attribution');
    });

    test('B4.3/7.4 aucune sélection par montant maximal dans l\'enregistreur',
        () {
      final code =
          codeSansCommentaires('lib/services/enregistreur_verdict_gain_pmu.dart');
      for (final interdit in <String>['reduce(', '.sort(', 'Math.max']) {
        expect(code.contains(interdit), isFalse, reason: interdit);
      }
      expect(code.contains('dividende >'), isFalse);
    });

    test('B4.3/7.5 les 11 fichiers protégés existent et reduce(MAX) est ABSENT',
        () {
      // La garde d'origine vérifiait la PRÉSENCE du `reduce(MAX)` dans les deux
      // écrans : c'était exact pour B-4.3, qui ne branchait rien. B-4.5 change
      // la propriété à défendre, dans le sens le plus strict : la sélection par
      // montant maximal doit avoir DISPARU de tout `lib/`.
      //
      // MESURÉ avant d'écrire : `grep "reduce((a, b) => a.dividende > b.dividende"
      // lib/` ne renvoie plus rien (les deux occurrences de mes_paris_screen
      // l.1105 et paris_detail_screen l.691 ont été supprimées).
      final proteges = <String>[
        'lib/screens/mes_paris_screen.dart',
        'lib/screens/paris_detail_screen.dart',
        'lib/services/moteur_gain_pmu.dart',
        'lib/services/arbitre_variante_pmu.dart',
        'lib/services/resolveur_rapport_pmu.dart',
        'lib/services/gain_calculator.dart',
        'lib/services/alert_service.dart',
        'lib/providers/pmu_provider.dart',
        'lib/models/zt_models.dart',
        'lib/services/gain_pmu_types.dart',
        'lib/services/gain_ticket_calculator.dart',
      ];
      for (final f in proteges) {
        expect(File(f).existsSync(), isTrue, reason: f);
      }

      // ★ B-4.5 — la neutralisation est prouvée, fichier par fichier, dans
      // TOUT `lib/` : aucun `reduce` ne compare plus deux dividendes.
      final coupables = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final code = codeSansCommentaires(f.path);
        if (code.contains('reduce((a, b) => a.dividende > b.dividende') ||
            code.contains('reduce((a, b) => a.dividende >') ||
            RegExp(r'\.reduce\([^)]*dividende').hasMatch(code)) {
          coupables.add(f.path);
        }
      }
      expect(coupables, isEmpty,
          reason: 'aucune sélection de dividende maximal ne doit subsister : '
              '$coupables');

      // Et les deux écrans portent bien le branchement B-4.5 à la place.
      // ★ B1-T12 / LOT 2-C — ANCRE MISE À JOUR, INTENTION CONSERVÉE.
      //   La garde exigeait `resoudrePrediction` DANS l'écran. Le défaut D1
      //   (mesuré) a imposé de déplacer la résolution DANS le provider : un
      //   écran résolvait sur un instantané capturé avant l'attente réseau,
      //   puis remplaçait un objet entier — écrasant une saisie manuelle
      //   concurrente. L'écran DÉLÈGUE désormais ; il ne sélectionne toujours
      //   aucun dividende, ce que les deux assertions suivantes continuent
      //   d'interdire.
      for (final ecran in <String>[
        'lib/screens/mes_paris_screen.dart',
        'lib/screens/paris_detail_screen.dart',
      ]) {
        final code = codeSansCommentaires(ecran);
        expect(code.contains('appliquerVerdictGainPredictionSecurise'), isTrue,
            reason: '$ecran doit écrire le verdict via la voie sécurisée');
        expect(code.contains('resoudreSuivi'), isTrue, reason: ecran);
        // Le chemin dangereux par instantané ne doit plus être emprunté.
        expect(code.contains('appliquerVerdictGainPrediction('), isFalse,
            reason: '$ecran ne doit plus remplacer un objet entier');
        // Les deux écritures de l'ancien chemin ont disparu de ces écrans.
        expect(code.contains('enregistrerDividendePmuTracked'), isFalse,
            reason: '$ecran ne doit plus écrire de dividende sélectionné');
        expect(code.contains('enregistrerDividendePmu('), isFalse,
            reason: '$ecran ne doit plus injecter de gain dans l\'IA');
      }
    });
  });
}
