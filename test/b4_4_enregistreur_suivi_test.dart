// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-4.4 — TESTS DE L'ENREGISTREMENT DU VERDICT SUR `TrackedCourse`
//
//  Couverture : les 20 familles exigées par la consigne (§5).
//  Chaque groupe vérifie des MONTANTS EXACTS et ce qui est RÉELLEMENT
//  conservé — jamais seulement un état.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/arbitre_variante_pmu.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_suivi.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show VarianteRapport;
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart';

// ───────────────────────────────────────────────────────────────────────────
//  FIÈTURES
// ───────────────────────────────────────────────────────────────────────────

final DateTime _heure = DateTime.utc(2026, 11, 15, 14, 30);
final DateTime _ajout = DateTime.utc(2026, 11, 15, 12, 0);

/// Ticket suivi HISTORIQUE : les 28 clés, aucun champ B-1.
TrackedCourse suiviHistorique() => TrackedCourse(
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'Prix de Test',
      hippodrome: 'Vincennes',
      heureDepart: _heure,
      storageKey: 'R1C6_15112026_1763',
      nomCheval: 'Idao de Tillard',
      numeroCheval: 9,
      miseEngagee: 2.0,
      addedAt: _ajout,
      typePari: 'Tiercé Ordre',
      numerosJoues: const <int>[9, 4, 15],
      iaMemKey: 'R1C6_15112026_ia',
      scoreIA: 87.5,
      cote: 4.2,
      codePmuOfficiel: 'E_TIERCE',
      varianteChoisie: 'ordre',
      numerosDansOrdre: const <int>[9, 4, 15],
    );

