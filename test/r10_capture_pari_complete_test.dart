// R10 — les cinq faux positifs mesurés par la sonde doivent être corrigés.
//
// Cette sonde rejoue EXACTEMENT les cinq cas qui rendaient `true` à tort, et
// vérifie qu'ils rendent désormais `false`. Elle contrôle les DEUX modèles
// jumeaux (`UserPrediction` et `TrackedCourse`) pour qu'ils ne divergent pas.
import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart';

UserPrediction _p({
  String typePari = 'Quinté+',
  List<int> numerosJoues = const [],
  String? codePmuOfficiel,
  String? varianteChoisie,
  List<int>? numerosDansOrdre,
  String? formulePari,
}) {
  return UserPrediction(
    id: 'x',
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
    formulePari: formulePari,
  );
}

TrackedCourse _t({
  String typePari = 'Quinté+',
  List<int> numerosJoues = const [],
  String? codePmuOfficiel,
  String? varianteChoisie,
  List<int>? numerosDansOrdre,
  String? formulePari,
}) {
  return TrackedCourse(
    numReunion: 1,
    numCourse: 1,
    nomCourse: 'C',
    hippodrome: 'H',
    heureDepart: DateTime(2026, 1, 1, 14),
    nomCheval: 'X',
    numeroCheval: 1,
    typePari: typePari,
    numerosJoues: numerosJoues,
    codePmuOfficiel: codePmuOfficiel,
    varianteChoisie: varianteChoisie,
    numerosDansOrdre: numerosDansOrdre,
    formulePari: formulePari,
  );
}

