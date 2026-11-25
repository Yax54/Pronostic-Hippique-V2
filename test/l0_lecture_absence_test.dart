// ═══════════════════════════════════════════════════════════════════════════
//  L0 — LECTURE : ABSENCE ET CLÉS INVALIDES
//
//  A6 n° 2-a — preuve des deux branches `return null` d'`arrivee(courseKey)`
//  (arrivee_officielle_service.dart:593-599), qui n'étaient couvertes par
//  AUCUN test : mesure `grep -rn "arrivee('R9\|arrivee('CLE\|arrivee('')"`
//  sur test/ ne renvoyait rien.
//
//  CE QUE CE FICHIER PROUVE, ET RIEN DE PLUS :
//    L0-A1  une clé SYNTAXIQUEMENT VALIDE mais absente de L0 → `null`,
//           et aucune entrée n'apparaît dans le stockage après la lecture.
//    L0-A2  une clé invalide, une date impossible ou une clé vide → `null`,
//           et aucune entrée n'apparaît dans le stockage après la lecture.
//
//  CE QU'IL NE PROUVE PAS : rien sur les parseurs (P1..P5), rien sur le
//  chargement historique, rien sur l'apprentissage. `arrivee()` est une
//  lecture pure : ces tests ne font que constater ses sorties anticipées.
//
//  ⚠️ AUCUNE MODIFICATION DE PRODUCTION. `lib/services/arrivee_officielle_service.dart`
//  est INCHANGÉ : ce fichier ne fait que l'observer.
//
//  ── ISOLATION (exigence explicite du mandat) ──────────────────────────────
//  `ArriveeOfficielleService` est un SINGLETON (`:370-373`). Trois précautions,
//  toutes fondées sur des mécanismes EXISTANTS de production, aucune ajoutée :
//
//    1. `viderMemoireSeulement()` (`:1286-1287`, `@visibleForTesting`) vide
//       `_shards`, `_enAttente` et remet `_charge = false`. Aucun autre état
//       n'est réinitialisé.
//    2. Le store est REMPLACÉ par `StoreVide` avant chaque test puis
//       `SharedPreferences.resetStatic()`. Même si `_charge` repassait à
//       `true` par un appel de `charger()`, le disque vu par le service est
//       VIDE : aucune entrée d'un autre fichier de test ne peut être héritée.
//    3. Clés choisies HORS de toute fixture existante (voir L0-A1), pour
//       qu'un éventuel résidu d'un autre fichier ne puisse pas les remplir.
//
//  PREUVE D'ISOLATION (témoin de non-vacuité) : L0-A1 écrit une arrivée
//  CONNUE sur une clé de contrôle, prouve qu'elle est lisible, puis prouve
//  que la clé ABSENTE rend `null` sur le MÊME service chargé. Sans cela,
//  `null` pourrait simplement signifier « service vide » et ne rien prouver.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:pronostic_hippique/services/arrivee_officielle_service.dart';

// ───────────────────────────────────────────────────────────────────────────
//  Store en mémoire VIDE. Aucun semis possible : le disque vu par le
//  service ne peut contenir que ce que le test courant y écrit.
// ───────────────────────────────────────────────────────────────────────────
class StoreVide extends SharedPreferencesStorePlatform {
  final Map<String, Object> _valeurs = <String, Object>{};

  /// Clés réellement écrites (non préfixées). Sert à prouver qu'une LECTURE
  /// n'ajoute rien.
  final List<String> sets = <String>[];

  @override
  Future<bool> clear() async {
    _valeurs.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    final prefix = parameters.filter.prefix;
    return <String, Object>{
      for (final e in _valeurs.entries)
        if (e.key.startsWith(prefix)) e.key: e.value,
    };
  }

  @override
  Future<bool> remove(String key) async {
    _valeurs.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final nue = key.startsWith('flutter.') ? key.substring(8) : key;
    sets.add(nue);
    _valeurs[key] = value;
    return true;
  }

  // ── Helpers de mesure ───────────────────────────────────────────────────
  bool contient(String cle) => _valeurs.containsKey('flutter.$cle');

  /// Toutes les clés de shard mensuel présentes, triées.
  List<String> get clesArrivees => _valeurs.keys
      .where((k) => k.startsWith('flutter.$kArriveeStoragePrefix'))
      .toList()
    ..sort();

  /// Nombre d'écritures sur des clés de ce stockage.
  int get nbSetsArrivees =>
      sets.where((k) => k.startsWith(kArriveeStoragePrefix)).length;
}

late StoreVide storeVide;

