// ═══════════════════════════════════════════════════════════════════════════
//  LOT B-1 — CHAMPS PERSISTÉS SUR LES DEUX MODÈLES JUMELLES
//
//  Ces tests vérifient SEPT exigences, dans l'ordre où elles ont été formulées :
//    1. la sérialisation / désérialisation JSON des nouveaux champs ;
//    2. la propagation dans TOUTES les reconstructions de `TrackedCourse` ;
//    3. la conservation EXACTE des données historiques ;
//    4. l'absence de recalcul rétroactif ;
//    5. la compatibilité des sauvegardes et restaurations ;
//    6. le maintien de la baseline (7 échecs préexistants, aucun nouveau) ;
//    7. la non-divergence des deux modèles jumeaux.
//
//  Le test le plus important de ce fichier est celui du NOMBRE DE CLÉS : c'est
//  lui qui prouve qu'un ticket historique relu puis réécrit garde sa forme.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/models/pmu_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/gain_pmu_types.dart'
    show
        EtatGain,
        EtatTirelire,
        MotifNonDetermination,
        RapportAttribue,
        RapportPublie;
import 'package:pronostic_hippique/services/gain_ticket_calculator.dart'
    show VarianteRapport;

// ─── Fabriques ──────────────────────────────────────────────────────────────

UserPrediction _up({
  String typePari = 'Simple Gagnant',
  String? codePmuOfficiel,
  EtatGain? etatGain,
  List<RapportAttribue>? rapportsAttribues,
  EtatTirelire? etatTirelire,
  double? dividendeGagnant,
  double? dividendePlace,
  int? miseBaseCentimesUtilisee,
  MotifNonDetermination? motifNonDetermination,
}) {
  return UserPrediction(
    id: 'up1',
    dateStr: '2026-11-15',
    numReunion: 1,
    numCourse: 6,
    nomCourse: 'Prix Test',
    hippodrome: 'Vincennes',
    numeroCheval: 9,
    nomCheval: 'Cheval 9',
    cote: 6.5,
    typePari: typePari,
    createdAt: DateTime(2026, 11, 15, 14, 30),
    montantMise: 2.0,
    numerosJoues: const [9],
    codePmuOfficiel: codePmuOfficiel,
    etatGain: etatGain,
    rapportsAttribues: rapportsAttribues,
    etatTirelire: etatTirelire,
    dividendeGagnant: dividendeGagnant,
    dividendePlace: dividendePlace,
    miseBaseCentimesUtilisee: miseBaseCentimesUtilisee,
    motifNonDetermination: motifNonDetermination,
  );
}

TrackedCourse _tc({
  String typePari = 'Simple Gagnant',
  String? codePmuOfficiel,
  EtatGain? etatGain,
  List<RapportAttribue>? rapportsAttribues,
  EtatTirelire? etatTirelire,
  double? dividendeGagnant,
  double? dividendePlace,
  int? miseBaseCentimesUtilisee,
  MotifNonDetermination? motifNonDetermination,
  double? dividendePmuReel,
}) {
  return TrackedCourse(
    numReunion: 1,
    numCourse: 6,
    nomCourse: 'Prix Test',
    hippodrome: 'Vincennes',
    heureDepart: DateTime(2026, 11, 15, 14, 30),
    nomCheval: 'Cheval 9',
    numeroCheval: 9,
    miseEngagee: 2.0,
    typePari: typePari,
    numerosJoues: const [9],
    cote: 6.5,
    storageKey: 'R1C6_15112026',
    codePmuOfficiel: codePmuOfficiel,
    dividendePmuReel: dividendePmuReel,
    etatGain: etatGain,
    rapportsAttribues: rapportsAttribues,
    etatTirelire: etatTirelire,
    dividendeGagnant: dividendeGagnant,
    dividendePlace: dividendePlace,
    miseBaseCentimesUtilisee: miseBaseCentimesUtilisee,
    motifNonDetermination: motifNonDetermination,
  );
}

/// Rapport publié réaliste (mesures R1C6 du 15/11/2026).
RapportPublie _pub({
  String libelle = 'e-Quinté+ Ordre',
  VarianteRapport variante = VarianteRapport.ordre,
  String combinaison = '9-4-15-10-1',
  double? pourUnEuro = 6462670.0,
  int? rang = 1,
}) =>
    RapportPublie(
      codePmu: 'E_QUINTE_PLUS',
      libelle: libelle,
      variante: variante,
      combinaison: combinaison,
      pourUnEuro: pourUnEuro,
      rang: rang,
      miseBaseCentimes: 200,
    );

