// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 1 — TESTS DU RÉFÉRENTIEL CENTRAL DES TYPES DE PARIS PMU
//
//  Ces tests ne vérifient pas une implémentation : ils vérifient des
//  INVARIANTS. Le plus important est la non-assimilation : deux paris PMU
//  distincts ne doivent jamais produire le même code API.
//
//  Aucun test existant n'est modifié. Ce fichier est strictement additif.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/services/referentiel_paris_pmu.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    as module_a;

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  group('E1/1 — les 13 codes API sont uniques et non vides', () {
    test('chaque type canonique rend un code non nul et non vide', () {
      for (final type in TypePariPmu.values) {
        final code = codeApiPourTypePmu(type);
        expect(code, isNotNull, reason: '$type doit avoir un code');
        expect(code!.trim(), isNotEmpty, reason: '$type : code vide');
        expect(code, code.toUpperCase(),
            reason: '$type : les codes API mesurés sont en majuscules');
      }
    });

    test('les 13 codes sont deux à deux distincts', () {
      final vus = <String, TypePariPmu>{};
      for (final type in TypePariPmu.values) {
        final code = codeApiPourTypePmu(type)!;
        expect(vus.containsKey(code), isFalse,
            reason: 'COLLISION : $code déjà produit par ${vus[code]} '
                'et maintenant par $type');
        vus[code] = type;
      }
      expect(vus.length, TypePariPmu.values.length);
      expect(vus.length, 13);
    });

    test('la table des codes est exactement celle mesurée sur 3 742 rapports',
        () {
      const attendu = {
        TypePariPmu.simpleGagnant: 'E_SIMPLE_GAGNANT',
        TypePariPmu.simplePlace: 'E_SIMPLE_PLACE',
        TypePariPmu.coupleGagnant: 'E_COUPLE_GAGNANT',
        TypePariPmu.couplePlace: 'E_COUPLE_PLACE',
        TypePariPmu.coupleOrdre: 'E_COUPLE_ORDRE',
        TypePariPmu.tierce: 'E_TIERCE',
        TypePariPmu.trio: 'E_TRIO',
        TypePariPmu.trioOrdre: 'E_TRIO_ORDRE',
        TypePariPmu.quartePlus: 'E_QUARTE_PLUS',
        TypePariPmu.superQuatre: 'E_SUPER_QUATRE',
        TypePariPmu.quintePlus: 'E_QUINTE_PLUS',
        TypePariPmu.multi: 'E_MULTI',
        TypePariPmu.miniMulti: 'E_MINI_MULTI',
      };
      expect(attendu.length, TypePariPmu.values.length,
          reason: 'la table de référence doit couvrir tout l\'enum');
      for (final e in attendu.entries) {
        expect(codeApiPourTypePmu(e.key), e.value, reason: '${e.key}');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E1/2 — invariants explicites de non-assimilation', () {
    test('la liste kCouplesNonAssimilables est non vide', () {
      expect(kCouplesNonAssimilables, isNotEmpty);
    });

    test('aucun couple marqué non assimilable ne partage un code', () {
      expect(kCouplesNonAssimilables, isNotEmpty,
          reason: 'sans couple, ce test ne prouve rien');
      for (final couple in kCouplesNonAssimilables) {
        final (a, b) = couple;
        final ca = codeApiPourTypePmu(a);
        final cb = codeApiPourTypePmu(b);
        expect(a, isNot(b), reason: 'un couple ne peut pas être (x, x)');
        expect(ca, isNot(cb),
            reason: 'ASSIMILATION INTERDITE : $a et $b produisent tous deux '
                '« $ca »');
      }
    });

    test('Tiercé n\'est jamais assimilé au Trio ni au Trio Ordre', () {
      final tierce = codeApiPourTypePmu(TypePariPmu.tierce);
      final trio = codeApiPourTypePmu(TypePariPmu.trio);
      final trioOrdre = codeApiPourTypePmu(TypePariPmu.trioOrdre);
      expect(tierce, 'E_TIERCE');
      expect(trio, 'E_TRIO');
      expect(trioOrdre, 'E_TRIO_ORDRE');
      expect(tierce, isNot(trio));
      expect(tierce, isNot(trioOrdre));
      expect(trio, isNot(trioOrdre));
    });

    test('Quarté+ n\'est jamais assimilé au Super4', () {
      expect(codeApiPourTypePmu(TypePariPmu.quartePlus), 'E_QUARTE_PLUS');
      expect(codeApiPourTypePmu(TypePariPmu.superQuatre), 'E_SUPER_QUATRE');
      expect(
        codeApiPourTypePmu(TypePariPmu.quartePlus),
        isNot(codeApiPourTypePmu(TypePariPmu.superQuatre)),
      );
    });

    test('Quinté+ n\'est assimilé ni au MULTI ni au MINI MULTI', () {
      final quinte = codeApiPourTypePmu(TypePariPmu.quintePlus);
      expect(quinte, 'E_QUINTE_PLUS');
      expect(quinte, isNot(codeApiPourTypePmu(TypePariPmu.multi)));
      expect(quinte, isNot(codeApiPourTypePmu(TypePariPmu.miniMulti)));
      expect(
        codeApiPourTypePmu(TypePariPmu.multi),
        isNot(codeApiPourTypePmu(TypePariPmu.miniMulti)),
      );
    });

    test('Couplé Gagnant, Placé et Ordre restent trois codes distincts', () {
      final g = codeApiPourTypePmu(TypePariPmu.coupleGagnant);
      final p = codeApiPourTypePmu(TypePariPmu.couplePlace);
      final o = codeApiPourTypePmu(TypePariPmu.coupleOrdre);
      expect({g, p, o}.length, 3);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E1/3 — aucun code hors périmètre n\'est atteignable', () {
    test('les codes mesurés mais non modélisés ne sont jamais rendus', () {
      // Mesuré présent dans les rapports, volontairement hors périmètre.
      const horsPerimetre = {
        'E_DEUX_SUR_QUATRE',
        'E_SUPER_PICK5',
        'EB5',
        'E_MULTI_EN_4',
        'E_MULTI_EN_3',
      };
      final produits = TypePariPmu.values.map(codeApiPourTypePmu).toSet();
      for (final interdit in horsPerimetre) {
        expect(produits.contains(interdit), isFalse,
            reason: '$interdit est hors périmètre et ne doit pas être produit');
      }
    });

    test('tous les codes produits sont des codes réellement mesurés', () {
      const mesures = {
        'E_SIMPLE_GAGNANT',
        'E_SIMPLE_PLACE',
        'E_COUPLE_GAGNANT',
        'E_COUPLE_PLACE',
        'E_COUPLE_ORDRE',
        'E_TIERCE',
        'E_TRIO',
        'E_TRIO_ORDRE',
        'E_QUARTE_PLUS',
        'E_SUPER_QUATRE',
        'E_QUINTE_PLUS',
        'E_MULTI',
        'E_MINI_MULTI',
      };
      for (final type in TypePariPmu.values) {
        expect(mesures.contains(codeApiPourTypePmu(type)), isTrue,
            reason: '$type produit un code non mesuré');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E1/4 — taille de combinaison vs taille de jeu', () {
    test('multi et miniMulti : combinaison 4, jeu variable', () {
      // Mesuré : tous les libellés « en 4 » à « en 7 » portent une
      // combinaison de 4 chevaux. La taille du libellé est celle du JEU.
      expect(tailleCombinaisonGagnante(TypePariPmu.multi), 4);
      expect(tailleCombinaisonGagnante(TypePariPmu.miniMulti), 4);

      final jeuMulti = tailleJeu(TypePariPmu.multi);
      final jeuMini = tailleJeu(TypePariPmu.miniMulti);
      expect(jeuMulti, isNotNull);
      expect(jeuMini, isNotNull);
      expect((jeuMulti!.min, jeuMulti.max), (4, 7));
      expect((jeuMini!.min, jeuMini.max), (4, 6));

      // La combinaison gagnante n'est JAMAIS la taille du jeu.
      expect(tailleCombinaisonGagnante(TypePariPmu.multi), isNot(jeuMulti.max));
      expect(
          tailleCombinaisonGagnante(TypePariPmu.miniMulti), isNot(jeuMini.max));
    });

    test('tailles de combinaison conformes à la mesure', () {
      expect(tailleCombinaisonGagnante(TypePariPmu.simpleGagnant), 1);
      expect(tailleCombinaisonGagnante(TypePariPmu.simplePlace), 1);
      expect(tailleCombinaisonGagnante(TypePariPmu.coupleGagnant), 2);
      expect(tailleCombinaisonGagnante(TypePariPmu.couplePlace), 2);
      expect(tailleCombinaisonGagnante(TypePariPmu.coupleOrdre), 2);
      expect(tailleCombinaisonGagnante(TypePariPmu.tierce), 3);
      expect(tailleCombinaisonGagnante(TypePariPmu.trio), 3);
      expect(tailleCombinaisonGagnante(TypePariPmu.trioOrdre), 3);
      expect(tailleCombinaisonGagnante(TypePariPmu.quartePlus), 4);
      expect(tailleCombinaisonGagnante(TypePariPmu.superQuatre), 4);
      expect(tailleCombinaisonGagnante(TypePariPmu.quintePlus), 5);
    });

    test('aucune taille de jeu n\'est nulle ni inversée', () {
      for (final type in TypePariPmu.values) {
        final t = tailleJeu(type);
        expect(t, isNotNull, reason: '$type');
        expect(t!.min, greaterThanOrEqualTo(1), reason: '$type');
        expect(t.max, greaterThanOrEqualTo(t.min), reason: '$type');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E1/5 — variante déduite du libellé, jamais du type', () {
    test('les libellés réellement mesurés sont classés correctement', () {
      const cas = {
        'e-Simple Gagnant': VariantePmu.sansVariante,
        'e-Simple Placé': VariantePmu.sansVariante,
        'e-Couplé Gagnant': VariantePmu.sansVariante,
        'e-Couplé Placé': VariantePmu.sansVariante,
        'e-Couplé Ordre': VariantePmu.ordre,
        'e-Tiercé Ordre': VariantePmu.ordre,
        'e-Tiercé Désordre': VariantePmu.desordre,
        'e-Trio': VariantePmu.sansVariante,
        'e-Trio Ordre': VariantePmu.ordre,
        'e-Quarté+ Ordre': VariantePmu.ordre,
        'e-Quarté+ Désordre': VariantePmu.desordre,
        'e-Bonus': VariantePmu.bonusQuarte,
        'e-Super4': VariantePmu.sansVariante,
        'e-Quinté+ Ordre': VariantePmu.ordre,
        'e-Quinté+ Désordre': VariantePmu.desordre,
        'e-Bonus 4sur5': VariantePmu.bonus4sur5,
        'e-Bonus 3': VariantePmu.bonus3,
        'e-Quinté+ Ordre + Tirelire': VariantePmu.tirelire,
        'e-Multi en 4': VariantePmu.sansVariante,
        'e-Multi en 7': VariantePmu.sansVariante,
        'e-Mini Multi en 6': VariantePmu.sansVariante,
      };
      for (final c in cas.entries) {
        expect(varianteDepuisLibellePmu(c.key), c.value,
            reason: 'libellé « ${c.key} »');
      }
    });

    test('un rapport de non-partant n\'est jamais classé désordre', () {
      // Régression explicite : l'ancienne heuristique `contains('NP')` sur la
      // COMBINAISON classait un non-partant en désordre.
      for (final lib in [
        'e-Tiercé 1 NP',
        'e-Trio 1 NP',
        'e-Trio Ordre 1 NP',
        'e-Super4 1 NP',
        'e-Couplé Gagnant 1 NP',
        'e-Couplé Placé 1 NP',
        'e-Couplé Placé 2 NP',
      ]) {
        expect(varianteDepuisLibellePmu(lib), VariantePmu.nonPartant,
            reason: lib);
      }
    });

    test('Tirelire n\'est jamais confondu avec un rapport Ordre simple', () {
      expect(varianteDepuisLibellePmu('e-Quinté+ Ordre + Tirelire'),
          VariantePmu.tirelire);
      expect(varianteDepuisLibellePmu('e-Quinté+ Ordre'), VariantePmu.ordre);
    });

    test('un libellé vide est illisible, pas sansVariante', () {
      expect(varianteDepuisLibellePmu(''), VariantePmu.illisible);
      expect(varianteDepuisLibellePmu('   '), VariantePmu.illisible);
    });

    test('la casse et les espaces ne changent pas le classement', () {
      expect(varianteDepuisLibellePmu('  E-TIERCÉ ORDRE  '),
          VariantePmu.ordre);
      expect(varianteDepuisLibellePmu('e-tiercé désordre'),
          VariantePmu.desordre);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E1/6 — non-résolutions rendues null, jamais une valeur plausible', () {
    test('exigeOrdreExactSaisie : null explicite pour multi et miniMulti', () {
      expect(exigeOrdreExactSaisie(TypePariPmu.multi), isNull);
      expect(exigeOrdreExactSaisie(TypePariPmu.miniMulti), isNull);
    });

    test('exigeOrdreExactSaisie : valeurs établies', () {
      expect(exigeOrdreExactSaisie(TypePariPmu.simpleGagnant), isFalse);
      expect(exigeOrdreExactSaisie(TypePariPmu.simplePlace), isFalse);
      expect(exigeOrdreExactSaisie(TypePariPmu.coupleGagnant), isFalse);
      expect(exigeOrdreExactSaisie(TypePariPmu.couplePlace), isFalse);
      expect(exigeOrdreExactSaisie(TypePariPmu.trio), isFalse);
      expect(exigeOrdreExactSaisie(TypePariPmu.coupleOrdre), isTrue);
      expect(exigeOrdreExactSaisie(TypePariPmu.tierce), isTrue);
      expect(exigeOrdreExactSaisie(TypePariPmu.trioOrdre), isTrue);
      expect(exigeOrdreExactSaisie(TypePariPmu.quartePlus), isTrue);
      expect(exigeOrdreExactSaisie(TypePariPmu.superQuatre), isTrue);
      expect(exigeOrdreExactSaisie(TypePariPmu.quintePlus), isTrue);
    });

    test('variantesPayables : null explicite pour multi et miniMulti', () {
      expect(variantesPayables(TypePariPmu.multi), isNull);
      expect(variantesPayables(TypePariPmu.miniMulti), isNull);
    });

    test('variantesPayables : un pari à ordre multiple paie les deux', () {
      final tierce = variantesPayables(TypePariPmu.tierce);
      expect(tierce, isNotNull);
      expect(tierce!.contains(VariantePmu.ordre), isTrue);
      expect(tierce.contains(VariantePmu.desordre), isTrue);

      final quarte = variantesPayables(TypePariPmu.quartePlus);
      expect(quarte!.contains(VariantePmu.bonusQuarte), isTrue);

      final quinte = variantesPayables(TypePariPmu.quintePlus);
      expect(quinte!.contains(VariantePmu.bonus4sur5), isTrue);
      expect(quinte.contains(VariantePmu.bonus3), isTrue);
      expect(quinte.contains(VariantePmu.tirelire), isTrue);
    });

    test('un pari à ordre unique ne déclare jamais le désordre', () {
      for (final type in [
        TypePariPmu.coupleOrdre,
        TypePariPmu.trioOrdre,
      ]) {
        final v = variantesPayables(type);
        expect(v, isNotNull, reason: '$type');
        expect(v!.contains(VariantePmu.ordre), isTrue, reason: '$type');
        expect(v.contains(VariantePmu.desordre), isFalse, reason: '$type');
      }
    });

    test('le Super4 ne déclare aucun rapport Désordre', () {
      final v = variantesPayables(TypePariPmu.superQuatre);
      expect(v, isNotNull);
      expect(v!.contains(VariantePmu.desordre), isFalse);
    });

    test('aucune variante déclarée n\'est illisible', () {
      for (final type in TypePariPmu.values) {
        final v = variantesPayables(type);
        if (v == null) continue;
        expect(v.contains(VariantePmu.illisible), isFalse, reason: '$type');
        expect(v, isNotEmpty, reason: '$type');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E1/7 — libellés historiques en lecture seule', () {
    test('les 12 libellés de l\'écran « Mes paris » sont reconnus ou classés',
        () {
      // Composition relevée dans le code, 12 entrées.
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
      expect(libelles.length, 12);
      for (final lib in libelles) {
        final type = typePmuDepuisLibelleHistorique(lib);
        final horsPmu = estTicketApplicatifHorsReferentielPmu(lib);
        // Tout libellé est soit reconnu, soit explicitement hors référentiel.
        // Aucun troisième cas : un libellé ni reconnu ni classé serait une
        // donnée silencieusement perdue.
        expect(type != null || horsPmu, isTrue,
            reason: '« $lib » n\'est ni reconnu ni classé hors PMU');
      }
    });

    test('seul Gagnant+Placé est hors référentiel PMU', () {
      expect(estTicketApplicatifHorsReferentielPmu('Gagnant+Placé'), isTrue);
      expect(estTicketApplicatifHorsReferentielPmu('Gagnant + Placé'), isTrue);
      expect(estTicketApplicatifHorsReferentielPmu('Gagnant+Place'), isTrue);
      expect(typePmuDepuisLibelleHistorique('Gagnant+Placé'), isNull,
          reason: 'un ticket à deux composantes n\'a pas de type unique');

      for (final lib in ['Simple Gagnant', 'Tiercé', 'Quinté+']) {
        expect(estTicketApplicatifHorsReferentielPmu(lib), isFalse,
            reason: lib);
      }
    });

    test('un libellé inconnu rend null, jamais un défaut', () {
      expect(typePmuDepuisLibelleHistorique(null), isNull);
      expect(typePmuDepuisLibelleHistorique(''), isNull);
      expect(typePmuDepuisLibelleHistorique('   '), isNull);
      expect(typePmuDepuisLibelleHistorique('Toto'), isNull);
      expect(typePmuDepuisLibelleHistorique('Tous'), isNull,
          reason: '« Tous » est un filtre, pas un pari');
    });

    test('Couplé Désordre est rattaché au Couplé Gagnant, sans code inventé',
        () {
      // Aucun libellé « Couplé Désordre » n'existe côté API : mesuré.
      expect(typePmuDepuisLibelleHistorique('Couplé Désordre'),
          TypePariPmu.coupleGagnant);
      expect(codeApiPourTypePmu(TypePariPmu.coupleGagnant),
          'E_COUPLE_GAGNANT');
    });

    test('la table est immuable (const) et sans entrée vide', () {
      expect(kLibellesHistoriquesVersTypePmu, isNotEmpty);
      for (final e in kLibellesHistoriquesVersTypePmu.entries) {
        expect(e.key.trim(), isNotEmpty);
        expect(e.key, e.key.toLowerCase(),
            reason: 'les clés sont normalisées en minuscules');
      }
    });

    test('aucun libellé historique ne pointe vers un pari à jeu variable',
        () {
      // Les 12 libellés applicatifs ne contiennent ni Trio, ni Super4, ni
      // Multi : la table ne doit pas en inventer.
      for (final e in kLibellesHistoriquesVersTypePmu.entries) {
        expect(
          e.value,
          isNot(anyOf(
            TypePariPmu.trio,
            TypePariPmu.trioOrdre,
            TypePariPmu.superQuatre,
            TypePariPmu.multi,
            TypePariPmu.miniMulti,
          )),
          reason: '« ${e.key} » ne doit pas être assimilé à ${e.value}',
        );
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E1/8 — cohérence avec le sous-lot A, sans le modifier', () {
    test('aucun code du module A n\'est un code étranger au référentiel', () {
      final codesReferentiel =
          TypePariPmu.values.map(codeApiPourTypePmu).whereType<String>().toSet();
      for (final type in module_a.TypePariJoue.values) {
        final code = module_a.codeApiPourType(type);
        if (code == null) continue;
        expect(codesReferentiel.contains(code), isTrue,
            reason: 'le module A produit « $code » ($type), '
                'absent du référentiel');
      }
    });

    test('le module A n\'assimile jamais Trio, Super4, Multi ou MiniMulti', () {
      // Preuve que le sous-lot A n'a pas la dérive mesurée ailleurs dans
      // l'application (`_typePariApiFromLabel`).
      final codesA = module_a.TypePariJoue.values
          .map(module_a.codeApiPourType)
          .whereType<String>()
          .toSet();
      for (final interdit in [
        'E_TRIO',
        'E_TRIO_ORDRE',
        'E_SUPER_QUATRE',
        'E_MULTI',
        'E_MINI_MULTI',
      ]) {
        expect(codesA.contains(interdit), isFalse,
            reason: 'le module A ne doit pas produire $interdit');
      }
    });

    test('les codes communs aux deux modules sont identiques', () {
      // Correspondance type canonique → type du module A.
      const paires = {
        TypePariPmu.simpleGagnant: module_a.TypePariJoue.simpleGagnant,
        TypePariPmu.simplePlace: module_a.TypePariJoue.simplePlace,
        TypePariPmu.coupleGagnant: module_a.TypePariJoue.coupleGagnant,
        TypePariPmu.couplePlace: module_a.TypePariJoue.couplePlace,
        TypePariPmu.coupleOrdre: module_a.TypePariJoue.coupleOrdre,
        TypePariPmu.tierce: module_a.TypePariJoue.tierce,
        TypePariPmu.quartePlus: module_a.TypePariJoue.quarte,
        TypePariPmu.quintePlus: module_a.TypePariJoue.quinte,
      };
      for (final p in paires.entries) {
        expect(codeApiPourTypePmu(p.key), module_a.codeApiPourType(p.value),
            reason: 'divergence sur ${p.key} / ${p.value}');
      }
    });

    test('Couplé Désordre du module A converge vers le même code', () {
      expect(
        module_a.codeApiPourType(module_a.TypePariJoue.coupleDesordre),
        codeApiPourTypePmu(TypePariPmu.coupleGagnant),
      );
    });

    test('Tiercé Ordre et Tiercé Désordre du module A restent sur E_TIERCE',
        () {
      expect(module_a.codeApiPourType(module_a.TypePariJoue.tierceOrdre),
          codeApiPourTypePmu(TypePariPmu.tierce));
      expect(module_a.codeApiPourType(module_a.TypePariJoue.tierceDesordre),
          codeApiPourTypePmu(TypePariPmu.tierce));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E1/9 — pureté du module', () {
    test('les fonctions sont totales : aucune ne lève sur l\'enum entier', () {
      for (final type in TypePariPmu.values) {
        expect(() => codeApiPourTypePmu(type), returnsNormally);
        expect(() => tailleCombinaisonGagnante(type), returnsNormally);
        expect(() => tailleJeu(type), returnsNormally);
        expect(() => exigeOrdreExactSaisie(type), returnsNormally);
        expect(() => variantesPayables(type), returnsNormally);
      }
    });

    test('les résultats sont déterministes', () {
      for (final type in TypePariPmu.values) {
        expect(codeApiPourTypePmu(type), codeApiPourTypePmu(type));
        expect(tailleCombinaisonGagnante(type),
            tailleCombinaisonGagnante(type));
        expect(exigeOrdreExactSaisie(type), exigeOrdreExactSaisie(type));
      }
    });

    test('un libellé quelconque ne fait jamais lever', () {
      for (final lib in ['', ' ', '?', 'e-', 'NP', '0', 'é' * 500]) {
        expect(() => varianteDepuisLibellePmu(lib), returnsNormally);
        expect(() => typePmuDepuisLibelleHistorique(lib), returnsNormally);
        expect(() => estTicketApplicatifHorsReferentielPmu(lib),
            returnsNormally);
      }
    });
  });
}
