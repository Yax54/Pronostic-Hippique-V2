// ═══════════════════════════════════════════════════════════════════════════
//  a7_33a_registre_empreinte_test.dart — A7 / 3.3-A
//  TESTS UNITAIRES DU MODÈLE `elo_registre_v3` ET DE L'EMPREINTE ELO
//
//  ⚠️ Ce fichier ne teste AUCUNE formule ELO, AUCUN coefficient K, AUCUNE
//     probabilité, AUCUN facteur de distance, AUCUN delta, AUCUN mécanisme
//     d'apprentissage IA, AUCUN poids, AUCUN seuil métier, AUCUNE règle TOP3.
//     Aucune valeur ELO n'est calculée ni recalculée ici.
//
//  ⚠️ AUCUN SharedPreferences n'est instancié : les deux fichiers testés
//     (`lib/utils/elo_empreinte.dart`, `lib/models/elo_registre_v3.dart`)
//     n'en importent aucun, et un test structurel le vérifie explicitement.
//
//  Chaque valeur attendue ci-dessous a été MESURÉE sur le code réel avant
//  d'être écrite (script `measure_33a.dart`). Aucune constante n'est devinée.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/elo_registre_v3.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/utils/elo_empreinte.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Aides de construction
// ───────────────────────────────────────────────────────────────────────────

/// Empreintes de forme valide (16 hexadécimaux minuscules), pour les tests
/// d'invariants. Ce ne sont PAS des empreintes d'un contenu réel.
const String _fpA = '0123456789abcdef';
const String _fpB = 'fedcba9876543210';

EloScore _sc(
  double rating, {
  int nb = 0,
  double varMois = 0.0,
  String nom = 'X',
}) =>
    EloScore(
      nomCheval: nom,
      rating: rating,
      nbCourses: nb,
      variationMois: varMois,
    );

EntreeRegistreElo _entreeCourse({
  int id = 1,
  String cle = 'ALPHA|PLAT',
  EtapeEntreeRegistre etape = EtapeEntreeRegistre.appliquee,
  IssueEcritureElo? issue = IssueEcritureElo.persistee,
  int? tsFinal = 2000,
  String empreinteAvant = _fpA,
  String empreinteApres = _fpB,
  List<ChevalJournalise> chevaux = const <ChevalJournalise>[],
}) =>
    EntreeRegistreElo(
      id: id,
      type: TypeEntreeRegistre.course,
      cle: cle,
      numR: 1,
      numC: 2,
      date: '2026-04-23',
      discipline: 'PLAT',
      etape: etape,
      issue: issue,
      tsIntention: 1000,
      tsFinal: tsFinal,
      empreinteAvant: empreinteAvant,
      empreinteApres: empreinteApres,
      chevaux: chevaux,
    );

EntreeRegistreElo _entreeHorsCourse({
  int id = 9,
  MotifHorsCourse motif = MotifHorsCourse.importBackup,
  EtapeEntreeRegistre etape = EtapeEntreeRegistre.appliquee,
  IssueEcritureElo? issue = IssueEcritureElo.persistee,
  int? tsFinal = 2000,
  List<ChevalJournalise> chevaux = const <ChevalJournalise>[],
}) =>
    EntreeRegistreElo(
      id: id,
      type: TypeEntreeRegistre.horsCourse,
      motif: motif,
      nbChevauxAvant: 40,
      nbChevauxApres: 52,
      etape: etape,
      issue: issue,
      tsIntention: 1000,
      tsFinal: tsFinal,
      empreinteAvant: _fpA,
      empreinteApres: _fpB,
      chevaux: chevaux,
    );

ChevalJournalise _cheval({
  ImageRatingElo? avant,
  String cle = 'ALPHA|PLAT',
}) =>
    ChevalJournalise(
      cle: cle,
      nom: 'Alpha',
      avant: avant,
      apres: const ImageRatingElo(
        rating: 1512.5,
        nbCourses: 4,
        variationMois: 12.5,
      ),
    );

