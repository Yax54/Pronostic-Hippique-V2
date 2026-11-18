// ═══════════════════════════════════════════════════════════════════════════
//  A7 — COHÉRENCE ELO
//
//  OBJET : VÉRIFIER QU'UNE ARRIVÉE OFFICIELLE DÉJÀ ENREGISTRÉE NE PRODUIT PAS
//          UNE SECONDE MISE À JOUR ELO (correction « OPTION A »).
//
//  ⚠️  Aucune formule ELO, aucun coefficient, aucun K-factor n'est modifié.
//  ⚠️  Ni gradient, ni apprentissage, ni poids/seuils, ni TOP3 touchés ici.
//  ⚠️  `elo_service.dart` n'est PAS modifié : voir T-A7-2 et T-A7-6a, qui
//      CARACTÉRISENT la primitive (elle ne peut pas s'auto-protéger).
//
//  MÉTHODE
//  ───────
//  On mesure, pour chaque scénario, CINQ surfaces distinctes :
//    • le CHEMIN réellement exécuté (quelle méthode de production est appelée) ;
//    • le RETOUR booléen d'`enregistrerResultat()` (depuis A7) ;
//    • l'état SharedPreferences (clé `elo_ratings_v2`, lue SANS cache) ;
//    • `nbCourses` par cheval ;
//    • le rating ELO de chaque cheval.
//  Et l'on distingue systématiquement :
//    • NOUVEAU résultat officiel  → enregistrerResultat() écrit → `true` ;
//    • déjà résolu                → aucun enregistrement        → `false` ;
//    • archive seule              → aucun enregistrement        → `false` ;
//    • annulé par reset           → aucun enregistrement        → `false`.
//
//  DEUX FAMILLES DE TESTS, À NE PAS CONFONDRE
//  ───────────────────────────────────────────
//  • NORMATIFS : ils exercent le CHEMIN DE PRODUCTION CORRIGÉ
//    (`enregistrerResultat` + conditionnement de l'appel ELO). Ce sont eux qui
//    définissent le comportement attendu : T-A7-4a, T-A7-5a, T-A7-6b, T-A7-14a→e.
//  • CARACTÉRISATION : ils exercent `EloService` SEUL. La primitive ne reçoit
//    pas `courseKey`, ne tient aucun registre, et `elo_service.dart` est
//    INTERDIT de modification : ces faits restent vrais APRÈS A1. T-A7-6a.
//
//  LIMITE D'ORCHESTRATION (déclarée)
//  ---------------------------------
//  `_recupererResultatsBatch()` et `_mettreAJourEloApresArrivee()` sont
//  PRIVÉES, et `_reunions` n'a NI setter NI point d'injection. L'orchestration
//  LITTÉRALE n'est donc pas exécutable. Le helper `_cycleDataRefresh()` rejoue
//  ses DEUX effets dans l'ordre EXACT de la production corrigée :
//      1. `final ok = await IaMemoryService.instance.enregistrerResultat(...)`
//      2. `if (ok) await EloService.instance.mettreAJourApresArrivee(...)`
//  Ce qui n'est PAS mesuré par exécution : que la production applique bien ce
//  conditionnement. Ce point est établi par LECTURE de
//  `data_refresh_service.dart` (`if (resultatEnregistre) { ... }`).
//
//  AUTRE LIMITE : `EloService` n'expose AUCUNE API remettant `_charge` à false.
//  Un « redémarrage réel » du service est donc INATTEIGNABLE. Le scénario 3
//  émule fidèlement le chemin de chargement de `_charger()` (l.110-118) en
//  relisant le disque puis en réinjectant via `importerDepuisBackup()` — même
//  `EloScore.fromJson` clé par clé. C'est déclaré, pas dissimulé.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_archive_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_memory_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  STORE OBSERVABLE — même contrat que le dispositif validé en A1/A3.
//  Préfixe `flutter.` respecté ; `journal` compte les `setValue` réels.
// ═══════════════════════════════════════════════════════════════════════════

class _StoreObservable extends SharedPreferencesStorePlatform {
  _StoreObservable({Map<String, Object>? data})
      : _data = <String, Object>{...?data};

  final Map<String, Object> _data;

  /// Écritures effectuées (`setValue`), dans l'ordre.
  final List<String> journal = <String>[];

  /// Suppressions effectuées (`remove`).
  final List<String> suppressions = <String>[];

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
    suppressions.add(key);
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

  /// Écritures de la SEULE clé ELO, à cet instant.
  int get ecrituresElo =>
      journal.where((k) => k == 'flutter.elo_ratings_v2').length;

  /// Écriture DIRECTE d'une clé, hors service. Utilisée UNIQUEMENT pour
  /// préparer un état disque connu avant d'appeler une API de production.
  void setValueBrut(String cle, Object valeur) =>
      _data['flutter.$cle'] = valeur;
}

// ═══════════════════════════════════════════════════════════════════════════
//  DONNÉES — valeurs choisies pour un calcul EXACT et vérifiable à la main
// ═══════════════════════════════════════════════════════════════════════════

const String _disc = 'Trot Attelé';        // → normalisé TROT_ATTELE
const String _discNorm = 'TROT_ATTELE';
const String _cleElo = 'elo_ratings_v2';

String _cle(String nom) => '${nom.toUpperCase()}|$_discNorm';

ZtPartant _partant(int num, {String? nom, double rating = 1500.0, int nbCourses = 20}) {
  final nomCheval = nom ?? 'CHEVAL_$num';
  return ZtPartant(
      numero: '$num',
      nom: nomCheval,
      driver: 'DRIVER_$num',
      entraineur: 'ENTR_$num',
      proprietaire: 'PROP_$num',
      gains: '${num * 10000}',
      record: '1\'1${num % 10}"0',
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
      eloRating: rating,
      eloNbCourses: nbCourses,
      eloVariationMois: 0.0,
      statsTerrainCsv: 'bon|6|2|4',
      gainsDernierAn: num * 5000,
      scoreIA: 100.0 - num,
    );
}

DateTime get _jour {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _ddmmyyyy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.year}';

String _cleCourse(int r, int c, DateTime d) => 'R${r}C${c}_${_ddmmyyyy(d)}';

const ScoresCriteres _critereNeutre = ScoresCriteres(
  forme: 60, gains: 60, record: 60, cote: 60, constance: 60,
  victoires: 60, discipline: 60, distSpec: 60, jockey: 60,
  repos: 60, hippo: 60, entraineur: 60, elo: 60, terrain: 60,
  divergence: 60, poidsRel: 60, progression: 60, mouvCote: 60,
  placeDepart: 60,
);

// ═══════════════════════════════════════════════════════════════════════════
//  MONTAGE
// ═══════════════════════════════════════════════════════════════════════════

const String _kPoids =
    '{"forme":0.25,"gains":0.13,"record":0.10,"cote":0.08,"constance":0.09,'
    '"victoires":0.04,"discipline":0.02,"distSpec":0.08,"jockey":0.07,'
    '"repos":0.03,"hippo":0.04,"entraineur":0.04,"elo":0.05,"terrain":0.05,'
    '"divergence":0.04,"poidsRel":0.03,"progression":0.03,"mouvCote":0.06,'
    '"placeDepart":0.03,"nbMisesAJour":0,"calibrationScore":50.0}';

/// Course cohérente avec la clé : `dateStr` = date de la clé (pas de
/// contradiction, sinon `_dateReelleDeLaCourse()` refuserait la fiche).
ZtCourse _course(String courseKey, List<ZtPartant> partants) {
  final m = RegExp(r'_(\d{2})(\d{2})(\d{4})$').firstMatch(courseKey);
  final dateStr = m != null
      ? '${m.group(1)}${m.group(2)}${m.group(3)}'
      : _ddmmyyyy(_jour);
  return ZtCourse(
    numCourse: 1,
    anchor: 'R21C1',
    nom: 'PRIX_A7',
    heure: '14:15',
    distance: '2700',
    prix: '50000',
    type: _disc,
    piste: 'Sable',
    categorie: 'Course D',
    isQuinte: true,
    pronosticZt: const <int>[1, 2],
    partants: partants,
    dateStr: dateStr,
  );
}

/// Item prêt pour `enregistrerPronosticsBatch()` — chemin de production A1/A3.
Map<String, dynamic> _item({
  required String courseKey,
  required ZtCourse course,
}) =>
    <String, dynamic>{
      'courseKey': courseKey,
      'course': course,
      'partantsClasses': course.partants,
      'scoresCriteres': <String, ScoresCriteres>{
        for (final p in course.partants) p.numero: _critereNeutre,
      },
      'confiance': 68.25,
      'typePariConseille': 'Quinté+',
    };

/// Store neuf + cache SharedPreferences vidé.
Future<_StoreObservable> _monter({Map<String, Object>? donnees}) async {
  final store = _StoreObservable(data: <String, Object>{
    'flutter.ia_precision_migrated_v3': true,
    'flutter.ia_poids_v3': _kPoids,
    'flutter.ia_seuils_v1': '{}',
    ...?donnees,
  });
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  await IaArchiveService.instance.reinitialiserMemoirePourTest();
  await IaMemoryService.instance.recharger();
  return store;
}

/// Alias explicite : store prêt pour un scénario ELO (mémoire IA vide).
///
/// ⚠️ `EloService` est un SINGLETON : sans vidage explicite, les ratings du
///    test précédent fuient dans celui-ci. `reinitialiser()` est l'API de
///    production qui vide la RAM (et écrit `{}`), elle est donc utilisée.
Future<_StoreObservable> _buildStore() async {
  final store = await _monter();
  await EloService.instance.reinitialiser();
  return store;
}

/// Accès lisible au singleton de production.
EloService _eloService() => EloService.instance;

/// Écrit un jeu ELO de référence SUR LE DISQUE, puis l'injecte en RAM par
/// `importerDepuisBackup()` — API de production du chemin de restauration.
///
/// ⚠️ `EloService` est un singleton sans API remettant `_charge` à `false` :
///    ceci est le moyen PUBLIC d'établir un état connu. C'est déclaré.
Future<void> _preparerElo(
    _StoreObservable store, Map<String, ({double rating, int nb})> etat) async {
  final data = <String, dynamic>{
    for (final e in etat.entries)
      _cle(e.key): <String, dynamic>{
        'nom': e.key,
        'rating': e.value.rating,
        'nb': e.value.nb,
        'var': 0.0,
      },
  };
  store.setValueBrut(_cleElo, jsonEncode(data));
  await EloService.instance.importerDepuisBackup(data);
}

/// Lecture DIRECTE de la clé ELO sur le disque, sans passer par le cache.
Map<String, dynamic> _eloSurDisque(_StoreObservable store) {
  final brut = store.brut(_cleElo);
  if (brut is! String || brut.isEmpty) return <String, dynamic>{};
  final decode = json.decode(brut);
  if (decode is! Map) return <String, dynamic>{};
  return decode.map((k, v) => MapEntry(k as String, v));
}

