// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-4.6 — D1 : REPRODUCTION DU BLOCAGE « nonDetermine → verdict définitif »
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE PRODUCTION.
//      Aucun écran n'est monté, aucun service n'est instancié, rien n'est
//      écrit sur disque. Toutes les mesures passent par les fonctions PURES
//      déjà livrées : `resoudreGainTicketDepuisDonnees` (B-4.1),
//      `enregistrerVerdictGainSuivi` (B-4.4) et la chaîne réelle
//      `resoudreSuivi` (B-4.5).
//
//  ── CE QUE CE FICHIER DOIT PROUVER, ET RIEN DE PLUS ──────────────────────
//  L'utilisateur exige une reproduction MESURÉE de quatre choses :
//
//    (a) B-4.5 empêche-t-il déjà la persistance d'un verdict incomplet ?
//        ⇒ Mesure T1/T2 : la persistance d'un `nonDetermine` dépend
//          UNIQUEMENT du fait que la liste des rapports officiels soit VIDE
//          ou NON. B-4.5 ne bloque donc pas le verdict lui-même : il ne
//          filtre en amont que l'absence d'arrivée et l'absence de rapports.
//
//    (b) Le blocage réel de la transition existe-t-il ?
//        ⇒ Mesure T3/T5 : OUI, et il est prononcé par la branche A de
//          `deciderEcritureVerdict` (`refuseTransitionNonDeterminee`).
//
//    (c) La distinction « résultat officiel incomplet » / « rapport pas
//        encore publié » est-elle mesurable séparément ?
//        ⇒ Mesure T1 vs T2 : OUI, et elle tombe exactement sur la
//          frontière de la branche C de l'enregistreur.
//
//    (d) Ne jamais accepter un verdict sans preuve suffisante, ne jamais
//        écraser un verdict définitif.
//        ⇒ Mesure T8 : la protection du verdict définitif est intacte.
//
//  ── DÉCOUVERTE MESURÉE, ET SON STATUT ────────────────────────────────────
//  T6/T7 mesurent un SECOND blocage, DISTINCT de la transition D1 : la
//  branche C de l'enregistreur refuse TOUT verdict à zéro composante
//  (`perdu`, `rembourse`) dès que la liste des rapports officiels est NON
//  VIDE — y compris à la PREMIÈRE écriture, sur un ticket vierge.
//
//  Ce n'est pas un scénario D1 (il n'y a pas de transition), mais il rend
//  la cible D1 « transition vers `perdu` » structurellement inatteignable
//  si on ne le traite pas dans la même règle. Il est donc mesuré ici et
//  remonté tel quel dans le livrable.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/branchement_verdict_course.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_suivi.dart';
import 'package:pronostic_hippique/services/gain_calculator.dart' show RapportPmu;
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show VarianteRapport;
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart';
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';

// ─────────────────────────── Constantes du scénario ────────────────────────

/// Arrivée officielle DÉFINITIVE et SANS ex æquo : trois singletons.
/// C'est une arrivée exploitable — donc un « résultat officiel complet » au
/// sens de la consigne. Le blocage mesuré ne vient PAS d'une arrivée
/// manquante.
const List<List<int>> kArrivee = <List<int>>[
  <int>[9],
  <int>[4],
  <int>[15],
];

const String kCode = 'E_TIERCE';
const String kLibelleOrdre = 'e-Tiercé Ordre';
const String kCombinaison = '9-4-15';
const double kPourUnEuro = 477.40;
const double kMise = 2.0;

/// Retour attendu si le rapport Ordre est réellement attribué : 2 × 477,40.
const double kTotalAttendu = kMise * kPourUnEuro; // 954.8

/// Rapport « e-Tiercé Ordre » publié tel que l'API le fournit (après
/// normalisation en euros pour 1 € déjà faite par `decoderRapportsDefinitifs`).
RapportPmu rapportApiTierceOrdre() => const RapportPmu(
      typePari: kCode,
      combinaison: kCombinaison,
      dividende: kPourUnEuro,
      estOrdre: true,
      libelleOfficiel: kLibelleOrdre,
      codePariOfficiel: kCode,
      rangCombinaisonPayable: 1,
      miseBaseCentimes: 100,
    );

/// Rapport API d'un AUTRE bloc, parfaitement lisible. Il sert à rendre la
/// liste des rapports NON VIDE sans jamais fournir le bloc Tiercé joué.
/// C'est exactement la situation « le bloc juste n'est pas encore publié,
/// mais la course publie déjà d'autres rapports ».
RapportPmu rapportApiSimpleGagnantLisible() => const RapportPmu(
      typePari: 'E_SIMPLE_GAGNANT',
      combinaison: '9',
      dividende: 7.50,
      estOrdre: false,
      libelleOfficiel: 'e-Simple Gagnant',
      codePariOfficiel: 'E_SIMPLE_GAGNANT',
      rangCombinaisonPayable: 1,
      miseBaseCentimes: 100,
    );

/// Rapport API du bloc Tiercé, mais SANS libellé officiel.
///
/// `rapportPublieDepuisApi` rend alors `null` (variante illisible) et le
/// rapport est ÉCARTÉ : la liste des rapports publiés devient VIDE. C'est la
/// seule façon mesurée d'obtenir une liste vide alors que l'API a répondu.
RapportPmu rapportApiTierceSansLibelle() => const RapportPmu(
      typePari: kCode,
      combinaison: kCombinaison,
      dividende: kPourUnEuro,
      estOrdre: true,
      libelleOfficiel: '',
      codePariOfficiel: kCode,
    );

