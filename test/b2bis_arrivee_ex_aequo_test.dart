// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-2 bis — CORRECTION DE L'ÉCRASEMENT DES EX ÆQUO
//
//  ── LE DÉFAUT CORRIGÉ (mesuré, pas supposé) ───────────────────────────────
//  `ZoneTurfService.chargerResultatsCourseComplet` construisait l'arrivée
//  avec `rangParNumero[rangInt] = num`, une `Map<int,int>` indexée par RANG.
//  Deux chevaux ex æquo partagent le même rang : le second écrasait le
//  premier, et le cheval perdant DISPARAISSAIT de l'arrivée. Ce n'était donc
//  pas seulement une perte de frontières de groupes, mais une perte de
//  cheval.
//
//  Sur les trois courses réelles portant un ex æquo :
//    prog_17112026 R5C5  [[2],[4],[5,7],[8],[3],[6]]        → le 5 disparaissait
//    prog_17112026 R6C5  [[12],[1,7],[9],[2],[10],[8],[6],[13],[5]]
//                                                          → le 1 disparaissait
//    prog_20112026 R5C7  [[4],[6],[1,5],[2]]               → le 1 disparaissait
//
//  ── CE QUE CE LOT CHANGE ──────────────────────────────────────────────────
//  La `Map<int,int>` est remplacée par `Map<int,List<int>>`. Tous les chevaux
//  d'un même rang y sont conservés, dans l'ordre de l'API. Aucun départage,
//  aucun tri, aucune invention.
//
//  ── CE QUE CE LOT NE CHANGE PAS ───────────────────────────────────────────
//  • `arriveeFinale` reste `List<int>` (seul son CONTENU cesse d'être amputé).
//  • Aucun calcul de gain, de ROI, de statistique ni d'IA n'est touché.
//  • Aucun recalcul rétroactif : les tickets déjà enregistrés gardent leur
//    valeur ; seules les nouvelles lectures bénéficient de la correction.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/widgets/arrivee_officielle_groupes_widget.dart';

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

// ─── Lecture du CODE SEUL, commentaires retirés ─────────────────────────────
//
// Les assertions de B2B/2 portent sur du code, PAS sur des commentaires.
// Or le commentaire correctif du service cite volontairement l'ancien code
// (`rangParNumero[rangInt] = num`) pour documenter le défaut. Chercher cette
// chaîne dans le fichier BRUT produirait donc un faux positif : c'est
// exactement ce qui faisait échouer l'assertion lors du premier passage.
//
// Ce lecteur retire les commentaires `//` en respectant les chaînes littérales
// (une URL `'https://...'` ne doit pas être tronquée). Le fichier ne contient
// ni `'''` ni `/* */` — mesuré — donc cette lecture est suffisante.
String _codeSeul(String source) {
  final out = StringBuffer();
  for (final ligne in source.split('\n')) {
    var i = 0;
    var enChaine = false;
    var quote = '';
    var coupe = ligne.length;
    while (i < ligne.length) {
      final c = ligne[i];
      if (enChaine) {
        if (c.codeUnitAt(0) == 92) { // antislash
          i += 2;
          continue;
        }
        if (c == quote) enChaine = false;
        i++;
        continue;
      }
      if (c == '"' || c == "'") {
        enChaine = true;
        quote = c;
        i++;
        continue;
      }
      if (c == '/' && i + 1 < ligne.length && ligne[i + 1] == '/') {
        coupe = i;
        break;
      }
      i++;
    }
    out.writeln(ligne.substring(0, coupe));
  }
  return out.toString();
}

// ─── Reproduction FIDÈLE de l'ancien algorithme, pour prouver la différence ──

/// Ce que l'ancien code produisait : `Map<int,int>` indexée par rang.
List<int> _ancienAlgorithme(List<List<int>> groupes) {
  final Map<int, int> rangParNumero = {};
  var rang = 1;
  for (final g in groupes) {
    for (final num in g) {
      rangParNumero[rang] = num; // ← écrasement
    }
    rang += 1;
  }
  final rangs = rangParNumero.keys.toList()..sort();
  return rangs.map((r) => rangParNumero[r]!).toList();
}