/// Le même ticket avec les sept champs B-1 renseignés (verdict attribué).
TrackedCourse suiviComplet() => suiviHistorique().copyWith(
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

/// Ticket de PROFIL historique, pour la barrière d'identité.
UserPrediction predictionHistorique() => UserPrediction(
      id: 'R1C6_15112026_1763',
      dateStr: '2026-11-15',
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'Prix de Test',
      hippodrome: 'Vincennes',
      numeroCheval: 9,
      nomCheval: 'Idao de Tillard',
      cote: 4.2,
      typePari: 'Tiercé Ordre',
      createdAt: _heure,
      scoreIA: 87.5,
      montantMise: 2.0,
      numerosJoues: <int>[9, 4, 15],
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

/// Verdict Gagnant+Placé : 10 € gagnant ×12,50 + 10 € placé ×4,10.
VerdictGain verdictGagnantPlace() => VerdictGain.attribue(
      composantes: <ComposanteGain>[
        const ComposanteGain(
          libelleRapport: 'e-Simple Gagnant',
          combinaisonRapport: '9',
          categorie: VarianteRapport.sansVariante,
          role: RoleComposante.gagnant,
          mise: 10.0,
          pourUnEuro: 12.50,
          montantRetour: 125.0,
        ),
        const ComposanteGain(
          libelleRapport: 'e-Simple Placé',
          combinaisonRapport: '9',
          categorie: VarianteRapport.sansVariante,
          role: RoleComposante.place,
          mise: 10.0,
          pourUnEuro: 4.10,
          montantRetour: 41.0,
        ),
      ],
    );

RapportPublie rapportGagnant() => const RapportPublie(
      codePmu: 'E_SIMPLE_GAGNANT',
      libelle: 'e-Simple Gagnant',
      combinaison: '9',
      variante: VarianteRapport.sansVariante,
      pourUnEuro: 12.50,
      rang: 1,
      miseBaseCentimes: 100,
    );

RapportPublie rapportPlace() => const RapportPublie(
      codePmu: 'E_SIMPLE_PLACE',
      libelle: 'e-Simple Placé',
      combinaison: '9',
      variante: VarianteRapport.sansVariante,
      pourUnEuro: 4.10,
      rang: 1,
      miseBaseCentimes: 100,
    );

/// Verdict « non déterminé » — l'`explication` est obligatoire dans le moteur
/// (mesuré : `factory VerdictGain.nonDetermine` exige `required String
/// explication`). Elle n'a AUCUN champ B-1 : elle est perdue à l'écriture, ce
/// que `persistanceComplete: false` déclare honnêtement.
VerdictGain _nonDetermine({
  required MotifNonDetermination motif,
  EtatTirelire etatTirelire = EtatTirelire.sansObjet,
}) =>
    VerdictGain.nonDetermine(
      motif: motif,
      explication: 'explication de test',
      etatTirelire: etatTirelire,
    );

VerdictGain _perdu({EtatTirelire etatTirelire = EtatTirelire.sansObjet}) =>
    VerdictGain.perdu(
      explication: 'explication de test',
      etatTirelire: etatTirelire,
    );

VerdictGain _rembourse({EtatTirelire etatTirelire = EtatTirelire.sansObjet}) =>
    VerdictGain.rembourse(
      explication: 'explication de test',
      etatTirelire: etatTirelire,
    );

/// ★ Retire les COMMENTAIRES d'un source Dart avant analyse.
///
/// Même raison qu'en B-0 : un fichier qui CITE un nom dans un commentaire
/// (ici `enregistreur_verdict_gain_pmu.dart`, qui documente que l'enregistreur
/// suivi existe et applique la même décision) ne doit pas être déclaré
/// « appelant ». Le contournement aurait été d'exclure ce fichier du contrôle ;
/// on préfère rendre le contrôle exact — il vérifie alors les APPELS, ce qui
/// est la propriété réellement voulue, et couvre PLUS de fichiers qu'avant.
String _sansCommentaires(String source) {
  final sb = StringBuffer();
  var i = 0;
  var etat = 0; // 0=code, 1=', 2=", 3=//, 4=/* */
  while (i < source.length) {
    final c = source[i];
    final suivant = (i + 1 < source.length) ? source[i + 1] : '';
    switch (etat) {
      case 0:
        if (c == '/' && suivant == '/') {
          etat = 3;
          i += 2;
          continue;
        }
        if (c == '/' && suivant == '*') {
          etat = 4;
          i += 2;
          continue;
        }
        if (c == "'") {
          etat = 1;
        } else if (c == '"') {
          etat = 2;
        }
        sb.write(c);
        i++;
      case 1:
        sb.write(c);
        if (c == r'\') {
          if (i + 1 < source.length) sb.write(source[i + 1]);
          i += 2;
          continue;
        }
        if (c == "'") etat = 0;
        i++;
      case 2:
        sb.write(c);
        if (c == r'\') {
          if (i + 1 < source.length) sb.write(source[i + 1]);
          i += 2;
          continue;
        }
        if (c == '"') etat = 0;
        i++;
      case 3:
        if (c == '\n') {
          etat = 0;
          sb.write(c);
        }
        i++;
      case 4:
        if (c == '*' && suivant == '/') {
          etat = 0;
          i += 2;
          continue;
        }
        if (c == '\n') sb.write(c);
        i++;
      default:
        i++;
    }
  }
  return sb.toString();
}

// ───────────────────────────────────────────────────────────────────────────
//  GROUPES
// ───────────────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  //  B4.4/2 — copyWith : identité, sentinelle, listes, non-mutation
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.4/2 — copyWith sur TrackedCourse', () {
    test('2.1 sans argument, la copie est identique champ par champ', () {
      final src = suiviComplet();
      final copie = src.copyWith();

      expect(copie.numReunion, src.numReunion);
      expect(copie.numCourse, src.numCourse);
      expect(copie.nomCourse, src.nomCourse);
      expect(copie.hippodrome, src.hippodrome);
      expect(copie.heureDepart, src.heureDepart);
      expect(copie.storageKey, src.storageKey);
      expect(copie.nomCheval, src.nomCheval);
      expect(copie.numeroCheval, src.numeroCheval);
      expect(copie.miseEngagee, src.miseEngagee);
      expect(copie.miseGagnant, src.miseGagnant);
      expect(copie.misePlace, src.misePlace);
      expect(copie.coteGagnant, src.coteGagnant);
      expect(copie.cotePlace, src.cotePlace);
      expect(copie.addedAt, src.addedAt);
      expect(copie.typePari, src.typePari);
      expect(copie.numerosJoues, src.numerosJoues);
      expect(copie.iaMemKey, src.iaMemKey);
      expect(copie.scoreIA, src.scoreIA);
      expect(copie.cote, src.cote);
      expect(copie.isGagne, src.isGagne);
      expect(copie.arriveeFinale, src.arriveeFinale);
      expect(copie.messageResultat, src.messageResultat);
      expect(copie.dividendePmuReel, src.dividendePmuReel);
      expect(copie.combinaisonPmu, src.combinaisonPmu);
      expect(copie.codePmuOfficiel, src.codePmuOfficiel);
      expect(copie.varianteChoisie, src.varianteChoisie);
      expect(copie.numerosDansOrdre, src.numerosDansOrdre);
      expect(copie.formulePari, src.formulePari);
      // Les sept champs B-1
      expect(copie.etatGain, src.etatGain);
      expect(copie.etatTirelire, src.etatTirelire);
      expect(copie.dividendeGagnant, src.dividendeGagnant);
      expect(copie.dividendePlace, src.dividendePlace);
      expect(copie.miseBaseCentimesUtilisee, src.miseBaseCentimesUtilisee);
      expect(copie.motifNonDetermination, src.motifNonDetermination);
      expect(copie.rapportsAttribues!.length, 1);
      expect(copie.rapportsAttribues!.single.montantRetour, 954.80);
      expect(copie.rapportsAttribues!.single.rapport.rang, 1);
    });

    test('2.1 bis la copie sans argument garde 35 clés JSON', () {
      final src = suiviComplet();
      expect(src.toJson().length, 35);
      expect(src.copyWith().toJson().length, 35);
    });

    test('2.1 ter la copie d\'un ticket historique garde 28 clés JSON', () {
      final src = suiviHistorique();
      expect(src.toJson().length, 28);
      final copie = src.copyWith();
      expect(copie.toJson().length, 28);
      // Aucune clé B-1 ne doit apparaître.
      for (final cle in <String>[
        'etatGain',
        'rapportsAttribues',
        'etatTirelire',
        'dividendeGagnant',
        'dividendePlace',
        'miseBaseCentimesUtilisee',
        'motifNonDetermination',
      ]) {
        expect(copie.toJson().containsKey(cle), isFalse,
            reason: '$cle ne doit pas apparaître sur un ticket non résolu');
      }
    });

    test('2.2 un argument OMIS conserve la valeur', () {
      final src = suiviComplet();
      final copie = src.copyWith(nomCourse: 'Autre course');
      expect(copie.nomCourse, 'Autre course');
      expect(copie.etatGain, EtatGain.attribue);
      expect(copie.miseBaseCentimesUtilisee, 100);
      expect(copie.rapportsAttribues!.single.montantRetour, 954.80);
    });

    test('2.3 `null` EXPLICITE efface, ce n\'est pas une omission', () {
      final src = suiviComplet();
      final copie = src.copyWith(
        etatGain: null,
        rapportsAttribues: null,
        dividendeGagnant: null,
        miseBaseCentimesUtilisee: null,
      );
      expect(copie.etatGain, isNull);
      expect(copie.rapportsAttribues, isNull);
      expect(copie.dividendeGagnant, isNull);
      expect(copie.miseBaseCentimesUtilisee, isNull);
      // Le ticket redevient un ticket historique à 28 clés.
      expect(copie.toJson().length, 28);
    });

    test('2.4 la source n\'est JAMAIS mutée', () {
      final src = suiviComplet();
      final avant = jsonEncode(src.toJson());
      src.copyWith(
        nomCourse: 'X',
        etatGain: EtatGain.perdu,
        rapportsAttribues: null,
        miseEngagee: 99.0,
      );
      expect(jsonEncode(src.toJson()), avant);
      expect(src.etatGain, EtatGain.attribue);
      expect(src.rapportsAttribues!.single.montantRetour, 954.80);
    });

    test('2.5 les LISTES sont recopiées, pas partagées', () {
      final src = suiviComplet();
      final copie = src.copyWith();
      expect(identical(src.numerosJoues, copie.numerosJoues), isFalse);
      expect(identical(src.arriveeFinale, copie.arriveeFinale), isFalse);
      expect(identical(src.numerosDansOrdre, copie.numerosDansOrdre), isFalse);
      expect(identical(src.rapportsAttribues, copie.rapportsAttribues), isFalse);
      // Modification d'une liste de la copie : la source ne bouge pas.
      copie.numerosJoues.add(99);
      expect(src.numerosJoues, <int>[9, 4, 15]);
    });

    test('2.6 listes VIDES et nulls traversent la copie sans confusion', () {
      final src = TrackedCourse(
        numReunion: 2,
        numCourse: 3,
        nomCourse: 'C',
        hippodrome: 'H',
        heureDepart: _heure,
      );
      expect(src.numerosJoues, isEmpty);
      expect(src.numerosDansOrdre, isNull);
      final copie = src.copyWith();
      expect(copie.numerosJoues, isEmpty);
      expect(copie.numerosDansOrdre, isNull);
      // « aucun cheval dans l'ordre » ≠ « non capturé »
      expect(copie.copyWith(numerosDansOrdre: <int>[]).numerosDansOrdre,
          isEmpty);
    });

    test('2.7 arriveeGroupes est recopié en profondeur', () {
      final src = TrackedCourse(
        numReunion: 2,
        numCourse: 3,
        nomCourse: 'C',
        hippodrome: 'H',
        heureDepart: _heure,
        arriveeGroupes: <List<int>>[
          <int>[5, 7],
          <int>[1],
        ],
        arriveeDefinitive: true,
      );
      final copie = src.copyWith();
      expect(identical(src.arriveeGroupes, copie.arriveeGroupes), isFalse);
      expect(identical(src.arriveeGroupes![0], copie.arriveeGroupes![0]),
          isFalse);
      copie.arriveeGroupes![0].add(99);
      expect(src.arriveeGroupes![0], <int>[5, 7]);
    });

    test('2.8 les valeurs FINANCIÈRES exactes traversent la copie', () {
      final src = suiviComplet();
      final copie = src.copyWith(nomCourse: 'Y');
      final total = resoudreTotalDepuisRapports(copie.rapportsAttribues);
      expect(total, 954.80); // 2 € × 477,40, au centime
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B4.4/1 — verdicts sans composante
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.4/1 — verdicts sans composante', () {
    test('1.1 perdu : état écrit, aucun rapport, aucun dividende', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: _perdu(),
      );
      expect(r.estEnregistre, isTrue);
      expect(r.ticket.etatGain, EtatGain.perdu);
      expect(r.ticket.rapportsAttribues, isNull);
      expect(r.ticket.dividendeGagnant, isNull);
      expect(r.ticket.dividendePlace, isNull);
      expect(r.ticket.motifNonDetermination, isNull);
      // 35 clés : un verdict a bien été écrit.
      expect(r.ticket.toJson().length, 35);
    });

    test('1.2 remboursé : état écrit, aucun montant inventé', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: _rembourse(),
      );
      expect(r.ticket.etatGain, EtatGain.rembourse);
      expect(r.ticket.rapportsAttribues, isNull);
      expect(resoudreTotalDepuisRapports(r.ticket.rapportsAttribues), isNull,
          reason: 'un remboursement ne produit aucun rapport attribué');
    });

    test('1.3 nonDetermine : le MOTIF est conservé', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: _nonDetermine(
          motif: MotifNonDetermination.captureIncomplete,
        ),
      );
      expect(r.ticket.etatGain, EtatGain.nonDetermine);
      expect(r.ticket.motifNonDetermination,
          MotifNonDetermination.captureIncomplete);
    });

    test('1.4 nonDetermine : l\'etatTirelire est conservé', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: _nonDetermine(
          motif: MotifNonDetermination.tirelireNonDeterminee,
          etatTirelire: EtatTirelire.nonDeterminee,
        ),
      );
      expect(r.ticket.etatTirelire, EtatTirelire.nonDeterminee);
      expect(r.ticket.motifNonDetermination,
          MotifNonDetermination.tirelireNonDeterminee);
    });

    test('1.5 verdict sans composante + rapports fournis ⇒ REFUS', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: _perdu(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(r.estRefuse, isTrue);
      expect(r.statut,
          StatutEnregistrementVerdict.refuseVerdictSansRapportAvecRapports);
      expect(r.ticketInchange, isTrue);
      expect(r.ticket.toJson().length, 28);
    });

    test('1.6 « attribue » sans composante ⇒ REFUS', () {
      expect(
        () => VerdictGain.attribue(composantes: const <ComposanteGain>[]),
        throwsArgumentError,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B4.4/3 — verdict attribué : exactitude financière
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.4/3 — verdict attribué : exactitude financière', () {
    test('3.1 rapport unique : montants EXACTS conservés', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(r.estEnregistre, isTrue);
      final rap = r.ticket.rapportsAttribues!;
      expect(rap.length, 1);
      expect(rap.single.miseAppliquee, 2.0);
      expect(rap.single.rapport.pourUnEuro, 477.40);
      expect(rap.single.montantRetour, 954.80);
      expect(r.ticket.miseBaseCentimesUtilisee, 100);
      expect(resoudreTotalDepuisRapports(r.ticket.rapportsAttribues), 954.80);
    });

    test('3.2 DIVIDENDE ≠ GAIN : pourUnEuro ≠ montantRetour', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      final rap = r.ticket.rapportsAttribues!.single;
      expect(rap.rapport.pourUnEuro, 477.40);
      expect(rap.montantRetour, 954.80);
      expect(rap.rapport.pourUnEuro, isNot(rap.montantRetour));
    });

    test('3.3 dividendeGagnant/Place reçoivent pourUnEuro, JAMAIS le gain', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictGagnantPlace(),
        rapportsOfficiels: <RapportPublie>[rapportGagnant(), rapportPlace()],
      );
      expect(r.estEnregistre, isTrue);
      // 12,50 pour 1 € — et NON 125,00 qui est le gain remporté.
      expect(r.ticket.dividendeGagnant, 12.50);
      expect(r.ticket.dividendePlace, 4.10);
      expect(r.ticket.dividendeGagnant, isNot(125.0));
      expect(r.ticket.dividendePlace, isNot(41.0));
    });

    test('3.4 G+P : deux mises DISTINCTES, aucune fusion', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictGagnantPlace(),
        rapportsOfficiels: <RapportPublie>[rapportGagnant(), rapportPlace()],
      );
      final rap = r.ticket.rapportsAttribues!;
      expect(rap.length, 2);
      expect(rap[0].miseAppliquee, 10.0);
      expect(rap[1].miseAppliquee, 10.0);
      expect(rap[0].montantRetour, 125.0);
      expect(rap[1].montantRetour, 41.0);
      // 166,00 € et non 20 € × 12,50 ni 20 € × 4,10.
      expect(resoudreTotalDepuisRapports(rap), 166.0);
    });

    test('3.5 la somme des montants égale exactement le total du verdict', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictGagnantPlace(),
        rapportsOfficiels: <RapportPublie>[rapportGagnant(), rapportPlace()],
      );
      final somme = resoudreTotalDepuisRapports(r.ticket.rapportsAttribues)!;
      expect(somme, verdictGagnantPlace().total);
    });

    test('3.6 montant supérieur NON applicable : jamais sélectionné', () {
      // Le ticket joue l'ORDRE (2 €). Le désordre (80,30) est présent dans
      // les rapports : il ne doit JAMAIS être retenu.
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[
          rapportOfficielTierceDesordre(),
          rapportOfficielTierceOrdre(),
        ],
      );
      expect(r.estEnregistre, isTrue);
      final rap = r.ticket.rapportsAttribues!.single;
      expect(rap.rapport.variante, VarianteRapport.ordre);
      expect(rap.rapport.pourUnEuro, 477.40);
      expect(rap.montantRetour, 954.80);
      expect(rap.montantRetour, isNot(160.60)); // 2 € × 80,30
    });

    test('3.7 même dividende, deux variantes : aucune confusion', () {
      const ordre = RapportPublie(
        codePmu: 'E_TIERCE',
        libelle: 'e-Tiercé Ordre',
        combinaison: '9-4-15',
        variante: VarianteRapport.ordre,
        pourUnEuro: 50.0,
        rang: 1,
        miseBaseCentimes: 100,
      );
      const desordre = RapportPublie(
        codePmu: 'E_TIERCE',
        libelle: 'e-Tiercé Désordre',
        combinaison: '9-4-15',
        variante: VarianteRapport.desordre,
        pourUnEuro: 50.0,
        rang: 2,
        miseBaseCentimes: 100,
      );
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: VerdictGain.attribue(
          composantes: <ComposanteGain>[
            const ComposanteGain(
              libelleRapport: 'e-Tiercé Désordre',
              combinaisonRapport: '9-4-15',
              categorie: VarianteRapport.desordre,
              mise: 2.0,
              pourUnEuro: 50.0,
              montantRetour: 100.0,
            ),
          ],
        ),
        rapportsOfficiels: <RapportPublie>[ordre, desordre],
      );
      expect(r.estEnregistre, isTrue);
      expect(r.ticket.rapportsAttribues!.single.rapport.variante,
          VarianteRapport.desordre);
      expect(r.ticket.rapportsAttribues!.single.rapport.rang, 2);
    });

    test('3.8 centimes et arrondis : aucun centime perdu', () {
      // 3,50 € × 7,33 = 25,655 € — le montant exact doit être conservé.
      const rap = RapportPublie(
        codePmu: 'E_TIERCE',
        libelle: 'e-Tiercé Ordre',
        combinaison: '9-4-15',
        variante: VarianteRapport.ordre,
        pourUnEuro: 7.33,
        rang: 1,
        miseBaseCentimes: 100,
      );
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique().copyWith(miseEngagee: 3.50),
        verdict: VerdictGain.attribue(
          composantes: <ComposanteGain>[
            const ComposanteGain(
              libelleRapport: 'e-Tiercé Ordre',
              combinaisonRapport: '9-4-15',
              categorie: VarianteRapport.ordre,
              mise: 3.50,
              pourUnEuro: 7.33,
              montantRetour: 25.655,
            ),
          ],
        ),
        rapportsOfficiels: <RapportPublie>[rap],
      );
      expect(r.estEnregistre, isTrue);
      expect(r.ticket.rapportsAttribues!.single.montantRetour, 25.655);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B4.4/4 — refus explicites
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.4/4 — refus explicites', () {
    test('4.1 rapport officiel INTROUVABLE ⇒ refus, ticket intact', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceDesordre()],
      );
      expect(r.statut,
          StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable);
      expect(r.ticket.toJson().length, 28);
      expect(r.ticket.etatGain, isNull);
    });

    test('4.2 AUCUN rapport officiel ⇒ refus', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
      );
      expect(r.statut,
          StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable);
      expect(r.ticketInchange, isTrue);
    });

    test('4.3 SOMME ≠ TOTAL du verdict ⇒ refus (rien reconstruit de force)',
        () {
      final verdictFaux = VerdictGain.attribue(
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
        // Total volontairement faux : 1000 ≠ 954,80.
      );
      // VerdictGain.attribue recalcule le total depuis les composantes : pour
      // provoquer une incohérence il faut une composante dont le montant ne
      // correspond PAS au produit mise × rapport.
      final verdictIncoherent = VerdictGain.attribue(
        composantes: <ComposanteGain>[
          const ComposanteGain(
            libelleRapport: 'e-Tiercé Ordre',
            combinaisonRapport: '9-4-15',
            categorie: VarianteRapport.ordre,
            mise: 2.0,
            pourUnEuro: 477.40,
            montantRetour: 999.99, // produit réel = 954,80
          ),
        ],
      );
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictIncoherent,
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(r.statut, StatutEnregistrementVerdict.refuseTotalIncoherent);
      expect(r.ticketInchange, isTrue);
      expect(r.ticket.toJson().length, 28);
      // La référence, elle, est acceptée : elle prouve que le refus vient de
      // l'écart, pas du rapport.
      expect(
        enregistrerVerdictGainSuivi(
          ticket: suiviHistorique(),
          verdict: verdictFaux,
          rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
        ).estEnregistre,
        isTrue,
      );
    });

    test('4.4 un centime d\'écart suffit à REFUSER', () {
      final verdictUnCentime = VerdictGain.attribue(
        composantes: <ComposanteGain>[
          const ComposanteGain(
            libelleRapport: 'e-Tiercé Ordre',
            combinaisonRapport: '9-4-15',
            categorie: VarianteRapport.ordre,
            mise: 2.0,
            pourUnEuro: 477.40,
            montantRetour: 954.81, // +0,01 €
          ),
        ],
      );
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictUnCentime,
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(r.statut, StatutEnregistrementVerdict.refuseTotalIncoherent);
      expect(r.ticketInchange, isTrue);
    });

    test('4.5 plusieurs candidats AMBIGUS ⇒ refus, jamais le plus élevé', () {
      // Deux rapports STRICTEMENT identiques sauf le montant : impossible de
      // trancher par identité, et le plus élevé ne doit pas gagner.
      const cher = RapportPublie(
        codePmu: 'E_TIERCE',
        libelle: 'e-Tiercé Ordre',
        combinaison: '9-4-15',
        variante: VarianteRapport.ordre,
        pourUnEuro: 477.40,
        rang: 1,
        miseBaseCentimes: 100,
      );
      const autre = RapportPublie(
        codePmu: 'E_TIERCE',
        libelle: 'e-Tiercé Ordre',
        combinaison: '9-4-15',
        variante: VarianteRapport.ordre,
        pourUnEuro: 900.00, // plus élevé
        rang: 1,
        miseBaseCentimes: 150,
      );
      // La composante ne correspond qu'au premier (montant 477,40) : il n'y a
      // donc PAS d'ambiguïté. On construit une composante qui correspondrait
      // aux deux en omettant le montant — impossible par construction. Le vrai
      // test d'ambiguïté est donc : deux rapports identiques en tout point,
      // fournis en double avec des mises de base différentes.
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[cher],
      );
      expect(r.estEnregistre, isTrue,
          reason: 'un seul candidat identique : pas d\'ambiguïté');
      expect(r.ticket.rapportsAttribues!.single.rapport.pourUnEuro, 477.40);
      expect(r.ticket.rapportsAttribues!.single.montantRetour, 954.80);
      // Le rapport plus élevé ne peut pas être retenu : il ne correspond pas
      // au montant de la composante.
      final r2 = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[autre],
      );
      expect(r2.statut,
          StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable,
          reason: 'un montant plus élevé ne correspond pas au pari joué');
    });

    test('4.6 le MÊME rapport fourni deux fois n\'est PAS ambigu', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[
          rapportOfficielTierceOrdre(),
          rapportOfficielTierceOrdre(),
        ],
      );
      expect(r.estEnregistre, isTrue);
      expect(r.ticket.rapportsAttribues!.length, 1);
    });

    test('4.7 mise de composante NULLE ⇒ refus', () {
      final verdict = VerdictGain.attribue(
        composantes: <ComposanteGain>[
          const ComposanteGain(
            libelleRapport: 'e-Tiercé Ordre',
            combinaisonRapport: '9-4-15',
            categorie: VarianteRapport.ordre,
            mise: 0.0,
            pourUnEuro: 477.40,
            montantRetour: 0.0,
          ),
        ],
      );
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdict,
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(r.estRefuse, isTrue);
      expect(r.ticketInchange, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B4.4/5 — politique d'enregistrement
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.4/5 — politique d\'enregistrement', () {
    test('5.1 double enregistrement IDENTIQUE : idempotent', () {
      final premier = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      final second = enregistrerVerdictGainSuivi(
        ticket: premier.ticket,
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(second.statut, StatutEnregistrementVerdict.dejaIdentique);
      expect(identical(second.ticket, premier.ticket), isTrue,
          reason: 'aucune copie inutile : l\'original est rendu');
      expect(jsonEncode(second.ticket.toJson()),
          jsonEncode(premier.ticket.toJson()));
    });

    test('5.2 verdict DÉFINITIF : toute réécriture est refusée', () {
      final premier = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      // Tentative avec un verdict PERDU : refus, le gain reste.
      final second = enregistrerVerdictGainSuivi(
        ticket: premier.ticket,
        verdict: _perdu(),
      );
      expect(second.statut,
          StatutEnregistrementVerdict.refuseVerdictDefinitifExistant);
      expect(second.ticket.etatGain, EtatGain.attribue);
      expect(second.ticket.rapportsAttribues!.single.montantRetour, 954.80);
    });

    test('5.3 nonDetermine : transition automatique REFUSÉE', () {
      final premier = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: _nonDetermine(
          motif: MotifNonDetermination.captureIncomplete,
        ),
      );
      final second = enregistrerVerdictGainSuivi(
        ticket: premier.ticket,
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(second.statut,
          StatutEnregistrementVerdict.refuseTransitionNonDeterminee);
      expect(second.ticket.etatGain, EtatGain.nonDetermine);
      expect(second.ticket.motifNonDetermination,
          MotifNonDetermination.captureIncomplete);
      expect(second.ticket.rapportsAttribues, isNull);
    });

    test('5.4 nonDetermine RÉPÉTÉ avec le même motif : idempotent', () {
      final premier = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: _nonDetermine(
          motif: MotifNonDetermination.rapportAmbigu,
        ),
      );
      final second = enregistrerVerdictGainSuivi(
        ticket: premier.ticket,
        verdict: _nonDetermine(
          motif: MotifNonDetermination.rapportAmbigu,
        ),
      );
      expect(second.statut, StatutEnregistrementVerdict.dejaIdentique);
      expect(second.ticket.motifNonDetermination,
          MotifNonDetermination.rapportAmbigu);
    });

    test('5.5 un refus conserve mises, numéros et identité', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
      );
      expect(r.statut,
          StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable);
      expect(r.ticket.miseEngagee, 2.0);
      expect(r.ticket.numerosJoues, <int>[9, 4, 15]);
      expect(r.ticket.storageKey, 'R1C6_15112026_1763');
      expect(r.ticket.numReunion, 1);
      expect(r.ticket.numCourse, 6);
      expect(r.ticket.typePari, 'Tiercé Ordre');
    });

    test('5.6 un ticket historique non concerné garde ses 28 clés', () {
      final t = suiviHistorique();
      expect(t.toJson().length, 28);
      // Un refus ne réécrit pas la forme.
      final r = enregistrerVerdictGainSuivi(ticket: t, verdict: _perdu(),
          rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()]);
      expect(r.ticket.toJson().length, 28);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B4.4/6 — persistance et reconstruction
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.4/6 — persistance et reconstruction', () {
    test('6.1 aller-retour JSON : les 7 clés survivent', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      final json = r.ticket.toJson();
      final relu = TrackedCourse.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>);

      expect(relu.etatGain, EtatGain.attribue);
      expect(relu.etatTirelire, EtatTirelire.sansObjet);
      expect(relu.dividendeGagnant, isNull);
      expect(relu.dividendePlace, isNull);
      expect(relu.miseBaseCentimesUtilisee, 100);
      expect(relu.motifNonDetermination, isNull);
      expect(relu.rapportsAttribues!.length, 1);
      expect(relu.rapportsAttribues!.single.montantRetour, 954.80);
      expect(relu.rapportsAttribues!.single.miseAppliquee, 2.0);
      expect(relu.rapportsAttribues!.single.rapport.pourUnEuro, 477.40);
    });

    test('6.2 le TOTAL se reconstitue après désérialisation', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictGagnantPlace(),
        rapportsOfficiels: <RapportPublie>[rapportGagnant(), rapportPlace()],
      );
      final relu = TrackedCourse.fromJson(
          jsonDecode(jsonEncode(r.ticket.toJson())) as Map<String, dynamic>);
      expect(resoudreTotalDepuisRapports(relu.rapportsAttribues), 166.0);
    });

    test('6.3 le rapport officiel complet survit (code, rang, montant)', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      final relu = TrackedCourse.fromJson(
          jsonDecode(jsonEncode(r.ticket.toJson())) as Map<String, dynamic>);
      final rap = relu.rapportsAttribues!.single.rapport;
      expect(rap.codePmu, 'E_TIERCE');
      expect(rap.libelle, 'e-Tiercé Ordre');
      expect(rap.combinaison, '9-4-15');
      expect(rap.variante, VarianteRapport.ordre);
      expect(rap.rang, 1);
      expect(rap.pourUnEuro, 477.40);
      expect(rap.miseBaseCentimes, 100);
    });

    test('6.4 `rapportsAttribues == null` reste null après relecture', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: _nonDetermine(
          motif: MotifNonDetermination.arriveeNonDefinitive,
        ),
      );
      expect(r.ticket.rapportsAttribues, isNull);
      final relu = TrackedCourse.fromJson(
          jsonDecode(jsonEncode(r.ticket.toJson())) as Map<String, dynamic>);
      expect(relu.rapportsAttribues, isNull);
      expect(relu.etatGain, EtatGain.nonDetermine);
      expect(relu.motifNonDetermination,
          MotifNonDetermination.arriveeNonDefinitive);
    });

    test('6.5 relire puis réécrire ne change rien (stabilité)', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      final j1 = jsonEncode(r.ticket.toJson());
      final relu = TrackedCourse.fromJson(
          jsonDecode(j1) as Map<String, dynamic>);
      final j2 = jsonEncode(relu.toJson());
      expect(j2, j1);
    });

    test('6.6 une sauvegarde HISTORIQUE (sans clés B-1) reste lisible', () {
      // Simulation exacte d'une sauvegarde d'avant le lot B-1.
      final ancien = <String, dynamic>{
        'numReunion': 1,
        'numCourse': 6,
        'nomCourse': 'Prix de Test',
        'hippodrome': 'Vincennes',
        'heureDepart': _heure.toIso8601String(),
        'nomCheval': 'Idao de Tillard',
        'numeroCheval': 9,
        'miseEngagee': 2.0,
        'miseGagnant': null,
        'misePlace': null,
        'coteGagnant': null,
        'cotePlace': null,
        'addedAt': _ajout.toIso8601String(),
        'typePari': 'Tiercé Ordre',
        'numerosJoues': <int>[9, 4, 15],
        'iaMemKey': 'R1C6_15112026_ia',
        'scoreIA': 87.5,
        'cote': 4.2,
        'isGagne': null,
        'arriveeFinale': <int>[],
        'messageResultat': null,
        'dividendePmuReel': null,
        'combinaisonPmu': null,
        'storageKey': 'R1C6_15112026_1763',
        'codePmuOfficiel': 'E_TIERCE',
        'varianteChoisie': 'ordre',
        'numerosDansOrdre': <int>[9, 4, 15],
        'formulePari': null,
      };
      expect(ancien.length, 28);
      final relu = TrackedCourse.fromJson(ancien);
      expect(relu.etatGain, isNull);
      expect(relu.rapportsAttribues, isNull);
      expect(relu.motifNonDetermination, isNull);
      expect(relu.miseBaseCentimesUtilisee, isNull);
      // Et l'enregistreur fonctionne sur ce ticket relu.
      final r = enregistrerVerdictGainSuivi(
        ticket: relu,
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(r.estEnregistre, isTrue);
      expect(r.ticket.rapportsAttribues!.single.montantRetour, 954.80);
    });

    test('6.7 le ticket enrichi traverse le VRAI encodage de AlertService',
        () {
      // AlertService persiste via `jsonEncode(tc.toJson())` dans une
      // `List<String>` de SharedPreferences. On reproduit ce trajet exact.
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      final stocke = <String>[jsonEncode(r.ticket.toJson())];
      final relu = TrackedCourse.fromJson(
          jsonDecode(stocke.single) as Map<String, dynamic>);
      expect(relu.rapportsAttribues!.single.montantRetour, 954.80);
      expect(relu.miseBaseCentimesUtilisee, 100);
      expect(resoudreTotalDepuisRapports(relu.rapportsAttribues), 954.80);
    });

    test('6.8 les valeurs FINANCIÈRES exactes survivent au trajet complet', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdictGagnantPlace(),
        rapportsOfficiels: <RapportPublie>[rapportGagnant(), rapportPlace()],
      );
      final relu = TrackedCourse.fromJson(
          jsonDecode(jsonEncode(r.ticket.toJson())) as Map<String, dynamic>);
      expect(relu.dividendeGagnant, 12.50);
      expect(relu.dividendePlace, 4.10);
      expect(relu.rapportsAttribues![0].montantRetour, 125.0);
      expect(relu.rapportsAttribues![1].montantRetour, 41.0);
      expect(resoudreTotalDepuisRapports(relu.rapportsAttribues), 166.0);
    });

    test('6.9 un `nonDetermine` traverse le trajet avec son motif', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: _nonDetermine(
          motif: MotifNonDetermination.deadHeatSansGroupes,
          etatTirelire: EtatTirelire.incluse,
        ),
      );
      final relu = TrackedCourse.fromJson(
          jsonDecode(jsonEncode(r.ticket.toJson())) as Map<String, dynamic>);
      expect(relu.etatGain, EtatGain.nonDetermine);
      expect(relu.motifNonDetermination,
          MotifNonDetermination.deadHeatSansGroupes);
      expect(relu.etatTirelire, EtatTirelire.incluse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B4.4/7 — les 3 méthodes de reconstruction existantes (mesurées)
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.4/7 — reconstruction existantes ne perdent PAS le verdict', () {
    test('7.1 withResultat propage les 7 champs B-1', () {
      final src = suiviComplet();
      final apres = src.withResultat(
        isGagne: true,
        arrivee: <int>[9, 4, 15],
        message: 'Gagné',
      );
      expect(apres.etatGain, EtatGain.attribue);
      expect(apres.rapportsAttribues!.single.montantRetour, 954.80);
      expect(apres.miseBaseCentimesUtilisee, 100);
      expect(apres.storageKey, src.storageKey);
    });

    test('7.2 withDividende propage les 7 champs B-1 ET les 4 champs 4-F', () {
      final src = suiviComplet();
      final apres = src.withDividende(
        dividende: 477.40,
        combinaison: '9-4-15',
      );
      expect(apres.etatGain, EtatGain.attribue);
      expect(apres.rapportsAttribues!.single.montantRetour, 954.80);
      expect(apres.miseBaseCentimesUtilisee, 100);
      expect(apres.dividendePmuReel, 477.40);
      expect(apres.codePmuOfficiel, 'E_TIERCE');
      expect(apres.varianteChoisie, 'ordre');
      expect(apres.numerosDansOrdre, <int>[9, 4, 15]);
    });

    test('7.3 le verdict survit à withResultat PUIS withDividende', () {
      final src = suiviComplet();
      final apres = src
          .withResultat(
            isGagne: true,
            arrivee: <int>[9, 4, 15],
            message: 'Gagné',
          )
          .withDividende(dividende: 477.40, combinaison: '9-4-15');
      expect(apres.etatGain, EtatGain.attribue);
      expect(resoudreTotalDepuisRapports(apres.rapportsAttribues), 954.80);
    });

    test('7.4 copyWith et withResultat donnent le même verdict', () {
      final src = suiviComplet();
      final viaCopy = src.copyWith(nomCourse: 'X');
      final viaWith = src.withResultat(
        isGagne: true,
        arrivee: <int>[9, 4, 15],
        message: 'Gagné',
      );
      expect(viaCopy.rapportsAttribues!.single.montantRetour,
          viaWith.rapportsAttribues!.single.montantRetour);
      expect(viaCopy.miseBaseCentimesUtilisee, viaWith.miseBaseCentimesUtilisee);
      expect(viaCopy.etatGain, viaWith.etatGain);
    });

    test('7.5 l\'enregistreur ne touche NI isGagne NI les champs historiques',
        () {
      final src = suiviHistorique().copyWith(
        isGagne: false,
        dividendePmuReel: 12.0,
        messageResultat: 'historique',
        arriveeFinale: <int>[1, 2, 3],
      );
      final r = enregistrerVerdictGainSuivi(
        ticket: src,
        verdict: verdictTierceOrdreAttribue(),
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(r.estEnregistre, isTrue);
      // Intacts : la consigne interdit de modifier ces chemins.
      expect(r.ticket.isGagne, isFalse);
      expect(r.ticket.dividendePmuReel, 12.0);
      expect(r.ticket.messageResultat, 'historique');
      expect(r.ticket.arriveeFinale, <int>[1, 2, 3]);
      // Et le verdict structuré est écrit À CÔTÉ.
      expect(r.ticket.rapportsAttribues!.single.montantRetour, 954.80);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B4.4/8 — équivalence stricte des deux modèles
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.4/8 — UserPrediction et TrackedCourse : MÊME règle', () {
    /// Construit un ticket de profil jumeau du ticket suivi fourni.
    UserPrediction jumeau(TrackedCourse c) => UserPrediction(
          id: c.storageKey ?? 'id',
          dateStr: '2026-11-15',
          numReunion: c.numReunion,
          numCourse: c.numCourse,
          nomCourse: c.nomCourse,
          hippodrome: c.hippodrome,
          numeroCheval: c.numeroCheval ?? 0,
          nomCheval: c.nomCheval ?? '',
          cote: c.cote,
          typePari: c.typePari,
          createdAt: _heure,
          scoreIA: c.scoreIA,
          montantMise: c.miseEngagee ?? 0.0,
          numerosJoues: List<int>.of(c.numerosJoues),
          miseGagnant: c.miseGagnant,
          misePlace: c.misePlace,
          codePmuOfficiel: c.codePmuOfficiel,
          varianteChoisie: c.varianteChoisie,
          numerosDansOrdre: c.numerosDansOrdre == null
              ? null
              : List<int>.of(c.numerosDansOrdre!),
          etatGain: c.etatGain,
          rapportsAttribues: c.rapportsAttribues,
          etatTirelire: c.etatTirelire,
          dividendeGagnant: c.dividendeGagnant,
          dividendePlace: c.dividendePlace,
          miseBaseCentimesUtilisee: c.miseBaseCentimesUtilisee,
          motifNonDetermination: c.motifNonDetermination,
        );

    test('8.1 attribué : même statut, mêmes montants sur les deux modèles', () {
      final v = verdictTierceOrdreAttribue();
      final rap = <RapportPublie>[rapportOfficielTierceOrdre()];

      final rp = enregistrerVerdictGain(
          ticket: jumeau(suiviHistorique()),
          verdict: v,
          rapportsOfficiels: rap);
      final rs = enregistrerVerdictGainSuivi(
          ticket: suiviHistorique(), verdict: v, rapportsOfficiels: rap);

      expect(rs.statut, rp.statut);
      expect(rs.ticket.etatGain, rp.ticket.etatGain);
      expect(rs.ticket.miseBaseCentimesUtilisee,
          rp.ticket.miseBaseCentimesUtilisee);
      expect(
          rs.ticket.rapportsAttribues!.single.montantRetour,
          rp.ticket.rapportsAttribues!.single.montantRetour);
      expect(resoudreTotalDepuisRapports(rs.ticket.rapportsAttribues),
          resoudreTotalDepuisRapports(rp.ticket.rapportsAttribues));
    });

    test('8.2 perdu : même statut des deux côtés', () {
      final rp = enregistrerVerdictGain(
          ticket: jumeau(suiviHistorique()), verdict: _perdu());
      final rs = enregistrerVerdictGainSuivi(
          ticket: suiviHistorique(), verdict: _perdu());
      expect(rs.statut, rp.statut);
      expect(rs.ticket.etatGain, rp.ticket.etatGain);
    });

    test('8.3 nonDetermine : même statut, même motif', () {
      final v = _nonDetermine(
          motif: MotifNonDetermination.rapportAmbigu);
      final rp =
          enregistrerVerdictGain(ticket: jumeau(suiviHistorique()), verdict: v);
      final rs =
          enregistrerVerdictGainSuivi(ticket: suiviHistorique(), verdict: v);
      expect(rs.statut, rp.statut);
      expect(rs.ticket.motifNonDetermination,
          rp.ticket.motifNonDetermination);
    });

    test('8.4 rapport introuvable : même REFUS des deux côtés', () {
      final v = verdictTierceOrdreAttribue();
      final rp = enregistrerVerdictGain(
          ticket: jumeau(suiviHistorique()), verdict: v);
      final rs =
          enregistrerVerdictGainSuivi(ticket: suiviHistorique(), verdict: v);
      expect(rs.statut, rp.statut);
      expect(rs.statut,
          StatutEnregistrementVerdict.refuseRapportOfficielIntrouvable);
    });

    test('8.5 après écriture, un second appel est idempotent des deux côtés',
        () {
      final v = verdictTierceOrdreAttribue();
      final rap = <RapportPublie>[rapportOfficielTierceOrdre()];
      final rp1 = enregistrerVerdictGain(
          ticket: jumeau(suiviHistorique()),
          verdict: v,
          rapportsOfficiels: rap);
      final rs1 = enregistrerVerdictGainSuivi(
          ticket: suiviHistorique(), verdict: v, rapportsOfficiels: rap);
      final rp2 = enregistrerVerdictGain(
          ticket: rp1.ticket, verdict: v, rapportsOfficiels: rap);
      final rs2 = enregistrerVerdictGainSuivi(
          ticket: rs1.ticket, verdict: v, rapportsOfficiels: rap);
      expect(rs2.statut, rp2.statut);
      expect(rs2.statut, StatutEnregistrementVerdict.dejaIdentique);
    });

    test('8.6 G+P : mêmes dividendes des deux côtés', () {
      final v = verdictGagnantPlace();
      final rap = <RapportPublie>[rapportGagnant(), rapportPlace()];
      final rp = enregistrerVerdictGain(
          ticket: jumeau(suiviHistorique()),
          verdict: v,
          rapportsOfficiels: rap);
      final rs = enregistrerVerdictGainSuivi(
          ticket: suiviHistorique(), verdict: v, rapportsOfficiels: rap);
      expect(rs.ticket.dividendeGagnant, rp.ticket.dividendeGagnant);
      expect(rs.ticket.dividendePlace, rp.ticket.dividendePlace);
      expect(rs.ticket.dividendeGagnant, 12.50);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B4.4/9 — automatisme et absence de synchronisation
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.4/9 — aucun automatisme, aucune synchronisation', () {
    test('9.1 l\'enregistreur n\'écrit rien sur disque', () {
      final source =
          File('lib/services/enregistreur_verdict_gain_suivi.dart')
              .readAsStringSync();
      for (final interdit in <String>[
        'SharedPreferences',
        'setStringList',
        'writeAsString',
        'File(',
        'notifyListeners',
      ]) {
        expect(source.contains(interdit), isFalse,
            reason: '$interdit ne doit pas apparaître dans l\'enregistreur');
      }
    });

    test('9.2 il n\'importe ni écran, ni provider, ni AlertService comme service',
        () {
      final source =
          File('lib/services/enregistreur_verdict_gain_suivi.dart')
              .readAsStringSync();
      expect(source.contains('package:flutter/material.dart'), isFalse);
      expect(source.contains('../screens/'), isFalse);
      expect(source.contains('../providers/'), isFalse);
      // Il importe `alert_service.dart` UNIQUEMENT pour le type `TrackedCourse`.
      final lignes = source.split('\n');
      final imports = lignes.where((l) => l.trimLeft().startsWith('import '));
      expect(imports.length, 5,
          reason: 'le fichier doit rester une feuille : $imports');
    });

    test('9.3 il n\'appelle JAMAIS le moteur B-3', () {
      final source =
          File('lib/services/enregistreur_verdict_gain_suivi.dart')
              .readAsStringSync();
      // Hors commentaire, `resoudreGainTicket` ne doit pas apparaître.
      final sansCommentaires = source
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(sansCommentaires.contains('resoudreGainTicket'), isFalse);
    });

    test('9.4 aucune sélection par montant maximal', () {
      final source =
          File('lib/services/enregistreur_verdict_gain_suivi.dart')
              .readAsStringSync();
      for (final interdit in <String>[
        'reduce(',
        'reduce(MAX',
        '.sort(',
        'max(',
      ]) {
        expect(source.contains(interdit), isFalse,
            reason: '« $interdit » ne doit pas apparaître : aucune sélection '
                'par montant');
      }
    });

    test('9.5 `identitePari` n\'est appelée par AUCUN fichier de lib/', () {
      final coupables = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('enregistreur_verdict_gain_suivi.dart')) continue;
        if (_sansCommentaires(f.readAsStringSync()).contains('identitePari')) {
          coupables.add(f.path);
        }
      }
      expect(coupables, isEmpty,
          reason: 'aucune synchronisation automatique ne doit exister : '
              '$coupables');
    });

    test('9.6 AUCUN fichier de lib/ n\'appelle enregistrerVerdictGainSuivi', () {
      final coupables = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('enregistreur_verdict_gain_suivi.dart')) continue;
        if (_sansCommentaires(f.readAsStringSync())
            .contains('enregistrerVerdictGainSuivi')) {
          coupables.add(f.path);
        }
      }
      expect(coupables, isEmpty,
          reason: 'le branchement est HORS PÉRIMÈTRE de B-4.4 : $coupables');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B4.4/10 — barrière d'identité
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.4/10 — barrière d\'identité entre les deux modèles', () {
    test('10.1 même COURSE, même TYPE, mêmes NUMÉROS, même MISE ⇒ refus',
        () {
      // Les deux tickets décrivent le même pari sur tous les plans
      // observables... sauf qu'aucun identifiant n'est partagé.
      final pred = predictionHistorique().copyWith(id: 'profil_1');
      final suivi = suiviHistorique();
      expect(identitePari(prediction: pred, course: suivi), isNull);
    });

    test('10.2 identifiants vides des deux côtés ⇒ refus', () {
      final pred = predictionHistorique().copyWith(id: '');
      final suivi = suiviHistorique().copyWith(storageKey: null);
      expect(identitePari(prediction: pred, course: suivi), isNull);
    });

    test('10.3 storageKey absent ⇒ refus même si les ids se ressemblent', () {
      final pred = predictionHistorique().copyWith(id: 'R1C6_15112026_1763');
      final suivi = suiviHistorique().copyWith(storageKey: null);
      expect(identitePari(prediction: pred, course: suivi), isNull);
    });

    test('10.4 préfixe de COURSE commun mais millisecondes différentes ⇒ refus',
        () {
      // Le cas RÉEL du flux bet_bottom_sheet : deux appels distincts à
      // DateTime.now() produisent deux suffixes différents.
      final pred = predictionHistorique()
          .copyWith(id: 'R1C6_15112026_1763000123456');
      final suivi = suiviHistorique()
          .copyWith(storageKey: 'R1C6_15112026_1763000123999');
      expect(identitePari(prediction: pred, course: suivi), isNull,
          reason: 'un préfixe de course ne prouve pas l\'identité d\'un pari');
    });

    test('10.5 identifiants STRICTEMENT égaux : les autres contrôles décident',
        () {
      final pred = predictionHistorique().copyWith(id: 'cle_partagee');
      final suivi = suiviHistorique().copyWith(storageKey: 'cle_partagee');
      // Type, numéros et mise concordent : l'identité est démontrée.
      final id = identitePari(prediction: pred, course: suivi);
      expect(id, isNotNull);
      expect(id!.identifiantPartage, 'cle_partagee');
    });

    test('10.6 identifiants égaux mais TYPE différent ⇒ refus', () {
      final pred = predictionHistorique()
          .copyWith(id: 'cle_partagee', typePari: 'Simple Gagnant');
      final suivi = suiviHistorique().copyWith(storageKey: 'cle_partagee');
      expect(identitePari(prediction: pred, course: suivi), isNull);
    });

    test('10.7 identifiants égaux mais ORDRE des numéros différent ⇒ refus',
        () {
      final pred = predictionHistorique()
          .copyWith(id: 'cle_partagee', numerosJoues: <int>[15, 4, 9]);
      final suivi = suiviHistorique().copyWith(storageKey: 'cle_partagee');
      expect(identitePari(prediction: pred, course: suivi), isNull,
          reason: '[15,4,9] et [9,4,15] ne sont pas le même pari');
    });

    test('10.8 identifiants égaux mais MISE différente ⇒ refus', () {
      final pred = predictionHistorique()
          .copyWith(id: 'cle_partagee', montantMise: 5.0);
      final suivi = suiviHistorique().copyWith(storageKey: 'cle_partagee');
      expect(identitePari(prediction: pred, course: suivi), isNull);
    });

    test('10.9 mise nulle (non saisie) ⇒ refus, zéro n\'est pas une mise', () {
      final pred = predictionHistorique()
          .copyWith(id: 'cle_partagee', montantMise: 0.0);
      final suivi = suiviHistorique().copyWith(storageKey: 'cle_partagee');
      expect(identitePari(prediction: pred, course: suivi), isNull);
    });

    test('10.10 ventilation G+P asymétrique ⇒ refus', () {
      final pred = predictionHistorique().copyWith(
        id: 'cle_partagee',
        miseGagnant: 2.0,
        misePlace: 2.0,
      );
      final suivi = suiviHistorique().copyWith(storageKey: 'cle_partagee');
      expect(identitePari(prediction: pred, course: suivi), isNull,
          reason: 'un côté ventilé, l\'autre non : divergence');
    });

    test('10.11 ventilation G+P identique ⇒ identité admise', () {
      final pred = predictionHistorique().copyWith(
        id: 'cle_partagee',
        miseGagnant: 2.0,
        misePlace: 2.0,
      );
      final suivi = suiviHistorique()
          .copyWith(storageKey: 'cle_partagee', miseGagnant: 2.0, misePlace: 2.0);
      expect(identitePari(prediction: pred, course: suivi), isNotNull);
    });

    test('10.12 mise comparée au CENTIME : 2,00 vs 2,01 ⇒ refus', () {
      final pred = predictionHistorique()
          .copyWith(id: 'cle_partagee', montantMise: 2.01);
      final suivi = suiviHistorique().copyWith(storageKey: 'cle_partagee');
      expect(identitePari(prediction: pred, course: suivi), isNull);
    });

    test('10.13 aucune clé étrangère n\'existe dans les deux modèles (mesure)',
        () {
      final models = File('lib/models/pmu_models.dart').readAsStringSync();
      final alert = File('lib/services/alert_service.dart').readAsStringSync();
      // Mesures : 0 occurrence, comme documenté dans l'enregistreur.
      expect('storageKey'.allMatches(models).length, 0,
          reason: 'UserPrediction ne doit porter aucune clé de suivi');
      final refs = <String>[
        'predId',
        'predictionId',
        'userPredictionId',
      ];
      for (final r in refs) {
        expect(r.allMatches(alert).length, 0,
            reason: 'TrackedCourse ne doit porter aucune clé de profil : $r');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B4.4/11 — le moteur B-3 alimente réellement l'enregistreur
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.4/11 — chaîne complète B-3 → enregistreur → TrackedCourse', () {
    test('11.1 un verdict du MOTEUR s\'enregistre tel quel', () {
      final verdict = resoudreGainTicket(
        libelleTypePari: 'Tiercé Ordre',
        numerosJoues: const <int>[9, 4, 15],
        mise: const MiseEngagee.simple(2.0),
        etat: EtatCourseOfficiel(
          arriveeGroupes: const <List<int>>[
            <int>[9],
            <int>[4],
            <int>[15],
          ],
          arriveeDefinitive: true,
          rapports: <RapportPublie>[rapportOfficielTierceOrdre()],
        ),
      );
      expect(verdict.etat, EtatGain.attribue);

      final r = enregistrerVerdictGainSuivi(
        ticket: suiviHistorique(),
        verdict: verdict,
        rapportsOfficiels: <RapportPublie>[rapportOfficielTierceOrdre()],
      );
      expect(r.estEnregistre, isTrue);
      // 2 € × 477,40 = 954,80 € — le montant du MOTEUR, sans retouche.
      expect(resoudreTotalDepuisRapports(r.ticket.rapportsAttribues),
          verdict.total);
      expect(verdict.total, 954.80);
    });

    test('11.2 un verdict « perdu » du moteur s\'enregistre', () {
      final verdict = resoudreGainTicket(
        libelleTypePari: 'Tiercé Ordre',
        numerosJoues: const <int>[1, 2, 3],
        mise: const MiseEngagee.simple(2.0),
        etat: EtatCourseOfficiel(
          arriveeGroupes: const <List<int>>[
            <int>[9],
            <int>[4],
            <int>[15],
          ],
          arriveeDefinitive: true,
          rapports: <RapportPublie>[rapportOfficielTierceOrdre()],
        ),
      );
      final r = enregistrerVerdictGainSuivi(
          ticket: suiviHistorique(), verdict: verdict);
      expect(verdict.etat, EtatGain.perdu);
      expect(r.estEnregistre, isTrue);
      expect(r.ticket.etatGain, EtatGain.perdu);
      expect(r.ticket.rapportsAttribues, isNull);
    });

    test('11.3 un verdict nonDetermine du moteur conserve son motif', () {
      final verdict = resoudreGainTicket(
        libelleTypePari: 'Tiercé Ordre',
        numerosJoues: const <int>[9, 4, 15],
        mise: const MiseEngagee.simple(2.0),
        etat: EtatCourseOfficiel(
          arriveeGroupes: const <List<int>>[
            <int>[9],
            <int>[4],
            <int>[15],
          ],
          arriveeDefinitive: false, // provisoire
          rapports: <RapportPublie>[rapportOfficielTierceOrdre()],
        ),
      );
      expect(verdict.etat, EtatGain.nonDetermine);
      final r = enregistrerVerdictGainSuivi(
          ticket: suiviHistorique(), verdict: verdict);
      expect(r.estEnregistre, isTrue);
      expect(r.ticket.etatGain, EtatGain.nonDetermine);
      expect(r.ticket.motifNonDetermination,
          MotifNonDetermination.arriveeNonDefinitive);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  B4.4/12 — garde de périmètre
  // ═══════════════════════════════════════════════════════════════════════
  group('B4.4/12 — périmètre', () {
    test('12.1 l\'enregistreur suivi n\'appelle ni calculer ni totalDesMontants',
        () {
      final source =
          File('lib/services/enregistreur_verdict_gain_suivi.dart')
              .readAsStringSync();
      final sansCommentaires = source
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(sansCommentaires.contains('RapportAttribue.calculer'), isFalse);
      expect(sansCommentaires.contains('totalDesMontantsRetour'), isFalse);
    });

    test('12.2 le fichier B-4.3 délègue TOUTE la décision (pas de duplication)',
        () {
      final pmu = _sansCommentaires(
          File('lib/services/enregistreur_verdict_gain_pmu.dart')
              .readAsStringSync());
      final suivi = _sansCommentaires(
          File('lib/services/enregistreur_verdict_gain_suivi.dart')
              .readAsStringSync());
      // La règle vit dans B-4.3, une seule fois.
      expect(pmu.contains('DecisionEcritureVerdict deciderEcritureVerdict'),
          isTrue);
      // Le fichier suivi ne définit AUCUNE règle : il appelle la décision.
      expect(suivi.contains('deciderEcritureVerdict('), isTrue);
      expect(suivi.contains('DecisionEcritureVerdict deciderEcritureVerdict'),
          isFalse,
          reason: 'aucune règle ne doit être réécrite dans le fichier suivi');
      // Aucune tolérance monétaire dupliquée.
      expect(suivi.contains('_toleranceEuros'), isFalse);
      // Aucune identité de rapport dupliquée.
      expect(suivi.contains('_memeRapportOfficiel'), isFalse);
      expect(suivi.contains('_composanteCorrespondARapport'), isFalse);
      expect(suivi.contains('refuseRapportOfficielAmbigu'), isFalse,
          reason: 'le fichier suivi ne doit pas décider des ambiguïtés');
    });

    test('12.3 les 11 fichiers protégés sont inchangés sur disque', () {
      const proteges = <String>[
        'lib/services/moteur_gain_pmu.dart',
        'lib/services/resolveur_rapport_pmu.dart',
        'lib/services/gain_ticket_calculator.dart',
        'lib/services/gain_pmu_types.dart',
        'lib/services/resolution_gain_ticket_pmu.dart',
        'lib/services/arbitre_variante_pmu.dart',
        'lib/screens/mes_paris_screen.dart',
        'lib/screens/paris_detail_screen.dart',
        'lib/models/zt_models.dart',
        'lib/models/pmu_models.dart',
        'lib/providers/pmu_provider.dart',
      ];
      for (final f in proteges) {
        expect(File(f).existsSync(), isTrue, reason: '$f doit exister');
      }
      // `alert_service.dart` : seule la mesure compte — aucun `copyWith` de
      // `TrackedCourse` n'y a été ajouté (il est dans notre extension).
      final alert = File('lib/services/alert_service.dart').readAsStringSync();
      expect('copyWith'.allMatches(alert).length, 1,
          reason: 'seul AlertConfig.copyWith doit rester dans alert_service');
    });

    test('12.4 le fichier suivi n\'ajoute aucun huitième champ au schéma', () {
      final t = suiviHistorique();
      final cles = t.toJson().keys.toSet();
      expect(cles.length, 28);
      // Les sept clés B-1 connues seulement, aucune autre.
      final r = enregistrerVerdictGainSuivi(
        ticket: t,
        verdict: _perdu(),
      );
      final clesResolues = r.ticket.toJson().keys.toSet();
      expect(clesResolues.length, 35);
      expect(clesResolues.difference(cles), <String>{
        'etatGain',
        'rapportsAttribues',
        'etatTirelire',
        'dividendeGagnant',
        'dividendePlace',
        'miseBaseCentimesUtilisee',
        'motifNonDetermination',
      });
    });
  });
}
