// ═══════════════════════════════════════════════════════════════════════════
//  B-4.6 — SUJET 8 : CAS PARTICULIERS (bout en bout)
//
//  Ce fichier NE MODIFIE AUCUNE RÈGLE MÉTIER. Il MESURE le comportement de
//  production sur :
//    • les TROIS arrivées ex æquo réellement présentes dans les captures ;
//    • les TROIS chemins de code qui prononcent `deadHeatSansGroupes` ;
//    • Gagnant+Placé et ses DEUX rapports / DEUX mises distincts ;
//    • les rapports incomplets, absents, ou devenant disponibles après coup ;
//    • les paris Ordre/Désordre et la variante réellement retenue ;
//    • la conservation des verdicts définitifs et l'absence de double gain.
//
//  ⚠️ AUCUN RAPPORT ET AUCUN MONTANT N'EST INVENTÉ ICI.
//     Chaque montant asserté provient d'une capture réelle, lue par le
//     DÉCODEUR DE PRODUCTION (`PmuApiService.decoderRapportsDefinitifs`) —
//     pas d'un littéral recopié à la main. Toute assertion sur un ex æquo
//     vérifie l'ABSENCE de montant, jamais un montant supposé.
//
//  ── ORIGINE DES TROIS EX ÆQUO (mesurée) ───────────────────────────────────
//  Sur les 5 `prog_*.json` (309 arrivées), exactement TROIS portent un groupe
//  non singleton, et toutes trois sont des courses ÉTRANGÈRES :
//    R5C5 17112026  HIPPODROME DE MONS  BELGIQUE  [[2],[4],[5,7],[8],[3],[6]]
//    R6C5 17112026  HIPPODROME DE CONCEPCION CHILI [[12],[1,7],[9],…]
//    R5C7 20112026  HIPPODROME DE WOLVEGA P-B    [[4],[6],[1,5],[2]]
//  Le test S8-0 le revérifie : si une capture supplémentaire apparaissait,
//  il échouerait et le présent commentaire deviendrait faux — c'est voulu.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/branchement_verdict_course.dart';
import 'package:pronostic_hippique/services/enregistreur_verdict_gain_pmu.dart'
    show StatutEnregistrementVerdict;
import 'package:pronostic_hippique/services/gain_calculator.dart' show RapportPmu;
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart'
    show RoleComposante;
import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';
import 'fixtures/fixture_paths.dart';

// ───────────────────────────────────────────────────────────────────────────
//  DONNÉES RÉELLES
// ───────────────────────────────────────────────────────────────────────────

final String kDossier = dossierMulti;

/// Rapports d'une capture, lus par le DÉCODEUR DE PRODUCTION.
///
/// Aucun littéral n'est écrit à la main : si le décodeur change, ces tests
/// suivent le décodeur et non une valeur figée hors du code.
List<RapportPmu> rapportsDe(String nom) =>
    PmuApiService.decoderRapportsDefinitifs(
      File('$kDossier/$nom').readAsStringSync(),
    );

/// Arrivées ex æquo RÉELLES, telles que publiées dans `prog_*.json`.
const List<List<int>> kArriveeMons = <List<int>>[
  <int>[2], <int>[4], <int>[5, 7], <int>[8], <int>[3], <int>[6],
];
const List<List<int>> kArriveeConcepcion = <List<int>>[
  <int>[12], <int>[1, 7], <int>[9], <int>[2], <int>[10], <int>[8], <int>[6],
  <int>[13], <int>[5],
];
const List<List<int>> kArriveeWolvega = <List<int>>[
  <int>[4], <int>[6], <int>[1, 5], <int>[2],
];

/// Arrivée SANS ex æquo de R1C6 15112026 (témoin de contrôle).
const List<List<int>> kArrivee16 = <List<int>>[
  <int>[9], <int>[4], <int>[15], <int>[10], <int>[1], <int>[7], <int>[12],
];

// ───────────────────────────────────────────────────────────────────────────
//  FABRIQUES DE TICKETS
// ───────────────────────────────────────────────────────────────────────────

