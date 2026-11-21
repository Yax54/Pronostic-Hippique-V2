// ═══════════════════════════════════════════════════════════════════════════
//  ÉTAPE 4-F / ÉTAPE 1 — MODÈLES ET PROPAGATION DANS LES RECONSTRUCTIONS
//
//  Ce fichier ne teste QUE l'étape 1 du lot 4-F :
//    • les quatre champs facultatifs existent sur les DEUX modèles ;
//    • ils survivent à `toJson` → `fromJson` (aller-retour) ;
//    • ils survivent aux TROIS reconstructions de `TrackedCourse`
//      (`ajouterSuivi`, `withResultat`, `withDividende`) ;
//    • les anciens tickets restent lisibles, sans valeur inventée ;
//    • `numerosJoues` et `typePari` gardent leur signification historique.
//
//  Ce qui n'est PAS testé ici (étapes 2 à 4) : la capture depuis les
//  sélecteurs. À l'étape 1, tous les champs valent `null` à la création ;
//  c'est l'état ATTENDU et les tests le vérifient explicitement.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Fabriques
// ───────────────────────────────────────────────────────────────────────────

UserPrediction _up({
  String typePari = 'Tiercé Ordre',
  List<int> numerosJoues = const [1, 3, 5],
  String? codePmuOfficiel,
  String? varianteChoisie,
  List<int>? numerosDansOrdre,
  String? formulePari,
}) =>
    UserPrediction(
      id: 'p1',
      dateStr: '2026-11-21',
      numReunion: 1,
      numCourse: 1,
      nomCourse: 'Prix de test',
      hippodrome: 'Vincennes',
      numeroCheval: 3,
      nomCheval: 'Cheval 3',
      cote: 4.2,
      typePari: typePari,
      createdAt: DateTime(2026, 11, 21, 14, 30),
      montantMise: 10.0,
      numerosJoues: numerosJoues,
      codePmuOfficiel: codePmuOfficiel,
      varianteChoisie: varianteChoisie,
      numerosDansOrdre: numerosDansOrdre,
      formulePari: formulePari,
    );

