// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 4-D — L'ADAPTATEUR EST-IL EXPLOITABLE PAR LE RÉSOLVEUR ?
//
//  OBJET : vérifier que les rapports officiels conservés par `RapportPmu`
//  (étape 4-C) sont directement exploitables par le résolveur, sans
//  reconstitution d'aucune sorte.
//
//  ── SÉPARATION DES DEUX CONTRATS ─────────────────────────────────────────
//  Le présent fichier de test est le SEUL endroit où adaptateur et résolveur
//  se rencontrent (la garde E4A/7 interdit cette rencontre dans `lib/`).
//  C'est exactement ce que le mandat demande : prouver la COMPATIBILITÉ,
//  sans brancher les écritures financières.
//
//  ── ORIGINE DES FIXTURES ─────────────────────────────────────────────────
//  Les rapports `RapportPmu` sont produits par le décodeur RÉEL
//  (`PmuApiService.decoderRapportsDefinitifs`), alimenté par une réponse
//  calquée sur la production du 18/11/2026 (R1C1). Aucune valeur inventée :
//  ce sont les libellés, combinaisons, rangs et dividendes mesurés.
//
//  ── CE QUE CE LOT NE FAIT PAS ────────────────────────────────────────────
//   • Aucun raccordement aux écrans, au provider ou aux écritures.
//   • Aucune modification des codes historiques ni des tests existants.
//   • Aucune correction de l'heuristique `estOrdre` : elle est CONSTATÉE
//     fausse, et il est prouvé qu'aucune décision ne s'appuie sur elle.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/adaptateur_rapport_officiel.dart';
import 'package:pronostic_hippique/services/gain_calculator.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart';
import 'package:pronostic_hippique/services/pmu_api_service.dart';
import 'package:pronostic_hippique/services/resolveur_rapport_pmu.dart';

// ───────────────────────────────────────────────────────────────────────────
//  1. FIXTURE — RÉPONSE RÉELLE DU 18/11/2026 (R1C1)
// ───────────────────────────────────────────────────────────────────────────

