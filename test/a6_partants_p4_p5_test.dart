// ═══════════════════════════════════════════════════════════════════════════
//  A6 — CONTRÔLE DES PARTANTS SUR P4 ET P5 (LISTE RÉELLEMENT DISPONIBLE)
//
//  ⚠️  FICHIER DE TEST UNIQUEMENT. AUCUNE MODIFICATION DE PRODUCTION.
//
//  OBJET : combler la limite explicitement déclarée du rapport A6. Les tests
//  T7a/T7b de `a6_fiabilite_arrivees_pmu_test.dart` mesuraient P4 et P5 avec
//  un programme SANS partants : leur contrôle d'appartenance était donc
//  « impossible » par construction, et aucun refus ne pouvait y être exercé.
//  Ces tests-ci fournissent une liste de partants RÉELLEMENT DISPONIBLE dans
//  le contexte des services, sans toucher au code de production.
//
//  ── Comment la liste devient disponible, sans modifier la production ─────
//  Les deux parseurs lisent le MÊME état : `DataRefreshService.reunions`.
//    • P4 (`DataRefreshService._partantsDeLaCourse`, l.1318) lit `_reunions`;
//    • P5 (`AlertService._partantsDeLaCourse`, l.2746) lit
//      `DataRefreshService.instance.reunions`.
//  On le peuple par le chemin PUBLIC de production :
//      `DataRefreshService.instance.refresh()`
//        → `_doRefresh()` → `ZoneTurfService.chargerProgramme()`  [/programme]
//        → `_chargerPartants()`                                   [/participants]
//        → `_reunions = reunions`                                 (l.674)
//        → `_recupererResultatsAuto()`                            (l.702)
//  Aucune méthode privée n'est appelée, aucun champ n'est écrit de force.
//
//  ── Vérifications imposées par le mandat ────────────────────────────────
//   1. une arrivée contenant un numéro absent des partants (99) est REFUSÉE ;
//   2. une arrivée composée uniquement de numéros valides reste ACCEPTÉE ;
//   3. une liste INDISPONIBLE n'est PAS assimilée à une liste INCOHÉRENTE ;
//   4. une arrivée refusée ne déclenche ni enregistrement, ni apprentissage,
//      ni mise à jour ELO.
//
//  ── Ce qui n'est pas touché ─────────────────────────────────────────────
//  Gradient, poids, seuils, calibration, apprentissage IA, calculs ELO,
//  TOP3 learning, archives. On ne fait que LIRE leurs effets pour constater
//  qu'ils ne se produisent pas.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/alert_service.dart';
import 'package:pronostic_hippique/services/data_refresh_service.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';
import 'package:pronostic_hippique/services/zone_turf_service.dart';

// ─────────────────────────── Outils de formatage ───────────────────────────

String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

/// Affichage d'une arrivée. `[]` si vide, `null` si absente.
String _arr(List<int>? a) => a == null ? 'null' : (a.isEmpty ? '[]' : a.join('-'));

// ───────────────── Faux serveur PMU (aucun appel réel) ─────────────────────

/// Un bloc `{typePari, rapports[]}` du format RÉEL de l'API.
class _Bloc {
  final String type;
  final List<String> combinaisons;
  const _Bloc(this.type, this.combinaisons);
}

/// Corps JSON au format réel : racine = **List** de blocs.
String _corps(List<_Bloc> blocs) => json.encode([
      for (final b in blocs)
        {
          'typePari': b.type,
          'rapports': [
            for (final c in b.combinaisons)
              {'combinaison': c, 'dividendePourUnEuro': 350},
          ],
        },
    ]);

/// Corps « arrivée ordonnée 7-4-2-9-X » ; [dernier] permet d'injecter 99.
String _corpsArrivee({int dernier = 1}) => _corps([
      const _Bloc('E_SIMPLE_GAGNANT', ['7']),
      const _Bloc('E_SIMPLE_PLACE', ['7', '4', '2']),
      _Bloc('E_QUINTE_PLUS', ['7-4-2-9-$dernier']),
    ]);

/// Programme minimal : une réunion R1, une course C1, heure de départ [dep].
/// Les partants ne sont PAS ici : ils viennent de `/participants`.
String _programme(DateTime dep) => json.encode({
      'programme': {
        'reunions': [
          {
            'numOfficiel': 1,
            'hippodrome': {
              'libelleLong': 'VINCENNES (FRANCE)',
              'libelleCourt': 'VINCENNES',
            },
            'courses': [
              {
                'numOrdre': 1,
                'libelle': 'PRIX A6 PARTANTS',
                'discipline': 'ATTELE',
                'distance': 2100,
                'montantPrix': 30000,
                'paris': <Map<String, dynamic>>[],
                'heureDepart': dep.millisecondsSinceEpoch,
              },
            ],
          },
        ],
      },
    });

/// Participants RÉELS au format de l'API : `numPmu` 1..[nb].
///
/// C'est la source de `ZtPartant.numero` côté production
/// (`zone_turf_service.dart:643` : `pm['numPmu'] ?? pm['numero']`).
/// `statut: 'PARTANT'` → le filtre `NON_PARTANT` de `_chargerPartants` les
/// conserve tous.
String _participants(int nb) => json.encode({
      'participants': [
        for (var n = 1; n <= nb; n++)
          {
            'numPmu': n,
            'nom': 'CHEVAL_$n',
            'statut': 'PARTANT',
            'age': 6,
            'sexe': 'H',
            'driver': {'nom': 'DRIVER_$n'},
            'entraineur': {'nom': 'ENTRAINEUR_$n'},
          },
      ],
    });

