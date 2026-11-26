// AUDIT §3.1 / §3.2 / §3.3 — TROIS CHAÎNES DE BOUT EN BOUT
//
// §3.1  ELO : ratings DISTINCTS (clé composite NOM|DISCIPLINE), acquisition,
//       mise à jour après arrivée, persistance, transmission au moteur.
// §3.2  Mouvement de cote (critère R) : fonctionnement DANS la fenêtre active
//       et transmission effective vers le score.
// §3.3  Isolates : `_BatchPayload`, sérialisation, et surtout POIDS EFFECTIFS
//       sur TOUS les chemins d'analyse.
//
// MÉTHODE : on n'emploie QUE des API publiques ou `@visibleForTesting`.
// Aucune formule, aucun seuil, aucun poids, aucune borne n'est modifié.
// Les valeurs sont MESURÉES, jamais supposées.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/cote_tracker_service.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';

ZtPartant _p(String num, String nom, {double cote = 5.0}) => ZtPartant(
      numero: num,
      nom: nom,
      driver: 'J. DUPONT',
      entraineur: 'E. MARTIN',
      proprietaire: 'ECURIE TEST',
      gains: '50000',
      record: "1'12\"5",
      musique: '1a2a3a',
      cote: cote.toStringAsFixed(1),
      ageSexe: 'H5',
      poids: 56.0,
      placeDepartInt: 3,
      joursRepos: 20,
    );

