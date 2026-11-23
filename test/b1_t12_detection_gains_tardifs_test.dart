// ═══════════════════════════════════════════════════════════════════════════
//  B1-T12 / LOT 2-C — DÉTECTION DES GAINS OFFICIELS TARDIFS
//
//  Familles :
//    A1–A6  : IDENTITÉ de course et validation de date (aucune date inventée).
//    B1–B9  : CLASSIFICATION — les CINQ cas, chacun prouvé SÉPARÉMENT.
//    C1–C3  : COURT-CIRCUIT — on n'interroge pas l'arrivée pour rien.
//    D1–D2  : AUCUNE EXCEPTION PROPAGÉE — une panne est classée.
//    E1–E6  : BACKOFF — échelle exacte, plancher à 48 h, aucun abandon.
//    F1–F4  : SÉLECTION — bornage à 3, ordre déterministe, dédoublonnage.
//    G1–G3  : NON-CONCURRENCE — verrou posé avant le premier `await`.
//    H1–H3  : PERSISTANCE — l'état survit et pilote le cycle suivant.
//    I1–I2  : GARANTIES MÉTIER — `permetEcriture` et `reessayable`.
//
//  ⚠️ MÉTHODE : les sources réseau sont INJECTÉES. Chaque test vérifie ce que
//     la classification VAUT, mais aussi COMBIEN de fois chaque source a été
//     appelée — une classification correcte obtenue en interrogeant l'arrivée
//     inutilement serait un défaut caché, et il est mesuré ici.
//
//  ⚠️ AUCUNE VALEUR ATTENDUE N'EST SUPPOSÉE : l'échelle du backoff est relue
//     depuis `EtatSuiviCourse.delais` pour les assertions d'échéance, et les
//     durées sont écrites en clair là où c'est l'ÉCHELLE elle-même qui est
//     sous test — les deux se contrôlent mutuellement.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart' show ResultatCourse;
import 'package:pronostic_hippique/services/detection_gains_tardifs.dart';
import 'package:pronostic_hippique/services/gain_calculator.dart'
    show RapportPmu;
import 'package:pronostic_hippique/services/pmu_api_service.dart'
    show CauseAbsenceRapports, DiagnosticRapports;

// ═══════════════════════════════ Outils de test ═════════════════════════════

/// Une date valide au format `DDMMYYYY`, celui de `UserPrediction.dateStr`.
const String _date = '15032025';

IdentiteCourseTardive _id({
  String dateStr = _date,
  int r = 1,
  int c = 1,
}) =>
    IdentiteCourseTardive(dateStr: dateStr, numReunion: r, numCourse: c);

/// Arrivée EXPLOITABLE : définitive, avec des groupes non vides.
ResultatCourse _arriveeOk() => const ResultatCourse(
      arriveeOfficielle: <int>[5, 7, 3],
      arriveeGroupes: <List<int>>[
        <int>[5],
        <int>[7],
        <int>[3],
      ],
      arriveeDefinitive: true,
    );

/// Diagnostic « au moins un rapport exploitable ».
DiagnosticRapports _diagOk() => DiagnosticRapports(
      rapports: <RapportPmu>[
        const RapportPmu(
          typePari: 'E_SIMPLE_GAGNANT',
          combinaison: '5',
          dividende: 3.4,
          estOrdre: false,
        ),
      ],
      cause: CauseAbsenceRapports.aucune,
      lignesPubliees: 1,
    );

DiagnosticRapports _diag(CauseAbsenceRapports cause, {int lignes = 0}) =>
    DiagnosticRapports(
      rapports: const <RapportPmu>[],
      cause: cause,
      lignesPubliees: lignes,
    );

/// Détecteur instrumenté : compte les appels, et laisse choisir les réponses.
class _Sonde {
  int appelsRapports = 0;
  int appelsArrivee = 0;

  /// Ce que la source de rapports rend (ou lève, si [leverRapports]).
  DiagnosticRapports Function(IdentiteCourseTardive) repondRapports =
      (_) => _diagOk();
  Object? leverRapports;

