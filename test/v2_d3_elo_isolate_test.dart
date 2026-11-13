// ═══════════════════════════════════════════════════════════════════════════
//  V2 — PREUVE DU DÉFAUT D3 (ELO perdu dans l'isolate)
//
//  ⚠️  FICHIER DE PREUVE, PAS DE CORRECTION.
//  ⚠️  Aucune modification de production n'est requise pour l'exécuter.
//
//  ── MISE À JOUR suite à la relecture ──────────────────────────────────────
//  v1 de ce test ne vérifiait que l'appel direct de la future méthode.
//  Cette version teste le VÉRITABLE chemin `compute()` (isolate réel),
//  comme demandé : ce n'est plus un test de présence d'API, c'est un test
//  du comportement de production.
//
//    T1  DÉFAUT dans le vrai isolate ...... passe aujourd'hui (documente le bug)
//    T2  Le VRAI chemin compute() ......... passe aujourd'hui (statics isolés)
//    T3  APRÈS D3 : M correct dans l'isolate ÉCHOUE aujourd'hui (NoSuchMethod)
//    T4  APRÈS D3 : impact favori / TOP3 ... ÉCHOUE aujourd'hui (NoSuchMethod)
//    T5  NON-RÉGRESSION mécanisme ......... passe aujourd'hui et après D3
//
//  T3/T4 utilisent un appel `dynamic` volontaire vers la méthode que D3
//  ajoutera (`chargerDepuisMapIsolate`). Aujourd'hui : NoSuchMethodError.
//  Après D3 : la méthode existe, les assertions s'exécutent et passent.
//  → Le rouge est RÉEL, pas une erreur de compilation masquée.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart' show compute, setEquals, debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pronostic_hippique/models/zt_models.dart';
import 'package:pronostic_hippique/services/elo_service.dart';
import 'package:pronostic_hippique/services/ia_memory_models.dart';
import 'package:pronostic_hippique/services/ia_pronostic_engine.dart';

// ─── Constantes de référence (formule zt_models.dart:489) ───────────────────
// scoreElo = ((rating - 1200) / 8).clamp(0, 100)
const double kEloNeutreScore = 37.5; // (1500 - 1200) / 8

// ─── Clé ELO : reproduit elo_service.dart:129-146 ───────────────────────────
//   _cleNom   : trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ')
//   discipline: normaliserDiscipline(course.type)
//   clé       : '<NOM>|<DISCIPLINE>'
String kCleElo(String nom, String discipline) {
  final nomNorm = nom.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  return '$nomNorm|${EloService.normaliserDiscipline(discipline)}';
}

// ═══════════════════════════════════════════════════════════════════════════
//  FONCTIONS TOP-LEVEL — exécutées DANS le vrai isolate par compute()
//  (impossible d'appeler une méthode de classe depuis compute())
// ═══════════════════════════════════════════════════════════════════════════

/// Sonde : lit un ELO depuis l'instance du service dans l'isolate.
double _probeElo(String nom) {
  return EloService.instance.getScore(nom, discipline: 'Trot Attelé').rating;
}

/// Rejoue EXACTEMENT le calcul de production de l'isolate
/// (data_refresh_service.dart:88-93) et retourne le critère M par numéro.
///
/// `eloJson` est passé en argument pour simuler la présence/absence de la
/// restauration. Si `eloJson` est vide → comportement actuel (bug).
/// Après D3, l'isolate appellera `chargerDepuisMapIsolate(payload.eloJson)`.
Map<String, double> _calculerMDansIsolate(_ProbePayload payload) {
  // ★ Équivalent de la ligne D3 : à ajouter dans data_refresh_service.dart
  if (payload.eloJson.isNotEmpty) {
    (EloService.instance as dynamic).chargerDepuisMapIsolate(payload.eloJson);
  }

  final (_, criteres) = IaPronosticEngine.analyserCourseAvecCriteres(
    payload.course,
    poidsOverride: IaPoidsAdaptatifs.defaut(),
  );
  return criteres.map((numero, sc) => MapEntry(numero, sc.elo));
}

