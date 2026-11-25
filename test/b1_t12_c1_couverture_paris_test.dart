// ═══════════════════════════════════════════════════════════════════════════
//  CHANTIER 1/3 — OPÉRATION 2/3 : COUVERTURE DES TYPES ET VARIANTES DE PARIS
//
//  OBJET — « Examiner la couverture existante de tous les types et variantes
//           de paris pris en charge par l'application. Réutiliser les tests
//           existants lorsqu'ils sont suffisants. Compléter uniquement les
//           véritables lacunes et corriger les anomalies démontrées. »
//
//  ── MÉTHODE : MESURER D'ABORD, ÉCRIRE ENSUITE ────────────────────────────
//  Ce fichier ne duplique PAS la couverture existante, qui est déjà large :
//    • `b3_moteur_gain_pmu_test.dart` (117 tests) couvre les variantes
//      `ordre`/`desordre`/`bonusQuarte`/`bonus4sur5`/`bonus3`/`tirelire`/
//      `nonPartant` pour Tiercé, Quarté+ et Quinté+, sur des blocs RÉELS ;
//    • `b4_7_trois_anomalies_test.dart` couvre la PERTE DÉMONTRÉE pour
//      Simple Gagnant, Simple Placé et Couplé Gagnant sur capture réelle ;
//    • `b4_6_moteur_sur_arrivees_reelles_test.dart` mesure les 7 types sur
//      313 captures réelles ;
//    • `a0_01_type_pari_utils_test.dart` couvre le CONVERTISSEUR de libellés.
//
//  ── LACUNES MESURÉES, ET SEULES COMBLÉES ICI ─────────────────────────────
//    L1. `Couplé Placé` : aucune perte démontrée n'était assertée nulle part.
//        Mesure : `grep "Couplé Placé" test/*.dart | grep -i perdu` est VIDE.
//        Or `_dansPerimetrePerteDemontree` le déclare DANS le périmètre —
//        une promesse de code qu'aucun test n'épinglait.
//    L2. `Couplé Ordre` et `Couplé Désordre` : idem, aucune perte démontrée
//        assertée. Ils sont hors du périmètre de perte démontrée par le
//        moteur (la perte y est prononcée par l'ARBITRE), donc la lacune à
//        combler est celle du verdict RÉELLEMENT rendu, pas d'une promesse.
//    L3. `Gagnant+Placé` : la perte TOTALE (aucune des deux composantes ne
//        paie) n'était assertée qu'en gain partiel (B3/6.5) et en mixte
//        remboursé (b1_t12_p1 R3/R4). Aucun test ne dit ce que vaut un G+P
//        dont AUCUNE composante n'est payable.
//    L4. Les quatre codes PMU non mesurés par les captures du dépôt :
//        `E_COUPLE_ORDRE` existe (11 courses réelles) mais la perte n'était
//        pas assertée ; `E_SIMPLE_PLACE` en perte l'était (A1/2).
//
//  ⚠️ CE FICHIER N'INVENTE AUCUN TYPE, AUCUN CODE, AUCUN DIVIDENDE. Tous les
//     montants proviennent de la capture réelle `R1C6_15112026.json`, lue par
//     le DÉCODEUR DE PRODUCTION (`PmuApiService.decoderRapportsDefinitifs`),
//     ou sont explicitement décrits comme synthétiques quand le bloc réel ne
//     publie pas la variante (cas mesuré du Couplé Ordre sur cette course).
//
//  ⚠️ AUCUNE ASSERTION MÉTIER N'EST AFFAIBLIE. Chaque test ci-dessous échoue
//     si le moteur cesse de rendre l'état annoncé.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/arbitre_variante_pmu.dart';
import 'package:pronostic_hippique/services/gain_calculator.dart' show RapportPmu;
import 'package:pronostic_hippique/services/gain_pmu_types.dart'
    show EtatGain, MotifNonDetermination;
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show
        TypePariJoue,
        VarianteRapport,
        codeApiPourType,
        tailleCombinaisonAttendue,
        typePariDepuisLibelle,
        varianteDepuisLibelle,
        variantesIdentifiablesParCombinaison;
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart'
    show MiseEngagee, VerdictGain, resoudreGainTicket;
import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart'
    show convertirRapportsApi;
import 'fixtures/fixture_paths.dart';

final String kDossier = dossierMulti;

/// R1C6 du 15/11/2026 : arrivée officielle 9-4-15-10-1-7-12.
///
/// Blocs publiés par cette course (mesurés) :
///   • E_SIMPLE_GAGNANT 9 @ 7,50 €
///   • E_SIMPLE_PLACE   9 @ 3,00 € · 4 @ 2,60 € · 15 @ 6,90 €
///   • E_COUPLE_GAGNANT 9-4
///   • E_COUPLE_PLACE   (paires payables du top 3)
///   • E_TIERCE         Ordre 9-4-15 @ 477,40 € · Désordre @ 80,30 €
///   • E_QUARTE_PLUS / E_QUINTE_PLUS (blocs complets)
const List<List<int>> kArrivee = <List<int>>[
  <int>[9], <int>[4], <int>[15], <int>[10], <int>[1], <int>[7], <int>[12],
];