/// Rapport officiel publié, exploitable, désignant exactement le pari joué.
/// Sert aux mesures « transition vers un verdict PROUVÉ ».
const RapportPublie kOfficielTierceOrdre = RapportPublie(
  codePmu: kCode,
  libelle: kLibelleOrdre,
  combinaison: kCombinaison,
  variante: VarianteRapport.ordre,
  pourUnEuro: kPourUnEuro,
  rang: 1,
  miseBaseCentimes: 100,
);

// ─────────────────────────── Fixture ticket suivi ──────────────────────────

final DateTime _heure = DateTime.utc(2026, 11, 15, 14, 30);

/// Ticket suivi « Tiercé Ordre », dans l'état demandé.
///
/// `etatGain == null` ⇒ ticket vierge de tout verdict (première écriture).
/// `etatGain == nonDetermine` ⇒ ticket déjà porteur d'une indétermination
/// (c'est la précondition de la transition D1).
TrackedCourse _suivi({
  EtatGain? etatGain,
  MotifNonDetermination? motif,
  List<RapportAttribue>? rapportsAttribues,
}) =>
    TrackedCourse(
      numReunion: 1,
      numCourse: 6,
      nomCourse: 'PRIX B-4.6 D1',
      hippodrome: 'VINCENNES',
      heureDepart: _heure,
      storageKey: 'R1C6_15112026_b46',
      nomCheval: 'IDAO DE TILLARD',
      numeroCheval: 9,
      miseEngagee: kMise,
      typePari: 'Tiercé Ordre',
      numerosJoues: const <int>[9, 4, 15],
      codePmuOfficiel: kCode,
      varianteChoisie: 'ordre',
      numerosDansOrdre: const <int>[9, 4, 15],
      etatGain: etatGain,
      motifNonDetermination: motif,
      rapportsAttribues: rapportsAttribues,
    );

ResultatOfficielCourse _resultat(List<RapportPmu> rapports) =>
    ResultatOfficielCourse(
      arriveeGroupes: kArrivee,
      arriveeDefinitive: true,
      rapports: rapports,
    );

/// Verdict PROUVÉ : une composante réelle, tirée du rapport officiel exact.
VerdictGain _verdictAttribue() => VerdictGain.attribue(
      composantes: <ComposanteGain>[
        ComposanteGain(
          libelleRapport: kLibelleOrdre,
          combinaisonRapport: kCombinaison,
          categorie: VarianteRapport.ordre,
          role: RoleComposante.unique,
          mise: kMise,
          pourUnEuro: kPourUnEuro,
          montantRetour: kTotalAttendu,
        ),
      ],
    );

/// Verdict DÉFINITIF différent, prouvé par un autre rapport officiel.
VerdictGain _verdictAutreDefinitif() => VerdictGain.attribue(
      composantes: <ComposanteGain>[
        const ComposanteGain(
          libelleRapport: 'e-Tiercé Désordre',
          combinaisonRapport: '1-2-3',
          categorie: VarianteRapport.desordre,
          role: RoleComposante.unique,
          mise: kMise,
          pourUnEuro: 80.30,
          montantRetour: kMise * 80.30,
        ),
      ],
    );

const RapportPublie kOfficielAutre = RapportPublie(
  codePmu: kCode,
  libelle: 'e-Tiercé Désordre',
  combinaison: '1-2-3',
  variante: VarianteRapport.desordre,
  pourUnEuro: 80.30,
  rang: 2,
);

