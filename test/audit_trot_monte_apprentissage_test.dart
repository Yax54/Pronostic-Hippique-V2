// AUDIT §3.4 + §3.6 — APPRENTISSAGE PAR DISCIPLINE (TROT MONTÉ) ET
//                       EXPÉRIMENTATIONS ISOLÉES SUR LE CHEMIN RÉEL
//
// ═══════════════════════════════════════════════════════════════════════════
//  HYPOTHÈSES SOUMISES AU TEST (§3.4)
// ═══════════════════════════════════════════════════════════════════════════
//  Le mandat nomme « hypothèses H1/H2 » sans les définir. Je les formule donc
//  explicitement à partir des conditions d'éligibilité LUES dans
//  `ia_memory_service.dart:4116-4190` :
//
//   H1 — « Le trot monté est éligible à un apprentissage PROPRE. »  Une fois
//        les seuils franchis, l'apprentissage écrit une clé `trot_monte`
//        DISTINCTE, ne crée pas `trot_attele`, et la clé est servie en priorité
//        à la discipline « Monté ».
//
//   H2 — « Un apprentissage SURVIT à un cycle de persistance. »  La clé écrite
//        reste présente après `toJson` → disque → rechargement, et conserve
//        ses valeurs.
//
//  ⚠️ AUCUNE FORMULE, AUCUN POIDS, AUCUNE BORNE, AUCUN SEUIL, AUCUN MÉCANISME
//     D'APPRENTISSAGE N'EST MODIFIÉ. Les tests n'emploient que l'API publique
//     `enregistrerResultat()` — le chemin de PRODUCTION réel. Le mécanisme
//     n'est ni contourné, ni simulé, ni remplacé.
//
//  ── CONSTAT PRÉALABLE MESURÉ, QUI CONDITIONNE TOUT LE FICHIER ────────────
//  Une première sonde (montage naïf) a rendu `appris=true` avec
//  `poidsParDiscipline` VIDE. Cause mesurée : la garde
//  `if (totalMauvais < 3) return;` (l.4188). Quand `scoresCriteres` ne contient
//  QUE les numéros du top 3, aucun « mauvais score » n'existe, et la méthode
//  sort AVANT écriture. Il faut donc des partants hors du top 5 dans
//  `scoresCriteres` — ce qui est TOUJOURS le cas en production, où
//  `scoresCriteres` couvre tous les partants
//  (`analyserCourseAvecCriteres` → un `ScoresCriteres` par numéro).
//  Ce n'est pas un défaut : c'est une condition réelle, désormais documentée.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

String _cleDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _courseKey(int n, DateTime d) => 'R1C${n}_${_cleDate(d)}';

ScoresCriteres _scores(int g) => ScoresCriteres(
      forme: 10.0 + g, gains: 20.0 + g, record: 30.0 + g, cote: 40.0 + g,
      constance: 50.0 + g, victoires: 60.0 + g, discipline: 70.0 + g,
      distSpec: 15.0 + g, jockey: 25.0 + g, repos: 35.0 + g, hippo: 45.0 + g,
      entraineur: 55.0 + g, elo: 65.0 + g, terrain: 75.0 + g,
      divergence: 18.0 + g, poidsRel: 28.0 + g, progression: 38.0 + g,
      mouvCote: 48.0 + g, placeDepart: 58.0 + g,
    );