/// Ce que le code corrigé produit : `Map<int,List<int>>`.
List<int> _nouvelAlgorithme(List<List<int>> groupes) {
  final Map<int, List<int>> rangsGroupes = {};
  var rang = 1;
  for (final g in groupes) {
    for (final num in g) {
      rangsGroupes.putIfAbsent(rang, () => <int>[]).add(num);
    }
    rang += 1;
  }
  final rangs = rangsGroupes.keys.toList()..sort();
  return <int>[for (final r in rangs) ...rangsGroupes[r]!];
}

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  B2B/1 — LA PREUVE : AUCUN CHEVAL NE DISPARAÎT PLUS
  // ═════════════════════════════════════════════════════════════════════════
  group('B2B/1 — preuve de non-disparition sur les trois cas réels', () {
    test('l\'ancien algorithme PERDAIT un cheval sur chaque cas — mesure', () {
      // Ce test documente le défaut. Il ne teste pas le code de production :
      // il reproduit l'ancien calcul pour établir que la différence est réelle.
      expect(_ancienAlgorithme(_r5c5), equals(<int>[2, 4, 7, 8, 3, 6]));
      expect(_ancienAlgorithme(_r5c5).contains(5), isFalse,
          reason: 'le 5 était le cheval perdu sur R5C5');
      expect(_ancienAlgorithme(_r6c5).contains(1), isFalse,
          reason: 'le 1 était le cheval perdu sur R6C5');
      expect(_ancienAlgorithme(_r5c7).contains(1), isFalse,
          reason: 'le 1 était le cheval perdu sur R5C7');
    });

    test('le nouvel algorithme CONSERVE tous les chevaux', () {
      expect(_nouvelAlgorithme(_r5c5), equals(<int>[2, 4, 5, 7, 8, 3, 6]));
      expect(_nouvelAlgorithme(_r6c5),
          equals(<int>[12, 1, 7, 9, 2, 10, 8, 6, 13, 5]));
      expect(_nouvelAlgorithme(_r5c7), equals(<int>[4, 6, 1, 5, 2]));
    });

    test('nouvel algorithme = aplatissement exact des groupes, sur les 3 cas',
        () {
      for (final cas in <List<List<int>>>[_r5c5, _r6c5, _r5c7]) {
        expect(_nouvelAlgorithme(cas), equals(_aplatir(cas)));
      }
    });

    test('le nombre exact de chevaux est conservé', () {
      expect(_nouvelAlgorithme(_r5c5).length, 7);
      expect(_nouvelAlgorithme(_r6c5).length, 10);
      expect(_nouvelAlgorithme(_r5c7).length, 5);
      // Mesure de l'écart avec l'ancien comportement : -1 dans les trois cas.
      expect(_nouvelAlgorithme(_r5c5).length - _ancienAlgorithme(_r5c5).length,
          1);
      expect(_nouvelAlgorithme(_r6c5).length - _ancienAlgorithme(_r6c5).length,
          1);
      expect(_nouvelAlgorithme(_r5c7).length - _ancienAlgorithme(_r5c7).length,
          1);
    });

    test('aucun doublon n\'est introduit', () {
      for (final cas in <List<List<int>>>[_r5c5, _r6c5, _r5c7]) {
        final plate = _nouvelAlgorithme(cas);
        expect(plate.toSet().length, plate.length,
            reason: 'aucun numéro ne doit apparaître deux fois');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2B/2 — LE CODE DE PRODUCTION NE CONTIENT PLUS L'ÉCRASEMENT
  // ═════════════════════════════════════════════════════════════════════════
  group('B2B/2 — le service de production est corrigé', () {
    // Le lecteur ci-dessus doit être fiable, sinon les tests qui en dépendent
    // seraient vacus. On le prouve sur des cas choisis.
    test('le lecteur de code seul n\'est pas vacu', () {
      expect(_codeSeul('a(); // rangParNumero[r] = x'), contains('a();'));
      expect(_codeSeul('a(); // rangParNumero[r] = x'),
          isNot(contains('rangParNumero')));
      // Une URL ne doit pas être tronquée par le `//` de son schéma.
      expect(_codeSeul("final u = 'https://pmu.fr/x';"),
          contains("'https://pmu.fr/x'"));
      // Un `//` à l'intérieur d'une chaîne n'est pas un commentaire.
      expect(_codeSeul("final s = 'a // b';"), contains("'a // b'"));
      // Le code réel du service, lui, survit au retrait.
      final src = File('lib/services/zone_turf_service.dart').readAsStringSync();
      expect(_codeSeul(src),
          contains('rangsGroupes.putIfAbsent(rangInt, () => <int>[]).add(num)'));
    });

    test('la Map<int,int> indexée par rang a disparu', () {
      final src = File('lib/services/zone_turf_service.dart').readAsStringSync();
      final code = _codeSeul(src);
      // Le texte brut, lui, contient encore l'ancien code : c'est la citation
      // du commentaire correctif. On le MESURE pour que le test reste honnête.
      expect(src.contains('rangParNumero[rangInt] = num'), isTrue,
          reason: 'citation volontaire dans le commentaire de correction');
      // Mais le CODE, lui, ne le contient plus.
      expect(code.contains('Map<int, int> rangParNumero'), isFalse,
          reason: 'la structure qui écrasait les ex æquo ne doit plus exister');
      expect(code.contains('rangParNumero[rangInt] = num'), isFalse,
          reason: 'l\'affectation qui écrasait ne doit plus exister');
      // Forme générique : aucune affectation indexée par un identifiant
      // contenant « rang », quel qu'en soit le nom.
      expect(
          RegExp(r'\[[A-Za-z_]*[Rr]ang[A-Za-z_]*\]\s*=[^=]').hasMatch(code),
          isFalse,
          reason: 'aucune Map indexée par rang ne doit subsister');
    });

    test('la structure de remplacement conserve une liste par rang', () {
      final src = File('lib/services/zone_turf_service.dart').readAsStringSync();
      final code = _codeSeul(src);
      expect(code.contains('Map<int, List<int>> rangsGroupes'), isTrue);
      expect(code.contains('.putIfAbsent(rangInt, () => <int>[]).add(num)'),
          isTrue,
          reason: 'l\'ajout doit se faire dans une liste, jamais en écrasement');
    });

    test('les groupes sont joints à l\'aplatissement dans ResultatCourse', () {
      final src = File('lib/services/zone_turf_service.dart').readAsStringSync();
      final code = _codeSeul(src);
      expect(code.contains('arriveeGroupes: List<List<int>>.unmodifiable'),
          isTrue);
      // ★ GARDE RE-POINTÉE (BLOC 1, correction du drapeau définitif).
      //
      //   Ce test vérifiait auparavant la présence littérale de
      //   `arriveeDefinitive: _lireDrapeauDefinitif(data)`, où `data` est le
      //   corps de `/participants`. Or cette lecture était le DÉFAUT MESURÉ :
      //   ce corps ne porte pas le drapeau (clés racine : participants,
      //   ecuries, spriteCasaques, cached), si bien que `null` était rendu
      //   systématiquement et qu'aucune perte ne pouvait être établie.
      //
      //   La garde n'est donc pas supprimée : elle est RE-POINTÉE vers
      //   l'invariant corrigé, et COMPLÉTÉE d'une interdiction explicite.
      //   Elle est plus exigeante qu'avant, pas moins.
      expect(code.contains('arriveeDefinitive: lectureDrapeau.valeur'), isTrue,
          reason: 'le drapeau doit venir de la lecture par course');
      expect(
          code.contains('arriveeDefinitive: _lireDrapeauDefinitif(data)'),
          isFalse,
          reason: 'INTERDIT : le corps de /participants ne porte pas le '
              'drapeau — le relire là reproduirait le défaut mesuré');
      expect(code.contains('_drapeauDefinitifDepuisCourse('), isTrue,
          reason: 'la lecture doit cibler l\'endpoint qui publie le drapeau');
    });

    test('aucun tri ni départage n\'est appliqué à l\'intérieur d\'un rang', () {
      final src = File('lib/services/zone_turf_service.dart').readAsStringSync();
      final code = _codeSeul(src);

      // On isole la SEULE fonction concernée. Le service contient un autre
      // tri (sur `partants`, dans `_chargerPartants`), totalement étranger à
      // l'arrivée : l'ignorer est une mesure, pas un passe-droit.
      const debut = 'static Future<ResultatCourse?> chargerResultatsCourseComplet(';
      const finMarqueur = 'static Future<List<int>?> chargerResultatsCourse(';
      final i = code.indexOf(debut);
      final j = code.indexOf(finMarqueur);
      expect(i, greaterThanOrEqualTo(0),
          reason: 'la fonction corrigée doit exister');
      expect(j, greaterThan(i), reason: 'ses bornes doivent être mesurables');
      final fonction = code.substring(i, j);

      // Le seul tri autorisé porte sur les CLÉS de rang.
      expect(fonction.contains('rangsGroupes.keys.toList()..sort()'), isTrue);
      // Mesure : UN SEUL tri dans cette fonction, et c'est celui-là.
      expect(RegExp(r'sort\(').allMatches(fonction).length, 1,
          reason: 'un seul tri dans la fonction, sur les clés de rang');
      // Aucun tri sur les numéros eux-mêmes.
      expect(RegExp(r'rangsGroupes\[r\]!\.\.sort\(\)').hasMatch(fonction),
          isFalse);
      expect(
          RegExp(r'(rangsGroupes\[r\]!|\bnum\b|\bnumero\b|\.add)\s*\.\.sort\(')
              .hasMatch(fonction),
          isFalse,
          reason: 'aucun tri sur les listes de numéros');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2B/3 — RANGS OFFICIELS ET BADGES : LA SPÉCIFICATION EXACTE
  // ═════════════════════════════════════════════════════════════════════════
  group('B2B/3 — rangs officiels et badges', () {
    test('R5C5 : rangs OFFICIELS attendus [1,2,3,3,5,6,6]', () {
      // Spécification validée : 2→1er, 4→2e, 5→3e, 7→3e, 8→5e, 3→6e, 6→7e.
      final rangsGroupes = rangsOfficiels(_r5c5);
      expect(rangsGroupes, equals(<int>[1, 2, 3, 5, 6, 7]));

      // Rang de CHAQUE cheval.
      final rangParCheval = <int, int>{};
      for (var gi = 0; gi < _r5c5.length; gi++) {
        for (final num in _r5c5[gi]) {
          rangParCheval[num] = rangsGroupes[gi];
        }
      }
      expect(rangParCheval[2], 1, reason: 'cheval 2 : 1er');
      expect(rangParCheval[4], 2, reason: 'cheval 4 : 2e');
      expect(rangParCheval[5], 3, reason: 'cheval 5 : 3e (ex æquo)');
      expect(rangParCheval[7], 3, reason: 'cheval 7 : 3e (ex æquo)');
      expect(rangParCheval[8], 5, reason: 'cheval 8 : 5e — et NON 4e');
      expect(rangParCheval[3], 6, reason: 'cheval 3 : 6e');
      expect(rangParCheval[6], 7, reason: 'cheval 6 : 7e');
    });

    test('R6C5 : rangs officiels [1,2,4,5,6,7,8,9,10]', () {
      final rangs = rangsOfficiels(_r6c5);
      expect(rangs, equals(<int>[1, 2, 4, 5, 6, 7, 8, 9, 10]),
          reason: 'un groupe de 2 au rang 2 consomme les places 2 et 3');
    });

    test('R5C7 : rangs officiels [1,2,3,5]', () {
      final rangs = rangsOfficiels(_r5c7);
      expect(rangs, equals(<int>[1, 2, 3, 5]),
          reason: 'un groupe de 2 au rang 3 consomme les places 3 et 4');
    });

    test('le badge n\'est demandé QUE pour les chevaux ex æquo', () {
      // `arriveeAvecExAequo` décide du rendu. Pour les trois cas : vrai.
      expect(arriveeAvecExAequo(_r5c5), isTrue);
      expect(arriveeAvecExAequo(_r6c5), isTrue);
      expect(arriveeAvecExAequo(_r5c7), isTrue);
      // Une arrivée sans ex æquo : aucun badge.
      expect(arriveeAvecExAequo(const [
        [1], [2], [3]
      ]), isFalse);
      // Groupes inconnus : aucun badge (on n'affirme pas l'absence).
      expect(arriveeAvecExAequo(null), isFalse);
      expect(arriveeAvecExAequo(const []), isFalse);
    });

    test('les libellés de rang sont corrects en français', () {
      expect(libelleRang(1), '1er');
      expect(libelleRang(2), '2e');
      expect(libelleRang(3), '3e');
      expect(libelleRang(5), '5e');
      expect(libelleRang(7), '7e');
    });

    test('le badge gris utilise bien la couleur grise documentée', () {
      // Couleur du badge « Ex æquo » : gris 0xFF9E9E9E, distincte du doré
      // réservé à la mise en évidence des numéros.
      expect(kCouleurBadgeExAequo, const Color(0xFF9E9E9E));
      expect(kCouleurExAequo, const Color(0xFFFFD700));
      expect(kCouleurBadgeExAequo == kCouleurExAequo, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2B/4 — ARRIVÉE NORMALE, PROVISOIRE, HISTORIQUE, INVALIDE
  // ═════════════════════════════════════════════════════════════════════════
  group('B2B/4 — cas normaux et cas limites', () {
    test('arrivée NORMALE sans ex æquo : 7 chevaux, 7 rangs distincts', () {
      const cas = [
        [7], [12], [8], [6], [3], [1], [9]
      ];
      expect(_nouvelAlgorithme(cas), equals(<int>[7, 12, 8, 6, 3, 1, 9]));
      expect(rangsOfficiels(cas), equals(<int>[1, 2, 3, 4, 5, 6, 7]));
      // Aucun badge : le rendu historique est conservé.
      expect(arriveeAvecExAequo(cas), isFalse);
    });

    test('arrivée PROVISOIRE : ResultatCourse porte le drapeau false', () {
      const r = ResultatCourse(
        arriveeOfficielle: <int>[2, 4, 5, 7, 8],
        arriveeGroupes: _r5c5,
        arriveeDefinitive: false,
      );
      expect(r.arriveeDefinitive, isFalse,
          reason: 'provisoire ne doit jamais devenir définitif');
      // Et la conversion en JSON du ticket doit conserver ce false.
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
        arriveeFinale: const <int>[2, 4, 5, 7, 8],
        arriveeGroupes: _r5c5,
        arriveeDefinitive: false,
      );
      final relu = TrackedCourse.fromJson(
        jsonDecode(jsonEncode(tc.toJson())) as Map<String, dynamic>,
      );
      expect(relu.arriveeDefinitive, isFalse);
    });

    test('arrivée HISTORIQUE sans groupes : aucun faux badge', () {
      // Un ticket ancien a `arriveeFinale` mais AUCUN groupe. On ne doit
      // jamais fabriquer de groupes à partir de la liste plate, donc aucun
      // badge ne peut apparaître.
      final ancien = <String, dynamic>{
        'numReunion': 5,
        'numCourse': 5,
        'nomCourse': 'C',
        'hippodrome': 'H',
        'heureDepart': '2026-11-17T14:30:00.000',
        'nomCheval': 'X',
        'numeroCheval': 5,
        'miseEngagee': 2.0,
        'typePari': 'Simple Gagnant',
        'numerosJoues': <int>[5],
        'scoreIA': 0.0,
        'cote': 6.5,
        'isGagne': false,
        'arriveeFinale': <int>[2, 4, 5, 7, 8],
        'storageKey': 'R5C5_17112026',
      };
      final relu = TrackedCourse.fromJson(ancien);
      expect(relu.arriveeGroupes, isNull);
      expect(arriveeAvecExAequo(relu.arriveeGroupes), isFalse,
          reason: 'sans groupes connus, aucun badge ne doit apparaître');
      // Et la liste plate historique reste lisible telle quelle.
      expect(relu.arriveeFinale, equals(<int>[2, 4, 5, 7, 8]));
    });

    test('données officielles INVALIDES : aucun groupe inventé', () {
      // Structure où un rang n'est pas une liste.
      const Map<String, dynamic> base = <String, dynamic>{};
      final j = Map<String, dynamic>.from(base)
        ..addAll(<String, dynamic>{
          'numReunion': 5,
          'numCourse': 5,
          'nomCourse': 'C',
          'hippodrome': 'H',
          'heureDepart': '2026-11-17T14:30:00.000',
          'nomCheval': 'X',
          'numeroCheval': 5,
          'miseEngagee': 2.0,
          'typePari': 'Simple Gagnant',
          'numerosJoues': <int>[5],
          'scoreIA': 0.0,
          'cote': 6.5,
          'arriveeGroupes': <dynamic>[
            <dynamic>[2],
            'invalide',
          ],
        });
      expect(TrackedCourse.fromJson(j).arriveeGroupes, isNull);
    });

    test('un groupe vide dans l\'arrivée fait refuser l\'ensemble', () {
      final j = <String, dynamic>{
        'numReunion': 5,
        'numCourse': 5,
        'nomCourse': 'C',
        'hippodrome': 'H',
        'heureDepart': '2026-11-17T14:30:00.000',
        'nomCheval': 'X',
        'numeroCheval': 5,
        'miseEngagee': 2.0,
        'typePari': 'Simple Gagnant',
        'numerosJoues': <int>[5],
        'scoreIA': 0.0,
        'cote': 6.5,
        'arriveeGroupes': <dynamic>[
          <dynamic>[2],
          <dynamic>[],
        ],
      };
      expect(TrackedCourse.fromJson(j).arriveeGroupes, isNull);
    });

    test('un groupe d\'un seul cheval n\'est pas un ex æquo', () {
      expect(arriveeAvecExAequo(const [
        [1], [2], [3]
      ]), isFalse);
      // Mais un groupe de 2 oui, où qu'il soit.
      expect(arriveeAvecExAequo(const [
        [1, 2], [3]
      ]), isTrue);
      expect(arriveeAvecExAequo(const [
        [1], [2, 3]
      ]), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2B/5 — TRANSMISSION JUSQU'AU TICKET
  // ═════════════════════════════════════════════════════════════════════════
  group('B2B/5 — transmission et conservation dans TrackedCourse', () {
    TrackedCourse ticket() => TrackedCourse(
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
          storageKey: 'R5C5_17112026',
        );

    test('withResultat conserve les groupes transmis', () {
      final apres = ticket().withResultat(
        isGagne: true,
        arrivee: _aplatir(_r5c5),
        message: 'ok',
        arriveeGroupes: _r5c5,
        arriveeDefinitive: true,
      );
      expect(apres.arriveeGroupes, equals(_r5c5));
      expect(apres.arriveeDefinitive, isTrue);
      expect(apres.aDesExAequo, isTrue);
    });

    test('les trois cas réels survivent au cycle complet '
        'withResultat → JSON → fromJson', () {
      for (final cas in <List<List<int>>>[_r5c5, _r6c5, _r5c7]) {
        final apres = ticket().withResultat(
          isGagne: false,
          arrivee: _aplatir(cas),
          message: 'x',
          arriveeGroupes: cas,
          arriveeDefinitive: true,
        );
        final relu = TrackedCourse.fromJson(
          jsonDecode(jsonEncode(apres.toJson())) as Map<String, dynamic>,
        );
        expect(relu.arriveeGroupes, equals(cas));
        expect(relu.arriveeFinale, equals(_aplatir(cas)));
        expect(rangsOfficiels(relu.arriveeGroupes!),
            equals(rangsOfficiels(cas)));
      }
    });

    test('arriveeFinale reste List<int> — format historique intact', () {
      final apres = ticket().withResultat(
        isGagne: true,
        arrivee: _aplatir(_r5c5),
        message: 'ok',
        arriveeGroupes: _r5c5,
        arriveeDefinitive: true,
      );
      final List<int> plate = apres.arriveeFinale;
      expect(plate, equals(<int>[2, 4, 5, 7, 8, 3, 6]));
      // Le JSON contient bien une liste de nombres, pas une liste de listes.
      final brut = apres.toJson()['arriveeFinale'];
      expect(brut, isA<List<dynamic>>());
      expect((brut as List<dynamic>).every((e) => e is int), isTrue,
          reason: 'arriveeFinale doit rester une liste plate de nombres');
    });

    test('une arrivée provisoire n\'est jamais enregistrée comme définitive',
        () {
      // Règle appliquée par l'appelant : si definitive == false, on ne
      // transmet AUCUN groupe et le drapeau reste false.
      const bool definitive = false;
      final groupesAEnregistrer = definitive == false ? null : _r5c5;
      final apres = ticket().withResultat(
        isGagne: true,
        arrivee: _aplatir(_r5c5),
        message: 'ok',
        arriveeGroupes: groupesAEnregistrer,
        arriveeDefinitive: definitive,
      );
      expect(apres.arriveeGroupes, isNull,
          reason: 'une arrivée provisoire ne doit pas être présentée '
              'comme établie');
      expect(apres.arriveeDefinitive, isFalse,
          reason: 'le caractère provisoire doit rester lisible');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2B/6 — NON-RÉGRESSION : AUCUN CALCUL FINANCIER OU IA TOUCHÉ
  // ═════════════════════════════════════════════════════════════════════════
  group('B2B/6 — protections respectées', () {
    test('aucun calcul de gain n\'est introduit dans les fichiers modifiés',
        () {
      const interdits = <String>[
        'gainNet =',
        'roi =',
        'dividendePmuReel *',
        'reduce((a, b) => a > b',
      ];
      for (final chemin in <String>[
        'lib/services/zone_turf_service.dart',
        'lib/models/zt_models.dart',
      ]) {
        final src = File(chemin).readAsStringSync();
        for (final i in interdits) {
          expect(src.contains(i), isFalse,
              reason: '$i trouvé dans $chemin — hors périmètre B-2 bis');
        }
      }
    });

    test('le fichier de rendu ex æquo n\'est pas modifié par ce lot', () {
      // Le rendu existait déjà (lot A6) : ce lot ne fait que l\'alimenter.
      // Ses fonctions restent purement visuelles.
      final src = File('lib/widgets/arrivee_officielle_groupes_widget.dart')
          .readAsStringSync();
      expect(src.contains('DateTime.now('), isFalse);
      expect(src.contains('SharedPreferences'), isFalse);
      expect(src.contains('http'), isFalse);
    });

    test('aucune écriture de service n\'a été ajoutée au rendu', () {
      // Le widget doit rester un pur rendu : aucune référence à un service.
      final src = File('lib/widgets/arrivee_officielle_groupes_widget.dart')
          .readAsStringSync();
      final imports = src
          .split('\n')
          .where((l) => l.trimLeft().startsWith('import '))
          .toList();
      expect(imports.length, 1, reason: 'un seul import, material : $imports');
      expect(imports.single.contains('material.dart'), isTrue);
    });
  });
}
