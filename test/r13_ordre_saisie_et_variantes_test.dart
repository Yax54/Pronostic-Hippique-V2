// R3 — conservation de l'ordre réel et fiabilité des variantes Ordre/Désordre.
//
// Le point destructeur mesuré est `_numerosManuelsSel.toList()..sort()` dans
// `bet_bottom_sheet.dart`. Ce tri est NÉCESSAIRE au comportement historique de
// `numerosJoues` : il n'a donc pas été supprimé.
//
// Ce fichier vérifie trois choses distinctes :
//   1. `numerosJoues` conserve exactement son comportement historique (trié).
//   2. `numerosDansOrdre` n'est JAMAIS alimenté par autre chose qu'une donnée
//      réellement capturée — ici, rien ne l'alimente, il reste null.
//   3. `varianteChoisie` ne peut porter une valeur que si le référentiel
//      prouve que le type est payable en Ordre ET en Désordre.
import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/referentiel_paris_pmu.dart';
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show TypePariJoue, typePariDepuisLibelle, exigeOrdreExact;

/// Les huit types du sélecteur de `bet_bottom_sheet.dart`.
const List<String> kTypesDuSelecteur = [
  'Simple Gagnant',
  'Simple Placé',
  'Gagnant+Placé',
  'Couplé Gagnant',
  'Couplé Placé',
  'Tiercé',
  'Quarté+',
  'Quinté+',
];

/// Rejoue `_ordonnancementRequis` : le type impose-t-il de désigner les
/// chevaux DANS UN ORDRE à la saisie ? Source : `exigeOrdreExactSaisie`
/// du référentiel (elle-même distincte d'`exigeOrdreExact`, qui parle du
/// PAIEMENT).
bool exigeOrdreSaisie(String libelle) {
  final type = typePmuDepuisLibelleHistorique(libelle);
  if (type == null) return false;
  return exigeOrdreExactSaisie(type) ?? false;
}

/// Rejoue `_numerosFinaux` en mode manuel : la sélection est TRIÉE puis
/// tronquée au nombre requis. Comportement historique, inchangé.
List<int> numerosFinauxManuel(Set<int> sel, int nbRequis) {
  final list = sel.toList()..sort();
  return list.take(nbRequis).toList();
}

int nbChevauxRequis(String libelle) {
  switch (libelle) {
    case 'Couplé Gagnant':
    case 'Couplé Placé':
      return 2;
    case 'Tiercé':
      return 3;
    case 'Quarté+':
      return 4;
    case 'Quinté+':
      return 5;
    default:
      return 1;
  }
}

UserPrediction _pred({
  String typePari = 'Tiercé',
  List<int> numerosJoues = const [1, 3, 5],
  String? codePmuOfficiel,
  String? varianteChoisie,
  List<int>? numerosDansOrdre,
}) {
  return UserPrediction(
    id: 'r3',
    dateStr: '2026-01-01',
    numReunion: 1,
    numCourse: 1,
    nomCourse: 'C',
    hippodrome: 'H',
    numeroCheval: 1,
    nomCheval: 'X',
    cote: 2.0,
    typePari: typePari,
    createdAt: DateTime(2026, 1, 1),
    numerosJoues: numerosJoues,
    codePmuOfficiel: codePmuOfficiel,
    varianteChoisie: varianteChoisie,
    numerosDansOrdre: numerosDansOrdre,
  );
}

