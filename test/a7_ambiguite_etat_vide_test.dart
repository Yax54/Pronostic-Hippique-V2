// ═══════════════════════════════════════════════════════════════════════════
//  A7 — DÉMONSTRATION : LE STOCKAGE `{}` EST-IL AMBIGU ?
//
//  QUESTION POSÉE (validation de l'étape 1) :
//    « Le stockage `{}` peut représenter un ancien état indéterminé, mais aussi
//      un état neuf après réinitialisation. Démontre comment distinguer ces
//      situations sans risque de double comptage ni blocage des nouvelles
//      courses. »
//
//  MÉTHODE — ce fichier ne répond PAS par un raisonnement. Il MESURE.
//  Chaque test isole un état de départ réel (clé absente, `{}`, map plate
//  legacy, enveloppe v3) et relève ce que le code de production FAIT.
//
//  STATUT DES ASSERTIONS :
//    • MESURE   — constate l'état actuel du code, y compris ses défauts.
//    • INVARIANT — propriété démontrée dont dépend l'architecture retenue
//      (option C). Si un invariant tombe, l'architecture tombe avec lui.
//
//  CE QUI N'EST PAS TESTÉ, ET POURQUOI :
//    • Aucune formule ELO n'est modifiée ni re-dérivée ici. Les invariants
//      portent sur la STRUCTURE du stockage et sur l'identité des courses.
//    • Aucun réseau, aucun apprentissage IA, aucun poids, aucun seuil.
//    • Aucune donnée réelle : stores en mémoire.
//
//  RÉSULTAT ATTENDU DE LA DÉMONSTRATION : voir les 7 groupes ci-dessous.
//  Les groupes A7-1 à A7-3 établissent que les TROIS états de départ sont
//  DISTINGUABLES sans convention inventée. Les groupes A7-5 et A7-6
//  mesurent le SEUL défaut bloquant restant (entrées fantômes).
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/backup_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/utils/date_utils.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  STORE
//  Écriture toujours acceptée. Aucune injection d'échec ici : la
//  démonstration porte sur la FORME des états, pas sur la durabilité.
// ═══════════════════════════════════════════════════════════════════════════

class _Store extends SharedPreferencesStorePlatform {
  _Store({Map<String, Object>? data}) : _data = <String, Object>{...?data};

  final Map<String, Object> _data;

  /// Écritures effectuées (`setValue`), dans l'ordre.
  final List<String> journal = <String>[];

  @override
  Future<bool> clear() async => clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final f = parameters.filter;
    final keys = _data.keys
        .where((k) =>
            k.startsWith(f.prefix) &&
            (f.allowList == null || f.allowList!.contains(k)))
        .toList();
    for (final k in keys) {
      _data.remove(k);
    }
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final f = parameters.filter;
    final result = Map<String, Object>.from(_data);
    result.removeWhere((k, _) =>
        !k.startsWith(f.prefix) ||
        (f.allowList != null && !f.allowList!.contains(k)));
    return result;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    journal.add(key);
    _data[key] = value;
    return true;
  }

  // ── Outils de mesure ────────────────────────────────────────────────────
  Object? brut(String cle) => _data['flutter.$cle'];

  bool contient(String cle) => _data.containsKey('flutter.$cle');

  /// Écritures de la SEULE clé `elo_ratings_v2`.
  int get ecrituresEloV2 =>
      journal.where((k) => k == 'flutter.elo_ratings_v2').length;

  /// Écritures de la clé `elo_ratings_v2_ts`.
  int get ecrituresEloTs =>
      journal.where((k) => k == 'flutter.elo_ratings_v2_ts').length;

  /// Écriture DIRECTE d'une clé, hors service : préparation d'un état connu.
  void poser(String cle, Object valeur) => _data['flutter.$cle'] = valeur;
}

// ═══════════════════════════════════════════════════════════════════════════
//  DONNÉES DE TEST
// ═══════════════════════════════════════════════════════════════════════════

const String _disc = 'Trot Attelé'; // → normalisé TROT_ATTELE
const String _discNorm = 'TROT_ATTELE';