// ═══════════════════════════════════════════════════════════════════════════
void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 1 — ENCODAGE DE CHAMP : INJECTIVITÉ
  //  Exigence contractuelle : « gérer les clés contenant des séparateurs ».
  // ═════════════════════════════════════════════════════════════════════════
  group('T-E · encoderChamp (injectivité, séparateurs)', () {
    test('T-E1 · préfixe de longueur — valeurs mesurées', () {
      expect(encoderChamp(''), '0:');
      expect(encoderChamp('A'), '1:A');
      expect(encoderChamp('AB'), '2:AB');
      expect(encoderChamp('A|B|TROT_ATTELE'), '15:A|B|TROT_ATTELE');
      // Mesuré : 'ÉTÉ'.length == 3 (unités UTF-16), et non 5 (octets UTF-8).
      expect(encoderChamp('ÉTÉ'), '3:ÉTÉ');
    });

    test('T-E2 · la concaténation naïve serait ambiguë, la nôtre ne l\'est pas',
        () {
      // Défaut de schéma PRÉEXISTANT du dépôt : `_cleNom` ne filtre pas `|`.
      //   nom "A|B" + discipline "TROT_ATTELE"  → "A|B|TROT_ATTELE"
      //   nom "A"   + discipline "B|TROT_ATTELE" → "A|B|TROT_ATTELE"
      // Ces deux constructions produisent LA MÊME clé composite : la clé seule
      // ne peut donc pas servir de séparateur fiable. On encode séparément
      // chaque champ AVEC sa longueur.
      expect(encoderChamp('AB') + encoderChamp('C'), '2:AB1:C');
      expect(encoderChamp('A') + encoderChamp('BC'), '1:A2:BC');
      expect(
        encoderChamp('AB') + encoderChamp('C'),
        isNot(encoderChamp('A') + encoderChamp('BC')),
      );
    });

    test('T-E3 · clés contenant | ; : et espaces restent distinctes', () {
      const cles = <String>[
        'A|B',
        'A;B',
        'A:B',
        'A B',
        'A||B',
        'A;|B',
        '|',
        ';',
        ':',
        '',
      ];
      final encodages = cles.map(encoderChamp).toSet();
      expect(encodages.length, cles.length);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 2 — BITS IEEE 754
  //  Exigences : distinguer 0.0 / -0.0, distinguer au bit, rester calculable
  //  sur les valeurs non finies.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-B · encoderReelBits (bits IEEE 754)', () {
    test('T-B1 · 16 hexadécimaux minuscules pour toute valeur', () {
      final valeurs = <double>[
        0.0,
        -0.0,
        1.0,
        -1.0,
        1500.0,
        1512.5,
        -1512.5,
        800.0,
        2500.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        double.minPositive,
        double.maxFinite,
      ];
      final re = RegExp(r'^[0-9a-f]{16}$');
      for (final v in valeurs) {
        expect(re.hasMatch(encoderReelBits(v)), isTrue,
            reason: 'encoderReelBits($v) = "${encoderReelBits(v)}"');
      }
    });

    test('T-B2 · 0.0 et -0.0 sont DISTINGUÉS malgré leur égalité Dart', () {
      // Mesuré : 0.0 == -0.0 vaut true en Dart.
      expect(0.0 == -0.0, isTrue);
      expect(encoderReelBits(0.0), '0000000000000000');
      expect(encoderReelBits(-0.0), '8000000000000000');
      expect(encoderReelBits(0.0), isNot(encoderReelBits(-0.0)));
    });

    test('T-B3 · deux doubles voisins diffèrent au bit', () {
      expect(encoderReelBits(1512.5), '4097a20000000000');
      expect(encoderReelBits(1512.5000000000002), '4097a20000000001');
      expect(
        encoderReelBits(1512.5),
        isNot(encoderReelBits(1512.5000000000002)),
      );
      expect(1512.5 == 1512.5000000000002, isFalse);
    });

    test('T-B4 · NaN et ±Infinity encodés SANS lever', () {
      expect(() => encoderReelBits(double.nan), returnsNormally);
      expect(encoderReelBits(double.nan), 'fff8000000000000');
      expect(encoderReelBits(double.infinity), '7ff0000000000000');
      expect(encoderReelBits(double.negativeInfinity), 'fff0000000000000');
    });

    test('T-B5 · les trois non-finies sont mutuellement distinctes', () {
      expect(
        <String>{
          encoderReelBits(double.nan),
          encoderReelBits(double.infinity),
          encoderReelBits(double.negativeInfinity),
        }.length,
        3,
      );
    });

    test('T-B5b · un double NÉGATIF ne produit jamais d\'hexadécimal négatif',
        () {
      // Mesuré : `getUint64(-1512.5)` rend -4569005176060379136 (hex négatif).
      // L'implémentation n'utilise jamais getUint64 : deux mots non signés.
      for (final v in <double>[-1.0, -1512.5, -2500.0, double.negativeInfinity]) {
        expect(encoderReelBits(v).contains('-'), isFalse, reason: '$v');
      }
    });

    test('T-B6 · déterminisme : deux appels → même chaîne', () {
      for (final v in <double>[0.0, -0.0, 1512.5, double.nan, double.infinity]) {
        expect(encoderReelBits(v), encoderReelBits(v));
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 3 — REPRÉSENTATION CANONIQUE
  // ═════════════════════════════════════════════════════════════════════════
  group('T-C · canoniqueRatings (représentation canonique)', () {
    test('T-C1 · map vide → "0;"', () {
      expect(canoniqueRatings(<String, EloScore>{}), '0;');
    });

    test('T-C2 · forme exacte d\'une entrée unique — mesurée', () {
      final map = <String, EloScore>{
        'ALPHA|PLAT': const EloScore(
          nomCheval: 'Alpha',
          rating: 1512.5,
          nbCourses: 3,
          variationMois: 12.5,
        ),
      };
      expect(
        canoniqueRatings(map),
        '1;10:ALPHA|PLAT16:4097a200000000001:316:4029000000000000',
      );
    });

    test('T-C3 · le compte de tête délimite le domaine', () {
      final un = <String, EloScore>{'A|PLAT': _sc(1500.0)};
      final deux = <String, EloScore>{
        'A|PLAT': _sc(1500.0),
        'B|PLAT': _sc(1500.0),
      };
      expect(canoniqueRatings(un).startsWith('1;'), isTrue);
      expect(canoniqueRatings(deux).startsWith('2;'), isTrue);
      expect(canoniqueRatings(un), isNot(canoniqueRatings(deux)));
    });

    test('T-C4 · ordre d\'insertion INDÉPENDANT', () {
      final ordre1 = <String, EloScore>{};
      ordre1['BETA|TROT_ATTELE'] = _sc(1500.0, nom: 'Beta');
      ordre1['ALPHA|PLAT'] = _sc(1512.5, nb: 3, varMois: 12.5, nom: 'Alpha');

      final ordre2 = <String, EloScore>{};
      ordre2['ALPHA|PLAT'] = _sc(1512.5, nb: 3, varMois: 12.5, nom: 'Alpha');
      ordre2['BETA|TROT_ATTELE'] = _sc(1500.0, nom: 'Beta');

      expect(canoniqueRatings(ordre1), canoniqueRatings(ordre2));
      expect(
        canoniqueRatings(ordre1),
        '2;10:ALPHA|PLAT16:4097a200000000001:316:4029000000000000'
        '16:BETA|TROT_ATTELE16:40977000000000001:016:0000000000000000',
      );
    });

    test('T-C5 · map non modifiable acceptée (aucune mutation tentée)', () {
      final map = Map<String, EloScore>.unmodifiable(<String, EloScore>{
        'A|PLAT': _sc(1500.0),
      });
      expect(() => canoniqueRatings(map), returnsNormally);
    });

    test('T-C6 · le champ `nomCheval` N\'ENTRE PAS dans l\'empreinte', () {
      // L'empreinte couvre l'ÉTAT comparé par le registre (rating / nb / var),
      // pas le libellé humain. Deux EloScore de même état et de `nomCheval`
      // différent produisent la même empreinte : décision assumée.
      final a = <String, EloScore>{'A|PLAT': _sc(1500.0, nom: 'Alpha')};
      final b = <String, EloScore>{'A|PLAT': _sc(1500.0, nom: 'Autre Nom')};
      expect(canoniqueRatings(a), canoniqueRatings(b));
      expect(empreinte64Ratings(a), empreinte64Ratings(b));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 4 — EMPREINTE
  // ═════════════════════════════════════════════════════════════════════════
  group('T-F · empreinte64Ratings', () {
    test('T-F1 · indépendante de l\'ordre d\'insertion', () {
      final ordre1 = <String, EloScore>{};
      ordre1['Z|PLAT'] = _sc(1500.0);
      ordre1['A|PLAT'] = _sc(1600.0);
      ordre1['M|PLAT'] = _sc(1700.0);

      final ordre2 = <String, EloScore>{};
      ordre2['M|PLAT'] = _sc(1700.0);
      ordre2['Z|PLAT'] = _sc(1500.0);
      ordre2['A|PLAT'] = _sc(1600.0);

      expect(empreinte64Ratings(ordre1), empreinte64Ratings(ordre2));
    });

    test('T-F2 · 0.0 et -0.0 produisent des empreintes DIFFÉRENTES', () {
      final pos = <String, EloScore>{'K|PLAT': _sc(0.0)};
      final neg = <String, EloScore>{'K|PLAT': _sc(-0.0)};
      expect(empreinte64Ratings(pos), '7e09ec266327abb4');
      expect(empreinte64Ratings(neg), '2932e44e43b4fc8c');
      expect(empreinte64Ratings(pos), isNot(empreinte64Ratings(neg)));
    });

    test('T-F3 · deux valeurs différentes au bit → empreintes différentes', () {
      final a = <String, EloScore>{'K|PLAT': _sc(1512.5)};
      final b = <String, EloScore>{'K|PLAT': _sc(1512.5000000000002)};
      expect(empreinte64Ratings(a), 'c01d69a9ae44c64f');
      expect(empreinte64Ratings(b), 'c1446046642099dc');
      expect(empreinte64Ratings(a), isNot(empreinte64Ratings(b)));
    });

    test('T-F4 · NaN et ±Infinity restent calculables (aucune exception)', () {
      final nan = <String, EloScore>{'K|PLAT': _sc(double.nan)};
      final inf = <String, EloScore>{'K|PLAT': _sc(double.infinity)};
      final ninf = <String, EloScore>{'K|PLAT': _sc(double.negativeInfinity)};

      expect(() => empreinte64Ratings(nan), returnsNormally);
      expect(() => empreinte64Ratings(inf), returnsNormally);
      expect(() => empreinte64Ratings(ninf), returnsNormally);

      expect(empreinte64Ratings(nan), '145aded891c0a876');
      expect(empreinte64Ratings(inf), '36d5d7292ed6bfc9');
      expect(empreinte64Ratings(ninf), '37f09810681c0d5e');

      expect(
        <String>{
          empreinte64Ratings(nan),
          empreinte64Ratings(inf),
          empreinte64Ratings(ninf),
        }.length,
        3,
      );
    });

    test('T-F5 · clés contenant des séparateurs → empreintes distinctes', () {
      final barre = <String, EloScore>{'A|B': _sc(1500.0)};
      final pointVirgule = <String, EloScore>{'A;B': _sc(1500.0)};
      final deuxPoints = <String, EloScore>{'A:B': _sc(1500.0)};

      expect(empreinte64Ratings(barre), 'b9efea63ab857367');
      expect(empreinte64Ratings(pointVirgule), '973a204a07fc37fe');

      expect(empreinte64Ratings(barre), isNot(empreinte64Ratings(pointVirgule)));
      expect(empreinte64Ratings(barre), isNot(empreinte64Ratings(deuxPoints)));
      expect(
        empreinte64Ratings(pointVirgule),
        isNot(empreinte64Ratings(deuxPoints)),
      );
    });

    test('T-F6 · map vide distincte d\'une map à une entrée', () {
      expect(canoniqueRatings(<String, EloScore>{}), '0;');
      expect(empreinte64Ratings(<String, EloScore>{}), '16ed60fcfaed47f4');
      final une = <String, EloScore>{'A|PLAT': _sc(1500.0)};
      expect(
        empreinte64Ratings(<String, EloScore>{}),
        isNot(empreinte64Ratings(une)),
      );
    });

    test('T-F7 · format de sortie : 16 hexadécimaux minuscules', () {
      final re = RegExp(r'^[0-9a-f]{16}$');
      expect(re.hasMatch(empreinte64Ratings(<String, EloScore>{})), isTrue);
      expect(
        re.hasMatch(
            empreinte64Ratings(<String, EloScore>{'A|PLAT': _sc(1500.0)})),
        isTrue,
      );
    });

    test('T-F8 · déterminisme : deux appels → même empreinte', () {
      final map = <String, EloScore>{
        'A|PLAT': _sc(1512.5, nb: 3, varMois: 12.5),
        'B|TROT_ATTELE': _sc(1400.0, nb: 7, varMois: -30.0),
        'C|OBSTACLE_HAIE': _sc(1800.0, nb: 1, varMois: 0.0),
      };
      expect(empreinte64Ratings(map), empreinte64Ratings(map));
      expect(empreinte64Ratings(map), empreinte64Ratings(Map.of(map)));
    });

    test('T-F9 · toute variation d\'un seul champ change l\'empreinte', () {
      final base = <String, EloScore>{
        'K|PLAT': _sc(1500.0, nb: 1, varMois: 1.0),
      };
      final fp = empreinte64Ratings(base);

      final rating = <String, EloScore>{
        'K|PLAT': _sc(1500.5, nb: 1, varMois: 1.0),
      };
      final nb = <String, EloScore>{'K|PLAT': _sc(1500.0, nb: 2, varMois: 1.0)};
      final varMois = <String, EloScore>{
        'K|PLAT': _sc(1500.0, nb: 1, varMois: 1.5),
      };
      final cle = <String, EloScore>{
        'K2|PLAT': _sc(1500.0, nb: 1, varMois: 1.0),
      };

      for (final variante in <Map<String, EloScore>>[rating, nb, varMois, cle]) {
        expect(empreinte64Ratings(variante), isNot(fp),
            reason: 'variante non détectée : ${canoniqueRatings(variante)}');
      }
    });

    test('T-F10 · variationMois -0.0 et 0.0 → empreintes différentes', () {
      final pos = <String, EloScore>{'K|PLAT': _sc(1500.0, varMois: 0.0)};
      final neg = <String, EloScore>{'K|PLAT': _sc(1500.0, varMois: -0.0)};
      expect(empreinte64Ratings(pos), isNot(empreinte64Ratings(neg)));
    });

    test('T-F11 · l\'empreinte NE MODIFIE PAS les ratings (pureté)', () {
      final map = <String, EloScore>{
        'A|PLAT': _sc(1512.5, nb: 3, varMois: 12.5, nom: 'Alpha'),
        'B|TROT_ATTELE': _sc(1400.0, nb: 7, varMois: -30.0, nom: 'Beta'),
      };
      // Instantané complet AVANT, pris champ par champ.
      final avant = <String, List<Object>>{};
      for (final k in map.keys) {
        final s = map[k]!;
        avant[k] = <Object>[s.nomCheval, s.rating, s.nbCourses, s.variationMois];
      }
      final canonAvant = canoniqueRatings(map);
      final tailleAvant = map.length;

      final fp1 = empreinte64Ratings(map);
      final fp2 = empreinte64Ratings(map);

      expect(fp1, fp2);
      expect(map.length, tailleAvant);
      for (final k in avant.keys) {
        final s = map[k]!;
        expect(s.nomCheval, avant[k]![0]);
        expect(s.rating, avant[k]![1]);
        expect(s.nbCourses, avant[k]![2]);
        expect(s.variationMois, avant[k]![3]);
      }
      expect(canoniqueRatings(map), canonAvant);
      // Contrôle direct : aucun clamp, aucun arrondi, aucune écriture.
      expect(map['A|PLAT']!.rating, 1512.5);
      expect(encoderReelBits(map['A|PLAT']!.rating), '4097a20000000000');
      expect(map['B|TROT_ATTELE']!.variationMois, -30.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 5 — OCTETS UTF-8 (rétention)
  // ═════════════════════════════════════════════════════════════════════════
  group('T-U · octetsUtf8', () {
    test('T-U1 · valeurs mesurées', () {
      expect(octetsUtf8(''), 0);
      expect(octetsUtf8('A'), 1);
      expect(octetsUtf8('É'), 2);
      expect(octetsUtf8('ÉTÉ'), 5);
      expect(octetsUtf8('€'), 3);
    });

    test('T-U2 · cohérent avec utf8.encode sur des libellés du domaine', () {
      for (final s in <String>['', 'A', 'ÉTÉ', 'HELLO WORLD', 'ÉLÉGANT']) {
        expect(octetsUtf8(s), utf8.encode(s).length, reason: '"$s"');
      }
    });

    test('T-U3 · longueur en unités ≠ longueur en octets pour l\'accentué', () {
      expect('ÉTÉ'.length, 3);
      expect(octetsUtf8('ÉTÉ'), 5);
      expect('ÉTÉ'.length, isNot(octetsUtf8('ÉTÉ')));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 6 — IMAGES AVANT / APRÈS
  // ═════════════════════════════════════════════════════════════════════════
  group('T-I · ImageRatingElo et ChevalJournalise', () {
    test('T-I1 · ImageRatingElo — aller-retour JSON exact', () {
      const image = ImageRatingElo(
        rating: 1512.5,
        nbCourses: 4,
        variationMois: 12.5,
      );
      expect(image.toJson(), <String, dynamic>{
        'rating': 1512.5,
        'nb': 4,
        'var': 12.5,
      });
      final relu = ImageRatingElo.fromJson(image.toJson());
      expect(relu.rating, 1512.5);
      expect(relu.nbCourses, 4);
      expect(relu.variationMois, 12.5);
    });

    test('T-I2 · ImageRatingElo — champ manquant LÈVE (aucun défaut inventé)',
        () {
      expect(
        () => ImageRatingElo.fromJson(<String, dynamic>{'nb': 1, 'var': 0.0}),
        throwsFormatException,
      );
      expect(
        () => ImageRatingElo.fromJson(<String, dynamic>{'rating': 1.0, 'var': 0.0}),
        throwsFormatException,
      );
      expect(
        () => ImageRatingElo.fromJson(<String, dynamic>{'rating': 1.0, 'nb': 1}),
        throwsFormatException,
      );
    });

    test('T-I3 · ImageRatingElo — type incorrect LÈVE', () {
      expect(
        () => ImageRatingElo.fromJson(<String, dynamic>{
          'rating': '1512.5',
          'nb': 1,
          'var': 0.0,
        }),
        throwsFormatException,
      );
      expect(
        () => ImageRatingElo.fromJson(<String, dynamic>{
          'rating': 1.0,
          'nb': '1',
          'var': 0.0,
        }),
        throwsFormatException,
      );
      expect(
        () => ImageRatingElo.fromJson(<String, dynamic>{
          'rating': 1.0,
          'nb': 1,
          'var': '0',
        }),
        throwsFormatException,
      );
    });

    test('T-I4 · ImageRatingElo — non-finies survivent à l\'aller-retour objet',
        () {
      for (final v in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -0.0,
      ]) {
        final image = ImageRatingElo(
          rating: v,
          nbCourses: 1,
          variationMois: 0.0,
        );
        final relu = ImageRatingElo.fromJson(image.toJson());
        // Bit à bit : -0.0 reste -0.0, NaN reste NaN.
        expect(encoderReelBits(relu.rating), encoderReelBits(v));
      }
    });

    test('T-I5 · ChevalJournalise — `avant == null` = clé ABSENTE, distinct de '
        '1500.0', () {
      final absent = _cheval(avant: null);
      final present = _cheval(
        avant: const ImageRatingElo(
          rating: 1500.0,
          nbCourses: 0,
          variationMois: 0.0,
        ),
      );
      expect(absent.avant, isNull);
      expect(present.avant, isNotNull);
      expect(absent.toJson()['avant'], isNull);
      expect(present.toJson()['avant'], isNotNull);
      // Les deux JSON sont DIFFÉRENTS : la création et un rating déjà à 1500
      // sont donc discernables, contrairement à ce que permet `?? _eloDefaut`.
      expect(absent.toJson(), isNot(present.toJson()));
    });

    test('T-I6 · ChevalJournalise — aller-retour conserve `avant` nul ou non',
        () {
      final absent = _cheval(avant: null);
      final reluAbsent = ChevalJournalise.fromJson(absent.toJson());
      expect(reluAbsent.avant, isNull);
      expect(reluAbsent.apres.rating, 1512.5);

      final present = _cheval(
        avant: const ImageRatingElo(
          rating: 1500.0,
          nbCourses: 0,
          variationMois: 0.0,
        ),
      );
      final reluPresent = ChevalJournalise.fromJson(present.toJson());
      expect(reluPresent.avant, isNotNull);
      expect(reluPresent.avant!.rating, 1500.0);
    });

    test('T-I7 · ChevalJournalise — `avant` mal typé LÈVE', () {
      final json = _cheval(avant: null).toJson();
      json['avant'] = 'pas un objet';
      expect(() => ChevalJournalise.fromJson(json), throwsFormatException);
    });

    test('T-I8 · ChevalJournalise — `apres` manquant LÈVE', () {
      final json = _cheval(avant: null).toJson();
      json.remove('apres');
      expect(() => ChevalJournalise.fromJson(json), throwsFormatException);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 7 — INVARIANTS DE L'ENTRÉE
  // ═════════════════════════════════════════════════════════════════════════
  group('T-N · EntreeRegistreElo — invariants', () {
    test('T-N1 · `intention` : issue et tsFinal doivent être NULS', () {
      final valide = _entreeCourse(
        etape: EtapeEntreeRegistre.intention,
        issue: null,
        tsFinal: null,
      );
      expect(() => EntreeRegistreElo.fromJson(valide.toJson()),
          returnsNormally);

      final avecIssue = _entreeCourse(
        etape: EtapeEntreeRegistre.intention,
        issue: IssueEcritureElo.persistee,
        tsFinal: null,
      );
      expect(() => EntreeRegistreElo.fromJson(avecIssue.toJson()),
          throwsFormatException);

      final avecTs = _entreeCourse(
        etape: EtapeEntreeRegistre.intention,
        issue: null,
        tsFinal: 2000,
      );
      expect(() => EntreeRegistreElo.fromJson(avecTs.toJson()),
          throwsFormatException);
    });

    test('T-N2 · `appliquee` : issue=persistee ET tsFinal non nul OBLIGATOIRES',
        () {
      final valide = _entreeCourse();
      expect(() => EntreeRegistreElo.fromJson(valide.toJson()),
          returnsNormally);

      final sansTs = _entreeCourse(tsFinal: null);
      expect(() => EntreeRegistreElo.fromJson(sansTs.toJson()),
          throwsFormatException);

      final mauvaiseIssue = _entreeCourse(issue: IssueEcritureElo.refusee);
      expect(() => EntreeRegistreElo.fromJson(mauvaiseIssue.toJson()),
          throwsFormatException);

      final issueNulle = _entreeCourse(issue: null);
      expect(() => EntreeRegistreElo.fromJson(issueNulle.toJson()),
          throwsFormatException);
    });

    test('T-N3 · `nonConfirmee` : issue ∈ {refusee, echouee}, tsFinal NUL', () {
      for (final issue in <IssueEcritureElo>[
        IssueEcritureElo.refusee,
        IssueEcritureElo.echouee,
      ]) {
        final valide = _entreeCourse(
          etape: EtapeEntreeRegistre.nonConfirmee,
          issue: issue,
          tsFinal: null,
        );
        expect(() => EntreeRegistreElo.fromJson(valide.toJson()),
            returnsNormally);
      }

      // persistee interdit en nonConfirmee.
      final persistee = _entreeCourse(
        etape: EtapeEntreeRegistre.nonConfirmee,
        issue: IssueEcritureElo.persistee,
        tsFinal: null,
      );
      expect(() => EntreeRegistreElo.fromJson(persistee.toJson()),
          throwsFormatException);

      // issue nulle interdite en nonConfirmee.
      final nulle = _entreeCourse(
        etape: EtapeEntreeRegistre.nonConfirmee,
        issue: null,
        tsFinal: null,
      );
      expect(() => EntreeRegistreElo.fromJson(nulle.toJson()),
          throwsFormatException);

      // tsFinal non nul interdit en nonConfirmee.
      final avecTs = _entreeCourse(
        etape: EtapeEntreeRegistre.nonConfirmee,
        issue: IssueEcritureElo.refusee,
        tsFinal: 2000,
      );
      expect(() => EntreeRegistreElo.fromJson(avecTs.toJson()),
          throwsFormatException);
    });

    test('T-N4 · `estIncertaine` : vrai pour intention et nonConfirmee', () {
      expect(
        _entreeCourse(
          etape: EtapeEntreeRegistre.intention,
          issue: null,
          tsFinal: null,
        ).estIncertaine,
        isTrue,
      );
      expect(
        _entreeCourse(
          etape: EtapeEntreeRegistre.nonConfirmee,
          issue: IssueEcritureElo.refusee,
          tsFinal: null,
        ).estIncertaine,
        isTrue,
      );
      expect(_entreeCourse().estIncertaine, isFalse);
    });

    test('T-N5 · `bloqueNouvelleSoumission` est vrai pour les trois états', () {
      // Aucune dérogation : intention (issue inconnue), nonConfirmee (ni preuve
      // d'écriture ni preuve d'absence) et appliquee (déjà appliquée).
      for (final etape in EtapeEntreeRegistre.values) {
        final e = etape == EtapeEntreeRegistre.appliquee
            ? _entreeCourse()
            : etape == EtapeEntreeRegistre.intention
                ? _entreeCourse(
                    etape: etape, issue: null, tsFinal: null)
                : _entreeCourse(
                    etape: etape,
                    issue: IssueEcritureElo.refusee,
                    tsFinal: null);
        expect(e.bloqueNouvelleSoumission, isTrue, reason: etape.name);
      }
    });

    test('T-N6 · `horsCourse` : `chevaux` non vide INTERDIT', () {
      final vide = _entreeHorsCourse();
      expect(() => EntreeRegistreElo.fromJson(vide.toJson()), returnsNormally);

      final avecChevaux = _entreeHorsCourse(
        chevaux: <ChevalJournalise>[_cheval(avant: null)],
      );
      // toJson n'écrit pas `chevaux` pour horsCourse : on l'injecte à la main
      // pour prouver que le LECTEUR refuse, même sur un JSON forgé.
      final json = avecChevaux.toJson();
      json['chevaux'] = <dynamic>[_cheval(avant: null).toJson()];
      expect(() => EntreeRegistreElo.fromJson(json), throwsFormatException);
    });

    test('T-N7 · `horsCourse` : `motif` obligatoire', () {
      final json = _entreeHorsCourse().toJson()..remove('motif');
      expect(() => EntreeRegistreElo.fromJson(json), throwsFormatException);
    });

    test('T-N8 · `motif` doit appartenir à l\'énumération', () {
      final json = _entreeHorsCourse().toJson();
      json['motif'] = 'motifInexistant';
      expect(() => EntreeRegistreElo.fromJson(json), throwsFormatException);
    });

    test('T-N9 · `type` et `etape` doivent appartenir à leur énumération', () {
      final typeKo = _entreeCourse().toJson()..['type'] = 'inconnu';
      expect(() => EntreeRegistreElo.fromJson(typeKo), throwsFormatException);

      final etapeKo = _entreeCourse().toJson()..['etape'] = 'inconnu';
      expect(() => EntreeRegistreElo.fromJson(etapeKo), throwsFormatException);

      // Le rejet d'`abandonneeParReset` prouve qu'il n'est pas persistable.
      final abandon = _entreeCourse().toJson()
        ..['etape'] = 'abandonneeParReset';
      expect(() => EntreeRegistreElo.fromJson(abandon), throwsFormatException);
    });

    test('T-N10 · empreinte hors format REFUSÉE', () {
      for (final invalide in <String>[
        '',
        '0123456789abcde', // 15
        '0123456789abcdef0', // 17
        '0123456789ABCDEF', // majuscules
        '0123456789abcdeg', // hors [0-9a-f]
        'zzzzzzzzzzzzzzzz',
      ]) {
        expect(
          () => EntreeRegistreElo.fromJson(
              _entreeCourse().toJson()..['empreinteAvant'] = invalide),
          throwsFormatException,
          reason: '"$invalide"',
        );
        expect(
          () => EntreeRegistreElo.fromJson(
              _entreeCourse().toJson()..['empreinteApres'] = invalide),
          throwsFormatException,
          reason: '"$invalide" (apres)',
        );
      }
    });

    test('T-N11 · aller-retour complet conserve TOUS les champs', () {
      final original = _entreeCourse(
        id: 42,
        cle: 'ALPHA|PLAT',
        chevaux: <ChevalJournalise>[
          _cheval(
            avant: const ImageRatingElo(
              rating: 1500.0,
              nbCourses: 3,
              variationMois: 0.0,
            ),
          ),
        ],
      );
      final relu = EntreeRegistreElo.fromJson(original.toJson());
      expect(relu.id, 42);
      expect(relu.type, TypeEntreeRegistre.course);
      expect(relu.cle, 'ALPHA|PLAT');
      expect(relu.numR, 1);
      expect(relu.numC, 2);
      expect(relu.date, '2026-04-23');
      expect(relu.discipline, 'PLAT');
      expect(relu.etape, EtapeEntreeRegistre.appliquee);
      expect(relu.issue, IssueEcritureElo.persistee);
      expect(relu.tsIntention, 1000);
      expect(relu.tsFinal, 2000);
      expect(relu.empreinteAvant, _fpA);
      expect(relu.empreinteApres, _fpB);
      expect(relu.chevaux.length, 1);
      expect(relu.chevaux.single.avant!.nbCourses, 3);
      expect(relu.chevaux.single.apres.rating, 1512.5);
    });

    test('T-N12 · tsFinal accepté en double ENTIER, refusé en fractionnaire', () {
      final entier = _entreeCourse().toJson()..['tsFinal'] = 2000.0;
      expect(() => EntreeRegistreElo.fromJson(entier), returnsNormally);

      final fraction = _entreeCourse().toJson()..['tsFinal'] = 2000.5;
      expect(() => EntreeRegistreElo.fromJson(fraction), throwsFormatException);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 8 — REGISTRE : SCHÉMA, VERSION, SÉRIALISATION
  // ═════════════════════════════════════════════════════════════════════════
  group('T-R · RegistreEloV3 — schéma et sérialisation', () {
    test('T-R1 · constantes du schéma', () {
      expect(kSchemaRegistreElo, 3);
      expect(kVersionRegistreElo, 1);
      expect(kCleRegistreElo, 'elo_registre_v3');
    });

    test('T-R1b · seuils de rétention — valeurs mesurées', () {
      expect(kSeuilVeilleOctets, 1572864);
      expect(kSeuilAlerteOctets, 3145728);
      expect(kSeuilSaturationOctets, 6291456);
      expect(kEntreeRegistreSeuilAlerte, 100000);
    });

    test('T-R2 · `vierge()` — état initial', () {
      final r = RegistreEloV3.vierge(empreinteRatings: _fpA);
      expect(r.schema, 3);
      expect(r.version, 1);
      expect(r.horloge, 0);
      expect(r.empreinteRatings, _fpA);
      expect(r.origine, OrigineRegistreElo.courante);
      expect(r.entrees, isEmpty);
      expect(r.interpretable, isTrue);
    });

    test('T-R3 · aller-retour `encoder()` / `decoder()` — contenu identique', () {
      final original = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 7,
        empreinteRatings: _fpB,
        origine: OrigineRegistreElo.courante,
        entrees: <EntreeRegistreElo>[
          _entreeCourse(id: 1),
          _entreeHorsCourse(id: 2),
          _entreeCourse(
            id: 3,
            etape: EtapeEntreeRegistre.nonConfirmee,
            issue: IssueEcritureElo.echouee,
            tsFinal: null,
          ),
        ],
      );
      final relu = RegistreEloV3.decoder(original.encoder());
      expect(relu.schema, 3);
      expect(relu.version, 1);
      expect(relu.horloge, 7);
      expect(relu.empreinteRatings, _fpB);
      expect(relu.origine, OrigineRegistreElo.courante);
      expect(relu.entrees.length, 3);
      expect(relu.entrees[0].id, 1);
      expect(relu.entrees[1].type, TypeEntreeRegistre.horsCourse);
      expect(relu.entrees[2].etape, EtapeEntreeRegistre.nonConfirmee);
      // Ré-encodage idempotent : aucune perte, aucun réordonnancement de champs
      // observable sur la forme sérialisée.
      expect(relu.encoder(), original.encoder());
    });

    test('T-R4 · `decoder` refuse un JSON invalide ou non-objet', () {
      expect(() => RegistreEloV3.decoder(''), throwsFormatException);
      expect(() => RegistreEloV3.decoder('{'), throwsFormatException);
      expect(() => RegistreEloV3.decoder('[]'), throwsFormatException);
      expect(() => RegistreEloV3.decoder('"chaine"'), throwsFormatException);
      expect(() => RegistreEloV3.decoder('42'), throwsFormatException);
      expect(() => RegistreEloV3.decoder('null'), throwsFormatException);
    });

    test('T-R5 · `decoder` refuse un champ obligatoire manquant', () {
      final base = RegistreEloV3.vierge(empreinteRatings: _fpA).toJson();
      for (final champ in <String>[
        'schema',
        'version',
        'horloge',
        'empreinteRatings',
        'origine',
        'entrees',
      ]) {
        final copie = Map<String, dynamic>.from(base)..remove(champ);
        expect(() => RegistreEloV3.fromJson(copie), throwsFormatException,
            reason: 'champ $champ');
      }
    });

    test('T-R6 · `decoder` refuse `entrees` non-liste et empreinte invalide', () {
      final base = RegistreEloV3.vierge(empreinteRatings: _fpA).toJson();

      expect(
        () => RegistreEloV3.fromJson(
            Map<String, dynamic>.from(base)..['entrees'] = 'non'),
        throwsFormatException,
      );
      expect(
        () => RegistreEloV3.fromJson(
            Map<String, dynamic>.from(base)..['empreinteRatings'] = 'XYZ'),
        throwsFormatException,
      );
      expect(
        () => RegistreEloV3.fromJson(
            Map<String, dynamic>.from(base)..['entrees'] = <dynamic>['a']),
        throwsFormatException,
      );
    });

    test('T-R7 · schéma différent : décodé, NON interprétable, NON supprimé', () {
      final futur = RegistreEloV3(
        schema: 99,
        version: 1,
        horloge: 0,
        empreinteRatings: _fpA,
        origine: OrigineRegistreElo.courante,
        entrees: const <EntreeRegistreElo>[],
      );
      final relu = RegistreEloV3.decoder(futur.encoder());
      expect(relu.interpretable, isFalse);
      expect(relu.schema, 99);
      // Le contenu est intégralement conservé : rien n'est effacé.
      expect(relu.empreinteRatings, _fpA);
    });

    test('T-R8 · `entreesIncertaines` isole intention et nonConfirmee', () {
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 3,
        empreinteRatings: _fpA,
        origine: OrigineRegistreElo.courante,
        entrees: <EntreeRegistreElo>[
          _entreeCourse(id: 1),
          _entreeCourse(
            id: 2,
            etape: EtapeEntreeRegistre.intention,
            issue: null,
            tsFinal: null,
          ),
          _entreeCourse(
            id: 3,
            etape: EtapeEntreeRegistre.nonConfirmee,
            issue: IssueEcritureElo.refusee,
            tsFinal: null,
          ),
        ],
      );
      final incertaines = r.entreesIncertaines;
      expect(incertaines.length, 2);
      expect(incertaines.map((e) => e.id), <int>[2, 3]);
    });

    test('T-R9 · `entreePourCle` rend la PLUS RÉCENTE (id max)', () {
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 3,
        empreinteRatings: _fpA,
        origine: OrigineRegistreElo.courante,
        entrees: <EntreeRegistreElo>[
          _entreeCourse(id: 10, cle: 'A|PLAT'),
          _entreeCourse(id: 30, cle: 'A|PLAT'),
          _entreeCourse(id: 20, cle: 'A|PLAT'),
          _entreeCourse(id: 40, cle: 'B|PLAT'),
        ],
      );
      expect(r.entreePourCle('A|PLAT')!.id, 30);
      expect(r.entreePourCle('B|PLAT')!.id, 40);
      expect(r.entreePourCle('INCONNUE|PLAT'), isNull);
    });

    test('T-R9b · `entreePourCle` ignore les entrées horsCourse', () {
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 1,
        empreinteRatings: _fpA,
        origine: OrigineRegistreElo.courante,
        entrees: <EntreeRegistreElo>[_entreeHorsCourse(id: 99)],
      );
      expect(r.entreePourCle('ALPHA|PLAT'), isNull);
    });

    test('T-R10 · `copyWith` ne touche que les champs nommés', () {
      final base = RegistreEloV3.vierge(empreinteRatings: _fpA);
      final modifie = base.copyWith(
        horloge: 12,
        origine: OrigineRegistreElo.historiqueInconnu,
      );
      expect(modifie.horloge, 12);
      expect(modifie.origine, OrigineRegistreElo.historiqueInconnu);
      expect(modifie.empreinteRatings, _fpA);
      expect(modifie.schema, base.schema);
      expect(modifie.version, base.version);
      expect(modifie.entrees, isEmpty);
      // La source n'est pas modifiée : copyWith est pure.
      expect(base.horloge, 0);
      expect(base.origine, OrigineRegistreElo.courante);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 9 — PREUVE STRUCTURELLE : `abandonneeParReset` NON PERSISTABLE
  // ═════════════════════════════════════════════════════════════════════════
  group('T-S · abandonneeParReset absent de tout chemin de sérialisation', () {
    test('T-S1 · EtapeEntreeRegistre ne compte QUE trois membres', () {
      expect(EtapeEntreeRegistre.values.length, 3);
      expect(
        EtapeEntreeRegistre.values.map((e) => e.name).toList(),
        <String>['intention', 'appliquee', 'nonConfirmee'],
      );
      expect(
        EtapeEntreeRegistre.values
            .map((e) => e.name)
            .contains('abandonneeParReset'),
        isFalse,
      );
      expect(
        EtapeEntreeRegistre.values
            .map((e) => e.name)
            .contains('annuleeParReset'),
        isFalse,
      );
    });

    test('T-S2 · aucun JSON produit ne contient la chaîne', () {
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 1,
        empreinteRatings: _fpA,
        origine: OrigineRegistreElo.courante,
        entrees: <EntreeRegistreElo>[
          _entreeCourse(id: 1),
          _entreeCourse(
            id: 2,
            etape: EtapeEntreeRegistre.intention,
            issue: null,
            tsFinal: null,
          ),
          _entreeCourse(
            id: 3,
            etape: EtapeEntreeRegistre.nonConfirmee,
            issue: IssueEcritureElo.refusee,
            tsFinal: null,
          ),
          _entreeHorsCourse(id: 4),
        ],
      );
      final json = r.encoder();
      expect(json.contains('abandonneeParReset'), isFalse);
      expect(json.contains('annuleeParReset'), isFalse);
      // Contrôle positif : les trois états persistables SONT présents.
      expect(json.contains('"etape":"intention"'), isTrue);
      expect(json.contains('"etape":"appliquee"'), isTrue);
      expect(json.contains('"etape":"nonConfirmee"'), isTrue);
    });

    test('T-S3 · dans le source, `annuleeParReset` n\'apparaît qu\'en commentaire',
        () {
      // Relevé mesuré : 2 occurrences, lignes 33 et 45, toutes deux `//`.
      final lignes = File(_fichierModele)
          .readAsLinesSync()
          .where((l) => l.contains('annuleeParReset'))
          .toList();
      expect(lignes.length, 2);
      for (final l in lignes) {
        expect(l.trimLeft().startsWith('//'), isTrue, reason: l);
      }
    });

    test('T-S3b · dans le source, `abandonneeParReset` n\'apparaît qu\'en commentaire',
        () {
      final lignes = File(_fichierModele)
          .readAsLinesSync()
          .where((l) => l.contains('abandonneeParReset'))
          .toList();
      expect(lignes, isNotEmpty);
      for (final l in lignes) {
        expect(l.trimLeft().startsWith('//'), isTrue, reason: l);
      }
    });

    test('T-S4 · le modèle n\'importe AUCUN service et AUCUNE prefs', () {
      // Dépendances exactes, mesurées : un seul import.
      final imports = File(_fichierModele)
          .readAsLinesSync()
          .where((l) => l.trimLeft().startsWith('import '))
          .map((l) => l.trim())
          .toList();
      expect(imports, <String>["import 'dart:convert';"]);

      // Contrôle sur le CODE SEUL : le fichier PARLE de SharedPreferences et
      // de `elo_service` dans sa documentation (c'est voulu, les références
      // sont utiles), mais n'en exécute rien. Mesuré : les seules occurrences
      // sont des lignes de commentaire.
      final code = _lignesDeCode(_fichierModele).join('\n');
      expect(code.contains('shared_preferences'), isFalse);
      expect(code.contains('SharedPreferences'), isFalse);
      expect(code.contains('services/'), isFalse);
      expect(code.contains('elo_service'), isFalse);
      expect(code.contains('elo_ratings_v2_ts'), isFalse);
    });

    test('T-S5 · l\'empreinte n\'importe AUCUN service et AUCUNE prefs', () {
      final imports = File(_fichierEmpreinte)
          .readAsLinesSync()
          .where((l) => l.trimLeft().startsWith('import '))
          .map((l) => l.trim())
          .toList();
      expect(imports, <String>[
        "import 'dart:typed_data';",
        "import '../models/zt_models.dart';",
      ]);

      final code = _lignesDeCode(_fichierEmpreinte).join('\n');
      expect(code.contains('shared_preferences'), isFalse);
      expect(code.contains('SharedPreferences'), isFalse);
      expect(code.contains('services/'), isFalse);
    });

    test('T-S6 · aucune fonction publique ne RECONSTRUIT des ratings', () {
      // Le registre est un TÉMOIN, jamais une source. Contrôle sur le code
      // seul : aucune signature ne rend une `Map<String, EloScore>` ni un
      // `EloScore`, et aucun export de map n'existe.
      final code = _lignesDeCode(_fichierModele).join('\n');
      expect(code.contains('Map<String, EloScore>'), isFalse);
      expect(code.contains('EloScore'), isFalse);
      expect(RegExp(r'EloScore\s+\w+\s*\(').hasMatch(code), isFalse);
      expect(code.contains('toRatings'), isFalse);
      expect(code.contains('versRatings'), isFalse);
      expect(code.contains('ratingsDepuis'), isFalse);
      // Contrôle positif : les seules lectures de collection rendues sont
      // `List<EntreeRegistreElo>` et `EntreeRegistreElo?`.
      expect(code.contains('List<EntreeRegistreElo>'), isTrue);
      expect(code.contains('EntreeRegistreElo? entreePourCle'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 10 — DIAGNOSTIC
  // ═════════════════════════════════════════════════════════════════════════
  group('T-D · diagnostiquerRegistre', () {
    test('T-D1 · registre absent + 0 rating → registreAbsent / courante', () {
      final d = diagnostiquerRegistre(
        jsonRegistre: null,
        empreinteDisque: '0000000000000000',
        nombreRatings: 0,
      );
      expect(d.coherence, DiagnosticCoherenceElo.registreAbsent);
      expect(d.origine, OrigineRegistreElo.courante);
      expect(d.empreinteRegistre, isNull);
      expect(d.empreinteDisque, '0000000000000000');
      expect(d.registre, isNull);
      expect(d.autoriseApplication, isTrue);
      expect(d.protegeContreDoubleApplication, isFalse);
      expect(d.message, 'Premier usage : aucun registre ELO antérieur.');
    });

    test('T-D2 · registre absent + ratings non vides → historiqueInconnu', () {
      final d = diagnostiquerRegistre(
        jsonRegistre: null,
        empreinteDisque: _fpA,
        nombreRatings: 37,
      );
      expect(d.coherence, DiagnosticCoherenceElo.registreAbsent);
      expect(d.origine, OrigineRegistreElo.historiqueInconnu);
      expect(d.autoriseApplication, isTrue);
      // Aucune protection rétroactive : c'est le cœur de l'arbitrage.
      expect(d.protegeContreDoubleApplication, isFalse);
      expect(d.message, _messageImpose);
    });

    test('T-D3 · registre vide/blanc → corrompu, origine historiqueInconnu', () {
      for (final brut in <String>['', '   ', '\n', '\t ']) {
        final d = diagnostiquerRegistre(
          jsonRegistre: brut,
          empreinteDisque: _fpA,
          nombreRatings: 5,
        );
        expect(d.coherence, DiagnosticCoherenceElo.corrompu, reason: '"$brut"');
        expect(d.origine, OrigineRegistreElo.historiqueInconnu);
        expect(d.empreinteRegistre, isNull);
        expect(d.autoriseApplication, isFalse);
        expect(d.protegeContreDoubleApplication, isFalse);
        expect(d.message, contains('Registre ELO illisible'));
        expect(d.message, contains('n\'est pas supprimé'));
      }
    });

    test('T-D4 · JSON invalide → corrompu, jamais d\'exception', () {
      for (final brut in <String>['{', '[]', '42', '"x"', 'null', '{"a":1}']) {
        final d = diagnostiquerRegistre(
          jsonRegistre: brut,
          empreinteDisque: _fpA,
          nombreRatings: 5,
        );
        expect(d.coherence, DiagnosticCoherenceElo.corrompu, reason: '"$brut"');
        expect(d.autoriseApplication, isFalse);
      }
    });

    test('T-D5 · schéma incompatible : décodé mais NON interprété', () {
      final futur = RegistreEloV3(
        schema: kSchemaRegistreElo + 1,
        version: 1,
        horloge: 4,
        empreinteRatings: _fpA,
        origine: OrigineRegistreElo.courante,
        entrees: const <EntreeRegistreElo>[],
      );
      final d = diagnostiquerRegistre(
        jsonRegistre: futur.encoder(),
        empreinteDisque: _fpA,
        nombreRatings: 3,
      );
      expect(d.coherence, DiagnosticCoherenceElo.schemaIncompatible);
      expect(d.autoriseApplication, isFalse);
      expect(d.protegeContreDoubleApplication, isFalse);
      expect(d.empreinteRegistre, _fpA);
      // Le registre reste LISIBLE pour le diagnostic : rien n'est effacé.
      expect(d.registre, isNotNull);
      expect(d.registre!.schema, kSchemaRegistreElo + 1);
      expect(d.message, contains('schéma ou d\'une version incompatible'));
      expect(d.message, contains('n\'est pas supprimé'));
    });

    test('T-D6 · empreintes égales → cohérent, protection RÉELLE', () {
      final r = RegistreEloV3.vierge(empreinteRatings: _fpB);
      final d = diagnostiquerRegistre(
        jsonRegistre: r.encoder(),
        empreinteDisque: _fpB,
        nombreRatings: 12,
      );
      expect(d.coherence, DiagnosticCoherenceElo.coherent);
      expect(d.origine, OrigineRegistreElo.courante);
      expect(d.empreinteRegistre, _fpB);
      expect(d.empreinteDisque, _fpB);
      expect(d.autoriseApplication, isTrue);
      expect(d.protegeContreDoubleApplication, isTrue);
      expect(d.message, 'Registre ELO cohérent.');
    });

    test('T-D7 · empreintes différentes → divergent, cause NON identifiée', () {
      final r = RegistreEloV3.vierge(empreinteRatings: _fpB);
      final d = diagnostiquerRegistre(
        jsonRegistre: r.encoder(),
        empreinteDisque: _fpA,
        nombreRatings: 12,
      );
      expect(d.coherence, DiagnosticCoherenceElo.divergent);
      expect(d.empreinteRegistre, _fpB);
      expect(d.empreinteDisque, _fpA);
      expect(d.autoriseApplication, isFalse);
      expect(d.protegeContreDoubleApplication, isFalse);
      expect(d.message, contains('cause n\'est pas identifiée'));
      expect(d.message, contains('aucune reconstruction'));
    });

    test('T-D8 · cohérent MAIS historiqueInconnu → autorisé SANS protection',
        () {
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 0,
        empreinteRatings: _fpB,
        origine: OrigineRegistreElo.historiqueInconnu,
        entrees: const <EntreeRegistreElo>[],
      );
      final d = diagnostiquerRegistre(
        jsonRegistre: r.encoder(),
        empreinteDisque: _fpB,
        nombreRatings: 8,
      );
      expect(d.coherence, DiagnosticCoherenceElo.coherent);
      expect(d.origine, OrigineRegistreElo.historiqueInconnu);
      expect(d.autoriseApplication, isTrue);
      expect(d.protegeContreDoubleApplication, isFalse);
      expect(d.message, _messageImpose);
    });

    test('T-D9 · le message imposé ne contient aucun mot rassurant', () {
      expect(
        _messageImpose,
        'Historique d\'application ELO inconnu. Les courses antérieures ne '
        'sont pas mémorisées. Une nouvelle application sur l\'une d\'elles ne '
        'peut pas être détectée par le registre.',
      );
      for (final mot in <String>['protégé', 'sécurisé', 'vérifié', 'garanti']) {
        expect(_messageImpose.contains(mot), isFalse, reason: mot);
      }
      expect(_messageImpose.contains('ne peut pas être détectée'), isTrue);
    });

    test('T-D10 · matrice complète autorisation / protection', () {
      final cas = <List<Object>>[
        // [coherence, origine, autorise, protege]
        [
          DiagnosticCoherenceElo.coherent,
          OrigineRegistreElo.courante,
          true,
          true
        ],
        [
          DiagnosticCoherenceElo.coherent,
          OrigineRegistreElo.historiqueInconnu,
          true,
          false
        ],
        [
          DiagnosticCoherenceElo.registreAbsent,
          OrigineRegistreElo.courante,
          true,
          false
        ],
        [
          DiagnosticCoherenceElo.registreAbsent,
          OrigineRegistreElo.historiqueInconnu,
          true,
          false
        ],
        [
          DiagnosticCoherenceElo.divergent,
          OrigineRegistreElo.courante,
          false,
          false
        ],
        [
          DiagnosticCoherenceElo.corrompu,
          OrigineRegistreElo.historiqueInconnu,
          false,
          false
        ],
        [
          DiagnosticCoherenceElo.schemaIncompatible,
          OrigineRegistreElo.courante,
          false,
          false
        ],
      ];
      for (final c in cas) {
        final d = ResultatDiagnosticElo(
          coherence: c[0] as DiagnosticCoherenceElo,
          origine: c[1] as OrigineRegistreElo,
          empreinteRegistre: null,
          empreinteDisque: _fpA,
        );
        expect(d.autoriseApplication, c[2] as bool,
            reason: '${c[0]} / ${c[1]}');
        expect(d.protegeContreDoubleApplication, c[3] as bool,
            reason: '${c[0]} / ${c[1]}');
      }
    });

    test('T-D11 · tout diagnostic porte un message non vide', () {
      final coherences = DiagnosticCoherenceElo.values;
      for (final c in coherences) {
        for (final o in OrigineRegistreElo.values) {
          final d = ResultatDiagnosticElo(
            coherence: c,
            origine: o,
            empreinteRegistre: null,
            empreinteDisque: _fpA,
          );
          expect(d.message.trim(), isNotEmpty, reason: '${c.name}/${o.name}');
        }
      }
      expect(coherences.length, 5);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 10 bis — 3.3-A.1 : VERSIONNEMENT DU REGISTRE
  //
  //  Défaut corrigé : `interpretable` ne contrôlait que `schema`. Un registre
  //  portant `version: 2` était donc déclaré LISIBLE et pouvait ressortir
  //  `coherent` sur une empreinte identique — c'est-à-dire être interprété
  //  alors que la sémantique de son contenu n'était pas connue.
  //
  //  ⚠️ Ces tests ne touchent NI formule ELO, NI coefficient K, NI probabilité,
  //     NI poids, NI seuil, NI mécanisme d'apprentissage, NI règle TOP3.
  //     Ils ne lisent ni n'écrivent aucune SharedPreferences.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-V · versionnement — version 1 acceptée', () {
    test('T-V1 · version == kVersionRegistreElo → interprétable', () {
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 0,
        empreinteRatings: _fpA,
        origine: OrigineRegistreElo.courante,
        entrees: const <EntreeRegistreElo>[],
      );
      expect(kVersionRegistreElo, 1);
      expect(r.interpretable, isTrue);
    });

    test('T-V2 · version 1 + empreinte identique → cohérent, protégé', () {
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 9,
        empreinteRatings: _fpB,
        origine: OrigineRegistreElo.courante,
        entrees: const <EntreeRegistreElo>[],
      );
      final d = diagnostiquerRegistre(
        jsonRegistre: r.encoder(),
        empreinteDisque: _fpB,
        nombreRatings: 6,
      );
      expect(d.coherence, DiagnosticCoherenceElo.coherent);
      expect(d.autoriseApplication, isTrue);
      expect(d.protegeContreDoubleApplication, isTrue);
      expect(d.message, 'Registre ELO cohérent.');
    });

    test('T-V3 · \'vierge()\' produit la version courante', () {
      final v = RegistreEloV3.vierge(empreinteRatings: _fpA);
      expect(v.version, kVersionRegistreElo);
      expect(v.schema, kSchemaRegistreElo);
      expect(v.interpretable, isTrue);
    });
  });

  group('T-V · versionnement — versions inconnues REFUSÉES', () {
    /// Registre bien formé, seule la version varie.
    RegistreEloV3 avecVersion(int version) => RegistreEloV3(
          schema: kSchemaRegistreElo,
          version: version,
          horloge: 3,
          empreinteRatings: _fpA,
          origine: OrigineRegistreElo.courante,
          entrees: const <EntreeRegistreElo>[],
        );

    test('T-V4 · version 2 → NON interprétable', () {
      expect(avecVersion(2).interpretable, isFalse);
    });

    test('T-V5 · version 0 → NON interprétable', () {
      expect(avecVersion(0).interpretable, isFalse);
    });

    test('T-V6 · toute version ≠ 1 → NON interprétable', () {
      for (final v in <int>[-1, 0, 2, 3, 99, 1000]) {
        expect(avecVersion(v).interpretable, isFalse, reason: 'version $v');
        // Par contraste : le schéma reste correct dans TOUS ces cas. Le refus
        // vient donc bien de la version seule.
        expect(avecVersion(v).schema, kSchemaRegistreElo, reason: 'version $v');
      }
    });

    test('T-V7 · version 2 + EMPREINTE IDENTIQUE → JAMAIS cohérent', () {
      // C'est le cœur de la correction : avant, ce cas rendait `coherent`.
      final r = avecVersion(2);
      final d = diagnostiquerRegistre(
        jsonRegistre: r.encoder(),
        empreinteDisque: _fpA, // ← strictement égale à celle du registre
        nombreRatings: 4,
      );
      expect(d.empreinteRegistre, _fpA);
      expect(d.empreinteDisque, _fpA);
      expect(d.empreinteRegistre, d.empreinteDisque);
      expect(d.coherence, isNot(DiagnosticCoherenceElo.coherent));
      expect(d.coherence, DiagnosticCoherenceElo.schemaIncompatible);
      expect(d.autoriseApplication, isFalse);
      expect(d.protegeContreDoubleApplication, isFalse);
    });

    test('T-V8 · version 0 + empreinte identique → JAMAIS cohérent', () {
      final d = diagnostiquerRegistre(
        jsonRegistre: avecVersion(0).encoder(),
        empreinteDisque: _fpA,
        nombreRatings: 4,
      );
      expect(d.coherence, DiagnosticCoherenceElo.schemaIncompatible);
      expect(d.coherence, isNot(DiagnosticCoherenceElo.coherent));
      expect(d.autoriseApplication, isFalse);
    });

    test('T-V9 · version inconnue + empreinte DIFFÉRENTE → schemaIncompatible, '
        'pas divergent', () {
      // L'incompatibilité de version l'emporte sur l'écart d'empreinte : la
      // cause première reste « je ne sais pas lire ce registre ».
      final d = diagnostiquerRegistre(
        jsonRegistre: avecVersion(7).encoder(),
        empreinteDisque: _fpB,
        nombreRatings: 4,
      );
      expect(d.coherence, DiagnosticCoherenceElo.schemaIncompatible);
      expect(d.coherence, isNot(DiagnosticCoherenceElo.divergent));
      expect(d.autoriseApplication, isFalse);
    });

    test('T-V10 · version incompatible : registre NI supprimé, NI migré, '
        'NI réinterprété', () {
      final r = avecVersion(2);
      final brut = r.encoder();
      final d = diagnostiquerRegistre(
        jsonRegistre: brut,
        empreinteDisque: _fpA,
        nombreRatings: 4,
      );
      // Le registre reste lisible pour le diagnostic, intégralement.
      expect(d.registre, isNotNull);
      expect(d.registre!.version, 2);
      expect(d.registre!.schema, kSchemaRegistreElo);
      expect(d.registre!.horloge, 3);
      expect(d.registre!.empreinteRatings, _fpA);
      expect(d.registre!.entrees, isEmpty);
      // La chaîne d'origine n'a pas été touchée : décoder ne mute pas.
      final relu = RegistreEloV3.decoder(brut);
      expect(relu.version, 2);
      expect(relu.encoder(), brut);
      // Aucune coercition de version vers 1.
      expect(relu.version, isNot(kVersionRegistreElo));
    });

    test('T-V11 · message : « schéma ou version », mentions de sûreté', () {
      final d = diagnostiquerRegistre(
        jsonRegistre: avecVersion(2).encoder(),
        empreinteDisque: _fpA,
        nombreRatings: 1,
      );
      expect(d.message, contains('schéma ou d\'une version incompatible'));
      expect(d.message, contains('Aucune application automatique'));
      expect(d.message, contains('n\'est pas supprimé'));
      // Le message ne prétend jamais avoir réparé quoi que ce soit.
      for (final mot in <String>['migré', 'converti', 'réparé', 'mis à jour']) {
        expect(d.message.contains(mot), isFalse, reason: mot);
      }
    });
  });

  group('T-V · versionnement — schéma ET version combinés', () {
    test('T-V12 · schéma différent seul → refusé', () {
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo + 1,
        version: kVersionRegistreElo,
        horloge: 0,
        empreinteRatings: _fpA,
        origine: OrigineRegistreElo.courante,
        entrees: const <EntreeRegistreElo>[],
      );
      expect(r.interpretable, isFalse);
      final d = diagnostiquerRegistre(
        jsonRegistre: r.encoder(),
        empreinteDisque: _fpA,
        nombreRatings: 2,
      );
      expect(d.coherence, DiagnosticCoherenceElo.schemaIncompatible);
    });

    test('T-V13 · schéma ET version différents → refusé', () {
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo + 5,
        version: kVersionRegistreElo + 1,
        horloge: 0,
        empreinteRatings: _fpA,
        origine: OrigineRegistreElo.courante,
        entrees: const <EntreeRegistreElo>[],
      );
      expect(r.interpretable, isFalse);
      final d = diagnostiquerRegistre(
        jsonRegistre: r.encoder(),
        empreinteDisque: _fpA,
        nombreRatings: 2,
      );
      expect(d.coherence, DiagnosticCoherenceElo.schemaIncompatible);
      expect(d.autoriseApplication, isFalse);
    });

    test('T-V14 · le getter est la SEULE porte : les deux getters en dérivent',
        () {
      // autoriseApplication / protegeContreDoubleApplication ne peuvent pas
      // être vrais sur un diagnostic schemaIncompatible, quelle que soit
      // l'origine déclarée par le registre.
      for (final version in <int>[0, 2, 99]) {
        for (final origine in OrigineRegistreElo.values) {
          final r = RegistreEloV3(
            schema: kSchemaRegistreElo,
            version: version,
            horloge: 0,
            empreinteRatings: _fpA,
            origine: origine,
            entrees: const <EntreeRegistreElo>[],
          );
          final d = diagnostiquerRegistre(
            jsonRegistre: r.encoder(),
            empreinteDisque: _fpA,
            nombreRatings: 2,
          );
          expect(d.coherence, DiagnosticCoherenceElo.schemaIncompatible,
              reason: 'v$version/${origine.name}');
          expect(d.autoriseApplication, isFalse,
              reason: 'v$version/${origine.name}');
          expect(d.protegeContreDoubleApplication, isFalse,
              reason: 'v$version/${origine.name}');
        }
      }
    });
  });

  group('T-V · versionnement — aucune perte à la sérialisation', () {
    test('T-V15 · la version survit à encoder/decoder sans coercition', () {
      for (final version in <int>[0, 1, 2, 7, 1234]) {
        final r = RegistreEloV3(
          schema: kSchemaRegistreElo,
          version: version,
          horloge: 42,
          empreinteRatings: _fpB,
          origine: OrigineRegistreElo.historiqueInconnu,
          entrees: <EntreeRegistreElo>[_entreeCourse(id: 5)],
        );
        final relu = RegistreEloV3.decoder(r.encoder());
        expect(relu.version, version, reason: 'version $version');
        expect(relu.schema, kSchemaRegistreElo);
        expect(relu.horloge, 42);
        expect(relu.empreinteRatings, _fpB);
        expect(relu.origine, OrigineRegistreElo.historiqueInconnu);
        expect(relu.entrees.length, 1);
        expect(relu.entrees.single.id, 5);
        // Ré-encodage idempotent : rien n'est ajouté ni retiré.
        expect(relu.encoder(), r.encoder());
      }
    });

    test('T-V16 · le JSON contient bien le champ `version`', () {
      final json = RegistreEloV3.vierge(empreinteRatings: _fpA).toJson();
      expect(json.containsKey('version'), isTrue);
      expect(json['version'], kVersionRegistreElo);
      expect(json['schema'], kSchemaRegistreElo);
    });

    test('T-V17 · version absente du JSON → corrompu, pas « version 0 »', () {
      // Aucune valeur par défaut n'est inventée : un champ manquant est une
      // corruption. Sans cette exigence, un registre amputé passerait pour
      // une version antérieure et pourrait être interprété à tort.
      final json = RegistreEloV3.vierge(empreinteRatings: _fpA).toJson()
        ..remove('version');
      expect(() => RegistreEloV3.fromJson(json), throwsFormatException);

      final d = diagnostiquerRegistre(
        jsonRegistre: jsonEncode(json),
        empreinteDisque: _fpA,
        nombreRatings: 2,
      );
      expect(d.coherence, DiagnosticCoherenceElo.corrompu);
      expect(d.autoriseApplication, isFalse);
      expect(d.origine, OrigineRegistreElo.historiqueInconnu);
    });

    test('T-V18 · version non entière → refusée', () {
      for (final mauvais in <Object>['1', 1.5, true, <int>[], <String, int>{}]) {
        final json = RegistreEloV3.vierge(empreinteRatings: _fpA).toJson()
          ..['version'] = mauvais;
        expect(() => RegistreEloV3.fromJson(json), throwsFormatException,
            reason: '$mauvais (${mauvais.runtimeType})');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 10 ter — 3.3-A.1 : HISTORIQUE INCONNU, NON-RÉGRESSION
  //  Les trois situations du contrat, assertées ensemble.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-H · historique inconnu — les trois situations', () {
    test('T-H1 · SITUATION 1 — registre absent + ratings vides = premier usage',
        () {
      final d = diagnostiquerRegistre(
        jsonRegistre: null,
        empreinteDisque: _fpVide,
        nombreRatings: 0,
      );
      expect(d.coherence, DiagnosticCoherenceElo.registreAbsent);
      expect(d.origine, OrigineRegistreElo.courante);
      expect(d.message, 'Premier usage : aucun registre ELO antérieur.');
      // Aucune protection n'est annoncée, et aucune n'est nécessaire : il n'y a
      // rien à protéger.
      expect(d.protegeContreDoubleApplication, isFalse);
      expect(d.autoriseApplication, isTrue);
      // Le message ne mentionne pas d'historique inconnu : ce serait faux.
      expect(d.message.contains('Historique'), isFalse);
    });

    test('T-H2 · SITUATION 2 — registre absent + ratings existants = '
        'historiqueInconnu', () {
      final d = diagnostiquerRegistre(
        jsonRegistre: null,
        empreinteDisque: _fpB,
        nombreRatings: 1, // une seule entrée suffit à changer de situation
      );
      expect(d.coherence, DiagnosticCoherenceElo.registreAbsent);
      expect(d.origine, OrigineRegistreElo.historiqueInconnu);
      expect(d.message, _messageImpose);
      // AUCUNE protection rétroactive n'est annoncée.
      expect(d.protegeContreDoubleApplication, isFalse);
      // Mais l'application reste autorisée : bloquer serait une régression.
      expect(d.autoriseApplication, isTrue);
    });

    test('T-H2b · le seuil est exactement 0 / 1 rating', () {
      for (final n in <int>[0, 1, 2, 37, 5000]) {
        final d = diagnostiquerRegistre(
          jsonRegistre: null,
          empreinteDisque: _fpA,
          nombreRatings: n,
        );
        expect(
          d.origine,
          n == 0
              ? OrigineRegistreElo.courante
              : OrigineRegistreElo.historiqueInconnu,
          reason: 'nombreRatings=$n',
        );
      }
    });

    test('T-H3 · SITUATION 3 — origine historiqueInconnu + empreinte cohérente '
        '→ origine CONSERVÉE, protection FAUSSE', () {
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 11,
        empreinteRatings: _fpB,
        origine: OrigineRegistreElo.historiqueInconnu,
        entrees: const <EntreeRegistreElo>[],
      );
      final d = diagnostiquerRegistre(
        jsonRegistre: r.encoder(),
        empreinteDisque: _fpB, // strictement cohérent
        nombreRatings: 9,
      );
      expect(d.coherence, DiagnosticCoherenceElo.coherent);
      // L'origine déclarée par le registre est CONSERVÉE : rien ne la remet à
      // `courante` automatiquement, même quand tout est cohérent.
      expect(d.origine, OrigineRegistreElo.historiqueInconnu);
      expect(d.registre!.origine, OrigineRegistreElo.historiqueInconnu);
      // Aucune protection : c'est l'exigence centrale.
      expect(d.protegeContreDoubleApplication, isFalse);
      expect(d.autoriseApplication, isTrue);
      expect(d.message, _messageImpose);
    });

    test('T-H4 · l\'origine n\'est jamais promue automatiquement', () {
      // Un enregistrement à l'identique ne change rien : seule une opération
      // explicite pourra le faire (hors périmètre de ce lot).
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 1,
        empreinteRatings: _fpA,
        origine: OrigineRegistreElo.historiqueInconnu,
        entrees: const <EntreeRegistreElo>[],
      );
      final une = RegistreEloV3.decoder(r.encoder());
      final deux = RegistreEloV3.decoder(une.encoder());
      expect(une.origine, OrigineRegistreElo.historiqueInconnu);
      expect(deux.origine, OrigineRegistreElo.historiqueInconnu);
      // copyWith ne promeut pas non plus.
      expect(deux.copyWith(horloge: 2).origine,
          OrigineRegistreElo.historiqueInconnu);
    });

    test('T-H5 · les trois situations sont mutuellement distinctes', () {
      final s1 = diagnostiquerRegistre(
        jsonRegistre: null,
        empreinteDisque: _fpVide,
        nombreRatings: 0,
      );
      final s2 = diagnostiquerRegistre(
        jsonRegistre: null,
        empreinteDisque: _fpB,
        nombreRatings: 3,
      );
      final r3 = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 0,
        empreinteRatings: _fpB,
        origine: OrigineRegistreElo.historiqueInconnu,
        entrees: const <EntreeRegistreElo>[],
      );
      final s3 = diagnostiquerRegistre(
        jsonRegistre: r3.encoder(),
        empreinteDisque: _fpB,
        nombreRatings: 3,
      );
      // S1 et S2 partagent la cohérence mais diffèrent par l'origine.
      expect(s1.coherence, s2.coherence);
      expect(s1.origine, isNot(s2.origine));
      expect(s1.message, isNot(s2.message));
      // S3 diffère des deux par la cohérence.
      expect(s3.coherence, isNot(s1.coherence));
      expect(s3.coherence, isNot(s2.coherence));
      // S2 et S3 portent le même avertissement imposé, mais pas le même état.
      expect(s2.message, s3.message);
      expect(s2.coherence, isNot(s3.coherence));
    });

    test('T-H6 · aucun des trois cas ne prétend être protégé', () {
      final diags = <ResultatDiagnosticElo>[
        diagnostiquerRegistre(
          jsonRegistre: null,
          empreinteDisque: _fpVide,
          nombreRatings: 0,
        ),
        diagnostiquerRegistre(
          jsonRegistre: null,
          empreinteDisque: _fpB,
          nombreRatings: 3,
        ),
        diagnostiquerRegistre(
          jsonRegistre: RegistreEloV3(
            schema: kSchemaRegistreElo,
            version: kVersionRegistreElo,
            horloge: 0,
            empreinteRatings: _fpB,
            origine: OrigineRegistreElo.historiqueInconnu,
            entrees: const <EntreeRegistreElo>[],
          ).encoder(),
          empreinteDisque: _fpB,
          nombreRatings: 3,
        ),
      ];
      for (final d in diags) {
        expect(d.protegeContreDoubleApplication, isFalse,
            reason: d.toString());
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 11 — SOUS-ÉTATS D'INTERRUPTION
  // ═════════════════════════════════════════════════════════════════════════
  group('T-X · sousEtatInterruption', () {
    test('T-X1 · entrée appliquée → aucune', () {
      final e = _entreeCourse();
      expect(
        sousEtatInterruption(entree: e, empreinteDisque: _fpApres),
        SousEtatInterruptionElo.aucune,
      );
    });

    test('T-X2 · disque == empreinteApres → appliqueeSansAcquittement', () {
      for (final etape in <EtapeEntreeRegistre>[
        EtapeEntreeRegistre.intention,
        EtapeEntreeRegistre.nonConfirmee,
      ]) {
        final e = etape == EtapeEntreeRegistre.intention
            ? _entreeCourse(etape: etape, issue: null, tsFinal: null)
            : _entreeCourse(
                etape: etape,
                issue: IssueEcritureElo.echouee,
                tsFinal: null,
              );
        expect(
          sousEtatInterruption(entree: e, empreinteDisque: e.empreinteApres),
          SousEtatInterruptionElo.appliqueeSansAcquittement,
          reason: etape.name,
        );
      }
    });

    test('T-X3 · disque == empreinteAvant → intentionSansEcriture', () {
      final e = _entreeCourse(
        etape: EtapeEntreeRegistre.intention,
        issue: null,
        tsFinal: null,
      );
      expect(
        sousEtatInterruption(entree: e, empreinteDisque: e.empreinteAvant),
        SousEtatInterruptionElo.intentionSansEcriture,
      );
    });

    test('T-X4 · empreinte étrangère → indetermine (aucune attribution)', () {
      final e = _entreeCourse(
        etape: EtapeEntreeRegistre.intention,
        issue: null,
        tsFinal: null,
      );
      expect(
        sousEtatInterruption(
            entree: e, empreinteDisque: '9999999999999999'),
        SousEtatInterruptionElo.indetermine,
      );
    });

    test('T-X5 · priorité : l\'APRÈS est testé avant l\'AVANT', () {
      // Cas dégénéré où avant == apres pour une entrée INCERTAINE : l'ordre de
      // comparaison décide. Le code teste `empreinteApres` en premier, donc
      // c'est `appliqueeSansAcquittement` qui doit sortir. Une entrée
      // `appliquee` rendrait `aucune` AVANT toute comparaison (test T-X1) :
      // c'est pourquoi ce cas utilise `intention`.
      final e = _entreeCourse(
        etape: EtapeEntreeRegistre.intention,
        issue: null,
        tsFinal: null,
        empreinteAvant: _fpA,
        empreinteApres: _fpA,
      );
      expect(e.estIncertaine, isTrue);
      expect(
        sousEtatInterruption(entree: e, empreinteDisque: _fpA),
        SousEtatInterruptionElo.appliqueeSansAcquittement,
      );
    });

    test('T-X6 · deux entrées non terminales : une seule peut correspondre', () {
      final e1 = _entreeCourse(
        id: 1,
        etape: EtapeEntreeRegistre.intention,
        issue: null,
        tsFinal: null,
        empreinteAvant: '1111111111111111',
        empreinteApres: '2222222222222222',
      );
      final e2 = _entreeCourse(
        id: 2,
        etape: EtapeEntreeRegistre.intention,
        issue: null,
        tsFinal: null,
        empreinteAvant: '3333333333333333',
        empreinteApres: '4444444444444444',
      );
      const disque = '2222222222222222';
      expect(
        sousEtatInterruption(entree: e1, empreinteDisque: disque),
        SousEtatInterruptionElo.appliqueeSansAcquittement,
      );
      expect(
        sousEtatInterruption(entree: e2, empreinteDisque: disque),
        SousEtatInterruptionElo.indetermine,
      );
    });

    test('T-X7 · fonction PURE : aucun champ de l\'entrée n\'est modifié', () {
      final e = _entreeCourse(
        etape: EtapeEntreeRegistre.nonConfirmee,
        issue: IssueEcritureElo.refusee,
        tsFinal: null,
      );
      final avant = e.toJson();
      sousEtatInterruption(entree: e, empreinteDisque: _fpA);
      sousEtatInterruption(entree: e, empreinteDisque: _fpB);
      expect(e.toJson(), avant);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 12 — RÉTENTION
  // ═════════════════════════════════════════════════════════════════════════
  group('T-L · classerRetention et compacterEntree', () {
    test('T-L1 · bornes exactes des quatre niveaux', () {
      expect(classerRetention(0), NiveauRetentionElo.normal);
      expect(classerRetention(kSeuilVeilleOctets - 1), NiveauRetentionElo.normal);
      expect(classerRetention(kSeuilVeilleOctets), NiveauRetentionElo.veille);
      expect(
          classerRetention(kSeuilAlerteOctets - 1), NiveauRetentionElo.veille);
      expect(classerRetention(kSeuilAlerteOctets), NiveauRetentionElo.alerte);
      expect(
          classerRetention(kSeuilSaturationOctets - 1), NiveauRetentionElo.alerte);
      expect(
          classerRetention(kSeuilSaturationOctets), NiveauRetentionElo.saturation);
      expect(classerRetention(100000000), NiveauRetentionElo.saturation);
    });

    test('T-L2 · une entrée incertaine N\'EST JAMAIS compactée', () {
      final cheval = _cheval(avant: null);
      for (final etape in <EtapeEntreeRegistre>[
        EtapeEntreeRegistre.intention,
        EtapeEntreeRegistre.nonConfirmee,
      ]) {
        final e = etape == EtapeEntreeRegistre.intention
            ? _entreeCourse(
                etape: etape,
                issue: null,
                tsFinal: null,
                chevaux: <ChevalJournalise>[cheval],
              )
            : _entreeCourse(
                etape: etape,
                issue: IssueEcritureElo.refusee,
                tsFinal: null,
                chevaux: <ChevalJournalise>[cheval],
              );
        final compactee = compacterEntree(e);
        expect(identical(compactee, e), isTrue, reason: etape.name);
        expect(compactee.chevaux.length, 1, reason: etape.name);
      }
    });

    test('T-L3 · une entrée appliquée EST compactée, preuves conservées', () {
      final e = _entreeCourse(
        id: 77,
        chevaux: <ChevalJournalise>[
          _cheval(avant: null, cle: 'A|PLAT'),
          _cheval(avant: null, cle: 'B|PLAT'),
        ],
      );
      final c = compacterEntree(e);
      expect(c.chevaux, isEmpty);
      // Toutes les preuves utiles restent : rien d'autre n'est perdu.
      expect(c.id, 77);
      expect(c.type, TypeEntreeRegistre.course);
      expect(c.cle, e.cle);
      expect(c.numR, e.numR);
      expect(c.numC, e.numC);
      expect(c.date, e.date);
      expect(c.discipline, e.discipline);
      expect(c.etape, EtapeEntreeRegistre.appliquee);
      expect(c.issue, IssueEcritureElo.persistee);
      expect(c.tsIntention, e.tsIntention);
      expect(c.tsFinal, e.tsFinal);
      expect(c.empreinteAvant, e.empreinteAvant);
      expect(c.empreinteApres, e.empreinteApres);
      // Le blocage et la vérification ne dépendent pas de `chevaux`.
      expect(c.bloqueNouvelleSoumission, isTrue);
      expect(c.estIncertaine, isFalse);
    });

    test('T-L4 · compaction IDEMPOTENTE et source inchangée', () {
      final e = _entreeCourse(chevaux: <ChevalJournalise>[_cheval(avant: null)]);
      final c1 = compacterEntree(e);
      final c2 = compacterEntree(c1);
      expect(c2.chevaux, isEmpty);
      expect(c2.id, c1.id);
      expect(e.chevaux.length, 1); // source non mutée
    });

    test('T-L5 · une entrée sans chevaux est rendue telle quelle', () {
      final e = _entreeHorsCourse();
      final c = compacterEntree(e);
      expect(identical(c, e), isTrue);
    });

    test('T-L6 · après compaction, l\'entrée relue reste valide', () {
      final e = _entreeCourse(chevaux: <ChevalJournalise>[_cheval(avant: null)]);
      final c = compacterEntree(e);
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 1,
        empreinteRatings: _fpA,
        origine: OrigineRegistreElo.courante,
        entrees: <EntreeRegistreElo>[c],
      );
      final relu = RegistreEloV3.decoder(r.encoder());
      expect(relu.entrees.single.chevaux, isEmpty);
      expect(relu.entrees.single.empreinteApres, _fpB);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  GROUPE 13 — LIMITES DÉCLARÉES (contrôle de non-surestimation)
  // ═════════════════════════════════════════════════════════════════════════
  group('T-M · limites documentées', () {
    test('T-M1 · l\'empreinte n\'est PAS injective par construction', () {
      // L'espace de sortie est fini (16 hex = 2^64) : deux contenus distincts
      // PEUVENT collisionner. On vérifie ici seulement que la sortie est
      // contrainte à 2^64 valeurs, ce qui interdit toute prétention
      // d'injectivité.
      final re = RegExp(r'^[0-9a-f]{16}$');
      final fp = empreinte64Ratings(<String, EloScore>{'A|PLAT': _sc(1500.0)});
      expect(re.hasMatch(fp), isTrue);
      expect(fp.length, 16);
      // 16 hexadécimaux = 64 bits = 1,8446744e19 valeurs possibles.
      expect(16 * 4, 64);
    });

    test('T-M2 · encoder() LÈVE sur un double non fini dans une image', () {
      // Limite DÉCLARÉE : le modèle ne masque pas l'exception de jsonEncode.
      // Ce n'est pas une garantie de succès, c'est un comportement constaté.
      final r = RegistreEloV3(
        schema: kSchemaRegistreElo,
        version: kVersionRegistreElo,
        horloge: 1,
        empreinteRatings: _fpA,
        origine: OrigineRegistreElo.courante,
        entrees: <EntreeRegistreElo>[
          _entreeCourse(
            chevaux: <ChevalJournalise>[
              ChevalJournalise(
                cle: 'K|PLAT',
                nom: 'K',
                avant: null,
                apres: ImageRatingElo(
                  rating: double.nan,
                  nbCourses: 1,
                  variationMois: 0.0,
                ),
              ),
            ],
          ),
        ],
      );
      expect(r.encoder, throwsA(isA<JsonUnsupportedObjectError>()));
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────
//  Constantes de lisibilité
// ───────────────────────────────────────────────────────────────────────────

const String _fpApres = 'fedcba9876543210';

/// Empreinte MESURÉE de `empreinte64Ratings(<String, EloScore>{})`.
/// Vérifiée par T-F6 : une map vide rend `16ed60fcfaed47f4`.
const String _fpVide = '16ed60fcfaed47f4';

const String _fichierModele = 'lib/models/elo_registre_v3.dart';
const String _fichierEmpreinte = 'lib/utils/elo_empreinte.dart';

/// Lignes de CODE du fichier : les commentaires `//` (y compris `///`) et les
/// lignes vides sont retirés.
///
/// Indispensable : ces deux fichiers CITENT `SharedPreferences`, `elo_service`
/// et `Map<String, EloScore>` dans leur documentation, ce qui est légitime et
/// documentaire. Tester `contains` sur le fichier brut mesurerait la prose, pas
/// le comportement. Ce filtre isole ce qui est réellement exécutable.
///
/// Limite déclarée : ce filtre ne reconnaît ni les blocs `/* */` ni un `//` en
/// fin de ligne de code. Les deux fichiers testés n'en contiennent aucun
/// (vérifié par `T-S3`/`T-S3b` qui exigent que chaque occurrence fautive soit
/// en début de commentaire).
List<String> _lignesDeCode(String chemin) => File(chemin)
    .readAsLinesSync()
    .where((l) {
      final t = l.trimLeft();
      return t.isNotEmpty && !t.startsWith('//');
    })
    .toList();

const String _messageImpose =
    'Historique d\'application ELO inconnu. Les courses antérieures ne '
    'sont pas mémorisées. Une nouvelle application sur l\'une d\'elles ne '
    'peut pas être détectée par le registre.';