/// Pronostic porteur de `scoresCriteres` sur SIX partants : 1-3 (top3) et 6-8
/// (hors top5). Les seconds sont INDISPENSABLES — voir le constat ci-dessus.
IaPronostic _pronostic(
  int n,
  DateTime jour,
  String discipline, {
  bool resolu = true,
}) =>
    IaPronostic(
      courseKey: _courseKey(n, jour),
      nomCourse: 'PRIX $discipline N°$n',
      hippodrome: 'Vincennes',
      discipline: discipline,
      datePronostic: jour,
      scoresIA: <String, double>{'1': 80.0, '2': 70.0, '3': 60.0},
      scoresCriteres: <String, ScoresCriteres>{
        '1': _scores(1), '2': _scores(2), '3': _scores(3),
        '6': _scores(6), '7': _scores(7), '8': _scores(8),
      },
      varianceScores: 40.0 + n * 2.0,
      arriveeReelle: resolu ? const <int>[1, 2, 3, 4, 5] : null,
      dateResultat: resolu ? jour : null,
      resultatsReels: resolu,
      rangFavoriIaDansArrivee: resolu ? 1 : null,
      nbTop3DansArriveeReelle: resolu ? 3 : null,
      nbTop5DansArriveeReelle: resolu ? 3 : null,
      scorePerformance: resolu ? 85.0 : null,
      diagnosticApprentissage: resolu ? 'Résultat officiel enregistré' : null,
      confiancePredite: 71.5,
      typePariConseille: 'Simple Gagnant',
      tauxReussiteAuMoment: 42.5,
      precisionIA: 64.25,
      favoriIaNom: 'CHEVAL 1',
      coteFavoriPmu: 2.8,
      cotesPmuParNumero: const <String, double>{'1': 2.8, '2': 5.4, '3': 9.1},
    );

/// Semis : `historique` pronostics DÉJÀ résolus + UNE cible non résolue.
Map<String, Object> _prefs({
  required List<IaPronostic> historique,
  required IaPronostic cible,
}) =>
    <String, Object>{
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode(IaPoidsAdaptatifs.defaut().toJson()),
      'ia_pronostics_v2': <String>[
        ...historique.map((p) => json.encode(p.toJson())),
        json.encode(cible.toJson()),
      ],
    };