void main() {
  // ───────────────────────────────────────────────────────────────────────
  group('R10/1 — les CINQ faux positifs mesurés sont corrigés', () {
    test('FP1 — Quinté+ avec code mais ZÉRO numéro => incomplet', () {
      final p = _p(
          typePari: 'Quinté+',
          numerosJoues: const [],
          codePmuOfficiel: 'E_QUINTE_PLUS');
      final t = _t(
          typePari: 'Quinté+',
          numerosJoues: const [],
          codePmuOfficiel: 'E_QUINTE_PLUS');
      expect(p.capturePariComplete, isFalse,
          reason: '5 numéros attendus, 0 enregistré');
      expect(t.capturePariComplete, isFalse);
    });

    test('FP2 — Tiercé avec code mais 2 numéros au lieu de 3 => incomplet', () {
      final p = _p(
          typePari: 'Tiercé',
          numerosJoues: const [1, 2],
          codePmuOfficiel: 'E_TIERCE');
      final t = _t(
          typePari: 'Tiercé',
          numerosJoues: const [1, 2],
          codePmuOfficiel: 'E_TIERCE');
      expect(p.capturePariComplete, isFalse);
      expect(t.capturePariComplete, isFalse);
    });

    test('FP3 — ticket vide dont seul le code est forcé => incomplet', () {
      final p = _p(
          typePari: 'Quinté+',
          numerosJoues: const [],
          codePmuOfficiel: 'E_QUINTE_PLUS');
      expect(p.capturePariComplete, isFalse);
    });

    test('FP4 — ordre incompatible avec les numéros joués => incomplet', () {
      // « Tiercé Ordre » exige l'ordre. Les numéros joués sont 1,2,3 mais
      // l'ordre prétend 9,8,7 : ce ne sont pas les mêmes chevaux.
      final p = _p(
        typePari: 'Tiercé Ordre',
        numerosJoues: const [1, 2, 3],
        codePmuOfficiel: 'E_TIERCE',
        varianteChoisie: 'ordre',
        numerosDansOrdre: const [9, 8, 7],
      );
      final t = _t(
        typePari: 'Tiercé Ordre',
        numerosJoues: const [1, 2, 3],
        codePmuOfficiel: 'E_TIERCE',
        varianteChoisie: 'ordre',
        numerosDansOrdre: const [9, 8, 7],
      );
      expect(p.capturePariComplete, isFalse);
      expect(t.capturePariComplete, isFalse);
    });

    test('FP5 — Multi sans formule => incomplet (type non reconnu)', () {
      // « Multi » n'est pas dans la table de `typePariDepuisLibelle` : le type
      // est donc inconnu, et on ne peut rien affirmer. Un code PMU présent ne
      // suffit pas à compenser.
      final p = _p(
          typePari: 'Multi',
          numerosJoues: const [1, 2, 3, 4],
          codePmuOfficiel: 'E_MULTI');
      final t = _t(
          typePari: 'Multi',
          numerosJoues: const [1, 2, 3, 4],
          codePmuOfficiel: 'E_MULTI');
      expect(p.capturePariComplete, isFalse,
          reason: 'type inconnu => aucune attente vérifiable');
      expect(t.capturePariComplete, isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R10/2 — les tickets réellement complets restent complets', () {
    test('Simple Gagnant avec 1 numéro et son code => complet', () {
      final p = _p(
          typePari: 'Simple Gagnant',
          numerosJoues: const [7],
          codePmuOfficiel: 'E_SIMPLE_GAGNANT');
      final t = _t(
          typePari: 'Simple Gagnant',
          numerosJoues: const [7],
          codePmuOfficiel: 'E_SIMPLE_GAGNANT');
      expect(p.capturePariComplete, isTrue);
      expect(t.capturePariComplete, isTrue);
    });

    test('Tiercé avec 3 numéros => complet (aucune variante requise)', () {
      final p = _p(
          typePari: 'Tiercé',
          numerosJoues: const [1, 3, 5],
          codePmuOfficiel: 'E_TIERCE');
      expect(p.capturePariComplete, isTrue);
    });

    test('Quinté+ avec 5 numéros => complet', () {
      final p = _p(
          typePari: 'Quinté+',
          numerosJoues: const [1, 3, 5, 7, 9],
          codePmuOfficiel: 'E_QUINTE_PLUS');
      final t = _t(
          typePari: 'Quinté+',
          numerosJoues: const [1, 3, 5, 7, 9],
          codePmuOfficiel: 'E_QUINTE_PLUS');
      expect(p.capturePariComplete, isTrue);
      expect(t.capturePariComplete, isTrue);
    });

    test('Tiercé Ordre avec 3 numéros + ordre cohérent + variante => complet',
        () {
      final p = _p(
        typePari: 'Tiercé Ordre',
        numerosJoues: const [1, 3, 5],
        codePmuOfficiel: 'E_TIERCE',
        varianteChoisie: 'ordre',
        numerosDansOrdre: const [5, 1, 3],
      );
      expect(p.capturePariComplete, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R10/3 — la variante requise est désormais contrôlée', () {
    test('Tiercé Ordre SANS variante => incomplet', () {
      final p = _p(
        typePari: 'Tiercé Ordre',
        numerosJoues: const [1, 3, 5],
        codePmuOfficiel: 'E_TIERCE',
        numerosDansOrdre: const [1, 3, 5],
      );
      expect(p.capturePariComplete, isFalse,
          reason: 'le choix Ordre/Désordre est requis et absent');
    });

    test('Couplé Ordre exige aussi sa variante', () {
      final sans = _p(
        typePari: 'Couplé Ordre',
        numerosJoues: const [1, 3],
        codePmuOfficiel: 'E_COUPLE_ORDRE',
        numerosDansOrdre: const [1, 3],
      );
      expect(sans.capturePariComplete, isFalse);
      final avec = _p(
        typePari: 'Couplé Ordre',
        numerosJoues: const [1, 3],
        codePmuOfficiel: 'E_COUPLE_ORDRE',
        varianteChoisie: 'ordre',
        numerosDansOrdre: const [1, 3],
      );
      expect(avec.capturePariComplete, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R10/4 — un code PMU ne suffit jamais à lui seul', () {
    test('code présent + type connu + 0 numéro => incomplet, pour les 8 types',
        () {
      for (final t in [
        'Simple Gagnant',
        'Simple Placé',
        'Couplé Gagnant',
        'Couplé Placé',
        'Tiercé',
        'Quarté+',
        'Quinté+',
      ]) {
        final p = _p(
            typePari: t, numerosJoues: const [], codePmuOfficiel: 'E_X');
        expect(p.capturePariComplete, isFalse, reason: '$t : aucun numéro');
      }
    });

    test('type inconnu => incomplet même avec numéros et code', () {
      final p = _p(
          typePari: 'Type Bidon',
          numerosJoues: const [1],
          codePmuOfficiel: 'E_X');
      expect(p.capturePariComplete, isFalse);
    });

    test('trop de numéros => incomplet (le compte doit être exact)', () {
      // Un Quinté+ avec 6 numéros n'est pas « plus complet » : il est anormal.
      final p = _p(
          typePari: 'Quinté+',
          numerosJoues: const [1, 2, 3, 4, 5, 6],
          codePmuOfficiel: 'E_QUINTE_PLUS');
      expect(p.capturePariComplete, isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R10/5 — les deux modèles ne divergent jamais', () {
    test('même verdict sur les cinq faux positifs ET sur les cas valides', () {
      // Table de cas : (type, numéros, code, variante, ordre)
      final cas = <List<Object?>>[
        ['Quinté+', <int>[], 'E_QUINTE_PLUS', null, null],
        ['Tiercé', <int>[1, 2], 'E_TIERCE', null, null],
        ['Simple Gagnant', <int>[7], 'E_SIMPLE_GAGNANT', null, null],
        ['Tiercé', <int>[1, 3, 5], 'E_TIERCE', null, null],
        ['Quinté+', <int>[1, 3, 5, 7, 9], 'E_QUINTE_PLUS', null, null],
        ['Tiercé Ordre', <int>[1, 2, 3], 'E_TIERCE', 'ordre', <int>[9, 8, 7]],
        ['Tiercé Ordre', <int>[1, 2, 3], 'E_TIERCE', 'ordre', <int>[3, 1, 2]],
        ['Multi', <int>[1, 2, 3, 4], 'E_MULTI', null, null],
      ];
      for (final c in cas) {
        final type = c[0] as String;
        final nums = c[1] as List<int>;
        final code = c[2] as String?;
        final variante = c[3] as String?;
        final ordre = c[4] as List<int>?;
        final p = _p(
            typePari: type,
            numerosJoues: nums,
            codePmuOfficiel: code,
            varianteChoisie: variante,
            numerosDansOrdre: ordre);
        final t = _t(
            typePari: type,
            numerosJoues: nums,
            codePmuOfficiel: code,
            varianteChoisie: variante,
            numerosDansOrdre: ordre);
        expect(p.capturePariComplete, t.capturePariComplete,
            reason: 'divergence sur $type / $nums');
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R10/6 — ce getter ne parle PAS d\'argent', () {
    test('une mise absente ne rend pas le ticket « incomplet »', () {
      final p = _p(
          typePari: 'Simple Gagnant',
          numerosJoues: const [1],
          codePmuOfficiel: 'E_SIMPLE_GAGNANT');
      expect(p.montantMise, 0.0);
      expect(p.capturePariComplete, isTrue,
          reason: 'la calculabilité financière est une autre question');
    });

    test('un rapport officiel manquant ne change pas le verdict', () {
      final p = _p(
          typePari: 'Tiercé',
          numerosJoues: const [1, 3, 5],
          codePmuOfficiel: 'E_TIERCE');
      expect(p.combinaisonPmu, isNull);
      expect(p.dividendePmuReel, isNull);
      expect(p.capturePariComplete, isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R10/7 — JSON : le getter n\'est jamais persisté', () {
    test('capturePariComplete absent du JSON des deux modèles', () {
      final p = _p(
          typePari: 'Tiercé',
          numerosJoues: const [1, 3, 5],
          codePmuOfficiel: 'E_TIERCE');
      final t = _t(
          typePari: 'Tiercé',
          numerosJoues: const [1, 3, 5],
          codePmuOfficiel: 'E_TIERCE');
      expect(p.toJson().containsKey('capturePariComplete'), isFalse);
      expect(t.toJson().containsKey('capturePariComplete'), isFalse);
    });

    test('le verdict survit à un aller-retour JSON', () {
      final p = _p(
          typePari: 'Tiercé',
          numerosJoues: const [1, 3, 5],
          codePmuOfficiel: 'E_TIERCE');
      final relu = UserPrediction.fromJson(p.toJson());
      expect(relu.capturePariComplete, isTrue);

      final vide = _p(
          typePari: 'Tiercé', numerosJoues: const [], codePmuOfficiel: 'E_TIERCE');
      expect(UserPrediction.fromJson(vide.toJson()).capturePariComplete,
          isFalse);
    });
  });
}