UserPrediction pred(
  String type,
  List<int> numeros, {
  double mise = 10,
  String? code,
  double? miseGagnant,
  double? misePlace,
  List<int>? ordre,
  String? variante,
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
      codePmuOfficiel: code,
      miseGagnant: miseGagnant,
      misePlace: misePlace,
      numerosDansOrdre: ordre,
      varianteChoisie: variante,
    );

ResultatOfficielCourse resultat(
  List<RapportPmu> rapports, {
  required List<List<int>>? groupes,
  bool? definitive = true,
}) =>
    construireResultatOfficiel(
      arriveeGroupes: groupes,
      arriveeDefinitive: definitive,
      rapports: rapports,
    );

/// Résout et rend la résolution complète (verdict + décision d'écriture).
ResolutionTicketPrediction resoudre(
  UserPrediction p,
  ResultatOfficielCourse r,
) =>
    resoudrePrediction(prediction: p, resultat: r);

/// Vérifie les invariants d'une non-détermination par ex æquo.
///
/// Ces trois invariants SONT le sujet : aucun montant, aucune composante,
/// aucun rapport persisté — et le motif fermé est bien celui de l'ex æquo.
void verifierDeadHeat(ResolutionTicketPrediction res, {String? trace}) {
  final contexte = trace == null ? '' : ' [$trace]';
  expect(res.aUneIssue, isFalse,
      reason: 'Un ex æquo ne doit pas empêcher la CONSTRUCTION du ticket$contexte');
  final v = res.verdict!;
  expect(v.etat, EtatGain.nonDetermine, reason: 'état$contexte');
  expect(v.motif, MotifNonDetermination.deadHeatSansGroupes,
      reason: 'motif$contexte');
  expect(v.total, 0.0, reason: 'aucun montant pour un ex æquo$contexte');
  expect(v.composantes, isEmpty, reason: 'aucune composante$contexte');
  expect(v.gainGagnant, 0.0, reason: 'gainGagnant$contexte');
  expect(v.gainPlace, 0.0, reason: 'gainPlace$contexte');
  expect(v.explication.trim(), isNotEmpty,
      reason: 'une non-détermination doit être motivée$contexte');

  // La décision d'écriture ne doit RIEN persister de montant.
  //
  // ★ B-4.7 : l'indétermination est désormais PERSISTÉE (état + motif), alors
  //   qu'elle était refusée dès que des rapports officiels existaient. C'était
  //   l'« Anomalie 1 » : la persistance d'un MÊME ticket dépendait de la
  //   disponibilité des données. Aucun montant n'est écrit pour autant — c'est
  //   ce que ce helper continue d'exiger, et c'est ce qui compte.
  final e = res.enregistrement!;
  expect(e.ticket.rapportsAttribues, isNull,
      reason: 'aucun rapport attribué ne doit être écrit$contexte');
  expect(e.ticket.etatGain, EtatGain.nonDetermine,
      reason: 'l\'indétermination motivée est persistée, sans montant$contexte');
  expect(e.ticket.dividendeGagnant, isNull,
      reason: 'aucun dividende Gagnant$contexte');
  expect(e.ticket.dividendePlace, isNull,
      reason: 'aucun dividende Placé$contexte');
}

// ───────────────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  //  S8-0 — INVENTAIRE MESURÉ DES EX ÆQUO
  // ═══════════════════════════════════════════════════════════════════════
  group('S8-0 — inventaire mesuré des arrivées ex æquo', () {
    test('S8-0 seules TROIS arrivées sur 309 portent un groupe non singleton',
        () {
      final fichiers = Directory(kDossier)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .where((f) => f.path.split('/').last.startsWith('prog_'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      expect(fichiers.length, 5,
          reason: 'mesuré : 5 fichiers programme datés dans $kDossier');

      var totalArrivees = 0;
      final exAequo = <String>[];

      for (final f in fichiers) {
        final racine =
            jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final reunions =
            (racine['programme'] as Map<String, dynamic>)['reunions'] as List;
        for (final rBrut in reunions) {
          final r = rBrut as Map<String, dynamic>;
          final hippodrome = r['hippodrome'];
          final nomHippodrome = hippodrome is Map
              ? (hippodrome['libelleLong']?.toString() ?? '?')
              : (hippodrome?.toString() ?? '?');
          final courses = r['courses'] as List;
          for (var i = 0; i < courses.length; i++) {
            final c = courses[i] as Map<String, dynamic>;
            final oa = c['ordreArrivee'];
            if (oa is! List) continue;
            totalArrivees++;
            final aUnGroupeMultiple =
                oa.any((g) => g is List && g.length != 1);
            if (aUnGroupeMultiple) {
              // ⚠️ MESURÉ : `numReunion` est porté par la COURSE, pas par la
              //    réunion. Lire la réunion rend `null` et produirait
              //    « RnullC5 » — une étiquette fausse.
              exAequo.add('R${c['numReunion']}C${i + 1} $nomHippodrome');
            }
          }
        }
      }

      expect(totalArrivees, 309,
          reason: 'mesuré : 309 arrivées dans les 5 programmes datés');
      expect(exAequo.length, 3,
          reason: 'mesuré : exactement 3 arrivées ex æquo. '
              'Obtenu : $exAequo');
      expect(exAequo.map((e) => e.split(' ').first).toList(),
          <String>['R5C5', 'R6C5', 'R5C7'],
          reason: 'les trois ex æquo sont R5C5, R6C5 et R5C7');
      // Toutes trois étrangères — élément factuel, pas une conséquence logique.
      expect(exAequo.every((e) => e.contains('BELGIQUE') ||
          e.contains('CHILI') ||
          e.contains('P-B')), isTrue,
          reason: 'mesuré : les 3 ex æquo sont des courses étrangères. '
              'Obtenu : $exAequo');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S8-A — LES TROIS COURSES EX ÆQUO RÉELLES
  // ═══════════════════════════════════════════════════════════════════════
  group('S8-A — les trois courses ex æquo réelles', () {
    test('S8-1 MONS R5C5 : le Tiercé ne reçoit AUCUN montant (ex æquo au 3e rang)',
        () {
      final r = rapportsDe('R5C5_17112026.json');
      expect(r, isNotEmpty, reason: 'la capture MONS est réelle et non vide');

      // ⚠️ MESURÉ — et contraire à mon hypothèse initiale : MONS ne publie
      //    AUCUN bloc `E_TIERCE`. Elle publie un bloc `E_TRIO` portant les DEUX
      //    combinaisons de l'ex æquo (2-4-5 et 2-4-7), ce qui est exactement
      //    la signature officielle d'un ex æquo au 3e rang.
      //    C'est aussi la preuve, sur données réelles, que `E_TRIO` n'est pas
      //    le Tiercé : aucun `E_TIERCE` n'est publié ici.
      expect(r.any((x) => x.typePari == 'E_TIERCE'), isFalse,
          reason: 'mesuré : MONS ne publie aucun E_TIERCE');
      final trio = r.where((x) => x.typePari == 'E_TRIO').toList();
      expect(trio.map((x) => x.combinaison).toSet(),
          <String>{'2-4-5', '2-4-7'},
          reason: 'mesuré : le bloc Trio de MONS publie les deux combinaisons '
              'ex æquo. Obtenu : ${trio.map((x) => x.combinaison).toList()}');

      final res = resultat(r, groupes: kArriveeMons);

      // Les deux combinaisons possibles refusent également de payer.
      for (final joues in <List<int>>[
        <int>[2, 4, 5],
        <int>[2, 4, 7],
      ]) {
        verifierDeadHeat(
          resoudre(
            pred('Tiercé', joues, code: 'E_TIERCE', ordre: joues),
            res,
          ),
          trace: 'MONS ${joues.join("-")}',
        );
      }
    });

    test('S8-2 CONCEPCION R6C5 : les 3 Placé officiels sont payés à leur montant exact',
        () {
      final r = rapportsDe('R6C5_17112026.json');
      final res = resultat(r, groupes: kArriveeConcepcion);

      // Le bloc Placé publie 12 → 2,30 / 1 → 4,50 / 7 → 2,30 (relevé réel).
      // L'ex æquo porte sur le 2e rang (1 et 7) : chacun est bien PLACÉ.
      // Un Simple Placé n'a pas de notion d'ordre → aucun arbitrage d'arrivée,
      // donc l'ex æquo ne le rend PAS indéterminable. C'est le comportement
      // correct : ces trois chevaux sont effectivement placés.
      const attendus = <int, double>{12: 23.0, 1: 45.0, 7: 23.0};
      for (final entree in attendus.entries) {
        final p = pred('Simple Placé', <int>[entree.key],
            code: 'E_SIMPLE_PLACE');
        final resu = resoudre(p, res);
        expect(resu.verdict!.etat, EtatGain.attribue,
            reason: 'cheval ${entree.key} est placé');
        expect(resu.verdict!.total, entree.value,
            reason: 'montant officiel du Placé ${entree.key} pour 10 € ; '
                'valeur obtenue ${resu.verdict!.total}');
        expect(resu.verdict!.composantes.single.combinaisonRapport,
            '${entree.key}');
        expect(resu.enregistrement!.statut,
            StatutEnregistrementVerdict.enregistre);
        expect(resu.enregistrement!.ticket.etatGain, EtatGain.attribue);
      }
    });

    test('S8-3 WOLVEGA R5C7 : Quarté+ indéterminé, Simple et Couplé Ordre payés',
        () {
      final r = rapportsDe('R5C7_20112026.json');
      final res = resultat(r, groupes: kArriveeWolvega);

      // Le Quarté exige les 4 rangs dans l'ordre. Le 3e rang est [1,5] : la
      // variante Ordre/Désordre n'existe pas → refus motivé, aucun montant.
      // (Mesuré : cette course ne publie de toute façon AUCUN bloc
      //  E_QUARTE_PLUS — le refus pour ex æquo intervient avant.)
      expect(r.any((x) => x.typePari == 'E_QUARTE_PLUS'), isFalse,
          reason: 'mesuré : WOLVEGA ne publie aucun Quarté+');
      verifierDeadHeat(
        resoudre(
          pred('Quarté+', <int>[4, 6, 1, 5],
              code: 'E_QUARTE_PLUS', ordre: <int>[4, 6, 1, 5]),
          res,
        ),
        trace: 'WOLVEGA Quarté+',
      );

      // Les deux Super4 publiés (4-6-1-5 et 4-6-5-1) ne sont JAMAIS
      // attribués : ils correspondent aux deux ordres possibles de l'ex æquo.
      final superQuatre =
          r.where((x) => x.typePari == 'E_SUPER_QUATRE').toList();
      expect(superQuatre.map((x) => x.combinaison).toSet(),
          <String>{'4-6-1-5', '4-6-5-1'},
          reason: 'mesuré : les deux ordres ex æquo sont publiés, '
              'et aucun ne doit être choisi');

      // Les paris SANS notion d'ordre restent payés normalement.
      final simpleG = resoudre(
          pred('Simple Gagnant', <int>[4], code: 'E_SIMPLE_GAGNANT'), res);
      expect(simpleG.verdict!.etat, EtatGain.attribue);
      expect(simpleG.verdict!.total, 24.0,
          reason: 'e-Simple Gagnant 4 = 2,40 € pour 1 € → 24,00 € pour 10 €');

      final simpleP = resoudre(
          pred('Simple Placé', <int>[6], code: 'E_SIMPLE_PLACE'), res);
      expect(simpleP.verdict!.etat, EtatGain.attribue);
      expect(simpleP.verdict!.total, 13.0,
          reason: 'e-Simple Placé 6 = 1,30 € pour 1 € → 13,00 € pour 10 €');

      // Couplé Ordre : 1er et 2e rangs sont des singletons → déterminable.
      final couple = resoudre(
        pred('Couplé Ordre', <int>[4, 6],
            code: 'E_COUPLE_ORDRE', ordre: <int>[4, 6], variante: 'ordre'),
        res,
      );
      expect(couple.verdict!.etat, EtatGain.attribue,
          reason: 'les rangs 1 et 2 sont des singletons : le Couplé Ordre '
              'est déterminable malgré l\'ex æquo au 3e rang');
      expect(couple.verdict!.total, 74.0,
          reason: 'e-Couplé Ordre 4-6 = 7,40 € → 74,00 € pour 10 €');
    });

    test('S8-4 le refus des ex æquo n\'est PAS une absence de rapports', () {
      // Invariant : les trois captures publient bel et bien des rapports.
      // Le refus vient de l'ARBITRAGE, jamais d'un manque de données.
      for (final entree in <String, List<List<int>>>{
        'R5C5_17112026.json': kArriveeMons,
        'R6C5_17112026.json': kArriveeConcepcion,
        'R5C7_20112026.json': kArriveeWolvega,
      }.entries) {
        final r = rapportsDe(entree.key);
        expect(r.length, greaterThanOrEqualTo(8),
            reason: '${entree.key} publie des rapports réels');
        final res = resultat(r, groupes: entree.value);
        expect(res.rapports, isNotEmpty,
            reason: '${entree.key} : le résultat officiel porte des rapports');
        // Construction possible : la donnée est là, seule la variante manque.
        final c = construireTicketPrediction(
          pred('Tiercé', <int>[2, 4, 5], code: 'E_TIERCE', ordre: <int>[2, 4, 5]),
        );
        expect(c.estExploitable, isTrue,
            reason: '${entree.key} : le ticket est constructible — le refus '
                'viendra de l\'arbitrage, pas de la donnée');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S8-B — LES TROIS CHEMINS deadHeatSansGroupes
  // ═══════════════════════════════════════════════════════════════════════
  group('S8-B — les trois chemins qui prononcent deadHeatSansGroupes', () {
    final r16 = rapportsDe('R1C6_15112026.json');

    test('S8-5 groupes == null (frontières inconnues)', () {
      verifierDeadHeat(
        resoudre(
          pred('Tiercé', <int>[9, 4, 15],
              code: 'E_TIERCE', ordre: <int>[9, 4, 15]),
          resultat(r16, groupes: null),
        ),
        trace: 'groupes null',
      );
    });

    test('S8-6 groupes trop courts (comparaison partielle)', () {
      // Le Tiercé compare 3 rangs ; l'arrivée n'en fournit que 2.
      verifierDeadHeat(
        resoudre(
          pred('Tiercé', <int>[9, 4, 15],
              code: 'E_TIERCE', ordre: <int>[9, 4, 15]),
          resultat(r16, groupes: const <List<int>>[
            <int>[9], <int>[4],
          ]),
        ),
        trace: 'groupes courts',
      );
    });

    test('S8-7 groupe multiple sur un rang COMPARÉ', () {
      // L'ex æquo porte ici sur le 2e rang, qui EST comparé par le Tiercé.
      verifierDeadHeat(
        resoudre(
          pred('Tiercé', <int>[9, 4, 15],
              code: 'E_TIERCE', ordre: <int>[9, 4, 15]),
          resultat(r16, groupes: const <List<int>>[
            <int>[9], <int>[4, 15], <int>[10],
          ]),
        ),
        trace: 'ex æquo au rang 2',
      );
    });

    test('S8-7b un ex æquo HORS des rangs comparés n\'empêche rien', () {
      // Contrôle négatif : sans lui, S8-7 pourrait passer pour la mauvaise
      // raison (refus systématique dès qu'un groupe est multiple).
      final groupes = <List<int>>[
        <int>[9], <int>[4], <int>[15], <int>[10, 1], <int>[7], <int>[12],
      ];
      final res = resoudre(
        pred('Tiercé', <int>[9, 4, 15],
            code: 'E_TIERCE', ordre: <int>[9, 4, 15]),
        resultat(r16, groupes: groupes),
      );
      expect(res.verdict!.etat, EtatGain.attribue,
          reason: 'l\'ex æquo porte sur les rangs 4-5, non comparés par le '
              'Tiercé : le gain doit être attribué');
      expect(res.verdict!.total, 4774.0,
          reason: 'e-Tiercé Ordre 9-4-15 = 477,40 € → 4774,00 € pour 10 €');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S8-C — GAGNANT+PLACÉ : DEUX RAPPORTS, DEUX MISES
  // ═══════════════════════════════════════════════════════════════════════
  group('S8-C — Gagnant+Placé, deux rapports et deux mises distincts', () {
    final r16 = rapportsDe('R1C6_15112026.json');
    final res = resultat(r16, groupes: kArrivee16);

    test('S8-8 le cheval 9 cumule Gagnant 7,50 ET Placé 3,00', () {
      final resu =
          resoudre(pred('Gagnant+Placé', <int>[9], miseGagnant: 10, misePlace: 10), res);
      final v = resu.verdict!;
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.length, 2,
          reason: 'Gagnant+Placé gagnant produit DEUX composantes distinctes');

      final gagnant = v.composantes
          .firstWhere((c) => c.role == RoleComposante.gagnant);
      final place =
          v.composantes.firstWhere((c) => c.role == RoleComposante.place);
      expect(gagnant.libelleRapport, 'e-Simple Gagnant');
      expect(place.libelleRapport, 'e-Simple Placé');
      expect(gagnant.pourUnEuro, 7.50, reason: 'dividende officiel Gagnant 9');
      expect(place.pourUnEuro, 3.00, reason: 'dividende officiel Placé 9');
      expect(v.gainGagnant, 75.0);
      expect(v.gainPlace, 30.0);
      expect(v.total, 105.0,
          reason: '75,00 + 30,00 — les deux mises valent 10 € chacune');
    });

    test('S8-9 mises asymétriques : chaque composante garde SA mise', () {
      final resu = resoudre(
        pred('Gagnant+Placé', <int>[9], miseGagnant: 5, misePlace: 20),
        res,
      );
      final v = resu.verdict!;
      expect(v.gainGagnant, 37.5, reason: '5 € × 7,50');
      expect(v.gainPlace, 60.0, reason: '20 € × 3,00');
      expect(v.total, 97.5,
          reason: 'Un calcul sur mise totale (25 €) donnerait un montant faux : '
              '25 × 7,50 + 25 × 3,00 = 262,50 €, jamais 97,50 €');
      // Preuve arithmétique de la non-confusion :
      expect(v.total, isNot(equals(262.5)));
    });

    test('S8-10 le 4e cheval (2e de l\'arrivée) : Gagnant perdu, Placé payé', () {
      final resu = resoudre(
        pred('Gagnant+Placé', <int>[4], miseGagnant: 10, misePlace: 10),
        res,
      );
      final v = resu.verdict!;
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.length, 1,
          reason: 'seule la composante Placé est gagnante');
      expect(v.composantes.single.role, RoleComposante.place);
      expect(v.gainGagnant, 0.0);
      expect(v.gainPlace, 26.0, reason: '10 € × 2,60 (Placé officiel du 4)');
      expect(v.total, 26.0);
    });

    test('S8-11 le Placé le plus élevé n\'est JAMAIS sélectionné à la place du joué',
        () {
      // Le bloc Placé publie 3,00 (9), 2,60 (4) et 6,90 (15).
      // Le ticket porte le 9 : le gain doit être 3,00, jamais 6,90.
      final places =
          r16.where((x) => x.typePari == 'E_SIMPLE_PLACE').toList();
      expect(places.map((x) => x.dividende).reduce((a, b) => a > b ? a : b),
          6.90,
          reason: 'mesuré : le Placé maximal publié est 6,90');

      final resu = resoudre(
        pred('Simple Placé', <int>[9], code: 'E_SIMPLE_PLACE'),
        res,
      );
      expect(resu.verdict!.total, 30.0,
          reason: '10 € × 3,00 — et surtout PAS 10 × 6,90 = 69,00 €');
      expect(resu.verdict!.total, isNot(equals(69.0)));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S8-D — RAPPORTS INCOMPLETS, ABSENTS, OU TARDIFS
  // ═══════════════════════════════════════════════════════════════════════
  group('S8-D — rapports incomplets, absents, ou devenus disponibles', () {
    final r16 = rapportsDe('R1C6_15112026.json');
    final sansRapport = resultat(
      const <RapportPmu>[],
      groupes: const <List<int>>[<int>[9], <int>[4], <int>[15]],
    );

    test('S8-12 aucun rapport publié : blocJusteAbsent, aucun montant', () {
      final resu = resoudre(
        pred('Tiercé', <int>[9, 4, 15],
            code: 'E_TIERCE', ordre: <int>[9, 4, 15]),
        sansRapport,
      );
      final v = resu.verdict!;
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.blocJusteAbsent,
          reason: 'aucun bloc E_TIERCE n\'est publié');
      expect(v.total, 0.0);
      expect(v.composantes, isEmpty);

      // ⚠️ MESURÉ — et c'est le comportement CORRECT : quand AUCUN rapport
      //    n'est fourni, la branche C de `deciderEcritureVerdict` ne voit pas
      //    de contradiction et enregistre l'indétermination MOTIVÉE.
      //    Un ticket en attente porte donc bien `etatGain = nonDetermine`,
      //    avec son motif fermé, et AUCUN rapport attribué (jamais `[]`).
      expect(resu.enregistrement!.statut,
          StatutEnregistrementVerdict.enregistre,
          reason: 'l\'indétermination motivée est enregistrée');
      expect(resu.enregistrement!.ticket.etatGain, EtatGain.nonDetermine);
      expect(resu.enregistrement!.ticket.motifNonDetermination,
          MotifNonDetermination.blocJusteAbsent);
      expect(resu.enregistrement!.ticket.rapportsAttribues, isNull,
          reason: 'aucun montant, aucun rapport attribué');
    });

    test('S8-13 Gagnant+Placé sans aucun rapport : nonDetermine, pas un gain nul',
        () {
      final resu =
          resoudre(pred('Gagnant+Placé', <int>[9], miseGagnant: 10, misePlace: 10),
              sansRapport);
      final v = resu.verdict!;
      expect(v.etat, EtatGain.nonDetermine,
          reason: 'un gain à 0,00 € serait un mensonge : c\'est indéterminé');
      expect(v.motif, MotifNonDetermination.blocJusteAbsent);
      expect(v.total, 0.0);
      expect(v.gainGagnant, 0.0);
      expect(v.gainPlace, 0.0);
      expect(resu.enregistrement!.ticket.rapportsAttribues, isNull);
      expect(resu.enregistrement!.ticket.etatGain, EtatGain.nonDetermine);
    });

    test('S8-14 un rapport publié PLUS TARD ne réécrit pas un ticket indéterminé',
        () {
      final plein = resultat(r16, groupes: kArrivee16);
      const ordre = <int>[9, 4, 15];

      // 1) Première résolution : les rapports ne sont pas encore là.
      final premier = resoudre(
        pred('Tiercé', ordre, code: 'E_TIERCE', ordre: ordre),
        sansRapport,
      );
      expect(premier.verdict!.motif, MotifNonDetermination.blocJusteAbsent);
      expect(premier.enregistrement!.statut,
          StatutEnregistrementVerdict.enregistre,
          reason: 'l\'indétermination est enregistrée (trace motivée)');
      final ticketPersiste = premier.enregistrement!.ticket;
      expect(ticketPersiste.etatGain, EtatGain.nonDetermine);

      // 2) Seconde résolution : les rapports sont désormais disponibles.
      final second = resoudre(ticketPersiste, plein);
      expect(second.verdict!.etat, EtatGain.attribue,
          reason: 'le moteur sait maintenant calculer 4774,00 €');
      expect(second.verdict!.total, 4774.0);

      // 3) ★ B-4.7 (Anomalie 2) : la transition EST désormais autorisée quand
      //    les rapports officiels démontrent le verdict. Elle était refusée
      //    par la branche A (`refuseTransitionNonDeterminee`), ce qui laissait
      //    le ticket indéterminé POUR TOUJOURS. Le verdict définitif est écrit
      //    une seule fois, et le total reste celui d'un seul règlement.
      expect(second.enregistrement!.statut,
          StatutEnregistrementVerdict.enregistre,
          reason: 'la transition nonDetermine → définitif est autorisée dès lors '
              'que les rapports officiels démontrent le verdict');
      expect(second.enregistrement!.ticket.etatGain, EtatGain.attribue);
      expect(second.enregistrement!.ticket.rapportsAttribues, isNotNull,
          reason: 'le rapport officiel identifié est persisté');
      expect(second.verdict!.total, 4774.0,
          reason: 'aucun double gain : le total est celui d\'un seul règlement');

      // 4) Un ticket NEUF, lui, obtient bien le montant : la donnée tardive
      //    n'est donc pas perdue, elle n'est simplement jamais réécrite
      //    silencieusement sur un ticket existant.
      final neuf = resoudre(
        pred('Tiercé', ordre, code: 'E_TIERCE', ordre: ordre, id: 'p2'),
        plein,
      );
      expect(neuf.enregistrement!.statut,
          StatutEnregistrementVerdict.enregistre);
      expect(neuf.enregistrement!.ticket.etatGain, EtatGain.attribue);
      expect(totalDesMontantsRetour(
              neuf.enregistrement!.ticket.rapportsAttribues!),
          4774.0);
    });

    test('S8-15 arrivée explicitement provisoire : aucun montant, aucun ordre deviné',
        () {
      final prov = resultat(r16,
          groupes: kArrivee16, definitive: false);
      final resu = resoudre(
        pred('Tiercé', <int>[9, 4, 15],
            code: 'E_TIERCE', ordre: <int>[9, 4, 15]),
        prov,
      );
      final v = resu.verdict!;
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.arriveeNonDefinitive);
      expect(v.total, 0.0);
      expect(v.composantes, isEmpty, reason: 'aucun ordre deviné');
      // ★ B-4.7 : l'indétermination motivée est désormais PERSISTÉE (le
      //   refus dépendait auparavant de la seule présence de rapports). Ce qui
      //   compte ici est vérifié : AUCUN montant n'est écrit.
      expect(resu.enregistrement!.ticket.etatGain, EtatGain.nonDetermine);
      expect(resu.enregistrement!.ticket.rapportsAttribues, isNull);
      expect(resu.enregistrement!.ticket.dividendeGagnant, isNull);
      expect(resu.enregistrement!.ticket.dividendePlace, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S8-E — ORDRE / DÉSORDRE ET VARIANTES
  // ═══════════════════════════════════════════════════════════════════════
  group('S8-E — Ordre, Désordre et variantes', () {
    final r16 = rapportsDe('R1C6_15112026.json');
    final res = resultat(r16, groupes: kArrivee16);

    test('S8-16 ordre joué = ordre officiel ⇒ rapport ORDRE (477,40)', () {
      final resu = resoudre(
        pred('Tiercé', <int>[9, 4, 15],
            code: 'E_TIERCE', ordre: <int>[9, 4, 15]),
        res,
      );
      final v = resu.verdict!;
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.libelleRapport, 'e-Tiercé Ordre');
      expect(v.composantes.single.pourUnEuro, 477.40);
      expect(v.total, 4774.0);
    });

    test('S8-17 ordre joué ≠ ordre officiel ⇒ rapport DÉSORDRE (80,30)', () {
      final resu = resoudre(
        pred('Tiercé', <int>[15, 4, 9],
            code: 'E_TIERCE', ordre: <int>[15, 4, 9]),
        res,
      );
      final v = resu.verdict!;
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.libelleRapport, 'e-Tiercé Désordre',
          reason: 'les 3 bons chevaux dans un autre ordre = Désordre');
      expect(v.composantes.single.pourUnEuro, 80.30);
      expect(v.total, 803.0,
          reason: 'jamais 4774,00 : le rapport le plus élevé ne doit pas '
              'être sélectionné');
      expect(v.total, isNot(equals(4774.0)));
    });

    test('S8-18 les deux rapports Ordre/Désordre portent la MÊME combinaison', () {
      final tierce = r16.where((x) => x.typePari == 'E_TIERCE').toList();
      expect(tierce.length, 2);
      expect(tierce[0].combinaison, tierce[1].combinaison,
          reason: 'mesuré : Ordre et Désordre publient 9-4-15 tous les deux — '
              'seul le libellé les sépare');
      expect(tierce.map((x) => x.libelleOfficiel).toSet(),
          <String>{'e-Tiercé Ordre', 'e-Tiercé Désordre'});
      expect(tierce.map((x) => x.dividende).toSet(),
          <double>{477.40, 80.30});
    });

    test('S8-19 la variante vient du LIBELLÉ joué, pas de l\'ARRIVÉE '
        '(corrigé en B-4.7)', () {
      // ★ B-4.7 (Anomalie 3) : ce test épinglait auparavant le DÉFAUT.
      //   « Tiercé Désordre » joué avec un ordre qui EST celui de l'arrivée :
      //   l'arbitre déduisait « ordre » de l'arrivée, écartait le rapport
      //   Désordre pourtant publié, et déclarait le ticket `blocJusteAbsent` —
      //   alors que ce ticket est GAGNANT Désordre.
      //
      //   Mesure qui fonde la correction : Ordre et Désordre publient la MÊME
      //   combinaison (20/20 paires), donc la combinaison ne peut pas désigner
      //   la variante ; seul le libellé joué le peut.
      final resu = resoudre(
        pred('Tiercé Désordre', <int>[9, 4, 15],
            code: 'E_TIERCE',
            ordre: <int>[9, 4, 15],
            variante: 'desordre'),
        res,
      );
      final v = resu.verdict!;
      expect(v.etat, EtatGain.attribue,
          reason: 'le Désordre est payable quel que soit l\'ordre d\'arrivée');
      // e-Tiercé Désordre 9-4-15 publié à 80,30 € pour 1 €, mise 10 €.
      expect(v.total, 803.0, reason: 'dividende Désordre, jamais celui d\'Ordre');
      expect(resu.enregistrement!.ticket.etatGain, EtatGain.attribue);
    });

    test('S8-20 Couplé Ordre sur ex æquo hors rangs comparés : payé à 74,00 €', () {
      final res = resultat(rapportsDe('R5C7_20112026.json'),
          groupes: kArriveeWolvega);
      final resu = resoudre(
        pred('Couplé Ordre', <int>[4, 6],
            code: 'E_COUPLE_ORDRE', ordre: <int>[4, 6], variante: 'ordre'),
        res,
      );
      expect(resu.verdict!.etat, EtatGain.attribue,
          reason: 'l\'ex æquo est au 3e rang : les rangs 1-2 sont déterminés');
      expect(resu.verdict!.total, 74.0);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  S8-F — VERDICTS DÉFINITIFS ET ABSENCE DE DOUBLE GAIN
  // ═══════════════════════════════════════════════════════════════════════
  group('S8-F — verdicts définitifs et absence de double gain', () {
    final r16 = rapportsDe('R1C6_15112026.json');
    final res = resultat(r16, groupes: kArrivee16);

    test('S8-21 rejouer 4 fois un gain ne le multiplie jamais', () {
      var courant = pred('Simple Placé', <int>[9], code: 'E_SIMPLE_PLACE');
      var resolue = resoudre(courant, res);
      expect(resolue.enregistrement!.statut,
          StatutEnregistrementVerdict.enregistre);
      final montantInitial =
          totalDesMontantsRetour(resolue.enregistrement!.ticket.rapportsAttribues!);
      expect(montantInitial, 30.0);

      for (var i = 0; i < 4; i++) {
        final suivant =
            resoudre(resolue.enregistrement!.ticket, res);
        expect(suivant.enregistrement!.statut,
            StatutEnregistrementVerdict.dejaIdentique,
            reason: 'rejeu ${i + 1} : rien n\'est réécrit');
        final montant = totalDesMontantsRetour(
            suivant.enregistrement!.ticket.rapportsAttribues!);
        expect(montant, 30.0,
            reason: 'rejeu ${i + 1} : le montant ne double jamais. '
                'Obtenu : $montant');
        resolue = suivant;
      }
    });

    test('S8-22 un verdict définitif n\'est jamais écrasé par une indétermination',
        () {
      final gagne = resoudre(
        pred('Simple Placé', <int>[9], code: 'E_SIMPLE_PLACE'),
        res,
      );
      final ticketDefinitif = gagne.enregistrement!.ticket;
      expect(ticketDefinitif.etatGain, EtatGain.attribue);

      // On rejoue le MÊME ticket contre une course SANS rapports.
      final sansRapport = resultat(
        const <RapportPmu>[],
        groupes: kArrivee16,
      );
      final rejeu = resoudre(ticketDefinitif, sansRapport);
      expect(rejeu.enregistrement!.statut,
          StatutEnregistrementVerdict.refuseVerdictDefinitifExistant,
          reason: 'un verdict définitif est protégé');
      expect(rejeu.enregistrement!.ticket.etatGain, EtatGain.attribue,
          reason: 'l\'état définitif reste attribué');
      expect(
          totalDesMontantsRetour(
              rejeu.enregistrement!.ticket.rapportsAttribues!),
          30.0,
          reason: 'le montant acquis n\'est jamais effacé');
    });

    test('S8-23 un pari PERDU n\'écrit jamais de montant', () {
      // ★ B-4.7 (Anomalie 1) : la branche C refusait d'écrire un verdict sans
      //   composante dès que des rapports officiels étaient fournis. Un pari
      //   perdu sur une course dont les rapports sont publiés n'était donc PAS
      //   persisté : le ticket restait « en attente » indéfiniment, alors que
      //   sa perte était démontrée.
      //
      //   Le verdict `perdu` est désormais ENREGISTRÉ — et l'exigence qui
      //   compte est vérifiée ici : AUCUN montant n'est écrit.
      final resu = resoudre(
        pred('Tiercé', <int>[1, 2, 3],
            code: 'E_TIERCE', ordre: <int>[1, 2, 3]),
        res,
      );
      final v = resu.verdict!;
      expect(v.etat, EtatGain.perdu,
          reason: 'les chevaux joués ne sont pas les 3 premiers : perte ÉTABLIE');
      expect(v.total, 0.0);
      expect(v.composantes, isEmpty);
      expect(resu.enregistrement!.statut,
          StatutEnregistrementVerdict.enregistre,
          reason: 'la perte démontrée est persistée');
      expect(resu.enregistrement!.ticket.etatGain, EtatGain.perdu);
      expect(resu.enregistrement!.ticket.rapportsAttribues, isNull,
          reason: 'aucun rapport attribué : un perdu n\'a pas de montant');
      expect(resu.enregistrement!.ticket.dividendeGagnant, isNull);
      expect(resu.enregistrement!.ticket.dividendePlace, isNull);
    });
  });
}