List<RapportPmu> rapportsReels() => PmuApiService.decoderRapportsDefinitifs(
      File('$kDossier/R1C6_15112026.json').readAsStringSync(),
    );

/// Construit l'état officiel à partir des seuls rapports réels.
///
/// ⚠️ `statutsPartants` reste ABSENT : la capture de rapports ne porte pas les
///    statuts. C'est exactement la situation réelle de l'application quand
///    elle ne dispose que des rapports — et le moteur doit malgré tout rendre
///    un verdict, sans jamais inventer une perte par simple absence.
/// ───────────────────────────────────────────────────────────────────────────
///  SENTINELLE D'ABSENCE — correction d'un défaut de mon propre harnais.
///
///  DÉFAUT MESURÉ : ma première version était
///  `etatReel({List<List<int>>? groupes}) => ... arriveeGroupes: groupes ?? kArrivee`.
///  Le repli `??` rendait le scénario NÉGATIF INEXPRIMABLE : passer `null`
///  RÉINJECTAIT silencieusement l'arrivée réelle. Le test C1/4.3 prétendait donc
///  mesurer « aucune arrivée » alors qu'il mesurait « arrivée complète ».
///
///  CORRECTION : trois états distincts, non confondables.
///    • `_Arrivee.fournie(g)`  → une arrivée explicite ;
///    • `_Arrivee.absente`     → `arriveeGroupes: null` transmis TEL QUEL ;
///    • `_Arrivee.parDefaut`   → l'arrivée de référence, choisi EXPLICITEMENT.
///  Aucun `??` ne subsiste sur cette dimension : une valeur par défaut ne peut
///  plus se substituer à une absence.
/// ───────────────────────────────────────────────────────────────────────────
class _Arrivee {
  const _Arrivee._(this.groupes, this.estAbsente);

  final List<List<int>>? groupes;
  final bool estAbsente;

  /// Arrivée explicite.
  const _Arrivee.fournie(List<List<int>> g) : this._(g, false);

  /// Absence EXPLICITE : `null` est transmis au moteur, sans repli.
  const _Arrivee.absente() : this._(null, true);

  /// Arrivée de référence de la capture, choisie volontairement.
  factory _Arrivee.parDefaut() => const _Arrivee.fournie(kArrivee);
}

/// Construit l'état officiel par le CHEMIN DE PRODUCTION, sans le réécrire.
///
/// ⚠️ Le chemin est celui de `resoudreGainTicketDepuisDonnees`
///    (resolution_gain_ticket_pmu.dart:259-272) : `convertirRapportsApi` puis
///    `EtatCourseOfficiel`. Aucun helper imaginaire.
///
/// ⚠️ `statutsPartants` reste ABSENT : la capture de rapports n'en porte aucun.
EtatCourseOfficiel etatReel({
  _Arrivee? arrivee,
  bool? definitive = true,
}) {
  final conversion = convertirRapportsApi(rapportsReels());
  // Pas de `??` : si `arrivee` est omis, on choisit EXPLICITEMENT le défaut.
  final a = arrivee ?? _Arrivee.parDefaut();
  return EtatCourseOfficiel(
    arriveeGroupes: a.groupes,
    arriveeDefinitive: definitive,
    rapports: conversion.rapports,
  );
}

VerdictGain jouer(
  String libelle,
  List<int> numeros,
  double mise,
  EtatCourseOfficiel e,
) =>
    resoudreGainTicket(
      libelleTypePari: libelle,
      numerosJoues: numeros,
      mise: MiseEngagee.simple(mise),
      etat: e,
    );