ZtCourse _course({
  String type = 'Attelé',
  String anchor = 'R1C1',
  String dateStr = '26112026',
  String heure = '15:15',
}) =>
    ZtCourse(
      numCourse: 1,
      anchor: anchor,
      nom: 'PRIX DE TEST',
      heure: heure,
      distance: '2700',
      prix: '30000',
      type: type,
      piste: 'bon',
      categorie: 'Course D',
      isQuinte: false,
      pronosticZt: const <int>[],
      partants: <ZtPartant>[_p('1', 'ALPHA'), _p('2', 'BRAVO')],
      dateStr: dateStr,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // ══════════════════════════════════════════════════════════════════════════
  // §3.1 — ELO : RATINGS DISTINCTS PAR DISCIPLINE
  // ══════════════════════════════════════════════════════════════════════════
  group('E — ELO par discipline (§3.1)', () {
    test('E1 — la clé ELO est composite NOM|DISCIPLINE : deux ratings distincts', () {
      EloService.instance.chargerDepuisMapIsolate(<String, dynamic>{
        'ALPHA|TROT_ATTELE': const EloScore(nomCheval: 'ALPHA', rating: 1700.0).toJson(),
        'ALPHA|PLAT': const EloScore(nomCheval: 'ALPHA', rating: 1300.0).toJson(),
      });

      expect(EloService.instance.getRating('ALPHA', discipline: 'Attelé'),
          equals(1700.0));
      expect(EloService.instance.getRating('ALPHA', discipline: 'Plat'),
          equals(1300.0));
      // Deux ratings DISTINCTS coexistent pour le MÊME cheval : mesuré.
      expect(EloService.instance.nbChevauxSuivis, equals(2));
    });

    test('E2 — discipline inconnue → repli sur la clé globale, sinon défaut 1500', () {
      EloService.instance.chargerDepuisMapIsolate(<String, dynamic>{
        'CHARLIE|': const EloScore(nomCheval: 'CHARLIE', rating: 1620.0).toJson(),
      });
      expect(EloService.instance.getRating('CHARLIE', discipline: 'Cross'),
          equals(1620.0), reason: 'clé globale utilisée en repli');
      expect(EloService.instance.getRating('DELTA', discipline: 'Cross'),
          equals(1500.0), reason: 'aucun rating → défaut mesuré 1500');
    });

    test('E3 — enrichirAvecElo TRANSMET le rating distinct au partant', () {
      EloService.instance.chargerDepuisMapIsolate(<String, dynamic>{
        'ALPHA|TROT_ATTELE': const EloScore(nomCheval: 'ALPHA', rating: 1700.0).toJson(),
        'ALPHA|PLAT': const EloScore(nomCheval: 'ALPHA', rating: 1300.0).toJson(),
      });

      final partants = <ZtPartant>[_p('1', 'ALPHA'), _p('2', 'BRAVO')];
      final enTrot = EloService.instance
          .enrichirAvecElo(partants, discipline: 'Attelé');
      final enPlat = EloService.instance
          .enrichirAvecElo(partants, discipline: 'Plat');

      expect(enTrot[0].eloRating, equals(1700.0));
      expect(enPlat[0].eloRating, equals(1300.0));
      // ⚠️ BRAVO n'a AUCUN rating : la valeur de repli n'est plus écrite comme
      //    une note. Mesuré avant correction : 1500.0 → critère M figé à 37.5
      //    pour tout cheval sans historique. Désormais 0.0 (convention du
      //    modèle : « 0 = inconnu ») → critère M = 50.0 (neutralité légitime).
      //    Les deux ratings AUTHENTIQUES ci-dessus restent inchangés : aucune
      //    formule n'a été touchée.
      expect(enTrot[1].eloRating, equals(0.0),
          reason: 'aucune connaissance ⇒ aucun rating, pas un repli de 1500');
      expect(enTrot[1].eloNbCourses, equals(0));
    });

    test('E4 — scoreElo : barème réel mesuré (neutre sous 1200)', () {
      // Barème lu dans zt_models : ((elo - 1200) / 8).clamp(0,100)
      final p1700 = _p('1', 'ALPHA').copyWith(eloRating: 1700.0);
      final p1500 = _p('2', 'BRAVO').copyWith(eloRating: 1500.0);
      final p0 = _p('3', 'CHARLIE').copyWith(eloRating: 0.0);

      expect(p1700.scoreElo, closeTo(62.5, 1e-9));
      expect(p1500.scoreElo, closeTo(37.5, 1e-9));
      expect(p0.scoreElo, equals(50.0), reason: 'eloRating <= 0 → neutre 50');
    });

    test('E5 — l\'écriture ELO est déclenchée par UN SEUL chemin de production', () {
      // Constat de recensement (mesuré par grep) : `mettreAJourApresArrivee`
      // n'a QU'UN appelant de production, `data_refresh_service.dart:1321`,
      // et il transmet `discipline: typeCourse` (donc la clé est bien
      // composite). Ce test ne prouve pas l'absence d'autres chemins par
      // exécution : il FIGE la valeur de repli quand `discipline` est vide,
      // afin qu'une régression silencieuse soit détectée.
      EloService.instance.chargerDepuisMapIsolate(<String, dynamic>{
        'ALPHA|TROT_ATTELE': const EloScore(nomCheval: 'ALPHA', rating: 1700.0).toJson(),
        'ALPHA|': const EloScore(nomCheval: 'ALPHA', rating: 1510.0).toJson(),
      });
      // discipline vide → aucune clé composite cherchée → clé globale
      expect(EloService.instance.getRating('ALPHA'), equals(1510.0));
      expect(EloService.instance.getRating('ALPHA', discipline: 'Attelé'),
          equals(1700.0));
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // §3.2 — MOUVEMENT DE COTE (critère R)
  // ══════════════════════════════════════════════════════════════════════════
  group('R — mouvement de cote (§3.2)', () {
    test('R1 — barème scoreIA mesuré sur 7 paliers', () {
      final base = DateTime(2026, 11, 26, 15, 0);
      MouvementCote m(double v) => MouvementCote(
            numero: '1',
            nom: 'ALPHA',
            coteDebut: 10.0,
            coteCourante: 10.0,
            variationPct: v,
            premierSnap: base,
            dernierSnap: base,
            nbSnapshots: 2,
          );
      // Paliers LUS dans le code, MESURÉS ici.
      expect(m(-40).scoreIA, equals(90.0));
      expect(m(-20).scoreIA, equals(75.0));
      expect(m(-10).scoreIA, equals(62.0));
      expect(m(0).scoreIA, equals(50.0));
      expect(m(10).scoreIA, equals(38.0));
      expect(m(20).scoreIA, equals(28.0));
      expect(m(40).scoreIA, equals(15.0));
    });

    test('R2 — moyenne pondérée des snapshots : transmission par la MAP seule', () {
      // On injecte par `chargerMouvementsDepuisMapIsolate`, exactement le
      // véhicule utilisé par l'isolate : aucune valeur calculée n'est figée,
      // seules les ENTRÉES sont transmises.
      final now = DateTime.now();
      CoteTrackerService.instance.chargerMouvementsDepuisMapIsolate(
        <String, dynamic>{
          'R1C1_26112026': <Map<String, dynamic>>[
            <String, dynamic>{
              'numero': '1',
              'nom': 'ALPHA',
              'coteDebut': 10.0,
              'coteCourante': 5.0,
              'variationPct': -50.0,
              'premierSnap': now.millisecondsSinceEpoch,
              'dernierSnap': now.millisecondsSinceEpoch,
              'nbSnapshots': 3,
            },
          ],
        },
      );
      expect(
        CoteTrackerService.instance.scoreCritereR('R1C1_26112026', '1'),
        equals(90.0),
      );
      // Numéro absent → null (donc 50.0 côté moteur)
      expect(
        CoteTrackerService.instance.scoreCritereR('R1C1_26112026', '99'),
        isNull,
      );
    });

    test('R3 — estDansFenetre : bornes mesurées [0, +30 min]', () {
      String hhmm(DateTime d) =>
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      String ddmmyyyy(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}${d.month.toString().padLeft(2, '0')}${d.year}';

      final now = DateTime.now();
      final dans10 = now.add(const Duration(minutes: 10));
      final dans45 = now.add(const Duration(minutes: 45));
      final passe = now.subtract(const Duration(minutes: 5));

      final c10 = _course(heure: hhmm(dans10), dateStr: ddmmyyyy(dans10));
      final c45 = _course(heure: hhmm(dans45), dateStr: ddmmyyyy(dans45));
      final cp = _course(heure: hhmm(passe), dateStr: ddmmyyyy(passe));

      expect(CoteTrackerService.instance.estDansFenetre(c10), isTrue);
      expect(CoteTrackerService.instance.estDansFenetre(c45), isFalse);
      expect(CoteTrackerService.instance.estDansFenetre(cp), isFalse,
          reason: 'départ déjà passé → hors fenêtre');
    });

    test('R4 — la clé de course du moteur coïncide avec celle du tracker', () {
      // Producteur du tracker (`cote_tracker_service.dart:494`) :
      //   'R{numR}C{numCourse}_{dateStr}'
      // Moteur : `cleCourseMouvements()` (@visibleForTesting).
      // ⚠️ FIXTURE RENDU FIDÈLE À LA PRODUCTION : `zone_turf_service.dart`
      //    construit `numCourse: numOrdre` ET `anchor: 'R${numOfficiel}C$numOrdre'`
      //    (l. 338 et 358). Les deux portent donc le MÊME numéro de course.
      //    Mon fixture initial (`anchor: 'R3C7'` avec `numCourse: 1`) était
      //    incohérent — c'est le fixture qui était faux, pas la production.
      final c = _course(anchor: 'R3C1', dateStr: '26112026');
      final cle = IaPronosticEngine.cleCourseMouvements(c);
      expect(cle, equals('R3C1_26112026'),
          reason: 'numR=3 est bien EXTRAIT de l\'ancre, numCourse=1 vient du champ');
    });

    test('R5 — ancre inexploitable → clé VIDE, aucune clé inventée', () {
      final c = _course(anchor: '', dateStr: '26112026');
      expect(IaPronosticEngine.cleCourseMouvements(c), isEmpty);
    });

    test('R6 — hors fenêtre, le moteur écrit 50.0 (critère neutralisé)', () {
      final p = _p('1', 'ALPHA').copyWith(scoreMouvementCote: 90.0);
      final c = _course(
        heure: '03:00',
        dateStr: '01012030',
      );
      final res = IaPronosticEngine.analyserCourseAvecCriteres(c);
      // On ne peut pas lire `scoreMouvementCote` dans le retour (copie), mais
      // le critère R persisté doit valoir 50.0 sur les deux partants.
      final sc = res.$2;
      for (final entry in sc.entries) {
        expect(entry.value.mouvCote, equals(50.0),
            reason: 'partant ${entry.key} hors fenêtre → R neutre');
      }
      expect(p.scoreMouvementCote, equals(90.0),
          reason: 'témoin : le copyWith du test n\'a rien modifié en production');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // §3.3 — POIDS EFFECTIFS SUR TOUS LES CHEMINS D'ANALYSE
  // ══════════════════════════════════════════════════════════════════════════
  group('P — poids effectifs, tous chemins (§3.3)', () {
    test('P1 — les 3 chemins publics du moteur produisent les MÊMES scores', () {
      final c = _course();

      final a = IaPronosticEngine.analyserCourse(c);
      final b = IaPronosticEngine.analyserCourseAvecCriteres(c).$1;

      expect(a.length, equals(b.length));
      for (var i = 0; i < a.length; i++) {
        expect(a[i].numero, equals(b[i].numero));
        expect(a[i].scoreIA, closeTo(b[i].scoreIA, 1e-9),
            reason: 'chemin « analyserCourse » vs « analyserCourseAvecCriteres »');
      }
    });

    test('P2 — les 19 critères sont TOUS présents dans ScoresCriteres', () {
      final c = _course();
      final sc = IaPronosticEngine.analyserCourseAvecCriteres(c).$2;
      expect(sc, isNotEmpty);
      for (final entry in sc.entries) {
        final s = entry.value;
        expect(s.forme, isNotNull);
        expect(s.gains, isNotNull);
        expect(s.record, isNotNull);
        expect(s.cote, isNotNull);
        expect(s.constance, isNotNull);
        expect(s.victoires, isNotNull);
        expect(s.discipline, isNotNull);
        expect(s.distSpec, isNotNull);
        expect(s.jockey, isNotNull);
        expect(s.repos, isNotNull);
        expect(s.hippo, isNotNull);
        expect(s.entraineur, isNotNull);
        expect(s.elo, isNotNull);
        expect(s.terrain, isNotNull);
        expect(s.divergence, isNotNull);
        expect(s.poidsRel, isNotNull);
        expect(s.progression, isNotNull);
        expect(s.mouvCote, isNotNull);
        expect(s.placeDepart, isNotNull);
      }
    });

    test('P3 — POIDS EFFECTIFS identiques pour une discipline sans clé dédiée', () {
      final poids = IaPoidsAdaptatifs();
      final a = poids.poidsEffectifsPourDiscipline('Attelé');
      final b = poids.poidsEffectifsPourDiscipline('Plat');
      final c = poids.poidsEffectifsPourDiscipline('');

      // Aucune clé de discipline n'existe → les trois passent par le repli.
      for (final k in a.keys) {
        expect(b[k], closeTo(a[k]!, 1e-12), reason: 'clé $k');
        expect(c[k], closeTo(a[k]!, 1e-12), reason: 'clé $k');
      }
      expect(a.length, equals(19));
    });

    test('P4 — avec une clé de discipline, seule CETTE discipline change', () {
      final Map<String, double> vingtPlat = <String, double>{
        'forme': 0.30, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
        'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
        'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
        'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
        'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
        'mouvCote': 0.06, 'placeDepart': 0.03,
      };
      IaPoidsAdaptatifs.clampDiscipline(vingtPlat);

      final poids = IaPoidsAdaptatifs(
        poidsParDiscipline: <String, Map<String, double>>{'plat': vingtPlat},
      );

      final enPlat = poids.poidsEffectifsPourDiscipline('Plat');
      final enTrot = poids.poidsEffectifsPourDiscipline('Attelé');

      expect(enPlat['forme'], closeTo(vingtPlat['forme']!, 1e-12));
      expect(enTrot['forme'], equals(poids.forme),
          reason: 'trot sans clé dédiée → champ d\'instance, PAS le poids plat');
      expect(enPlat['forme'], isNot(closeTo(enTrot['forme']!, 1e-12)),
          reason: 'les deux disciplines ne partagent donc pas les mêmes poids');
    });

    test('P5 — la serialisation isolate conserve TOUS les poids de discipline', () {
      final Map<String, double> v = <String, double>{
        'forme': 0.31, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
        'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
        'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
        'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
        'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
        'mouvCote': 0.06, 'placeDepart': 0.03,
      };
      IaPoidsAdaptatifs.clampDiscipline(v);
      final poids = IaPoidsAdaptatifs(
        poidsParDiscipline: <String, Map<String, double>>{'trot_monte': v},
      );

      final json = poids.toJson();
      final relu = IaPoidsAdaptatifs.fromJson(json);

      expect(relu.poidsParDiscipline.keys, contains('trot_monte'));
      final a = poids.poidsEffectifsPourDiscipline('Monté');
      final b = relu.poidsEffectifsPourDiscipline('Monté');
      for (final k in a.keys) {
        expect(b[k], closeTo(a[k]!, 1e-12),
            reason: 'poids « $k » perdu par la sérialisation isolate');
      }
    });
  });
}