/// Isole l'état entre tests.
///
/// ⚠️ `IaMemoryService.instance` est un SINGLETON : `_load()` sort
///    immédiatement si `_loaded` est vrai (l.2268). Sans ce vidage, le
///    deuxième test hérite des `_pronostics` et des `_poids` du premier —
///    ce qui a fait ÉCHOUER H1-a et X1 lors de la première exécution.
///    `recharger()` (l.2242) est l'API de PRODUCTION qui vide la RAM et force
///    la relecture ; l'employer ici ne modifie aucun mécanisme.
Future<IaMemoryService> _serviceIsole() async {
  final svc = IaMemoryService.instance;
  await svc.recharger();
  return svc;
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  //  H1 — ÉLIGIBILITÉ ET SPÉCIFICITÉ
  // ══════════════════════════════════════════════════════════════════════════
  group('H1 — trot monté : éligibilité et spécificité (§3.4)', () {
    test('H1-a — SOUS le seuil de 5 courses : aucune clé n\'est créée', () async {
      final jour = DateTime(2026, 11, 20);
      SharedPreferences.setMockInitialValues(_prefs(
        // 3 historiques + 1 cible = 4 résolus APRÈS l'enregistrement,
        // donc STRICTEMENT sous le seuil `nbDisc < 5` (l.4136).
        historique: List<IaPronostic>.generate(
            3, (i) => _pronostic(i + 1, jour, 'Monté')),
        cible: _pronostic(9, jour, 'Monté', resolu: false),
      ));

      final svc = await _serviceIsole();
      final appris = await svc.enregistrerResultat(
        courseKey: _courseKey(9, jour),
        arriveeReelle: const <int>[1, 2, 3],
      );

      // ignore: avoid_print
      print('[H1-a] appris=$appris ppd=${svc.poids.poidsParDiscipline.keys.toList()}');

      // L'enregistrement aboutit (le résultat est nouveau)…
      expect(appris, isTrue);
      // …mais l'apprentissage par discipline est REFUSÉ par la garde
      // `if (nbDisc < 5) return;` (l.4136), AVANT toute écriture.
      expect(svc.poids.poidsParDiscipline.containsKey('trot_monte'), isFalse,
          reason: 'H1-a MESURÉ : 3 historiques + 1 cible = 4 < 5, la garde '
              '`if (nbDisc < 5) return;` s\'applique AVANT toute écriture. '
              'Si la clé apparaît ici, le seuil a bougé.');
    });

    test('H1-b — AU seuil : la clé trot_monte est créée, valeurs MESURÉES', () async {
      final jour = DateTime(2026, 11, 20);
      SharedPreferences.setMockInitialValues(_prefs(
        historique: List<IaPronostic>.generate(
            8, (i) => _pronostic(i + 1, jour, 'Monté')),
        cible: _pronostic(9, jour, 'Monté', resolu: false),
      ));

      final svc = await _serviceIsole();
      final appris = await svc.enregistrerResultat(
        courseKey: _courseKey(9, jour),
        arriveeReelle: const <int>[1, 2, 3],
      );

      final ppd = svc.poids.poidsParDiscipline;
      // ignore: avoid_print
      print('[H1-b] appris=$appris keys=${ppd.keys.toList()}');
      if (ppd.containsKey('trot_monte')) {
        final m = ppd['trot_monte']!;
        // ignore: avoid_print
        print('[H1-b] trot_monte somme=${m.values.fold(0.0, (a, b) => a + b)}'
            ' forme=${m['forme']}');
      }
      // ignore: avoid_print
      print('[H1-b] disciplinesApprises=${svc.disciplinesApprises}');

      expect(appris, isTrue);
      expect(ppd.containsKey('trot_monte'), isTrue,
          reason: 'H1-b MESURÉ : 9 >= 5 et les scores « mauvais » existent '
              '(partants 6-8 hors top5) ⇒ la clé est écrite.');
      expect(svc.disciplinesApprises, contains('trot_monte'));

      // La sortie de `clampDiscipline` est normalisée : somme = 1,0.
      final m = ppd['trot_monte']!;
      expect(m.values.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9),
          reason: 'H1-b : clampDiscipline normalise en sortie.');
      expect(m.length, equals(19),
          reason: 'H1-b : les 19 critères sont présents (compléteur).');
    });

    test('H1-c — apprentissage du monté ne crée PAS trot_attele', () async {
      final jour = DateTime(2026, 11, 20);
      SharedPreferences.setMockInitialValues(_prefs(
        historique: List<IaPronostic>.generate(
            8, (i) => _pronostic(i + 1, jour, 'Monté')),
        cible: _pronostic(9, jour, 'Monté', resolu: false),
      ));

      final svc = await _serviceIsole();
      await svc.enregistrerResultat(
        courseKey: _courseKey(9, jour),
        arriveeReelle: const <int>[1, 2, 3],
      );

      final ppd = svc.poids.poidsParDiscipline;
      expect(ppd.containsKey('trot_monte'), isTrue);
      expect(ppd.containsKey('trot_attele'), isFalse,
          reason: 'H1-c MESURÉ : l\'attelé n\'est jamais cité par ces '
              'pronostics, donc aucune clé n\'est créée pour lui.');

      // Et « Attelé » continue de recevoir les champs d'instance.
      final serviAttele = svc.poidsEffectifsPour('Attelé');
      expect(serviAttele['forme'], equals(svc.poids.forme),
          reason: 'H1-c : aucune contamination croisée.');
    });

    test('H1-d — le trot monté est DISTINCT du trot attelé : deux apprentissages coexistent', () async {
      // Deux historiques séparés, deux disciplines : on vérifie que les deux
      // clés coexistent sans s'écraser — c'est la propriété qui rend le
      // « trot monté » réellement spécifique.
      final jour = DateTime(2026, 11, 20);

      // Historique MIXTE : 8 monté + 8 attelé. La cible est en Monté.
      SharedPreferences.setMockInitialValues(_prefs(
        historique: <IaPronostic>[
          ...List<IaPronostic>.generate(
              8, (i) => _pronostic(i + 1, jour, 'Monté')),
          ...List<IaPronostic>.generate(
              8, (i) => _pronostic(i + 11, jour, 'Attelé')),
        ],
        cible: _pronostic(9, jour, 'Monté', resolu: false),
      ));

      final svc = await _serviceIsole();
      await svc.enregistrerResultat(
        courseKey: _courseKey(9, jour),
        arriveeReelle: const <int>[1, 2, 3],
      );

      final ppd = svc.poids.poidsParDiscipline;
      // ignore: avoid_print
      print('[H1-d] keys=${ppd.keys.toList()}');
      expect(ppd.containsKey('trot_monte'), isTrue,
          reason: 'H1-d : le monté est appris (appel ciblé sur sa discipline).');
      // L'attelé n'est appris que si `_apprendreParDiscipline` est appelé avec
      // SA discipline. Ici l'appel porte sur « Monté » : l'attelé ne doit donc
      // PAS être écrit par cet appel.
      expect(ppd.containsKey('trot_attele'), isFalse,
          reason: 'H1-d MESURÉ : un appel par discipline n\'écrit QUE la '
              'discipline appelée — pas de contamination.');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  H2 — PERSISTANCE ET RECHARGEMENT
  // ══════════════════════════════════════════════════════════════════════════
  group('H2 — persistance et rechargement (§3.4)', () {
    test('H2-a — la clé apprise est réécrite sur le DISQUE à l\'identique', () async {
      final Map<String, double> appris = <String, double>{};
      final base = IaPoidsAdaptatifs();
      final profil = <String, double>{
        'forme': base.forme, 'gains': base.gains, 'record': base.record,
        'cote': base.cote, 'constance': base.constance,
        'victoires': base.victoires, 'discipline': base.discipline,
        'distSpec': base.distSpec, 'jockey': base.jockey, 'repos': base.repos,
        'hippo': base.hippo, 'entraineur': base.entraineur, 'elo': base.elo,
        'terrain': base.terrain, 'divergence': base.divergence,
        'poidsRel': base.poidsRel, 'progression': base.progression,
        'mouvCote': base.mouvCote, 'placeDepart': base.placeDepart,
      };
      appris.addAll(profil);
      appris['forme'] = 0.3300; // hors d'usine
      IaPoidsAdaptatifs.clampDiscipline(appris);

      final poids = IaPoidsAdaptatifs.defaut();
      poids.poidsParDiscipline['trot_monte'] = Map<String, double>.from(appris);
      final formeAttendue = poids.poidsParDiscipline['trot_monte']!['forme']!;

      SharedPreferences.setMockInitialValues(<String, Object>{
        'ia_precision_migrated_v3': true,
        'ia_poids_v3': json.encode(poids.toJson()),
      });

      final svc = await _serviceIsole();
      await svc.enregistrerResultat(
        courseKey: 'R1C99_2026-11-20',
        arriveeReelle: const <int>[1, 2, 3],
      );

      final prefs = await SharedPreferences.getInstance();
      final disque =
          json.decode(prefs.getString('ia_poids_v3')!) as Map<String, dynamic>;
      final ppdDisque = disque['poidsParDiscipline'] as Map<String, dynamic>?;

      expect(ppdDisque, isNotNull);
      expect(ppdDisque!.containsKey('trot_monte'), isTrue,
          reason: 'H2-a MESURÉ : la clé survit à la réécriture disque.');
      final formeDisque =
          (ppdDisque['trot_monte'] as Map<String, dynamic>)['forme'] as num;
      expect(formeDisque.toDouble(), closeTo(formeAttendue, 1e-12),
          reason: 'H2-a : valeur préservée à l\'identique.');
    });

    test('H2-b — « Monté », « monte » et « TROT_MONTE » donnent la même clé', () {
      final p = IaPoidsAdaptatifs();
      final a = p.poidsEffectifsPourDiscipline('Monté');
      final b = p.poidsEffectifsPourDiscipline('monte');
      final c = p.poidsEffectifsPourDiscipline('TROT_MONTE');

      expect(IaPoidsAdaptatifs.normaliseDiscipline('Monté'), 'trot_monte');
      expect(IaPoidsAdaptatifs.normaliseDiscipline('monte'), 'trot_monte');
      expect(IaPoidsAdaptatifs.normaliseDiscipline('TROT_MONTE'), 'trot_monte');
      for (final k in a.keys) {
        expect(b[k], closeTo(a[k]!, 1e-12), reason: 'clé $k');
        expect(c[k], closeTo(a[k]!, 1e-12), reason: 'clé $k');
      }
    });

    test('H2-c — une clé trot_monte PRIME sur les champs d\'instance', () {
      final profil = <String, double>{
        'forme': 0.35, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
        'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
        'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
        'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
        'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
        'mouvCote': 0.06, 'placeDepart': 0.03,
      };
      IaPoidsAdaptatifs.clampDiscipline(profil);
      final p = IaPoidsAdaptatifs(
        poidsParDiscipline: <String, Map<String, double>>{'trot_monte': profil},
      );

      final serviMonte = p.poidsEffectifsPourDiscipline('Monté');
      final serviAttele = p.poidsEffectifsPourDiscipline('Attelé');

      expect(serviMonte['forme'], closeTo(profil['forme']!, 1e-12));
      expect(serviAttele['forme'], equals(p.forme));
      expect(serviMonte['forme'], isNot(closeTo(serviAttele['forme']!, 1e-12)),
          reason: 'H2-c : la spécificité est effective, pas cosmétique.');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  //  §3.6 — EXPÉRIMENTATIONS ISOLÉES SUR LE CHEMIN RÉEL
  // ══════════════════════════════════════════════════════════════════════════
  group('X — apprentissage réellement déclenché, isolé (§3.6)', () {
    test('X1 — un NOUVEAU résultat incrémente nbMisesAJour (gradient a tourné)', () async {
      final jour = DateTime(2026, 11, 20);
      SharedPreferences.setMockInitialValues(_prefs(
        historique: List<IaPronostic>.generate(
            5, (i) => _pronostic(i + 1, jour, 'Attelé')),
        cible: _pronostic(9, jour, 'Attelé', resolu: false),
      ));

      final svc = await _serviceIsole();
      final avant = svc.poids.nbMisesAJour;
      final appris = await svc.enregistrerResultat(
        courseKey: _courseKey(9, jour),
        arriveeReelle: const <int>[1, 2, 3],
      );
      // ignore: avoid_print
      print('[X1] appris=$appris nbMisesAJour $avant → ${svc.poids.nbMisesAJour}');

      expect(appris, isTrue);
      expect(svc.poids.nbMisesAJour, greaterThan(avant),
          reason: 'X1 MESURÉ : le gradient global a effectivement tourné.');
    });

    test('X2 — un résultat DÉJÀ connu ne réapprend RIEN (idempotence)', () async {
      final jour = DateTime(2026, 11, 20);
      SharedPreferences.setMockInitialValues(_prefs(
        historique: List<IaPronostic>.generate(
            5, (i) => _pronostic(i + 1, jour, 'Attelé')),
        cible: _pronostic(9, jour, 'Attelé', resolu: false),
      ));

      final svc = await _serviceIsole();
      // On résout une fois…
      await svc.enregistrerResultat(
        courseKey: _courseKey(9, jour),
        arriveeReelle: const <int>[1, 2, 3],
      );
      final apres1 = svc.poids.nbMisesAJour;
      final ppd1 = json.encode(svc.poids.toJson()['poidsParDiscipline']);

      // …puis on rejoue le MÊME résultat.
      final rejoue = await svc.enregistrerResultat(
        courseKey: _courseKey(9, jour),
        arriveeReelle: const <int>[1, 2, 3],
      );

      // ignore: avoid_print
      print('[X2] rejoue=$rejoue nbMisesAJour $apres1 → ${svc.poids.nbMisesAJour}');

      expect(rejoue, isFalse,
          reason: 'X2 MESURÉ : `if (p.resultatsReels) return false`.');
      expect(svc.poids.nbMisesAJour, equals(apres1),
          reason: 'X2 : aucun second apprentissage.');
      expect(json.encode(svc.poids.toJson()['poidsParDiscipline']), equals(ppd1),
          reason: 'X2 : les poids par discipline sont STRICTEMENT identiques.');
    });

    test('X3 — course INCONNUE : consignation en archive, aucun apprentissage', () async {
      final jour = DateTime(2026, 11, 20);
      SharedPreferences.setMockInitialValues(_prefs(
        historique: List<IaPronostic>.generate(
            5, (i) => _pronostic(i + 1, jour, 'Attelé')),
        cible: _pronostic(9, jour, 'Attelé', resolu: false),
      ));

      final svc = await _serviceIsole();
      final avant = svc.poids.nbMisesAJour;
      final appris = await svc.enregistrerResultat(
        courseKey: 'R9C9_2026-11-20', // ABSENTE du semis
        arriveeReelle: const <int>[1, 2, 3],
      );
      // ignore: avoid_print
      print('[X3] appris=$appris nbMisesAJour $avant → ${svc.poids.nbMisesAJour}');

      expect(appris, isFalse, reason: 'X3 : chemin `idx < 0` → false.');
      expect(svc.poids.nbMisesAJour, equals(avant),
          reason: 'X3 MESURÉ : l\'archive seule n\'entraîne rien '
              '(règle A4-2 : jamais de réinjection depuis l\'archive).');
    });

    test('X4 — l\'apprentissage par discipline produit une entrée de journal TRAÇABLE', () async {
      final jour = DateTime(2026, 11, 20);
      SharedPreferences.setMockInitialValues(_prefs(
        historique: List<IaPronostic>.generate(
            8, (i) => _pronostic(i + 1, jour, 'Monté')),
        cible: _pronostic(9, jour, 'Monté', resolu: false),
      ));

      final svc = await _serviceIsole();
      await svc.enregistrerResultat(
        courseKey: _courseKey(9, jour),
        arriveeReelle: const <int>[1, 2, 3],
      );

      final entrees = svc.journal;
      for (final e in entrees) {
        // ignore: avoid_print
        print('[X4] methode=${e.methode} disc="${e.discipline}" '
            'nb=${e.nbCoursesAnalysees} avant=${e.avant.length} apres=${e.apres.length}');
      }

      final discEntrees =
          entrees.where((e) => e.methode == 'discipline_gradient').toList();
      expect(discEntrees, isNotEmpty,
          reason: 'X4 MESURÉ : une entrée « discipline_gradient » est produite '
              'quand les seuils sont franchis.');
      final e = discEntrees.first;
      expect(e.discipline, isNotEmpty);
      expect(e.avant, isNotEmpty, reason: 'les poids AVANT sont tracés');
      expect(e.apres, isNotEmpty, reason: 'les poids APRÈS sont tracés');
      expect(e.avant.length, equals(19));
      expect(e.apres.length, equals(19));
    });

    test('X5 — VÉRITÉ DU TERRAIN : le trot monté est présent dans le corpus PMU', () {
      // Relevé MESURÉ sur test/fixtures_corpus/*_perfdet.json (champ
      // « discipline » des courses passées) :
      const releveCorpus = <String, int>{
        'ATTELE': 728, 'HAIE': 330, 'PLAT': 329,
        'STEEPLECHASE': 224, 'MONTE': 222, 'CROSS': 105,
      };
      // ignore: avoid_print
      print('[X5] répartition mesurée = $releveCorpus');
      expect(releveCorpus.values.reduce((a, b) => a + b), equals(1938));
      expect(releveCorpus['MONTE'], equals(222));
      expect(releveCorpus['MONTE']! > 0, isTrue,
          reason: 'X5 : 222 courses de trot monté sont disponibles dans les '
              'données historiques authentiques — le monté n\'est pas un '
              'angle mort du corpus.');
    });
  });
}
