// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-2 — ARRIVÉE OFFICIELLE STRUCTURÉE
//
//  Deux champs facultatifs sont ajoutés à `TrackedCourse` :
//    • `arriveeGroupes`    : les groupes d'ex æquo EXACTS de l'API ;
//    • `arriveeDefinitive` : le caractère définitif de l'arrivée.
//
//  SEPT exigences sont vérifiées, dans l'ordre où elles ont été formulées :
//    1. `arriveeFinale` reste STRICTEMENT inchangé, format et fonctionnement ;
//    2. aucun groupe n'est JAMAIS reconstruit depuis une liste aplatie ;
//    3. les groupes EXACTS fournis par l'API sont préservés ;
//    4. propagation dans TOUTES les reconstructions concernées ;
//    5. sérialisation JSON et restauration des anciens tickets ;
//    6. une arrivée provisoire n'est JAMAIS enregistrée comme définitive ;
//    7. les tests s'appuient sur les TROIS cas réels d'ex æquo mesurés.
//
//  ═══ MESURE DE RÉFÉRENCE : LES TROIS CAS RÉELS ═══
//  Extraits des captures `/home/user/recherche_pmu/multi/` :
//    prog_17112026 R5C5  [[2], [4], [5, 7], [8], [3], [6]]        (8 partants)
//    prog_17112026 R6C5  [[12], [1, 7], [9], [2], [10], [8],
//                          [6], [13], [5]]                       (13 partants)
//    prog_20112026 R5C7  [[4], [6], [1, 5], [2]]                 (7 partants)
//  Les trois sont `ARRIVEE_DEFINITIVE_COMPLETE`, `isArriveeDefinitive = true`,
//  `arriveeDefinitive = true`.
//
//  ═══ CE QUE LE CODE EXISTANT FAISAIT DE CES TROIS CAS ═══
//  `ZoneTurfService.chargerResultatsCourseComplet` construit l'arrivée avec
//  `rangParNumero[rangInt] = num` : une `Map` indexée par RANG. Deux chevaux
//  ex æquo partagent le même rang, donc **le second écrase le premier**. Le
//  cheval perdant disparaît purement et simplement de l'arrivée. Vérifié par
//  simulation sur les trois cas : un cheval perdu dans chacun
//  (R5C5 → 5, R6C5 → 1, R5C7 → 1).
//
//  Ce lot NE CORRIGE PAS ce service (hors périmètre : il touche à la
//  construction de l'arrivée utilisée par les calculs). Il rend seulement la
//  perte ÉVITABLE : une fois les groupes stockés, l'information exacte existe.
//  La correction du service relèvera d'un lot ultérieur explicitement autorisé.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/services/alert_service.dart';

// ─── Les trois cas réels, tels quels ────────────────────────────────────────

/// prog_17112026 R5C5 — ex æquo au 3ᵉ rang (5 et 7).
const List<List<int>> _r5c5 = [
  [2], [4], [5, 7], [8], [3], [6]
];

/// prog_17112026 R6C5 — ex æquo au 2ᵉ rang (1 et 7).
const List<List<int>> _r6c5 = [
  [12], [1, 7], [9], [2], [10], [8], [6], [13], [5]
];

/// prog_20112026 R5C7 — ex æquo au 3ᵉ rang (1 et 5).
const List<List<int>> _r5c7 = [
  [4], [6], [1, 5], [2]
];

List<int> _aplatir(List<List<int>> groupes) =>
    <int>[for (final g in groupes) ...g];

// ─── Fabrique ───────────────────────────────────────────────────────────────