  /// Porte d'étranglement : tant qu'elle n'est pas complétée, la source de
  /// rapports reste suspendue. Permet de prouver que le VERROU est posé avant
  /// le premier `await`, sans dépendre du timing de la machine.
  Completer<void>? porte;

  /// Ce que la source d'arrivée rend (ou lève, si [leverArrivee]).
  ResultatCourse? Function(IdentiteCourseTardive) repondArrivee =
      (_) => _arriveeOk();
  Object? leverArrivee;

  late final DetecteurGainsTardifs detecteur;

  _Sonde({
    required BackoffTardifStore store,
    DateTime Function()? horloge,
  }) {
    detecteur = DetecteurGainsTardifs(
      store: store,
      horloge: horloge,
      sourceRapports: (dateStr, numR, numC) async {
        appelsRapports++;
        final p = porte;
        if (p != null) await p.future;
        final e = leverRapports;
        if (e != null) throw e;
        return repondRapports(
            _id(dateStr: dateStr, r: numR, c: numC));
      },
      sourceArrivee: ({required heureDepart, required numReunion, required numCourse}) async {
        appelsArrivee++;
        final e = leverArrivee;
        if (e != null) throw e;
        return repondArrivee(_id(
          dateStr: '${heureDepart.day.toString().padLeft(2, '0')}'
              '${heureDepart.month.toString().padLeft(2, '0')}'
              '${heureDepart.year}',
          r: numReunion,
          c: numCourse,
        ));
      },
    );
  }
}