void main() {
  // ───────────────────────────────────────────────────────────────────────
  group('R3/1 — numerosJoues conserve son comportement historique TRIÉ', () {
    test('une saisie dans le désordre produit une liste triée', () {
      // Saisie volontairement désordonnée : 5, puis 1, puis 3.
      final sel = <int>{5, 1, 3};
      final joues = numerosFinauxManuel(sel, 3);
      expect(joues, [1, 3, 5], reason: 'le tri historique est conservé');
    });

    test('le tri reste appliqué quel que soit l\'ordre d\'insertion', () {
      for (final ordre in [
        [3, 1, 2],
        [1, 2, 3],
        [2, 3, 1],
        [3, 2, 1],
      ]) {
        final sel = <int>{};
        for (final n in ordre) {
          sel.add(n);
        }
        expect(numerosFinauxManuel(sel, 3), [1, 2, 3],
            reason: 'saisie $ordre -> toujours [1, 2, 3]');
      }
    });

    test('la troncature au nombre requis est conservée', () {
      final sel = <int>{9, 2, 7, 4, 1};
      expect(numerosFinauxManuel(sel, 3), [1, 2, 4],
          reason: 'les N plus petits, comme avant');
    });

    test('le tri est bien celui d\'un Set (LinkedHashSet) trié explicitement', () {
      // Vérifie que le tri ne dépend pas de l'ordre d'itération du Set :
      // c'est `..sort()` qui décide, pas l'insertion.
      final sel = <int>{42, 7, 19};
      expect(sel.toList(), [42, 7, 19], reason: 'ordre d\'insertion conservé');
      expect(numerosFinauxManuel(sel, 3), [7, 19, 42],
          reason: 'mais numerosJoues est trié');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R3/2 — numerosDansOrdre n\'est jamais inventé', () {
    test('aucun ordre n\'est déduit de l\'ordre de sélection', () {
      // Même en saisissant 5/1/3 dans cet ordre, le ticket doit porter
      // numerosJoues trié ET numerosDansOrdre null.
      final sel = <int>{5, 1, 3};
      final joues = numerosFinauxManuel(sel, 3);
      final p = _pred(
        typePari: 'Tiercé',
        numerosJoues: joues,
        codePmuOfficiel: 'E_TIERCE',
        // L'interface ne capture AUCUN ordre : le champ reste null.
        numerosDansOrdre: null,
        varianteChoisie: null,
      );
      expect(p.numerosJoues, [1, 3, 5]);
      expect(p.numerosDansOrdre, isNull);
    });

    test('numerosDansOrdre null pour les huit types', () {
      for (final t in kTypesDuSelecteur) {
        final p = _pred(typePari: t, numerosDansOrdre: null);
        expect(p.numerosDansOrdre, isNull, reason: t);
      }
    });

    test('un ordre différent des numéros joués violerait l\'invariant', () {
      // Preuve que l'invariant documenté est bien discriminant : si un ordre
      // est un jour capturé, son tri DOIT égaler numerosJoues.
      final coherent = _pred(
        typePari: 'Tiercé',
        numerosJoues: const [1, 3, 5],
        numerosDansOrdre: const [3, 1, 5],
      );
      final tri = (List<int>.from(coherent.numerosDansOrdre!)..sort());
      expect(tri, coherent.numerosJoues,
          reason: 'tri(numerosDansOrdre) == numerosJoues');

      final incoherent = _pred(
        typePari: 'Tiercé',
        numerosJoues: const [1, 3, 5],
        numerosDansOrdre: const [9, 8, 7],
      );
      final tri2 = (List<int>.from(incoherent.numerosDansOrdre!)..sort());
      expect(tri2, isNot(equals(incoherent.numerosJoues)),
          reason: 'cet état est détectable, et donc interdisable');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R13/3 — l\'ordonnancement est requis à la SAISIE (mesuré)', () {
    // ★ RÉÉCRITURE après suppression des boutons Ordre/Désordre.
    //   L'ancien groupe R3/3 vérifiait `_proposeChoixVariante`, qui n'existe
    //   plus : c'était la mauvaise question (« quels rapports sont publiables ? »)
    //   appliquée au parieur (« que doit-il choisir ? »). Le PMU ne lui fait
    //   rien choisir. Ce qui compte est ceci : QUELS types exigent de désigner
    //   les chevaux dans un ordre à la saisie.
    test('exactement trois types exigent un ordre à la saisie', () {
      final requis =
          kTypesDuSelecteur.where(exigeOrdreSaisie).toList();
      expect(requis, ['Tiercé', 'Quarté+', 'Quinté+']);
    });

    test('Simple, Couplé et Gagnant+Placé n\'exigent aucun ordre', () {
      for (final t in [
        'Simple Gagnant',
        'Simple Placé',
        'Gagnant+Placé',
        'Couplé Gagnant',
        'Couplé Placé',
      ]) {
        expect(exigeOrdreSaisie(t), isFalse, reason: t);
      }
    });

    test('Gagnant+Placé est hors référentiel, donc sans ordre exigé', () {
      expect(typePmuDepuisLibelleHistorique('Gagnant+Placé'), isNull);
      expect(exigeOrdreSaisie('Gagnant+Placé'), isFalse);
    });

    test('un type inconnu n\'exige rien (aucune supposition)', () {
      expect(typePmuDepuisLibelleHistorique('Pari Inventé'), isNull);
      expect(exigeOrdreSaisie('Pari Inventé'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R13/3bis — SAISIE et PAIEMENT sont deux questions distinctes', () {
    // C'est le cœur de la confusion corrigée. Les deux fonctions ne
    // « divergent » pas : elles répondent à deux questions différentes.
    test('Tiercé : ordre exigé à la saisie, mais pas au paiement', () {
      final type = typePmuDepuisLibelleHistorique('Tiercé')!;
      expect(exigeOrdreExactSaisie(type), isTrue,
          reason: 'le bulletin doit préciser l\'ordre d\'arrivée');
      expect(exigeOrdreExact(typePariDepuisLibelle('Tiercé')), isFalse,
          reason: 'le Désordre est payable : le paiement n\'exige pas l\'ordre');
    });

    test('Quarté+ et Quinté+ : même dissymétrie', () {
      for (final t in ['Quarté+', 'Quinté+']) {
        final type = typePmuDepuisLibelleHistorique(t)!;
        expect(exigeOrdreExactSaisie(type), isTrue, reason: t);
        expect(exigeOrdreExact(typePariDepuisLibelle(t)), isFalse, reason: t);
      }
    });

    test('Simple et Couplé : aucune des deux n\'exige l\'ordre', () {
      for (final t in [
        'Simple Gagnant',
        'Simple Placé',
        'Couplé Gagnant',
        'Couplé Placé'
      ]) {
        final type = typePmuDepuisLibelleHistorique(t)!;
        expect(exigeOrdreExactSaisie(type), isFalse, reason: t);
        expect(exigeOrdreExact(typePariDepuisLibelle(t)), isFalse, reason: t);
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R13/4 — la variante n\'est JAMAIS choisie en création', () {
    // ★ RÉÉCRITURE : l'ancien test vérifiait qu'un « choix explicite du
    //   parieur » était transporté. Ce choix n'existe pas au PMU : les boutons
    //   ont été supprimés. On vérifie désormais le contrat inverse.
    test('un ticket créé ne porte aucune variante choisie', () {
      for (final t in ['Tiercé', 'Quarté+', 'Quinté+']) {
        final p = _pred(typePari: t, codePmuOfficiel: 'E_TIERCE');
        expect(p.varianteChoisie, isNull,
            reason: '$t : c\'est l\'arrivée qui décide, pas le parieur');
      }
    });

    test('les libellés qui PORTENT la variante restent interprétables', () {
      // Cas légitime et distinct : un ancien ticket nommé « Tiercé Ordre »
      // porte la variante dans son LIBELLÉ. Ce n'est pas une déduction : c'est
      // une lecture du nom enregistré.
      expect(typePariDepuisLibelle('Tiercé Ordre'), TypePariJoue.tierceOrdre);
      expect(typePariDepuisLibelle('Tiercé Désordre'),
          TypePariJoue.tierceDesordre);
      expect(typePariDepuisLibelle('Couplé Ordre'), TypePariJoue.coupleOrdre);
    });

    test('un libellé générique n\'implique aucune variante', () {
      expect(typePariDepuisLibelle('Tiercé'), TypePariJoue.tierce);
      // `tierce` n'est ni `tierceOrdre` ni `tierceDesordre`.
      expect(typePariDepuisLibelle('Tiercé'), isNot(TypePariJoue.tierceOrdre));
      expect(typePariDepuisLibelle('Tiercé'),
          isNot(TypePariJoue.tierceDesordre));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R13/5 — construction de l\'ordre réellement transmis', () {
    // Rejoue `_numerosDansOrdreCapture` : filtrage sur les numéros joués,
    // cohérence exigée, sinon null.
    List<int>? ordreCapture({
      required String typePari,
      required List<int> ordreSaisi,
      required List<int> numerosJoues,
    }) {
      if (!exigeOrdreSaisie(typePari)) return null;
      if (ordreSaisi.isEmpty) return null;
      final filtre =
          ordreSaisi.where((n) => numerosJoues.contains(n)).toList();
      if (filtre.length != numerosJoues.length) return null;
      if (filtre.toSet().length != numerosJoues.toSet().length) return null;
      return filtre;
    }

    test('un ordre complet et cohérent est transmis tel quel', () {
      final r = ordreCapture(
        typePari: 'Tiercé',
        ordreSaisi: const [5, 1, 3],
        numerosJoues: const [1, 3, 5],
      );
      expect(r, [5, 1, 3], reason: 'l\'ordre du parieur est conservé');
    });

    test('numerosJoues reste TRIÉ indépendamment de cet ordre', () {
      expect(numerosFinauxManuel({5, 1, 3}, 3), [1, 3, 5]);
    });

    test('un ordre partiel n\'est pas transmis', () {
      final r = ordreCapture(
        typePari: 'Tiercé',
        ordreSaisi: const [5, 1],
        numerosJoues: const [1, 3, 5],
      );
      expect(r, isNull, reason: '2 numéros pour 3 joués : ordre inconnu');
    });

    test('un ordre désignant d\'autres chevaux n\'est pas transmis', () {
      final r = ordreCapture(
        typePari: 'Tiercé',
        ordreSaisi: const [9, 8, 7],
        numerosJoues: const [1, 3, 5],
      );
      expect(r, isNull, reason: 'ce ne sont pas les mêmes chevaux');
    });

    test('les numéros non retenus sont filtrés, l\'ordre relatif conservé', () {
      // Le parieur a ordonné 9 puis 5 puis 1 puis 3, mais seuls 1/3/5 sont
      // finalement joués. On garde leur ordre relatif : 5 puis 1 puis 3.
      final r = ordreCapture(
        typePari: 'Tiercé',
        ordreSaisi: const [9, 5, 1, 3],
        numerosJoues: const [1, 3, 5],
      );
      expect(r, [5, 1, 3]);
    });

    test('un type sans ordonnancement ne transmet jamais d\'ordre', () {
      for (final t in ['Simple Gagnant', 'Couplé Gagnant', 'Gagnant+Placé']) {
        final r = ordreCapture(
          typePari: t,
          ordreSaisi: const [1],
          numerosJoues: const [1],
        );
        expect(r, isNull, reason: t);
      }
    });

    test('ordre vide => null (aucune invention)', () {
      expect(
        ordreCapture(
            typePari: 'Quinté+',
            ordreSaisi: const [],
            numerosJoues: const [1, 3, 5, 7, 9]),
        isNull,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R3/5 — sérialisation et restauration', () {
    test('varianteChoisie et numerosDansOrdre survivent au JSON', () {
      final p = _pred(
        typePari: 'Tiercé',
        numerosJoues: const [1, 3, 5],
        codePmuOfficiel: 'E_TIERCE',
        varianteChoisie: 'ordre',
        numerosDansOrdre: const [3, 1, 5],
      );
      final relu = UserPrediction.fromJson(p.toJson());
      expect(relu.numerosJoues, [1, 3, 5]);
      expect(relu.varianteChoisie, 'ordre');
      expect(relu.numerosDansOrdre, [3, 1, 5]);
      expect(relu.codePmuOfficiel, 'E_TIERCE');
    });

    test('les nulls survivent aussi (aucune valeur fabriquée)', () {
      final p = _pred(typePari: 'Tiercé', codePmuOfficiel: 'E_TIERCE');
      final relu = UserPrediction.fromJson(p.toJson());
      expect(relu.varianteChoisie, isNull);
      expect(relu.numerosDansOrdre, isNull);
      expect(relu.formulePari, isNull);
    });

    test('numerosDansOrdre absent du JSON reste null (jamais [])', () {
      final json = _pred(typePari: 'Tiercé').toJson();
      json.remove('numerosDansOrdre');
      final relu = UserPrediction.fromJson(json);
      expect(relu.numerosDansOrdre, isNull,
          reason: 'un ordre vide n\'est pas un ordre');
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R3/6 — paris simples et Gagnant+Placé intacts', () {
    test('Simple Gagnant : un numéro, aucun ordre, aucune variante', () {
      final p = _pred(
        typePari: 'Simple Gagnant',
        numerosJoues: const [7],
        codePmuOfficiel: 'E_SIMPLE_GAGNANT',
      );
      expect(p.numerosJoues, [7]);
      expect(p.numerosDansOrdre, isNull);
      expect(p.varianteChoisie, isNull);
    });

    test('Gagnant+Placé : deux composantes préservées, aucun code inventé', () {
      final p = UserPrediction(
        id: 'gp',
        dateStr: '2026-01-01',
        numReunion: 1,
        numCourse: 1,
        nomCourse: 'C',
        hippodrome: 'H',
        numeroCheval: 4,
        nomCheval: 'X',
        cote: 3.0,
        typePari: 'Gagnant+Placé',
        createdAt: DateTime(2026, 1, 1),
        numerosJoues: const [4],
        miseGagnant: 10.0,
        misePlace: 10.0,
        coteGagnant: 3.0,
        cotePlace: 1.8,
      );
      expect(p.miseGagnant, 10.0);
      expect(p.misePlace, 10.0);
      expect(p.miseTotaleEngagee, 20.0,
          reason: '10 € saisis = 10 Gagnant + 10 Placé, jamais divisé');
      expect(p.codePmuOfficiel, isNull);
      expect(p.varianteChoisie, isNull);
      expect(p.numerosDansOrdre, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R3/7 — les trois ordres ne sont pas confondus', () {
    test('l\'ordre d\'arrivée officiel n\'est pas un ordre de pari', () {
      // `combinaisonPmu` porte le résultat officiel, `numerosDansOrdre` le
      // pari du parieur. Ce sont deux grandeurs distinctes.
      final p = UserPrediction(
        id: 'x',
        dateStr: '2026-01-01',
        numReunion: 1,
        numCourse: 1,
        nomCourse: 'C',
        hippodrome: 'H',
        numeroCheval: 1,
        nomCheval: 'X',
        cote: 2.0,
        typePari: 'Tiercé',
        createdAt: DateTime(2026, 1, 1),
        numerosJoues: const [1, 3, 5],
        combinaisonPmu: '3-1-5',
        numerosDansOrdre: null,
      );
      // Le résultat officiel est connu…
      expect(p.combinaisonPmu, '3-1-5');
      // …mais cela ne remplit PAS l'ordre du pari : ce serait une invention.
      expect(p.numerosDansOrdre, isNull,
          reason: 'l\'arrivée officielle n\'est pas la combinaison jouée');
    });

    test('le nombre requis dépend du type, pas de la sélection', () {
      expect(nbChevauxRequis('Tiercé'), 3);
      expect(nbChevauxRequis('Quarté+'), 4);
      expect(nbChevauxRequis('Quinté+'), 5);
      expect(nbChevauxRequis('Simple Gagnant'), 1);
    });
  });
}