RapportAttribue _attr({double miseAppliquee = 2.0}) => RapportAttribue.calculer(
      rapport: _pub(),
      miseAppliquee: miseAppliquee,
    );

void main() {
  // ═════════════════════════════════════════════════════════════════════════
  //  B1/1 — LES SEPT CHAMPS EXISTENT, NULL PAR DÉFAUT
  // ═════════════════════════════════════════════════════════════════════════
  group('B1/1 — les sept champs existent sur les deux modèles', () {
    test('UserPrediction : tous null par défaut', () {
      final p = _up();
      expect(p.etatGain, isNull);
      expect(p.rapportsAttribues, isNull);
      expect(p.etatTirelire, isNull);
      expect(p.dividendeGagnant, isNull);
      expect(p.dividendePlace, isNull);
      expect(p.miseBaseCentimesUtilisee, isNull);
      expect(p.motifNonDetermination, isNull);
    });

    test('TrackedCourse : tous null par défaut', () {
      final t = _tc();
      expect(t.etatGain, isNull);
      expect(t.rapportsAttribues, isNull);
      expect(t.etatTirelire, isNull);
      expect(t.dividendeGagnant, isNull);
      expect(t.dividendePlace, isNull);
      expect(t.miseBaseCentimesUtilisee, isNull);
      expect(t.motifNonDetermination, isNull);
    });

    test('les champs portent bien la valeur fournie', () {
      final p = _up(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[_attr()],
        etatTirelire: EtatTirelire.incluse,
        dividendeGagnant: 7.2,
        dividendePlace: 2.9,
        miseBaseCentimesUtilisee: 200,
        motifNonDetermination: MotifNonDetermination.rapportAmbigu,
      );
      expect(p.etatGain, EtatGain.attribue);
      expect(p.rapportsAttribues, hasLength(1));
      expect(p.etatTirelire, EtatTirelire.incluse);
      expect(p.dividendeGagnant, 7.2);
      expect(p.dividendePlace, 2.9);
      expect(p.miseBaseCentimesUtilisee, 200);
      expect(p.motifNonDetermination, MotifNonDetermination.rapportAmbigu);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1/2 — LE VERROU DE FORME : 26 / 28 CLÉS EXACTEMENT
  //
  //  C'est LE test de ce lot. Il prouve qu'un ticket historique relu puis
  //  réécrit garde SA forme d'origine, et que l'écriture conditionnelle
  //  fonctionne : un ticket résolu, lui, gagne ses clés.
  // ═════════════════════════════════════════════════════════════════════════
  group('B1/2 — forme des sauvegardes préservée', () {
    test('UserPrediction historique : 26 clés, avant ET après relecture', () {
      final json = _up().toJson();
      expect(json.length, 26, reason: '22 historiques + 4 de capture');

      final relu = UserPrediction.fromJson(json);
      expect(relu.toJson().length, 26,
          reason: 'relire puis réécrire ne doit RIEN ajouter');

      // Aucune des sept clés de gain ne doit apparaître.
      for (final cle in <String>[
        'etatGain',
        'rapportsAttribues',
        'etatTirelire',
        'dividendeGagnant',
        'dividendePlace',
        'miseBaseCentimesUtilisee',
        'motifNonDetermination',
      ]) {
        expect(json.containsKey(cle), isFalse,
            reason: 'un ticket historique ne doit pas porter « $cle »');
      }
    });

    test('TrackedCourse historique : 28 clés, avant ET après relecture', () {
      final json = _tc().toJson();
      expect(json.length, 28);

      final relu = TrackedCourse.fromJson(json);
      expect(relu.toJson().length, 28);

      // Deuxième aller-retour : stable, aucune dérive cumulative.
      final relu2 = TrackedCourse.fromJson(relu.toJson());
      expect(relu2.toJson().length, 28);
    });

    test('un ticket RÉSOLU porte bien ses sept clés en plus', () {
      final json = _tc(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[_attr()],
        etatTirelire: EtatTirelire.incluse,
        dividendeGagnant: 7.2,
        dividendePlace: 2.9,
        miseBaseCentimesUtilisee: 200,
      ).toJson();

      expect(json.length, 35, reason: '28 + 7');
      expect(json.containsKey('etatGain'), isTrue);
      expect(json.containsKey('rapportsAttribues'), isTrue);
    });

    test('un ticket non résolu mais avec motif reste à 28 clés', () {
      // `etatGain == null` est la condition d'écriture : un motif seul ne
      // suffit pas à basculer un ticket historique dans le nouveau format.
      final t = _tc(motifNonDetermination: MotifNonDetermination.captureIncomplete);
      expect(t.toJson().length, 28);
      expect(t.toJson().containsKey('motifNonDetermination'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1/3 — ALLER-RETOUR JSON DES SEPT CHAMPS
  // ═════════════════════════════════════════════════════════════════════════
  group('B1/3 — aller-retour JSON', () {
    test('TrackedCourse : les sept champs survivent', () {
      final avant = _tc(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[_attr(miseAppliquee: 3.0)],
        etatTirelire: EtatTirelire.nonDeterminee,
        dividendeGagnant: 7.2,
        dividendePlace: 2.9,
        miseBaseCentimesUtilisee: 200,
        motifNonDetermination: MotifNonDetermination.tirelireNonDeterminee,
      );
      final apres = TrackedCourse.fromJson(avant.toJson());

      expect(apres.etatGain, EtatGain.attribue);
      expect(apres.rapportsAttribues, hasLength(1));
      expect(apres.rapportsAttribues!.single.miseAppliquee, 3.0);
      expect(apres.etatTirelire, EtatTirelire.nonDeterminee);
      expect(apres.dividendeGagnant, 7.2);
      expect(apres.dividendePlace, 2.9);
      expect(apres.miseBaseCentimesUtilisee, 200);
      expect(apres.motifNonDetermination,
          MotifNonDetermination.tirelireNonDeterminee);
    });

    test('UserPrediction : les sept champs survivent', () {
      final avant = _up(
        etatGain: EtatGain.perdu,
        etatTirelire: EtatTirelire.sansObjet,
        miseBaseCentimesUtilisee: 150,
      );
      final apres = UserPrediction.fromJson(avant.toJson());

      expect(apres.etatGain, EtatGain.perdu);
      expect(apres.etatTirelire, EtatTirelire.sansObjet);
      expect(apres.miseBaseCentimesUtilisee, 150);
    });

    test('le montant d\'un RapportAttribue survit à l\'aller-retour', () {
      final avant = _attr(miseAppliquee: 2.0);
      final apres = TrackedCourse.fromJson(
          _tc(etatGain: EtatGain.attribue, rapportsAttribues: <RapportAttribue>[avant]).toJson());

      // 2 € × 6 462 670 €/€ — le montant ne doit pas être recalculé ni perdu.
      expect(apres.rapportsAttribues!.single.montantRetour,
          closeTo(12925340.0, 1.0));
      expect(apres.rapportsAttribues!.single.rapport.libelle,
          'e-Quinté+ Ordre');
      expect(apres.rapportsAttribues!.single.variante, VarianteRapport.ordre);
    });

    test('le JSON reste encodable et décodable par dart:convert', () {
      final t = _tc(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[_attr()],
      );
      final decode = jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>;
      final relu = TrackedCourse.fromJson(decode);
      expect(relu.etatGain, EtatGain.attribue);
      expect(relu.rapportsAttribues, hasLength(1));
    });

    test('une valeur d\'état inconnue ne produit aucun état deviné', () {
      final json = _tc(etatGain: EtatGain.attribue).toJson();
      json['etatGain'] = 'etatFuturInconnu';
      expect(TrackedCourse.fromJson(json).etatGain, isNull,
          reason: 'aucun repli sur un état par défaut');
    });

    test('une liste de rapports illisible ne fabrique aucun rapport', () {
      final json = _tc(etatGain: EtatGain.attribue).toJson();
      json['rapportsAttribues'] = <dynamic>[
        <String, dynamic>{'pasDeCleRapport': true},
        'pasUnMap',
      ];
      final relu = TrackedCourse.fromJson(json);
      expect(relu.rapportsAttribues, isNull,
          reason: '« non résolu » plutôt qu\'une liste fabriquée');
    });

    test('« résolu sans rapport » et « non résolu » restent distincts', () {
      // Une liste vide à l'écriture devient `null` à la relecture : on ne peut
      // donc PAS affirmer une résolution sans rapport. C'est le choix assumé.
      final t = _tc(etatGain: EtatGain.nonDetermine, rapportsAttribues: const []);
      final relu = TrackedCourse.fromJson(t.toJson());
      expect(relu.rapportsAttribues, isNull);
      // Mais l'ÉTAT, lui, est bien conservé.
      expect(relu.etatGain, EtatGain.nonDetermine);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1/4 — PROPAGATION DANS LES RECONSTRUCTIONS
  // ═════════════════════════════════════════════════════════════════════════
  group('B1/4 — propagation dans les reconstructions', () {
    test('withResultat propage les sept champs', () {
      final t = _tc(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[_attr()],
        etatTirelire: EtatTirelire.incluse,
        dividendeGagnant: 7.2,
        dividendePlace: 2.9,
        miseBaseCentimesUtilisee: 200,
      );
      final copie = t.withResultat(
        isGagne: true,
        arrivee: const [9, 4, 15, 10, 1],
        message: 'ok',
      );

      expect(copie.etatGain, EtatGain.attribue);
      expect(copie.rapportsAttribues, hasLength(1));
      expect(copie.etatTirelire, EtatTirelire.incluse);
      expect(copie.dividendeGagnant, 7.2);
      expect(copie.dividendePlace, 2.9);
      expect(copie.miseBaseCentimesUtilisee, 200);
    });

    test('withDividende propage les sept champs', () {
      final t = _tc(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[_attr()],
        etatTirelire: EtatTirelire.nonDeterminee,
        miseBaseCentimesUtilisee: 150,
        motifNonDetermination: MotifNonDetermination.tirelireNonDeterminee,
      );
      final copie = t.withDividende(dividende: 8.03, combinaison: '9-4-15');

      expect(copie.etatGain, EtatGain.attribue);
      expect(copie.rapportsAttribues, hasLength(1));
      expect(copie.etatTirelire, EtatTirelire.nonDeterminee);
      expect(copie.miseBaseCentimesUtilisee, 150);
      expect(copie.motifNonDetermination,
          MotifNonDetermination.tirelireNonDeterminee);
    });

    test('withResultat puis withDividende : gains intacts de bout en bout', () {
      final t = _tc(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[_attr(miseAppliquee: 5.0)],
      );
      final copie = t
          .withResultat(isGagne: true, arrivee: const [9], message: 'ok')
          .withDividende(dividende: 1.0, combinaison: '9');

      expect(copie.rapportsAttribues!.single.miseAppliquee, 5.0);
      expect(copie.etatGain, EtatGain.attribue);
    });

    test('les quatre champs de capture 4-F survivent aussi (non-régression)', () {
      final t = TrackedCourse(
        numReunion: 1,
        numCourse: 6,
        nomCourse: 'P',
        hippodrome: 'V',
        heureDepart: DateTime(2026, 11, 15),
        nomCheval: 'C',
        numeroCheval: 9,
        typePari: 'Tiercé',
        numerosJoues: const [9, 4, 15],
        codePmuOfficiel: 'E_TIERCE',
        numerosDansOrdre: const [9, 4, 15],
      );
      final copie = t.withResultat(isGagne: true, arrivee: const [9], message: '');
      expect(copie.codePmuOfficiel, 'E_TIERCE');
      expect(copie.numerosDansOrdre, const [9, 4, 15]);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1/5 — AUCUN RECALCUL RÉTROACTIF
  //
  //  Un ticket historique doit conserver EXACTEMENT son gain d'origine. Le
  //  nouveau moteur ne doit produire aucune écriture sur lui.
  // ═════════════════════════════════════════════════════════════════════════
  group('B1/5 — aucun recalcul rétroactif', () {
    test('un ticket historique conserve son gainNet d\'origine', () {
      final t = TrackedCourse(
        numReunion: 1,
        numCourse: 6,
        nomCourse: 'P',
        hippodrome: 'V',
        heureDepart: DateTime(2026, 11, 15),
        nomCheval: 'C',
        numeroCheval: 9,
        miseEngagee: 2.0,
        typePari: 'Simple Gagnant',
        isGagne: true,
        dividendePmuReel: 7.5,
      );
      // Aucun état de gain structuré : le chemin legacy s'applique seul.
      expect(t.etatGain, isNull);
      expect(t.dividendePmuReel, 7.5);
      // Le dividende historique n'est ni effacé ni remplacé.
      final relu = TrackedCourse.fromJson(t.toJson());
      expect(relu.dividendePmuReel, 7.5);
      expect(relu.etatGain, isNull);
    });

    test('un ticket historique relu 3 fois garde la même valeur', () {
      var json = TrackedCourse(
        numReunion: 2,
        numCourse: 3,
        nomCourse: 'P',
        hippodrome: 'V',
        heureDepart: DateTime(2026, 11, 16),
        nomCheval: 'C',
        numeroCheval: 5,
        miseEngagee: 10.0,
        typePari: 'Simple Placé',
        isGagne: true,
        dividendePmuReel: 3.4,
      ).toJson();

      for (var i = 0; i < 3; i++) {
        json = TrackedCourse.fromJson(json).toJson();
      }
      expect(json['dividendePmuReel'], 3.4);
      expect(json.length, 28, reason: 'aucune clé ajoutée par les relectures');
    });

    test('le nouveau moteur n\'écrit rien quand etatGain est null', () {
      // Preuve structurelle : sans `etatGain`, aucune clé de gain n'existe
      // dans le JSON, donc aucun consommateur ne peut lire un gain structuré.
      final json = _tc(dividendePmuReel: 5.0).toJson();
      expect(json['etatGain'], isNull);
      expect(json['rapportsAttribues'], isNull);
      expect(json['dividendeGagnant'], isNull);
      expect(json['dividendePlace'], isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1/6 — COMPATIBILITÉ DES SAUVEGARDES
  // ═════════════════════════════════════════════════════════════════════════
  group('B1/6 — sauvegarde et restauration', () {
    test('une sauvegarde ancienne SANS les sept clés se restaure sans invention', () {
      // Reproduit exactement ce que contiendrait un `StringList` d'avant B-1.
      const ancien = <String, dynamic>{
        'numReunion': 1,
        'numCourse': 6,
        'nomCourse': 'P',
        'hippodrome': 'V',
        'heureDepart': '2026-11-15T14:30:00.000',
        'nomCheval': 'C',
        'numeroCheval': 9,
        'miseEngagee': 2.0,
        'typePari': 'Simple Gagnant',
        'numerosJoues': <int>[9],
        'cote': 6.5,
        'isGagne': true,
        'dividendePmuReel': 7.5,
        'storageKey': 'R1C6_15112026',
      };

      final relu = TrackedCourse.fromJson(Map<String, dynamic>.from(ancien));

      expect(relu.etatGain, isNull);
      expect(relu.rapportsAttribues, isNull);
      expect(relu.etatTirelire, isNull);
      expect(relu.dividendeGagnant, isNull);
      expect(relu.dividendePlace, isNull);
      expect(relu.miseBaseCentimesUtilisee, isNull);
      expect(relu.motifNonDetermination, isNull);
      // Et surtout : le gain historique est INTACT.
      expect(relu.dividendePmuReel, 7.5);
      expect(relu.isGagne, isTrue);
    });

    test('une sauvegarde restaurée puis réécrite garde 28 clés', () {
      const ancien = <String, dynamic>{
        'numReunion': 1,
        'numCourse': 6,
        'nomCourse': 'P',
        'hippodrome': 'V',
        'heureDepart': '2026-11-15T14:30:00.000',
        'nomCheval': 'C',
        'numeroCheval': 9,
        'typePari': 'Simple Gagnant',
        'storageKey': 'R1C6_15112026',
      };
      final relu = TrackedCourse.fromJson(Map<String, dynamic>.from(ancien));
      expect(relu.toJson().length, 28,
          reason: 'la restauration ne doit pas gonfler la forme');
    });

    test('aucun champ de gain n\'est persisté comme getter dérivé', () {
      // `miseTotaleEngagee` est un getter : il ne doit jamais apparaître.
      final json = _tc(etatGain: EtatGain.attribue).toJson();
      expect(json.containsKey('miseTotaleEngagee'), isFalse);
      expect(json.containsKey('misesGagnantPlaceIncompletes'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1/7 — LES DEUX MODÈLES JUMEAUX NE DIVERGENT PAS
  // ═════════════════════════════════════════════════════════════════════════
  group('B1/7 — non-divergence des modèles jumeaux', () {
    test('mêmes noms de clés de gain de part et d\'autre', () {
      final clesUp = _up(etatGain: EtatGain.attribue).toJson().keys.toSet();
      final clesTc = _tc(etatGain: EtatGain.attribue).toJson().keys.toSet();

      const attendues = <String>{
        'etatGain',
        'rapportsAttribues',
        'etatTirelire',
        'dividendeGagnant',
        'dividendePlace',
        'miseBaseCentimesUtilisee',
        'motifNonDetermination',
      };

      expect(clesUp.containsAll(attendues), isTrue);
      expect(clesTc.containsAll(attendues), isTrue,
          reason: 'les deux modèles doivent exposer EXACTEMENT les mêmes clés');
    });

    test('la même donnée produit la même relecture dans les deux modèles', () {
      final t = _tc(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[_attr()],
        etatTirelire: EtatTirelire.incluse,
        miseBaseCentimesUtilisee: 200,
      );
      final p = _up(
        etatGain: EtatGain.attribue,
        rapportsAttribues: <RapportAttribue>[_attr()],
        etatTirelire: EtatTirelire.incluse,
        miseBaseCentimesUtilisee: 200,
      );

      final tc = TrackedCourse.fromJson(t.toJson());
      final up = UserPrediction.fromJson(p.toJson());

      expect(tc.etatGain, up.etatGain);
      expect(tc.etatTirelire, up.etatTirelire);
      expect(tc.miseBaseCentimesUtilisee, up.miseBaseCentimesUtilisee);
      expect(tc.rapportsAttribues!.single.montantRetour,
          up.rapportsAttribues!.single.montantRetour);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1/9 — INVARIANT DE PROPAGATION (analyse statique du code source)
  //
  //  MESURE À L'ORIGINE DE CE GROUPE : `ajouterSuivi` (alert_service.dart:737)
  //  reconstruisait `TrackedCourse` champ par champ SANS les sept champs de
  //  gain — exactement le piège déjà corrigé trois fois dans ce fichier
  //  (`storageKey` = R1, ventilation G+P = B2-C, capture 4-F). De même
  //  `profile_historique_tab.dart:702` construisait une carte de partage
  //  depuis un `UserPrediction` sans recopier ces champs.
  //
  //  Ces deux sites sont corrigés au lot B-1. Ce groupe VERROUILLE
  //  l'invariant pour l'avenir : toute reconstruction qui recopie la capture
  //  4-F (`codePmuOfficiel`) doit aussi recopier les sept champs de gain.
  //  Si un futur lot ajoute une reconstruction partielle, ce test échoue.
  // ═════════════════════════════════════════════════════════════════════════
  group('B1/9 — invariant : aucune reconstruction ne perd les gains', () {
    const champsGain = <String>[
      'etatGain:',
      'rapportsAttribues:',
      'etatTirelire:',
      'dividendeGagnant:',
      'dividendePlace:',
      'miseBaseCentimesUtilisee:',
      'motifNonDetermination:',
    ];

    test('chaque bloc qui recopie codePmuOfficiel recopie les sept champs', () {
      // LISTE NOMINATIVE DES RECONSTRUCTIONS — pas d'heuristique.
      //
      // Trois tentatives successives de détection automatique ont été FAUSSES
      // (fenêtre arrière : 3 faux négatifs ; fenêtre avant : 4 faux positifs
      // sur des créations ; détection par identifiants : 2 faux négatifs sur
      // withResultat/withDividende, qui recopient des identifiants nus). Un
      // contrôle manuel ligne à ligne a établi la liste réelle des
      // reconstructions de `TrackedCourse` dans le dépôt :
      //
      //   1. alert_service.dart — ajouterSuivi        (course.xxx)
      //   2. alert_service.dart — withResultat        (identifiants nus)
      //   3. alert_service.dart — withDividende       (identifiants nus)
      //   4. alert_service.dart — fromJson            (j['xxx'])
      //   5. profile_historique_tab.dart — _partagerPrediction (pred.xxx)
      //
      // ★ CORRECTION BLOC 1 (qualité) — CE TEST ANNONÇAIT UNE PROTECTION QU'IL
      //   N'EXÉCUTAIT PAS.
      //
      //   Le bloc `if (debutMethode < 0)` est un CONTINUE : un site dont la
      //   méthode avait été renommée était compté « manquant » puis IGNORÉ,
      //   et la boucle passait au suivant. La garde ne protégeait donc pas
      //   réellement les cinq reconstructions. Le défaut est masqué aujourd'hui
      //   parce que `expect(manquants, isEmpty)` échoue sur toute méthode
      //   introuvable — la protection tient, mais par un chemin fragile et
      //   involontaire. Elle est maintenant EXPLICITE ci-dessous (P2).
      //
      //   Le commentaire annonçait aussi un contrôle « en sens inverse » des
      //   4 créations (« aucune ne doit porter ces champs ») qui n'existait
      //   NULLE PART, et il citait des lignes (`mes_paris_screen.dart:3083`,
      //   `bet_bottom_sheet.dart:3075`) qui ne correspondent plus à rien dans
      //   les fichiers actuels (respectivement 3 947 et 3 398 lignes).
      //
      //   Mesure réelle des 8 sites de construction (2026, BLOC 1) :
      //     • reconstructions (doivent recopier les 8) : ajouterSuivi,
      //       withResultat, withDividende, fromJson, _partagerPrediction,
      //       enregistreur_verdict_gain_pmu.enregistrerVerdictGain
      //     • créations (ne peuvent rien perdre) : mes_paris_screen:3877,
      //       bet_bottom_sheet:3226
      //   Les deux créations ÉCRIVENT bien `codePmuOfficiel` (mesuré :
      //   `null` pour l'une, `_codePmuDuTypeChoisi` pour l'autre) : la détection
      //   par simple présence de ce champ les aurait prises pour des
      //   reconstructions — d'où la liste nominative, qui reste la seule
      //   méthode fiable ici.
      final reconstructions = <List<String>>[
        ['lib/services/alert_service.dart', 'Future<void> ajouterSuivi('],
        ['lib/services/alert_service.dart', 'TrackedCourse withResultat({'],
        ['lib/services/alert_service.dart', 'TrackedCourse withDividende({'],
        [
          'lib/services/alert_service.dart',
          'factory TrackedCourse.fromJson(Map<String, dynamic> j) => TrackedCourse('
        ],
        [
          'lib/widgets/profile/profile_historique_tab.dart',
          'void _partagerPrediction(BuildContext context, UserPrediction pred)'
        ],
        [
          'lib/services/enregistreur_verdict_gain_suivi.dart',
          'TrackedCourse copyWith({'
        ],
      ];

      final manquants = <String>[];
      for (final entree in reconstructions) {
        final chemin = entree[0];
        final signature = entree[1];
        final src = File(chemin).readAsStringSync();
        final debutMethode = src.indexOf(signature);
        if (debutMethode < 0) {
          manquants.add('$chemin : méthode introuvable « $signature » '
              '(renommée ? le test doit être mis à jour explicitement)');
          continue;
        }
        // Le bloc court de la signature jusqu'à la fermeture de l'appel.
        final fermeture = RegExp(r'\n[ \t]*\)[ \t]*;')
            .firstMatch(src.substring(debutMethode));
        if (fermeture == null) {
          manquants.add('$chemin : fin de bloc introuvable pour « $signature »');
          continue;
        }
        final bloc = src.substring(
            debutMethode, debutMethode + fermeture.end);
        for (final champ in champsGain) {
          if (!bloc.contains(champ)) {
            manquants.add('$chemin (`$signature`) ne recopie pas $champ');
          }
        }
      }

      // ★ P2 — LA PROTECTION EST MAINTENANT EXPLICITE.
      //
      // Chacune des six reconstructions doit avoir été TROUVÉE : sans ce
      // contrôle, une signature renommée produirait un « manquant » puis
      // l'ignorerait si l'assertion finale venait à être modifiée. On sépare
      // donc « site introuvable » de « champ manquant », et on exige zéro des
      // deux — y compris si `champsGain` devenait vide un jour.
      final introuvables =
          manquants.where((m) => m.contains('introuvable')).toList();
      expect(introuvables, isEmpty,
          reason: 'sites de reconstruction non localisés : '
              '${introuvables.join(" | ")}');
      expect(reconstructions.length, 6,
          reason: 'la liste nominative doit couvrir les 6 reconstructions '
              'mesurées ; toute modification est une décision explicite');
      expect(champsGain.length, 7,
          reason: 'les SEPTIEME champs de gain mesurés — la liste du groupe '
              's\'appelle « les sept champs », une valeur différente signalerait '
              'un élargissement non documenté');
      expect(manquants, isEmpty, reason: manquants.join(' | '));
    });

    test(
        'ajouterSuivi propage bien les sept champs (preuve ciblée)', () {
      final src = File('lib/services/alert_service.dart').readAsStringSync();
      final i = src.indexOf('Future<void> ajouterSuivi(');
      expect(i, greaterThan(0), reason: 'ajouterSuivi introuvable');
      final fin = src.indexOf('_trackedCourses[storageKey] = courseAvecKey;', i);
      expect(fin, greaterThan(i));
      final bloc = src.substring(i, fin);
      for (final champ in champsGain) {
        expect(bloc.contains(champ), isTrue,
            reason: 'ajouterSuivi perd $champ — piège R1/B2-C/4-F');
      }
    });

    test('la carte de partage G+P ne crée pas une seconde source de montant',
        () {
      // Le montant de la carte vient de `pred.gainNet` sous garde G+P, jamais
      // des champs de gain structurés. Vérifié pour qu'un futur lot ne
      // réintroduise pas un second chemin de calcul silencieux.
      final src =
          File('lib/widgets/profile/profile_historique_tab.dart').readAsStringSync();
      expect(
          src.contains(
              'pred.isCorrect == true && pred.gainGagnantPlaceEtabli ? pred.gainNet : null'),
          isTrue,
          reason: 'la garde G+P du montant partagé a disparu');
      expect(src.contains('gainTotal: gain'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B1/8 — NON-RÉGRESSION DES CHAMPS HISTORIQUES
  // ═════════════════════════════════════════════════════════════════════════
  group('B1/8 — champs historiques intacts', () {
    test('les 22 clés historiques de UserPrediction sont toujours écrites', () {
      final json = _up().toJson();
      for (final cle in <String>[
        'id', 'dateStr', 'numReunion', 'numCourse', 'nomCourse', 'hippodrome',
        'numeroCheval', 'nomCheval', 'cote', 'typePari', 'createdAt',
        'isCorrect', 'scoreIA', 'montantMise', 'gainRealise', 'numerosJoues',
        'dividendePmuReel', 'combinaisonPmu', 'miseGagnant', 'misePlace',
        'coteGagnant', 'cotePlace',
      ]) {
        expect(json.containsKey(cle), isTrue, reason: 'clé perdue : $cle');
      }
    });

    test('les 24 clés historiques de TrackedCourse sont toujours écrites', () {
      final json = _tc().toJson();
      for (final cle in <String>[
        'numReunion', 'numCourse', 'nomCourse', 'hippodrome', 'heureDepart',
        'nomCheval', 'numeroCheval', 'miseEngagee', 'miseGagnant', 'misePlace',
        'coteGagnant', 'cotePlace', 'addedAt', 'typePari', 'numerosJoues',
        'iaMemKey', 'scoreIA', 'cote', 'isGagne', 'arriveeFinale',
        'messageResultat', 'dividendePmuReel', 'combinaisonPmu', 'storageKey',
      ]) {
        expect(json.containsKey(cle), isTrue, reason: 'clé perdue : $cle');
      }
    });

    test('typePari et numerosJoues traversent inchangés', () {
      final relu = TrackedCourse.fromJson(
          _tc(typePari: 'Quinté+').toJson());
      expect(relu.typePari, 'Quinté+');
      expect(relu.numerosJoues, const [9]);
    });

    test('gainNet du chemin legacy reste identique', () {
      // Aucun des sept champs n'entre dans `gainNet` : la formule existante
      // est intacte. On le vérifie explicitement.
      final p = UserPrediction(
        id: 'x',
        dateStr: '2026-11-15',
        numReunion: 1,
        numCourse: 1,
        nomCourse: 'P',
        hippodrome: 'V',
        numeroCheval: 9,
        nomCheval: 'C',
        cote: 6.5,
        typePari: 'Simple Gagnant',
        createdAt: DateTime(2026, 11, 15),
        montantMise: 2.0,
        isCorrect: true,
        dividendePmuReel: 7.5,
        etatGain: EtatGain.attribue,
      );
      // gainNet = (7.5 × 2) − 2 = 13.0 — inchangé par la présence d'etatGain.
      expect(p.gainNet, 13.0);
    });
  });
}