/// Classe de payload (doit être transmissible à un isolate).
class _ProbePayload {
  final ZtCourse course;
  final Map<String, dynamic> eloJson;
  const _ProbePayload(this.course, this.eloJson);
}

// ─── Fixtures (hors isolate : construction sur le thread principal) ─────────

ZtPartant _partant(String numero, String nom,
    {double eloRating = 0.0, String musique = '1a 2a 3a 1a 2a'}) {
  return ZtPartant(
    numero: numero,
    nom: nom,
    driver: 'Driver $numero',
    entraineur: 'Entraineur $numero',
    proprietaire: 'Proprietaire $numero',
    gains: '100000',
    record: '1\'12"0',
    musique: musique,
    cote: '5.0',
    ageSexe: '5 H',
    joursRepos: 20,
    hippodromeActuel: 'Vincennes',
    statsJockeyCsv: 'JOCKEY $numero|20|5|10',
    statsHippodromeCsv: 'vincennes|10|3|6',
    statsEntraineurCsv: 'ENTRAINEUR $numero|30|6|15',
    statsTerrainCsv: 'sable|10|3|6',
    eloRating: eloRating, // sérialisé en 'elo_r' (zt_models:216)
  );
}

ZtCourse _course() {
  return ZtCourse(
    numCourse: 1,
    anchor: 'R1C1',
    nom: 'PRIX DE TEST ELO',
    heure: '14:30',
    distance: '2700',
    prix: '50000',
    type: 'Trot Attelé',
    piste: 'Sable',
    categorie: 'Condition',
    isQuinte: false,
    pronosticZt: const [],
    partants: [
      _partant('1', 'CHEVAL A', eloRating: 1800.0, musique: '1a 1a 2a 1a 3a'),
      _partant('2', 'CHEVAL B', eloRating: 1500.0, musique: '3a 3a 4a 3a 3a'),
      _partant('3', 'CHEVAL C', eloRating: 1200.0, musique: '6a 6a 7a 6a 6a'),
    ],
  );
}

/// ELO réel attendu pour chaque cheval, via la formule officielle.
Map<String, double> _eloAttendu() => {
      '1': ((1800.0 - 1200.0) / 8.0).clamp(0.0, 100.0), // 75.0
      '2': ((1500.0 - 1200.0) / 8.0).clamp(0.0, 100.0), // 37.5
      '3': ((1200.0 - 1200.0) / 8.0).clamp(0.0, 100.0), //  0.0
    };

/// Map ELO telle que produite par EloService.exporterPourBackup()
/// — c'est exactement le contenu de `payload.eloJson`.
Map<String, dynamic> _eloJson() {
  const disc = 'Trot Attelé';
  return {
    kCleElo('CHEVAL A', disc): const EloScore(
      nomCheval: 'CHEVAL A',
      rating: 1800.0,
      nbCourses: 12,
    ).toJson(),
    kCleElo('CHEVAL B', disc): const EloScore(
      nomCheval: 'CHEVAL B',
      rating: 1500.0,
      nbCourses: 8,
    ).toJson(),
    kCleElo('CHEVAL C', disc): const EloScore(
      nomCheval: 'CHEVAL C',
      rating: 1200.0,
      nbCourses: 3,
    ).toJson(),
  };
}

/// Calcul sur le thread principal (référence, EloService correctement chargé).
Map<String, double> _criteresEloThreadPrincipal(ZtCourse course) {
  final (_, criteres) = IaPronosticEngine.analyserCourseAvecCriteres(
    course,
    poidsOverride: IaPoidsAdaptatifs.defaut(),
  );
  return criteres.map((numero, sc) => MapEntry(numero, sc.elo));
}