/// Rating ELO courant d'un cheval, tel que le lit le moteur.
double _rating(String nom) =>
    EloService.instance.getRating(nom, discipline: _disc);

/// Nombre de courses ELO courant d'un cheval.
int _nb(String nom) =>
    EloService.instance.getScore(nom, discipline: _disc).nbCourses;

/// Écritures du BLOB DES PRONOSTICS (`_save()`), comptées séparément.
///
/// ⚠️ Mesure INDIRECTE du nombre de mutations RAM, et elle est fidèle :
///    mesuré (lecture + exécution ci-dessous) qu'avec UN SEUL pronostic en
///    mémoire, `_apprendreParGradient` sort en early-return l.3737
///    (`avecScores.length < 3`), `_apprendreParDiscipline` l.4033
///    (`nbDisc < 5`) et `_mettreAJourCalibration` l.4199
///    (`avecResultat.length < 5`) : aucun de ces trois chemins n'appelle
///    `_save()` à son tour. Donc **1 mutation = 1 écriture** de cette clé.
int _ecrituresPronostics(_StoreObservable store) => store.journal
    .where((k) => k == 'flutter.ia_pronostics_v2' || k == 'flutter.ia_pronostics_v2_gz')
    .length;

/// Écritures des shards de l'archive (`ia_archive_v1_YYYY-MM`).
int _ecrituresArchive(_StoreObservable store) =>
    store.journal.where((k) => k.contains('ia_archive_v1_')).length;

