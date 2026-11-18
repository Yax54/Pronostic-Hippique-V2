// ═══════════════════════════════════════════════════════════════════════════
//  A7 / 3.3-B2-b — PRÉPARATION ET VALIDATION DE L'IDENTITÉ DE COURSE
//
//  OBJET DU LOT
//  ────────────
//  Transformer une `courseKey` en identité EXPLOITABLE (`numR`, `numC`, date
//  ISO, discipline normalisée) ou REFUSER toute identité partielle, sans
//  jamais toucher au comportement ELO existant.
//
//  CE QUE CE LOT NE FAIT **PAS** — À LIRE AVANT TOUTE INTERPRÉTATION
//  ─────────────────────────────────────────────────────────────────
//  • il n'accède PAS à `elo_registre_v3` : le registre n'est ni lu, ni écrit,
//    ni supprimé, ni migré. Aucun test de ce fichier ne sème cette clé ;
//  • il ne décide PAS de la signification de `EntreeRegistreElo.cle` — c'est
//    réservé à B2-d. Aucun test n'asserte de « clé de journal » composite ;
//  • il ne modifie AUCUN calcul ELO, aucun coefficient K, aucun mécanisme IA,
//    ni le reset, ni la FIFO, ni les backups ;
//  • ⚠️ DEPUIS 3.3-B2-e, LES RATINGS NE SONT PLUS MIS À JOUR SANS IDENTITÉ.
//    §6 de la consigne : « Ne pas appliquer de mise à jour ELO non journalisée
//    lorsque l'identité est absente ou invalide. » C'est l'inverse du contrat
//    B2-b, qui appliquait l'ELO avec ou sans clé. Les tests du groupe B2b-6
//    ont été réécrits en conséquence : ce qu'ils prouvent désormais est
//    « le refus ne mute RIEN » ET « avec une identité valide, le résultat est
//    celui, inchangé, des formules ELO ».
//
//  MESURE PRÉALABLE, IMPORTANTE POUR LA LECTURE DES ASSERTIONS
//  ───────────────────────────────────────────────────────────
//  `setUp()` appelle `EloService.init()` → `_charger()`, qui écrit
//  `elo_orphelins_purges_v1`. Toute assertion sur le CONTENU du journal du
//  store est donc bornée par un index relevé au début du test — jamais absolue.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/models/elo_registre_v3.dart'
    show OrigineRegistreElo;
import 'package:pronostic_hippique/services/elo_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  STORE INSTRUMENTÉ — même contrat que B1 / B2-a (copie assumée)
// ───────────────────────────────────────────────────────────────────────────

class _Store extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};
  final List<String> journal = <String>[];

  String? cleSuspendue;
  Completer<void>? _entreeSuspendue;
  Completer<void>? _verrouSuspendu;

  @override
  Future<bool> clear() async {
    journal.add('CLEAR');
    _valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    journal.add('GETALL');
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    journal.add('REM $key');
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add('SET-ENTREE $key');
    // ÉGALITÉ STRICTE — jamais `contains`.
    if (cleSuspendue != null && key == cleSuspendue) {
      final entree = _entreeSuspendue;
      _entreeSuspendue = null;
      if (entree != null && !entree.isCompleted) entree.complete();
      final verrou = _verrouSuspendu;
      if (verrou != null) await verrou.future;
    }
    _valeurs[key] = value;
    journal.add('SET-OK $key');
    return true;
  }

  Future<void> armerSuspension(String cle) {
    final entree = Completer<void>();
    _entreeSuspendue = entree;
    cleSuspendue = cle;
    _verrouSuspendu = Completer<void>();
    return entree.future;
  }

  void libererSuspension() {
    final v = _verrouSuspendu;
    _verrouSuspendu = null;
    cleSuspendue = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void desarmer() {
    cleSuspendue = null;
    _entreeSuspendue = null;
    final v = _verrouSuspendu;
    _verrouSuspendu = null;
    if (v != null && !v.isCompleted) v.complete();
  }

  void semer(String cle, Object valeur) => _valeurs['flutter.$cle'] = valeur;
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');

  /// Suppression avec le nom de clé NU, comme `semer`/`contient`.
  ///
  /// ⚠️ MESURE : `SharedPreferences.remove()` transmet à la plateforme la clé
  ///    DÉJÀ PRÉFIXÉE (`flutter.<clé>`). Appeler `remove('elo_ratings_v2')`
  ///    ne supprime donc RIEN — c'est un no-op silencieux. Cette méthode
  ///    n'existe que pour que la simulation d'un reset soit fidèle.
  Future<bool> supprimer(String cle) => remove('flutter.$cle');

  Set<String> clesEcritesDepuis(int index) => journal
      .skip(index)
      .where((e) => e.startsWith('SET-OK '))
      .map((e) => e.substring('SET-OK '.length))
      .toSet();
}