TrackedCourse _tc({
  String typePari = 'Tiercé Ordre',
  List<int> numerosJoues = const [1, 3, 5],
  String? codePmuOfficiel,
  String? varianteChoisie,
  List<int>? numerosDansOrdre,
  String? formulePari,
  String? storageKey = 'R1C1_21112026_1',
}) =>
    TrackedCourse(
      numReunion: 1,
      numCourse: 1,
      nomCourse: 'Prix de test',
      hippodrome: 'Vincennes',
      heureDepart: DateTime(2026, 11, 21, 14, 30),
      storageKey: storageKey,
      nomCheval: 'Cheval 3',
      numeroCheval: 3,
      miseEngagee: 10.0,
      typePari: typePari,
      numerosJoues: numerosJoues,
      codePmuOfficiel: codePmuOfficiel,
      varianteChoisie: varianteChoisie,
      numerosDansOrdre: numerosDansOrdre,
      formulePari: formulePari,
    );

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E1/1 — les quatre champs existent sur les deux modèles', () {
    test('UserPrediction expose les quatre champs, null par défaut', () {
      final up = _up();
      expect(up.codePmuOfficiel, isNull);
      expect(up.varianteChoisie, isNull);
      expect(up.numerosDansOrdre, isNull);
      expect(up.formulePari, isNull);
    });

    test('TrackedCourse expose les quatre champs, null par défaut', () {
      final tc = _tc();
      expect(tc.codePmuOfficiel, isNull);
      expect(tc.varianteChoisie, isNull);
      expect(tc.numerosDansOrdre, isNull);
      expect(tc.formulePari, isNull);
    });

    test('les champs portent bien la valeur fournie', () {
      final tc = _tc(
        codePmuOfficiel: 'E_TIERCE',
        varianteChoisie: 'ordre',
        numerosDansOrdre: const [3, 1, 5],
      );
      expect(tc.codePmuOfficiel, 'E_TIERCE');
      expect(tc.varianteChoisie, 'ordre');
      expect(tc.numerosDansOrdre, const [3, 1, 5]);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E1/2 — aller-retour JSON des deux modèles', () {
    test('TrackedCourse : les quatre champs survivent à toJson/fromJson', () {
      final origine = _tc(
        codePmuOfficiel: 'E_TIERCE',
        varianteChoisie: 'ordre',
        numerosDansOrdre: const [3, 1, 5],
      );
      final relu = TrackedCourse.fromJson(origine.toJson());

      expect(relu.codePmuOfficiel, 'E_TIERCE');
      expect(relu.varianteChoisie, 'ordre');
      expect(relu.numerosDansOrdre, const [3, 1, 5],
          reason: "l'ORDRE de saisie doit être conservé, pas retrié");
      expect(relu.formulePari, isNull);
    });

    test('UserPrediction : les quatre champs survivent à toJson/fromJson', () {
      final origine = _up(
        codePmuOfficiel: 'E_QUINTE_PLUS',
        numerosJoues: const [1, 3, 5, 7, 9],
      );
      final relu = UserPrediction.fromJson(origine.toJson());

      expect(relu.codePmuOfficiel, 'E_QUINTE_PLUS');
      // Quarté+/Quinté+ : AUCUNE variante choisie par le parieur.
      expect(relu.varianteChoisie, isNull,
          reason: "on n'invente jamais Ordre/Désordre pour un Quinté+");
      expect(relu.numerosDansOrdre, isNull,
          reason: "un Quinté+ n'exige pas d'ordre à la saisie");
      expect(relu.formulePari, isNull);
    });

    test('le JSON contient les quatre clés, même à null', () {
      final json = _tc().toJson();
      for (final cle in [
        'codePmuOfficiel',
        'varianteChoisie',
        'numerosDansOrdre',
        'formulePari',
      ]) {
        expect(json.containsKey(cle), isTrue,
            reason: 'clé absente du JSON : $cle');
      }
    });

    test('les getters dérivés ne sont JAMAIS persistés', () {
      final jsonT = _tc().toJson();
      final jsonU = _up().toJson();
      for (final interdit in ['capturePariComplete', 'typePmu', 'typePariReconnu']) {
        expect(jsonT.containsKey(interdit), isFalse, reason: 'TC: $interdit');
        expect(jsonU.containsKey(interdit), isFalse, reason: 'UP: $interdit');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E1/3 — numérosDansOrdre et numerosJoues ne divergent pas', () {
    test("le tri de numerosDansOrdre est égal à numerosJoues", () {
      final tc = _tc(
        numerosJoues: const [1, 3, 5],
        numerosDansOrdre: const [3, 1, 5],
      );
      final trie = List<int>.from(tc.numerosDansOrdre!)..sort();
      expect(trie, tc.numerosJoues);
    });

    test('un ordre saisi différent ne modifie pas numerosJoues', () {
      final a = _tc(numerosJoues: const [1, 3, 5], numerosDansOrdre: const [3, 1, 5]);
      final b = _tc(numerosJoues: const [1, 3, 5], numerosDansOrdre: const [5, 3, 1]);
      expect(a.numerosJoues, b.numerosJoues,
          reason: 'numerosJoues garde sa signification : ensemble, pas séquence');
      expect(a.numerosDansOrdre, isNot(b.numerosDansOrdre));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E1/4 — rétrocompatibilité : anciens tickets', () {
    test('TrackedCourse ancien (sans les 4 clés) se relit sans invention', () {
      final ancien = <String, dynamic>{
        'numReunion': 1,
        'numCourse': 1,
        'nomCourse': 'Ancienne course',
        'hippodrome': 'Vincennes',
        'heureDepart': '2026-11-21T14:30:00.000',
        'typePari': 'Tiercé',
        'numerosJoues': [1, 3, 5],
        'storageKey': 'R1C1_21112026_2',
      };
      final relu = TrackedCourse.fromJson(ancien);

      expect(relu.codePmuOfficiel, isNull);
      expect(relu.varianteChoisie, isNull,
          reason: "aucune variante n'est DEVINÉE pour un ancien ticket");
      expect(relu.numerosDansOrdre, isNull,
          reason: 'null = non capturé, jamais une liste vide inventée');
      expect(relu.formulePari, isNull);
      expect(relu.typePari, 'Tiercé', reason: 'typePari historique intact');
      expect(relu.numerosJoues, const [1, 3, 5]);
    });

    test('UserPrediction ancien (sans les 4 clés) se relit sans invention', () {
      final ancien = <String, dynamic>{
        'id': 'vieux',
        'dateStr': '2026-11-20',
        'numReunion': 2,
        'numCourse': 3,
        'nomCourse': 'Ancienne',
        'hippodrome': 'Deauville',
        'numeroCheval': 7,
        'nomCheval': 'Cheval 7',
        'cote': 5.0,
        'typePari': 'Quarté+',
        'createdAt': '2026-11-20T15:00:00.000',
        'numerosJoues': [2, 7, 4, 9],
      };
      final relu = UserPrediction.fromJson(ancien);

      expect(relu.codePmuOfficiel, isNull);
      expect(relu.varianteChoisie, isNull);
      expect(relu.numerosDansOrdre, isNull);
      expect(relu.formulePari, isNull);
      expect(relu.typePari, 'Quarté+');
    });

    test("un ancien ticket réécrit garde la même forme (28 clés)", () {
      final relu = TrackedCourse.fromJson(_tc(storageKey: 'K').toJson());
      expect(relu.toJson().length, 28);
      // Deuxième aller-retour : stable, aucune dérive.
      expect(TrackedCourse.fromJson(relu.toJson()).toJson().length, 28);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E1/5 — PROPAGATION dans les reconstructions de TrackedCourse',
      () {
    test('withResultat propage les quatre champs', () {
      final tc = _tc(
        codePmuOfficiel: 'E_TIERCE',
        varianteChoisie: 'ordre',
        numerosDansOrdre: const [3, 1, 5],
      );
      final copie = tc.withResultat(
        isGagne: true,
        arrivee: const [3, 1, 5],
        message: 'Gagné',
      );

      expect(copie.codePmuOfficiel, 'E_TIERCE');
      expect(copie.varianteChoisie, 'ordre');
      expect(copie.numerosDansOrdre, const [3, 1, 5],
          reason: "c'est le défaut exact de R1 sur storageKey, rejoué ici");
      expect(copie.formulePari, isNull);
      // Les champs historiques restent propagés.
      expect(copie.storageKey, tc.storageKey);
      expect(copie.typePari, tc.typePari);
      expect(copie.numerosJoues, tc.numerosJoues);
    });

    test('withDividende propage les quatre champs', () {
      final tc = _tc(
        codePmuOfficiel: 'E_QUINTE_PLUS',
        numerosJoues: const [1, 3, 5, 7, 9],
      );
      final copie = tc.withDividende(dividende: 51.2, combinaison: '3-1-5-7-9');

      expect(copie.codePmuOfficiel, 'E_QUINTE_PLUS');
      expect(copie.varianteChoisie, isNull);
      expect(copie.numerosDansOrdre, isNull);
      expect(copie.formulePari, isNull);
      expect(copie.storageKey, tc.storageKey);
      // Le dividende est bien celui demandé.
      expect(copie.dividendePmuReel, 51.2);
      expect(copie.combinaisonPmu, '3-1-5-7-9');
    });

    test('withResultat puis withDividende : capture intacte de bout en bout', () {
      final tc = _tc(
        codePmuOfficiel: 'E_TIERCE',
        varianteChoisie: 'desordre',
        numerosDansOrdre: const [5, 1, 3],
      );
      final apresResultat = tc.withResultat(
        isGagne: true,
        arrivee: const [5, 1, 3],
        message: 'Gagné',
      );
      final apresDividende =
          apresResultat.withDividende(dividende: 105.1, combinaison: '5-1-3');

      expect(apresDividende.codePmuOfficiel, 'E_TIERCE',
          reason: 'la capture survit à DEUX reconstructions successives');
      expect(apresDividende.varianteChoisie, 'desordre');
      expect(apresDividende.numerosDansOrdre, const [5, 1, 3]);
      expect(apresDividende.storageKey, tc.storageKey);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E1/6 — capturePariComplete ne devine rien', () {
    test('sans code PMU, la capture est incomplète', () {
      expect(_tc(typePari: 'Tiercé Ordre').capturePariComplete, isFalse);
    });

    test('Tiercé Ordre sans variante : incomplet', () {
      final tc = _tc(typePari: 'Tiercé Ordre', codePmuOfficiel: 'E_TIERCE');
      expect(tc.capturePariComplete, isFalse,
          reason: "le choix Ordre/Désordre est requis et n'a pas été capturé");
    });

    test('Tiercé Ordre avec variante : complet', () {
      final tc = _tc(
        typePari: 'Tiercé Ordre',
        codePmuOfficiel: 'E_TIERCE',
        varianteChoisie: 'ordre',
        // ★ R10 : `Tiercé Ordre` impose l'ordre exact (`exigeOrdreExact` rend
        //   vrai). Depuis R10, « complet » exige donc AUSSI que l'ordre ait
        //   été réellement capturé. Ce test ne fournissait que la variante :
        //   il validait donc un ticket incomplet. On fournit l'ordre — sans
        //   changer l'intention du test, qui reste « avec variante : complet ».
        numerosDansOrdre: const [1, 3, 5],
      );
      expect(tc.capturePariComplete, isTrue);
    });

    test('Quinté+ avec code, sans variante : complet (aucun choix requis)', () {
      final tc = _tc(
        typePari: 'Quinté+',
        numerosJoues: const [1, 3, 5, 7, 9],
        codePmuOfficiel: 'E_QUINTE_PLUS',
      );
      expect(tc.capturePariComplete, isTrue,
          reason: "au PMU le parieur Quinté+ ne choisit pas Ordre/Désordre");
    });

    test('Couplé Ordre exige la variante', () {
      final sans = _tc(
        typePari: 'Couplé Ordre',
        numerosJoues: const [1, 3],
        codePmuOfficiel: 'E_COUPLE_ORDRE',
      );
      expect(sans.capturePariComplete, isFalse);

      final avec = _tc(
        typePari: 'Couplé Ordre',
        numerosJoues: const [1, 3],
        codePmuOfficiel: 'E_COUPLE_ORDRE',
        varianteChoisie: 'ordre',
        // ★ R10 : `Couplé Ordre` impose l'ordre exact. Depuis R10, la variante
        //   seule ne suffit plus : l'ordre doit être présent ET désigner les
        //   mêmes deux chevaux que `numerosJoues`.
        numerosDansOrdre: const [3, 1],
      );
      expect(avec.capturePariComplete, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('4F-E1/7 — aucune régression sur les champs historiques', () {
    test('typePari et numerosJoues traversent toJson/fromJson inchangés', () {
      for (final t in ['Tiercé Ordre', 'Tiercé Désordre', 'Quarté+', 'Quinté+']) {
        final relu = TrackedCourse.fromJson(_tc(typePari: t).toJson());
        expect(relu.typePari, t, reason: 'typePari réécrit pour $t');
        expect(relu.numerosJoues, const [1, 3, 5]);
      }
    });

    test('les 24 clés historiques de TrackedCourse sont toujours écrites', () {
      final json = _tc().toJson();
      for (final cle in [
        'numReunion', 'numCourse', 'nomCourse', 'hippodrome', 'heureDepart',
        'nomCheval', 'numeroCheval', 'miseEngagee', 'miseGagnant', 'misePlace',
        'coteGagnant', 'cotePlace', 'addedAt', 'typePari', 'numerosJoues',
        'iaMemKey', 'scoreIA', 'cote', 'isGagne', 'arriveeFinale',
        'messageResultat', 'dividendePmuReel', 'combinaisonPmu', 'storageKey',
      ]) {
        expect(json.containsKey(cle), isTrue, reason: 'clé historique perdue : $cle');
      }
    });

    test('les 22 clés historiques de UserPrediction sont toujours écrites', () {
      final json = _up().toJson();
      for (final cle in [
        'id', 'dateStr', 'numReunion', 'numCourse', 'nomCourse', 'hippodrome',
        'numeroCheval', 'nomCheval', 'cote', 'typePari', 'createdAt', 'isCorrect',
        'scoreIA', 'montantMise', 'gainRealise', 'numerosJoues',
        'dividendePmuReel', 'combinaisonPmu', 'miseGagnant', 'misePlace',
        'coteGagnant', 'cotePlace',
      ]) {
        expect(json.containsKey(cle), isTrue, reason: 'clé historique perdue : $cle');
      }
      expect(json.length, 26, reason: '22 historiques + 4 de capture');
    });

    test('le JSON reste encodable et décodable', () {
      final tc = _tc(
        codePmuOfficiel: 'E_TIERCE',
        varianteChoisie: 'ordre',
        numerosDansOrdre: const [3, 1, 5],
      );
      final encode = jsonEncode(tc.toJson());
      final decode = jsonDecode(encode) as Map<String, dynamic>;
      final relu = TrackedCourse.fromJson(decode);
      expect(relu.numerosDansOrdre, const [3, 1, 5]);
      expect(relu.varianteChoisie, 'ordre');
    });
  });
}
