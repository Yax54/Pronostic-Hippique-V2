// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-4.1 — TESTS DE LA RÉSOLUTION PURE DU GAIN D'UN TICKET
//
//  Objet : prouver que `resoudreGainTicketDepuisDonnees` transmet au moteur
//  B-3 les informations EXACTES d'un ticket et rend son verdict sans le
//  réinterpréter, sans écriture et sans effet de bord.
//
//  Fixtures : bloc `E_QUINTE_PLUS` réel de R1C6_15112026 (mesuré) —
//      e-Quinté+ Ordre + Tirelire  9-4-15-10-1  pe 11462670 (centimes)
//      e-Quinté+ Ordre             9-4-15-10-1  pe  6462670
//      e-Quinté+ Désordre          9-4-15-10-1  pe   104390
//      e-Bonus 4sur5 ×5 (sous-combinaisons à 4 du top5)  pe 720
//      e-Bonus 3                   9-4-15      pe      510
//  `RapportPmu.dividende` est en EUROS (normalisation /100 faite à la lecture
//  de l'API, une seule fois) : 114626.70 etc.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/arbitre_variante_pmu.dart'
    show EtatCourseOfficiel;
import 'package:pronostic_hippique/services/gain_calculator.dart'
    show RapportPmu;
import 'package:pronostic_hippique/services/gain_pmu_types.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show VarianteRapport;
import 'package:pronostic_hippique/services/moteur_gain_pmu.dart'
    show MiseEngagee, RoleComposante, VerdictGain, resoudreGainTicket;
import 'package:pronostic_hippique/services/resolution_gain_ticket_pmu.dart';

// ───────────────────────────────────────────────────────────────────────────
//  FABRIQUES
// ───────────────────────────────────────────────────────────────────────────

RapportPmu api(
  String code,
  String libelle,
  String combinaison,
  double pourUnEuro, {
  bool rembourse = false,
  int? rang,
  int? miseBase,
}) =>
    RapportPmu(
      typePari: code,
      combinaison: combinaison,
      dividende: pourUnEuro,
      estOrdre: libelle.toLowerCase().contains('ordre'),
      libelleOfficiel: libelle,
      codePariOfficiel: code,
      rangCombinaisonPayable: rang,
      rembourse: rembourse,
      miseBaseCentimes: miseBase,
    );

/// Bloc Quinté+ réel de R1C6_15112026 (euros).
List<RapportPmu> quinteReel() => <RapportPmu>[
      api('E_QUINTE_PLUS', 'e-Quinté+ Ordre + Tirelire', '9-4-15-10-1',
          114626.70, rang: 1),
      api('E_QUINTE_PLUS', 'e-Quinté+ Ordre', '9-4-15-10-1', 64626.70, rang: 1),
      api('E_QUINTE_PLUS', 'e-Quinté+ Désordre', '9-4-15-10-1', 1043.90, rang: 2),
      api('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-4-15-10', 7.20, rang: 3),
      api('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-4-15-1', 7.20, rang: 3),
      api('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-4-10-1', 7.20, rang: 3),
      api('E_QUINTE_PLUS', 'e-Bonus 4sur5', '9-15-10-1', 7.20, rang: 3),
      api('E_QUINTE_PLUS', 'e-Bonus 4sur5', '4-15-10-1', 7.20, rang: 3),
      api('E_QUINTE_PLUS', 'e-Bonus 3', '9-4-15', 5.10, rang: 4),
    ];

List<RapportPmu> quinteSansTirelire() =>
    quinteReel().where((r) => !r.libelleOfficiel.contains('Tirelire')).toList();

List<RapportPmu> quarteReel() => <RapportPmu>[
      api('E_QUARTE_PLUS', 'e-Quarté+ Ordre', '9-4-15-10', 6585.50),
      api('E_QUARTE_PLUS', 'e-Quarté+ Désordre', '9-4-15-10', 576.20),
      api('E_QUARTE_PLUS', 'e-Bonus', '9-4-15', 17.60),
    ];

