// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 2 — RECONNAISSANCE EN LECTURE DES TYPES DE PARIS HISTORIQUES
//
//  Ce fichier est strictement additif : aucun test existant n'est modifié.
//
//  Il vérifie trois choses, dans cet ordre d'importance :
//   1. la lecture seule — rien n'est réécrit, ni en mémoire ni à la
//      sérialisation ;
//   2. la non-assimilation — Tiercé n'est jamais Trio, Quarté+ jamais Super4,
//      Quinté+ jamais Multi ;
//   3. le refus du défaut — un type absent, vide ou inconnu reste NON RÉSOLU,
//      il ne devient jamais « Simple Gagnant ».
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/referentiel_paris_pmu.dart';

/// Construit un `TrackedCourse` minimal, avec un `typePari` donné.
TrackedCourse _tc(String typePari, {String? storageKey, List<int>? joues}) {
  return TrackedCourse(
    numReunion: 1,
    numCourse: 3,
    nomCourse: 'Prix de Test',
    hippodrome: 'VINCENNES',
    heureDepart: DateTime(2026, 11, 21, 14, 30),
    typePari: typePari,
    storageKey: storageKey ?? 'R1C3_21112026',
    numerosJoues: joues ?? const [7, 4, 2],
    miseEngagee: 10.0,
  );
}