/// ★ A7 (3.3-B2-e) — IDENTITÉS DE COURSE DES APPLICATIONS DE CE FICHIER.
///
/// Le contrat B2-e exige une identité exploitable pour TOUTE application ELO :
/// un appel sans `courseKey` rend `identiteNonExploitable` et ne mute rien.
/// Les appels de ce fichier vérifient des CALCULS et des ÉTATS DE STOCKAGE, pas
/// l'absence d'identité : ils reçoivent donc une identité RÉELLE, cohérente et
/// calendairement valide.
///
/// Choix de conception (et non contournement de la protection) :
///   • `_cleCoursePopulations` — la course qui PEUPLE l'état avant un reset ;
///   • `_cleCoursePostReset`   — la PREMIÈRE course APRÈS le reset, qui est une
///     course LOGIQUEMENT DIFFÉRENTE (A7-3b en vérifie l'application).
/// Les deux dates sont ancrées dans le PASSÉ (2026-11-01 / 2026-11-02), donc
/// jamais refusées par la garde d'antériorité, et JAMAIS dans le futur.
const String _cleCoursePeuplement = 'R1C1_01112026';
const String _cleCoursePostReset = 'R2C2_02112026';

String _cle(String nom) => '${nom.toUpperCase()}|$_discNorm';

ZtPartant _partant(int num, {String? nom}) => ZtPartant(
      numero: '$num',
      nom: nom ?? 'CHEVAL_$num',
      driver: 'DRIVER_$num',
      entraineur: 'ENTR_$num',
      proprietaire: 'PROP_$num',
      gains: '${num * 10000}',
      record: "1'1${num % 10}\"0",
      musique: '1a2a3a4a5a',
      cote: '4.0',
      ageSexe: '${4 + num % 6} M',
      poids: 57.0 + num,
      placeDepartInt: num,
      joursRepos: 10 + num,
      hippodromeActuel: 'VINCENNES',
      statsJockeyCsv: 'JOCKEY_$num|15|40|12',
      statsHippodromeCsv: 'VINCENNES|20|45|15',
      statsEntraineurCsv: 'ENTR_$num|12|33|8',
      eloRating: 1500.0,
      eloNbCourses: 20,
      eloVariationMois: 0.0,
      statsTerrainCsv: 'bon|6|2|4',
      gainsDernierAn: num * 5000,
      scoreIA: 100.0 - num,
    );

/// Store monté + singletons remis dans un état de premier démarrage.
///
/// `EloService` n'est PAS pré-initialisé : chaque test choisit lui-même l'état
/// de départ (clé absente, `{}`, map plate, enveloppe v3), puis appelle le
/// chargeur de PRODUCTION (`EloService.init()`), qui sort immédiatement si
/// `_charge` est déjà vrai.
Future<_Store> _monter({Map<String, Object>? data}) async {
  SharedPreferences.resetStatic();
  final store = _Store(data: data);
  SharedPreferencesStorePlatform.instance = store;
  // Remise à zéro de l'état RAM sans écrire sur le disque : c'est exactement
  // ce que fait le reset complet (`executerResetComplet` → `_ratings.clear()`).
  EloService.instance.viderMemoirePourResetComplet();
  SharedPreferences.resetStatic();
  return store;
}

/// Lit le blob ELO tel qu'il est SUR LE DISQUE, sans passer par le cache.
Map<String, dynamic> _disque(_Store store) {
  final b = store.brut('elo_ratings_v2');
  if (b is! String || b.isEmpty) return <String, dynamic>{};
  final d = json.decode(b);
  if (d is! Map) return <String, dynamic>{};
  return d.map((k, v) => MapEntry(k as String, v));
}

double _rating(String nom) =>
    EloService.instance.getRating(nom, discipline: _disc);

int _nb(String nom) =>
    EloService.instance.getScore(nom, discipline: _disc).nbCourses;