TrackedCourse _tc({
  List<int> arriveeFinale = const [],
  List<List<int>>? arriveeGroupes,
  bool? arriveeDefinitive,
  bool? isGagne,
  String? storageKey = 'R5C5_17112026',
}) {
  return TrackedCourse(
    numReunion: 5,
    numCourse: 5,
    nomCourse: 'Coupe des 5 ans',
    hippodrome: 'Mons',
    heureDepart: DateTime(2026, 11, 17, 14, 30),
    nomCheval: 'Cheval 5',
    numeroCheval: 5,
    miseEngagee: 2.0,
    typePari: 'Simple Gagnant',
    numerosJoues: const [5],
    cote: 6.5,
    storageKey: storageKey,
    isGagne: isGagne,
    arriveeFinale: arriveeFinale,
    arriveeGroupes: arriveeGroupes,
    arriveeDefinitive: arriveeDefinitive,
  );
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  B2/1 — LES DEUX CHAMPS EXISTENT, FACULTATIFS, SANS VALEUR INVENTÉE
  // ═════════════════════════════════════════════════════════════════════════
  group('B2/1 — les deux champs existent et sont facultatifs', () {
    test('null par défaut : aucune arrivée structurée n\'est devinée', () {
      final tc = _tc();
      expect(tc.arriveeGroupes, isNull);
      expect(tc.arriveeDefinitive, isNull);
      // « groupes inconnus » n'autorise pas à affirmer « pas d'ex æquo ».
      expect(tc.aDesExAequo, isFalse);
      expect(tc.arriveeGroupesAplatis, isNull);
    });

    test('les champs portent bien la valeur fournie', () {
      final tc = _tc(arriveeGroupes: _r5c5, arriveeDefinitive: true);
      expect(tc.arriveeGroupes, equals(_r5c5));
      expect(tc.arriveeDefinitive, isTrue);
      expect(tc.aDesExAequo, isTrue);
    });

    test('une arrivée SANS ex æquo est bien reconnue comme telle', () {
      final tc = _tc(
        arriveeGroupes: const [
          [1], [2], [3]
        ],
        arriveeDefinitive: true,
      );
      // Ici les groupes SONT connus : l'absence d'ex æquo est un fait affirmé.
      expect(tc.aDesExAequo, isFalse);
      expect(tc.arriveeGroupesAplatis, equals(<int>[1, 2, 3]));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2/2 — EXIGENCE 1 : `arriveeFinale` RESTE STRICTEMENT INCHANGÉ
  // ═════════════════════════════════════════════════════════════════════════
  group('B2/2 — arriveeFinale reste strictement inchangé', () {
    test('le type de arriveeFinale est toujours List<int>', () {
      // Contrôle de type à l'exécution : si le champ changeait de nature,
      // cette affectation échouerait à la compilation.
      final List<int> plate = _tc(arriveeFinale: const [1, 2, 3]).arriveeFinale;
      expect(plate, equals(<int>[1, 2, 3]));
    });

    test('arriveeFinale par défaut reste une liste vide, pas null', () {
      // Le contrat historique est `const []` : un ticket sans résultat porte
      // une liste VIDE, jamais `null`. Le préserver évite de casser tous les
      // `arriveeFinale.isNotEmpty` du code existant.
      expect(_tc().arriveeFinale, isEmpty);
    });

    test('les nouveaux champs ne modifient pas arriveeFinale', () {
      final sans = _tc(arriveeFinale: const [2, 4, 5, 7, 8]);
      final avec = _tc(
        arriveeFinale: const [2, 4, 5, 7, 8],
        arriveeGroupes: _r5c5,
        arriveeDefinitive: true,
      );
      expect(avec.arriveeFinale, equals(sans.arriveeFinale));
    });

    test('aucune déduction automatique : les groupes ne remplissent pas la '
        'liste plate, et la liste plate ne remplit pas les groupes', () {
      // Groupes seuls : arriveeFinale reste VIDE.
      final groupesSeuls = _tc(arriveeGroupes: _r5c5);
      expect(groupesSeuls.arriveeFinale, isEmpty,
          reason: 'arriveeFinale ne doit pas être déduite des groupes');
      // Liste plate seule : les groupes restent NULL.
      final plateSeule = _tc(arriveeFinale: const [2, 4, 5, 7]);
      expect(plateSeule.arriveeGroupes, isNull,
          reason: 'aucun groupe ne doit être reconstruit depuis une liste');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2/3 — EXIGENCES 2 ET 3 : LES GROUPES EXACTS SONT PRÉSERVÉS
  // ═════════════════════════════════════════════════════════════════════════
  group('B2/3 — les trois cas réels d\'ex æquo sont préservés exactement', () {
    test('prog_17112026 R5C5 : [[2],[4],[5,7],[8],[3],[6]]', () {
      final tc = _tc(arriveeGroupes: _r5c5, arriveeDefinitive: true);
      expect(tc.arriveeGroupes, equals(_r5c5));
      expect(tc.arriveeGroupes!.length, 6, reason: '6 rangs');
      expect(tc.arriveeGroupes![2], equals(<int>[5, 7]));
      expect(tc.aDesExAequo, isTrue);
      // L'ordre DANS le groupe est celui de l'API, jamais retrié.
      expect(tc.arriveeGroupes![2].first, 5);
    });

    test('prog_17112026 R6C5 : [[12],[1,7],[9],[2],[10],[8],[6],[13],[5]]', () {
      final tc = _tc(arriveeGroupes: _r6c5, arriveeDefinitive: true);
      expect(tc.arriveeGroupes, equals(_r6c5));
      expect(tc.arriveeGroupes!.length, 9, reason: '9 rangs');
      expect(tc.arriveeGroupes![1], equals(<int>[1, 7]));
      // Le 5 est DERNIER dans son groupe d'API ; un tri le mettrait avant.
      expect(tc.arriveeGroupes![1].first, 1);
      expect(tc.aDesExAequo, isTrue);
    });

    test('prog_20112026 R5C7 : [[4],[6],[1,5],[2]]', () {
      final tc = _tc(arriveeGroupes: _r5c7, arriveeDefinitive: true);
      expect(tc.arriveeGroupes, equals(_r5c7));
      expect(tc.arriveeGroupes!.length, 4, reason: '4 rangs');
      expect(tc.arriveeGroupes![2], equals(<int>[1, 5]));
      expect(tc.aDesExAequo, isTrue);
    });

    test('l\'aplatissement sans perte rend TOUS les chevaux, y compris ceux '
        'que le code actuel perd', () {
      // Mesure : le service actuel perd le 5 sur R5C5, le 1 sur R6C5 et R5C7.
      final a = _tc(arriveeGroupes: _r5c5).arriveeGroupesAplatis!;
      expect(a, equals(<int>[2, 4, 5, 7, 8, 3, 6]));
      expect(a.contains(5), isTrue,
          reason: 'le 5 est précisément le cheval perdu par le code actuel');

      final b = _tc(arriveeGroupes: _r6c5).arriveeGroupesAplatis!;
      expect(b.length, 10, reason: '9 rangs mais 10 chevaux');
      expect(b.contains(1), isTrue);

      final c = _tc(arriveeGroupes: _r5c7).arriveeGroupesAplatis!;
      expect(c, equals(<int>[4, 6, 1, 5, 2]));
      expect(c.contains(1), isTrue);
    });

    test('le nombre de chevaux aplatís dépasse le nombre de rangs '
        'exactement quand il y a ex æquo', () {
      for (final cas in <List<List<int>>>[_r5c5, _r6c5, _r5c7]) {
        final tc = _tc(arriveeGroupes: cas);
        final nbRangs = cas.length;
        final nbChevaux = tc.arriveeGroupesAplatis!.length;
        expect(nbChevaux, greaterThan(nbRangs),
            reason: 'chaque cas réel contient au moins un ex æquo');
        expect(tc.aDesExAequo, isTrue);
      }
    });

    test('la structure rendue est non modifiable (aucune mutation possible)',
        () {
      final tc = _tc(arriveeGroupes: _r5c5);
      expect(() => tc.arriveeGroupes!.add(<int>[99]), throwsA(anything));
      expect(() => tc.arriveeGroupes![0].add(99), throwsA(anything));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2/4 — EXIGENCE 4 : PROPAGATION DANS LES RECONSTRUCTIONS
  // ═════════════════════════════════════════════════════════════════════════
  group('B2/4 — propagation dans les reconstructions', () {
    test('withDividende propage les deux champs', () {
      final tc = _tc(
        arriveeFinale: _aplatir(_r5c5),
        arriveeGroupes: _r5c5,
        arriveeDefinitive: true,
      );
      final apres = tc.withDividende(dividende: 6.5, combinaison: '5-7-2');
      expect(apres.arriveeGroupes, equals(_r5c5));
      expect(apres.arriveeDefinitive, isTrue);
      // arriveeFinale inchangée par ce chemin.
      expect(apres.arriveeFinale, equals(_aplatir(_r5c5)));
    });

    test('withResultat CONSERVE les groupes déjà connus s\'ils sont '
        'cohérents avec la nouvelle arrivée', () {
      final tc = _tc(
        arriveeFinale: _aplatir(_r5c5),
        arriveeGroupes: _r5c5,
        arriveeDefinitive: true,
      );
      final apres = tc.withResultat(
        isGagne: true,
        arrivee: _aplatir(_r5c5),
        message: 'ok',
      );
      expect(apres.arriveeGroupes, equals(_r5c5));
      expect(apres.arriveeDefinitive, isTrue);
    });

    test('withResultat REFUSE des groupes qui contrediraient la nouvelle '
        'arrivée — il ne les propage pas aveuglément', () {
      // Situation piégeuse : l'ancien ticket portait les groupes de R5C5, mais
      // le résultat enregistré porte une autre arrivée. Propager les groupes
      // associerait des ex æquo à une liste qui ne les contient pas.
      final tc = _tc(
        arriveeFinale: _aplatir(_r5c5),
        arriveeGroupes: _r5c5,
        arriveeDefinitive: true,
      );
      final apres = tc.withResultat(
        isGagne: false,
        arrivee: const [9, 8, 7],
        message: 'autre arrivée',
      );
      expect(apres.arriveeGroupes, isNull,
          reason: 'des groupes incohérents doivent devenir INCONNUS, '
              'pas être propagés ni réinventés');
      expect(apres.arriveeFinale, equals(<int>[9, 8, 7]));
    });

    test('withResultat accepte des groupes FOURNIS par l\'appelant', () {
      final tc = _tc();
      final apres = tc.withResultat(
        isGagne: true,
        arrivee: _aplatir(_r5c7),
        message: 'ok',
        arriveeGroupes: _r5c7,
        arriveeDefinitive: true,
      );
      expect(apres.arriveeGroupes, equals(_r5c7));
      expect(apres.arriveeDefinitive, isTrue);
      expect(apres.arriveeFinale, equals(_aplatir(_r5c7)));
    });

    test('withResultat conserve arriveeDefinitive même si les groupes '
        'deviennent inconnus', () {
      final tc = _tc(
        arriveeFinale: _aplatir(_r5c5),
        arriveeGroupes: _r5c5,
        arriveeDefinitive: true,
      );
      final apres = tc.withResultat(
        isGagne: false,
        arrivee: const [1, 2],
        message: 'x',
      );
      expect(apres.arriveeGroupes, isNull);
      expect(apres.arriveeDefinitive, isTrue,
          reason: 'le caractère définitif ne dépend pas de la forme');
    });

    test('avecResultat → withDividende : tout survit de bout en bout', () {
      final tc = _tc();
      final etape1 = tc.withResultat(
        isGagne: true,
        arrivee: _aplatir(_r6c5),
        message: 'ok',
        arriveeGroupes: _r6c5,
        arriveeDefinitive: true,
      );
      final etape2 = etape1.withDividende(dividende: 12.0, combinaison: '12-1');
      expect(etape2.arriveeGroupes, equals(_r6c5));
      expect(etape2.arriveeDefinitive, isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2/5 — EXIGENCE 5 : SÉRIALISATION ET RESTAURATION
  // ═════════════════════════════════════════════════════════════════════════
  group('B2/5 — sérialisation JSON et restauration', () {
    test('un ticket historique garde EXACTEMENT 28 clés (forme préservée)', () {
      // Verrou mesuré en 4-F puis en B-1 : 28 clés. Les deux nouveaux champs
      // ne doivent pas faire grossir un ticket qui n'a pas d'arrivée
      // structurée, sinon la forme des sauvegardes historiques change.
      expect(_tc().toJson().length, 28);
      // Et après relecture, la forme doit rester stable.
      final relu = TrackedCourse.fromJson(_tc().toJson());
      expect(relu.toJson().length, 28);
    });

    test('un ticket AVEC arrivée structurée porte ses deux clés en plus', () {
      final j = _tc(
        arriveeFinale: _aplatir(_r5c5),
        arriveeGroupes: _r5c5,
        arriveeDefinitive: true,
      ).toJson();
      expect(j.length, 30, reason: '28 historiques + 2 d\'arrivée');
      expect(j.containsKey('arriveeGroupes'), isTrue);
      expect(j.containsKey('arriveeDefinitive'), isTrue);
    });

    test('aller-retour JSON : les trois cas réels survivent intacts', () {
      for (final cas in <List<List<int>>>[_r5c5, _r6c5, _r5c7]) {
        final tc = _tc(
          arriveeFinale: _aplatir(cas),
          arriveeGroupes: cas,
          arriveeDefinitive: true,
        );
        final relu = TrackedCourse.fromJson(
          jsonDecode(jsonEncode(tc.toJson())) as Map<String, dynamic>,
        );
        expect(relu.arriveeGroupes, equals(cas),
            reason: 'les groupes doivent survivre EXACTEMENT');
        expect(relu.arriveeDefinitive, isTrue);
        expect(relu.arriveeFinale, equals(_aplatir(cas)));
      }
    });

    test('le JSON reste encodable et décodable par dart:convert', () {
      final tc = _tc(
        arriveeFinale: _aplatir(_r5c7),
        arriveeGroupes: _r5c7,
        arriveeDefinitive: false,
      );
      final texte = jsonEncode(tc.toJson());
      final retour = jsonDecode(texte) as Map<String, dynamic>;
      expect(retour['arriveeGroupes'], equals(<dynamic>[
        <dynamic>[4],
        <dynamic>[6],
        <dynamic>[1, 5],
        <dynamic>[2],
      ]));
      expect(retour['arriveeDefinitive'], isFalse);
    });

    test('un ancien ticket SANS les deux clés se restaure sans invention', () {
      // Sauvegarde antérieure à B-2 : aucune des deux clés.
      final ancien = <String, dynamic>{
        'numReunion': 5,
        'numCourse': 5,
        'nomCourse': 'Coupe des 5 ans',
        'hippodrome': 'Mons',
        'heureDepart': '2026-11-17T14:30:00.000',
        'nomCheval': 'Cheval 5',
        'numeroCheval': 5,
        'miseEngagee': 2.0,
        'typePari': 'Simple Gagnant',
        'numerosJoues': <int>[5],
        'scoreIA': 0.0,
        'cote': 6.5,
        'isGagne': false,
        'arriveeFinale': <int>[2, 4, 5, 7, 8],
        'messageResultat': 'perdu',
        'storageKey': 'R5C5_17112026',
      };
      final relu = TrackedCourse.fromJson(ancien);
      expect(relu.arriveeGroupes, isNull,
          reason: 'aucun groupe ne doit être fabriqué depuis arriveeFinale');
      expect(relu.arriveeDefinitive, isNull,
          reason: 'le caractère définitif ne doit pas être supposé');
      // Et la réécriture ne doit pas faire grossir le ticket.
      expect(relu.toJson().length, 28);
      // L'arrivée historique plate est intacte.
      expect(relu.arriveeFinale, equals(<int>[2, 4, 5, 7, 8]));
    });

    test('aucun getter dérivé n\'est persisté', () {
      final j = _tc(arriveeGroupes: _r5c5, arriveeDefinitive: true).toJson();
      expect(j.containsKey('aDesExAequo'), isFalse);
      expect(j.containsKey('arriveeGroupesAplatis'), isFalse);
    });

    test('arriveeFinale est écrite EXACTEMENT comme avant', () {
      // La clé existe, elle est inconditionnelle, et sa valeur est la liste
      // plate brute — pas un aplatissement de groupes.
      final j = _tc(
        arriveeFinale: const [9, 8, 7],
        arriveeGroupes: _r5c7,
      ).toJson();
      expect(j['arriveeFinale'], equals(<int>[9, 8, 7]),
          reason: 'arriveeFinale ne doit jamais être recalculée');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2/6 — EXIGENCE 6 : UNE ARRIVÉE PROVISOIRE N'EST JAMAIS DÉFINITIVE
  // ═════════════════════════════════════════════════════════════════════════
  group('B2/6 — provisoire n\'est jamais enregistrée comme définitive', () {
    test('arriveeDefinitive = false survit à l\'aller-retour JSON', () {
      final tc = _tc(
        arriveeGroupes: _r5c5,
        arriveeDefinitive: false,
      );
      final relu = TrackedCourse.fromJson(
        jsonDecode(jsonEncode(tc.toJson())) as Map<String, dynamic>,
      );
      expect(relu.arriveeDefinitive, isFalse,
          reason: 'false ne doit pas devenir null ni true');
    });

    test('l\'absence d\'information reste null, jamais true', () {
      // Contrat : `null` = inconnu. Transformer l'inconnu en « définitive »
      // serait exactement le raccourci interdit.
      expect(_tc().arriveeDefinitive, isNull);
      final relu = TrackedCourse.fromJson(_tc().toJson());
      expect(relu.arriveeDefinitive, isNull);
    });

    test('provisoire et définitif restent DISTINCTS dans le JSON', () {
      final provisoire = _tc(arriveeGroupes: _r5c5, arriveeDefinitive: false);
      final definitif = _tc(arriveeGroupes: _r5c5, arriveeDefinitive: true);
      expect(provisoire.toJson()['arriveeDefinitive'], isFalse);
      expect(definitif.toJson()['arriveeDefinitive'], isTrue);
      expect(provisoire.toJson()['arriveeDefinitive'],
          isNot(definitif.toJson()['arriveeDefinitive']));
    });

    test('aucune valeur par défaut ne transforme un provisoire en définitif',
        () {
      // Un ticket construit sans préciser le caractère définitif ne doit pas
      // hériter de `true` par défaut.
      final tc = _tc(arriveeGroupes: _r5c5);
      expect(tc.arriveeDefinitive, isNot(isTrue));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2/7 — LECTURE STRICTE : RIEN N'EST INVENTÉ
  // ═════════════════════════════════════════════════════════════════════════
  group('B2/7 — la lecture refuse tout ce qui n\'est pas exact', () {
    Map<String, dynamic> base() => _tc().toJson();

    test('une structure mal formée donne null, pas une correction', () {
      final j = base()..['arriveeGroupes'] = <dynamic>[
            <dynamic>[2],
            'pas une liste',
          ];
      expect(TrackedCourse.fromJson(j).arriveeGroupes, isNull);
    });

    test('un rang VIDE fait refuser l\'arrivée ENTIÈRE', () {
      final j = base()..['arriveeGroupes'] = <dynamic>[
            <dynamic>[2],
            <dynamic>[],
          ];
      expect(TrackedCourse.fromJson(j).arriveeGroupes, isNull,
          reason: 'mieux vaut inconnu qu\'une arrivée partielle');
    });

    test('un numéro non entier ou négatif fait refuser l\'ensemble', () {
      final j = base()..['arriveeGroupes'] = <dynamic>[
            <dynamic>[2],
            <dynamic>[0],
          ];
      expect(TrackedCourse.fromJson(j).arriveeGroupes, isNull);

      final j2 = base()..['arriveeGroupes'] = <dynamic>[
            <dynamic>[2],
            <dynamic>['x'],
          ];
      expect(TrackedCourse.fromJson(j2).arriveeGroupes, isNull);
    });

    test('une liste vide donne null, pas une liste vide', () {
      // « aucune arrivée » et « groupes vides » ne sont pas la même chose.
      final j = base()..['arriveeGroupes'] = <dynamic>[];
      expect(TrackedCourse.fromJson(j).arriveeGroupes, isNull);
    });

    test('une valeur d\'un autre type donne null', () {
      final j = base()..['arriveeGroupes'] = 'groupes';
      expect(TrackedCourse.fromJson(j).arriveeGroupes, isNull);
    });

    test('arriveeDefinitive d\'un autre type donne null', () {
      final j = base()..['arriveeDefinitive'] = 'oui';
      expect(TrackedCourse.fromJson(j).arriveeDefinitive, isNull);
    });

    test('les groupes lus sont non modifiables', () {
      final tc = TrackedCourse.fromJson(
        base()..['arriveeGroupes'] = <dynamic>[
              <dynamic>[2],
              <dynamic>[5, 7],
            ],
      );
      expect(tc.arriveeGroupes, equals(const [
        [2], [5, 7]
      ]));
      expect(() => tc.arriveeGroupes!.add(<int>[1]), throwsA(anything));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2/8 — NON-RÉGRESSION : LES CHAMPS DE B-1 ET 4-F SURVIVENT
  // ═════════════════════════════════════════════════════════════════════════
  group('B2/8 — non-régression des lots précédents', () {
    test('les sept champs de B-1 ne sont pas perdus par l\'ajout de B-2', () {
      // `toJson` doit toujours écrire 30 clés avec les gains ET l'arrivée.
      final tc = TrackedCourse(
        numReunion: 5,
        numCourse: 5,
        nomCourse: 'C',
        hippodrome: 'H',
        heureDepart: DateTime(2026, 11, 17),
        nomCheval: 'X',
        numeroCheval: 5,
        miseEngagee: 2.0,
        storageKey: 'k',
        etatGain: null,
        arriveeGroupes: _r5c5,
        arriveeDefinitive: true,
      );
      final j = tc.toJson();
      expect(j.length, 30);
      // Les 4 clés 4-F restent inconditionnelles.
      for (final cle in <String>[
        'codePmuOfficiel',
        'varianteChoisie',
        'numerosDansOrdre',
        'formulePari'
      ]) {
        expect(j.containsKey(cle), isTrue, reason: '$cle doit rester écrite');
      }
      // Les 22 clés historiques + storageKey restent écrites.
      expect(j.containsKey('arriveeFinale'), isTrue);
      expect(j.containsKey('gainNetFictif'), isFalse);
    });

    test('aucun calcul financier n\'est introduit par B-2', () {
      // Contrôle statique : le code de production ne doit contenir aucun
      // calcul de gain lié à l'arrivée structurée.
      final src = File('lib/services/alert_service.dart').readAsStringSync();
      for (final interdit in <String>[
        'totauxParArrivee',
        'gainDepuisGroupes',
        'montantDepuisArriveeGroupes',
      ]) {
        expect(src.contains(interdit), isFalse, reason: interdit);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2/9 — INVARIANT : LA PROPAGATION NE PEUT PAS ÊTRE OUBLIÉE
  //
  //  Même méthode qu'en B-1 : liste NOMINATIVE des reconstructions, chacune
  //  ancrée sur sa signature de méthode. Aucune heuristique fragile.
  // ═════════════════════════════════════════════════════════════════════════
  group('B2/9 — invariant de propagation de B-2', () {
    test('les cinq reconstructions portent les deux champs', () {
      final reconstructions = <List<String>>[
        ['lib/services/alert_service.dart', 'Future<void> ajouterSuivi('],
        ['lib/services/alert_service.dart', 'TrackedCourse withResultat({'],
        ['lib/services/alert_service.dart', 'TrackedCourse withDividende({'],
        [
          'lib/services/alert_service.dart',
          'factory TrackedCourse.fromJson(Map<String, dynamic> j) => TrackedCourse('
        ],
      ];

      final manquants = <String>[];
      for (final entree in reconstructions) {
        final chemin = entree[0];
        final signature = entree[1];
        final src = File(chemin).readAsStringSync();
        final debut = src.indexOf(signature);
        if (debut < 0) {
          manquants.add('$chemin : méthode introuvable « $signature »');
          continue;
        }
        final fermeture =
            RegExp(r'\n[ \t]*\)[ \t]*;').firstMatch(src.substring(debut));
        if (fermeture == null) {
          manquants.add('$chemin : fin de bloc introuvable pour « $signature »');
          continue;
        }
        final bloc = src.substring(debut, debut + fermeture.end);
        for (final champ in <String>['arriveeGroupes', 'arriveeDefinitive']) {
          if (!bloc.contains(champ)) {
            manquants.add('$chemin (`$signature`) ne propage pas $champ');
          }
        }
      }
      expect(manquants, isEmpty, reason: manquants.join(' | '));
    });

    test('aucune reconstruction ne peut réinventer des groupes', () {
      // Contrôle statique : le seul constructeur de groupes est la lecture
      // stricte. Aucune ligne ne doit déduire des groupes d'une liste plate.
      final src = File('lib/services/alert_service.dart').readAsStringSync();
      // La lecture stricte ne consulte jamais arriveeFinale.
      final debut = src.indexOf('static List<List<int>>? _lireArriveeGroupes(');
      expect(debut, greaterThan(0));
      final fin = src.indexOf('\n  }', debut);
      final corps = src.substring(debut, fin);
      expect(corps.contains('arriveeFinale'), isFalse,
          reason: 'la lecture des groupes ne doit JAMAIS regarder la liste '
              'plate : ce serait reconstruire des groupes par déduction');
    });
  });
}