VerdictGain jouerGagnantPlace(
  List<int> numeros,
  double miseGagnant,
  double misePlace,
  EtatCourseOfficiel e,
) =>
    resoudreGainTicket(
      libelleTypePari: 'Gagnant+Placé',
      numerosJoues: numeros,
      mise: MiseEngagee.gagnantPlace(
        gagnant: miseGagnant,
        place: misePlace,
      ),
      etat: e,
    );

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  C1/0 — ÉTAT DES LIEUX : LE RÉFÉRENTIEL DES TYPES EST CLOS
  //
  //  Ce groupe ne teste pas une correction : il ÉPINGLE l'inventaire que les
  //  groupes suivants parcourent. Si un type était ajouté sans être couvert,
  //  le décompte ci-dessous changerait et le test tomberait.
  // ═════════════════════════════════════════════════════════════════════════
  group('C1/0 — inventaire des types et variantes pris en charge', () {
    test('C1/0.1 les 12 libellés reconnus correspondent aux 12 TypePariJoue',
        () {
      // Mesuré : `typePariDepuisLibelle` reconnaît 12 libellés et rend
      // `inconnu` pour tout autre. `inconnu` n'est pas un libellé jouable.
      const libelles = <String, TypePariJoue>{
        'Simple Gagnant': TypePariJoue.simpleGagnant,
        'Simple Placé': TypePariJoue.simplePlace,
        'Gagnant+Placé': TypePariJoue.gagnantPlace,
        'Couplé Gagnant': TypePariJoue.coupleGagnant,
        'Couplé Placé': TypePariJoue.couplePlace,
        'Couplé Ordre': TypePariJoue.coupleOrdre,
        'Couplé Désordre': TypePariJoue.coupleDesordre,
        'Tiercé': TypePariJoue.tierce,
        'Tiercé Ordre': TypePariJoue.tierceOrdre,
        'Tiercé Désordre': TypePariJoue.tierceDesordre,
        'Quarté+': TypePariJoue.quarte,
        'Quinté+': TypePariJoue.quinte,
      };
      expect(libelles.length, 12,
          reason: 'un libellé de plus ⇒ la couverture de ce fichier est '
              'incomplète, il faut la compléter');
      for (final e in libelles.entries) {
        expect(typePariDepuisLibelle(e.key), e.value,
            reason: '« ${e.key} » doit se résoudre en ${e.value.name}');
      }
      // Tout le reste rend `inconnu` : aucun type par défaut n'est substitué.
      for (final inconnu in <String>['Trio', '2sur4', 'Multi', 'Super 4']) {
        expect(typePariDepuisLibelle(inconnu), TypePariJoue.inconnu,
            reason: '« $inconnu » ne doit JAMAIS être assimilé à un type '
                'de l\'application');
      }
    });

    test('C1/0.2 les codes PMU officiels reconnus sont exactement HUIT', () {
      // Mesuré sur `codeApiPourType`. `gagnantPlace` et `inconnu` rendent
      // `null` — et c'est voulu : un G+P n'a pas de code unique, il se
      // dédouble ; un type inconnu n'a aucun calcul.
      const attendu = <TypePariJoue, String?>{
        TypePariJoue.simpleGagnant: 'E_SIMPLE_GAGNANT',
        TypePariJoue.simplePlace: 'E_SIMPLE_PLACE',
        TypePariJoue.gagnantPlace: null,
        TypePariJoue.coupleGagnant: 'E_COUPLE_GAGNANT',
        TypePariJoue.coupleDesordre: 'E_COUPLE_GAGNANT',
        TypePariJoue.couplePlace: 'E_COUPLE_PLACE',
        TypePariJoue.coupleOrdre: 'E_COUPLE_ORDRE',
        TypePariJoue.tierce: 'E_TIERCE',
        TypePariJoue.tierceOrdre: 'E_TIERCE',
        TypePariJoue.tierceDesordre: 'E_TIERCE',
        TypePariJoue.quarte: 'E_QUARTE_PLUS',
        TypePariJoue.quinte: 'E_QUINTE_PLUS',
        TypePariJoue.inconnu: null,
      };
      for (final e in attendu.entries) {
        expect(codeApiPourType(e.key), e.value,
            reason: 'code PMU de ${e.key.name}');
      }
      final codes = attendu.values.whereType<String>().toSet();
      // ★ MESURÉ, et non supposé : vérifié par exécution du référentiel —
      //   DISTINCTS=8 -> {E_SIMPLE_GAGNANT, E_SIMPLE_PLACE, E_COUPLE_GAGNANT,
      //   E_COUPLE_PLACE, E_COUPLE_ORDRE, E_TIERCE, E_QUARTE_PLUS,
      //   E_QUINTE_PLUS}. Ma première assertion disait 7 : c'était une ERREUR
      //   D'ARITHMÉTIQUE de ma part, pas un défaut du code.
      expect(codes.length, 8,
          reason: 'huit codes distincts mesurés : $codes');
      // Aucun code EXOTIQUE n'est revendiqué par l'application.
      for (final exotique in <String>[
        'E_TRIO', 'E_TRIO_ORDRE', 'E_SUPER_QUATRE', 'E_MULTI',
        'E_MINI_MULTI', 'E_DEUX_SUR_QUATRE', 'E_SUPER_PICK5', 'EB5',
      ]) {
        expect(attendu.values.contains(exotique), isFalse,
            reason: '$exotique est un pari DIFFÉRENT : jamais revendiqué');
      }
    });

    test('C1/0.3 les variantes par combinaison couvrent ordre et désordre', () {
      // L'exigence dit : « notamment ordre et désordre ». On vérifie donc
      // que CHAQUE type qui les distingue les déclare bien.
      expect(variantesIdentifiablesParCombinaison(TypePariJoue.coupleOrdre),
          <VarianteRapport>{VarianteRapport.ordre});
      expect(variantesIdentifiablesParCombinaison(TypePariJoue.tierceOrdre),
          <VarianteRapport>{VarianteRapport.ordre});
      expect(variantesIdentifiablesParCombinaison(TypePariJoue.tierceDesordre),
          <VarianteRapport>{VarianteRapport.desordre});
      // Tiercé et Quarté+ génériques admettent LES DEUX.
      for (final t in <TypePariJoue>[TypePariJoue.tierce, TypePariJoue.quarte]) {
        final v = variantesIdentifiablesParCombinaison(t);
        expect(v.contains(VarianteRapport.ordre), isTrue, reason: t.name);
        expect(v.contains(VarianteRapport.desordre), isTrue, reason: t.name);
      }
      // Quinté+ admet en plus `tirelire` — comme CANDIDAT CONCURRENT, pour
      // rendre l'ambiguïté visible, jamais comme gain autonome.
      expect(
          variantesIdentifiablesParCombinaison(TypePariJoue.quinte)
              .contains(VarianteRapport.tirelire),
          isTrue);
      // Types sans notion d'ordre : une seule variante, `sansVariante`.
      expect(variantesIdentifiablesParCombinaison(TypePariJoue.simpleGagnant),
          <VarianteRapport>{VarianteRapport.sansVariante});
      expect(variantesIdentifiablesParCombinaison(TypePariJoue.couplePlace),
          <VarianteRapport>{VarianteRapport.sansVariante});
      // Type inconnu : AUCUNE variante.
      expect(variantesIdentifiablesParCombinaison(TypePariJoue.inconnu),
          isEmpty);
    });

    test('C1/0.4 la taille de combinaison attendue est celle du référentiel',
        () {
      const attendu = <TypePariJoue, int?>{
        TypePariJoue.simpleGagnant: 1,
        TypePariJoue.simplePlace: 1,
        TypePariJoue.gagnantPlace: 1,
        TypePariJoue.coupleGagnant: 2,
        TypePariJoue.couplePlace: 2,
        TypePariJoue.coupleOrdre: 2,
        TypePariJoue.coupleDesordre: 2,
        TypePariJoue.tierce: 3,
        TypePariJoue.tierceOrdre: 3,
        TypePariJoue.tierceDesordre: 3,
        TypePariJoue.quarte: 4,
        TypePariJoue.quinte: 5,
        TypePariJoue.inconnu: null,
      };
      for (final e in attendu.entries) {
        expect(tailleCombinaisonAttendue(e.key), e.value,
            reason: 'taille de ${e.key.name}');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C1/1 — LA PERTE DÉMONTRÉE, TYPE PAR TYPE
  //
  //  ⚠️ LACUNE L1 / L2 COMBLÉE ICI. `_dansPerimetrePerteDemontree` déclare
  //     `couplePlace` DANS le périmètre, et aucun test n'assertait la perte
  //     d'un Couplé Placé. C'est une promesse de code non épinglée.
  // ═════════════════════════════════════════════════════════════════════════
  group('C1/1 — perte démontrée (types du périmètre du moteur)', () {
    test('C1/1.1 Simple Gagnant hors du 1er ⇒ perdu', () {
      // Témoin de non-régression : déjà couvert par b4_7/A1-1, rejoué ici
      // pour que ce fichier soit auto-suffisant sur le périmètre.
      final v = jouer('Simple Gagnant', <int>[15], 10, etatReel());
      expect(v.etat, EtatGain.perdu);
      expect(v.total, 0.0);
    });

    test('C1/1.2 Simple Placé hors des rangs payables ⇒ perdu', () {
      // Le 12 est 7e de l'arrivée : hors des 3 rangs payables du Placé.
      final v = jouer('Simple Placé', <int>[12], 10, etatReel());
      expect(v.etat, EtatGain.perdu);
    });

    test('C1/1.3 Couplé Gagnant sur une paire qui n\'est pas celle de tête '
        '⇒ perdu', () {
      // Témoin : c'est A1/3 de b4_7, la régression qui a motivé le
      // périmètre restreint de la preuve de participation.
      final v = jouer('Couplé Gagnant', <int>[1, 2], 10, etatReel());
      expect(v.etat, EtatGain.perdu);
    });

    test('★ C1/1.4 LACUNE L1 COMBLÉE — Couplé Placé sur une paire HORS du '
        'top 3 ⇒ perdu', () {
      // MESURE QUI A MOTIVÉ CE TEST : `grep "Couplé Placé" test/*.dart |
      // grep -i perdu` rend ZÉRO ligne. Or `_dansPerimetrePerteDemontree`
      // retourne `true` pour `couplePlace`. La promesse du code n'était donc
      // épinglée par AUCUN test.
      //
      // La paire 1-12 : le 1 est 5e, le 12 est 7e. Aucun des deux n'est dans
      // le top 3, donc aucune ligne du bloc `E_COUPLE_PLACE` (dont les
      // combinaisons sont des paires du top 3) ne peut les contenir.
      final v = jouer('Couplé Placé', <int>[1, 12], 10, etatReel());
      expect(v.etat, EtatGain.perdu,
          reason: 'la perte d\'un Couplé Placé dont AUCUN cheval n\'est dans '
              'le top 3 est démontrée par recoupement avec l\'arrivée');
    });

    test('C1/1.5 Couplé Placé sur une paire PARTIELLEMENT dans le top 3 '
        '⇒ perdu', () {
      // Le 9 est 1er (donc dans le top 3), le 12 est 7e. La paire 9-12 n'est
      // publiée par AUCUNE ligne : le bloc est complet et ne la contient pas.
      // Un cheval joué présent dans l'arrivée prouve sa participation — la
      // perte est donc démontrable sans table de statuts.
      final v = jouer('Couplé Placé', <int>[9, 12], 10, etatReel());
      expect(v.etat, EtatGain.perdu);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C1/2 — VARIANTES ORDRE / DÉSORDRE : LE VERDICT RÉELLEMENT RENDU
  //
  //  ⚠️ LACUNE L2 COMBLÉE ICI. Ces types sont HORS du périmètre de perte
  //     démontrée du moteur (`_dansPerimetrePerteDemontree` rend `false`),
  //     ce qui est correct : la perte y est prononcée par l'ARBITRE, sur
  //     l'arrivée. Ce qui manquait est le test du verdict RÉELLEMENT rendu.
  // ═════════════════════════════════════════════════════════════════════════
  group('C1/2 — variantes ordre et désordre', () {
    test('C1/2.1 Tiercé Ordre dans l\'ordre exact ⇒ attribué au rapport Ordre',
        () {
      // Bloc réel : Ordre @ 477,40 €. Mise 2 € ⇒ 954,80 €.
      final v = jouer('Tiercé Ordre', <int>[9, 4, 15], 2, etatReel());
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.ordre);
      expect(v.composantes.single.pourUnEuro, 477.40);
      expect(v.total, closeTo(954.80, 1e-9));
    });

    test('C1/2.2 Tiercé Désordre : le rapport Désordre paie, jamais l\'Ordre',
        () {
      // Bloc réel : Désordre @ 80,30 €. Mise 2 € ⇒ 160,60 €.
      final v = jouer('Tiercé Désordre', <int>[9, 4, 15], 2, etatReel());
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.desordre);
      expect(v.composantes.single.pourUnEuro, 80.30);
      expect(v.total, closeTo(160.60, 1e-9));
    });

    test('C1/2.3 Tiercé Ordre sur un ordre FAUX ⇒ la variante déclarée est '
        'respectée : aucun rapport Ordre, donc refus ou perte, JAMAIS le '
        'Désordre', () {
      // Le ticket joue 4-9-15 (inversé). Le bloc publie un Désordre 9-4-15.
      // Si le moteur rabattait un Tiercé Ordre sur le Désordre, l'utilisateur
      // serait payé pour un ordre qu'il n'a pas joué : c'est le défaut que
      // la variante déclarée interdit.
      final v = jouer('Tiercé Ordre', <int>[4, 9, 15], 2, etatReel());
      expect(v.etat, isNot(EtatGain.attribue),
          reason: 'un Tiercé Ordre faux ne doit JAMAIS toucher le Désordre');
    });

    test('★ C1/2.4 LACUNE L2 COMBLÉE — Couplé Ordre : promesse « exige l\'ordre '
        'exact » vérifiée sur le référentiel ET sur le comportement', () {
      // Référentiel : `exigeOrdreExact` n'est PAS exporté par le `show` de ce
      // fichier ; on vérifie donc la même propriété par ses EFFETS mesurables,
      // qui sont plus forts qu'un booléen : le code PMU et la variante.
      expect(codeApiPourType(TypePariJoue.coupleOrdre), 'E_COUPLE_ORDRE');
      expect(variantesIdentifiablesParCombinaison(TypePariJoue.coupleOrdre),
          <VarianteRapport>{VarianteRapport.ordre});
      // Et aucun code de repli n'existe : le Couplé Ordre ne peut pas
      // emprunter le bloc `E_COUPLE_GAGNANT` du Couplé Gagnant.
      expect(codeApiPourType(TypePariJoue.coupleOrdre),
          isNot(codeApiPourType(TypePariJoue.coupleGagnant)));

      // Comportement : la capture R1C6 ne publie AUCUN `E_COUPLE_ORDRE`
      // (mesuré : 11 courses sur 206 en publient un, pas celle-ci). Un
      // Couplé Ordre sur cette course ne peut donc pas être attribué par
      // ressemblance avec le Couplé Gagnant 9-4.
      final v = jouer('Couplé Ordre', <int>[9, 4], 2, etatReel());
      expect(v.etat, isNot(EtatGain.attribue),
          reason: 'aucun `E_COUPLE_ORDRE` publié ⇒ aucune attribution. Le '
              'Couplé Gagnant 9-4 de la même course ne doit JAMAIS servir de '
              'repli.');
    });

    test('C1/2.5 Couplé Désordre : rattaché au Couplé Gagnant, sans code '
        'inventé', () {
      // Décision du référentiel : le PMU ne publie pas de Couplé Désordre
      // distinct — le Couplé Gagnant EST le couplé sans ordre.
      expect(codeApiPourType(TypePariJoue.coupleDesordre), 'E_COUPLE_GAGNANT');
      expect(
          variantesIdentifiablesParCombinaison(TypePariJoue.coupleDesordre),
          <VarianteRapport>{VarianteRapport.sansVariante});
      // Le bloc réel publie 9-4 : la paire 9-4 jouée en Désordre paie.
      final v = jouer('Couplé Désordre', <int>[9, 4], 2, etatReel());
      expect(v.etat, EtatGain.attribue,
          reason: 'le Couplé Gagnant 9-4 publié EST le couplé sans ordre');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C1/3 — GAGNANT+PLACÉ : LA PERTE TOTALE
  //
  //  ⚠️ LACUNE L3 COMBLÉE ICI. Les tests existants couvrent le G+P gagnant
  //     (B3/6.1), partiel (B3/6.5) et mixte remboursé (b1_t12_p1 R3/R4).
  //     AUCUN ne dit ce que vaut un G+P dont AUCUNE composante n'est payable.
  // ═════════════════════════════════════════════════════════════════════════
  group('C1/3 — Gagnant+Placé, perte totale', () {
    test('★ C1/3.1 LACUNE L3 COMBLÉE — G+P sur un cheval hors de TOUT rang '
        'payable : aucune composante ne paie, total nul, jamais un gain', () {
      // Le 12 est 7e : ni gagnant (9), ni dans les 3 rangs du Placé.
      final v = jouerGagnantPlace(<int>[12], 10, 10, etatReel());
      expect(v.composantes, isEmpty,
          reason: 'aucune composante ne peut être payée');
      expect(v.total, 0.0);
      expect(v.aUnRemboursement, isFalse,
          reason: 'aucun remboursement n\'est établi sur cette course');
      // ⚠️ Le G+P est HORS du périmètre de perte démontrée : le moteur ne
      //    prononce pas `perdu` par recoupement, la perte du cheval joué
      //    n'étant prouvée que par son absence de l'arrivée — insuffisant.
      //    Ce qui est exigé ici, c'est qu'AUCUN gain ne soit inventé.
      expect(v.etat, isNot(EtatGain.attribue),
          reason: 'aucun euro ne doit être gagné sur un cheval hors de tout '
              'rang payable');
    });

    test('C1/3.2 G+P sur le gagnant : les DEUX composantes paient, chacune sa '
        'mise (témoin de non-régression de B3/6.1)', () {
      final v = jouerGagnantPlace(<int>[9], 10, 10, etatReel());
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.length, 2);
      // 10 × 7,50 = 75,0 et 10 × 3,00 = 30,0.
      expect(v.total, closeTo(105.0, 1e-9));
    });

    test('C1/3.3 G+P sur un cheval 3e : seule la composante Placé paie '
        '(témoin de non-régression de B3/6.5)', () {
      final v = jouerGagnantPlace(<int>[15], 10, 5, etatReel());
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.length, 1);
      expect(v.composantes.single.role.name, 'place');
      // 5 × 6,90 = 34,5.
      expect(v.total, closeTo(34.5, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C1/4 — INDÉTERMINÉ : AUCUNE PERTE INVENTÉE PAR SIMPLE ABSENCE
  //
  //  Exigence : « Les situations gagnantes, perdantes, remboursées, mixtes
  //  lorsque applicables, et indéterminées. » Ce groupe épingle l'indéterminé
  //  là où il est LÉGITIME de ne rien affirmer.
  // ═════════════════════════════════════════════════════════════════════════
  group('C1/4 — indétermination : jamais une perte déduite d\'une absence', () {
    test('C1/4.1 arrivée EXPLICITEMENT PROVISOIRE ⇒ aucune attribution', () {
      final v = jouer('Tiercé Ordre', <int>[9, 4, 15], 2,
          etatReel(definitive: false));
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.arriveeNonDefinitive);
      expect(v.total, 0.0);
    });

    test('C1/4.2 ★ CONTRAT B3/9.3 — le provisoire est GLOBAL, pas limité au '
        'Tiercé', () {
      // MESURE QUI CORRIGE MON PROPRE DIAGNOSTIC : j'avais soupçonné une
      // anomalie « Tiercé Ordre attribué sur arrivée provisoire ». Lecture du
      // code : la garde est posée AVANT tout aiguillage de type
      // (moteur_gain_pmu.dart:638, `if (etat.estProvisoire)`) puis une seconde
      // fois dans l'arbitre (arbitre_variante_pmu.dart:466). Elle ne dépend
      // donc PAS du passage par l'arbitre de l'arrivée. Aucune anomalie.
      // Elle est vérifiée ici sur les DEUX familles de types.
      for (final libelle in <String>[
        'Tiercé Ordre', 'Tiercé Désordre', 'Tiercé',
        'Quarté+', 'Quinté+', 'Simple Gagnant', 'Simple Placé',
        'Couplé Gagnant', 'Couplé Placé', 'Couplé Ordre',
      ]) {
        final numeros = tailleCombinaisonAttendue(typePariDepuisLibelle(libelle))!;
        final v = jouer(libelle, List<int>.generate(numeros, (i) => i + 1), 2,
            etatReel(definitive: false));
        expect(v.etat, EtatGain.nonDetermine,
            reason: '« $libelle » sur arrivée provisoire');
        expect(v.motif, MotifNonDetermination.arriveeNonDefinitive,
            reason: '« $libelle » : le motif doit nommer l\'arrivée provisoire');
      }
    });

    test('C1/4.3 ★ MESURE OPPOSÉE À MON INTUITION — `arriveeDefinitive: null` '
        'n\'est PAS provisoire : B3/9.3 est préservé', () {
      // J'avais asserté `nonDetermine` ici. C'était FAUX, et B3/9.3
      // (b3_moteur_gain_pmu_test.dart:723-728) verrouille explicitement le
      // contraire : « drapeau définitif ABSENT (null) ⇒ l'arrivée n'est pas
      // tenue pour provisoire ». `estProvisoire` est `== false`, et non
      // `!= true` : `null` signifie « non renseigné », jamais « provisoire ».
      // Une attribution reste possible sur un rapport officiel explicite.
      final v = jouer('Simple Gagnant', <int>[9], 10,
          etatReel(definitive: null));
      expect(v.etat, EtatGain.attribue,
          reason: 'B3/9.3 : `null` n\'est pas `false`. Le rapport officiel '
              '« E_SIMPLE_GAGNANT 9 » est explicite et applicable.');
      expect(v.total, closeTo(75.0, 1e-9));
    });

    test('C1/4.4 arrivée RÉELLEMENT ABSENTE ⇒ aucune perte prononcée', () {
      // ⚠️ Le scénario négatif est désormais EXPRIMABLE : `_Arrivee.absente()`
      //    transmet `null` sans aucun repli.
      //
      // ★ MESURE DEMANDÉE — « Recherche toi-même dans les chemins de production
      //   si `arriveeGroupes: null` peut réellement être transmis au moteur. »
      //   RÉPONSE, mesurée par lecture des deux seuls constructeurs de
      //   `ResultatOfficielCourse` :
      //     • `chargerResultatOfficielCourse` (branchement_verdict_course.dart:180)
      //       rend `null` si `ZoneTurfService.chargerResultatsCourseComplet`
      //       rend `null` ; or ce dernier rend `null` quand aucun classement
      //       n'est disponible (zone_turf_service.dart:1076) et sinon fournit
      //       `List<List<int>>.unmodifiable(groupes)` NON VIDE (l.1097) ;
      //     • `resultatOfficielDepuisSuivi` (branchement_verdict_course.dart:695)
      //       commence par `if (ticket.arriveeGroupes == null) return null;`.
      //   CONCLUSION MESURÉE : aucun chemin de production ne transmet
      //   aujourd'hui `arriveeGroupes: null` au moteur. Ce test n'épingle donc
      //   pas un scénario atteignable en production : il épingle la ROBUSTESSE
      //   défensive exigée par la consigne (« le moteur doit gérer correctement
      //   une donnée absente »), et il est le témoin de non-vacuité du harnais.
      final v = jouer(
        'Simple Gagnant',
        <int>[15],
        10,
        etatReel(arrivee: const _Arrivee.absente(), definitive: true),
      );
      expect(v.etat, EtatGain.nonDetermine,
          reason: 'sans arrivée, aucune perte ne peut être démontrée par '
              'recoupement');
      expect(v.etat, isNot(EtatGain.perdu),
          reason: 'une absence d\'arrivée ne doit JAMAIS devenir une défaite');
      expect(v.total, 0.0);
      expect(v.aUnRemboursement, isFalse,
          reason: 'une absence ne doit pas non plus fabriquer un '
              'remboursement');
    });

    test('C1/4.8 témoin de non-vacuité : le même ticket AVEC arrivée donne un verdict '
        'DIFFÉRENT — preuve que le test C1/4.4 mesure bien l\'absence', () {
      // Témoin de NON-VACUITÉ exigé par la consigne (« Le test doit démontrer
      // qu'aucune valeur de repli ne masque le scénario négatif ») : le MÊME
      // ticket, la MÊME liste de rapports, la seule différence étant la
      // présence de l'arrivée, doit changer de verdict. Sans ce témoin, un
      // harnais défaillant pourrait rendre C1/4.4 vert par accident.
      final avecAbsence = jouer(
        'Simple Gagnant',
        <int>[15],
        10,
        etatReel(arrivee: const _Arrivee.absente(), definitive: true),
      );
      final avecArrivee = jouer(
        'Simple Gagnant',
        <int>[15],
        10,
        etatReel(definitive: true),
      );
      expect(avecAbsence.etat, EtatGain.nonDetermine);
      expect(avecArrivee.etat, EtatGain.perdu,
          reason: 'le 15 est 3e : sa perte est démontrée par recoupement');
      expect(avecAbsence.etat, isNot(avecArrivee.etat),
          reason: 'si ces deux états étaient égaux, le harnais ne '
              'distinguerait pas l\'absence de la présence');
    });

    test('C1/4.5 type NON RÉPERTORIÉ ⇒ aucun calcul financier', () {
      final v = jouer('Trio', <int>[9, 4, 15], 10, etatReel());
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.typeNonRepertorie);
      expect(v.total, 0.0);
    });

    test('C1/4.6 mise NULLE ⇒ indéterminé, jamais « perdu »', () {
      final v = jouer('Simple Gagnant', <int>[9], 0, etatReel());
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.total, 0.0,
          reason: 'un gain de 0 € sur une mise de 0 € n\'est pas une perte '
              'établie');
    });

    test('C1/4.7 rapport officiel EXPLICITE et applicable ⇒ résolution même '
        'sans arrivée (carve-out de l\'arbitrage)', () {
      // L'arbitrage l'exige : « Un rapport officiel explicite, définitif et
      // suffisant peut toutefois permettre une résolution sans arrivée
      // complète. » Le Simple Gagnant 9 est publié ; le ticket joue 9.
      final v = jouer(
        'Simple Gagnant',
        <int>[9],
        10,
        etatReel(arrivee: const _Arrivee.absente(), definitive: true),
      );
      expect(v.etat, EtatGain.attribue,
          reason: 'le rapport officiel « E_SIMPLE_GAGNANT 9 » est explicite : '
              '10 × 7,50 = 75,0 doit être attribué');
      expect(v.total, closeTo(75.0, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C1/5 — LE CONVERTISSEUR DE VARIANTES, DANS LES DEUX SENS
  //
  //  ⚠️ Le libellé est l'AUTORITÉ de la variante (décision b4_7 anomalie 3) :
  //     Ordre et Désordre publient la MÊME combinaison, donc déduire la
  //     variante de l'arrivée était le défaut.
  // ═════════════════════════════════════════════════════════════════════════
  group('C1/5 — varianteDepuisLibelle', () {
    test('C1/5.1 les libellés Ordre rendent `ordre`, les Désordre `desordre`',
        () {
      const attendu = <String, VarianteRapport>{
        'e-Tiercé Ordre': VarianteRapport.ordre,
        'e-Tiercé Désordre': VarianteRapport.desordre,
        'e-Couplé Ordre': VarianteRapport.ordre,
        'e-Quarté+ Ordre': VarianteRapport.ordre,
        'e-Quarté+ Désordre': VarianteRapport.desordre,
        'e-Quinté+ Ordre': VarianteRapport.ordre,
        'e-Quinté+ Désordre': VarianteRapport.desordre,
        'e-Simple Gagnant': VarianteRapport.sansVariante,
        'e-Simple Placé': VarianteRapport.sansVariante,
        'e-Couplé Gagnant': VarianteRapport.sansVariante,
        'e-Couplé Placé': VarianteRapport.sansVariante,
      };
      for (final e in attendu.entries) {
        expect(varianteDepuisLibelle(e.key), e.value,
            reason: 'libellé « ${e.key} »');
      }
    });

    test('C1/5.2 les Bonus et la Tirelire sont reconnus SÉPARÉMENT', () {
      // Sans cette reconnaissance, un Bonus serait lu comme un Ordre — ou
      // l'inverse : deux façons de payer un même ticket.
      expect(varianteDepuisLibelle('e-Bonus'), VarianteRapport.bonusQuarte);
      expect(varianteDepuisLibelle('e-Bonus 4sur5'),
          VarianteRapport.bonus4sur5);
      expect(varianteDepuisLibelle('e-Bonus 3'), VarianteRapport.bonus3);
      expect(varianteDepuisLibelle('e-Quinté+ Ordre + Tirelire'),
          VarianteRapport.tirelire);
    });

    test('C1/5.3 les rapports non-partants sont reconnus, pas assimilés', () {
      expect(varianteDepuisLibelle('e-Simple Placé 1 NP'),
          VarianteRapport.nonPartant);
      expect(varianteDepuisLibelle('e-Simple Placé 2 NP'),
          VarianteRapport.nonPartant);
    });

    test('C1/5.4 un libellé VIDE ou illisible rend `illisible` : on ne '
        'suppose RIEN', () {
      expect(varianteDepuisLibelle(''), VarianteRapport.illisible);
      expect(varianteDepuisLibelle('   '), VarianteRapport.illisible);
    });
  });
}