void installerStoreVide() {
  storeVide = StoreVide();
  SharedPreferencesStorePlatform.instance = storeVide;
  SharedPreferences.resetStatic();
}

void main() {
  setUp(() {
    installerStoreVide();
    // Retire tout état RAM du singleton : sans cela, une entrée écrite par un
    // autre fichier de test resterait visible et fausserait la mesure.
    ArriveeOfficielleService.instance.viderMemoireSeulement();
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L0-A1 — Clé SYNTAXIQUEMENT VALIDE, mais ABSENTE de L0
  // ═════════════════════════════════════════════════════════════════════════
  test('L0-A1 clé valide absente de L0 : arrivee() rend null et n\'écrit rien',
      () async {
    final svc = ArriveeOfficielleService.instance;

    // ── TÉMOIN DE NON-VACUITÉ ────────────────────────────────────────────
    // On écrit d'abord une arrivée CONNUE sur une clé de contrôle, de la même
    // forme et du même mois que la clé absente. On prouve qu'elle est lisible,
    // puis on prouve que l'AUTRE clé rend `null`. Sans ce témoin, un `null`
    // pourrait simplement signifier « service vide » et ne rien démontrer.
    const cleControle = 'R7C3_15062025';
    const cleAbsente = 'R7C4_15062025'; // même mois, même jour, course 4
    final rangsControle = <List<int>>[
      [1], [5], [3]
    ];

    final e = ArriveeOfficielleService.depuisJsonCourse(
      <String, dynamic>{
        'statut': kStatutArriveeDefinitiveComplete,
        'isArriveeDefinitive': true,
        'arriveeDefinitive': true,
        'nombreDeclaresPartants': 12,
        'ordreArrivee': rangsControle,
      },
      courseKey: cleControle,
    );
    expect(e, isNotNull,
        reason: 'TÉMOIN : la fixture doit être acceptée par le service');
    debugPrint('L0-A1 entree construite=$e');

    final res = await svc.enregistrer(e!);
    debugPrint('L0-A1 res=$res');
    expect(res.succes, isTrue, reason: 'TÉMOIN : l\'écriture doit être confirmée');
    expect(storeVide.nbSetsArrivees, 1,
        reason: 'TÉMOIN : exactement une écriture de shard');

    // Rechargement depuis le disque : on mesure l'état réellement persisté,
    // pas seulement l'état RAM de la session d'écriture.
    svc.viderMemoireSeulement();
    await svc.charger();
    expect(svc.estCharge, isTrue, reason: 'TÉMOIN : les shards sont chargés');

    // ── TÉMOIN : la clé de contrôle est bien lisible ──────────────────────
    final temoin = svc.arrivee(cleControle);
    debugPrint('L0-A1 temoin($cleControle)=$temoin');
    expect(temoin, isNotNull,
        reason: 'TÉMOIN : le service est bien chargé et non vide');
    expect(temoin, equals(rangsControle),
        reason: 'TÉMOIN : contenu exact de la clé de contrôle');
    expect(svc.nbEntrees, 1, reason: 'TÉMOIN : une seule entrée en L0');

    // ── MESURE : la clé valide mais absente rend null ─────────────────────
    final obtenu = svc.arrivee(cleAbsente);
    debugPrint('L0-A1 arrivee($cleAbsente)=$obtenu');
    expect(obtenu, isNull,
        reason: 'une course valide mais absente de L0 doit rendre null');
    expect(svc.contient(cleAbsente), isFalse,
        reason: 'contient() doit suivre la même vérité');
    expect(svc.declares(cleAbsente), isNull,
        reason: 'aucune métadonnée ne doit être inventée');
    expect(svc.nbEntrees, 1,
        reason: 'la lecture ne doit pas créer d\'entrée');

    // ── Exigence du mandat : la LECTURE n'ajoute RIEN au stockage ─────────
    final clesAvant = List<String>.from(storeVide.clesArrivees);
    final setsAvant = storeVide.sets.length;

    for (var i = 0; i < 5; i++) {
      expect(svc.arrivee(cleAbsente), isNull, reason: 'lecture répétée $i');
    }
    expect(svc.arrivee('R7C5_15062025'), isNull);
    expect(svc.arrivee('R7C6_16062025'), isNull);

    expect(storeVide.clesArrivees, equals(clesAvant),
        reason: 'aucune clé de stockage ajoutée par les lectures');
    expect(storeVide.sets.length, setsAvant,
        reason: 'aucune écriture déclenchée par les lectures');
    expect(svc.nbEntrees, 1, reason: 'toujours une seule entrée après lecture');
    expect(svc.nbEnAttente, 0,
        reason: 'aucune lecture ne doit alimenter la file d\'attente');
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  L0-A2 — Clé INVALIDE, date IMPOSSIBLE, clé VIDE
  // ═════════════════════════════════════════════════════════════════════════
  test('L0-A2 clé invalide, date impossible ou clé vide : arrivee() rend null',
      () async {
    final svc = ArriveeOfficielleService.instance;

    // ── TÉMOIN DE NON-VACUITÉ ────────────────────────────────────────────
    // Les mêmes invalidités, comparées à une clé VALIDE du MÊME service.
    const cleValide = 'R2C1_03042025';
    final rangsValide = <List<int>>[
      [4, 7], [2]
    ];

    final e = ArriveeOfficielleService.depuisJsonCourse(
      <String, dynamic>{
        'statut': kStatutArriveeDefinitiveComplete,
        'isArriveeDefinitive': true,
        'arriveeDefinitive': true,
        'nombreDeclaresPartants': 9,
        'ordreArrivee': rangsValide,
      },
      courseKey: cleValide,
    );
    expect(e, isNotNull, reason: 'TÉMOIN : la fixture valide est acceptée');
    final res = await svc.enregistrer(e!);
    expect(res.succes, isTrue, reason: 'TÉMOIN : écriture confirmée');

    svc.viderMemoireSeulement();
    await svc.charger();

    // TÉMOIN : la clé valide est lisible, avec ses ex æquo intacts.
    expect(svc.arrivee(cleValide), equals(rangsValide),
        reason: 'TÉMOIN : le service répond correctement sur une clé valide');

    // ── CAS INVALIDES, chacun avec sa justification ───────────────────────
    final cas = <String, String>{
      '': 'clé vide',
      'CLE_BIDON': 'aucun motif R{n}C{n}_date',
      'R1C1': 'aucune date',
      'R1C1_': 'date absente après le séparateur',
      'R1C1_31022026':
          '31 février : impossible (rejeté par le contrôle aller-retour)',
      'R1C1_29022025':
          '29 février 2025 : année non bissextile',
      'R1C1_32012026': '32 janvier : jour hors bornes',
      'R1C1_00122026': '0 décembre : jour hors bornes',
      'R1C1_01132026': 'mois 13 : hors bornes',
      'R1C1_abcdefgh': 'date non numérique',
      'R1C1_2026-13-05': 'ISO au mois 13 : hors bornes',
      'R1C1_2026-02-30': 'ISO au 30 février : impossible',
      'R9C9_0101202': 'date tronquée (7 chiffres)',
    };

    for (final entree in cas.entries) {
      final cle = entree.key;
      final obtenu = svc.arrivee(cle);
      debugPrint('L0-A2 arrivee("$cle")=$obtenu  // ${entree.value}');
      expect(obtenu, isNull, reason: '"$cle" — ${entree.value}');
      expect(moisDepuisCourseKey(cle), isNull,
          reason: 'TÉMOIN de cause : "$cle" doit être sans mois exploitable');
    }

    // ── TÉMOIN CROISÉ : sur les MÊMES clés, le motif est bien la cause ────
    // Si `moisDepuisCourseKey` acceptait l'une de ces clés, ce serait cette
    // fonction qui serait fausse, et le test ci-dessus ne prouverait rien sur
    // `arrivee()`. On vérifie donc la cause ET l'effet.
    expect(moisDepuisCourseKey(cleValide), equals('2025-04'),
        reason: 'TÉMOIN : une clé valide produit bien un mois');

    // ── Exigence du mandat : aucune écriture pendant ces lectures ─────────
    final setsAvant = storeVide.sets.length;
    final clesAvant = List<String>.from(storeVide.clesArrivees);

    for (final cle in cas.keys) {
      svc.arrivee(cle);
    }

    expect(storeVide.sets.length, setsAvant,
        reason: 'aucune écriture déclenchée par des clés invalides');
    expect(storeVide.clesArrivees, equals(clesAvant),
        reason: 'aucune clé de shard ajoutée');
    expect(svc.nbEntrees, 1,
        reason: 'l\'unique entrée valide subsiste, aucune autre créée');
    expect(svc.nbEnAttente, 0,
        reason: 'aucune clé invalide ne doit alimenter la file d\'attente');

    // Le témoin final : la clé valide est TOUJOURS lisible après tout ça.
    expect(svc.arrivee(cleValide), equals(rangsValide),
        reason: 'TÉMOIN FINAL : les lectures invalides n\'ont rien altéré');
  });
}