/// Une arrivée de 3 partants, pour observer l'effet d'UNE application ELO.
///
/// ★ A7 (3.3-B2-e) — [courseKey] est OBLIGATOIRE côté production : un appel
///   sans identité est refusé (`identiteNonExploitable`) et ne mute aucun
///   rating, ce qui rendrait les mesures de ce fichier vides de sens.
///   L'identité est donc un paramètre explicite, choisi par chaque test selon
///   la course qu'il représente RÉELLEMENT.
Future<void> _appliquerUneCourse({required String courseKey}) async {
  await EloService.instance.mettreAJourApresArrivee(
    arrivee: const <int>[1, 2, 3],
    partants: <ZtPartant>[_partant(1), _partant(2), _partant(3)],
    discipline: _disc,
    courseKey: courseKey,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  A7-1 — ANCIEN STOCKAGE VIDE (état hérité, blob `{}` déjà sur le disque)
  // ═════════════════════════════════════════════════════════════════════════
  group('A7-1 — ancien stockage vide (`{}` hérité)', () {
    test('A7-1a [MESURE] — `{}` se charge sans erreur, sans rating, et ne '
        'crée AUCUNE entrée fantôme', () async {
      final store = await _monter(data: <String, Object>{
        'flutter.elo_ratings_v2': '{}',
        'flutter.ia_poids_v3': '{}',
      });

      await EloService.init();

      // ignore: avoid_print
      print('[A7-1a] brut="${store.brut('elo_ratings_v2')}" | '
          'nbChevauxSuivis=${EloService.instance.nbChevauxSuivis} | '
          'export=${EloService.instance.exporterPourBackup().length}');

      expect(EloService.instance.nbChevauxSuivis, 0,
          reason: 'MESURE : un blob `{}` ne produit aucun rating');
      expect(EloService.instance.exporterPourBackup(), isEmpty,
          reason: 'MESURE : l\'export est vide — aucune entrée fantôme');
    });

    test('A7-1b [INVARIANT I0] — `{}` et « clé absente » sont DISTINGUABLES '
        'par la seule présence de la clé', () async {
      // État A : blob `{}` hérité.
      final storeA = await _monter(data: <String, Object>{
        'flutter.elo_ratings_v2': '{}',
      });
      await EloService.init();
      final presentA = storeA.contient('elo_ratings_v2');

      // État B : aucune clé (installation vierge, ou reset complet abouti).
      final storeB = await _monter();
      await EloService.init();
      final presentB = storeB.contient('elo_ratings_v2');

      // ignore: avoid_print
      print('[A7-1b] `{}` hérité -> clé présente=$presentA | '
          'clé absente -> présente=$presentB');

      expect(presentA, isTrue,
          reason: 'INVARIANT I0 : `{}` est une clé ÉCRITE, donc présente');
      expect(presentB, isFalse,
          reason: 'INVARIANT I0 : le chargeur ne CRÉE jamais la clé '
              '(`_charger` l.90-146 est en lecture seule hors migration)');
      expect(presentA, isNot(presentB),
          reason: 'INVARIANT I0 : les deux états sont distinguables SANS '
              'convention — pas de valeur par défaut inventée');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A7-2 — NOUVELLE INSTALLATION VIERGE
  // ═════════════════════════════════════════════════════════════════════════
  group('A7-2 — nouvelle installation vierge', () {
    test('A7-2a [MESURE] — store totalement vide : chargement sans création '
        'de clé, aucune écriture ELO', () async {
      final store = await _monter();

      await EloService.init();

      // ignore: avoid_print
      print('[A7-2a] clés présentes=EloService(1=${store.contient('elo_ratings_v2')}, '
          'ts=${store.contient('elo_ratings_v2_ts')}) | '
          'écritures ELO=${store.ecrituresEloV2}');

      expect(EloService.instance.nbChevauxSuivis, 0);
      expect(store.contient('elo_ratings_v2'), isFalse,
          reason: 'MESURE : aucune clé n\'est fabriquée au démarrage');
      expect(store.ecrituresEloV2, 0,
          reason: 'MESURE : le chargement n\'écrit rien');
    });

    test('A7-2b [INVARIANT I1] — une application ELO réussie rend la map '
        'NON VIDE : une arrivée de 3 partants crée au moins 2 entrées', () async {
      final store = await _monter();
      await EloService.init();

      expect(EloService.instance.nbChevauxSuivis, 0,
          reason: 'TÉMOIN : map vide avant application');

      await _appliquerUneCourse(courseKey: _cleCoursePeuplement);

      final nb = EloService.instance.nbChevauxSuivis;
      final export = EloService.instance.exporterPourBackup().length;

      // ignore: avoid_print
      print('[A7-2b] après 1 application : nbChevauxSuivis=$nb | '
          'export=$export | écritures ELO v2=${store.ecrituresEloV2}');

      expect(nb, greaterThanOrEqualTo(2),
          reason: 'INVARIANT I1 : `deltas.forEach` ÉCRIT au moins une entrée '
              'par partant de l\'arrivée (mesuré : 4 entrées pour 3 partants)');
      expect(export, nb,
          reason: 'INVARIANT I1 : l\'export contient exactement les entrées');

      // Formulation directe de I1 : la map est vide ⟺ aucune application.
      expect(nb > 0, isTrue,
          reason: 'INVARIANT I1 : `_ratings` ne peut pas être vide APRÈS une '
              'application ELO réussie');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A7-3 — RESET COMPLET PUIS PREMIÈRE NOUVELLE COURSE
  // ═════════════════════════════════════════════════════════════════════════
  group('A7-3 — reset complet, puis première nouvelle course', () {
    test('A7-3a [MESURE] — après `reinitialiserComplet()`, la clé ELO est '
        'ABSENTE (pas `{}`)', () async {
      final store = await _monter(data: <String, Object>{
        'flutter.ia_precision_migrated_v3': true,
        'flutter.ia_poids_v3': '{}',
        'flutter.ia_seuils_v1': '{}',
      });
      await EloService.init();

      // Peuplement : deux courses appliquées.
      await _appliquerUneCourse(courseKey: _cleCoursePeuplement);
      expect(store.contient('elo_ratings_v2'), isTrue,
          reason: 'TÉMOIN : le blob existe avant le reset');

      await BackupService.instance.reinitialiserComplet();

      final present = store.contient('elo_ratings_v2');

      // ignore: avoid_print
      print('[A7-3a] après reset : clé présente=$present | '
          'brut=${store.brut('elo_ratings_v2')} | '
          'RAM=${EloService.instance.nbChevauxSuivis}');

      expect(present, isFalse,
          reason: 'MESURE : le reset SUPPRIME la clé et ne réécrit PAS `{}` '
              '(backup_service.dart:1644 : « sans passer par reinitialiser(), '
              'qui recréerait elo_ratings_v2 = {} »)');
      expect(EloService.instance.nbChevauxSuivis, 0,
          reason: 'MESURE : le vidage RAM est fait dans le `finally`');
    });

    test('A7-3b [INVARIANT I2] — la première course APRÈS reset s\'applique '
        'normalement : aucun blocage', () async {
      final store = await _monter(data: <String, Object>{
        'flutter.ia_precision_migrated_v3': true,
        'flutter.ia_poids_v3': '{}',
        'flutter.ia_seuils_v1': '{}',
      });
      await EloService.init();
      await _appliquerUneCourse(courseKey: _cleCoursePeuplement);
      await BackupService.instance.reinitialiserComplet();

      expect(EloService.instance.nbChevauxSuivis, 0,
          reason: 'TÉMOIN : état vierge après reset');

      // Première nouvelle course — LOGIQUEMENT DIFFÉRENTE de celle qui a peuplé
      // l'état avant le reset. Un même `courseKey` serait refusé à juste titre
      // (`courseDejaJournalisee`) et le test mesurerait un refus, pas
      // l'application qu'il prétend vérifier.
      await _appliquerUneCourse(courseKey: _cleCoursePostReset);

      final r = _rating('CHEVAL_1');
      final nb = _nb('CHEVAL_1');
      final present = store.contient('elo_ratings_v2');

      // ignore: avoid_print
      print('[A7-3b] 1re course post-reset : rating=$r | nb=$nb | '
          'clé présente=$present | RAM=${EloService.instance.nbChevauxSuivis}');

      expect(r, isNot(1500.0),
          reason: 'INVARIANT I2 : le rating bouge — la course N\'EST PAS '
              'bloquée par l\'état vide laissé par le reset');
      expect(nb, 1,
          reason: 'INVARIANT I2 : le compteur repart de 0 après le reset, '
              'donc vaut exactement 1 après une course');
      expect(present, isTrue,
          reason: 'INVARIANT I2 : la clé est RECRÉÉE par l\'application');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A7-4 — RESTAURATION D'UNE ANCIENNE SAUVEGARDE (map plate, sans registre)
  // ═════════════════════════════════════════════════════════════════════════
  group('A7-4 — restauration d\'une ancienne sauvegarde', () {
    test('A7-4a [MESURE] — une map PLATE (format historique) est restaurée '
        'sans erreur et sans entrée fantôme', () async {
      final store = await _monter();
      await EloService.init();

      final ancien = <String, dynamic>{
        _cle('ALPHA'): <String, dynamic>{
          'nom': 'ALPHA', 'rating': 1922.5, 'nb': 17, 'var': 12.5,
        },
        _cle('BRAVO'): <String, dynamic>{
          'nom': 'BRAVO', 'rating': 1687.25, 'nb': 9, 'var': -3.0,
        },
      };

      await EloService.instance.importerDepuisBackup(ancien);

      // ignore: avoid_print
      print('[A7-4a] après restauration legacy : RAM='
          '${EloService.instance.nbChevauxSuivis} | ALPHA=${_rating('ALPHA')} '
          '| BRAVO=${_rating('BRAVO')} | disque=${_disque(store).keys.toList()}');

      expect(EloService.instance.nbChevauxSuivis, 2,
          reason: 'MESURE : la map plate est acceptée telle quelle');
      expect(_rating('ALPHA'), 1922.5,
          reason: 'MESURE : la valeur est restituée à l\'identique');
      expect(_rating('BRAVO'), 1687.25);
      expect(_disque(store).length, 2,
          reason: 'MESURE : le disque contient exactement les 2 ratings');
    });

    test('A7-4b [MESURE] — le format historique est INDÉTERMINABLE : aucune '
        'information ne dit si une course a déjà été comptée', () async {
      final store = await _monter();
      await EloService.init();

      await EloService.instance.importerDepuisBackup(<String, dynamic>{
        _cle('ALPHA'): <String, dynamic>{
          'nom': 'ALPHA', 'rating': 1590.0, 'nb': 4, 'var': 0.0,
        },
      });

      final disque = _disque(store);
      final racine = disque.keys.toList()..sort();

      // ignore: avoid_print
      print('[A7-4b] racine du blob legacy=$racine | '
          'clé de version présente=${disque.containsKey('v')} | '
          'clé de registre présente=${disque.containsKey('c')}');

      expect(racine, <String>[_cle('ALPHA')],
          reason: 'MESURE : la racine d\'un blob legacy ne contient QUE des '
              'clés de ratings — aucun champ réservé');
      expect(disque.containsKey('v'), isFalse,
          reason: 'MESURE : aucun marqueur de version dans le format '
              'historique');
      expect(disque.containsKey('c'), isFalse,
          reason: 'MESURE : aucun registre dans le format historique');
      // CONCLUSION MESURÉE : l'absence des champs réservés est le SEUL
      // discriminant disponible entre « legacy indéterminé » et « nouveau
      // format ». C'est ce qui fonde le 3e état de connaissance.
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A7-5 — RESTAURATION D'UNE NOUVELLE SAUVEGARDE AVEC REGISTRE VIDE
  //  ⚠️ GROUPE DÉCISIF : il mesure le DÉFAUT à corriger à l'étape 3.
  group('A7-5 — nouvelle sauvegarde à enveloppe v3 et registre vide', () {
    // ⚠️ CE GROUPE MESURE UNE DESTRUCTION, PAS UNE SIMPLE POLLUTION.
    //
    // PRÉDICTION INITIALE (fausse, corrigée ici) : je m'attendais à ce que les
    // clés réservées `r` et `c` deviennent des chevaux fantômes SUPPLÉMENTAIRES,
    // à côté des ratings réels (attendu : 3 ratings + 2 fantômes = 5).
    //
    // MESURE RÉELLE — les ratings réels ne sont pas « accompagnés » de
    // fantômes, ils sont ÉCRASÉS. Les trois chargeurs ne parcourent que le
    // PREMIER niveau de la map :
    //   • `_charger`               (l.118-122) : `data.forEach` ;
    //   • `chargerDepuisMapIsolate`(l.353)     : `_ratings.clear()` + forEach ;
    //   • `importerDepuisBackup`   (l.334)     : `_ratings.clear()` + forEach.
    // Avec une enveloppe, leurs seules entrées sont `v`, `r`, `c`. Les ratings
    // réels sont donc INATTEIGNABLES : jamais lus. Le résultat n'est pas
    // « 3 + 2 », c'est « 0 + 2 ».
    //
    // MESURÉ DANS TROIS PROCESSUS SÉPARÉS (résultat identique, reproductible) :
    //   [_charger] nb=2 cles=[c, r] ALPHA=1500.0
    //   [isolate ] nb=2 cles=[c, r] ALPHA=1500.0
    //   [import  ] nb=2 cles=[c, r] ALPHA=1500.0
    //
    // ── LIMITE DE MÉTHODE DÉCLARÉE ────────────────────────────────────────
    // `EloService._charge` est un booléen PRIVÉ, sans remise à zéro publique :
    // `_charger()` sort immédiatement au 2e appel du processus. Le chemin 1
    // (`_charger`, lecture disque) ne peut donc être exercé qu'UNE SEULE FOIS
    // par fichier de test. C'est A7-1a et A7-3a qui l'exercent, sur des lectures
    // réelles du stockage. Les cas ci-dessous utilisent les chemins 2 et 3, qui
    // sont reproductibles à volonté.

    /// Enveloppe v3 de référence : 2 ratings réels, registre vide.
    Map<String, dynamic> enveloppe(Map<String, double> ratings) =>
        <String, dynamic>{
          'v': 3,
          'r': <String, dynamic>{
            for (final e in ratings.entries)
              _cle(e.key): <String, dynamic>{
                'nom': e.key,
                'rating': e.value,
                'nb': 17,
                'var': 0.0,
              },
          },
          'c': <String, dynamic>{},
        };

    const reference = <String, double>{'ALPHA': 1922.5, 'BRAVO': 1687.25};

    test('A7-5a [MESURE — DESTRUCTION] — CHEMIN 2 '
        '`chargerDepuisMapIsolate` : 2 lignes fantômes, 0 rating réel',
        () async {
      final store = await _monter();
      await EloService.init();

      EloService.instance.chargerDepuisMapIsolate(enveloppe(reference));

      final export = EloService.instance.exporterPourBackup();
      final cles = export.keys.toList()..sort();

      // ignore: avoid_print
      print('[A7-5a][isolate] nb=${export.length} | clés=$cles | '
          'ALPHA=${_rating('ALPHA')} | BRAVO=${_rating('BRAVO')}');

      expect(cles, <String>['c', 'r'],
          reason: 'MESURE : les seules clés sont les clés RÉSERVÉES — '
              '`v` est un int (lève dans `as Map`, avalé par `catch (_)`), '
              '`r` et `c` deviennent des lignes. Les 2 ratings réels sont '
              'inatteignables');
      expect(EloService.instance.nbChevauxSuivis, 2,
          reason: 'MESURE : 2 lignes, toutes les deux fantômes');
      expect(_rating('ALPHA'), 1500.0,
          reason: 'DESTRUCTION MESURÉE : ALPHA (1922.5) est retombé au défaut '
              '1500.0 — ce n\'est pas une imprécision, c\'est une perte totale');
      expect(_rating('BRAVO'), 1500.0,
          reason: 'DESTRUCTION MESURÉE : BRAVO (1687.25) est perdu aussi');
      expect(store.contient('elo_ratings_v2'), isFalse,
          reason: 'MESURE : ce chargeur est en LECTURE SEULE — il n\'écrit '
              'rien, donc le disque n\'est pas encore corrompu à ce stade');
    });

    test('A7-5b [MESURE — DESTRUCTION + RÉÉCRITURE] — CHEMIN 3 '
        '`importerDepuisBackup` détruit ET réécrit le disque corrompu',
        () async {
      final store = await _monter();
      await EloService.init();
      // Le disque porte les ratings corrects AVANT l'import.
      store.poser('elo_ratings_v2', jsonEncode(<String, dynamic>{
        for (final e in reference.entries)
          _cle(e.key): <String, dynamic>{
            'nom': e.key, 'rating': e.value, 'nb': 17, 'var': 0.0,
          },
      }));
      final disqueAvant = _disque(store).keys.toList()..sort();

      await EloService.instance.importerDepuisBackup(enveloppe(reference));

      final export = EloService.instance.exporterPourBackup();
      final cles = export.keys.toList()..sort();
      final disqueApres = _disque(store).keys.toList()..sort();

      // ignore: avoid_print
      print('[A7-5b][import] disqueAvant=$disqueAvant -> '
          'disqueAprès=$disqueApres | RAM=$cles | ALPHA=${_rating('ALPHA')}');

      expect(disqueAvant, <String>[_cle('ALPHA'), _cle('BRAVO')],
          reason: 'TÉMOIN : les 2 ratings réels sont bien sur le disque avant');
      expect(cles, <String>['c', 'r'],
          reason: 'MESURE : mêmes 2 lignes fantômes qu\'au chemin 2');
      expect(disqueApres, <String>['c', 'r'],
          reason: 'AGGRAVATION MESURÉE : ce chemin ÉCRIT. Les ratings réels '
              'initialement corrects sur le disque sont REMPLACÉS par les '
              '2 lignes vides — la perte devient DURABLE, elle survit au '
              'redémarrage');
      expect(_rating('ALPHA'), 1500.0);
    });

    test('A7-5c [MESURE — CONSÉQUENCE] — le contrat `exporterPourBackup()'
        '.length == 3` des tests historiques est rompu, et pas par excès',
        () async {
      final store = await _monter();
      await EloService.init();

      await EloService.instance.importerDepuisBackup(enveloppe(<String, double>{
        'ALPHA': 1922.5,
        'BRAVO': 1687.25,
        'CHARLIE': 1544.75,
      }));

      final longueur = EloService.instance.exporterPourBackup().length;

      // ignore: avoid_print
      print('[A7-5c] 3 ratings réels + enveloppe -> '
          'exporterPourBackup().length=$longueur (contrat historique : 3) | '
          'disque=${_disque(store).length}');

      // Les assertions historiques (v18 l.160,188,216,263,272 et v5 l.465,1578)
      // attendent 3. On mesure 2.
      expect(longueur, 2,
          reason: 'MESURE : 2 fantômes, 0 rating réel. Le contrat est rompu '
              'PAR DÉFAUT (2 < 3), pas par excès (5 > 3) comme je l\'avais '
              'prédit à tort');
      expect(longueur, isNot(3),
          reason: 'MESURE : `length == 3` échouerait');
      expect(_rating('ALPHA'), 1500.0,
          reason: 'MESURE : les 3 ratings sont perdus, pas déplacés');
      expect(_rating('CHARLIE'), 1500.0);
    });

    test('A7-5d [INVARIANT I5] — le format legacy PLAT reste intact : la '
        'destruction ne concerne QUE le format à enveloppe', () async {
      await _monter();
      await EloService.init();

      final plate = <String, dynamic>{
        for (final e in reference.entries)
          _cle(e.key): <String, dynamic>{
            'nom': e.key, 'rating': e.value, 'nb': 17, 'var': 0.0,
          },
      };
      EloService.instance.chargerDepuisMapIsolate(plate);

      final cles = EloService.instance.exporterPourBackup().keys.toList()
        ..sort();

      // ignore: avoid_print
      print('[A7-5d][plate] clés=$cles | ALPHA=${_rating('ALPHA')} | '
          'BRAVO=${_rating('BRAVO')}');

      expect(cles, <String>[_cle('ALPHA'), _cle('BRAVO')],
          reason: 'INVARIANT I5 : une map plate est lue correctement — '
              'aucune entrée fantôme');
      expect(_rating('ALPHA'), 1922.5,
          reason: 'INVARIANT I5 : la valeur est restituée exactement');
      expect(_rating('BRAVO'), 1687.25);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A7-6 — IDENTIFIANTS DE COURSES : normal, date doublée, invalide
  //  ⚠️ Ce groupe ne touche NI au stockage NI à `EloService` : il mesure
  //  uniquement la fonction de normalisation de production
  //  (`utils/date_utils.dart`), dont dépend l'identité des courses du registre.
  // ═════════════════════════════════════════════════════════════════════════
  group('A7-6 — identifiants de courses', () {
    test('A7-6a [INVARIANT I3] — les variantes d\'un MÊME courseKey rendent '
        'la même date canonique', () async {
      const variantes = <String>[
        'R1C1_17042026',                 // format nominal
        'R1C1_17042026_17042026',        // date DOUBLÉE (alert_service:2717)
        'R1C1_17042026_ia',              // suffixe `_ia` (overrideKey)
        'R1C1_17042026_1745000000000',   // storageKey + horodatage
        'R1C1_2026-04-17',               // format ISO
        'R1C1_2026-04-17_suffixe',
      ];

      final dates = <String, String?>{};
      for (final v in variantes) {
        dates[v] = dateDepuisCourseKey(v);
      }

      // ignore: avoid_print
      print('[A7-6a] variants -> $dates');

      for (final v in variantes) {
        expect(dates[v], '2026-04-17',
            reason: 'INVARIANT I3 : `$v` doit rendre la date canonique '
                '2026-04-17, sinon deux producteurs comptent DOUBLE');
      }
      final uniques = dates.values.toSet();
      expect(uniques.length, 1,
          reason: 'INVARIANT I3 : 6 variantes -> 1 seule date canonique');
    });

    test('A7-6b [INVARIANT I3] — les formats INVALIDES rendent `null` : aucun '
        'identifiant inventé', () async {
      const invalides = <String>[
        'R1C1_31022026',   // 31 février : inexistant
        'R1C1_29022025',   // 29/02 d'une année NON bissextile
        'R1C1_32012026',   // jour 32
        'R1C1_1704202',    // 7 chiffres
        'R1C1_',           // date absente
        'R1C1',            // aucune date
        'C1_17042026',     // pas de préfixe R
        'R1C1_00002026',   // mois 00
        'R1C1_17002026',   // mois 00
        'R1C1_17042026abc',// chiffres collés à des lettres (pas de `_`)
      ];

      for (final v in invalides) {
        final d = dateDepuisCourseKey(v);
        // ignore: avoid_print
        print('[A7-6b] `$v` -> ${d ?? "null"}');
        expect(d, isNull,
            reason: 'INVARIANT I3 : `$v` est invalide — la fonction refuse, '
                'elle ne fabrique JAMAIS de date de remplacement');
      }

      // Témoin : une date bissextile VALIDE doit passer.
      expect(dateDepuisCourseKey('R1C1_29022024'), '2024-02-29',
          reason: 'TÉMOIN : le refus n\'est pas systématique');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  A7-7 — ABSENCE DE COLLISION ENTRE DEUX COURSES DIFFÉRENTES
  // ═════════════════════════════════════════════════════════════════════════
  group('A7-7 — absence de collision entre deux courses différentes', () {
    test('A7-7a [INVARIANT I4] — R1C1, R11C1, R1C11 et R4C7 restent '
        'DISTINCTS après normalisation', () async {
      // La clé canonique retenue pour le registre est
      // `R{numR}C{numC}_{YYYYMMDD}` reconstruite depuis le préfixe et la date.
      String canonique(String courseKey) {
        final m = RegExp(r'^R(\d+)C(\d+)_').firstMatch(courseKey);
        final iso = dateDepuisCourseKey(courseKey);
        if (m == null || iso == null) return 'INVALIDE';
        return 'R${m.group(1)}C${m.group(2)}_${iso.replaceAll('-', '')}';
      }

      final cas = <String, String>{
        'R1C1_17042026': 'R1C1_20260417',
        'R11C1_17042026': 'R11C1_20260417',
        'R1C11_17042026': 'R1C11_20260417',
        'R4C7_17042026': 'R4C7_20260417',
        'R1C1_18042026': 'R1C1_20260418',
      };

      cas.forEach((entree, attendu) {
        final obtenu = canonique(entree);
        // ignore: avoid_print
        print('[A7-7a] $entree -> $obtenu (attendu $attendu)');
        expect(obtenu, attendu);
      });

      final canoniques = cas.keys.map(canonique).toSet();
      expect(canoniques.length, cas.length,
          reason: 'INVARIANT I4 : aucune collision — ${cas.length} entrées '
              'donnent ${canoniques.length} clés canoniques distinctes');
    });

    test('A7-7b [INVARIANT I4] — les variantes de la MÊME course convergent '
        'vers UNE SEULE clé canonique', () async {
      String canonique(String courseKey) {
        final m = RegExp(r'^R(\d+)C(\d+)_').firstMatch(courseKey);
        final iso = dateDepuisCourseKey(courseKey);
        if (m == null || iso == null) return 'INVALIDE';
        return 'R${m.group(1)}C${m.group(2)}_${iso.replaceAll('-', '')}';
      }

      const variantes = <String>[
        'R1C1_17042026',
        'R1C1_17042026_17042026',
        'R1C1_17042026_ia',
        'R1C1_17042026_1745000000000',
        'R1C1_2026-04-17',
      ];

      final canoniques = variantes.map(canonique).toSet();

      // ignore: avoid_print
      print('[A7-7b] ${variantes.length} variantes -> '
          '${canoniques.length} clé(s) canonique(s) : $canoniques');

      expect(canoniques.length, 1,
          reason: 'INVARIANT I4 : sans convergence, la MÊME course serait '
              'comptée autant de fois qu\'elle a de graphies — c\'est '
              'exactement le double comptage que A7 Option A a corrigé côté '
              'appelant, et que le registre doit corriger côté persistance');
      expect(canoniques.first, 'R1C1_20260417');
    });

    test('A7-7c [INVARIANT I4] — un identifiant invalide ne produit JAMAIS '
        'de clé canonique : il ne peut donc pas collisionner', () async {
      String canonique(String courseKey) {
        final m = RegExp(r'^R(\d+)C(\d+)_').firstMatch(courseKey);
        final iso = dateDepuisCourseKey(courseKey);
        if (m == null || iso == null) return 'INVALIDE';
        return 'R${m.group(1)}C${m.group(2)}_${iso.replaceAll('-', '')}';
      }

      const invalides = <String>[
        'R1C1_31022026',
        'R1C1_29022025',
        'R1C1',
        '',
        'R0C0_17042026', // numR=0 : syntaxiquement valide, sémantiquement vide
      ];

      for (final v in invalides) {
        final c = canonique(v);
        // ignore: avoid_print
        print('[A7-7c] `$v` -> $c');
        if (v == 'R0C0_17042026') {
          // Cas limite HONNÊTE : le préfixe impose `\d+`, donc `0` passe.
          // La normalisation seule ne suffit pas ; le registre devra refuser
          // explicitement numR <= 0 || numC <= 0.
          expect(c, 'R0C0_20260417',
              reason: 'MESURE : `0` satisfait `\\d+`. La validation devra être '
                  'explicite dans le registre (numR/numC > 0), pas déduite de '
                  'la normalisation');
        } else {
          expect(c, 'INVALIDE',
              reason: 'INVARIANT I4 : `$v` n\'a pas de clé canonique');
        }
      }
    });
  });
}