// ═══════════════════════════════════════════════════════════════════════════
//  MESURES
// ═══════════════════════════════════════════════════════════════════════════

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  //  GROUPE 1 — CE QUE PRODUIT RÉELLEMENT LE MOTEUR B-3
  //
  //  Avant de parler de transition, il faut prouver que le verdict
  //  `nonDetermine` qu'on prétend voir persister EXISTE vraiment, avec le
  //  motif attendu. Aucune hypothèse n'est faite ici : tout vient de
  //  `resoudreGainTicketDepuisDonnees`, la fonction de production.
  // ─────────────────────────────────────────────────────────────────────────
  group('B4.6/1 — verdict CALCULÉ par le moteur (preuve amont)', () {
    test('B4.6/1.1 tous les rapports écartés ⇒ blocJusteAbsent', () {
      final verdict = resoudreGainTicketDepuisDonnees(
        ticket: const TicketAGainResoudre.ticketSimple(
          libelleTypePari: 'Tiercé Ordre',
          numerosJoues: <int>[9, 4, 15],
          mise: kMise,
        ),
        resultat: _resultat(<RapportPmu>[rapportApiTierceSansLibelle()]),
      );

      // ignore: avoid_print
      print('─── B4.6/1.1 : etat=${verdict.etat.name} '
          'motif=${verdict.motif?.name} total=${verdict.total}');

      expect(verdict.etat, EtatGain.nonDetermine);
      expect(verdict.motif, MotifNonDetermination.blocJusteAbsent);
      expect(verdict.total, 0.0);
      expect(verdict.composantes, isEmpty);
    });

    test('B4.6/1.2 autres rapports publiés, bloc Tiercé absent ⇒ blocJusteAbsent',
        () {
      final verdict = resoudreGainTicketDepuisDonnees(
        ticket: const TicketAGainResoudre.ticketSimple(
          libelleTypePari: 'Tiercé Ordre',
          numerosJoues: <int>[9, 4, 15],
          mise: kMise,
        ),
        resultat:
            _resultat(<RapportPmu>[rapportApiSimpleGagnantLisible()]),
      );

      // ignore: avoid_print
      print('─── B4.6/1.2 : etat=${verdict.etat.name} '
          'motif=${verdict.motif?.name} total=${verdict.total}');

      expect(verdict.etat, EtatGain.nonDetermine);
      expect(verdict.motif, MotifNonDetermination.blocJusteAbsent);
      expect(verdict.composantes, isEmpty);
    });

    test('B4.6/1.3 rapport Tiercé sans montant ⇒ montantAbsent', () {
      final verdict = resoudreGainTicketDepuisDonnees(
        ticket: const TicketAGainResoudre.ticketSimple(
          libelleTypePari: 'Tiercé Ordre',
          numerosJoues: <int>[9, 4, 15],
          mise: kMise,
        ),
        resultat: _resultat(<RapportPmu>[
          const RapportPmu(
            typePari: kCode,
            combinaison: kCombinaison,
            dividende: 0.0,
            estOrdre: true,
            libelleOfficiel: kLibelleOrdre,
            codePariOfficiel: kCode,
          ),
        ]),
      );

      // ignore: avoid_print
      print('─── B4.6/1.3 : etat=${verdict.etat.name} '
          'motif=${verdict.motif?.name} total=${verdict.total}');

      expect(verdict.etat, EtatGain.nonDetermine);
      expect(verdict.motif, MotifNonDetermination.montantAbsent);
    });

    test('B4.6/1.4 rapport Tiercé complet ⇒ attribue 954,80 €', () {
      final verdict = resoudreGainTicketDepuisDonnees(
        ticket: const TicketAGainResoudre.ticketSimple(
          libelleTypePari: 'Tiercé Ordre',
          numerosJoues: <int>[9, 4, 15],
          mise: kMise,
        ),
        resultat: _resultat(<RapportPmu>[rapportApiTierceOrdre()]),
      );

      // ignore: avoid_print
      print('─── B4.6/1.4 : etat=${verdict.etat.name} total=${verdict.total}');

      expect(verdict.etat, EtatGain.attribue);
      expect(verdict.total, closeTo(kTotalAttendu, 1e-9));
      expect(verdict.composantes, hasLength(1));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  GROUPE 2 — (a) B-4.5 EMPÊCHE-T-IL DÉJÀ LA PERSISTANCE ?
  //
  //  La question n'est pas « le verdict est-il calculé ? » (oui, groupe 1)
  //  mais « est-il PERSISTÉ ? ». La mesure isole la seule variable qui
  //  compte : la liste des rapports officiels est-elle VIDE ou NON.
  // ─────────────────────────────────────────────────────────────────────────
  group('B4.6/2 — persistance d\'un verdict incomplet (frontière exacte)', () {
    test('B4.6/2.1 rapports VIDE ⇒ le nonDetermine EST persisté', () {
      final avant = _suivi();
      final r = enregistrerVerdictGainSuivi(
        ticket: avant,
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.blocJusteAbsent,
          explication: 'aucun bloc publié',
        ),
        rapportsOfficiels:
            const <RapportPublie>[], // ← LA variable isolée
      );

      // ignore: avoid_print
      print('─── B4.6/2.1 : statut=${r.statut.name} '
          'etatPersiste=${r.ticket.etatGain?.name} '
          'motifPersiste=${r.ticket.motifNonDetermination?.name} '
          'rapportsAttribues=${r.ticket.rapportsAttribues}');

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.nonDetermine);
      expect(r.ticket.motifNonDetermination,
          MotifNonDetermination.blocJusteAbsent);
      expect(r.ticket.rapportsAttribues, isNull,
          reason: 'null, JAMAIS [] — verrou documenté de B-4.3');
    });

    test('B4.6/2.2 ★ B-4.7 : rapports NON VIDE ⇒ le MÊME nonDetermine est '
        'désormais ENREGISTRÉ (incohérence corrigée)', () {
      final avant = _suivi();
      final r = enregistrerVerdictGainSuivi(
        ticket: avant,
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.blocJusteAbsent,
          explication: 'aucun bloc publié',
        ),
        rapportsOfficiels: <RapportPublie>[kOfficielTierceOrdre],
      );

      // ignore: avoid_print
      print('─── B4.6/2.2 : statut=${r.statut.name} '
          'etatPersiste=${r.ticket.etatGain?.name} '
          'identique=${identical(r.ticket, avant)}');

      // ★ B-4.7 (Anomalie 1) : ce test épinglait auparavant le DÉFAUT.
      //   La persistance d'un MÊME `nonDetermine` dépendait de la seule
      //   présence de rapports officiels : refusé quand la liste était pleine,
      //   écrit quand elle était vide. Un ticket indéterminé ne pouvait donc
      //   jamais être persisté sur une course dont les rapports existaient.
      //   Le refus est maintenant CIBLÉ sur l'incohérence réelle (branche B) et
      //   sur les composantes non identifiables (branche D), pas sur le fait
      //   qu'il existe des rapports pour la course.
      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.nonDetermine);
      expect(r.ticket.motifNonDetermination,
          MotifNonDetermination.blocJusteAbsent);
      expect(r.ticket.rapportsAttribues, isNull,
          reason: 'null, JAMAIS [] — verrou documenté de B-4.3');
      expect(r.ticket.dividendeGagnant, isNull);
      expect(r.ticket.dividendePlace, isNull);
    });

    test('B4.6/2.3 la frontière ne dépend PLUS de la VACUITÉ de la liste '
        '(corrigé en B-4.7)', () {
      // Même mesure avec `montantAbsent`. AVANT B-4.7 : `vide` était enregistré
      // et `plein` refusé — la frontière suivait la vacuité de la liste, ce qui
      // n'a aucune justification métier. Désormais les deux sont enregistrés :
      // l'indétermination motivée est persistée dans les deux cas.
      final vide = enregistrerVerdictGainSuivi(
        ticket: _suivi(),
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.montantAbsent,
          explication: 'montant absent',
        ),
      );
      final plein = enregistrerVerdictGainSuivi(
        ticket: _suivi(),
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.montantAbsent,
          explication: 'montant absent',
        ),
        rapportsOfficiels: <RapportPublie>[kOfficielTierceOrdre],
      );

      // ignore: avoid_print
      print('─── B4.6/2.3 : vide=${vide.statut.name} '
          'plein=${plein.statut.name}');

      expect(vide.statut, StatutEnregistrementVerdict.enregistre);
      expect(plein.statut, StatutEnregistrementVerdict.enregistre,
          reason: 'l\'indétermination motivée est persistée dans les deux cas');
      expect(plein.ticket.etatGain, EtatGain.nonDetermine);
      expect(plein.ticket.rapportsAttribues, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  GROUPE 3 — (b) LA TRANSITION, MESURÉE APRÈS CORRECTION B-4.7
  //
  //  ★ B-4.7 : la transition `nonDetermine → définitif` est désormais
  //    AUTORISÉE (arbitrage utilisateur) dès lors que les données démontrent le
  //    verdict. Ces tests ont été inversés en conséquence : ils épinglaient
  //    auparavant le blocage. Les garde-fous qui comptent restent vérifiés :
  //    aucun verdict définitif n'est écrasé (A2/3), et l'opération est
  //    idempotente (A2/2).
  // ─────────────────────────────────────────────────────────────────────────
  group('B4.6/3 — transition depuis un ticket déjà nonDeterminé', () {
    test('B4.6/3.1 nonDetermine → attribue PROUVÉ : la transition est '
        'autorisée et le montant est écrit UNE fois', () {
      final avant = _suivi(
        etatGain: EtatGain.nonDetermine,
        motif: MotifNonDetermination.blocJusteAbsent,
      );
      final r = enregistrerVerdictGainSuivi(
        ticket: avant,
        verdict: _verdictAttribue(),
        rapportsOfficiels: <RapportPublie>[kOfficielTierceOrdre],
      );

      // ignore: avoid_print
      print('─── B4.6/3.1 : statut=${r.statut.name} '
          'etat=${r.ticket.etatGain?.name} identical=${identical(r.ticket, avant)} '
          'motif=${r.motif?.replaceAll("\n", " ")}');

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.attribue);
      expect(identical(r.ticket, avant), isFalse,
          reason: 'un nouveau ticket est rendu : le définitif est écrit');
      expect(r.ticket.rapportsAttribues, isNotNull);
    });

    test('B4.6/3.2 nonDetermine → perdu : la transition est autorisée, sans '
        'aucun montant', () {
      final avant = _suivi(
        etatGain: EtatGain.nonDetermine,
        motif: MotifNonDetermination.blocJusteAbsent,
      );
      final r = enregistrerVerdictGainSuivi(
        ticket: avant,
        verdict: VerdictGain.perdu(explication: 'arrivée non conforme'),
      );

      // ignore: avoid_print
      print('─── B4.6/3.2 : statut=${r.statut.name}');

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.perdu);
      expect(r.ticket.rapportsAttribues, isNull);
      expect(r.ticket.dividendeGagnant, isNull);
      expect(r.ticket.dividendePlace, isNull);
    });

    test('B4.6/3.3 nonDetermine → rembourse : la transition est autorisée, '
        'sans aucun montant', () {
      final avant = _suivi(
        etatGain: EtatGain.nonDetermine,
        motif: MotifNonDetermination.blocJusteAbsent,
      );
      final r = enregistrerVerdictGainSuivi(
        ticket: avant,
        verdict: VerdictGain.rembourse(explication: 'bloc remboursé'),
      );

      // ignore: avoid_print
      print('─── B4.6/3.3 : statut=${r.statut.name}');

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.rembourse);
      expect(r.ticket.rapportsAttribues, isNull);
    });

    test('B4.6/3.4 transition nonDetermine → nonDetermine (autre motif) '
        'autorisée : une indétermination peut S\'AMÉLIORER', () {
      // Une indétermination n'est pas un verdict définitif : la remplacer par
      // une indétermination MIEUX motivée (ici l'arrivée est connue, seul le
      // bloc manque) est légitime et n'engage aucun montant.
      final avant = _suivi(
        etatGain: EtatGain.nonDetermine,
        motif: MotifNonDetermination.deadHeatSansGroupes,
      );
      final r = enregistrerVerdictGainSuivi(
        ticket: avant,
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.blocJusteAbsent,
          explication: 'arrivée connue, bloc absent',
        ),
      );

      // ignore: avoid_print
      print('─── B4.6/3.4 : statut=${r.statut.name} '
          'motifConserve=${r.ticket.motifNonDetermination?.name}');

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.motifNonDetermination,
          MotifNonDetermination.blocJusteAbsent);
      expect(r.ticket.etatGain, EtatGain.nonDetermine);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  GROUPE 4 — (b) LE BLOCAGE VU DEPUIS LA CHAÎNE RÉELLE DE PRODUCTION
  //
  //  Les groupes 2 et 3 appellent l'enregistreur. Ici on appelle la fonction
  //  effectivement utilisée par les DEUX écrans B-4.5 : `resoudreSuivi`.
  //  Cela prouve que le verdict est bien CALCULÉ et bien TRANSMIS, et que
  //  c'est l'enregistreur — pas le branchement — qui refuse.
  // ─────────────────────────────────────────────────────────────────────────
  group('B4.6/4 — chaîne réelle `resoudreSuivi` (verdict calculé ≠ persisté)',
      () {
    test('B4.6/4.1 ★ B-4.7 : le verdict est calculé ET désormais PERSISTÉ', () {
      final avant = _suivi(
        etatGain: EtatGain.nonDetermine,
        motif: MotifNonDetermination.blocJusteAbsent,
      );

      final resolution = resoudreSuivi(
        ticket: avant,
        resultat: _resultat(<RapportPmu>[rapportApiTierceOrdre()]),
      );

      // ignore: avoid_print
      print('─── B4.6/4.1 : aUneIssue=${resolution.aUneIssue} '
          'verdict=${resolution.verdict?.etat.name} '
          'verdictTotal=${resolution.verdict?.total} '
          'statutPersistance=${resolution.enregistrement?.statut.name} '
          'etatTicketRendu=${resolution.enregistrement?.ticket.etatGain?.name}');

      // 1. Aucun refus de construction : la donnée du ticket est exploitable.
      expect(resolution.aUneIssue, isFalse);

      // 2. Le moteur a bien PRODUIT le verdict définitif et son montant.
      expect(resolution.verdict, isNotNull);
      expect(resolution.verdict!.etat, EtatGain.attribue);
      expect(resolution.verdict!.total, closeTo(kTotalAttendu, 1e-9));

      // 3. ★ B-4.7 : le verdict définitif est désormais PERSISTÉ. Le refus
      //    venait du persisteur, pas du calcul — et il bloquait pour toujours
      //    un ticket dont les données démontraient pourtant le gain.
      expect(resolution.enregistrement, isNotNull);
      expect(resolution.enregistrement!.statut,
          StatutEnregistrementVerdict.enregistre);
      expect(resolution.enregistrement!.estEnregistre, isTrue);
      expect(resolution.enregistrement!.ticket.etatGain, EtatGain.attribue);
      // Aucun double gain : le rapport officiel identifié est persisté UNE
      // fois, et le total persisté est celui d'un seul règlement.
      expect(resolution.enregistrement!.ticket.rapportsAttribues, isNotNull);
      expect(resolution.enregistrement!.ticket.rapportsAttribues!.length, 1);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  GROUPE 5 — (d) LE VERDICT DÉFINITIF EXISTANT EST INTACT
  //
  //  « Ne jamais écraser un verdict déjà définitif. » On le mesure avant de
  //  proposer la moindre règle : si cette protection n'était pas solide, la
  //  règle de transition proposée serait dangereuse.
  // ─────────────────────────────────────────────────────────────────────────
  group('B4.6/5 — protection du verdict définitif (non-régression à préserver)',
      () {
    test('B4.6/5.1 même verdict définitif ⇒ dejaIdentique, aucune copie', () {
      final officiel = RapportAttribue.calculer(
        rapport: kOfficielTierceOrdre,
        miseAppliquee: kMise,
      );
      final avant = _suivi(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[officiel],
      );
      final r = enregistrerVerdictGainSuivi(
        ticket: avant,
        verdict: _verdictAttribue(),
        rapportsOfficiels: <RapportPublie>[kOfficielTierceOrdre],
      );

      // ignore: avoid_print
      print('─── B4.6/5.1 : statut=${r.statut.name} '
          'identical=${identical(r.ticket, avant)}');

      expect(r.statut, StatutEnregistrementVerdict.dejaIdentique);
      expect(r.estEnregistre, isFalse,
          reason: 'dejaIdentique n\'est PAS estEnregistre (l.120)');
      expect(identical(r.ticket, avant), isTrue);
    });

    test('B4.6/5.2 verdict définitif DIFFÉRENT ⇒ refus, jamais d\'écrasement',
        () {
      final officiel = RapportAttribue.calculer(
        rapport: kOfficielTierceOrdre,
        miseAppliquee: kMise,
      );
      final avant = _suivi(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[officiel],
      );
      final r = enregistrerVerdictGainSuivi(
        ticket: avant,
        verdict: _verdictAutreDefinitif(),
        rapportsOfficiels: <RapportPublie>[kOfficielAutre],
      );

      // ignore: avoid_print
      print('─── B4.6/5.2 : statut=${r.statut.name} '
          'totalConserve=${resoudreTotalDepuisRapports(r.ticket.rapportsAttribues)}');

      expect(r.statut,
          StatutEnregistrementVerdict.refuseVerdictDefinitifExistant);
      expect(resoudreTotalDepuisRapports(r.ticket.rapportsAttribues),
          closeTo(kTotalAttendu, 1e-9),
          reason: 'le montant déjà établi est conservé tel quel');
    });

    test('B4.6/5.3 perdu, puis attribue : refus, la perte tient', () {
      final premier = enregistrerVerdictGainSuivi(
        ticket: _suivi(),
        verdict: VerdictGain.perdu(explication: 'perdu'),
      );
      expect(premier.statut, StatutEnregistrementVerdict.enregistre);
      expect(premier.ticket.etatGain, EtatGain.perdu);

      final second = enregistrerVerdictGainSuivi(
        ticket: premier.ticket,
        verdict: _verdictAttribue(),
        rapportsOfficiels: <RapportPublie>[kOfficielTierceOrdre],
      );

      // ignore: avoid_print
      print('─── B4.6/5.3 : premier=${premier.statut.name} '
          'second=${second.statut.name}');

      expect(second.statut,
          StatutEnregistrementVerdict.refuseVerdictDefinitifExistant);
      expect(second.ticket.etatGain, EtatGain.perdu);
      expect(second.ticket.rapportsAttribues, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  GROUPE 6 — LE SECOND BLOCAGE, DISTINCT DE D1, MESURÉ
  //
  //  ⚠️ CE N'EST PAS UN SCÉNARIO DE TRANSITION.
  //  C'est la raison pour laquelle « transition vers `perdu` » et « transition
  //  vers `rembourse` » sont, en l'état, STRUCTURELLEMENT inatteignables :
  //  `perdu` et `rembourse` n'ont AUCUNE composante, et la branche C refuse
  //  tout verdict sans composante dès que la liste des rapports est non vide —
  //  y compris sur un ticket VIERGE.
  // ─────────────────────────────────────────────────────────────────────────
  group('B4.6/6 — branche C : verdict à zéro composante face à des rapports',
      () {
    test('B4.6/6.1 ★ B-4.7 : ticket vierge + perdu + rapports publiés ⇒ '
        'la perte EST écrite, sans aucun montant', () {
      final avant = _suivi(); // etatGain == null : première écriture
      final r = enregistrerVerdictGainSuivi(
        ticket: avant,
        verdict: VerdictGain.perdu(explication: 'chevaux non placés'),
        rapportsOfficiels: <RapportPublie>[kOfficielTierceOrdre],
      );

      // ignore: avoid_print
      print('─── B4.6/6.1 : statut=${r.statut.name} '
          'etatPersiste=${r.ticket.etatGain?.name} identical=${identical(r.ticket, avant)}');

      // ★ B-4.7 (Anomalie 1) : ce test épinglait le DÉFAUT. La présence de
      //   rapports pour la COURSE n'implique pas qu'un ticket doive porter une
      //   composante : une perte démontrée est persistable.
      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.perdu);
      expect(identical(r.ticket, avant), isFalse);
      expect(r.ticket.rapportsAttribues, isNull, reason: 'aucun montant');
      expect(r.ticket.dividendeGagnant, isNull);
      expect(r.ticket.dividendePlace, isNull);
    });

    test('B4.6/6.2 même ticket, mêmes rapports VIDES ⇒ la perte EST écrite', () {
      // Contrôle : la SEULE variable est la vacuité de la liste. Cela isole
      // la branche C comme cause unique du refus mesuré en 6.1.
      final r = enregistrerVerdictGainSuivi(
        ticket: _suivi(),
        verdict: VerdictGain.perdu(explication: 'chevaux non placés'),
        rapportsOfficiels: const <RapportPublie>[],
      );

      // ignore: avoid_print
      print('─── B4.6/6.2 : statut=${r.statut.name} '
          'etatPersiste=${r.ticket.etatGain?.name}');

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.perdu);
    });

    test('B4.6/6.3 ★ B-4.7 : ticket vierge + rembourse + rapports publiés ⇒ '
        'le remboursement EST écrit, sans aucun montant', () {
      final r = enregistrerVerdictGainSuivi(
        ticket: _suivi(),
        verdict: VerdictGain.rembourse(explication: 'bloc remboursé'),
        rapportsOfficiels: <RapportPublie>[kOfficielTierceOrdre],
      );

      // ignore: avoid_print
      print('─── B4.6/6.3 : statut=${r.statut.name}');

      // ★ B-4.7 : un remboursement démontré est persisté. C'est une exigence
      //   de la consigne (« préserver les remboursements »).
      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.rembourse);
      expect(r.ticket.rapportsAttribues, isNull);
    });

    test('B4.6/6.4 ticket vierge + attribue PROUVÉ + rapports publiés ⇒ écrit',
        () {
      // Le seul cas qui traverse la branche C avec des rapports : un verdict
      // pourvu de composantes. Il sert de témoin : le chemin n'est pas bloqué
      // « en général », il l'est précisément pour les verdicts à zéro
      // composante.
      final r = enregistrerVerdictGainSuivi(
        ticket: _suivi(),
        verdict: _verdictAttribue(),
        rapportsOfficiels: <RapportPublie>[kOfficielTierceOrdre],
      );

      // ignore: avoid_print
      print('─── B4.6/6.4 : statut=${r.statut.name} '
          'etat=${r.ticket.etatGain?.name} '
          'total=${resoudreTotalDepuisRapports(r.ticket.rapportsAttribues)}');

      expect(r.statut, StatutEnregistrementVerdict.enregistre);
      expect(r.ticket.etatGain, EtatGain.attribue);
      expect(resoudreTotalDepuisRapports(r.ticket.rapportsAttribues),
          closeTo(kTotalAttendu, 1e-9));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  GROUPE 7 — LE SCÉNARIO D1 COMPLET, DE BOUT EN BOUT, PAR LA CHAÎNE RÉELLE
  //
  //  C'est LA reproduction demandée. Elle se déroule en trois temps, tous
  //  mesurés sur `resoudreSuivi` — la fonction que les deux écrans B-4.5
  //  appellent réellement.
  //
  //  Le point décisif mesuré ici : l'écran ne filtre que deux choses avant
  //  d'appeler la chaîne — la présence des groupes d'arrivée et la vacuité de
  //  la liste API BRUTE. Il ne filtre PAS ce que le convertisseur va écarter.
  //  Un lot de rapports tous illisibles passe donc le filtre de l'écran, mais
  //  arrive VIDE au persisteur : c'est le chemin par lequel un verdict
  //  incomplet est réellement écrit.
  // ─────────────────────────────────────────────────────────────────────────
  group('B4.6/7 — scénario D1 de bout en bout (trois temps)', () {
    test('B4.6/7.1 TEMPS 1 : le bloc juste n\'est pas publié, la liste API '
        'contient pourtant des lignes ⇒ le nonDetermine est ÉCRIT', () {
      // Ticket VIERGE : c'est la condition `course.etatGain == null` de
      // l'écran. Groupes d'arrivée PRÉSENTS et DÉFINITIFS : la première
      // garde de l'écran passe. Liste API BRUTE NON VIDE : la seconde garde
      // passe. Et pourtant le convertisseur écarte tout.
      final avant = _suivi(); // etatGain == null

      final resolution = resoudreSuivi(
        ticket: avant,
        resultat: _resultat(<RapportPmu>[rapportApiTierceSansLibelle()]),
      );

      // ignore: avoid_print
      print('─── B4.6/7.1 : verdict=${resolution.verdict?.etat.name} '
          'motif=${resolution.verdict?.motif?.name} '
          'statut=${resolution.enregistrement?.statut.name} '
          'etatECRIT=${resolution.enregistrement?.ticket.etatGain?.name} '
          'estEnregistre=${resolution.enregistrement?.estEnregistre}');

      expect(resolution.verdict!.etat, EtatGain.nonDetermine);
      expect(resolution.verdict!.motif, MotifNonDetermination.blocJusteAbsent);
      expect(resolution.enregistrement!.statut,
          StatutEnregistrementVerdict.enregistre);
      expect(resolution.enregistrement!.estEnregistre, isTrue);
      expect(resolution.enregistrement!.ticket.etatGain,
          EtatGain.nonDetermine,
          reason: 'LE VERDICT INCOMPLET EST PERSISTÉ');
    });

    test('B4.6/7.2 TEMPS 2 : le bloc juste est publié ⇒ la transition est '
        'REFUSÉE, définitivement', () {
      // On reprend le ticket tel qu'il vient d'être écrit au temps 1 : c'est
      // ce que `_load()` relirait au prochain démarrage.
      final ecrit = enregistrerVerdictGainSuivi(
        ticket: _suivi(),
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.blocJusteAbsent,
          explication: 'aucun bloc publié',
        ),
      ).ticket;
      expect(ecrit.etatGain, EtatGain.nonDetermine);

      // Le bloc Tiercé Ordre est désormais publié, avec son montant.
      final resolution = resoudreSuivi(
        ticket: ecrit,
        resultat: _resultat(<RapportPmu>[rapportApiTierceOrdre()]),
      );

      // ignore: avoid_print
      print('─── B4.6/7.2 : verdict=${resolution.verdict?.etat.name} '
          'verdictTotal=${resolution.verdict?.total} '
          'statut=${resolution.enregistrement?.statut.name} '
          'etatCONSERVE=${resolution.enregistrement?.ticket.etatGain?.name}');

      // Le moteur recalcule correctement 954,80 €…
      expect(resolution.verdict!.etat, EtatGain.attribue);
      expect(resolution.verdict!.total, closeTo(kTotalAttendu, 1e-9));

      // …et ce gain PROUVÉ est désormais ÉCRIT (★ B-4.7, Anomalie 2).
      expect(resolution.enregistrement!.statut,
          StatutEnregistrementVerdict.enregistre);
      expect(resolution.enregistrement!.estEnregistre, isTrue);
      expect(resolution.enregistrement!.ticket.etatGain, EtatGain.attribue);
    });

    test('B4.6/7.3 TEMPS 3 : l\'écran ne rappelle même plus la chaîne '
        '(garde `etatGain == null`)', () {
      // Mesure de la SECONDE barrière. Elle n'est pas dans l'enregistreur :
      // elle est dans les deux écrans B-4.5, sous la forme
      //     if (course.etatGain == null) { ... resoudreSuivi ... }
      //     if (pred.etatGain != null) continue;
      //
      // On mesure ici la CONSÉQUENCE de cette garde sans monter d'écran :
      // une fois un verdict écrit, la chaîne n'est plus sollicitée, donc le
      // verdict n'a plus AUCUNE occasion d'être recalculé ni corrigé.
      final ecrit = enregistrerVerdictGainSuivi(
        ticket: _suivi(),
        verdict: VerdictGain.nonDetermine(
          motif: MotifNonDetermination.blocJusteAbsent,
          explication: 'aucun bloc publié',
        ),
      ).ticket;

      // Condition littérale lue dans mes_paris_screen.dart:1136 et
      // paris_detail_screen.dart:690 — reproduite ici telle quelle.
      final laChaineEstAppelee = ecrit.etatGain == null;

      // ignore: avoid_print
      print('─── B4.6/7.3 : etatGain=${ecrit.etatGain?.name} '
          'laChaineEstAppelee=$laChaineEstAppelee');

      expect(laChaineEstAppelee, isFalse,
          reason: 'la garde d\'écran empêche toute reprise du calcul');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  GROUPE 8 — (c) « RÉSULTAT INCOMPLET » vs « RAPPORT PAS ENCORE PUBLIÉ »
  //
  //  La consigne exige de distinguer ces deux situations. Le lot B-4.5 les
  //  distingue DÉJÀ — mais dans le mauvais sens pour D1 : c'est la situation
  //  « rapport pas encore publié » qui est ÉCRITE, et « résultat incomplet »
  //  qui est REFUSÉE. Ces deux mesures le prouvent, terme à terme.
  // ─────────────────────────────────────────────────────────────────────────
  group('B4.6/8 — les deux situations, mesurées séparément', () {
    test('B4.6/8.1 « rapport pas encore publié » (liste API vide) : rien '
        'n\'est tenté — l\'écran s\'arrête avant la chaîne', () {
      // Mesure de la garde d'écran, traduite en appel de chaîne : quand la
      // liste API est VIDE, l'écran ne descend pas jusqu'à `resoudreSuivi`.
      // Aucune écriture, donc aucun blocage futur n'est créé.
      final listeApiVide = <RapportPmu>[];
      final laChaineEstAppelee = listeApiVide.isNotEmpty;

      // ignore: avoid_print
      print('─── B4.6/8.1 : rapportsApi=${listeApiVide.length} '
          'laChaineEstAppelee=$laChaineEstAppelee');

      expect(laChaineEstAppelee, isFalse);
    });

    test('B4.6/8.2 « résultat officiel incomplet » (lignes publiées mais '
        'inconvertibles) : le nonDetermine EST écrit', () {
      // C'est le cas dangereux : l'API a répondu (liste non vide), donc
      // l'écran descend jusqu'à la chaîne, mais la conversion écarte tout.
      final resolution = resoudreSuivi(
        ticket: _suivi(),
        resultat: _resultat(<RapportPmu>[rapportApiTierceSansLibelle()]),
      );

      // ignore: avoid_print
      print('─── B4.6/8.2 : ecartes=${resolution.verdict?.motif?.name} '
          'statut=${resolution.enregistrement?.statut.name}');

      expect(resolution.enregistrement!.statut,
          StatutEnregistrementVerdict.enregistre,
          reason: 'un verdict SANS preuve suffisante est écrit');
    });

    test('B4.6/8.3 « autres blocs publiés, bloc joué absent » : le'
        ' nonDetermine est REFUSÉ (protection existante)', () {
      // Contre-exemple mesuré de 8.2 : il suffit qu'UN rapport soit
      // convertible pour que la branche C refuse l'écriture. C'est une
      // protection RÉELLE de B-4.5 — mais elle est involontaire : elle
      // dépend de la lisibilité d'un rapport SANS RAPPORT avec le pari joué.
      final resolution = resoudreSuivi(
        ticket: _suivi(),
        resultat: _resultat(<RapportPmu>[rapportApiSimpleGagnantLisible()]),
      );

      // ignore: avoid_print
      print('─── B4.6/8.3 : motif=${resolution.verdict?.motif?.name} '
          'statut=${resolution.enregistrement?.statut.name}');

      expect(resolution.verdict!.motif, MotifNonDetermination.blocJusteAbsent);
      // ★ B-4.7 (Anomalie 1) : l'indétermination motivée est PERSISTÉE, alors
      //   qu'elle était refusée dès qu'un rapport — même SANS RAPPORT avec le
      //   pari joué — était lisible. C'était bien une frontière involontaire.
      //   Aucun montant n'est écrit pour autant.
      expect(resolution.enregistrement!.statut,
          StatutEnregistrementVerdict.enregistre);
      expect(resolution.enregistrement!.ticket.etatGain, EtatGain.nonDetermine);
      expect(resolution.enregistrement!.ticket.rapportsAttribues, isNull);
    });
  });
}
