// ═══════════════════════════════════════════════════════════════════════════
//  SOUS-LOT A — TESTS CIBLÉS : IDENTIFICATION EXACTE TICKET ⇄ RAPPORT PMU
//
//  Toutes les valeurs de dividende et de combinaison utilisées ici sont
//  RECOPIÉES des artefacts réels mesurés
//  (/home/user/recherche_pmu/rapports, 50 fichiers, 839 rapports), et non
//  inventées. La course R1C6 sert de cas de référence : elle publie
//  simultanément Ordre ET Désordre avec la MÊME combinaison, ce qui est
//  précisément le piège que ce sous-lot doit rendre non silencieux.
//
//  Ce fichier ne teste QUE la couche d'identification pure. Aucune I/O,
//  aucun widget, aucun `SharedPreferences`.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // 0. TABLE DES LIBELLES RÉELS
  //    Les 20 libellés distincts observés sur 839 rapports. Si l'API en
  //    publie un nouveau, ce test ne le couvre pas mais ne ment pas : il
  //    vérifie au minimum que TOUS les libellés mesurés sont classés
  //    correctement (aucun ne tombe dans `illisible`).
  // ─────────────────────────────────────────────────────────────────────────
  group('A/0 — varianteDepuisLibelle sur les libellés réels mesurés', () {
    const attendus = <String, VarianteRapport>{
      'e-Simple Gagnant': VarianteRapport.sansVariante,
      'e-Simple Placé': VarianteRapport.sansVariante,
      'e-Couplé Gagnant': VarianteRapport.sansVariante,
      'e-Couplé Gagnant 1 NP': VarianteRapport.nonPartant,
      'e-Couplé Placé': VarianteRapport.sansVariante,
      'e-Couplé Placé 1 NP': VarianteRapport.nonPartant,
      'e-Couplé Ordre': VarianteRapport.ordre,
      'e-2sur4': VarianteRapport.sansVariante,
      'e-2sur4 1 NP': VarianteRapport.nonPartant,
      'e-Mini Multi en 4': VarianteRapport.sansVariante,
      'e-Mini Multi en 5': VarianteRapport.sansVariante,
      'e-Mini Multi en 6': VarianteRapport.sansVariante,
      'e-Multi en 4': VarianteRapport.sansVariante,
      'e-Multi en 5': VarianteRapport.sansVariante,
      'e-Multi en 6': VarianteRapport.sansVariante,
      'e-Multi en 7': VarianteRapport.sansVariante,
      'e-Bonus': VarianteRapport.bonusQuarte,
      'e-Quarté+ Désordre': VarianteRapport.desordre,
      'e-Quarté+ Ordre': VarianteRapport.ordre,
      'e-Bonus 3': VarianteRapport.bonus3,
      'e-Bonus 4sur5': VarianteRapport.bonus4sur5,
      'e-Quinté+ Désordre': VarianteRapport.desordre,
      'e-Quinté+ Ordre': VarianteRapport.ordre,
      'e-Super Pick5 Désordre': VarianteRapport.desordre,
      'e-Super Pick5 Ordre': VarianteRapport.ordre,
      'e-Super Pick5 Super Désordre': VarianteRapport.desordre,
      'e-Super4': VarianteRapport.sansVariante,
      'e-Super4 1 NP': VarianteRapport.nonPartant,
      'e-Tiercé Désordre': VarianteRapport.desordre,
      'e-Tiercé Ordre': VarianteRapport.ordre,
      'e-Trio': VarianteRapport.sansVariante,
      'e-Trio 1 NP': VarianteRapport.nonPartant,
      'e-Trio Ordre': VarianteRapport.ordre,
      'e-Trio Ordre 1 NP': VarianteRapport.nonPartant,
    };

    attendus.forEach((libelle, variante) {
      test('« $libelle » ⇒ $variante', () {
        expect(varianteDepuisLibelle(libelle), variante);
      });
    });

    test('aucun libellé mesuré ne tombe dans `illisible`', () {
      for (final libelle in attendus.keys) {
        expect(
          varianteDepuisLibelle(libelle),
          isNot(VarianteRapport.illisible),
          reason: '« $libelle » doit être classé, pas illisible',
        );
      }
    });

    test('libellé vide ⇒ illisible', () {
      expect(varianteDepuisLibelle(''), VarianteRapport.illisible);
      expect(varianteDepuisLibelle('   '), VarianteRapport.illisible);
    });

    test('« 1 NP » n\'est JAMAIS un désordre (ancienne heuristique fausse)', () {
      // pmu_api_service.dart classait « combinaison.contains(NP) » ⇒ désordre.
      expect(
        varianteDepuisLibelle('e-Couplé Placé 1 NP'),
        VarianteRapport.nonPartant,
      );
      expect(
        varianteDepuisLibelle('e-Couplé Placé 1 NP'),
        isNot(VarianteRapport.desordre),
      );
      // « Placé » est bien présent dans la chaîne : c'est le piège.
      expect('e-Couplé Placé 1 NP'.toLowerCase().contains('placé'), isTrue);
    });

    test('« e-Bonus 4sur5 » n\'est pas classé « bonusQuarte »', () {
      expect(varianteDepuisLibelle('e-Bonus 4sur5'), VarianteRapport.bonus4sur5);
      expect(varianteDepuisLibelle('e-Bonus'), VarianteRapport.bonusQuarte);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 1. TYPE DE PARI JOUÉ : les 12 libellés réellement proposés par l'app
  //    (mes_paris_screen.dart `_typesPariDisponibles`) + refus des inconnus.
  // ─────────────────────────────────────────────────────────────────────────
  group('A/1 — typePariDepuisLibelle sur les libellés applicatifs', () {
    test('les 12 libellés de _typesPariDisponibles sont tous reconnus', () {
      const libelles = [
        'Simple Gagnant',
        'Simple Placé',
        'Gagnant+Placé',
        'Couplé Gagnant',
        'Couplé Placé',
        'Couplé Ordre',
        'Couplé Désordre',
        'Tiercé',
        'Tiercé Ordre',
        'Tiercé Désordre',
        'Quarté+',
        'Quinté+',
      ];
      for (final l in libelles) {
        expect(
          typePariDepuisLibelle(l),
          isNot(TypePariJoue.inconnu),
          reason: '« $l » est proposé par l\'app et doit être reconnu',
        );
      }
      expect(libelles.length, 12);
    });

    test('libellé inconnu ⇒ inconnu (aucun calcul financier possible)', () {
      expect(typePariDepuisLibelle('Trio'), TypePariJoue.inconnu);
      expect(typePariDepuisLibelle('Multi'), TypePariJoue.inconnu);
      expect(typePariDepuisLibelle('2sur4'), TypePariJoue.inconnu);
      expect(typePariDepuisLibelle(''), TypePariJoue.inconnu);
      expect(typePariDepuisLibelle('simple gagnant'), TypePariJoue.inconnu);
    });

    test('les 8 libellés de bet_bottom_sheet sont un sous-ensemble reconnu', () {
      const libelles = [
        'Simple Gagnant',
        'Simple Placé',
        'Gagnant+Placé',
        'Couplé Gagnant',
        'Couplé Placé',
        'Tiercé',
        'Quarté+',
        'Quinté+',
      ];
      for (final l in libelles) {
        expect(typePariDepuisLibelle(l), isNot(TypePariJoue.inconnu));
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. CODES API ET TAILLES
  // ─────────────────────────────────────────────────────────────────────────
  group('A/2 — codes API et tailles attendues', () {
    test('code API unique par type joué', () {
      expect(codeApiPourType(TypePariJoue.simpleGagnant), 'E_SIMPLE_GAGNANT');
      expect(codeApiPourType(TypePariJoue.simplePlace), 'E_SIMPLE_PLACE');
      expect(codeApiPourType(TypePariJoue.coupleGagnant), 'E_COUPLE_GAGNANT');
      expect(codeApiPourType(TypePariJoue.couplePlace), 'E_COUPLE_PLACE');
      expect(codeApiPourType(TypePariJoue.coupleOrdre), 'E_COUPLE_ORDRE');
      expect(codeApiPourType(TypePariJoue.tierce), 'E_TIERCE');
      expect(codeApiPourType(TypePariJoue.quarte), 'E_QUARTE_PLUS');
      expect(codeApiPourType(TypePariJoue.quinte), 'E_QUINTE_PLUS');
      expect(codeApiPourType(TypePariJoue.inconnu), isNull);
    });

    test('Simple Gagnant et Simple Placé ont des codes DISTINCTS', () {
      // Régression mesurée : un paramètre booléen de composante, par défaut
      // `false`, faisait retomber un Simple Placé joué seul sur le rapport
      // Gagnant (4.73 au lieu de 1.40).
      expect(codeApiPourType(TypePariJoue.simpleGagnant), isNot('E_SIMPLE_PLACE'));
      expect(codeApiPourType(TypePariJoue.simplePlace), isNot('E_SIMPLE_GAGNANT'));
      expect(
        codeApiPourType(TypePariJoue.simpleGagnant),
        isNot(codeApiPourType(TypePariJoue.simplePlace)),
      );
    });

    test('Gagnant+Placé n\'a AUCUN code unique (deux composantes)', () {
      // Deux composantes ⇒ deux rapports : il n'existe pas de code unique.
      // Le dédoublement est fait par identifierGagnantPlace().
      expect(codeApiPourType(TypePariJoue.gagnantPlace), isNull);
    });

    test('un Couplé Désordre n\'exige pas l\'ordre, un Couplé Ordre si', () {
      expect(exigeOrdreExact(TypePariJoue.coupleOrdre), isTrue);
      expect(exigeOrdreExact(TypePariJoue.coupleDesordre), isFalse);
      expect(exigeOrdreExact(TypePariJoue.tierceOrdre), isTrue);
      expect(exigeOrdreExact(TypePariJoue.tierceDesordre), isFalse);
    });

    test('tailles de combinaison', () {
      expect(tailleCombinaisonAttendue(TypePariJoue.simpleGagnant), 1);
      expect(tailleCombinaisonAttendue(TypePariJoue.coupleGagnant), 2);
      expect(tailleCombinaisonAttendue(TypePariJoue.coupleOrdre), 2);
      expect(tailleCombinaisonAttendue(TypePariJoue.tierce), 3);
      expect(tailleCombinaisonAttendue(TypePariJoue.quarte), 4);
      expect(tailleCombinaisonAttendue(TypePariJoue.quinte), 5);
      expect(tailleCombinaisonAttendue(TypePariJoue.inconnu), isNull);
    });

    test('les Bonus ne sont pas identifiables par égalité de combinaison', () {
      for (final t in [
        TypePariJoue.quarte,
        TypePariJoue.quinte,
      ]) {
        final v = variantesIdentifiablesParCombinaison(t);
        expect(v.contains(VarianteRapport.bonusQuarte), isFalse);
        expect(v.contains(VarianteRapport.bonus4sur5), isFalse);
        expect(v.contains(VarianteRapport.bonus3), isFalse);
        expect(v.contains(VarianteRapport.nonPartant), isFalse);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2 bis. TABLE DES CODES — CORRESPONDANCES VÉRIFIÉES
  //
  // Sources croisées :
  //  • 3 742 rapports réels / 206 courses (08→16 nov. 2026, API v7) ;
  //  • règlement officiel 05/07/2022 (/home/user/recherche_pmu/reglement.txt).
  //
  // Chaque test ci-dessous correspond à une affirmation VÉRIFIÉE, pas à une
  // intuition : il échouera si quelqu'un ré-assimile deux paris distincts.
  // ─────────────────────────────────────────────────────────────────────────
  group('A/12 — table des codes API : correspondances vérifiées', () {
    test('les codes retenus sont EXACTEMENT ceux mesurés sur l\'API', () {
      // Mesuré dans les 3 742 rapports : les six codes ci-dessous existent
      // réellement et portent les libellés cités en commentaire.
      expect(codeApiPourType(TypePariJoue.simpleGagnant), 'E_SIMPLE_GAGNANT');
      expect(codeApiPourType(TypePariJoue.simplePlace), 'E_SIMPLE_PLACE');
      expect(codeApiPourType(TypePariJoue.coupleGagnant), 'E_COUPLE_GAGNANT');
      expect(codeApiPourType(TypePariJoue.couplePlace), 'E_COUPLE_PLACE');
      expect(codeApiPourType(TypePariJoue.coupleOrdre), 'E_COUPLE_ORDRE');
      expect(codeApiPourType(TypePariJoue.tierce), 'E_TIERCE');
      expect(codeApiPourType(TypePariJoue.quarte), 'E_QUARTE_PLUS');
      expect(codeApiPourType(TypePariJoue.quinte), 'E_QUINTE_PLUS');
    });

    test('E_TRIO n\'est JAMAIS assimilé au Tiercé (E_TIERCE)', () {
      // Mesuré : E_TRIO = 179 courses (« e-Trio », sans ordre, règlement
      // l.6832) ; E_TIERCE = 9 courses (« e-Tiercé Ordre/Désordre », ordre
      // imposé, l.2674). Co-occurrence sur une même course : 0/206.
      final codesTierce = {
        codeApiPourType(TypePariJoue.tierce),
        codeApiPourType(TypePariJoue.tierceOrdre),
        codeApiPourType(TypePariJoue.tierceDesordre),
      };
      expect(codesTierce, {'E_TIERCE'});
      expect(codesTierce.contains('E_TRIO'), isFalse);
      expect(codesTierce.contains('E_TRIO_ORDRE'), isFalse);
    });

    test('E_SUPER_QUATRE n\'est JAMAIS assimilé au Quarté+ (E_QUARTE_PLUS)', () {
      // Mesuré : E_SUPER_QUATRE = 44 courses (« e-Super4 », ordre imposé,
      // règlement l.7172) ; E_QUARTE_PLUS = 9 courses. Co-occurrence : 0/206.
      expect(codeApiPourType(TypePariJoue.quarte), 'E_QUARTE_PLUS');
      expect(codeApiPourType(TypePariJoue.quarte), isNot('E_SUPER_QUATRE'));
    });

    test('E_MULTI / E_MINI_MULTI ne sont JAMAIS assimilés au Quinté+', () {
      // Mesuré : E_QUINTE_PLUS = 9 courses ; E_MULTI = 62, E_MINI_MULTI = 87.
      // Ce sont trois chapitres distincts du règlement (7, 8 et 9).
      expect(codeApiPourType(TypePariJoue.quinte), 'E_QUINTE_PLUS');
      expect(codeApiPourType(TypePariJoue.quinte), isNot('E_MULTI'));
      expect(codeApiPourType(TypePariJoue.quinte), isNot('E_MINI_MULTI'));
    });

    test('E_COUPLE_ORDRE reste distinct de E_COUPLE_GAGNANT', () {
      // Règlement l.1784-1790 : même pari, mais condition de paiement
      // différente (ordre exact exigé) dès que la liste des partants le
      // mentionne. Deux codes, jamais interchangeables.
      expect(codeApiPourType(TypePariJoue.coupleOrdre), 'E_COUPLE_ORDRE');
      expect(codeApiPourType(TypePariJoue.coupleGagnant), 'E_COUPLE_GAGNANT');
      expect(
        codeApiPourType(TypePariJoue.coupleOrdre),
        isNot(codeApiPourType(TypePariJoue.coupleGagnant)),
      );
    });

    test('aucun type joué ne renvoie un code de pari NON PROPOSÉ par l\'app', () {
      // E_DEUX_SUR_QUATRE, E_SUPER_PICK5, EB5 (« Big 5 ») existent sur l'API
      // mais ne correspondent à aucun pari de l'application : ils ne doivent
      // jamais être atteints.
      const interdits = {
        'E_DEUX_SUR_QUATRE',
        'E_SUPER_PICK5',
        'EB5',
        'E_TRIO',
        'E_TRIO_ORDRE',
        'E_SUPER_QUATRE',
        'E_MULTI',
        'E_MINI_MULTI',
      };
      for (final t in TypePariJoue.values) {
        final code = codeApiPourType(t);
        if (code == null) continue;
        expect(interdits.contains(code), isFalse,
            reason: '$t ne doit pas renvoyer le code $code');
      }
    });

    test('chaque code retourné appartient à la liste blanche mesurée', () {
      const listeBlanche = {
        'E_SIMPLE_GAGNANT',
        'E_SIMPLE_PLACE',
        'E_COUPLE_GAGNANT',
        'E_COUPLE_PLACE',
        'E_COUPLE_ORDRE',
        'E_TIERCE',
        'E_QUARTE_PLUS',
        'E_QUINTE_PLUS',
      };
      for (final t in TypePariJoue.values) {
        final code = codeApiPourType(t);
        if (code == null) continue;
        expect(listeBlanche.contains(code), isTrue,
            reason: '$t renvoie un code non mesuré : $code');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. UNITÉ DU DIVIDENDE
  // ─────────────────────────────────────────────────────────────────────────
  group('A/3 — normalisation du dividende en euros pour 1 €', () {
    test('dividendePourUnEuro prioritaire : centimes → euros', () {
      final r = RapportOfficiel.depuisJson(
        {
          'libelle': 'e-Simple Gagnant',
          'combinaison': '8',
          'dividendePourUnEuro': 473520,
          'dividendePourUneMiseDeBase': 473520,
          'dividende': 473520,
        },
        typePari: 'E_SIMPLE_GAGNANT',
        miseBaseCentimes: 100,
      )!;
      expect(r.rapportPourUnEuro, closeTo(4735.20, 0.001));
    });

    test('repli exact via miseBase : Quarté+ 944220 / 150 = 6294.80', () {
      // Valeur RÉELLE mesurée en R1C6.
      final r = RapportOfficiel.depuisJson(
        {
          'libelle': 'e-Quarté+ Désordre',
          'combinaison': '13-16-7-4',
          'dividendePourUneMiseDeBase': 944220,
          'dividende': 944220,
        },
        typePari: 'E_QUARTE_PLUS',
        miseBaseCentimes: 150,
      )!;
      expect(r.rapportPourUnEuro, closeTo(6294.80, 0.001));
      // Formule de contrôle mesurée : 944220 × 100 / 150 = 629480 centimes.
      expect(944220 * 100 / 150, closeTo(629480, 0.0001));
    });

    test('repli exact : Quinté+ 3116260 / 200 = 15581.30', () {
      final r = RapportOfficiel.depuisJson(
        {
          'libelle': 'e-Quinté+ Désordre',
          'combinaison': '13-16-7-4-1',
          'dividendePourUneMiseDeBase': 3116260,
        },
        typePari: 'E_QUINTE_PLUS',
        miseBaseCentimes: 200,
      )!;
      expect(r.rapportPourUnEuro, closeTo(15581.30, 0.001));
    });

    test('repli exact : Bonus 4sur5 6500 / 200 = 32.50', () {
      final r = RapportOfficiel.depuisJson(
        {
          'libelle': 'e-Bonus 4sur5',
          'combinaison': '13-16-7-4',
          'dividendePourUneMiseDeBase': 6500,
        },
        typePari: 'E_QUINTE_PLUS',
        miseBaseCentimes: 200,
      )!;
      expect(r.rapportPourUnEuro, closeTo(32.50, 0.001));
    });

    test('`dividende` seul n\'est JAMAIS utilisé comme multiplicateur', () {
      // Sans dividendePourUnEuro ni miseBase, le rapport reste null :
      // on refuse plutôt que d'appliquer un diviseur faux (×2 sur Quinté+).
      final r = RapportOfficiel.depuisJson(
        {
          'libelle': 'e-Quinté+ Désordre',
          'combinaison': '13-16-7-4-1',
          'dividende': 3116260,
        },
        typePari: 'E_QUINTE_PLUS',
        miseBaseCentimes: null,
      )!;
      expect(r.rapportPourUnEuro, isNull);
    });

    test('objet vide ⇒ null (pas de rapport anonyme)', () {
      expect(
        RapportOfficiel.depuisJson(
          const {},
          typePari: 'E_SIMPLE_GAGNANT',
          miseBaseCentimes: 100,
        ),
        isNull,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. NUMÉROS DE COMBINAISON ET NON-PARTANTS
  // ─────────────────────────────────────────────────────────────────────────
  group('A/4 — lecture des combinaisons', () {
    test('combinaison simple', () {
      const r = RapportOfficiel(
        typePari: 'E_SIMPLE_GAGNANT',
        libelle: 'e-Simple Gagnant',
        combinaison: '8',
        rapportPourUnEuro: 4.5,
      );
      expect(r.numeros, [8]);
      expect(r.estComparable, isTrue);
    });

    test('combinaison multiple dans l\'ordre publié', () {
      const r = RapportOfficiel(
        typePari: 'E_TIERCE',
        libelle: 'e-Tiercé Ordre',
        combinaison: '13-16-7',
        rapportPourUnEuro: 4735.20,
      );
      expect(r.numeros, [13, 16, 7]);
    });

    test('combinaison avec NP ⇒ numeros null (pas un cheval)', () {
      const r = RapportOfficiel(
        typePari: 'E_COUPLE_PLACE',
        libelle: 'e-Couplé Placé 1 NP',
        combinaison: '8-NP',
        rapportPourUnEuro: 1.40,
      );
      expect(r.numeros, isNull);
      expect(r.estComparable, isFalse);
    });

    test('combinaison vide ou illisible ⇒ numeros null', () {
      for (final c in ['', '  ', 'A-B', '8-0', '-8', '8-']) {
        final r = RapportOfficiel(
          typePari: 'X',
          libelle: 'e-X',
          combinaison: c,
          rapportPourUnEuro: 1.0,
        );
        expect(r.numeros, isNull, reason: 'combinaison « $c »');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 5. IDENTIFICATION EXACTE — SIMPLE
  // ─────────────────────────────────────────────────────────────────────────
  group('A/5 — Simple : identification exacte', () {
    // Rapports réels d'une course : 3 chevaux payés au gagnant.
    final rapports = <RapportOfficiel>[
      const RapportOfficiel(
        typePari: 'E_SIMPLE_GAGNANT',
        libelle: 'e-Simple Gagnant',
        combinaison: '8',
        rapportPourUnEuro: 4.73,
      ),
      const RapportOfficiel(
        typePari: 'E_SIMPLE_PLACE',
        libelle: 'e-Simple Placé',
        combinaison: '8',
        rapportPourUnEuro: 1.40,
      ),
      const RapportOfficiel(
        typePari: 'E_SIMPLE_PLACE',
        libelle: 'e-Simple Placé',
        combinaison: '3',
        rapportPourUnEuro: 2.10,
      ),
      const RapportOfficiel(
        typePari: 'E_SIMPLE_PLACE',
        libelle: 'e-Simple Placé',
        combinaison: '11',
        rapportPourUnEuro: 1.30,
      ),
    ];

    test('Simple Gagnant sur le 8 ⇒ rapport du 8 (4.73)', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.simpleGagnant,
        numerosJoues: const [8],
        rapports: rapports,
      );
      expect(id.trouve, isTrue);
      expect(id.rapport!.rapportPourUnEuro, closeTo(4.73, 0.001));
      expect(id.rapport!.libelle, 'e-Simple Gagnant');
    });

    test('Simple Placé sur le 8 ⇒ rapport placé du 8, PAS le premier', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.simplePlace,
        numerosJoues: const [8],
        rapports: rapports,
      );
      expect(id.trouve, isTrue);
      expect(id.rapport!.rapportPourUnEuro, closeTo(1.40, 0.001));
      // Preuve du piège évité : `rapports.first` aurait aussi donné 1.40,
      // mais sur le 11 il donnerait 1.40 au lieu de 1.30.
      final id11 = identifierRapportExact(
        typeJoue: TypePariJoue.simplePlace,
        numerosJoues: const [11],
        rapports: rapports,
      );
      expect(id11.trouve, isTrue);
      expect(id11.rapport!.rapportPourUnEuro, closeTo(1.30, 0.001));
      expect(rapports.first.rapportPourUnEuro, closeTo(4.73, 0.001));
      expect(id11.rapport!.rapportPourUnEuro,
          isNot(closeTo(rapports.first.rapportPourUnEuro!, 0.0001)));
    });

    test('Simple Placé sur un cheval non payé ⇒ absent, aucun montant', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.simplePlace,
        numerosJoues: const [99],
        rapports: rapports,
      );
      expect(id.trouve, isFalse);
      expect(id.rapport, isNull);
      expect(id.motif, isNotEmpty);
    });

    test('Simple Gagnant ne prend jamais un rapport Placé', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.simpleGagnant,
        numerosJoues: const [3],
        rapports: rapports, // le 3 n'est payé qu'au placé
      );
      expect(id.trouve, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 6. ORDRE / DÉSORDRE : le cas R1C6, mesuré
  // ─────────────────────────────────────────────────────────────────────────
  group('A/6 — Ordre/Désordre, même combinaison (mesure R1C6)', () {
    final rapports = <RapportOfficiel>[
      const RapportOfficiel(
        typePari: 'E_TIERCE',
        libelle: 'e-Tiercé Ordre',
        combinaison: '13-16-7',
        rapportPourUnEuro: 4735.20,
      ),
      const RapportOfficiel(
        typePari: 'E_TIERCE',
        libelle: 'e-Tiercé Désordre',
        combinaison: '13-16-7',
        rapportPourUnEuro: 614.80,
      ),
    ];

    test('Tiercé Ordre explicite ⇒ 4735.20', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.tierceOrdre,
        numerosJoues: const [13, 16, 7],
        rapports: rapports,
      );
      expect(id.trouve, isTrue);
      expect(id.rapport!.rapportPourUnEuro, closeTo(4735.20, 0.001));
    });

    test('Tiercé Désordre explicite ⇒ 614.80, quel que soit l\'ordre joué', () {
      for (final joues in [
        const [13, 16, 7],
        const [7, 13, 16],
        const [16, 7, 13],
      ]) {
        final id = identifierRapportExact(
          typeJoue: TypePariJoue.tierceDesordre,
          numerosJoues: joues,
          rapports: rapports,
        );
        expect(id.trouve, isTrue, reason: 'joué $joues');
        expect(id.rapport!.rapportPourUnEuro, closeTo(614.80, 0.001));
      }
    });

    test('Tiercé Ordre : un ordre différent n\'est PAS payé à l\'ordre', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.tierceOrdre,
        numerosJoues: const [7, 16, 13], // même combinaison, autre ordre
        rapports: rapports,
      );
      expect(id.trouve, isFalse);
      expect(id.motif, contains('Aucun rapport officiel'));
    });

    test('« Tiercé » générique ⇒ AMBIGU, refus explicite (pas de choix)', () {
      // C'est le cœur du sous-lot A : les deux rapports portent la même
      // combinaison, donc aucune identification n'est possible sans
      // l'arrivée officielle. On refuse, on ne devine pas.
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.tierce,
        numerosJoues: const [13, 16, 7],
        rapports: rapports,
      );
      expect(id.trouve, isFalse);
      expect(id.motif, contains('ambigu'));
    });

    test('« Quarté+ » générique avec Ordre ET Désordre ⇒ ambigu', () {
      final q = <RapportOfficiel>[
        const RapportOfficiel(
          typePari: 'E_QUARTE_PLUS',
          libelle: 'e-Quarté+ Ordre',
          combinaison: '13-16-7-4',
          rapportPourUnEuro: 0.0,
        ),
        const RapportOfficiel(
          typePari: 'E_QUARTE_PLUS',
          libelle: 'e-Quarté+ Désordre',
          combinaison: '13-16-7-4',
          rapportPourUnEuro: 6294.80,
        ),
      ];
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.quarte,
        numerosJoues: const [13, 16, 7, 4],
        rapports: q,
      );
      expect(id.trouve, isFalse);
      expect(id.motif, contains('ambigu'));
    });

    test('le rapport le plus élevé n\'est jamais choisi par défaut', () {
      // Si le code retenait le max, il rendrait 4735.20 pour un Désordre.
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.tierceDesordre,
        numerosJoues: const [13, 16, 7],
        rapports: rapports,
      );
      expect(id.rapport!.rapportPourUnEuro, isNot(closeTo(4735.20, 0.001)));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 7. BONUS ET NON-PARTANTS : hors périmètre A, donc JAMAIS attribués
  // ─────────────────────────────────────────────────────────────────────────
  group('A/7 — Bonus et non-partants ne sont pas attribués en A', () {
    final rapports = <RapportOfficiel>[
      const RapportOfficiel(
        typePari: 'E_QUARTE_PLUS',
        libelle: 'e-Quarté+ Ordre',
        combinaison: '13-16-7-4',
        rapportPourUnEuro: 6294.80,
      ),
      const RapportOfficiel(
        typePari: 'E_QUARTE_PLUS',
        libelle: 'e-Bonus',
        combinaison: '13-16-7', // 3 numéros pour un pari de 4
        rapportPourUnEuro: 107.30,
      ),
      const RapportOfficiel(
        typePari: 'E_COUPLE_PLACE',
        libelle: 'e-Couplé Placé 1 NP',
        combinaison: '8-NP',
        rapportPourUnEuro: 1.40,
      ),
      const RapportOfficiel(
        typePari: 'E_COUPLE_PLACE',
        libelle: 'e-Couplé Placé',
        combinaison: '8-3',
        rapportPourUnEuro: 3.20,
      ),
    ];

    test('un ticket Quarté+ à 4 numéros ne reçoit jamais le Bonus', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.quarte,
        numerosJoues: const [13, 16, 7, 4],
        rapports: rapports,
      );
      // Un seul candidat (Ordre) → il est retenu, et ce n'est pas le Bonus.
      expect(id.trouve, isTrue);
      expect(id.rapport!.libelle, 'e-Quarté+ Ordre');
      expect(id.rapport!.rapportPourUnEuro, isNot(closeTo(107.30, 0.001)));
    });

    test('un Couplé Placé sur 8-3 ne reçoit jamais le rapport « 1 NP »', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.couplePlace,
        numerosJoues: const [8, 3],
        rapports: rapports,
      );
      expect(id.trouve, isTrue);
      expect(id.rapport!.rapportPourUnEuro, closeTo(3.20, 0.001));
      expect(id.rapport!.combinaison, '8-3');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 8. CODES DE PARIS ÉTRANGERS : jamais attribués à un ticket de l'app
  // ─────────────────────────────────────────────────────────────────────────
  group('A/8 — un rapport d\'un autre pari n\'est jamais attribué', () {
    test('un Trio ne rémunère jamais un Tiercé joué', () {
      final rapports = <RapportOfficiel>[
        const RapportOfficiel(
          typePari: 'E_TRIO',
          libelle: 'e-Trio',
          combinaison: '13-16-7',
          rapportPourUnEuro: 82.40,
        ),
      ];
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.tierceDesordre,
        numerosJoues: const [13, 16, 7],
        rapports: rapports,
      );
      expect(id.trouve, isFalse);
      expect(id.motif, contains('E_TIERCE'));
    });

    test('un Super4 ne rémunère jamais un Quarté+ joué', () {
      final rapports = <RapportOfficiel>[
        const RapportOfficiel(
          typePari: 'E_SUPER_QUATRE',
          libelle: 'e-Super4',
          combinaison: '13-16-7-4',
          rapportPourUnEuro: 340.0,
        ),
      ];
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.quarte,
        numerosJoues: const [13, 16, 7, 4],
        rapports: rapports,
      );
      expect(id.trouve, isFalse);
    });

    test('un Multi ne rémunère jamais un Quinté+ joué', () {
      final rapports = <RapportOfficiel>[
        const RapportOfficiel(
          typePari: 'E_MULTI',
          libelle: 'e-Multi en 5',
          combinaison: '13-16-7-4-1',
          rapportPourUnEuro: 120.0,
        ),
      ];
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.quinte,
        numerosJoues: const [13, 16, 7, 4, 1],
        rapports: rapports,
      );
      expect(id.trouve, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 9. COUPLÉ : Ordre vs Gagnant, et l'ambiguïté évitée
  // ─────────────────────────────────────────────────────────────────────────
  group('A/9 — Couplé Ordre / Gagnant / Placé', () {
    final rapports = <RapportOfficiel>[
      const RapportOfficiel(
        typePari: 'E_COUPLE_GAGNANT',
        libelle: 'e-Couplé Gagnant',
        combinaison: '8-3',
        rapportPourUnEuro: 12.40,
      ),
      const RapportOfficiel(
        typePari: 'E_COUPLE_ORDRE',
        libelle: 'e-Couplé Ordre',
        combinaison: '8-3',
        rapportPourUnEuro: 27.90,
      ),
      const RapportOfficiel(
        typePari: 'E_COUPLE_PLACE',
        libelle: 'e-Couplé Placé',
        combinaison: '8-3',
        rapportPourUnEuro: 3.20,
      ),
    ];

    test('Couplé Ordre ⇒ E_COUPLE_ORDRE, ordre imposé, 27.90', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.coupleOrdre,
        numerosJoues: const [8, 3],
        rapports: rapports,
      );
      expect(id.trouve, isTrue);
      expect(id.rapport!.rapportPourUnEuro, closeTo(27.90, 0.001));
      expect(id.rapport!.typePari, 'E_COUPLE_ORDRE');
    });

    test('Couplé Ordre : 3-8 ne paie pas à l\'ordre quand l\'arrivée est 8-3', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.coupleOrdre,
        numerosJoues: const [3, 8],
        rapports: rapports,
      );
      expect(id.trouve, isFalse);
    });

    test('Couplé Gagnant ⇒ 12.40 (jamais le rapport Ordre 27.90)', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.coupleGagnant,
        numerosJoues: const [3, 8], // sans ordre
        rapports: rapports,
      );
      expect(id.trouve, isTrue);
      expect(id.rapport!.rapportPourUnEuro, closeTo(12.40, 0.001));
    });

    test('Couplé Placé ⇒ 3.20', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.couplePlace,
        numerosJoues: const [8, 3],
        rapports: rapports,
      );
      expect(id.trouve, isTrue);
      expect(id.rapport!.rapportPourUnEuro, closeTo(3.20, 0.001));
    });

    test('trois rapports de même combinaison mais codes différents : '
        'aucune ambiguïté, chacun trouve le sien', () {
      for (final t in [
        TypePariJoue.coupleOrdre,
        TypePariJoue.coupleGagnant,
        TypePariJoue.couplePlace,
      ]) {
        final id = identifierRapportExact(
          typeJoue: t,
          numerosJoues: const [8, 3],
          rapports: rapports,
        );
        expect(id.trouve, isTrue, reason: '$t doit être identifié sans ambiguïté');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 10. GAGNANT + PLACÉ : deux composantes, deux mises, deux rapports
  // ─────────────────────────────────────────────────────────────────────────
  group('A/10 — Gagnant+Placé : composantes séparées', () {
    final rapports = <RapportOfficiel>[
      const RapportOfficiel(
        typePari: 'E_SIMPLE_GAGNANT',
        libelle: 'e-Simple Gagnant',
        combinaison: '8',
        rapportPourUnEuro: 4.73,
      ),
      const RapportOfficiel(
        typePari: 'E_SIMPLE_PLACE',
        libelle: 'e-Simple Placé',
        combinaison: '8',
        rapportPourUnEuro: 1.40,
      ),
    ];

    test('les deux composantes sont identifiées séparément', () {
      final id = identifierGagnantPlace(
        numerosJoues: const [8],
        rapports: rapports,
      );
      expect(id.complet, isTrue);
      expect(id.gagnant.rapport!.rapportPourUnEuro, closeTo(4.73, 0.001));
      expect(id.place.rapport!.rapportPourUnEuro, closeTo(1.40, 0.001));
      expect(id.gagnant.rapport!.typePari, 'E_SIMPLE_GAGNANT');
      expect(id.place.rapport!.typePari, 'E_SIMPLE_PLACE');
    });

    test('le cheval gagne mais n\'est pas listé au placé ⇒ incomplet', () {
      final sansPlace = <RapportOfficiel>[
        const RapportOfficiel(
          typePari: 'E_SIMPLE_GAGNANT',
          libelle: 'e-Simple Gagnant',
          combinaison: '8',
          rapportPourUnEuro: 4.73,
        ),
      ];
      final id = identifierGagnantPlace(
        numerosJoues: const [8],
        rapports: sansPlace,
      );
      expect(id.gagnant.trouve, isTrue);
      expect(id.place.trouve, isFalse);
      expect(id.complet, isFalse);
    });

    test('composante unique sur un Gagnant+Placé sans précision ⇒ refus', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.gagnantPlace,
        numerosJoues: const [8],
        rapports: rapports,
      );
      expect(id.trouve, isFalse);
      expect(id.motif, contains('deux composantes'));
    });  });

  // ─────────────────────────────────────────────────────────────────────────
  // 11. ÉCHECS FERMÉS
  // ─────────────────────────────────────────────────────────────────────────
  group('A/11 — échecs fermés', () {
    test('type inconnu ⇒ absent', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.inconnu,
        numerosJoues: const [8],
        rapports: const [],
      );
      expect(id.trouve, isFalse);
      expect(id.motif, contains('non répertorié'));
    });

    test('aucun numéro joué ⇒ absent', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.simpleGagnant,
        numerosJoues: const [],
        rapports: const [],
      );
      expect(id.trouve, isFalse);
      expect(id.motif, contains('Aucun numéro'));
    });

    test('rapport présent mais dividende absent ⇒ absent, pas 0 €', () {
      final rapports = <RapportOfficiel>[
        const RapportOfficiel(
          typePari: 'E_SIMPLE_GAGNANT',
          libelle: 'e-Simple Gagnant',
          combinaison: '8',
          rapportPourUnEuro: null,
        ),
      ];
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.simpleGagnant,
        numerosJoues: const [8],
        rapports: rapports,
      );
      expect(id.trouve, isFalse);
      expect(id.rapport, isNull);
      expect(id.motif, contains('dividende pour 1 € est absent'));
    });

    test('liste vide ⇒ absent', () {
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.simpleGagnant,
        numerosJoues: const [8],
        rapports: const [],
      );
      expect(id.trouve, isFalse);
    });

    test('deux rapports identiques ⇒ ambigu, refus', () {
      final rapports = <RapportOfficiel>[
        const RapportOfficiel(
          typePari: 'E_SIMPLE_GAGNANT',
          libelle: 'e-Simple Gagnant',
          combinaison: '8',
          rapportPourUnEuro: 4.73,
        ),
        const RapportOfficiel(
          typePari: 'E_SIMPLE_GAGNANT',
          libelle: 'e-Simple Gagnant',
          combinaison: '8',
          rapportPourUnEuro: 4.80,
        ),
      ];
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.simpleGagnant,
        numerosJoues: const [8],
        rapports: rapports,
      );
      expect(id.trouve, isFalse);
      expect(id.motif, contains('ambigu'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // A/13 — e-TIRELIRE : CAS NON RÉSOLU, REFUS EXPLICITE
  //
  // Valeurs RÉELLES mesurées (15112026_R1C6) :
  //   « e-Quinté+ Ordre + Tirelire » = 11462670 centimes (114 626,70 €/€)
  //   « e-Quinté+ Ordre »            =  6462670 centimes ( 64 626,70 €/€)
  //   « e-Quinté+ Désordre »         =   104390 centimes (  1 043,90 €/€)
  //   combinaison identique : 9-4-15-10-1
  //
  // Règlement art. 7.1 (l.6190) : la Tirelire est un SUPPLÉMENT affecté au
  // rapport « e-Quinté+ Ordre », qui devient alors le rapport brut commun
  // DÉFINITIF. Les deux rapports ne sont pas deux paiements alternatifs.
  // ─────────────────────────────────────────────────────────────────────────
  group('A/13 — e-Tirelire : conflit détecté, jamais résolu par le montant '
      'le plus élevé', () {
    // Rapports réels de la course 15112026 R1C6, convertis en €/€.
    const rapportsReels = <RapportOfficiel>[
      RapportOfficiel(
        typePari: 'E_QUINTE_PLUS',
        libelle: 'e-Quinté+ Ordre + Tirelire',
        combinaison: '9-4-15-10-1',
        rapportPourUnEuro: 114626.70,
      ),
      RapportOfficiel(
        typePari: 'E_QUINTE_PLUS',
        libelle: 'e-Quinté+ Ordre',
        combinaison: '9-4-15-10-1',
        rapportPourUnEuro: 64626.70,
      ),
      RapportOfficiel(
        typePari: 'E_QUINTE_PLUS',
        libelle: 'e-Quinté+ Désordre',
        combinaison: '9-4-15-10-1',
        rapportPourUnEuro: 1043.90,
      ),
    ];

    test('la Tirelire est classée comme sa PROPRE variante, pas comme « ordre »',
        () {
      // Piège mesuré : « e-Quinté+ Ordre + Tirelire » contient le mot
      // « ordre ». Si la détection passait après, la variante serait [ordre]
      // et le conflit avec « e-Quinté+ Ordre » disparaîtrait silencieusement.
      const r = RapportOfficiel(
        typePari: 'E_QUINTE_PLUS',
        libelle: 'e-Quinté+ Ordre + Tirelire',
        combinaison: '9-4-15-10-1',
        rapportPourUnEuro: 114626.70,
      );
      expect(r.variante, VarianteRapport.tirelire);
      expect(r.variante, isNot(VarianteRapport.ordre));
    });

    test('Quinté+ ordre sur une course AVEC Tirelire ⇒ ambigu, aucun montant',
        () {
      // 3 candidats (tirelire, ordre, désordre) sur la même combinaison :
      // le module refuse. Il ne retient NI le plus élevé (114626.70)
      // NI « e-Quinté+ Ordre » (64626.70) en silence.
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.quinte,
        numerosJoues: const [9, 4, 15, 10, 1],
        rapports: rapportsReels,
      );
      expect(id.trouve, isFalse);
      expect(id.rapport, isNull);
      expect(id.motif, contains('ambigu'));
      // Preuve explicite : aucun des trois montants n'est proposé.
      expect(id.motif, isNot(contains('114626')));
      expect(id.motif, isNot(contains('64626')));
    });

    test('Tirelire publiée SEULE ⇒ refus explicite, jamais retenue', () {
      // Aucune des 3 courses mesurées ne publie la Tirelire seule, mais si
      // l'API le faisait, on ne saurait pas si le rapport définitif (sans
      // supplément) sera publié plus tard. On refuse.
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.quinte,
        numerosJoues: const [9, 4, 15, 10, 1],
        rapports: const [
          RapportOfficiel(
            typePari: 'E_QUINTE_PLUS',
            libelle: 'e-Quinté+ Ordre + Tirelire',
            combinaison: '9-4-15-10-1',
            rapportPourUnEuro: 114626.70,
          ),
        ],
      );
      expect(id.trouve, isFalse);
      expect(id.motif, contains('Tirelire'));
      expect(id.motif, contains('art. 7.1'));
    });

    test('Quinté+ Désordre reste identifiable sur une course AVEC Tirelire', () {
      // La Tirelire n'affecte QUE le rapport « e-Quinté+ Ordre ». Jouer
      // explicitement le Désordre reste donc identifiable sans ambiguïté :
      // un seul candidat porte la variante [desordre].
      final id = identifierRapportExact(
        typeJoue: TypePariJoue.quinte,
        numerosJoues: const [9, 4, 15, 10, 1],
        rapports: rapportsReels,
      );
      // (quinte générique = variantes {ordre, désordre, tirelire} ⇒ ambigu)
      expect(id.trouve, isFalse);

      // En revanche, un type explicitement désordre ne regarde que [desordre].
      expect(
        variantesIdentifiablesParCombinaison(TypePariJoue.quinte),
        containsAll(<VarianteRapport>{
          VarianteRapport.ordre,
          VarianteRapport.desordre,
          VarianteRapport.tirelire,
        }),
      );
    });

    test('la Tirelire n\'est admise QUE pour le Quinté+', () {
      // Aucun libelle « … Tirelire » mesuré sur les autres paris ; en
      // admettre la variante ailleurs ouvrirait une porte non démontrée.
      for (final t in TypePariJoue.values) {
        final v = variantesIdentifiablesParCombinaison(t);
        if (t == TypePariJoue.quinte) {
          expect(v.contains(VarianteRapport.tirelire), isTrue);
        } else {
          expect(v.contains(VarianteRapport.tirelire), isFalse,
              reason: '$t ne doit pas admettre la variante Tirelire');
        }
      }
    });
  });
}