// Type privé volontaire : le dispositif reste local à ce fichier.
// ignore: library_private_types_in_public_api
late _Store store;

void _installerStore() {
  store = _Store();
  SharedPreferencesStorePlatform.instance = store;
  SharedPreferences.resetStatic();
}

/// Vidage BORNÉ de la boucle d'événements (nombre de tours, jamais une durée).
Future<void> _laisserProgresser([int tours = 24]) async {
  for (var i = 0; i < tours; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ── Constantes partagées avec les tests B1 / B2-a ───────────────────────────

const String kDisc = 'Trot Attelé';
const String kCleElo = 'elo_ratings_v2';
const String kCleTs = 'elo_ratings_v2_ts';
const String kJournalElo = 'flutter.$kCleElo';

ZtPartant _partant(int num) => ZtPartant(
      numero: '$num',
      nom: 'CHEVAL_$num',
      driver: 'DRIVER_$num',
      entraineur: 'ENTR_$num',
      proprietaire: 'PROP_$num',
      gains: '${num * 10000}',
      record: '1\'1${num % 10}"0',
      musique: '1a2a3a4a5a',
      cote: '4.0',
      ageSexe: '5 M',
      poids: 57.0 + num,
      placeDepartInt: num,
      joursRepos: 10 + num,
      hippodromeActuel: 'VINCENNES',
      statsJockeyCsv: 'JOCKEY_$num|15|40|12',
      statsHippodromeCsv: 'VINCENNES|20|45|15',
      statsEntraineurCsv: 'ENTR_$num|12|33|8',
      eloRating: 1500.0,
      eloNbCourses: 20,
      eloVariationMois: 5.0,
      statsTerrainCsv: 'bon|6|2|4',
      gainsDernierAn: num * 5000,
    );

final List<ZtPartant> kPartants = List.generate(6, (i) => _partant(i + 1));
const List<int> kArrivee = <int>[1, 2, 3];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _installerStore();
    await EloService.init();
    EloService.instance.viderMemoirePourResetComplet();
  });

  tearDown(() {
    store.desarmer();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2b-1 — CLÉ ABSENTE : AUCUNE IDENTITÉ, AUCUN EFFET SUR L'ELO
  //
  //  Exigence 1 (paramètre optionnel, appels existants intacts) et exigence 5
  //  (clé absente ⇒ aucune identité exploitable) du mandat.
  // ═════════════════════════════════════════════════════════════════════════
  group('B2b-1 — clé absente', () {
    test('B2b-1a — sans `courseKey`, aucune identité n\'est publiée et l\'ELO '
        'est mis à jour normalement', () async {
      final elo = EloService.instance;

      expect(elo.derniereIdentiteCourse, isNull,
          reason: 'TÉMOIN : avant toute opération, aucune identité');

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
      );
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2b-1a] etat=${etat.name} | identite='
          '${elo.derniereIdentiteCourse} | chevaux=${elo.nbChevauxSuivis}');

      // ⚠️ A7 / 3.3-B2-e — CONTRAT MODIFIÉ, ET VOULU (§6).
      //   B2-e exige qu'aucune arrivée ne soit appliquée sans identité : sans
      //   `courseKey`, aucune entrée de registre ne peut être journalisée, donc
      //   la mise à jour ELO est REFUSÉE. L'assertion sur l'IDENTITÉ est
      //   conservée telle quelle ; seule l'assertion sur l'EFFET change.
      expect(etat, EtatPersistanceElo.nonTentee,
          reason: 'B2-e : sans identité, AUCUNE application (refus explicite)');
      expect(elo.dernierResultatMiseAJour?.motifRefus,
          MotifRefusApplicationElo.identiteNonExploitable,
          reason: 'le motif du refus doit être NOMMÉ, pas silencieux');
      expect(elo.derniereIdentiteCourse, isNull,
          reason: 'clé absente ⇒ AUCUNE identité. Aucune clé fictive, aucun '
              'R0C0, aucune date inventée (D-B2-1)');
      expect(elo.nbChevauxSuivis, 0,
          reason: 'B2-e : aucune mutation RAM, donc aucun cheval suivi');
    });

    test('B2b-1b — `courseKey: null` explicite et clé vide/blanche : aucune '
        'identité', () async {
      final elo = EloService.instance;

      for (final Object? cle in <Object?>[null, '', '   ']) {
        final etat = await elo.mettreAJourApresArrivee(
          arrivee: kArrivee,
          partants: kPartants,
          discipline: kDisc,
          courseKey: cle as String?,
        );
        await _laisserProgresser();

        // ignore: avoid_print
        print('[B2b-1b] cle=${cle == null ? "null" : '"$cle"'} '
            'etat=${etat.name} identite=${elo.derniereIdentiteCourse}');

        expect(etat, EtatPersistanceElo.nonTentee,
            reason: 'B2-e : ni `null`, ni vide, ni blanche ⇒ identité nulle '
                '⇒ aucune application');
        expect(elo.derniereIdentiteCourse, isNull,
            reason: 'ni `null`, ni vide, ni blanche ne produisent d\'identité');
      }
      expect(elo.nbChevauxSuivis, 0,
          reason: 'B2-e : aucun refus ne mute les ratings');
    });

    test('B2b-1c — une identité d\'opération PRÉCÉDENTE n\'est jamais laissée '
        'en observation', () async {
      final elo = EloService.instance;

      // 1) opération AVEC clé valide → identité publiée.
      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R3C4_23042026',
      );
      await _laisserProgresser();
      expect(elo.derniereIdentiteCourse, isNotNull,
          reason: 'TÉMOIN : la première opération a bien publié une identité');
      expect(elo.derniereIdentiteCourse!.numR, 3);

      // 2) opération SANS clé → l'identité précédente doit DISPARAÎTRE.
      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
      );
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.nonTentee,
          reason: 'B2-e : sans identité, aucune application');
      expect(elo.derniereIdentiteCourse, isNull,
          reason: 'ANTI-RÉSIDU : sans réinitialisation, un test croirait '
              'qu\'une identité a été produite là où il n\'y en a pas');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2b-2 — CLÉS VALIDES DANS LES DEUX FORMATS RECONNUS
  //
  //  Exigence 2 (validation stricte) et exigence 3 (deux formats déjà
  //  reconnus par `dateDepuisCourseKey`, sans invention) du mandat.
  // ═════════════════════════════════════════════════════════════════════════
  group('B2b-2 — clés valides, deux formats', () {
    test('B2b-2a — format `JJMMAAAA` : constituants exacts', () {
      final id = IdentiteCourseElo.tenter(
          courseKey: 'R1C5_23042026', discipline: kDisc);

      expect(id, isNotNull);
      expect(id!.numR, 1);
      expect(id.numC, 5);
      expect(id.date, '2026-04-23',
          reason: 'date ISO rendue par `dateDepuisCourseKey`, jamais '
              'reformatée depuis une autre source');
      expect(id.courseKey, 'R1C5_23042026',
          reason: 'la clé d\'origine est conservée TELLE QUELLE');
      expect(id.discipline, 'TROT_ATTELE');
    });

    test('B2b-2b — format ISO `AAAA-MM-JJ` : même résultat', () {
      final id = IdentiteCourseElo.tenter(
          courseKey: 'R1C1_2026-01-05', discipline: kDisc);

      expect(id, isNotNull);
      expect(id!.numR, 1);
      expect(id.numC, 1);
      expect(id.date, '2026-01-05',
          reason: 'le format ISO est un format RÉELLEMENT présent dans les '
              'données (v26/v27) : il ne doit pas être rejeté');
    });

    test('B2b-2c — les deux formats produisent la MÊME identité', () {
      final a = IdentiteCourseElo.tenter(
          courseKey: 'R1C1_23042026', discipline: kDisc)!;
      final b = IdentiteCourseElo.tenter(
          courseKey: 'R1C1_2026-04-23', discipline: kDisc)!;

      // ignore: avoid_print
      print('[B2b-2c] a=$a | b=$b');

      expect(a.numR, b.numR);
      expect(a.numC, b.numC);
      expect(a.date, b.date);
      expect(a.discipline, b.discipline);
    });

    test('B2b-2d — suffixes tolérés (`_ia`, millisecondes) et `trim()`', () {
      final ia = IdentiteCourseElo.tenter(
          courseKey: 'R99C1005_23042026_ia', discipline: kDisc);
      final ms = IdentiteCourseElo.tenter(
          courseKey: 'R4C7_23042026_1745000111', discipline: kDisc);
      final espace = IdentiteCourseElo.tenter(
          courseKey: '  R2C9_01012026  ', discipline: kDisc);

      expect(ia, isNotNull, reason: 'suffixe `_ia` toléré (déjà dans l\'app)');
      expect(ia!.numR, 99);
      expect(ia.numC, 1005);
      expect(ia.date, '2026-04-23');

      expect(ms, isNotNull, reason: 'suffixe millisecondes toléré');
      expect(ms!.date, '2026-04-23');

      expect(espace, isNotNull, reason: '`trim()` appliqué');
      expect(espace!.courseKey, 'R2C9_01012026',
          reason: 'la clé mémorisée est la forme `trim()`ée');
      expect(espace.date, '2026-01-01');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2b-3 — RÉUNION / COURSE INVALIDES : AUCUNE IDENTITÉ
  //
  //  Exigence 2 : `numR` et `numC` STRICTEMENT positifs.
  // ═════════════════════════════════════════════════════════════════════════
  group('B2b-3 — réunion / course invalides', () {
    test('B2b-3a — `R0C0`, `R0C5`, `R5C0`, `R00C5` sont REFUSÉS', () {
      for (final cle in <String>[
        'R0C0_23042026',
        'R0C5_23042026',
        'R5C0_23042026',
        'R00C5_23042026',
        'R0C0_2026-04-23',
      ]) {
        final id = IdentiteCourseElo.tenter(courseKey: cle, discipline: kDisc);
        // ignore: avoid_print
        print('[B2b-3a] $cle → ${id ?? "REFUSÉ"}');
        expect(id, isNull,
            reason: '$cle : numR et numC doivent être STRICTEMENT positifs — '
                'aucune identité pour une réunion ou une course 0');
      }
    });

    test('B2b-3b — clés hors format REFUSÉES', () {
      for (final cle in <String>[
        'KEY_PERSONNALISEE',
        'R1C3',
        'R1C3_',
        'RC_23042026',
        'R1C_23042026',
        '',
        '   ',
      ]) {
        final id = IdentiteCourseElo.tenter(courseKey: cle, discipline: kDisc);
        // ignore: avoid_print
        print('[B2b-3b] "$cle" → ${id ?? "REFUSÉ"}');
        expect(id, isNull, reason: '"$cle" ne porte pas d\'identité complète');
      }
    });

    test('B2b-3c — une clé REFUSÉE ne publie aucune identité via le service',
        () async {
      final elo = EloService.instance;

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R0C0_23042026',
      );
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.nonTentee,
          reason: 'B2-e (§6) : une identité REFUSÉE est une identité ABSENTE '
              '⇒ aucune application non journalisée');
      expect(elo.dernierResultatMiseAJour?.motifRefus,
          MotifRefusApplicationElo.identiteNonExploitable);
      expect(elo.derniereIdentiteCourse, isNull);
      expect(elo.nbChevauxSuivis, 0);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2b-4 — DATE IMPOSSIBLE : AUCUNE IDENTITÉ, AUCUNE DATE INVENTÉE
  // ═════════════════════════════════════════════════════════════════════════
  group('B2b-4 — date impossible', () {
    test('B2b-4a — dates calendairement impossibles REFUSÉES', () {
      for (final cle in <String>[
        'R1C1_31022026', // 31 février
        'R1C1_29022025', // 29 février d'une année non bissextile
        'R1C1_32012026', // 32 janvier
        'R1C1_00012026', // jour 0
        'R1C1_01132026', // mois 13
        'R1C1_2026-02-31', // ISO impossible
        'R1C1_2026-13-01', // ISO mois 13
      ]) {
        final id = IdentiteCourseElo.tenter(courseKey: cle, discipline: kDisc);
        // ignore: avoid_print
        print('[B2b-4a] $cle → ${id ?? "REFUSÉ"}');
        expect(id, isNull,
            reason: '$cle n\'est pas une date réelle du calendrier');
      }
    });

    test('B2b-4b — aucune année n\'est ajoutée comme borne (règle inventée)',
        () {
      // 2028 est bissextile : 29 février doit être ACCEPTÉ. Ce test protège
      // contre l'ajout d'un plancher/plafond d'année, que `date_utils.dart`
      // refuse explicitement.
      final bissextile = IdentiteCourseElo.tenter(
          courseKey: 'R1C1_29022028', discipline: kDisc);
      final ancienne = IdentiteCourseElo.tenter(
          courseKey: 'R1C1_01011990', discipline: kDisc);

      expect(bissextile, isNotNull,
          reason: '29/02/2028 est une date réelle : elle doit passer');
      expect(bissextile!.date, '2028-02-29');
      expect(ancienne, isNotNull,
          reason: 'aucune borne d\'année n\'est inventée par ce lot');
      expect(ancienne!.date, '1990-01-01');
    });

    test('B2b-4c — date impossible via le service : identité nulle, ELO '
        'intact', () async {
      final elo = EloService.instance;

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R1C1_31022026',
      );
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.nonTentee,
          reason: 'B2-e : date impossible ⇒ identité nulle ⇒ aucune '
              'application (refus explicite)');
      expect(elo.derniereIdentiteCourse, isNull,
          reason: 'aucune date de remplacement n\'est JAMAIS produite');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2b-5 — DISCIPLINE NORMALISÉE PAR LA FONCTION DE PRODUCTION
  //
  //  Exigence 4 : discipline normalisée prête pour le registre. La cohérence
  //  avec les clés réellement écrites dans `_ratings` est vérifiée en 5d.
  // ═════════════════════════════════════════════════════════════════════════
  group('B2b-5 — discipline normalisée', () {
    test('B2b-5a — libellés de trot', () {
      final a = IdentiteCourseElo.tenter(
          courseKey: 'R1C1_23042026', discipline: 'Trot Attelé')!;
      final b = IdentiteCourseElo.tenter(
          courseKey: 'R1C1_23042026', discipline: 'trot attele')!;
      final c = IdentiteCourseElo.tenter(
          courseKey: 'R1C1_23042026', discipline: 'TROT MONTE')!;

      expect(a.discipline, 'TROT_ATTELE');
      expect(b.discipline, 'TROT_ATTELE',
          reason: 'casse et accents variés convergent par la fonction de prod');
      expect(c.discipline, 'TROT_MONTE');
    });

    test('B2b-5b — autres disciplines', () {
      expect(
          IdentiteCourseElo.tenter(courseKey: 'R1C1_23042026', discipline: 'Plat')
              ?.discipline,
          'PLAT');
      expect(
          IdentiteCourseElo.tenter(courseKey: 'R1C1_23042026', discipline: 'Haies')
              ?.discipline,
          'OBSTACLE_HAIE');
      expect(
          IdentiteCourseElo.tenter(
                  courseKey: 'R1C1_23042026', discipline: 'Steeple Chase')
              ?.discipline,
          'OBSTACLE_STEEPLE');
      expect(
          IdentiteCourseElo.tenter(
                  courseKey: 'R1C1_23042026', discipline: 'Cross Country')
              ?.discipline,
          'OBSTACLE_CROSS');
    });

    test('B2b-5c — discipline vide ou inconnue ⇒ `INCONNU` (valeur réelle de '
        'la normalisation, pas une invention)', () {
      expect(
          IdentiteCourseElo.tenter(courseKey: 'R1C1_23042026')?.discipline,
          'INCONNU');
      expect(
          IdentiteCourseElo.tenter(
                  courseKey: 'R1C1_23042026', discipline: 'Licorne')
              ?.discipline,
          'INCONNU');
      expect(EloService.normaliserDiscipline(''), 'INCONNU',
          reason: 'TÉMOIN : `INCONNU` est bien ce que rend la production');
    });

    test('B2b-5d — la discipline de l\'identité est EXACTEMENT celle des clés '
        'écrites dans `_ratings`', () async {
      final elo = EloService.instance;

      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R1C1_23042026',
      );
      await _laisserProgresser();

      final id = elo.derniereIdentiteCourse!;
      // La clé ELO réellement écrite est « NOM|DISC_NORM ». On vérifie que le
      // rating existe sous CETTE discipline : aucune divergence possible entre
      // l'identité préparée et les ratings mis à jour.
      final rating = elo.getRating('CHEVAL_1', discipline: kDisc);
      // ignore: avoid_print
      print('[B2b-5d] disciplineIdentite=${id.discipline} | '
          'ratingCheval1=$rating');

      expect(id.discipline, EloService.normaliserDiscipline(kDisc));
      expect(rating, isNot(1500.0),
          reason: 'le rating a bien bougé sous la discipline normalisée');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2b-6 — LE COMPORTEMENT ELO EST STRICTEMENT PRÉSERVÉ
  //
  //  Exigence 5 : « Préserver toutefois le comportement ELO existant tant que
  //  le registre n'est pas activé ». Ces tests comparent des RÉSULTATS.
  // ═════════════════════════════════════════════════════════════════════════
  group('B2b-6 — comportement ELO préservé', () {
    test('B2b-6a — sans `courseKey` : refus ; avec `courseKey` : application '
        'effective', () async {
      final elo = EloService.instance;

      // 1) SANS clé — B2-e (§6) : refusée, donc AUCUNE mutation. C'est le
      //    nouveau contrat : ce n'est plus « mêmes ratings », mais « aucune
      //    application non journalisée ». On vérifie donc l'égalité des
      //    ratings à l'état INITIAL, pas entre deux applications.
      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
      );
      await _laisserProgresser();
      final sansCle = <String, double>{
        for (final p in kPartants) p.nom: elo.getRating(p.nom, discipline: kDisc)
      };
      final chevauxSansCle = elo.nbChevauxSuivis;

      expect(sansCle.values.every((v) => v == 1500.0), isTrue,
          reason: 'B2-e : sans identité, le refus laisse tous les ratings à '
              'leur valeur par défaut');
      expect(chevauxSansCle, 0, reason: 'aucun cheval créé par un refus');

      // 2) AVEC clé valide, sur une RAM repartie de zéro. TÉMOIN indispensable :
      //    il prouve que le refus ci-dessus est causé par l'ABSENCE d'identité,
      //    et non par un service qui n'appliquerait jamais rien.
      elo.viderMemoirePourResetComplet();
      final etatAvecCle = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R1C5_23042026',
      );
      await _laisserProgresser();
      final avecCle = <String, double>{
        for (final p in kPartants) p.nom: elo.getRating(p.nom, discipline: kDisc)
      };

      // ignore: avoid_print
      print('[B2b-6a] sansCle=${sansCle.values.toList()} | '
          'avecCle=${avecCle.values.toList()}');

      expect(etatAvecCle, EtatPersistanceElo.persistee,
          reason: 'TÉMOIN : avec une identité valide, l\'application aboutit');
      expect(avecCle.values.any((v) => v != 1500.0), isTrue,
          reason: 'TÉMOIN : les ratings ont RÉELLEMENT bougé — les formules ELO '
              'sont inchangées, seule la journalisation conditionne l\'accès');
      expect(elo.nbChevauxSuivis, greaterThan(chevauxSansCle),
          reason: 'TÉMOIN : des chevaux ont été créés par l\'application');
      expect(sansCle.values.every((v) => v == 1500.0), isTrue,
          reason: 'le refus n\'a laissé AUCUNE trace dans les ratings');
    });

    test('B2b-6b — les clés écrites sont EXACTEMENT celles attendues : ratings, '
        'horodatage et registre', () async {
      final elo = EloService.instance;
      final indexAvant = store.journal.length;

      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R2C7_15062026',
      );
      await _laisserProgresser();

      final cles = store.clesEcritesDepuis(indexAvant);
      // ignore: avoid_print
      print('[B2b-6b] clés écrites=${cles.toList()..sort()}');

      // ★ B2-e : au premier passage, le registre est ABSENT du stockage. Le
      //   mandat impose de l'amorcer (l.1091-1129 de `elo_service.dart`), donc
      //   `elo_registre_v3` est écrit — c'est un fait MESURÉ, pas un oubli.
      //   Aucune AUTRE clé n'apparaît : l'ensemble est exhaustif, il n'est pas
      //   seulement minoré.
      expect(
          cles,
          <String>{kJournalElo, 'flutter.$kCleTs', 'flutter.elo_registre_v3'},
          reason: 'exactement trois clés : ratings, horodatage et registre');
      expect(store.contient('elo_registre_v3'), isTrue,
          reason: 'l\'amorçage est PERSISTÉ (condition du §6)');
      expect(cles.length, 3,
          reason: 'aucune écriture supplémentaire n\'est introduite');
    });

    test('B2b-6c — compteurs d\'écriture inchangés après une opération avec '
        'identité', () async {
      final elo = EloService.instance;
      final refusResetAvant = elo.nbRefusParReset;
      final refusGenAvant = elo.nbRefusParGeneration;
      final genAvant = elo.generationCache;

      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R1C1_23042026',
      );
      await _laisserProgresser();

      expect(elo.nbEcrituresEnCours, 0);
      expect(elo.nbEcrituresPersistantesEnCours, 0);
      expect(elo.generationCache, genAvant);
      expect(elo.nbRefusParReset, refusResetAvant);
      expect(elo.nbRefusParGeneration, refusGenAvant);
    });

    test('B2b-6d — le reset n\'est pas modifié : il vide la RAM et laisse la '
        'barrière ouverte', () async {
      final elo = EloService.instance;

      await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R1C1_23042026',
      );
      await _laisserProgresser();
      expect(elo.nbChevauxSuivis, greaterThan(0));
      expect(store.contient('elo_registre_v3'), isTrue,
          reason: 'TÉMOIN : le registre a bien été créé avant le reset');

      var effacements = 0;
      // ⚠️ Le callback reproduit le contrat de `BackupService.reinitialiserComplet`
      //    : les TROIS clés ELO du périmètre disparaissent ensemble. `_keysELO`
      //    de `backup_service.dart` l.177-200 contient bien `elo_registre_v3`
      //    (l.198) et `_toutesLesCles` (l.405) l'inclut — mesuré. Le reset de
      //    production efface donc le registre ; ce test ne fait que reproduire
      //    ce périmètre, il ne l'invente pas.
      await elo.executerResetComplet(() async {
        effacements++;
        await store.supprimer(kCleElo);
        await store.supprimer(kCleTs);
        await store.supprimer('elo_registre_v3');
      });

      expect(effacements, 1);
      expect(elo.nbChevauxSuivis, 0, reason: 'le reset a vidé la RAM');
      expect(store.contient('elo_registre_v3'), isFalse,
          reason: 'le registre et les ratings disparaissent ENSEMBLE — un '
              'registre survivant témoignerait de courses dont les ratings '
              'n\'existent plus');

      // La barrière est bien relâchée : une opération postérieure est traitée.
      // La date est ANCRÉE DANS LE PASSÉ : depuis B2-b, une clé portant une date
      // postérieure au lendemain est refusée (`datePosterieure`) — la garde
      // d'antériorité de l'étape A s'applique à toute opération, y compris
      // après un reset. Utiliser une date future testerait ce refus, pas la
      // réouverture de la barrière.
      final etat = await elo.mettreAJourApresArrivee(
        arrivee: <int>[1, 2],
        partants: <ZtPartant>[_partant(1), _partant(2)],
        discipline: kDisc,
        courseKey: 'R2C2_01012026',
      );
      await _laisserProgresser();

      expect(etat, EtatPersistanceElo.persistee);
      expect(elo.derniereIdentiteCourse, isNotNull,
          reason: 'après reset, une nouvelle opération publie SA propre '
              'identité');
      expect(elo.derniereIdentiteCourse!.numR, 2);
      // Après le reset, le registre est ABSENT : il est ré-amorcé, et la RAM
      // étant vide, c'est le Cas A (`origine: courante`) qui s'applique.
      expect(store.contient('elo_registre_v3'), isTrue,
          reason: 'le registre est ré-amorcé après le reset');
      expect(elo.dernierResultatMiseAJour?.origineAvant,
          OrigineRegistreElo.courante,
          reason: 'RAM vide ⇒ Cas A de l\'amorçage (§6) : registre courant');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  B2b-7 — UNE OPÉRATION SANS EFFET NE PUBLIE AUCUNE IDENTITÉ
  //
  //  Exigence 5, second membre : « ne produire aucune identité de journal
  //  exploitable » quand il n'y a rien à journaliser.
  // ═════════════════════════════════════════════════════════════════════════
  group('B2b-7 — opération sans effet', () {
    test('B2b-7a — `arrivee` vide ou d\'un seul élément ⇒ `nonTentee` et '
        'aucune identité', () async {
      final elo = EloService.instance;

      final vide = await elo.mettreAJourApresArrivee(
        arrivee: const <int>[],
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R1C1_23042026',
      );
      expect(vide, EtatPersistanceElo.nonTentee);
      expect(elo.derniereIdentiteCourse, isNull,
          reason: 'rien n\'est appliqué ⇒ aucune identité exploitable');

      final unSeul = await elo.mettreAJourApresArrivee(
        arrivee: const <int>[1],
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R1C1_23042026',
      );
      expect(unSeul, EtatPersistanceElo.nonTentee);
      expect(elo.derniereIdentiteCourse, isNull);
      expect(elo.nbChevauxSuivis, 0,
          reason: 'TÉMOIN : aucune mutation RAM n\'a eu lieu');
    });

    test('B2b-7b — `partants` vide ⇒ `nonTentee` et aucune identité', () async {
      final elo = EloService.instance;

      final etat = await elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: const <ZtPartant>[],
        discipline: kDisc,
        courseKey: 'R1C1_23042026',
      );

      expect(etat, EtatPersistanceElo.nonTentee);
      expect(elo.derniereIdentiteCourse, isNull);
    });

    test('B2b-7c — opération ABANDONNÉE par le contrôle G : aucune identité '
        'n\'est laissée en observation', () async {
      final elo = EloService.instance;

      // La FIFO (B1) sérialise : la 1ʳᵉ opération est retenue dans son
      // écriture, la 2ᵉ attend son tour. Un reset survenu entre-temps rend la
      // 2ᵉ périmée ⇒ contrôle G ⇒ abandon, SANS aucune identité publiée.
      final entree = store.armerSuspension(kJournalElo);
      final f1 = elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R1C1_23042026',
      );
      await entree;

      final f2 = elo.mettreAJourApresArrivee(
        arrivee: kArrivee,
        partants: kPartants,
        discipline: kDisc,
        courseKey: 'R9C9_31122026',
      );

      final reset = elo.executerResetComplet(() async {
        await store.remove(kCleElo);
        await store.remove(kCleTs);
      });

      store.libererSuspension();
      await reset;
      final etat1 = await f1;
      final etat2 = await f2;
      await _laisserProgresser();

      // ignore: avoid_print
      print('[B2b-7c] etat1=${etat1.name} | etat2=${etat2.name} | '
          'identite=${elo.derniereIdentiteCourse}');

      expect(etat2, EtatPersistanceElo.abandonneeParReset,
          reason: 'l\'opération en attente est périmée par le reset');
      expect(elo.derniereIdentiteCourse, isNull,
          reason: 'une opération abandonnée ne laisse AUCUNE identité '
              'exploitable derrière elle');
      expect(elo.nbChevauxSuivis, 0, reason: 'le reset a vidé la RAM');
    });
  });
}