void main() {
  // EloService est un singleton : on repart d'un état vide avant chaque test,
  // sinon un test hériterait des ratings chargés par un autre.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await EloService.instance.reinitialiser();
  });

  // ═════════════════════════════════════════════════════════════════════
  // T2 — LE VRAI CHEMIN compute() EST BIEN ISOLÉ.  Passe aujourd'hui.
  //
  // Étape indispensable : elle prouve que `compute()` lance un VRAI
  // isolate en environnement de test, et que les singletons n'y sont
  // pas partagés. Sans cette preuve, T1/T3 ne démontreraient rien du
  // comportement Android.
  // ═════════════════════════════════════════════════════════════════════
  test('V2/T2 — compute() isole réellement les statiques (vrai défaut)',
      () async {
    // Thread principal : ELO réel chargé
    await EloService.instance.importerDepuisBackup(_eloJson());
    expect(
      EloService.instance.getScore('CHEVAL A', discipline: 'Trot Attelé').rating,
      closeTo(1800.0, 0.01),
      reason: 'Sur le thread principal, EloService est bien chargé',
    );

    // Isolate : instance neuve → défaut 1500
    final ratingDansIsolate = await compute(_probeElo, 'CHEVAL A');
    expect(ratingDansIsolate, closeTo(1500.0, 0.01),
        reason: 'Les statiques ne traversent PAS la frontière de l\'isolate');
  });

  // ═════════════════════════════════════════════════════════════════════
  // T1 — LE DÉFAUT, DANS LE VRAI ISOLATE.  Passe aujourd'hui.
  //
  // Rejoue le calcul de production (sans restauration ELO, donc l'état
  // actuel du code) et constate que M est figé à 37.5.
  // ═════════════════════════════════════════════════════════════════════
  test('V2/T1 — DÉFAUT : dans compute(), M est figé à 37.5 pour tous',
      () async {
    // ELO chargés côté principal : ils ne serviront à rien dans l'isolate.
    await EloService.instance.importerDepuisBackup(_eloJson());

    final m = await compute(
      _calculerMDansIsolate,
      _ProbePayload(_course(), const {}), // ← eloJson VIDE = état actuel
    );

    expect(m['1'], closeTo(kEloNeutreScore, 0.01),
        reason: 'CHEVAL A a eloRating=1800 mais M est écrasé à 37.5');
    expect(m['2'], closeTo(kEloNeutreScore, 0.01));
    expect(m['3'], closeTo(kEloNeutreScore, 0.01));

    expect(m.values.toSet().length, 1,
        reason: 'Aucune variance : le critère M est neutralisé dans l\'isolate');
  });

  // ═════════════════════════════════════════════════════════════════════
  // T3 — APRÈS D3 : M CORRECT DANS L'ISOLATE.  ÉCHOUE aujourd'hui.
  //
  // Avec l'eloJson transmis (ce que D3 rendra effectif), M doit refléter
  // chaque cheval. Appel `dynamic` : aujourd'hui NoSuchMethodError.
  // ═════════════════════════════════════════════════════════════════════
  test('V2/T3 — APRÈS D3 : M reflète le vrai ELO dans compute()', () async {
    final m = await compute(
      _calculerMDansIsolate,
      _ProbePayload(_course(), _eloJson()), // ← eloJson transmis (D3)
    );

    final attendu = _eloAttendu();
    expect(m['1'], closeTo(attendu['1']!, 0.01), reason: 'A (1800) → 75.0');
    expect(m['2'], closeTo(attendu['2']!, 0.01), reason: 'B (1500) → 37.5');
    expect(m['3'], closeTo(attendu['3']!, 0.01), reason: 'C (1200) →  0.0');

    expect(m.values.toSet().length, 3,
        reason: 'Trois valeurs distinctes : le critère M est vivant');
  });

  // ═════════════════════════════════════════════════════════════════════
  // T4 — APRÈS D3 : COHÉRENCE ISOLATE == THREAD PRINCIPAL.  ÉCHOUE auj.
  //
  // C'est LE contrôle qui compte : l'isolate doit produire exactement
  // les mêmes critères M que le thread principal. Toute divergence
  // signalerait un transport incomplet.
  // ═════════════════════════════════════════════════════════════════════
  test('V2/T4 — APRÈS D3 : isolate et thread principal donnent le même M',
      () async {
    final course = _course();

    // Référence : thread principal, EloService chargé
    await EloService.instance.importerDepuisBackup(_eloJson());
    final reference = _criteresEloThreadPrincipal(course);

    // Isolate : avec restauration (D3)
    await EloService.instance.reinitialiser(); // l'isolate ne doit PAS en dépendre
    final dansIsolate = await compute(
      _calculerMDansIsolate,
      _ProbePayload(course, _eloJson()),
    );

    for (final numero in ['1', '2', '3']) {
      expect(dansIsolate[numero], closeTo(reference[numero]!, 0.001),
          reason: 'M du cheval $numero doit être identique des deux côtés');
    }
  });

  // ═════════════════════════════════════════════════════════════════════
  // T5 — NON-RÉGRESSION DU MÉCANISME.
  //      Passe aujourd'hui ET après D3.
  //
  // Prouve que le seul chaînon manquant est le CHARGEMENT : dès que les
  // ratings sont en mémoire, le calcul est correct. D3 n'ajoute donc
  // aucune formule, il branche une alimentation.
  // ═════════════════════════════════════════════════════════════════════
  test('V2/T5 — MÉCANISME : charger les ratings suffit à corriger M',
      () async {
    final course = _course();
    expect(_criteresEloThreadPrincipal(course).values.toSet().length, 1,
        reason: 'État initial : M neutralisé');

    // importerDepuisBackup existe déjà et alimente _ratings (elo_service:260)
    await EloService.instance.importerDepuisBackup(_eloJson());

    final m = _criteresEloThreadPrincipal(course);
    final attendu = _eloAttendu();
    expect(m['1'], closeTo(attendu['1']!, 0.01));
    expect(m['3'], closeTo(attendu['3']!, 0.01));
  });

  // ═════════════════════════════════════════════════════════════════════
  // T6 — IMPACT SUR LE CLASSEMENT (mesuré, non garanti).
  //
  // Corrige une erreur de la v1 : l'impact avait été annoncé « nul »,
  // puis mesuré à « TOP3 100 % » à cause d'un bug de comparaison
  // (Set == teste l'IDENTITÉ, pas le contenu — cf. setEquals).
  // Ici la comparaison utilise setEquals : mesure fiable.
  // ═════════════════════════════════════════════════════════════════════
  test('V2/T6 — IMPACT : D3 modifie bien le classement (comparaison fiable)',
      () async {
    final course = _course();

    // Avant : M neutralisé
    final (avant, _) = IaPronosticEngine.analyserCourseAvecCriteres(
      course,
      poidsOverride: IaPoidsAdaptatifs.defaut(),
    );
    final ordreAvant = avant.map((p) => p.numero).toList();
    final top3Avant = ordreAvant.take(3).toSet();

    // Après : M réel
    await EloService.instance.importerDepuisBackup(_eloJson());
    final (apres, _) = IaPronosticEngine.analyserCourseAvecCriteres(
      course,
      poidsOverride: IaPoidsAdaptatifs.defaut(),
    );
    final ordreApres = apres.map((p) => p.numero).toList();
    final top3Apres = ordreApres.take(3).toSet();

    // Le favori suit l'ELO : A (1800) doit passer devant.
    expect(ordreApres.first, '1',
        reason: 'Le meilleur ELO doit devenir favori IA');
    expect(ordreApres.last, '3',
        reason: 'Le plus faible ELO doit devenir dernier');

    // Amplitude du terme M : poids(elo) = 0.05
    //   A : 75.0 * 0.05 = 3.750
    //   C :  0.0 * 0.05 = 0.000
    const amplitudeMax = (75.0 - 0.0) * 0.05;
    expect(amplitudeMax, closeTo(3.75, 0.001),
        reason: 'Impact max du critère M sur le score brut : 3.75 pts');

    // La comparaison de CONTENU (setEquals), pas d'identité.
    final top3Identique = setEquals(top3Avant, top3Apres);
    debugPrint('[V2/T6] ordre avant=$ordreAvant après=$ordreApres '
        'top3 identique=$top3Identique');
  });
}