/// Construit un `UserPrediction` minimal, avec un `typePari` donné.
UserPrediction _up(String typePari, {List<int>? joues}) {
  return UserPrediction(
    id: 'pred-1',
    dateStr: '21112026',
    numReunion: 1,
    numCourse: 3,
    nomCourse: 'Prix de Test',
    hippodrome: 'VINCENNES',
    numeroCheval: 7,
    nomCheval: 'IDEAL DU MOULIN',
    cote: 6.5,
    typePari: typePari,
    createdAt: DateTime(2026, 11, 21, 13, 0),
    montantMise: 10.0,
    numerosJoues: joues ?? const [7, 4, 2],
  );
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  group('E2/1 — lecture seule : la chaîne enregistrée n\'est jamais réécrite',
      () {
    test('TrackedCourse conserve le typePari exactement tel quel', () {
      for (final lib in [
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
        'TRIO',
        'Super4',
        'Multi en 5',
        'inconnu xyz',
        '',
      ]) {
        expect(_tc(lib).typePari, lib,
            reason: 'le typePari doit rester « $lib » au caractère près');
      }
    });

    test('UserPrediction conserve le typePari exactement tel quel', () {
      for (final lib in [
        'Simple Gagnant',
        'Gagnant+Placé',
        'Tiercé',
        'Quinté+',
        'TRIO',
        'inconnu xyz',
        '',
      ]) {
        expect(_up(lib).typePari, lib, reason: lib);
      }
    });

    test('les getters de lecture ne modifient pas le typePari', () {
      // On lit TOUS les getters, puis on revérifie la chaîne d'origine.
      for (final lib in ['Tiercé', 'Gagnant+Placé', 'inconnu', '']) {
        final tc = _tc(lib);
        // Lecture de tous les getters dérivés.
        // ignore: unnecessary_statements
        tc.typePmu;
        // ignore: unnecessary_statements
        tc.typePariReconnu;
        // ignore: unnecessary_statements
        tc.typePariHorsReferentielPmu;
        // ignore: unnecessary_statements
        tc.typePariNonResolu;
        expect(tc.typePari, lib,
            reason: 'aucun getter ne doit réécrire la chaîne');
      }
    });

    test('toJson de TrackedCourse n\'ajoute aucune clé et garde typePari', () {
      final tc = _tc('Tiercé');
      final json = tc.toJson();
      expect(json['typePari'], 'Tiercé');
      // Les getters sont DÉRIVÉS : ils ne doivent pas apparaître dans le JSON.
      for (final interdit in [
        'typePmu',
        'typePariReconnu',
        'typePariHorsReferentielPmu',
        'typePariNonResolu',
      ]) {
        expect(json.containsKey(interdit), isFalse,
            reason: '$interdit ne doit jamais être persisté');
      }
    });

    test('toJson de UserPrediction n\'ajoute aucune clé et garde typePari', () {
      final up = _up('Quarté+');
      final json = up.toJson();
      expect(json['typePari'], 'Quarté+');
      for (final interdit in [
        'typePmu',
        'typePariReconnu',
        'typePariHorsReferentielPmu',
        'typePariNonResolu',
      ]) {
        expect(json.containsKey(interdit), isFalse, reason: interdit);
      }
    });

    test('les clés historiques de TrackedCourse sont toutes présentes', () {
      final json = _tc('Simple Gagnant').toJson();
      for (final cle in [
        'numReunion',
        'numCourse',
        'nomCourse',
        'hippodrome',
        'heureDepart',
        'nomCheval',
        'numeroCheval',
        'miseEngagee',
        'miseGagnant',
        'misePlace',
        'coteGagnant',
        'cotePlace',
        'addedAt',
        'typePari',
        'numerosJoues',
        'iaMemKey',
        'scoreIA',
        'cote',
        'isGagne',
        'arriveeFinale',
        'messageResultat',
        'dividendePmuReel',
        'combinaisonPmu',
        'storageKey',
      ]) {
        expect(json.containsKey(cle), isTrue, reason: 'clé perdue : $cle');
      }
      expect(json.length, 24, reason: 'aucune clé ajoutée ni retirée');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E2/2 — non-assimilation : Tiercé ≠ Trio, Quarté+ ≠ Super4, '
      'Quinté+ ≠ Multi', () {
    test('Tiercé n\'est jamais interprété comme Trio', () {
      final tc = _tc('Tiercé');
      expect(tc.typePmu, TypePariPmu.tierce);
      expect(tc.typePmu, isNot(TypePariPmu.trio));
      expect(tc.typePmu, isNot(TypePariPmu.trioOrdre));
      expect(codeApiPourTypePmu(tc.typePmu!), 'E_TIERCE');
    });

    test('Tiercé Ordre et Tiercé Désordre restent Tiercé, pas Trio', () {
      for (final lib in ['Tiercé Ordre', 'Tiercé Désordre']) {
        final tc = _tc(lib);
        expect(tc.typePmu, TypePariPmu.tierce, reason: lib);
        expect(tc.typePmu, isNot(TypePariPmu.trio), reason: lib);
        expect(codeApiPourTypePmu(tc.typePmu!), 'E_TIERCE', reason: lib);
      }
    });

    test('Quarté+ n\'est jamais interprété comme Super4', () {
      final tc = _tc('Quarté+');
      expect(tc.typePmu, TypePariPmu.quartePlus);
      expect(tc.typePmu, isNot(TypePariPmu.superQuatre));
      expect(codeApiPourTypePmu(tc.typePmu!), 'E_QUARTE_PLUS');
    });

    test('Quinté+ n\'est jamais interprété comme Multi ni MiniMulti', () {
      final tc = _tc('Quinté+');
      expect(tc.typePmu, TypePariPmu.quintePlus);
      expect(tc.typePmu, isNot(TypePariPmu.multi));
      expect(tc.typePmu, isNot(TypePariPmu.miniMulti));
      expect(codeApiPourTypePmu(tc.typePmu!), 'E_QUINTE_PLUS');
    });

    test('Couplé Gagnant, Placé et Ordre restent distincts', () {
      expect(_tc('Couplé Gagnant').typePmu, TypePariPmu.coupleGagnant);
      expect(_tc('Couplé Placé').typePmu, TypePariPmu.couplePlace);
      expect(_tc('Couplé Ordre').typePmu, TypePariPmu.coupleOrdre);
      expect(_tc('Couplé Gagnant').typePmu,
          isNot(_tc('Couplé Ordre').typePmu));
    });

    test('Couplé Désordre reste Couplé Gagnant, sans code inventé', () {
      final tc = _tc('Couplé Désordre');
      expect(tc.typePmu, TypePariPmu.coupleGagnant);
      expect(codeApiPourTypePmu(tc.typePmu!), 'E_COUPLE_GAGNANT');
    });

    test('Simple Gagnant et Simple Placé restent distincts', () {
      expect(_tc('Simple Gagnant').typePmu, TypePariPmu.simpleGagnant);
      expect(_tc('Simple Placé').typePmu, TypePariPmu.simplePlace);
      expect(_tc('Simple Gagnant').typePmu,
          isNot(_tc('Simple Placé').typePmu));
    });

    test('UserPrediction suit les mêmes règles de non-assimilation', () {
      expect(_up('Tiercé').typePmu, TypePariPmu.tierce);
      expect(_up('Tiercé').typePmu, isNot(TypePariPmu.trio));
      expect(_up('Quarté+').typePmu, TypePariPmu.quartePlus);
      expect(_up('Quarté+').typePmu, isNot(TypePariPmu.superQuatre));
      expect(_up('Quinté+').typePmu, TypePariPmu.quintePlus);
      expect(_up('Quinté+').typePmu, isNot(TypePariPmu.multi));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E2/3 — refus du défaut : un type absent, vide ou inconnu reste '
      'NON RÉSOLU', () {
    test('un type vide n\'est jamais supposé Simple Gagnant', () {
      final tc = _tc('');
      expect(tc.typePmu, isNull,
          reason: 'un type vide ne doit produire AUCUN type canonique');
      expect(tc.typePmu, isNot(TypePariPmu.simpleGagnant));
      expect(tc.typePariReconnu, isFalse);
      expect(tc.typePariNonResolu, isTrue);
    });

    test('un type inconnu n\'est jamais supposé Simple Gagnant', () {
      for (final lib in [
        'Toto',
        'Tous',
        'inconnu xyz',
        'Tierce sans accent',
        '12345',
        'Multi',
        'Mini Multi',
      ]) {
        final tc = _tc(lib);
        expect(tc.typePmu, isNull, reason: '« $lib » ne doit pas être résolu');
        expect(tc.typePmu, isNot(TypePariPmu.simpleGagnant), reason: lib);
        expect(tc.typePariNonResolu, isTrue, reason: lib);
      }
    });

    test('UserPrediction : type vide relu depuis un JSON sans clé', () {
      // Mesure du comportement RÉEL de fromJson : `?? ''` pour ce modèle.
      final up = UserPrediction.fromJson({
        'id': 'p1',
        'dateStr': '21112026',
        'numReunion': 1,
        'numCourse': 3,
        'nomCourse': 'Prix',
        'hippodrome': 'VINCENNES',
        'numeroCheval': 1,
        'nomCheval': 'X',
        'cote': 2.0,
        'createdAt': '2026-11-21T13:00:00.000',
        // 'typePari' volontairement ABSENT de la clé
      });
      expect(up.typePari, '', reason: 'fromJson applique ?? \'\' — inchangé');
      expect(up.typePmu, isNull);
      expect(up.typePmu, isNot(TypePariPmu.simpleGagnant));
      expect(up.typePariNonResolu, isTrue);
    });

    test('Gagnant+Placé est hors référentiel, jamais « non résolu »', () {
      // Distinction explicite : ce n'est pas une donnée corrompue, c'est un
      // ticket à deux composantes.
      for (final lib in ['Gagnant+Placé', 'Gagnant + Placé', 'Gagnant+Place']) {
        final tc = _tc(lib);
        expect(tc.typePmu, isNull, reason: lib);
        expect(tc.typePariHorsReferentielPmu, isTrue, reason: lib);
        expect(tc.typePariNonResolu, isFalse,
            reason: '$lib est connu, mais hors référentiel PMU');
      }
    });

    test('un type reconnu n\'est jamais marqué non résolu', () {
      for (final lib in [
        'Simple Gagnant',
        'Simple Placé',
        'Couplé Gagnant',
        'Tiercé',
        'Quarté+',
        'Quinté+',
      ]) {
        final tc = _tc(lib);
        expect(tc.typePariReconnu, isTrue, reason: lib);
        expect(tc.typePariNonResolu, isFalse, reason: lib);
        expect(tc.typePariHorsReferentielPmu, isFalse, reason: lib);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E2/4 — compatibilité des anciens tickets et de leurs identifiants',
      () {
    test('storageKey et champs d\'un ancien ticket survivent à la lecture', () {
      final tc = _tc('Quinté+', storageKey: 'R1C3_21112026_1732000000');
      expect(tc.storageKey, 'R1C3_21112026_1732000000');
      expect(tc.numerosJoues, [7, 4, 2]);
      expect(tc.miseEngagee, 10.0);
      // Lecture du type : aucun effet sur les autres champs.
      expect(tc.typePmu, TypePariPmu.quintePlus);
      expect(tc.storageKey, 'R1C3_21112026_1732000000');
      expect(tc.numerosJoues, [7, 4, 2]);
      expect(tc.miseEngagee, 10.0);
    });

    test('aller-retour JSON d\'un ancien ticket : typePari et clés intacts',
        () {
      final origine = _tc('Tiercé', storageKey: 'R2C5_08112026_900');
      final json = origine.toJson();
      final relu = TrackedCourse.fromJson(json);
      expect(relu.typePari, 'Tiercé');
      expect(relu.storageKey, origine.storageKey);
      expect(relu.typePmu, TypePariPmu.tierce);
      expect(relu.numerosJoues, origine.numerosJoues);
      expect(relu.miseEngagee, origine.miseEngagee);
      // Le second aller-retour est stable : aucune dérive.
      final relu2 = TrackedCourse.fromJson(relu.toJson());
      expect(relu2.typePari, 'Tiercé');
      expect(relu2.toJson().length, json.length);
    });

    test('un ancien ticket sans clés B1/B2 relu correctement', () {
      // JSON d'avant les lots B1/B2-C : ni miseGagnant, ni cotePlace, etc.
      final relu = TrackedCourse.fromJson({
        'numReunion': 1,
        'numCourse': 3,
        'nomCourse': 'Ancien',
        'hippodrome': 'VINCENNES',
        'heureDepart': '2026-11-21T14:30:00.000',
        'typePari': 'Quarté+',
        'numerosJoues': [1, 2, 3, 4],
        'miseEngagee': 5.0,
      });
      expect(relu.typePari, 'Quarté+');
      expect(relu.typePmu, TypePariPmu.quartePlus);
      expect(relu.storageKey, isNull);
      expect(relu.miseGagnant, isNull);
      expect(relu.misePlace, isNull);
      // Le contrat B1 reste intact : deux mises nulles → miseEngagee.
      expect(relu.miseTotaleEngagee, 5.0);
    });

    test('UserPrediction : aller-retour JSON conserve typePari et id', () {
      final origine = _up('Couplé Placé');
      final relu = UserPrediction.fromJson(origine.toJson());
      expect(relu.id, 'pred-1');
      expect(relu.typePari, 'Couplé Placé');
      expect(relu.typePmu, TypePariPmu.couplePlace);
      expect(relu.numerosJoues, origine.numerosJoues);
    });

    test('les copies de TrackedCourse propagent le typePari et la lecture',
        () {
      final origine = _tc('Quinté+', storageKey: 'R1C3_21112026_1');
      final avecResultat = origine.withResultat(
        isGagne: false,
        arrivee: const [1, 2, 3, 4, 5],
        message: 'Perdu',
      );
      expect(avecResultat.typePari, 'Quinté+');
      expect(avecResultat.typePmu, TypePariPmu.quintePlus);
      expect(avecResultat.storageKey, origine.storageKey);

      final avecDividende = origine.withDividende(
        dividende: 12.5,
        combinaison: '7-4-2-1-3',
      );
      expect(avecDividende.typePari, 'Quinté+');
      expect(avecDividende.typePmu, TypePariPmu.quintePlus);
      expect(avecDividende.storageKey, origine.storageKey);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E2/5 — aucune écriture financière déclenchée par la lecture', () {
    test('lire le type ne modifie ni isCorrect ni le gain', () {
      final up = _up('Tiercé');
      final isCorrectAvant = up.isCorrect;
      final gainAvant = up.gainNet;
      final retourAvant = up.retourTotal;
      // ignore: unnecessary_statements
      up.typePmu;
      // ignore: unnecessary_statements
      up.typePariReconnu;
      expect(up.isCorrect, isCorrectAvant);
      expect(up.gainNet, gainAvant);
      expect(up.retourTotal, retourAvant);
    });

    test('lire le type ne modifie ni isGagne ni le dividende', () {
      final tc = _tc('Quarté+');
      final isGagneAvant = tc.isGagne;
      final divAvant = tc.dividendePmuReel;
      // ignore: unnecessary_statements
      tc.typePmu;
      expect(tc.isGagne, isGagneAvant);
      expect(tc.dividendePmuReel, divAvant);
    });

    test('estPariCombine reste inchangé (comportement historique préservé)',
        () {
      // Ce getter n'est PAS modifié à l'étape 2. On documente son périmètre
      // actuel, y compris son angle mort sur Trio/Super4/Multi.
      expect(_up('Tiercé').estPariCombine, isTrue);
      expect(_up('Quarté+').estPariCombine, isTrue);
      expect(_up('Quinté+').estPariCombine, isTrue);
      expect(_up('Simple Gagnant').estPariCombine, isFalse);
      // Angle mort assumé, hors périmètre de l'étape 2 :
      expect(_up('Trio').estPariCombine, isFalse,
          reason: 'angle mort documenté, non corrigé ici');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('E2/6 — cohérence avec le référentiel de l\'étape 1', () {
    test('les getters délèguent exactement au référentiel', () {
      for (final lib in [
        'Simple Gagnant',
        'Simple Placé',
        'Couplé Gagnant',
        'Couplé Placé',
        'Couplé Ordre',
        'Couplé Désordre',
        'Tiercé',
        'Tiercé Ordre',
        'Tiercé Désordre',
        'Quarté+',
        'Quinté+',
        'inconnu',
        '',
      ]) {
        expect(_tc(lib).typePmu, typePmuDepuisLibelleHistorique(lib),
            reason: lib);
        expect(_up(lib).typePmu, typePmuDepuisLibelleHistorique(lib),
            reason: lib);
      }
    });

    test('aucun libellé historique ne produit un code hors référentiel', () {
      final codesValides =
          TypePariPmu.values.map(codeApiPourTypePmu).whereType<String>().toSet();
      for (final lib in [
        'Simple Gagnant',
        'Simple Placé',
        'Couplé Gagnant',
        'Couplé Placé',
        'Couplé Ordre',
        'Couplé Désordre',
        'Tiercé',
        'Tiercé Ordre',
        'Tiercé Désordre',
        'Quarté+',
        'Quinté+',
      ]) {
        final t = _tc(lib).typePmu;
        expect(t, isNotNull, reason: lib);
        expect(codesValides.contains(codeApiPourTypePmu(t!)), isTrue,
            reason: lib);
      }
    });

    test('les tailles lues sont cohérentes avec les libellés', () {
      expect(tailleCombinaisonGagnante(_tc('Tiercé').typePmu!), 3);
      expect(tailleCombinaisonGagnante(_tc('Quarté+').typePmu!), 4);
      expect(tailleCombinaisonGagnante(_tc('Quinté+').typePmu!), 5);
      expect(tailleCombinaisonGagnante(_tc('Couplé Placé').typePmu!), 2);
      expect(tailleCombinaisonGagnante(_tc('Simple Gagnant').typePmu!), 1);
    });

    test('aucune lecture ne lève, quel que soit le libellé', () {
      for (final lib in ['', ' ', '?', 'é' * 300, 'NP', '0', '\n\t']) {
        expect(() => _tc(lib).typePmu, returnsNormally);
        expect(() => _tc(lib).typePariReconnu, returnsNormally);
        expect(() => _tc(lib).typePariNonResolu, returnsNormally);
        expect(() => _up(lib).typePmu, returnsNormally);
      }
    });
  });
}