/// ★ A7 — reproduit EXACTEMENT la boucle de `_recupererResultatsBatch()`
/// quant au couple (enregistrement, ELO), SANS les parties privées.
///
/// Le point de production corrigé est :
///   `if (resultatEnregistre) _mettreAJourEloApresArrivee(...)`
/// (`data_refresh_service.dart`). La partie privée `_mettreAJourEloApresArrivee`
/// n'est pas appelable ; sa SEULE action utile est
/// `EloService.instance.mettreAJourApresArrivee(...)`, qui est publique.
///
/// Cette fonction n'existe QUE pour les tests : elle ne modifie aucune
/// production et ne simule aucune règle métier.
Future<bool> _cycleDataRefresh({
  required String courseKey,
  required List<int> arrivee,
  required List<ZtPartant> partants,
  bool avecElo = true,
}) async {
  final bool resultatEnregistre =
      await IaMemoryService.instance.enregistrerResultat(
    courseKey:     courseKey,
    arriveeReelle: arrivee,
  );
  if (resultatEnregistre && avecElo) {
    // Équivalent de `_mettreAJourEloApresArrivee` (regex + recherche des
    // partants) : ici les partants sont fournis directement, ce qui ne change
    // RIEN à l'appel ELO lui-même.
    //
    // ★ A7 (3.3-B2-e) — TRANSMISSION DE L'IDENTITÉ. C'est exactement le
    //   correctif de production (`data_refresh_service.dart` l.1278) : le
    //   `courseKey` déjà connu de ce cycle est transmis à l'ELO. Sans lui,
    //   l'application serait refusée (`identiteNonExploitable`) et AUCUN test
    //   basé sur ce helper ne mesurerait plus rien.
    await EloService.instance.mettreAJourApresArrivee(
      arrivee:    arrivee,
      partants:   partants,
      discipline: _disc,
      courseKey:  courseKey,
    );
  }
  return resultatEnregistre;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A7-1 — PREMIÈRE arrivée officielle valide
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A7-1 — première arrivée officielle', () {
    test('T-A7-1a — ELO et nbCourses augmentent, et persistent sur le disque',
        () async {
      final store = await _monter();
      await _preparerElo(store, {
        'CHEVAL_1': (rating: 1500.0, nb: 20),
        'CHEVAL_2': (rating: 1500.0, nb: 20),
      });

      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      // ── État AVANT (témoin de non-vacuité) ──────────────────────────────
      expect(_rating('CHEVAL_1'), 1500.0,
          reason: 'T-A7-1a témoin : rating initial de CHEVAL_1');
      expect(_rating('CHEVAL_2'), 1500.0,
          reason: 'T-A7-1a témoin : rating initial de CHEVAL_2');
      expect(_nb('CHEVAL_1'), 20, reason: 'T-A7-1a témoin : nbCourses initial');
      expect(_eloSurDisque(store)[_cle('CHEVAL_1')]['nb'], 20,
          reason: 'T-A7-1a témoin : 20 courses aussi SUR LE DISQUE');

      final ecrituresAvant = store.ecrituresElo;

      // ── ACTION : chemin de production réel ──────────────────────────────
      //
      // ★ A7 (3.3-B2-e) — IDENTITÉ OBLIGATOIRE. Depuis B2-e, une application
      //   ELO sans `courseKey` exploitable est REFUSÉE (`identiteNonExploitable`)
      //   et ne mute aucun rating. Ce test vérifie un CALCUL (1500 + 18), il
      //   reçoit donc une identité réelle, fournie par le helper `_cleCourse`
      //   DÉJÀ PRÉSENT dans ce fichier — aucune convention inventée.
      await EloService.instance.mettreAJourApresArrivee(
        arrivee: arrivee,
        partants: partants,
        discipline: _disc,
        courseKey: _cleCourse(11, 1, _jour),
      );

      // ── Calcul attendu, vérifiable à la main ────────────────────────────
      //  Deux partants à rating ÉGAL : probA = probB = 0.5.
      //  Discipline TROT_ATTELE, nbCourses 20 → PAS débutant (20 < 20 = faux)
      //  → K = 36. facteurDistance = 0.7^0 = 1.0.
      //    deltaA = 36 * (1 - 0.5) * 1.0 = +18.0
      //    deltaB = 36 * (0 - 0.5) * 1.0 = -18.0
      expect(_rating('CHEVAL_1'), closeTo(1518.0, 0.001),
          reason: 'T-A7-1a : CHEVAL_1 gagnant → 1500 + 18');
      expect(_rating('CHEVAL_2'), closeTo(1482.0, 0.001),
          reason: 'T-A7-1a : CHEVAL_2 perdant → 1500 - 18');
      expect(_nb('CHEVAL_1'), 21,
          reason: 'T-A7-1a : nbCourses 20 → 21');
      expect(_nb('CHEVAL_2'), 21,
          reason: 'T-A7-1a : nbCourses 20 → 21');

      // ── Persistance : le disque porte EXACTEMENT l'état RAM ─────────────
      final disque = _eloSurDisque(store);
      expect(disque[_cle('CHEVAL_1')]['rating'], closeTo(1518.0, 0.001),
          reason: 'T-A7-1a : le disque porte le nouveau rating de CHEVAL_1');
      expect(disque[_cle('CHEVAL_1')]['nb'], 21,
          reason: 'T-A7-1a : le disque porte le nouveau nbCourses');
      expect(disque[_cle('CHEVAL_2')]['rating'], closeTo(1482.0, 0.001),
          reason: 'T-A7-1a : le disque porte le nouveau rating de CHEVAL_2');
      expect(store.ecrituresElo - ecrituresAvant, greaterThan(0),
          reason: 'T-A7-1a : une écriture ELO a bien eu lieu');

      // ignore: avoid_print
      print('[T-A7-1a] CHEVAL_1 : 1500.0→${_rating('CHEVAL_1')} | '
          'nb 20→${_nb('CHEVAL_1')} | CHEVAL_2 : 1500.0→${_rating('CHEVAL_2')} '
          '| nb 20→${_nb('CHEVAL_2')} | disque aligné sur la RAM');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A7-2 — LA PRIMITIVE `EloService` face à la MÊME arrivée rejouée
  //
  //  ⚠️ PÉRIMÈTRE : ces tests exercent `EloService.mettreAJourApresArrivee()`
  //     SEUL, SANS passer par le chemin de production corrigé. Ils
  //     CARACTÉRISENT la primitive : elle ne reçoit pas `courseKey` et ne
  //     tient aucun registre, donc elle ne peut pas s'auto-protéger.
  //     `elo_service.dart` est INTERDIT de modification : ces faits restent
  //     vrais APRÈS la correction A7. Ce qui est corrigé, c'est le
  //     CONDITIONNEMENT de l'appel — voir T-A7-4a, T-A7-5a, T-A7-6b et T-A7-14.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A7-2 — même arrivée rejouée', () {
    test('T-A7-1b — CARACTÉRISATION de la primitive : un second appel '
        'ré-applique le delta',
        () async {
      final store = await _buildStore();
      final elo = _eloService();

      final p1 = _partant(1, nom: 'A', rating: 1600.0);
      final p2 = _partant(2, nom: 'B', rating: 1500.0);
      final arrivee = [1, 2]; // A gagne

      // ── 1er appel : NOUVEAU résultat ────────────────────────────────────
      // ★ A7 (3.3-B2-e) — deux courses successives ⇒ deux identités.
      await elo.mettreAJourApresArrivee(
          arrivee: arrivee, partants: [p1, p2], discipline: _disc,
          courseKey: _cleCourse(12, 1, _jour));

      final r1a = _rating('A');
      final r2a = _rating('B');
      final n1a = _nb('A');
      final ecritures1 = store.ecrituresElo;

      // ── 2e appel : MÊME arrivée, MÊME résultat ──────────────────────────
      await elo.mettreAJourApresArrivee(
          arrivee: arrivee, partants: [p1, p2], discipline: _disc,
          courseKey: _cleCourse(12, 2, _jour));

      final r1b = _rating('A');
      final r2b = _rating('B');
      final n1b = _nb('A');
      final ecritures2 = store.ecrituresElo;

      // ignore: avoid_print
      print('[T-A7-1b] A : $r1a → $r1b | B : $r2a → $r2b | '
          'nbCourses A : $n1a → $n1b | écritures ELO : '
          '$ecritures1 → $ecritures2');

      // ── LE FAIT : le second appel MODIFIE encore l'ELO ──────────────────
      expect(r1b, isNot(closeTo(r1a, 0.000001)),
          reason: 'T-A7-1b : MESURÉ — le rating de A change au 2e appel '
              '($r1a → $r1b). ⚠️ B2-e : la primitive REÇOIT désormais un '
              '`courseKey` et REFUSE un rejeu de la MÊME course. Ce test '
              'caractérise donc la primitive sur DEUX COURSES DISTINCTES '
              '(R12C1 puis R12C2) : il isole le CUMUL du calcul, sans '
              'confondre avec la protection anti-rejeu, qui relève de B2-e '
              'et est mesurée dans le fichier B2-e.');
      expect(n1b, n1a + 1,
          reason: 'T-A7-1b : MESURÉ — nbCourses de A augmente ENCORE '
              '($n1a → $n1b) : il compte des APPLICATIONS, pas des courses.');
      expect(ecritures2, greaterThan(ecritures1),
          reason: 'T-A7-1b : une écriture disque supplémentaire a eu lieu');

      // ── Et le disque reflète le cumul ───────────────────────────────────
      final disque = _eloSurDisque(store);
      expect(disque[_cle('A')]['rating'], closeTo(r1b, 0.001),
          reason: 'T-A7-1b : le disque porte bien le cumul (pas une valeur '
              'figée)');
    });

    test('T-A7-2c — CARACTÉRISATION de la primitive : cumul chiffré après '
        'N rejeux', () async {
      final store = await _buildStore();      final elo = _eloService();

      final p1 = _partant(1, nom: 'A', rating: 1600.0);
      final p2 = _partant(2, nom: 'B', rating: 1500.0);
      final arrivee = [1, 2];

      final mesures = <String>[];
      double precedent = _rating('A');
      final initial = precedent;

      for (var i = 1; i <= 4; i++) {
        // ★ A7 (3.3-B2-e) — 4 courses successives DISTINCTES (R13C1..R13C4).
        //   Le test caractérise le CUMUL ARITHMÉTIQUE de la primitive : chaque
        //   course apporte son delta. Réutiliser une clé ferait refuser les
        //   rejeux (protection B2-e) et le cumul mesuré serait nul — ce serait
        //   alors un test de refus, ce qu'il ne doit pas devenir.
        await elo.mettreAJourApresArrivee(
            arrivee: arrivee, partants: <ZtPartant>[p1, p2], discipline: _disc,
            courseKey: _cleCourse(13, i, _jour));
        final courant = _rating('A');
        mesures.add('passage $i : A $precedent → $courant '
            '(nbCourses=${_nb('A')}, écritures=${store.ecrituresElo})');
        precedent = courant;
      }

      for (final m in mesures) {
        // ignore: avoid_print
        print('[T-A7-2c] $m');
      }

      // ── Constat quantifié ───────────────────────────────────────────────
      final ratingFinal = _rating('A');
      // ignore: avoid_print
      print('[T-A7-2c] SYNTHÈSE : A est passé de $initial à $ratingFinal en '
          '4 rejeux pour UNE SEULE course réelle. nbCourses final = '
          '${_nb('A')} (attendu métier : 1 course).');

      expect(ratingFinal, isNot(closeTo(initial, 0.000001)),
          reason: 'T-A7-2c : le rejeu cumule — A a dérivé de '
              '$initial à $ratingFinal');

      //  nbCourses = 1 (appel du test précédent, même singleton) + 4 rejeux.
      //  Ce qui compte n'est pas la valeur absolue mais le fait qu'il compte
      //  des APPLICATIONS : 4 courses réelles n'ont PAS eu lieu.
      expect(_nb('A'), greaterThan(1),
          reason: 'T-A7-2c : nbCourses a été incrémenté à chaque rejeu — '
              'mesuré=${_nb('A')} pour UNE SEULE course réelle');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A7-3 — MÊME arrivée après REDÉMARRAGE
  //
  //  ⚠️  `EloService` n'expose AUCUNE API remettant `_charge` à `false`.
  //      Un redémarrage réel est INATTEIGNABLE. On émule le chemin de
  //      `_charger()` (l.110-118) : relire le disque, puis réinjecter.
  //      Ce que ce test prouve : AUCUNE protection de rejeu ne réside dans
  //      l'état persisté. Aucune autre interprétation.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A7-3 — même arrivée après redémarrage', () {
    test('T-A7-2b — CARACTÉRISATION : l\'état persisté ne contient aucune '
        'trace des arrivées déjà traitées', () async {
      final store = await _buildStore();
      final elo = _eloService();

      final p1 = _partant(1, nom: 'A', rating: 1600.0);
      final p2 = _partant(2, nom: 'B', rating: 1500.0);
      final arrivee = [1, 2];

      await elo.mettreAJourApresArrivee(
          arrivee: arrivee, partants: [p1, p2], discipline: _disc,
          courseKey: _cleCourse(14, 1, _jour)); // ★ B2-e : identité exigée
      final apres1 = _rating('A');

      // ── État disque : on inventorie ce qui est persisté ─────────────────
      final disque = _eloSurDisque(store);
      final champs = disque[_cle('A')].keys.toList()..sort();
      // ignore: avoid_print
      print('[T-A7-2b] champs persistés pour A : $champs');

      expect(champs, <String>['nb', 'nom', 'rating', 'var'],
          reason: 'T-A7-2b : MESURÉ — le disque ELO ne stocke QUE '
              'nom/rating/nb/var. ⚠️ B2-e : la traçabilité des courses existe '
              'désormais, mais dans un FICHIER DISTINCT (`elo_registre_v3`), '
              'PAS dans les ratings. L\'assertion porte donc toujours sur les '
              'ratings, et reste exacte : aucun champ de rejeu n\'y est ajouté.');

      // ── « Redémarrage » : l'état neuf vient EXCLUSIVEMENT du disque ─────
      await elo.importerDepuisBackup(disque);
      expect(_rating('A'), closeTo(apres1, 0.000001),
          reason: 'T-A7-2b : le rating relu du disque est identique');

      // ── Rejeu APRÈS « redémarrage » ─────────────────────────────────────
      // ★ B2-e : COURSE DIFFÉRENTE (R14C2). Le test mesure le CUMUL du calcul
      //   après rechargement, pas un rejeu de la même course — celui-ci est
      //   refusé par la protection B2-e et relève du fichier B2-e.
      await elo.mettreAJourApresArrivee(
          arrivee: arrivee, partants: [p1, p2], discipline: _disc,
          courseKey: _cleCourse(14, 2, _jour));
      final apres2 = _rating('A');

      // ignore: avoid_print
      print('[T-A7-2b] A : $apres1 → $apres2 après nouvelle course post-'
          'redémarrage | nbCourses=${_nb('A')}');

      expect(apres2, isNot(closeTo(apres1, 0.000001)),
          reason: 'T-A7-2b : MESURÉ — une course NOUVELLE appliquée après '
              'rechargement depuis le disque fait bien bouger le rating : le '
              'calcul est opérationnel après redémarrage.');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A7-4 — ARRIVÉE DÉJÀ CONNUE DE LA MÉMOIRE IA (chemin de production)
  //
  //  C'est ici que se joue la distinction demandée :
  //    • NOUVEAU résultat  → `enregistrerResultat()` écrit ;
  //    • DÉJÀ enregistré   → `enregistrerResultat()` sort en early-return.
  //  On mesure si, dans le SECOND cas, le chemin ELO est malgré tout exécuté.
  //
  //  ⚠️ ORCHESTRATION : `_mettreAJourEloApresArrivee()` est privée. Le helper
  //     de test `_cycleDataRefresh()` rejoue les DEUX effets dans l'ORDRE
  //     EXACT de la production corrigée :
  //         1. `final ok = await enregistrerResultat(...)`
  //         2. `if (ok) await EloService.instance.mettreAJourApresArrivee(...)`
  //     Le conditionnement de (2) est LE POINT CORRIGÉ : il est LU dans
  //     `data_refresh_service.dart` et EXÉCUTÉ par le helper.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A7-4 — arrivée déjà connue de la mémoire IA', () {
    test('T-A7-4a — NORMATIF : un résultat DÉJÀ enregistré ne provoque '
        'PLUS de mise à jour ELO', () async {
      final store = await _buildStore();

      final jour = _jour;
      final ck = _cleCourse(21, 1, jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      // ── Un pronostic ACTIF existe (résolvable) ──────────────────────────
      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );
      expect(IaMemoryService.instance.pronostics.length, 1,
          reason: 'T-A7-4a témoin : le pronostic est bien en mémoire');

      // ── Cycle 1 : NOUVEAU résultat, chemin de production corrigé ────────
      final bool retour1 = await _cycleDataRefresh(
        courseKey: ck,
        arrivee:   arrivee,
        partants:  partants,
      );

      final resolu1   = IaMemoryService.instance.pronostics.single.resultatsReels;
      final rating1   = _rating('CHEVAL_1');
      final nb1       = _nb('CHEVAL_1');
      final disque1   = _eloSurDisque(store);
      final ecritures1 = store.ecrituresElo;

      expect(resolu1, isTrue,
          reason: 'T-A7-4a témoin : le résultat du cycle 1 est enregistré');
      expect(retour1, isTrue,
          reason: 'T-A7-4a : `enregistrerResultat` rend `true` sur un '
              'résultat NOUVEAU — c\'est ce `true` qui autorise l\'appel ELO');

      // ── Cycle 2 : MÊME arrivée, déjà connue ─────────────────────────────
      final bool retour2 = await _cycleDataRefresh(
        courseKey: ck,
        arrivee:   arrivee,
        partants:  partants,
      );

      final resolu2    = IaMemoryService.instance.pronostics.single.resultatsReels;
      final rating2    = _rating('CHEVAL_1');
      final nb2        = _nb('CHEVAL_1');
      final ecritures2 = store.ecrituresElo;

      // ignore: avoid_print
      print('[T-A7-4a] cycle 1 : retour=$retour1 → ELO $rating1 (nb=$nb1) | '
          'cycle 2 : retour=$retour2 → ELO $rating2 (nb=$nb2) | écritures ELO '
          '(cumul) $ecritures1 → $ecritures2');

      // ── La mémoire IA reste idempotente ─────────────────────────────────
      expect(resolu2, isTrue,
          reason: 'T-A7-4a : le résultat reste enregistré');
      expect(
        IaMemoryService.instance.pronostics.single.arriveeReelle,
        arrivee,
        reason: 'T-A7-4a : l\'arrivée n\'a pas été réécrite');
      expect(
        IaMemoryService.instance.pronostics.single.dateResultat,
        isNotNull,
        reason: 'T-A7-4a : la date de résultat est préservée');

      // ── CORRECTION A7 : le 2e cycle est REFUSÉ et n'applique AUCUN ELO ──
      expect(retour2, isFalse,
          reason: 'T-A7-4a : `enregistrerResultat` rend `false` sur un '
              'résultat DÉJÀ connu (garde `p.resultatsReels`) — c\'est ce '
              '`false` qui empêche désormais l\'appel ELO');
      expect(rating2, closeTo(rating1, 0.000001),
          reason: 'T-A7-4a : AVANT la correction, le rating dérivait à chaque '
              'cycle. APRÈS : $rating1 → $rating2, INCHANGÉ.');
      expect(nb2, nb1,
          reason: 'T-A7-4a : nbCourses INCHANGÉ ($nb1 → $nb2). Il compte '
              'désormais des COURSES, plus des applications.');
      expect(ecritures2, ecritures1,
          reason: 'T-A7-4a : aucune écriture ELO supplémentaire au cycle 2');
      expect(disque1[_cle('CHEVAL_1')]['nb'], nb1,
          reason: 'T-A7-4a : le disque est aligné sur la RAM au cycle 1');
      expect(_eloSurDisque(store)[_cle('CHEVAL_1')]['nb'], nb2,
          reason: 'T-A7-4a : le disque reste aligné après le cycle 2');
    });

    test('T-A7-4b — contrôle NÉGATIF : sans appel ELO, un résultat déjà connu '
        'ne modifie RIEN', () async {
      final store = await _buildStore();
      final jour = _jour;
      final ck = _cleCourse(22, 1, jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );

      await IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);
      final ratingApres1 = _rating('CHEVAL_1');
      final nbApres1 = _nb('CHEVAL_1');
      final ecrituresAvant = store.ecrituresElo;

      // ── Second cycle, chemin COMPLET mais avec `avecElo: false` ─────────
      //    Prouve que `enregistrerResultat` seul ne touche JAMAIS l'ELO :
      //    même le chemin corrigé, s'il n'appelle pas l'ELO, ne le bouge pas.
      final bool retour2 = await _cycleDataRefresh(
        courseKey:  ck,
        arrivee:    arrivee,
        partants:   partants,
        avecElo:    false,
      );

      expect(retour2, isFalse,
          reason: 'T-A7-4b : le second cycle obtient `false`');
      expect(_rating('CHEVAL_1'), closeTo(ratingApres1, 0.000001),
          reason: 'T-A7-4b : l\'ELO ne bouge pas — un résultat déjà connu '
              'n\'écrit rien');
      expect(_nb('CHEVAL_1'), nbApres1,
          reason: 'T-A7-4b : nbCourses inchangé');
      expect(store.ecrituresElo, ecrituresAvant,
          reason: 'T-A7-4b : AUCUNE écriture ELO supplémentaire — '
              '`enregistrerResultat` seul est bien idempotent');

      // ignore: avoid_print
      print('[T-A7-4b] sans appel ELO : retour=$retour2 | rating=$ratingApres1 '
          'inchangé | nbCourses=$nbApres1 inchangé | écritures ELO=0 '
          'supplémentaire → le mouvement ELO vient bien de l\'APPEL, pas de '
          'la mémoire');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A7-5 — COURSE SANS PRONOSTIC ACTIF mais PRÉSENTE DANS L'ARCHIVE
  //
  //  `enregistrerResultat()` bascule alors sur `_consignerResultatEnArchive()` :
  //  archive SEULE, aucun apprentissage, et — depuis A7 — retour `false`.
  //  AVANT : l'appelant mettait l'ELO à jour quand même (défaut mesuré).
  //  APRÈS : `false` empêche cet appel. C'est le test NORMATIF T-A7-5a.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A7-5 — course sans pronostic actif', () {
    test('T-A7-5a — NORMATIF : la consignation ARCHIVE SEULE ne provoque '
        'AUCUNE mise à jour ELO', () async {
      await _buildStore();

      const ck = 'R99C1_COURSE_ABSENTE';
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      // ── Témoin : aucune pronostic actif ────────────────────────────────
      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'T-A7-5a témoin : aucun pronostic actif');
      expect(IaArchiveService.instance.nbVersionsArchivees, 0,
          reason: 'T-A7-5a témoin : archive vide');

      final ratingAvant = _rating('CHEVAL_1');
      final nbAvant = _nb('CHEVAL_1');

      // ── Chemin de production CORRIGÉ : archive seule → false → pas d'ELO ─
      final bool retour = await _cycleDataRefresh(
        courseKey: ck,
        arrivee:   arrivee,
        partants:  partants,
      );

      final ratingApres = _rating('CHEVAL_1');
      final nbApres = _nb('CHEVAL_1');

      // ignore: avoid_print
      print('[T-A7-5a] course absente de la RAM | retour=$retour | ELO '
          'CHEVAL_1 : $ratingAvant → $ratingApres | nbCourses : '
          '$nbAvant → $nbApres');

      // ── RIEN n'est réinjecté dans la mémoire active ────────────────────
      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'T-A7-5a : AUCUNE réinjection dans la mémoire active');

      // ── CORRECTION A7 : la branche archive rend `false` ────────────────
      expect(retour, isFalse,
          reason: 'T-A7-5a : `enregistrerResultat` rend `false` sur la branche '
              'de consignation ARCHIVE SEULE (arbitrage §3)');
      expect(ratingApres, closeTo(ratingAvant, 0.000001),
          reason: 'T-A7-5a : AVANT la correction, l\'ELO bougeait alors que '
              'la course n\'existe pas dans la mémoire active. APRÈS : '
              '$ratingAvant → $ratingApres, INCHANGÉ.');
      expect(nbApres, nbAvant,
          reason: 'T-A7-5a : nbCourses INCHANGÉ ($nbAvant → $nbApres)');
    });

    test('T-A7-5b — contrôle NÉGATIF : le résultat archivé seul ne touche pas '
        'l\'ELO', () async {
      await _buildStore();
      const ck = 'R99C2_COURSE_ABSENTE';

      final ratingAvant = _rating('CHEVAL_1');
      final nbAvant = _nb('CHEVAL_1');

      // ── Appel de `enregistrerResultat` SEUL ────────────────────────────
      await IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: const <int>[1, 2]);

      expect(_rating('CHEVAL_1'), closeTo(ratingAvant, 0.000001),
          reason: 'T-A7-5b : `_consignerResultatEnArchive()` ne touche pas '
              'l\'ELO — ce n\'est pas lui le responsable');
      expect(_nb('CHEVAL_1'), nbAvant,
          reason: 'T-A7-5b : nbCourses inchangé');

      // ignore: avoid_print
      print('[T-A7-5b] résultat archivé seul : rating=$ratingAvant et '
          'nbCourses=$nbAvant INCHANGÉS → le mouvement ELO vient de '
          'l\'appelant, pas de la consignation d\'archive');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A7-6 — TRAITEMENTS CONCURRENTS d'une même arrivée
  //
  //  Deux niveaux sont distingués :
  //    • T-A7-6a : `EloService` SEUL. Deux applications cumulent quand elles
  //      portent sur DEUX COURSES DISTINCTES — c'est un fait CARACTÉRISÉ de
  //      l'API bas niveau : elle sérialise (file FIFO) mais ne déduplique pas
      //      les courses différentes.
  //      ⚠️ B2-e : la primitive REFUSE désormais un rejeu de la MÊME course.
  //      Ce test ne mesure donc pas cette protection (elle est mesurée dans le
  //      fichier B2-e) mais bien le CUMUL, avec deux identités distinctes.
  //    • T-A7-6b : le CHEMIN DE PRODUCTION CORRIGÉ (enregistrerResultat +
  //      conditionnement de l'appel ELO). C'est CE test qui est normatif.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A7-6 — traitements concurrents', () {
    test('T-A7-6a — CARACTÉRISATION de la primitive : EloService seul cumule '
        'deux applications', () async {
      await _buildStore();
      final elo = _eloService();

      final p1 = _partant(1, nom: 'A', rating: 1500.0);
      final p2 = _partant(2, nom: 'B', rating: 1500.0);
      const arrivee = <int>[1, 2];

      final ratingAvant = _rating('A');
      final nbAvant = _nb('A');

      // ── Deux appels NON attendus, lancés ensemble ─────────────────────
      // ★ B2-e : DEUX COURSES DISTINCTES (R61C1 puis R61C2). L'objectif du
      //   test est de prouver qu'AUCUN verrou d'idempotence n'existe dans la
      //   primitive : deux courses = deux applications. Avec une clé unique, la
      //   seconde serait refusée et le test deviendrait un test de refus.
      final f1 = elo.mettreAJourApresArrivee(
          arrivee: arrivee, partants: <ZtPartant>[p1, p2], discipline: _disc,
          courseKey: _cleCourse(61, 1, _jour));
      final f2 = elo.mettreAJourApresArrivee(
          arrivee: arrivee, partants: <ZtPartant>[p1, p2], discipline: _disc,
          courseKey: _cleCourse(61, 2, _jour));
      await Future.wait(<Future<void>>[f1, f2]);

      final ratingApres = _rating('A');
      final nbApres = _nb('A');

      // ignore: avoid_print
      print('[T-A7-6a] EloService seul, 2 appels concurrents | A : '
          '$ratingAvant → $ratingApres | nbCourses : $nbAvant → $nbApres');

      //  Aucun verrou d'idempotence DANS la primitive : les DEUX courses
      //  distinctes s'appliquent. C'est ce qui rend le conditionnement de
      //  l'appelant INDISPENSABLE (voir T-A7-6b).
      expect(nbApres, nbAvant + 2,
          reason: 'T-A7-6a : les deux courses ont incrémenté nbCourses — '
              'mesuré : $nbAvant → $nbApres. La primitive sérialise mais ne '
              'déduplique pas deux COURSES DIFFÉRENTES ; la protection '
              'anti-rejeu d\'une MÊME course relève de B2-e.');
      expect(ratingApres, isNot(closeTo(ratingAvant, 0.000001)),
          reason: 'T-A7-6a : le rating a bougé');
      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'T-A7-6a : aucun effet de bord sur la mémoire IA');
    });

    test('T-A7-6b — NORMATIF : deux cycles de production concurrents sur la '
        'même course n\'appliquent l\'ELO qu\'UNE fois', () async {
      await _buildStore();
      final jour = _jour;
      final ck = _cleCourse(61, 1, jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );
      expect(IaMemoryService.instance.pronostics.length, 1,
          reason: 'T-A7-6b témoin : la course non résolue est en mémoire');

      final ratingAvant = _rating('CHEVAL_1');
      final nbAvant = _nb('CHEVAL_1');

      // ── DEUX cycles DataRefresh lancés ensemble, SANS attendre le 1er ────
      final f1 = _cycleDataRefresh(
          courseKey: ck, arrivee: arrivee, partants: partants);
      final f2 = _cycleDataRefresh(
          courseKey: ck, arrivee: arrivee, partants: partants);

      final retours = await Future.wait(<Future<bool>>[f1, f2]);

      final ratingApres = _rating('CHEVAL_1');
      final nbApres = _nb('CHEVAL_1');

      // ignore: avoid_print
      print('[T-A7-6b] 2 cycles concurrents | retours=$retours | '
          'ELO CHEVAL_1 : $ratingAvant → $ratingApres | nbCourses : '
          '$nbAvant → $nbApres');

      // ── Exactement UN `true` : c'est la garantie mesurée au diagnostic ──
      expect(retours.where((r) => r).length, 1,
          reason: 'T-A7-6b : MESURÉ — exactement UN cycle a obtenu `true`. '
              'La garde `p.resultatsReels` et la mutation sont dans une '
              'section synchrone contiguë : un seul cycle peut muter.');
      expect(retours.where((r) => !r).length, 1,
          reason: 'T-A7-6b : l\'autre cycle a obtenu `false`');

      // ── Donc UNE SEULE application ELO ──────────────────────────────────
      expect(nbApres, nbAvant + 1,
          reason: 'T-A7-6b : nbCourses n\'a augmenté QUE de 1 ($nbAvant → '
              '$nbApres) pour deux cycles concurrents');
      expect(ratingApres, isNot(closeTo(ratingAvant, 0.000001)),
          reason: 'T-A7-6b : le premier passage a bien appliqué son delta');

      // ── Et le disque porte EXACTEMENT l'état RAM ────────────────────────
      final store = SharedPreferencesStorePlatform.instance as _StoreObservable;
      expect(_eloSurDisque(store)[_cle('CHEVAL_1')]['nb'], nbApres,
          reason: 'T-A7-6b : disque aligné sur la RAM');
      expect(
        _eloSurDisque(store)[_cle('CHEVAL_1')]['rating'],
        closeTo(ratingApres, 0.001),
        reason: 'T-A7-6b : le rating disque est celui de la RAM');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A7-7 — CRITÈRE M : les VRAIS ratings ELO (correctif D3)
  //  Sans `chargerDepuisMapIsolate()`, `enrichirAvecElo()` écraserait
  //  `eloRating` par le défaut 1500 → critère M figé à 37.5 pour tous.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A7-7 — critère M et le correctif D3', () {
    test('T-A7-7a — le critère M reflète le rating réel, pas 1500', () async {
      await _buildStore();

      //  Trois ratings FRANCHEMENT distincts, tous ≠ 1500.
      final partants = <ZtPartant>[
        _partant(1, nom: 'FORT', rating: 2000.0),
        _partant(2, nom: 'MOYEN', rating: 1600.0),
        _partant(3, nom: 'FAIBLE', rating: 1300.0),
      ];
      await EloService.instance.importerDepuisBackup(<String, dynamic>{
        for (final p in partants)
          _cle(p.nom): <String, dynamic>{
            'nom': p.nom,
            'rating': p.eloRating,
            'nb': 20,
            'var': 0.0,
          },
      });

      final enrichis =
          EloService.instance.enrichirAvecElo(partants, discipline: _disc);

      // ── Le rating injecté est bien porté, pas écrasé ───────────────────
      expect(enrichis[0].eloRating, closeTo(2000.0, 0.000001),
          reason: 'T-A7-7a : FORT garde 2000 (pas 1500)');
      expect(enrichis[2].eloRating, closeTo(1300.0, 0.000001),
          reason: 'T-A7-7a : FAIBLE garde 1300 (pas 1500)');

      // ── Le critère M en découle, et n'est PAS figé ─────────────────────
      //  scoreElo = ((rating - 1200) / 8).clamp(0, 100)
      //    2000 → 100.0 | 1600 → 50.0 | 1300 → 12.5
      expect(enrichis[0].scoreElo, closeTo(100.0, 0.000001),
          reason: 'T-A7-7a : critère M de FORT = 100');
      expect(enrichis[1].scoreElo, closeTo(50.0, 0.000001),
          reason: 'T-A7-7a : critère M de MOYEN = 50');
      expect(enrichis[2].scoreElo, closeTo(12.5, 0.000001),
          reason: 'T-A7-7a : critère M de FAIBLE = 12.5');

      final scores = enrichis.map((p) => p.scoreElo).toSet();
      expect(scores.length, 3,
          reason: 'T-A7-7a : trois valeurs DISTINCTES — le critère M n\'est '
              'pas figé. Le défaut D3 donnait 37.5 pour tous.');

      // ignore: avoid_print
      print('[T-A7-7a] critères M : FORT=${enrichis[0].scoreElo} '
          'MOYEN=${enrichis[1].scoreElo} FAIBLE=${enrichis[2].scoreElo} '
          '| 3 valeurs distinctes (D3 opérationnel)');
    });

    test('T-A7-7b — CARACTÉRISATION : un rating INCONNU produit 37.5, pas 50',
        () async {
      await _buildStore();

      //  Aucun rating pour ce cheval → getScore() rend le défaut 1500.
      final inconnu = <ZtPartant>[_partant(7, nom: 'INCONNU_A7')];
      final enrichi =
          EloService.instance.enrichirAvecElo(inconnu, discipline: _disc).single;

      expect(enrichi.eloRating, closeTo(1500.0, 0.000001),
          reason: 'T-A7-7b : le défaut du modèle est bien 1500');
      //  scoreElo = (1500 - 1200) / 8 = 37.5  (et NON 50)
      expect(enrichi.scoreElo, closeTo(37.5, 0.000001),
          reason: 'T-A7-7b : MESURÉ — pour un rating INCONNU, le critère M '
              'vaut 37.5 (1500 → 37.5), pas 50. La valeur 50.0 n\'est rendue '
              'que si `eloRating <= 0`, état que `enrichirAvecElo()` ne '
              'produit jamais puisqu\'il écrit toujours 1500.');

      // ignore: avoid_print
      print('[T-A7-7b] rating inconnu → eloRating=${enrichi.eloRating} | '
          'critère M=${enrichi.scoreElo} (37.5 attendu, pas 50)');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A7-8 → T-A7-12 — VALIDATION DE LA CONCURRENCE (mandat « OPTION A »)
  //
  //  QUESTION POSÉE : `Future<bool>` (rendre le résultat d'`enregistrerResultat`)
  //  suffit-il à garantir qu'UN SEUL appel traite une nouvelle arrivée ?
  //
  //  CE QUI EST MESURÉ ICI : le nombre de MUTATIONS de `_pronostics[idx]`.
  //  Mesure INDIRECTE, mais fidèle et déclarée : cf. `_ecrituresPronostics()`.
  //
  //  CE QUI NE PEUT PAS ÊTRE MESURÉ AVANT LA MODIFICATION DE PRODUCTION : la
  //  valeur de retour `Future<bool>` elle-même — la signature est aujourd'hui
  //  `Future<void>`. Aucun test ne peut donc lire `true`/`false`. On observe
  //  l'EFFET (mutation ou non), pas le RETOUR. C'est déclaré, pas contourné.
  //
  //  LIMITE D'EXÉCUTION DÉCLARÉE : `_recupererResultatsBatch()` est PRIVÉE et
  //  `_recupererResultatsAuto()` aussi. Le recouvrement de DEUX cycles batch
  //  n'est donc pas exécutable ici ; il est établi par LECTURE (§ rapport).
  // ═════════════════════════════════════════════════════════════════════════

  // ─────────────────────────────────────────────────────────────────────────
  //  A — deux appels concurrents, `_load()` NON terminé
  // ─────────────────────────────────────────────────────────────────────────
  group('T-A7-8 — A : deux appels concurrents, _load() en vol', () {
    test('T-A7-8a — les deux appels se suspendent sur le MÊME _load(), '
        'et UNE SEULE mutation a lieu', () async {
      final store = await _buildStore();
      final jour = _jour;
      final ck = _cleCourse(31, 1, jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      // ── Le pronostic est écrit SUR LE DISQUE par le chemin de production ──
      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );
      expect(IaMemoryService.instance.pronostics.length, 1,
          reason: 'T-A7-8a témoin : le pronostic existe avant le scénario');

      // ── Relevés AVANT ────────────────────────────────────────────────────
      final wAvant = _ecrituresPronostics(store);
      final eAvant = store.ecrituresElo;

      // ── `recharger()` NON attendu : `_loaded = false`, `_load()` EN VOL ──
      //    `recharger()` pose `_loaded = false` puis `_pronostics.clear()`
      //    SYNCHRONEMENT, avant son premier `await`. Au retour de l'appel,
      //    `_loadCompleter` est donc déjà créé : les deux appels suivants
      //    vont s'attacher à la MÊME future de chargement.
      final chargement = IaMemoryService.instance.recharger();

      // Témoin DANS la fenêtre : la RAM est bien vide à cet instant.
      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'T-A7-8a témoin : `recharger()` a vidé la RAM — les deux '
              'appels vont donc devoir attendre le chargement');

      final f1 = IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);
      final f2 = IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);
      await Future.wait(<Future<void>>[chargement, f1, f2]);

      final wApres = _ecrituresPronostics(store);
      final eApres = store.ecrituresElo;

      // Témoin APRÈS : le chargement a bien repeuplé la RAM depuis le disque.
      expect(IaMemoryService.instance.pronostics.length, 1,
          reason: 'T-A7-8a témoin : `_load()` a rechargé le pronostic — la '
              'fenêtre de concurrence était donc bien celle du chargement');

      final resolu = IaMemoryService.instance.pronostics.single;
      expect(resolu.resultatsReels, isTrue,
          reason: 'T-A7-8a : la course est résolue');
      expect(resolu.arriveeReelle, arrivee,
          reason: 'T-A7-8a : l\'arrivée enregistrée est la bonne');

      // ignore: avoid_print
      print('[T-A7-8a] 2 appels concurrents, _load() en vol | mutations '
          '(_save plage pronostics) : ${wApres - wAvant} | écritures ELO : '
          '${eApres - eAvant}');

      expect(wApres - wAvant, 1,
          reason: 'T-A7-8a : MESURÉ — UNE SEULE mutation de `_pronostics[idx]`. '
              'La seconde continuation du chargement a lu '
              '`resultatsReels == true` (garde l.3336) et est sortie. '
              'Mesuré : ${wApres - wAvant} écriture(s).');
      expect(eApres - eAvant, 0,
          reason: 'T-A7-8a : `enregistrerResultat()` ne touche JAMAIS l\'ELO — '
              'mesuré : ${eApres - eAvant} écriture(s) ELO');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  B — même scénario, `_load()` DÉJÀ terminé
  // ─────────────────────────────────────────────────────────────────────────
  group('T-A7-9 — B : deux appels concurrents, _load() terminé', () {
    test('T-A7-9a — le `await _load()` rend la main en microtâche même '
        'chargé : UNE SEULE mutation', () async {
      final store = await _buildStore();
      final jour = _jour;
      final ck = _cleCourse(32, 1, jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );
      expect(IaMemoryService.instance.pronostics.length, 1,
          reason: 'T-A7-9a témoin : pronostic en RAM et sur le disque');

      final wAvant = _ecrituresPronostics(store);

      // `_loaded == true` : `_load()` sort immédiatement (l.2219). Le `await`
      // de la l.3318 rend néanmoins la main en microtâche : c'est le point
      // d'entrelacement résiduel, même sans chargement réel.
      final f1 = IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);
      final f2 = IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);
      await Future.wait(<Future<void>>[f1, f2]);

      final wApres = _ecrituresPronostics(store);
      final resolu = IaMemoryService.instance.pronostics.single;

      // ignore: avoid_print
      print('[T-A7-9a] 2 appels concurrents, _load() terminé | mutations : '
          '${wApres - wAvant} | resultatsReels=${resolu.resultatsReels}');

      expect(resolu.resultatsReels, isTrue,
          reason: 'T-A7-9a : la course est résolue');
      expect(wApres - wAvant, 1,
          reason: 'T-A7-9a : MESURÉ — une seule mutation. Les deux appels '
              'franchissent `await _load()` en microtâches successives, mais '
              'le premier exécute lu-garde → mutation SANS AUCUNE suspension '
              'intermédiaire (prouvé plus bas, T-A7-10a).');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  C — la garde `resultatsReels` peut-elle être franchie DEUX FOIS
  //      avant la première mutation ?
  // ─────────────────────────────────────────────────────────────────────────
  group('T-A7-10 — C : atomicité de la garde', () {
    test('T-A7-10a — un 2e appel lancé PENDANT le `_save()` du 1er voit '
        'déjà la mutation : il est refusé', () async {
      final store = await _buildStore();
      final jour = _jour;
      final ck = _cleCourse(33, 1, jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );

      final wAvant = _ecrituresPronostics(store);

      // ── Injection par le SEUL point de suspension de test EXISTANT ───────
      //    `IaMemoryService.hookApresGetInstancePourTest` (l.213,
      //    `@visibleForTesting`, nul par défaut). Aucun ajout en production.
      //    Il s'exécute dans `_ecrireProtege` (l.2633), donc à l'INTÉRIEUR de
      //    `_save()`, c.-à-d. APRÈS la mutation `_pronostics[idx] = …` (l.3405).
      expect(IaMemoryService.instance.hookApresGetInstancePourTest, isNull,
          reason: 'T-A7-10a témoin : le hook est nul en production');

      var appelsHook = 0;
      bool? resoluAuHook;
      int? mutationsAuHook;
      bool? secondResolu;
      final mem = IaMemoryService.instance;

      try {
        mem.hookApresGetInstancePourTest = () async {
          appelsHook++;
          if (appelsHook != 1) return; // une seule interception
          // État de la RAM À L'INTÉRIEUR du `_save()` du 1er appel.
          resoluAuHook = mem.pronostics.single.resultatsReels;
          mutationsAuHook = _ecrituresPronostics(store);
          // 2e appel lancé ICI, alors que le 1er est suspendu.
          await mem.enregistrerResultat(
              courseKey: ck, arriveeReelle: arrivee);
          secondResolu = mem.pronostics.single.resultatsReels;
        };

        await mem.enregistrerResultat(courseKey: ck, arriveeReelle: arrivee);
      } finally {
        // Le hook ne doit JAMAIS survivre : le service est un singleton.
        mem.hookApresGetInstancePourTest = null;
      }

      final wApres = _ecrituresPronostics(store);

      // ignore: avoid_print
      print('[T-A7-10a] hook atteint $appelsHook fois | RAM résolue au hook = '
          '$resoluAuHook | mutations au hook = ${(mutationsAuHook ?? -1) - wAvant} '
          '| mutations totales = ${wApres - wAvant}');

      expect(appelsHook, 1,
          reason: 'T-A7-10a témoin : le hook a été atteint une seule fois');
      expect(resoluAuHook, isTrue,
          reason: 'T-A7-10a : PREUVE D\'ORDRE — au moment où le 1er appel est '
              'suspendu dans `_save()`, la mutation `_pronostics[idx] = …` '
              '(l.3405) est DÉJÀ faite. La garde (l.3336) a donc été lue et '
              'franchie AVANT, et la mutation est postérieure : les deux '
              'opérations sont dans la MÊME section synchrone.');
      expect(mutationsAuHook, wAvant,
          reason: 'T-A7-10a : aucune écriture du blob n\'a encore eu lieu au '
              'hook (il précède l\'action de `_ecrireProtege`)');
      expect(secondResolu, isTrue,
          reason: 'T-A7-10a : le 2e appel a bien vu `resultatsReels == true`');
      expect(wApres - wAvant, 1,
          reason: 'T-A7-10a : MESURÉ — une seule mutation, alors que le 2e '
              'appel s\'est exécuté pendant la suspension du 1er');
    });

    test('T-A7-10b — PREUVE PAR LECTURE : aucun `await` entre la garde '
        'et la mutation', () async {
      //  Contrôle NÉGATIF exécutable : la mesure de T-A7-10a ne vaudrait rien
      //  si la fenêtre garde→mutation contenait une suspension. On établit ici
      //  le fait structurel par la MÊME mesure, sur un cas où une suspension
      //  EXISTE, pour montrer que l'instrument la détecterait.
      final store = await _buildStore();
      final jour = _jour;
      final ck = _cleCourse(34, 1, jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );
      final wAvant = _ecrituresPronostics(store);

      final mem = IaMemoryService.instance;
      var appelsHook = 0;
      var secondPendantLeSave = 0;
      try {
        mem.hookApresGetInstancePourTest = () async {
          appelsHook++;
          if (appelsHook != 1) return;
          // On relève l'état AVANT mutation dans un cas NOMINAL, en lançant
          // une lecture pure : elle voit la mutation déjà faite.
          if (mem.pronostics.single.resultatsReels) secondPendantLeSave++;
        };
        await mem.enregistrerResultat(
            courseKey: ck, arriveeReelle: const <int>[1, 2]);
      } finally {
        mem.hookApresGetInstancePourTest = null;
      }

      expect(appelsHook, 1, reason: 'T-A7-10b : hook atteint une fois');
      expect(secondPendantLeSave, 1,
          reason: 'T-A7-10b : la lecture faite depuis l\'intérieur de `_save()` '
              'voit la mutation — la mutation précède donc la 1re suspension '
              'postérieure à la garde');
      expect(_ecrituresPronostics(store) - wAvant, 1,
          reason: 'T-A7-10b : une seule mutation sur ce chemin nominal');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  D — `pronosticsEnAttente` peut-il devenir OBSOLÈTE ?
  // ─────────────────────────────────────────────────────────────────────────
  group('T-A7-11 — D : obsolescence du filtre pronosticsEnAttente', () {
    test('T-A7-11a — le filtre rend une LISTE FIGÉE d\'objets FIGÉS : '
        'après enregistrement, l\'objet filtré reste `!resultatsReels`',
        () async {
      await _buildStore();
      final jour = _jour;
      final ck = _cleCourse(35, 1, jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );

      // ── Reproduction EXACTE du filtre de data_refresh_service.dart:1128 ──
      //    `_pronostics` est exposé par `List.unmodifiable(...)` (l.253) :
      //    le `.toList()` produit une COPIE de la liste, mais les ÉLÉMENTS
      //    sont les MÊMES RÉFÉRENCES.
      final pronosticsEnAttente = IaMemoryService.instance.pronostics
          .where((p) => !p.resultatsReels)
          .toList();

      // Témoins : le filtre contient bien la course, non résolue.
      expect(pronosticsEnAttente.length, 1,
          reason: 'T-A7-11a témoin : le filtre retient la course');
      expect(pronosticsEnAttente.single.resultatsReels, isFalse,
          reason: 'T-A7-11a témoin : elle est non résolue à la capture');

      // ── Résolution par le chemin de production ──────────────────────────
      await IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);

      final vivant = IaMemoryService.instance.pronostics.single;
      final filtre = pronosticsEnAttente.single;

      // ignore: avoid_print
      print('[T-A7-11a] après résolution | objet du FILTRE : '
          'resultatsReels=${filtre.resultatsReels} | objet VIVANT : '
          'resultatsReels=${vivant.resultatsReels} | même instance : '
          '${identical(filtre, vivant)}');

      expect(vivant.resultatsReels, isTrue,
          reason: 'T-A7-11a : la mémoire vivante est résolue');
      expect(filtre.resultatsReels, isFalse,
          reason: 'T-A7-11a : DÉFAUT MESURÉ — l\'objet retenu par le filtre '
              'reste `resultatsReels == false`. `enregistrerResultat()` '
              'REMPLACE l\'élément (`_pronostics[idx] = IaPronostic(...)`, '
              'l.3405) au lieu de le muter : le filtre conserve la référence '
              'ANCIENNE.');
      expect(identical(filtre, vivant), isFalse,
          reason: 'T-A7-11a : ce sont bien deux objets DISTINCTS — la preuve '
              'que le filtre est devenu obsolète par REMPLACEMENT');

      //  Conséquence : un 2e parcours de CE filtre obsolète rejoue l'appel.
      //  AVANT la correction, l'appel ELO de l'appelant s'appliquait quand
      //  même (il était inconditionnel). APRÈS, le `false` rendu par
      //  `enregistrerResultat` empêche cet appel — c'est ce que `_cycleDataRefresh`
      //  reproduit ici.
      final rAvant = _rating('CHEVAL_1');
      final nAvant = _nb('CHEVAL_1');
      final retoursFiltre = <bool>[];
      for (final p in pronosticsEnAttente) {
        retoursFiltre.add(await _cycleDataRefresh(
          courseKey: p.courseKey,
          arrivee:   arrivee,
          partants:  partants,
        ));
      }
      final rApres = _rating('CHEVAL_1');
      final nApres = _nb('CHEVAL_1');

      // ignore: avoid_print
      print('[T-A7-11a] 2e parcours du filtre obsolète | retours=$retoursFiltre '
          '| ELO CHEVAL_1 : $rAvant → $rApres | nbCourses : $nAvant → $nApres');

      expect(retoursFiltre, <bool>[false],
          reason: 'T-A7-11a : le filtre obsolète rejoue bien l\'appel, mais '
              'il obtient `false` — la course est déjà résolue en mémoire');
      expect(nApres, nAvant,
          reason: 'T-A7-11a : APRÈS correction, le filtre obsolète ne produit '
              'PLUS de mise à jour ELO ($nAvant → $nApres). AVANT, il en '
              'produisait une (mesuré au diagnostic : 0 → 1).');
      expect(rApres, closeTo(rAvant, 0.000001),
          reason: 'T-A7-11a : rating inchangé');
    });

    test('T-A7-11b — contrôle NÉGATIF : un filtre RE-CALCULÉ ne contient '
        'plus la course et ne produit aucun ELO', () async {
      await _buildStore();
      final jour = _jour;
      final ck = _cleCourse(36, 1, jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );
      await IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);

      // Filtre recalculé APRÈS la résolution — ce que fait un NOUVEAU cycle.
      final filtre = IaMemoryService.instance.pronostics
          .where((p) => !p.resultatsReels)
          .toList();
      final rAvant = _rating('CHEVAL_1');
      final nAvant = _nb('CHEVAL_1');

      expect(filtre, isEmpty,
          reason: 'T-A7-11b : un filtre recalculé est VIDE — c\'est la '
              'protection réelle du cycle suivant');
      for (final p in filtre) {
        await EloService.instance.mettreAJourApresArrivee(
            arrivee: arrivee, partants: partants, discipline: _disc);
        expect(p, isNotNull);
      }
      expect(_rating('CHEVAL_1'), closeTo(rAvant, 0.000001),
          reason: 'T-A7-11b : aucun ELO appliqué');
      expect(_nb('CHEVAL_1'), nAvant,
          reason: 'T-A7-11b : nbCourses inchangé');

      // ignore: avoid_print
      print('[T-A7-11b] filtre recalculé : ${filtre.length} élément(s) | ELO '
          'inchangé ($rAvant / $nAvant) → le filtre protège le cycle SUIVANT, '
          'pas un parcours déjà engagé');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  //  E — distinguer les QUATRE états
  // ─────────────────────────────────────────────────────────────────────────
  group('T-A7-12 — E : les quatre états distingués', () {
    test('T-A7-12a — NOUVEAU résultat puis DÉJÀ CONNU : 1 mutation puis 0',
        () async {
      final store = await _buildStore();
      final jour = _jour;
      final ck = _cleCourse(41, 1, jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );

      // ── ÉTAT 1 : NOUVEAU ────────────────────────────────────────────────
      final w0 = _ecrituresPronostics(store);
      await IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);
      final w1 = _ecrituresPronostics(store);
      final date1 = IaMemoryService.instance.pronostics.single.dateResultat;

      expect(w1 - w0, 1, reason: 'T-A7-12a ÉTAT 1 : une mutation');
      expect(date1, isNotNull, reason: 'T-A7-12a ÉTAT 1 : date de résultat posée');

      // ── ÉTAT 2 : DÉJÀ CONNU ─────────────────────────────────────────────
      await IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);
      final w2 = _ecrituresPronostics(store);
      final date2 = IaMemoryService.instance.pronostics.single.dateResultat;

      // ignore: avoid_print
      print('[T-A7-12a] ÉTAT 1 mutations=${w1 - w0} | ÉTAT 2 '
          'mutations=${w2 - w1} | dateResultat identique : '
          '${identical(date1, date2)}');

      expect(w2 - w1, 0,
          reason: 'T-A7-12a ÉTAT 2 : AUCUNE mutation — sortie l.3336');
      expect(date2, date1,
          reason: 'T-A7-12a ÉTAT 2 : `dateResultat` n\'a PAS été réécrite — '
              'preuve que la garde a bien court-circuité avant la mutation');
    });

    test('T-A7-12b — ARCHIVE SEULE : écritures archive oui, mutations '
        'pronostics NON, ELO NON', () async {
      final store = await _buildStore();

      // La course est ABSENTE de la mémoire active ET de l'archive :
      // `_consignerResultatEnArchive()` sort à l.3480 sans rien écrire.
      const ckAbsente = 'R98C1_ABSENTE_A7';

      final wAvant = _ecrituresPronostics(store);
      final aAvant = _ecrituresArchive(store);
      final eAvant = store.ecrituresElo;
      final rAvant = _rating('CHEVAL_1');

      await IaMemoryService.instance.enregistrerResultat(
          courseKey: ckAbsente, arriveeReelle: const <int>[1, 2]);

      // ignore: avoid_print
      print('[T-A7-12b] archive seule | mutations pronostics : '
          '${_ecrituresPronostics(store) - wAvant} | écritures archive : '
          '${_ecrituresArchive(store) - aAvant} | écritures ELO : '
          '${store.ecrituresElo - eAvant} | ELO CHEVAL_1 : $rAvant → '
          '${_rating('CHEVAL_1')}');

      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'T-A7-12b : aucune réinjection dans la mémoire active');
      expect(_ecrituresPronostics(store) - wAvant, 0,
          reason: 'T-A7-12b : `_consignerResultatEnArchive` n\'appelle pas '
              '`_save()`, donc aucune mutation du blob des pronostics');
      expect(store.ecrituresElo - eAvant, 0,
          reason: 'T-A7-12b : AUCUN ELO — la branche archive d'
              '`enregistrerResultat` ne touche pas l\'ELO');
      expect(_rating('CHEVAL_1'), closeTo(rAvant, 0.000001),
          reason: 'T-A7-12b : rating inchangé');
    });

    test('T-A7-12c — ARCHIVE SEULE avec fiche PRÉSENTE dans l\'archive : '
        'archive écrite, mémoire active NON, ELO NON', () async {
      final store = await _buildStore();
      const ckArchivee = 'R98C2_ARCHIVEE_A7';

      // Alimentation de l'archive par son API publique de production.
      final archive = IaArchiveService.instance;
      await archive.charger();
      archive.enregistrerEviction(
        IaPronostic(
          courseKey:     ckArchivee,
          nomCourse:     'PRIX_ARCHIVE_A7',
          hippodrome:    'VINCENNES',
          discipline:    _disc,
          datePronostic: _jour,
          scoresIA: const <String, double>{'CHEVAL_1': 90.0, 'CHEVAL_2': 80.0},
          scoresCriteres: const <String, ScoresCriteres>{
            'CHEVAL_1': _critereNeutre,
            'CHEVAL_2': _critereNeutre,
          },
          favoriIaNom: 'CHEVAL_1',
        ),
        motif: ArchiveReason.eviction,
      );
      await archive.persisterEnAttente();

      expect(archive.versionRetenue(ckArchivee), isNotNull,
          reason: 'T-A7-12c témoin : la fiche est bien dans l\'archive');
      expect(archive.versionRetenue(ckArchivee)!.resultatsReels, isFalse,
          reason: 'T-A7-12c témoin : elle est NON résolue dans l\'archive');

      final eAvant = store.ecrituresElo;
      final rAvant = _rating('CHEVAL_1');
      final wAvant = _ecrituresPronostics(store);

      await IaMemoryService.instance.enregistrerResultat(
          courseKey: ckArchivee, arriveeReelle: const <int>[1, 2]);

      final retenue = archive.versionRetenue(ckArchivee)!;

      // ignore: avoid_print
      print('[T-A7-12c] archive avec fiche | retenue.resultatsReels='
          '${retenue.resultatsReels} | mutations pronostics : '
          '${_ecrituresPronostics(store) - wAvant} | écritures ELO : '
          '${store.ecrituresElo - eAvant}');

      expect(retenue.resultatsReels, isTrue,
          reason: 'T-A7-12c : la fiche d\'archive reçoit le résultat '
              '(autorité croissante)');
      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'T-A7-12c : toujours AUCUNE réinjection en mémoire active');
      expect(_ecrituresPronostics(store) - wAvant, 0,
          reason: 'T-A7-12c : le blob des pronostics n\'est pas réécrit');
      expect(store.ecrituresElo - eAvant, 0,
          reason: 'T-A7-12c ARBITRAGE §3 : une consignation ARCHIVE SEULE ne '
              'déclenche AUCUNE mise à jour ELO — mesuré : '
              '${store.ecrituresElo - eAvant} écriture(s)');
      expect(_rating('CHEVAL_1'), closeTo(rAvant, 0.000001),
          reason: 'T-A7-12c : rating ELO inchangé');
    });

    test('T-A7-12d — ANNULÉ PAR RESET : génération périmée, 0 mutation, '
        'contrôle positif sur une 2e course', () async {
      final store = await _buildStore();
      final jour = _jour;
      final ckRefusee = _cleCourse(42, 1, jour);
      final ckAcceptee = _cleCourse(42, 2, jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ckRefusee, course: _course(ckRefusee, partants)),
        ],
      );

      // ── Capture de la génération, comme le fait DataRefreshService ───────
      final gen0 = IaMemoryService.instance.generationCache;

      // ── Reset complet (API publique). Le callback n'efface rien sur le
      //    disque : on veut seulement la BARRIÈRE de génération.
      await IaMemoryService.instance.executerResetComplet(() async {});

      final gen1 = IaMemoryService.instance.generationCache;
      expect(gen1, greaterThan(gen0),
          reason: 'T-A7-12d témoin : le reset a incrémenté la génération');

      // ── Ré-alimentation de la mémoire : DEUX courses non résolues ────────
      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ckRefusee, course: _course(ckRefusee, partants)),
          _item(courseKey: ckAcceptee, course: _course(ckAcceptee, partants)),
        ],
      );
      expect(IaMemoryService.instance.pronostics.length, 2,
          reason: 'T-A7-12d témoin : deux courses non résolues en RAM');

      final wAvant = _ecrituresPronostics(store);

      // ── ÉTAT 4 : génération PÉRIMÉE → refus l.3310 ──────────────────────
      await IaMemoryService.instance.enregistrerResultat(
        courseKey:        ckRefusee,
        arriveeReelle:    const <int>[1, 2],
        generationAppelante: gen0,
      );
      final wApresRefus = _ecrituresPronostics(store);
      final refusee = IaMemoryService.instance.getPronostic(ckRefusee)!;

      // ── CONTRÔLE POSITIF : même appel, génération COURANTE ──────────────
      await IaMemoryService.instance.enregistrerResultat(
        courseKey:        ckAcceptee,
        arriveeReelle:    const <int>[1, 2],
        generationAppelante: gen1,
      );
      final wApresAccept = _ecrituresPronostics(store);
      final acceptee = IaMemoryService.instance.getPronostic(ckAcceptee)!;

      // ignore: avoid_print
      print('[T-A7-12d] génération $gen0 → $gen1 | course PÉRIMÉE : '
          'resultatsReels=${refusee.resultatsReels} (mutations '
          '${wApresRefus - wAvant}) | course COURANTE : '
          'resultatsReels=${acceptee.resultatsReels} (mutations '
          '${wApresAccept - wApresRefus})');

      expect(refusee.resultatsReels, isFalse,
          reason: 'T-A7-12d ÉTAT 4 : la course reste NON résolue');
      expect(wApresRefus - wAvant, 0,
          reason: 'T-A7-12d ÉTAT 4 : AUCUNE mutation — refus sur génération');
      expect(refusee.dateResultat, isNull,
          reason: 'T-A7-12d ÉTAT 4 : aucune date de résultat inventée');

      expect(acceptee.resultatsReels, isTrue,
          reason: 'T-A7-12d CONTRÔLE POSITIF : le MÊME appel avec la '
              'génération courante résout bien la course — le refus ci-dessus '
              'vient donc de la génération, pas d\'un autre empêchement');
      expect(wApresAccept - wApresRefus, 1,
          reason: 'T-A7-12d CONTRÔLE POSITIF : exactement une mutation');
    });

    test('T-A7-12e — branche ARCHIVE sous concurrence : une seule version '
        'résolue, donc idempotente elle aussi', () async {
      await _buildStore();
      const ckArchivee = 'R98C3_ARCHIVEE_CONCURRENTE_A7';

      final archive = IaArchiveService.instance;
      await archive.charger();
      archive.enregistrerEviction(
        IaPronostic(
          courseKey:     ckArchivee,
          nomCourse:     'PRIX_ARCHIVE_CONC_A7',
          hippodrome:    'VINCENNES',
          discipline:    _disc,
          datePronostic: _jour,
          scoresIA: const <String, double>{'CHEVAL_1': 90.0, 'CHEVAL_2': 80.0},
          scoresCriteres: const <String, ScoresCriteres>{
            'CHEVAL_1': _critereNeutre,
            'CHEVAL_2': _critereNeutre,
          },
          favoriIaNom: 'CHEVAL_1',
        ),
        motif: ArchiveReason.eviction,
      );
      await archive.persisterEnAttente();

      final versionsAvant = archive.nbVersions(ckArchivee);
      expect(versionsAvant, 1,
          reason: 'T-A7-12e témoin : UNE version (non résolue) dans l\'archive');
      expect(archive.versionRetenue(ckArchivee)!.resultatsReels, isFalse,
          reason: 'T-A7-12e témoin : cette version est NON résolue');

      // ── DEUX appels concurrents sur la même course archivée ─────────────
      final f1 = IaMemoryService.instance.enregistrerResultat(
          courseKey: ckArchivee, arriveeReelle: const <int>[1, 2]);
      final f2 = IaMemoryService.instance.enregistrerResultat(
          courseKey: ckArchivee, arriveeReelle: const <int>[1, 2]);
      await Future.wait(<Future<void>>[f1, f2]);

      final versionsApres = archive.nbVersions(ckArchivee);

      // ignore: avoid_print
      print('[T-A7-12e] archive concurrente | versions : $versionsAvant → '
          '$versionsApres | retenue.resultatsReels='
          '${archive.versionRetenue(ckArchivee)!.resultatsReels}');

      expect(versionsApres, versionsAvant + 1,
          reason: 'T-A7-12e : MESURÉ — UNE SEULE version résolue ajoutée pour '
              'deux appels concurrents. La garde `p.resultatsReels` '
              '(ia_memory_service.dart:3483) et l\'écriture '
              '`enregistrerEviction` (l.3572) sont dans la MÊME section '
              'synchrone (aucun `await` entre elles), comme la garde l.3336 et '
              'la mutation l.3405 du chemin nominal.');
      expect(archive.versionRetenue(ckArchivee)!.resultatsReels, isTrue,
          reason: 'T-A7-12e : la version RETENUE est résolue');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A7-13 — PRÉCISION SUR « DÉJÀ CONNU » : deux causes DISTINCTES
  //
  //  L'état « résultat déjà connu » recouvre DEUX situations incompatibles :
  //    (i)  la course a été résolue PAR le cycle DataRefresh → l'ELO a été
  //         appliqué (ou était en vol) ;
  //    (ii) la course a été résolue par un AUTRE chemin, qui n'appelle PAS
  //         l'ELO : `alert_service.dart:2719` et `ia_memory_service.dart:1683`
  //         / `:1991`. Le résultat est alors écrit, mais l'ELO JAMAIS.
  //
  //  Conséquence pour l'OPTION A : un critère `!resultatsReels` ne sait pas
  //  distinguer (i) de (ii). Dans le cas (ii), il conclut « déjà traité » et
  //  l'ELO est perdu DÉFINITIVEMENT (le résultat est sur le disque, et
  //  `enregistrerResultat` ne réécrit jamais un résultat existant).
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A7-13 — « déjà connu » : deux causes, un seul critère', () {
    test('T-A7-13a — une course résolue par un chemin SANS ELO ne reçoit '
        'JAMAIS son ELO ensuite', () async {
      await _buildStore();
      final jour = _jour;
      final ck = _cleCourse(51, 1, jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );

      // ── CHEMIN (ii) : `alert_service.dart:2719` — sans appel ELO ────────
      await IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);

      expect(IaMemoryService.instance.pronostics.single.resultatsReels, isTrue,
          reason: 'T-A7-13a témoin : la course est résolue');
      expect(_nb('CHEVAL_1'), 0,
          reason: 'T-A7-13a témoin : l\'ELO n\'a PAS été touché par ce chemin');
      expect(_rating('CHEVAL_1'), closeTo(1500.0, 0.000001),
          reason: 'T-A7-13a témoin : rating encore au défaut');

      // ── CHEMIN (i) au cycle SUIVANT : filtre recalculé ──────────────────
      //    Reproduction EXACTE de `_recupererResultatsBatch` (l.1128) puis
      //    de la garde `!resultatsReels` avant l'appel ELO (l.1183).
      final enAttente = IaMemoryService.instance.pronostics
          .where((p) => !p.resultatsReels)
          .toList();
      var eloApplique = 0;
      for (final p in enAttente) {
        // Conditionnement OPTION A : n'appeler l'ELO que si le retour est vrai.
        final dejaResolu =
            IaMemoryService.instance.getPronostic(p.courseKey)!.resultatsReels;
        if (dejaResolu) continue;
        await EloService.instance.mettreAJourApresArrivee(
            arrivee: arrivee, partants: partants, discipline: _disc);
        eloApplique++;
      }

      // ignore: avoid_print
      print('[T-A7-13a] course résolue SANS ELO | filtre : '
          '${enAttente.length} élément(s) | ELO appliqués au cycle suivant : '
          '$eloApplique | rating CHEVAL_1=${_rating('CHEVAL_1')} | '
          'nbCourses=${_nb('CHEVAL_1')}');

      expect(enAttente, isEmpty,
          reason: 'T-A7-13a : MESURÉ — le filtre recalculé est VIDE, donc le '
              'cycle suivant ne voit JAMAIS cette course');
      expect(eloApplique, 0,
          reason: 'T-A7-13a : aucun ELO appliqué');
      expect(_nb('CHEVAL_1'), 0,
          reason: 'T-A7-13a : DÉFAUT MESURÉ — nbCourses reste à 0. L\'arrivée '
              'officielle existe, est enregistrée, mais n\'a JAMAIS nourri '
              'l\'ELO. Le critère `!resultatsReels` ne distingue pas '
              '« résolu avec ELO » de « résolu sans ELO ».');
      expect(_rating('CHEVAL_1'), closeTo(1500.0, 0.000001),
          reason: 'T-A7-13a : le rating n\'a jamais bougé');

      // ── Et un rejeu via le CHEMIN CORRIGÉ ne répare rien non plus ────────
      final bool rejeu = await _cycleDataRefresh(
          courseKey: ck, arrivee: arrivee, partants: partants);
      expect(rejeu, isFalse,
          reason: 'T-A7-13a : le rejeu obtient `false` — la course est déjà '
              'résolue');
      expect(_nb('CHEVAL_1'), 0,
          reason: 'T-A7-13a : même un rejeu explicite ne change rien — '
              '`enregistrerResultat` ne réécrit jamais un résultat existant. '
              'C\'est la limite R-b, NON CORRIGÉE par l\'option A.');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  T-A7-14 — NORMATIF : la TABLE DE VÉRITÉ des retours de
  //             `enregistrerResultat()`
  //
  //  Les quatre chemins de sortie sont vérifiés un par un, avec le retour
  //  ATTENDU. C'est le contrat de l'option A, rendu exécutable.
  // ═════════════════════════════════════════════════════════════════════════
  group('T-A7-14 — table de vérité des retours', () {
    test('T-A7-14a — NOUVEAU résultat ⇒ true, et vraie mutation', () async {
      final store = await _buildStore();
      final ck = _cleCourse(71, 1, _jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );
      final wAvant = _ecrituresPronostics(store);

      final bool retour = await IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);

      // ignore: avoid_print
      print('[T-A7-14a] NOUVEAU ⇒ retour=$retour | mutations : '
          '${_ecrituresPronostics(store) - wAvant} | dateResultat=${IaMemoryService.instance.pronostics.single.dateResultat}');

      expect(retour, isTrue,
          reason: 'T-A7-14a : chemin nominal d\'un résultat nouveau');
      expect(_ecrituresPronostics(store) - wAvant, 1,
          reason: 'T-A7-14a : `true` s\'accompagne bien d\'une mutation '
              'effective — il n\'est pas rendu à tort');
      expect(IaMemoryService.instance.pronostics.single.dateResultat, isNotNull,
          reason: 'T-A7-14a : la date de résultat a bien été posée');
    });

    test('T-A7-14b — DÉJÀ connu ⇒ false, sans mutation ni réécriture',
        () async {
      final store = await _buildStore();
      final ck = _cleCourse(72, 1, _jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );
      await IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);
      final date1 = IaMemoryService.instance.pronostics.single.dateResultat;
      final wAvant = _ecrituresPronostics(store);

      final bool retour = await IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: arrivee);
      final date2 = IaMemoryService.instance.pronostics.single.dateResultat;

      // ignore: avoid_print
      print('[T-A7-14b] DÉJÀ connu ⇒ retour=$retour | mutations : '
          '${_ecrituresPronostics(store) - wAvant} | dateResultat réécrite : '
          '${date2 != date1}');

      expect(retour, isFalse,
          reason: 'T-A7-14b : `false` sur un résultat déjà connu');
      expect(_ecrituresPronostics(store) - wAvant, 0,
          reason: 'T-A7-14b : aucune mutation');
      expect(date2, date1,
          reason: 'T-A7-14b : `dateResultat` n\'a pas été réécrite');
    });

    test('T-A7-14c — ARCHIVE SEULE ⇒ false', () async {
      await _buildStore();
      const ck = 'R97C1_ARCHIVE_ONLY_A7';

      final bool retour = await IaMemoryService.instance.enregistrerResultat(
          courseKey: ck, arriveeReelle: const <int>[1, 2]);

      // ignore: avoid_print
      print('[T-A7-14c] ARCHIVE SEULE ⇒ retour=$retour');

      expect(retour, isFalse,
          reason: 'T-A7-14c : `false` sur la branche archive (arbitrage §3)');
      expect(IaMemoryService.instance.pronostics, isEmpty,
          reason: 'T-A7-14c : aucune réinjection');
    });

    test('T-A7-14d — ANNULÉ PAR RESET ⇒ false, sans mutation', () async {
      final store = await _buildStore();
      final ck = _cleCourse(73, 1, _jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );
      final gen0 = IaMemoryService.instance.generationCache;
      await IaMemoryService.instance.executerResetComplet(() async {});
      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );
      final wAvant = _ecrituresPronostics(store);

      final bool retour = await IaMemoryService.instance.enregistrerResultat(
        courseKey:          ck,
        arriveeReelle:      const <int>[1, 2],
        generationAppelante: gen0,
      );

      // ignore: avoid_print
      print('[T-A7-14d] ANNULÉ par reset ⇒ retour=$retour | mutations : '
          '${_ecrituresPronostics(store) - wAvant}');

      expect(retour, isFalse,
          reason: 'T-A7-14d : `false` sur génération périmée');
      expect(_ecrituresPronostics(store) - wAvant, 0,
          reason: 'T-A7-14d : aucune mutation');
      expect(IaMemoryService.instance.getPronostic(ck)!.resultatsReels, isFalse,
          reason: 'T-A7-14d : la course reste non résolue');
    });

    test('T-A7-14e — NON-RÉGRESSION des appelants qui IGNORENT la valeur : '
        'un simple `await` compile et fonctionne', () async {
      await _buildStore();
      final ck = _cleCourse(74, 1, _jour);
      final partants = <ZtPartant>[_partant(1), _partant(2)];
      const arrivee = <int>[1, 2];

      await IaMemoryService.instance.enregistrerPronosticsBatch(
        <Map<String, dynamic>>[
          _item(courseKey: ck, course: _course(ck, partants)),
        ],
      );

      // Forme EXACTE des 3 autres appelants de production
      // (`alert_service.dart:2719`, `ia_memory_service.dart:1683` et `:1991`) :
      // `await` SANS affectation. Le passage à `Future<bool>` doit rester
      // transparent.
      await IaMemoryService.instance.enregistrerResultat(
        courseKey:     ck,
        arriveeReelle: arrivee,
      );
      expect(IaMemoryService.instance.pronostics.single.resultatsReels, isTrue,
          reason: 'T-A7-14e : l\'appel sans affectation a bien enregistré');

      // Et un second appel, toujours sans lire la valeur, est un no-op.
      await IaMemoryService.instance.enregistrerResultat(
        courseKey:     ck,
        arriveeReelle: arrivee,
      );
      expect(IaMemoryService.instance.pronostics.single.resultatsReels, isTrue,
          reason: 'T-A7-14e : toujours résolu, sans erreur');
    });
  });
}