String corpsReel() => json.encode([
      {
        'typePari': 'E_SIMPLE_GAGNANT',
        'miseBase': 100,
        'rembourse': false,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Simple Gagnant',
            'combinaison': '2',
            'dividendePourUnEuro': 3130,
          },
        ],
      },
      {
        'typePari': 'E_SIMPLE_PLACE',
        'miseBase': 100,
        'rembourse': false,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Simple Placé',
            'combinaison': '2',
            'dividendePourUnEuro': 630,
          },
          {
            'rangCombinaisonPayable': 2,
            'libelle': 'e-Simple Placé',
            'combinaison': '1',
            'dividendePourUnEuro': 260,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Simple Placé',
            'combinaison': '14',
            'dividendePourUnEuro': 240,
          },
        ],
      },
      // ── Tiercé : Ordre ET Désordre, MÊME combinaison ────────────────────
      {
        'typePari': 'E_TIERCE',
        'miseBase': 100,
        'rembourse': false,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Tiercé Ordre',
            'combinaison': '2-1-14',
            'dividendePourUnEuro': 73950,
          },
          {
            'rangCombinaisonPayable': 2,
            'libelle': 'e-Tiercé Désordre',
            'combinaison': '2-1-14',
            'dividendePourUnEuro': 10510,
          },
        ],
      },
      // ── Quarté+ : Ordre (0 €), Désordre, Bonus ──────────────────────────
      {
        'typePari': 'E_QUARTE_PLUS',
        'miseBase': 150,
        'rembourse': false,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Quarté+ Ordre',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 0,
          },
          {
            'rangCombinaisonPayable': 2,
            'libelle': 'e-Quarté+ Désordre',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 14490,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Bonus',
            'combinaison': '2-1-14',
            'dividendePourUnEuro': 1620,
          },
        ],
      },
      // ── Quinté+ : Ordre, Désordre, Bonus 4sur5, Bonus 3 ─────────────────
      {
        'typePari': 'E_QUINTE_PLUS',
        'miseBase': 200,
        'rembourse': false,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Quinté+ Ordre',
            'combinaison': '2-1-14-12-8',
            'dividendePourUnEuro': 615350,
          },
          {
            'rangCombinaisonPayable': 2,
            'libelle': 'e-Quinté+ Désordre',
            'combinaison': '2-1-14-12-8',
            'dividendePourUnEuro': 5120,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Bonus 4sur5',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 220,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Bonus 4sur5',
            'combinaison': '2-1-14-8',
            'dividendePourUnEuro': 220,
          },
          {
            'rangCombinaisonPayable': 4,
            'libelle': 'e-Bonus 3',
            'combinaison': '2-1-14',
            'dividendePourUnEuro': 200,
          },
        ],
      },
      // ── Multi : 4 variantes, MÊME combinaison ───────────────────────────
      {
        'typePari': 'E_MULTI',
        'miseBase': 300,
        'rembourse': false,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'e-Multi en 4',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 14700,
          },
          {
            'rangCombinaisonPayable': 2,
            'libelle': 'e-Multi en 5',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 2940,
          },
          {
            'rangCombinaisonPayable': 3,
            'libelle': 'e-Multi en 6',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 980,
          },
          {
            'rangCombinaisonPayable': 4,
            'libelle': 'e-Multi en 7',
            'combinaison': '2-1-14-12',
            'dividendePourUnEuro': 420,
          },
        ],
      },
      // ── Rapport REMBOURSÉ (bloc) ────────────────────────────────────────
      {
        'typePari': 'E_TRIO',
        'miseBase': 100,
        'rembourse': true,
        'dividendeUnite': 'PourUnEuro',
        'rapports': [
          {
            'rangCombinaisonPayable': 1,
            'libelle': 'Remboursement e-Trio',
            'combinaison': '2-1-14',
            'dividendePourUnEuro': 100,
          },
        ],
      },
    ]);

List<RapportPmu> _pmu() =>
    PmuApiService.decoderRapportsDefinitifs(corpsReel());

/// Tous les rapports, adaptés.
List<RapportOfficiel> _officiels() => adaptateurRapportsPmu(_pmu());