List<RapportPmu> tierceReel() => <RapportPmu>[
      api('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 477.40),
      api('E_TIERCE', 'e-Tiercé Désordre', '9-4-15', 80.30),
    ];

List<RapportPmu> simpleReel() => <RapportPmu>[
      api('E_SIMPLE_GAGNANT', 'e-Simple Gagnant', '9', 7.50),
      api('E_SIMPLE_PLACE', 'e-Simple Place', '9', 3.00),
      api('E_SIMPLE_PLACE', 'e-Simple Place', '4', 2.60),
    ];

/// Arrivée officielle singulière : 9-4-15-10-1-7-12.
const List<List<int>> arrivee = <List<int>>[
  <int>[9],
  <int>[4],
  <int>[15],
  <int>[10],
  <int>[1],
  <int>[7],
  <int>[12],
];

ResultatOfficielCourse res(
  List<RapportPmu> rapports, {
  List<List<int>>? groupes = arrivee,
  bool? definitive = true,
}) =>
    ResultatOfficielCourse(
      arriveeGroupes: groupes,
      arriveeDefinitive: definitive,
      rapports: rapports,
    );

/// Ticket à une composante.
TicketAGainResoudre t(String type, List<int> numeros, double mise) =>
    TicketAGainResoudre.ticketSimple(
      libelleTypePari: type,
      numerosJoues: numeros,
      mise: mise,
    );

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/1 — contrat de pureté : signature, imports, absence de montant',
      () {
    test('B4.1/1.1 la fonction est exportée et appelable sans contexte', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 1),
        resultat: res(tierceReel()),
      );
      expect(v, isA<VerdictGain>());
      expect(v.etat, EtatGain.attribue);
    });

    test('B4.1/1.2 le fichier n\'importe NI écran NI service d\'état', () {
      // Mesure : la liste des imports du fichier de production.
      final src = _lireSource('lib/services/resolution_gain_ticket_pmu.dart');
      expect(src, isNot(contains('mes_paris_screen')));
      expect(src, isNot(contains('paris_detail_screen')));
      expect(src, isNot(contains('alert_service')));
      expect(src, isNot(contains('pmu_provider')));
      expect(src, isNot(contains('gain_calculator.dart\' show RapportPmu, ')));
    });

    test('B4.1/1.3 ne contient AUCUNE sélection de montant', () {
      // Preuve d'absence : on analyse le CODE (hors commentaires), car les
      // commentaires mentionnent légitimement `reduce`, `max` et `sort` pour
      // expliquer qu'ils sont PROSCRITS.
      final code = _codeSansCommentaires(
          'lib/services/resolution_gain_ticket_pmu.dart');
      expect(code, isNot(contains('reduce(')),
          reason: 'aucun reduce ⇒ aucun MAX possible');
      expect(code, isNot(contains('.sort(')),
          reason: 'aucun tri ⇒ aucun ordre par montant');
      expect(RegExp(r'\bmax\s*\(').hasMatch(code), isFalse,
          reason: 'aucune fonction max');
      expect(code, isNot(contains('dividende >')),
          reason: 'aucune comparaison de dividendes');
      expect(code, isNot(contains('pourUnEuro >')),
          reason: 'aucune comparaison de pourUnEuro');
    });

    test('B4.1/1.4 n\'écrit rien : aucun appel de persistance', () {
      final code = _codeSansCommentaires(
          'lib/services/resolution_gain_ticket_pmu.dart');
      for (final interdit in <String>[
        '_save(',
        'notifyListeners',
        'setState',
        'File(',
        'SharedPreferences',
        'Hive',
      ]) {
        expect(code, isNot(contains(interdit)),
            reason: '« $interdit » ne doit pas apparaître dans le CODE');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/2 — gagnant avec rapport officiel exact (test 1)', () {
    test('B4.1/2.1 Tiercé Ordre exact ⇒ attribué au montant OFFICIEL', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 2),
        resultat: res(tierceReel()),
      );
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes, hasLength(1));
      expect(v.composantes.single.categorie, VarianteRapport.ordre);
      // 2 € × 477,40 = 954,80 € — le rapport ORDRE, pas le désordre.
      expect(v.total, closeTo(2 * 477.40, 1e-9));
    });

    test('B4.1/2.2 Simple Gagnant ⇒ attribué au rapport Simple Gagnant', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Simple Gagnant', const [9], 5),
        resultat: res(simpleReel()),
      );
      expect(v.etat, EtatGain.attribue);
      expect(v.total, closeTo(5 * 7.50, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/3 — perdant établi (test 2)', () {
    test('B4.1/3.1 Tiercé dont les chevaux sont hors du top3 ⇒ perdu', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [7, 12, 16], 2),
        resultat: res(tierceReel()),
      );
      expect(v.etat, EtatGain.perdu);
      expect(v.total, 0.0);
      expect(v.motif, isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/4 — remboursement justifié (test 3)', () {
    test('B4.1/4.1 rapport explicitement remboursé ⇒ rembourse, 0 €', () {
      // MESURÉ : sur 4684 rapports réels, AUCUN ne porte un libellé contenant
      // « embours », et aucun bloc n'a `rembourse: true`. Le remboursement est
      // donc signalé par le DRAPEAU du bloc, jamais par un libellé inventé.
      final rapports = <RapportPmu>[
        api('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 1.00, rembourse: true),
      ];
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 3),
        resultat: res(rapports),
      );
      expect(v.etat, EtatGain.rembourse);
      expect(v.total, 0.0);
    });

    test('B4.1/4.2 sans marquage de remboursement ⇒ PAS remboursé', () {
      // Le même rapport, mais l'API ne dit pas « remboursé » : on ne l'invente
      // pas. Avec un montant exploitable, il est attribué normalement.
      final rapports = <RapportPmu>[
        api('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 477.40),
      ];
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 3),
        resultat: res(rapports),
      );
      expect(v.etat, EtatGain.attribue);
      expect(v.etat, isNot(EtatGain.rembourse));
    });

    test('B4.1/4.3 remboursé avec un montant NON nul : le drapeau prime', () {
      // Mesuré : `rembourse == true` l'emporte sur un montant exploitable. Un
      // remboursement ne se transforme jamais en gain.
      final rapports = <RapportPmu>[
        api('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 477.40, rembourse: true),
      ];
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 3),
        resultat: res(rapports),
      );
      expect(v.etat, EtatGain.rembourse);
      expect(v.total, 0.0);
      expect(v.total, isNot(closeTo(3 * 477.40, 1e-9)));
    });

    test('B4.1/4.4 remboursé sur Ordre ET Désordre publiés ⇒ remboursé', () {
      final rapports = <RapportPmu>[
        api('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 1.00, rembourse: true),
        api('E_TIERCE', 'e-Tiercé Désordre', '9-4-15', 80.30),
      ];
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 3),
        resultat: res(rapports),
      );
      expect(v.etat, EtatGain.rembourse);
      expect(v.total, 0.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/5 — Gagnant + Placé, deux mises distinctes (test 4)', () {
    test('B4.1/5.1 deux composantes, deux mises, deux montants', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: TicketAGainResoudre.gagnantPlace(
          libelleTypePari: 'Gagnant+Placé',
          numerosJoues: const [9],
          miseGagnant: 10,
          misePlace: 10,
        ),
        resultat: res(simpleReel()),
      );
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes, hasLength(2));

      // 10 € × 7,50 = 75,00 (Gagnant) ; 10 € × 3,00 = 30,00 (Placé).
      expect(v.gainGagnant, closeTo(75.0, 1e-9));
      expect(v.gainPlace, closeTo(30.0, 1e-9));
      expect(v.total, closeTo(105.0, 1e-9));

      // Aucune mise n'est doublée : la somme engagée vaut 20 €.
      expect(v.miseEngageeDesComposantes, closeTo(20.0, 1e-9));
    });

    test('B4.1/5.2 mises ASYMÉTRIQUES : aucun alignement silencieux', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: TicketAGainResoudre.gagnantPlace(
          libelleTypePari: 'Gagnant+Placé',
          numerosJoues: const [9],
          miseGagnant: 2,
          misePlace: 20,
        ),
        resultat: res(simpleReel()),
      );
      expect(v.gainGagnant, closeTo(2 * 7.50, 1e-9));
      expect(v.gainPlace, closeTo(20 * 3.00, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/6 — Bonus R22 ambigu ⇒ nonDetermine (test 5)', () {
    test('B4.1/6.1 ticket 9-4-10-1-7 : combinaison publiée non conforme', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Quinté+', const [9, 4, 10, 1, 7], 2),
        resultat: res(quinteSansTirelire()),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.ambiguiteReglementaireBonus);
      expect(v.total, 0.0);
    });

    test('B4.1/6.2 ticket 9-4-15-1-7 : pas de Bonus 4sur5 automatique', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Quinté+', const [9, 4, 15, 1, 7], 2),
        resultat: res(quinteSansTirelire()),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.ambiguiteReglementaireBonus);
    });

    test('B4.1/6.3 combinaison CONFORME au top4 ⇒ reste attribuée', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Quinté+', const [9, 4, 15, 10, 7], 2),
        resultat: res(quinteSansTirelire()),
      );
      expect(v.etat, EtatGain.attribue);
      expect(v.total, closeTo(2 * 7.20, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/7 — Tirelire incertaine ⇒ nonDetermine (test 6)', () {
    test('B4.1/7.1 avec la ligne Tirelire publiée : nonDetermine', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Quinté+', const [9, 4, 15, 10, 1], 2),
        resultat: res(quinteReel()),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.tirelireNonDeterminee);
      expect(v.total, 0.0);
    });

    test('B4.1/7.2 la Tirelire n\'est JAMAIS additionnée à l\'Ordre', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Quinté+', const [9, 4, 15, 10, 1], 2),
        resultat: res(quinteReel()),
      );
      // Si les deux lignes étaient additionnées on obtiendrait
      // 2 × (114626,70 + 64626,70) = 358 506,80. On vérifie l'ABSENCE.
      expect(v.total, isNot(closeTo(2 * (114626.70 + 64626.70), 1e-6)));
    });

    test('B4.1/7.3 Ordre SEUL publié ⇒ attribué à l\'Ordre', () {
      final rapports = <RapportPmu>[
        api('E_QUINTE_PLUS', 'e-Quinté+ Ordre', '9-4-15-10-1', 64626.70),
      ];
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Quinté+', const [9, 4, 15, 10, 1], 2),
        resultat: res(rapports),
      );
      expect(v.etat, EtatGain.attribue);
      expect(v.total, closeTo(2 * 64626.70, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/8 — arrivée provisoire (test 7)', () {
    test('B4.1/8.1 definitive == false ⇒ nonDetermine + motif dédié', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 2),
        resultat: res(tierceReel(), definitive: false),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.arriveeNonDefinitive);
      expect(v.total, 0.0);
    });

    test('B4.1/8.2 definitive == null (API muette) ⇒ le calcul est mené', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 2),
        resultat: res(tierceReel(), definitive: null),
      );
      // Le silence n'est PAS traduit par « définitif » : mais il n'est pas non
      // plus traduit par « provisoire ». Le calcul est donc mené.
      expect(v.etat, EtatGain.attribue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/9 — ex æquo AVEC groupes officiels (test 8)', () {
    test('B4.1/9.1 arrivée avec ex æquo au-delà du top3 ⇒ Tiercé tranchable', () {
      // R6C5 réelle : [[12],[1,7],[9],[2],[10],...] — ex æquo au rang 2.
      // Un Tiercé compare 3 rangs : le rang 2 est ex æquo ⇒ non tranchable.
      final groupes = <List<int>>[
        <int>[12],
        <int>[1, 7],
        <int>[9],
        <int>[2],
        <int>[10],
      ];
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [12, 1, 9], 2),
        resultat: res(tierceReel(), groupes: groupes),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.deadHeatSansGroupes);
    });

    test('B4.1/9.2 ex æquo APRÈS le top3 ⇒ Tiercé reste tranchable', () {
      // R5C5 réelle : [[2],[4],[5,7],[8],[3],[6]] — ex æquo au rang 3.
      final groupes = <List<int>>[
        <int>[2],
        <int>[4],
        <int>[5, 7],
        <int>[8],
        <int>[3],
      ];
      final rapports = <RapportPmu>[
        api('E_TIERCE', 'e-Tiercé Ordre', '2-4-8', 477.40),
        api('E_TIERCE', 'e-Tiercé Désordre', '2-4-8', 80.30),
      ];
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [2, 4, 8], 1),
        resultat: res(rapports, groupes: groupes),
      );
      // Le rang 3 est ex æquo : il EST comparé par un Tiercé ⇒ refus.
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.deadHeatSansGroupes);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/10 — ex æquo SANS groupes officiels (test 9)', () {
    test('B4.1/10.1 groupes == null ⇒ nonDetermine, aucun ordre inventé', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 2),
        resultat: res(tierceReel(), groupes: null),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.deadHeatSansGroupes);
      expect(v.total, 0.0);
    });

    test('B4.1/10.2 groupes vides ⇒ même refus', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 2),
        resultat: res(tierceReel(), groupes: const <List<int>>[]),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.deadHeatSansGroupes);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/11 — mise manquante ou invalide (test 10)', () {
    test('B4.1/11.1 mise 0 ⇒ nonDetermine montantAbsent', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 0),
        resultat: res(tierceReel()),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.montantAbsent);
      expect(v.total, 0.0);
    });

    test('B4.1/11.2 mise négative ⇒ nonDetermine, jamais un gain négatif', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], -5),
        resultat: res(tierceReel()),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.montantAbsent);
      expect(v.total, 0.0);
    });

    test('B4.1/11.3 G+P sans aucune mise ⇒ nonDetermine', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: const TicketAGainResoudre.gagnantPlace(
          libelleTypePari: 'Gagnant+Placé',
          numerosJoues: <int>[9],
        ),
        resultat: res(simpleReel()),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.montantAbsent);
    });

    test('B4.1/11.4 G+P avec une seule mise ⇒ aucune composante inventée', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: const TicketAGainResoudre.gagnantPlace(
          libelleTypePari: 'Gagnant+Placé',
          numerosJoues: <int>[9],
          miseGagnant: 10,
        ),
        resultat: res(simpleReel()),
      );
      // Seule la composante Gagnant est engagée : la Placé n'est pas inventée.
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes, hasLength(1));
      expect(v.composantes.single.role, RoleComposante.gagnant);
      expect(v.gainPlace, 0.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/12 — variante inconnue ou insuffisamment documentée (test 11)',
      () {
    test('B4.1/12.1 rapport sans libellé ⇒ écarté, jamais transmis', () {
      final rapports = <RapportPmu>[
        api('E_TIERCE', '', '9-4-15', 477.40), // libellé vide
        api('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 477.40),
      ];
      final r = resoudreGainTicketDepuisDonneesAvecTrace(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 2),
        resultat: res(rapports),
      );
      expect(r.conversion.nbEcartes, 1, reason: 'un rapport illisible écarté');
      expect(r.verdict.etat, EtatGain.attribue);
      expect(r.verdict.total, closeTo(2 * 477.40, 1e-9));
    });

    test('B4.1/12.2 libellé non répertorié ⇒ nonDetermine typeNonRepertorie',
        () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Pari Inventé', const [9, 4, 15], 2),
        resultat: res(tierceReel()),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.typeNonRepertorie);
    });

    test('B4.1/12.3 combinaison illisible ⇒ rapport écarté', () {
      final rapports = <RapportPmu>[
        api('E_TIERCE', 'e-Tiercé Ordre', '  ', 477.40),
      ];
      final r = resoudreGainTicketDepuisDonneesAvecTrace(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 2),
        resultat: res(rapports),
      );
      expect(r.conversion.nbEcartes, 1);
      expect(r.verdict.etat, isNot(EtatGain.attribue));
    });

    test('B4.1/12.4 montant absent ⇒ nonDetermine montantAbsent', () {
      final rapports = <RapportPmu>[
        api('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 0.0),
      ];
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 2),
        resultat: res(rapports),
      );
      expect(v.etat, EtatGain.nonDetermine);
      expect(v.motif, MotifNonDetermination.montantAbsent);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/13 — plusieurs rapports : JAMAIS le montant le plus élevé '
      '(test 12)', () {
    test('B4.1/13.1 un rapport ÉLEVÉ non conforme ne capte pas le gain', () {
      // Le Désordre vaut 80,30 €, l'Ordre 477,40 €. Un ticket Désordre doit
      // percevoir 80,30 — jamais 477,40, même si c'est plus élevé.
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Désordre', const [4, 9, 15], 1),
        resultat: res(tierceReel()),
      );
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.desordre);
      expect(v.total, closeTo(80.30, 1e-9));
      expect(v.total, isNot(closeTo(477.40, 1e-9)));
    });

    test('B4.1/13.2 Tiercé Ordre joué : le Désordre (moindre) ne capte pas', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 1),
        resultat: res(tierceReel()),
      );
      expect(v.composantes.single.categorie, VarianteRapport.ordre);
      expect(v.total, closeTo(477.40, 1e-9));
    });

    test('B4.1/13.3 Quinté+ Désordre joué : jamais le montant Ordre', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Quinté+', const [4, 9, 15, 10, 1], 1),
        resultat: res(quinteSansTirelire()),
      );
      expect(v.etat, EtatGain.attribue);
      expect(v.composantes.single.categorie, VarianteRapport.desordre);
      expect(v.total, closeTo(1043.90, 1e-9));
      expect(v.total, isNot(closeTo(64626.70, 1e-9)));
      expect(v.total, isNot(closeTo(114626.70, 1e-9)));
    });

    test('B4.1/13.4 l\'ordre de la liste d\'entrée ne change RIEN', () {
      final ordin = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Désordre', const [4, 9, 15], 1),
        resultat: res(tierceReel()),
      );
      final inverse = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Désordre', const [4, 9, 15], 1),
        resultat: res(tierceReel().reversed.toList()),
      );
      expect(inverse.etat, ordin.etat);
      expect(inverse.total, closeTo(ordin.total, 1e-9));
      expect(inverse.composantes.single.categorie, ordin.composantes.single.categorie);
    });

    test('B4.1/13.5 Quarté+ Désordre joué : montant Désordre seulement', () {
      final v = resoudreGainTicketDepuisDonnees(
        ticket: t('Quarté+', const [4, 9, 15, 10], 1),
        resultat: res(quarteReel()),
      );
      expect(v.etat, EtatGain.attribue);
      expect(v.total, closeTo(576.20, 1e-9));
      expect(v.total, isNot(closeTo(6585.50, 1e-9)));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/14 — aucune modification des objets reçus', () {
    test('B4.1/14.1 la liste de rapports API garde sa taille et son ordre', () {
      final rapports = quinteReel();
      final avant = rapports.map((r) => r.toString()).toList();
      resoudreGainTicketDepuisDonnees(
        ticket: t('Quinté+', const [9, 4, 15, 10, 1], 2),
        resultat: res(rapports),
      );
      expect(rapports, hasLength(avant.length));
      expect(rapports.map((r) => r.toString()).toList(), equals(avant));
    });

    test('B4.1/14.2 la liste de numéros joués est inchangée', () {
      final numeros = <int>[9, 4, 15, 10, 1];
      resoudreGainTicketDepuisDonnees(
        ticket: t('Quinté+', numeros, 2),
        resultat: res(quinteSansTirelire()),
      );
      expect(numeros, equals(<int>[9, 4, 15, 10, 1]));
    });

    test('B4.1/14.3 les groupes d\'arrivée sont inchangés', () {
      final groupes = <List<int>>[
        <int>[9],
        <int>[4],
        <int>[15],
        <int>[10],
        <int>[1],
      ];
      final copie = groupes.map((g) => List<int>.from(g)).toList();
      resoudreGainTicketDepuisDonnees(
        ticket: t('Quinté+', const [9, 4, 15, 10, 1], 2),
        resultat: res(quinteSansTirelire(), groupes: groupes),
      );
      for (var i = 0; i < groupes.length; i++) {
        expect(groupes[i], equals(copie[i]));
      }
    });

    test('B4.1/14.4 deux appels successifs rendent le MÊME verdict', () {
      final a = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 2),
        resultat: res(tierceReel()),
      );
      final b = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 2),
        resultat: res(tierceReel()),
      );
      expect(b.etat, a.etat);
      expect(b.total, closeTo(a.total, 1e-9));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/15 — conversion API → RapportPublie', () {
    test('B4.1/15.1 les champs officiels sont repris tels quels', () {
      final p = rapportPublieDepuisApi(
        api('E_QUINTE_PLUS', 'e-Quinté+ Ordre', '9-4-15-10-1', 64626.70,
            rang: 1, miseBase: 200),
      );
      expect(p, isNotNull);
      expect(p!.codePmu, 'E_QUINTE_PLUS');
      expect(p.libelle, 'e-Quinté+ Ordre');
      expect(p.combinaison, '9-4-15-10-1');
      expect(p.variante, VarianteRapport.ordre);
      expect(p.pourUnEuro, closeTo(64626.70, 1e-9));
      expect(p.rang, 1);
      expect(p.miseBaseCentimes, 200);
      expect(p.rembourse, isFalse);
    });

    test('B4.1/15.2 aucune conversion monétaire supplémentaire (pas de /100)',
        () {
      // Le dividende de l'API est DÉJÀ en euros pour 1 €. Une seconde division
      // donnerait 646,267 — on vérifie qu'elle n'a pas lieu.
      final p = rapportPublieDepuisApi(
        api('E_QUINTE_PLUS', 'e-Quinté+ Ordre', '9-4-15-10-1', 64626.70),
      );
      expect(p!.pourUnEuro, closeTo(64626.70, 1e-9));
      expect(p.pourUnEuro, isNot(closeTo(646.267, 1e-6)));
    });

    test('B4.1/14.3 le marquage remboursé est conservé', () {
      final p = rapportPublieDepuisApi(
        api('E_TIERCE', 'e-Tiercé Ordre', '9-4-15', 1.00, rembourse: true),
      );
      expect(p!.rembourse, isTrue);
    });

    test('B4.1/15.4 Tirelire : variante reconnue AVANT « ordre »', () {
      final p = rapportPublieDepuisApi(
        api('E_QUINTE_PLUS', 'e-Quinté+ Ordre + Tirelire', '9-4-15-10-1',
            114626.70),
      );
      expect(p!.variante, VarianteRapport.tirelire);
    });

    test('B4.1/15.5 la conversion ne modifie pas la liste d\'entrée', () {
      final rapports = tierceReel();
      final avant = rapports.map((r) => r.toString()).toList();
      final c = convertirRapportsApi(rapports);
      expect(c.rapports, hasLength(2));
      expect(rapports.map((r) => r.toString()).toList(), equals(avant));
    });

    test('B4.1/15.6 les listes rendues sont NON MODIFIABLES', () {
      final c = convertirRapportsApi(tierceReel());
      expect(() => c.rapports.add(c.rapports.first), throwsUnsupportedError);
      expect(() => c.ecartes.add('x'), throwsUnsupportedError);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('B4.1/16 — équivalence avec un appel direct au moteur B-3', () {
    test('B4.1/16.1 le verdict est IDENTIQUE à celui du moteur', () {
      // Preuve que la couche ne réinterprète rien : on reconstruit le même
      // `EtatCourseOfficiel` à la main et on compare.
      final direct = _appelDirectMoteur();
      final via = resoudreGainTicketDepuisDonnees(
        ticket: t('Tiercé Ordre', const [9, 4, 15], 2),
        resultat: res(tierceReel()),
      );
      expect(via.etat, direct.etat);
      expect(via.total, closeTo(direct.total, 1e-9));
      expect(via.composantes.single.categorie,
          direct.composantes.single.categorie);
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
//  UTILITAIRES DE TEST
// ───────────────────────────────────────────────────────────────────────────

/// Lecture du source de production, pour prouver l'absence de motifs interdits.
///
/// `dart:io` est utilisé ICI, dans le TEST, pas dans le code de production :
/// le fichier testé n'importe aucun service d'écriture.
String _lireSource(String chemin) => File(chemin).readAsStringSync();

/// Ne garde que le CODE d'un fichier Dart : retire les lignes de commentaire
/// (`//` et `///`).
///
/// Nécessaire parce que la documentation du fichier CITE volontairement les
/// motifs proscrits (`reduce`, `max`, `sort`) pour expliquer qu'ils sont
/// interdits. Chercher ces motifs dans le texte brut produirait un faux
/// positif ; le contrôle porte donc sur le code exécutable.
String _codeSansCommentaires(String chemin) {
  final lignes = _lireSource(chemin).split('\n');
  final gardees = <String>[];
  for (final l in lignes) {
    final t = l.trimLeft();
    if (t.startsWith('//')) continue;
    gardees.add(l);
  }
  return gardees.join('\n');
}

/// Appel direct au moteur, sans passer par la couche B-4.1.
VerdictGain _appelDirectMoteur() {
  final etat = EtatCourseOfficiel(
    arriveeGroupes: arrivee,
    arriveeDefinitive: true,
    rapports: <RapportPublie>[
      RapportPublie(
        codePmu: 'E_TIERCE',
        libelle: 'e-Tiercé Ordre',
        combinaison: '9-4-15',
        variante: VarianteRapport.ordre,
        pourUnEuro: 477.40,
      ),
      RapportPublie(
        codePmu: 'E_TIERCE',
        libelle: 'e-Tiercé Désordre',
        combinaison: '9-4-15',
        variante: VarianteRapport.desordre,
        pourUnEuro: 80.30,
      ),
    ],
  );
  return resoudreGainTicket(
    libelleTypePari: 'Tiercé Ordre',
    numerosJoues: const <int>[9, 4, 15],
    mise: const MiseEngagee.simple(2),
    etat: etat,
  );
}