/// Exécute [action] avec un réseau PMU entièrement simulé.
///
/// [nbPartants] = nombre de participants servis par `/participants`.
/// `0` reproduit une liste INDISPONIBLE (aucun partant chargé → le contrôle
/// d'appartenance est impossible et ne doit produire aucun refus).
Future<T> _avecPmu<T>(
  Future<T> Function() action, {
  required String corps,
  required DateTime dep,
  required int nbPartants,
}) {
  final client = MockClient((request) async {
    final p = request.url.path;

    if (p.contains('rapports-definitifs')) {
      return http.Response(corps, 200,
          headers: {'content-type': 'application/json'});
    }
    if (p.contains('participants')) {
      return http.Response(_participants(nbPartants), 200,
          headers: {'content-type': 'application/json'});
    }
    if (p.contains('statuts')) {
      return http.Response(json.encode({'participants': <dynamic>[]}), 200,
          headers: {'content-type': 'application/json'});
    }
    // Programme (et tout le reste) → fixture de programme.
    return http.Response(_programme(dep), 200,
        headers: {'content-type': 'application/json'});
  });
  return http.runWithClient(action, () => client);
}

/// Laisse progresser la boucle d'événements jusqu'à ce que [c] soit vraie.
Future<bool> _attendreQue(bool Function() c, {int ms = 4000}) async {
  var ecoule = 0;
  while (ecoule < ms) {
    if (c()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    ecoule += 10;
  }
  return c();
}

// ─────────────────────────── État simulé ───────────────────────────────────

const Map<String, double> _poidsDefaut = {
  'forme': 0.25, 'gains': 0.13, 'record': 0.10, 'cote': 0.08,
  'constance': 0.09, 'victoires': 0.04, 'discipline': 0.02,
  'distSpec': 0.08, 'jockey': 0.07, 'repos': 0.03, 'hippo': 0.04,
  'entraineur': 0.04, 'elo': 0.05, 'terrain': 0.05,
  'divergence': 0.04, 'poidsRel': 0.03, 'progression': 0.03,
  'mouvCote': 0.06, 'placeDepart': 0.03,
};

Map<String, Object> _prefs({
  List<String>? pronostics,
  List<String>? tracked,
}) =>
    <String, Object>{
      'ia_precision_migrated_v3': true,
      'ia_poids_v3': json.encode({
        ..._poidsDefaut,
        'nbMisesAJour': 0,
        'calibrationScore': 50.0,
      }),
      'ia_seuils_v1': json.encode({}),
      'ia_precision_v2': json.encode({}),
      'ia_stats_labels_v1': json.encode({}),
      'ia_stats_types_v1': <String>[],
      'ia_journal_v2': <String>[],
      if (pronostics != null) 'ia_pronostics_v2': pronostics,
      if (tracked != null) 'tracked_courses_v1': tracked,
    };

/// Scores IA du pronostic. Couvre 1..9 et NE contient PAS 99 — liste fiable.
///
/// ⚠️ COHÉRENCE DE FIXTURE (mesurée, pas supposée). La production construit
/// `scoresIA` à partir de `course.partants` COMPLET
/// (`data_refresh_service.dart:978`, puis `scores[p.numero] = p.scoreIA`) :
/// `scoresIA` couvre donc TOUS les partants, jamais un sous-ensemble.
/// La version précédente de cette fixture s'arrêtait à 8 numéros alors que
/// l'arrivée de référence contient le n° 9 : elle décrivait une course de
/// 8 partants dont l'arrivée comportait un 9e cheval — un cas qui n'existe
/// pas en production. La liste a été complétée pour redevenir conforme.
const Map<String, double> _scoresFavori4 = <String, double>{
  '4': 95.0, '7': 88.0, '2': 70.0, '9': 60.0,
  '1': 55.0, '3': 40.0, '5': 30.0, '6': 20.0,
  '8': 25.0,
};

IaPronostic _pronostic({required String cle, required DateTime date}) =>
    IaPronostic(
      courseKey: cle,
      nomCourse: 'PRIX A6 PARTANTS',
      hippodrome: 'VINCENNES',
      discipline: 'Trot Attelé',
      datePronostic: date,
      scoresIA: _scoresFavori4,
      scoresCriteres: const <String, ScoresCriteres>{},
      confiancePredite: 70.0,
      typePariConseille: 'Simple Gagnant',
      resultatsReels: false,
      arriveeReelle: null,
    );

int _slot = 0;

TrackedCourse _suivi({
  required DateTime heureDepart,
  required int slot,
  required String iaMemKey,
}) =>
    TrackedCourse(
      numReunion: 1,
      numCourse: 1,
      nomCourse: 'PRIX A6 PARTANTS',
      hippodrome: 'VINCENNES',
      heureDepart: heureDepart,
      numeroCheval: 7,
      nomCheval: 'CHEVAL_7',
      miseEngagee: 10.0,
      typePari: 'Simple Gagnant',
      cote: 5.0,
      // ⚠️ `iaMemKey` EST INDISPENSABLE. Sans lui, `AlertService` construit
      // `memKey = '${tc.key}_$_aj$_am${annee}'` (alert_service.dart:2717-2718)
      // et `tc.key` contenant DÉJÀ la date, la clé devient
      // `R1C1_17112026_17112026` — mesuré : elle ne correspond à aucun
      // pronostic et l'écriture est abandonnée
      // (« [IaMem][A4-2] résultat IGNORÉ — … absente de la mémoire active »).
      // La production vise la clé du pronostic : la fixture doit faire de même.
      iaMemKey: iaMemKey,
      // Clé UNIQUE : `AlertService._resultatsVerifies` est un `Set` du
      // singleton qui n'est jamais vidé par `_load()`. Une clé réutilisée
      // ferait sauter silencieusement le scénario suivant.
      storageKey: 'R1C1_${_fmt(heureDepart)}_$slot',
    );

Future<void> _reset({
  List<IaPronostic> pronostics = const <IaPronostic>[],
  List<TrackedCourse> tracked = const <TrackedCourse>[],
}) async {
  SharedPreferences.setMockInitialValues(_prefs(
    pronostics: pronostics.map((p) => json.encode(p.toJson())).toList(),
    tracked: tracked.map((t) => json.encode(t.toJson())).toList(),
  ));
  SharedPreferences.resetStatic();
  ZoneTurfService.viderCachePourResetComplet();
  DataRefreshService.instance.viderMemoirePourResetComplet();
  await EloService.instance.reinitialiser();
  await IaMemoryService.instance.recharger();
}

IaPronostic? _pronosticDe(String cle) {
  final l = IaMemoryService.instance.pronostics
      .where((p) => p.courseKey == cle)
      .toList();
  return l.isEmpty ? null : l.first;
}

/// Retire les courses suivies de la RAM d'`AlertService`.
///
/// Indispensable : le watchdog armé par `init()` tire toutes les 60 s. Une
/// course restée en suivi avec un `resultKey` retiré provoquerait une requête
/// HTTP RÉELLE au tick suivant, hors de tout `http.runWithClient`.
Future<void> _viderSuivi() async {
  final cles = AlertService.instance.trackedCourses.keys.toList();
  for (final k in cles) {
    await AlertService.instance.retirerSuivi(k);
  }
}

bool _alertesOuvertes = false;

Future<void> _ouvrirAlertes() async {
  _alertesOuvertes = true;
  await AlertService.init();
}

Future<void> _fermerAlertes() async {
  if (!_alertesOuvertes) return;
  _alertesOuvertes = false;
  await _viderSuivi();
  AlertService.instance.dispose();
}

// ─────────────────────── Mesure d'un scénario P4 ───────────────────────────

/// Résultat mesuré d'un scénario : tout ce que le mandat demande de vérifier.
class _Mesure {
  final List<int>? arrivee;
  final bool resultatsReels;
  final int nbMisesAJourPoids;
  final int nbChevauxElo;

  /// Arrivée RÉELLEMENT transmise à `EloService.mettreAJourApresArrivee`.
  ///
  /// ⚠️ `null` signifie « la mise à jour ELO n'a JAMAIS été atteinte », ce qui
  /// n'est pas la même chose que « atteinte mais sans effet ». C'est la
  /// distinction que l'ancien harnais ne pouvait pas faire : il ne mesurait
  /// qu'un DELTA de `nbChevauxSuivis`, sans preuve que l'étape avait eu lieu.
  final List<int>? arriveeElo;

  /// Mode de persistance de la mise à jour ELO (`persistee`, `nonTentee`, ...),
  /// ou `null` si l'étape n'a jamais été atteinte.
  final String? etatPersistanceElo;

  /// Identité de course reçue par `EloService` (`R1C1_<date>` ou `R1C1_<date>|`).
  final String? cleCourseElo;

  /// Ratings EXTRAITS DU DISQUE (`elo_ratings_v2`) pour les chevaux de
  /// l'arrivée. C'est la preuve de PERSISTANCE : la RAM ne suffirait pas.
  final Map<String, double> ratingsDisque;

  /// Nombre de courses désormais présentes dans le registre ELO persistant :
  /// c'est l'anti-double-application (une course ne doit être comptée qu'UNE
  /// fois, quel que soit le nombre de passages).
  final int? nbCoursesRegistre;

  /// Nb de mises à jour ELO CONFIRMÉES par `setString → true`, mesuré en delta
  /// autour du scénario. C'est l'anti-double-écriture au niveau du stockage.
  final int deltaPersistees;

  final int nbPartantsEnMemoire;

  /// Message de résultat observé côté `AlertService` (P5 uniquement).
  final String? messageResultat;

  /// `true` si une alerte de résultat a été produite par P5.
  final bool alerteResultat;

  const _Mesure({
    required this.arrivee,
    required this.resultatsReels,
    required this.nbMisesAJourPoids,
    required this.nbChevauxElo,
    required this.nbPartantsEnMemoire,
    this.arriveeElo,
    this.etatPersistanceElo,
    this.cleCourseElo,
    this.ratingsDisque = const <String, double>{},
    this.nbCoursesRegistre,
    this.deltaPersistees = 0,
    this.messageResultat,
    this.alerteResultat = false,
  });
}

/// Signature d'un observateur de mise à jour ELO.
typedef _ObserveurElo = void Function(
    List<int> arrivee, List<ZtPartant> partants, String discipline,
    String? courseKey);

/// Espion qui relaie l'observation sans RIEN changer au déroulement.
///
/// Il ne remplace aucune logique : il est appelé par un point d'observation
/// ajouté à `EloService` (voir `debugObserveurMiseAJour`), qui ne conditionne
/// aucune écriture et ne modifie aucune formule.
class _EspionMiseAJourElo implements DebugObserveurElo {
  final _ObserveurElo _surObservation;
  const _EspionMiseAJourElo(this._surObservation);

  @override
  void appeler(List<int> arrivee, List<ZtPartant> partants, String discipline,
          String? courseKey) =>
      _surObservation(arrivee, partants, discipline, courseKey);
}

/// Lit `elo_ratings_v2` et rend les ratings des chevaux demandés.
/// ⚠️ LECTURE DU DISQUE, PAS DE LA RAM. `EloService.nbChevauxSuivis` ne prouve
///    rien sur la persistance : une mutation en mémoire réussie peut n'avoir
///    jamais été écrite. La clé est celle de la production
///    (`elo_service.dart:853`).
Future<Map<String, double>> _ratingsSurDisque(List<String> noms) async {
  final prefs = await SharedPreferences.getInstance();
  final brut = prefs.getString('elo_ratings_v2');
  if (brut == null || brut.isEmpty) return <String, double>{};
  final data = jsonDecode(brut) as Map<String, dynamic>;
  final res = <String, double>{};
  for (final nom in noms) {
    final norm = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    for (final e in data.entries) {
      // Clé de production : « NOM|DISCIPLINE », éventuellement « NOM| ».
      if (e.key.split('|').first == norm) {
        res[e.key] = ((e.value as Map<String, dynamic>)['rating'] as num)
            .toDouble();
      }
    }
  }
  return res;
}

/// Nombre de courses DISTINCTES du registre ELO persistant.
///
/// Anti-double-application : `mettreAJourApresArrivee` refuse une course déjà
/// vue (`registre.entreePourCle != null`) ; le registre doit donc contenir
/// EXACTEMENT une entrée pour la course du scénario.
Future<int?> _nbCoursesRegistre() async {
  final prefs = await SharedPreferences.getInstance();
  final brut = prefs.getString('elo_registre_v3');
  if (brut == null || brut.isEmpty) return null;
  try {
    final data = jsonDecode(brut);
    if (data is! Map<String, dynamic>) return null;
    final entrees = data['entrees'];
    if (entrees is! List) return null;
    return entrees
        .whereType<Map<String, dynamic>>()
        .where((e) => e['type'] == 'course')
        .length;
  } catch (_) {
    return null;
  }
}

/// Exécute P4 (`DataRefreshService.refresh()`) sur un état vierge.
///
/// [nbPartants] = taille de la liste servie par `/participants`.
/// [corps] = corps `/rapports-definitifs` simulé.
Future<_Mesure> _mesurerP4({
  required int nbPartants,
  required String corps,
  required DateTime dep,
}) async {
  final cle = 'R1C1_${_fmt(dep)}';
  await _reset(pronostics: [_pronostic(cle: cle, date: dep)]);

  final poidsAvant = IaMemoryService.instance.poids.nbMisesAJour;
  final eloAvant = EloService.instance.nbChevauxSuivis;
  final persisteesAvant = EloService.instance.nbPersistees;
  // L'arrivée RÉELLEMENT remise à `_mettreAJourEloApresArrivee` est capturée
  // en enveloppant le service : c'est la seule preuve que l'étape a été
  // ATTEINTE avec le bon contenu, distincte de la preuve qu'elle a EU un
  // effet. Aucune logique de production n'est modifiée — on observe.
  List<int>? arriveeTransmise;
  final messagerieElo = _EspionMiseAJourElo((arrivee, _, __, ___) {
    arriveeTransmise = List<int>.unmodifiable(arrivee);
  });
  EloService.instance.debugObserveurMiseAJour = messagerieElo;

  await _avecPmu(
    () => DataRefreshService.instance.refresh(),
    corps: corps,
    dep: dep,
    nbPartants: nbPartants,
  );

  // ═══════════════════════════════════════════════════════════════════════
  //  ATTENTE DÉTERMINISTE DE L'ACHÈVEMENT DU TRAITEMENT ELO
  //
  //  ── DÉFAUT DU HARNAIS, MESURÉ ─────────────────────────────────────────
  //  v1 attendait `_pronosticDe(cle)?.resultatsReels == true` puis lisait
  //  immédiatement `nbChevauxSuivis`. Or la production exécute, DANS CET
  //  ORDRE (data_refresh_service.dart) :
  //      1491  resultatEnregistre = await IaMemoryService.enregistrerResultat(...)
  //      1510  if (resultatEnregistre) {
  //      1514    await _mettreAJourEloApresArrivee(p.courseKey, arrivee);
  //            }
  //  `resultatsReels` devient vrai DANS l'appel de la ligne 1491, c'est-à-dire
  //  AVANT l'étape ELO. L'ancienne condition rendait donc la main avant que
  //  la mise à jour ELO ait commencé. Mesuré : `Δchevaux=0` alors que la
  //  ligne de journal `[EloService] ✅ 5 ELO mis à jour (discipline: Attelé) —
  //  persistance: persistee` apparaissait APRÈS la mesure.
  //
  //  ── CONDITION CORRIGÉE : ATTENTE À DEUX ÉTAGES ────────────────────────
  //  Le défaut n'était pas qu'un premier étage existait, c'est qu'il était le
  //  SEUL : `resultatsReels` devient vrai dans `enregistrerResultat(...)`
  //  (l.1491), AVANT l'étape ELO (l.1514). On garde donc cet étage — il dit
  //  si une arrivée a été acceptée — et on en AJOUTE un second, sur
  //  l'ACHÈVEMENT RÉEL de l'étape ELO.
  //
  //  ⚠️ TROIS PIÈGES RENCONTRÉS ET MESURÉS, tous évités ici :
  //   1. `ΔnbChevauxSuivis` vaut 0 aussi bien si l'étape n'a pas commencé,
  //      si elle a échoué, que si elle est encore en cours → inutilisable
  //      comme condition d'achèvement.
  //   2. L'observateur d'ENTRÉE se déclenche AVANT le travail : l'utiliser
  //      comme critère de fin rendait l'attente immédiatement vraie (mesuré :
  //      `etat=null`, `disque=0` alors que l'arrivée était déjà « transmise »).
  //      Il sert donc à PROUVER L'ATTEINTE, jamais à décider de la fin.
  //   3. `dernierResultatMiseAJour` SURVIT d'un scénario à l'autre : au
  //      scénario « liste absente », il valait encore `persistee` du scénario
  //      précédent. On ne l'accepte donc que s'il s'agit d'une NOUVELLE
  //      instance (`identical`), seule preuve qu'il a été réécrit ICI.
  // ═══════════════════════════════════════════════════════════════════════
  final resultatAvant = EloService.instance.dernierResultatMiseAJour;
  final bool resolu = await _attendreQue(
      () => _pronosticDe(cle)?.resultatsReels == true,
      ms: 3000);

  // Second étage, franchi seulement si une arrivée a été acceptée : sans
  // arrivée, l'étape ELO n'est légitimement jamais atteinte (`continue` en
  // l.1471), et l'attendre n'aurait aucun sens.
  final bool eloAtteint = !resolu
      ? false
      : await _attendreQue(
          () {
            final r = EloService.instance.dernierResultatMiseAJour;
            final nouveau = r != null && !identical(r, resultatAvant);
            return nouveau ||
                EloService.instance.nbPersistees > persisteesAvant;
          },
          ms: 10000,
        );

  final p = _pronosticDe(cle);

  // Nombre de partants effectivement chargés dans le contexte des services :
  // c'est la preuve que la liste n'était pas vide (ou l'était, pour le
  // scénario « liste indisponible »).
  var nbEnMemoire = 0;
  for (final r in DataRefreshService.instance.reunions) {
    if (r.code != 'R1') continue;
    for (final c in r.courses) {
      if (c.numCourse == 1) nbEnMemoire = c.partants.length;
    }
  }

  // Ratings RÉELLEMENT présents sur le disque après le scénario.
  final noms = [for (var n = 1; n <= nbPartants; n++) 'CHEVAL_$n'];
  final surDisque = await _ratingsSurDisque(noms);
  final resultat = EloService.instance.dernierResultatMiseAJour;

  // L'observateur est retiré IMMÉDIATEMENT : il ne doit pas survivre au
  // scénario, sinon un scénario ultérieur écrirait dans cette closure.
  EloService.instance.debugObserveurMiseAJour = null;

  debugPrint('[P4] attente ELO aboutie=$eloAtteint | '
      'arriveeTransmise=${arriveeTransmise?.join("-") ?? "JAMAIS ATTEINTE"} | '
      'etat=${resultat?.etatRatings.name} | '
      'cle=${EloService.instance.derniereIdentiteCourse?.courseKey} | '
      'persistees $persisteesAvant→${EloService.instance.nbPersistees} | '
      'disque=${surDisque.length} rating(s)');

  return _Mesure(
    arrivee: p?.arriveeReelle,
    resultatsReels: p?.resultatsReels ?? false,
    nbMisesAJourPoids:
        IaMemoryService.instance.poids.nbMisesAJour - poidsAvant,
    nbChevauxElo: EloService.instance.nbChevauxSuivis - eloAvant,
    nbPartantsEnMemoire: nbEnMemoire,
    arriveeElo: arriveeTransmise,
    etatPersistanceElo: resultat?.etatRatings.name,
    cleCourseElo: EloService.instance.derniereIdentiteCourse?.courseKey,
    ratingsDisque: surDisque,
    nbCoursesRegistre: await _nbCoursesRegistre(),
    deltaPersistees: EloService.instance.nbPersistees - persisteesAvant,
  );
}

/// Exécute P5 (`AlertService.init()` → watchdog → `_fetchResultatAuto`).
///
/// Le programme est chargé AU PRÉALABLE par le chemin public
/// `DataRefreshService.refresh()` : c'est lui qui rend la liste de partants
/// disponible pour `AlertService._partantsDeLaCourse`. Aucun pronostic n'est
/// semé, donc P4 ne peut pas écrire dans ce scénario.
Future<_Mesure> _mesurerP5({
  required int nbPartants,
  required String corps,
  required int slot,
}) async {
  // −40 min : `_fetchResultatAuto` est déclenché (diffMin <= −10, l.1820)
  // mais la détection DQ (diffMin > −35, l.1833) ne l'est pas → un seul
  // chemin réseau, celui du résultat.
  final dep = DateTime.now().subtract(const Duration(minutes: 40));
  final cle = 'R1C1_${_fmt(dep)}';

  // Le pronostic DOIT exister : `AlertService` enregistre le résultat sous
  // `tc.iaMemKey`, exactement comme en production. Aucun pronostic n'est
  // attendu en retour de P4 ici : `_recupererResultatsBatch` exige
  // `courseDiff.inMinutes >= 10` (data_refresh_service.dart:1147) et
  // [dep] vaut −40 min → P4 n'écrit rien dans ce scénario.
  await _reset(
    pronostics: [_pronostic(cle: cle, date: dep)],
    tracked: [_suivi(heureDepart: dep, slot: slot, iaMemKey: cle)],
  );

  final poidsAvant = IaMemoryService.instance.poids.nbMisesAJour;
  final eloAvant = EloService.instance.nbChevauxSuivis;

  // Mesure de l'état PRISE AVANT la purge du suivi. Lire après
  // `_viderSuivi()` rendait la mesure structurellement nulle : `trackedCourses`
  // était vidé, donc relu à `null` quel que soit le résultat réel de la
  // production (défaut du harnais précédent).
  //
  // ⚠️ CE QUE P5 MODIFIE RÉELLEMENT (vérifié dans la production) :
  //   • `IaMemoryService.enregistrerResultat(...)` → `arriveeReelle` du
  //     pronostic (alert_service.dart:2719-2723) ;
  //   • une alerte de résultat via `_addAlert` (l.2651).
  //   Il n'écrit JAMAIS dans `_trackedCourses` : `withResultat()` n'est
  //   appelé que par `enregistrerResultatPari` (l.772-786), dont l'unique
  //   appelant est `mes_paris_screen.dart`. Observer `tc.isGagne` était donc
  //   une mesure de la mauvaise surface.
  late _Mesure mesure;

  try {
    await _avecPmu(
      () async {
        // 1. Charger le programme (peuple `_reunions`, donc les partants).
        await DataRefreshService.instance.refresh();
        // 2. Ouvrir les alertes : le watchdog évalue immédiatement.
        await _ouvrirAlertes();
        // 3. Laisser aboutir `_fetchResultatAuto` (asynchrone, non attendu).
        //    On attend une écriture RÉELLE : le pronostic devient résolu, ou
        //    une alerte de résultat apparaît. Un refus ne produit ni l'un ni
        //    l'autre : le délai borne alors simplement.
        await _attendreQue(
          () =>
              (_pronosticDe(cle)?.resultatsReels ?? false) ||
              AlertService.instance.alerts
                  .any((a) => a.id.contains('_resultat')),
          ms: 3000,
        );
      },
      corps: corps,
      dep: dep,
      nbPartants: nbPartants,
    );

    var nbEnMemoire = 0;
    for (final r in DataRefreshService.instance.reunions) {
      if (r.code != 'R1') continue;
      for (final c in r.courses) {
        if (c.numCourse == 1) nbEnMemoire = c.partants.length;
      }
    }

    // Alerte de résultat produite par P5, si elle existe.
    final alertes = AlertService.instance.alerts
        .where((a) => a.id.contains('_resultat'))
        .toList();
    final p = _pronosticDe(cle);

    mesure = _Mesure(
      arrivee: p?.arriveeReelle,
      resultatsReels: p?.resultatsReels ?? false,
      nbMisesAJourPoids:
          IaMemoryService.instance.poids.nbMisesAJour - poidsAvant,
      nbChevauxElo: EloService.instance.nbChevauxSuivis - eloAvant,
      nbPartantsEnMemoire: nbEnMemoire,
      messageResultat: alertes.isEmpty ? null : alertes.first.message,
      alerteResultat: alertes.isNotEmpty,
    );
  } finally {
    await _viderSuivi();
  }

  return mesure;
}

void _ligne(String t, String attendu, String obtenu, String verdict) {
  debugPrint('| $t | $attendu | $obtenu | $verdict |');
}

// ─────────────────────────────── Tests ─────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(_prefs());
    SharedPreferences.resetStatic();
    ZoneTurfService.viderCachePourResetComplet();
    DataRefreshService.instance.viderMemoirePourResetComplet();
    await EloService.instance.reinitialiser();
    await IaMemoryService.instance.recharger();
  });

  tearDown(() async {
    await _viderSuivi();
  });

  // `AlertService.instance` est un singleton : son `Timer.periodic(60 s)` ne
  // peut être annulé qu'une fois. On ferme donc le service à la FIN du
  // fichier, jamais entre deux tests.
  tearDownAll(() async {
    await _fermerAlertes();
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  P4 — 9 partants RÉELLEMENT chargés, arrivée contenant 99.
  //  Attendu : REFUS. Ni enregistrement, ni apprentissage, ni ELO.
  // ═══════════════════════════════════════════════════════════════════════
  test('P4 — 99 absent des partants chargés : arrivée REFUSÉE, rien écrit',
      () async {
    final dep = DateTime.now().subtract(const Duration(minutes: 60));
    final m = await _mesurerP4(
      nbPartants: 9,
      corps: _corpsArrivee(dernier: 99),
      dep: dep,
    );

    debugPrint('');
    debugPrint('| Scénario | Attendu | Obtenu | Verdict |');
    debugPrint('|---|---|---|---|');
    _ligne('P4 / 99 + 9 partants', 'partants=9', '${m.nbPartantsEnMemoire}',
        m.nbPartantsEnMemoire == 9 ? 'PASS' : 'FAIL');
    _ligne('P4 / 99 + 9 partants', 'arrivee=null', _arr(m.arrivee),
        m.arrivee == null ? 'PASS' : 'FAIL');
    _ligne('P4 / 99 + 9 partants', 'resultatsReels=false',
        '${m.resultatsReels}', m.resultatsReels == false ? 'PASS' : 'FAIL');
    _ligne('P4 / 99 + 9 partants', 'poids inchangés',
        'ΔnbMisesAJour=${m.nbMisesAJourPoids}',
        m.nbMisesAJourPoids == 0 ? 'PASS' : 'FAIL');
    _ligne('P4 / 99 + 9 partants', 'ELO inchangé', 'Δchevaux=${m.nbChevauxElo}',
        m.nbChevauxElo == 0 ? 'PASS' : 'FAIL');

    // TÉMOIN : la liste de partants était bien disponible. Sans ce contrôle,
    // un refus pourrait venir d'une absence de liste et non du contrôle.
    expect(m.nbPartantsEnMemoire, 9,
        reason: 'TÉMOIN : les 9 partants doivent être réellement chargés '
            'dans `DataRefreshService.reunions` — sinon le contrôle '
            'd\'appartenance est impossible et le test ne prouve rien');
    expect(m.arrivee, isNull,
        reason: 'P4 (A6 §5) : 99 n\'appartient pas aux partants chargés → '
            'arrivée REFUSÉE, donc rien n\'est enregistré');
    expect(m.resultatsReels, isFalse,
        reason: 'P4 : une arrivée refusée ne résout pas le pronostic');
    expect(m.nbMisesAJourPoids, 0,
        reason: 'P4 : une arrivée refusée ne déclenche AUCUN apprentissage '
            '(gradient jamais appelé)');
    expect(m.nbChevauxElo, 0,
        reason: 'P4 : une arrivée refusée ne déclenche AUCUNE mise à jour ELO '
            '(`if (arrivee.isEmpty) continue;` précède l\'appel)');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  P4 — arrivée composée UNIQUEMENT de numéros valides (7-4-2-9-1).
  //  Attendu : ACCEPTÉE, enregistrée, et l'ELO est mis à jour (partants
  //  présents). Sert de contre-épreuve au scénario précédent : le refus de
  //  99 n'est pas un refus systématique.
  // ═══════════════════════════════════════════════════════════════════════
  test('P4 — arrivée 100 % valide (7-4-2-9-1) : ACCEPTÉE et enregistrée',
      () async {
    final dep = DateTime.now().subtract(const Duration(minutes: 60));
    final m = await _mesurerP4(
      nbPartants: 9,
      corps: _corpsArrivee(dernier: 1),
      dep: dep,
    );

    _ligne('P4 / 7-4-2-9-1', 'partants=9', '${m.nbPartantsEnMemoire}',
        m.nbPartantsEnMemoire == 9 ? 'PASS' : 'FAIL');
    _ligne('P4 / 7-4-2-9-1', 'arrivee=7-4-2-9-1', _arr(m.arrivee),
        m.arrivee == null ? 'FAIL' : 'PASS');
    // CONTRE-ÉPREUVE ELO : une arrivée ACCEPTÉE déclenche bien la mise à jour
    // ELO (les partants sont chargés). Sans cette ligne, le test ne prouverait
    // pas que l'absence de mise à jour du scénario refusé vient du refus.
    _ligne('P4 / 7-4-2-9-1', 'ELO mis à jour', 'Δchevaux=${m.nbChevauxElo}',
        m.nbChevauxElo > 0 ? 'PASS' : 'FAIL');
    _ligne('P4 / 7-4-2-9-1', 'arrivée reçue par EloService',
        m.arriveeElo?.join('-') ?? 'JAMAIS ATTEINTE',
        m.arriveeElo == null ? 'FAIL' : 'PASS');

    expect(m.nbPartantsEnMemoire, 9,
        reason: 'TÉMOIN : liste de partants réellement disponible');
    expect(m.arrivee, isNotNull,
        reason: 'P4 : une arrivée ne contenant que des numéros valides doit '
            'rester ACCEPTÉE');
    expect(m.arrivee, equals(<int>[7, 4, 2, 9, 1]),
        reason: 'P4 : l\'arrivée acceptée est celle du rapport ordonné, et '
            'aucun numéro n\'en a été retiré');
    expect(m.resultatsReels, isTrue,
        reason: 'P4 : une arrivée acceptée résout bien le pronostic');

    // ══════════════════════════════════════════════════════════════════
    //  ÉTAPE ELO — PREUVE D'ACHÈVEMENT EFFECTIF (et non d'un Δ trompeur)
    //
    //  ── DÉFAUT DU HARNAIS, MESURÉ ──────────────────────────────────────
    //  v1 assertait seulement `ΔnbChevauxSuivis > 0`, après avoir attendu
    //  `resultatsReels == true`. Or cette condition devient vraie dans
    //  `enregistrerResultat(...)` (l.1491), AVANT `_mettreAJourEloApresArrivee`
    //  (l.1514). La mesure tombait donc avant l'étape ELO : mesuré
    //  `Δchevaux=0` alors que le journal de production affichait ensuite
    //  `✅ 5 ELO mis à jour (discipline: Attelé) — persistance: persistee`.
    //  Un delta n'est pas non plus une preuve d'achèvement : il vaut 0 aussi
    //  bien si l'étape n'a pas commencé que si elle a échoué.
    //
    //  ── PREUVES EXIGÉES ICI ────────────────────────────────────────────
    //    1. l'étape a été ATTEINTE, avec le bon contenu ;
    //    2. la persistance est CONFIRMÉE (`persistee`) ;
    //    3. les ratings sont réellement SUR LE DISQUE ;
    //    4. les valeurs sont celles qu'impose la mise à jour ;
    //    5. aucune double application (registre) ni double écriture.
    // ══════════════════════════════════════════════════════════════════
    expect(m.arriveeElo, isNotNull,
        reason: 'l\'étape `_mettreAJourEloApresArrivee` doit être ATTEINTE. '
            'Cette assertion sépare « jamais atteinte » de « atteinte sans '
            'effet », ce que le seul delta ne permettait pas');
    expect(m.arriveeElo, equals(<int>[7, 4, 2, 9, 1]),
        reason: 'l\'arrivée reçue par EloService est celle qui a été enregistrée');
    expect(m.etatPersistanceElo, 'persistee',
        reason: 'la persistance des ratings doit être CONFIRMÉE, pas seulement '
            'tentée (EtatPersistanceElo.persistee)');
    expect(m.cleCourseElo, startsWith('R1C1_'),
        reason: 'l\'identité de course transmise est réelle, jamais fabriquée');
    expect(m.deltaPersistees, greaterThan(0),
        reason: 'au moins une écriture de `elo_ratings_v2` a été CONFIRMÉE par '
            '`setString → true` pendant ce scénario');

    // 3. Ratings réellement PERSISTÉS.
    //
    //    ── CE QUE LA FORMULE IMPOSE, MESURÉ PUIS EXPLIQUÉ ────────────────
    //    L'état est vierge : AUCUN des neuf chevaux n'a d'entrée de rating
    //    avant ce scénario. Cinq entrées nouvelles sur le disque sont donc,
    //    à elles seules, la preuve que la mise à jour a été écrite.
    //
    //    ⚠️ ASSERTION RETIRÉE APRÈS MESURE : j'avais d'abord exigé que les
    //    cinq ratings diffèrent de 1500. La mesure l'a démenti — CHEVAL_2 vaut
    //    exactement 1500.0000 — et ce n'est PAS un défaut : le calcul est
    //    apparié et symétrique. Partant tous de 1500, les gains d'un cheval
    //    du milieu (+0,85·k comme gagnant de ses duels) et ses pertes
    //    (−0,85·k comme perdant) s'annulent EXACTEMENT quand kA == kB, ce qui
    //    est le cas ici (les deux compteurs `nbCourses` valent 0, donc les
    //    deux K sont ceux du débutant). Exiger un écart aurait donc exigé de
    //    modifier la formule — interdit. L'assertion est remplacée par des
    //    preuves qui ne dépendent d'aucune valeur de formule.
    expect(m.ratingsDisque.length, 5,
        reason: 'les CINQ chevaux de l\'arrivée doivent être présents sur le '
            'disque alors qu\'AUCUN n\'y était avant : c\'est la preuve de '
            'persistance, et non de simple mutation en RAM');
    debugPrint('[P4] ratings SUR DISQUE = '
        '${m.ratingsDisque.entries.map((e) => "${e.key}=${e.value.toStringAsFixed(4)}").join(" | ")}');

    // Le critère M n'est pas resté figé : les ratings persistés ne sont pas
    // tous identiques. C'est la preuve qu'un calcul a bien eu lieu, sans
    // affirmer qu'aucun delta ne peut être nul.
    final valeursDistinctes = m.ratingsDisque.values.toSet();
    expect(valeursDistinctes.length, greaterThan(1),
        reason: 'les ratings persistés doivent être DIFFÉRENCIÉS. S\'ils '
            'valaient tous 1500.0, la mise à jour n\'aurait rien calculé. '
            'Mesuré : 4 valeurs sur 5 diffèrent de 1500, la 5e étant '
            'légitimement à l\'équilibre exact de la formule appariée');

    // 5. Anti-double-application : le registre ELO doit contenir EXACTEMENT
    //    une entrée de type `course` pour ce scénario. Deux entrées
    //    prouveraient un rejeu ; zéro prouverait qu'aucune course n'a été
    //    consignée.
    expect(m.nbCoursesRegistre, 1,
        reason: 'le registre ELO doit contenir UNE SEULE course consignée. '
            'Deux entrées = double application ; zéro = aucune protection');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  P4 — liste INDISPONIBLE (aucun participant servi) et arrivée avec 99.
  //  Attendu : l'absence de liste n'est PAS une preuve d'incohérence → aucun
  //  refus au motif du 99. Mesure : l'arrivée est conservée TELLE QUELLE.
  // ═══════════════════════════════════════════════════════════════════════
  test('P4 — liste indisponible ≠ liste incohérente : 99 non refusé',
      () async {
    final dep = DateTime.now().subtract(const Duration(minutes: 60));
    final m = await _mesurerP4(
      nbPartants: 0,
      corps: _corpsArrivee(dernier: 99),
      dep: dep,
    );

    _ligne('P4 / liste absente', 'partants=0', '${m.nbPartantsEnMemoire}',
        m.nbPartantsEnMemoire == 0 ? 'PASS' : 'FAIL');
    _ligne('P4 / liste absente', '99 conservé (aucun refus possible)',
        _arr(m.arrivee), (m.arrivee?.contains(99) ?? false) ? 'PASS' : 'FAIL');

    expect(m.nbPartantsEnMemoire, 0,
        reason: 'TÉMOIN : aucun partant chargé → contrôle IMPOSSIBLE');
    expect(m.arrivee, isNotNull,
        reason: 'P4 (A6 §5) : sans liste fiable, AUCUN refus ne doit être '
            'prononcé — l\'absence de données n\'est pas une incohérence');
    expect(m.arrivee!.contains(99), isTrue,
        reason: 'P4 : la décision n\'a pas été refusée au motif du 99 '
            '(contrôle impossible), le numéro reste donc dans la liste');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  P5 — même exigence, chemin `AlertService`.
  //  Le programme est chargé par `refresh()` AVANT `AlertService.init()`,
  //  donc `_partantsDeLaCourse` lit une liste RÉELLE.
  // ═══════════════════════════════════════════════════════════════════════
  test('P5 — 99 absent des partants chargés : rien n\'est enregistré',
      () async {
    final m = await _mesurerP5(
      nbPartants: 9,
      corps: _corpsArrivee(dernier: 99),
      slot: _slot++,
    );

    _ligne('P5 / 99 + 9 partants', 'partants=9', '${m.nbPartantsEnMemoire}',
        m.nbPartantsEnMemoire == 9 ? 'PASS' : 'FAIL');
    _ligne('P5 / 99 + 9 partants', 'aucune arrivée enregistrée (99 refusé)',
        _arr(m.arrivee), (m.arrivee?.contains(99) ?? false) ? 'FAIL' : 'PASS');
    _ligne('P5 / 99 + 9 partants', 'poids inchangés',
        'ΔnbMisesAJour=${m.nbMisesAJourPoids}',
        m.nbMisesAJourPoids == 0 ? 'PASS' : 'FAIL');

    expect(m.nbPartantsEnMemoire, 9,
        reason: 'TÉMOIN : les 9 partants sont réellement disponibles pour '
            '`AlertService._partantsDeLaCourse`');
    expect(m.arrivee?.contains(99) ?? false, isFalse,
        reason: 'P5 (A6 §5) : 99 n\'appartient pas aux partants → '
            '`decision.peutEnregistrer` est faux, `arriveeRetenue` est vide, '
            'donc 99 ne peut pas être enregistré');
    expect(m.nbMisesAJourPoids, 0,
        reason: 'P5 : aucun apprentissage déclenché');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  P5 — arrivée 100 % valide : reste acceptée (contre-épreuve).
  // ═══════════════════════════════════════════════════════════════════════
  test('P5 — arrivée 100 % valide (7-4-2-9-1) : acceptée', () async {
    final m = await _mesurerP5(
      nbPartants: 9,
      corps: _corpsArrivee(dernier: 1),
      slot: _slot++,
    );

    _ligne('P5 / 7-4-2-9-1', 'partants=9', '${m.nbPartantsEnMemoire}',
        m.nbPartantsEnMemoire == 9 ? 'PASS' : 'FAIL');
    _ligne('P5 / 7-4-2-9-1', 'arrivée enregistrée', _arr(m.arrivee),
        (m.arrivee?.isNotEmpty ?? false) ? 'PASS' : 'FAIL');

    expect(m.nbPartantsEnMemoire, 9,
        reason: 'TÉMOIN : liste de partants réellement disponible');
    expect(m.arrivee, isNotNull,
        reason: 'P5 : une arrivée entièrement valide reste acceptée');
    expect(m.arrivee, equals(<int>[7, 4, 2, 9, 1]),
        reason: 'P5 : l\'ordre retenu est celui du rapport ordonné');
  });

  // ═══════════════════════════════════════════════════════════════════════
  //  P5 — liste indisponible : aucun refus au motif du 99.
  // ═══════════════════════════════════════════════════════════════════════
  test('P5 — liste indisponible ≠ liste incohérente : 99 non refusé',
      () async {
    final m = await _mesurerP5(
      nbPartants: 0,
      corps: _corpsArrivee(dernier: 99),
      slot: _slot++,
    );

    _ligne('P5 / liste absente', 'partants=0', '${m.nbPartantsEnMemoire}',
        m.nbPartantsEnMemoire == 0 ? 'PASS' : 'FAIL');
    _ligne('P5 / liste absente', '99 conservé (aucun refus possible)',
        _arr(m.arrivee), (m.arrivee?.contains(99) ?? false) ? 'PASS' : 'FAIL');

    expect(m.nbPartantsEnMemoire, 0,
        reason: 'TÉMOIN : aucun partant chargé → contrôle IMPOSSIBLE');
    expect(m.arrivee!.contains(99), isTrue,
        reason: 'P5 (A6 §5) : sans liste fiable, aucun refus au motif du 99');
  });
}