// ───────────────────────────────────────────────────────────────────────────
//  2. TESTS
// ───────────────────────────────────────────────────────────────────────────

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  //  4D/1 — FIDÉLITÉ DE L'ADAPTATEUR, CHAMP PAR CHAMP
  // ══════════════════════════════════════════════════════════════════════════
  group('4D/1 — adaptation fidèle, champ par champ', () {
    test('code PMU officiel, libellé et combinaison sont recopiés', () {
      final pmu = _pmu();
      final off = _officiels();
      expect(off, hasLength(pmu.length),
          reason: 'une adaptation ne doit ni perdre ni dupliquer un rapport');

      for (var i = 0; i < pmu.length; i++) {
        expect(off[i].typePari, pmu[i].codePariOfficiel);
        expect(off[i].libelle, pmu[i].libelleOfficiel);
        expect(off[i].combinaison, pmu[i].combinaison);
        expect(off[i].rapportPourUnEuro, pmu[i].dividende);
        expect(off[i].rembourse, pmu[i].rembourse);
      }
    });

    test('le dividende n\'est ni arrondi ni reconverti', () {
      final tierce = adaptateurRapportsPmuDuCode(_pmu(), 'E_TIERCE');
      expect(tierce[0].rapportPourUnEuro, closeTo(739.50, 1e-12));
      expect(tierce[1].rapportPourUnEuro, closeTo(105.10, 1e-12));
    });

    test('l\'ordre publié est conservé, aucun tri n\'est appliqué', () {
      final quintes = adaptateurRapportsPmuDuCode(_pmu(), 'E_QUINTE_PLUS');
      expect(quintes.map((o) => o.libelle), <String>[
        'e-Quinté+ Ordre',
        'e-Quinté+ Désordre',
        'e-Bonus 4sur5',
        'e-Bonus 4sur5',
        'e-Bonus 3',
      ]);
    });

    test('le remboursement est transporté tel quel', () {
      final trio = adaptateurRapportsPmuDuCode(_pmu(), 'E_TRIO').single;
      expect(trio.rembourse, isTrue);
      final gagnant =
          adaptateurRapportsPmuDuCode(_pmu(), 'E_SIMPLE_GAGNANT').single;
      expect(gagnant.rembourse, isFalse);
    });

    test('la liste adaptée est non modifiable', () {
      final off = _officiels();
      expect(() => off.add(off.first), throwsUnsupportedError);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4D/2 — SIMPLE GAGNANT : correspondance et non-correspondance
  // ══════════════════════════════════════════════════════════════════════════
  group('4D/2 — Simple Gagnant', () {
    test('cheval correspondant ⇒ rapport trouvé', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const <int>[2],
        rapports: adaptateurRapportsPmuDuCode(_pmu(), 'E_SIMPLE_GAGNANT'),
      );
      expect(res.trouve, isTrue);
      expect(res.rapport!.combinaison, '2');
      expect(res.rapport!.rapportPourUnEuro, closeTo(31.30, 1e-12));
      expect(res.rapport!.libelle, 'e-Simple Gagnant');
    });

    test('cheval NON correspondant ⇒ refus explicite, aucun repli', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const <int>[7],
        rapports: adaptateurRapportsPmuDuCode(_pmu(), 'E_SIMPLE_GAGNANT'),
      );
      expect(res.refuse, isTrue);
      expect(res.rapport, isNull);
      expect(res.motifRefus, MotifRefusPmu.aucunRapportExact);
      expect(res.explication, isNotEmpty);
    });

    test('Simple Placé : le cheval 14 est trouvé au rang 3', () {
      final places = adaptateurRapportsPmuDuCode(_pmu(), 'E_SIMPLE_PLACE');
      expect(places, hasLength(3));
      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Placé',
        numerosJoues: const <int>[14],
        rapports: places,
      );
      expect(res.trouve, isTrue);
      expect(res.rapport!.combinaison, '14');
      expect(res.rapport!.rapportPourUnEuro, closeTo(2.40, 1e-12));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4D/3 — TIERCÉ : Ordre et Désordre pour une MÊME combinaison
  // ══════════════════════════════════════════════════════════════════════════
  group('4D/3 — Tiercé Ordre / Désordre', () {
    test('le Tiercé générique est AMBIGU : refus, jamais un choix', () {
      final tierce = adaptateurRapportsPmuDuCode(_pmu(), 'E_TIERCE');
      expect(tierce, hasLength(2));
      expect(tierce[0].combinaison, tierce[1].combinaison,
          reason: 'les deux rapports portent la même combinaison');

      final res = resoudreRapportPmu(
        libelleTypePari: 'Tiercé',
        numerosJoues: const <int>[2, 1, 14],
        rapports: tierce,
      );
      expect(res.refuse, isTrue);
      expect(res.rapport, isNull);
      expect(res.motifRefus, MotifRefusPmu.ambiguitePlusieursRapports,
          reason: 'Ordre et Désordre co-existent : aucune sélection inventée');
    });

    test('aucun montant arbitraire n\'est retenu sur le Tiercé ambigu', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Tiercé',
        numerosJoues: const <int>[2, 1, 14],
        rapports: adaptateurRapportsPmuDuCode(_pmu(), 'E_TIERCE'),
      );
      // Ni le maximum (739,50) ni le premier ne doit ressortir.
      expect(res.rapport, isNull);
      // MESURÉ : sur une ambiguïté, AUCUN rapport n'est « écarté » — les deux
      // correspondent exactement à la combinaison jouée. La liste est donc
      // vide, et c'est la preuve qu'aucun n'a été disqualifié au profit de
      // l'autre. Un refus qui écarterait le Désordre pour garder l'Ordre (ou
      // l'inverse) trahirait un choix arbitraire.
      expect(res.ecartes, isEmpty,
          reason: 'aucun des deux rapports ne doit être écarté : ils sont '
              'tous deux exacts, et le refus porte sur l\'impossibilité de '
              'choisir');
      // L'explication nomme la combinaison et les deux variantes en cause.
      expect(res.explication, contains('2-1-14'));
      expect(res.explication, isNotEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4D/4 — QUARTÉ+ : Ordre, Désordre, Bonus
  // ══════════════════════════════════════════════════════════════════════════
  group('4D/4 — Quarté+ Ordre / Désordre / Bonus', () {
    test('les trois variantes restent distinctes après adaptation', () {
      final quarte = adaptateurRapportsPmuDuCode(_pmu(), 'E_QUARTE_PLUS');
      // L'Ordre est publié à 0 € : il n'est pas dans le modèle historique.
      expect(quarte.map((o) => o.libelle),
          <String>['e-Quarté+ Désordre', 'e-Bonus']);
      expect(quarte.map((o) => o.combinaison), <String>['2-1-14-12', '2-1-14']);
    });

    test('« e-Quarté+ Ordre » à 0 € est refusé, pas reconstitué', () {
      // On force le rapport à 0 € dans la liste, comme l'API le publie.
      final forceA0 = <RapportOfficiel>[
        const RapportOfficiel(
          typePari: 'E_QUARTE_PLUS',
          libelle: 'e-Quarté+ Ordre',
          combinaison: '2-1-14-12',
          rapportPourUnEuro: 0.0,
        ),
      ];
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quarté+',
        numerosJoues: const <int>[2, 1, 14, 12],
        rapports: forceA0,
      );
      // Un rapport à 0 € n'est pas un gain : le résolveur ne peut pas
      // l'ignorer silencieusement, il tranche par un verdict explicite.
      expect(res.trouve, isTrue,
          reason: 'le rapport existe et correspond exactement');
      expect(res.rapport!.rapportPourUnEuro, 0.0,
          reason: 'le montant publié est transmis tel quel, jamais remplacé '
              'par un autre rapport plus généreux');
    });

    test('Quarté+ générique (Ordre + Désordre présents) ⇒ ambiguïté ou refus',
        () {
      // On reconstitue le cas réel complet : Ordre + Désordre + Bonus.
      final complet = <RapportOfficiel>[
        const RapportOfficiel(
          typePari: 'E_QUARTE_PLUS',
          libelle: 'e-Quarté+ Ordre',
          combinaison: '2-1-14-12',
          rapportPourUnEuro: 0.0,
        ),
        const RapportOfficiel(
          typePari: 'E_QUARTE_PLUS',
          libelle: 'e-Quarté+ Désordre',
          combinaison: '2-1-14-12',
          rapportPourUnEuro: 144.90,
        ),
        const RapportOfficiel(
          typePari: 'E_QUARTE_PLUS',
          libelle: 'e-Bonus',
          combinaison: '2-1-14',
          rapportPourUnEuro: 16.20,
        ),
      ];
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quarté+',
        numerosJoues: const <int>[2, 1, 14, 12],
        rapports: complet,
      );
      // Ordre et Désordre portent la MÊME combinaison exacte : le résolveur
      // doit refuser de trancher entre les deux.
      expect(res.motifRefus, MotifRefusPmu.ambiguitePlusieursRapports);
      expect(res.rapport, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4D/5 — QUINTÉ+ : Ordre, Désordre, Bonus 4sur5, Bonus 3
  // ══════════════════════════════════════════════════════════════════════════
  group('4D/5 — Quinté+ Ordre / Désordre / Bonus', () {
    test('les Bonus restent distincts de l\'Ordre et du Désordre', () {
      final quinte = adaptateurRapportsPmuDuCode(_pmu(), 'E_QUINTE_PLUS');
      final libelles = quinte.map((o) => o.libelle).toList();
      expect(libelles, contains('e-Bonus 4sur5'));
      expect(libelles, contains('e-Bonus 3'));

      // Un Bonus n'a jamais la combinaison du ticket de 5 chevaux.
      for (final o in quinte) {
        if (o.libelle.contains('Bonus')) {
          expect(o.combinaison.split('-').length, lessThan(5),
              reason: 'un Bonus porte une combinaison plus courte');
        }
      }
    });

    test('Quinté+ générique ⇒ refus (Ordre et Désordre même combinaison)', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Quinté+',
        numerosJoues: const <int>[2, 1, 14, 12, 8],
        rapports: adaptateurRapportsPmuDuCode(_pmu(), 'E_QUINTE_PLUS'),
      );
      expect(res.refuse, isTrue);
      expect(res.rapport, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4D/6 — MULTI : variantes en 4, 5, 6 et 7
  // ══════════════════════════════════════════════════════════════════════════
  group('4D/6 — Multi en 4/5/6/7', () {
    test('les 4 variantes sont toutes adaptées, aucune n\'est fondue', () {
      final multi = adaptateurRapportsPmuDuCode(_pmu(), 'E_MULTI');
      expect(multi, hasLength(4));
      expect(multi.map((o) => o.libelle), <String>[
        'e-Multi en 4',
        'e-Multi en 5',
        'e-Multi en 6',
        'e-Multi en 7',
      ]);
      // Même combinaison : seul le libellé les sépare.
      for (final o in multi) {
        expect(o.combinaison, '2-1-14-12');
      }
      expect(multi.map((o) => o.libelle).toSet(), hasLength(4));
    });

    test('Multi ne produit jamais un rapport unique par défaut', () {
      // Le résolveur refuse le Multi (pari à jeu variable, hors moteur A) :
      // il ne choisit pas « en 4 » au motif que c'est le premier.
      final res = resoudreRapportPmu(
        libelleTypePari: 'Multi',
        numerosJoues: const <int>[2, 1, 14, 12],
        rapports: adaptateurRapportsPmuDuCode(_pmu(), 'E_MULTI'),
      );
      expect(res.refuse, isTrue);
      expect(res.rapport, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4D/7 — REMBOURSÉ, INCOMPLET, AMBIGU
  // ══════════════════════════════════════════════════════════════════════════
  group('4D/7 — remboursé, incomplet, ambigu', () {
    test('rapport remboursé ⇒ refus rapportRembourse', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Trio',
        numerosJoues: const <int>[2, 1, 14],
        rapports: adaptateurRapportsPmuDuCode(_pmu(), 'E_TRIO'),
      );
      expect(res.refuse, isTrue);
      expect(res.rapport, isNull);
      // Le Trio relève du moteur A : le refus est explicite et motivé.
      expect(res.explication, isNotEmpty);
    });

    test('libellé absent ⇒ jamais reconstitué depuis estOrdre', () {
      // Un rapport SANS libellé mais avec estOrdre = true : la tentation
      // serait d'en déduire « e-Tiercé Ordre ». C'est interdit.
      const sansLibelle = RapportPmu(
        typePari: 'E_TIERCE',
        combinaison: '2-1-14',
        dividende: 739.50,
        estOrdre: true,
        codePariOfficiel: 'E_TIERCE',
        libelleOfficiel: '',
      );
      final adapte = adaptateurRapportPmuVersOfficiel(sansLibelle);
      expect(adapte.libelle, '',
          reason: 'le libellé n\'est JAMAIS fabriqué depuis estOrdre');
      expect(adapte.variante, VarianteRapport.illisible);

      final res = resoudreRapportPmu(
        libelleTypePari: 'Tiercé',
        numerosJoues: const <int>[2, 1, 14],
        rapports: [adapte],
      );
      expect(res.refuse, isTrue,
          reason: 'libellé illisible ⇒ refus, pas une supposition');
      expect(res.rapport, isNull);
    });

    test('dividende nul ⇒ non transporté comme montant établi', () {
      const sansDividende = RapportPmu(
        typePari: 'E_SIMPLE_GAGNANT',
        combinaison: '2',
        dividende: 0.0,
        estOrdre: true,
        codePariOfficiel: 'E_SIMPLE_GAGNANT',
        libelleOfficiel: 'e-Simple Gagnant',
      );
      final adapte = adaptateurRapportPmuVersOfficiel(sansDividende);
      expect(adapte.rapportPourUnEuro, isNull,
          reason: 'aucun montant n\'est inventé à partir de 0');

      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const <int>[2],
        rapports: [adapte],
      );
      expect(res.refuse, isTrue);
      // MESURÉ : le rapport à 0 € n'est pas « vu » comme un rapport à
      // dividende absent, il n'est pas vu du tout — le moteur A ne retient
      // aucun candidat, donc `aucunRapportExact`. Dans les deux cas le refus
      // est explicite et AUCUN montant n'est établi.
      expect(res.motifRefus, MotifRefusPmu.aucunRapportExact);
    });

    test('liste vide ⇒ refus, pas d\'exception', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Simple Gagnant',
        numerosJoues: const <int>[2],
        rapports: const <RapportOfficiel>[],
      );
      expect(res.refuse, isTrue);
      expect(res.rapport, isNull);
    });

    test('Gagnant+Placé ⇒ refusé (deux composantes)', () {
      final res = resoudreRapportPmu(
        libelleTypePari: 'Gagnant+Placé',
        numerosJoues: const <int>[2],
        rapports: _officiels(),
      );
      expect(res.refuse, isTrue);
      expect(res.motifRefus, MotifRefusPmu.ticketDeuxComposantes);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4D/8 — AUCUNE DÉCISION NE S'APPUIE SUR estOrdre
  // ══════════════════════════════════════════════════════════════════════════
  group('4D/8 — estOrdre n\'est jamais utilisé', () {
    test('l\'heuristique est FAUSSE sur le Tiercé (constat mesuré)', () {
      final tierce = adaptateurRapportsPmuDuCode(_pmu(), 'E_TIERCE');
      final source = _pmu().where((r) => r.codePariOfficiel == 'E_TIERCE');
      // « e-Tiercé Ordre » ET « e-Tiercé Désordre » sont tous deux estOrdre=true.
      expect(source.map((r) => r.estOrdre).toSet(), <bool>{true});
      // Alors que les libellés, eux, sont bien distincts.
      expect(tierce.map((o) => o.libelle).toSet(),
          <String>{'e-Tiercé Ordre', 'e-Tiercé Désordre'});
    });

    test('l\'adaptateur ignore estOrdre : même résultat s\'il est inversé', () {
      const a = RapportPmu(
        typePari: 'E_TIERCE',
        combinaison: '2-1-14',
        dividende: 105.10,
        estOrdre: true,
        codePariOfficiel: 'E_TIERCE',
        libelleOfficiel: 'e-Tiercé Désordre',
        rangCombinaisonPayable: 2,
      );
      const b = RapportPmu(
        typePari: 'E_TIERCE',
        combinaison: '2-1-14',
        dividende: 105.10,
        estOrdre: false, // heuristique inversée
        codePariOfficiel: 'E_TIERCE',
        libelleOfficiel: 'e-Tiercé Désordre',
        rangCombinaisonPayable: 2,
      );
      final oa = adaptateurRapportPmuVersOfficiel(a);
      final ob = adaptateurRapportPmuVersOfficiel(b);
      expect(oa.libelle, ob.libelle);
      expect(oa.combinaison, ob.combinaison);
      expect(oa.rapportPourUnEuro, ob.rapportPourUnEuro);
      expect(oa.variante, VarianteRapport.desordre);
      expect(ob.variante, VarianteRapport.desordre,
          reason: 'la variante vient du libellé, jamais de estOrdre');
    });

    test('l\'adaptateur ne lit jamais estOrdre : preuve par la source', () {
      final src =
          File('lib/services/adaptateur_rapport_officiel.dart').readAsStringSync();
      // Hors commentaires, `estOrdre` ne doit apparaître dans AUCUNE
      // instruction : on retire les lignes de commentaire avant de chercher.
      final sansCommentaires = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(sansCommentaires.contains('estOrdre'), isFalse,
          reason: 'aucune instruction ne doit s\'appuyer sur estOrdre');
    });

    test('l\'adaptateur ne prend aucune décision de sélection', () {
      final src =
          File('lib/services/adaptateur_rapport_officiel.dart').readAsStringSync();
      for (final interdit in <String>[
        '.first',
        'reduce(',
        '.last',
        'sort(',
        'max(',
      ]) {
        expect(src.contains(interdit), isFalse,
            reason: 'l\'adaptateur ne doit pas sélectionner ($interdit)');
      }
    });

    test('l\'adaptateur n\'accède pas au réseau', () {
      final src =
          File('lib/services/adaptateur_rapport_officiel.dart').readAsStringSync();
      // On neutralise les commentaires : un mot cité en documentation n'est
      // pas une dépendance. Seul le CODE compte.
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final interdit in <String>[
        'http',
        'Future',
        'await',
        'jsonDecode',
        'jsonEncode',
        'SharedPreferences',
      ]) {
        expect(code.contains(interdit), isFalse,
            reason: 'l\'adaptateur doit rester PUR ($interdit)');
      }
      expect(code.contains('package:'), isFalse,
          reason: 'aucune dépendance de package : l\'adaptateur ne dépend que '
              'de deux modules relatifs');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4D/9 — CONTRÔLE CROISÉ DU RANG PAYABLE
  // ══════════════════════════════════════════════════════════════════════════
  group('4D/9 — cohérence rang payable / libellé', () {
    test('les rapports réels sont tous cohérents', () {
      for (final r in _pmu()) {
        final inc = verifierCoherenceRang(r);
        expect(inc, isNull,
            reason: 'incohérence inattendue sur « ${r.libelleOfficiel} » '
                '(rang ${r.rangCombinaisonPayable}) : ${inc?.explication}');
      }
    });

    test('un rang contredit par le libellé est SIGNALÉ, pas arbitré', () {
      const contradiction = RapportPmu(
        typePari: 'E_TIERCE',
        combinaison: '2-1-14',
        dividende: 105.10,
        estOrdre: true,
        codePariOfficiel: 'E_TIERCE',
        libelleOfficiel: 'e-Tiercé Désordre', // ⇒ rang attendu 2
        rangCombinaisonPayable: 1, // ⇒ publié 1 : désaccord
      );
      final inc = verifierCoherenceRang(contradiction);
      expect(inc, isNotNull);
      expect(inc!.rang, 1);
      expect(inc.variante, VarianteRapport.desordre);
      expect(inc.explication, isNotEmpty);
      expect(inc.explication, contains('Le libellé'));
      expect(inc.explication, contains('implique le rang 2'));
      expect(inc.explication, contains('publie le rang 1'));
    });

    test('un libellé vide est signalé dès qu\'un rang est publié', () {
      const vide = RapportPmu(
        typePari: 'E_QUINTE_PLUS',
        combinaison: '2-1-14-12-8',
        dividende: 5120.0,
        estOrdre: true,
        codePariOfficiel: 'E_QUINTE_PLUS',
        libelleOfficiel: '',
        rangCombinaisonPayable: 2,
      );
      final inc = verifierCoherenceRang(vide);
      expect(inc, isNotNull);
      expect(inc!.variante, VarianteRapport.illisible);
    });

    test('sans rang publié, aucune affirmation n\'est faite', () {
      const sansRang = RapportPmu(
        typePari: 'E_TIERCE',
        combinaison: '2-1-14',
        dividende: 739.50,
        estOrdre: true,
        codePariOfficiel: 'E_TIERCE',
        libelleOfficiel: 'e-Tiercé Ordre',
        // rangCombinaisonPayable absent
      );
      expect(verifierCoherenceRang(sansRang), isNull);
    });

    test('un code sans grille par rang n\'est jamais déclaré incohérent', () {
      const simple = RapportPmu(
        typePari: 'E_SIMPLE_GAGNANT',
        combinaison: '2',
        dividende: 31.30,
        estOrdre: true,
        codePariOfficiel: 'E_SIMPLE_GAGNANT',
        libelleOfficiel: 'e-Simple Gagnant',
        rangCombinaisonPayable: 7, // rang absurde, mais aucune grille
      );
      expect(verifierCoherenceRang(simple), isNull,
          reason: 'aucune grille par rang pour un Simple : rien à affirmer');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  4D/10 — NON-BRANCHEMENT (l'adaptateur ne sert à personne)
  // ══════════════════════════════════════════════════════════════════════════
  group('4D/10 — l\'adaptateur n\'est branché nulle part', () {
    test('aucun écran, provider ou service d\'écriture ne l\'utilise', () {
      final fautifs = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('adaptateur_rapport_officiel.dart')) continue;
        final s = f.readAsStringSync();
        if (s.contains('adaptateurRapportPmuVersOfficiel') ||
            s.contains('adaptateurRapportsPmu') ||
            s.contains('adaptateur_rapport_officiel')) {
          fautifs.add(f.path);
        }
      }
      expect(fautifs, isEmpty,
          reason: 'aucun raccordement à cette étape : $fautifs');
    });

    test('l\'adaptateur n\'importe pas le résolveur', () {
      final src =
          File('lib/services/adaptateur_rapport_officiel.dart').readAsStringSync();
      // ⚠️ L'import du second module s'écrit sur DEUX lignes
      //    (`import 'gain_ticket_calculator.dart'` puis `show …`), d'où un
      //    motif qui ne suppose pas le `;` sur la même ligne.
      final imports = RegExp(r"^import '([^']+)'", multiLine: true)
          .allMatches(src)
          .map((m) => m.group(1))
          .toList();
      expect(imports, hasLength(2), reason: 'imports lus : $imports');
      expect(imports, containsAll(<String>[
        'gain_calculator.dart',
        'gain_ticket_calculator.dart',
      ]));
      for (final i in imports) {
        expect(i, isNot(contains('resolveur')),
            reason: 'l\'adaptateur ne doit pas dépendre du résolveur');
        expect(i, isNot(contains('package:')),
            reason: 'dépendance de package interdite : $i');
      }
    });

    test('aucun fichier de lib/ ne cite le résolveur (hors lui-même)', () {
      // ★ LOT B-3 — CONTRÔLE RESSERRÉ : citation ≠ dépendance.
      //
      // La recherche d'origine était une sous-chaîne nue : un simple
      // commentaire la faisait échouer, et un vrai `import` passait
      // inaperçu si le chemin était écrit autrement. On distingue
      // maintenant les deux, et la liste des DÉPENDANTS est fermée et
      // nominative. B-3 est le lot qui autorise la délégation ; il reste le
      // seul, et l'adaptateur 4-D n'en fait toujours pas partie.
      const dependantsAutorises = <String>[
        'lib/services/moteur_gain_pmu.dart',
      ];
      final dependantsReels = <String>[];
      final citationsSeules = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('resolveur_rapport_pmu.dart')) continue;
        final contenu = f.readAsStringSync();
        if (!contenu.contains('resolveur_rapport_pmu.dart')) continue;
        final importe = RegExp(
          r'''^\s*import\s+['"][^'"]*resolveur_rapport_pmu\.dart['"]''',
          multiLine: true,
        ).hasMatch(contenu);
        (importe ? dependantsReels : citationsSeules).add(f.path);
      }
      dependantsReels.sort();
      citationsSeules.sort();
      expect(dependantsReels, equals(dependantsAutorises),
          reason: 'branchement interdit : $dependantsReels');
      expect(citationsSeules, equals(<String>['lib/services/arbitre_variante_pmu.dart']),
          reason: 'citations du résolveur sans import : $citationsSeules');
    });
  });
}