Future<BackoffTardifStore> _store() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return BackoffTardifStore.ouvrir();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  A — IDENTITÉ ET DATE
  // ═════════════════════════════════════════════════════════════════════════

  group('A — identité de course et validation de date', () {
    test('A1 la clé inclut la DATE : deux courses de mêmes numéros à des '
        'dates différentes sont DEUX courses', () {
      final a = _id(dateStr: '15032025');
      final b = _id(dateStr: '16032025');
      expect(a.cle, isNot(b.cle));
      expect(a, isNot(b));
      expect(a.cle, '15032025_R1C1');
    });

    test('A2 une date au format attendu est lue sans invention', () {
      final d = _id(dateStr: '15032025').date;
      expect(d, isNotNull);
      expect(d!.year, 2025);
      expect(d.month, 3);
      expect(d.day, 15);
    });

    test('A3 longueur incorrecte, caractères non numériques, champs hors '
        'bornes : TOUT rend null, rien n\'est corrigé', () {
      for (final mauvais in <String>[
        '',
        '1503202', // 7 chiffres
        '150320255', // 9 chiffres
        '15O32025', // lettre O au lieu de 0
        '15/03/25', // séparateurs
        ' 1503202', // espace + 7 chiffres => 7 après trim
        '150320255 ', // espace final, mais 9 chiffres
        '00032025', // jour 0
        '32032025', // jour 32
        '15132025', // mois 13
        '15002025', // mois 0
        '15031800', // année trop ancienne
        '15032300', // année trop lointaine
      ]) {
        final d = IdentiteCourseTardive(
                dateStr: mauvais, numReunion: 1, numCourse: 1)
            .date;
        expect(d, isNull, reason: 'dateStr="$mauvais" aurait dû rendre null');
      }
    });

    test('A4 le 31 avril est REFUSÉ : la relecture détecte la composante '
        'réécrite par le constructeur de DateTime', () {
      // 31/04 n'existe pas : `DateTime(2025, 4, 31)` devient le 1er mai.
      // Sans relecture, on accepterait une date que le ticket ne porte pas.
      expect(_id(dateStr: '31042025').date, isNull);
      // Témoin : le 30 avril, lui, existe.
      expect(_id(dateStr: '30042025').date, isNotNull);
    });

    test('A5 égalité et hashCode suivent les trois composantes', () {
      expect(_id(), _id());
      expect(_id().hashCode, _id().hashCode);
      expect(_id(), isNot(_id(r: 2)));
      expect(_id(), isNot(_id(c: 2)));
      expect(_id(), isNot(_id(dateStr: '16032025')));
    });

    test('A6 toString est la clé — aucune donnée ajoutée', () {
      expect(_id().toString(), _id().cle);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B — CLASSIFICATION : les cinq cas, séparément
  // ═════════════════════════════════════════════════════════════════════════

  group('B — classification', () {
    test('B1 rapports exploitables + arrivée définitive + groupes non vides '
        '⇒ exploitable', () async {
      final s = _Sonde(store: await _store());
      final r = await s.detecteur.interroger(_id());
      expect(r.classification, ClassificationCourseTardive.exploitable);
      expect(r.classification.permetEcriture, isTrue);
      expect(r.causeRapports, CauseAbsenceRapports.aucune);
      expect(r.erreur, isNull);
    });

    test('B2 `aucunRapportPublie` ⇒ rapportsAbsents (JAMAIS indisponible : '
        'l\'API a répondu, elle dit qu\'elle n\'a rien)', () async {
      final s = _Sonde(store: await _store());
      s.repondRapports = (_) => _diag(CauseAbsenceRapports.aucunRapportPublie);
      final r = await s.detecteur.interroger(_id());
      expect(r.classification, ClassificationCourseTardive.rapportsAbsents);
      expect(r.classification.permetEcriture, isFalse);
      expect(r.causeRapports, CauseAbsenceRapports.aucunRapportPublie);
    });

    test('B3 `aucunRapportExploitable` ⇒ rapportsInexploitables, distinct '
        'de « absents »', () async {
      final s = _Sonde(store: await _store());
      s.repondRapports =
          (_) => _diag(CauseAbsenceRapports.aucunRapportExploitable, lignes: 4);
      final r = await s.detecteur.interroger(_id());
      expect(
          r.classification, ClassificationCourseTardive.rapportsInexploitables);
      expect(r.classification, isNot(ClassificationCourseTardive.rapportsAbsents));
      expect(r.classification.permetEcriture, isFalse);
    });

    test('B4 les cinq causes de PANNE ⇒ indisponible, et jamais '
        '« rapports absents » : la course peut très bien être réglée', () async {
      for (final cause in <CauseAbsenceRapports>[
        CauseAbsenceRapports.httpNonOk,
        CauseAbsenceRapports.timeout,
        CauseAbsenceRapports.reseau,
        CauseAbsenceRapports.corpsNonJson,
        CauseAbsenceRapports.racineNonListe,
      ]) {
        final s = _Sonde(store: await _store());
        s.repondRapports = (_) => _diag(cause);
        final r = await s.detecteur.interroger(_id());
        expect(r.classification, ClassificationCourseTardive.indisponible,
            reason: 'cause=${cause.name}');
        expect(r.classification, isNot(ClassificationCourseTardive.rapportsAbsents),
            reason: 'cause=${cause.name}');
        expect(r.causeRapports, cause);
      }
    });

    test('B5 arrivée explicitement PROVISOIRE ⇒ arriveeProvisoire, '
        'aucune écriture autorisée', () async {
      final s = _Sonde(store: await _store());
      s.repondArrivee = (_) => const ResultatCourse(
            arriveeOfficielle: <int>[5, 7, 3],
            arriveeGroupes: <List<int>>[
              <int>[5],
              <int>[7],
              <int>[3],
            ],
            arriveeDefinitive: false,
          );
      final r = await s.detecteur.interroger(_id());
      expect(r.classification, ClassificationCourseTardive.arriveeProvisoire);
      expect(r.classification.permetEcriture, isFalse);
    });

    test('B6 `arriveeDefinitive == null` n\'est PAS converti en « provisoire » '
        'ni refusé : l\'absence de démenti n\'est pas une confirmation, mais '
        'elle n\'est pas non plus une infirmation — on continue', () async {
      final s = _Sonde(store: await _store());
      s.repondArrivee = (_) => const ResultatCourse(
            arriveeOfficielle: <int>[5, 7, 3],
            arriveeGroupes: <List<int>>[
              <int>[5],
              <int>[7],
              <int>[3],
            ],
            arriveeDefinitive: null,
          );
      final r = await s.detecteur.interroger(_id());
      expect(r.classification, ClassificationCourseTardive.exploitable);
    });

    test('B7 arrivée null (illisible) ⇒ indisponible', () async {
      final s = _Sonde(store: await _store());
      s.repondArrivee = (_) => null;
      final r = await s.detecteur.interroger(_id());
      expect(r.classification, ClassificationCourseTardive.indisponible);
      expect(r.erreur, isNotNull);
    });

    test('B8 groupes nuls ou vides ⇒ indisponible — on n\'écrit pas un '
        'verdict sur une arrivée dont on ne connaît pas la structure', () async {
      for (final groupes in <List<List<int>>?>[
        null,
        const <List<int>>[],
      ]) {
        final s = _Sonde(store: await _store());
        s.repondArrivee = (_) => ResultatCourse(
              arriveeOfficielle: const <int>[],
              arriveeGroupes: groupes,
              arriveeDefinitive: true,
            );
        final r = await s.detecteur.interroger(_id());
        expect(r.classification, ClassificationCourseTardive.indisponible);
      }
    });

    test('B9 une date inexploitable ⇒ indisponible SANS AUCUN APPEL réseau',
        () async {
      final s = _Sonde(store: await _store());
      final r = await s.detecteur.interroger(_id(dateStr: '15/03/25'));
      expect(r.classification, ClassificationCourseTardive.indisponible);
      expect(s.appelsRapports, 0);
      expect(s.appelsArrivee, 0);
      expect(r.erreur, contains('dateStr'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  C — COURT-CIRCUIT : ne pas interroger l'arrivée pour rien
  // ═════════════════════════════════════════════════════════════════════════

  group('C — court-circuit des sources', () {
    test('C1 quand les rapports sont absents, l\'arrivée n\'est PAS '
        'interrogée : un appel réseau inutile par cycle et par course', () async {
      final s = _Sonde(store: await _store());
      s.repondRapports = (_) => _diag(CauseAbsenceRapports.aucunRapportPublie);
      await s.detecteur.interroger(_id());
      expect(s.appelsRapports, 1);
      expect(s.appelsArrivee, 0);
    });

    test('C2 quand les rapports sont inexploitables, l\'arrivée n\'est PAS '
        'interrogée', () async {
      final s = _Sonde(store: await _store());
      s.repondRapports =
          (_) => _diag(CauseAbsenceRapports.aucunRapportExploitable, lignes: 2);
      await s.detecteur.interroger(_id());
      expect(s.appelsArrivee, 0);
    });

    test('C3 quand les rapports sont exploitables, l\'arrivée EST interrogée '
        '— une fois, pas deux', () async {
      final s = _Sonde(store: await _store());
      await s.detecteur.interroger(_id());
      expect(s.appelsRapports, 1);
      expect(s.appelsArrivee, 1);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  D — AUCUNE EXCEPTION PROPAGÉE
  // ═════════════════════════════════════════════════════════════════════════

  group('D — les pannes sont classées, jamais propagées', () {
    test('D1 une exception de la source de rapports ⇒ indisponible, '
        'et l\'appelant ne lève pas', () async {
      final s = _Sonde(store: await _store());
      s.leverRapports = StateError('réseau coupé');
      late ResultatDetectionCourse r;
      await expectLater(
        () async => r = await s.detecteur.interroger(_id()),
        returnsNormally,
      );
      expect(r.classification, ClassificationCourseTardive.indisponible);
      expect(r.erreur, contains('réseau coupé'));
      expect(s.appelsArrivee, 0);
    });

    test('D2 une exception de la source d\'arrivée ⇒ indisponible', () async {
      final s = _Sonde(store: await _store());
      s.leverArrivee = const FormatException('corps illisible');
      final r = await s.detecteur.interroger(_id());
      expect(r.classification, ClassificationCourseTardive.indisponible);
      expect(r.erreur, contains('arrivée'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  E — BACKOFF
  // ═════════════════════════════════════════════════════════════════════════

  group('E — backoff persistant', () {
    test('E1 l\'échelle est EXACTEMENT 15 min, 1 h, 6 h, 24 h, 48 h', () {
      expect(EtatSuiviCourse.delais.length, 5);
      expect(EtatSuiviCourse.delais[0], const Duration(minutes: 15));
      expect(EtatSuiviCourse.delais[1], const Duration(hours: 1));
      expect(EtatSuiviCourse.delais[2], const Duration(hours: 6));
      expect(EtatSuiviCourse.delais[3], const Duration(hours: 24));
      expect(EtatSuiviCourse.delais[4], const Duration(hours: 48));
    });

    test('E2 `delaiApres` : immédiat avant le premier essai, puis indexation, '
        'puis PLANCHER à 48 h — jamais d\'abandon', () {
      expect(EtatSuiviCourse.delaiApres(0), Duration.zero);
      expect(EtatSuiviCourse.delaiApres(1), const Duration(minutes: 15));
      expect(EtatSuiviCourse.delaiApres(2), const Duration(hours: 1));
      expect(EtatSuiviCourse.delaiApres(3), const Duration(hours: 6));
      expect(EtatSuiviCourse.delaiApres(4), const Duration(hours: 24));
      expect(EtatSuiviCourse.delaiApres(5), const Duration(hours: 48));
      // ★ Le plancher : au-delà, on ne cesse JAMAIS de réessayer.
      expect(EtatSuiviCourse.delaiApres(6), const Duration(hours: 48));
      expect(EtatSuiviCourse.delaiApres(50), const Duration(hours: 48));
      expect(EtatSuiviCourse.delaiApres(5000), const Duration(hours: 48));
    });

    test('E3 `prochainEssai` est null avant tout essai, puis dernierEssai + '
        'délai', () {
      expect(const EtatSuiviCourse().prochainEssai, isNull);
      final t0 = DateTime(2025, 3, 15, 12);
      final e1 = const EtatSuiviCourse().apresEssai(
          t0, ClassificationCourseTardive.rapportsAbsents);
      expect(e1.prochainEssai, t0.add(const Duration(minutes: 15)));
    });

    test('E4 éligibilité : refusée AVANT l\'échéance, accordée À l\'échéance '
        'et après', () {
      final t0 = DateTime(2025, 3, 15, 12);
      final e1 = const EtatSuiviCourse()
          .apresEssai(t0, ClassificationCourseTardive.rapportsAbsents);
      expect(e1.estEligibleA(t0), isFalse);
      expect(e1.estEligibleA(t0.add(const Duration(minutes: 14))), isFalse);
      expect(e1.estEligibleA(t0.add(const Duration(minutes: 15))), isTrue);
      expect(e1.estEligibleA(t0.add(const Duration(days: 30))), isTrue);
    });

    test('E5 un état vierge est immédiatement éligible', () {
      expect(const EtatSuiviCourse().estEligibleA(DateTime(2025, 1, 1)),
          isTrue);
    });

    test('E6 chaque essai incrémente le compteur et mémorise la '
        'classification', () {
      final t0 = DateTime(2025, 3, 15, 12);
      var e = const EtatSuiviCourse();
      expect(e.tentatives, 0);
      e = e.apresEssai(t0, ClassificationCourseTardive.indisponible);
      expect(e.tentatives, 1);
      expect(e.derniereClassification, ClassificationCourseTardive.indisponible);
      e = e.apresEssai(t0, ClassificationCourseTardive.rapportsAbsents);
      expect(e.tentatives, 2);
      expect(e.derniereClassification, ClassificationCourseTardive.rapportsAbsents);
      // Le délai suit le NOMBRE de tentatives, pas la dernière classification.
      expect(e.prochainEssai, t0.add(const Duration(hours: 1)));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  F — SÉLECTION
  // ═════════════════════════════════════════════════════════════════════════

  group('F — sélection bornée et déterministe', () {
    test('F1 trois courses au maximum par cycle, même si dix sont candidates',
        () async {
      expect(kMaxCoursesParCycle, 3);
      final store = await _store();
      final d = DetecteurGainsTardifs(store: store);
      final candidates = <IdentiteCourseTardive>[
        for (var i = 1; i <= 10; i++) _id(c: i),
      ];
      expect(d.selectionner(candidates).length, 3);
    });

    test('F2 l\'ordre est DÉTERMINISTE : les jamais-essayées d\'abord, '
        'par clé croissante', () async {
      final store = await _store();
      final d = DetecteurGainsTardifs(store: store);
      final candidates = <IdentiteCourseTardive>[_id(c: 3), _id(c: 1), _id(c: 2)];
      final sel = d.selectionner(candidates);
      expect(sel.map((e) => e.cle).toList(),
          <String>['${_date}_R1C1', '${_date}_R1C2', '${_date}_R1C3']);
    });

    test('F3 une course due passe, une course pas encore due est écartée',
        () async {
      final t0 = DateTime(2025, 3, 15, 12);
      final store = await _store();
      // C2 : essayée il y a 2 jours, 1 tentative -> délai 15 min -> DUE.
      // C3 : essayée il y a 1 min, 1 tentative -> échéance t0+14min -> PAS due.
      await store.ecrireTout(<String, EtatSuiviCourse>{
        _id(c: 2).cle: EtatSuiviCourse(
            tentatives: 1, dernierEssai: t0.subtract(const Duration(days: 2))),
        _id(c: 3).cle: EtatSuiviCourse(
            tentatives: 1, dernierEssai: t0.subtract(const Duration(minutes: 1))),
      });
      final d = DetecteurGainsTardifs(store: store, horloge: () => t0);
      final sel = d.selectionner(<IdentiteCourseTardive>[
        _id(c: 2),
        _id(c: 3),
      ]);
      expect(sel.map((e) => e.cle).toList(), <String>['${_date}_R1C2']);
    });

    test('F3bis à échéances égales, l\'ordre retombe sur la clé : le tri est '
        'TOTAL, donc reproductible', () async {
      final t0 = DateTime(2025, 3, 15, 12);
      final store = await _store();
      // C1 et C2 ont la MÊME échéance : seule la clé peut les départager.
      await store.ecrireTout(<String, EtatSuiviCourse>{
        _id(c: 1).cle: EtatSuiviCourse(
            tentatives: 1, dernierEssai: t0.subtract(const Duration(days: 3))),
        _id(c: 2).cle: EtatSuiviCourse(
            tentatives: 1, dernierEssai: t0.subtract(const Duration(days: 3))),
      });
      final d = DetecteurGainsTardifs(store: store, horloge: () => t0);
      final sel = d.selectionner(<IdentiteCourseTardive>[_id(c: 2), _id(c: 1)]);
      expect(sel.map((e) => e.cle).toList(),
          <String>['${_date}_R1C1', '${_date}_R1C2']);
    });

    test('F4 dédoublonnage : la même course proposée deux fois n\'est '
        'sélectionnée qu\'une fois, et une date invalide est écartée',
        () async {
      final store = await _store();
      final d = DetecteurGainsTardifs(store: store);
      final sel = d.selectionner(<IdentiteCourseTardive>[
        _id(),
        _id(), // doublon exact
        _id(dateStr: 'bidon'),
      ]);
      expect(sel.length, 1);
      expect(sel.single.cle, _id().cle);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  G — NON-CONCURRENCE
  // ═════════════════════════════════════════════════════════════════════════

  group('G — non-concurrence', () {
    test('G1 le verrou est posé AVANT le premier `await` : une seconde '
        'demande de la même course est exclue de la sélection', () async {
      final store = await _store();
      final s = _Sonde(store: store);
      final porte = Completer<void>();
      s.porte = porte;

      final futur = s.detecteur.interroger(_id());
      // Aucun `await` de l'appelant : on est encore dans la section synchrone.
      expect(s.detecteur.estEnVol(_id().cle), isTrue);
      expect(s.detecteur.selectionner(<IdentiteCourseTardive>[_id()]), isEmpty);

      porte.complete();
      await futur;
      expect(s.detecteur.estEnVol(_id().cle), isFalse);
      // Une fois relâchée, la course redevient sélectionnable.
      expect(s.detecteur.selectionner(<IdentiteCourseTardive>[_id()]).length, 1);
    });

    test('G2 le verrou est relâché MÊME si la source lève', () async {
      final store = await _store();
      final s = _Sonde(store: store);
      s.leverRapports = StateError('boum');
      await s.detecteur.interroger(_id());
      expect(s.detecteur.estEnVol(_id().cle), isFalse);
    });

    test('G3 deux cycles successifs interrogent bien la course deux fois : '
        'le verrou n\'est pas un abandon définitif', () async {
      final store = await _store();
      var t = DateTime(2025, 3, 15, 12);
      final s = _Sonde(store: store, horloge: () => t);
      await s.detecteur.executerCycle(<IdentiteCourseTardive>[_id()]);
      expect(s.appelsRapports, 1);
      // Immédiatement après : le backoff de 15 min interdit le second essai.
      await s.detecteur.executerCycle(<IdentiteCourseTardive>[_id()]);
      expect(s.appelsRapports, 1);
      // 16 minutes plus tard : de nouveau éligible.
      t = t.add(const Duration(minutes: 16));
      await s.detecteur.executerCycle(<IdentiteCourseTardive>[_id()]);
      expect(s.appelsRapports, 2);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  H — PERSISTANCE
  // ═════════════════════════════════════════════════════════════════════════

  group('H — persistance du backoff', () {
    test('H1 l\'état écrit survit à la relecture, y compris la classification',
        () async {
      final store = await _store();
      final t0 = DateTime(2025, 3, 15, 12);
      await store.ecrireTout(<String, EtatSuiviCourse>{
        _id().cle: const EtatSuiviCourse()
            .apresEssai(t0, ClassificationCourseTardive.rapportsAbsents),
      });
      final relu = store.lire(_id().cle);
      expect(relu.tentatives, 1);
      expect(relu.dernierEssai, t0);
      expect(relu.derniereClassification,
          ClassificationCourseTardive.rapportsAbsents);
    });

    test('H2 un cycle persiste l\'état : un SECOND détecteur sur le même '
        'stockage respecte le backoff du Premier', () async {
      final t0 = DateTime(2025, 3, 15, 12);
      final store = await _store();
      final s1 = _Sonde(store: store, horloge: () => t0);
      await s1.detecteur.executerCycle(<IdentiteCourseTardive>[_id()]);
      expect(s1.appelsRapports, 1);

      // Redémarrage : nouvelle instance, même disque, horloge au même instant.
      final s2 = _Sonde(store: store, horloge: () => t0);
      await s2.detecteur.executerCycle(<IdentiteCourseTardive>[_id()]);
      expect(s2.appelsRapports, 0,
          reason: 'le backoff persisté aurait dû interdire le second essai');
    });

    test('H3 un contenu corrompu rend une carte vide et ne bloque RIEN',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        BackoffTardifStore.clePrefs: '{ceci n\'est pas du JSON',
      });
      final store = await BackoffTardifStore.ouvrir();
      expect(store.lireTout(), isEmpty);
      expect(store.lire(_id().cle).tentatives, 0);
      // Et l'éligibilité est donc immédiate.
      expect(store.lire(_id().cle).estEligibleA(DateTime(2025, 1, 1)), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  I — GARANTIES MÉTIER
  // ═════════════════════════════════════════════════════════════════════════

  group('I — garanties du lot', () {
    test('I1 SEUL `exploitable` autorise une écriture', () {
      for (final c in ClassificationCourseTardive.values) {
        expect(c.permetEcriture, c == ClassificationCourseTardive.exploitable,
            reason: 'classification=${c.name}');
      }
    });

    test('I2 AUCUN cas n\'est un abandon définitif : tous restent '
        'réessayables, y compris « inexploitables »', () {
      for (final c in ClassificationCourseTardive.values) {
        expect(c.reessayable, isTrue, reason: 'classification=${c.name}');
      }
    });
  });
}
